# "GPU" tab, NVIDIA part: the "Gerenciar as configurações em 3D" settings written straight to
# the driver profile database (DRS) for the Call of Duty profile or globally, with backup and
# undo; output dynamic range; power limit; Resizable BAR.
# All DRS access goes through Open-UTNvDrsSession, so tests replace it with an in-memory fake.

#region Recommendations
function Get-UTGpuOption {
    <#
    .SYNOPSIS
        Options the user sets in the GPU tab: ComGsync (monitor has G-SYNC/FreeSync) and HzMonitor
        (defaults to the highest refresh rate found).
    #>
    [CmdletBinding()]
    param()
    $options = Get-UTSyncValue -Key 'OpcoesGpu'
    $gsync = $false
    $hz = $null
    if ($options) {
        if ($null -ne $options['ComGsync']) { $gsync = [bool]$options['ComGsync'] }
        if ($options['HzMonitor']) { $hz = [int]$options['HzMonitor'] }
    }
    if (-not $hz) {
        $hw = Get-UTSyncValue -Key 'Hardware'
        if ($hw -and $hw.Monitores) { $hz = (@($hw.Monitores) | Measure-Object HzMaximo -Maximum).Maximum }
    }
    if (-not $hz) {
        try { $hz = (@(Get-UTDisplayInfo) | Measure-Object HzMaximo -Maximum).Maximum } catch { $hz = 60 }
    }
    return [pscustomobject]@{ ComGsync = $gsync; HzMonitor = [int]$hz }
}

function ConvertTo-UTDrsValue {
    [CmdletBinding()]
    [OutputType([uint32])]
    param([Parameter(Mandatory)][object]$Value)
    $n = ConvertTo-UTInt64 $Value
    return [uint32]([BitConverter]::ToUInt32([BitConverter]::GetBytes([int64]$n), 0))
}

function Resolve-UTNvidiaRecommendation {
    <#
    .SYNOPSIS
        What the program sets for one nvidia-drs.json item in one scope ('perfil' or 'global'):
        Rotulo and Valores (one per id), or $null when the item is left alone in that scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Item,
        [Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo,
        [Parameter(Mandatory)][psobject]$Opcoes
    )
    if ($null -eq $Item.recomendado -or @($Item.ids).Count -eq 0) { return $null }
    $choice = $Item.recomendado[$Escopo]
    if (-not $choice) { return $null }

    if ($choice -eq 'regra:vsync') { $choice = $(if ($Opcoes.ComGsync) { 'ligado' } else { 'desligado' }) }
    elseif ($choice -eq 'regra:gsync') {
        if (-not $Opcoes.ComGsync) { return $null }
        $choice = 'telaCheiaJanela'
    } elseif ($choice -eq 'regra:limiteFps') {
        $fps = 0
        if ($Opcoes.ComGsync -and $Opcoes.HzMonitor -gt 3) { $fps = $Opcoes.HzMonitor - 3 }
        $label = $(if ($fps -gt 0) { "$fps FPS ($($Opcoes.HzMonitor) Hz - 3)" } else { 'Desligado' })
        return [pscustomobject]@{ Opcao = 'numero'; Rotulo = $label; Valores = @([uint32]$fps) }
    }

    $option = $Item.opcoes[$choice]
    if ($null -eq $option) { throw "nvidia-drs.json: a opção '$choice' de '$($Item.chave)' não existe." }
    return [pscustomobject]@{ Opcao = $choice; Rotulo = [string]$option.rotulo; Valores = @($option.valores | ForEach-Object { ConvertTo-UTDrsValue $_ }) }
}

function Get-UTNvidiaCurrentLabel {
    # Turns the values read from the driver into the option label of the panel.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Item, [Parameter(Mandatory)][object[]]$Lidos)
    if (@($Lidos | Where-Object { $_.Existe }).Count -eq 0) { return 'Padrão do driver' }
    if ($Item.tipo -eq 'numero') {
        $v = [uint32]$Lidos[0].Valor
        return $(if ($v -eq 0) { 'Desligado' } else { "$v FPS" })
    }
    foreach ($key in @($Item.opcoes.Keys)) {
        $vals = @($Item.opcoes[$key].valores | ForEach-Object { ConvertTo-UTDrsValue $_ })
        $match = $true
        for ($i = 0; $i -lt $vals.Count; $i++) {
            $read = $Lidos[$i]
            $current = $(if ($read.Existe) { [uint32]$read.Valor } else { $null })
            if ($current -ne $vals[$i]) { $match = $false; break }
        }
        if ($match) { return [string]$Item.opcoes[$key].rotulo }
    }
    return ('Personalizado (' + ((@($Lidos) | ForEach-Object { if ($_.Existe) { '0x{0:X8}' -f [uint32]$_.Valor } else { 'padrão' } }) -join ', ') + ')')
}
#endregion

#region Target profile
function Get-UTNvidiaTargetProfile {
    <#
    .SYNOPSIS
        Global: the base profile. Perfil: the driver profile that already contains one of the
        Call of Duty executables (usually NVIDIA's own, e.g. "Call of Duty: Black Ops 7"), else
        the "Upgrade Tweaks - Warzone" profile, else a profile still to be created.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Sessao,
        [Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo,
        [psobject]$Contexto
    )
    if ($Escopo -eq 'global') {
        $h = $Sessao.BaseProfile()
        return [pscustomobject]@{ Handle = $h; Nome = [string]$Sessao.ProfileName($h); Existe = $true; Executaveis = @(); Criar = $false }
    }
    $exes = @(Get-UTGameExecutable -Contexto $Contexto | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
    if ($exes.Count -eq 0) { throw 'Call of Duty não encontrado; não há perfil do jogo para ajustar.' }
    foreach ($exe in $exes) {
        $h = $Sessao.FindProfileByApp($exe)
        if ($h -ne [IntPtr]::Zero) { return [pscustomobject]@{ Handle = $h; Nome = [string]$Sessao.ProfileName($h); Existe = $true; Executaveis = $exes; Criar = $false } }
    }
    $name = [string](Get-UTConfig -Name 'nvidia-drs').nomePerfilNovo
    $h = $Sessao.FindProfile($name)
    if ($h -ne [IntPtr]::Zero) { return [pscustomobject]@{ Handle = $h; Nome = $name; Existe = $true; Executaveis = $exes; Criar = $false } }
    return [pscustomobject]@{ Handle = [IntPtr]::Zero; Nome = $name; Existe = $false; Executaveis = $exes; Criar = $true }
}
#endregion

#region Status / apply / undo
function Get-UTNvidiaDrsStatus {
    <#
    .SYNOPSIS
        Side by side for the GPU tab: each setting, current value, recommended value and whether
        they already match. Read only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo,
        [psobject]$Contexto
    )
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    $cfg = Get-UTConfig -Name 'nvidia-drs'
    $opts = Get-UTGpuOption
    $session = Open-UTNvDrsSession
    try {
        $target = Get-UTNvidiaTargetProfile -Sessao $session -Escopo $Escopo -Contexto $Contexto
        foreach ($item in @($cfg.configuracoes)) {
            $rec = Resolve-UTNvidiaRecommendation -Item $item -Escopo $Escopo -Opcoes $opts
            $read = @()
            if ($target.Existe) { $read = @(@($item.ids) | ForEach-Object { $session.GetSetting($target.Handle, (ConvertTo-UTDrsValue $_)) }) }
            $current = $(if ($target.Existe -and $read.Count -gt 0) { Get-UTNvidiaCurrentLabel -Item $item -Lidos $read } elseif ($read.Count -eq 0 -and @($item.ids).Count -gt 0) { 'Padrão do driver' } else { '—' })
            $equal = $false
            if ($rec -and $read.Count -gt 0) {
                $equal = $true
                for ($i = 0; $i -lt $rec.Valores.Count; $i++) {
                    if (-not ($read[$i].Existe -and [uint32]$read[$i].Valor -eq $rec.Valores[$i])) { $equal = $false; break }
                }
            }
            [pscustomobject]@{
                Chave       = [string]$item.chave
                Nome        = [string]$item.nome
                NomeApp     = [string]$item.nomeApp
                Perfil      = $target.Nome
                Atual       = $current
                Recomendado = $(if ($rec) { $rec.Rotulo } else { 'Manter (informativo)' })
                Igual       = $equal
                Aplicavel   = ($null -ne $rec)
                Explicacao  = [string]$item.explicacao
            }
        }
    } finally {
        $session.Dispose()
    }
}

function Backup-UTNvidiaDrsFile {
    <#
    .SYNOPSIS
        Full export of the driver profile database to the session backup folder (restorable with
        Restore-UTNvidiaBackupFile).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][object]$Sessao)
    $folder = Join-Path (Get-UTSessionBackupFolder) 'nvidia'
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
    $file = Join-Path $folder ('drs-' + (Get-Date).ToString('HHmmss') + '.txt')
    if ($PSCmdlet.ShouldProcess($file, 'Exportar o banco de perfis do driver NVIDIA')) { $Sessao.SaveToFile($file) }
    return $file
}

function Invoke-UTNvidiaDrsCore {
    <#
    .SYNOPSIS
        Applies the recommended values of nvidia-drs.json to the Call of Duty profile ('perfil') or
        globally ('global'). Saves every original value first. Called by UT_GPU_NvidiaPerfil /
        UT_GPU_NvidiaGlobal, or with -Chave for a single item from the GPU tab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo,
        [Parameter(Mandatory)][string]$TweakId,
        [psobject]$Contexto,
        [string[]]$Chave
    )
    if ($null -eq $Contexto) { $Contexto = Get-UTSystemContext }
    if (-not (Test-UTNvApiAvailable)) { throw 'Driver NVIDIA não encontrado (NVAPI indisponível).' }
    $cfg = Get-UTConfig -Name 'nvidia-drs'
    $opts = Get-UTGpuOption
    $session = Open-UTNvDrsSession
    try {
        [void](Backup-UTNvidiaDrsFile -Sessao $session)
        $target = Get-UTNvidiaTargetProfile -Sessao $session -Escopo $Escopo -Contexto $Contexto
        if ($target.Criar) {
            $target.Handle = $session.CreateProfile($target.Nome)
            foreach ($exe in $target.Executaveis) { $session.AddApplication($target.Handle, $exe) }
            [void](Save-UTOriginalItem -Chave "nvidia|perfilcriado|$($target.Nome)" -Dados ([ordered]@{ nome = $target.Nome }) -TweakId $TweakId)
            Write-UTLog -Level Info -TweakId $TweakId -Message "Perfil '$($target.Nome)' criado no driver NVIDIA com $($target.Executaveis -join ', ')."
        }
        foreach ($item in @($cfg.configuracoes)) {
            if ($Chave -and $Chave -notcontains $item.chave) { continue }
            $rec = Resolve-UTNvidiaRecommendation -Item $item -Escopo $Escopo -Opcoes $opts
            if ($null -eq $rec) { continue }
            $ids = @($item.ids | ForEach-Object { ConvertTo-UTDrsValue $_ })
            for ($i = 0; $i -lt $ids.Count; $i++) {
                $id = $ids[$i]
                $before = $session.GetSetting($target.Handle, $id)
                [void](Save-UTOriginalItem -Chave ('nvidia|{0}|{1}|{2:X8}' -f $Escopo, $target.Nome, $id) -Dados ([ordered]@{
                            escopo = $Escopo; perfil = $target.Nome; id = [int64]$id
                            existia = [bool]$before.Existe; valor = [int64]$before.Valor; predefinido = [bool]$before.Predefinido
                        }) -TweakId $TweakId)
                $session.SetDword($target.Handle, $id, $rec.Valores[$i])
            }
            Write-UTLog -Level Debug -TweakId $TweakId -Message "NVIDIA ($($target.Nome)): $($item.nome) = $($rec.Rotulo)"
        }
        $session.Save()
    } finally {
        $session.Dispose()
    }
}

function Undo-UTNvidiaDrsCore {
    <#
    .SYNOPSIS
        Puts every saved NVIDIA value back: a value that did not exist is removed (the profile
        inherits again), a predefined one returns to NVIDIA's default, a user value is rewritten.
        A profile the program created is deleted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo,
        [Parameter(Mandatory)][string]$TweakId,
        [string[]]$Chave
    )
    $cfg = Get-UTConfig -Name 'nvidia-drs'
    $onlyIds = $null
    if ($Chave) {
        $onlyIds = @($cfg.configuracoes | Where-Object { $Chave -contains $_.chave } | ForEach-Object { $_.ids } | ForEach-Object { [int64](ConvertTo-UTDrsValue $_) })
    }
    $session = Open-UTNvDrsSession
    try {
        $profiles = @{}
        foreach ($entry in @(Get-UTOriginalStateItem)) {
            $item = $entry.Item
            if ($item.tipo -ne 'generico' -or ([string]$item.chave) -notlike "nvidia|$Escopo|*" -or @($item.tweaks) -notcontains $TweakId) { continue }
            if ($null -ne $onlyIds -and $onlyIds -notcontains [int64]$item.dados.id) { continue }
            $d = Pop-UTOriginalItem -Chave $item.chave -TweakId $TweakId
            if ($d -isnot [System.Collections.IDictionary]) { continue }
            $profileName = [string]$d.perfil
            if (-not $profiles.ContainsKey($profileName)) {
                $profiles[$profileName] = $(if ($Escopo -eq 'global') { $session.BaseProfile() } else { $session.FindProfile($profileName) })
            }
            $h = $profiles[$profileName]
            if ($h -eq [IntPtr]::Zero) { continue }
            $id = [uint32]$d.id
            if (-not $d.existia) { [void]$session.DeleteSetting($h, $id) }
            elseif ($d.predefinido) { [void]$session.RestoreDefaultSetting($h, $id) }
            else { $session.SetDword($h, $id, [uint32]$d.valor) }
        }
        if (-not $Chave) {
            foreach ($entry in @(Get-UTOriginalStateItem)) {
                $item = $entry.Item
                if ($item.tipo -ne 'generico' -or ([string]$item.chave) -notlike 'nvidia|perfilcriado|*' -or @($item.tweaks) -notcontains $TweakId) { continue }
                $d = Pop-UTOriginalItem -Chave $item.chave -TweakId $TweakId
                if ($d -is [System.Collections.IDictionary]) {
                    $h = $session.FindProfile([string]$d.nome)
                    if ($h -ne [IntPtr]::Zero) { $session.DeleteProfile($h) }
                }
            }
        }
        $session.Save()
    } finally {
        $session.Dispose()
    }
}

function Test-UTNvidiaDrsSetting {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo, [psobject]$Contexto)
    if (-not (Test-UTNvApiAvailable)) { return $false }
    $rows = @(Get-UTNvidiaDrsStatus -Escopo $Escopo -Contexto $Contexto | Where-Object { $_.Aplicavel })
    return ($rows.Count -gt 0 -and @($rows | Where-Object { -not $_.Igual }).Count -eq 0)
}

function Get-UTNvidiaDrsPlannedAction {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo, [psobject]$Contexto)
    $rows = @(Get-UTNvidiaDrsStatus -Escopo $Escopo -Contexto $Contexto | Where-Object { $_.Aplicavel -and -not $_.Igual })
    if ($rows.Count -eq 0) { return @('Nada a mudar: tudo já está no recomendado.') }
    $lines = @("Perfil do driver: $($rows[0].Perfil)")
    $lines += @($rows | ForEach-Object { "$($_.Nome): $($_.Atual) -> $($_.Recomendado)" })
    return $lines
}

function Restore-UTNvidiaDefault {
    <#
    .SYNOPSIS
        "Restaurar padrões NVIDIA": the Call of Duty profile (or the global one) back to NVIDIA's
        defaults. A full backup of the database is exported first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][ValidateSet('perfil', 'global')][string]$Escopo, [psobject]$Contexto)
    Assert-UTAdmin
    $session = Open-UTNvDrsSession
    try {
        $target = Get-UTNvidiaTargetProfile -Sessao $session -Escopo $Escopo -Contexto $Contexto
        if (-not $target.Existe) { return }
        if (-not $PSCmdlet.ShouldProcess($target.Nome, 'Restaurar os padrões da NVIDIA')) { return }
        [void](Backup-UTNvidiaDrsFile -Sessao $session)
        $session.RestoreProfileDefault($target.Handle)
        $session.Save()
        Write-UTLog -Level Sucesso -Message "Perfil NVIDIA '$($target.Nome)' voltou aos padrões da NVIDIA."
    } finally {
        $session.Dispose()
    }
}

function Get-UTNvidiaBackupFile {
    [CmdletBinding()]
    param()
    $base = Get-UTPath -Name Backups
    if (-not (Test-Path -LiteralPath $base)) { return }
    Get-ChildItem -LiteralPath $base -Recurse -Filter 'drs-*.txt' -File | Sort-Object LastWriteTime -Descending |
        ForEach-Object { [pscustomobject]@{ Arquivo = $_.FullName; Data = $_.LastWriteTime } }
}

function Restore-UTNvidiaBackupFile {
    <#
    .SYNOPSIS
        "Restaurar meu backup": loads an exported database file back into the driver.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$Arquivo)
    Assert-UTAdmin
    if (-not (Test-Path -LiteralPath $Arquivo)) { throw "Arquivo não encontrado: $Arquivo" }
    if (-not $PSCmdlet.ShouldProcess($Arquivo, 'Restaurar o banco de perfis do driver NVIDIA')) { return }
    $session = Open-UTNvDrsSession
    try {
        $session.LoadFromFile($Arquivo)
        $session.Save()
    } finally {
        $session.Dispose()
    }
    Write-UTLog -Level Sucesso -Message "Configurações NVIDIA restauradas de $Arquivo"
}
#endregion

#region Output color range
function Get-UTNvDisplayColor {
    # Thin wrappers over the static NVAPI calls, replaced in tests.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Dispositivo)
    Initialize-UTNvApiType
    $id = [UpgradeTweaks.NvDrs]::DisplayId($Dispositivo)
    $c = [UpgradeTweaks.NvDrs]::GetColor($id)
    return [pscustomobject]@{ DisplayId = $id; Faixa = [int]$c.dynamicRange; Formato = [int]$c.colorFormat }
}

function Set-UTNvDisplayRange {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][uint32]$DisplayId, [Parameter(Mandatory)][int]$Faixa)
    if ($PSCmdlet.ShouldProcess("monitor 0x$('{0:X}' -f $DisplayId)", "Faixa dinâmica = $Faixa")) {
        [UpgradeTweaks.NvDrs]::SetDynamicRange($DisplayId, [byte]$Faixa)
    }
}

function Get-UTNvidiaColorRange {
    <#
    .SYNOPSIS
        Output dynamic range of each monitor driven by the NVIDIA card: Completa (0-255) or
        Limitada (16-235, washed-out image on PC monitors).
    #>
    [CmdletBinding()]
    param()
    foreach ($m in @(Get-UTDisplayInfo)) {
        try {
            $c = Get-UTNvDisplayColor -Dispositivo $m.Dispositivo
        } catch {
            continue   # monitor on another GPU (integrated graphics)
        }
        [pscustomobject]@{
            Dispositivo = $m.Dispositivo
            Nome        = $m.Nome
            DisplayId   = $c.DisplayId
            Faixa       = $c.Faixa
            Completa    = ($c.Faixa -eq 0)
            Rotulo      = $(if ($c.Faixa -eq 0) { 'Completa (0-255)' } else { 'Limitada (16-235)' })
        }
    }
}

function Set-UTNvidiaFullRange {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $monitors = @(Get-UTNvidiaColorRange)
    if ($monitors.Count -eq 0) { throw 'Nenhum monitor ligado na placa NVIDIA foi encontrado.' }
    foreach ($m in @($monitors | Where-Object { -not $_.Completa })) {
        if (-not $PSCmdlet.ShouldProcess($m.Nome, 'Faixa dinâmica Completa')) { continue }
        [void](Save-UTOriginalItem -Chave "nvidia|cor|$($m.Dispositivo)" -Dados ([ordered]@{ dispositivo = $m.Dispositivo; faixa = $m.Faixa }) -TweakId $TweakId)
        Set-UTNvDisplayRange -DisplayId $m.DisplayId -Faixa 0
        Write-UTLog -Level Info -TweakId $TweakId -Message "Faixa dinâmica Completa em $($m.Nome)."
    }
}

function Restore-UTNvidiaFullRange {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    foreach ($entry in @(Get-UTOriginalStateItem)) {
        $item = $entry.Item
        if ($item.tipo -ne 'generico' -or ([string]$item.chave) -notlike 'nvidia|cor|*' -or @($item.tweaks) -notcontains $TweakId) { continue }
        $d = Pop-UTOriginalItem -Chave $item.chave -TweakId $TweakId
        if ($d -isnot [System.Collections.IDictionary]) { continue }
        $c = Get-UTNvDisplayColor -Dispositivo ([string]$d.dispositivo)
        Set-UTNvDisplayRange -DisplayId $c.DisplayId -Faixa ([int]$d.faixa)
    }
}

function Test-UTNvidiaFullRange {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $monitors = @(Get-UTNvidiaColorRange)
    return ($monitors.Count -gt 0 -and @($monitors | Where-Object { -not $_.Completa }).Count -eq 0)
}
#endregion

#region Power limit and Resizable BAR (nvidia-smi)
function Get-UTNvidiaPowerLimit {
    <#
    .SYNOPSIS
        Current, default, minimum and maximum power limit in watts (nvidia-smi).
    #>
    [CmdletBinding()]
    param()
    $r = Invoke-UTNative -FilePath 'nvidia-smi.exe' -ArgumentList @('--query-gpu=power.limit,power.default_limit,power.min_limit,power.max_limit', '--format=csv,noheader,nounits')
    if ($r.CodigoSaida -ne 0) { throw "nvidia-smi não respondeu: $($r.Saida) $($r.Erro)" }
    $line = @($r.Saida -split "`r?`n" | Where-Object { $_.Trim() })[0]
    $parts = @($line.Split(',') | ForEach-Object { $_.Trim() })
    $num = { param($t) if ($t -match '^[\d.]+$') { [double]::Parse($t, [Globalization.CultureInfo]::InvariantCulture) } else { $null } }
    return [pscustomobject]@{ Atual = (& $num $parts[0]); Padrao = (& $num $parts[1]); Minimo = (& $num $parts[2]); Maximo = (& $num $parts[3]) }
}

function Set-UTNvidiaPowerLimit {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][double]$Watts)
    $limits = Get-UTNvidiaPowerLimit
    if ($null -eq $limits.Maximo) { throw 'Esta placa não permite ajustar o limite de energia (comum em notebooks).' }
    if ($Watts -gt $limits.Maximo -or $Watts -lt $limits.Minimo) { throw "Limite fora do permitido pela placa ($($limits.Minimo) a $($limits.Maximo) W)." }
    if (-not $PSCmdlet.ShouldProcess('placa NVIDIA', "Limite de energia = $Watts W")) { return }
    $r = Invoke-UTNative -FilePath 'nvidia-smi.exe' -ArgumentList @('-pl', $Watts.ToString([Globalization.CultureInfo]::InvariantCulture))
    if ($r.CodigoSaida -ne 0) {
        throw "O driver recusou mudar o limite de energia ($($r.Saida.Trim())). Use o MSI Afterburner (aba Programas)."
    }
}

function Set-UTNvidiaPowerMax {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $limits = Get-UTNvidiaPowerLimit
    if (-not $PSCmdlet.ShouldProcess('GPU NVIDIA', "Limite de energia em $($limits.Maximo) W")) { return }
    [void](Save-UTOriginalItem -Chave 'nvidia|powerlimit' -Dados ([ordered]@{ watts = $limits.Atual; padrao = $limits.Padrao }) -TweakId $TweakId)
    Set-UTNvidiaPowerLimit -Watts $limits.Maximo
}

function Restore-UTNvidiaPowerMax {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TweakId)
    $d = Pop-UTOriginalItem -Chave 'nvidia|powerlimit' -TweakId $TweakId
    $limits = Get-UTNvidiaPowerLimit
    $target = $limits.Padrao
    if ($d -is [System.Collections.IDictionary] -and $d.watts) { $target = [double]$d.watts }
    Set-UTNvidiaPowerLimit -Watts $target
}

function Get-UTResizableBarStatus {
    <#
    .SYNOPSIS
        Resizable BAR from nvidia-smi: with it on, the BAR1 window is about the size of the VRAM;
        off, it is 256 MiB.
    #>
    [CmdletBinding()]
    param()
    $r = Invoke-UTNative -FilePath 'nvidia-smi.exe' -ArgumentList @('-q', '-d', 'MEMORY')
    if ($r.CodigoSaida -ne 0) { return [pscustomobject]@{ Ligado = $null; Bar1MiB = $null; VramMiB = $null } }
    $fb = [regex]::Match($r.Saida, '(?s)FB Memory Usage.*?Total\s*:\s*(\d+)\s*MiB')
    $bar = [regex]::Match($r.Saida, '(?s)BAR1 Memory Usage.*?Total\s*:\s*(\d+)\s*MiB')
    if (-not $bar.Success) { return [pscustomobject]@{ Ligado = $null; Bar1MiB = $null; VramMiB = $null } }
    $barMiB = [int]$bar.Groups[1].Value
    $vram = $(if ($fb.Success) { [int]$fb.Groups[1].Value } else { $null })
    $on = $barMiB -gt 256
    if ($vram) { $on = ($barMiB -ge ($vram * 0.9)) }
    return [pscustomobject]@{ Ligado = $on; Bar1MiB = $barMiB; VramMiB = $vram }
}
#endregion
