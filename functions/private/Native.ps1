function Invoke-UTNative {
    <#
    .SYNOPSIS
        Runs a console program (sc.exe, reg.exe, powercfg, bcdedit...) and captures its output.
    .DESCRIPTION
        Console tools print in the OEM code page (850 on PT-BR Windows), so the output is decoded
        with it. Every native call goes through here, which also makes them easy to mock in tests.
        Returns an object with CodigoSaida, Saida and Erro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 300
    )

    $oem = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($ArgumentList | ForEach-Object { ConvertTo-UTNativeArgument $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $oem
    $psi.StandardErrorEncoding = $oem

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        # Read both streams asynchronously so a full stderr buffer cannot block the child.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { Write-Verbose 'O processo já tinha terminado.' }
            throw "O comando $FilePath não terminou em $TimeoutSeconds segundos."
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            CodigoSaida = $process.ExitCode
            Saida       = $stdoutTask.Result.TrimEnd()
            Erro        = $stderrTask.Result.TrimEnd()
        }
    } finally {
        $process.Dispose()
    }
}

function ConvertTo-UTNativeArgument {
    <#
    .SYNOPSIS
        Quotes one argument following the Windows command-line rules (CommandLineToArgvW).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Argument)

    if ($Argument -eq '') { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $escaped = $Argument -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}
