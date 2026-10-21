function Add-UTTweakDefault {
    <#
    .SYNOPSIS
        Fills the optional fields of a tweak definition with their defaults, so the engine can
        read any field without checking (and runs under Set-StrictMode -Version Latest).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$Tweak)
    if ($Tweak -isnot [System.Collections.IDictionary]) { return }
    $defaults = [ordered]@{
        ganhoEsperado = ''; observacao = ''; grupoServico = ''; confirmacao = ''; grupoExclusivo = ''; controverso = $false; requerReinicio = $false
        abasExtras = @(); registro = @(); servicos = @()
        scriptAplicar = @(); scriptDesfazer = @(); scriptDetectar = @(); scriptSimular = @(); scriptSimularDesfazer = @()
    }
    foreach ($k in $defaults.Keys) { if (-not $Tweak.Contains($k)) { $Tweak[$k] = $defaults[$k] } }
    if (-not $Tweak.Contains('compatibilidade') -or $null -eq $Tweak['compatibilidade']) { $Tweak['compatibilidade'] = [ordered]@{} }
    $compat = $Tweak['compatibilidade']
    if ($compat -is [System.Collections.IDictionary]) {
        $compatDefaults = [ordered]@{ windows = @(); buildMinimo = 0; gpu = @(); cpu = @(); notebook = $true; desktop = $true; launchersBloqueados = @(); x3dDuplo = $true; exigeX3D = $null; exigeJogo = $false }
        foreach ($k in $compatDefaults.Keys) { if (-not $compat.Contains($k)) { $compat[$k] = $compatDefaults[$k] } }
    }
    foreach ($e in @($Tweak['registro'])) {
        if ($e -is [System.Collections.IDictionary]) {
            foreach ($k in 'acao', 'ausenteEquivale') { if (-not $e.Contains($k)) { $e[$k] = $null } }
        }
    }
    foreach ($e in @($Tweak['servicos'])) {
        if ($e -is [System.Collections.IDictionary] -and -not $e.Contains('parar')) { $e['parar'] = $false }
    }
}

function Test-UTTweakDefinition {
    <#
    .SYNOPSIS
        Validates one tweak definition against docs\esquema-tweaks.md.
        Returns the list of problems (empty = valid).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][AllowNull()][object]$Tweak)

    $problems = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Tweak -or $Tweak -isnot [System.Collections.IDictionary]) {
        $problems.Add('não é um objeto JSON')
        return $problems.ToArray()
    }

    $categories = 'Energia', 'Gaming', 'Latencia', 'Rede', 'ServicosApps', 'Privacidade', 'Visual', 'Personalizar', 'GPU', 'Warzone', 'Ferramentas'
    $risks = 'baixo', 'médio', 'alto'
    $regTypes = 'DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary'
    $startTypes = 'Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled'
    $detections = 'registro', 'servicos', 'script', 'combinada'

    foreach ($field in 'id', 'nome', 'descricao', 'ganhoEsperado', 'categoria', 'risco', 'deteccao') {
        if (-not $Tweak.Contains($field) -or [string]::IsNullOrWhiteSpace([string]$Tweak[$field])) { $problems.Add("campo obrigatório '$field' ausente ou vazio") }
    }
    foreach ($field in 'requerReinicio', 'controverso') {
        if (-not $Tweak.Contains($field) -or $Tweak[$field] -isnot [bool]) { $problems.Add("campo '$field' precisa ser true ou false") }
    }
    if (-not $Tweak.Contains('compatibilidade') -or (Get-UTField $Tweak 'compatibilidade') -isnot [System.Collections.IDictionary]) {
        $problems.Add("campo obrigatório 'compatibilidade' ausente")
    }

    $id = [string](Get-UTField $Tweak 'id')
    if ($id -and $id -notmatch '^UT_[A-Za-z0-9_]+$') { $problems.Add("id '$id' fora do padrão UT_Xxx") }
    if ((Get-UTField $Tweak 'categoria') -and $categories -notcontains (Get-UTField $Tweak 'categoria')) { $problems.Add("categoria '$((Get-UTField $Tweak 'categoria'))' inválida") }
    foreach ($extra in @((Get-UTField $Tweak 'abasExtras') | Where-Object { $null -ne $_ })) {
        if ($categories -notcontains $extra) { $problems.Add("abasExtras '$extra' inválida") }
    }
    if ((Get-UTField $Tweak 'risco') -and $risks -notcontains (Get-UTField $Tweak 'risco')) { $problems.Add("risco '$((Get-UTField $Tweak 'risco'))' inválido (use baixo, médio ou alto)") }
    if ((Get-UTField $Tweak 'risco') -eq 'alto' -and [string]::IsNullOrWhiteSpace([string](Get-UTField $Tweak 'confirmacao'))) {
        $problems.Add("risco alto exige o texto de 'confirmacao'")
    }
    if ((Get-UTField $Tweak 'deteccao') -and $detections -notcontains (Get-UTField $Tweak 'deteccao')) { $problems.Add("deteccao '$((Get-UTField $Tweak 'deteccao'))' inválida") }

    $registry = @((Get-UTField $Tweak 'registro') | Where-Object { $null -ne $_ })
    $services = @((Get-UTField $Tweak 'servicos') | Where-Object { $null -ne $_ })
    $apply = @((Get-UTField $Tweak 'scriptAplicar') | Where-Object { $_ })
    $undo = @((Get-UTField $Tweak 'scriptDesfazer') | Where-Object { $_ })
    $detect = @((Get-UTField $Tweak 'scriptDetectar') | Where-Object { $_ })

    if ($registry.Count -eq 0 -and $services.Count -eq 0 -and $apply.Count -eq 0) { $problems.Add('nenhuma ação (registro, servicos ou scriptAplicar)') }
    if ($apply.Count -gt 0 -and $undo.Count -eq 0) { $problems.Add('scriptAplicar sem scriptDesfazer') }
    if ((Get-UTField $Tweak 'deteccao') -eq 'script' -and $detect.Count -eq 0) { $problems.Add("deteccao 'script' exige scriptDetectar") }
    if ((Get-UTField $Tweak 'deteccao') -eq 'combinada' -and $apply.Count -gt 0 -and $detect.Count -eq 0) { $problems.Add("deteccao 'combinada' com script exige scriptDetectar") }
    if ((Get-UTField $Tweak 'deteccao') -eq 'combinada' -and $apply.Count -eq 0 -and ($registry.Count -eq 0 -or $services.Count -eq 0)) { $problems.Add("deteccao 'combinada' sem script precisa de registro e serviços") }
    if ((Get-UTField $Tweak 'deteccao') -eq 'registro' -and $registry.Count -eq 0) { $problems.Add("deteccao 'registro' sem entradas de registro") }
    if ((Get-UTField $Tweak 'deteccao') -eq 'servicos' -and $services.Count -eq 0) { $problems.Add("deteccao 'servicos' sem serviços") }
    if ((Get-UTField $Tweak 'deteccao') -eq 'registro' -and $apply.Count -gt 0 -and $detect.Count -eq 0) {
        # Allowed, but then the script part is not checked; force the author to choose.
        $problems.Add("tweak com script deve usar deteccao 'combinada' ou 'script'")
    }

    $i = 0
    foreach ($r in $registry) {
        $i++
        $where = "registro[$i]"
        if ($r -isnot [System.Collections.IDictionary]) { $problems.Add("$where não é objeto"); continue }
        if ([string]::IsNullOrWhiteSpace([string](Get-UTField $r 'caminho'))) { $problems.Add("$where sem caminho") }
        else {
            try { [void](Resolve-UTRegistryPath -Path (Get-UTField $r 'caminho')) } catch { $problems.Add("$where caminho inválido: $((Get-UTField $r 'caminho'))") }
        }
        if (-not $r.Contains('nome')) { $problems.Add("$where sem nome (use """" para o valor padrão)") }
        $remove = ((Get-UTField $r 'acao') -eq 'remover')
        if ($null -ne (Get-UTField $r 'acao') -and (Get-UTField $r 'acao') -notin 'definir', 'remover') { $problems.Add("$where acao '$((Get-UTField $r 'acao'))' inválida") }
        if ($null -ne (Get-UTField $r 'ausenteEquivale') -and (Get-UTField $r 'ausenteEquivale') -isnot [bool]) { $problems.Add("$where ausenteEquivale precisa ser true ou false") }
        if ((Get-UTField $r 'ausenteEquivale') -and $null -ne (Get-UTField $r 'valorOriginal')) { $problems.Add("$where ausenteEquivale só faz sentido quando valorOriginal é null") }
        if ($regTypes -notcontains (Get-UTField $r 'tipo')) { $problems.Add("$where tipo '$((Get-UTField $r 'tipo'))' inválido") }
        if (-not $remove -and -not $r.Contains('valor')) { $problems.Add("$where sem valor") }
        if (-not $r.Contains('valorOriginal')) { $problems.Add("$where sem valorOriginal (use null se o valor não existe por padrão)") }
        if ($regTypes -contains (Get-UTField $r 'tipo')) {
            if (-not $remove) {
                try { [void](ConvertTo-UTRegistryData -Type (Get-UTField $r 'tipo') -Value (Get-UTField $r 'valor')) } catch { $problems.Add("$where valor incompatível com $((Get-UTField $r 'tipo'))") }
            }
            if ($null -ne (Get-UTField $r 'valorOriginal')) {
                try { [void](ConvertTo-UTRegistryData -Type (Get-UTField $r 'tipo') -Value (Get-UTField $r 'valorOriginal')) } catch { $problems.Add("$where valorOriginal incompatível com $((Get-UTField $r 'tipo'))") }
            }
        }
    }

    $i = 0
    foreach ($s in $services) {
        $i++
        $where = "servicos[$i]"
        if ($s -isnot [System.Collections.IDictionary]) { $problems.Add("$where não é objeto"); continue }
        if ([string]::IsNullOrWhiteSpace([string](Get-UTField $s 'nome'))) { $problems.Add("$where sem nome") }
        if ($startTypes -notcontains (Get-UTField $s 'inicio')) { $problems.Add("$where inicio '$((Get-UTField $s 'inicio'))' inválido") }
        if ($startTypes -notcontains (Get-UTField $s 'inicioOriginal')) { $problems.Add("$where inicioOriginal '$((Get-UTField $s 'inicioOriginal'))' inválido") }
    }

    $simulate = @((Get-UTField $Tweak 'scriptSimular') | Where-Object { $_ })
    $simulateUndo = @((Get-UTField $Tweak 'scriptSimularDesfazer') | Where-Object { $_ })
    foreach ($pair in @(@('scriptAplicar', $apply), @('scriptDesfazer', $undo), @('scriptDetectar', $detect), @('scriptSimular', $simulate), @('scriptSimularDesfazer', $simulateUndo))) {
        if ($pair[1].Count -eq 0) { continue }
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput(($pair[1] -join "`n"), [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) { $problems.Add("$($pair[0]) com erro de sintaxe: $($parseErrors[0].Message)") }
    }

    $compat = (Get-UTField $Tweak 'compatibilidade')
    if ($compat -is [System.Collections.IDictionary]) {
        foreach ($w in @((Get-UTField $compat 'windows') | Where-Object { $null -ne $_ })) { if ($w -notin '10', '11') { $problems.Add("compatibilidade.windows '$w' inválido") } }
        foreach ($g in @((Get-UTField $compat 'gpu') | Where-Object { $null -ne $_ })) { if ($g -notin 'nvidia', 'amd', 'intel') { $problems.Add("compatibilidade.gpu '$g' inválido") } }
        foreach ($c in @((Get-UTField $compat 'cpu') | Where-Object { $null -ne $_ })) { if ($c -notin 'amd', 'intel') { $problems.Add("compatibilidade.cpu '$c' inválido") } }
        foreach ($l in @((Get-UTField $compat 'launchersBloqueados') | Where-Object { $null -ne $_ })) { if ($l -notin 'battlenet', 'steam', 'xbox') { $problems.Add("compatibilidade.launchersBloqueados '$l' inválido") } }
        if ($null -ne (Get-UTField $compat 'exigeX3D') -and (Get-UTField $compat 'exigeX3D') -notin 'unico', 'duplo') { $problems.Add("compatibilidade.exigeX3D '$((Get-UTField $compat 'exigeX3D'))' inválido (use unico ou duplo)") }
        foreach ($b in 'notebook', 'desktop', 'x3dDuplo', 'exigeJogo') {
            if ($compat.Contains($b) -and $compat[$b] -isnot [bool]) { $problems.Add("compatibilidade.$b precisa ser true ou false") }
        }
    }

    return $problems.ToArray()
}

function Test-UTTweakCompatibility {
    <#
    .SYNOPSIS
        Checks a tweak against the PC context (Get-UTSystemContext). Anything unknown about the
        PC never blocks. Returns Compativel (bool) and Motivo (PT-BR).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Tweak,
        [Parameter(Mandatory)][psobject]$Contexto
    )

    $compat = (Get-UTField $Tweak 'compatibilidade')
    $reason = $null
    if ($null -ne $compat) {
        $gpus = @((Get-UTField $Contexto 'GpuFabricantes') | Where-Object { $_ })
        $gpuMatch = @($gpus | Where-Object { @((Get-UTField $compat 'gpu')) -contains $_ })
        $blockedLaunchers = @((Get-UTField $compat 'launchersBloqueados') | Where-Object { $_ })
        $launcherHit = @(@((Get-UTField $Contexto 'Launchers') | Where-Object { $_ }) | Where-Object { $blockedLaunchers -contains $_ })
        $launcherNames = @{ battlenet = 'Battle.net'; steam = 'Steam'; xbox = 'Xbox App/Game Pass' }

        if ((Get-UTField $Contexto 'WindowsGeracao') -and (Get-UTField $compat 'windows') -and @((Get-UTField $compat 'windows')) -notcontains [string](Get-UTField $Contexto 'WindowsGeracao')) {
            $reason = "Disponível só para Windows $(@((Get-UTField $compat 'windows')) -join ' e ')."
        } elseif ((Get-UTField $Contexto 'Build') -and (Get-UTField $compat 'buildMinimo') -and [int](Get-UTField $Contexto 'Build') -lt [int](Get-UTField $compat 'buildMinimo')) {
            $reason = "Exige uma versão mais nova do Windows (build $((Get-UTField $compat 'buildMinimo')) ou superior)."
        } elseif ($gpus.Count -gt 0 -and (Get-UTField $compat 'gpu') -and $gpuMatch.Count -eq 0) {
            $reason = "Não se aplica à sua placa de vídeo ($($gpus -join ', '))."
        } elseif ((Get-UTField $Contexto 'CpuFabricante') -and (Get-UTField $compat 'cpu') -and @((Get-UTField $compat 'cpu')) -notcontains (Get-UTField $Contexto 'CpuFabricante')) {
            $reason = "Não se aplica ao seu processador ($((Get-UTField $Contexto 'CpuFabricante')))."
        } elseif ((Get-UTField $Contexto 'EhNotebook') -eq $true -and $compat.Contains('notebook') -and -not (Get-UTField $compat 'notebook')) {
            $reason = 'Não recomendado para notebooks.'
        } elseif ((Get-UTField $Contexto 'EhNotebook') -eq $false -and $compat.Contains('desktop') -and -not (Get-UTField $compat 'desktop')) {
            $reason = 'Só faz sentido em notebooks.'
        } elseif ($launcherHit.Count -gt 0) {
            $reason = "Bloqueado porque o jogo usa $($launcherNames[$launcherHit[0]]); este ajuste atrapalharia o launcher."
        } elseif ((Get-UTField $Contexto 'X3D') -eq 'duplo' -and $compat.Contains('x3dDuplo') -and -not (Get-UTField $compat 'x3dDuplo')) {
            $reason = 'Não aplicar em Ryzen X3D de dois CCDs: o driver da AMD precisa dessa configuração para usar o CCD com V-Cache no jogo.'
        } elseif ((Get-UTField $compat 'exigeJogo') -and @((Get-UTField $Contexto 'Executaveis') | Where-Object { $_ }).Count -eq 0) {
            $reason = 'Call of Duty não encontrado neste PC (Steam, Battle.net ou Xbox App). Instale o jogo e rode o diagnóstico de novo.'
        } elseif ((Get-UTField $compat 'exigeX3D') -and (Get-UTField $Contexto 'X3D') -ne (Get-UTField $compat 'exigeX3D')) {
            # A requirement (unlike a restriction) blocks when the PC is unknown: it must be confirmed.
            $reason = $(if ((Get-UTField $compat 'exigeX3D') -eq 'duplo') { 'Só se aplica a Ryzen X3D de dois CCDs (7900X3D, 7950X3D, 9900X3D, 9950X3D...).' } else { 'Só se aplica a Ryzen X3D de um CCD.' })
        }
    }
    return [pscustomobject]@{ Compativel = ($null -eq $reason); Motivo = [string]$reason }
}
