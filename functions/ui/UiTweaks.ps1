# Tweak lists of the tabs: one row per tweak (checkbox, name, badges, current state, tooltip),
# the shared selection, and the apply / undo / simulate flow with its confirmations.

function Get-UTUiTabDefinition {
    <#
    .SYNOPSIS
        Side tabs in order. Categorias = tweak categories listed in the tab.
    #>
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Id = 'Inicio'; Nome = 'Início'; Icone = 'E80F'; Categorias = @() }
        [pscustomobject]@{ Id = 'Energia'; Nome = 'Energia'; Icone = 'E945'; Categorias = @('Energia') }
        [pscustomobject]@{ Id = 'Gaming'; Nome = 'Gaming'; Icone = 'E7FC'; Categorias = @('Gaming') }
        [pscustomobject]@{ Id = 'Latencia'; Nome = 'Latência'; Icone = 'E916'; Categorias = @('Latencia') }
        [pscustomobject]@{ Id = 'Rede'; Nome = 'Rede'; Icone = 'E968'; Categorias = @('Rede') }
        [pscustomobject]@{ Id = 'ServicosApps'; Nome = 'Serviços e Apps'; Icone = 'E71D'; Categorias = @('ServicosApps'); Pagina = 'Servico' }
        [pscustomobject]@{ Id = 'Privacidade'; Nome = 'Privacidade'; Icone = 'EA18'; Categorias = @('Privacidade') }
        [pscustomobject]@{ Id = 'GPU'; Nome = 'GPU'; Icone = 'E7F4'; Categorias = @('GPU') }
        [pscustomobject]@{ Id = 'Warzone'; Nome = 'Warzone'; Icone = 'E7C1'; Categorias = @('Warzone') }
        [pscustomobject]@{ Id = 'Ferramentas'; Nome = 'Ferramentas'; Icone = 'EC7A'; Categorias = @('Ferramentas'); Pagina = 'Ferramenta' }
        [pscustomobject]@{ Id = 'Programas'; Nome = 'Programas'; Icone = 'E896'; Categorias = @(); Pagina = 'Programa' }
        [pscustomobject]@{ Id = 'Personalizar'; Nome = 'Personalizar'; Icone = 'E771'; Categorias = @('Personalizar', 'Visual') }
        [pscustomobject]@{ Id = 'Restaurar'; Nome = 'Restaurar'; Icone = 'E777'; Categorias = @() }
        [pscustomobject]@{ Id = 'Sobre'; Nome = 'Sobre'; Icone = 'E946'; Categorias = @() }
    )
}

function Get-UTUiTabTweak {
    <#
    .SYNOPSIS
        Tweaks shown in a tab: its categories plus tweaks that list the tab in abasExtras.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Aba)
    $tab = @(Get-UTUiTabDefinition | Where-Object Id -eq $Aba)[0]
    if (-not $tab -or @($tab.Categorias).Count -eq 0) { return @() }
    foreach ($t in @(Get-UTTweak)) {
        $extra = @($t.abasExtras | Where-Object { $tab.Categorias -contains $_ })
        if ($tab.Categorias -contains $t.categoria -or $extra.Count -gt 0) { $t }
    }
}

function Get-UTUiStateVisual {
    param([string]$Estado)
    switch ($Estado) {
        'Aplicado' { @{ Texto = 'Aplicado'; Cor = 'GreenBrush' } }
        'NaoAplicado' { @{ Texto = 'Não aplicado'; Cor = 'MutedBrush' } }
        'Parcial' { @{ Texto = 'Parcial'; Cor = 'YellowBrush' } }
        'Incompativel' { @{ Texto = 'Não se aplica'; Cor = 'MutedBrush' } }
        'Desconhecido' { @{ Texto = 'Sem leitura'; Cor = 'YellowBrush' } }
        default { @{ Texto = 'Verificando...'; Cor = 'MutedBrush' } }
    }
}

function Get-UTUiTweakToolTip {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Tweak, [string]$Motivo)
    $sp = New-UTUiStack
    [void]$sp.Children.Add((New-UTUiText ([string]$Tweak.nome) -Peso SemiBold -Quebrar))
    [void]$sp.Children.Add((New-UTUiText ([string]$Tweak.descricao) -Quebrar -Margem '0,6,0,0'))
    if ($Tweak.ganhoEsperado) { [void]$sp.Children.Add((New-UTUiText ("Ganho esperado: " + $Tweak.ganhoEsperado) -Cor AccentLightBrush -Quebrar -Margem '0,6,0,0')) }
    if ($Tweak.observacao) { [void]$sp.Children.Add((New-UTUiText ([string]$Tweak.observacao) -Cor YellowBrush -Quebrar -Margem '0,6,0,0')) }
    if ($Tweak.risco -eq 'alto' -and $Tweak.confirmacao) { [void]$sp.Children.Add((New-UTUiText ([string]$Tweak.confirmacao) -Cor RedBrush -Quebrar -Margem '0,6,0,0')) }
    if ($Motivo) { [void]$sp.Children.Add((New-UTUiText ("Não se aplica: " + $Motivo) -Cor MutedBrush -Quebrar -Margem '0,6,0,0')) }
    return $sp
}

function New-UTUiTweakRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [Parameter(Mandatory)][string]$Pagina
    )
    $ui = Get-UTUi
    $id = [string]$Tweak.id

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in 'Auto', '*', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto })
        [void]$grid.ColumnDefinitions.Add($cd)
    }

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Tag = $id
    $cb.VerticalAlignment = 'Center'
    $cb.Margin = '0,0,12,0'
    $cb.IsChecked = $ui.Selecionados.Contains($id)
    $cb.Add_Click({
            param($box, $evt)
            $null = $evt
            Set-UTUiSelection -Id ([string]$box.Tag) -Marcado ([bool]$box.IsChecked)
        })
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)
    [void]$grid.Children.Add($cb)

    $title = New-UTUiWrap -Itens @((New-UTUiText ([string]$Tweak.nome) -Peso SemiBold))
    [void]$title.Children.Add((Get-UTUiRiskBadge -Risco ([string]$Tweak.risco)))
    if ($Tweak.requerReinicio) { [void]$title.Children.Add((New-UTUiBadge 'Requer reinício' -Cor azul)) }
    if ($Tweak.controverso) { [void]$title.Children.Add((New-UTUiBadge 'Controverso' -Cor roxo)) }
    $texts = New-UTUiStack -Itens @($title)
    if ($Tweak.ganhoEsperado) {
        $gain = New-UTUiText ("Ganho: " + $Tweak.ganhoEsperado) -Tamanho 12 -Cor MutedBrush -Margem '0,2,0,0'
        $gain.TextTrimming = 'CharacterEllipsis'
        [void]$texts.Children.Add($gain)
    }
    [System.Windows.Controls.Grid]::SetColumn($texts, 1)
    [void]$grid.Children.Add($texts)

    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 8; $dot.Height = 8
    $dot.Margin = '12,0,6,0'
    $dot.VerticalAlignment = 'Center'
    $stateText = New-UTUiText '' -Tamanho 12
    $stateText.MinWidth = 92
    $state = New-UTUiStack -Horizontal -Itens @($dot, $stateText)
    $state.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($state, 2)
    [void]$grid.Children.Add($state)

    $row = New-Object System.Windows.Controls.Border
    $row.Padding = '10,8'
    $row.CornerRadius = 8
    $row.Margin = '0,1'
    $row.Background = [System.Windows.Media.Brushes]::Transparent
    $row.Child = $grid
    $row.ToolTip = Get-UTUiTweakToolTip -Tweak $Tweak
    [System.Windows.Controls.ToolTipService]::SetShowDuration($row, 60000)
    $row.Add_MouseEnter({ param($r, $evt) $null = $evt; $r.Background = Get-UTUiBrush 'CardHoverBrush' })
    $row.Add_MouseLeave({ param($r, $evt) $null = $evt; $r.Background = [System.Windows.Media.Brushes]::Transparent })

    $entry = [pscustomobject]@{ Id = $id; Pagina = $Pagina; Check = $cb; Ponto = $dot; EstadoTexto = $stateText; Borda = $row; Tweak = $Tweak }
    $ui.Rows.Add($entry)
    Sync-UTUiRowState -Linha $entry
    return $row
}

function Sync-UTUiRowState {
    param([Parameter(Mandatory)][psobject]$Linha)
    $ui = Get-UTUi
    $s = $null
    if ($ui.Estados.ContainsKey($Linha.Id)) { $s = $ui.Estados[$Linha.Id] }
    $visual = Get-UTUiStateVisual -Estado $(if ($s) { $s.Estado } else { '' })
    $Linha.EstadoTexto.Text = $visual.Texto
    $Linha.EstadoTexto.Foreground = Get-UTUiBrush $visual.Cor
    $Linha.Ponto.Fill = Get-UTUiBrush $visual.Cor
    $incompatible = ($s -and $s.Estado -eq 'Incompativel')
    $Linha.Check.IsEnabled = -not $incompatible
    if ($incompatible) {
        $Linha.Check.IsChecked = $false
        $Linha.EstadoTexto.ToolTip = $s.Motivo
        $Linha.Borda.ToolTip = Get-UTUiTweakToolTip -Tweak $Linha.Tweak -Motivo $s.Motivo
    } else {
        $Linha.Check.IsChecked = $ui.Selecionados.Contains($Linha.Id)
    }
}

function Sync-UTUiTweakState {
    <#
    .SYNOPSIS
        Stores the states read in the background and repaints every row of those tweaks.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Estados)
    $ui = Get-UTUi
    foreach ($s in $Estados) {
        if (-not $s.Id) { continue }
        $ui.Estados[[string]$s.Id] = $s
        if ($s.Estado -eq 'Incompativel') { [void]$ui.Selecionados.Remove([string]$s.Id) }
    }
    foreach ($row in $ui.Rows.ToArray()) { Sync-UTUiRowState -Linha $row }
    Sync-UTUiSelectionText
}

function Invoke-UTUiStateRefresh {
    <#
    .SYNOPSIS
        Reads the state of the given tweaks (all when empty) in the background.
    #>
    [CmdletBinding()]
    param([string[]]$Id)
    $args2 = @{}
    if ($Id) { $args2.Ids = $Id }
    [void](Invoke-UTUiJob -Nome 'Lendo o estado dos ajustes' -Argumentos $args2 -Script {
            param([string[]]$Ids)
            if ($Ids) { Get-UTTweakState -Id $Ids } else { Get-UTTweakState }
        } -AoTerminar {
            param($Resultado, $Estado)
            $null = $Estado
            if ($Resultado.Ok) { Sync-UTUiTweakState -Estados @($Resultado.Resultado) }
        })
}

function Set-UTUiSelection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Id, [Parameter(Mandatory)][bool]$Marcado)
    $ui = Get-UTUi
    foreach ($i in $Id) {
        if ($Marcado) {
            if ($ui.Estados.ContainsKey($i) -and $ui.Estados[$i].Estado -eq 'Incompativel') { continue }
            [void]$ui.Selecionados.Add($i)
        } else {
            [void]$ui.Selecionados.Remove($i)
        }
    }
    foreach ($row in @($ui.Rows | Where-Object { $Id -contains $_.Id })) {
        if ($row.Check.IsEnabled) { $row.Check.IsChecked = $ui.Selecionados.Contains($row.Id) }
    }
    Sync-UTUiSelectionText
}

function Clear-UTUiSelection {
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $ids = @($ui.Selecionados)
    if ($ids.Count -gt 0) { Set-UTUiSelection -Id $ids -Marcado $false }
}

function Get-UTUiSelectedId {
    # Selected ids in catalog order (the order tweaks are applied).
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $ui = Get-UTUi
    return @(Get-UTTweak | Where-Object { $ui.Selecionados.Contains([string]$_.id) } | ForEach-Object { [string]$_.id })
}

function Sync-UTUiSelectionText {
    $ui = Get-UTUi
    if ($null -eq $ui -or -not $ui.C.ContainsKey('SelectionText')) { return }
    $n = $ui.Selecionados.Count
    $ui.C['SelectionText'].Text = $(if ($n -eq 0) { 'Nenhum ajuste marcado' } elseif ($n -eq 1) { '1 ajuste marcado' } else { "$n ajustes marcados" })
}

function New-UTUiTweakList {
    <#
    .SYNOPSIS
        Card with the tweaks of a tab, grouped by risk, with "mark recommended" / "unmark".
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tweaks,
        [Parameter(Mandatory)][string]$Pagina,
        [string]$Titulo = 'Ajustes',
        [string]$Subtitulo
    )
    if (@($Tweaks).Count -eq 0) { return $null }
    $ids = @($Tweaks | ForEach-Object { [string]$_.id })
    $low = @($Tweaks | Where-Object { $_.risco -eq 'baixo' } | ForEach-Object { [string]$_.id })
    $tools = New-UTUiWrap -Margem '0,0,0,6'
    [void]$tools.Children.Add((New-UTUiButton 'Marcar os de risco baixo' -Estilo Link -Margem '0,0,18,0' -Dados $low -AoClicar { param($b, $d) $null = $b; Set-UTUiSelection -Id @($d) -Marcado $true }))
    [void]$tools.Children.Add((New-UTUiButton 'Desmarcar todos desta aba' -Estilo Link -Margem '0' -Dados $ids -AoClicar { param($b, $d) $null = $b; Set-UTUiSelection -Id @($d) -Marcado $false }))
    $content = New-Object System.Collections.Generic.List[object]
    $content.Add($tools)
    $groups = @(
        @{ Risco = 'baixo'; Titulo = 'Recomendados (risco baixo)' }
        @{ Risco = 'médio'; Titulo = 'Risco médio: leia a descrição antes' }
        @{ Risco = 'alto'; Titulo = 'Risco alto: pedem confirmação' }
    )
    foreach ($g in $groups) {
        $part = @($Tweaks | Where-Object { $_.risco -eq $g.Risco } | Sort-Object { [string]$_.nome })
        if ($part.Count -eq 0) { continue }
        $content.Add((New-UTUiText $g.Titulo -Tamanho 12 -Peso SemiBold -Cor AccentLightBrush -Margem '0,10,0,2'))
        foreach ($t in $part) { $content.Add((New-UTUiTweakRow -Tweak $t -Pagina $Pagina)) }
    }
    if (-not $Subtitulo) { $Subtitulo = 'Passe o mouse sobre um ajuste para ver o que ele faz, o ganho esperado e os cuidados.' }
    return (New-UTUiCard -Titulo $Titulo -Subtitulo $Subtitulo -Icone 'E762' -Conteudo $content.ToArray())
}

function Remove-UTUiPageRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Pagina)
    $ui = Get-UTUi
    foreach ($r in @($ui.Rows | Where-Object Pagina -eq $Pagina)) { [void]$ui.Rows.Remove($r) }
}

function Find-UTUiTweak {
    # Tweaks whose name, description or id contain the text (accent-insensitive).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto)
    $needle = ConvertTo-UTUiSearchText $Texto
    if (-not $needle) { return @() }
    foreach ($t in @(Get-UTTweak)) {
        $hay = ConvertTo-UTUiSearchText ("{0} {1} {2} {3}" -f $t.nome, $t.descricao, $t.id, $t.ganhoEsperado)
        if ($hay.Contains($needle)) { $t }
    }
}

function ConvertTo-UTUiSearchText {
    param([AllowEmptyString()][string]$Texto)
    if (-not $Texto) { return '' }
    $norm = $Texto.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString().ToLowerInvariant().Trim()
}

#region Apply / undo / simulate
function Invoke-UTUiRun {
    <#
    .SYNOPSIS
        Buttons "Aplicar selecionados", "Desfazer selecionados" and "Simular": confirmations
        (high risk listed one by one) and the background run.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Aplicar', 'Desfazer', 'Simular')][string]$Modo)
    if (Test-UTUiExclusiveJob) { return }
    $ids = @(Get-UTUiSelectedId)
    if ($ids.Count -eq 0) {
        [void](Show-UTUiDialog -Titulo 'Nenhum ajuste marcado' -Mensagem 'Marque os ajustes nas abas (ou escolha um preset) e tente de novo.' -Tipo info)
        return
    }
    if ($Modo -eq 'Aplicar' -and (Get-UTSyncValue -Key 'Simular')) { $Modo = 'Simular' }
    $tweaks = @(Get-UTTweak -Id $ids)
    $risk = $false

    if ($Modo -eq 'Aplicar') {
        $high = @($tweaks | Where-Object { $_.risco -eq 'alto' })
        if ($high.Count -gt 0) {
            $lines = @($high | ForEach-Object { "$($_.nome): $($_.confirmacao)" })
            $answer = Show-UTUiDialog -Titulo 'Ajustes de risco alto' -Tipo aviso -Largura 640 -Itens $lines `
                -Mensagem 'Estes ajustes podem causar instabilidade ou efeitos colaterais. Leia cada aviso. Tudo pode ser desfeito na aba Restaurar.' `
                -Botoes @('Entendo o risco, aplicar', 'Pular os de risco alto', 'Cancelar')
            if ($answer -eq 'Pular os de risco alto') {
                $skip = @($high | ForEach-Object { [string]$_.id })
                $ids = @($ids | Where-Object { $skip -notcontains $_ })
                $tweaks = @($tweaks | Where-Object { $skip -notcontains [string]$_.id })
                if ($ids.Count -eq 0) { return }
            } elseif ($answer -ne 'Entendo o risco, aplicar') {
                return
            } else {
                $risk = $true
            }
        }
        $restart = @($tweaks | Where-Object { $_.requerReinicio }).Count
        $msg = "Antes da primeira alteração o programa cria um ponto de restauração e um backup. Tudo pode ser desfeito depois."
        if ($restart -gt 0) { $msg += " $restart ajuste(s) só valem depois de reiniciar." }
        $answer = Show-UTUiDialog -Titulo "Aplicar $($ids.Count) ajuste(s)?" -Mensagem $msg -Tipo pergunta -Itens @($tweaks | ForEach-Object { [string]$_.nome }) -Botoes @('Aplicar', 'Cancelar')
        if ($answer -ne 'Aplicar') { return }
    } elseif ($Modo -eq 'Desfazer') {
        $answer = Show-UTUiDialog -Titulo "Desfazer $($ids.Count) ajuste(s)?" -Mensagem 'Cada ajuste volta exatamente ao valor que estava antes do Upgrade Tweaks mexer.' -Tipo pergunta -Itens @($tweaks | ForEach-Object { [string]$_.nome }) -Botoes @('Desfazer', 'Cancelar')
        if ($answer -ne 'Desfazer') { return }
    } else {
        $risk = $true
    }

    $label = @{ Aplicar = 'Aplicando ajustes'; Desfazer = 'Desfazendo ajustes'; Simular = 'Simulando' }[$Modo]
    [void](Invoke-UTUiJob -Nome $label -Exclusivo -Argumentos @{ Ids = $ids; Modo = $Modo; Risco = $risk } -Estado @{ Ids = $ids; Modo = $Modo } -Script {
            param([string[]]$Ids, [string]$Modo, [bool]$Risco)
            switch ($Modo) {
                'Aplicar' { Invoke-UTTweak -Id $Ids -RiscoAltoConfirmado:$Risco }
                'Simular' { Invoke-UTTweak -Id $Ids -RiscoAltoConfirmado:$Risco -WhatIf }
                'Desfazer' { Undo-UTTweak -Id $Ids }
            }
        } -AoTerminar {
            param($Resultado, $Estado)
            Complete-UTUiRun -Resultado $Resultado -Estado $Estado
        })
}

function Complete-UTUiRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Resultado, [Parameter(Mandatory)][hashtable]$Estado)
    if (-not $Resultado.Ok) { Show-UTUiError -Mensagem $Resultado.Erro; return }
    $results = @($Resultado.Resultado)

    # The refresh-rate change is confirmed first: if the monitor went black, it goes back alone.
    $hz = @($results | Where-Object { $_.Id -eq 'UT_GPU_MonitorMaxHz' -and $_.Status -eq 'Aplicado' })
    if ($Estado.Modo -eq 'Aplicar' -and $hz.Count -gt 0) {
        $keep = Show-UTUiCountdownDialog -Titulo 'Manter a nova taxa de atualização?' -Segundos 15 `
            -Mensagem 'O monitor agora está na taxa máxima. Se a imagem está normal, clique em Manter. Se a tela ficou preta ou piscando, espere: ela volta sozinha.'
        if (-not $keep) {
            [void](Invoke-UTUiJob -Nome 'Voltando a taxa de atualização' -Exclusivo -Script { Undo-UTTweak -Id 'UT_GPU_MonitorMaxHz' } -AoTerminar {
                    param($R, $E)
                    $null = $E
                    if (-not $R.Ok) { Show-UTUiError -Mensagem $R.Erro }
                    Invoke-UTUiStateRefresh -Id @('UT_GPU_MonitorMaxHz')
                })
            foreach ($r in $hz) { $r.Status = 'Desfeito'; $r.Mensagem = 'Voltou para a taxa anterior.' }
        }
    }

    $title = @{ Aplicar = 'Ajustes aplicados'; Desfazer = 'Ajustes desfeitos'; Simular = 'Simulação (nada foi alterado)' }[$Estado.Modo]
    [void](Show-UTUiRunSummary -Resultados $results -Titulo $title)
    if ($Estado.Modo -ne 'Simular') { Invoke-UTUiStateRefresh -Id $Estado.Ids }
}
#endregion
