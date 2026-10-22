# Tweak lists of the tabs: one row per tweak (checkbox, name, badges, current state, tooltip),
# the shared selection, and the apply / undo / simulate flow with its confirmations.

function Get-UTUiTabDefinition {
    <#
    .SYNOPSIS
        Side tabs in order. Categorias = tweak categories listed in the tab.
    #>
    [CmdletBinding()]
    param()
    # Secao groups the sidebar like the macOS Settings; Cor is the squircle color (theme token).
    @(
        [pscustomobject]@{ Id = 'Inicio'; Nome = 'Início'; Icone = 'E80F'; Cor = 'IconBlue'; Secao = ''; Categorias = @() }
        [pscustomobject]@{ Id = 'Monitor'; Nome = 'Monitor'; Icone = 'E9D9'; Cor = 'IconGreen'; Secao = ''; Categorias = @() }
        [pscustomobject]@{ Id = 'Energia'; Nome = 'Energia'; Icone = 'E945'; Cor = 'IconOrange'; Secao = 'Otimização'; Categorias = @('Energia') }
        [pscustomobject]@{ Id = 'Gaming'; Nome = 'Gaming'; Icone = 'E7FC'; Cor = 'IconGreen'; Secao = 'Otimização'; Categorias = @('Gaming') }
        [pscustomobject]@{ Id = 'Latencia'; Nome = 'Latência'; Icone = 'E916'; Cor = 'IconPurple'; Secao = 'Otimização'; Categorias = @('Latencia') }
        [pscustomobject]@{ Id = 'Rede'; Nome = 'Rede'; Icone = 'E968'; Cor = 'IconBlue'; Secao = 'Otimização'; Categorias = @('Rede') }
        [pscustomobject]@{ Id = 'ServicosApps'; Nome = 'Serviços e Apps'; Icone = 'E71D'; Cor = 'IconGray'; Secao = 'Otimização'; Categorias = @('ServicosApps'); Pagina = 'Servico' }
        [pscustomobject]@{ Id = 'Privacidade'; Nome = 'Privacidade'; Icone = 'EA18'; Cor = 'IconIndigo'; Secao = 'Otimização'; Categorias = @('Privacidade') }
        [pscustomobject]@{ Id = 'GPU'; Nome = 'GPU'; Icone = 'E7F4'; Cor = 'IconTeal'; Secao = 'Otimização'; Categorias = @('GPU') }
        [pscustomobject]@{ Id = 'Warzone'; Nome = 'Warzone'; Icone = 'E7C1'; Cor = 'IconRed'; Secao = 'Otimização'; Categorias = @('Warzone') }
        [pscustomobject]@{ Id = 'Ferramentas'; Nome = 'Ferramentas'; Icone = 'EC7A'; Cor = 'IconGray'; Secao = 'Sistema'; Categorias = @('Ferramentas'); Pagina = 'Ferramenta' }
        [pscustomobject]@{ Id = 'BIOS'; Nome = 'BIOS'; Icone = 'E950'; Cor = 'IconIndigo'; Secao = 'Sistema'; Categorias = @(); Pagina = 'Firmware' }
        [pscustomobject]@{ Id = 'Programas'; Nome = 'Programas'; Icone = 'E896'; Cor = 'IconBlue'; Secao = 'Sistema'; Categorias = @(); Pagina = 'Programa' }
        [pscustomobject]@{ Id = 'Personalizar'; Nome = 'Personalizar'; Icone = 'E771'; Cor = 'IconPink'; Secao = 'Sistema'; Categorias = @('Personalizar', 'Visual') }
        [pscustomobject]@{ Id = 'Restaurar'; Nome = 'Restaurar'; Icone = 'E777'; Cor = 'IconOrange'; Secao = 'Geral'; Categorias = @() }
        [pscustomobject]@{ Id = 'Sobre'; Nome = 'Sobre'; Icone = 'E946'; Cor = 'IconGray'; Secao = 'Geral'; Categorias = @() }
    )
}

function Get-UTUiTabTweak {
    <#
    .SYNOPSIS
        Tweaks shown in a tab: its categories plus tweaks that list the tab in abasExtras.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Aba)
    $tab = (@(Get-UTUiTabDefinition | Where-Object Id -eq $Aba) | Select-Object -First 1)
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
    <#
    .SYNOPSIS
        One tweak: icon, name, short gain, the switch (on = applied) and the "i" with the details.
        Flipping the switch only records a pending change; "Revisar e aplicar" does the work.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [Parameter(Mandatory)][string]$Pagina,
        [string]$Icone = 'E762',
        [string]$IconeCor = 'IconBlue'
    )
    $ui = Get-UTUi
    $id = [string]$Tweak.id
    $badges = @()
    if ($Tweak.risco -ne 'baixo') { $badges += Get-UTUiRiskBadge -Risco ([string]$Tweak.risco) }
    if ($Tweak.requerReinicio) { $badges += New-UTUiBadge 'Reinício' -Cor azul }
    if ($Tweak.controverso) { $badges += New-UTUiBadge 'Controverso' -Cor roxo }

    $switch = New-UTUiSwitch -Marcado $false -Dados $id -Dica ([string]$Tweak.nome) -AoMudar {
        param($s, $d)
        if ((Get-UTUi).Sincronizando) { return }
        Set-UTUiPending -Id $d -Ligado ([bool]$s.IsChecked)
    }
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 7; $dot.Height = 7
    $dot.Margin = '0,0,6,0'
    $dot.VerticalAlignment = 'Center'
    $stateText = New-UTUiText '' -Tamanho 12 -Cor MutedBrush -Margem '0,0,12,0'
    $stateText.VerticalAlignment = 'Center'
    $right = New-UTUiStack -Horizontal -Itens @($dot, $stateText, $switch)
    $subtitle = $(if ($Tweak.ganhoEsperado) { 'Ganho: ' + [string]$Tweak.ganhoEsperado } else { '' })
    $row = New-UTUiRow -Titulo ([string]$Tweak.nome) -Subtitulo $subtitle -Icone $Icone -IconeCor $IconeCor -Direita $right -Selos $badges -Dados $id -AoClicarInfo {
        param($b, $d) $null = $b
        Show-UTUiTweakDetail -Id $d
    }
    $entry = [pscustomobject]@{ Id = $id; Pagina = $Pagina; Check = $switch; Ponto = $dot; EstadoTexto = $stateText; Borda = $row; Tweak = $Tweak }
    $ui.Rows.Add($entry)
    Sync-UTUiRowState -Linha $entry
    return $row
}

function Test-UTUiTweakApplied {
    # $true when the last read state says the tweak is on (Aplicado or Parcial).
    param([Parameter(Mandatory)][string]$Id)
    $ui = Get-UTUi
    return [bool]($ui.Estados.ContainsKey($Id) -and $ui.Estados[$Id].Estado -in 'Aplicado', 'Parcial')
}

function Sync-UTUiRowState {
    param([Parameter(Mandatory)][psobject]$Linha)
    $ui = Get-UTUi
    $s = $null
    if ($ui.Estados.ContainsKey($Linha.Id)) { $s = $ui.Estados[$Linha.Id] }
    $visual = Get-UTUiStateVisual -Estado $(if ($s) { $s.Estado } else { '' })
    $incompatible = ($s -and $s.Estado -eq 'Incompativel')
    $on = Test-UTUiTweakApplied -Id $Linha.Id
    $text = $visual.Texto; $color = $visual.Cor
    if ($ui.Selecionados.Contains($Linha.Id)) { $on = $true; $text = 'Será aplicado'; $color = 'AccentLightBrush' }
    elseif ($ui.Desmarcados.Contains($Linha.Id)) { $on = $false; $text = 'Será desfeito'; $color = 'YellowBrush' }
    $ui.Sincronizando = $true
    try {
        $Linha.Check.IsEnabled = -not $incompatible
        $Linha.Check.IsChecked = ($on -and -not $incompatible)
    } finally { $ui.Sincronizando = $false }
    $Linha.EstadoTexto.Text = $text
    $Linha.EstadoTexto.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $color)
    $Linha.Ponto.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $color)
    $Linha.EstadoTexto.ToolTip = $(if ($incompatible) { [string]$s.Motivo } else { $null })
}

function Sync-UTUiTweakState {
    <#
    .SYNOPSIS
        Stores the states read in the background and repaints every row of those tweaks. A
        pending change that is already true (on and applied, off and not applied) is dropped.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Estados)
    $ui = Get-UTUi
    foreach ($s in $Estados) {
        if (-not $s.Id) { continue }
        $id = [string]$s.Id
        $ui.Estados[$id] = $s
        if ($s.Estado -eq 'Incompativel') { [void]$ui.Selecionados.Remove($id); [void]$ui.Desmarcados.Remove($id) }
        elseif ($s.Estado -eq 'Aplicado') { [void]$ui.Selecionados.Remove($id) }
        elseif ($s.Estado -eq 'NaoAplicado') { [void]$ui.Desmarcados.Remove($id) }
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

function Set-UTUiPending {
    <#
    .SYNOPSIS
        A switch was flipped: on for a tweak that is not applied = pending apply; off for one
        that is applied = pending undo; flipping back cancels the pending change.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the selection in the interface.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][bool]$Ligado)
    $ui = Get-UTUi
    if ($ui.Estados.ContainsKey($Id) -and $ui.Estados[$Id].Estado -eq 'Incompativel') { return }
    $applied = Test-UTUiTweakApplied -Id $Id
    if ($Ligado) {
        [void]$ui.Desmarcados.Remove($Id)
        if (-not $applied) { [void]$ui.Selecionados.Add($Id) }
    } else {
        [void]$ui.Selecionados.Remove($Id)
        if ($applied) { [void]$ui.Desmarcados.Add($Id) }
    }
    foreach ($row in @($ui.Rows | Where-Object { $_.Id -eq $Id })) { Sync-UTUiRowState -Linha $row }
    Sync-UTUiSelectionText
}

function Set-UTUiSelection {
    <#
    .SYNOPSIS
        Marks tweaks to be applied (presets, imported selections). Tweaks already applied or that do
        not fit this PC are left as they are.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the selection in the interface.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Id, [Parameter(Mandatory)][bool]$Marcado)
    $ui = Get-UTUi
    foreach ($i in $Id) {
        if ($Marcado) {
            if ($ui.Estados.ContainsKey($i) -and $ui.Estados[$i].Estado -in 'Incompativel', 'Aplicado') { continue }
            [void]$ui.Desmarcados.Remove($i)
            [void]$ui.Selecionados.Add($i)
        } else {
            [void]$ui.Selecionados.Remove($i)
        }
    }
    foreach ($row in @($ui.Rows | Where-Object { $Id -contains $_.Id })) { Sync-UTUiRowState -Linha $row }
    Sync-UTUiSelectionText
}

function Clear-UTUiSelection {
    <#
    .SYNOPSIS
        "Descartar": forgets every pending change; the switches go back to the real state.
    #>
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    $ui.Selecionados.Clear()
    $ui.Desmarcados.Clear()
    foreach ($row in $ui.Rows.ToArray()) { Sync-UTUiRowState -Linha $row }
    Sync-UTUiSelectionText
}

function Get-UTUiSelectedId {
    # Tweaks pending apply, in catalog order (the order they are applied).
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $ui = Get-UTUi
    return @(Get-UTTweak | Where-Object { $ui.Selecionados.Contains([string]$_.id) } | ForEach-Object { [string]$_.id })
}

function Get-UTUiUndoId {
    # Tweaks pending undo, in reverse catalog order.
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $ui = Get-UTUi
    $ids = @(Get-UTTweak | Where-Object { $ui.Desmarcados.Contains([string]$_.id) } | ForEach-Object { [string]$_.id })
    [array]::Reverse($ids)
    return $ids
}

function Get-UTUiOnId {
    # Tweaks whose switch is on (applied and not switched off, or pending apply), in catalog order.
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $ui = Get-UTUi
    return @(Get-UTTweak | Where-Object {
            $i = [string]$_.id
            $ui.Selecionados.Contains($i) -or ((Test-UTUiTweakApplied -Id $i) -and -not $ui.Desmarcados.Contains($i))
        } | ForEach-Object { [string]$_.id })
}

function Get-UTUiPendingCount {
    $ui = Get-UTUi
    if ($null -eq $ui) { return 0 }
    return ($ui.Selecionados.Count + $ui.Desmarcados.Count)
}

function Sync-UTUiSelectionText {
    $ui = Get-UTUi
    if ($null -eq $ui -or -not $ui.C.ContainsKey('SelectionText')) { return }
    $n = Get-UTUiPendingCount
    $ui.C['SelectionText'].Text = $(if ($n -eq 0) { 'Nenhuma alteração pendente' } elseif ($n -eq 1) { '1 alteração pendente' } else { "$n alterações pendentes" })
    Sync-UTUiBusy
}

function New-UTUiTweakList {
    <#
    .SYNOPSIS
        The tweaks of a tab as grouped lists by risk, with "ligar os recomendados" and "descartar".
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
    $tab = (@(Get-UTUiTabDefinition | Where-Object Id -eq $Pagina) | Select-Object -First 1)
    $icon = $(if ($tab) { [string]$tab.Icone } else { 'E762' })
    $color = $(if ($tab) { [string](Get-UTField -Objeto $tab -Nome 'Cor' -Padrao 'IconBlue') } else { 'IconBlue' })
    $ids = @($Tweaks | ForEach-Object { [string]$_.id })
    $low = @($Tweaks | Where-Object { $_.risco -eq 'baixo' } | ForEach-Object { [string]$_.id })

    $root = New-UTUiStack
    $head = New-Object System.Windows.Controls.Grid
    foreach ($w in '*', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto })
        [void]$head.ColumnDefinitions.Add($cd)
    }
    $titleBox = New-UTUiStack -Itens @((New-UTUiText $Titulo -Tamanho 17 -Peso SemiBold))
    if (-not $Subtitulo) { $Subtitulo = 'Ligue ou desligue e clique em "Revisar e aplicar". O "i" mostra o que cada um faz.' }
    [void]$titleBox.Children.Add((New-UTUiText $Subtitulo -Cor MutedBrush -Quebrar -Margem '0,2,0,0'))
    [void]$head.Children.Add($titleBox)
    $tools = New-UTUiStack -Horizontal
    $tools.VerticalAlignment = 'Bottom'
    [void]$tools.Children.Add((New-UTUiButton 'Ligar os recomendados' -Estilo Link -Margem '0,0,18,0' -Dados $low -AoClicar { param($b, $d) $null = $b; Set-UTUiSelection -Id @($d) -Marcado $true }))
    [void]$tools.Children.Add((New-UTUiButton 'Descartar alterações' -Estilo Link -Margem '0' -Dados $ids -AoClicar {
                param($b, $d) $null = $b
                $u = Get-UTUi
                foreach ($i in @($d)) { [void]$u.Selecionados.Remove($i); [void]$u.Desmarcados.Remove($i) }
                foreach ($row in @($u.Rows | Where-Object { @($d) -contains $_.Id })) { Sync-UTUiRowState -Linha $row }
                Sync-UTUiSelectionText
            }))
    [System.Windows.Controls.Grid]::SetColumn($tools, 1)
    [void]$head.Children.Add($tools)
    $head.Margin = '0,8,0,12'
    [void]$root.Children.Add($head)

    $groups = @(
        @{ Risco = 'baixo'; Titulo = 'Recomendados'; Rodape = '' }
        @{ Risco = 'médio'; Titulo = 'Leia antes de ligar'; Rodape = 'Risco médio: veja o "i" para saber o que muda e o cuidado de cada um.' }
        @{ Risco = 'alto'; Titulo = 'Risco alto'; Rodape = 'Pedem uma confirmação a mais antes de aplicar.' }
    )
    foreach ($g in $groups) {
        $part = @($Tweaks | Where-Object { $_.risco -eq $g.Risco } | Sort-Object { [string]$_.nome })
        if ($part.Count -eq 0) { continue }
        $rows = @($part | ForEach-Object { New-UTUiTweakRow -Tweak $_ -Pagina $Pagina -Icone $icon -IconeCor $color })
        [void]$root.Children.Add((New-UTUiGroup -Titulo $g.Titulo -Linhas $rows -Rodape $g.Rodape -RecuoSeparador 56))
    }
    return $root
}

function Show-UTUiTweakDetail {
    <#
    .SYNOPSIS
        The "i" of a tweak: full description, risk, expected gain, what changes (registry and
        services) and, when it is applied, the button to undo it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $t = Get-UTTweak -Id $Id
    $ui = Get-UTUi
    $box = New-UTUiStack
    [void]$box.Children.Add((New-UTUiText ([string]$t.descricao) -Quebrar))
    $state = $(if ($ui.Estados.ContainsKey($Id)) { (Get-UTUiStateVisual -Estado $ui.Estados[$Id].Estado).Texto } else { 'Verificando...' })
    $pairs = @(
        , @('Risco', ([string]$t.risco))
        , @('Ganho esperado', ([string]$t.ganhoEsperado))
        , @('Reiniciar depois', $(if ($t.requerReinicio) { 'Sim' } else { 'Não' }))
        , @('Situação agora', $state)
    )
    $kv = New-UTUiKeyValue -Pares $pairs -LarguraRotulo 140
    $kv.Margin = '0,12,0,0'
    [void]$box.Children.Add($kv)
    if ($t.observacao) { [void]$box.Children.Add((New-UTUiText ([string]$t.observacao) -Cor YellowBrush -Quebrar -Margem '0,10,0,0')) }
    if ($t.risco -eq 'alto' -and $t.confirmacao) { [void]$box.Children.Add((New-UTUiText ([string]$t.confirmacao) -Cor RedBrush -Quebrar -Margem '0,8,0,0')) }
    $changes = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($t.registro | Where-Object { $_ })) {
        $name = $(if ([string]$r.nome) { [string]$r.nome } else { '(Padrão)' })
        $value = $(if ($r.Contains('acao') -and $r.acao -eq 'remover') { 'apagado' } else { ($r.valor | ForEach-Object { [string]$_ }) -join ', ' })
        $changes.Add("Registro: $($r.caminho)\$name = $value")
    }
    foreach ($s in @($t.servicos | Where-Object { $_ })) { $changes.Add("Serviço $($s.nome): inicialização $($s.inicio)") }
    if (@($t.scriptAplicar | Where-Object { $_ }).Count -gt 0) { $changes.Add('Procedimento próprio do programa: o botão Simular mostra cada passo neste PC.') }
    if ($changes.Count -gt 0) {
        [void]$box.Children.Add((New-UTUiText 'O que muda' -Peso SemiBold -Margem '0,14,0,4'))
        $list = New-UTUiStack
        foreach ($c in $changes) {
            $line = New-UTUiText $c -Tamanho 12 -Cor MutedBrush -Quebrar -Margem '0,1'
            $line.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, 'MonoFont')
            [void]$list.Children.Add($line)
        }
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.MaxHeight = 200
        $scroll.VerticalScrollBarVisibility = 'Auto'
        $scroll.Content = $list
        [void]$box.Children.Add($scroll)
    }
    $buttons = @('Fechar')
    if (Test-UTUiTweakApplied -Id $Id) { $buttons = @('Fechar', 'Desfazer este ajuste') }
    $answer = Show-UTUiSheet -Titulo ([string]$t.nome) -Tipo info -Conteudo $box -Botoes $buttons
    if ($answer -eq 'Desfazer este ajuste') {
        Set-UTUiPending -Id $Id -Ligado $false
        Invoke-UTUiRun -Modo Aplicar
    }
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

#region Progress (sheet without buttons while work runs)
function Show-UTUiProgress {
    <#
    .SYNOPSIS
        Non-blocking sheet with an animated progress bar while a long job runs.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Titulo, [string]$Texto)
    $ui = Get-UTUi
    if ($null -eq $ui -or $null -eq $ui.Window -or -not $ui.Window.IsVisible -or -not $ui.C.ContainsKey('SheetHost') -or $ui.SheetEstado) { Show-UTUiStatus $Titulo; return }
    $bar = New-Object System.Windows.Controls.ProgressBar
    $bar.IsIndeterminate = $true
    $bar.Height = 6
    $bar.Margin = '0,16,0,0'
    $box = New-UTUiStack -Itens @((New-UTUiText $Titulo -Tamanho 17 -Peso SemiBold))
    if ($Texto) { [void]$box.Children.Add((New-UTUiText $Texto -Cor MutedBrush -Quebrar -Margem '0,8,0,0')) }
    [void]$box.Children.Add($bar)
    $ui.C['SheetContent'].Content = $box
    $ui.C['SheetHost'].Visibility = 'Visible'
    $ui.ProgressoAberto = $true
}

function Hide-UTUiProgress {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $ui = Get-UTUi
    if ($null -eq $ui -or -not $ui.ProgressoAberto) { return }
    $ui.ProgressoAberto = $false
    if ($ui.C.ContainsKey('SheetHost') -and -not $ui.SheetEstado) { $ui.C['SheetHost'].Visibility = 'Collapsed'; $ui.C['SheetContent'].Content = $null }
}
#endregion

#region Review, apply, undo, simulate
function Invoke-UTUiRun {
    <#
    .SYNOPSIS
        "Revisar e aplicar" (Aplicar), "Simular" and the old "undo selected" (Desfazer).
    .DESCRIPTION
        Aplicar: confirms high-risk tweaks, computes in the background exactly what will change
        (the engine in simulation mode), shows it in a sheet, then applies the pending tweaks and
        undoes the ones switched off, with a progress sheet and a summary at the end.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Aplicar', 'Desfazer', 'Simular')][string]$Modo)
    if (Test-UTUiExclusiveJob) { return }

    if ($Modo -eq 'Desfazer') {
        $ids = @(Get-UTUiSelectedId)
        if ($ids.Count -eq 0) { return }
        $tweaks = @(Get-UTTweak -Id $ids)
        $answer = Show-UTUiDialog -Titulo "Desfazer $($ids.Count) ajuste(s)?" -Mensagem 'Cada ajuste volta exatamente ao valor que estava antes do Upgrade Tweaks mexer.' -Tipo pergunta -Itens @($tweaks | ForEach-Object { [string]$_.nome }) -Botoes @('Desfazer', 'Cancelar')
        if ($answer -ne 'Desfazer') { return }
        [void](Invoke-UTUiJob -Nome 'Desfazendo ajustes' -Exclusivo -Argumentos @{ Ids = $ids; Desfazer = @(); Modo = 'Desfazer'; Risco = $false } -Estado @{ Ids = $ids; Desfazer = @(); Modo = 'Desfazer' } -Script {
                param([string[]]$Ids) Undo-UTTweak -Id $Ids
            } -AoTerminar { param($Resultado, $Estado) Hide-UTUiProgress; Complete-UTUiRun -Resultado $Resultado -Estado $Estado })
        Show-UTUiProgress -Titulo 'Desfazendo ajustes...'
        return
    }

    $apply = @(Get-UTUiSelectedId)
    $undo = @(Get-UTUiUndoId)
    if ($apply.Count + $undo.Count -eq 0) {
        [void](Show-UTUiDialog -Titulo 'Nada para aplicar' -Mensagem 'Ligue ou desligue ajustes nas abas (ou escolha um preset no Início) e tente de novo.' -Tipo info)
        return
    }
    if ($Modo -eq 'Aplicar' -and (Get-UTSyncValue -Key 'Simular')) { $Modo = 'Simular' }
    $risk = $false
    if ($Modo -eq 'Simular') {
        $risk = $true
    } else {
        $high = @(Get-UTTweak -Id $apply | Where-Object { $_.risco -eq 'alto' })
        if ($high.Count -gt 0) {
            $lines = @($high | ForEach-Object { "$($_.nome): $($_.confirmacao)" })
            $answer = Show-UTUiDialog -Titulo 'Ajustes de risco alto' -Tipo aviso -Largura 640 -Itens $lines `
                -Mensagem 'Estes ajustes podem causar instabilidade ou efeitos colaterais. Leia cada aviso. Tudo pode ser desfeito depois.' `
                -Botoes @('Entendo o risco, aplicar', 'Pular os de risco alto', 'Cancelar')
            if ($answer -eq 'Pular os de risco alto') {
                $skip = @($high | ForEach-Object { [string]$_.id })
                $apply = @($apply | Where-Object { $skip -notcontains $_ })
                if ($apply.Count + $undo.Count -eq 0) { return }
            } elseif ($answer -ne 'Entendo o risco, aplicar') {
                return
            } else {
                $risk = $true
            }
        }
    }
    $state = @{ Ids = $apply; Desfazer = $undo; Modo = $Modo; Risco = $risk }
    [void](Invoke-UTUiJob -Nome 'Calculando o que vai mudar' -Exclusivo -Argumentos @{ Ids = $apply; Desfazer = $undo; Modo = $Modo; Risco = $risk } -Estado $state -Script {
            param([string[]]$Ids, [string[]]$Desfazer, [string]$Modo, [bool]$Risco)
            $null = $Modo
            if (@($Ids).Count -gt 0) { Invoke-UTTweak -Id $Ids -RiscoAltoConfirmado:$Risco -WhatIf }
            if (@($Desfazer).Count -gt 0) { Undo-UTTweak -Id $Desfazer -WhatIf }
        } -AoTerminar {
            param($Resultado, $Estado)
            Complete-UTUiPreview -Resultado $Resultado -Estado $Estado
        })
    Show-UTUiProgress -Titulo 'Calculando o que vai mudar...' -Texto 'Nada é alterado nesta etapa.'
}

function Complete-UTUiPreview {
    <#
    .SYNOPSIS
        The simulation came back: in simulation mode it is the result; otherwise the review sheet
        lists every change (current -> new) and, confirmed, the real run starts.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Resultado, [Parameter(Mandatory)][hashtable]$Estado)
    Hide-UTUiProgress
    if (-not $Resultado.Ok) { Show-UTUiError -Mensagem $Resultado.Erro; return }
    $results = @($Resultado.Resultado)
    if ($Estado.Modo -eq 'Simular') {
        [void](Show-UTUiRunSummary -Resultados $results -Titulo 'Simulação (nada foi alterado)')
        return
    }
    $items = New-Object System.Collections.Generic.List[string]
    $todo = 0
    foreach ($r in $results) {
        if ($r.Status -eq 'Simulado') {
            $todo++
            $verb = $(if (@($Estado.Desfazer) -contains $r.Id) { 'Desligar' } else { 'Ligar' })
            $items.Add("$verb`: $($r.Nome)")
            foreach ($a in @($r.Acoes)) { $items.Add("      $a") }
        } else {
            $items.Add("$($r.Nome): $($r.Mensagem)")
        }
    }
    if ($todo -eq 0) {
        [void](Show-UTUiRunSummary -Resultados $results -Titulo 'Nada para mudar')
        Complete-UTUiPending -Resultados $results -Estado $Estado
        return
    }
    $restart = @($results | Where-Object { $_.RequerReinicio }).Count
    $msg = 'Antes da primeira alteração o programa cria um ponto de restauração e um backup. Tudo pode ser desfeito depois.'
    if ($restart -gt 0) { $msg += " $restart ajuste(s) só valem depois de reiniciar." }
    $answer = Show-UTUiDialog -Titulo $(if ($todo -eq 1) { 'Aplicar 1 alteração?' } else { "Aplicar $todo alterações?" }) -Mensagem $msg -Tipo pergunta -Itens $items.ToArray() -Botoes @('Aplicar', 'Cancelar') -Largura 680
    if ($answer -ne 'Aplicar') { return }
    $run = @{ Ids = @($Estado.Ids); Desfazer = @($Estado.Desfazer); Modo = 'Aplicar'; Risco = [bool]$Estado.Risco }
    [void](Invoke-UTUiJob -Nome 'Aplicando ajustes' -Exclusivo -Argumentos @{ Ids = $run.Ids; Desfazer = $run.Desfazer; Modo = 'Aplicar'; Risco = $run.Risco } -Estado $run -Script {
            param([string[]]$Ids, [string[]]$Desfazer, [string]$Modo, [bool]$Risco)
            $null = $Modo
            if (@($Ids).Count -gt 0) { Invoke-UTTweak -Id $Ids -RiscoAltoConfirmado:$Risco }
            if (@($Desfazer).Count -gt 0) { Undo-UTTweak -Id $Desfazer }
        } -AoTerminar {
            param($Resultado, $Estado)
            Hide-UTUiProgress
            Complete-UTUiRun -Resultado $Resultado -Estado $Estado
        })
    Show-UTUiProgress -Titulo $(if ($todo -eq 1) { 'Aplicando 1 alteração...' } else { "Aplicando $todo alterações..." }) -Texto 'Não feche o programa até terminar.'
}

function Complete-UTUiPending {
    # After a run, the pending changes that were done (or had nothing to do) are cleared.
    param([AllowEmptyCollection()][object[]]$Resultados, [hashtable]$Estado)
    $ui = Get-UTUi
    $keep = @(@($Resultados) | Where-Object { $_.Status -in 'Falhou', 'PrecisaConfirmacao' } | ForEach-Object { [string]$_.Id })
    foreach ($id in @(@($Estado.Ids) + @(Get-UTField -Objeto $Estado -Nome 'Desfazer' -Padrao @()))) {
        if ($keep -contains $id) { continue }
        [void]$ui.Selecionados.Remove([string]$id)
        [void]$ui.Desmarcados.Remove([string]$id)
    }
    Sync-UTUiSelectionText
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

    $title = @{ Aplicar = 'Pronto'; Desfazer = 'Ajustes desfeitos'; Simular = 'Simulação (nada foi alterado)' }[$Estado.Modo]
    [void](Show-UTUiRunSummary -Resultados $results -Titulo $title)
    if ($Estado.Modo -ne 'Simular') {
        Complete-UTUiPending -Resultados $results -Estado $Estado
        $ids = @(@($Estado.Ids) + @(Get-UTField -Objeto $Estado -Nome 'Desfazer' -Padrao @()) | Where-Object { $_ })
        if ($ids.Count -gt 0) { Invoke-UTUiStateRefresh -Id $ids }
    }
}
#endregion
