#!/usr/bin/env bash
# Instalador do GHCM HUB-AGENTS.
# Uso: ~/agent-hub/install.sh
#
# Cria symlink ~/.local/bin/ghcm apontando pro repo clonado.
# Verifica dependências e avisa o que falta.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

if [ ! -x "$REPO_DIR/ghcm" ]; then
  echo "Erro: $REPO_DIR/ghcm não encontrado ou não executável." >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/ghcm" "$BIN_DIR/ghcm"
echo "OK: $BIN_DIR/ghcm -> $REPO_DIR/ghcm"

if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
  echo
  echo "AVISO: $BIN_DIR não está no PATH."
  echo "Adicione ao seu ~/.bashrc ou ~/.zshrc:"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

echo
echo "Verificando dependências:"
required=(tmux git)
optional=(gh claude codex gemini ollama)

missing_required=0
for d in "${required[@]}"; do
  if command -v "$d" >/dev/null 2>&1; then
    printf "  [OK]      %-8s %s\n" "$d" "$(command -v "$d")"
  else
    printf "  [FALTA]   %-8s (obrigatório)\n" "$d"
    missing_required=1
  fi
done

echo "  ---"
for d in "${optional[@]}"; do
  if command -v "$d" >/dev/null 2>&1; then
    printf "  [OK]      %-8s %s\n" "$d" "$(command -v "$d")"
  else
    printf "  [opcional] %-8s (instale se for usar essa CLI em algum role)\n" "$d"
  fi
done

if [ $missing_required -eq 1 ]; then
  echo
  echo "Instale as dependências obrigatórias antes de rodar 'ghcm start'."
  exit 1
fi

echo
echo "Pronto. Rode 'ghcm help' pra começar."
