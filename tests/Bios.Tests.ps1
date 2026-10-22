BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    # IFR text as IFRExtractor-RS writes it (tabs = scope), trimmed from a real Gigabyte AM5 BIOS.
    function Get-TestIfr {
        return [string[]]@(
        'Program version: 1.6.1, Extraction mode: UEFI'
        'FormSet Guid: 7B59104A-C00D-4158-87FF-F04D6396A915, Title: "Setup", Help: "Setup"'
        "`tVarStore Guid: EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9, VarStoreId: 0xF101, Size: 0x10, Name: `"Setup`""
        "`tVarStore Guid: E770BB69-BCB4-4D04-9E97-23FF9456FEAC, VarStoreId: 0xF000, Size: 0x1, Name: `"SystemAccess`""
        "`tVarStoreEfi Guid: ACA9F304-21E2-4852-9875-7FF4881D67A5, VarStoreId: 0x13, Attributes: 0x3, Size: 0x6, Name: `"PCI_COMMON`""
        "`tForm FormId: 0x2735, Title: `"Advanced CPU Settings`""
        "`t`tGrayOutIf "
        "`t`t`tEqIdVal QuestionId: 0x1D1, Value: 0x1"
        "`t`t`tOneOf Prompt: `"Global C-state Control`", Help: `"Controls IO based C-state generation.`", QuestionFlags: 0x10, QuestionId: 0x33, VarStoreId: 0xF101, VarOffset: 0x4, Flags: 0x10, Size: 8, Min: 0x0, Max: 0x3, Step: 0x0"
        "`t`t`t`tDefault DefaultId: 0x0 Value: 3"
        "`t`t`t`tOneOfOption Option: `"Disabled`" Value: 0"
        "`t`t`t`tOneOfOption Option: `"Enabled`" Value: 1"
        "`t`t`t`tOneOfOption Option: `"Auto`" Value: 3, MfgDefault"
        "`t`t`tEnd "
        "`t`tEnd "
        "`t`tSuppressIf "
        "`t`t`tEqIdVal QuestionId: 0x33, Value: 0x0"
        "`t`t`t`tNot "
        "`t`t`t`tEqIdVal QuestionId: 0x1D1, Value: 0x1"
        "`t`t`t`tOr "
        "`t`t`tEnd "
        "`t`t`tOneOf Prompt: `"Soft-Off by PWR-BTTN`", Help: `"Configure the power button."
        'Instant Off = turns off at once.", QuestionFlags: 0x10, QuestionId: 0x34, VarStoreId: 0xF101, VarOffset: 0x6, Flags: 0x11, Size: 16, Min: 0x0, Max: 0x1, Step: 0x0'
        "`t`t`t`tOneOfOption Option: `"Instant Off`" Value: 0, Default, MfgDefault"
        "`t`t`t`tOneOfOption Option: `"Delay 4 Sec.`" Value: 1"
        "`t`t`tEnd "
        "`t`tEnd "
        "`t`tNumeric Prompt: `"`", Help: `"`", QuestionFlags: 0x0, QuestionId: 0x1D1, VarStoreId: 0xF000, VarOffset: 0x0, Flags: 0x10, Size: 8, Min: 0x0, Max: 0xFF, Step: 0x0"
        "`t`tEnd "
        "`t`tCheckBox Prompt: `"Above 4G Decoding`", Help: `"Decoding.`", QuestionFlags: 0x10, QuestionId: 0x7006, VarStoreId: 0x13, VarOffset: 0x1, Flags: 0x0, Default: Enabled, MfgDefault: Enabled"
        "`t`tEnd "
        "`tEnd "
        'End '
        )
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Leitura do IFR (mapa da BIOS)' {
    It 'lê variáveis, perguntas, opções, padrões e o caminho no menu' {
        $r = ConvertFrom-UTIfrText -Linhas (Get-TestIfr) -Modulo 'Setup'
        @($r.VarStores).Count | Should -Be 3
        ($r.VarStores | Where-Object Nome -eq 'PCI_COMMON').Atributos | Should -Be 3
        $q = $r.Perguntas | Where-Object Nome -eq 'Global C-state Control'
        $q.Offset | Should -Be 4
        $q.Bits | Should -Be 8
        $q.Padrao | Should -Be 3
        $q.Formulario | Should -Be 'Advanced CPU Settings'
        @($q.Opcoes).Texto | Should -Be @('Disabled', 'Enabled', 'Auto')
        $q.Condicoes[0].Tipo | Should -Be 'GrayOutIf'
    }

    It 'ajuda em várias linhas não quebra a leitura; 16 bits e padrão vindo da opção' {
        $r = ConvertFrom-UTIfrText -Linhas (Get-TestIfr) -Modulo 'Setup'
        $q = $r.Perguntas | Where-Object Nome -eq 'Soft-Off by PWR-BTTN'
        $q.Ajuda | Should -Match 'Instant Off = turns off'
        $q.Bits | Should -Be 16
        $q.Padrao | Should -Be 0
        $q.Condicoes[0].Tipo | Should -Be 'SuppressIf'
        @($q.Condicoes[0].Expr).Count | Should -Be 4
    }

    It 'checkbox vira opções Disabled/Enabled' {
        $r = ConvertFrom-UTIfrText -Linhas (Get-TestIfr) -Modulo 'PciDynamicSetup'
        $q = $r.Perguntas | Where-Object Nome -eq 'Above 4G Decoding'
        @($q.Opcoes).Valor | Should -Be @(0, 1)
        $q.Padrao | Should -Be 1
        @($q.Condicoes).Count | Should -Be 0
    }
}

Describe 'Expressões e bytes da NVRAM' {
    It 'avalia expressões pós-fixas e devolve $null quando falta valor' {
        $expr = @('EqIdVal QuestionId: 0x33, Value: 0x0', 'Not', 'EqIdVal QuestionId: 0x1D1, Value: 0x1', 'Or')
        Test-UTIfrExpression -Expr $expr -Valores @{ 0x33 = [uint64]3; 0x1D1 = [uint64]0 } | Should -BeTrue
        Test-UTIfrExpression -Expr $expr -Valores @{ 0x33 = [uint64]0; 0x1D1 = [uint64]0 } | Should -BeFalse
        Test-UTIfrExpression -Expr $expr -Valores @{ 0x33 = [uint64]0 } | Should -BeNullOrEmpty
        Test-UTIfrExpression -Expr @('EqIdValList QuestionId: 0x72, Values: [4, 5, 6]') -Valores @{ 0x72 = [uint64]5 } | Should -BeTrue
        Test-UTIfrExpression -Expr @('Uint64 Value: 0x1', 'Uint64 Value: 0x0', 'Equal') -Valores @{} | Should -BeFalse
        Test-UTIfrExpression -Expr @('Opcode Desconhecido') -Valores @{} | Should -BeNullOrEmpty
    }

    It 'lê e grava valores little-endian sem mexer no resto' {
        [byte[]]$data = 1, 2, 3, 4, 5, 6
        Get-UTBiosBytesValue -Dados $data -Offset 1 -Bits 16 | Should -Be 0x0302
        $new = Set-UTBiosBytesValue -Dados $data -Offset 1 -Bits 16 -Valor 0xABCD
        $new | Should -Be @(1, 0xCD, 0xAB, 4, 5, 6)
        $data | Should -Be @(1, 2, 3, 4, 5, 6)
        Get-UTBiosBytesValue -Dados $data -Offset 6 -Bits 8 | Should -BeNullOrEmpty
        { Set-UTBiosBytesValue -Dados $data -Offset 5 -Bits 16 -Valor 1 } | Should -Throw
    }

    It 'separa o buffer de variáveis do firmware' {
        $name = [Text.Encoding]::Unicode.GetBytes('Setup') + [byte[]](0, 0)
        $guid = (New-Object Guid 'EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9').ToByteArray()
        [byte[]]$buffer = [BitConverter]::GetBytes([int]0) + [BitConverter]::GetBytes([int]44) + [BitConverter]::GetBytes([int]536) + [BitConverter]::GetBytes([int]7) + $guid + $name
        $v = @(ConvertFrom-UTUefiVariableBuffer -Buffer $buffer)
        $v.Count | Should -Be 1
        $v[0].Nome | Should -Be 'Setup'
        $v[0].Guid | Should -Be 'EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9'
        $v[0].Tamanho | Should -Be 536
        $v[0].Atributos | Should -Be 7
    }

    It 'escolhe os menus AMD da família do processador' {
        Get-UTAmdBiosFamily -Identificador 'AMD64 Family 26 Model 68 Stepping 0' | Should -Be 'RPL'
        Get-UTAmdBiosFamily -Identificador 'AMD64 Family 25 Model 117 Stepping 2' | Should -Be 'PHX'
        Get-UTAmdBiosFamily -Identificador 'AMD64 Family 26 Model 36 Stepping 0' | Should -Be 'STX'
        Get-UTAmdBiosFamily -Identificador 'Intel64 Family 6 Model 183 Stepping 1' | Should -BeNullOrEmpty
        Test-UTBiosModuleActive -Modulo 'CbsSetupDxeRPL' -Familia 'RPL' | Should -BeTrue
        Test-UTBiosModuleActive -Modulo 'GbtCrbCbsPHX' -Familia 'RPL' | Should -BeFalse
        Test-UTBiosModuleActive -Modulo 'Setup' -Familia 'RPL' | Should -BeTrue
        Test-UTBiosModuleActive -Modulo 'CbsSetupDxeSTX' -Familia $null | Should -BeTrue
    }
}

Describe 'Opções da BIOS (NVRAM simulada)' {
    BeforeEach {
        Reset-UTTestEnvironment
        Mock Assert-UTAdmin {}
        $parsed = ConvertFrom-UTIfrText -Linhas (Get-TestIfr) -Modulo 'Setup'
        $stores = @(
            [ordered]@{ Nome = 'Setup'; Guid = 'EC87D643-EBA4-4BB5-A1E5-3F3E36B20DA9'; Tamanho = 16; Atributos = $null }
            [ordered]@{ Nome = 'SystemAccess'; Guid = 'E770BB69-BCB4-4D04-9E97-23FF9456FEAC'; Tamanho = 1; Atributos = $null }
            [ordered]@{ Nome = 'PCI_COMMON'; Guid = 'ACA9F304-21E2-4852-9875-7FF4881D67A5'; Tamanho = 6; Atributos = 3 }
        )
        $byId = @{ 0xF101 = $stores[0]; 0xF000 = $stores[1]; 0x13 = $stores[2] }
        $questions = foreach ($q in $parsed.Perguntas) {
            $s = $byId[$q.VarStoreId]
            [ordered]@{ Chave = ('Setup/0#0:0x{0:X}' -f $q.Qid); Formset = 'Setup/0#0'; Qid = $q.Qid; Modulo = 'Setup'; Menu = 'Setup'; Formulario = $q.Formulario; Nome = $q.Nome; Ajuda = $q.Ajuda
                Tipo = $q.Tipo; Var = $s.Nome; Guid = $s.Guid; Offset = $q.Offset; Bits = $q.Bits; Min = $q.Min; Max = $q.Max; Passo = $q.Passo; Padrao = $q.Padrao
                Opcoes = @($q.Opcoes); Condicoes = @($q.Condicoes | ForEach-Object { [ordered]@{ Tipo = $_.Tipo; Expr = @($_.Expr) } }) }
        }
        $UTSync['BiosMapa'] = @{ Caminho = 'mapa.json'; Mapa = @{ VarStores = $stores; Perguntas = @($questions) } }
        Mock Get-UTBiosMapPath { 'mapa.json' }
        $script:nv = @{ 'Setup' = [byte[]](0, 0, 0, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0); 'SystemAccess' = [byte[]](0) }
        Mock Read-UTUefiVariable { if ($script:nv.ContainsKey($Nome)) { [pscustomobject]@{ Nome = $Nome; Guid = $Guid; Atributos = 7; Dados = [byte[]]$script:nv[$Nome].Clone() } } else { $null } }
        Mock Write-UTUefiVariable { $script:nv[$Nome] = $Dados }
        Mock Backup-UTNvram { 'C:\backup\nvram' }
        Mock Get-UTAmdBiosFamily { 'RPL' }
    }

    It 'mostra valor atual, padrão, o que só existe na BIOS e esconde o que a BIOS esconde' {
        $all = @(Get-UTBiosSetting)
        $c = $all | Where-Object Nome -eq 'Global C-state Control'
        $c.ValorTexto | Should -Be 'Auto'
        $c.Editavel | Should -BeTrue
        $c.Bloqueada | Should -BeFalse
        ($all | Where-Object Nome -eq 'Above 4G Decoding').Estado | Should -Be 'SomenteNaBios'
        # C-state = Auto (3): "Not (3 == 0) Or ..." is true, so the power button question is hidden.
        @($all | Where-Object Nome -eq 'Soft-Off by PWR-BTTN').Count | Should -Be 0
        @(Get-UTBiosSetting -IncluirOcultas | Where-Object Nome -eq 'Soft-Off by PWR-BTTN').Count | Should -Be 1
    }

    It 'destaque traz o título em português e o que o Windows confirma' {
        Mock Get-UTBiosCheck { @{ rebar = $true } }
        Mock Get-UTCpuInfo { [pscustomobject]@{ Fabricante = 'amd' } }
        $d = @(Get-UTBiosSetting -Destaque)
        @($d | ForEach-Object Nome) | Should -Not -Contain 'Soft-Off by PWR-BTTN'
        ($d | Where-Object Nome -eq 'Global C-state Control').Titulo | Should -Be 'Global C-State Control'
        ($d | Where-Object Nome -eq 'Global C-state Control').Recomendado | Should -Be 'Auto'
        $above = $d | Where-Object Nome -eq 'Above 4G Decoding'
        $above.WindowsConfirma | Should -BeTrue
        $above.Divergente | Should -BeFalse
    }

    It 'cópia desligada enquanto o Windows mostra ligado fica marcada como divergente' {
        Mock Get-UTBiosCheck { @{ rebar = $true } }
        Mock Get-UTCpuInfo { [pscustomobject]@{ Fabricante = 'amd' } }
        # Above 4G stored in a readable variable, off, while Windows sees Resizable BAR on.
        $script:nv['PCI_COMMON'] = [byte[]](0, 0, 0, 0, 0, 0)
        $above = @(Get-UTBiosSetting -Destaque) | Where-Object Nome -eq 'Above 4G Decoding'
        $above.ValorTexto | Should -Be 'Disabled'
        $above.Divergente | Should -BeTrue
    }

    It 'grava só o byte da opção, depois de um backup, e recusa valor fora das opções' {
        $r = Set-UTBiosSetting -Chave 'Setup/0#0:0x33' -Valor 0 -Confirm:$false
        $r.Alterado | Should -BeTrue
        $r.Antes | Should -Be 3
        $script:nv['Setup'] | Should -Be @(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        Should -Invoke Backup-UTNvram -Times 1
        { Set-UTBiosSetting -Chave 'Setup/0#0:0x33' -Valor 2 -Confirm:$false } | Should -Throw '*não é uma das opções*'
        { Set-UTBiosSetting -Chave 'Setup/0#0:0x7006' -Valor 1 -Confirm:$false } | Should -Throw '*durante o boot*'
    }

    It 'mesmo valor não grava; mapa de outra versão é recusado' {
        (Set-UTBiosSetting -Chave 'Setup/0#0:0x33' -Valor 3 -Confirm:$false).Alterado | Should -BeFalse
        Should -Invoke Write-UTUefiVariable -Times 0
        $script:nv['Setup'] = [byte[]](0, 0, 0, 0, 3, 0, 1, 0)
        { Set-UTBiosSetting -Chave 'Setup/0#0:0x33' -Valor 1 -Confirm:$false } | Should -Throw '*outra versão*'
    }

    It 'simulação não grava nem faz backup' {
        Set-UTBiosSetting -Chave 'Setup/0#0:0x33' -Valor 1 -WhatIf | Out-Null
        Should -Invoke Write-UTUefiVariable -Times 0
        Should -Invoke Backup-UTNvram -Times 0
    }
}

Describe 'Gravação na NVRAM' {
    BeforeEach { Reset-UTTestEnvironment; Mock Assert-UTAdmin {} }

    It 'recusa tamanho diferente e variáveis do Secure Boot' {
        Mock Read-UTUefiVariable { [pscustomobject]@{ Nome = $Nome; Guid = 'X'; Atributos = 0x27; Dados = [byte[]](1, 2) } }
        { Write-UTUefiVariable -Nome 'db' -Guid 'X' -Dados ([byte[]](1, 2, 3)) -Confirm:$false } | Should -Throw '*Tamanho diferente*'
        { Write-UTUefiVariable -Nome 'db' -Guid 'X' -Dados ([byte[]](1, 3)) -Confirm:$false } | Should -Throw '*Secure Boot*'
    }
}
