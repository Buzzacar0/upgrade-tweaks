function Get-UTConfig {
    <#
    .SYNOPSIS
        Returns a config file (config\<Name>.json) as hashtables, cached per session.
    .DESCRIPTION
        Lookup order:
          1. UPGRADETWEAKS_CONFIG_DIR (tests point it to tests\fixtures)
          2. $UTEmbeddedConfig, filled by compile.ps1 in the single-file build
          3. config\ of the repository (development)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$SemCache
    )

    $cache = Get-UTSyncValue -Key 'ConfigCache'
    $overrideDir = $env:UPGRADETWEAKS_CONFIG_DIR
    $cacheKey = "$overrideDir|$Name"
    if (-not $SemCache -and $null -ne $cache -and $cache.ContainsKey($cacheKey)) { return $cache[$cacheKey] }

    $json = $null
    if ($overrideDir) {
        $file = Join-Path $overrideDir "$Name.json"
        if (Test-Path -LiteralPath $file) { $json = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) }
    }
    if ($null -eq $json) {
        $embedded = Get-Variable -Name UTEmbeddedConfig -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $embedded -and $embedded.ContainsKey($Name)) { $json = $embedded[$Name] }
    }
    if ($null -eq $json) {
        $file = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "config\$Name.json"
        if (Test-Path -LiteralPath $file) { $json = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) }
    }
    if ($null -eq $json) { throw "Configuração '$Name' não encontrada." }

    $data = ConvertTo-UTHashtable ($json | ConvertFrom-Json)
    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $sync) {
        if ($null -eq $cache) {
            $cache = [hashtable]::Synchronized(@{})
            $sync['ConfigCache'] = $cache
        }
        $cache[$cacheKey] = $data
    }
    return $data
}

function Get-UTConfigName {
    <#
    .SYNOPSIS
        Names of the available config files that start with -Prefixo ("tweaks" -> tweaks,
        tweaks-gaming, tweaks-rede...). Uses the same source order as Get-UTConfig; when
        UPGRADETWEAKS_CONFIG_DIR is set (tests), only that folder counts.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Prefixo)

    $names = @()
    $overrideDir = $env:UPGRADETWEAKS_CONFIG_DIR
    if ($overrideDir) {
        $names = @(Get-ChildItem -LiteralPath $overrideDir -Filter '*.json' -File | ForEach-Object { $_.BaseName })
    } else {
        $embedded = Get-Variable -Name UTEmbeddedConfig -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $embedded -and $embedded.Count -gt 0) {
            $names = @($embedded.Keys)
        } else {
            $dir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config'
            if (Test-Path -LiteralPath $dir) { $names = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | ForEach-Object { $_.BaseName }) }
        }
    }
    $pattern = '^' + [regex]::Escape($Prefixo) + '(-.+)?$'
    return @($names | Where-Object { $_ -match $pattern } | Sort-Object)
}

function Test-UTConfigFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)
    return (@(Get-UTConfigName -Prefixo $Name) -contains $Name)
}

function Get-UTTweak {
    <#
    .SYNOPSIS
        Tweak definitions from tweaks.json. -Id filters (order of -Id is kept).
        Invalid definitions are dropped with an error in the log.
    #>
    [CmdletBinding()]
    param([string[]]$Id)

    $cache = Get-UTSyncValue -Key 'ConfigCache'
    $cacheKey = "$($env:UPGRADETWEAKS_CONFIG_DIR)|tweaks-validos"
    $valid = $null
    if ($null -ne $cache -and $cache.ContainsKey($cacheKey)) { $valid = $cache[$cacheKey] }
    if ($null -eq $valid) {
        $all = New-Object System.Collections.Generic.List[object]
        foreach ($name in @(Get-UTConfigName -Prefixo 'tweaks')) {
            foreach ($t in @((Get-UTConfig -Name $name).tweaks)) { $all.Add($t) }
        }
        foreach ($t in @(Get-UTGeneratedTweak)) { $all.Add($t) }
        $valid = New-Object System.Collections.Generic.List[object]
        $seen = @{}
        foreach ($t in $all) {
            $errors = @(Test-UTTweakDefinition -Tweak $t)
            if ($errors.Count -eq 0 -and $seen.ContainsKey([string]$t.id)) { $errors = @('id duplicado') }
            if ($errors.Count -gt 0) {
                Write-UTLog -Level Erro -TweakId ([string]$t.id) -Message 'Definição de tweak inválida; ele foi ignorado.' -Detalhe ($errors -join ' | ')
                continue
            }
            $seen[[string]$t.id] = $true
            $valid.Add($t)
        }
        if ($null -eq $cache) { $cache = Get-UTSyncValue -Key 'ConfigCache' }  # Get-UTConfig may have just created it
        if ($null -ne $cache) { $cache[$cacheKey] = $valid }
    }

    if (-not $Id) { return $valid.ToArray() }
    $result = foreach ($wanted in $Id) {
        $found = $valid | Where-Object { $_.id -eq $wanted } | Select-Object -First 1
        if ($null -eq $found) { throw "Tweak '$wanted' não existe no catálogo." }
        $found
    }
    return $result
}
