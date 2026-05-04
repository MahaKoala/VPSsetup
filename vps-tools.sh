#!/usr/bin/env bash
# vps-tools.sh — install AI/agent tooling for $VPS_USER
set -Eeuo pipefail
ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
# shellcheck disable=SC1090
source "$ENV_FILE"

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

run_as_user() { sudo -Hiu "$VPS_USER" bash -lc "$*"; }

# Most coding agents publish brew taps; prefer brew where possible.
run_as_user '
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

  # Code agents
  brew install sst/tap/opencode || true
  brew install charmbracelet/tap/crush || true
  brew install codex || true                  # OpenAI Codex CLI
  brew install --cask claude-code 2>/dev/null || \
    curl -fsSL https://claude.ai/install.sh | bash || true

  # Terminal niceties
  brew install lazygit glow ranger zoxide btop chafa csvlens || true

  # tmuxai
  curl -fsSL https://get.tmuxai.dev | bash || true

  # tmux plugin manager (per-user)
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
'

# Ollama runs as a system daemon
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama || true

echo "Tools installed. Configure secrets via /etc/vps/secrets.env (see notes)."