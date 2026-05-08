#!/usr/bin/env bash
# vps-init.sh — one-shot, self-contained Ubuntu 24.04 VPS provisioner.
# Works on any provider (Hetzner, DigitalOcean, Vultr, Linode, Contabo,
# OVH, RackNerd, Scaleway, etc.) with or without cloud-init.
#
# Usage:
#   # one-liner from a fresh root SSH session (recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)
#
#   # also works (prompts read from /dev/tty):
#   curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | bash
#
#   # or scp + run:
#   scp vps-init.sh root@HOST:/root/ && ssh root@HOST 'bash /root/vps-init.sh'
#
#   # non-interactive (for agents / automation):
#   VPS_USER=pink SSH_ID=mahakoala TAILSCALE_AUTHKEY=tskey-... NONINTERACTIVE=1 \
#     bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)
#
# Idempotent. Safe to re-run.

set -Eeuo pipefail
umask 022

[[ $EUID -eq 0 ]] || { echo "Run as root (try: sudo bash $0)"; exit 1; }

# ------------------------------------------------------------------------------
# OS sanity check
# ------------------------------------------------------------------------------
. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
    ubuntu|debian) : ;;
    *) echo "WARN: untested OS (${ID:-unknown}). Proceeding anyway in 3s..."; sleep 3 ;;
esac

# ------------------------------------------------------------------------------
# Defaults (override via env vars)
# ------------------------------------------------------------------------------
: "${VPS_USER:=maha}"
: "${VPS_HOSTNAME:=}"
: "${VPS_HOSTNAME_PREFIX:=deployeddigital}"
: "${VPS_ROLE:=dev}"

: "${SSH_ID:=}"
: "${SSH_GH_USER:=}"
: "${SSH_AUTHORIZED_KEYS:=}"

: "${INSTALL_BREW:=1}"
: "${BREW_PACKAGES:=starship eza tldr zoxide btop fd ripgrep bat git-delta lazygit glow ranger jq yq fzf gh node oven-sh/bun/bun pnpm yarn go}"
: "${INSTALL_NODE_LTS:=0}"
: "${INSTALL_DOCKER:=0}"
: "${ENABLE_PASSWORDLESS_SUDO:=1}"

: "${SSH_PORT:=22}"
: "${ALLOW_PASSWORD_AUTH:=no}"
: "${PERMIT_ROOT_LOGIN:=prohibit-password}"
: "${LIMIT_SSH_TO_ADMIN_USER:=1}"
: "${HARDEN_SSH:=1}"
: "${ENABLE_UFW:=1}"
: "${PUBLIC_SSH_ALLOWED:=1}"
: "${ALLOW_HTTP_HTTPS:=0}"
: "${EXTRA_UFW_PORTS:=}"
: "${ENABLE_FAIL2BAN:=1}"
: "${ENABLE_UNATTENDED:=1}"
: "${ENABLE_SYSCTL_HARDENING:=1}"

: "${INSTALL_TAILSCALE:=1}"
: "${TAILSCALE_AUTHKEY:=}"
: "${TAILSCALE_HOSTNAME:=}"
: "${TAILSCALE_TAGS:=}"   # empty = use whatever tags the auth key was generated with
: "${TAILSCALE_SSH:=1}"
: "${TAILSCALE_ACCEPT_DNS:=false}"
: "${TAILSCALE_ADVERTISE_ROUTES:=}"
: "${TAILSCALE_EXIT_NODE:=0}"
: "${TAILSCALE_EXTRA_ARGS:=--accept-routes}"

: "${INSTALL_TOOLS:=0}"
# tmuxai is configured with multi-provider model presets. Provide whichever
# API keys you have; the config gets one entry per available provider × tier
# (best / fast / cheap). All three blank → config still written with just the
# always-on local-ollama entry.
: "${OPENROUTER_API_KEY:=}"
: "${OPENAI_API_KEY:=}"
: "${ANTHROPIC_API_KEY:=}"

: "${NONINTERACTIVE:=}"
: "${RUN_HARDEN:=1}"

# Interactive if: a controlling terminal is reachable (works for `bash script`,
# `bash <(curl ...)`, AND `curl ... | bash` since prompts read from /dev/tty)
# unless the user explicitly forced non-interactive.
if [[ -z "$NONINTERACTIVE" ]] && [[ -r /dev/tty && -w /dev/tty ]]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# ------------------------------------------------------------------------------
# Prompt helpers
# ------------------------------------------------------------------------------
c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
hdr() { echo; echo "$(c '1;34' "── $* ──")"; }

ask() {
    # ask "prompt" VAR_NAME [default]
    local prompt="$1" var="$2" def="${3:-}" val line
    line="$prompt"
    [[ -n "$def" ]] && line+=" $(c '2' "[$def]")"
    read -r -p "$line: " val </dev/tty
    [[ -z "$val" ]] && val="$def"
    printf -v "$var" '%s' "$val"
}

ask_secret() {
    local prompt="$1" var="$2" val
    read -r -s -p "$prompt: " val </dev/tty
    echo
    printf -v "$var" '%s' "$val"
}

ask_yn() {
    local prompt="$1" def="$2" val hint
    [[ "$def" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
    while :; do
        read -r -p "$prompt $hint " val </dev/tty
        val="${val:-$def}"
        case "$val" in [Yy]*) return 0;; [Nn]*) return 1;; esac
    done
}

# ------------------------------------------------------------------------------
# Interactive wizard
# ------------------------------------------------------------------------------
if (( INTERACTIVE )); then
    echo
    echo "$(c '1;34' '════════════════════════════════════════════════════')"
    echo "$(c '1;34' '  VPS Init — Ubuntu 24.04 provisioning wizard')"
    echo "$(c '1;34' '════════════════════════════════════════════════════')"
    echo "Press Enter to accept defaults. Ctrl-C to abort."

    hdr "Identity"
    ask  "Primary username"                    VPS_USER            "${VPS_USER:-maha}"
    ask  "Role (staging / production / dev)"   VPS_ROLE            "${VPS_ROLE}"
    ask  "Hostname (blank = auto-generate)"    VPS_HOSTNAME        "${VPS_HOSTNAME}"
    [[ -z "$VPS_HOSTNAME" ]] && \
        ask "Hostname prefix"                  VPS_HOSTNAME_PREFIX "${VPS_HOSTNAME_PREFIX}"

    hdr "SSH keys (at least one source required)"
    ask  "sshid.io id (https://sshid.io/<id>)" SSH_ID      "${SSH_ID}"
    ask  "GitHub username (github.com/<u>.keys)" SSH_GH_USER "${SSH_GH_USER}"
    if [[ -z "$SSH_ID$SSH_GH_USER$SSH_AUTHORIZED_KEYS" ]]; then
        echo "$(c '1;33' 'WARNING: no SSH key source provided. You will be locked out after hardening.')"
        ask_yn "Continue anyway?" "n" || exit 1
    fi

    hdr "Homebrew & toolchain"
    ask_yn "Install Homebrew + CLI tools?" "y" && INSTALL_BREW=1 || INSTALL_BREW=0

    hdr "Tailscale"
    if ask_yn "Install Tailscale?" "y"; then
        INSTALL_TAILSCALE=1
        echo
        echo "  Generate an auth key in the Tailscale admin:"
        echo "    https://login.tailscale.com/admin/settings/keys"
        echo "  Recommended: ephemeral + tagged (e.g. tag:vps) + 1-hour expiry."
        echo "  Make sure every tag you choose exists in tagOwners in your tailscale.json."
        echo
        echo "  Paste EITHER:"
        echo "    (a) the auth key alone:    tskey-auth-XXXXXXXXXXXXXX"
        echo "    (b) the full install line: curl -fsSL ... | sh && sudo tailscale up --auth-key=tskey-auth-XXX"
        echo "  (the wizard will extract the key from (b) automatically)"
        echo
        ask_secret "Tailscale authkey (blank to install only)" TAILSCALE_AUTHKEY

        # Extract just the auth key if the user pasted the full one-liner.
        case "$TAILSCALE_AUTHKEY" in
            *"--auth-key="*) TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY##*--auth-key=}" ;;
            *"--authkey="*)  TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY##*--authkey=}" ;;
        esac
        # Strip anything after the first whitespace (trailing flags, &&, etc.)
        TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY%% *}"
        # Strip a trailing semicolon or quote, just in case.
        TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY%[;\"\']}"

        if [[ -n "$TAILSCALE_AUTHKEY" && "$TAILSCALE_AUTHKEY" != tskey-* ]]; then
            echo "  $(c '1;33' 'WARNING: that does not look like a Tailscale auth key (expected to start with tskey-).')"
            ask_yn "Continue anyway?" "n" || { echo "Aborted."; exit 1; }
        fi

        echo
        echo "  (Leave tags blank to use the tags baked into the auth key —"
        echo "   safer than overriding, since extra tags must be in tagOwners.)"
        ask "Override tags (comma-separated, blank = key default)" TAILSCALE_TAGS ""
    else
        INSTALL_TAILSCALE=0
    fi

    hdr "Hardening"
    ask_yn "Run hardening (UFW + fail2ban + SSH lockdown) after bootstrap?" "y" \
        && RUN_HARDEN=1 || RUN_HARDEN=0
    ask_yn "Open HTTP/HTTPS ports (80/443)?" "n" \
        && ALLOW_HTTP_HTTPS=1 || ALLOW_HTTP_HTTPS=0

    hdr "AI / agent tooling (optional)"
    echo "Installs opencode, crush, codex, claude-code, ollama, lazygit, glow,"
    echo "ranger, zoxide, btop, chafa, csvlens, tmuxai, tpm. Adds 5–10 minutes."
    ask_yn "Install AI/agent tooling after hardening?" "n" \
        && INSTALL_TOOLS=1 || INSTALL_TOOLS=0

    if (( INSTALL_TOOLS )); then
        hdr "tmuxai (AI in tmux) configuration"
        cat <<'EOF'
The config will include 3 named model presets per provider you enable
(best / fast / cheap). Switch at runtime with:  tmuxai --model <name>

  OpenRouter (recommended — most reliable with tmuxai)
    one key, access to all major models. Pay-as-you-go from $5 top-up.
      best:  anthropic/claude-opus-4.7
      fast:  anthropic/claude-haiku-4.5
      cheap: google/gemini-2.5-flash-lite
    https://openrouter.ai/keys

  OpenAI (direct — REQUIRES billing credits)
    Without credits you'll see 'insufficient_quota' errors. Top up first.
      best:  gpt-5.1
      fast:  gpt-4.1-mini
      cheap: gpt-4.1-nano
    https://platform.openai.com/api-keys
    https://platform.openai.com/account/billing

  Anthropic (direct — sometimes errors with "Missing Authentication header")
    tmuxai's direct-Anthropic provider is uneven across versions. If you
    hit auth errors, use the equivalent openrouter-* preset above instead
    (same Claude models, via OpenRouter, works reliably).
      best:  claude-opus-4-7  (1M context)
      fast:  claude-sonnet-4-6
      cheap: claude-haiku-4-5
    https://console.anthropic.com/settings/keys

A `local-ollama` entry is added automatically (uses your local ollama,
no API key required). Press Enter on any provider prompt to skip it.

EOF
        ask_secret "OpenRouter API key (blank to skip)" OPENROUTER_API_KEY
        ask_secret "OpenAI API key (blank to skip)"     OPENAI_API_KEY
        ask_secret "Anthropic API key (blank to skip)"  ANTHROPIC_API_KEY
    fi

    hdr "Review"
    cat <<EOF
  user        : $VPS_USER
  role        : $VPS_ROLE
  hostname    : ${VPS_HOSTNAME:-<auto>}
  ssh sources : ${SSH_ID:+sshid.io/$SSH_ID }${SSH_GH_USER:+github.com/$SSH_GH_USER}
  homebrew    : $([[ $INSTALL_BREW == 1 ]] && echo yes || echo no)
  tailscale   : $([[ $INSTALL_TAILSCALE == 1 ]] && echo "yes ($TAILSCALE_TAGS)" || echo no)
  authkey set : $([[ -n "$TAILSCALE_AUTHKEY" ]] && echo yes || echo no)
  harden      : $([[ $RUN_HARDEN == 1 ]] && echo yes || echo no)
  http/https  : $([[ $ALLOW_HTTP_HTTPS == 1 ]] && echo open || echo closed)
  ai tools    : $([[ $INSTALL_TOOLS == 1 ]] && echo yes || echo no)
EOF
    echo
    ask_yn "Proceed?" "y" || { echo "Aborted."; exit 1; }
fi

# ------------------------------------------------------------------------------
# Write /etc/vps/bootstrap.env
# ------------------------------------------------------------------------------
mkdir -p /etc/vps /usr/local/sbin
umask 077
cat > /etc/vps/bootstrap.env <<EOF
# Written by vps-init.sh on $(date -Is)
VPS_USER="${VPS_USER}"
VPS_HOSTNAME="${VPS_HOSTNAME}"
VPS_HOSTNAME_PREFIX="${VPS_HOSTNAME_PREFIX}"
VPS_ROLE="${VPS_ROLE}"

SSH_ID="${SSH_ID}"
SSH_GH_USER="${SSH_GH_USER}"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS}"

ENABLE_PASSWORDLESS_SUDO="${ENABLE_PASSWORDLESS_SUDO}"

INSTALL_BREW="${INSTALL_BREW}"
BREW_PACKAGES="${BREW_PACKAGES}"
INSTALL_NODE_LTS="${INSTALL_NODE_LTS}"
INSTALL_DOCKER="${INSTALL_DOCKER}"

SSH_PORT="${SSH_PORT}"
ALLOW_PASSWORD_AUTH="${ALLOW_PASSWORD_AUTH}"
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN}"
LIMIT_SSH_TO_ADMIN_USER="${LIMIT_SSH_TO_ADMIN_USER}"
HARDEN_SSH="${HARDEN_SSH}"

ENABLE_UFW="${ENABLE_UFW}"
PUBLIC_SSH_ALLOWED="${PUBLIC_SSH_ALLOWED}"
ALLOW_HTTP_HTTPS="${ALLOW_HTTP_HTTPS}"
EXTRA_UFW_PORTS="${EXTRA_UFW_PORTS}"
ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN}"
ENABLE_UNATTENDED="${ENABLE_UNATTENDED}"
ENABLE_SYSCTL_HARDENING="${ENABLE_SYSCTL_HARDENING}"

INSTALL_TAILSCALE="${INSTALL_TAILSCALE}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME}"
TAILSCALE_TAGS="${TAILSCALE_TAGS}"
TAILSCALE_SSH="${TAILSCALE_SSH}"
TAILSCALE_ACCEPT_DNS="${TAILSCALE_ACCEPT_DNS}"
TAILSCALE_ADVERTISE_ROUTES="${TAILSCALE_ADVERTISE_ROUTES}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE}"
TAILSCALE_EXTRA_ARGS="${TAILSCALE_EXTRA_ARGS}"
EOF
chmod 600 /etc/vps/bootstrap.env
umask 022

echo "Wrote /etc/vps/bootstrap.env (mode 600)"

# ------------------------------------------------------------------------------
# Write vps-bootstrap.sh  (quoted heredoc — no expansion at init time)
# ------------------------------------------------------------------------------
cat > /usr/local/sbin/vps-bootstrap.sh <<'BOOTSTRAP_EOF'
#!/usr/bin/env bash
# vps-bootstrap.sh — first-boot provisioning for Ubuntu 24.04
# Idempotent. Safe to re-run.
set -Eeuo pipefail
umask 022

LOG=/var/log/vps-bootstrap.log
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR
echo "===== vps-bootstrap @ $(date -Is) ====="

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
mkdir -p /etc/vps
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

export DEBIAN_FRONTEND=noninteractive

# ---------- helpers ----------
valid_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_hostname() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]; }

is_generic_hostname() {
  local h; h="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$h" in
    localhost|ubuntu|debian|server|vps|cloud|hetzner) return 0;;
    ubuntu-*|debian-*|hetzner-*|cx*|cpx*|ccx*|vps-*) return 0;;
  esac
  return 1
}

# Prefer Hetzner instance-id; fall back to machine-id then random.
make_auto_hostname() {
  local id source prefix="${VPS_HOSTNAME_PREFIX}"

  source="$(curl -fsS --connect-timeout 1 \
            http://169.254.169.254/hetzner/v1/metadata/instance-id 2>/dev/null || true)"
  [[ -z "$source" && -r /etc/machine-id ]] && source="$(cut -c1-8 /etc/machine-id)"
  [[ -z "$source" ]] && source="$(tr -dc a-z0-9 </dev/urandom | head -c6)"

  id="$(printf '%s' "$source" | tr '[:upper:]_' '[:lower:]-' \
        | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//' | cut -c1-16)"

  printf '%s-%s-%s' "$prefix" "${VPS_ROLE}" "$id" \
    | tr '[:upper:]_' '[:lower:]-' \
    | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//' | cut -c1-63
}

append_line_if_missing() {
  local file="$1" line="$2" owner="${3:-root}" group="${4:-root}"
  touch "$file"
  grep -qxF "$line" "$file" || printf '\n%s\n' "$line" >> "$file"
  chown "$owner:$group" "$file"
}

run_as_user() { sudo -Hiu "$VPS_USER" bash -lc "$*"; }

# ---------- 1. Base packages ----------
echo "--- Base packages ---"
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
    sudo curl wget git ca-certificates gnupg2 lsb-release \
    build-essential pkg-config lsof procps file \
    python3 python3-pip python3-venv \
    fd-find unzip zip jq bc htop tmux rsync \
    software-properties-common apt-transport-https

# fd-find quirk on Debian/Ubuntu
if [[ ! -e /usr/local/bin/fd ]] && command -v fdfind >/dev/null; then
    ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi

# ---------- 2. Hostname ----------
echo "--- Hostname ---"
current="$(hostnamectl --static 2>/dev/null || hostname)"
if [[ -z "$VPS_HOSTNAME" ]]; then
    if is_generic_hostname "$current"; then
        VPS_HOSTNAME="$(make_auto_hostname)"
    else
        VPS_HOSTNAME="$current"
    fi
fi
valid_hostname "$VPS_HOSTNAME" || { echo "Invalid hostname: $VPS_HOSTNAME"; exit 1; }

if [[ "$current" != "$VPS_HOSTNAME" ]]; then
    echo "Renaming $current -> $VPS_HOSTNAME"
    hostnamectl set-hostname "$VPS_HOSTNAME"
    if grep -qE '^127\.0\.1\.1' /etc/hosts; then
        sed -i -E "s/^(127\.0\.1\.1\s+).*/\1${VPS_HOSTNAME}/" /etc/hosts
    else
        echo "127.0.1.1   ${VPS_HOSTNAME}" >> /etc/hosts
    fi
    if grep -qE '^VPS_HOSTNAME=' "$ENV_FILE"; then
        sed -i -E "s|^VPS_HOSTNAME=.*|VPS_HOSTNAME=\"${VPS_HOSTNAME}\"|" "$ENV_FILE"
    else
        echo "VPS_HOSTNAME=\"${VPS_HOSTNAME}\"" >> "$ENV_FILE"
    fi
fi

# ---------- 3. Primary user ----------
echo "--- User: $VPS_USER ---"
valid_username "$VPS_USER" || { echo "Invalid username"; exit 1; }

# Refuse collision with system users; 'linuxbrew' is the obvious gotcha.
if [[ "$VPS_USER" == "linuxbrew" || "$VPS_USER" == "root" ]]; then
    echo "Refusing to use reserved username: $VPS_USER"; exit 1
fi
if id -u "$VPS_USER" &>/dev/null; then
    uid="$(id -u "$VPS_USER")"
    if (( uid < 1000 )); then
        echo "User $VPS_USER exists as system user (uid=$uid). Refusing."; exit 1
    fi
else
    useradd -m -s "$VPS_USER_SHELL" -d "/home/${VPS_USER}" "$VPS_USER"
fi
usermod -aG sudo "$VPS_USER"

if [[ "$ENABLE_PASSWORDLESS_SUDO" == "1" ]]; then
    echo "${VPS_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-${VPS_USER}"
    chmod 0440 "/etc/sudoers.d/90-${VPS_USER}"
    visudo -cf "/etc/sudoers.d/90-${VPS_USER}"
fi

# ---------- 4. SSH keys ----------
USER_HOME="/home/${VPS_USER}"
install -d -o "$VPS_USER" -g "$VPS_USER" -m 700 "${USER_HOME}/.ssh"
AUTH="${USER_HOME}/.ssh/authorized_keys"
touch "$AUTH"; chown "$VPS_USER:$VPS_USER" "$AUTH"; chmod 600 "$AUTH"

add_keys() {
    local src="$1" data="$2"
    [[ -z "$data" ]] && return 0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        grep -qxF "$line" "$AUTH" || { echo "$line" >> "$AUTH"; echo "  + key from $src"; }
    done <<< "$data"
}

[[ -n "$SSH_ID" ]]      && add_keys "sshid.io/$SSH_ID"    "$(curl -fsSL "https://sshid.io/${SSH_ID}" || true)"
[[ -n "$SSH_GH_USER" ]] && add_keys "github/$SSH_GH_USER" "$(curl -fsSL "https://github.com/${SSH_GH_USER}.keys" || true)"
[[ -n "$SSH_AUTHORIZED_KEYS" ]] && add_keys "env" "$SSH_AUTHORIZED_KEYS"

# Mirror keys to root as a transitional safety net so you cannot lock yourself
# out during the first-boot handover. The hardening script can later restrict
# root login. Append+dedupe to preserve any existing root keys across re-runs.
install -d -m 700 /root/.ssh
ROOT_AUTH=/root/.ssh/authorized_keys
touch "$ROOT_AUTH"
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    grep -qxF "$line" "$ROOT_AUTH" || echo "$line" >> "$ROOT_AUTH"
done < "$AUTH"
chmod 600 "$ROOT_AUTH"

# ---------- 4b. First-login password prompt ----------
# When root does `su $VPS_USER` (or the user logs in for the first time),
# the user lands in an interactive shell with no password set. This hook,
# sourced from ~/.bashrc, prompts them to set one. Self-disables after success.
echo "--- First-login password hook ---"
FIRSTLOGIN="${USER_HOME}/.firstlogin-passwd.sh"
cat > "$FIRSTLOGIN" <<'HOOK'
#!/usr/bin/env bash
# Prompt to set a password on first interactive login. Sourced from ~/.bashrc.
[ -t 0 ] || return 0
[ -f "$HOME/.password_set" ] && return 0

# Column 2 of `passwd -S`: L=locked, NP=no-password, P=valid.
state=$(sudo -n passwd -S "$USER" 2>/dev/null | awk '{print $2}')
case "$state" in
    L|NP)
        echo
        echo "Welcome, $USER. This account has no password yet."
        echo "Set one now (you'll be prompted twice):"
        if sudo passwd "$USER"; then
            touch "$HOME/.password_set"
            echo "Password set. This prompt will not appear again."
        else
            echo "Password setup failed. You will be prompted again next login."
        fi
        echo
        ;;
    P)
        touch "$HOME/.password_set"
        ;;
esac
HOOK
chown "$VPS_USER:$VPS_USER" "$FIRSTLOGIN"
chmod 700 "$FIRSTLOGIN"

# ---------- 5. Homebrew ----------
if [[ "$INSTALL_BREW" == "1" ]]; then
    echo "--- Homebrew ---"
    apt-get install -y build-essential procps curl file git

    # Pre-create the prefix with correct ownership to avoid the
    # "current working directory must be readable" error.
    if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        mkdir -p /home/linuxbrew/.linuxbrew
        chown -R "$VPS_USER:$VPS_USER" /home/linuxbrew

        sudo -Hiu "$VPS_USER" bash -lc '
          cd "$HOME"
          NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        '
    fi

    # System-wide shellenv covers SSH non-login shells, cron, systemd User=.
    # Critical: `cd "$HOME"` inside the eval's subshell. brew refuses to start
    # when CWD is unreadable to the running user — e.g. after `su <user>` from
    # /root, which is the most common way to reproduce the bug. The cd happens
    # in a subshell so the user's actual CWD is unchanged.
    cat > /etc/profile.d/homebrew.sh <<'EOF'
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(cd "$HOME" 2>/dev/null && /home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
fi
EOF
    chmod 0644 /etc/profile.d/homebrew.sh

    BREW_LINE='eval "$(cd "$HOME" 2>/dev/null && /home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"'
    for rc in "${USER_HOME}/.profile" "${USER_HOME}/.bashrc"; do
        # Migrate: scrub any earlier broken variants we may have written
        # (without the cd guard) so we don't accumulate duplicates.
        [[ -f "$rc" ]] && sed -i -E \
            '/^eval "\$\(\/home\/linuxbrew\/\.linuxbrew\/bin\/brew shellenv( bash)?\)"$/d' "$rc"
        append_line_if_missing "$rc" "$BREW_LINE" "$VPS_USER" "$VPS_USER"
    done

    # Every sudo-to-user block must `cd "$HOME"` first. sudo -Hu inherits the
    # parent's CWD (typically /root), which the new user cannot read — that's
    # the "current working directory must be readable" error from brew.
    run_as_user '
      cd "$HOME"
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
      brew analytics off || true
      brew update || true
    '

    if [[ "$INSTALL_BREW_PACKAGES" == "1" && -n "${BREW_PACKAGES// }" ]]; then
        echo "--- brew install $BREW_PACKAGES ---"
        sudo -Hiu "$VPS_USER" env BREW_PACKAGES="$BREW_PACKAGES" bash -lc '
          cd "$HOME"
          eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
          for pkg in $BREW_PACKAGES; do
            # Tap-prefixed forms (e.g. oven-sh/bun/bun) install via tap; the
            # local "already installed" check expects the leaf name only.
            case "$pkg" in
                */*/*) name="${pkg##*/}" ;;
                *)     name="$pkg" ;;
            esac
            if brew list --formula "$name" >/dev/null 2>&1; then
              printf "[STATUS] ok|brew %s|already installed\n" "$name"
            elif brew install "$pkg"; then
              printf "[STATUS] ok|brew %s|installed\n" "$name"
            else
              printf "[STATUS] warn|brew %s|install failed\n" "$name"
            fi
          done
        '
    fi
fi

# ---------- 6. Optional: Node via nvm (only if INSTALL_NODE_LTS=1) ----------
if [[ "$INSTALL_NODE_LTS" == "1" ]]; then
    echo "--- Node LTS via nvm ---"
    sudo -Hiu "$VPS_USER" env NVM_VERSION="$NVM_VERSION" bash -lc '
      cd "$HOME"
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] || curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
      . "$NVM_DIR/nvm.sh"
      nvm install --lts
      nvm alias default "lts/*"
      corepack enable || true
      node -v; npm -v
    '
fi

# ---------- 7. Optional: Docker ----------
if [[ "$INSTALL_DOCKER" == "1" ]]; then
    echo "--- Docker ---"
    apt-get install -y docker.io docker-compose-v2 || apt-get install -y docker.io
    systemctl enable --now docker
    usermod -aG docker "$VPS_USER"
fi

# ---------- 8. Shell niceties ----------
BASHRC="${USER_HOME}/.bashrc"
PROFILE="${USER_HOME}/.profile"

# Ensure ~/.local/bin is in PATH for user-local installers (Claude Code,
# pipx, npm-prefix tools, etc.). Idempotent: the inner `case` skips if the
# directory is already in PATH, so sourcing the rc twice doesn't duplicate.
LOCAL_BIN_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for rc in "$PROFILE" "$BASHRC"; do
    append_line_if_missing "$rc" "$LOCAL_BIN_LINE" "$VPS_USER" "$VPS_USER"
done

# ---------- Managed shell init (regenerated every run) ----------
# All volatile shell tweaks (aliases, tool init, hooks) live in ~/.vps-shell.sh,
# which is rewritten on every bootstrap run — old alias text is replaced, not
# left as dead lines next to new ones. The loader appended to .bashrc sources
# it on shell start AND re-sources it via PROMPT_COMMAND whenever its mtime
# changes, so existing shells auto-pick-up updates without `exec bash`.
SHELL_INIT="${USER_HOME}/.vps-shell.sh"
cat > "$SHELL_INIT" <<'INIT'
# Generated by vps-bootstrap. Do not edit — regenerated every run.

# One-shot init — guarded so re-sourcing doesn't double-fire prompts/hooks.
if [ -z "${VPS_SHELL_ONESHOT_DONE:-}" ]; then
    command -v starship >/dev/null && eval "$(starship init bash)"
    command -v zoxide   >/dev/null && eval "$(zoxide init bash)"
    export VPS_SHELL_ONESHOT_DONE=1
fi

# Idempotent — safe to re-source on every prompt.
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first'
    alias la='eza -la --group --header --group-directories-first'
fi
command -v bat >/dev/null && alias cat='bat --paging=never'

# First-login password hook
[ -f "$HOME/.firstlogin-passwd.sh" ] && . "$HOME/.firstlogin-passwd.sh"
INIT
chown "$VPS_USER:$VPS_USER" "$SHELL_INIT"
chmod 644 "$SHELL_INIT"

# Drop inline lines that older bootstrap versions appended directly. Idempotent.
sed -i \
    -e '\|^command -v starship >/dev/null && eval "\$(starship init bash)"$|d' \
    -e '\|^command -v zoxide >/dev/null && eval "\$(zoxide init bash)"$|d' \
    -e '\|^command -v eza >/dev/null && alias l[as]=".*"$|d' \
    -e '\|^command -v bat >/dev/null && alias cat="bat --paging=never"$|d' \
    -e '\|^\[ -f "\$HOME/\.firstlogin-passwd\.sh" \] && \. "\$HOME/\.firstlogin-passwd\.sh"$|d' \
    "$BASHRC"

# Install the loader block (idempotent — guarded by a sentinel comment).
if ! grep -qF '# >>> vps-shell-loader >>>' "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<'LOADER'

# >>> vps-shell-loader >>>
__vps_shell_resource() {
    [ -f "$HOME/.vps-shell.sh" ] || return
    local m
    m=$(stat -c %Y "$HOME/.vps-shell.sh" 2>/dev/null) || return
    [ "${__VPS_SHELL_MTIME:-0}" = "$m" ] && return
    . "$HOME/.vps-shell.sh"
    __VPS_SHELL_MTIME=$m
}
__vps_shell_resource
case ":${PROMPT_COMMAND:-}:" in
    *__vps_shell_resource*) ;;
    *) PROMPT_COMMAND="__vps_shell_resource; ${PROMPT_COMMAND:-}" ;;
esac
# <<< vps-shell-loader <<<
LOADER
fi
chown "$VPS_USER:$VPS_USER" "$BASHRC"

echo "===== bootstrap complete @ $(date -Is) ====="
echo "Next: /usr/local/sbin/vps-harden.sh"
BOOTSTRAP_EOF
chmod +x /usr/local/sbin/vps-bootstrap.sh
echo "Wrote /usr/local/sbin/vps-bootstrap.sh"

# ------------------------------------------------------------------------------
# Write vps-harden.sh
# ------------------------------------------------------------------------------
cat > /usr/local/sbin/vps-harden.sh <<'HARDEN_EOF'
#!/usr/bin/env bash
# vps-harden.sh — SSH, UFW, fail2ban, unattended-upgrades, sysctl, Tailscale
set -Eeuo pipefail
umask 022

LOG=/var/log/vps-bootstrap.log
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR
echo "===== vps-harden @ $(date -Is) ====="

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Defaults for every optional var. The env file written by vps-init.sh is
# intentionally minimal — older or hand-edited copies may be missing newer
# vars. With `set -u` on, any unset reference would abort the run; defaults
# make the script tolerant of partial env files.
: "${VPS_USER:?VPS_USER must be set in $ENV_FILE}"
: "${SSH_PORT:=22}"
: "${HARDEN_SSH:=1}"
: "${ALLOW_PASSWORD_AUTH:=no}"
: "${PERMIT_ROOT_LOGIN:=prohibit-password}"
: "${LIMIT_SSH_TO_ADMIN_USER:=1}"
: "${DISABLE_IPV6_SSH:=0}"
: "${ENABLE_UFW:=1}"
: "${PUBLIC_SSH_ALLOWED:=1}"
: "${ALLOW_HTTP_HTTPS:=0}"
: "${EXTRA_UFW_PORTS:=}"
: "${ENABLE_FAIL2BAN:=1}"
: "${ENABLE_UNATTENDED:=1}"
: "${UNATTENDED_AUTOREBOOT:=true}"
: "${UNATTENDED_AUTOREBOOT_TIME:=03:30}"
: "${ENABLE_SYSCTL_HARDENING:=1}"
: "${DISABLE_IPV6:=0}"
: "${INSTALL_TAILSCALE:=1}"
: "${TAILSCALE_AUTHKEY:=}"
: "${TAILSCALE_HOSTNAME:=}"
: "${TAILSCALE_TAGS:=}"
: "${TAILSCALE_SSH:=1}"
: "${TAILSCALE_ACCEPT_DNS:=false}"
: "${TAILSCALE_ADVERTISE_ROUTES:=}"
: "${TAILSCALE_EXIT_NODE:=0}"
: "${TAILSCALE_EXTRA_ARGS:=--accept-routes}"

# Normalize TAILSCALE_AUTHKEY: accept either the bare tskey-auth-... key OR
# the full install one-liner from the Tailscale admin web (which contains
# `--auth-key=tskey-auth-...`). Extract just the key portion.
case "$TAILSCALE_AUTHKEY" in
    *"--auth-key="*) TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY##*--auth-key=}" ;;
    *"--authkey="*)  TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY##*--authkey=}" ;;
esac
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY%% *}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY%[;\"\']}"

export DEBIAN_FRONTEND=noninteractive
bool() { [[ "$1" == "1" || "$1" == "true" || "$1" == "yes" ]]; }

# ---------- Safety gates ----------
if ! id -u "$VPS_USER" &>/dev/null; then
    echo "ERROR: user $VPS_USER missing — run vps-bootstrap.sh first"; exit 1
fi

USER_AUTH="/home/${VPS_USER}/.ssh/authorized_keys"
ROOT_AUTH="/root/.ssh/authorized_keys"

# Pre-flight: verify at least one viable SSH login path exists. The single
# biggest cause of accidental lockout is tightening sshd while no key is in
# the right place — verify both VPS_USER and root paths up front.
have_user_keys=0
have_root_keys=0
[[ -s "$USER_AUTH" ]] && have_user_keys=1
[[ -s "$ROOT_AUTH" ]] && have_root_keys=1

if [[ "$ALLOW_PASSWORD_AUTH" == "no" ]]; then
    if (( !have_user_keys && !have_root_keys )); then
        echo "ERROR: refusing to disable password auth — neither $USER_AUTH"
        echo "       nor $ROOT_AUTH has any keys. You would lock yourself out."
        echo "       Re-run vps-bootstrap.sh with SSH_ID/SSH_GH_USER/SSH_AUTHORIZED_KEYS set."
        exit 1
    fi
    if (( !have_user_keys )); then
        echo "WARN: $VPS_USER has no authorized_keys — only root SSH (key-only) will work."
    fi
    if (( !have_root_keys )) && [[ "$PERMIT_ROOT_LOGIN" != "no" ]]; then
        echo "WARN: PermitRootLogin=$PERMIT_ROOT_LOGIN but $ROOT_AUTH is empty;"
        echo "      root SSH login will not work even though sshd_config permits it."
    fi
fi

# If running inside an SSH session, warn loudly when the new AllowUsers list
# would exclude the current user. Don't abort — operator may have a reason —
# but make sure they see it before any reload happens.
if [[ -n "${SSH_CONNECTION:-}" ]] && bool "$LIMIT_SSH_TO_ADMIN_USER"; then
    current_ssh_user="${SUDO_USER:-$(whoami)}"
    allowed="${VPS_USER}"
    [[ "$PERMIT_ROOT_LOGIN" != "no" ]] && allowed="${allowed} root"
    case " $allowed " in
        *" $current_ssh_user "*) :;;
        *)  echo "WARN: current SSH session is as '$current_ssh_user' but the new"
            echo "      AllowUsers list will be: $allowed"
            echo "      Open a NEW shell as '$VPS_USER' (or root) BEFORE closing this one."
            ;;
    esac
fi
[[ -n "${SSH_CONNECTION:-}" ]] && \
    echo "NOTE: 'systemctl reload ssh' (SIGHUP) preserves existing sessions; new connections use the new config."

# ---------- 1. Packages ----------
apt-get update -y
apt-get install -y openssh-server ufw fail2ban unattended-upgrades \
                   apt-listchanges curl ca-certificates gnupg lsb-release

# ---------- 2. SSH hardening ----------
if bool "$HARDEN_SSH"; then
    echo "--- SSH hardening ---"
    mkdir -p /etc/ssh/sshd_config.d
    DROPIN=/etc/ssh/sshd_config.d/99-vps-hardening.conf

    # Snapshot existing drop-in so we can roll back if validation fails — a
    # broken drop-in left in place would prevent sshd from starting on next boot.
    [[ -f "$DROPIN" ]] && cp -p "$DROPIN" "${DROPIN}.bak"

    {
      echo "Port ${SSH_PORT}"
      echo "PermitRootLogin ${PERMIT_ROOT_LOGIN}"
      echo "PasswordAuthentication ${ALLOW_PASSWORD_AUTH}"
      echo "KbdInteractiveAuthentication no"
      echo "ChallengeResponseAuthentication no"
      echo "PubkeyAuthentication yes"
      echo "PermitEmptyPasswords no"
      echo "UsePAM yes"
      echo "X11Forwarding no"
      echo "AllowAgentForwarding yes"
      echo "AllowTcpForwarding yes"
      echo "ClientAliveInterval 60"
      echo "ClientAliveCountMax 3"
      echo "MaxAuthTries 4"
      echo "LoginGraceTime 20"
      echo "Protocol 2"
      bool "$DISABLE_IPV6_SSH" && echo "AddressFamily inet"
      if bool "$LIMIT_SSH_TO_ADMIN_USER"; then
          extra=""
          [[ "$PERMIT_ROOT_LOGIN" != "no" ]] && extra=" root"
          echo "AllowUsers ${VPS_USER}${extra}"
      fi
    } > "$DROPIN"
    chmod 644 "$DROPIN"

    # Ubuntu 24.04 ships ssh.socket socket-activated. Drop-in changes don't
    # always apply on first restart unless we disable AND mask the socket and
    # use the classic ssh.service. Masking prevents apt operations / package
    # hooks from re-enabling it later.
    systemctl disable --now ssh.socket 2>/dev/null || true
    systemctl mask ssh.socket 2>/dev/null || true

    # /run/sshd must exist for sshd -t / sshd -T (privilege-separation dir).
    # /run is a tmpfs; the directory is normally materialised by ssh.service's
    # RuntimeDirectory=sshd at start time, but `sshd -t` runs before that so
    # we have to create it ourselves.
    mkdir -p /run/sshd
    chmod 0755 /run/sshd

    # Validate. Roll back to previous drop-in (or remove ours) on failure
    # rather than leaving a broken sshd config in place.
    if ! sshd -t; then
        echo "ERROR: sshd -t rejected the new drop-in; rolling back"
        if [[ -f "${DROPIN}.bak" ]]; then
            mv "${DROPIN}.bak" "$DROPIN"
        else
            rm -f "$DROPIN"
        fi
        exit 1
    fi
    rm -f "${DROPIN}.bak"

    systemctl enable ssh.service 2>/dev/null || true

    # Override KillMode for ssh.service. Ubuntu's default is KillMode=process,
    # which leaves orphan listener processes alive when start fails — they sit
    # in the unit's cgroup blocking the port. Switching to KillMode=mixed
    # makes `systemctl stop` clean the cgroup properly. Trade-off: openssh
    # package upgrades that issue restart will now disconnect existing SSH
    # sessions. Mitigated because (a) our harden flow uses reload (SIGHUP) for
    # config changes, and (b) failed-start recovery is way more important than
    # session preservation across rare openssh upgrades.
    mkdir -p /etc/systemd/system/ssh.service.d
    cat > /etc/systemd/system/ssh.service.d/00-vps-killmode.conf <<'EOF'
# Written by vps-harden.sh — make systemctl stop fully clean the cgroup so
# failed starts don't leak the listener and block the next start.
[Service]
KillMode=mixed
TimeoutStopSec=15
EOF
    systemctl daemon-reload 2>/dev/null || true

    # Orphan/failed-state cleanup via systemd-native commands. NEVER use raw
    # kill against systemd-managed processes — on prior versions of this
    # script a `kill -KILL` against a tracked sshd PID has triggered a PID-1
    # systemd ABRT and frozen the whole box. systemctl stop with the
    # KillMode=mixed override above will properly tear the cgroup down.
    unit_state="$(systemctl show -p ActiveState --value ssh.service 2>/dev/null || echo unknown)"
    if [[ "$unit_state" == "failed" ]] || \
       (! systemctl is-active --quiet ssh.service && \
        ss -tlnp 2>/dev/null | grep -qE ":${SSH_PORT}[[:space:]]"); then
        echo "ssh.service is in '$unit_state' state with port held; clearing via systemd"
        systemctl reset-failed ssh.service 2>/dev/null || true
        systemctl stop ssh.service 2>/dev/null || true
        sleep 2
    fi

    # If port is STILL held after systemd cleanup, refuse to proceed and tell
    # the operator how to recover manually. Don't try aggressive raw kills.
    if ! systemctl is-active --quiet ssh.service && \
       ss -tlnp 2>/dev/null | grep -qE ":${SSH_PORT}[[:space:]]"; then
        echo
        echo "ERROR: port ${SSH_PORT} is still held after systemctl stop ssh.service."
        echo "An orphan sshd listener is bound to the port outside systemd's"
        echo "tracking. Refusing to proceed — manual intervention required."
        echo
        echo "Recovery (run from a console session, NOT this script):"
        echo "  pkill -KILL -f 'sshd: /usr/sbin/sshd -D \\[listener\\]'"
        echo "  systemctl reset-failed ssh.service"
        echo "  systemctl start ssh.service"
        echo "Or, if the VPS is in a strange state: power-cycle via cloud panel,"
        echo "then re-run this script."
        exit 1
    fi

    # State machine to apply config without locking the operator out:
    #   - ssh.service already active  → reload (SIGHUP, preserves sessions)
    #   - ssh.service not active yet  → start (first transition off ssh.socket)
    if systemctl is-active --quiet ssh.service; then
        if ! systemctl reload ssh.service; then
            echo "WARN: 'systemctl reload ssh' failed; falling back to restart"
            systemctl restart ssh.service
        fi
    else
        if ! systemctl start ssh.service; then
            echo
            echo "ERROR: ssh.service failed to start. Diagnostics:"
            echo "--- systemctl status ---"
            systemctl status ssh.service --no-pager 2>&1 | head -25 || true
            echo "--- recent journal ---"
            journalctl -u ssh.service --no-pager -n 25 2>/dev/null || true
            echo "--- port ${SSH_PORT} listeners ---"
            ss -tlnp 2>/dev/null | grep -E ":${SSH_PORT}\b" || echo "(none listening)"
            echo
            echo "Common fixes:"
            echo "  1) ssh.socket still holding the port:"
            echo "       systemctl stop ssh.socket; systemctl mask ssh.socket"
            echo "       systemctl restart ssh.service"
            echo "  2) Missing host keys:"
            echo "       ssh-keygen -A; systemctl restart ssh.service"
            echo "  3) Config error not caught by sshd -t:"
            echo "       /usr/sbin/sshd -ddd -p ${SSH_PORT}   (foreground, verbose)"
            exit 1
        fi
    fi
fi

# ---------- 3. UFW ----------
if bool "$ENABLE_UFW"; then
    echo "--- UFW ---"

    # Lockout safety: refuse to enable UFW with no public-SSH rule unless
    # Tailscale is verifiably up. The interface-wide tailscale0 allow added
    # below depends on the interface existing — without it we'd brick SSH.
    if ! bool "$PUBLIC_SSH_ALLOWED"; then
        if ! command -v tailscale >/dev/null || ! tailscale status >/dev/null 2>&1; then
            echo "ERROR: PUBLIC_SSH_ALLOWED=0 but Tailscale is not connected."
            echo "       Refusing to enable UFW (you would be locked out)."
            echo "       Run with PUBLIC_SSH_ALLOWED=1 first, verify the tailnet,"
            echo "       then re-run with PUBLIC_SSH_ALLOWED=0 to lock down."
            exit 1
        fi
    fi

    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing

    if bool "$PUBLIC_SSH_ALLOWED"; then
        ufw allow "${SSH_PORT}/tcp" comment 'public ssh'
    fi

    # Tailscale direct UDP (helps NAT traversal even if not strictly required)
    ufw allow 41641/udp comment 'tailscale direct'
    ufw allow in on tailscale0 comment 'tailscale interface'

    if bool "$ALLOW_HTTP_HTTPS"; then
        ufw allow 80/tcp  comment 'http'
        ufw allow 443/tcp comment 'https'
    fi
    for p in $EXTRA_UFW_PORTS; do ufw allow "$p"; done

    ufw --force enable
fi

# ---------- 4. fail2ban ----------
if bool "$ENABLE_FAIL2BAN"; then
    echo "--- fail2ban ---"
    cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port    = ${SSH_PORT}
backend = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
    systemctl enable --now fail2ban
    systemctl restart fail2ban
fi

# ---------- 5. Unattended upgrades ----------
if bool "$ENABLE_UNATTENDED"; then
    echo "--- unattended-upgrades ---"
    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    cat >/etc/apt/apt.conf.d/52unattended-upgrades-local <<EOF
Unattended-Upgrade::Automatic-Reboot "${UNATTENDED_AUTOREBOOT}";
Unattended-Upgrade::Automatic-Reboot-Time "${UNATTENDED_AUTOREBOOT_TIME}";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    systemctl enable --now unattended-upgrades || true
fi

# ---------- 6. Sysctl hardening ----------
if bool "$ENABLE_SYSCTL_HARDENING"; then
    cat >/etc/sysctl.d/99-vps-hardening.conf <<'EOF'
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.yama.ptrace_scope=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2
EOF

    if [[ -n "$TAILSCALE_ADVERTISE_ROUTES" ]] || bool "$TAILSCALE_EXIT_NODE"; then
        cat >/etc/sysctl.d/99-tailscale-routing.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
    fi

    if bool "$DISABLE_IPV6"; then
        cat >/etc/sysctl.d/98-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
    fi

    sysctl --system >/dev/null
fi

# ---------- 7. Tailscale ----------
if bool "$INSTALL_TAILSCALE"; then
    echo "--- Tailscale ---"

    if ! command -v tailscale >/dev/null; then
        echo "Installing tailscale..."
        if curl -fsSL https://tailscale.com/install.sh | sh; then
            printf '[STATUS] ok|tailscale install|installed via tailscale.com/install.sh\n'
        else
            printf '[STATUS] fail|tailscale install|installer failed (network/dns?)\n'
        fi
    else
        printf '[STATUS] ok|tailscale install|already present\n'
    fi

    if command -v tailscale >/dev/null; then
        systemctl enable --now tailscaled

        # Wait up to 5s for tailscaled to be ready before issuing `tailscale up`.
        for _ in 1 2 3 4 5; do
            tailscale status >/dev/null 2>&1 && break
            sleep 1
        done

        if [[ -n "$TAILSCALE_AUTHKEY" ]]; then
            TS_HOST="${TAILSCALE_HOSTNAME:-${VPS_HOSTNAME:-$(hostname)}}"
            args=( up
                   --auth-key="$TAILSCALE_AUTHKEY"
                   --hostname="$TS_HOST"
                   --accept-dns="$TAILSCALE_ACCEPT_DNS"
                   --operator="$VPS_USER" )
            # Only pass --advertise-tags when the operator has explicitly set
            # tags. Auth keys carry their own tag list (chosen at generation);
            # passing extra tags requires every tag to be in tagOwners AND
            # within the key's allowed set, or the request is rejected.
            [[ -n "$TAILSCALE_TAGS" ]] && args+=( --advertise-tags="$TAILSCALE_TAGS" )
            bool "$TAILSCALE_SSH"     && args+=( --ssh )
            bool "$TAILSCALE_EXIT_NODE" && args+=( --advertise-exit-node )
            [[ -n "$TAILSCALE_ADVERTISE_ROUTES" ]] && args+=( --advertise-routes="$TAILSCALE_ADVERTISE_ROUTES" )
            [[ -n "$TAILSCALE_EXTRA_ARGS" ]] && args+=( $TAILSCALE_EXTRA_ARGS )

            # Sanity-check the parsed key length so a parse error is obvious.
            # Tailscale auth keys are typically 60-65 chars and have exactly 3
            # dashes (tskey-<role>-<keyId>-<token>). Differences here suggest
            # truncation; matching values mean parsing is OK and a Tailscale
            # rejection is a key-state problem (used / expired / revoked).
            key_len="${#TAILSCALE_AUTHKEY}"
            key_dashes="$(awk -F'-' '{print NF-1}' <<< "$TAILSCALE_AUTHKEY")"
            echo "Auth key parsed: length=$key_len, dashes=$key_dashes (expect ~60+ and 3)"
            echo "Running: tailscale up --auth-key=<redacted> --hostname=$TS_HOST [...]"
            ts_out="$(tailscale "${args[@]}" 2>&1)" && ts_rc=0 || ts_rc=$?
            [[ -n "$ts_out" ]] && echo "$ts_out"

            if (( ts_rc == 0 )); then
                # Scrub the auth key from disk so VPS snapshots/images don't leak it.
                sed -i -E 's|^TAILSCALE_AUTHKEY=.*|TAILSCALE_AUTHKEY=""|' "$ENV_FILE"
                printf '[STATUS] ok|tailscale up|joined as %s\n' "$TS_HOST"

                # Show the operator their tailnet IPs so they can ssh-via-tailnet
                # immediately, without scrolling through verbose status output.
                ts_v4=$(tailscale ip -4 2>/dev/null | head -1)
                ts_v6=$(tailscale ip -6 2>/dev/null | head -1)
                ts_dns=$(tailscale status --self --json 2>/dev/null \
                    | grep -oP '"DNSName":\s*"\K[^"]+' | head -1)
                echo
                echo "✓ Joined tailnet:"
                [[ -n "$ts_dns" ]] && echo "    DNS:    $ts_dns"
                [[ -n "$ts_v4" ]]  && echo "    IPv4:   $ts_v4"
                [[ -n "$ts_v6" ]]  && echo "    IPv6:   $ts_v6"
                echo "    SSH:    ssh ${VPS_USER}@${ts_dns:-${ts_v4:-<host>}}"
            else
                printf '[STATUS] fail|tailscale up|exit %d\n' "$ts_rc"
                echo
                echo "ERROR: 'tailscale up' failed (exit $ts_rc). Common causes:"
                echo "  - the auth key is expired, already used, or marked single-use"
                echo "  - a tag in --advertise-tags is not in tagOwners (check tailscale.json)"
                echo "  - the auth key was generated with a different tag set than requested"
                echo "  - controlplane unreachable (firewall blocking *.tailscale.com:443)"
                echo "  - existing tailscale state conflicts; try: sudo tailscale logout && re-run"
                echo
                echo "  Generate a fresh key at: https://login.tailscale.com/admin/settings/keys"
                echo "  Edit /etc/vps/bootstrap.env to set TAILSCALE_AUTHKEY=<new-key>, then:"
                echo "    sudo /usr/local/sbin/vps-harden.sh"
            fi
        else
            printf '[STATUS] warn|tailscale up|no TAILSCALE_AUTHKEY; tailscaled installed but not joined\n'
            echo
            echo "tailscaled is installed but not joined to a tailnet."
            echo "To join, generate an auth key at:"
            echo "    https://login.tailscale.com/admin/settings/keys"
            echo "Then run ONE of:"
            echo "    sudo tailscale up --auth-key=<key>"
            echo "    sudo sed -i 's|^TAILSCALE_AUTHKEY=.*|TAILSCALE_AUTHKEY=\"<key>\"|' /etc/vps/bootstrap.env"
            echo "    sudo /usr/local/sbin/vps-harden.sh"
        fi
    else
        echo "WARN: tailscale binary missing after install attempt; skipping tailscale up"
    fi
fi

# ---------- 8. Lock down public SSH after Tailscale is up (optional 2nd run) ----------
if bool "$ENABLE_UFW" && ! bool "$PUBLIC_SSH_ALLOWED"; then
    if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
        echo "Tailscale connected -> restricting SSH to tailscale0"
        ufw allow in on tailscale0 to any port "$SSH_PORT" proto tcp comment 'ssh via tailscale'

        # Verify the tailnet SSH path is actually visible in UFW before
        # tearing the public rule down.
        if ufw status | grep -qE "tailscale0.*ALLOW"; then
            ufw delete allow "${SSH_PORT}/tcp" || true
            echo "OK: tailnet SSH rule verified; public ${SSH_PORT}/tcp removed"
        else
            echo "WARN: tailnet SSH rule not visible in 'ufw status'; leaving public rule in place"
        fi
    else
        echo "WARN: Tailscale not connected; leaving public SSH rule untouched"
    fi
fi

# ---------- 9. SSH access summary ----------
echo
echo "--- SSH access summary ---"
if command -v ufw >/dev/null && ufw status >/dev/null 2>&1; then
    ufw status verbose | grep -iE "(^Status:|${SSH_PORT}|tailscale)" || true
fi
echo "PermitRootLogin = ${PERMIT_ROOT_LOGIN}"
if [[ "$PERMIT_ROOT_LOGIN" != "no" ]]; then
    echo "  -> root SSH allowed (key-only); root keys mirrored from ${VPS_USER} as recovery hatch"
fi
if bool "$LIMIT_SSH_TO_ADMIN_USER"; then
    extra=""; [[ "$PERMIT_ROOT_LOGIN" != "no" ]] && extra=" root"
    echo "AllowUsers      = ${VPS_USER}${extra}"
fi

echo "===== harden complete @ $(date -Is) ====="
HARDEN_EOF
chmod +x /usr/local/sbin/vps-harden.sh
echo "Wrote /usr/local/sbin/vps-harden.sh"

# ------------------------------------------------------------------------------
# Write vps-tools.sh  (AI / agent tooling — opt-in via INSTALL_TOOLS=1)
# ------------------------------------------------------------------------------
cat > /usr/local/sbin/vps-tools.sh <<'TOOLS_EOF'
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
TOOLS_EOF
chmod +x /usr/local/sbin/vps-tools.sh
echo "Wrote /usr/local/sbin/vps-tools.sh"

# ------------------------------------------------------------------------------
# Run
# ------------------------------------------------------------------------------
echo
echo "$(c '1;32' '▶ Running vps-bootstrap.sh')"
/usr/local/sbin/vps-bootstrap.sh

if [[ "${RUN_HARDEN}" == "1" ]]; then
    echo
    echo "$(c '1;32' '▶ Running vps-harden.sh')"
    /usr/local/sbin/vps-harden.sh
fi

if [[ "${INSTALL_TOOLS}" == "1" ]]; then
    echo
    echo "$(c '1;32' '▶ Running vps-tools.sh')"
    # Propagate provider keys to the tools script; cleared after run.
    export OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
    /usr/local/sbin/vps-tools.sh
    unset OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
fi

echo
echo "$(c '1;32' '═══════════════════════════════════════════════════')"
echo "$(c '1;32' '  Done.')"
echo "$(c '1;32' '═══════════════════════════════════════════════════')"

# ---------- Install report ----------
# Parse [STATUS] lines emitted by bootstrap/harden/tools and print a
# consolidated tally + the warnings/failures up front so the operator
# isn't expected to scroll back through 1000+ lines of brew output.
LOG=/var/log/vps-bootstrap.log
if [[ -r "$LOG" ]]; then
    ok_n=$(grep -c '^\[STATUS\] ok|'   "$LOG" 2>/dev/null || true); ok_n=${ok_n:-0}
    warn_n=$(grep -c '^\[STATUS\] warn|' "$LOG" 2>/dev/null || true); warn_n=${warn_n:-0}
    fail_n=$(grep -c '^\[STATUS\] fail|' "$LOG" 2>/dev/null || true); fail_n=${fail_n:-0}

    echo
    echo "$(c '1;36' '── Install report ──')"
    echo "  $(c '0;32' "✓ ok:")   $ok_n"
    echo "  $(c '0;33' "! warn:") $warn_n"
    echo "  $(c '0;31' "✗ fail:") $fail_n"

    if (( warn_n > 0 )); then
        echo
        echo "$(c '1;33' 'Warnings:')"
        grep '^\[STATUS\] warn|' "$LOG" | awk -F'|' '{
            if ($3 != "") printf "  ! %-32s (%s)\n", $2, $3
            else          printf "  ! %s\n", $2
        }'
    fi
    if (( fail_n > 0 )); then
        echo
        echo "$(c '1;31' 'Failures:')"
        grep '^\[STATUS\] fail|' "$LOG" | awk -F'|' '{
            if ($3 != "") printf "  ✗ %-32s (%s)\n", $2, $3
            else          printf "  ✗ %s\n", $2
        }'
    fi

    if (( warn_n > 0 || fail_n > 0 )); then
        echo
        echo "$(c '2' "How to retry individual items:")"
        echo "  brew package          → sudo -u $VPS_USER bash -lc 'brew install <pkg>'"
        echo "  npm package           → sudo -u $VPS_USER bash -lc 'npm i -g <pkg>'"
        echo "  claude-code           → sudo -u $VPS_USER bash -lc 'curl -fsSL https://claude.ai/install.sh | bash'"
        echo "  tailscale             → sudo tailscale up --auth-key=<new-key>"
        echo "  full log              → less /var/log/vps-bootstrap.log"
    fi
fi

echo
echo "Hostname : $(hostnamectl --static)"
echo "User     : ${VPS_USER}"
echo "Log      : /var/log/vps-bootstrap.log"
echo
echo "Try:      ssh ${VPS_USER}@$(hostname -I | awk '{print $1}')"
if [[ "${INSTALL_TAILSCALE}" == "1" ]]; then
    echo "Tailnet:  ssh ${VPS_USER}@$(tailscale status --self --json 2>/dev/null | grep -oP '"DNSName":\s*"\K[^"]+' | head -1 || echo '<hostname>')"
fi
echo
if [[ "${INSTALL_TOOLS}" == "1" ]]; then
    echo
    echo "AI tools installed under user '${VPS_USER}'."
    echo "  For full per-user state:  sudo -iu ${VPS_USER}   (then run claude / opencode / etc.)"
    echo "  'claude' is also symlinked to /usr/local/bin/claude so root can run it too."
    echo
fi
echo "Re-run later:"
echo "  sudo /usr/local/sbin/vps-bootstrap.sh   # re-apply user/keys/brew"
echo "  sudo /usr/local/sbin/vps-harden.sh      # re-apply firewall/ssh/tailscale"
echo "  sudo /usr/local/sbin/vps-tools.sh       # install/refresh AI/agent tooling"
echo
if [[ "${PUBLIC_SSH_ALLOWED}" == "1" && "${INSTALL_TAILSCALE}" == "1" ]]; then
    echo "$(c '1;33' 'To lock SSH to Tailscale-only after verifying tailnet access:')"
    echo "  sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED=\"0\"/' /etc/vps/bootstrap.env"
    echo "  sudo /usr/local/sbin/vps-harden.sh"
fi

# ---------- Optional verification ----------
# Offer to run VerifyChecklist.sh now. Interactive runs ask; non-interactive
# can opt in via RUN_VERIFY=1 (or skip via RUN_VERIFY=0, the default).
: "${RUN_VERIFY:=}"
verify_url='https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh'
run_verify=0
if (( INTERACTIVE )); then
    echo
    if ask_yn "Run VerifyChecklist.sh now to audit the install?" "y"; then
        run_verify=1
    fi
elif [[ "$RUN_VERIFY" == "1" ]]; then
    run_verify=1
fi

if (( run_verify )); then
    echo
    echo "$(c '1;36' '── VerifyChecklist ──')"
    if curl -fsSL "$verify_url" -o /tmp/VerifyChecklist.sh 2>/dev/null && [[ -s /tmp/VerifyChecklist.sh ]]; then
        bash /tmp/VerifyChecklist.sh || true
        rm -f /tmp/VerifyChecklist.sh
    else
        echo "$(c '0;33' "WARN: could not fetch $verify_url — run it manually:")"
        echo "  sudo bash <(curl -fsSL $verify_url)"
    fi
else
    echo
    echo "Run anytime: sudo bash <(curl -fsSL $verify_url)"
fi
