# "Ferramentas" tab: cleanup, Windows repair, drive optimization, page file, Windows Update
# pause and shortcuts. Prefetch cleanup and "RAM cleaners" are left out on purpose (myths).

#region Temporary files
function Get-UTFolderSize {
    [CmdletBinding()]
    [OutputType([double])]
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { return 0.0 }
    $sum = Get-UTSum @(Get-ChildItem -LiteralPath $Caminho -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Length })
    return [math]::Round([double]$sum / 1MB, 1)
}

function Get-UTTargetUserTempPath {
    <#
    .SYNOPSIS
        %TEMP% of the person using the PC (not of the admin account that approved the UAC).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $sid = $null
    if ($UTSync -and $UTSync.ContainsKey('UsuarioAlvoSid')) { $sid = $UTSync['UsuarioAlvoSid'] }
    if ($sid) {
        $profileImage = Get-UTRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name 'ProfileImagePath'
        if ($profileImage.ValorExiste) { return (Join-Path ([Environment]::ExpandEnvironmentVariables([string]$profileImage.Valor)) 'AppData\Local\Temp') }
    }
    return [IO.Path]::GetTempPath().TrimEnd('\')
}

function Get-UTTempCleanupTarget {
    <#
    .SYNOPSIS
        What the cleanup can delete, with the current size, so the tab shows it before.
    #>
    [CmdletBinding()]
    param([switch]$IncluirLixeira)
    $targets = @(
        [pscustomobject]@{ Id = 'tempusuario'; Nome = 'Temporários do usuário (%TEMP%)'; Caminho = (Get-UTTargetUserTempPath) }
        [pscustomobject]@{ Id = 'tempwindows'; Nome = 'Temporários do Windows'; Caminho = (Join-Path $env:SystemRoot 'Temp') }
        [pscustomobject]@{ Id = 'windowsupdate'; Nome = 'Downloads do Windows Update já instalados'; Caminho = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download') }
    )
    if ($IncluirLixeira) {
        foreach ($d in @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) {
            $targets += [pscustomobject]@{ Id = 'lixeira'; Nome = "Lixeira ($($d.Name.TrimEnd('\')))"; Caminho = (Join-Path $d.RootDirectory.FullName '$Recycle.Bin') }
        }
    }
    foreach ($t in $targets) { $t | Add-Member -NotePropertyName TamanhoMB -NotePropertyValue (Get-UTFolderSize -Caminho $t.Caminho) -PassThru }
}

function Clear-UTTempFile {
    <#
    .SYNOPSIS
        Deletes temporary files (files in use are skipped). The Windows Update download cache
        is cleaned with its services stopped, and they go back to the state they were in.
        Returns what was freed per item.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateSet('tempusuario', 'tempwindows', 'windowsupdate', 'lixeira')][string[]]$Itens = @('tempusuario', 'tempwindows', 'windowsupdate'),
        [switch]$IncluirLixeira
    )
    Assert-UTAdmin
    if ($IncluirLixeira -and $Itens -notcontains 'lixeira') { $Itens += 'lixeira' }
    $targets = @(Get-UTTempCleanupTarget -IncluirLixeira:($Itens -contains 'lixeira') | Where-Object { $Itens -contains $_.Id })
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($t in $targets) {
        if (-not $PSCmdlet.ShouldProcess($t.Caminho, "Limpar $($t.Nome)")) { continue }
        $before = $t.TamanhoMB
        if ($t.Id -eq 'lixeira') {
            Clear-RecycleBin -DriveLetter $t.Caminho.Substring(0, 1) -Force -ErrorAction SilentlyContinue
        } elseif ($t.Id -eq 'windowsupdate') {
            $stopped = @()
            foreach ($svc in 'wuauserv', 'bits') {
                $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
                if ($s -and $s.Status -eq 'Running') { Stop-Service -Name $svc -Force -ErrorAction Stop; $stopped += $svc }
            }
            try { Remove-UTFolderContent -Caminho $t.Caminho } finally { foreach ($svc in $stopped) { Start-Service -Name $svc -ErrorAction SilentlyContinue } }
        } else {
            Remove-UTFolderContent -Caminho $t.Caminho
        }
        $after = Get-UTFolderSize -Caminho $t.Caminho
        $results.Add([pscustomobject]@{ Id = $t.Id; Nome = $t.Nome; LiberadoMB = [math]::Max(0, [math]::Round($before - $after, 1)); RestanteMB = $after })
    }
    $total = [math]::Round((Get-UTSum @($results | ForEach-Object { $_.LiberadoMB })), 1)
    Write-UTLog -Level Sucesso -Message "Limpeza de temporários: $total MB liberados."
    return $results.ToArray()
}

function Remove-UTFolderContent {
    # Deletes everything inside the folder, skipping what is in use; the folder itself stays.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { return }
    foreach ($item in @(Get-ChildItem -LiteralPath $Caminho -Force -ErrorAction SilentlyContinue)) {
        if (-not $PSCmdlet.ShouldProcess($item.FullName, 'Apagar')) { continue }
        try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop } catch { Write-Verbose "Em uso: $($item.FullName)" }
    }
}
#endregion

#region Disk Cleanup and Windows repair
function Get-UTDiskCleanupHandler {
    <#
    .SYNOPSIS
        Disk Cleanup categories used by "Limpeza de Disco". Left out: Downloads folder (user
        files), Recycle Bin (own option), previous Windows installation (removes the rollback)
        and DirectX shader cache (the GPU tab has its own cleanup, and the game recompiles).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @('Active Setup Temp Folders', 'Delivery Optimization Files', 'Device Driver Packages', 'Downloaded Program Files', 'Internet Cache Files',
        'Old ChkDsk Files', 'Setup Log Files', 'System error memory dump files', 'System error minidump files', 'Temporary Files', 'Temporary Setup Files',
        'Thumbnail Cache', 'Update Cleanup', 'Upgrade Discarded Files', 'Windows Error Reporting Files', 'Windows Upgrade Log Files')
}

function Invoke-UTDiskCleanup {
    <#
    .SYNOPSIS
        Runs "cleanmgr /sagerun" with the categories above and removes the selection flag
        afterwards. Returns the GB freed on the Windows drive.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()
    Assert-UTAdmin
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $flag = 'StateFlags0777'
    $handlers = @(Get-UTDiskCleanupHandler | Where-Object { Test-UTRegistryKey -Path "$root\$_" })
    if (-not $PSCmdlet.ShouldProcess('Limpeza de Disco', ($handlers -join ', '))) { return $null }
    $drive = New-Object System.IO.DriveInfo ($env:SystemDrive)
    $before = $drive.AvailableFreeSpace
    try {
        foreach ($h in $handlers) { Set-UTRegistryValue -Path "$root\$h" -Name $flag -Type DWord -Value 2 }
        $r = Invoke-UTNative -FilePath (Join-Path $env:SystemRoot 'System32\cleanmgr.exe') -ArgumentList @('/sagerun:777') -TimeoutSeconds 3600
        Write-UTLog -Level Info -Message "Limpeza de Disco terminou (código $($r.CodigoSaida))."
    } finally {
        foreach ($h in $handlers) { [void](Remove-UTRegistryValue -Path "$root\$h" -Name $flag) }
    }
    $drive = New-Object System.IO.DriveInfo ($env:SystemDrive)
    $freed = [math]::Round([math]::Max(0, $drive.AvailableFreeSpace - $before) / 1GB, 2)
    Write-UTLog -Level Sucesso -Message "Limpeza de Disco: $freed GB liberados em $env:SystemDrive."
    return $freed
}

function ConvertFrom-UTToolOutput {
    # sfc writes UTF-16 even when redirected; removes the NULs and the progress lines.
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Texto)
    if (-not $Texto) { return '' }
    $clean = $Texto -replace "`0", ''
    $lines = foreach ($l in ($clean -split "`r?`n")) {
        $last = (@($l -split "`r") | Select-Object -Last 1).TrimEnd()
        # DISM progress bar: [=====   45.0%            ]
        if ($last -and $last -notmatch '^\s*\[[=\s\d.,%]*\]\s*$') { $last }
    }
    return (@($lines) -join [Environment]::NewLine)
}

function Invoke-UTWindowsRepairTool {
    <#
    .SYNOPSIS
        sfc /scannow, DISM /RestoreHealth or DISM /StartComponentCleanup. The output goes to the
        log; returns exit code, success and a short PT-BR summary.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('sfc', 'restorehealth', 'componentcleanup')][string]$Ferramenta)
    Assert-UTAdmin
    $sys32 = Join-Path $env:SystemRoot 'System32'
    switch ($Ferramenta) {
        'sfc' { $file = Join-Path $sys32 'sfc.exe'; $arguments = @('/scannow'); $label = 'Verificação de arquivos do sistema (sfc /scannow)' }
        'restorehealth' { $file = Join-Path $sys32 'dism.exe'; $arguments = @('/Online', '/Cleanup-Image', '/RestoreHealth'); $label = 'Reparo da imagem do Windows (DISM /RestoreHealth)' }
        'componentcleanup' { $file = Join-Path $sys32 'dism.exe'; $arguments = @('/Online', '/Cleanup-Image', '/StartComponentCleanup'); $label = 'Limpeza de componentes (DISM /StartComponentCleanup)' }
    }
    if (-not $PSCmdlet.ShouldProcess($label, (($file | Split-Path -Leaf) + ' ' + ($arguments -join ' ')))) { return $null }
    Write-UTLog -Level Info -Message "$label iniciada. Pode levar de 5 a 30 minutos."
    $r = Invoke-UTNative -FilePath $file -ArgumentList $arguments -TimeoutSeconds 5400
    $out = ConvertFrom-UTToolOutput -Texto ($r.Saida + [Environment]::NewLine + $r.Erro)
    $ok = ($r.CodigoSaida -eq 0)
    $summary = switch ($Ferramenta) {
        'sfc' { $(if ($ok) { 'Terminou. Se ele encontrou e corrigiu arquivos, reinicie o PC. Detalhes em C:\Windows\Logs\CBS\CBS.log.' } else { 'O sfc não conseguiu terminar. Rode o "Reparo da imagem (DISM)" e depois o sfc de novo.' }) }
        'restorehealth' { $(if ($ok) { 'Imagem do Windows verificada e reparada. Rode o sfc /scannow em seguida.' } else { 'O DISM não conseguiu reparar (precisa de internet e do Windows Update funcionando).' }) }
        'componentcleanup' { $(if ($ok) { 'Componentes antigos do Windows Update removidos.' } else { 'A limpeza de componentes não terminou.' }) }
    }
    Write-UTLog -Level $(if ($ok) { 'Sucesso' } else { 'Aviso' }) -Message "${label}: $summary" -Detalhe $out
    return [pscustomobject]@{ Ferramenta = $Ferramenta; CodigoSaida = $r.CodigoSaida; Sucesso = $ok; Resumo = $summary; Saida = $out }
}
#endregion

#region Drives
function Get-UTDriveOptimizationPlan {
    <#
    .SYNOPSIS
        What "Otimizar unidades" does on each drive: TRIM on SSD/NVMe, defrag only on HDD.
        Unknown media type is skipped (never defragment something that may be an SSD).
    #>
    [CmdletBinding()]
    param([psobject]$Armazenamento)
    if ($null -eq $Armazenamento) { $Armazenamento = Get-UTStorageInfo }
    foreach ($v in @($Armazenamento.Volumes)) {
        $disk = (@($Armazenamento.Discos | Where-Object { $_.Numero -eq $v.Disco }) | Select-Object -First 1)
        $kind = $(if ($disk) { $disk.Tipo } else { 'Desconhecido' })
        $action = switch ($kind) { 'NVMe' { 'ReTrim' } 'SSD' { 'ReTrim' } 'HDD' { 'Defrag' } default { 'Nenhuma' } }
        $text = switch ($action) { 'ReTrim' { 'TRIM (avisa o SSD dos blocos livres)' } 'Defrag' { 'Desfragmentar (HD)' } default { 'Pular: tipo de disco desconhecido' } }
        [pscustomobject]@{ Letra = $v.Letra; Disco = $(if ($disk) { $disk.Nome } else { $null }); Tipo = $kind; Acao = $action; Descricao = $text }
    }
}

function Optimize-UTDrive {
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$Letra)
    Assert-UTAdmin
    $plan = @(Get-UTDriveOptimizationPlan)
    if ($Letra) { $plan = @($plan | Where-Object { $Letra -contains $_.Letra }) }
    foreach ($p in $plan) {
        if ($p.Acao -eq 'Nenhuma') { [pscustomobject]@{ Letra = $p.Letra; Acao = $p.Acao; Sucesso = $false; Mensagem = $p.Descricao }; continue }
        if (-not $PSCmdlet.ShouldProcess("$($p.Letra):", $p.Descricao)) { continue }
        try {
            if ($p.Acao -eq 'ReTrim') { Optimize-Volume -DriveLetter $p.Letra -ReTrim -ErrorAction Stop } else { Optimize-Volume -DriveLetter $p.Letra -Defrag -ErrorAction Stop }
            Write-UTLog -Level Sucesso -Message "Unidade $($p.Letra): $($p.Descricao) concluído."
            [pscustomobject]@{ Letra = $p.Letra; Acao = $p.Acao; Sucesso = $true; Mensagem = 'Concluído.' }
        } catch {
            Write-UTLog -Level Aviso -Message "Unidade $($p.Letra): não foi possível otimizar." -Detalhe $_.Exception.Message
            [pscustomobject]@{ Letra = $p.Letra; Acao = $p.Acao; Sucesso = $false; Mensagem = 'Não foi possível otimizar esta unidade.' }
        }
    }
}
#endregion

#region Page file
function Get-UTPageFileStatus {
    <#
    .SYNOPSIS
        Page file state with the recommendation ("gerenciado pelo sistema").
    #>
    [CmdletBinding()]
    param()
    $p = (Get-UTSystemSettingsInfo).Paginacao
    $state = $(if ($p.Automatica) { 'Automatico' } elseif (@($p.Arquivos).Count -eq 0 -and -not $p.EmUso) { 'Desativado' } else { 'Personalizado' })
    $text = switch ($state) {
        'Automatico' { 'Gerenciado pelo sistema (recomendado).' }
        'Desativado' { 'Desativado. O Call of Duty fecha sozinho por falta de memória sem arquivo de paginação; ative "gerenciado pelo sistema".' }
        default { 'Tamanho personalizado. Se o jogo fechar sozinho, volte para "gerenciado pelo sistema".' }
    }
    return [pscustomobject]@{ Estado = $state; Mensagem = $text; Arquivos = @($p.Arquivos) }
}
#endregion

#region Windows Update pause
function Get-UTWindowsUpdatePauseKey { 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' }

function Get-UTWindowsUpdatePause {
    [CmdletBinding()]
    param()
    $v = Get-UTRegistryValue -Path (Get-UTWindowsUpdatePauseKey) -Name 'PauseUpdatesExpiryTime'
    if (-not $v.ValorExiste -or -not $v.Valor) { return [pscustomobject]@{ Pausado = $false; Ate = $null } }
    $until = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$v.Valor, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$until)) {
        return [pscustomobject]@{ Pausado = $false; Ate = $null }
    }
    return [pscustomobject]@{ Pausado = ($until -gt [datetime]::UtcNow); Ate = $until.ToLocalTime() }
}

function Suspend-UTWindowsUpdate {
    <#
    .SYNOPSIS
        Pauses Windows Update the same way the Settings app does (up to 35 days, never
        permanently). "Retomar" undoes it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateRange(1, 35)][int]$Dias)
    Assert-UTAdmin
    $start = [datetime]::UtcNow
    $end = $start.AddDays($Dias)
    $fmt = 'yyyy-MM-ddTHH:mm:ssZ'
    if (-not $PSCmdlet.ShouldProcess('Windows Update', "Pausar por $Dias dias (até $($end.ToLocalTime().ToString('dd/MM/yyyy')))")) { return $null }
    $key = Get-UTWindowsUpdatePauseKey
    foreach ($name in 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime') { Set-UTRegistryValue -Path $key -Name $name -Type String -Value $start.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture) }
    foreach ($name in 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime') { Set-UTRegistryValue -Path $key -Name $name -Type String -Value $end.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture) }
    Write-UTLog -Level Sucesso -Message "Windows Update pausado até $($end.ToLocalTime().ToString('dd/MM/yyyy')). As atualizações de segurança voltam sozinhas depois disso."
    return $end.ToLocalTime()
}

function Resume-UTWindowsUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess('Windows Update', 'Retomar atualizações')) { return }
    $key = Get-UTWindowsUpdatePauseKey
    foreach ($name in 'PauseUpdatesStartTime', 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime') {
        [void](Remove-UTRegistryValue -Path $key -Name $name)
    }
    Write-UTLog -Level Sucesso -Message 'Windows Update retomado.'
}
#endregion

#region Shortcuts
function Get-UTSystemShortcut {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Id = 'dispositivos'; Nome = 'Gerenciador de Dispositivos'; Comando = 'devmgmt.msc'; Argumentos = $null }
        [pscustomobject]@{ Id = 'energia'; Nome = 'Opções de Energia'; Comando = 'control.exe'; Argumentos = 'powercfg.cpl' }
        [pscustomobject]@{ Id = 'video'; Nome = 'Configurações de Vídeo'; Comando = 'ms-settings:display'; Argumentos = $null }
        [pscustomobject]@{ Id = 'graficos'; Nome = 'Configurações de Gráficos (preferência de GPU por app)'; Comando = 'ms-settings:display-advancedgraphics'; Argumentos = $null }
        [pscustomobject]@{ Id = 'seguranca'; Nome = 'Segurança do Windows'; Comando = 'windowsdefender:'; Argumentos = $null }
        [pscustomobject]@{ Id = 'msconfig'; Nome = 'Configuração do Sistema (msconfig)'; Comando = 'msconfig.exe'; Argumentos = $null }
        [pscustomobject]@{ Id = 'som'; Nome = 'Dispositivos de som'; Comando = 'control.exe'; Argumentos = 'mmsys.cpl' }
        [pscustomobject]@{ Id = 'servicos'; Nome = 'Serviços'; Comando = 'services.msc'; Argumentos = $null }
    )
}

function Open-UTSystemShortcut {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('dispositivos', 'energia', 'video', 'graficos', 'seguranca', 'msconfig', 'som', 'servicos')][string]$Atalho)
    $s = (@(Get-UTSystemShortcut | Where-Object Id -eq $Atalho) | Select-Object -First 1)
    if (-not $PSCmdlet.ShouldProcess($s.Nome, 'Abrir')) { return }
    if ($s.Argumentos) { Start-Process -FilePath $s.Comando -ArgumentList $s.Argumentos } else { Start-Process -FilePath $s.Comando }
}
#endregion
