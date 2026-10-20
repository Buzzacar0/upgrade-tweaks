# System restore point before the first change of the session. Uses CIM (root/default
# SystemRestore) instead of Checkpoint-Computer, which does not exist in PowerShell 7.

function Get-UTSystemDriveVolumeId {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $drive = $env:SystemDrive
    $volume = Get-CimInstance -ClassName Win32_Volume -Filter ("DriveLetter='{0}'" -f $drive) -ErrorAction SilentlyContinue
    if ($null -eq $volume) { return $null }
    $m = [regex]::Match([string]$volume.DeviceID, 'Volume\{[0-9a-fA-F-]+\}')
    if ($m.Success) { return $m.Value.ToLowerInvariant() }
    return $null
}

function Test-UTSystemRestoreEnabled {
    <#
    .SYNOPSIS
        True when System Protection is on for the system drive. Windows lists the protected
        volumes in SPP\Clients; the system volume GUID must be among them.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $clients = Get-UTRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -Name '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}'
    if (-not $clients.ValorExiste) { return $false }
    $entries = (@($clients.Valor) -join ' ').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($entries)) { return $false }
    $volumeId = Get-UTSystemDriveVolumeId
    if (-not $volumeId) { return $true }  # cannot tell which volume; something is protected
    return $entries.Contains($volumeId)
}

function Enable-UTSystemRestore {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $drive = "$env:SystemDrive\"
    if (-not $PSCmdlet.ShouldProcess($drive, 'Ligar a Proteção do Sistema')) { return }
    $r = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'Enable' -Arguments @{ Drive = $drive } -ErrorAction Stop
    if ($r.ReturnValue -ne 0) { throw "Não foi possível ligar a Proteção do Sistema (código $($r.ReturnValue))." }
}

function New-UTRestorePoint {
    <#
    .SYNOPSIS
        Creates a restore point once per session.
    .DESCRIPTION
        - Turns System Protection on for the system drive when it is off (and says so).
        - Windows refuses a new point if one was created in the last 24 h; the program sets
          SystemRestorePointCreationFrequency=0 just for this call and puts the original back.
        Returns Criado (bool), Mensagem and ProtecaoLigadaAgora.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Descricao = 'Upgrade Tweaks - antes das alterações',
        [switch]$Force
    )

    $session = Get-UTSessionState
    if ($session['PontoRestauracao'] -and -not $Force) { return $session['PontoRestauracao'] }

    $result = [pscustomobject]@{ Criado = $false; Mensagem = ''; ProtecaoLigadaAgora = $false }
    if (-not $PSCmdlet.ShouldProcess($env:SystemDrive, "Criar ponto de restauração '$Descricao'")) {
        $result.Mensagem = 'Simulação: um ponto de restauração seria criado.'
        return $result
    }

    $freqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqName = 'SystemRestorePointCreationFrequency'
    $freqOriginal = $null
    try {
        if (-not (Test-UTSystemRestoreEnabled)) {
            Write-UTLog -Level Aviso -Message "A Proteção do Sistema estava desligada no $env:SystemDrive. Ela será ligada para criar o ponto de restauração."
            Enable-UTSystemRestore
            $result.ProtecaoLigadaAgora = $true
        }

        $freqOriginal = Get-UTRegistryValue -Path $freqKey -Name $freqName
        Set-UTRegistryValue -Path $freqKey -Name $freqName -Type DWord -Value 0

        # RestorePointType 12 = MODIFY_SETTINGS, EventType 100 = BEGIN_SYSTEM_CHANGE
        $r = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'CreateRestorePoint' -Arguments @{
            Description      = $Descricao
            RestorePointType = [uint32]12
            EventType        = [uint32]100
        } -ErrorAction Stop
        if ($r.ReturnValue -ne 0) { throw "CreateRestorePoint devolveu $($r.ReturnValue)" }

        $result.Criado = $true
        $result.Mensagem = 'Ponto de restauração criado.'
        Write-UTLog -Level Sucesso -Message "Ponto de restauração criado: $Descricao"
    } catch {
        $result.Mensagem = 'Não foi possível criar o ponto de restauração. Os backups do Upgrade Tweaks continuam ativos, mas recomendamos criar um manualmente.'
        Write-UTLog -Level Aviso -Message $result.Mensagem -Detalhe $_.Exception.Message
    } finally {
        if ($null -ne $freqOriginal) {
            try {
                if ($freqOriginal.ValorExiste) {
                    Set-UTRegistryValue -Path $freqKey -Name $freqName -Type $freqOriginal.Tipo -Value $freqOriginal.Valor
                } else {
                    [void](Remove-UTRegistryValue -Path $freqKey -Name $freqName)
                }
            } catch {
                Write-UTLog -Level Aviso -Message 'Não foi possível voltar a frequência de pontos de restauração ao valor original.' -Detalhe $_.Exception.Message
            }
        }
    }

    $session['PontoRestauracao'] = $result
    return $result
}

function Invoke-UTPreApplySafety {
    <#
    .SYNOPSIS
        Safety net before the first change of the session: folders, backup folder and restore
        point. Runs once; later calls return the same result.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$SemPontoRestauracao)

    $session = Get-UTSessionState
    if ($session['Seguranca']) { return $session['Seguranca'] }

    [void](Initialize-UTFolder)
    $folder = Get-UTSessionBackupFolder
    $point = $null
    if (-not $SemPontoRestauracao) { $point = New-UTRestorePoint }

    $result = [pscustomobject]@{
        PastaBackup      = $folder
        PontoRestauracao = $point
    }
    if (-not $WhatIfPreference) { $session['Seguranca'] = $result }
    return $result
}
