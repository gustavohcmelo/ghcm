#!/usr/bin/env bash
set -e

HUB="$HOME/agent-hub"
AGENTS="$HUB/agents"
LOGS="$HUB/logs"

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

# Banner ASCII completo (terminais largos).
banner_full() {
  local C_TITLE C_TAG C_RESET
  if [ -t 1 ]; then
    C_TITLE=$'\033[1;36m'
    C_TAG=$'\033[2;37m'
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
     Gated Hub CLI Manager${C_RESET}

EOF
}

# Banner compacto (terminais estreitos).
banner_compact() {
  local C_TITLE C_RESET
  if [ -t 1 ]; then
    C_TITLE=$'\033[1;36m'
    C_RESET=$'\033[0m'
  fi
  cat <<EOF

${C_TITLE}GHCM HUB-AGENTS${C_RESET}
Gated Hub CLI Manager

EOF
}

banner() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  if [ "$cols" -lt 50 ]; then
    banner_compact
  else
    banner_full
  fi
}

# Valida dependências (tmux, git, CLIs configurados). Aborta se faltar
# obrigatórias. Avisa sobre opcionais (gh) sem abortar.
preflight() {
  local missing=()
  command -v tmux   >/dev/null 2>&1 || missing+=("tmux")
  command -v git    >/dev/null 2>&1 || missing+=("git")
  command -v pandoc >/dev/null 2>&1 || missing+=("pandoc")

  local cmd_var cmd_val cli
  for cmd_var in PLANNER_CMD DEVELOPER_CMD REVIEWER_CMD GIT_MANAGER_CMD; do
    cmd_val="${!cmd_var}"
    cli="${cmd_val%% *}"
    if ! command -v "$cli" >/dev/null 2>&1; then
      missing+=("$cli (configurado em $cmd_var)")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "  Erro: dependências faltando:" >&2
    printf "    - %s\n" "${missing[@]}" >&2
    echo >&2
    echo "  Instale e rode novamente. Veja config: ghcm config" >&2
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "  Aviso: 'gh' não autenticado — git-manager vai falhar ao criar PR."
    echo "         Resolva com: gh auth login"
    echo
  fi
}

# Marker de "TUI pronta" por CLI. Usa textos estáveis que aparecem sempre
# que o CLI sobe nos modos não-interativos que configuramos.
ready_marker_for() {
  case "$1" in
    claude) echo 'bypass permissions|Claude Code v|Welcome back' ;;
    codex)  echo 'YOLO mode|OpenAI Codex|model:' ;;
    gemini) echo 'Gemini|GEMINI.md' ;;
    ollama) echo '>>>' ;;
    *)      echo 'bypass permissions|YOLO mode|>>>|❯' ;;
  esac
}

# Aguarda os panes ficarem prontos via heurística: capture-pane periódico
# até ver um marker específico do CLI rodando em cada um. Mostra progresso
# e desiste após timeout. Retorna 0 se todos prontos, 1 se timeout.
# Args: lista de pares "pane_id:cli_name" (ex: "%1:claude").
wait_for_ready() {
  local entries=("$@")
  local timeout=45
  local cols=40
  local total=${#entries[@]}
  local i ready

  for ((i=0; i<timeout; i++)); do
    ready=0
    for entry in "${entries[@]}"; do
      local pane="${entry%%:*}"
      local cli="${entry##*:}"
      local marker
      marker=$(ready_marker_for "$cli")
      local content
      content=$(tmux capture-pane -t "$pane" -p -S -200 2>/dev/null || echo "")
      if echo "$content" | grep -qE "$marker"; then
        ready=$((ready + 1))
      fi
    done

    local filled=$((ready * cols / total))
    local empty=$((cols - filled))
    local bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '=')
    bar+=$(printf '%*s' "$empty" ''  | tr ' ' '-')
    printf "\r  Aguardando CLIs [%s] %d/%d prontos  " "$bar" "$ready" "$total"

    if [ "$ready" -eq "$total" ]; then
      printf "\r  CLIs prontos    [%s] %d/%d - ok                       \n" \
        "$(printf '%*s' "$cols" '' | tr ' ' '=')" "$total" "$total"
      return 0
    fi

    sleep 1
  done

  printf "\r  Aguardando CLIs [%s] timeout - atachando assim mesmo  \n" \
    "$(printf '%*s' "$cols" '' | tr ' ' '?')"
  return 1
}

# Roda 'claude /init' headless no projeto, mostrando só um timer em segundos
# (atualizado in-place) pra confirmar que está vivo. A saída completa do
# claude vai pro $log_file pra inspeção posterior em caso de falha.
run_init_with_tail() {
  local project_dir=$1
  local log_file=$2

  : > "$log_file"
  local start
  start=$(date +%s)

  ( cd "$project_dir" && claude --dangerously-skip-permissions -p "/init" ) \
    > "$log_file" 2>&1 &
  local init_pid=$!

  while kill -0 "$init_pid" 2>/dev/null; do
    local elapsed=$(($(date +%s) - start))
    printf "\r  Criando arquivos de contexto... %ds" "$elapsed"
    sleep 1
  done

  wait "$init_pid"
  local rc=$?
  local elapsed=$(($(date +%s) - start))
  if [ "$rc" -eq 0 ]; then
    printf "\r  Criando arquivos de contexto... %ds ✓\n" "$elapsed"
  else
    printf "\r  Criando arquivos de contexto... %ds (falhou)\n" "$elapsed"
  fi
  return $rc
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
  echo "  Aviso: $PROJECT_DIR não é um repositório git."
  read -r -p "  Continuar mesmo assim? [y/N] " ans
  [[ "$ans" =~ ^[yY] ]] || exit 1
fi

PROJECT_SLUG=$(basename "$PROJECT_DIR")
STATE="$HUB/state/$PROJECT_SLUG"
SESSION="agents-$PROJECT_SLUG"

mkdir -p "$STATE/plans/pending" "$STATE/plans/done" \
         "$STATE/reviews/pending" \
         "$STATE/reviews/done/approved" \
         "$STATE/reviews/done/rejected" \
         "$STATE/reviews/done/shipped" \
         "$LOGS"

echo "$PROJECT_DIR" > "$HUB/current-project.txt"
# Guarda o path absoluto do projeto pra esse slug, pra ghcm status saber
# resolver o slug -> path mesmo quando o current-project é outro.
echo "$PROJECT_DIR" > "$STATE/.project-path"

printf "  %-14s %s\n" "Projeto:" "$PROJECT_DIR"
printf "  %-14s %s\n" "Slug:"    "$PROJECT_SLUG"
printf "  %-14s %s\n" "Sessão:"  "$SESSION"
printf "  %-14s %s\n" "State:"   "$STATE"
echo

preflight

# Se o projeto não tem context file, roda /init pra mapear antes de subir.
echo "  Verificando arquivos de contexto (CLAUDE.md, AGENTS.md)..."
if [ ! -f "$PROJECT_DIR/CLAUDE.md" ] && [ ! -f "$PROJECT_DIR/AGENTS.md" ]; then
  echo "  Não encontrados — vou criar."
  init_log="$LOGS/$(date +%Y%m%d-%H%M%S)-init-${PROJECT_SLUG}.log"
  if run_init_with_tail "$PROJECT_DIR" "$init_log"; then
    if [ -f "$PROJECT_DIR/CLAUDE.md" ] && [ ! -e "$PROJECT_DIR/AGENTS.md" ]; then
      cp "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md"
    fi
  else
    echo "  Log: $init_log"
  fi
  echo
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "  Sessão tmux '$SESSION' já existe — anexando."
  exec tmux attach -t "$SESSION"
fi

# Captura pane IDs estáveis (%X) na criação. Não dependem de select-layout.
PLANNER=$(tmux new-session -d -s "$SESSION" -x 240 -y 60 \
  -c "$AGENTS/planner" -P -F '#{pane_id}')

DEVELOPER=$(tmux split-window -h -t "$PLANNER" \
  -c "$AGENTS/developer" -P -F '#{pane_id}')

REVIEWER=$(tmux split-window -v -t "$PLANNER" \
  -c "$AGENTS/reviewer" -P -F '#{pane_id}')

GIT_MANAGER=$(tmux split-window -v -t "$DEVELOPER" \
  -c "$AGENTS/git-manager" -P -F '#{pane_id}')

tmux select-layout -t "$SESSION:0" tiled
# Interface limpa: sem status bar inferior, com título no topo de cada pane.
tmux set -t "$SESSION" -g status off
tmux set -t "$SESSION" -g pane-border-status top
# Usa variável user-defined @role_label (resistente a sobrescritas que
# claude/codex fazem em pane_title via escape sequences).
tmux set -t "$SESSION" -g pane-border-format " #{@role_label} "
# Notificação visual: pisca o pane border quando fica silencioso por 5s
# (agente terminou de responder).
tmux set -t "$SESSION" -g visual-silence on
tmux set -t "$SESSION" -g visual-bell off
tmux set -t "$SESSION" -g bell-action none

# Atalho pra encerrar a sessão sem precisar de `:kill-session`.
# Ctrl-b X com confirmação interativa.
tmux bind-key -T prefix X confirm-before -p "Encerrar sessão #S? (y/n)" kill-session

tmux set -t "$PLANNER"     -p @role_label "#[fg=cyan,bold]PLANNER [${PLANNER_CMD%% *}]#[default]"
tmux set -t "$DEVELOPER"   -p @role_label "#[fg=green,bold]DEVELOPER [${DEVELOPER_CMD%% *}]#[default]"
tmux set -t "$REVIEWER"    -p @role_label "#[fg=yellow,bold]REVIEWER [${REVIEWER_CMD%% *}]#[default]"
tmux set -t "$GIT_MANAGER" -p @role_label "#[fg=magenta,bold]GIT-MANAGER [${GIT_MANAGER_CMD%% *}]#[default]"

# Cor da borda por pane: combina com a cor do título e ajuda a identificar
# o agente de relance. -p define como pane option (não global).
tmux set -t "$PLANNER"     -p pane-border-style        "fg=cyan"
tmux set -t "$PLANNER"     -p pane-active-border-style "fg=brightcyan,bold"
tmux set -t "$DEVELOPER"   -p pane-border-style        "fg=green"
tmux set -t "$DEVELOPER"   -p pane-active-border-style "fg=brightgreen,bold"
tmux set -t "$REVIEWER"    -p pane-border-style        "fg=yellow"
tmux set -t "$REVIEWER"    -p pane-active-border-style "fg=brightyellow,bold"
tmux set -t "$GIT_MANAGER" -p pane-border-style        "fg=magenta"
tmux set -t "$GIT_MANAGER" -p pane-active-border-style "fg=brightmagenta,bold"

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

# O `|| true` é crítico: wait_for_ready retorna 1 em timeout, e com `set -e`
# isso abortaria o script ANTES do `exec tmux attach` no final, deixando a
# sessão tmux rodando detached e o usuário sem feedback no terminal.
wait_for_ready \
  "$PLANNER:${PLANNER_CMD%% *}" \
  "$DEVELOPER:${DEVELOPER_CMD%% *}" \
  "$REVIEWER:${REVIEWER_CMD%% *}" \
  "$GIT_MANAGER:${GIT_MANAGER_CMD%% *}" || true

# Ativa monitor-silence DEPOIS dos CLIs estarem rodando, pra que o silêncio
# inicial (subida) não dispare alerta. 5s de silêncio = agente parou.
for pane in "$PLANNER" "$DEVELOPER" "$REVIEWER" "$GIT_MANAGER"; do
  tmux set-option -t "$pane" -p monitor-silence 5 || true
done

echo
echo "  Fluxo: PLANNER → aprova → DEVELOPER → REVIEWER → GIT-MANAGER"
echo "  Ctrl-b d  desanexar  (volta com: ghcm attach $PROJECT_SLUG)"
echo "  Ctrl-b X  encerrar a sessão (com confirmação)"
echo

sleep 1
exec tmux attach -t "$SESSION"
