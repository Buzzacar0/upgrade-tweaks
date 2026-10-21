function ConvertTo-UTHashtable {
    <#
    .SYNOPSIS
        Converts the PSCustomObject graph returned by ConvertFrom-Json (PowerShell 5.1 has no
        -AsHashtable) into ordered hashtables and arrays, recursively.
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)][AllowNull()][object]$InputObject)

    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IDictionary]) {
            $hash = [ordered]@{}
            foreach ($key in $InputObject.Keys) { $hash[$key] = ConvertTo-UTHashtable $InputObject[$key] }
            return $hash
        }
        if ($InputObject -is [string]) { return $InputObject }
        if ($InputObject -is [System.Collections.IEnumerable]) {
            $list = @()
            foreach ($item in $InputObject) { $list += , (ConvertTo-UTHashtable $item) }
            return , $list
        }
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = [ordered]@{}
            foreach ($prop in $InputObject.PSObject.Properties) { $hash[$prop.Name] = ConvertTo-UTHashtable $prop.Value }
            return $hash
        }
        return $InputObject
    }
}

function Read-UTJsonFile {
    <#
    .SYNOPSIS
        Reads a JSON file into hashtables. Returns -Default when the file does not exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Default = $null
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    return (ConvertTo-UTHashtable ($text | ConvertFrom-Json))
}

function Write-UTJsonFile {
    <#
    .SYNOPSIS
        Writes an object as JSON (UTF-8 without BOM) atomically: temp file + replace, so a crash
        in the middle never leaves a half-written state file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowNull()][object]$InputObject,
        [int]$Depth = 12
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Gravar arquivo JSON')) { return }

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }

    $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth
    $temp = "$Path.tmp"
    [IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) {
        # [NullString]::Value: a plain $null would reach .NET as "" and fail as an invalid path.
        [IO.File]::Replace($temp, $Path, [NullString]::Value)
    } else {
        [IO.File]::Move($temp, $Path)
    }
}

function Enter-UTNamedLock {
    <#
    .SYNOPSIS
        Acquires a named mutex shared by all runspaces and processes. Always pair with
        Exit-UTNamedLock in a finally block.
    .NOTES
        Deliberately not a "run this script block under the lock" helper: PowerShell resolves
        variables dynamically, so a script block run inside another function would see that
        function's $Name/$Path instead of the caller's.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSeconds = 30
    )

    $mutex = New-Object System.Threading.Mutex($false, "Local\UpgradeTweaks_$Name")
    $owned = $false
    try {
        $owned = $mutex.WaitOne($TimeoutSeconds * 1000)
    } catch [System.Threading.AbandonedMutexException] {
        $owned = $true
    }
    if (-not $owned) {
        $mutex.Dispose()
        throw "Tempo esgotado esperando o bloqueio '$Name'."
    }
    return $mutex
}

function Exit-UTNamedLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][System.Threading.Mutex]$Mutex)

    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Get-UTField {
    <#
    .SYNOPSIS
        Optional field of a config item (dictionary or object), or -Padrao when it is missing.
        Under Set-StrictMode -Version Latest reading a missing key throws, even on hashtables.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Objeto,
        [Parameter(Mandatory)][string]$Nome,
        [AllowNull()][object]$Padrao = $null
    )
    if ($null -eq $Objeto) { return $Padrao }
    if ($Objeto -is [System.Collections.IDictionary]) {
        if ($Objeto.Contains($Nome)) { return , $Objeto[$Nome] }
        return $Padrao
    }
    $prop = $Objeto.PSObject.Properties[$Nome]
    if ($prop) { return , $prop.Value }
    return $Padrao
}

function Get-UTSum {
    # Sum that also works on an empty list (Measure-Object has no Sum then, which fails in strict mode).
    [CmdletBinding()]
    [OutputType([double])]
    param([AllowNull()][AllowEmptyCollection()][object[]]$Valores)
    $total = 0.0
    foreach ($v in @($Valores)) { if ($null -ne $v) { $total += [double]$v } }
    return $total
}

