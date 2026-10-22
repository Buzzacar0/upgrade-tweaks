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

    It 'tem as cores da Upgrade Store' {
        $ui = Initialize-TestWindow
        $ui.Window.FindResource('BgBrush').Color.ToString() | Should -Be '#FF0B0F1E'
        $ui.Window.FindResource('CardBrush').Color.ToString() | Should -Be '#FF141A33'
        $ui.Window.FindResource('AccentBrush').Color.ToString() | Should -Be '#FF7C3AED'
        $ui.Window.FindResource('AccentLightBrush').Color.ToString() | Should -Be '#FFA78BFA'
    }
}

Describe 'Abas' {
    It 'segue a ordem pedida (com Latência como aba avançada)' {
        (Get-UTUiTabDefinition).Nome | Should -Be @('Início', 'Monitor', 'Energia', 'Gaming', 'Latência', 'Rede', 'Serviços e Apps', 'Privacidade', 'GPU', 'Warzone', 'Ferramentas', 'BIOS', 'Programas', 'Personalizar', 'Restaurar', 'Sobre')
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
        $list | Should -BeOfType System.Windows.Controls.Border
    }

    It 'marcar atualiza as caixas e o contador; "Não se aplica" desmarca e bloqueia' {
        Set-UTUiSelection -Id $ids[0], $ids[1] -Marcado $true
        $ui.C['SelectionText'].Text | Should -Be '2 ajustes marcados'
        @($ui.Rows | Where-Object { $_.Id -eq $ids[0] })[0].Check.IsChecked | Should -BeTrue
        Sync-UTUiTweakState -Estados @([pscustomobject]@{ Id = $ids[0]; Estado = 'Incompativel'; Motivo = 'Só para notebook' }, [pscustomobject]@{ Id = $ids[1]; Estado = 'Aplicado'; Motivo = $null })
        $row0 = @($ui.Rows | Where-Object { $_.Id -eq $ids[0] })[0]
        $row0.Check.IsEnabled | Should -BeFalse
        $row0.EstadoTexto.Text | Should -Be 'Não se aplica'
        $ui.Selecionados.Contains($ids[0]) | Should -BeFalse
        @($ui.Rows | Where-Object { $_.Id -eq $ids[1] })[0].EstadoTexto.Text | Should -Be 'Aplicado'
        $ui.C['SelectionText'].Text | Should -Be '1 ajuste marcado'
        Set-UTUiSelection -Id $ids[0] -Marcado $true
        $ui.Selecionados.Contains($ids[0]) | Should -BeFalse
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

    It 'sem nada marcado só avisa' {
        Mock Show-UTUiDialog { 'OK' }
        Invoke-UTUiRun -Modo Aplicar
        $script:jobs.Count | Should -Be 0
        Should -Invoke Show-UTUiDialog -Times 1 -ParameterFilter { $Titulo -eq 'Nenhum ajuste marcado' }
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

    It 'cancelar não faz nada' {
        Set-UTUiSelection -Id $low -Marcado $true
        Mock Show-UTUiDialog { 'Cancelar' }
        Invoke-UTUiRun -Modo Aplicar
        Invoke-UTUiRun -Modo Desfazer
        $script:jobs.Count | Should -Be 0
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
