BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Get-UTServiceState' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'Start=<Start> Delayed=<Delayed> -> <Esperado>' -TestCases @(
        @{ Start = 2; Delayed = 1; Esperado = 'AutomaticDelayedStart' }
        @{ Start = 2; Delayed = 0; Esperado = 'Automatic' }
        @{ Start = 3; Delayed = 0; Esperado = 'Manual' }
        @{ Start = 4; Delayed = 0; Esperado = 'Disabled' }
    ) {
        Mock Get-UTRegistryValue {
            if ($Name -eq 'Start') { return [pscustomobject]@{ ValorExiste = $true; Valor = $Start } }
            return [pscustomobject]@{ ValorExiste = $true; Valor = $Delayed }
        }
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        $s = Get-UTServiceState -Name 'Teste'
        $s.Existe | Should -BeTrue
        $s.StartType | Should -Be $Esperado
        $s.Status | Should -Be 'Running'
    }

    It 'serviço inexistente' {
        Mock Get-UTRegistryValue { [pscustomobject]@{ ValorExiste = $false; Valor = $null } }
        (Get-UTServiceState -Name 'NaoExiste').Existe | Should -BeFalse
    }

    It 'lê um serviço real do Windows (só leitura)' {
        $s = Get-UTServiceState -Name 'EventLog'
        $s.Existe | Should -BeTrue
        $s.StartType | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-UTServiceStartType' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = 'Automatic'; Status = 'Running' } }
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } }
        Mock Stop-Service {}
    }

    It '<Tipo> vira "start= <Arg>" no sc.exe' -TestCases @(
        @{ Tipo = 'Automatic'; Arg = 'auto' }
        @{ Tipo = 'AutomaticDelayedStart'; Arg = 'delayed-auto' }
        @{ Tipo = 'Manual'; Arg = 'demand' }
        @{ Tipo = 'Disabled'; Arg = 'disabled' }
    ) {
        Set-UTServiceStartType -Name 'SysMain' -StartType $Tipo
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { ($ArgumentList -join ' ') -eq "config SysMain start= $Arg" }
    }

    It 'acesso negado vira mensagem amigável em PT-BR' {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 5; Saida = '[SC] OpenService FAILED 5'; Erro = '' } }
        { Set-UTServiceStartType -Name 'WaaSMedicSvc' -StartType Disabled } | Should -Throw 'Não foi possível alterar o serviço WaaSMedicSvc porque ele é protegido pelo sistema.'
    }

    It 'serviço inexistente não chama o sc.exe' {
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $false; StartType = $null; Status = $null } }
        { Set-UTServiceStartType -Name 'Fantasma' -StartType Manual } | Should -Throw '*não existe neste computador*'
        Should -Invoke Invoke-UTNative -Times 0
    }

    It '-Parar para o serviço ao desativar' {
        Set-UTServiceStartType -Name 'DiagTrack' -StartType Disabled -Parar
        Should -Invoke Stop-Service -Times 1 -ParameterFilter { $Name -eq 'DiagTrack' }
    }

    It 'falha ao parar não desfaz a mudança (vira aviso)' {
        Mock Stop-Service { throw 'em uso' }
        { Set-UTServiceStartType -Name 'DiagTrack' -StartType Disabled -Parar } | Should -Not -Throw
    }

    It '-WhatIf não chama o sc.exe' {
        Set-UTServiceStartType -Name 'SysMain' -StartType Disabled -WhatIf
        Should -Invoke Invoke-UTNative -Times 0
    }
}
