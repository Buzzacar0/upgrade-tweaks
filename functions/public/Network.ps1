# "Rede" tab: DNS selector with speed test, connection info, latency/jitter/loss test and the
# repair tools. DNS changes go through catalog tweaks (UT_Net_DNS_*), so they are undone by
# "Desfazer TUDO" like everything else; DHCP (the provider's DNS) is the undo.

#region DNS
function Get-UTDnsTargetInterface {
    <#
    .SYNOPSIS
        Connected physical adapters (Ethernet/Wi-Fi) whose DNS the program changes.
    #>
    [CmdletBinding()]
    param()
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
}

function Get-UTInterfaceDnsState {
    <#
    .SYNOPSIS
        Static DNS of an adapter, read from the registry: empty NameServer means DHCP.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InterfaceGuid)
    $v4 = Get-UTRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$InterfaceGuid" -Name 'NameServer'
    $v6 = Get-UTRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$InterfaceGuid" -Name 'NameServer'
    $split = { param($text) @(([string]$text) -split '[ ,]' | Where-Object { $_ }) }
    return [pscustomobject]@{
        Ipv4 = @(& $split $v4.Valor)
        Ipv6 = @(& $split $v6.Valor)
    }
}

function Set-UTDnsProvider {
    <#
    .SYNOPSIS
        Sets the DNS of every connected physical adapter to a provider of dns.json (IPv4 and IPv6),
        saving what each adapter had before.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Provedor,
        [Parameter(Mandatory)][string]$TweakId
    )
    $p = (@((Get-UTConfig -Name 'dns').provedores | Where-Object { $_.id -eq $Provedor }) | Select-Object -First 1)
    if ($null -eq $p) { throw "Provedor de DNS '$Provedor' não existe." }
    $adapters = @(Get-UTDnsTargetInterface)
    if ($adapters.Count -eq 0) { throw 'Nenhuma conexão de rede ativa encontrada.' }
    foreach ($a in $adapters) {
        $guid = [string]$a.InterfaceGuid
        $before = Get-UTInterfaceDnsState -InterfaceGuid $guid
        if (-not $PSCmdlet.ShouldProcess($a.Name, "DNS = $($p.nome)")) { continue }
        [void](Save-UTOriginalItem -Chave "dns|$guid" -Dados ([ordered]@{ adaptador = $a.Name; ipv4 = @($before.Ipv4); ipv6 = @($before.Ipv6) }) -TweakId $TweakId)
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses (@($p.ipv4) + @($p.ipv6)) -ErrorAction Stop
        Write-UTLog -Level Info -TweakId $TweakId -Message "DNS de $($a.Name): $($p.nome)."
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Restore-UTDnsProvider {
    <#
    .SYNOPSIS
        Puts back the DNS each adapter had (static servers or DHCP).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    foreach ($entry in @(Get-UTOriginalStateItem)) {
        $item = $entry.Item
        if ($item.tipo -ne 'generico' -or ([string]$item.chave) -notlike 'dns|*' -or @($item.tweaks) -notcontains $TweakId) { continue }
        $guid = ([string]$item.chave).Substring(4)
        $d = Pop-UTOriginalItem -Chave $item.chave -TweakId $TweakId
        if ($d -isnot [System.Collections.IDictionary]) { continue }
        $a = (@(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { [string]$_.InterfaceGuid -eq $guid }) | Select-Object -First 1)
        if ($null -eq $a -or -not $PSCmdlet.ShouldProcess($a.Name, 'Restaurar DNS')) { continue }
        $servers = @(@($d.ipv4) + @($d.ipv6) | Where-Object { $_ })
        if ($servers.Count -eq 0) {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers -ErrorAction Stop
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Test-UTDnsProvider {
    <#
    .SYNOPSIS
        True when every connected adapter uses the provider's IPv4 servers.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Provedor)
    $p = (@((Get-UTConfig -Name 'dns').provedores | Where-Object { $_.id -eq $Provedor }) | Select-Object -First 1)
    $adapters = @(Get-UTDnsTargetInterface)
    if ($null -eq $p -or $adapters.Count -eq 0) { return $false }
    foreach ($a in $adapters) {
        $state = Get-UTInterfaceDnsState -InterfaceGuid ([string]$a.InterfaceGuid)
        if ((@($state.Ipv4) | Select-Object -First 1) -ne (@($p.ipv4) | Select-Object -First 1)) { return $false }
    }
    return $true
}

function Measure-UTDnsProvider {
    <#
    .SYNOPSIS
        Speed test of every provider: ping to the primary server and DNS resolution time.
        Returns the providers sorted from fastest to slowest.
    #>
    [CmdletBinding()]
    param([int]$Tentativas)

    $cfg = Get-UTConfig -Name 'dns'
    if (-not $Tentativas) { $Tentativas = [int]$cfg.teste.tentativas }
    $domain = [string]$cfg.teste.dominio
    $results = foreach ($p in @($cfg.provedores)) {
        $server = (@($p.ipv4) | Select-Object -First 1)
        $ping = Measure-UTPing -Alvo $server -Quantidade $Tentativas
        $times = New-Object System.Collections.Generic.List[double]
        for ($i = 0; $i -lt $Tentativas; $i++) {
            $watch = [Diagnostics.Stopwatch]::StartNew()
            try {
                [void](Resolve-DnsName -Name $domain -Server $server -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop)
                $watch.Stop()
                $times.Add($watch.Elapsed.TotalMilliseconds)
            } catch { $watch.Stop() }
        }
        $resolve = $null
        if ($times.Count -gt 0) { $resolve = [math]::Round(($times | Measure-Object -Average).Average, 1) }
        [pscustomobject]@{
            Id          = $p.id
            Nome        = $p.nome
            PingMs      = $ping.MediaMs
            ResolucaoMs = $resolve
            Perda       = $ping.PerdaPct
            Descricao   = $p.descricao
        }
    }
    return @($results | Sort-Object @{ Expression = { if ($null -eq $_.ResolucaoMs) { [double]::MaxValue } else { $_.ResolucaoMs } } }, PingMs)
}
#endregion

#region Connection info and latency test
function Get-UTNetworkInfo {
    <#
    .SYNOPSIS
        Active connection: adapter, type, speed, IP, gateway and DNS in use.
    #>
    [CmdletBinding()]
    param()
    $config = (@(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }) | Select-Object -First 1)
    if ($null -eq $config) { return $null }
    $adapter = $config.NetAdapter
    return [pscustomobject]@{
        Adaptador  = $adapter.Name
        Descricao  = $adapter.InterfaceDescription
        Tipo       = $(if ($adapter.MediaType -eq '802.3') { 'Cabo (Ethernet)' } elseif ([string]$adapter.InterfaceDescription -match '(?i)wi-?fi|wireless|802\.11') { 'Wi-Fi' } else { [string]$adapter.MediaType })
        Velocidade = [string]$adapter.LinkSpeed
        IPv4       = @($config.IPv4Address | ForEach-Object { $_.IPAddress })
        Gateway    = (@($config.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Select-Object -First 1)
        Dns        = @($config.DNSServer | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
    }
}

function Measure-UTPing {
    <#
    .SYNOPSIS
        Sends -Quantidade pings and returns sent/received, loss %, min/avg/max and jitter (average
        difference between consecutive replies), all in ms.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Alvo,
        [int]$Quantidade = 10,
        [int]$IntervaloMs = 0,
        [int]$TimeoutMs = 1000
    )
    $ping = New-Object System.Net.NetworkInformation.Ping
    $samples = New-Object System.Collections.Generic.List[double]
    try {
        for ($i = 0; $i -lt $Quantidade; $i++) {
            try {
                $reply = $ping.Send($Alvo, $TimeoutMs)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $samples.Add([double]$reply.RoundtripTime) }
            } catch { Write-Verbose "Ping falhou: $($_.Exception.Message)" }
            if ($IntervaloMs -gt 0 -and $i -lt $Quantidade - 1) { Start-Sleep -Milliseconds $IntervaloMs }
        }
    } finally { $ping.Dispose() }
    return (Get-UTLatencyStat -Alvo $Alvo -Enviados $Quantidade -Amostras $samples.ToArray())
}

function Get-UTLatencyStat {
    # Pure statistics, separated so it can be tested without network.
    [CmdletBinding()]
    param(
        [string]$Alvo,
        [Parameter(Mandatory)][int]$Enviados,
        [AllowEmptyCollection()][double[]]$Amostras = @()
    )
    $received = @($Amostras).Count
    $jitter = $null
    if ($received -ge 2) {
        $diffs = for ($i = 1; $i -lt $received; $i++) { [math]::Abs($Amostras[$i] - $Amostras[$i - 1]) }
        $jitter = [math]::Round(($diffs | Measure-Object -Average).Average, 1)
    }
    $stats = $null
    if ($received -gt 0) { $stats = $Amostras | Measure-Object -Minimum -Maximum -Average }
    return [pscustomobject]@{
        Alvo      = $Alvo
        Enviados  = $Enviados
        Recebidos = $received
        PerdaPct  = $(if ($Enviados -gt 0) { [math]::Round(100 * ($Enviados - $received) / $Enviados, 1) } else { 0 })
        MinMs     = $(if ($stats) { $stats.Minimum } else { $null })
        MediaMs   = $(if ($stats) { [math]::Round($stats.Average, 1) } else { $null })
        MaxMs     = $(if ($stats) { $stats.Maximum } else { $null })
        JitterMs  = $jitter
        Amostras  = @($Amostras)
    }
}

function Test-UTNetworkQuality {
    <#
    .SYNOPSIS
        30-second test (default) against the gateway and 1.1.1.1 at the same time, so the user
        sees whether a problem is in the home network (gateway) or beyond it (internet).
    #>
    [CmdletBinding()]
    param([int]$Segundos = 30, [int]$IntervaloMs = 500)
    $info = Get-UTNetworkInfo
    $targets = @('1.1.1.1')
    if ($info -and $info.Gateway) { $targets = @($info.Gateway, '1.1.1.1') }
    $count = [math]::Max(1, [int](($Segundos * 1000) / $IntervaloMs))
    foreach ($t in $targets) {
        $r = Measure-UTPing -Alvo $t -Quantidade $count -IntervaloMs $IntervaloMs
        $r | Add-Member -NotePropertyName Rotulo -NotePropertyValue $(if ($t -eq '1.1.1.1') { 'Internet (1.1.1.1)' } else { "Roteador ($t)" }) -PassThru
    }
}

function Open-UTBufferbloatTest {
    <#
    .SYNOPSIS
        Opens the Waveform bufferbloat test in the browser. Bufferbloat is latency that shoots up
        when the connection is busy (someone downloading); SQM/QoS on the router fixes it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('https://www.waveform.com/tools/bufferbloat', 'Abrir no navegador')) {
        Start-Process 'https://www.waveform.com/tools/bufferbloat'
    }
}
#endregion

#region Repair tools
function Clear-UTDnsCache {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('Cache DNS', 'Limpar')) {
        Clear-DnsClientCache -ErrorAction Stop
        Write-UTLog -Level Sucesso -Message 'Cache DNS limpo.'
    }
}

function Reset-UTNetworkStack {
    <#
    .SYNOPSIS
        netsh winsock reset + netsh int ip reset. Fixes broken network stacks; requires restart
        and resets custom IP settings of the adapters.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess('Winsock e TCP/IP', 'Resetar (exige reiniciar)')) { return }
    $a = Invoke-UTNative -FilePath 'netsh.exe' -ArgumentList @('winsock', 'reset')
    $b = Invoke-UTNative -FilePath 'netsh.exe' -ArgumentList @('int', 'ip', 'reset')
    if ($a.CodigoSaida -ne 0 -and $b.CodigoSaida -ne 0) { throw "O reset de rede falhou: $($a.Saida) $($b.Saida)" }
    Write-UTLog -Level Aviso -Message 'Winsock e TCP/IP resetados. Reinicie o PC para concluir.'
}
#endregion
