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
    param([switch]$Simular)

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        # WPF needs an STA thread (PowerShell 7 started with -MTA, some hosts). Run it in one.
        $rs = [runspacefactory]::CreateRunspace($Host, (New-UTUiSessionState))
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddCommand('Show-UTMainWindow').AddParameter('Simular', [bool]$Simular)
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

    Show-UTUiPage -Id 'Inicio'
    Write-UTLog -Level Info -Message 'Interface aberta.'
    try {
        [void]$ui.Window.ShowDialog()
    } finally {
        $timer.Stop()
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
    foreach ($tab in @(Get-UTUiTabDefinition)) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = New-UTUiStack -Horizontal -Itens @((New-UTUiIcon -Glifo $tab.Icone -Tamanho 16 -Cor 'AccentLightBrush' -Margem '0,0,12,0'), (New-UTUiText $tab.Nome -Tamanho 13.5))
        # The text follows the item color (muted, hover, selected).
        $bind = New-Object System.Windows.Data.Binding 'Foreground'
        $bind.RelativeSource = New-Object System.Windows.Data.RelativeSource ([System.Windows.Data.RelativeSourceMode]::FindAncestor, [System.Windows.Controls.ListBoxItem], 1)
        [void]$item.Content.Children[1].SetBinding([System.Windows.Controls.TextBlock]::ForegroundProperty, $bind)
        $item.Tag = $tab.Id
        [void]$list.Items.Add($item)
    }
    $list.Add_SelectionChanged({
            param($l, $evt) $null = $evt
            $ui2 = Get-UTUi
            if ($ui2.Navegando -or $null -eq $l.SelectedItem) { return }
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
    Set-UTUiPageContent -Conteudo $ui.Pages[$Id]
    foreach ($row in @($ui.Rows | Where-Object Pagina -eq $Id)) { Sync-UTUiRowState -Linha $row }

    $ui.Navegando = $true
    try {
        $item = (@($ui.C['NavList'].Items | Where-Object { $_.Tag -eq $Id }) | Select-Object -First 1)
        $ui.C['NavList'].SelectedItem = $item
        if ($ui.C['SearchBox'].Text) { $ui.C['SearchBox'].Text = '' }
    } finally { $ui.Navegando = $false }
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
}

function Show-UTUiSearch {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texto)
    $ui = Get-UTUi
    if ($ui.Navegando) { return }
    Remove-UTUiPageRow -Pagina 'Busca'
    if ([string]::IsNullOrWhiteSpace($Texto) -or $Texto.Trim().Length -lt 2) {
        if ($ui.PaginaAtual -and $ui.Pages.ContainsKey($ui.PaginaAtual)) { Set-UTUiPageContent -Conteudo $ui.Pages[$ui.PaginaAtual] }
        return
    }
    $found = @(Find-UTUiTweak -Texto $Texto)
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo "Busca: $($Texto.Trim())" -Descricao "$($found.Count) ajuste(s) encontrado(s) em todas as abas."))
    if ($found.Count -gt 0) { [void]$page.Children.Add((New-UTUiTweakList -Tweaks $found -Pagina 'Busca' -Titulo 'Resultados')) }
    else { [void]$page.Children.Add((New-UTUiText 'Nenhum ajuste com esse nome. Tente outra palavra (ex.: "mouse", "telemetria", "DNS").' -Cor MutedBrush)) }
    $ui.Navegando = $true
    try { $ui.C['NavList'].SelectedItem = $null } finally { $ui.Navegando = $false }
    Set-UTUiPageContent -Conteudo $page
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
    $c['UndoButton'].Add_Click({ try { Invoke-UTUiRun -Modo Desfazer } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
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
    $c['SearchBox'].Tag = 'Buscar ajustes...'
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
    Show-UTUiStatus "Preset $Nome`: $(@($info.Ids).Count) ajustes marcados. Confira as abas e clique em Aplicar selecionados."
}
