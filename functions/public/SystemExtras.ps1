# Extra system tools of the Ferramentas tab (the useful part of the Ghost Toolbox menus): event
# logs, search index, Explorer views, CompactOS, a quick disk test and the scheduled cleanup of
# the standby memory.

#region Event logs, search index and Explorer
function Clear-UTEventLog {
    <#
    .SYNOPSIS
        Empties every log of the Event Viewer (wevtutil). Returns how many were cleared.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param()
    Assert-UTAdmin
    $list = Invoke-UTNative -FilePath 'wevtutil.exe' -ArgumentList @('el')
    if ($list.CodigoSaida -ne 0) { throw "Não foi possível listar os logs de eventos: $($list.Erro)" }
    $names = @($list.Saida -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $PSCmdlet.ShouldProcess("$($names.Count) logs de eventos", 'Limpar')) { return 0 }
    $cleared = 0
    foreach ($n in $names) {
        $r = Invoke-UTNative -FilePath 'wevtutil.exe' -ArgumentList @('cl', $n) -TimeoutSeconds 60
        if ($r.CodigoSaida -eq 0) { $cleared++ }
    }
    Write-UTLog -Level Sucesso -Message "Logs de eventos limpos: $cleared de $($names.Count) (os demais são protegidos pelo Windows)."
    return $cleared
}

function Reset-UTSearchIndex {
    <#
    .SYNOPSIS
        Deletes the Windows Search index so it is rebuilt from scratch (fixes a search that does
        not find files or an indexer using too much CPU/disk). Rebuilding takes a while.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    $folder = Join-Path $env:ProgramData 'Microsoft\Search\Data\Applications\Windows'
    if (-not $PSCmdlet.ShouldProcess($folder, 'Apagar o índice de pesquisa e recriar')) { return }
    $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
    if ($null -eq $svc) { throw 'O serviço Windows Search não existe neste Windows.' }
    if ([string]$svc.StartType -eq 'Disabled') { throw 'O Windows Search está desativado (aba Serviços e Apps). Ative-o antes de recriar o índice.' }
    Stop-Service -Name 'WSearch' -Force -ErrorAction Stop
    try {
        if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Force | Remove-Item -Recurse -Force -ErrorAction Stop }
    } finally {
        Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
    }
    Write-UTLog -Level Sucesso -Message 'Índice de pesquisa apagado; o Windows está recriando (pode levar alguns minutos).'
}

function Get-UTTargetUserProfilePath {
    # Profile folder of the person using the PC (not of the admin account that approved the UAC).
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $sid = Get-UTSyncValue -Key 'UsuarioAlvoSid'
    if ($sid) {
        $p = Get-UTRegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name 'ProfileImagePath'
        if ($p.ValorExiste) { return [Environment]::ExpandEnvironmentVariables([string]$p.Valor) }
    }
    return $env:USERPROFILE
}

function Reset-UTExplorerView {
    <#
    .SYNOPSIS
        Fix for a slow or stuck File Explorer: forgets the saved views of every folder (Bags),
        clears the recent-items lists of the taskbar/Start (jump lists) and the Run history, then
        restarts the Explorer. Files are never touched.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('Explorador de Arquivos', 'Redefinir modos de exibição e reiniciar')) { return }
    foreach ($key in 'HKCU:\Software\Microsoft\Windows\Shell\Bags', 'HKCU:\Software\Microsoft\Windows\Shell\BagMRU', 'HKCU:\Software\Microsoft\Windows\ShellNoRoam\Bags', 'HKCU:\Software\Microsoft\Windows\ShellNoRoam\BagMRU', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU') {
        $p = Resolve-UTRegistryPath -Path $key
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($p.Hive, [Microsoft.Win32.RegistryView]::Registry64)
        try { $base.DeleteSubKeyTree($p.SubKey, $false) } catch { Write-UTLog -Level Aviso -Message "Não foi possível apagar $key." -Detalhe $_.Exception.Message } finally { $base.Dispose() }
    }
    $recent = Join-Path (Get-UTTargetUserProfilePath) 'AppData\Roaming\Microsoft\Windows\Recent'
    foreach ($sub in 'AutomaticDestinations', 'CustomDestinations') {
        $dir = Join-Path $recent $sub
        if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    }
    Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') }
    Write-UTLog -Level Sucesso -Message 'Explorador de Arquivos redefinido e reiniciado.'
}
#endregion

#region CompactOS and disk test
function Get-UTCompactOSState {
    <#
    .SYNOPSIS
        $true when the Windows files are compressed (CompactOS), $false when not, $null unknown.
    #>
    [CmdletBinding()]
    param()
    $r = Invoke-UTNative -FilePath 'compact.exe' -ArgumentList @('/CompactOS:query') -TimeoutSeconds 120
    $text = "$($r.Saida)"
    if ($text -match '(?i)\b(not|não|nao)\b[^.]*\b(compact|compacto)') { return $false }
    if ($text -match '(?i)\b(compact state|estado compacto|compact)\b') { return $true }
    return $null
}

function Set-UTCompactOS {
    <#
    .SYNOPSIS
        Compresses (or decompresses) the Windows files with CompactOS. Frees 2 to 5 GB on the
        Windows drive; on an NVMe/SSD the cost when opening programs is negligible. Takes minutes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][bool]$Ativar)
    Assert-UTAdmin
    $mode = $(if ($Ativar) { 'always' } else { 'never' })
    if (-not $PSCmdlet.ShouldProcess('Windows', "CompactOS: $mode")) { return }
    $before = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free
    $r = Invoke-UTNative -FilePath 'compact.exe' -ArgumentList @("/CompactOS:$mode") -TimeoutSeconds 3600
    if ($r.CodigoSaida -ne 0) { throw "O compact.exe falhou: $($r.Saida) $($r.Erro)".Trim() }
    $after = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free
    $gb = [math]::Round(($after - $before) / 1GB, 1)
    Write-UTLog -Level Sucesso -Message $(if ($Ativar) { "CompactOS ativado: $gb GB liberados." } else { "CompactOS desativado: $([math]::Abs($gb)) GB voltaram a ser usados." })
    return $gb
}

function Measure-UTDiskSpeed {
    <#
    .SYNOPSIS
        Quick disk test with the Windows own tool (winsat disk): sequential and random read and
        write in MB/s. Takes about a minute.
    #>
    [CmdletBinding()]
    param([ValidatePattern('^[A-Za-z]$')][string]$Unidade = $env:SystemDrive.TrimEnd(':'))
    Assert-UTAdmin
    $r = Invoke-UTNative -FilePath 'winsat.exe' -ArgumentList @('disk', '-drive', $Unidade.ToLowerInvariant()) -TimeoutSeconds 600
    $rows = foreach ($line in ($r.Saida -split "`r?`n")) {
        $m = [regex]::Match($line, '^>\s*Disk\s+(?<t>.+?)\s{2,}(?<v>[\d.,]+)\s*MB/s', 'IgnoreCase')
        if ($m.Success) {
            $label = $m.Groups['t'].Value.Trim() -replace 'Random 16.0 Read', 'Leitura aleatória' -replace 'Sequential 64.0 Read', 'Leitura sequencial' -replace 'Sequential 64.0 Write', 'Escrita sequencial' -replace 'Random 16.0 Write', 'Escrita aleatória'
            [pscustomobject]@{ Teste = $label; MBs = [double]($m.Groups['v'].Value.Replace(',', '.')) }
        }
    }
    if (@($rows).Count -eq 0) { throw "O winsat não devolveu resultados. $($r.Erro)".Trim() }
    return @($rows)
}
#endregion

#region Scheduled cleanup of the standby memory
function Get-UTMemoryCleanTaskName { return 'Upgrade Tweaks - Limpeza da RAM' }

function Get-UTMemoryCleanScript {
    <#
    .SYNOPSIS
        Script of the scheduled task: empties the standby list when the free memory (free + zero
        lists, without the cache) is below -LimiteMB. Self-contained: the task does not depend on
        the Upgrade Tweaks being on the disk.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int]$LimiteMB = 0)
    return @"
`$ErrorActionPreference = 'Stop'
`$limit = $LimiteMB
if (`$limit -gt 0) {
    `$m = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Memory
    if ([double]`$m.FreeAndZeroPageListBytes -ge (`$limit * 1MB)) { exit 0 }
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UTPurge {
    [StructLayout(LayoutKind.Sequential, Pack = 1)] struct TP { public int Count; public long Luid; public int Attributes; }
    [DllImport("advapi32.dll")] static extern bool OpenProcessToken(IntPtr p, int a, out IntPtr t);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string s, string n, out long l);
    [DllImport("advapi32.dll")] static extern bool AdjustTokenPrivileges(IntPtr t, bool d, ref TP n, int l, IntPtr p, IntPtr r);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int c, ref int i, int l);
    public static int Run() {
        IntPtr t; OpenProcessToken(GetCurrentProcess(), 0x28, out t);
        long l; LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out l);
        var tp = new TP { Count = 1, Luid = l, Attributes = 2 };
        AdjustTokenPrivileges(t, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int cmd = 4;
        return NtSetSystemInformation(80, ref cmd, 4);
    }
}
'@
[void][UTPurge]::Run()
"@
}

function Get-UTMemoryCleanTask {
    <#
    .SYNOPSIS
        State of the scheduled cleanup: Ativo, Minutos, LimiteMB.
    #>
    [CmdletBinding()]
    param()
    $task = Get-ScheduledTask -TaskName (Get-UTMemoryCleanTaskName) -ErrorAction SilentlyContinue
    if ($null -eq $task) { return [pscustomobject]@{ Ativo = $false; Minutos = 0; LimiteMB = 0 } }
    $minutes = 0
    $interval = [string](@($task.Triggers) | Select-Object -First 1).Repetition.Interval
    $m = [regex]::Match($interval, '^PT(?:(\d+)H)?(?:(\d+)M)?$')
    if ($m.Success) { $minutes = [int]('0' + $m.Groups[1].Value) * 60 + [int]('0' + $m.Groups[2].Value) }
    $limit = 0
    $lm = [regex]::Match([string]$task.Description, 'limite=(\d+)')
    if ($lm.Success) { $limit = [int]$lm.Groups[1].Value }
    return [pscustomobject]@{ Ativo = ([string]$task.State -ne 'Disabled'); Minutos = $minutes; LimiteMB = $limit }
}

function Register-UTMemoryCleanTask {
    <#
    .SYNOPSIS
        Scheduled task (SYSTEM, hidden) that empties the standby memory every -Minutos.
    .DESCRIPTION
        Honestly: Windows already hands the cached memory to the game when it needs it. The
        cleanup helps only on PCs with little RAM where the cache does not shrink fast enough
        (stutters after hours of use). With -LimiteMB it only acts when the free memory is low.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet(1, 5, 15, 30, 60)][int]$Minutos,
        [ValidateRange(0, 65536)][int]$LimiteMB = 1024
    )
    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess((Get-UTMemoryCleanTaskName), "Agendar a cada $Minutos minuto(s)")) { return }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-UTMemoryCleanScript -LimiteMB $LimiteMB)))
    $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutos)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
    $desc = "Upgrade Tweaks: esvazia a memória em espera a cada $Minutos min. limite=$LimiteMB"
    Register-ScheduledTask -TaskName (Get-UTMemoryCleanTaskName) -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $desc -Force | Out-Null
    $when = ''
    if ($LimiteMB -gt 0) { $when = " (só com menos de $LimiteMB MB livres)" }
    Write-UTLog -Level Sucesso -Message "Limpeza automática da RAM agendada a cada $Minutos minuto(s)$when."
}

function Unregister-UTMemoryCleanTask {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Assert-UTAdmin
    $task = Get-ScheduledTask -TaskName (Get-UTMemoryCleanTaskName) -ErrorAction SilentlyContinue
    if ($null -eq $task) { return }
    if ($PSCmdlet.ShouldProcess((Get-UTMemoryCleanTaskName), 'Remover tarefa agendada')) {
        Unregister-ScheduledTask -TaskName (Get-UTMemoryCleanTaskName) -Confirm:$false
        Write-UTLog -Level Info -Message 'Limpeza automática da RAM desligada.'
    }
}
#endregion
