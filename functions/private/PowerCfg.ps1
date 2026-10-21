# powercfg helpers. Output of powercfg is localized, so parsing relies only on GUIDs and on the
# 0x######## values, never on the words around them.

function Invoke-UTPowerCfg {
    <#
    .SYNOPSIS
        Runs powercfg.exe and throws (with its output) when it fails.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Argumentos)

    $r = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList $Argumentos
    if ($r.CodigoSaida -ne 0) {
        throw ("powercfg {0} falhou ({1}): {2} {3}" -f ($Argumentos -join ' '), $r.CodigoSaida, $r.Saida, $r.Erro).Trim()
    }
    return $r.Saida
}

function Get-UTPowerSchemeList {
    <#
    .SYNOPSIS
        Power plans from "powercfg /list": Guid, Nome, Ativo.
    #>
    [CmdletBinding()]
    param()

    $out = Invoke-UTPowerCfg -Argumentos @('/list')
    foreach ($line in ($out -split "`r?`n")) {
        $m = [regex]::Match($line, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([^)]*)\)\s*(\*)?')
        if (-not $m.Success) { continue }
        [pscustomobject]@{
            Guid  = $m.Groups[1].Value.ToLowerInvariant()
            Nome  = $m.Groups[2].Value.Trim()
            Ativo = $m.Groups[3].Success
        }
    }
}

function Test-UTPowerScheme {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Guid)
    return (@(Get-UTPowerSchemeList | Where-Object { $_.Guid -eq $Guid.ToLowerInvariant() }).Count -gt 0)
}

function Get-UTPowerSettingValue {
    <#
    .SYNOPSIS
        Current AC/DC index of a power setting (also hidden ones: uses "powercfg /qh").
        Existe is $false when this Windows does not have the setting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Esquema,
        [Parameter(Mandatory)][string]$Subgrupo,
        [Parameter(Mandatory)][string]$Configuracao
    )

    $r = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('/qh', $Esquema, $Subgrupo, $Configuracao)
    $hex = @([regex]::Matches($r.Saida, '0x([0-9a-fA-F]{8})') | ForEach-Object { [Convert]::ToInt64($_.Groups[1].Value, 16) })
    if ($r.CodigoSaida -ne 0 -or $hex.Count -lt 2 -or $r.Saida -notmatch [regex]::Escape($Configuracao)) {
        return [pscustomobject]@{ Existe = $false; AC = $null; DC = $null }
    }
    # The current AC and DC indexes are always the last two values printed.
    return [pscustomobject]@{ Existe = $true; AC = $hex[$hex.Count - 2]; DC = $hex[$hex.Count - 1] }
}

function Set-UTPowerSettingValue {
    <#
    .SYNOPSIS
        Sets the AC index (plugged in) and, when given, the DC index (battery) of a power setting.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Esquema,
        [Parameter(Mandatory)][string]$Subgrupo,
        [Parameter(Mandatory)][string]$Configuracao,
        [Parameter(Mandatory)][long]$AC,
        [Nullable[long]]$DC
    )

    if (-not $PSCmdlet.ShouldProcess("$Esquema $Configuracao", "Na tomada = $AC; bateria = $DC")) { return }
    [void](Invoke-UTPowerCfg -Argumentos @('/setacvalueindex', $Esquema, $Subgrupo, $Configuracao, [string]$AC))
    if ($null -ne $DC) {
        [void](Invoke-UTPowerCfg -Argumentos @('/setdcvalueindex', $Esquema, $Subgrupo, $Configuracao, [string]$DC))
    }
}

function Copy-UTPowerScheme {
    <#
    .SYNOPSIS
        powercfg /duplicatescheme; returns the GUID of the new plan.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Base)

    if (-not $PSCmdlet.ShouldProcess($Base, 'Duplicar plano de energia')) { return $null }
    $out = Invoke-UTPowerCfg -Argumentos @('/duplicatescheme', $Base)
    $m = [regex]::Match($out, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if (-not $m.Success) { throw "powercfg /duplicatescheme não devolveu o GUID do novo plano: $out" }
    return $m.Value.ToLowerInvariant()
}

function Find-UTUpgradePowerScheme {
    <#
    .SYNOPSIS
        GUID of the "Upgrade Warzone" plan if it exists: first the one recorded in the original
        state, then any plan with that name (left from an earlier install).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $schemes = @(Get-UTPowerSchemeList)
    $saved = Get-UTOriginalItem -Chave 'generico|energia|planoupgrade'
    if ($saved -and $saved.dados.guid -and @($schemes | Where-Object { $_.Guid -eq $saved.dados.guid }).Count -gt 0) {
        return [string]$saved.dados.guid
    }
    $cfg = Get-UTConfig -Name 'powerplan'
    $byName = (@($schemes | Where-Object { $_.Nome -eq $cfg.nome -or $_.Nome -eq $cfg.nomeNotebook }) | Select-Object -First 1)
    if ($byName) { return $byName.Guid }
    return $null
}
