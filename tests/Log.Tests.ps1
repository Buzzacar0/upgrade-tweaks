BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'functions\private\Paths.ps1')
    . (Join-Path $repoRoot 'functions\private\Log.ps1')
}

Describe 'Get-UTPath' {
    BeforeEach {
        $utHome = Join-Path $TestDrive ('ut' + [guid]::NewGuid().ToString('N'))
        $env:UPGRADETWEAKS_HOME = $utHome
    }
    AfterEach { $env:UPGRADETWEAKS_HOME = $null }

    It 'usa a pasta definida em UPGRADETWEAKS_HOME' {
        Get-UTPath | Should -Be $utHome
        Get-UTPath -Name Logs | Should -Be (Join-Path $utHome 'logs')
        Get-UTPath -Name Backups | Should -Be (Join-Path $utHome 'backups')
        Get-UTPath -Name State | Should -Be (Join-Path $utHome 'state')
    }

    It 'usa o ProgramData quando a variável não existe' {
        $env:UPGRADETWEAKS_HOME = $null
        Get-UTPath | Should -Be (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'UpgradeTweaks')
    }

    It 'Initialize-UTFolder cria as quatro pastas e é idempotente' {
        $first = Initialize-UTFolder
        $first.Count | Should -Be 4
        foreach ($n in 'Root', 'Logs', 'Backups', 'State') { Test-Path (Get-UTPath -Name $n) | Should -BeTrue }
        @(Initialize-UTFolder).Count | Should -Be 0
    }

    It 'Initialize-UTFolder -WhatIf não cria nada' {
        Initialize-UTFolder -WhatIf | Out-Null
        Test-Path (Get-UTPath) | Should -BeFalse
    }
}

Describe 'Write-UTLog' {
    BeforeEach {
        $env:UPGRADETWEAKS_HOME = Join-Path $TestDrive ('ut' + [guid]::NewGuid().ToString('N'))
        $UTSync = [hashtable]::Synchronized(@{ Silencioso = $true })
        $logFile = Join-Path (Get-UTPath -Name Logs) ((Get-Date).ToString('yyyy-MM-dd') + '.log')
    }
    AfterEach { $env:UPGRADETWEAKS_HOME = $null }

    It 'grava nível, id do tweak e valores antes/depois' {
        Write-UTLog -Level Sucesso -TweakId 'UT_Teste' -Message 'Aplicado' -Antes 1 -Depois 0
        $line = Get-Content -LiteralPath $logFile -Encoding UTF8 | Select-Object -Last 1
        $line | Should -Match '\[SUCESSO\] \[UT_Teste\] Aplicado \| antes=1 depois=0$'
        $line | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} '
    }

    It 'mostra <ausente> quando o valor anterior não existia' {
        Write-UTLog -Message 'Criado' -Antes $null -Depois 5
        Get-Content -LiteralPath $logFile -Encoding UTF8 | Select-Object -Last 1 | Should -Match 'antes=<ausente> depois=5'
    }

    It 'preserva os acentos (arquivo em UTF-8 com BOM)' {
        Write-UTLog -Message 'Não foi possível alterar o serviço'
        $bytes = [IO.File]::ReadAllBytes($logFile)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        [IO.File]::ReadAllText($logFile, [Text.Encoding]::UTF8) | Should -Match 'Não foi possível alterar o serviço'
    }

    It 'grava o detalhe técnico só no arquivo' {
        $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $UTSync.LogQueue = $queue
        Write-UTLog -Level Erro -Message 'Falhou' -Detalhe 'HRESULT 0x80070005'
        Get-Content -LiteralPath $logFile -Encoding UTF8 | Select-Object -Last 1 | Should -Match 'detalhe: HRESULT 0x80070005'
        $entry = $null
        $queue.TryDequeue([ref]$entry) | Should -BeTrue
        $entry.Linha | Should -Not -Match 'HRESULT'
        $entry.Nivel | Should -Be 'Erro'
    }

    It 'não escreve no console em modo silencioso' {
        Mock Write-UTConsole {}
        Write-UTLog -Message 'quieto'
        Should -Invoke Write-UTConsole -Times 0
    }

    It 'escreve no console colorido pelo nível fora do modo silencioso' {
        $UTSync.Silencioso = $false
        Mock Write-UTConsole {}
        Write-UTLog -Level Aviso -Message 'atenção'
        Should -Invoke Write-UTConsole -Times 1 -ParameterFilter { $Color -eq 'Yellow' -and $Text -match 'atenção' }
    }

    It 'funciona mesmo sem a tabela $UTSync' {
        Remove-Variable -Name UTSync -ErrorAction SilentlyContinue
        Mock Write-UTConsole {}
        { Write-UTLog -Message 'sem sync' } | Should -Not -Throw
        Get-Content -LiteralPath $logFile -Encoding UTF8 | Select-Object -Last 1 | Should -Match 'sem sync'
    }

    It 'não perde linhas com escrita simultânea de vários runspaces' {
        $functions = @(
            (Get-Content (Join-Path $repoRoot 'functions\private\Paths.ps1') -Raw -Encoding UTF8),
            (Get-Content (Join-Path $repoRoot 'functions\private\Log.ps1') -Raw -Encoding UTF8)
        ) -join "`n"
        $utHome = $env:UPGRADETWEAKS_HOME
        $pool = [runspacefactory]::CreateRunspacePool(1, 4)
        $pool.Open()
        $jobs = foreach ($n in 1..4) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript({
                param($code, $root, $id)
                $env:UPGRADETWEAKS_HOME = $root
                $UTSync = [hashtable]::Synchronized(@{ Silencioso = $true })
                . ([scriptblock]::Create($code))
                foreach ($i in 1..25) { Write-UTLog -Message "runspace $id linha $i" }
            }).AddArgument($functions).AddArgument($utHome).AddArgument($n)
            [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
        }
        foreach ($j in $jobs) { $j.PS.EndInvoke($j.Handle); $j.PS.Dispose() }
        $pool.Close()
        @(Get-Content -LiteralPath $logFile -Encoding UTF8 | Where-Object { $_ -match 'runspace \d linha' }).Count | Should -Be 100
    }
}

Describe 'Remove-UTOldLog' {
    BeforeEach {
        $env:UPGRADETWEAKS_HOME = Join-Path $TestDrive ('ut' + [guid]::NewGuid().ToString('N'))
        $logs = Get-UTPath -Name Logs
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $hoje = [datetime]'2026-10-20'
        foreach ($d in 0, 30, 31, 90) {
            Set-Content -LiteralPath (Join-Path $logs ($hoje.AddDays(-$d).ToString('yyyy-MM-dd') + '.log')) -Value 'x'
        }
        Set-Content -LiteralPath (Join-Path $logs 'outro.log') -Value 'x'
    }
    AfterEach { $env:UPGRADETWEAKS_HOME = $null }

    It 'remove só os logs diários com mais de 30 dias' {
        $removed = Remove-UTOldLog -Dias 30 -Hoje $hoje
        $removed.Count | Should -Be 2
        $left = (Get-ChildItem -LiteralPath $logs).Name | Sort-Object
        $left | Should -Be @('2026-09-20.log', '2026-10-20.log', 'outro.log')
    }

    It 'não remove nada com -WhatIf' {
        Remove-UTOldLog -Dias 30 -Hoje $hoje -WhatIf | Out-Null
        (Get-ChildItem -LiteralPath $logs).Count | Should -Be 5
    }
}
