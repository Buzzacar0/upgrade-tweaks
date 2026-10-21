function Get-UTPath {
    <#
    .SYNOPSIS
        Returns one of the Upgrade Tweaks working folders.
    .DESCRIPTION
        The root is %ProgramData%\UpgradeTweaks. Tests (and anyone who needs it) can point the
        root elsewhere through the UPGRADETWEAKS_HOME environment variable, so nothing touches
        ProgramData during development.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('Root', 'Logs', 'Backups', 'State', 'Temp', 'Tools')]
        [string]$Name = 'Root'
    )

    $root = $env:UPGRADETWEAKS_HOME
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'UpgradeTweaks'
    }

    switch ($Name) {
        'Root'    { return $root }
        'Logs'    { return (Join-Path $root 'logs') }
        'Backups' { return (Join-Path $root 'backups') }
        'State'   { return (Join-Path $root 'state') }
        'Tools'   { return (Join-Path $root 'ferramentas') }
        'Temp'    { return (Join-Path ([IO.Path]::GetTempPath()) 'UpgradeTweaks') }
    }
}

function Initialize-UTFolder {
    <#
    .SYNOPSIS
        Creates the root folder and its logs, backups and state subfolders when missing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param()

    $created = @()
    foreach ($name in 'Root', 'Logs', 'Backups', 'State') {
        $path = Get-UTPath -Name $name
        if (-not (Test-Path -LiteralPath $path)) {
            if ($PSCmdlet.ShouldProcess($path, 'Criar pasta')) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
                $created += $path
            }
        }
    }
    return $created
}
