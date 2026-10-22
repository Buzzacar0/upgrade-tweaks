<#
.SYNOPSIS
    Compiles Upgrade Tweaks into a single dist\upgradetweaks.ps1.

.DESCRIPTION
    Order of the output file:
      1. Help comment + param block of scripts\start.ps1 (must come first in a script)
      2. Every functions\**\*.ps1 and scripts\main.ps1
      3. config\*.json and xaml\*.xaml embedded as here-strings
      4. The rest of scripts\start.ps1, without the DEV-LOADER region

    The output is pure ASCII. GitHub serves release assets as application/octet-stream with no
    charset, and "irm | iex" on Windows PowerShell 5.1 would then decode UTF-8 accents wrongly.
    So every non-ASCII character is rewritten:
      - JSON: \uXXXX escapes          - XAML: &#xXXXX; entities
      - double-quoted strings: $([char]0xXXXX)
      - single-quoted strings: turned into equivalent double-quoted strings
      - comments: accents removed (c cedilla -> c, a tilde -> a, ...)
    Anything else with non-ASCII (identifiers, attribute arguments) stops the build with an error.

.PARAMETER Version
    Version written into the file. Defaults to the content of the VERSION file.

.PARAMETER OutputPath
    Defaults to dist\upgradetweaks.ps1.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputPath,
    # Skip regenerating the tweak table of the README (CI: it only checks it).
    [switch]$SemDocumentacao
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Version) { $Version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim() }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'dist\upgradetweaks.ps1' }

. (Join-Path $PSScriptRoot 'lib\CompileHelpers.ps1')

# ---------------------------------------------------------------------------------------------
Write-Host "Compilando Upgrade Tweaks v$Version..." -ForegroundColor Cyan
if (-not $SemDocumentacao) { & (Join-Path $PSScriptRoot 'build-docs.ps1') }

$startPath = Join-Path $repoRoot 'scripts\start.ps1'
$startText = Read-UTSourceFile $startPath
$startAst = [System.Management.Automation.Language.Parser]::ParseInput($startText, [ref]$null, [ref]$null)
if ($null -eq $startAst.ParamBlock) { throw 'scripts\start.ps1 precisa ter um bloco param().' }
$splitAt = $startAst.ParamBlock.Extent.EndOffset
$head = $startText.Substring(0, $splitAt)
$body = $startText.Substring($splitAt)
$body = [regex]::Replace($body, '(?s)#region DEV-LOADER.*?#endregion DEV-LOADER\r?\n', '')
if ($body -match 'DEV-LOADER') { throw 'Não foi possível remover a região DEV-LOADER do start.ps1.' }
$body = $body.Replace("'#{versao}'", "'$Version'").Replace("'#{build}'", "'release'")

$parts = New-Object System.Collections.Generic.List[string]
$parts.Add($head)
$parts.Add("`r`n`r`n# Compilado em $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. Nao edite este arquivo: edite o repositorio e rode scripts\compile.ps1.`r`n")

$functionFiles = @(Get-ChildItem -Path (Join-Path $repoRoot 'functions') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
$functionFiles += Get-Item -LiteralPath (Join-Path $repoRoot 'scripts\main.ps1')
foreach ($file in $functionFiles) {
    $relative = $file.FullName.Substring($repoRoot.Length + 1)
    $parts.Add("`r`n#region $relative`r`n" + (Read-UTSourceFile $file.FullName).TrimEnd() + "`r`n#endregion`r`n")
}

$parts.Add("`r`n#region Configuracao embutida`r`n`$UTEmbeddedConfig = @{}`r`n`$UTEmbeddedXaml = @{}`r`n")
foreach ($file in @(Get-ChildItem -Path (Join-Path $repoRoot 'config') -Filter '*.json' -File | Sort-Object Name)) {
    $json = Read-UTSourceFile $file.FullName
    [void]($json | ConvertFrom-Json)   # fail the build on invalid JSON
    $json = ConvertTo-UTAsciiJson $json.Trim()
    if ($json -match "(?m)^'@") { throw "$($file.Name): uma linha começa com '@ e quebraria o here-string." }
    $parts.Add("`$UTEmbeddedConfig['$($file.BaseName)'] = @'`r`n$json`r`n'@`r`n")
}
# Subfolders keep their path in the name: xaml\Theme\Claro.xaml is embedded as 'Theme\Claro'.
$xamlRoot = Join-Path $repoRoot 'xaml'
foreach ($file in @(Get-ChildItem -Path $xamlRoot -Filter '*.xaml' -File -Recurse | Sort-Object FullName)) {
    $xamlName = $file.FullName.Substring($xamlRoot.Length + 1) -replace '\.xaml$', ''
    $xaml = ConvertTo-UTAsciiXml (Read-UTSourceFile $file.FullName).Trim()
    if ($xaml -match "(?m)^'@") { throw "$($file.Name): uma linha começa com '@ e quebraria o here-string." }
    $parts.Add("`$UTEmbeddedXaml['$xamlName'] = @'`r`n$xaml`r`n'@`r`n")
}
$parts.Add("#endregion`r`n")
$parts.Add($body)

$combined = ($parts -join '') -replace "(?<!\r)\n", "`r`n"
$ascii = ConvertTo-UTAsciiScript -Script $combined -SourceName 'upgradetweaks.ps1'

if (Test-UTHasNonAscii $ascii) { throw 'A saída ainda contém caracteres não ASCII.' }
$checkErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($ascii, [ref]$null, [ref]$checkErrors)
if ($checkErrors -and $checkErrors.Count -gt 0) {
    throw "O arquivo compilado tem erro de sintaxe: $($checkErrors[0].Message) (linha $($checkErrors[0].Extent.StartLineNumber))"
}

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
[IO.File]::WriteAllText($OutputPath, $ascii, (New-Object System.Text.ASCIIEncoding))

$size = [math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1KB, 1)
Write-Host "OK: $OutputPath ($size KB)" -ForegroundColor Green
