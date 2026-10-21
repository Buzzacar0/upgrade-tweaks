# NVIDIA driver settings (DRS, the database behind the old Control Panel and the NVIDIA App)
# through NVAPI, plus output color range. Struct layouts and function ids come from the public
# NVIDIA/nvapi headers (MIT); they match the ones NVIDIA Profile Inspector uses.

function Initialize-UTNvApiType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.NvDrs' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace UpgradeTweaks {
    public class NvApiException : Exception {
        public int Status;
        public NvApiException(string function, int status) : base(function + " falhou (NVAPI " + status + ")") { Status = status; }
    }

    public class NvSettingValue {
        public bool Existe;
        public uint Valor;
        public bool Predefinido;
        public uint Local;
        public bool PadraoValido;
        public uint ValorPadrao;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 8, CharSet = CharSet.Unicode, Size = 4100)]
    public struct NvSettingUnion {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4100)] public byte[] raw;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 8, CharSet = CharSet.Unicode)]
    public struct NvDrsSetting {
        public uint version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string settingName;
        public uint settingId;
        public uint settingType;
        public uint settingLocation;
        public uint isCurrentPredefined;
        public uint isPredefinedValid;
        public NvSettingUnion predefinedValue;
        public NvSettingUnion currentValue;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 8, CharSet = CharSet.Unicode)]
    public struct NvDrsProfile {
        public uint version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string profileName;
        public uint gpuSupport;
        public uint isPredefined;
        public uint numOfApps;
        public uint numOfSettings;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 8, CharSet = CharSet.Unicode)]
    public struct NvDrsApplicationV3 {
        public uint version;
        public uint isPredefined;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string appName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string userFriendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string launcher;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 2048)] public string fileInFolder;
        public uint flags;
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    public struct NvColorData {
        [FieldOffset(0)] public uint version;
        [FieldOffset(4)] public ushort size;
        [FieldOffset(6)] public byte cmd;
        [FieldOffset(8)] public byte colorFormat;
        [FieldOffset(9)] public byte colorimetry;
        [FieldOffset(10)] public byte dynamicRange;
        [FieldOffset(12)] public uint bpc;
        [FieldOffset(16)] public uint colorSelectionPolicy;
        [FieldOffset(20)] public uint depth;
    }

    public sealed class NvDrs : IDisposable {
        public const int OK = 0;
        public const int SETTING_NOT_FOUND = -160;
        public const int PROFILE_NOT_FOUND = -163;
        public const int EXECUTABLE_NOT_FOUND = -166;

        [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr QueryInterface(uint id);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int D0();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DSessionOut(out IntPtr h);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DSession(IntPtr h);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DProfileOut(IntPtr s, out IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DFindProfile(IntPtr s, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, out IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DFindApp(IntPtr s, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, out IntPtr p, ref NvDrsApplicationV3 app);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DCreateProfile(IntPtr s, ref NvDrsProfile info, out IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DProfileInfo(IntPtr s, IntPtr p, ref NvDrsProfile info);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DCreateApp(IntPtr s, IntPtr p, ref NvDrsApplicationV3 app);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DProfile(IntPtr s, IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DGetSetting(IntPtr s, IntPtr p, uint id, ref NvDrsSetting setting);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DSetSetting(IntPtr s, IntPtr p, ref NvDrsSetting setting);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DProfileSetting(IntPtr s, IntPtr p, uint id);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DFile(IntPtr s, [MarshalAs(UnmanagedType.LPWStr)] StringBuilder path);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DDisplayId([MarshalAs(UnmanagedType.LPStr)] string name, out uint id);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DColor(uint displayId, ref NvColorData data);

        static bool loaded;
        static D0 initialize;
        static DSessionOut createSession;
        static DSession destroySession, loadSettings, saveSettings;
        static DProfileOut getBaseProfile;
        static DFindProfile findProfileByName;
        static DFindApp findApplicationByName;
        static DCreateProfile createProfile;
        static DProfileInfo getProfileInfo;
        static DCreateApp createApplication;
        static DProfile deleteProfile, restoreProfileDefault;
        static DGetSetting getSetting;
        static DSetSetting setSetting;
        static DProfileSetting restoreDefaultSetting, deleteProfileSetting;
        static DFile saveToFile, loadFromFile;
        static DDisplayId displayIdByName;
        static DColor colorControl;

        static T Get<T>(uint id) where T : class {
            IntPtr p = QueryInterface(id);
            if (p == IntPtr.Zero) throw new NvApiException("nvapi_QueryInterface 0x" + id.ToString("X8"), -136);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
        }

        public static void Load() {
            if (loaded) return;
            initialize = Get<D0>(0x0150E828);
            int st = initialize();
            if (st != OK) throw new NvApiException("NvAPI_Initialize", st);
            createSession = Get<DSessionOut>(0x0694D52E);
            destroySession = Get<DSession>(0xDAD9CFF8);
            loadSettings = Get<DSession>(0x375DBD6B);
            saveSettings = Get<DSession>(0xFCBC7E14);
            getBaseProfile = Get<DProfileOut>(0xDA8466A0);
            findProfileByName = Get<DFindProfile>(0x7E4A9A0B);
            findApplicationByName = Get<DFindApp>(0xEEE566B2);
            createProfile = Get<DCreateProfile>(0xCC176068);
            getProfileInfo = Get<DProfileInfo>(0x61CD6FD6);
            createApplication = Get<DCreateApp>(0x4347A9DE);
            deleteProfile = Get<DProfile>(0x17093206);
            restoreProfileDefault = Get<DProfile>(0xFA5F6134);
            getSetting = Get<DGetSetting>(0x73BF8338);
            setSetting = Get<DSetSetting>(0x577DD202);
            restoreDefaultSetting = Get<DProfileSetting>(0x53F0381E);
            deleteProfileSetting = Get<DProfileSetting>(0xE4A26362);
            saveToFile = Get<DFile>(0x2BE25DF8);
            loadFromFile = Get<DFile>(0xD3EDE889);
            displayIdByName = Get<DDisplayId>(0xAE457190);
            colorControl = Get<DColor>(0x92F9D80D);
            loaded = true;
        }

        static uint Version<T>(int v) { return (uint)(Marshal.SizeOf(typeof(T)) | (v << 16)); }
        static void Check(string f, int st) { if (st != OK) throw new NvApiException(f, st); }
        static StringBuilder Buffer(string s) { var b = new StringBuilder(2048); b.Append(s); return b; }

        IntPtr session;

        public NvDrs() {
            Load();
            Check("NvAPI_DRS_CreateSession", createSession(out session));
            Check("NvAPI_DRS_LoadSettings", loadSettings(session));
        }

        public void Dispose() {
            if (session != IntPtr.Zero) { destroySession(session); session = IntPtr.Zero; }
        }

        public IntPtr BaseProfile() {
            IntPtr p; Check("NvAPI_DRS_GetBaseProfile", getBaseProfile(session, out p)); return p;
        }

        public IntPtr FindProfile(string name) {
            IntPtr p; int st = findProfileByName(session, Buffer(name), out p);
            if (st == PROFILE_NOT_FOUND) return IntPtr.Zero;
            Check("NvAPI_DRS_FindProfileByName", st); return p;
        }

        public IntPtr FindProfileByApp(string exe) {
            var app = new NvDrsApplicationV3(); app.version = Version<NvDrsApplicationV3>(3);
            IntPtr p; int st = findApplicationByName(session, Buffer(exe), out p, ref app);
            if (st == EXECUTABLE_NOT_FOUND || st == PROFILE_NOT_FOUND) return IntPtr.Zero;
            Check("NvAPI_DRS_FindApplicationByName", st); return p;
        }

        public string ProfileName(IntPtr profile) {
            var info = new NvDrsProfile(); info.version = Version<NvDrsProfile>(1);
            Check("NvAPI_DRS_GetProfileInfo", getProfileInfo(session, profile, ref info));
            return info.profileName;
        }

        public bool ProfileIsPredefined(IntPtr profile) {
            var info = new NvDrsProfile(); info.version = Version<NvDrsProfile>(1);
            Check("NvAPI_DRS_GetProfileInfo", getProfileInfo(session, profile, ref info));
            return info.isPredefined != 0;
        }

        public IntPtr CreateProfile(string name) {
            var info = new NvDrsProfile(); info.version = Version<NvDrsProfile>(1); info.profileName = name; info.gpuSupport = 1;
            IntPtr p; Check("NvAPI_DRS_CreateProfile", createProfile(session, ref info, out p)); return p;
        }

        public void AddApplication(IntPtr profile, string exe) {
            var app = new NvDrsApplicationV3(); app.version = Version<NvDrsApplicationV3>(3); app.appName = exe; app.userFriendlyName = exe;
            Check("NvAPI_DRS_CreateApplication", createApplication(session, profile, ref app));
        }

        public void DeleteProfile(IntPtr profile) { Check("NvAPI_DRS_DeleteProfile", deleteProfile(session, profile)); }
        public void RestoreProfileDefault(IntPtr profile) { Check("NvAPI_DRS_RestoreProfileDefault", restoreProfileDefault(session, profile)); }

        public NvSettingValue GetSetting(IntPtr profile, uint id) {
            var s = new NvDrsSetting(); s.version = Version<NvDrsSetting>(1);
            int st = getSetting(session, profile, id, ref s);
            var r = new NvSettingValue();
            if (st == SETTING_NOT_FOUND) return r;
            Check("NvAPI_DRS_GetSetting", st);
            r.Existe = true;
            r.Valor = BitConverter.ToUInt32(s.currentValue.raw, 0);
            r.Predefinido = s.isCurrentPredefined != 0;
            r.Local = s.settingLocation;
            r.PadraoValido = s.isPredefinedValid != 0;
            r.ValorPadrao = BitConverter.ToUInt32(s.predefinedValue.raw, 0);
            return r;
        }

        public void SetDword(IntPtr profile, uint id, uint value) {
            var s = new NvDrsSetting(); s.version = Version<NvDrsSetting>(1); s.settingId = id; s.settingType = 0; s.settingName = "";
            s.predefinedValue.raw = new byte[4100]; s.currentValue.raw = new byte[4100];
            Array.Copy(BitConverter.GetBytes(value), s.currentValue.raw, 4);
            Check("NvAPI_DRS_SetSetting", setSetting(session, profile, ref s));
        }

        public int RestoreDefaultSetting(IntPtr profile, uint id) { return restoreDefaultSetting(session, profile, id); }
        public int DeleteSetting(IntPtr profile, uint id) { return deleteProfileSetting(session, profile, id); }
        public void Save() { Check("NvAPI_DRS_SaveSettings", saveSettings(session)); }
        public void SaveToFile(string path) { Check("NvAPI_DRS_SaveSettingsToFile", saveToFile(session, Buffer(path))); }
        public void LoadFromFile(string path) { Check("NvAPI_DRS_LoadSettingsFromFile", loadFromFile(session, Buffer(path))); }

        public static uint DisplayId(string gdiName) {
            Load(); uint id; Check("NvAPI_DISP_GetDisplayIdByDisplayName", displayIdByName(gdiName, out id)); return id;
        }

        public static NvColorData GetColor(uint displayId) {
            Load();
            var d = new NvColorData(); d.version = (uint)(24 | (5 << 16)); d.size = 24; d.cmd = 1;
            Check("NvAPI_Disp_ColorControl(GET)", colorControl(displayId, ref d)); return d;
        }

        public static void SetDynamicRange(uint displayId, byte range) {
            var d = GetColor(displayId);
            d.version = (uint)(24 | (5 << 16)); d.size = 24; d.cmd = 2; d.dynamicRange = range; d.colorSelectionPolicy = 0;
            Check("NvAPI_Disp_ColorControl(SET)", colorControl(displayId, ref d));
        }
    }
}
'@
}

function Test-UTNvApiAvailable {
    <#
    .SYNOPSIS
        True when an NVIDIA driver with NVAPI is installed and answers.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\nvapi64.dll'))) { return $false }
    try {
        Initialize-UTNvApiType
        [UpgradeTweaks.NvDrs]::Load()
        return $true
    } catch {
        Write-UTLog -Level Debug -Message 'NVAPI indisponível.' -Detalhe $_.Exception.Message
        return $false
    }
}

function Open-UTNvDrsSession {
    <#
    .SYNOPSIS
        Opens a DRS session with the current driver settings loaded. Dispose() it in a finally.
    #>
    [CmdletBinding()]
    param()
    Initialize-UTNvApiType
    return (New-Object UpgradeTweaks.NvDrs)
}
