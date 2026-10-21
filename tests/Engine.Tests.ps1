BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    function Reset-UTEngineTest {
        Reset-UTTestEnvironment
        $env:UPGRADETWEAKS_CONFIG_DIR = Join-Path $PSScriptRoot 'fixtures'
        $UTSync.Contexto = [pscustomobject]@{
            WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'
            EhNotebook = $false; Launchers = @('steam'); X3D = $null
        }
        Set-UTRegistryValue -Path "$UTTestKey\Existente" -Name 'Valor' -Type DWord -Value 1
        Set-UTRegistryValue -Path "$UTTestKey\Existente" -Name 'Apagar' -Type String -Value 'meu valor'
    }

    function Get-Val([string]$Sub, [string]$Name) { Get-UTRegistryValue -Path "$UTTestKey\$Sub" -Name $Name }
}

AfterAll {
    $env:UPGRADETWEAKS_CONFIG_DIR = $null
    Clear-UTTestEnvironment
}

Describe 'Motor de tweaks' {
    BeforeEach {
        Reset-UTEngineTest
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
    }

    It 'aplicar -> detectar -> desfazer -> detectar (registro)' {
        (Get-UTTweakState -Id 'UT_Test_Reg').Estado | Should -Be 'NaoAplicado'

        $r = Invoke-UTTweak -Id 'UT_Test_Reg'
        $r.Status | Should -Be 'Aplicado'
        (Get-UTTweakState -Id 'UT_Test_Reg').Estado | Should -Be 'Aplicado'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 0
        (Get-Val 'Nova\Sub' 'Texto').Valor | Should -Be 'ligado'
        (Get-UTAppliedRecord).tweakId | Should -Be 'UT_Test_Reg'

        $u = Undo-UTTweak -Id 'UT_Test_Reg'
        $u.Status | Should -Be 'Desfeito'
        (Get-UTTweakState -Id 'UT_Test_Reg').Estado | Should -Be 'NaoAplicado'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
        Test-UTRegistryKey -Path "$UTTestKey\Nova" | Should -BeFalse
        @(Get-UTAppliedRecord).Count | Should -Be 0
        @((Read-UTOriginalState).itens.Keys).Count | Should -Be 0
    }

    It 'aplicar duas vezes é idempotente' {
        (Invoke-UTTweak -Id 'UT_Test_Reg').Status | Should -Be 'Aplicado'
        (Invoke-UTTweak -Id 'UT_Test_Reg').Status | Should -Be 'JaAplicado'
        Undo-UTTweak -Id 'UT_Test_Reg' | Out-Null
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
    }

    It 'o desfazer volta o valor REAL do usuário, não o padrão do tweaks.json' {
        Set-UTRegistryValue -Path "$UTTestKey\Existente" -Name 'Valor' -Type DWord -Value 42
        Invoke-UTTweak -Id 'UT_Test_Reg' | Out-Null
        Undo-UTTweak -Id 'UT_Test_Reg' | Out-Null
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 42
    }

    It 'sem estado salvo, o desfazer usa o valorOriginal (e apaga quando é null)' {
        Set-UTRegistryValue -Path "$UTTestKey\Existente" -Name 'Valor' -Type DWord -Value 0
        Set-UTRegistryValue -Path "$UTTestKey\Nova\Sub" -Name 'Texto' -Type String -Value 'ligado'
        (Get-UTTweakState -Id 'UT_Test_Reg').Estado | Should -Be 'Aplicado'
        (Undo-UTTweak -Id 'UT_Test_Reg').Status | Should -Be 'Desfeito'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
        (Get-Val 'Nova\Sub' 'Texto').ValorExiste | Should -BeFalse
    }

    It 'acao remover: apaga o valor e o desfazer devolve o que o usuário tinha' {
        $r = Invoke-UTTweak -Id 'UT_Test_Remover'
        $r.Status | Should -Be 'Aplicado'
        $r.RequerReinicio | Should -BeTrue
        (Get-Val 'Existente' 'Apagar').ValorExiste | Should -BeFalse
        Undo-UTTweak -Id 'UT_Test_Remover' | Out-Null
        (Get-Val 'Existente' 'Apagar').Valor | Should -Be 'meu valor'
    }

    It 'valor ausente que equivale ao padrão do Windows conta como aplicado' {
        (Get-UTTweakState -Id 'UT_Test_Ausente').Estado | Should -Be 'Aplicado'
        (Invoke-UTTweak -Id 'UT_Test_Ausente').Status | Should -Be 'JaAplicado'
        Set-UTRegistryValue -Path "$UTTestKey\Ausente" -Name 'Ligado' -Type DWord -Value 0
        (Get-UTTweakState -Id 'UT_Test_Ausente').Estado | Should -Be 'NaoAplicado'
        (Invoke-UTTweak -Id 'UT_Test_Ausente').Status | Should -Be 'Aplicado'
        (Get-Val 'Ausente' 'Ligado').Valor | Should -Be 1
    }

    It 'desfazer o que não está aplicado não mexe em nada' {
        (Undo-UTTweak -Id 'UT_Test_Reg').Status | Should -Be 'NaoAplicado'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
    }

    It 'simular (-WhatIf) lista as ações e não altera nada' {
        $r = Invoke-UTTweak -Id 'UT_Test_Reg' -WhatIf
        $r.Status | Should -Be 'Simulado'
        $r.Acoes | Should -Contain "$UTTestKey\Existente\Valor: 1 -> 0".Insert(0, 'Registro ')
        $r.Acoes | Should -Contain "Registro $UTTestKey\Nova\Sub\Texto: <ausente> -> ligado"
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
        @(Get-UTAppliedRecord).Count | Should -Be 0
        Test-Path -LiteralPath (Get-UTStateFilePath -Name 'estado-original') | Should -BeFalse
        Should -Invoke Invoke-UTPreApplySafety -Times 0
    }

    It 'simular o desfazer mostra para onde cada valor volta' {
        Invoke-UTTweak -Id 'UT_Test_Reg' | Out-Null
        $u = Undo-UTTweak -Id 'UT_Test_Reg' -WhatIf
        $u.Status | Should -Be 'Simulado'
        $u.Acoes | Should -Contain "Registro $UTTestKey\Existente\Valor -> 1 (valor salvo)"
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 0
    }

    It 'risco alto só é aplicado com confirmação' {
        $r = Invoke-UTTweak -Id 'UT_Test_Alto'
        $r.Status | Should -Be 'PrecisaConfirmacao'
        $r.Mensagem | Should -Be 'Isto é perigoso. Confirma?'
        (Get-Val 'Alto' 'Ligado').ValorExiste | Should -BeFalse
        (Invoke-UTTweak -Id 'UT_Test_Alto' -RiscoAltoConfirmado).Status | Should -Be 'Aplicado'
    }

    It 'tweak incompatível é ignorado com o motivo' {
        $r = Invoke-UTTweak -Id 'UT_Test_Win10'
        $r.Status | Should -Be 'Ignorado'
        $r.Mensagem | Should -Match 'Windows 10'
        (Get-UTTweakState -Id 'UT_Test_Win10').Estado | Should -Be 'Incompativel'
    }

    It 'regra do Xbox App: bloqueia quando o launcher é Xbox' {
        $UTSync.Contexto.Launchers = @('xbox')
        (Invoke-UTTweak -Id 'UT_Test_Xbox').Status | Should -Be 'Ignorado'
        $UTSync.Contexto.Launchers = @('battlenet')
        (Invoke-UTTweak -Id 'UT_Test_Xbox').Status | Should -Be 'Aplicado'
    }

    It 'falha no meio desfaz o que já tinha sido mudado e não interrompe os outros' {
        $r = @(Invoke-UTTweak -Id 'UT_Test_Quebra', 'UT_Test_Remover')
        $r[0].Status | Should -Be 'Falhou'
        $r[1].Status | Should -Be 'Aplicado'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
        (Get-UTAppliedRecord).tweakId | Should -Be 'UT_Test_Remover'
        @((Read-UTOriginalState).itens.Keys | Where-Object { $_ -match '\|valor$' }).Count | Should -Be 0
    }

    It 'quando o Windows não mantém a alteração, falha com explicação e volta tudo' {
        Mock Set-UTRegistryValue {} -ParameterFilter { $Value -eq 'ligado' }
        $r = Invoke-UTTweak -Id 'UT_Test_Reg'
        $r.Status | Should -Be 'Falhou'
        $r.Mensagem | Should -Match 'não manteve a alteração'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
        @(Get-UTAppliedRecord).Count | Should -Be 0
    }

    It 'tweak com script guarda o original como item genérico e desfaz' {
        Set-UTRegistryValue -Path "$UTTestKey\Script" -Name 'Modo' -Type String -Value 'normal'
        (Invoke-UTTweak -Id 'UT_Test_Script').Status | Should -Be 'Aplicado'
        (Get-Val 'Script' 'Modo').Valor | Should -Be 'rapido'
        (Get-UTTweakState -Id 'UT_Test_Script').Estado | Should -Be 'Aplicado'
        (Undo-UTTweak -Id 'UT_Test_Script').Status | Should -Be 'Desfeito'
        (Get-Val 'Script' 'Modo').Valor | Should -Be 'normal'
    }

    It 'grupo exclusivo: aplicar B desfaz A antes' {
        (Invoke-UTTweak -Id 'UT_Test_GrupoA').Status | Should -Be 'Aplicado'
        (Invoke-UTTweak -Id 'UT_Test_GrupoB').Status | Should -Be 'Aplicado'
        (Get-UTAppliedRecord).tweakId | Should -Be 'UT_Test_GrupoB'
        (Get-Val 'Grupo' 'Modo').Valor | Should -Be 2
        Undo-UTTweak -Id 'UT_Test_GrupoB' | Out-Null
        (Get-Val 'Grupo' 'Modo').ValorExiste | Should -BeFalse
    }

    It 'Desfazer TUDO reverte na ordem inversa da aplicação' {
        Set-UTRegistryValue -Path "$UTTestKey\Script" -Name 'Modo' -Type String -Value 'normal'
        Invoke-UTTweak -Id 'UT_Test_Reg', 'UT_Test_Remover', 'UT_Test_Script' | Out-Null
        $r = @(Undo-UTAllTweak)
        ($r | ForEach-Object { $_.Id }) | Should -Be @('UT_Test_Script', 'UT_Test_Remover', 'UT_Test_Reg')
        @($r | Where-Object { $_.Status -ne 'Desfeito' }).Count | Should -Be 0
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
        (Get-Val 'Existente' 'Apagar').Valor | Should -Be 'meu valor'
        (Get-Val 'Script' 'Modo').Valor | Should -Be 'normal'
        @(Get-UTAppliedRecord).Count | Should -Be 0
    }

    It 'Desfazer TUDO também restaura tweak que saiu do catálogo, pelo estado salvo' {
        Set-UTRegistryValue -Path "$UTTestKey\Velho" -Name 'v' -Type DWord -Value 3
        [void](Save-UTOriginalRegistryValue -Path "$UTTestKey\Velho" -Name 'v' -TweakId 'UT_Removido')
        Add-UTAppliedRecord -TweakId 'UT_Removido'
        Set-UTRegistryValue -Path "$UTTestKey\Velho" -Name 'v' -Type DWord -Value 0
        Undo-UTAllTweak | Out-Null
        (Get-Val 'Velho' 'v').Valor | Should -Be 3
        @(Get-UTAppliedRecord).Count | Should -Be 0
    }

    It 'checa admin antes de cada aplicação' {
        Mock Assert-UTAdmin { throw 'O Upgrade Tweaks precisa ser executado como administrador. Nenhuma alteração foi feita.' }
        $r = Invoke-UTTweak -Id 'UT_Test_Reg'
        $r.Status | Should -Be 'Falhou'
        $r.Mensagem | Should -Match 'administrador'
        (Get-Val 'Existente' 'Valor').Valor | Should -Be 1
    }

    It 'id inexistente vira erro claro' {
        { Invoke-UTTweak -Id 'UT_NaoExiste' } | Should -Throw "*não existe no catálogo*"
    }
}

Describe 'Motor de tweaks: serviços' {
    BeforeEach {
        Reset-UTEngineTest
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
        Mock Backup-UTServiceState {}
        $script:fakeType = 'Manual'
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = $script:fakeType; Status = 'Running' } }
        Mock Invoke-UTNative {
            if ($ArgumentList[0] -eq 'config') {
                $map = @{ auto = 'Automatic'; 'delayed-auto' = 'AutomaticDelayedStart'; demand = 'Manual'; disabled = 'Disabled' }
                $script:fakeType = $map[$ArgumentList[3]]
            }
            [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' }
        }
        Mock Stop-Service {}
    }

    It 'desativa e para o serviço, e o desfazer volta ao tipo salvo' {
        (Invoke-UTTweak -Id 'UT_Test_Servico').Status | Should -Be 'Aplicado'
        $script:fakeType | Should -Be 'Disabled'
        Should -Invoke Stop-Service -Times 1
        (Undo-UTTweak -Id 'UT_Test_Servico').Status | Should -Be 'Desfeito'
        $script:fakeType | Should -Be 'Manual'
    }

    It 'serviço inexistente conta como feito e não chama o sc.exe' {
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $false; StartType = $null; Status = $null } }
        (Get-UTTweakState -Id 'UT_Test_Servico').Estado | Should -Be 'Aplicado'
        (Invoke-UTTweak -Id 'UT_Test_Servico').Status | Should -Be 'JaAplicado'
        Should -Invoke Invoke-UTNative -Times 0
    }

    It 'dois ajustes com os mesmos valores: desfazer um não desfaz o outro' {
        Set-UTRegistryValue -Path "$UTTestKey\Shared" -Name 'outro' -Type DWord -Value 1
        (Invoke-UTTweak -Id 'UT_Test_ShareA').Status | Should -Be 'Aplicado'
        (Invoke-UTTweak -Id 'UT_Test_ShareB').Status | Should -Be 'JaAplicado'
        (Get-UTAppliedRecord).tweakId | Should -Be @('UT_Test_ShareA', 'UT_Test_ShareB')
        Undo-UTTweak -Id 'UT_Test_ShareA' | Out-Null
        (Get-UTTweakState -Id 'UT_Test_ShareB').Estado | Should -Be 'Aplicado'
        $script:fakeType | Should -Be 'Disabled'
        Undo-UTTweak -Id 'UT_Test_ShareB' | Out-Null
        (Get-UTRegistryValue "$UTTestKey\Shared" 'V').ValorExiste | Should -BeFalse
        $script:fakeType | Should -Be 'Manual'
    }

    It 'valor que o usuário já tinha (nada salvo) continua "já aplicado" sem entrar no registro' {
        Set-UTRegistryValue -Path "$UTTestKey\Shared" -Name 'V' -Type DWord -Value 1
        $script:fakeType = 'Disabled'
        (Invoke-UTTweak -Id 'UT_Test_ShareB').Status | Should -Be 'JaAplicado'
        @(Get-UTAppliedRecord).Count | Should -Be 0
    }

    It 'serviço protegido falha com a mensagem amigável' {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 5; Saida = 'Acesso negado'; Erro = '' } }
        $r = Invoke-UTTweak -Id 'UT_Test_Servico'
        $r.Status | Should -Be 'Falhou'
        $r.Mensagem | Should -Be 'Não foi possível alterar o serviço UTFakeSvc porque ele é protegido pelo sistema.'
    }
}

Describe 'Get-UTRunSummary' {
    It 'monta o resumo em PT-BR com aviso de reinício' {
        $results = @(
            [pscustomobject]@{ Nome = 'A'; Status = 'Aplicado'; Mensagem = ''; RequerReinicio = $true }
            [pscustomobject]@{ Nome = 'B'; Status = 'JaAplicado'; Mensagem = ''; RequerReinicio = $false }
            [pscustomobject]@{ Nome = 'C'; Status = 'Falhou'; Mensagem = 'protegido'; RequerReinicio = $false }
        )
        $s = Get-UTRunSummary -Resultados $results
        $s.Aplicados | Should -Be 1
        $s.JaAplicados | Should -Be 1
        $s.Falhas.Count | Should -Be 1
        $s.RequerReinicio | Should -BeTrue
        $s.Texto | Should -Match '^1 aplicados, 1 já estavam aplicados, 1 falharam\.'
        $s.Texto | Should -Match ' - C: protegido'
        $s.Texto | Should -Match 'Reinicie o computador'
    }
}

Describe 'Initialize-UTTargetUser' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'redireciona o HKCU quando o UAC usou outra conta' {
        Mock Get-UTInteractiveUser { [pscustomobject]@{ Sid = 'S-1-5-21-1-2-3-1001'; Nome = 'PC\jogador' } }
        Mock Test-UTRegistryKey { $true } -ParameterFilter { $Path -like 'HKU:*' }
        $r = Initialize-UTTargetUser
        $r.Nome | Should -Be 'PC\jogador'
        $UTSync.UsuarioAlvoSid | Should -Be 'S-1-5-21-1-2-3-1001'
    }

    It 'não faz nada quando é a mesma conta' {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Mock Get-UTInteractiveUser { [pscustomobject]@{ Sid = $me; Nome = 'eu' } }
        Initialize-UTTargetUser | Should -BeNullOrEmpty
        $UTSync.ContainsKey('UsuarioAlvoSid') | Should -BeFalse
    }

    It 'acha o usuário da sessão atual no PC real (só leitura)' {
        $u = Get-UTInteractiveUser
        $u.Sid | Should -Match '^S-1-5-'
    }
}

Describe 'Get-UTConfig' {
    BeforeEach { Reset-UTTestEnvironment; $env:UPGRADETWEAKS_CONFIG_DIR = $null }
    AfterEach { Remove-Variable -Name UTEmbeddedConfig -Scope Script -ErrorAction SilentlyContinue }

    It 'usa a configuração embutida do arquivo compilado' {
        $script:UTEmbeddedConfig = @{ 'exemplo' = '{"nome":"Configuração embutida"}' }
        (Get-UTConfig -Name 'exemplo').nome | Should -Be 'Configuração embutida'
    }

    It 'lê o config\ do repositório no desenvolvimento' {
        @((Get-UTConfig -Name 'tweaks-gaming').tweaks).Count | Should -BeGreaterThan 0
    }

    It 'erro claro para configuração inexistente' {
        { Get-UTConfig -Name 'nao-existe' } | Should -Throw "*'nao-existe' não encontrada*"
    }
}
