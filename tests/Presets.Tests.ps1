BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Presets (config\presets.json)' {
    BeforeAll {
        Reset-UTTestEnvironment
        $catalog = @(Get-UTTweak)
        $byId = @{}; foreach ($t in $catalog) { $byId[[string]$t.id] = $t }
        $cfg = Get-UTConfig -Name 'presets'
        $seguro = @(Get-UTPresetTweakId -Nome Seguro)
        $competitivo = @(Get-UTPresetTweakId -Nome Competitivo)
        $extremo = @(Get-UTPresetTweakId -Nome Extremo)
    }

    It 'tem Seguro, Competitivo e Extremo, cada um contendo o anterior' {
        Get-UTPresetName | Should -Be @('Seguro', 'Competitivo', 'Extremo')
        foreach ($id in $seguro) { $competitivo | Should -Contain $id }
        foreach ($id in $competitivo) { $extremo | Should -Contain $id }
        $competitivo.Count | Should -BeGreaterThan $seguro.Count
        $extremo.Count | Should -BeGreaterThan $competitivo.Count
    }

    It 'todo id citado existe no catálogo' {
        foreach ($p in $cfg.presets) { foreach ($id in $p.ajustes) { $byId.ContainsKey([string]$id) | Should -BeTrue -Because "$($p.nome): $id" } }
        foreach ($id in @($cfg.nuncaEmPreset) + @($cfg.foraDaLinhaDeComando)) { $byId.ContainsKey([string]$id) | Should -BeTrue -Because $id }
    }

    It 'Seguro: só risco baixo e nada controverso' {
        foreach ($id in $seguro) {
            $byId[$id].risco | Should -Be 'baixo' -Because $id
            [bool]$byId[$id].controverso | Should -BeFalse -Because $id
        }
    }

    It 'Competitivo: nada de risco alto' {
        foreach ($id in $competitivo) { $byId[$id].risco | Should -Not -Be 'alto' -Because $id }
    }

    It 'nenhum preset tem serviço do Xbox, Spooler, DNS, personalização ou duas alternativas do mesmo grupo' {
        foreach ($set in @(, $seguro) + @(, $competitivo) + @(, $extremo)) {
            foreach ($id in $set) {
                $id | Should -Not -Match '^UT_Svc_(Xbl|Xbox|Gaming)|^UT_Svc_Spooler$|^UT_Net_DNS_'
                $byId[$id].categoria | Should -Not -Be 'Personalizar'
            }
            $groups = @($set | ForEach-Object { $byId[$_].grupoExclusivo } | Where-Object { $_ })
            @($groups | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        }
    }

    It 'nunca remove Store, Xbox App, Gaming Services, Game Bar, Calculadora, Fotos, Terminal ou App Installer' {
        foreach ($id in $extremo) { $id | Should -Not -Match 'WindowsStore|XboxApp|GamingApp|GamingServices|XboxGamingOverlay|WindowsCalculator|Windows_Photos|WindowsTerminal|DesktopAppInstaller' }
    }

    It 'todo ajuste do catálogo está em algum preset ou foi deixado de fora de propósito' {
        $never = @($cfg.nuncaEmPreset)
        foreach ($t in $catalog) {
            ($extremo -contains $t.id) -or ($never -contains $t.id) -or ($t.categoria -eq 'Personalizar') | Should -BeTrue -Because $t.id
        }
    }

    It 'taxa do monitor fica fora da linha de comando (ninguém para confirmar em 15 s)' {
        $competitivo | Should -Contain 'UT_GPU_MonitorMaxHz'
        Get-UTPresetTweakId -Nome Competitivo -LinhaDeComando | Should -Not -Contain 'UT_GPU_MonitorMaxHz'
    }

    It 'Extremo exige digitar EU ENTENDO' {
        $s = Get-UTPresetSelection -Nome Extremo
        $s.ExigeConfirmacao | Should -BeTrue
        $s.TextoConfirmacao | Should -Be 'EU ENTENDO'
        (Get-UTPresetSelection -Nome Seguro).ExigeConfirmacao | Should -BeFalse
    }

    It 'preset inexistente dá erro claro' {
        { Get-UTPresetTweakId -Nome 'Turbo' } | Should -Throw '*não existe*'
    }
}

Describe 'Exportar e importar seleção' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'ida e volta mantém os ajustes na ordem do catálogo' {
        $file = Join-Path $TestDrive 'sel.json'
        Export-UTSelection -Id @('UT_Gaming_GameMode_On', 'UT_Gaming_GameDVR_Off', 'NAO_EXISTE') -Caminho $file -Descricao 'Cliente X' | Should -Be $file
        $j = Get-Content $file -Raw | ConvertFrom-Json
        $j.programa | Should -Be 'Upgrade Tweaks'
        @($j.ajustes).Count | Should -Be 2
        $imp = Import-UTSelection -Caminho $file
        $imp.Ids | Should -Be @(Get-UTTweak | Where-Object { $_.id -in 'UT_Gaming_GameMode_On', 'UT_Gaming_GameDVR_Off' } | ForEach-Object id)
        $imp.Descricao | Should -Be 'Cliente X'
    }

    It 'aceita lista simples e avisa ids desconhecidos' {
        $file = Join-Path $TestDrive 'lista.json'
        '["UT_Gaming_GameMode_On","UT_Futuro_Ajuste"]' | Set-Content $file
        $imp = Import-UTSelection -Caminho $file
        $imp.Ids | Should -Be @('UT_Gaming_GameMode_On')
        $imp.Desconhecidos | Should -Be @('UT_Futuro_Ajuste')
    }

    It 'arquivo inválido dá erro claro' {
        $file = Join-Path $TestDrive 'ruim.json'
        'isto não é json' | Set-Content $file
        { Import-UTSelection -Caminho $file } | Should -Throw '*não é um JSON válido*'
        { Import-UTSelection -Caminho (Join-Path $TestDrive 'nada.json') } | Should -Throw '*não encontrado*'
    }
}

Describe 'Linha de comando' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Write-UTConsole {}
        Mock Get-UTHardwareInfo { [pscustomobject]@{} }
        $script:applied = $null
        Mock Invoke-UTTweak {
            $script:applied = [pscustomobject]@{ Ids = @($Id); Risco = [bool]$RiscoAltoConfirmado; WhatIf = [bool]$WhatIfPreference }
            foreach ($i in $Id) { [pscustomobject]@{ Id = $i; Nome = $i; Acao = 'Aplicar'; Status = $(if ($WhatIfPreference) { 'Simulado' } else { 'Aplicado' }); Mensagem = 'ok'; RequerReinicio = $false; Acoes = @() } }
        }
    }

    It '-Preset Seguro aplica os ajustes do preset e sai com 0' {
        Invoke-UTCommandLine -Preset Seguro | Should -Be 0
        $script:applied.Ids | Should -Be @(Get-UTPresetTweakId -Nome Seguro -LinhaDeComando)
        $script:applied.Risco | Should -BeFalse
        Should -Invoke Get-UTHardwareInfo -Times 1
    }

    It '-Simular -Preset Competitivo só simula' {
        Invoke-UTCommandLine -Preset Competitivo -Simular | Should -Be 0
        $script:applied.WhatIf | Should -BeTrue
        $script:applied.Ids | Should -Not -Contain 'UT_GPU_MonitorMaxHz'
    }

    It 'Extremo: digitou EU ENTENDO, inclui risco alto; não digitou, pula' {
        $UTSync.Silencioso = $false
        Mock Read-UTConsoleInput { 'EU ENTENDO' }
        Invoke-UTCommandLine -Preset Extremo | Out-Null
        $script:applied.Risco | Should -BeTrue
        Mock Read-UTConsoleInput { 'eu entendo' }
        Invoke-UTCommandLine -Preset Extremo | Out-Null
        $script:applied.Risco | Should -BeFalse
    }

    It 'Extremo com -Silencioso nunca pergunta e pula o risco alto' {
        $UTSync.Silencioso = $true
        Mock Read-UTConsoleInput { 'EU ENTENDO' }
        Invoke-UTCommandLine -Preset Extremo | Out-Null
        $script:applied.Risco | Should -BeFalse
        Should -Invoke Read-UTConsoleInput -Times 0
        Should -Invoke Write-UTConsole -Times 0
    }

    It 'código de saída: falha = 1, reinício pendente = 3010' {
        Mock Invoke-UTTweak { [pscustomobject]@{ Id = 'a'; Nome = 'A'; Status = 'Falhou'; Mensagem = 'x'; RequerReinicio = $false; Acoes = @() } }
        Invoke-UTCommandLine -Preset Seguro | Should -Be 1
        Mock Invoke-UTTweak { [pscustomobject]@{ Id = 'a'; Nome = 'A'; Status = 'Aplicado'; Mensagem = 'x'; RequerReinicio = $true; Acoes = @() } }
        Invoke-UTCommandLine -Preset Seguro | Should -Be 3010
    }

    It '-Config aplica a seleção do arquivo' {
        $file = Join-Path $TestDrive 'cfg.json'
        Export-UTSelection -Id @('UT_Gaming_GameMode_On') -Caminho $file | Out-Null
        Invoke-UTCommandLine -Config $file | Should -Be 0
        $script:applied.Ids | Should -Be @('UT_Gaming_GameMode_On')
        Invoke-UTCommandLine -Config (Join-Path $TestDrive 'nao.json') | Should -Be 2
    }

    It 'parâmetros que não combinam saem com 2' {
        Invoke-UTCommandLine -Preset Seguro -Config 'x.json' | Should -Be 2
        Invoke-UTCommandLine -Preset Seguro -DesfazerTudo | Should -Be 2
        Invoke-UTCommandLine -Preset 'Turbo' | Should -Be 2
        Should -Invoke Invoke-UTTweak -Times 0
    }

    It '-DesfazerTudo pede S, e no -Silencioso desfaz direto' {
        Mock Get-UTAppliedRecord { [pscustomobject]@{ tweakId = 'UT_Gaming_GameMode_On' } }
        Mock Undo-UTAllTweak { [pscustomobject]@{ Id = 'UT_Gaming_GameMode_On'; Nome = 'Modo de Jogo'; Status = 'Desfeito'; Mensagem = 'ok'; RequerReinicio = $false; Acoes = @() } }
        $UTSync.Silencioso = $false
        Mock Read-UTConsoleInput { 'n' }
        Invoke-UTCommandLine -DesfazerTudo | Should -Be 0
        Should -Invoke Undo-UTAllTweak -Times 0
        Mock Read-UTConsoleInput { 's' }
        Invoke-UTCommandLine -DesfazerTudo | Should -Be 0
        Should -Invoke Undo-UTAllTweak -Times 1
        $UTSync.Silencioso = $true
        Invoke-UTCommandLine -DesfazerTudo | Should -Be 0
        Should -Invoke Undo-UTAllTweak -Times 2
        Invoke-UTCommandLine -DesfazerTudo -Simular | Should -Be 0
        Should -Invoke Undo-UTAllTweak -Times 2
    }

    It '-Diagnostico -ExportarRelatorio gera o relatório' {
        Mock Get-UTDiagnostic { [pscustomobject]@{ Nota = 72; Pendencias = @([pscustomobject]@{ Status = 'Aviso'; Titulo = 'XMP'; Mensagem = 'desligado'; Aba = 'BIOS' }); Verificacoes = @(); Hardware = [pscustomobject]@{} } }
        Mock Get-UTHardwareSummaryLine { [pscustomobject]@{ Rotulo = 'CPU'; Valor = 'Ryzen' } }
        Mock Export-UTDiagnosticReport { $Path }
        Invoke-UTCommandLine -Diagnostico -ExportarRelatorio 'C:\relatorio.html' | Should -Be 0
        Should -Invoke Export-UTDiagnosticReport -Times 1 -ParameterFilter { $Path -eq 'C:\relatorio.html' }
        Should -Invoke Invoke-UTTweak -Times 0
    }

    It 'Invoke-UTMain manda os parâmetros de linha de comando para o modo sem interface' {
        . (Join-Path $UTTestRepoRoot 'scripts\main.ps1')
        Mock Invoke-UTCommandLine { 0 }
        Mock Show-UTMainWindow { 0 }
        Invoke-UTMain -Preset Seguro | Should -Be 0
        Should -Invoke Invoke-UTCommandLine -Times 1 -ParameterFilter { $Preset -eq 'Seguro' }
        Should -Invoke Show-UTMainWindow -Times 0
        Invoke-UTMain -Simular | Out-Null
        Should -Invoke Show-UTMainWindow -Times 1 -ParameterFilter { $Simular }
    }
}
