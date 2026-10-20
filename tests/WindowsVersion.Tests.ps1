BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'functions\private\WindowsVersion.ps1')
    # Test hive allowed by the project rules; removed in AfterAll.
    $testKey = 'HKCU:\Software\UpgradeTweaksTest\CurrentVersion'
}

AfterAll {
    Remove-Item -LiteralPath 'HKCU:\Software\UpgradeTweaksTest' -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-UTWindowsInfo' {
    BeforeEach {
        Remove-Item -LiteralPath $testKey -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $testKey -Force | Out-Null
    }

    It 'identifica o Windows 11 pelo build, mesmo com ProductName dizendo Windows 10' {
        New-ItemProperty -Path $testKey -Name ProductName -Value 'Windows 10 Pro' | Out-Null
        New-ItemProperty -Path $testKey -Name CurrentBuild -Value '26200' | Out-Null
        New-ItemProperty -Path $testKey -Name UBR -Value 6899 -PropertyType DWord | Out-Null
        New-ItemProperty -Path $testKey -Name DisplayVersion -Value '25H2' | Out-Null
        New-ItemProperty -Path $testKey -Name EditionID -Value 'Professional' | Out-Null
        $info = Get-UTWindowsInfo -RegistryPath $testKey
        $info.Geracao | Should -Be '11'
        $info.Build | Should -Be 26200
        $info.Versao | Should -Be '25H2'
        $info.EhHome | Should -BeFalse
        $info.Descricao | Should -Be 'Windows 11 Professional 25H2 (build 26200.6899)'
    }

    It 'reconhece Windows 10 e edição Home' {
        New-ItemProperty -Path $testKey -Name CurrentBuild -Value '19045' | Out-Null
        New-ItemProperty -Path $testKey -Name ReleaseId -Value '2009' | Out-Null
        New-ItemProperty -Path $testKey -Name EditionID -Value 'Core' | Out-Null
        $info = Get-UTWindowsInfo -RegistryPath $testKey
        $info.Geracao | Should -Be '10'
        $info.Versao | Should -Be '2009'
        $info.UBR | Should -Be 0
        $info.EhHome | Should -BeTrue
    }

    It 'lê a máquina real sem erro' {
        { Get-UTWindowsInfo } | Should -Not -Throw
    }
}

Describe 'Get-UTWindowsSupport' {
    It 'build <Build> -> <Status>' -TestCases @(
        @{ Build = 19044; Status = 'NaoSuportado' }
        @{ Build = 19045; Status = 'Aviso' }
        @{ Build = 22000; Status = 'NaoSuportado' }
        @{ Build = 22621; Status = 'NaoSuportado' }
        @{ Build = 22631; Status = 'OK' }
        @{ Build = 26100; Status = 'OK' }
        @{ Build = 26200; Status = 'OK' }
        @{ Build = 27000; Status = 'OK' }
    ) {
        $info = [pscustomobject]@{ Build = $Build; Descricao = "build $Build" }
        $s = Get-UTWindowsSupport -Info $info
        $s.Status | Should -Be $Status
        $s.Suportado | Should -Be ($Status -ne 'NaoSuportado')
        $s.Mensagem | Should -Not -BeNullOrEmpty
    }

    It 'avisa sobre o fim do suporte do Windows 10' {
        (Get-UTWindowsSupport -Info ([pscustomobject]@{ Build = 19045; Descricao = 'x' })).Mensagem | Should -Match '14/10/2025'
    }
}
