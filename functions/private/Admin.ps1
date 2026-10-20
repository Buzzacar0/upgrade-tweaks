function Test-UTAdmin {
    <#
    .SYNOPSIS
        True when the current process runs with an elevated administrator token.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-UTAdmin {
    <#
    .SYNOPSIS
        Throws when the process is not elevated. Called again before every apply/undo,
        not only at startup.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-UTAdmin)) {
        throw 'O Upgrade Tweaks precisa ser executado como administrador. Nenhuma alteração foi feita.'
    }
}

function Test-UTNeeds64BitRelaunch {
    <#
    .SYNOPSIS
        True when a 32-bit PowerShell is running on 64-bit Windows. In that case HKLM\SOFTWARE
        writes would be redirected to WOW6432Node, so the program must restart in 64-bit.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess)
}

function Get-UTPowerShellPath {
    <#
    .SYNOPSIS
        Path of the PowerShell executable used to relaunch: the same host that is running now
        (Windows PowerShell 5.1 or PowerShell 7), always the 64-bit one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (Test-UTNeeds64BitRelaunch) {
        # Sysnative is how a 32-bit process reaches the real System32.
        return (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe')
    }

    $current = $null
    try { $current = (Get-Process -Id $PID).Path } catch { $current = $null }
    if ($current -and (Test-Path -LiteralPath $current)) { return $current }

    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function ConvertTo-UTArgumentString {
    <#
    .SYNOPSIS
        Turns bound script parameters back into a command line for powershell.exe -File.
    .DESCRIPTION
        Switches set to $true become "-Name", switches set to $false are dropped,
        other values become -Name "value" with embedded double quotes escaped.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Collections.IDictionary]$Parameters
    )

    if ($null -eq $Parameters) { return '' }

    $parts = @()
    foreach ($key in ($Parameters.Keys | Sort-Object)) {
        $value = $Parameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter] -or $value -is [bool]) {
            if ([bool]$value) { $parts += "-$key" }
            continue
        }
        if ($null -eq $value) { continue }
        $text = [string]$value
        # Backslashes before a quote must be doubled too, or the quote ends the argument early.
        $text = $text -replace '(\\*)"', '$1$1\"'
        $text = $text -replace '(\\+)$', '$1$1'
        $parts += ('-{0} "{1}"' -f $key, $text)
    }
    return ($parts -join ' ')
}

function Save-UTRemoteScript {
    <#
    .SYNOPSIS
        Downloads the published upgradetweaks.ps1 to a temp file, byte for byte.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )

    $folder = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($Url, 'Baixar o Upgrade Tweaks para reiniciar como administrador')) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $client = New-Object System.Net.WebClient
        try {
            $client.DownloadFile($Url, $Destination)
        } finally {
            $client.Dispose()
        }
    }
    return $Destination
}

function Invoke-UTElevation {
    <#
    .SYNOPSIS
        Relaunches Upgrade Tweaks elevated (UAC) and 64-bit, passing the same parameters.
    .DESCRIPTION
        - Started from a file: relaunches that same file.
        - Started from "irm | iex" (no file): downloads the release to %TEMP% and runs it with -File.
        Headless runs (preset, config, undo, diagnostics) wait for the elevated process and return
        its exit code, so scripts calling Upgrade Tweaks get a real result.
        Returns an object with Iniciado (bool) and CodigoSaida (int or $null).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowNull()][string]$ScriptPath,
        [AllowNull()][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory)][string]$ReleaseUrl,
        [switch]$Wait
    )

    $result = [pscustomobject]@{ Iniciado = $false; CodigoSaida = $null; Mensagem = '' }

    try {
        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            $target = Join-Path (Get-UTPath -Name Temp) 'upgradetweaks.ps1'
            Write-UTConsole -Text 'Baixando o Upgrade Tweaks para reiniciar como administrador...' -Color Cyan
            $ScriptPath = Save-UTRemoteScript -Url $ReleaseUrl -Destination $target
        }

        $exe = Get-UTPowerShellPath
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
        $extra = ConvertTo-UTArgumentString -Parameters $BoundParameters
        if ($extra) { $arguments += ' ' + $extra }

        if (-not $PSCmdlet.ShouldProcess($exe, "Reiniciar como administrador: $arguments")) {
            $result.Mensagem = 'Simulação: o programa seria reiniciado como administrador.'
            return $result
        }

        if ($Wait) {
            $process = Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
            $result.CodigoSaida = $process.ExitCode
        } else {
            Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop | Out-Null
        }
        $result.Iniciado = $true
    } catch {
        $result.Mensagem = 'O Upgrade Tweaks precisa ser executado como administrador. ' +
            'A permissão foi negada no aviso do Windows (UAC) ou não foi possível reiniciar. ' +
            'Abra o PowerShell como administrador e tente de novo.'
        Write-Verbose "Falha na elevação: $($_.Exception.Message)"
    }
    return $result
}
