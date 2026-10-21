#region winget
function Get-UTWingetPath {
    <#
    .SYNOPSIS
        winget.exe: the App Installer alias of the current user, or the package folder itself
        (when UAC was approved with another admin account the alias may not exist).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $cmd = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $alias) { return $alias }
    $pkg = @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'WindowsApps') -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'winget.exe' } | Where-Object { Test-Path -LiteralPath $_ })
    if ($pkg.Count -gt 0) { return $pkg[0] }
    return $null
}

function Invoke-UTWinget {
    <#
    .SYNOPSIS
        Runs winget without prompts. Every call accepts the source agreements (needed on the
        first run) and never waits for input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Argumentos,
        [int]$TimeoutSeconds = 300
    )
    $exe = Get-UTWingetPath
    if (-not $exe) { throw 'O winget (Instalador de Aplicativo) não está instalado. Use "Instalar winget" na aba Programas ou instale o "Instalador de Aplicativo" pela Microsoft Store.' }
    $all = @($Argumentos) + @('--accept-source-agreements', '--disable-interactivity')
    return (Invoke-UTNative -FilePath $exe -ArgumentList $all -TimeoutSeconds $TimeoutSeconds)
}

function Get-UTWingetMessage {
    <#
    .SYNOPSIS
        PT-BR text for the winget exit codes that matter to the user.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int64]$Codigo)
    $known = @{
        0           = 'Concluído.'
        -1978335212 = 'Programa não encontrado (nem instalado nem no catálogo do winget).'
        -1978335189 = 'Já está na versão mais nova.'
        -1978335135 = 'O programa já está instalado.'
        -1978334975 = 'O programa está aberto. Feche-o e tente de novo.'
        -1978334974 = 'Outra instalação está em andamento. Espere terminar e tente de novo.'
        -1978334967 = 'Instalado. Reinicie o PC para terminar.'
    }
    # Exit codes can arrive as unsigned (0x8A15....); winget documents them as HRESULTs.
    $key = $Codigo
    if ($key -gt [int32]::MaxValue) { $key -= 4294967296 }
    if ($known.ContainsKey([int]$key)) { return $known[[int]$key] }
    return ('O winget terminou com o código 0x{0:X8}.' -f ($key -band [int64]4294967295))
}

function ConvertFrom-UTWingetLine {
    <#
    .SYNOPSIS
        Clean lines of winget output: removes the spinner/progress that winget writes with
        carriage returns and keeps the last state of each line.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowEmptyString()][string]$Saida)
    if (-not $Saida) { return @() }
    $lines = foreach ($raw in ($Saida -split "`n")) {
        $last = @($raw -split "`r" | Where-Object { $_.Trim() -ne '' })
        if ($last.Count -gt 0) { $last[-1].TrimEnd() }
    }
    return @($lines)
}

function Get-UTWingetRow {
    <#
    .SYNOPSIS
        Reads the row of one package from a "winget list" / "winget upgrade" table. Instead of
        column positions (they move with localized headers and long names), it finds the exact
        id and reads what comes after it: version, [available], source.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Saida,
        [Parameter(Mandatory)][string]$Id
    )
    # Greedy prefix: the last occurrence is the Id column even when the name contains the id.
    $pattern = '(?i)^.*(?:^|\s)' + [regex]::Escape($Id) + '\s+(?<resto>.+)$'
    foreach ($line in (ConvertFrom-UTWingetLine -Saida $Saida)) {
        $m = [regex]::Match($line, $pattern)
        if (-not $m.Success) { continue }
        $tokens = New-Object System.Collections.Generic.List[string]
        $parts = @($m.Groups['resto'].Value.Trim() -split '\s+')
        for ($i = 0; $i -lt $parts.Count; $i++) {
            # "< 2.0" / "> 1.5" are one value split in two
            if ($parts[$i] -in '<', '>' -and $i + 1 -lt $parts.Count) { $tokens.Add($parts[$i] + ' ' + $parts[$i + 1]); $i++ } else { $tokens.Add($parts[$i]) }
        }
        # After the Id come at most version, available and source; more means it matched the name.
        if ($tokens.Count -lt 1 -or $tokens.Count -gt 3) { continue }
        $available = $null
        $source = $null
        if ($tokens.Count -ge 3) { $available = $tokens[1]; $source = $tokens[2] }
        elseif ($tokens.Count -eq 2) { $source = $tokens[1] }
        return [pscustomobject]@{ Id = $Id; Versao = $tokens[0]; Disponivel = $available; Origem = $source }
    }
    return $null
}

function Get-UTWingetInstalled {
    <#
    .SYNOPSIS
        Installed packages that winget knows, as a hashtable id -> version, from one
        "winget export" (JSON, nothing to parse by column).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $file = Join-Path (Get-UTPath -Name Temp) ('winget-' + [guid]::NewGuid().ToString('N') + '.json')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
    $result = @{}
    try {
        [void](Invoke-UTWinget -Argumentos @('export', '-o', $file, '--include-versions') -TimeoutSeconds 180)
        if (-not (Test-Path -LiteralPath $file)) { return $result }
        $data = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($src in @($data.Sources)) {
            foreach ($p in @($src.Packages)) { $result[[string]$p.PackageIdentifier] = [string]$p.Version }
        }
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    return $result
}

function Get-UTWingetUpgrade {
    <#
    .SYNOPSIS
        Available updates for the given ids (hashtable id -> new version), from one
        "winget upgrade" call.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Ids)
    $result = @{}
    if (@($Ids).Count -eq 0) { return $result }
    $r = Invoke-UTWinget -Argumentos @('upgrade', '--include-unknown') -TimeoutSeconds 180
    foreach ($id in $Ids) {
        $row = Get-UTWingetRow -Saida $r.Saida -Id $id
        if ($row -and $row.Disponivel) { $result[$id] = $row.Disponivel }
    }
    return $result
}

function Open-UTWingetStorePage {
    <#
    .SYNOPSIS
        winget comes with the "App Installer" from the Microsoft Store.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Microsoft Store', 'Abrir o Instalador de Aplicativo (winget)')) { Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' }
}
#endregion

#region GitHub releases and downloads
function Get-UTGitHubLatestRelease {
    <#
    .SYNOPSIS
        Latest release of a GitHub project (tag and assets) through the public API.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repo)
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $r = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'UpgradeTweaks'; 'Accept' = 'application/vnd.github+json' } -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    } catch {
        throw "Não foi possível consultar a última versão no GitHub ($Repo). Confira a internet e tente de novo."
    }
    return [pscustomobject]@{
        Versao  = ([string]$r.tag_name).TrimStart('v', 'V')
        Pagina  = [string]$r.html_url
        Arquivos = @($r.assets | ForEach-Object { [pscustomobject]@{ Nome = [string]$_.name; Url = [string]$_.browser_download_url; TamanhoMB = [math]::Round([double]$_.size / 1MB, 1) } })
    }
}

function Save-UTDownload {
    <#
    .SYNOPSIS
        Downloads one file (HTTPS only) to the given path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destino
    )
    if ($Url -notmatch '^https://') { throw "Download recusado: só são aceitos endereços https ($Url)." }
    if (-not $PSCmdlet.ShouldProcess($Url, "Baixar para $Destino")) { return $null }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destino) | Out-Null
    $old = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing -Headers @{ 'User-Agent' = 'UpgradeTweaks' } -TimeoutSec 600 -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $Destino -Force -ErrorAction SilentlyContinue
        throw "O download falhou: $Url"
    } finally {
        $ProgressPreference = $old
    }
    return $Destino
}
#endregion
