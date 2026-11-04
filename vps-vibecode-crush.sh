#!/usr/bin/env bash
# vps-vibecode-crush.sh — OPTIONAL Charm Crush worker, independent of cloud-init.
# Run as root on Ubuntu after base user/bootstrap. It does not run by default.
# It never copies API keys into config files or executes as root by default.
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "ERROR: Run with sudo/root" >&2; exit 1; }

ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
if [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
: "${VPS_USER:=maha}"
: "${VPS_SETUP_REF:=main}"
: "${CRUSH_SETUP_REF:=$VPS_SETUP_REF}"
: "${CRUSH_MCP_PROFILE:=core}"    # none | core | extended
: "${CRUSH_LSP_PROFILE:=web,python}" # comma-separated: web,python,go,rust,none
: "${CRUSH_INSTALL_ROOT:=0}"      # root config is explicitly opt-in
: "${CRUSH_CONFIG_ONLY:=0}"       # 1 = configure without installing packages
: "${CRUSH_OVERWRITE_COMMANDS:=0}" # preserve user-edited commands
: "${CRUSH_INSTALL_BIN:=1}"

id -u "$VPS_USER" >/dev/null 2>&1 ||
  { echo "ERROR: User $VPS_USER does not exist; run vps-bootstrap.sh first" >&2; exit 1; }
[[ "$VPS_USER" != root ]] || { echo "ERROR: Choose an unprivileged VPS_USER" >&2; exit 1; }
case "$CRUSH_MCP_PROFILE" in none|core|extended) ;; *) echo "Invalid CRUSH_MCP_PROFILE" >&2; exit 1 ;; esac

CRUSH_LSP_PROFILE="${CRUSH_LSP_PROFILE//,/ }"
lsp_profiles=()
for profile in $CRUSH_LSP_PROFILE; do
  case "$profile" in
    none) ;;
    web|python|go|rust) lsp_profiles+=("$profile") ;;
    *) echo "ERROR: Invalid LSP profile: $profile" >&2; exit 1 ;;
  esac
done

log=/var/log/vps-bootstrap.log
exec > >(tee -a "$log") 2>&1
status() { printf '[STATUS] %s|crush %s|%s\n' "$1" "$2" "${3:-}"; }
base="https://raw.githubusercontent.com/MahaKoala/VPSsetup/$CRUSH_SETUP_REF"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

download() {
  local item="$1" target="$stage/$item"
  mkdir -p "$(dirname "$target")"
  curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 \
    "$base/vibecode-crush/$item" -o "$target"
  [[ -s "$target" ]] || { status fail "download" "$item empty"; return 1; }
}

echo "=== Optional Crush worker for $VPS_USER (ref=$CRUSH_SETUP_REF) ==="
for item in providers.crushrc core.crushrc extended.crushrc \
    lsp/web.crushrc lsp/python.crushrc lsp/go.crushrc lsp/rust.crushrc \
    templates/frontend.crushrc templates/deploy.crushrc \
    commands/plan.md commands/ship.md commands/review.md \
    commands/debug.md commands/scaffold.md; do
  download "$item"
done
# Validate all downloaded script-like config assets before deployment.
while IFS= read -r -d '' rc; do bash -n "$rc"; done < <(find "$stage" -name '*.crushrc' -print0)
status ok "assets" "downloaded and Bash-syntax-checked"

if [[ "$CRUSH_CONFIG_ONLY" != "1" ]]; then
  if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    status fail "dependencies" "Homebrew missing; set INSTALL_BREW=1 and run vps-bootstrap.sh, or CRUSH_CONFIG_ONLY=1"
    exit 1
  fi

  # Never run package managers as root. Existing packages are reused.
  sudo -Hu "$VPS_USER" env \
    CRUSH_INSTALL_BIN="$CRUSH_INSTALL_BIN" \
    CRUSH_LSP_PROFILE="$CRUSH_LSP_PROFILE" \
    CRUSH_MCP_PROFILE="$CRUSH_MCP_PROFILE" bash -l -s <<'INSTALL_EOF'
set -Eeuo pipefail
cd "$HOME"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
st() { printf '[STATUS] %s|crush package|%s\n' "$1" "$2"; }
install_brew() {
  local pkg="$1"
  if brew list --formula "${pkg##*/}" >/dev/null 2>&1; then
    st ok "$pkg already installed"
  elif brew install "$pkg"; then
    st ok "$pkg installed"
  else
    st warn "$pkg installation failed"
    return 1
  fi
}
if [[ "$CRUSH_INSTALL_BIN" == 1 ]]; then
  if ! install_brew charmbracelet/tap/crush; then
    echo "[STATUS] fail|crush package|Crush binary install failed" >&2
    exit 1
  fi
fi
if [[ "$CRUSH_MCP_PROFILE" != none ]]; then
  command -v node >/dev/null 2>&1 || install_brew node || st warn "Node unavailable"
fi
if [[ "$CRUSH_MCP_PROFILE" == extended ]]; then install_brew uv || st warn "uv unavailable"; fi
for language in $CRUSH_LSP_PROFILE; do
  case "$language" in
    python) install_brew ruff || st warn "Ruff unavailable" ;;
    go) install_brew gopls || st warn "gopls unavailable" ;;
    rust) install_brew rust-analyzer || st warn "rust-analyzer unavailable" ;;
    web) command -v npm >/dev/null 2>&1 || install_brew node || st warn "npm unavailable" ;;
  esac
done
if command -v npm >/dev/null 2>&1; then
  for language in $CRUSH_LSP_PROFILE; do
    case "$language" in
      web)
        npm install -g @vtsls/language-server @biomejs/biome || st warn "web LSPs unavailable" ;;
      python)
        npm install -g basedpyright || st warn "basedpyright unavailable" ;;
    esac
  done
fi
INSTALL_EOF
fi

deploy_user() {
  local user="$1" home group dir managed target existing name
  home="$(getent passwd "$user" | cut -d: -f6)"
  group="$(id -gn "$user")"
  [[ -d "$home" ]] || { status fail "user" "$user missing home"; return 1; }
  dir="$home/.config/crush"
  install -d -m 700 -o "$user" -g "$group" "$home/.config" \
    "$dir" "$dir/vpssetup.d" "$dir/vpssetup.d/lsp" \
    "$dir/commands" "$dir/templates"

  for name in providers.crushrc core.crushrc extended.crushrc; do
    install -m 600 -o "$user" -g "$group" "$stage/$name" "$dir/vpssetup.d/$name"
  done
  for name in web python go rust; do
    install -m 600 -o "$user" -g "$group" "$stage/lsp/$name.crushrc" "$dir/vpssetup.d/lsp/$name.crushrc"
  done
  for name in frontend deploy; do
    install -m 600 -o "$user" -g "$group" "$stage/templates/$name.crushrc" "$dir/templates/$name.crushrc"
  done
  for name in plan ship review debug scaffold; do
    target="$dir/commands/$name.md"
    if [[ -e "$target" && "$CRUSH_OVERWRITE_COMMANDS" != 1 ]]; then
      status ok "command" "$user/$name preserved"
    else
      install -m 600 -o "$user" -g "$group" "$stage/commands/$name.md" "$target"
    fi
  done

  # Only overwrite VPSsetup-owned files. Preserve operator's existing crushrc.
  managed="$dir/vpssetup-managed.crushrc"
  {
    echo "# VPSsetup managed config; edit your crushrc for local overrides."
    printf '%s\n' 'source "$HOME/.config/crush/vpssetup.d/providers.crushrc"'
    if [[ "$CRUSH_MCP_PROFILE" != none ]]; then
      printf '%s\n' 'source "$HOME/.config/crush/vpssetup.d/core.crushrc"'
    fi
    if [[ "$CRUSH_MCP_PROFILE" == extended ]]; then
      printf '%s\n' 'source "$HOME/.config/crush/vpssetup.d/extended.crushrc"'
    fi
    for name in "${lsp_profiles[@]}"; do
      printf 'source "$HOME/.config/crush/vpssetup.d/lsp/%s.crushrc"\n' "$name"
    done
  } > "$stage/managed.crushrc"
  bash -n "$stage/managed.crushrc"
  install -m 600 -o "$user" -g "$group" "$stage/managed.crushrc" "$managed"
  target="$dir/crushrc"
  if [[ ! -f "$target" ]]; then
    printf '%s\n' '#!/usr/bin/env bash' 'source "$HOME/.config/crush/vpssetup-managed.crushrc"' > "$target"
    chown "$user:$group" "$target"
    chmod 600 "$target"
  elif ! grep -qF 'vpssetup-managed.crushrc' "$target"; then
    # Put VPSsetup defaults BEFORE existing custom configuration so local
    # provider/model/permission choices retain priority on every re-run.
    local temp_original
    temp_original="$(mktemp)"
    {
      if [[ "$(head -n 1 "$target")" == '#!'* ]]; then
        head -n 1 "$target"
        printf '%s\n' 'source "$HOME/.config/crush/vpssetup-managed.crushrc"'
        tail -n +2 "$target"
      else
        printf '%s\n' 'source "$HOME/.config/crush/vpssetup-managed.crushrc"'
        cat "$target"
      fi
    } > "$temp_original"
    install -m 600 -o "$user" -g "$group" "$temp_original" "$target"
    rm -f "$temp_original"
    status ok "config" "$user existing crushrc preserved; overrides load last"
  fi
  status ok "user" "$user crushrc + scoped profiles installed"
}

deploy_user "$VPS_USER"
if [[ "$CRUSH_INSTALL_ROOT" == 1 ]]; then
  deploy_user root
else
  status ok "root" "not configured (explicit opt-in)"
fi

echo "=== Crush config ready ==="
echo "Run as $VPS_USER: crush (choose authenticated model in model picker)"
echo "API keys belong in your user environment or secret manager, never user-data."
echo "Model choices depend on API account access. See README_VibecodeCrush.md."
