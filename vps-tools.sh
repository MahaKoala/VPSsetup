#!/usr/bin/env bash
# vps-tools.sh — install AI/agent tooling for $VPS_USER
#
# Usage:
#   sudo /usr/local/sbin/vps-tools.sh
#   sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-tools.sh)
#
# Idempotent. Safe to re-run.

set -Eeuo pipefail

# Root check FIRST — /etc/vps/bootstrap.env is mode 600, so a non-root run
# would fail at `source` with "Permission denied" before we get to give a
# friendly error.
[[ $EUID -eq 0 ]] || { echo "Must run as root (try: sudo $0)"; exit 1; }

ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE — run vps-bootstrap.sh first"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

[[ -n "${VPS_USER:-}" ]] || { echo "VPS_USER not set in $ENV_FILE"; exit 1; }
id -u "$VPS_USER" &>/dev/null || { echo "User $VPS_USER does not exist; run vps-bootstrap.sh first"; exit 1; }

echo "===== vps-tools @ $(date -Is) ====="
echo "Installing AI/agent tooling for user: $VPS_USER"

# Run the user-side install via stdin heredoc, NOT `bash -lc "$multi-line"`.
# `bash -lc` round-trips the script through argv and collapses newlines on
# some sudo/kernel combos, breaking compound statements. `bash -s` reads the
# script from stdin where newlines are inviolable.
#
# `cd "$HOME"` first because brew refuses to run when CWD is unreadable
# (e.g. /root after `sudo -Hu` without -i changing directory).
sudo -Hu "$VPS_USER" bash -l -s <<'INNER_EOF'
set +e   # don't abort the whole tools run if one upstream is flaky
cd "$HOME"

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

    echo "--- code agents (brew taps) ---"
    brew install sst/tap/opencode      || echo "WARN: opencode failed"
    brew install charmbracelet/tap/crush || echo "WARN: crush failed"

    echo "--- OpenAI Codex CLI ---"
    if command -v npm >/dev/null; then
        npm i -g @openai/codex || echo "WARN: @openai/codex npm install failed"
    else
        echo "WARN: npm not found; skipping @openai/codex"
    fi

    echo "--- Anthropic Claude Code ---"
    curl -fsSL https://claude.ai/install.sh | bash || echo "WARN: claude-code install failed"

    echo "--- terminal niceties ---"
    brew install lazygit glow ranger zoxide btop chafa csvlens || echo "WARN: some terminal tools failed"
else
    echo "WARN: brew not found at /home/linuxbrew/.linuxbrew/bin/brew — skipping brew tools"
fi

# Ensure ~/.local/bin is in PATH so claude (and any other ~/.local/bin tool)
# resolves in fresh shells. Idempotent: case-pattern skips when already present.
LOCAL_BIN_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for rc in "$HOME/.profile" "$HOME/.bashrc"; do
    [ -f "$rc" ] || touch "$rc"
    grep -qxF "$LOCAL_BIN_LINE" "$rc" || printf '\n%s\n' "$LOCAL_BIN_LINE" >> "$rc"
done
# Also export for the rest of THIS heredoc's commands (so any post-install
# verification can find claude / other ~/.local/bin tools).
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

echo "--- tmuxai ---"
curl -fsSL https://get.tmuxai.dev | bash || echo "WARN: tmuxai install failed"

echo "--- tmux plugin manager ---"
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
        || echo "WARN: tpm clone failed"
fi
INNER_EOF

# Ollama runs as a system daemon, not under $VPS_USER
echo "--- Ollama (system daemon) ---"
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama || echo "WARN: could not enable ollama service"

echo "===== vps-tools complete @ $(date -Is) ====="
echo "Configure API keys in /etc/vps/secrets.env (mode 0600); source it from the user's .profile."
