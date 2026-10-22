# WPF interface core: window loading, background work and the log panel.
#
# Threading: the window lives on this (STA) thread. Everything slow (tweaks, diagnostics,
# winget, NVAPI...) runs in a runspace pool. Workers never touch WPF objects: they return
# results, and a DispatcherTimer on the UI thread collects finished jobs and drains the log
# queue. That keeps the window responsive without cross-thread Dispatcher calls.

#region State and XAML
function Get-UTUi {
    # The interface state (window, controls, jobs, rows) shared by the UI functions.
    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $sync) { return $null }
    return $sync['Ui']
}

function Initialize-UTUiState {
    [CmdletBinding()]
    param()
    $ui = @{
        Window      = $null
        C           = @{}
        Pool        = $null
        Jobs        = New-Object System.Collections.Generic.List[object]
        Timer       = $null
        Pages       = @{}
        Rows        = New-Object System.Collections.Generic.List[object]
        # Pending changes: switched on (to apply) and switched off (to undo).
        Selecionados = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        Desmarcados = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        Sincronizando = $false
        ProgressoAberto = $false
        Estados     = @{}
        Diagnostico = $null
        PaginaAtual = $null
        Navegando   = $false
        EstadosPedidos = $false
        LogLinhas   = New-Object System.Collections.Generic.List[string]
        LogMax      = 2000
        Monitor     = $null
        SheetEstado = $null
        BiosBusca   = $null
        OverlayEditor = $null
    }
    $UTSync['Ui'] = $ui
    if (-not $UTSync.ContainsKey('LogQueue') -or $null -eq $UTSync['LogQueue']) {
        $UTSync['LogQueue'] = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    }
    return $ui
}

function Get-UTXamlText {
    <#
    .SYNOPSIS
        XAML of a window: embedded in the compiled script, or xaml\<Name>.xaml of the repository.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $embedded = Get-Variable -Name UTEmbeddedXaml -ValueOnly -ErrorAction SilentlyContinue
    if ($embedded -and $embedded.ContainsKey($Name)) { return [string]$embedded[$Name] }
    $file = Join-Path (Get-UTSourceRoot) "xaml\$Name.xaml"
    if (-not (Test-Path -LiteralPath $file)) { throw "Arquivo de interface não encontrado: $Name.xaml" }
    return [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
}

function Import-UTUiAssembly {
    [CmdletBinding()]
    param()
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
}

function Get-UTUiWindow {
    <#
    .SYNOPSIS
        Loads a XAML window and returns it with a table of its named controls.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Import-UTUiAssembly
    $text = Get-UTXamlText -Name $Name
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$text)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    # Design system (xaml\Theme) with the theme and accent color the person chose.
    $pref = Get-UTUiPreference
    [void](Set-UTUiTheme -Janela $window -Tema ([string]$pref.Tema) -Destaque ([string]$pref.Destaque))
    $controls = @{}
    foreach ($m in [regex]::Matches($text, 'x:Name="(\w+)"')) {
        $n = $m.Groups[1].Value
        $el = $window.FindName($n)
        if ($el) { $controls[$n] = $el }
    }
    return [pscustomobject]@{ Window = $window; Controles = $controls }
}

function Get-UTUiBrush {
    # A brush of the window theme (BgBrush, CardBrush, AccentBrush, GreenBrush...).
    param([Parameter(Mandatory)][string]$Nome)
    $ui = Get-UTUi
    if ($ui -and $ui.Window) {
        $b = $ui.Window.TryFindResource($Nome)
        if ($b) { return $b }
    }
    # Dark theme values, for elements built before a window has the design system.
    $fallback = @{ BgBrush = '#1C1C1E'; CardBrush = '#2C2C2E'; BorderBrush = '#3A3A3C'; AccentBrush = '#7C3AED'; AccentLightBrush = '#A78BFA'
        TextBrush = '#F5F5F7'; MutedBrush = '#98989F'; GreenBrush = '#32D74B'; YellowBrush = '#FF9F0A'; RedBrush = '#FF453A'; BlueBrush = '#0A84FF'
    }
    $hex = $fallback[$Nome]
    if (-not $hex) { $hex = '#F5F5F7' }
    return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)))
}
#endregion

#region Background jobs
function Initialize-UTUiRunspacePool {
    <#
    .SYNOPSIS
        Pool for the background work, with every Upgrade Tweaks function and the shared state.
    #>
    [CmdletBinding()]
    param([int]$Maximo = 3)
    if (-not (Get-UTSyncValue -Key 'RaizRepositorio')) { $UTSync['RaizRepositorio'] = Get-UTSourceRoot }
    $iss = New-UTUiSessionState
    $pool = [runspacefactory]::CreateRunspacePool(1, $Maximo, $iss, $Host)
    $pool.Open()
    $ui = Get-UTUi
    if ($ui) { $ui.Pool = $pool }
    return $pool
}

function Get-UTUiJobWrapper {
    # Runs the job code in the worker and turns any error into a friendly message.
    return {
        param($Codigo, $Parametros)
        $ErrorActionPreference = 'Stop'
        try {
            $sb = [scriptblock]::Create($Codigo)
            $out = @(& $sb @Parametros)
            [pscustomobject]@{ Ok = $true; Resultado = $out; Erro = $null }
        } catch {
            $msg = $_.Exception.Message
            try { $msg = Get-UTFriendlyError -ErrorRecord $_ -Alvo 'a tarefa' } catch { $msg = $_.Exception.Message }
            try { Write-UTLog -Level Erro -Message $msg -Detalhe ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.ToString()) } catch { $null = $_ }
            [pscustomobject]@{ Ok = $false; Resultado = @(); Erro = $msg }
        }
    }
}

function Invoke-UTUiJob {
    <#
    .SYNOPSIS
        Runs a script block in the background. When it ends, -AoTerminar runs on the UI thread
        with two arguments: the result ({Ok, Resultado, Erro}) and -Estado.
    .DESCRIPTION
        The script block is sent as text: it must use only its parameters (-Argumentos is
        splatted into it) and the Upgrade Tweaks functions. The same goes for -AoTerminar,
        which gets everything it needs through -Estado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Argumentos = @{},
        [scriptblock]$AoTerminar,
        [object]$Estado,
        # Tweak runs: the apply/undo buttons stay disabled while it runs.
        [switch]$Exclusivo
    )
    $ui = Get-UTUi
    $pool = $ui.Pool
    if ($null -eq $pool) { $pool = Initialize-UTUiRunspacePool }
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript((Get-UTUiJobWrapper).ToString()).AddArgument($Script.ToString()).AddArgument($Argumentos)
    $job = [pscustomobject]@{
        Nome       = $Nome
        PowerShell = $ps
        Handle     = $ps.BeginInvoke()
        AoTerminar = $AoTerminar
        Estado     = $Estado
        Exclusivo  = [bool]$Exclusivo
        Inicio     = Get-Date
    }
    $ui.Jobs.Add($job)
    Sync-UTUiBusy
    return $job
}

function Receive-UTUiJob {
    <#
    .SYNOPSIS
        Collects finished jobs and runs their -AoTerminar (called by the UI timer).
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    if ($null -eq $ui) { return }
    foreach ($job in @($ui.Jobs | Where-Object { $_.Handle.IsCompleted })) {
        [void]$ui.Jobs.Remove($job)
        $result = $null
        try {
            $out = $job.PowerShell.EndInvoke($job.Handle)
            $result = (@($out) | Select-Object -First 1)
        } catch {
            $result = [pscustomobject]@{ Ok = $false; Resultado = @(); Erro = $_.Exception.Message }
        } finally {
            $job.PowerShell.Dispose()
        }
        if ($null -eq $result) { $result = [pscustomobject]@{ Ok = $false; Resultado = @(); Erro = 'A tarefa terminou sem resposta.' } }
        if ($job.AoTerminar) {
            try { & $job.AoTerminar $result $job.Estado } catch { Show-UTUiError -Mensagem "Erro ao mostrar o resultado de '$($job.Nome)': $($_.Exception.Message)" }
        }
    }
    Sync-UTUiBusy
}

function Test-UTUiExclusiveJob {
    $ui = Get-UTUi
    return [bool]($ui -and @($ui.Jobs | Where-Object Exclusivo).Count -gt 0)
}

function Sync-UTUiBusy {
    # Progress bar, status text and the apply buttons follow the running jobs.
    $ui = Get-UTUi
    if ($null -eq $ui -or $ui.C.Count -eq 0) { return }
    $running = $ui.Jobs.ToArray()
    $busy = $running.Count -gt 0
    $ui.C['BusyBar'].IsIndeterminate = $busy
    $ui.C['BusyBar'].Visibility = $(if ($busy) { 'Visible' } else { 'Hidden' })
    $ui.C['StatusText'].Text = $(if ($busy) { 'Trabalhando: ' + (($running | ForEach-Object Nome) -join ', ') + '...' } else { 'Pronto.' })
    $exclusive = Test-UTUiExclusiveJob
    $pending = (Get-UTUiPendingCount) -gt 0
    foreach ($n in 'ApplyButton', 'UndoButton', 'SimulateButton') { $ui.C[$n].IsEnabled = (-not $exclusive -and $pending) }
}
#endregion

#region Log panel
function Get-UTUiLogBrushName {
    param([string]$Nivel)
    switch ($Nivel) {
        'Sucesso' { 'GreenBrush' }
        'Aviso' { 'YellowBrush' }
        'Erro' { 'RedBrush' }
        'Debug' { 'MutedBrush' }
        default { 'TextBrush' }
    }
}

function Receive-UTUiLog {
    <#
    .SYNOPSIS
        Moves the log entries written by any runspace into the log panel (UI thread).
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $queue = Get-UTSyncValue -Key 'LogQueue'
    if ($null -eq $ui -or $null -eq $queue) { return }
    $entry = $null
    $added = $null
    while ($queue.TryDequeue([ref]$entry)) {
        if ($entry.Nivel -eq 'Debug') { continue }
        $text = '{0}  {1}' -f $entry.Data.ToString('HH:mm:ss'), $entry.Mensagem
        $ui.LogLinhas.Add(('{0} [{1}] {2}' -f $entry.Data.ToString('HH:mm:ss'), $entry.Nivel, $entry.Mensagem))
        if ($ui.C.ContainsKey('LogList')) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $text
            $tb.TextWrapping = 'Wrap'
            $tb.Foreground = Get-UTUiBrush (Get-UTUiLogBrushName $entry.Nivel)
            [void]$ui.C['LogList'].Items.Add($tb)
            $added = $tb
        }
    }
    if ($ui.C.ContainsKey('LogList')) {
        $list = $ui.C['LogList']
        while ($list.Items.Count -gt $ui.LogMax) { $list.Items.RemoveAt(0) }
        if ($added) { $list.ScrollIntoView($added) }
    }
    while ($ui.LogLinhas.Count -gt $ui.LogMax) { $ui.LogLinhas.RemoveAt(0) }
}

function Copy-UTUiLog {
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $text = ($ui.LogLinhas -join [Environment]::NewLine)
    if (-not $text) { $text = '(log vazio)' }
    [System.Windows.Clipboard]::SetText($text)
    Show-UTUiStatus 'Log copiado para a área de transferência.'
}

function Show-UTUiStatus {
    param([string]$Texto)
    $ui = Get-UTUi
    if ($ui -and $ui.C.ContainsKey('StatusText')) { $ui.C['StatusText'].Text = $Texto }
}
#endregion
