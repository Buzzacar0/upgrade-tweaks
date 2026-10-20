# Functions behind the "Restaurar" tab.

function Restore-UTAllOriginalState {
    <#
    .SYNOPSIS
        Puts back every saved original (registry values and services), newest first.
    .DESCRIPTION
        Low-level safety net: it does not need the tweak definitions. "Desfazer TUDO" in the
        engine undoes the applied tweaks one by one (running their undo scripts) and calls this
        at the end for anything left. One failure does not stop the others.
        Generic items (power plan, bcdedit...) are skipped here because they need their own
        undo; they are listed in Ignorados.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $summary = [pscustomobject]@{ Restaurados = @(); Falhas = @(); Ignorados = @() }
    foreach ($entry in (Get-UTOriginalStateItem)) {
        $item = $entry.Item
        $label = switch ($item.tipo) {
            'registro' { "$($item.caminho)\$($item.nome)" }
            'servico' { "serviço $($item.nome)" }
            default { [string]$item.chave }
        }
        if ($item.tipo -notin 'registro', 'servico') {
            $summary.Ignorados += $label
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($label, 'Restaurar o valor original')) { continue }
        try {
            $status = Restore-UTOriginalEntry -Key $entry.Chave -Force
            if ($status -eq 'Restaurado') {
                $summary.Restaurados += $label
                Write-UTLog -Level Sucesso -Message "Restaurado: $label"
            }
        } catch {
            $friendly = Get-UTFriendlyError -ErrorRecord $_ -Alvo $label
            $summary.Falhas += [pscustomobject]@{ Item = $label; Motivo = $friendly }
            Write-UTLog -Level Erro -Message $friendly -Detalhe $_.Exception.Message
        }
    }
    return $summary
}

function Get-UTBackup {
    <#
    .SYNOPSIS
        Lists the backup folders, newest first, with date and what each one contains.
    #>
    [CmdletBinding()]
    param()

    $base = Get-UTPath -Name Backups
    if (-not (Test-Path -LiteralPath $base)) { return }

    $list = foreach ($dir in (Get-ChildItem -LiteralPath $base -Directory)) {
        $manifest = Read-UTJsonFile -Path (Join-Path $dir.FullName 'manifesto.json')
        if ($null -eq $manifest) { continue }
        $items = @($manifest.itens | Where-Object { $_ })
        $created = $dir.CreationTime
        if ($manifest.criadoEm) { $created = [datetime]::Parse($manifest.criadoEm, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
        [pscustomobject]@{
            Nome          = $dir.Name
            Pasta         = $dir.FullName
            Data          = $created
            Versao        = $manifest.versaoPrograma
            ChavesReg     = @($items | Where-Object { $_.tipo -eq 'registro' }).Count
            TemServicos   = @($items | Where-Object { $_.tipo -eq 'servicos' }).Count -gt 0
            TemPlano      = @($items | Where-Object { $_.tipo -eq 'energia' }).Count -gt 0
            Itens         = $items
        }
    }
    return ($list | Sort-Object Data -Descending)
}

function Restore-UTBackup {
    <#
    .SYNOPSIS
        Restores one backup folder: re-imports the .reg files, puts the services' start types
        back and re-imports the power plan (activating it).
    .DESCRIPTION
        Importing a .reg brings back the values that existed; values created after the backup
        are not deleted. To remove those too, use the tweak undo or "Desfazer TUDO".
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Pasta)

    Assert-UTAdmin
    $manifest = Read-UTJsonFile -Path (Join-Path $Pasta 'manifesto.json')
    if ($null -eq $manifest) { throw "A pasta $Pasta não é um backup do Upgrade Tweaks (manifesto.json não encontrado)." }

    $summary = [pscustomobject]@{ Restaurados = @(); Falhas = @() }
    foreach ($entry in @($manifest.itens | Where-Object { $_ })) {
        $file = Join-Path $Pasta $entry.arquivo
        try {
            switch ($entry.tipo) {
                'registro' {
                    Import-UTRegistryFile -Path $file
                    $summary.Restaurados += "Registro: $($entry.origem)"
                }
                'servicos' {
                    $data = Read-UTJsonFile -Path $file
                    foreach ($name in @($data.servicos.Keys)) {
                        $s = $data.servicos[$name]
                        if (-not $s.existia -or -not $s.startType) { continue }
                        try {
                            Set-UTServiceStartType -Name $name -StartType $s.startType
                            $summary.Restaurados += "Serviço: $name ($($s.startType))"
                        } catch {
                            $summary.Falhas += [pscustomobject]@{ Item = "Serviço $name"; Motivo = $_.Exception.Message }
                        }
                    }
                }
                'energia' {
                    Restore-UTPowerPlanFile -Path $file -Nome $entry.origem
                    $summary.Restaurados += "Plano de energia: $($entry.origem)"
                }
            }
        } catch {
            $friendly = Get-UTFriendlyError -ErrorRecord $_ -Alvo $entry.origem
            $summary.Falhas += [pscustomobject]@{ Item = $entry.origem; Motivo = $friendly }
            Write-UTLog -Level Erro -Message $friendly -Detalhe $_.Exception.Message
        }
    }
    Write-UTLog -Level Info -Message ("Backup {0} restaurado: {1} itens, {2} falhas." -f (Split-Path -Leaf $Pasta), $summary.Restaurados.Count, $summary.Falhas.Count)
    return $summary
}

function Restore-UTPowerPlanFile {
    <#
    .SYNOPSIS
        Imports a .pow file as a new plan and activates it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Nome
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Importar e ativar plano de energia')) { return }
    $r = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('/import', $Path)
    $m = [regex]::Match($r.Saida, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($r.CodigoSaida -ne 0 -or -not $m.Success) { throw "powercfg /import falhou: $($r.Saida) $($r.Erro)" }
    $guid = $m.Value
    if ($Nome) { [void](Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('/changename', $guid, "$Nome (restaurado)")) }
    $a = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('/setactive', $guid)
    if ($a.CodigoSaida -ne 0) { throw "powercfg /setactive falhou: $($a.Saida) $($a.Erro)" }
}

function Restore-UTDefaultPowerScheme {
    <#
    .SYNOPSIS
        powercfg -restoredefaultschemes: brings back Windows' default plans.
        Warning: this deletes every custom plan, including "Upgrade Warzone".
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    Assert-UTAdmin
    if (-not $PSCmdlet.ShouldProcess('Planos de energia', 'Restaurar os padrões do Windows (apaga planos personalizados)')) { return }
    $r = Invoke-UTNative -FilePath 'powercfg.exe' -ArgumentList @('-restoredefaultschemes')
    if ($r.CodigoSaida -ne 0) { throw "Não foi possível restaurar os planos de energia padrão: $($r.Saida) $($r.Erro)" }
    Write-UTLog -Level Sucesso -Message 'Planos de energia padrão do Windows restaurados.'
}

function Open-UTSystemRestore {
    <#
    .SYNOPSIS
        Opens Windows' System Restore wizard (rstrui.exe).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('rstrui.exe', 'Abrir a Restauração do Sistema')) {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\rstrui.exe')
    }
}
