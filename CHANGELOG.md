# Changelog

Todas as mudanças relevantes do Upgrade Tweaks ficam registradas aqui.
O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto usa [versionamento semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- **Design system** em `xaml/Theme/` (`Claro.xaml`, `Escuro.xaml`, `Controles.xaml`): tokens de cor, tipografia Segoe UI Variable, raios e espaçamentos em grade de 8; estilos de switch animado, botões primário/secundário/destrutivo, lista agrupada, card, sheet, campo de busca e selos. Cores sempre por `DynamicResource`.
- Tema claro e escuro (ou igual ao Windows) e cor de destaque configurável, com o roxo da Upgrade Store como padrão; Mica atrás da barra lateral no Windows 11 e fundo sólido no Windows 10.
- Janela nova: barra de título integrada com os botões do Windows à direita, barra lateral estilo Ajustes do macOS (seções, ícones em squircle, busca no topo, Ctrl+K), barra de ação flutuante, transição suave entre páginas (respeita "reduzir animações"), confirmações em sheet dentro da janela.
- A janela lembra tamanho, posição, última página e tema (`%AppData%\UpgradeTweaks\ui.json`).
- Galeria de componentes: `-Galeria` ou Ctrl+Shift+G.
- Ajustes em listas agrupadas por risco, cada um com switch (ligado = aplicado), ganho em uma linha e botão ⓘ com descrição, risco, aviso e o que muda no registro/serviços.
- Fluxo revisar → aplicar: ligar ou desligar só cria uma pendência ("Será aplicado" / "Será desfeito"); "Revisar e aplicar" calcula em simulação exatamente o que vai mudar, mostra num sheet e só então aplica e desfaz na mesma rodada, com progresso e resumo.
- Início novo: anel com a Nota de Otimização, card "Otimizar agora" com o preset, pendências com "Resolver", resumo do PC e o que já está certo.
- Busca global (Ctrl+K): abas, ajustes, sensores lidos agora e opções da BIOS (quando o mapa já foi carregado), com atalho para cada resultado.
- **Monitor personalizável** (`%AppData%\UpgradeTweaks\monitor.json`): layouts Essencial, Gamer, Completo e Personalizado (regras em `config/monitor-layouts.json`), exportar/importar o layout em JSON, favoritos no topo, nome próprio por sensor, ocultar e reordenar arrastando os cartões (num layout pronto isso cria o Personalizado a partir do que está na tela).
- Monitor em cartões com gráfico dos últimos 60 valores ou em tabela com mínimo, máximo e média; resumo dos núcleos (uma linha com a média em vez de uma por núcleo) e sensores que só marcam zero escondidos (as duas coisas opcionais).
- Alertas por sensor (acima/abaixo de um valor) e alertas padrão (processador 90 °C, placa de vídeo 85 °C, hotspot 105 °C, SSD 70 °C), com notificação do Windows no máximo uma vez por minuto por sensor e margem de 3 unidades para rearmar.
- °C ou °F, 0 a 2 casas decimais, atualização de 250 ms a 2 s, relatório CSV (separado por ";", abre direto no Excel) e log CSV com uma linha por leitura.
- Uso de CPU medido com a janela no Monitor (Ryzen 7 9800X3D): 0,5% no padrão (Essencial, 1 s), 1,3% no Gamer a 250 ms e 1,6% no Completo a 250 ms.
- **Overlay** (aba nova e processo próprio, `-Overlay`): FPS, 1% e 0,1% low, frametime, gráfico de frametime, CPU/GPU (temperatura e uso), RAM, VRAM, relógio e modo de apresentação por cima do jogo. Os quadros vêm do **PresentMon oficial da Intel** (baixado da Release do GitHub e guardado só com a assinatura digital da Intel), que lê os eventos ETW do Windows: nada é injetado no jogo.
- Janela do overlay sempre no topo e "clique-através" (`WS_EX_TRANSPARENT | LAYERED | TOOLWINDOW | NOACTIVATE`), DPI por monitor, escolha do monitor (o do jogo, o principal ou um específico) e 8 posições.
- Editor visual com prévia ao vivo: perfis (novo, duplicar, renomear, excluir), posição, tamanho, opacidade, fundo, cor, layout vertical ou horizontal e os itens na ordem escolhida; perfil automático por jogo (`cod.exe` usa o Competitivo); atalhos globais (mostrar/esconder, próximo perfil, benchmark).
- Ícone ao lado do relógio com o menu do overlay, opção de abrir com o Windows (tarefa agendada sem UAC), aviso de tela cheia exclusiva, texto opcional pelo RivaTuner (RTSS) e integração com o Modo Partida (liga o overlay e desliga no fim).
- Uso de CPU medido com um jogo de teste a ~175 FPS e o perfil Completo: overlay 0,35–0,44% e PresentMon 0,01–0,03% da CPU total.
- **Benchmark** (aba nova): grava os frametimes de um jogo pela aba (com tempo para voltar ao jogo) ou com **Ctrl+Shift+F12** dentro do jogo (o overlay mostra "● REC"); resumo com FPS médio, 1% e 0,1% low, P1, mínimo, máximo, frametime e engasgos; gráfico de frametime; CSV para o Excel; **comparação de duas gravações** com a diferença em % de cada métrica. Gravações em `%AppData%\UpgradeTweaks\benchmarks`.
- README com as medições de CPU, como cada número é calculado e a seção nova do anti-cheat sobre o overlay; roteiro de teste manual do Monitor, overlay e benchmark.

> **[Print: Início]** `docs/img/inicio.png` · **[Print: Gaming]** `docs/img/gaming.png` · **[Print: Monitor]** `docs/img/monitor.png` · **[Print: Overlay]** `docs/img/overlay.png` · **[Print: Benchmark]** `docs/img/benchmark.png`

### Mudado
- Checklists, a contagem de 15 s da taxa do monitor e as confirmações viraram sheets dentro da janela (janela própria só antes de a interface abrir).
- Programas da inicialização com switch em vez de caixa de seleção.
- Leitura dos sensores mais leve: um objeto por sensor reaproveitado a cada leitura, nomes calculados uma vez por sessão e discos (SMART) lidos no máximo a cada 5 s. O relatório `.txt` do Monitor deu lugar ao CSV.
- Nomes de sensores por tipo ("Temperatura da GPU" e "Uso da GPU" em vez de dois "Núcleo da GPU") e da memória ("Memória RAM").
- Plano de energia: o plano personalizado das versões anteriores deu lugar ao **Desempenho Máximo** nativo do Windows (liberado com `powercfg -duplicatescheme` só quando está escondido, sem criar cópias; Alto Desempenho quando a edição não permite). Na primeira execução, o plano antigo é apagado (com o Desempenho Máximo ativado no lugar quando ele era o ativo) e sai do diário de ajustes.
- Os valores que eram do plano antigo viraram ajustes avulsos e opcionais sobre o plano ativo (`UT_Power_Ajuste_*`), fora dos presets.
- Aba Energia: botão "Ativar Desempenho Máximo", seletor com todos os planos instalados e "Restaurar planos padrão do Windows".

## [0.2.0] - 2026-10-22

### Adicionado
- Aba **Monitor**: sensores em tempo real (LibreHardwareMonitorLib + driver PawnIO, instalados sob demanda), com mínimo/máximo, filtro por dispositivo, relatório `.txt`, rótulos e multiplicadores do chip da placa (`config/sensores-placas.json`) e resumo do hardware no estilo CPU-Z.
- Aba **BIOS**: reiniciar direto na BIOS (`shutdown /r /fw`), backup/restauração da NVRAM e editor de opções da BIOS pelo Windows. O mapa (`state\bios\<placa>_<versão>.json`) é criado do arquivo oficial da BIOS com UEFIExtract e IFRExtractor-RS; as condições SuppressIf/GrayOutIf são avaliadas com os valores atuais; menus de outras famílias AMD são filtrados; cópias que divergem do Windows são marcadas; gravação só com backup, confirmação "EU ENTENDO" e leitura de volta. Opções destacadas em `config/bios-ajustes.json`.
- Ferramentas do Ghost Toolbox que fazem sentido: limpar logs de eventos, recriar índice de pesquisa, redefinir o Explorer, CompactOS, teste de disco (winsat) e limpeza automática da memória em espera por tarefa agendada (opcional, só abaixo de 1 GB livre).
- Ajustes novos (`config/tweaks-sistema.json`): agrupar serviços do svchost, abrir programas da inicialização sem espera, tirar o desfoque do login, destaques da pesquisa do Bing, "Tomar posse" e plano de energia no botão direito, Modo Deus e .NET Framework 3.5.
- Programas novos: Visual C++ 2005–2022, DirectX, .NET Desktop 8/9, Steam, Battle.net, Epic, EA app, Ubisoft Connect, GOG GALAXY, Magpie, Lossless Scaling (página), CapFrameX, Brave, Firefox, Chrome, VLC, MPC-HC, PotPlayer, NanaZip, WinRAR, OBS e Discord.

## [0.1.0] - 2026-10-22

### Adicionado
- Pesquisa de referências (WinUtil, vídeos, NVAPI, winget) em `docs/pesquisa.md`.
- Estrutura do repositório.
- Inicialização (`scripts/start.ps1`): elevação obrigatória com UAC (inclusive via `irm | iex`), relançamento em 64 bits, TLS 1.2, checagem da versão do Windows, pastas em `%ProgramData%\UpgradeTweaks` e banner.
- Log diário em `logs\AAAA-MM-DD.log` (UTF-8), seguro para vários runspaces, com rotação de 30 dias.
- Compilação mínima (`scripts/compile.ps1`) que gera um `upgradetweaks.ps1` único e 100% ASCII.
- Testes Pester 5 e configuração do PSScriptAnalyzer.
- Helpers de registro (tipos exatos, visão 64 bits, valor padrão, redirecionamento de HKCU para o usuário que vai jogar) e de serviços (tipo de inicialização real, incluindo "Automático (atraso)", via `sc.exe`).
- Estado original (`state\estado-original.json`): guarda o valor real antes da primeira alteração, desfaz só quando o último tweak que usa o item é desfeito e remove apenas as chaves criadas pelo programa.
- Registro dos tweaks aplicados (`state\aplicados.json`) para o "Desfazer TUDO" na ordem inversa.
- Backup por sessão em `backups\AAAA-MM-DD_HHmm\`: `.reg` de cada chave, `servicos.json`, plano de energia ativo (`.pow`) e `manifesto.json`.
- Ponto de restauração antes da primeira alteração (liga a Proteção do Sistema se estiver desligada e contorna o limite de 24 h).
- Funções da aba Restaurar: desfazer tudo pelo estado salvo, listar e restaurar backups, restaurar planos de energia padrão e abrir a Restauração do Sistema.
- Mensagens de erro amigáveis em PT-BR (detalhe técnico só no log).
- Motor de tweaks (`Invoke-UTTweak`, `Undo-UTTweak`, `Get-UTTweakState`, `Undo-UTAllTweak`): checagem de admin a cada aplicação, compatibilidade com o hardware, confirmação de risco alto, simulação com lista de ações, desfazer automático quando um ajuste falha no meio, grupos exclusivos e resumo final em PT-BR.
- Esquema do `tweaks.json` documentado em `docs/esquema-tweaks.md` e validado em teste (inclui `ausenteEquivale` para padrões do Windows).
- Detecção do usuário que vai jogar quando o UAC é aprovado com outra conta de administrador.
- Primeiros ajustes: Game DVR desligado, Modo de Jogo ligado e aceleração do mouse desligada.
- Diagnóstico de hardware (aba Início): CPU com detecção de Ryzen X3D de um ou dois CCDs (`config/cpu-x3d.json`), GPUs com idade do driver e VRAM real, RAM (XMP/EXPO, pentes diferentes, dual channel), discos (NVMe/SSD/HD, TRIM, espaço), monitores com taxa atual e máxima (nome real pelo EDID), Secure Boot, TPM, VBS/HVCI, HAGS, Modo de Jogo, Game DVR, plano de energia, arquivo de paginação e notebook/desktop.
- Detecção do Call of Duty na Steam, Battle.net e Xbox App/Game Pass, com executáveis e disco do jogo.
- "Nota de Otimização" de 0 a 100 com pendências ordenadas por gravidade e a aba que resolve cada uma.
- Relatório de diagnóstico em TXT ou HTML para o atendimento.
- Plano de energia "Upgrade Warzone" (`config/powerplan.json`, cada configuração com o motivo): cópia do Desempenho Máximo (com Alto Desempenho e Equilibrado como alternativas), processador a 100%, boost agressivo, sem estacionamento de núcleos e sem economia em USB, PCIe, SATA/NVMe e disco; desligar vídeo configurável. Configurações que não existem no Windows são puladas.
- Ryzen X3D de dois CCDs: o plano não é aplicado; um ajuste próprio mantém o Equilibrado e confere driver de chipset da AMD, Game Bar e Modo de Jogo.
- Notebook: plano "Upgrade Warzone (na tomada)" baseado no Equilibrado, mudando só os valores com carregador.
- Ajustes de Energia: plano Upgrade Warzone, X3D de dois CCDs, mostrar configurações ocultas, IDLEDISABLE (risco alto) e desativar hibernação.
- Ferramentas da aba Energia: voltar ao plano anterior, exportar e importar `.pow`.
- Simulação de ajustes feitos por script agora mostra cada valor atual -> novo (`scriptSimular`).
- Ajuste que não se aplica ao PC aparece como "não se aplica", mesmo quando o sistema por acaso coincide.
- Catálogo completo (145 ajustes) dividido em `config/tweaks-*.json`: Gaming, Warzone, Latência e sistema, Rede, Serviços e Apps, Privacidade, Visual e Personalizar, mais os gerados de `services.json`, `apps-debloat.json` e `dns.json`.
- Modo Lite (`config/modo-lite.json`): debloat agressivo mostrado como lista antes de aplicar, sem serviços do Xbox, Spooler, Store, Game Bar, Defender ou Windows Update.
- Gerenciador de inicialização, ferramentas de rede (teste de latência/jitter/perda, DNS, reset de rede) e dispositivos opcionais.
- Ajustes que compartilham valores agora se seguram mutuamente: desfazer um não desfaz o outro.
- Aba GPU, NVIDIA: leitura e gravação direta no banco de perfis do driver (NVAPI DRS, sem depender do Painel de Controle aposentado) com o perfil que a NVIDIA já tem para o Call of Duty ou um perfil próprio "Upgrade Tweaks - Warzone"; tabela atual × recomendado (`config/nvidia-drs.json`, cada opção com explicação), V-Sync/G-SYNC/limite de FPS conforme o monitor, backup `.txt` do DRS antes de gravar e restaurar padrões.
- Faixa dinâmica Completa (0-255) por monitor, taxa de atualização máxima do monitor (testada antes de aplicar), power limit máximo via `nvidia-smi` (risco alto, só desktop) e status do Resizable BAR.
- Ferramentas da aba GPU: limpar cache de shaders (NVIDIA, AMD, Intel e DirectX) com o espaço liberado, páginas oficiais de driver, checklists de AMD, Intel, NVIDIA App e DDU (`config/gpu-guia.json`) e instalação guiada "só o driver de vídeo" da NVIDIA.
- Aba Warzone: localiza o arquivo de configuração do jogo, faz backup/restauração, altera só chaves que já existem (ex.: `RendererWorkerCount` = núcleos físicos) e guia de configurações do jogo por placa e VRAM (`config/warzone-guia.json`).
- Exclusão do jogo e do cache de shaders no Windows Defender (sem desligar o Defender), desfeita removendo só o que foi adicionado.
- Modo Partida (`config/modo-partida.json`): fecha os programas marcados, ativa o plano Upgrade Warzone (Equilibrado em X3D de dois CCDs) e, ao desligar, volta o plano e reabre os programas sem privilégio de administrador. Limpeza da memória em espera fica opcional e com aviso honesto.
- Diagnóstico: avisos de monitor em faixa Limitada e de Resizable BAR desligado.
- Aba Programas (`config/programs.json`, editável sem mexer no código): 19 programas de overclock/monitoramento, GPU/driver, latência e utilitários, com origem (link), versão instalada e atualização disponível. Instalar, atualizar e desinstalar pelo winget (id exato, silencioso); sem winget, a última Release do GitHub do projeto, sem versão ou hash fixos. Programas sem canal oficial (Ryzen Master, MSI Utility v3, Interrupt Affinity Policy Tool) só abrem a página. Todos abrem como administrador.
- NVIDIA Profile Inspector: gera o perfil recomendado do Warzone em `.nip` e importa em silêncio, com backup completo do driver antes.
- Aba Ferramentas: limpeza de temporários mostrando o espaço liberado (Windows Update com os serviços parados e devolvidos ao estado anterior; lixeira opcional), Limpeza de Disco (`cleanmgr /sagerun`, sem a pasta Downloads nem a instalação anterior do Windows), `DISM /StartComponentCleanup`, `sfc /scannow` e `DISM /RestoreHealth` com saída no log, otimizar unidades (TRIM em SSD/NVMe, desfragmentar só HD), pausar o Windows Update por 7/14/35 dias (no máximo 35) e atalhos do sistema.
- Ajuste "Arquivo de paginação gerenciado pelo sistema" (categoria Ferramentas), com desfazer para o tamanho que estava.
- Guia de BIOS (`config/bios-guia.json`): XMP/EXPO, Resizable BAR, CSM, Secure Boot, TPM, PBO, Curve Optimizer, FCLK, Memory Context Restore, modo ECO, notas de X3D, limites Intel e temperaturas, filtrado pelo processador e marcado com o que o diagnóstico já confirmou; link de suporte do fabricante da placa-mãe e do driver de chipset.
- Interface gráfica WPF (`xaml/MainWindow.xaml`) com o tema da Upgrade Store (#0B0F1E, cards #141A33, roxo #7C3AED/#A78BFA, Segoe UI), mínimo 1100x700 e abas laterais com ícones: Início, Energia, Gaming, Latência, Rede, Serviços e Apps, Privacidade, GPU, Warzone, Ferramentas, Programas, Personalizar, Restaurar e Sobre.
- Cada ajuste com caixa de marcação, selos de risco, "requer reinício" e "controverso", estado atual (aplicado / não aplicado / não se aplica) e dica com descrição, ganho esperado e cuidados; busca em todas as abas sem diferenciar acentos.
- Barra superior com "Aplicar selecionados", "Desfazer selecionados" e "Simular (não altera nada)"; confirmação listando cada ajuste de risco alto (aplicar, pular ou cancelar); resumo final com falhas e o motivo, e "Reiniciar agora" quando precisa.
- Depois de mudar a taxa de atualização do monitor, um aviso de 15 segundos volta a taxa anterior sozinho se ninguém confirmar (tela preta).
- Todo trabalho pesado roda num pool de runspaces; a tela recebe o resultado e o log por um temporizador, sem travar. Painel de log colorido por nível, recolhível, com "Copiar log" e "Abrir pasta de logs".
- Abas com ferramentas: diagnóstico e nota na Início (com exportar relatório), plano de energia, teste de latência/jitter e comparação de DNS, Modo Lite e inicialização, tabela NVIDIA atual × recomendado, Modo Partida, arquivo de configuração e guia de gráficos do jogo, limpeza/reparo/discos/Windows Update/BIOS, catálogo de programas, backups e "Desfazer TUDO", e verificação de nova versão na aba Sobre (`config/sobre.json`).
- Modo simulação (`-Simular`) com faixa de aviso: "Aplicar" só mostra o que seria feito.
- Presets Seguro, Competitivo e Extremo (`config/presets.json`, lista explícita de ajustes; Extremo pede "EU ENTENDO"). Personalização, escolha de DNS, alternativas (HAGS, MPO), serviços do Xbox, Spooler e apps de uso comum (Paint, Relógio, Media Player...) nunca entram em preset. Botão grande "Otimizar agora com o preset Seguro" na tela Início e seletor de preset na barra de cima.
- Exportar e importar a seleção de ajustes em JSON (tela Início ou `-Config`), para padronizar o atendimento.
- Modo linha de comando: `-Preset`, `-Config`, `-DesfazerTudo`, `-Diagnostico`/`-ExportarRelatorio`, `-Simular` e `-Silencioso`, com códigos de saída 0/1/2/3010. Risco alto pede "EU ENTENDO" digitado (pulado no `-Silencioso`) e a taxa do monitor nunca é mudada sem alguém na tela.
- GitHub Actions: analisador, testes no Windows PowerShell 5.1 e no PowerShell 7, README conferido com o catálogo e compilação a cada push; tag `v*.*.*` testa, compila e publica a Release com `upgradetweaks.ps1` e o SHA256.
- README completo em PT-BR (aba por aba, presets, linha de comando, anti-cheat, como desfazer, FAQ) com a tabela de todos os ajustes gerada do catálogo (`scripts/build-docs.ps1`, chamado pelo `compile.ps1`), logo e capturas de tela.
- Ícone da janela em vetor (XAML).
- Roteiro de teste manual em VM antes da primeira Release (`docs/teste-manual.md`) e teste de ponta a ponta do arquivo compilado no CI (diagnóstico e simulação dos três presets).

- **AMD:** as configurações do AMD Software (Anti-Lag, Chill, Boost, AFMF, Radeon Super Resolution, Enhanced Sync, V-Sync, FRTC, anti-aliasing, filtragem anisotrópica, tesselação e FreeSync) são gravadas direto no driver pela ADLX, a biblioteca oficial da AMD; a filtragem de textura vai para o registro do driver (`UMD\TFQ`). Ajuste "Configurações AMD recomendadas", no preset Seguro.
- **Intel Arc:** baixa latência, V-Sync, Endurance Gaming, limitador de FPS e download de shaders pré-compilados gravados pela Intel Graphics Control Library (oficial). Ajuste "Configurações Intel Arc recomendadas", no preset Seguro.
- **DDU automático:** escolhe o instalador do driver novo e o programa bloqueia o Windows Update de instalar driver, reinicia em Modo de Segurança sem internet, roda o DDU sozinho, volta ao Windows normal, abre o instalador e desfaz o bloqueio. A flag do Modo de Segurança é retirada antes de qualquer outra coisa, para o PC nunca ficar preso nele.
- **Gráficos do jogo:** o guia (competitivo ou equilíbrio) é gravado direto no arquivo de configuração do Call of Duty, nas duas cópias que o jogo mantém, com backup e só com valores que o próprio arquivo lista como válidos. O que não tem chave segura é mostrado para ajustar no menu.
- Os guias passo a passo de AMD, Intel, NVIDIA App, DDU e "só o driver" foram trocados por essas ações automáticas.

### Corrigido
- A leitura de estado não roda mais a detecção de ajustes que não se aplicam ao PC (evita avisos de hardware que não existe).
- "Desfazer TUDO" sem nada aplicado agora só avisa, em vez de mostrar um resumo vazio.
- O modo de desenvolvimento (`Set-StrictMode -Version Latest`) quebrava ao ler campos opcionais dos JSON, ao pegar o primeiro item de listas vazias e ao somar tamanhos de pastas vazias. Os campos opcionais agora recebem valores padrão ao carregar cada configuração, e a suíte de testes roda sempre em modo estrito.
- O arquivo de configuração do Call of Duty não era encontrado quando a pasta Documentos foi movida para o OneDrive (o jogo continua gravando em `%USERPROFILE%\Documents`).
