# Internals of the tweak engine. Public entry points are in functions\public\Tweaks.ps1.

function Get-UTSystemContext {
    <#
    .SYNOPSIS
        What the engine knows about this PC for compatibility checks. Cached in $UTSync.Contexto.
        Hardware fields (GPU, CPU, notebook, launchers, X3D) are filled by the diagnostics
        (phase 4); while unknown they are $null and never block a tweak.
    #>
    [CmdletBinding()]
    param([switch]$Atualizar)

    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if (-not $Atualizar -and $null -ne $sync -and $null -ne $sync['Contexto']) { return $sync['Contexto'] }

    $windows = $null
    if ($null -ne $sync -and $null -ne $sync['Windows']) { $windows = $sync['Windows'] }
    if ($null -eq $windows) {
        try { $windows = Get-UTWindowsInfo } catch { $windows = $null }
    }
    $hardware = $null
    if ($null -ne $sync) { $hardware = $sync['Hardware'] }
    if ($null -eq $hardware) {
        # Rules like "never on dual-CCD X3D" are only safe with the hardware known, so collect it
        # once here when nobody did before (command-line runs skip the Início tab).
        try { $hardware = Get-UTHardwareInfo } catch { $hardware = $null }
    }

    $context = [pscustomobject]@{
        WindowsGeracao = $(if ($windows) { [string]$windows.Geracao } else { $null })
        Build          = $(if ($windows) { [int]$windows.Build } else { $null })
        GpuFabricantes = $(if ($hardware) { @($hardware.GpuFabricantes) } else { @() })
        CpuFabricante  = $(if ($hardware) { $hardware.CpuFabricante } else { $null })
        EhNotebook     = $(if ($hardware) { $hardware.EhNotebook } else { $null })
        Launchers      = $(if ($hardware) { @($hardware.Launchers) } else { @() })
        X3D            = $(if ($hardware) { $hardware.X3D } else { $null })
        Executaveis    = $(if ($hardware -and $hardware.PSObject.Properties['Executaveis']) { @($hardware.Executaveis) } else { @() })
    }
    if ($null -ne $sync) { $sync['Contexto'] = $context }
    return $context
}

function Invoke-UTTweakScript {
    <#
    .SYNOPSIS
        Runs a tweak's script lines. $TweakId and $Contexto are visible to the script.
        Scripts come only from the embedded tweaks.json, never from user input.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'TweakId and Contexto are read by the tweak script through dynamic scoping.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$TweakId,
        [psobject]$Contexto
    )

    $code = ($Lines -join "`n")
    $block = [scriptblock]::Create($code)
    # The script sees $TweakId and $Contexto through PowerShell's dynamic scoping.
    return (& $block)
}

function Get-UTRegistryEntryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Entry)

    $current = Get-UTRegistryValue -Path $Entry.caminho -Name ([string]$Entry.nome)
    if ($Entry.acao -eq 'remover') {
        $ok = -not $current.ValorExiste
    } elseif (-not $current.ValorExiste -and $Entry.ausenteEquivale) {
        # Windows' built-in default (value absent) already behaves like the target.
        $ok = $true
    } else {
        $ok = Test-UTRegistryValueEqual -Actual $current -Type $Entry.tipo -Expected $Entry.valor
    }
    return [pscustomobject]@{ Ok = $ok; Atual = $current }
}

function Get-UTServiceEntryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Entry)

    $current = Get-UTServiceState -Name $Entry.nome
    # A service that does not exist on this edition cannot get in the way: count it as done.
    $ok = (-not $current.Existe) -or ($current.StartType -eq $Entry.inicio)
    return [pscustomobject]@{ Ok = $ok; Atual = $current }
}

function Get-UTTweakStateCore {
    <#
    .SYNOPSIS
        Estado: Aplicado, NaoAplicado or Parcial, plus one line per checked item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [psobject]$Contexto
    )

    $checks = New-Object System.Collections.Generic.List[bool]
    $details = New-Object System.Collections.Generic.List[string]
    $mode = $Tweak.deteccao

    if ($mode -in 'registro', 'combinada') {
        foreach ($entry in @($Tweak.registro | Where-Object { $_ })) {
            $s = Get-UTRegistryEntryState -Entry $entry
            $checks.Add([bool]$s.Ok)
            $now = if ($s.Atual.ValorExiste) { ConvertTo-UTLogValue $s.Atual.Valor } else { '<ausente>' }
            $details.Add(('{0}\{1} = {2}' -f $entry.caminho, $entry.nome, $now))
        }
    }
    if ($mode -in 'servicos', 'combinada') {
        foreach ($entry in @($Tweak.servicos | Where-Object { $_ })) {
            $s = Get-UTServiceEntryState -Entry $entry
            $checks.Add([bool]$s.Ok)
            $now = if ($s.Atual.Existe) { $s.Atual.StartType } else { 'não existe' }
            $details.Add(('serviço {0}: {1}' -f $entry.nome, $now))
        }
    }
    if ($mode -eq 'script' -or ($mode -eq 'combinada' -and @($Tweak.scriptDetectar | Where-Object { $_ }).Count -gt 0)) {
        $result = $false
        try {
            $result = [bool](@(Invoke-UTTweakScript -Lines @($Tweak.scriptDetectar) -TweakId $Tweak.id -Contexto $Contexto) | Select-Object -Last 1)
        } catch {
            Write-UTLog -Level Aviso -TweakId $Tweak.id -Message 'Não foi possível verificar o estado deste ajuste.' -Detalhe $_.Exception.Message
        }
        $checks.Add($result)
        $scriptState = 'não aplicado'
        if ($result) { $scriptState = 'aplicado' }
        $details.Add("verificação por script: $scriptState")
    }

    $done = @($checks | Where-Object { $_ }).Count
    $state = 'NaoAplicado'
    if ($checks.Count -gt 0 -and $done -eq $checks.Count) { $state = 'Aplicado' }
    elseif ($done -gt 0) { $state = 'Parcial' }
    return [pscustomobject]@{ Estado = $state; Detalhes = $details.ToArray() }
}

function Get-UTTweakAction {
    <#
    .SYNOPSIS
        Human-readable list of what applying or undoing would do (used by "Simular").
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [ValidateSet('Aplicar', 'Desfazer')][string]$Modo = 'Aplicar'
    )

    $actions = New-Object System.Collections.Generic.List[string]
    $registry = @($Tweak.registro | Where-Object { $_ })
    $services = @($Tweak.servicos | Where-Object { $_ })
    $hasScript = @($Tweak.scriptAplicar | Where-Object { $_ }).Count -gt 0

    if ($Modo -eq 'Aplicar') {
        foreach ($e in $registry) {
            $current = Get-UTRegistryValue -Path $e.caminho -Name ([string]$e.nome)
            $before = if ($current.ValorExiste) { ConvertTo-UTLogValue $current.Valor } else { '<ausente>' }
            $after = if ($e.acao -eq 'remover') { '<removido>' } else { ConvertTo-UTLogValue $e.valor }
            $actions.Add(('Registro {0}\{1}: {2} -> {3}' -f $e.caminho, $e.nome, $before, $after))
        }
        foreach ($e in $services) {
            $current = Get-UTServiceState -Name $e.nome
            if ($current.Existe) { $actions.Add(('Serviço {0}: {1} -> {2}' -f $e.nome, $current.StartType, $e.inicio)) }
            else { $actions.Add(('Serviço {0}: não existe neste PC (ignorado)' -f $e.nome)) }
        }
        if ($hasScript) { Add-UTScriptedAction -Lista $actions -Tweak $Tweak -Campo 'scriptSimular' -Padrao 'Executa o script do ajuste' }
    } else {
        if ($hasScript) { Add-UTScriptedAction -Lista $actions -Tweak $Tweak -Campo 'scriptSimularDesfazer' -Padrao 'Executa o script de desfazer' }
        foreach ($e in $services) {
            $saved = Get-UTOriginalItem -Chave (Get-UTServiceStateKey -Name $e.nome)
            $target = if ($saved) { $saved.startType } else { $e.inicioOriginal }
            $actions.Add(('Serviço {0} -> {1}' -f $e.nome, $target))
        }
        foreach ($e in $registry) {
            $saved = Get-UTOriginalItem -Chave (Get-UTRegistryStateKey -Path $e.caminho -Name ([string]$e.nome))
            if ($saved) {
                $target = if ($saved.valorExistia) { ConvertTo-UTLogValue $saved.valor } else { '<removido>' }
                $source = 'valor salvo'
            } else {
                $target = if ($null -eq $e.valorOriginal) { '<removido>' } else { ConvertTo-UTLogValue $e.valorOriginal }
                $source = 'padrão do Windows'
            }
            $actions.Add(('Registro {0}\{1} -> {2} ({3})' -f $e.caminho, $e.nome, $target, $source))
        }
    }
    return $actions.ToArray()
}

function Register-UTSharedReference {
    <#
    .SYNOPSIS
        For a tweak that is already applied: adds its reference to the saved originals that other
        tweaks recorded for the same registry values/services. Returns $true when every value
        of the tweak is held that way (it then counts as applied by the program). Values the user
        set by hand (nothing saved) are left alone.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Tweak)

    $registry = @($Tweak.registro | Where-Object { $_ })
    $services = @($Tweak.servicos | Where-Object { $_ })
    if (@($Tweak.scriptAplicar | Where-Object { $_ }).Count -gt 0 -or ($registry.Count + $services.Count) -eq 0) { return $false }

    $registryKeys = @($registry | ForEach-Object { Get-UTRegistryStateKey -Path $_.caminho -Name ([string]$_.nome) })
    $serviceKeys = @($services | ForEach-Object { Get-UTServiceStateKey -Name $_.nome })
    $missing = @(@($registryKeys + $serviceKeys) | Where-Object { $null -eq (Get-UTOriginalItem -Chave $_) })
    # Services that do not exist on this PC count as held.
    $missing = @($missing | Where-Object { $_ -notlike 'servico|*' -or (Get-UTServiceState -Name $_.Substring(8)).Existe })
    if ($missing.Count -gt 0) { return $false }

    foreach ($e in $registry) { [void](Save-UTOriginalRegistryValue -Path $e.caminho -Name ([string]$e.nome) -TweakId ([string]$Tweak.id)) }
    foreach ($e in $services) {
        if ($null -ne (Get-UTOriginalItem -Chave (Get-UTServiceStateKey -Name $e.nome))) { [void](Save-UTOriginalServiceState -Name $e.nome -TweakId ([string]$Tweak.id)) }
    }
    return $true
}

function Add-UTScriptedAction {
    <#
    .SYNOPSIS
        Adds the read-only description a tweak script gives of itself (scriptSimular /
        scriptSimularDesfazer); falls back to a generic line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Lista,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [Parameter(Mandatory)][string]$Campo,
        [Parameter(Mandatory)][string]$Padrao
    )
    $lines = @($Tweak[$Campo] | Where-Object { $_ })
    if ($lines.Count -gt 0) {
        try {
            $described = @(Invoke-UTTweakScript -Lines $lines -TweakId ([string]$Tweak.id) -Contexto (Get-UTSystemContext) | Where-Object { $_ } | ForEach-Object { [string]$_ })
            if ($described.Count -gt 0) {
                foreach ($d in $described) { $Lista.Add($d) }
                return
            }
        } catch {
            Write-UTLog -Level Debug -TweakId ([string]$Tweak.id) -Message 'Não foi possível descrever a simulação deste ajuste.' -Detalhe $_.Exception.Message
        }
    }
    $Lista.Add($Padrao)
}

function Invoke-UTTweakApplyCore {
    <#
    .SYNOPSIS
        Applies one tweak: backup + original state, then registry -> services -> script.
        On any error it rolls back what this tweak had already changed and rethrows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [psobject]$Contexto
    )

    $id = [string]$Tweak.id
    $doneRegistry = New-Object System.Collections.Generic.List[object]
    $doneServices = New-Object System.Collections.Generic.List[object]
    $scriptDone = $false

    try {
        foreach ($e in @($Tweak.registro | Where-Object { $_ })) {
            $name = [string]$e.nome
            $before = Get-UTRegistryValue -Path $e.caminho -Name $name
            [void](Backup-UTRegistryKey -Path $e.caminho)
            [void](Save-UTOriginalRegistryValue -Path $e.caminho -Name $name -TweakId $id)
            $doneRegistry.Add($e)
            if ($e.acao -eq 'remover') {
                [void](Remove-UTRegistryValue -Path $e.caminho -Name $name)
                $after = '<removido>'
            } else {
                Set-UTRegistryValue -Path $e.caminho -Name $name -Type $e.tipo -Value $e.valor
                $after = $e.valor
            }
            $beforeValue = if ($before.ValorExiste) { $before.Valor } else { $null }
            Write-UTLog -Level Debug -TweakId $id -Message "Registro $($e.caminho)\$name" -Antes $beforeValue -Depois $after
        }

        foreach ($e in @($Tweak.servicos | Where-Object { $_ })) {
            $current = Get-UTServiceState -Name $e.nome
            if (-not $current.Existe) {
                Write-UTLog -Level Info -TweakId $id -Message "Serviço $($e.nome) não existe neste PC; nada a fazer."
                continue
            }
            Backup-UTServiceState -Name $e.nome
            [void](Save-UTOriginalServiceState -Name $e.nome -TweakId $id)
            $doneServices.Add($e)
            Set-UTServiceStartType -Name $e.nome -StartType $e.inicio -Parar:([bool]$e.parar)
            Write-UTLog -Level Debug -TweakId $id -Message "Serviço $($e.nome)" -Antes $current.StartType -Depois $e.inicio
        }

        $apply = @($Tweak.scriptAplicar | Where-Object { $_ })
        if ($apply.Count -gt 0) {
            [void](Invoke-UTTweakScript -Lines $apply -TweakId $id -Contexto $Contexto)
            $scriptDone = $true
        }
    } catch {
        $original = $_
        Write-UTLog -Level Aviso -TweakId $id -Message 'Falha no meio da aplicação; desfazendo o que este ajuste já tinha mudado.' -Detalhe $original.Exception.Message
        Undo-UTTweakPartial -Tweak $Tweak -Registro $doneRegistry -Servicos $doneServices -ScriptAplicado:$scriptDone -Contexto $Contexto
        throw $original
    }
}

function Undo-UTTweakPartial {
    <#
    .SYNOPSIS
        Internal rollback: undoes only the given parts of a tweak, best effort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [object[]]$Registro = @(),
        [object[]]$Servicos = @(),
        [switch]$ScriptAplicado,
        [psobject]$Contexto
    )

    $id = [string]$Tweak.id
    if ($ScriptAplicado) {
        try { [void](Invoke-UTTweakScript -Lines @($Tweak.scriptDesfazer) -TweakId $id -Contexto $Contexto) }
        catch { Write-UTLog -Level Erro -TweakId $id -Message 'Não foi possível desfazer o script deste ajuste.' -Detalhe $_.Exception.Message }
    }
    foreach ($e in @($Servicos)) {
        if ($null -eq $e) { continue }
        try { [void](Undo-UTServiceEntry -Entry $e -TweakId $id) }
        catch { Write-UTLog -Level Erro -TweakId $id -Message (Get-UTFriendlyError -ErrorRecord $_ -Alvo "o serviço $($e.nome)") -Detalhe $_.Exception.Message }
    }
    $reversed = @($Registro | Where-Object { $_ })
    [array]::Reverse($reversed)
    foreach ($e in $reversed) {
        try { [void](Undo-UTRegistryEntry -Entry $e -TweakId $id) }
        catch { Write-UTLog -Level Erro -TweakId $id -Message (Get-UTFriendlyError -ErrorRecord $_ -Alvo "$($e.caminho)\$($e.nome)") -Detalhe $_.Exception.Message }
    }
}

function Undo-UTRegistryEntry {
    <#
    .SYNOPSIS
        Restores one registry entry: saved real value first, "valorOriginal" as fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Entry,
        [Parameter(Mandatory)][string]$TweakId
    )

    $name = [string]$Entry.nome
    $status = Restore-UTOriginalRegistryValue -Path $Entry.caminho -Name $name -TweakId $TweakId
    if ($status -eq 'SemEstado') {
        if ($null -eq $Entry.valorOriginal) {
            [void](Remove-UTRegistryValue -Path $Entry.caminho -Name $name)
        } else {
            Set-UTRegistryValue -Path $Entry.caminho -Name $name -Type $Entry.tipo -Value $Entry.valorOriginal
        }
        Write-UTLog -Level Debug -TweakId $TweakId -Message "Registro $($Entry.caminho)\$name voltou ao padrão do Windows (não havia valor salvo)." -Antes $null -Depois $Entry.valorOriginal
    } elseif ($status -eq 'MantidoPorOutroTweak') {
        Write-UTLog -Level Info -TweakId $TweakId -Message "Registro $($Entry.caminho)\$name mantido: outro ajuste aplicado também usa este valor."
    }
    return $status
}

function Undo-UTServiceEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Entry,
        [Parameter(Mandatory)][string]$TweakId
    )

    $status = Restore-UTOriginalServiceState -Name $Entry.nome -TweakId $TweakId
    if ($status -eq 'SemEstado') {
        $current = Get-UTServiceState -Name $Entry.nome
        if ($current.Existe) { Set-UTServiceStartType -Name $Entry.nome -StartType $Entry.inicioOriginal }
    }
    return $status
}

function ConvertTo-UTTweakResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [Parameter(Mandatory)][string]$Acao,
        [Parameter(Mandatory)][string]$Status,
        [string]$Mensagem = '',
        [string[]]$Acoes = @()
    )
    # Pure object factory; nothing changes on the system.
    return [pscustomobject]@{
        Id             = [string]$Tweak.id
        Nome           = [string]$Tweak.nome
        Acao           = $Acao
        Status         = $Status
        Mensagem       = $Mensagem
        RequerReinicio = ([bool]$Tweak.requerReinicio -and $Status -in 'Aplicado', 'Desfeito')
        Acoes          = $Acoes
    }
}
