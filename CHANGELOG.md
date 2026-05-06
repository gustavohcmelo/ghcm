# Changelog

Todas as mudanças relevantes deste projeto serão documentadas aqui.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
e o projeto segue [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [2.0.0] — 2026-05-06

Renomeação do projeto pra alinhar com o brand `GHCM` em todo lugar.
Sem mudanças funcionais — só path e identidade visual.

### Alterado (BREAKING)

- **Repositório:** `gustavohcmelo/hub-agents` → `gustavohcmelo/ghcm`.
  GitHub mantém redirect automático nas URLs antigas, mas o nome
  canônico é `ghcm` agora.
- **Diretório de instalação:** `~/agent-hub` → `~/ghcm`. Variável
  `HUB="$HOME/ghcm"` em `ghcm` e `start.sh`. Todas as referências
  em scripts, prompts e docs atualizadas.
- **Banner ASCII e branding:** removida a tag "HUB-AGENTS" (codinome
  antigo). Banner agora mostra só o ASCII GHCM + tagline "Gated Hub
  CLI Manager".

### Migração

Quem tem instalação anterior (`~/agent-hub`):

```bash
# pare sessões em andamento
ghcm stop --all

# mova o diretório
mv ~/agent-hub ~/ghcm

# reinstale (recria o symlink ~/.local/bin/ghcm pro novo path)
~/ghcm/install.sh

# atualize o remote do clone local (GitHub também tem redirect, mas
# vale fixar o nome novo)
cd ~/ghcm
git remote set-url origin git@github.com:gustavohcmelo/ghcm.git
git pull
```

State (`~/ghcm/state/<slug>/`) e config (`~/ghcm/config.sh`) são
preservados pelo `mv` — nenhum plano/review é perdido.

[2.0.0]: https://github.com/gustavohcmelo/ghcm/releases/tag/v2.0.0

## [1.1.0] — 2026-05-06

Iteração pós-1.0.0 com foco em comunicação assíncrona entre agentes,
fila por sessão e robustez dos prompts. Pipeline mantém o mesmo
formato; mudanças são em torno de UX, multi-CLI e regras de operação.

### Adicionado

#### CLI
- `ghcm --version` (alias `version` / `-v`) imprime a versão do pacote.
- `ghcm plans [slug] export <plan-id>` gera PDF do plano em
  `state/<slug>/exports/`, com capa estruturada e tipografia
  customizável via `templates/plan-pdf.css` e
  `templates/plan-pdf-template.html`.
- Atalho `Ctrl-b X` encerra a sessão tmux com confirmação.

#### Multi-CLI
- Suporte a `qwen` (qwen-code, fork do gemini-cli) como CLI
  configurável em qualquer role; provider definido em
  `~/.qwen/settings.json`. `wait_for_ready` reconhece o marker de
  boot do qwen.

#### Comunicação inter-agente
- Pings automáticos entre painéis a cada transição do pipeline:
  `planner → developer` (plano novo), `developer → reviewer`
  (review pendente), `reviewer → developer` (rejeitada) ou
  `git-manager` (aprovada), `git-manager → developer` (PR aberto,
  working tree limpa). A fila no filesystem segue como fonte da
  verdade; pings são nudge.
- Developer processa **um plano por turno** e aguarda o ping do
  git-manager pra retomar a fila — evita misturar diffs de múltiplos
  planos num único PR.

#### Robustez dos prompts
- Bloco "Desambiguação crítica" em todos os roles: "este projeto"
  sempre = `$PROJECT_PATH`, nunca `~/ghcm`.
- Regra "queue-first, não explora projeto" prominente no topo dos
  prompts — agente lista a fila antes de qualquer leitura
  exploratória.
- Planner: regra explícita "não implementa, só planeja"; único
  `Write` permitido é em `state/<slug>/plans/pending/`.
- Git-manager: hard rule "tudo termina em PR" + proibição de PR
  `homolog → main` (cada feature/fix abre PR isolado pra main).
- Tarefas cross-repo geram **um único plano/review** no slug ativo
  com seção "Repos envolvidos"; git-manager desdobra em N PRs no
  ship.

#### UX
- Cor própria por pane (planner ciano, developer verde, reviewer
  amarelo, git-manager magenta) — título e borda; pane ativo em
  tom mais brilhante.
- Timer in-place durante o `claude /init` headless em projetos
  novos.

#### Documentação
- `CLAUDE.md` e `AGENTS.md` na raiz descrevem a arquitetura do
  GHCM pra orientar agentes que venham a editar o próprio repo.
- README documenta os pings inter-agente e a regra de fila por
  sessão.

[1.1.0]: https://github.com/gustavohcmelo/ghcm/releases/tag/v1.1.0

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
- Logs timestamped em `~/ghcm/logs/<ts>-init-<slug>.log`.
- `monitor-silence` do tmux pisca o pane border quando o agente fica idle 5s.
- Atalho `Ctrl-b X` encerra a sessão com confirmação.
- Configuração por role em `~/ghcm/config.sh`
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
