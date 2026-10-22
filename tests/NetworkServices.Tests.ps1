BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null; Executaveis = @('C:\Jogo\cod.exe') }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }
    function Use-EngineMocks {
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        Mock Backup-UTRegistryKey {}
        Mock Backup-UTServiceState {}
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Ajustes gerados a partir de services.json, apps-debloat.json e dns.json' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx }

    It 'um ajuste por serviço, mais o do Modo Lite' {
        $cfg = Get-UTConfig -Name 'services'
        $svc = @(Get-UTTweak | Where-Object { $_.id -like 'UT_Svc_*' })
        $svc.Count | Should -Be (@($cfg.servicos).Count + 1)
        (Get-UTTweak -Id 'UT_Svc_ModoLiteManual').servicos.Count | Should -Be @($cfg.modoLiteManual.servicos).Count
    }

    It 'serviços do Xbox ficam bloqueados quando o jogo é do Xbox App' {
        $t = Get-UTTweak -Id 'UT_Svc_XblAuthManager'
        $t.compatibilidade.launchersBloqueados | Should -Contain 'xbox'
        Set-Ctx @{ Launchers = @('xbox') }
        (Test-UTTweakCompatibility -Tweak $t -Contexto $UTSync.Contexto).Compativel | Should -BeFalse
    }

    It 'nunca lista GamingServices, GamingServicesNet nem XboxGipSvc' {
        $names = @((Get-UTConfig -Name 'services').servicos | ForEach-Object { $_.nome })
        foreach ($n in 'GamingServices', 'GamingServicesNet', 'XboxGipSvc') { $names | Should -Not -Contain $n }
    }

    It 'tipos de inicialização válidos em services.json' {
        $valid = 'Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled'
        foreach ($s in (Get-UTConfig -Name 'services').servicos) {
            $valid | Should -Contain $s.recomendado
            $valid | Should -Contain $s.padrao
        }
    }

    It 'nenhum app do debloat é protegido (Store, Xbox, Game Bar, Calculadora, Fotos, Terminal, winget...)' {
        $cfg = Get-UTConfig -Name 'apps-debloat'
        foreach ($a in $cfg.apps) { Test-UTAppxProtected -Pacote $a.pacote | Should -BeFalse -Because $a.pacote }
        foreach ($p in 'Microsoft.WindowsStore', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsTerminal', 'Microsoft.DesktopAppInstaller', 'Microsoft.VCLibs.140.00') {
            Test-UTAppxProtected -Pacote $p | Should -BeTrue -Because $p
        }
    }

    It 'cinco provedores de DNS exclusivos entre si' {
        $dns = @(Get-UTTweak | Where-Object { $_.id -like 'UT_Net_DNS_*' })
        $dns.Count | Should -Be 5
        @($dns | Where-Object { $_.grupoExclusivo -ne 'dns' }).Count | Should -Be 0
    }
}

Describe 'Serviços pelo motor' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks
        $script:svc = @{ DiagTrack = 'Automatic' }
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $script:svc.ContainsKey($Name); StartType = $script:svc[$Name]; Status = 'Running' } }
        Mock Set-UTServiceStartType { $script:svc[$Name] = $StartType }
    }

    It 'desativa e volta ao tipo real que o serviço tinha' {
        (Invoke-UTTweak -Id 'UT_Svc_DiagTrack').Status | Should -Be 'Aplicado'
        $script:svc.DiagTrack | Should -Be 'Disabled'
        Undo-UTTweak -Id 'UT_Svc_DiagTrack' | Out-Null
        $script:svc.DiagTrack | Should -Be 'Automatic'
    }

    It 'telemetria do catálogo e o serviço isolado compartilham o original' {
        $script:svc.DiagTrack = 'AutomaticDelayedStart'
        Invoke-UTTweak -Id 'UT_Svc_DiagTrack' | Out-Null
        (Undo-UTTweak -Id 'UT_Svc_DiagTrack').Status | Should -Be 'Desfeito'
        $script:svc.DiagTrack | Should -Be 'AutomaticDelayedStart'
    }
}

Describe 'Debloat de apps' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks
        $script:installed = @('Clipchamp.Clipchamp')
        Mock Get-AppxPackage { @($script:installed | Where-Object { $_ -eq $Name } | ForEach-Object { [pscustomobject]@{ Name = $_; PackageFullName = "${_}_1.0_x64__abc" } }) }
        Mock Remove-AppxPackage { $script:installed = @($script:installed | Where-Object { "${_}_1.0_x64__abc" -ne $Package }) }
        Mock Get-AppxProvisionedPackage { @() }
        Mock Invoke-UTNative { $script:installed += 'Clipchamp.Clipchamp'; [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } } -ParameterFilter { $FilePath -eq 'winget.exe' }
        Mock Get-Command { [pscustomobject]@{ Name = 'winget.exe' } } -ParameterFilter { $Name -eq 'winget.exe' }
    }

    It 'remove de todos os usuários e o desfazer reinstala pela Store' {
        (Invoke-UTTweak -Id 'UT_App_Clipchamp_Clipchamp').Status | Should -Be 'Aplicado'
        $script:installed | Should -Not -Contain 'Clipchamp.Clipchamp'
        Should -Invoke Remove-AppxPackage -Times 1 -ParameterFilter { $AllUsers }
        (Undo-UTTweak -Id 'UT_App_Clipchamp_Clipchamp').Status | Should -Be 'Desfeito'
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { ($ArgumentList -join ' ') -match '--id 9P1J8S7CCWWT --source msstore' }
    }

    It 'recusa remover app protegido mesmo chamado direto' {
        { Remove-UTAppxPackage -Pacote 'Microsoft.WindowsStore' -TweakId 'x' } | Should -Throw '*protegido*'
        { Remove-UTAppxPackage -Pacote 'Microsoft.GamingApp' -TweakId 'x' } | Should -Throw '*protegido*'
    }
}

Describe 'Placa de rede (nomes por fabricante)' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks
        $script:props = @{
            'Ethernet' = @{ '*EEE' = '1'; 'EnableGreenEthernet' = '1'; 'GigaLite' = '1'; '*InterruptModeration' = '1'; '*RSS' = '1'; '*WakeOnMagicPacket' = '1'; '*FlowControl' = '3' }
            'Wi-Fi'    = @{ 'EEELinkAdvertisement' = '1'; '*WakeOnPattern' = '1' }
        }
        Mock Get-UTPhysicalAdapter { @([pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Realtek Gaming 2.5GbE'; InterfaceGuid = '{E}' }, [pscustomobject]@{ Name = 'Wi-Fi'; InterfaceDescription = 'Intel Wi-Fi 6E'; InterfaceGuid = '{W}' }) }
        Mock Get-NetAdapterAdvancedProperty {
            foreach ($k in $script:props[[string]@($Name)[0]].Keys) {
                [pscustomobject]@{ RegistryKeyword = $k; DisplayName = "Nome $k"; RegistryValue = @($script:props[[string]@($Name)[0]][$k]); ValidRegistryValues = @('0', '1', '3') }
            }
        }
        Mock Set-NetAdapterAdvancedProperty { $script:props[[string]@($Name)[0]][[string]@($RegistryKeyword)[0]] = [string]@($RegistryValue)[0] }
        Mock Restart-NetAdapter {}
        Mock Get-UTNicClassKey { "$UTTestKey\Class\$InterfaceGuid" }
    }

    It 'desliga a economia de energia que existe em cada placa e o desfazer volta tudo' {
        Test-UTNicAdvancedProperty -Conjunto EconomiaEnergia | Should -BeFalse
        (Invoke-UTTweak -Id 'UT_Net_NicPowerSaving_Off').Status | Should -Be 'Aplicado'
        $script:props.Ethernet['*EEE'] | Should -Be '0'
        $script:props.Ethernet['GigaLite'] | Should -Be '0'
        $script:props['Wi-Fi']['EEELinkAdvertisement'] | Should -Be '0'
        $script:props.Ethernet['*FlowControl'] | Should -Be '3'
        (Get-UTRegistryValue "$UTTestKey\Class\{E}" 'PnPCapabilities').Valor | Should -Be 24
        Should -Invoke Restart-NetAdapter -Times 2
        (Undo-UTTweak -Id 'UT_Net_NicPowerSaving_Off').Status | Should -Be 'Desfeito'
        $script:props.Ethernet['*EEE'] | Should -Be '1'
        $script:props['Wi-Fi']['EEELinkAdvertisement'] | Should -Be '1'
        (Get-UTRegistryValue "$UTTestKey\Class\{E}" 'PnPCapabilities').ValorExiste | Should -BeFalse
    }

    It 'opção que a placa não tem vira mensagem clara' {
        $script:props.Ethernet.Remove('*InterruptModeration')
        $r = Invoke-UTTweak -Id 'UT_Net_InterruptModeration_Off'
        $r.Status | Should -Be 'Falhou'
        $r.Mensagem | Should -Match 'não tem esta opção'
    }
}

Describe 'IPv6 DisabledComponents (bits compartilhados)' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks
        $script:dc = 0
        $script:dcExists = $true
        Mock Get-UTRegistryValue { [pscustomobject]@{ Caminho = $Path; Nome = $Name; ChaveExiste = $true; ValorExiste = $script:dcExists; Tipo = 'DWord'; Valor = $script:dc } } -ParameterFilter { $Name -eq 'DisabledComponents' }
        Mock Set-UTRegistryValue { $script:dc = [int64]$Value; $script:dcExists = $true } -ParameterFilter { $Name -eq 'DisabledComponents' }
        Mock Get-UTFirstMissingKey { $null }
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } } -ParameterFilter { $FilePath -eq 'netsh.exe' }
    }

    It 'IPv4 preferido e Teredo convivem; cada desfazer só tira o próprio bit' {
        (Invoke-UTTweak -Id 'UT_Net_PreferIPv4').Status | Should -Be 'Aplicado'
        $script:dc | Should -Be 32
        (Invoke-UTTweak -Id 'UT_Net_Teredo_Off').Status | Should -Be 'Aplicado'
        $script:dc | Should -Be 33
        Undo-UTTweak -Id 'UT_Net_PreferIPv4' | Out-Null
        $script:dc | Should -Be 1
        (Get-UTTweakState -Id 'UT_Net_Teredo_Off').Estado | Should -Be 'Aplicado'
        Undo-UTTweak -Id 'UT_Net_Teredo_Off' | Out-Null
        $script:dc | Should -Be 0
    }

    It 'Teredo e IPv6 desligado ficam bloqueados com Xbox App' {
        Set-Ctx @{ Launchers = @('xbox') }
        (Invoke-UTTweak -Id 'UT_Net_Teredo_Off').Status | Should -Be 'Ignorado'
        (Invoke-UTTweak -Id 'UT_Net_IPv6_Off' -RiscoAltoConfirmado).Status | Should -Be 'Ignorado'
    }
}

Describe 'Nagle e QoS' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks }

    It 'Nagle: grava nas interfaces ativas e o desfazer limpa' {
        Mock Get-UTActiveInterfaceKey { "$UTTestKey\Interfaces\{A}" }
        (Invoke-UTTweak -Id 'UT_Net_Nagle_Off').Status | Should -Be 'Aplicado'
        (Get-UTRegistryValue "$UTTestKey\Interfaces\{A}" 'TCPNoDelay').Valor | Should -Be 1
        Undo-UTTweak -Id 'UT_Net_Nagle_Off' | Out-Null
        Test-UTRegistryKey -Path "$UTTestKey\Interfaces" | Should -BeFalse
    }

    It 'QoS: uma política DSCP 46 por executável do jogo' {
        Set-Ctx @{ Executaveis = @('C:\Jogo\cod.exe', 'C:\Jogo\cod25\cod25-cod.exe') }
        $script:qos = @{}
        Mock Get-NetQosPolicy { if ($Name) { $n = [string]@($Name)[0]; if ($script:qos.ContainsKey($n)) { [pscustomobject]@{ Name = $n; DSCPAction = 46 } } } else { $script:qos.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; DSCPAction = 46 } } } }
        Mock New-NetQosPolicy { $script:qos[$Name] = $AppPathNameMatchCondition }
        Mock Remove-NetQosPolicy { $script:qos.Remove([string]@($Name)[0]) }
        Mock Set-UTRegistryValueTracked {}
        Mock Restore-UTTweakRegistryItem { 0 }
        (Invoke-UTTweak -Id 'UT_Net_QoS_CoD').Status | Should -Be 'Aplicado'
        $script:qos.Keys | Sort-Object | Should -Be @('Upgrade Tweaks - cod.exe', 'Upgrade Tweaks - cod25-cod.exe')
        Undo-UTTweak -Id 'UT_Net_QoS_CoD' | Out-Null
        $script:qos.Count | Should -Be 0
    }
}

Describe 'DNS' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks
        $script:dns = @{ '{A}' = @() }
        Mock Get-UTDnsTargetInterface { @([pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7; InterfaceGuid = '{A}' }) }
        Mock Get-NetAdapter { @([pscustomobject]@{ Name = 'Ethernet'; ifIndex = 7; InterfaceGuid = '{A}' }) }
        Mock Get-UTInterfaceDnsState { [pscustomobject]@{ Ipv4 = @($script:dns[$InterfaceGuid] | Where-Object { $_ -notmatch ':' }); Ipv6 = @($script:dns[$InterfaceGuid] | Where-Object { $_ -match ':' }) } }
        Mock Set-DnsClientServerAddress { if ($ResetServerAddresses) { $script:dns['{A}'] = @() } else { $script:dns['{A}'] = @($ServerAddresses) } }
        Mock Clear-DnsClientCache {}
    }

    It 'aplica o Cloudflare e o desfazer volta para o DHCP' {
        (Invoke-UTTweak -Id 'UT_Net_DNS_Cloudflare').Status | Should -Be 'Aplicado'
        $script:dns['{A}'][0] | Should -Be '1.1.1.1'
        $script:dns['{A}'] | Should -Contain '2606:4700:4700::1111'
        Undo-UTTweak -Id 'UT_Net_DNS_Cloudflare' | Out-Null
        @($script:dns['{A}']).Count | Should -Be 0
    }

    It 'trocar de provedor desfaz o anterior e mantém o DNS original do usuário' {
        $script:dns['{A}'] = @('192.168.0.1')
        Invoke-UTTweak -Id 'UT_Net_DNS_Cloudflare' | Out-Null
        (Invoke-UTTweak -Id 'UT_Net_DNS_Google').Status | Should -Be 'Aplicado'
        $script:dns['{A}'][0] | Should -Be '8.8.8.8'
        (Get-UTAppliedRecord).tweakId | Should -Be 'UT_Net_DNS_Google'
        Undo-UTTweak -Id 'UT_Net_DNS_Google' | Out-Null
        $script:dns['{A}'] | Should -Be @('192.168.0.1')
    }
}

Describe 'Teste de latência' {
    It 'calcula perda, média e jitter' {
        $s = Get-UTLatencyStat -Alvo 'x' -Enviados 5 -Amostras @(10, 12, 11, 30)
        $s.PerdaPct | Should -Be 20
        $s.MediaMs | Should -Be 15.8
        $s.MinMs | Should -Be 10
        $s.MaxMs | Should -Be 30
        $s.JitterMs | Should -Be 7.3
    }

    It 'sem respostas não quebra' {
        $s = Get-UTLatencyStat -Alvo 'x' -Enviados 3 -Amostras @()
        $s.PerdaPct | Should -Be 100
        $s.MediaMs | Should -BeNullOrEmpty
    }

    It 'ping real em 127.0.0.1 e informações da conexão (só leitura)' {
        # On a busy CI runner the first reply can miss the 1 s timeout; one reply proves the real ping works.
        $r = Measure-UTPing -Alvo '127.0.0.1' -Quantidade 3
        $r.Enviados | Should -Be 3
        $r.Recebidos | Should -BeGreaterThan 0
        { Get-UTNetworkInfo } | Should -Not -Throw
    }
}

Describe 'OneDrive, Edge e Logitech' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx; Use-EngineMocks }

    It 'recusa remover o OneDrive quando os Documentos estão nele' {
        Mock Test-UTOneDriveFolderBackup { $true }
        Mock Test-UTOneDriveInstalled { $true }
        $r = Invoke-UTTweak -Id 'UT_Lite_RemoveOneDrive'
        $r.Status | Should -Be 'Falhou'
        $r.Mensagem | Should -Match 'backup de pastas'
    }

    It 'detecta Documentos dentro do OneDrive pelo caminho' {
        Mock Get-Variable { $null } -ParameterFilter { $Name -eq 'UTSync' }
        $env:OneDrive = 'C:\Users\x\OneDrive'
        try {
            # This PC has Documents inside OneDrive; any machine with "\OneDrive\" in the path counts.
            $docs = [Environment]::GetFolderPath('MyDocuments')
            (Test-UTOneDriveFolderBackup) | Should -Be ($docs -match '\\OneDrive( - [^\\]+)?\\' -or $docs.StartsWith($env:OneDrive, [StringComparison]::OrdinalIgnoreCase))
        } finally { $env:OneDrive = $null }
    }

    It 'Edge: sem instalador encontrado, não faz nada' {
        Mock Get-UTEdgeSetupPath { $null }
        Mock Invoke-UTNative {}
        Remove-UTEdge -TweakId 'x'
        Should -Invoke Invoke-UTNative -Times 0
    }

    It 'Logitech: cria a pasta bloqueada quando não existia' {
        $folder = Join-Path $TestDrive 'LogiDownloadAssistant'
        Mock Get-UTLogiFolder { $folder }
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } } -ParameterFilter { $FilePath -eq 'icacls.exe' }
        Set-UTLogiBlock -TweakId 'UT_L'
        Test-Path -LiteralPath $folder | Should -BeTrue
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { ($ArgumentList -join ' ') -eq "$folder /deny *S-1-1-0:(W)" }
        Restore-UTLogiBlock -TweakId 'UT_L'
        Test-Path -LiteralPath $folder | Should -BeFalse
    }
}

Describe 'Gerenciador de inicialização' {
    BeforeEach {
        Reset-UTTestEnvironment
        $folder = Join-Path $TestDrive ('Startup' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'Discord.lnk') -Value 'x'
        Set-UTRegistryValue -Path "$UTTestKey\U\Microsoft\Windows\CurrentVersion\Run" -Name 'Steam' -Type String -Value '"C:\Steam\steam.exe" -silent'
        Set-UTRegistryValue -Path "$UTTestKey\U\Microsoft\Windows\CurrentVersion\Run" -Name 'OneDrive' -Type String -Value 'C:\OneDrive.exe'
        $sources = Get-UTStartupSource -RaizUsuario "$UTTestKey\U" -RaizMaquina "$UTTestKey\M" -PastaUsuario $folder -PastaComum (Join-Path $TestDrive 'nao-existe')
    }

    It 'lista Run e pasta Inicializar, todos ativos por padrão' {
        $items = @(Get-UTStartupItem -Fontes $sources -SemTarefas)
        ($items | ForEach-Object Nome | Sort-Object) | Should -Be @('Discord.lnk', 'OneDrive', 'Steam')
        @($items | Where-Object { -not $_.Ativo }).Count | Should -Be 0
    }

    It 'desativa e reativa pelo StartupApproved (igual ao Gerenciador de Tarefas)' {
        $steam = @(Get-UTStartupItem -Fontes $sources -SemTarefas | Where-Object Nome -eq 'Steam')[0]
        Set-UTStartupItemState -Item $steam -Ativo $false
        $v = Get-UTRegistryValue -Path $steam.Aprovacao -Name 'Steam'
        $v.Tipo | Should -Be 'Binary'
        $v.Valor | Should -Match '^03000000'
        (@(Get-UTStartupItem -Fontes $sources -SemTarefas | Where-Object Nome -eq 'Steam')[0]).Ativo | Should -BeFalse
        Set-UTStartupItemState -Item $steam -Ativo $true
        (@(Get-UTStartupItem -Fontes $sources -SemTarefas | Where-Object Nome -eq 'Steam')[0]).Ativo | Should -BeTrue
    }

    It 'tarefas agendadas de logon usam Disable/Enable-ScheduledTask' {
        Mock Disable-ScheduledTask {}
        $task = [pscustomobject]@{ Nome = 'Atualizador'; Tipo = 'tarefa'; Tarefa = '\Fabricante\Atualizador'; Aprovacao = $null }
        Set-UTStartupItemState -Item $task -Ativo $false
        Should -Invoke Disable-ScheduledTask -Times 1 -ParameterFilter { $TaskPath -eq '\Fabricante\' -and $TaskName -eq 'Atualizador' }
    }
}
