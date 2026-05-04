#!/usr/bin/env bash
# vps-init.sh — one-shot, self-contained Ubuntu 24.04 VPS provisioner.
# Works on any provider (Hetzner, DigitalOcean, Vultr, Linode, Contabo,
# OVH, RackNerd, Scaleway, etc.) with or without cloud-init.
#
# Usage:
#   scp vps-init.sh root@HOST:/root/
#   ssh root@HOST 'bash /root/vps-init.sh'
#
#   # or piped:
#   ssh root@HOST 'bash -s' < vps-init.sh
#
#   # or non-interactive (for agents / automation):
#   VPS_USER=pink SSH_ID=mahakoala TAILSCALE_AUTHKEY=tskey-... \
#     NONINTERACTIVE=1 bash vps-init.sh
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
: "${BREW_PACKAGES:=starship eza tldr zoxide btop fd ripgw bat git-delta lazygit glow ranger jq yq fzf gh node bun pnpm yarn go}"
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
: "${TAILSCALE_TAGS:=tag:vps}"
: "${TAILSCALE_SSH:=1}"
: "${TAILSCALE_ACCEPT_DNS:=false}"
: "${TAILSCALE_ADVERTISE_ROUTES:=}"
: "${TAILSCALE_EXIT_NODE:=0}"
: "${TAILSCALE_EXTRA_ARGS:=--accept-routes}"

: "${NONINTERACTIVE:=}"
: "${RUN_HARDEN:=1}"

# Interactive if: we have a TTY AND user hasn't forced non-interactive
if [[ -z "$NONINTERACTIVE" && -t 0 && -t 1 ]]; then
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
        ask_secret "Tailscale authkey (blank to install only)" TAILSCALE_AUTHKEY
        ask "Tailscale tags (comma-separated)" TAILSCALE_TAGS "tag:vps,tag:${VPS_ROLE}"
    else
        INSTALL_TAILSCALE=0
    fi

    hdr "Hardening"
    ask_yn "Run hardening (UFW + fail2ban + SSH lockdown) after bootstrap?" "y" \
        && RUN_HARDEN=1 || RUN_HARDEN=0
    ask_yn "Open HTTP/HTTPS ports (80/443)?" "n" \
        && ALLOW_HTTP_HTTPS=1 || ALLOW_HTTP_HTTPS=0

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
set -Eeuo pipefail
umask 022
LOG=/var/log/vps-bootstrap.log
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[ERROR] line $LINENO: $BASH_COMMAND" >&2' ERR
echo "===== vps-bootstrap @ $(date -Is) ====="

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }
ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
# shellcheck disable=SC1090
source "$ENV_FILE"
export DEBIAN_FRONTEND=noninteractive

valid_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_hostname() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]; }
is_generic_hostname() {
  local h; h="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$h" in
    localhost|ubuntu|debian|server|vps|cloud|hetzner) return 0;;
    ubuntu-*|debian-*|hetzner-*|vps-*|cx*|cpx*|ccx*|srv*) return 0;;
  esac
  return 1
}
make_auto_hostname() {
  local src prefix="${VPS_HOSTNAME_PREFIX}"
  src="$(curl -fsS --connect-timeout 1 http://169.254.169.254/hetzner/v1/metadata/instance-id 2>/dev/null || true)"
  [[ -z "$src" && -r /etc/machine-id ]] && src="$(cut -c1-8 /etc/machine-id)"
  [[ -z "$src" ]] && src="$(tr -dc a-z0-9 </dev/urandom | head -c6)"
  printf '%s-%s-%s' "$prefix" "${VPS_ROLE:-vps}" "$src" \
    | tr '[:upper:]_' '[:lower:]-' \
    | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//' | cut -c1-63
}
append_missing() {
  local f="$1" l="$2" o="${3:-root}" g="${4:-root}"
  touch "$f"; grep -qxF "$l" "$f" || printf '\n%s\n' "$l" >> "$f"
  chown "$o:$g" "$f"
}

# 1. Base packages
echo "--- apt update + base packages ---"
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  sudo curl wget git ca-certificates gnupg2 lsb-release \
  build-essential pkg-config lsof procps file \
  python3 python3-pip python3-venv \
  fd-find unzip zip jq htop tmux rsync \
  software-properties-common apt-transport-https
[[ -e /usr/local/bin/fd ]] || ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# 2. Hostname
echo "--- hostname ---"
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
    echo "$current -> $VPS_HOSTNAME"
    hostnamectl set-hostname "$VPS_HOSTNAME"
    if grep -qE '^127\.0\.1\.1' /etc/hosts; then
        sed -i -E "s/^(127\.0\.1\.1\s+).*/\1${VPS_HOSTNAME}/" /etc/hosts
    else
        echo "127.0.1.1   ${VPS_HOSTNAME}" >> /etc/hosts
    fi
    if grep -qE '^VPS_HOSTNAME=' "$ENV_FILE"; then
        sed -i -E "s|^VPS_HOSTNAME=.*|VPS_HOSTNAME=\"${VPS_HOSTNAME}\"|" "$ENV_FILE"
    fi
fi

# 3. User
echo "--- user: $VPS_USER ---"
valid_username "$VPS_USER" || { echo "Invalid username"; exit 1; }
[[ "$VPS_USER" == "root" || "$VPS_USER" == "linuxbrew" ]] && { echo "Reserved username"; exit 1; }
if id -u "$VPS_USER" &>/dev/null; then
    uid="$(id -u "$VPS_USER")"
    (( uid >= 1000 )) || { echo "Refusing system user $VPS_USER (uid $uid)"; exit 1; }
else
    useradd -m -s /bin/bash -d "/home/${VPS_USER}" "$VPS_USER"
fi
usermod -aG sudo "$VPS_USER"
if [[ "${ENABLE_PASSWORDLESS_SUDO:-1}" == "1" ]]; then
    echo "${VPS_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-${VPS_USER}"
    chmod 0440 "/etc/sudoers.d/90-${VPS_USER}"
    visudo -cf "/etc/sudoers.d/90-${VPS_USER}"
fi

# 4. SSH keys
USER_HOME="/home/${VPS_USER}"
install -d -o "$VPS_USER" -g "$VPS_USER" -m 700 "${USER_HOME}/.ssh"
AUTH="${USER_HOME}/.ssh/authorized_keys"
touch "$AUTH"; chown "$VPS_USER:$VPS_USER" "$AUTH"; chmod 600 "$AUTH"
add_keys() {
    local src="$1" data="$2"
    [[ -z "$data" ]] && return 0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        grep -qxF "$line" "$AUTH" || { echo "$line" >> "$AUTH"; echo "  + $src"; }
    done <<< "$data"
}
[[ -n "${SSH_ID:-}" ]]      && add_keys "sshid.io/$SSH_ID"      "$(curl -fsSL "https://sshid.io/${SSH_ID}" || true)"
[[ -n "${SSH_GH_USER:-}" ]] && add_keys "github/$SSH_GH_USER"   "$(curl -fsSL "https://github.com/${SSH_GH_USER}.keys" || true)"
[[ -n "${SSH_AUTHORIZED_KEYS:-}" ]] && add_keys "env" "$SSH_AUTHORIZED_KEYS"

# Mirror to root as a safety net (harden script later tightens root login)
install -d -m 700 /root/.ssh
cat "$AUTH" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# 5. Homebrew (as the user, not root)
if [[ "${INSTALL_BREW:-1}" == "1" ]]; then
    echo "--- homebrew ---"
    if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        mkdir -p /home/linuxbrew/.linuxbrew
        chown -R "$VPS_USER:$VPS_USER" /home/linuxbrew
        sudo -Hiu "$VPS_USER" bash -lc '
          cd "$HOME"
          NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        '
    fi
    cat > /etc/profile.d/homebrew.sh <<'PROFILE'
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
PROFILE
    chmod 644 /etc/profile.d/homebrew.sh
    BL='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
    for rc in "${USER_HOME}/.profile" "${USER_HOME}/.bashrc"; do
        append_missing "$rc" "$BL" "$VPS_USER" "$VPS_USER"
    done
    sudo -Hiu "$VPS_USER" bash -lc '
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
      brew analytics off || true
      brew update || true
    '
    if [[ -n "${BREW_PACKAGES// }" ]]; then
        sudo -Hiu "$VPS_USER" env BREW_PACKAGES="$BREW_PACKAGES" bash -lc '
          eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
          for pkg in $BREW_PACKAGES; do
            if brew list --formula "$pkg" >/dev/null 2>&1; then
              echo "ok: $pkg"
            else
              brew install "$pkg" || echo "WARN: failed $pkg"
            fi
          done
        '
    fi
fi

# 6. Optional: Node via nvm
if [[ "${INSTALL_NODE_LTS:-0}" == "1" ]]; then
    sudo -Hiu "$VPS_USER" bash -lc '
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] || curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
      . "$NVM_DIR/nvm.sh"
      nvm install --lts
      nvm alias default "lts/*"
      corepack enable || true
    '
fi

# 7. Optional: Docker
if [[ "${INSTALL_DOCKER:-0}" == "1" ]]; then
    apt-get install -y docker.io docker-compose-v2 || apt-get install -y docker.io
    systemctl enable --now docker
    usermod -aG docker "$VPS_USER"
fi

# 8. Shell niceties
BASHRC="${USER_HOME}/.bashrc"
append_missing "$BASHRC" 'command -v starship >/dev/null && eval "$(starship init bash)"' "$VPS_USER" "$VPS_USER"
append_missing "$BASHRC" 'command -v zoxide >/dev/null && eval "$(zoxide init bash)"'     "$VPS_USER" "$VPS_USER"
append_missing "$BASHRC" 'command -v eza >/dev/null && alias ls="eza --group-directories-first"' "$VPS_USER" "$VPS_USER"
append_missing "$BASHRC" 'command -v bat >/dev/null && alias cat="bat --paging=never"'    "$VPS_USER" "$VPS_USER"

echo "===== bootstrap done @ $(date -Is) ====="
BOOTSTRAP_EOF
chmod +x /usr/local/sbin/vps-bootstrap.sh
echo "Wrote /usr/local/sbin/vps-bootstrap.sh"

# ------------------------------------------------------------------------------
# Write vps-harden.sh
# ------------------------------------------------------------------------------
cat > /usr/local/sbin/vps-harden.sh <<'HARDEN_EOF'
#!/usr/bin/env bash
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
export DEBIAN_FRONTEND=noninteractive
bool() { [[ "$1" == "1" || "$1" == "true" || "$1" == "yes" ]]; }

# Safety gates
if ! id -u "$VPS_USER" &>/dev/null; then
    echo "ERROR: $VPS_USER missing — run vps-bootstrap.sh first"; exit 1
fi
if [[ "$ALLOW_PASSWORD_AUTH" == "no" ]] && ! [[ -s "/home/${VPS_USER}/.ssh/authorized_keys" ]]; then
    echo "ERROR: refusing to disable password auth with empty authorized_keys"; exit 1
fi

apt-get update -y
apt-get install -y openssh-server ufw fail2ban unattended-upgrades apt-listchanges

# SSH
if bool "${HARDEN_SSH:-1}"; then
    echo "--- ssh hardening ---"
    mkdir -p /etc/ssh/sshd_config.d
    DROPIN=/etc/ssh/sshd_config.d/99-vps-hardening.conf
    {
      echo "Port ${SSH_PORT}"
      echo "PermitRootLogin ${PERMIT_ROOT_LOGIN}"
      echo "PasswordAuthentication ${ALLOW_PASSWORD_AUTH}"
      echo "KbdInteractiveAuthentication no"
      echo "ChallengeResponseAuthentication no"
      echo "PubkeyAuthentication yes"
      echo "PermitEmptyPasswords no"
      echo "X11Forwarding no"
      echo "ClientAliveInterval 60"
      echo "ClientAliveCountMax 3"
      echo "MaxAuthTries 4"
      echo "LoginGraceTime 20"
      if bool "${LIMIT_SSH_TO_ADMIN_USER:-1}"; then
          extra=""; [[ "$PERMIT_ROOT_LOGIN" != "no" ]] && extra=" root"
          echo "AllowUsers ${VPS_USER}${extra}"
      fi
    } > "$DROPIN"
    chmod 644 "$DROPIN"
    # Ubuntu 24.04 ships ssh as a socket unit — disable so drop-ins apply reliably
    systemctl disable --now ssh.socket 2>/dev/null || true
    sshd -t
    systemctl enable --now ssh
    systemctl restart ssh
fi

# UFW
if bool "${ENABLE_UFW:-1}"; then
    echo "--- ufw ---"
    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing
    bool "${PUBLIC_SSH_ALLOWED:-1}" && ufw allow "${SSH_PORT}/tcp" comment 'public ssh'
    ufw allow 41641/udp comment 'tailscale direct'
    ufw allow in on tailscale0 comment 'tailscale iface'
    bool "${ALLOW_HTTP_HTTPS:-0}" && { ufw allow 80/tcp; ufw allow 443/tcp; }
    for p in ${EXTRA_UFW_PORTS:-}; do ufw allow "$p"; done
    ufw --force enable
fi

# fail2ban
if bool "${ENABLE_FAIL2BAN:-1}"; then
    cat > /etc/fail2ban/jail.d/sshd.local <<EOF
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

# Unattended upgrades
if bool "${ENABLE_UNATTENDED:-1}"; then
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    cat > /etc/apt/apt.conf.d/52unattended-upgrades-local <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    systemctl enable --now unattended-upgrades || true
fi

# Sysctl
if bool "${ENABLE_SYSCTL_HARDENING:-1}"; then
    cat > /etc/sysctl.d/99-vps-hardening.conf <<'EOF'
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
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
    if [[ -n "${TAILSCALE_ADVERTISE_ROUTES:-}" ]] || bool "${TAILSCALE_EXIT_NODE:-0}"; then
        cat > /etc/sysctl.d/99-tailscale-routing.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
    fi
    sysctl --system >/dev/null
fi

# Tailscale
if bool "${INSTALL_TAILSCALE:-1}"; then
    echo "--- tailscale ---"
    command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
        TS_HOST="${TAILSCALE_HOSTNAME:-${VPS_HOSTNAME:-$(hostname)}}"
        args=( up
               --authkey="$TAILSCALE_AUTHKEY"
               --hostname="$TS_HOST"
               --accept-dns="${TAILSCALE_ACCEPT_DNS:-false}"
               --operator="$VPS_USER"
               --advertise-tags="$TAILSCALE_TAGS" )
        bool "${TAILSCALE_SSH:-1}"       && args+=( --ssh )
        bool "${TAILSCALE_EXIT_NODE:-0}" && args+=( --advertise-exit-node )
        [[ -n "${TAILSCALE_ADVERTISE_ROUTES:-}" ]] && args+=( --advertise-routes="$TAILSCALE_ADVERTISE_ROUTES" )
        [[ -n "${TAILSCALE_EXTRA_ARGS:-}" ]]      && args+=( ${TAILSCALE_EXTRA_ARGS} )
        if tailscale "${args[@]}"; then
            # Scrub authkey so snapshots/images don't leak it
            sed -i -E 's|^TAILSCALE_AUTHKEY=.*|TAILSCALE_AUTHKEY=""|' "$ENV_FILE"
        else
            echo "WARN: tailscale up failed"
        fi
        tailscale status || true
    else
        echo "No TAILSCALE_AUTHKEY; tailscaled installed but not joined."
    fi
fi

# Optional: lock public SSH after tailscale is up (second-run mode)
if bool "${ENABLE_UFW:-1}" && ! bool "${PUBLIC_SSH_ALLOWED:-1}"; then
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        ufw allow in on tailscale0 to any port "$SSH_PORT" proto tcp comment 'ssh via tailnet'
        ufw delete allow "${SSH_PORT}/tcp" || true
        echo "SSH is now restricted to tailscale0"
    else
        echo "WARN: tailscale not connected — leaving public SSH rule in place"
    fi
fi

echo "===== harden done @ $(date -Is) ====="
HARDEN_EOF
chmod +x /usr/local/sbin/vps-harden.sh
echo "Wrote /usr/local/sbin/vps-harden.sh"

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

echo
echo "$(c '1;32' '═══════════════════════════════════════════════════')"
echo "$(c '1;32' '  Done.')"
echo "$(c '1;32' '═══════════════════════════════════════════════════')"
echo
echo "Hostname : $(hostnamectl --static)"
echo "User     : ${VPS_USER}"
echo "Log      : /var/log/vps-bootstrap.log"
echo
echo "Try:      ssh ${VPS_USER}@$(hostname -I | awk '{print $1}')"
if bool "${INSTALL_TAILSCALE}"; then
    echo "Tailnet:  ssh ${VPS_USER}@$(tailscale status --self --json 2>/dev/null | grep -oP '"DNSName":\s*"\K[^"]+' | head -1 || echo '<hostname>')"
fi
echo
echo "Re-run later:"
echo "  sudo /usr/local/sbin/vps-bootstrap.sh   # re-apply user/keys/brew"
echo "  sudo /usr/local/sbin/vps-harden.sh      # re-apply firewall/ssh/tailscale"
echo
if [[ "${PUBLIC_SSH_ALLOWED}" == "1" && "${INSTALL_TAILSCALE}" == "1" ]]; then
    echo "$(c '1;33' 'To lock SSH to Tailscale-only after verifying tailnet access:')"
    echo "  sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED=\"0\"/' /etc/vps/bootstrap.env"
    echo "  sudo /usr/local/sbin/vps-harden.sh"
fi