```
     ____ _   _  ____ __  __
    / ___| | | |/ ___|  \/  |
   | |  _| |_| | |   | |\/| |
   | |_| |  _  | |___| |  | |
    \____|_| |_|\____|_|  |_|

     H U B  -  A G E N T S
     ------------------------
     Gated Hub CLI Manager
```

**GHCM** = **G**ated **H**ub **C**LI **M**anager. Orquestrador multi-agente em terminal: quatro CLIs de LLM rodam simultaneamente em painéis tmux, cada um com um papel bem definido (`planner`, `developer`, `reviewer`, `git-manager`), com **gates de aprovação manuais** entre os estágios — daí o "Gated". Os arquivos de controle ficam fora do projeto, em `~/agent-hub/state/<projeto>/` — o repositório de código nunca é poluído por planos/reviews.

![Sessão tmux com os 4 agentes](docs/screenshots/panes.png)

## Por que

Trabalhar com LLM-CLIs sozinho em um único terminal é OK pra tarefas pequenas. Mas quando o trabalho exige **planejar, executar, revisar criticamente e abrir um PR**, fica mais produtivo dividir em papéis: cada estágio com seu prompt focado, cada um podendo usar um modelo/CLI diferente, e o usuário mantendo controle de aprovação entre passos.

Você fala com o **planner** ("crie um plano pra adicionar login com magic link"), aprova quando estiver bom, e o plano vai pra fila do **developer**. Quando você pedir, o developer executa, e o resultado vai pra fila do **reviewer**, que valida o diff como num PR. Se aprovar, o **git-manager** cria branch, commit, push e abre PR no GitHub.

## Fluxo

```
você → planner   → mostra plano em texto → aprova → arquivo em state/<proj>/plans/pending/
                                                    │
                                                    ▼
você → developer → executa pendentes → cria entrada em state/<proj>/reviews/pending/
                                       │
                                       ▼
você → reviewer  → roda git diff + lê contexto → approved/rejected
                                                  │
                          ┌───────────────────────┴───────────┐
                          ▼                                   ▼
                     approved                            rejected
                          │                                   │
                          ▼                                   ▼
você → git-manager → branch + commit       você → developer → corrige (-v2)
                     + push + gh pr create        → nova review pendente
```

Reviews reprovadas viram correções versionadas (`-v2`, `-v3`...) — o developer endereça as notas do reviewer e devolve pra nova revisão. Não precisa voltar ao planner pra cada ajuste.

## Requisitos

- **Linux** (testado em Ubuntu)
- `tmux` (≥ 3.0)
- `git`
- `pandoc` (usado por `ghcm plans export` pra gerar PDF dos planos — `sudo apt install pandoc`)
- `weasyprint` (engine de PDF do pandoc — `pip install weasyprint` ou via `pipx`)
- Pelo menos uma CLI de LLM com tool use por papel:
  - [`claude`](https://docs.claude.com/en/docs/claude-code/quickstart) (Anthropic Claude Code)
  - [`codex`](https://github.com/openai/codex) (OpenAI Codex)
  - [`gemini`](https://github.com/google-gemini/gemini-cli) (Google Gemini, opcional)
  - [`qwen`](https://github.com/QwenLM/qwen-code) (qwen-code, fork do gemini-cli; provider em `~/.qwen/settings.json`)
- `gh` (GitHub CLI), autenticado, **se for usar o git-manager pra abrir PRs**

## Instalação

```bash
git clone git@github.com:gustavohcmelo/hub-agents.git ~/agent-hub
~/agent-hub/install.sh
```

O instalador cria o symlink `~/.local/bin/ghcm` e verifica dependências. Se `~/.local/bin` não estiver no `PATH`, ele te avisa.

## Uso

```bash
cd /seu/projeto-git
ghcm start                  # abre sessão tmux 'agents-<slug>' com os 4 painéis
ghcm attach [slug]          # reconecta numa sessão existente (default: cwd)
ghcm switch [slug]          # alterna entre sessões (lista interativa se >1)
ghcm stop [slug|--all]      # encerra a sessão (default: cwd; --all encerra todas)
ghcm status [slug]          # planos/reviews do projeto (default: current)
ghcm list                   # sessões tmux ativas
ghcm plans [slug] [--pending|--all]   # lista planos (default: --all = pending + done)
ghcm plans [slug] export <plan-id>    # gera PDF do plano em state/<slug>/exports/
ghcm config                 # edita ~/agent-hub/config.sh
ghcm config --reset         # restaura config.sh do template
ghcm logs [name]            # lista logs ou mostra um específico
ghcm logs --prune [N]       # apaga logs antigos, mantém últimos N (default 20)
ghcm clean <slug> [--yes]   # apaga state/<slug>/ (sessão precisa estar parada)
ghcm help                   # ajuda
```

![Tela inicial do ghcm start](docs/screenshots/boot.png)

Dentro do tmux:

| Painel | Papel | Você fala |
|---|---|---|
| top-left | planner | "implemente login com magic link" → mostra plano → "pode criar" |
| top-right | developer | "execute os planos pendentes" / "corrija a review reprovada" |
| bottom-left | reviewer | "verifique reviews pendentes" |
| bottom-right | git-manager | "envie aprovados" |

Cada projeto tem sua **própria sessão tmux** (`agents-<slug>`), então você pode ter vários projetos abertos ao mesmo tempo sem conflito. Atalhos úteis dentro do tmux:

- `Ctrl-b d` — desanexa sem matar (volte com `ghcm attach`)
- `Ctrl-b X` — encerra a sessão (com confirmação)
- `Ctrl-b s` — alterna entre sessões abertas (seguro: agentes derivam o slug do nome da sessão atual)

Quando um agente termina de responder e fica 5s silencioso, o tmux pisca o border do pane (sinal visual de "pronto pra próxima"). Configurável via `monitor-silence` na sessão. Cada pane tem **cor própria pra identificação rápida** (planner ciano, developer verde, reviewer amarelo, git-manager magenta) tanto no título quanto na borda — pane ativo destaca em tom mais brilhante.

### Trabalhando em vários projetos

```bash
cd ~/projeto-a && ghcm start    # cria sessão agents-projeto-a
# Ctrl-b d pra desanexar
cd ~/projeto-b && ghcm start    # cria sessão agents-projeto-b
ghcm list                       # mostra as duas sessões ativas
ghcm switch projeto-a           # alterna pra projeto-a (atualiza current-project automaticamente)
ghcm switch                     # menu interativo se houver >1 sessão
```

> Cada agente descobre seu projeto pelo nome da sessão tmux (`tmux display-message -p '#S'`), não pelo `current-project.txt`. Isso significa que `Ctrl-b s` (alternar nativo do tmux) também é seguro — o agente sempre lê o slug certo. Os comandos `ghcm switch`/`attach` continuam atualizando `current-project.txt` por compatibilidade com sessões em andamento, mas a fonte de verdade é o nome da sessão.

### Exportar plano pra aprovação

Quando um plano precisa de aval externo (gestor, cliente) antes de virar tarefa do developer, dá pra exportar como PDF formatado:

```bash
ghcm plans                                       # lista planos do projeto atual
ghcm plans meu-projeto --pending                 # só pendentes do projeto X
ghcm plans meu-projeto export login-magic-link   # gera PDF (id parcial OK)
# -> ~/agent-hub/state/meu-projeto/exports/<id>.pdf
```

O comando ecoa só o path no stdout — fácil capturar (`pdf=$(ghcm plans ... export ...)`) ou abrir direto (`xdg-open "$(ghcm plans ... export ...)"`). Se o id casar com mais de um plano, mostra os candidatos pra refinar.

O PDF tem capa estruturada (título, projeto, status com badge colorido, criado em, ID, bloco de assinatura "Aprovado por") + corpo formatado com tipografia serif/sans-serif, headings com barra lateral colorida por tema (verde "aceitação", laranja "riscos", azul "objetivo"), code blocks estilizados e paginação no rodapé.

Customização visual: edite `~/agent-hub/templates/plan-pdf.css` (cores/tamanhos) ou `~/agent-hub/templates/plan-pdf-template.html` (layout da capa). O `ghcm` não precisa mudar.

### Primeira vez num projeto

Se o projeto não tiver `CLAUDE.md` nem `AGENTS.md`, o `ghcm start` roda `claude /init` headless antes de subir o tmux pra mapear o stack/arquitetura. Isso melhora muito a qualidade dos planos e revisões. O log é gravado em `~/agent-hub/logs/<timestamp>-init-<slug>.log` e mostrado em tempo real durante a execução (`ghcm logs` lista o histórico).

## Configurando os CLIs

Edite `~/agent-hub/config.sh` (ou rode `ghcm config`):

```bash
PLANNER_CMD="claude --dangerously-skip-permissions"
DEVELOPER_CMD="claude --dangerously-skip-permissions"
REVIEWER_CMD="codex --dangerously-bypass-approvals-and-sandbox"
GIT_MANAGER_CMD="claude --dangerously-skip-permissions"
```

Misture os modelos como quiser. Restrição: **ollama não funciona em roles que precisam executar comandos** (developer, git-manager) porque não tem tool use por padrão — só consegue ser planner ou consultor textual.

## Estrutura

```
~/agent-hub/
├── ghcm                              entrypoint (start | attach | switch | stop | status | list | config | logs | help)
├── start.sh                          setup do tmux (chamado por `ghcm start`)
├── install.sh                        cria symlink em ~/.local/bin
├── config.example.sh                 template; copiado pra config.sh no primeiro uso
├── agents/
│   ├── planner/CLAUDE.md             prompts/papéis dos agentes
│   ├── developer/CLAUDE.md
│   ├── reviewer/AGENTS.md            (codex lê AGENTS.md, claude lê CLAUDE.md)
│   └── git-manager/CLAUDE.md
├── templates/                        template/css usados por `ghcm plans export`
│   ├── plan-pdf-template.html        layout da capa (pandoc HTML5 template)
│   └── plan-pdf.css                  tipografia, cores, paginação
├── logs/                             logs históricos timestamped (gitignored)
└── state/<projeto>/                  estado por projeto (gitignored)
    ├── .project-path                 caminho absoluto do projeto (escrito por start.sh)
    ├── plans/{pending,done}/
    ├── reviews/{pending,done/{approved,rejected,shipped}}/
    └── exports/                      PDFs gerados por `ghcm plans export`
```

Plans e reviews têm **frontmatter YAML obrigatório** (`id`, `created_at`, `project_slug`, `kind`, `status`, `version`, `type` em plans, `plan_ref`/`previous_review_ref` em reviews). `ghcm status` valida e avisa sobre arquivos legados sem frontmatter.

`current-project.txt` (gitignored) registra o caminho do projeto ativo. Os agentes leem esse arquivo no começo de cada operação.

## Customizando os papéis

Cada papel é definido por um único arquivo de prompt em `agents/<role>/CLAUDE.md` (ou `AGENTS.md` no caso do reviewer/codex). Edite à vontade — formato livre, contanto que continue descrevendo:

1. Diretórios que o papel lê/escreve
2. Quando ativar (que comando do usuário dispara)
3. O que fazer (passos numerados, formato dos artefatos gerados)

## Limitações conhecidas

- **macOS**: não testado. Provavelmente funciona com pequenos ajustes (`stat` flags, `realpath` etc.).
- **WSL**: não testado.
- **Bracketed paste do tmux**: se você notar que mensagens injetadas não submetem, pode ser preciso ajustar timing do `send-keys` (não usado no fluxo atual, mas relevante se você customizar).
- **Cota dos provedores**: especialmente gemini free tier estoura rápido. Tenha redundância via `config.sh`.

## Licença

MIT — veja [LICENSE](LICENSE).
