# Overlay: the visual (shared by the overlay window and the live preview of the editor), the
# overlay process (-Overlay: click-through window over the game, icon next to the clock, global
# hotkeys) and the Overlay tab with the visual editor.

#region Visual (window and preview)
function ConvertTo-UTOverlayBrush {
    param([string]$Hex, [double]$Alfa = 1)
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb([byte][math]::Round(255 * $Alfa), $c.R, $c.G, $c.B))
    $b.Freeze()
    return $b
}

function New-UTOverlayVisual {
    <#
    .SYNOPSIS
        The overlay for a profile: semi-transparent card with the items in the profile order.
        Returns the root element plus the text blocks and the graph, for Update-UTOverlayVisual.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Perfil)
    $fg = ConvertTo-UTOverlayBrush $Perfil.CorTexto
    $muted = ConvertTo-UTOverlayBrush $Perfil.CorTexto 0.68
    $accent = ConvertTo-UTOverlayBrush $Perfil.CorDestaque
    $font = New-Object System.Windows.Media.FontFamily 'Segoe UI Variable Display, Segoe UI'
    $text = {
        param([string]$s, [double]$size, $brush, [string]$weight = 'Normal')
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $s; $tb.FontSize = $size; $tb.Foreground = $brush; $tb.FontFamily = $font
        $tb.FontWeight = [System.Windows.FontWeights]::$weight
        $tb.VerticalAlignment = 'Center'
        return $tb
    }
    $root = New-Object System.Windows.Controls.Border
    $root.CornerRadius = 8
    $root.Padding = '10,6,10,7'
    $root.Background = ConvertTo-UTOverlayBrush '#000000' $Perfil.Fundo
    $root.Opacity = $Perfil.Opacidade
    $root.LayoutTransform = New-Object System.Windows.Media.ScaleTransform ($Perfil.Escala, $Perfil.Escala)
    $root.SnapsToDevicePixels = $true
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($root, 'Display')
    $panel = New-Object System.Windows.Controls.StackPanel
    if ($Perfil.Horizontal) { $panel.Orientation = 'Horizontal' }
    $values = @{}
    $graph = $null; $canvas = $null
    $gw = 210.0; $gh = 38.0
    foreach ($item in @($Perfil.Itens)) {
        if ($item -eq 'grafico') {
            $canvas = New-Object System.Windows.Controls.Canvas
            $canvas.Width = $(if ($Perfil.Horizontal) { 120 } else { $gw }); $canvas.Height = $(if ($Perfil.Horizontal) { 20 } else { $gh })
            $canvas.Margin = $(if ($Perfil.Horizontal) { '0,0,12,0' } else { '0,4,0,2' })
            $canvas.ClipToBounds = $true
            $base = New-Object System.Windows.Shapes.Line
            $base.X1 = 0; $base.X2 = $canvas.Width; $base.Y1 = $canvas.Height - 0.5; $base.Y2 = $canvas.Height - 0.5
            $base.Stroke = ConvertTo-UTOverlayBrush $Perfil.CorTexto 0.2
            $base.StrokeThickness = 1
            [void]$canvas.Children.Add($base)
            $graph = New-Object System.Windows.Shapes.Polyline
            $graph.Stroke = $accent
            $graph.StrokeThickness = 1.4
            $graph.StrokeLineJoin = 'Round'
            [void]$canvas.Children.Add($graph)
            [void]$panel.Children.Add($canvas)
            continue
        }
        $label = @{ fps = 'FPS'; lows = '1% / 0,1%'; frametime = 'Frametime'; cpu = 'CPU'; gpu = 'GPU'; ram = 'RAM'; vram = 'VRAM'; relogio = 'Hora'; modo = 'Modo' }[$item]
        $isFps = ($item -eq 'fps')
        $valueSize = $(if ($isFps) { $(if ($Perfil.Horizontal) { 17 } else { 24 }) } else { 13 })
        $value = & $text '-' $valueSize $(if ($isFps) { $accent } else { $fg }) 'SemiBold'
        $lab = & $text $label 11 $muted
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        if ($Perfil.Horizontal) {
            $lab.Margin = '0,0,5,0'
            $row.Margin = '0,0,12,0'
            [void]$row.Children.Add($lab); [void]$row.Children.Add($value)
        } else {
            $lab.Width = 70
            [void]$row.Children.Add($lab); [void]$row.Children.Add($value)
        }
        $values[$item] = $value
        [void]$panel.Children.Add($row)
    }
    $root.Child = $panel
    return @{ Raiz = $root; Valores = $values; Grafico = $graph; Canvas = $canvas; Perfil = $Perfil; Escala = 0 }
}

function Update-UTOverlayVisual {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Visual, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas, [AllowNull()][object]$Quadros)
    foreach ($l in $Linhas) {
        $tb = $Visual.Valores[$l.Item]
        if ($tb -and $tb.Text -ne $l.Valor) { $tb.Text = $l.Valor }
    }
    if ($Visual.Grafico) {
        $data = $(if ($Quadros) { [double[]]$Quadros.Graph } else { [double[]]@() })
        $c = $Visual.Canvas
        $w = $c.Width; $h = $c.Height
        if ($data.Count -lt 2) { $Visual.Grafico.Points = $null; return }
        $pts = [UpgradeTweaks.Overlay.FrameMath]::Downsample($data, [int]($w / 1.5))
        # Fixed scale while the frame times fit, so the line does not jump around.
        $top = [UpgradeTweaks.Overlay.FrameMath]::Max($pts) * 1.15
        $scale = 16.7
        foreach ($s in 8.4, 16.7, 33.4, 66.7, 100, 200, 1000) { $scale = $s; if ($top -le $s) { break } }
        $points = New-Object System.Windows.Media.PointCollection $pts.Count
        $step = $w / ($pts.Count - 1)
        for ($i = 0; $i -lt $pts.Count; $i++) { $points.Add((New-Object System.Windows.Point (($i * $step), ($h - 1 - [math]::Min($h - 2, ($pts[$i] / $scale) * ($h - 2)))))) }
        $points.Freeze()
        $Visual.Grafico.Points = $points
    }
}
#endregion

#region Overlay process (-Overlay)
function Get-UTOverlayHost { return (Get-UTSyncValue -Key 'OverlayHost') }

function Start-UTOverlayHost {
    <#
    .SYNOPSIS
        Body of the overlay process: click-through window always on top, icon next to the clock,
        hotkeys and the PresentMon capture. Returns when the overlay is closed (tray menu, the
        main window or Stop-UTOverlay).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Opens the overlay window; it only reads (ETW and sensors).')]
    [CmdletBinding()]
    [OutputType([int])]
    param()
    $created = $false
    $mutex = New-Object System.Threading.Mutex ($true, (Get-UTOverlayMutexName), [ref]$created)
    if (-not $created) { $mutex.Dispose(); Write-UTLog -Level Info -Message 'O overlay já está aberto.'; return 0 }
    $stop = New-Object System.Threading.EventWaitHandle ($false, [System.Threading.EventResetMode]::ManualReset, (Get-UTOverlayStopEventName))
    [void]$stop.Reset()
    $o = $null
    try {
        Initialize-UTOverlayNative
        # Per-monitor DPI before WPF loads: crisp text on every monitor of a mixed setup.
        [void][UpgradeTweaks.Overlay.Native]::EnablePerMonitorDpi()
        try { [AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false) } catch { $null = $_ }
        Import-UTUiAssembly
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        Initialize-UTOverlayHotkeyType
        $cfg = Get-UTOverlayConfig
        $o = @{
            Config = $cfg; ConfigHora = (Get-UTOverlayConfigTime); Parar = $stop; Visivel = $true; Janela = $null; Hwnd = [IntPtr]::Zero
            Visual = $null; PerfilNome = ''; Sessao = $null; Atalhos = $null; Bandeja = $null; Timer = $null; FgPid = 0; FgNome = ''
            Nomes = @{}; Avisados = @{}; Posicao = ''; SensorIds = $null; RtssAtivo = $false; UltimoTopo = [datetime]::MinValue; Tick = 0
            Benchmark = $null
        }
        $UTSync['OverlayHost'] = $o

        $w = New-Object System.Windows.Window
        $w.WindowStyle = 'None'; $w.AllowsTransparency = $true; $w.Background = [System.Windows.Media.Brushes]::Transparent
        $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false; $w.Focusable = $false
        $w.SizeToContent = 'WidthAndHeight'; $w.ResizeMode = 'NoResize'; $w.Left = -32000; $w.Top = -32000
        $w.Title = 'Upgrade Tweaks overlay'
        $w.Add_SourceInitialized({
                param($win, $e) $null = $e
                $h = Get-UTOverlayHost
                $h.Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
                [UpgradeTweaks.Overlay.Native]::MakeClickThrough($h.Hwnd)
                $h.Atalhos = New-Object UpgradeTweaks.Overlay.HotkeyListener
                $h.Atalhos.Attach($h.Hwnd)
                Register-UTOverlayHotkey
            })
        $o.Janela = $w
        Set-UTOverlayProfileVisual -Nome ([string]$cfg.PerfilAtual)
        $o.Bandeja = New-UTOverlayTray
        Start-UTOverlayCapture
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($cfg.IntervaloMs)
        $timer.Add_Tick({ try { Update-UTOverlayHost } catch { Write-UTLog -Level Aviso -Message 'Falha ao atualizar o overlay.' -Detalhe $_.Exception.Message } })
        $o.Timer = $timer
        $w.Show()
        $w.Visibility = 'Hidden'
        $timer.Start()
        Write-UTLog -Level Info -Message 'Overlay aberto.'
        [System.Windows.Threading.Dispatcher]::Run()
    } catch {
        Write-UTLog -Level Erro -Message 'O overlay não abriu.' -Detalhe $_.Exception.ToString()
        return 1
    } finally {
        if ($o) {
            if ($o.Timer) { $o.Timer.Stop() }
            if ($o.Hwnd -ne [IntPtr]::Zero) { foreach ($id in 1, 2, 3) { [void][UpgradeTweaks.Overlay.Native]::UnregisterHotKey($o.Hwnd, $id) } }
            if ($o.Atalhos) { $o.Atalhos.Detach() }
            if ($o.Sessao) { $o.Sessao.Stop() }
            if ($o.RtssAtivo) { try { [void][UpgradeTweaks.Overlay.Rtss]::Release('UpgradeTweaks') } catch { $null = $_ } }
            if ($o.Bandeja) { $o.Bandeja.Visible = $false; $o.Bandeja.Dispose() }
            try { Stop-UTSensorMonitor -Confirm:$false } catch { $null = $_ }
        }
        $UTSync['OverlayHost'] = $null
        $stop.Dispose()
        try { $mutex.ReleaseMutex() } catch { $null = $_ }
        $mutex.Dispose()
        Write-UTLog -Level Info -Message 'Overlay fechado.'
    }
    return 0
}

function Get-UTOverlayConfigTime {
    $p = Get-UTOverlayConfigPath
    if (Test-Path -LiteralPath $p) { return [IO.File]::GetLastWriteTimeUtc($p) }
    return [datetime]::MinValue
}

function Register-UTOverlayHotkey {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Hotkeys of the overlay window only, released when it closes.')]
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    if ($o.Hwnd -eq [IntPtr]::Zero) { return }
    $ids = @{ Mostrar = 1; ProximoPerfil = 2; Benchmark = 3 }
    foreach ($k in $ids.Keys) {
        [void][UpgradeTweaks.Overlay.Native]::UnregisterHotKey($o.Hwnd, $ids[$k])
        $hk = ConvertTo-UTHotkey -Texto ([string]$o.Config.Atalhos[$k])
        if ($null -eq $hk) { continue }
        if (-not [UpgradeTweaks.Overlay.Native]::RegisterHotKey($o.Hwnd, $ids[$k], [uint32]$hk.Modificadores, [uint32]$hk.Tecla)) {
            Write-UTLog -Level Aviso -Message "O atalho $($hk.Texto) já é usado por outro programa."
        }
    }
}

function Start-UTOverlayCapture {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts a read-only capture (ETW).')]
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    if (-not (Test-UTPresentMon)) {
        if ($o.Bandeja) { $o.Bandeja.ShowBalloonTip(5000, 'Upgrade Tweaks', 'Falta o PresentMon: instale na aba Overlay do Upgrade Tweaks.', 'Warning') }
        return
    }
    if ($null -eq $o.Sessao) { $o.Sessao = New-Object UpgradeTweaks.Overlay.PresentMonSession }
    $o.Sessao.Start((Get-UTPresentMonPath), (Get-UTPresentMonArgument))
}

function Set-UTOverlayProfileVisual {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Nome)
    $o = Get-UTOverlayHost
    $p = $o.Config.Perfis[$Nome]
    if ($null -eq $p) { $Nome = [string]$o.Config.PerfilAtual; $p = $o.Config.Perfis[$Nome] }
    $o.PerfilNome = $Nome
    $o.Visual = New-UTOverlayVisual -Perfil $p
    $o.Janela.Content = $o.Visual.Raiz
    $o.Posicao = ''
    $needSensors = (@($p.Itens | Where-Object { $_ -in 'cpu', 'gpu', 'ram', 'vram' }).Count -gt 0)
    if ($needSensors -and (Get-UTSensorSetup).Pronto) {
        try { Start-UTSensorMonitor -IntervaloMs 1000 -Confirm:$false } catch { Write-UTLog -Level Aviso -Message 'Sensores indisponíveis no overlay.' -Detalhe $_.Exception.Message }
    }
}

function Get-UTOverlaySensorValue {
    # Values of the sensors of the overlay (ids found once, then read only those).
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    if ($null -eq (Get-UTSyncValue -Key 'Sensores')) { return @{} }
    if ($null -eq $o.SensorIds) {
        $all = @(Get-UTSensorSnapshot -SemTexto)
        if ($all.Count -eq 0) { return @{} }
        $o.SensorIds = Find-UTOverlaySensor -Linhas $all
        $set = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($v in $o.SensorIds.Values) { [void]$set.Add([string]$v) }
        $o.SensorSet = $set
    }
    $rows = @(Get-UTSensorSnapshot -SemTexto -Ids $o.SensorSet)
    $byId = @{}
    foreach ($r in $rows) { $byId[[string]$r.Id] = $r.Valor }
    $out = @{}
    foreach ($k in @($o.SensorIds.Keys)) { $out[$k] = $byId[[string]$o.SensorIds[$k]] }
    return $out
}

function Update-UTOverlayHost {
    <#
    .SYNOPSIS
        Tick of the overlay: stop request, new settings, hotkeys, the game in the foreground and
        its profile, the exclusive full screen warning, texts, graph, position and RTSS.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates the overlay window; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    if ($null -eq $o) { return }
    if ($o.Parar.WaitOne(0)) { Close-UTOverlayHost; return }
    $o.Tick++
    $time = Get-UTOverlayConfigTime
    if ($time -ne $o.ConfigHora) {
        $o.ConfigHora = $time
        $o.Config = Get-UTOverlayConfig
        $o.Timer.Interval = [TimeSpan]::FromMilliseconds($o.Config.IntervaloMs)
        Register-UTOverlayHotkey
        Set-UTOverlayProfileVisual -Nome $o.PerfilNome
        Update-UTOverlayTrayMenu
    }
    $cfg = $o.Config
    if ($o.Atalhos) {
        foreach ($id in $o.Atalhos.Drain()) {
            switch ($id) {
                1 { $o.Visivel = -not $o.Visivel }
                2 { Switch-UTOverlayProfile }
                3 { if (Get-Command -Name Switch-UTOverlayBenchmark -ErrorAction SilentlyContinue) { Switch-UTOverlayBenchmark } }
            }
        }
    }
    if ($o.Sessao -and -not $o.Sessao.Running -and $o.Tick % 20 -eq 0) { Start-UTOverlayCapture }

    $fg = [UpgradeTweaks.Overlay.Native]::ForegroundProcessId()
    if ($fg -ne $o.FgPid) {
        $o.FgPid = $fg
        if (-not $o.Nomes.ContainsKey($fg)) {
            $n = ''
            try { $n = ([System.Diagnostics.Process]::GetProcessById($fg).ProcessName + '.exe').ToLowerInvariant() } catch { $n = '' }
            $o.Nomes[$fg] = $n
        }
        $o.FgNome = $o.Nomes[$fg]
    }
    $stats = $null
    if ($o.Sessao) {
        $p = $cfg.Perfis[$o.PerfilNome]
        $graphMs = $(if ($p) { 1000.0 * $p.GraficoSegundos } else { 5000.0 })
        $stats = $o.Sessao.GetStats($fg, 1000, 1000.0 * $cfg.JanelaLowsSegundos, $graphMs)
    }
    $notGame = @('explorer.exe', 'powershell.exe', 'pwsh.exe', 'searchhost.exe', 'shellexperiencehost.exe', 'startmenuexperiencehost.exe', 'textinputhost.exe', 'lockapp.exe', '')
    $inGame = ($null -ne $stats -and $stats.Frames -ge 30 -and $stats.SecondsSinceLastFrame -lt 2 -and $notGame -notcontains $o.FgNome)

    $want = $(if ($inGame) { Resolve-UTOverlayProfile -Config $cfg -Processo $o.FgNome } else { [string]$cfg.PerfilAtual })
    if ($want -ne $o.PerfilNome) { Set-UTOverlayProfileVisual -Nome $want }

    if ($inGame -and -not $o.Avisados.ContainsKey($fg)) {
        $exclusive = ([UpgradeTweaks.Overlay.Native]::IsExclusiveFullscreen() -or [string]$stats.PresentMode -like '*Legacy*')
        if ($exclusive) {
            $o.Avisados[$fg] = $true
            $tip = 'O jogo está em tela cheia exclusiva: o overlay não aparece por cima. Use "Tela cheia sem bordas" no jogo' + $(if ($cfg.Rtss) { '.' } else { ' ou ligue o RTSS na aba Overlay.' })
            if ($o.Bandeja) { $o.Bandeja.ShowBalloonTip(6000, 'Upgrade Tweaks: overlay', $tip, 'Info') }
            Write-UTLog -Level Aviso -Message "Overlay: $($o.FgNome) em tela cheia exclusiva."
        }
    }

    $show = ($o.Visivel -and ($inGame -or -not $cfg.SoEmJogo))
    $lines = @()
    if ($show -or $cfg.Rtss) {
        $sensors = Get-UTOverlaySensorValue
        $lines = @(Get-UTOverlayLine -Perfil $cfg.Perfis[$o.PerfilNome] -Quadros $(if ($inGame) { $stats } else { $null }) -Sensores $sensors)
    }
    $win = $o.Janela
    if ($show) {
        Update-UTOverlayVisual -Visual $o.Visual -Linhas $lines -Quadros $(if ($inGame) { $stats } else { $null })
        if ($win.Visibility -ne 'Visible') { $win.Visibility = 'Visible' }
        Set-UTOverlayWindowPosition -NoJogo:$inGame
    } elseif ($win.Visibility -eq 'Visible') {
        $win.Visibility = 'Hidden'
    }
    if ($cfg.Rtss -and $inGame -and $o.Visivel) {
        $o.RtssAtivo = [UpgradeTweaks.Overlay.Rtss]::Write('UpgradeTweaks', (Format-UTOverlayRtssText -Linhas $lines))
    } elseif ($o.RtssAtivo) {
        [void][UpgradeTweaks.Overlay.Rtss]::Release('UpgradeTweaks')
        $o.RtssAtivo = $false
    }
}

function Set-UTOverlayWindowPosition {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Moves the overlay window only.')]
    [CmdletBinding()]
    param([switch]$NoJogo)
    $o = Get-UTOverlayHost
    $p = $o.Config.Perfis[$o.PerfilNome]
    $mon = $null
    switch -Regex ([string]$p.Monitor) {
        '^jogo$' { $mon = [UpgradeTweaks.Overlay.Native]::MonitorOfForeground() }
        '^principal$' { $mon = (@([UpgradeTweaks.Overlay.Native]::GetMonitors() | Where-Object Primary) | Select-Object -First 1) }
        default { $dev = [string]$p.Monitor; $mon = (@([UpgradeTweaks.Overlay.Native]::GetMonitors() | Where-Object { $_.Device -eq $dev }) | Select-Object -First 1) }
    }
    if ($null -eq $mon) { $mon = (@([UpgradeTweaks.Overlay.Native]::GetMonitors()) | Select-Object -First 1) }
    if ($null -eq $mon) { return }
    # A game covers the whole monitor; otherwise keep out of the taskbar.
    $area = $(if ($NoJogo) { [pscustomobject]@{ Left = $mon.Left; Top = $mon.Top; Right = $mon.Right; Bottom = $mon.Bottom } } else { [pscustomobject]@{ Left = $mon.WorkLeft; Top = $mon.WorkTop; Right = $mon.WorkRight; Bottom = $mon.WorkBottom } })
    $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($o.Janela)
    $wPx = $o.Janela.ActualWidth * $dpi.DpiScaleX
    $hPx = $o.Janela.ActualHeight * $dpi.DpiScaleY
    $pos = Get-UTOverlayPosition -Area $area -Largura $wPx -Altura $hPx -Posicao $p.Posicao -Margem $p.Margem -Dpi $mon.Dpi
    $key = "$($pos.X),$($pos.Y)"
    # Re-asserted every second: some games and launchers push their own windows to the top.
    if ($key -ne $o.Posicao -or ([datetime]::Now - $o.UltimoTopo).TotalSeconds -ge 1) {
        $o.Posicao = $key
        $o.UltimoTopo = [datetime]::Now
        [UpgradeTweaks.Overlay.Native]::PlaceTopmost($o.Hwnd, $pos.X, $pos.Y)
    }
}

function Switch-UTOverlayProfile {
    # Next profile (hotkey or tray menu), saved as the current one.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the overlay preferences.')]
    [CmdletBinding()]
    param([string]$Nome)
    $o = Get-UTOverlayHost
    $names = @($o.Config.Perfis.Keys)
    if (-not $Nome) { $i = [array]::IndexOf($names, $o.PerfilNome); $Nome = $names[($i + 1) % $names.Count] }
    $c = ConvertTo-UTOverlayConfig -Config $o.Config
    $c.PerfilAtual = $Nome
    $o.Config = Save-UTOverlayConfig -Config $c -Confirm:$false
    $o.ConfigHora = Get-UTOverlayConfigTime
    Set-UTOverlayProfileVisual -Nome $Nome
    Update-UTOverlayTrayMenu
    if ($o.Bandeja) { $o.Bandeja.Text = "Upgrade Tweaks: overlay ($Nome)" }
}

function Close-UTOverlayHost {
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    if ($o -and $o.Timer) { $o.Timer.Stop() }
    if ($o -and $o.Janela) { $o.Janela.Close() }
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}

function New-UTOverlayTrayIcon {
    # The program icon (purple rounded square with the lightning bolt), drawn at 32 px.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an icon in memory.')]
    [CmdletBinding()]
    param()
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 8
    $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90); $path.AddArc(31 - $r * 2, 0, $r * 2, $r * 2, 270, 90)
    $path.AddArc(31 - $r * 2, 31 - $r * 2, $r * 2, $r * 2, 0, 90); $path.AddArc(0, 31 - $r * 2, $r * 2, $r * 2, 90, 90)
    $path.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0x7C, 0x3A, 0xED))), $path)
    $bolt = [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 18.8, 4), (New-Object System.Drawing.PointF 9.6, 18.4), (New-Object System.Drawing.PointF 16, 18.4), (New-Object System.Drawing.PointF 13.2, 28), (New-Object System.Drawing.PointF 23.2, 12.8), (New-Object System.Drawing.PointF 16.8, 12.8))
    $g.FillPolygon([System.Drawing.Brushes]::White, $bolt)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function New-UTOverlayTray {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds the tray icon of the overlay.')]
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = New-UTOverlayTrayIcon
    $tray.Text = "Upgrade Tweaks: overlay ($($o.Config.PerfilAtual))"
    $tray.ContextMenuStrip = New-Object System.Windows.Forms.ContextMenuStrip
    $tray.Visible = $true
    $tray.add_MouseDoubleClick({ $h = Get-UTOverlayHost; $h.Visivel = -not $h.Visivel })
    $o.Bandeja = $tray
    Update-UTOverlayTrayMenu
    return $tray
}

function Update-UTOverlayTrayMenu {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds the tray menu of the overlay.')]
    [CmdletBinding()]
    param()
    $o = Get-UTOverlayHost
    if ($null -eq $o -or $null -eq $o.Bandeja) { return }
    $menu = $o.Bandeja.ContextMenuStrip
    $menu.Items.Clear()
    $toggle = New-Object System.Windows.Forms.ToolStripMenuItem ("Mostrar ou ocultar ($($o.Config.Atalhos.Mostrar))")
    $toggle.add_Click({ $h = Get-UTOverlayHost; $h.Visivel = -not $h.Visivel })
    [void]$menu.Items.Add($toggle)
    $profiles = New-Object System.Windows.Forms.ToolStripMenuItem ('Perfil')
    foreach ($n in @($o.Config.Perfis.Keys)) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem ([string]$n)
        $mi.Checked = ($n -eq $o.Config.PerfilAtual)
        $mi.Tag = [string]$n
        $mi.add_Click({ param($s, $e) $null = $e; Switch-UTOverlayProfile -Nome ([string]$s.Tag) })
        [void]$profiles.DropDownItems.Add($mi)
    }
    [void]$menu.Items.Add($profiles)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $open = New-Object System.Windows.Forms.ToolStripMenuItem ('Abrir o Upgrade Tweaks')
    $open.add_Click({
            try {
                $cmd = Get-UTOverlayCommand -Script (Get-UTAppScriptPath -Confirm:$false)
                Start-Process -FilePath $cmd.Exe -ArgumentList ($cmd.Argumentos -replace ' -WindowStyle Hidden', '' -replace ' -Overlay$', '')
            } catch { Write-UTLog -Level Aviso -Message 'Não foi possível abrir o Upgrade Tweaks.' -Detalhe $_.Exception.Message }
        })
    [void]$menu.Items.Add($open)
    $quit = New-Object System.Windows.Forms.ToolStripMenuItem ('Fechar o overlay')
    $quit.add_Click({ Close-UTOverlayHost })
    [void]$menu.Items.Add($quit)
}
#endregion

#region Overlay tab (editor with live preview)
function New-UTUiPageOverlay {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    Initialize-UTOverlayNative
    $ui = Get-UTUi
    $cfg = Get-UTOverlayConfig
    $e = @{ Config = $cfg; Perfil = [string]$cfg.PerfilAtual; Previa = $null; PreviaHost = $null; Editor = $null; Timer = $null; Salvar = $null; Fase = 0.0; Grafico = (New-Object 'System.Collections.Generic.List[double]') }
    $ui.OverlayEditor = $e
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'Overlay' -Descricao 'FPS, 1% e 0,1% low, frametime e sensores por cima do jogo. Os quadros vêm do PresentMon oficial da Intel, que lê os eventos do Windows (ETW): nada é injetado no jogo.'))

    $installed = Test-UTPresentMon
    $running = Test-UTOverlayRunning
    $pmRight = $null
    if (-not $installed) {
        $pmRight = New-UTUiButton 'Baixar PresentMon' -Estilo Primario -Icone 'E896' -Margem '0' -AoClicar {
            param($b, $d) $null = $b, $d
            $ans = Show-UTUiDialog -Titulo 'Baixar o PresentMon?' -Mensagem 'O PresentMon é a ferramenta oficial da Intel para medir quadros (código aberto, cerca de 1 MB, da Release do GitHub GameTechDev/PresentMon). Ele só é guardado se tiver a assinatura digital da Intel.' -Tipo pergunta -Botoes @('Baixar', 'Cancelar')
            if ($ans -ne 'Baixar') { return }
            Invoke-UTUiAction -Nome 'Baixando o PresentMon' -Exclusivo -Script { Install-UTPresentMon -Confirm:$false } -Depois {
                param($r, $dd) $null = $r, $dd
                Reset-UTUiOverlayPage
            }
        }
    }
    $runRight = New-UTUiButton $(if ($running) { 'Desligar' } else { 'Ligar o overlay' }) -Estilo $(if ($running) { 'Normal' } else { 'Primario' }) -Margem '0' -AoClicar {
        param($b, $d) $null = $b, $d
        if (Test-UTOverlayRunning) { Stop-UTOverlay -Confirm:$false } else { [void](Start-UTOverlay -Confirm:$false) }
        Start-Sleep -Milliseconds 600
        Reset-UTUiOverlayPage
    }
    $runRight.IsEnabled = $installed
    $switch = {
        param([string]$Chave, [string]$Dica)
        New-UTUiSwitch -Marcado ([bool]$cfg[$Chave]) -Dados $Chave -Dica $Dica -AoMudar {
            param($s, $k)
            $ed = (Get-UTUi).OverlayEditor
            $ed.Config[$k] = [bool]$s.IsChecked
            Save-UTUiOverlayConfig
        }
    }
    $startup = New-UTUiSwitch -Marcado (Test-UTOverlayStartup) -Dica 'Abrir com o Windows' -AoMudar {
        param($s, $d) $null = $d
        if ($s.IsChecked) {
            if (Test-UTUiSimulacao -Acao 'criar a tarefa agendada que abre o overlay ao entrar no Windows.') { $s.IsChecked = $false; return }
            Invoke-UTUiAction -Nome 'Abrir o overlay com o Windows' -Script { Register-UTOverlayStartup -Confirm:$false } -Sucesso 'O overlay vai abrir sozinho ao entrar no Windows.'
        } else {
            Invoke-UTUiAction -Nome 'Não abrir o overlay com o Windows' -Script { Unregister-UTOverlayStartup -Confirm:$false } -Sucesso 'O overlay não abre mais com o Windows.'
        }
    }
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Overlay' -Linhas @(
                (New-UTUiRow -Titulo 'PresentMon' -Subtitulo $(if ($installed) { 'Instalado. Oficial da Intel, com assinatura digital verificada.' } else { 'Necessário para medir os quadros. Cerca de 1 MB.' }) -Icone 'E9D9' -IconeCor 'IconBlue' -Direita $pmRight)
                (New-UTUiRow -Titulo $(if ($running) { 'Overlay ligado' } else { 'Overlay desligado' }) -Subtitulo "Fica ao lado do relógio do Windows e continua com esta janela fechada. $($cfg.Atalhos.Mostrar) mostra ou esconde." -Icone 'E890' -IconeCor 'IconYellow' -Direita $runRight)
                (New-UTUiRow -Titulo 'Abrir com o Windows' -Subtitulo 'Tarefa agendada, sem o aviso do UAC a cada vez' -Icone 'E7E8' -IconeCor 'IconGray' -Direita $startup)
                (New-UTUiRow -Titulo 'Só aparecer em jogo' -Subtitulo 'Some na área de trabalho e em programas que não desenham quadros' -Icone 'E7FC' -IconeCor 'IconGreen' -Direita (& $switch 'SoEmJogo' 'Só aparecer em jogo'))
                (New-UTUiRow -Titulo 'Ligar junto com o Modo Partida' -Subtitulo 'O Modo Partida (aba Warzone) liga o overlay e desliga no fim' -Icone 'E768' -IconeCor 'IconRed' -Direita (& $switch 'ModoPartida' 'Ligar junto com o Modo Partida'))
                (New-UTUiRow -Titulo 'Mostrar também pelo RivaTuner (RTSS)' -Subtitulo 'Para jogos em tela cheia exclusiva, quando o RTSS estiver aberto. O RTSS entra no jogo por conta própria; o Upgrade Tweaks só escreve o texto nele.' -Icone 'E7B3' -IconeCor 'IconOrange' -Direita (& $switch 'Rtss' 'Usar o RTSS'))
            )))

    $editorHost = New-Object System.Windows.Controls.ContentControl
    $e.Editor = $editorHost
    [void]$page.Children.Add($editorHost)
    Show-UTUiOverlayEditor

    $games = New-Object System.Windows.Controls.ContentControl
    $e.Jogos = $games
    [void]$page.Children.Add($games)
    Show-UTUiOverlayGameList

    $keys = foreach ($k in @(@('Mostrar', 'Mostrar ou esconder'), @('ProximoPerfil', 'Próximo perfil'), @('Benchmark', 'Iniciar e parar o benchmark'))) {
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Width = 170; $tb.IsReadOnly = $true; $tb.Text = [string]$cfg.Atalhos[$k[0]]; $tb.Tag = 'Clique e aperte as teclas'
        $tb.DataContext = $k[0]
        $tb.ToolTip = 'Clique e aperte a combinação (ex.: Ctrl+Shift+F10). Delete apaga.'
        $tb.Add_PreviewKeyDown({
                param($s, $ev)
                $key = $(if ($ev.Key -eq 'System') { $ev.SystemKey } else { $ev.Key })
                $ev.Handled = $true
                if ($key -in 'LeftCtrl', 'RightCtrl', 'LeftShift', 'RightShift', 'LeftAlt', 'RightAlt', 'LWin', 'RWin', 'Tab') { return }
                $text = ''
                if ($key -notin 'Delete', 'Back') {
                    $mods = [System.Windows.Input.Keyboard]::Modifiers
                    $parts = @()
                    if ($mods -band [System.Windows.Input.ModifierKeys]::Control) { $parts += 'Ctrl' }
                    if ($mods -band [System.Windows.Input.ModifierKeys]::Shift) { $parts += 'Shift' }
                    if ($mods -band [System.Windows.Input.ModifierKeys]::Alt) { $parts += 'Alt' }
                    $name = [string]$key -replace '^D(\d)$', '$1' -replace '^NumPad(\d)$', 'Num$1' -replace '^Scroll$', 'ScrollLock'
                    $text = (@($parts) + $name) -join '+'
                    if ($null -eq (ConvertTo-UTHotkey -Texto $text)) { Show-UTUiStatus "Atalho inválido: $text. Use Ctrl, Shift ou Alt com uma tecla (ou F13 a F24)."; return }
                }
                $s.Text = $text
                $ed = (Get-UTUi).OverlayEditor
                $ed.Config.Atalhos[[string]$s.DataContext] = $text
                Save-UTUiOverlayConfig
            })
        New-UTUiRow -Titulo $k[1] -Direita $tb
    }
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Atalhos (funcionam dentro do jogo)' -Linhas @($keys) -RecuoSeparador 16 -Rodape 'Tela cheia exclusiva: nenhuma janela fica por cima do jogo (nem esta). Use "Tela cheia sem bordas" ou ligue o RTSS acima. Um overlay por cima do jogo pode tirar o jogo do modo Independent Flip em placas sem plano de sobreposição (MPO); a linha "Modo" do perfil Completo mostra o modo atual.'))

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({ try { Update-UTUiOverlayPreview } catch { Write-UTLog -Level Aviso -Message 'Falha na prévia do overlay.' -Detalhe $_.Exception.Message } })
    $e.Timer = $timer
    $timer.Start()
    return $page
}

function Reset-UTUiOverlayPage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Rebuilds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    if ($ui.OverlayEditor -and $ui.OverlayEditor.Timer) { $ui.OverlayEditor.Timer.Stop() }
    [void]$ui.Pages.Remove('Overlay')
    if ($ui.PaginaAtual -eq 'Overlay') { Show-UTUiPage -Id 'Overlay' }
}

function Save-UTUiOverlayConfig {
    <#
    .SYNOPSIS
        Saves the overlay settings a moment after the last change (a slider fires many changes)
        and refreshes the preview now.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Saves only the overlay preferences.')]
    [CmdletBinding()]
    param([switch]$Agora)
    $e = (Get-UTUi).OverlayEditor
    $e.Previa = $null
    if ($Agora) { $e.Config = Save-UTOverlayConfig -Config $e.Config -Confirm:$false; return }
    if ($null -eq $e.Salvar) {
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(400)
        $t.Add_Tick({ param($s, $ev) $null = $ev; $s.Stop(); $ed = (Get-UTUi).OverlayEditor; $ed.Config = Save-UTOverlayConfig -Config $ed.Config -Confirm:$false })
        $e.Salvar = $t
    }
    $e.Salvar.Stop()
    $e.Salvar.Start()
}

function Show-UTUiOverlayEditor {
    <#
    .SYNOPSIS
        Editor of the selected profile (controls on the left, live preview on the right).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $e = (Get-UTUi).OverlayEditor
    $cfg = $e.Config
    if (-not $cfg.Perfis.Contains($e.Perfil)) { $e.Perfil = [string]$cfg.PerfilAtual }
    $p = $cfg.Perfis[$e.Perfil]
    $combo = {
        param([object[]]$Itens, [object]$Selecionado, [double]$Largura = 190)
        $cb = New-Object System.Windows.Controls.ComboBox
        $cb.Width = $Largura
        foreach ($i in $Itens) { [void]$cb.Items.Add($i) }
        $cb.SelectedItem = $Selecionado
        return $cb
    }

    $profileBox = & $combo @($cfg.Perfis.Keys) $e.Perfil 170
    $profileBox.Add_SelectionChanged({ param($cb, $ev) $null = $ev; if ($null -eq $cb.SelectedItem) { return }; $ed = (Get-UTUi).OverlayEditor; $ed.Perfil = [string]$cb.SelectedItem; $ed.Previa = $null; Show-UTUiOverlayEditor })
    $active = New-UTUiSwitch -Marcado ($cfg.PerfilAtual -eq $e.Perfil) -Dica 'Perfil padrão' -AoMudar {
        param($s, $d) $null = $d
        $ed = (Get-UTUi).OverlayEditor
        if ($s.IsChecked) { $ed.Config.PerfilAtual = $ed.Perfil; Save-UTUiOverlayConfig } elseif ($ed.Config.PerfilAtual -eq $ed.Perfil) { $s.IsChecked = $true }
    }
    $profileTools = New-UTUiWrap -Itens @(
        (New-UTUiButton 'Novo' -Estilo Link -Margem '0,0,14,0' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiOverlayProfileAction -Acao Novo })
        (New-UTUiButton 'Duplicar' -Estilo Link -Margem '0,0,14,0' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiOverlayProfileAction -Acao Duplicar })
        (New-UTUiButton 'Renomear' -Estilo Link -Margem '0,0,14,0' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiOverlayProfileAction -Acao Renomear })
        (New-UTUiButton 'Excluir' -Estilo Link -Margem '0' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiOverlayProfileAction -Acao Excluir })
    )

    $posNames = [ordered]@{ SuperiorEsquerda = 'Canto superior esquerdo'; SuperiorCentro = 'Em cima, no centro'; SuperiorDireita = 'Canto superior direito'; MeioEsquerda = 'Meio, à esquerda'; MeioDireita = 'Meio, à direita'; InferiorEsquerda = 'Canto inferior esquerdo'; InferiorCentro = 'Embaixo, no centro'; InferiorDireita = 'Canto inferior direito' }
    $pos = & $combo @($posNames.Values) $posNames[$p.Posicao]
    $pos.Tag = $posNames
    $pos.Add_SelectionChanged({ param($cb, $ev) $null = $ev; $k = @($cb.Tag.Keys)[$cb.SelectedIndex]; Set-UTUiOverlayValue 'Posicao' $k })
    $monitors = [ordered]@{ jogo = 'O monitor do jogo'; principal = 'O monitor principal' }
    try { foreach ($m in [UpgradeTweaks.Overlay.Native]::GetMonitors()) { $monitors[$m.Device] = "$($m.Device -replace '^\\\\\.\\', '') ($($m.Width) x $($m.Height))" } } catch { $null = $_ }
    $mon = & $combo @($monitors.Values) $(if ($monitors.Contains($p.Monitor)) { $monitors[$p.Monitor] } else { $monitors['jogo'] })
    $mon.Tag = $monitors
    $mon.Add_SelectionChanged({ param($cb, $ev) $null = $ev; $k = @($cb.Tag.Keys)[$cb.SelectedIndex]; Set-UTUiOverlayValue 'Monitor' $k })
    $layout = & $combo @('Vertical (lista)', 'Horizontal (uma linha)') $(if ($p.Horizontal) { 'Horizontal (uma linha)' } else { 'Vertical (lista)' })
    $layout.Add_SelectionChanged({ param($cb, $ev) $null = $ev; Set-UTUiOverlayValue 'Horizontal' ($cb.SelectedIndex -eq 1) })
    $slider = {
        param([string]$Chave, [double]$Min, [double]$Max, [double]$Valor, [double]$Passo)
        $sl = New-Object System.Windows.Controls.Slider
        $sl.Width = 190; $sl.Minimum = $Min; $sl.Maximum = $Max; $sl.Value = $Valor; $sl.SmallChange = $Passo; $sl.LargeChange = $Passo * 5
        $sl.IsSnapToTickEnabled = $true; $sl.TickFrequency = $Passo
        $sl.Tag = $Chave
        $sl.Add_ValueChanged({ param($s, $ev) $null = $ev; Set-UTUiOverlayValue ([string]$s.Tag) ([math]::Round($s.Value, 2)) })
        return $sl
    }
    $accents = New-UTUiWrap
    foreach ($hex in '#A78BFA', '#FFFFFF', '#30D158', '#0A84FF', '#FF9F0A', '#FF375F', '#64D2FF') {
        $dot = New-Object System.Windows.Controls.Button
        $dot.Width = 22; $dot.Height = 22; $dot.Margin = '0,0,8,0'; $dot.Cursor = 'Hand'; $dot.ToolTip = $hex
        $ring = $(if ($p.CorDestaque -eq $hex) { "Stroke='#FFFFFFFF' StrokeThickness='2'" } else { "Stroke='#33000000' StrokeThickness='1'" })
        $dot.Template = [Windows.Markup.XamlReader]::Parse("<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'><Ellipse Fill='$hex' $ring/></ControlTemplate>")
        $dot.Tag = $hex
        $dot.Add_Click({ param($b, $ev) $null = $ev; Set-UTUiOverlayValue 'CorDestaque' ([string]$b.Tag); Show-UTUiOverlayEditor })
        [void]$accents.Children.Add($dot)
    }

    $names = @{ fps = 'FPS'; lows = '1% e 0,1% low'; frametime = 'Frametime médio'; grafico = 'Gráfico de frametime'; cpu = 'CPU: temperatura e uso'; gpu = 'GPU: temperatura e uso'; ram = 'RAM em uso'; vram = 'VRAM em uso'; relogio = 'Relógio'; modo = 'Modo de apresentação (Flip, iFlip...)' }
    $order = @(@($p.Itens) + @(Get-UTOverlayItem | Where-Object { @($p.Itens) -notcontains $_ }))
    $itemRows = foreach ($it in $order) {
        $sw = New-UTUiSwitch -Marcado (@($p.Itens) -contains $it) -Dados $it -Dica $names[$it] -AoMudar {
            param($s, $item)
            $ed = (Get-UTUi).OverlayEditor
            $pp = $ed.Config.Perfis[$ed.Perfil]
            $all = @(@($pp.Itens) + @(Get-UTOverlayItem | Where-Object { @($pp.Itens) -notcontains $_ }))
            $on = @($all | Where-Object { ($_ -eq $item -and $s.IsChecked) -or ($_ -ne $item -and @($pp.Itens) -contains $_) })
            $pp.Itens = $on
            Save-UTUiOverlayConfig
        }
        $up = New-UTUiButton '↑' -Estilo Link -Margem '0,0,10,0' -Dica 'Subir' -Dados $it -AoClicar { param($b, $d) $null = $b; Move-UTUiOverlayItem -Item $d -Direcao -1 }
        $down = New-UTUiButton '↓' -Estilo Link -Margem '0,0,12,0' -Dica 'Descer' -Dados $it -AoClicar { param($b, $d) $null = $b; Move-UTUiOverlayItem -Item $d -Direcao 1 }
        New-UTUiRow -Titulo $names[$it] -Direita (New-UTUiStack -Horizontal -Itens @($up, $down, $sw))
    }

    $controls = New-UTUiStack -Itens @(
        (New-UTUiGroup -RecuoSeparador 16 -Linhas @(
                (New-UTUiRow -Titulo 'Perfil' -Subtitulo 'Cada jogo pode usar um perfil (lista abaixo)' -Direita $profileBox)
                (New-UTUiRowBox $profileTools)
                (New-UTUiRow -Titulo 'Perfil padrão' -Subtitulo 'Usado nos jogos sem perfil próprio' -Direita $active)
                (New-UTUiRow -Titulo 'Posição' -Direita $pos)
                (New-UTUiRow -Titulo 'Monitor' -Direita $mon)
                (New-UTUiRow -Titulo 'Layout' -Direita $layout)
                (New-UTUiRow -Titulo 'Tamanho' -Subtitulo 'Já acompanha a escala (DPI) de cada monitor' -Direita (& $slider 'Escala' 0.5 2.5 $p.Escala 0.05))
                (New-UTUiRow -Titulo 'Opacidade' -Direita (& $slider 'Opacidade' 0.2 1 $p.Opacidade 0.05))
                (New-UTUiRow -Titulo 'Fundo' -Subtitulo '0 = só o texto' -Direita (& $slider 'Fundo' 0 1 $p.Fundo 0.05))
                (New-UTUiRow -Titulo 'Distância da borda' -Direita (& $slider 'Margem' 0 120 $p.Margem 2))
                (New-UTUiRow -Titulo 'Cor de destaque' -Direita $accents)
            ))
        (New-UTUiGroup -Titulo 'O que mostrar (e em que ordem)' -RecuoSeparador 16 -Linhas @($itemRows))
    )
    $preview = New-Object System.Windows.Controls.Border
    $preview.Width = 520; $preview.Height = 300
    $preview.CornerRadius = 12
    $preview.ClipToBounds = $true
    $grad = New-Object System.Windows.Media.LinearGradientBrush
    $grad.StartPoint = '0,0'; $grad.EndPoint = '1,1'
    foreach ($stop in @(@('#FF2B3A4F', 0.0), @('#FF5B6E5A', 0.55), @('#FFB59A6B', 1.0))) { $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($stop[0]), $stop[1]))) }
    $preview.Background = $grad
    $grid = New-Object System.Windows.Controls.Grid
    $preview.Child = $grid
    $e.PreviaHost = $grid
    $e.Previa = $null
    $right = New-UTUiStack -Margem '24,0,0,0' -Itens @(
        (New-UTUiText 'Prévia ao vivo (valores de exemplo)' -Tamanho 12 -Peso SemiBold -Cor MutedBrush -Margem '2,0,0,6')
        $preview
        (New-UTUiText 'O overlay real lê o jogo em primeiro plano e troca o perfil sozinho conforme a lista de jogos.' -Tamanho 11.5 -Cor TertiaryBrush -Quebrar -Margem '2,8,0,0')
    )
    $right.Width = 520
    $right.VerticalAlignment = 'Top'
    $wrap = New-Object System.Windows.Controls.Grid
    foreach ($w in '*', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto })
        [void]$wrap.ColumnDefinitions.Add($cd)
    }
    [void]$wrap.Children.Add($controls)
    [System.Windows.Controls.Grid]::SetColumn($right, 1)
    [void]$wrap.Children.Add($right)
    $e.Editor.Content = New-UTUiStack -Itens @((New-UTUiText 'Editor do perfil' -Tamanho 17 -Peso SemiBold -Margem '0,4,0,12'), $wrap)
    Update-UTUiOverlayPreview
}

function Set-UTUiOverlayValue {
    # One setting of the profile being edited.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the overlay preferences.')]
    param([Parameter(Mandatory)][string]$Chave, [AllowNull()][object]$Valor)
    $ed = (Get-UTUi).OverlayEditor
    $ed.Config.Perfis[$ed.Perfil][$Chave] = $Valor
    Save-UTUiOverlayConfig
}

function Move-UTUiOverlayItem {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the overlay preferences.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Item, [int]$Direcao)
    $e = (Get-UTUi).OverlayEditor
    $p = $e.Config.Perfis[$e.Perfil]
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($i in @($p.Itens)) { $list.Add([string]$i) }
    $at = $list.IndexOf($Item)
    if ($at -lt 0) { return }
    $to = [math]::Min($list.Count - 1, [math]::Max(0, $at + $Direcao))
    if ($to -eq $at) { return }
    $list.RemoveAt($at); $list.Insert($to, $Item)
    $p.Itens = $list.ToArray()
    Save-UTUiOverlayConfig
    Show-UTUiOverlayEditor
}

function Invoke-UTUiOverlayProfileAction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the overlay preferences.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Novo', 'Duplicar', 'Renomear', 'Excluir')][string]$Acao)
    $e = (Get-UTUi).OverlayEditor
    $cfg = $e.Config
    $current = $e.Perfil
    if ($Acao -eq 'Excluir') {
        if ($cfg.Perfis.Count -le 1) { [void](Show-UTUiDialog -Titulo 'Não dá para excluir' -Mensagem 'É preciso ter pelo menos um perfil.' -Tipo info); return }
        if ((Show-UTUiDialog -Titulo "Excluir o perfil $current?" -Mensagem 'Os jogos que usavam este perfil passam a usar o perfil padrão.' -Tipo pergunta -Botoes @('Excluir', 'Cancelar')) -ne 'Excluir') { return }
        $cfg.Perfis.Remove($current)
        $e.Perfil = [string]@($cfg.Perfis.Keys)[0]
    } else {
        $box = New-Object System.Windows.Controls.TextBox
        $box.Width = 300
        $box.Text = $(if ($Acao -eq 'Renomear') { $current } elseif ($Acao -eq 'Duplicar') { "$current (cópia)" } else { 'Meu perfil' })
        $ans = Show-UTUiSheet -Titulo $(@{ Novo = 'Novo perfil'; Duplicar = 'Duplicar perfil'; Renomear = 'Renomear perfil' }[$Acao]) -Mensagem 'Nome do perfil:' -Conteudo $box -Botoes @('OK', 'Cancelar') -Tipo pergunta
        if ($ans -ne 'OK') { return }
        $name = $box.Text.Trim()
        if (-not $name -or $name.Length -gt 40) { Show-UTUiStatus 'Nome inválido (1 a 40 caracteres).'; return }
        if ($cfg.Perfis.Contains($name) -and $name -ne $current) { Show-UTUiStatus "Já existe um perfil chamado $name."; return }
        switch ($Acao) {
            'Novo' { $cfg.Perfis[$name] = New-UTOverlayProfile }
            'Duplicar' { $cfg.Perfis[$name] = ConvertTo-UTOverlayProfile -Perfil $cfg.Perfis[$current] }
            'Renomear' {
                $copy = [ordered]@{}
                foreach ($k in @($cfg.Perfis.Keys)) { $copy[$(if ($k -eq $current) { $name } else { $k })] = $cfg.Perfis[$k] }
                $cfg.Perfis = $copy
                if ($cfg.PerfilAtual -eq $current) { $cfg.PerfilAtual = $name }
                foreach ($g in @($cfg.Jogos.Keys)) { if ($cfg.Jogos[$g] -eq $current) { $cfg.Jogos[$g] = $name } }
            }
        }
        $e.Perfil = $name
    }
    Save-UTUiOverlayConfig -Agora
    Show-UTUiOverlayEditor
    Show-UTUiOverlayGameList
}

function Show-UTUiOverlayGameList {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $e = (Get-UTUi).OverlayEditor
    $cfg = $e.Config
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($g in @($cfg.Jogos.Keys)) {
        $cb = New-Object System.Windows.Controls.ComboBox
        $cb.Width = 170
        foreach ($n in @($cfg.Perfis.Keys)) { [void]$cb.Items.Add($n) }
        $cb.SelectedItem = [string]$cfg.Jogos[$g]
        $cb.Tag = [string]$g
        $cb.Add_SelectionChanged({ param($s, $ev) $null = $ev; $ed = (Get-UTUi).OverlayEditor; $ed.Config.Jogos[[string]$s.Tag] = [string]$s.SelectedItem; Save-UTUiOverlayConfig })
        $del = New-UTUiButton 'Remover' -Estilo Link -Margem '12,0,0,0' -Dados ([string]$g) -AoClicar { param($b, $d) $null = $b; $ed = (Get-UTUi).OverlayEditor; $ed.Config.Jogos.Remove($d); Save-UTUiOverlayConfig -Agora; Show-UTUiOverlayGameList }
        $rows.Add((New-UTUiRow -Titulo ([string]$g) -Icone 'E7FC' -IconeCor 'IconGreen' -Direita (New-UTUiStack -Horizontal -Itens @($cb, $del))))
    }
    $exe = New-Object System.Windows.Controls.TextBox
    $exe.Width = 200; $exe.Tag = 'jogo.exe'
    $prof = New-Object System.Windows.Controls.ComboBox
    $prof.Width = 170
    foreach ($n in @($cfg.Perfis.Keys)) { [void]$prof.Items.Add($n) }
    $prof.SelectedIndex = 0
    $add = New-UTUiButton 'Adicionar' -Margem '12,0,0,0' -Dados @{ Exe = $exe; Perfil = $prof } -AoClicar {
        param($b, $d) $null = $b
        $name = $d.Exe.Text.Trim().ToLowerInvariant()
        if ($name -and -not $name.EndsWith('.exe')) { $name += '.exe' }
        if ($name -notmatch '^[^\\/:*?"<>|]+\.exe$') { Show-UTUiStatus 'Digite o nome do executável do jogo, como cod.exe.'; return }
        $ed = (Get-UTUi).OverlayEditor
        $ed.Config.Jogos[$name] = [string]$d.Perfil.SelectedItem
        Save-UTUiOverlayConfig -Agora
        Show-UTUiOverlayGameList
    }
    $rows.Add((New-UTUiRowBox (New-UTUiStack -Horizontal -Itens @($exe, (New-UTUiText '  usa  ' -Cor MutedBrush), $prof, $add))))
    $e.Jogos.Content = New-UTUiGroup -Titulo 'Perfil automático por jogo' -Linhas $rows.ToArray() -RecuoSeparador 16 -Rodape 'Quando um destes jogos está em primeiro plano, o overlay troca para o perfil escolhido. Os outros usam o perfil padrão.'
}

function Update-UTUiOverlayPreview {
    <#
    .SYNOPSIS
        Live preview of the profile being edited, with made-up but realistic numbers (about 165 FPS
        with a stutter now and then), placed like the real one would be on the screen.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $e = $ui.OverlayEditor
    if ($null -eq $e -or $null -eq $e.PreviaHost) { return }
    if ($ui.PaginaAtual -ne 'Overlay' -and $null -ne $e.Previa) { return }
    $p = $e.Config.Perfis[$e.Perfil]
    if ($null -eq $e.Previa) {
        $e.Previa = New-UTOverlayVisual -Perfil $p
        $r = $e.Previa.Raiz
        $r.HorizontalAlignment = $(switch -Regex ($p.Posicao) { 'Esquerda$' { 'Left' } 'Direita$' { 'Right' } default { 'Center' } })
        $r.VerticalAlignment = $(switch -Regex ($p.Posicao) { '^Superior' { 'Top' } '^Inferior' { 'Bottom' } default { 'Center' } })
        $m = [math]::Round($p.Margem / 2)
        $r.Margin = "$m"
        $e.PreviaHost.Children.Clear()
        [void]$e.PreviaHost.Children.Add($r)
    }
    $e.Fase += 0.25
    $rnd = New-Object System.Random ([int]($e.Fase * 4))
    for ($i = 0; $i -lt 40; $i++) {
        $ms = 6.0 + 0.6 * [math]::Sin(($e.Fase * 10 + $i) / 7) + $rnd.NextDouble() * 0.5
        if ($rnd.Next(0, 140) -eq 0) { $ms = 14 + $rnd.NextDouble() * 6 }
        $e.Grafico.Add($ms)
    }
    while ($e.Grafico.Count -gt 800) { $e.Grafico.RemoveAt(0) }
    $frames = $e.Grafico.ToArray()
    $stats = [pscustomobject]@{
        Fps = [UpgradeTweaks.Overlay.FrameMath]::AverageFps($frames[([math]::Max(0, $frames.Count - 165))..($frames.Count - 1)])
        Low1 = [UpgradeTweaks.Overlay.FrameMath]::LowAverageFps($frames, 0.01); Low01 = [UpgradeTweaks.Overlay.FrameMath]::LowAverageFps($frames, 0.001)
        FrameMs = ($frames | Select-Object -Last 165 | Measure-Object -Average).Average; PresentMode = 'Hardware: Independent Flip'; Graph = $frames
    }
    $sensors = @{ CpuTemp = 61 + 2 * [math]::Sin($e.Fase / 3); CpuUso = 38 + 5 * [math]::Sin($e.Fase); GpuTemp = 64; GpuUso = 97; Ram = 9.8; Vram = 7340 }
    $lines = @(Get-UTOverlayLine -Perfil $p -Quadros $stats -Sensores $sensors)
    Update-UTOverlayVisual -Visual $e.Previa -Linhas $lines -Quadros $stats
}
#endregion
