function Get-UTX3DInfo {
    <#
    .SYNOPSIS
        Identifies Ryzen 3D V-Cache CPUs and whether they have one or two CCDs.
    .DESCRIPTION
        Uses config\cpu-x3d.json. A model missing from the list (newer than this version) is
        classified by core count: more than 8 cores means two CCDs on Zen 4/Zen 5.
        Returns EhX3D, Modelo, Tipo ('unico'/'duplo'), VCacheNosDois and Fonte ('lista'/'nucleos').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Nome,
        [int]$Nucleos = 0
    )

    $none = [pscustomobject]@{ EhX3D = $false; Modelo = $null; Tipo = $null; VCacheNosDois = $false; Fonte = $null }
    $m = [regex]::Match($Nome.ToUpperInvariant(), '\b(\d{4,5}[A-Z]*X3D\d?)\b')
    if (-not $m.Success -or $Nome -notmatch '(?i)ryzen') { return $none }
    $model = $m.Groups[1].Value

    $list = @()
    try { $list = @((Get-UTConfig -Name 'cpu-x3d').modelos) } catch { $list = @() }
    $entry = $list | Where-Object { [string]$_.modelo -eq $model } | Select-Object -First 1
    if ($entry) {
        return [pscustomobject]@{
            EhX3D = $true; Modelo = $model; Tipo = [string]$entry.ccd
            VCacheNosDois = [bool]$entry.vcacheNosDois; Fonte = 'lista'
        }
    }

    $type = 'duplo'
    if ($Nucleos -gt 0 -and $Nucleos -le 8) { $type = 'unico' }
    return [pscustomobject]@{ EhX3D = $true; Modelo = $model; Tipo = $type; VCacheNosDois = $false; Fonte = 'nucleos' }
}
