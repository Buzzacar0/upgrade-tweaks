function Initialize-UTMemoryListType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.MemoryList' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace UpgradeTweaks {
    public static class MemoryList {
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        struct TOKEN_PRIVILEGES { public int Count; public long Luid; public int Attributes; }
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr process, int access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool LookupPrivilegeValue(string system, string name, out long luid);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int length, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, ref int info, int length);

        // SystemMemoryListInformation (80) with MemoryPurgeStandbyList (4). Returns the NTSTATUS.
        public static int PurgeStandby() {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return Marshal.GetLastWin32Error();
            try {
                long luid;
                if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid)) return Marshal.GetLastWin32Error();
                var tp = new TOKEN_PRIVILEGES { Count = 1, Luid = luid, Attributes = 2 };
                AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            } finally { CloseHandle(token); }
            int command = 4;
            return NtSetSystemInformation(80, ref command, 4);
        }
    }
}
'@
}

function Clear-UTStandbyList {
    <#
    .SYNOPSIS
        Empties the standby memory list (cached files the Windows keeps in RAM). Honestly: Windows
        already gives that memory to the game when it needs it; this only helps in the rare cases
        where the cache does not shrink fast enough. Optional in the Modo Partida.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess('memória em espera', 'Esvaziar')) { return }
    Initialize-UTMemoryListType
    $status = [UpgradeTweaks.MemoryList]::PurgeStandby()
    if ($status -ne 0) { throw "O Windows não permitiu esvaziar a memória em espera (código 0x$('{0:X8}' -f $status))." }
    Write-UTLog -Level Info -Message 'Memória em espera esvaziada.'
}
