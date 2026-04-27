#!/usr/bin/env bash
set -e

SESSION=agents
HUB="$HOME/agent-hub"
AGENTS="$HUB/agents"

# Carrega config do usuário (comandos por role). Se config.sh não existe,
# inicializa do template versionado. Defaults no fallback abaixo garantem
# que apagar/comentar uma variável não quebra o start.
if [ ! -f "$HUB/config.sh" ] && [ -f "$HUB/config.example.sh" ]; then
  cp "$HUB/config.example.sh" "$HUB/config.sh"
fi
[ -f "$HUB/config.sh" ] && . "$HUB/config.sh"
: "${PLANNER_CMD:=claude --dangerously-skip-permissions}"
: "${DEVELOPER_CMD:=claude --dangerously-skip-permissions}"
: "${REVIEWER_CMD:=codex --dangerously-bypass-approvals-and-sandbox}"
: "${GIT_MANAGER_CMD:=claude --dangerously-skip-permissions}"

# ---------- helpers ----------

banner() {
  local C_TITLE C_TAG C_RESET
  if [ -t 1 ]; then
    C_TITLE=$'\033[1;36m'   # ciano bold
    C_TAG=$'\033[2;37m'     # cinza claro
    C_RESET=$'\033[0m'
  fi
  cat <<EOF

${C_TITLE}     ____ _   _  ____ __  __
    / ___| | | |/ ___|  \\/  |
   | |  _| |_| | |   | |\\/| |
   | |_| |  _  | |___| |  | |
    \\____|_| |_|\\____|_|  |_|${C_RESET}

${C_TITLE}     H U B  -  A G E N T S${C_RESET}
${C_TAG}     ------------------------
     Multi-Agent Orchestrator${C_RESET}

EOF
}

progress_bar() {
  local total=$1
  local label=$2
  local cols=40
  local i pct filled empty bar
  for ((i=0; i<=total; i++)); do
    pct=$((i * 100 / total))
    filled=$((i * cols / total))
    empty=$((cols - filled))
    bar=$(printf '%*s' "$filled" '' | tr ' ' '=')
    bar+=$(printf '%*s' "$empty" ''   | tr ' ' '-')
    printf "\r  %s [%s] %3d%% - %ds restantes  " "$label" "$bar" "$pct" "$((total - i))"
    [ $i -lt $total ] && sleep 1
  done
  printf "\r  %s [%s] %3d%% - pronto                \n" \
    "$label" "$(printf '%*s' "$cols" '' | tr ' ' '=')" 100
}

# ---------- main ----------

clear 2>/dev/null || true
banner

PROJECT_DIR="${1:-$PWD}"
PROJECT_DIR=$(cd "$PROJECT_DIR" 2>/dev/null && pwd) || {
  echo "Erro: '$1' não é um diretório válido." >&2
  exit 1
}

if [ ! -d "$PROJECT_DIR/.git" ]; then
  echo "Aviso: $PROJECT_DIR não é um repositório git."
  read -r -p "Continuar mesmo assim? [y/N] " ans
  [[ "$ans" =~ ^[yY] ]] || exit 1
fi

PROJECT_SLUG=$(basename "$PROJECT_DIR")
STATE="$HUB/state/$PROJECT_SLUG"

mkdir -p "$STATE/plans/pending" "$STATE/plans/done" \
         "$STATE/reviews/pending" \
         "$STATE/reviews/done/approved" \
         "$STATE/reviews/done/rejected" \
         "$STATE/reviews/done/shipped"

echo "$PROJECT_DIR" > "$HUB/current-project.txt"

printf "  %-14s %s\n" "Projeto:" "$PROJECT_DIR"
printf "  %-14s %s\n" "Slug:"    "$PROJECT_SLUG"
printf "  %-14s %s\n" "State:"   "$STATE"
echo

# Se o projeto não tem context file, roda /init pra mapear antes de subir os agentes.
if [ ! -f "$PROJECT_DIR/CLAUDE.md" ] && [ ! -f "$PROJECT_DIR/AGENTS.md" ]; then
  echo "  Projeto sem CLAUDE.md/AGENTS.md — rodando /init pra mapear o projeto."
  echo "  (pode levar 1-3 min; log: /tmp/agent-hub-init.log)"
  if ( cd "$PROJECT_DIR" && claude --dangerously-skip-permissions -p "/init" ) \
       > /tmp/agent-hub-init.log 2>&1; then
    if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
      echo "  OK: CLAUDE.md gerado."
      if [ ! -e "$PROJECT_DIR/AGENTS.md" ]; then
        cp "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md"
        echo "  OK: AGENTS.md criado (cópia de CLAUDE.md, pro codex/reviewer)."
      fi
    else
      echo "  AVISO: /init terminou sem criar CLAUDE.md. Veja /tmp/agent-hub-init.log"
    fi
  else
    echo "  AVISO: /init falhou. Veja /tmp/agent-hub-init.log"
  fi
  echo
fi

if tmux has-session -t $SESSION 2>/dev/null; then
  echo "  Sessão tmux 'agents' já existe — anexando."
  exec tmux attach -t $SESSION
fi

# Captura pane IDs estáveis (%X) na criação. Não dependem de select-layout.
PLANNER=$(tmux new-session -d -s $SESSION -x 240 -y 60 \
  -c "$AGENTS/planner" -P -F '#{pane_id}')

DEVELOPER=$(tmux split-window -h -t "$PLANNER" \
  -c "$AGENTS/developer" -P -F '#{pane_id}')

REVIEWER=$(tmux split-window -v -t "$PLANNER" \
  -c "$AGENTS/reviewer" -P -F '#{pane_id}')

GIT_MANAGER=$(tmux split-window -v -t "$DEVELOPER" \
  -c "$AGENTS/git-manager" -P -F '#{pane_id}')

tmux select-layout -t $SESSION:0 tiled
# Interface limpa: sem status bar inferior nem barra de borda superior
tmux set -t $SESSION -g status off
tmux set -t $SESSION -g pane-border-status off

tmux send-keys -t "$PLANNER"     "$PLANNER_CMD"     Enter
tmux send-keys -t "$DEVELOPER"   "$DEVELOPER_CMD"   Enter
tmux send-keys -t "$REVIEWER"    "$REVIEWER_CMD"    Enter
tmux send-keys -t "$GIT_MANAGER" "$GIT_MANAGER_CMD" Enter

echo "  Subindo CLIs nos 4 panes:"
printf "    %-12s -> %s\n" "PLANNER"     "$PLANNER_CMD"
printf "    %-12s -> %s\n" "DEVELOPER"   "$DEVELOPER_CMD"
printf "    %-12s -> %s\n" "REVIEWER"    "$REVIEWER_CMD"
printf "    %-12s -> %s\n" "GIT-MANAGER" "$GIT_MANAGER_CMD"
echo

progress_bar 10 "Aguardando inicialização"

echo
echo "  Fluxo: PLANNER → aprova → DEVELOPER → REVIEWER → GIT-MANAGER"
echo "  Ctrl-b d  desanexar  (volta com: tmux attach -t agents)"
echo

sleep 1
exec tmux attach -t $SESSION
