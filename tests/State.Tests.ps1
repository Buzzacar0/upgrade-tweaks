BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Estado original do registro: aplicar -> detectar -> desfazer -> detectar' {
    BeforeEach {
        Reset-UTTestEnvironment
        $k = "$UTTestKey\GameConfigStore"
    }

    It 'valor que existia: salva o valor REAL e o desfazer volta a ele' {
        Set-UTRegistryValue -Path $k -Name 'GameDVR_Enabled' -Type DWord -Value 1

        Save-UTOriginalRegistryValue -Path $k -Name 'GameDVR_Enabled' -TweakId 'UT_A' | Should -BeTrue
        Set-UTRegistryValue -Path $k -Name 'GameDVR_Enabled' -Type DWord -Value 0
        Test-UTRegistryValueEqual -Actual (Get-UTRegistryValue $k 'GameDVR_Enabled') -Type DWord -Expected 0 | Should -BeTrue

        Restore-UTOriginalRegistryValue -Path $k -Name 'GameDVR_Enabled' -TweakId 'UT_A' | Should -Be 'Restaurado'
        (Get-UTRegistryValue $k 'GameDVR_Enabled').Valor | Should -Be 1
        (Read-UTOriginalState).itens.Count | Should -Be 0
    }

    It 'aplicar duas vezes não troca o original pelo valor do próprio tweak (idempotente)' {
        Set-UTRegistryValue -Path $k -Name 'v' -Type DWord -Value 5
        Save-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' | Should -BeTrue
        Set-UTRegistryValue -Path $k -Name 'v' -Type DWord -Value 0
        Save-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' | Should -BeFalse
        Restore-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' | Out-Null
        (Get-UTRegistryValue $k 'v').Valor | Should -Be 5
    }

    It 'valor e chave que não existiam: o desfazer remove o valor e só as chaves criadas' {
        $deep = "$UTTestKey\Policies\Microsoft\Windows\GameDVR"
        Save-UTOriginalRegistryValue -Path $deep -Name 'AllowGameDVR' -TweakId 'UT_A' | Out-Null
        $item = Get-UTOriginalItem -Chave (Get-UTRegistryStateKey -Path $deep -Name 'AllowGameDVR')
        $item.chaveExistia | Should -BeFalse
        $item.valorExistia | Should -BeFalse
        $item.primeiraChaveCriada | Should -Be "$UTTestKey\Policies"

        Set-UTRegistryValue -Path $deep -Name 'AllowGameDVR' -Type DWord -Value 0
        Restore-UTOriginalRegistryValue -Path $deep -Name 'AllowGameDVR' -TweakId 'UT_A' | Should -Be 'Restaurado'
        Test-UTRegistryKey -Path "$UTTestKey\Policies" | Should -BeFalse
        Test-UTRegistryKey -Path $UTTestKey | Should -BeTrue
    }

    It 'valor que não existia numa chave existente: remove só o valor' {
        Set-UTRegistryValue -Path $k -Name 'outro' -Type DWord -Value 1
        Save-UTOriginalRegistryValue -Path $k -Name 'novo' -TweakId 'UT_A' | Out-Null
        Set-UTRegistryValue -Path $k -Name 'novo' -Type String -Value 'x'
        Restore-UTOriginalRegistryValue -Path $k -Name 'novo' -TweakId 'UT_A' | Out-Null
        (Get-UTRegistryValue $k 'novo').ValorExiste | Should -BeFalse
        (Get-UTRegistryValue $k 'outro').Valor | Should -Be 1
    }

    It 'preserva tipo e conteúdo binário e MultiString' {
        Set-UTRegistryValue -Path $k -Name 'bin' -Type Binary -Value '9E1E078012000000'
        Set-UTRegistryValue -Path $k -Name 'multi' -Type MultiString -Value @('a', 'b')
        Save-UTOriginalRegistryValue -Path $k -Name 'bin' -TweakId 'UT_A' | Out-Null
        Save-UTOriginalRegistryValue -Path $k -Name 'multi' -TweakId 'UT_A' | Out-Null
        Set-UTRegistryValue -Path $k -Name 'bin' -Type DWord -Value 0
        Remove-UTRegistryValue -Path $k -Name 'multi' | Out-Null
        Restore-UTOriginalRegistryValue -Path $k -Name 'bin' -TweakId 'UT_A' | Out-Null
        Restore-UTOriginalRegistryValue -Path $k -Name 'multi' -TweakId 'UT_A' | Out-Null
        $bin = Get-UTRegistryValue $k 'bin'
        $bin.Tipo | Should -Be 'Binary'
        $bin.Valor | Should -Be '9E1E078012000000'
        (Get-UTRegistryValue $k 'multi').Valor | Should -Be @('a', 'b')
    }

    It 'dois tweaks no mesmo valor: só restaura quando o último é desfeito' {
        Set-UTRegistryValue -Path $k -Name 'DisabledComponents' -Type DWord -Value 0
        Save-UTOriginalRegistryValue -Path $k -Name 'DisabledComponents' -TweakId 'UT_IPv4' | Out-Null
        Set-UTRegistryValue -Path $k -Name 'DisabledComponents' -Type DWord -Value 32
        Save-UTOriginalRegistryValue -Path $k -Name 'DisabledComponents' -TweakId 'UT_Teredo' | Out-Null
        Set-UTRegistryValue -Path $k -Name 'DisabledComponents' -Type DWord -Value 33

        Restore-UTOriginalRegistryValue -Path $k -Name 'DisabledComponents' -TweakId 'UT_IPv4' | Should -Be 'MantidoPorOutroTweak'
        (Get-UTRegistryValue $k 'DisabledComponents').Valor | Should -Be 33
        Restore-UTOriginalRegistryValue -Path $k -Name 'DisabledComponents' -TweakId 'UT_Teredo' | Should -Be 'Restaurado'
        (Get-UTRegistryValue $k 'DisabledComponents').Valor | Should -Be 0
    }

    It 'sem estado salvo devolve SemEstado (o motor usa o valorOriginal do tweaks.json)' {
        Restore-UTOriginalRegistryValue -Path $k -Name 'nunca' -TweakId 'UT_A' | Should -Be 'SemEstado'
    }

    It '-WhatIf não grava o arquivo de estado nem altera o registro' {
        Set-UTRegistryValue -Path $k -Name 'v' -Type DWord -Value 1
        Save-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' -WhatIf | Out-Null
        Test-Path -LiteralPath (Get-UTStateFilePath -Name 'estado-original') | Should -BeFalse

        Save-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' | Out-Null
        Set-UTRegistryValue -Path $k -Name 'v' -Type DWord -Value 0
        Restore-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' -WhatIf | Out-Null
        (Get-UTRegistryValue $k 'v').Valor | Should -Be 0
        (Read-UTOriginalState).itens.Count | Should -Be 1
    }

    It 'se a restauração falhar, o original continua salvo' {
        Set-UTRegistryValue -Path $k -Name 'v' -Type DWord -Value 1
        Save-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' | Out-Null
        Mock Set-UTRegistryValue { throw [System.UnauthorizedAccessException]'negado' }
        { Restore-UTOriginalRegistryValue -Path $k -Name 'v' -TweakId 'UT_A' } | Should -Throw
        (Read-UTOriginalState).itens.Count | Should -Be 1
    }
}

Describe 'Estado original de serviços' {
    BeforeEach {
        Reset-UTTestEnvironment
        $script:svcType = 'Automatic'
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = $script:svcType; Status = 'Running' } }
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = '[SC] ChangeServiceConfig SUCCESS'; Erro = '' } }
    }

    It 'salva o tipo real e o desfazer chama sc.exe com ele' {
        Save-UTOriginalServiceState -Name 'DiagTrack' -TweakId 'UT_Tel' | Should -BeTrue
        $script:svcType = 'Disabled'
        Restore-UTOriginalServiceState -Name 'DiagTrack' -TweakId 'UT_Tel' | Should -Be 'Restaurado'
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter {
            $FilePath -eq 'sc.exe' -and ($ArgumentList -join ' ') -eq 'config DiagTrack start= auto'
        }
    }
}

Describe 'Itens genéricos' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'salva uma vez e devolve os dados no desfazer' {
        Save-UTOriginalItem -Chave 'bcdedit|disabledynamictick' -Dados ([ordered]@{ existia = $false }) -TweakId 'UT_Tick' | Should -BeTrue
        Save-UTOriginalItem -Chave 'bcdedit|disabledynamictick' -Dados ([ordered]@{ existia = $true }) -TweakId 'UT_Tick' | Should -BeFalse
        $d = Pop-UTOriginalItem -Chave 'bcdedit|disabledynamictick' -TweakId 'UT_Tick'
        $d.existia | Should -BeFalse
        Pop-UTOriginalItem -Chave 'bcdedit|disabledynamictick' -TweakId 'UT_Tick' | Should -BeNullOrEmpty
    }
}

Describe 'Registro de tweaks aplicados' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'mantém a ordem da primeira aplicação e desfaz na ordem inversa' {
        Add-UTAppliedRecord -TweakId 'UT_1'
        Add-UTAppliedRecord -TweakId 'UT_2'
        Add-UTAppliedRecord -TweakId 'UT_1'
        Add-UTAppliedRecord -TweakId 'UT_3'
        (Get-UTAppliedRecord).tweakId | Should -Be @('UT_1', 'UT_2', 'UT_3')
        (Get-UTAppliedRecord -Reverse).tweakId | Should -Be @('UT_3', 'UT_2', 'UT_1')
        Remove-UTAppliedRecord -TweakId 'UT_2'
        (Get-UTAppliedRecord).tweakId | Should -Be @('UT_1', 'UT_3')
    }

    It 'com -WhatIf não registra nada' {
        Add-UTAppliedRecord -TweakId 'UT_1' -WhatIf
        @(Get-UTAppliedRecord).Count | Should -Be 0
    }
}

Describe 'Restore-UTAllOriginalState' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = 'Manual'; Status = 'Stopped' } }
    }

    It 'restaura tudo do mais novo para o mais antigo e uma falha não para as outras' {
        Set-UTRegistryValue -Path $UTTestKey -Name 'a' -Type DWord -Value 1
        Save-UTOriginalRegistryValue -Path $UTTestKey -Name 'a' -TweakId 'UT_1' | Out-Null
        Save-UTOriginalServiceState -Name 'SysMain' -TweakId 'UT_2' | Out-Null
        Save-UTOriginalRegistryValue -Path $UTTestKey -Name 'b' -TweakId 'UT_3' | Out-Null
        Save-UTOriginalItem -Chave 'energia|plano' -Dados ([ordered]@{ guid = 'x' }) -TweakId 'UT_4' | Out-Null
        Set-UTRegistryValue -Path $UTTestKey -Name 'a' -Type DWord -Value 0
        Set-UTRegistryValue -Path $UTTestKey -Name 'b' -Type DWord -Value 0

        Mock Set-UTServiceStartType { throw (New-Object System.UnauthorizedAccessException 'negado') }
        $r = Restore-UTAllOriginalState
        $r.Restaurados | Should -Be @("$UTTestKey\b", "$UTTestKey\a")
        $r.Falhas.Count | Should -Be 1
        $r.Falhas[0].Motivo | Should -Match 'protegido pelo sistema'
        $r.Ignorados | Should -Be @('energia|plano')
        (Get-UTRegistryValue $UTTestKey 'a').Valor | Should -Be 1
        (Get-UTRegistryValue $UTTestKey 'b').ValorExiste | Should -BeFalse
    }
}
