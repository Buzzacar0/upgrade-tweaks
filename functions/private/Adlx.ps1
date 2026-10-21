# AMD Software (Adrenalin) settings through ADLX, the official AMD library that ships with the
# driver (amdadlx64.dll). ADLX exposes C interfaces as vtables; the slot numbers below come
# from the public headers of GPUOpen-LibrariesAndSDKs/ADLX (SDK/Include, C section).


function Initialize-UTAdlxType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.Adlx' -as [type]) { return }
    # The source lives inside the function: functions copied to background runspaces keep it.
    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace UpgradeTweaks
{
    public class AdlxValue
    {
        public bool Suportado;
        public int Valor;
        public string Erro;
    }

    public class AdlxGpu
    {
        public IntPtr Ptr;
        public string Nome;
        public int Tipo;
        public int Id;
    }

    public sealed class Adlx : IDisposable
    {
        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string path);
        [DllImport("kernel32", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitFn(ulong version, out IntPtr system);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int TerminateFn();
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int ReleaseFn(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int OutPtrFn(IntPtr self, out IntPtr result);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int ArgOutPtrFn(IntPtr self, IntPtr arg, out IntPtr result);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int QueryFn(IntPtr self, [MarshalAs(UnmanagedType.LPWStr)] string iid, out IntPtr result);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int OutBoolFn(IntPtr self, out byte value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int InBoolFn(IntPtr self, byte value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int OutIntFn(IntPtr self, out int value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int InIntFn(IntPtr self, int value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate uint SizeFn(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int AtFn(IntPtr self, uint index, out IntPtr item);

        public const int OK = 0;
        public const int ALREADY_ENABLED = 1;
        public const int NOT_SUPPORTED = 12;

        // Setting -> slot in IADLX3DSettingsServices (-1 = IADLX3DSettingsServices1), global (no GPU),
        // kind (b = IsEnabled/SetEnabled, m = Get/Set mode), getter slot, setter slot.
        class Spec { public int Service; public bool Global; public char Kind; public int Get; public int Set; public string Iid;
            public Spec(int s, bool g, char k, int get, int set, string iid) { Service = s; Global = g; Kind = k; Get = get; Set = set; Iid = iid; } }
        static readonly Dictionary<string, Spec> Specs = new Dictionary<string, Spec>(StringComparer.OrdinalIgnoreCase)
        {
            { "antiLag",        new Spec(3,  false, 'b', 4, 5, null) },
            { "chill",          new Spec(4,  false, 'b', 4, 8, null) },
            { "boost",          new Spec(5,  false, 'b', 4, 7, null) },
            { "imageSharpening",new Spec(6,  false, 'b', 4, 7, null) },
            { "enhancedSync",   new Spec(7,  false, 'b', 4, 5, null) },
            { "vsync",          new Spec(8,  false, 'm', 5, 6, null) },
            { "frtc",           new Spec(9,  false, 'b', 4, 7, null) },
            { "antiAliasing",   new Spec(10, false, 'm', 4, 7, null) },
            { "mlaa",           new Spec(11, false, 'b', 4, 5, null) },
            { "anisotropic",    new Spec(12, false, 'b', 4, 6, null) },
            { "tessellation",   new Spec(13, false, 'm', 4, 6, null) },
            { "rsr",            new Spec(14, true,  'b', 4, 5, null) },
            { "afmf",           new Spec(17, true,  'b', 4, 5, "IADLX3DSettingsServices1") }
        };

        IntPtr module, system, settings;
        readonly List<IntPtr> owned = new List<IntPtr>();

        static T Slot<T>(IntPtr obj, int index) where T : class
        {
            IntPtr vtbl = Marshal.ReadIntPtr(obj);
            IntPtr fn = Marshal.ReadIntPtr(vtbl, index * IntPtr.Size);
            return (T)(object)Marshal.GetDelegateForFunctionPointer(fn, typeof(T));
        }

        static void Check(int r, string what) { if (r != OK && r != ALREADY_ENABLED) throw new InvalidOperationException(what + " devolveu " + r); }

        IntPtr Own(IntPtr p) { if (p != IntPtr.Zero) owned.Add(p); return p; }

        public static bool Available()
        {
            return System.IO.File.Exists(System.IO.Path.Combine(Environment.SystemDirectory, "amdadlx64.dll"));
        }

        public Adlx()
        {
            module = LoadLibrary(System.IO.Path.Combine(Environment.SystemDirectory, "amdadlx64.dll"));
            if (module == IntPtr.Zero) throw new InvalidOperationException("amdadlx64.dll n\u00e3o carregou");
            IntPtr init = GetProcAddress(module, "ADLXInitialize");
            if (init == IntPtr.Zero) throw new InvalidOperationException("ADLXInitialize n\u00e3o encontrado");
            // Ask for 1.0: every interface used here exists since then; newer runtimes accept it.
            int r = ((InitFn)Marshal.GetDelegateForFunctionPointer(init, typeof(InitFn)))(1UL << 48, out system);
            Check(r, "ADLXInitialize");
            Check(Slot<OutPtrFn>(system, 7)(system, out settings), "Get3DSettingsServices");
            Own(settings);
        }

        public List<AdlxGpu> Gpus()
        {
            IntPtr list;
            Check(Slot<OutPtrFn>(system, 1)(system, out list), "GetGPUs");
            Own(list);
            var result = new List<AdlxGpu>();
            uint n = Slot<SizeFn>(list, 3)(list);
            for (uint i = 0; i < n; i++)
            {
                IntPtr gpu;
                if (Slot<AtFn>(list, 11)(list, i, out gpu) != OK || gpu == IntPtr.Zero) continue;
                Own(gpu);
                IntPtr name; int type; int id;
                Slot<OutPtrFn>(gpu, 7)(gpu, out name);
                Slot<OutIntFn>(gpu, 5)(gpu, out type);
                Slot<OutIntFn>(gpu, 18)(gpu, out id);
                result.Add(new AdlxGpu { Ptr = gpu, Nome = name == IntPtr.Zero ? "" : Marshal.PtrToStringAnsi(name), Tipo = type, Id = id });
            }
            return result;
        }

        IntPtr SettingInterface(string key, IntPtr gpu)
        {
            Spec s;
            if (!Specs.TryGetValue(key, out s)) throw new ArgumentException("Configura\u00e7\u00e3o AMD desconhecida: " + key);
            IntPtr svc = settings;
            if (s.Iid != null)
            {
                IntPtr svc1;
                if (Slot<QueryFn>(settings, 2)(settings, s.Iid, out svc1) != OK || svc1 == IntPtr.Zero) return IntPtr.Zero;
                svc = Own(svc1);
            }
            IntPtr itf; int r;
            if (s.Global) r = Slot<OutPtrFn>(svc, s.Service)(svc, out itf);
            else r = Slot<ArgOutPtrFn>(svc, s.Service)(svc, gpu, out itf);
            if (r != OK || itf == IntPtr.Zero) return IntPtr.Zero;
            return Own(itf);
        }

        public static bool IsGlobal(string key) { return Specs[key].Global; }

        public AdlxValue Get(string key, IntPtr gpu)
        {
            var v = new AdlxValue();
            IntPtr itf = SettingInterface(key, gpu);
            if (itf == IntPtr.Zero) { v.Erro = "interface indispon\u00edvel"; return v; }
            byte supported;
            if (Slot<OutBoolFn>(itf, 3)(itf, out supported) != OK || supported == 0) { v.Erro = "n\u00e3o suportado"; return v; }
            v.Suportado = true;
            Spec s = Specs[key];
            int r;
            if (s.Kind == 'b') { byte b; r = Slot<OutBoolFn>(itf, s.Get)(itf, out b); v.Valor = b; }
            else { int m; r = Slot<OutIntFn>(itf, s.Get)(itf, out m); v.Valor = m; }
            if (r != OK) { v.Suportado = false; v.Erro = "leitura devolveu " + r; }
            return v;
        }

        public int Set(string key, IntPtr gpu, int value)
        {
            IntPtr itf = SettingInterface(key, gpu);
            if (itf == IntPtr.Zero) return NOT_SUPPORTED;
            Spec s = Specs[key];
            if (s.Kind == 'b') return Slot<InBoolFn>(itf, s.Set)(itf, (byte)(value != 0 ? 1 : 0));
            return Slot<InIntFn>(itf, s.Set)(itf, value);
        }

        // FreeSync per display: IADLXSystem.GetDisplaysServices (3) -> GetDisplays (4) / GetFreeSync (9).
        public List<KeyValuePair<string, IntPtr>> FreeSyncDisplays()
        {
            var result = new List<KeyValuePair<string, IntPtr>>();
            IntPtr disp, list;
            if (Slot<OutPtrFn>(system, 3)(system, out disp) != OK || disp == IntPtr.Zero) return result;
            Own(disp);
            if (Slot<OutPtrFn>(disp, 4)(disp, out list) != OK || list == IntPtr.Zero) return result;
            Own(list);
            uint n = Slot<SizeFn>(list, 3)(list);
            for (uint i = 0; i < n; i++)
            {
                IntPtr d, fs, name;
                if (Slot<AtFn>(list, 11)(list, i, out d) != OK || d == IntPtr.Zero) continue;
                Own(d);
                Slot<OutPtrFn>(d, 6)(d, out name);
                if (Slot<ArgOutPtrFn>(disp, 9)(disp, d, out fs) != OK || fs == IntPtr.Zero) continue;
                Own(fs);
                result.Add(new KeyValuePair<string, IntPtr>(name == IntPtr.Zero ? "" : Marshal.PtrToStringAnsi(name), fs));
            }
            return result;
        }

        public AdlxValue GetFreeSync(IntPtr fs)
        {
            var v = new AdlxValue();
            byte s, e;
            if (Slot<OutBoolFn>(fs, 3)(fs, out s) != OK || s == 0) { v.Erro = "n\u00e3o suportado"; return v; }
            v.Suportado = true;
            Slot<OutBoolFn>(fs, 4)(fs, out e);
            v.Valor = e;
            return v;
        }

        public int SetFreeSync(IntPtr fs, bool enabled) { return Slot<InBoolFn>(fs, 5)(fs, (byte)(enabled ? 1 : 0)); }

        public void Dispose()
        {
            for (int i = owned.Count - 1; i >= 0; i--) { try { Slot<ReleaseFn>(owned[i], 1)(owned[i]); } catch { } }
            owned.Clear();
            if (module != IntPtr.Zero)
            {
                IntPtr term = GetProcAddress(module, "ADLXTerminate");
                if (term != IntPtr.Zero && system != IntPtr.Zero) { try { ((TerminateFn)Marshal.GetDelegateForFunctionPointer(term, typeof(TerminateFn)))(); } catch { } }
                system = IntPtr.Zero;
            }
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp
}

function Test-UTAdlxAvailable {
    # AMD driver with ADLX installed (Adrenalin 22.x or newer).
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\amdadlx64.dll'))
}

function Open-UTAdlxSession {
    [CmdletBinding()]
    param()
    if (-not (Test-UTAdlxAvailable)) { throw 'Driver AMD com ADLX não encontrado. Instale o AMD Software: Adrenalin Edition mais recente.' }
    Initialize-UTAdlxType
    return (New-Object UpgradeTweaks.Adlx)
}
