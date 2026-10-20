BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'functions\private\Paths.ps1')
    . (Join-Path $repoRoot 'functions\private\Log.ps1')
    . (Join-Path $repoRoot 'functions\private\Admin.ps1')
    $url = 'https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1'
}

Describe 'Assert-UTAdmin' {
    It 'lança erro em PT-BR quando não é administrador' {
        Mock Test-UTAdmin { $false }
        { Assert-UTAdmin } | Should -Throw '*precisa ser executado como administrador*'
    }
    It 'não faz nada quando é administrador' {
        Mock Test-UTAdmin { $true }
        { Assert-UTAdmin } | Should -Not -Throw
    }
}

Describe 'ConvertTo-UTArgumentString' {
    It 'devolve vazio para nenhum parâmetro' {
        ConvertTo-UTArgumentString -Parameters @{} | Should -Be ''
        ConvertTo-UTArgumentString -Parameters $null | Should -Be ''
    }
    It 'repassa switches ligados e descarta desligados' {
        $p = [ordered]@{
            Silencioso = [System.Management.Automation.SwitchParameter]$true
            Simular    = [System.Management.Automation.SwitchParameter]$false
        }
        ConvertTo-UTArgumentString -Parameters $p | Should -Be '-Silencioso'
    }
    It 'coloca valores entre aspas e ordena por nome' {
        $p = @{ Preset = 'Seguro'; Config = 'C:\Minha Pasta\config.json' }
        ConvertTo-UTArgumentString -Parameters $p | Should -Be '-Config "C:\Minha Pasta\config.json" -Preset "Seguro"'
    }
    It 'escapa aspas e barras finais para a linha de comando do Windows' {
        ConvertTo-UTArgumentString -Parameters @{ Config = 'a"b' } | Should -Be '-Config "a\"b"'
        ConvertTo-UTArgumentString -Parameters @{ Config = 'C:\pasta\' } | Should -Be '-Config "C:\pasta\\"'
    }
}

Describe 'Invoke-UTElevation' {
    BeforeEach {
        $env:UPGRADETWEAKS_HOME = Join-Path $TestDrive 'ut'
        Mock Write-UTConsole {}
        Mock Get-UTPowerShellPath { 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
    }
    AfterEach { $env:UPGRADETWEAKS_HOME = $null }

    It 'relança o mesmo arquivo com -Verb RunAs e os parâmetros' {
        Mock Start-Process {}
        Mock Save-UTRemoteScript { throw 'não deveria baixar' }
        $r = Invoke-UTElevation -ScriptPath 'C:\x\upgradetweaks.ps1' -BoundParameters @{ Preset = 'Seguro' } -ReleaseUrl $url
        $r.Iniciado | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $Verb -eq 'RunAs' -and
            $ArgumentList -eq '-NoProfile -ExecutionPolicy Bypass -File "C:\x\upgradetweaks.ps1" -Preset "Seguro"'
        }
        Should -Invoke Save-UTRemoteScript -Times 0
    }

    It 'sem arquivo (irm | iex) baixa a Release para a pasta temporária e roda de lá' {
        Mock Start-Process {}
        Mock Save-UTRemoteScript { $Destination }
        $r = Invoke-UTElevation -ScriptPath $null -BoundParameters @{} -ReleaseUrl $url
        $r.Iniciado | Should -BeTrue
        $expected = Join-Path ([IO.Path]::GetTempPath()) 'UpgradeTweaks\upgradetweaks.ps1'
        Should -Invoke Save-UTRemoteScript -Times 1 -ParameterFilter { $Url -eq $url -and $Destination -eq $expected }
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $ArgumentList -like "*-File `"$expected`"" }
    }

    It 'com -Wait espera o processo elevado e devolve o código de saída' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 3 } }
        $r = Invoke-UTElevation -ScriptPath 'C:\x\a.ps1' -BoundParameters @{ Silencioso = [switch]$true } -ReleaseUrl $url -Wait
        $r.CodigoSaida | Should -Be 3
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $Wait -and $PassThru }
    }

    It 'UAC recusado: não inicia e devolve mensagem clara em PT-BR' {
        Mock Start-Process { throw [System.InvalidOperationException]'The operation was canceled by the user' }
        $r = Invoke-UTElevation -ScriptPath 'C:\x\a.ps1' -BoundParameters @{} -ReleaseUrl $url
        $r.Iniciado | Should -BeFalse
        $r.Mensagem | Should -Match 'precisa ser executado como administrador'
    }

    It 'falha no download também vira mensagem, sem exceção' {
        Mock Start-Process {}
        Mock Save-UTRemoteScript { throw 'sem internet' }
        $r = Invoke-UTElevation -ScriptPath '' -BoundParameters @{} -ReleaseUrl $url
        $r.Iniciado | Should -BeFalse
        Should -Invoke Start-Process -Times 0
    }

    It '-WhatIf não inicia nenhum processo' {
        Mock Start-Process {}
        $r = Invoke-UTElevation -ScriptPath 'C:\x\a.ps1' -BoundParameters @{} -ReleaseUrl $url -WhatIf
        $r.Iniciado | Should -BeFalse
        Should -Invoke Start-Process -Times 0
    }
}

Describe 'Get-UTPowerShellPath' {
    It 'usa o Sysnative quando um PowerShell 32 bits roda num Windows 64 bits' {
        Mock Test-UTNeeds64BitRelaunch { $true }
        Get-UTPowerShellPath | Should -Match 'Sysnative\\WindowsPowerShell\\v1\.0\\powershell\.exe$'
    }
    It 'usa o executável atual nos demais casos' {
        Mock Test-UTNeeds64BitRelaunch { $false }
        Get-UTPowerShellPath | Should -Be (Get-Process -Id $PID).Path
    }
}
