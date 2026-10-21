BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null
            Executaveis = @('H:\HQ\cod.exe'); PastasJogo = @('H:\HQ') }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Arquivo de configuração do jogo' {
    BeforeEach {
        Reset-UTTestEnvironment
        $players = Join-Path $TestDrive ('players' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $players | Out-Null
        $file = Join-Path $players 's.1.0.cod25.txt0'
        $content = @(
            '// Configurações do Call of Duty'
            'RendererWorkerCount@0;11223;44556 = 7 // Número de threads do renderizador'
            'VideoMemoryScale:0.0 = "0.85" // Escala de memória de vídeo'
            'ShowFPS@0;1;2 = false'
        ) -join "`r`n"
        [IO.File]::WriteAllText($file, $content, (New-Object System.Text.UTF8Encoding($false)))
        Set-Content -LiteralPath (Join-Path $players 's.1.0.cod24.txt0') -Value 'x'
        (Get-Item (Join-Path $players 's.1.0.cod24.txt0')).LastWriteTime = (Get-Date).AddDays(-5)
    }

    It 'acha os arquivos pelo padrão, com o título do jogo, mais novo primeiro' {
        $f = @(Get-UTCodConfigFile -Pasta $players)
        $f.Count | Should -Be 2
        $f[0].Titulo | Should -Be 'Black Ops 7'
        $f[1].Titulo | Should -Be 'Black Ops 6'
    }

    It 'lê valores em todos os formatos de linha' {
        Get-UTCodConfigValue -Arquivo $file -Chave 'RendererWorkerCount' | Should -Be '7'
        Get-UTCodConfigValue -Arquivo $file -Chave 'VideoMemoryScale' | Should -Be '0.85'
        Get-UTCodConfigValue -Arquivo $file -Chave 'NaoExiste' | Should -BeNullOrEmpty
    }

    It 'altera só o valor, mantendo o resto da linha, e faz backup antes' {
        Set-UTCodConfigValue -Arquivo $file -Chave 'RendererWorkerCount' -Valor '8' | Should -Be '7'
        $text = [IO.File]::ReadAllText($file)
        $text | Should -Match 'RendererWorkerCount@0;11223;44556 = 8 // Número de threads do renderizador'
        Set-UTCodConfigValue -Arquivo $file -Chave 'VideoMemoryScale' -Valor '0.9' | Out-Null
        [IO.File]::ReadAllText($file) | Should -Match 'VideoMemoryScale:0.0 = "0.9" // Escala'
        @(Get-UTCodConfigBackup).Count | Should -Be 2
    }

    It 'nunca acrescenta chave desconhecida' {
        { Set-UTCodConfigValue -Arquivo $file -Chave 'ChaveInventada' -Valor '1' } | Should -Throw '*não acrescenta chaves desconhecidas*'
    }

    It 'RendererWorkerCount = núcleos físicos' {
        $UTSync.Hardware = [pscustomobject]@{ Cpu = [pscustomobject]@{ Nucleos = 8 } }
        Set-UTCodRendererWorker -Arquivo $file | Out-Null
        Get-UTCodConfigValue -Arquivo $file -Chave 'RendererWorkerCount' | Should -Be '8'
    }

    It 'restaura um backup guardando o atual antes' {
        $b = Backup-UTCodConfig -Arquivo $file
        Set-UTCodConfigValue -Arquivo $file -Chave 'ShowFPS' -Valor 'true' | Out-Null
        Restore-UTCodConfig -Backup $b -Pasta $players
        Get-UTCodConfigValue -Arquivo $file -Chave 'ShowFPS' | Should -Be 'false'
    }
}

Describe 'Pasta players do jogo' {
    It 'prefere a pasta que tem arquivos do jogo (Documentos no OneDrive x Documents do perfil)' {
        $one = Join-Path $TestDrive 'OneDrive\Documentos'
        $prof = Join-Path $TestDrive 'perfil\Documents'
        New-Item -ItemType Directory -Force (Join-Path $one 'Call of Duty\players'), (Join-Path $prof 'Call of Duty\players') | Out-Null
        Set-Content (Join-Path $prof 'Call of Duty\players\s.1.0.cod25.txt0') 'x'
        Get-UTCodPlayersFolder -Candidatas @($one, $prof) | Should -Be (Join-Path $prof 'Call of Duty\players')
        Get-UTCodPlayersFolder -Candidatas @((Join-Path $TestDrive 'nada'), $one) | Should -Be (Join-Path $one 'Call of Duty\players')
    }
}

Describe 'Guia aplicado no arquivo do jogo' {
    BeforeEach {
        Reset-UTTestEnvironment
        $players = Join-Path $TestDrive ('wz' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $players | Out-Null
        # Lines copied from the real Black Ops 7 file format.
        $lines = @(
            'DisplayMode@0;22564;43096 = Fullscreen borderless window // one of Windowed, Fullscreen, Fullscreen borderless window, Fullscreen borderless extended window'
            'ResolutionMultiplier@0;64786;30730 = 75 // 0 to 200'
            'NvidiaReflex@0;33761;11445 = Enabled // one of Disabled, Enabled, Enabled + boost'
            'CapFps@0;57752;20945 = false'
            'MaxFpsInGame@0;13305;58861 = 250 // 30 to 300'
            'TextureQuality@0;61129;7764 = 3 // 0 to 3'
            'ShadowQuality@0;3981;58629 = Medium // one of Very_Low, Low, Medium, High, Very_High'
            'EnableVelocityBasedBlur@0;57752;20945 = true'
            'DepthOfField@0;57752;20945 = true'
            'DepthOfField@1;29449;43096 = Script // one of Off, On, Script'
            'VideoMemoryScaleMP@0;59710;7707 = 0.800000 // 0.000000 to 2.000000'
        )
        foreach ($n in 's.1.0.cod25.txt0', 's.1.0.cod25.txt1') { [IO.File]::WriteAllLines((Join-Path $players $n), [string[]]$lines, (New-Object System.Text.UTF8Encoding($false))) }
        Mock Get-UTCodPlayersFolder { $players }
        Mock Test-UTCodGameRunning { $false }
        Mock Get-UTGpuOption { [pscustomobject]@{ ComGsync = $true; HzMonitor = 165 } }
        $UTSync.Hardware = [pscustomobject]@{ GpuFabricantes = @('nvidia'); Gpus = @([pscustomobject]@{ Integrada = $false; VramGB = 12 }) }
    }

    It 'lê as opções válidas do próprio comentário da linha' {
        $f = Join-Path $players 's.1.0.cod25.txt0'
        (Get-UTCodConfigOption -Arquivo $f -Chave 'NvidiaReflex').Opcoes | Should -Contain 'Enabled + boost'
        (Get-UTCodConfigOption -Arquivo $f -Chave 'ResolutionMultiplier').Maximo | Should -Be 200
        (Get-UTCodConfigOption -Arquivo $f -Chave 'CapFps').Tipo | Should -Be 'bool'
        Get-UTCodConfigOption -Arquivo $f -Chave 'NaoExiste' | Should -BeNullOrEmpty
    }

    It 'grava o competitivo nas duas cópias, com backup, e só valores aceitos' {
        $r = @(Set-UTCodRecommendedSetting -Perfil competitivo -Confirm:$false)
        foreach ($n in 's.1.0.cod25.txt0', 's.1.0.cod25.txt1') {
            $f = Join-Path $players $n
            Get-UTCodConfigValue -Arquivo $f -Chave 'DisplayMode' | Should -Be 'Fullscreen'
            Get-UTCodConfigValue -Arquivo $f -Chave 'ResolutionMultiplier' | Should -Be '100'
            Get-UTCodConfigValue -Arquivo $f -Chave 'NvidiaReflex' | Should -Be 'Enabled + boost'
            Get-UTCodConfigValue -Arquivo $f -Chave 'CapFps' | Should -Be 'true'
            Get-UTCodConfigValue -Arquivo $f -Chave 'MaxFpsInGame' | Should -Be '162'
            Get-UTCodConfigValue -Arquivo $f -Chave 'TextureQuality' | Should -Be '0'
            Get-UTCodConfigValue -Arquivo $f -Chave 'ShadowQuality' | Should -Be 'Very_Low'
            Get-UTCodConfigValue -Arquivo $f -Chave 'EnableVelocityBasedBlur' | Should -Be 'false'
            Get-UTCodConfigValue -Arquivo $f -Chave 'DepthOfField' | Should -Be 'false'
            Get-UTCodConfigValue -Arquivo $f -Chave 'VideoMemoryScaleMP' | Should -Be '0.850000'
            [IO.File]::ReadAllText($f) | Should -Match 'DepthOfField@1;29449;43096 = Script'
            [IO.File]::ReadAllText($f) | Should -Match 'NvidiaReflex@0;33761;11445 = Enabled \+ boost // one of Disabled, Enabled, Enabled \+ boost'
        }
        @(Get-UTCodConfigBackup).Count | Should -Be 2
        @($r | Where-Object { $_.Chave -eq 'SSRQuality' } | Select-Object -First 1).Motivo | Should -Match 'não tem essa chave'
        @($r | Where-Object { -not $_.Chave }).Count | Should -BeGreaterThan 0
    }

    It 'valor que o jogo não aceita fica como está' {
        $f = Join-Path $players 's.1.0.cod25.txt0'
        $o = Get-UTCodConfigOption -Arquivo $f -Chave 'ShadowQuality'
        Test-UTCodConfigValueValid -Opcao $o -Valor 'Ultra' | Should -BeNullOrEmpty
        Test-UTCodConfigValueValid -Opcao (Get-UTCodConfigOption -Arquivo $f -Chave 'ResolutionMultiplier') -Valor '250' | Should -BeNullOrEmpty
    }

    It 'com o jogo aberto, recusa' {
        Mock Test-UTCodGameRunning { $true }
        { Set-UTCodRecommendedSetting -Perfil competitivo -Confirm:$false } | Should -Throw '*Feche o Call of Duty*'
    }

    It 'sem G-SYNC/FreeSync o competitivo tira o limite de FPS' {
        Mock Get-UTGpuOption { [pscustomobject]@{ ComGsync = $false; HzMonitor = 165 } }
        Set-UTCodRecommendedSetting -Perfil competitivo -Confirm:$false | Out-Null
        Get-UTCodConfigValue -Arquivo (Join-Path $players 's.1.0.cod25.txt0') -Chave 'CapFps' | Should -Be 'false'
    }
}

Describe 'Guia de configurações do jogo' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'ajusta upscaler e texturas pela placa' {
        $UTSync.Hardware = [pscustomobject]@{ GpuFabricantes = @('nvidia'); Gpus = @([pscustomobject]@{ Integrada = $false; VramGB = 12 }) }
        $g = @(Get-UTWarzoneGuide -Perfil competitivo)
        ($g | Where-Object Opcao -eq 'Upscaling / nitidez').Valor | Should -Be 'DLSS Qualidade'
        ($g | Where-Object Opcao -eq 'Resolução das texturas').Valor | Should -Be 'Alta'
        $UTSync.Hardware = [pscustomobject]@{ GpuFabricantes = @('amd'); Gpus = @([pscustomobject]@{ Integrada = $false; VramGB = 8 }) }
        $g = @(Get-UTWarzoneGuide -Perfil competitivo)
        ($g | Where-Object Opcao -eq 'Upscaling / nitidez').Valor | Should -Be 'FSR Qualidade'
        ($g | Where-Object Opcao -eq 'Resolução das texturas').Valor | Should -Be 'Normal'
    }
}

Describe 'Exclusão do Windows Defender' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        Mock Get-UTShaderCacheLocation { [pscustomobject]@{ Caminho = 'C:\Users\x\AppData\Local\NVIDIA\DXCache' } }
        $script:excl = @('D:\MeusProjetos')
        Mock Get-MpPreference { [pscustomobject]@{ ExclusionPath = $script:excl } }
        Mock Add-MpPreference { $script:excl = @($script:excl + $ExclusionPath) }
        Mock Remove-MpPreference { $script:excl = @($script:excl | Where-Object { $ExclusionPath -notcontains $_ }) }
    }

    It 'exclui pasta do jogo e cache, e o desfazer tira só o que adicionou' {
        (Invoke-UTTweak -Id 'UT_Warzone_DefenderExclusion').Status | Should -Be 'Aplicado'
        $script:excl | Should -Contain 'H:\HQ'
        $script:excl | Should -Contain 'C:\Users\x\AppData\Local\NVIDIA\DXCache'
        Undo-UTTweak -Id 'UT_Warzone_DefenderExclusion' | Out-Null
        $script:excl | Should -Be @('D:\MeusProjetos')
    }

    It 'outro antivírus ativo: mensagem clara' {
        Mock Get-MpPreference { throw 'servico parado' }
        (Invoke-UTTweak -Id 'UT_Warzone_DefenderExclusion').Mensagem | Should -Match 'não é o antivírus ativo'
    }
}

Describe 'Modo Partida' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        Mock Assert-UTAdmin {}
        $script:running = @('chrome', 'Spotify', 'OneDrive', 'steam', 'Discord')
        Mock Get-Process { @($script:running | Where-Object { $_ -eq $Name } | ForEach-Object { [pscustomobject]@{ Name = $_; Path = "C:\Apps\$_.exe" } }) }
        Mock Stop-Process { $n = $(if ($InputObject) { @($InputObject)[0].Name } else { @($Name)[0] }); $script:running = @($script:running | Where-Object { $_ -ne $n }) }
        $script:active = '381b4222-f694-41f0-9685-ff5bb260df2e'
        Mock Get-UTActivePowerScheme { [pscustomobject]@{ Guid = $script:active; Nome = 'x' } }
        Mock Find-UTUpgradePowerScheme { '11111111-1111-1111-1111-111111111111' }
        Mock Invoke-UTPowerCfg { if ($Argumentos[0] -eq '/setactive') { $script:active = $Argumentos[1] }; '' }
        Mock Test-UTPowerScheme { $true }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'C:\Apps\*' }
        Mock Start-Process {}
    }

    It 'a lista não tem o launcher do jogo nem processos protegidos; Discord não vem marcado' {
        $list = @(Get-UTMatchModeList)
        ($list | ForEach-Object Processo) | Should -Not -Contain 'steam'
        ($list | ForEach-Object Processo) | Should -Not -Contain 'Discord'
        ($list | Where-Object Processo -eq 'Spotify').Marcado | Should -BeFalse
    }

    It 'liga: fecha só os marcados, ativa o plano Upgrade Warzone; desliga: volta o plano e reabre' {
        $s = Start-UTMatchMode
        $s.Ativo | Should -BeTrue
        $script:running | Should -Be @('Spotify', 'steam', 'Discord')
        $script:active | Should -Be '11111111-1111-1111-1111-111111111111'
        Stop-UTMatchMode
        $script:active | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'explorer.exe' -and $ArgumentList -match 'OneDrive' }
        (Get-UTMatchModeStatus).Ativo | Should -BeFalse
    }

    It 'X3D de dois CCDs: usa o Equilibrado em vez do Upgrade Warzone' {
        Set-Ctx @{ X3D = 'duplo' }
        $script:active = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        Start-UTMatchMode | Out-Null
        $script:active | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
    }

    It 'escolhas do usuário: marca o Discord e acrescenta um processo; protegido é recusado' {
        Set-UTMatchModeChoice -Marcados @{ Spotify = $true } -Extras @([ordered]@{ processo = 'Discord'; nome = 'Discord'; grupo = 'Comunicação'; marcado = $true; reabrir = $true })
        $list = @(Get-UTMatchModeList)
        ($list | Where-Object Processo -eq 'Spotify').Marcado | Should -BeTrue
        ($list | Where-Object Processo -eq 'Discord').Marcado | Should -BeTrue
        { Set-UTMatchModeChoice -Extras @(@{ processo = 'audiodg'; nome = 'Áudio' }) } | Should -Throw '*protegido*'
    }

    It 'não liga duas vezes' {
        Start-UTMatchMode | Out-Null
        { Start-UTMatchMode } | Should -Throw '*já está ativo*'
    }
}
