# Components of the design system built from code: squircle icons, "inset grouped" lists, rows
# with a switch, the sheet (modal inside the window) and the component gallery (-Galeria).
# Colors always by resource reference, so a theme switch restyles them too.

function Set-UTUiColor {
    # Binds a brush property to a theme token (DynamicResource from code).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Styles a UI element; nothing changes on the system.')]
    param([Parameter(Mandatory)][System.Windows.FrameworkElement]$Elemento, [Parameter(Mandatory)][System.Windows.DependencyProperty]$Propriedade, [Parameter(Mandatory)][string]$Token)
    $Elemento.SetResourceReference($Propriedade, $Token)
}

function New-UTUiSquircle {
    <#
    .SYNOPSIS
        Rounded square with a white glyph on a category color (the icons of the macOS Settings).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Glifo, [string]$Cor = 'IconBlue', [double]$Tamanho = 24, [string]$Margem = '0,0,10,0')
    $bd = New-Object System.Windows.Controls.Border
    $bd.Width = $Tamanho; $bd.Height = $Tamanho
    $bd.CornerRadius = [math]::Round($Tamanho * 0.26)
    $bd.Margin = $Margem
    $bd.VerticalAlignment = 'Center'
    Set-UTUiColor -Elemento $bd -Propriedade ([System.Windows.Controls.Border]::BackgroundProperty) -Token $Cor
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = [string][char][Convert]::ToInt32($Glifo, 16)
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets'
    $tb.FontSize = [math]::Round($Tamanho * 0.55)
    $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    $bd.Child = $tb
    return $bd
}

function New-UTUiSwitch {
    <#
    .SYNOPSIS
        On/off switch. -AoMudar runs with (switch, -Dados) after each change by the user.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([bool]$Marcado, [scriptblock]$AoMudar, [object]$Dados, [string]$Rotulo = '', [string]$Dica)
    $cb = New-Object System.Windows.Controls.CheckBox
    $ui = Get-UTUi
    $style = $null
    if ($ui -and $ui.Window) { $style = $ui.Window.TryFindResource('Switch') }
    if ($style) { $cb.Style = $style }
    $cb.IsChecked = $Marcado
    $cb.VerticalAlignment = 'Center'
    if ($Rotulo) { $cb.Content = $Rotulo }
    if ($Dica) { $cb.ToolTip = $Dica }
    [System.Windows.Automation.AutomationProperties]::SetName($cb, $(if ($Rotulo) { $Rotulo } elseif ($Dica) { $Dica } else { 'Ligar ou desligar' }))
    $cb.Tag = @{ Acao = $AoMudar; Dados = $Dados }
    $handler = {
        param($s, $e) $null = $e
        $t = $s.Tag
        if ($null -eq $t -or $null -eq $t.Acao) { return }
        try { & $t.Acao $s $t.Dados } catch { Show-UTUiError -Mensagem $_.Exception.Message }
    }
    $cb.Add_Checked($handler)
    $cb.Add_Unchecked($handler)
    return $cb
}

function New-UTUiRow {
    <#
    .SYNOPSIS
        One row of a grouped list: optional squircle icon, title, short gray subtitle, an element on
        the right (switch, value, button) and the "i" button that opens the details.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [string]$Subtitulo,
        [string]$Icone,
        [string]$IconeCor = 'IconBlue',
        [object]$Direita,
        [scriptblock]$AoClicarInfo,
        [object]$Dados,
        [object[]]$Selos = @()
    )
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in 'Auto', '*', 'Auto', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto })
        [void]$grid.ColumnDefinitions.Add($cd)
    }
    if ($Icone) { $sq = New-UTUiSquircle -Glifo $Icone -Cor $IconeCor -Tamanho 28 -Margem '0,0,12,0'; [void]$grid.Children.Add($sq) }
    $texts = New-Object System.Windows.Controls.StackPanel
    $texts.VerticalAlignment = 'Center'
    $head = New-Object System.Windows.Controls.WrapPanel
    $title = New-UTUiText $Titulo -Tamanho 13.5
    $title.TextWrapping = 'Wrap'
    $title.Margin = '0,0,6,0'
    [void]$head.Children.Add($title)
    foreach ($s in @($Selos)) { if ($s) { [void]$head.Children.Add($s) } }
    [void]$texts.Children.Add($head)
    if ($Subtitulo) { [void]$texts.Children.Add((New-UTUiText $Subtitulo -Tamanho 12 -Cor MutedBrush -Quebrar -Margem '0,2,0,0')) }
    [System.Windows.Controls.Grid]::SetColumn($texts, 1)
    [void]$grid.Children.Add($texts)
    if ($Direita) {
        $Direita.Margin = '12,0,0,0'
        $Direita.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($Direita, 2)
        [void]$grid.Children.Add($Direita)
    }
    if ($AoClicarInfo) {
        $info = New-Object System.Windows.Controls.Button
        $ui = Get-UTUi
        if ($ui -and $ui.Window) { $info.Style = $ui.Window.TryFindResource('IconButton') }
        $info.Content = New-UTUiIcon -Glifo 'E946' -Tamanho 14 -Cor 'MutedBrush'
        $info.Margin = '6,0,0,0'
        $info.ToolTip = 'Detalhes'
        [System.Windows.Automation.AutomationProperties]::SetName($info, "Detalhes de $Titulo")
        $info.Tag = @{ Acao = $AoClicarInfo; Dados = $Dados }
        $info.Add_Click({ param($b, $e) $null = $e; try { & $b.Tag.Acao $b $b.Tag.Dados } catch { Show-UTUiError -Mensagem $_.Exception.Message } })
        [System.Windows.Controls.Grid]::SetColumn($info, 3)
        [void]$grid.Children.Add($info)
    }
    $row = New-Object System.Windows.Controls.Border
    $row.Padding = '16,10'
    $row.MinHeight = 48
    $row.Background = [System.Windows.Media.Brushes]::Transparent
    $row.Child = $grid
    return $row
}

function New-UTUiGroup {
    <#
    .SYNOPSIS
        "Inset grouped" block: small gray title above, rounded surface, thin separators that do
        not touch the left edge.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([string]$Titulo, [object[]]$Linhas = @(), [string]$Rodape, [double]$RecuoSeparador = 56)
    $outer = New-Object System.Windows.Controls.StackPanel
    $outer.Margin = '0,0,0,24'
    if ($Titulo) {
        $t = New-UTUiText $Titulo -Tamanho 12 -Peso SemiBold -Cor MutedBrush -Margem '16,0,0,6'
        [void]$outer.Children.Add($t)
    }
    $bd = New-Object System.Windows.Controls.Border
    $ui = Get-UTUi
    $style = $null
    if ($ui -and $ui.Window) { $style = $ui.Window.TryFindResource('Group') }
    if ($style) { $bd.Style = $style } else { $bd.CornerRadius = 12 }
    $list = New-Object System.Windows.Controls.StackPanel
    $first = $true
    foreach ($l in @($Linhas)) {
        if ($null -eq $l) { continue }
        if (-not $first) {
            $sep = New-Object System.Windows.Controls.Border
            $sep.Height = 1
            $sep.Margin = "$RecuoSeparador,0,0,0"
            Set-UTUiColor -Elemento $sep -Propriedade ([System.Windows.Controls.Border]::BackgroundProperty) -Token 'SeparatorBrush'
            [void]$list.Children.Add($sep)
        }
        [void]$list.Children.Add($l)
        $first = $false
    }
    $bd.Child = $list
    [void]$outer.Children.Add($bd)
    if ($Rodape) { [void]$outer.Children.Add((New-UTUiText $Rodape -Tamanho 12 -Cor MutedBrush -Quebrar -Margem '16,6,16,0')) }
    return $outer
}

function New-UTUiScoreRing {
    <#
    .SYNOPSIS
        Progress ring (like the Activity rings of the Apple Watch) with the number in the middle.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([ValidateRange(0, 100)][int]$Nota, [string]$Cor = 'GreenBrush', [double]$Tamanho = 140, [double]$Espessura = 14)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = $Tamanho; $grid.Height = $Tamanho
    $track = New-Object System.Windows.Shapes.Ellipse
    $track.StrokeThickness = $Espessura
    $track.Margin = [System.Windows.Thickness]::new($Espessura / 2)
    $track.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, 'SeparatorBrush')
    [void]$grid.Children.Add($track)
    if ($Nota -ge 100) {
        $arc = New-Object System.Windows.Shapes.Ellipse
        $arc.Margin = [System.Windows.Thickness]::new($Espessura / 2)
    } else {
        $r = ($Tamanho - $Espessura) / 2
        $c = $Tamanho / 2
        $angle = 360.0 * [math]::Max($Nota, 0.5) / 100
        $rad = ($angle - 90) * [math]::PI / 180
        $ci = [Globalization.CultureInfo]::InvariantCulture
        $data = [string]::Format($ci, 'M {0},{1} A {2},{2} 0 {3} 1 {4},{5}', $c, ($c - $r), $r, $(if ($angle -gt 180) { 1 } else { 0 }), ($c + $r * [math]::Cos($rad)), ($c + $r * [math]::Sin($rad)))
        $arc = New-Object System.Windows.Shapes.Path
        $arc.Data = [System.Windows.Media.Geometry]::Parse($data)
        $arc.StrokeStartLineCap = 'Round'
        $arc.StrokeEndLineCap = 'Round'
    }
    $arc.StrokeThickness = $Espessura
    $arc.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, $Cor)
    [void]$grid.Children.Add($arc)
    $number = New-UTUiText ([string]$Nota) -Tamanho ([math]::Round($Tamanho * 0.27)) -Peso SemiBold
    $number.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, 'DisplayFont')
    $number.HorizontalAlignment = 'Center'
    $of = New-UTUiText 'de 100' -Tamanho 12 -Cor MutedBrush
    $of.HorizontalAlignment = 'Center'
    $center = New-UTUiStack -Itens @($number, $of)
    $center.HorizontalAlignment = 'Center'; $center.VerticalAlignment = 'Center'
    [void]$grid.Children.Add($center)
    [System.Windows.Automation.AutomationProperties]::SetName($grid, "Nota de Otimização: $Nota de 100")
    return $grid
}

#region Sheet
function Show-UTUiSheet {
    <#
    .SYNOPSIS
        Modal sheet inside the main window (dims the rest, slides in). Returns the text of the
        button clicked, or $null (Esc). The first button is the primary one; with
        -TextoConfirmacao it only enables after the exact text is typed. Without a visible main
        window it falls back to a dialog window.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [AllowEmptyString()][string]$Mensagem = '',
        [string[]]$Botoes = @('OK'),
        [ValidateSet('info', 'aviso', 'erro', 'sucesso', 'pergunta')][string]$Tipo = 'info',
        [string[]]$Itens,
        [string]$TextoConfirmacao,
        [object]$Conteudo
    )
    $ui = Get-UTUi
    if (-not (Test-UTUiSheetAvailable)) {
        return (Show-UTUiDialogWindow -Titulo $Titulo -Mensagem $Mensagem -Botoes $Botoes -Tipo $Tipo -Itens $Itens -TextoConfirmacao $TextoConfirmacao)
    }
    $state = @{ Resultado = $null; Frame = (New-Object System.Windows.Threading.DispatcherFrame) }
    $root = New-UTUiStack
    $icon = Get-UTUiDialogIcon $Tipo
    $head = New-UTUiStack -Horizontal -Itens @((New-UTUiIcon -Glifo $icon.Glifo -Tamanho 22 -Cor $icon.Cor -Margem '0,0,12,0'), (New-UTUiText $Titulo -Tamanho 17 -Peso SemiBold -Quebrar))
    [void]$root.Children.Add($head)
    if ($Mensagem) { [void]$root.Children.Add((New-UTUiText $Mensagem -Quebrar -Cor MutedBrush -Margem '0,12,0,0')) }
    if ($Itens) {
        $list = New-UTUiStack
        foreach ($i in $Itens) {
            # Indented lines are details of the item above (e.g. what changes in the registry).
            if ($i -match '^\s{2,}') { [void]$list.Children.Add((New-UTUiText $i.Trim() -Quebrar -Tamanho 12 -Cor MutedBrush -Margem '16,0,0,2')) }
            else { [void]$list.Children.Add((New-UTUiText ("•  " + $i) -Quebrar -Margem '0,4,0,2')) }
        }
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.MaxHeight = 320
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Margin = '0,12,0,0'
        $scroll.Content = $list
        [void]$root.Children.Add($scroll)
    }
    if ($Conteudo) { $Conteudo.Margin = '0,12,0,0'; [void]$root.Children.Add($Conteudo) }
    $box = $null
    if ($TextoConfirmacao) {
        [void]$root.Children.Add((New-UTUiText "Para continuar, digite $TextoConfirmacao" -Peso SemiBold -Margem '0,16,0,6'))
        $box = New-Object System.Windows.Controls.TextBox
        $box.Tag = $TextoConfirmacao
        [void]$root.Children.Add($box)
    }
    $buttons = New-UTUiStack -Horizontal -Margem '0,22,0,0'
    $buttons.HorizontalAlignment = 'Right'
    $first = $null
    # The primary action is the rightmost one, as on Windows and macOS.
    for ($i = $Botoes.Count - 1; $i -ge 0; $i--) {
        $style = $(if ($i -eq 0) { 'Primario' } else { 'Normal' })
        $b = New-UTUiButton $Botoes[$i] -Estilo $style -Margem '8,0,0,0' -Dados @{ Estado = $state; Valor = $Botoes[$i] } -AoClicar {
            param($btn, $d) $null = $btn
            $d.Estado.Resultado = $d.Valor
            $d.Estado.Frame.Continue = $false
        }
        if ($i -eq 0) { $first = $b; $b.IsDefault = $true }
        [void]$buttons.Children.Add($b)
    }
    if ($box -and $first) {
        $first.IsEnabled = $false
        $box.DataContext = @{ Texto = $TextoConfirmacao; Botao = $first }
        $box.Add_TextChanged({ param($tb, $evt) $null = $evt; $tb.DataContext.Botao.IsEnabled = ($tb.Text.Trim() -ceq $tb.DataContext.Texto) })
    }
    [void]$root.Children.Add($buttons)

    $ui.SheetEstado = $state
    $ui.C['SheetContent'].Content = $root
    $sheetHost = $ui.C['SheetHost']
    $sheetHost.Visibility = 'Visible'
    if (Test-UTUiMotion) {
        $time = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(180))
        $ease = New-Object System.Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation (0.0, 1.0, $time); $fade.EasingFunction = $ease
        $slide = New-Object System.Windows.Media.Animation.DoubleAnimation (16.0, 0.0, $time); $slide.EasingFunction = $ease
        $sheetHost.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
        $ui.C['SheetShift'].BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slide)
    }
    if ($box) { [void]$box.Focus() } elseif ($first) { [void]$first.Focus() }
    try {
        [System.Windows.Threading.Dispatcher]::PushFrame($state.Frame)
    } finally {
        $sheetHost.Visibility = 'Collapsed'
        $ui.C['SheetContent'].Content = $null
        $ui.SheetEstado = $null
    }
    return $state.Resultado
}

function Test-UTUiSheetAvailable {
    # A sheet needs the main window on screen and no other sheet open (otherwise: dialog window).
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $ui = Get-UTUi
    if ($null -eq $ui -or $null -eq $ui.Window -or -not $ui.Window.IsVisible -or -not $ui.C.ContainsKey('SheetHost')) { return $false }
    return -not ($ui.ContainsKey('SheetEstado') -and $null -ne $ui.SheetEstado)
}

function Initialize-UTUiSheet {
    <#
    .SYNOPSIS
        Esc closes the open sheet (as "cancel"); Tab stays inside it.
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    if (-not $ui.C.ContainsKey('SheetHost')) { return }
    [System.Windows.Input.KeyboardNavigation]::SetTabNavigation($ui.C['SheetHost'], 'Cycle')
    $ui.C['SheetHost'].Add_PreviewKeyDown({
            param($s, $e) $null = $s
            if ($e.Key -ne 'Escape') { return }
            $st = (Get-UTUi).SheetEstado
            if ($st) { $st.Resultado = $null; $st.Frame.Continue = $false; $e.Handled = $true }
        })
}
#endregion

#region Component gallery (-Galeria)
function New-UTUiPageGaleria {
    <#
    .SYNOPSIS
        Hidden page with every component of the design system, to review the look (start with
        -Galeria or press Ctrl+Shift+G).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'Galeria de componentes' -Descricao 'Todos os componentes do design system, nos dois temas. Página interna para revisão visual.'))

    $type = New-UTUiStack -Itens @(
        (New-UTUiText 'Título grande (30)' -Tamanho 30 -Peso SemiBold)
        (New-UTUiText 'Título de seção (17)' -Tamanho 17 -Peso SemiBold -Margem '0,6,0,0')
        (New-UTUiText 'Corpo (13,5): texto principal, linguagem simples.' -Tamanho 13.5 -Margem '0,6,0,0')
        (New-UTUiText 'Legenda (11,5): detalhes e jargão ficam aqui.' -Tamanho 11.5 -Cor MutedBrush -Margem '0,4,0,0')
    )
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Tipografia' -Linhas @((New-UTUiRowBox $type))))

    $swatches = New-UTUiWrap
    foreach ($k in 'AccentBrush', 'AccentLightBrush', 'AccentSoftBrush', 'TextBrush', 'MutedBrush', 'TertiaryBrush', 'CardBrush', 'BgBrush', 'SeparatorBrush', 'GreenBrush', 'YellowBrush', 'RedBrush', 'BlueBrush') {
        $sw = New-Object System.Windows.Controls.Border
        $sw.Width = 44; $sw.Height = 44; $sw.CornerRadius = 10; $sw.BorderThickness = 1
        Set-UTUiColor -Elemento $sw -Propriedade ([System.Windows.Controls.Border]::BackgroundProperty) -Token $k
        Set-UTUiColor -Elemento $sw -Propriedade ([System.Windows.Controls.Border]::BorderBrushProperty) -Token 'SeparatorBrush'
        [void]$swatches.Children.Add((New-UTUiStack -Margem '0,0,14,10' -Itens @($sw, (New-UTUiText ($k -replace 'Brush$', '') -Tamanho 11 -Cor MutedBrush -Margem '0,4,0,0'))))
    }
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Cores (tokens)' -Linhas @((New-UTUiRowBox $swatches))))

    $buttons = New-UTUiWrap -Itens @(
        (New-UTUiButton 'Primário' -Estilo Primario)
        (New-UTUiButton 'Secundário')
        (New-UTUiButton 'Com ícone' -Icone 'E72C')
        (New-UTUiButton 'Destrutivo' -Estilo Perigo)
        (New-UTUiButton 'Link' -Estilo Link)
    )
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Botões' -Linhas @((New-UTUiRowBox $buttons))))

    $combo = New-Object System.Windows.Controls.ComboBox
    $combo.Width = 200
    foreach ($o in 'Opção um', 'Opção dois', 'Opção três') { [void]$combo.Items.Add($o) }
    $combo.SelectedIndex = 0
    $text = New-Object System.Windows.Controls.TextBox; $text.Width = 220; $text.Tag = 'Campo de texto'
    $search = New-Object System.Windows.Controls.TextBox; $search.Width = 220; $search.Tag = 'Buscar'
    $sstyle = (Get-UTUi).Window.TryFindResource('SearchBox'); if ($sstyle) { $search.Style = $sstyle }
    $check = New-Object System.Windows.Controls.CheckBox; $check.Content = 'Caixa de seleção'; $check.IsChecked = $true
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Controles' -Linhas @(
                (New-UTUiRow -Titulo 'Switch ligado' -Subtitulo 'Liga e desliga com animação de 150 ms.' -Icone 'E945' -IconeCor 'IconOrange' -Direita (New-UTUiSwitch -Marcado $true -Dica 'Exemplo'))
                (New-UTUiRow -Titulo 'Switch desligado' -Subtitulo 'Subtítulo curto em cinza.' -Icone 'E7FC' -IconeCor 'IconGreen' -Direita (New-UTUiSwitch -Marcado $false -Dica 'Exemplo') -AoClicarInfo { param($b, $d) $null = $b, $d; [void](Show-UTUiSheet -Titulo 'Detalhes' -Mensagem 'Descrição completa, risco, ganho esperado e o que muda no registro aparecem aqui.' -Tipo info) })
                (New-UTUiRow -Titulo 'Lista suspensa' -Icone 'E713' -IconeCor 'IconGray' -Direita $combo)
                (New-UTUiRow -Titulo 'Campo de texto' -Icone 'E70F' -IconeCor 'IconBlue' -Direita $text)
                (New-UTUiRow -Titulo 'Busca' -Icone 'E721' -IconeCor 'IconIndigo' -Direita $search)
                (New-UTUiRow -Titulo 'Caixa de seleção' -Icone 'E73E' -IconeCor 'IconTeal' -Direita $check)
            )))

    $badges = New-UTUiWrap -Itens @((Get-UTUiRiskBadge 'baixo'), (Get-UTUiRiskBadge 'médio'), (Get-UTUiRiskBadge 'alto'), (New-UTUiBadge 'Reinício' -Cor azul), (New-UTUiBadge 'Controverso' -Cor roxo))
    $status = New-UTUiStack -Itens @(
        (New-UTUiStatusLine -Status 'OK' -Titulo 'Tudo certo' -Texto 'Estado positivo.')
        (New-UTUiStatusLine -Status 'Aviso' -Titulo 'Atenção' -Texto 'Algo pede cuidado.')
        (New-UTUiStatusLine -Status 'Problema' -Titulo 'Problema' -Texto 'Algo precisa de ação.')
    )
    $bar = New-Object System.Windows.Controls.ProgressBar; $bar.IsIndeterminate = $true; $bar.Width = 240
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Selos, estados e progresso' -Linhas @((New-UTUiRowBox $badges), (New-UTUiRowBox $status), (New-UTUiRowBox $bar))))

    $card = New-UTUiCard -Titulo 'Card (widget)' -Icone 'E9D9' -Subtitulo 'Valor grande, rótulo pequeno.' -Conteudo @((New-UTUiText '47 °C' -Tamanho 34 -Peso SemiBold))
    [void]$page.Children.Add($card)

    $sheets = New-UTUiWrap -Itens @(
        (New-UTUiButton 'Sheet de informação' -AoClicar { param($b, $d) $null = $b, $d; [void](Show-UTUiSheet -Titulo 'Informação' -Mensagem 'Um sheet aparece sobre a janela, escurece o resto e fecha com Esc.' -Tipo info) })
        (New-UTUiButton 'Sheet de confirmação' -AoClicar { param($b, $d) $null = $b, $d; $r = Show-UTUiSheet -Titulo 'Aplicar 3 ajustes?' -Mensagem 'O que vai mudar:' -Itens @('Modo de Jogo: desligado -> ligado', 'Game DVR: ligado -> desligado') -Botoes @('Aplicar', 'Cancelar') -Tipo pergunta; Show-UTUiStatus "Escolha: $r" })
        (New-UTUiButton 'Sheet de risco alto' -Estilo Perigo -AoClicar { param($b, $d) $null = $b, $d; [void](Show-UTUiSheet -Titulo 'Risco alto' -Mensagem 'Confirmações de risco alto pedem para digitar um texto.' -Botoes @('Continuar', 'Cancelar') -Tipo aviso -TextoConfirmacao 'EU ENTENDO') })
    )
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Sheets' -Linhas @((New-UTUiRowBox $sheets))))

    $themes = New-UTUiWrap
    foreach ($t in @(@('sistema', 'Igual ao Windows'), @('claro', 'Claro'), @('escuro', 'Escuro'))) {
        [void]$themes.Children.Add((New-UTUiButton $t[1] -Dados $t[0] -AoClicar { param($b, $d) $null = $b; Switch-UTUiTheme -Tema $d }))
    }
    $accents = New-UTUiWrap
    foreach ($hex in '#7C3AED', '#0A84FF', '#30D158', '#FF9F0A', '#FF375F', '#5E5CE6', '#8E8E93') {
        $dot = New-Object System.Windows.Controls.Button
        $dot.Width = 26; $dot.Height = 26; $dot.Margin = '0,0,10,0'; $dot.Cursor = 'Hand'; $dot.ToolTip = $hex
        $dot.Template = [Windows.Markup.XamlReader]::Parse("<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'><Ellipse Fill='$hex' Stroke='#33000000' StrokeThickness='1'/></ControlTemplate>")
        $dot.Tag = $hex
        $dot.Add_Click({ param($b, $e) $null = $e; Set-UTUiAccent -Hex ([string]$b.Tag) })
        [void]$accents.Children.Add($dot)
    }
    [void]$page.Children.Add((New-UTUiGroup -Titulo 'Aparência' -Linhas @(
                (New-UTUiRow -Titulo 'Tema' -Subtitulo 'Igual ao Windows, claro ou escuro.' -Icone 'E793' -IconeCor 'IconIndigo' -Direita $themes)
                (New-UTUiRow -Titulo 'Cor de destaque' -Subtitulo 'Padrão: roxo da Upgrade Store.' -Icone 'E790' -IconeCor 'IconPink' -Direita $accents)
                (New-UTUiRow -Titulo 'Fundo' -Subtitulo $(if ((Get-UTUiBackdropKind) -eq 'nenhum') { 'Windows 10: fundo sólido.' } else { 'Windows 11: Mica atrás da barra lateral.' }) -Icone 'E7F4' -IconeCor 'IconTeal')
            )))
    return $page
}

function New-UTUiRowBox {
    # A free-form block inside a grouped list (same padding as a row).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    param([Parameter(Mandatory)][System.Windows.UIElement]$Conteudo)
    $bd = New-Object System.Windows.Controls.Border
    $bd.Padding = '16,12'
    $bd.Child = $Conteudo
    return $bd
}

function Set-UTUiAccent {
    <#
    .SYNOPSIS
        New accent color, saved for the next sessions; pages are rebuilt with it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the look of the interface.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^#[0-9A-Fa-f]{6}$')][string]$Hex)
    $ui = Get-UTUi
    $pref = Get-UTUiPreference
    [void](Set-UTUiTheme -Janela $ui.Window -Tema ([string]$pref.Tema) -Destaque $Hex)
    Save-UTUiPreference -Valores @{ Destaque = $Hex } -Confirm:$false
    $current = $ui.PaginaAtual
    foreach ($k in @($ui.Pages.Keys)) { [void]$ui.Pages.Remove($k); Remove-UTUiPageRow -Pagina $k }
    if ($current) { Show-UTUiPage -Id $current }
}
#endregion
