<div id="top"></div>

<div align="center">

# 🛡️ VPSSETUP

**Idempotent, opinionated, lockout-safe provisioning for Ubuntu 24.04 VPSs.**

*From bare root SSH to fully hardened, Tailscale-meshed, AI-tooled — in one command.*

<img src="https://img.shields.io/github/last-commit/MahaKoala/VPSsetup?style=flat&logo=git&logoColor=white&color=0080ff" alt="last-commit">
<img src="https://img.shields.io/badge/Ubuntu-24.04-E95420?style=flat&logo=ubuntu&logoColor=white" alt="Ubuntu 24.04">
<img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white" alt="Bash">
<img src="https://img.shields.io/badge/Tailscale-meshed-blueviolet?style=flat&logo=tailscale&logoColor=white" alt="Tailscale">
<img src="https://img.shields.io/badge/Idempotent-yes-success?style=flat" alt="Idempotent">

</div>

<br>

---

## 🗺️ At a glance

```mermaid
flowchart LR
    A[Bare VPS<br/>provider gives you root] --> B{Deploy method}
    B -->|cloud-init.yaml| C[Auto-runs on first boot]
    B -->|firstrun.sh| D[Manual paste as root]
    B -->|vps-init.sh| E[Interactive wizard]
    C --> F
    D --> F
    E --> F
    F["🧱 vps-bootstrap.sh<br/>user · SSH keys<br/>Homebrew · base tools"] --> G
    G["🔒 vps-harden.sh<br/>UFW · fail2ban<br/>SSH lockdown · Tailscale"] --> H
    H["🤖 vps-tools.sh<br/>Claude Code + statusline<br/>opencode · crush · ollama"] --> I
    I["✅ VerifyChecklist.sh<br/>SSH · UFW · Tailscale<br/>per-tool PATH audit"]
```

The three worker scripts run sequentially and idempotently. Each step is independently re-runnable, and the whole pipeline is designed so a misconfigured run still leaves you with a working SSH session.

---

## 📑 Table of Contents

- [Quickstart](#-quickstart)
  - [Path A — vps-init wizard (recommended)](#path-a--vps-init-wizard-recommended)
  - [Path B — Manual / split files](#path-b--manual--split-files)
  - [Path C — Cloud-init providers](#path-c--cloud-init-providers)
  - [End-of-install report](#end-of-install-report-path-a-only)
- [Verify the result](#-verify-the-result)
- [Connect with your real user](#-connect-with-your-real-user)
- [Lock SSH to the tailnet](#-lock-ssh-to-the-tailnet)
- [First-login password prompt](#-first-login-password-prompt)
- [Claude Code statusline](#-claude-code-statusline)
- [Safety guarantees](#-safety-guarantees)
- [Re-running & idempotency](#-re-running--idempotency)
- [Troubleshooting](#-troubleshooting)
- [Architecture & file layout](#-architecture--file-layout)
- [Resolved design decisions](#-resolved-design-decisions)
- [Per-environment considerations](#-per-environment-considerations)
- [Related documentation](#-related-documentation)
- [Contributing](#-contributing)

---

## 🚀 Quickstart

Operator guide for a brand-new Ubuntu 24.04 VPS where you can SSH in as `root` (the default state on Hetzner, DigitalOcean, Vultr, Linode, Contabo, OVH, RackNerd, Scaleway, etc.).

> 💡 **First-time installer?** Read [README_SampleExperience.md](README_SampleExperience.md) alongside this — it walks through every wizard prompt with the actual output you should see, so you know what's normal vs. what indicates a problem. Failure paths are catalogued in [README_Troubleshooting.md](README_Troubleshooting.md).

### Before you begin

You will want these in hand:

- `<server-ip>` — IPv4 of the VPS (or DNS name)
- `root` SSH access — the temporary password the provider gave you, or a pre-installed root key
- An SSH key source for your real user, one or more of:
  - `sshid.io` ID (e.g. `mahakoala`) — keys fetched from `https://sshid.io/<id>`
  - GitHub username — keys fetched from `https://github.com/<u>.keys`
  - Raw `authorized_keys` content
- A Tailscale auth key *(strongly recommended)* — generate at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys). Make it **ephemeral**, **tagged** (e.g. `tag:vps`), and short-lived (1 hour is plenty). The tag(s) you choose at key generation **must already exist** in `tagOwners` in your `tailscale.json` ACL — the script defaults to using those tags as-is and *not* overriding them with `--advertise-tags`, which is the safe path.

### Path A — vps-init wizard (recommended)

`vps-init.sh` is self-contained: it writes `bootstrap.env` plus all three worker scripts to `/usr/local/sbin/`, runs them in order, then prints an install report. Re-runnable.

**From your laptop, in one shot:**

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
  INSTALL_TOOLS=1 \
  RUN_VERIFY=1 \
  NONINTERACTIVE=1 bash"
```

| Var | Effect |
|---|---|
| `INSTALL_TOOLS=1` | Add the AI/agent tooling step (opencode, crush, codex, claude-code + statusline, ollama, lazygit, etc.). Default `0`. Interactive wizard prompts for it. |
| `RUN_VERIFY=1` | Run `VerifyChecklist.sh` at the end. Default off for non-interactive; interactive runs always prompt. |
| `TAILSCALE_TAGS=…` | Override the tags advertised on `tailscale up`. **Leave unset** to use whatever tags the auth key was generated with — overriding requires every tag be in `tagOwners` AND within the key's allowed set, which is the most common cause of silent join failures. |

All [bootstrap.env](bootstrap.env) variables can be passed this way. Anything you don't set falls back to the defaults baked into `vps-init.sh`. See [README_SingleFileVPSinit.md](README_SingleFileVPSinit.md) for the full env-var reference.

### Path B — Manual / split files

If you'd rather see and edit each file before running, or if `bash <(curl …)` is blocked by your environment:

```bash
# 1. Pull the files (run as root on the VPS)
mkdir -p /etc/vps /usr/local/sbin
BASE=https://raw.githubusercontent.com/MahaKoala/VPSsetup/main
curl -fsSL $BASE/bootstrap.env    -o /etc/vps/bootstrap.env
curl -fsSL $BASE/vps-bootstrap.sh -o /usr/local/sbin/vps-bootstrap.sh
curl -fsSL $BASE/vps-harden.sh    -o /usr/local/sbin/vps-harden.sh
curl -fsSL $BASE/vps-tools.sh     -o /usr/local/sbin/vps-tools.sh
chmod 600 /etc/vps/bootstrap.env
chmod +x /usr/local/sbin/vps-bootstrap.sh /usr/local/sbin/vps-harden.sh /usr/local/sbin/vps-tools.sh

# 2. Edit the config — at minimum fill VPS_USER, SSH_ID/SSH_GH_USER, TAILSCALE_AUTHKEY
nano /etc/vps/bootstrap.env

# 3. Run, in order
/usr/local/sbin/vps-bootstrap.sh   # user, hostname, SSH keys, Homebrew, base tooling
/usr/local/sbin/vps-harden.sh      # SSH lockdown, UFW, fail2ban, sysctl, Tailscale
/usr/local/sbin/vps-tools.sh       # Claude Code + statusline, AI/agent tooling
```

[`firstrun.sh`](firstrun.sh) is the same flow as a single copy-pasteable script — handy if your VPS console has no easy way to paste a multi-line block. As of the current revision it includes `vps-tools.sh` in the run order, so a fresh VPS via `firstrun.sh` ships fully tooled.

If you skipped `vps-tools.sh` and want to add AI tooling later (or refresh it), it's a stand-alone re-runnable step — pull the latest and run as root:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-tools.sh)

or as User:
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-tools.sh | sudo bash
```

It reads the existing `/etc/vps/bootstrap.env` to find `VPS_USER` and installs everything under that user's Homebrew. **Must be run as root** — the env file is mode 600 and the script aborts with a clear error if invoked as a regular user.

### Path C — Cloud-init providers

Paste the contents of [cloud-init.yaml](cloud-init.yaml) into the provider's **User Data** / **Cloud Config** field at server creation time. Everything happens on first boot before you ever SSH in. Edit the inline `bootstrap.env` block in the YAML to set your `VPS_USER`, `SSH_ID`, `TAILSCALE_AUTHKEY`, etc. The cloud-init flow runs all three scripts (`vps-bootstrap.sh`, `vps-harden.sh`, `vps-tools.sh`) in order — Claude Code and the custom statusline land turnkey.

### End-of-install report (Path A only)

After bootstrap → harden → tools, `vps-init.sh` parses `[STATUS]` lines from `/var/log/vps-bootstrap.log` and prints a tally:

```
── Install report ──
  ✓ ok:   24
  ! warn: 2
  ✗ fail: 1

Warnings:
  ! brew bun                         (install failed)
  ! tmuxai                           (installer failed)

Failures:
  ✗ tailscale up                     (exit 1)

How to retry individual items:
  brew package          → sudo -u maha bash -lc 'brew install <pkg>'
  npm package           → sudo -u maha bash -lc 'npm i -g <pkg>'
  claude-code           → sudo -u maha bash -lc 'curl -fsSL https://claude.ai/install.sh | bash'
  tailscale             → sudo tailscale up --auth-key=<new-key>
  full log              → less /var/log/vps-bootstrap.log
```

Each install step (per-package brew, per-tap, npm, curl-installers, tailscale up, etc.) emits one structured `[STATUS] <ok|warn|fail>|<step>|<detail>` line into the shared log. Path B and Path C don't print the report at the end (only `vps-init.sh` orchestrates) — but the structured log lines are still emitted, so you can run `VerifyChecklist.sh --report` later to read the same tally.

---

## ✅ Verify the result

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh)
```

`vps-init.sh` already prompts to run this at the end of every install (interactive runs); for non-interactive runs, opt in with `RUN_VERIFY=1`.

The verify script does a full audit: hostname/OS, disk space (warns under 2GB, fails under 500MB), effective `sshd -T` config (per-key validated, not just dumped), per-user `authorized_keys`, UFW status + SSH-path verification, fail2ban jail counts, unattended-upgrades, Tailscale connectivity (interface + peers + self IP), per-user Homebrew, and login-shell PATH resolution for `claude`, `eza`, `bat`, `gh`, `node`, etc. (catches the *"installed but not in PATH"* class of regression).

It tracks each check as **ok / warn / fail**, prints a 3-line tally + verdict, and **exits non-zero if any check failed** — so you can run it from cron or CI:

```
── Verify summary ──
  ✓ ok:   18
  ! warn: 2
  ✗ fail: 0

Result: PASS with warnings — review ! items, decide if action needed.
```

| Flag | Effect |
|---|---|
| `--quiet` / `-q` | Suppress `ok` lines and section headers; only print warnings, failures, summary. Cron-friendly |
| `--report` / `-r` | Print only the install `[STATUS]` tally from `/var/log/vps-bootstrap.log` and exit. Lets you re-check what failed during the original deploy weeks later |
| `--help` / `-h` | Usage |

You should see, among other things:

- `Status: active` from UFW
- A `tailscale0 ALLOW` rule in `ufw status`
- `tailscale status` showing your tailnet peers and a `tailscale0` IP on the interface
- `PermitRootLogin prohibit-password` (root SSH allowed by key only — recovery hatch)
- `AllowUsers <your-user> root` in `sshd -T`
- `Result: PASS` (or `PASS with warnings`)

---

## 🔌 Connect with your real user

```bash
# Public (still allowed on first run):
ssh <your-user>@<server-ip>

# Tailnet (preferred — works even if public SSH is later locked down):
ssh <your-user>@<tailscale-hostname>
```

The host's tailnet hostname follows the pattern `<prefix>-<role>-<id>` (e.g. `deployeddigital-dev-abc12345`). Run `tailscale status` to see it.

---

## 🔒 Lock SSH to the tailnet

Once you've confirmed you can reach the VPS over Tailscale, eliminate the public SSH attack surface:

```bash
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

The harden script **refuses to run** if you set `PUBLIC_SSH_ALLOWED=0` while Tailscale isn't connected — it won't lock you out. After it succeeds, the `--- SSH access summary ---` block at the bottom shows the verified tailnet rule and confirms root key access is still available as the recovery hatch.

---

## 🔑 First-login password prompt

When the bootstrap creates the primary user, `useradd -m` leaves the password locked. The first time anyone gets an interactive shell as that user — via `ssh`, `su user`, `su - user`, or a console login — a hook drops them into a `passwd` prompt automatically, then self-disables.

This closes the gap where the locked-password state plus `NOPASSWD` sudo means the user never has a password until they unexpectedly need one (sudo with `ENABLE_PASSWORDLESS_SUDO=0`, console rescue, switching to password-or-key auth, etc.).

The hook lives at `~/.firstlogin-passwd.sh`, is sourced by `~/.vps-shell.sh`, and writes `~/.password_set` once the user successfully sets a password (preventing the prompt on subsequent logins). Full design notes and customization options: **[README_FirstLoginPassword.md](README_FirstLoginPassword.md)**.

---

## 🤖 Claude Code statusline

`vps-tools.sh` installs Claude Code (Anthropic's CLI agent) and applies a custom statusline showing:

- Model name (color-coded by family)
- Current working directory (with `~` for `$HOME`)
- Git branch + dirty file count
- Context window usage
- 5-hour and 7-day Max-plan rate-limit windows with pace arrows and time-to-reset
- Prompt cache hit rate

The bundle ([`CustomConfigs/claude-statusline-export.tar.gz`](CustomConfigs/)) is fetched at install time and unpacked under `~/.claude/`. **Installed for both `root` and `$VPS_USER`** — since `claude` is symlinked to `/usr/local/bin/claude` either user can invoke it, and both get the same statusline. Re-runnable; settings are merged with `jq`, never blindly overwritten — any existing `settings.json` is backed up to `settings.json.bak.YYYYMMDD-HHMMSS` first.

See **[CustomConfigs/README.md](CustomConfigs/README.md)** for the full statusline spec, install-script behavior, and customization.

---

## 🛡️ Safety guarantees

The harden script has several layers of lockout protection. Worth knowing what each protects against:

- **`sshd reload`, not `restart`.** Config changes are applied via `systemctl reload ssh` (SIGHUP). Existing SSH sessions stay alive — only *new* connections see the tightened config. So you can run the harden script from your active SSH session, then open a *second* SSH window to verify the new config still lets you in *before* you log out of the first one. This is the canonical "configure-without-locking-yourself-out" pattern.
- **Pre-flight key check.** Before tightening anything, the script verifies that at least one of `/home/<user>/.ssh/authorized_keys` or `/root/.ssh/authorized_keys` is non-empty. If both are empty and password auth is being disabled → **abort** with a clear error.
- **Per-path warnings.** If `PermitRootLogin` allows root login but `/root/.ssh/authorized_keys` is empty → **warn** that the saved root key won't actually work. If `<user>` has no keys but root does → warn that only root SSH will work after hardening.
- **Current-session warning.** If the harden script is running inside an SSH session and the new `AllowUsers` list would exclude the user you're currently logged in as → **warn** explicitly: `Open a NEW shell as '<user>' (or root) BEFORE closing this session.`
- **Drop-in rollback on validation failure.** The script backs up the existing `99-vps-hardening.conf`, writes the new one, and runs `sshd -t`. If `sshd -t` rejects the new drop-in → restore the previous one (or remove ours if there was no prior version) and exit. A broken sshd config is never left in place.
- **UFW lockout gate.** `PUBLIC_SSH_ALLOWED=0` requires `tailscale status` to succeed before UFW is enabled (so you can't blindly enable a firewall with no SSH path to the box).
- **Tailnet rule verification.** When the lockdown removes the public SSH rule, it first checks `ufw status` for the `tailscale0 ... ALLOW` rule. If that rule isn't visible, the public rule is left in place.

Together: even if you misconfigure something, you keep the SSH session you're running the script *from*, plus the public path stays open until the tailnet path is verifiably alive.

---

## 🔁 Re-running & idempotency

Every step is idempotent. Edit, re-run:

```bash
sudo nano /etc/vps/bootstrap.env       # change anything — add a brew package, add an SSH key source, etc.
sudo /usr/local/sbin/vps-bootstrap.sh  # re-applies user/keys/brew/shell config
sudo /usr/local/sbin/vps-harden.sh     # re-applies firewall/SSH/tailscale config
sudo /usr/local/sbin/vps-tools.sh      # re-applies AI tooling + statusline
```

Logs accumulate in `/var/log/vps-bootstrap.log`.

**Shell config auto-converges.** Volatile shell tweaks (aliases, tool init, hooks) live in `~/.vps-shell.sh`, which the bootstrap rewrites on every run — old alias text is replaced, never appended next to. The loader in `~/.bashrc` re-sources the file via `PROMPT_COMMAND` whenever its mtime changes, so existing shells pick up updates automatically without needing `exec bash`. One-shot init (`starship init bash`, `zoxide init bash`) is guarded by an env var so it doesn't double-fire.

---

## 🧰 Troubleshooting

For deeper coverage of failure modes, recovery commands, and how to read `VerifyChecklist.sh` output, see **[README_Troubleshooting.md](README_Troubleshooting.md)**. The table below is the quick-reference index.

| Symptom | Likely cause / fix |
|---|---|
| `bash: line 1: curl: command not found` | Older minimal image; run `apt-get update && apt-get install -y curl` first |
| `ERROR: PUBLIC_SSH_ALLOWED=0 but Tailscale is not connected` | First run with lockdown enabled — leave `PUBLIC_SSH_ALLOWED=1` until tailnet is verified |
| `ERROR: refusing to disable password auth — neither <user> nor /root/.ssh/authorized_keys has any keys` | No SSH key sources were resolved during bootstrap — re-run `vps-bootstrap.sh` with `SSH_ID` / `SSH_GH_USER` / `SSH_AUTHORIZED_KEYS` set, or add a key manually before re-running harden |
| `WARN: PermitRootLogin=… but /root/.ssh/authorized_keys is empty` | sshd allows root key login but no key is installed for root. Add the key your laptop uses to `/root/.ssh/authorized_keys` (or set `PERMIT_ROOT_LOGIN=no` and rely on `<user>` only) |
| `WARN: SSH'd in as '<x>' but new AllowUsers will be: <y>` | You're running the harden script as a user who won't be allowed in after reload. **Don't log out** — open a new SSH session as `<user>` (or root) first to verify access |
| `ERROR: sshd -t rejected new drop-in; rolling back` | Something invalidated `99-vps-hardening.conf` — typically a stray character in `SSH_PORT` / `PERMIT_ROOT_LOGIN` / `ALLOW_PASSWORD_AUTH`. The previous drop-in is restored automatically; fix the env file and re-run |
| `Missing privilege separation directory: /run/sshd` | `/run` is a tmpfs and `/run/sshd` was cleared. Current scripts run `mkdir -p /run/sshd && chmod 0755 /run/sshd` before `sshd -t`; if you see this, you're running an old copy — re-pull `vps-harden.sh` |
| `Address already in use` from `ssh.service` start | Orphan `sshd` listener from a previous failed start is holding the port (Ubuntu's `KillMode=process` leaves it around). Current scripts auto-detect and kill `[listener]` orphans before `start`. Manual fix: `sudo kill <pid>; sudo systemctl reset-failed ssh.service; sudo systemctl start ssh.service` |
| `<var>: unbound variable` (e.g. `DISABLE_IPV6_SSH`) | Your `/etc/vps/bootstrap.env` is missing a var the latest harden script references. Current `vps-harden.sh` has a defaults block that backstops every optional var; re-pull the latest harden |
| `bash: /dev/fd/63: No such file or directory` / `curl: (23) Failure writing output to destination` | Race between `sudo` and process-substitution closing the FD. Use `curl -fsSL <url> \| sudo bash` *or* `sudo -i` first, then `bash <(curl …)` |
| `WARN: tailnet SSH rule not visible in 'ufw status'` | tailscaled didn't bring up `tailscale0`; check `journalctl -u tailscaled` and `tailscale status` |
| `ERROR: 'tailscale up' failed (exit N)` with `requested tags … are invalid or not permitted` | A tag in `TAILSCALE_TAGS` (or `--advertise-tags`) isn't in `tagOwners` in your `tailscale.json`. Either remove the tag from `TAILSCALE_TAGS` (leave blank to use the auth-key default), or add the tag to `tagOwners` and re-publish the policy |
| `ERROR: 'tailscale up' failed` with `auth key … exhausted` / `expired` | Auth key already used (single-use) or past its TTL. Generate a new ephemeral, tagged auth key, paste it into `TAILSCALE_AUTHKEY`, re-run harden |
| Tailscale joined but SSH via tailnet rejects `<user>` | Your `tailscale.json` SSH ACL `users` list doesn't include `<user>`. Add `<user>` to the `users` array, re-publish the policy |
| `Error: The current working directory must be readable to <user> to run brew.` | A sub-shell ran as the user from `/root` (which the user can't read). The current scripts always `cd "$HOME"` first; if you see this, re-pull `vps-bootstrap.sh` |
| `bash: -c: line 1: syntax error near unexpected token 'then'` (running `vps-tools.sh`) | Old `bash -lc "$multi-line"` form collapsed newlines through argv. Fixed in the current script (uses `bash -l -s` heredoc-via-stdin). Re-pull `vps-tools.sh` |
| `/etc/vps/bootstrap.env: Permission denied` | You ran `vps-tools.sh` (or another root-only script) as a regular user. Re-run with `sudo` — the env file is mode 600 |
| `Refusing to use reserved username` | Your `VPS_USER` is `root` / `linuxbrew` / a UID < 1000 — pick a new one |
| `WARN: brew not found at /home/linuxbrew/.linuxbrew/bin/brew` | First Homebrew install failed; re-run `vps-bootstrap.sh` after fixing the underlying network/disk issue |
| `WARN: failed bun` (during `vps-bootstrap.sh`) | `bun` isn't in homebrew-core under that bare name. The default `BREW_PACKAGES` now lists `oven-sh/bun/bun` (the official tap form). Edit `/etc/vps/bootstrap.env` and re-run if you see this on an older env file |
| `claude: command not found` from root (but Claude installed under `<user>`) | Claude Code installs to `~/.local/bin/claude` (per-user). `vps-tools.sh` creates `/usr/local/bin/claude` symlink. If missing on an older install: `sudo ln -sf /home/<user>/.local/bin/claude /usr/local/bin/claude` |

---

## 🏗️ Architecture & file layout

### Worker scripts (run on the VPS)

| File | Responsibility |
|---|---|
| [`vps-bootstrap.sh`](vps-bootstrap.sh) | Apt base packages (incl. `bc`, `jq`), hostname, primary user + sudoers, SSH keys, Homebrew, `~/.vps-shell.sh` sentinel + auto-resource loader, first-login password hook |
| [`vps-harden.sh`](vps-harden.sh) | UFW rules, fail2ban, unattended-upgrades, sshd lockdown via drop-in, sysctl, Tailscale join + tag/SSH ACL |
| [`vps-tools.sh`](vps-tools.sh) | Claude Code + custom statusline, opencode, crush, codex, tmuxai, ollama, lazygit, system-wide `claude` symlink |
| [`VerifyChecklist.sh`](VerifyChecklist.sh) | Post-install audit. `--quiet` for cron, `--report` to re-print last install tally |
| [`firstrun.sh`](firstrun.sh) | Manual one-shot script (no cloud-init). Pulls + runs all three workers in order |
| [`vps-init.sh`](vps-init.sh) | Self-contained orchestrator: writes the three workers as embedded heredocs, runs them, prints the install report |

### Helper scripts

| File | Responsibility |
|---|---|
| [`addnew-sshid-key.sh`](addnew-sshid-key.sh) | Install `sshid.io` keys for a target user. Optional `--create-user` for new accounts |
| [`addupdate-sshid-key.sh`](addupdate-sshid-key.sh) | Append-only key sync (root-only target by default; safer for re-runs) |

### Configuration / data

| File | Purpose |
|---|---|
| [`bootstrap.env`](bootstrap.env) | Single source of truth. Sourced by all workers |
| [`cloud-init.yaml`](cloud-init.yaml) | Provider user-data: writes `bootstrap.env`, fetches all three workers, runs them |
| [`tailscale.json`](tailscale.json) | Reference Tailscale ACL: tag owners, SSH access policy |
| [`CustomConfigs/`](CustomConfigs/) | Bundle for the Claude Code statusline (downloaded by `vps-tools.sh`) |

### Filesystem layout after a successful run

```
/etc/vps/bootstrap.env             # mode 600, sourced by all scripts
/usr/local/sbin/vps-bootstrap.sh
/usr/local/sbin/vps-harden.sh
/usr/local/sbin/vps-tools.sh
/usr/local/sbin/VerifyChecklist.sh # if you ran the verify
/var/log/vps-bootstrap.log         # all [STATUS] lines, append-only
/home/<user>/.vps-shell.sh         # sentinel: aliases, tool init, hook source
/home/<user>/.firstlogin-passwd.sh # one-shot password prompt
/home/<user>/.password_set         # appears once user has set a password
```

---

## 📐 Resolved design decisions

These are points worth being explicit about — non-obvious choices and *why*.

### SSH lockout safety

- **`sshd reload`, not `restart`.** SIGHUP makes sshd re-read config in place; existing sessions survive, only new connections see the new config. But reload requires the service to already be active — on the first transition from socket-activated to service-mode SSH, `start` is the only valid action. The script picks based on `systemctl is-active`. On failure either way, prints `systemctl status` + last 25 journal lines + port listeners + three concrete remediation commands, so the operator never sees a bare exit code.
- **Orphan-listener cleanup before `start`.** Ubuntu's `ssh.service` has `KillMode=process`; a previous failed start can leave the original `sshd` listener alive and unparented in the unit's cgroup. Before starting, the script scans for processes bound to `SSH_PORT` whose cmdline contains `[listener]` (the master sshd marker — per-connection sshds carrying live SSH sessions never have it) and kills them; `systemctl reset-failed ssh.service` clears systemd's memory of the prior failure.
- **sshd drop-in rollback.** Snapshot `99-vps-hardening.conf` to `*.bak` before writing the new one; `sshd -t` validates; on failure restore the backup (or remove ours if there was no prior). A broken drop-in is never left in place.
- **Pre-flight key check before tightening sshd.** Verify *at least one* of `<user>`'s or `root`'s `authorized_keys` is non-empty before disabling password auth. Warn (don't abort) on empty root keys when `PermitRootLogin` is permissive.
- **Privilege-separation runtime dir.** `mkdir -p /run/sshd && chmod 0755 /run/sshd` before `sshd -t`. `/run` is a tmpfs; the directory is normally materialised by `ssh.service`'s `RuntimeDirectory=sshd` at start time, but `sshd -t` runs *before* that, so the script has to create it itself.
- **Defaults block for partial env files.** Every optional `bootstrap.env` var (≈25 of them) gets a `: "${VAR:=default}"` line at the top of `vps-harden.sh`. So `set -u` doesn't trip when an older or hand-edited env file is missing newer vars. Required vars (`VPS_USER`) use `:?` instead — clean error if absent.
- **Ubuntu 24.04 `ssh.socket`:** disable AND mask it. `disable --now` only removes symlinks (apt operations / package hooks can re-create them); `mask` makes the unit a `/dev/null` symlink that survives package operations.
- **Mirror keys to root:** yes, during bootstrap, as a transitional safety net. Append+dedupe (not overwrite) so re-runs preserve any keys the cloud provider seeded or that you added by hand. The hardening script then enforces `PermitRootLogin prohibit-password` (no passwords, key-only) so root SSH remains a recovery hatch rather than a routine login path.

### Tailscale

- **Auth key:** scrub from `/etc/vps/bootstrap.env` after a successful join; cloud-init `user-data` is also persisted on disk in `/var/lib/cloud/instances/*/user-data.txt`, so use **ephemeral, tagged, time-limited** auth keys (`tskey-auth-...`) issued per-environment.
- **Auth-key paste flexibility.** The wizard and `vps-harden.sh` both normalise `TAILSCALE_AUTHKEY` on load: accept either the bare `tskey-auth-…` key OR the full one-liner Tailscale's admin web hands you (`curl … | sh && sudo tailscale up --auth-key=tskey-auth-…`). The `--auth-key=` portion is extracted automatically.
- **Public SSH lockdown:** automated via `PUBLIC_SSH_ALLOWED=0` on a second run, gated on Tailscale actually being up *and* the `tailscale0 … ALLOW` rule being visible in `ufw status` before the public rule is removed — never blindly during first boot.
- **Success summary.** After a successful `tailscale up`, the script prints DNS / IPv4 / IPv6 / a ready-to-paste `ssh user@<hostname>` command — the operator doesn't have to read raw `tailscale status`.

### User & shell

- **Username collision:** explicitly refuse `root`, `linuxbrew`, or any existing system user with UID < 1000, to avoid clobbering the Linuxbrew install user.
- **Hostname generation:** prefer Hetzner metadata `instance-id` when available (deterministic, traceable), fall back to `/etc/machine-id`, then to random bytes. Format: `<prefix>-<role>-<id>` so role is encoded in the device name.
- **First-login password hook.** `useradd -m` leaves the password locked. A `~/.firstlogin-passwd.sh` hook (sourced from `~/.vps-shell.sh`) prompts the user to set a password on first interactive shell, self-disables on success. Reliable across `ssh`, `su`, `su -`, and console login — independent of PAM. Full notes: [README_FirstLoginPassword.md](README_FirstLoginPassword.md).
- **`~/.vps-shell.sh` sentinel + auto-resource loader.** All volatile shell tweaks live in this one file, regenerated on every bootstrap run — old alias text is replaced, never appended next to. The loader in `~/.bashrc` (between `# >>> vps-shell-loader >>>` markers) re-sources it via `PROMPT_COMMAND` when its mtime changes, so existing shells pick up updates without `exec bash`. One-shot init (`starship init bash`, `zoxide init bash`) is guarded by `VPS_SHELL_ONESHOT_DONE` so it doesn't double-fire.

### Homebrew & user-space tooling

- **Brew CWD requirement.** Every `sudo -Hu <user> bash` block that touches brew must `cd "$HOME"` first. `sudo -Hu` (without `-i`) inherits the parent CWD, typically `/root`, which the unprivileged user can't read — brew refuses to start with the "current working directory must be readable" error.
- **`brew shellenv bash`** instead of bare `brew shellenv`. Removes shell-detection ambiguity in non-interactive contexts (cron, systemd `User=`, scripts).
- **Tap-aware brew install loop.** `BREW_PACKAGES` accepts both bare formula names (`starship`, `jq`) and tap-prefixed forms (`oven-sh/bun/bun`, `charmbracelet/tap/crush`). The install loop strips the leaf for the local "already installed" check (`brew list --formula` only accepts simple names) but passes the full path to `brew install`.
- **Node.js:** install via Homebrew (`node` formula). Brew gives one consistent install path across all VPSs. The `nvm` route is left as opt-in (`INSTALL_NODE_LTS=1`) for projects that need to pin specific Node versions per-project.
- **`~/.local/bin` in user PATH.** `vps-bootstrap.sh` writes an idempotent guard (`case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH=…;; esac`) into `~/.profile` and `~/.bashrc`. `[ -d "$HOME/.local/bin" ] &&` guard means non-existent dirs don't pollute PATH on a fresh box.

### AI tooling

- **Installer paths:** brew taps where they exist (`opencode`, `crush`); `npm i -g @openai/codex` for Codex (no Linux brew formula); `claude.ai/install.sh` for Claude Code (no Linux cask). Failed installs do not abort the rest of the tools step — each step emits a `[STATUS] warn` line so the operator sees what broke.
- **Claude Code system-wide symlink.** Claude's installer writes to `~/.local/bin/claude` per-user, so root has no PATH access by default. After Claude install, `vps-tools.sh` creates `/usr/local/bin/claude` as a symlink to `<user>/.local/bin/claude`. Both root and the VPS user can now run `claude`; each user gets their own state under their own `$HOME/.config/claude` dir.
- **Custom statusline (CustomConfigs).** `vps-tools.sh` fetches `CustomConfigs/claude-statusline-export.tar.gz` after Claude installs, then runs the bundled `install.sh` **twice — once as root, once as `$VPS_USER` via `sudo -Hu`** — so `~/.claude/settings.json` is configured under both `/root/.claude` and `/home/<user>/.claude`. The temp extraction dir is `chown`'d between runs so the user can read it. Settings merge via `jq` with a timestamped backup. See [CustomConfigs/README.md](CustomConfigs/README.md).

### Install reporting

- **Structured `[STATUS]` install protocol.** Every install attempt emits one line per step: `[STATUS] <ok|warn|fail>|<step>|<detail>`. Per-package brew loops, per-tap install attempts, npm/curl-installers, tailscale up, ollama daemon. Format is human-readable in the log AND `grep|awk`-able for the report. No more silent batch failures like *"some terminal tools failed"*.
- **End-of-install report in `vps-init.sh`.** After all worker scripts complete, parses `/var/log/vps-bootstrap.log` for `[STATUS]` lines and prints a 3-line tally + explicit list of warnings/failures + copy-pasteable retry recipes. The operator doesn't scroll back through 1000+ lines of brew output to find what broke.
- **`VerifyChecklist.sh` as a real audit tool.** Counted, color-coded, exit-coded. Each check goes through `ok`/`warn`/`fail` helpers that tally; final summary prints `Result: PASS / PASS with warnings / FAIL` and exits non-zero on any failure (cron- and CI-usable). Validates each `sshd -T` field individually; verifies `tailscale0` interface is up *and* has an IP; spot-checks login-shell PATH resolution for `claude`, `eza`, `bat`, etc. — catches the *"installed but not in PATH"* regression.

---

## 🌍 Per-environment considerations

These are deliberately *not* automated in the scripts above because they require per-deployment policy decisions:

- **Secret injection.** Anything you put in cloud-init `user-data` lands on disk (`/var/lib/cloud/instances/*/user-data.txt`). For real secrets (Anthropic/OpenAI/OpenRouter API keys, long-lived Tailscale keys, registry credentials), use **SOPS + age**, **HashiCorp Vault**, **Doppler**, or **Infisical**. A common pattern: cloud-init installs only a short-lived bootstrap token, then the VPS pulls the rest from your secret store via Tailscale ACLs.
- **AI tool API keys.** `vps-tools.sh` deliberately doesn't write `~/.config/tmuxai/config.yaml`, `~/.config/opencode/config.json`, etc. Drop secrets into `/etc/vps/secrets.env`, mode 0600, and source it from the user's `.profile` so each tool reads `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, etc. from environment.
- **Re-running on long-lived VPSs.** The scripts are idempotent, but for fleets, prefer pinning to a script version (`?ref=v1.2.0` on the GitHub raw URL) and tracking which version is installed (`/etc/vps/version`). For drift detection consider a tiny periodic systemd timer that re-runs the bootstrap and reports a diff.
- **First-boot systemd unit.** If you don't want cloud-init, a `/etc/systemd/system/vps-firstboot.service` with `ConditionPathExists=!/var/lib/vps/bootstrapped` running `vps-bootstrap.sh && vps-harden.sh && touch /var/lib/vps/bootstrapped` is the equivalent.
- **IPv6.** SSH and UFW handle IPv6 by default. If you don't need it, set `DISABLE_IPV6=1` and `DISABLE_IPV6_SSH=1`. Otherwise verify `ufw status` shows v6 rules, and that your tailnet has IPv6 enabled if you want dual-stack across the mesh.
- **Backups / snapshots.** Hetzner's automated snapshots are cheap; enable them per-server via the API. For application data, set up `restic` or `borg` to a Backblaze B2 / S3 bucket. Not included by default because retention/policy varies wildly.
- **Monitoring / observability.** For a staging+production fleet, install `node_exporter` (Prometheus), or a unified agent like `vector`, `grafana-agent`, or `netdata`. Recommended pattern: the agent listens only on `tailscale0` and your Prometheus/Loki scrapes via Tailscale, with no public exposure.
- **GitOps for staging vs prod.** Maintain `bootstrap.staging.env` and `bootstrap.production.env` in your config repo; cloud-init picks the right one via the `VPS_ROLE` variable. Gate production auth keys (Tailscale, registries) behind a separate SOPS recipient so accidental staging deploys cannot pull production secrets.
- **Disaster recovery.** Keep the scripts plus `bootstrap.env` (with secrets stripped) in version control so any VPS can be reproduced from scratch by running cloud-init against a fresh image.

---

## 📚 Related documentation

| Doc | What it covers |
|---|---|
| [README_SampleExperience.md](README_SampleExperience.md) | Walkthrough of every interactive `vps-init.sh` prompt with expected output. Read alongside Quickstart on first install |
| [README_Troubleshooting.md](README_Troubleshooting.md) | Deep-dive failure modes, recovery commands, expected `VerifyChecklist.sh` output |
| [README_VPSscripts.md](README_VPSscripts.md) | Per-script overview of `vps-bootstrap.sh` / `vps-harden.sh` / `vps-tools.sh` and design constraints |
| [README_SingleFileVPSinit.md](README_SingleFileVPSinit.md) | Full env-var reference for `vps-init.sh`; detail on why it ships as a single self-contained file |
| [README_SSHIDscript.md](README_SSHIDscript.md) | `addnew-sshid-key.sh` / `addupdate-sshid-key.sh` — adding sshid.io keys post-bootstrap |
| [README_FirstLoginPassword.md](README_FirstLoginPassword.md) | First-login password prompt hook — design and customization |
| [CustomConfigs/README.md](CustomConfigs/README.md) | Claude Code statusline bundle — install script, customization, deps |

---

## 🤝 Contributing

Issues and pull requests welcome at <https://github.com/MahaKoala/VPSsetup>.

**When editing the bootstrap pipeline,** keep the **standalone scripts** (`vps-bootstrap.sh`, `vps-harden.sh`, `vps-tools.sh`) as the source of truth — they are what `cloud-init.yaml` and `firstrun.sh` curl directly. `vps-init.sh` embeds copies of all three as heredocs (`BOOTSTRAP_EOF`, `HARDEN_EOF`, `TOOLS_EOF`); these need to be re-synced from the standalones after script changes. Run `bash -n *.sh` before pushing.

---

<div align="center">

<sub>Built for self-hosted infrastructure. Lockout-safe. Idempotent. Designed to be re-run.</sub>

<br>

<a href="#top">⬆ Back to top</a>

</div>
