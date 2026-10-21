BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'scripts\lib\CompileHelpers.ps1')

    function Invoke-Both([string]$Code) {
        $original = @(& ([scriptblock]::Create($Code)))
        $converted = ConvertTo-UTAsciiScript -Script $Code
        $after = @(& ([scriptblock]::Create($converted)))
        return [pscustomobject]@{ Original = $original; Depois = $after; Codigo = $converted }
    }
}

Describe 'ConvertTo-UTAsciiScript' {
    It 'gera só ASCII e mantém o mesmo valor das strings' {
        $nl = "`r`n"
        $code = @(
            '$a = ''ação'''
            '$b = "olá $($a.Length) é"'
            ('$c = @''' + $nl + 'linha com ç e "aspas" e $nao' + $nl + '''@')
            ('$d = @"' + $nl + 'here expansível: $a ñ' + $nl + '"@')
            '# comentário com acentuação'
            '$e = ''it''''s ção $literal `crase "aspas"'''
            '$f = "aspas `"x`" e `$ literal ção"'
            '$a, $b, $c, $d, $e, $f'
        ) -join $nl
        $r = Invoke-Both $code
        Test-UTHasNonAscii $r.Codigo | Should -BeFalse
        $r.Depois.Count | Should -Be 6
        for ($i = 0; $i -lt 6; $i++) { $r.Depois[$i] | Should -BeExactly $r.Original[$i] }
    }

    It 'remove acentos dos comentários' {
        (ConvertTo-UTAsciiScript -Script "# Otimização`n1") | Should -Match '# Otimizacao'
    }

    It 'converte caracteres fora do BMP (emoji) em pares substitutos' {
        $code = '"ok ' + [char]::ConvertFromUtf32(0x1F680) + '"'
        $r = Invoke-Both $code
        $r.Depois[0] | Should -BeExactly $r.Original[0]
    }

    It 'recusa acento em nome de função' {
        { ConvertTo-UTAsciiScript -Script 'function Ação { 1 }' } | Should -Throw '*fora de string ou comentário*'
    }

    It 'recusa acento em argumento sem aspas' {
        { ConvertTo-UTAsciiScript -Script 'Write-Output ação' } | Should -Throw '*fora de string*'
    }

    It 'recusa script com erro de sintaxe' {
        { ConvertTo-UTAsciiScript -Script 'if (' } | Should -Throw '*Erro de sintaxe*'
    }
}

Describe 'ConvertTo-UTAsciiJson e ConvertTo-UTAsciiXml' {
    It 'JSON escapado continua com os mesmos dados' {
        $json = '{"nome":"Desativar gravação","lista":["ç","ã"]}'
        $ascii = ConvertTo-UTAsciiJson $json
        Test-UTHasNonAscii $ascii | Should -BeFalse
        $obj = $ascii | ConvertFrom-Json
        $obj.nome | Should -BeExactly 'Desativar gravação'
        $obj.lista[1] | Should -BeExactly 'ã'
    }

    It 'XAML escapado continua com o mesmo texto' {
        $xml = '<Root Titulo="Configurações"><T>Início ' + [char]::ConvertFromUtf32(0x1F680) + '</T></Root>'
        $ascii = ConvertTo-UTAsciiXml $xml
        Test-UTHasNonAscii $ascii | Should -BeFalse
        $doc = [xml]$ascii
        $doc.Root.Titulo | Should -BeExactly 'Configurações'
        $doc.Root.T | Should -BeExactly ('Início ' + [char]::ConvertFromUtf32(0x1F680))
    }
}

Describe 'scripts\compile.ps1' {
    BeforeAll {
        $out = Join-Path $TestDrive 'upgradetweaks.ps1'
        & (Join-Path $repoRoot 'scripts\compile.ps1') -Version '9.9.9' -OutputPath $out *> $null
        $text = [IO.File]::ReadAllText($out)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($out, [ref]$tokens, [ref]$errors)
    }

    It 'gera um arquivo só com bytes ASCII (seguro para irm | iex no PowerShell 5.1)' {
        $bytes = [IO.File]::ReadAllBytes($out)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'o arquivo compilado não tem erros de sintaxe no PowerShell atual' {
        $errors.Count | Should -Be 0
    }

    It 'mantém o bloco de parâmetros do start.ps1 no início' {
        $names = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
        $names | Should -Be @('Preset', 'Config', 'Silencioso', 'DesfazerTudo', 'Diagnostico', 'ExportarRelatorio', 'Simular')
    }

    It 'substitui versão e build e remove o carregador de desenvolvimento' {
        $text | Should -Match "\`$UTVersion = '9\.9\.9'"
        $text | Should -Match "\`$UTBuild = 'release'"
        $text | Should -Not -Match 'DEV-LOADER'
        $text | Should -Not -Match '#\{versao\}'
    }

    It 'inclui todas as funções antes do código principal' {
        $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $names = $functions | ForEach-Object { $_.Name }
        foreach ($expected in 'Write-UTLog', 'Test-UTAdmin', 'Invoke-UTElevation', 'Get-UTWindowsSupport', 'Invoke-UTMain', 'Show-UTBanner') {
            $names | Should -Contain $expected
        }
        $firstCall = $text.IndexOf('Test-UTAdmin) -or')
        $firstCall | Should -BeGreaterThan $text.IndexOf('function Test-UTAdmin')
    }

    It 'as mensagens com acento continuam corretas depois da conversão' {
        $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $defs = ($functions | Where-Object { $_.Name -eq 'Get-UTWindowsSupport' } | ForEach-Object { $_.Extent.Text }) -join "`n"
        . ([scriptblock]::Create($defs))
        $msg = (Get-UTWindowsSupport -Info ([pscustomobject]@{ Build = 26200; Descricao = 'Windows 11' })).Mensagem
        $msg | Should -BeExactly 'Windows 11: versão suportada.'
    }
}

Describe 'README' {
    It 'a tabela de ajustes está em dia com o catálogo (scripts\build-docs.ps1)' {
        $exe = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
        $out = & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\build-docs.ps1') -Verificar 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out -join ' ')
    }
}

