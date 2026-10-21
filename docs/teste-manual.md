# Roteiro de teste manual antes da primeira Release

Durante o desenvolvimento o Upgrade Tweaks **nunca aplicou um ajuste de verdade**: os testes automáticos usam mocks e uma chave de registro de teste, e o CI só roda diagnóstico e simulação. Antes de publicar a primeira versão, rode este roteiro numa **máquina virtual** (Hyper-V ou VirtualBox) com Windows 10 22H2 e outra com Windows 11 25H2, ambas limpas. Tire um snapshot antes de começar.

Para testar sem Release publicada, copie `dist\upgradetweaks.ps1` (gerado por `scripts\compile.ps1`) para a VM.

## 1. Abertura e administrador

- [ ] PowerShell **sem** administrador: `powershell -ExecutionPolicy Bypass -File .\upgradetweaks.ps1` pede o UAC e abre a janela numa nova instância.
- [ ] Negar o UAC: aparece a mensagem em português e nada é alterado.
- [ ] `irm <url> | iex` num PowerShell de administrador abre direto (só depois da Release; antes, use `Get-Content .\upgradetweaks.ps1 -Raw | iex`).
- [ ] Acentos aparecem certos na janela e no console (arquivo é ASCII puro).

## 2. Interface

- [ ] Janela abre na aba Início, a nota aparece em poucos segundos e a janela não trava enquanto carrega.
- [ ] Todas as abas abrem; redimensionar até 1100x700 não esconde botões.
- [ ] Busca acha "mouse", "telemetria", "DNS" (com e sem acento).
- [ ] Passar o mouse num ajuste mostra descrição, ganho e cuidados.

## 3. Aplicar e desfazer (o mais importante)

- [ ] **Simular** com o preset Competitivo marcado: o resumo lista valor atual → novo e nada muda (confira `regedit` em uma ou duas chaves).
- [ ] **Otimizar agora com o preset Seguro**: confirma, aplica, mostra o resumo.
- [ ] Foi criado um ponto de restauração (`rstrui.exe`) e uma pasta em `%ProgramData%\UpgradeTweaks\backups`.
- [ ] Os ajustes aplicados mostram "Aplicado"; reiniciar e conferir que continuam.
- [ ] Aplicar o Competitivo por cima: o plano "Upgrade Warzone" aparece em Opções de Energia e fica ativo.
- [ ] Ajuste de risco alto (ex.: IDLEDISABLE): pede confirmação um por um.
- [ ] **Restaurar → Desfazer TUDO**: tudo volta; conferir plano de energia, uma chave de registro e um serviço (ex.: DiagTrack volta a Automático).
- [ ] Desfazer de novo não quebra nada ("nada para desfazer").

## 4. Casos especiais

- [ ] VM com Xbox App / Game Pass instalado: serviços do Xbox aparecem como "não se aplica".
- [ ] Taxa do monitor (precisa de monitor real com mais Hz disponível): aplicar mostra o aviso de 15 s e, sem clicar, volta sozinho.
- [ ] Modo Partida: entrar fecha os programas marcados e troca o plano; sair volta o plano e reabre o que foi fechado (sem administrador).
- [ ] Notebook (se tiver um para testar): o plano vira "Upgrade Warzone (na tomada)".

## 5. Programas e ferramentas

- [ ] Instalar o 7-Zip pela aba Programas, abrir (como administrador) e desinstalar.
- [ ] Limpar temporários informa o espaço liberado.
- [ ] Pausar o Windows Update por 7 dias aparece em Configurações > Windows Update; "Retomar" volta.

## 6. NVIDIA (no PC real, quando quiser)

- [ ] Aba GPU mostra a tabela atual × recomendado do perfil do Call of Duty.
- [ ] Aplicar "Configurações NVIDIA recomendadas no perfil do Call of Duty", conferir no NVIDIA Profile Inspector, e desfazer.
- [ ] Faixa dinâmica Completa no monitor que está Limitada, e desfazer.

## 7. Linha de comando

```powershell
.\upgradetweaks.ps1 -Diagnostico -ExportarRelatorio C:\relatorio.html
.\upgradetweaks.ps1 -Simular -Preset Competitivo
.\upgradetweaks.ps1 -Preset Seguro -Silencioso; $LASTEXITCODE
.\upgradetweaks.ps1 -DesfazerTudo
```

- [ ] Códigos de saída: `0`, ou `3010` quando precisa reiniciar.

## 8. Publicar

1. Renomeie `## [Não lançado]` do `CHANGELOG.md` para `## [0.1.0] - AAAA-MM-DD`.
2. `git tag v0.1.0` e `git push --tags`.
3. O GitHub Actions testa, compila e cria a Release com `upgradetweaks.ps1` e `upgradetweaks.ps1.sha256`.
4. Teste o comando `irm https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1 | iex` numa VM.
