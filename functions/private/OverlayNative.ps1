# Native part of the overlay, compiled on first use with Add-Type (C# 5, the compiler that
# comes with Windows): the PresentMon reader (the official Intel console app reading ETW events,
# nothing is injected into the game), frame time statistics, the click-through window styles,
# monitors and DPI, global hotkeys and the optional RivaTuner (RTSS) shared memory.

function Initialize-UTOverlayNative {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.Overlay.FrameMath' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace UpgradeTweaks.Overlay {

    public sealed class FrameSample {
        public string Application;
        public int ProcessId;
        public string PresentMode;
        public double FrameMs;          // between presents (the frame rate the game runs at)
        public double DisplayMs;        // between display changes; NaN when the frame was not shown
        public double GpuBusyMs;
        public double CpuBusyMs;
        public double TimeMs;           // time of the frame since the capture started
    }

    // Reads the CSV of PresentMon (1.x and 2.x columns) by the names in the header line.
    public sealed class PresentMonParser {
        int iApp = -1, iPid = -1, iMode = -1, iFrame = -1, iDisplay = -1, iGpu = -1, iCpu = -1, iTime = -1;
        double timeScale = 1;
        int maxIndex = -1;
        public bool HasHeader { get; private set; }
        public string[] Columns { get; private set; }

        static int Find(string[] cols, params string[] names) {
            foreach (string n in names) {
                for (int i = 0; i < cols.Length; i++) { if (string.Equals(cols[i].Trim(), n, StringComparison.OrdinalIgnoreCase)) return i; }
            }
            return -1;
        }

        public bool ReadHeader(string line) {
            string[] cols = line.Split(',');
            Columns = cols;
            iApp = Find(cols, "Application", "ProcessName");
            iPid = Find(cols, "ProcessID");
            iMode = Find(cols, "PresentMode");
            iFrame = Find(cols, "MsBetweenPresents", "FrameTime", "MsBetweenAppStart");
            iDisplay = Find(cols, "MsBetweenDisplayChange", "DisplayedTime");
            iGpu = Find(cols, "MsGPUBusy", "GPUBusy", "MsGPUActive", "MsGPUTime");
            iCpu = Find(cols, "MsCPUBusy", "CPUBusy");
            timeScale = 1;
            iTime = Find(cols, "TimeInMs", "CPUStartTimeInMs");
            if (iTime < 0) { iTime = Find(cols, "TimeInSeconds", "CPUStartTime"); timeScale = 1000; }
            maxIndex = Math.Max(Math.Max(iApp, iPid), Math.Max(iFrame, Math.Max(iMode, Math.Max(iDisplay, Math.Max(iGpu, Math.Max(iCpu, iTime))))));
            HasHeader = iApp >= 0 && iPid >= 0 && iFrame >= 0;
            return HasHeader;
        }

        public static double Number(string s) {
            double v;
            if (s != null && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v)) return v;
            return double.NaN;
        }

        // A frame, or null for the header, lines before it, broken lines and frames without time.
        public FrameSample Parse(string line) {
            if (string.IsNullOrEmpty(line)) return null;
            if (line.StartsWith("Application,", StringComparison.OrdinalIgnoreCase) || line.StartsWith("ProcessName,", StringComparison.OrdinalIgnoreCase)) {
                ReadHeader(line);
                return null;
            }
            if (!HasHeader) return null;
            string[] f = line.Split(',');
            if (f.Length <= maxIndex) return null;
            int pid;
            if (!int.TryParse(f[iPid], NumberStyles.Integer, CultureInfo.InvariantCulture, out pid)) return null;
            double frame = Number(f[iFrame]);
            if (double.IsNaN(frame) || frame <= 0 || frame > 10000) return null;
            FrameSample s = new FrameSample();
            s.Application = f[iApp];
            s.ProcessId = pid;
            s.FrameMs = frame;
            s.PresentMode = iMode >= 0 ? f[iMode] : "";
            s.DisplayMs = iDisplay >= 0 ? Number(f[iDisplay]) : double.NaN;
            s.GpuBusyMs = iGpu >= 0 ? Number(f[iGpu]) : double.NaN;
            s.CpuBusyMs = iCpu >= 0 ? Number(f[iCpu]) : double.NaN;
            s.TimeMs = iTime >= 0 ? Number(f[iTime]) * timeScale : double.NaN;
            return s;
        }
    }

    // Last frame times of one process, with the running clock of the game to pick a window.
    public sealed class FrameRing {
        readonly double[] ms;
        readonly double[] end;
        int head, count;
        double clock;
        public FrameRing(int capacity) { ms = new double[capacity]; end = new double[capacity]; }
        public int Count { get { return count; } }
        public double Clock { get { return clock; } }
        public void Add(double frameMs) {
            clock += frameMs;
            ms[head] = frameMs;
            end[head] = clock;
            head = (head + 1) % ms.Length;
            if (count < ms.Length) count++;
        }
        public void Clear() { head = 0; count = 0; clock = 0; }
        // The frames of the last windowMs of game time, oldest first.
        public double[] Window(double windowMs) {
            int n = 0;
            for (int i = 1; i <= count; i++) {
                int idx = (head - i + ms.Length) % ms.Length;
                if (clock - end[idx] >= windowMs) break;
                n++;
            }
            return Last(n);
        }
        public double[] Last(int n) {
            if (n > count) n = count;
            double[] r = new double[n];
            for (int i = 0; i < n; i++) r[i] = ms[(head - n + i + ms.Length) % ms.Length];
            return r;
        }
    }

    public static class FrameMath {
        public static double AverageFps(double[] frameMs) {
            if (frameMs == null || frameMs.Length == 0) return double.NaN;
            double sum = 0;
            foreach (double v in frameMs) sum += v;
            return sum <= 0 ? double.NaN : frameMs.Length * 1000.0 / sum;
        }

        // "1% low" as the average FPS of the slowest 1% of the frames (at least one frame):
        // 1000 / mean of the k longest frame times, k = ceiling(n * fraction).
        public static double LowAverageFps(double[] frameMs, double fraction) {
            if (frameMs == null || frameMs.Length == 0) return double.NaN;
            double[] sorted = (double[])frameMs.Clone();
            Array.Sort(sorted);
            int k = (int)Math.Ceiling(sorted.Length * fraction - 1e-9);
            if (k < 1) k = 1;
            double sum = 0;
            for (int i = sorted.Length - k; i < sorted.Length; i++) sum += sorted[i];
            return 1000.0 / (sum / k);
        }

        // Percentile of the frame times (nearest rank), e.g. 0.99 -> the frame time 99% of the
        // frames are faster than. The "P1" FPS is 1000 / Percentile(ms, 0.99).
        public static double Percentile(double[] values, double p) {
            if (values == null || values.Length == 0) return double.NaN;
            double[] sorted = (double[])values.Clone();
            Array.Sort(sorted);
            int rank = (int)Math.Ceiling(p * sorted.Length);
            if (rank < 1) rank = 1;
            if (rank > sorted.Length) rank = sorted.Length;
            return sorted[rank - 1];
        }

        public static double PercentileFps(double[] frameMs, double fraction) {
            double t = Percentile(frameMs, 1.0 - fraction);
            return double.IsNaN(t) || t <= 0 ? double.NaN : 1000.0 / t;
        }

        // At most `buckets` points for a graph: the slowest frame of each stretch, so a stutter
        // never disappears from the line.
        public static double[] Downsample(double[] values, int buckets) {
            if (values == null || values.Length <= buckets || buckets < 1) return values == null ? new double[0] : values;
            double[] r = new double[buckets];
            for (int b = 0; b < buckets; b++) {
                int from = (int)((long)b * values.Length / buckets), to = (int)((long)(b + 1) * values.Length / buckets);
                double m = values[from];
                for (int i = from + 1; i < to; i++) if (values[i] > m) m = values[i];
                r[b] = m;
            }
            return r;
        }

        public static double Max(double[] values) {
            double m = double.NaN;
            if (values == null) return m;
            foreach (double v in values) if (double.IsNaN(m) || v > m) m = v;
            return m;
        }
    }

    public sealed class FrameStats {
        public string Application;
        public int ProcessId;
        public string PresentMode;
        public double Fps = double.NaN;
        public double Low1 = double.NaN;
        public double Low01 = double.NaN;
        public double FrameMs = double.NaN;
        public double GpuBusyMs = double.NaN;
        public double[] Graph = new double[0];
        public long Frames;
        public double SecondsSinceLastFrame = double.PositiveInfinity;
    }

    public sealed class ProcessFrames {
        public string Application;
        public int ProcessId;
        public string PresentMode = "";
        public FrameRing Ring;
        public long Frames;
        public DateTime LastFrameUtc;
        public double GpuBusyMs = double.NaN;
        public ProcessFrames(string app, int pid, int capacity) { Application = app; ProcessId = pid; Ring = new FrameRing(capacity); }
    }

    // Runs PresentMon and keeps the frames of each process. Feed() is also used by the tests.
    public sealed class PresentMonSession : IDisposable {
        readonly object gate = new object();
        readonly PresentMonParser parser = new PresentMonParser();
        readonly Dictionary<int, ProcessFrames> byPid = new Dictionary<int, ProcessFrames>();
        Process proc;
        Thread reader;
        public int Capacity = 20000;
        public long Lines;
        public string LastError = "";
        public DateTime StartedUtc;

        public bool Running { get { try { return proc != null && !proc.HasExited; } catch { return false; } } }
        public int PresentMonPid { get { try { return proc == null ? 0 : proc.Id; } catch { return 0; } } }

        public void Start(string exe, string arguments) {
            Stop();
            ProcessStartInfo psi = new ProcessStartInfo(exe, arguments);
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            proc = Process.Start(psi);
            StartedUtc = DateTime.UtcNow;
            try { proc.PriorityClass = ProcessPriorityClass.BelowNormal; } catch { }
            proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (!string.IsNullOrEmpty(e.Data)) LastError = e.Data; };
            proc.BeginErrorReadLine();
            Process p = proc;
            reader = new Thread(delegate() {
                try {
                    string line;
                    while ((line = p.StandardOutput.ReadLine()) != null) Feed(line);
                } catch (Exception ex) { LastError = ex.Message; }
            });
            reader.IsBackground = true;
            reader.Name = "PresentMon reader";
            reader.Start();
        }

        // Benchmark: every frame of one process between StartRecording and StopRecording (the ring
        // keeps only the last frames).
        List<double> recording;
        int recordingPid;
        public bool IsRecording { get { lock (gate) { return recording != null; } } }
        public int RecordingPid { get { lock (gate) { return recordingPid; } } }
        public int RecordedFrames { get { lock (gate) { return recording == null ? 0 : recording.Count; } } }
        public void StartRecording(int pid) { lock (gate) { recording = new List<double>(65536); recordingPid = pid; } }
        public double[] StopRecording() {
            lock (gate) {
                double[] r = recording == null ? new double[0] : recording.ToArray();
                recording = null;
                recordingPid = 0;
                return r;
            }
        }

        // The process that drew the most frames in the last `withinSeconds` (the game being played).
        public int BusiestProcess(double withinSeconds, int[] exclude) {
            lock (gate) {
                int best = 0; long most = 0;
                foreach (ProcessFrames pf in byPid.Values) {
                    if ((DateTime.UtcNow - pf.LastFrameUtc).TotalSeconds > withinSeconds) continue;
                    if (exclude != null && Array.IndexOf(exclude, pf.ProcessId) >= 0) continue;
                    if (pf.Frames > most) { most = pf.Frames; best = pf.ProcessId; }
                }
                return best;
            }
        }

        public string ApplicationOf(int pid) { lock (gate) { ProcessFrames pf; return byPid.TryGetValue(pid, out pf) ? pf.Application : ""; } }

        public void Feed(string line) {
            Interlocked.Increment(ref Lines);
            FrameSample s = parser.Parse(line);
            if (s == null) return;
            lock (gate) {
                if (recording != null && s.ProcessId == recordingPid) recording.Add(s.FrameMs);
                ProcessFrames pf;
                if (!byPid.TryGetValue(s.ProcessId, out pf)) { pf = new ProcessFrames(s.Application, s.ProcessId, Capacity); byPid[s.ProcessId] = pf; }
                pf.Ring.Add(s.FrameMs);
                pf.Frames++;
                pf.LastFrameUtc = DateTime.UtcNow;
                if (!string.IsNullOrEmpty(s.PresentMode)) pf.PresentMode = s.PresentMode;
                if (!double.IsNaN(s.GpuBusyMs)) pf.GpuBusyMs = s.GpuBusyMs;
            }
        }

        // Statistics of one process: FPS of the last fpsWindowMs, lows of the last lowsWindowMs and
        // the frame times of the last graphMs for the graph.
        public FrameStats GetStats(int pid, double fpsWindowMs, double lowsWindowMs, double graphMs) {
            FrameStats st = new FrameStats();
            st.ProcessId = pid;
            lock (gate) {
                ProcessFrames pf;
                if (!byPid.TryGetValue(pid, out pf)) return st;
                st.Application = pf.Application;
                st.PresentMode = pf.PresentMode;
                st.Frames = pf.Frames;
                st.GpuBusyMs = pf.GpuBusyMs;
                st.SecondsSinceLastFrame = (DateTime.UtcNow - pf.LastFrameUtc).TotalSeconds;
                double[] recent = pf.Ring.Window(fpsWindowMs);
                st.Fps = FrameMath.AverageFps(recent);
                double sum = 0;
                foreach (double v in recent) sum += v;
                st.FrameMs = recent.Length > 0 ? sum / recent.Length : double.NaN;
                double[] lows = pf.Ring.Window(lowsWindowMs);
                st.Low1 = FrameMath.LowAverageFps(lows, 0.01);
                st.Low01 = FrameMath.LowAverageFps(lows, 0.001);
                st.Graph = pf.Ring.Window(graphMs);
            }
            return st;
        }

        public void Reset(int pid) { lock (gate) { ProcessFrames pf; if (byPid.TryGetValue(pid, out pf)) { pf.Ring.Clear(); pf.Frames = 0; } } }

        public double[] AllFrames(int pid) {
            lock (gate) { ProcessFrames pf; return byPid.TryGetValue(pid, out pf) ? pf.Ring.Last(pf.Ring.Count) : new double[0]; }
        }

        public void Stop() {
            Process p = proc;
            proc = null;
            if (p != null) {
                try { if (!p.HasExited) { p.Kill(); p.WaitForExit(3000); } } catch { }
                try { p.Dispose(); } catch { }
            }
            reader = null;
        }

        public void Dispose() { Stop(); }
    }

    public sealed class MonitorArea {
        public string Device;
        public bool Primary;
        public int Left, Top, Right, Bottom;            // whole monitor, physical pixels
        public int WorkLeft, WorkTop, WorkRight, WorkBottom;
        public uint Dpi = 96;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    public static class Native {
        const int GWL_EXSTYLE = -20;
        public const long WS_EX_TOPMOST = 0x8, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_LAYERED = 0x80000, WS_EX_NOACTIVATE = 0x8000000;
        public const int WM_HOTKEY = 0x0312;

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX info);
        delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data);
        [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);
        [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);
        [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct MONITORINFOEX {
            public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
        }

        // Window the mouse and the keyboard go through, that never takes the focus and stays out
        // of Alt+Tab and the taskbar.
        public static void MakeClickThrough(IntPtr hwnd) {
            long ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
            ex |= WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST;
            SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex));
        }

        public static long GetExStyle(IntPtr hwnd) { return GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64(); }

        // Position in physical pixels, always on top, without activating it.
        public static void PlaceTopmost(IntPtr hwnd, int x, int y) {
            SetWindowPos(hwnd, new IntPtr(-1), x, y, 0, 0, 0x0001 | 0x0010);
        }

        public static bool EnablePerMonitorDpi() {
            try { return SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { return false; }
        }

        // QUNS_RUNNING_D3D_FULL_SCREEN: a game in exclusive full screen owns the display.
        public static bool IsExclusiveFullscreen() {
            int state;
            try { return SHQueryUserNotificationState(out state) == 0 && state == 3; } catch { return false; }
        }

        public static int ForegroundProcessId() {
            uint pid;
            GetWindowThreadProcessId(GetForegroundWindow(), out pid);
            return (int)pid;
        }

        static MonitorArea Read(IntPtr hmon) {
            MONITORINFOEX mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            if (!GetMonitorInfo(hmon, ref mi)) return null;
            MonitorArea a = new MonitorArea();
            a.Device = mi.szDevice; a.Primary = (mi.dwFlags & 1) != 0;
            a.Left = mi.rcMonitor.Left; a.Top = mi.rcMonitor.Top; a.Right = mi.rcMonitor.Right; a.Bottom = mi.rcMonitor.Bottom;
            a.WorkLeft = mi.rcWork.Left; a.WorkTop = mi.rcWork.Top; a.WorkRight = mi.rcWork.Right; a.WorkBottom = mi.rcWork.Bottom;
            uint dx, dy;
            try { if (GetDpiForMonitor(hmon, 0, out dx, out dy) == 0) a.Dpi = dx; } catch { }
            return a;
        }

        public static MonitorArea[] GetMonitors() {
            List<MonitorArea> list = new List<MonitorArea>();
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr h, IntPtr hdc, IntPtr r, IntPtr d) { MonitorArea a = Read(h); if (a != null) list.Add(a); return true; }, IntPtr.Zero);
            return list.ToArray();
        }

        public static MonitorArea MonitorOfWindow(IntPtr hwnd) { return Read(MonitorFromWindow(hwnd, 2)); }
        public static MonitorArea MonitorOfForeground() { return MonitorOfWindow(GetForegroundWindow()); }
    }

    // On-screen text through RivaTuner Statistics Server (optional): RTSS draws it inside the game
    // (RTSS itself hooks the game; Upgrade Tweaks only writes the text into its shared memory).
    public static class Rtss {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr OpenFileMapping(uint access, bool inherit, string name);
        [DllImport("kernel32.dll")] static extern IntPtr MapViewOfFile(IntPtr map, uint access, uint high, uint low, UIntPtr bytes);
        [DllImport("kernel32.dll")] static extern bool UnmapViewOfFile(IntPtr view);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        const uint FILE_MAP_ALL_ACCESS = 0xF001F;

        static bool Use(Func<IntPtr, bool> work) {
            IntPtr map = OpenFileMapping(FILE_MAP_ALL_ACCESS, false, "RTSSSharedMemoryV2");
            if (map == IntPtr.Zero) return false;
            IntPtr view = MapViewOfFile(map, FILE_MAP_ALL_ACCESS, 0, 0, UIntPtr.Zero);
            if (view == IntPtr.Zero) { CloseHandle(map); return false; }
            try {
                uint sig = (uint)Marshal.ReadInt32(view, 0);
                uint ver = (uint)Marshal.ReadInt32(view, 4);
                if (sig != 0x52545353 || ver < 0x00020000) return false;
                return work(view);
            } finally { UnmapViewOfFile(view); CloseHandle(map); }
        }

        public static bool IsRunning() { return Use(delegate(IntPtr v) { return true; }); }

        public static bool Write(string owner, string text) {
            return Use(delegate(IntPtr v) {
                uint ver = (uint)Marshal.ReadInt32(v, 4);
                int entrySize = Marshal.ReadInt32(v, 20), arrOffset = Marshal.ReadInt32(v, 24), arrSize = Marshal.ReadInt32(v, 28);
                for (int pass = 0; pass < 2; pass++) {
                    // Entry 0 belongs to RTSS. First pass: our slot; second pass: take a free one.
                    for (int i = 1; i < arrSize; i++) {
                        IntPtr e = IntPtr.Add(v, arrOffset + i * entrySize);
                        string o = Marshal.PtrToStringAnsi(IntPtr.Add(e, 256));
                        if (pass == 1 && string.IsNullOrEmpty(o)) { WriteAnsi(IntPtr.Add(e, 256), owner, 256); o = owner; }
                        if (o != owner) continue;
                        if (ver >= 0x00020007) WriteAnsi(IntPtr.Add(e, 512), text, 4096); else WriteAnsi(e, text, 256);
                        Marshal.WriteInt32(v, 32, Marshal.ReadInt32(v, 32) + 1);
                        return true;
                    }
                }
                return false;
            });
        }

        public static bool Release(string owner) {
            return Use(delegate(IntPtr v) {
                int entrySize = Marshal.ReadInt32(v, 20), arrOffset = Marshal.ReadInt32(v, 24), arrSize = Marshal.ReadInt32(v, 28);
                bool found = false;
                for (int i = 1; i < arrSize; i++) {
                    IntPtr e = IntPtr.Add(v, arrOffset + i * entrySize);
                    if (Marshal.PtrToStringAnsi(IntPtr.Add(e, 256)) != owner) continue;
                    byte[] zero = new byte[Math.Min(entrySize, 512 + 4096)];
                    Marshal.Copy(zero, 0, e, zero.Length);
                    found = true;
                }
                if (found) Marshal.WriteInt32(v, 32, Marshal.ReadInt32(v, 32) + 1);
                return found;
            });
        }

        static void WriteAnsi(IntPtr dest, string s, int max) {
            byte[] b = Encoding.Default.GetBytes(s == null ? "" : s);
            int n = Math.Min(b.Length, max - 1);
            Marshal.Copy(b, 0, dest, n);
            Marshal.WriteByte(dest, n, 0);
        }
    }
}
'@
}

function Initialize-UTOverlayHotkeyType {
    # Receives WM_HOTKEY in the window of the overlay (needs WPF, so it is compiled apart).
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.Overlay.HotkeyListener' -as [type]) { return }
    $refs = @([System.Windows.Interop.HwndSource].Assembly.Location, [System.Windows.Threading.Dispatcher].Assembly.Location)
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Windows.Interop;

namespace UpgradeTweaks.Overlay {
    public sealed class HotkeyListener {
        readonly ConcurrentQueue<int> pressed = new ConcurrentQueue<int>();
        HwndSource source;
        HwndSourceHook hook;
        public void Attach(IntPtr hwnd) {
            source = HwndSource.FromHwnd(hwnd);
            hook = new HwndSourceHook(Hook);
            source.AddHook(hook);
        }
        IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
            if (msg == 0x0312) { pressed.Enqueue(wParam.ToInt32()); handled = true; }
            return IntPtr.Zero;
        }
        public int[] Drain() {
            List<int> l = new List<int>();
            int id;
            while (pressed.TryDequeue(out id)) l.Add(id);
            return l.ToArray();
        }
        public void Detach() { if (source != null && hook != null) source.RemoveHook(hook); source = null; }
    }
}
'@
}
