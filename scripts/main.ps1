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
        [switch]$Simular
    )

    if ($Simular) { Write-UTLog -Level Info -Message 'Modo simulação: nada será alterado no sistema.' }

    $cliMode = [bool]($Preset -or $Config -or $DesfazerTudo -or $Diagnostico -or $ExportarRelatorio)
    if ($cliMode) {
        # Implemented in phase 10 (presets and command line).
        Write-UTLog -Level Aviso -Message 'O modo linha de comando ainda não está disponível nesta versão de desenvolvimento.'
        return 2
    }

    try {
        return (Show-UTMainWindow -Simular:$Simular)
    } catch {
        Write-UTLog -Level Erro -Message 'Não foi possível abrir a interface gráfica. Use o modo linha de comando (-Preset, -Diagnostico, -DesfazerTudo).' -Detalhe $_.Exception.ToString()
        return 1
    }
}
