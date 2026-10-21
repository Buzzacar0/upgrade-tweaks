BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null; Executaveis = @('C:\Jogo\cod.exe') }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Catálogo completo' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx }

    It 'tem ajustes em todas as abas previstas' {
        $categories = @(Get-UTTweak | ForEach-Object { $_.categoria } | Sort-Object -Unique)
        foreach ($c in 'Energia', 'Gaming', 'Latencia', 'Rede', 'ServicosApps', 'Privacidade', 'Visual', 'Personalizar', 'Warzone') {
            $categories | Should -Contain $c
        }
    }

    It 'todo ajuste de risco alto pede confirmação e está desmarcado no Seguro (risco alto nunca é baixo)' {
        foreach ($t in @(Get-UTTweak | Where-Object { $_.risco -eq 'alto' })) {
            [string]$t.confirmacao | Should -Not -BeNullOrEmpty -Because $t.id
        }
    }

    It 'não há mitos proibidos no catálogo' {
        $text = (Get-ChildItem (Join-Path $UTTestRepoRoot 'config') -Filter 'tweaks*.json' | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $text | Should -Not -Match '(?i)useplatformclock'
        $text | Should -Not -Match '(?i)EmptyStandbyList|limpador de RAM'
        $text | Should -Not -Match '(?i)\\Prefetch'
        $text | Should -Not -Match '(?i)DisableAntiSpyware|DisableRealtimeMonitoring'
        $text | Should -Not -Match '(?i)NoAutoUpdate|DisableWindowsUpdateAccess'
        $text | Should -Not -Match '(?i)EnableLUA'
    }

    It 'nenhum ajuste desativa serviços essenciais (Defender, Windows Update, Store, Game Bar)' {
        $forbidden = 'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'InstallService', 'GamingServices', 'GamingServicesNet', 'XboxGipSvc', 'BcastDVRUserService'
        foreach ($t in @(Get-UTTweak)) {
            foreach ($s in @($t.servicos | Where-Object { $_ })) {
                if ($s.inicio -eq 'Disabled') { $forbidden | Should -Not -Contain $s.nome -Because $t.id }
            }
        }
    }
}

Describe 'Modo Lite' {
    BeforeEach { Reset-UTTestEnvironment; Set-Ctx }

    It 'todos os ids da lista existem no catálogo' {
        $all = @(Get-UTTweak | ForEach-Object { $_.id })
        foreach ($id in @((Get-UTConfig -Name 'modo-lite').incluir)) { $all | Should -Contain $id }
    }

    It 'inclui os apps e nunca os serviços do Xbox nem o Spooler' {
        $plan = @(Get-UTLiteModePlan)
        $ids = @($plan | ForEach-Object { $_.Id })
        $ids | Should -Contain 'UT_App_Clipchamp_Clipchamp'
        $ids | Should -Contain 'UT_Lite_RemoveEdge'
        $ids | Should -Not -Contain 'UT_Svc_XblAuthManager'
        $ids | Should -Not -Contain 'UT_Svc_Spooler'
        $ids | Should -Not -Contain 'UT_App_MicrosoftCorporationII_QuickAssist'
    }

    It 'itens incompatíveis com o PC vêm desmarcados e com o motivo' {
        Set-Ctx @{ WindowsGeracao = '10'; Build = 19045 }
        $recall = @(Get-UTLiteModePlan | Where-Object Id -eq 'UT_Privacy_Recall_Off')[0]
        $recall.Marcado | Should -BeFalse
        $recall.Motivo | Should -Match 'Windows 11'
    }

    It 'recusa aplicar algo que não está no Modo Lite' {
        { Invoke-UTLiteMode -Id 'UT_Lat_Spectre_Off' } | Should -Throw '*não fazem parte do Modo Lite*'
    }

    It 'simulação do Modo Lite não altera nada' {
        $r = @(Invoke-UTLiteMode -Id 'UT_Privacy_AdvertisingId_Off', 'UT_Privacy_ActivityHistory_Off' -WhatIf)
        @($r | Where-Object { $_.Status -notin 'Simulado', 'JaAplicado' }).Count | Should -Be 0
    }
}
