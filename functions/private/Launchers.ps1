# Finds where Call of Duty (Warzone / CoD HQ) is installed: Steam, Battle.net or Xbox App /
# Game Pass. Only reads paths and file names; never touches game files.

function Get-UTSteamLibrary {
    <#
    .SYNOPSIS
        Steam library folders, parsed from steamapps\libraryfolders.vdf.
    #>
    [CmdletBinding()]
    param([string]$SteamPath)

    if (-not $SteamPath) {
        $v = Get-UTRegistryValue -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath'
        if ($v.ValorExiste) { $SteamPath = [string]$v.Valor }
    }
    if (-not $SteamPath) {
        $v = Get-UTRegistryValue -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name 'InstallPath'
        if ($v.ValorExiste) { $SteamPath = [string]$v.Valor }
    }
    if (-not $SteamPath) { return @() }
    $SteamPath = $SteamPath.Replace('/', '\')

    $libraries = New-Object System.Collections.Generic.List[string]
    $libraries.Add($SteamPath)
    $vdf = Join-Path $SteamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw -Encoding UTF8), '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value.Replace('\\', '\')
            if (-not ($libraries | Where-Object { $_ -ieq $p })) { $libraries.Add($p) }
        }
    }
    return $libraries.ToArray()
}

function Get-UTSteamCodInstall {
    [CmdletBinding()]
    param([string[]]$Bibliotecas = (Get-UTSteamLibrary))

    # 1938090 = Call of Duty HQ (Warzone, MW, BO); 1962663 = old standalone Warzone entry.
    foreach ($lib in $Bibliotecas) {
        foreach ($appId in '1938090', '1962663') {
            $manifest = Join-Path $lib "steamapps\appmanifest_$appId.acf"
            if (-not (Test-Path -LiteralPath $manifest)) { continue }
            $m = [regex]::Match((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8), '"installdir"\s+"([^"]+)"')
            if (-not $m.Success) { continue }
            $path = Join-Path $lib ("steamapps\common\" + $m.Groups[1].Value)
            if (Test-Path -LiteralPath $path) {
                [pscustomobject]@{ Launcher = 'steam'; Caminho = $path }
            }
        }
    }
}

function Get-UTUninstallEntry {
    [CmdletBinding()]
    param()
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($root in $roots) {
        $key = Open-UTRegistryKey -Path $root
        if ($null -eq $key) { continue }
        try { $names = $key.GetSubKeyNames() } finally { $key.Dispose() }
        foreach ($n in $names) {
            $name = Get-UTRegistryValue -Path "$root\$n" -Name 'DisplayName'
            if (-not $name.ValorExiste) { continue }
            [pscustomobject]@{
                Chave      = $n
                Nome       = [string]$name.Valor
                Fabricante = [string](Get-UTRegistryValue -Path "$root\$n" -Name 'Publisher').Valor
                Local      = [string](Get-UTRegistryValue -Path "$root\$n" -Name 'InstallLocation').Valor
            }
        }
    }
}

function Get-UTBattleNetCodInstall {
    [CmdletBinding()]
    param([object[]]$Entradas = @(Get-UTUninstallEntry))

    $seen = @{}
    foreach ($e in $Entradas) {
        if ($e.Nome -notmatch 'Call of Duty') { continue }
        if ($e.Chave -like 'Steam App *') { continue }
        if ($e.Fabricante -and $e.Fabricante -notmatch 'Blizzard|Activision|Infinity Ward|Treyarch|Raven') { continue }
        $path = ([string]$e.Local).Trim('"').TrimEnd('\')
        if (-not $path -or $seen.ContainsKey($path.ToLowerInvariant()) -or -not (Test-Path -LiteralPath $path)) { continue }
        $seen[$path.ToLowerInvariant()] = $true
        [pscustomobject]@{ Launcher = 'battlenet'; Caminho = $path }
    }
    $default = Join-Path ${env:ProgramFiles(x86)} 'Call of Duty'
    if (${env:ProgramFiles(x86)} -and (Test-Path -LiteralPath $default) -and -not $seen.ContainsKey($default.ToLowerInvariant())) {
        [pscustomobject]@{ Launcher = 'battlenet'; Caminho = $default }
    }
}

function Get-UTXboxCodInstall {
    <#
    .SYNOPSIS
        Game Pass / Xbox App installs live in <drive>:\XboxGames\<game>\Content (the WindowsApps
        copy is protected). Looks for "Call of Duty*" there on every fixed drive.
    #>
    [CmdletBinding()]
    param([string[]]$Raizes = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName }))

    foreach ($root in $Raizes) {
        $xbox = Join-Path $root 'XboxGames'
        if (-not (Test-Path -LiteralPath $xbox)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $xbox -Directory -Filter 'Call of Duty*' -ErrorAction SilentlyContinue)) {
            $content = Join-Path $dir.FullName 'Content'
            $path = $dir.FullName
            if (Test-Path -LiteralPath $content) { $path = $content }
            [pscustomobject]@{ Launcher = 'xbox'; Caminho = $path }
        }
    }
}

function Get-UTCodExecutable {
    <#
    .SYNOPSIS
        Game executables in an install folder: cod.exe (CoD HQ) and the per-title ones like
        cod25-cod.exe, sp26-cod.exe. Crash handlers, installers and helpers are ignored.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Caminho)

    if (-not (Test-Path -LiteralPath $Caminho)) { return @() }
    $candidates = @(Get-ChildItem -LiteralPath $Caminho -Filter '*.exe' -File -ErrorAction SilentlyContinue)
    foreach ($sub in @(Get-ChildItem -LiteralPath $Caminho -Directory -ErrorAction SilentlyContinue)) {
        $candidates += @(Get-ChildItem -LiteralPath $sub.FullName -Filter '*.exe' -File -ErrorAction SilentlyContinue)
    }
    $result = $candidates | Where-Object {
        $_.Name -match '^(?i)(cod|(cod|sp|mp)\d{2}-cod|ModernWarfare|BlackOps\w*)\.exe$'
    } | ForEach-Object { $_.FullName } | Sort-Object -Unique
    return @($result)
}

function Get-UTGameInfo {
    <#
    .SYNOPSIS
        Every Call of Duty install found, with launcher, folder, executables and the disk it is on,
        plus which launchers are installed at all.
    #>
    [CmdletBinding()]
    param([psobject]$Armazenamento)

    $installs = @()
    $installs += @(Get-UTSteamCodInstall)
    $installs += @(Get-UTBattleNetCodInstall)
    $installs += @(Get-UTXboxCodInstall)

    $result = foreach ($i in $installs) {
        if ($null -eq $i) { continue }
        $drive = $null
        if ($Armazenamento) { $drive = Get-UTDriveOfPath -Path $i.Caminho -Armazenamento $Armazenamento }
        [pscustomobject]@{
            Launcher     = $i.Launcher
            Caminho      = $i.Caminho
            Executaveis  = @(Get-UTCodExecutable -Caminho $i.Caminho)
            Disco        = $drive
        }
    }

    $entries = @(Get-UTUninstallEntry)
    $installedLaunchers = New-Object System.Collections.Generic.List[string]
    if (@(Get-UTSteamLibrary).Count -gt 0) { $installedLaunchers.Add('steam') }
    if (@($entries | Where-Object { $_.Nome -eq 'Battle.net' }).Count -gt 0) { $installedLaunchers.Add('battlenet') }
    if (Get-AppxPackage -Name 'Microsoft.GamingApp' -ErrorAction SilentlyContinue) { $installedLaunchers.Add('xbox') }

    return [pscustomobject]@{
        Instalacoes          = @($result)
        Launchers            = @(@($result) | ForEach-Object { $_.Launcher } | Sort-Object -Unique)
        LaunchersInstalados  = $installedLaunchers.ToArray()
    }
}
