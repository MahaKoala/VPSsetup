#!/usr/bin/env bash
# AnchorGarden: read-only security assessment for a Linux VPS.
# Initial check: CVE-2026-123158 (*SSHole) + SSH key-only policy.
# Never attempts authentication, modifies sshd_config, or restarts services.
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: sudo bash vps-anchor.sh [--help]
Read-only local checks for CVE-2026-123158 (*SSHole) and SSH key-only policy.
Exit codes: 0 = no findings; 1 = warning/manual review; 2 = high-risk finding;
            3 = audit unavailable/incomplete (e.g. sshd missing).
This script does not patch, restart, scan remotely, or exploit a host.
USAGE
}

case "${1:-}" in
  "" ) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 3 ;;
esac
if (( EUID != 0 )); then
  echo "ERROR: Audit requires root to read account metadata. No changes are made." >&2
  exit 3
fi

severity=0
report() {
  local level="$1" message="$2"
  printf '[%-6s] %s\n' "$level" "$message"
  case "$level" in
    HIGH) severity=2 ;;
    WARN) (( severity < 1 )) && severity=1 ;;
  esac
  return 0
}
value() {
  local key="$1"
  awk -v key="$key" '$1 == key {print $2; exit}' <<< "$sshd_config"
}

echo "== VPS AnchorGarden / CVE-2026-123158 =="
echo "Read-only local assessment (no login attempts or configuration changes)"
if [[ -r /etc/os-release ]]; then
  # /etc/os-release belongs to the local OS installation.
  # shellcheck source=/dev/null
  source /etc/os-release
  printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
else
  report WARN "Cannot read /etc/os-release; distribution unknown."
fi

libc="unknown"
if command -v getconf >/dev/null 2>&1 &&
   getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
  libc="glibc"
elif compgen -G '/lib/ld-musl-*.so*' >/dev/null ||
     compgen -G '/usr/lib/ld-musl-*.so*' >/dev/null; then
  libc="musl"
fi
printf 'C library: %s\n' "$libc"

sshd_bin="$(command -v sshd || true)"
[[ -n "$sshd_bin" ]] || [[ ! -x /usr/sbin/sshd ]] || sshd_bin=/usr/sbin/sshd
if [[ -z "$sshd_bin" ]]; then
  report WARN "No OpenSSH sshd binary found; check other SSH servers separately."
  printf 'ANCHORGARDEN_RESULT=INCOMPLETE\n'
  exit 3
fi
sshd_version="$("$sshd_bin" -V 2>&1 || true)"
printf 'OpenSSH: %s\n' "${sshd_version%%$'\n'*}"
if ! sshd_config="$("$sshd_bin" -T 2>&1)"; then
  report HIGH "Cannot evaluate sshd -T; inspect sshd configuration/host keys."
  printf 'ANCHORGARDEN_RESULT=INCOMPLETE\n'
  exit 3
fi

password_auth="$(value passwordauthentication)"
kbd_auth="$(value kbdinteractiveauthentication)"
pubkey_auth="$(value pubkeyauthentication)"
usepam="$(value usepam)"
root_auth="$(value permitrootlogin)"
printf 'Effective OpenSSH: PasswordAuthentication=%s, KbdInteractiveAuthentication=%s, PubkeyAuthentication=%s, UsePAM=%s, PermitRootLogin=%s\n' \
  "${password_auth:-unknown}" "${kbd_auth:-unknown}" \
  "${pubkey_auth:-unknown}" "${usepam:-unknown}" "${root_auth:-unknown}"

# User policy: public port 22 is acceptable, but password authentication is not.
if [[ "$password_auth" == no ]]; then
  report PASS "PasswordAuthentication no blocks the *SSHole password bypass."
else
  report HIGH "SSH password authentication is not disabled: value=${password_auth:-unknown}."
fi
if [[ "$kbd_auth" == no ]]; then
  report PASS "Keyboard-interactive authentication is disabled."
else
  report WARN "Keyboard-interactive authentication is not disabled: value=${kbd_auth:-unknown}."
fi
if [[ "$pubkey_auth" == yes ]]; then
  report PASS "SSH public-key authentication is enabled."
else
  report HIGH "SSH public-key authentication is not enabled."
fi
case "$root_auth" in
  prohibit-password|without-password|no|forced-commands-only)
    report PASS "Root password login is restricted (${root_auth})." ;;
  *)
    report HIGH "Root SSH password login may be allowed (${root_auth:-unknown})." ;;
esac

if [[ "$libc" == glibc ]]; then
  report PASS "glibc is not the musl-specific environment for CVE-2026-123158."
elif [[ "$libc" == musl ]]; then
  report WARN "musl detected; check OpenSSH and Alpine/vendor security patches."
else
  report WARN "Unable to identify libc; assess musl/PAM exposure manually."
fi

if [[ "$libc" == musl && "$usepam" != yes && "$password_auth" != no ]]; then
  # Count account metadata only; never print password hashes or shadow entries.
  if [[ -r /etc/shadow ]]; then
    counts="$(awk -F: '
      $2 == "*" { stars++ }
      $2 ~ /^\$[56]\$/ { salted++ }
      END { printf "%d %d", stars+0, salted+0 }
    ' /etc/shadow)"
    read -r star_accounts salted_accounts <<< "$counts"
    if (( star_accounts > 0 && salted_accounts > 0 )); then
      report HIGH "Potential *SSHole prerequisite combination: musl, no PAM, password auth, '*' account(s), and SHA-crypt hashes. Patch and investigate immediately; account accessibility and patch status require confirmation."
    else
      report WARN "No matching local shadow combination detected; external identity sources and vendor patch status still need review."
    fi
  else
    report WARN "/etc/shadow unreadable; cannot evaluate affected account conditions."
  fi
fi

# Match blocks may override global sshd -T settings for particular users/hosts.
for config in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [[ -f "$config" ]] || continue
  if grep -Eiq '^[[:space:]]*Match[[:space:]]+' "$config"; then
    report WARN "A Match directive exists in OpenSSH config; verify per-user/source conditions with sshd -T -C."
    break
  fi
done

echo "Reference: https://alpinelinux.org/posts/2026-11-05-openssh-password-authentication-bypass/"
case "$severity" in
  0) printf 'ANCHORGARDEN_RESULT=PASS\n' ;;
  1) printf 'ANCHORGARDEN_RESULT=REVIEW\n' ;;
  2) printf 'ANCHORGARDEN_RESULT=HIGH\n' ;;
esac
exit "$severity"
