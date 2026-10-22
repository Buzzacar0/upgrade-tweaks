BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-UTOverlayNative
    # Header and lines exactly as PresentMon 2.6.0 writes them (captured on a real PC).
    $script:Header26 = 'Application,ProcessID,SwapChainAddress,PresentRuntime,SyncInterval,PresentFlags,AllowsTearing,PresentMode,TimeInMs,MsBetweenSimulationStart,MsBetweenPresents,MsBetweenDisplayChange,MsInPresentAPI,MsRenderPresentLatency,MsUntilDisplayed,CPUStartTimeInMs,MsBetweenAppStart,MsCPUBusy,MsCPUWait,MsGPULatency,MsGPUTime,MsGPUBusy,MsGPUWait,MsAnimationError,AnimationTime,MsFlipDelay,MsAllInputToPhotonLatency,MsClickToPhotonLatency'
    function New-Line26 {
        param([string]$App = 'cod.exe', [int]$ProcId = 4242, [double]$Ms = 6.25, [string]$Mode = 'Hardware: Independent Flip', [string]$Display = '6.2500', [double]$Time = 1000)
        $ci = [Globalization.CultureInfo]::InvariantCulture
        "$App,$ProcId,0x1C498191EA0,DXGI,0,0,1,$Mode,$($Time.ToString($ci)),NA,$($Ms.ToString($ci)),$Display,0.1693,0.3415,2.5092,190.7956,$($Ms.ToString($ci)),4.1500,0.1693,0.2188,3.2727,3.1871,0.0856,NA,190.7956,NA,NA,NA"
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'PresentMon: leitura do CSV' {
    It 'lê o cabeçalho do PresentMon 2.6 pelos nomes e cada quadro' {
        $p = New-Object UpgradeTweaks.Overlay.PresentMonParser
        $p.Parse('claude.exe,1,0x1,DXGI,0,0,0,Composed: Flip,1,NA,1,1,1,1,1,1,1,1,1,1,1,1,1,NA,1,NA,NA,NA') | Should -BeNullOrEmpty
        $p.Parse($script:Header26) | Should -BeNullOrEmpty
        $p.HasHeader | Should -BeTrue
        $s = $p.Parse('claude.exe,14916,0x1C498191EA0,DXGI,0,0,0,Composed: Flip,669.9456,NA,479.31170000000003,477.76810000000000,0.16930000000000,0.34150000000000,2.5092,190.7956,479.3193,479.1500,0.1693,479.2188,0.2727,0.1871,0.0856,NA,190.7956,NA,NA,NA')
        $s.Application | Should -Be 'claude.exe'
        $s.ProcessId | Should -Be 14916
        $s.PresentMode | Should -Be 'Composed: Flip'
        $s.FrameMs | Should -BeGreaterThan 479.31
        $s.DisplayMs | Should -BeGreaterThan 477.76
        $s.GpuBusyMs | Should -Be 0.1871
        $s.TimeMs | Should -Be 669.9456
    }

    It 'quadro não exibido (NA), linha quebrada e lixo não derrubam a leitura' {
        $p = New-Object UpgradeTweaks.Overlay.PresentMonParser
        [void]$p.Parse($script:Header26)
        [double]::IsNaN($p.Parse((New-Line26 -Display 'NA')).DisplayMs) | Should -BeTrue
        $p.Parse('cod.exe,1,0x1') | Should -BeNullOrEmpty
        $p.Parse((New-Line26 -Ms 0)) | Should -BeNullOrEmpty
        $p.Parse('') | Should -BeNullOrEmpty
        $p.Parse('error: falhou,x,y') | Should -BeNullOrEmpty
        $p.Parse((New-Line26 -Ms 16.667)).FrameMs | Should -Be 16.667
    }

    It 'aceita o formato 1.x (TimeInSeconds) e o nome FrameTime' {
        $p = New-Object UpgradeTweaks.Overlay.PresentMonParser
        [void]$p.Parse('Application,ProcessID,SwapChainAddress,Runtime,SyncInterval,PresentFlags,AllowsTearing,PresentMode,WasBatched,DwmNotified,Dropped,TimeInSeconds,MsInPresentAPI,MsBetweenPresents,MsBetweenDisplayChange')
        $s = $p.Parse('game.exe,10,0x1,DXGI,0,0,0,Hardware: Legacy Flip,0,0,0,1.5,0.1,8.33,8.33')
        $s.FrameMs | Should -Be 8.33
        $s.TimeMs | Should -Be 1500
        $q = New-Object UpgradeTweaks.Overlay.PresentMonParser
        [void]$q.Parse('Application,ProcessID,PresentMode,FrameTime')
        $q.Parse('x.exe,7,Composed: Flip,4.0').FrameMs | Should -Be 4
    }

    It 'separa os quadros por processo e calcula FPS, lows e o gráfico de cada um' {
        $s = New-Object UpgradeTweaks.Overlay.PresentMonSession
        $s.Feed($script:Header26)
        for ($i = 0; $i -lt 990; $i++) { $s.Feed((New-Line26 -Ms 4)) }
        for ($i = 0; $i -lt 10; $i++) { $s.Feed((New-Line26 -Ms 20)) }
        for ($i = 0; $i -lt 50; $i++) { $s.Feed((New-Line26 -App 'chrome.exe' -ProcId 77 -Ms 16.7)) }
        $st = $s.GetStats(4242, 1000, 30000, 2000)
        $st.Application | Should -Be 'cod.exe'
        $st.Frames | Should -Be 1000
        $st.PresentMode | Should -Be 'Hardware: Independent Flip'
        [math]::Round($st.Low1, 3) | Should -Be 50
        [math]::Round($st.Low01, 3) | Should -Be 50
        $st.SecondsSinceLastFrame | Should -BeLessThan 5
        $st.Graph.Count | Should -BeGreaterThan 10
        $s.GetStats(77, 1000, 30000, 2000).Frames | Should -Be 50
        $s.GetStats(999, 1000, 30000, 2000).Frames | Should -Be 0
        $s.Lines | Should -Be 1051
    }
}

Describe 'PresentMon: FPS, 1% low e 0,1% low' {
    It 'FPS médio = quadros / tempo' {
        [UpgradeTweaks.Overlay.FrameMath]::AverageFps([double[]]@(10, 10, 10, 10)) | Should -Be 100
        [UpgradeTweaks.Overlay.FrameMath]::AverageFps([double[]]@(5, 15)) | Should -Be 100
        [double]::IsNaN([UpgradeTweaks.Overlay.FrameMath]::AverageFps([double[]]@())) | Should -BeTrue
    }

    It '1% low é a média de FPS do 1% de quadros mais lentos' {
        $f = [double[]](@(5) * 1980 + @(10) * 10 + @(20) * 10)
        # k = 20 slowest frames: ten of 10 ms and ten of 20 ms -> 15 ms -> 66,67 FPS.
        [math]::Round([UpgradeTweaks.Overlay.FrameMath]::LowAverageFps($f, 0.01), 2) | Should -Be 66.67
        # 0,1% of 2000 = 2 frames, both 20 ms -> 50 FPS.
        [UpgradeTweaks.Overlay.FrameMath]::LowAverageFps($f, 0.001) | Should -Be 50
    }

    It 'com poucos quadros usa pelo menos o quadro mais lento; ordem não importa' {
        [UpgradeTweaks.Overlay.FrameMath]::LowAverageFps([double[]]@(8, 4, 25, 4), 0.01) | Should -Be 40
        $a = [double[]](1..500 | ForEach-Object { 4 + ($_ % 7) })
        $b = [double[]]($a | Sort-Object -Descending)
        [UpgradeTweaks.Overlay.FrameMath]::LowAverageFps($a, 0.01) | Should -Be ([UpgradeTweaks.Overlay.FrameMath]::LowAverageFps($b, 0.01))
    }

    It 'percentil (P1 do benchmark) e redução do gráfico mantendo os picos' {
        $f = [double[]](1..100 | ForEach-Object { $_ })
        [UpgradeTweaks.Overlay.FrameMath]::Percentile($f, 0.99) | Should -Be 99
        [UpgradeTweaks.Overlay.FrameMath]::PercentileFps($f, 0.01) | Should -Be (1000 / 99)
        $g = [double[]](@(4) * 1000)
        $g[637] = 50
        $d = [UpgradeTweaks.Overlay.FrameMath]::Downsample($g, 100)
        $d.Count | Should -Be 100
        ($d | Measure-Object -Maximum).Maximum | Should -Be 50
    }

    It 'a janela de tempo pega só os últimos segundos de jogo' {
        $r = New-Object UpgradeTweaks.Overlay.FrameRing 100
        foreach ($ms in @(100) * 10 + @(10) * 50) { $r.Add($ms) }
        $r.Window(500).Count | Should -Be 50
        $r.Window(600).Count | Should -Be 51
        foreach ($i in 1..200) { $r.Add(1) }
        $r.Count | Should -Be 100
        $r.Last(3) | Should -Be @(1, 1, 1)
    }
}

Describe 'Overlay: configuração e lógica' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'padrão com três perfis e os jogos de Call of Duty no Competitivo; salva e lê de volta' {
        $c = Get-UTOverlayConfig
        @($c.Perfis.Keys) | Should -Be @('Padrão', 'Competitivo', 'Completo')
        $c.Jogos['cod.exe'] | Should -Be 'Competitivo'
        $c.Atalhos.Mostrar | Should -Be 'Ctrl+Shift+F10'
        $c.Perfis['Padrão'].Posicao = 'InferiorDireita'
        $c.Rtss = $true
        [void](Save-UTOverlayConfig -Config $c -Confirm:$false)
        Test-Path (Join-Path (Get-UTPath -Name Usuario) 'overlay.json') | Should -BeTrue
        $r = Get-UTOverlayConfig
        $r.Perfis['Padrão'].Posicao | Should -Be 'InferiorDireita'
        $r.Rtss | Should -BeTrue
    }

    It 'valida tudo: faixa dos números, cores, itens, nomes de .exe e perfis inexistentes' {
        $c = ConvertTo-UTOverlayConfig -Config @{
            PerfilAtual = 'Nada'
            Perfis = @{ 'A' = @{ Escala = 9; Opacidade = 0; Posicao = 'Lua'; CorDestaque = 'roxo'; Itens = @('fps', 'xyz', 'fps', 'gpu'); Monitor = '\\.\DISPLAY2'; Margem = '12,5' } }
            Jogos = @{ 'Jogo.EXE' = 'Nada'; 'c:\x\y.exe' = 'A'; 'semexe' = 'A' }
            Atalhos = @{ Mostrar = 'Ctrl+Shift+F10'; ProximoPerfil = 'Q'; Benchmark = '' }
            IntervaloMs = 5; JanelaLowsSegundos = 999
        }
        $c.PerfilAtual | Should -Be 'A'
        $a = $c.Perfis['A']
        $a.Escala | Should -Be 2.5
        $a.Opacidade | Should -Be 0.2
        $a.Posicao | Should -Be 'SuperiorEsquerda'
        $a.CorDestaque | Should -Be '#A78BFA'
        $a.Itens | Should -Be @('fps', 'gpu')
        $a.Monitor | Should -Be '\\.\DISPLAY2'
        $a.Margem | Should -Be 12
        @($c.Jogos.Keys) | Should -Be @('jogo.exe')
        $c.Jogos['jogo.exe'] | Should -Be 'A'
        $c.Atalhos.ProximoPerfil | Should -Be 'Ctrl+Shift+F11'
        $c.Atalhos.Benchmark | Should -Be ''
        $c.IntervaloMs | Should -Be 100
        $c.JanelaLowsSegundos | Should -Be 120
        (ConvertTo-UTOverlayConfig -Config @{ Perfis = @{} }).Perfis.Count | Should -Be 3
    }

    It 'perfil automático pelo jogo em primeiro plano' {
        $c = Get-UTOverlayConfig
        Resolve-UTOverlayProfile -Config $c -Processo 'cod.exe' | Should -Be 'Competitivo'
        Resolve-UTOverlayProfile -Config $c -Processo 'COD' | Should -Be 'Competitivo'
        Resolve-UTOverlayProfile -Config $c -Processo 'notepad.exe' | Should -Be 'Padrão'
        Resolve-UTOverlayProfile -Config $c -Processo '' | Should -Be 'Padrão'
    }

    It 'posição nos 8 lugares, com a margem na escala do monitor' {
        $area = [pscustomobject]@{ Left = 0; Top = 0; Right = 2560; Bottom = 1440 }
        $p = Get-UTOverlayPosition -Area $area -Largura 200 -Altura 100 -Posicao SuperiorEsquerda -Margem 16 -Dpi 96
        "$($p.X),$($p.Y)" | Should -Be '16,16'
        $p = Get-UTOverlayPosition -Area $area -Largura 200 -Altura 100 -Posicao InferiorDireita -Margem 16 -Dpi 144
        "$($p.X),$($p.Y)" | Should -Be '2336,1316'
        $p = Get-UTOverlayPosition -Area $area -Largura 200 -Altura 100 -Posicao SuperiorCentro -Margem 16
        "$($p.X),$($p.Y)" | Should -Be '1180,16'
        $second = [pscustomobject]@{ Left = 2560; Top = -200; Right = 4480; Bottom = 880 }
        $p = Get-UTOverlayPosition -Area $second -Largura 100 -Altura 50 -Posicao MeioEsquerda -Margem 10
        "$($p.X),$($p.Y)" | Should -Be '2570,315'
    }

    It 'atalhos: modificadores e tecla do RegisterHotKey; inválidos viram nulo' {
        $h = ConvertTo-UTHotkey -Texto 'Ctrl+Shift+F10'
        $h.Modificadores | Should -Be (0x2 -bor 0x4 -bor 0x4000)
        $h.Tecla | Should -Be 0x79
        (ConvertTo-UTHotkey -Texto 'alt+O').Tecla | Should -Be ([int][char]'O')
        (ConvertTo-UTHotkey -Texto 'F13').Tecla | Should -Be 0x7C
        ConvertTo-UTHotkey -Texto 'F10' | Should -BeNullOrEmpty
        ConvertTo-UTHotkey -Texto 'Ctrl+Shift' | Should -BeNullOrEmpty
        ConvertTo-UTHotkey -Texto 'Ctrl+Banana' | Should -BeNullOrEmpty
        ConvertTo-UTHotkey -Texto '' | Should -BeNullOrEmpty
    }

    It 'linhas do overlay e texto do RTSS na ordem do perfil' {
        $p = New-UTOverlayProfile -Valores @{ Itens = @('fps', 'lows', 'grafico', 'frametime', 'cpu', 'gpu', 'vram', 'modo') }
        $q = [pscustomobject]@{ Fps = 164.6; Low1 = 101.2; Low01 = 70.4; FrameMs = 6.08; PresentMode = 'Hardware: Independent Flip' }
        $l = @(Get-UTOverlayLine -Perfil $p -Quadros $q -Sensores @{ CpuTemp = 61.4; CpuUso = 38; GpuTemp = $null; GpuUso = 97; Vram = 7340 })
        ($l | ForEach-Object Item) | Should -Be @('fps', 'lows', 'grafico', 'frametime', 'cpu', 'gpu', 'vram', 'modo')
        ($l | Where-Object Item -eq 'fps').Valor | Should -Be '165'
        ($l | Where-Object Item -eq 'lows').Valor | Should -Be '101 / 70'
        ($l | Where-Object Item -eq 'frametime').Valor | Should -Be '6,1 ms'
        ($l | Where-Object Item -eq 'cpu').Valor | Should -Be '61 °C  38 %'
        ($l | Where-Object Item -eq 'gpu').Valor | Should -Be '97 %'
        ($l | Where-Object Item -eq 'vram').Valor | Should -Be '7,2 GB'
        ($l | Where-Object Item -eq 'modo').Valor | Should -Be 'Independent Flip'
        Format-UTOverlayRtssText -Linhas $l | Should -Be ("FPS 165`n1% / 0,1% 101 / 70`nFrametime 6,1 ms`nCPU 61 °C  38 %`nGPU 97 %`nVRAM 7,2 GB`nModo Independent Flip")
        (@(Get-UTOverlayLine -Perfil $p -Quadros $null) | Where-Object Item -eq 'fps').Valor | Should -Be '-'
    }

    It 'sensores do overlay: CPU principal e a GPU dedicada (a de mais VRAM)' {
        $row = { param($hw, $tipo, $hwNome, $tipoS, $nome, $v) [pscustomobject]@{ Id = "/$hwNome/$tipoS/$nome"; HardwareTipo = $hw; HardwareNome = $hwNome; TipoOriginal = $tipoS; NomeOriginal = $nome; Valor = $v } }
        $rows = @(
            (& $row 'Cpu' 0 'Ryzen' 'Temperature' 'Core (Tctl/Tdie)' 50)
            (& $row 'Cpu' 0 'Ryzen' 'Load' 'CPU Total' 10)
            (& $row 'GpuAmd' 0 'Radeon iGPU' 'SmallData' 'GPU Memory Total' 512)
            (& $row 'GpuAmd' 0 'Radeon iGPU' 'Load' 'GPU Core' 0)
            (& $row 'GpuNvidia' 0 'RTX 5070' 'SmallData' 'GPU Memory Total' 12227)
            (& $row 'GpuNvidia' 0 'RTX 5070' 'Temperature' 'GPU Core' 49)
            (& $row 'GpuNvidia' 0 'RTX 5070' 'Load' 'GPU Core' 3)
            (& $row 'GpuNvidia' 0 'RTX 5070' 'SmallData' 'GPU Memory Used' 1304)
            (& $row 'Memory' 0 'Total Memory' 'Data' 'Memory Used' 6.5)
        )
        $ids = Find-UTOverlaySensor -Linhas $rows
        $ids.CpuTemp | Should -Be '/Ryzen/Temperature/Core (Tctl/Tdie)'
        $ids.GpuUso | Should -Be '/RTX 5070/Load/GPU Core'
        $ids.Vram | Should -Be '/RTX 5070/SmallData/GPU Memory Used'
        $ids.Ram | Should -Be '/Total Memory/Data/Memory Used'
    }

    It 'PresentMon: captura sem o dwm, por stdout; só fica se for assinado pela Intel' {
        Get-UTPresentMonArgument | Should -Match '--output_stdout'
        Get-UTPresentMonArgument | Should -Match '--exclude dwm\.exe'
        Get-UTPresentMonArgument -ProcessoId 99 | Should -Match '--process_id 99$'
        Mock Assert-UTAdmin { }
        Mock Get-UTGitHubLatestRelease { [pscustomobject]@{ Versao = '2.6.0'; Arquivos = @([pscustomobject]@{ Nome = 'PresentMon-2.6.0.msi'; Url = 'x' }, [pscustomobject]@{ Nome = 'PresentMon-2.6.0-x64.exe'; Url = 'https://y/PresentMon-2.6.0-x64.exe' }) } }
        # Like the real one: creates the folder (a clean CI machine has no %TEMP%\UpgradeTweaks).
        Mock Save-UTDownload { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destino) | Out-Null; Set-Content -LiteralPath $Destino -Value 'x' }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
        { Install-UTPresentMon -Confirm:$false } | Should -Throw '*assinatura digital da Intel*'
        Test-UTPresentMon | Should -BeFalse
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Intel Corporation, O=Intel Corporation, C=US' } } }
        Install-UTPresentMon -Confirm:$false | Should -Be (Get-UTPresentMonPath)
        Test-UTPresentMon | Should -BeTrue
        Should -Invoke Save-UTDownload -ParameterFilter { $Url -like '*x64.exe' }
    }

    It 'ligar abre um processo escondido com -Overlay; abrir com o Windows cria a tarefa do usuário' {
        Mock Test-UTOverlayRunning { $false }
        Mock Test-UTPresentMon { $true }
        Mock Get-UTAppScriptPath { 'C:\UT\app\upgradetweaks.ps1' }
        Mock Start-Process { }
        Start-UTOverlay -Confirm:$false | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $ArgumentList -like '*-STA*-File "C:\UT\app\upgradetweaks.ps1" -Overlay' -and $WindowStyle -eq 'Hidden' }
        Mock Test-UTPresentMon { $false }
        { Start-UTOverlay -Confirm:$false } | Should -Throw '*PresentMon*'
        Mock Assert-UTAdmin { }
        Mock Register-UTTaskDefinition { }
        Mock New-ScheduledTaskTrigger { 'gatilho' }
        Mock New-ScheduledTaskPrincipal { 'principal' }
        Mock New-ScheduledTaskAction { 'acao' }
        Mock New-ScheduledTaskSettingsSet { 'cfg' }
        Register-UTOverlayStartup -Confirm:$false
        Should -Invoke New-ScheduledTaskTrigger -ParameterFilter { $AtLogOn }
        Should -Invoke New-ScheduledTaskPrincipal -ParameterFilter { $RunLevel -eq 'Highest' }
        Should -Invoke Register-UTTaskDefinition -ParameterFilter { $Nome -eq 'UpgradeTweaks Overlay' -and $Gatilho -eq 'gatilho' }
    }

    It 'o Modo Partida liga o overlay quando pedido e desliga no fim' {
        Mock Assert-UTAdmin { }
        Mock Get-UTMatchModeList { @() }
        Mock Get-UTActivePowerScheme { [pscustomobject]@{ Guid = 'g' } }
        Mock Find-UTMaxPerformanceScheme { 'm' }
        Mock Invoke-UTPowerCfg { }
        Mock Test-UTPowerScheme { $true }
        Mock Test-UTPresentMon { $true }
        Mock Test-UTOverlayRunning { $false }
        Mock Start-UTOverlay { $true }
        Mock Stop-UTOverlay { }
        [void](Start-UTMatchMode -Contexto ([pscustomobject]@{ X3D = $null; Launchers = @() }) -Confirm:$false)
        Should -Invoke Start-UTOverlay -Times 1
        Stop-UTMatchMode -Confirm:$false
        Should -Invoke Stop-UTOverlay -Times 1
        $c = Get-UTOverlayConfig; $c.ModoPartida = $false; [void](Save-UTOverlayConfig -Config $c -Confirm:$false)
        [void](Start-UTMatchMode -Contexto ([pscustomobject]@{ X3D = $null; Launchers = @() }) -Confirm:$false)
        Should -Invoke Start-UTOverlay -Times 1 -Exactly
        Stop-UTMatchMode -Confirm:$false
        Should -Invoke Stop-UTOverlay -Times 1 -Exactly
    }
}

Describe 'Overlay: visual e aba' {
    BeforeAll { Import-UTUiAssembly }
    BeforeEach {
        Reset-UTTestEnvironment
        $ui = Initialize-UTUiState
        $w = Get-UTUiWindow -Name 'MainWindow'
        $ui.Window = $w.Window
        $ui.C = $w.Controles
    }
    AfterEach { $e = (Get-UTUi).OverlayEditor; if ($e -and $e.Timer) { $e.Timer.Stop() } }

    It 'o visual tem um texto por item e o gráfico com os frametimes' {
        $p = New-UTOverlayProfile -Valores @{ Itens = @('fps', 'grafico', 'lows'); Escala = 1.5 }
        $v = New-UTOverlayVisual -Perfil $p
        @($v.Valores.Keys | Sort-Object) | Should -Be @('fps', 'lows')
        $v.Raiz.LayoutTransform.ScaleX | Should -Be 1.5
        $q = [pscustomobject]@{ Fps = 144; Low1 = 90; Low01 = 60; FrameMs = 6.9; PresentMode = ''; Graph = [double[]](@(6.9) * 300 + @(25)) }
        Update-UTOverlayVisual -Visual $v -Linhas @(Get-UTOverlayLine -Perfil $p -Quadros $q) -Quadros $q
        $v.Valores['fps'].Text | Should -Be '144'
        $v.Grafico.Points.Count | Should -BeGreaterThan 50
        # The stutter (25 ms) is far above the 6,9 ms frames (Y grows downwards).
        $ys = @($v.Grafico.Points | ForEach-Object Y)
        ($ys | Measure-Object -Minimum).Minimum | Should -BeLessThan (($ys | Measure-Object -Maximum).Maximum - 15)
    }

    It 'a aba monta sem o PresentMon, com prévia, perfis e jogos; mudanças vão para o overlay.json' {
        Mock Test-UTOverlayStartup { $false }
        Mock Test-UTOverlayRunning { $false }
        $page = New-UTUiPageOverlay
        $page | Should -Not -BeNullOrEmpty
        $e = (Get-UTUi).OverlayEditor
        $e.Previa | Should -Not -BeNullOrEmpty
        $e.Previa.Valores['fps'].Text | Should -Not -Be '-'
        Set-UTUiOverlayValue -Chave 'Posicao' -Valor 'InferiorDireita'
        Save-UTUiOverlayConfig -Agora
        (Get-UTOverlayConfig).Perfis['Padrão'].Posicao | Should -Be 'InferiorDireita'
        Move-UTUiOverlayItem -Item 'gpu' -Direcao -10
        $e.Config.Perfis['Padrão'].Itens[0] | Should -Be 'gpu'
    }
}
