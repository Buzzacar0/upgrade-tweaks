# UEFI NVRAM access through the Windows firmware API (no driver): list, read and write the
# variables where the BIOS keeps its settings (Setup, AmdSetup..., CbsSetup...). Reading and
# writing need SeSystemEnvironmentPrivilege, which an elevated administrator token has.

function Initialize-UTFirmwareType {
    [CmdletBinding()]
    param()
    if ('UpgradeTweaks.Firmware' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace UpgradeTweaks {
    public static class Firmware {
        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        struct TOKEN_PRIVILEGES { public int Count; public long Luid; public int Attributes; }
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr process, int access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool LookupPrivilegeValue(string system, string name, out long luid);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int length, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetFirmwareType(out int type);
        [DllImport("ntdll.dll")] static extern int NtEnumerateSystemEnvironmentValuesEx(int infoClass, IntPtr buffer, ref int length);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern int GetFirmwareEnvironmentVariableExW(string name, string guid, byte[] buffer, int size, out int attributes);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool SetFirmwareEnvironmentVariableExW(string name, string guid, byte[] value, int size, int attributes);

        // 0 when the privilege is now enabled, otherwise the Win32 error.
        public static int EnablePrivilege() {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return Marshal.GetLastWin32Error();
            try {
                long luid;
                if (!LookupPrivilegeValue(null, "SeSystemEnvironmentPrivilege", out luid)) return Marshal.GetLastWin32Error();
                var tp = new TOKEN_PRIVILEGES { Count = 1, Luid = luid, Attributes = 2 };
                if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return Marshal.GetLastWin32Error();
                return Marshal.GetLastWin32Error();
            } finally { CloseHandle(token); }
        }

        // 1 = legacy BIOS, 2 = UEFI, 0 = unknown.
        public static int FirmwareType() {
            int t;
            return GetFirmwareType(out t) ? t : 0;
        }

        // VARIABLE_NAME_AND_VALUE records (SystemEnvironmentValueInformation, class 2).
        public static byte[] Enumerate(out int status) {
            int length = 0;
            NtEnumerateSystemEnvironmentValuesEx(2, IntPtr.Zero, ref length);
            if (length <= 0) length = 1 << 20;
            for (int attempt = 0; attempt < 3; attempt++) {
                IntPtr buffer = Marshal.AllocHGlobal(length);
                try {
                    int size = length;
                    status = NtEnumerateSystemEnvironmentValuesEx(2, buffer, ref size);
                    if (status == 0) { var data = new byte[size]; Marshal.Copy(buffer, data, 0, size); return data; }
                    if (size > length) { length = size; continue; }
                    length *= 2;
                } finally { Marshal.FreeHGlobal(buffer); }
            }
            status = -1;
            return new byte[0];
        }

        public static byte[] Read(string name, string guid, out int attributes, out int error) {
            var buffer = new byte[1 << 16];
            int n = GetFirmwareEnvironmentVariableExW(name, guid, buffer, buffer.Length, out attributes);
            if (n <= 0) { error = Marshal.GetLastWin32Error(); return null; }
            error = 0;
            var data = new byte[n];
            Array.Copy(buffer, data, n);
            return data;
        }

        public static int Write(string name, string guid, byte[] value, int attributes) {
            return SetFirmwareEnvironmentVariableExW(name, guid, value, value.Length, attributes) ? 0 : Marshal.GetLastWin32Error();
        }
    }
}
'@
}

function Test-UTUefiFirmware {
    <#
    .SYNOPSIS
        $true when Windows booted in UEFI mode (NVRAM variables only exist there).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    Initialize-UTFirmwareType
    return ([UpgradeTweaks.Firmware]::FirmwareType() -eq 2)
}

function Enable-UTFirmwarePrivilege {
    [CmdletBinding()]
    param()
    Initialize-UTFirmwareType
    $err = [UpgradeTweaks.Firmware]::EnablePrivilege()
    # 1300 (ERROR_NOT_ALL_ASSIGNED): the token does not have it, i.e. not elevated.
    if ($err -ne 0) { throw 'O Windows não liberou o acesso à NVRAM da BIOS. Abra o Upgrade Tweaks como administrador.' }
}

function ConvertFrom-UTUefiVariableBuffer {
    <#
    .SYNOPSIS
        Splits the buffer of NtEnumerateSystemEnvironmentValuesEx into variables:
        NextEntryOffset, ValueOffset, ValueLength, Attributes (4 bytes each), VendorGuid (16),
        Name (UTF-16, zero terminated).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Buffer)
    $offset = 0
    while ($offset + 32 -le $Buffer.Length) {
        $next = [BitConverter]::ToInt32($Buffer, $offset)
        $valueLength = [BitConverter]::ToInt32($Buffer, $offset + 8)
        $attributes = [BitConverter]::ToInt32($Buffer, $offset + 12)
        $guidBytes = New-Object byte[] 16
        [Array]::Copy($Buffer, $offset + 16, $guidBytes, 0, 16)
        $end = $offset + 32
        $limit = $(if ($next -gt 0) { $offset + $next } else { $Buffer.Length })
        while ($end + 1 -lt $limit -and ($Buffer[$end] -ne 0 -or $Buffer[$end + 1] -ne 0)) { $end += 2 }
        [pscustomobject]@{
            Nome      = [Text.Encoding]::Unicode.GetString($Buffer, $offset + 32, $end - $offset - 32)
            Guid      = (New-Object Guid (, $guidBytes)).ToString().ToUpperInvariant()
            Atributos = $attributes
            Tamanho   = $valueLength
        }
        if ($next -le 0) { break }
        $offset += $next
    }
}

function Get-UTUefiVariableList {
    <#
    .SYNOPSIS
        Every NVRAM variable the firmware exposes to Windows: name, GUID, attributes, size.
    #>
    [CmdletBinding()]
    param()
    if (-not (Test-UTUefiFirmware)) { throw 'Este Windows foi instalado em modo Legacy (CSM): não há NVRAM UEFI para ler.' }
    Enable-UTFirmwarePrivilege
    $status = 0
    $buffer = [UpgradeTweaks.Firmware]::Enumerate([ref]$status)
    if ($status -ne 0) { throw ('O firmware não deixou listar as variáveis da NVRAM (código 0x{0:X8}).' -f $status) }
    return @(ConvertFrom-UTUefiVariableBuffer -Buffer $buffer)
}

function Read-UTUefiVariable {
    <#
    .SYNOPSIS
        One NVRAM variable ({Nome, Guid, Atributos, Dados}), or $null when it does not exist or is
        only visible while the PC boots (no runtime access).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][string]$Guid
    )
    Enable-UTFirmwarePrivilege
    $attributes = 0
    $err = 0
    $data = [UpgradeTweaks.Firmware]::Read($Nome, ('{' + $Guid.Trim('{', '}') + '}'), [ref]$attributes, [ref]$err)
    if ($null -eq $data) {
        if ($err -eq 203) { return $null }   # ERROR_ENVVAR_NOT_FOUND
        throw "Não foi possível ler a variável $Nome da NVRAM (erro $err)."
    }
    return [pscustomobject]@{ Nome = $Nome; Guid = $Guid.Trim('{', '}').ToUpperInvariant(); Atributos = $attributes; Dados = $data }
}

function Write-UTUefiVariable {
    <#
    .SYNOPSIS
        Writes a whole NVRAM variable with the attributes it already has. Callers back up the old
        content first; the size never changes (a different size is refused).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][byte[]]$Dados
    )
    Assert-UTAdmin
    $current = Read-UTUefiVariable -Nome $Nome -Guid $Guid
    if ($null -eq $current) { throw "A variável $Nome não está acessível pelo Windows; só dá para mudar dentro da BIOS." }
    if ($current.Dados.Length -ne $Dados.Length) { throw "Tamanho diferente do atual na variável $Nome ($($Dados.Length) em vez de $($current.Dados.Length) bytes): gravação recusada." }
    if (-not $PSCmdlet.ShouldProcess("NVRAM: $Nome", 'Gravar')) { return }
    # Authenticated variables (Secure Boot keys) need signed payloads; never written here.
    if (($current.Atributos -band 0x30) -ne 0) { throw "A variável $Nome é protegida por assinatura (Secure Boot) e não pode ser gravada." }
    $err = [UpgradeTweaks.Firmware]::Write($Nome, ('{' + $current.Guid + '}'), $Dados, $current.Atributos)
    if ($err -ne 0) {
        if ($err -in 5, 19, 1314) { throw "A BIOS bloqueou a gravação de $Nome pelo Windows (proteção do fabricante). Mude essa opção dentro da BIOS." }
        throw "A gravação de $Nome na NVRAM falhou (erro $err)."
    }
    $check = Read-UTUefiVariable -Nome $Nome -Guid $current.Guid
    if ($null -eq $check -or [Convert]::ToBase64String($check.Dados) -ne [Convert]::ToBase64String($Dados)) {
        throw "A NVRAM não confirmou a gravação de $Nome (o valor lido de volta é diferente)."
    }
    Write-UTLog -Level Info -Message "NVRAM: variável $Nome gravada ($($Dados.Length) bytes)."
}
