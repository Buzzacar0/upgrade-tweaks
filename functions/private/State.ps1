# Original state store (state\estado-original.json) and the journal of applied tweaks
# (state\aplicados.json).
#
# Rule: the value saved is the REAL value found the first time the program touches an item,
# never the default "valorOriginal" from tweaks.json. Applying again does not overwrite it, so
# an undo always returns to what the user had before Upgrade Tweaks. When two tweaks touch the
# same item, it is restored only when the last of them is undone.

function Get-UTStateFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateSet('estado-original', 'aplicados')][string]$Name)
    return (Join-Path (Get-UTPath -Name State) "$Name.json")
}

function Get-UTRegistryStateKey {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    $display = (Resolve-UTRegistryPath -Path $Path).Display
    return ('registro|{0}|{1}' -f $display, $Name).ToLowerInvariant()
}

function Get-UTServiceStateKey {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    return ('servico|{0}' -f $Name).ToLowerInvariant()
}

function Read-UTOriginalState {
    [CmdletBinding()]
    param()
    $state = Read-UTJsonFile -Path (Get-UTStateFilePath -Name 'estado-original')
    if ($null -eq $state) { $state = [ordered]@{ versao = 1; proximaOrdem = 1; itens = [ordered]@{} } }
    if ($null -eq $state['itens']) { $state['itens'] = [ordered]@{} }
    if ($null -eq $state['proximaOrdem']) { $state['proximaOrdem'] = 1 }
    return $state
}

function Write-UTOriginalState {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $path = Get-UTStateFilePath -Name 'estado-original'
    if ($PSCmdlet.ShouldProcess($path, 'Gravar estado original')) {
        Write-UTJsonFile -Path $path -InputObject $State -WhatIf:$false
    }
}

function Add-UTOriginalEntry {
    <#
    .SYNOPSIS
        Internal: inserts -Item under -Key, or only adds the tweak reference when the key already
        exists. Returns $true when a new original was recorded.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][System.Collections.IDictionary]$Item,
        [string]$TweakId
    )

    $existing = $State.itens[$Key]
    if ($null -ne $existing) {
        $refs = @(@($existing.tweaks) | Where-Object { $_ })
        if ($TweakId -and $refs -notcontains $TweakId) { $existing.tweaks = @($refs + $TweakId) }
        return $false
    }
    $Item['salvoEm'] = (Get-Date).ToString('o')
    $Item['ordem'] = [int]$State.proximaOrdem
    $Item['tweaks'] = @(@($TweakId) | Where-Object { $_ })
    $State.proximaOrdem = [int]$State.proximaOrdem + 1
    $State.itens[$Key] = $Item
    return $true
}

function Save-UTOriginalRegistryValue {
    <#
    .SYNOPSIS
        Saves the current real value of a registry entry before the first change.
        Returns $true when it was saved now, $false when an original already existed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [string]$TweakId
    )

    $key = Get-UTRegistryStateKey -Path $Path -Name $Name
    $lock = Enter-UTNamedLock -Name 'Estado'
    try {
        $state = Read-UTOriginalState
        $item = $null
        if ($null -eq $state.itens[$key]) {
            $current = Get-UTRegistryValue -Path $Path -Name $Name
            $item = [ordered]@{
                tipo                = 'registro'
                caminho             = (Resolve-UTRegistryPath -Path $Path).Display
                nome                = $Name
                chaveExistia        = $current.ChaveExiste
                primeiraChaveCriada = (Get-UTFirstMissingKey -Path $Path)
                valorExistia        = $current.ValorExiste
                tipoValor           = $current.Tipo
                valor               = $current.Valor
            }
        }
        $isNew = Add-UTOriginalEntry -State $state -Key $key -Item $item -TweakId $TweakId
        Write-UTOriginalState -State $state
        return $isNew
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function Save-UTOriginalServiceState {
    <#
    .SYNOPSIS
        Saves the real start type of a service before the first change.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$TweakId
    )

    $key = Get-UTServiceStateKey -Name $Name
    $lock = Enter-UTNamedLock -Name 'Estado'
    try {
        $state = Read-UTOriginalState
        $item = $null
        if ($null -eq $state.itens[$key]) {
            $current = Get-UTServiceState -Name $Name
            $item = [ordered]@{ tipo = 'servico'; nome = $Name; existia = $current.Existe; startType = $current.StartType }
        }
        $isNew = Add-UTOriginalEntry -State $state -Key $key -Item $item -TweakId $TweakId
        Write-UTOriginalState -State $state
        return $isNew
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function Save-UTOriginalItem {
    <#
    .SYNOPSIS
        Saves an arbitrary original value (power plan, bcdedit entry, adapter property...).
        -Chave identifies it; -Dados is whatever the matching undo needs.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Chave,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Dados,
        [string]$TweakId
    )

    $key = ('generico|{0}' -f $Chave).ToLowerInvariant()
    $lock = Enter-UTNamedLock -Name 'Estado'
    try {
        $state = Read-UTOriginalState
        $item = $null
        if ($null -eq $state.itens[$key]) { $item = [ordered]@{ tipo = 'generico'; chave = $Chave; dados = $Dados } }
        $isNew = Add-UTOriginalEntry -State $state -Key $key -Item $item -TweakId $TweakId
        Write-UTOriginalState -State $state
        return $isNew
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function Get-UTOriginalItem {
    <#
    .SYNOPSIS
        Returns a saved original item, or $null. -Chave is the full key
        (registro|..., servico|..., generico|...).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Chave)
    return (Read-UTOriginalState).itens[$Chave.ToLowerInvariant()]
}

function Get-UTOriginalStateItem {
    <#
    .SYNOPSIS
        Every saved original, newest first (the order "Desfazer TUDO" uses).
    #>
    [CmdletBinding()]
    param()
    $state = Read-UTOriginalState
    $items = foreach ($key in @($state.itens.Keys)) {
        $item = $state.itens[$key]
        [pscustomobject]@{ Chave = $key; Ordem = [int]$item.ordem; Item = $item }
    }
    return ($items | Sort-Object Ordem -Descending)
}

function Resolve-UTOriginalReference {
    <#
    .SYNOPSIS
        Internal: drops a tweak reference. Returns the item when it must be restored now (removed
        from the store), the string 'Mantido' when another tweak still uses it, or $null when
        nothing was saved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [Parameter(Mandatory)][string]$Key,
        [string]$TweakId,
        [switch]$Force
    )

    $item = $State.itens[$Key]
    if ($null -eq $item) { return $null }
    $refs = @(@($item.tweaks) | Where-Object { $_ -and $_ -ne $TweakId })
    if ($refs.Count -gt 0 -and -not $Force) {
        $item.tweaks = $refs
        return 'Mantido'
    }
    $State.itens.Remove($Key)
    return $item
}

function Restore-UTRegistryItem {
    <#
    .SYNOPSIS
        Internal: writes a saved registry item back (or deletes the value/keys the program created).
        -WhatIf reaches the inner Set/Remove calls through $WhatIfPreference.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Item)

    if ($Item.valorExistia) {
        Set-UTRegistryValue -Path $Item.caminho -Name $Item.nome -Type $Item.tipoValor -Value $Item.valor
    } else {
        [void](Remove-UTRegistryValue -Path $Item.caminho -Name $Item.nome)
    }
    if ($Item.primeiraChaveCriada) {
        [void](Remove-UTEmptyKeyChain -Path $Item.caminho -StopAt $Item.primeiraChaveCriada)
    }
}

function Restore-UTServiceItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Item)

    if ($Item.existia -and $Item.startType) {
        Set-UTServiceStartType -Name $Item.nome -StartType $Item.startType
    }
}

function Restore-UTOriginalEntry {
    <#
    .SYNOPSIS
        Internal: common undo path for registry and service entries. The item is removed from
        the store only after it was restored successfully.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$TweakId,
        [switch]$Force
    )

    $lock = Enter-UTNamedLock -Name 'Estado'
    try {
        $state = Read-UTOriginalState
        $r = Resolve-UTOriginalReference -State $state -Key $Key -TweakId $TweakId -Force:$Force
        if ($null -eq $r) { return 'SemEstado' }
        if ($r -is [string]) {
            Write-UTOriginalState -State $state
            return 'MantidoPorOutroTweak'
        }
        # Restore first: if it throws, the state file is not written and the original stays recorded.
        switch ($r.tipo) {
            'registro' { Restore-UTRegistryItem -Item $r }
            'servico' { Restore-UTServiceItem -Item $r }
            default { throw "Item '$Key' não pode ser restaurado automaticamente (tipo $($r.tipo))." }
        }
        Write-UTOriginalState -State $state
        return 'Restaurado'
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function Restore-UTOriginalRegistryValue {
    <#
    .SYNOPSIS
        Puts back the saved original of a registry entry.
    .OUTPUTS
        'Restaurado', 'MantidoPorOutroTweak' or 'SemEstado' (nothing saved: the caller falls back
        to "valorOriginal" from tweaks.json).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [string]$TweakId,
        [switch]$Force
    )
    return (Restore-UTOriginalEntry -Key (Get-UTRegistryStateKey -Path $Path -Name $Name) -TweakId $TweakId -Force:$Force)
}

function Restore-UTOriginalServiceState {
    <#
    .SYNOPSIS
        Puts back the saved start type of a service. Same outputs as Restore-UTOriginalRegistryValue.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$TweakId,
        [switch]$Force
    )
    return (Restore-UTOriginalEntry -Key (Get-UTServiceStateKey -Name $Name) -TweakId $TweakId -Force:$Force)
}

function Pop-UTOriginalItem {
    <#
    .SYNOPSIS
        For generic items: drops the tweak reference and returns the saved data when it must be
        restored now (the caller restores it and the item leaves the store), the string
        'MantidoPorOutroTweak', or $null when nothing was saved.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Chave,
        [string]$TweakId,
        [switch]$Force
    )

    $key = ('generico|{0}' -f $Chave).ToLowerInvariant()
    $lock = Enter-UTNamedLock -Name 'Estado'
    try {
        $state = Read-UTOriginalState
        $r = Resolve-UTOriginalReference -State $state -Key $key -TweakId $TweakId -Force:$Force
        if ($null -eq $r) { return $null }
        Write-UTOriginalState -State $state
        if ($r -is [string]) { return 'MantidoPorOutroTweak' }
        return $r.dados
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

#region Applied journal
function Read-UTAppliedJournal {
    [CmdletBinding()]
    param()
    $journal = Read-UTJsonFile -Path (Get-UTStateFilePath -Name 'aplicados')
    if ($null -eq $journal) { $journal = [ordered]@{ versao = 1; registros = @() } }
    if ($null -eq $journal['registros']) { $journal['registros'] = @() }
    return $journal
}

function Add-UTAppliedRecord {
    <#
    .SYNOPSIS
        Records that a tweak was applied. Re-applying keeps the first position, so
        "Desfazer TUDO" undoes in the true reverse order of the first applications.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId, [string]$Detalhe)

    $path = Get-UTStateFilePath -Name 'aplicados'
    if (-not $PSCmdlet.ShouldProcess($path, "Registrar $TweakId como aplicado")) { return }
    $lock = Enter-UTNamedLock -Name 'Aplicados'
    try {
        $journal = Read-UTAppliedJournal
        if (@(@($journal.registros) | Where-Object { $_.tweakId -eq $TweakId }).Count -eq 0) {
            $record = [ordered]@{
                tweakId        = $TweakId
                aplicadoEm     = (Get-Date).ToString('o')
                versaoPrograma = [string](Get-UTSyncValue -Key 'Versao')
                detalhe        = $Detalhe
            }
            $journal.registros = @(@($journal.registros) + $record)
            Write-UTJsonFile -Path $path -InputObject $journal -WhatIf:$false
        }
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function Remove-UTAppliedRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)

    $path = Get-UTStateFilePath -Name 'aplicados'
    if (-not $PSCmdlet.ShouldProcess($path, "Remover $TweakId da lista de aplicados")) { return }
    $lock = Enter-UTNamedLock -Name 'Aplicados'
    try {
        $journal = Read-UTAppliedJournal
        $kept = @(@($journal.registros) | Where-Object { $_.tweakId -ne $TweakId })
        if ($kept.Count -ne @($journal.registros).Count) {
            $journal.registros = $kept
            Write-UTJsonFile -Path $path -InputObject $journal -WhatIf:$false
        }
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function Get-UTAppliedRecord {
    <#
    .SYNOPSIS
        Applied tweaks in the order they were first applied (-Reverse gives the undo order).
    #>
    [CmdletBinding()]
    param([switch]$Reverse)
    $records = @((Read-UTAppliedJournal).registros)
    if ($Reverse) { [array]::Reverse($records) }
    return $records
}
#endregion
