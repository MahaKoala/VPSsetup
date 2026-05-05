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

# Tee output into the shared log so the end-of-install report (in vps-init.sh)
# can parse [STATUS] lines from this run too.
LOG=/var/log/vps-bootstrap.log
exec > >(tee -a "$LOG") 2>&1

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

# [STATUS] kind|step|detail — parsed by vps-init.sh's end-of-install report
_st() { printf '[STATUS] %s|%s|%s\n' "$1" "$2" "${3:-}"; }

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

    echo "--- code agents (brew taps) ---"
    for tap_pkg in sst/tap/opencode charmbracelet/tap/crush; do
        pkg_short="${tap_pkg##*/}"
        if brew list "$pkg_short" >/dev/null 2>&1; then
            _st ok "$pkg_short" "already installed"
        elif brew install "$tap_pkg"; then
            _st ok "$pkg_short" "installed via tap"
        else
            _st warn "$pkg_short" "tap install failed"
        fi
    done

    echo "--- OpenAI Codex CLI ---"
    if command -v npm >/dev/null; then
        if npm i -g @openai/codex; then
            _st ok "@openai/codex" "installed via npm"
        else
            _st warn "@openai/codex" "npm install failed"
        fi
    else
        _st warn "@openai/codex" "npm not found; skipped"
    fi

    echo "--- Anthropic Claude Code ---"
    if curl -fsSL https://claude.ai/install.sh | bash; then
        _st ok "claude-code" "installed"
    else
        _st warn "claude-code" "installer failed"
    fi

    echo "--- terminal niceties ---"
    for pkg in lazygit glow ranger zoxide btop chafa csvlens; do
        if brew list --formula "$pkg" >/dev/null 2>&1; then
            _st ok "brew $pkg" "already installed"
        elif brew install "$pkg"; then
            _st ok "brew $pkg" "installed"
        else
            _st warn "brew $pkg" "install failed"
        fi
    done
else
    _st fail "brew" "not found at /home/linuxbrew/.linuxbrew/bin/brew — skipping all brew tools"
fi

# Ensure ~/.local/bin is in PATH (Claude Code installs there). Idempotent.
LOCAL_BIN_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for rc in "$HOME/.profile" "$HOME/.bashrc"; do
    [ -f "$rc" ] || touch "$rc"
    grep -qxF "$LOCAL_BIN_LINE" "$rc" || printf '\n%s\n' "$LOCAL_BIN_LINE" >> "$rc"
done
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

echo "--- tmuxai ---"
if curl -fsSL https://get.tmuxai.dev | bash; then
    _st ok "tmuxai" "installed"
else
    _st warn "tmuxai" "installer failed"
fi

# tmuxai config — write ~/.config/tmuxai/config.yaml.
# Three input modes, in order of precedence:
#   1. TMUXAI_API_KEY env var set      → write config from env vars (CI/wizard)
#   2. /dev/tty available, no env var  → prompt the operator interactively
#   3. neither                         → leave the example file alone (skip)
# Idempotent: never overwrites an existing config.yaml.
TMUXAI_CFG_DIR="$HOME/.config/tmuxai"
TMUXAI_CFG="$TMUXAI_CFG_DIR/config.yaml"

if [ -f "$TMUXAI_CFG" ]; then
    _st ok "tmuxai config" "already exists at $TMUXAI_CFG (kept)"
else
    if [ -z "${TMUXAI_API_KEY:-}" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        echo
        echo "tmuxai needs an LLM API key. OpenRouter recommended:"
        echo "  https://openrouter.ai/keys"
        echo "Press Enter at the API key prompt to skip; configure later."
        read -r -p "  Provider (openrouter/openai/azure) [openrouter]: " _tx_p </dev/tty
        read -r -p "  Model [anthropic/claude-haiku-4.5]: " _tx_m </dev/tty
        read -r -s -p "  API key (input hidden, blank to skip): " _tx_k </dev/tty
        echo
        TMUXAI_PROVIDER="${_tx_p:-${TMUXAI_PROVIDER:-openrouter}}"
        TMUXAI_MODEL="${_tx_m:-${TMUXAI_MODEL:-anthropic/claude-haiku-4.5}}"
        TMUXAI_API_KEY="$_tx_k"
        unset _tx_p _tx_m _tx_k
    fi

    if [ -n "${TMUXAI_API_KEY:-}" ]; then
        mkdir -p "$TMUXAI_CFG_DIR"
        umask 077
        cat > "$TMUXAI_CFG" <<YAML_EOF
models:
  primary:
    provider: ${TMUXAI_PROVIDER:-openrouter}
    model: ${TMUXAI_MODEL:-anthropic/claude-haiku-4.5}
    api_key: $TMUXAI_API_KEY
YAML_EOF
        chmod 600 "$TMUXAI_CFG"
        umask 022
        _st ok "tmuxai config" "written to $TMUXAI_CFG"
        unset TMUXAI_API_KEY
    else
        _st warn "tmuxai config" "no API key; skipped (edit $TMUXAI_CFG manually to enable)"
    fi
fi

echo "--- tmux plugin manager ---"
if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    _st ok "tpm" "already cloned"
elif git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; then
    _st ok "tpm" "cloned"
else
    _st warn "tpm" "git clone failed"
fi
INNER_EOF

# Bridge user-local AI tools into /usr/local/bin so root (and any other user)
# can invoke them. Claude Code's official installer drops the binary in
# ~/.local/bin which is per-user — root's PATH won't see it. The binary
# itself uses $HOME for state, so each user gets their own config dir.
echo "--- system-wide tool symlinks ---"
USER_HOME="$(getent passwd "$VPS_USER" | cut -d: -f6 2>/dev/null || true)"
if [[ -n "$USER_HOME" ]]; then
    for bin in claude; do
        src="$USER_HOME/.local/bin/$bin"
        dst="/usr/local/bin/$bin"
        if [[ -x "$src" ]]; then
            ln -sf "$src" "$dst"
            printf '[STATUS] ok|symlink %s|%s -> %s\n' "$bin" "$dst" "$src"
        else
            printf '[STATUS] warn|symlink %s|source not found at %s\n' "$bin" "$src"
        fi
    done
fi

# Ollama runs as a system daemon, not under $VPS_USER
echo "--- Ollama (system daemon) ---"
if command -v ollama &>/dev/null; then
    printf '[STATUS] ok|ollama|already installed\n'
elif curl -fsSL https://ollama.com/install.sh | sh; then
    printf '[STATUS] ok|ollama|installed\n'
else
    printf '[STATUS] warn|ollama|installer failed\n'
fi
if systemctl enable --now ollama 2>/dev/null; then
    printf '[STATUS] ok|ollama service|enabled\n'
else
    printf '[STATUS] warn|ollama service|could not enable\n'
fi

echo "===== vps-tools complete @ $(date -Is) ====="
echo
echo "AI tools are installed under: $VPS_USER"
echo "  - For full per-user state (config, history, MCP servers):"
echo "      sudo -iu $VPS_USER       # then run claude / opencode / etc."
echo "  - 'claude' is also symlinked to /usr/local/bin/claude so it works from any account"
echo "    (it uses \$HOME for state, so root and $VPS_USER each get their own config dir)"
echo
echo "Configure API keys in /etc/vps/secrets.env (mode 0600); source it from the user's .profile."
