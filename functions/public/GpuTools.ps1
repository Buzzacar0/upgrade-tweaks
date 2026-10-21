# GPU tab tools for every vendor: shader cache cleanup, official driver pages
# (config\gpu-guia.json) and the guided "NVIDIA driver only" install.

#region Shader cache
function Get-UTShaderCacheLocation {
    <#
    .SYNOPSIS
        Driver/Windows shader caches with their size. Nothing of the game itself is listed.
    #>
    [CmdletBinding()]
    param()
    $local = $env:LOCALAPPDATA
    $known = @(
        @{ Nome = 'NVIDIA DirectX (DXCache)'; Caminho = "$local\NVIDIA\DXCache"; Fabricante = 'nvidia' }
        @{ Nome = 'NVIDIA OpenGL/Vulkan (GLCache)'; Caminho = "$local\NVIDIA\GLCache"; Fabricante = 'nvidia' }
        @{ Nome = 'AMD DirectX (DxCache)'; Caminho = "$local\AMD\DxCache"; Fabricante = 'amd' }
        @{ Nome = 'AMD DirectX 12 (DxcCache)'; Caminho = "$local\AMD\DxcCache"; Fabricante = 'amd' }
        @{ Nome = 'AMD Vulkan (VkCache)'; Caminho = "$local\AMD\VkCache"; Fabricante = 'amd' }
        @{ Nome = 'Intel (ShaderCache)'; Caminho = "$local\Intel\ShaderCache"; Fabricante = 'intel' }
        @{ Nome = 'Windows DirectX (D3DSCache)'; Caminho = "$local\D3DSCache"; Fabricante = 'windows' }
    )
    foreach ($k in $known) {
        if (-not (Test-Path -LiteralPath $k.Caminho)) { continue }
        $bytes = Get-UTSum @(Get-ChildItem -LiteralPath $k.Caminho -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Length })
        [pscustomobject]@{ Nome = $k.Nome; Caminho = $k.Caminho; Fabricante = $k.Fabricante; TamanhoMB = [math]::Round([double]$bytes / 1MB, 1) }
    }
}

function Clear-UTShaderCache {
    <#
    .SYNOPSIS
        Deletes the contents of the selected shader caches (files in use are skipped) and returns
        how many MB were freed. The game recompiles shaders the next time it opens (first match
        may stutter or take longer to load).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string[]]$Caminho)
    $locations = @(Get-UTShaderCacheLocation)
    if ($Caminho) { $locations = @($locations | Where-Object { $Caminho -contains $_.Caminho }) }
    $freed = 0.0
    foreach ($loc in $locations) {
        if (-not $PSCmdlet.ShouldProcess($loc.Caminho, 'Apagar cache de shaders')) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $loc.Caminho -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $size = $f.Length
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $size } catch { Write-Verbose "Em uso: $($f.FullName)" }
        }
    }
    $mb = [math]::Round($freed / 1MB, 1)
    Write-UTLog -Level Sucesso -Message "Cache de shaders limpo: $mb MB liberados. O jogo vai recompilar os shaders na próxima abertura."
    return $mb
}
#endregion

#region Drivers and guides
function Open-UTDriverDownload {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('nvidia', 'amd', 'intel')][string]$Fabricante)
    $url = (Get-UTConfig -Name 'gpu-guia').links[$Fabricante]
    if ($PSCmdlet.ShouldProcess($url, 'Abrir a página oficial de drivers')) { Start-Process $url }
}

#endregion

#region NVIDIA driver only (no NVIDIA App, telemetry, HD Audio...)
function Get-UT7ZipPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    foreach ($p in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Expand-UTNvidiaDriverPackage {
    <#
    .SYNOPSIS
        Extracts the official NVIDIA driver installer (.exe) with 7-Zip.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Instalador,
        [Parameter(Mandatory)][string]$Destino
    )
    if (-not (Test-Path -LiteralPath $Instalador)) { throw "Instalador não encontrado: $Instalador" }
    $sevenZip = Get-UT7ZipPath
    if (-not $sevenZip) { throw 'O 7-Zip não está instalado. Instale pela aba Programas e tente de novo.' }
    if (-not $PSCmdlet.ShouldProcess($Instalador, "Extrair para $Destino")) { return $Destino }
    $r = Invoke-UTNative -FilePath $sevenZip -ArgumentList @('x', '-y', "-o$Destino", $Instalador) -TimeoutSeconds 900
    if ($r.CodigoSaida -ne 0) { throw "O 7-Zip não conseguiu extrair o driver (código $($r.CodigoSaida))." }
    return $Destino
}

function Optimize-UTNvidiaDriverPackage {
    <#
    .SYNOPSIS
        Keeps only the display driver in an extracted NVIDIA package: Display.Driver, NVI2 (the
        installer core) and, if asked, HD Audio (sound through HDMI/DisplayPort) and PhysX. Also
        removes from setup.cfg the EULA/consent pages that would point to deleted files.
        Returns the removed folders.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Pasta,
        [switch]$ManterHdAudio,
        [switch]$ManterPhysX
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Pasta 'setup.exe')) -or -not (Test-Path -LiteralPath (Join-Path $Pasta 'Display.Driver'))) {
        throw 'A pasta não parece um driver NVIDIA extraído (setup.exe e Display.Driver não encontrados).'
    }
    $keep = @('Display.Driver', 'NVI2')
    if ($ManterHdAudio) { $keep += 'HDAudio' }
    if ($ManterPhysX) { $keep += 'PhysX' }
    $removed = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @(Get-ChildItem -LiteralPath $Pasta -Directory)) {
        if ($keep -contains $dir.Name) { continue }
        if ($PSCmdlet.ShouldProcess($dir.FullName, 'Remover componente opcional')) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force
            $removed.Add($dir.Name)
        }
    }
    $cfg = Join-Path $Pasta 'setup.cfg'
    if ((Test-Path -LiteralPath $cfg) -and $PSCmdlet.ShouldProcess($cfg, 'Remover referências a EULA/consentimento')) {
        $lines = @(Get-Content -LiteralPath $cfg -Encoding UTF8 | Where-Object { $_ -notmatch '\$\{\{(EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile)\}\}' })
        Set-Content -LiteralPath $cfg -Value $lines -Encoding UTF8
    }
    return $removed.ToArray()
}

function Install-UTNvidiaDriverOnly {
    <#
    .SYNOPSIS
        Runs the reduced package silently. -InstalacaoLimpa resets the NVIDIA settings (like the
        "clean install" box of the official installer).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Pasta,
        [switch]$InstalacaoLimpa
    )
    Assert-UTAdmin
    $setup = Join-Path $Pasta 'setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) { throw "setup.exe não encontrado em $Pasta" }
    $arguments = @('-s', '-noreboot', '-noeula', '-nofinish', '-passive')
    if ($InstalacaoLimpa) { $arguments += '-clean' }
    if (-not $PSCmdlet.ShouldProcess($setup, ('Instalar só o driver de vídeo ' + ($arguments -join ' ')))) { return $null }
    [void](Invoke-UTPreApplySafety)
    $r = Invoke-UTNative -FilePath $setup -ArgumentList $arguments -TimeoutSeconds 1800
    Write-UTLog -Level $(if ($r.CodigoSaida -eq 0) { 'Sucesso' } else { 'Aviso' }) -Message "Instalador NVIDIA terminou com código $($r.CodigoSaida). Reinicie o PC."
    return $r.CodigoSaida
}
#endregion
