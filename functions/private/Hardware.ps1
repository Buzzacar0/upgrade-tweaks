# Hardware collectors for the "Início" tab. Every collector only reads; each one is called
# through Invoke-UTCollector so a failure in one area never breaks the whole diagnostic.

function Invoke-UTCollector {
    <#
    .SYNOPSIS
        Runs one collector; on error logs it, records it in -Erros and returns $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][scriptblock]$Coletor,
        [System.Collections.Generic.List[string]]$Erros
    )
    try {
        return (& $Coletor)
    } catch {
        Write-UTLog -Level Aviso -Message "Não foi possível ler: $Nome." -Detalhe $_.Exception.Message
        if ($null -ne $Erros) { $Erros.Add("${Nome}: $($_.Exception.Message)") }
        return $null
    }
}

function Get-UTCpuInfo {
    [CmdletBinding()]
    param()

    $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)[0]
    $name = ([string]$cpu.Name).Trim() -replace '\s{2,}', ' '
    $vendor = 'desconhecido'
    if ($cpu.Manufacturer -match 'AMD' -or $name -match '\bAMD\b') { $vendor = 'amd' }
    elseif ($cpu.Manufacturer -match 'Intel' -or $name -match '\bIntel\b') { $vendor = 'intel' }

    return [pscustomobject]@{
        Fabricante = $vendor
        Nome       = $name
        Nucleos    = [int]$cpu.NumberOfCores
        Threads    = [int]$cpu.NumberOfLogicalProcessors
        X3D        = (Get-UTX3DInfo -Nome $name -Nucleos ([int]$cpu.NumberOfCores))
    }
}

function ConvertTo-UTNvidiaDriverVersion {
    <#
    .SYNOPSIS
        Windows driver version (32.0.16.1742) -> NVIDIA version (617.42): the last five digits
        of the two last fields.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$WindowsVersion)

    $parts = $WindowsVersion.Split('.')
    if ($parts.Count -lt 4) { return $WindowsVersion }
    $digits = ($parts[2] + $parts[3].PadLeft(4, '0'))
    if ($digits.Length -lt 5) { return $WindowsVersion }
    $last5 = $digits.Substring($digits.Length - 5)
    return ('{0}.{1}' -f [int]$last5.Substring(0, 3), $last5.Substring(3))
}

function Get-UTDisplayAdapterRegistry {
    <#
    .SYNOPSIS
        The display class keys ({4d36e968-...}\00XX): driver description, PnP id and real VRAM
        (HardwareInformation.qwMemorySize; Win32_VideoController.AdapterRAM stops at 4 GB).
    #>
    [CmdletBinding()]
    param()

    $classPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $base = Open-UTRegistryKey -Path $classPath
    if ($null -eq $base) { return @() }
    try {
        $names = @($base.GetSubKeyNames() | Where-Object { $_ -match '^\d{4}$' })
    } finally { $base.Dispose() }

    foreach ($n in $names) {
        $path = "$classPath\$n"
        $desc = Get-UTRegistryValue -Path $path -Name 'DriverDesc'
        if (-not $desc.ValorExiste) { continue }
        $vram = Get-UTRegistryValue -Path $path -Name 'HardwareInformation.qwMemorySize'
        $match = Get-UTRegistryValue -Path $path -Name 'MatchingDeviceId'
        [pscustomobject]@{
            Chave            = $path
            Nome             = [string]$desc.Valor
            MatchingDeviceId = [string]$match.Valor
            VramBytes        = $(if ($vram.ValorExiste) { [double]$vram.Valor } else { $null })
        }
    }
}

function Get-UTGpuInfo {
    [CmdletBinding()]
    param([datetime]$Hoje = (Get-Date))

    $registry = @(Get-UTDisplayAdapterRegistry)
    $controllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
        Where-Object { [string]$_.PNPDeviceID -like 'PCI\*' })

    foreach ($c in $controllers) {
        $pnp = [string]$c.PNPDeviceID
        $vendor = 'outro'
        if ($pnp -match 'VEN_10DE') { $vendor = 'nvidia' }
        elseif ($pnp -match 'VEN_1002') { $vendor = 'amd' }
        elseif ($pnp -match 'VEN_8086') { $vendor = 'intel' }

        $driverDate = $null
        if ($c.DriverDate) { $driverDate = [datetime]$c.DriverDate }
        $friendly = [string]$c.DriverVersion
        if ($vendor -eq 'nvidia') { $friendly = ConvertTo-UTNvidiaDriverVersion -WindowsVersion ([string]$c.DriverVersion) }

        $reg = $registry | Where-Object { $_.Nome -eq $c.Name } | Select-Object -First 1
        $vramGb = $null
        if ($reg -and $reg.VramBytes) { $vramGb = [math]::Round($reg.VramBytes / 1GB, 1) }

        # Integrated GPUs share system memory; AMD/Intel iGPUs usually report under 4 GB of
        # dedicated memory, and AMD's iGPU name is the generic "AMD Radeon(TM) Graphics".
        $integrated = ($vendor -eq 'intel' -and [string]$c.Name -notmatch '\bArc\b') -or
            ($vendor -eq 'amd' -and [string]$c.Name -match '^AMD Radeon\(TM\)( \w+)? Graphics$')

        [pscustomobject]@{
            Fabricante     = $vendor
            Nome           = [string]$c.Name
            PnpId          = $pnp
            DriverVersao   = [string]$c.DriverVersion
            DriverAmigavel = $friendly
            DriverData     = $driverDate
            DiasDriver     = $(if ($driverDate) { [int]($Hoje - $driverDate).TotalDays } else { $null })
            VramGB         = $vramGb
            Integrada      = [bool]$integrated
            ChaveRegistro  = $(if ($reg) { $reg.Chave } else { $null })
        }
    }
}

function Get-UTPartNumberSpeed {
    <#
    .SYNOPSIS
        Rated speed hinted by a memory part number (AX5U5600C468G -> 5600, F5-6000J3038F16G -> 6000,
        CMK32GX5M2B6000C36 -> 6000, KF560C36BBE -> 6000). $null when nothing plausible is found.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$PartNumber)

    if ([string]::IsNullOrWhiteSpace($PartNumber)) { return $null }
    $pn = $PartNumber.Trim().ToUpperInvariant()
    $candidates = @([regex]::Matches($pn, '(?<!\d)(\d{4})(?!\d)') | ForEach-Object { [int]$_.Groups[1].Value } |
        Where-Object { $_ -ge 2133 -and $_ -le 9600 })
    if ($candidates.Count -gt 0) { return ($candidates | Measure-Object -Maximum).Maximum }
    # Kingston FURY: KF + generation digit + speed/100 (KF556 = DDR5 5600, KF432 = DDR4 3200)
    $k = [regex]::Match($pn, '^KF[345](\d{2})C')
    if ($k.Success) { return ([int]$k.Groups[1].Value * 100) }
    return $null
}

function Get-UTMemoryInfo {
    [CmdletBinding()]
    param()

    $modules = foreach ($m in @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)) {
        $type = switch ([int]$m.SMBIOSMemoryType) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } 35 { 'LPDDR5' } 30 { 'LPDDR4' } default { 'Desconhecido' } }
        $label = ('{0} {1}' -f $m.BankLabel, $m.DeviceLocator)
        $channel = $null
        $cm = [regex]::Match($label, '(?i)CHANNEL\s*([A-H])|DIMM_?([A-H])\d|\bChannel([A-H])|\b([A-H])\d\b')
        if ($cm.Success) { $channel = (@($cm.Groups[1].Value, $cm.Groups[2].Value, $cm.Groups[3].Value, $cm.Groups[4].Value) | Where-Object { $_ } | Select-Object -First 1).ToUpperInvariant() }
        [pscustomobject]@{
            CapacidadeGB  = [math]::Round([double]$m.Capacity / 1GB, 1)
            Nominal       = [int]$m.Speed
            Configurada   = [int]$m.ConfiguredClockSpeed
            Tipo          = $type
            PartNumber    = ([string]$m.PartNumber).Trim()
            PartNumberMTs = (Get-UTPartNumberSpeed -PartNumber ([string]$m.PartNumber))
            Fabricante    = ([string]$m.Manufacturer).Trim()
            Slot          = $label.Trim()
            Canal         = $channel
        }
    }
    $modules = @($modules)
    return [pscustomobject]@{
        TotalGB = [math]::Round((($modules | Measure-Object CapacidadeGB -Sum).Sum), 1)
        Modulos = $modules
    }
}

function Get-UTStorageInfo {
    [CmdletBinding()]
    param()

    $disks = foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
        $bus = [string]$d.BusType
        $media = [string]$d.MediaType
        $kind = 'Desconhecido'
        if ($bus -eq 'NVMe') { $kind = 'NVMe' }
        elseif ($media -eq 'SSD') { $kind = 'SSD' }
        elseif ($media -eq 'HDD') { $kind = 'HDD' }
        [pscustomobject]@{
            Numero     = [int]$d.DeviceId
            Nome       = ([string]$d.FriendlyName).Trim()
            Tipo       = $kind
            Barramento = $bus
            TamanhoGB  = [math]::Round([double]$d.Size / 1GB)
        }
    }

    $volumes = foreach ($p in @(Get-Partition -ErrorAction Stop | Where-Object { $_.DriveLetter -and [char]$_.DriveLetter -ne [char]0 })) {
        $letter = [string]$p.DriveLetter
        $info = New-Object System.IO.DriveInfo ($letter + ':')
        if (-not $info.IsReady) { continue }
        [pscustomobject]@{
            Letra   = $letter
            Disco   = [int]$p.DiskNumber
            TotalGB = [math]::Round($info.TotalSize / 1GB)
            LivreGB = [math]::Round($info.AvailableFreeSpace / 1GB)
        }
    }

    $trim = $null
    $r = Invoke-UTNative -FilePath 'fsutil.exe' -ArgumentList @('behavior', 'query', 'DisableDeleteNotify')
    $tm = [regex]::Match($r.Saida, 'NTFS\s+DisableDeleteNotify\s*=\s*(\d)')
    if ($r.CodigoSaida -eq 0 -and $tm.Success) { $trim = ($tm.Groups[1].Value -eq '0') }

    return [pscustomobject]@{ Discos = @($disks); Volumes = @($volumes); TrimAtivo = $trim }
}

function Get-UTDriveOfPath {
    <#
    .SYNOPSIS
        Volume and physical disk that hold -Path, using the storage info already collected.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][psobject]$Armazenamento
    )
    $letter = ([IO.Path]::GetPathRoot($Path)).TrimEnd(':\').ToUpperInvariant()
    $volume = @($Armazenamento.Volumes | Where-Object { $_.Letra -eq $letter })[0]
    if ($null -eq $volume) { return $null }
    $disk = @($Armazenamento.Discos | Where-Object { $_.Numero -eq $volume.Disco })[0]
    return [pscustomobject]@{
        Letra     = $letter
        LivreGB   = $volume.LivreGB
        TotalGB   = $volume.TotalGB
        TipoDisco = $(if ($disk) { $disk.Tipo } else { 'Desconhecido' })
        NomeDisco = $(if ($disk) { $disk.Nome } else { '' })
    }
}

function Initialize-UTDisplayType {
    # user32 EnumDisplayDevices/EnumDisplaySettings: the only reliable source for the current and
    # maximum refresh rate of each monitor (WMI reports one value per GPU).
    if ('UpgradeTweaks.Display' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace UpgradeTweaks {
    public class MonitorMode {
        public string Device; public string Name; public string MonitorId; public bool Primary;
        public int Width; public int Height; public int Hz; public int MaxHzAtResolution; public int MaxHzAny;
    }
    public static class Display {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DISPLAY_DEVICE {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
            public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
            public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
            public int dmDisplayFlags; public int dmDisplayFrequency;
            public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
            public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
        const int ENUM_CURRENT_SETTINGS = -1;
        const int ATTACHED_TO_DESKTOP = 1;
        const int PRIMARY_DEVICE = 4;

        public static List<MonitorMode> GetMonitors() {
            var list = new List<MonitorMode>();
            for (uint i = 0; ; i++) {
                var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
                if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
                if ((dd.StateFlags & ATTACHED_TO_DESKTOP) == 0) continue;
                var cur = new DEVMODE(); cur.dmSize = (short)Marshal.SizeOf(cur);
                if (!EnumDisplaySettings(dd.DeviceName, ENUM_CURRENT_SETTINGS, ref cur)) continue;
                var m = new MonitorMode();
                m.Device = dd.DeviceName; m.Primary = (dd.StateFlags & PRIMARY_DEVICE) != 0;
                m.Width = cur.dmPelsWidth; m.Height = cur.dmPelsHeight; m.Hz = cur.dmDisplayFrequency;
                var mon = new DISPLAY_DEVICE(); mon.cb = Marshal.SizeOf(mon);
                if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0)) { m.Name = mon.DeviceString; m.MonitorId = mon.DeviceID; } else { m.Name = dd.DeviceString; }
                for (int n = 0; ; n++) {
                    var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
                    if (!EnumDisplaySettings(dd.DeviceName, n, ref dm)) break;
                    if (dm.dmDisplayFrequency > m.MaxHzAny) m.MaxHzAny = dm.dmDisplayFrequency;
                    if (dm.dmPelsWidth == m.Width && dm.dmPelsHeight == m.Height && dm.dmDisplayFrequency > m.MaxHzAtResolution)
                        m.MaxHzAtResolution = dm.dmDisplayFrequency;
                }
                list.Add(m);
            }
            return list;
        }
    }
}
'@
}

function Get-UTDisplayInfo {
    [CmdletBinding()]
    param()
    Initialize-UTDisplayType
    # Real model names come from the EDID (WmiMonitorID); user32 only says "Generic PnP Monitor".
    $edid = @(Get-CimInstance -Namespace 'root/wmi' -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    foreach ($m in [UpgradeTweaks.Display]::GetMonitors()) {
        $name = $m.Name
        $code = $null
        if ($m.MonitorId) { $code = @($m.MonitorId.Split('\'))[1] }
        if ($code) {
            $hit = @($edid | Where-Object { [string]$_.InstanceName -like "DISPLAY\$code\*" })[0]
            if ($hit) {
                $friendly = -join (@($hit.UserFriendlyName | Where-Object { $_ }) | ForEach-Object { [char]$_ })
                if ($friendly) { $name = $friendly.Trim() }
            }
        }
        [pscustomobject]@{
            Dispositivo  = $m.Device
            Nome         = $name
            Primario     = $m.Primary
            Largura      = $m.Width
            Altura       = $m.Height
            HzAtual      = $m.Hz
            HzMaximo     = [math]::Max($m.MaxHzAtResolution, $m.Hz)
            HzMaximoTodo = $m.MaxHzAny
        }
    }
}

function Get-UTSecurityInfo {
    [CmdletBinding()]
    param()

    $secureBoot = $null
    $sb = Get-UTRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name 'UEFISecureBootEnabled'
    if ($sb.ValorExiste) { $secureBoot = ([int]$sb.Valor -eq 1) }

    $tpm = [pscustomobject]@{ Presente = $null; Versao = $null; Ativo = $null }
    try {
        $t = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($null -eq $t) {
            $tpm = [pscustomobject]@{ Presente = $false; Versao = $null; Ativo = $false }
        } else {
            $version = ([string]$t.SpecVersion).Split(',')[0].Trim()
            $tpm = [pscustomobject]@{ Presente = $true; Versao = $version; Ativo = [bool]$t.IsEnabled_InitialValue }
        }
    } catch {
        Write-UTLog -Level Debug -Message 'TPM não pôde ser lido (normal sem administrador).' -Detalhe $_.Exception.Message
    }

    $vbs = $null
    $hvci = $null
    try {
        $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $vbs = ([int]$dg.VirtualizationBasedSecurityStatus -eq 2)
        $hvci = (@($dg.SecurityServicesRunning) -contains [uint32]2)
    } catch {
        Write-UTLog -Level Debug -Message 'Estado do VBS não pôde ser lido.' -Detalhe $_.Exception.Message
    }

    return [pscustomobject]@{ SecureBoot = $secureBoot; Tpm = $tpm; Vbs = $vbs; Hvci = $hvci }
}

function Get-UTPlatformInfo {
    [CmdletBinding()]
    param()
    $battery = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0
    $chassis = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    # 8 Portable, 9 Laptop, 10 Notebook, 14 Sub Notebook, 30 Tablet, 31 Convertible, 32 Detachable
    $laptopChassis = @($chassis | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 }).Count -gt 0
    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        EhNotebook   = ($battery -or $laptopChassis)
        TemBateria   = $battery
        PlacaMae     = $(if ($board) { ('{0} {1}' -f $board.Manufacturer, $board.Product).Trim() } else { $null })
        FabricantePM = $(if ($board) { ([string]$board.Manufacturer).Trim() } else { $null })
    }
}

function Get-UTSystemSettingsInfo {
    [CmdletBinding()]
    param()

    $hags = 'padrao'
    $h = Get-UTRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
    if ($h.ValorExiste) { $hags = $(if ([int]$h.Valor -eq 2) { 'ligado' } else { 'desligado' }) }

    $gm = Get-UTRegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
    $gameMode = (-not $gm.ValorExiste) -or ([int]$gm.Valor -eq 1)

    $dvr = Get-UTRegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
    $gameDvr = (-not $dvr.ValorExiste) -or ([int]$dvr.Valor -eq 1)

    $plan = $null
    try { $plan = Get-UTActivePowerScheme } catch { $plan = $null }

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $pageFiles = @(Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue)
    $pageUsage = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $paging = [pscustomobject]@{
        Automatica = $(if ($cs) { [bool]$cs.AutomaticManagedPagefile } else { $null })
        Arquivos   = @($pageFiles | ForEach-Object { [pscustomobject]@{ Caminho = $_.Name; InicialMB = $_.InitialSize; MaximoMB = $_.MaximumSize } })
        EmUso      = ($pageUsage.Count -gt 0)
    }

    return [pscustomobject]@{
        Hags            = $hags
        ModoJogo        = $gameMode
        GameDvr         = $gameDvr
        PlanoEnergia    = $plan
        Paginacao       = $paging
    }
}
