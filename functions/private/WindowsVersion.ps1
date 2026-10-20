function Get-UTWindowsInfo {
    <#
    .SYNOPSIS
        Reads the Windows version from the registry.
    .DESCRIPTION
        ProductName still says "Windows 10" on Windows 11, so the generation comes from the
        build number (22000 and above is Windows 11).
    #>
    [CmdletBinding()]
    param(
        [string]$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    )

    $cv = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop
    $build = 0
    [void][int]::TryParse([string]$cv.CurrentBuild, [ref]$build)

    $ubr = 0
    if ($cv.PSObject.Properties['UBR']) { $ubr = [int]$cv.UBR }

    $displayVersion = ''
    if ($cv.PSObject.Properties['DisplayVersion']) { $displayVersion = [string]$cv.DisplayVersion }
    elseif ($cv.PSObject.Properties['ReleaseId']) { $displayVersion = [string]$cv.ReleaseId }

    $edition = ''
    if ($cv.PSObject.Properties['EditionID']) { $edition = [string]$cv.EditionID }

    $generation = '10'
    if ($build -ge 22000) { $generation = '11' }

    return [pscustomobject]@{
        Geracao       = $generation
        Nome          = "Windows $generation"
        Versao        = $displayVersion
        Build         = $build
        UBR           = $ubr
        Edicao        = $edition
        EhHome        = ($edition -like 'Core*')
        Descricao     = ('Windows {0} {1} {2} (build {3}.{4})' -f $generation, $edition, $displayVersion, $build, $ubr).Replace('  ', ' ')
    }
}

function Get-UTWindowsSupport {
    <#
    .SYNOPSIS
        Classifies the running Windows: OK, Aviso (supported with a warning) or NaoSuportado.
    .DESCRIPTION
        Supported: Windows 10 22H2 (build 19045) and Windows 11 23H2 (22631) or newer.
        Unsupported versions only get a warning; the program still opens.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Info
    )

    $build = [int]$Info.Build
    $status = 'OK'
    $message = "$($Info.Descricao): versão suportada."

    if ($build -lt 19045) {
        $status = 'NaoSuportado'
        $message = "$($Info.Descricao) não é suportado. Atualize para o Windows 10 22H2 ou para o Windows 11 23H2 ou mais novo. Alguns ajustes podem não funcionar."
    } elseif ($build -lt 22000) {
        $status = 'Aviso'
        $message = "$($Info.Descricao): o Windows 10 22H2 é suportado, mas a Microsoft encerrou o suporte gratuito em 14/10/2025. Recomendamos migrar para o Windows 11."
    } elseif ($build -lt 22631) {
        $status = 'NaoSuportado'
        $message = "$($Info.Descricao) é uma versão antiga do Windows 11 e não é suportada. Atualize para o 23H2 ou mais novo pelo Windows Update. Alguns ajustes podem não funcionar."
    }

    return [pscustomobject]@{
        Status   = $status
        Suportado = ($status -ne 'NaoSuportado')
        Mensagem = $message
    }
}
