# Heavy debloat used by the "Modo Lite": OneDrive, Edge (never WebView2), Widgets, and the
# Logitech Download Assistant block. Each one has a reinstall/undo path.

#region OneDrive
function Test-UTOneDriveFolderBackup {
    <#
    .SYNOPSIS
        True when Documents, Desktop or Pictures live inside OneDrive ("backup de pastas" /
        Known Folder Move). Uninstalling OneDrive then can leave online-only files unreachable,
        so the removal refuses in that case.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $root = $env:OneDrive
    $folders = @([Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyPictures'))
    foreach ($f in $folders) {
        if (-not $f) { continue }
        if ($root -and $f.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($f -match '\\OneDrive( - [^\\]+)?\\') { return $true }
    }
    return $false
}

function Test-UTOneDriveInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $paths = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe")
    return (@($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) }).Count -gt 0)
}

function Remove-UTOneDrive {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)

    if (Test-UTOneDriveFolderBackup) {
        throw 'Seus Documentos, Área de Trabalho ou Imagens estão dentro do OneDrive (backup de pastas). Remover o OneDrive agora pode deixar arquivos que estão só na nuvem inacessíveis. Abra o OneDrive > Configurações > Sincronização e backup > Gerenciar backup, desligue o backup das pastas e rode de novo.'
    }
    if (-not (Test-UTOneDriveInstalled)) { return }
    if (-not $PSCmdlet.ShouldProcess('OneDrive', 'Desinstalar')) { return }

    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($setup) {
        $r = Invoke-UTNative -FilePath $setup -ArgumentList @('/uninstall') -TimeoutSeconds 600
    } else {
        $r = Invoke-UTNative -FilePath 'winget.exe' -TimeoutSeconds 600 -ArgumentList @('uninstall', '--id', 'Microsoft.OneDrive', '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity')
    }
    if (Test-UTOneDriveInstalled) { throw "O desinstalador do OneDrive não terminou a remoção (código $($r.CodigoSaida))." }
    Write-UTLog -Level Sucesso -TweakId $TweakId -Message 'OneDrive desinstalado. Seus arquivos na nuvem continuam na sua conta e a pasta local não foi apagada.'
}

function Install-UTOneDrive {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('OneDrive', 'Reinstalar')) { return }
    $r = Invoke-UTNative -FilePath 'winget.exe' -TimeoutSeconds 900 -ArgumentList @('install', '--id', 'Microsoft.OneDrive', '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($r.CodigoSaida -ne 0) { throw "Não foi possível reinstalar o OneDrive (winget $($r.CodigoSaida))." }
}
#endregion

#region Edge
function Get-UTEdgeSetupPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $root = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $setup = @(Get-ChildItem -Path "$root\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Sort-Object FullName)
    if ($setup.Count -eq 0) { return $null }
    return $setup[-1].FullName
}

function Test-UTEdgeInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return (Test-Path -LiteralPath "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")
}

function Remove-UTEdge {
    <#
    .SYNOPSIS
        Uninstalls Microsoft Edge (the browser only; the WebView2 runtime, which the Xbox App and
        many launchers need, is a separate product and stays). Outside the EEA Windows hides the
        uninstall, so the legacy-Edge placeholder trick is used to unlock the official uninstaller.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)

    $setup = Get-UTEdgeSetupPath
    if (-not $setup) { return }
    if (-not $PSCmdlet.ShouldProcess('Microsoft Edge', 'Desinstalar (o WebView2 fica)')) { return }

    $legacyDir = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
    $placeholder = Join-Path $legacyDir 'MicrosoftEdge.exe'
    $createdPlaceholder = $false
    if ((Test-Path -LiteralPath $legacyDir) -and -not (Test-Path -LiteralPath $placeholder)) {
        New-Item -Path $placeholder -ItemType File -Force | Out-Null
        $createdPlaceholder = $true
    }
    try {
        Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $r = Invoke-UTNative -FilePath $setup -ArgumentList @('--uninstall', '--system-level', '--force-uninstall') -TimeoutSeconds 600
        Write-UTLog -Level Debug -TweakId $TweakId -Message "Desinstalador do Edge terminou com código $($r.CodigoSaida)."
    } finally {
        if ($createdPlaceholder) { Remove-Item -LiteralPath $placeholder -Force -ErrorAction SilentlyContinue }
    }
    if (Test-UTEdgeInstalled) { throw 'O Windows não permitiu remover o Edge.' }
    # Stops Windows Update from putting it back.
    Set-UTRegistryValueTracked -Path 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' -Name 'DoNotUpdateToEdgeWithChromium' -Type DWord -Value 1 -TweakId $TweakId
}

function Install-UTEdge {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    if (-not $PSCmdlet.ShouldProcess('Microsoft Edge', 'Reinstalar')) { return }
    [void](Restore-UTTweakRegistryItem -TweakId $TweakId)
    $r = Invoke-UTNative -FilePath 'winget.exe' -TimeoutSeconds 900 -ArgumentList @('install', '--id', 'Microsoft.Edge', '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($r.CodigoSaida -ne 0) { throw "Não foi possível reinstalar o Edge (winget $($r.CodigoSaida))." }
}
#endregion

#region Widgets
function Remove-UTWidgetsPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    if (-not $PSCmdlet.ShouldProcess('Widgets (Windows Web Experience Pack)', 'Remover')) { return }
    Get-Process -Name '*Widget*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($name in 'MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime') {
        foreach ($p in @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)) {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
        }
    }
    Write-UTLog -Level Info -TweakId $TweakId -Message 'Widgets removidos.'
}
#endregion

#region Logitech Download Assistant
function Get-UTLogiFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $pf = $env:ProgramW6432
    if (-not $pf) { $pf = $env:ProgramFiles }
    return (Join-Path $pf 'LogiDownloadAssistant')
}

function Set-UTLogiBlock {
    <#
    .SYNOPSIS
        Windows Update reinstalls the Logi Download Assistant together with Logitech drivers.
        A folder in its install location that nobody can write to stops that; the mouse and
        keyboard keep working without it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $folder = Get-UTLogiFolder
    if (-not $PSCmdlet.ShouldProcess($folder, 'Bloquear instalação automática do Logi Download Assistant')) { return }
    $existed = Test-Path -LiteralPath $folder
    [void](Save-UTOriginalItem -Chave 'logi|pasta' -Dados ([ordered]@{ existia = $existed }) -TweakId $TweakId)
    Get-Process -Name 'logi_download_assistant' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if ($existed) {
        Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
    $r = Invoke-UTNative -FilePath 'icacls.exe' -ArgumentList @($folder, '/deny', '*S-1-1-0:(W)')
    if ($r.CodigoSaida -ne 0) { throw "icacls falhou ao bloquear a pasta: $($r.Saida)" }
}

function Restore-UTLogiBlock {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TweakId)
    $folder = Get-UTLogiFolder
    $saved = Pop-UTOriginalItem -Chave 'logi|pasta' -TweakId $TweakId
    if (-not (Test-Path -LiteralPath $folder) -or -not $PSCmdlet.ShouldProcess($folder, 'Liberar a pasta')) { return }
    [void](Invoke-UTNative -FilePath 'icacls.exe' -ArgumentList @($folder, '/remove:d', '*S-1-1-0'))
    if ($saved -is [System.Collections.IDictionary] -and -not $saved.existia -and @(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0) {
        Remove-Item -LiteralPath $folder -Force
    }
}

function Test-UTLogiBlock {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $folder = Get-UTLogiFolder
    if (-not (Test-Path -LiteralPath $folder)) { return $false }
    $acl = Get-Acl -LiteralPath $folder
    foreach ($rule in @($acl.Access)) {
        $sid = $null
        try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $sid = $null }
        if ($sid -eq 'S-1-1-0' -and [string]$rule.AccessControlType -eq 'Deny' -and ([string]$rule.FileSystemRights) -match 'Write') { return $true }
    }
    return $false
}
#endregion
