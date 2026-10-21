# "Energia" tab: the "Upgrade Warzone" power plan, the dual-CCD Ryzen X3D path and the plan
# tools. The plan itself is applied through the catalog tweak UT_Power_UpgradeWarzone, so it
# gets restore point, journal and "Desfazer TUDO" like every other tweak; the functions below
# are what that tweak's scripts call. The *Core functions take no -WhatIf: the engine never runs
# tweak scripts in simulation mode, it lists the planned actions instead.

function Get-UTPowerPlanOption {
    <#
    .SYNOPSIS
        User options for the plan (set by the Energia tab): MinutosVideo (default 15).
    #>
    [CmdletBinding()]
    param()
    $options = Get-UTSyncValue -Key 'OpcoesEnergia'
    $minutes = 15
    if ($options -and $null -ne $options['MinutosVideo']) { $minutes = [int]$options['MinutosVideo'] }
    return [pscustomobject]@{ MinutosVideo = $minutes }
}

function Invoke-UTPowerPlanCore {
    <#
    .SYNOPSIS
        Creates (or reuses) the "Upgrade Warzone" plan, applies every setting of powerplan.json
        and activates it. Called by the scriptAplicar of UT_Power_UpgradeWarzone.
    .DESCRIPTION
        Desktop: copy of Ultimate Performance (falls back to High Performance, then Balanced) with
        the same values plugged in and on battery.
        Notebook: copy of Balanced named "Upgrade Warzone (na tomada)"; only the plugged-in
        values change, so the battery keeps Balanced behaviour.
        Dual-CCD Ryzen X3D: refuses (the AMD driver needs Balanced).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TweakId,
        [psobject]$Contexto
    )

    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    if ($Contexto.X3D -eq 'duplo') {
        throw 'Ryzen X3D de dois CCDs: o plano Upgrade Warzone não é usado. Use o ajuste "Manter o plano Equilibrado (Ryzen X3D de dois CCDs)".'
    }
    $cfg = Get-UTConfig -Name 'powerplan'
    $isLaptop = ($Contexto.EhNotebook -eq $true)
    $options = Get-UTPowerPlanOption

    $active = Get-UTActivePowerScheme
    [void](Backup-UTActivePowerPlan)
    $guid = Find-UTUpgradePowerScheme
    if ($active.Guid -ne $guid) {
        [void](Save-UTOriginalItem -Chave 'energia|planoAnterior' -Dados ([ordered]@{ guid = $active.Guid; nome = $active.Nome }) -TweakId $TweakId)
    }

    $created = $false
    if (-not $guid) {
        $bases = @($cfg.bases | ForEach-Object { $_.guid })
        if ($isLaptop) { $bases = @($cfg.baseNotebook) }
        foreach ($base in $bases) {
            try {
                $guid = Copy-UTPowerScheme -Base $base
                if ($guid) {
                    $created = $true
                    Write-UTLog -Level Info -TweakId $TweakId -Message "Plano criado a partir de $base."
                    break
                }
            } catch {
                Write-UTLog -Level Aviso -TweakId $TweakId -Message "Não foi possível usar o plano base $base; tentando o próximo." -Detalhe $_.Exception.Message
            }
        }
        if (-not $guid) { throw 'Não foi possível criar o plano Upgrade Warzone (o Windows recusou duplicar os planos base).' }
    }
    [void](Save-UTOriginalItem -Chave 'energia|planoUpgrade' -Dados ([ordered]@{ guid = $guid; criado = $created }) -TweakId $TweakId)

    $name = $(if ($isLaptop) { $cfg.nomeNotebook } else { $cfg.nome })
    [void](Invoke-UTPowerCfg -Argumentos @('/changename', $guid, $name, $cfg.descricao))

    $applied = 0
    $skipped = New-Object System.Collections.Generic.List[string]
    foreach ($s in @($cfg.configuracoes)) {
        if ($s.pularX3DDuplo -and $Contexto.X3D -eq 'duplo') { $skipped.Add($s.nome); continue }
        $value = [long]$s.valor
        if ($s.configuravel -eq 'minutosVideo') { $value = [long]$options.MinutosVideo * 60 }
        $current = Get-UTPowerSettingValue -Esquema $guid -Subgrupo $s.subgrupo -Configuracao $s.configuracao
        if (-not $current.Existe) {
            $level = $(if ($s.opcional) { 'Info' } else { 'Aviso' })
            Write-UTLog -Level $level -TweakId $TweakId -Message "Configuração '$($s.nome)' não existe neste Windows; pulada."
            $skipped.Add($s.nome)
            continue
        }
        $dc = $value
        if ($isLaptop) { $dc = $null }
        Set-UTPowerSettingValue -Esquema $guid -Subgrupo $s.subgrupo -Configuracao $s.configuracao -AC $value -DC $dc
        Write-UTLog -Level Debug -TweakId $TweakId -Message "Energia: $($s.nome)" -Antes $current.AC -Depois $value
        $applied++
    }

    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $guid))
    Write-UTLog -Level Sucesso -TweakId $TweakId -Message "Plano '$name' ativo ($applied configurações aplicadas)."
    return [pscustomobject]@{ Guid = $guid; Nome = $name; Criado = $created; Aplicadas = $applied; Puladas = $skipped.ToArray() }
}

function Undo-UTPowerPlanCore {
    <#
    .SYNOPSIS
        Goes back to the plan that was active before and deletes the "Upgrade Warzone" plan if
        Upgrade Tweaks created it. Called by the scriptDesfazer of UT_Power_UpgradeWarzone.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)

    $cfg = Get-UTConfig -Name 'powerplan'
    $previous = Pop-UTOriginalItem -Chave 'energia|planoAnterior' -TweakId $TweakId
    $target = $cfg.equilibrado
    if ($previous -is [System.Collections.IDictionary] -and $previous.guid -and (Test-UTPowerScheme -Guid $previous.guid)) {
        $target = [string]$previous.guid
    }
    [void](Invoke-UTPowerCfg -Argumentos @('/setactive', $target))

    $plan = Pop-UTOriginalItem -Chave 'energia|planoUpgrade' -TweakId $TweakId
    if ($plan -is [System.Collections.IDictionary] -and $plan.criado -and $plan.guid -and (Test-UTPowerScheme -Guid $plan.guid)) {
        [void](Invoke-UTPowerCfg -Argumentos @('/delete', [string]$plan.guid))
    }
    Write-UTLog -Level Sucesso -TweakId $TweakId -Message 'Plano de energia anterior restaurado.'
}

function Get-UTPowerPlanPlannedAction {
    <#
    .SYNOPSIS
        Read-only description for "Simular": which plan is created or reused and, for each
        setting, the current value -> the new one. -Desfazer describes the undo.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [psobject]$Contexto,
        [switch]$Desfazer
    )

    $cfg = Get-UTConfig -Name 'powerplan'
    $lines = New-Object System.Collections.Generic.List[string]
    $schemes = @(Get-UTPowerSchemeList)
    $nameOf = { param($g) $hit = (@($schemes | Where-Object { $_.Guid -eq $g }) | Select-Object -First 1); if ($hit) { $hit.Nome } else { $g } }

    if ($Desfazer) {
        $previous = Get-UTOriginalItem -Chave 'generico|energia|planoanterior'
        $target = $(if ($previous) { [string]$previous.dados.guid } else { $cfg.equilibrado })
        $lines.Add("Ativa de novo o plano '$(& $nameOf $target)'")
        $plan = Get-UTOriginalItem -Chave 'generico|energia|planoupgrade'
        if ($plan -and $plan.dados.criado) { $lines.Add("Apaga o plano '$(& $nameOf ([string]$plan.dados.guid))' criado pelo Upgrade Tweaks") }
        return $lines.ToArray()
    }

    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    $isLaptop = ($Contexto.EhNotebook -eq $true)
    $active = Get-UTActivePowerScheme
    $existing = Find-UTUpgradePowerScheme
    $reference = $active.Guid
    if ($existing) {
        $reference = $existing
        $lines.Add("Reaproveita o plano '$(& $nameOf $existing)' que já existe")
    } else {
        $baseGuid = $(if ($isLaptop) { $cfg.baseNotebook } else { (@($cfg.bases) | Select-Object -First 1).guid })
        $base = (@($cfg.bases | Where-Object { $_.guid -eq $baseGuid }) | Select-Object -First 1)
        $planName = $(if ($isLaptop) { $cfg.nomeNotebook } else { $cfg.nome })
        $lines.Add("Cria o plano '$planName' a partir do $($base.nome)")
    }
    $where = $(if ($isLaptop) { ' (na tomada)' } else { '' })
    $options = Get-UTPowerPlanOption
    foreach ($s in @($cfg.configuracoes)) {
        if ($s.pularX3DDuplo -and $Contexto.X3D -eq 'duplo') { continue }
        $value = [long]$s.valor
        if ($s.configuravel -eq 'minutosVideo') { $value = [long]$options.MinutosVideo * 60 }
        $current = Get-UTPowerSettingValue -Esquema $reference -Subgrupo $s.subgrupo -Configuracao $s.configuracao
        if (-not $current.Existe) { $lines.Add("$($s.nome): não existe neste Windows (pulada)"); continue }
        $lines.Add("$($s.nome)${where}: $($current.AC) -> $value")
    }
    $lines.Add("Ativa o plano (hoje está ativo: $($active.Nome))")
    return $lines.ToArray()
}

function Test-UTPowerPlanApplied {
    <#
    .SYNOPSIS
        True when the "Upgrade Warzone" plan exists and is the active one.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $guid = Find-UTUpgradePowerScheme
    if (-not $guid) { return $false }
    return ((Get-UTActivePowerScheme).Guid -eq $guid)
}

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

function Get-UTPowerPlanStatus {
    <#
    .SYNOPSIS
        Everything the Energia tab shows: active plan, whether Upgrade Warzone exists/is active,
        which path this PC should follow and the X3D checks when relevant.
    #>
    [CmdletBinding()]
    param()

    $context = Get-UTSystemContext
    $active = Get-UTActivePowerScheme
    $upgrade = Find-UTUpgradePowerScheme
    $mode = 'padrao'
    $message = 'Aplique o plano Upgrade Warzone para manter o processador sempre no máximo durante o jogo.'
    if ($context.X3D -eq 'duplo') {
        $mode = 'x3dDuplo'
        $message = 'Seu processador é um Ryzen X3D de dois CCDs. Ele NÃO deve usar o plano Upgrade Warzone: o driver de chipset da AMD e o Game Bar usam o plano Equilibrado para estacionar o CCD sem V-Cache enquanto você joga, deixando o jogo no CCD com V-Cache. O Upgrade Tweaks mantém o Equilibrado e confere o resto para você.'
    } elseif ($context.X3D -eq 'unico') {
        $mode = 'x3dUnico'
        $message = 'Ryzen X3D de um CCD: pode usar o plano Upgrade Warzone normalmente. Mantenha o driver de chipset da AMD atualizado; PBO e Curve Optimizer só pelo BIOS (veja o guia de BIOS).'
    } elseif ($context.EhNotebook -eq $true) {
        $mode = 'notebook'
        $message = 'Notebook: o plano "Upgrade Warzone (na tomada)" só muda o comportamento com o carregador ligado. Na bateria ele age como o Equilibrado. Usar o plano agressivo na bateria derruba a autonomia e esquenta o notebook; troque para o Equilibrado quando estiver fora da tomada.'
    }

    return [pscustomobject]@{
        Ativo         = $active
        UpgradeGuid   = $upgrade
        UpgradeAtivo  = ($upgrade -and $active.Guid -eq $upgrade)
        Modo          = $mode
        Mensagem      = $message
        ChecagensX3D  = $(if ($mode -eq 'x3dDuplo') { @(Get-UTX3DDualCheck) } else { @() })
    }
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
        "Voltar para o plano anterior": undoes the Upgrade Warzone plan (or the X3D Balanced switch).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $applied = @(Get-UTAppliedRecord | ForEach-Object { $_.tweakId })
    $ids = @(@('UT_Power_UpgradeWarzone', 'UT_Power_X3DDuplo_Equilibrado') | Where-Object { $applied -contains $_ })
    if ($ids.Count -eq 0) { $ids = @('UT_Power_UpgradeWarzone') }
    return (Undo-UTTweak -Id $ids)
}

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
