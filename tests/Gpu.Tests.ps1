BeforeDiscovery {
    $hasNvidia = Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\nvapi64.dll')
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null
            Executaveis = @('H:\HQ\cod.exe', 'H:\HQ\cod25\cod25-cod.exe'); PastasJogo = @('H:\HQ') }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }

    function New-FakeDrs {
        # In-memory stand-in for UpgradeTweaks.NvDrs (handles are [IntPtr]).
        $script:drs = @{
            next     = 3
            profiles = @{
                1 = @{ nome = 'Base Profile'; apps = @(); settings = @{}; defaults = @{} }
                2 = @{ nome = 'Call of Duty: Black Ops 7'; apps = @('cod25-cod.exe'); settings = @{ ([uint32]0x1057EB71) = @{ valor = [uint32]0; predef = $true } }; defaults = @{ ([uint32]0x1057EB71) = [uint32]0 } }
            }
            saved    = 0
        }
        $o = [pscustomobject]@{}
        $find = { param($pred) foreach ($k in @($script:drs.profiles.Keys)) { if (& $pred $script:drs.profiles[$k]) { return [IntPtr][int64]$k } }; return [IntPtr]::Zero }
        $o | Add-Member ScriptMethod BaseProfile { [IntPtr]1 }
        $o | Add-Member ScriptMethod FindProfile { $n = $args[0]; foreach ($k in @($script:drs.profiles.Keys)) { if ($script:drs.profiles[$k].nome -eq $n) { return [IntPtr][int64]$k } }; [IntPtr]::Zero }
        $o | Add-Member ScriptMethod FindProfileByApp { $e = $args[0]; foreach ($k in @($script:drs.profiles.Keys)) { if ($script:drs.profiles[$k].apps -contains $e) { return [IntPtr][int64]$k } }; [IntPtr]::Zero }
        $o | Add-Member ScriptMethod ProfileName { $script:drs.profiles[[int]$args[0].ToInt64()].nome }
        $o | Add-Member ScriptMethod CreateProfile { $h = $script:drs.next; $script:drs.next++; $script:drs.profiles[$h] = @{ nome = $args[0]; apps = @(); settings = @{}; defaults = @{} }; [IntPtr][int64]$h }
        $o | Add-Member ScriptMethod AddApplication { $p = $script:drs.profiles[[int]$args[0].ToInt64()]; $p.apps = @($p.apps + $args[1]) }
        $o | Add-Member ScriptMethod DeleteProfile { $script:drs.profiles.Remove([int]$args[0].ToInt64()) }
        $o | Add-Member ScriptMethod RestoreProfileDefault { $p = $script:drs.profiles[[int]$args[0].ToInt64()]; $p.settings = @{}; foreach ($k in $p.defaults.Keys) { $p.settings[$k] = @{ valor = $p.defaults[$k]; predef = $true } } }
        $o | Add-Member ScriptMethod GetSetting {
            $p = $script:drs.profiles[[int]$args[0].ToInt64()]; $s = $p.settings[[uint32]$args[1]]
            if ($null -eq $s) { return [pscustomobject]@{ Existe = $false; Valor = [uint32]0; Predefinido = $false } }
            [pscustomobject]@{ Existe = $true; Valor = [uint32]$s.valor; Predefinido = [bool]$s.predef }
        }
        $o | Add-Member ScriptMethod SetDword { $p = $script:drs.profiles[[int]$args[0].ToInt64()]; $p.settings[[uint32]$args[1]] = @{ valor = [uint32]$args[2]; predef = $false } }
        $o | Add-Member ScriptMethod RestoreDefaultSetting { $p = $script:drs.profiles[[int]$args[0].ToInt64()]; $id = [uint32]$args[1]; if ($p.defaults.ContainsKey($id)) { $p.settings[$id] = @{ valor = $p.defaults[$id]; predef = $true } } else { $p.settings.Remove($id) }; 0 }
        $o | Add-Member ScriptMethod DeleteSetting { $p = $script:drs.profiles[[int]$args[0].ToInt64()]; $p.settings.Remove([uint32]$args[1]); 0 }
        $o | Add-Member ScriptMethod Save { $script:drs.saved++ }
        $o | Add-Member ScriptMethod SaveToFile { Set-Content -LiteralPath $args[0] -Value 'drs' }
        $o | Add-Member ScriptMethod LoadFromFile { $script:drs.loaded = $args[0] }
        $o | Add-Member ScriptMethod Dispose { }
        $null = $find
        return $o
    }

    function Get-Fake([int]$Handle, [uint32]$Id) { $s = $script:drs.profiles[$Handle].settings[$Id]; if ($s) { [uint32]$s.valor } else { $null } }

    function Use-GpuMocks {
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        Mock Test-UTNvApiAvailable { $true }
        Mock Open-UTNvDrsSession { New-FakeDrs-Shared }
        Mock Get-UTDisplayInfo { @([pscustomobject]@{ Dispositivo = '\\.\DISPLAY1'; Nome = 'GS27QA'; HzAtual = 165; HzMaximo = 165 }) }
    }
    # The same fake must survive across sessions opened by different functions.
    function New-FakeDrs-Shared { if (-not $script:fakeSession) { $script:fakeSession = New-FakeDrs }; $script:fakeSession }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Recomendações NVIDIA' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx }

    It 'sem G-SYNC: V-Sync desligado e sem limite de FPS' {
        $cfg = Get-UTConfig -Name 'nvidia-drs'
        $opts = [pscustomobject]@{ ComGsync = $false; HzMonitor = 165 }
        $vsync = $cfg.configuracoes | Where-Object { $_.chave -eq 'vsync' }
        (Resolve-UTNvidiaRecommendation -Item $vsync -Escopo perfil -Opcoes $opts).Valores[0] | Should -Be ([uint32]0x08416747)
        $fps = $cfg.configuracoes | Where-Object { $_.chave -eq 'limiteFps' }
        (Resolve-UTNvidiaRecommendation -Item $fps -Escopo perfil -Opcoes $opts).Valores[0] | Should -Be 0
        $gs = $cfg.configuracoes | Where-Object { $_.chave -eq 'gsync' }
        Resolve-UTNvidiaRecommendation -Item $gs -Escopo global -Opcoes $opts | Should -BeNullOrEmpty
    }

    It 'com G-SYNC em 165 Hz: V-Sync ligado no driver e limite de 162 FPS' {
        $cfg = Get-UTConfig -Name 'nvidia-drs'
        $opts = [pscustomobject]@{ ComGsync = $true; HzMonitor = 165 }
        (Resolve-UTNvidiaRecommendation -Item ($cfg.configuracoes | Where-Object { $_.chave -eq 'vsync' }) -Escopo perfil -Opcoes $opts).Valores[0] | Should -Be ([uint32]0x47814940)
        $r = Resolve-UTNvidiaRecommendation -Item ($cfg.configuracoes | Where-Object { $_.chave -eq 'limiteFps' }) -Escopo perfil -Opcoes $opts
        $r.Valores[0] | Should -Be 162
        $r.Rotulo | Should -Match '162 FPS'
    }

    It 'baixa latência: desligada no perfil (Reflex) e Ultra no global' {
        $cfg = Get-UTConfig -Name 'nvidia-drs'
        $item = $cfg.configuracoes | Where-Object { $_.chave -eq 'baixaLatencia' }
        $opts = [pscustomobject]@{ ComGsync = $false; HzMonitor = 60 }
        (Resolve-UTNvidiaRecommendation -Item $item -Escopo perfil -Opcoes $opts).Valores | Should -Be @(0, 0, 0)
        (Resolve-UTNvidiaRecommendation -Item $item -Escopo global -Opcoes $opts).Valores | Should -Be @(2, 1, 1)
    }

    It 'todas as opções do nvidia-drs.json são coerentes (um valor por id)' {
        foreach ($item in (Get-UTConfig -Name 'nvidia-drs').configuracoes) {
            if (-not $item.opcoes) { continue }
            foreach ($k in @($item.opcoes.Keys)) { @($item.opcoes[$k].valores).Count | Should -Be @($item.ids).Count -Because "$($item.chave).$k" }
            foreach ($e in 'perfil', 'global') {
                if ($item.recomendado -and $item.recomendado[$e] -and $item.recomendado[$e] -notlike 'regra:*') { $item.opcoes.Contains($item.recomendado[$e]) | Should -BeTrue -Because "$($item.chave) $e" }
            }
        }
    }
}

Describe 'Perfil NVIDIA do Call of Duty (driver simulado)' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx; $script:fakeSession = $null; Use-GpuMocks }

    It 'usa o perfil que a NVIDIA já tem para o jogo e mostra atual x recomendado' {
        $rows = @(Get-UTNvidiaDrsStatus -Escopo perfil)
        $energia = $rows | Where-Object Chave -eq 'energia'
        $energia.Perfil | Should -Be 'Call of Duty: Black Ops 7'
        $energia.Atual | Should -Be 'Ideal / Adaptável'
        $energia.Recomendado | Should -Be 'Preferir desempenho máximo'
        $energia.Igual | Should -BeFalse
        ($rows | Where-Object Chave -eq 'dsr').Aplicavel | Should -BeFalse
    }

    It 'aplica, detecta e o desfazer devolve o padrão da NVIDIA e apaga o resto' {
        (Invoke-UTTweak -Id 'UT_GPU_NvidiaPerfil').Status | Should -Be 'Aplicado'
        Get-Fake 2 0x1057EB71 | Should -Be 1
        Get-Fake 2 0x00A879CF | Should -Be ([uint32]0x08416747)
        Get-Fake 2 0x0005F543 | Should -Be 0
        $script:drs.saved | Should -BeGreaterThan 0
        @(Get-ChildItem (Get-UTPath -Name Backups) -Recurse -Filter 'drs-*.txt').Count | Should -Be 1
        (Get-UTTweakState -Id 'UT_GPU_NvidiaPerfil').Estado | Should -Be 'Aplicado'

        (Undo-UTTweak -Id 'UT_GPU_NvidiaPerfil').Status | Should -Be 'Desfeito'
        Get-Fake 2 0x1057EB71 | Should -Be 0
        $script:drs.profiles[2].settings[[uint32]0x1057EB71].predef | Should -BeTrue
        Get-Fake 2 0x00A879CF | Should -BeNullOrEmpty
        (Get-UTTweakState -Id 'UT_GPU_NvidiaPerfil').Estado | Should -Be 'NaoAplicado'
    }

    It 'sem perfil do jogo no driver, cria "Upgrade Tweaks - Warzone" e o desfazer apaga' {
        $null = New-FakeDrs-Shared
        $script:drs.profiles.Remove(2)
        (Invoke-UTTweak -Id 'UT_GPU_NvidiaPerfil').Status | Should -Be 'Aplicado'
        $created = @($script:drs.profiles.Values | Where-Object { $_.nome -eq 'Upgrade Tweaks - Warzone' })[0]
        $created.apps | Should -Be @('cod.exe', 'cod25-cod.exe')
        Undo-UTTweak -Id 'UT_GPU_NvidiaPerfil' | Out-Null
        @($script:drs.profiles.Values | Where-Object { $_.nome -eq 'Upgrade Tweaks - Warzone' }).Count | Should -Be 0
    }

    It 'global: cache de shaders ilimitado e baixa latência Ultra' {
        (Invoke-UTTweak -Id 'UT_GPU_NvidiaGlobal').Status | Should -Be 'Aplicado'
        Get-Fake 1 0x00AC8497 | Should -Be ([uint32]::MaxValue)
        Get-Fake 1 0x0005F543 | Should -Be 2
        Get-Fake 1 0x00CE2691 | Should -Be 20
    }

    It 'simular lista atual -> recomendado sem tocar no driver' {
        $r = Invoke-UTTweak -Id 'UT_GPU_NvidiaPerfil' -WhatIf
        $r.Status | Should -Be 'Simulado'
        $r.Acoes | Should -Contain 'Perfil do driver: Call of Duty: Black Ops 7'
        $r.Acoes | Should -Contain 'Modo de gerenciamento de energia: Ideal / Adaptável -> Preferir desempenho máximo'
        $script:drs.saved | Should -Be 0
    }

    It 'sem driver NVIDIA, falha com mensagem clara' {
        Mock Test-UTNvApiAvailable { $false }
        $r = Invoke-UTTweak -Id 'UT_GPU_NvidiaPerfil'
        $r.Status | Should -Be 'Falhou'
        $r.Mensagem | Should -Match 'Driver NVIDIA não encontrado'
    }

    It 'restaurar padrões NVIDIA faz backup e reseta o perfil' {
        $null = New-FakeDrs-Shared
        $script:fakeSession.SetDword([IntPtr]2, [uint32]0x00CE2691, [uint32]20)
        Restore-UTNvidiaDefault -Escopo perfil -Confirm:$false
        Get-Fake 2 0x00CE2691 | Should -BeNullOrEmpty
        Get-Fake 2 0x1057EB71 | Should -Be 0
    }
}

Describe 'Faixa dinâmica, taxa de atualização e power limit' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx; Use-GpuMocks }

    It 'faixa Limitada vira Completa e o desfazer volta' {
        $script:range = @{ '\\.\DISPLAY1' = 0; '\\.\DISPLAY2' = 1 }
        Mock Get-UTDisplayInfo { @([pscustomobject]@{ Dispositivo = '\\.\DISPLAY1'; Nome = 'GS27QA' }, [pscustomobject]@{ Dispositivo = '\\.\DISPLAY2'; Nome = 'SFV2405S' }) }
        Mock Get-UTNvDisplayColor { [pscustomobject]@{ DisplayId = [uint32]($(if ($Dispositivo -like '*1') { 1 } else { 2 })); Faixa = $script:range[$Dispositivo]; Formato = 0 } }
        Mock Set-UTNvDisplayRange { $dev = $(if ($DisplayId -eq 1) { '\\.\DISPLAY1' } else { '\\.\DISPLAY2' }); $script:range[$dev] = $Faixa }
        (Get-UTNvidiaColorRange | Where-Object Nome -eq 'SFV2405S').Rotulo | Should -Be 'Limitada (16-235)'
        (Invoke-UTTweak -Id 'UT_GPU_NvidiaFullRange').Status | Should -Be 'Aplicado'
        $script:range['\\.\DISPLAY2'] | Should -Be 0
        Should -Invoke Set-UTNvDisplayRange -Times 1
        Undo-UTTweak -Id 'UT_GPU_NvidiaFullRange' | Out-Null
        $script:range['\\.\DISPLAY2'] | Should -Be 1
    }

    It 'monitor abaixo da taxa máxima sobe, testando o modo antes, e o desfazer volta' {
        $script:hz = @{ '\\.\DISPLAY2' = 120 }
        Mock Get-UTDisplayInfo { @([pscustomobject]@{ Dispositivo = '\\.\DISPLAY2'; Nome = 'SFV2405S'; HzAtual = $script:hz['\\.\DISPLAY2']; HzMaximo = 280 }) }
        Mock Set-UTMonitorRefresh { if (-not $Teste) { $script:hz[$Dispositivo] = $Hz }; 0 }
        (Invoke-UTTweak -Id 'UT_GPU_MonitorMaxHz').Status | Should -Be 'Aplicado'
        $script:hz['\\.\DISPLAY2'] | Should -Be 280
        Should -Invoke Set-UTMonitorRefresh -Times 1 -ParameterFilter { $Teste }
        Undo-UTTweak -Id 'UT_GPU_MonitorMaxHz' | Out-Null
        $script:hz['\\.\DISPLAY2'] | Should -Be 120
    }

    It 'power limit: lê o nvidia-smi, sobe ao máximo e volta' {
        $script:pl = 250
        Mock Invoke-UTNative {
            if ($ArgumentList[0] -eq '-pl') { $script:pl = [double]$ArgumentList[1]; return [pscustomobject]@{ CodigoSaida = 0; Saida = 'ok'; Erro = '' } }
            [pscustomobject]@{ CodigoSaida = 0; Saida = "$($script:pl).00, 250.00, 175.00, 300.00"; Erro = '' }
        } -ParameterFilter { $FilePath -eq 'nvidia-smi.exe' }
        (Get-UTNvidiaPowerLimit).Maximo | Should -Be 300
        (Invoke-UTTweak -Id 'UT_GPU_NvidiaPowerMax' -RiscoAltoConfirmado).Status | Should -Be 'Aplicado'
        $script:pl | Should -Be 300
        Undo-UTTweak -Id 'UT_GPU_NvidiaPowerMax' | Out-Null
        $script:pl | Should -Be 250
        { Set-UTNvidiaPowerLimit -Watts 400 } | Should -Throw '*fora do permitido*'
    }

    It 'Resizable BAR: <Caso>' -TestCases @(
        @{ Caso = 'ligado'; Bar = 16384; Fb = 12227; Esperado = $true }
        @{ Caso = 'desligado'; Bar = 256; Fb = 8192; Esperado = $false }
    ) {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = "    FB Memory Usage`n        Total : $Fb MiB`n    BAR1 Memory Usage`n        Total : $Bar MiB"; Erro = '' } } -ParameterFilter { $FilePath -eq 'nvidia-smi.exe' }
        (Get-UTResizableBarStatus).Ligado | Should -Be $Esperado
    }
}

Describe 'Ferramentas da aba GPU' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'limpa o cache de shaders e informa quanto liberou' {
        $old = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path $TestDrive 'local'
            $dir = Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'
            New-Item -ItemType Directory -Force $dir | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $dir 'a.bin'), (New-Object byte[] (2MB)))
            (@(Get-UTShaderCacheLocation)[0]).TamanhoMB | Should -Be 2
            Clear-UTShaderCache -Confirm:$false | Should -Be 2
            @(Get-ChildItem $dir).Count | Should -Be 0
        } finally { $env:LOCALAPPDATA = $old }
    }

    It 'driver só-vídeo: mantém Display.Driver e NVI2 e limpa o setup.cfg' {
        $pkg = Join-Path $TestDrive 'nv'
        foreach ($d in 'Display.Driver', 'NVI2', 'HDAudio', 'PhysX', 'NvTelemetry', 'GFExperience', 'NvApp', 'USBC') { New-Item -ItemType Directory -Force (Join-Path $pkg $d) | Out-Null }
        Set-Content (Join-Path $pkg 'setup.exe') 'x'
        Set-Content (Join-Path $pkg 'setup.cfg') @('<setup>', '<file name="${{EulaHtmlFile}}"/>', '<file name="${{FunctionalConsentFile}}"/>', '<file name="${{PrivacyPolicyFile}}"/>', '<keep/>', '</setup>')
        $removed = Optimize-UTNvidiaDriverPackage -Pasta $pkg -ManterHdAudio
        ($removed | Sort-Object) | Should -Be @('GFExperience', 'NvApp', 'NvTelemetry', 'PhysX', 'USBC')
        (Get-ChildItem $pkg -Directory).Name | Sort-Object | Should -Be @('Display.Driver', 'HDAudio', 'NVI2')
        $cfg = Get-Content (Join-Path $pkg 'setup.cfg')
        $cfg | Should -Not -Match 'EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile'
        $cfg | Should -Contain '<keep/>'
    }

    It 'recusa pasta que não é driver NVIDIA' {
        { Optimize-UTNvidiaDriverPackage -Pasta $TestDrive } | Should -Throw '*não parece um driver NVIDIA*'
    }

    It 'links oficiais de driver dos três fabricantes' {
        $links = (Get-UTConfig -Name 'gpu-guia').links
        foreach ($v in 'nvidia', 'amd', 'intel') { $links[$v] | Should -Match '^https://' }
    }
}

Describe 'Diagnóstico: faixa de cor e Resizable BAR' {
    It 'avisa monitor em faixa Limitada e ReBAR desligado' {
        $hw = [pscustomobject]@{ EhNotebook = $false; Seguranca = $null; Memoria = $null; Monitores = @(); Gpus = @(); Sistema = $null; Armazenamento = $null; Jogo = $null; Cpu = $null; X3D = $null; Windows = $null
            Nvidia = [pscustomobject]@{ Cor = @([pscustomobject]@{ Nome = 'SFV2405S'; Completa = $false }); ResizableBar = [pscustomobject]@{ Ligado = $false } } }
        $checks = @(Get-UTDiagnosticCheck -Hardware $hw)
        ($checks | Where-Object Id -eq 'faixa').Mensagem | Should -Match 'SFV2405S'
        ($checks | Where-Object Id -eq 'rebar').Status | Should -Be 'Aviso'
    }
}

Describe 'Driver NVIDIA real deste PC (só leitura)' -Skip:(-not $hasNvidia) {
    BeforeAll { Reset-UTTestEnvironment }

    It 'lê o perfil do jogo e o global sem gravar' {
        $UTSync.Contexto = $null
        @(Get-UTNvidiaDrsStatus -Escopo global).Count | Should -BeGreaterThan 10
    }

    It 'lê a faixa dinâmica e o Resizable BAR' {
        @(Get-UTNvidiaColorRange).Count | Should -BeGreaterThan 0
        (Get-UTResizableBarStatus).Bar1MiB | Should -BeGreaterThan 0
    }
}
