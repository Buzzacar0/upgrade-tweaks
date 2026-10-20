# Registry helpers built on Microsoft.Win32.RegistryKey (64-bit view) instead of the PowerShell
# provider: exact value kinds, no environment-variable expansion, default values supported.

function Resolve-UTRegistryPath {
    <#
    .SYNOPSIS
        Parses HKLM:\..., HKCU:\..., HKEY_USERS\..., Registry::HKEY_... into hive + subkey.
    .DESCRIPTION
        When $UTSync.UsuarioAlvoSid is set (the program was elevated with a different admin
        account), HKCU is redirected to HKEY_USERS\<SID of the logged-on user>, so per-user
        tweaks land on the person who is actually going to play.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $clean = $Path.Trim()
    if ($clean -like 'Registry::*') { $clean = $clean.Substring(10) }
    $pattern = '^(?i)(?<hive>HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_USERS|HKEY_CLASSES_ROOT|HKEY_CURRENT_CONFIG|HKLM|HKCU|HKU|HKCR|HKCC):?(?:\\(?<sub>.*))?$'
    $m = [regex]::Match($clean, $pattern)
    if (-not $m.Success) { throw "Caminho de registro inválido: $Path" }

    $map = @{
        'HKLM' = 'LocalMachine'; 'HKEY_LOCAL_MACHINE' = 'LocalMachine'
        'HKCU' = 'CurrentUser'; 'HKEY_CURRENT_USER' = 'CurrentUser'
        'HKU' = 'Users'; 'HKEY_USERS' = 'Users'
        'HKCR' = 'ClassesRoot'; 'HKEY_CLASSES_ROOT' = 'ClassesRoot'
        'HKCC' = 'CurrentConfig'; 'HKEY_CURRENT_CONFIG' = 'CurrentConfig'
    }
    $hiveName = $map[$m.Groups['hive'].Value.ToUpperInvariant()]
    $sub = $m.Groups['sub'].Value.Trim('\')

    $short = @{ LocalMachine = 'HKLM'; CurrentUser = 'HKCU'; Users = 'HKU'; ClassesRoot = 'HKCR'; CurrentConfig = 'HKCC' }[$hiveName]
    $display = "${short}:\$sub".TrimEnd('\')

    $targetSid = Get-UTSyncValue -Key 'UsuarioAlvoSid'
    if ($hiveName -eq 'CurrentUser' -and $targetSid) {
        $hiveName = 'Users'
        $sub = ("$targetSid\$sub").TrimEnd('\')
    }

    $long = @{ LocalMachine = 'HKEY_LOCAL_MACHINE'; CurrentUser = 'HKEY_CURRENT_USER'; Users = 'HKEY_USERS'; ClassesRoot = 'HKEY_CLASSES_ROOT'; CurrentConfig = 'HKEY_CURRENT_CONFIG' }[$hiveName]

    return [pscustomobject]@{
        Hive       = [Microsoft.Win32.RegistryHive]$hiveName
        SubKey     = $sub
        NativePath = ("$long\$sub").TrimEnd('\')
        Display    = $display
    }
}

function Open-UTRegistryKey {
    <#
    .SYNOPSIS
        Opens a key (64-bit view). Returns $null when it does not exist, unless -Create.
        The caller must Dispose() the key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Writable,
        [switch]$Create
    )

    $loc = Resolve-UTRegistryPath -Path $Path
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($loc.Hive, [Microsoft.Win32.RegistryView]::Registry64)
    if ([string]::IsNullOrEmpty($loc.SubKey)) { return $base }
    try {
        if ($Create) { return $base.CreateSubKey($loc.SubKey) }
        return $base.OpenSubKey($loc.SubKey, [bool]$Writable)
    } finally {
        $base.Dispose()
    }
}

function Test-UTRegistryKey {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    $key = Open-UTRegistryKey -Path $Path
    if ($null -eq $key) { return $false }
    $key.Dispose()
    return $true
}

function ConvertTo-UTRegistryData {
    <#
    .SYNOPSIS
        Converts a value from tweaks.json / the state file into the exact .NET type the registry
        expects for the given kind.
    .DESCRIPTION
        DWord accepts 0..4294967295 (also "0xFFFFFFFF") and negative Int32; it is stored as the
        same 32 bits. Binary accepts an array of bytes or a hex string ("01 0A FF" or "010AFF").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type,

        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object]$Value
    )

    switch ($Type) {
        'DWord' {
            $number = ConvertTo-UTInt64 $Value
            if ($number -lt [int32]::MinValue -or $number -gt [uint32]::MaxValue) { throw "Valor fora do intervalo de um DWord: $Value" }
            if ($number -gt [int32]::MaxValue) {
                return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$number), 0)
            }
            return [int32]$number
        }
        'QWord' {
            if ($Value -is [string] -and $Value -match '^0x[0-9a-fA-F]+$') {
                return [BitConverter]::ToInt64([BitConverter]::GetBytes([Convert]::ToUInt64($Value.Substring(2), 16)), 0)
            }
            return [int64](ConvertTo-UTInt64 $Value)
        }
        'String' { return [string]$Value }
        'ExpandString' { return [string]$Value }
        'MultiString' {
            # The leading comma stops PowerShell from unrolling the array on return.
            if ($null -eq $Value) { return , ([string[]]@()) }
            return , ([string[]]@($Value | ForEach-Object { [string]$_ }))
        }
        'Binary' {
            if ($null -eq $Value) { return [byte[]]@() }
            if ($Value -is [string]) {
                $hex = $Value -replace '[\s,\-]', ''
                if ($hex.Length % 2 -ne 0 -or $hex -notmatch '^[0-9a-fA-F]*$') { throw "Valor binário inválido: $Value" }
                $bytes = New-Object byte[] ($hex.Length / 2)
                for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
                return , $bytes
            }
            return , ([byte[]]@($Value | ForEach-Object { [byte]$_ }))
        }
    }
}

function ConvertTo-UTInt64 {
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)][AllowNull()][object]$Value)

    if ($null -eq $Value) { throw 'Valor numérico ausente.' }
    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text -match '^0x[0-9a-fA-F]+$') { return [Convert]::ToInt64($text.Substring(2), 16) }
        return [int64]::Parse($text, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [uint32]) { return [int64]$Value }
    return [int64]$Value
}

function ConvertTo-UTStateValue {
    <#
    .SYNOPSIS
        Converts a raw registry value to something JSON keeps exactly: DWord as unsigned number,
        Binary as hex string, MultiString as string array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Type,
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return $null }
    switch ($Type) {
        'DWord' { return [int64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$Value), 0) }
        'QWord' { return [int64]$Value }
        'Binary' { return (($Value | ForEach-Object { ([byte]$_).ToString('X2') }) -join '') }
        'MultiString' { return , ([string[]]@($Value)) }
        default { return [string]$Value }
    }
}

function Get-UTRegistryValue {
    <#
    .SYNOPSIS
        Reads one value. Always returns an object, also when key or value are missing:
        Caminho, Nome, ChaveExiste, ValorExiste, Tipo, Valor (DWord as unsigned, Binary as hex).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    $result = [pscustomobject]@{
        Caminho     = $Path
        Nome        = $Name
        ChaveExiste = $false
        ValorExiste = $false
        Tipo        = $null
        Valor       = $null
    }

    $key = Open-UTRegistryKey -Path $Path
    if ($null -eq $key) { return $result }
    try {
        $result.ChaveExiste = $true
        if (@($key.GetValueNames()) -contains $Name) {
            $kind = $key.GetValueKind($Name).ToString()
            $raw = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $result.ValorExiste = $true
            $result.Tipo = $kind
            $result.Valor = ConvertTo-UTStateValue -Type $kind -Value $raw
        }
    } finally {
        $key.Dispose()
    }
    return $result
}

function Set-UTRegistryValue {
    <#
    .SYNOPSIS
        Writes one value, creating the key path when needed. Honors -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object]$Value
    )

    $data = ConvertTo-UTRegistryData -Type $Type -Value $Value
    $label = if ($Name) { $Name } else { '(Padrão)' }
    if (-not $PSCmdlet.ShouldProcess("$Path\$label", "Definir $Type = $(ConvertTo-UTLogValue $Value)")) { return }

    $key = Open-UTRegistryKey -Path $Path -Create
    try {
        $key.SetValue($Name, $data, [Microsoft.Win32.RegistryValueKind]$Type)
    } finally {
        $key.Dispose()
    }
}

function Remove-UTRegistryValue {
    <#
    .SYNOPSIS
        Deletes one value if it exists. Returns $true when something was removed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    $key = Open-UTRegistryKey -Path $Path -Writable
    if ($null -eq $key) { return $false }
    try {
        if (-not (@($key.GetValueNames()) -contains $Name)) { return $false }
        if (-not $PSCmdlet.ShouldProcess("$Path\$Name", 'Remover valor do registro')) { return $false }
        $key.DeleteValue($Name, $false)
        return $true
    } finally {
        $key.Dispose()
    }
}

function Get-UTFirstMissingKey {
    <#
    .SYNOPSIS
        Returns the top-most key of the path that does not exist yet (the one a write would
        create), or $null when the whole path exists. Saved in the original state so an undo
        can remove exactly the keys the program created.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (Test-UTRegistryKey -Path $Path) { return $null }
    $loc = Resolve-UTRegistryPath -Path $Path
    $parts = $loc.Display.Split('\')
    $current = $parts[0]
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $current = "$current\$($parts[$i])"
        if (-not (Test-UTRegistryKey -Path $current)) { return $current }
    }
    return $Path
}

function Remove-UTEmptyKeyChain {
    <#
    .SYNOPSIS
        Deletes -Path and then each parent up to -StopAt (inclusive), but only while the key is
        empty (no values, no subkeys). Never touches keys that hold anything else.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$StopAt
    )

    $removed = 0
    $current = (Resolve-UTRegistryPath -Path $Path).Display
    $stop = (Resolve-UTRegistryPath -Path $StopAt).Display
    if (-not $current.StartsWith($stop, [StringComparison]::OrdinalIgnoreCase)) { return 0 }

    while ($true) {
        $key = Open-UTRegistryKey -Path $current
        if ($null -ne $key) {
            $empty = ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0)
            $key.Dispose()
            if (-not $empty) { break }
            $parentPath = $current.Substring(0, $current.LastIndexOf('\'))
            $leaf = $current.Substring($current.LastIndexOf('\') + 1)
            if ($PSCmdlet.ShouldProcess($current, 'Remover chave vazia criada pelo Upgrade Tweaks')) {
                $parent = Open-UTRegistryKey -Path $parentPath -Writable
                if ($null -ne $parent) {
                    try { $parent.DeleteSubKey($leaf, $false) } finally { $parent.Dispose() }
                    $removed++
                }
            }
        }
        if ($current.Equals($stop, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $current.Substring(0, $current.LastIndexOf('\'))
        if ($current -notmatch '\\') { break }
    }
    return $removed
}

function Test-UTRegistryValueEqual {
    <#
    .SYNOPSIS
        True when the value read by Get-UTRegistryValue equals the expected value and kind.
        Strings compare case-insensitively (Windows treats "Deny" and "deny" the same).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][psobject]$Actual,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object]$Expected
    )

    if (-not $Actual.ValorExiste) { return $false }
    if ($Actual.Tipo -ne $Type) { return $false }

    $expectedState = ConvertTo-UTStateValue -Type $Type -Value (ConvertTo-UTRegistryData -Type $Type -Value $Expected)
    switch ($Type) {
        'MultiString' {
            $a = @($Actual.Valor); $e = @($expectedState)
            if ($a.Count -ne $e.Count) { return $false }
            for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -ne $e[$i]) { return $false } }
            return $true
        }
        { $_ -in 'String', 'ExpandString' } {
            return [string]::Equals([string]$Actual.Valor, [string]$expectedState, [StringComparison]::OrdinalIgnoreCase)
        }
        default { return ([string]$Actual.Valor -eq [string]$expectedState) }
    }
}

function Export-UTRegistryKey {
    <#
    .SYNOPSIS
        Exports a key (and subkeys) to a .reg file with reg.exe. Returns the file path, or $null
        when the key does not exist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-UTRegistryKey -Path $Path)) { return $null }
    $loc = Resolve-UTRegistryPath -Path $Path
    if (-not $PSCmdlet.ShouldProcess($loc.NativePath, "Exportar para $Destination")) { return $null }

    $folder = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
    $r = Invoke-UTNative -FilePath 'reg.exe' -ArgumentList @('export', $loc.NativePath, $Destination, '/y', '/reg:64')
    if ($r.CodigoSaida -ne 0) { throw "reg export falhou ($($r.CodigoSaida)): $($r.Erro) $($r.Saida)" }
    return $Destination
}

function Import-UTRegistryFile {
    <#
    .SYNOPSIS
        Imports a .reg file with reg.exe.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)

    if (-not $PSCmdlet.ShouldProcess($Path, 'Importar arquivo .reg')) { return }
    $r = Invoke-UTNative -FilePath 'reg.exe' -ArgumentList @('import', $Path, '/reg:64')
    if ($r.CodigoSaida -ne 0) { throw "reg import falhou ($($r.CodigoSaida)): $($r.Erro) $($r.Saida)" }
}
