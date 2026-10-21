BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}
AfterAll { Clear-UTTestEnvironment }

Describe 'DDU automático em Modo de Segurança' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        Mock Suspend-UTBitLockerForBoot {}
        Mock Find-UTProgramExecutable { 'C:\Program Files\Display Driver Uninstaller\Display Driver Uninstaller.exe' }
        $script:native = New-Object System.Collections.Generic.List[string]
        Mock Invoke-UTNative { $script:native.Add((Split-Path -Leaf $FilePath) + ' ' + ($ArgumentList -join ' ')); [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } }
        $script:reg = @{}
        Mock Set-UTRegistryValue { $script:reg["$Path|$Name"] = $Value }
        Mock Remove-UTRegistryValue { [void]$script:reg.Remove("$Path|$Name"); $true }
        Mock Get-UTRegistryValue { [pscustomobject]@{ ValorExiste = $false; Valor = $null } } -ParameterFilter { $Name -eq 'SearchOrderConfig' }
        $installer = Join-Path $TestDrive 'driver-novo.exe'
        Set-Content -LiteralPath $installer -Value 'x'
    }

    It 'prepara tudo e marca o Modo de Segurança por último' {
        $r = Start-UTDduClean -Fabricante nvidia -Instalador $installer -NaoReiniciar -Confirm:$false
        $script:reg['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching|SearchOrderConfig'] | Should -Be 0
        $script:reg['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce|*UpgradeTweaksDDU'] | Should -Match 'etapa-modo-seguranca\.ps1'
        $script:reg['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce|UpgradeTweaksDriver'] | Should -Match 'etapa-depois\.ps1'
        $script:native | Should -Contain 'bcdedit.exe /set {current} safeboot minimal'
        $script:native | Should -Not -Contain 'shutdown.exe /r /t 15 /c Upgrade Tweaks: reiniciando em Modo de Segurança para limpar o driver de vídeo.'
        Should -Invoke Suspend-UTBitLockerForBoot -Times 1 -ParameterFilter { $Reinicios -eq 2 }
        Should -Invoke Invoke-UTPreApplySafety -Times 1
        Test-Path (Join-Path (Get-UTDduFolder) 'driver-novo.exe') | Should -BeTrue
    }

    It 'a etapa do Modo de Segurança tira a flag de boot ANTES de rodar o DDU' {
        $r = Start-UTDduClean -Fabricante amd -Instalador $installer -NaoReiniciar -Confirm:$false
        $lines = @(Get-Content -LiteralPath $r.ModoSeguranca -Encoding UTF8)
        $flag = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match 'deletevalue .*safeboot' })
        $ddu = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match 'Start-Process -FilePath ''C:\\Program Files\\Display Driver Uninstaller' })
        $flag | Should -BeGreaterOrEqual 0
        $ddu | Should -BeGreaterThan $flag
        ($lines -join "`n") | Should -Match "'-Silent', '-CleanAmd', '-NoSafeModeMsg'"
        $after = Get-Content -LiteralPath $r.Depois -Raw -Encoding UTF8
        $after | Should -Match 'driver-novo\.exe'
        $after | Should -Match "Remove-ItemProperty .*SearchOrderConfig"
        { [scriptblock]::Create((Get-Content -LiteralPath $r.ModoSeguranca -Raw)) } | Should -Not -Throw
        { [scriptblock]::Create($after) } | Should -Not -Throw
    }

    It 'guarda e devolve o valor que o Windows Update tinha' {
        Mock Get-UTRegistryValue { [pscustomobject]@{ ValorExiste = $true; Valor = 1 } } -ParameterFilter { $Name -eq 'SearchOrderConfig' }
        $r = Start-UTDduClean -Fabricante intel -Instalador $installer -NaoReiniciar -Confirm:$false
        Get-Content -LiteralPath $r.Depois -Raw | Should -Match "SearchOrderConfig' -Value 1 -Type DWord"
    }

    It 'se o bcdedit falhar, desfaz o que preparou e avisa' {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 1; Saida = 'acesso negado'; Erro = '' } } -ParameterFilter { $ArgumentList -contains 'minimal' }
        { Start-UTDduClean -Fabricante nvidia -Instalador $installer -NaoReiniciar -Confirm:$false } | Should -Throw '*Modo de Segurança*'
        $script:reg.ContainsKey('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce|*UpgradeTweaksDDU') | Should -BeFalse
    }

    It 'sem instalador do driver novo, nada é feito' {
        { Start-UTDduClean -Fabricante nvidia -Instalador (Join-Path $TestDrive 'nao.exe') -NaoReiniciar -Confirm:$false } | Should -Throw '*Instalador do driver não encontrado*'
        Should -Invoke Invoke-UTNative -Times 0
    }

    It 'reinicia em 15 segundos quando não pedem para esperar' {
        Start-UTDduClean -Fabricante nvidia -Instalador $installer -Confirm:$false | Out-Null
        @($script:native | Where-Object { $_ -like 'shutdown.exe /r /t 15*' }).Count | Should -Be 1
    }
}
