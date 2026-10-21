function Get-UTBiosGuide {
    <#
    .SYNOPSIS
        "BIOS" guide of the Ferramentas tab, filtered by the detected processor and marked with
        what the diagnostics already confirmed. Also returns the motherboard support page and
        the chipset driver link for the detected vendors.
    #>
    [CmdletBinding()]
    param(
        [psobject]$Hardware,
        [object[]]$Verificacoes
    )
    if ($null -eq $Hardware) { $Hardware = Get-UTHardwareInfo }
    if ($null -eq $Verificacoes) { $Verificacoes = @(Get-UTDiagnosticCheck -Hardware $Hardware) }
    $cfg = Get-UTConfig -Name 'bios-guia'

    $cpuVendor = $null
    if ($Hardware.PSObject.Properties['CpuFabricante']) { $cpuVendor = $Hardware.CpuFabricante }
    $isX3D = [bool]($Hardware.PSObject.Properties['X3D'] -and $Hardware.X3D)
    $boardMaker = $null
    if ($Hardware.PSObject.Properties['Plataforma'] -and $Hardware.Plataforma) { $boardMaker = [string]$Hardware.Plataforma.FabricantePM }

    $board = $null
    if ($boardMaker) { $board = (@($cfg.fabricantesPlaca | Where-Object { $boardMaker -match $_.padrao }) | Select-Object -First 1) }
    $chipset = $null
    if ($cpuVendor -and $cfg.chipset.Contains($cpuVendor)) { $chipset = $cfg.chipset[$cpuVendor] }

    $items = foreach ($i in @($cfg.itens)) {
        if ($i.cpu -and @($i.cpu) -notcontains $cpuVendor) { continue }
        if ($i.x3d -and -not $isX3D) { continue }
        $state = 'Verificar'
        $detail = $null
        if ($i.verificacao) {
            $check = (@($Verificacoes | Where-Object { $_.Id -eq $i.verificacao }) | Select-Object -First 1)
            if ($check) {
                $detail = $check.Mensagem
                $state = switch ($check.Status) { 'OK' { 'Confirmado' } 'Aviso' { 'Pendente' } 'Problema' { 'Pendente' } default { 'Verificar' } }
            }
        }
        [pscustomobject]@{
            Id       = [string]$i.id
            Grupo    = [string]$i.grupo
            Titulo   = [string]$i.titulo
            Texto    = [string]$i.texto
            Aviso    = [string]$i.aviso
            Estado   = $state
            Detalhe  = $detail
        }
    }
    return [pscustomobject]@{
        PlacaMae      = $(if ($Hardware.PSObject.Properties['Plataforma'] -and $Hardware.Plataforma) { $Hardware.Plataforma.PlacaMae } else { $null })
        FabricantePM  = $(if ($board) { $board.nome } else { $boardMaker })
        SuportePlaca  = $(if ($board) { $board.suporte } else { $null })
        TeclaBios     = $(if ($board) { $board.teclaBios } else { 'Del, F2 ou F10 (aparece na tela ao ligar)' })
        Chipset       = $chipset
        Itens         = @($items)
    }
}
