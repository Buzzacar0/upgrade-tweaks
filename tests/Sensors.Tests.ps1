BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    function New-RawSensor {
        param($Hardware, $HardwareTipo, $Nome, $Tipo, $Valor, $Min = $Valor, $Max = $Valor, $Pai = $null)
        [pscustomobject]@{ Hardware = $Hardware; HardwareTipo = $HardwareTipo; Pai = $Pai; Id = "/$HardwareTipo/$Nome"; Nome = $Nome; Tipo = $Tipo; Valor = $Valor; Min = $Min; Max = $Max }
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Sensores' {
    BeforeEach { Reset-UTTestEnvironment }

    It 'formata no padrão brasileiro com unidade' {
        Format-UTSensorValue -Valor 1.2345 -Tipo Voltage | Should -Be '1,235 V'
        Format-UTSensorValue -Valor 47.38 -Tipo Temperature | Should -Be '47,4 °C'
        Format-UTSensorValue -Valor 1679.1 -Tipo Fan | Should -Be '1679 RPM'
        Format-UTSensorValue -Valor (2MB) -Tipo Throughput | Should -Be '2,0 MB/s'
        Format-UTSensorValue -Valor $null -Tipo Power | Should -Be '-'
    }

    It 'usa os rótulos e multiplicadores da placa só no chip certo' {
        $raw = @(
            (New-RawSensor 'ITE IT8696E' 'SuperIO' 'Voltage #3' 'Voltage' 2.016 -Pai 'Gigabyte X870 GAMING WIFI6')
            (New-RawSensor 'ITE IT8696E' 'SuperIO' 'Fan #1' 'Fan' 1650)
            (New-RawSensor 'ITE IT8696E' 'SuperIO' 'Fan #2' 'Fan' 0 -Max 0)
            (New-RawSensor 'AMD Ryzen 7 9800X3D' 'Cpu' 'Core (Tctl/Tdie)' 'Temperature' 50.5)
            (New-RawSensor 'A-DATA ?z?    ?>?> (#1)' 'Memory' 'Thermal Sensor High Limit' 'Temperature' 55)
            (New-RawSensor 'A-DATA ?z?    ?>?> (#1)' 'Memory' 'DIMM #1' 'Temperature' 33)
        )
        $rows = @(ConvertTo-UTSensorRow -Itens $raw -Placa 'X870 GAMING WIFI6')
        $v = $rows | Where-Object Id -eq '/SuperIO/Voltage #3'
        $v.Sensor | Should -Be '+12 V'
        $v.Atual | Should -Be '12,096 V'
        $v.Grupo | Should -Be 'Placa-mãe'
        $v.Hardware | Should -Be 'Gigabyte X870 GAMING WIFI6 · ITE IT8696E'
        ($rows | Where-Object Id -eq '/SuperIO/Fan #1').Sensor | Should -Be 'CPU_FAN'
        @($rows | Where-Object Id -eq '/SuperIO/Fan #2').Count | Should -Be 0
        ($rows | Where-Object Id -eq '/Cpu/Core (Tctl/Tdie)').Sensor | Should -Be 'Ponto mais quente da CPU'
        @($rows | Where-Object Sensor -like '*Limit*').Count | Should -Be 0
        ($rows | Where-Object Id -eq '/Memory/DIMM #1').Hardware | Should -Be 'Pente de memória (#1)'
        # Another board: raw value, generic name.
        $other = @(ConvertTo-UTSensorRow -Itens $raw -Placa 'B650 AORUS ELITE') | Where-Object Id -eq '/SuperIO/Voltage #3'
        $other.Sensor | Should -Be 'Voltage #3'
        $other.Atual | Should -Be '2,016 V'
    }

    It 'timings do SPD em ciclos, com CL par no DDR5' {
        $UTSync['Sensores'] = @{ Hora = Get-Date; Itens = @(
                (New-RawSensor 'DIMM (#1)' 'Memory' 'tAA (CAS Latency Time)' 'Timing' 16.0)
                (New-RawSensor 'DIMM (#1)' 'Memory' 'tRCD (RAS to CAS Delay Time)' 'Timing' 16.0)
                (New-RawSensor 'DIMM (#1)' 'Memory' 'tRP (Row Precharge Delay Time)' 'Timing' 16.0)
                (New-RawSensor 'DIMM (#1)' 'Memory' 'tRAS (Active to Precharge Delay Time)' 'Timing' 32.0)
                (New-RawSensor 'DIMM (#1)' 'Memory' 'tRC (Active to Active/Refresh Delay Time)' 'Timing' 48.0)
            )
        }
        Get-UTSpdTiming -VelocidadeMTs 5600 | Should -Be '46-45-45-90-135 (aprox.)'
        $UTSync['Sensores'] = $null
        Get-UTSpdTiming -VelocidadeMTs 5600 | Should -BeNullOrEmpty
    }

    It 'monitor não inicia sem o driver e a biblioteca' {
        Mock Test-UTPawnIO { $false }
        (Get-UTSensorSetup).Pronto | Should -BeFalse
        { Start-UTSensorMonitor -Confirm:$false } | Should -Throw '*suporte a sensores*'
    }

    It 'codinome do processador pela família e modelo' {
        Get-UTCpuCodename -Fabricante amd -Familia 26 -Modelo 68 | Should -Be 'Granite Ridge (Zen 5)'
        Get-UTCpuCodename -Fabricante intel -Familia 6 -Modelo 183 | Should -Be 'Raptor Lake'
        Get-UTCpuCodename -Fabricante amd -Familia 99 -Modelo 1 | Should -Be ''
    }
}

Describe 'Ferramentas extras do sistema' {
    BeforeEach { Reset-UTTestEnvironment; Mock Assert-UTAdmin {} }

    It 'lê o resultado do winsat' {
        Mock Invoke-UTNative {
            [pscustomobject]@{ CodigoSaida = 0; Erro = ''; Saida = @(
                    '> Disk  Random 16.0 Read                       1158.47 MB/s          8.8'
                    '> Disk  Sequential 64.0 Read                   5243.18 MB/s          9.4'
                    '> Disk  Sequential 64.0 Write                  4096.00 MB/s          9.3'
                    '> Tempo total decorrido: 00:00:15'
                ) -join "`r`n"
            }
        }
        $r = @(Measure-UTDiskSpeed -Unidade C)
        $r.Count | Should -Be 3
        ($r | Where-Object Teste -eq 'Leitura sequencial').MBs | Should -Be 5243.18
        Should -Invoke Invoke-UTNative -Times 1 -ParameterFilter { $FilePath -eq 'winsat.exe' -and $ArgumentList -contains 'c' }
    }

    It 'estado do CompactOS em português e em inglês' {
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Erro = ''; Saida = 'O sistema não está no estado Compacto porque o Windows determinou que não é vantajoso.' } }
        Get-UTCompactOSState | Should -BeFalse
        Mock Invoke-UTNative { [pscustomobject]@{ CodigoSaida = 0; Erro = ''; Saida = 'The system is in the Compact state. It will remain in this state unless an administrator changes it.' } }
        Get-UTCompactOSState | Should -BeTrue
    }

    It 'o script da limpeza da RAM só age abaixo do limite e é autossuficiente' {
        $s = Get-UTMemoryCleanScript -LimiteMB 1024
        $s | Should -Match '\$limit = 1024'
        $s | Should -Match 'NtSetSystemInformation\(80'
        $s | Should -Not -Match 'Get-UT|Write-UT'
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($s, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}
