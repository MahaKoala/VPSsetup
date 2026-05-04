#!/usr/bin/env bash
# VerifyChecklist.sh — post-deploy health and security audit.
# Run on the VPS after vps-bootstrap.sh + vps-harden.sh.
#
# Usage:
#   sudo bash VerifyChecklist.sh

set -u

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
section() { echo; echo "$(c '1;36' "▶ $*")"; }
ok()   { echo "  $(c '0;32' '✓') $*"; }
warn() { echo "  $(c '0;33' '!') $*"; }
fail() { echo "  $(c '0;31' '✗') $*"; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    warn "not running as root — some checks (sshd -T, fail2ban, ufw) will be limited"
fi

# Pull VPS_USER from the env file if available so per-user checks know who to inspect.
if [[ -r /etc/vps/bootstrap.env ]]; then
    # shellcheck disable=SC1091
    source /etc/vps/bootstrap.env
fi
VPS_USER="${VPS_USER:-}"

section "Hostname / OS"
hostnamectl 2>/dev/null || warn "hostnamectl unavailable"

section "Kernel / uptime"
uname -a
uptime

section "Disk / memory"
df -h / 2>/dev/null
free -h 2>/dev/null

section "SSH config (effective)"
if command -v sshd >/dev/null; then
    sshd -T 2>/dev/null | grep -iE \
        '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|kbdinteractiveauthentication|x11forwarding|clientaliveinterval|maxauthtries) ' \
        || warn "could not read sshd effective config (run as root)"
else
    fail "sshd not installed"
fi

section "authorized_keys per user"
for u in root $VPS_USER $(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}'); do
    [[ -z "$u" ]] && continue
    home="$(getent passwd "$u" | cut -d: -f6)"
    f="$home/.ssh/authorized_keys"
    if [[ -s "$f" ]]; then
        ok "$u: $(grep -cvE '^\s*(#|$)' "$f" 2>/dev/null || wc -l < "$f") key(s) in $f"
    fi
done

section "UFW status"
if command -v ufw >/dev/null; then
    ufw status verbose 2>/dev/null || warn "ufw status failed (root needed)"
else
    warn "ufw not installed"
fi

section "fail2ban — sshd jail"
if command -v fail2ban-client >/dev/null; then
    fail2ban-client status sshd 2>/dev/null || warn "fail2ban sshd jail not running"
else
    warn "fail2ban not installed"
fi

section "unattended-upgrades"
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    ok "unattended-upgrades active"
else
    warn "unattended-upgrades not active"
fi

section "Tailscale"
if command -v tailscale >/dev/null; then
    tailscale status 2>/dev/null || warn "tailscale not connected"
    ip -brief addr show tailscale0 2>/dev/null || warn "tailscale0 interface not up"
else
    warn "tailscale not installed"
fi

section "Homebrew (per-user)"
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    if [[ -n "$VPS_USER" ]] && id -u "$VPS_USER" &>/dev/null; then
        sudo -Hiu "$VPS_USER" bash -lc 'brew --version; brew doctor || true' 2>/dev/null \
            || warn "brew check failed for $VPS_USER"
    else
        warn "VPS_USER unknown; skipping per-user brew check"
    fi
else
    warn "brew not installed at /home/linuxbrew/.linuxbrew"
fi

section "Listening ports"
if command -v ss >/dev/null; then
    ss -tulpn 2>/dev/null | head -40
elif command -v netstat >/dev/null; then
    netstat -tulpn 2>/dev/null | head -40
else
    warn "no ss/netstat available"
fi

echo
echo "$(c '1;32' '── Verification done. Logs: /var/log/vps-bootstrap.log ──')"
