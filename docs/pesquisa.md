# Pesquisa e mapeamento de referências (Fase 0)

> Data da pesquisa: 2026-10-20. Este documento registra o que foi verificado antes de escrever código,
> o que muda em relação ao documento de requisitos original e de onde veio cada informação.
> Nada aqui foi aplicado na máquina de desenvolvimento — só leituras.

## 1. Ambiente de desenvolvimento

| Item | Situação |
|---|---|
| Windows | 11 Enterprise 25H2 (build 26200) |
| PowerShell | 5.1.26100 (não há PowerShell 7 instalado) |
| Pester | 5.7.1 instalado no usuário (o 3.4 nativo continua lá; os testes importam `-RequiredVersion 5.7.1`) |
| PSScriptAnalyzer | 1.25.0 instalado no usuário |
| GPU de teste (só leitura) | RTX 5070, driver **617.42**, power limit 250 W (máx. 300 W) |
| CoD instalado | Steam, `H:\SteamLibrary\steamapps\common\Call of Duty HQ` |
| Pasta Documentos | Redirecionada para o OneDrive (`OneDrive\Documentos`) |

**Consequência:** a pasta Documentos sempre é resolvida com `[Environment]::GetFolderPath('MyDocuments')`,
nunca com `$env:USERPROFILE\Documents` (no PC de teste isso apontaria para o lugar errado).

## 2. WinUtil (Chris Titus Tech) — o que aprendemos

Repositório clonado em `_ref/winutil` (fora do projeto). Licença MIT, © 2022 CT Tech Group LLC.
**Nenhum código foi copiado**; usamos apenas fatos técnicos (chaves de registro, valores) e ideias de arquitetura.

### 2.1 Arquitetura

- **Compilação:** `Compile.ps1` concatena todos os `functions/**/*.ps1`, embute cada `config/*.json` como
  here-string (`@'...'@ | ConvertFrom-Json`) e o XAML da mesma forma, gerando um único `winutil.ps1`.
  Vamos fazer o mesmo, mais logo em base64 e a tabela do README.
- **Elevação:** se não for admin, gera um bootstrap em `-EncodedCommand` que baixa de novo o script da
  Release (`irm .../releases/latest/download/winutil.ps1`) e relança com `Start-Process -Verb RunAs`,
  repassando os parâmetros; quando há `-Preset/-Config`, espera o processo elevado e devolve o exit code.
  **Decisão:** seguiremos o pedido original (baixar para `%TEMP%\UpgradeTweaks\upgradetweaks.ps1` e relançar com
  `-File`), que mantém o arquivo exato executado e facilita repassar parâmetros. UAC recusado → mensagem em PT-BR e saída com código 1.
- **Presets:** `preset.json` é só uma lista de ids por preset (`Standard`, `Minimal`, `Advanced`). Nosso
  `presets.json` terá a mesma ideia, mais regras de hardware (X3D, notebook, Game Pass).
- **Runspaces:** pool de runspaces com `$sync` sincronizado (`[Hashtable]::Synchronized`) e atualização
  da UI via Dispatcher. Mesmo padrão aqui.
- **MPO:** WinUtil modela como combobox (Ativado / Desativado compatibilidade = `OverlayTestMode=5` /
  Totalmente desativado = `+ DisableOverlays=1`). Ver ressalva na seção 5.

### 2.2 Mapeamento tweak a tweak

Legenda da decisão: **Portar** (entra no nosso catálogo), **Adaptar** (entra com mudança), **Não portar**.

| WinUtil | Decisão | Id Upgrade Tweaks | Aba | Observação |
|---|---|---|---|---|
| Activity History - Disable | Portar | `UT_Privacy_ActivityHistory_Off` | Privacidade | |
| Hibernation - Disable | Portar | `UT_Power_Hibernation_Off` | Energia | Explicar Inicialização Rápida |
| Widgets - Remove | Adaptar | `UT_Win11_Widgets_Off` | Privacidade | Política `AllowNewsAndInterests=0` (reversível); remoção do pacote só no Modo Lite |
| Start Menu Previous Layout | Não portar | — | — | Não funciona em builds novas; não é desempenho |
| Store Recommended Search - Disable | Não portar | — | — | Mexe na permissão do banco da Store (`store.db`), que a Store recria; efeito instável |
| Location Tracking - Disable | Portar | `UT_Privacy_Location_Off` | Privacidade | Inclui serviço `lfsvc` |
| Services - Set to Manual | Adaptar | `UT_Services_*` (via `services.json`) | Serviços e Apps | `SvcHostSplitThresholdInKB` entra separado, marcado controverso (menos processos svchost, ganho de FPS ~nulo) |
| Brave - Debloat | Portar | `UT_Privacy_BraveDebloat` | Privacidade | Opcional |
| RDP Unsigned Warnings | Não portar | — | — | Segurança, fora do escopo |
| Edge - Debloat | Portar | `UT_Privacy_EdgeDebloat` | Privacidade | Só políticas, reversível |
| ConsumerFeatures - Disable | Portar | `UT_Privacy_ConsumerFeatures_Off` | Privacidade | |
| Telemetry - Disable | Adaptar | `UT_Privacy_Telemetry_Min` | Privacidade | Ver bugs na seção 2.3; envio de amostras do Defender vira tweak separado |
| Delivery Optimization - Disable | Portar | `UT_Net_DeliveryOptimization_Off` | Rede | |
| Edge - Remove | Adaptar | `UT_Lite_RemoveEdge` | Serviços e Apps (Modo Lite) | Risco alto; preservar WebView2; desfazer via winget `Microsoft.Edge` |
| BitLocker - Disable | Adaptar | `UT_Sys_BitLocker_Off` | Latência e Sistema | Risco alto; desfazer correto exige protetor TPM |
| Date & Time UTC | Não portar | — | — | Só para dual boot |
| OneDrive - Remove | Portar | `UT_Lite_RemoveOneDrive` | Serviços e Apps (Modo Lite) | Desfazer via winget `Microsoft.OneDrive` |
| Explorer Home/Gallery - Disable | Portar | `UT_Custom_ExplorerThisPC` | Personalizar | |
| Visual Effects - Best Performance | Adaptar | `UT_Visual_BestPerformance` | Visual | Manter fontes suavizadas e miniaturas; tirar os itens de barra de tarefas que o WinUtil mistura |
| Reserved Storage - Disable | Portar | `UT_Sys_ReservedStorage_Off` | Latência e Sistema | Avisar para reativar antes de atualização grande |
| Restore Point - Create | Adaptar | (módulo de backup) | Restaurar | Parte do fluxo obrigatório, não é tweak |
| End Task with Right Click | Portar | `UT_Custom_EndTaskTaskbar` | Personalizar | Útil quando o jogo trava |
| Storage Sense - Disable | Portar | `UT_Sys_StorageSense_Off` | Latência e Sistema | |
| Windows AI - Disable/Remove | Adaptar | `UT_Privacy_Recall_Off`, `UT_Privacy_Copilot_Off`, `UT_Privacy_ClickToDo_Off` | Privacidade | Usar as políticas oficiais (seção 5.4) |
| WPBT - Disable | Portar | `UT_Privacy_WPBT_Off` | Privacidade | |
| Prevent Device Companion Apps | Portar | `UT_Apps_DeviceMetadata_Off` | Serviços e Apps | |
| Razer Auto-Install - Disable | Adaptar | `UT_Apps_RazerBlock` | Serviços e Apps | `SearchOrderConfig=0` também impede o Windows Update de baixar drivers de dispositivos novos → risco médio, avisar |
| Logitech Download Assistant | Portar | `UT_Apps_LogiBlock` | Serviços e Apps | |
| Notifications & Calendar - Disable | Portar | `UT_Custom_Notifications_Off` | Personalizar | Também no Modo Lite |
| Adobe URL Block | Não portar | — | — | Lista de hosts de terceiros, fora do escopo |
| Right-Click Menu Previous Layout | Portar | `UT_Custom_ClassicContextMenu` | Personalizar | |
| Disk Cleanup - Run | Adaptar | ação da aba Ferramentas | Ferramentas | `/ResetBase` impede desinstalar updates → opção separada com aviso |
| Temporary Files - Remove | Adaptar | ação da aba Ferramentas | Ferramentas | Mostrar espaço liberado |
| IPv4 preferred | Portar | `UT_Net_PreferIPv4` | Rede | |
| Teredo - Disable | Adaptar | `UT_Net_Teredo_Off` | Rede | **Bloqueado quando o launcher é Xbox App** (Teredo é usado pela rede Xbox) |
| IPv6 - Disable | Adaptar | `UT_Net_IPv6_Off` | Rede | Risco alto, desmarcado; a Microsoft não recomenda |
| Background Apps - Disable | Portar | `UT_Privacy_BackgroundApps_Off` | Privacidade | |
| Explorer Folder Auto Discovery | Não portar | — | — | Apaga as preferências de visualização de todas as pastas, sem como desfazer |
| BSoD verbose, Logon verbose | Portar | `UT_Custom_VerboseBSoD`, `UT_Custom_VerboseLogon` | Personalizar | |
| Battery %, Dark Theme, File Ext., Hidden Files, Scrollbars, Num Lock, Snapping, Settings Home, Login Blur, Lock Screen, Taskbar alignment/search/task view, Long Paths | Portar | `UT_Custom_*` | Personalizar | |
| New Outlook | Não portar | — | — | Não é desempenho |
| Multiplane Overlay | Adaptar | `UT_Gaming_MPO` (seletor) | Gaming | Ver seção 5.2 |
| Mouse Acceleration | Portar | `UT_Gaming_MouseAccel_Off` | Gaming | |
| S0 Sleep Network | Portar | `UT_Power_ModernStandbyNetwork_Off` | Energia | Só notebooks com Modern Standby |
| S3 Sleep | Não portar | — | — | Depende de firmware; risco de não acordar |
| Bing Search, Start Recommendations | Portar | `UT_Privacy_BingSearch_Off`, `UT_Privacy_StartRecommendations_Off` | Privacidade | |
| Sticky Keys | Portar | `UT_Gaming_StickyKeys_Off` | Gaming | Inclui Filtragem e Alternância |
| Game Mode | Portar | `UT_Gaming_GameMode_On` | Gaming | |
| O&O ShutUp10++ | Adaptar | catálogo de programas | Programas | winget `OO-Software.ShutUp10` (verificado na Fase 8; hoje se chama "O&O ShutUp10" v3) |
| DNS | Adaptar | seletor de DNS | Rede | Mesma lista (Cloudflare, Google, Quad9, OpenDNS, AdGuard) + DHCP |
| Ultimate Performance | Usar o nativo | `Invoke-UTMaxPerformanceCore` | Energia | Desempenho Máximo do Windows (desde a v0.3) |
| Fixes (rede, winget, Windows Update) | Portar | ações da aba Ferramentas | Ferramentas | Reset Winsock/TCP-IP, reparo do winget |

### 2.3 Erros encontrados no WinUtil que não vamos repetir

1. **Telemetria:** o script faz `Set-Service -Name wermgr`, mas `wermgr` é um executável, não um serviço.
   O serviço de relatório de erros é o **`WerSvc`**.
2. **BitLocker (desfazer):** `Enable-BitLocker -MountPoint C:` sem protetor falha. O desfazer precisa
   de `-TpmProtector` (e avisar que a criptografia inteira vai rodar de novo).
3. **Telemetria (honestidade):** `AllowTelemetry=0` só é respeitado nas edições Enterprise/Education.
   Em Home/Pro o Windows trata como 1 ("Obrigatório"). A descrição vai dizer isso.
4. **Visual Effects:** o tweak mistura efeitos visuais com botões da barra de tarefas (Task View, pesquisa,
   Chat). Separamos.

## 3. Vídeos de referência

Transcrições baixadas com `yt-dlp` (só legendas, sem vídeo).

### 3.1 "GHOST SPECTRE - SUPERLITE WINDOWS" (TheLite)

O vídeo é a instalação de uma ISO modificada (não fazemos isso). O que aproveitamos:

| Ideia no vídeo | O que vira no Upgrade Tweaks |
|---|---|
| Edição "SuperLite" + "Ghost Mode" (reduz processos de 114 para 77) | **Modo Lite** (seção 7.4 do pedido), num Windows original |
| Ghost Toolbox instala VC++ AIO e DirectX runtime | Novo item na aba Programas: **"Runtimes essenciais"** (winget `Microsoft.VCRedist.2015+.x64`, `Microsoft.DirectX`) |
| DDU com "impedir downloads de driver pelo Windows Update" | Fluxo "Instalar só o driver NVIDIA" (passo DDU) |
| NVCleanstall: desativar telemetria do instalador e do driver, instalação limpa, desativar Ansel, desativar HDCP, timer de suspensão do HD Audio, opção "MPO off", método compatível com anti-cheat, prioridade de interrupção normal | Mesmo fluxo; vamos documentar cada opção em PT-BR. **Não** usar "prioridade de interrupção alta" |
| Configurações NVIDIA: baixa latência On (Ultra só com CPU forte), desempenho máximo, filtragem "alto desempenho", V-Sync off, cache de shader 10 GB/ilimitado | Coincide com a tabela do pedido; entra no `nvidia-drs.json` |
| Ajustar Hz do monitor para o máximo | Já previsto no diagnóstico |
| Planos "Game Turbo"/"Dynamic Boost" | Desempenho Máximo nativo + ajustes avulsos |
| **"Limpar memória a cada 5 minutos"** | **Não entra** — é limpador de RAM, mito proibido pela regra 4 |

**Achado importante do vídeo:** o autor diz que o driver NVIDIA mais novo (6xx) não traz mais o
Painel de Controle. Confirmado na web — ver seção 5.1.

### 3.2 "I Paid ChatGPT $100 to Optimize My PC" (Premfn)

Teste caseiro (Fortnite, sem metodologia controlada). O que foi feito no vídeo:

| Ajuste | Avaliação | No Upgrade Tweaks |
|---|---|---|
| Limpar a poeira do PC | Não mudou FPS no vídeo, mas evita thermal throttling | Guia de hardware: limpeza + checar temperaturas no HWiNFO |
| Atualizar drivers | Real | Diagnóstico avisa driver com mais de 3 meses |
| Reativar o Game Bar | Necessário em X3D de CCD duplo | Já previsto |
| Tela cheia exclusiva em vez de janela sem borda | Pode reduzir latência em alguns jogos | Guia in-game do Warzone |
| Reduzir processos (123 → 117) | Efeito mínimo | Modo Partida / Modo Lite, sem prometer FPS |
| OC de GPU (+90 core) com Afterburner, testado no OCCT | Ganho real e pequeno; exige teste de estabilidade | Aba Programas + guia (manual, risco alto) |
| PBO Advanced testado no OCCT | Real, exige teste | Guia de BIOS |

Resultado mostrado: máximos de ~900 → ~1000 FPS numa única rodada. O próprio autor atribui o pouco ganho
a já ter usado o WinUtil antes. Nada novo que precise de tweak próprio.

## 4. IDs e fontes verificados

### 4.1 winget (verificado com `winget show --id <id> -e` em 2026-10-20)

| Programa | Id winget | Situação |
|---|---|---|
| MSI Afterburner | `Guru3D.Afterburner` | OK |
| RivaTuner Statistics Server | `Guru3D.RTSS` | OK |
| HWiNFO64 | `REALiX.HWiNFO` | OK |
| OCCT | `OCBase.OCCT.Personal` | OK |
| CPU-Z | `CPUID.CPU-Z` | OK |
| GPU-Z | `TechPowerUp.GPU-Z` | OK |
| NVIDIA Profile Inspector | `Orbmu2k.nvidiaProfileInspector` | OK (v3.0.2.3); também tem Release no GitHub |
| DDU | `Wagnardsoft.DisplayDriverUninstaller` | OK |
| NVCleanstall | `TechPowerUp.NVCleanstall` | OK |
| Autoruns | `Microsoft.Sysinternals.Autoruns` | OK |
| Process Lasso | `BitSum.ProcessLasso` | OK |
| 7-Zip | `7zip.7zip` | OK |
| Everything | `voidtools.Everything` | OK |
| CrystalDiskInfo | `CrystalDewWorld.CrystalDiskInfo` | OK |
| CrystalDiskMark | `CrystalDewWorld.CrystalDiskMark` | OK |
| O&O ShutUp10 | `OO-Software.ShutUp10` | OK (verificado em 2026-10-21; nome atual sem "++", v3.6) |
| VC++ 2015+ x64 | `Microsoft.VCRedist.2015+.x64` | OK |
| DirectX End-User Runtime | `Microsoft.DirectX` | OK |
| Edge / OneDrive / WebView2 | `Microsoft.Edge`, `Microsoft.OneDrive`, `Microsoft.EdgeWebView2Runtime` | OK (usados nos "desfazer") |
| **AMD Ryzen Master** | — | **Não existe no winget.** Só "abrir página oficial da AMD" |
| **Intel Graphics Software** | — | Não encontrado no winget. Só "abrir página oficial" |
| **MSI Utility v3** | — | Sem canal oficial (anexo de fórum). Só "abrir página"; o modo MSI é feito nativamente pelo programa |
| **Interrupt Affinity Policy Tool** | — | Download antigo da Microsoft removido. Só "abrir página" com explicação |

### 4.2 NVAPI (headers oficiais `NVIDIA/nvapi`, licença MIT)

Ids para `nvapi_QueryInterface` (arquivo `nvapi_interface.h`):

| Função | Id |
|---|---|
| NvAPI_Initialize | `0x0150E828` |
| NvAPI_Unload | `0xD22BDD7E` |
| NvAPI_SYS_GetDriverAndBranchVersion | `0x2926AAAD` |
| NvAPI_EnumPhysicalGPUs | `0xE5AC921F` |
| NvAPI_GPU_GetFullName | `0xCEEE8E9F` |
| NvAPI_Disp_ColorControl | `0x92F9D80D` |
| NvAPI_DISP_GetDisplayConfig / SetDisplayConfig | `0x11ABCCF8` / `0x5D8CF8DE` |
| NvAPI_DRS_CreateSession / DestroySession | `0x0694D52E` / `0xDAD9CFF8` |
| NvAPI_DRS_LoadSettings / SaveSettings | `0x375DBD6B` / `0xFCBC7E14` |
| NvAPI_DRS_SaveSettingsToFile / LoadSettingsFromFile | `0x2BE25DF8` / `0xD3EDE889` |
| NvAPI_DRS_GetBaseProfile | `0xDA8466A0` |
| NvAPI_DRS_FindProfileByName / FindApplicationByName | `0x7E4A9A0B` / `0xEEE566B2` |
| NvAPI_DRS_CreateProfile / CreateApplication | `0xCC176068` / `0x4347A9DE` |
| NvAPI_DRS_GetSetting / SetSetting | `0x73BF8338` / `0x577DD202` |
| NvAPI_DRS_DeleteProfileSetting | `0xE4A26362` |
| NvAPI_DRS_RestoreProfileDefaultSetting | `0x53F0381E` |

`NvAPI_DRS_SaveSettingsToFile` dá um **backup completo do banco de perfis** antes de qualquer alteração —
vamos usar além do backup por configuração em JSON.

Configurações (arquivo `NvApiDriverSettings.h`, salvo onde indicado):

| Configuração | Id | Valores relevantes |
|---|---|---|
| Gerenciamento de energia | `0x1057EB71` | 0 adaptável · **1 preferir desempenho máximo** · 5 energia ideal |
| Sincronização vertical | `0x00A879CF` | `0x60925292` app controla · **`0x08416747` desligado** · `0x47814940` ligado |
| Taxa máxima de quadros | `0x10835002` | 0 desligado · 1–1023 FPS |
| Taxa de atualização preferencial | `0x0064B541` | 0 app controla · **1 mais alta disponível** |
| Cache de shader (tamanho, em MB) | `0x00AC8497` | padrão do header `0x4000` (16 GB) · `0xFFFFFFFF` ilimitado |
| Filtragem de textura - qualidade | `0x00CE2691` | `0xFFFFFFF6` alta qualidade · 0 qualidade · 10 desempenho · **20 (`0x14`) alto desempenho** |
| Filtragem - otimização trilinear | `0x002ECAF2` | 1 ligado |
| Filtragem - otimização de amostra anisotrópica | `0x00E73211` | 1 ligado |
| Filtragem - desvio LOD negativo | `0x0019BB68` | 0 permitir · 1 travar |
| Filtragem anisotrópica (modo) | `0x10D2BB16` | **0 controlado por aplicativo** |
| FXAA | `0x1074C972` | 0 desligado |
| Modo de anti-aliasing | `0x107EFC5B` | 0 controlado por aplicativo |
| Oclusão de ambiente | `0x00667329` | 0 desligado |
| Otimização com threads (OpenGL) | `0x20C1221E` | 1 ligado · 2 desligado |
| Quadros pré-renderizados de RV | `0x10111133` | 1 |
| Buffering triplo (OpenGL) | `0x20FDD1F9` | 0 desligado |
| Método de apresentação Vulkan/OpenGL | `0x20D690F8` | 0 preferir nativo · 1 preferir DXGI · 2 auto |
| G-SYNC (modo global) | `0x1194F158` | 0 desligado · 1 só tela cheia · 2 tela cheia e janela |
| Quadros pré-renderizados (parte do "Modo de baixa latência") | `0x007BA09E` | 0 app · 1 |
| **Baixa latência - estado no painel** (não documentado) | `0x0005F543` | 0 desligado · 1 ligado · 2 ultra |
| **Baixa latência ultra - ativado** (não documentado) | `0x10835000` | 0 · 1 |

Os dois últimos não estão nos headers públicos; vêm do `CustomSettingNames.xml` do NVIDIA Profile Inspector
(MIT, © 2016 Orbmu2k). Vão marcados como "não documentado oficialmente" no `nvidia-drs.json`.
**Fatores DSR não estão nos headers públicos nem num id estável conhecido** → vira só verificação/checklist.

## 5. Correções ao documento de requisitos

### 5.1 NVIDIA: o Painel de Controle foi aposentado

- O driver GeForce **610.47 (26/05/2026)** deixou de instalar o Painel de Controle NVIDIA; as configurações
  foram para o **NVIDIA App**. Atualizando por cima, o painel antigo continua; em instalação limpa ele some.
  O painel legado ainda pode ser baixado na Microsoft Store, sem atualizações.
  Fontes: [Tom's Hardware](https://www.tomshardware.com/pc-components/gpus/nvidia-is-finally-ditching-its-iconic-control-panel-after-20-years-new-driver-updates-only-ship-in-the-nvidia-app),
  [PCGamesN](https://www.pcgamesn.com/nvidia/control-panel-rip),
  [Windows Central](https://www.windowscentral.com/gaming/pc-gaming/nvidia-drops-the-control-panel-for-windows-11-after-20-years-of-faithful-service-and-goes-all-in-on-its-newer-app).
- O PC de teste já está no driver 617.42.
- **Impacto:** o banco DRS continua sendo onde as configurações ficam (o Profile Inspector segue funcionando,
  com versões novas em 2026), então o caminho **NVAPI DRS fica ainda mais importante**: é o jeito de aplicar
  sem depender de interface nenhuma. Na UI, os nomes seguirão o NVIDIA App, com o nome antigo do painel entre
  parênteses. A tela também vai explicar que o painel antigo pode não existir mais.
- **A confirmar na Fase 7:** se o NVIDIA App sobrescreve ou ignora algum valor gravado direto no DRS
  (teste só de leitura no PC de desenvolvimento; gravação só com autorização).

### 5.2 MPO (`OverlayTestMode`)

Relatos em fóruns (Guru3D, ElevenForum) dizem que `OverlayTestMode=5` sozinho **não tem mais efeito** no
Windows 11 24H2/25H2; um usuário relata efeito somando `EnableOverlay=0`. Não há posição oficial da Microsoft.
**Decisão:** o seletor de MPO continua (WinUtil e NVCleanstall ainda oferecem), mas marcado como
**controverso** com o texto "pode não ter efeito no Windows 11 24H2 ou mais novo". Vamos pesquisar a variante
com `EnableOverlay` na Fase 6 antes de incluí-la.

### 5.3 X3D

| Grupo | Modelos | Tratamento |
|---|---|---|
| CCD único | 5500X3D, 5600X3D, 5700X3D, 5800X3D, 7600X3D, 7800X3D, 9800X3D, 9850X3D* | Desempenho Máximo normal |
| CCD duplo, V-Cache em um só | 7900X3D, 7950X3D, 9900X3D, 9950X3D; notebook 7945HX3D, 9955HX3D* | Manter Equilibrado, Game Bar ligado, driver de chipset AMD |
| CCD duplo, V-Cache nos dois | 9950X3D2 (lançado em abril/2026) | **Tratar como CCD duplo** por segurança: uma fonte diz que o core parking ainda importa para limitar a comunicação entre os CCDs; nenhuma fonte oficial sobre o driver |

\* Modelos que a pesquisa não confirmou; ficam na lista porque a regra "na dúvida, tratar como CCD duplo"
é a segura. A lista vai para um arquivo de dados (`config/cpu-x3d.json`), não para o código, para ser
fácil de atualizar.

Detalhe útil: um review aponta que **editar o plano pelo Painel de Controle antigo pode desligar o parking**
nos X3D de CCD duplo — mais um motivo para não mexer no plano Equilibrado nesses PCs.

### 5.4 Copilot e Recall (fonte: [Microsoft Learn — WindowsAI Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai), atualizado em 09/2026)

Todas em `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI`:

| Política | Valor | Efeito | Edições |
|---|---|---|---|
| `AllowRecallEnablement` | 0 | Recall indisponível; remove os binários e apaga snapshots; **requer reinício** | Pro, Enterprise, Education |
| `DisableAIDataAnalysis` | 1 | Não salva snapshots (também em HKCU) | Pro, Enterprise, Education |
| `DisableClickToDo` | 1 | Desativa o "Clicar para Fazer" | Insider por enquanto |
| `RemoveMicrosoftCopilotApp` | 1 | Desinstala o app Copilot **só se** M365 Copilot também estiver instalado, o app não foi instalado pelo usuário e não foi aberto em 28 dias | Pro, Enterprise, Education |

- `TurnOffWindowsCopilot` (`...\Windows\WindowsCopilot`) está **oficialmente obsoleta** e não vale para o
  Copilot novo (que é um app). Vamos gravá-la mesmo assim (inofensiva) e **remover o Appx `Microsoft.Copilot`**,
  com desfazer pela Store/winget.
- Em Windows Home essas políticas não são suportadas oficialmente; a UI vai avisar.

### 5.5 `nvidia-smi -pl`

Os relatos de "Changing power management limit is not supported" são quase todos de **notebooks** (o limite
vem do firmware/Dynamic Boost). Em desktop a leitura funciona (no PC de teste: 250 W padrão, 300 W máximo).
**Decisão:** mostrar padrão/atual/máximo sempre; o botão de ajuste tenta `-pl`, e se o driver recusar,
explica e indica o Afterburner. Bloqueado em notebook.

### 5.6 AMD Adrenalin

A AMD não documenta as chaves UMD; o caminho suportado para ler/gravar configurações do Adrenalin é o
**SDK ADLX** (C++, precisaria de uma DLL compilada junto — inviável num `.ps1` único sem binário).
Um fórum da AMD confirma que a ADL antiga não sincroniza com o Adrenalin.
**Decisão:** só automatizar as poucas chaves UMD que conseguirmos validar (cache de shader, tesselação,
qualidade de filtragem), marcadas como **experimentais**, com backup. Anti-Lag, Chill e Boost viram
**checklist com passo a passo**. Lembrete na UI: Chill e Anti-Lag não funcionam juntos.

### 5.7 Call of Duty (verificado na instalação Steam do PC de teste)

- **Modern Warfare 4** sai em **23/10/2026** (Steam, Battle.net, Xbox App) e exige **TPM 2.0 + Secure Boot**
  (Ricochet). O CoD HQ já tem pastas `cod25` (BO7/Warzone), `cod26` e `sp26` (MW4).
- Executáveis encontrados: `cod.exe` (CoD HQ), **`cod25-cod.exe`**, **`sp26-cod.exe`**. Padrão a detectar:
  `cod.exe` + `^(cod|sp|mp)\d{2}-cod\.exe$`, varrendo a pasta do jogo (só leitura). Ignorar `*CrashHandler*`,
  `bootstrapper*`, `ccsdownloader*`, `CODBroker*`, `codinstallcleaner*`, `CrashLogsGenerator*` e
  `CODSecureAttestationWizard*`.
- O CoD HQ traz o **`CODSecureAttestationWizard.exe`** — vamos oferecer um botão na aba Warzone para
  rodar a verificação oficial de TPM/Secure Boot.
- Arquivo de configuração: o padrão conhecido (BO6) é `Documents\Call of Duty\players\s.1.0.cod24.txt0/txt1`.
  No PC de teste a pasta `players` ainda não existe (o jogo nunca salvou configurações). Detecção:
  regex `^s\.\d+\.\d+\.cod\d+\.txt\d*$` na pasta `players`, escolhendo o mais recente; edição só de chaves
  que já existam (como pedido). `RendererWorkerCount`: as recomendações da comunidade divergem
  (núcleos físicos × metade dos threads) e não há fonte oficial — vai como **experimental** com o valor
  "núcleos físicos" do pedido e explicação honesta.

### 5.8 Outros pontos

- **`bcdedit` + BitLocker:** antes de qualquer `bcdedit`, se o BitLocker estiver ativo, rodar
  `Suspend-BitLocker -MountPoint C: -RebootCount 1` para não cair na tela da chave de recuperação.
- **Teredo × Xbox:** desligar Teredo quebra o NAT da rede Xbox → bloqueado quando o launcher é Xbox App.
- **Windows 10 22H2:** fora de suporte desde 10/2025 (só ESU). Compatível, com aviso.
- **Remoção do Edge:** nunca remover o WebView2 (Xbox App e vários launchers dependem dele).

## 6. Pendências para as próximas fases

| Fase | Verificar |
|---|---|
| 3 (feito) | Detectar quando o UAC foi aprovado com **outra conta de administrador** (usuário padrão + senha do admin): nesse caso o HKCU do processo é o do admin, não o de quem vai jogar. O helper de registro já redireciona HKCU para `HKEY_USERS\<SID>` quando `$UTSync.UsuarioAlvoSid` está definido; falta descobrir o SID do usuário logado (dono do `explorer.exe`) |
| 4 (feito) | CCD duplo além do nome: modelo fora da lista é classificado pela contagem de núcleos (mais de 8 = dois CCDs; sem informação = dois CCDs, o caminho seguro) |
| 4 (limitação) | XMP/EXPO: o `Win32_PhysicalMemory.Speed` costuma trazer a velocidade JEDEC, não a do XMP. Se o XMP estiver desligado, `Speed` e `ConfiguredClockSpeed` ficam iguais. Por isso o diagnóstico também lê a velocidade do part number (ex.: `F5-6000J3038F16G` = 6000) e avisa quando a DDR5 está a 4800 / DDR4 a 2666 |
| 6 (feito) | MPO em dois modos exclusivos (`OverlayTestMode` = 5 e, no modo completo, também `DisableOverlays` do driver); máscara `UserPreferencesMask` do "melhor desempenho" mantendo fontes suavizadas e miniaturas; Storage Sense pela chave `StoragePolicy` (igual no 25H2) |
| 6 (feito) | Id winget do O&O ShutUp10: `OO-Software.ShutUp10` (v3.6, 2026-10-21) |
| 7 (feito) | DRS gravado direto pela NVAPI (a NVIDIA App lê o mesmo banco; backup `.txt` antes). Faixa dinâmica via `NvAPI_Disp_ColorControl` (`NV_COLOR_DATA_V5`). Dimensionamento na tela ficou de fora: depende do modo do monitor e o Windows já expõe |
| 7 → 13 (feito) | AMD: em vez de chaves UMD, a **ADLX** (SDK oficial, `amdadlx64.dll` instalada com o driver; vtables do `SDK/Include` de GPUOpen-LibrariesAndSDKs/ADLX v2.0). Lida com sucesso na GPU integrada do PC de teste (Ryzen 9800X3D). Só a qualidade da filtragem de textura fica no registro (`UMD\TFQ`, texto UTF-16: 0 alta, 1 padrão, 2 desempenho, conforme RadeonMod e o valor que o driver grava). Intel: **IGCL** (`ControlLib.dll`, `igcl_api.h` de intel/drivers.gpu.control-library); sem placa Intel para testar, cada valor é lido antes de gravar. DDU 18.1.5.7: argumentos `-Silent -CleanNvidia/-CleanAmd/-CleanIntel -NoSafeModeMsg` conferidos no executável; o bloqueio de driver pelo Windows Update é feito pelo programa (`DriverSearching\SearchOrderConfig`) e desfeito no fim |
| 12 (conferido em parte) | MW4 (lançamento 23/10): a instalação do Call of Duty HQ no PC de teste já tem as pastas `cod26` e `sp26`, então o título é `cod26` (mapeado como Modern Warfare 4). O arquivo `s.1.0.cod26.txt0` só aparece depois de abrir o jogo; como a busca é por padrão, ele é achado sem mudar código. O jogo grava em `%USERPROFILE%\Documents\Call of Duty\players` mesmo com Documentos no OneDrive (corrigido na fase 11) |
| 8 (feito) | Ryzen Master: `amd.com/en/products/software/ryzen-master.html`. Intel Graphics Software fica no guia Intel da aba GPU. MSI Utility v3: tópico 378044 do fórum Guru3D. IAPT: espelho da TechPowerUp (a Microsoft tirou o download) |
| 9 (decidido) | Aba "Latência" acrescentada entre Gaming e Rede: o documento pede uma aba avançada de latência (7.2), mas ela não estava na lista de abas. Efeitos visuais ficam em Personalizar. Tabelas da interface são Grid próprio (o DataGrid do WPF calcula colunas * antes de saber a largura). Link da Upgrade Store em `config/sobre.json` (vazio = botão escondido) |
