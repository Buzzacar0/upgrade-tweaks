# Monitor refresh rate (user32 ChangeDisplaySettingsEx). The mode is always validated with
# CDS_TEST before it is applied; the interface asks the user to confirm within 15 seconds and
# reverts on its own otherwise (phase 9), the same way Windows does.

function Initialize-UTDisplayModeType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.DisplayMode' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace UpgradeTweaks {
    public static class DisplayMode {
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
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, uint flags, IntPtr lParam);
        const int ENUM_CURRENT_SETTINGS = -1;
        const int DM_DISPLAYFREQUENCY = 0x400000;
        const uint CDS_UPDATEREGISTRY = 1;
        const uint CDS_TEST = 2;

        // Returns the DISP_CHANGE code: 0 = success, 1 = restart needed, negative = failure.
        public static int SetRefresh(string device, int hz, bool testOnly) {
            var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
            if (!EnumDisplaySettings(device, ENUM_CURRENT_SETTINGS, ref dm)) return -99;
            dm.dmDisplayFrequency = hz;
            dm.dmFields = DM_DISPLAYFREQUENCY;
            int test = ChangeDisplaySettingsEx(device, ref dm, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
            if (test != 0 || testOnly) return test;
            return ChangeDisplaySettingsEx(device, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
        }
    }
}
'@
}

function Set-UTMonitorRefresh {
    <#
    .SYNOPSIS
        Changes the refresh rate of one monitor keeping its resolution. -Teste only validates.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Dispositivo,
        [Parameter(Mandatory)][int]$Hz,
        [switch]$Teste
    )
    if (-not $Teste -and -not $PSCmdlet.ShouldProcess($Dispositivo, "Taxa de atualização = $Hz Hz")) { return }
    Initialize-UTDisplayModeType
    $code = [UpgradeTweaks.DisplayMode]::SetRefresh($Dispositivo, $Hz, [bool]$Teste)
    if ($code -lt 0) { throw "O Windows recusou $Hz Hz em $Dispositivo (código $code)." }
    return $code
}

function Set-UTMonitorMaxRefresh {
    <#
    .SYNOPSIS
        Puts every monitor below its maximum refresh rate (at the current resolution) on the
        maximum, saving the previous rate.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $slow = @(Get-UTDisplayInfo | Where-Object { $_.HzMaximo -gt $_.HzAtual })
    foreach ($m in $slow) {
        if (-not $PSCmdlet.ShouldProcess($m.Dispositivo, "Taxa de atualização em $($m.HzMaximo) Hz")) { continue }
        [void](Set-UTMonitorRefresh -Dispositivo $m.Dispositivo -Hz $m.HzMaximo -Teste)
        [void](Save-UTOriginalItem -Chave "monitor|$($m.Dispositivo)" -Dados ([ordered]@{ dispositivo = $m.Dispositivo; hz = $m.HzAtual }) -TweakId $TweakId)
        [void](Set-UTMonitorRefresh -Dispositivo $m.Dispositivo -Hz $m.HzMaximo)
        Write-UTLog -Level Info -TweakId $TweakId -Message "$($m.Nome): $($m.HzAtual) Hz -> $($m.HzMaximo) Hz."
    }
}

function Restore-UTMonitorMaxRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    foreach ($entry in @(Get-UTOriginalStateItem)) {
        $item = $entry.Item
        if ($item.tipo -ne 'generico' -or ([string]$item.chave) -notlike 'monitor|*' -or @($item.tweaks) -notcontains $TweakId) { continue }
        $d = Pop-UTOriginalItem -Chave $item.chave -TweakId $TweakId
        if ($d -is [System.Collections.IDictionary]) { [void](Set-UTMonitorRefresh -Dispositivo ([string]$d.dispositivo) -Hz ([int]$d.hz)) }
    }
}

function Test-UTMonitorMaxRefresh {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $monitors = @(Get-UTDisplayInfo)
    return ($monitors.Count -gt 0 -and @($monitors | Where-Object { $_.HzMaximo -gt $_.HzAtual }).Count -eq 0)
}
