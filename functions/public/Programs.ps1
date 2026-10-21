# "Programas" tab: third-party tools from config\programs.json. winget first; otherwise the
# latest GitHub release of the project; programs without an official channel only open their
# page. Programs always start elevated (the Upgrade Tweaks process already is).

#region Catalog and lookup
function Get-UTProgramCatalog {
    <#
    .SYNOPSIS
        Programs of the catalog, optionally only the ones that make sense for this PC (an AMD
        tool is hidden on Intel, NVIDIA tools without an NVIDIA card).
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [switch]$SoCompativeis,
        [psobject]$Contexto
    )
    $all = @((Get-UTConfig -Name 'programs').programas)
    if ($Id) {
        $p = @($all | Where-Object { $_.id -eq $Id })
        if ($p.Count -eq 0) { throw "Programa '$Id' não existe no catálogo." }
        return $p[0]
    }
    if (-not $SoCompativeis) { return $all }
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    foreach ($p in $all) {
        if ($p.cpu -and $Contexto.CpuFabricante -and @($p.cpu) -notcontains $Contexto.CpuFabricante) { continue }
        if ($p.gpu -and @(@($p.gpu) | Where-Object { @($Contexto.GpuFabricantes) -contains $_ }).Count -eq 0) { continue }
        $p
    }
}

function Expand-UTProgramFolder {
    <#
    .SYNOPSIS
        Expands %VARIABLES% and * of a catalog folder into existing folders.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Pasta)
    $expanded = [Environment]::ExpandEnvironmentVariables($Pasta)
    if ($expanded -match '%') { return @() }
    if ($expanded -match '\*') { return @(Get-ChildItem -Path $expanded -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    if (Test-Path -LiteralPath $expanded -PathType Container) { return @($expanded) }
    return @()
}

function Find-UTProgramExecutable {
    <#
    .SYNOPSIS
        Where the program's .exe is: catalog folders, the Upgrade Tweaks tools folder (GitHub
        downloads), winget links and portable packages, and the App Paths registry.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Programa)
    $names = @($Programa.executaveis | Where-Object { $_ })
    if ($names.Count -eq 0) { return $null }

    $folders = New-Object System.Collections.Generic.List[string]
    foreach ($f in @($Programa.pastas)) { if ($f) { foreach ($e in (Expand-UTProgramFolder -Pasta $f)) { $folders.Add($e) } } }
    $tool = Join-Path (Get-UTPath -Name Tools) $Programa.id
    if (Test-Path -LiteralPath $tool) { $folders.Add($tool) }
    foreach ($links in "$env:LOCALAPPDATA\Microsoft\WinGet\Links", "$env:ProgramFiles\WinGet\Links") { if (Test-Path -LiteralPath $links) { $folders.Add($links) } }

    foreach ($dir in $folders) {
        foreach ($n in $names) {
            $direct = Join-Path $dir $n
            if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
        }
    }
    # Downloads of the tools folder can have a version subfolder (zip with a folder inside).
    if (Test-Path -LiteralPath $tool) {
        foreach ($n in $names) {
            $hit = Get-ChildItem -LiteralPath $tool -Filter $n -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    if (Get-UTField $Programa 'winget') {
        foreach ($root in "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:ProgramFiles\WinGet\Packages") {
            foreach ($pkg in @(Get-ChildItem -Path (Join-Path $root ($Programa.winget + '_*')) -Directory -ErrorAction SilentlyContinue)) {
                foreach ($n in $names) {
                    $hit = Get-ChildItem -LiteralPath $pkg.FullName -Filter $n -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($hit) { return $hit.FullName }
                }
            }
        }
    }
    foreach ($n in $names) {
        $app = Get-UTRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$n" -Name ''
        if ($app.ValorExiste -and $app.Valor) {
            $path = ([string]$app.Valor).Trim('"')
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }
    return $null
}

function Get-UTToolVersionFile {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Id)
    return (Join-Path (Join-Path (Get-UTPath -Name Tools) $Id) '.versao-upgradetweaks')
}
#endregion

#region Status
function Get-UTProgramStatus {
    <#
    .SYNOPSIS
        One line per program for the tab: where it comes from (link), installed or not,
        installed version and, with -VerificarAtualizacao, whether there is a newer one.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Id,
        [switch]$VerificarAtualizacao,
        [psobject]$Contexto
    )
    $programs = @(Get-UTProgramCatalog -SoCompativeis -Contexto $Contexto)
    if ($Id) { $programs = @($programs | Where-Object { $Id -contains $_.id }) }

    $hasWinget = [bool](Get-UTWingetPath)
    $installed = @{}
    if ($hasWinget -and @($programs | Where-Object { $_.winget }).Count -gt 0) {
        try { $installed = Get-UTWingetInstalled } catch { Write-UTLog -Level Aviso -Message 'Não foi possível ler os programas instalados pelo winget.' -Detalhe $_.Exception.Message }
    }
    $upgrades = @{}
    if ($VerificarAtualizacao -and $hasWinget) {
        $ids = @($programs | Where-Object { $_.winget -and $installed.ContainsKey($_.winget) } | ForEach-Object { [string]$_.winget })
        try { $upgrades = Get-UTWingetUpgrade -Ids $ids } catch { Write-UTLog -Level Aviso -Message 'Não foi possível procurar atualizações pelo winget.' -Detalhe $_.Exception.Message }
    }

    foreach ($p in $programs) {
        $exe = Find-UTProgramExecutable -Programa $p
        $version = $null
        $available = $null
        $source = 'Página oficial'
        if ($p.winget -and $installed.ContainsKey($p.winget)) {
            $version = $installed[$p.winget]
            $source = "winget ($($p.winget))"
            if ($upgrades.ContainsKey($p.winget)) { $available = $upgrades[$p.winget] }
        } elseif ($p.github -and (Test-Path -LiteralPath (Get-UTToolVersionFile -Id $p.id))) {
            $version = (Get-Content -LiteralPath (Get-UTToolVersionFile -Id $p.id) -Raw).Trim()
            $source = "GitHub ($($p.github.repo))"
            if ($VerificarAtualizacao) {
                try {
                    $latest = Get-UTGitHubLatestRelease -Repo $p.github.repo
                    if ($latest.Versao -and $latest.Versao -ne $version) { $available = $latest.Versao }
                } catch { Write-UTLog -Level Aviso -Message $_.Exception.Message }
            }
        } elseif ($p.winget) {
            $source = "winget ($($p.winget))"
        } elseif ($p.github) {
            $source = "GitHub ($($p.github.repo))"
        }
        if (-not $version -and $exe) {
            try { $version = [string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion } catch { $version = $null }
        }
        [pscustomobject]@{
            Id                   = [string]$p.id
            Nome                 = [string]$p.nome
            Categoria            = [string]$p.categoria
            Descricao            = [string]$p.descricao
            Aviso                = [string]$p.aviso
            Site                 = [string]$p.site
            Origem               = $source
            SomentePagina        = [bool]$p.somentePagina
            Instalado            = [bool]($exe -or $version)
            Executavel           = $exe
            Versao               = $version
            VersaoDisponivel     = $available
            AtualizacaoDisponivel = [bool]$available
            PodeInstalar         = (-not $p.somentePagina) -and (($p.winget -and $hasWinget) -or [bool]$p.github)
        }
    }
}
#endregion

#region Install / update / uninstall / start
function Install-UTProgram {
    <#
    .SYNOPSIS
        Installs through winget (exact id, silent); when winget is missing or fails and the
        program has a GitHub project, downloads the latest release instead. Programs without an
        official channel only open their page.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    Assert-UTAdmin
    $p = Get-UTProgramCatalog -Id $Id
    if ($p.somentePagina) {
        Open-UTProgramPage -Id $Id
        return [pscustomobject]@{ Id = $Id; Status = 'Pagina'; Mensagem = "$($p.nome) não tem instalação automática; a página oficial foi aberta." }
    }
    $wingetError = $null
    if ($p.winget -and (Get-UTWingetPath)) {
        if (-not $PSCmdlet.ShouldProcess($p.nome, "winget install --id $($p.winget)")) { return [pscustomobject]@{ Id = $Id; Status = 'Simulado'; Mensagem = "winget install --id $($p.winget) -e" } }
        $r = Invoke-UTWinget -Argumentos @('install', '--id', $p.winget, '-e', '--silent', '--source', 'winget', '--accept-package-agreements') -TimeoutSeconds 1800
        $msg = Get-UTWingetMessage -Codigo $r.CodigoSaida
        if ($r.CodigoSaida -in 0, -1978335135, -1978334967) {
            Write-UTLog -Level Sucesso -Message "$($p.nome): $msg"
            return [pscustomobject]@{ Id = $Id; Status = 'Instalado'; Mensagem = $msg }
        }
        $wingetError = $msg
        Write-UTLog -Level Aviso -Message "$($p.nome): $msg" -Detalhe $r.Saida
    }
    if ($p.github) {
        $done = Install-UTProgramFromGitHub -Programa $p
        if ($done) { return $done }
    }
    if ($wingetError) { throw "$($p.nome): $wingetError" }
    throw "$($p.nome): o winget não está disponível neste PC. Instale o Instalador de Aplicativo pela Microsoft Store ou baixe pelo site: $($p.site)"
}

function Install-UTProgramFromGitHub {
    <#
    .SYNOPSIS
        Downloads the release asset that matches the catalog pattern. A .zip is extracted to
        the tools folder (portable); an .exe/.msi runs with the catalog's silent arguments.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Programa)
    $rel = Get-UTGitHubLatestRelease -Repo $Programa.github.repo
    $asset = (@($rel.Arquivos | Where-Object { $_.Nome -match $Programa.github.arquivo }) | Select-Object -First 1)
    if (-not $asset) { throw "A última versão de $($Programa.nome) no GitHub não tem o arquivo esperado. Baixe pela página: $($rel.Pagina)" }
    if (-not $PSCmdlet.ShouldProcess($Programa.nome, "Baixar $($asset.Nome) ($($asset.TamanhoMB) MB) do GitHub")) {
        return [pscustomobject]@{ Id = $Programa.id; Status = 'Simulado'; Mensagem = "Baixar $($asset.Url)" }
    }
    $download = Join-Path (Get-UTPath -Name Temp) ("$($Programa.id)-" + $asset.Nome)
    [void](Save-UTDownload -Url $asset.Url -Destino $download)
    try {
        if ($asset.Nome -match '\.zip$') {
            $dest = Join-Path (Get-UTPath -Name Tools) $Programa.id
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Expand-Archive -LiteralPath $download -DestinationPath $dest -Force
            Set-Content -LiteralPath (Get-UTToolVersionFile -Id $Programa.id) -Value $rel.Versao -Encoding ASCII
        } else {
            $silent = [string](Get-UTField $Programa.github 'argsSilencioso' '')
            $installArgs = @()
            if ($silent) { $installArgs = @($silent -split ' ') }
            if ($asset.Nome -match '\.msi$') { $r = Invoke-UTNative -FilePath 'msiexec.exe' -ArgumentList (@('/i', $download, '/qn', '/norestart') + $installArgs) -TimeoutSeconds 1800 }
            else { $r = Invoke-UTNative -FilePath $download -ArgumentList $installArgs -TimeoutSeconds 1800 }
            if ($r.CodigoSaida -notin 0, 3010) { throw "O instalador de $($Programa.nome) terminou com o código $($r.CodigoSaida)." }
        }
    } finally {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }
    $msg = "$($Programa.nome) $($rel.Versao) instalado a partir do GitHub ($($Programa.github.repo))."
    Write-UTLog -Level Sucesso -Message $msg
    return [pscustomobject]@{ Id = $Programa.id; Status = 'Instalado'; Mensagem = $msg }
}

function Update-UTProgram {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    Assert-UTAdmin
    $p = Get-UTProgramCatalog -Id $Id
    if ($p.winget -and (Get-UTWingetPath) -and (Get-UTWingetInstalled).ContainsKey($p.winget)) {
        if (-not $PSCmdlet.ShouldProcess($p.nome, "winget upgrade --id $($p.winget)")) { return [pscustomobject]@{ Id = $Id; Status = 'Simulado'; Mensagem = "winget upgrade --id $($p.winget) -e" } }
        $r = Invoke-UTWinget -Argumentos @('upgrade', '--id', $p.winget, '-e', '--silent', '--accept-package-agreements') -TimeoutSeconds 1800
        $msg = Get-UTWingetMessage -Codigo $r.CodigoSaida
        if ($r.CodigoSaida -notin 0, -1978335189, -1978334967) { throw "$($p.nome): $msg" }
        Write-UTLog -Level Sucesso -Message "$($p.nome): $msg"
        return [pscustomobject]@{ Id = $Id; Status = 'Atualizado'; Mensagem = $msg }
    }
    if ($p.github) { return (Install-UTProgramFromGitHub -Programa $p) }
    throw "$($p.nome) não foi instalado pelo winget; atualize pelo próprio programa ou pelo site: $($p.site)"
}

function Uninstall-UTProgram {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][string]$Id)
    Assert-UTAdmin
    $p = Get-UTProgramCatalog -Id $Id
    $tool = Join-Path (Get-UTPath -Name Tools) $p.id
    if (Test-Path -LiteralPath $tool) {
        if (-not $PSCmdlet.ShouldProcess($tool, 'Apagar a versão portátil')) { return }
        Remove-Item -LiteralPath $tool -Recurse -Force
        Write-UTLog -Level Sucesso -Message "$($p.nome) (portátil) removido."
        return [pscustomobject]@{ Id = $Id; Status = 'Removido'; Mensagem = "$($p.nome) removido." }
    }
    if (-not $p.winget) { throw "$($p.nome) não foi instalado pelo Upgrade Tweaks; desinstale em Configurações > Aplicativos." }
    if (-not $PSCmdlet.ShouldProcess($p.nome, "winget uninstall --id $($p.winget)")) { return }
    $r = Invoke-UTWinget -Argumentos @('uninstall', '--id', $p.winget, '-e', '--silent') -TimeoutSeconds 900
    $msg = Get-UTWingetMessage -Codigo $r.CodigoSaida
    if ($r.CodigoSaida -ne 0) { throw "$($p.nome): $msg" }
    Write-UTLog -Level Sucesso -Message "$($p.nome) desinstalado."
    return [pscustomobject]@{ Id = $Id; Status = 'Removido'; Mensagem = "$($p.nome) desinstalado." }
}

function Start-UTProgram {
    <#
    .SYNOPSIS
        Opens the program as administrator.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string[]]$Argumentos
    )
    $p = Get-UTProgramCatalog -Id $Id
    $exe = Find-UTProgramExecutable -Programa $p
    if (-not $exe) {
        if ($p.somentePagina) { Open-UTProgramPage -Id $Id; return }
        throw "$($p.nome) não está instalado. Use o botão Instalar."
    }
    if (-not $PSCmdlet.ShouldProcess($exe, 'Abrir como administrador')) { return }
    $params = @{ FilePath = $exe; Verb = 'RunAs'; WorkingDirectory = (Split-Path -Parent $exe) }
    if ($Argumentos) { $params.ArgumentList = $Argumentos }
    Start-Process @params
    Write-UTLog -Level Info -Message "$($p.nome) aberto como administrador."
}

function Open-UTProgramPage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    $p = Get-UTProgramCatalog -Id $Id
    if ($PSCmdlet.ShouldProcess($p.site, "Abrir a página de $($p.nome)")) { Start-Process $p.site }
}
#endregion

#region NVIDIA Profile Inspector (.nip)
function Export-UTNvidiaInspectorFile {
    <#
    .SYNOPSIS
        Writes the recommended Warzone profile as an NVIDIA Profile Inspector .nip (same
        values as the GPU tab). The profile name and executables come from the driver.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Destino,
        [psobject]$Contexto
    )
    if (-not (Test-UTNvApiAvailable)) { throw 'Driver NVIDIA não encontrado.' }
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    $cfg = Get-UTConfig -Name 'nvidia-drs'
    $opts = Get-UTGpuOption
    $session = Open-UTNvDrsSession
    try { $target = Get-UTNvidiaTargetProfile -Sessao $session -Escopo perfil -Contexto $Contexto } finally { $session.Dispose() }

    $settings = New-Object System.Text.StringBuilder
    foreach ($item in @($cfg.configuracoes)) {
        $rec = Resolve-UTNvidiaRecommendation -Item $item -Escopo perfil -Opcoes $opts
        if (-not $rec) { continue }
        for ($i = 0; $i -lt @($item.ids).Count; $i++) {
            $sid = [uint32](ConvertTo-UTDrsValue @($item.ids)[$i])
            [void]$settings.AppendFormat("      <ProfileSetting>`r`n        <SettingNameInfo>{0}</SettingNameInfo>`r`n        <SettingID>{1}</SettingID>`r`n        <SettingValue>{2}</SettingValue>`r`n        <ValueType>Dword</ValueType>`r`n      </ProfileSetting>`r`n",
                [Security.SecurityElement]::Escape([string]$item.nomeApp), $sid, [uint32]$rec.Valores[$i])
        }
    }
    $exes = (@($target.Executaveis) | ForEach-Object { "      <string>$([Security.SecurityElement]::Escape($_))</string>" }) -join "`r`n"
    $xml = "<?xml version=`"1.0`" encoding=`"utf-16`"?>`r`n<ArrayOfProfile>`r`n  <Profile>`r`n    <ProfileName>$([Security.SecurityElement]::Escape($target.Nome))</ProfileName>`r`n    <Executeables>`r`n$exes`r`n    </Executeables>`r`n    <Settings>`r`n$($settings.ToString())    </Settings>`r`n  </Profile>`r`n</ArrayOfProfile>`r`n"
    if (-not $PSCmdlet.ShouldProcess($Destino, 'Gravar perfil .nip')) { return $Destino }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destino) | Out-Null
    [IO.File]::WriteAllText($Destino, $xml, [Text.Encoding]::Unicode)
    return $Destino
}

function Import-UTNvidiaInspectorProfile {
    <#
    .SYNOPSIS
        Alternative to the GPU tab: backs up the whole driver profile database, generates the
        .nip and imports it silently with NVIDIA Profile Inspector.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([psobject]$Contexto)
    Assert-UTAdmin
    $p = Get-UTProgramCatalog -Id 'profileinspector'
    $exe = Find-UTProgramExecutable -Programa $p
    if (-not $exe) { throw 'O NVIDIA Profile Inspector não está instalado. Instale na aba Programas.' }
    $nip = Join-Path (Get-UTPath -Name Temp) 'upgrade-warzone.nip'
    $nip = Export-UTNvidiaInspectorFile -Destino $nip -Contexto $Contexto
    if (-not $PSCmdlet.ShouldProcess($exe, "Importar $nip")) { return $nip }
    [void](Invoke-UTPreApplySafety)
    $session = Open-UTNvDrsSession
    try { $backup = Backup-UTNvidiaDrsFile -Sessao $session } finally { $session.Dispose() }
    $r =Invoke-UTNative -FilePath $exe -ArgumentList @($nip, '-silentImport') -TimeoutSeconds 120
    if ($r.CodigoSaida -ne 0) { throw "O Profile Inspector terminou com o código $($r.CodigoSaida). O backup do driver está em $backup." }
    Write-UTLog -Level Sucesso -Message "Perfil do Warzone importado pelo Profile Inspector. Backup completo do driver: $backup"
    return $backup
}
#endregion
