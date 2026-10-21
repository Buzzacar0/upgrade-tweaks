function Get-UTGeneratedTweak {
    <#
    .SYNOPSIS
        Tweaks built from data files instead of being written one by one in tweaks-*.json:
        one per service in services.json and one per app in apps-debloat.json (phase 6b).
        Returns nothing while those files do not exist.
    #>
    [CmdletBinding()]
    param()
    if (Test-UTConfigFile -Name 'services') { ConvertTo-UTServiceTweak -Config (Get-UTConfig -Name 'services') }
    if (Test-UTConfigFile -Name 'apps-debloat') { ConvertTo-UTAppTweak -Config (Get-UTConfig -Name 'apps-debloat') }
}

function ConvertTo-UTServiceTweak {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    # Filled in phase 6b.
    $null = $Config
}

function ConvertTo-UTAppTweak {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    # Filled in phase 6b.
    $null = $Config
}
