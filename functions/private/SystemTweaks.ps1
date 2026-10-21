# Helpers for the "Latência e sistema" tweaks: boot configuration (bcdedit), MSI interrupt
# mode, USB power management, memory compression and BitLocker.

#region bcdedit
function Get-UTBcdSetting {
    <#
    .SYNOPSIS
        Reads one element of the current boot entry. Existe/Valor; "Yes"/"Sim" become $true.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $r = Invoke-UTNative -FilePath 'bcdedit.exe' -ArgumentList @('/enum', '{current}')
    if ($r.CodigoSaida -ne 0) { throw "bcdedit /enum falhou: $($r.Saida) $($r.Erro)" }
    $m = [regex]::Match($r.Saida, "(?im)^\s*$([regex]::Escape($Name))\s+(\S+)")
    if (-not $m.Success) { return [pscustomobject]@{ Existe = $false; Valor = $null; Ligado = $false } }
    $value = $m.Groups[1].Value
    return [pscustomobject]@{ Existe = $true; Valor = $value; Ligado = ($value -match '^(?i)(yes|sim|on|true|1)$') }
}

function Suspend-UTBitLockerForBoot {
    <#
    .SYNOPSIS
        Changing the boot configuration with BitLocker on makes Windows ask for the recovery key
        at the next boot. Suspending protection for one restart avoids that.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) { return }
    $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    if ($v -and [string]$v.ProtectionStatus -eq 'On' -and $PSCmdlet.ShouldProcess($env:SystemDrive, 'Suspender o BitLocker por 1 reinício')) {
        Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 | Out-Null
        Write-UTLog -Level Info -Message 'BitLocker suspenso por um reinício para a alteração de boot não pedir a chave de recuperação.'
    }
}

function Set-UTBcdSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$TweakId
    )
    if (-not $PSCmdlet.ShouldProcess("bcdedit $Name", "Definir $Value")) { return }
    $before = Get-UTBcdSetting -Name $Name
    [void](Save-UTOriginalItem -Chave "bcd|$Name" -Dados ([ordered]@{ existia = $before.Existe; valor = $before.Valor }) -TweakId $TweakId)
    Suspend-UTBitLockerForBoot
    $r = Invoke-UTNative -FilePath 'bcdedit.exe' -ArgumentList @('/set', '{current}', $Name, $Value)
    if ($r.CodigoSaida -ne 0) { throw "bcdedit /set $Name falhou: $($r.Saida) $($r.Erro)" }
}

function Restore-UTBcdSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TweakId
    )
    if (-not $PSCmdlet.ShouldProcess("bcdedit $Name", 'Restaurar')) { return }
    $saved = Pop-UTOriginalItem -Chave "bcd|$Name" -TweakId $TweakId
    if ($saved -eq 'MantidoPorOutroTweak') { return }
    Suspend-UTBitLockerForBoot
    if ($saved -is [System.Collections.IDictionary] -and $saved.existia) {
        $r = Invoke-UTNative -FilePath 'bcdedit.exe' -ArgumentList @('/set', '{current}', $Name, [string]$saved.valor)
    } else {
        $r = Invoke-UTNative -FilePath 'bcdedit.exe' -ArgumentList @('/deletevalue', '{current}', $Name)
    }
    if ($r.CodigoSaida -ne 0) { throw "bcdedit falhou ao restaurar $Name`: $($r.Saida) $($r.Erro)" }
}
#endregion

#region MSI (Message Signaled Interrupts)
function Get-UTMsiDevice {
    <#
    .SYNOPSIS
        PCI devices for the MSI tweak: dedicated GPU(s) or physical network adapters.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('GPU', 'NIC')][string]$Tipo)

    if ($Tipo -eq 'GPU') {
        $devices = @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
                $_.InstanceId -like 'PCI\VEN_10DE*' -or
                ($_.InstanceId -like 'PCI\VEN_1002*' -and $_.FriendlyName -notmatch '^AMD Radeon\(TM\)( \w+)? Graphics$') -or
                ($_.InstanceId -like 'PCI\VEN_8086*' -and $_.FriendlyName -match '\bArc\b')
            })
    } else {
        $ids = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PnPDeviceID -like 'PCI\*' } | ForEach-Object { $_.PnPDeviceID })
        $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $ids -contains $_.InstanceId })
    }
    foreach ($d in $devices) {
        [pscustomobject]@{
            Nome      = [string]$d.FriendlyName
            Instancia = [string]$d.InstanceId
            Caminho   = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        }
    }
}

function Set-UTMsiMode {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('GPU', 'NIC')][string]$Tipo, [Parameter(Mandatory)][string]$TweakId)
    $devices = @(Get-UTMsiDevice -Tipo $Tipo)
    if ($devices.Count -eq 0) { throw 'Nenhum dispositivo compatível encontrado.' }
    foreach ($d in $devices) {
        Set-UTRegistryValueTracked -Path $d.Caminho -Name 'MSISupported' -Type DWord -Value 1 -TweakId $TweakId
        Write-UTLog -Level Info -TweakId $TweakId -Message "Modo MSI ligado em $($d.Nome)."
    }
}

function Test-UTMsiMode {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][ValidateSet('GPU', 'NIC')][string]$Tipo)
    $devices = @(Get-UTMsiDevice -Tipo $Tipo)
    if ($devices.Count -eq 0) { return $false }
    foreach ($d in $devices) {
        $v = Get-UTRegistryValue -Path $d.Caminho -Name 'MSISupported'
        if (-not ($v.ValorExiste -and [int]$v.Valor -eq 1)) { return $false }
    }
    return $true
}
#endregion

#region USB power management ("Permitir que o computador desligue este dispositivo")
function Get-UTUsbPowerDevice {
    [CmdletBinding()]
    param()
    @(Get-CimInstance -Namespace 'root/wmi' -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.InstanceName -like 'USB\*' })
}

function Set-UTUsbDeviceEnable {
    # Thin wrapper so tests can replace the CIM write.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][object]$Dispositivo, [Parameter(Mandatory)][bool]$Ativo)
    if ($PSCmdlet.ShouldProcess([string]$Dispositivo.InstanceName, "Economia de energia = $Ativo")) {
        Set-CimInstance -InputObject $Dispositivo -Property @{ Enable = $Ativo } -ErrorAction Stop
    }
}

function Disable-UTUsbPowerSaving {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $devices = @(Get-UTUsbPowerDevice)
    $original = [ordered]@{}
    foreach ($d in $devices) { $original[[string]$d.InstanceName] = [bool]$d.Enable }
    [void](Save-UTOriginalItem -Chave 'usb|energia' -Dados $original -TweakId $TweakId)
    foreach ($d in @($devices | Where-Object { $_.Enable })) {
        if ($PSCmdlet.ShouldProcess([string]$d.InstanceName, 'Não deixar o Windows desligar para economizar energia')) {
            Set-UTUsbDeviceEnable -Dispositivo $d -Ativo $false
        }
    }
}

function Restore-UTUsbPowerSaving {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $saved = Pop-UTOriginalItem -Chave 'usb|energia' -TweakId $TweakId
    if ($saved -isnot [System.Collections.IDictionary]) { return }
    foreach ($d in @(Get-UTUsbPowerDevice)) {
        $name = [string]$d.InstanceName
        if ($saved.Contains($name) -and [bool]$saved[$name] -ne [bool]$d.Enable -and $PSCmdlet.ShouldProcess($name, 'Restaurar economia de energia')) {
            Set-UTUsbDeviceEnable -Dispositivo $d -Ativo ([bool]$saved[$name])
        }
    }
}

function Test-UTUsbPowerSaving {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $devices = @(Get-UTUsbPowerDevice)
    return ($devices.Count -gt 0 -and @($devices | Where-Object { $_.Enable }).Count -eq 0)
}
#endregion

#region BitLocker
function Get-UTBitLockerStatus {
    <#
    .SYNOPSIS
        BitLocker / Device Encryption state of the system drive, including decryption progress.
    #>
    [CmdletBinding()]
    param()
    $status = [pscustomobject]@{ Disponivel = $false; Protegido = $false; Estado = 'Desconhecido'; Percentual = $null }
    if (-not (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) { return $status }
    $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $status }
    $status.Disponivel = $true
    $status.Protegido = ([string]$v.ProtectionStatus -eq 'On')
    $status.Estado = [string]$v.VolumeStatus
    $status.Percentual = $v.EncryptionPercentage
    return $status
}
#endregion
