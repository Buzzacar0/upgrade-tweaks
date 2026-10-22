BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function New-RawSensor {
        param($Hardware, $HardwareTipo, $Nome, $Tipo, $Valor, $Min = $Valor, $Max = $Valor, $Id)
        if (-not $Id) { $Id = "/$HardwareTipo/$Nome" }
        [pscustomobject]@{ Hardware = $Hardware; HardwareTipo = $HardwareTipo; Pai = $null; Id = $Id; Nome = $Nome; Tipo = $Tipo; Valor = $Valor; Min = $Min; Max = $Max }
    }
    # Sensors as a Ryzen 9800X3D + RTX 5070 + iGPU read them (names of LibreHardwareMonitor).
    function Get-FakeRows {
        $raw = @(
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'CPU Total' 'Load' 12.5 -Id '/amdcpu/0/load/0')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'CPU Core Max' 'Load' 40 -Id '/amdcpu/0/load/1')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'CPU Core #1' 'Load' 20 -Max 100 -Id '/amdcpu/0/load/2')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'CPU Core #2' 'Load' 10 -Max 40 -Id '/amdcpu/0/load/3')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Package' 'Power' 36.2 -Id '/amdcpu/0/power/0')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core #1' 'Clock' 5000 -Min 4600 -Max 5225 -Id '/amdcpu/0/clock/3')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core #1 (Effective)' 'Clock' 1500 -Id '/amdcpu/0/clock/4')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core #2' 'Clock' 4700 -Min 4500 -Max 5100 -Id '/amdcpu/0/clock/5')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core #2 (Effective)' 'Clock' 10 -Id '/amdcpu/0/clock/6')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core (Tctl/Tdie)' 'Temperature' 46.25 -Id '/amdcpu/0/temperature/2')
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'CCD1 (Tdie)' 'Temperature' 44 -Id '/amdcpu/0/temperature/3')
            (New-RawSensor 'Total Memory' 'Memory' 'Memory' 'Load' 43.6 -Id '/ram/load/0')
            (New-RawSensor 'AMD Radeon(TM) Graphics' 'GpuAmd' 'GPU Core' 'Load' 0 -Id '/gpu-amd/0/load/0')
            (New-RawSensor 'NVIDIA GeForce RTX 5070' 'GpuNvidia' 'GPU Core' 'Temperature' 49.85 -Id '/gpu-nvidia/0/temperature/0')
            (New-RawSensor 'NVIDIA GeForce RTX 5070' 'GpuNvidia' 'GPU Core' 'Load' 3 -Id '/gpu-nvidia/0/load/0')
            (New-RawSensor 'NVIDIA GeForce RTX 5070' 'GpuNvidia' 'GPU Video Engine' 'Load' 0 -Id '/gpu-nvidia/0/load/2')
        )
        return @(ConvertTo-UTSensorRow -Itens $raw -Placa 'qualquer')
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Monitor: configuração (monitor.json)' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'sem arquivo, usa o padrão; salva e lê de volta em %AppData% (pasta do usuário)' {
        $c = Get-UTMonitorConfig
        $c.Layout | Should -Be 'Essencial'
        $c.IntervaloMs | Should -Be 1000
        $c.Unidade | Should -Be 'C'
        $c.Layout = 'Gamer'; $c.Visao = 'Tabela'; $c.IntervaloMs = 500; $c.Unidade = 'F'; $c.Casas = 0
        $c.Favoritos = @('/a', '/b'); $c.Nomes['/a'] = 'CPU'; $c.Alertas['/a'] = [ordered]@{ Acima = 88; Abaixo = $null }
        [void](Save-UTMonitorConfig -Config $c -Confirm:$false)
        Get-UTMonitorConfigPath | Should -BeLike "$(Get-UTPath -Name Usuario)*monitor.json"
        Test-Path (Get-UTMonitorConfigPath) | Should -BeTrue
        $r = Get-UTMonitorConfig
        $r.Layout | Should -Be 'Gamer'
        $r.Visao | Should -Be 'Tabela'
        $r.IntervaloMs | Should -Be 500
        $r.Unidade | Should -Be 'F'
        $r.Casas | Should -Be 0
        $r.Favoritos | Should -Be @('/a', '/b')
        $r.Nomes['/a'] | Should -Be 'CPU'
        $r.Alertas['/a'].Acima | Should -Be 88
        $r.Alertas['/a'].Abaixo | Should -BeNullOrEmpty
    }

    It 'valores fora da faixa voltam para o mais perto válido; chaves desconhecidas somem' {
        $c = ConvertTo-UTMonitorConfig -Config @{ IntervaloMs = 50; Unidade = 'K'; Casas = 7; Layout = 'Outro'; Visao = 'x'; Lixo = 1; Favoritos = @('/a', '/a', 3, ''); Nomes = @{ '/a' = ('x' * 60); '/b' = '  ' } }
        $c.IntervaloMs | Should -Be 250
        $c.Unidade | Should -Be 'C'
        $c.Casas | Should -Be 2
        $c.Layout | Should -Be 'Essencial'
        $c.Visao | Should -Be 'Cartoes'
        $c.Contains('Lixo') | Should -BeFalse
        $c.Favoritos | Should -Be @('/a')
        $c.Nomes['/a'].Length | Should -Be 40
        $c.Nomes.Contains('/b') | Should -BeFalse
        (ConvertTo-UTMonitorConfig -Config @{ IntervaloMs = 99999 }).IntervaloMs | Should -Be 2000
        (ConvertTo-UTMonitorConfig -Config @{ Alertas = @{ '/a' = @{ Acima = '90,5' }; '/b' = @{ Acima = 'muito' } } }).Alertas.Keys | Should -Be @('/a')
    }

    It 'arquivo danificado: volta ao padrão e guarda uma cópia .bak' {
        $p = Get-UTMonitorConfigPath
        New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
        Set-Content -LiteralPath $p -Value '{ isto não é json' -Encoding UTF8
        (Get-UTMonitorConfig).Layout | Should -Be 'Essencial'
        Test-Path "$p.bak" | Should -BeTrue
    }

    It 'exporta e importa o layout; arquivo errado é recusado sem mexer na configuração' {
        $c = Get-UTMonitorDefault
        $c.Layout = 'Personalizado'; $c.Personalizado = @('/x', '/y'); $c.Unidade = 'F'
        $file = Join-Path $TestDrive 'layout.json'
        [void](Export-UTMonitorLayout -Path $file -Config $c -Confirm:$false)
        Reset-UTTestEnvironment
        $imp = Import-UTMonitorLayout -Path $file -Confirm:$false
        $imp.Personalizado | Should -Be @('/x', '/y')
        (Get-UTMonitorConfig).Unidade | Should -Be 'F'
        $bad = Join-Path $TestDrive 'outro.json'
        Set-Content -LiteralPath $bad -Value '{"tweaks": []}' -Encoding UTF8
        { Import-UTMonitorLayout -Path $bad -Confirm:$false } | Should -Throw '*não é um layout do Monitor*'
        (Get-UTMonitorConfig).Personalizado | Should -Be @('/x', '/y')
    }
}

Describe 'Monitor: layouts, resumo por núcleo e sensores zerados' {
    BeforeEach { Reset-UTTestEnvironment; $rows = Get-FakeRows }

    It 'Essencial: temperatura e uso do processador, GPU, memória; iGPU parada fica de fora' {
        $c = Get-UTMonitorDefault
        $ids = @(Select-UTMonitorRow -Linhas $rows -Config $c | ForEach-Object Id)
        $ids | Should -Be @('/amdcpu/0/temperature/2', '/amdcpu/0/load/0', '/amdcpu/0/power/0', '/gpu-nvidia/0/temperature/0', '/gpu-nvidia/0/load/0', '/ram/load/0')
        $c.OcultarZerados = $false
        @(Select-UTMonitorRow -Linhas $rows -Config $c | ForEach-Object Id) | Should -Contain '/gpu-amd/0/load/0'
    }

    It 'Completo: tudo, com os núcleos resumidos em uma linha por tipo' {
        $c = Get-UTMonitorDefault
        $c.Layout = 'Completo'
        $sel = @(Select-UTMonitorRow -Linhas $rows -Config $c)
        $ids = @($sel | ForEach-Object Id)
        $ids | Should -Contain '/amdcpu/0/nucleos/clock'
        $ids | Should -Contain '/amdcpu/0/nucleos/clock-effective'
        $ids | Should -Contain '/amdcpu/0/nucleos/load'
        $ids | Should -Not -Contain '/amdcpu/0/clock/3'
        $ids | Should -Not -Contain '/gpu-nvidia/0/load/2'
        $clock = ($sel | Where-Object Id -eq '/amdcpu/0/nucleos/clock').Linha
        $clock.Valor | Should -Be 4850
        $clock.MinValor | Should -Be 4500
        $clock.MaxValor | Should -Be 5225
        $clock.Faixa | Should -Be @(4700, 5000)
        $clock.Sensor | Should -Be 'Clock dos núcleos (2)'
        $c.ResumoNucleos = $false
        @(Select-UTMonitorRow -Linhas $rows -Config $c | ForEach-Object Id) | Should -Contain '/amdcpu/0/clock/3'
    }

    It 'favoritos no topo em qualquer layout, nome próprio, Personalizado na ordem escolhida' {
        $c = Get-UTMonitorDefault
        $c.Favoritos = @('/amdcpu/0/temperature/3')
        $c.Nomes['/amdcpu/0/load/0'] = 'CPU'
        $sel = @(Select-UTMonitorRow -Linhas $rows -Config $c)
        $sel[0].Id | Should -Be '/amdcpu/0/temperature/3'
        $sel[0].Favorito | Should -BeTrue
        ($sel | Where-Object Id -eq '/amdcpu/0/load/0').NomeExibicao | Should -Be 'CPU'
        $c.Layout = 'Personalizado'
        $c.Personalizado = @('/ram/load/0', '/gpu-amd/0/load/0', '/nao/existe', '/amdcpu/0/load/0')
        $c.Favoritos = @()
        @(Select-UTMonitorRow -Linhas $rows -Config $c | ForEach-Object Id) | Should -Be @('/ram/load/0', '/gpu-amd/0/load/0', '/amdcpu/0/load/0')
    }

    It 'ocultar ou arrastar num layout pronto vira Personalizado com o que estava na tela' {
        $c = Get-UTMonitorDefault
        $h = Set-UTMonitorCustomList -Linhas $rows -Config $c -Ocultar '/amdcpu/0/power/0'
        $h.Layout | Should -Be 'Personalizado'
        $h.Personalizado | Should -Be @('/amdcpu/0/temperature/2', '/amdcpu/0/load/0', '/gpu-nvidia/0/temperature/0', '/gpu-nvidia/0/load/0', '/ram/load/0')
        $m = Set-UTMonitorCustomList -Linhas $rows -Config $h -Mover '/ram/load/0' -Antes '/amdcpu/0/temperature/2'
        $m.Personalizado[0] | Should -Be '/ram/load/0'
        $m.Personalizado.Count | Should -Be 5
        $end = Set-UTMonitorCustomList -Linhas $rows -Config $m -Mover '/ram/load/0'
        $end.Personalizado[-1] | Should -Be '/ram/load/0'
        $add = Set-UTMonitorCustomList -Linhas $rows -Config $end -Mostrar @('/amdcpu/0/power/0', '/ram/load/0')
        $add.Personalizado.Count | Should -Be 6
        $c.Layout | Should -Be 'Essencial'
    }
}

Describe 'Monitor: unidades, histórico, alertas e CSV' {
    BeforeEach { Reset-UTTestEnvironment; $rows = Get-FakeRows }

    It '°F e casas decimais' {
        Format-UTSensorValue -Valor 50 -Tipo Temperature -Unidade F | Should -Be '122,0 °F'
        Format-UTSensorValue -Valor 47.38 -Tipo Temperature -Casas 0 | Should -Be '47 °C'
        Format-UTSensorValue -Valor 47.38 -Tipo Temperature -Casas 2 | Should -Be '47,38 °C'
        Format-UTSensorValue -Valor 12.345 -Tipo Load -Casas 0 | Should -Be '12 %'
        Format-UTSensorValue -Valor 1.2345 -Tipo Voltage -Casas 0 | Should -Be '1,235 V'
        ConvertTo-UTMonitorUnit -Valor 100 -Tipo Temperature -Unidade F | Should -Be 212
        ConvertTo-UTMonitorUnit -Valor 100 -Tipo Load -Unidade F | Should -Be 100
    }

    It 'histórico guarda os últimos 60 valores; a média conta desde o início' {
        $h = @{}
        for ($i = 1; $i -le 100; $i++) { Add-UTMonitorSample -Historico $h -Linhas @([pscustomobject]@{ Id = 'x'; Valor = $i }) }
        $h['x'].Valores.Count | Should -Be 60
        $h['x'].Valores.Peek() | Should -Be 41
        Get-UTMonitorAverage -Historico $h -Id 'x' | Should -Be 50.5
        Get-UTMonitorAverage -Historico $h -Id 'nada' | Should -BeNullOrEmpty
    }

    It 'alerta dispara ao cruzar, não repete parado no limite e só rearma depois da margem' {
        $lim = @{ 't' = @{ Acima = 90; Abaixo = $null } }
        $st = @{}
        $t0 = [datetime]'2026-10-22 20:00:00'
        $row = { param($v) [pscustomobject]@{ Id = 't'; Valor = $v; Sensor = 'CPU'; Hardware = 'Ryzen'; TipoOriginal = 'Temperature' } }
        @(Update-UTMonitorAlert -Linhas @(& $row 85) -Limites $lim -Estado $st -Agora $t0).Count | Should -Be 0
        $e = @(Update-UTMonitorAlert -Linhas @(& $row 91) -Limites $lim -Estado $st -Agora $t0.AddSeconds(1))
        $e.Count | Should -Be 1
        $e[0].Lado | Should -Be 'acima'
        @(Update-UTMonitorAlert -Linhas @(& $row 92) -Limites $lim -Estado $st -Agora $t0.AddSeconds(2)).Count | Should -Be 0
        @(Update-UTMonitorAlert -Linhas @(& $row 89) -Limites $lim -Estado $st -Agora $t0.AddSeconds(3)).Count | Should -Be 0
        @(Update-UTMonitorAlert -Linhas @(& $row 91) -Limites $lim -Estado $st -Agora $t0.AddSeconds(4)).Count | Should -Be 0
        # Back below 87 (90 - margin) arms it again, but the same sensor warns once a minute.
        [void](Update-UTMonitorAlert -Linhas @(& $row 80) -Limites $lim -Estado $st -Agora $t0.AddSeconds(5))
        @(Update-UTMonitorAlert -Linhas @(& $row 95) -Limites $lim -Estado $st -Agora $t0.AddSeconds(6)).Count | Should -Be 0
        [void](Update-UTMonitorAlert -Linhas @(& $row 80) -Limites $lim -Estado $st -Agora $t0.AddSeconds(70))
        @(Update-UTMonitorAlert -Linhas @(& $row 95) -Limites $lim -Estado $st -Agora $t0.AddSeconds(71)).Count | Should -Be 1
        $low = @{ 'f' = @{ Acima = $null; Abaixo = 300 } }
        $e2 = @(Update-UTMonitorAlert -Linhas @([pscustomobject]@{ Id = 'f'; Valor = 0 }) -Limites $low -Estado @{} -Agora $t0)
        $e2[0].Lado | Should -Be 'abaixo'
    }

    It 'alertas padrão por regra e os do usuário por sensor; texto na unidade escolhida' {
        $c = Get-UTMonitorDefault
        $c.Alertas['/ram/load/0'] = [ordered]@{ Acima = 95; Abaixo = $null }
        $lim = Get-UTMonitorAlertLimit -Linhas $rows -Config $c
        $lim['/amdcpu/0/temperature/2'].Acima | Should -Be 90
        $lim['/gpu-nvidia/0/temperature/0'].Acima | Should -Be 85
        $lim['/ram/load/0'].Acima | Should -Be 95
        $c.AlertasPadrao = $false
        (Get-UTMonitorAlertLimit -Linhas $rows -Config $c).Keys | Should -Be @('/ram/load/0')
        $cpu = $rows | Where-Object Id -eq '/amdcpu/0/temperature/2'
        $ev = [pscustomobject]@{ Id = $cpu.Id; Linha = $cpu; Lado = 'acima'; Valor = 91.2; Limite = 90 }
        Format-UTMonitorAlertText -Alerta $ev -Unidade F -Casas 0 | Should -Be 'Processador (Tctl/Tdie) (AMD Ryzen 7 9800X3D) chegou a 196 °F (limite 194 °F).'
    }

    It 'relatório CSV com ponto e vírgula, decimais com vírgula, média e unidade' {
        $h = @{}
        Add-UTMonitorSample -Historico $h -Linhas $rows
        $c = Get-UTMonitorDefault
        $c.Nomes['/amdcpu/0/temperature/2'] = 'CPU; principal'
        $file = Join-Path $TestDrive 'r.csv'
        [void](Export-UTMonitorCsv -Path $file -Linhas $rows -Historico $h -Config $c -Confirm:$false)
        $lines = Get-Content -LiteralPath $file -Encoding UTF8
        $lines[0] | Should -Be 'Dispositivo;Grupo;Tipo;Sensor;Atual;Mínimo;Máximo;Média;Unidade'
        ($lines | Where-Object { $_ -like '*CPU; principal*' }) | Should -Be 'AMD Ryzen 7 9800X3D;Processador;Temperaturas;"CPU; principal";46,250;46,250;46,250;46,250;°C'
        [IO.File]::ReadAllBytes($file)[0] | Should -Be 0xEF
    }

    It 'log CSV: uma linha por leitura com os sensores escolhidos' {
        $file = Join-Path $TestDrive 'log.csv'
        $log = New-UTMonitorLog -Path $file -Colunas @([pscustomobject]@{ Id = 'a'; Nome = 'CPU'; Tipo = 'Temperature' }, [pscustomobject]@{ Id = 'b'; Nome = 'Uso'; Tipo = 'Load' }) -Unidade F -Confirm:$false
        Write-UTMonitorLogLine -Log $log -Valores @{ a = 50; b = 12.345 } -Hora ([datetime]'2026-10-22 20:00:01.5')
        Write-UTMonitorLogLine -Log $log -Valores @{ a = 60 } -Hora ([datetime]'2026-10-22 20:00:02')
        Close-UTMonitorLog -Log $log
        $lines = Get-Content -LiteralPath $file -Encoding UTF8
        $lines[0] | Should -Be 'Hora;CPU (°F);Uso (%)'
        $lines[1] | Should -Be '22/10/2026 20:00:01.500;122,00;12,35'
        $lines[2] | Should -Be '22/10/2026 20:00:02.000;140,00;'
        $log.Linhas | Should -Be 2
    }
}

Describe 'Monitor: a aba' {
    BeforeAll { Import-UTUiAssembly }
    BeforeEach {
        Reset-UTTestEnvironment
        $ui = Initialize-UTUiState
        $w = Get-UTUiWindow -Name 'MainWindow'
        $ui.Window = $w.Window
        $ui.C = $w.Controles
        Mock Get-UTSensorSetup { [pscustomobject]@{ Driver = $true; Biblioteca = 'x'; Pronto = $true } }
        Mock Start-UTSensorMonitor { }
        Mock Invoke-UTUiJob { [pscustomobject]@{ Nome = $Nome } }
        Mock Send-UTNotification { $true }
        $UTSync['SensoresPlaca'] = 'qualquer'
        $UTSync['Sensores'] = @{ Hora = Get-Date; Itens = @(
                (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core (Tctl/Tdie)' 'Temperature' 95 -Id '/amdcpu/0/temperature/2')
                (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'CPU Total' 'Load' 12.5 -Id '/amdcpu/0/load/0')
                (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core #1' 'Clock' 5000 -Id '/amdcpu/0/clock/3')
                (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core #2' 'Clock' 4700 -Id '/amdcpu/0/clock/5')
                (New-RawSensor 'Total Memory' 'Memory' 'Memory' 'Load' 43.6 -Id '/ram/load/0')
            ) }
    }
    AfterEach { $m = (Get-UTUi).Monitor; if ($m -and $m.Timer) { $m.Timer.Stop() }; $UTSync['Sensores'] = $null }

    It 'monta os cartões do layout, dispara o alerta padrão e troca para tabela' {
        $page = New-UTUiPageMonitor
        $page | Should -Not -BeNullOrEmpty
        $ui.PaginaAtual = 'Monitor'
        Update-UTUiMonitor -Forcar
        $m = $ui.Monitor
        @($m.Itens | ForEach-Object Id) | Should -Be @('/amdcpu/0/temperature/2', '/amdcpu/0/load/0', '/ram/load/0')
        $m.Visuais['/amdcpu/0/temperature/2'].Valor.Text | Should -Be '95,0 °C'
        $m.Visuais['/amdcpu/0/temperature/2'].Tipo | Should -Be 'cartao'
        Should -Invoke Send-UTNotification -Times 1 -ParameterFilter { $Texto -like '*95 °C*limite 90 °C*' }
        $c = ConvertTo-UTMonitorConfig -Config $m.Config
        $c.Visao = 'Tabela'; $c.Layout = 'Completo'
        Save-UTUiMonitorConfig -Config $c
        (Get-UTMonitorConfig).Visao | Should -Be 'Tabela'
        $m.Visuais['/amdcpu/0/nucleos/clock'].Tipo | Should -Be 'tabela'
        $m.Visuais['/amdcpu/0/nucleos/clock'].Valor.Text | Should -Be '4850 MHz'
    }

    It 'ocultar pelo menu cria o Personalizado e salva' {
        $null = New-UTUiPageMonitor
        $ui.PaginaAtual = 'Monitor'
        Update-UTUiMonitor -Forcar
        Invoke-UTUiMonitorAction -Acao Ocultar -Id '/amdcpu/0/load/0'
        $saved = Get-UTMonitorConfig
        $saved.Layout | Should -Be 'Personalizado'
        $saved.Personalizado | Should -Be @('/amdcpu/0/temperature/2', '/ram/load/0')
        @($ui.Monitor.Itens | ForEach-Object Id) | Should -Be @('/amdcpu/0/temperature/2', '/ram/load/0')
        $ui.Monitor.Controles.Layout.SelectedItem | Should -Be 'Personalizado'
        Invoke-UTUiMonitorAction -Acao Favorito -Id '/ram/load/0'
        $ui.Monitor.Itens[0].Id | Should -Be '/ram/load/0'
    }
}
