# Dialogs of the interface: messages, confirmations (including high risk), checklists, the
# end-of-run summary and the 15-second "keep this refresh rate?" countdown. With the main window
# open they are sheets inside it; before it opens, dialog windows.

function New-UTUiDialogWindow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Titulo, [double]$Largura = 520)
    $ui = Get-UTUi
    $w = New-Object System.Windows.Window
    $w.Title = $Titulo
    $w.Width = $Largura
    $w.SizeToContent = 'Height'
    $w.MaxHeight = 760
    $w.ResizeMode = 'NoResize'
    $w.ShowInTaskbar = $false
    $w.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'
    $w.FontSize = 13
    $w.UseLayoutRounding = $true
    if ($ui -and $ui.Window) {
        $w.Resources.MergedDictionaries.Add($ui.Window.Resources)
        if ($ui.Window.IsVisible) { $w.Owner = $ui.Window; $w.WindowStartupLocation = 'CenterOwner' } else { $w.WindowStartupLocation = 'CenterScreen' }
    } else {
        $w.WindowStartupLocation = 'CenterScreen'
    }
    $w.Background = Get-UTUiBrush 'BgBrush'
    return $w
}

function Get-UTUiDialogIcon {
    param([string]$Tipo)
    switch ($Tipo) {
        'aviso' { @{ Glifo = 'E7BA'; Cor = 'YellowBrush' } }
        'erro' { @{ Glifo = 'EA39'; Cor = 'RedBrush' } }
        'sucesso' { @{ Glifo = 'E930'; Cor = 'GreenBrush' } }
        'pergunta' { @{ Glifo = 'E9CE'; Cor = 'AccentLightBrush' } }
        default { @{ Glifo = 'E946'; Cor = 'AccentLightBrush' } }
    }
}

function Show-UTUiDialog {
    <#
    .SYNOPSIS
        Message of the interface: a sheet inside the main window when it is open, otherwise a
        dialog window. Returns the text of the button clicked ($null if closed).
        -TextoConfirmacao: the first button only enables after the user types that text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Mensagem,
        [string[]]$Botoes = @('OK'),
        [ValidateSet('info', 'aviso', 'erro', 'sucesso', 'pergunta')][string]$Tipo = 'info',
        [string[]]$Itens,
        [string]$TextoConfirmacao,
        [double]$Largura = 540
    )
    $null = $Largura
    return (Show-UTUiSheet -Titulo $Titulo -Mensagem $Mensagem -Botoes $Botoes -Tipo $Tipo -Itens $Itens -TextoConfirmacao $TextoConfirmacao)
}

function Show-UTUiDialogWindow {
    <#
    .SYNOPSIS
        Message box in its own window (used before the main window opens). Returns the text of the button clicked ($null if closed).
        -TextoConfirmacao: the first button only enables after the user types that text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Mensagem,
        [string[]]$Botoes = @('OK'),
        [ValidateSet('info', 'aviso', 'erro', 'sucesso', 'pergunta')][string]$Tipo = 'info',
        [string[]]$Itens,
        [string]$TextoConfirmacao,
        [double]$Largura = 540
    )
    $w = New-UTUiDialogWindow -Titulo $Titulo -Largura $Largura
    $root = New-UTUiStack -Margem '24,20,24,18'
    $icon = Get-UTUiDialogIcon $Tipo
    $head = New-UTUiStack -Horizontal -Itens @((New-UTUiIcon -Glifo $icon.Glifo -Tamanho 22 -Cor $icon.Cor -Margem '0,0,12,0'), (New-UTUiText $Titulo -Tamanho 17 -Peso SemiBold))
    [void]$root.Children.Add($head)
    if ($Mensagem) { [void]$root.Children.Add((New-UTUiText $Mensagem -Quebrar -Margem '0,12,0,0')) }
    if ($Itens) {
        $list = New-UTUiStack
        foreach ($i in $Itens) { [void]$list.Children.Add((New-UTUiText ("•  " + $i) -Quebrar -Cor MutedBrush -Margem '0,2,0,2')) }
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.MaxHeight = 360
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Margin = '0,10,0,0'
        $scroll.Content = $list
        [void]$root.Children.Add($scroll)
    }
    $box = $null
    if ($TextoConfirmacao) {
        [void]$root.Children.Add((New-UTUiText "Para continuar, digite $TextoConfirmacao" -Peso SemiBold -Margem '0,14,0,6'))
        $box = New-Object System.Windows.Controls.TextBox
        $box.Tag = $TextoConfirmacao
        [void]$root.Children.Add($box)
    }
    $buttons = New-UTUiStack -Horizontal -Margem '0,18,0,0'
    $buttons.HorizontalAlignment = 'Right'
    $first = $null
    for ($i = 0; $i -lt $Botoes.Count; $i++) {
        $style = $(if ($i -eq 0) { 'Primario' } else { 'Normal' })
        $b = New-UTUiButton $Botoes[$i] -Estilo $style -Margem '8,0,0,0' -Dados @{ Janela = $w; Valor = $Botoes[$i] } -AoClicar {
            param($btn, $d)
            $null = $btn
            $d.Janela.Tag = $d.Valor
            $d.Janela.Close()
        }
        if ($i -eq 0) { $first = $b }
        [void]$buttons.Children.Add($b)
    }
    if ($box -and $first) {
        $first.IsEnabled = $false
        # Tag is the hint of the text box template; the state goes in DataContext.
        $box.DataContext = @{ Texto = $TextoConfirmacao; Botao = $first }
        $box.Add_TextChanged({ param($tb, $evt) $null = $evt; $tb.DataContext.Botao.IsEnabled = ($tb.Text.Trim() -ceq $tb.DataContext.Texto) })
    }
    [void]$root.Children.Add($buttons)
    $w.Content = $root
    [void]$w.ShowDialog()
    return $w.Tag
}

function Show-UTUiError {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Mensagem)
    Write-UTLog -Level Erro -Message $Mensagem
    $ui = Get-UTUi
    if ($ui -and $ui.Window -and $ui.Window.IsVisible) { [void](Show-UTUiDialog -Titulo 'Algo deu errado' -Mensagem $Mensagem -Tipo erro) }
}

function Show-UTUiChecklistDialog {
    <#
    .SYNOPSIS
        List with checkboxes. -Itens: objects with Id, Texto, Detalhe, Marcado, Habilitado.
        Returns the ids left checked, or $null when cancelled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [string]$Mensagem,
        [Parameter(Mandatory)][object[]]$Itens,
        [string]$BotaoOk = 'Continuar',
        [double]$Largura = 640
    )
    if (Test-UTUiSheetAvailable) {
        $list = New-UTUiStack
        $checks = New-Object System.Collections.Generic.List[object]
        foreach ($i in $Itens) {
            $sw = New-UTUiSwitch -Marcado ([bool]$i.Marcado) -Dica ([string]$i.Texto)
            if ($i.PSObject.Properties['Habilitado'] -and -not $i.Habilitado) { $sw.IsEnabled = $false; $sw.IsChecked = $false }
            $sw.DataContext = [string]$i.Id
            $detail = $(if ($i.PSObject.Properties['Detalhe']) { [string]$i.Detalhe } else { '' })
            [void]$list.Children.Add((New-UTUiRow -Titulo ([string]$i.Texto) -Subtitulo $detail -Direita $sw))
            $checks.Add($sw)
        }
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.MaxHeight = 380
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $list
        $links = New-UTUiStack -Horizontal -Margem '0,8,0,0' -Itens @(
            (New-UTUiButton 'Ligar todos' -Estilo Link -Margem '0,0,16,0' -Dados $checks -AoClicar { param($b, $d) $null = $b; foreach ($c in $d) { if ($c.IsEnabled) { $c.IsChecked = $true } } })
            (New-UTUiButton 'Desligar todos' -Estilo Link -Dados $checks -AoClicar { param($b, $d) $null = $b; foreach ($c in $d) { $c.IsChecked = $false } })
        )
        $content = New-UTUiStack -Itens @($scroll, $links)
        $answer = Show-UTUiSheet -Titulo $Titulo -Mensagem $Mensagem -Botoes @($BotaoOk, 'Cancelar') -Tipo pergunta -Conteudo $content
        if ($answer -ne $BotaoOk) { return $null }
        return , @($checks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.DataContext })
    }
    $w = New-UTUiDialogWindow -Titulo $Titulo -Largura $Largura
    $root = New-UTUiStack -Margem '24,20,24,18'
    [void]$root.Children.Add((New-UTUiText $Titulo -Tamanho 17 -Peso SemiBold))
    if ($Mensagem) { [void]$root.Children.Add((New-UTUiText $Mensagem -Quebrar -Cor MutedBrush -Margem '0,8,0,8')) }
    $list = New-UTUiStack
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($i in $Itens) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $label = New-UTUiStack -Itens @((New-UTUiText ([string]$i.Texto) -Quebrar))
        if ($i.PSObject.Properties['Detalhe'] -and $i.Detalhe) { [void]$label.Children.Add((New-UTUiText ([string]$i.Detalhe) -Tamanho 11.5 -Cor MutedBrush -Quebrar)) }
        $cb.Content = $label
        $cb.IsChecked = [bool]$i.Marcado
        if ($i.PSObject.Properties['Habilitado'] -and -not $i.Habilitado) { $cb.IsEnabled = $false; $cb.IsChecked = $false }
        $cb.Margin = '0,4,0,4'
        $cb.Tag = [string]$i.Id
        [void]$list.Children.Add($cb)
        $checks.Add($cb)
    }
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.MaxHeight = 440
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.Content = $list
    [void]$root.Children.Add($scroll)
    $buttons = New-UTUiStack -Horizontal -Margem '0,16,0,0'
    $buttons.HorizontalAlignment = 'Right'
    $state = @{ Janela = $w; Checks = $checks }
    [void]$buttons.Children.Add((New-UTUiButton 'Marcar todos' -Estilo Normal -Margem '0,0,8,0' -Dados $state -AoClicar { param($b, $d) $null = $b; foreach ($c in $d.Checks) { if ($c.IsEnabled) { $c.IsChecked = $true } } }))
    [void]$buttons.Children.Add((New-UTUiButton 'Desmarcar todos' -Estilo Normal -Margem '0,0,24,0' -Dados $state -AoClicar { param($b, $d) $null = $b; foreach ($c in $d.Checks) { $c.IsChecked = $false } }))
    [void]$buttons.Children.Add((New-UTUiButton 'Cancelar' -Margem '0,0,8,0' -Dados $state -AoClicar { param($b, $d) $null = $b; $d.Janela.Tag = $null; $d.Janela.Close() }))
    [void]$buttons.Children.Add((New-UTUiButton $BotaoOk -Estilo Primario -Margem '0' -Dados $state -AoClicar {
                param($b, $d)
                $null = $b
                $d.Janela.Tag = @($d.Checks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
                $d.Janela.Close()
            }))
    [void]$root.Children.Add($buttons)
    $w.Content = $root
    [void]$w.ShowDialog()
    if ($null -eq $w.Tag) { return $null }
    return , @($w.Tag)
}

function Show-UTUiCountdownDialog {
    <#
    .SYNOPSIS
        "Keep this?" dialog that answers No by itself after -Segundos (used after changing the
        monitor refresh rate: if the screen went black the user cannot click anything).
        Returns $true only when the user clicks to keep.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][string]$Mensagem,
        [int]$Segundos = 15
    )
    if (Test-UTUiSheetAvailable) {
        $count = New-UTUiText "Voltando sozinho em $Segundos segundos..." -Cor YellowBrush
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Tag = @{ Restante = $Segundos; Texto = $count }
        $timer.Add_Tick({
                param($t, $evt)
                $null = $evt
                $s = $t.Tag
                $s.Restante--
                if ($s.Restante -le 0) {
                    $t.Stop()
                    $sheet = (Get-UTUi).SheetEstado
                    if ($sheet) { $sheet.Resultado = $null; $sheet.Frame.Continue = $false }
                    return
                }
                $s.Texto.Text = "Voltando sozinho em $($s.Restante) segundos..."
            })
        $timer.Start()
        try {
            $answer = Show-UTUiSheet -Titulo $Titulo -Mensagem $Mensagem -Botoes @('Manter', 'Voltar como estava') -Tipo pergunta -Conteudo $count
        } finally { $timer.Stop() }
        return ($answer -eq 'Manter')
    }
    $w = New-UTUiDialogWindow -Titulo $Titulo -Largura 500
    $root = New-UTUiStack -Margem '24,20,24,18'
    [void]$root.Children.Add((New-UTUiText $Titulo -Tamanho 17 -Peso SemiBold))
    [void]$root.Children.Add((New-UTUiText $Mensagem -Quebrar -Margem '0,10,0,0'))
    $count = New-UTUiText '' -Tamanho 13 -Cor YellowBrush -Margem '0,12,0,0'
    [void]$root.Children.Add($count)
    $state = @{ Janela = $w; Restante = $Segundos; Texto = $count; Manter = $false }
    $buttons = New-UTUiStack -Horizontal -Margem '0,16,0,0'
    $buttons.HorizontalAlignment = 'Right'
    [void]$buttons.Children.Add((New-UTUiButton 'Manter' -Estilo Primario -Margem '0,0,8,0' -Dados $state -AoClicar { param($b, $d) $null = $b; $d.Manter = $true; $d.Janela.Close() }))
    [void]$buttons.Children.Add((New-UTUiButton 'Voltar como estava' -Margem '0' -Dados $state -AoClicar { param($b, $d) $null = $b; $d.Manter = $false; $d.Janela.Close() }))
    [void]$root.Children.Add($buttons)
    $w.Content = $root
    $count.Text = "Voltando sozinho em $Segundos segundos..."
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Tag = $state
    $timer.Add_Tick({
            param($t, $evt)
            $null = $evt
            $s = $t.Tag
            $s.Restante--
            if ($s.Restante -le 0) { $t.Stop(); $s.Janela.Close(); return }
            $s.Texto.Text = "Voltando sozinho em $($s.Restante) segundos..."
        })
    $timer.Start()
    [void]$w.ShowDialog()
    $timer.Stop()
    return [bool]$state.Manter
}

function Restart-UTUiComputer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Reiniciar em 10 segundos')) {
        Write-UTLog -Level Info -Message 'Reiniciando o computador a pedido do usuário.'
        [void](Invoke-UTNative -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList @('/r', '/t', '10', '/c', 'Upgrade Tweaks: reiniciando para concluir os ajustes.'))
    }
}

function Show-UTUiRunSummary {
    <#
    .SYNOPSIS
        End of an apply/undo/simulation: counts, failures with the reason, and the restart
        offer when something needs it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resultados,
        [string]$Titulo = 'Resumo'
    )
    $summary = Get-UTRunSummary -Resultados $Resultados
    $simulated = $summary.Simulados -gt 0
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($r in $Resultados) {
        if ($r.Status -eq 'Simulado') {
            $items.Add("$($r.Nome):")
            foreach ($a in @($r.Acoes)) { $items.Add("     $a") }
        } elseif ($r.Status -in 'Falhou', 'PrecisaConfirmacao', 'Ignorado') {
            $items.Add("$($r.Nome): $($r.Mensagem)")
        }
    }
    $type = $(if ($summary.Falhas.Count -gt 0) { 'aviso' } else { 'sucesso' })
    $first = ($summary.Texto -split "`n")[0]
    $msg = $first
    if ($summary.RequerReinicio -and -not $simulated) { $msg += "`n`nAlgumas alterações só valem depois de reiniciar o computador." }
    $buttons = @('OK')
    if ($summary.RequerReinicio -and -not $simulated) { $buttons = @('Reiniciar agora', 'Depois') }
    $answer = Show-UTUiDialog -Titulo $Titulo -Mensagem $msg -Tipo $type -Botoes $buttons -Itens $items.ToArray() -Largura 620
    if ($answer -eq 'Reiniciar agora') {
        $confirm = Show-UTUiDialog -Titulo 'Reiniciar agora?' -Mensagem 'Salve o que estiver aberto. O computador reinicia em 10 segundos.' -Tipo pergunta -Botoes @('Reiniciar', 'Cancelar')
        if ($confirm -eq 'Reiniciar') { Restart-UTUiComputer -Confirm:$false }
    }
    return $summary
}
