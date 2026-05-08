#!/usr/bin/env bash
# Quick manual run for VPS (no cloud-init) — MahaKoala/VPSsetup
set -Eeuo pipefail

mkdir -p /etc/vps /usr/local/sbin
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/bootstrap.env    -o /etc/vps/bootstrap.env
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-bootstrap.sh -o /usr/local/sbin/vps-bootstrap.sh
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-harden.sh    -o /usr/local/sbin/vps-harden.sh
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-tools.sh     -o /usr/local/sbin/vps-tools.sh
chmod +x /usr/local/sbin/vps-bootstrap.sh /usr/local/sbin/vps-harden.sh /usr/local/sbin/vps-tools.sh

VPS_USER=maha SSH_ID=mahakoala VPS_ROLE=dev \
TAILSCALE_AUTHKEY=tskey-auth-... TAILSCALE_TAGS=tag:vps,tag:staging \
/usr/local/sbin/vps-bootstrap.sh && /usr/local/sbin/vps-harden.sh && /usr/local/sbin/vps-tools.sh

# After verifying you can connect via Tailscale:
#   PUBLIC_SSH_ALLOWED=0 /usr/local/sbin/vps-harden.sh
