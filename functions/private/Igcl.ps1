# Intel Arc settings through the Intel Graphics Control Library (IGCL), the official Intel API
# that ships with the driver (System32\ControlLib.dll). Layout of ctl_3d_feature_getset_t and
# ctl_init_args_t from intel/drivers.gpu.control-library (include/igcl_api.h), x64.


function Initialize-UTIgclType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.Igcl' -as [type]) { return }
    # The source lives inside the function: functions copied to background runspaces keep it.
    $source = @'
using System;
using System.Runtime.InteropServices;

namespace UpgradeTweaks
{
    public class IgclValue
    {
        public bool Suportado;
        public int Valor;
        public int Resultado;
    }

    public sealed class Igcl : IDisposable
    {
        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string path);
        [DllImport("kernel32", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint InitFn(IntPtr args, out IntPtr api);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint CloseFn(IntPtr api);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint EnumFn(IntPtr api, ref uint count, [In, Out] IntPtr[] devices);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint GetSetFn(IntPtr device, IntPtr feature);

        // ctl_3d_feature_t
        public const int FEATURE_ENDURANCE_GAMING = 1;
        public const int FEATURE_FRAME_LIMIT = 2;
        public const int FEATURE_GAMING_FLIP_MODES = 9;
        public const int FEATURE_LOW_LATENCY = 16;
        public const int FEATURE_PREBUILT_SHADER_DOWNLOAD = 18;
        // ctl_property_value_type_t
        public const int TYPE_BOOL = 0;
        public const int TYPE_INT32 = 2;
        public const int TYPE_ENUM = 4;
        public const int TYPE_CUSTOM = 5;

        const int GETSET_SIZE = 56;
        const int INIT_SIZE = 36;

        IntPtr module, api;
        InitFn init; CloseFn close; EnumFn enumerate; GetSetFn getset;

        public static string LibraryPath() { return System.IO.Path.Combine(Environment.SystemDirectory, "ControlLib.dll"); }

        public Igcl()
        {
            module = LoadLibrary(LibraryPath());
            if (module == IntPtr.Zero) throw new InvalidOperationException("ControlLib.dll n\u00e3o carregou");
            init = Load<InitFn>("ctlInit");
            close = Load<CloseFn>("ctlClose");
            enumerate = Load<EnumFn>("ctlEnumerateDevices");
            getset = Load<GetSetFn>("ctlGetSet3DFeature");
            IntPtr args = Marshal.AllocHGlobal(INIT_SIZE);
            try
            {
                for (int i = 0; i < INIT_SIZE; i++) Marshal.WriteByte(args, i, 0);
                Marshal.WriteInt32(args, 0, INIT_SIZE);                 // Size
                Marshal.WriteByte(args, 4, 0);                          // Version
                Marshal.WriteInt32(args, 8, (1 << 16) | 1);             // AppVersion = CTL_IMPL_VERSION 1.1
                Marshal.WriteInt32(args, 12, 0);                        // flags
                byte[] uid = new Guid("6a0b5f8e-3c2d-4e1f-9a7b-55e1c0d2a901").ToByteArray();
                Marshal.Copy(uid, 0, new IntPtr(args.ToInt64() + 20), 16);   // ApplicationUID
                uint r = init(args, out api);
                if (r != 0 || api == IntPtr.Zero) throw new InvalidOperationException("ctlInit devolveu 0x" + r.ToString("X8"));
            }
            finally { Marshal.FreeHGlobal(args); }
        }

        T Load<T>(string name) where T : class
        {
            IntPtr p = GetProcAddress(module, name);
            if (p == IntPtr.Zero) throw new InvalidOperationException(name + " n\u00e3o encontrado em ControlLib.dll");
            return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
        }

        public IntPtr[] Devices()
        {
            uint count = 0;
            uint r = enumerate(api, ref count, null);
            if (r != 0 || count == 0) return new IntPtr[0];
            IntPtr[] devices = new IntPtr[count];
            r = enumerate(api, ref count, devices);
            if (r != 0) return new IntPtr[0];
            return devices;
        }

        // Get/set one global 3D feature. For TYPE_INT32 the value is the "Enable" flag of the
        // frame limiter; for TYPE_CUSTOM (endurance gaming) it is EGControl.
        IgclValue Call(IntPtr device, int feature, int type, bool set, int value)
        {
            var v = new IgclValue();
            IntPtr p = Marshal.AllocHGlobal(GETSET_SIZE);
            IntPtr custom = IntPtr.Zero;
            try
            {
                for (int i = 0; i < GETSET_SIZE; i++) Marshal.WriteByte(p, i, 0);
                Marshal.WriteInt32(p, 0, GETSET_SIZE);   // Size
                Marshal.WriteByte(p, 4, 0);              // Version
                Marshal.WriteInt32(p, 8, feature);       // FeatureType
                Marshal.WriteIntPtr(p, 16, IntPtr.Zero); // ApplicationName = global
                Marshal.WriteByte(p, 24, 0);             // ApplicationNameLength
                Marshal.WriteByte(p, 25, (byte)(set ? 1 : 0)); // bSet
                Marshal.WriteInt32(p, 28, type);         // ValueType
                if (type == TYPE_CUSTOM)
                {
                    custom = Marshal.AllocHGlobal(8);    // ctl_endurance_gaming_t { EGControl, EGMode }
                    Marshal.WriteInt32(custom, 0, value);
                    Marshal.WriteInt32(custom, 4, 0);
                    Marshal.WriteInt32(p, 40, 8);
                    Marshal.WriteIntPtr(p, 48, custom);
                }
                else if (set)
                {
                    if (type == TYPE_BOOL) Marshal.WriteByte(p, 32, (byte)(value != 0 ? 1 : 0));
                    else if (type == TYPE_ENUM) Marshal.WriteInt32(p, 32, value);
                    else if (type == TYPE_INT32)
                    {
                        // Read first so the FPS value stays; then change only Enable.
                        Marshal.WriteByte(p, 25, 0);
                        uint r0 = getset(device, p);
                        if (r0 != 0) { v.Resultado = (int)r0; return v; }
                        Marshal.WriteByte(p, 25, 1);
                        Marshal.WriteByte(p, 32, (byte)(value != 0 ? 1 : 0));
                    }
                }
                uint r = getset(device, p);
                v.Resultado = (int)r;
                v.Suportado = (r == 0);
                if (type == TYPE_CUSTOM) v.Valor = Marshal.ReadInt32(custom, 0);
                else if (type == TYPE_ENUM) v.Valor = Marshal.ReadInt32(p, 32);
                else v.Valor = Marshal.ReadByte(p, 32);
                return v;
            }
            finally
            {
                Marshal.FreeHGlobal(p);
                if (custom != IntPtr.Zero) Marshal.FreeHGlobal(custom);
            }
        }

        public IgclValue Get(IntPtr device, int feature, int type) { return Call(device, feature, type, false, 0); }
        public IgclValue Set(IntPtr device, int feature, int type, int value) { return Call(device, feature, type, true, value); }

        public void Dispose()
        {
            if (api != IntPtr.Zero) { try { close(api); } catch { } api = IntPtr.Zero; }
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp
}

function Test-UTIgclAvailable {
    # Intel graphics driver with the Control Library (Arc and recent integrated GPUs).
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\ControlLib.dll'))
}

function Open-UTIgclSession {
    [CmdletBinding()]
    param()
    if (-not (Test-UTIgclAvailable)) { throw 'Driver Intel com a Control Library não encontrado. Instale o driver Intel Arc/Iris Xe mais recente.' }
    Initialize-UTIgclType
    return (New-Object UpgradeTweaks.Igcl)
}
