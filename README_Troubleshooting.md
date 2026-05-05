# Troubleshooting

A symptom-first guide to recovering from common VPS-setup failures. Each entry is **what you see → why it happens → how to fix**.

If you're not sure where to start:

```bash
# Read the install report from your last run:
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh) --report

# Full audit (cron-friendly: exits 1 on any failure):
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh)
```

---

## 1. SSH lockout / can't get back in

**This is the highest-priority section.** If you're SSH'd in *right now* and a harden run failed, **don't log out** until you've verified you can open a *new* SSH session.

### `ssh.service failed to start` with `Address already in use` on port 22

You'll see something like:

```
sshd[…]: error: Bind to port 22 on 0.0.0.0 failed: Address already in use.
sshd[…]: fatal: Cannot bind any address.
ssh.service: Found left-over process 862 (sshd) in control group while starting unit.
```

**Cause:** Ubuntu's `ssh.service` has `KillMode=process` — when a previous start fails, the master listener `sshd` survives but is unparented from the unit. Next `start` fails because the port is still bound.

**Fix:** kill the orphan listener (its cmdline contains `[listener]`; per-connection sshds carrying live sessions don't have that marker, so this is safe even from inside an SSH session).

```bash
# Identify it
ps -ef | grep '[s]shd: /usr/sbin/sshd -D \[listener\]'

# Kill it
sudo kill <pid>           # e.g. sudo kill 862
sleep 1

# Reset systemd's failure memory and start cleanly
sudo systemctl reset-failed ssh.service
sudo systemctl start ssh.service
sudo systemctl is-active ssh.service     # → active
sudo ss -tlnp | grep ':22'                # → new sshd listener
```

The current `vps-harden.sh` does this automatically before `start`. If you're hitting it manually, you're running an old copy — re-pull `vps-harden.sh`.

### `Missing privilege separation directory: /run/sshd`

**Cause:** `/run` is a tmpfs; `/run/sshd` is normally created by `ssh.service`'s `RuntimeDirectory=sshd` at start time. But `sshd -t` runs *before* the service starts, so the dir isn't there yet.

**Fix:**
```bash
sudo mkdir -p /run/sshd
sudo chmod 0755 /run/sshd
sudo sshd -t                # should now complete silently
```

The current scripts run `mkdir -p /run/sshd` before `sshd -t` automatically.

### `ssh.service` won't start after `systemctl mask ssh.socket`

If the harden run masked `ssh.socket` and the original socket-activated `sshd` was still serving connections:

```bash
# Show what's currently in the ssh.service cgroup
sudo systemctl status ssh.service

# Kill any orphan listener (see above), reset, restart
sudo systemctl reset-failed ssh.service
sudo systemctl unmask ssh.socket    # only if you need to revert
sudo systemctl mask ssh.socket      # mask again after fix (recommended)
sudo systemctl start ssh.service
```

Mask is preferred over plain `disable` because apt operations can re-enable a disabled unit; mask makes it a `/dev/null` symlink that survives.

### `WARN: SSH'd in as '<x>' but new AllowUsers will be: <y>`

The harden script printed this and continued. **Don't log out.** The new SSH config will reject your username on next login.

**Fix:** before logging out, open a *new* SSH window as one of the listed users (`<user>` or `root`):

```bash
ssh maha@<server-ip>      # or root, if PermitRootLogin allows
```

If that succeeds, you can close the original session safely. If not, the new config never reloaded and you can edit `/etc/vps/bootstrap.env` to add your user to the allowed list, then re-run harden.

### `ERROR: refusing to disable password auth — neither <user> nor /root/.ssh/authorized_keys has any keys`

Pre-flight check tripping. Either no SSH key sources resolved during bootstrap, or the keys never got written.

**Fix:** add at least one key to either path before re-running harden:

```bash
# Option A: re-run bootstrap with key sources
sudo SSH_ID=mahakoala SSH_GH_USER=mahakoala /usr/local/sbin/vps-bootstrap.sh

# Option B: paste a key directly
echo 'ssh-ed25519 AAAAC3… your@laptop' | sudo tee -a /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys
```

Then re-run `vps-harden.sh`.

### `WARN: PermitRootLogin=… but /root/.ssh/authorized_keys is empty`

sshd allows root key-login but no key is installed for root.

**Fix:** mirror your laptop's key into root's `authorized_keys` (the bootstrap script does this from `<user>`'s keys, but only if `<user>` has any).

```bash
# Mirror from <user> to root (matches what bootstrap does)
sudo cat /home/maha/.ssh/authorized_keys >> /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys
sudo sort -u -o /root/.ssh/authorized_keys /root/.ssh/authorized_keys
```

---

## 2. Firewall (UFW)

### `ufw is installed but not active`

The most common cause: a previous harden run aborted at §2 (SSH hardening) before reaching §3 (UFW). UFW config never ran.

**Fix:** finish whatever blocked §2, then re-run:

```bash
sudo /usr/local/sbin/vps-harden.sh
```

It's idempotent; no-op for steps that already completed.

### `ERROR: PUBLIC_SSH_ALLOWED=0 but Tailscale is not connected. Refusing to enable UFW`

The lockout-prevention guard is doing its job. You set `PUBLIC_SSH_ALLOWED=0` (intending tailnet-only SSH) but Tailscale isn't up, so enabling UFW would lock you out.

**Fix:** revert to public SSH, finish Tailscale, *then* lock down:

```bash
# 1. Allow public SSH again (default state)
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="1"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
# 2. Verify Tailscale works (in a new terminal):
tailscale status
ssh maha@<tailscale-hostname>
# 3. Now lock down:
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

### `WARN: tailnet SSH rule not visible in 'ufw status'`

`tailscaled` didn't bring up `tailscale0`, or it's up but the rule didn't apply.

**Fix:**
```bash
sudo journalctl -u tailscaled --no-pager -n 30
sudo tailscale status        # check the daemon's view
sudo ip -brief addr show tailscale0    # interface should have an IP
```

If the interface is missing, run `sudo tailscale up --auth-key=<key>` to re-establish.

### Confirming port 22 is allowed

After a successful harden run with default config:

```bash
sudo ufw status verbose | grep -E '(Status|22/tcp|tailscale)'
# Status: active
# 22/tcp                     ALLOW IN    Anywhere
# 22/tcp (v6)                ALLOW IN    Anywhere (v6)
# Anywhere on tailscale0     ALLOW IN    Anywhere
# 41641/udp                  ALLOW IN    Anywhere
```

---

## 3. Tailscale

### `'tailscale up' failed (exit N)` with `requested tags … are invalid or not permitted`

**Cause:** A tag in `TAILSCALE_TAGS` (or `--advertise-tags`) isn't declared in `tagOwners` in your Tailscale ACL (`tailscale.json`), OR isn't within the auth-key's allowed tag set.

**Fix:** the safe path is to **not** override tags — let the auth-key's own tags speak for themselves:

```bash
# Clear the override (default: empty = use key's tags)
sudo sed -i 's/^TAILSCALE_TAGS=.*/TAILSCALE_TAGS=""/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

If you genuinely need to override, add the tag to `tagOwners` in your Tailscale admin's Access Controls and re-publish the policy first.

### `'tailscale up' failed` with `auth key … exhausted` / `expired`

Auth key is single-use and already consumed, or past its TTL.

**Fix:** generate a new ephemeral, tagged auth key at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) and update `bootstrap.env`:

```bash
# Edit the env file (mode 600, must be root)
sudo sed -i "s|^TAILSCALE_AUTHKEY=.*|TAILSCALE_AUTHKEY=\"tskey-auth-NEWKEY\"|" /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

The wizard and harden script both accept either the bare key OR the full `curl … && sudo tailscale up --auth-key=…` one-liner — paste whichever the admin web shows you and the `--auth-key=` portion is extracted automatically.

### Tailscale joined but `tailscale ssh` rejects `<user>`

Your `tailscale.json` SSH ACL `users` list doesn't include `<user>`.

**Fix:** edit `tailscale.json` in the Tailscale admin (Access Controls), add `<user>` to the `users` array, save:

```json
"ssh": [
  {
    "action": "accept",
    "src":    ["autogroup:admin"],
    "dst":    ["tag:vps"],
    "users":  ["root", "maha"]   // add your user here
  }
]
```

No VPS-side action needed; the change applies on the next connection attempt.

### `tailscale up` itself succeeds but the script reports failure

Capture stderr to see the real reason:

```bash
sudo tailscale up --auth-key="$TAILSCALE_AUTHKEY" --hostname="$(hostname)" --accept-dns=false 2>&1 | tee /tmp/ts-up.log
```

Common causes the script's failure-message lists:
- key expired / single-use
- tag not in tagOwners
- key tag set ≠ requested tag set
- controlplane unreachable (firewall blocks `*.tailscale.com:443`)
- existing state conflict — try `sudo tailscale logout` then re-run

---

## 4. Homebrew & brew packages

### `Error: The current working directory must be readable to <user> to run brew`

**Cause:** A sub-shell ran as the user from `/root` (which the user can't read). Brew refuses to start when CWD is unreadable.

**Fix:** the current scripts always `cd "$HOME"` first inside every `sudo -Hu user` block, including the persistent `eval "$(brew shellenv bash)"` line in `~/.bashrc` and `~/.profile`. If you're hitting this, you're running an old copy — re-pull `vps-bootstrap.sh` and re-run.

Quick manual fix to the dotfiles:
```bash
# Replace the bad line with the cd-protected version
sudo -u maha sed -i -E '/^eval "\$\(\/home\/linuxbrew\/\.linuxbrew\/bin\/brew shellenv( bash)?\)"$/d' \
    /home/maha/.bashrc /home/maha/.profile
echo 'eval "$(cd "$HOME" 2>/dev/null && /home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' \
    | sudo -u maha tee -a /home/maha/.bashrc /home/maha/.profile
```

### `WARN: failed bun`

**Cause:** `bun` isn't in homebrew-core under that bare name. The default `BREW_PACKAGES` now uses `oven-sh/bun/bun` (the official tap form).

**Fix:** edit `BREW_PACKAGES` in `/etc/vps/bootstrap.env` to replace `bun` with `oven-sh/bun/bun`, then re-run bootstrap:

```bash
sudo sed -i 's| bun | oven-sh/bun/bun |g' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-bootstrap.sh
```

Or install just bun manually:

```bash
sudo -Hu maha bash -lc 'cd "$HOME" && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)" && brew install oven-sh/bun/bun && bun --version'
```

### `WARN: <pkg> install failed` for any other formula

The `[STATUS] warn` line tells you exactly which package. Re-attempt manually for diagnostics:

```bash
sudo -Hu maha bash -lc 'cd "$HOME" && brew install <pkg>'
```

If brew complains about post-install steps (e.g. `libthai`), those are usually warnings — the formula was actually installed; brew just couldn't run a non-essential post-install hook. Verify with `brew list --formula <pkg>`.

---

## 5. AI tools (Claude / opencode / codex / tmuxai / ollama)

### `claude: command not found` from root (but Claude installed for `<user>`)

**Cause:** Claude Code's installer drops the binary in `~/.local/bin/claude` — only on `<user>`'s PATH, not root's.

**Fix:** the current `vps-tools.sh` creates `/usr/local/bin/claude` as a symlink during install. If missing on an older install:

```bash
sudo ln -sf /home/maha/.local/bin/claude /usr/local/bin/claude
which claude && claude --version
```

Each user gets their own state under `$HOME/.config/claude` regardless of which symlink they invoked.

### `tmuxai: command not found`

The tmuxai installer puts itself in `/usr/local/bin/tmuxai` (with sudo prompt). If missing, re-run the installer:

```bash
sudo -Hu maha bash -c 'cd ~ && curl -fsSL https://get.tmuxai.dev | bash'
which tmuxai
```

### `codex: command not found`

`codex` is installed as a global npm package using Linuxbrew node, so it lands in `/home/linuxbrew/.linuxbrew/bin/codex` (already on every user's PATH via `/etc/profile.d/homebrew.sh`).

If missing:

```bash
sudo -Hu maha bash -lc 'cd "$HOME" && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)" && npm i -g @openai/codex && codex --version'
```

### `opencode` / `crush: command not found`

Both are brew taps. Re-install:

```bash
sudo -Hu maha bash -lc '
cd "$HOME"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
brew install sst/tap/opencode charmbracelet/tap/crush
'
```

### Ollama service not active

```bash
sudo systemctl status ollama
sudo journalctl -u ollama --no-pager -n 30
sudo systemctl restart ollama
```

If the daemon installer never ran successfully:

```bash
sudo curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama
```

---

## 6. Script execution

### `bash: -c: line 1: syntax error near unexpected token 'then'`

**Cause:** Old `bash -lc "$multi-line"` form collapsed newlines through argv on some sudo/kernel combos, fusing `if … then` onto one line.

**Fix:** the current `vps-tools.sh` uses `bash -l -s` heredoc-via-stdin which is immune. Re-pull the latest.

### `/etc/vps/bootstrap.env: Permission denied`

**Cause:** You ran `vps-tools.sh` (or another root-only script) as a regular user. The env file is mode 600 and aborts the script before the friendly "must run as root" error.

**Fix:** prefix with `sudo`:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-tools.sh)
```

### `<var>: unbound variable` (e.g. `DISABLE_IPV6_SSH`)

**Cause:** Older `/etc/vps/bootstrap.env` is missing a var that the latest harden script references. With `set -u`, that aborts.

**Fix:** the current `vps-harden.sh` has a defaults block that backstops every optional var. Re-pull it. Or add the missing var to your env file:

```bash
echo 'DISABLE_IPV6_SSH="0"' | sudo tee -a /etc/vps/bootstrap.env
```

### `bash: /dev/fd/63: No such file or directory` / `curl: (23) Failure writing output`

**Cause:** Race between `sudo` and process substitution closing the FD too early. Particularly affects `sudo bash <(curl …)`.

**Fix:** use one of these forms instead:

```bash
# Option 1: pipe through sudo
curl -fsSL <url> | sudo bash

# Option 2: become root first, then process-sub works
sudo -i
bash <(curl -fsSL <url>)
```

### `Refusing to use reserved username`

`VPS_USER` is `root` / `linuxbrew` / a UID < 1000. The bootstrap refuses to clobber system users or the Linuxbrew install user.

**Fix:** pick a different name in `bootstrap.env`:

```bash
sudo sed -i 's/^VPS_USER=.*/VPS_USER="maha"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-bootstrap.sh
```

---

## 7. Reading `VerifyChecklist.sh` output

Run it after every install / change:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh)
```

### Three exit states

| Result | Meaning | Action |
|---|---|---|
| `Result: PASS` | All checks ok | Done |
| `Result: PASS with warnings` | Some `!` items, no `✗` | Review the warnings — usually optional improvements (e.g. tailnet rule absent because tailnet wasn't joined yet). Acceptable in most flows. |
| `Result: FAIL` | At least one `✗` | Must fix before locking SSH to tailnet. Each `✗` line tells you which check failed and a recovery command |

Exit code is `0` for PASS / PASS-with-warnings, `1` for FAIL — usable in cron / CI pipelines.

### Useful flags

```bash
# Print only the install-time [STATUS] tally from /var/log/vps-bootstrap.log:
sudo bash VerifyChecklist.sh --report

# Suppress ok lines, only show warn/fail/summary (cron-friendly):
sudo bash VerifyChecklist.sh --quiet
```

### What each section verifies

| Section | What ✓ means | Common ✗ |
|---|---|---|
| Hostname / OS | `hostnamectl` works, OS is recognised | rare |
| Disk space | `> 2GB` free on `/`, `/home`, `/var` | tiny VPS, fails under 500MB |
| SSH config (effective) | `sshd -T` parses; each field validated | missing host keys (`ssh-keygen -A`), corrupted drop-in |
| `authorized_keys` per user | Key file exists and has lines | empty file → bootstrap key sources didn't resolve |
| UFW | `Status: active`, SSH path visible | harden didn't reach §3 (re-run) |
| fail2ban | service active, sshd jail tracked | service missing — re-run harden |
| unattended-upgrades | service active | service missing — re-run harden |
| Tailscale | self IP + name + tailscale0 interface | not joined — `sudo tailscale up --auth-key=…` |
| Homebrew | `brew --version` works as `<user>` | brew install didn't complete; re-run bootstrap |
| Tool resolution | `claude` / `eza` / `bat` / etc. resolve | PATH issue — re-run bootstrap; check `~/.bashrc` |

If multiple sections fail, fix in the order they're checked. Earlier failures often cause later ones (e.g. UFW failing because SSH config never finished).

---

## 8. Recovery scripts

### Wholesale re-install (idempotent)

```bash
# Re-fetch the latest from the repo (assumes you've pushed your fixes):
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-bootstrap.sh)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-harden.sh)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-tools.sh)
```

### Apply only the SSH-config drop-in changes

```bash
# Edit /etc/vps/bootstrap.env to change SSH_PORT / PERMIT_ROOT_LOGIN / etc.
sudo /usr/local/sbin/vps-harden.sh
# The script reloads ssh.service via SIGHUP — existing sessions survive.
```

### Add SSH keys after the fact

```bash
# Pull a key from sshid.io (uses sshid identifier you set up at https://sshid.io)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/addupdate-sshid-key.sh) -i mahakoala -u maha -t ALL

# Or from GitHub
curl -fsSL https://github.com/<gh-user>.keys | sudo tee -a /home/maha/.ssh/authorized_keys
sudo chmod 600 /home/maha/.ssh/authorized_keys
sudo chown maha:maha /home/maha/.ssh/authorized_keys
```

### Lock SSH to Tailscale-only (after verifying tailnet works)

```bash
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
# Refuses to apply if tailscale isn't connected — see §2 if blocked.
```

### Undo the SSH lockdown (allow public SSH again)

```bash
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="1"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

---

## When all else fails

The full install log is at `/var/log/vps-bootstrap.log` — it captures every script run, every `[STATUS]` line, every error. Often the answer is in there.

```bash
# Last 100 lines
sudo tail -100 /var/log/vps-bootstrap.log

# Just the install-report-relevant lines
sudo grep -E '^\[STATUS\]' /var/log/vps-bootstrap.log | tail -50

# Errors and warnings only
sudo grep -E '(ERROR|WARN|fail\|)' /var/log/vps-bootstrap.log | tail -30
```

For Hetzner specifically: if you've completely locked yourself out, the **rescue console** (Hetzner Cloud panel → Rescue) boots a recovery image with full filesystem access. From there you can edit `/etc/ssh/sshd_config.d/99-vps-hardening.conf`, add a key to `/root/.ssh/authorized_keys`, or undo any UFW rule.
