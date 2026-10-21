# Upgrade Tweaks

Otimizador de Windows da **Upgrade Store** (Porto Alegre/RS), focado em desempenho, latência e estabilidade no **Call of Duty: Warzone**. Todo em português do Brasil.

> **Em desenvolvimento.** Ainda não existe uma versão pronta para uso. O README completo chega junto com a primeira versão.

## Como vai funcionar

Abra o **PowerShell como administrador** e cole:

```powershell
irm https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1 | iex
```

O programa **sempre roda como administrador**: se for aberto sem esse privilégio, ele mesmo pede a permissão do Windows (UAC). Se a permissão for negada, ele avisa e fecha sem alterar nada.

## Presets

| Preset | O que marca |
|---|---|
| **Seguro** (recomendado) | Só ajustes de risco baixo com ganho comprovado: Game DVR, Modo de Jogo, mouse, perfil NVIDIA do jogo, GPU dedicada, paginação e telemetria básica. |
| **Competitivo** | Seguro + risco médio sem efeitos colaterais conhecidos: plano Upgrade Warzone, MMCSS, rede, modo MSI, serviços em Manual, exclusão do Defender e debloat moderado. |
| **Extremo** | Competitivo + todo o resto de desempenho, inclusive risco alto. Pede para digitar **EU ENTENDO**. |

O que não se aplica ao hardware (X3D de dois CCDs, notebook, Xbox/Game Pass, fabricante da placa) é pulado sozinho. Personalização, escolha de DNS, serviços do Xbox e o Spooler de impressão nunca entram em preset. A lista exata de cada um está em [`config/presets.json`](config/presets.json).

Na tela Início dá para **exportar a seleção** marcada em JSON e **importar** em outro PC (ou usar com `-Config`).

## Linha de comando (sem interface)

Com o arquivo baixado:

```powershell
.\upgradetweaks.ps1 -Preset Seguro -Silencioso
.\upgradetweaks.ps1 -Config .\minha-config.json
.\upgradetweaks.ps1 -DesfazerTudo
.\upgradetweaks.ps1 -Diagnostico -ExportarRelatorio C:\relatorio.html
.\upgradetweaks.ps1 -Simular -Preset Competitivo
```

Direto da internet (o `irm | iex` não aceita parâmetros, então o script vira um bloco):

```powershell
& ([scriptblock]::Create((irm https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1))) -Preset Seguro
```

| Parâmetro | Efeito |
|---|---|
| `-Preset Seguro\|Competitivo\|Extremo` | Aplica o preset. Os ajustes de risco alto pedem para digitar `EU ENTENDO`; com `-Silencioso` eles são pulados. |
| `-Config arquivo.json` | Aplica uma seleção exportada pela interface. |
| `-DesfazerTudo` | Desfaz tudo que o programa aplicou, do último para o primeiro (pede `S` para confirmar, exceto com `-Silencioso`). |
| `-Diagnostico` / `-ExportarRelatorio caminho` | Mostra a nota e as pendências; o relatório pode ser `.html` ou `.txt`. |
| `-Simular` | Mostra tudo que seria feito sem alterar nada (sozinho, abre a interface em modo simulação). |
| `-Silencioso` | Sem saída no console e sem perguntas; tudo fica no log em `%ProgramData%\UpgradeTweaks\logs`. |

A taxa de atualização do monitor nunca é alterada pela linha de comando: na interface ela tem 15 segundos para ser confirmada e volta sozinha se a tela apagar.

Código de saída: `0` ok, `1` algum ajuste falhou, `2` parâmetros inválidos, `3010` ok mas precisa reiniciar.

## Desenvolvimento

Requisitos: Windows PowerShell 5.1, Pester 5.7.1 e PSScriptAnalyzer (`Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck` e `Install-Module PSScriptAnalyzer -Scope CurrentUser`).

| Tarefa | Comando |
|---|---|
| Rodar testes e analisador | `powershell -File tests\Invoke-UTTests.ps1` |
| Compilar o arquivo único | `powershell -File scripts\compile.ps1` (gera `dist\upgradetweaks.ps1`) |
| Corrigir codificação (UTF-8 com BOM) | `powershell -File scripts\fix-encoding.ps1` |

Regras do código:
- Precisa rodar no **PowerShell 5.1** (e também no 7). Nada de `??`, `?.`, operador ternário ou `ForEach-Object -Parallel`.
- Arquivos `.ps1` com acentos são salvos em **UTF-8 com BOM**. O arquivo compilado é convertido para ASCII puro, porque o GitHub entrega a Release sem charset e o `irm` do PowerShell 5.1 estragaria os acentos.
- Acentos só dentro de strings e comentários, nunca em nomes de funções ou variáveis.

## Licença

[MIT](LICENSE). Inspirado no [WinUtil](https://github.com/ChrisTitusTech/winutil) do Chris Titus Tech (MIT), sem reaproveitar código.
