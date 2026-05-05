# Sample Experience — what a successful run looks like

A walkthrough of running `vps-init.sh` on a fresh Ubuntu 24.04 VPS, from your laptop terminal to a working tailnet-connected box. Use this as a reference for *what's normal* — if your run looks dramatically different, check [README_Troubleshooting.md](README_Troubleshooting.md).

The flow assumes a Hetzner Cloud VPS but the script works the same on DigitalOcean, Vultr, Linode, OVH, RackNerd, etc.

---

## 0. Pre-flight (on your laptop, ~5 min)

You need three things ready before SSHing in:

### Tailscale auth key

Visit [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys):

- Click **Generate auth key**
- Settings: **Reusable: off**, **Ephemeral: on**, **Pre-approved: off**, **Tags: tag:vps**, **Expiration: 1 hour**
- Copy the entire one-liner Tailscale shows you. It looks like:
  ```
  curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --auth-key=tskey-auth-XXXXXXXXXXXXXXXXXXXXXXXXX
  ```
- The wizard accepts either this whole line OR just the bare `tskey-auth-…` portion — it extracts the key automatically either way.

### Tailscale ACL (`tailscale.json`)

In the Tailscale admin → **Access Controls**, confirm the policy declares every tag you'll use AND lists your VPS user in the SSH ACL:

```json
{
  "tagOwners": {
    "tag:vps":             ["autogroup:admin"],
    "tag:dev":             ["autogroup:admin"],
    "tag:staging":         ["autogroup:admin"],
    "tag:production":      ["autogroup:admin"]
  },
  "ssh": [
    {
      "action": "accept",
      "src":    ["autogroup:admin"],
      "dst":    ["tag:vps"],
      "users":  ["root", "maha"]
    }
  ]
}
```

If you don't have the right tags, `tailscale up` will fail with `requested tags … are invalid or not permitted` — that's the most common Tailscale failure mode. Easy fix; just add to tagOwners and re-publish.

### Cloud-panel SSH key

In the Hetzner Cloud panel (or your provider's equivalent), make sure your laptop's public SSH key is registered AND will be injected into `/root/.ssh/authorized_keys` on first boot. This gives you a guaranteed root recovery path even if the SSH-ID fetch fails.

---

## 1. SSH into the fresh VPS

After provisioning, SSH in as root from your laptop:

```bash
ssh -t root@62.238.30.99 "bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)"
```

The `-t` allocates a TTY so the wizard's interactive prompts work over SSH. (Without `-t`, you'd see the wizard freeze waiting for input that has no controlling terminal.)

---

## 2. The wizard

You'll see something like:

```
════════════════════════════════════════════════════
  VPS Init — Ubuntu 24.04 provisioning wizard
════════════════════════════════════════════════════
Press Enter to accept defaults. Ctrl-C to abort.
```

### Identity

```
── Identity ──
Primary username [maha]:                                            ← Enter for default
Role (staging / production / dev) [dev]:                            ← Enter
Hostname (blank = auto-generate) []:                                ← Enter
Hostname prefix [deployeddigital]:                                  ← Enter
```

The auto-generated hostname will be `deployeddigital-dev-<id>` where `<id>` comes from Hetzner metadata or `/etc/machine-id`.

### SSH keys (at least one source required)

```
── SSH keys (at least one source required) ──
sshid.io id (https://sshid.io/<id>) []:                             mahakoala
GitHub username (github.com/<u>.keys) []:                           ← Enter (or your gh username)
```

The script will fetch your keys from those URLs and write them to `/home/maha/.ssh/authorized_keys` AND mirror to `/root/.ssh/authorized_keys` (append+dedupe — won't overwrite the cloud-panel-injected key).

### Homebrew & toolchain

```
── Homebrew & toolchain ──
Install Homebrew + CLI tools? [Y/n]                                 ← Enter for yes
```

This installs Linuxbrew under `/home/linuxbrew/.linuxbrew/` and provisions the default `BREW_PACKAGES` list (`starship`, `eza`, `tldr`, `zoxide`, `btop`, `fd`, `ripgrep`, `bat`, `git-delta`, `lazygit`, `glow`, `ranger`, `jq`, `yq`, `fzf`, `gh`, `node`, `oven-sh/bun/bun`, `pnpm`, `yarn`, `go`).

### Tailscale

```
── Tailscale ──
Install Tailscale? [Y/n]                                            ← Enter for yes

  Generate an auth key in the Tailscale admin:
    https://login.tailscale.com/admin/settings/keys
  Recommended: ephemeral + tagged (e.g. tag:vps) + 1-hour expiry.
  Make sure every tag you choose exists in tagOwners in your tailscale.json.

  Paste EITHER:
    (a) the auth key alone:    tskey-auth-XXXXXXXXXXXXXX
    (b) the full install line: curl -fsSL ... | sh && sudo tailscale up --auth-key=tskey-auth-XXX
  (the wizard will extract the key from (b) automatically)

Tailscale authkey (blank to install only):                          [paste either form]

  (Leave tags blank to use the tags baked into the auth key —
   safer than overriding, since extra tags must be in tagOwners.)
Override tags (comma-separated, blank = key default) []:            ← Enter (blank)
```

If you paste the full one-liner, the wizard says nothing (the extraction is silent). If you paste something that doesn't start with `tskey-`, it warns:

```
WARNING: that does not look like a Tailscale auth key (expected to start with tskey-).
Continue anyway? [y/N]
```

### Hardening

```
── Hardening ──
Run hardening (UFW + fail2ban + SSH lockdown) after bootstrap? [Y/n]   ← Enter
Open HTTP/HTTPS ports (80/443)? [y/N]                                  ← Enter (no by default)
```

### AI / agent tooling (optional)

```
── AI / agent tooling (optional) ──
Installs opencode, crush, codex, claude-code, ollama, lazygit, glow,
ranger, zoxide, btop, chafa, csvlens, tmuxai, tpm. Adds 5–10 minutes.
Install AI/agent tooling after hardening? [y/N]                        ← y if you want it
```

### Review

```
── Review ──
  user        : maha
  role        : dev
  hostname    : <auto>
  ssh sources : sshid.io/mahakoala
  homebrew    : yes
  tailscale   : yes ()
  authkey set : yes
  harden      : yes
  http/https  : closed
  ai tools    : yes

Proceed? [Y/n]                                                         ← Enter
```

---

## 3. The actual install (~10–15 minutes)

You'll see a lot of output. The high-level flow:

```
Wrote /etc/vps/bootstrap.env (mode 600)
Wrote /usr/local/sbin/vps-bootstrap.sh
Wrote /usr/local/sbin/vps-harden.sh
Wrote /usr/local/sbin/vps-tools.sh

▶ Running vps-bootstrap.sh
===== vps-bootstrap @ … =====
--- apt update + base packages ---
[apt fetching, ~30s]

--- hostname ---
… -> deployeddigital-dev-abc12345

--- user: maha ---
[adduser output]

--- homebrew ---
[brew installer, ~2 min]

--- brew install starship eza … ---
[STATUS] ok|brew starship|installed
[STATUS] ok|brew eza|installed
[STATUS] ok|brew tldr|installed
…
[STATUS] ok|brew oven-sh/bun/bun|installed via tap        ← bun via the official tap
…

▶ Running vps-harden.sh
===== vps-harden @ … =====
[apt install of openssh-server / ufw / fail2ban / etc.]

--- SSH hardening ---
[STATUS] ok|sshd config|drop-in written
[sshd reload]

--- UFW ---
Rules updated
Rules updated (v6)
Default incoming policy changed to 'deny'
Default outgoing policy changed to 'allow'
Rule added                ← 22/tcp public ssh
Rule added (v6)
Rule added                ← 41641/udp tailscale direct
Rule added (v6)
Rule added                ← tailscale0 interface
Firewall is active and enabled on system startup

--- fail2ban ---
[service start]

--- unattended-upgrades ---
[service start]

--- Tailscale ---
Installing tailscale...
[STATUS] ok|tailscale install|installed via tailscale.com/install.sh
Running: tailscale up --auth-key=<redacted> --hostname=deployeddigital-dev-abc12345 [...]
[STATUS] ok|tailscale up|joined as deployeddigital-dev-abc12345

✓ Joined tailnet:
    DNS:    deployeddigital-dev-abc12345.tailXXXX.ts.net
    IPv4:   100.123.45.67
    IPv6:   fd7a:115c:a1e0::1234
    SSH:    ssh maha@deployeddigital-dev-abc12345.tailXXXX.ts.net

--- SSH access summary ---
Status: active
22/tcp                     ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
Anywhere on tailscale0     ALLOW IN    Anywhere
PermitRootLogin = prohibit-password
  -> root SSH allowed (key-only); root keys mirrored from maha as recovery hatch
AllowUsers      = maha root

▶ Running vps-tools.sh
===== vps-tools @ … =====
Installing AI/agent tooling for: maha
--- code agents (brew taps) ---
[STATUS] ok|opencode|installed via tap
[STATUS] ok|crush|installed via tap

--- OpenAI Codex CLI ---
[STATUS] ok|@openai/codex|installed via npm

--- Anthropic Claude Code ---
[Claude Code installer output]
[STATUS] ok|claude-code|installed

--- terminal niceties ---
[STATUS] ok|brew lazygit|installed
[STATUS] ok|brew glow|installed
[STATUS] ok|brew ranger|installed
[STATUS] ok|brew zoxide|already installed
[STATUS] ok|brew btop|already installed
[STATUS] ok|brew chafa|installed
[STATUS] ok|brew csvlens|installed

--- tmuxai ---
[STATUS] ok|tmuxai|installed

--- tmux plugin manager ---
[STATUS] ok|tpm|cloned

--- system-wide tool symlinks ---
[STATUS] ok|symlink claude|/usr/local/bin/claude -> /home/maha/.local/bin/claude

--- Ollama (system daemon) ---
[Ollama installer output]
[STATUS] ok|ollama|installed
[STATUS] ok|ollama service|enabled
```

---

## 4. The install report

```
═══════════════════════════════════════════════════
  Done.
═══════════════════════════════════════════════════

── Install report ──
  ✓ ok:   34
  ! warn: 0
  ✗ fail: 0

Hostname : deployeddigital-dev-abc12345
User     : maha
Log      : /var/log/vps-bootstrap.log

Try:      ssh maha@62.238.30.99
Tailnet:  ssh maha@deployeddigital-dev-abc12345.tailXXXX.ts.net

AI tools installed under user 'maha'.
  For full per-user state:  sudo -iu maha   (then run claude / opencode / etc.)
  'claude' is also symlinked to /usr/local/bin/claude so root can run it too.

Re-run later:
  sudo /usr/local/sbin/vps-bootstrap.sh   # re-apply user/keys/brew
  sudo /usr/local/sbin/vps-harden.sh      # re-apply firewall/ssh/tailscale
  sudo /usr/local/sbin/vps-tools.sh       # install/refresh AI/agent tooling

To lock SSH to Tailscale-only after verifying tailnet access:
  sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
  sudo /usr/local/sbin/vps-harden.sh

Run VerifyChecklist.sh now to audit the install? [Y/n]
```

A clean run shows `ok: 30+`, `warn: 0`, `fail: 0`. If anything failed, those lines come first with retry recipes.

---

## 5. The verify (running automatically here)

Hit Enter at the prompt to run the audit:

```
── VerifyChecklist ──

▶ Last install: [STATUS] tally from /var/log/vps-bootstrap.log
    ok=34  warn=0  fail=0

▶ Hostname / OS
  ✓ hostname: deployeddigital-dev-abc12345
  ✓ os: Ubuntu 24.04.x LTS

▶ Disk space
  ✓ disk: / has 38GB free
  ✓ disk: /home has 38GB free
  ✓ disk: /var has 38GB free

▶ SSH config (effective)
  ✓ Port = 22
  ✓ PasswordAuthentication = no
  ✓ PubkeyAuthentication = yes
  ✓ KbdInteractiveAuthentication = no
  ✓ X11Forwarding = no
  ✓ PermitRootLogin = prohibit-password (key-only)
  ✓ AllowUsers = maha root

▶ authorized_keys per user
  ✓ root: 2 key(s) in /root/.ssh/authorized_keys
  ✓ maha: 2 key(s) in /home/maha/.ssh/authorized_keys

▶ UFW
  ✓ ufw active
  ✓ ssh path: public 22/tcp allowed
  ✓ ssh path: tailscale0 allowed

▶ fail2ban
  ✓ fail2ban service active
  ✓ sshd jail: currently_banned=0 total_banned=0

▶ unattended-upgrades
  ✓ service active

▶ Tailscale
  ✓ tailscale up: deployeddigital-dev-abc12345 @ 100.123.45.67
  ✓ tailnet peers visible: 5
  ✓ tailscale0 interface up: 100.123.45.67/32

▶ Homebrew (per-user)
  ✓ Homebrew 4.4.6 (under maha)

▶ Tool resolution in maha's login shell
  ✓ brew resolves
  ✓ node resolves
  ✓ npm resolves
  ✓ gh resolves
  ✓ starship resolves
  ✓ eza resolves
  ✓ bat resolves
  ✓ fzf resolves
  ✓ zoxide resolves
  ✓ claude resolves
  ✓ lazygit resolves

── Verify summary ──
  ✓ ok:   30
  ! warn: 0
  ✗ fail: 0

Result: PASS
Full install log: /var/log/vps-bootstrap.log
```

`Result: PASS` is what you want to see. `PASS with warnings` is fine for most cases (review the `!` items, decide if action is needed). `FAIL` means you need to look at the failed sections — each `✗` line tells you what failed.

---

## 6. Connect with your real user

Open a **second** terminal on your laptop **before closing the install one**:

```bash
# Public path (still allowed on first run):
ssh maha@62.238.30.99

# Tailnet path (preferred — works even after locking down):
ssh maha@deployeddigital-dev-abc12345.tailXXXX.ts.net
```

You should land in maha's login shell with the brew/AI tools on PATH:

```
maha@deployeddigital-dev-abc12345:~$ which brew claude eza node
/home/linuxbrew/.linuxbrew/bin/brew
/home/maha/.local/bin/claude
/home/linuxbrew/.linuxbrew/bin/eza
/home/linuxbrew/.linuxbrew/bin/node

maha@deployeddigital-dev-abc12345:~$ claude --version
2.1.128 (Claude Code)

maha@deployeddigital-dev-abc12345:~$ tailscale status
100.123.45.67   deployeddigital-dev-abc12345 maha@   linux   -
[other peers...]
```

If you get this far, the box is fully operational.

---

## 7. (Optional but recommended) Lock SSH to the tailnet

Once you've confirmed Tailscale SSH works, eliminate the public SSH attack surface:

```bash
# On the VPS as root:
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

Output:

```
--- UFW ---
[Rules reset; only tailnet path now]

--- SSH access summary ---
Anywhere on tailscale0     ALLOW IN    Anywhere
[no public 22/tcp rule]
PermitRootLogin = prohibit-password
AllowUsers      = maha root

OK: tailnet SSH rule verified; public 22/tcp removed
```

The script **refuses** to run this if Tailscale isn't connected — it won't lock you out. After it succeeds, public SSH is closed; only tailnet access works:

```bash
ssh maha@62.238.30.99                                              # connection refused
ssh maha@deployeddigital-dev-abc12345.tailXXXX.ts.net              # works
```

---

## 8. Day-1 sanity: things to try

```bash
ssh maha@deployeddigital-dev-abc12345.tailXXXX.ts.net

# Brew tools
btop                                                              # system monitor
eza --tree -L 2                                                   # pretty tree listing
lazygit                                                           # git TUI
fzf                                                               # fuzzy finder
gh auth status                                                    # GitHub CLI

# AI tools
claude --help
opencode --help
crush --help
codex --help
ollama list
ollama pull llama3.2:3b      # download a small model

# Tailscale
tailscale status
tailscale ip -4

# Verify is still re-runnable any time
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh)

# Or just the install report (faster):
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh) --report
```

---

## What's *not* normal

If your run looks like one of these, see [README_Troubleshooting.md](README_Troubleshooting.md):

- **`Address already in use`** during SSH hardening — orphan listener; current scripts handle this automatically via systemd-native cleanup. If you see it on a recent script version, the box may be in a weird state.
- **`systemd[1]: Caught <ABRT>`** broadcast → power-cycle is the only recovery. Older versions of the script could trigger this with raw `kill`; current version uses `systemctl reset-failed` + `systemctl stop` only.
- **`'tailscale up' failed`** with a tag-related error → tag isn't in `tagOwners` in your `tailscale.json`. Either add it to the policy or unset `TAILSCALE_TAGS` to use the auth key's own tags.
- **`WARN: failed bun`** → old `BREW_PACKAGES` had bare `bun`; now uses `oven-sh/bun/bun` (the official tap). Edit `/etc/vps/bootstrap.env` and re-run.
- **Install report shows `fail: <n>`** → each `✗` line names the failed step; the "How to retry individual items" block shows the recovery command.
- **Verify shows `Result: FAIL`** → look at the `✗` lines; each maps to a section in troubleshooting.

A typical fresh install on a Hetzner CX22 takes **~12 minutes** end-to-end (apt update + brew install dominate). If yours is hitting 30+ min, something is hanging — Ctrl-C, check the log at `/var/log/vps-bootstrap.log`, and consult troubleshooting.

---

## At a glance: what got installed where

| Where | What | Available to |
|---|---|---|
| `/etc/vps/bootstrap.env` | Single source of config (mode 600) | root only |
| `/etc/vps/secrets.env` | Optional API keys (you create this) | mode 600, sourced by `.profile` |
| `/usr/local/sbin/vps-{bootstrap,harden,tools}.sh` | Worker scripts (re-runnable) | root |
| `/etc/profile.d/homebrew.sh` | brew on PATH (cd-protected) | every user's login shell |
| `/etc/systemd/system/ssh.service.d/00-vps-killmode.conf` | KillMode override | systemd |
| `/etc/ssh/sshd_config.d/99-vps-hardening.conf` | SSH drop-in (validated, with rollback) | sshd |
| `/etc/sudoers.d/90-maha` | Passwordless sudo for VPS_USER | sudoers |
| `/home/linuxbrew/.linuxbrew/bin/` | brew, opencode, crush, codex, lazygit, eza, bat, … | every user (via profile.d) |
| `/home/maha/.local/bin/claude` (+ symlink at `/usr/local/bin/claude`) | Claude Code | every user, per-user state |
| `/usr/local/bin/{tmuxai,ollama}` | tmuxai, ollama | every user |
| `/home/maha/.tmux/plugins/tpm` | tmux plugin manager | maha |
| `/var/log/vps-bootstrap.log` | Combined log of every script run | root |

Re-running `vps-init.sh` (or any of the worker scripts directly) is **always safe** — they're idempotent. Anything already done is detected and skipped; anything new gets applied.
