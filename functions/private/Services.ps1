# Lookup tables live inside the functions: worker runspaces only receive function definitions.

function Get-UTServiceState {
    <#
    .SYNOPSIS
        Real start type of a service, read from the registry (Get-Service on PowerShell 5.1
        does not know "Automatic (Delayed Start)").
    .OUTPUTS
        Nome, Existe, StartType (Boot/System/Automatic/AutomaticDelayedStart/Manual/Disabled), Status.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $result = [pscustomobject]@{ Nome = $Name; Existe = $false; StartType = $null; Status = $null }
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"

    $start = Get-UTRegistryValue -Path $keyPath -Name 'Start'
    if (-not $start.ValorExiste) { return $result }

    $result.Existe = $true
    $startNames = @{ 0 = 'Boot'; 1 = 'System'; 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }
    $type = $startNames[[int]$start.Valor]
    if ($type -eq 'Automatic') {
        $delayed = Get-UTRegistryValue -Path $keyPath -Name 'DelayedAutostart'
        if ($delayed.ValorExiste -and [int]$delayed.Valor -eq 1) { $type = 'AutomaticDelayedStart' }
    }
    $result.StartType = $type

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service) { $result.Status = [string]$service.Status } else { $result.Status = 'Desconhecido' }
    return $result
}

function Set-UTServiceStartType {
    <#
    .SYNOPSIS
        Changes the start type with sc.exe (supports delayed start on PowerShell 5.1).
        -Parar also stops the service when it is being disabled.
    .DESCRIPTION
        Throws a PT-BR message (see Get-UTServiceErrorMessage) when Windows refuses, e.g.
        "Não foi possível alterar o serviço X porque ele é protegido pelo sistema".
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet('Boot', 'System', 'Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled')]
        [string]$StartType,
        [switch]$Parar
    )

    $current = Get-UTServiceState -Name $Name
    if (-not $current.Existe) { throw (Get-UTServiceErrorMessage -ExitCode 1060 -Name $Name) }
    if (-not $PSCmdlet.ShouldProcess("serviço $Name", "Tipo de inicialização: $($current.StartType) -> $StartType")) { return }

    $scArgument = @{
        'Boot' = 'boot'; 'System' = 'system'; 'Automatic' = 'auto'
        'AutomaticDelayedStart' = 'delayed-auto'; 'Manual' = 'demand'; 'Disabled' = 'disabled'
    }
    $r = Invoke-UTNative -FilePath 'sc.exe' -ArgumentList @('config', $Name, 'start=', $scArgument[$StartType])
    if ($r.CodigoSaida -ne 0) {
        $message = Get-UTServiceErrorMessage -ExitCode $r.CodigoSaida -Name $Name
        Write-UTLog -Level Erro -Message $message -Detalhe "sc.exe config: $($r.Saida) $($r.Erro)"
        throw $message
    }

    if ($Parar -and $StartType -eq 'Disabled' -and $current.Status -eq 'Running') {
        try {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        } catch {
            # The start type already changed; stopping now is a bonus, it takes effect at the next boot anyway.
            Write-UTLog -Level Aviso -Message "O serviço $Name foi desativado, mas só vai parar depois de reiniciar." -Detalhe $_.Exception.Message
        }
    }
}
