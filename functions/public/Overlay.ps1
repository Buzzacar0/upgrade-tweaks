# Overlay: FPS, 1% and 0.1% low, frame time graph and sensors over the game. The frames come from
# PresentMon (official Intel console app, from its GitHub Release), which reads the ETW events of
# Windows: nothing is injected into the game and no process is hooked. Settings and profiles in
# %AppData%\UpgradeTweaks\overlay.json; the overlay itself runs in its own process (-Overlay), so it
# keeps going with the main window closed and can start with Windows.

#region Settings (overlay.json)
function Get-UTOverlayItem {
    # Items an overlay profile can show, in the default order.
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @('fps', 'lows', 'frametime', 'grafico', 'cpu', 'gpu', 'ram', 'vram', 'relogio', 'modo')
}

function Get-UTOverlayPositionName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @('SuperiorEsquerda', 'SuperiorCentro', 'SuperiorDireita', 'MeioEsquerda', 'MeioDireita', 'InferiorEsquerda', 'InferiorCentro', 'InferiorDireita')
}

function New-UTOverlayProfile {
    # A profile with the defaults, changed by -Valores.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a new object; nothing changes on the system.')]
    [CmdletBinding()]
    param([System.Collections.IDictionary]$Valores = @{})
    $p = [ordered]@{
        Posicao = 'SuperiorEsquerda'; Monitor = 'jogo'; Margem = 16; Escala = 1.0; Opacidade = 1.0; Fundo = 0.55
        CorTexto = '#FFFFFF'; CorDestaque = '#A78BFA'; Horizontal = $false; GraficoSegundos = 5
        Itens = @('fps', 'lows', 'frametime', 'grafico', 'cpu', 'gpu')
    }
    foreach ($k in @($Valores.Keys)) { $p[$k] = $Valores[$k] }
    return $p
}

function Get-UTOverlayDefault {
    [CmdletBinding()]
    param()
    $profiles = [ordered]@{
        'Padrão'      = New-UTOverlayProfile
        'Competitivo' = New-UTOverlayProfile -Valores @{ Posicao = 'SuperiorCentro'; Horizontal = $true; Fundo = 0.35; Itens = @('fps', 'lows', 'frametime') }
        'Completo'    = New-UTOverlayProfile -Valores @{ Itens = @(Get-UTOverlayItem) }
    }
    $games = [ordered]@{}
    foreach ($g in 'cod.exe', 'cod25-cod.exe', 'cod26-cod.exe', 'sp26-cod.exe') { $games[$g] = 'Competitivo' }
    return [ordered]@{
        Versao = 1; PerfilAtual = 'Padrão'; Perfis = $profiles; Jogos = $games
        Atalhos = [ordered]@{ Mostrar = 'Ctrl+Shift+F10'; ProximoPerfil = 'Ctrl+Shift+F11'; Benchmark = 'Ctrl+Shift+F12' }
        SoEmJogo = $true; Rtss = $false; IniciarComWindows = $false; ModoPartida = $true; JanelaLowsSegundos = 30; IntervaloMs = 250
    }
}

function ConvertTo-UTOverlayColor {
    param([AllowNull()][object]$Cor, [string]$Padrao)
    $s = [string]$Cor
    if ($s -match '^#[0-9A-Fa-f]{6}$') { return $s.ToUpperInvariant() }
    return $Padrao
}

function ConvertTo-UTOverlayProfile {
    # Validated profile: numbers within range, known items only, colors as #RRGGBB.
    [CmdletBinding()]
    param([AllowNull()][object]$Perfil)
    $out = New-UTOverlayProfile
    if ($Perfil -isnot [System.Collections.IDictionary]) { return $out }
    $num = {
        param($k, [double]$min, [double]$max)
        if (-not $Perfil.Contains($k)) { return }
        $v = 0.0
        if ([double]::TryParse(("$($Perfil[$k])" -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { $out[$k] = [math]::Min($max, [math]::Max($min, $v)) }
    }
    if ((Get-UTOverlayPositionName) -contains [string]$Perfil['Posicao']) { $out.Posicao = [string]$Perfil['Posicao'] }
    $mon = [string]$Perfil['Monitor']
    if ($mon -in 'jogo', 'principal' -or $mon -match '^\\\\\.\\DISPLAY\d+$') { $out.Monitor = $mon }
    & $num 'Margem' 0 400
    & $num 'Escala' 0.5 2.5
    & $num 'Opacidade' 0.2 1
    & $num 'Fundo' 0 1
    & $num 'GraficoSegundos' 1 30
    $out.Margem = [int]$out.Margem
    $out.GraficoSegundos = [int]$out.GraficoSegundos
    $out.CorTexto = ConvertTo-UTOverlayColor $Perfil['CorTexto'] '#FFFFFF'
    $out.CorDestaque = ConvertTo-UTOverlayColor $Perfil['CorDestaque'] '#A78BFA'
    if ($Perfil['Horizontal'] -is [bool]) { $out.Horizontal = $Perfil['Horizontal'] }
    if ($Perfil.Contains('Itens')) {
        $known = Get-UTOverlayItem
        $seen = @{}
        $out.Itens = @(@($Perfil['Itens']) | Where-Object { $known -contains [string]$_ -and -not $seen.ContainsKey([string]$_) } | ForEach-Object { $seen[[string]$_] = $true; [string]$_ })
    }
    return $out
}

function ConvertTo-UTOverlayConfig {
    <#
    .SYNOPSIS
        Validated copy of the overlay settings. At least one profile always exists, the current
        profile and the profiles of the games always point to an existing one.
    #>
    [CmdletBinding()]
    param([AllowNull()][object]$Config)
    $def = Get-UTOverlayDefault
    if ($Config -isnot [System.Collections.IDictionary]) { return $def }
    $out = [ordered]@{ Versao = 1; PerfilAtual = $def.PerfilAtual; Perfis = [ordered]@{}; Jogos = [ordered]@{}; Atalhos = [ordered]@{} }
    if ($Config['Perfis'] -is [System.Collections.IDictionary] -and $Config['Perfis'].Count -gt 0) {
        foreach ($k in @($Config['Perfis'].Keys)) {
            $name = ([string]$k).Trim()
            if ($name -and $name.Length -le 40) { $out.Perfis[$name] = ConvertTo-UTOverlayProfile -Perfil $Config['Perfis'][$k] }
        }
    }
    if ($out.Perfis.Count -eq 0) { $out.Perfis = $def.Perfis }
    $first = @($out.Perfis.Keys)[0]
    $out.PerfilAtual = $(if ($out.Perfis.Contains([string]$Config['PerfilAtual'])) { [string]$Config['PerfilAtual'] } else { $first })
    $games = $(if ($Config.Contains('Jogos')) { $Config['Jogos'] } else { $def.Jogos })
    if ($games -is [System.Collections.IDictionary]) {
        foreach ($k in @($games.Keys)) {
            $exe = ([string]$k).Trim().ToLowerInvariant()
            if ($exe -notmatch '^[^\\/:*?"<>|]+\.exe$') { continue }
            $out.Jogos[$exe] = $(if ($out.Perfis.Contains([string]$games[$k])) { [string]$games[$k] } else { $first })
        }
    }
    foreach ($k in 'Mostrar', 'ProximoPerfil', 'Benchmark') {
        $h = $def.Atalhos[$k]
        if ($Config['Atalhos'] -is [System.Collections.IDictionary] -and $Config['Atalhos'].Contains($k)) {
            $v = [string]$Config['Atalhos'][$k]
            if ($v -eq '' -or $null -ne (ConvertTo-UTHotkey -Texto $v)) { $h = $v }
        }
        $out.Atalhos[$k] = $h
    }
    foreach ($k in 'SoEmJogo', 'Rtss', 'IniciarComWindows', 'ModoPartida') { $out[$k] = $(if ($Config[$k] -is [bool]) { $Config[$k] } else { $def[$k] }) }
    $lows = $Config['JanelaLowsSegundos']
    $out.JanelaLowsSegundos = $(if ("$lows" -match '^\d+$') { [int][math]::Min(120, [math]::Max(5, [int]$lows)) } else { $def.JanelaLowsSegundos })
    $iv = $Config['IntervaloMs']
    $out.IntervaloMs = $(if ("$iv" -match '^\d+$') { [int][math]::Min(1000, [math]::Max(100, [int]$iv)) } else { $def.IntervaloMs })
    return $out
}

function Get-UTOverlayConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path (Get-UTPath -Name Usuario) 'overlay.json')
}

function Get-UTOverlayConfig {
    [CmdletBinding()]
    param()
    $path = Get-UTOverlayConfigPath
    $saved = $null
    try { $saved = Read-UTJsonFile -Path $path } catch {
        Write-UTLog -Level Aviso -Message 'O arquivo de configuração do overlay estava danificado; voltou ao padrão.' -Detalhe $_.Exception.Message
        try { Copy-Item -LiteralPath $path -Destination "$path.bak" -Force } catch { $null = $_ }
    }
    return (ConvertTo-UTOverlayConfig -Config $saved)
}

function Save-UTOverlayConfig {
    <#
    .SYNOPSIS
        Saves the overlay settings (validated). A running overlay picks them up within a second.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $clean = ConvertTo-UTOverlayConfig -Config $Config
    if ($PSCmdlet.ShouldProcess((Get-UTOverlayConfigPath), 'Salvar configuração do overlay')) {
        Write-UTJsonFile -Path (Get-UTOverlayConfigPath) -InputObject $clean -Confirm:$false
    }
    return $clean
}

function Resolve-UTOverlayProfile {
    # Profile for the game in the foreground: the one set for its .exe, otherwise the current one.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config, [AllowEmptyString()][string]$Processo)
    $exe = $Processo.ToLowerInvariant()
    if ($exe -and -not $exe.EndsWith('.exe')) { $exe += '.exe' }
    if ($exe -and $Config.Jogos.Contains($exe)) { return [string]$Config.Jogos[$exe] }
    return [string]$Config.PerfilAtual
}
#endregion

#region Pure helpers (position, hotkeys, texts, sensors)
function Get-UTOverlayPosition {
    <#
    .SYNOPSIS
        Top-left corner (physical pixels) of an overlay of -Largura x -Altura pixels at one of the
        8 positions of the work area -Area (Left/Top/Right/Bottom), with -Margem in pixels at 100%
        scaled by the monitor DPI.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Area,
        [Parameter(Mandatory)][double]$Largura,
        [Parameter(Mandatory)][double]$Altura,
        [Parameter(Mandatory)][string]$Posicao,
        [double]$Margem = 16,
        [double]$Dpi = 96
    )
    $m = $Margem * $Dpi / 96
    $l = [double]$Area.Left; $t = [double]$Area.Top; $r = [double]$Area.Right; $b = [double]$Area.Bottom
    $x = switch -Regex ($Posicao) { 'Esquerda$' { $l + $m } 'Direita$' { $r - $m - $Largura } default { $l + ($r - $l - $Largura) / 2 } }
    $y = switch -Regex ($Posicao) { '^Superior' { $t + $m } '^Inferior' { $b - $m - $Altura } default { $t + ($b - $t - $Altura) / 2 } }
    return [pscustomobject]@{ X = [int][math]::Round($x); Y = [int][math]::Round($y) }
}

function ConvertTo-UTHotkey {
    <#
    .SYNOPSIS
        "Ctrl+Shift+F10" -> modifiers and virtual key of RegisterHotKey; $null when invalid. A
        hotkey needs at least one modifier, except F13 to F24, Pause and Scroll Lock.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texto)
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $null }
    $mods = 0
    $vk = 0
    foreach ($part in ($Texto -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        switch -Regex ($part) {
            '^(?i)(ctrl|control)$' { $mods = $mods -bor 0x2; continue }
            '^(?i)shift$' { $mods = $mods -bor 0x4; continue }
            '^(?i)alt$' { $mods = $mods -bor 0x1; continue }
            '^(?i)win$' { $mods = $mods -bor 0x8; continue }
            '^(?i)f([1-9]|1[0-9]|2[0-4])$' { $vk = 0x6F + [int]$part.Substring(1); continue }
            '^[A-Za-z]$' { $vk = [int][char]$part.ToUpperInvariant(); continue }
            '^[0-9]$' { $vk = [int][char]$part; continue }
            '^(?i)num([0-9])$' { $vk = 0x60 + [int]$part.Substring(3); continue }
            '^(?i)(insert|ins)$' { $vk = 0x2D; continue }
            '^(?i)home$' { $vk = 0x24; continue }
            '^(?i)end$' { $vk = 0x23; continue }
            '^(?i)(pageup|pgup)$' { $vk = 0x21; continue }
            '^(?i)(pagedown|pgdn)$' { $vk = 0x22; continue }
            '^(?i)pause$' { $vk = 0x13; continue }
            '^(?i)(scrolllock|scroll)$' { $vk = 0x91; continue }
            default { return $null }
        }
    }
    if ($vk -eq 0) { return $null }
    $alone = ($vk -ge 0x7C -and $vk -le 0x87) -or $vk -in 0x13, 0x91
    if ($mods -eq 0 -and -not $alone) { return $null }
    return [pscustomobject]@{ Modificadores = ($mods -bor 0x4000); Tecla = $vk; Texto = $Texto }
}

function Format-UTOverlayNumber {
    param([AllowNull()][object]$Valor, [int]$Casas = 0)
    if ($null -eq $Valor -or [double]::IsNaN([double]$Valor) -or [double]::IsInfinity([double]$Valor)) { return '-' }
    return ([double]$Valor).ToString("F$Casas", [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
}

function Get-UTOverlayLine {
    <#
    .SYNOPSIS
        The lines of the overlay for a profile: Item, Rotulo and Valor (texts), from the frame
        statistics (-Quadros, a FrameStats) and the sensors (-Sensores: CpuTemp, CpuUso,
        GpuTemp, GpuUso, Ram, Vram). Used by the window and by the RTSS text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Perfil,
        [AllowNull()][object]$Quadros,
        [System.Collections.IDictionary]$Sensores = @{},
        [datetime]$Agora = [datetime]::Now
    )
    $s = $Sensores
    $pair = {
        param($temp, $use)
        $parts = @()
        if ($null -ne $temp) { $parts += "$(Format-UTOverlayNumber $temp) °C" }
        if ($null -ne $use) { $parts += "$(Format-UTOverlayNumber $use) %" }
        if ($parts.Count -eq 0) { '-' } else { $parts -join '  ' }
    }
    foreach ($item in @($Perfil.Itens)) {
        switch ($item) {
            'fps' { [pscustomobject]@{ Item = 'fps'; Rotulo = 'FPS'; Valor = $(if ($Quadros) { Format-UTOverlayNumber $Quadros.Fps } else { '-' }) } }
            'lows' { [pscustomobject]@{ Item = 'lows'; Rotulo = '1% / 0,1%'; Valor = $(if ($Quadros) { "$(Format-UTOverlayNumber $Quadros.Low1) / $(Format-UTOverlayNumber $Quadros.Low01)" } else { '- / -' }) } }
            'frametime' { [pscustomobject]@{ Item = 'frametime'; Rotulo = 'Frametime'; Valor = $(if ($Quadros) { "$(Format-UTOverlayNumber $Quadros.FrameMs 1) ms" } else { '-' }) } }
            'grafico' { [pscustomobject]@{ Item = 'grafico'; Rotulo = ''; Valor = '' } }
            'cpu' { [pscustomobject]@{ Item = 'cpu'; Rotulo = 'CPU'; Valor = (& $pair $s['CpuTemp'] $s['CpuUso']) } }
            'gpu' { [pscustomobject]@{ Item = 'gpu'; Rotulo = 'GPU'; Valor = (& $pair $s['GpuTemp'] $s['GpuUso']) } }
            'ram' { [pscustomobject]@{ Item = 'ram'; Rotulo = 'RAM'; Valor = $(if ($null -ne $s['Ram']) { "$(Format-UTOverlayNumber $s['Ram'] 1) GB" } else { '-' }) } }
            'vram' { [pscustomobject]@{ Item = 'vram'; Rotulo = 'VRAM'; Valor = $(if ($null -ne $s['Vram']) { "$(Format-UTOverlayNumber ([double]$s['Vram'] / 1024) 1) GB" } else { '-' }) } }
            'relogio' { [pscustomobject]@{ Item = 'relogio'; Rotulo = 'Hora'; Valor = $Agora.ToString('HH:mm') } }
            'modo' { [pscustomobject]@{ Item = 'modo'; Rotulo = 'Modo'; Valor = $(if ($Quadros -and $Quadros.PresentMode) { ([string]$Quadros.PresentMode -replace '^Hardware: ', '' -replace '^Hardware Composed: ', 'Composto: ' -replace '^Composed: ', 'Composto: ') } else { '-' }) } }
        }
    }
}

function Format-UTOverlayRtssText {
    # Plain text for RTSS: one item per line, without the graph.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas)
    return ((@($Linhas | Where-Object { $_.Item -ne 'grafico' }) | ForEach-Object { "$($_.Rotulo) $($_.Valor)".Trim() }) -join "`n")
}

function Find-UTOverlaySensor {
    <#
    .SYNOPSIS
        Ids of the sensors the overlay shows: main CPU temperature and total use, the dedicated GPU
        (the one with the most VRAM) temperature and use, RAM and VRAM in use.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas)
    $ids = @{}
    $first = { param($f) (@($Linhas | Where-Object $f) | Select-Object -First 1) }
    $cpuTemp = & $first { $_.HardwareTipo -eq 'Cpu' -and $_.TipoOriginal -eq 'Temperature' -and $_.NomeOriginal -match '^(Core \(Tctl/Tdie\)|Core \(Tctl\)|CPU Package|Core Max|Package)$' }
    if ($cpuTemp) { $ids.CpuTemp = $cpuTemp.Id }
    $cpuUse = & $first { $_.HardwareTipo -eq 'Cpu' -and $_.TipoOriginal -eq 'Load' -and $_.NomeOriginal -eq 'CPU Total' }
    if ($cpuUse) { $ids.CpuUso = $cpuUse.Id }
    $gpus = @($Linhas | Where-Object { $_.HardwareTipo -like 'Gpu*' } | Group-Object HardwareNome)
    $best = $null; $bestMem = -1
    foreach ($g in $gpus) {
        $mem = (@($g.Group | Where-Object { $_.NomeOriginal -eq 'GPU Memory Total' -or $_.NomeOriginal -eq 'D3D Dedicated Memory Total' }) | Select-Object -First 1)
        $size = $(if ($mem -and $null -ne $mem.Valor) { [double]$mem.Valor } else { 0 })
        if ($size -gt $bestMem) { $bestMem = $size; $best = $g }
    }
    if ($best) {
        $t = (@($best.Group | Where-Object { $_.TipoOriginal -eq 'Temperature' -and $_.NomeOriginal -eq 'GPU Core' }) | Select-Object -First 1)
        $u = (@($best.Group | Where-Object { $_.TipoOriginal -eq 'Load' -and $_.NomeOriginal -eq 'GPU Core' }) | Select-Object -First 1)
        $v = (@($best.Group | Where-Object { $_.TipoOriginal -eq 'SmallData' -and $_.NomeOriginal -in 'GPU Memory Used', 'D3D Dedicated Memory Used' }) | Select-Object -First 1)
        if ($t) { $ids.GpuTemp = $t.Id }
        if ($u) { $ids.GpuUso = $u.Id }
        if ($v) { $ids.Vram = $v.Id }
    }
    $ram = & $first { $_.HardwareTipo -eq 'Memory' -and $_.TipoOriginal -eq 'Data' -and $_.NomeOriginal -eq 'Memory Used' -and $_.HardwareNome -match '^(Total|Generic|Physical) Memory$' }
    if ($ram) { $ids.Ram = $ram.Id }
    return $ids
}
#endregion

#region PresentMon
function Get-UTPresentMonPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path (Join-Path (Get-UTPath -Name Tools) 'presentmon') 'PresentMon.exe')
}

function Test-UTPresentMon {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return (Test-Path -LiteralPath (Get-UTPresentMonPath))
}

function Install-UTPresentMon {
    <#
    .SYNOPSIS
        Downloads the PresentMon console app (x64) of the latest GitHub Release of
        GameTechDev/PresentMon and keeps it only if it is signed by Intel.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    $rel = Get-UTGitHubLatestRelease -Repo 'GameTechDev/PresentMon'
    $asset = (@($rel.Arquivos | Where-Object { $_.Nome -match '^PresentMon-[\d.]+-x64\.exe$' }) | Select-Object -First 1)
    if (-not $asset) { throw 'Não encontrei o PresentMon (x64) na última Release da Intel.' }
    if (-not $PSCmdlet.ShouldProcess("$($asset.Nome) (GitHub GameTechDev/PresentMon)", 'Baixar')) { return $null }
    $tmp = Join-Path (Get-UTPath -Name Temp) $asset.Nome
    [void](Save-UTDownload -Url $asset.Url -Destino $tmp -Confirm:$false)
    $sig = Get-AuthenticodeSignature -LiteralPath $tmp
    if ($sig.Status -ne 'Valid' -or [string]$sig.SignerCertificate.Subject -notmatch 'O=Intel Corporation') {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "O PresentMon baixado não tem a assinatura digital da Intel ($($sig.Status)). Nada foi instalado."
    }
    $target = Get-UTPresentMonPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Move-Item -LiteralPath $tmp -Destination $target -Force
    Write-UTLog -Level Sucesso -Message "PresentMon $($rel.Versao) instalado (oficial da Intel, assinado)."
    return $target
}

function Get-UTPresentMonArgument {
    # Arguments of the capture used by the overlay and the benchmark: CSV on stdout, every process
    # except the Windows compositor, without tracking input (lighter).
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Sessao = 'UpgradeTweaksOverlay', [int]$ProcessoId)
    $a = "--output_stdout --no_console_stats --session_name $Sessao --stop_existing_session --no_track_input --exclude dwm.exe"
    if ($ProcessoId -gt 0) { $a += " --process_id $ProcessoId" }
    return $a
}
#endregion

#region Overlay process
function Get-UTOverlayMutexName { return 'Local\UpgradeTweaks_Overlay' }
function Get-UTOverlayStopEventName { return 'Local\UpgradeTweaks_OverlayStop' }

function Test-UTOverlayRunning {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting((Get-UTOverlayMutexName), [ref]$m)) { $m.Dispose(); return $true }
    return $false
}

function Get-UTAppScriptPath {
    <#
    .SYNOPSIS
        Script file that starts a second Upgrade Tweaks process (the overlay): the one running
        now, copied to %ProgramData%\UpgradeTweaks\app when it is a downloaded release, or
        downloaded again from the release when the program came from "irm | iex".
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $current = [string](Get-UTSyncValue -Key 'ScriptPath')
    $target = Join-Path (Join-Path (Get-UTPath -Name Root) 'app') 'upgradetweaks.ps1'
    if ($current -and (Test-Path -LiteralPath $current)) {
        # From the repository (scripts\start.ps1) the file itself; a release goes to a fixed place
        # (the temp folder of the UAC relaunch is cleaned).
        if ((Split-Path -Leaf $current) -eq 'start.ps1') { return $current }
        if ($current -ne $target -and $PSCmdlet.ShouldProcess($target, 'Copiar o Upgrade Tweaks')) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $current -Destination $target -Force
        }
        return $target
    }
    if ($PSCmdlet.ShouldProcess($target, 'Baixar o Upgrade Tweaks da Release')) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        [void](Save-UTRemoteScript -Url ([string](Get-UTSyncValue -Key 'ReleaseUrl')) -Destination $target)
    }
    return $target
}

function Get-UTOverlayCommand {
    # powershell.exe and its arguments to run the overlay process.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Script)
    return [pscustomobject]@{ Exe = (Get-UTPowerShellPath); Argumentos = ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Overlay' -f $Script) }
}

function Start-UTOverlay {
    <#
    .SYNOPSIS
        Starts the overlay in its own process (hidden, with an icon next to the clock). It keeps
        running with the main window closed. Returns $true when started (or already running).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param()
    if (Test-UTOverlayRunning) { return $true }
    if (-not (Test-UTPresentMon)) { throw 'Instale o PresentMon na aba Overlay primeiro.' }
    $cmd = Get-UTOverlayCommand -Script (Get-UTAppScriptPath -Confirm:$false)
    if (-not $PSCmdlet.ShouldProcess('overlay', 'Ligar')) { return $false }
    Start-Process -FilePath $cmd.Exe -ArgumentList $cmd.Argumentos -WindowStyle Hidden | Out-Null
    Write-UTLog -Level Info -Message 'Overlay ligado.'
    return $true
}

function Stop-UTOverlay {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not (Test-UTOverlayRunning)) { return }
    if (-not $PSCmdlet.ShouldProcess('overlay', 'Desligar')) { return }
    $created = $false
    $ev = New-Object System.Threading.EventWaitHandle ($false, [System.Threading.EventResetMode]::ManualReset, (Get-UTOverlayStopEventName), [ref]$created)
    try {
        [void]$ev.Set()
        $deadline = (Get-Date).AddSeconds(5)
        while ((Test-UTOverlayRunning) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    } finally { [void]$ev.Reset(); $ev.Dispose() }
    Write-UTLog -Level Info -Message 'Overlay desligado.'
}

function Get-UTOverlayTaskName { return 'UpgradeTweaks Overlay' }

function Test-UTOverlayStartup {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool](Get-ScheduledTask -TaskName (Get-UTOverlayTaskName) -ErrorAction SilentlyContinue)
}

function Register-UTOverlayStartup {
    <#
    .SYNOPSIS
        Starts the overlay when the person logs on: a scheduled task with the highest privileges
        (PresentMon reads ETW events, which needs administrator), without the UAC prompt.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess((Get-UTOverlayTaskName), 'Iniciar o overlay com o Windows')) { return }
    # The person using the PC (it can differ from the administrator account that approved the UAC).
    $user = [string](Get-UTSyncValue -Key 'UsuarioAlvoNome')
    if (-not $user) { $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    $cmd = Get-UTOverlayCommand -Script (Get-UTAppScriptPath -Confirm:$false)
    $action = New-ScheduledTaskAction -Execute $cmd.Exe -Argument $cmd.Argumentos
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-UTTaskDefinition -Nome (Get-UTOverlayTaskName) -Acao $action -Gatilho $trigger -Principal $principal -Config $settings -Descricao 'Upgrade Tweaks: overlay de FPS ao entrar no Windows.' -Confirm:$false
    Write-UTLog -Level Sucesso -Message "O overlay vai abrir sozinho quando $user entrar no Windows."
}

function Register-UTTaskDefinition {
    # Thin wrapper of Register-ScheduledTask (its CIM-typed parameters cannot be mocked in tests).
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Nome, [object]$Acao, [object]$Gatilho, [object]$Principal, [object]$Config, [string]$Descricao)
    if ($PSCmdlet.ShouldProcess($Nome, 'Registrar tarefa agendada')) {
        Register-ScheduledTask -TaskName $Nome -Action $Acao -Trigger $Gatilho -Principal $Principal -Settings $Config -Description $Descricao -Force | Out-Null
    }
}

function Unregister-UTOverlayStartup {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not (Test-UTOverlayStartup)) { return }
    if ($PSCmdlet.ShouldProcess((Get-UTOverlayTaskName), 'Não iniciar mais com o Windows')) {
        Unregister-ScheduledTask -TaskName (Get-UTOverlayTaskName) -Confirm:$false
        Write-UTLog -Level Info -Message 'O overlay não abre mais com o Windows.'
    }
}
#endregion
