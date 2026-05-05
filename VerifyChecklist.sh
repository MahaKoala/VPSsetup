#!/usr/bin/env bash
# VerifyChecklist.sh — post-deploy health and security audit.
#
# Usage:
#   sudo bash VerifyChecklist.sh             # full audit (recommended)
#   sudo bash VerifyChecklist.sh --quiet     # only show warnings, failures, summary
#   sudo bash VerifyChecklist.sh --report    # only show last install's [STATUS] tally
#   sudo bash VerifyChecklist.sh --help
#
# Exit code: 0 if no failures, 1 if any check failed.

set -u

# ---------- arg parsing ----------
QUIET=0
REPORT_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --quiet|-q)  QUIET=1 ;;
        --report|-r) REPORT_ONLY=1 ;;
        --help|-h)   sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

# ---------- helpers ----------
c()       { printf '\033[%sm%s\033[0m' "$1" "$2"; }
section() { (( QUIET )) || { echo; echo "$(c '1;36' "▶ $*")"; }; }
ok()      { CHK_OK=$((CHK_OK+1));     (( QUIET )) || echo "  $(c '0;32' '✓') $*"; }
warn()    { CHK_WARN=$((CHK_WARN+1)); echo "  $(c '0;33' '!') $*"; }
fail()    { CHK_FAIL=$((CHK_FAIL+1)); echo "  $(c '0;31' '✗') $*"; }
note()    { (( QUIET )) || echo "    $*"; }

CHK_OK=0
CHK_WARN=0
CHK_FAIL=0

# Pull config so per-user / per-port checks know what to look for
if [[ -r /etc/vps/bootstrap.env ]]; then
    # shellcheck disable=SC1091
    source /etc/vps/bootstrap.env
fi
VPS_USER="${VPS_USER:-}"
SSH_PORT="${SSH_PORT:-22}"

EUID_NOW="${EUID:-$(id -u)}"
if (( EUID_NOW != 0 )); then
    warn "not running as root — sshd, fail2ban, ufw checks will be limited (re-run with sudo)"
fi

# ============================================================
# Install report (parses /var/log/vps-bootstrap.log [STATUS] lines)
# ============================================================
LOG=/var/log/vps-bootstrap.log
if [[ -r "$LOG" ]]; then
    section "Last install: [STATUS] tally from $LOG"
    rep_ok=$(grep -c '^\[STATUS\] ok|'   "$LOG" 2>/dev/null || true); rep_ok=${rep_ok:-0}
    rep_warn=$(grep -c '^\[STATUS\] warn|' "$LOG" 2>/dev/null || true); rep_warn=${rep_warn:-0}
    rep_fail=$(grep -c '^\[STATUS\] fail|' "$LOG" 2>/dev/null || true); rep_fail=${rep_fail:-0}
    note "$(c '0;32' "ok=$rep_ok")  $(c '0;33' "warn=$rep_warn")  $(c '0;31' "fail=$rep_fail")"

    if (( rep_warn > 0 )); then
        echo "    $(c '1;33' 'warnings:')"
        grep '^\[STATUS\] warn|' "$LOG" | awk -F'|' '{
            if ($3 != "") printf "      ! %-32s (%s)\n", $2, $3
            else          printf "      ! %s\n", $2
        }'
    fi
    if (( rep_fail > 0 )); then
        echo "    $(c '1;31' 'failures:')"
        grep '^\[STATUS\] fail|' "$LOG" | awk -F'|' '{
            if ($3 != "") printf "      ✗ %-32s (%s)\n", $2, $3
            else          printf "      ✗ %s\n", $2
        }'
    fi
fi

if (( REPORT_ONLY )); then
    exit 0
fi

# ============================================================
# System
# ============================================================
section "Hostname / OS"
hn=$(hostnamectl --static 2>/dev/null || hostname)
ok "hostname: $hn"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    ok "os: ${PRETTY_NAME:-unknown}"
fi
note "kernel: $(uname -r)"
note "uptime: $(uptime -p 2>/dev/null || uptime)"

section "Disk space"
# Warn under 2GB free on / or /home, fail under 500MB.
while read -r mount free_kb; do
    free_gb=$(( free_kb / 1024 / 1024 ))
    if (( free_kb < 500*1024 )); then
        fail "disk: $mount has only ${free_gb}GB free (< 500MB threshold)"
    elif (( free_kb < 2*1024*1024 )); then
        warn "disk: $mount has ${free_gb}GB free (< 2GB threshold)"
    else
        ok "disk: $mount has ${free_gb}GB free"
    fi
done < <(df -P / /home /var 2>/dev/null | awk 'NR>1 {print $6, $4}' | sort -u)

# ============================================================
# SSH
# ============================================================
section "SSH config (effective)"
if ! command -v sshd >/dev/null; then
    fail "sshd not installed"
elif (( EUID_NOW != 0 )); then
    warn "sshd -T requires root — re-run with sudo to inspect effective config"
else
    # Capture both stdout and stderr so we can show the actual error if it
    # fails — `2>/dev/null` would mask a useful diagnostic.
    SSHD_T_RAW=$(sshd -T 2>&1)
    sshd_rc=$?
    if (( sshd_rc != 0 )); then
        fail "sshd -T failed (exit $sshd_rc) — output below:"
        echo "$SSHD_T_RAW" | head -8 | sed 's/^/      /'
        note "Try: sudo sshd -T   (interactive, full output)"
        note "     sudo sshd -t   (syntax check only)"
        note "     sudo ssh-keygen -A   (regenerate missing host keys)"
        SSHD_T=""
    elif [[ -z "$SSHD_T_RAW" ]]; then
        fail "sshd -T returned empty output"
        SSHD_T=""
    else
        SSHD_T="$SSHD_T_RAW"
    fi
    if [[ -n "$SSHD_T" ]]; then
        get_sshd() { echo "$SSHD_T" | grep -i "^$1 " | head -1 | awk '{print $2}'; }

        eff_port=$(get_sshd port)
        eff_root=$(get_sshd permitrootlogin)
        eff_pw=$(get_sshd passwordauthentication)
        eff_pubkey=$(get_sshd pubkeyauthentication)
        eff_kbd=$(get_sshd kbdinteractiveauthentication)
        eff_x11=$(get_sshd x11forwarding)
        eff_alive=$(get_sshd clientaliveinterval)
        eff_max=$(get_sshd maxauthtries)

        [[ "$eff_port" == "$SSH_PORT" ]]      && ok "Port = $eff_port"            || warn "Port = $eff_port (expected $SSH_PORT)"
        [[ "$eff_pw" == "no" ]]               && ok "PasswordAuthentication = no" || warn "PasswordAuthentication = $eff_pw (expected no)"
        [[ "$eff_pubkey" == "yes" ]]          && ok "PubkeyAuthentication = yes"  || fail "PubkeyAuthentication = $eff_pubkey (expected yes!)"
        [[ "$eff_kbd" == "no" ]]              && ok "KbdInteractiveAuthentication = no" || warn "KbdInteractiveAuthentication = $eff_kbd"
        [[ "$eff_x11" == "no" ]]              && ok "X11Forwarding = no"          || warn "X11Forwarding = $eff_x11"
        case "$eff_root" in
            no)                  ok "PermitRootLogin = no" ;;
            prohibit-password|forced-commands-only) ok "PermitRootLogin = $eff_root (key-only)" ;;
            *)                   warn "PermitRootLogin = $eff_root (consider 'prohibit-password' or 'no')" ;;
        esac
        note "ClientAliveInterval = ${eff_alive:-unset}"
        note "MaxAuthTries        = ${eff_max:-unset}"

        if echo "$SSHD_T" | grep -qi '^allowusers '; then
            au=$(echo "$SSHD_T" | grep -i '^allowusers ' | sed 's/^[Aa][Ll][Ll][Oo][Ww][Uu][Ss][Ee][Rr][Ss] //')
            ok "AllowUsers = $au"
        else
            warn "AllowUsers not set — any system user with a key could SSH"
        fi
    fi
fi

section "authorized_keys per user"
seen=""
check_keys_for() {
    local u="$1"
    [[ -z "$u" || "$seen" == *":$u:"* ]] && return
    seen="${seen}:$u:"
    local home f n
    home=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
    [[ -z "$home" ]] && return
    f="$home/.ssh/authorized_keys"
    if [[ -s "$f" ]]; then
        n=$(grep -cvE '^\s*(#|$)' "$f" 2>/dev/null || wc -l < "$f")
        ok "$u: $n key(s) in $f"
    else
        if [[ "$u" == "root" || "$u" == "$VPS_USER" ]]; then
            warn "$u: $f is empty or missing"
        fi
    fi
}
check_keys_for root
check_keys_for "$VPS_USER"
while IFS= read -r u; do check_keys_for "$u"; done < <(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}')

# ============================================================
# Firewall / fail2ban
# ============================================================
section "UFW"
if ! command -v ufw >/dev/null; then
    warn "ufw not installed"
elif (( EUID_NOW != 0 )); then
    warn "ufw status requires root — re-run with sudo"
else
    UFW_OUT=$(ufw status verbose 2>/dev/null || true)
    if echo "$UFW_OUT" | grep -q '^Status: active'; then
        ok "ufw active"
        if echo "$UFW_OUT" | grep -qE "(^| )${SSH_PORT}/tcp[[:space:]]+ALLOW"; then
            ok "ssh path: public ${SSH_PORT}/tcp allowed"
        else
            note "ssh path: public ${SSH_PORT}/tcp not allowed (tailnet-only mode)"
        fi
        if echo "$UFW_OUT" | grep -qE "tailscale0.*ALLOW"; then
            ok "ssh path: tailscale0 allowed"
        else
            warn "tailscale0 not in ufw — tailnet SSH won't work"
        fi
    else
        fail "ufw is installed but not active — re-run 'sudo /usr/local/sbin/vps-harden.sh'"
        note "(common when a previous harden run aborted before §3 UFW; harden is idempotent and safe to re-run)"
    fi
fi

section "fail2ban"
if ! command -v fail2ban-client >/dev/null; then
    warn "fail2ban not installed"
elif ! systemctl is-active --quiet fail2ban 2>/dev/null; then
    fail "fail2ban service not active"
else
    ok "fail2ban service active"
    if (( EUID_NOW == 0 )); then
        F2B=$(fail2ban-client status sshd 2>/dev/null || true)
        if [[ -n "$F2B" ]]; then
            curr=$(echo "$F2B" | grep -oE 'Currently banned:\s*[0-9]+' | grep -oE '[0-9]+' || echo "?")
            tot=$(echo  "$F2B" | grep -oE 'Total banned:\s*[0-9]+'    | grep -oE '[0-9]+' || echo "?")
            ok "sshd jail: currently_banned=$curr total_banned=$tot"
        else
            warn "sshd jail not configured in fail2ban"
        fi
    else
        warn "skipping fail2ban-client status (need root)"
    fi
fi

section "unattended-upgrades"
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    ok "service active"
elif systemctl list-unit-files unattended-upgrades.service >/dev/null 2>&1; then
    fail "unattended-upgrades installed but not active"
else
    warn "unattended-upgrades not installed"
fi

# ============================================================
# Tailscale
# ============================================================
section "Tailscale"
if ! command -v tailscale >/dev/null; then
    warn "tailscale not installed"
else
    TS=$(tailscale status 2>&1 || true)
    if echo "$TS" | grep -qiE 'logged out|not logged in|not authenticated|Logged out'; then
        warn "tailscale installed but not joined (run: sudo tailscale up --auth-key=<key>)"
    elif echo "$TS" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        self_ip=$(echo "$TS" | head -1 | awk '{print $1}')
        self_name=$(echo "$TS" | head -1 | awk '{print $2}')
        ok "tailscale up: $self_name @ $self_ip"
        peers=$(echo "$TS" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo 0)
        ok "tailnet peers visible: $peers"
        if ip -brief addr show tailscale0 >/dev/null 2>&1; then
            ts_addr=$(ip -brief addr show tailscale0 | awk '{print $3}')
            ok "tailscale0 interface up: $ts_addr"
        else
            fail "tailscale0 interface missing despite 'tailscale up' showing connected"
        fi
    else
        warn "tailscale status unparseable: $(echo "$TS" | head -1)"
    fi
fi

# ============================================================
# Homebrew & user PATH spot-check
# ============================================================
section "Homebrew (per-user)"
if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    warn "brew not installed at /home/linuxbrew/.linuxbrew"
elif [[ -z "$VPS_USER" ]] || ! id -u "$VPS_USER" &>/dev/null; then
    warn "VPS_USER unset or missing — skipping per-user brew check"
else
    # Run brew --version from a CWD the user can read; capture both stdout and stderr.
    brew_v=$(sudo -Hu "$VPS_USER" bash -c \
        'cd "$HOME"; /home/linuxbrew/.linuxbrew/bin/brew --version 2>&1 | head -1' 2>&1)
    if echo "$brew_v" | grep -q '^Homebrew'; then
        ok "$brew_v (under $VPS_USER)"
    else
        fail "brew under $VPS_USER errored: $brew_v"
    fi

    section "Tool resolution in $VPS_USER's login shell"
    # Spot-check tools we expect to be installed. -lc loads .profile/.bashrc so
    # shellenv + ~/.local/bin PATH lines apply, mirroring a real login.
    for tool in brew node npm gh starship eza bat fzf zoxide claude lazygit; do
        if sudo -Hu "$VPS_USER" bash -lc "cd \$HOME; command -v $tool >/dev/null"; then
            ok "$tool resolves"
        else
            warn "$tool NOT in PATH for $VPS_USER (or not installed)"
        fi
    done
fi

# ============================================================
# Listening ports (info only)
# ============================================================
section "Listening ports (info)"
if (( EUID_NOW != 0 )); then
    note "(root needed for full process names)"
fi
if command -v ss >/dev/null; then
    if (( QUIET )); then
        :
    else
        ss -tulpnH 2>/dev/null | head -15
    fi
elif command -v netstat >/dev/null; then
    (( QUIET )) || netstat -tulpn 2>/dev/null | head -15
fi

# ============================================================
# Final tally
# ============================================================
echo
echo "$(c '1;36' '── Verify summary ──')"
echo "  $(c '0;32' "✓ ok:")   $CHK_OK"
echo "  $(c '0;33' "! warn:") $CHK_WARN"
echo "  $(c '0;31' "✗ fail:") $CHK_FAIL"
echo
if (( CHK_FAIL > 0 )); then
    echo "$(c '1;31' 'Result: FAIL') — see ✗ items above and fix before locking SSH to tailnet."
elif (( CHK_WARN > 0 )); then
    echo "$(c '1;33' 'Result: PASS with warnings') — review ! items, decide if action needed."
else
    echo "$(c '1;32' 'Result: PASS')"
fi
echo "Full install log: $LOG"

exit $(( CHK_FAIL > 0 ? 1 : 0 ))
