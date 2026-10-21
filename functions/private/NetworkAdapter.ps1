# Network tweak helpers: adapter advanced properties (names differ per vendor, so the standard
# registry keywords are used), "allow the computer to turn off this device", IPv6
# DisabledComponents bits, Nagle per interface and QoS DSCP policies for the game.

function Get-UTNicKeywordSet {
    <#
    .SYNOPSIS
        Registry keywords (and the value that turns each feature off) for one adapter tweak.
        Intel, Realtek and Killer use different display names but these keywords.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('EconomiaEnergia', 'WakeOnLan', 'InterruptModeration', 'Rss')][string]$Conjunto)

    switch ($Conjunto) {
        'EconomiaEnergia' {
            return [ordered]@{
                '*EEE' = '0'; 'EEELinkAdvertisement' = '0'; 'AdvancedEEE' = '0'; 'EnableGreenEthernet' = '0'
                'GreenEthernet' = '0'; 'PowerSavingMode' = '0'; 'GigaLite' = '0'; '*SelectiveSuspend' = '0'
                'ULPMode' = '0'; 'ReduceSpeedOnPowerDown' = '0'; 'EnableSavePowerNow' = '0'; 'SavePowerNowEnabled' = '0'
                'AutoPowerSaveModeEnabled' = '0'; 'EnableDynamicPowerGating' = '0'; 'EnableConnectedPowerGating' = '0'
                'DMACoalescing' = '0'
            }
        }
        'WakeOnLan' { return [ordered]@{ '*WakeOnMagicPacket' = '0'; '*WakeOnPattern' = '0'; 'WakeOnLink' = '0'; 'S5WakeOnLan' = '0'; '*ModernStandbyWoLMagicPacket' = '0' } }
        'InterruptModeration' { return [ordered]@{ '*InterruptModeration' = '0' } }
        'Rss' { return [ordered]@{ '*RSS' = '1' } }
    }
}

function Get-UTPhysicalAdapter {
    [CmdletBinding()]
    param()
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PnPDeviceID -and $_.InterfaceDescription -notmatch '(?i)virtual|vpn|bluetooth' })
}

function Get-UTNicApplicableProperty {
    <#
    .SYNOPSIS
        Properties of -Conjunto that exist on each physical adapter and accept the "off" value.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Conjunto)
    $wanted = Get-UTNicKeywordSet -Conjunto $Conjunto
    foreach ($a in @(Get-UTPhysicalAdapter)) {
        foreach ($p in @(Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties -ErrorAction SilentlyContinue)) {
            $kw = [string]$p.RegistryKeyword
            if (-not $wanted.Contains($kw)) { continue }
            $target = [string]$wanted[$kw]
            $valid = @($p.ValidRegistryValues | ForEach-Object { [string]$_ })
            if ($valid.Count -gt 0 -and $valid -notcontains $target) { continue }
            [pscustomobject]@{
                Adaptador = $a.Name
                Descricao = $a.InterfaceDescription
                Palavra   = $kw
                Nome      = [string]$p.DisplayName
                Atual     = [string]((@($p.RegistryValue) | Select-Object -First 1))
                Alvo      = $target
            }
        }
    }
}

function Set-UTNicAdvancedProperty {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Conjunto,
        [Parameter(Mandatory)][string]$TweakId,
        # Energy saving: having none of the options is fine (nothing to turn off).
        [switch]$PermitirVazio
    )
    $props = @(Get-UTNicApplicableProperty -Conjunto $Conjunto)
    if ($props.Count -eq 0) {
        if ($PermitirVazio) { return }
        throw 'Sua placa de rede não tem esta opção.'
    }
    foreach ($p in @($props | Where-Object { $_.Atual -ne $_.Alvo })) {
        if (-not $PSCmdlet.ShouldProcess("$($p.Adaptador): $($p.Nome)", "$($p.Atual) -> $($p.Alvo)")) { continue }
        [void](Save-UTOriginalItem -Chave "nic|$($p.Descricao)|$($p.Palavra)" -Dados ([ordered]@{ adaptador = $p.Adaptador; descricao = $p.Descricao; palavra = $p.Palavra; valor = $p.Atual }) -TweakId $TweakId)
        Set-NetAdapterAdvancedProperty -Name $p.Adaptador -RegistryKeyword $p.Palavra -RegistryValue $p.Alvo -NoRestart -ErrorAction Stop
        Write-UTLog -Level Debug -TweakId $TweakId -Message "Placa $($p.Adaptador): $($p.Nome)" -Antes $p.Atual -Depois $p.Alvo
    }
    Restart-UTPhysicalAdapter -Adaptador @($props | ForEach-Object { $_.Adaptador } | Sort-Object -Unique)
}

function Restore-UTNicAdvancedProperty {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $touched = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @(Get-UTOriginalStateItem)) {
        $item = $entry.Item
        if ($item.tipo -ne 'generico' -or ([string]$item.chave) -notlike 'nic|*' -or @($item.tweaks) -notcontains $TweakId) { continue }
        $d = Pop-UTOriginalItem -Chave $item.chave -TweakId $TweakId
        if ($d -isnot [System.Collections.IDictionary]) { continue }
        $adapter = (@(Get-UTPhysicalAdapter | Where-Object { $_.InterfaceDescription -eq $d.descricao }) | Select-Object -First 1)
        if ($null -eq $adapter) { continue }
        if ($PSCmdlet.ShouldProcess("$($adapter.Name): $($d.palavra)", "Restaurar $($d.valor)")) {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $d.palavra -RegistryValue ([string]$d.valor) -NoRestart -ErrorAction Stop
            if (-not $touched.Contains($adapter.Name)) { $touched.Add($adapter.Name) }
        }
    }
    if ($touched.Count -gt 0) { Restart-UTPhysicalAdapter -Adaptador $touched.ToArray() }
}

function Test-UTNicAdvancedProperty {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Conjunto, [switch]$PermitirVazio)
    $props = @(Get-UTNicApplicableProperty -Conjunto $Conjunto)
    if ($props.Count -eq 0) { return [bool]$PermitirVazio }
    return ( @($props | Where-Object { $_.Atual -ne $_.Alvo }).Count -eq 0)
}

function Restart-UTPhysicalAdapter {
    <#
    .SYNOPSIS
        Restarts the adapters once so the new properties take effect (a few seconds offline).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$Adaptador)
    foreach ($name in @($Adaptador | Where-Object { $_ })) {
        if ($PSCmdlet.ShouldProcess($name, 'Reiniciar a placa de rede (alguns segundos sem internet)')) {
            Restart-NetAdapter -Name $name -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

function Get-UTNicClassKey {
    <#
    .SYNOPSIS
        Driver key of a network adapter ({4d36e972-...}\00XX), where PnPCapabilities lives.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InterfaceGuid)
    $classPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    $base = Open-UTRegistryKey -Path $classPath
    if ($null -eq $base) { return $null }
    try { $names = @($base.GetSubKeyNames() | Where-Object { $_ -match '^\d{4}$' }) } finally { $base.Dispose() }
    foreach ($n in $names) {
        $id = Get-UTRegistryValue -Path "$classPath\$n" -Name 'NetCfgInstanceId'
        if ($id.ValorExiste -and ([string]$id.Valor) -ieq $InterfaceGuid) { return "$classPath\$n" }
    }
    return $null
}

function Set-UTNicDevicePowerOff {
    <#
    .SYNOPSIS
        Unchecks "Allow the computer to turn off this device to save power" on the physical
        adapters (PnPCapabilities = 24).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    if (-not $PSCmdlet.ShouldProcess('placas de rede', 'Desmarcar "Permitir que o computador desligue este dispositivo"')) { return }
    foreach ($a in @(Get-UTPhysicalAdapter)) {
        $key = Get-UTNicClassKey -InterfaceGuid ([string]$a.InterfaceGuid)
        if ($key) { Set-UTRegistryValueTracked -Path $key -Name 'PnPCapabilities' -Type DWord -Value 24 -TweakId $TweakId }
    }
}

function Test-UTNicDevicePowerOff {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $adapters = @(Get-UTPhysicalAdapter)
    if ($adapters.Count -eq 0) { return $false }
    foreach ($a in $adapters) {
        $key = Get-UTNicClassKey -InterfaceGuid ([string]$a.InterfaceGuid)
        if (-not $key) { continue }
        $v = Get-UTRegistryValue -Path $key -Name 'PnPCapabilities'
        if (-not ($v.ValorExiste -and [int]$v.Valor -eq 24)) { return $false }
    }
    return $true
}

#region IPv6 DisabledComponents (bit field shared by "IPv4 preferido", Teredo and IPv6 off)
function Set-UTIpv6ComponentBit {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][int]$Bit,
        [Parameter(Mandatory)][string]$TweakId
    )
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    $current = Get-UTRegistryValue -Path $path -Name 'DisabledComponents'
    $value = $(if ($current.ValorExiste) { [int64]$current.Valor } else { 0 })
    if (-not $PSCmdlet.ShouldProcess("DisabledComponents", "$value -> $($value -bor $Bit)")) { return }
    [void](Backup-UTRegistryKey -Path $path)
    [void](Save-UTOriginalRegistryValue -Path $path -Name 'DisabledComponents' -TweakId $TweakId)
    Set-UTRegistryValue -Path $path -Name 'DisabledComponents' -Type DWord -Value ($value -bor $Bit)
}

function Clear-UTIpv6ComponentBit {
    <#
    .SYNOPSIS
        Undo: when no other tweak uses the value it goes back to the saved original; otherwise
        only this tweak's bit is cleared.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][int]$Bit,
        [Parameter(Mandatory)][string]$TweakId
    )
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    $status = Restore-UTOriginalRegistryValue -Path $path -Name 'DisabledComponents' -TweakId $TweakId
    if ($status -eq 'Restaurado') { return }
    $current = Get-UTRegistryValue -Path $path -Name 'DisabledComponents'
    if (-not $current.ValorExiste) { return }
    # The bit of this tweak may overlap others (IPv6 off is 0xFF); keep bits other tweaks still need.
    $others = 0
    foreach ($t in @(Get-UTAppliedRecord | ForEach-Object { $_.tweakId } | Where-Object { $_ -ne $TweakId })) {
        switch ($t) { 'UT_Net_PreferIPv4' { $others = $others -bor 0x20 } 'UT_Net_Teredo_Off' { $others = $others -bor 0x01 } 'UT_Net_IPv6_Off' { $others = $others -bor 0xFF } }
    }
    $newValue = ([int64]$current.Valor -band (-bnot ($Bit -band (-bnot $others)))) -band 0xFFFFFFFF
    Set-UTRegistryValue -Path $path -Name 'DisabledComponents' -Type DWord -Value $newValue
}

function Test-UTIpv6ComponentBit {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][int]$Bit)
    $v = Get-UTRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents'
    return ($v.ValorExiste -and (([int64]$v.Valor -band $Bit) -eq $Bit))
}
#endregion

#region Nagle
function Get-UTActiveInterfaceKey {
    <#
    .SYNOPSIS
        Tcpip\Parameters\Interfaces\{GUID} keys of the adapters that are connected.
    #>
    [CmdletBinding()]
    param()
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $guid = ([string]$a.InterfaceGuid)
        if ($guid) { "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" }
    }
}

function Set-UTNagleOff {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    if (-not $PSCmdlet.ShouldProcess('conexões ativas', 'TcpAckFrequency = 1 e TCPNoDelay = 1')) { return }
    $keys = @(Get-UTActiveInterfaceKey)
    if ($keys.Count -eq 0) { throw 'Nenhuma conexão de rede ativa encontrada.' }
    foreach ($k in $keys) {
        Set-UTRegistryValueTracked -Path $k -Name 'TcpAckFrequency' -Type DWord -Value 1 -TweakId $TweakId
        Set-UTRegistryValueTracked -Path $k -Name 'TCPNoDelay' -Type DWord -Value 1 -TweakId $TweakId
    }
}

function Test-UTNagleOff {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $keys = @(Get-UTActiveInterfaceKey)
    if ($keys.Count -eq 0) { return $false }
    foreach ($k in $keys) {
        foreach ($n in 'TcpAckFrequency', 'TCPNoDelay') {
            $v = Get-UTRegistryValue -Path $k -Name $n
            if (-not ($v.ValorExiste -and [int]$v.Valor -eq 1)) { return $false }
        }
    }
    return $true
}
#endregion

#region QoS DSCP for the game
function Get-UTGameQosName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([psobject]$Contexto)
    return @(Get-UTGameExecutable -Contexto $Contexto | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
}

function New-UTGameQosPolicy {
    <#
    .SYNOPSIS
        One QoS policy per game executable marking its traffic with DSCP 46 (Expedited Forwarding).
        Only helps if the router honours DSCP.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId, [psobject]$Contexto)
    $names = @(Get-UTGameQosName -Contexto $Contexto)
    if ($names.Count -eq 0) { throw 'Call of Duty não encontrado; nada a ajustar.' }
    # Without a domain, Windows only tags packets with this policy switch on.
    Set-UTRegistryValueTracked -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS' -Name 'Do not use NLA' -Type String -Value '1' -TweakId $TweakId
    foreach ($n in $names) {
        $policy = "Upgrade Tweaks - $n"
        if (Get-NetQosPolicy -Name $policy -ErrorAction SilentlyContinue) { continue }
        if ($PSCmdlet.ShouldProcess($policy, 'Criar política QoS DSCP 46')) {
            New-NetQosPolicy -Name $policy -AppPathNameMatchCondition $n -DSCPAction 46 -NetworkProfile All -IPProtocolMatchCondition Both -ErrorAction Stop | Out-Null
        }
    }
}

function Remove-UTGameQosPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    foreach ($p in @(Get-NetQosPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Upgrade Tweaks - *' })) {
        if ($PSCmdlet.ShouldProcess($p.Name, 'Remover política QoS')) { Remove-NetQosPolicy -Name $p.Name -Confirm:$false -ErrorAction Stop }
    }
    [void](Restore-UTTweakRegistryItem -TweakId $TweakId)
}

function Test-UTGameQosPolicy {
    [CmdletBinding()]
    [OutputType([bool])]
    param([psobject]$Contexto)
    $names = @(Get-UTGameQosName -Contexto $Contexto)
    if ($names.Count -eq 0) { return $false }
    foreach ($n in $names) {
        $p = Get-NetQosPolicy -Name "Upgrade Tweaks - $n" -ErrorAction SilentlyContinue
        if (-not $p -or [int]$p.DSCPAction -ne 46) { return $false }
    }
    return $true
}
#endregion
