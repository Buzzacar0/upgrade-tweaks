function Invoke-UTMain {
    <#
    .SYNOPSIS
        Entry point after elevation and environment checks. Chooses between the command-line
        modes and the graphical interface. Returns the process exit code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string]$Preset = '',
        [string]$Config = '',
        [switch]$DesfazerTudo,
        [switch]$Diagnostico,
        [string]$ExportarRelatorio = '',
        [switch]$Simular,
        [switch]$Galeria,
        [switch]$Overlay
    )

    # Overlay process only (started by the Overlay tab, the Match mode or at logon).
    if ($Overlay) { return (Start-UTOverlayHost) }

    if ($Simular) { Write-UTLog -Level Info -Message 'Modo simulação: nada será alterado no sistema.' }
    else {
        # v2: the custom power plan of the old versions gives way to Windows' Maximum Performance.
        try { [void](Invoke-UTPowerPlanMigration -Confirm:$false) } catch { Write-UTLog -Level Aviso -Message 'Não foi possível migrar o plano de energia antigo.' -Detalhe $_.Exception.Message }
    }

    $cliMode = [bool]($Preset -or $Config -or $DesfazerTudo -or $Diagnostico -or $ExportarRelatorio)
    if ($cliMode) {
        try {
            return (Invoke-UTCommandLine -Preset $Preset -Config $Config -DesfazerTudo:$DesfazerTudo `
                    -Diagnostico:$Diagnostico -ExportarRelatorio $ExportarRelatorio -Simular:$Simular)
        } catch {
            Write-UTLog -Level Erro -Message (Get-UTFriendlyError -ErrorRecord $_ -Alvo 'o modo linha de comando') -Detalhe $_.Exception.ToString()
            return 1
        }
    }

    try {
        return (Show-UTMainWindow -Simular:$Simular -Galeria:$Galeria)
    } catch {
        Write-UTLog -Level Erro -Message 'Não foi possível abrir a interface gráfica. Use o modo linha de comando (-Preset, -Diagnostico, -DesfazerTudo).' -Detalhe $_.Exception.ToString()
        return 1
    }
}
