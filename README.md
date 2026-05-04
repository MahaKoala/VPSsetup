<div id="top">

<!-- HEADER STYLE: CLASSIC -->
<div align="center">


# VPSSETUP

<em>Secure, Simplify, Scale Your Server Infrastructure Effortlessly</em>

<!-- BADGES -->
<img src="https://img.shields.io/github/last-commit/MahaKoala/VPSsetup?style=flat&logo=git&logoColor=white&color=0080ff" alt="last-commit">
<img src="https://img.shields.io/github/languages/top/MahaKoala/VPSsetup?style=flat&color=0080ff" alt="repo-top-language">
<img src="https://img.shields.io/github/languages/count/MahaKoala/VPSsetup?style=flat&color=0080ff" alt="repo-language-count">

<em>Built with the tools and technologies:</em>

<img src="https://img.shields.io/badge/JSON-000000.svg?style=flat&logo=JSON&logoColor=white" alt="JSON">
<img src="https://img.shields.io/badge/Markdown-000000.svg?style=flat&logo=Markdown&logoColor=white" alt="Markdown">
<img src="https://img.shields.io/badge/GNU%20Bash-4EAA25.svg?style=flat&logo=GNU-Bash&logoColor=white" alt="GNU%20Bash">
<img src="https://img.shields.io/badge/YAML-CB171E.svg?style=flat&logo=YAML&logoColor=white" alt="YAML">

</div>
<br>

---

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
    - [Usage](#usage)
    - [Testing](#testing)
- [Features](#features)
- [Project Structure](#project-structure)
    - [Project Index](#project-index)

---

## Overview

VPSsetup is a comprehensive toolkit designed to automate the secure deployment and management of VPS instances, ensuring consistency and resilience across your infrastructure. The core features include:

- 🛡️ **Security Hardening:** Automates firewall rules, intrusion prevention, kernel tuning, and automatic updates to keep your servers secure.
- 🔑 **SSH Key Management:** Securely add and update SSH keys from sshid.io, simplifying user onboarding and access control.
- ⚙️ **Automated Initialization:** Supports idempotent setup scripts for quick, repeatable server provisioning across multiple providers.
- 🌐 **Network Integration:** Manages server tags and SSH permissions with Tailscale, ensuring organized and secure remote access.
- 🧰 **Tooling & Monitoring:** Installs essential development tools and performs health checks to maintain optimal server performance.

---

## Features

|      | Component          | Details                                                                                     |
| :--- | :----------------- | :------------------------------------------------------------------------------------------ |
| ⚙️  | **Architecture**   | <ul><li>Modular scripts for VPS setup automation</li><li>Uses cloud-init for initial provisioning</li></ul> |
| 🔩 | **Code Quality**   | <ul><li>Clear separation of concerns</li><li>Consistent naming conventions</li></ul>     |
| 📄 | **Documentation**  | <ul><li>README provides overview and usage instructions</li><li>Includes sample configs</li></ul> |
| 🔌 | **Integrations**    | <ul><li>Integrates with Tailscale via `tailscale.json`</li><li>Uses cloud-init YAML for cloud provisioning</li></ul> |
| 🧩 | **Modularity**      | <ul><li>Scripts organized into distinct files for setup, configuration, and cleanup</li></ul> |
| 🧪 | **Testing**         | <ul><li>No explicit testing framework detected; relies on manual validation</li></ul> |
| ⚡️  | **Performance**     | <ul><li>Lightweight scripts optimized for quick execution</li><li>Minimal dependencies reduce startup time</li></ul> |
| 🛡️ | **Security**        | <ul><li>Uses cloud-init for secure initial setup</li><li>Minimal external dependencies reduce attack surface</li></ul> |
| 📦 | **Dependencies**    | <ul><li>Python modules: `markdown`</li><li>Configuration files: `tailscale.json`, `shell` scripts, `cloud-init.yaml`</li></ul> |

---

## Project Structure

```sh
└── VPSsetup/
    ├── README.md
    ├── README_SSHIDscript.md
    ├── README_SingleFileVPSinit.md
    ├── README_VPSscripts.md
    ├── VerifyChecklist.sh
    ├── addnew-sshid-key.sh
    ├── addupdate-sshid-key.sh
    ├── bootstrap.env
    ├── cloud-init.yaml
    ├── firstrun.sh
    ├── tailscale.json
    ├── vps-bootstrap.sh
    ├── vps-harden.sh
    ├── vps-init.sh
    └── vps-tools.sh
```

---

### Project Index

<details open>
	<summary><b><code>VPSSETUP/</code></b></summary>
	<!-- __root__ Submodule -->
	<details>
		<summary><b>__root__</b></summary>
		<blockquote>
			<div class='directory-path' style='padding: 8px 0; color: #666;'>
				<code><b>⦿ __root__</b></code>
			<table style='width: 100%; border-collapse: collapse;'>
			<thead>
				<tr style='background-color: #f8f9fa;'>
					<th style='width: 30%; text-align: left; padding: 8px;'>File Name</th>
					<th style='text-align: left; padding: 8px;'>Summary</th>
				</tr>
			</thead>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-harden.sh'>vps-harden.sh</a></b></td>
					<td style='padding: 8px;'>- Provides automated hardening and security configuration for VPS instances by managing SSH access, firewall rules, intrusion prevention, automatic updates, system kernel settings, and optional Tailscale integration<br>- Ensures a secure, resilient, and manageable environment, aligning with best practices for server security and network connectivity within the overall infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/addnew-sshid-key.sh'>addnew-sshid-key.sh</a></b></td>
					<td style='padding: 8px;'>- Automates the secure addition of SSH public keys from sshid.io to specified user accounts, with optional user creation and sudo privileges<br>- Ensures idempotent key installation, manages user setup, permissions, and reloads SSH service as needed<br>- Facilitates streamlined, repeatable onboarding of SSH keys for secure, passwordless access across server environments.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README_SingleFileVPSinit.md'>README_SingleFileVPSinit.md</a></b></td>
					<td style='padding: 8px;'>- Provides a comprehensive, self-contained script to automate VPS initialization across various providers lacking cloud-init<br>- It streamlines setup by configuring user access, hostname, SSH keys, system hardening, and Tailscale integration, ensuring idempotent re-runs and secure handling of sensitive data<br>- Facilitates quick, consistent deployment and easy reconfiguration of VPS environments with minimal manual intervention.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/tailscale.json'>tailscale.json</a></b></td>
					<td style='padding: 8px;'>- Defines access control policies for managing server tags and SSH permissions within the infrastructure<br>- It specifies ownership of environment tags such as vps, staging, and production, and grants SSH access to designated users from administrative groups<br>- This configuration ensures secure, organized, and consistent management of server environments and remote access across the entire architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-tools.sh'>vps-tools.sh</a></b></td>
					<td style='padding: 8px;'>- Sets up AI and agent tooling on a VPS environment by installing essential development, terminal, and automation tools, and configuring system services<br>- Facilitates seamless integration of AI agents, code assistants, and productivity utilities, ensuring a ready-to-use infrastructure for AI-driven workflows and development automation within the broader system architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README_SSHIDscript.md'>README_SSHIDscript.md</a></b></td>
					<td style='padding: 8px;'>- Provides a secure, idempotent mechanism to manage SSH access by installing SSH keys and optionally creating and configuring users with sudo privileges<br>- Enhances overall system security and accessibility by automating user setup, key validation, and sudo configuration, ensuring consistent, safe, and repeatable SSH key deployment across the infrastructure.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README.md'>README.md</a></b></td>
					<td style='padding: 8px;'>- Provides an overview of the VPSsetup project, outlining its primary goal of automating the configuration and deployment of virtual private servers<br>- Facilitates streamlined server setup, ensuring consistent environments across deployments<br>- Serves as a foundational component within the broader infrastructure, enabling efficient management and scaling of server resources across various environments.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/cloud-init.yaml'>cloud-init.yaml</a></b></td>
					<td style='padding: 8px;'>- Automates the initial setup and hardening of cloud-based VPS instances across multiple providers by configuring system packages, security settings, and essential tools<br>- Ensures consistent, secure, and ready-to-use environments tailored for development or deployment roles, integrating custom environment variables and security enhancements to streamline provisioning within the overall infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/VerifyChecklist.sh'>VerifyChecklist.sh</a></b></td>
					<td style='padding: 8px;'>- VerifyChecklist.sh performs a comprehensive health and security audit of a server environment<br>- It verifies SSH access, system configuration, network status, firewall rules, security tools, and system updates, providing a consolidated overview of the server’s operational state<br>- This ensures the server remains secure, properly configured, and ready for production or further deployment within the overall infrastructure.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-bootstrap.sh'>vps-bootstrap.sh</a></b></td>
					<td style='padding: 8px;'>- Automates initial server setup on Ubuntu 24.04 by provisioning essential packages, configuring hostname, managing user accounts and SSH keys, and optionally installing development tools like Homebrew, Node.js, and Docker<br>- Ensures a secure, consistent environment ready for deployment or development, streamlining the first-boot process and establishing a solid foundation within the overall infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/vps-init.sh'>vps-init.sh</a></b></td>
					<td style='padding: 8px;'>- Vps-init.shThis script serves as a comprehensive, one-shot provisioning tool for Ubuntu 24.04 VPS instances across various cloud providers<br>- Its primary purpose is to automate the initial setup process, ensuring consistent and secure configuration of new virtual private servers<br>- Designed to be idempotent and safe to rerun, it streamlines the deployment workflow by handling essential system preparations, making it ideal for both manual and automated provisioning scenarios within the broader infrastructure architecture.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/firstrun.sh'>firstrun.sh</a></b></td>
					<td style='padding: 8px;'>- Facilitates manual VPS setup by automating environment configuration, security hardening, and initial provisioning without cloud-init<br>- Ensures consistent deployment through scripted steps that install necessary tools, apply security measures, and prepare the server for remote management via Tailscale<br>- Integrates seamlessly into the broader infrastructure to streamline initial server setup and hardening processes.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/addupdate-sshid-key.sh'>addupdate-sshid-key.sh</a></b></td>
					<td style='padding: 8px;'>- Facilitates secure, automated management of SSH access by fetching public keys from sshid.io and integrating them into user authorized_keys files<br>- Ensures idempotent updates, proper permissions, and optional SSH daemon reloads, supporting multiple key types<br>- Integrates seamlessly into deployment workflows to streamline user access provisioning across the infrastructure.</td>
				</tr>
				<tr style='border-bottom: 1px solid #eee;'>
					<td style='padding: 8px;'><b><a href='https://github.com/MahaKoala/VPSsetup/blob/master/README_VPSscripts.md'>README_VPSscripts.md</a></b></td>
					<td style='padding: 8px;'>- Provides a comprehensive, idempotent provisioning framework for Ubuntu 24.04 VPSs, enabling automated setup, security hardening, and optional tooling installation<br>- It streamlines initial deployment, enforces best practices for SSH, network, and system security, and supports environment-specific configurations, facilitating scalable, secure, and maintainable cloud infrastructure aligned with modern DevOps workflows.</td>
				</tr>
			</table>
		</blockquote>
	</details>
</details>

---


# VPS Bootstrap & Hardening System for Ubuntu 24.04

A complete, idempotent provisioning system designed for Hetzner (and any cloud-init compatible provider). It splits into:

- **`vps-bootstrap.sh`** — user, hostname, SSH keys, Homebrew, base tooling
- **`vps-harden.sh`** — SSH hardening, UFW, fail2ban, unattended-upgrades, sysctl, Tailscale
- **`vps-tools.sh`** *(optional)* — AI/CLI tools (opencode, crush, codex, claude-code, ollama, lazygit, etc.)
- **`/etc/vps/bootstrap.env`** — single source of truth for both scripts

Layout:

```
/etc/vps/bootstrap.env             # configuration (sourced by all scripts)
/usr/local/sbin/vps-bootstrap.sh
/usr/local/sbin/vps-harden.sh
/usr/local/sbin/vps-tools.sh
/var/log/vps-bootstrap.log
```

---

## Quickstart: Fresh VPS as root

Operator guide for a brand-new Ubuntu 24.04 VPS where you can SSH in as `root` (the default state on Hetzner, DigitalOcean, Vultr, Linode, Contabo, OVH, RackNerd, Scaleway, etc.).

### Before you begin

You will want these in hand:

- `<server-ip>` — IPv4 of the VPS (or DNS name)
- `root` SSH access — the temporary password the provider gave you, or a pre-installed root key
- An SSH key source for your real user, one or more of:
  - `sshid.io` ID (e.g. `mahakoala`) — keys fetched from `https://sshid.io/<id>`
  - GitHub username — keys fetched from `https://github.com/<u>.keys`
  - Raw `authorized_keys` content
- A Tailscale auth key *(strongly recommended)* — generate at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys). Make it **ephemeral**, **tagged** (e.g. `tag:vps`), and short-lived (1 hour is plenty)

### Path A — One-liner (recommended)

The `vps-init.sh` script is self-contained: it writes the config file and both worker scripts, runs them, and leaves everything on disk for re-runs.

**From your laptop, in one shot (interactive wizard):**

```bash
ssh -t root@<server-ip> "bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)"
```

The `-t` is important — it allocates a TTY so the wizard's prompts work over the SSH session. The wizard asks for username, SSH key sources, Tailscale key, and hardening choices, then prints a review screen before changing anything.

**Already SSH'd in as root?**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)
```

**Non-interactive (CI / agents / scripted fleet):**

```bash
ssh root@<server-ip> "curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | \
  VPS_USER=pink \
  SSH_ID=mahakoala \
  VPS_ROLE=staging \
  TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxx \
  TAILSCALE_TAGS=tag:vps,tag:staging \
  NONINTERACTIVE=1 bash"
```

All [bootstrap.env](bootstrap.env) variables can be passed this way. Anything you don't set falls back to the defaults baked into `vps-init.sh`.

### Path B — Manual / split files

If you'd rather see and edit each file before running, or if `bash <(curl …)` is blocked by your environment:

```bash
# 1. Pull the files (run as root on the VPS)
mkdir -p /etc/vps /usr/local/sbin
BASE=https://raw.githubusercontent.com/MahaKoala/VPSsetup/main
curl -fsSL $BASE/bootstrap.env    -o /etc/vps/bootstrap.env
curl -fsSL $BASE/vps-bootstrap.sh -o /usr/local/sbin/vps-bootstrap.sh
curl -fsSL $BASE/vps-harden.sh    -o /usr/local/sbin/vps-harden.sh
curl -fsSL $BASE/vps-tools.sh     -o /usr/local/sbin/vps-tools.sh   # optional
chmod 600 /etc/vps/bootstrap.env
chmod +x /usr/local/sbin/vps-bootstrap.sh /usr/local/sbin/vps-harden.sh /usr/local/sbin/vps-tools.sh

# 2. Edit the config — at minimum fill VPS_USER, SSH_ID/SSH_GH_USER, TAILSCALE_AUTHKEY
nano /etc/vps/bootstrap.env

# 3. Run, in order
/usr/local/sbin/vps-bootstrap.sh   # user, hostname, SSH keys, Homebrew, base tooling
/usr/local/sbin/vps-harden.sh      # SSH lockdown, UFW, fail2ban, sysctl, Tailscale
/usr/local/sbin/vps-tools.sh       # optional: AI/agent tooling (opencode, crush, codex, claude-code, ollama)
```

`firstrun.sh` is the same flow as a single copy-pasteable script — handy if your VPS console has no easy way to paste a multi-line block.

### Path C — Cloud-init providers (Hetzner / DO / Vultr / Linode)

Paste the contents of [cloud-init.yaml](cloud-init.yaml) into the provider's **User Data** / **Cloud Config** field at server creation time. Everything happens on first boot before you ever SSH in. Edit the inline `bootstrap.env` block in the YAML to set your `VPS_USER`, `SSH_ID`, `TAILSCALE_AUTHKEY`, etc.

### Verify the result

```bash
# As root or your new user:
bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh)
```

This prints hostname/OS, effective `sshd` config, per-user `authorized_keys` counts, UFW rules, fail2ban status, unattended-upgrades, Tailscale status, Homebrew sanity, and listening ports — one consolidated audit you can read top-to-bottom.

You should see, among other things:

- `Status: active` from UFW
- A `tailscale0` interface in `tailnet ALLOW Anywhere` rules
- `tailscale status` showing your tailnet peers
- `PermitRootLogin prohibit-password` (root SSH allowed by key only — recovery hatch)
- `AllowUsers <your-user> root` in `sshd -T`

### Connect with your real user

```bash
# Public (still allowed on first run):
ssh <your-user>@<server-ip>

# Tailnet (preferred — works even if public SSH is later locked down):
ssh <your-user>@<tailscale-hostname>
```

The host's tailnet hostname follows the pattern `<prefix>-<role>-<id>` (e.g. `deployeddigital-dev-abc12345`). Run `tailscale status` to see it.

### Lock SSH to the tailnet (second run, optional but recommended)

Once you've confirmed you can reach the VPS over Tailscale, eliminate the public SSH attack surface:

```bash
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

The harden script **refuses to run** if you set `PUBLIC_SSH_ALLOWED=0` while Tailscale isn't connected — it won't lock you out. After it succeeds, the `--- SSH access summary ---` block at the bottom shows the verified tailnet rule and confirms root key access is still available as the recovery hatch.

### Safety guarantees

The harden script has several layers of lockout protection. Worth knowing what each protects against:

- **`sshd reload`, not `restart`.** Config changes are applied via `systemctl reload ssh` (SIGHUP). Existing SSH sessions stay alive — only *new* connections see the tightened config. So you can run the harden script from your active SSH session, then open a *second* SSH window to verify the new config still lets you in *before* you log out of the first one. This is the canonical "configure-without-locking-yourself-out" pattern.
- **Pre-flight key check.** Before tightening anything, the script verifies that at least one of `/home/<user>/.ssh/authorized_keys` or `/root/.ssh/authorized_keys` is non-empty. If both are empty and password auth is being disabled → **abort** with a clear error.
- **Per-path warnings.** If `PermitRootLogin` allows root login but `/root/.ssh/authorized_keys` is empty → **warn** that the saved root key won't actually work. If `<user>` has no keys but root does → warn that only root SSH will work after hardening.
- **Current-session warning.** If the harden script is running inside an SSH session and the new `AllowUsers` list would exclude the user you're currently logged in as → **warn** explicitly: `Open a NEW shell as '<user>' (or root) BEFORE closing this session.`
- **Drop-in rollback on validation failure.** The script backs up the existing `99-vps-hardening.conf`, writes the new one, and runs `sshd -t`. If `sshd -t` rejects the new drop-in → restore the previous one (or remove ours if there was no prior version) and exit. A broken sshd config is never left in place.
- **UFW lockout gate.** `PUBLIC_SSH_ALLOWED=0` requires `tailscale status` to succeed before UFW is enabled (so you can't blindly enable a firewall with no SSH path to the box).
- **Tailnet rule verification.** When the lockdown removes the public SSH rule, it first checks `ufw status` for the `tailscale0 ... ALLOW` rule. If that rule isn't visible, the public rule is left in place.

Together: even if you misconfigure something, you keep the SSH session you're running the script *from*, plus the public path stays open until the tailnet path is verifiably alive.

### Re-running

Every step is idempotent:

```bash
sudo nano /etc/vps/bootstrap.env       # change anything — add a brew package, add a SSH key source, etc.
sudo /usr/local/sbin/vps-bootstrap.sh  # re-applies user/keys/brew
sudo /usr/local/sbin/vps-harden.sh     # re-applies firewall/SSH/tailscale config
```

Logs accumulate in `/var/log/vps-bootstrap.log`.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `bash: line 1: curl: command not found` | Older minimal image; run `apt-get update && apt-get install -y curl` first |
| `ERROR: PUBLIC_SSH_ALLOWED=0 but Tailscale is not connected` | First run with lockdown enabled — leave `PUBLIC_SSH_ALLOWED=1` until tailnet is verified |
| `ERROR: refusing to disable password auth — neither <user> nor /root/.ssh/authorized_keys has any keys` | No SSH key sources were resolved during bootstrap — re-run `vps-bootstrap.sh` with `SSH_ID` / `SSH_GH_USER` / `SSH_AUTHORIZED_KEYS` set, or add a key manually before re-running harden |
| `WARN: PermitRootLogin=… but /root/.ssh/authorized_keys is empty` | sshd allows root key login but no key is installed for root. Add the key your laptop uses to `/root/.ssh/authorized_keys` (or set `PERMIT_ROOT_LOGIN=no` and rely on `<user>` only) |
| `WARN: SSH'd in as '<x>' but new AllowUsers will be: <y>` | You're running the harden script as a user who won't be allowed in after reload. **Don't log out** — open a new SSH session as `<user>` (or root) first to verify access |
| `ERROR: sshd -t rejected new drop-in; rolling back` | Something invalidated `99-vps-hardening.conf` — typically a stray character in `SSH_PORT`/`PERMIT_ROOT_LOGIN`/`ALLOW_PASSWORD_AUTH`. The previous drop-in is restored automatically; fix the env file and re-run |
| `WARN: tailnet SSH rule not visible in 'ufw status'` | tailscaled didn't bring up `tailscale0`; check `journalctl -u tailscaled` and `tailscale status` |
| `Error: The current working directory must be readable to <user> to run brew.` | A sub-shell ran as the user from `/root` (which the user can't read). The current scripts always `cd "$HOME"` first; if you see this, you're running an old copy — re-pull `vps-bootstrap.sh` |
| `Refusing to use reserved username` | Your `VPS_USER` is `root` / `linuxbrew` / a UID < 1000 — pick a new one |
| `WARN: brew not found at /home/linuxbrew/.linuxbrew/bin/brew` | First Homebrew install failed; re-run `vps-bootstrap.sh` after fixing the underlying network/disk issue |

---


## Resolved Design Decisions

These are points worth being explicit about:

- **Node.js:** install via Homebrew (`node` formula). Brew gives one consistent install path across all VPSs. The `nvm` route is left as an opt-in (`INSTALL_NODE_LTS=1`) for projects that need to pin specific Node versions per-project.
- **Mirror keys to root:** yes, during bootstrap, as a transitional safety net. Append+dedupe (not overwrite) so re-runs preserve any keys the cloud provider seeded or that you added by hand. The hardening script then enforces `PermitRootLogin prohibit-password` (no passwords, key-only) so root SSH remains a recovery hatch rather than a routine login path.
- **Ubuntu 24.04 `ssh.socket`:** explicitly disable it. Without this, `sshd_config.d/*.conf` drop-ins frequently fail to apply on first restart on Noble.
- **`reload`, not `restart`, for sshd config changes.** SIGHUP makes sshd re-read config in place; existing sessions survive, only new connections see the new config. Lets you open a verification SSH session before logging out of the script-running session.
- **sshd drop-in rollback.** Snapshot `99-vps-hardening.conf` to `*.bak` before writing the new one; `sshd -t` validates; on failure restore the backup (or remove ours if there was no prior). A broken drop-in is never left in place.
- **Pre-flight key check before tightening sshd.** Verify *at least one* of `<user>`'s or `root`'s `authorized_keys` is non-empty before disabling password auth. Warn (don't abort) on empty root keys when `PermitRootLogin` is permissive — the operator should know root key login won't work.
- **Brew CWD requirement.** Every `sudo -Hu <user> bash` block that touches brew must `cd "$HOME"` first. `sudo -Hu` (without `-i`) inherits the parent CWD, typically `/root`, which the unprivileged user can't read — brew refuses to start with the "current working directory must be readable" error and the eval of `brew shellenv` returns nothing, breaking the rest of the script.
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

## Getting Started FOR DEVELOPING FURTHER

### Prerequisites

This project requires the following dependencies:

- **Programming Language:** Shell
- **Package Manager:** Bash

### Installation

Build VPSsetup from the source and install dependencies:

1. **Clone the repository:**

    ```sh
    ❯ git clone https://github.com/MahaKoala/VPSsetup
    ```

2. **Navigate to the project directory:**

    ```sh
    ❯ cd VPSsetup
    ```

3. **Install the dependencies:**

**Using [bash](https://www.gnu.org/software/bash/):**

```sh
❯ chmod +x {entrypoint}
```

### Usage

Run the project with:

**Using [bash](https://www.gnu.org/software/bash/):**

```sh
./{entrypoint}
```

### Testing

Vpssetup uses the {__test_framework__} test framework. Run the test suite with:

**Using [bash](https://www.gnu.org/software/bash/):**

```sh
bats *.bats
```

---

<div align="left"><a href="#top">⬆ Return</a></div>

---
