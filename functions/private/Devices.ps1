# Optional devices the user may want to disable ("Latência e sistema" tab, list with checkboxes):
# serial/COM ports, Wi-Fi when the PC is on a cable, Bluetooth, the GPU's HDMI/DisplayPort audio.
# Nothing is suggested automatically; the user picks each one.

function Get-UTOptionalDevice {
    <#
    .SYNOPSIS
        Candidates with Tipo, Nome, InstanceId, Ativo and Sugestao (why it may be unnecessary).
    #>
    [CmdletBinding()]
    param()

    $wiredUp = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.MediaType -eq '802.3' }).Count -gt 0
    $all = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)

    foreach ($d in $all) {
        $name = [string]$d.FriendlyName
        $class = [string]$d.Class
        $kind = $null
        $why = ''
        if ($class -eq 'Ports' -and $name -match '\(COM\d+\)') {
            $kind = 'Porta serial (COM)'
            $why = 'Só é usada por equipamentos antigos ou de automação.'
        } elseif ($class -eq 'Net' -and $name -match '(?i)wi-?fi|wireless|802\.11|wlan') {
            $kind = 'Wi-Fi'
            $why = $(if ($wiredUp) { 'O PC está conectado por cabo; o Wi-Fi não está sendo usado.' } else { 'Desative só se usar cabo de rede.' })
        } elseif ($class -eq 'Bluetooth' -and $name -notmatch '(?i)enumerator|le |rfcomm|protocol|service') {
            $kind = 'Bluetooth'
            $why = 'Desative só se não usar fone, controle ou outro aparelho Bluetooth.'
        } elseif ($class -eq 'MEDIA' -and $name -match '(?i)(NVIDIA|AMD|Intel).*(High Definition Audio|HD Audio)|High Definition Audio.*(NVIDIA|AMD)') {
            $kind = 'Áudio da placa de vídeo (HDMI/DisplayPort)'
            $why = 'Desative só se o som não sai pelo monitor ou pela TV.'
        }
        if ($null -eq $kind) { continue }
        [pscustomobject]@{
            Tipo       = $kind
            Nome       = $name
            InstanceId = [string]$d.InstanceId
            Ativo      = ([string]$d.Status -eq 'OK')
            Sugestao   = $why
        }
    }
}

function Disable-UTOptionalDevice {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InstanceId)
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess($InstanceId, 'Desativar dispositivo')) { return }
    [void](Invoke-UTPreApplySafety)
    [void](Save-UTOriginalItem -Chave "dispositivo|$InstanceId" -Dados ([ordered]@{ instancia = $InstanceId; ativo = $true }) -TweakId 'UT_Dispositivos')
    Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
    Write-UTLog -Level Sucesso -Message "Dispositivo desativado: $InstanceId"
}

function Enable-UTOptionalDevice {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InstanceId)
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess($InstanceId, 'Reativar dispositivo')) { return }
    Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
    [void](Pop-UTOriginalItem -Chave "dispositivo|$InstanceId" -TweakId 'UT_Dispositivos')
    Write-UTLog -Level Sucesso -Message "Dispositivo reativado: $InstanceId"
}
