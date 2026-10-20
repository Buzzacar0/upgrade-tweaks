<#
.SYNOPSIS
    Runs PSScriptAnalyzer and the Pester 5 suite. Exit code 0 only when both pass.

.DESCRIPTION
    Nothing here changes the system: the tests use mocks, TestDrive and the test key
    HKCU:\Software\UpgradeTweaksTest (removed at the end).
#>
[CmdletBinding()]
param(
    [switch]$SemAnalyzer,
    [string]$CaminhoResultado
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Import-Module Pester -RequiredVersion 5.7.1 -Force
$failed = $false

if (-not $SemAnalyzer) {
    Import-Module PSScriptAnalyzer -Force
    Write-Host 'PSScriptAnalyzer...' -ForegroundColor Cyan
    $settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
    $issues = foreach ($folder in 'functions', 'scripts') {
        Invoke-ScriptAnalyzer -Path (Join-Path $repoRoot $folder) -Recurse -Settings $settings
    }
    if ($issues) {
        $issues | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 220 | Write-Host
        if (@($issues | Where-Object Severity -eq 'Error').Count -gt 0) { $failed = $true }
        if (@($issues | Where-Object Severity -eq 'Warning').Count -gt 0) { $failed = $true }
    } else {
        Write-Host 'Nenhum problema encontrado.' -ForegroundColor Green
    }
}

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
if ($CaminhoResultado) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $CaminhoResultado
}
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { $failed = $true }

Remove-Item -LiteralPath 'HKCU:\Software\UpgradeTweaksTest' -Recurse -Force -ErrorAction SilentlyContinue

if ($failed) { exit 1 }
exit 0
