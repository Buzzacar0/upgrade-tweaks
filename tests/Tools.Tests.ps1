BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Limpeza de temporários' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Assert-UTAdmin {}
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $user = Join-Path $root 'user'; $win = Join-Path $root 'win'; $wu = Join-Path $root 'wu'
        foreach ($d in $user, $win, (Join-Path $wu 'pkg')) { New-Item -ItemType Directory -Force $d | Out-Null }
        [IO.File]::WriteAllBytes((Join-Path $user 'a.tmp'), (New-Object byte[] (1MB)))
        [IO.File]::WriteAllBytes((Join-Path $win 'b.tmp'), (New-Object byte[] (2MB)))
        [IO.File]::WriteAllBytes((Join-Path $wu 'pkg\c.cab'), (New-Object byte[] (3MB)))
        Mock Get-UTTargetUserTempPath { $user }
        Mock Get-UTTempCleanupTarget {
            foreach ($t in @(@{ Id = 'tempusuario'; Nome = 'u'; Caminho = $user }, @{ Id = 'tempwindows'; Nome = 'w'; Caminho = $win }, @{ Id = 'windowsupdate'; Nome = 'wu'; Caminho = $wu })) {
                [pscustomobject]@{ Id = $t.Id; Nome = $t.Nome; Caminho = $t.Caminho; TamanhoMB = (Get-UTFolderSize -Caminho $t.Caminho) }
            }
        }
        $script:svc = @{ wuauserv = 'Running'; bits = 'Stopped' }
        Mock Get-Service { [pscustomobject]@{ Name = $Name; Status = $script:svc[@($Name)[0]] } }
        Mock Stop-Service { $script:svc[@($Name)[0]] = 'Stopped' }
        Mock Start-Service { $script:svc[@($Name)[0]] = 'Running' }
    }

    It 'apaga, informa o espaço liberado e deixa os serviços do Windows Update como estavam' {
        $r = @(Clear-UTTempFile -Confirm:$false)
        ($r | Where-Object Id -eq 'tempusuario').LiberadoMB | Should -Be 1
        ($r | Where-Object Id -eq 'windowsupdate').LiberadoMB | Should -Be 3
        @(Get-ChildItem $wu -Force).Count | Should -Be 0
        Test-Path $wu | Should -BeTrue
        $script:svc.wuauserv | Should -Be 'Running'
        $script:svc.bits | Should -Be 'Stopped'
        Should -Invoke Stop-Service -Times 1 -ParameterFilter { $Name -eq 'wuauserv' }
        Should -Invoke Start-Service -Times 1 -ParameterFilter { $Name -eq 'wuauserv' }
    }

    It 'só os itens escolhidos' {
        $r = @(Clear-UTTempFile -Itens tempwindows -Confirm:$false)
        $r.Count | Should -Be 1
        Test-Path (Join-Path $user 'a.tmp') | Should -BeTrue
        Should -Invoke Stop-Service -Times 0
    }

    It 'simulação não apaga nada' {
        Clear-UTTempFile -WhatIf | Out-Null
        Test-Path (Join-Path $win 'b.tmp') | Should -BeTrue
    }
}

Describe 'Limpeza de Disco e reparo do Windows' {
    BeforeEach { Reset-UTTestEnvironment; Mock Assert-UTAdmin {} }

    It 'marca as categorias, roda o cleanmgr e tira as marcas depois (sem a pasta Downloads)' {
        Get-UTDiskCleanupHandler | Should -Not -Contain 'DownloadsFolder'
        Get-UTDiskCleanupHandler | Should -Not -Contain 'Previous Installations'
        Mock Test-UTRegistryKey { $true }
        Mock Set-UTRegistryValue {}
        Mock Remove-UTRegistryValue { $true }
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } }
        Invoke-UTDiskCleanup -Confirm:$false | Out-Null
        $n = @(Get-UTDiskCleanupHandler).Count
        Should -Invoke Set-UTRegistryValue -Times $n -Exactly -ParameterFilter { $Name -eq 'StateFlags0777' -and $Value -eq 2 }
        Should -Invoke Remove-UTRegistryValue -Times $n -Exactly
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { $FilePath -like '*cleanmgr.exe' -and $ArgumentList[0] -eq '/sagerun:777' }
    }

    It 'saída do sfc (UTF-16 com NUL) e barra de progresso do DISM ficam legíveis' {
        $sfc = "B`0e`0g`0i`0n`0n`0i`0n`0g`0`r`n`0V`0e`0r`0i`0f`0y`0 `01`0%`0`rV`0e`0r`0i`0f`0y`0 `01`00`00`0%`0"
        ConvertFrom-UTToolOutput -Texto $sfc | Should -Be ("Beginning" + [Environment]::NewLine + 'Verify 100%')
        $dism = "Image Version: 10.0`r`n[==========================100.0%==========================]`r`nThe restore operation completed successfully."
        ConvertFrom-UTToolOutput -Texto $dism | Should -Not -Match '====='
        ConvertFrom-UTToolOutput -Texto $dism | Should -Match 'completed successfully'
    }

    It '<Ferramenta> chama <Exe> <Arg>' -TestCases @(
        @{ Ferramenta = 'sfc'; Exe = 'sfc.exe'; Arg = '/scannow' }
        @{ Ferramenta = 'restorehealth'; Exe = 'dism.exe'; Arg = '/RestoreHealth' }
        @{ Ferramenta = 'componentcleanup'; Exe = 'dism.exe'; Arg = '/StartComponentCleanup' }
    ) {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = 'ok'; Erro = '' } }
        $r = Invoke-UTWindowsRepairTool -Ferramenta $Ferramenta
        $r.Sucesso | Should -BeTrue
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { $FilePath -like "*\$Exe" -and $ArgumentList -contains $Arg }
    }
}

Describe 'Otimizar unidades' {
    BeforeEach {
        Reset-UTTestEnvironment; Mock Assert-UTAdmin {}
        Mock Get-UTStorageInfo {
            [pscustomobject]@{
                Discos  = @([pscustomobject]@{ Numero = 0; Nome = 'NVMe'; Tipo = 'NVMe' }, [pscustomobject]@{ Numero = 1; Nome = 'HD'; Tipo = 'HDD' }, [pscustomobject]@{ Numero = 2; Nome = 'VM'; Tipo = 'Desconhecido' })
                Volumes = @([pscustomobject]@{ Letra = 'C'; Disco = 0 }, [pscustomobject]@{ Letra = 'D'; Disco = 1 }, [pscustomobject]@{ Letra = 'E'; Disco = 2 })
            }
        }
        Mock Optimize-Volume {}
    }

    It 'TRIM no SSD, desfragmentar só no HD, desconhecido é pulado' {
        $plan = @(Get-UTDriveOptimizationPlan)
        ($plan | Where-Object Letra -eq 'C').Acao | Should -Be 'ReTrim'
        ($plan | Where-Object Letra -eq 'D').Acao | Should -Be 'Defrag'
        ($plan | Where-Object Letra -eq 'E').Acao | Should -Be 'Nenhuma'
        $r = @(Optimize-UTDrive)
        Should -Invoke Optimize-Volume -Times 1 -ParameterFilter { $DriveLetter -eq 'C' -and $ReTrim }
        Should -Invoke Optimize-Volume -Times 1 -ParameterFilter { $DriveLetter -eq 'D' -and $Defrag }
        Should -Invoke Optimize-Volume -Times 0 -ParameterFilter { $DriveLetter -eq 'C' -and $Defrag }
        Should -Invoke Optimize-Volume -Times 0 -ParameterFilter { $DriveLetter -eq 'E' }
        ($r | Where-Object Letra -eq 'E').Sucesso | Should -BeFalse
    }
}

Describe 'Arquivo de paginação' {
    It '<Caso>' -TestCases @(
        @{ Caso = 'automático'; P = @{ Automatica = $true; Arquivos = @(); EmUso = $true }; Estado = 'Automatico' }
        @{ Caso = 'desativado'; P = @{ Automatica = $false; Arquivos = @(); EmUso = $false }; Estado = 'Desativado' }
        @{ Caso = 'personalizado'; P = @{ Automatica = $false; Arquivos = @([pscustomobject]@{ Caminho = 'C:\pagefile.sys' }); EmUso = $true }; Estado = 'Personalizado' }
    ) {
        Mock Get-UTSystemSettingsInfo { [pscustomobject]@{ Paginacao = [pscustomobject]$P } }
        (Get-UTPageFileStatus).Estado | Should -Be $Estado
    }

    It 'o ajuste volta para "gerenciado pelo sistema" (?:\pagefile.sys)' {
        $t = Get-UTTweak -Id 'UT_Ferramentas_PaginacaoAuto'
        $t.registro[0].tipo | Should -Be 'MultiString'
        @($t.registro[0].valor) | Should -Be @('?:\pagefile.sys')
    }
}

Describe 'Pausar o Windows Update' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Assert-UTAdmin {}
        Mock Get-UTWindowsUpdatePauseKey { "$UTTestKey\WU" }
        if (Test-UTRegistryKey -Path "$UTTestKey\WU") { Remove-Item -Path "$UTTestKey\WU" -Recurse -Force }
    }
    AfterAll { if (Test-Path "$UTTestKey\WU") { Remove-Item -Path "$UTTestKey\WU" -Recurse -Force } }

    It 'pausa por 14 dias como o app Configurações e retoma' {
        (Get-UTWindowsUpdatePause).Pausado | Should -BeFalse
        $until = Suspend-UTWindowsUpdate -Dias 14
        ($until - (Get-Date)).TotalDays | Should -BeGreaterThan 13.9
        $p = Get-UTWindowsUpdatePause
        $p.Pausado | Should -BeTrue
        $p.Ate.Date | Should -Be $until.Date
        (Get-UTRegistryValue -Path "$UTTestKey\WU" -Name 'PauseQualityUpdatesEndTime').Valor | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
        Resume-UTWindowsUpdate
        (Get-UTWindowsUpdatePause).Pausado | Should -BeFalse
        (Get-UTRegistryValue -Path "$UTTestKey\WU" -Name 'PauseUpdatesExpiryTime').ValorExiste | Should -BeFalse
    }

    It 'nunca mais de 35 dias' {
        { Suspend-UTWindowsUpdate -Dias 36 } | Should -Throw
    }
}

Describe 'Atalhos do sistema' {
    It 'cada atalho abre o comando certo' {
        Mock Start-Process {}
        Open-UTSystemShortcut -Atalho energia
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'control.exe' -and $ArgumentList -eq 'powercfg.cpl' }
        Open-UTSystemShortcut -Atalho dispositivos
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'devmgmt.msc' }
    }
}

Describe 'Guia de BIOS' {
    BeforeAll {
        $checks = @(
            [pscustomobject]@{ Id = 'xmp'; Status = 'OK'; Mensagem = 'DDR5-6000' }
            [pscustomobject]@{ Id = 'rebar'; Status = 'Aviso'; Mensagem = 'Resizable BAR desligado' }
            [pscustomobject]@{ Id = 'secureboot'; Status = 'OK'; Mensagem = 'ligado' }
        )
    }

    It 'Ryzen X3D em placa MSI: itens AMD e X3D, link da MSI e estados do diagnóstico' {
        $hw = [pscustomobject]@{ CpuFabricante = 'amd'; X3D = 'unico'; Plataforma = [pscustomobject]@{ PlacaMae = 'Micro-Star International Co., Ltd. MAG B650 TOMAHAWK'; FabricantePM = 'Micro-Star International Co., Ltd.' } }
        $g = Get-UTBiosGuide -Hardware $hw -Verificacoes $checks
        $g.FabricantePM | Should -Be 'MSI'
        $g.SuportePlaca | Should -Match 'msi.com'
        $g.Chipset.url | Should -Match 'amd.com'
        $ids = @($g.Itens | ForEach-Object Id)
        $ids | Should -Contain 'curveoptimizer'
        $ids | Should -Contain 'x3dnotas'
        $ids | Should -Not -Contain 'intellimites'
        ($g.Itens | Where-Object Id -eq 'xmp').Estado | Should -Be 'Confirmado'
        ($g.Itens | Where-Object Id -eq 'rebar').Estado | Should -Be 'Pendente'
        ($g.Itens | Where-Object Id -eq 'tpm').Estado | Should -Be 'Verificar'
        ($g.Itens | Where-Object Id -eq 'csm').Estado | Should -Be 'Verificar'
    }

    It 'Intel em placa desconhecida: só itens Intel e sem notas de X3D' {
        $hw = [pscustomobject]@{ CpuFabricante = 'intel'; X3D = $null; Plataforma = [pscustomobject]@{ PlacaMae = 'Fabricante X'; FabricantePM = 'Fabricante X' } }
        $g = Get-UTBiosGuide -Hardware $hw -Verificacoes @()
        $ids = @($g.Itens | ForEach-Object Id)
        $ids | Should -Contain 'intellimites'
        $ids | Should -Not -Contain 'pbo'
        $ids | Should -Not -Contain 'x3dnotas'
        $g.SuportePlaca | Should -BeNullOrEmpty
        $g.TeclaBios | Should -Match 'Del'
    }
}
