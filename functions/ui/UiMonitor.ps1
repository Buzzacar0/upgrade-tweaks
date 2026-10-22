# Monitor tab: the sensors in real time as cards (value, sparkline, minimum/maximum/average) or as
# a table, with the layouts, favorites, names, order (drag a card), alerts and CSV files kept in
# monitor.json, and the hardware summary (CPU-Z). It only reads the hardware.

#region Page
function New-UTUiPageMonitor {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'Monitor' -Descricao 'Temperaturas, uso, clocks, consumo e ventoinhas em tempo real (como o HWMonitor) e o resumo do hardware (como o CPU-Z). Só lê o hardware.'))
    $setup = Get-UTSensorSetup
    if (-not $setup.Pronto) {
        $missing = @()
        if (-not $setup.Driver) { $missing += 'Driver PawnIO (assinado, código aberto) pelo winget: cerca de 3 MB. É ele que dá acesso aos sensores da placa-mãe, do processador e da memória.' }
        if (-not $setup.Biblioteca) { $missing += 'Biblioteca LibreHardwareMonitor (código aberto) do GitHub: cerca de 6 MB.' }
        $install = New-UTUiButton 'Instalar suporte a sensores' -Estilo Primario -Icone 'E896' -Margem '0,10,0,0' -AoClicar {
            param($b, $d) $null = $b, $d
            $ans = Show-UTUiDialog -Titulo 'Instalar suporte a sensores?' -Mensagem 'Serão instalados o driver PawnIO (winget) e a biblioteca LibreHardwareMonitor (GitHub). Os dois são de código aberto e usados por programas como o FanControl. Para remover depois: winget uninstall namazso.PawnIO.' -Tipo pergunta -Botoes @('Instalar', 'Cancelar')
            if ($ans -ne 'Instalar') { return }
            Invoke-UTUiAction -Nome 'Instalando suporte a sensores' -Exclusivo -Script { Install-UTSensorSupport -Confirm:$false } -Depois {
                param($r, $dd) $null = $r, $dd
                $ui = Get-UTUi
                [void]$ui.Pages.Remove('Monitor')
                Show-UTUiPage -Id 'Monitor'
            }
        }
        [void]$page.Children.Add((New-UTUiCard -Titulo 'Falta instalar o suporte a sensores' -Icone 'E7BA' -Subtitulo 'O Windows não mostra temperaturas, tensões e ventoinhas sem um driver que leia o hardware diretamente. É preciso instalar:' -Conteudo @(
                    (New-UTUiStack -Itens @($missing | ForEach-Object { New-UTUiText ('•  ' + $_) -Quebrar -Margem '0,2' }))
                    $install
                )))
        [void]$page.Children.Add((New-UTUiMonitorSpecCard))
        return $page
    }

    $ui = Get-UTUi
    $cfg = Get-UTMonitorConfig
    $m = @{
        Config = $cfg; Host = (New-UTUiStack); Status = $null; Itens = @(); Visuais = @{}; Assinatura = ''; Historico = @{}; Alertas = @{}
        Limites = @{}; Timer = $null; UltimaHora = [datetime]::MinValue; UltimaSelecao = [datetime]::MinValue; Recalcular = $true; Sujo = $true
        Log = $null; Linhas = @(); Atuais = @{}; CacheNucleos = @{}; Controles = @{}; Sincronizando = $false; Movimento = $null; Necessarios = $null
    }
    $ui.Monitor = $m

    $layout = New-Object System.Windows.Controls.ComboBox
    $layout.MinWidth = 150
    foreach ($l in 'Essencial', 'Gamer', 'Completo', 'Personalizado') { [void]$layout.Items.Add($l) }
    $layout.ToolTip = 'Essencial: o básico. Gamer: o que importa jogando. Completo: todos os sensores. Personalizado: só os que você escolher.'
    $layout.Add_SelectionChanged({
            param($cb, $e) $null = $e
            $mm = (Get-UTUi).Monitor
            if ($mm.Sincronizando -or $null -eq $cb.SelectedItem) { return }
            $new = [string]$cb.SelectedItem
            if ($new -eq $mm.Config.Layout) { return }
            $c = ConvertTo-UTMonitorConfig -Config $mm.Config
            # The first Personalizado starts as what is on screen now.
            if ($new -eq 'Personalizado' -and @($c.Personalizado).Count -eq 0) { $c.Personalizado = @(Get-UTMonitorVisibleId -Linhas $mm.Linhas -Config $mm.Config) }
            $c.Layout = $new
            Save-UTUiMonitorConfig -Config $c
        })
    $view = New-Object System.Windows.Controls.ComboBox
    $view.MinWidth = 120
    [void]$view.Items.Add('Cartões'); [void]$view.Items.Add('Tabela')
    $view.ToolTip = 'Cartões com gráfico ou tabela com mínimo, máximo e média'
    $view.Add_SelectionChanged({
            param($cb, $e) $null = $e
            $mm = (Get-UTUi).Monitor
            if ($mm.Sincronizando -or $null -eq $cb.SelectedItem) { return }
            $c = ConvertTo-UTMonitorConfig -Config $mm.Config
            $c.Visao = $(if ([string]$cb.SelectedItem -eq 'Tabela') { 'Tabela' } else { 'Cartoes' })
            if ($c.Visao -ne $mm.Config.Visao) { Save-UTUiMonitorConfig -Config $c }
        })
    $add = New-UTUiButton 'Adicionar sensores' -Icone 'E710' -AoClicar { param($b, $d) $null = $b, $d; Show-UTUiMonitorAddSensor }
    $reset = New-UTUiButton 'Zerar mín./máx.' -Icone 'E72C' -Dica 'Zera mínimo, máximo e média de todos os sensores' -AoClicar {
        param($b, $d) $null = $b, $d
        $UTSync['SensoresZerar'] = $true
        $mm = (Get-UTUi).Monitor
        $mm.Historico = @{}
        $mm.Alertas = @{}
        Show-UTUiStatus 'Mínimos, máximos e médias zerados.'
    }
    $csv = New-UTUiButton 'Relatório CSV' -Icone 'E74E' -Dica 'Todos os sensores com atual, mínimo, máximo e média (abre no Excel)' -AoClicar {
        param($b, $d) $null = $b, $d
        $mm = (Get-UTUi).Monitor
        $p = Get-UTUiFileDialog -Modo Salvar -Filtro 'CSV (*.csv)|*.csv' -NomeSugerido ('sensores-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.csv')
        if (-not $p) { return }
        $rows = @($mm.Linhas)
        if ($mm.Config.ResumoNucleos) { $rows = @(Merge-UTMonitorCoreSummary -Linhas $rows -Cache $mm.CacheNucleos) }
        [void](Export-UTMonitorCsv -Path $p -Linhas $rows -Historico $mm.Historico -Config $mm.Config -Confirm:$false)
        Show-UTUiStatus "Relatório salvo em $p"
    }
    $log = New-UTUiButton 'Gravar log' -Icone 'E7C8' -Dica 'Grava uma linha por leitura dos sensores na tela, num CSV (para sessões longas)' -AoClicar { param($b, $d) $null = $d; Switch-UTUiMonitorLog -Botao $b }
    $settings = New-UTUiButton 'Ajustes' -Icone 'E713' -AoClicar { param($b, $d) $null = $b, $d; Show-UTUiMonitorPreference }
    $m.Controles = @{ Layout = $layout; Visao = $view; Adicionar = $add; Log = $log }

    $tools = New-UTUiWrap -Itens @(
        (New-UTUiStack -Margem '0,0,12,8' -Itens @((New-UTUiText 'Layout' -Tamanho 11.5 -Cor MutedBrush -Margem '2,0,0,3'), $layout))
        (New-UTUiStack -Margem '0,0,20,8' -Itens @((New-UTUiText 'Exibir como' -Tamanho 11.5 -Cor MutedBrush -Margem '2,0,0,3'), $view))
    )
    $buttons = New-UTUiWrap -Itens @($add, $reset, $csv, $log, $settings)
    $buttons.VerticalAlignment = 'Bottom'
    [void]$tools.Children.Add($buttons)
    $m.Status = New-UTUiText 'Abrindo os sensores (leva alguns segundos)...' -Cor MutedBrush -Margem '2,2,0,12'
    [void]$page.Children.Add($tools)
    [void]$page.Children.Add($m.Status)
    [void]$page.Children.Add($m.Host)
    [void]$page.Children.Add((New-UTUiMonitorSpecCard))
    Sync-UTUiMonitorToolbar

    try { Start-UTSensorMonitor -IntervaloMs $cfg.IntervaloMs -Confirm:$false } catch { $m.Status.Text = $_.Exception.Message; $m.Status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'YellowBrush') }
    Set-UTSensorInterval -IntervaloMs $cfg.IntervaloMs -Confirm:$false
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($cfg.IntervaloMs)
    $timer.Add_Tick({ try { Update-UTUiMonitor } catch { Write-UTLog -Level Aviso -Message 'Falha ao atualizar os sensores na tela.' -Detalhe $_.Exception.Message } })
    $m.Timer = $timer
    $timer.Start()
    return $page
}

function Sync-UTUiMonitorToolbar {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $m = (Get-UTUi).Monitor
    if ($null -eq $m -or $null -eq $m.Controles.Layout) { return }
    $m.Sincronizando = $true
    try {
        $m.Controles.Layout.SelectedItem = [string]$m.Config.Layout
        $m.Controles.Visao.SelectedItem = $(if ($m.Config.Visao -eq 'Tabela') { 'Tabela' } else { 'Cartões' })
        $m.Controles.Adicionar.Visibility = $(if ($m.Config.Layout -eq 'Personalizado') { 'Visible' } else { 'Collapsed' })
    } finally { $m.Sincronizando = $false }
}

function Save-UTUiMonitorConfig {
    <#
    .SYNOPSIS
        Saves new Monitor settings and applies them now (layout, view, interval, unit...).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Saves only the preferences of the Monitor tab.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config, [string]$Mensagem)
    $m = (Get-UTUi).Monitor
    $before = $m.Config
    $m.Config = Save-UTMonitorConfig -Config $Config -Confirm:$false
    if ($m.Config.IntervaloMs -ne $before.IntervaloMs) {
        Set-UTSensorInterval -IntervaloMs $m.Config.IntervaloMs -Confirm:$false
        if ($m.Timer) { $m.Timer.Interval = [TimeSpan]::FromMilliseconds($m.Config.IntervaloMs) }
    }
    $m.Recalcular = $true
    Sync-UTUiMonitorToolbar
    if ($Mensagem) { Show-UTUiStatus $Mensagem }
    Update-UTUiMonitor -Forcar
}
#endregion

#region Update (timer)
function Update-UTUiMonitor {
    <#
    .SYNOPSIS
        Timer tick: reads the last snapshot, picks the sensors of the layout again every 5 s,
        keeps history and alerts and, with the tab on screen, updates only the values (the view is
        rebuilt only when the list of sensors changes). With the tab hidden only alerts and the
        log run, and nothing at all when there are none.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param([switch]$Forcar)
    $ui = Get-UTUi
    if ($null -eq $ui -or $null -eq $ui.Monitor) { return }
    $m = $ui.Monitor
    $err = Get-UTSyncValue -Key 'SensoresErro'
    if ($err) {
        $m.Status.Text = "Os sensores pararam: $err"
        $m.Status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'YellowBrush')
        return
    }
    $snap = Get-UTSyncValue -Key 'Sensores'
    if ($null -eq $snap) { return }
    $visible = ($ui.PaginaAtual -eq 'Monitor' -and $null -ne $ui.Window -and $ui.Window.WindowState -ne 'Minimized')
    if ($snap.Hora -eq $m.UltimaHora -and -not $Forcar) { return }
    if (-not $visible -and -not $Forcar -and $m.Limites.Count -eq 0 -and $null -eq $m.Log -and -not $m.Recalcular) { return }
    $m.UltimaHora = $snap.Hora
    $cfg = $m.Config
    # Every sensor is converted only when the selection is redone (every 5 s, or after a change);
    # in between, only the ones on screen, with alerts or in the log.
    $full = ($m.Recalcular -or $null -eq $m.Necessarios -or ([datetime]::Now - $m.UltimaSelecao).TotalSeconds -ge 5)
    if ($full) { $rows = @(Get-UTSensorSnapshot -SemTexto) } else { $rows = @(Get-UTSensorSnapshot -SemTexto -Ids $m.Necessarios) }
    if ($rows.Count -eq 0) { return }
    $current = $rows
    if ($cfg.ResumoNucleos) { $current = @(Merge-UTMonitorCoreSummary -Linhas $rows -Cache $m.CacheNucleos) }
    $byId = @{}
    foreach ($r in $current) { $byId[[string]$r.Id] = $r }
    if ($full) { $m.Linhas = $rows; $m.Atuais = $byId } else { foreach ($k in @($byId.Keys)) { $m.Atuais[$k] = $byId[$k] } }

    # A sensor that leaves zero (a fan that starts) shows up at the next selection.
    if ($full) {
        $m.Recalcular = $false
        $m.UltimaSelecao = [datetime]::Now
        $m.Itens = @(Select-UTMonitorRow -Linhas $rows -Config $cfg -Cache $m.CacheNucleos)
        $m.Limites = Get-UTMonitorAlertLimit -Linhas $current -Config $cfg
        $wanted = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($i in @($m.Itens | ForEach-Object { $_.Id }) + @($m.Limites.Keys)) { [void]$wanted.Add([string]$i) }
        if ($m.Log) { foreach ($c in $m.Log.Colunas) { [void]$wanted.Add([string]$c.Id) } }
        $need = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($r in $rows) {
            $id = [string]$r.Id
            $key = $m.CacheNucleos[$id]
            if ($wanted.Contains($id) -or ($key -and $wanted.Contains([string]$key))) { [void]$need.Add($id) }
        }
        $m.Necessarios = $need
        $sig = "$($cfg.Visao)#$($cfg.Unidade)$($cfg.Casas)#" + (($m.Itens | ForEach-Object { "$($_.Id)=$($_.NomeExibicao)=$($_.Favorito)" }) -join '|')
        if ($sig -ne $m.Assinatura) { $m.Assinatura = $sig; $m.Sujo = $true }
    }

    $shown = New-Object System.Collections.Generic.List[object]
    foreach ($it in $m.Itens) { $r = $byId[$it.Id]; if ($null -ne $r) { $shown.Add($r) } }
    Add-UTMonitorSample -Historico $m.Historico -Linhas $shown.ToArray()
    if ($m.Limites.Count -gt 0) {
        $watched = @($m.Limites.Keys | ForEach-Object { $byId[$_] } | Where-Object { $null -ne $_ })
        foreach ($ev in @(Update-UTMonitorAlert -Linhas $watched -Limites $m.Limites -Estado $m.Alertas)) {
            $name = $(if ($cfg.Nomes.Contains($ev.Id)) { [string]$cfg.Nomes[$ev.Id] } else { [string]$ev.Linha.Sensor })
            $text = Format-UTMonitorAlertText -Alerta $ev -Nome $name -Unidade $cfg.Unidade -Casas 0
            Write-UTLog -Level Aviso -Message "Alerta do Monitor: $text"
            Show-UTUiStatus "Alerta: $text"
            if ($cfg.Notificar) { [void](Send-UTNotification -Titulo 'Upgrade Tweaks: alerta de sensor' -Texto $text -Confirm:$false) }
        }
    }
    if ($m.Log) {
        $vals = @{}
        foreach ($c in $m.Log.Colunas) { $r = $byId[[string]$c.Id]; if ($null -ne $r) { $vals[[string]$c.Id] = $r.Valor } }
        Write-UTMonitorLogLine -Log $m.Log -Valores $vals
        if ($m.Log.Linhas % 5 -eq 0 -and $m.Controles.Log) { $m.Controles.Log.Content = "Parar log ($($m.Log.Linhas) linhas)" }
    }
    if (-not $visible) { return }
    if ($m.Sujo) { $m.Sujo = $false; Show-UTUiMonitorView }

    $every = $(if ($cfg.IntervaloMs -ge 1000) { "$([math]::Round($cfg.IntervaloMs / 1000, 1)) s" } else { "$($cfg.IntervaloMs) ms" })
    $m.Status.Text = "Última leitura: $($snap.Hora.ToString('HH:mm:ss'))  ·  $(@($m.Itens).Count) de $($current.Count) sensores ($($cfg.Layout))  ·  a cada $every"
    $m.Status.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush')
    $spark = (@($m.Itens).Count -le 60)
    foreach ($it in $m.Itens) {
        $v = $m.Visuais[$it.Id]
        $r = $byId[$it.Id]
        if ($null -eq $v -or $null -eq $r) { continue }
        $alarm = ($m.Alertas.ContainsKey($it.Id) -and $m.Alertas[$it.Id].Ativo)
        Update-UTUiMonitorVisual -Visual $v -Linha $r -Config $cfg -Historico $m.Historico -Alerta $alarm -Grafico $spark
    }
}

function Update-UTUiMonitorVisual {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    param([hashtable]$Visual, [psobject]$Linha, [System.Collections.IDictionary]$Config, [hashtable]$Historico, [bool]$Alerta, [bool]$Grafico = $true)
    $t = [string]$Linha.TipoOriginal
    $fmt = { param($x) Format-UTSensorValue -Valor $x -Tipo $t -Unidade $Config.Unidade -Casas $Config.Casas }
    $avg = Get-UTMonitorAverage -Historico $Historico -Id ([string]$Linha.Id)
    # Texts are formatted again only when a value changes at the precision shown.
    $d = Get-UTSensorDecimal -Tipo $t -Casas $Config.Casas
    $key = { param($x) if ($null -eq $x) { '-' } else { [math]::Round([double]$x, $d) } }
    $kNow = & $key $Linha.Valor
    if ($Visual['UltimoAtual'] -ne $kNow -or $null -eq $Visual['UltimoAtual']) { $Visual['UltimoAtual'] = $kNow; $Visual.Valor.Text = & $fmt $Linha.Valor }
    $kRest = "$(& $key $Linha.MinValor)|$(& $key $Linha.MaxValor)|$(& $key $avg)"
    $restChanged = ($Visual['UltimoResto'] -ne $kRest)
    $Visual['UltimoResto'] = $kRest
    if ($Visual.Tipo -eq 'cartao') {
        $faixa = Get-UTField -Objeto $Linha -Nome 'Faixa'
        # Numbers only (the unit is in the big value), so the line fits the card.
        $num = { param($x) (& $fmt $x) -replace '\s+\S*[^\d\s,.-]\S*$', '' }
        if ($faixa -and $null -ne $faixa[0]) { $foot = "núcleos agora: $(& $num $faixa[0]) a $(& $num $faixa[1])"; $Visual.Rodape.Text = $foot }
        elseif ($restChanged) { $Visual.Rodape.Text = "mín $(& $num $Linha.MinValor)  ·  máx $(& $num $Linha.MaxValor)  ·  méd $(& $num $avg)" }
        if ($Grafico -and $Visual.Linha) { Update-UTUiSparkline -Linha $Visual.Linha -Historico $Historico[[string]$Linha.Id] -Largura $Visual.Largura -Altura $Visual.Altura }
    } elseif ($restChanged) {
        $Visual.Minimo.Text = & $fmt $Linha.MinValor
        $Visual.Maximo.Text = & $fmt $Linha.MaxValor
        $Visual.Media.Text = & $fmt $avg
    }
    if ($Visual.EmAlerta -ne $Alerta) {
        $Visual.EmAlerta = $Alerta
        $Visual.Valor.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($Alerta) { 'RedBrush' } else { 'TextBrush' }))
        if ($Visual.Linha) { $Visual.Linha.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, $(if ($Alerta) { 'RedBrush' } else { 'AccentBrush' })) }
    }
}

function Update-UTUiSparkline {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    param($Linha, [hashtable]$Historico, [double]$Largura, [double]$Altura, [int]$Capacidade = 60)
    if ($null -eq $Historico -or $Historico.Valores.Count -lt 2) { return }
    $vals = $Historico.Valores.ToArray()
    $lo = [double]::MaxValue; $hi = [double]::MinValue
    foreach ($v in $vals) { if ($v -lt $lo) { $lo = $v }; if ($v -gt $hi) { $hi = $v } }
    $span = $hi - $lo
    $step = $Largura / ($Capacidade - 1)
    $x = $Largura - ($vals.Count - 1) * $step
    $points = New-Object System.Windows.Media.PointCollection $vals.Count
    foreach ($v in $vals) {
        # A flat line sits in the middle; otherwise the window of values fills the height.
        $y = $(if ($span -le 0) { $Altura / 2 } else { 2 + ($Altura - 4) * (1 - ($v - $lo) / $span) })
        $points.Add((New-Object System.Windows.Point ($x, $y)))
        $x += $step
    }
    $Linha.Points = $points
}
#endregion

#region View (cards / table)
function Show-UTUiMonitorView {
    <#
    .SYNOPSIS
        Rebuilds the cards or the table for the sensors of the layout: favorites first, then by
        device.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $m = (Get-UTUi).Monitor
    $m.Host.Children.Clear()
    $m.Visuais = @{}
    $items = @($m.Itens)
    if ($items.Count -eq 0) {
        $msg = $(if ($m.Config.Layout -eq 'Personalizado') { 'Nenhum sensor no layout Personalizado. Use "Adicionar sensores".' } else { 'Nenhum sensor deste layout foi encontrado neste PC. Tente o layout Completo.' })
        [void]$m.Host.Children.Add((New-UTUiText $msg -Cor MutedBrush -Margem '2,0,0,16'))
        return
    }
    $sections = New-Object System.Collections.Generic.List[object]
    $fav = @($items | Where-Object { $_.Favorito })
    if ($fav.Count -gt 0) { $sections.Add(@{ Titulo = 'Favoritos'; Itens = $fav }) }
    foreach ($g in @($items | Where-Object { -not $_.Favorito } | Group-Object { $_.Linha.Hardware })) { $sections.Add(@{ Titulo = [string]$g.Name; Itens = @($g.Group) }) }
    $cards = ($m.Config.Visao -ne 'Tabela')
    $spark = ($items.Count -le 60)
    foreach ($s in $sections) {
        if ($cards) {
            [void]$m.Host.Children.Add((New-UTUiText $s.Titulo -Tamanho 12 -Peso SemiBold -Cor MutedBrush -Margem '2,4,0,8'))
            $wrap = New-UTUiWrap -Margem '0,0,0,8'
            foreach ($it in $s.Itens) { [void]$wrap.Children.Add((New-UTUiSensorCard -Item $it -Grafico $spark)) }
            [void]$m.Host.Children.Add($wrap)
        } else {
            $rows = @((New-UTUiSensorTableRow -Cabecalho))
            foreach ($it in $s.Itens) { $rows += New-UTUiSensorTableRow -Item $it }
            [void]$m.Host.Children.Add((New-UTUiGroup -Titulo $s.Titulo -Linhas $rows -RecuoSeparador 16))
        }
    }
    if ($cards) { [void]$m.Host.Children.Add((New-UTUiText 'Arraste um cartão para mudar a ordem. Clique para ver detalhes, renomear ou criar um alerta; botão direito para mais opções.' -Tamanho 11.5 -Cor TertiaryBrush -Margem '2,0,0,18')) }
}

function New-UTUiSensorCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    param([Parameter(Mandatory)][psobject]$Item, [bool]$Grafico = $true)
    $m = (Get-UTUi).Monitor
    $width = 204.0; $height = 30.0
    $card = New-Object System.Windows.Controls.Border
    $card.Width = 236
    $card.Margin = '0,0,12,12'
    $card.Padding = '16,12,16,12'
    $card.CornerRadius = 12
    $card.BorderThickness = 1
    $card.Cursor = 'Hand'
    $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'CardBrush')
    $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'SeparatorBrush')
    $card.ToolTip = "$($Item.Linha.Hardware) · $($Item.Linha.Tipo)
Rodapé: mínimo, máximo e média desde que o Monitor abriu."
    [System.Windows.Automation.AutomationProperties]::SetName($card, [string]$Item.NomeExibicao)

    $stack = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.DockPanel
    if ($Item.Favorito) {
        $star = New-UTUiIcon -Glifo 'E735' -Tamanho 11 -Cor 'IconYellow' -Margem '6,0,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($star, 'Right')
        [void]$head.Children.Add($star)
    }
    $title = New-UTUiText ([string]$Item.NomeExibicao) -Tamanho 12.5 -Cor MutedBrush
    $title.TextTrimming = 'CharacterEllipsis'
    [void]$head.Children.Add($title)
    [void]$stack.Children.Add($head)
    $value = New-UTUiText '-' -Tamanho 26 -Peso SemiBold -Margem '0,2,0,0'
    $value.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, 'DisplayFont')
    [void]$stack.Children.Add($value)
    $line = $null
    if ($Grafico) {
        $canvas = New-Object System.Windows.Controls.Canvas
        $canvas.Width = $width; $canvas.Height = $height
        $canvas.Margin = '0,4,0,4'
        $canvas.ClipToBounds = $true
        $line = New-Object System.Windows.Shapes.Polyline
        $line.StrokeThickness = 1.6
        $line.StrokeLineJoin = 'Round'
        $line.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, 'AccentBrush')
        [void]$canvas.Children.Add($line)
        [void]$stack.Children.Add($canvas)
    }
    $foot = New-UTUiText '' -Tamanho 11 -Cor MutedBrush -Margem '0,2,0,0'
    $foot.TextTrimming = 'CharacterEllipsis'
    [void]$stack.Children.Add($foot)
    $card.Child = $stack
    $card.ContextMenu = New-UTUiSensorMenu -Item $Item
    $card.Tag = @{ Id = [string]$Item.Id; Inicio = $null; Arrastou = $false }
    $card.AllowDrop = $true
    $card.Add_PreviewMouseLeftButtonDown({ param($s, $e) $s.Tag.Inicio = $e.GetPosition($null); $s.Tag.Arrastou = $false })
    $card.Add_PreviewMouseMove({
            param($s, $e)
            if ($e.LeftButton -ne 'Pressed' -or $null -eq $s.Tag.Inicio) { return }
            $p = $e.GetPosition($null)
            if ([math]::Abs($p.X - $s.Tag.Inicio.X) -lt 8 -and [math]::Abs($p.Y - $s.Tag.Inicio.Y) -lt 8) { return }
            $s.Tag.Arrastou = $true
            $s.Tag.Inicio = $null
            $mm = (Get-UTUi).Monitor
            $mm.Movimento = $null
            $s.Opacity = 0.5
            try { [void][System.Windows.DragDrop]::DoDragDrop($s, (New-Object System.Windows.DataObject ('UTSensor', [string]$s.Tag.Id)), 'Move') } finally { $s.Opacity = 1 }
            # Applied after the drag ends: the drop target is rebuilt with the new order.
            $mv = $mm.Movimento
            $mm.Movimento = $null
            if ($mv) { Move-UTUiMonitorItem -Id $mv.Id -Antes $mv.Antes }
        })
    $card.Add_MouseLeftButtonUp({ param($s, $e) $null = $e; if (-not $s.Tag.Arrastou -and $null -ne $s.Tag.Inicio) { $s.Tag.Inicio = $null; Show-UTUiSensorDetail -Id $s.Tag.Id } })
    $card.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent('UTSensor')) { $s.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') } })
    $card.Add_DragLeave({ param($s, $e) $null = $e; $s.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'SeparatorBrush') })
    $card.Add_DragOver({ param($s, $e) $null = $s; $e.Effects = $(if ($e.Data.GetDataPresent('UTSensor')) { 'Move' } else { 'None' }); $e.Handled = $true })
    $card.Add_Drop({
            param($s, $e)
            $s.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'SeparatorBrush')
            if (-not $e.Data.GetDataPresent('UTSensor')) { return }
            $id = [string]$e.Data.GetData('UTSensor')
            if ($id -and $id -ne $s.Tag.Id) { (Get-UTUi).Monitor.Movimento = @{ Id = $id; Antes = [string]$s.Tag.Id } }
            $e.Handled = $true
        })
    $m.Visuais[[string]$Item.Id] = @{ Tipo = 'cartao'; Valor = $value; Rodape = $foot; Linha = $line; Largura = $width; Altura = $height; EmAlerta = $false }
    return $card
}

function New-UTUiSensorTableRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    param([psobject]$Item, [switch]$Cabecalho)
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in '*', 120, 110, 110, 110) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) } else { $cd.Width = New-Object System.Windows.GridLength ([double]$w) }
        [void]$grid.ColumnDefinitions.Add($cd)
    }
    $texts = @()
    if ($Cabecalho) {
        $labels = @('Sensor', 'Atual', 'Mínimo', 'Máximo', 'Média')
        for ($i = 0; $i -lt 5; $i++) {
            $tb = New-UTUiText $labels[$i] -Tamanho 11.5 -Peso SemiBold -Cor MutedBrush
            if ($i -gt 0) { $tb.HorizontalAlignment = 'Right' }
            [System.Windows.Controls.Grid]::SetColumn($tb, $i)
            [void]$grid.Children.Add($tb)
        }
        $row = New-Object System.Windows.Controls.Border
        $row.Padding = '16,8,16,6'
        $row.Child = $grid
        return $row
    }
    $name = New-UTUiStack -Horizontal
    if ($Item.Favorito) { [void]$name.Children.Add((New-UTUiIcon -Glifo 'E735' -Tamanho 11 -Cor 'IconYellow' -Margem '0,0,6,0')) }
    $label = New-UTUiText ([string]$Item.NomeExibicao)
    $label.TextTrimming = 'CharacterEllipsis'
    [void]$name.Children.Add($label)
    $name.ToolTip = "$($Item.Linha.Tipo) · $($Item.Linha.NomeOriginal)"
    [void]$grid.Children.Add($name)
    for ($i = 1; $i -lt 5; $i++) {
        $tb = New-UTUiText '-'
        $tb.HorizontalAlignment = 'Right'
        if ($i -eq 1) { $tb.FontWeight = 'SemiBold' }
        [System.Windows.Controls.Grid]::SetColumn($tb, $i)
        [void]$grid.Children.Add($tb)
        $texts += $tb
    }
    $row = New-Object System.Windows.Controls.Border
    $row.Padding = '16,7'
    $row.Background = [System.Windows.Media.Brushes]::Transparent
    $row.Cursor = 'Hand'
    $row.Child = $grid
    $row.ContextMenu = New-UTUiSensorMenu -Item $Item
    $row.Tag = [string]$Item.Id
    $row.Add_MouseLeftButtonUp({ param($s, $e) $null = $e; Show-UTUiSensorDetail -Id ([string]$s.Tag) })
    (Get-UTUi).Monitor.Visuais[[string]$Item.Id] = @{ Tipo = 'tabela'; Valor = $texts[0]; Minimo = $texts[1]; Maximo = $texts[2]; Media = $texts[3]; Linha = $null; EmAlerta = $false }
    return $row
}

function New-UTUiSensorMenu {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    param([Parameter(Mandatory)][psobject]$Item)
    $menu = New-Object System.Windows.Controls.ContextMenu
    $entries = @(
        @($(if ($Item.Favorito) { 'Tirar dos favoritos' } else { 'Adicionar aos favoritos' }), 'Favorito')
        @('Detalhes, nome e alerta...', 'Detalhes')
        @('Mover para o início', 'Inicio')
        @('Mover para o fim', 'Fim')
        @('Ocultar', 'Ocultar')
    )
    foreach ($e in $entries) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $e[0]
        $mi.Tag = @{ Acao = $e[1]; Id = [string]$Item.Id }
        $mi.Add_Click({ param($s, $ev) $null = $ev; try { Invoke-UTUiMonitorAction -Acao $s.Tag.Acao -Id $s.Tag.Id } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
        [void]$menu.Items.Add($mi)
    }
    return $menu
}
#endregion

#region Actions
function Invoke-UTUiMonitorAction {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the preferences of the Monitor tab.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Favorito', 'Detalhes', 'Inicio', 'Fim', 'Ocultar')][string]$Acao, [Parameter(Mandatory)][string]$Id)
    $m = (Get-UTUi).Monitor
    switch ($Acao) {
        'Detalhes' { Show-UTUiSensorDetail -Id $Id }
        'Favorito' {
            $c = ConvertTo-UTMonitorConfig -Config $m.Config
            if ($c.Favoritos -contains $Id) { $c.Favoritos = @($c.Favoritos | Where-Object { $_ -ne $Id }) } else { $c.Favoritos = @($c.Favoritos) + $Id }
            Save-UTUiMonitorConfig -Config $c
        }
        'Ocultar' { Hide-UTUiMonitorItem -Id $Id }
        'Inicio' { $first = (@($m.Itens) | Select-Object -First 1); if ($first -and $first.Id -ne $Id) { Move-UTUiMonitorItem -Id $Id -Antes $first.Id } }
        'Fim' { Move-UTUiMonitorItem -Id $Id }
    }
}

function Move-UTUiMonitorItem {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the preferences of the Monitor tab.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [string]$Antes)
    $m = (Get-UTUi).Monitor
    $from = $m.Config.Layout
    $c = Set-UTMonitorCustomList -Linhas $m.Linhas -Config $m.Config -Mover $Id -Antes $Antes
    Save-UTUiMonitorConfig -Config $c -Mensagem $(if ($from -ne 'Personalizado') { "Layout Personalizado criado a partir do $from, com a nova ordem." } else { '' })
}

function Hide-UTUiMonitorItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $m = (Get-UTUi).Monitor
    $from = $m.Config.Layout
    $c = Set-UTMonitorCustomList -Linhas $m.Linhas -Config $m.Config -Ocultar $Id
    Save-UTUiMonitorConfig -Config $c -Mensagem $(if ($from -ne 'Personalizado') { "Layout Personalizado criado a partir do $from, sem esse sensor. Para trazer de volta: Adicionar sensores." } else { 'Sensor ocultado. Para trazer de volta: Adicionar sensores.' })
}

function Show-UTUiMonitorAddSensor {
    <#
    .SYNOPSIS
        List of the sensors that are not on screen, to add to the Personalizado layout.
    #>
    [CmdletBinding()]
    param()
    $m = (Get-UTUi).Monitor
    $shown = @($m.Itens | ForEach-Object { $_.Id })
    $all = @($m.Atuais.Values | Sort-Object { $_.Hardware }, { $_.Ordem })
    $items = foreach ($r in $all) {
        if ($shown -contains [string]$r.Id) { continue }
        $now = Format-UTSensorValue -Valor $r.Valor -Tipo ([string]$r.TipoOriginal) -Unidade $m.Config.Unidade -Casas $m.Config.Casas
        [pscustomobject]@{ Id = [string]$r.Id; Texto = [string]$r.Sensor; Detalhe = "$($r.Hardware) · $($r.Tipo) · agora $now"; Marcado = $false }
    }
    if (@($items).Count -eq 0) { [void](Show-UTUiDialog -Titulo 'Todos os sensores já estão na tela' -Mensagem 'Não há outros sensores para adicionar.' -Tipo info); return }
    $pick = Show-UTUiChecklistDialog -Titulo 'Adicionar sensores' -Mensagem 'Ligue os sensores que você quer ver. Eles entram no fim; arraste para mudar a ordem.' -Itens @($items) -BotaoOk 'Adicionar'
    if ($null -eq $pick -or @($pick).Count -eq 0) { return }
    $c = Set-UTMonitorCustomList -Linhas $m.Linhas -Config $m.Config -Mostrar @($pick)
    Save-UTUiMonitorConfig -Config $c -Mensagem "$(@($pick).Count) sensor(es) adicionado(s)."
}

function Switch-UTUiMonitorLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes only a file chosen by the person.')]
    [CmdletBinding()]
    param($Botao)
    $m = (Get-UTUi).Monitor
    if ($m.Log) {
        $path = $m.Log.Caminho; $n = $m.Log.Linhas
        Close-UTMonitorLog -Log $m.Log
        $m.Log = $null
        if ($Botao) { $Botao.Content = 'Gravar log' }
        Show-UTUiStatus "Log salvo: $path ($n leituras)."
        return
    }
    if (@($m.Itens).Count -eq 0) { return }
    $p = Get-UTUiFileDialog -Modo Salvar -Filtro 'CSV (*.csv)|*.csv' -NomeSugerido ('log-sensores-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.csv')
    if (-not $p) { return }
    $cols = @($m.Itens | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Nome = $_.NomeExibicao; Tipo = [string]$_.Linha.TipoOriginal } })
    $m.Log = New-UTMonitorLog -Path $p -Colunas $cols -Unidade $m.Config.Unidade -Confirm:$false
    if ($Botao) { $Botao.Content = 'Parar log' }
    $m.Recalcular = $true
    Show-UTUiStatus "Gravando $($cols.Count) sensores em $p a cada leitura."
}

function Show-UTUiSensorDetail {
    <#
    .SYNOPSIS
        Sheet of one sensor: values, own name, favorite and the alert limits.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $m = (Get-UTUi).Monitor
    $r = $m.Atuais[$Id]
    if ($null -eq $r) { return }
    $cfg = $m.Config
    $t = [string]$r.TipoOriginal
    $fmt = { param($x) Format-UTSensorValue -Valor $x -Tipo $t -Unidade $cfg.Unidade -Casas $cfg.Casas }
    $unit = Get-UTMonitorUnitName -Tipo $t -Unidade $cfg.Unidade
    $pairs = @(
        @('Dispositivo', [string]$r.Hardware), @('Tipo', [string]$r.Tipo), @('Nome original', [string]$r.NomeOriginal)
        @('Agora', (& $fmt $r.Valor)), @('Mínimo', (& $fmt $r.MinValor)), @('Máximo', (& $fmt $r.MaxValor)), @('Média', (& $fmt (Get-UTMonitorAverage -Historico $m.Historico -Id $Id)))
    )
    $name = New-Object System.Windows.Controls.TextBox
    $name.Width = 240
    $name.Tag = [string]$r.Sensor
    if ($cfg.Nomes.Contains($Id)) { $name.Text = [string]$cfg.Nomes[$Id] }
    $fav = New-UTUiSwitch -Marcado ($cfg.Favoritos -contains $Id) -Dica 'Favorito'
    $lim = $null
    if ($cfg.Alertas.Contains($Id)) { $lim = $cfg.Alertas[$Id] }
    $toText = { param($x) if ($null -eq $x) { '' } else { (ConvertTo-UTMonitorUnit -Valor $x -Tipo $t -Unidade $cfg.Unidade).ToString('0.##', [Globalization.CultureInfo]::GetCultureInfo('pt-BR')) } }
    $above = New-Object System.Windows.Controls.TextBox; $above.Width = 90; $above.Tag = 'nenhum'
    $below = New-Object System.Windows.Controls.TextBox; $below.Width = 90; $below.Tag = 'nenhum'
    if ($lim) { $above.Text = & $toText $lim.Acima; $below.Text = & $toText $lim.Abaixo }
    $default = (Get-UTMonitorAlertLimit -Linhas @($r) -Config $cfg)[$Id]
    $hint = $(if ($default -and $default.Padrao -and -not $lim) { "Alerta padrão: acima de $(& $fmt $default.Acima)." } else { 'Avisa com uma notificação do Windows quando passar do limite (uma vez por minuto, no máximo).' })
    $content = New-UTUiStack -Itens @(
        (New-UTUiKeyValue -Pares $pairs -LarguraRotulo 120)
        (New-UTUiGroup -Linhas @(
                (New-UTUiRow -Titulo 'Nome na tela' -Subtitulo 'Vazio = nome padrão' -Direita $name)
                (New-UTUiRow -Titulo 'Favorito' -Subtitulo 'Fica no topo, em qualquer layout' -Direita $fav)
                (New-UTUiRow -Titulo "Avisar acima de ($unit)" -Subtitulo $hint -Direita $above)
                (New-UTUiRow -Titulo "Avisar abaixo de ($unit)" -Subtitulo 'Útil para ventoinhas paradas (RPM) ou tensões baixas' -Direita $below)
            ) -RecuoSeparador 16)
    )
    $content.Children[1].Margin = '0,14,0,0'
    $answer = Show-UTUiSheet -Titulo $(if ($cfg.Nomes.Contains($Id)) { [string]$cfg.Nomes[$Id] } else { [string]$r.Sensor }) -Tipo info -Conteudo $content -Botoes @('Salvar', 'Ocultar', 'Cancelar')
    if ($answer -eq 'Ocultar') { Hide-UTUiMonitorItem -Id $Id; return }
    if ($answer -ne 'Salvar') { return }
    $c = ConvertTo-UTMonitorConfig -Config $cfg
    $newName = $name.Text.Trim()
    if ($newName -and $newName -ne [string]$r.Sensor) { $c.Nomes[$Id] = $newName } elseif ($c.Nomes.Contains($Id)) { $c.Nomes.Remove($Id) }
    $isFav = [bool]$fav.IsChecked
    if ($isFav -and $c.Favoritos -notcontains $Id) { $c.Favoritos = @($c.Favoritos) + $Id }
    if (-not $isFav) { $c.Favoritos = @($c.Favoritos | Where-Object { $_ -ne $Id }) }
    $parse = {
        param($s)
        $s = $s.Trim().Replace(',', '.')
        if (-not $s) { return $null }
        $v = 0.0
        if (-not [double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { throw "Valor de alerta inválido: $s" }
        # Limits are kept in °C, whatever the unit on screen.
        if ($t -eq 'Temperature' -and $cfg.Unidade -eq 'F') { $v = ($v - 32) * 5 / 9 }
        return $v
    }
    $a = & $parse $above.Text
    $b = & $parse $below.Text
    if ($null -eq $a -and $null -eq $b) { if ($c.Alertas.Contains($Id)) { $c.Alertas.Remove($Id) } }
    else { $c.Alertas[$Id] = [ordered]@{ Acima = $a; Abaixo = $b } }
    if ($m.Alertas.ContainsKey($Id)) { $m.Alertas.Remove($Id) }
    Save-UTUiMonitorConfig -Config $c -Mensagem 'Sensor atualizado.'
}

function Show-UTUiMonitorPreference {
    <#
    .SYNOPSIS
        Sheet with the Monitor settings, the layout export/import and the reset.
    #>
    [CmdletBinding()]
    param()
    $m = (Get-UTUi).Monitor
    $cfg = $m.Config
    $combo = {
        param([string[]]$Itens, [int]$Indice)
        $cb = New-Object System.Windows.Controls.ComboBox
        $cb.MinWidth = 150
        foreach ($i in $Itens) { [void]$cb.Items.Add($i) }
        $cb.SelectedIndex = [math]::Max(0, $Indice)
        return $cb
    }
    $intervals = @(250, 500, 1000, 2000)
    $iv = & $combo @('250 ms', '500 ms', '1 segundo', '2 segundos') ([array]::IndexOf($intervals, [int]$cfg.IntervaloMs))
    if ($intervals -notcontains [int]$cfg.IntervaloMs) { $iv.SelectedIndex = 2 }
    $un = & $combo @('°C (Celsius)', '°F (Fahrenheit)') $(if ($cfg.Unidade -eq 'F') { 1 } else { 0 })
    $dc = & $combo @('Nenhuma (47 °C)', 'Uma (47,3 °C)', 'Duas (47,25 °C)') ([int]$cfg.Casas)
    $zero = New-UTUiSwitch -Marcado ([bool]$cfg.OcultarZerados) -Dica 'Esconder sensores que só marcam zero'
    $cores = New-UTUiSwitch -Marcado ([bool]$cfg.ResumoNucleos) -Dica 'Resumo dos núcleos'
    $defaults = New-UTUiSwitch -Marcado ([bool]$cfg.AlertasPadrao) -Dica 'Alertas padrão'
    $notify = New-UTUiSwitch -Marcado ([bool]$cfg.Notificar) -Dica 'Notificações'
    $links = New-UTUiWrap -Itens @(
        (New-UTUiButton 'Exportar layout...' -Estilo Link -Margem '0,0,18,0' -AoClicar {
                param($b, $d) $null = $b, $d
                $p = Get-UTUiFileDialog -Modo Salvar -Filtro 'Layout do Monitor (*.json)|*.json' -NomeSugerido 'monitor-layout.json'
                if ($p) { [void](Export-UTMonitorLayout -Path $p -Config (Get-UTUi).Monitor.Config -Confirm:$false); Show-UTUiStatus "Layout exportado para $p" }
            })
        (New-UTUiButton 'Importar layout...' -Estilo Link -Margem '0,0,18,0' -AoClicar {
                param($b, $d) $null = $b, $d
                $p = Get-UTUiFileDialog -Modo Abrir -Filtro 'Layout do Monitor (*.json)|*.json'
                if (-not $p) { return }
                $st = (Get-UTUi).SheetEstado
                $st.Importado = Import-UTMonitorLayout -Path $p -Confirm:$false
                $st.Resultado = 'Importado'
                $st.Frame.Continue = $false
            })
        (New-UTUiButton 'Voltar ao padrão' -Estilo Link -Margem '0' -AoClicar {
                param($b, $d) $null = $b, $d
                $st = (Get-UTUi).SheetEstado
                $st.Resultado = 'Padrao'
                $st.Frame.Continue = $false
            })
    )
    $content = New-UTUiStack -Itens @(
        (New-UTUiGroup -RecuoSeparador 16 -Linhas @(
                (New-UTUiRow -Titulo 'Atualizar a cada' -Subtitulo 'Mais rápido = mais detalhe nos gráficos, um pouco mais de CPU' -Direita $iv)
                (New-UTUiRow -Titulo 'Temperatura em' -Direita $un)
                (New-UTUiRow -Titulo 'Casas decimais' -Subtitulo 'Temperatura, uso e consumo' -Direita $dc)
                (New-UTUiRow -Titulo 'Esconder sensores que só marcam zero' -Subtitulo 'Conectores de ventoinha vazios, motores de vídeo parados...' -Direita $zero)
                (New-UTUiRow -Titulo 'Resumo dos núcleos' -Subtitulo 'Uma linha com a média em vez de uma por núcleo' -Direita $cores)
                (New-UTUiRow -Titulo 'Alertas padrão' -Subtitulo 'Processador 90 °C, placa de vídeo 85 °C (hotspot 105 °C), SSD 70 °C' -Direita $defaults)
                (New-UTUiRow -Titulo 'Notificação do Windows nos alertas' -Direita $notify)
            ))
        $links
    )
    $answer = Show-UTUiSheet -Titulo 'Ajustes do Monitor' -Tipo info -Conteudo $content -Botoes @('Salvar', 'Cancelar')
    switch ($answer) {
        'Importado' {
            # Import-UTMonitorLayout already saved them; apply them now.
            Save-UTUiMonitorConfig -Config (Get-UTMonitorConfig) -Mensagem 'Layout importado.'
        }
        'Padrao' { Save-UTUiMonitorConfig -Config (Get-UTMonitorDefault) -Mensagem 'Monitor de volta ao padrão.' }
        'Salvar' {
            $c = ConvertTo-UTMonitorConfig -Config $cfg
            $c.IntervaloMs = $intervals[[math]::Max(0, $iv.SelectedIndex)]
            $c.Unidade = $(if ($un.SelectedIndex -eq 1) { 'F' } else { 'C' })
            $c.Casas = [math]::Max(0, $dc.SelectedIndex)
            $c.OcultarZerados = [bool]$zero.IsChecked
            $c.ResumoNucleos = [bool]$cores.IsChecked
            $c.AlertasPadrao = [bool]$defaults.IsChecked
            $c.Notificar = [bool]$notify.IsChecked
            Save-UTUiMonitorConfig -Config $c -Mensagem 'Ajustes do Monitor salvos.'
        }
    }
}
#endregion

#region Hardware summary (CPU-Z)
function New-UTUiMonitorSpecCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $data = @{}
    # With the monitor starting, wait for its first reading: it brings the SPD timings.
    $panel = New-UTUiAsyncPanel -Nome 'Resumo do hardware' -Dados $data -Script {
        $t = 0
        while ((Get-UTSyncValue -Key 'SensoresJob') -and -not (Get-UTSyncValue -Key 'Sensores') -and $t -lt 150) { Start-Sleep -Milliseconds 100; $t++ }
        Get-UTSystemSpec
    } -Montar {
        param($R, $D) $null = $D
        $wrap = New-UTUiWrap
        foreach ($s in @($R)) {
            $box = New-UTUiStack -Margem '0,0,24,12'
            $box.Width = 430
            [void]$box.Children.Add((New-UTUiText $s.Titulo -Tamanho 12 -Peso SemiBold -Cor AccentLightBrush -Margem '0,0,0,2'))
            [void]$box.Children.Add((New-UTUiKeyValue -Pares @($s.Itens) -LarguraRotulo 170))
            [void]$wrap.Children.Add($box)
        }
        return $wrap
    }
    $data.Painel = $panel
    $refresh = New-UTUiButton 'Atualizar' -Icone 'E72C' -Dados $data -Margem '0,4,0,0' -AoClicar { param($b, $d) $null = $b; Sync-UTUiAsyncPanel -Painel $d.Painel }
    return (New-UTUiCard -Titulo 'Resumo do hardware' -Icone 'E950' -Subtitulo 'Processador, placa-mãe, BIOS, memória (com os timings do SPD quando o monitor está ligado) e placas de vídeo.' -Conteudo @($panel, $refresh))
}
#endregion
