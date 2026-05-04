
# VPS Bootstrap & Hardening System for Ubuntu 24.04

A complete, idempotent provisioning system designed for Hetzner (and any cloud-init compatible provider). It splits into:

- **`vps-init.sh`** — one-shot wizard that writes the config and both worker scripts, then runs them. Provider-agnostic, works without cloud-init.
- **`vps-bootstrap.sh`** — user, hostname, SSH keys, Homebrew, base tooling
- **`vps-harden.sh`** — SSH hardening, UFW, fail2ban, unattended-upgrades, sysctl, Tailscale
- **`vps-tools.sh`** *(optional)* — AI/CLI tools (opencode, crush, codex, claude-code, ollama, lazygit, etc.)
- **`VerifyChecklist.sh`** — post-deploy audit (sshd config, authorized_keys, UFW, fail2ban, Tailscale, brew, listening ports)
- **`/etc/vps/bootstrap.env`** — single source of truth for all scripts

Layout:

```
/etc/vps/bootstrap.env             # configuration (sourced by all scripts)
/usr/local/sbin/vps-bootstrap.sh
/usr/local/sbin/vps-harden.sh
/usr/local/sbin/vps-tools.sh
/var/log/vps-bootstrap.log
```

---



## Resolved Design Decisions

These are points worth being explicit about:

- **Node.js:** install via Homebrew (`node` formula). Brew gives one consistent install path across all VPSs. The `nvm` route is left as an opt-in (`INSTALL_NODE_LTS=1`) for projects that need to pin specific Node versions per-project.
- **Mirror keys to root:** yes, during bootstrap, as a transitional safety net. Append+dedupe (not overwrite) so re-runs preserve any keys the cloud provider seeded or that you added by hand. The hardening script then enforces `PermitRootLogin prohibit-password` (no passwords, key-only) so root SSH remains a recovery hatch rather than a routine login path.
- **Ubuntu 24.04 `ssh.socket`:** explicitly disable it. Without this, `sshd_config.d/*.conf` drop-ins frequently fail to apply on first restart on Noble.
- **`reload`, not `restart`, for sshd config changes.** SIGHUP makes sshd re-read config in place; existing sessions survive, only new connections see the new config. Lets you open a verification SSH session before logging out of the script-running session — the canonical "configure-without-locking-yourself-out" pattern.
- **sshd drop-in rollback.** Snapshot `99-vps-hardening.conf` to `*.bak` before writing the new one; `sshd -t` validates; on failure restore the backup (or remove ours if there was no prior). A broken drop-in is never left in place.
- **Pre-flight key check before tightening sshd.** Verify *at least one* of `<user>`'s or `root`'s `authorized_keys` is non-empty before disabling password auth. Warn (don't abort) on empty root keys when `PermitRootLogin` is permissive — the operator should know root key login won't work.
- **Current-session-aware AllowUsers warning.** When `vps-harden.sh` runs inside an SSH session, it checks `$SSH_CONNECTION` and warns if the new `AllowUsers` list would exclude the current user; the operator is told explicitly to open a new shell as `<user>` (or root) before logging out.
- **Brew CWD requirement.** Every `sudo -Hu <user> bash` block that touches brew must `cd "$HOME"` first. `sudo -Hu` (without `-i`) inherits the parent CWD, typically `/root`, which the unprivileged user can't read — brew refuses to start with the "current working directory must be readable" error and the eval of `brew shellenv` returns nothing, silently breaking the rest of the script.
- **`brew shellenv bash`** instead of bare `brew shellenv`. Matches what Homebrew's installer prints and removes shell-detection ambiguity in non-interactive contexts (cron, systemd User=, scripts).
- **Tailscale auth key:** scrub from `/etc/vps/bootstrap.env` after a successful join; cloud-init `user-data` is also persisted on disk in `/var/lib/cloud/instances/*/user-data.txt`, so you should additionally use **ephemeral, tagged, time-limited** auth keys (`tskey-auth-...`) issued per-environment.
- **Public SSH lockdown:** automated via `PUBLIC_SSH_ALLOWED=0` on a second run, gated on Tailscale actually being up *and* the `tailscale0 … ALLOW` rule being visible in `ufw status` before the public rule is removed — never blindly during first boot.
- **Hostname generation:** prefer Hetzner metadata `instance-id` when available (deterministic, traceable), fall back to `/etc/machine-id`, then to random bytes. Format: `<prefix>-<role>-<id>` so role is encoded in the device name.
- **Username collision:** explicitly refuse `root`, `linuxbrew`, or any existing system user with UID < 1000 to avoid clobbering the Linuxbrew install user.
- **AI tooling installer paths:** brew taps where they exist (`opencode`, `crush`); `npm i -g @openai/codex` for Codex (no Linux brew formula); `claude.ai/install.sh` for Claude Code (no Linux cask). Failed installs `|| true` through so one broken upstream doesn't fail the whole tools run.

---

## Open Considerations / Things Worth Adding Per Environment

These are deliberately *not* automated in the scripts above because they require per-deployment policy decisions:

- **Secret injection.** Anything you put in cloud-init `user-data` lands on disk (`/var/lib/cloud/instances/*/user-data.txt`). For real secrets (Anthropic/OpenAI/OpenRouter API keys, long-lived Tailscale keys, registry credentials), use **SOPS + age**, **HashiCorp Vault**, **Doppler**, or **Infisical**. A common pattern: use cloud-init to install only a short-lived bootstrap token, then have the VPS pull the rest from your secret store via Tailscale ACLs.
- **AI tool API keys.** `vps-tools.sh` deliberately doesn't write `~/.config/tmuxai/config.yaml`, `~/.config/opencode/config.json`, etc. Drop secrets into `/etc/vps/secrets.env`, mode 0600, and source it from the user's `.profile` so each tool reads `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, etc. from environment.
- **Re-running on long-lived VPSs.** The scripts are idempotent, but for fleets, prefer pinning to a script version (`?ref=v1.2.0` on the GitHub raw URL) and tracking which version is installed (`/etc/vps/version`). For drift detection consider a tiny periodic systemd timer that re-runs the bootstrap and reports a diff.
- **First-boot systemd unit.** If you don't want cloud-init, a `/etc/systemd/system/vps-firstboot.service` with `ConditionPathExists=!/var/lib/vps/bootstrapped` running `vps-bootstrap.sh && vps-harden.sh && touch /var/lib/vps/bootstrapped` is the equivalent.
- **IPv6.** SSH and UFW handle IPv6 by default. If you don't need it, set `DISABLE_IPV6=1` and `DISABLE_IPV6_SSH=1`. Otherwise verify `ufw status` shows v6 rules, and that your tailnet has IPv6 enabled if you want dual-stack across the mesh.
- **Backups / snapshots.** Hetzner's automated snapshots are cheap; enable them per-server via the API. For application data, set up `restic` or `borg` to a Backblaze B2 / S3 bucket from `vps-tools.sh`. Not included by default because retention/policy varies wildly.
- **Monitoring / observability.** For a staging+production fleet, install `node_exporter` (Prometheus), or a unified agent like `vector`, `grafana-agent`, or `netdata`. Recommended pattern: the agent listens only on `tailscale0` and your Prometheus/Loki scrapes via Tailscale, with no public exposure.
- **GitOps for staging vs prod.** Maintain `bootstrap.staging.env` and `bootstrap.production.env` in your config repo; cloud-init picks the right one via the `VPS_ROLE` variable. Gate production auth keys (Tailscale, registries) behind a separate SOPS recipient so accidental staging deploys cannot pull production secrets.
- **Disaster recovery.** Keep the scripts plus the `bootstrap.env` (with secrets stripped) in version control so any VPS can be reproduced from scratch by running cloud-init against a fresh image.

---
