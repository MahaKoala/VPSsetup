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
    fd-find unzip zip jq htop tmux rsync \
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
    # Use `brew shellenv bash` (matches what Homebrew's installer prints) so PATH
    # is configured correctly even when the script runs without an interactive shell.
    cat > /etc/profile.d/homebrew.sh <<'EOF'
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
fi
EOF
    chmod 0644 /etc/profile.d/homebrew.sh

    BREW_LINE='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"'
    for rc in "${USER_HOME}/.profile" "${USER_HOME}/.bashrc"; do
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
            if brew list --formula "$pkg" >/dev/null 2>&1; then
              echo "ok: $pkg"
            else
              brew install "$pkg" || echo "WARN: failed $pkg"
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
append_line_if_missing "$BASHRC" 'command -v starship >/dev/null && eval "$(starship init bash)"' "$VPS_USER" "$VPS_USER"
append_line_if_missing "$BASHRC" 'command -v zoxide >/dev/null && eval "$(zoxide init bash)"' "$VPS_USER" "$VPS_USER"
append_line_if_missing "$BASHRC" 'command -v eza >/dev/null && alias ls="eza --group-directories-first"' "$VPS_USER" "$VPS_USER"
append_line_if_missing "$BASHRC" 'command -v bat >/dev/null && alias cat="bat --paging=never"' "$VPS_USER" "$VPS_USER"

echo "===== bootstrap complete @ $(date -Is) ====="
echo "Next: /usr/local/sbin/vps-harden.sh"