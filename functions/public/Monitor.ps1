# Monitor tab settings and logic: monitor.json in %AppData%, ready-made layouts, the per-core
# summary, history and average, alerts and the CSV files. Everything works on plain sensor rows
# (ConvertTo-UTSensorRow), so it is tested without the sensors or the window.

#region Settings (monitor.json)
function Get-UTMonitorDefault {
    <#
    .SYNOPSIS
        Settings of a person who never customized the Monitor.
    #>
    [CmdletBinding()]
    param()
    return [ordered]@{
        Versao         = 1
        Layout         = 'Essencial'
        Visao          = 'Cartoes'
        IntervaloMs    = 1000
        Unidade        = 'C'
        Casas          = 1
        OcultarZerados = $true
        ResumoNucleos  = $true
        Notificar      = $true
        AlertasPadrao  = $true
        Personalizado  = @()
        Favoritos      = @()
        Nomes          = [ordered]@{}
        Alertas        = [ordered]@{}
    }
}

function Get-UTMonitorConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path (Get-UTPath -Name Usuario) 'monitor.json')
}

function ConvertTo-UTMonitorConfig {
    <#
    .SYNOPSIS
        Validated copy of a settings object: unknown keys dropped, values out of range brought back
        to the nearest valid one (interval 250 ms to 2 s, 0 to 2 decimals...).
    #>
    [CmdletBinding()]
    param([AllowNull()][object]$Config)
    $out = Get-UTMonitorDefault
    if ($Config -isnot [System.Collections.IDictionary]) { return $out }
    $get = { param($k) if ($Config.Contains($k)) { $Config[$k] } else { $null } }
    $layout = [string](& $get 'Layout')
    if ($layout -in 'Upgrade', 'Essencial', 'Gamer', 'Completo', 'Personalizado') { $out.Layout = $layout }
    $view = [string](& $get 'Visao')
    if ($view -in 'Cartoes', 'Tabela') { $out.Visao = $view }
    $interval = & $get 'IntervaloMs'
    if ($null -ne $interval -and "$interval" -match '^\d+(\.\d+)?$') { $out.IntervaloMs = [int][math]::Min(2000, [math]::Max(250, [double]$interval)) }
    $unit = [string](& $get 'Unidade')
    if ($unit -in 'C', 'F') { $out.Unidade = $unit.ToUpperInvariant() }
    $dec = & $get 'Casas'
    if ($null -ne $dec -and "$dec" -match '^\d+$') { $out.Casas = [int][math]::Min(2, [int]$dec) }
    foreach ($k in 'OcultarZerados', 'ResumoNucleos', 'Notificar', 'AlertasPadrao') {
        $v = & $get $k
        if ($v -is [bool]) { $out[$k] = $v }
    }
    foreach ($k in 'Personalizado', 'Favoritos') {
        $seen = @{}
        $out[$k] = @(@(& $get $k) | Where-Object { $_ -is [string] -and $_ -and -not $seen.ContainsKey($_) } | ForEach-Object { $seen[$_] = $true; $_ })
    }
    $names = & $get 'Nomes'
    if ($names -is [System.Collections.IDictionary]) {
        foreach ($k in @($names.Keys)) {
            $n = ([string]$names[$k]).Trim()
            if ($n) { $out.Nomes[[string]$k] = $(if ($n.Length -gt 40) { $n.Substring(0, 40) } else { $n }) }
        }
    }
    $alerts = & $get 'Alertas'
    if ($alerts -is [System.Collections.IDictionary]) {
        foreach ($k in @($alerts.Keys)) {
            $a = $alerts[$k]
            if ($a -isnot [System.Collections.IDictionary]) { continue }
            $entry = [ordered]@{ Acima = $null; Abaixo = $null }
            foreach ($side in 'Acima', 'Abaixo') {
                if ($a.Contains($side) -and $null -ne $a[$side] -and "$($a[$side])" -match '^-?\d+([.,]\d+)?$') {
                    $entry[$side] = [double]::Parse(("$($a[$side])" -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
                }
            }
            if ($null -ne $entry.Acima -or $null -ne $entry.Abaixo) { $out.Alertas[[string]$k] = $entry }
        }
    }
    return $out
}

function Get-UTMonitorConfig {
    <#
    .SYNOPSIS
        The Monitor settings (monitor.json in %AppData%\UpgradeTweaks), validated. A damaged file
        is kept as monitor.json.bak and the defaults are used.
    #>
    [CmdletBinding()]
    param()
    $path = Get-UTMonitorConfigPath
    $saved = $null
    try {
        $saved = Read-UTJsonFile -Path $path
    } catch {
        Write-UTLog -Level Aviso -Message 'O arquivo de configuração do Monitor estava danificado; voltou ao padrão.' -Detalhe $_.Exception.Message
        try { Copy-Item -LiteralPath $path -Destination "$path.bak" -Force } catch { $null = $_ }
    }
    return (ConvertTo-UTMonitorConfig -Config $saved)
}

function Save-UTMonitorConfig {
    <#
    .SYNOPSIS
        Saves the Monitor settings (validated first). Returns what was saved.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $clean = ConvertTo-UTMonitorConfig -Config $Config
    if ($PSCmdlet.ShouldProcess((Get-UTMonitorConfigPath), 'Salvar configuração do Monitor')) {
        Write-UTJsonFile -Path (Get-UTMonitorConfigPath) -InputObject $clean -Confirm:$false
    }
    return $clean
}

function Export-UTMonitorLayout {
    <#
    .SYNOPSIS
        Writes the Monitor settings to a JSON file that can be imported on another PC.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [System.Collections.IDictionary]$Config)
    if (-not $Config) { $Config = Get-UTMonitorConfig }
    $doc = [ordered]@{ formato = 'upgradetweaks-monitor'; versao = 1; exportado = (Get-Date).ToString('s'); monitor = (ConvertTo-UTMonitorConfig -Config $Config) }
    if ($PSCmdlet.ShouldProcess($Path, 'Exportar layout do Monitor')) { Write-UTJsonFile -Path $Path -InputObject $doc -Confirm:$false }
    return $Path
}

function Import-UTMonitorLayout {
    <#
    .SYNOPSIS
        Reads a layout exported by Export-UTMonitorLayout, saves it as the current settings and
        returns it. Anything that is not such a file is refused without touching the settings.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)
    $doc = $null
    try { $doc = Read-UTJsonFile -Path $Path } catch { $doc = $null }
    if ($doc -isnot [System.Collections.IDictionary] -or [string]$doc['formato'] -ne 'upgradetweaks-monitor' -or $doc['monitor'] -isnot [System.Collections.IDictionary]) {
        throw 'Este arquivo não é um layout do Monitor exportado pelo Upgrade Tweaks.'
    }
    $config = ConvertTo-UTMonitorConfig -Config $doc['monitor']
    if ($PSCmdlet.ShouldProcess((Get-UTMonitorConfigPath), 'Importar layout do Monitor')) { $config = Save-UTMonitorConfig -Config $config -Confirm:$false }
    return $config
}
#endregion

#region Layouts and the per-core summary
function Group-UTInOrder {
    <#
    .SYNOPSIS
        Groups like Group-Object (Name, Group) keeping the groups in the order they first appear.
        PowerShell 7 sorts the groups of Group-Object by name, Windows PowerShell 5.1 does not.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Itens, [Parameter(Mandatory)][scriptblock]$Chave)
    $groups = [ordered]@{}
    foreach ($i in $Itens) {
        $k = [string](& $Chave $i)
        if (-not $groups.Contains($k)) { $groups[$k] = New-Object System.Collections.Generic.List[object] }
        $groups[$k].Add($i)
    }
    foreach ($k in @($groups.Keys)) { [pscustomobject]@{ Name = $k; Group = $groups[$k].ToArray() } }
}function Test-UTMonitorRule {
    # $true when the row matches a layout/alert rule (hardware type, device, sensor type, name).
    param([Parameter(Mandatory)][psobject]$Linha, [Parameter(Mandatory)][System.Collections.IDictionary]$Regra)
    if ($Regra.Contains('hardware') -and [string]$Linha.HardwareTipo -notmatch [string]$Regra.hardware) { return $false }
    if ($Regra.Contains('dispositivo') -and [string]$Linha.HardwareNome -notmatch [string]$Regra.dispositivo) { return $false }
    if ($Regra.Contains('tipo') -and [string]$Linha.TipoOriginal -ne [string]$Regra.tipo) { return $false }
    if ($Regra.Contains('nome') -and [string]$Linha.NomeOriginal -notmatch [string]$Regra.nome) { return $false }
    return $true
}

function Get-UTMonitorCoreKey {
    <#
    .SYNOPSIS
        For a per-core sensor ("Core #3", "CPU Core #3", "Core #3 (Effective)", "CPU Core #3
        Thread #2"...) the key of its summary group; $null for any other sensor.
    #>
    param([Parameter(Mandatory)][psobject]$Linha)
    if ([string]$Linha.HardwareTipo -ne 'Cpu') { return $null }
    $m = [regex]::Match([string]$Linha.NomeOriginal, '^(CPU )?Core #\d+(?<resto>.*)$')
    if (-not $m.Success) { return $null }
    $rest = ($m.Groups['resto'].Value -replace '^\s*Thread #\d+', '').Trim()
    $device = ([regex]::Match([string]$Linha.Id, '^/[^/]+/\d+')).Value
    if (-not $device) { $device = '/' + ([string]$Linha.Hardware -replace '\W', '') }
    $slug = ($rest -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    return ("{0}/nucleos/{1}{2}" -f $device, ([string]$Linha.TipoOriginal).ToLowerInvariant(), $(if ($slug) { "-$slug" } else { '' }))
}

function Get-UTMonitorCoreName {
    param([string]$Tipo, [string]$Resto, [int]$Quantidade)
    $base = switch -Regex ($Resto) {
        'Effective' { 'Clock efetivo dos núcleos'; break }
        'SMU' { 'Consumo dos núcleos'; break }
        'VID' { 'Tensão dos núcleos (VID)'; break }
        'TjMax' { 'Distância do TjMax'; break }
        default {
            switch ($Tipo) {
                'Clock' { 'Clock dos núcleos' } 'Load' { 'Uso dos núcleos' } 'Temperature' { 'Temperatura dos núcleos' }
                'Power' { 'Consumo dos núcleos' } 'Voltage' { 'Tensão dos núcleos' } 'Factor' { 'Multiplicador dos núcleos' }
                default { "Núcleos ($Tipo)" }
            }
        }
    }
    return "$base ($Quantidade)"
}

function Merge-UTMonitorCoreSummary {
    <#
    .SYNOPSIS
        Replaces the per-core sensors with one summary row per kind: current = average of the
        cores now, minimum/maximum = lowest/highest any core reached, Faixa = lowest and highest
        core now. Other rows pass through unchanged, in the same order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas,
        # Group key of each sensor id, kept between readings (the names never change).
        [hashtable]$Cache
    )
    $groups = [ordered]@{}
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Linhas) {
        $id = [string]$r.Id
        if ($null -ne $Cache -and $Cache.ContainsKey($id)) { $key = $Cache[$id] }
        else { $key = [string](Get-UTMonitorCoreKey -Linha $r); if ($null -ne $Cache) { $Cache[$id] = $key } }
        if (-not $key) { $out.Add($r); continue }
        if (-not $groups.Contains($key)) {
            $groups[$key] = New-Object System.Collections.Generic.List[object]
            # Placeholder keeps the summary where the first core of the group was.
            $out.Add($key)
        }
        $groups[$key].Add($r)
    }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($item in $out) {
        if ($item -isnot [string]) { $result.Add($item); continue }
        $members = $groups[$item]
        $first = $members[0]
        if ($members.Count -eq 1) { $result.Add($first); continue }
        $vals = @($members | Where-Object { $null -ne $_.Valor } | ForEach-Object { [double]$_.Valor })
        $mins = @($members | Where-Object { $null -ne $_.MinValor } | ForEach-Object { [double]$_.MinValor })
        $maxs = @($members | Where-Object { $null -ne $_.MaxValor } | ForEach-Object { [double]$_.MaxValor })
        $rest = ([regex]::Match([string]$first.NomeOriginal, '^(CPU )?Core #\d+(?<resto>.*)$')).Groups['resto'].Value
        $avg = $null; $low = $null; $high = $null
        if ($vals.Count -gt 0) {
            $m = $vals | Measure-Object -Average -Minimum -Maximum
            $avg = [double]$m.Average; $low = [double]$m.Minimum; $high = [double]$m.Maximum
        }
        $result.Add([pscustomobject]@{
                Id = $item; Ordem = $first.Ordem; Grupo = $first.Grupo; Hardware = $first.Hardware; HardwareNome = $first.HardwareNome
                HardwareTipo = $first.HardwareTipo; Tipo = $first.Tipo; TipoOriginal = $first.TipoOriginal
                Sensor = Get-UTMonitorCoreName -Tipo ([string]$first.TipoOriginal) -Resto $rest -Quantidade $members.Count
                NomeOriginal = "Cores$rest"; Valor = $avg
                MinValor = $(if ($mins.Count) { ($mins | Measure-Object -Minimum).Minimum } else { $null })
                MaxValor = $(if ($maxs.Count) { ($maxs | Measure-Object -Maximum).Maximum } else { $null })
                Faixa = @($low, $high); Membros = $members.Count; Resumo = $true
            })
    }
    return $result.ToArray()
}

function Get-UTMonitorLayoutRule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Upgrade', 'Essencial', 'Gamer')][string]$Layout)
    return @((Get-UTConfig -Name 'monitor-layouts').layouts[$Layout])
}

function Test-UTMonitorZero {
    # A sensor that never read anything but zero (unused fan header, idle video engine...).
    param([Parameter(Mandatory)][psobject]$Linha)
    $max = $Linha.MaxValor
    $now = $Linha.Valor
    return (($null -eq $max -or [double]$max -eq 0) -and ($null -eq $now -or [double]$now -eq 0))
}

function Select-UTMonitorRow {
    <#
    .SYNOPSIS
        Sensors to show, in order, for the settings: the layout (rules of Essencial/Gamer, all of
        Completo, the person's list in Personalizado), the per-core summary, sensors that only
        read zero left out, favorites first and the custom names (NomeExibicao).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [hashtable]$Cache
    )
    $rows = @($Linhas)
    if ($Config.ResumoNucleos) { $rows = @(Merge-UTMonitorCoreSummary -Linhas $rows -Cache $Cache) }
    $byId = @{}
    foreach ($r in $rows) { $byId[[string]$r.Id] = $r }
    $picked = New-Object System.Collections.Generic.List[object]
    $taken = @{}
    $add = { param($r) if (-not $taken.ContainsKey([string]$r.Id)) { $taken[[string]$r.Id] = $true; $picked.Add($r) } }
    switch ($Config.Layout) {
        'Personalizado' {
            foreach ($id in @($Config.Personalizado)) { if ($byId.ContainsKey($id)) { & $add $byId[$id] } }
        }
        'Completo' {
            # Grouped by device in the order the devices appear, sensors by kind inside each.
            foreach ($g in @(Group-UTInOrder -Itens $rows -Chave { param($r) $r.Hardware })) { foreach ($r in @($g.Group | Sort-Object Ordem)) { & $add $r } }
        }
        default {
            foreach ($rule in @(Get-UTMonitorLayoutRule -Layout $Config.Layout)) {
                $firstOnly = ($rule.Contains('primeiro') -and $rule.primeiro)
                $seenDevice = @{}
                foreach ($r in $rows) {
                    if (-not (Test-UTMonitorRule -Linha $r -Regra $rule)) { continue }
                    if ($firstOnly) {
                        if ($seenDevice.ContainsKey([string]$r.Hardware)) { continue }
                        $seenDevice[[string]$r.Hardware] = $true
                    }
                    & $add $r
                }
            }
        }
    }
    $favorites = @($Config.Favoritos)
    $list = $picked.ToArray()
    if ($Config.OcultarZerados -and $Config.Layout -ne 'Personalizado') {
        $list = @($list | Where-Object { $favorites -contains [string]$_.Id -or -not (Test-UTMonitorZero -Linha $_) })
    }
    $front = @($favorites | Where-Object { $byId.ContainsKey($_) } | ForEach-Object { $byId[$_] })
    $rest = @($list | Where-Object { $favorites -notcontains [string]$_.Id })
    foreach ($r in @($front) + @($rest)) {
        $id = [string]$r.Id
        [pscustomobject]@{
            Id = $id; Linha = $r; Favorito = ($favorites -contains $id)
            NomeExibicao = $(if ($Config.Nomes.Contains($id)) { [string]$Config.Nomes[$id] } else { [string]$r.Sensor })
        }
    }
}

function Get-UTMonitorVisibleId {
    <#
    .SYNOPSIS
        Ids shown now for the settings: the starting list of Personalizado when the person
        customizes another layout (hide, reorder).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas, [Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    return @(Select-UTMonitorRow -Linhas $Linhas -Config $Config | ForEach-Object { $_.Id })
}

function Set-UTMonitorCustomList {
    <#
    .SYNOPSIS
        Hide (-Ocultar), show (-Mostrar) or move a sensor (-Mover before -Antes, or to the end).
        Doing it in a ready-made layout first turns what is on screen into the Personalizado
        layout, so nothing jumps around. Returns the new settings (not saved).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns new settings; saves nothing.')]
    [CmdletBinding(DefaultParameterSetName = 'Ocultar')]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory, ParameterSetName = 'Ocultar')][string]$Ocultar,
        [Parameter(Mandatory, ParameterSetName = 'Mostrar')][string[]]$Mostrar,
        [Parameter(Mandatory, ParameterSetName = 'Mover')][string]$Mover,
        [Parameter(ParameterSetName = 'Mover')][string]$Antes
    )
    $cfg = ConvertTo-UTMonitorConfig -Config $Config
    $ids = New-Object System.Collections.Generic.List[string]
    if ($cfg.Layout -eq 'Personalizado') { foreach ($i in @($cfg.Personalizado)) { $ids.Add($i) } }
    else { foreach ($i in @(Get-UTMonitorVisibleId -Linhas $Linhas -Config $cfg)) { $ids.Add($i) } }
    switch ($PSCmdlet.ParameterSetName) {
        'Ocultar' { [void]$ids.Remove($Ocultar); $cfg.Favoritos = @($cfg.Favoritos | Where-Object { $_ -ne $Ocultar }) }
        'Mostrar' { foreach ($i in $Mostrar) { if (-not $ids.Contains($i)) { $ids.Add($i) } } }
        'Mover' {
            if ($Mover -eq $Antes) { break }
            [void]$ids.Remove($Mover)
            $at = $(if ($Antes) { $ids.IndexOf($Antes) } else { -1 })
            if ($at -ge 0) { $ids.Insert($at, $Mover) } else { $ids.Add($Mover) }
            # A favorite moved stays a favorite, in the new relative order.
            if ($cfg.Favoritos -contains $Mover) {
                $cfg.Favoritos = @($ids | Where-Object { $cfg.Favoritos -contains $_ })
            }
        }
    }
    $cfg.Personalizado = $ids.ToArray()
    $cfg.Layout = 'Personalizado'
    return $cfg
}
#endregion

#region Formatting, history and average
function ConvertTo-UTMonitorUnit {
    # Value in the unit chosen (temperatures in °F when -Unidade F).
    param([AllowNull()][object]$Valor, [string]$Tipo, [string]$Unidade = 'C')
    if ($null -eq $Valor) { return $null }
    if ($Tipo -eq 'Temperature' -and $Unidade -eq 'F') { return ([double]$Valor * 9 / 5 + 32) }
    return [double]$Valor
}

function Add-UTMonitorSample {
    <#
    .SYNOPSIS
        Adds the current values to the history (last -Tamanho values of each sensor, for the
        sparkline) and to the running average (since the monitor started or was reset).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Historico,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas,
        [int]$Tamanho = 60
    )
    foreach ($r in $Linhas) {
        if ($null -eq $r.Valor) { continue }
        $id = [string]$r.Id
        $h = $Historico[$id]
        if ($null -eq $h) { $h = @{ Valores = New-Object 'System.Collections.Generic.Queue[double]'; Soma = 0.0; N = 0 }; $Historico[$id] = $h }
        $v = [double]$r.Valor
        $h.Valores.Enqueue($v)
        while ($h.Valores.Count -gt $Tamanho) { [void]$h.Valores.Dequeue() }
        $h.Soma += $v
        $h.N++
    }
}

function Get-UTMonitorAverage {
    param([Parameter(Mandatory)][hashtable]$Historico, [Parameter(Mandatory)][string]$Id)
    $h = $Historico[$Id]
    if ($null -eq $h -or $h.N -eq 0) { return $null }
    return ($h.Soma / $h.N)
}
#endregion

#region Alerts
function Get-UTMonitorAlertLimit {
    <#
    .SYNOPSIS
        Limits in force for the sensors: the person's own (Alertas, by sensor) and, when
        AlertasPadrao is on, the built-in ones of monitor-layouts.json. Id -> @{Acima; Abaixo}.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas, [Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $limits = @{}
    if ($Config.AlertasPadrao) {
        foreach ($rule in @((Get-UTConfig -Name 'monitor-layouts').alertasPadrao)) {
            foreach ($r in $Linhas) {
                if (Test-UTMonitorRule -Linha $r -Regra $rule) { $limits[[string]$r.Id] = @{ Acima = [double]$rule.acima; Abaixo = $null; Padrao = $true } }
            }
        }
    }
    foreach ($k in @($Config.Alertas.Keys)) {
        $a = $Config.Alertas[$k]
        $limits[[string]$k] = @{ Acima = $a.Acima; Abaixo = $a.Abaixo; Padrao = $false }
    }
    return $limits
}

function Update-UTMonitorAlert {
    <#
    .SYNOPSIS
        Checks the values against the limits and returns the alerts that just started. An alert
        fires when the value crosses the limit, stays quiet while it is still over it, and arms
        again only after the value comes back past the limit by the margin (3 units), so a value
        hovering at the limit does not repeat it. The same sensor warns at most once a minute.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Updates only the alert state in memory.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas,
        [Parameter(Mandatory)][hashtable]$Limites,
        [Parameter(Mandatory)][hashtable]$Estado,
        [datetime]$Agora = [datetime]::Now,
        [double]$Margem = 3,
        [int]$IntervaloSegundos = 60
    )
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Linhas) {
        $id = [string]$r.Id
        if (-not $Limites.ContainsKey($id) -or $null -eq $r.Valor) { continue }
        $lim = $Limites[$id]
        $v = [double]$r.Valor
        $st = $Estado[$id]
        if ($null -eq $st) { $st = @{ Ativo = $false; Lado = $null; Ultimo = [datetime]::MinValue }; $Estado[$id] = $st }
        $side = $null
        if ($null -ne $lim.Acima -and $v -ge [double]$lim.Acima) { $side = 'acima' }
        elseif ($null -ne $lim.Abaixo -and $v -le [double]$lim.Abaixo) { $side = 'abaixo' }
        if ($st.Ativo) {
            $clear = $false
            if ($st.Lado -eq 'acima') { $clear = ($null -eq $lim.Acima -or $v -lt ([double]$lim.Acima - $Margem)) }
            else { $clear = ($null -eq $lim.Abaixo -or $v -gt ([double]$lim.Abaixo + $Margem)) }
            if ($clear) { $st.Ativo = $false; $st.Lado = $null }
            continue
        }
        if ($null -eq $side) { continue }
        $st.Ativo = $true
        $st.Lado = $side
        if (($Agora - $st.Ultimo).TotalSeconds -lt $IntervaloSegundos) { continue }
        $st.Ultimo = $Agora
        $events.Add([pscustomobject]@{ Id = $id; Linha = $r; Lado = $side; Valor = $v; Limite = $(if ($side -eq 'acima') { [double]$lim.Acima } else { [double]$lim.Abaixo }) })
    }
    return $events.ToArray()
}

function Format-UTMonitorAlertText {
    # "Ponto mais quente da CPU chegou a 91 °C (limite 90 °C)."
    param([Parameter(Mandatory)][psobject]$Alerta, [string]$Nome, [string]$Unidade = 'C', [int]$Casas = 0)
    $t = [string]$Alerta.Linha.TipoOriginal
    $v = Format-UTSensorValue -Valor $Alerta.Valor -Tipo $t -Unidade $Unidade -Casas $Casas
    $l = Format-UTSensorValue -Valor $Alerta.Limite -Tipo $t -Unidade $Unidade -Casas $Casas
    if (-not $Nome) { $Nome = [string]$Alerta.Linha.Sensor }
    $verb = $(if ($Alerta.Lado -eq 'acima') { 'chegou a' } else { 'caiu para' })
    return "$Nome ($($Alerta.Linha.Hardware)) $verb $v (limite $l)."
}
#endregion

#region CSV
function ConvertTo-UTCsvNumber {
    # Number for a CSV opened in Excel in Portuguese: comma decimals, no thousands separator.
    param([AllowNull()][object]$Valor, [int]$Casas = 2)
    if ($null -eq $Valor) { return '' }
    return ([double]$Valor).ToString("F$Casas", [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
}

function ConvertTo-UTCsvField {
    param([AllowNull()][object]$Texto)
    $s = [string]$Texto
    if ($s -match '[;"\r\n]') { return '"' + $s.Replace('"', '""') + '"' }
    return $s
}

function Get-UTMonitorUnitName {
    param([string]$Tipo, [string]$Unidade = 'C')
    switch ($Tipo) {
        'Temperature' { if ($Unidade -eq 'F') { '°F' } else { '°C' } }
        'Voltage' { 'V' } 'Current' { 'A' } 'Power' { 'W' } 'Clock' { 'MHz' } 'Load' { '%' } 'Control' { '%' } 'Level' { '%' }
        'Fan' { 'RPM' } 'Flow' { 'L/h' } 'Data' { 'GB' } 'SmallData' { 'MB' } 'Throughput' { 'B/s' } 'Timing' { 'ns' } 'Frequency' { 'Hz' }
        default { '' }
    }
}

function Export-UTMonitorCsv {
    <#
    .SYNOPSIS
        CSV (separated by ";", for Excel in Portuguese) with every sensor: current, minimum,
        maximum and average, in the unit chosen.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Linhas,
        [hashtable]$Historico = @{},
        [System.Collections.IDictionary]$Config
    )
    if (-not $Config) { $Config = Get-UTMonitorDefault }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Dispositivo;Grupo;Tipo;Sensor;Atual;Mínimo;Máximo;Média;Unidade')
    foreach ($r in $Linhas) {
        $t = [string]$r.TipoOriginal
        $name = $(if ($Config.Nomes.Contains([string]$r.Id)) { $Config.Nomes[[string]$r.Id] } else { $r.Sensor })
        $conv = { param($x) ConvertTo-UTCsvNumber (ConvertTo-UTMonitorUnit -Valor $x -Tipo $t -Unidade $Config.Unidade) -Casas 3 }
        $lines.Add((@(
                    (ConvertTo-UTCsvField $r.Hardware), (ConvertTo-UTCsvField $r.Grupo), (ConvertTo-UTCsvField $r.Tipo), (ConvertTo-UTCsvField $name),
                    (& $conv $r.Valor), (& $conv $r.MinValor), (& $conv $r.MaxValor), (& $conv (Get-UTMonitorAverage -Historico $Historico -Id ([string]$r.Id))),
                    (Get-UTMonitorUnitName -Tipo $t -Unidade $Config.Unidade)
                ) -join ';'))
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Salvar relatório CSV')) {
        # BOM: Excel only reads the accents right with it.
        [IO.File]::WriteAllLines($Path, $lines.ToArray(), (New-Object Text.UTF8Encoding($true)))
    }
    return $Path
}

function New-UTMonitorLog {
    <#
    .SYNOPSIS
        Starts a CSV log with one line per reading (time + the sensors chosen), for long
        sessions. Returns the log object for Write-UTMonitorLogLine / Close-UTMonitorLog.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Colunas,
        [string]$Unidade = 'C'
    )
    if (-not $PSCmdlet.ShouldProcess($Path, 'Gravar log CSV dos sensores')) { return $null }
    $writer = New-Object System.IO.StreamWriter($Path, $false, (New-Object Text.UTF8Encoding($true)))
    $head = @('Hora') + @($Colunas | ForEach-Object { ConvertTo-UTCsvField ("{0} ({1})" -f $_.Nome, (Get-UTMonitorUnitName -Tipo ([string]$_.Tipo) -Unidade $Unidade)) })
    $writer.WriteLine(($head -join ';'))
    return @{ Escritor = $writer; Caminho = $Path; Colunas = @($Colunas); Unidade = $Unidade; Linhas = 0 }
}

function Write-UTMonitorLogLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Log, [Parameter(Mandatory)][hashtable]$Valores, [datetime]$Hora = [datetime]::Now)
    $cells = New-Object System.Collections.Generic.List[string]
    $cells.Add($Hora.ToString('dd/MM/yyyy HH:mm:ss.fff'))
    foreach ($c in $Log.Colunas) {
        $v = $Valores[[string]$c.Id]
        $cells.Add((ConvertTo-UTCsvNumber (ConvertTo-UTMonitorUnit -Valor $v -Tipo ([string]$c.Tipo) -Unidade $Log.Unidade) -Casas 2))
    }
    $Log.Escritor.WriteLine(($cells -join ';'))
    $Log.Linhas++
    if ($Log.Linhas % 20 -eq 0) { $Log.Escritor.Flush() }
}

function Close-UTMonitorLog {
    [CmdletBinding()]
    param([AllowNull()][hashtable]$Log)
    if ($null -eq $Log -or $null -eq $Log.Escritor) { return }
    try { $Log.Escritor.Flush(); $Log.Escritor.Dispose() } catch { $null = $_ }
    $Log.Escritor = $null
}
#endregion
