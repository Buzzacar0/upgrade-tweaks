BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $tweakCases = foreach ($file in Get-ChildItem -Path (Join-Path $repoRoot 'config') -Filter 'tweaks*.json') {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $raw.tweaks | ForEach-Object { @{ Id = $_.id; Arquivo = $file.Name } }
    }
    $tweakCases = @($tweakCases)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $catalog = [ordered]@{ tweaks = @() }
    foreach ($file in Get-ChildItem -Path (Join-Path $UTTestRepoRoot 'config') -Filter 'tweaks*.json') {
        $catalog.tweaks += @((ConvertTo-UTHashtable (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)).tweaks)
    }
    $fixture = ConvertTo-UTHashtable (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}

Describe 'Catálogo config\tweaks-*.json' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'tem a lista de tweaks' {
        @($catalog.tweaks).Count | Should -BeGreaterThan 0
    }

    It 'não tem ids repetidos entre os arquivos' {
        $ids = @($catalog.tweaks | ForEach-Object { $_.id })
        @($ids | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
    }

    It 'o motor carrega todos (nenhum descartado como inválido)' {
        $loaded = @(Get-UTTweak)
        $loaded.Count | Should -BeGreaterOrEqual @($catalog.tweaks).Count
    }

    It 'a categoria do tweak combina com o arquivo onde ele está' {
        $map = @{ 'tweaks-gaming.json' = 'Gaming'; 'tweaks-energia.json' = 'Energia'; 'tweaks-latencia.json' = 'Latencia'; 'tweaks-warzone.json' = 'Warzone'
            'tweaks-rede.json' = 'Rede'; 'tweaks-servicos.json' = 'ServicosApps'; 'tweaks-privacidade.json' = 'Privacidade'; 'tweaks-visual.json' = 'Visual'; 'tweaks-personalizar.json' = 'Personalizar' }
        foreach ($file in Get-ChildItem -Path (Join-Path $UTTestRepoRoot 'config') -Filter 'tweaks-*.json') {
            $expected = $map[$file.Name]
            if (-not $expected) { continue }
            foreach ($t in (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).tweaks) {
                $t.categoria | Should -Be $expected -Because "$($t.id) está em $($file.Name)"
            }
        }
    }

    It '<Id> segue o esquema (campos, risco, desfazer, detecção)' -TestCases $tweakCases {
        $tweak = $catalog.tweaks | Where-Object { $_.id -eq $Id }
        $problems = @(Test-UTTweakDefinition -Tweak $tweak)
        $problems -join "`n" | Should -BeNullOrEmpty
    }

    It '<Id> tem textos em PT-BR suficientes para a interface' -TestCases $tweakCases {
        $tweak = $catalog.tweaks | Where-Object { $_.id -eq $Id }
        $tweak.nome.Length | Should -BeLessOrEqual 90
        $tweak.descricao.Length | Should -BeGreaterThan 40
    }
}

Describe 'Test-UTTweakDefinition (regras)' {
    BeforeEach {
        $base = ConvertTo-UTHashtable ((ConvertTo-Json -InputObject ($fixture.tweaks | Where-Object { $_.id -eq 'UT_Test_Reg' }) -Depth 10) | ConvertFrom-Json)
    }

    It 'o catálogo de teste inteiro é válido' {
        foreach ($t in $fixture.tweaks) { @(Test-UTTweakDefinition -Tweak $t) -join ' | ' | Should -BeNullOrEmpty -Because $t.id }
    }

    It 'acusa campo obrigatório faltando' {
        $base.Remove('descricao')
        Test-UTTweakDefinition -Tweak $base | Should -Contain "campo obrigatório 'descricao' ausente ou vazio"
    }

    It 'acusa risco inválido e risco alto sem confirmação' {
        $base.risco = 'medio'
        (Test-UTTweakDefinition -Tweak $base) -join ' ' | Should -Match 'risco .medio. inválido'
        $base.risco = 'alto'
        Test-UTTweakDefinition -Tweak $base | Should -Contain "risco alto exige o texto de 'confirmacao'"
    }

    It 'acusa script de aplicar sem script de desfazer' {
        $base.scriptAplicar = @('Write-Output 1')
        $base.deteccao = 'combinada'
        $base.scriptDetectar = @('$true')
        Test-UTTweakDefinition -Tweak $base | Should -Contain 'scriptAplicar sem scriptDesfazer'
    }

    It 'acusa registro sem valorOriginal e com tipo errado' {
        $base.registro[0].Remove('valorOriginal')
        $base.registro[1].tipo = 'Texto'
        $p = (Test-UTTweakDefinition -Tweak $base) -join ' | '
        $p | Should -Match 'registro\[1\] sem valorOriginal'
        $p | Should -Match "registro\[2\] tipo 'Texto' inválido"
    }

    It 'acusa valor incompatível com o tipo' {
        $base.registro[0].valor = 'abc'
        (Test-UTTweakDefinition -Tweak $base) -join ' | ' | Should -Match 'valor incompatível com DWord'
    }

    It 'acusa erro de sintaxe nos scripts' {
        $base.scriptAplicar = @('if (')
        $base.scriptDesfazer = @('$null')
        $base.scriptDetectar = @('$true')
        $base.deteccao = 'combinada'
        (Test-UTTweakDefinition -Tweak $base) -join ' | ' | Should -Match 'scriptAplicar com erro de sintaxe'
    }

    It 'acusa tweak sem nenhuma ação' {
        $base.registro = @()
        (Test-UTTweakDefinition -Tweak $base) -join ' | ' | Should -Match 'nenhuma ação'
    }
}

Describe 'Test-UTTweakCompatibility' {
    BeforeAll {
        $tweak = [ordered]@{
            compatibilidade = [ordered]@{
                windows = @('11'); buildMinimo = 22631; gpu = @('nvidia'); cpu = @('amd')
                notebook = $false; desktop = $true; launchersBloqueados = @('xbox'); x3dDuplo = $false
            }
        }
        function New-Ctx([hashtable]$Change) {
            $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = 'unico' }
            foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
            return [pscustomobject]$c
        }
    }

    It 'compatível no PC padrão de teste' {
        (Test-UTTweakCompatibility -Tweak $tweak -Contexto (New-Ctx @{})).Compativel | Should -BeTrue
    }

    It 'bloqueia <Caso>' -TestCases @(
        @{ Caso = 'Windows 10'; Change = @{ WindowsGeracao = '10' }; Texto = 'Windows 11' }
        @{ Caso = 'build antigo'; Change = @{ Build = 22621 }; Texto = 'build 22631' }
        @{ Caso = 'GPU AMD'; Change = @{ GpuFabricantes = @('amd') }; Texto = 'placa de vídeo' }
        @{ Caso = 'CPU Intel'; Change = @{ CpuFabricante = 'intel' }; Texto = 'processador' }
        @{ Caso = 'notebook'; Change = @{ EhNotebook = $true }; Texto = 'notebooks' }
        @{ Caso = 'Xbox App'; Change = @{ Launchers = @('battlenet', 'xbox') }; Texto = 'Xbox App/Game Pass' }
        @{ Caso = 'X3D de dois CCDs'; Change = @{ X3D = 'duplo' }; Texto = 'dois CCDs' }
    ) {
        $r = Test-UTTweakCompatibility -Tweak $tweak -Contexto (New-Ctx $Change)
        $r.Compativel | Should -BeFalse
        $r.Motivo | Should -Match ([regex]::Escape($Texto))
    }

    It 'informação desconhecida do PC nunca bloqueia' {
        $ctx = [pscustomobject]@{ WindowsGeracao = $null; Build = $null; GpuFabricantes = @(); CpuFabricante = $null; EhNotebook = $null; Launchers = @(); X3D = $null }
        (Test-UTTweakCompatibility -Tweak $tweak -Contexto $ctx).Compativel | Should -BeTrue
    }

    It 'PC com duas GPUs passa se uma delas é permitida' {
        (Test-UTTweakCompatibility -Tweak $tweak -Contexto (New-Ctx @{ GpuFabricantes = @('intel', 'nvidia') })).Compativel | Should -BeTrue
    }
}
