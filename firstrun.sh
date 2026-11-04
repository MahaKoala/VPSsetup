#!/usr/bin/env bash
# Manual entry point when a VPS provider does not support cloud-init.
# No fixed username, hostname, SSH ID, or Tailscale key is embedded here.
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

VPS_SETUP_REF="${VPS_SETUP_REF:-main}"
base="https://raw.githubusercontent.com/MahaKoala/VPSsetup/$VPS_SETUP_REF"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fLsS --retry 3 --max-time 120 "$base/vps-init.sh" -o "$tmp"
bash -n "$tmp"
bash "$tmp" "$@"
