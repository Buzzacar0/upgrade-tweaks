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
    if (-not $Tweak.Contains('compatibilidade') -or $Tweak.compatibilidade -isnot [System.Collections.IDictionary]) {
        $problems.Add("campo obrigatório 'compatibilidade' ausente")
    }

    $id = [string]$Tweak.id
    if ($id -and $id -notmatch '^UT_[A-Za-z0-9_]+$') { $problems.Add("id '$id' fora do padrão UT_Xxx") }
    if ($Tweak.categoria -and $categories -notcontains $Tweak.categoria) { $problems.Add("categoria '$($Tweak.categoria)' inválida") }
    foreach ($extra in @($Tweak.abasExtras | Where-Object { $null -ne $_ })) {
        if ($categories -notcontains $extra) { $problems.Add("abasExtras '$extra' inválida") }
    }
    if ($Tweak.risco -and $risks -notcontains $Tweak.risco) { $problems.Add("risco '$($Tweak.risco)' inválido (use baixo, médio ou alto)") }
    if ($Tweak.risco -eq 'alto' -and [string]::IsNullOrWhiteSpace([string]$Tweak.confirmacao)) {
        $problems.Add("risco alto exige o texto de 'confirmacao'")
    }
    if ($Tweak.deteccao -and $detections -notcontains $Tweak.deteccao) { $problems.Add("deteccao '$($Tweak.deteccao)' inválida") }

    $registry = @($Tweak.registro | Where-Object { $null -ne $_ })
    $services = @($Tweak.servicos | Where-Object { $null -ne $_ })
    $apply = @($Tweak.scriptAplicar | Where-Object { $_ })
    $undo = @($Tweak.scriptDesfazer | Where-Object { $_ })
    $detect = @($Tweak.scriptDetectar | Where-Object { $_ })

    if ($registry.Count -eq 0 -and $services.Count -eq 0 -and $apply.Count -eq 0) { $problems.Add('nenhuma ação (registro, servicos ou scriptAplicar)') }
    if ($apply.Count -gt 0 -and $undo.Count -eq 0) { $problems.Add('scriptAplicar sem scriptDesfazer') }
    if ($Tweak.deteccao -eq 'script' -and $detect.Count -eq 0) { $problems.Add("deteccao 'script' exige scriptDetectar") }
    if ($Tweak.deteccao -eq 'combinada' -and $apply.Count -gt 0 -and $detect.Count -eq 0) { $problems.Add("deteccao 'combinada' com script exige scriptDetectar") }
    if ($Tweak.deteccao -eq 'combinada' -and $apply.Count -eq 0 -and ($registry.Count -eq 0 -or $services.Count -eq 0)) { $problems.Add("deteccao 'combinada' sem script precisa de registro e serviços") }
    if ($Tweak.deteccao -eq 'registro' -and $registry.Count -eq 0) { $problems.Add("deteccao 'registro' sem entradas de registro") }
    if ($Tweak.deteccao -eq 'servicos' -and $services.Count -eq 0) { $problems.Add("deteccao 'servicos' sem serviços") }
    if ($Tweak.deteccao -eq 'registro' -and $apply.Count -gt 0 -and $detect.Count -eq 0) {
        # Allowed, but then the script part is not checked; force the author to choose.
        $problems.Add("tweak com script deve usar deteccao 'combinada' ou 'script'")
    }

    $i = 0
    foreach ($r in $registry) {
        $i++
        $where = "registro[$i]"
        if ($r -isnot [System.Collections.IDictionary]) { $problems.Add("$where não é objeto"); continue }
        if ([string]::IsNullOrWhiteSpace([string]$r.caminho)) { $problems.Add("$where sem caminho") }
        else {
            try { [void](Resolve-UTRegistryPath -Path $r.caminho) } catch { $problems.Add("$where caminho inválido: $($r.caminho)") }
        }
        if (-not $r.Contains('nome')) { $problems.Add("$where sem nome (use """" para o valor padrão)") }
        $remove = ($r.acao -eq 'remover')
        if ($r.Contains('acao') -and $r.acao -notin 'definir', 'remover') { $problems.Add("$where acao '$($r.acao)' inválida") }
        if ($r.Contains('ausenteEquivale') -and $r.ausenteEquivale -isnot [bool]) { $problems.Add("$where ausenteEquivale precisa ser true ou false") }
        if ($r.ausenteEquivale -and $null -ne $r.valorOriginal) { $problems.Add("$where ausenteEquivale só faz sentido quando valorOriginal é null") }
        if ($regTypes -notcontains $r.tipo) { $problems.Add("$where tipo '$($r.tipo)' inválido") }
        if (-not $remove -and -not $r.Contains('valor')) { $problems.Add("$where sem valor") }
        if (-not $r.Contains('valorOriginal')) { $problems.Add("$where sem valorOriginal (use null se o valor não existe por padrão)") }
        if ($regTypes -contains $r.tipo) {
            if (-not $remove) {
                try { [void](ConvertTo-UTRegistryData -Type $r.tipo -Value $r.valor) } catch { $problems.Add("$where valor incompatível com $($r.tipo)") }
            }
            if ($null -ne $r.valorOriginal) {
                try { [void](ConvertTo-UTRegistryData -Type $r.tipo -Value $r.valorOriginal) } catch { $problems.Add("$where valorOriginal incompatível com $($r.tipo)") }
            }
        }
    }

    $i = 0
    foreach ($s in $services) {
        $i++
        $where = "servicos[$i]"
        if ($s -isnot [System.Collections.IDictionary]) { $problems.Add("$where não é objeto"); continue }
        if ([string]::IsNullOrWhiteSpace([string]$s.nome)) { $problems.Add("$where sem nome") }
        if ($startTypes -notcontains $s.inicio) { $problems.Add("$where inicio '$($s.inicio)' inválido") }
        if ($startTypes -notcontains $s.inicioOriginal) { $problems.Add("$where inicioOriginal '$($s.inicioOriginal)' inválido") }
    }

    $simulate = @($Tweak.scriptSimular | Where-Object { $_ })
    $simulateUndo = @($Tweak.scriptSimularDesfazer | Where-Object { $_ })
    foreach ($pair in @(@('scriptAplicar', $apply), @('scriptDesfazer', $undo), @('scriptDetectar', $detect), @('scriptSimular', $simulate), @('scriptSimularDesfazer', $simulateUndo))) {
        if ($pair[1].Count -eq 0) { continue }
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput(($pair[1] -join "`n"), [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) { $problems.Add("$($pair[0]) com erro de sintaxe: $($parseErrors[0].Message)") }
    }

    $compat = $Tweak.compatibilidade
    if ($compat -is [System.Collections.IDictionary]) {
        foreach ($w in @($compat.windows | Where-Object { $null -ne $_ })) { if ($w -notin '10', '11') { $problems.Add("compatibilidade.windows '$w' inválido") } }
        foreach ($g in @($compat.gpu | Where-Object { $null -ne $_ })) { if ($g -notin 'nvidia', 'amd', 'intel') { $problems.Add("compatibilidade.gpu '$g' inválido") } }
        foreach ($c in @($compat.cpu | Where-Object { $null -ne $_ })) { if ($c -notin 'amd', 'intel') { $problems.Add("compatibilidade.cpu '$c' inválido") } }
        foreach ($l in @($compat.launchersBloqueados | Where-Object { $null -ne $_ })) { if ($l -notin 'battlenet', 'steam', 'xbox') { $problems.Add("compatibilidade.launchersBloqueados '$l' inválido") } }
        if ($compat.Contains('exigeX3D') -and $compat.exigeX3D -notin 'unico', 'duplo') { $problems.Add("compatibilidade.exigeX3D '$($compat.exigeX3D)' inválido (use unico ou duplo)") }
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

    $compat = $Tweak.compatibilidade
    $reason = $null
    if ($null -ne $compat) {
        $gpus = @($Contexto.GpuFabricantes | Where-Object { $_ })
        $gpuMatch = @($gpus | Where-Object { @($compat.gpu) -contains $_ })
        $blockedLaunchers = @($compat.launchersBloqueados | Where-Object { $_ })
        $launcherHit = @(@($Contexto.Launchers | Where-Object { $_ }) | Where-Object { $blockedLaunchers -contains $_ })
        $launcherNames = @{ battlenet = 'Battle.net'; steam = 'Steam'; xbox = 'Xbox App/Game Pass' }

        if ($Contexto.WindowsGeracao -and $compat.windows -and @($compat.windows) -notcontains [string]$Contexto.WindowsGeracao) {
            $reason = "Disponível só para Windows $(@($compat.windows) -join ' e ')."
        } elseif ($Contexto.Build -and $compat.buildMinimo -and [int]$Contexto.Build -lt [int]$compat.buildMinimo) {
            $reason = "Exige uma versão mais nova do Windows (build $($compat.buildMinimo) ou superior)."
        } elseif ($gpus.Count -gt 0 -and $compat.gpu -and $gpuMatch.Count -eq 0) {
            $reason = "Não se aplica à sua placa de vídeo ($($gpus -join ', '))."
        } elseif ($Contexto.CpuFabricante -and $compat.cpu -and @($compat.cpu) -notcontains $Contexto.CpuFabricante) {
            $reason = "Não se aplica ao seu processador ($($Contexto.CpuFabricante))."
        } elseif ($Contexto.EhNotebook -eq $true -and $compat.Contains('notebook') -and -not $compat.notebook) {
            $reason = 'Não recomendado para notebooks.'
        } elseif ($Contexto.EhNotebook -eq $false -and $compat.Contains('desktop') -and -not $compat.desktop) {
            $reason = 'Só faz sentido em notebooks.'
        } elseif ($launcherHit.Count -gt 0) {
            $reason = "Bloqueado porque o jogo usa $($launcherNames[$launcherHit[0]]); este ajuste atrapalharia o launcher."
        } elseif ($Contexto.X3D -eq 'duplo' -and $compat.Contains('x3dDuplo') -and -not $compat.x3dDuplo) {
            $reason = 'Não aplicar em Ryzen X3D de dois CCDs: o driver da AMD precisa dessa configuração para usar o CCD com V-Cache no jogo.'
        } elseif ($compat.exigeJogo -and @($Contexto.Executaveis | Where-Object { $_ }).Count -eq 0) {
            $reason = 'Call of Duty não encontrado neste PC (Steam, Battle.net ou Xbox App). Instale o jogo e rode o diagnóstico de novo.'
        } elseif ($compat.exigeX3D -and $Contexto.X3D -ne $compat.exigeX3D) {
            # A requirement (unlike a restriction) blocks when the PC is unknown: it must be confirmed.
            $reason = $(if ($compat.exigeX3D -eq 'duplo') { 'Só se aplica a Ryzen X3D de dois CCDs (7900X3D, 7950X3D, 9900X3D, 9950X3D...).' } else { 'Só se aplica a Ryzen X3D de um CCD.' })
        }
    }
    return [pscustomobject]@{ Compativel = ($null -eq $reason); Motivo = [string]$reason }
}
