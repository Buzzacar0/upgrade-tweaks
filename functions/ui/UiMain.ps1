# Main window: navigation, search, top-bar buttons, presets, log panel and lifetime.

function New-UTUiSessionState {
    <#
    .SYNOPSIS
        Session state with every Upgrade Tweaks function and the shared variables, used by the
        background pool and by the STA thread of the window when the host is MTA.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in @(Get-ChildItem -Path function: | Where-Object { $_.Name -like '*-UT*' })) {
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $f.Name, $f.Definition))
    }
    foreach ($v in 'UTSync', 'UTEmbeddedConfig', 'UTEmbeddedXaml', 'UTVersion', 'UTReleaseUrl') {
        $var = Get-Variable -Name $v -ErrorAction SilentlyContinue
        if ($var) { $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $v, $var.Value, '')) }
    }
    return $iss
}

function Show-UTMainWindow {
    <#
    .SYNOPSIS
        Opens the interface and blocks until it is closed. Returns the exit code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([switch]$Simular, [switch]$Galeria)

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        # WPF needs an STA thread (PowerShell 7 started with -MTA, some hosts). Run it in one.
        $rs = [runspacefactory]::CreateRunspace($Host, (New-UTUiSessionState))
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddCommand('Show-UTMainWindow').AddParameter('Simular', [bool]$Simular).AddParameter('Galeria', [bool]$Galeria)
        try { return [int]((@($ps.Invoke()) | Select-Object -Last 1)) } finally { $ps.Dispose(); $rs.Dispose() }
    }

    Import-UTUiAssembly
    $ui = Initialize-UTUiState
    $loaded = Get-UTUiWindow -Name 'MainWindow'
    $ui.Window = $loaded.Window
    $ui.C = $loaded.Controles
    $c = $ui.C
    $version = [string](Get-UTSyncValue -Key 'Versao')
    $ui.Window.Title = "Upgrade Tweaks $version"
    $c['VersionText'].Text = "v$version  ·  Upgrade Store"
    $pref = Get-UTUiPreference
    Restore-UTUiWindowPlacement -Janela $ui.Window -Preferencias $pref
    Update-UTUiThemeIcon -Tema ([string]$pref.Tema)
    $ui.Window.Add_SourceInitialized({
            param($w, $e) $null = $e
            # Mica and the title bar color need the window handle, which exists only now.
            [void](Enable-UTUiBackdrop -Janela $w)
            Set-UTUiWindowDarkMode -Janela $w -Escuro ([string]$w.Resources['TemaAtual'] -eq 'escuro')
        })
    Initialize-UTUiChrome
    Initialize-UTUiSheet

    if ($Simular -or (Get-UTSyncValue -Key 'Simular')) {
        $UTSync['Simular'] = $true
        $c['Banner'].Visibility = 'Visible'
        $c['BannerText'].Text = 'MODO SIMULAÇÃO: nada será alterado no sistema. "Aplicar" só mostra o que seria feito.'
    }

    Initialize-UTUiNavigation
    Initialize-UTUiPreset
    Register-UTUiHandler

    [void](Initialize-UTUiRunspacePool)
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
            try { Receive-UTUiLog; Receive-UTUiJob } catch { Write-UTLog -Level Erro -Message 'Falha ao atualizar a tela.' -Detalhe $_.Exception.Message }
        })
    $ui.Timer = $timer
    $timer.Start()

    $first = 'Inicio'
    if (@(Get-UTUiTabDefinition | ForEach-Object Id) -contains [string]$pref.Pagina) { $first = [string]$pref.Pagina }
    if ($Galeria) { $first = 'Galeria' }
    Show-UTUiPage -Id $first
    Write-UTLog -Level Info -Message 'Interface aberta.'
    try {
        [void]$ui.Window.ShowDialog()
    } finally {
        $timer.Stop()
        try { Save-UTUiWindowPlacement -Janela $ui.Window -Pagina ([string]$ui.PaginaAtual) } catch { $null = $_ }
        if ($ui.ContainsKey('Monitor') -and $ui.Monitor -and $ui.Monitor.Timer) { $ui.Monitor.Timer.Stop() }
        if ($ui.ContainsKey('Monitor') -and $ui.Monitor -and $ui.Monitor.Log) { Close-UTMonitorLog -Log $ui.Monitor.Log }
        if ($ui.ContainsKey('Benchmark') -and $ui.Benchmark -and $ui.Benchmark.Sessao) { $ui.Benchmark.Sessao.Stop() }
        if ($ui.ContainsKey('OverlayEditor') -and $ui.OverlayEditor -and $ui.OverlayEditor.Timer) { $ui.OverlayEditor.Timer.Stop() }
        try { Stop-UTSensorMonitor -Confirm:$false } catch { Write-UTLog -Level Aviso -Message 'Não foi possível parar a leitura dos sensores.' -Detalhe $_.Exception.Message }
        Close-UTUiPool
    }
    return 0
}

function Close-UTUiPool {
    $ui = Get-UTUi
    if ($null -eq $ui) { return }
    foreach ($j in $ui.Jobs.ToArray()) { try { $j.PowerShell.Stop(); $j.PowerShell.Dispose() } catch { $null = $_ } }
    $ui.Jobs.Clear()
    if ($ui.Pool) { try { $ui.Pool.Close(); $ui.Pool.Dispose() } catch { $null = $_ }; $ui.Pool = $null }
}

function Initialize-UTUiNavigation {
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $list = $ui.C['NavList']
    $section = $null
    $headerStyle = $ui.Window.TryFindResource('NavHeader')
    foreach ($tab in @(Get-UTUiTabDefinition)) {
        $sec = [string](Get-UTField -Objeto $tab -Nome 'Secao' -Padrao '')
        if ($sec -ne $section) {
            $section = $sec
            if ($sec) {
                # Section title of the sidebar: not selectable, skipped by the keyboard.
                $header = New-Object System.Windows.Controls.ListBoxItem
                $header.Content = $sec
                $header.IsEnabled = $false
                if ($headerStyle) { $header.Style = $headerStyle }
                [void]$list.Items.Add($header)
            }
        }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $icon = New-UTUiSquircle -Glifo $tab.Icone -Cor ([string](Get-UTField -Objeto $tab -Nome 'Cor' -Padrao 'IconBlue')) -Tamanho 24 -Margem '0,0,10,0'
        $item.Content = New-UTUiStack -Horizontal -Itens @($icon, (New-UTUiText $tab.Nome -Tamanho 13.5))
        $item.Content.Children[1].VerticalAlignment = 'Center'
        [System.Windows.Automation.AutomationProperties]::SetName($item, $tab.Nome)
        $item.Tag = $tab.Id
        [void]$list.Items.Add($item)
    }
    $list.Add_SelectionChanged({
            param($l, $evt) $null = $evt
            $ui2 = Get-UTUi
            if ($ui2.Navegando -or $null -eq $l.SelectedItem -or $null -eq $l.SelectedItem.Tag) { return }
            try { Show-UTUiPage -Id ([string]$l.SelectedItem.Tag) } catch { Show-UTUiError -Mensagem $_.Exception.Message }
        })
}

function Show-UTUiPage {
    <#
    .SYNOPSIS
        Shows a tab, building its page the first time.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $ui = Get-UTUi
    if (-not $ui.Pages.ContainsKey($Id)) {
        $tab = (@(Get-UTUiTabDefinition | Where-Object Id -eq $Id) | Select-Object -First 1)
        $builder = "New-UTUiPage$Id"
        if ($tab -and $tab.PSObject.Properties['Pagina']) { $builder = "New-UTUiPage$($tab.Pagina)" }
        try {
            $ui.Pages[$Id] = & $builder
        } catch {
            Write-UTLog -Level Erro -Message "Não foi possível montar a aba $Id." -Detalhe $_.Exception.ToString()
            return (Set-UTUiPageContent -Conteudo (New-UTUiCard -Titulo 'Esta aba não abriu' -Subtitulo $_.Exception.Message -Icone 'EA39'))
        }
    }
    $ui.PaginaAtual = $Id
    Set-UTUiTitle -Id $Id
    Set-UTUiPageContent -Conteudo $ui.Pages[$Id]
    foreach ($row in @($ui.Rows | Where-Object Pagina -eq $Id)) { Sync-UTUiRowState -Linha $row }

    $ui.Navegando = $true
    try {
        $item = (@($ui.C['NavList'].Items | Where-Object { $_.Tag -eq $Id }) | Select-Object -First 1)
        $ui.C['NavList'].SelectedItem = $item
        if ($ui.C['SearchBox'].Text) { $ui.C['SearchBox'].Text = '' }
    } finally { $ui.Navegando = $false }
}

function Set-UTUiTitle {
    # Title of the page in the title bar (tab name, "Busca" for the search results).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only a text of the interface.')]
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Id)
    $ui = Get-UTUi
    if (-not $ui.C.ContainsKey('TitleText')) { return }
    $tab = (@(Get-UTUiTabDefinition | Where-Object Id -eq $Id) | Select-Object -First 1)
    $ui.C['TitleText'].Text = $(if ($tab) { $tab.Nome } elseif ($Id -eq 'Galeria') { 'Galeria de componentes' } elseif ($Id -eq 'Busca') { 'Busca' } else { 'Upgrade Tweaks' })
}
function Set-UTUiPageContent {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Conteudo)
    $ui = Get-UTUi
    # A page is kept in memory; detach it from the previous host before showing it again.
    $ui.C['PageHost'].Content = $null
    $ui.C['PageHost'].Content = $Conteudo
    $ui.C['PageScroll'].ScrollToTop()
    if ($ui.Window.IsVisible) { Invoke-UTUiPageTransition -Elemento $ui.C['PageHost'] -Deslocamento $ui.C['PageShift'] }
}

function Show-UTUiSearch {
    <#
    .SYNOPSIS
        Global search (Ctrl+K): tabs, tweaks, sensors being read now and BIOS options (when the
        map of this BIOS is loaded). Clicking a result opens where it lives.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texto)
    $ui = Get-UTUi
    if ($ui.Navegando) { return }
    Remove-UTUiPageRow -Pagina 'Busca'
    if ([string]::IsNullOrWhiteSpace($Texto) -or $Texto.Trim().Length -lt 2) {
        if ($ui.PaginaAtual -and $ui.Pages.ContainsKey($ui.PaginaAtual)) { Set-UTUiPageContent -Conteudo $ui.Pages[$ui.PaginaAtual]; Set-UTUiTitle -Id ([string]$ui.PaginaAtual) }
        return
    }
    $q = $Texto.Trim()
    $tabs = @(Find-UTUiTab -Texto $q)
    $found = @(Find-UTUiTweak -Texto $q)
    $sensors = @(Find-UTUiSensor -Texto $q)
    $bios = @(Find-UTUiBiosOption -Texto $q)
    $total = $tabs.Count + $found.Count + $sensors.Count + $bios.Count
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo "Busca: $q" -Descricao $(if ($total -eq 1) { '1 resultado.' } else { "$total resultados." })))
    if ($tabs.Count -gt 0) {
        $rows = foreach ($tab in $tabs) {
            $open = New-UTUiButton 'Abrir' -Estilo Link -Dados ([string]$tab.Id) -AoClicar { param($b, $d) $null = $b; Show-UTUiPage -Id $d }
            New-UTUiRow -Titulo ([string]$tab.Nome) -Subtitulo $(if ($tab.Secao) { [string]$tab.Secao } else { 'Visão geral' }) -Icone ([string]$tab.Icone) -IconeCor ([string]$tab.Cor) -Direita $open
        }
        [void]$page.Children.Add((New-UTUiGroup -Titulo 'Abas' -Linhas @($rows)))
    }
    if ($found.Count -gt 0) { [void]$page.Children.Add((New-UTUiTweakList -Tweaks $found -Pagina 'Busca' -Titulo 'Ajustes')) }
    if ($sensors.Count -gt 0) {
        $rows = foreach ($s in $sensors) {
            $value = New-UTUiText ([string]$s.Atual) -Peso SemiBold
            New-UTUiRow -Titulo ([string]$s.Sensor) -Subtitulo "$($s.Hardware) · $($s.Tipo)" -Icone 'E9D9' -IconeCor 'IconGreen' -Direita $value
        }
        $more = New-UTUiButton 'Abrir o Monitor' -Estilo Link -AoClicar { param($b, $d) $null = $b, $d; Show-UTUiPage -Id 'Monitor' }
        [void]$page.Children.Add((New-UTUiGroup -Titulo 'Sensores (agora)' -Linhas @(@($rows) + @(New-UTUiRowBox $more))))
    }
    if ($bios.Count -gt 0) {
        $rows = foreach ($o in $bios) {
            $open = New-UTUiButton 'Ver na aba BIOS' -Estilo Link -Dados ([string]$o.Nome) -AoClicar { param($b, $d) $null = $b; Start-UTUiBiosSearch -Texto $d }
            New-UTUiRow -Titulo ([string]$o.Nome) -Subtitulo ([string]$o.Local) -Icone 'E950' -IconeCor 'IconIndigo' -Direita $open
        }
        [void]$page.Children.Add((New-UTUiGroup -Titulo 'Opções da BIOS' -Linhas @($rows) -Rodape 'Nomes em inglês, como aparecem na tela da BIOS.'))
    }
    if ($total -eq 0) { [void]$page.Children.Add((New-UTUiText 'Nada encontrado. Tente outra palavra (ex.: "mouse", "telemetria", "DNS", "temperatura").' -Cor MutedBrush)) }
    $ui.Navegando = $true
    try { $ui.C['NavList'].SelectedItem = $null } finally { $ui.Navegando = $false }
    Set-UTUiTitle -Id 'Busca'
    Set-UTUiPageContent -Conteudo $page
}

function Find-UTUiTab {
    # Side tabs whose name or section contain the text (accent-insensitive).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto)
    $needle = ConvertTo-UTUiSearchText $Texto
    if (-not $needle) { return @() }
    foreach ($tab in @(Get-UTUiTabDefinition)) {
        if ((ConvertTo-UTUiSearchText ("{0} {1} {2}" -f $tab.Nome, $tab.Id, $tab.Secao)).Contains($needle)) { $tab }
    }
}

function Find-UTUiSensor {
    # Sensors of the last reading (only while the Monitor reads them), at most -Maximo.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto, [int]$Maximo = 12)
    $needle = ConvertTo-UTUiSearchText $Texto
    if (-not $needle -or $null -eq (Get-UTSyncValue -Key 'Sensores')) { return @() }
    $rows = @()
    try { $rows = @(Get-UTSensorSnapshot) } catch { return @() }
    @($rows | Where-Object { (ConvertTo-UTUiSearchText ("{0} {1} {2} {3}" -f $_.Sensor, $_.Hardware, $_.Tipo, $_.Grupo)).Contains($needle) } | Select-Object -First $Maximo)
}

function Find-UTUiBiosOption {
    <#
    .SYNOPSIS
        Options of the BIOS map already loaded in this session (opening the BIOS tab loads it),
        by the name shown in the BIOS screen. Nothing is read from the NVRAM here.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto, [int]$Maximo = 8)
    $needle = ConvertTo-UTUiSearchText $Texto
    $cached = Get-UTSyncValue -Key 'BiosMapa'
    if (-not $needle -or $null -eq $cached -or $null -eq $cached.Mapa) { return @() }
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($q in @($cached.Mapa['Perguntas'])) {
        $name = [string]$q['Nome']
        if (-not $name -or $seen.ContainsKey($name)) { continue }
        if (-not (ConvertTo-UTUiSearchText $name).Contains($needle)) { continue }
        $seen[$name] = $true
        $out.Add([pscustomobject]@{ Nome = $name; Local = (@([string]$q['Menu'], [string]$q['Formulario']) | Where-Object { $_ }) -join ' > ' })
        if ($out.Count -ge $Maximo) { break }
    }
    return $out.ToArray()
}
function Register-UTUiHandler {
    <#
    .SYNOPSIS
        Events of the fixed controls of the window.
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $c = $ui.C
    $c['ApplyButton'].Add_Click({ try { Invoke-UTUiRun -Modo Aplicar } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
    # "Descartar": the switches go back to the real state.
    $c['UndoButton'].Add_Click({ try { Clear-UTUiSelection } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
    $c['SimulateButton'].Add_Click({ try { Invoke-UTUiRun -Modo Simular } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
    $c['LogCopy'].Add_Click({ try { Copy-UTUiLog } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
    $c['LogOpenFolder'].Add_Click({ Start-Process explorer.exe -ArgumentList (Get-UTPath -Name Logs) })
    $c['LogToggle'].Add_Click({
            param($b, $evt) $null = $evt
            $list = (Get-UTUi).C['LogList']
            if ($list.Visibility -eq 'Visible') { $list.Visibility = 'Collapsed'; $b.Content = '▸ Log' } else { $list.Visibility = 'Visible'; $b.Content = '▾ Log' }
        })

    $search = New-Object System.Windows.Threading.DispatcherTimer
    $search.Interval = [TimeSpan]::FromMilliseconds(350)
    $search.Add_Tick({
            param($t, $evt) $null = $evt
            $t.Stop()
            try { Show-UTUiSearch -Texto (Get-UTUi).C['SearchBox'].Text } catch { Show-UTUiError -Mensagem $_.Exception.Message }
        })
    $c['SearchBox'].Tag = 'Buscar (Ctrl+K)'
    $c['ThemeButton'].Add_Click({ try { Switch-UTUiTheme } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
    $ui.Window.Add_PreviewKeyDown({
            param($w, $e) $null = $w
            $mods = [System.Windows.Input.Keyboard]::Modifiers
            $u = Get-UTUi
            if ($u.SheetEstado) { return }
            if ($mods -eq 'Control' -and $e.Key -in 'K', 'F') { [void]$u.C['SearchBox'].Focus(); $u.C['SearchBox'].SelectAll(); $e.Handled = $true }
            elseif ($mods -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift) -and $e.Key -eq 'G') { Show-UTUiPage -Id 'Galeria'; $e.Handled = $true }
        })
    $c['SearchBox'].DataContext = $search
    $c['SearchBox'].Add_TextChanged({
            param($box, $evt) $null = $evt
            if ((Get-UTUi).Navegando) { return }
            $box.DataContext.Stop()
            $box.DataContext.Start()
        })

    $ui.Window.Add_Closing({
            param($w, $e) $null = $w
            if (Test-UTUiExclusiveJob) {
                $ans = Show-UTUiDialog -Titulo 'Uma alteração está em andamento' -Mensagem 'Fechar agora pode deixar um ajuste pela metade. Espere terminar.' -Tipo aviso -Botoes @('Esperar', 'Fechar mesmo assim')
                if ($ans -ne 'Fechar mesmo assim') { $e.Cancel = $true; return }
            }
            try {
                if ((Get-UTMatchModeStatus).Ativo) {
                    $ans = Show-UTUiDialog -Titulo 'Modo Partida ativo' -Mensagem 'Sair do Modo Partida antes de fechar? (volta o plano de energia e reabre os programas)' -Tipo pergunta -Botoes @('Sair do Modo Partida', 'Deixar ativo')
                    if ($ans -eq 'Sair do Modo Partida') { Stop-UTMatchMode }
                }
            } catch { Write-UTLog -Level Aviso -Message 'Não foi possível verificar o Modo Partida ao fechar.' -Detalhe $_.Exception.Message }
        })
}

function Initialize-UTUiPreset {
    <#
    .SYNOPSIS
        Fills the preset selector (presets.json). Choosing one marks its tweaks.
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $box = $ui.C['PresetBox']
    $names = @()
    if (Get-Command -Name Get-UTPresetName -ErrorAction SilentlyContinue) { try { $names = @(Get-UTPresetName) } catch { $names = @() } }
    if ($names.Count -eq 0) { $box.Visibility = 'Collapsed'; return }
    [void]$box.Items.Add('Escolher preset...')
    foreach ($n in $names) { [void]$box.Items.Add($n) }
    $box.SelectedIndex = 0
    $box.Add_SelectionChanged({
            param($cb, $evt) $null = $evt
            if ($cb.SelectedIndex -le 0) { return }
            $name = [string]$cb.SelectedItem
            try { Select-UTUiPreset -Nome $name } catch { Show-UTUiError -Mensagem $_.Exception.Message }
            $cb.SelectedIndex = 0
        })
}

function Select-UTUiPreset {
    <#
    .SYNOPSIS
        Marks the tweaks of a preset (and unmarks the others). Extremo asks for "EU ENTENDO".
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Nome)
    $info = Get-UTPresetSelection -Nome $Nome
    if ($info.ExigeConfirmacao) {
        $ans = Show-UTUiDialog -Titulo "Preset $Nome" -Mensagem ([string]$info.Aviso) -Tipo aviso -Botoes @('Marcar', 'Cancelar') -TextoConfirmacao ([string]$info.TextoConfirmacao)
        if ($ans -ne 'Marcar') { return }
    }
    Clear-UTUiSelection
    Set-UTUiSelection -Id @($info.Ids) -Marcado $true
    Show-UTUiStatus "Preset $Nome`: $(Get-UTUiPendingCount) alterações pendentes. Confira as abas e clique em Revisar e aplicar."
}
