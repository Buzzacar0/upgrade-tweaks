# Automatic DDU (Display Driver Uninstaller) in Safe Mode, the way its author recommends:
#
#   now          : restore point, block driver downloads from Windows Update (saved), Safe
#                  Mode flag, RunOnce entry that runs even in Safe Mode ("*" prefix), restart
#   Safe Mode    : 1) remove the Safe Mode flag first (the PC can never get stuck there)
#                  2) DDU -Silent -Clean<vendor>  3) restart
#   normal boot  : open the new driver installer, wait for it, unblock Windows Update
#
# Safe Mode "minimal" has no network, which is what DDU asks for.

function Get-UTDduFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path (Get-UTPath -Name Root) 'ddu')
}

function Get-UTDduArgument {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][ValidateSet('nvidia', 'amd', 'intel')][string]$Fabricante)
    $vendor = @{ nvidia = '-CleanNvidia'; amd = '-CleanAmd'; intel = '-CleanIntel' }[$Fabricante]
    return @('-Silent', $vendor, '-NoSafeModeMsg')
}

function New-UTDduStageScript {
    <#
    .SYNOPSIS
        Writes the two scripts that run after the restarts. Returns their paths.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$DDu,
        [Parameter(Mandatory)][string[]]$Argumentos,
        [string]$Instalador,
        [AllowNull()][object]$BuscaOriginal
    )
    $folder = Get-UTDduFolder
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $log = Join-Path $folder 'ddu.log'
    $q = { param($t) "'" + ([string]$t).Replace("'", "''") + "'" }
    $safe = @(
        '# Upgrade Tweaks - etapa do Modo de Segurança (gerado automaticamente)'
        '$ErrorActionPreference = ''Continue'''
        "`$log = $(& $q $log)"
        'function Log([string]$m) { Add-Content -LiteralPath $log -Value ((Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') + '' '' + $m) -Encoding UTF8 }'
        '# 1) Sai do Modo de Segurança no próximo boot, aconteça o que acontecer.'
        '& bcdedit.exe /deletevalue ''{current}'' safeboot | Out-Null'
        'Log ''Modo de Segurança desmarcado para o próximo boot.'''
        'try {'
        "    Log 'Rodando o DDU: $($Argumentos -join ' ')'"
        "    `$p = Start-Process -FilePath $(& $q $DDu) -ArgumentList $((@($Argumentos) | ForEach-Object { & $q $_ }) -join ', ') -Wait -PassThru"
        '    Log (''DDU terminou com o código '' + $p.ExitCode)'
        '} catch { Log (''Falha ao rodar o DDU: '' + $_.Exception.Message) }'
        '& shutdown.exe /r /t 5 /c ''Upgrade Tweaks: limpeza do driver concluída, voltando ao Windows normal.'''
    )
    $normal = @(
        '# Upgrade Tweaks - etapa depois da limpeza (gerado automaticamente)'
        '$ErrorActionPreference = ''Continue'''
        "`$log = $(& $q $log)"
        'function Log([string]$m) { Add-Content -LiteralPath $log -Value ((Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') + '' '' + $m) -Encoding UTF8 }'
    )
    if ($Instalador) {
        $normal += "try { Log 'Abrindo o instalador do driver novo.'; Start-Process -FilePath $(& $q $Instalador) -Wait } catch { Log ('Falha ao abrir o instalador: ' + `$_.Exception.Message) }"
    }
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
    if ($null -eq $BuscaOriginal) {
        $normal += "Remove-ItemProperty -Path $(& $q $key) -Name 'SearchOrderConfig' -ErrorAction SilentlyContinue"
    } else {
        $normal += "Set-ItemProperty -Path $(& $q $key) -Name 'SearchOrderConfig' -Value $([int]$BuscaOriginal) -Type DWord"
    }
    $normal += 'Log ''Windows Update pode voltar a instalar drivers. Fim.'''
    $safeFile = Join-Path $folder 'etapa-modo-seguranca.ps1'
    $normalFile = Join-Path $folder 'etapa-depois.ps1'
    if ($PSCmdlet.ShouldProcess($folder, 'Gravar as etapas do DDU')) {
        $enc = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllLines($safeFile, [string[]]$safe, $enc)
        [IO.File]::WriteAllLines($normalFile, [string[]]$normal, $enc)
    }
    return [pscustomobject]@{ ModoSeguranca = $safeFile; Depois = $normalFile; Log = $log }
}

function Start-UTDduClean {
    <#
    .SYNOPSIS
        Prepares and starts the automatic DDU cleanup (see the top of this file).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateSet('nvidia', 'amd', 'intel')][string]$Fabricante,
        [Parameter(Mandatory)][string]$Instalador,
        [switch]$NaoReiniciar
    )
    Assert-UTAdmin
    if (-not (Test-Path -LiteralPath $Instalador -PathType Leaf)) { throw "Instalador do driver não encontrado: $Instalador" }
    $ddu = Find-UTProgramExecutable -Programa (Get-UTProgramCatalog -Id 'ddu')
    if (-not $ddu) {
        Write-UTLog -Level Info -Message 'Instalando o DDU pelo winget.'
        [void](Install-UTProgram -Id 'ddu')
        $ddu = Find-UTProgramExecutable -Programa (Get-UTProgramCatalog -Id 'ddu')
    }
    if (-not $ddu) { throw 'O DDU não pôde ser instalado. Instale pela aba Programas e tente de novo.' }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Reiniciar em Modo de Segurança e limpar o driver $Fabricante com o DDU")) { return $null }

    [void](Invoke-UTPreApplySafety)
    $folder = Get-UTDduFolder
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    # The installer goes to a fixed place: Downloads may be on another drive or synced.
    $copy = Join-Path $folder (Split-Path -Leaf $Instalador)
    if ($copy -ne $Instalador) { Copy-Item -LiteralPath $Instalador -Destination $copy -Force }

    $searchKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
    $search = Get-UTRegistryValue -Path $searchKey -Name 'SearchOrderConfig'
    $original = $(if ($search.ValorExiste) { [int]$search.Valor } else { $null })
    $stages = New-UTDduStageScript -DDu $ddu -Argumentos (Get-UTDduArgument -Fabricante $Fabricante) -Instalador $copy -BuscaOriginal $original

    # Windows Update must not put a driver back before the new one is installed.
    Set-UTRegistryValue -Path $searchKey -Name 'SearchOrderConfig' -Type DWord -Value 0
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $runOnce = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    Set-UTRegistryValue -Path $runOnce -Name '*UpgradeTweaksDDU' -Type String -Value ("`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$($stages.ModoSeguranca)`"")
    Set-UTRegistryValue -Path $runOnce -Name 'UpgradeTweaksDriver' -Type String -Value ("`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$($stages.Depois)`"")

    Suspend-UTBitLockerForBoot -Reinicios 2 -Confirm:$false
    $r = Invoke-UTNative -FilePath (Join-Path $env:SystemRoot 'System32\bcdedit.exe') -ArgumentList @('/set', '{current}', 'safeboot', 'minimal')
    if ($r.CodigoSaida -ne 0) {
        Stop-UTDduClean -Confirm:$false
        throw "Não foi possível marcar o Modo de Segurança (bcdedit): $($r.Saida) $($r.Erro)"
    }
    Write-UTLog -Level Sucesso -Message "Limpeza do driver $Fabricante preparada. O PC vai reiniciar em Modo de Segurança, rodar o DDU e voltar sozinho. Log: $($stages.Log)"
    if (-not $NaoReiniciar) {
        [void](Invoke-UTNative -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList @('/r', '/t', '15', '/c', 'Upgrade Tweaks: reiniciando em Modo de Segurança para limpar o driver de vídeo.'))
    }
    return $stages
}

function Stop-UTDduClean {
    <#
    .SYNOPSIS
        Cancels a prepared cleanup that has not run yet (before the restart).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Cancelar a limpeza do DDU')) { return }
    [void](Invoke-UTNative -FilePath (Join-Path $env:SystemRoot 'System32\bcdedit.exe') -ArgumentList @('/deletevalue', '{current}', 'safeboot'))
    $runOnce = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    [void](Remove-UTRegistryValue -Path $runOnce -Name '*UpgradeTweaksDDU')
    $after = Join-Path (Get-UTDduFolder) 'etapa-depois.ps1'
    [void](Remove-UTRegistryValue -Path $runOnce -Name 'UpgradeTweaksDriver')
    # The "after" stage restores Windows Update driver downloads; run that part now.
    if (Test-Path -LiteralPath $after) {
        $restore = @(Get-Content -LiteralPath $after -Encoding UTF8 | Where-Object { $_ -match 'SearchOrderConfig' })
        foreach ($line in $restore) { & ([scriptblock]::Create($line)) }
    }
    [void](Invoke-UTNative -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList @('/a'))
    Write-UTLog -Level Info -Message 'Limpeza do DDU cancelada; nada foi removido.'
}
