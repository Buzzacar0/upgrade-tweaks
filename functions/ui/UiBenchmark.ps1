# Benchmark tab: record the frame times of a game (with a delay to go back to it), the saved runs,
# the summary and frame time chart of one run, CSV, and the comparison of two runs.

function New-UTUiPageBenchmark {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    Initialize-UTOverlayNative
    $ui = Get-UTUi
    $b = @{ Sessao = $null; Fase = ''; Ate = [datetime]::MinValue; Inicio = [datetime]::MinValue; Timer = $null; Status = $null; Botao = $null; Lista = $null; Detalhe = $null; Selecionados = (New-Object System.Collections.Generic.List[string]); Duracao = $null; Atraso = $null }
    $ui.Benchmark = $b
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'Benchmark' -Descricao 'Grave os frametimes de uma partida e compare antes e depois de um ajuste. Mesma medição do overlay: PresentMon oficial da Intel, sem injetar nada no jogo.'))

    $b.Duracao = New-Object System.Windows.Controls.ComboBox
    $b.Duracao.Width = 150
    foreach ($d in '30 segundos', '1 minuto', '2 minutos', '5 minutos') { [void]$b.Duracao.Items.Add($d) }
    $b.Duracao.SelectedIndex = 1
    $b.Atraso = New-Object System.Windows.Controls.ComboBox
    $b.Atraso.Width = 150
    foreach ($d in '5 segundos', '10 segundos', '30 segundos') { [void]$b.Atraso.Items.Add($d) }
    $b.Atraso.SelectedIndex = 1
    $b.Status = New-UTUiText $(if (Test-UTPresentMon) { 'Pronto para gravar.' } else { 'Falta o PresentMon: instale na aba Overlay.' }) -Tamanho 12 -Cor MutedBrush -Quebrar
    $b.Botao = New-UTUiButton 'Gravar' -Estilo Primario -Icone 'E7C8' -Margem '0' -AoClicar { param($bt, $d) $null = $bt, $d; Switch-UTUiBenchmarkRecording }
    $b.Botao.IsEnabled = (Test-UTPresentMon)
    $hotkey = [string](Get-UTOverlayConfig).Atalhos.Benchmark
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Gravar' -RecuoSeparador 16 -Linhas @(
                (New-UTUiRow -Titulo 'Duração' -Direita $b.Duracao)
                (New-UTUiRow -Titulo 'Começar depois de' -Subtitulo 'Tempo para voltar para o jogo' -Direita $b.Atraso)
                (New-UTUiRow -Titulo 'Gravação' -Subtitulo $null -Direita $b.Botao)
                (New-UTUiRowBox $b.Status)
            ) -Rodape "Dentro do jogo, com o overlay ligado: $hotkey começa e para a gravação. Para comparar, grave o mesmo trecho (ex.: o mesmo lugar do mapa) antes e depois da mudança."))

    $b.Lista = New-Object System.Windows.Controls.ContentControl
    $b.Detalhe = New-Object System.Windows.Controls.ContentControl
    [void]$page.Children.Add($b.Lista)
    [void]$page.Children.Add($b.Detalhe)
    Show-UTUiBenchmarkList

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({ try { Update-UTUiBenchmarkRecording } catch { Write-UTLog -Level Aviso -Message 'Falha na gravação do benchmark.' -Detalhe $_.Exception.Message } })
    $b.Timer = $timer
    return $page
}

function Switch-UTUiBenchmarkRecording {
    <#
    .SYNOPSIS
        "Gravar": starts PresentMon, waits the delay (time to go back to the game), records the
        game for the duration and saves. Clicked again: stops (saving what was recorded).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Records frame times (read only).')]
    [CmdletBinding()]
    param()
    $b = (Get-UTUi).Benchmark
    if ($b.Fase -eq 'gravando') { Complete-UTUiBenchmarkRecording; return }
    if ($b.Fase -eq 'espera') { Stop-UTUiBenchmarkSession; $b.Status.Text = 'Gravação cancelada.'; return }
    if (-not (Test-UTPresentMon)) { [void](Show-UTUiDialog -Titulo 'Falta o PresentMon' -Mensagem 'Instale o PresentMon na aba Overlay (é a ferramenta oficial da Intel que mede os quadros).' -Tipo info); return }
    $b.Sessao = New-Object UpgradeTweaks.Overlay.PresentMonSession
    $b.Sessao.Start((Get-UTPresentMonPath), (Get-UTPresentMonArgument -Sessao 'UpgradeTweaksBenchmark'))
    $delay = @(5, 10, 30)[[math]::Max(0, $b.Atraso.SelectedIndex)]
    $b.Fase = 'espera'
    $b.Ate = [datetime]::Now.AddSeconds($delay)
    $b.Botao.Content = 'Cancelar'
    $b.Timer.Start()
    Update-UTUiBenchmarkRecording
}

function Update-UTUiBenchmarkRecording {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $b = (Get-UTUi).Benchmark
    if ($null -eq $b -or -not $b.Fase) { return }
    $left = [math]::Ceiling(($b.Ate - [datetime]::Now).TotalSeconds)
    if ($b.Fase -eq 'espera') {
        if ($left -gt 0) { $b.Status.Text = "Volte para o jogo: a gravação começa em $left s."; return }
        $p = Start-UTBenchmarkRecording -Sessao $b.Sessao -Confirm:$false
        if ($p -le 0) {
            if ($left -lt -15) { Stop-UTUiBenchmarkSession; $b.Status.Text = 'Nenhum jogo desenhou quadros. Abra o jogo e tente de novo.'; return }
            $b.Status.Text = 'Esperando um jogo desenhar quadros...'
            return
        }
        $secs = @(30, 60, 120, 300)[[math]::Max(0, $b.Duracao.SelectedIndex)]
        $b.Fase = 'gravando'
        $b.Inicio = [datetime]::Now
        $b.Ate = [datetime]::Now.AddSeconds($secs)
        $b.Botao.Content = 'Parar e salvar'
        return
    }
    if ($left -gt 0) {
        $b.Status.Text = "Gravando $($b.Sessao.ApplicationOf($b.Sessao.RecordingPid)): faltam $left s, $($b.Sessao.RecordedFrames) quadros."
        return
    }
    Complete-UTUiBenchmarkRecording
}

function Complete-UTUiBenchmarkRecording {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Saves a file of the person.')]
    [CmdletBinding()]
    param()
    $b = (Get-UTUi).Benchmark
    $mode = [string]$b.Sessao.GetStats($b.Sessao.RecordingPid, 1000, 1000, 0).PresentMode
    $run = Stop-UTBenchmarkRecording -Sessao $b.Sessao -Inicio $b.Inicio -ModoApresentacao $mode -Confirm:$false
    Stop-UTUiBenchmarkSession
    if ($null -eq $run) { $b.Status.Text = 'Gravação muito curta: nada foi salvo.'; return }
    $text = ("{0}: FPS médio {1}, 1% low {2}, 0,1% low {3}." -f $run.Jogo, (Format-UTOverlayNumber $run.Resumo.FpsMedio), (Format-UTOverlayNumber $run.Resumo.Low1), (Format-UTOverlayNumber $run.Resumo.Low01))
    $b.Status.Text = "Salvo. $text"
    [void](Send-UTNotification -Titulo 'Upgrade Tweaks: benchmark pronto' -Texto $text -Confirm:$false)
    Show-UTUiBenchmarkList
    Show-UTUiBenchmarkDetail -Id $run.Id
}

function Stop-UTUiBenchmarkSession {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops a read-only capture.')]
    [CmdletBinding()]
    param()
    $b = (Get-UTUi).Benchmark
    if ($b.Timer) { $b.Timer.Stop() }
    if ($b.Sessao) { $b.Sessao.Stop(); $b.Sessao = $null }
    $b.Fase = ''
    $b.Botao.Content = 'Gravar'
}

function Show-UTUiBenchmarkList {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $b = (Get-UTUi).Benchmark
    $runs = @(Get-UTBenchmarkRun)
    foreach ($id in @($b.Selecionados)) { if (@($runs | ForEach-Object Id) -notcontains $id) { [void]$b.Selecionados.Remove($id) } }
    if ($runs.Count -eq 0) {
        $b.Lista.Content = New-UTUiGroup -Titulo 'Gravações' -Linhas @((New-UTUiRowBox (New-UTUiText 'Nenhuma gravação ainda.' -Cor MutedBrush)))
        return
    }
    $rows = foreach ($r in $runs) {
        $s = $r.Resumo
        $pick = New-Object System.Windows.Controls.CheckBox
        $pick.Content = 'Comparar'
        $pick.IsChecked = $b.Selecionados.Contains([string]$r.Id)
        $pick.Tag = [string]$r.Id
        $pick.Margin = '14,0,6,0'
        $pick.Add_Click({
                param($cb, $e) $null = $e
                $bb = (Get-UTUi).Benchmark
                $id = [string]$cb.Tag
                if ($cb.IsChecked) { [void]$bb.Selecionados.Add($id); while ($bb.Selecionados.Count -gt 2) { $bb.Selecionados.RemoveAt(0) } } else { [void]$bb.Selecionados.Remove($id) }
                Show-UTUiBenchmarkList
                if ($bb.Selecionados.Count -eq 2) { Show-UTUiBenchmarkComparison }
            })
        $numbers = New-UTUiText ("{0} FPS  ·  1% {1}" -f (Format-UTOverlayNumber $s.FpsMedio), (Format-UTOverlayNumber $s.Low1)) -Peso SemiBold
        $actions = New-UTUiStack -Horizontal -Itens @(
            $numbers
            (New-UTUiButton 'Ver' -Estilo Link -Margem '16,0,0,0' -Dados ([string]$r.Id) -AoClicar { param($bt, $d) $null = $bt; Show-UTUiBenchmarkDetail -Id $d })
            (New-UTUiButton 'CSV' -Estilo Link -Margem '12,0,0,0' -Dados ([string]$r.Id) -AoClicar { param($bt, $d) $null = $bt; Export-UTUiBenchmarkCsv -Id $d })
            (New-UTUiButton 'Excluir' -Estilo Link -Margem '12,0,0,0' -Dados ([string]$r.Id) -AoClicar {
                    param($bt, $d) $null = $bt
                    if ((Show-UTUiDialog -Titulo 'Excluir esta gravação?' -Mensagem 'O arquivo do benchmark é apagado.' -Tipo pergunta -Botoes @('Excluir', 'Cancelar')) -ne 'Excluir') { return }
                    Remove-UTBenchmarkRun -Id $d -Confirm:$false
                    (Get-UTUi).Benchmark.Detalhe.Content = $null
                    Show-UTUiBenchmarkList
                })
            $pick
        )
        $sub = "{0}  ·  {1}  ·  {2} s  ·  {3:N0} quadros" -f $r.Jogo, ([datetime]$r.Inicio).ToString('dd/MM/yyyy HH:mm'), (Format-UTOverlayNumber $s.DuracaoS), [int]$s.Quadros
        New-UTUiRow -Titulo ([string]$r.Nome) -Subtitulo $sub -Icone 'E9F5' -IconeCor 'IconPink' -Direita $actions
    }
    $foot = $(if ($b.Selecionados.Count -eq 2) { 'Comparando as duas marcadas (abaixo).' } else { 'Marque duas gravações em "Comparar" para ver a diferença entre elas.' })
    $b.Lista.Content = New-UTUiGroup -Titulo 'Gravações' -Linhas @($rows) -Rodape $foot
}

function Export-UTUiBenchmarkCsv {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes only a file chosen by the person.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $run = (@(Get-UTBenchmarkRun -Id $Id) | Select-Object -First 1)
    if ($null -eq $run) { return }
    $p = Get-UTUiFileDialog -Modo Salvar -Filtro 'CSV (*.csv)|*.csv' -NomeSugerido "benchmark-$Id.csv"
    if (-not $p) { return }
    [void](Export-UTBenchmarkCsv -Run $run -Path $p -Confirm:$false)
    Show-UTUiStatus "CSV salvo em $p"
}

function New-UTUiFrametimeChart {
    <#
    .SYNOPSIS
        Frame time over time for one or two runs (the slowest frame of each stretch, so every
        stutter shows), with reference lines at 60, 144 and 240 FPS.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Series, [double]$Largura = 760, [double]$Altura = 200)
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $Largura; $canvas.Height = $Altura
    $canvas.ClipToBounds = $true
    $all = @()
    foreach ($s in $Series) { $all += [UpgradeTweaks.Overlay.FrameMath]::Percentile([double[]]$s.Frametimes, 0.999) }
    $top = [math]::Max(20, ($all | Measure-Object -Maximum).Maximum * 1.2)
    $longest = 0.0
    foreach ($s in $Series) { $t = 0.0; foreach ($v in $s.Frametimes) { $t += [double]$v }; if ($t -gt $longest) { $longest = $t } }
    $y = { param($ms) $Altura - 2 - [math]::Min($Altura - 4, ($ms / $top) * ($Altura - 4)) }
    foreach ($ref in @(@(16.67, '60 FPS'), @(6.94, '144 FPS'), @(4.17, '240 FPS'))) {
        if ($ref[0] -gt $top) { continue }
        $line = New-Object System.Windows.Shapes.Line
        $line.X1 = 0; $line.X2 = $Largura; $line.Y1 = & $y $ref[0]; $line.Y2 = $line.Y1
        $line.StrokeThickness = 1
        $line.StrokeDashArray = [System.Windows.Media.DoubleCollection]::Parse('4 4')
        $line.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, 'SeparatorBrush')
        [void]$canvas.Children.Add($line)
        $lab = New-UTUiText $ref[1] -Tamanho 10 -Cor TertiaryBrush
        [System.Windows.Controls.Canvas]::SetLeft($lab, 4); [System.Windows.Controls.Canvas]::SetTop($lab, $line.Y1 - 14)
        [void]$canvas.Children.Add($lab)
    }
    foreach ($s in $Series) {
        $f = [double[]]$s.Frametimes
        if ($f.Count -lt 2) { continue }
        # Points spread by time, the slowest frame of each pixel column.
        $cols = [int]$Largura
        $peak = New-Object 'double[]' $cols
        $t = 0.0
        foreach ($v in $f) {
            $c = [int][math]::Min($cols - 1, [math]::Floor($t / $longest * $cols))
            if ($v -gt $peak[$c]) { $peak[$c] = $v }
            $t += $v
        }
        $points = New-Object System.Windows.Media.PointCollection
        for ($c = 0; $c -lt $cols; $c++) { if ($peak[$c] -gt 0) { $points.Add((New-Object System.Windows.Point ($c, (& $y $peak[$c])))) } }
        $pl = New-Object System.Windows.Shapes.Polyline
        $pl.Points = $points
        $pl.StrokeThickness = 1.3
        $pl.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, [string]$s.Cor)
        [void]$canvas.Children.Add($pl)
    }
    $legend = New-UTUiWrap -Margem '0,6,0,0'
    foreach ($s in $Series) {
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 9; $dot.Height = 9; $dot.Margin = '0,0,6,0'
        $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, [string]$s.Cor)
        [void]$legend.Children.Add((New-UTUiStack -Horizontal -Margem '0,0,18,0' -Itens @($dot, (New-UTUiText ([string]$s.Nome) -Tamanho 12 -Cor MutedBrush))))
    }
    [void]$legend.Children.Add((New-UTUiText ("Escala: 0 a {0} ms; {1} s" -f (Format-UTOverlayNumber $top), (Format-UTOverlayNumber ($longest / 1000))) -Tamanho 12 -Cor TertiaryBrush))
    return (New-UTUiStack -Itens @($canvas, $legend))
}

function Show-UTUiBenchmarkDetail {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $b = (Get-UTUi).Benchmark
    $run = (@(Get-UTBenchmarkRun -Id $Id) | Select-Object -First 1)
    if ($null -eq $run) { return }
    $pairs = @(@('Jogo', [string]$run.Jogo), @('Início', ([datetime]$run.Inicio).ToString('dd/MM/yyyy HH:mm:ss')), @('Duração', "$(Format-UTOverlayNumber $run.Resumo.DuracaoS 1) s"), @('Quadros', ('{0:N0}' -f [int]$run.Resumo.Quadros)))
    if ($run.ModoApresentacao) { $pairs += , @('Modo de apresentação', [string]$run.ModoApresentacao) }
    foreach ($m in Get-UTBenchmarkMetric) { $pairs += , @($m.Nome, (Format-UTOverlayNumber $run.Resumo.($m.Chave) $m.Casas)) }
    $chart = New-UTUiFrametimeChart -Series @([pscustomobject]@{ Frametimes = [double[]]@($run.Frametimes); Cor = 'AccentBrush'; Nome = [string]$run.Nome })
    $rename = New-UTUiButton 'Renomear' -Estilo Link -Margem '0' -Dados $Id -AoClicar {
        param($bt, $d) $null = $bt
        $box = New-Object System.Windows.Controls.TextBox
        $box.Width = 320
        $box.Text = [string](@(Get-UTBenchmarkRun -Id $d) | Select-Object -First 1).Nome
        if ((Show-UTUiSheet -Titulo 'Renomear gravação' -Mensagem 'Ex.: "Antes do Modo Partida", "Depois do driver novo".' -Conteudo $box -Botoes @('OK', 'Cancelar') -Tipo pergunta) -ne 'OK' -or -not $box.Text.Trim()) { return }
        Rename-UTBenchmarkRun -Id $d -Nome $box.Text -Confirm:$false
        Show-UTUiBenchmarkList
        Show-UTUiBenchmarkDetail -Id $d
    }
    $b.Detalhe.Content = New-UTUiGroup -Titulo ([string]$run.Nome) -RecuoSeparador 16 -Linhas @(
        (New-UTUiRowBox (New-UTUiKeyValue -Pares $pairs -LarguraRotulo 230))
        (New-UTUiRowBox $chart)
        (New-UTUiRowBox $rename)
    )
}

function Show-UTUiBenchmarkComparison {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds UI elements; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $b = (Get-UTUi).Benchmark
    if ($b.Selecionados.Count -ne 2) { return }
    $runs = @($b.Selecionados | ForEach-Object { @(Get-UTBenchmarkRun -Id $_) | Select-Object -First 1 } | Sort-Object { [datetime]$_.Inicio })
    if ($runs.Count -ne 2) { return }
    $a = $runs[0]; $z = $runs[1]
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in '*', 130, 130, 120) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) } else { New-Object System.Windows.GridLength ([double]$w) })
        [void]$grid.ColumnDefinitions.Add($cd)
    }
    $cell = {
        param($text, [int]$row, [int]$col, [string]$cor = 'TextBrush', [string]$peso = 'Normal')
        $tb = New-UTUiText ([string]$text) -Cor $cor -Peso $peso -Margem '0,4,0,4'
        if ($col -gt 0) { $tb.HorizontalAlignment = 'Right' }
        [System.Windows.Controls.Grid]::SetRow($tb, $row); [System.Windows.Controls.Grid]::SetColumn($tb, $col)
        [void]$grid.Children.Add($tb)
    }
    [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    & $cell 'Métrica' 0 0 'MutedBrush' 'SemiBold'; & $cell 'A' 0 1 'MutedBrush' 'SemiBold'; & $cell 'B' 0 2 'MutedBrush' 'SemiBold'; & $cell 'B vs A' 0 3 'MutedBrush' 'SemiBold'
    $row = 1
    foreach ($c in Compare-UTBenchmarkRun -A $a -B $z) {
        [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        & $cell $c.Metrica $row 0
        & $cell (Format-UTOverlayNumber $c.A $c.Casas) $row 1
        & $cell (Format-UTOverlayNumber $c.B $c.Casas) $row 2
        $pct = $(if ($null -eq $c.DiferencaPct) { '-' } else { ('{0}{1} %' -f $(if ($c.DiferencaPct -gt 0) { '+' } else { '' }), (Format-UTOverlayNumber $c.DiferencaPct 1)) })
        & $cell $pct $row 3 $(switch ($c.Melhor) { 'B' { 'GreenBrush' } 'A' { 'RedBrush' } default { 'MutedBrush' } }) 'SemiBold'
        $row++
    }
    $grid.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and [System.Windows.Controls.Grid]::GetRow($_) -eq 0 } | ForEach-Object { $_.TextTrimming = 'CharacterEllipsis' }
    $chart = New-UTUiFrametimeChart -Series @(
        [pscustomobject]@{ Frametimes = [double[]]@($a.Frametimes); Cor = 'MutedBrush'; Nome = "A: $($a.Nome)" }
        [pscustomobject]@{ Frametimes = [double[]]@($z.Frametimes); Cor = 'AccentBrush'; Nome = "B: $($z.Nome)" }
    )
    $names = New-UTUiText ("A: {0} ({1})
B: {2} ({3})" -f $a.Nome, ([datetime]$a.Inicio).ToString('dd/MM HH:mm'), $z.Nome, ([datetime]$z.Inicio).ToString('dd/MM HH:mm')) -Cor MutedBrush -Quebrar
    $b.Detalhe.Content = New-UTUiGroup -Titulo 'Comparação (B é a gravação mais nova)' -RecuoSeparador 16 -Linhas @((New-UTUiRowBox $names), (New-UTUiRowBox $grid), (New-UTUiRowBox $chart)) -Rodape 'Verde: B melhor que A; vermelho: pior. Diferenças menores que 1% contam como empate (variação normal entre gravações).'
}
