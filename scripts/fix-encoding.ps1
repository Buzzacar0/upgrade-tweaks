<#
.SYNOPSIS
    Development helper: saves every .ps1/.psd1 of the repository as UTF-8 with BOM.

.DESCRIPTION
    Windows PowerShell 5.1 reads a .ps1 without BOM as the ANSI code page, which breaks the
    PT-BR accents. Run this after creating files with an editor that saves without BOM.
    tests\Encoding.Tests.ps1 fails when a file is left without BOM.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$repoRoot = Split-Path -Parent $PSScriptRoot
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

$files = Get-ChildItem -Path $repoRoot -Include '*.ps1', '*.psd1' -File -Recurse |
    Where-Object { $_.FullName -notmatch '\\(dist|\.git)\\' }

foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) { continue }
    try {
        $text = $utf8Strict.GetString($bytes)
    } catch {
        Write-Warning "$($file.FullName) não é UTF-8 válido; corrija manualmente."
        continue
    }
    if ($PSCmdlet.ShouldProcess($file.FullName, 'Salvar como UTF-8 com BOM')) {
        [IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        Write-Host "BOM adicionado: $($file.FullName.Substring($repoRoot.Length + 1))"
    }
}
