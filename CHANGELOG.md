# Changelog

Todas as mudanças relevantes do Upgrade Tweaks ficam registradas aqui.
O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto usa [versionamento semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

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
