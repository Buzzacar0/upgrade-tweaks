BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function Set-Ctx([string[]]$Gpu) {
        $UTSync.Contexto = [pscustomobject]@{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = $Gpu; CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null
            Executaveis = @('H:\HQ\cod.exe'); PastasJogo = @('H:\HQ') }
    }

    function New-FakeAdlx {
        # In-memory stand-in for UpgradeTweaks.Adlx: two GPUs (integrated + discrete), one FreeSync monitor.
        $script:adlx = @{
            gpu = @{ 'antiLag' = 0; 'chill' = 1; 'boost' = 1; 'imageSharpening' = 0; 'enhancedSync' = 1; 'vsync' = 2; 'frtc' = 1; 'antiAliasing' = 2; 'mlaa' = 1; 'anisotropic' = 1; 'tessellation' = 1 }
            global = @{ 'afmf' = 1; 'rsr' = 1 }
            igpu = @{}
            freesync = 0
        }
        $o = [pscustomobject]@{}
        $o | Add-Member ScriptMethod Gpus { @([pscustomobject]@{ Ptr = [IntPtr]1; Nome = 'Radeon iGPU'; Tipo = 1; Id = 10 }, [pscustomobject]@{ Ptr = [IntPtr]2; Nome = 'Radeon RX 9070 XT'; Tipo = 2; Id = 20 }) }
        $o | Add-Member ScriptMethod Get {
            $k = [string]$args[0]
            if ($script:adlx.global.ContainsKey($k)) { return [pscustomobject]@{ Suportado = $true; Valor = $script:adlx.global[$k]; Erro = $null } }
            if ([int64]$args[1] -ne 2) { return [pscustomobject]@{ Suportado = $false; Valor = 0; Erro = 'iGPU' } }
            [pscustomobject]@{ Suportado = $true; Valor = $script:adlx.gpu[$k]; Erro = $null }
        }
        $o | Add-Member ScriptMethod Set {
            $k = [string]$args[0]
            if ($script:adlx.global.ContainsKey($k)) { $script:adlx.global[$k] = [int]$args[2] } else { $script:adlx.gpu[$k] = [int]$args[2] }
            0
        }
        $o | Add-Member ScriptMethod FreeSyncDisplays { @([System.Collections.Generic.KeyValuePair[string, IntPtr]]::new('Monitor FreeSync', [IntPtr]9)) }
        $o | Add-Member ScriptMethod GetFreeSync { [pscustomobject]@{ Suportado = $true; Valor = $script:adlx.freesync; Erro = $null } }
        $o | Add-Member ScriptMethod SetFreeSync { $script:adlx.freesync = $(if ($args[1]) { 1 } else { 0 }); 0 }
        $o | Add-Member ScriptMethod Dispose { }
        return $o
    }

    function New-FakeIgcl {
        $script:igcl = @{ 16 = 0; 9 = 2; 1 = 2; 2 = 1; 18 = 0 }
        $o = [pscustomobject]@{}
        $o | Add-Member ScriptMethod Devices { , @([IntPtr]5) }
        $o | Add-Member ScriptMethod Get { [pscustomobject]@{ Suportado = $true; Valor = $script:igcl[[int]$args[1]]; Resultado = 0 } }
        $o | Add-Member ScriptMethod Set { $script:igcl[[int]$args[1]] = [int]$args[3]; [pscustomobject]@{ Suportado = $true; Valor = [int]$args[3]; Resultado = 0 } }
        $o | Add-Member ScriptMethod Dispose { }
        return $o
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'AMD (ADLX simulado)' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx -Gpu @('amd')
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        $script:fakeAdlx = New-FakeAdlx
        Mock Open-UTAdlxSession { $script:fakeAdlx }
        Mock Get-UTAmdUmdKey { @("$UTTestKey\Amd\0001\UMD") }
        Set-UTRegistryValue -Path "$UTTestKey\Amd\0001\UMD" -Name 'TFQ' -Type Binary -Value ([Text.Encoding]::Unicode.GetBytes('1'))
    }
    AfterEach { if (Test-Path "$UTTestKey\Amd") { Remove-Item "$UTTestKey\Amd" -Recurse -Force } }

    It 'usa só a placa dedicada quando existe; a integrada fica de fora' {
        $s = New-FakeAdlx
        @(Get-UTAmdTargetGpu -Sessao $s).Nome | Should -Be @('Radeon RX 9070 XT')
    }

    It 'status mostra atual x recomendado, inclusive FreeSync e filtragem de textura' {
        $rows = @(Get-UTAmdSettingStatus)
        ($rows | Where-Object Chave -eq 'antiLag').Atual | Should -Be 'Desligado'
        ($rows | Where-Object Chave -eq 'antiLag').Recomendado | Should -Be 'Ligado'
        ($rows | Where-Object Chave -eq 'vsync').Atual | Should -Be 'Ligado, a menos que o aplicativo especifique'
        ($rows | Where-Object Chave -eq 'afmf').Placa | Should -Be 'Todas'
        ($rows | Where-Object Chave -eq 'freeSync').Atual | Should -Be 'Desligado'
        ($rows | Where-Object Chave -eq 'tfq').Atual | Should -Be 'Padrão'
        @($rows | Where-Object Igual).Count | Should -Be 0
    }

    It 'aplica tudo, detecta como aplicado e o desfazer volta cada valor' {
        (Invoke-UTTweak -Id 'UT_GPU_AmdRecomendado').Status | Should -Be 'Aplicado'
        $script:adlx.gpu.antiLag | Should -Be 1
        $script:adlx.gpu.chill | Should -Be 0
        $script:adlx.gpu.vsync | Should -Be 1
        $script:adlx.global.afmf | Should -Be 0
        $script:adlx.freesync | Should -Be 1
        ConvertFrom-UTUmdString (Get-UTRegistryValue -Path "$UTTestKey\Amd\0001\UMD" -Name 'TFQ').Valor | Should -Be '2'
        (Get-UTTweakState -Id 'UT_GPU_AmdRecomendado').Estado | Should -Be 'Aplicado'

        (Undo-UTTweak -Id 'UT_GPU_AmdRecomendado').Status | Should -Be 'Desfeito'
        $script:adlx.gpu.antiLag | Should -Be 0
        $script:adlx.gpu.vsync | Should -Be 2
        $script:adlx.global.rsr | Should -Be 1
        $script:adlx.freesync | Should -Be 0
        ConvertFrom-UTUmdString (Get-UTRegistryValue -Path "$UTTestKey\Amd\0001\UMD" -Name 'TFQ').Valor | Should -Be '1'
    }

    It 'simular lista atual -> novo sem tocar no driver' {
        $r = Invoke-UTTweak -Id 'UT_GPU_AmdRecomendado' -WhatIf
        $r.Status | Should -Be 'Simulado'
        $r.Acoes | Should -Contain 'Radeon Anti-Lag [Radeon RX 9070 XT]: Desligado -> Ligado'
        $script:adlx.gpu.antiLag | Should -Be 0
    }

    It 'não se aplica a PC com placa NVIDIA (iGPU AMD não conta)' {
        Set-Ctx -Gpu @('nvidia')
        (Invoke-UTTweak -Id 'UT_GPU_AmdRecomendado').Status | Should -Be 'Ignorado'
    }

    It 'valor UMD lido como bytes ou texto hexadecimal' {
        ConvertFrom-UTUmdString ([byte[]](0x32, 0x00)) | Should -Be '2'
        ConvertFrom-UTUmdString '3100' | Should -Be '1'
    }
}

Describe 'Intel (IGCL simulado)' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx -Gpu @('intel')
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        $script:fakeIgcl = New-FakeIgcl
        Mock Open-UTIgclSession { $script:fakeIgcl }
    }

    It 'aplica, detecta e desfaz' {
        (Get-UTIntelSettingStatus | Where-Object Chave -eq 'lowLatency').Atual | Should -Be 'Desligado'
        (Invoke-UTTweak -Id 'UT_GPU_IntelRecomendado').Status | Should -Be 'Aplicado'
        $script:igcl[16] | Should -Be 1
        $script:igcl[9] | Should -Be 1
        $script:igcl[1] | Should -Be 0
        $script:igcl[2] | Should -Be 0
        $script:igcl[18] | Should -Be 1
        (Get-UTTweakState -Id 'UT_GPU_IntelRecomendado').Estado | Should -Be 'Aplicado'
        Undo-UTTweak -Id 'UT_GPU_IntelRecomendado' | Out-Null
        $script:igcl[16] | Should -Be 0
        $script:igcl[1] | Should -Be 2
    }

    It 'configuração que o driver não responde é pulada' {
        $script:fakeIgcl | Add-Member ScriptMethod Get { if ([int]$args[1] -eq 18) { return [pscustomobject]@{ Suportado = $false; Valor = 0; Resultado = 0x40000007 } }; [pscustomobject]@{ Suportado = $true; Valor = $script:igcl[[int]$args[1]]; Resultado = 0 } } -Force
        (Invoke-UTTweak -Id 'UT_GPU_IntelRecomendado').Status | Should -Be 'Aplicado'
        $script:igcl[18] | Should -Be 0
    }
}

Describe 'Bibliotecas nativas' {
    It 'os tipos C# da ADLX e da IGCL compilam' {
        Initialize-UTAdlxType
        Initialize-UTIgclType
        'UpgradeTweaks.Adlx' -as [type] | Should -Not -BeNullOrEmpty
        'UpgradeTweaks.Igcl' -as [type] | Should -Not -BeNullOrEmpty
    }
}
