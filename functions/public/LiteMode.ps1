# "Modo Lite": the aggressive debloat as one list (config\modo-lite.json). The list is always
# shown first; the user unchecks what they want to keep and only then it is applied.

function Get-UTLiteModePlan {
    <#
    .SYNOPSIS
        Tweaks of the Modo Lite for this PC: Id, Nome, Risco, Marcado (default selection),
        Compativel and Motivo. Xbox/Game Pass services, the printer spooler, the Store, Game Bar,
        Defender and Windows Update never enter.
    #>
    [CmdletBinding()]
    param()

    $cfg = Get-UTConfig -Name 'modo-lite'
    $all = @(Get-UTTweak)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($cfg.incluir)) { if (-not $ids.Contains($id)) { $ids.Add($id) } }
    if ($cfg.incluirApps -eq 'todos' -or $cfg.incluirApps -eq 'padrao') {
        foreach ($t in @($all | Where-Object { $_.id -like 'UT_App_*' })) {
            if ($cfg.incluirApps -eq 'padrao' -and -not $t.debloatPadrao) { continue }
            if (-not $ids.Contains($t.id)) { $ids.Add($t.id) }
        }
    }
    $excluded = @($cfg.excluir)
    $neverGroups = @($cfg.nuncaIncluirGrupos)
    $context = Get-UTSystemContext

    foreach ($id in $ids) {
        if ($excluded -contains $id) { continue }
        $t = @($all | Where-Object { $_.id -eq $id })[0]
        if ($null -eq $t) { continue }
        if ($t.grupoServico -and $neverGroups -contains $t.grupoServico) { continue }
        $compat = Test-UTTweakCompatibility -Tweak $t -Contexto $context
        [pscustomobject]@{
            Id         = [string]$t.id
            Nome       = [string]$t.nome
            Categoria  = [string]$t.categoria
            Risco      = [string]$t.risco
            Marcado    = $compat.Compativel
            Compativel = $compat.Compativel
            Motivo     = $compat.Motivo
        }
    }
}

function Invoke-UTLiteMode {
    <#
    .SYNOPSIS
        Applies the Modo Lite items the user kept checked. -RiscoAltoConfirmado is passed only
        after the UI showed the high-risk confirmations (e.g. Edge removal).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [switch]$RiscoAltoConfirmado
    )
    $allowed = @(Get-UTLiteModePlan | ForEach-Object { $_.Id })
    $outside = @($Id | Where-Object { $allowed -notcontains $_ })
    if ($outside.Count -gt 0) { throw "Estes itens não fazem parte do Modo Lite: $($outside -join ', ')" }
    return (Invoke-UTTweak -Id $Id -RiscoAltoConfirmado:$RiscoAltoConfirmado -WhatIf:$WhatIfPreference)
}
