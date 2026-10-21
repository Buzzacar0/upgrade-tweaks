function Get-UTInteractiveUser {
    <#
    .SYNOPSIS
        The user logged on to this desktop session: owner of explorer.exe in the same session
        as this process. Returns Sid and Nome, or $null when it cannot be found.
    #>
    [CmdletBinding()]
    param()

    try {
        $session = (Get-Process -Id $PID).SessionId
        $explorers = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
            Where-Object { $_.SessionId -eq $session })
        foreach ($p in $explorers) {
            $sid = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop
            $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop
            if ($sid.ReturnValue -eq 0 -and $sid.Sid) {
                return [pscustomobject]@{ Sid = [string]$sid.Sid; Nome = ('{0}\{1}' -f $owner.Domain, $owner.User) }
            }
        }
    } catch {
        Write-UTLog -Level Debug -Message 'Não foi possível identificar o usuário da área de trabalho.' -Detalhe $_.Exception.Message
    }
    return $null
}

function Initialize-UTTargetUser {
    <#
    .SYNOPSIS
        When the UAC prompt was approved with a different administrator account (standard user
        typing the admin password), HKCU of this process belongs to that admin. Per-user tweaks
        must go to the person using the PC, so HKCU is redirected to HKEY_USERS\<their SID>.
    #>
    [CmdletBinding()]
    param()

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $interactive = Get-UTInteractiveUser
    if ($null -eq $interactive -or $interactive.Sid -eq $currentSid) { return $null }

    if (-not (Test-UTRegistryKey -Path "HKU:\$($interactive.Sid)")) {
        $message = ("O programa está rodando com outra conta de administrador e o perfil de {0} não está carregado. " -f $interactive.Nome) +
            'Os ajustes por usuário vão para a conta de administrador. Para evitar isso, entre como administrador e rode de novo.'
        Write-UTLog -Level Aviso -Message $message
        return $null
    }

    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $sync) {
        $sync['UsuarioAlvoSid'] = $interactive.Sid
        $sync['UsuarioAlvoNome'] = $interactive.Nome
    }
    Write-UTLog -Level Aviso -Message ("O UAC foi aprovado com outra conta de administrador. Os ajustes por usuário serão aplicados na conta {0}, que está usando o PC." -f $interactive.Nome)
    return $interactive
}
