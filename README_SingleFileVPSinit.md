
# Single-File VPS Init Script (Works Anywhere)

Quickstart:
ssh -t root@<ip> "bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)"

Already in SSH:
bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)

For providers without cloud-init (Contabo, RackNerd, most budget VPS hosts, or when you just want to skip Hetzner's user-data UI), the workflow becomes:

```
# 1. Copy the script to the fresh VPS
scp vps-init.sh root@<ip>:/root/

# 2. Run it as root (interactive)
ssh root@<ip> 'bash /root/vps-init.sh'
```

Or pipe it directly without copying:

```
ssh root@<ip> 'bash -s' < vps-init.sh
```

Or fully non-interactive for agents:

```
ssh root@<ip> "
  VPS_USER=pink \
  SSH_ID=mahakoala \
  VPS_ROLE=staging \
  TAILSCALE_AUTHKEY=tskey-auth-xxx \
  INSTALL_TOOLS=1 \
  RUN_VERIFY=1 \
  NONINTERACTIVE=1 \
  bash -s
" < vps-init.sh
```

The script is a single self-contained file that:

1. Prompts interactively (or reads env vars in `NONINTERACTIVE=1` mode)
2. Writes `/etc/vps/bootstrap.env`
3. Writes `/usr/local/sbin/vps-bootstrap.sh`, `/usr/local/sbin/vps-harden.sh`, and `/usr/local/sbin/vps-tools.sh` as embedded heredocs
4. Runs bootstrap + harden, plus vps-tools (only if `INSTALL_TOOLS=1`)
5. Prints an end-of-install report — tally of `[STATUS] ok / warn / fail` lines from the log, plus per-step warnings and failures with copy-pasteable retry recipes
6. Optionally runs `VerifyChecklist.sh` (interactive runs prompt; non-interactive runs opt in via `RUN_VERIFY=1`)
7. Leaves everything on disk so you can re-run any worker script later without re-downloading

### Opt-in env vars

| Var | Default | What it does |
|---|---|---|
| `INSTALL_TOOLS` | `0` | Install AI/agent tooling (opencode, crush, codex, claude-code, ollama, lazygit, etc.) after harden |
| `RUN_VERIFY` | unset | When non-interactive, set to `1` to run `VerifyChecklist.sh` at the end. Interactive runs always prompt regardless |
| `RUN_HARDEN` | `1` | Run hardening after bootstrap. Set `0` to skip (e.g. testing on a non-public box) |
| `TAILSCALE_TAGS` | unset | Override tags advertised on `tailscale up`. **Leave unset** to use whatever tags the auth key was generated with — overriding requires every tag be in `tagOwners` AND within the key's allowed set |

---


## Run  `vps-init.sh`


---

## Usage patterns

```
scp vps-init.sh root@<ip>:/root/
ssh root@<ip>
bash /root/vps-init.sh
```

The wizard walks through user, hostname, SSH key sources, Tailscale auth key, hardening, and AI tooling. Everything is printed for review before anything is changed.

```
ssh root@<ip> "
  VPS_USER=pink \
  SSH_ID=mahakoala \
  VPS_ROLE=staging \
  VPS_HOSTNAME_PREFIX=koala \
  TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxx \
  INSTALL_TOOLS=1 \
  RUN_VERIFY=1 \
  NONINTERACTIVE=1 \
  bash -s
" < vps-init.sh
```

Once `vps-init.sh` lives in a repo:

```
ssh root@<ip> "curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | \
  VPS_USER=pink SSH_ID=mahakoala TAILSCALE_AUTHKEY=tskey-... NONINTERACTIVE=1 bash"
```

Or with interactive mode preserved (note the `-t` for TTY allocation, so the wizard's prompts work over SSH):

```
ssh -t root@<ip> "bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh)"
```

For providers that boot with only a web console (Contabo, OVH, some RackNerd plans), paste the script contents and then:

```
cat > /root/vps-init.sh <<'EOF'
# ... paste contents ...
EOF
bash /root/vps-init.sh
```

---

## What lands on the VPS

|Path|Purpose|
|---|---|
|`/etc/vps/bootstrap.env`|Config; mode `0600` (contains Tailscale key until scrubbed)|
|`/usr/local/sbin/vps-bootstrap.sh`|User, hostname, SSH keys, Homebrew, base tooling|
|`/usr/local/sbin/vps-harden.sh`|SSH, UFW, fail2ban, unattended-upgrades, sysctl, Tailscale|
|`/usr/local/sbin/vps-tools.sh`|AI/agent tooling (opencode, crush, codex, claude-code, ollama, lazygit, etc.)|
|`/var/log/vps-bootstrap.log`|Combined log of all runs, including `[STATUS]` lines parsed by the install report|
|`/etc/profile.d/homebrew.sh`|System-wide `brew` on `PATH` (with `cd "$HOME"` guard for the Linuxbrew CWD bug)|
|`/etc/sudoers.d/90-<user>`|Passwordless sudo for your user|
|`/etc/ssh/sshd_config.d/99-vps-hardening.conf`|SSH drop-in (with `*.bak` snapshot if a previous version existed)|

---

## Re-running safely

Every piece is idempotent:

```
# Add more SSH keys / new brew packages / change hostname:
sudo nano /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-bootstrap.sh

# Refresh / install AI tooling:
sudo /usr/local/sbin/vps-tools.sh

# Tighten firewall to tailnet-only after verifying Tailscale works:
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

The harden script's safety guards (UFW lockout gate, sshd drop-in rollback on validation failure, `reload` instead of `restart` so existing sessions survive) all apply on every re-run.

---

## End-of-install report

After bootstrap → harden → tools, `vps-init.sh` parses `[STATUS]` lines from `/var/log/vps-bootstrap.log` and prints:

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

Every install attempt across the worker scripts emits one structured line per step (`[STATUS] <ok|warn|fail>|<step>|<detail>`), so the report shows you exactly what worked, what failed, and the recipe to retry each category. No more silent batch failures like *"some terminal tools failed"* without specifying which ones.

---

## Tailscale wizard

When the wizard reaches the Tailscale step, it explicitly tells you where to generate a key and accepts both paste forms:

```
── Tailscale ──
Install Tailscale? [Y/n]

  Generate an auth key in the Tailscale admin:
    https://login.tailscale.com/admin/settings/keys
  Recommended: ephemeral + tagged (e.g. tag:vps) + 1-hour expiry.
  Make sure every tag you choose exists in tagOwners in your tailscale.json.

  Paste EITHER:
    (a) the auth key alone:    tskey-auth-XXXXXXXXXXXXXX
    (b) the full install line: curl -fsSL ... | sh && sudo tailscale up --auth-key=tskey-auth-XXX
  (the wizard will extract the key from (b) automatically)
```

So you can copy the literal install line Tailscale's admin web shows you and paste it into the wizard — the `--auth-key=…` portion is extracted automatically. Both `--auth-key` and the older `--authkey` forms are recognised. A sanity check warns if what you pasted doesn't start with `tskey-`.

After successful `tailscale up`, the script prints a clean "joined" summary:

```
✓ Joined tailnet:
    DNS:    dev-deployeddigital-abc12345.tailXXXX.ts.net
    IPv4:   100.123.45.67
    IPv6:   fd7a:115c:a1e0::1234
    SSH:    ssh maha@dev-deployeddigital-abc12345.tailXXXX.ts.net
```

So you don't have to parse raw `tailscale status` to find the tailnet hostname.

---

## SSH-hardening robustness

The harden step has several guards against the common Ubuntu 24.04 footguns that have bitten earlier runs:

- **Mask `ssh.socket`** instead of just disabling — `disable --now` symlinks can be re-created by package operations; `mask` makes the unit a `/dev/null` symlink that survives apt.
- **Create `/run/sshd`** before `sshd -t`. The privsep dir is a tmpfs ephemeral and `sshd -t` runs before `ssh.service`'s `RuntimeDirectory=sshd` materialises it.
- **Smart `reload`-or-`start`**: SIGHUP if `ssh.service` is already active (preserves existing sessions for the operator), `start` on first transition off `ssh.socket`. On failure, prints `systemctl status` + last 25 journal lines + port listeners + three concrete remediation commands.
- **Orphan-listener cleanup**. `KillMode=process` on `ssh.service` leaves the master `sshd` listener alive after a failed start, blocking the next start with `Address already in use`. The script kills any process bound to `SSH_PORT` whose cmdline contains `[listener]` (per-connection sshds carrying live SSH sessions don't have that marker, so this is safe even from inside an SSH session) and runs `systemctl reset-failed ssh.service`.
- **Defaults block** for every optional `bootstrap.env` var, so partial / older env files don't trip `set -u` with `<var>: unbound variable`.

The AI tools step (`INSTALL_TOOLS=1`) installs everything under the configured user (`$VPS_USER`), then creates `/usr/local/bin/claude` as a symlink to `~/.local/bin/claude` so root can also invoke it (per-user `$HOME` state is preserved). All other AI binaries (`opencode`, `crush`, `codex`, `tmuxai`, `ollama`) land in paths that are already on every user's PATH, so no extra symlinks are needed for those.

---

## Verification

`vps-init.sh` prompts at the end (interactive runs) or runs unattended with `RUN_VERIFY=1` (non-interactive). You can also run it on demand:

```
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/VerifyChecklist.sh)
```

Useful flags:

- `--quiet` / `-q` — only print warnings, failures, and the final summary (cron/CI-friendly)
- `--report` / `-r` — only print the install `[STATUS]` tally from `/var/log/vps-bootstrap.log` and exit
- `--help`

Each check goes through `ok`/`warn`/`fail` helpers that tally; final verdict prints `Result: PASS / PASS with warnings / FAIL` and the script exits non-zero if any check failed. Validates each `sshd -T` field individually, checks UFW SSH paths, verifies `tailscale0` is up *and* has an IP, spot-checks login-shell PATH resolution for `claude` / `eza` / `bat` / etc. — catches the "installed but not in PATH" regression.

---

## One caveat worth calling out

When you paste or `scp` this script, the Tailscale authkey (if supplied) will be written to `/etc/vps/bootstrap.env` at mode `600`. The harden script **scrubs it after successful `tailscale up`**, but:

- If you take a VPS snapshot _before_ the first successful `tailscale up`, the key is in the snapshot.
- Prefer **ephemeral** + **tagged** + **reusable-off** auth keys from the Tailscale admin console, expiring in 1 hour. That way even a leaked key is worthless.
- The tag(s) chosen at key generation MUST already be in `tagOwners` in your `tailscale.json` ACL. The script does NOT pass `--advertise-tags` by default — it lets the key's own tags speak for themselves, which is the safe path. Set `TAILSCALE_TAGS` only if you specifically want to override (and every tag is in `tagOwners`).
