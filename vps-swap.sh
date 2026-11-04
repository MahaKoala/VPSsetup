#!/usr/bin/env bash
# Dynamic, provider-neutral swap setup. Run as root; safe to re-run.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
[[ -r "$ENV_FILE" ]] && source "$ENV_FILE"

: "${SWAP_MODE:=auto}"
: "${SWAP_PERCENT:=50}"
: "${SWAP_MIN_MB:=512}"
: "${SWAP_MAX_MB:=4096}"
: "${SWAP_DISK_RESERVE_MB:=1024}"
: "${SWAP_FILE:=/swapfile}"

if [[ "$SWAP_MODE" == "off" ]]; then
    echo "[swap] disabled by configuration"
    exit 0
fi
[[ "$SWAP_MODE" == auto ]] || { echo "Invalid SWAP_MODE: $SWAP_MODE" >&2; exit 1; }

for n in "$SWAP_PERCENT" "$SWAP_MIN_MB" "$SWAP_MAX_MB" "$SWAP_DISK_RESERVE_MB"; do
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "Swap parameters must be nonnegative integers" >&2; exit 1; }
done
(( SWAP_PERCENT >= 1 && SWAP_PERCENT <= 100 &&
   SWAP_MIN_MB >= 1 && SWAP_MAX_MB >= SWAP_MIN_MB )) ||
   { echo "Invalid swap sizing bounds" >&2; exit 1; }

# Do not overwrite an existing swap setup (including provider-managed swap).
if swapon --noheadings --show=NAME | grep -q '[^[:space:]]'; then
    echo "[swap] existing active swap retained"
    swapon --show
    exit 0
fi
if [[ -e "$SWAP_FILE" ]]; then
    echo "[swap] $SWAP_FILE exists but is not active; manual review needed"
    exit 0
fi

ram_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
[[ "$ram_kb" =~ ^[0-9]+$ ]] || { echo "Cannot detect RAM" >&2; exit 1; }
ram_mb=$(( (ram_kb + 1023) / 1024 ))
size_mb=$(( ram_mb * SWAP_PERCENT / 100 ))
(( size_mb < SWAP_MIN_MB )) && size_mb="$SWAP_MIN_MB"
(( size_mb > SWAP_MAX_MB )) && size_mb="$SWAP_MAX_MB"

disk_mb="$(df -Pm "$(dirname "$SWAP_FILE")" | awk 'NR==2 {print $4}')"
[[ "$disk_mb" =~ ^[0-9]+$ ]] || { echo "Cannot detect free disk space" >&2; exit 1; }
if (( disk_mb < size_mb + SWAP_DISK_RESERVE_MB )); then
    echo "[swap] insufficient free disk space; skipping"
    exit 0
fi

echo "[swap] RAM=${ram_mb}MB; creating ${size_mb}MB at $SWAP_FILE"
created=0
cleanup_swap() {
    if (( created )); then
        swapoff "$SWAP_FILE" >/dev/null 2>&1 || true
        rm -f "$SWAP_FILE"
    fi
}
trap cleanup_swap ERR
fallocate -l "${size_mb}M" "$SWAP_FILE"
created=1
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"
created=0
trap - ERR
if ! awk -v file="$SWAP_FILE" '$1==file {found=1} END {exit !found}' /etc/fstab; then
    printf '%s none swap sw 0 0\n' "$SWAP_FILE" >> /etc/fstab
fi
swapon --show
