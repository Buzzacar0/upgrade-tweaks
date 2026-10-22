BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-UTOverlayNative
    $script:Header26 = 'Application,ProcessID,SwapChainAddress,PresentRuntime,SyncInterval,PresentFlags,AllowsTearing,PresentMode,TimeInMs,MsBetweenSimulationStart,MsBetweenPresents,MsBetweenDisplayChange,MsInPresentAPI,MsRenderPresentLatency,MsUntilDisplayed,CPUStartTimeInMs,MsBetweenAppStart,MsCPUBusy,MsCPUWait,MsGPULatency,MsGPUTime,MsGPUBusy,MsGPUWait,MsAnimationError,AnimationTime,MsFlipDelay,MsAllInputToPhotonLatency,MsClickToPhotonLatency'
    function New-Line {
        param([string]$App, [int]$ProcId, [double]$Ms)
        $ms2 = $Ms.ToString([Globalization.CultureInfo]::InvariantCulture)
        "$App,$ProcId,0x1,DXGI,0,0,1,Hardware: Independent Flip,1000,NA,$ms2,$ms2,0.1,0.3,2.5,190,$ms2,4.1,0.1,0.2,3.2,3.1,0.08,NA,190,NA,NA,NA"
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Benchmark: resumo' {
    It 'FPS médio, lows, percentis, mínimo, máximo e engasgos' {
        $f = [double[]](@(5) * 1980 + @(10) * 10 + @(20) * 10)
        $s = Get-UTBenchmarkSummary -Frametimes $f
        $s.Quadros | Should -Be 2000
        $s.DuracaoS | Should -Be 10.2
        [math]::Round($s.FpsMedio, 2) | Should -Be 196.08
        [math]::Round($s.Low1, 2) | Should -Be 66.67
        $s.Low01 | Should -Be 50
        $s.P1 | Should -Be 200
        $s.P01 | Should -Be 50
        $s.FpsMinimo | Should -Be 50
        $s.FpsMaximo | Should -Be 200
        $s.FrametimeMaximo | Should -Be 20
        $s.Engasgos | Should -Be 10
    }

    It 'gravação vazia não quebra' {
        $s = Get-UTBenchmarkSummary -Frametimes ([double[]]@())
        $s.Quadros | Should -Be 0
        $s.FpsMedio | Should -BeNullOrEmpty
    }
}

Describe 'Benchmark: gravações, CSV e comparação' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'salva em %AppData% (pasta do usuário), lista, renomeia e exclui' {
        $r = Save-UTBenchmarkRun -Jogo 'cod.exe' -Frametimes ([double[]](@(6.25) * 600)) -Inicio ([datetime]'2026-10-22 21:30:00') -Confirm:$false
        $r.Id | Should -Be '20261022-213000_cod'
        (Get-UTBenchmarkFolder) | Should -BeLike "$(Get-UTPath -Name Usuario)*benchmarks"
        [void](Save-UTBenchmarkRun -Jogo 'cod.exe' -Frametimes ([double[]](@(5) * 600)) -Inicio ([datetime]'2026-10-22 22:00:00') -Confirm:$false)
        $all = @(Get-UTBenchmarkRun)
        $all.Count | Should -Be 2
        $all[0].Id | Should -Be '20261022-220000_cod'
        $all[1].Resumo.FpsMedio | Should -Be 160
        @($all[1].Frametimes).Count | Should -Be 600
        Rename-UTBenchmarkRun -Id '20261022-213000_cod' -Nome 'Antes do ajuste' -Confirm:$false
        (Get-UTBenchmarkRun -Id '20261022-213000_cod').Nome | Should -Be 'Antes do ajuste'
        Set-Content -LiteralPath (Join-Path (Get-UTBenchmarkFolder) 'quebrado.json') -Value '{ nada'
        @(Get-UTBenchmarkRun).Count | Should -Be 2
        Remove-UTBenchmarkRun -Id '20261022-213000_cod' -Confirm:$false
        @(Get-UTBenchmarkRun).Count | Should -Be 1
    }

    It 'CSV com o resumo no topo e uma linha por quadro, para o Excel' {
        $r = Save-UTBenchmarkRun -Jogo 'cod.exe' -Frametimes ([double[]]@(5, 10, 5, 4)) -Inicio ([datetime]'2026-10-22 21:30:00') -Confirm:$false
        $file = Join-Path $TestDrive 'b.csv'
        [void](Export-UTBenchmarkCsv -Run (Get-UTBenchmarkRun -Id $r.Id) -Path $file -Confirm:$false)
        $lines = Get-Content -LiteralPath $file -Encoding UTF8
        $lines[0] | Should -Be 'Benchmark;cod.exe 22/10 21:30'
        $lines | Should -Contain 'Quadros;4'
        $lines | Should -Contain 'FPS médio;166,7'
        $i = [array]::IndexOf($lines, 'Quadro;Tempo (s);Frametime (ms);FPS')
        $i | Should -BeGreaterThan 5
        $lines[$i + 2] | Should -Be '2;0,0150;10,000;100,0'
        $lines.Count | Should -Be ($i + 5)
    }

    It 'compara B com A: diferença em % e quem é melhor em cada métrica' {
        $a = [pscustomobject]@{ Resumo = Get-UTBenchmarkSummary -Frametimes ([double[]](@(10) * 990 + @(25) * 10)) }
        $b = [pscustomobject]@{ Resumo = Get-UTBenchmarkSummary -Frametimes ([double[]](@(8) * 995 + @(16) * 5)) }
        $c = @(Compare-UTBenchmarkRun -A $a -B $b)
        $avg = $c | Where-Object Chave -eq 'FpsMedio'
        $avg.Melhor | Should -Be 'B'
        # A: 98,52 FPS; B: 124,38 FPS -> +26,24%.
        [math]::Round($avg.DiferencaPct, 2) | Should -Be 26.24
        ($c | Where-Object Chave -eq 'FrametimeMaximo').Melhor | Should -Be 'B'
        ($c | Where-Object Chave -eq 'Engasgos').Melhor | Should -Be 'B'
        $same = @(Compare-UTBenchmarkRun -A $a -B $a)
        @($same | Where-Object Melhor -ne '=').Count | Should -Be 0
    }

    It 'grava só o processo escolhido (o que mais desenha) entre começar e parar' {
        $s = New-Object UpgradeTweaks.Overlay.PresentMonSession
        $s.Feed($script:Header26)
        for ($i = 0; $i -lt 100; $i++) { $s.Feed((New-Line 'cod.exe' 500 6.0)); if ($i % 10 -eq 0) { $s.Feed((New-Line 'chrome.exe' 600 16.7)) } }
        $p = Start-UTBenchmarkRecording -Sessao $s -Confirm:$false
        $p | Should -Be 500
        $s.IsRecording | Should -BeTrue
        for ($i = 0; $i -lt 300; $i++) { $s.Feed((New-Line 'cod.exe' 500 5.0)); $s.Feed((New-Line 'chrome.exe' 600 16.7)) }
        $s.RecordedFrames | Should -Be 300
        $run = Stop-UTBenchmarkRecording -Sessao $s -Inicio ([datetime]'2026-10-22 23:00:00') -Confirm:$false
        $s.IsRecording | Should -BeFalse
        $run.Jogo | Should -Be 'cod.exe'
        $run.Resumo.Quadros | Should -Be 300
        $run.Resumo.FpsMedio | Should -Be 200
        $s.StartRecording(500)
        $s.Feed((New-Line 'cod.exe' 500 5.0))
        Stop-UTBenchmarkRecording -Sessao $s -Confirm:$false | Should -BeNullOrEmpty
        $empty = New-Object UpgradeTweaks.Overlay.PresentMonSession
        Start-UTBenchmarkRecording -Sessao $empty -Confirm:$false | Should -Be 0
    }
}

Describe 'Benchmark: aba' {
    BeforeAll { Import-UTUiAssembly }
    BeforeEach {
        Reset-UTTestEnvironment
        $ui = Initialize-UTUiState
        $w = Get-UTUiWindow -Name 'MainWindow'
        $ui.Window = $w.Window
        $ui.C = $w.Controles
    }

    It 'lista as gravações, mostra uma com gráfico e compara duas' {
        [void](Save-UTBenchmarkRun -Jogo 'cod.exe' -Nome 'Antes' -Frametimes ([double[]](@(7) * 900 + @(30) * 3)) -Inicio ([datetime]'2026-10-22 20:00:00') -Confirm:$false)
        [void](Save-UTBenchmarkRun -Jogo 'cod.exe' -Nome 'Depois' -Frametimes ([double[]](@(6) * 1000)) -Inicio ([datetime]'2026-10-22 21:00:00') -Confirm:$false)
        $page = New-UTUiPageBenchmark
        $page | Should -Not -BeNullOrEmpty
        $b = $ui.Benchmark
        $b.Lista.Content | Should -Not -BeNullOrEmpty
        Show-UTUiBenchmarkDetail -Id '20261022-200000_cod'
        $b.Detalhe.Content | Should -Not -BeNullOrEmpty
        $b.Selecionados.Add('20261022-200000_cod'); $b.Selecionados.Add('20261022-210000_cod')
        Show-UTUiBenchmarkComparison
        $b.Detalhe.Content.Children[0].Text | Should -Be 'Comparação (B é a gravação mais nova)'
    }

    It 'sem PresentMon, gravar só avisa' {
        $null = New-UTUiPageBenchmark
        Mock Show-UTUiDialog { 'OK' }
        Switch-UTUiBenchmarkRecording
        Should -Invoke Show-UTUiDialog -Times 1 -ParameterFilter { $Titulo -eq 'Falta o PresentMon' }
        $ui.Benchmark.Fase | Should -Be ''
    }
}
