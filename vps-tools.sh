#!/usr/bin/env bash
# vps-tools.sh — install AI/agent tooling for $VPS_USER
set -Eeuo pipefail
ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }
[[ -n "${VPS_USER:-}" ]] || { echo "VPS_USER not set in $ENV_FILE"; exit 1; }
id -u "$VPS_USER" &>/dev/null || { echo "User $VPS_USER does not exist; run vps-bootstrap.sh first"; exit 1; }

run_as_user() { sudo -Hiu "$VPS_USER" bash -lc "$*"; }

# Most coding agents publish brew taps; prefer brew where possible.
run_as_user '
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

    # Code agents (brew taps)
    brew install sst/tap/opencode || true
    brew install charmbracelet/tap/crush || true

    # OpenAI Codex CLI — no Linux brew formula; install via npm if node is present
    if command -v npm >/dev/null; then
      npm i -g @openai/codex || true
    else
      echo "WARN: npm not found; skipping @openai/codex"
    fi

    # Anthropic Claude Code — official installer (no Linux brew/cask)
    curl -fsSL https://claude.ai/install.sh | bash || true

    # Terminal niceties
    brew install lazygit glow ranger zoxide btop chafa csvlens || true
  else
    echo "WARN: brew not found at /home/linuxbrew/.linuxbrew/bin/brew — skipping brew tools"
  fi

  # tmuxai (curl installer; no brew tap)
  curl -fsSL https://get.tmuxai.dev | bash || true

  # tmux plugin manager (per-user)
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" || true
  fi
'

# Ollama runs as a system daemon
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama || true

echo "Tools installed. Configure secrets via /etc/vps/secrets.env (see notes)."
