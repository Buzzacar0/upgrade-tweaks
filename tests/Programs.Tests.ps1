BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function Set-Ctx([hashtable]$Change = @{}) {
        $c = @{ WindowsGeracao = '11'; Build = 26200; GpuFabricantes = @('nvidia'); CpuFabricante = 'amd'; EhNotebook = $false; Launchers = @('steam'); X3D = $null
            Executaveis = @('H:\HQ\cod.exe', 'H:\HQ\cod25\cod25-cod.exe'); PastasJogo = @('H:\HQ') }
        foreach ($k in $Change.Keys) { $c[$k] = $Change[$k] }
        $UTSync.Contexto = [pscustomobject]$c
    }
    # Real output of winget 1.29 on the test PC.
    $listOutput = "Name                       Id                                   Version  Source`r`n--------------------------------------------------------------------------------`r`nDisplay Driver Uninstaller Wagnardsoft.DisplayDriverUninstaller 18.1.5.7 winget"
    $upgradeOutput = @(
        "   - `r   \ `r"
        'Name                                             Id                                    Version                       Available                     Source'
        '---------------------------------------------------------------------------------------------------------------------------------------------------------'
        'App Installer                                    Microsoft.AppInstaller                1.29.379.0                    1.29.380                      winget'
        'AutoHotkey                                       AutoHotkey.AutoHotkey                 2.0.27                        2.0.30                        winget'
        'HWiNFO                                           REALiX.HWiNFO                         < 8.20                        8.30                          winget'
        '4 upgrades available.'
    ) -join "`r`n"
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Catálogo config\programs.json' {
    BeforeAll { $cfg = Get-UTConfig -Name 'programs' }

    It 'cada programa tem id único, categoria válida, descrição, site https e um canal' {
        $ids = @($cfg.programas | ForEach-Object { $_.id })
        @($ids | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        foreach ($p in $cfg.programas) {
            $cfg.categorias | Should -Contain $p.categoria -Because $p.id
            $p.descricao | Should -Not -BeNullOrEmpty -Because $p.id
            $p.site | Should -Match '^https://' -Because $p.id
            ($p.winget -or $p.github -or $p.somentePagina) | Should -BeTrue -Because $p.id
            if ($p.github) { { [regex]::new($p.github.arquivo) } | Should -Not -Throw }
        }
    }

    It 'tem todos os programas pedidos' {
        $ids = @($cfg.programas | ForEach-Object { $_.id })
        foreach ($id in 'afterburner', 'rtss', 'hwinfo', 'occt', 'cpuz', 'gpuz', 'ryzenmaster', 'profileinspector', 'ddu', 'nvcleanstall', 'msiutility', 'iapt', 'autoruns', 'processlasso', '7zip', 'everything', 'crystaldiskinfo', 'crystaldiskmark', 'shutup10') {
            $ids | Should -Contain $id
        }
    }

    It 'programas sem canal oficial só abrem a página' {
        foreach ($id in 'ryzenmaster', 'msiutility', 'iapt') { (Get-UTProgramCatalog -Id $id).somentePagina | Should -BeTrue }
    }

    It 'esconde ferramenta AMD em PC Intel e ferramentas NVIDIA sem placa NVIDIA' {
        $ids = @(Get-UTProgramCatalog -SoCompativeis -Contexto ([pscustomobject]@{ CpuFabricante = 'intel'; GpuFabricantes = @('amd') }) | ForEach-Object { $_.id })
        $ids | Should -Not -Contain 'ryzenmaster'
        $ids | Should -Not -Contain 'profileinspector'
        $ids | Should -Not -Contain 'nvcleanstall'
        $ids | Should -Contain 'ddu'
    }
}

Describe 'Leitura da saída do winget' {
    It 'lê versão e origem de "winget list"' {
        $r = Get-UTWingetRow -Saida $listOutput -Id 'Wagnardsoft.DisplayDriverUninstaller'
        $r.Versao | Should -Be '18.1.5.7'
        $r.Disponivel | Should -BeNullOrEmpty
        $r.Origem | Should -Be 'winget'
    }

    It 'lê a versão disponível de "winget upgrade", ignorando o spinner' {
        (Get-UTWingetRow -Saida $upgradeOutput -Id 'AutoHotkey.AutoHotkey').Disponivel | Should -Be '2.0.30'
        $h = Get-UTWingetRow -Saida $upgradeOutput -Id 'REALiX.HWiNFO'
        $h.Versao | Should -Be '< 8.20'
        $h.Disponivel | Should -Be '8.30'
        Get-UTWingetRow -Saida $upgradeOutput -Id 'AutoHotkey' | Should -BeNullOrEmpty
        Get-UTWingetRow -Saida $upgradeOutput -Id '7zip.7zip' | Should -BeNullOrEmpty
    }

    It 'atualizações só dos ids pedidos' {
        Mock Invoke-UTWinget { [pscustomobject]@{ CodigoSaida = 0; Saida = $upgradeOutput; Erro = '' } }
        $u = Get-UTWingetUpgrade -Ids @('REALiX.HWiNFO', '7zip.7zip')
        $u.Keys | Should -Be @('REALiX.HWiNFO')
        $u['REALiX.HWiNFO'] | Should -Be '8.30'
    }

    It 'instalados vêm do "winget export" em JSON' {
        Reset-UTTestEnvironment
        Mock Invoke-UTWinget {
            $i = [array]::IndexOf($Argumentos, '-o')
            '{"Sources":[{"Packages":[{"PackageIdentifier":"7zip.7zip","Version":"25.01"}],"SourceDetails":{"Name":"winget"}}]}' | Set-Content -LiteralPath $Argumentos[$i + 1]
            [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' }
        }
        (Get-UTWingetInstalled)['7zip.7zip'] | Should -Be '25.01'
    }

    It 'mensagens dos códigos do winget em PT-BR (com sinal ou sem)' {
        Get-UTWingetMessage -Codigo -1978335135 | Should -Be 'O programa já está instalado.'
        Get-UTWingetMessage -Codigo 0x8A150014L | Should -Match 'não encontrado'
        Get-UTWingetMessage -Codigo -1 | Should -Match '0xFFFFFFFF'
    }
}

Describe 'Localizar o executável' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'acha pelas pastas do catálogo com variáveis e curinga' {
        $env:UT_TEST_PF = Join-Path $TestDrive 'pf'
        $dir = Join-Path $env:UT_TEST_PF 'CrystalDiskMark9'
        New-Item -ItemType Directory -Force $dir | Out-Null
        Set-Content (Join-Path $dir 'DiskMark64.exe') 'x'
        $p = [ordered]@{ id = 'cdm'; executaveis = @('DiskMark64.exe'); pastas = @('%UT_TEST_PF%\CrystalDiskMark*') }
        Find-UTProgramExecutable -Programa $p | Should -Be (Join-Path $dir 'DiskMark64.exe')
        $env:UT_TEST_PF = $null
    }

    It 'acha a versão portátil baixada do GitHub (subpasta do zip)' {
        $dir = Join-Path (Get-UTPath -Name Tools) 'profileinspector\nvidiaProfileInspector'
        New-Item -ItemType Directory -Force $dir | Out-Null
        Set-Content (Join-Path $dir 'nvidiaProfileInspector.exe') 'x'
        $p = [ordered]@{ id = 'profileinspector'; executaveis = @('nvidiaProfileInspector.exe'); pastas = @() }
        Find-UTProgramExecutable -Programa $p | Should -Be (Join-Path $dir 'nvidiaProfileInspector.exe')
    }

    It 'programa ausente retorna nada' {
        Find-UTProgramExecutable -Programa ([ordered]@{ id = 'nada'; executaveis = @('naoexiste-ut.exe'); pastas = @('%ProgramFiles%\NaoExisteUT') }) | Should -BeNullOrEmpty
    }
}

Describe 'Status, instalar, atualizar, desinstalar e abrir' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        Mock Assert-UTAdmin {}
        Mock Get-UTWingetPath { 'C:\fake\winget.exe' }
        Mock Start-Process {}
    }

    It 'status: origem, versão instalada e atualização disponível' {
        Mock Get-UTWingetInstalled { @{ 'REALiX.HWiNFO' = '8.20'; '7zip.7zip' = '25.01' } }
        Mock Get-UTWingetUpgrade { @{ 'REALiX.HWiNFO' = '8.30' } }
        Mock Find-UTProgramExecutable { $null }
        $s = @(Get-UTProgramStatus -VerificarAtualizacao)
        $h = $s | Where-Object Id -eq 'hwinfo'
        $h.Instalado | Should -BeTrue
        $h.Versao | Should -Be '8.20'
        $h.AtualizacaoDisponivel | Should -BeTrue
        $h.Origem | Should -Be 'winget (REALiX.HWiNFO)'
        ($s | Where-Object Id -eq '7zip').AtualizacaoDisponivel | Should -BeFalse
        ($s | Where-Object Id -eq 'everything').Instalado | Should -BeFalse
        ($s | Where-Object Id -eq 'ryzenmaster').PodeInstalar | Should -BeFalse
        Should -Invoke Get-UTWingetUpgrade -Times 1 -ParameterFilter { $Ids -contains 'REALiX.HWiNFO' -and $Ids -notcontains 'voidtools.Everything' }
    }

    It 'instala pelo winget com id exato e silencioso' {
        Mock Invoke-UTWinget { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } }
        (Install-UTProgram -Id '7zip').Status | Should -Be 'Instalado'
        Should -Invoke Invoke-UTWinget -Times 1 -ParameterFilter { ($Argumentos -join ' ') -eq 'install --id 7zip.7zip -e --silent --source winget --accept-package-agreements' }
    }

    It 'já instalado conta como sucesso' {
        Mock Invoke-UTWinget { [pscustomobject]@{ CodigoSaida = -1978335135; Saida = ''; Erro = '' } }
        (Install-UTProgram -Id 'hwinfo').Mensagem | Should -Be 'O programa já está instalado.'
    }

    It 'sem winget: baixa a última Release do GitHub e extrai o zip na pasta de ferramentas' {
        Mock Get-UTWingetPath { $null }
        $src = Join-Path $TestDrive 'src\nvidiaProfileInspector'
        New-Item -ItemType Directory -Force $src | Out-Null
        Set-Content (Join-Path $src 'nvidiaProfileInspector.exe') 'x'
        $zip = Join-Path $TestDrive 'npi.zip'
        Compress-Archive -Path $src -DestinationPath $zip -Force
        Mock Get-UTGitHubLatestRelease { [pscustomobject]@{ Versao = '3.0.2.3'; Pagina = 'https://github.com/x'; Arquivos = @([pscustomobject]@{ Nome = 'nvidiaProfileInspector.zip'; Url = 'https://github.com/x/npi.zip'; TamanhoMB = 1 }) } }
        Mock Save-UTDownload { Copy-Item -LiteralPath $zip -Destination $Destino; $Destino }
        (Install-UTProgram -Id 'profileinspector').Status | Should -Be 'Instalado'
        $exe = Find-UTProgramExecutable -Programa (Get-UTProgramCatalog -Id 'profileinspector')
        $exe | Should -BeLike '*ferramentas\profileinspector\*nvidiaProfileInspector.exe'
        (Get-UTProgramStatus -Id 'profileinspector').Versao | Should -Be '3.0.2.3'
        (Uninstall-UTProgram -Id 'profileinspector' -Confirm:$false).Status | Should -Be 'Removido'
        Test-Path (Join-Path (Get-UTPath -Name Tools) 'profileinspector') | Should -BeFalse
    }

    It 'winget falhou e não há GitHub: erro com a mensagem do winget' {
        Mock Invoke-UTWinget { [pscustomobject]@{ CodigoSaida = -1978334974; Saida = ''; Erro = '' } }
        { Install-UTProgram -Id 'everything' } | Should -Throw '*Outra instalação está em andamento*'
    }

    It 'programa só com página: abre o site em vez de instalar' {
        (Install-UTProgram -Id 'ryzenmaster').Status | Should -Be 'Pagina'
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq 'https://www.amd.com/en/products/software/ryzen-master.html' }
    }

    It 'atualiza e desinstala pelo winget' {
        Mock Get-UTWingetInstalled { @{ 'REALiX.HWiNFO' = '8.20' } }
        Mock Invoke-UTWinget { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } }
        (Update-UTProgram -Id 'hwinfo').Status | Should -Be 'Atualizado'
        Should -Invoke Invoke-UTWinget -ParameterFilter { $Argumentos[0] -eq 'upgrade' -and $Argumentos -contains 'REALiX.HWiNFO' }
        Uninstall-UTProgram -Id 'hwinfo' -Confirm:$false | Out-Null
        Should -Invoke Invoke-UTWinget -ParameterFilter { $Argumentos[0] -eq 'uninstall' -and $Argumentos -contains 'REALiX.HWiNFO' }
    }

    It 'abre o programa como administrador' {
        Mock Find-UTProgramExecutable { 'C:\Program Files\HWiNFO64\HWiNFO64.exe' }
        Start-UTProgram -Id 'hwinfo'
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -like '*HWiNFO64.exe' -and $Verb -eq 'RunAs' }
    }

    It 'abrir programa não instalado avisa para instalar' {
        Mock Find-UTProgramExecutable { $null }
        { Start-UTProgram -Id 'hwinfo' } | Should -Throw '*não está instalado*'
    }
}

Describe 'Perfil .nip para o NVIDIA Profile Inspector' {
    BeforeEach {
        Reset-UTTestEnvironment; Set-Ctx
        Mock Test-UTNvApiAvailable { $true }
        Mock Open-UTNvDrsSession { $o = [pscustomobject]@{}; $o | Add-Member ScriptMethod Dispose {}; $o }
        Mock Get-UTNvidiaTargetProfile { [pscustomobject]@{ Handle = [IntPtr]2; Nome = 'Call of Duty: Black Ops 7'; Existe = $true; Executaveis = @('cod.exe', 'cod25-cod.exe'); Criar = $false } }
        Mock Get-UTGpuOption { [pscustomobject]@{ ComGsync = $false; HzMonitor = 165 } }
    }

    It 'gera o XML com o perfil do jogo, executáveis e valores recomendados' {
        $file = Export-UTNvidiaInspectorFile -Destino (Join-Path $TestDrive 'wz.nip')
        [xml]$x = [IO.File]::ReadAllText($file, [Text.Encoding]::Unicode)
        $x.ArrayOfProfile.Profile.ProfileName | Should -Be 'Call of Duty: Black Ops 7'
        @($x.ArrayOfProfile.Profile.Executeables.string) | Should -Be @('cod.exe', 'cod25-cod.exe')
        $power = @($x.ArrayOfProfile.Profile.Settings.ProfileSetting | Where-Object { $_.SettingID -eq [string][uint32]0x1057EB71 })[0]
        $power.SettingValue | Should -Be '1'
        $vsync = @($x.ArrayOfProfile.Profile.Settings.ProfileSetting | Where-Object { $_.SettingID -eq [string][uint32]0x00A879CF })[0]
        $vsync.SettingValue | Should -Be ([string][uint32]0x08416747)
        @($x.ArrayOfProfile.Profile.Settings.ProfileSetting | Where-Object { $_.ValueType -ne 'Dword' }).Count | Should -Be 0
    }

    It 'importar faz backup completo do driver antes' {
        Mock Assert-UTAdmin {}
        Mock Invoke-UTPreApplySafety { [pscustomobject]@{} }
        Mock Find-UTProgramExecutable { 'C:\npi\nvidiaProfileInspector.exe' }
        Mock Backup-UTNvidiaDrsFile { 'C:\backup\drs.txt' }
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Saida = ''; Erro = '' } }
        Import-UTNvidiaInspectorProfile | Should -Be 'C:\backup\drs.txt'
        Should -Invoke Backup-UTNvidiaDrsFile -Times 1
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { $ArgumentList[1] -eq '-silentImport' -and $ArgumentList[0] -like '*.nip' }
    }
}
