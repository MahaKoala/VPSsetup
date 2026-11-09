# 🛡️ VPS AnchorGarden

> **Security initiative · Independent checks · Fail safely**
>
> Goal: translate verified Linux/security advisories (including AI-assisted discoveries) into repeatable VPS exposure checks, minimal hardening improvements, and recovery-tested documentation.

[Repository root](../../README.md) · [Initial finding: CVE-2026-123158](CVE-2026-123158.md) · [Audit worker](../../vps-anchor.sh)

## Operating principles

| Principle | Implementation |
|:---|:---|
| **Protect first** | Read-only inventory and policy checks before changing SSH or firewalls |
| **Verify the threat model** | Distinguish glibc from musl, PAM from non-PAM, and actual SSH settings from package banner guesses |
| **No exploit execution** | Do not run public proof-of-concept code or brute-force SSH |
| **No surprise changes** | Never start this initiative from cloud-init or the standard `vps-init.sh` without explicit opt-in |
| **Provider neutrality** | Optional worker runs independently, without depending on previous cloud-init |
| **Key-only public SSH** | Public port 22 may remain open; password and keyboard-interactive authentication must be disabled |
| **Evidence-based release gates** | Cite vendor fixes, test expected behavior, retain rollback and SSH console recovery |
| **Credentials stay private** | No shadow hash output, API keys, ssh private keys or raw chat transcripts in repo or logs |

## 1. First assessment — *SSHole

**CVE-2026-123158** — musl libc + OpenSSH without PAM + password authentication enabled, under specific account conditions.

The incident was disclosed November 5, 2026. It is not an exploit that requires AI; OpenSSH's release notes explain why AI-assisted vulnerability discovery is accelerating its security release cadence.

**Why your Ubuntu VPS configuration is lower risk:** Ubuntu's standard OpenSSH uses glibc/PAM and VPSsetup already defaults to `PasswordAuthentication no`. Do not infer host safety solely from a version banner: distributions backport security fixes.

### Run the read-only audit

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/VPS-AnchorGarden/vps-anchor.sh \
  -o /tmp/vps-anchor.sh
bash -n /tmp/vps-anchor.sh
sudo bash /tmp/vps-anchor.sh
```

Or from a checked-out repository: `sudo bash vps-anchor.sh`. Requires root to read local account metadata; it does not print passwords/hashes or change configuration.

| Exit | Label | Interpretation |
|---:|---|---|
| 0 | PASS | No identified issue among supported checks |
| 1 | REVIEW | Unverified setting, Match block, or vendor patch status needs manual review |
| 2 | HIGH | Password policy violation or potential matching exposure condition |
| 3 | INCOMPLETE | Unable to assess local OpenSSH configuration |

Audits are **not vulnerability exploitation tests** and do not certify the absence of compromise.

## 2. Accepted hardening policy

- Preserve conventional OpenSSH access for any existing Linux user with a valid authorized public key.
- Disable `PasswordAuthentication`, `KbdInteractiveAuthentication`, and `PermitEmptyPasswords`.
- Keep `PubkeyAuthentication yes`; root may use keys only under `PermitRootLogin prohibit-password`, or be disabled separately.
- Keep Tailscale SSH optional, distinct from the conventional SSH key check.
- Maintain a live root/provider console during SSH policy updates and independently verify a new SSH session.
- Never turn off public SSH or restrict user identities as an undocumented consequence of AnchorGarden checks.

`vps-harden.sh` already writes the above SSH settings. The AnchorGarden branch strengthens its **effective-configuration verification** before reload; it does not modify a running server until an operator explicitly runs the hardening worker.

## 3. Next assessment themes

Future advisories should be assessed separately before implementation: OpenSSH releases/backports, kernel local privilege escalation, container/runtime exposure, build and package supply chains, CI/CD token boundaries, agent/MCP tool permissions, and SSH login telemetry. Include an official advisory, affected configurations, safe detection, remediation, false-positive notes, regression tests, and rollback for each.

## Review checklist / acceptance criteria

- [x] New isolated branch `VPS-AnchorGarden` based on current main
- [x] Read-only first check for CVE-2026-123158 and public SSH key-only policy
- [x] Independent worker, no cloud-init or automated install changes
- [x] Validate keyboard-interactive and empty-password policy before SSH reload
- [x] Mocked positive/negative checks and CI integration
- [ ] Smoke test on disposable Ubuntu and Alpine hosts
- [ ] Verify patched Alpine package inventory and manual SSH reload behavior on a non-production system
- [ ] After review, create a PR and approve any merge/deployment explicitly

## References

- [OpenSSH 10.6p2 release notes](https://www.openssh.org/txt/release-10.6p2)
- [Alpine security advisory](https://alpinelinux.org/posts/2026-11-05-openssh-password-authentication-bypass/)
- [CVE-2026-123158 (NVD)](https://nvd.nist.gov/vuln/detail/CVE-2026-123158)
- [Ubuntu CVE tracker](https://ubuntu.com/security/CVE-2026-123158)
