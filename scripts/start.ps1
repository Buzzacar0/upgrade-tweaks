<#
.SYNOPSIS
    Upgrade Tweaks - otimização de Windows focada em Call of Duty: Warzone.

.DESCRIPTION
    Sempre roda como administrador: sem privilégio elevado, reinicia sozinho pedindo o UAC
    (inclusive quando aberto com "irm ... | iex") e fecha a instância não elevada.

.PARAMETER Preset
    Aplica um preset sem abrir a interface: Seguro, Competitivo ou Extremo.

.PARAMETER Config
    Aplica uma seleção exportada (arquivo JSON) sem abrir a interface.

.PARAMETER Silencioso
    Não mostra o console colorido nem pede confirmação (para uso em scripts).

.PARAMETER DesfazerTudo
    Reverte tudo que o Upgrade Tweaks já aplicou, na ordem inversa.

.PARAMETER Diagnostico
    Só gera o diagnóstico de hardware e sai.

.PARAMETER ExportarRelatorio
    Caminho do relatório (TXT ou HTML) gerado junto com -Diagnostico.

.PARAMETER Simular
    Mostra tudo que seria feito, sem alterar nada.

.PARAMETER Galeria
    Abre a interface na Galeria de componentes (revisão visual do design system).

.PARAMETER Overlay
    Abre só o overlay de FPS (ícone ao lado do relógio), sem a janela principal.

.EXAMPLE
    irm https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1))) -Preset Seguro
#>
param(
    [ValidateSet('', 'Seguro', 'Competitivo', 'Extremo')]
    [string]$Preset = '',
    [string]$Config = '',
    [switch]$Silencioso,
    [switch]$DesfazerTudo,
    [switch]$Diagnostico,
    [string]$ExportarRelatorio = '',
    [switch]$Simular,
    [switch]$Galeria,
    [switch]$Overlay
)

$UTVersion = '#{versao}'
$UTBuild = '#{build}'
$UTReleaseUrl = 'https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1'

#region DEV-LOADER
# Removed by compile.ps1. When running straight from the repository, load every function file.
if ($UTBuild -like '#*') {
    $UTVersion = '0.1.0-dev'
    Set-StrictMode -Version Latest
    $UTRepoRoot = Split-Path -Parent $PSScriptRoot
    foreach ($UTFile in (Get-ChildItem -Path (Join-Path $UTRepoRoot 'functions') -Filter '*.ps1' -File -Recurse)) {
        . $UTFile.FullName
    }
    . (Join-Path $PSScriptRoot 'main.ps1')
}
#endregion DEV-LOADER

# Add-Type, WPF and the registry helpers need FullLanguage; AppLocker/WDAC can force ConstrainedLanguage.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host ("O PowerShell está em modo restrito ({0}), provavelmente por política da empresa (AppLocker/WDAC). " -f $ExecutionContext.SessionState.LanguageMode) -ForegroundColor Red
    Write-Host 'O Upgrade Tweaks não consegue funcionar assim. Nenhuma alteração foi feita.' -ForegroundColor Red
    if ($MyInvocation.MyCommand -is [System.Management.Automation.ExternalScriptInfo]) { exit 1 }
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Running from a .ps1 file, or from "irm | iex" / [scriptblock]::Create (no file on disk)?
$UTScriptPath = $null
if ($MyInvocation.MyCommand -is [System.Management.Automation.ExternalScriptInfo]) {
    $UTScriptPath = $MyInvocation.MyCommand.Path
}
$UTIsFileProcess = -not [string]::IsNullOrEmpty($UTScriptPath)
$UTHeadless = [bool]($Preset -or $Config -or $Silencioso -or $DesfazerTudo -or $Diagnostico)

#region Elevation (rule 1: never run without administrator)
if (-not (Test-UTAdmin) -or (Test-UTNeeds64BitRelaunch)) {
    $UTElevation = Invoke-UTElevation -ScriptPath $UTScriptPath -BoundParameters $PSBoundParameters `
        -ReleaseUrl $UTReleaseUrl -Wait:$UTHeadless
    $UTExitCode = 0
    if ($UTElevation.Iniciado) {
        if ($null -ne $UTElevation.CodigoSaida) { $UTExitCode = [int]$UTElevation.CodigoSaida }
        if (-not $UTHeadless) {
            Write-UTConsole -Text 'O Upgrade Tweaks foi aberto em uma nova janela como administrador.' -Color Green
        }
    } else {
        $UTExitCode = 1
        Write-UTConsole -Text $UTElevation.Mensagem -Color Red
        if ($UTIsFileProcess -and -not $UTHeadless -and $Host.Name -eq 'ConsoleHost') {
            Write-UTConsole -Text 'Pressione Enter para fechar.' -Color Gray
            [void](Read-Host)
        }
    }
    if ($UTIsFileProcess) { exit $UTExitCode }
    $global:LASTEXITCODE = $UTExitCode
    return
}
#endregion

try { $Host.UI.RawUI.WindowTitle = "Upgrade Tweaks v$UTVersion [Administrador]" } catch { Write-Verbose 'Sem título de janela neste host.' }
try { Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop } catch { Write-Verbose 'Política de execução definida por GPO; seguindo assim mesmo.' }

# Shared state between the UI thread and the worker runspaces.
$UTSync = [hashtable]::Synchronized(@{})
$UTSync.Versao = $UTVersion
$UTSync.Build = $UTBuild
$UTSync.Silencioso = [bool]$Silencioso
$UTSync.Simular = [bool]$Simular
$UTSync.ScriptPath = $UTScriptPath
$UTSync.ReleaseUrl = $UTReleaseUrl

[void](Initialize-UTFolder)
[void](Remove-UTOldLog -Dias 30)

if (-not $Silencioso -and -not $Overlay) { Show-UTBanner -Version $UTVersion }

$UTWindows = Get-UTWindowsInfo
$UTSupport = Get-UTWindowsSupport -Info $UTWindows
$UTSync.Windows = $UTWindows
switch ($UTSupport.Status) {
    'OK'           { Write-UTLog -Level Info -Message $UTSupport.Mensagem }
    'Aviso'        { Write-UTLog -Level Aviso -Message $UTSupport.Mensagem }
    'NaoSuportado' { Write-UTLog -Level Aviso -Message $UTSupport.Mensagem }
}

[void](Initialize-UTTargetUser)

$UTParamSummary = ConvertTo-UTArgumentString -Parameters $PSBoundParameters
if (-not $UTParamSummary) { $UTParamSummary = '(nenhum)' }
Write-UTLog -Level Info -Message "Sessão iniciada. Versão $UTVersion. Parâmetros: $UTParamSummary"

$UTExitCode = Invoke-UTMain -Preset $Preset -Config $Config -DesfazerTudo:$DesfazerTudo `
    -Diagnostico:$Diagnostico -ExportarRelatorio $ExportarRelatorio -Simular:$Simular -Galeria:$Galeria -Overlay:$Overlay

Write-UTLog -Level Info -Message "Sessão encerrada (código $UTExitCode)."
if ($UTIsFileProcess) { exit $UTExitCode }
$global:LASTEXITCODE = $UTExitCode
