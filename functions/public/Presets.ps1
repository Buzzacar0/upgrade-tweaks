# Presets (config\presets.json) and the exported selection files used to standardize the
# service at the store: the same JSON goes to "-Config" on the command line or to "Importar
# seleção" in the interface.

function Get-UTPresetName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @((Get-UTConfig -Name 'presets').presets | ForEach-Object { [string]$_.nome })
}

function Get-UTPreset {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Nome)
    $p = @((Get-UTConfig -Name 'presets').presets | Where-Object { $_.nome -eq $Nome })
    if ($p.Count -eq 0) { throw "Preset '$Nome' não existe. Use: $((Get-UTPresetName) -join ', ')." }
    return $p[0]
}

function Get-UTPresetTweakId {
    <#
    .SYNOPSIS
        Tweak ids of a preset (with the ones it inherits), in catalog order. -LinhaDeComando
        leaves out what needs someone at the screen (monitor refresh rate: 15 s confirmation).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [switch]$LinhaDeComando
    )
    $cfg = Get-UTConfig -Name 'presets'
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seen = @{}
    $current = Get-UTPreset -Nome $Nome
    while ($current) {
        if ($seen.ContainsKey($current.nome)) { throw "Preset '$Nome': herança circular." }
        $seen[$current.nome] = $true
        foreach ($id in @($current.ajustes)) { [void]$ids.Add([string]$id) }
        $current = $(if ($current.herda) { Get-UTPreset -Nome $current.herda } else { $null })
    }
    foreach ($never in @($cfg.nuncaEmPreset)) { [void]$ids.Remove([string]$never) }
    if ($LinhaDeComando) { foreach ($x in @($cfg.foraDaLinhaDeComando)) { [void]$ids.Remove([string]$x) } }
    return @(Get-UTTweak | Where-Object { $ids.Contains([string]$_.id) } | ForEach-Object { [string]$_.id })
}

function Get-UTPresetSelection {
    <#
    .SYNOPSIS
        What the interface needs to mark a preset: ids and whether it asks for typed confirmation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Nome, [switch]$LinhaDeComando)
    $p = Get-UTPreset -Nome $Nome
    return [pscustomobject]@{
        Nome             = [string]$p.nome
        Descricao        = [string]$p.descricao
        Ids              = @(Get-UTPresetTweakId -Nome $Nome -LinhaDeComando:$LinhaDeComando)
        ExigeConfirmacao = [bool]$p.exigeConfirmacao
        TextoConfirmacao = $(if ($p.textoConfirmacao) { [string]$p.textoConfirmacao } else { 'EU ENTENDO' })
        Aviso            = [string]$p.aviso
    }
}

function Export-UTSelection {
    <#
    .SYNOPSIS
        Saves a list of tweak ids as JSON (to repeat the same setup on other PCs).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Id,
        [Parameter(Mandatory)][string]$Caminho,
        [string]$Descricao = ''
    )
    $known = @(Get-UTTweak | ForEach-Object { [string]$_.id })
    $ids = @($Id | Where-Object { $known -contains $_ })
    $data = [ordered]@{
        programa  = 'Upgrade Tweaks'
        versao    = [string](Get-UTSyncValue -Key 'Versao')
        criadoEm  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        descricao = $Descricao
        ajustes   = $ids
    }
    if (-not $PSCmdlet.ShouldProcess($Caminho, "Salvar seleção com $($ids.Count) ajustes")) { return $null }
    $dir = Split-Path -Parent $Caminho
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Caminho, ($data | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    Write-UTLog -Level Sucesso -Message "Seleção com $($ids.Count) ajustes salva em $Caminho."
    return $Caminho
}

function Import-UTSelection {
    <#
    .SYNOPSIS
        Reads a selection file: the exported format ({ "ajustes": [...] }) or a plain list of
        ids. Unknown ids (from another version) are reported, not applied.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { throw "Arquivo de seleção não encontrado: $Caminho" }
    try { $data = Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "O arquivo $Caminho não é um JSON válido." }
    $list = $(if ($data -is [array]) { $data } elseif ($data.PSObject.Properties['ajustes']) { $data.ajustes } else { $null })
    if ($null -eq $list) { throw "O arquivo $Caminho não tem a lista ""ajustes""." }
    $wanted = @($list | ForEach-Object { [string]$_ } | Where-Object { $_ })
    $known = @(Get-UTTweak | ForEach-Object { [string]$_.id })
    $unknown = @($wanted | Where-Object { $known -notcontains $_ })
    if ($unknown.Count -gt 0) { Write-UTLog -Level Aviso -Message "Ajustes desconhecidos nesta versão foram ignorados: $($unknown -join ', ')" }
    $ordered = @(Get-UTTweak | Where-Object { $wanted -contains [string]$_.id } | ForEach-Object { [string]$_.id })
    return [pscustomobject]@{ Ids = $ordered; Desconhecidos = $unknown; Descricao = $(if ($data -isnot [array] -and $data.PSObject.Properties['descricao']) { [string]$data.descricao } else { '' }) }
}
