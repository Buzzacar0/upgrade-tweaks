BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $files = Get-ChildItem -Path $repoRoot -Include '*.ps1', '*.psd1' -File -Recurse |
        Where-Object { $_.FullName -notmatch '\\(dist|\.git)\\' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($repoRoot.Length + 1) } }
}

Describe 'Arquivo <Name>' -ForEach $files {
    It 'está em UTF-8 com BOM quando tem acentos (exigência do PowerShell 5.1)' {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasNonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
        if ($hasNonAscii) { $hasBom | Should -BeTrue -Because 'rode scripts\fix-encoding.ps1' }
    }

    It 'não tem erros de sintaxe neste PowerShell' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'não usa recursos exclusivos do PowerShell 7 nem cmdlets removidos no 7' {
        $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        # The test file itself lists the patterns.
        if ($Name -like 'tests\Encoding.Tests.ps1') { return }
        $forbidden = @(
            @{ Pattern = 'ForEach-Object\s+-Parallel'; Why = 'só existe no PS 7' }
            @{ Pattern = 'ConvertFrom-Json[^\r\n|]*-AsHashtable'; Why = 'só existe no PS 6+' }
            @{ Pattern = '\?\?'; Why = 'operador ?? só existe no PS 7' }
            @{ Pattern = '\?\.\w'; Why = 'operador ?. só existe no PS 7' }
            @{ Pattern = '(?i)\bGet-WmiObject\b'; Why = 'removido no PS 7; use Get-CimInstance' }
            @{ Pattern = '(?i)\bInvoke-WmiMethod\b'; Why = 'removido no PS 7; use Invoke-CimMethod' }
        )
        foreach ($rule in $forbidden) {
            $text | Should -Not -Match $rule.Pattern -Because $rule.Why
        }
    }
}
