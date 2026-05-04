#!/usr/bin/env bash
# NEWUSER_CREATES
# add-sshid-key.sh — fetch SSH public keys from sshid.io and install them
# into a target user's authorized_keys. Optionally create the user with
# sudo privileges. Idempotent; safe to re-run.
#
# Usage:
#   sudo ./add-sshid-key.sh                            # root, mahakoala, RSA
#   sudo ./add-sshid-key.sh -i mahakoala -c            # create user 'mahakoala' with sudo
#   sudo ./add-sshid-key.sh -i mahakoala -u pink -c    # create user 'pink' with sudo
#   sudo ./add-sshid-key.sh -i mahakoala -t ALL        # fetch all key types
#   sudo ./add-sshid-key.sh -i mahakoala -c --no-nopasswd
#
# Piped:
#   curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/add-sshid-key.sh \
#     | sudo bash -s -- -i mahakoala -c

set -Eeuo pipefail
umask 077

# ---------- defaults ----------
SSHID="${SSHID:-mahakoala}"
TARGET_USER="${TARGET_USER:-}"
KEY_TYPE="${KEY_TYPE:-RSA}"       # RSA | ED25519 | ECDSA | ALL
RELOAD_SSH="${RELOAD_SSH:-1}"
CREATE_USER="${CREATE_USER:-0}"
PASSWORDLESS_SUDO="${PASSWORDLESS_SUDO:-1}"
USER_SHELL="${USER_SHELL:-/bin/bash}"
BASE_URL="${BASE_URL:-https://sshid.io}"

# ---------- args ----------
usage() {
    cat <<EOF
Usage: $0 [options]

  -i, --id ID           sshid.io identifier           (default: $SSHID)
  -u, --user USER       target user                   (default: root, or \$SSHID with -c)
  -t, --type TYPE       RSA | ED25519 | ECDSA | ALL   (default: $KEY_TYPE)
  -c, --create-user     create the user if missing, grant sudo
      --no-nopasswd     when creating, require password for sudo (default: passwordless)
      --shell PATH      login shell for created user  (default: $USER_SHELL)
      --no-reload       don't reload sshd after install
  -h, --help            show this help

Examples:
  sudo $0                                  # install mahakoala's RSA key into root
  sudo $0 -c                               # create user 'mahakoala' with sudo, install key
  sudo $0 -i mahakoala -u pink -c          # create user 'pink' with sudo, install key
  sudo $0 -i mahakoala -u pink -c -t ALL   # same, fetch all key types
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--id)          SSHID="$2"; shift 2 ;;
        -u|--user)        TARGET_USER="$2"; shift 2 ;;
        -t|--type)        KEY_TYPE="$2"; shift 2 ;;
        -c|--create-user) CREATE_USER=1; shift ;;
        --no-nopasswd)    PASSWORDLESS_SUDO=0; shift ;;
        --shell)          USER_SHELL="$2"; shift 2 ;;
        --no-reload)      RELOAD_SSH=0; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
    esac
done

# Default target user: if --create-user given, use SSHID; else root
if [[ -z "$TARGET_USER" ]]; then
    if [[ "$CREATE_USER" == "1" ]]; then
        TARGET_USER="$SSHID"
    else
        TARGET_USER="root"
    fi
fi

# ---------- pretty logging ----------
log()  { printf '\033[0;36m[ssh-id]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[ ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[warn ]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[fail ]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- checks ----------
[[ $EUID -eq 0 ]] || die "must run as root (try: sudo $0)"
command -v curl >/dev/null || die "curl is required"

valid_username() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

# ---------- ensure user exists ----------
ensure_user() {
    local user="$1"

    if [[ "$user" == "root" ]]; then
        return 0
    fi

    if id "$user" &>/dev/null; then
        local uid; uid="$(id -u "$user")"
        if (( uid < 1000 )) && [[ "$user" != "root" ]]; then
            die "refusing to use system user '$user' (uid $uid)"
        fi
        log "user '$user' already exists (uid $uid)"
    else
        if [[ "$CREATE_USER" != "1" ]]; then
            die "user '$user' does not exist (use -c / --create-user to create)"
        fi
        valid_username "$user" || die "invalid username: '$user'"
        log "creating user '$user' (shell: $USER_SHELL)"

        if command -v adduser >/dev/null 2>&1 && adduser --help 2>&1 | grep -q -- --disabled-password; then
            # Debian/Ubuntu adduser
            adduser --disabled-password --gecos "" --shell "$USER_SHELL" "$user"
        else
            # Generic useradd fallback (RHEL/Alpine/etc.)
            useradd -m -s "$USER_SHELL" "$user"
            passwd -l "$user" >/dev/null
        fi
        ok "user '$user' created with locked password (SSH-key-only)"
    fi

    # Grant sudo/wheel membership when -c was passed (even if user existed)
    if [[ "$CREATE_USER" == "1" ]]; then
        local admin_group=""
        if getent group sudo  >/dev/null; then admin_group="sudo"
        elif getent group wheel >/dev/null; then admin_group="wheel"
        fi

        if [[ -n "$admin_group" ]]; then
            if id -nG "$user" | tr ' ' '\n' | grep -qx "$admin_group"; then
                log "user '$user' already in '$admin_group' group"
            else
                usermod -aG "$admin_group" "$user"
                ok "added '$user' to '$admin_group' group"
            fi
        else
            warn "no sudo/wheel group found; skipping group membership"
        fi

        if [[ "$PASSWORDLESS_SUDO" == "1" ]]; then
            local sudoers_file="/etc/sudoers.d/90-$user"
            echo "$user ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
            chmod 0440 "$sudoers_file"
            if command -v visudo >/dev/null 2>&1; then
                visudo -cf "$sudoers_file" >/dev/null || {
                    rm -f "$sudoers_file"
                    die "sudoers syntax check failed; rolled back"
                }
            fi
            ok "passwordless sudo enabled via $sudoers_file"
        fi
    fi
}

ensure_user "$TARGET_USER"

# ---------- resolve home dir ----------
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -d "$HOME_DIR" ]] || die "home directory '$HOME_DIR' not found for $TARGET_USER"

SSH_DIR="$HOME_DIR/.ssh"
AUTH_FILE="$SSH_DIR/authorized_keys"

install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$SSH_DIR"
touch "$AUTH_FILE"
chown "$TARGET_USER:$TARGET_USER" "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

# ---------- tempfile with cleanup ----------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM

# ---------- fetch + append ----------
fetch_and_add() {
    local type="$1"
    local url="${BASE_URL}/${SSHID}/${type}"
    log "fetching $url"

    if ! curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$TMP"; then
        warn "could not fetch $type key from $url (skipping)"
        return 1
    fi

    if ! grep -qE '^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-)' "$TMP"; then
        warn "response from $url did not look like an SSH key (skipping)"
        return 1
    fi

    local added=0 skipped=0 line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if grep -qxF "$line" "$AUTH_FILE"; then
            skipped=$((skipped + 1))
        else
            printf '%s\n' "$line" >> "$AUTH_FILE"
            added=$((added + 1))
        fi
    done < "$TMP"

    ok "$type: added $added, already present $skipped"
    return 0
}

# ---------- main ----------
case "${KEY_TYPE^^}" in
    ALL)
        any=0
        for t in RSA ED25519 ECDSA; do
            fetch_and_add "$t" && any=1 || true
        done
        (( any )) || die "no keys were fetched for '$SSHID'"
        ;;
    RSA|ED25519|ECDSA)
        fetch_and_add "${KEY_TYPE^^}" || die "failed to fetch $KEY_TYPE key for '$SSHID'"
        ;;
    *)
        die "invalid key type: $KEY_TYPE (use RSA, ED25519, ECDSA, or ALL)"
        ;;
esac

# ---------- re-assert permissions ----------
chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_FILE"

# ---------- reload sshd ----------
if [[ "$RELOAD_SSH" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
    if systemctl reload ssh 2>/dev/null; then
        ok "reloaded ssh.service"
    elif systemctl reload sshd 2>/dev/null; then
        ok "reloaded sshd.service"
    else
        warn "no ssh/sshd service found to reload (authorized_keys is re-read per login anyway)"
    fi
fi

echo
log "summary"
printf '  user        : %s\n' "$TARGET_USER"
printf '  home        : %s\n' "$HOME_DIR"
printf '  authorized  : %s (%s line(s))\n' "$AUTH_FILE" "$(wc -l < "$AUTH_FILE")"
printf '  sshid       : %s\n' "$SSHID"
if [[ "$TARGET_USER" != "root" ]]; then
    printf '  groups      : %s\n' "$(id -nG "$TARGET_USER" | tr ' ' ',')"
fi
echo
log "test with:  ssh ${TARGET_USER}@$(hostname -I 2>/dev/null | awk '{print $1}')"