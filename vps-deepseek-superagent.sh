#!/usr/bin/env bash
# Optional research-only staging of DeepSeek Super-Agent prototype.
# This DOES NOT install/run the agent, install dependencies, or grant credentials.
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run as root (sudo)" >&2; exit 1; }
ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
[[ -r "$ENV_FILE" ]] && source "$ENV_FILE"
: "${VPS_USER:=maha}"
: "${DEEPSEEK_SUPERAGENT_REF:=main}"
id -u "$VPS_USER" >/dev/null 2>&1 || { echo "No user: $VPS_USER" >&2; exit 1; }
[[ "$VPS_USER" != root ]] || { echo "Stage under an unprivileged user" >&2; exit 1; }
home="$(getent passwd "$VPS_USER" | cut -d: -f6)"
target="${DEEPSEEK_SUPERAGENT_DIR:-$home/workspaces/dsh-superagent-prototype}"
[[ "$target" == "$home/"* ]] || { echo "Stage directory must be under $home" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git required; run vps-bootstrap.sh" >&2; exit 1; }
if [[ -e "$target" ]]; then
  echo "[STATUS] ok|deepseek-superagent|existing checkout preserved: $target"
  exit 0
fi
install -d -m 700 -o "$VPS_USER" -g "$(id -gn "$VPS_USER")" "$(dirname "$target")"
runuser -u "$VPS_USER" -- git clone --depth 1 --branch "$DEEPSEEK_SUPERAGENT_REF" \
  https://github.com/deepseek-ai/dsh-superagent-prototype.git "$target"
echo "[STATUS] ok|deepseek-superagent|source staged, NOT built or executed"
echo "Review upstream README, SETUP.md, license, security and permissions first:"
echo "  $target"
echo "No GitHub token, background service, Docker container or agent was started."
