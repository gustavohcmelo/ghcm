# Configuração do agent-hub.
# Edite os comandos abaixo pra trocar qual CLI roda em cada pane.
#
# CLIs com tool use (executam comandos): claude, codex, gemini, qwen
# CLIs sem tool use (só texto): ollama
#
# Sugestões de invocação não-interativa:
#   claude --dangerously-skip-permissions
#   codex  --dangerously-bypass-approvals-and-sandbox
#   gemini --yolo                                       (cuidado com cota)
#   qwen   --yolo                                       (qwen-code, fork do gemini-cli; provider em ~/.qwen/settings.json)
#   ollama run qwen2.5-coder:14b                        (sem tool use; só consulta)

PLANNER_CMD="claude --dangerously-skip-permissions"
DEVELOPER_CMD="claude --dangerously-skip-permissions"
REVIEWER_CMD="codex --dangerously-bypass-approvals-and-sandbox"
GIT_MANAGER_CMD="claude --dangerously-skip-permissions"
