# Intel Arc: the global Intel Graphics Software settings recommended for the game, written
# straight to the driver through the Intel Graphics Control Library (config\intel-igcl.json).

function Get-UTIntelSettingStatus {
    <#
    .SYNOPSIS
        Current x recommended for each setting on each Intel GPU. Read only.
    #>
    [CmdletBinding()]
    param()
    $cfg = Get-UTConfig -Name 'intel-igcl'
    $session = Open-UTIgclSession
    try {
        $devices = @($session.Devices())
        for ($i = 0; $i -lt $devices.Count; $i++) {
            foreach ($item in @($cfg.configuracoes)) {
                $v = $session.Get($devices[$i], [int]$item.recurso, [int]$item.tipo)
                $current = $(if ($v.Suportado) { $item.rotulos[[string]$v.Valor] } else { 'Não suportado' })
                if (-not $current) { $current = [string]$v.Valor }
                [pscustomobject]@{
                    Chave       = [string]$item.chave
                    Nome        = [string]$item.nome
                    Placa       = "Intel $($i + 1)"
                    Indice      = $i
                    Atual       = $current
                    Recomendado = [string]$item.rotulos[[string]$item.recomendado]
                    Suportado   = [bool]$v.Suportado
                    Igual       = ([bool]$v.Suportado -and [int]$v.Valor -eq [int]$item.recomendado)
                    Explicacao  = [string]$item.explicacao
                }
            }
        }
    } finally {
        $session.Dispose()
    }
}

function Get-UTIntelPlannedAction {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $rows = @(Get-UTIntelSettingStatus | Where-Object { $_.Suportado -and -not $_.Igual })
    if ($rows.Count -eq 0) { return @('Nada a mudar: tudo já está no recomendado.') }
    return @($rows | ForEach-Object { "$($_.Nome) [$($_.Placa)]: $($_.Atual) -> $($_.Recomendado)" })
}

function Test-UTIntelSetting {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $rows = @(Get-UTIntelSettingStatus | Where-Object { $_.Suportado })
    return ($rows.Count -gt 0 -and @($rows | Where-Object { -not $_.Igual }).Count -eq 0)
}

function Set-UTIntelRecommended {
    <#
    .SYNOPSIS
        Writes the recommended values, reading each one first: a feature the driver does not
        answer for is skipped, and every changed value is saved for undo (intel|<n>|<setting>).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $cfg = Get-UTConfig -Name 'intel-igcl'
    $session = Open-UTIgclSession
    try {
        $devices = @($session.Devices())
        if ($devices.Count -eq 0) { throw 'Nenhuma placa Intel encontrada pela Control Library.' }
        for ($i = 0; $i -lt $devices.Count; $i++) {
            foreach ($item in @($cfg.configuracoes)) {
                $v = $session.Get($devices[$i], [int]$item.recurso, [int]$item.tipo)
                if (-not $v.Suportado -or [int]$v.Valor -eq [int]$item.recomendado) { continue }
                if (-not $PSCmdlet.ShouldProcess("$($item.nome) (Intel $($i + 1))", "Definir $($item.recomendado)")) { continue }
                [void](Save-UTOriginalItem -Chave "intel|$i|$($item.chave)" -Dados ([ordered]@{ indice = $i; chave = [string]$item.chave; valor = [int]$v.Valor }) -TweakId $TweakId)
                $r = $session.Set($devices[$i], [int]$item.recurso, [int]$item.tipo, [int]$item.recomendado)
                if (-not $r.Suportado) { throw ("O driver Intel recusou mudar '{0}' (código 0x{1:X8})." -f $item.nome, $r.Resultado) }
                Write-UTLog -Level Info -TweakId $TweakId -Message "$($item.nome): $($item.rotulos[[string]$v.Valor]) -> $($item.rotulos[[string]$item.recomendado])."
            }
        }
    } finally {
        $session.Dispose()
    }
}

function Restore-UTIntelRecommended {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    $cfg = Get-UTConfig -Name 'intel-igcl'
    $pending = @(Get-UTOriginalStateItem | Where-Object { $_.Item.tipo -eq 'generico' -and ([string]$_.Item.chave) -like 'intel|*' -and @($_.Item.tweaks) -contains $TweakId })
    if ($pending.Count -eq 0) { return }
    $session = Open-UTIgclSession
    try {
        $devices = @($session.Devices())
        foreach ($entry in $pending) {
            $d = Pop-UTOriginalItem -Chave $entry.Item.chave -TweakId $TweakId
            if ($d -isnot [System.Collections.IDictionary]) { continue }
            $item = @($cfg.configuracoes | Where-Object { $_.chave -eq [string]$d.chave } | Select-Object -First 1)
            if ($item.Count -eq 0 -or [int]$d.indice -ge $devices.Count) { continue }
            [void]$session.Set($devices[[int]$d.indice], [int]$item[0].recurso, [int]$item[0].tipo, [int]$d.valor)
        }
    } finally {
        $session.Dispose()
    }
}
