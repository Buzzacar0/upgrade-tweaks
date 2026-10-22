# BIOS tab (info, restart into the BIOS, NVRAM backup, settings map and editor). The Monitor tab
# is in UiMonitor.ps1.

function Test-UTUiSimulacao {
    <#
    .SYNOPSIS
        In simulation mode, says what the action would do and returns $true (the caller stops).
        Used by the actions that change firmware or schedule things outside the tweak engine.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Acao)
    if (-not (Get-UTSyncValue -Key 'Simular')) { return $false }
    [void](Show-UTUiDialog -Titulo 'Modo simulação' -Mensagem "Nada foi alterado. Fora do modo simulação, isto faria: $Acao" -Tipo info)
    return $true
}

#region BIOS
function New-UTUiPageFirmware {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param()
    $page = New-UTUiStack -Itens @((New-UTUiPageHeader -Titulo 'BIOS' -Descricao 'Informações da placa-mãe, reiniciar direto na BIOS, backup da NVRAM e as opções da BIOS lidas e alteradas pelo Windows, sem programas do fabricante. Nada aqui atualiza (grava) a BIOS: só muda o valor de opções que já existem.'))

    $info = New-UTUiAsyncPanel -Nome 'Placa-mãe e BIOS' -Script { Get-UTBiosInfo } -Montar {
        param($R, $D) $null = $D
        $i = (@($R) | Select-Object -First 1)
        $pairs = @(
            , @('Placa-mãe', ("{0} {1}" -f $i.Fabricante, $i.Placa))
            , @('BIOS', ("{0} · versão {1} · {2}" -f $i.BiosMarca, $i.BiosVersao, $i.BiosData))
            , @('Modo de boot', $(if ($i.Uefi) { 'UEFI' } else { 'Legacy (CSM): o editor de opções não funciona neste modo' }))
            , @('Secure Boot', $(if ($i.SecureBoot) { 'Ligado' } elseif ($null -eq $i.SecureBoot) { 'Desconhecido' } else { 'Desligado' }))
        )
        $box = New-UTUiStack -Itens @((New-UTUiKeyValue -Pares $pairs))
        $btns = New-UTUiWrap -Margem '0,10,0,0'
        [void]$btns.Children.Add((New-UTUiButton 'Reiniciar direto na BIOS' -Estilo Perigo -Icone 'E7E8' -AoClicar {
                    param($b, $d) $null = $b, $d
                    if (Test-UTUiSimulacao -Acao 'reiniciar o PC direto na BIOS (shutdown /r /fw).') { return }
                    $ans = Show-UTUiDialog -Titulo 'Reiniciar na BIOS?' -Mensagem 'O PC reinicia em 5 segundos e abre a tela de configuração da BIOS, sem precisar apertar Del/F2. Salve o que estiver aberto.' -Tipo aviso -Botoes @('Reiniciar', 'Cancelar')
                    if ($ans -eq 'Reiniciar') { Invoke-UTUiAction -Nome 'Reiniciar na BIOS' -Script { Restart-UTFirmwareSetup -Confirm:$false } -Sucesso 'O PC vai reiniciar e abrir a BIOS.' }
                }))
        $maker = (@((Get-UTConfig -Name 'bios-guia').fabricantesPlaca | Where-Object { $i.Fabricante -match $_.padrao }) | Select-Object -First 1)
        if ($maker) { [void]$btns.Children.Add((New-UTUiButton "Atualizações da BIOS ($($maker.nome))" -Icone 'E896' -Dados $maker.suporte -AoClicar { param($b, $d) $null = $b; Open-UTUiLink -Url $d })) }
        [void]$box.Children.Add($btns)
        return $box
    }
    [void]$page.Children.Add((New-UTUiCard -Titulo 'Placa-mãe e BIOS' -Icone 'E950' -Conteudo @($info)))

    $backupData = @{}
    $backups = New-UTUiAsyncPanel -Nome 'Backups da NVRAM' -Dados $backupData -Script { @(Get-UTNvramBackup) } -Montar {
        param($R, $D)
        $box = New-UTUiStack
        $list = @($R)
        if ($list.Count -eq 0) { [void]$box.Children.Add((New-UTUiText 'Nenhum backup ainda. Antes de mudar qualquer opção pelo editor o programa faz um automaticamente.' -Cor MutedBrush -Quebrar)) }
        foreach ($bk in ($list | Select-Object -First 8)) {
            $row = New-UTUiWrap -Margem '0,2'
            [void]$row.Children.Add((New-UTUiText ("{0}  ·  BIOS {1}  ·  {2} variáveis  ·  {3}" -f ([datetime]$bk.Criado).ToString('dd/MM/yyyy HH:mm'), $bk.Bios, $bk.Variaveis, $bk.Motivo) -Margem '0,6,12,0'))
            [void]$row.Children.Add((New-UTUiButton 'Restaurar' -Estilo Perigo -Dados @{ Pasta = $bk.Pasta; Painel = $D.Painel } -AoClicar {
                        param($b, $d) $null = $b
                        if (Test-UTUiSimulacao -Acao "gravar de volta na NVRAM as opções da BIOS do backup $($d.Pasta).") { return }
                        $ans = Show-UTUiDialog -Titulo 'Restaurar as opções da BIOS deste backup?' -Mensagem 'Volta, na NVRAM, as variáveis de opções da BIOS que mudaram desde o backup (chaves do Secure Boot e entradas de boot nunca são mexidas). Vale no próximo boot.' -Tipo aviso -Botoes @('Restaurar', 'Cancelar') -TextoConfirmacao 'RESTAURAR'
                        if ($ans -ne 'Restaurar') { return }
                        Invoke-UTUiAction -Nome 'Restaurar NVRAM' -Exclusivo -Argumentos @{ Pasta = $d.Pasta } -Script { param($Pasta) @(Restore-UTNvramBackup -Pasta $Pasta -Confirm:$false) } -Dados $d -Depois {
                            param($r, $dd) $null = $dd
                            $names = @($r)
                            if ($names.Count -eq 0) { [void](Show-UTUiDialog -Titulo 'Nada para restaurar' -Mensagem 'As opções da BIOS estão iguais às do backup.' -Tipo info) }
                            else { [void](Show-UTUiDialog -Titulo 'Restaurado' -Mensagem 'Reinicie o PC para a BIOS usar os valores do backup.' -Tipo sucesso -Itens $names) }
                        }
                    }))
            [void]$row.Children.Add((New-UTUiButton 'Abrir pasta' -Dados $bk.Pasta -AoClicar { param($b, $d) $null = $b; Start-Process explorer.exe -ArgumentList $d }))
            [void]$box.Children.Add($row)
        }
        [void]$box.Children.Add((New-UTUiButton 'Fazer backup agora' -Estilo Primario -Icone 'E74E' -Margem '0,8,0,0' -Dados $D -AoClicar {
                    param($b, $d) $null = $b
                    Invoke-UTUiAction -Nome 'Backup da NVRAM' -Script { Backup-UTNvram -Motivo 'manual' } -Dados $d -Depois { param($r, $dd) $null = $r; Sync-UTUiAsyncPanel -Painel $dd.Painel }
                }))
        return $box
    }
    $backupData.Painel = $backups
    [void]$page.Children.Add((New-UTUiCard -Titulo 'Backup da NVRAM' -Icone 'E74E' -Subtitulo 'Cópia de todas as variáveis que a BIOS guarda (opções, perfis, boot). Fica em ProgramData\UpgradeTweaks\backups\nvram.' -Conteudo @($backups)))

    $mapData = @{}
    $mapPanel = New-UTUiAsyncPanel -Nome 'Mapa da BIOS' -Dados $mapData -Script {
        $map = Get-UTBiosMap
        if ($null -eq $map) { return [pscustomobject]@{ Existe = $false } }
        [pscustomobject]@{ Existe = $true; Criado = [string]$map.Criado; Arquivo = [string]$map.ArquivoBios; Opcoes = @($map.Perguntas).Count; Bios = [string]$map.Bios }
    } -Montar {
        param($R, $D)
        $m = (@($R) | Select-Object -First 1)
        $box = New-UTUiStack
        if ($m.Existe) {
            [void]$box.Children.Add((New-UTUiStatusLine -Status 'OK' -Titulo "Mapa da BIOS $($m.Bios) pronto: $($m.Opcoes) opções" -Texto "Criado em $(([datetime]$m.Criado).ToString('dd/MM/yyyy HH:mm')) a partir de $($m.Arquivo)."))
        } else {
            [void]$box.Children.Add((New-UTUiStatusLine -Status 'Aviso' -Titulo 'Mapa ainda não criado' -Texto 'O mapa diz onde cada opção da BIOS fica guardada. Ele sai do arquivo oficial da BIOS, uma vez só por versão.'))
        }
        $steps = @(
            '1. No site do fabricante da placa-mãe, baixe o arquivo da MESMA versão da BIOS que está instalada (veja a versão acima).'
            '2. Clique em "Criar mapa" e escolha o .zip baixado (ou o arquivo da BIOS de dentro dele).'
            '3. O programa baixa duas ferramentas de código aberto (UEFIExtract e IFRExtractor, menos de 1 MB) e lê o arquivo. Nada é gravado na placa.'
        )
        foreach ($s in $steps) { [void]$box.Children.Add((New-UTUiText $s -Cor MutedBrush -Quebrar -Margem '0,2')) }
        [void]$box.Children.Add((New-UTUiButton $(if ($m.Existe) { 'Criar o mapa de novo...' } else { 'Criar mapa...' }) -Estilo Primario -Icone 'E8E5' -Margem '0,10,0,0' -Dados $D -AoClicar {
                    param($b, $d) $null = $b, $d
                    $file = Get-UTUiFileDialog -Modo Abrir -Filtro 'Arquivo da BIOS (*.zip;*.bin;*.rom;*.cap;*.F*)|*.zip;*.bin;*.rom;*.cap;*.F*|Todos os arquivos (*.*)|*.*'
                    if (-not $file) { return }
                    Invoke-UTUiAction -Nome 'Criando o mapa da BIOS' -Exclusivo -Argumentos @{ Arquivo = $file } -Script { param($Arquivo) New-UTBiosMap -ArquivoBios $Arquivo } -Depois {
                        param($r, $dd) $null = $dd
                        $x = (@($r) | Select-Object -First 1)
                        $msg = "$($x.Opcoes) opções em $($x.Variaveis) variáveis; $($x.Acessiveis) variáveis podem ser lidas e alteradas pelo Windows (as outras só existem durante o boot)."
                        if ($x.VersaoDiferente) { [void](Show-UTUiDialog -Titulo 'O arquivo é de outra versão da BIOS' -Mensagem "Estas variáveis não batem com a BIOS instalada: $($x.VariaveisDiferentes -join ', '). Use o arquivo da mesma versão instalada; até lá, a gravação dessas variáveis fica bloqueada." -Tipo aviso) }
                        else { [void](Show-UTUiDialog -Titulo 'Mapa da BIOS criado' -Mensagem $msg -Tipo sucesso) }
                        $ui = Get-UTUi
                        [void]$ui.Pages.Remove('BIOS')
                        Show-UTUiPage -Id 'BIOS'
                    }
                }))
        return $box
    }
    $mapData.Painel = $mapPanel
    [void]$page.Children.Add((New-UTUiCard -Titulo 'Mapa da BIOS' -Icone 'E8E5' -Conteudo @($mapPanel)))

    if (-not (Test-Path -LiteralPath (Get-UTBiosMapPath))) { return $page }

    $mainData = @{}
    $main = New-UTUiAsyncPanel -Nome 'Opções importantes da BIOS' -Dados $mainData -Carregando 'Lendo as opções na NVRAM...' -Script { @(Get-UTBiosSetting -Destaque) } -Montar {
        param($R, $D)
        $box = New-UTUiStack
        $group = ''
        foreach ($s in (@($R) | Sort-Object Grupo, Titulo)) {
            if ($s.Grupo -ne $group) { $group = $s.Grupo; [void]$box.Children.Add((New-UTUiText $group -Tamanho 12 -Peso SemiBold -Cor AccentLightBrush -Margem '0,10,0,2')) }
            [void]$box.Children.Add((New-UTUiBiosSettingRow -Opcao $s -Painel $D.Painel))
        }
        if (@($R).Count -eq 0) { [void]$box.Children.Add((New-UTUiText 'Nenhuma das opções conhecidas foi encontrada no mapa desta BIOS. Use a busca abaixo.' -Cor MutedBrush -Quebrar)) }
        return $box
    }
    $mainData.Painel = $main
    [void]$page.Children.Add((New-UTUiCard -Titulo 'Opções importantes para jogos' -Icone 'E9F5' -Subtitulo 'Valor gravado na NVRAM agora (o que a BIOS usa no próximo boot). Algumas placas guardam cópias da mesma opção: a marcada como "sem efeito" não é a que a placa usa.' -Conteudo @($main)))

    $searchState = @{ Resultado = $null; Caixa = $null }
    $searchBox = New-Object System.Windows.Controls.TextBox
    $searchBox.MinWidth = 260
    $searchBox.Margin = '0,0,8,8'
    $searchBox.Tag = 'Ex.: C-State, fan, SATA, USB, XHCI...'
    $searchState.Caixa = $searchBox
    $results = New-UTUiStack
    $searchState.Resultado = $results
    $go = New-UTUiButton 'Buscar' -Icone 'E721' -Dados $searchState -AoClicar {
        param($b, $d) $null = $b
        $text = $d.Caixa.Text.Trim()
        if ($text.Length -lt 2) { return }
        $d.Resultado.Children.Clear()
        [void]$d.Resultado.Children.Add((New-UTUiText 'Buscando...' -Cor MutedBrush))
        Invoke-UTUiAction -Nome 'Busca na BIOS' -Argumentos @{ Texto = $text } -Script {
            param($Texto)
            $pattern = [regex]::Escape($Texto)
            @(Get-UTBiosSetting | Where-Object { $_.Nome -match $pattern -or $_.Local -match $pattern } | Select-Object -First 60)
        } -Dados $d -Depois {
            param($r, $dd)
            $dd.Resultado.Children.Clear()
            $list = @($r)
            if ($list.Count -eq 0) { [void]$dd.Resultado.Children.Add((New-UTUiText 'Nada encontrado.' -Cor MutedBrush)); return }
            if ($list.Count -eq 60) { [void]$dd.Resultado.Children.Add((New-UTUiText 'Mostrando as 60 primeiras; refine a busca.' -Cor MutedBrush)) }
            foreach ($s in $list) { [void]$dd.Resultado.Children.Add((New-UTUiBiosSettingRow -Opcao $s -Painel $null)) }
        }
    }
    $searchState.Botao = $go
    (Get-UTUi).BiosBusca = $searchState
    $bar = New-UTUiWrap -Itens @($searchBox, $go)
    [void]$page.Children.Add((New-UTUiCard -Titulo 'Todas as opções (avançado)' -Icone 'E721' -Subtitulo 'Busca em todas as opções visíveis da BIOS, pelo nome em inglês como aparece na tela da BIOS. Mude só o que você conhece.' -Conteudo @($bar, $results)))
    return $page
}

function Start-UTUiBiosSearch {
    # Opens the BIOS tab and runs its "all options" search with the text (from the global search).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only searches; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto)
    Show-UTUiPage -Id 'BIOS'
    $s = (Get-UTUi).BiosBusca
    if ($null -eq $s -or $null -eq $s.Caixa -or $null -eq $s.Botao) { return }
    $s.Caixa.Text = $Texto
    $s.Botao.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    $s.Caixa.BringIntoView()
}
function New-UTUiBiosSettingRow {
    <#
    .SYNOPSIS
        One BIOS setting: name, where it is, explanation, badges, and (when it can be changed from
        Windows) the options and the "Gravar" button.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a UI element; nothing changes on the system.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Opcao, [AllowNull()][object]$Painel)
    $s = $Opcao
    $bd = New-Object System.Windows.Controls.Border
    $bd.BorderBrush = Get-UTUiBrush 'BorderBrush'
    $bd.BorderThickness = '0,0,0,1'
    $bd.Padding = '0,6,0,8'
    $box = New-UTUiStack
    $head = New-UTUiWrap
    [void]$head.Children.Add((New-UTUiText $s.Titulo -Peso SemiBold -Margem '0,0,4,0'))
    if ($s.Titulo -ne $s.Nome) { [void]$head.Children.Add((New-UTUiText "($($s.Nome))" -Cor MutedBrush -Margem '0,0,4,0')) }
    if ($s.Estado -eq 'SomenteNaBios') { [void]$head.Children.Add((New-UTUiBadge 'Só dentro da BIOS' -Cor cinza)) }
    elseif ($s.Estado -eq 'TamanhoDiferente') { [void]$head.Children.Add((New-UTUiBadge 'Mapa de outra versão' -Cor vermelho)) }
    if ($s.Divergente) { [void]$head.Children.Add((New-UTUiBadge 'Cópia sem efeito' -Cor amarelo)) }
    elseif ($s.Estado -eq 'SomenteNaBios' -and $null -ne $s.WindowsConfirma) { [void]$head.Children.Add((New-UTUiBadge $(if ($s.WindowsConfirma) { 'Ativo segundo o Windows' } else { 'Inativo segundo o Windows' }) -Cor $(if ($s.WindowsConfirma) { 'verde' } else { 'amarelo' }))) }
    elseif ($null -ne $s.WindowsConfirma) { [void]$head.Children.Add((New-UTUiBadge 'Confirmado pelo Windows' -Cor verde)) }
    if ($s.Bloqueada) { [void]$head.Children.Add((New-UTUiBadge 'Bloqueada na BIOS' -Cor cinza)) }
    if ($s.Recomendado) { [void]$head.Children.Add((New-UTUiBadge "Sugerido: $($s.Recomendado)" -Cor roxo)) }
    [void]$box.Children.Add($head)
    [void]$box.Children.Add((New-UTUiText ("{0}  ·  {1} @ 0x{2:X}" -f $s.Local, $s.Variavel, $s.Offset) -Tamanho 11 -Cor MutedBrush -Margem '0,2,0,0'))
    if ($s.Explicacao) { [void]$box.Children.Add((New-UTUiText $s.Explicacao -Cor MutedBrush -Quebrar -Margem '0,2,0,0')) }

    $line = New-UTUiWrap -Margem '0,6,0,0'
    $current = $(if ($s.Estado -eq 'SomenteNaBios') { 'não dá para ler pelo Windows' } elseif ($s.ValorTexto) { $s.ValorTexto } else { '-' })
    [void]$line.Children.Add((New-UTUiText "Atual: $current" -Margem '0,6,12,0'))
    if ($s.PadraoTexto) { [void]$line.Children.Add((New-UTUiText "Padrão: $($s.PadraoTexto)" -Cor MutedBrush -Margem '0,6,12,0')) }
    if ($s.Editavel -and -not $s.Bloqueada -and @($s.Opcoes).Count -gt 0) {
        $combo = New-Object System.Windows.Controls.ComboBox
        $combo.MinWidth = 170
        $combo.Margin = '0,0,8,0'
        foreach ($o in @($s.Opcoes)) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = [string]$o.Texto
            $item.Tag = [uint64]$o.Valor
            [void]$combo.Items.Add($item)
            if ($null -ne $s.Valor -and [uint64]$o.Valor -eq [uint64]$s.Valor) { $combo.SelectedItem = $item }
        }
        [void]$line.Children.Add($combo)
        [void]$line.Children.Add((New-UTUiButton 'Gravar' -Estilo Primario -Margem '0,0,0,0' -Dados @{ Opcao = $s; Combo = $combo; Painel = $Painel } -AoClicar {
                    param($b, $d) $null = $b
                    $sel = $d.Combo.SelectedItem
                    if ($null -eq $sel) { return }
                    $new = [uint64]$sel.Tag
                    if ($null -ne $d.Opcao.Valor -and $new -eq [uint64]$d.Opcao.Valor) { return }
                    if (Test-UTUiSimulacao -Acao "gravar '$($d.Opcao.Nome)' = $($sel.Content) na variável $($d.Opcao.Variavel) da NVRAM (posição 0x$('{0:X}' -f $d.Opcao.Offset)).") { return }
                    $msg = "'$($d.Opcao.Nome)': $($d.Opcao.ValorTexto) -> $($sel.Content). Antes de gravar o programa faz um backup completo da NVRAM. A mudança vale no próximo boot. Se o PC não ligar depois, limpe a CMOS (botão ou jumper CLR_CMOS da placa) ou restaure o backup nesta aba."
                    $ans = Show-UTUiDialog -Titulo 'Gravar opção da BIOS?' -Mensagem $msg -Tipo aviso -Botoes @('Gravar', 'Cancelar') -TextoConfirmacao 'EU ENTENDO'
                    if ($ans -ne 'Gravar') { return }
                    Invoke-UTUiAction -Nome 'Gravando opção da BIOS' -Exclusivo -Argumentos @{ Chave = $d.Opcao.Chave; Valor = $new } -Script { param($Chave, [uint64]$Valor) Set-UTBiosSetting -Chave $Chave -Valor $Valor -Confirm:$false } -Dados $d -Depois {
                        param($r, $dd)
                        $x = (@($r) | Select-Object -First 1)
                        $ans2 = Show-UTUiDialog -Titulo 'Opção gravada' -Mensagem "'$($x.Nome)' foi gravada na NVRAM. Reinicie o PC para a BIOS usar o novo valor. Backup: $($x.Backup)" -Tipo sucesso -Botoes @('Reiniciar agora', 'Depois')
                        if ($ans2 -eq 'Reiniciar agora') { Restart-UTUiComputer -Confirm:$false }
                        if ($dd.Painel) { Sync-UTUiAsyncPanel -Painel $dd.Painel }
                    }
                }))
    }
    [void]$box.Children.Add($line)
    $bd.Child = $box
    return $bd
}
#endregion
