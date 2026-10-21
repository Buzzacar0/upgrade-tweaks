BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null; Executaveis = @() }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Textos de flags' {
    It 'Merge-UTFlagString: <Caso>' -TestCases @(
        @{ Caso = 'vazio'; Texto = ''; Esperado = 'SwapEffectUpgradeEnable=1;' }
        @{ Caso = 'mantém os outros'; Texto = 'AutoHDREnable=1;VRROptimizeEnable=0;'; Esperado = 'AutoHDREnable=1;VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;' }
        @{ Caso = 'troca o existente'; Texto = 'SwapEffectUpgradeEnable=0;AutoHDREnable=1;'; Esperado = 'SwapEffectUpgradeEnable=1;AutoHDREnable=1;' }
    ) {
        Merge-UTFlagString -Text $Texto -Key 'SwapEffectUpgradeEnable' -Value '1' | Should -BeExactly $Esperado
    }

    It 'Get-UTFlagString' {
        Get-UTFlagString -Text 'GpuPreference=2;' -Key 'GpuPreference' | Should -Be '2'
        Get-UTFlagString -Text 'AutoHDREnable=1;' -Key 'GpuPreference' | Should -BeNullOrEmpty
    }

    It 'Add-UTCompatLayerFlag mantém as outras opções de compatibilidade' {
        Add-UTCompatLayerFlag -Text '' -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' | Should -BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Add-UTCompatLayerFlag -Text '~ HIGHDPIAWARE' -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' | Should -BeExactly '~ HIGHDPIAWARE DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Add-UTCompatLayerFlag -Text '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' | Should -BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    }
}

Describe 'Registro rastreado por tweak (caminhos descobertos na hora)' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Backup-UTRegistryKey {}
    }

    It 'grava, guarda o original e Restore-UTTweakRegistryItem desfaz tudo do tweak' {
        Set-UTRegistryValue -Path "$UTTestKey\Gpu" -Name 'C:\Jogo\cod.exe' -Type String -Value 'AutoHDREnable=1;'
        Set-UTRegistryValueTracked -Path "$UTTestKey\Gpu" -Name 'C:\Jogo\cod.exe' -Type String -Value 'GpuPreference=2;' -TweakId 'UT_X'
        Set-UTRegistryValueTracked -Path "$UTTestKey\Gpu" -Name 'C:\Jogo\sp26-cod.exe' -Type String -Value 'GpuPreference=2;' -TweakId 'UT_X'
        @(Get-UTTweakRegistryItem -TweakId 'UT_X').Count | Should -Be 2
        Restore-UTTweakRegistryItem -TweakId 'UT_X' | Should -Be 2
        (Get-UTRegistryValue "$UTTestKey\Gpu" 'C:\Jogo\cod.exe').Valor | Should -Be 'AutoHDREnable=1;'
        (Get-UTRegistryValue "$UTTestKey\Gpu" 'C:\Jogo\sp26-cod.exe').ValorExiste | Should -BeFalse
    }

    It 'preferência de GPU por executável, mantendo flags existentes' {
        Set-Ctx @{ Executaveis = @('C:\Jogo\cod.exe', 'C:\Jogo\cod25\cod25-cod.exe') }
        Set-UTRegistryValue -Path "$UTTestKey\Gpu" -Name 'C:\Jogo\cod.exe' -Type String -Value 'AutoHDREnable=1;'
        Test-UTGameRegistryFlag -Path "$UTTestKey\Gpu" -Mode GpuPreference | Should -BeFalse
        Set-UTGameRegistryFlag -Path "$UTTestKey\Gpu" -Mode GpuPreference -TweakId 'UT_G'
        Test-UTGameRegistryFlag -Path "$UTTestKey\Gpu" -Mode GpuPreference | Should -BeTrue
        (Get-UTRegistryValue "$UTTestKey\Gpu" 'C:\Jogo\cod.exe').Valor | Should -Be 'AutoHDREnable=1;GpuPreference=2;'
        [void](Restore-UTTweakRegistryItem -TweakId 'UT_G')
        Test-UTGameRegistryFlag -Path "$UTTestKey\Gpu" -Mode GpuPreference | Should -BeFalse
    }

    It 'otimizações de tela cheia por executável' {
        Set-Ctx @{ Executaveis = @('C:\Jogo\cod.exe') }
        Set-UTGameRegistryFlag -Path "$UTTestKey\Layers" -Mode DisableFso -TweakId 'UT_F'
        (Get-UTRegistryValue "$UTTestKey\Layers" 'C:\Jogo\cod.exe').Valor | Should -Be '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Test-UTGameRegistryFlag -Path "$UTTestKey\Layers" -Mode DisableFso | Should -BeTrue
    }

    It 'sem jogo encontrado, recusa com mensagem clara' {
        Set-Ctx
        { Set-UTGameRegistryFlag -Path "$UTTestKey\Gpu" -Mode GpuPreference -TweakId 'UT_G' } | Should -Throw '*não encontrado*'
    }

    It 'prioridade IFEO usa só o nome do executável, sem repetir' {
        Set-Ctx @{ Executaveis = @('C:\A\cod.exe', 'D:\B\cod.exe', 'C:\A\cod25\cod25-cod.exe') }
        Mock Set-UTRegistryValueTracked {}
        Set-UTGameIfeoPriority -TweakId 'UT_P'
        Should -Invoke Set-UTRegistryValueTracked -Times 2
        Should -Invoke Set-UTRegistryValueTracked -Times 1 -ParameterFilter { $Path -like '*Image File Execution Options\cod.exe\PerfOptions' -and $Value -eq 3 }
    }

    It 'DirectXUserGlobalSettings preserva as outras opções' {
        Mock Get-UTRegistryValue { [pscustomobject]@{ ValorExiste = $true; Valor = 'AutoHDREnable=1;' } } -ParameterFilter { $Name -eq 'DirectXUserGlobalSettings' }
        Mock Set-UTRegistryValueTracked {}
        Set-UTDirectXGlobalFlag -Key 'SwapEffectUpgradeEnable' -Value '1' -TweakId 'UT_W'
        Should -Invoke Set-UTRegistryValueTracked -Times 1 -ParameterFilter { $Value -eq 'AutoHDREnable=1;SwapEffectUpgradeEnable=1;' }
    }
}

Describe 'bcdedit' {
    BeforeEach {
        Reset-UTTestEnvironment
        $script:bcd = @{}
        Mock Suspend-UTBitLockerForBoot {}
        Mock Invoke-UTNative {
            switch ($ArgumentList[0]) {
                '/enum' {
                    $lines = @('Carregador de Inicialização do Windows', '-------------------', 'identificador           {current}', 'description             Windows 11')
                    foreach ($k in $script:bcd.Keys) { $lines += ('{0,-23} {1}' -f $k, $script:bcd[$k]) }
                    return [pscustomobject]@{ CodigoSaida = 0; Saida = ($lines -join "`n"); Erro = '' }
                }
                '/set' { $script:bcd[$ArgumentList[2]] = $(if ($ArgumentList[3] -eq 'yes') { 'Yes' } else { $ArgumentList[3] }) }
                '/deletevalue' { $script:bcd.Remove($ArgumentList[2]) }
            }
            [pscustomobject]@{ CodigoSaida = 0; Saida = 'A operação foi concluída com êxito.'; Erro = '' }
        } -ParameterFilter { $FilePath -eq 'bcdedit.exe' }
    }

    It 'lê, liga e o desfazer apaga quando o valor não existia' {
        (Get-UTBcdSetting -Name 'disabledynamictick').Existe | Should -BeFalse
        Set-UTBcdSetting -Name 'disabledynamictick' -Value 'yes' -TweakId 'UT_T'
        (Get-UTBcdSetting -Name 'disabledynamictick').Ligado | Should -BeTrue
        Should -Invoke Suspend-UTBitLockerForBoot -Times 1
        Restore-UTBcdSetting -Name 'disabledynamictick' -TweakId 'UT_T'
        (Get-UTBcdSetting -Name 'disabledynamictick').Existe | Should -BeFalse
    }

    It 'volta o valor anterior quando ele existia' {
        $script:bcd['disabledynamictick'] = 'No'
        Set-UTBcdSetting -Name 'disabledynamictick' -Value 'yes' -TweakId 'UT_T'
        Restore-UTBcdSetting -Name 'disabledynamictick' -TweakId 'UT_T'
        (Get-UTBcdSetting -Name 'disabledynamictick').Valor | Should -Be 'No'
    }

    It 'entende "Sim" no Windows em português' {
        $script:bcd['disabledynamictick'] = 'Sim'
        (Get-UTBcdSetting -Name 'disabledynamictick').Ligado | Should -BeTrue
    }

    It 'o tweak do catálogo aplica e desfaz pelo motor' {
        Set-Ctx
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        (Invoke-UTTweak -Id 'UT_Lat_DynamicTick_Off').Status | Should -Be 'Aplicado'
        $script:bcd['disabledynamictick'] | Should -Be 'Yes'
        (Undo-UTTweak -Id 'UT_Lat_DynamicTick_Off').Status | Should -Be 'Desfeito'
        $script:bcd.ContainsKey('disabledynamictick') | Should -BeFalse
    }
}

Describe 'Modo MSI' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Backup-UTRegistryKey {}
        Mock Get-UTMsiDevice { @([pscustomobject]@{ Nome = 'NVIDIA GeForce RTX 5070'; Instancia = 'PCI\VEN_10DE&DEV_2F04\X'; Caminho = "$UTTestKey\Enum\GPU\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" }) }
    }

    It 'liga, detecta e desfaz removendo as chaves criadas' {
        Test-UTMsiMode -Tipo GPU | Should -BeFalse
        Set-UTMsiMode -Tipo GPU -TweakId 'UT_M'
        Test-UTMsiMode -Tipo GPU | Should -BeTrue
        [void](Restore-UTTweakRegistryItem -TweakId 'UT_M')
        Test-UTRegistryKey -Path "$UTTestKey\Enum" | Should -BeFalse
    }

    It 'já ligado pelo driver aparece como aplicado' {
        Set-UTRegistryValue -Path "$UTTestKey\Enum\GPU\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" -Name 'MSISupported' -Type DWord -Value 1
        Test-UTMsiMode -Tipo GPU | Should -BeTrue
    }
}

Describe 'Economia de energia USB' {
    BeforeEach {
        Reset-UTTestEnvironment
        $script:usb = @(
            [pscustomobject]@{ InstanceName = 'USB\ROOT_HUB30\4&1_0'; Enable = $true }
            [pscustomobject]@{ InstanceName = 'USB\VID_046D&PID_C539\5&2_0'; Enable = $false }
        )
        Mock Get-UTUsbPowerDevice { $script:usb }
        Mock Set-UTUsbDeviceEnable { $Dispositivo.Enable = $Ativo }
    }

    It 'desmarca, detecta e devolve cada dispositivo ao estado original' {
        Test-UTUsbPowerSaving | Should -BeFalse
        Disable-UTUsbPowerSaving -TweakId 'UT_U'
        Test-UTUsbPowerSaving | Should -BeTrue
        Restore-UTUsbPowerSaving -TweakId 'UT_U'
        $script:usb[0].Enable | Should -BeTrue
        $script:usb[1].Enable | Should -BeFalse
    }
}

Describe 'Compatibilidade: exigeJogo' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'ajustes do executável ficam bloqueados sem o jogo e liberados com ele' {
        Set-Ctx
        (Get-UTTweakState -Id 'UT_Warzone_GpuPreference').Estado | Should -Be 'Incompativel'
        (Invoke-UTTweak -Id 'UT_Warzone_GpuPreference').Mensagem | Should -Match 'Call of Duty não encontrado'
        Set-Ctx @{ Executaveis = @('C:\Jogo\cod.exe') }
        $t = Get-UTTweak -Id 'UT_Warzone_GpuPreference'
        (Test-UTTweakCompatibility -Tweak $t -Contexto $UTSync.Contexto).Compativel | Should -BeTrue
    }
}

Describe 'Dispositivos opcionais' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'lista só os tipos previstos e sugere desligar o Wi-Fi quando há cabo' {
        Mock Get-NetAdapter { @([pscustomobject]@{ Status = 'Up'; MediaType = '802.3' }) }
        Mock Get-PnpDevice {
            @(
                [pscustomobject]@{ FriendlyName = 'Porta de comunicação (COM1)'; Class = 'Ports'; InstanceId = 'ACPI\PNP0501\1'; Status = 'OK' }
                [pscustomobject]@{ FriendlyName = 'Intel(R) Wi-Fi 6E AX211 160MHz'; Class = 'Net'; InstanceId = 'PCI\WIFI'; Status = 'OK' }
                [pscustomobject]@{ FriendlyName = 'NVIDIA High Definition Audio'; Class = 'MEDIA'; InstanceId = 'HDAUDIO\NV'; Status = 'OK' }
                [pscustomobject]@{ FriendlyName = 'Realtek Gaming 2.5GbE Family Controller'; Class = 'Net'; InstanceId = 'PCI\LAN'; Status = 'OK' }
                [pscustomobject]@{ FriendlyName = 'Realtek USB Audio'; Class = 'MEDIA'; InstanceId = 'USB\AUDIO'; Status = 'OK' }
            )
        }
        $d = @(Get-UTOptionalDevice)
        ($d | ForEach-Object Tipo) | Should -Be @('Porta serial (COM)', 'Wi-Fi', 'Áudio da placa de vídeo (HDMI/DisplayPort)')
        ($d | Where-Object Tipo -eq 'Wi-Fi').Sugestao | Should -Match 'conectado por cabo'
    }
}

Describe 'Catálogo real neste PC (só leitura)' {
    BeforeAll { Reset-UTTestEnvironment }

    It 'detecta o estado de todos os tweaks sem erro' {
        $states = @(Get-UTTweakState)
        $states.Count | Should -BeGreaterThan 20
        @($states | Where-Object { $_.Estado -eq 'Desconhecido' }).Count | Should -Be 0
    }
}
