# Upgrade Tweaks

Otimizador de Windows da **Upgrade Store** (Porto Alegre/RS), focado em desempenho, latência e estabilidade no **Call of Duty: Warzone**. Todo em português do Brasil.

> **Em desenvolvimento.** Ainda não existe uma versão pronta para uso. O README completo chega junto com a primeira versão.

## Como vai funcionar

Abra o **PowerShell como administrador** e cole:

```powershell
irm https://github.com/Buzzacar0/upgrade-tweaks/releases/latest/download/upgradetweaks.ps1 | iex
```

O programa **sempre roda como administrador**: se for aberto sem esse privilégio, ele mesmo pede a permissão do Windows (UAC). Se a permissão for negada, ele avisa e fecha sem alterar nada.

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
