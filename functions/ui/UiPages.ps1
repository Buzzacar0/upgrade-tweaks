# Content of each side tab. Pages are built the first time they are shown; whatever needs
# the system (diagnostics, NVIDIA, winget...) loads in the background inside the page.

#region Helpers
function Invoke-UTUiAction {
    <#
    .SYNOPSIS
        Runs a tool action in the background and tells the result: -Sucesso message, or
        -Depois (UI thread) with (result, -Dados).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Argumentos = @{},
        [string]$Sucesso,
        [scriptblock]$Depois,
        [object]$Dados,
        [switch]$Exclusivo
    )
    [void](Invoke-UTUiJob -Nome $Nome -Script $Script -Argumentos $Argumentos -Exclusivo:$Exclusivo -Estado @{ Sucesso = $Sucesso; Depois = $Depois; Dados = $Dados; Nome = $Nome } -AoTerminar {
            param($R, $E)
            if (-not $R.Ok) { Show-UTUiError -Mensagem $R.Erro; return }
            if ($E.Depois) { & $E.Depois $R.Resultado $E.Dados; return }
            if ($E.Sucesso) { [void](Show-UTUiDialog -Titulo $E.Nome -Mensagem $E.Sucesso -Tipo sucesso) }
        })
}

function New-UTUiKeyValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Pares, [double]$LarguraRotulo = 170)
    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = $LarguraRotulo
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    [void]$grid.ColumnDefinitions.Add($c1); [void]$grid.ColumnDefinitions.Add($c2)
    $i = 0
    foreach ($p in $Pares) {
        [void]$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $k = New-UTUiText ([string]$p[0]) -Cor MutedBrush -Margem '0,3,12,3'
        $v = New-UTUiText ([string]$p[1]) -Quebrar -Margem '0,3,0,3'
        [System.Windows.Controls.Grid]::SetRow($k, $i); [System.Windows.Controls.Grid]::SetRow($v, $i)
        [System.Windows.Controls.Grid]::SetColumn($v, 1)
        [void]$grid.Children.Add($k); [void]$grid.Children.Add($v)
        $i++
    }
    return $grid
}

function New-UTUiStatusLine {
    # One line with a colored dot: OK (green), Aviso (yellow), Problema (red), other (gray).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([string]$Status, [string]$Titulo, [string]$Texto, [object]$Extra)
    $color = switch ($Status) { 'OK' { 'GreenBrush' } 'Confirmado' { 'GreenBrush' } 'Aviso' { 'YellowBrush' } 'Pendente' { 'YellowBrush' } 'Problema' { 'RedBrush' } default { 'MutedBrush' } }
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 9; $dot.Height = 9; $dot.Fill = Get-UTUiBrush $color; $dot.Margin = '0,5,10,0'; $dot.VerticalAlignment = 'Top'
    $texts = New-UTUiStack -Itens @((New-UTUiText $Titulo -Peso SemiBold -Quebrar))
    if ($Texto) { [void]$texts.Children.Add((New-UTUiText $Texto -Cor MutedBrush -Quebrar -Margem '0,2,0,0')) }
    if ($Extra) { [void]$texts.Children.Add($Extra) }
    $dock = New-Object System.Windows.Controls.DockPanel
    $dock.Margin = '0,5'
    [System.Windows.Controls.DockPanel]::SetDock($dot, 'Left')
    [void]$dock.Children.Add($dot)
    [void]$dock.Children.Add($texts)
    return $dock
}

function Get-UTUiTabForCheck {
    # Diagnostic checks point to a tab name; a few live inside another tab.
    param([string]$Aba)
    switch ($Aba) { 'BIOS' { 'Ferramentas' } 'Video' { 'GPU' } default { $Aba } }
}

function Test-UTUiVendor {
    # GPU/CPU vendor for vendor-only cards. Before the diagnostics finish, a quick WMI read.
    param([string]$Gpu, [string]$Cpu)
    $hw = Get-UTSyncValue -Key 'Hardware'
    $gpus = @(); $cpuVendor = $null
    if ($hw) {
        $gpus = @($hw.GpuFabricantes); $cpuVendor = $hw.CpuFabricante
    } else {
        $quick = Get-UTSyncValue -Key 'FabricantesRapido'
        if ($null -eq $quick) {
            $names = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Name })
            $g = @()
            if ($names -match 'NVIDIA') { $g += 'nvidia' }
            if ($names -match 'AMD|Radeon') { $g += 'amd' }
            if ($names -match 'Intel') { $g += 'intel' }
            $maker = [string](@(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)[0]).Manufacturer
            $quick = @{ Gpus = $g; Cpu = $(if ($maker -match 'AMD') { 'amd' } elseif ($maker -match 'Intel') { 'intel' } else { $null }) }
            $UTSync['FabricantesRapido'] = $quick
        }
        $gpus = @($quick.Gpus); $cpuVendor = $quick.Cpu
    }
    if ($Gpu) { return ($gpus -contains $Gpu) }
    if ($Cpu) { return ($cpuVendor -eq $Cpu) }
    return $false
}
#endregion

#region Início
function New-UTUiPageInicio {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'Início' -Descricao 'Diagnóstico do seu PC para o Call of Duty: Warzone. Esta tela só lê o sistema; nada é alterado aqui.'))
    $data = @{}
    $panel = New-UTUiAsyncPanel -Nome 'Diagnóstico do PC' -Carregando 'Analisando o hardware e o Windows (leva alguns segundos)...' -Dados $data -Script { Get-UTDiagnostic } -Montar {
        param($R, $D)
        $diag = @($R)[0]
        $ui = Get-UTUi
        $ui.Diagnostico = $diag
        if (-not $ui.EstadosPedidos) {
            $ui.EstadosPedidos = $true
            Invoke-UTUiStateRefresh
            # Pages built before the hardware was known are rebuilt on the next visit.
            foreach ($k in @($ui.Pages.Keys)) { if ($k -ne 'Inicio' -and $k -ne $ui.PaginaAtual) { [void]$ui.Pages.Remove($k); Remove-UTUiPageRow -Pagina $k } }
        }
        New-UTUiDiagnosticView -Diagnostico $diag -Painel $D.Painel
    }
    $data.Painel = $panel
    [void]$page.Children.Add($panel)
    return $page
}

function New-UTUiDiagnosticView {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Diagnostico, [object]$Painel)
    $root = New-UTUiStack
    $score = [int]$Diagnostico.Nota
    $color = $(if ($score -ge 80) { 'GreenBrush' } elseif ($score -ge 60) { 'YellowBrush' } else { 'RedBrush' })

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in 300, 0) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w) { New-Object System.Windows.GridLength $w } else { New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star) })
        [void]$grid.ColumnDefinitions.Add($cd)
    }
    $scoreBox = New-UTUiStack -Itens @(
        (New-UTUiText 'Nota de Otimização' -Cor MutedBrush)
        (New-UTUiStack -Horizontal -Itens @((New-UTUiText ([string]$score) -Tamanho 56 -Peso Bold -Cor $color), (New-UTUiText '/100' -Tamanho 18 -Cor MutedBrush -Margem '6,0,0,12')))
        (New-UTUiText $(if ($score -ge 80) { 'PC bem ajustado para jogar.' } elseif ($score -ge 60) { 'Bom, mas há pontos para melhorar.' } else { 'Há problemas que custam FPS ou estabilidade.' }) -Quebrar)
    )
    $scoreBox.Children[1].Children[1].VerticalAlignment = 'Bottom'
    $btns = New-UTUiWrap -Margem '0,14,0,0'
    if ($Painel) { [void]$btns.Children.Add((New-UTUiButton 'Analisar de novo' -Icone 'E72C' -Dados $Painel -AoClicar { param($b, $d) $null = $b; Sync-UTUiAsyncPanel -Painel $d })) }
    [void]$btns.Children.Add((New-UTUiButton 'Exportar relatório' -Icone 'E8A5' -Dados $Diagnostico -AoClicar {
                param($b, $d)
                $null = $b
                $path = Get-UTUiFileDialog -Modo Salvar -Filtro 'Página HTML (*.html)|*.html|Texto (*.txt)|*.txt' -NomeSugerido ("diagnostico-{0}-{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd'))
                if (-not $path) { return }
                Export-UTDiagnosticReport -Path $path -Diagnostico $d | Out-Null
                [void](Show-UTUiDialog -Titulo 'Relatório salvo' -Mensagem $path -Tipo sucesso)
            }))
    [void]$scoreBox.Children.Add($btns)
    $left = New-UTUiCard -Conteudo @($scoreBox)
    $left.Margin = '0,0,12,12'
    [System.Windows.Controls.Grid]::SetColumn($left, 0)
    [void]$grid.Children.Add($left)

    $lines = @()
    try { $lines = @(Get-UTHardwareSummaryLine -Hardware $Diagnostico.Hardware | ForEach-Object { , @($_.Rotulo, $_.Valor) }) } catch { $lines = @() }
    $right = New-UTUiCard -Titulo 'Seu PC' -Icone 'E7F8' -Conteudo @((New-UTUiKeyValue -Pares $lines -LarguraRotulo 150))
    [System.Windows.Controls.Grid]::SetColumn($right, 1)
    [void]$grid.Children.Add($right)
    [void]$root.Children.Add($grid)

    $pending = @($Diagnostico.Pendencias)
    $items = New-Object System.Collections.Generic.List[object]
    if ($pending.Count -eq 0) { $items.Add((New-UTUiText 'Nenhuma pendência encontrada.' -Cor GreenBrush)) }
    foreach ($p in $pending) {
        $tab = Get-UTUiTabForCheck -Aba ([string]$p.Aba)
        $extra = $null
        if ($tab -and @(Get-UTUiTabDefinition | Where-Object Id -eq $tab).Count -gt 0) {
            $tabName = @(Get-UTUiTabDefinition | Where-Object Id -eq $tab)[0].Nome
            $extra = New-UTUiButton ("Resolver na aba $tabName") -Estilo Link -Margem '0,4,0,0' -Dados $tab -AoClicar { param($b, $d) $null = $b; Show-UTUiPage -Id $d }
        }
        $items.Add((New-UTUiStatusLine -Status ([string]$p.Status) -Titulo ([string]$p.Titulo) -Texto ([string]$p.Mensagem) -Extra $extra))
    }
    [void]$root.Children.Add((New-UTUiCard -Titulo 'Pendências' -Subtitulo 'Ordenadas pelo impacto. Cada uma diz em qual aba se resolve.' -Icone 'E7BA' -Conteudo $items.ToArray()))

    $ok = @($Diagnostico.Verificacoes | Where-Object { $_.Status -eq 'OK' })
    if ($ok.Count -gt 0) {
        $okItems = @($ok | ForEach-Object { New-UTUiStatusLine -Status OK -Titulo ([string]$_.Titulo) -Texto ([string]$_.Mensagem) })
        [void]$root.Children.Add((New-UTUiCard -Titulo 'Já está certo' -Icone 'E73E' -Conteudo $okItems))
    }
    return $root
}
#endregion

#region Tweak tabs with tools
function New-UTUiTweakPage {
    # Header + optional tool cards + the tweak list of the tab.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Aba, [string]$Descricao, [object[]]$Ferramentas = @(), [string]$TituloLista = 'Ajustes')
    $tab = @(Get-UTUiTabDefinition | Where-Object Id -eq $Aba)[0]
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo $tab.Nome -Descricao $Descricao))
    foreach ($f in $Ferramentas) { if ($f) { [void]$page.Children.Add($f) } }
    $list = New-UTUiTweakList -Tweaks @(Get-UTUiTabTweak -Aba $Aba) -Pagina $Aba -Titulo $TituloLista
    if ($list) { [void]$page.Children.Add($list) }
    return $page
}

function New-UTUiPageEnergia {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $data = @{}
    $status = New-UTUiAsyncPanel -Nome 'Plano de energia' -Dados $data -Script { Get-UTPowerPlanStatus } -Montar {
        param($R, $D)
        $s = @($R)[0]
        $pairs = @(, @('Plano ativo', $s.Ativo.Nome))
        $pairs += , @('Situação', $s.Mensagem)
        $box = New-UTUiStack -Itens @((New-UTUiKeyValue -Pares $pairs))
        $btns = New-UTUiWrap -Margem '0,10,0,0'
        [void]$btns.Children.Add((New-UTUiButton 'Voltar ao plano anterior' -Icone 'E7A7' -Dados $D -AoClicar {
                    param($b, $d) $null = $b
                    Invoke-UTUiAction -Nome 'Voltar ao plano anterior' -Script { Restore-UTPreviousPowerPlan } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                }))
        [void]$btns.Children.Add((New-UTUiButton 'Exportar plano ativo (.pow)' -Icone 'E74E' -AoClicar {
                    param($b, $d) $null = $b, $d
                    $p = Get-UTUiFileDialog -Modo Salvar -Filtro 'Plano de energia (*.pow)|*.pow' -NomeSugerido 'plano-de-energia.pow'
                    if ($p) { Invoke-UTUiAction -Nome 'Exportar plano' -Argumentos @{ Caminho = $p } -Script { param($Caminho) Export-UTPowerPlan -Path $Caminho } -Sucesso "Plano exportado para $p" }
                }))
        [void]$btns.Children.Add((New-UTUiButton 'Importar plano (.pow)' -Icone 'E8B5' -Dados $D -AoClicar {
                    param($b, $d) $null = $b
                    $p = Get-UTUiFileDialog -Modo Abrir -Filtro 'Plano de energia (*.pow)|*.pow'
                    if ($p) { Invoke-UTUiAction -Nome 'Importar plano' -Argumentos @{ Caminho = $p } -Script { param($Caminho) Import-UTPowerPlan -Path $Caminho -Ativar } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel } }
                }))
        [void]$btns.Children.Add((New-UTUiButton 'Restaurar planos padrão do Windows' -Icone 'E777' -AoClicar {
                    param($b, $d) $null = $b, $d
                    if ((Show-UTUiDialog -Titulo 'Restaurar planos padrão?' -Mensagem 'Recria os planos de energia originais do Windows (Equilibrado etc.). Planos personalizados continuam lá.' -Tipo pergunta -Botoes @('Restaurar', 'Cancelar')) -eq 'Restaurar') {
                        Invoke-UTUiAction -Nome 'Restaurar planos padrão' -Script { Restore-UTDefaultPowerScheme } -Sucesso 'Planos padrão restaurados.'
                    }
                }))
        [void]$box.Children.Add($btns)
        return $box
    }
    $data.Painel = $status
    $tools = @((New-UTUiCard -Titulo 'Plano de energia' -Icone 'E945' -Conteudo @($status)))
    $hw = Get-UTSyncValue -Key 'Hardware'
    if ($hw -and $hw.X3D -eq 'duplo') {
        $x3d = New-UTUiAsyncPanel -Nome 'Checagem do X3D' -Script { Get-UTX3DDualCheck } -Montar {
            param($R, $D) $null = $D
            New-UTUiStack -Itens @(@($R) | ForEach-Object { New-UTUiStatusLine -Status $(if ($_.Ok) { 'OK' } else { 'Aviso' }) -Titulo ([string]$_.Item) -Texto ([string]$_.Mensagem) })
        }
        $tools += New-UTUiCard -Titulo 'Ryzen X3D com dois CCDs' -Subtitulo 'Nestes processadores o plano Equilibrado + driver de chipset da AMD + Game Bar colocam o jogo no CCD com 3D V-Cache. Por isso o plano Upgrade Warzone não é usado.' -Icone 'E950' -Conteudo @($x3d)
    }
    return (New-UTUiTweakPage -Aba Energia -Descricao 'Plano de energia "Upgrade Warzone" e ajustes de energia do processador. Notebooks e Ryzen X3D de dois CCDs são tratados à parte.' -Ferramentas $tools)
}

function New-UTUiPageGaming {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    return (New-UTUiTweakPage -Aba Gaming -Descricao 'Ajustes do Windows para jogos: Modo de Jogo, gravação em segundo plano, mouse, agendamento de GPU e afins.')
}

function New-UTUiPageLatencia {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    return (New-UTUiTweakPage -Aba Latencia -Descricao 'Ajustes avançados de latência e sistema. Todos opcionais; os de risco médio e alto têm efeito pequeno e difícil de medir. Leia a descrição de cada um.')
}

function New-UTUiPagePrivacidade {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    return (New-UTUiTweakPage -Aba Privacidade -Descricao 'Telemetria, histórico de atividades, anúncios, Copilot/Recall e afins. O Windows Defender, o Windows Update e o UAC nunca são desligados.')
}

function New-UTUiPagePersonalizar {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    return (New-UTUiTweakPage -Aba Personalizar -Descricao 'Aparência e conforto: tema, barra de tarefas, extensões de arquivo, menu de contexto e efeitos visuais.')
}

function New-UTUiPageRede {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $info = New-UTUiAsyncPanel -Nome 'Adaptador de rede' -Script { Get-UTNetworkInfo } -Montar {
        param($R, $D) $null = $D
        $n = @($R)[0]
        if (-not $n) { return (New-UTUiText 'Nenhum adaptador de rede conectado.' -Cor YellowBrush) }
        $pairs = @(, @('Adaptador', "$($n.Adaptador) ($($n.Tipo))"))
        $pairs += , @('Velocidade', $n.Velocidade)
        $pairs += , @('IP', (@($n.IPv4) -join ', '))
        $pairs += , @('Gateway', $n.Gateway)
        $pairs += , @('DNS', (@($n.Dns) -join ', '))
        New-UTUiKeyValue -Pares $pairs
    }
    $results = New-Object System.Windows.Controls.Border
    $btns = New-UTUiWrap -Margem '0,10,0,0'
    [void]$btns.Children.Add((New-UTUiButton 'Testar latência, jitter e perda (30 s)' -Estilo Primario -Icone 'E916' -Dados $results -AoClicar {
                param($b, $d) $null = $b
                $d.Child = New-UTUiText 'Medindo por 30 segundos...' -Cor MutedBrush
                Invoke-UTUiAction -Nome 'Teste de rede' -Script { Test-UTNetworkQuality -Segundos 30 } -Dados $d -Depois {
                    param($r, $dd)
                    $rows = @($r | ForEach-Object { [pscustomobject]@{ Alvo = $_.Rotulo; Media = "$($_.MediaMs) ms"; Jitter = "$($_.JitterMs) ms"; Perda = "$($_.PerdaPct) %"; Minimo = "$($_.MinMs) ms"; Maximo = "$($_.MaxMs) ms" } })
                    $dd.Child = New-UTUiStack -Itens @(
                        (New-UTUiTable -Colunas @(@{ Titulo = 'Alvo'; Campo = 'Alvo'; Largura = '*' }, @{ Titulo = 'Média'; Campo = 'Media'; Largura = 90 }, @{ Titulo = 'Jitter'; Campo = 'Jitter'; Largura = 90 }, @{ Titulo = 'Perda'; Campo = 'Perda'; Largura = 80 }, @{ Titulo = 'Mín.'; Campo = 'Minimo'; Largura = 80 }, @{ Titulo = 'Máx.'; Campo = 'Maximo'; Largura = 80 }) -Itens $rows)
                        (New-UTUiText 'Jitter acima de ~5 ms ou qualquer perda no roteador indicam problema no Wi-Fi/cabo. Para jogar, prefira cabo.' -Cor MutedBrush -Quebrar)
                    )
                }
            }))
    [void]$btns.Children.Add((New-UTUiButton 'Comparar servidores DNS' -Icone 'E968' -Dados $results -AoClicar {
                param($b, $d) $null = $b
                $d.Child = New-UTUiText 'Medindo os servidores DNS...' -Cor MutedBrush
                Invoke-UTUiAction -Nome 'Comparar DNS' -Script { Measure-UTDnsProvider } -Dados $d -Depois {
                    param($r, $dd)
                    $rows = @($r | Sort-Object ResolucaoMs | ForEach-Object { [pscustomobject]@{ Nome = $_.Nome; Ping = "$($_.PingMs) ms"; Resolucao = "$($_.ResolucaoMs) ms"; Perda = "$($_.Perda) %" } })
                    $dd.Child = New-UTUiStack -Itens @(
                        (New-UTUiTable -Colunas @(@{ Titulo = 'Servidor'; Campo = 'Nome'; Largura = '*' }, @{ Titulo = 'Ping'; Campo = 'Ping'; Largura = 90 }, @{ Titulo = 'Resolução'; Campo = 'Resolucao'; Largura = 100 }, @{ Titulo = 'Perda'; Campo = 'Perda'; Largura = 80 }) -Itens $rows)
                        (New-UTUiText 'DNS só muda o tempo para achar os servidores; não muda o ping dentro da partida. Escolha o DNS nos ajustes abaixo.' -Cor MutedBrush -Quebrar)
                    )
                }
            }))
    [void]$btns.Children.Add((New-UTUiButton 'Limpar cache DNS' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiAction -Nome 'Limpar cache DNS' -Script { Clear-UTDnsCache } -Sucesso 'Cache DNS limpo.' }))
    [void]$btns.Children.Add((New-UTUiButton 'Teste de bufferbloat (site)' -AoClicar { param($b, $d) $null = $b, $d; Open-UTBufferbloatTest }))
    [void]$btns.Children.Add((New-UTUiButton 'Resetar rede (Winsock/TCP-IP)' -Estilo Perigo -AoClicar {
                param($b, $d) $null = $b, $d
                if ((Show-UTUiDialog -Titulo 'Resetar a rede?' -Mensagem 'Volta Winsock e TCP/IP ao padrão do Windows. Use só se a internet estiver com problema. Precisa reiniciar o PC depois, e VPNs podem precisar ser reinstaladas.' -Tipo aviso -Botoes @('Resetar', 'Cancelar')) -eq 'Resetar') {
                    Invoke-UTUiAction -Nome 'Resetar rede' -Exclusivo -Script { Reset-UTNetworkStack } -Sucesso 'Rede resetada. Reinicie o computador.'
                }
            }))
    $tools = @(New-UTUiCard -Titulo 'Conexão' -Icone 'E968' -Conteudo @($info, $btns, $results))
    return (New-UTUiTweakPage -Aba Rede -Descricao 'Adaptador, DNS e ajustes de rede. O ping da partida depende do servidor e da sua internet; aqui o foco é estabilidade e jitter.' -Ferramentas $tools)
}

function New-UTUiPageServico {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $lite = New-UTUiCard -Titulo 'Modo Lite' -Icone 'E74C' -Subtitulo 'Debloat agressivo de uma vez (OneDrive, Edge, Widgets, Copilot, apps que não são de jogo, serviços em Manual), num Windows original. Mostra a lista completa antes, tudo desmarcável. Nunca mexe em Xbox/Game Pass, Store, Game Bar, Defender ou Windows Update.' -Conteudo @(
        (New-UTUiButton 'Ver a lista do Modo Lite' -Icone 'E8FD' -AoClicar {
            param($b, $d) $null = $b, $d
            Invoke-UTUiAction -Nome 'Montando o Modo Lite' -Script { Get-UTLiteModePlan } -Depois {
                param($r, $dd) $null = $dd
                $plan = @($r)
                $items = @($plan | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Texto = "$($_.Nome)  [$($_.Risco)]"; Detalhe = $(if ($_.Compativel) { $_.Categoria } else { "Não se aplica: $($_.Motivo)" }); Marcado = $_.Marcado; Habilitado = $_.Compativel } })
                $chosen = Show-UTUiChecklistDialog -Titulo 'Modo Lite' -Mensagem 'Desmarque o que você quer manter. Tudo fica registrado e pode ser desfeito na aba Restaurar.' -Itens $items -BotaoOk 'Aplicar o Modo Lite'
                if ($null -eq $chosen -or @($chosen).Count -eq 0) { return }
                $high = @($plan | Where-Object { @($chosen) -contains $_.Id -and $_.Risco -eq 'alto' })
                $risk = $false
                if ($high.Count -gt 0) {
                    $ans = Show-UTUiDialog -Titulo 'Itens de risco alto no Modo Lite' -Tipo aviso -Itens @($high | ForEach-Object { $_.Nome }) -Mensagem 'Estes itens têm risco alto.' -Botoes @('Entendo o risco, aplicar', 'Pular os de risco alto', 'Cancelar')
                    if ($ans -eq 'Cancelar' -or -not $ans) { return }
                    if ($ans -eq 'Pular os de risco alto') { $chosen = @($chosen | Where-Object { @($high.Id) -notcontains $_ }) } else { $risk = $true }
                }
                $sim = [bool](Get-UTSyncValue -Key 'Simular')
                [void](Invoke-UTUiJob -Nome 'Aplicando o Modo Lite' -Exclusivo -Argumentos @{ Ids = @($chosen); Risco = $risk; Sim = $sim } -Estado @{ Ids = @($chosen); Modo = $(if ($sim) { 'Simular' } else { 'Aplicar' }) } -Script {
                        param([string[]]$Ids, [bool]$Risco, [bool]$Sim)
                        if ($Sim) { Invoke-UTTweak -Id $Ids -RiscoAltoConfirmado:$Risco -WhatIf } else { Invoke-UTLiteMode -Id $Ids -RiscoAltoConfirmado:$Risco }
                    } -AoTerminar { param($R, $E) Complete-UTUiRun -Resultado $R -Estado $E })
            }
        })
    )
    $data = @{}
    $startup = New-UTUiAsyncPanel -Nome 'Programas que iniciam com o Windows' -Dados $data -Script { Get-UTStartupItem } -Montar {
        param($R, $D)
        $list = New-UTUiStack
        foreach ($it in @($R | Sort-Object Nome)) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = New-UTUiStack -Itens @((New-UTUiText ([string]$it.Nome) -Peso SemiBold), (New-UTUiText ("$($it.Origem): $($it.Comando)") -Tamanho 11.5 -Cor MutedBrush -Quebrar))
            $cb.IsChecked = [bool]$it.Ativo
            $cb.Margin = '0,4'
            $cb.Tag = $it
            $cb.Add_Click({
                    param($box, $evt) $null = $evt
                    $item = $box.Tag
                    $on = [bool]$box.IsChecked
                    Invoke-UTUiAction -Nome 'Inicialização' -Argumentos @{ Item = $item; Ativo = $on } -Script { param($Item, [bool]$Ativo) Set-UTStartupItemState -Item $Item -Ativo $Ativo } -Dados $box -Depois { param($r, $bx) $null = $r; $bx.Tag.Ativo = [bool]$bx.IsChecked }
                })
            [void]$list.Children.Add($cb)
        }
        if ($list.Children.Count -eq 0) { [void]$list.Children.Add((New-UTUiText 'Nenhum programa inicia com o Windows.' -Cor MutedBrush)) }
        $null = $D
        return $list
    }
    $data.Painel = $startup
    $start = New-UTUiCard -Titulo 'Inicialização' -Icone 'E7E8' -Subtitulo 'Marcado = inicia com o Windows. Desmarcar só impede de abrir sozinho; o programa continua instalado.' -Conteudo @($startup)
    return (New-UTUiTweakPage -Aba ServicosApps -Descricao 'Serviços em Manual e remoção de apps que não são de jogo. Store, Xbox App, Gaming Services, Game Bar, Calculadora, Fotos, Terminal e Instalador de Aplicativo nunca são removidos.' -Ferramentas @($lite, $start))
}
#endregion

#region GPU
function New-UTUiPageGPU {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $tools = New-Object System.Collections.Generic.List[object]
    if (Test-UTUiVendor -Gpu nvidia) {
        foreach ($scope in 'perfil', 'global') {
            $title = $(if ($scope -eq 'perfil') { 'NVIDIA: perfil do Call of Duty' } else { 'NVIDIA: configurações globais' })
            $panel = New-UTUiAsyncPanel -Nome "NVIDIA ($scope)" -Argumentos @{ Escopo = $scope } -Script { param($Escopo) Get-UTNvidiaDrsStatus -Escopo $Escopo } -Montar {
                param($R, $D) $null = $D
                $rows = @($R | ForEach-Object { [pscustomobject]@{ Nome = $_.Nome; Atual = $_.Atual; Recomendado = $_.Recomendado; Ok = $(if ($_.Igual) { 'OK' } elseif ($_.Aplicavel) { 'Mudar' } else { '' }) } })
                $perfil = $(if (@($R).Count -gt 0) { @($R)[0].Perfil } else { '' })
                New-UTUiStack -Itens @(
                    (New-UTUiText "Perfil do driver: $perfil" -Cor MutedBrush)
                    (New-UTUiTable -Colunas @(@{ Titulo = 'Configuração'; Campo = 'Nome'; Largura = '*' }, @{ Titulo = 'Atual'; Campo = 'Atual'; Largura = 190 }, @{ Titulo = 'Recomendado'; Campo = 'Recomendado'; Largura = 210 }, @{ Titulo = ''; Campo = 'Ok'; Largura = 60 }) -Itens $rows)
                )
            }
            $btn = New-UTUiButton 'Restaurar padrões da NVIDIA' -Estilo Link -Margem '0,4,0,0' -Dados $scope -AoClicar {
                param($b, $d) $null = $b
                if ((Show-UTUiDialog -Titulo 'Restaurar padrões da NVIDIA?' -Mensagem 'Faz um backup do banco de perfis do driver e volta este perfil ao padrão de fábrica.' -Tipo pergunta -Botoes @('Restaurar', 'Cancelar')) -eq 'Restaurar') {
                    Invoke-UTUiAction -Nome 'Restaurar padrões NVIDIA' -Exclusivo -Argumentos @{ Escopo = $d } -Script { param($Escopo) Restore-UTNvidiaDefault -Escopo $Escopo -Confirm:$false } -Sucesso 'Padrões da NVIDIA restaurados.'
                }
            }
            $tools.Add((New-UTUiCard -Titulo $title -Icone 'E7F4' -Subtitulo 'Lido direto do driver (o Painel de Controle da NVIDIA foi aposentado). Para gravar, marque o ajuste correspondente na lista abaixo.' -Conteudo @($panel, $btn)))
        }
        $extra = New-UTUiAsyncPanel -Nome 'Cor e Resizable BAR' -Script { [pscustomobject]@{ Cor = @(Get-UTNvidiaColorRange); Rebar = (Get-UTResizableBarStatus) } } -Montar {
            param($R, $D) $null = $D
            $x = @($R)[0]
            $pairs = @($x.Cor | ForEach-Object { , @("Monitor $($_.Nome)", $_.Rotulo) })
            if ($x.Rebar) { $pairs += , @('Resizable BAR', $(if ($x.Rebar.Ligado) { 'Ligado' } else { 'Desligado (ligue na BIOS: veja Ferramentas > BIOS)' })) }
            New-UTUiKeyValue -Pares $pairs
        }
        $tools.Add((New-UTUiCard -Titulo 'Faixa de cor e Resizable BAR' -Icone 'E790' -Conteudo @($extra)))
    }

    $cacheData = @{}
    $cache = New-UTUiAsyncPanel -Nome 'Cache de shaders' -Dados $cacheData -Script { Get-UTShaderCacheLocation } -Montar {
        param($R, $D)
        $rows = @($R | ForEach-Object { [pscustomobject]@{ Nome = $_.Nome; Tamanho = "$($_.TamanhoMB) MB"; Caminho = $_.Caminho } })
        $clear = New-UTUiButton 'Limpar cache de shaders' -Icone 'E74D' -Dados $D -AoClicar {
            param($b, $d) $null = $b
            if ((Show-UTUiDialog -Titulo 'Limpar o cache de shaders?' -Mensagem 'Feche o jogo antes. Na próxima abertura o jogo recompila os shaders: o primeiro carregamento demora mais e pode engasgar no começo. Útil depois de atualizar o driver ou com travadas/artefatos.' -Tipo pergunta -Botoes @('Limpar', 'Cancelar')) -eq 'Limpar') {
                Invoke-UTUiAction -Nome 'Limpar cache de shaders' -Script { Clear-UTShaderCache -Confirm:$false } -Dados $d -Depois {
                    param($r, $dd)
                    [void](Show-UTUiDialog -Titulo 'Cache de shaders' -Mensagem "$(@($r)[0]) MB liberados." -Tipo sucesso)
                    Sync-UTUiAsyncPanel -Painel $dd.Painel
                }
            }
        }
        New-UTUiStack -Itens @((New-UTUiTable -Colunas @(@{ Titulo = 'Cache'; Campo = 'Nome'; Largura = 240 }, @{ Titulo = 'Tamanho'; Campo = 'Tamanho'; Largura = 100 }, @{ Titulo = 'Pasta'; Campo = 'Caminho'; Largura = '*' }) -Itens $rows), $clear)
    }
    $cacheData.Painel = $cache
    $tools.Add((New-UTUiCard -Titulo 'Cache de shaders' -Icone 'E74D' -Conteudo @($cache)))

    $driverBtns = New-UTUiWrap
    foreach ($v in 'nvidia', 'amd', 'intel') {
        [void]$driverBtns.Children.Add((New-UTUiButton ("Driver " + @{ nvidia = 'NVIDIA'; amd = 'AMD'; intel = 'Intel' }[$v]) -Icone 'E896' -Dados $v -AoClicar { param($b, $d) $null = $b; Open-UTDriverDownload -Fabricante $d }))
    }
    $guides = New-UTUiWrap
    foreach ($g in @(@('amd', 'Guia AMD Adrenalin'), @('intel', 'Guia Intel'), @('nvidiaApp', 'Guia NVIDIA App'), @('ddu', 'Guia do DDU'), @('driverSoVideo', 'Guia: só o driver NVIDIA'))) {
        [void]$guides.Children.Add((New-UTUiButton $g[1] -Icone 'E82D' -Dados $g[0] -AoClicar { param($b, $d) $null = $b; Show-UTUiGpuGuide -Guia $d }))
    }
    $content = @($driverBtns, $guides)
    if (Test-UTUiVendor -Gpu nvidia) {
        $content += New-UTUiButton 'Instalar só o driver de vídeo da NVIDIA...' -Estilo Primario -Icone 'E7F4' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiDriverOnlyFlow }
    }
    $tools.Add((New-UTUiCard -Titulo 'Drivers e guias' -Icone 'E896' -Subtitulo 'Baixe drivers só dos sites oficiais. Os guias trazem o passo a passo do que não dá para fazer por script.' -Conteudo $content))
    return (New-UTUiTweakPage -Aba GPU -Descricao 'Placa de vídeo: perfil NVIDIA do jogo, faixa de cor, taxa do monitor, cache de shaders, drivers e guias de AMD e Intel.' -Ferramentas $tools.ToArray())
}

function Show-UTUiGpuGuide {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Guia)
    $g = Get-UTGpuGuide -Guia $Guia
    $lines = @($g.passos | ForEach-Object { "$($_.item): $($_.valor) — $($_.motivo)" })
    [void](Show-UTUiDialog -Titulo ([string]$g.titulo) -Mensagem ([string]$g.observacao) -Itens $lines -Largura 720)
}

function Invoke-UTUiDriverOnlyFlow {
    <#
    .SYNOPSIS
        Guided "NVIDIA driver only": pick the official installer, choose what to keep, extract,
        strip and install silently.
    #>
    [CmdletBinding()]
    param()
    $exe = Get-UTUiFileDialog -Modo Abrir -Filtro 'Instalador do driver NVIDIA (*.exe)|*.exe'
    if (-not $exe) { return }
    $items = @(
        [pscustomobject]@{ Id = 'hdaudio'; Texto = 'Manter HD Audio (som pelo HDMI/DisplayPort do monitor)'; Marcado = $false }
        [pscustomobject]@{ Id = 'physx'; Texto = 'Manter PhysX (só jogos antigos usam)'; Marcado = $false }
        [pscustomobject]@{ Id = 'limpa'; Texto = 'Instalação limpa (zera as configurações da NVIDIA)'; Detalhe = 'Os ajustes do perfil do jogo feitos na aba GPU precisam ser aplicados de novo depois.'; Marcado = $false }
    )
    $chosen = Show-UTUiChecklistDialog -Titulo 'Só o driver de vídeo' -Mensagem "Instalador: $exe`nO pacote é extraído com o 7-Zip, os componentes extras (NVIDIA App, telemetria, USB-C...) são removidos e só o driver é instalado. A tela pisca durante a instalação." -Itens $items -BotaoOk 'Instalar'
    if ($null -eq $chosen) { return }
    $chosen = @($chosen)
    [void](Invoke-UTUiJob -Nome 'Instalando o driver NVIDIA' -Exclusivo -Argumentos @{ Instalador = $exe; HdAudio = ($chosen -contains 'hdaudio'); PhysX = ($chosen -contains 'physx'); Limpa = ($chosen -contains 'limpa') } -Script {
            param($Instalador, [bool]$HdAudio, [bool]$PhysX, [bool]$Limpa)
            $dest = Join-Path (Get-UTPath -Name Temp) ('nvidia-' + (Get-Date -Format 'yyyyMMddHHmmss'))
            [void](Expand-UTNvidiaDriverPackage -Instalador $Instalador -Destino $dest)
            [void](Optimize-UTNvidiaDriverPackage -Pasta $dest -ManterHdAudio:$HdAudio -ManterPhysX:$PhysX)
            Install-UTNvidiaDriverOnly -Pasta $dest -InstalacaoLimpa:$Limpa
        } -AoTerminar {
            param($R, $E) $null = $E
            if (-not $R.Ok) { Show-UTUiError -Mensagem $R.Erro; return }
            $code = @($R.Resultado)[-1]
            $msg = $(if ($code -eq 0) { 'Driver instalado. Reinicie o computador.' } else { "O instalador da NVIDIA terminou com o código $code. Veja o log." })
            [void](Show-UTUiDialog -Titulo 'Driver NVIDIA' -Mensagem $msg -Tipo $(if ($code -eq 0) { 'sucesso' } else { 'aviso' }))
        })
}
#endregion

#region Warzone
function New-UTUiPageWarzone {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $matchData = @{}
    $match = New-UTUiAsyncPanel -Nome 'Modo Partida' -Dados $matchData -Script { [pscustomobject]@{ Status = (Get-UTMatchModeStatus); Lista = @(Get-UTMatchModeList) } } -Montar {
        param($R, $D)
        $x = @($R)[0]
        $box = New-UTUiStack
        if ($x.Status.Ativo) {
            [void]$box.Children.Add((New-UTUiText "Modo Partida ATIVO desde $($x.Status.Inicio). Programas fechados: $(@($x.Status.Fechados | ForEach-Object { $_.nome }) -join ', ')" -Cor GreenBrush -Quebrar))
            [void]$box.Children.Add((New-UTUiButton 'Sair do Modo Partida' -Estilo Primario -Icone 'E7A7' -Margem '0,10,0,0' -Dados $D -AoClicar {
                        param($b, $d) $null = $b
                        Invoke-UTUiAction -Nome 'Saindo do Modo Partida' -Script { Stop-UTMatchMode } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                    }))
            return $box
        }
        [void]$box.Children.Add((New-UTUiText 'Marque o que fechar durante a partida. Discord, áudio e drivers nunca são fechados sem você marcar.' -Cor MutedBrush -Quebrar -Margem '0,0,0,6'))
        $wrap = New-UTUiWrap
        $checks = New-Object System.Collections.Generic.List[object]
        foreach ($p in @($x.Lista)) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = "$($p.Nome)"
            $cb.ToolTip = "$($p.Grupo) - $($p.Processo).exe"
            $cb.IsChecked = [bool]$p.Marcado
            $cb.Tag = [string]$p.Processo
            $cb.Margin = '0,4,22,4'
            $cb.MinWidth = 180
            [void]$wrap.Children.Add($cb)
            $checks.Add($cb)
        }
        [void]$box.Children.Add($wrap)
        $mem = New-Object System.Windows.Controls.CheckBox
        $mem.Content = 'Limpar a memória em espera (opcional; efeito pequeno, o Windows já faz isso sozinho)'
        $mem.Margin = '0,10,0,0'
        [void]$box.Children.Add($mem)
        $state = @{ Checks = $checks; Memoria = $mem; Painel = $D.Painel }
        [void]$box.Children.Add((New-UTUiButton 'Entrar no Modo Partida' -Estilo Primario -Icone 'E768' -Margem '0,12,0,0' -Dados $state -AoClicar {
                    param($b, $d) $null = $b
                    $marks = @{}
                    foreach ($c in $d.Checks) { $marks[[string]$c.Tag] = [bool]$c.IsChecked }
                    Invoke-UTUiAction -Nome 'Entrando no Modo Partida' -Argumentos @{ Marcados = $marks; Memoria = [bool]$d.Memoria.IsChecked } -Script {
                        param([hashtable]$Marcados, [bool]$Memoria)
                        Set-UTMatchModeChoice -Marcados $Marcados
                        Start-UTMatchMode -LimparMemoriaEspera:$Memoria
                    } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                }))
        return $box
    }
    $matchData.Painel = $match

    $cfgData = @{}
    $cfg = New-UTUiAsyncPanel -Nome 'Configuração do jogo' -Dados $cfgData -Script {
        $files = @(Get-UTCodConfigFile)
        $rows = foreach ($f in $files) {
            $rw = $null
            try { $rw = Get-UTCodConfigValue -Arquivo $f.Arquivo -Chave 'RendererWorkerCount' } catch { $rw = $null }
            [pscustomobject]@{ Titulo = $f.Titulo; Arquivo = $f.Nome; Caminho = $f.Arquivo; Threads = $rw; Data = $f.Alterado }
        }
        [pscustomobject]@{ Arquivos = @($rows); Backups = @(Get-UTCodConfigBackup) }
    } -Montar {
        param($R, $D)
        $x = @($R)[0]
        if (@($x.Arquivos).Count -eq 0) { return (New-UTUiText 'Nenhum arquivo de configuração do Call of Duty encontrado em Documentos\Call of Duty\players. Abra o jogo uma vez e feche.' -Cor YellowBrush -Quebrar) }
        $grid = New-UTUiTable -Colunas @(@{ Titulo = 'Jogo'; Campo = 'Titulo'; Largura = 140 }, @{ Titulo = 'Arquivo'; Campo = 'Arquivo'; Largura = '*' }, @{ Titulo = 'RendererWorkerCount'; Campo = 'Threads'; Largura = 150 }) -Itens @($x.Arquivos)
        $first = @($x.Arquivos)[0]
        $btns = New-UTUiWrap -Margem '0,6,0,0'
        [void]$btns.Children.Add((New-UTUiButton 'Abrir a pasta' -Icone 'E8B7' -AoClicar { param($b, $d) $null = $b, $d; Open-UTCodConfigFolder }))
        [void]$btns.Children.Add((New-UTUiButton 'Fazer backup' -Icone 'E74E' -Dados @{ Arquivo = $first.Caminho; Painel = $D.Painel } -AoClicar {
                    param($b, $d) $null = $b
                    Invoke-UTUiAction -Nome 'Backup da configuração' -Argumentos @{ Arquivo = $d.Arquivo } -Script { param($Arquivo) Backup-UTCodConfig -Arquivo $Arquivo } -Dados $d -Depois { param($r, $dd) [void](Show-UTUiDialog -Titulo 'Backup feito' -Mensagem ([string]@($r)[0]) -Tipo sucesso); Sync-UTUiAsyncPanel -Painel $dd.Painel }
                }))
        [void]$btns.Children.Add((New-UTUiButton 'RendererWorkerCount = núcleos físicos' -Icone 'E950' -Dica 'Número de threads de renderização do jogo igual aos núcleos físicos do processador. Feche o jogo antes.' -Dados @{ Arquivo = $first.Caminho; Painel = $D.Painel } -AoClicar {
                    param($b, $d) $null = $b
                    Invoke-UTUiAction -Nome 'RendererWorkerCount' -Argumentos @{ Arquivo = $d.Arquivo } -Script { param($Arquivo) Set-UTCodRendererWorker -Arquivo $Arquivo } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                }))
        if (@($x.Backups).Count -gt 0) {
            [void]$btns.Children.Add((New-UTUiButton 'Restaurar um backup...' -Icone 'E777' -Dados @{ Backups = @($x.Backups); Painel = $D.Painel } -AoClicar {
                        param($b, $d) $null = $b
                        $items = @($d.Backups | ForEach-Object { [pscustomobject]@{ Id = $_.Backup; Texto = "$($_.Data) - $($_.Nome)"; Marcado = $false } })
                        $pick = Show-UTUiChecklistDialog -Titulo 'Restaurar backup da configuração' -Mensagem 'Marque um backup. O arquivo atual é guardado antes.' -Itens $items -BotaoOk 'Restaurar'
                        if ($null -eq $pick -or @($pick).Count -eq 0) { return }
                        Invoke-UTUiAction -Nome 'Restaurar configuração' -Argumentos @{ Backup = @($pick)[0] } -Script { param($Backup) Restore-UTCodConfig -Backup $Backup } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                    }))
        }
        New-UTUiStack -Itens @($grid, $btns)
    }
    $cfgData.Painel = $cfg

    $guideHost = New-Object System.Windows.Controls.Border
    $combo = New-Object System.Windows.Controls.ComboBox
    $combo.Width = 300
    $combo.HorizontalAlignment = 'Left'
    foreach ($p in 'Competitivo (mais FPS e visibilidade)', 'Equilíbrio (FPS + imagem)') { [void]$combo.Items.Add($p) }
    $combo.Tag = $guideHost
    $combo.Add_SelectionChanged({
            param($cbx, $evt) $null = $evt
            $perfil = $(if ($cbx.SelectedIndex -eq 1) { 'equilibrio' } else { 'competitivo' })
            $rows = @(Get-UTWarzoneGuide -Perfil $perfil)
            $cbx.Tag.Child = New-UTUiTable -Colunas @(@{ Titulo = 'Grupo'; Campo = 'Grupo'; Largura = 120 }, @{ Titulo = 'Opção'; Campo = 'Opcao'; Largura = 200 }, @{ Titulo = 'Valor'; Campo = 'Valor'; Largura = 160 }, @{ Titulo = 'Por quê'; Campo = 'Motivo'; Largura = '*' }) -Itens $rows
        })
    $combo.SelectedIndex = 0
    $tools = @(
        (New-UTUiCard -Titulo 'Modo Partida' -Icone 'E7FC' -Subtitulo 'Antes de jogar: fecha programas pesados e ativa o plano Upgrade Warzone. Ao sair, volta o plano anterior e reabre o que foi fechado.' -Conteudo @($match))
        (New-UTUiCard -Titulo 'Arquivo de configuração do jogo' -Icone 'E713' -Subtitulo 'O programa só altera chaves que já existem e sempre faz backup antes. Feche o jogo antes de mexer.' -Conteudo @($cfg))
        (New-UTUiCard -Titulo 'Configurações recomendadas dentro do jogo' -Icone 'E7FC' -Subtitulo 'Ajustadas para a sua placa de vídeo e VRAM. Configure no menu do jogo.' -Conteudo @($combo, $guideHost))
    )
    return (New-UTUiTweakPage -Aba Warzone -Descricao 'Tudo específico do Call of Duty: Modo Partida, arquivo de configuração, guia de gráficos e ajustes do Windows para o jogo.' -Ferramentas $tools)
}
#endregion

#region Ferramentas
function New-UTUiPageFerramenta {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $tempData = @{}
    $temp = New-UTUiAsyncPanel -Nome 'Temporários' -Dados $tempData -Script { Get-UTTempCleanupTarget -IncluirLixeira } -Montar {
        param($R, $D)
        $box = New-UTUiStack
        $checks = New-Object System.Collections.Generic.List[object]
        $seen = @{}
        foreach ($t in @($R)) {
            $key = [string]$t.Id
            if ($key -eq 'lixeira') {
                if ($seen.ContainsKey('lixeira')) { $seen['lixeira'].Size += [double]$t.TamanhoMB; $seen['lixeira'].Check.Content = ("Lixeira (todas as unidades): {0:N0} MB" -f $seen['lixeira'].Size); continue }
            }
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $(if ($key -eq 'lixeira') { "Lixeira (todas as unidades): {0:N0} MB" -f $t.TamanhoMB } else { "{0}: {1:N0} MB" -f $t.Nome, $t.TamanhoMB })
            $cb.IsChecked = ($key -ne 'lixeira')
            $cb.Tag = $key
            $cb.Margin = '0,3'
            [void]$box.Children.Add($cb)
            $checks.Add($cb)
            $seen[$key] = @{ Check = $cb; Size = [double]$t.TamanhoMB }
        }
        [void]$box.Children.Add((New-UTUiButton 'Limpar' -Estilo Primario -Icone 'E74D' -Margem '0,10,0,0' -Dados @{ Checks = $checks; Painel = $D.Painel } -AoClicar {
                    param($b, $d) $null = $b
                    $sel = @($d.Checks | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
                    if ($sel.Count -eq 0) { return }
                    Invoke-UTUiAction -Nome 'Limpando temporários' -Argumentos @{ Itens = $sel } -Script { param([string[]]$Itens) Clear-UTTempFile -Itens $Itens -Confirm:$false } -Dados $d -Depois {
                        param($r, $dd)
                        $total = [math]::Round((@($r) | Measure-Object LiberadoMB -Sum).Sum, 0)
                        [void](Show-UTUiDialog -Titulo 'Limpeza concluída' -Mensagem "$total MB liberados." -Tipo sucesso -Itens @(@($r) | ForEach-Object { "$($_.Nome): $($_.LiberadoMB) MB" }))
                        Sync-UTUiAsyncPanel -Painel $dd.Painel
                    }
                }))
        return $box
    }
    $tempData.Painel = $temp

    $repair = New-UTUiWrap
    [void]$repair.Children.Add((New-UTUiButton 'Limpeza de Disco do Windows' -Icone 'EA99' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiAction -Nome 'Limpeza de Disco' -Exclusivo -Script { Invoke-UTDiskCleanup -Confirm:$false } -Depois { param($r, $dd) $null = $dd; [void](Show-UTUiDialog -Titulo 'Limpeza de Disco' -Mensagem "$(@($r)[0]) GB liberados no disco do Windows." -Tipo sucesso) } }))
    foreach ($t in @(@('componentcleanup', 'Limpar componentes (DISM)'), @('sfc', 'Verificar arquivos do sistema (sfc)'), @('restorehealth', 'Reparar imagem do Windows (DISM)'))) {
        [void]$repair.Children.Add((New-UTUiButton $t[1] -Icone 'E90F' -Dados $t[0] -AoClicar {
                    param($b, $d) $null = $b
                    Invoke-UTUiAction -Nome 'Reparo do Windows' -Exclusivo -Argumentos @{ Ferramenta = $d } -Script { param($Ferramenta) Invoke-UTWindowsRepairTool -Ferramenta $Ferramenta } -Depois {
                        param($r, $dd) $null = $dd
                        $x = @($r)[0]
                        [void](Show-UTUiDialog -Titulo 'Reparo do Windows' -Mensagem $x.Resumo -Tipo $(if ($x.Sucesso) { 'sucesso' } else { 'aviso' }))
                    }
                }))
    }

    $drives = New-UTUiAsyncPanel -Nome 'Unidades' -Script { Get-UTDriveOptimizationPlan } -Montar {
        param($R, $D) $null = $D
        $rows = @($R | ForEach-Object { [pscustomobject]@{ Letra = "$($_.Letra):"; Disco = $_.Disco; Tipo = $_.Tipo; Acao = $_.Descricao } })
        New-UTUiStack -Itens @(
            (New-UTUiTable -Colunas @(@{ Titulo = 'Unidade'; Campo = 'Letra'; Largura = 70 }, @{ Titulo = 'Disco'; Campo = 'Disco'; Largura = '*' }, @{ Titulo = 'Tipo'; Campo = 'Tipo'; Largura = 80 }, @{ Titulo = 'O que será feito'; Campo = 'Acao'; Largura = 260 }) -Itens $rows)
            (New-UTUiButton 'Otimizar unidades' -Icone 'EDA2' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiAction -Nome 'Otimizar unidades' -Exclusivo -Script { Optimize-UTDrive } -Depois { param($r, $dd) $null = $dd; [void](Show-UTUiDialog -Titulo 'Otimizar unidades' -Mensagem 'Concluído.' -Tipo sucesso -Itens @(@($r) | ForEach-Object { "$($_.Letra): $($_.Mensagem)" })) } })
        )
    }

    $wuData = @{}
    $wu = New-UTUiAsyncPanel -Nome 'Windows Update' -Dados $wuData -Script { Get-UTWindowsUpdatePause } -Montar {
        param($R, $D)
        $p = @($R)[0]
        $box = New-UTUiStack -Itens @((New-UTUiText $(if ($p.Pausado) { "Pausado até $($p.Ate.ToString('dd/MM/yyyy HH:mm'))." } else { 'Atualizações ativas.' }) -Cor $(if ($p.Pausado) { 'YellowBrush' } else { 'GreenBrush' })))
        $btns = New-UTUiWrap -Margem '0,8,0,0'
        foreach ($days in 7, 14, 35) {
            [void]$btns.Children.Add((New-UTUiButton "Pausar $days dias" -Dados @{ Dias = $days; Painel = $D.Painel } -AoClicar { param($b, $d) $null = $b; Invoke-UTUiAction -Nome 'Pausar Windows Update' -Argumentos @{ Dias = $d.Dias } -Script { param([int]$Dias) Suspend-UTWindowsUpdate -Dias $Dias } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel } }))
        }
        if ($p.Pausado) { [void]$btns.Children.Add((New-UTUiButton 'Retomar agora' -Estilo Primario -Dados $D -AoClicar { param($b, $d) $null = $b; Invoke-UTUiAction -Nome 'Retomar Windows Update' -Script { Resume-UTWindowsUpdate } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel } })) }
        [void]$box.Children.Add($btns)
        return $box
    }
    $wuData.Painel = $wu

    $paging = New-UTUiAsyncPanel -Nome 'Arquivo de paginação' -Script { Get-UTPageFileStatus } -Montar {
        param($R, $D) $null = $D
        $p = @($R)[0]
        New-UTUiStatusLine -Status $(if ($p.Estado -eq 'Automatico') { 'OK' } elseif ($p.Estado -eq 'Desativado') { 'Problema' } else { 'Aviso' }) -Titulo 'Arquivo de paginação' -Texto $p.Mensagem
    }

    $shortcuts = New-UTUiWrap
    foreach ($s in @(Get-UTSystemShortcut)) { [void]$shortcuts.Children.Add((New-UTUiButton $s.Nome -Dados $s.Id -AoClicar { param($b, $d) $null = $b; Open-UTSystemShortcut -Atalho $d })) }

    $bios = New-UTUiAsyncPanel -Nome 'Guia de BIOS' -Script { Get-UTBiosGuide -Hardware (Get-UTSyncValue -Key 'Hardware') } -Montar {
        param($R, $D) $null = $D
        $g = @($R)[0]
        $box = New-UTUiStack
        $head = @()
        if ($g.PlacaMae) { $head += , @('Placa-mãe', $g.PlacaMae) }
        $head += , @('Tecla para entrar na BIOS', $g.TeclaBios)
        [void]$box.Children.Add((New-UTUiKeyValue -Pares $head))
        $links = New-UTUiWrap -Margem '0,6,0,6'
        if ($g.SuportePlaca) { [void]$links.Children.Add((New-UTUiButton "Suporte $($g.FabricantePM) (BIOS)" -Icone 'E896' -Dados $g.SuportePlaca -AoClicar { param($b, $d) $null = $b; Open-UTUiLink -Url $d })) }
        if ($g.Chipset) { [void]$links.Children.Add((New-UTUiButton $g.Chipset.nome -Icone 'E896' -Dados $g.Chipset.url -AoClicar { param($b, $d) $null = $b; Open-UTUiLink -Url $d })) }
        [void]$box.Children.Add($links)
        $group = ''
        foreach ($i in @($g.Itens)) {
            if ($i.Grupo -ne $group) { $group = $i.Grupo; [void]$box.Children.Add((New-UTUiText $group -Tamanho 12 -Peso SemiBold -Cor AccentLightBrush -Margem '0,10,0,2')) }
            $extra = $null
            if ($i.Aviso) { $extra = New-UTUiText ("Cuidado: " + $i.Aviso) -Tamanho 12 -Cor YellowBrush -Quebrar -Margem '0,3,0,0' }
            $label = @{ Confirmado = ' (confirmado pelo diagnóstico)'; Pendente = ' (pendente)'; Verificar = '' }[$i.Estado]
            [void]$box.Children.Add((New-UTUiStatusLine -Status $i.Estado -Titulo ($i.Titulo + $label) -Texto $i.Texto -Extra $extra))
        }
        return $box
    }

    $tools = @(
        (New-UTUiCard -Titulo 'Limpar temporários' -Icone 'E74D' -Subtitulo 'Arquivos em uso são pulados. Limpar o Prefetch ou "limpar a RAM" não ajuda, por isso não está aqui.' -Conteudo @($temp))
        (New-UTUiCard -Titulo 'Limpeza e reparo do Windows' -Icone 'E90F' -Subtitulo 'Podem levar de 5 a 30 minutos. A saída completa fica no log.' -Conteudo @($repair))
        (New-UTUiCard -Titulo 'Otimizar unidades' -Icone 'EDA2' -Subtitulo 'TRIM em SSD/NVMe. Desfragmentação só em HD: SSD nunca é desfragmentado.' -Conteudo @($drives))
        (New-UTUiCard -Titulo 'Arquivo de paginação' -Icone 'E964' -Conteudo @($paging))
        (New-UTUiCard -Titulo 'Pausar o Windows Update' -Icone 'E895' -Subtitulo 'No máximo 35 dias, igual ao app Configurações. Nunca é desligado de vez.' -Conteudo @($wu))
        (New-UTUiCard -Titulo 'Atalhos do sistema' -Icone 'E8A7' -Conteudo @($shortcuts))
        (New-UTUiCard -Titulo 'Guia de BIOS e hardware' -Icone 'E950' -Subtitulo 'O que não dá para fazer por script, personalizado para o seu processador e placa-mãe.' -Conteudo @($bios))
    )
    return (New-UTUiTweakPage -Aba Ferramentas -Descricao 'Limpeza, reparo do Windows, discos, paginação, pausa de atualizações e guia de BIOS.' -Ferramentas $tools)
}
#endregion

#region Programas
function New-UTUiPagePrograma {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $data = @{ Atualizacao = $false }
    $panel = New-UTUiAsyncPanel -Nome 'Programas' -Carregando 'Lendo os programas instalados (winget)...' -Dados $data -Argumentos @{ Atualizacao = $false } -Script {
        param([bool]$Atualizacao)
        [pscustomobject]@{ Programas = @(Get-UTProgramStatus -VerificarAtualizacao:$Atualizacao); Winget = [bool](Get-UTWingetPath) }
    } -Montar {
        param($R, $D)
        $x = @($R)[0]
        $root = New-UTUiStack
        $bar = New-UTUiWrap -Margem '0,0,0,8'
        [void]$bar.Children.Add((New-UTUiButton 'Procurar atualizações' -Icone 'E895' -Dados $D -AoClicar {
                    param($b, $d) $null = $b
                    $d.Painel.Tag.Argumentos = @{ Atualizacao = $true }
                    Sync-UTUiAsyncPanel -Painel $d.Painel
                }))
        if (-not $x.Winget) {
            [void]$root.Children.Add((New-UTUiStatusLine -Status Aviso -Titulo 'winget não encontrado' -Texto 'Sem o winget, só os programas com versão no GitHub podem ser instalados. Instale o "Instalador de Aplicativo" pela Microsoft Store.' -Extra (New-UTUiButton 'Abrir na Microsoft Store' -Estilo Link -AoClicar { param($b, $d) $null = $b, $d; Open-UTWingetStorePage })))
        }
        [void]$root.Children.Add($bar)
        foreach ($cat in @((Get-UTConfig -Name 'programs').categorias)) {
            $progs = @($x.Programas | Where-Object Categoria -eq $cat)
            if ($progs.Count -eq 0) { continue }
            [void]$root.Children.Add((New-UTUiText $cat -Tamanho 13 -Peso SemiBold -Cor AccentLightBrush -Margem '0,12,0,4'))
            foreach ($p in $progs) { [void]$root.Children.Add((New-UTUiProgramRow -Programa $p -Painel $D.Painel)) }
        }
        return $root
    }
    $data.Painel = $panel
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'Programas' -Descricao 'Ferramentas de terceiros conhecidas, instaladas pelo winget ou pela última versão oficial no GitHub. Todas abrem como administrador.'))
    [void]$page.Children.Add((New-UTUiCard -Conteudo @($panel)))
    if (Test-UTUiVendor -Gpu nvidia) {
        [void]$page.Children.Add((New-UTUiCard -Titulo 'NVIDIA Profile Inspector' -Icone 'E7F4' -Subtitulo 'Caminho alternativo à aba GPU: importa o perfil recomendado do Warzone em .nip, com backup completo do driver antes.' -Conteudo @(
                    (New-UTUiButton 'Importar o perfil do Warzone pelo Profile Inspector' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiAction -Nome 'Profile Inspector' -Exclusivo -Script { Import-UTNvidiaInspectorProfile } -Depois { param($r, $dd) $null = $dd; [void](Show-UTUiDialog -Titulo 'Perfil importado' -Mensagem "Backup do driver: $(@($r)[-1])" -Tipo sucesso) } })
                )))
    }
    return $page
}

function New-UTUiProgramRow {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Programa, [object]$Painel)
    $p = $Programa
    $title = New-UTUiWrap -Itens @((New-UTUiText $p.Nome -Peso SemiBold))
    if ($p.Instalado) { [void]$title.Children.Add((New-UTUiBadge $(if ($p.Versao) { "Instalado $($p.Versao)" } else { 'Instalado' }) -Cor verde)) }
    if ($p.AtualizacaoDisponivel) { [void]$title.Children.Add((New-UTUiBadge "Atualização $($p.VersaoDisponivel)" -Cor amarelo)) }
    if ($p.SomentePagina) { [void]$title.Children.Add((New-UTUiBadge 'Só página oficial' -Cor cinza)) }
    $texts = New-UTUiStack -Itens @($title, (New-UTUiText $p.Descricao -Tamanho 12 -Cor MutedBrush -Quebrar -Margem '0,2,0,0'))
    if ($p.Aviso) { [void]$texts.Children.Add((New-UTUiText $p.Aviso -Tamanho 12 -Cor YellowBrush -Quebrar -Margem '0,2,0,0')) }
    [void]$texts.Children.Add((New-UTUiButton ("Origem: " + $p.Origem) -Estilo Link -Margem '0,3,0,0' -Dados $p.Site -AoClicar { param($b, $d) $null = $b; Open-UTUiLink -Url $d }))

    $d = @{ Id = $p.Id; Nome = $p.Nome; Painel = $Painel }
    $btns = New-UTUiWrap
    $btns.HorizontalAlignment = 'Right'
    $btns.VerticalAlignment = 'Center'
    if ($p.SomentePagina) {
        if ($p.Instalado) { [void]$btns.Children.Add((New-UTUiButton 'Abrir' -Estilo Primario -Dados $d -AoClicar { param($b, $x) $null = $b; Start-UTProgram -Id $x.Id })) }
        [void]$btns.Children.Add((New-UTUiButton 'Abrir página' -Dados $d -AoClicar { param($b, $x) $null = $b; Open-UTProgramPage -Id $x.Id }))
    } elseif ($p.Instalado) {
        [void]$btns.Children.Add((New-UTUiButton 'Abrir' -Estilo Primario -Dados $d -AoClicar { param($b, $x) $null = $b; Start-UTProgram -Id $x.Id }))
        if ($p.AtualizacaoDisponivel) { [void]$btns.Children.Add((New-UTUiButton 'Atualizar' -Dados $d -AoClicar { param($b, $x) $null = $b; Invoke-UTUiProgramAction -Acao Atualizar -Dados $x })) }
        [void]$btns.Children.Add((New-UTUiButton 'Desinstalar' -Dados $d -AoClicar { param($b, $x) $null = $b; Invoke-UTUiProgramAction -Acao Desinstalar -Dados $x }))
    } else {
        $install = New-UTUiButton 'Instalar' -Estilo Primario -Dados $d -AoClicar { param($b, $x) $null = $b; Invoke-UTUiProgramAction -Acao Instalar -Dados $x }
        $install.IsEnabled = [bool]$p.PodeInstalar
        [void]$btns.Children.Add($install)
    }

    $grid = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    [void]$grid.ColumnDefinitions.Add($c1); [void]$grid.ColumnDefinitions.Add($c2)
    [System.Windows.Controls.Grid]::SetColumn($btns, 1)
    [void]$grid.Children.Add($texts); [void]$grid.Children.Add($btns)
    $row = New-Object System.Windows.Controls.Border
    $row.Padding = '4,8'
    $row.BorderBrush = Get-UTUiBrush 'BorderBrush'
    $row.BorderThickness = '0,0,0,1'
    $row.Child = $grid
    return $row
}

function Invoke-UTUiProgramAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Instalar', 'Atualizar', 'Desinstalar')][string]$Acao, [Parameter(Mandatory)][hashtable]$Dados)
    if ($Acao -eq 'Desinstalar' -and (Show-UTUiDialog -Titulo "Desinstalar $($Dados.Nome)?" -Mensagem 'O programa será removido.' -Tipo pergunta -Botoes @('Desinstalar', 'Cancelar')) -ne 'Desinstalar') { return }
    Invoke-UTUiAction -Nome "$Acao $($Dados.Nome)" -Argumentos @{ Id = $Dados.Id; Acao = $Acao } -Script {
        param($Id, $Acao)
        switch ($Acao) {
            'Instalar' { Install-UTProgram -Id $Id }
            'Atualizar' { Update-UTProgram -Id $Id }
            'Desinstalar' { Uninstall-UTProgram -Id $Id -Confirm:$false }
        }
    } -Dados $Dados -Depois {
        param($r, $dd)
        $x = @($r)[-1]
        if ($x -and $x.Mensagem) { [void](Show-UTUiDialog -Titulo $dd.Nome -Mensagem $x.Mensagem -Tipo sucesso) }
        if ($dd.Painel) { Sync-UTUiAsyncPanel -Painel $dd.Painel }
    }
}
#endregion

#region Restaurar and Sobre
function New-UTUiPageRestaurar {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $all = New-UTUiCard -Titulo 'Desfazer tudo' -Icone 'E7A7' -Subtitulo 'Reverte, na ordem inversa, tudo que o Upgrade Tweaks aplicou neste PC, voltando cada valor para o que estava antes.' -Conteudo @(
        (New-UTUiButton 'Desfazer TUDO' -Estilo Perigo -Icone 'E7A7' -AoClicar {
            param($b, $d) $null = $b, $d
            if ((Show-UTUiDialog -Titulo 'Desfazer tudo?' -Mensagem 'Todos os ajustes aplicados pelo Upgrade Tweaks serão revertidos. Alguns só voltam depois de reiniciar.' -Tipo aviso -Botoes @('Desfazer tudo', 'Cancelar')) -ne 'Desfazer tudo') { return }
            [void](Invoke-UTUiJob -Nome 'Desfazendo tudo' -Exclusivo -Script { Undo-UTAllTweak } -Estado @{ Ids = @(); Modo = 'Desfazer' } -AoTerminar {
                    param($R, $E) $null = $E
                    if (-not $R.Ok) { Show-UTUiError -Mensagem $R.Erro; return }
                    [void](Show-UTUiRunSummary -Resultados @($R.Resultado) -Titulo 'Tudo desfeito')
                    Invoke-UTUiStateRefresh
                })
        })
    )
    $bkData = @{}
    $backups = New-UTUiAsyncPanel -Nome 'Backups' -Dados $bkData -Script { Get-UTBackup } -Montar {
        param($R, $D)
        $list = @($R)
        if ($list.Count -eq 0) { return (New-UTUiText 'Nenhum backup ainda. O primeiro é criado antes da primeira alteração.' -Cor MutedBrush) }
        $box = New-UTUiStack
        foreach ($bk in $list) {
            $info = "{0}  -  {1} chaves de registro{2}{3}" -f $bk.Data, $bk.ChavesReg, $(if ($bk.TemServicos) { ', serviços' } else { '' }), $(if ($bk.TemPlano) { ', plano de energia' } else { '' })
            [void]$box.Children.Add((New-UTUiStatusLine -Status Info -Titulo $bk.Nome -Texto $info -Extra (New-UTUiButton 'Restaurar este backup' -Estilo Link -Margem '0,3,0,0' -Dados @{ Pasta = $bk.Pasta; Painel = $D.Painel } -AoClicar {
                            param($b, $d) $null = $b
                            if ((Show-UTUiDialog -Titulo 'Restaurar este backup?' -Mensagem 'Importa de volta as chaves de registro, os serviços e o plano de energia salvos neste backup. Prefira "Desfazer tudo": ele é mais preciso.' -Tipo aviso -Botoes @('Restaurar', 'Cancelar')) -eq 'Restaurar') {
                                Invoke-UTUiAction -Nome 'Restaurar backup' -Exclusivo -Argumentos @{ Pasta = $d.Pasta } -Script { param($Pasta) Restore-UTBackup -Pasta $Pasta } -Sucesso 'Backup restaurado. Reinicie o computador.'
                            }
                        })))
        }
        return $box
    }
    $bkData.Painel = $backups
    $other = New-UTUiWrap
    [void]$other.Children.Add((New-UTUiButton 'Abrir a Restauração do Sistema' -Icone 'E777' -AoClicar { param($b, $d) $null = $b, $d; Open-UTSystemRestore }))
    [void]$other.Children.Add((New-UTUiButton 'Restaurar planos de energia padrão' -Icone 'E945' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiAction -Nome 'Planos padrão' -Script { Restore-UTDefaultPowerScheme } -Sucesso 'Planos padrão restaurados.' }))
    [void]$other.Children.Add((New-UTUiButton 'Abrir a pasta de backups' -Icone 'E8B7' -AoClicar { param($b, $d) $null = $b, $d; Start-Process explorer.exe -ArgumentList (Get-UTPath -Name Backups) }))
    $cards = @($all, (New-UTUiCard -Titulo 'Backups por sessão' -Icone 'E74E' -Conteudo @($backups)), (New-UTUiCard -Titulo 'Outras opções' -Icone 'E713' -Conteudo @($other)))
    if (Test-UTUiVendor -Gpu nvidia) {
        $nv = New-UTUiAsyncPanel -Nome 'Backups NVIDIA' -Script { Get-UTNvidiaBackupFile } -Montar {
            param($R, $D) $null = $D
            $list = @($R)
            if ($list.Count -eq 0) { return (New-UTUiText 'Nenhum backup do driver NVIDIA ainda.' -Cor MutedBrush) }
            New-UTUiStack -Itens @($list | Select-Object -First 8 | ForEach-Object {
                    New-UTUiStatusLine -Status Info -Titulo ([string]$_.Data) -Texto ([string]$_.Arquivo) -Extra (New-UTUiButton 'Restaurar' -Estilo Link -Dados ([string]$_.Arquivo) -AoClicar {
                            param($b, $d) $null = $b
                            if ((Show-UTUiDialog -Titulo 'Restaurar o banco de perfis NVIDIA?' -Mensagem 'Todas as configurações do driver voltam para como estavam neste backup.' -Tipo aviso -Botoes @('Restaurar', 'Cancelar')) -eq 'Restaurar') {
                                Invoke-UTUiAction -Nome 'Restaurar NVIDIA' -Exclusivo -Argumentos @{ Arquivo = $d } -Script { param($Arquivo) Restore-UTNvidiaBackupFile -Arquivo $Arquivo } -Sucesso 'Configurações NVIDIA restauradas.'
                            }
                        })
                })
        }
        $cards += New-UTUiCard -Titulo 'Backups do driver NVIDIA' -Icone 'E7F4' -Conteudo @($nv)
    }
    return (New-UTUiStack -Itens (@((New-UTUiPageHeader -Titulo 'Restaurar' -Descricao 'Tudo que o programa muda pode ser desfeito. O estado original de cada item fica salvo antes da primeira alteração.')) + $cards))
}

function New-UTUiPageSobre {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $about = Get-UTConfig -Name 'sobre'
    $version = [string](Get-UTSyncValue -Key 'Versao')
    $links = New-UTUiWrap -Margem '0,8,0,0'
    [void]$links.Children.Add((New-UTUiButton 'GitHub do projeto' -Icone 'E71B' -Dados ([string]$about.github) -AoClicar { param($b, $d) $null = $b; Open-UTUiLink -Url $d }))
    if ($about.loja) { [void]$links.Children.Add((New-UTUiButton 'Upgrade Store' -Icone 'E719' -Dados ([string]$about.loja) -AoClicar { param($b, $d) $null = $b; Open-UTUiLink -Url $d })) }
    $updateHost = New-Object System.Windows.Controls.Border
    $check = New-UTUiButton 'Verificar nova versão' -Estilo Primario -Icone 'E895' -Dados @{ Host = $updateHost; Versao = $version; Repo = [string]$about.repositorio } -AoClicar {
        param($b, $d) $null = $b
        $d.Host.Child = New-UTUiText 'Consultando o GitHub...' -Cor MutedBrush
        Invoke-UTUiAction -Nome 'Verificar versão' -Argumentos @{ Repo = $d.Repo } -Script { param($Repo) Get-UTGitHubLatestRelease -Repo $Repo } -Dados $d -Depois {
            param($r, $dd)
            $rel = @($r)[0]
            $newer = $false
            try { $newer = ([version]($rel.Versao -replace '[^\d.]', '')) -gt ([version](($dd.Versao -split '-')[0])) } catch { $newer = $rel.Versao -ne $dd.Versao }
            if ($newer) {
                $dd.Host.Child = New-UTUiStack -Itens @(
                    (New-UTUiText "Versão $($rel.Versao) disponível (você está na $($dd.Versao))." -Cor YellowBrush -Peso SemiBold)
                    (New-UTUiText 'Feche o programa e rode o comando de sempre no PowerShell como administrador: ele baixa a versão nova.' -Cor MutedBrush -Quebrar)
                    (New-UTUiButton 'Ver novidades' -Estilo Link -Dados $rel.Pagina -AoClicar { param($b2, $u) $null = $b2; Open-UTUiLink -Url $u })
                )
            } else {
                $dd.Host.Child = New-UTUiText "Você está na versão mais nova ($($dd.Versao))." -Cor GreenBrush
            }
        }
    }
    $cmd = New-Object System.Windows.Controls.TextBox
    $cmd.Text = [string]$about.comando
    $cmd.IsReadOnly = $true
    $cmd.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    $cmd.Margin = '0,6,0,0'
    $cards = @(
        (New-UTUiCard -Titulo "Upgrade Tweaks $version" -Icone 'E946' -Subtitulo 'Otimizador de Windows da Upgrade Store (Porto Alegre/RS), focado em Call of Duty: Warzone.' -Conteudo @($links, $check, $updateHost))
        (New-UTUiCard -Titulo 'Como abrir' -Icone 'E756' -Subtitulo 'No PowerShell como administrador:' -Conteudo @($cmd))
        (New-UTUiCard -Titulo 'Aviso legal' -Icone 'E7BA' -Conteudo @((New-UTUiText ([string]$about.avisoLegal) -Quebrar -Cor MutedBrush)))
        (New-UTUiCard -Titulo 'Créditos' -Icone 'E734' -Conteudo @((New-UTUiText ([string]$about.creditos) -Quebrar -Cor MutedBrush)))
    )
    return (New-UTUiStack -Itens (@((New-UTUiPageHeader -Titulo 'Sobre')) + $cards))
}
#endregion
