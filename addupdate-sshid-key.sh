#!/usr/bin/env bash 
# EXISTING USER
# add-sshid-key.sh — fetch SSH public keys from sshid.io and install them
# into a target user's authorized_keys. Idempotent; safe to re-run.
#
# Usage:
#   sudo ./add-sshid-key.sh                            # defaults: root, mahakoala, RSA
#   sudo ./add-sshid-key.sh -i mahakoala               # explicit id
#   sudo ./add-sshid-key.sh -i mahakoala -u maha       # install for user 'maha'
#   sudo ./add-sshid-key.sh -i mahakoala -t ED25519    # different key type
#   sudo ./add-sshid-key.sh -i mahakoala -t ALL        # fetch all key types
#   sudo ./add-sshid-key.sh -i mahakoala -u root --no-reload
#
# Piped:
#   curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/add-sshid-key.sh | sudo bash

set -Eeuo pipefail
umask 077

# ---------- defaults ----------
SSHID="${SSHID:-mahakoala}"
TARGET_USER="${TARGET_USER:-root}"
KEY_TYPE="${KEY_TYPE:-RSA}"   # RSA | ED25519 | ECDSA | ALL
RELOAD_SSH="${RELOAD_SSH:-1}"
BASE_URL="${BASE_URL:-https://sshid.io}"

# ---------- args ----------
usage() {
    cat <<EOF
Usage: $0 [-i SSHID] [-u USER] [-t TYPE] [--no-reload]

  -i, --id       sshid.io identifier           (default: $SSHID)
  -u, --user     target user                   (default: $TARGET_USER)
  -t, --type     RSA | ED25519 | ECDSA | ALL   (default: $KEY_TYPE)
      --no-reload  don't reload sshd after install
  -h, --help     show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--id)      SSHID="$2"; shift 2 ;;
        -u|--user)    TARGET_USER="$2"; shift 2 ;;
        -t|--type)    KEY_TYPE="$2"; shift 2 ;;
        --no-reload)  RELOAD_SSH=0; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
    esac
done

# ---------- pretty logging ----------
log()  { printf '\033[0;36m[ssh-id]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[ ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[warn ]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[fail ]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- checks ----------
[[ $EUID -eq 0 ]] || die "must run as root (try: sudo $0)"
command -v curl >/dev/null || die "curl is required"

id "$TARGET_USER" &>/dev/null || die "user '$TARGET_USER' does not exist"

HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -d "$HOME_DIR" ]] || die "home directory '$HOME_DIR' not found for $TARGET_USER"

SSH_DIR="$HOME_DIR/.ssh"
AUTH_FILE="$SSH_DIR/authorized_keys"

# ---------- prepare ~/.ssh ----------
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

    # -f: fail on HTTP errors; -L: follow redirects; -S: show errors on -s
    if ! curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$TMP"; then
        warn "could not fetch $type key from $url (skipping)"
        return 1
    fi

    # sshid.io returns HTML 200 for bad IDs sometimes; sanity-check content.
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
            fetch_and_add "$t" && any=1
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

# ---------- ensure permissions again (paranoid) ----------
chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_FILE"

# ---------- reload sshd ----------
# Note: sshd rereads authorized_keys on each login; reload isn't strictly needed
# but matches your original flow. We try multiple unit names.
if [[ "$RELOAD_SSH" == "1" ]]; then
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl reload ssh 2>/dev/null; then
            ok "reloaded ssh.service"
        elif systemctl reload sshd 2>/dev/null; then
            ok "reloaded sshd.service"
        else
            warn "no ssh/sshd service found to reload (authorized_keys is read per-login anyway)"
        fi
    fi
fi

log "done. $AUTH_FILE now contains $(wc -l < "$AUTH_FILE") line(s)."