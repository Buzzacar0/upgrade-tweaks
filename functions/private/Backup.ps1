# Per-session backups in backups\AAAA-MM-DD_HHmm\: .reg export of every key before its first
# change, the services' start types (servicos.json), the active power plan (.pow) and a
# manifesto.json that lists everything, used by the "Restaurar" tab.

function Get-UTSessionState {
    <#
    .SYNOPSIS
        Synchronized hashtable with this session's bookkeeping (backup folder, exported keys,
        restore point). Lives in $UTSync.Sessao so every runspace shares it.
    #>
    [CmdletBinding()]
    param()

    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $sync) {
        if (-not $sync.ContainsKey('Sessao') -or $null -eq $sync['Sessao']) {
            $sync['Sessao'] = [hashtable]::Synchronized(@{})
        }
        return $sync['Sessao']
    }
    if ($null -eq (Get-Variable -Name UTSessionFallback -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        $script:UTSessionFallback = [hashtable]::Synchronized(@{})
    }
    return $script:UTSessionFallback
}

function Get-UTSessionBackupFolder {
    <#
    .SYNOPSIS
        Backup folder of this session (backups\AAAA-MM-DD_HHmm). Created on first use.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()

    $session = Get-UTSessionState
    if ($session['PastaBackup']) { return $session['PastaBackup'] }

    $base = Get-UTPath -Name Backups
    $name = (Get-Date).ToString('yyyy-MM-dd_HHmm')
    $folder = Join-Path $base $name
    $n = 2
    while (Test-Path -LiteralPath $folder) {
        $folder = Join-Path $base ('{0}_{1}' -f $name, $n)
        $n++
    }
    if ($PSCmdlet.ShouldProcess($folder, 'Criar pasta de backup da sessão')) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $manifest = [ordered]@{
            versao         = 1
            criadoEm       = (Get-Date).ToString('o')
            versaoPrograma = [string](Get-UTSyncValue -Key 'Versao')
            computador     = $env:COMPUTERNAME
            usuario        = $env:USERNAME
            itens          = @()
        }
        Write-UTJsonFile -Path (Join-Path $folder 'manifesto.json') -InputObject $manifest -WhatIf:$false
        $session['PastaBackup'] = $folder
    }
    return $folder
}

function Add-UTBackupManifestEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][ValidateSet('registro', 'servicos', 'energia')][string]$Tipo,
        [Parameter(Mandatory)][string]$Arquivo,
        [string]$Origem,
        [System.Collections.IDictionary]$Extra
    )

    $lock = Enter-UTNamedLock -Name 'Manifesto'
    try {
        $path = Join-Path $Folder 'manifesto.json'
        $manifest = Read-UTJsonFile -Path $path -Default ([ordered]@{ versao = 1; itens = @() })
        $entry = [ordered]@{ tipo = $Tipo; arquivo = $Arquivo; origem = $Origem; criadoEm = (Get-Date).ToString('o') }
        if ($Extra) { foreach ($k in $Extra.Keys) { $entry[$k] = $Extra[$k] } }
        $others = @(@($manifest.itens) | Where-Object { $_ -and $_.arquivo -ne $Arquivo })
        $manifest.itens = @($others + $entry)
        Write-UTJsonFile -Path $path -InputObject $manifest -WhatIf:$false
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
}

function ConvertTo-UTSafeFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Text, [int]$MaxLength = 120)

    $safe = ($Text -replace '[:\\/*?"<>|\s]+', '_').Trim('_')
    if ($safe.Length -gt $MaxLength) {
        # Keep it unique: shorten and append a hash of the full text.
        $sha = [Security.Cryptography.SHA1]::Create()
        try {
            $hash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally { $sha.Dispose() }
        $safe = $safe.Substring(0, $MaxLength - 9) + '_' + $hash
    }
    return $safe
}

function Backup-UTRegistryKey {
    <#
    .SYNOPSIS
        Exports a registry key to a .reg file once per session, before its first change.
        Returns the file path, or $null when the key does not exist yet (nothing to back up:
        the original state already records that it did not exist).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)

    $session = Get-UTSessionState
    if ($null -eq $session['RegistroExportado']) { $session['RegistroExportado'] = [hashtable]::Synchronized(@{}) }
    $loc = Resolve-UTRegistryPath -Path $Path
    $id = $loc.NativePath.ToLowerInvariant()
    if ($session['RegistroExportado'].ContainsKey($id)) { return $session['RegistroExportado'][$id] }

    if (-not (Test-UTRegistryKey -Path $Path)) {
        $session['RegistroExportado'][$id] = $null
        return $null
    }
    if (-not $PSCmdlet.ShouldProcess($loc.NativePath, 'Exportar backup .reg')) { return $null }

    $folder = Get-UTSessionBackupFolder
    $file = Join-Path $folder ('registro\' + (ConvertTo-UTSafeFileName $loc.NativePath) + '.reg')
    [void](Export-UTRegistryKey -Path $Path -Destination $file)
    Add-UTBackupManifestEntry -Folder $folder -Tipo registro -Arquivo ($file.Substring($folder.Length + 1)) -Origem $loc.NativePath
    $session['RegistroExportado'][$id] = $file
    return $file
}

function Backup-UTServiceState {
    <#
    .SYNOPSIS
        Adds the current start type of each service to servicos.json in the session folder
        (first value per service wins).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string[]]$Name)

    if (-not $PSCmdlet.ShouldProcess(($Name -join ', '), 'Salvar estado dos serviços')) { return }
    $folder = Get-UTSessionBackupFolder
    $file = Join-Path $folder 'servicos.json'
    $lock = Enter-UTNamedLock -Name 'BackupServicos'
    try {
        $data = Read-UTJsonFile -Path $file -Default ([ordered]@{ servicos = [ordered]@{} })
        foreach ($n in $Name) {
            if ($data.servicos.Contains($n)) { continue }
            $s = Get-UTServiceState -Name $n
            $data.servicos[$n] = [ordered]@{ existia = $s.Existe; startType = $s.StartType; status = $s.Status }
        }
        Write-UTJsonFile -Path $file -InputObject $data -WhatIf:$false
    } finally {
        Exit-UTNamedLock -Mutex $lock
    }
    Add-UTBackupManifestEntry -Folder $folder -Tipo servicos -Arquivo 'servicos.json' -Origem 'Serviços do Windows'
}

function Get-UTActivePowerScheme {
    <#
    .SYNOPSIS
        GUID and name of the active power plan (parses "powercfg /getactivescheme").
    #>
    [CmdletBinding()]
    param()

    $r = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('/getactivescheme')
    $m = [regex]::Match($r.Saida, '(?<guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*(\((?<nome>[^)]*)\))?')
    if ($r.CodigoSaida -ne 0 -or -not $m.Success) { throw "Não foi possível ler o plano de energia ativo: $($r.Saida) $($r.Erro)" }
    return [pscustomobject]@{ Guid = $m.Groups['guid'].Value.ToLowerInvariant(); Nome = $m.Groups['nome'].Value.Trim() }
}

function Backup-UTActivePowerPlan {
    <#
    .SYNOPSIS
        Exports the active power plan (powercfg /export) once per session.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $session = Get-UTSessionState
    if ($session['PlanoExportado']) { return $session['PlanoExportado'] }

    $active = Get-UTActivePowerScheme
    if (-not $PSCmdlet.ShouldProcess("$($active.Nome) ($($active.Guid))", 'Exportar plano de energia')) { return $null }

    $folder = Get-UTSessionBackupFolder
    $file = Join-Path $folder ("energia\plano-ativo_$($active.Guid).pow")
    $energyFolder = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $energyFolder)) { New-Item -Path $energyFolder -ItemType Directory -Force | Out-Null }
    $r = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('/export', $file, $active.Guid)
    if ($r.CodigoSaida -ne 0) { throw "powercfg /export falhou: $($r.Saida) $($r.Erro)" }

    $result = [pscustomobject]@{ Guid = $active.Guid; Nome = $active.Nome; Arquivo = $file }
    Add-UTBackupManifestEntry -Folder $folder -Tipo energia -Arquivo ($file.Substring($folder.Length + 1)) `
        -Origem $active.Nome -Extra ([ordered]@{ guid = $active.Guid })
    $session['PlanoExportado'] = $result
    return $result
}
