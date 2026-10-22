# Design system at run time: theme (system / light / dark) and accent color, Mica on Windows 11,
# the integrated title bar, window placement and page transitions. The XAML of the theme lives in
# xaml\Theme (tokens per theme + control styles); everything refers to the tokens with
# DynamicResource, so switching the token dictionary restyles the whole window at once.

#region Preferences (%AppData%\UpgradeTweaks\ui.json)
function Get-UTUiPreference {
    <#
    .SYNOPSIS
        Window and theme preferences of the person, with defaults for what was never saved.
    #>
    [CmdletBinding()]
    param()
    $defaults = [ordered]@{ Tema = 'sistema'; Destaque = '#7C3AED'; Largura = 1280; Altura = 820; Esquerda = $null; Topo = $null; Maximizada = $false; Pagina = 'Inicio' }
    $saved = $null
    try { $saved = Read-UTJsonFile -Path (Join-Path (Get-UTPath -Name Usuario) 'ui.json') } catch { $saved = $null }
    if ($saved -is [System.Collections.IDictionary]) { foreach ($k in @($saved.Keys)) { $defaults[$k] = $saved[$k] } }
    return $defaults
}

function Save-UTUiPreference {
    <#
    .SYNOPSIS
        Merges -Valores into ui.json. Never fails the interface: a write error is only logged.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Valores)
    $all = Get-UTUiPreference
    foreach ($k in $Valores.Keys) { $all[$k] = $Valores[$k] }
    if (-not $PSCmdlet.ShouldProcess('ui.json', 'Salvar preferências da janela')) { return }
    try { Write-UTJsonFile -Path (Join-Path (Get-UTPath -Name Usuario) 'ui.json') -InputObject $all -Confirm:$false } catch { Write-UTLog -Level Aviso -Message 'Não foi possível salvar as preferências da janela.' -Detalhe $_.Exception.Message }
}
#endregion

#region Theme
function Resolve-UTUiThemeName {
    <#
    .SYNOPSIS
        'claro' or 'escuro' for a preference ('sistema' follows "Modo do app" of Windows).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Tema = 'sistema')
    if ($Tema -in 'claro', 'escuro') { return $Tema }
    $v = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction SilentlyContinue
    if ($v -and [int]$v.AppsUseLightTheme -eq 1) { return 'claro' }
    return 'escuro'
}

function ConvertTo-UTUiColor {
    param([Parameter(Mandatory)][string]$Hex)
    return [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
}

function Get-UTUiAccentSet {
    <#
    .SYNOPSIS
        The accent brushes for a color: base, hover, light (text/icons on the background) and soft
        (selection highlight), tuned for the light or dark theme.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hex, [Parameter(Mandatory)][ValidateSet('claro', 'escuro')][string]$Tema)
    $c = ConvertTo-UTUiColor $Hex
    $mix = {
        param($color, [double]$t, [byte]$target)
        [System.Windows.Media.Color]::FromRgb([byte]($color.R + ($target - $color.R) * $t), [byte]($color.G + ($target - $color.G) * $t), [byte]($color.B + ($target - $color.B) * $t))
    }
    if ($Tema -eq 'escuro') {
        $hover = & $mix $c 0.15 255
        $light = & $mix $c 0.35 255
        $softA = 0x33
    } else {
        $hover = & $mix $c 0.12 0
        $light = & $mix $c 0.15 0
        $softA = 0x1F
    }
    $soft = [System.Windows.Media.Color]::FromArgb($softA, $c.R, $c.G, $c.B)
    $brush = { param($x) $b = New-Object System.Windows.Media.SolidColorBrush $x; $b.Freeze(); $b }
    return @{ AccentBrush = (& $brush $c); AccentHoverBrush = (& $brush $hover); AccentLightBrush = (& $brush $light); AccentSoftBrush = (& $brush $soft) }
}

function Set-UTUiTheme {
    <#
    .SYNOPSIS
        Puts the design system into a window: control styles once, the token dictionary of the
        theme (replaced on every call) and the accent color on top.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Styles a window; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.FrameworkElement]$Janela,
        [string]$Tema = 'sistema',
        [string]$Destaque = '#7C3AED'
    )
    $name = Resolve-UTUiThemeName -Tema $Tema
    $tokenFile = $(if ($name -eq 'claro') { 'Theme\Claro' } else { 'Theme\Escuro' })
    $tokens = [Windows.Markup.XamlReader]::Parse((Get-UTXamlText -Name $tokenFile))
    $merged = $Janela.Resources.MergedDictionaries
    if ($merged.Count -ge 2) {
        $merged[0] = $tokens
    } else {
        $merged.Clear()
        $merged.Add($tokens)
        $merged.Add([Windows.Markup.XamlReader]::Parse((Get-UTXamlText -Name 'Theme\Controles')))
    }
    if ($Destaque -notmatch '^#[0-9A-Fa-f]{6}$') { $Destaque = '#7C3AED' }
    $accent = Get-UTUiAccentSet -Hex $Destaque -Tema $name
    # Cast: a PowerShell-wrapped brush in a ResourceDictionary is not a Brush for WPF.
    foreach ($k in @($accent.Keys)) { $tokens[$k] = [System.Windows.Media.SolidColorBrush]$accent[$k] }
    $Janela.Resources['TemaAtual'] = $name
    if ($Janela -is [System.Windows.Window]) { Set-UTUiWindowDarkMode -Janela $Janela -Escuro ($name -eq 'escuro') }
    return $name
}
#endregion

#region Mica and title bar
function Initialize-UTUiDwmType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.Dwm' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace UpgradeTweaks {
    public static class Dwm {
        [StructLayout(LayoutKind.Sequential)]
        public struct MARGINS { public int Left, Right, Top, Bottom; }
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);
        public static int Set(IntPtr hwnd, int attribute, int value) { return DwmSetWindowAttribute(hwnd, attribute, ref value, 4); }
        public static int ExtendAll(IntPtr hwnd) { var m = new MARGINS { Left = -1, Right = -1, Top = -1, Bottom = -1 }; return DwmExtendFrameIntoClientArea(hwnd, ref m); }
    }
}
'@
}

function Get-UTUiWindowHandle {
    param([Parameter(Mandatory)][System.Windows.Window]$Janela)
    return (New-Object System.Windows.Interop.WindowInteropHelper $Janela).Handle
}

function Set-UTUiWindowDarkMode {
    # Dark title bar / Mica tint follow the theme (DWMWA_USE_IMMERSIVE_DARK_MODE = 20).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Styles a window; nothing changes on the system.')]
    param([Parameter(Mandatory)][System.Windows.Window]$Janela, [bool]$Escuro)
    $hwnd = Get-UTUiWindowHandle -Janela $Janela
    if ($hwnd -eq [IntPtr]::Zero) { return }
    Initialize-UTUiDwmType
    [void][UpgradeTweaks.Dwm]::Set($hwnd, 20, [int]$Escuro)
}

function Get-UTUiBackdropKind {
    <#
    .SYNOPSIS
        Which backdrop this Windows supports: 'mica' (Windows 11 22H2+), 'mica-antigo' (Windows 11
        21H2, undocumented attribute) or 'nenhum' (Windows 10: solid background).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int]$Build = [Environment]::OSVersion.Version.Build)
    if ($Build -ge 22621) { return 'mica' }
    if ($Build -ge 22000) { return 'mica-antigo' }
    return 'nenhum'
}

function Enable-UTUiBackdrop {
    <#
    .SYNOPSIS
        Mica behind the window on Windows 11 (the sidebar becomes translucent); Windows 10 keeps the
        solid background of the theme. Called once the window has a handle (SourceInitialized).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Styles a window; nothing changes on the system.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][System.Windows.Window]$Janela)
    $kind = Get-UTUiBackdropKind
    if ($kind -eq 'nenhum') { return $false }
    $hwnd = Get-UTUiWindowHandle -Janela $Janela
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    Initialize-UTUiDwmType
    try {
        $source = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
        $source.CompositionTarget.BackgroundColor = [System.Windows.Media.Colors]::Transparent
        [void][UpgradeTweaks.Dwm]::ExtendAll($hwnd)
        $hr = $(if ($kind -eq 'mica') { [UpgradeTweaks.Dwm]::Set($hwnd, 38, 2) } else { [UpgradeTweaks.Dwm]::Set($hwnd, 1029, 1) })
        if ($hr -ne 0) { return $false }
        # Transparent window and sidebar let Mica through; the content keeps its own surface.
        $clear = [System.Windows.Media.SolidColorBrush](New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Colors]::Transparent))
        $Janela.Resources['WindowBrush'] = $clear
        $Janela.Resources['SideBrush'] = $clear
        return $true
    } catch {
        Write-UTLog -Level Debug -Message 'Mica não disponível; usando fundo sólido.' -Detalhe $_.Exception.Message
        return $false
    }
}

function Initialize-UTUiChrome {
    <#
    .SYNOPSIS
        Buttons of the integrated title bar (minimize, maximize/restore, close) and the margin a
        maximized WindowChrome window needs so nothing goes off screen.
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $c = $ui.C
    $c['MinButton'].Add_Click({ (Get-UTUi).Window.WindowState = 'Minimized' })
    $c['MaxButton'].Add_Click({
            $w = (Get-UTUi).Window
            $w.WindowState = $(if ($w.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
        })
    $c['CloseButton'].Add_Click({ (Get-UTUi).Window.Close() })
    $ui.Window.Add_StateChanged({
            param($w, $e) $null = $e
            $u = Get-UTUi
            $max = ($w.WindowState -eq 'Maximized')
            $u.C['RootGrid'].Margin = $(if ($max) { New-Object System.Windows.Thickness 7 } else { New-Object System.Windows.Thickness 0 })
            $u.C['MaxButton'].Content = $(if ($max) { [string][char]0xE923 } else { [string][char]0xE922 })
            $u.C['MaxButton'].ToolTip = $(if ($max) { 'Restaurar' } else { 'Maximizar' })
        })
}
#endregion

#region Window placement and motion
function Restore-UTUiWindowPlacement {
    <#
    .SYNOPSIS
        Size, position and maximized state from the last session, kept inside the visible screen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Window]$Janela, [Parameter(Mandatory)][System.Collections.IDictionary]$Preferencias)
    $p = $Preferencias
    if ($p.Largura -and [double]$p.Largura -ge $Janela.MinWidth) { $Janela.Width = [double]$p.Largura }
    if ($p.Altura -and [double]$p.Altura -ge $Janela.MinHeight) { $Janela.Height = [double]$p.Altura }
    if ($null -ne $p.Esquerda -and $null -ne $p.Topo) {
        $left = [double]$p.Esquerda; $top = [double]$p.Topo
        $vs = @{ L = [System.Windows.SystemParameters]::VirtualScreenLeft; T = [System.Windows.SystemParameters]::VirtualScreenTop; W = [System.Windows.SystemParameters]::VirtualScreenWidth; H = [System.Windows.SystemParameters]::VirtualScreenHeight }
        if ($left -ge $vs.L -and $top -ge $vs.T -and ($left + 200) -le ($vs.L + $vs.W) -and ($top + 100) -le ($vs.T + $vs.H)) {
            $Janela.WindowStartupLocation = 'Manual'
            $Janela.Left = $left
            $Janela.Top = $top
        }
    }
    if ($p.Maximizada) { $Janela.WindowState = 'Maximized' }
}

function Save-UTUiWindowPlacement {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Saves user preferences only.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.Window]$Janela, [string]$Pagina)
    $b = $Janela.RestoreBounds
    $values = [ordered]@{ Maximizada = ($Janela.WindowState -eq 'Maximized') }
    if (-not $b.IsEmpty) { $values.Largura = [int]$b.Width; $values.Altura = [int]$b.Height; $values.Esquerda = [int]$b.Left; $values.Topo = [int]$b.Top }
    if ($Pagina -and $Pagina -ne 'Busca') { $values.Pagina = $Pagina }
    Save-UTUiPreference -Valores $values -Confirm:$false
}

function Test-UTUiMotion {
    # $false when "Mostrar animações no Windows" is off (the interface then skips its animations).
    return [bool][System.Windows.SystemParameters]::ClientAreaAnimation
}

function Invoke-UTUiPageTransition {
    <#
    .SYNOPSIS
        200 ms ease-out: the new page fades in and slides 8 px up.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Animates a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Windows.UIElement]$Elemento, [System.Windows.Media.TranslateTransform]$Deslocamento)
    if (-not (Test-UTUiMotion)) { $Elemento.Opacity = 1; return }
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'
    $time = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(200))
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation (0.0, 1.0, $time)
    $fade.EasingFunction = $ease
    $Elemento.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    if ($Deslocamento) {
        $slide = New-Object System.Windows.Media.Animation.DoubleAnimation (8.0, 0.0, $time)
        $slide.EasingFunction = $ease
        $Deslocamento.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slide)
    }
}
#endregion

#region Theme button
function Switch-UTUiTheme {
    <#
    .SYNOPSIS
        Theme button of the sidebar: sistema -> claro -> escuro -> sistema. Pages are rebuilt so
        every element takes the new colors.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the look of the interface.')]
    [CmdletBinding()]
    param([string]$Tema)
    $ui = Get-UTUi
    $pref = Get-UTUiPreference
    if (-not $Tema) { $Tema = @{ sistema = 'claro'; claro = 'escuro'; escuro = 'sistema' }[[string]$pref.Tema] }
    if (-not $Tema) { $Tema = 'sistema' }
    [void](Set-UTUiTheme -Janela $ui.Window -Tema $Tema -Destaque ([string]$pref.Destaque))
    Save-UTUiPreference -Valores @{ Tema = $Tema } -Confirm:$false
    Update-UTUiThemeIcon -Tema $Tema
    $current = $ui.PaginaAtual
    foreach ($k in @($ui.Pages.Keys)) { [void]$ui.Pages.Remove($k); Remove-UTUiPageRow -Pagina $k }
    if ($current) { Show-UTUiPage -Id $current }
    Show-UTUiStatus ("Tema: " + @{ sistema = 'igual ao Windows'; claro = 'claro'; escuro = 'escuro' }[$Tema])
}

function Update-UTUiThemeIcon {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates a UI element; nothing changes on the system.')]
    param([string]$Tema)
    $ui = Get-UTUi
    if (-not $ui.C.ContainsKey('ThemeIcon')) { return }
    $glyph = @{ sistema = 0xE793; claro = 0xE706; escuro = 0xE708 }[$Tema]
    if (-not $glyph) { $glyph = 0xE793 }
    $ui.C['ThemeIcon'].Text = [string][char]$glyph
    $ui.C['ThemeButton'].ToolTip = 'Tema: ' + @{ sistema = 'igual ao Windows'; claro = 'claro'; escuro = 'escuro' }[$Tema] + ' (clique para trocar)'
}
#endregion
