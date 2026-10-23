# Monitor tab: real-time sensors (what HWMonitor shows) and the hardware summary (what CPU-Z
# shows). Temperatures per core, voltages and fans of the board, RAM temperature and SPD need
# direct hardware access, so they come from LibreHardwareMonitorLib (open source, MPL-2.0) with the
# signed PawnIO driver (installed through winget). Both are only installed when the user asks.

#region Setup
function Get-UTSensorLibFolder {
    return (Join-Path (Get-UTPath -Name Tools) 'sensores')
}

function Test-UTPawnIO {
    <#
    .SYNOPSIS
        $true when the PawnIO driver service exists (installed).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool](Get-Service -Name 'PawnIO' -ErrorAction SilentlyContinue)
}

function Get-UTSensorSetup {
    <#
    .SYNOPSIS
        What the monitor needs: Driver (PawnIO installed), Biblioteca (path of
        LibreHardwareMonitorLib.dll or $null) and Pronto.
    #>
    [CmdletBinding()]
    param()
    $dll = Join-Path (Get-UTSensorLibFolder) 'LibreHardwareMonitorLib.dll'
    $lib = $(if (Test-Path -LiteralPath $dll) { $dll } else { $null })
    $driver = Test-UTPawnIO
    return [pscustomobject]@{ Driver = $driver; Biblioteca = $lib; Pronto = ($driver -and $lib) }
}

function Install-UTSensorSupport {
    <#
    .SYNOPSIS
        Installs the PawnIO driver (winget namazso.PawnIO) and downloads LibreHardwareMonitorLib
        (the .NET Framework build of the latest GitHub release), when missing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    $setup = Get-UTSensorSetup
    if (-not $setup.Driver -and $PSCmdlet.ShouldProcess('PawnIO (winget namazso.PawnIO)', 'Instalar driver')) {
        $r = Invoke-UTWinget -Argumentos @('install', '--id', 'namazso.PawnIO', '-e', '--silent', '--accept-package-agreements') -TimeoutSeconds 600
        if (-not (Test-UTPawnIO)) { throw "O driver PawnIO não foi instalado. $(Get-UTWingetMessage -Codigo $r.CodigoSaida)" }
        Write-UTLog -Level Sucesso -Message 'Driver de sensores PawnIO instalado.'
    }
    if (-not $setup.Biblioteca -and $PSCmdlet.ShouldProcess('LibreHardwareMonitor (GitHub)', 'Baixar biblioteca de sensores')) {
        $rel = Get-UTGitHubLatestRelease -Repo 'LibreHardwareMonitor/LibreHardwareMonitor'
        # LibreHardwareMonitor.zip is the .NET Framework 4.7.2 build that Windows PowerShell loads.
        $asset = (@($rel.Arquivos | Where-Object { $_.Nome -eq 'LibreHardwareMonitor.zip' }) | Select-Object -First 1)
        if (-not $asset) { throw 'Não encontrei a versão .NET Framework da LibreHardwareMonitor na última Release.' }
        $zip = Join-Path (Get-UTPath -Name Temp) $asset.Nome
        [void](Save-UTDownload -Url $asset.Url -Destino $zip -Confirm:$false)
        $target = Get-UTSensorLibFolder
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Write-UTLog -Level Sucesso -Message "Biblioteca de sensores baixada (LibreHardwareMonitor $($rel.Versao))."
    }
    return (Get-UTSensorSetup)
}
#endregion

#region Background reading
function Get-UTSensorLoopScript {
    <#
    .SYNOPSIS
        Code of the reading thread. Self-contained (only .NET), it opens the hardware once and
        publishes a snapshot in $Sync['Sensores'] every -Intervalo ms (or $Sync['SensoresIntervalo'],
        changed while it runs) until $Sync['SensoresParar']. Disks are read every 5 s at most:
        their SMART data is the slowest part and barely changes.
    #>
    return {
        param($LibDir, $Sync, [int]$Intervalo)
        $computer = $null
        try {
            [void][Reflection.Assembly]::LoadFrom((Join-Path $LibDir 'LibreHardwareMonitorLib.dll'))
            $computer = New-Object LibreHardwareMonitor.Hardware.Computer
            $computer.IsCpuEnabled = $true; $computer.IsGpuEnabled = $true; $computer.IsMemoryEnabled = $true
            $computer.IsMotherboardEnabled = $true; $computer.IsStorageEnabled = $true; $computer.IsControllerEnabled = $true
            $computer.IsPsuEnabled = $true; $computer.IsBatteryEnabled = $true; $computer.IsNetworkEnabled = $false
            $computer.Open()
            $Sync['SensoresEstado'] = 'Rodando'
            $lastDisk = [datetime]::MinValue
            $known = New-Object 'System.Collections.Generic.Dictionary[object,object]'
            while (-not $Sync['SensoresParar']) {
                $started = [datetime]::Now
                $readDisks = (($started - $lastDisk).TotalMilliseconds -ge 5000)
                if ($readDisks) { $lastDisk = $started }
                $reset = [bool]$Sync['SensoresZerar']
                $Sync['SensoresZerar'] = $false
                $rows = New-Object System.Collections.Generic.List[object]
                $queue = New-Object System.Collections.Generic.Queue[object]
                foreach ($h in $computer.Hardware) { $queue.Enqueue(@($h, $null)) }
                while ($queue.Count -gt 0) {
                    $pair = $queue.Dequeue()
                    $hw = $pair[0]
                    if ($readDisks -or [string]$hw.HardwareType -ne 'Storage') { try { $hw.Update() } catch { continue } }
                    foreach ($s in $hw.Sensors) {
                        if ($reset) { $s.ResetMin(); $s.ResetMax() }
                        # One object per sensor for the whole session; each reading only updates the
                        # values (creating hundreds of objects 4 times a second costs CPU).
                        $o = $null
                        if ($known.TryGetValue($s, [ref]$o)) {
                            $o.Valor = $s.Value; $o.Min = $s.Min; $o.Max = $s.Max
                        } else {
                            $o = [pscustomobject]@{
                                Hardware = [string]$hw.Name; HardwareTipo = [string]$hw.HardwareType; Pai = $pair[1]
                                Id = [string]$s.Identifier; Nome = [string]$s.Name; Tipo = [string]$s.SensorType
                                Valor = $s.Value; Min = $s.Min; Max = $s.Max
                            }
                            $known[$s] = $o
                        }
                        $rows.Add($o)
                    }
                    foreach ($sub in $hw.SubHardware) { $queue.Enqueue(@($sub, [string]$hw.Name)) }
                }
                $Sync['Sensores'] = @{ Hora = [datetime]::Now; Itens = $rows.ToArray() }
                $every = $Intervalo
                if ($Sync['SensoresIntervalo']) { $every = [int]$Sync['SensoresIntervalo'] }
                # The wait counts from the start of the reading, so the pace stays steady.
                while (-not $Sync['SensoresParar']) {
                    $left = $every - ([datetime]::Now - $started).TotalMilliseconds
                    if ($left -le 0) { break }
                    Start-Sleep -Milliseconds ([int][math]::Min(100, [math]::Max(1, $left)))
                }
            }
        } catch {
            $Sync['SensoresErro'] = $_.Exception.Message
        } finally {
            if ($computer) { try { $computer.Close() } catch { $null = $_ } }
            $Sync['SensoresEstado'] = 'Parado'
        }
    }
}

function Start-UTSensorMonitor {
    <#
    .SYNOPSIS
        Starts the reading thread (once per session).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateRange(250, 10000)][int]$IntervaloMs = 1000)
    $setup = Get-UTSensorSetup
    if (-not $setup.Pronto) { throw 'Instale o suporte a sensores primeiro (driver PawnIO e biblioteca).' }
    $job = Get-UTSyncValue -Key 'SensoresJob'
    if ($job -and -not $job.Handle.IsCompleted) { return }
    if (-not $PSCmdlet.ShouldProcess('sensores', 'Iniciar leitura')) { return }
    $UTSync['SensoresParar'] = $false
    $UTSync['SensoresErro'] = $null
    $UTSync['SensoresEstado'] = 'Iniciando'
    $UTSync['SensoresIntervalo'] = $IntervaloMs
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript((Get-UTSensorLoopScript).ToString()).AddArgument((Get-UTSensorLibFolder)).AddArgument($UTSync).AddArgument($IntervaloMs)
    $UTSync['SensoresJob'] = @{ PowerShell = $ps; Runspace = $rs; Handle = $ps.BeginInvoke() }
    Write-UTLog -Level Info -Message 'Leitura dos sensores iniciada.'
}

function Stop-UTSensorMonitor {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $job = Get-UTSyncValue -Key 'SensoresJob'
    if ($null -eq $job) { return }
    if (-not $PSCmdlet.ShouldProcess('sensores', 'Parar leitura')) { return }
    $UTSync['SensoresParar'] = $true
    $deadline = (Get-Date).AddSeconds(5)
    while (-not $job.Handle.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    try { if ($job.Handle.IsCompleted) { [void]$job.PowerShell.EndInvoke($job.Handle) } else { $job.PowerShell.Stop() } } catch { $null = $_ }
    $job.PowerShell.Dispose()
    $job.Runspace.Dispose()
    $UTSync['SensoresJob'] = $null
}
#endregion

#region Snapshot formatting
function Get-UTSensorGroupName {
    param([string]$HardwareTipo)
    switch -Regex ($HardwareTipo) {
        '^(Motherboard|SuperIO|EmbeddedController)$' { 'Placa-mãe' }
        '^Cpu$' { 'Processador' }
        '^Memory$' { 'Memória' }
        '^Gpu' { 'Placa de vídeo' }
        '^Storage$' { 'Discos' }
        '^(Cooler)$' { 'Refrigeração' }
        '^Psu$' { 'Fonte' }
        '^Battery$' { 'Bateria' }
        default { 'Outros' }
    }
}

function Format-UTSensorValue {
    # Value with unit in Brazilian format; $null -> '-'. -Unidade F shows temperatures in
    # Fahrenheit; -Casas is the number of decimals of temperatures, usage and power.
    param([AllowNull()][object]$Valor, [string]$Tipo, [ValidateSet('C', 'F')][string]$Unidade = 'C', [ValidateRange(0, 2)][int]$Casas = 1)
    if ($null -eq $Valor) { return '-' }
    $v = [double]$Valor
    $ci = [Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    $fmt = $(if ($Casas -eq 0) { '0' } else { '0.' + ('0' * $Casas) })
    switch ($Tipo) {
        'Voltage' { return $v.ToString('0.000', $ci) + ' V' }
        'Current' { return $v.ToString('0.00', $ci) + ' A' }
        'Power' { return $v.ToString($fmt, $ci) + ' W' }
        'Clock' { return $v.ToString('0', $ci) + ' MHz' }
        'Temperature' {
            if ($Unidade -eq 'F') { return ($v * 9 / 5 + 32).ToString($fmt, $ci) + ' °F' }
            return $v.ToString($fmt, $ci) + ' °C'
        }
        'Load' { return $v.ToString($fmt, $ci) + ' %' }
        'Control' { return $v.ToString('0', $ci) + ' %' }
        'Level' { return $v.ToString('0', $ci) + ' %' }
        'Humidity' { return $v.ToString('0', $ci) + ' %' }
        'Fan' { return $v.ToString('0', $ci) + ' RPM' }
        'Flow' { return $v.ToString('0', $ci) + ' L/h' }
        'Frequency' { return $v.ToString('0', $ci) + ' Hz' }
        'Data' { return $v.ToString('0.00', $ci) + ' GB' }
        'SmallData' { return $v.ToString('0', $ci) + ' MB' }
        'Throughput' { return ($v / 1MB).ToString('0.0', $ci) + ' MB/s' }
        'Timing' { return $v.ToString('0.00', $ci) + ' ns' }
        'Energy' { return $v.ToString('0', $ci) + ' mWh' }
        'Noise' { return $v.ToString('0', $ci) + ' dBA' }
        default { return $v.ToString('0.##', $ci) }
    }
}

function Get-UTSensorDecimal {
    # Decimals Format-UTSensorValue shows for a sensor type.
    param([string]$Tipo, [int]$Casas = 1)
    switch ($Tipo) {
        'Voltage' { 3 } 'Current' { 2 } 'Data' { 2 } 'Timing' { 2 } 'Factor' { 2 }
        'Temperature' { $Casas } 'Load' { $Casas } 'Power' { $Casas }
        default { 0 }
    }
}

function Get-UTSensorTypeName {
    param([string]$Tipo)
    $names = @{ Voltage = 'Tensões'; Current = 'Correntes'; Power = 'Consumo'; Clock = 'Clocks'; Temperature = 'Temperaturas'; Load = 'Uso'
        Control = 'Controle das ventoinhas'; Level = 'Níveis'; Fan = 'Ventoinhas'; Flow = 'Fluxo'; Frequency = 'Frequências'; Data = 'Dados'
        SmallData = 'Memória'; Throughput = 'Taxa de transferência'; Timing = 'Timings (SPD)'; Factor = 'Multiplicadores e contadores'; Energy = 'Energia'; Noise = 'Ruído'; Humidity = 'Umidade'
    }
    if ($names.ContainsKey($Tipo)) { return $names[$Tipo] }
    return $Tipo
}

function ConvertTo-UTSensorRow {
    <#
    .SYNOPSIS
        Turns the raw snapshot of the reading thread into the rows of the tab: Portuguese group,
        type and sensor names, board labels and multipliers (sensores-placas.json), and the
        values formatted. Fans that never turned and sensors with no reading are left out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Itens,
        [string]$Placa,
        [ValidateSet('C', 'F')][string]$Unidade = 'C',
        [ValidateRange(0, 2)][int]$Casas = 1,
        # Without the formatted texts (Atual/Minimo/Maximo): the Monitor formats only what it shows.
        [switch]$SemTexto,
        # Only these sensor ids (the Monitor between two full readings).
        [System.Collections.Generic.HashSet[string]]$Ids
    )
    $cfg = Get-UTConfig -Name 'sensores-placas'
    # Names, groups and multipliers never change for a sensor: worked out once per session and
    # kept by sensor id, so each reading (up to 4 per second) only copies the values.
    $cacheKey = "$Placa|$([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($cfg))"
    $cache = Get-UTSyncValue -Key 'SensoresMeta'
    if ($null -eq $cache -or $cache.Chave -ne $cacheKey) {
        $cache = @{ Chave = $cacheKey; Itens = [hashtable]::Synchronized(@{}) }
        if (Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue) { $UTSync['SensoresMeta'] = $cache }
    }
    $meta = $cache.Itens
    $tr = $cfg.traducoes
    $board = $null
    if ($Placa) { $board = (@($cfg.placas | Where-Object { $Placa -match $_.padrao }) | Select-Object -First 1) }
    # Order inside each device, like HWMonitor: temperatures first, then voltages, power...
    $rank = @{ Temperature = 1; Voltage = 2; Current = 3; Power = 4; Clock = 5; Load = 6; Fan = 7; Control = 8; Flow = 9; Level = 10; Factor = 11; Data = 12; SmallData = 13; Throughput = 14; Timing = 15 }
    $index = 0
    foreach ($s in $Itens) {
        $index++
        if ($null -eq $s.Valor -and $null -eq $s.Max) { continue }
        if ($s.Tipo -eq 'Fan' -and ($null -eq $s.Max -or [double]$s.Max -le 0)) { continue }
        if ($s.Tipo -eq 'Control' -and $null -eq $s.Valor) { continue }
        $id = [string]$s.Id
        if ($null -ne $Ids -and -not $Ids.Contains($id)) { continue }
        $m = $meta[$id]
        if ($null -eq $m) {
            # Fixed limits of the DIMM thermal sensor and the 3DS timings (always 0) are noise.
            $skip = ($s.HardwareTipo -eq 'Memory' -and $s.Nome -match 'Resolution|Limit|_dlr')
            $name = [string]$s.Nome
            $factor = 1.0
            if ($board -and $s.HardwareTipo -eq 'SuperIO' -and $s.Hardware -match $board.chip -and $board.sensores.Contains($name)) {
                $label = $board.sensores[$name]
                $name = [string]$label.nome
                $f = Get-UTField -Objeto $label -Nome 'fator'
                if ($null -ne $f) { $factor = [double]$f }
            } elseif ($tr.Contains("$($s.Tipo)|$name")) {
                $name = [string]$tr["$($s.Tipo)|$name"]
            } elseif ($tr.Contains($name)) {
                $name = [string]$tr[$name]
            }
            $hwName = ([string]$s.Hardware -replace '[^ -~ -ɏ]', '').Trim()
            $devices = Get-UTField -Objeto $cfg -Nome 'dispositivos' -Padrao @{}
            if ($devices.Contains($hwName)) { $hwName = [string]$devices[$hwName] }
            if ($s.HardwareTipo -eq 'Memory' -and $hwName -match '\?|\s{3,}') { $hwName = 'Pente de memória ' + ([regex]::Match($hwName, '\(#\d+\)')).Value }
            $r = 99
            if ($rank.ContainsKey([string]$s.Tipo)) { $r = $rank[[string]$s.Tipo] }
            $m = @{
                Ignorar = $skip; Fator = $factor; Ordem = $r * 100000 + $index; Grupo = Get-UTSensorGroupName ([string]$s.HardwareTipo)
                Hardware = $(if ($s.Pai) { "$($s.Pai) · $hwName" } else { $hwName }); Tipo = Get-UTSensorTypeName ([string]$s.Tipo); Sensor = $name
            }
            $meta[$id] = $m
        }
        if ($m.Ignorar) { continue }
        $factor = $m.Fator
        $now = $(if ($null -eq $s.Valor) { $null } else { [double]$s.Valor * $factor })
        $low = $(if ($null -eq $s.Min) { $null } else { [double]$s.Min * $factor })
        $high = $(if ($null -eq $s.Max) { $null } else { [double]$s.Max * $factor })
        if ($SemTexto -and $m.Contains('Linha')) {
            # The Monitor asks several times a second: same row object, new values.
            $row = $m.Linha
            $row.Valor = $now; $row.MinValor = $low; $row.MaxValor = $high
            $row
            continue
        }
        $row = [pscustomobject]@{
            Id = $id; Ordem = $m.Ordem; Grupo = $m.Grupo; Hardware = $m.Hardware; HardwareNome = [string]$s.Hardware; HardwareTipo = [string]$s.HardwareTipo
            Tipo = $m.Tipo; TipoOriginal = [string]$s.Tipo; Sensor = $m.Sensor; NomeOriginal = [string]$s.Nome
            Valor = $now; MinValor = $low; MaxValor = $high; Atual = $null; Minimo = $null; Maximo = $null
        }
        if ($SemTexto) { $m['Linha'] = $row }
        if (-not $SemTexto) {
            $row.Atual = Format-UTSensorValue -Valor $now -Tipo $row.TipoOriginal -Unidade $Unidade -Casas $Casas
            $row.Minimo = Format-UTSensorValue -Valor $low -Tipo $row.TipoOriginal -Unidade $Unidade -Casas $Casas
            $row.Maximo = Format-UTSensorValue -Valor $high -Tipo $row.TipoOriginal -Unidade $Unidade -Casas $Casas
        }
        $row
    }
}
function Get-UTSensorSnapshot {
    <#
    .SYNOPSIS
        Last reading of the sensors, formatted (empty before the first reading).
    #>
    [CmdletBinding()]
    param([ValidateSet('C', 'F')][string]$Unidade = 'C', [ValidateRange(0, 2)][int]$Casas = 1, [switch]$SemTexto, [System.Collections.Generic.HashSet[string]]$Ids)
    $snap = Get-UTSyncValue -Key 'Sensores'
    if ($null -eq $snap) { return @() }
    $board = Get-UTSyncValue -Key 'SensoresPlaca'
    if ($null -eq $board) {
        $board = [string]((@(Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue) | Select-Object -First 1).Product)
        $UTSync['SensoresPlaca'] = $board
    }
    return @(ConvertTo-UTSensorRow -Itens @($snap.Itens) -Placa $board -Unidade $Unidade -Casas $Casas -SemTexto:$SemTexto -Ids $Ids)
}

function Set-UTSensorInterval {
    <#
    .SYNOPSIS
        Time between readings of the running monitor (250 ms to 2 s), effective on the next one.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateRange(250, 2000)][int]$IntervaloMs)
    if ($PSCmdlet.ShouldProcess('sensores', "Ler a cada $IntervaloMs ms")) { $UTSync['SensoresIntervalo'] = $IntervaloMs }
}

function Export-UTSensorReport {
    <#
    .SYNOPSIS
        Text file with the hardware summary and every sensor (current, minimum, maximum), like
        the "Save monitoring data" of HWMonitor.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Upgrade Tweaks - Monitor de hardware - $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))")
    $lines.Add('')
    $spec = Get-UTSystemSpec
    foreach ($section in $spec) {
        $lines.Add("== $($section.Titulo)")
        foreach ($p in $section.Itens) { $lines.Add(('  {0,-28} {1}' -f $p[0], $p[1])) }
        $lines.Add('')
    }
    $rows = @(Get-UTSensorSnapshot)
    foreach ($g in @(Group-UTInOrder -Itens $rows -Chave { param($r) $r.Hardware })) {
        $lines.Add("== $($g.Name)")
        foreach ($r in $g.Group) { $lines.Add(('  {0,-34} {1,14} {2,14} {3,14}' -f $r.Sensor, $r.Atual, $r.Minimo, $r.Maximo)) }
        $lines.Add('')
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Salvar relatório')) {
        [IO.File]::WriteAllLines($Path, $lines.ToArray(), (New-Object Text.UTF8Encoding($true)))
    }
    return $Path
}
#endregion

#region Hardware summary (CPU-Z)
function Initialize-UTCpuFeatureType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.CpuFeature' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace UpgradeTweaks {
    public static class CpuFeature {
        [DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int feature);
    }
}
'@
}

function Get-UTCpuCodename {
    # Codename from family/model (CPUID), for the processors a gaming PC has today.
    param([string]$Fabricante, [int]$Familia, [int]$Modelo)
    $amd = @{ '23|113' = 'Matisse (Zen 2)'; '23|96' = 'Renoir (Zen 2)'; '25|33' = 'Vermeer (Zen 3)'; '25|80' = 'Cezanne (Zen 3)'; '25|97' = 'Raphael (Zen 4)'
        '25|116' = 'Phoenix (Zen 4)'; '25|117' = 'Phoenix (Zen 4)'; '25|120' = 'Phoenix 2 (Zen 4)'; '26|68' = 'Granite Ridge (Zen 5)'; '26|36' = 'Strix Point (Zen 5)'; '26|96' = 'Krackan Point (Zen 5)'
    }
    $intel = @{ '6|165' = 'Comet Lake'; '6|167' = 'Rocket Lake'; '6|151' = 'Alder Lake'; '6|154' = 'Alder Lake'; '6|183' = 'Raptor Lake'; '6|186' = 'Raptor Lake'; '6|191' = 'Raptor Lake'
        '6|170' = 'Meteor Lake'; '6|198' = 'Arrow Lake'; '6|189' = 'Lunar Lake'
    }
    $key = "$Familia|$Modelo"
    if ($Fabricante -eq 'amd' -and $amd.ContainsKey($key)) { return $amd[$key] }
    if ($Fabricante -eq 'intel' -and $intel.ContainsKey($key)) { return $intel[$key] }
    return ''
}

function Get-UTSystemSpec {
    <#
    .SYNOPSIS
        Hardware summary in sections (Processador, Placa-mãe, Memória, pentes, Placa de vídeo),
        each with label/value pairs. Uses Windows (CIM, registry, CPU features) and, when the
        monitor is running, the SPD timings of the memory modules.
    #>
    [CmdletBinding()]
    param()
    $sections = New-Object System.Collections.Generic.List[object]
    $cpu = (@(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1)
    $reg = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue
    if ($cpu) {
        $vendor = $(if ($cpu.Manufacturer -match 'AMD') { 'amd' } elseif ($cpu.Manufacturer -match 'Intel') { 'intel' } else { '' })
        $fam = 0; $model = 0; $step = 0
        if ($reg) {
            $m = [regex]::Match([string]$reg.Identifier, 'Family (\d+) Model (\d+) Stepping (\d+)')
            if ($m.Success) { $fam = [int]$m.Groups[1].Value; $model = [int]$m.Groups[2].Value; $step = [int]$m.Groups[3].Value }
        }
        $micro = ''
        if ($reg -and $reg.PSObject.Properties['Update Revision']) {
            # AMD: 4 bytes; Intel: 8 bytes with the revision in the high half.
            $bytes = [byte[]]$reg.'Update Revision'
            $rev = 0
            if ($bytes.Length -ge 8) { $rev = [BitConverter]::ToUInt32($bytes, 4) }
            if ($rev -eq 0 -and $bytes.Length -ge 4) { $rev = [BitConverter]::ToUInt32($bytes, 0) }
            if ($rev -ne 0) { $micro = '0x{0:X}' -f $rev }
        }
        Initialize-UTCpuFeatureType
        $features = @()
        foreach ($f in @(@(13, 'SSE3'), @(36, 'SSSE3'), @(37, 'SSE4.1'), @(38, 'SSE4.2'), @(39, 'AVX'), @(40, 'AVX2'), @(41, 'AVX-512'), @(28, 'RDRAND'), @(12, 'NX'))) {
            if ([UpgradeTweaks.CpuFeature]::IsProcessorFeaturePresent($f[0])) { $features += $f[1] }
        }
        $sections.Add([pscustomobject]@{ Titulo = 'Processador'; Itens = @(
                    , @('Nome', (([string]$cpu.Name).Trim() -replace '\s{2,}', ' '))
                    , @('Codinome', (Get-UTCpuCodename -Fabricante $vendor -Familia $fam -Modelo $model))
                    , @('Soquete', [string]$cpu.SocketDesignation)
                    , @('Núcleos / threads', "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)")
                    , @('Família / modelo / stepping', ('{0:X} / {1:X} / {2:X}' -f $fam, $model, $step))
                    , @('Clock base', "$($cpu.MaxClockSpeed) MHz")
                    , @('Cache L2 / L3', ('{0:N0} KB / {1:N0} MB' -f $cpu.L2CacheSize, ([double]$cpu.L3CacheSize / 1024)))
                    , @('Microcódigo', $micro)
                    , @('Instruções', ($features -join ', '))
                    , @('Virtualização na BIOS', $(if ($cpu.VirtualizationFirmwareEnabled -or (Get-CimInstance -ClassName Win32_ComputerSystem).HypervisorPresent) { 'Ligada' } else { 'Desligada' }))
                ) })
    }

    $info = Get-UTBiosInfo
    $sections.Add([pscustomobject]@{ Titulo = 'Placa-mãe'; Itens = @(
                , @('Fabricante', $info.Fabricante)
                , @('Modelo', $info.Placa)
                , @('BIOS', ("{0} {1} ({2})" -f $info.BiosMarca, $info.BiosVersao, $info.BiosData))
                , @('Modo de boot', $(if ($info.Uefi) { 'UEFI' } else { 'Legacy (CSM)' }))
                , @('Secure Boot', $(if ($info.SecureBoot) { 'Ligado' } elseif ($null -eq $info.SecureBoot) { 'Desconhecido' } else { 'Desligado' }))
            ) })

    $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    if ($modules.Count -gt 0) {
        $types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
        $first = $modules[0]
        $type = $(if ($types.ContainsKey([int]$first.SMBIOSMemoryType)) { $types[[int]$first.SMBIOSMemoryType] } else { '' })
        $speed = [int]$first.ConfiguredClockSpeed
        $total = [math]::Round((Get-UTSum @($modules | ForEach-Object { [double]$_.Capacity })) / 1GB, 0)
        $pairs = @(
            , @('Tipo', $type)
            , @('Total', "$total GB em $($modules.Count) pente(s)")
            , @('Velocidade', "$speed MT/s (clock real $([math]::Round($speed / 2)) MHz)")
            , @('Máximo dos pentes', "$($first.Speed) MT/s")
        )
        if ($first.ConfiguredVoltage) { $pairs += , @('Tensão', ('{0:N2} V' -f ([double]$first.ConfiguredVoltage / 1000))) }
        $timings = Get-UTSpdTiming -VelocidadeMTs $speed
        if ($timings) { $pairs += , @('Timings do SPD (CL-tRCD-tRP-tRAS-tRC)', $timings) }
        $sections.Add([pscustomobject]@{ Titulo = 'Memória'; Itens = $pairs })
        $slots = foreach ($m in $modules) {
            , @(("{0} {1}" -f $m.BankLabel, $m.DeviceLocator).Trim(), ("{0} {1} · {2} GB · {3} MT/s" -f ([string]$m.Manufacturer).Trim(), ([string]$m.PartNumber).Trim(), [math]::Round([double]$m.Capacity / 1GB), $m.Speed))
        }
        $sections.Add([pscustomobject]@{ Titulo = 'Pentes de memória'; Itens = @($slots) })
    }

    $gpus = @()
    try { $gpus = @(Get-UTGpuInfo) } catch { $gpus = @() }
    if ($gpus.Count -gt 0) {
        $items = foreach ($g in $gpus) {
            $kind = ''
            if ($g.Integrada) { $kind = ' · integrada' }
            , @([string]$g.Nome, ("Driver {0} · {1} GB de VRAM{2}" -f $g.DriverAmigavel, $g.VramGB, $kind))
        }
        $sections.Add([pscustomobject]@{ Titulo = 'Placa de vídeo'; Itens = @($items) })
    }
    return $sections.ToArray()
}

function Get-UTSpdTiming {
    <#
    .SYNOPSIS
        Base timings of the first memory module in clock cycles at -VelocidadeMTs, from the SPD
        minimums the monitor reads (ns). $null when the monitor is not running.
    #>
    [CmdletBinding()]
    param([int]$VelocidadeMTs)
    $snap = Get-UTSyncValue -Key 'Sensores'
    if ($null -eq $snap -or $VelocidadeMTs -le 0) { return $null }
    $dimm = @($snap.Itens | Where-Object { $_.HardwareTipo -eq 'Memory' -and $_.Tipo -eq 'Timing' })
    if ($dimm.Count -eq 0) { return $null }
    $firstHw = $dimm[0].Hardware
    $tck = 2000.0 / $VelocidadeMTs
    $get = {
        param($prefix)
        $s = (@($dimm | Where-Object { $_.Hardware -eq $firstHw -and $_.Nome -like "$prefix *" }) | Select-Object -First 1)
        if ($null -eq $s -or $null -eq $s.Valor) { return $null }
        return [int][math]::Ceiling([double]$s.Valor / $tck - 0.01)
    }
    $cl = & $get 'tAA'
    # DDR5 only runs even CAS latencies.
    if ($null -ne $cl -and $VelocidadeMTs -ge 4000 -and $cl % 2 -eq 1) { $cl++ }
    $parts = @($cl, (& $get 'tRCD'), (& $get 'tRP'), (& $get 'tRAS'), (& $get 'tRC')) | ForEach-Object { if ($null -eq $_) { '?' } else { [string]$_ } }
    return (($parts -join '-') + ' (aprox.)')
}
#endregion
