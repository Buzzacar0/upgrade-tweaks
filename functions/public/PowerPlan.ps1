# "Energia" tab: Windows' own Maximum Performance plan (Ultimate Performance), the dual-CCD Ryzen
# X3D path, the optional per-setting adjustments over the active plan and the plan tools.
# Activating the plan is the catalog tweak UT_Power_DesempenhoMaximo, so it gets restore point,
# journal and "Desfazer TUDO" like every other tweak; the functions below are what its scripts
# call. The *Core functions take no -WhatIf: the engine never runs tweak scripts in simulation
# mode, it lists the planned actions instead.

#region Maximum Performance
function Find-UTMaxPerformanceScheme {
    <#
    .SYNOPSIS
        GUID of the Maximum Performance plan on this PC, or $null when it is hidden.
    .DESCRIPTION
        In order: the built-in scheme itself (e9a42b02-...) when it is listed, the copy the
        Upgrade Tweaks unlocked earlier (original state), and any plan with the Windows name of
        it (a copy unlocked by hand or by another tool). Never creates anything.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][object[]]$Planos)
    $cfg = Get-UTConfig -Name 'powerplan'
    $schemes = $(if ($null -ne $Planos) { @($Planos) } else { @(Get-UTPowerSchemeList) })
    $builtIn = (@($schemes | Where-Object { $_.Guid -eq $cfg.desempenhoMaximo }) | Select-Object -First 1)
    if ($builtIn) { return [string]$builtIn.Guid }
    $saved = Get-UTOriginalItem -Chave 'generico|energia|planomaximo'
    if ($saved -and $saved.dados.guid -and -not $saved.dados.alternativo -and @($schemes | Where-Object { $_.Guid -eq $saved.dados.guid }).Count -gt 0) {
        return [string]$saved.dados.guid
    }
    $names = @($cfg.nomesDesempenhoMaximo | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $byName = (@($schemes | Where-Object { $names -contains ([string]$_.Nome).ToLowerInvariant() }) | Select-Object -First 1)
    if ($byName) { return [string]$byName.Guid }
    return $null
}

function Invoke-UTMaxPerformanceCore {
    <#
    .SYNOPSIS
        Activates Windows' Maximum Performance plan. Called by UT_Power_DesempenhoMaximo.
    .DESCRIPTION
        Already listed: only activates it. Hidden (common on Windows 11 and notebooks): unlocks it
        once with powercfg -duplicatescheme, keeping the Windows name, and activates the copy;
        clicking again reuses that copy instead of creating another. When the Windows edition
        refuses, falls back to High Performance. Dual-CCD Ryzen X3D: refuses (Balanced is needed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [psobject]$Contexto
    )
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    if ($Contexto.X3D -eq 'duplo') {
        throw 'Ryzen X3D de dois CCDs: o Desempenho Máximo não é usado. Use o ajuste "Manter o plano Equilibrado (Ryzen X3D de dois CCDs)".'
    }
    $cfg = Get-UTConfig -Name 'powerplan'
    $schemes = @(Get-UTPowerSchemeList)
    $active = Get-UTActivePowerScheme
    [void](Backup-UTActivePowerPlan)

    $guid = Find-UTMaxPerformanceScheme -Planos $schemes
    $created = $false
    $fallback = $false
    if (-not $guid) {
        try {
            $guid = Copy-UTPowerScheme -Base $cfg.desempenhoMaximo
            $created = [bool]$guid
            if ($created) { Write-UTLog -Level Info -TweakId $TweakId -Message 'Desempenho Máximo liberado (powercfg -duplicatescheme).' }
        } catch {
            Write-UTLog -Level Aviso -TweakId $TweakId -Message 'Este Windows não liberou o Desempenho Máximo; usando o Alto Desempenho.' -Detalhe $_.Exception.Message
        }
    }
    if (-not $guid) {
        $fallback = $true
        if (@($schemes | Where-Object { $_.Guid -eq $cfg.altoDesempenho }).Count -gt 0) {
            $guid = $cfg.altoDesempenho
        } else {
            try { $guid = Copy-UTPowerScheme -Base $cfg.altoDesempenho; $created = [bool]$guid } catch { $guid = $null }
        }
        if (-not $guid) { throw 'Este Windows não permite o Desempenho Máximo nem o Alto Desempenho.' }
    }
    if ($active.Guid -ne $guid) {
        [void](Save-UTOriginalItem -Chave 'energia|planoAnteriorMaximo' -Dados ([ordered]@{ guid = $active.Guid; nome = $active.Nome }) -TweakId $TweakId)
    }
    [void](Save-UTOriginalItem -Chave 'energia|planoMaximo' -Dados ([ordered]@{ guid = $guid; criado = $created; alternativo = $fallback }) -TweakId $TweakId)
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $guid))
    $name = (@(Get-UTPowerSchemeList | Where-Object { $_.Guid -eq $guid }) | Select-Object -First 1).Nome
    Write-UTLog -Level Sucesso -TweakId $TweakId -Message "Plano '$name' ativo."
    return [pscustomobject]@{ Guid = $guid; Nome = $name; Criado = $created; Alternativo = $fallback }
}

function Undo-UTMaxPerformanceCore {
    <#
    .SYNOPSIS
        Goes back to the plan that was active before and deletes the copy of Maximum Performance
        when the Upgrade Tweaks unlocked it. Called by the undo of UT_Power_DesempenhoMaximo.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    $cfg = Get-UTConfig -Name 'powerplan'
    $previous = Pop-UTOriginalItem -Chave 'energia|planoAnteriorMaximo' -TweakId $TweakId
    $target = $cfg.equilibrado
    if ($previous -is [System.Collections.IDictionary] -and $previous.guid -and (Test-UTPowerScheme -Guid $previous.guid)) { $target = [string]$previous.guid }
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $target))
    $plan = Pop-UTOriginalItem -Chave 'energia|planoMaximo' -TweakId $TweakId
    if ($plan -is [System.Collections.IDictionary] -and $plan.criado -and $plan.guid -and $plan.guid -ne $target -and (Test-UTPowerScheme -Guid $plan.guid)) {
        [void](Invoke-UTPowerCfg -Argumentos @('/delete', [string]$plan.guid))
    }
    Write-UTLog -Level Sucesso -TweakId $TweakId -Message 'Plano de energia anterior restaurado.'
}

function Test-UTMaxPerformanceActive {
    <#
    .SYNOPSIS
        True when Maximum Performance (or the High Performance fallback chosen on a Windows that
        refuses it) is the active plan.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $schemes = @(Get-UTPowerSchemeList)
    $active = (@($schemes | Where-Object Ativo) | Select-Object -First 1)
    if (-not $active) { return $false }
    $guid = Find-UTMaxPerformanceScheme -Planos $schemes
    if ($guid -and $active.Guid -eq $guid) { return $true }
    $saved = Get-UTOriginalItem -Chave 'generico|energia|planomaximo'
    return [bool]($saved -and $saved.dados.alternativo -and $active.Guid -eq [string]$saved.dados.guid)
}

function Get-UTMaxPerformancePlannedAction {
    <#
    .SYNOPSIS
        Read-only description for "Simular" (and its undo with -Desfazer).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([switch]$Desfazer)
    $cfg = Get-UTConfig -Name 'powerplan'
    $schemes = @(Get-UTPowerSchemeList)
    $nameOf = { param($g) $hit = (@($schemes | Where-Object { $_.Guid -eq $g }) | Select-Object -First 1); if ($hit) { $hit.Nome } else { $g } }
    $lines = New-Object System.Collections.Generic.List[string]
    if ($Desfazer) {
        $previous = Get-UTOriginalItem -Chave 'generico|energia|planoanteriormaximo'
        $target = $(if ($previous) { [string]$previous.dados.guid } else { $cfg.equilibrado })
        $lines.Add("Ativa de novo o plano '$(& $nameOf $target)'")
        $plan = Get-UTOriginalItem -Chave 'generico|energia|planomaximo'
        if ($plan -and $plan.dados.criado) { $lines.Add("Apaga a cópia '$(& $nameOf ([string]$plan.dados.guid))' liberada pelo Upgrade Tweaks") }
        return $lines.ToArray()
    }
    $existing = Find-UTMaxPerformanceScheme -Planos $schemes
    if ($existing) { $lines.Add("Ativa o plano '$(& $nameOf $existing)' que já existe") }
    else {
        $lines.Add("Libera o Desempenho Máximo do Windows (powercfg -duplicatescheme $($cfg.desempenhoMaximo)) e ativa")
        $lines.Add('Se esta edição do Windows não permitir, ativa o Alto Desempenho')
    }
    $active = (@($schemes | Where-Object Ativo) | Select-Object -First 1)
    if ($active) { $lines.Add("Hoje está ativo: $($active.Nome)") }
    return $lines.ToArray()
}

function Invoke-UTPowerPlanMigration {
    <#
    .SYNOPSIS
        First run of the v2: removes the custom plan of the old versions (names in
        powerplan.json "migracao"). When it was the active plan, Maximum Performance (Balanced on
        a dual-CCD Ryzen X3D) is activated first. Runs once; a marker in the state folder keeps it
        from running again.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([psobject]$Contexto)
    $marker = Join-Path (Get-UTPath -Name State) 'migracoes.json'
    $done = Read-UTJsonFile -Path $marker -Default ([ordered]@{})
    if ($done.Contains('planoEnergiaV2') -and $done['planoEnergiaV2']) { return $null }
    $cfg = Get-UTConfig -Name 'powerplan'
    $oldNames = @($cfg.migracao.planos | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $schemes = @(Get-UTPowerSchemeList)
    $old = @($schemes | Where-Object { $oldNames -contains ([string]$_.Nome).ToLowerInvariant() })
    $result = [pscustomobject]@{ Removidos = @(); Ativado = $null }
    if ($old.Count -gt 0) {
        if (-not $PSCmdlet.ShouldProcess(($old.Nome -join ', '), 'Apagar o plano antigo e usar o Desempenho Máximo')) { return $null }
        Assert-UTAdmin
        if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
        if (@($old | Where-Object Ativo).Count -gt 0) {
            if ($Contexto.X3D -eq 'duplo') {
                [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $cfg.equilibrado))
                $result.Ativado = 'Equilibrado'
            } else {
                $r = Invoke-UTMaxPerformanceCore -TweakId 'UT_Power_DesempenhoMaximo' -Contexto $Contexto
                Add-UTAppliedRecord -TweakId 'UT_Power_DesempenhoMaximo' -Detalhe 'migração do plano antigo'
                $result.Ativado = $r.Nome
            }
        }
        foreach ($s in $old) { [void](Invoke-UTPowerCfg -Argumentos @('/delete', $s.Guid)) }
        $result.Removidos = @($old | ForEach-Object Nome)
        Write-UTLog -Level Sucesso -Message "Migração do plano de energia: removido '$($result.Removidos -join ', ')'$(if ($result.Ativado) { "; ativo agora: $($result.Ativado)" })."
    } elseif (-not $PSCmdlet.ShouldProcess($marker, 'Registrar migração do plano de energia')) {
        return $null
    }
    foreach ($id in @($cfg.migracao.tweaks)) {
        Remove-UTAppliedRecord -TweakId $id -Confirm:$false
        foreach ($k in @($cfg.migracao.chavesEstado)) { [void](Pop-UTOriginalItem -Chave $k -TweakId $id -Force -Confirm:$false) }
    }
    $done['planoEnergiaV2'] = $true
    Write-UTJsonFile -Path $marker -InputObject $done -Confirm:$false
    return $result
}
#endregion

#region Optional settings over the active plan
function Get-UTPowerAdjustment {
    # One entry of powerplan.json "ajustes".
    param([Parameter(Mandatory)][string]$Ajuste)
    $a = (@((Get-UTConfig -Name 'powerplan').ajustes | Where-Object { $_.id -eq $Ajuste }) | Select-Object -First 1)
    if ($null -eq $a) { throw "Ajuste de energia desconhecido: $Ajuste" }
    return $a
}

function Invoke-UTActivePlanSettingCore {
    <#
    .SYNOPSIS
        Applies one optional adjustment (powerplan.json "ajustes") to the active plan, saving the
        current values. On a notebook only the plugged-in value changes. Settings this Windows does
        not have are skipped; when none exists it fails.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Ajuste, [Parameter(Mandatory)][string]$TweakId, [psobject]$Contexto)
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    $a = Get-UTPowerAdjustment -Ajuste $Ajuste
    $scheme = (Get-UTActivePowerScheme).Guid
    $applied = 0
    foreach ($i in @($a.itens)) {
        $current = Get-UTPowerSettingValue -Esquema $scheme -Subgrupo $i.subgrupo -Configuracao $i.configuracao
        if (-not $current.Existe) { Write-UTLog -Level Info -TweakId $TweakId -Message "Configuração de energia $($i.configuracao) não existe neste Windows; pulada."; continue }
        [void](Save-UTOriginalItem -Chave "energia|ajuste|$($i.configuracao)" -Dados ([ordered]@{ guid = $scheme; subgrupo = $i.subgrupo; ac = $current.AC; dc = $current.DC }) -TweakId $TweakId)
        $dc = $(if ($Contexto.EhNotebook -eq $true) { $null } else { [long]$i.valor })
        Set-UTPowerSettingValue -Esquema $scheme -Subgrupo $i.subgrupo -Configuracao $i.configuracao -AC ([long]$i.valor) -DC $dc
        $applied++
    }
    if ($applied -eq 0) { throw "Este Windows não tem a configuração '$($a.nome)'." }
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $scheme))
}

function Undo-UTActivePlanSettingCore {
    <#
    .SYNOPSIS
        Undo of Invoke-UTActivePlanSettingCore: writes back the saved values on the plan they came from.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Ajuste, [Parameter(Mandatory)][string]$TweakId)
    $a = Get-UTPowerAdjustment -Ajuste $Ajuste
    $active = (Get-UTActivePowerScheme).Guid
    foreach ($i in @($a.itens)) {
        $saved = Pop-UTOriginalItem -Chave "energia|ajuste|$($i.configuracao)" -TweakId $TweakId
        if ($saved -isnot [System.Collections.IDictionary]) { continue }
        $scheme = [string]$saved.guid
        if (-not (Test-UTPowerScheme -Guid $scheme)) { continue }
        Set-UTPowerSettingValue -Esquema $scheme -Subgrupo $i.subgrupo -Configuracao $i.configuracao -AC ([long]$saved.ac) -DC ([long]$saved.dc)
    }
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $active))
}

function Test-UTActivePlanSetting {
    <#
    .SYNOPSIS
        True when every setting of the adjustment that exists here has the target value (plugged
        in) on the active plan.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Ajuste)
    $a = Get-UTPowerAdjustment -Ajuste $Ajuste
    $scheme = (Get-UTActivePowerScheme).Guid
    $seen = 0
    foreach ($i in @($a.itens)) {
        $v = Get-UTPowerSettingValue -Esquema $scheme -Subgrupo $i.subgrupo -Configuracao $i.configuracao
        if (-not $v.Existe) { continue }
        $seen++
        if ($v.AC -ne [long]$i.valor) { return $false }
    }
    return ($seen -gt 0)
}

function Get-UTActivePlanSettingAction {
    <#
    .SYNOPSIS
        "Simular" lines of an optional adjustment: current -> new on the active plan.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Ajuste)
    $a = Get-UTPowerAdjustment -Ajuste $Ajuste
    $active = Get-UTActivePowerScheme
    foreach ($i in @($a.itens)) {
        $v = Get-UTPowerSettingValue -Esquema $active.Guid -Subgrupo $i.subgrupo -Configuracao $i.configuracao
        if (-not $v.Existe) { "$($a.nome): não existe neste Windows (pulada)"; continue }
        "$($a.nome) no plano '$($active.Nome)': $($v.AC) -> $($i.valor)"
    }
}
#endregion

#region Dual-CCD Ryzen X3D
function Invoke-UTX3DBalancedCore {
    <#
    .SYNOPSIS
        Dual-CCD Ryzen X3D: activates Balanced (saving the previous plan) and reports the other
        pieces the AMD scheduler needs. Called by UT_Power_X3DDuplo_Equilibrado.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)

    $cfg = Get-UTConfig -Name 'powerplan'
    $active = Get-UTActivePowerScheme
    if ($active.Guid -ne $cfg.equilibrado) {
        [void](Backup-UTActivePowerPlan)
        [void](Save-UTOriginalItem -Chave 'energia|planoAnteriorX3D' -Dados ([ordered]@{ guid = $active.Guid; nome = $active.Nome }) -TweakId $TweakId)
        [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $cfg.equilibrado))
    }
    foreach ($check in @(Get-UTX3DDualCheck)) {
        if (-not $check.Ok) { Write-UTLog -Level Aviso -TweakId $TweakId -Message $check.Mensagem }
    }
}

function Undo-UTX3DBalancedCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    $previous = Pop-UTOriginalItem -Chave 'energia|planoAnteriorX3D' -TweakId $TweakId
    if ($previous -is [System.Collections.IDictionary] -and $previous.guid -and (Test-UTPowerScheme -Guid $previous.guid)) {
        [void](Invoke-UTPowerCfg -Argumentos @('/setactive', [string]$previous.guid))
    }
}

function Get-UTX3DDualCheck {
    <#
    .SYNOPSIS
        What a dual-CCD Ryzen X3D needs so games land on the V-Cache CCD: AMD chipset driver
        (3D V-Cache Performance Optimizer), Game Bar installed, Game Mode on, Balanced plan.
    #>
    [CmdletBinding()]
    param()

    $cfg = Get-UTConfig -Name 'powerplan'
    $driver = Get-UTServiceState -Name $cfg.x3d.servicoDriver
    $gameBar = $null -ne (Get-AppxPackage -Name $cfg.x3d.pacoteGameBar -ErrorAction SilentlyContinue)
    $gm = Get-UTRegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
    $gameMode = (-not $gm.ValorExiste) -or ([int]$gm.Valor -eq 1)
    $balanced = ((Get-UTActivePowerScheme).Guid -eq $cfg.equilibrado)

    @(
        [pscustomobject]@{ Item = 'Driver de chipset AMD (3D V-Cache Performance Optimizer)'; Ok = $driver.Existe
            Mensagem = $(if ($driver.Existe) { 'Driver de chipset da AMD instalado.' } else { "Instale o driver de chipset da AMD mais recente ($($cfg.x3d.linkChipset)); sem ele o Windows não sabe em qual CCD colocar o jogo." }) }
        [pscustomobject]@{ Item = 'Xbox Game Bar instalado'; Ok = $gameBar
            Mensagem = $(if ($gameBar) { 'Game Bar instalado.' } else { 'O Xbox Game Bar não está instalado. Reinstale pela Microsoft Store: é ele que avisa o driver da AMD que um jogo abriu.' }) }
        [pscustomobject]@{ Item = 'Modo de Jogo ligado'; Ok = $gameMode
            Mensagem = $(if ($gameMode) { 'Modo de Jogo ligado.' } else { 'Ligue o Modo de Jogo (aba Gaming).' }) }
        [pscustomobject]@{ Item = 'Plano Equilibrado ativo'; Ok = $balanced
            Mensagem = $(if ($balanced) { 'Plano Equilibrado ativo.' } else { 'Ative o plano Equilibrado: o estacionamento do CCD sem V-Cache depende dele.' }) }
    )
}
#endregion

#region Status and tools of the tab
function Get-UTPowerPlanStatus {
    <#
    .SYNOPSIS
        Everything the Energia tab shows: every installed plan (the active one marked), whether
        Maximum Performance is there and active, which path this PC should follow and the X3D
        checks when relevant.
    #>
    [CmdletBinding()]
    param()

    $context = Get-UTSystemContext
    $schemes = @(Get-UTPowerSchemeList)
    $active = (@($schemes | Where-Object Ativo) | Select-Object -First 1)
    if (-not $active) { $active = Get-UTActivePowerScheme }
    $max = Find-UTMaxPerformanceScheme -Planos $schemes
    $mode = 'padrao'
    $message = 'Ative o Desempenho Máximo do próprio Windows para o processador não baixar o clock durante o jogo.'
    if ($context.X3D -eq 'duplo') {
        $mode = 'x3dDuplo'
        $message = 'Seu processador é um Ryzen X3D de dois CCDs. Ele NÃO deve usar o Desempenho Máximo: o driver de chipset da AMD e o Game Bar usam o plano Equilibrado para estacionar o CCD sem V-Cache enquanto você joga, deixando o jogo no CCD com V-Cache. O Upgrade Tweaks mantém o Equilibrado e confere o resto para você.'
    } elseif ($context.X3D -eq 'unico') {
        $mode = 'x3dUnico'
        $message = 'Ryzen X3D de um CCD: pode usar o Desempenho Máximo normalmente. Mantenha o driver de chipset da AMD atualizado; PBO e Curve Optimizer só pela BIOS (veja a aba BIOS).'
    } elseif ($context.EhNotebook -eq $true) {
        $mode = 'notebook'
        $message = 'Notebook: use o Desempenho Máximo só na tomada. Na bateria ele derruba a autonomia e esquenta o notebook; troque para o Equilibrado quando estiver fora da tomada.'
    }
    return [pscustomobject]@{
        Ativo        = $active
        Planos       = $schemes
        MaximoGuid   = $max
        MaximoAtivo  = [bool]($max -and $active.Guid -eq $max)
        Modo         = $mode
        Mensagem     = $message
        ChecagensX3D = $(if ($mode -eq 'x3dDuplo') { @(Get-UTX3DDualCheck) } else { @() })
    }
}

function Set-UTActivePowerScheme {
    <#
    .SYNOPSIS
        Activates an installed plan (the plan selector of the Energia tab).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Guid)
    Assert-UTAdmin
    if (-not (Test-UTPowerScheme -Guid $Guid)) { throw "O plano $Guid não existe neste PC." }
    if (-not $PSCmdlet.ShouldProcess($Guid, 'Ativar plano de energia')) { return }
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $Guid.ToLowerInvariant()))
    Write-UTLog -Level Sucesso -Message "Plano de energia $Guid ativado."
}

function Export-UTPowerPlan {
    <#
    .SYNOPSIS
        Exports a plan (default: the active one) to a .pow file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Guid
    )
    if (-not $Guid) { $Guid = (Get-UTActivePowerScheme).Guid }
    if ($PSCmdlet.ShouldProcess($Path, "Exportar plano $Guid")) {
        [void](Invoke-UTPowerCfg -Argumentos @('/export', $Path, $Guid))
        Write-UTLog -Level Sucesso -Message "Plano de energia exportado para $Path"
    }
    return $Path
}

function Import-UTPowerPlan {
    <#
    .SYNOPSIS
        Imports a .pow file as a new plan; -Ativar also makes it the active plan.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Ativar
    )
    Assert-UTAdmin
    if (-not (Test-Path -LiteralPath $Path)) { throw "Arquivo não encontrado: $Path" }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Importar plano de energia')) { return $null }
    $out = Invoke-UTPowerCfg -Argumentos @('/import', $Path)
    $m = [regex]::Match($out, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if (-not $m.Success) { throw "powercfg /import não devolveu o GUID do plano: $out" }
    $guid = $m.Value.ToLowerInvariant()
    if ($Ativar) { [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $guid)) }
    Write-UTLog -Level Sucesso -Message "Plano importado de $Path ($guid)."
    return $guid
}

function Restore-UTPreviousPowerPlan {
    <#
    .SYNOPSIS
        "Voltar ao plano anterior": undoes Maximum Performance (or the X3D Balanced switch).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $applied = @(Get-UTAppliedRecord | ForEach-Object { $_.tweakId })
    $ids = @(@('UT_Power_DesempenhoMaximo', 'UT_Power_X3DDuplo_Equilibrado') | Where-Object { $applied -contains $_ })
    if ($ids.Count -eq 0) { $ids = @('UT_Power_DesempenhoMaximo') }
    return (Undo-UTTweak -Id $ids)
}
#endregion

#region IDLEDISABLE
function Invoke-UTIdleDisableCore {
    <#
    .SYNOPSIS
        IDLEDISABLE = 1 on the active plan (the processor never enters idle states). High risk:
        much higher temperature and power draw. Called by UT_Power_IdleDisable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)

    $s = (Get-UTConfig -Name 'powerplan').idleDisable
    $scheme = (Get-UTActivePowerScheme).Guid
    $current = Get-UTPowerSettingValue -Esquema $scheme -Subgrupo $s.subgrupo -Configuracao $s.configuracao
    if (-not $current.Existe) { throw 'Este Windows não tem a configuração IDLEDISABLE.' }
    [void](Save-UTOriginalItem -Chave 'energia|idledisable' -Dados ([ordered]@{ guid = $scheme; ac = $current.AC; dc = $current.DC }) -TweakId $TweakId)
    Set-UTPowerSettingValue -Esquema $scheme -Subgrupo $s.subgrupo -Configuracao $s.configuracao -AC ([long]$s.valor) -DC ([long]$s.valor)
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $scheme))
}

function Undo-UTIdleDisableCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)

    $s = (Get-UTConfig -Name 'powerplan').idleDisable
    $saved = Pop-UTOriginalItem -Chave 'energia|idledisable' -TweakId $TweakId
    $scheme = (Get-UTActivePowerScheme).Guid
    $ac = 0
    $dc = 0
    if ($saved -is [System.Collections.IDictionary]) {
        if ($saved.guid -and (Test-UTPowerScheme -Guid $saved.guid)) { $scheme = [string]$saved.guid }
        $ac = [long]$saved.ac
        $dc = [long]$saved.dc
    }
    Set-UTPowerSettingValue -Esquema $scheme -Subgrupo $s.subgrupo -Configuracao $s.configuracao -AC $ac -DC $dc
    if ($scheme -eq (Get-UTActivePowerScheme).Guid) { [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $scheme)) }
}

function Test-UTIdleDisable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $s = (Get-UTConfig -Name 'powerplan').idleDisable
    $v = Get-UTPowerSettingValue -Esquema (Get-UTActivePowerScheme).Guid -Subgrupo $s.subgrupo -Configuracao $s.configuracao
    return ($v.Existe -and $v.AC -eq [long]$s.valor)
}
#endregion
