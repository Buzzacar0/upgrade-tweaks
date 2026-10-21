# Public tweak engine: detect, apply, undo, simulate, undo everything.
# Every function takes tweak ids from config\tweaks.json and returns result objects
# (Id, Nome, Acao, Status, Mensagem, RequerReinicio, Acoes) for the UI and the command line.

function Get-UTTweakState {
    <#
    .SYNOPSIS
        Current state of each tweak: Aplicado, NaoAplicado, Parcial or Incompativel.
    #>
    [CmdletBinding()]
    param([string[]]$Id)

    $context = Get-UTSystemContext
    foreach ($tweak in (Get-UTTweak -Id $Id)) {
        $compat = Test-UTTweakCompatibility -Tweak $tweak -Contexto $context
        $state = [pscustomobject]@{ Estado = 'Desconhecido'; Detalhes = @() }
        try {
            $state = Get-UTTweakStateCore -Tweak $tweak -Contexto $context
        } catch {
            Write-UTLog -Level Aviso -TweakId $tweak.id -Message 'Não foi possível ler o estado deste ajuste.' -Detalhe $_.Exception.Message
        }
        $estado = $state.Estado
        if (-not $compat.Compativel -and $estado -ne 'Aplicado') { $estado = 'Incompativel' }
        [pscustomobject]@{
            Id         = [string]$tweak.id
            Nome       = [string]$tweak.nome
            Categoria  = [string]$tweak.categoria
            Risco      = [string]$tweak.risco
            Estado     = $estado
            Compativel = $compat.Compativel
            Motivo     = $compat.Motivo
            Detalhes   = $state.Detalhes
        }
    }
}

function Invoke-UTTweak {
    <#
    .SYNOPSIS
        Applies tweaks in the given order. One failure never stops the others.
    .DESCRIPTION
        For each tweak: admin check, compatibility, high-risk confirmation, already-applied check,
        session safety net (restore point + backup folder, once), backup and original state,
        apply, verification, journal. A failure in the middle rolls back that tweak.
        -WhatIf (Simular) changes nothing and returns the planned actions.
    .PARAMETER RiscoAltoConfirmado
        The user already confirmed the high-risk tweaks (dialog in the UI, "EU ENTENDO" in the CLI).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [switch]$RiscoAltoConfirmado,
        [switch]$SemPontoRestauracao
    )

    $context = Get-UTSystemContext
    foreach ($tweak in (Get-UTTweak -Id $Id)) {
        $tid = [string]$tweak.id
        try {
            $compat = Test-UTTweakCompatibility -Tweak $tweak -Contexto $context
            if (-not $compat.Compativel) {
                Write-UTLog -Level Info -TweakId $tid -Message "Ignorado: $($compat.Motivo)"
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status Ignorado -Mensagem $compat.Motivo
                continue
            }
            if ($tweak.risco -eq 'alto' -and -not $RiscoAltoConfirmado) {
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status PrecisaConfirmacao -Mensagem ([string]$tweak.confirmacao)
                continue
            }

            $state = Get-UTTweakStateCore -Tweak $tweak -Contexto $context
            if ($state.Estado -eq 'Aplicado') {
                Write-UTLog -Level Info -TweakId $tid -Message 'Já estava aplicado.'
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status JaAplicado -Mensagem 'Já estava aplicado.'
                continue
            }

            $actions = Get-UTTweakAction -Tweak $tweak -Modo Aplicar
            if (-not $PSCmdlet.ShouldProcess($tweak.nome, 'Aplicar')) {
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status Simulado -Mensagem 'Simulação: nada foi alterado.' -Acoes $actions
                continue
            }

            Assert-UTAdmin
            [void](Invoke-UTPreApplySafety -SemPontoRestauracao:$SemPontoRestauracao)

            # Alternatives in the same group (e.g. MPO modes) cannot stay applied together.
            if ($tweak.grupoExclusivo) {
                $siblings = @(Get-UTTweak | Where-Object { $_.grupoExclusivo -eq $tweak.grupoExclusivo -and $_.id -ne $tid })
                $applied = @(Get-UTAppliedRecord | ForEach-Object { $_.tweakId })
                foreach ($sibling in $siblings) {
                    if ($applied -contains $sibling.id) {
                        Write-UTLog -Level Info -TweakId $tid -Message "Desfazendo '$($sibling.nome)' antes, porque os dois não podem ficar ativos juntos."
                        [void](Undo-UTTweak -Id $sibling.id)
                    }
                }
            }

            Invoke-UTTweakApplyCore -Tweak $tweak -Contexto $context

            $after = Get-UTTweakStateCore -Tweak $tweak -Contexto $context
            if ($after.Estado -ne 'Aplicado') {
                Undo-UTTweakPartial -Tweak $tweak -Registro @($tweak.registro) -Servicos @($tweak.servicos) `
                    -ScriptAplicado:(@($tweak.scriptAplicar | Where-Object { $_ }).Count -gt 0) -Contexto $context
                $message = 'O Windows não manteve a alteração (pode haver uma política da empresa ou de outro programa controlando este ajuste). Nada foi mudado.'
                Write-UTLog -Level Erro -TweakId $tid -Message $message -Detalhe ($after.Detalhes -join ' | ')
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status Falhou -Mensagem $message -Acoes $actions
                continue
            }

            Add-UTAppliedRecord -TweakId $tid
            $note = ''
            if ($tweak.requerReinicio) { $note = ' Reinicie o PC para valer.' }
            Write-UTLog -Level Sucesso -TweakId $tid -Message "Aplicado: $($tweak.nome).$note"
            ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status Aplicado -Mensagem ("Aplicado.$note") -Acoes $actions
        } catch {
            $friendly = Get-UTFriendlyError -ErrorRecord $_ -Alvo "o ajuste '$($tweak.nome)'"
            if ($_.Exception.Message -match '^(Não foi possível|O serviço|O Upgrade Tweaks)') { $friendly = $_.Exception.Message }
            Write-UTLog -Level Erro -TweakId $tid -Message $friendly -Detalhe ("{0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
            ConvertTo-UTTweakResult -Tweak $tweak -Acao Aplicar -Status Falhou -Mensagem $friendly
        }
    }
}

function Undo-UTTweak {
    <#
    .SYNOPSIS
        Undoes tweaks: script -> services -> registry, back to the real saved values
        (or to Windows' defaults when nothing was saved).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string[]]$Id)

    $context = Get-UTSystemContext
    $journal = @(Get-UTAppliedRecord | ForEach-Object { $_.tweakId })
    foreach ($tweak in (Get-UTTweak -Id $Id)) {
        $tid = [string]$tweak.id
        try {
            $state = Get-UTTweakStateCore -Tweak $tweak -Contexto $context
            if ($state.Estado -eq 'NaoAplicado' -and $journal -notcontains $tid) {
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Desfazer -Status NaoAplicado -Mensagem 'Não estava aplicado.'
                continue
            }

            $actions = Get-UTTweakAction -Tweak $tweak -Modo Desfazer
            if (-not $PSCmdlet.ShouldProcess($tweak.nome, 'Desfazer')) {
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Desfazer -Status Simulado -Mensagem 'Simulação: nada foi alterado.' -Acoes $actions
                continue
            }
            Assert-UTAdmin

            $errors = New-Object System.Collections.Generic.List[string]
            $undo = @($tweak.scriptDesfazer | Where-Object { $_ })
            if ($undo.Count -gt 0) {
                try { [void](Invoke-UTTweakScript -Lines $undo -TweakId $tid -Contexto $context) }
                catch { $errors.Add('script: ' + $_.Exception.Message) }
            }
            foreach ($e in @($tweak.servicos | Where-Object { $_ })) {
                try { [void](Undo-UTServiceEntry -Entry $e -TweakId $tid) }
                catch { $errors.Add($_.Exception.Message) }
            }
            $registry = @($tweak.registro | Where-Object { $_ })
            [array]::Reverse($registry)
            foreach ($e in $registry) {
                try { [void](Undo-UTRegistryEntry -Entry $e -TweakId $tid) }
                catch { $errors.Add((Get-UTFriendlyError -ErrorRecord $_ -Alvo "$($e.caminho)\$($e.nome)")) }
            }

            if ($errors.Count -gt 0) {
                $message = 'Desfeito em parte: ' + ($errors -join '; ')
                Write-UTLog -Level Erro -TweakId $tid -Message $message
                ConvertTo-UTTweakResult -Tweak $tweak -Acao Desfazer -Status Falhou -Mensagem $message -Acoes $actions
                continue
            }

            Remove-UTAppliedRecord -TweakId $tid
            $note = ''
            if ($tweak.requerReinicio) { $note = ' Reinicie o PC para valer.' }
            Write-UTLog -Level Sucesso -TweakId $tid -Message "Desfeito: $($tweak.nome).$note"
            ConvertTo-UTTweakResult -Tweak $tweak -Acao Desfazer -Status Desfeito -Mensagem ("Desfeito.$note") -Acoes $actions
        } catch {
            $friendly = Get-UTFriendlyError -ErrorRecord $_ -Alvo "o ajuste '$($tweak.nome)'"
            Write-UTLog -Level Erro -TweakId $tid -Message $friendly -Detalhe $_.Exception.Message
            ConvertTo-UTTweakResult -Tweak $tweak -Acao Desfazer -Status Falhou -Mensagem $friendly
        }
    }
}

function Undo-UTAllTweak {
    <#
    .SYNOPSIS
        "Desfazer TUDO": undoes every applied tweak in reverse order of application, then puts back
        any original value still saved (e.g. from a tweak that left the catalog).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $catalog = @(Get-UTTweak | ForEach-Object { [string]$_.id })
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($record in @(Get-UTAppliedRecord -Reverse)) {
        if ($null -eq $record) { continue }
        $tid = [string]$record.tweakId
        if ($catalog -notcontains $tid) {
            Write-UTLog -Level Aviso -TweakId $tid -Message 'Este ajuste não existe mais no catálogo; os valores salvos dele serão restaurados no final.'
            if ($PSCmdlet.ShouldProcess($tid, 'Remover da lista de aplicados')) { Remove-UTAppliedRecord -TweakId $tid }
            continue
        }
        foreach ($r in @(Undo-UTTweak -Id $tid)) { $results.Add($r) }
    }

    $leftover = Restore-UTAllOriginalState
    foreach ($item in @($leftover.Falhas)) {
        $results.Add([pscustomobject]@{
                Id = ''; Nome = $item.Item; Acao = 'Desfazer'; Status = 'Falhou'; Mensagem = $item.Motivo; RequerReinicio = $false; Acoes = @()
            })
    }
    if (@($leftover.Restaurados).Count -gt 0) {
        Write-UTLog -Level Info -Message ("{0} valores salvos restaurados diretamente." -f @($leftover.Restaurados).Count)
    }
    return $results.ToArray()
}

function Get-UTRunSummary {
    <#
    .SYNOPSIS
        Counts the results of an apply/undo run and builds the PT-BR summary text
        ("X aplicados, Y já estavam aplicados, Z falharam") plus the restart warning.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resultados)

    $count = { param($status) @($Resultados | Where-Object { $_.Status -eq $status }).Count }
    $summary = [pscustomobject]@{
        Aplicados          = & $count 'Aplicado'
        JaAplicados        = & $count 'JaAplicado'
        Desfeitos          = & $count 'Desfeito'
        Ignorados          = & $count 'Ignorado'
        PrecisaConfirmacao = & $count 'PrecisaConfirmacao'
        Simulados          = & $count 'Simulado'
        Falhas             = @($Resultados | Where-Object { $_.Status -eq 'Falhou' })
        RequerReinicio     = @($Resultados | Where-Object { $_.RequerReinicio }).Count -gt 0
        Texto              = ''
    }

    $parts = New-Object System.Collections.Generic.List[string]
    if ($summary.Simulados -gt 0) { $parts.Add("$($summary.Simulados) seriam alterados (simulação)") }
    if ($summary.Aplicados -gt 0) { $parts.Add("$($summary.Aplicados) aplicados") }
    if ($summary.Desfeitos -gt 0) { $parts.Add("$($summary.Desfeitos) desfeitos") }
    if ($summary.JaAplicados -gt 0) { $parts.Add("$($summary.JaAplicados) já estavam aplicados") }
    if ($summary.Ignorados -gt 0) { $parts.Add("$($summary.Ignorados) não se aplicam a este PC") }
    if ($summary.PrecisaConfirmacao -gt 0) { $parts.Add("$($summary.PrecisaConfirmacao) aguardando confirmação de risco") }
    $parts.Add("$($summary.Falhas.Count) falharam")
    $text = ($parts -join ', ') + '.'
    foreach ($f in $summary.Falhas) { $text += "`n - $($f.Nome): $($f.Mensagem)" }
    if ($summary.RequerReinicio) { $text += "`nReinicie o computador para concluir algumas alterações." }
    $summary.Texto = $text
    return $summary
}
