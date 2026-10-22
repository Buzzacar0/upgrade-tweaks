# Benchmark: records the frame times of a game (PresentMon, the same capture of the overlay),
# summarizes them (average FPS, 1% and 0.1% low, percentiles, minimum and maximum, stutters),
# keeps each run in %AppData%\UpgradeTweaks\benchmarks, exports CSV and compares two runs (before
# and after a tweak, for example).

#region Summary
function Get-UTBenchmarkSummary {
    <#
    .SYNOPSIS
        Numbers of a run. FPS médio = frames / time; 1% and 0.1% low = average FPS of the slowest
        1% / 0.1% of the frames; P1 and P0,1 = FPS at the 99th / 99.9th percentile of the frame
        times; mínimo/máximo = slowest/fastest frame; engasgos = frames over twice the median.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Frametimes)
    Initialize-UTOverlayNative
    $f = [double[]]$Frametimes
    $n = $f.Count
    if ($n -eq 0) {
        return [pscustomobject]@{ Quadros = 0; DuracaoS = 0; FpsMedio = $null; Low1 = $null; Low01 = $null; P1 = $null; P01 = $null; FpsMinimo = $null; FpsMaximo = $null; FrametimeMedio = $null; FrametimeMaximo = $null; Engasgos = 0 }
    }
    $sum = 0.0; $min = [double]::MaxValue; $max = 0.0
    foreach ($v in $f) { $sum += $v; if ($v -lt $min) { $min = $v }; if ($v -gt $max) { $max = $v } }
    $median = [UpgradeTweaks.Overlay.FrameMath]::Percentile($f, 0.5)
    $stutters = 0
    foreach ($v in $f) { if ($v -gt 2 * $median) { $stutters++ } }
    $math = [UpgradeTweaks.Overlay.FrameMath]
    return [pscustomobject]@{
        Quadros = $n; DuracaoS = [math]::Round($sum / 1000, 2)
        FpsMedio = $math::AverageFps($f); Low1 = $math::LowAverageFps($f, 0.01); Low01 = $math::LowAverageFps($f, 0.001)
        P1 = $math::PercentileFps($f, 0.01); P01 = $math::PercentileFps($f, 0.001)
        FpsMinimo = 1000 / $max; FpsMaximo = 1000 / $min
        FrametimeMedio = $sum / $n; FrametimeMaximo = $max; Engasgos = $stutters
    }
}

function Get-UTBenchmarkMetric {
    # The metrics shown and compared, with the direction that is better.
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Chave = 'FpsMedio'; Nome = 'FPS médio'; Casas = 1; MaiorMelhor = $true }
        [pscustomobject]@{ Chave = 'Low1'; Nome = '1% low'; Casas = 1; MaiorMelhor = $true }
        [pscustomobject]@{ Chave = 'Low01'; Nome = '0,1% low'; Casas = 1; MaiorMelhor = $true }
        [pscustomobject]@{ Chave = 'P1'; Nome = 'P1 (percentil 99)'; Casas = 1; MaiorMelhor = $true }
        [pscustomobject]@{ Chave = 'FpsMinimo'; Nome = 'FPS mínimo (pior quadro)'; Casas = 1; MaiorMelhor = $true }
        [pscustomobject]@{ Chave = 'FpsMaximo'; Nome = 'FPS máximo'; Casas = 1; MaiorMelhor = $true }
        [pscustomobject]@{ Chave = 'FrametimeMedio'; Nome = 'Frametime médio (ms)'; Casas = 2; MaiorMelhor = $false }
        [pscustomobject]@{ Chave = 'FrametimeMaximo'; Nome = 'Pior frametime (ms)'; Casas = 1; MaiorMelhor = $false }
        [pscustomobject]@{ Chave = 'Engasgos'; Nome = 'Engasgos (mais que 2x a mediana)'; Casas = 0; MaiorMelhor = $false }
    )
}
#endregion

#region Runs (benchmarks folder)
function Get-UTBenchmarkFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path (Get-UTPath -Name Usuario) 'benchmarks')
}

function Save-UTBenchmarkRun {
    <#
    .SYNOPSIS
        Saves a run (game, start, every frame time and the summary) as a JSON file; returns it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Jogo,
        [Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Frametimes,
        [datetime]$Inicio = [datetime]::Now,
        [string]$Nome,
        [string]$ModoApresentacao = ''
    )
    $id = '{0}_{1}' -f $Inicio.ToString('yyyyMMdd-HHmmss'), ((ConvertTo-UTSafeFileName ($Jogo -replace '\.exe$', '')) -replace '\s', '_')
    $run = [ordered]@{
        Versao = 1; Id = $id; Nome = $(if ($Nome) { $Nome } else { "$Jogo $($Inicio.ToString('dd/MM HH:mm'))" }); Jogo = $Jogo
        Inicio = $Inicio.ToString('s'); ModoApresentacao = $ModoApresentacao
        Resumo = Get-UTBenchmarkSummary -Frametimes $Frametimes
        Frametimes = @($Frametimes | ForEach-Object { [math]::Round($_, 4) })
    }
    $path = Join-Path (Get-UTBenchmarkFolder) "$id.json"
    if ($PSCmdlet.ShouldProcess($path, 'Salvar benchmark')) {
        Write-UTJsonFile -Path $path -InputObject $run -Depth 4 -Confirm:$false
        Write-UTLog -Level Sucesso -Message ("Benchmark salvo: {0}, {1:N0} FPS médio, 1% low {2:N0}." -f $run.Nome, $run.Resumo.FpsMedio, $run.Resumo.Low1)
    }
    return [pscustomobject]$run
}

function Get-UTBenchmarkRun {
    <#
    .SYNOPSIS
        Saved runs, newest first (or the one with -Id). Damaged files are skipped.
    #>
    [CmdletBinding()]
    param([string]$Id)
    $folder = Get-UTBenchmarkFolder
    if (-not (Test-Path -LiteralPath $folder)) { return }
    $files = @(Get-ChildItem -LiteralPath $folder -Filter '*.json' -File | Sort-Object Name -Descending)
    if ($Id) { $files = @($files | Where-Object { $_.BaseName -eq $Id }) }
    foreach ($file in $files) {
        try {
            $j = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($null -eq $j.Resumo -or $null -eq $j.Frametimes) { continue }
            $j
        } catch { Write-UTLog -Level Aviso -Message "Benchmark ignorado (arquivo danificado): $($file.Name)" }
    }
}

function Remove-UTBenchmarkRun {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    $path = Join-Path (Get-UTBenchmarkFolder) "$Id.json"
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Excluir benchmark')) { Remove-Item -LiteralPath $path -Force }
}

function Rename-UTBenchmarkRun {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Nome)
    $run = (@(Get-UTBenchmarkRun -Id $Id) | Select-Object -First 1)
    if ($null -eq $run) { return }
    $run.Nome = $Nome.Trim()
    $path = Join-Path (Get-UTBenchmarkFolder) "$Id.json"
    if ($PSCmdlet.ShouldProcess($path, 'Renomear benchmark')) { Write-UTJsonFile -Path $path -InputObject $run -Depth 4 -Confirm:$false }
}

function Export-UTBenchmarkCsv {
    <#
    .SYNOPSIS
        CSV of a run for Excel (";" and comma decimals): the summary on top, then one line per
        frame with its time, frame time and FPS.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][psobject]$Run, [Parameter(Mandatory)][string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Benchmark;$(ConvertTo-UTCsvField $Run.Nome)")
    $lines.Add("Jogo;$(ConvertTo-UTCsvField $Run.Jogo)")
    $lines.Add("Início;$(([datetime]$Run.Inicio).ToString('dd/MM/yyyy HH:mm:ss'))")
    $lines.Add("Quadros;$($Run.Resumo.Quadros)")
    $lines.Add("Duração (s);$(ConvertTo-UTCsvNumber $Run.Resumo.DuracaoS -Casas 2)")
    foreach ($m in Get-UTBenchmarkMetric) { $lines.Add("$($m.Nome);$(ConvertTo-UTCsvNumber $Run.Resumo.($m.Chave) -Casas $m.Casas)") }
    $lines.Add('')
    $lines.Add('Quadro;Tempo (s);Frametime (ms);FPS')
    $t = 0.0
    $i = 0
    foreach ($ms in @($Run.Frametimes)) {
        $i++
        $t += [double]$ms
        $lines.Add("$i;$(ConvertTo-UTCsvNumber ($t / 1000) -Casas 4);$(ConvertTo-UTCsvNumber $ms -Casas 3);$(ConvertTo-UTCsvNumber (1000 / [double]$ms) -Casas 1)")
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Salvar CSV do benchmark')) {
        [IO.File]::WriteAllLines($Path, $lines.ToArray(), (New-Object Text.UTF8Encoding($true)))
    }
    return $Path
}

function Compare-UTBenchmarkRun {
    <#
    .SYNOPSIS
        Metric by metric, run A against run B: the values, the difference in percent (B relative
        to A) and which one is better.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$A, [Parameter(Mandatory)][psobject]$B)
    foreach ($m in Get-UTBenchmarkMetric) {
        $va = $A.Resumo.($m.Chave); $vb = $B.Resumo.($m.Chave)
        $diff = $null; $best = '='
        if ($null -ne $va -and $null -ne $vb) {
            if ([double]$va -ne 0) { $diff = ([double]$vb - [double]$va) / [double]$va * 100 }
            $tolerance = [math]::Max([math]::Abs([double]$va) * 0.01, [math]::Pow(10, -$m.Casas))
            if ([math]::Abs([double]$vb - [double]$va) -ge $tolerance) {
                $bBetter = $(if ($m.MaiorMelhor) { [double]$vb -gt [double]$va } else { [double]$vb -lt [double]$va })
                $best = $(if ($bBetter) { 'B' } else { 'A' })
            }
        }
        [pscustomobject]@{ Metrica = $m.Nome; Chave = $m.Chave; A = $va; B = $vb; DiferencaPct = $diff; Melhor = $best; Casas = $m.Casas }
    }
}
#endregion

#region Recording
function Start-UTBenchmarkRecording {
    <#
    .SYNOPSIS
        Starts recording the frames of a process in a running PresentMon session (-Sessao). Without
        -ProcessoId, the process that drew the most frames in the last 2 seconds (the game).
        Returns the process id, or 0 when no game is drawing frames.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param([Parameter(Mandatory)][object]$Sessao, [int]$ProcessoId, [int[]]$Ignorar = @())
    if ($ProcessoId -le 0) { $ProcessoId = $Sessao.BusiestProcess(2, [int[]]@(@($Ignorar) + $PID)) }
    if ($ProcessoId -le 0) { return 0 }
    if ($PSCmdlet.ShouldProcess($Sessao.ApplicationOf($ProcessoId), 'Gravar benchmark')) { $Sessao.StartRecording($ProcessoId) }
    return $ProcessoId
}

function Stop-UTBenchmarkRecording {
    <#
    .SYNOPSIS
        Stops the recording and saves the run (at least 1 second of frames). Returns the run or $null.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][object]$Sessao, [datetime]$Inicio = [datetime]::Now, [string]$ModoApresentacao = '')
    $pid2 = $Sessao.RecordingPid
    $app = $Sessao.ApplicationOf($pid2)
    $frames = [double[]]$Sessao.StopRecording()
    $total = 0.0
    foreach ($f in $frames) { $total += $f }
    if ($frames.Count -lt 10 -or $total -lt 1000) {
        Write-UTLog -Level Aviso -Message 'Benchmark descartado: menos de 1 segundo de quadros.'
        return $null
    }
    if (-not $PSCmdlet.ShouldProcess($app, 'Salvar benchmark')) { return $null }
    return (Save-UTBenchmarkRun -Jogo $(if ($app) { $app } else { 'jogo' }) -Frametimes $frames -Inicio $Inicio -ModoApresentacao $ModoApresentacao -Confirm:$false)
}
#endregion
