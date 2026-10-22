# BIOS tab: board and firmware info, restart straight into the BIOS, NVRAM backup/restore and the
# settings editor. The editor needs a map of the board's BIOS, built once from the official BIOS
# file of the manufacturer with two open-source tools (UEFIExtract and IFRExtractor-RS, LongSoft).
# Nothing here flashes the BIOS: only setting values inside the existing NVRAM variables change.

#region Info and restart
function Get-UTBiosInfo {
    <#
    .SYNOPSIS
        Board, BIOS (vendor, version, date), boot mode and Secure Boot.
    #>
    [CmdletBinding()]
    param()
    $board = (@(Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue) | Select-Object -First 1)
    $bios = (@(Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue) | Select-Object -First 1)
    $uefi = $false
    try { $uefi = Test-UTUefiFirmware } catch { $uefi = $false }
    $secure = $null
    if ($uefi) { try { $secure = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $secure = $null } }
    $date = $null
    if ($bios -and $bios.ReleaseDate) { $date = ([datetime]$bios.ReleaseDate).ToString('dd/MM/yyyy') }
    return [pscustomobject]@{
        Fabricante  = $(if ($board) { ([string]$board.Manufacturer).Trim() } else { '' })
        Placa       = $(if ($board) { ([string]$board.Product).Trim() } else { '' })
        BiosMarca   = $(if ($bios) { ([string]$bios.Manufacturer).Trim() } else { '' })
        BiosVersao  = $(if ($bios) { ([string]$bios.SMBIOSBIOSVersion).Trim() } else { '' })
        BiosData    = $date
        Uefi        = $uefi
        SecureBoot  = $secure
    }
}

function Restart-UTFirmwareSetup {
    <#
    .SYNOPSIS
        Restarts the PC straight into the BIOS/UEFI setup (shutdown /r /fw), no key to press.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([int]$Segundos = 5)
    Assert-UTAdmin
    if (-not (Test-UTUefiFirmware)) { throw 'Só funciona com o Windows em modo UEFI. Em modo Legacy, aperte Del/F2 ao ligar o PC.' }
    if (-not $PSCmdlet.ShouldProcess('PC', 'Reiniciar direto na BIOS')) { return }
    Write-UTLog -Level Info -Message "Reiniciando direto na BIOS em $Segundos segundos."
    $r = Invoke-UTNative -FilePath 'shutdown.exe' -ArgumentList @('/r', '/fw', '/t', [string]$Segundos)
    if ($r.CodigoSaida -ne 0) { throw "O Windows não aceitou reiniciar na BIOS: $($r.Saida) $($r.Erro)".Trim() }
}
#endregion

#region NVRAM backup
function Get-UTNvramBackupRoot {
    return (Join-Path (Get-UTPath -Name Backups) 'nvram')
}

function Backup-UTNvram {
    <#
    .SYNOPSIS
        Copies every readable NVRAM variable to backups\nvram\AAAA-MM-DD_HHmmss (one .bin per
        variable + manifesto.json). Only reads the firmware.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Motivo = 'manual')
    $vars = @(Get-UTUefiVariableList)
    $folder = Join-Path (Get-UTNvramBackupRoot) (Get-Date -Format 'yyyy-MM-dd_HHmmss')
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $saved = New-Object System.Collections.Generic.List[object]
    foreach ($v in $vars) {
        $data = Read-UTUefiVariable -Nome $v.Nome -Guid $v.Guid
        if ($null -eq $data) { continue }
        $file = '{0}_{1}.bin' -f (ConvertTo-UTSafeFileName $v.Nome), $v.Guid
        [IO.File]::WriteAllBytes((Join-Path $folder $file), $data.Dados)
        $saved.Add([ordered]@{ Nome = $v.Nome; Guid = $v.Guid; Atributos = $data.Atributos; Tamanho = $data.Dados.Length; Arquivo = $file })
    }
    $info = Get-UTBiosInfo
    Write-UTJsonFile -Path (Join-Path $folder 'manifesto.json') -InputObject ([ordered]@{
            Criado = (Get-Date).ToString('s'); Motivo = $Motivo; Placa = $info.Placa; Bios = $info.BiosVersao; Variaveis = $saved.ToArray()
        }) -Confirm:$false
    Write-UTLog -Level Sucesso -Message "Backup da NVRAM: $($saved.Count) variáveis em $folder."
    return $folder
}

function Get-UTNvramBackup {
    <#
    .SYNOPSIS
        NVRAM backups, newest first.
    #>
    [CmdletBinding()]
    param()
    $root = Get-UTNvramBackupRoot
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending)) {
        $m = Read-UTJsonFile -Path (Join-Path $d.FullName 'manifesto.json')
        if ($null -eq $m) { continue }
        [pscustomobject]@{ Pasta = $d.FullName; Criado = [string]$m.Criado; Motivo = [string]$m.Motivo; Bios = [string]$m.Bios; Variaveis = @($m.Variaveis).Count }
    }
}

function Restore-UTNvramBackup {
    <#
    .SYNOPSIS
        Writes back, from a backup, the BIOS settings variables that changed since then.
    .DESCRIPTION
        Only variables that hold BIOS settings in the current map (Setup, AmdSetup..., CbsSetup...)
        are restored, and only when the size is the same. Secure Boot keys, boot entries and
        anything else in the backup are never written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Pasta)
    Assert-UTAdmin
    $m = Read-UTJsonFile -Path (Join-Path $Pasta 'manifesto.json')
    if ($null -eq $m) { throw 'Esta pasta não é um backup da NVRAM do Upgrade Tweaks.' }
    $map = Get-UTBiosMap
    if ($null -eq $map) { throw 'Crie o mapa da BIOS antes de restaurar (o mapa diz quais variáveis guardam as opções da BIOS).' }
    $allowed = @{}
    foreach ($s in @($map.VarStores)) { $allowed["$($s.Nome)|$($s.Guid)"] = $true }
    $restored = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($m.Variaveis)) {
        $key = "$($v.Nome)|$($v.Guid)"
        if (-not $allowed.ContainsKey($key)) { continue }
        $old = [IO.File]::ReadAllBytes((Join-Path $Pasta $v.Arquivo))
        $now = Read-UTUefiVariable -Nome $v.Nome -Guid $v.Guid
        if ($null -eq $now -or $now.Dados.Length -ne $old.Length) { continue }
        if ([Convert]::ToBase64String($now.Dados) -eq [Convert]::ToBase64String($old)) { continue }
        if ($PSCmdlet.ShouldProcess("NVRAM: $($v.Nome)", 'Restaurar do backup')) {
            Write-UTUefiVariable -Nome $v.Nome -Guid $v.Guid -Dados $old -Confirm:$false
            $restored.Add([string]$v.Nome)
        }
    }
    if ($restored.Count -gt 0) { Write-UTLog -Level Sucesso -Message "NVRAM restaurada do backup ($($restored -join ', ')). Reinicie o PC." }
    return $restored.ToArray()
}
#endregion

#region Map tools
function Get-UTBiosMapToolPath {
    <#
    .SYNOPSIS
        UEFIExtract.exe and ifrextractor.exe in the tools folder ($null for a missing one).
    #>
    [CmdletBinding()]
    param()
    $dir = Join-Path (Get-UTPath -Name Tools) 'bios-mapa'
    $find = { param($n) (@(Get-ChildItem -LiteralPath $dir -Filter $n -File -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1) }
    $ue = $null; $ifr = $null
    if (Test-Path -LiteralPath $dir) {
        $a = & $find 'UEFIExtract.exe'; if ($a) { $ue = $a.FullName }
        $b = & $find 'ifrextractor.exe'; if ($b) { $ifr = $b.FullName }
    }
    return [pscustomobject]@{ Pasta = $dir; UEFIExtract = $ue; IfrExtractor = $ifr }
}

function Install-UTBiosMapTool {
    <#
    .SYNOPSIS
        Downloads UEFIExtract (LongSoft/UEFITool) and IFRExtractor-RS from their GitHub releases.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $paths = Get-UTBiosMapToolPath
    if ($paths.UEFIExtract -and $paths.IfrExtractor) { return $paths }
    if (-not $PSCmdlet.ShouldProcess('UEFIExtract e IFRExtractor (GitHub, LongSoft)', 'Baixar')) { return $paths }
    $wanted = @(
        @{ Repo = 'LongSoft/UEFITool'; Padrao = '^UEFIExtract_NE_.*_win64\.zip$'; Pasta = 'uefiextract' },
        @{ Repo = 'LongSoft/IFRExtractor-RS'; Padrao = '^ifrextractor_.*_windows\.zip$'; Pasta = 'ifrextractor' }
    )
    foreach ($w in $wanted) {
        $rel = Get-UTGitHubLatestRelease -Repo $w.Repo
        $asset = (@($rel.Arquivos | Where-Object { $_.Nome -match $w.Padrao }) | Select-Object -First 1)
        if (-not $asset) { throw "Não encontrei o arquivo para Windows na última versão de $($w.Repo)." }
        $zip = Join-Path (Get-UTPath -Name Temp) $asset.Nome
        [void](Save-UTDownload -Url $asset.Url -Destino $zip -Confirm:$false)
        $target = Join-Path $paths.Pasta $w.Pasta
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Write-UTLog -Level Info -Message "Baixado: $($asset.Nome) ($($w.Repo) $($rel.Versao))."
    }
    return (Get-UTBiosMapToolPath)
}

function Get-UTBiosImageFile {
    <#
    .SYNOPSIS
        The BIOS image inside what the user picked: the file itself, or the biggest file inside a
        .zip from the manufacturer (the other files are the flasher and its notes).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Arquivo, [Parameter(Mandatory)][string]$Trabalho)
    if (-not (Test-Path -LiteralPath $Arquivo)) { throw "Arquivo não encontrado: $Arquivo" }
    $target = Join-Path $Trabalho 'b.bin'
    if ([IO.Path]::GetExtension($Arquivo) -eq '.zip') {
        $x = Join-Path $Trabalho 'zip'
        Expand-Archive -LiteralPath $Arquivo -DestinationPath $x -Force
        $big = (@(Get-ChildItem -LiteralPath $x -File -Recurse | Sort-Object Length -Descending) | Select-Object -First 1)
        if (-not $big) { throw 'O .zip está vazio.' }
        Copy-Item -LiteralPath $big.FullName -Destination $target -Force
    } else {
        Copy-Item -LiteralPath $Arquivo -Destination $target -Force
    }
    if ((Get-Item -LiteralPath $target).Length -lt 4MB) { throw 'Este arquivo é pequeno demais para ser uma BIOS. Escolha o arquivo baixado do site do fabricante da placa-mãe.' }
    return $target
}
#endregion

#region Map
function Get-UTBiosMapPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $info = Get-UTBiosInfo
    $name = ConvertTo-UTSafeFileName ("{0}_{1}" -f $info.Placa, $info.BiosVersao)
    return (Join-Path (Join-Path (Get-UTPath -Name State) 'bios') "$name.json")
}

function New-UTBiosMap {
    <#
    .SYNOPSIS
        Builds the settings map of this PC's BIOS from the manufacturer's BIOS file.
    .DESCRIPTION
        UEFIExtract unpacks the image (flat "unpack" mode: deep folder trees break the 260
        character path limit), IFRExtractor-RS turns the forms of the setup modules into text and
        ConvertFrom-UTIfrText reads it. The map is checked against the NVRAM of this PC: a
        variable whose size differs means the file is of another BIOS version.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ArquivoBios)
    if (-not $PSCmdlet.ShouldProcess($ArquivoBios, 'Criar o mapa da BIOS')) { return }
    $tools = Install-UTBiosMapTool -Confirm:$false
    if (-not $tools.UEFIExtract -or -not $tools.IfrExtractor) { throw 'As ferramentas do mapa da BIOS não foram baixadas.' }
    $work = Join-Path (Get-UTPath -Name Temp) ('bm' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        $image = Get-UTBiosImageFile -Arquivo $ArquivoBios -Trabalho $work
        $hash = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
        $r = Invoke-UTNative -FilePath $tools.UEFIExtract -ArgumentList @($image, 'unpack') -TimeoutSeconds 900
        $dump = "$image.dump"
        if (-not (Test-Path -LiteralPath $dump)) { throw "O UEFIExtract não conseguiu abrir este arquivo de BIOS. $($r.Saida)".Trim() }
        $pe = @(Get-ChildItem -LiteralPath $dump -File -Filter 'Section_PE32_image_*_body.bin')
        $candidates = @($pe | Where-Object { $_.Name -match '(?i)setup|cbs|pbs|dynamic|screen|page|hii|form' })
        if ($candidates.Count -eq 0) { $candidates = @($pe | Where-Object { $_.Length -gt 20KB }) }
        $ifrDir = Join-Path $work 'ifr'
        New-Item -ItemType Directory -Force -Path $ifrDir | Out-Null

        $stores = New-Object System.Collections.Generic.List[object]
        $questions = New-Object System.Collections.Generic.List[object]
        $seen = @{}
        foreach ($c in $candidates) {
            $module = ([regex]::Match($c.Name, '^Section_PE32_image_[0-9A-Fa-f-]{36}_(?<n>.+)_body\.bin$')).Groups['n'].Value
            if (-not $module) { $module = $c.BaseName }
            $copy = Join-Path $ifrDir ((ConvertTo-UTSafeFileName $module) + '.bin')
            if (Test-Path -LiteralPath $copy) { continue }
            Copy-Item -LiteralPath $c.FullName -Destination $copy
            [void](Invoke-UTNative -FilePath $tools.IfrExtractor -ArgumentList @($copy) -TimeoutSeconds 120)
            foreach ($txt in @(Get-ChildItem -LiteralPath $ifrDir -Filter ((Split-Path -Leaf $copy) + '.*.ifr.txt') -File)) {
                $parsed = ConvertFrom-UTIfrText -Linhas ([IO.File]::ReadAllLines($txt.FullName)) -Modulo $module
                $prefix = "$module/$($txt.Name.Split('.')[2])"
                $byId = @{}
                foreach ($s in $parsed.VarStores) {
                    # EFI global variables (boot order, language, timeout) are not BIOS settings.
                    if ($s.Guid -eq '8BE4DF61-93CA-11D2-AA0D-00E098032B8C') { continue }
                    $byId["$($s.Formset)|$($s.Id)"] = $s
                    $key = "$($s.Nome)|$($s.Guid)"
                    if ($s.Nome -and -not $seen.ContainsKey("vs:$key")) {
                        $seen["vs:$key"] = $true
                        $stores.Add([ordered]@{ Nome = $s.Nome; Guid = $s.Guid; Tamanho = $s.Tamanho; Atributos = $s.Atributos })
                    }
                }
                foreach ($q in $parsed.Perguntas) {
                    $s = $byId["$($q.Formset)|$($q.VarStoreId)"]
                    if ($null -eq $s -or -not $s.Nome) { continue }
                    $formsetKey = "$prefix#$($q.Formset)"
                    $qKey = '{0}:0x{1:X}' -f $formsetKey, $q.Qid
                    if ($seen.ContainsKey($qKey)) { continue }
                    $seen[$qKey] = $true
                    $questions.Add([ordered]@{
                            Chave = $qKey; Formset = $formsetKey; Qid = $q.Qid; Modulo = $q.Modulo; Menu = $q.Menu; Formulario = $q.Formulario
                            Nome = $q.Nome; Ajuda = $q.Ajuda; Tipo = $q.Tipo; Var = $s.Nome; Guid = $s.Guid; Offset = $q.Offset; Bits = $q.Bits
                            Min = $q.Min; Max = $q.Max; Passo = $q.Passo; Padrao = $q.Padrao
                            Opcoes = @($q.Opcoes | ForEach-Object { [ordered]@{ Texto = $_.Texto; Valor = $_.Valor } })
                            Condicoes = @($q.Condicoes | ForEach-Object { [ordered]@{ Tipo = $_.Tipo; Expr = @($_.Expr) } })
                        })
                }
            }
        }
        if ($questions.Count -eq 0) { throw 'Nenhuma opção de BIOS foi encontrada neste arquivo. Confira se é a BIOS da sua placa-mãe.' }

        $info = Get-UTBiosInfo
        $check = @(Test-UTBiosMapNvram -VarStores $stores.ToArray())
        $map = [ordered]@{
            Versao = 1; Criado = (Get-Date).ToString('s'); Placa = $info.Placa; Fabricante = $info.Fabricante; Bios = $info.BiosVersao
            ArquivoBios = (Split-Path -Leaf $ArquivoBios); Sha256 = $hash
            VarStores = $stores.ToArray(); Perguntas = $questions.ToArray()
        }
        $path = Get-UTBiosMapPath
        Write-UTJsonFile -Path $path -InputObject $map -Depth 8 -Confirm:$false
        $UTSync['BiosMapa'] = $null
        $wrong = @($check | Where-Object { $_.Estado -eq 'TamanhoDiferente' })
        Write-UTLog -Level Sucesso -Message "Mapa da BIOS criado: $($questions.Count) opções em $($stores.Count) variáveis." -Detalhe $path
        return [pscustomobject]@{
            Arquivo = $path; Opcoes = $questions.Count; Variaveis = $stores.Count
            Acessiveis = @($check | Where-Object { $_.Estado -eq 'OK' }).Count
            VersaoDiferente = ($wrong.Count -gt 0); VariaveisDiferentes = @($wrong | ForEach-Object { $_.Nome })
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-UTBiosMapNvram {
    <#
    .SYNOPSIS
        For each variable of the map: OK (readable, same size), SomenteNaBios (no runtime access)
        or TamanhoDiferente (the map is of another BIOS version).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$VarStores)
    foreach ($s in $VarStores) {
        $v = $null
        try { $v = Read-UTUefiVariable -Nome ([string]$s.Nome) -Guid ([string]$s.Guid) } catch { $v = $null }
        $state = 'SomenteNaBios'
        if ($null -ne $v) { $state = $(if ($v.Dados.Length -eq [int]$s.Tamanho) { 'OK' } else { 'TamanhoDiferente' }) }
        # Set after creating the object: $( ) would unroll a 1-byte array into a single byte.
        $o = [pscustomobject]@{ Nome = [string]$s.Nome; Guid = [string]$s.Guid; Estado = $state; Dados = $null; Atributos = $null }
        if ($null -ne $v) { $o.Dados = [byte[]]$v.Dados; $o.Atributos = $v.Atributos }
        $o
    }
}

function Get-UTBiosMap {
    <#
    .SYNOPSIS
        The map of this PC's BIOS (cached in the session), or $null when it was not created yet.
    #>
    [CmdletBinding()]
    param()
    $cached = Get-UTSyncValue -Key 'BiosMapa'
    $path = Get-UTBiosMapPath
    if ($cached -and $cached.Caminho -eq $path) { return $cached.Mapa }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    # A map has thousands of questions: the .NET serializer reads it in a fraction of a second,
    # Read-UTJsonFile (recursive conversion to hashtables) would take several seconds.
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $map = $serializer.DeserializeObject([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8))
    if ($null -eq $map) { return $null }
    $UTSync['BiosMapa'] = @{ Caminho = $path; Mapa = $map }
    return $map
}

function Get-UTAmdBiosFamily {
    <#
    .SYNOPSIS
        Suffix of the AMD setup modules that apply to this processor. AM5 BIOSes carry the menus
        of several families (CbsSetupDxeRPL, ...PHX, ...STX, GbtCrbCbsKRK); only the one of the
        installed CPU is used. $null when the CPU is not AMD or the family is unknown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Identificador)
    if (-not $Identificador) {
        $Identificador = [string](Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name Identifier -ErrorAction SilentlyContinue).Identifier
        $vendor = [string](Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name VendorIdentifier -ErrorAction SilentlyContinue).VendorIdentifier
        if ($vendor -ne 'AuthenticAMD') { return $null }
    }
    $m = [regex]::Match($Identificador, 'Family (\d+) Model (\d+)')
    if (-not $m.Success) { return $null }
    $family = [int]$m.Groups[1].Value
    $model = [int]$m.Groups[2].Value
    if ($family -eq 25 -and $model -ge 0x60 -and $model -le 0x6F) { return 'RPL' }   # Ryzen 7000 (Raphael)
    if ($family -eq 25 -and $model -ge 0x70 -and $model -le 0x7F) { return 'PHX' }   # Ryzen 8000G (Phoenix)
    if ($family -eq 26 -and $model -ge 0x40 -and $model -le 0x4F) { return 'RPL' }   # Ryzen 9000 (Granite Ridge) uses the Raphael menus
    if ($family -eq 26 -and $model -ge 0x20 -and $model -le 0x2F) { return 'STX' }   # Strix Point
    if ($family -eq 26 -and $model -ge 0x60 -and $model -le 0x6F) { return 'KRK' }   # Krackan Point
    return $null
}

function Test-UTBiosModuleActive {
    # $false for setup modules of another AMD family (see Get-UTAmdBiosFamily).
    param([string]$Modulo, [AllowNull()][string]$Familia)
    if (-not $Familia) { return $true }
    $m = [regex]::Match($Modulo, '(?i)(RPL|PHX|STX|KRK)$')
    if (-not $m.Success) { return $true }
    return ($m.Groups[1].Value.ToUpperInvariant() -eq $Familia)
}

function Get-UTBiosCheck {
    <#
    .SYNOPSIS
        What Windows itself sees of a few BIOS settings, to confirm what the NVRAM says.
    #>
    [CmdletBinding()]
    param()
    $r = @{}
    try {
        $cpu = (@(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop) | Select-Object -First 1)
        $hv = [bool]((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).HypervisorPresent)
        $r['virtualizacao'] = ([bool]$cpu.VirtualizationFirmwareEnabled -or $hv)
    } catch { $null = $_ }
    try { $r['legacy'] = -not (Test-UTUefiFirmware) } catch { $null = $_ }
    try { $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop; $r['tpm'] = [bool]$tpm } catch { $r['tpm'] = $false }
    try { $rb = Get-UTResizableBarStatus; if ($null -ne $rb -and $null -ne $rb.Ligado) { $r['rebar'] = [bool]$rb.Ligado } } catch { $null = $_ }
    return $r
}

function Get-UTBiosSetting {
    <#
    .SYNOPSIS
        Settings of the map with their current NVRAM value and visibility.
    .DESCRIPTION
        Visivel = not hidden by a SuppressIf evaluated with the current values (what the BIOS
        itself would show). Bloqueada = grayed out. Editavel = the variable is readable from
        Windows and has the same size as in the map. -Destaque keeps only the settings listed in
        bios-ajustes.json, with the Portuguese title and explanation.
    #>
    [CmdletBinding()]
    param([switch]$Destaque, [switch]$IncluirOcultas)
    $map = Get-UTBiosMap
    if ($null -eq $map) { throw 'O mapa da BIOS ainda não foi criado.' }
    $vars = @{}
    foreach ($t in @(Test-UTBiosMapNvram -VarStores @($map.VarStores))) { $vars["$($t.Nome)|$($t.Guid)"] = $t }
    $family = Get-UTAmdBiosFamily
    $active = @{}
    foreach ($q in @($map.Perguntas)) {
        $m = [string]$q.Modulo
        if (-not $active.ContainsKey($m)) { $active[$m] = Test-UTBiosModuleActive -Modulo $m -Familia $family }
    }
    # Current value of every question, per formset (question ids are only unique inside one).
    # Hidden questions (empty name) count too: the conditions of the others read them.
    $values = @{}
    foreach ($q in @($map.Perguntas)) {
        if (-not $active[[string]$q.Modulo]) { continue }
        $table = $values[$q.Formset]
        if ($null -eq $table) { $table = @{}; $values[$q.Formset] = $table }
        $rv = $vars["$($q.Var)|$($q.Guid)"]
        if ($null -eq $rv -or $rv.Estado -ne 'OK') { continue }
        $off = [int]$q.Offset
        if ([int]$q.Bits -eq 8 -and $off -lt $rv.Dados.Length) { $table[[int]$q.Qid] = [uint64]$rv.Dados[$off] }
        else { $table[[int]$q.Qid] = Get-UTBiosBytesValue -Dados $rv.Dados -Offset $off -Bits ([int]$q.Bits) }
    }
    $curated = @()
    $cpuVendor = $null
    $anyCurated = $null
    if ($Destaque) {
        $hw = Get-UTSyncValue -Key 'Hardware'
        if ($hw) { $cpuVendor = $hw.CpuFabricante } else { try { $cpuVendor = (Get-UTCpuInfo).Fabricante } catch { $cpuVendor = $null } }
        $curated = @((Get-UTConfig -Name 'bios-ajustes').itens | Where-Object { @($_.cpu).Count -eq 0 -or -not $cpuVendor -or @($_.cpu) -contains $cpuVendor })
        $anyCurated = New-Object regex ((@($curated | ForEach-Object { '(?:' + $_.padrao + ')' }) -join '|'))
    }
    $checks = $(if ($Destaque) { Get-UTBiosCheck } else { @{} })
    $shown = @{}

    foreach ($q in @($map.Perguntas)) {
        if (-not $q.Nome) { continue }
        if (-not $active[[string]$q.Modulo]) { continue }
        $item = $null
        if ($Destaque) {
            if (-not $anyCurated.IsMatch([string]$q.Nome)) { continue }
            $item = (@($curated | Where-Object { $q.Nome -match $_.padrao }) | Select-Object -First 1)
            if (-not $item) { continue }
        }
        $var = $vars["$($q.Var)|$($q.Guid)"]
        $table = $values[$q.Formset]
        $value = $null
        if ($table.ContainsKey([int]$q.Qid)) { $value = $table[[int]$q.Qid] }
        $hidden = $false; $grayed = $false; $unknown = $false
        foreach ($c in @($q.Condicoes)) {
            $res = Test-UTIfrExpression -Expr @($c.Expr) -Valores $table
            if ($null -eq $res) { $unknown = $true; continue }
            if ($res -and $c.Tipo -eq 'SuppressIf') { $hidden = $true }
            if ($res -and $c.Tipo -in 'GrayOutIf', 'DisableIf') { $grayed = $true }
        }
        if ($hidden -and -not $IncluirOcultas) { continue }
        # The same byte often appears on more than one screen; list it once.
        $where = "$($q.Var)|$($q.Guid)|$($q.Offset)|$($q.Bits)"
        if ($shown.ContainsKey($where)) { continue }
        $shown[$where] = $true
        $optionText = {
            param($v)
            foreach ($o in @($q.Opcoes)) { if ([uint64]$o.Valor -eq [uint64]$v) { return [string]$o.Texto } }
            if ($null -ne $v) { return [string]$v }
            return ''
        }
        $state = $(if ($null -eq $var) { 'SomenteNaBios' } else { $var.Estado })
        $confirm = $null
        if ($item -and $item.verificacao -and $checks.ContainsKey([string]$item.verificacao)) { $confirm = $checks[[string]$item.verificacao] }
        $valueText = $(if ($null -ne $value) { & $optionText $value } else { '' })
        # Boards keep copies of some settings; the copy the firmware really uses agrees with Windows.
        $diverges = (($confirm -eq $true -and $valueText -match '^(Disabled?|Off)$') -or ($confirm -eq $false -and $valueText -match '^(Enabled?|On)$'))
        [pscustomobject]@{
            Chave       = [string]$q.Chave
            Nome        = [string]$q.Nome
            Titulo      = $(if ($item) { [string]$item.titulo } else { [string]$q.Nome })
            Explicacao  = $(if ($item) { [string]$item.texto } else { [string]$q.Ajuda })
            Grupo       = $(if ($item) { [string]$item.grupo } else { [string]$q.Formulario })
            Recomendado = $(if ($item) { [string]$item.recomendado } else { '' })
            Local       = (@($q.Menu, $q.Formulario) | Where-Object { $_ }) -join ' > '
            Modulo      = [string]$q.Modulo
            Tipo        = [string]$q.Tipo
            Variavel    = [string]$q.Var
            Offset      = [int]$q.Offset
            Valor       = $value
            ValorTexto  = $valueText
            Padrao      = $q.Padrao
            PadraoTexto = $(if ($null -ne $q.Padrao) { & $optionText $q.Padrao } else { '' })
            Opcoes      = @($q.Opcoes)
            Min         = $q.Min
            Max         = $q.Max
            Passo       = $q.Passo
            Visivel     = (-not $hidden)
            Bloqueada   = $grayed
            CondicaoDesconhecida = $unknown
            Estado      = $state
            Editavel    = ($state -eq 'OK')
            WindowsConfirma = $confirm
            Divergente  = [bool]$diverges
        }
    }
}

function Set-UTBiosSetting {
    <#
    .SYNOPSIS
        Changes one BIOS setting in the NVRAM. Takes a full NVRAM backup first (once per
        session), writes only the bytes of that setting and reads them back. Takes effect on
        the next boot.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Chave,
        [Parameter(Mandatory)][uint64]$Valor
    )
    Assert-UTAdmin
    $map = Get-UTBiosMap
    if ($null -eq $map) { throw 'O mapa da BIOS ainda não foi criado.' }
    $q = (@($map.Perguntas | Where-Object { $_.Chave -eq $Chave }) | Select-Object -First 1)
    if ($null -eq $q) { throw "Opção da BIOS não encontrada no mapa: $Chave" }
    $options = @($q.Opcoes)
    if ($options.Count -gt 0) {
        if (-not (@($options | Where-Object { [uint64]$_.Valor -eq $Valor }).Count)) { throw "Valor $Valor não é uma das opções de '$($q.Nome)'." }
    } else {
        if ($null -ne $q.Min -and $Valor -lt [uint64]$q.Min) { throw "Valor abaixo do mínimo de '$($q.Nome)' ($($q.Min))." }
        if ($null -ne $q.Max -and $Valor -gt [uint64]$q.Max) { throw "Valor acima do máximo de '$($q.Nome)' ($($q.Max))." }
    }
    $mapStore = (@($map.VarStores | Where-Object { $_.Nome -eq $q.Var -and $_.Guid -eq $q.Guid }) | Select-Object -First 1)
    $current = Read-UTUefiVariable -Nome ([string]$q.Var) -Guid ([string]$q.Guid)
    if ($null -eq $current) { throw "'$($q.Nome)' fica numa variável que só existe durante o boot. Mude essa opção dentro da BIOS." }
    if ($mapStore -and $current.Dados.Length -ne [int]$mapStore.Tamanho) { throw 'O mapa é de outra versão da BIOS (o tamanho da variável não bate). Crie o mapa de novo com o arquivo da versão instalada.' }
    $old = Get-UTBiosBytesValue -Dados $current.Dados -Offset ([int]$q.Offset) -Bits ([int]$q.Bits)
    if ($old -eq $Valor) { return [pscustomobject]@{ Nome = $q.Nome; Antes = $old; Depois = $Valor; Alterado = $false; Backup = $null } }
    if (-not $PSCmdlet.ShouldProcess("BIOS: $($q.Nome)", "Mudar de $old para $Valor")) { return }

    $backup = Get-UTSyncValue -Key 'BiosBackupSessao'
    if (-not $backup) {
        $backup = Backup-UTNvram -Motivo "antes de mudar '$($q.Nome)'"
        $UTSync['BiosBackupSessao'] = $backup
    }
    $new = Set-UTBiosBytesValue -Dados $current.Dados -Offset ([int]$q.Offset) -Bits ([int]$q.Bits) -Valor $Valor
    Write-UTUefiVariable -Nome ([string]$q.Var) -Guid ([string]$q.Guid) -Dados $new -Confirm:$false
    Write-UTLog -Level Sucesso -Message "BIOS: '$($q.Nome)' mudou de $old para $Valor. Vale a partir do próximo boot." -Antes $old -Depois $Valor
    return [pscustomobject]@{ Nome = $q.Nome; Antes = $old; Depois = $Valor; Alterado = $true; Backup = $backup }
}
#endregion
