function Get-UTSourceRoot {
    <#
    .SYNOPSIS
        Repository folder when running from source (development and tests). Functions copied
        into background runspaces have no $PSScriptRoot, so the path also lives in $UTSync.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($PSScriptRoot) { return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
    $root = Get-UTSyncValue -Key 'RaizRepositorio'
    if ($root) { return [string]$root }
    return [string](Get-Location)
}

function Add-UTConfigDefault {
    <#
    .SYNOPSIS
        Fills the optional fields of the items of a config file, so the code can read them
        directly (reading a missing key fails under Set-StrictMode -Version Latest).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Config)
    if ($Config -isnot [System.Collections.IDictionary]) { return }
    $lists = @()
    switch ($Name) {
        'programs' { $lists += , @(@($Config['programas']), @{ cpu = @(); gpu = @(); winget = ''; github = $null; somentePagina = $false; aviso = ''; pastas = @(); executaveis = @(); site = '' }) }
        'nvidia-drs' { $lists += , @(@($Config['configuracoes']), @{ tipo = ''; recomendado = $null; opcoes = $null; naoDocumentado = $false; ids = @(); nomeApp = ''; explicacao = '' }) }
        'bios-guia' { $lists += , @(@($Config['itens']), @{ cpu = @(); x3d = $false; verificacao = ''; aviso = '' }) }
        'bios-ajustes' { $lists += , @(@($Config['itens']), @{ cpu = @(); verificacao = ''; recomendado = '' }) }
        'presets' { $lists += , @(@($Config['presets']), @{ herda = ''; exigeConfirmacao = $false; textoConfirmacao = ''; aviso = ''; recomendado = $false; ajustes = @() }) }
        'cpu-x3d' { $lists += , @(@($Config['modelos']), @{ vcacheNosDois = $false }) }
        'powerplan' { $lists += , @(@($Config['configuracoes']), @{ configuravel = $false; opcional = $false; pularX3DDuplo = $false }) }
        'modo-partida' { $lists += , @(@($Config['processos']), @{ marcado = $false; reabrir = $false; grupo = '' }) }
        'warzone-guia' {
            if ($Config['perfis'] -is [System.Collections.IDictionary]) {
                foreach ($k in @($Config['perfis'].Keys)) { $lists += , @(@($Config['perfis'][$k]['itens']), @{ porGpu = $null; porVram = $null; motivo = ''; arquivo = @(); arquivoPorGpu = $null; arquivoPorVram = $null; regra = '' }) }
            }
        }
    }
    foreach ($pair in $lists) {
        foreach ($item in @($pair[0])) {
            if ($item -isnot [System.Collections.IDictionary]) { continue }
            foreach ($k in $pair[1].Keys) { if (-not $item.Contains($k)) { $item[$k] = $pair[1][$k] } }
        }
    }
}

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
        $file = Join-Path (Get-UTSourceRoot) "config\$Name.json"
        if (Test-Path -LiteralPath $file) { $json = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) }
    }
    if ($null -eq $json) { throw "Configuração '$Name' não encontrada." }

    $data = ConvertTo-UTHashtable ($json | ConvertFrom-Json)
    Add-UTConfigDefault -Name $Name -Config $data
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
            $dir = Join-Path (Get-UTSourceRoot) 'config'
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
            Add-UTTweakDefault -Tweak $t
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
