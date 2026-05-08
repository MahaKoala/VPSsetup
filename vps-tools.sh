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

    echo "--- Claude Code statusline (CustomConfigs) ---"
    # Install the statusline for BOTH root and $VPS_USER so `claude` works
    # the same way regardless of who invokes it. The bundled install.sh
    # resolves "$HOME/.claude" — so we run it twice with two different HOMEs:
    #   1. as root (current context) — lands in /root/.claude
    #   2. as $VPS_USER via `sudo -Hu`  — lands in /home/<user>/.claude
    # The mktemp dir is mode 700 owned by root; we install for root first
    # while ownership is still root, then chown to $VPS_USER for step 2.
    statusline_url="https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/CustomConfigs/claude-statusline-export.tar.gz"
    statusline_tmp="$(mktemp -d)"
    if curl -fsSL "$statusline_url" -o "$statusline_tmp/bundle.tar.gz" \
       && tar -xzf "$statusline_tmp/bundle.tar.gz" -C "$statusline_tmp"; then
        if bash "$statusline_tmp/claude-statusline-export/install.sh"; then
            _st ok "claude-statusline" "installed for root"
        else
            _st warn "claude-statusline" "install failed for root"
        fi
        chown -R "$VPS_USER:$VPS_USER" "$statusline_tmp"
        if sudo -Hu "$VPS_USER" bash "$statusline_tmp/claude-statusline-export/install.sh"; then
            _st ok "claude-statusline" "installed for $VPS_USER"
        else
            _st warn "claude-statusline" "install failed for $VPS_USER"
        fi
    else
        _st warn "claude-statusline" "download/extract failed"
    fi
    rm -rf "$statusline_tmp"

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

# tmuxai multi-provider config writer — writes ~/.config/tmuxai/config.yaml.
# Schema: default_model + tmux + models map (named presets) + safety patterns.
# Three input modes:
#   1. OPENROUTER_API_KEY / OPENAI_API_KEY / ANTHROPIC_API_KEY env vars set
#      → use them directly (wizard pass-through or CI)
#   2. None set + /dev/tty reachable → prompt for each (blank skips provider)
#   3. None set + no TTY → write config with only the local-ollama entry
# Idempotent: never overwrites an existing config.yaml.
TMUXAI_CFG_DIR="$HOME/.config/tmuxai"
TMUXAI_CFG="$TMUXAI_CFG_DIR/config.yaml"

if [ -f "$TMUXAI_CFG" ]; then
    _st ok "tmuxai config" "already exists at $TMUXAI_CFG (kept)"
else
    have_env_keys=0
    [ -n "${OPENROUTER_API_KEY:-}" ] && have_env_keys=1
    [ -n "${OPENAI_API_KEY:-}" ] && have_env_keys=1
    [ -n "${ANTHROPIC_API_KEY:-}" ] && have_env_keys=1

    if (( ! have_env_keys )) && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        echo
        echo "tmuxai supports multiple providers. Configure as many as you have"
        echo "keys for; the config gets 3 model presets per provider you enable"
        echo "(best / fast / cheap). Switch at runtime: tmuxai --model <name>"
        echo
        echo "  OpenRouter   one key, all models — recommended:"
        echo "                 best:  anthropic/claude-opus-4.7"
        echo "                 fast:  anthropic/claude-haiku-4.5"
        echo "                 cheap: deepseek/deepseek-chat-v3.5"
        echo "                 https://openrouter.ai/keys"
        echo
        echo "  OpenAI       direct:"
        echo "                 best:  gpt-5.1"
        echo "                 fast:  gpt-4.1-mini"
        echo "                 cheap: gpt-4.1-nano"
        echo "                 https://platform.openai.com/api-keys"
        echo
        echo "  Anthropic    direct (no markup, full Claude reliability):"
        echo "                 best:  claude-opus-4-7   (1M context)"
        echo "                 fast:  claude-sonnet-4-6"
        echo "                 cheap: claude-haiku-4-5"
        echo "                 https://console.anthropic.com/settings/keys"
        echo
        echo "A 'local-ollama' entry is added automatically. Blank input skips."
        echo
        read -r -s -p "  OpenRouter API key (hidden, blank = skip): " OPENROUTER_API_KEY </dev/tty || true
        echo
        read -r -s -p "  OpenAI API key     (hidden, blank = skip): " OPENAI_API_KEY </dev/tty || true
        echo
        read -r -s -p "  Anthropic API key  (hidden, blank = skip): " ANTHROPIC_API_KEY </dev/tty || true
        echo
    fi

    # Pick default_model: openrouter > anthropic > openai > local-ollama
    if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        _tmuxai_default="openrouter-fast"
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        _tmuxai_default="anthropic-fast"
    elif [ -n "${OPENAI_API_KEY:-}" ]; then
        _tmuxai_default="openai-fast"
    else
        _tmuxai_default="local-ollama"
    fi

    mkdir -p "$TMUXAI_CFG_DIR"
    umask 077
    {
        cat <<YAML_EOF
# ~/.config/tmuxai/config.yaml — generated by vps-tools.sh
# Switch model at runtime:  tmuxai --model <name>

default_model: "$_tmuxai_default"

tmux:
  exec_split_args: ["-d", "-h"]

models:
YAML_EOF
        if [ -n "${OPENROUTER_API_KEY:-}" ]; then
            cat <<YAML_EOF
  # OpenRouter — one key, access to all major models. Most reliable path.
  openrouter-best:
    provider: "openrouter"
    model: "anthropic/claude-opus-4.7"
    api_key: "$OPENROUTER_API_KEY"
  openrouter-fast:
    provider: "openrouter"
    model: "anthropic/claude-haiku-4.5"
    api_key: "$OPENROUTER_API_KEY"
  openrouter-cheap:
    provider: "openrouter"
    model: "google/gemini-2.5-flash-lite"
    api_key: "$OPENROUTER_API_KEY"
YAML_EOF
        fi
        if [ -n "${OPENAI_API_KEY:-}" ]; then
            cat <<YAML_EOF
  # OpenAI direct — requires billing credits at platform.openai.com/billing.
  # If you see 'insufficient_quota' errors, top up your OpenAI account.
  openai-best:
    provider: "openai"
    model: "gpt-5.1"
    api_key: "$OPENAI_API_KEY"
  openai-fast:
    provider: "openai"
    model: "gpt-4.1-mini"
    api_key: "$OPENAI_API_KEY"
  openai-cheap:
    provider: "openai"
    model: "gpt-4.1-nano"
    api_key: "$OPENAI_API_KEY"
YAML_EOF
        fi
        if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            cat <<YAML_EOF
  # Anthropic direct — note: some tmuxai versions don't set the x-api-key
  # header correctly and return "Missing Authentication header" (401). If
  # you hit that, switch to the equivalent openrouter-* model above. Same
  # Claude models, routed through OpenRouter — works reliably.
  anthropic-best:
    provider: "anthropic"
    model: "claude-opus-4-7"
    api_key: "$ANTHROPIC_API_KEY"
  anthropic-fast:
    provider: "anthropic"
    model: "claude-sonnet-4-6"
    api_key: "$ANTHROPIC_API_KEY"
  anthropic-cheap:
    provider: "anthropic"
    model: "claude-haiku-4-5"
    api_key: "$ANTHROPIC_API_KEY"
YAML_EOF
        fi
        # local-ollama is always emitted (no key needed; ollama runs on host)
        cat <<'YAML_EOF'
  local-ollama:
    provider: "openai"
    model: "qwen2.5-coder:7b"
    api_key: "ollama"
    base_url: "http://localhost:11434/v1"

# Safety: confirm before destructive or interactive operations
exec_confirm: true
send_keys_confirm: true
paste_multiline_confirm: true

# Commands tmuxai may run without confirmation
whitelist_patterns:
  - '^pwd\s*$'
  - '^ls(\s+.*)?$'
  - '^cat(\s+.*)?$'
  - '^find(\s+.*)?$'
  - '^grep(\s+.*)?$'
  - '^git status\s*$'
  - '^git diff(\s+.*)?$'

# Commands that always require confirmation
blacklist_patterns:
  - 'rm\s+'
  - 'mv\s+'
  - 'dd\s+'
  - 'mkfs'
  - 'shutdown'
  - 'reboot'
  - 'ufw\s+'
  - 'iptables'
  - 'chown\s+'
  - 'chmod\s+777'
  - 'userdel'
  - 'passwd'

knowledge_base:
  skills:
    enabled: false
YAML_EOF
    } > "$TMUXAI_CFG"
    chmod 600 "$TMUXAI_CFG"
    umask 022

    n_providers=0
    [ -n "${OPENROUTER_API_KEY:-}" ] && n_providers=$((n_providers+1))
    [ -n "${OPENAI_API_KEY:-}" ] && n_providers=$((n_providers+1))
    [ -n "${ANTHROPIC_API_KEY:-}" ] && n_providers=$((n_providers+1))
    _st ok "tmuxai config" "written; default=$_tmuxai_default, providers=$n_providers + local-ollama"

    unset OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY _tmuxai_default n_providers have_env_keys
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

# Mirror tmuxai's config to /root/.config/tmuxai/ so `tmuxai` works when
# invoked by root too (a common point of confusion: AI tool binaries are on
# every user's PATH, but tmuxai reads ~/.config/tmuxai/config.yaml — meaning
# root's empty $HOME/.config wouldn't find anything). Each user still keeps
# its own state dir (history, MCP cache, etc.) since tmuxai uses $HOME at
# runtime.
USER_HOME_CFG="$(getent passwd "$VPS_USER" | cut -d: -f6 2>/dev/null || true)/.config/tmuxai/config.yaml"
ROOT_CFG=/root/.config/tmuxai/config.yaml
if [[ -f "$USER_HOME_CFG" && ! -f "$ROOT_CFG" ]]; then
    install -d -m 700 -o root -g root /root/.config/tmuxai
    install -m 600 -o root -g root "$USER_HOME_CFG" "$ROOT_CFG"
    printf '[STATUS] ok|tmuxai config (root)|mirrored from %s\n' "$USER_HOME_CFG"
elif [[ -f "$ROOT_CFG" ]]; then
    printf '[STATUS] ok|tmuxai config (root)|already exists at %s (kept)\n' "$ROOT_CFG"
fi

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
echo "AI tools installed under user '$VPS_USER'."
echo
echo "$(printf '\033[1;36m%s\033[0m' 'Recommended:') run AI tools as $VPS_USER, not root:"
echo "    sudo -iu $VPS_USER         # one-shot login shell"
echo "    tmuxai / claude / opencode / crush / codex"
echo
echo "$(printf '\033[2m%s\033[0m' 'For convenience, root can also use:')"
echo "  - 'claude' (symlinked to /usr/local/bin/claude — uses \$HOME for state)"
echo "  - 'tmuxai' (config mirrored to /root/.config/tmuxai/config.yaml)"
echo
echo "$(printf '\033[2m%s\033[0m' 'Each user gets its own state dir:') /home/$VPS_USER/.config/<tool>/"
echo "$(printf '\033[2m%s\033[0m' 'and') /root/.config/<tool>/ — they don't share history/MCP cache."
echo
echo "Add per-tool API keys in /etc/vps/secrets.env (mode 0600); source from .profile."
echo
echo "$(printf '\033[1;36m%s\033[0m' 'Smoke-test tmuxai now:')"
echo "    sudo -iu $VPS_USER       # switch to the user account"
echo "    tmuxai                    # interactive REPL"
echo "    TmuxAI » /model           # list configured presets"
echo "    TmuxAI » /model openrouter-fast"
echo "    TmuxAI » hi               # confirm a model responds without error"
echo "If you hit:"
echo "  insufficient_quota         → top up at platform.openai.com/account/billing"
echo "  Missing Authentication     → switch to openrouter-* (Anthropic-direct quirk)"
echo "  not a valid model ID       → check openrouter.ai/models, edit the slug"
echo "  More: see README_Troubleshooting.md §5 (AI tools)"
