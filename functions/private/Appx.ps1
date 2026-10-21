# App (Appx) removal for the debloat. Protected packages (Store, Xbox, Game Bar, Calculator,
# Photos, Terminal, winget...) can never be removed, whatever the caller asks.

function Test-UTAppxProtected {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Pacote)
    $protected = @((Get-UTConfig -Name 'apps-debloat').protegidos)
    foreach ($pattern in $protected) {
        if ($Pacote -like $pattern) { return $true }
    }
    return $false
}

function Remove-UTAppxPackage {
    <#
    .SYNOPSIS
        Removes an app for all users and from the provisioned image (new accounts).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Pacote,
        [Parameter(Mandatory)][string]$TweakId
    )

    if (Test-UTAppxProtected -Pacote $Pacote) { throw "O app $Pacote é protegido e não pode ser removido pelo Upgrade Tweaks." }
    if (-not $PSCmdlet.ShouldProcess($Pacote, 'Remover app de todos os usuários')) { return }

    $installed = @(Get-AppxPackage -AllUsers -Name $Pacote -ErrorAction SilentlyContinue)
    [void](Save-UTOriginalItem -Chave "appx|$Pacote" -Dados ([ordered]@{ pacote = $Pacote; instalado = ($installed.Count -gt 0) }) -TweakId $TweakId)
    foreach ($p in $installed) {
        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
    }
    foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $Pacote })) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -AllUsers -ErrorAction SilentlyContinue | Out-Null
    }
    Write-UTLog -Level Info -TweakId $TweakId -Message "App removido: $Pacote ($($installed.Count) instalação(ões))."
}

function Test-UTAppxRemoved {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Pacote)
    return (@(Get-AppxPackage -Name $Pacote -ErrorAction SilentlyContinue).Count -eq 0)
}

function Install-UTStoreApp {
    <#
    .SYNOPSIS
        Reinstalls an app from the Microsoft Store through winget (undo of the debloat).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreId,
        [string]$Nome
    )
    if (-not $PSCmdlet.ShouldProcess("$Nome ($StoreId)", 'Reinstalar pela Microsoft Store')) { return }
    if (-not (Get-Command -Name winget.exe -ErrorAction SilentlyContinue)) {
        throw "O winget não está disponível. Reinstale $Nome pela Microsoft Store."
    }
    $r = Invoke-UTNative -FilePath 'winget.exe' -TimeoutSeconds 900 -ArgumentList @(
        'install', '--id', $StoreId, '--source', 'msstore', '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($r.CodigoSaida -ne 0) { throw "Não foi possível reinstalar $Nome pela Microsoft Store (winget $($r.CodigoSaida))." }
    Write-UTLog -Level Sucesso -Message "$Nome reinstalado pela Microsoft Store."
}
