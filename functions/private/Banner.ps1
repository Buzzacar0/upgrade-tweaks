function Show-UTBanner {
    <#
    .SYNOPSIS
        Prints the console banner with the version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version
    )

    $banner = @(
        '  _   _ ___  ___ ___    _   ___  ___   _______      _____   _   _  _____'
        ' | | | | _ \/ __| _ \  /_\ |   \| __| |_   _\ \    / / __| /_\ | |/ / __|'
        ' | |_| |  _/ (_ |   / / _ \| |) | _|    | |  \ \/\/ /| _| / _ \| '' <\__ \'
        '  \___/|_|  \___|_|_\/_/ \_\___/|___|   |_|   \_/\_/ |___/_/ \_\_|\_\___/'
    )
    Write-UTConsole -Text '' -Color Gray
    foreach ($line in $banner) { Write-UTConsole -Text $line -Color Magenta }
    Write-UTConsole -Text '' -Color Gray
    Write-UTConsole -Text ("  Upgrade Tweaks v$Version  |  Upgrade Store - Porto Alegre/RS") -Color Cyan
    Write-UTConsole -Text '  Otimização de Windows para Call of Duty: Warzone' -Color DarkCyan
    Write-UTConsole -Text '' -Color Gray
}
