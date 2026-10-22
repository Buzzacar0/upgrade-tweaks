BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-UTUiAssembly
    function Initialize-TestWindow {
        if ($null -eq (Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue)) { Reset-UTTestEnvironment }
        $ui = Initialize-UTUiState
        $w = Get-UTUiWindow -Name 'MainWindow'
        $ui.Window = $w.Window
        $ui.C = $w.Controles
        Initialize-UTUiNavigation
        return $ui
    }
    function Set-Ctx {
        $UTSync.Contexto = [pscustomobject]@{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null
            Executaveis = @('H:\HQ\cod.exe'); PastasJogo = @('H:\HQ') }
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Janela principal (XAML)' {
    It 'carrega e tem todos os controles que o código usa' {
        $ui = Initialize-TestWindow
        $ui.Window | Should -BeOfType System.Windows.Window
        $ui.Window.MinWidth | Should -Be 1100
        $ui.Window.MinHeight | Should -Be 700
        $used = foreach ($f in Get-ChildItem (Join-Path $UTTestRepoRoot 'functions\ui') -Filter *.ps1) { [regex]::Matches((Get-Content $f.FullName -Raw), "\.C\['(\w+)'\]") | ForEach-Object { $_.Groups[1].Value } }
        foreach ($n in @($used | Sort-Object -Unique)) { $ui.C.ContainsKey($n) | Should -BeTrue -Because "o código usa o controle $n" }
    }

    It 'usa o design system: roxo da Upgrade Store nos dois temas, superfícies de cada tema' {
        $ui = Initialize-TestWindow
        Set-UTUiTheme -Janela $ui.Window -Tema escuro | Should -Be 'escuro'
        $ui.Window.FindResource('AccentBrush').Color.ToString() | Should -Be '#FF7C3AED'
        $ui.Window.FindResource('BgBrush').Color.ToString() | Should -Be '#FF1C1C1E'
        $ui.Window.FindResource('CardBrush').Color.ToString() | Should -Be '#FF2C2C2E'
        Set-UTUiTheme -Janela $ui.Window -Tema claro | Should -Be 'claro'
        $ui.Window.FindResource('AccentBrush').Color.ToString() | Should -Be '#FF7C3AED'
        $ui.Window.FindResource('BgBrush').Color.ToString() | Should -Be '#FFF2F2F7'
        $ui.Window.FindResource('CardBrush').Color.ToString() | Should -Be '#FFFFFFFF'
        # The control styles stay; only the token dictionary is replaced.
        $ui.Window.Resources.MergedDictionaries.Count | Should -Be 2
        $ui.Window.TryFindResource('Switch') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Abas' {
    It 'segue a ordem pedida (com Latência como aba avançada)' {
        (Get-UTUiTabDefinition).Nome | Should -Be @('Início', 'Monitor', 'Overlay', 'Benchmark', 'Energia', 'Gaming', 'Latência', 'Rede', 'Serviços e Apps', 'Privacidade', 'GPU', 'Warzone', 'Ferramentas', 'BIOS', 'Programas', 'Personalizar', 'Restaurar', 'Sobre')
    }

    It 'cada aba tem a função que monta a página' {
        foreach ($t in Get-UTUiTabDefinition) {
            $name = "New-UTUiPage$($t.Id)"
            if ($t.PSObject.Properties['Pagina']) { $name = "New-UTUiPage$($t.Pagina)" }
            Get-Command $name -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because $t.Id
        }
    }

    It 'todo ajuste do catálogo aparece em alguma aba' {
        Reset-UTTestEnvironment
        $shown = foreach ($t in Get-UTUiTabDefinition) { Get-UTUiTabTweak -Aba $t.Id | ForEach-Object { $_.id } }
        foreach ($t in Get-UTTweak) { $shown | Should -Contain $t.id }
    }

    It 'abasExtras: a QoS do jogo aparece em Rede e em Warzone' {
        Reset-UTTestEnvironment
        $extra = Get-UTTweak -Id 'UT_Net_QoS_CoD'
        @($extra.abasExtras) | Should -Contain 'Warzone'
        if ($extra) {
            foreach ($a in @($extra.abasExtras) + $extra.categoria) {
                $tab = @(Get-UTUiTabDefinition | Where-Object { $_.Categorias -contains $a })[0]
                @(Get-UTUiTabTweak -Aba $tab.Id | ForEach-Object id) | Should -Contain $extra.id
            }
        }
    }

    It 'todas as abas montam sem erro (trabalho em segundo plano simulado)' {
        Reset-UTTestEnvironment; Set-Ctx
        $ui = Initialize-TestWindow
        Mock Invoke-UTUiJob { [pscustomobject]@{ Nome = $Nome } }
        Mock Test-UTUiVendor { $true }
        Mock Get-UTWarzoneGuide { [pscustomobject]@{ Grupo = 'Tela'; Opcao = 'Modo'; Valor = 'Tela cheia'; Motivo = 'x' } }
        foreach ($t in Get-UTUiTabDefinition) {
            { Show-UTUiPage -Id $t.Id } | Should -Not -Throw -Because $t.Id
            $ui.Pages[$t.Id] | Should -BeOfType System.Windows.UIElement
            $ui.C['PageHost'].Content | Should -Be $ui.Pages[$t.Id]
        }
        $ui.C['NavList'].SelectedItem.Tag | Should -Be 'Sobre'
    }
}

Describe 'Linhas de ajuste e seleção' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        $ui = Initialize-TestWindow
        $tweaks = @(Get-UTUiTabTweak -Aba Gaming)
        $list = New-UTUiTweakList -Tweaks $tweaks -Pagina Gaming
        $ids = @($tweaks | ForEach-Object { [string]$_.id })
    }

    It 'uma linha por ajuste, com selos de risco/reinício' {
        @($ui.Rows | Where-Object Pagina -eq 'Gaming').Count | Should -Be $tweaks.Count
        $list | Should -BeOfType System.Windows.Controls.StackPanel
    }

    It 'ligar vira pendência; o estado lido limpa o que já está feito; "Não se aplica" bloqueia' {
        Set-UTUiSelection -Id $ids[0], $ids[1] -Marcado $true
        $ui.C['SelectionText'].Text | Should -Be '2 alterações pendentes'
        $row0 = @($ui.Rows | Where-Object { $_.Id -eq $ids[0] })[0]
        $row0.Check.IsChecked | Should -BeTrue
        $row0.EstadoTexto.Text | Should -Be 'Será aplicado'
        Sync-UTUiTweakState -Estados @([pscustomobject]@{ Id = $ids[0]; Estado = 'Incompativel'; Motivo = 'Só para notebook' }, [pscustomobject]@{ Id = $ids[1]; Estado = 'Aplicado'; Motivo = $null })
        $row0.Check.IsEnabled | Should -BeFalse
        $row0.EstadoTexto.Text | Should -Be 'Não se aplica'
        $ui.Selecionados.Contains($ids[0]) | Should -BeFalse
        $row1 = @($ui.Rows | Where-Object { $_.Id -eq $ids[1] })[0]
        $row1.EstadoTexto.Text | Should -Be 'Aplicado'
        $row1.Check.IsChecked | Should -BeTrue
        $ui.C['SelectionText'].Text | Should -Be 'Nenhuma alteração pendente'
        Set-UTUiSelection -Id $ids[0] -Marcado $true
        $ui.Selecionados.Contains($ids[0]) | Should -BeFalse
    }

    It 'desligar um ajuste aplicado vira "Será desfeito"; ligar de novo cancela' {
        Sync-UTUiTweakState -Estados @([pscustomobject]@{ Id = $ids[1]; Estado = 'Aplicado'; Motivo = $null })
        $row1 = @($ui.Rows | Where-Object { $_.Id -eq $ids[1] })[0]
        $row1.Check.IsChecked = $false
        $ui.Desmarcados.Contains($ids[1]) | Should -BeTrue
        $row1.EstadoTexto.Text | Should -Be 'Será desfeito'
        $ui.C['SelectionText'].Text | Should -Be '1 alteração pendente'
        Get-UTUiUndoId | Should -Be @($ids[1])
        @(Get-UTUiOnId) | Should -Not -Contain $ids[1]
        $row1.Check.IsChecked = $true
        $ui.Desmarcados.Count | Should -Be 0
        @(Get-UTUiOnId) | Should -Contain $ids[1]
        Clear-UTUiSelection
        Get-UTUiPendingCount | Should -Be 0
    }

    It 'a seleção sai na ordem do catálogo' {
        Set-UTUiSelection -Id ($ids | Sort-Object -Descending) -Marcado $true
        $catalog = @(Get-UTTweak | Where-Object { $ids -contains $_.id } | ForEach-Object id)
        Get-UTUiSelectedId | Should -Be $catalog
    }

    It 'busca ignora acentos e maiúsculas' {
        @(Find-UTUiTweak -Texto 'ACELERACAO do mouse' | ForEach-Object id) | Should -Contain 'UT_Gaming_MouseAccel_Off'
        @(Find-UTUiTweak -Texto 'gravação').Count | Should -BeGreaterThan 0
    }
}

Describe 'Aplicar, desfazer e simular' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        $ui = Initialize-TestWindow
        $script:jobs = @()
        Mock Invoke-UTUiJob { $script:jobs += [pscustomobject]@{ Nome = $Nome; Argumentos = $Argumentos; Estado = $Estado; Exclusivo = [bool]$Exclusivo } ; [pscustomobject]@{ Nome = $Nome } }
        $high = @(Get-UTTweak | Where-Object risco -eq 'alto')[0].id
        $low = @(Get-UTTweak | Where-Object risco -eq 'baixo')[0].id
    }

    It 'sem nada pendente só avisa' {
        Mock Show-UTUiDialog { 'OK' }
        Invoke-UTUiRun -Modo Aplicar
        $script:jobs.Count | Should -Be 0
        Should -Invoke Show-UTUiDialog -Times 1 -ParameterFilter { $Titulo -eq 'Nada para aplicar' }
    }

    It 'risco alto: "pular" aplica só os outros' {
        Set-UTUiSelection -Id $high, $low -Marcado $true
        Mock Show-UTUiDialog { if ($Titulo -eq 'Ajustes de risco alto') { 'Pular os de risco alto' } else { 'Aplicar' } }
        Invoke-UTUiRun -Modo Aplicar
        $script:jobs.Count | Should -Be 1
        $script:jobs[0].Argumentos.Ids | Should -Be @($low)
        $script:jobs[0].Argumentos.Risco | Should -BeFalse
        $script:jobs[0].Exclusivo | Should -BeTrue
    }

    It 'risco alto confirmado vai com RiscoAltoConfirmado' {
        Set-UTUiSelection -Id $high -Marcado $true
        Mock Show-UTUiDialog { if ($Titulo -eq 'Ajustes de risco alto') { 'Entendo o risco, aplicar' } else { 'Aplicar' } }
        Invoke-UTUiRun -Modo Aplicar
        $script:jobs[0].Argumentos.Risco | Should -BeTrue
    }

    It 'primeiro calcula (simulação), depois revisa; cancelar na revisão não aplica nada' {
        Set-UTUiSelection -Id $low -Marcado $true
        Mock Show-UTUiDialog { 'Cancelar' }
        Invoke-UTUiRun -Modo Aplicar
        $script:jobs.Count | Should -Be 1
        $script:jobs[0].Nome | Should -Be 'Calculando o que vai mudar'
        $sim = [pscustomobject]@{ Ok = $true; Erro = $null; Resultado = @([pscustomobject]@{ Id = $low; Nome = 'X'; Status = 'Simulado'; Mensagem = ''; RequerReinicio = $false; Acoes = @('Registro: 0 -> 1') }) }
        Complete-UTUiPreview -Resultado $sim -Estado $script:jobs[0].Estado
        Should -Invoke Show-UTUiDialog -Times 1 -ParameterFilter { $Titulo -eq 'Aplicar 1 alteração?' -and $Itens -contains 'Ligar: X' }
        $script:jobs.Count | Should -Be 1
        $ui.Selecionados.Contains($low) | Should -BeTrue
        Invoke-UTUiRun -Modo Desfazer
        $script:jobs.Count | Should -Be 1
    }

    It 'revisão confirmada aplica os ligados e desfaz os desligados na mesma rodada' {
        $other = @(Get-UTTweak | Where-Object { $_.risco -eq 'baixo' -and $_.id -ne $low })[0].id
        Set-UTUiSelection -Id $low -Marcado $true
        Sync-UTUiTweakState -Estados @([pscustomobject]@{ Id = $other; Estado = 'Aplicado'; Motivo = $null })
        Set-UTUiPending -Id $other -Ligado $false
        Mock Show-UTUiDialog { 'Aplicar' }
        Mock Show-UTUiRunSummary {}
        Invoke-UTUiRun -Modo Aplicar
        $script:jobs[0].Argumentos.Ids | Should -Be @($low)
        $script:jobs[0].Argumentos.Desfazer | Should -Be @($other)
        $sim = [pscustomobject]@{ Ok = $true; Erro = $null; Resultado = @(
                [pscustomobject]@{ Id = $low; Nome = 'A'; Status = 'Simulado'; Mensagem = ''; RequerReinicio = $false; Acoes = @() }
                [pscustomobject]@{ Id = $other; Nome = 'B'; Status = 'Simulado'; Mensagem = ''; RequerReinicio = $false; Acoes = @() }) }
        Complete-UTUiPreview -Resultado $sim -Estado $script:jobs[0].Estado
        Should -Invoke Show-UTUiDialog -ParameterFilter { $Titulo -eq 'Aplicar 2 alterações?' -and $Itens -contains 'Desligar: B' }
        $script:jobs[1].Nome | Should -Be 'Aplicando ajustes'
        $script:jobs[1].Argumentos.Desfazer | Should -Be @($other)
        $done = [pscustomobject]@{ Ok = $true; Erro = $null; Resultado = @(
                [pscustomobject]@{ Id = $low; Nome = 'A'; Status = 'Aplicado'; Mensagem = ''; RequerReinicio = $false; Acoes = @() }
                [pscustomobject]@{ Id = $other; Nome = 'B'; Status = 'Desfeito'; Mensagem = ''; RequerReinicio = $false; Acoes = @() }) }
        Complete-UTUiRun -Resultado $done -Estado $script:jobs[1].Estado
        Get-UTUiPendingCount | Should -Be 0
        Should -Invoke Show-UTUiRunSummary -Times 1 -ParameterFilter { $Titulo -eq 'Pronto' }
    }

    It 'falha mantém a pendência para tentar de novo' {
        Set-UTUiSelection -Id $low -Marcado $true
        Mock Show-UTUiRunSummary {}
        $done = [pscustomobject]@{ Ok = $true; Erro = $null; Resultado = @([pscustomobject]@{ Id = $low; Nome = 'A'; Status = 'Falhou'; Mensagem = 'erro'; RequerReinicio = $false; Acoes = @() }) }
        Complete-UTUiRun -Resultado $done -Estado @{ Ids = @($low); Desfazer = @(); Modo = 'Aplicar' }
        $ui.Selecionados.Contains($low) | Should -BeTrue
    }

    It 'no modo simulação, "Aplicar" vira simulação e não pede confirmação' {
        $UTSync.Simular = $true
        try {
            Set-UTUiSelection -Id $low -Marcado $true
            Mock Show-UTUiDialog { 'Cancelar' }
            Invoke-UTUiRun -Modo Aplicar
            $script:jobs[0].Argumentos.Modo | Should -Be 'Simular'
        } finally { $UTSync.Simular = $false }
    }

    It 'taxa do monitor: sem confirmar em 15 s, volta sozinha' {
        Mock Show-UTUiCountdownDialog { $false }
        Mock Show-UTUiRunSummary {}
        $r = [pscustomobject]@{ Ok = $true; Erro = $null; Resultado = @([pscustomobject]@{ Id = 'UT_GPU_MonitorMaxHz'; Nome = 'Hz'; Status = 'Aplicado'; Mensagem = ''; RequerReinicio = $false; Acoes = @() }) }
        Complete-UTUiRun -Resultado $r -Estado @{ Ids = @('UT_GPU_MonitorMaxHz'); Modo = 'Aplicar' }
        Should -Invoke Show-UTUiCountdownDialog -Times 1 -ParameterFilter { $Segundos -eq 15 }
        ($script:jobs | Where-Object Nome -eq 'Voltando a taxa de atualização') | Should -Not -BeNullOrEmpty
        $r.Resultado[0].Status | Should -Be 'Desfeito'
    }

    It 'Desfazer TUDO sem nada aplicado só avisa' {
        Mock Get-UTAppliedRecord { }
        Mock Show-UTUiDialog { 'OK' }
        $page = New-UTUiPageRestaurar
        $btn = $page.Children[1].Child.Children[2]
        & $btn.Tag.Acao $btn $btn.Tag.Dados
        Should -Invoke Show-UTUiDialog -Times 1 -ParameterFilter { $Titulo -eq 'Nada para desfazer' }
        @($script:jobs | Where-Object Nome -eq 'Desfazendo tudo').Count | Should -Be 0
    }

    It 'resumo oferece reiniciar quando precisa' {
        Mock Show-UTUiDialog { if ($Titulo -eq 'Reiniciar agora?') { 'Reiniciar' } else { 'Reiniciar agora' } }
        Mock Restart-UTUiComputer {}
        $res = @([pscustomobject]@{ Id = 'a'; Nome = 'A'; Status = 'Aplicado'; Mensagem = ''; RequerReinicio = $true; Acoes = @() }, [pscustomobject]@{ Id = 'b'; Nome = 'B'; Status = 'Falhou'; Mensagem = 'motivo'; RequerReinicio = $false; Acoes = @() })
        $s = Show-UTUiRunSummary -Resultados $res
        $s.Falhas.Count | Should -Be 1
        Should -Invoke Show-UTUiDialog -ParameterFilter { $Botoes -contains 'Reiniciar agora' -and $Itens -contains 'B: motivo' }
        Should -Invoke Restart-UTUiComputer -Times 1
    }
}

Describe 'Busca global' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        $ui = Initialize-TestWindow
        Mock Invoke-UTUiJob { [pscustomobject]@{ Nome = $Nome } }
    }

    It 'acha abas, ajustes e opções da BIOS do mapa carregado (sem ler a NVRAM)' {
        @(Find-UTUiTab -Texto 'latencia' | ForEach-Object Id) | Should -Be @('Latencia')
        $UTSync['BiosMapa'] = @{ Caminho = 'x'; Mapa = @{ Perguntas = @(
                    @{ Nome = 'Global C-state Control'; Menu = 'Advanced'; Formulario = 'AMD CBS' }
                    @{ Nome = 'Global C-state Control'; Menu = 'Advanced'; Formulario = 'Cópia' }
                    @{ Nome = 'SATA Mode'; Menu = 'Settings'; Formulario = 'IO Ports' }) } }
        Mock Get-UTBiosSetting { throw 'não deveria ler a NVRAM' }
        $b = @(Find-UTUiBiosOption -Texto 'c-state')
        $b.Count | Should -Be 1
        $b[0].Local | Should -Be 'Advanced > AMD CBS'
        Show-UTUiSearch -Texto 'c-state'
        $ui.C['PageHost'].Content.Children[0] | Should -Not -BeNullOrEmpty
        $ui.C['NavList'].SelectedItem | Should -BeNullOrEmpty
    }

    It 'sensores só entram enquanto o Monitor lê' {
        $UTSync['Sensores'] = $null
        @(Find-UTUiSensor -Texto 'cpu').Count | Should -Be 0
        $UTSync['Sensores'] = @{ Itens = @() }
        Mock Get-UTSensorSnapshot { @([pscustomobject]@{ Sensor = 'CPU Package'; Hardware = 'Ryzen 7'; Tipo = 'Temperatura'; Grupo = 'Processador'; Atual = '47 °C' }, [pscustomobject]@{ Sensor = 'GPU Core'; Hardware = 'RTX'; Tipo = 'Temperatura'; Grupo = 'Placa de vídeo'; Atual = '50 °C' }) }
        @(Find-UTUiSensor -Texto 'processador' | ForEach-Object Sensor) | Should -Be @('CPU Package')
        $UTSync['Sensores'] = $null
    }

    It 'texto curto volta para a página atual; ajustes da busca não ficam duplicados' {
        Show-UTUiPage -Id 'Gaming'
        Show-UTUiSearch -Texto 'mouse'
        $n = @($ui.Rows | Where-Object Pagina -eq 'Busca').Count
        $n | Should -BeGreaterThan 0
        Show-UTUiSearch -Texto 'mouse'
        @($ui.Rows | Where-Object Pagina -eq 'Busca').Count | Should -Be $n
        Show-UTUiSearch -Texto 'm'
        $ui.C['PageHost'].Content | Should -Be $ui.Pages['Gaming']
        @($ui.Rows | Where-Object Pagina -eq 'Busca').Count | Should -Be 0
    }

    It 'sem a janela na tela, checklist e contagem usam janela própria (sheet só com a janela aberta)' {
        Test-UTUiSheetAvailable | Should -BeFalse
    }
}
Describe 'Trabalho em segundo plano' {
    BeforeAll {
        Reset-UTTestEnvironment
        $ui = Initialize-UTUiState
        [void](Initialize-UTUiRunspacePool -Maximo 2)
        function Wait-UTTestJob { $t0 = Get-Date; while ($ui.Jobs.Count -gt 0 -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 100; Receive-UTUiJob } }
    }
    AfterAll { Close-UTUiPool }

    It 'roda funções do programa no pool e devolve o resultado na thread da tela' {
        $got = @{}
        [void](Invoke-UTUiJob -Nome 'teste' -Argumentos @{ Nome = 'gaming' } -Script { param($Nome) (Get-UTConfig -Name "tweaks-$Nome").tweaks.Count } -Estado $got -AoTerminar { param($R, $E) $E.R = $R })
        Wait-UTTestJob
        $got.R.Ok | Should -BeTrue
        $got.R.Resultado[0] | Should -BeGreaterThan 0
    }

    It 'erro vira mensagem, sem derrubar a tela' {
        $got = @{}
        [void](Invoke-UTUiJob -Nome 'falha' -Script { throw 'Mensagem amigável de teste.' } -Estado $got -AoTerminar { param($R, $E) $E.R = $R })
        Wait-UTTestJob
        $got.R.Ok | Should -BeFalse
        $got.R.Erro | Should -Be 'Mensagem amigável de teste.'
    }

    It 'o log escrito no pool chega à fila da tela' {
        [void](Invoke-UTUiJob -Nome 'log' -Script { Write-UTLog -Level Sucesso -Message 'vindo do pool' })
        Wait-UTTestJob
        Receive-UTUiLog
        @($ui.LogLinhas | Where-Object { $_.Contains('[Sucesso] vindo do pool') }).Count | Should -Be 1
    }
}
