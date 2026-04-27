# Changelog

Todas as mudanças relevantes deste projeto serão documentadas aqui.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
e o projeto segue [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.0.0] — 2026-04-27

Primeira versão estável. Pipeline `planner → developer → reviewer → git-manager`
validado end-to-end em projeto real (PR aberto, revisado e mergeado).

### Adicionado

#### Orquestração
- Comando `ghcm` com subcomandos `start`, `attach`, `switch`, `stop`, `status`,
  `list`, `config`, `logs`, `clean`, `help`.
- Sessão tmux por projeto (`agents-<slug>`), permitindo múltiplos projetos
  abertos simultaneamente.
- Cada agente resolve o slug do projeto pelo nome da sessão tmux atual,
  não pelo `current-project.txt` global — `Ctrl-b s` virou seguro.
- 4 papéis com prompts dedicados em `agents/<role>/CLAUDE.md|AGENTS.md`:
  - `planner` (claude): gera planos, salva quando aprovado em `state/<slug>/plans/pending/`.
  - `developer` (claude): executa planos pendentes, cria reviews em `reviews/pending/`.
    Suporta correção de reviews reprovadas via versionamento `-v2`, `-v3`...
  - `reviewer` (codex): revisa diff + contexto do projeto, decide approved/rejected.
  - `git-manager` (claude): cria branch `<type>/<slug>`, commit, push e PR via `gh`.

#### Estrutura de dados
- `state/<slug>/plans/{pending,done}/` para planos.
- `state/<slug>/reviews/{pending,done/{approved,rejected,shipped}}/` para reviews.
- Frontmatter YAML obrigatório em plans e reviews
  (`id`, `created_at`, `project_slug`, `kind`, `status`, `version`, e específicos).
- `state/<slug>/.project-path` registra caminho absoluto do projeto.

#### UX e robustez
- Banner ASCII responsivo (compacto em terminais < 50 colunas).
- Pre-flight valida `tmux`, `git` e CLIs configurados antes de subir o tmux.
- Polling por marker específico de cada CLI (claude, codex, gemini, ollama)
  no lugar de `sleep` fixo.
- `claude /init` headless com tail do log em tempo real para projetos novos.
- Logs timestamped em `~/agent-hub/logs/<ts>-init-<slug>.log`.
- `monitor-silence` do tmux pisca o pane border quando o agente fica idle 5s.
- Atalho `Ctrl-b X` encerra a sessão com confirmação.
- Configuração por role em `~/agent-hub/config.sh`
  (criado a partir de `config.example.sh` no primeiro uso).

#### Integração com git
- Branch derivada do tipo do plano: `feat/`, `fix/`, `chore/`, `docs/`,
  `refactor/`, `test/`.
- Verificação de PR existente via `gh pr list` antes de pushar
  (não duplica PR aberto; sufixa branch se houver fechado/merged).
- Body do PR em pt-BR; título e mensagem de commit em inglês.

#### Documentação
- README em pt-BR com banner ASCII, fluxograma, screenshots, requisitos,
  instalação, uso, estrutura, customização e limitações conhecidas.
- LICENSE MIT.
- `install.sh` cria symlink `~/.local/bin/ghcm` e valida dependências.
- CI: `.github/workflows/lint.yml` com `shellcheck` + `shfmt`.

### Branding

GHCM = **G**ated **H**ub **C**LI **M**anager. O "Gated" referencia os gates
de aprovação manuais entre estágios — feature distintiva do projeto.

[1.0.0]: https://github.com/gustavohcmelo/hub-agents/releases/tag/v1.0.0
