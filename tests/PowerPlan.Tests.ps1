BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $proc = '54533251-82be-4824-96c1-47b60b740d00'
    $procMin = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    $parking = '0cc5b647-c1df-4637-891a-dec35c318583'
    $idle = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
    $videoSub = '7516b95f-f776-4464-8c53-06167f40cc99'
    $video = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
    $nvmeIdle = '0012ee47-9041-4b5d-9b77-535fba8b1442|d639518a-e56d-4345-8af2-b9f32fb26109'

    function New-FakeScheme([string]$Name) {
        # Every setting of powerplan.json, starting at a "Balanced-like" value.
        $settings = @{}
        foreach ($s in (Get-Content (Join-Path $UTTestRepoRoot 'config\powerplan.json') -Raw -Encoding UTF8 | ConvertFrom-Json).configuracoes) {
            $settings["$($s.subgrupo)|$($s.configuracao)"] = @{ ac = 5; dc = 3 }
        }
        $settings["$proc|$idle"] = @{ ac = 0; dc = 0 }
        return @{ nome = $Name; settings = $settings }
    }

    function Reset-FakePowerCfg {
        $script:pc = @{
            schemes   = [ordered]@{ $balanced = (New-FakeScheme 'Equilibrado'); $high = (New-FakeScheme 'Alto desempenho'); $ultimate = (New-FakeScheme 'Desempenho Máximo') }
            active    = $balanced
            refuse    = @()
            calls     = New-Object System.Collections.Generic.List[string]
            nextGuid  = 1
        }
    }

    function Invoke-FakePowerCfg([string[]]$a) {
        $ok = { param($text) [pscustomobject]@{ CodigoSaida = 0; Saida = $text; Erro = '' } }
        $fail = { param($text) [pscustomobject]@{ CodigoSaida = 1; Saida = $text; Erro = '' } }
        $script:pc.calls.Add(($a -join ' '))
        switch ($a[0]) {
            '/list' {
                $lines = foreach ($g in $script:pc.schemes.Keys) {
                    $mark = $(if ($g -eq $script:pc.active) { ' *' } else { '' })
                    "GUID do Esquema de Energia: $g  ($($script:pc.schemes[$g].nome))$mark"
                }
                return (& $ok ("Esquemas de Energia Existentes (* Ativos)`n---`n" + ($lines -join "`n")))
            }
            '/getactivescheme' { return (& $ok "GUID do Esquema de Energia: $($script:pc.active)  ($($script:pc.schemes[$script:pc.active].nome))") }
            '/duplicatescheme' {
                if ($script:pc.refuse -contains $a[1] -or -not $script:pc.schemes.Contains($a[1])) { return (& $fail 'Não é possível executar a operação.') }
                $g = '00000000-0000-0000-0000-{0:D12}' -f $script:pc.nextGuid
                $script:pc.nextGuid++
                $copy = New-FakeScheme $script:pc.schemes[$a[1]].nome
                foreach ($k in @($script:pc.schemes[$a[1]].settings.Keys)) { $copy.settings[$k] = $script:pc.schemes[$a[1]].settings[$k].Clone() }
                $script:pc.schemes[$g] = $copy
                return (& $ok "GUID do Esquema de Energia: $g  ($($copy.nome))")
            }
            '/changename' { $script:pc.schemes[$a[1]].nome = $a[2]; return (& $ok '') }
            '/setactive' { if (-not $script:pc.schemes.Contains($a[1])) { return (& $fail 'inválido') }; $script:pc.active = $a[1]; return (& $ok '') }
            '/delete' { $script:pc.schemes.Remove($a[1]); return (& $ok '') }
            { $_ -in '/setacvalueindex', '/setdcvalueindex' } {
                $key = "$($a[2])|$($a[3])"
                $setting = $script:pc.schemes[$a[1]].settings[$key]
                if ($null -eq $setting) { return (& $fail 'Parâmetros inválidos') }
                if ($a[0] -eq '/setacvalueindex') { $setting.ac = [long]$a[4] } else { $setting.dc = [long]$a[4] }
                return (& $ok '')
            }
            '/qh' {
                $scheme = $script:pc.schemes[$a[1]]
                $setting = $null
                if ($scheme) { $setting = $scheme.settings["$($a[2])|$($a[3])"] }
                if ($null -eq $setting) { return (& $ok '') }
                return (& $ok ("GUID do Esquema de Energia: $($a[1])  (x)`n  GUID de Subgrupos: $($a[2])`n    GUID de Configuração de Energia: $($a[3])  (y)`n      Valor mínimo: 0x00000000`n      Valor máximo: 0x00000064`n    Índice de Configurações de Correntes Alternadas Atuais: 0x{0:x8}`n    Índice de Configurações de Correntes Contínuas Atuais: 0x{1:x8}" -f $setting.ac, $setting.dc))
            }
            '/export' { Set-Content -LiteralPath $a[1] -Value 'pow'; return (& $ok '') }
            '/import' {
                $g = '00000000-0000-0000-0000-{0:D12}' -f (900 + $script:pc.nextGuid)
                $script:pc.nextGuid++
                $script:pc.schemes[$g] = New-FakeScheme 'Importado'
                return (& $ok "Esquema de energia importado com êxito. GUID: $g")
            }
            default { return (& $ok '') }
        }
    }

    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }

    function Get-Upgrade { @($script:pc.schemes.Keys | Where-Object { $script:pc.schemes[$_].nome -like 'Upgrade Warzone*' }) }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Plano Upgrade Warzone' {
    BeforeEach {
        Reset-UTTestEnvironment
        Reset-FakePowerCfg
        Set-Ctx
        Mock Invoke-UTNative { Invoke-FakePowerCfg $ArgumentList } -ParameterFilter { $FilePath -eq 'powercfg.exe' }
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
    }

    It 'desktop: duplica o Desempenho Máximo, aplica tudo na tomada e na bateria e ativa' {
        (Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Aplicado'
        $g = @(Get-Upgrade)
        $g.Count | Should -Be 1
        $script:pc.active | Should -Be $g[0]
        $plan = $script:pc.schemes[$g[0]]
        $plan.nome | Should -Be 'Upgrade Warzone'
        $plan.settings["$proc|$procMin"].ac | Should -Be 100
        $plan.settings["$proc|$procMin"].dc | Should -Be 100
        $plan.settings["$proc|$parking"].ac | Should -Be 100
        $plan.settings["$videoSub|$video"].ac | Should -Be 900
        $script:pc.calls | Should -Contain "/duplicatescheme $ultimate"
        (Get-UTTweakState -Id 'UT_Power_UpgradeWarzone').Estado | Should -Be 'Aplicado'
    }

    It 'desfazer volta ao plano anterior e apaga o plano criado' {
        $script:pc.active = $high
        Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone' | Out-Null
        (Undo-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Desfeito'
        $script:pc.active | Should -Be $high
        @(Get-Upgrade).Count | Should -Be 0
        (Get-UTTweakState -Id 'UT_Power_UpgradeWarzone').Estado | Should -Be 'NaoAplicado'
    }

    It 'sem Desempenho Máximo, usa o Alto Desempenho' {
        $script:pc.refuse = @($ultimate)
        (Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Aplicado'
        $script:pc.calls | Should -Contain "/duplicatescheme $high"
    }

    It 'reaplicar reaproveita o plano e mantém o plano anterior original' {
        Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone' | Out-Null
        $script:pc.active = $high   # the user switched by hand
        (Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Aplicado'
        @(Get-Upgrade).Count | Should -Be 1
        @($script:pc.calls | Where-Object { $_ -like '/duplicatescheme*' }).Count | Should -Be 1
        Undo-UTTweak -Id 'UT_Power_UpgradeWarzone' | Out-Null
        $script:pc.active | Should -Be $balanced
    }

    It 'configuração opcional que não existe no Windows é pulada sem falhar' {
        foreach ($s in $script:pc.schemes.Values) { $s.settings.Remove($nvmeIdle) }
        (Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Aplicado'
    }

    It 'respeita os minutos escolhidos para desligar o vídeo' {
        $UTSync.OpcoesEnergia = @{ MinutosVideo = 5 }
        Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone' | Out-Null
        $script:pc.schemes[@(Get-Upgrade)[0]].settings["$videoSub|$video"].ac | Should -Be 300
    }

    It 'notebook: parte do Equilibrado, nome "(na tomada)" e não mexe na bateria' {
        Set-Ctx @{ EhNotebook = $true }
        (Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Aplicado'
        $script:pc.calls | Should -Contain "/duplicatescheme $balanced"
        $plan = $script:pc.schemes[@(Get-Upgrade)[0]]
        $plan.nome | Should -Be 'Upgrade Warzone (na tomada)'
        $plan.settings["$proc|$procMin"].ac | Should -Be 100
        $plan.settings["$proc|$procMin"].dc | Should -Be 3
        @($script:pc.calls | Where-Object { $_ -like '/setdcvalueindex*' }).Count | Should -Be 0
    }

    It 'X3D de um CCD usa o plano normalmente e não vê o ajuste de dois CCDs' {
        Set-Ctx @{ X3D = 'unico' }
        (Get-UTTweakState -Id 'UT_Power_X3DDuplo_Equilibrado').Estado | Should -Be 'Incompativel'
        (Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone').Status | Should -Be 'Aplicado'
        (Invoke-UTTweak -Id 'UT_Power_X3DDuplo_Equilibrado').Status | Should -Be 'Ignorado'
    }

    It 'simular mostra o plano que será criado e cada valor atual -> novo' {
        $r = Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone' -WhatIf
        $r.Status | Should -Be 'Simulado'
        $r.Acoes | Should -Contain "Cria o plano 'Upgrade Warzone' a partir do Desempenho Máximo (Ultimate Performance)"
        $r.Acoes | Should -Contain 'Estado mínimo do processador: 5 -> 100'
        $r.Acoes | Should -Contain 'Ativa o plano (hoje está ativo: Equilibrado)'
        @(Get-Upgrade).Count | Should -Be 0
        @($script:pc.calls | Where-Object { $_ -match '^/(duplicatescheme|setactive|setacvalueindex)' }).Count | Should -Be 0
    }

    It 'simular o desfazer diz para qual plano volta e que apaga o criado' {
        Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone' | Out-Null
        $u = Undo-UTTweak -Id 'UT_Power_UpgradeWarzone' -WhatIf
        $u.Acoes | Should -Contain "Ativa de novo o plano 'Equilibrado'"
        $u.Acoes | Should -Contain "Apaga o plano 'Upgrade Warzone' criado pelo Upgrade Tweaks"
    }
}

Describe 'Ryzen X3D de dois CCDs' {
    BeforeEach {
        Reset-UTTestEnvironment
        Reset-FakePowerCfg
        Set-Ctx @{ X3D = 'duplo' }
        Mock Invoke-UTNative { Invoke-FakePowerCfg $ArgumentList } -ParameterFilter { $FilePath -eq 'powercfg.exe' }
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = 'Automatic'; Status = 'Running' } }
        Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.XboxGamingOverlay' } }
    }

    It 'NÃO aplica o Upgrade Warzone (nem com tudo selecionado)' {
        $r = Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone'
        $r.Status | Should -Be 'Ignorado'
        $r.Mensagem | Should -Match 'dois CCDs'
        @(Get-Upgrade).Count | Should -Be 0
    }

    It 'a função do plano também recusa se for chamada direto' {
        { Invoke-UTPowerPlanCore -TweakId 'x' -Contexto $UTSync.Contexto } | Should -Throw '*dois CCDs*'
    }

    It 'volta para o Equilibrado e o desfazer devolve o plano anterior' {
        $script:pc.active = $high
        (Invoke-UTTweak -Id 'UT_Power_X3DDuplo_Equilibrado').Status | Should -Be 'Aplicado'
        $script:pc.active | Should -Be $balanced
        Undo-UTTweak -Id 'UT_Power_X3DDuplo_Equilibrado' | Out-Null
        $script:pc.active | Should -Be $high
    }

    It 'o status da aba Energia explica e confere driver, Game Bar, Modo de Jogo e plano' {
        $s = Get-UTPowerPlanStatus
        $s.Modo | Should -Be 'x3dDuplo'
        $s.Mensagem | Should -Match 'NÃO deve usar o plano Upgrade Warzone'
        @($s.ChecagensX3D).Count | Should -Be 4
        @($s.ChecagensX3D | Where-Object { -not $_.Ok }).Count | Should -Be 0
    }

    It 'acusa driver de chipset da AMD ausente' {
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $false; StartType = $null; Status = $null } }
        $c = @(Get-UTX3DDualCheck)[0]
        $c.Ok | Should -BeFalse
        $c.Mensagem | Should -Match 'driver de chipset da AMD'
    }

    It 'sem saber o tipo de X3D, o ajuste de dois CCDs fica bloqueado' {
        Set-Ctx @{ X3D = $null }
        (Invoke-UTTweak -Id 'UT_Power_X3DDuplo_Equilibrado').Status | Should -Be 'Ignorado'
    }
}

Describe 'IDLEDISABLE (risco alto)' {
    BeforeEach {
        Reset-UTTestEnvironment
        Reset-FakePowerCfg
        Set-Ctx
        Mock Invoke-UTNative { Invoke-FakePowerCfg $ArgumentList } -ParameterFilter { $FilePath -eq 'powercfg.exe' }
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
    }

    It 'pede confirmação, aplica no plano ativo e o desfazer volta o valor' {
        (Invoke-UTTweak -Id 'UT_Power_IdleDisable').Status | Should -Be 'PrecisaConfirmacao'
        (Invoke-UTTweak -Id 'UT_Power_IdleDisable' -RiscoAltoConfirmado).Status | Should -Be 'Aplicado'
        $script:pc.schemes[$balanced].settings["$proc|$idle"].ac | Should -Be 1
        Undo-UTTweak -Id 'UT_Power_IdleDisable' | Out-Null
        $script:pc.schemes[$balanced].settings["$proc|$idle"].ac | Should -Be 0
    }

    It 'é bloqueado em notebook' {
        Set-Ctx @{ EhNotebook = $true }
        (Invoke-UTTweak -Id 'UT_Power_IdleDisable' -RiscoAltoConfirmado).Status | Should -Be 'Ignorado'
    }
}

Describe 'Ferramentas da aba Energia' {
    BeforeEach {
        Reset-UTTestEnvironment
        Reset-FakePowerCfg
        Set-Ctx
        Mock Invoke-UTNative { Invoke-FakePowerCfg $ArgumentList } -ParameterFilter { $FilePath -eq 'powercfg.exe' }
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
    }

    It 'exporta o plano ativo e importa ativando' {
        $p = Join-Path $TestDrive 'meu.pow'
        Export-UTPowerPlan -Path $p | Should -Be $p
        $script:pc.calls | Should -Contain "/export $p $balanced"
        $g = Import-UTPowerPlan -Path $p -Ativar
        $script:pc.active | Should -Be $g
    }

    It '"Voltar para o plano anterior" desfaz o Upgrade Warzone' {
        $script:pc.active = $high
        Invoke-UTTweak -Id 'UT_Power_UpgradeWarzone' | Out-Null
        (Restore-UTPreviousPowerPlan).Status | Should -Be 'Desfeito'
        $script:pc.active | Should -Be $high
    }

    It 'status padrão e de notebook' {
        (Get-UTPowerPlanStatus).Modo | Should -Be 'padrao'
        Set-Ctx @{ EhNotebook = $true }
        (Get-UTPowerPlanStatus).Mensagem | Should -Match 'bateria'
    }
}

Describe 'powercfg real deste PC (só leitura)' {
    BeforeAll { Reset-UTTestEnvironment }

    It 'lista os planos com o ativo marcado' {
        $list = @(Get-UTPowerSchemeList)
        $list.Count | Should -BeGreaterThan 0
        @($list | Where-Object Ativo).Count | Should -Be 1
    }

    It 'lê o estado máximo do processador do plano ativo (também com /qh)' {
        $active = (Get-UTActivePowerScheme).Guid
        $v = Get-UTPowerSettingValue -Esquema $active -Subgrupo $proc -Configuracao 'bc5038f7-23e0-4960-96da-33abaf5935ec'
        $v.Existe | Should -BeTrue
        $v.AC | Should -BeGreaterThan 0
    }

    It 'configuração inexistente vem como Existe = false' {
        $active = (Get-UTActivePowerScheme).Guid
        (Get-UTPowerSettingValue -Esquema $active -Subgrupo $proc -Configuracao '00000000-1111-2222-3333-444444444444').Existe | Should -BeFalse
    }
}
