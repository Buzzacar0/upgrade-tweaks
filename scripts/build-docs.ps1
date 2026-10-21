<#
.SYNOPSIS
    Generates the tweak table of the README (between the TABELA-AJUSTES markers) from the
    catalog, so the README never disagrees with config\tweaks-*.json.

.PARAMETER Verificar
    Only checks: exit code 1 when the README is out of date (used by the tests and the CI).
#>
[CmdletBinding()]
param([switch]$Verificar)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Shared state the functions expect (normally created by start.ps1).
Set-Variable -Name UTSync -Scope Script -Value ([hashtable]::Synchronized(@{ Silencioso = $true; Versao = 'docs' }))
foreach ($file in Get-ChildItem -Path (Join-Path $repoRoot 'functions') -Filter '*.ps1' -File -Recurse) { . $file.FullName }

function Get-UTDocTweakTable {
    $presetOf = @{}
    foreach ($name in @(Get-UTPresetName)) {
        foreach ($id in @(Get-UTPresetTweakId -Nome $name)) { if (-not $presetOf.ContainsKey($id)) { $presetOf[$id] = $name } }
    }
    $sb = New-Object System.Text.StringBuilder
    $total = 0
    foreach ($tab in @(Get-UTUiTabDefinition)) {
        $tweaks = @(Get-UTUiTabTweak -Aba $tab.Id | Where-Object { $_.categoria -in $tab.Categorias })
        if ($tweaks.Count -eq 0) { continue }
        $total += $tweaks.Count
        [void]$sb.AppendLine("<details><summary><b>$($tab.Nome)</b> ($($tweaks.Count) ajustes)</summary>")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Ajuste | Risco | Ganho esperado | Reinício | Preset |')
        [void]$sb.AppendLine('|---|---|---|---|---|')
        foreach ($t in @($tweaks | Sort-Object { @{ 'baixo' = 0; 'médio' = 1; 'alto' = 2 }[[string]$_.risco] }, { [string]$_.nome })) {
            $name = ([string]$t.nome) -replace '\|', '\|'
            if ($t.controverso) { $name += ' *(controverso)*' }
            $gain = ([string]$t.ganhoEsperado) -replace '\|', '\|'
            $preset = $(if ($presetOf.ContainsKey([string]$t.id)) { $presetOf[[string]$t.id] } else { '—' })
            [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} |' -f $name, $t.risco, $gain, $(if ($t.requerReinicio) { 'sim' } else { 'não' }), $preset))
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('</details>')
        [void]$sb.AppendLine('')
    }
    return ("Total: **$total ajustes**, todos com desfazer e detecção do estado atual. A coluna Preset mostra o primeiro preset que inclui o ajuste (Seguro está dentro do Competitivo, que está dentro do Extremo).`n`n" + $sb.ToString().TrimEnd())
}

$readmePath = Join-Path $repoRoot 'README.md'
$readme = [IO.File]::ReadAllText($readmePath, [Text.Encoding]::UTF8)
$start = '<!-- TABELA-AJUSTES:INICIO -->'
$end = '<!-- TABELA-AJUSTES:FIM -->'
$i = $readme.IndexOf($start)
$j = $readme.IndexOf($end)
if ($i -lt 0 -or $j -lt $i) { throw "README.md sem os marcadores $start / $end." }
$table = (Get-UTDocTweakTable) -replace "`r`n", "`n"
$new = $readme.Substring(0, $i + $start.Length) + "`n" + $table + "`n" + $readme.Substring($j)
if ($Verificar) {
    if ($new -ne $readme) { Write-Host 'README.md desatualizado: rode scripts\build-docs.ps1.' -ForegroundColor Red; exit 1 }
    Write-Host 'README.md em dia.' -ForegroundColor Green
    exit 0
}
if ($new -ne $readme) {
    [IO.File]::WriteAllText($readmePath, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Tabela de ajustes do README atualizada.' -ForegroundColor Green
} else {
    Write-Host 'Tabela de ajustes do README já estava em dia.' -ForegroundColor Gray
}
