BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Resolve-UTRegistryPath' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'entende o formato <Entrada>' -TestCases @(
        @{ Entrada = 'HKLM:\SOFTWARE\Teste'; Hive = 'LocalMachine'; Sub = 'SOFTWARE\Teste'; Nativo = 'HKEY_LOCAL_MACHINE\SOFTWARE\Teste' }
        @{ Entrada = 'HKCU:\Software\X\'; Hive = 'CurrentUser'; Sub = 'Software\X'; Nativo = 'HKEY_CURRENT_USER\Software\X' }
        @{ Entrada = 'Registry::HKEY_USERS\.DEFAULT\Control Panel'; Hive = 'Users'; Sub = '.DEFAULT\Control Panel'; Nativo = 'HKEY_USERS\.DEFAULT\Control Panel' }
        @{ Entrada = 'HKEY_LOCAL_MACHINE\SYSTEM'; Hive = 'LocalMachine'; Sub = 'SYSTEM'; Nativo = 'HKEY_LOCAL_MACHINE\SYSTEM' }
        @{ Entrada = 'HKU:\S-1-5-18'; Hive = 'Users'; Sub = 'S-1-5-18'; Nativo = 'HKEY_USERS\S-1-5-18' }
    ) {
        $r = Resolve-UTRegistryPath -Path $Entrada
        $r.Hive.ToString() | Should -Be $Hive
        $r.SubKey | Should -Be $Sub
        $r.NativePath | Should -Be $Nativo
    }

    It 'redireciona HKCU para o usuário que vai jogar quando a elevação usou outra conta' {
        $UTSync.UsuarioAlvoSid = 'S-1-5-21-111-222-333-1001'
        $r = Resolve-UTRegistryPath -Path 'HKCU:\Software\Microsoft\GameBar'
        $r.Hive.ToString() | Should -Be 'Users'
        $r.NativePath | Should -Be 'HKEY_USERS\S-1-5-21-111-222-333-1001\Software\Microsoft\GameBar'
        $r.Display | Should -Be 'HKCU:\Software\Microsoft\GameBar'
    }

    It 'recusa caminho inválido' {
        { Resolve-UTRegistryPath -Path 'C:\Windows' } | Should -Throw '*inválido*'
    }
}

Describe 'Get/Set/Remove-UTRegistryValue (hive de teste)' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'grava e lê <Tipo> com o tipo exato' -TestCases @(
        @{ Tipo = 'DWord'; Valor = 1; Esperado = 1 }
        @{ Tipo = 'DWord'; Valor = 4294967295; Esperado = 4294967295 }
        @{ Tipo = 'DWord'; Valor = '0xFFFFFFFF'; Esperado = 4294967295 }
        @{ Tipo = 'DWord'; Valor = 38; Esperado = 38 }
        @{ Tipo = 'QWord'; Valor = 5000000000; Esperado = 5000000000 }
        @{ Tipo = 'String'; Valor = 'Deny'; Esperado = 'Deny' }
        @{ Tipo = 'String'; Valor = 'Configuração'; Esperado = 'Configuração' }
        @{ Tipo = 'ExpandString'; Valor = '%TEMP%\x'; Esperado = '%TEMP%\x' }
        @{ Tipo = 'Binary'; Valor = '90 12 03 80 10 00 00 00'; Esperado = '9012038010000000' }
        @{ Tipo = 'Binary'; Valor = @(144, 18, 3, 128); Esperado = '90120380' }
    ) {
        Set-UTRegistryValue -Path "$UTTestKey\Tipos" -Name 'v' -Type $Tipo -Value $Valor
        $r = Get-UTRegistryValue -Path "$UTTestKey\Tipos" -Name 'v'
        $r.ValorExiste | Should -BeTrue
        $r.Tipo | Should -Be $Tipo
        $r.Valor | Should -Be $Esperado
        Test-UTRegistryValueEqual -Actual $r -Type $Tipo -Expected $Valor | Should -BeTrue
    }

    It 'grava MultiString com um único item como lista' {
        Set-UTRegistryValue -Path $UTTestKey -Name 'multi' -Type MultiString -Value @('único')
        $r = Get-UTRegistryValue -Path $UTTestKey -Name 'multi'
        $r.Tipo | Should -Be 'MultiString'
        , $r.Valor | Should -BeOfType [string[]]
        $r.Valor[0] | Should -Be 'único'
    }

    It 'grava o valor padrão da chave (nome vazio)' {
        Set-UTRegistryValue -Path "$UTTestKey\Padrao" -Name '' -Type String -Value 'abc'
        (Get-UTRegistryValue -Path "$UTTestKey\Padrao" -Name '').Valor | Should -Be 'abc'
    }

    It 'informa chave e valor ausentes sem erro' {
        $r = Get-UTRegistryValue -Path "$UTTestKey\NaoExiste" -Name 'x'
        $r.ChaveExiste | Should -BeFalse
        $r.ValorExiste | Should -BeFalse
        $r = Get-UTRegistryValue -Path $UTTestKey -Name 'x'
        $r.ChaveExiste | Should -BeTrue
        $r.ValorExiste | Should -BeFalse
    }

    It 'compara strings sem diferenciar maiúsculas, mas exige o mesmo tipo' {
        Set-UTRegistryValue -Path $UTTestKey -Name 's' -Type String -Value 'Deny'
        $r = Get-UTRegistryValue -Path $UTTestKey -Name 's'
        Test-UTRegistryValueEqual -Actual $r -Type String -Expected 'deny' | Should -BeTrue
        Set-UTRegistryValue -Path $UTTestKey -Name 'n' -Type String -Value '0'
        Test-UTRegistryValueEqual -Actual (Get-UTRegistryValue -Path $UTTestKey -Name 'n') -Type DWord -Expected 0 | Should -BeFalse
    }

    It 'recusa DWord fora do intervalo e binário inválido' {
        { Set-UTRegistryValue -Path $UTTestKey -Name 'x' -Type DWord -Value 4294967296 } | Should -Throw '*fora do intervalo*'
        { Set-UTRegistryValue -Path $UTTestKey -Name 'x' -Type Binary -Value 'XYZ' } | Should -Throw '*binário inválido*'
    }

    It '-WhatIf não grava nada' {
        Set-UTRegistryValue -Path "$UTTestKey\WhatIf" -Name 'v' -Type DWord -Value 1 -WhatIf
        Test-UTRegistryKey -Path "$UTTestKey\WhatIf" | Should -BeFalse
    }

    It 'remove valor existente e ignora inexistente' {
        Set-UTRegistryValue -Path $UTTestKey -Name 'apagar' -Type DWord -Value 1
        Remove-UTRegistryValue -Path $UTTestKey -Name 'apagar' | Should -BeTrue
        Remove-UTRegistryValue -Path $UTTestKey -Name 'apagar' | Should -BeFalse
        Remove-UTRegistryValue -Path "$UTTestKey\Nada" -Name 'x' | Should -BeFalse
    }
}

Describe 'Chaves criadas pelo programa' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'Get-UTFirstMissingKey devolve a primeira chave que ainda não existe' {
        Get-UTFirstMissingKey -Path $UTTestKey | Should -BeNullOrEmpty
        Get-UTFirstMissingKey -Path "$UTTestKey\A\B\C" | Should -Be "$UTTestKey\A"
    }

    It 'Remove-UTEmptyKeyChain apaga só as chaves vazias até o limite' {
        Set-UTRegistryValue -Path "$UTTestKey\A\B\C" -Name 'v' -Type DWord -Value 1
        Remove-UTRegistryValue -Path "$UTTestKey\A\B\C" -Name 'v' | Out-Null
        Remove-UTEmptyKeyChain -Path "$UTTestKey\A\B\C" -StopAt "$UTTestKey\A" | Should -Be 3
        Test-UTRegistryKey -Path "$UTTestKey\A" | Should -BeFalse
        Test-UTRegistryKey -Path $UTTestKey | Should -BeTrue
    }

    It 'Remove-UTEmptyKeyChain não apaga chave que tem outro conteúdo' {
        Set-UTRegistryValue -Path "$UTTestKey\A\B" -Name 'outro' -Type DWord -Value 1
        New-Item -Path "$UTTestKey\A\B\C" -Force | Out-Null
        Remove-UTEmptyKeyChain -Path "$UTTestKey\A\B\C" -StopAt "$UTTestKey\A" | Should -Be 1
        Test-UTRegistryKey -Path "$UTTestKey\A\B" | Should -BeTrue
    }
}

Describe 'Export-UTRegistryKey e Import-UTRegistryFile (reg.exe real, só na chave de teste)' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'exporta, e a importação devolve o valor alterado' {
        Set-UTRegistryValue -Path "$UTTestKey\Exp" -Name 'v' -Type DWord -Value 7
        $file = Join-Path $env:UPGRADETWEAKS_HOME 'exp.reg'
        Export-UTRegistryKey -Path "$UTTestKey\Exp" -Destination $file | Should -Be $file
        Test-Path -LiteralPath $file | Should -BeTrue
        Set-UTRegistryValue -Path "$UTTestKey\Exp" -Name 'v' -Type DWord -Value 99
        Import-UTRegistryFile -Path $file
        (Get-UTRegistryValue -Path "$UTTestKey\Exp" -Name 'v').Valor | Should -Be 7
    }

    It 'não exporta chave inexistente' {
        Export-UTRegistryKey -Path "$UTTestKey\Nada" -Destination (Join-Path $env:UPGRADETWEAKS_HOME 'x.reg') | Should -BeNullOrEmpty
    }

    It 'propaga erro do reg.exe' {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 1; Saida = ''; Erro = 'ERRO: acesso negado' } }
        { Export-UTRegistryKey -Path $UTTestKey -Destination (Join-Path $env:UPGRADETWEAKS_HOME 'y.reg') } | Should -Throw '*reg export falhou*'
    }
}

Describe 'Invoke-UTNative e ConvertTo-UTNativeArgument' {
    It 'captura saída e código de saída' {
        $r = Invoke-UTNative -FilePath 'cmd.exe' -ArgumentList @('/c', 'echo ola& exit 3')
        $r.CodigoSaida | Should -Be 3
        $r.Saida | Should -Be 'ola'
    }
    It 'coloca aspas só quando necessário' {
        ConvertTo-UTNativeArgument 'start=' | Should -Be 'start='
        ConvertTo-UTNativeArgument 'C:\Minha Pasta\a.reg' | Should -Be '"C:\Minha Pasta\a.reg"'
        ConvertTo-UTNativeArgument '' | Should -Be '""'
        ConvertTo-UTNativeArgument 'a "b"' | Should -Be '"a \"b\""'
    }
}

Describe 'JSON' {
    BeforeEach { Reset-UTTestEnvironment }
    It 'converte objetos, listas e objetos vazios para hashtables' {
        $h = ConvertTo-UTHashtable ('{"a":1,"b":{"c":[1,2]},"d":{},"e":[],"f":"ç"}' | ConvertFrom-Json)
        $h | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $h.b.c.Count | Should -Be 2
        $h.d | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $h.d.Count | Should -Be 0
        , $h.e | Should -BeOfType [object[]]
        $h.f | Should -Be 'ç'
    }
    It 'grava e lê de volta sem perder acentos' {
        $p = Join-Path $env:UPGRADETWEAKS_HOME 'x.json'
        Write-UTJsonFile -Path $p -InputObject ([ordered]@{ nome = 'Desativação'; lista = @('um') })
        Write-UTJsonFile -Path $p -InputObject ([ordered]@{ nome = 'Desativação 2'; lista = @('um') })
        $r = Read-UTJsonFile -Path $p
        $r.nome | Should -Be 'Desativação 2'
        @($r.lista).Count | Should -Be 1
        Test-Path -LiteralPath "$p.tmp" | Should -BeFalse
    }
}
