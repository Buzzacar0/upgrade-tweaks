# Small builders for the elements of the pages (text, buttons, cards, badges, tables).
# Event handlers never rely on closures: what a handler needs travels in the element's Tag.

function New-UTUiText {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$Texto = '',
        [double]$Tamanho = 13,
        [string]$Peso = 'Normal',
        [string]$Cor = 'TextBrush',
        [switch]$Quebrar,
        [string]$Margem = '0'
    )
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Texto
    $tb.FontSize = $Tamanho
    $tb.FontWeight = [System.Windows.FontWeights]::$Peso
    # By resource reference: a theme switch recolors the text without rebuilding it.
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Cor)
    $tb.Margin = $Margem
    if ($Quebrar) { $tb.TextWrapping = 'Wrap' }
    return $tb
}

function New-UTUiIcon {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Glifo, [double]$Tamanho = 16, [string]$Cor = 'TextBrush', [string]$Margem = '0')
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = [string][char][Convert]::ToInt32($Glifo, 16)
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets'
    $tb.FontSize = $Tamanho
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Cor)
    $tb.VerticalAlignment = 'Center'
    $tb.Margin = $Margem
    return $tb
}

function New-UTUiStack {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([object[]]$Itens = @(), [switch]$Horizontal, [string]$Margem = '0')
    $sp = New-Object System.Windows.Controls.StackPanel
    if ($Horizontal) { $sp.Orientation = 'Horizontal' }
    $sp.Margin = $Margem
    foreach ($i in @($Itens)) { if ($null -ne $i) { [void]$sp.Children.Add($i) } }
    return $sp
}

function New-UTUiWrap {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([object[]]$Itens = @(), [string]$Margem = '0')
    $wp = New-Object System.Windows.Controls.WrapPanel
    $wp.Margin = $Margem
    foreach ($i in @($Itens)) { if ($null -ne $i) { [void]$wp.Children.Add($i) } }
    return $wp
}

function New-UTUiButton {
    <#
    .SYNOPSIS
        Button whose click runs -AoClicar with (button, -Dados). Errors become a message box.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Texto,
        [scriptblock]$AoClicar,
        [object]$Dados,
        [ValidateSet('Normal', 'Primario', 'Perigo', 'Link')][string]$Estilo = 'Normal',
        [string]$Dica,
        [string]$Icone,
        [string]$Margem = '0,0,8,8'
    )
    $b = New-Object System.Windows.Controls.Button
    if ($Icone) {
        $b.Content = New-UTUiStack -Horizontal -Itens @((New-UTUiIcon -Glifo $Icone -Tamanho 13 -Margem '0,0,7,0'), (New-UTUiText $Texto))
    } else {
        $b.Content = $Texto
    }
    $ui = Get-UTUi
    if ($Estilo -ne 'Normal' -and $ui -and $ui.Window) {
        $key = @{ Primario = 'PrimaryButton'; Perigo = 'DangerButton'; Link = 'LinkButton' }[$Estilo]
        $style = $ui.Window.TryFindResource($key)
        if ($style) { $b.Style = $style }
    }
    $b.Margin = $Margem
    $b.HorizontalAlignment = 'Left'
    if ($Dica) { $b.ToolTip = $Dica }
    $b.Tag = @{ Acao = $AoClicar; Dados = $Dados }
    $b.Add_Click({
            param($btn, $evt)
            $null = $evt
            $t = $btn.Tag
            if ($null -eq $t -or $null -eq $t.Acao) { return }
            try { & $t.Acao $btn $t.Dados } catch { Show-UTUiError -Mensagem $_.Exception.Message }
        })
    return $b
}

function New-UTUiBadge {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Texto,
        [ValidateSet('verde', 'amarelo', 'vermelho', 'roxo', 'azul', 'cinza')][string]$Cor = 'cinza'
    )
    $map = @{ verde = '#22C55E'; amarelo = '#EAB308'; vermelho = '#EF4444'; roxo = '#A78BFA'; azul = '#38BDF8'; cinza = '#98A1C6' }
    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($map[$Cor])
    $bd = New-Object System.Windows.Controls.Border
    $bd.CornerRadius = 4
    $bd.Padding = '6,1'
    $bd.Margin = '6,0,0,0'
    $bd.VerticalAlignment = 'Center'
    $bd.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40, $color.R, $color.G, $color.B))
    $fg = $color
    $bd.BorderBrush = New-Object System.Windows.Media.SolidColorBrush $fg
    $bd.BorderThickness = 1
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Texto
    $tb.FontSize = 11
    $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush $fg
    $bd.Child = $tb
    return $bd
}

function Get-UTUiRiskBadge {
    param([string]$Risco)
    switch ($Risco) {
        'baixo' { New-UTUiBadge 'Risco baixo' -Cor verde }
        'médio' { New-UTUiBadge 'Risco médio' -Cor amarelo }
        'alto' { New-UTUiBadge 'Risco alto' -Cor vermelho }
        default { New-UTUiBadge $Risco }
    }
}

function New-UTUiCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [string]$Titulo,
        [string]$Subtitulo,
        [string]$Icone,
        [object[]]$Conteudo = @()
    )
    $bd = New-Object System.Windows.Controls.Border
    $ui = Get-UTUi
    $style = $null
    if ($ui -and $ui.Window) { $style = $ui.Window.TryFindResource('Card') }
    if ($style) { $bd.Style = $style } else { $bd.Background = Get-UTUiBrush 'CardBrush'; $bd.Padding = '18,14'; $bd.Margin = '0,0,0,12'; $bd.CornerRadius = 10 }
    $sp = New-Object System.Windows.Controls.StackPanel
    if ($Titulo) {
        $head = New-UTUiStack -Horizontal -Margem '0,0,0,4'
        if ($Icone) { [void]$head.Children.Add((New-UTUiIcon -Glifo $Icone -Tamanho 16 -Cor 'AccentLightBrush' -Margem '0,0,8,0')) }
        [void]$head.Children.Add((New-UTUiText $Titulo -Tamanho 15 -Peso SemiBold))
        [void]$sp.Children.Add($head)
    }
    if ($Subtitulo) { [void]$sp.Children.Add((New-UTUiText $Subtitulo -Cor MutedBrush -Quebrar -Margem '0,0,0,10')) }
    foreach ($c in @($Conteudo)) { if ($null -ne $c) { [void]$sp.Children.Add($c) } }
    $bd.Child = $sp
    return $bd
}

function New-UTUiPageHeader {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Titulo, [string]$Descricao)
    $title = New-UTUiText $Titulo -Tamanho 30 -Peso SemiBold
    $title.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, 'DisplayFont')
    $items = @($title)
    if ($Descricao) { $items += New-UTUiText $Descricao -Cor MutedBrush -Quebrar -Margem '0,6,0,0' }
    return (New-UTUiStack -Itens $items -Margem '0,4,0,24')
}

function New-UTUiTable {
    <#
    .SYNOPSIS
        Read-only table. -Colunas: list of @{ Titulo; Campo; Largura (number or '*') }.
        Built on a Grid: the WPF DataGrid sizes star columns before it knows its width.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Colunas,
        [AllowEmptyCollection()][object[]]$Itens = @(),
        [double]$AlturaMaxima = 0
    )
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($c in $Colunas) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($c.Largura -eq '*' -or -not $c.Largura) { $cd.Width = New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) }
        else { $cd.Width = New-Object System.Windows.GridLength ([double]$c.Largura) }
        [void]$grid.ColumnDefinitions.Add($cd)
    }
    $rows = @($Itens)
    for ($r = 0; $r -le $rows.Count; $r++) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = [System.Windows.GridLength]::Auto
        [void]$grid.RowDefinitions.Add($rd)
        $bg = New-Object System.Windows.Controls.Border
        if ($r -eq 0) { $bg.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'SeparatorBrush'); $bg.BorderThickness = '0,0,0,1' }
        elseif ($r % 2 -eq 0) { $bg.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'NavHoverBrush') }
        [System.Windows.Controls.Grid]::SetRow($bg, $r)
        [System.Windows.Controls.Grid]::SetColumnSpan($bg, $Colunas.Count)
        [void]$grid.Children.Add($bg)
        for ($i = 0; $i -lt $Colunas.Count; $i++) {
            if ($r -eq 0) {
                $tb = New-UTUiText ([string]$Colunas[$i].Titulo) -Peso SemiBold -Cor MutedBrush -Margem '8,6,8,6'
            } else {
                $item = $rows[$r - 1]
                $value = $null
                if ($item -is [System.Collections.IDictionary]) { $value = $item[$Colunas[$i].Campo] }
                elseif ($item.PSObject.Properties[$Colunas[$i].Campo]) { $value = $item.($Colunas[$i].Campo) }
                $tb = New-UTUiText ([string]$value) -Quebrar -Margem '8,5,8,5'
            }
            [System.Windows.Controls.Grid]::SetRow($tb, $r)
            [System.Windows.Controls.Grid]::SetColumn($tb, $i)
            [void]$grid.Children.Add($tb)
        }
    }
    $grid.Margin = '0,4,0,8'
    if ($AlturaMaxima -gt 0) {
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.MaxHeight = $AlturaMaxima
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $grid
        return $scroll
    }
    return $grid
}

function New-UTUiAsyncPanel {
    <#
    .SYNOPSIS
        Placeholder that runs -Script in the background and is replaced by what -Montar builds
        from the result (on the UI thread). -Montar receives (result, -Dados).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][scriptblock]$Script,
        [Parameter(Mandatory)][scriptblock]$Montar,
        [hashtable]$Argumentos = @{},
        [object]$Dados,
        [string]$Carregando = 'Carregando...'
    )
    $holder = New-Object System.Windows.Controls.Border
    $holder.Child = New-UTUiStack -Horizontal -Itens @((New-UTUiIcon -Glifo 'E895' -Tamanho 13 -Cor MutedBrush -Margem '0,0,8,0'), (New-UTUiText $Carregando -Cor MutedBrush)) -Margem '0,4,0,8'
    $state = @{ Holder = $holder; Montar = $Montar; Dados = $Dados; Nome = $Nome; Script = $Script; Argumentos = $Argumentos; Carregando = $Carregando }
    $holder.Tag = $state
    [void](Invoke-UTUiJob -Nome $Nome -Script $Script -Argumentos $Argumentos -Estado $state -AoTerminar {
            param($Resultado, $Estado)
            if (-not $Resultado.Ok) {
                $Estado.Holder.Child = New-UTUiText ("Não foi possível carregar: " + $Resultado.Erro) -Cor YellowBrush -Quebrar -Margem '0,4,0,8'
                return
            }
            $Estado.Holder.Child = & $Estado.Montar $Resultado.Resultado $Estado.Dados
        })
    return $holder
}

function Sync-UTUiAsyncPanel {
    # Runs the job of an async panel again (refresh buttons).
    param([Parameter(Mandatory)][System.Windows.Controls.Border]$Painel)
    $s = $Painel.Tag
    $Painel.Child = New-UTUiText $s.Carregando -Cor MutedBrush -Margem '0,4,0,8'
    [void](Invoke-UTUiJob -Nome $s.Nome -Script $s.Script -Argumentos $s.Argumentos -Estado $s -AoTerminar {
            param($Resultado, $Estado)
            if (-not $Resultado.Ok) { $Estado.Holder.Child = New-UTUiText ("Não foi possível carregar: " + $Resultado.Erro) -Cor YellowBrush -Quebrar; return }
            $Estado.Holder.Child = & $Estado.Montar $Resultado.Resultado $Estado.Dados
        })
}

function Get-UTUiFileDialog {
    <#
    .SYNOPSIS
        Open/save file dialog; returns the chosen path or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('Abrir', 'Salvar')][string]$Modo = 'Abrir',
        [string]$Filtro = 'Todos os arquivos (*.*)|*.*',
        [string]$NomeSugerido
    )
    $dlg = $(if ($Modo -eq 'Abrir') { New-Object Microsoft.Win32.OpenFileDialog } else { New-Object Microsoft.Win32.SaveFileDialog })
    $dlg.Filter = $Filtro
    if ($NomeSugerido) { $dlg.FileName = $NomeSugerido }
    $ui = Get-UTUi
    $ok = $(if ($ui -and $ui.Window) { $dlg.ShowDialog($ui.Window) } else { $dlg.ShowDialog() })
    if ($ok) { return $dlg.FileName }
    return $null
}

function Open-UTUiLink {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Url)
    if ($Url -notmatch '^(https://|ms-settings:|ms-windows-store:)') { throw "Link recusado: $Url" }
    if ($PSCmdlet.ShouldProcess($Url, 'Abrir')) { Start-Process $Url }
}
