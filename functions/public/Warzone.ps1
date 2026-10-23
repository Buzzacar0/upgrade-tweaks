# "Warzone" tab: game config file (backup, restore, experimental edits), in-game settings guide,
# Windows Defender exclusion and the "Modo Partida".

#region Game config file (Documents\Call of Duty\players)
function Get-UTCodPlayersFolder {
    <#
    .SYNOPSIS
        Documents\Call of Duty\players of the person using the PC. The game writes to the
        profile's own Documents folder even when Windows moved Documents to OneDrive, so every
        candidate is checked and the one with config files wins.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string[]]$Candidatas)
    if (-not $Candidatas) {
        $profileDir = $env:USERPROFILE
        $sid = Get-UTSyncValue -Key 'UsuarioAlvoSid'
        if ($sid) {
            $img = Get-UTRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name 'ProfileImagePath'
            if ($img.ValorExiste) { $profileDir = [Environment]::ExpandEnvironmentVariables([string]$img.Valor) }
        }
        $Candidatas = @(
            (Join-Path $profileDir 'Documents')
            [Environment]::GetFolderPath('MyDocuments')
            $(if ($env:OneDrive) { Join-Path $env:OneDrive 'Documents' })
            $(if ($env:OneDrive) { Join-Path $env:OneDrive 'Documentos' })
        ) | Where-Object { $_ } | Select-Object -Unique
    }
    $folders = @($Candidatas | ForEach-Object { Join-Path $_ 'Call of Duty\players' })
    foreach ($f in $folders) {
        if (@(Get-ChildItem -LiteralPath $f -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'cod\d+' }).Count -gt 0) { return $f }
    }
    foreach ($f in $folders) { if (Test-Path -LiteralPath $f) { return $f } }
    return ($folders | Select-Object -First 1)
}

function Get-UTCodConfigFile {
    <#
    .SYNOPSIS
        Config files of the installed Call of Duty titles (s.1.0.codNN.txt0/txt1 and older formats),
        newest first. The name changes every title, so it is found by pattern.
    #>
    [CmdletBinding()]
    param([string]$Pasta = (Get-UTCodPlayersFolder))
    if (-not (Test-Path -LiteralPath $Pasta)) { return }
    $titles = @{ cod22 = 'Modern Warfare II / Warzone 2'; cod23 = 'Modern Warfare III'; cod24 = 'Black Ops 6'; cod25 = 'Black Ops 7'; cod26 = 'Modern Warfare 4' }
    $files = @(Get-ChildItem -LiteralPath $Pasta -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^s\.\d+\.\d+\.cod\d+\.txt\d*$' -or $_.Name -match '^options\.\d+\.cod\d+\.cst$' -or $_.Name -eq 'adv_options.ini'
        })
    foreach ($f in ($files | Sort-Object LastWriteTime -Descending)) {
        $code = [regex]::Match($f.Name, 'cod\d+').Value
        [pscustomobject]@{
            Arquivo    = $f.FullName
            Nome       = $f.Name
            Titulo     = $(if ($titles.ContainsKey($code)) { $titles[$code] } elseif ($code) { $code } else { 'Call of Duty' })
            Alterado   = $f.LastWriteTime
        }
    }
}

function Backup-UTCodConfig {
    <#
    .SYNOPSIS
        Copies a game config file to backups\cod\AAAA-MM-DD_HHmmss\.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Arquivo)
    if (-not (Test-Path -LiteralPath $Arquivo)) { throw "Arquivo não encontrado: $Arquivo" }
    $folder = Join-Path (Get-UTPath -Name Backups) ('cod\' + (Get-Date).ToString('yyyy-MM-dd_HHmmss_fff'))
    $target = Join-Path $folder (Split-Path -Leaf $Arquivo)
    if ($PSCmdlet.ShouldProcess($Arquivo, "Copiar para $target")) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $Arquivo -Destination $target -Force
        Write-UTLog -Level Info -Message "Backup da configuração do jogo: $target"
    }
    return $target
}

function Get-UTCodConfigBackup {
    [CmdletBinding()]
    param()
    $base = Join-Path (Get-UTPath -Name Backups) 'cod'
    if (-not (Test-Path -LiteralPath $base)) { return }
    Get-ChildItem -LiteralPath $base -Recurse -File | Sort-Object LastWriteTime -Descending |
        ForEach-Object { [pscustomobject]@{ Backup = $_.FullName; Nome = $_.Name; Data = $_.Directory.CreationTime } }
}

function Restore-UTCodConfig {
    <#
    .SYNOPSIS
        Puts a backup back over the current config file (which is backed up first).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Backup,
        [string]$Pasta = (Get-UTCodPlayersFolder)
    )
    if (-not (Test-Path -LiteralPath $Backup)) { throw "Backup não encontrado: $Backup" }
    $target = Join-Path $Pasta (Split-Path -Leaf $Backup)
    if (-not $PSCmdlet.ShouldProcess($target, 'Restaurar a configuração do jogo')) { return }
    if (Test-Path -LiteralPath $target) { [void](Backup-UTCodConfig -Arquivo $target) }
    Copy-Item -LiteralPath $Backup -Destination $target -Force
    Write-UTLog -Level Sucesso -Message "Configuração do jogo restaurada: $target"
}

function Open-UTCodConfigFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $folder = Get-UTCodPlayersFolder
    if (-not (Test-Path -LiteralPath $folder)) { throw 'A pasta de configurações do Call of Duty ainda não existe: abra o jogo uma vez e feche.' }
    if ($PSCmdlet.ShouldProcess($folder, 'Abrir no Explorador')) { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$folder`"" }
}

function Get-UTCodKeyPattern {
    # Matches "Key = value", "Key:0.0 = "value"" and "Key@0;123;456 = value // comment".
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Chave)
    return ('(?m)^(?<prefix>\s*' + [regex]::Escape($Chave) + '(?:[:@][^=\s]*)?\s*=\s*)(?<q>"?)(?<value>[^"\r\n/]*?)(?<q2>"?)(?<suffix>\s*(?://.*)?)$')
}

function Get-UTCodConfigValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Arquivo, [Parameter(Mandatory)][string]$Chave)
    $text = [IO.File]::ReadAllText($Arquivo)
    $m = [regex]::Match($text, (Get-UTCodKeyPattern -Chave $Chave))
    if (-not $m.Success) { return $null }
    return $m.Groups['value'].Value.Trim()
}

function Set-UTCodConfigValue {
    <#
    .SYNOPSIS
        EXPERIMENTAL: changes a key that already exists in the game config file, keeping the line
        format. Never adds unknown keys. Backs up first. Game updates may change the format.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [Parameter(Mandatory)][string]$Chave,
        [Parameter(Mandatory)][string]$Valor,
        # The caller already backed up the file (several keys in one go).
        [switch]$SemBackup
    )
    $bytes = [IO.File]::ReadAllBytes($Arquivo)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [IO.File]::ReadAllText($Arquivo)
    $pattern = Get-UTCodKeyPattern -Chave $Chave
    $m = [regex]::Match($text, $pattern)
    if (-not $m.Success) { throw "A chave '$Chave' não existe neste arquivo; o Upgrade Tweaks não acrescenta chaves desconhecidas." }
    $before = $m.Groups['value'].Value.Trim()
    if ($before -eq $Valor) { return $before }
    if (-not $PSCmdlet.ShouldProcess("$Arquivo ($Chave)", "$before -> $Valor")) { return $before }
    if (-not $SemBackup) { [void](Backup-UTCodConfig -Arquivo $Arquivo) }
    $regex = New-Object System.Text.RegularExpressions.Regex($pattern)
    $new = $regex.Replace($text, { param($x) $x.Groups['prefix'].Value + $x.Groups['q'].Value + $Valor + $x.Groups['q2'].Value + $x.Groups['suffix'].Value }, 1)
    [IO.File]::WriteAllText($Arquivo, $new, (New-Object System.Text.UTF8Encoding($hasBom)))
    Write-UTLog -Level Info -Message "Configuração do jogo: $Chave" -Antes $before -Depois $Valor
    return $before
}

function Set-UTCodRendererWorker {
    <#
    .SYNOPSIS
        EXPERIMENTAL: RendererWorkerCount = physical cores. Community advice differs (cores vs.
        half the threads) and there is no official guidance; the backup allows going back.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Arquivo)
    if (-not $Arquivo) { $Arquivo = (@(Get-UTCodConfigFile) | Select-Object -First 1).Arquivo }
    if (-not $Arquivo) { throw 'Nenhum arquivo de configuração do Call of Duty encontrado. Abra o jogo uma vez e feche.' }
    $hw = Get-UTSyncValue -Key 'Hardware'
    $cores = $(if ($hw -and $hw.Cpu) { [int]$hw.Cpu.Nucleos } else { [int]((@(Get-CimInstance -ClassName Win32_Processor) | Select-Object -First 1).NumberOfCores) })
    return (Set-UTCodConfigValue -Arquivo $Arquivo -Chave 'RendererWorkerCount' -Valor ([string]$cores) -WhatIf:$WhatIfPreference)
}
#endregion

#region Recommended settings written to the config file
function Get-UTCodConfigOption {
    <#
    .SYNOPSIS
        What a key accepts, read from the comment the game writes on the same line:
        "// one of A, B, C" (list), "// 0 to 200" (range) or a true/false value.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Arquivo, [Parameter(Mandatory)][string]$Chave)
    $text = [IO.File]::ReadAllText($Arquivo)
    $m = [regex]::Match($text, (Get-UTCodKeyPattern -Chave $Chave))
    if (-not $m.Success) { return $null }
    $current = $m.Groups['value'].Value.Trim()
    $comment = $m.Groups['suffix'].Value
    $list = [regex]::Match($comment, '//\s*one of\s+(?<l>.+)$')
    if ($list.Success) { return [pscustomobject]@{ Tipo = 'lista'; Opcoes = @($list.Groups['l'].Value -split ',\s*' | ForEach-Object { $_.Trim() }); Atual = $current } }
    $range = [regex]::Match($comment, '//\s*(?<a>-?[\d.]+)\s+to\s+(?<b>-?[\d.]+)')
    if ($range.Success) {
        $inv = [Globalization.CultureInfo]::InvariantCulture
        return [pscustomobject]@{ Tipo = 'faixa'; Minimo = [double]::Parse($range.Groups['a'].Value, $inv); Maximo = [double]::Parse($range.Groups['b'].Value, $inv); Atual = $current }
    }
    if ($current -in 'true', 'false') { return [pscustomobject]@{ Tipo = 'bool'; Opcoes = @('true', 'false'); Atual = $current } }
    return [pscustomobject]@{ Tipo = 'livre'; Atual = $current }
}

function Test-UTCodConfigValueValid {
    # Returns the value with the exact spelling the game uses, or $null when it is not accepted.
    param([Parameter(Mandatory)][psobject]$Opcao, [Parameter(Mandatory)][string]$Valor)
    switch ($Opcao.Tipo) {
        'lista' { return (@($Opcao.Opcoes | Where-Object { $_ -eq $Valor }) | Select-Object -First 1) }
        'bool' { if ($Valor -in 'true', 'false') { return $Valor.ToLowerInvariant() }; return $null }
        'faixa' {
            $n = 0.0
            if (-not [double]::TryParse($Valor, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $null }
            if ($n -lt $Opcao.Minimo -or $n -gt $Opcao.Maximo) { return $null }
            return $Valor
        }
        default { return $null }
    }
}

function Get-UTCodRecommendedChange {
    <#
    .SYNOPSIS
        Key-by-key plan of the in-game guide for one config file: current value, new value and
        whether it can be written. Read only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('competitivo', 'equilibrio')][string]$Perfil,
        [Parameter(Mandatory)][string]$Arquivo
    )
    $cfg = Get-UTConfig -Name 'warzone-guia'
    $hw = Get-UTSyncValue -Key 'Hardware'
    $vendor = $null
    $vram = $null
    if ($hw) {
        $vendor = (@($hw.GpuFabricantes) | Select-Object -First 1)
        $g = (@($hw.Gpus | Where-Object { $_ -and -not $_.Integrada }) | Select-Object -First 1)
        if ($g) { $vram = $g.VramGB }
    }
    $opts = Get-UTGpuOption
    foreach ($item in @($cfg.perfis[$Perfil].itens)) {
        $pairs = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($item.arquivo)) { if ($p) { $pairs.Add($p) } }
        if ($vendor -and $item.arquivoPorGpu -and $item.arquivoPorGpu.Contains($vendor)) { foreach ($p in @($item.arquivoPorGpu[$vendor])) { $pairs.Add($p) } }
        if ($vram -and $item.arquivoPorVram) {
            $best = $null
            foreach ($k in @($item.arquivoPorVram.Keys | Sort-Object { [int]$_ })) { if ([double]$vram -ge [int]$k) { $best = $k } }
            if ($best) {
                $byVram = @($item.arquivoPorVram[$best])
                $keys = @($byVram | ForEach-Object { $_.chave })
                foreach ($old in @($pairs.ToArray() | Where-Object { $keys -contains $_.chave })) { [void]$pairs.Remove($old) }
                foreach ($p in $byVram) { $pairs.Add($p) }
            }
        }
        if ($item.regra -in 'limiteFps', 'limiteFpsSempre') {
            $limit = ($item.regra -eq 'limiteFpsSempre' -or $opts.ComGsync) -and [int]$opts.HzMonitor -gt 30
            if ($limit) {
                $pairs.Add([ordered]@{ chave = 'CapFps'; valor = 'true' })
                $pairs.Add([ordered]@{ chave = 'MaxFpsInGame'; valor = [string]([int]$opts.HzMonitor - 3) })
            } else {
                $pairs.Add([ordered]@{ chave = 'CapFps'; valor = 'false' })
            }
        }
        if ($pairs.Count -eq 0) {
            [pscustomobject]@{ Opcao = [string]$item.opcao; Chave = $null; Atual = $null; Novo = [string]$item.valor; Aplicavel = $false; Motivo = 'Configure no menu do jogo (não há uma chave segura no arquivo).' }
            continue
        }
        foreach ($p in $pairs) {
            $o = Get-UTCodConfigOption -Arquivo $Arquivo -Chave ([string]$p.chave)
            if ($null -eq $o) {
                [pscustomobject]@{ Opcao = [string]$item.opcao; Chave = [string]$p.chave; Atual = $null; Novo = [string]$p.valor; Aplicavel = $false; Motivo = 'Esta versão do jogo não tem essa chave.' }
                continue
            }
            $valid = Test-UTCodConfigValueValid -Opcao $o -Valor ([string]$p.valor)
            $reason = ''
            if (-not $valid) { $reason = 'Valor não aceito por esta versão do jogo; ficou como está.' } elseif ($o.Atual -eq $valid) { $reason = 'Já está assim.' }
            [pscustomobject]@{
                Opcao     = [string]$item.opcao
                Chave     = [string]$p.chave
                Atual     = $o.Atual
                Novo      = $(if ($valid) { $valid } else { [string]$p.valor })
                Aplicavel = [bool]$valid
                Motivo    = $reason
            }
        }
    }
}

function Test-UTCodGameRunning {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $names = @(Get-UTGameExecutable | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
    if ($names.Count -eq 0) { $names = @('cod', 'cod25-cod', 'cod26-cod', 'sp26-cod') }
    return (@(Get-Process -Name $names -ErrorAction SilentlyContinue).Count -gt 0)
}

function Set-UTCodRecommendedSetting {
    <#
    .SYNOPSIS
        Writes the in-game guide into the config files of the newest Call of Duty title (the
        game keeps two copies, txt0 and txt1). One backup per file before anything changes.
        Returns the plan with what was written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('competitivo', 'equilibrio')][string]$Perfil)
    if (Test-UTCodGameRunning) { throw 'Feche o Call of Duty antes: com o jogo aberto ele grava o arquivo de novo por cima.' }
    $files = @(Get-UTCodConfigFile)
    if ($files.Count -eq 0) { throw 'Nenhum arquivo de configuração do Call of Duty encontrado. Abra o jogo uma vez e feche.' }
    $title = [regex]::Match([string]$files[0].Nome, 'cod\d+').Value
    $targets = @($files | Where-Object { [regex]::Match([string]$_.Nome, 'cod\d+').Value -eq $title -and $_.Nome -match '\.txt\d*$' })
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($f in $targets) {
        $plan = @(Get-UTCodRecommendedChange -Perfil $Perfil -Arquivo $f.Arquivo)
        $changes = @($plan | Where-Object { $_.Aplicavel -and $_.Atual -ne $_.Novo })
        if ($changes.Count -gt 0 -and $PSCmdlet.ShouldProcess($f.Arquivo, "Gravar $($changes.Count) configurações ($Perfil)")) {
            [void](Backup-UTCodConfig -Arquivo $f.Arquivo)
            foreach ($c in $changes) { [void](Set-UTCodConfigValue -Arquivo $f.Arquivo -Chave $c.Chave -Valor $c.Novo -SemBackup -Confirm:$false) }
        }
        foreach ($p in $plan) { $result.Add(($p | Add-Member -NotePropertyName Arquivo -NotePropertyValue $f.Nome -PassThru)) }
    }
    Write-UTLog -Level Sucesso -Message ("Configurações do jogo ({0}) gravadas em {1} arquivo(s)." -f $Perfil, $targets.Count)
    return $result.ToArray()
}
#endregion

#region In-game guide
function Get-UTWarzoneGuide {
    <#
    .SYNOPSIS
        In-game settings guide for this PC: values adjusted for the GPU vendor and the VRAM.
    #>
    [CmdletBinding()]
    param([ValidateSet('competitivo', 'equilibrio')][string]$Perfil = 'competitivo')
    $cfg = Get-UTConfig -Name 'warzone-guia'
    $hw = Get-UTSyncValue -Key 'Hardware'
    $vendor = $null
    $vram = $null
    if ($hw) {
        $vendor = (@($hw.GpuFabricantes) | Select-Object -First 1)
        $g = (@($hw.Gpus | Where-Object { $_ -and -not $_.Integrada }) | Select-Object -First 1)
        if ($g) { $vram = $g.VramGB }
    }
    foreach ($item in @($cfg.perfis[$Perfil].itens)) {
        $value = [string]$item.valor
        if ($vendor -and $item.porGpu -and $item.porGpu[$vendor]) { $value = [string]$item.porGpu[$vendor] }
        if ($vram -and $item.porVram) {
            $best = $null
            foreach ($k in @($item.porVram.Keys | Sort-Object { [int]$_ })) { if ([double]$vram -ge [int]$k) { $best = $k } }
            if ($best) { $value = [string]$item.porVram[$best] }
        }
        [pscustomobject]@{ Grupo = $item.grupo; Opcao = $item.opcao; Valor = $value; Motivo = $item.motivo }
    }
}
#endregion

#region Windows Defender exclusion
function Get-UTDefenderExclusionTarget {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([psobject]$Contexto)
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    $paths = @($Contexto.PastasJogo | Where-Object { $_ })
    $paths += @(Get-UTShaderCacheLocation | ForEach-Object { $_.Caminho })
    return @($paths | Sort-Object -Unique)
}

function Add-UTDefenderGameExclusion {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId, [psobject]$Contexto)
    $targets = @(Get-UTDefenderExclusionTarget -Contexto $Contexto)
    if (@($targets | Where-Object { $_ -notlike '*Cache*' }).Count -eq 0) { throw 'Call of Duty não encontrado; nada a excluir.' }
    try { $pref = Get-MpPreference -ErrorAction Stop } catch { throw 'O Windows Defender não é o antivírus ativo neste PC; configure a exclusão no seu antivírus.' }
    $existing = @($pref.ExclusionPath | Where-Object { $_ })
    $toAdd = @($targets | Where-Object { $existing -notcontains $_ })
    [void](Save-UTOriginalItem -Chave 'defender|exclusoes' -Dados ([ordered]@{ adicionadas = @($toAdd) }) -TweakId $TweakId)
    if ($toAdd.Count -gt 0 -and $PSCmdlet.ShouldProcess(($toAdd -join '; '), 'Excluir da verificação do Windows Defender')) {
        Add-MpPreference -ExclusionPath $toAdd -ErrorAction Stop
    }
}

function Remove-UTDefenderGameExclusion {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $d = Pop-UTOriginalItem -Chave 'defender|exclusoes' -TweakId $TweakId
    if ($d -isnot [System.Collections.IDictionary]) { return }
    $added = @($d.adicionadas | Where-Object { $_ })
    if ($added.Count -gt 0 -and $PSCmdlet.ShouldProcess(($added -join '; '), 'Voltar a verificar no Windows Defender')) {
        Remove-MpPreference -ExclusionPath $added -ErrorAction Stop
    }
}

function Test-UTDefenderGameExclusion {
    [CmdletBinding()]
    [OutputType([bool])]
    param([psobject]$Contexto)
    $targets = @(Get-UTDefenderExclusionTarget -Contexto $Contexto)
    if ($targets.Count -eq 0) { return $false }
    try { $pref = Get-MpPreference -ErrorAction Stop } catch { return $false }
    $existing = @($pref.ExclusionPath | Where-Object { $_ })
    return (@($targets | Where-Object { $existing -notcontains $_ }).Count -eq 0)
}
#endregion

#region Modo Partida
function Get-UTMatchModeStateFile {
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateSet('estado', 'usuario')][string]$Tipo = 'estado')
    $name = $(if ($Tipo -eq 'estado') { 'modo-partida.json' } else { 'modo-partida-usuario.json' })
    return (Join-Path (Get-UTPath -Name State) $name)
}

function Get-UTMatchModeList {
    <#
    .SYNOPSIS
        Default list + the user's choices and extra processes. The launcher that holds the game
        and protected processes never appear.
    #>
    [CmdletBinding()]
    param([psobject]$Contexto)
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    $cfg = Get-UTConfig -Name 'modo-partida'
    $user = Read-UTJsonFile -Path (Get-UTMatchModeStateFile -Tipo usuario) -Default ([ordered]@{ marcados = [ordered]@{}; extras = @() })
    $protected = @($cfg.protegidos)
    $gameLaunchers = @{ steam = 'steam'; battlenet = 'Battle.net'; xbox = 'XboxPcApp' }
    $skip = @(@($Contexto.Launchers) | ForEach-Object { $gameLaunchers[[string]$_] } | Where-Object { $_ })

    $all = @(@($cfg.processos) + @($user.extras | Where-Object { $_ }))
    $seen = @{}
    foreach ($p in $all) {
        $name = [string]$p.processo
        if ($seen.ContainsKey($name.ToLowerInvariant()) -or $protected -contains $name -or $skip -contains $name) { continue }
        $seen[$name.ToLowerInvariant()] = $true
        $checked = [bool]$p.marcado
        if ($user.marcados -and $user.marcados.Contains($name)) { $checked = [bool]$user.marcados[$name] }
        [pscustomobject]@{ Processo = $name; Nome = [string]$p.nome; Grupo = [string]$p.grupo; Marcado = $checked; Reabrir = [bool]$p.reabrir }
    }
}

function Set-UTMatchModeChoice {
    <#
    .SYNOPSIS
        Saves which processes the user wants closed and adds extra ones.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Collections.IDictionary]$Marcados = @{},
        [object[]]$Extras = @()
    )
    $protected = @((Get-UTConfig -Name 'modo-partida').protegidos)
    foreach ($e in $Extras) { if ($protected -contains [string]$e.processo) { throw "O processo $($e.processo) é protegido e não pode entrar no Modo Partida." } }
    $path = Get-UTMatchModeStateFile -Tipo usuario
    if ($PSCmdlet.ShouldProcess($path, 'Salvar escolhas do Modo Partida')) {
        Write-UTJsonFile -Path $path -InputObject ([ordered]@{ marcados = $Marcados; extras = @($Extras) }) -WhatIf:$false
    }
}

function Get-UTMatchModeStatus {
    [CmdletBinding()]
    param()
    $s = Read-UTJsonFile -Path (Get-UTMatchModeStateFile)
    if ($null -eq $s) { return [pscustomobject]@{ Ativo = $false; Inicio = $null; Fechados = @() } }
    return [pscustomobject]@{ Ativo = [bool]$s.ativo; Inicio = $s.inicio; Fechados = @($s.fechados) }
}

function Start-UTMatchMode {
    <#
    .SYNOPSIS
        Before playing: closes the checked processes, activates Windows' Maximum Performance plan (or
        Balanced on dual-CCD X3D) and, optionally, empties the standby memory list.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$LimparMemoriaEspera, [psobject]$Contexto)
    Assert-UTAdmin
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    if ((Get-UTMatchModeStatus).Ativo) { throw 'O Modo Partida já está ativo.' }

    $closed = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Get-UTMatchModeList -Contexto $Contexto | Where-Object Marcado)) {
        $procs = @(Get-Process -Name $p.Processo -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) { continue }
        $path = (@($procs | ForEach-Object { try { $_.Path } catch { $null } } | Where-Object { $_ }) | Select-Object -First 1)
        if (-not $PSCmdlet.ShouldProcess($p.Nome, 'Fechar durante a partida')) { continue }
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        $closed.Add([ordered]@{ processo = $p.Processo; nome = $p.Nome; caminho = $path; reabrir = $p.Reabrir })
    }

    $previous = Get-UTActivePowerScheme
    if ($PSCmdlet.ShouldProcess('plano de energia', 'Ativar o plano da partida')) {
        if ($Contexto.X3D -eq 'duplo') {
            [void](Invoke-UTPowerCfg -Argumentos @('/setactive', (Get-UTConfig -Name 'powerplan').equilibrado))
        } else {
            $max = Find-UTMaxPerformanceScheme
            if ($max) { [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $max)) }
            else { [void](Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo') }
        }
        # Never turn off the display nor sleep in the middle of a match.
        try { Set-UTPlanNoSleep -Guid (Get-UTActivePowerScheme).Guid -Contexto $Contexto -Confirm:$false } catch { Write-UTLog -Level Aviso -Message 'Não foi possível deixar a tela e a suspensão em Nunca.' -Detalhe $_.Exception.Message }
    }
    if ($LimparMemoriaEspera) {
        try { Clear-UTStandbyList } catch { Write-UTLog -Level Aviso -Message $_.Exception.Message }
    }
    # The FPS overlay comes along when the person asked for it (Overlay tab) and it is not open yet.
    $overlay = $false
    try {
        if ((Get-UTOverlayConfig).ModoPartida -and (Test-UTPresentMon) -and -not (Test-UTOverlayRunning) -and $PSCmdlet.ShouldProcess('overlay', 'Ligar durante a partida')) {
            $overlay = [bool](Start-UTOverlay -Confirm:$false)
        }
    } catch { Write-UTLog -Level Aviso -Message 'Não foi possível ligar o overlay no Modo Partida.' -Detalhe $_.Exception.Message }

    if (-not $WhatIfPreference) {
        Write-UTJsonFile -Path (Get-UTMatchModeStateFile) -InputObject ([ordered]@{
                ativo = $true; inicio = (Get-Date).ToString('o'); planoAnterior = $previous.Guid; fechados = @($closed.ToArray()); overlay = $overlay
            })
    }
    Write-UTLog -Level Sucesso -Message ("Modo Partida ligado: {0} programa(s) fechado(s)." -f $closed.Count)
    return (Get-UTMatchModeStatus)
}

function Stop-UTMatchMode {
    <#
    .SYNOPSIS
        After playing: goes back to the previous power plan and reopens the programs marked to
        come back (without administrator rights, as the user who is logged on).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $s = Read-UTJsonFile -Path (Get-UTMatchModeStateFile)
    if ($null -eq $s -or -not $s.ativo) { return }
    if ($s.planoAnterior -and (Test-UTPowerScheme -Guid $s.planoAnterior) -and $PSCmdlet.ShouldProcess('plano de energia', 'Voltar ao plano anterior')) {
        [void](Invoke-UTPowerCfg -Argumentos @('/setactive', [string]$s.planoAnterior))
    }
    foreach ($p in @($s.fechados | Where-Object { $_ -and $_.reabrir -and $_.caminho })) {
        if ((Test-Path -LiteralPath $p.caminho) -and $PSCmdlet.ShouldProcess($p.nome, 'Reabrir')) {
            # Through explorer.exe the program starts as the logged-on user, not elevated.
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($p.caminho)`""
        }
    }
    if ((Get-UTField -Objeto $s -Nome 'overlay' -Padrao $false) -and $PSCmdlet.ShouldProcess('overlay', 'Desligar')) {
        try { Stop-UTOverlay -Confirm:$false } catch { Write-UTLog -Level Aviso -Message 'Não foi possível desligar o overlay.' -Detalhe $_.Exception.Message }
    }
    if (-not $WhatIfPreference) {
        $s.ativo = $false
        Write-UTJsonFile -Path (Get-UTMatchModeStateFile) -InputObject $s
    }
    Write-UTLog -Level Sucesso -Message 'Modo Partida desligado.'
}
#endregion
