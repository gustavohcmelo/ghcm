```
     ____ _   _  ____ __  __
    / ___| | | |/ ___|  \/  |
   | |  _| |_| | |   | |\/| |
   | |_| |  _  | |___| |  | |
    \____|_| |_|\____|_|  |_|

     H U B  -  A G E N T S
     ------------------------
     Multi-Agent Orchestrator
```

Orquestrador multi-agente em terminal. Quatro CLIs de LLM rodam simultaneamente em painéis tmux, cada um com um papel bem definido (`planner`, `developer`, `reviewer`, `git-manager`), com **gates de aprovação manuais** entre os estágios. Os arquivos de controle ficam fora do projeto, em `~/agent-hub/state/<projeto>/` — o repositório de código nunca é poluído por planos/reviews.

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
- Pelo menos uma CLI de LLM com tool use por papel:
  - [`claude`](https://docs.claude.com/en/docs/claude-code/quickstart) (Anthropic Claude Code)
  - [`codex`](https://github.com/openai/codex) (OpenAI Codex)
  - [`gemini`](https://github.com/google-gemini/gemini-cli) (Google Gemini, opcional)
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
ghcm start          # abre tmux com os 4 painéis (planner, developer, reviewer, git-manager)
ghcm config         # edita comandos por role (~/agent-hub/config.sh)
ghcm stop           # encerra a sessão
ghcm help           # ajuda
```

Dentro do tmux:

| Painel | Papel | Você fala |
|---|---|---|
| top-left | planner | "implemente login com magic link" → mostra plano → "pode criar" |
| top-right | developer | "execute os planos pendentes" / "corrija a review reprovada" |
| bottom-left | reviewer | "verifique reviews pendentes" |
| bottom-right | git-manager | "envie aprovados" |

`Ctrl-b d` desanexa sem matar a sessão (`tmux attach -t agents` pra voltar).

### Primeira vez num projeto

Se o projeto não tiver `CLAUDE.md` nem `AGENTS.md`, o `ghcm start` roda `claude /init` headless antes de subir o tmux pra mapear o stack/arquitetura. Isso melhora muito a qualidade dos planos e revisões. Saída em `/tmp/agent-hub-init.log`.

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
├── ghcm                              entrypoint (start | config | stop | help)
├── start.sh                          setup do tmux (chamado por `ghcm start`)
├── install.sh                        cria symlink em ~/.local/bin
├── config.example.sh                 template; copiado pra config.sh no primeiro uso
├── agents/
│   ├── planner/CLAUDE.md             prompts/papéis dos agentes
│   ├── developer/CLAUDE.md
│   ├── reviewer/AGENTS.md            (codex lê AGENTS.md, claude lê CLAUDE.md)
│   └── git-manager/CLAUDE.md
└── state/<projeto>/                  estado por projeto (gitignored)
    ├── plans/{pending,done}/
    └── reviews/{pending,done/{approved,rejected,shipped}}/
```

`current-project.txt` (gitignored) registra o caminho absoluto do projeto ativo, escrito por `ghcm start`. Os agentes leem esse arquivo no começo de cada operação.

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
