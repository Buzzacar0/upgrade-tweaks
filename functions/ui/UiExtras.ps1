# Cards of the Ferramentas tab for the extra system tools and the scheduled RAM cleanup.

function New-UTUiMemoryCleanCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $data = @{}
    $panel = New-UTUiAsyncPanel -Nome 'Limpeza automática da RAM' -Dados $data -Script { Get-UTMemoryCleanTask } -Montar {
        param($R, $D)
        $t = (@($R) | Select-Object -First 1)
        $box = New-UTUiStack
        if ($t.Ativo) {
            $cond = $(if ($t.LimiteMB -gt 0) { " quando sobrar menos de $($t.LimiteMB) MB livres" } else { '' })
            [void]$box.Children.Add((New-UTUiStatusLine -Status 'OK' -Titulo "Ligada: a cada $($t.Minutos) minuto(s)$cond" -Texto 'Roda escondida como tarefa agendada do Windows, mesmo com o Upgrade Tweaks fechado.'))
        } else {
            [void]$box.Children.Add((New-UTUiStatusLine -Status 'Info' -Titulo 'Desligada' -Texto 'O Windows já gerencia o cache sozinho; ligue só se o PC tem pouca RAM e trava depois de horas jogando.'))
        }
        $only = New-Object System.Windows.Controls.CheckBox
        $only.Content = 'Só limpar quando sobrar menos de 1 GB de RAM livre (recomendado)'
        $only.IsChecked = ($t.LimiteMB -gt 0 -or -not $t.Ativo)
        $only.Margin = '0,8,0,6'
        [void]$box.Children.Add($only)
        $btns = New-UTUiWrap
        foreach ($min in 1, 5, 15, 30, 60) {
            [void]$btns.Children.Add((New-UTUiButton $(if ($min -eq 1) { 'A cada 1 minuto' } else { "A cada $min minutos" }) -Dados @{ Minutos = $min; Check = $only; Painel = $D.Painel } -AoClicar {
                        param($b, $d) $null = $b
                        if (Test-UTUiSimulacao -Acao "criar a tarefa agendada que esvazia a memória em espera a cada $($d.Minutos) minuto(s).") { return }
                        $limit = $(if ($d.Check.IsChecked) { 1024 } else { 0 })
                        Invoke-UTUiAction -Nome 'Agendar limpeza da RAM' -Argumentos @{ Minutos = $d.Minutos; Limite = $limit } -Script { param([int]$Minutos, [int]$Limite) Register-UTMemoryCleanTask -Minutos $Minutos -LimiteMB $Limite -Confirm:$false } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                    }))
        }
        if ($t.Ativo) {
            [void]$btns.Children.Add((New-UTUiButton 'Desligar' -Estilo Perigo -Dados $D -AoClicar {
                        param($b, $d) $null = $b
                        Invoke-UTUiAction -Nome 'Desligar limpeza da RAM' -Script { Unregister-UTMemoryCleanTask -Confirm:$false } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                    }))
        }
        [void]$btns.Children.Add((New-UTUiButton 'Limpar agora' -Icone 'E74D' -AoClicar { param($b, $d) $null = $b, $d; Invoke-UTUiAction -Nome 'Limpar memória em espera' -Script { Clear-UTStandbyList -Confirm:$false } -Sucesso 'Memória em espera esvaziada.' }))
        [void]$box.Children.Add($btns)
        return $box
    }
    $data.Painel = $panel
    return (New-UTUiCard -Titulo 'Limpeza automática da RAM' -Icone 'E964' -Subtitulo 'Esvazia a "memória em espera" (cache de arquivos) de tempos em tempos, como o Ghost Mode e o ISLC. Não aumenta o FPS; ajuda só em PCs com pouca RAM onde o cache demora a ser liberado para o jogo.' -Conteudo @($panel))
}

function New-UTUiSystemExtrasCard {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $btns = New-UTUiWrap
    [void]$btns.Children.Add((New-UTUiButton 'Limpar logs de eventos' -Icone 'E74D' -AoClicar {
                param($b, $d) $null = $b, $d
                if ((Show-UTUiDialog -Titulo 'Limpar os logs de eventos?' -Mensagem 'Apaga o histórico do Visualizador de Eventos (erros, avisos, travamentos). Depois disso não dá para investigar problemas antigos.' -Tipo pergunta -Botoes @('Limpar', 'Cancelar')) -ne 'Limpar') { return }
                Invoke-UTUiAction -Nome 'Limpar logs de eventos' -Script { Clear-UTEventLog -Confirm:$false } -Depois { param($r, $dd) $null = $dd; [void](Show-UTUiDialog -Titulo 'Logs de eventos' -Mensagem "$((@($r) | Select-Object -First 1)) logs limpos." -Tipo sucesso) }
            }))
    [void]$btns.Children.Add((New-UTUiButton 'Recriar índice de pesquisa' -Icone 'E721' -AoClicar {
                param($b, $d) $null = $b, $d
                if ((Show-UTUiDialog -Titulo 'Recriar o índice de pesquisa?' -Mensagem 'Resolve a pesquisa do Windows que não acha arquivos ou o indexador usando muito disco. O índice é apagado e refeito em segundo plano (alguns minutos).' -Tipo pergunta -Botoes @('Recriar', 'Cancelar')) -ne 'Recriar') { return }
                Invoke-UTUiAction -Nome 'Recriar índice de pesquisa' -Script { Reset-UTSearchIndex -Confirm:$false } -Sucesso 'Índice apagado; o Windows está recriando.'
            }))
    [void]$btns.Children.Add((New-UTUiButton 'Consertar Explorer lento' -Icone 'EC50' -AoClicar {
                param($b, $d) $null = $b, $d
                if ((Show-UTUiDialog -Titulo 'Redefinir o Explorador de Arquivos?' -Mensagem 'Esquece o modo de exibição salvo de cada pasta, limpa as listas de recentes da barra de tarefas e o histórico do Executar, e reinicia o Explorer. Nenhum arquivo é apagado.' -Tipo pergunta -Botoes @('Redefinir', 'Cancelar')) -ne 'Redefinir') { return }
                Invoke-UTUiAction -Nome 'Redefinir Explorer' -Script { Reset-UTExplorerView -Confirm:$false } -Sucesso 'Explorer redefinido e reiniciado.'
            }))
    [void]$btns.Children.Add((New-UTUiButton 'Testar velocidade do disco C:' -Icone 'EDA2' -AoClicar {
                param($b, $d) $null = $b, $d
                Invoke-UTUiAction -Nome 'Teste de disco (winsat)' -Script { Measure-UTDiskSpeed } -Depois {
                    param($r, $dd) $null = $dd
                    $ci = [Globalization.CultureInfo]::GetCultureInfo('pt-BR')
                    [void](Show-UTUiDialog -Titulo 'Velocidade do disco C:' -Mensagem 'Resultado do winsat (ferramenta do Windows):' -Tipo info -Itens @(@($r) | ForEach-Object { "$($_.Teste): $($_.MBs.ToString('N0', $ci)) MB/s" }))
                }
            }))

    $compactData = @{}
    $compact = New-UTUiAsyncPanel -Nome 'CompactOS' -Dados $compactData -Script { Get-UTCompactOSState } -Montar {
        param($R, $D)
        $on = (@($R) | Select-Object -First 1)
        $box = New-UTUiWrap -Margem '0,8,0,0'
        $label = $(if ($on -eq $true) { 'CompactOS: ligado (Windows comprimido)' } elseif ($on -eq $false) { 'CompactOS: desligado' } else { 'CompactOS: estado desconhecido' })
        [void]$box.Children.Add((New-UTUiText $label -Margem '0,6,12,0'))
        [void]$box.Children.Add((New-UTUiButton $(if ($on -eq $true) { 'Desligar CompactOS' } else { 'Ligar CompactOS' }) -Dados @{ Ligar = ($on -ne $true); Painel = $D.Painel } -AoClicar {
                    param($b, $d) $null = $b
                    if (Test-UTUiSimulacao -Acao $(if ($d.Ligar) { 'comprimir os arquivos do Windows (compact /CompactOS:always).' } else { 'descomprimir os arquivos do Windows (compact /CompactOS:never).' })) { return }
                    $msg = $(if ($d.Ligar) { 'Comprime os arquivos do Windows e libera de 2 a 5 GB no disco C:. Em SSD/NVMe o custo ao abrir programas é desprezível; em HD pode deixar o Windows mais lento. Leva alguns minutos.' } else { 'Descomprime os arquivos do Windows (volta a ocupar de 2 a 5 GB). Leva alguns minutos.' })
                    if ((Show-UTUiDialog -Titulo 'CompactOS' -Mensagem $msg -Tipo pergunta -Botoes @('Continuar', 'Cancelar')) -ne 'Continuar') { return }
                    Invoke-UTUiAction -Nome 'CompactOS' -Exclusivo -Argumentos @{ Ligar = $d.Ligar } -Script { param([bool]$Ligar) Set-UTCompactOS -Ativar $Ligar -Confirm:$false } -Dados $d -Depois {
                        param($r, $dd)
                        $gb = (@($r) | Select-Object -First 1)
                        [void](Show-UTUiDialog -Titulo 'CompactOS' -Mensagem $(if ($dd.Ligar) { "Concluído: $gb GB liberados." } else { 'Concluído.' }) -Tipo sucesso)
                        Sync-UTUiAsyncPanel -Painel $dd.Painel
                    }
                }))
        return $box
    }
    $compactData.Painel = $compact
    return (New-UTUiCard -Titulo 'Mais ferramentas do sistema' -Icone 'E90F' -Subtitulo 'As ferramentas úteis do Ghost Toolbox, com confirmação e explicação. Ativadores de Windows e troca de edição não entram aqui.' -Conteudo @($btns, $compact))
}
