# Esquema do `config/tweaks.json`

Cada tweak é um objeto dentro de `"tweaks": [ ... ]`. O teste `tests/Schema.Tests.ps1` valida todos os
campos abaixo; um tweak inválido não entra no programa.

```json
{
  "id": "UT_Gaming_GameDVR_Off",
  "nome": "Desativar gravação em segundo plano (Game DVR)",
  "descricao": "Texto honesto do que muda e por quê.",
  "ganhoEsperado": "Pequeno a médio",
  "categoria": "Gaming",
  "risco": "baixo",
  "requerReinicio": false,
  "controverso": false,
  "observacao": "",
  "confirmacao": "",
  "grupoExclusivo": "",
  "compatibilidade": {
    "windows": ["10", "11"],
    "buildMinimo": 0,
    "gpu": ["nvidia", "amd", "intel"],
    "cpu": ["amd", "intel"],
    "notebook": true,
    "desktop": true,
    "launchersBloqueados": [],
    "x3dDuplo": true
  },
  "registro": [
    { "caminho": "HKCU:\\System\\GameConfigStore", "nome": "GameDVR_Enabled", "tipo": "DWord", "valor": 0, "valorOriginal": 1 }
  ],
  "servicos": [
    { "nome": "DiagTrack", "inicio": "Disabled", "inicioOriginal": "Automatic", "parar": true }
  ],
  "scriptAplicar": [],
  "scriptDesfazer": [],
  "scriptDetectar": [],
  "deteccao": "registro"
}
```

## Campos

| Campo | Obrigatório | Regras |
|---|---|---|
| `id` | sim | `UT_` + letras, números e `_`. Único. |
| `nome`, `descricao`, `ganhoEsperado` | sim | Texto em PT-BR. A descrição diz o ganho real; efeito duvidoso é dito com todas as letras. |
| `categoria` | sim | Aba onde aparece: `Energia`, `Gaming`, `Latencia`, `Rede`, `ServicosApps`, `Privacidade`, `Visual`, `Personalizar`, `GPU`, `Warzone`. |
| `risco` | sim | `baixo`, `médio` ou `alto`. `alto` exige `confirmacao` (texto da caixa de diálogo). |
| `requerReinicio` | sim | `true`/`false`. |
| `controverso` | sim | `true` mostra o selo "controverso". |
| `observacao`, `confirmacao` | não | Texto extra / texto da confirmação de risco alto. |
| `abasExtras` | não | Outras abas onde o ajuste também aparece (ex.: QoS do jogo em Rede e em Warzone). |
| `grupoExclusivo` | não | Tweaks com o mesmo grupo são alternativas (ex.: modos do MPO); só um pode ficar aplicado. |
| `compatibilidade` | sim | Ver abaixo. Valor desconhecido no PC nunca bloqueia. |
| `registro[]` | não | `caminho`, `nome` (vazio = valor padrão), `tipo` (`DWord`, `QWord`, `String`, `ExpandString`, `MultiString`, `Binary`), `valor`, `valorOriginal` (padrão do Windows; `null` = o valor não existe por padrão). `"acao": "remover"` apaga o valor em vez de definir. `"ausenteEquivale": true` quando o padrão do Windows (valor ausente) já se comporta como o alvo; aí a detecção não acusa "não aplicado" à toa. |
| `servicos[]` | não | `nome`, `inicio` e `inicioOriginal` (`Automatic`, `AutomaticDelayedStart`, `Manual`, `Disabled`), `parar` opcional. |
| `scriptAplicar[]`, `scriptDesfazer[]` | não | Linhas de PowerShell 5.1. Se houver `scriptAplicar`, `scriptDesfazer` é obrigatório. Recebem `$TweakId` e podem usar os helpers (`Save-UTOriginalItem`, `Pop-UTOriginalItem`, `Invoke-UTNative`...). |
| `scriptDetectar[]` | depende | Devolve `$true` quando o tweak está aplicado. Obrigatório quando `deteccao` é `script` ou `combinada`. |
| `scriptSimular[]`, `scriptSimularDesfazer[]` | não | Só leitura. Devolvem as linhas que a simulação mostra (ex.: "Estado mínimo do processador: 5 -> 100"). Sem eles, a simulação diz apenas "Executa o script do ajuste". |
| `deteccao` | sim | `registro`, `servicos`, `script` ou `combinada` (tudo o que o ajuste tiver: registro + serviços + `scriptDetectar`, se houver script). |

Todo tweak precisa ter pelo menos uma ação (`registro`, `servicos` ou `scriptAplicar`) e, para cada ação, o caminho de volta.

### `compatibilidade`

| Campo | Efeito |
|---|---|
| `windows` | Gerações permitidas (`"10"`, `"11"`). |
| `buildMinimo` | Build mínimo do Windows (ex.: `26100` para recursos do 24H2). |
| `gpu`, `cpu` | Fabricantes permitidos. |
| `notebook`, `desktop` | Se pode aparecer em notebook / desktop. |
| `launchersBloqueados` | Ex.: `["xbox"]` para tweaks que quebram o Xbox App/Game Pass. |
| `x3dDuplo` | `false` bloqueia em Ryzen X3D de dois CCDs. |
| `exigeJogo` | `true` para ajustes dos executáveis do Call of Duty: só aparecem com o jogo encontrado. |
| `exigeX3D` | `"duplo"` ou `"unico"`: o ajuste só aparece nesse tipo de X3D. Ao contrário das outras regras, bloqueia quando o tipo do processador é desconhecido. |

## Como o motor usa o esquema

1. **Detectar:** compara cada valor do registro e cada serviço com o alvo, e roda `scriptDetectar`.
   Resultado: `Aplicado`, `NaoAplicado`, `Parcial` ou `Incompativel`.
2. **Aplicar:** checa admin e compatibilidade, cria o ponto de restauração da sessão, exporta `.reg` da chave,
   salva o valor **real** em `estado-original.json`, aplica registro → serviços → script, detecta de novo e
   registra em `aplicados.json`. Se algo falhar no meio, desfaz o que aquele tweak já tinha mudado.
3. **Desfazer:** ordem inversa (script → serviços → registro). Volta o valor real salvo; sem estado salvo,
   usa `valorOriginal`; se o valor não existia, apaga.
4. **Simular (`-WhatIf`):** devolve a lista de ações sem alterar nada.
