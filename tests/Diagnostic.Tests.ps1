BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    function New-FakeHardware {
        # A healthy desktop: every check should be OK.
        param([hashtable]$Change = @{})
        $hw = [pscustomobject]@{
            Coletado      = [datetime]'2026-10-20'
            Computador    = 'PC-TESTE'
            Windows       = [pscustomobject]@{ Geracao = '11'; Build = 26200; Descricao = 'Windows 11 Pro 25H2 (build 26200.1)' }
            Cpu           = [pscustomobject]@{ Fabricante = 'amd'; Nome = 'AMD Ryzen 7 9800X3D 8-Core Processor'; Nucleos = 8; Threads = 16
                X3D = [pscustomobject]@{ EhX3D = $true; Modelo = '9800X3D'; Tipo = 'unico'; VCacheNosDois = $false; Fonte = 'lista' } }
            Gpus          = @([pscustomobject]@{ Fabricante = 'nvidia'; Nome = 'NVIDIA GeForce RTX 5070'; DriverAmigavel = '617.42'; DriverData = [datetime]'2026-09-29'; DiasDriver = 21; VramGB = 12; Integrada = $false })
            Memoria       = [pscustomobject]@{ TotalGB = 32; Modulos = @(
                    [pscustomobject]@{ CapacidadeGB = 16; Nominal = 6000; Configurada = 6000; Tipo = 'DDR5'; PartNumber = 'F5-6000J3038F16G'; PartNumberMTs = 6000; Slot = 'P0 CHANNEL A DIMM 1'; Canal = 'A' }
                    [pscustomobject]@{ CapacidadeGB = 16; Nominal = 6000; Configurada = 6000; Tipo = 'DDR5'; PartNumber = 'F5-6000J3038F16G'; PartNumberMTs = 6000; Slot = 'P0 CHANNEL B DIMM 1'; Canal = 'B' }
                ) }
            Armazenamento = [pscustomobject]@{
                Discos    = @([pscustomobject]@{ Numero = 0; Nome = 'NVMe 1TB'; Tipo = 'NVMe'; TamanhoGB = 1000 }, [pscustomobject]@{ Numero = 1; Nome = 'HD 2TB'; Tipo = 'HDD'; TamanhoGB = 2000 })
                Volumes   = @([pscustomobject]@{ Letra = 'C'; Disco = 0; TotalGB = 1000; LivreGB = 400 }, [pscustomobject]@{ Letra = 'D'; Disco = 1; TotalGB = 2000; LivreGB = 900 })
                TrimAtivo = $true
            }
            Monitores     = @([pscustomobject]@{ Nome = 'Monitor 1'; Largura = 2560; Altura = 1440; HzAtual = 165; HzMaximo = 165 })
            Seguranca     = [pscustomobject]@{ SecureBoot = $true; Tpm = [pscustomobject]@{ Presente = $true; Versao = '2.0'; Ativo = $true }; Vbs = $true; Hvci = $false }
            Plataforma    = [pscustomobject]@{ EhNotebook = $false; TemBateria = $false; PlacaMae = 'ASUS TUF B650' }
            Sistema       = [pscustomobject]@{ Hags = 'ligado'; ModoJogo = $true; GameDvr = $false
                PlanoEnergia = [pscustomobject]@{ Guid = '11111111-2222-3333-4444-555555555555'; Nome = 'Upgrade Warzone' }
                Paginacao = [pscustomobject]@{ Automatica = $true; Arquivos = @(); EmUso = $true } }
            Jogo          = [pscustomobject]@{ Instalacoes = @([pscustomobject]@{ Launcher = 'steam'; Caminho = 'C:\Steam\Call of Duty HQ'; Executaveis = @('C:\Steam\Call of Duty HQ\cod.exe')
                        Disco = [pscustomobject]@{ Letra = 'C'; LivreGB = 400; TotalGB = 1000; TipoDisco = 'NVMe' } }); Launchers = @('steam') }
            Erros         = @()
            GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = 'unico'
        }
        foreach ($k in $Change.Keys) { & $Change[$k] $hw }
        return $hw
    }

    function Get-Check($Hardware, [string]$Id) { @(Get-UTDiagnosticCheck -Hardware $Hardware | Where-Object { $_.Id -eq $Id })[0] }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Detecção de X3D' {
    BeforeEach { Reset-UTTestEnvironment }

    It '<Nome> -> <Esperado>' -TestCases @(
        @{ Nome = 'AMD Ryzen 7 9800X3D 8-Core Processor'; Nucleos = 8; Esperado = 'unico'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 7 5800X3D 8-Core Processor'; Nucleos = 8; Esperado = 'unico'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 7 7800X3D 8-Core Processor'; Nucleos = 8; Esperado = 'unico'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 9 7950X3D 16-Core Processor'; Nucleos = 16; Esperado = 'duplo'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 9 7900X3D 12-Core Processor'; Nucleos = 12; Esperado = 'duplo'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 9 9950X3D 16-Core Processor'; Nucleos = 16; Esperado = 'duplo'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 9 9950X3D2 16-Core Processor'; Nucleos = 16; Esperado = 'duplo'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 9 9955HX3D 16-Core Processor'; Nucleos = 16; Esperado = 'duplo'; Fonte = 'lista' }
        @{ Nome = 'AMD Ryzen 9 10950X3D 16-Core Processor'; Nucleos = 16; Esperado = 'duplo'; Fonte = 'nucleos' }
        @{ Nome = 'AMD Ryzen 7 10800X3D 8-Core Processor'; Nucleos = 8; Esperado = 'unico'; Fonte = 'nucleos' }
    ) {
        $r = Get-UTX3DInfo -Nome $Nome -Nucleos $Nucleos
        $r.EhX3D | Should -BeTrue
        $r.Tipo | Should -Be $Esperado
        $r.Fonte | Should -Be $Fonte
    }

    It 'marca o 9950X3D2 com V-Cache nos dois CCDs' {
        (Get-UTX3DInfo -Nome 'AMD Ryzen 9 9950X3D2 16-Core Processor' -Nucleos 16).VCacheNosDois | Should -BeTrue
    }

    It 'X3D desconhecido sem contagem de núcleos é tratado como dois CCDs (caminho seguro)' {
        (Get-UTX3DInfo -Nome 'AMD Ryzen 9 11950X3D' -Nucleos 0).Tipo | Should -Be 'duplo'
    }

    It 'não confunde <Nome> com X3D' -TestCases @(
        @{ Nome = 'AMD Ryzen 7 7800X 8-Core Processor' }
        @{ Nome = 'Intel(R) Core(TM) i9-14900K' }
        @{ Nome = '' }
    ) {
        (Get-UTX3DInfo -Nome $Nome -Nucleos 8).EhX3D | Should -BeFalse
    }
}

Describe 'Conversões' {
    It 'versão do driver NVIDIA: <Windows> -> <Nvidia>' -TestCases @(
        @{ Windows = '32.0.16.1742'; Nvidia = '617.42' }
        @{ Windows = '32.0.15.7342'; Nvidia = '573.42' }
        @{ Windows = '31.0.15.5222'; Nvidia = '552.22' }
        @{ Windows = '32.0.16.1003'; Nvidia = '610.03' }
    ) {
        ConvertTo-UTNvidiaDriverVersion -WindowsVersion $Windows | Should -Be $Nvidia
    }

    It 'velocidade pelo part number: <Pn> -> <Mts>' -TestCases @(
        @{ Pn = 'AX5U5600C468G-SLABRBK'; Mts = 5600 }
        @{ Pn = 'F5-6000J3038F16G'; Mts = 6000 }
        @{ Pn = 'CMK32GX5M2B6000C36'; Mts = 6000 }
        @{ Pn = 'CMK16GX4M2B3200C16'; Mts = 3200 }
        @{ Pn = 'KF560C36BBE-16'; Mts = 6000 }
        @{ Pn = 'KF432C16BB/8'; Mts = 3200 }
        @{ Pn = 'CT16G4DFRA32A'; Mts = $null }
        @{ Pn = ''; Mts = $null }
    ) {
        Get-UTPartNumberSpeed -PartNumber $Pn | Should -Be $Mts
    }
}

Describe 'Coletores (dados simulados)' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'memória: tipo, canais e velocidades' {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ BankLabel = 'P0 CHANNEL A'; DeviceLocator = 'DIMM 1'; Capacity = 17179869184; Speed = 4800; ConfiguredClockSpeed = 4800; SMBIOSMemoryType = 34; PartNumber = 'CMK32GX5M2B6000C36 '; Manufacturer = 'Corsair' }
                [pscustomobject]@{ BankLabel = 'P0 CHANNEL B'; DeviceLocator = 'DIMM 1'; Capacity = 17179869184; Speed = 4800; ConfiguredClockSpeed = 4800; SMBIOSMemoryType = 34; PartNumber = 'CMK32GX5M2B6000C36 '; Manufacturer = 'Corsair' }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' }
        $m = Get-UTMemoryInfo
        $m.TotalGB | Should -Be 32
        $m.Modulos[0].Tipo | Should -Be 'DDR5'
        ($m.Modulos | ForEach-Object Canal) | Should -Be @('A', 'B')
        $m.Modulos[0].PartNumberMTs | Should -Be 6000
    }

    It 'GPU: fabricante, idade do driver e integrada' {
        Mock Get-UTDisplayAdapterRegistry { @([pscustomobject]@{ Chave = 'K\0001'; Nome = 'NVIDIA GeForce RTX 5070'; MatchingDeviceId = 'pci\ven_10de'; VramBytes = 12884901888 }) }
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ Name = 'AMD Radeon(TM) Graphics'; PNPDeviceID = 'PCI\VEN_1002&DEV_13C0'; DriverVersion = '32.0.21042.62'; DriverDate = [datetime]'2026-04-16' }
                [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 5070'; PNPDeviceID = 'PCI\VEN_10DE&DEV_2F04'; DriverVersion = '32.0.16.1742'; DriverDate = [datetime]'2026-09-29' }
                [pscustomobject]@{ Name = 'Parsec Virtual Display Adapter'; PNPDeviceID = 'ROOT\DISPLAY\0000'; DriverVersion = '1'; DriverDate = $null }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        $g = @(Get-UTGpuInfo -Hoje ([datetime]'2026-10-20'))
        $g.Count | Should -Be 2
        $g[0].Integrada | Should -BeTrue
        $g[1].Fabricante | Should -Be 'nvidia'
        $g[1].DriverAmigavel | Should -Be '617.42'
        $g[1].DiasDriver | Should -Be 21
        $g[1].VramGB | Should -Be 12
    }

    It 'Get-UTHardwareInfo alimenta o contexto do motor só com as GPUs dedicadas' {
        $fake = New-FakeHardware
        Mock Get-UTCpuInfo { $fake.Cpu }
        Mock Get-UTGpuInfo { @([pscustomobject]@{ Fabricante = 'amd'; Nome = 'AMD Radeon(TM) Graphics'; Integrada = $true }) + $fake.Gpus }
        Mock Get-UTMemoryInfo { $fake.Memoria }
        Mock Get-UTStorageInfo { $fake.Armazenamento }
        Mock Get-UTDisplayInfo { $fake.Monitores }
        Mock Get-UTSecurityInfo { $fake.Seguranca }
        Mock Get-UTPlatformInfo { $fake.Plataforma }
        Mock Get-UTSystemSettingsInfo { $fake.Sistema }
        Mock Get-UTGameInfo { $fake.Jogo }
        Mock Get-UTWindowsInfo { $fake.Windows }
        $hw = Get-UTHardwareInfo
        $hw.GpuFabricantes | Should -Be @('nvidia')
        $ctx = Get-UTSystemContext
        $ctx.GpuFabricantes | Should -Be @('nvidia')
        $ctx.CpuFabricante | Should -Be 'amd'
        $ctx.X3D | Should -Be 'unico'
        $ctx.Launchers | Should -Be @('steam')
        $ctx.EhNotebook | Should -BeFalse
    }

    It 'um coletor que falha não derruba o diagnóstico' {
        Mock Get-UTCpuInfo { throw 'WMI quebrado' }
        Mock Get-UTGpuInfo { @() }
        Mock Get-UTMemoryInfo { $null }
        Mock Get-UTStorageInfo { $null }
        Mock Get-UTDisplayInfo { @() }
        Mock Get-UTSecurityInfo { $null }
        Mock Get-UTPlatformInfo { $null }
        Mock Get-UTSystemSettingsInfo { $null }
        Mock Get-UTGameInfo { $null }
        $hw = Get-UTHardwareInfo
        $hw.Cpu | Should -BeNullOrEmpty
        $hw.Erros | Should -Match 'processador'
        { Get-UTDiagnostic -Hardware $hw } | Should -Not -Throw
    }
}

Describe 'Launchers e executáveis' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'acha o CoD numa biblioteca secundária da Steam' {
        $steam = Join-Path $TestDrive 'Steam'
        $lib = Join-Path $TestDrive 'Lib2'
        New-Item -ItemType Directory -Force (Join-Path $steam 'steamapps'), (Join-Path $lib 'steamapps\common\Call of Duty HQ') | Out-Null
        $vdf = "`"libraryfolders`"`n{`n`t`"0`"`n`t{`n`t`t`"path`"`t`t`"$($steam.Replace('\','\\'))`"`n`t}`n`t`"1`"`n`t{`n`t`t`"path`"`t`t`"$($lib.Replace('\','\\'))`"`n`t}`n}"
        Set-Content -LiteralPath (Join-Path $steam 'steamapps\libraryfolders.vdf') -Value $vdf
        Set-Content -LiteralPath (Join-Path $lib 'steamapps\appmanifest_1938090.acf') -Value "`"AppState`"`n{`n`t`"appid`"`t`t`"1938090`"`n`t`"installdir`"`t`t`"Call of Duty HQ`"`n}"
        $libs = Get-UTSteamLibrary -SteamPath $steam.Replace('\', '/')
        $libs | Should -Be @($steam, $lib)
        $i = @(Get-UTSteamCodInstall -Bibliotecas $libs)
        $i.Count | Should -Be 1
        $i[0].Launcher | Should -Be 'steam'
        $i[0].Caminho | Should -Be (Join-Path $lib 'steamapps\common\Call of Duty HQ')
    }

    It 'lista só os executáveis do jogo' {
        $root = Join-Path $TestDrive 'HQ'
        New-Item -ItemType Directory -Force (Join-Path $root 'cod25'), (Join-Path $root 'sp26') | Out-Null
        foreach ($f in 'cod.exe', 'codCrashHandler.exe', 'bootstrapper.exe', 'CODSecureAttestationWizard.exe', 'cod25\cod25-cod.exe', 'cod25\codCrashHandler.exe', 'sp26\sp26-cod.exe') {
            Set-Content -LiteralPath (Join-Path $root $f) -Value 'x'
        }
        $exes = @(Get-UTCodExecutable -Caminho $root | ForEach-Object { Split-Path -Leaf $_ })
        $exes | Sort-Object | Should -Be @('cod.exe', 'cod25-cod.exe', 'sp26-cod.exe')
    }

    It 'Battle.net pelas entradas de desinstalação (ignora a Steam)' {
        $bnet = Join-Path $TestDrive 'Call of Duty'
        New-Item -ItemType Directory -Force $bnet | Out-Null
        $entries = @(
            [pscustomobject]@{ Chave = 'Call of Duty'; Nome = 'Call of Duty'; Fabricante = 'Blizzard Entertainment'; Local = $bnet }
            [pscustomobject]@{ Chave = 'Steam App 1938090'; Nome = 'Call of Duty®'; Fabricante = 'Treyarch'; Local = 'H:\SteamLibrary\steamapps\common\Call of Duty HQ' }
        )
        $i = @(Get-UTBattleNetCodInstall -Entradas $entries | Where-Object { $_.Caminho -eq $bnet })
        $i.Count | Should -Be 1
        $i[0].Launcher | Should -Be 'battlenet'
    }

    It 'Xbox App/Game Pass pela pasta XboxGames' {
        $root = Join-Path $TestDrive 'D'
        New-Item -ItemType Directory -Force (Join-Path $root 'XboxGames\Call of Duty\Content') | Out-Null
        $i = @(Get-UTXboxCodInstall -Raizes @($root))
        $i[0].Launcher | Should -Be 'xbox'
        $i[0].Caminho | Should -Match 'XboxGames\\Call of Duty\\Content$'
    }
}

Describe 'Verificações do diagnóstico' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'PC saudável tira 100 e não tem pendências' {
        $d = Get-UTDiagnostic -Hardware (New-FakeHardware)
        $d.Nota | Should -Be 100
        @($d.Pendencias).Count | Should -Be 0
        (Get-Check (New-FakeHardware) 'x3d').Mensagem | Should -Match 'um CCD'
    }

    It 'XMP/EXPO desligado (4800 com pentes de 6000) vira problema' {
        $hw = New-FakeHardware @{ x = { param($h) foreach ($m in $h.Memoria.Modulos) { $m.Configurada = 4800; $m.Nominal = 4800 } } }
        $c = Get-Check $hw 'xmp'
        $c.Status | Should -Be 'Problema'
        $c.Mensagem | Should -Match 'XMP/EXPO parece desativado'
        $c.Mensagem | Should -Match '4800'
        $c.Mensagem | Should -Match '6000'
    }

    It 'DDR5 a 4800 sem saber o nominal vira aviso' {
        $hw = New-FakeHardware @{ x = { param($h) foreach ($m in $h.Memoria.Modulos) { $m.Configurada = 4800; $m.Nominal = 4800; $m.PartNumberMTs = $null } } }
        (Get-Check $hw 'xmp').Status | Should -Be 'Aviso'
    }

    It 'em notebook o XMP é só informativo' {
        $hw = New-FakeHardware @{ x = { param($h) $h.EhNotebook = $true; foreach ($m in $h.Memoria.Modulos) { $m.Configurada = 4800; $m.Nominal = 4800 } } }
        (Get-Check $hw 'xmp').Status | Should -Be 'Info'
    }

    It 'um pente só = single channel' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Memoria.Modulos = @($h.Memoria.Modulos[0]); $h.Memoria.TotalGB = 16 } }
        (Get-Check $hw 'canal').Status | Should -Be 'Problema'
    }

    It 'dois pentes no mesmo canal geram aviso' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Memoria.Modulos[1].Canal = 'A' } }
        (Get-Check $hw 'canal').Mensagem | Should -Match 'mesmo canal'
    }

    It 'pentes diferentes geram aviso' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Memoria.Modulos[1].CapacidadeGB = 8 } }
        (Get-Check $hw 'pentes').Status | Should -Be 'Aviso'
    }

    It 'monitor em 60 Hz que suporta 144' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Monitores = @([pscustomobject]@{ Nome = 'AOC 24G2'; Largura = 1920; Altura = 1080; HzAtual = 60; HzMaximo = 144 }) } }
        $c = Get-Check $hw 'hz'
        $c.Status | Should -Be 'Problema'
        $c.Mensagem | Should -Match 'está em 60 Hz, mas suporta 144 Hz'
    }

    It 'jogo num HD mecânico' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Jogo.Instalacoes[0].Disco.TipoDisco = 'HDD' } }
        $c = Get-Check $hw 'jogohdd'
        $c.Status | Should -Be 'Problema'
        $c.Mensagem | Should -Match 'HD mecânico'
    }

    It 'Secure Boot desligado e TPM ausente (exigidos pelo CoD)' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Seguranca.SecureBoot = $false; $h.Seguranca.Tpm = [pscustomobject]@{ Presente = $false; Versao = $null; Ativo = $false } } }
        (Get-Check $hw 'secureboot').Status | Should -Be 'Problema'
        (Get-Check $hw 'tpm').Mensagem | Should -Match 'fTPM'
    }

    It 'paginação desativada' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Sistema.Paginacao = [pscustomobject]@{ Automatica = $false; Arquivos = @(); EmUso = $false } } }
        (Get-Check $hw 'paginacao').Status | Should -Be 'Problema'
    }

    It 'X3D de dois CCDs fora do Equilibrado' {
        $hw = New-FakeHardware @{ x = { param($h) $h.X3D = 'duplo'; $h.Cpu.X3D.Tipo = 'duplo' } }
        $c = Get-Check $hw 'energia'
        $c.Status | Should -Be 'Aviso'
        $c.Mensagem | Should -Match 'Equilibrado'
        $hw.Sistema.PlanoEnergia = [pscustomobject]@{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Nome = 'Equilibrado' }
        (Get-Check $hw 'energia').Status | Should -Be 'OK'
    }

    It 'driver de vídeo com mais de 90 dias' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Gpus[0].DiasDriver = 120 } }
        (Get-Check $hw 'driver').Mensagem | Should -Match '120 dias'
    }

    It 'RTX 50 com HAGS desligado' {
        $hw = New-FakeHardware @{ x = { param($h) $h.Sistema.Hags = 'desligado' } }
        (Get-Check $hw 'hags').Status | Should -Be 'Aviso'
    }

    It 'a nota cai conforme o peso e as pendências vêm em ordem de gravidade' {
        $hw = New-FakeHardware @{
            a = { param($h) $h.Monitores[0].HzAtual = 60 }
            b = { param($h) $h.Sistema.ModoJogo = $false }
        }
        $d = Get-UTDiagnostic -Hardware $hw
        $d.Nota | Should -BeLessThan 100
        $d.Nota | Should -BeGreaterThan 70
        $d.Pendencias[0].Id | Should -Be 'hz'
        $d.Pendencias[1].Id | Should -Be 'modojogo'
        $d.Pendencias[0].Aba | Should -Be 'Video'
    }
}

Describe 'Relatório' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'exporta TXT com nota, hardware e verificações' {
        $p = Join-Path $TestDrive 'relatorio.txt'
        $d = Get-UTDiagnostic -Hardware (New-FakeHardware @{ x = { param($h) $h.Monitores[0].HzAtual = 60 } })
        Export-UTDiagnosticReport -Path $p -Diagnostico $d | Should -Be $p
        $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        $t | Should -Match "NOTA DE OTIMIZAÇÃO: $($d.Nota)/100"
        $t | Should -Match 'Processador:\s+AMD Ryzen 7 9800X3D'
        $t | Should -Match '\[Problema\] Taxa de atualização'
    }

    It 'exporta HTML válido com texto escapado' {
        $p = Join-Path $TestDrive 'relatorio.html'
        $hw = New-FakeHardware @{ x = { param($h) $h.Computador = 'PC<script>' } }
        Export-UTDiagnosticReport -Path $p -Diagnostico (Get-UTDiagnostic -Hardware $hw) | Out-Null
        $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        $t | Should -Match '<html lang="pt-BR">'
        $t | Should -Match 'PC&lt;script&gt;'
        $t | Should -Not -Match 'PC<script>'
        $t | Should -Match 'Nota 100/100'
    }
}

Describe 'Leitura real deste PC (só leitura)' {
    BeforeAll { Reset-UTTestEnvironment }

    It 'coleta o hardware sem erro e gera uma nota de 0 a 100' {
        $hw = Get-UTHardwareInfo
        $hw.Cpu.Nome | Should -Not -BeNullOrEmpty
        @($hw.Gpus).Count | Should -BeGreaterThan 0
        $hw.Memoria.TotalGB | Should -BeGreaterThan 0
        @($hw.Monitores).Count | Should -BeGreaterThan 0
        $hw.Monitores[0].HzAtual | Should -BeGreaterThan 0
        $d = Get-UTDiagnostic -Hardware $hw
        $d.Nota | Should -BeGreaterOrEqual 0
        $d.Nota | Should -BeLessOrEqual 100
    }
}
