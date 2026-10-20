BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $activeSchemeOutput = 'GUID do Esquema de Energia: 381b4222-f694-41f0-9685-ff5bb260df2e  (Equilibrado)'
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Pasta de backup da sessão' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'cria backups\AAAA-MM-DD_HHmm com manifesto e reaproveita na mesma sessão' {
        $a = Get-UTSessionBackupFolder
        Split-Path -Leaf $a | Should -Match '^\d{4}-\d{2}-\d{2}_\d{4}$'
        Test-Path -LiteralPath (Join-Path $a 'manifesto.json') | Should -BeTrue
        Get-UTSessionBackupFolder | Should -Be $a
    }

    It 'uma nova sessão no mesmo minuto ganha sufixo' {
        $a = Get-UTSessionBackupFolder
        $UTSync.Sessao = $null
        $b = Get-UTSessionBackupFolder
        $b | Should -Not -Be $a
        $b | Should -Match '_2$'
    }
}

Describe 'Backup-UTRegistryKey' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'exporta a chave uma vez por sessão e registra no manifesto' {
        Set-UTRegistryValue -Path "$UTTestKey\Bkp" -Name 'v' -Type DWord -Value 1
        $file = Backup-UTRegistryKey -Path "$UTTestKey\Bkp"
        Test-Path -LiteralPath $file | Should -BeTrue
        (Get-Content -LiteralPath $file -Raw) | Should -Match 'UpgradeTweaksTest\\Bkp'

        Mock Export-UTRegistryKey { throw 'não deveria exportar de novo' }
        Backup-UTRegistryKey -Path "$UTTestKey\Bkp" | Should -Be $file

        $manifest = Read-UTJsonFile -Path (Join-Path (Get-UTSessionBackupFolder) 'manifesto.json')
        @($manifest.itens).Count | Should -Be 1
        $manifest.itens[0].tipo | Should -Be 'registro'
        $manifest.itens[0].origem | Should -Be 'HKEY_CURRENT_USER\Software\UpgradeTweaksTest\Bkp'
    }

    It 'chave inexistente não gera arquivo' {
        Backup-UTRegistryKey -Path "$UTTestKey\NaoExiste" | Should -BeNullOrEmpty
    }
}

Describe 'Backup-UTServiceState' {
    BeforeEach {
        Reset-UTTestEnvironment
        $script:tipo = 'Automatic'
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = $script:tipo; Status = 'Running' } }
    }

    It 'salva o StartType em servicos.json e mantém o primeiro valor' {
        Backup-UTServiceState -Name 'DiagTrack', 'SysMain'
        $script:tipo = 'Disabled'
        Backup-UTServiceState -Name 'DiagTrack'
        $data = Read-UTJsonFile -Path (Join-Path (Get-UTSessionBackupFolder) 'servicos.json')
        $data.servicos.DiagTrack.startType | Should -Be 'Automatic'
        $data.servicos.SysMain.startType | Should -Be 'Automatic'
    }
}

Describe 'Backup-UTActivePowerPlan' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Invoke-UTNative {
            if ($ArgumentList[0] -eq '/getactivescheme') { return [pscustomobject]@{ CodigoSaida = 0; Saida = $activeSchemeOutput; Erro = '' } }
            return [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' }
        }
    }

    It 'lê o plano ativo na saída em português' {
        $p = Get-UTActivePowerScheme
        $p.Guid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        $p.Nome | Should -Be 'Equilibrado'
    }

    It 'exporta com powercfg /export uma vez por sessão' {
        $r = Backup-UTActivePowerPlan
        $r.Guid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        $r.Arquivo | Should -Match 'energia\\plano-ativo_381b4222-f694-41f0-9685-ff5bb260df2e\.pow$'
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { $ArgumentList[0] -eq '/export' -and $ArgumentList[2] -eq '381b4222-f694-41f0-9685-ff5bb260df2e' }
        Backup-UTActivePowerPlan | Out-Null
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { $ArgumentList[0] -eq '/export' }
    }
}

Describe 'Get-UTBackup e Restore-UTBackup' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Assert-UTAdmin {}
        Mock Invoke-UTNative {
            if ($ArgumentList[0] -eq '/getactivescheme') { return [pscustomobject]@{ CodigoSaida = 0; Saida = $activeSchemeOutput; Erro = '' } }
            return [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' }
        }
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = 'Manual'; Status = 'Stopped' } }
        Set-UTRegistryValue -Path "$UTTestKey\R" -Name 'v' -Type DWord -Value 1
        [void](Backup-UTRegistryKey -Path "$UTTestKey\R")
        Backup-UTServiceState -Name 'SysMain'
        [void](Backup-UTActivePowerPlan)
    }

    It 'lista o backup com o que ele contém' {
        # @(): on PowerShell 5.1 a single [pscustomobject] has no .Count.
        $list = @(Get-UTBackup)
        $list.Count | Should -Be 1
        $list[0].ChavesReg | Should -Be 1
        $list[0].TemServicos | Should -BeTrue
        $list[0].TemPlano | Should -BeTrue
    }

    It 'restaura registro, serviços e plano; uma falha não para as outras' {
        Mock Import-UTRegistryFile { throw (New-Object System.UnauthorizedAccessException 'negado') }
        Mock Set-UTServiceStartType {}
        Mock Restore-UTPowerPlanFile {}
        $r = Restore-UTBackup -Pasta (Get-UTBackup)[0].Pasta
        $r.Falhas.Count | Should -Be 1
        $r.Restaurados.Count | Should -Be 2
        Should -Invoke Set-UTServiceStartType -Times 1 -ParameterFilter { $Name -eq 'SysMain' -and $StartType -eq 'Manual' }
        Should -Invoke Restore-UTPowerPlanFile -Times 1
    }

    It 'recusa pasta que não é backup' {
        { Restore-UTBackup -Pasta $env:UPGRADETWEAKS_HOME } | Should -Throw '*não é um backup*'
    }
}

Describe 'New-UTRestorePoint' {
    BeforeEach {
        Reset-UTTestEnvironment
        $script:writes = New-Object System.Collections.Generic.List[string]
        Mock Get-UTRegistryValue { [pscustomobject]@{ ChaveExiste = $true; ValorExiste = $false; Tipo = $null; Valor = $null } } -ParameterFilter { $Name -eq 'SystemRestorePointCreationFrequency' }
        Mock Set-UTRegistryValue { $script:writes.Add("set $Name=$Value") }
        Mock Remove-UTRegistryValue { $script:writes.Add("remove $Name"); $true }
        Mock Test-UTSystemRestoreEnabled { $true }
        Mock Enable-UTSystemRestore {}
        Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0 } }
    }

    It 'cria o ponto contornando o limite de 24 h e volta a configuração original' {
        $r = New-UTRestorePoint
        $r.Criado | Should -BeTrue
        $script:writes | Should -Be @('set SystemRestorePointCreationFrequency=0', 'remove SystemRestorePointCreationFrequency')
        Should -Invoke Invoke-CimMethod -Times 1 -ParameterFilter { $MethodName -eq 'CreateRestorePoint' -and $Arguments.RestorePointType -eq 12 }
        Should -Invoke Enable-UTSystemRestore -Times 0
    }

    It 'devolve o valor original da frequência quando ele existia' {
        Mock Get-UTRegistryValue { [pscustomobject]@{ ChaveExiste = $true; ValorExiste = $true; Tipo = 'DWord'; Valor = 1440 } } -ParameterFilter { $Name -eq 'SystemRestorePointCreationFrequency' }
        New-UTRestorePoint | Out-Null
        $script:writes[-1] | Should -Be 'set SystemRestorePointCreationFrequency=1440'
    }

    It 'liga a Proteção do Sistema quando estava desligada' {
        Mock Test-UTSystemRestoreEnabled { $false }
        $r = New-UTRestorePoint
        $r.ProtecaoLigadaAgora | Should -BeTrue
        Should -Invoke Enable-UTSystemRestore -Times 1
    }

    It 'só cria um ponto por sessão' {
        New-UTRestorePoint | Out-Null
        New-UTRestorePoint | Out-Null
        Should -Invoke Invoke-CimMethod -Times 1
    }

    It 'falha vira aviso e ainda restaura a frequência' {
        Mock Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 1058 } }
        $r = New-UTRestorePoint
        $r.Criado | Should -BeFalse
        $r.Mensagem | Should -Match 'Não foi possível criar o ponto de restauração'
        $script:writes[-1] | Should -Be 'remove SystemRestorePointCreationFrequency'
    }

    It '-WhatIf não faz nada' {
        $r = New-UTRestorePoint -WhatIf
        $r.Criado | Should -BeFalse
        Should -Invoke Invoke-CimMethod -Times 0
        $script:writes.Count | Should -Be 0
    }
}

Describe 'Invoke-UTPreApplySafety' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock New-UTRestorePoint { [pscustomobject]@{ Criado = $true; Mensagem = 'ok' } }
    }

    It 'roda uma vez por sessão: pastas, pasta de backup e ponto de restauração' {
        $a = Invoke-UTPreApplySafety
        $b = Invoke-UTPreApplySafety
        $a.PastaBackup | Should -Be $b.PastaBackup
        Test-Path -LiteralPath (Get-UTPath -Name State) | Should -BeTrue
        Should -Invoke New-UTRestorePoint -Times 1
    }
}
