# "Início" tab: hardware detection, the checks behind the "Nota de Otimização" and the report
# exported for Upgrade Store service.

function Get-UTHardwareInfo {
    <#
    .SYNOPSIS
        Reads everything the diagnostic needs. Never throws: a section that cannot be read is
        $null and listed in Erros. Also feeds the engine's compatibility context.
    #>
    [CmdletBinding()]
    param([datetime]$Hoje = (Get-Date))

    $errors = New-Object System.Collections.Generic.List[string]
    $cpu = Invoke-UTCollector -Nome 'processador' -Erros $errors -Coletor { Get-UTCpuInfo }
    $gpus = @(Invoke-UTCollector -Nome 'placa de vídeo' -Erros $errors -Coletor { Get-UTGpuInfo -Hoje $Hoje })
    $memory = Invoke-UTCollector -Nome 'memória RAM' -Erros $errors -Coletor { Get-UTMemoryInfo }
    $storage = Invoke-UTCollector -Nome 'armazenamento' -Erros $errors -Coletor { Get-UTStorageInfo }
    $displays = @(Invoke-UTCollector -Nome 'monitores' -Erros $errors -Coletor { Get-UTDisplayInfo })
    $security = Invoke-UTCollector -Nome 'Secure Boot/TPM' -Erros $errors -Coletor { Get-UTSecurityInfo }
    $platform = Invoke-UTCollector -Nome 'tipo de PC' -Erros $errors -Coletor { Get-UTPlatformInfo }
    $settings = Invoke-UTCollector -Nome 'configurações do Windows' -Erros $errors -Coletor { Get-UTSystemSettingsInfo }
    $game = Invoke-UTCollector -Nome 'instalação do Call of Duty' -Erros $errors -Coletor { Get-UTGameInfo -Armazenamento $storage }
    $windows = Invoke-UTCollector -Nome 'versão do Windows' -Erros $errors -Coletor { Get-UTWindowsInfo }

    $gpus = @($gpus | Where-Object { $_ })
    $dedicated = @($gpus | Where-Object { -not $_.Integrada })
    $vendorSource = $gpus
    if ($dedicated.Count -gt 0) { $vendorSource = $dedicated }

    $info = [pscustomobject]@{
        Coletado       = $Hoje
        Computador     = $env:COMPUTERNAME
        Windows        = $windows
        Cpu            = $cpu
        Gpus           = $gpus
        Memoria        = $memory
        Armazenamento  = $storage
        Monitores      = @($displays | Where-Object { $_ })
        Seguranca      = $security
        Plataforma     = $platform
        Sistema        = $settings
        Jogo           = $game
        Erros          = $errors.ToArray()
        # Flat fields read by the engine (Get-UTSystemContext)
        GpuFabricantes = @($vendorSource | ForEach-Object { $_.Fabricante } | Where-Object { $_ -in 'nvidia', 'amd', 'intel' } | Sort-Object -Unique)
        CpuFabricante  = $(if ($cpu -and $cpu.Fabricante -in 'amd', 'intel') { $cpu.Fabricante } else { $null })
        EhNotebook     = $(if ($platform) { $platform.EhNotebook } else { $null })
        Launchers      = $(if ($game) { @($game.Launchers) } else { @() })
        X3D            = $(if ($cpu -and $cpu.X3D.EhX3D) { $cpu.X3D.Tipo } else { $null })
    }

    $sync = Get-Variable -Name UTSync -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $sync) {
        $sync['Hardware'] = $info
        $sync['Contexto'] = $null   # rebuilt from the new hardware on next use
    }
    return $info
}

function New-UTCheck {
    # Pure object factory for one diagnostic line.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds an object; nothing on the system changes.')]
    [CmdletBinding()]
    param(
        [string]$Id, [string]$Titulo,
        [ValidateSet('OK', 'Aviso', 'Problema', 'Info', 'Desconhecido')][string]$Status,
        [string]$Mensagem, [int]$Peso = 0, [string]$Aba = 'Inicio'
    )
    return [pscustomobject]@{ Id = $Id; Titulo = $Titulo; Status = $Status; Mensagem = $Mensagem; Peso = $Peso; Aba = $Aba }
}

function Get-UTDiagnosticCheck {
    <#
    .SYNOPSIS
        Turns the hardware info into checks (OK / Aviso / Problema / Info / Desconhecido),
        each with its weight in the score and the tab that fixes it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Hardware)

    $checks = New-Object System.Collections.Generic.List[object]
    $isLaptop = ($Hardware.EhNotebook -eq $true)

    # Windows
    if ($Hardware.Windows) {
        $s = Get-UTWindowsSupport -Info $Hardware.Windows
        $status = @{ OK = 'OK'; Aviso = 'Aviso'; NaoSuportado = 'Problema' }[$s.Status]
        $checks.Add((New-UTCheck -Id 'windows' -Titulo 'Versão do Windows' -Status $status -Mensagem $s.Mensagem -Peso 5))
    }

    # Secure Boot and TPM (required by Call of Duty / Ricochet)
    $sec = $Hardware.Seguranca
    if ($null -eq $sec -or $null -eq $sec.SecureBoot) {
        $checks.Add((New-UTCheck -Id 'secureboot' -Titulo 'Secure Boot' -Status Desconhecido -Mensagem 'Não foi possível verificar o Secure Boot.' -Peso 10 -Aba 'BIOS'))
    } elseif ($sec.SecureBoot) {
        $checks.Add((New-UTCheck -Id 'secureboot' -Titulo 'Secure Boot' -Status OK -Mensagem 'Secure Boot ligado (exigido pelo anti-cheat do Call of Duty).' -Peso 10 -Aba 'BIOS'))
    } else {
        $checks.Add((New-UTCheck -Id 'secureboot' -Titulo 'Secure Boot' -Status Problema -Mensagem 'Secure Boot desligado. O Call of Duty exige Secure Boot ligado para jogar; ative no BIOS (veja o guia de BIOS).' -Peso 10 -Aba 'BIOS'))
    }
    if ($null -eq $sec -or $null -eq $sec.Tpm.Presente) {
        $checks.Add((New-UTCheck -Id 'tpm' -Titulo 'TPM 2.0' -Status Desconhecido -Mensagem 'Não foi possível verificar o TPM.' -Peso 10 -Aba 'BIOS'))
    } elseif ($sec.Tpm.Presente -and ([string]$sec.Tpm.Versao).StartsWith('2')) {
        $checks.Add((New-UTCheck -Id 'tpm' -Titulo 'TPM 2.0' -Status OK -Mensagem "TPM $($sec.Tpm.Versao) presente." -Peso 10 -Aba 'BIOS'))
    } else {
        $checks.Add((New-UTCheck -Id 'tpm' -Titulo 'TPM 2.0' -Status Problema -Mensagem 'TPM 2.0 não encontrado. O Call of Duty exige TPM 2.0; ative o fTPM (AMD) ou PTT (Intel) no BIOS.' -Peso 10 -Aba 'BIOS'))
    }

    # Memory
    $mem = $Hardware.Memoria
    $modules = @()
    if ($mem) { $modules = @($mem.Modulos | Where-Object { $_ }) }
    if ($modules.Count -gt 0) {
        $configured = ($modules | Measure-Object Configurada -Minimum).Minimum
        $rated = (@($modules | ForEach-Object { $_.Nominal; $_.PartNumberMTs } | Where-Object { $_ }) | Measure-Object -Maximum).Maximum
        $type = $modules[0].Tipo
        $jedecFloor = @{ DDR5 = 4800; DDR4 = 2666; DDR3 = 1600 }[$type]
        if ($rated -and $configured -and $configured -lt ($rated - 100)) {
            $msg = "A memória está rodando a $configured MT/s, mas os pentes são de $rated MT/s. Seu XMP/EXPO parece desativado: ative no BIOS (perfil XMP na Intel, EXPO na AMD) e teste a estabilidade."
            $st = 'Problema'
            if ($isLaptop) { $st = 'Info'; $msg += ' Em notebook isso geralmente não pode ser alterado.' }
            $checks.Add((New-UTCheck -Id 'xmp' -Titulo 'XMP/EXPO' -Status $st -Mensagem $msg -Peso $(if ($isLaptop) { 0 } else { 15 }) -Aba 'BIOS'))
        } elseif ($jedecFloor -and $configured -le $jedecFloor -and -not $isLaptop) {
            $checks.Add((New-UTCheck -Id 'xmp' -Titulo 'XMP/EXPO' -Status Aviso -Mensagem "A memória está a $configured MT/s, a velocidade básica do $type. Se os seus pentes forem mais rápidos, o XMP/EXPO está desligado no BIOS." -Peso 15 -Aba 'BIOS'))
        } else {
            $checks.Add((New-UTCheck -Id 'xmp' -Titulo 'XMP/EXPO' -Status OK -Mensagem "Memória a $configured MT/s ($type), de acordo com o nominal." -Peso $(if ($isLaptop) { 0 } else { 15 }) -Aba 'BIOS'))
        }

        $kinds = @($modules | ForEach-Object { '{0}|{1}|{2}' -f $_.CapacidadeGB, $_.Nominal, $_.PartNumber } | Sort-Object -Unique)
        if ($kinds.Count -gt 1) {
            $checks.Add((New-UTCheck -Id 'pentes' -Titulo 'Pentes de memória' -Status Aviso -Mensagem 'Os pentes são diferentes entre si (capacidade, velocidade ou modelo). Isso pode impedir o XMP/EXPO de funcionar estável; o ideal é um kit igual.' -Peso 5 -Aba 'BIOS'))
        } else {
            $checks.Add((New-UTCheck -Id 'pentes' -Titulo 'Pentes de memória' -Status OK -Mensagem "$($modules.Count) pente(s) iguais." -Peso 5 -Aba 'BIOS'))
        }

        $channels = @($modules | ForEach-Object { $_.Canal } | Where-Object { $_ } | Sort-Object -Unique)
        if ($modules.Count -eq 1) {
            $checks.Add((New-UTCheck -Id 'canal' -Titulo 'Dual channel' -Status $(if ($isLaptop) { 'Aviso' } else { 'Problema' }) -Mensagem 'Só um pente de memória: a RAM trabalha em single channel, o que custa bastante FPS mínimo em jogos como o Warzone. Use dois pentes iguais.' -Peso 10 -Aba 'BIOS'))
        } elseif ($channels.Count -eq 1) {
            $checks.Add((New-UTCheck -Id 'canal' -Titulo 'Dual channel' -Status Aviso -Mensagem "Os pentes parecem estar no mesmo canal ($($channels[0])). Confira no manual da placa-mãe os slots recomendados (geralmente A2 e B2)." -Peso 10 -Aba 'BIOS'))
        } else {
            $checks.Add((New-UTCheck -Id 'canal' -Titulo 'Dual channel' -Status OK -Mensagem 'Memória em dual channel.' -Peso 10 -Aba 'BIOS'))
        }

        if ($mem.TotalGB -lt 15) {
            $checks.Add((New-UTCheck -Id 'ramtotal' -Titulo 'Quantidade de RAM' -Status Aviso -Mensagem "$($mem.TotalGB) GB de RAM. O Warzone recomenda 16 GB ou mais; com menos, espere travadas." -Peso 5))
        } else {
            $checks.Add((New-UTCheck -Id 'ramtotal' -Titulo 'Quantidade de RAM' -Status OK -Mensagem "$($mem.TotalGB) GB de RAM." -Peso 5))
        }
    }

    # Monitors
    $monitors = @($Hardware.Monitores | Where-Object { $_ })
    if ($monitors.Count -gt 0) {
        $slow = @($monitors | Where-Object { $_.HzMaximo -gt $_.HzAtual })
        if ($slow.Count -gt 0) {
            $m = $slow[0]
            $checks.Add((New-UTCheck -Id 'hz' -Titulo 'Taxa de atualização' -Status Problema -Mensagem ("Seu monitor {0} está em {1} Hz, mas suporta {2} Hz. Ajuste em Configurações > Sistema > Tela > Tela avançada." -f $m.Nome, $m.HzAtual, $m.HzMaximo) -Peso 15 -Aba 'Video'))
        } else {
            $list = ($monitors | ForEach-Object { "$($_.Largura)x$($_.Altura) a $($_.HzAtual) Hz" }) -join '; '
            $checks.Add((New-UTCheck -Id 'hz' -Titulo 'Taxa de atualização' -Status OK -Mensagem "Monitores na taxa máxima: $list." -Peso 15 -Aba 'Video'))
        }
    }

    # GPU driver age and HAGS
    $dgpus = @($Hardware.Gpus | Where-Object { $_ -and -not $_.Integrada })
    if ($dgpus.Count -eq 0) { $dgpus = @($Hardware.Gpus | Where-Object { $_ }) }
    foreach ($g in $dgpus) {
        if ($null -eq $g.DiasDriver) { continue }
        if ($g.DiasDriver -gt 90) {
            $checks.Add((New-UTCheck -Id 'driver' -Titulo 'Driver de vídeo' -Status Aviso -Mensagem ("O driver da {0} ({1}) tem {2} dias. Atualize pelo site oficial do fabricante, de preferência com instalação limpa." -f $g.Nome, $g.DriverAmigavel, $g.DiasDriver) -Peso 10 -Aba 'GPU'))
        } else {
            $checks.Add((New-UTCheck -Id 'driver' -Titulo 'Driver de vídeo' -Status OK -Mensagem ("Driver da {0}: {1} ({2} dias)." -f $g.Nome, $g.DriverAmigavel, $g.DiasDriver) -Peso 10 -Aba 'GPU'))
        }
        break
    }
    $sys = $Hardware.Sistema
    $rtxNew = @($dgpus | Where-Object { $_.Fabricante -eq 'nvidia' -and $_.Nome -match 'RTX\s*(40|50)\d{2}' }).Count -gt 0
    if ($sys) {
        if ($rtxNew -and $sys.Hags -eq 'desligado') {
            $checks.Add((New-UTCheck -Id 'hags' -Titulo 'Agendamento de GPU (HAGS)' -Status Aviso -Mensagem 'HAGS desligado. Nas RTX 40/50 ele é recomendado ligado e é obrigatório para o Frame Generation (DLSS 3/4).' -Peso 5 -Aba 'Gaming'))
        } else {
            $hagsText = @{ ligado = 'ligado'; desligado = 'desligado'; padrao = 'no padrão do driver' }[$sys.Hags]
            $checks.Add((New-UTCheck -Id 'hags' -Titulo 'Agendamento de GPU (HAGS)' -Status Info -Mensagem "HAGS $hagsText. Recomendado ligado nas RTX 40/50; nas outras placas, teste ligado e desligado." -Aba 'Gaming'))
        }
        if ($sys.ModoJogo) {
            $checks.Add((New-UTCheck -Id 'modojogo' -Titulo 'Modo de Jogo' -Status OK -Mensagem 'Modo de Jogo ligado.' -Peso 5 -Aba 'Gaming'))
        } else {
            $checks.Add((New-UTCheck -Id 'modojogo' -Titulo 'Modo de Jogo' -Status Aviso -Mensagem 'Modo de Jogo desligado. Ligue na aba Gaming.' -Peso 5 -Aba 'Gaming'))
        }
        if ($sys.GameDvr) {
            $checks.Add((New-UTCheck -Id 'gamedvr' -Titulo 'Gravação em segundo plano' -Status Aviso -Mensagem 'A gravação do Game Bar (Game DVR) está ligada e usa a GPU o tempo todo. Desligue na aba Gaming.' -Peso 5 -Aba 'Gaming'))
        } else {
            $checks.Add((New-UTCheck -Id 'gamedvr' -Titulo 'Gravação em segundo plano' -Status OK -Mensagem 'Game DVR desligado.' -Peso 5 -Aba 'Gaming'))
        }

        $plan = $sys.PlanoEnergia
        if ($plan) {
            $balanced = ($plan.Guid -eq '381b4222-f694-41f0-9685-ff5bb260df2e')
            if ($Hardware.X3D -eq 'duplo') {
                $st = $(if ($balanced) { 'OK' } else { 'Aviso' })
                $msg = $(if ($balanced) { 'Plano Equilibrado, como o Ryzen X3D de dois CCDs precisa.' } else { "Plano '$($plan.Nome)'. Nos Ryzen X3D de dois CCDs use o Equilibrado: o driver da AMD depende dele para usar o CCD com V-Cache." })
                $checks.Add((New-UTCheck -Id 'energia' -Titulo 'Plano de energia' -Status $st -Mensagem $msg -Peso 5 -Aba 'Energia'))
            } elseif ($isLaptop) {
                $checks.Add((New-UTCheck -Id 'energia' -Titulo 'Plano de energia' -Status Info -Mensagem "Plano '$($plan.Nome)'. Em notebook, use o plano Upgrade Warzone só na tomada." -Aba 'Energia'))
            } elseif ($balanced -or $plan.Guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') {
                $checks.Add((New-UTCheck -Id 'energia' -Titulo 'Plano de energia' -Status Aviso -Mensagem "Plano '$($plan.Nome)'. Aplique o plano Upgrade Warzone na aba Energia." -Peso 5 -Aba 'Energia'))
            } else {
                $checks.Add((New-UTCheck -Id 'energia' -Titulo 'Plano de energia' -Status OK -Mensagem "Plano '$($plan.Nome)'." -Peso 5 -Aba 'Energia'))
            }
        }

        $paging = $sys.Paginacao
        if ($paging) {
            if ($paging.Automatica) {
                $checks.Add((New-UTCheck -Id 'paginacao' -Titulo 'Arquivo de paginação' -Status OK -Mensagem 'Gerenciado pelo sistema (recomendado).' -Peso 10 -Aba 'Ferramentas'))
            } elseif (@($paging.Arquivos).Count -eq 0 -and -not $paging.EmUso) {
                $checks.Add((New-UTCheck -Id 'paginacao' -Titulo 'Arquivo de paginação' -Status Problema -Mensagem 'O arquivo de paginação está desativado. Isso causa fechamentos do Call of Duty por falta de memória; volte para "gerenciado pelo sistema" na aba Ferramentas.' -Peso 10 -Aba 'Ferramentas'))
            } else {
                $checks.Add((New-UTCheck -Id 'paginacao' -Titulo 'Arquivo de paginação' -Status Aviso -Mensagem 'Arquivo de paginação com tamanho personalizado. Se o jogo fechar sozinho, volte para "gerenciado pelo sistema".' -Peso 10 -Aba 'Ferramentas'))
            }
        }
    }

    # Storage: TRIM, system drive, game drive
    $storage = $Hardware.Armazenamento
    if ($storage) {
        $hasSsd = @($storage.Discos | Where-Object { $_.Tipo -in 'SSD', 'NVMe' }).Count -gt 0
        if ($hasSsd) {
            if ($null -eq $storage.TrimAtivo) {
                $checks.Add((New-UTCheck -Id 'trim' -Titulo 'TRIM' -Status Desconhecido -Mensagem 'Não foi possível verificar o TRIM.' -Peso 5 -Aba 'Ferramentas'))
            } elseif ($storage.TrimAtivo) {
                $checks.Add((New-UTCheck -Id 'trim' -Titulo 'TRIM' -Status OK -Mensagem 'TRIM ativo nos SSDs.' -Peso 5 -Aba 'Ferramentas'))
            } else {
                $checks.Add((New-UTCheck -Id 'trim' -Titulo 'TRIM' -Status Problema -Mensagem 'TRIM desativado: o SSD perde desempenho com o tempo. Reative na aba Ferramentas.' -Peso 5 -Aba 'Ferramentas'))
            }
        }
        $systemLetter = ([string]$env:SystemDrive).TrimEnd(':')
        $sysVol = @($storage.Volumes | Where-Object { $_.Letra -eq $systemLetter })[0]
        if ($sysVol) {
            $freePct = if ($sysVol.TotalGB -gt 0) { [math]::Round(100 * $sysVol.LivreGB / $sysVol.TotalGB) } else { 100 }
            if ($sysVol.LivreGB -lt 30 -or $freePct -lt 10) {
                $checks.Add((New-UTCheck -Id 'discosistema' -Titulo 'Espaço no disco do Windows' -Status Aviso -Mensagem "Só $($sysVol.LivreGB) GB livres no ${systemLetter}: ($freePct%). Pouco espaço deixa o Windows lento e atrapalha atualizações; use a limpeza na aba Ferramentas." -Peso 5 -Aba 'Ferramentas'))
            } else {
                $checks.Add((New-UTCheck -Id 'discosistema' -Titulo 'Espaço no disco do Windows' -Status OK -Mensagem "$($sysVol.LivreGB) GB livres no ${systemLetter}:." -Peso 5 -Aba 'Ferramentas'))
            }
        }
    }

    $game = $Hardware.Jogo
    $installs = @()
    if ($game) { $installs = @($game.Instalacoes | Where-Object { $_ }) }
    if ($installs.Count -eq 0) {
        $checks.Add((New-UTCheck -Id 'jogo' -Titulo 'Call of Duty' -Status Info -Mensagem 'Call of Duty não encontrado (Steam, Battle.net ou Xbox App). Os ajustes do Windows funcionam mesmo assim.' -Aba 'Warzone'))
    } else {
        $names = @{ steam = 'Steam'; battlenet = 'Battle.net'; xbox = 'Xbox App/Game Pass' }
        foreach ($inst in $installs) {
            $label = "$($names[$inst.Launcher]) em $($inst.Caminho)"
            $d = $inst.Disco
            if ($d -and $d.TipoDisco -eq 'HDD') {
                $checks.Add((New-UTCheck -Id 'jogohdd' -Titulo 'Disco do jogo' -Status Problema -Mensagem "O Call of Duty está num HD mecânico ($label). Isso causa carregamento lento e texturas atrasadas; mova o jogo para um SSD ou NVMe." -Peso 15 -Aba 'Warzone'))
            } elseif ($d) {
                $checks.Add((New-UTCheck -Id 'jogohdd' -Titulo 'Disco do jogo' -Status OK -Mensagem "Call of Duty no $($d.TipoDisco) ($label)." -Peso 15 -Aba 'Warzone'))
            }
            if ($d -and $d.LivreGB -lt 20) {
                $checks.Add((New-UTCheck -Id 'jogoespaco' -Titulo 'Espaço para atualizações do jogo' -Status Problema -Mensagem "Só $($d.LivreGB) GB livres no disco do jogo ($($d.Letra):). As atualizações do Call of Duty costumam pedir dezenas de GB." -Peso 5 -Aba 'Warzone'))
            } elseif ($d -and $d.LivreGB -lt 50) {
                $checks.Add((New-UTCheck -Id 'jogoespaco' -Titulo 'Espaço para atualizações do jogo' -Status Aviso -Mensagem "$($d.LivreGB) GB livres no disco do jogo ($($d.Letra):). Deixe pelo menos 50 GB para as atualizações." -Peso 5 -Aba 'Warzone'))
            } elseif ($d) {
                $checks.Add((New-UTCheck -Id 'jogoespaco' -Titulo 'Espaço para atualizações do jogo' -Status OK -Mensagem "$($d.LivreGB) GB livres no disco do jogo." -Peso 5 -Aba 'Warzone'))
            }
            break
        }
    }

    # Information only
    if ($sec -and $null -ne $sec.Hvci) {
        if ($sec.Hvci) {
            $checks.Add((New-UTCheck -Id 'vbs' -Titulo 'Integridade da Memória (HVCI)' -Status Info -Mensagem 'Ligada. Protege o Windows contra drivers maliciosos e pode custar alguns % de FPS em parte dos jogos. O Upgrade Tweaks não desliga isso automaticamente; veja a aba Latência.' -Aba 'Latencia'))
        } else {
            $checks.Add((New-UTCheck -Id 'vbs' -Titulo 'Integridade da Memória (HVCI)' -Status Info -Mensagem 'Desligada.' -Aba 'Latencia'))
        }
    }
    $cpu = $Hardware.Cpu
    if ($cpu -and $cpu.X3D.EhX3D) {
        $text = $(if ($cpu.X3D.Tipo -eq 'duplo') {
                "$($cpu.Nome): Ryzen X3D de dois CCDs. Mantenha o plano Equilibrado, o Game Bar e o driver de chipset da AMD atualizado; o programa respeita isso automaticamente."
            } else {
                "$($cpu.Nome): Ryzen X3D de um CCD. Pode usar o plano Upgrade Warzone normalmente; mantenha o driver de chipset da AMD atualizado."
            })
        $checks.Add((New-UTCheck -Id 'x3d' -Titulo 'Processador X3D' -Status Info -Mensagem $text -Aba 'Energia'))
    }

    return $checks.ToArray()
}

function Get-UTDiagnostic {
    <#
    .SYNOPSIS
        Full diagnostic: hardware, checks, "Nota de Otimização" (0-100) and pending items.
    .DESCRIPTION
        Score = weighted share of OK checks; Aviso counts half, Problema zero. Info and
        Desconhecido do not count.
    #>
    [CmdletBinding()]
    param([psobject]$Hardware)

    if ($null -eq $Hardware) { $Hardware = Get-UTHardwareInfo }
    $checks = @(Get-UTDiagnosticCheck -Hardware $Hardware)

    $total = 0.0
    $points = 0.0
    foreach ($c in $checks) {
        if ($c.Peso -le 0 -or $c.Status -notin 'OK', 'Aviso', 'Problema') { continue }
        $total += $c.Peso
        if ($c.Status -eq 'OK') { $points += $c.Peso }
        elseif ($c.Status -eq 'Aviso') { $points += $c.Peso / 2 }
    }
    $score = 100
    if ($total -gt 0) { $score = [int][math]::Round(100 * $points / $total) }

    $severity = @{ Problema = 0; Aviso = 1 }
    $pending = @($checks | Where-Object { $_.Status -in 'Problema', 'Aviso' } |
        Sort-Object @{ Expression = { $severity[$_.Status] } }, @{ Expression = { $_.Peso }; Descending = $true })

    return [pscustomobject]@{
        Nota       = $score
        Pendencias = $pending
        Verificacoes = $checks
        Hardware   = $Hardware
    }
}

function ConvertTo-UTHtmlText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][object]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Get-UTHardwareSummaryLine {
    <#
    .SYNOPSIS
        Label/value pairs that describe the PC, shared by the TXT and HTML reports.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Hardware)

    $lines = New-Object System.Collections.Generic.List[object]
    function Add-Line([string]$label, [string]$value) { $lines.Add([pscustomobject]@{ Rotulo = $label; Valor = $value }) }

    if ($Hardware.Windows) { Add-Line 'Windows' $Hardware.Windows.Descricao }
    $c = $Hardware.Cpu
    if ($c) {
        $x3d = ''
        if ($c.X3D.EhX3D) { $x3d = $(if ($c.X3D.Tipo -eq 'duplo') { ' - X3D, dois CCDs' } else { ' - X3D, um CCD' }) }
        Add-Line 'Processador' ("{0} ({1} núcleos / {2} threads){3}" -f $c.Nome, $c.Nucleos, $c.Threads, $x3d)
    }
    foreach ($g in @($Hardware.Gpus | Where-Object { $_ })) {
        $vram = $(if ($g.VramGB) { ", $($g.VramGB) GB" } else { '' })
        $date = $(if ($g.DriverData) { $g.DriverData.ToString('dd/MM/yyyy') } else { '?' })
        Add-Line 'Placa de vídeo' ("{0}{1} - driver {2} de {3}" -f $g.Nome, $vram, $g.DriverAmigavel, $date)
    }
    $m = $Hardware.Memoria
    if ($m) {
        $mods = ($m.Modulos | ForEach-Object { "{0} GB {1} {2}/{3} MT/s ({4})" -f $_.CapacidadeGB, $_.Tipo, $_.Configurada, $_.Nominal, $_.Slot }) -join '; '
        Add-Line 'Memória' ("{0} GB: {1}" -f $m.TotalGB, $mods)
    }
    if ($Hardware.Armazenamento) {
        foreach ($d in @($Hardware.Armazenamento.Discos)) { Add-Line 'Disco' ("{0} ({1}, {2} GB)" -f $d.Nome, $d.Tipo, $d.TamanhoGB) }
    }
    foreach ($mon in @($Hardware.Monitores | Where-Object { $_ })) {
        Add-Line 'Monitor' ("{0}: {1}x{2} a {3} Hz (máx. {4} Hz)" -f $mon.Nome, $mon.Largura, $mon.Altura, $mon.HzAtual, $mon.HzMaximo)
    }
    if ($Hardware.Plataforma) {
        Add-Line 'Tipo' $(if ($Hardware.Plataforma.EhNotebook) { 'Notebook' } else { 'Desktop' })
        if ($Hardware.Plataforma.PlacaMae) { Add-Line 'Placa-mãe' $Hardware.Plataforma.PlacaMae }
    }
    if ($Hardware.Jogo) {
        foreach ($i in @($Hardware.Jogo.Instalacoes)) { Add-Line 'Call of Duty' ("{0}: {1}" -f $i.Launcher, $i.Caminho) }
    }
    return $lines.ToArray()
}

function Export-UTDiagnosticReport {
    <#
    .SYNOPSIS
        Saves the diagnostic as .txt or .html (chosen by the extension of -Path).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [psobject]$Diagnostico
    )

    if ($null -eq $Diagnostico) { $Diagnostico = Get-UTDiagnostic }
    $hw = $Diagnostico.Hardware
    $version = [string](Get-UTSyncValue -Key 'Versao')
    $when = $hw.Coletado.ToString('dd/MM/yyyy HH:mm')
    $summary = @(Get-UTHardwareSummaryLine -Hardware $hw)
    $statusText = @{ OK = 'OK'; Aviso = 'Atenção'; Problema = 'Problema'; Info = 'Info'; Desconhecido = 'Não verificado' }

    if ($Path -match '\.html?$') {
        $rows = ($summary | ForEach-Object { "<tr><th>$(ConvertTo-UTHtmlText $_.Rotulo)</th><td>$(ConvertTo-UTHtmlText $_.Valor)</td></tr>" }) -join "`n"
        $checks = ($Diagnostico.Verificacoes | ForEach-Object {
                "<tr class=""s-$($_.Status)""><td><span class=""tag"">$(ConvertTo-UTHtmlText $statusText[$_.Status])</span></td><td><b>$(ConvertTo-UTHtmlText $_.Titulo)</b><br>$(ConvertTo-UTHtmlText $_.Mensagem)</td></tr>"
            }) -join "`n"
        $content = @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Diagnóstico Upgrade Tweaks - $(ConvertTo-UTHtmlText $hw.Computador)</title>
<style>
body{background:#0B0F1E;color:#E5E7EB;font-family:'Segoe UI',sans-serif;margin:0;padding:32px}
h1{color:#A78BFA;margin:0 0 4px} .sub{color:#9CA3AF;margin-bottom:24px}
.nota{display:inline-block;background:#7C3AED;color:#fff;font-size:40px;font-weight:700;border-radius:14px;padding:12px 24px;margin-bottom:24px}
.card{background:#141A33;border-radius:12px;padding:16px 20px;margin-bottom:20px}
table{width:100%;border-collapse:collapse} th{text-align:left;color:#A78BFA;width:170px;vertical-align:top;padding:6px 8px} td{padding:6px 8px;vertical-align:top}
tr+tr td,tr+tr th{border-top:1px solid #232B4D}
.tag{display:inline-block;min-width:96px;text-align:center;border-radius:6px;padding:2px 8px;font-size:13px;font-weight:600}
.s-OK .tag{background:#14532D;color:#86EFAC} .s-Aviso .tag{background:#713F12;color:#FDE68A} .s-Problema .tag{background:#7F1D1D;color:#FCA5A5}
.s-Info .tag,.s-Desconhecido .tag{background:#1F2937;color:#D1D5DB}
footer{color:#6B7280;font-size:12px;margin-top:24px}
</style></head><body>
<h1>Diagnóstico Upgrade Tweaks</h1>
<div class="sub">$(ConvertTo-UTHtmlText $hw.Computador) - $when - Upgrade Tweaks $(ConvertTo-UTHtmlText $version)</div>
<div class="nota">Nota $($Diagnostico.Nota)/100</div>
<div class="card"><table>
$rows
</table></div>
<div class="card"><table>
$checks
</table></div>
<footer>Gerado pelo Upgrade Tweaks - Upgrade Store, Porto Alegre/RS.</footer>
</body></html>
"@
    } else {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('DIAGNÓSTICO UPGRADE TWEAKS')
        [void]$sb.AppendLine(("{0} - {1} - versão {2}" -f $hw.Computador, $when, $version))
        [void]$sb.AppendLine(('NOTA DE OTIMIZAÇÃO: {0}/100' -f $Diagnostico.Nota))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== Computador ==')
        foreach ($l in $summary) { [void]$sb.AppendLine(('{0,-16} {1}' -f ($l.Rotulo + ':'), $l.Valor)) }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('== Verificações ==')
        foreach ($c in $Diagnostico.Verificacoes) {
            [void]$sb.AppendLine(('[{0}] {1}: {2}' -f $statusText[$c.Status], $c.Titulo, $c.Mensagem))
        }
        if (@($hw.Erros).Count -gt 0) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('== Não foi possível ler ==')
            foreach ($e in $hw.Erros) { [void]$sb.AppendLine(" - $e") }
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Gerado pelo Upgrade Tweaks - Upgrade Store, Porto Alegre/RS.')
        $content = $sb.ToString()
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Salvar relatório de diagnóstico')) {
        $folder = Split-Path -Parent $Path
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
        [IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($true)))
        Write-UTLog -Level Sucesso -Message "Relatório salvo em $Path"
    }
    return $Path
}
