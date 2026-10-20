# Dot-source this file in BeforeAll to load every function of the project.
# Tests never touch the real system: registry tests use HKCU:\Software\UpgradeTweaksTest and
# everything that would change Windows (sc.exe, powercfg, CIM) is mocked.

$UTTestRepoRoot = Split-Path -Parent $PSScriptRoot
foreach ($UTTestFile in (Get-ChildItem -Path (Join-Path $UTTestRepoRoot 'functions') -Filter '*.ps1' -File -Recurse)) {
    . $UTTestFile.FullName
}
$UTTestKey = 'HKCU:\Software\UpgradeTweaksTest'
$UTTestHomes = New-Object System.Collections.Generic.List[string]

function Reset-UTTestEnvironment {
    # Fresh state folder, fresh session and an empty test registry key.
    $env:UPGRADETWEAKS_HOME = Join-Path ([IO.Path]::GetTempPath()) ('UTTest_' + [guid]::NewGuid().ToString('N'))
    $UTTestHomes.Add($env:UPGRADETWEAKS_HOME)
    $script:UTSync = [hashtable]::Synchronized(@{ Silencioso = $true; Versao = 'teste' })
    Remove-Item -LiteralPath $UTTestKey -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $UTTestKey -Force | Out-Null
}

function Clear-UTTestEnvironment {
    foreach ($dir in $UTTestHomes) {
        if ($dir -like '*UTTest_*') { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $UTTestHomes.Clear()
    $env:UPGRADETWEAKS_HOME = $null
    Remove-Item -LiteralPath $UTTestKey -Recurse -Force -ErrorAction SilentlyContinue
}
