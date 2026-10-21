# Helpers used by the scripts inside the tweak catalog (scriptAplicar / scriptDesfazer /
# scriptDetectar). They keep the same guarantees as the engine: .reg backup, real original
# value saved before the first change, undo through the saved state.

function Set-UTRegistryValueTracked {
    <#
    .SYNOPSIS
        Registry write for tweak scripts whose paths are only known at run time (one value per
        game executable, per network interface...). Backs up, saves the original under -TweakId
        and writes. Undo with Restore-UTTweakRegistryItem.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object]$Value,
        [Parameter(Mandatory)][string]$TweakId
    )
    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "Definir $Value")) { return }
    [void](Backup-UTRegistryKey -Path $Path)
    [void](Save-UTOriginalRegistryValue -Path $Path -Name $Name -TweakId $TweakId)
    Set-UTRegistryValue -Path $Path -Name $Name -Type $Type -Value $Value
}

function Restore-UTTweakRegistryItem {
    <#
    .SYNOPSIS
        Puts back every registry value saved under -TweakId (newest first). Returns how many
        were restored. -WhatIf reaches the inner calls through $WhatIfPreference.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$TweakId)

    $count = 0
    foreach ($entry in @(Get-UTOriginalStateItem)) {
        $item = $entry.Item
        if ($item.tipo -ne 'registro' -or @($item.tweaks) -notcontains $TweakId) { continue }
        $status = Restore-UTOriginalRegistryValue -Path $item.caminho -Name $item.nome -TweakId $TweakId
        if ($status -eq 'Restaurado') { $count++ }
    }
    return $count
}

function Get-UTTweakRegistryItem {
    <#
    .SYNOPSIS
        Registry items saved under -TweakId (what a script-based tweak changed).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    foreach ($entry in @(Get-UTOriginalStateItem)) {
        if ($entry.Item.tipo -eq 'registro' -and @($entry.Item.tweaks) -contains $TweakId) { $entry.Item }
    }
}

function Get-UTGameExecutable {
    <#
    .SYNOPSIS
        Full paths of the Call of Duty executables found by the diagnostic.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([psobject]$Contexto)
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    return @($Contexto.Executaveis | Where-Object { $_ } | Sort-Object -Unique)
}

function Merge-UTFlagString {
    <#
    .SYNOPSIS
        Sets Key=Value inside a "Key=Value;Key2=Value2;" string (DirectX user settings) without
        touching the other flags.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    $pairs = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($part in @(([string]$Text).Split(';') | Where-Object { $_.Trim() })) {
        $k = $part.Split('=')[0].Trim()
        if ($k -ieq $Key) { $pairs.Add("$Key=$Value"); $found = $true } else { $pairs.Add($part.Trim()) }
    }
    if (-not $found) { $pairs.Add("$Key=$Value") }
    return (($pairs -join ';') + ';')
}

function Get-UTFlagString {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Key)
    foreach ($part in @(([string]$Text).Split(';'))) {
        $kv = $part.Split('=')
        if ($kv[0].Trim() -ieq $Key -and $kv.Count -gt 1) { return $kv[1].Trim() }
    }
    return $null
}

function Add-UTCompatLayerFlag {
    <#
    .SYNOPSIS
        Adds a flag to an AppCompatFlags\Layers value ("~ FLAG1 FLAG2") keeping the others.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Flag)
    $flags = @(([string]$Text).Split(' ') | Where-Object { $_ -and $_ -ne '~' })
    if ($flags -notcontains $Flag) { $flags += $Flag }
    return ('~ ' + ($flags -join ' '))
}

function Set-UTGameRegistryFlag {
    <#
    .SYNOPSIS
        For each game executable, sets a per-executable registry value (named after the full
        path) to the result of -Transform applied to the current text. Shared by the GPU
        preference and fullscreen-optimization tweaks.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('GpuPreference', 'DisableFso')][string]$Mode,
        [Parameter(Mandatory)][string]$TweakId,
        [psobject]$Contexto
    )
    $exes = @(Get-UTGameExecutable -Contexto $Contexto)
    if ($exes.Count -eq 0) { throw 'Call of Duty não encontrado; nada a ajustar.' }
    foreach ($exe in $exes) {
        $current = Get-UTRegistryValue -Path $Path -Name $exe
        $text = $(if ($current.ValorExiste) { [string]$current.Valor } else { '' })
        $new = $(if ($Mode -eq 'GpuPreference') { Merge-UTFlagString -Text $text -Key 'GpuPreference' -Value '2' } else { Add-UTCompatLayerFlag -Text $text -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' })
        Set-UTRegistryValueTracked -Path $Path -Name $exe -Type String -Value $new -TweakId $TweakId
    }
}

function Test-UTGameRegistryFlag {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('GpuPreference', 'DisableFso')][string]$Mode,
        [psobject]$Contexto
    )
    $exes = @(Get-UTGameExecutable -Contexto $Contexto)
    if ($exes.Count -eq 0) { return $false }
    foreach ($exe in $exes) {
        $v = Get-UTRegistryValue -Path $Path -Name $exe
        if (-not $v.ValorExiste) { return $false }
        if ($Mode -eq 'GpuPreference' -and (Get-UTFlagString -Text ([string]$v.Valor) -Key 'GpuPreference') -ne '2') { return $false }
        if ($Mode -eq 'DisableFso' -and ([string]$v.Valor) -notmatch '\bDISABLEDXMAXIMIZEDWINDOWEDMODE\b') { return $false }
    }
    return $true
}

function Set-UTGameIfeoPriority {
    <#
    .SYNOPSIS
        Image File Execution Options\<exe>\PerfOptions\CpuPriorityClass = 3 (High) for each game
        executable name. A Windows setting: the game files are not touched.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId, [psobject]$Contexto)
    $names = @(Get-UTGameExecutable -Contexto $Contexto | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
    if ($names.Count -eq 0) { throw 'Call of Duty não encontrado; nada a ajustar.' }
    foreach ($n in $names) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$n\PerfOptions"
        Set-UTRegistryValueTracked -Path $path -Name 'CpuPriorityClass' -Type DWord -Value 3 -TweakId $TweakId
    }
}

function Test-UTGameIfeoPriority {
    [CmdletBinding()]
    [OutputType([bool])]
    param([psobject]$Contexto)
    $names = @(Get-UTGameExecutable -Contexto $Contexto | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
    if ($names.Count -eq 0) { return $false }
    foreach ($n in $names) {
        $v = Get-UTRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$n\PerfOptions" -Name 'CpuPriorityClass'
        if (-not ($v.ValorExiste -and [int]$v.Valor -eq 3)) { return $false }
    }
    return $true
}

function Set-UTDirectXGlobalFlag {
    <#
    .SYNOPSIS
        Sets one flag inside DirectXUserGlobalSettings ("SwapEffectUpgradeEnable=1;...") keeping
        the user's other DirectX flags (Auto HDR, VRR optimizations...).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$TweakId
    )
    $path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $current = Get-UTRegistryValue -Path $path -Name 'DirectXUserGlobalSettings'
    $text = $(if ($current.ValorExiste) { [string]$current.Valor } else { '' })
    Set-UTRegistryValueTracked -Path $path -Name 'DirectXUserGlobalSettings' -Type String -Value (Merge-UTFlagString -Text $text -Key $Key -Value $Value) -TweakId $TweakId
}

function Test-UTDirectXGlobalFlag {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    $v = Get-UTRegistryValue -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings'
    return ($v.ValorExiste -and (Get-UTFlagString -Text ([string]$v.Valor) -Key $Key) -eq $Value)
}
