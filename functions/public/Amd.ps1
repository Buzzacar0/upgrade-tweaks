# AMD Radeon: the Adrenalin settings recommended for the game, written straight to the driver
# through ADLX (config\amd-adlx.json), plus FreeSync on every monitor that supports it and the
# texture filtering quality (UMD registry of the driver, not covered by ADLX).

#region Targets
function Get-UTAmdTargetGpu {
    <#
    .SYNOPSIS
        AMD GPUs to configure: the dedicated ones; integrated only when there is no dedicated
        AMD card (APU used for gaming).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Sessao)
    $all = @($Sessao.Gpus())
    $discrete = @($all | Where-Object { $_.Tipo -eq 2 })
    if ($discrete.Count -gt 0) { return $discrete }
    return $all
}

function Get-UTAmdUmdKey {
    <#
    .SYNOPSIS
        UMD registry keys of the AMD display adapters (Class\{4d36e968...}\NNNN\UMD).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $keys = foreach ($k in @(Get-ChildItem -Path $class -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
        $provider = Get-UTRegistryValue -Path "$class\$($k.PSChildName)" -Name 'ProviderName'
        if ($provider.ValorExiste -and [string]$provider.Valor -match 'Advanced Micro Devices|AMD|ATI') {
            $umd = "$class\$($k.PSChildName)\UMD"
            if (Test-UTRegistryKey -Path $umd) { $umd }
        }
    }
    return @($keys)
}

function ConvertFrom-UTUmdString {
    # UMD values are UTF-16 text stored as REG_BINARY ("2" = 32 00).
    param([AllowNull()][object]$Valor)
    if ($null -eq $Valor) { return $null }
    if ($Valor -is [byte[]]) { return ([Text.Encoding]::Unicode.GetString($Valor)).TrimEnd([char]0) }
    if ($Valor -is [string] -and $Valor -match '^([0-9A-Fa-f]{2})+$') {
        $bytes = for ($i = 0; $i -lt $Valor.Length; $i += 2) { [Convert]::ToByte($Valor.Substring($i, 2), 16) }
        return ([Text.Encoding]::Unicode.GetString([byte[]]$bytes)).TrimEnd([char]0)
    }
    return [string]$Valor
}
#endregion

#region Status
function Get-UTAmdSettingStatus {
    <#
    .SYNOPSIS
        Side by side for the GPU tab: each setting, current value, recommended value, whether
        it already matches and whether the card supports it. Read only.
    #>
    [CmdletBinding()]
    param()
    $cfg = Get-UTConfig -Name 'amd-adlx'
    $session = Open-UTAdlxSession
    try {
        $gpus = @(Get-UTAmdTargetGpu -Sessao $session)
        foreach ($item in @($cfg.configuracoes)) {
            $targets = @($(if ($item.global) { $gpus | Select-Object -First 1 } else { $gpus }))
            foreach ($g in $targets) {
                $v = $session.Get([string]$item.chave, $g.Ptr)
                $current = $(if ($v.Suportado) { $item.rotulos[[string]$v.Valor] } else { 'Não suportado' })
                if (-not $current) { $current = [string]$v.Valor }
                [pscustomobject]@{
                    Chave       = [string]$item.chave
                    Nome        = [string]$item.nome
                    Placa       = $(if ($item.global) { 'Todas' } else { $g.Nome })
                    GpuId       = $(if ($item.global) { 'global' } else { [string]$g.Id })
                    Atual       = $current
                    Recomendado = [string]$item.rotulos[[string]$item.recomendado]
                    Suportado   = [bool]$v.Suportado
                    Igual       = ([bool]$v.Suportado -and [int]$v.Valor -eq [int]$item.recomendado)
                    Explicacao  = [string]$item.explicacao
                }
            }
        }
        foreach ($d in @($session.FreeSyncDisplays())) {
            $v = $session.GetFreeSync($d.Value)
            [pscustomobject]@{
                Chave = 'freeSync'; Nome = "$($cfg.freeSync.nome) ($($d.Key))"; Placa = $d.Key; GpuId = "monitor:$($d.Key)"
                Atual = $(if (-not $v.Suportado) { 'Monitor sem FreeSync' } elseif ($v.Valor) { 'Ligado' } else { 'Desligado' })
                Recomendado = 'Ligado'; Suportado = [bool]$v.Suportado; Igual = ([bool]$v.Suportado -and [int]$v.Valor -eq 1)
                Explicacao = [string]$cfg.freeSync.explicacao
            }
        }
    } finally {
        $session.Dispose()
    }
    foreach ($umd in @(Get-UTAmdUmdKey)) {
        $raw = Get-UTRegistryValue -Path $umd -Name 'TFQ'
        $tfq = ConvertFrom-UTUmdString $(if ($raw.ValorExiste) { $raw.Valor } else { $null })
        [pscustomobject]@{
            Chave = 'tfq'; Nome = [string]$cfg.filtragemTextura.nome; Placa = (Split-Path -Leaf (Split-Path -Parent $umd)); GpuId = "umd:$umd"
            Atual = $(if ($null -eq $tfq) { 'Padrão do driver' } elseif ($cfg.filtragemTextura.rotulos.Contains($tfq)) { $cfg.filtragemTextura.rotulos[$tfq] } else { $tfq })
            Recomendado = [string]$cfg.filtragemTextura.rotulos[[string]$cfg.filtragemTextura.valor]; Suportado = $true
            Igual = ($tfq -eq [string]$cfg.filtragemTextura.valor); Explicacao = [string]$cfg.filtragemTextura.explicacao
        }
    }
}

function Get-UTAmdPlannedAction {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $rows = @(Get-UTAmdSettingStatus | Where-Object { $_.Suportado -and -not $_.Igual })
    if ($rows.Count -eq 0) { return @('Nada a mudar: tudo já está no recomendado.') }
    return @($rows | ForEach-Object { "$($_.Nome) [$($_.Placa)]: $($_.Atual) -> $($_.Recomendado)" })
}

function Test-UTAmdSetting {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $rows = @(Get-UTAmdSettingStatus | Where-Object { $_.Suportado })
    return ($rows.Count -gt 0 -and @($rows | Where-Object { -not $_.Igual }).Count -eq 0)
}
#endregion

#region Apply / undo
function Set-UTAmdRecommended {
    <#
    .SYNOPSIS
        Writes the recommended values. Every value changed is saved first (generic items
        amd|<gpu>|<setting>), so undo puts back exactly what was there.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $cfg = Get-UTConfig -Name 'amd-adlx'
    $session = Open-UTAdlxSession
    try {
        $gpus = @(Get-UTAmdTargetGpu -Sessao $session)
        if ($gpus.Count -eq 0) { throw 'Nenhuma placa AMD encontrada pelo driver.' }
        foreach ($item in @($cfg.configuracoes)) {
            $targets = @($(if ($item.global) { $gpus | Select-Object -First 1 } else { $gpus }))
            foreach ($g in $targets) {
                $key = [string]$item.chave
                $v = $session.Get($key, $g.Ptr)
                if (-not $v.Suportado -or [int]$v.Valor -eq [int]$item.recomendado) { continue }
                if (-not $PSCmdlet.ShouldProcess("$($item.nome) ($($g.Nome))", "Definir $($item.recomendado)")) { continue }
                $scope = $(if ($item.global) { 'global' } else { [string]$g.Id })
                [void](Save-UTOriginalItem -Chave "amd|$scope|$key" -Dados ([ordered]@{ chave = $key; gpu = $scope; valor = [int]$v.Valor }) -TweakId $TweakId)
                $r = $session.Set($key, $g.Ptr, [int]$item.recomendado)
                if ($r -ne 0 -and $r -ne 1) { throw "O driver AMD recusou mudar '$($item.nome)' (código $r)." }
                Write-UTLog -Level Info -TweakId $TweakId -Message "$($item.nome): $($item.rotulos[[string]$v.Valor]) -> $($item.rotulos[[string]$item.recomendado])."
            }
        }
        foreach ($d in @($session.FreeSyncDisplays())) {
            $v = $session.GetFreeSync($d.Value)
            if (-not $v.Suportado -or [int]$v.Valor -eq 1) { continue }
            if (-not $PSCmdlet.ShouldProcess("FreeSync ($($d.Key))", 'Ligar')) { continue }
            [void](Save-UTOriginalItem -Chave "amd|freesync|$($d.Key)" -Dados ([ordered]@{ monitor = $d.Key; valor = 0 }) -TweakId $TweakId)
            $r = $session.SetFreeSync($d.Value, $true)
            if ($r -ne 0 -and $r -ne 1) { throw "O driver AMD recusou ligar o FreeSync em $($d.Key) (código $r)." }
        }
    } finally {
        $session.Dispose()
    }
    # The driver stores the digit as UTF-16 without terminator ("2" = 32 00), like Adrenalin does.
    $wanted = [Text.Encoding]::Unicode.GetBytes([string]$cfg.filtragemTextura.valor)
    foreach ($umd in @(Get-UTAmdUmdKey)) {
        $raw = Get-UTRegistryValue -Path $umd -Name 'TFQ'
        $current = ConvertFrom-UTUmdString $(if ($raw.ValorExiste) { $raw.Valor } else { $null })
        if ($current -eq [string]$cfg.filtragemTextura.valor) { continue }
        if (-not $PSCmdlet.ShouldProcess("$umd\TFQ", 'Desempenho')) { continue }
        [void](Save-UTOriginalRegistryValue -Path $umd -Name 'TFQ' -TweakId $TweakId)
        Set-UTRegistryValue -Path $umd -Name 'TFQ' -Type Binary -Value $wanted
    }
}

function Restore-UTAmdRecommended {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    $pending = @(Get-UTOriginalStateItem | Where-Object { $_.Item.tipo -eq 'generico' -and ([string]$_.Item.chave) -like 'amd|*' -and @($_.Item.tweaks) -contains $TweakId })
    if ($pending.Count -gt 0) {
        $session = Open-UTAdlxSession
        try {
            $gpus = @($session.Gpus())
            $displays = @($session.FreeSyncDisplays())
            foreach ($entry in $pending) {
                $d = Pop-UTOriginalItem -Chave $entry.Item.chave -TweakId $TweakId
                if ($d -isnot [System.Collections.IDictionary]) { continue }
                if ($d.Contains('monitor')) {
                    $fs = @($displays | Where-Object { $_.Key -eq [string]$d.monitor } | Select-Object -First 1)
                    if ($fs.Count -gt 0) { [void]$session.SetFreeSync($fs[0].Value, ([int]$d.valor -eq 1)) }
                    continue
                }
                $g = @($(if ($d.gpu -eq 'global') { $gpus | Select-Object -First 1 } else { $gpus | Where-Object { [string]$_.Id -eq [string]$d.gpu } | Select-Object -First 1 }))
                if ($g.Count -eq 0) { Write-UTLog -Level Aviso -TweakId $TweakId -Message "A placa AMD $($d.gpu) não está mais no PC; '$($d.chave)' não foi restaurado."; continue }
                [void]$session.Set([string]$d.chave, $g[0].Ptr, [int]$d.valor)
            }
        } finally {
            $session.Dispose()
        }
    }
    foreach ($umd in @(Get-UTAmdUmdKey)) { [void](Restore-UTOriginalRegistryValue -Path $umd -Name 'TFQ' -TweakId $TweakId) }
}
#endregion
