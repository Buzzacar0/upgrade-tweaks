function Get-UTSyncValue {
    <#
    .SYNOPSIS
        Reads a key from the shared $UTSync table without failing when it does not exist
        (tests and early bootstrap run before the table is created).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)

    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $sync -or -not $sync.ContainsKey($Key)) { return $null }
    # The comma keeps collections (like the empty log queue) from being unrolled on return.
    return , $sync[$Key]
}

function Write-UTLog {
    <#
    .SYNOPSIS
        Writes one entry to the daily log file, to the console and to the UI queue.
    .DESCRIPTION
        File: <root>\logs\AAAA-MM-DD.log, UTF-8. Writes are serialized with a named mutex
        because tweaks run in several runspaces at once.
    .EXAMPLE
        Write-UTLog -Level Sucesso -TweakId UT_GameDVR_Off -Message "Aplicado" -Antes 1 -Depois 0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Debug', 'Info', 'Sucesso', 'Aviso', 'Erro')]
        [string]$Level = 'Info',

        [string]$TweakId,

        [AllowNull()]
        [object]$Antes,

        [AllowNull()]
        [object]$Depois,

        # Technical detail that goes to the file only, never to the console/UI.
        [string]$Detalhe
    )

    $now = Get-Date
    $levelTag = $Level.ToUpperInvariant().PadRight(7)
    $line = '{0} [{1}]' -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $levelTag
    if ($TweakId) { $line += " [$TweakId]" }
    $line += " $Message"
    if ($PSBoundParameters.ContainsKey('Antes') -or $PSBoundParameters.ContainsKey('Depois')) {
        $line += ' | antes={0} depois={1}' -f (ConvertTo-UTLogValue $Antes), (ConvertTo-UTLogValue $Depois)
    }
    $fileLine = $line
    if ($Detalhe) { $fileLine += " | detalhe: $Detalhe" }

    $entry = [pscustomobject]@{
        Data     = $now
        Nivel    = $Level
        TweakId  = $TweakId
        Mensagem = $Message
        Linha    = $line
    }

    # 1) File
    try {
        $logDir = Get-UTPath -Name Logs
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $logFile = Join-Path $logDir ($now.ToString('yyyy-MM-dd') + '.log')
        Add-UTLogLine -Path $logFile -Line $fileLine
    } catch {
        # A broken log must never stop a tweak. Last resort: tell the console.
        Write-Verbose "Falha ao gravar log: $($_.Exception.Message)"
    }

    # 2) UI queue (filled only when the interface is running)
    $queue = Get-UTSyncValue -Key 'LogQueue'
    if ($null -ne $queue) { $queue.Enqueue($entry) }

    # 3) Console
    $silent = Get-UTSyncValue -Key 'Silencioso'
    if (-not $silent -and ($Level -ne 'Debug' -or $VerbosePreference -eq 'Continue')) {
        $color = switch ($Level) {
            'Debug'   { 'DarkGray' }
            'Info'    { 'Gray' }
            'Sucesso' { 'Green' }
            'Aviso'   { 'Yellow' }
            'Erro'    { 'Red' }
        }
        Write-UTConsole -Text $line -Color $color
    }
}

function Write-UTConsole {
    <#
    .SYNOPSIS
        Colored console output. Isolated so tests can mock it and so the analyzer
        suppression lives in one place.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Ferramenta interativa: a saida colorida no console e intencional.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [ConsoleColor]$Color = 'Gray',
        [switch]$NoNewline
    )
    Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline
}

function ConvertTo-UTLogValue {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '<ausente>' }
    if ($Value -is [byte[]]) { return ('hex:' + (($Value | ForEach-Object { $_.ToString('X2') }) -join '')) }
    if ($Value -is [array]) { return ('[' + ($Value -join ', ') + ']') }
    return [string]$Value
}

function Add-UTLogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Line
    )

    $mutex = New-Object System.Threading.Mutex($false, 'Local\UpgradeTweaksLog')
    $owned = $false
    try {
        try {
            $owned = $mutex.WaitOne(5000)
        } catch [System.Threading.AbandonedMutexException] {
            # Another process died while holding it; the mutex is ours now.
            $owned = $true
        }
        # UTF-8 with BOM: the BOM is only written when the file is new (stream at position 0).
        $writer = New-Object System.IO.StreamWriter($Path, $true, (New-Object System.Text.UTF8Encoding($true)))
        try {
            $writer.WriteLine($Line)
        } finally {
            $writer.Dispose()
        }
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Remove-UTOldLog {
    <#
    .SYNOPSIS
        Deletes daily log files older than -Dias (default 30), judging by the date in the file name.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [ValidateRange(1, 3650)]
        [int]$Dias = 30,

        [datetime]$Hoje = (Get-Date)
    )

    $logDir = Get-UTPath -Name Logs
    if (-not (Test-Path -LiteralPath $logDir)) { return @() }

    $limit = $Hoje.Date.AddDays(-$Dias)
    $removed = @()
    foreach ($file in Get-ChildItem -LiteralPath $logDir -Filter '*.log' -File) {
        $fileDate = [datetime]::MinValue
        $isDaily = [datetime]::TryParseExact($file.BaseName, 'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$fileDate)
        if ($isDaily -and $fileDate -lt $limit) {
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Remover log antigo')) {
                Remove-Item -LiteralPath $file.FullName -Force
                $removed += $file.FullName
            }
        }
    }
    return $removed
}
