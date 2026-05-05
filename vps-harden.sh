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

    # State machine to apply config without locking the operator out:
    #   - ssh.service already active  → reload (SIGHUP, preserves sessions)
    #   - ssh.service not active yet  → start (first transition off ssh.socket)
    #   - either fails                → fall back / print diagnostics, abort
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