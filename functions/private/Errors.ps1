function Get-UTFriendlyError {
    <#
    .SYNOPSIS
        Turns an exception into a short PT-BR sentence for the interface. The technical
        detail (exception type and message) goes to the log through -Detalhe.
    .EXAMPLE
        Get-UTFriendlyError -ErrorRecord $_ -Alvo 'o serviço DiagTrack'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][object]$ErrorRecord,
        [string]$Alvo = 'o item'
    )

    $exception = $ErrorRecord
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $exception = $ErrorRecord.Exception }
    while ($exception -is [System.Management.Automation.MethodInvocationException] -and $null -ne $exception.InnerException) {
        $exception = $exception.InnerException
    }

    if ($exception -is [System.UnauthorizedAccessException] -or $exception -is [System.Security.SecurityException]) {
        return "Não foi possível alterar $Alvo porque ele é protegido pelo sistema."
    }
    if ($exception -is [System.IO.IOException] -and $exception.Message -match 'being used|em uso') {
        return "Não foi possível alterar $Alvo porque ele está em uso por outro programa."
    }
    if ($exception -is [System.Management.Automation.ItemNotFoundException]) {
        return "Não foi possível alterar $Alvo porque ele não existe neste computador."
    }
    if ($exception -is [System.TimeoutException] -or $exception.Message -match 'não terminou em') {
        return "A alteração de $Alvo demorou demais e foi cancelada."
    }
    return "Não foi possível alterar $Alvo. Veja o log para os detalhes."
}

function Get-UTServiceErrorMessage {
    <#
    .SYNOPSIS
        Maps sc.exe exit codes (Win32 errors) to PT-BR messages.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Name
    )

    switch ($ExitCode) {
        5    { return "Não foi possível alterar o serviço $Name porque ele é protegido pelo sistema." }
        1060 { return "O serviço $Name não existe neste computador." }
        1072 { return "O serviço $Name está marcado para remoção; reinicie o PC e tente de novo." }
        1058 { return "O serviço $Name está desativado e não pode ser iniciado." }
        1051 { return "O serviço $Name não pode parar porque outros serviços dependem dele." }
        default { return "Não foi possível alterar o serviço $Name (código $ExitCode)." }
    }
}
