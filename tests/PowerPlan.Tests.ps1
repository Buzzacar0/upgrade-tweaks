BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $proc = '54533251-82be-4824-96c1-47b60b740d00'
    $procMin = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    $idle = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
    $storage = '0012ee47-9041-4b5d-9b77-535fba8b1442'

    function New-FakeScheme([string]$Name) {
        # Every setting of the optional adjustments, starting at a "Balanced-like" value.
        $settings = @{}
        foreach ($a in (Get-Content (Join-Path $UTTestRepoRoot 'config\powerplan.json') -Raw -Encoding UTF8 | ConvertFrom-Json).ajustes) {
            foreach ($i in $a.itens) { $settings["$($i.subgrupo)|$($i.configuracao)"] = @{ ac = 5; dc = 3 } }
        }
        $settings["$proc|$idle"] = @{ ac = 0; dc = 0 }
        return @{ nome = $Name; settings = $settings }
    }

    function Reset-FakePowerCfg {
        # Maximum Performance starts hidden (not listed), as on most Windows 11 PCs; it can still
        # be duplicated because Windows keeps it as a template.
        $script:pc = @{
            schemes   = [ordered]@{ $balanced = (New-FakeScheme 'Equilibrado'); $high = (New-FakeScheme 'Alto desempenho') }
            templates = @{ $ultimate = 'Desempenho Máximo' }
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
                $source = $a[1]
                if ($script:pc.refuse -contains $source) { return (& $fail 'Não é possível executar a operação.') }
                $name = $null
                if ($script:pc.schemes.Contains($source)) { $name = $script:pc.schemes[$source].nome }
                elseif ($script:pc.templates.ContainsKey($source)) { $name = $script:pc.templates[$source] }
                else { return (& $fail 'Não é possível executar a operação.') }
                $g = '00000000-0000-0000-0000-{0:D12}' -f $script:pc.nextGuid
                $script:pc.nextGuid++
                $script:pc.schemes[$g] = New-FakeScheme $name
                return (& $ok "GUID do Esquema de Energia: $g  ($name)")
            }
            '/changename' { $script:pc.schemes[$a[1]].nome = $a[2]; return (& $ok '') }
            '/setactive' { if (-not $script:pc.schemes.Contains($a[1])) { return (& $fail 'inválido') }; $script:pc.active = $a[1]; return (& $ok '') }
            '/delete' { if ($a[1] -eq $script:pc.active) { return (& $fail 'plano ativo') }; $script:pc.schemes.Remove($a[1]); return (& $ok '') }
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

    function Get-MaxCopy { @($script:pc.schemes.Keys | Where-Object { $script:pc.schemes[$_].nome -eq 'Desempenho Máximo' }) }
    function Get-DuplicateCount { @($script:pc.calls | Where-Object { $_ -like '/duplicatescheme*' }).Count }

    function Initialize-PowerTest([hashtable]$Ctx = @{}) {
        Reset-UTTestEnvironment
        Reset-FakePowerCfg
        Set-Ctx $Ctx
        Mock Invoke-UTNative { Invoke-FakePowerCfg $ArgumentList } -ParameterFilter { $FilePath -eq 'powercfg.exe' }
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{ PastaBackup = 'x'; PontoRestauracao = $null } }
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Desempenho Máximo do Windows' {
    BeforeEach { Initialize-PowerTest }

    It 'já na lista: só ativa, sem duplicar' {
        $script:pc.schemes[$ultimate] = New-FakeScheme 'Desempenho Máximo'
        (Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Aplicado'
        $script:pc.active | Should -Be $ultimate
        Get-DuplicateCount | Should -Be 0
        (Get-UTTweakState -Id 'UT_Power_DesempenhoMaximo').Estado | Should -Be 'Aplicado'
    }

    It 'escondido: libera uma vez com o nome do Windows e ativa a cópia' {
        (Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Aplicado'
        $script:pc.calls | Should -Contain "/duplicatescheme $ultimate"
        $copies = @(Get-MaxCopy)
        $copies.Count | Should -Be 1
        $script:pc.active | Should -Be $copies[0]
        @($script:pc.calls | Where-Object { $_ -like '/changename*' }).Count | Should -Be 0
        (Get-UTTweakState -Id 'UT_Power_DesempenhoMaximo').Estado | Should -Be 'Aplicado'
    }

    It 'clicar de novo não cria outra cópia' {
        Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo' | Out-Null
        $script:pc.active = $balanced   # the user switched by hand
        (Get-UTTweakState -Id 'UT_Power_DesempenhoMaximo').Estado | Should -Be 'NaoAplicado'
        (Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Aplicado'
        Get-DuplicateCount | Should -Be 1
        @(Get-MaxCopy).Count | Should -Be 1
    }

    It 'cópia liberada por fora (mesmo nome) é reaproveitada' {
        $script:pc.schemes['aaaaaaaa-0000-0000-0000-000000000001'] = New-FakeScheme 'Ultimate Performance'
        (Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Aplicado'
        $script:pc.active | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        Get-DuplicateCount | Should -Be 0
    }

    It 'Windows que não libera: usa o Alto Desempenho e conta como aplicado' {
        $script:pc.refuse = @($ultimate)
        (Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Aplicado'
        $script:pc.active | Should -Be $high
        (Get-UTTweakState -Id 'UT_Power_DesempenhoMaximo').Estado | Should -Be 'Aplicado'
    }

    It 'desfazer volta ao plano anterior e apaga a cópia criada' {
        $script:pc.active = $high
        Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo' | Out-Null
        (Undo-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Desfeito'
        $script:pc.active | Should -Be $high
        @(Get-MaxCopy).Count | Should -Be 0
    }

    It 'desfazer não apaga o plano que já existia' {
        $script:pc.schemes[$ultimate] = New-FakeScheme 'Desempenho Máximo'
        Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo' | Out-Null
        Undo-UTTweak -Id 'UT_Power_DesempenhoMaximo' | Out-Null
        $script:pc.active | Should -Be $balanced
        $script:pc.schemes.Contains($ultimate) | Should -BeTrue
    }

    It 'simular diz o que vai fazer sem mexer em nada' {
        $r = Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo' -WhatIf
        $r.Status | Should -Be 'Simulado'
        ($r.Acoes -join ' ') | Should -Match 'Libera o Desempenho Máximo'
        $r.Acoes | Should -Contain 'Hoje está ativo: Equilibrado'
        Get-DuplicateCount | Should -Be 0
        @($script:pc.calls | Where-Object { $_ -like '/setactive*' }).Count | Should -Be 0
    }

    It 'notebook pode usar, e o status avisa da bateria' {
        Set-Ctx @{ EhNotebook = $true }
        (Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo').Status | Should -Be 'Aplicado'
        (Get-UTPowerPlanStatus).Mensagem | Should -Match 'bateria'
    }
}

Describe 'Migração do plano antigo' {
    BeforeEach { Initialize-PowerTest }

    It 'plano antigo ativo: ativa o Desempenho Máximo, apaga o antigo e limpa o diário' {
        $old = '11111111-2222-3333-4444-555555555555'
        $script:pc.schemes[$old] = New-FakeScheme ((Get-UTConfig -Name 'powerplan').migracao.planos[0])
        $script:pc.active = $old
        $oldId = (Get-UTConfig -Name 'powerplan').migracao.tweaks[0]
        Add-UTAppliedRecord -TweakId $oldId
        [void](Save-UTOriginalItem -Chave 'energia|planoUpgrade' -Dados ([ordered]@{ guid = $old; criado = $true }) -TweakId $oldId)
        $r = Invoke-UTPowerPlanMigration -Confirm:$false
        @($r.Removidos).Count | Should -Be 1
        $script:pc.schemes.Contains($old) | Should -BeFalse
        $script:pc.active | Should -Be (@(Get-MaxCopy)[0])
        @(Get-UTAppliedRecord | ForEach-Object tweakId) | Should -Not -Contain $oldId
        @(Get-UTAppliedRecord | ForEach-Object tweakId) | Should -Contain 'UT_Power_DesempenhoMaximo'
        Get-UTOriginalItem -Chave 'generico|energia|planoupgrade' | Should -BeNullOrEmpty
        # Runs once.
        Invoke-UTPowerPlanMigration -Confirm:$false | Should -BeNullOrEmpty
    }

    It 'plano antigo inativo só é apagado; o plano ativo não muda' {
        $old = '11111111-2222-3333-4444-555555555555'
        $script:pc.schemes[$old] = New-FakeScheme ((Get-UTConfig -Name 'powerplan').migracao.planos[1])
        Invoke-UTPowerPlanMigration -Confirm:$false | Out-Null
        $script:pc.schemes.Contains($old) | Should -BeFalse
        $script:pc.active | Should -Be $balanced
        Get-DuplicateCount | Should -Be 0
    }

    It 'Ryzen X3D de dois CCDs volta para o Equilibrado' {
        Set-Ctx @{ X3D = 'duplo' }
        $old = '11111111-2222-3333-4444-555555555555'
        $script:pc.schemes[$old] = New-FakeScheme ((Get-UTConfig -Name 'powerplan').migracao.planos[0])
        $script:pc.active = $old
        (Invoke-UTPowerPlanMigration -Confirm:$false).Ativado | Should -Be 'Equilibrado'
        $script:pc.active | Should -Be $balanced
    }

    It 'sem plano antigo, só marca como feita' {
        (Invoke-UTPowerPlanMigration -Confirm:$false).Removidos.Count | Should -Be 0
        @($script:pc.calls | Where-Object { $_ -match '^/(delete|setactive|duplicatescheme)' }).Count | Should -Be 0
        Invoke-UTPowerPlanMigration -Confirm:$false | Should -BeNullOrEmpty
    }
}

Describe 'Ajustes avulsos sobre o plano ativo' {
    BeforeEach { Initialize-PowerTest }

    It 'ficam fora dos presets e desmarcados' {
        $ids = @(Get-UTTweak | Where-Object { $_.id -like 'UT_Power_Ajuste_*' } | ForEach-Object id)
        $ids.Count | Should -Be 8
        $never = @((Get-UTConfig -Name 'presets').nuncaEmPreset)
        foreach ($id in $ids) { $never | Should -Contain $id }
    }

    It 'aplica no plano ativo (tomada e bateria) e o desfazer volta o valor' {
        (Invoke-UTTweak -Id 'UT_Power_Ajuste_ProcMin').Status | Should -Be 'Aplicado'
        $script:pc.schemes[$balanced].settings["$proc|$procMin"].ac | Should -Be 100
        $script:pc.schemes[$balanced].settings["$proc|$procMin"].dc | Should -Be 100
        (Undo-UTTweak -Id 'UT_Power_Ajuste_ProcMin').Status | Should -Be 'Desfeito'
        $script:pc.schemes[$balanced].settings["$proc|$procMin"].ac | Should -Be 5
        $script:pc.schemes[$balanced].settings["$proc|$procMin"].dc | Should -Be 3
    }

    It 'notebook: só o valor na tomada' {
        Set-Ctx @{ EhNotebook = $true }
        Invoke-UTTweak -Id 'UT_Power_Ajuste_ProcMin' | Out-Null
        $script:pc.schemes[$balanced].settings["$proc|$procMin"].ac | Should -Be 100
        $script:pc.schemes[$balanced].settings["$proc|$procMin"].dc | Should -Be 3
    }

    It 'pula a configuração que o Windows não tem e falha quando não tem nenhuma' {
        foreach ($s in $script:pc.schemes.Values) { $s.settings.Remove("$storage|d639518a-e56d-4345-8af2-b9f32fb26109") }
        (Invoke-UTTweak -Id 'UT_Power_Ajuste_Armazenamento').Status | Should -Be 'Aplicado'
        foreach ($s in $script:pc.schemes.Values) { $s.settings.Remove("$storage|6738e2c4-e8a5-4a42-b16a-e040e769756e") }
        (Invoke-UTTweak -Id 'UT_Power_Ajuste_Disco').Status | Should -Not -Be 'Aplicado'
    }

    It 'estacionamento de núcleos fica bloqueado em X3D de dois CCDs' {
        Set-Ctx @{ X3D = 'duplo' }
        (Invoke-UTTweak -Id 'UT_Power_Ajuste_CoreParking').Status | Should -Be 'Ignorado'
    }

    It 'simular mostra valor atual -> novo no plano ativo' {
        $r = Invoke-UTTweak -Id 'UT_Power_Ajuste_ProcMin' -WhatIf
        $r.Acoes | Should -Contain "Estado mínimo do processador no plano 'Equilibrado': 5 -> 100"
    }
}

Describe 'Ryzen X3D de dois CCDs' {
    BeforeEach {
        Initialize-PowerTest @{ X3D = 'duplo' }
        Mock Get-UTServiceState { [pscustomobject]@{ Nome = $Name; Existe = $true; StartType = 'Automatic'; Status = 'Running' } }
        Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.XboxGamingOverlay' } }
    }

    It 'NÃO aplica o Desempenho Máximo (nem com tudo selecionado)' {
        $r = Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo'
        $r.Status | Should -Be 'Ignorado'
        $r.Mensagem | Should -Match 'dois CCDs'
        Get-DuplicateCount | Should -Be 0
    }

    It 'a função do plano também recusa se for chamada direto' {
        { Invoke-UTMaxPerformanceCore -TweakId 'x' -Contexto $UTSync.Contexto } | Should -Throw '*dois CCDs*'
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
        $s.Mensagem | Should -Match 'NÃO deve usar o Desempenho Máximo'
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
    BeforeEach { Initialize-PowerTest }

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
    BeforeEach { Initialize-PowerTest }

    It 'exporta o plano ativo e importa ativando' {
        $p = Join-Path $TestDrive 'meu.pow'
        Export-UTPowerPlan -Path $p | Should -Be $p
        $script:pc.calls | Should -Contain "/export $p $balanced"
        $g = Import-UTPowerPlan -Path $p -Ativar
        $script:pc.active | Should -Be $g
    }

    It '"Voltar ao plano anterior" desfaz o Desempenho Máximo' {
        $script:pc.active = $high
        Invoke-UTTweak -Id 'UT_Power_DesempenhoMaximo' | Out-Null
        (Restore-UTPreviousPowerPlan).Status | Should -Be 'Desfeito'
        $script:pc.active | Should -Be $high
    }

    It 'o seletor lista todos os planos com o ativo marcado e ativa o escolhido' {
        $s = Get-UTPowerPlanStatus
        @($s.Planos).Count | Should -Be 2
        @($s.Planos | Where-Object Ativo).Guid | Should -Be $balanced
        $s.MaximoAtivo | Should -BeFalse
        Set-UTActivePowerScheme -Guid $high -Confirm:$false
        $script:pc.active | Should -Be $high
        { Set-UTActivePowerScheme -Guid '99999999-9999-9999-9999-999999999999' -Confirm:$false } | Should -Throw '*não existe*'
    }

    It 'status padrão' {
        (Get-UTPowerPlanStatus).Modo | Should -Be 'padrao'
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
