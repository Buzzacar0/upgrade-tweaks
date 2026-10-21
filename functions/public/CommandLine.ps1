# Command-line mode (no interface): presets, selection files, undo everything and diagnostics.
#
#   .\upgradetweaks.ps1 -Preset Seguro -Silencioso
#   .\upgradetweaks.ps1 -Config .\minha-config.json
#   .\upgradetweaks.ps1 -DesfazerTudo
#   .\upgradetweaks.ps1 -Diagnostico -ExportarRelatorio C:\relatorio.html
#   .\upgradetweaks.ps1 -Simular -Preset Competitivo
#
# Exit codes: 0 ok, 1 something failed, 2 invalid parameters, 3010 ok but restart needed.

function Read-UTConsoleInput {
    # Isolated so tests can answer the prompts.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Prompt)
    return [string](Read-Host -Prompt $Prompt)
}

function Write-UTCliLine {
    # Console output of the command-line mode; nothing in -Silencioso (the log file has it all).
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texto = '', [string]$Cor = 'Gray')
    if (Get-UTSyncValue -Key 'Silencioso') { return }
    Write-UTConsole -Text $Texto -Color $Cor
}

function Get-UTCliExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][psobject]$Resumo, [switch]$Simulacao)
    if ($Resumo.Falhas.Count -gt 0) { return 1 }
    if ($Resumo.RequerReinicio -and -not $Simulacao) { return 3010 }
    return 0
}

function Write-UTCliSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resultados)
    foreach ($r in $Resultados) {
        $color = switch ($r.Status) { 'Aplicado' { 'Green' } 'Desfeito' { 'Green' } 'Falhou' { 'Red' } 'PrecisaConfirmacao' { 'Yellow' } 'Simulado' { 'Cyan' } default { 'Gray' } }
        Write-UTCliLine ("  [{0}] {1}: {2}" -f $r.Status, $r.Nome, $r.Mensagem) $color
        if ($r.Status -eq 'Simulado') { foreach ($a in @($r.Acoes)) { Write-UTCliLine "        $a" 'DarkCyan' } }
    }
    $summary = Get-UTRunSummary -Resultados $Resultados
    Write-UTCliLine ''
    foreach ($line in ($summary.Texto -split "`n")) { Write-UTCliLine $line $(if ($summary.Falhas.Count -gt 0) { 'Yellow' } else { 'Green' }) }
    Write-UTLog -Level Info -Message ("Linha de comando: " + ($summary.Texto -split "`n")[0])
    return $summary
}

function Invoke-UTCommandLine {
    <#
    .SYNOPSIS
        Runs the command-line mode and returns the exit code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string]$Preset = '',
        [string]$Config = '',
        [switch]$DesfazerTudo,
        [switch]$Diagnostico,
        [string]$ExportarRelatorio = '',
        [switch]$Simular
    )
    $silent = [bool](Get-UTSyncValue -Key 'Silencioso')
    if ($Preset -and $Config) { Write-UTLog -Level Erro -Message 'Use -Preset ou -Config, não os dois.'; return 2 }
    if ($DesfazerTudo -and ($Preset -or $Config)) { Write-UTLog -Level Erro -Message '-DesfazerTudo não pode ser usado junto com -Preset ou -Config.'; return 2 }

    $exit = 0

    # Diagnostics (also needed before applying: the compatibility checks use the hardware).
    if ($Diagnostico -or $ExportarRelatorio) {
        Write-UTCliLine 'Analisando o hardware e o Windows...' 'Cyan'
        $diag = Get-UTDiagnostic
        Write-UTCliLine ''
        Write-UTCliLine ("Nota de Otimização: {0}/100" -f $diag.Nota) $(if ($diag.Nota -ge 80) { 'Green' } elseif ($diag.Nota -ge 60) { 'Yellow' } else { 'Red' })
        foreach ($line in @(Get-UTHardwareSummaryLine -Hardware $diag.Hardware)) { Write-UTCliLine ("  {0,-16} {1}" -f $line.Rotulo, $line.Valor) }
        Write-UTCliLine ''
        if (@($diag.Pendencias).Count -eq 0) { Write-UTCliLine 'Nenhuma pendência.' 'Green' }
        foreach ($p in @($diag.Pendencias)) { Write-UTCliLine ("  [{0}] {1}: {2} (aba {3})" -f $p.Status, $p.Titulo, $p.Mensagem, $p.Aba) $(if ($p.Status -eq 'Problema') { 'Red' } else { 'Yellow' }) }
        if ($ExportarRelatorio) {
            $file = Export-UTDiagnosticReport -Path $ExportarRelatorio -Diagnostico $diag
            Write-UTCliLine ''
            Write-UTCliLine "Relatório salvo em $file" 'Green'
        }
        if (-not ($Preset -or $Config -or $DesfazerTudo)) { return 0 }
    } elseif ($Preset -or $Config) {
        Write-UTCliLine 'Lendo o hardware para checar a compatibilidade dos ajustes...' 'Cyan'
        [void](Get-UTHardwareInfo)
    }

    if ($DesfazerTudo) {
        $applied = @(Get-UTAppliedRecord)
        if ($applied.Count -eq 0) { Write-UTCliLine 'Nada para desfazer: o Upgrade Tweaks não aplicou nenhum ajuste neste PC.' 'Green'; return 0 }
        if ($Simular) {
            Write-UTCliLine "Simulação: estes $($applied.Count) ajustes seriam desfeitos (do último para o primeiro):" 'Cyan'
            [array]::Reverse($applied)
            foreach ($a in $applied) { Write-UTCliLine "  $($a.tweakId)" }
            return 0
        }
        if (-not $silent) {
            $answer = Read-UTConsoleInput -Prompt "Desfazer os $($applied.Count) ajustes aplicados pelo Upgrade Tweaks? Digite S para confirmar"
            if ($answer.Trim().ToUpperInvariant() -ne 'S') { Write-UTCliLine 'Cancelado. Nada foi alterado.' 'Yellow'; return 0 }
        }
        $results = @(Undo-UTAllTweak)
        $summary = Write-UTCliSummary -Resultados $results
        return (Get-UTCliExitCode -Resumo $summary)
    }

    if ($Preset -or $Config) {
        $ids = @()
        $risk = $false
        if ($Preset) {
            try { $sel = Get-UTPresetSelection -Nome $Preset -LinhaDeComando } catch { Write-UTLog -Level Erro -Message $_.Exception.Message; return 2 }
            $ids = @($sel.Ids)
            Write-UTCliLine "Preset $($sel.Nome): $($ids.Count) ajustes. $($sel.Descricao)" 'Cyan'
            if ($sel.ExigeConfirmacao) { $risk = Confirm-UTCliHighRisk -Ids $ids -Texto $sel.TextoConfirmacao -Aviso $sel.Aviso -Simulacao:$Simular }
        } else {
            try { $imp = Import-UTSelection -Caminho $Config } catch { Write-UTLog -Level Erro -Message $_.Exception.Message; return 2 }
            $ids = @($imp.Ids)
            Write-UTCliLine "Seleção $Config`: $($ids.Count) ajustes. $($imp.Descricao)" 'Cyan'
            if (@($imp.Desconhecidos).Count -gt 0) { Write-UTCliLine "Ignorados (não existem nesta versão): $($imp.Desconhecidos -join ', ')" 'Yellow' }
            $risk = Confirm-UTCliHighRisk -Ids $ids -Texto 'EU ENTENDO' -Aviso 'A seleção inclui ajustes de risco alto.' -Simulacao:$Simular
        }
        if ($ids.Count -eq 0) { Write-UTCliLine 'Nenhum ajuste para aplicar.' 'Yellow'; return 0 }
        if ($Simular) { Write-UTCliLine 'MODO SIMULAÇÃO: nada será alterado.' 'Cyan' }
        Write-UTCliLine ''
        $results = @(Invoke-UTTweak -Id $ids -RiscoAltoConfirmado:$risk -WhatIf:$Simular)
        $summary = Write-UTCliSummary -Resultados $results
        $exit = Get-UTCliExitCode -Resumo $summary -Simulacao:$Simular
    }
    return $exit
}

function Confirm-UTCliHighRisk {
    <#
    .SYNOPSIS
        High-risk tweaks in the command line need the confirmation text typed. In -Silencioso
        nobody can type it, so they are skipped (reported as waiting for confirmation).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Ids,
        [string]$Texto = 'EU ENTENDO',
        [string]$Aviso,
        [switch]$Simulacao
    )
    $high = @(Get-UTTweak -Id $Ids | Where-Object { $_.risco -eq 'alto' })
    if ($high.Count -eq 0) { return $false }
    if ($Simulacao) { return $true }
    if (Get-UTSyncValue -Key 'Silencioso') {
        Write-UTLog -Level Aviso -Message "$($high.Count) ajustes de risco alto foram pulados: no modo -Silencioso ninguém pode digitar a confirmação. Rode sem -Silencioso para incluí-los."
        return $false
    }
    Write-UTCliLine ''
    if ($Aviso) { Write-UTCliLine $Aviso 'Yellow' }
    foreach ($t in $high) { Write-UTCliLine "  - $($t.nome): $($t.confirmacao)" 'Yellow' }
    $answer = Read-UTConsoleInput -Prompt "Digite $Texto para incluir os $($high.Count) ajustes de risco alto (Enter pula esses)"
    $ok = ($answer.Trim() -ceq $Texto)
    if (-not $ok) { Write-UTCliLine 'Os ajustes de risco alto serão pulados.' 'Yellow' }
    return $ok
}
