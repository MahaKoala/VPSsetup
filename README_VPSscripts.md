# VPSsetup scripts and architecture

**One pipeline, three entry points** for Ubuntu 24.04 and compatible Debian-family VPS hosts.

| Entry point | Purpose |
|---|---|
| [`cloud-init.yaml`](cloud-init.yaml) | Provider cloud user-data, writes `bootstrap.env` then calls the common installer |
| [`vps-init.sh`](vps-init.sh) | One-line interactive/noninteractive installer on any provider with shell/network access |
| [`firstrun.sh`](firstrun.sh) | Thin compatibility launcher for `vps-init.sh` |

Both cloud-init and one-line installation download the **same standalone worker files**, rather than embedding parallel copies of their implementations.

## Independent workers

```bash
sudo /usr/local/sbin/vps-swap.sh
sudo /usr/local/sbin/vps-bootstrap.sh
sudo /usr/local/sbin/vps-harden.sh
sudo /usr/local/sbin/vps-tools.sh             # full legacy AI suite; optional
sudo /usr/local/sbin/vps-vibecode-crush.sh   # standalone Crush setup; optional
sudo /usr/local/sbin/VerifyChecklist.sh
```

| Worker | Responsibility |
|---|---|
| `vps-swap.sh` | 50% of detected RAM by default; bounded, disk-space-aware, preserves existing swap |
| `vps-bootstrap.sh` | Installs base packages, creates configurable user, fetches and validates keys, optional Homebrew |
| `vps-harden.sh` | Enforces effective OpenSSH configuration, manages project UFW rules without resetting unrelated ones, Fail2Ban, updates, sysctl, Tailscale |
| `vps-tools.sh` | Optional complete AI/dev suite; use `INSTALL_TOOLS=1` |
| `vps-vibecode-crush.sh` | Optional Crush provider profiles, MCP/LSP setup, and slash commands; `INSTALL_VIBECODE_CRUSH=1` |
| `VerifyChecklist.sh` | Validates keys, SSH, password policy, swap, UFW, services, Tailscale and optional tooling |

Each worker reads the saved `/etc/vps/bootstrap.env`, and **none requires cloud-init**. For use on a completely fresh provider, generate/edit this config and download the necessary worker, or use the one-liner to do it.

## Configuration and defaults

All defaults are defined in [`bootstrap.env`](bootstrap.env). Particularly important:

- `VPS_USER` and `VPS_HOSTNAME` set user and optional explicit FQDN.
- `SSH_ID` + `SSH_ID_TYPED_KEYS="RSA ECDSA-SK"` select validated public-key sources; `SSH_GH_USER` and `SSH_AUTHORIZED_KEYS` are alternatives.
- `FIRST_LOGIN_PASSWORD_PROMPT=0` means a **new** admin has no preset password and no first-login prompt. Password auth over SSH is disabled separately.
- `SWAP_MODE=auto`, `SWAP_PERCENT=50`, `SWAP_MIN_MB=512`, `SWAP_MAX_MB=4096` and disk reserve control swap on any RAM size.
- `INSTALL_BREW=0`, `INSTALL_TOOLS=0`, `INSTALL_VIBECODE_CRUSH=0`: optional AI tool installations are opt-in.
- `CRUSH_MCP_PROFILE=core` and `CRUSH_LSP_PROFILE=web,python`: configure lightweight Crush MCP/LSP profiles only when the Crush worker is explicitly called.
- `PUBLIC_SSH_ALLOWED=1` preserves public SSH during initial setup. To close it after verifying a **new** SSH session over Tailscale, also set `TAILNET_SSH_VERIFIED=1`.
- `VPS_SETUP_REF` selects the revision to download; prefer a known release/tag/SHA for production.
- `TAILSCALE_AUTHKEY` may be blank; joining the tailnet and authorizing Tailscale SSH are separate operations.

## Key design constraints

1. **No lockout:** Register a recovery public key in the cloud provider, keep the root console open, and verify a second working user SSH connection before disabling public SSH. `vps-harden.sh` validates its OpenSSH effective settings with `sshd -T` before reloading.
2. **No blind UFW reset:** Re-runs preserve application-specific allow/deny rules. Project public SSH rules are managed according to the config; the tailnet-only transition is explicitly gated.
3. **No duplicate embedded workers:** Changes to SSH, swap or hardening belong in their respective worker files, not copy-pasted into cloud-init or the main installer.
4. **Script reruns:** Workers are designed to preserve existing authorized keys, swap and configuration. They can reapply managed settings; test before production.
5. **Secrets:** Cloud-init user-data is persisted in `/var/lib/cloud`. Do not commit or paste persistent auth keys, private keys, API tokens, or registry credentials.
6. **Tailscale permissions:** [`tailscale.json`](tailscale.json) is an *example*. It requires a `tag:vps` device and network TCP/22 grant plus SSH authorization. It must be applied in the Tailscale admin console separately.

## Related guides

- [One-line installer](README_SingleFileVPSinit.md)
- [Modular Crush providers and profiles](README_VibecodeCrush.md)
- [Hetzner setup and recovery](docs/HETZNER.md)
- [SSHID helper scripts](README_SSHIDscript.md)
- [Password policy](README_FirstLoginPassword.md)
- [Troubleshooting](README_Troubleshooting.md)
