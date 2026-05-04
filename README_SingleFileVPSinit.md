
# Single-File VPS Init Script (Works Anywhere)

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
  NONINTERACTIVE=1 \
  bash -s
" < vps-init.sh
```

The script is a single self-contained file that:

1. Prompts interactively (or reads env vars in `NONINTERACTIVE=1` mode)
2. Writes `/etc/vps/bootstrap.env`
3. Writes `/usr/local/sbin/vps-bootstrap.sh` and `/usr/local/sbin/vps-harden.sh` as embedded heredocs
4. Runs both
5. Leaves everything on disk so you can re-run `vps-bootstrap.sh` or `vps-harden.sh` later without re-downloading

---


## Run  `vps-init.sh`


---

## Usage patterns

```
scp vps-init.sh root@<ip>:/root/
ssh root@<ip>
bash /root/vps-init.sh
```

The wizard walks through user, hostname, SSH key sources, Tailscale auth key, and hardening. Everything is printed for review before anything is changed.

```
ssh root@<ip> "
  VPS_USER=pink \
  SSH_ID=mahakoala \
  VPS_ROLE=staging \
  VPS_HOSTNAME_PREFIX=koala \
  TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxx \
  TAILSCALE_TAGS=tag:vps,tag:staging \
  NONINTERACTIVE=1 \
  bash -s
" < vps-init.sh
```

Once `vps-init.sh` lives in a repo:

```
ssh root@<ip> "curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | \
  VPS_USER=pink SSH_ID=mahakoala TAILSCALE_AUTHKEY=tskey-... NONINTERACTIVE=1 bash"
```

Or with interactive mode preserved (note the `</dev/tty`):

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
|`/etc/vps/bootstrap.env`|Config; mode `0600` (contains Tailscale key until scrubbed)|
|`/usr/local/sbin/vps-bootstrap.sh`|User, hostname, SSH keys, Homebrew, base tooling|
|`/usr/local/sbin/vps-harden.sh`|SSH, UFW, fail2ban, unattended-upgrades, sysctl, Tailscale|
|`/var/log/vps-bootstrap.log`|Combined log of all runs|
|`/etc/profile.d/homebrew.sh`|System-wide `brew` on `PATH`|
|`/etc/sudoers.d/90-<user>`|Passwordless sudo for your user|
|`/etc/ssh/sshd_config.d/99-vps-hardening.conf`|SSH drop-in|

---

## Re-running safely

Every piece is idempotent:

```
# Add more SSH keys / new brew packages / change hostname:
sudo nano /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-bootstrap.sh

# Tighten firewall to tailnet-only after verifying Tailscale works:
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

---

## Verification

```
ssh pink@<ip>
hostnamectl
brew doctor
tailscale status
sudo ufw status verbose
sudo fail2ban-client status sshd
systemctl status unattended-upgrades
tail -n 100 /var/log/vps-bootstrap.log
```

---

## One caveat worth calling out

When you paste or `scp` this script, the Tailscale authkey (if supplied) will be written to `/etc/vps/bootstrap.env` at mode `600`. The harden script **scrubs it after successful `tailscale up`**, but:

- If you take a VPS snapshot _before_ the first successful `tailscale up`, the key is in the snapshot.
- Prefer **ephemeral** + **tagged** + **reusable-off** auth keys from the Tailscale admin console, expiring in 1 hour. That way even a leaked key is worthless.

