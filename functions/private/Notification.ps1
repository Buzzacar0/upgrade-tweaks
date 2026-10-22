# Windows notifications (toasts) for the Monitor alerts. Windows PowerShell reaches the WinRT
# notification API directly; the toast shows under "Windows PowerShell", the app that runs the
# program. Nothing to install, and a failure only goes to the log.

function Send-UTNotification {
    <#
    .SYNOPSIS
        Shows a Windows notification. Returns $true when it was shown.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Titulo, [string]$Texto = '')
    if (-not $PSCmdlet.ShouldProcess($Titulo, 'Mostrar notificação do Windows')) { return $false }
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $esc = { param($s) [Security.SecurityElement]::Escape([string]$s) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$(& $esc $Titulo)</text><text>$(& $esc $Texto)</text></binding></visual></toast>")
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        return $true
    } catch {
        Write-UTLog -Level Aviso -Message 'Não foi possível mostrar a notificação do Windows.' -Detalhe $_.Exception.Message
        return $false
    }
}
