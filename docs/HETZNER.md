# Hetzner Cloud deployment and recovery

This guide covers Ubuntu 24.04 on Hetzner, but VPSsetup uses the **same independent workers** on providers without cloud-init. Neither individual workers nor the one-line installer require cloud-init.

## Cloud-init installation

1. Create the server with Ubuntu 24.04 and pre-register your public SSH key in Hetzner's SSH Keys section. Keep Hetzner's console available as a recovery path.
2. Open [cloud-init.yaml](../cloud-init.yaml). Set `VPS_USER`, `VPS_HOSTNAME`, `SSH_ID` and, if desired, `VPS_SETUP_REF` (a pinned Git SHA or reviewed tag is recommended).
3. Copy the **entire file**, starting with `#cloud-config`, into Hetzner's Cloud config field. It must be smaller than **32 KiB**.
4. Boot the VPS. Cloud-init writes `/etc/vps/bootstrap.env` and starts `/usr/local/sbin/hetzner-firstboot.sh`. That script fetches **the exact same** `vps-init.sh` used by the one-line installer.
5. Check the install and SSH key fingerprints before closing your original console.

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/hetzner-firstboot.log
sudo tail -n 100 /var/log/vps-bootstrap.log
sudo /usr/local/sbin/VerifyChecklist.sh
```

Defaults: new admin user with **no password**, SSH public keys fetched and validated, root SSH key recovery, dynamic swap sized from real RAM, SSH/UFW/Fail2Ban/unattended upgrades, Tailscale installed. Docker, Homebrew and AI tools are opt-in.

## Generic provider without cloud-init

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | sudo bash
```

For unattended operation, specify at least one key source:

```bash
sudo env VPS_USER=maha SSH_ID=mahakoala NONINTERACTIVE=1 RUN_VERIFY=1 \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | bash'
```

The installer downloads scripts to `/usr/local/sbin`. Each script can also be downloaded or rerun separately with `ENV_FILE=/etc/vps/bootstrap.env`.

## SSHID and Windows keys

`SSH_ID=mahakoala` fetches the base URL `https://sshid.io/mahakoala` and optionally attempts `/RSA` and `/ECDSA-SK` as configured by `SSH_ID_TYPED_KEYS`. The typed endpoints may return unexpected responses. Only syntactically valid OpenSSH public keys are imported; existing valid keys are preserved.

**A Linux account password is never generated.** If Windows falls back to a password prompt, compare key fingerprints:

```powershell
Get-ChildItem "$env:USERPROFILE\.ssh\*.pub" | ForEach-Object { ssh-keygen -lf $_.FullName }
ssh -vvv -o PreferredAuthentications=publickey -o PasswordAuthentication=no maha@YOUR_SERVER_IP
```

On the VPS:

```bash
sudo ssh-keygen -lf /home/maha/.ssh/authorized_keys
sudo sshd -T | grep -E 'passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication'
```

Never paste a private key into cloud-init, GitHub, logs, or a chat.

## Tailscale: network reachability vs Tailscale SSH

The `tailscale.json` file is an **example policy only**; it is not automatically applied. Admin-to-VPS SSH needs a network grant for TCP/22 and an SSH grant. The device must carry `tag:vps` for those example rules to match. Apply and verify the rules in the Tailscale admin console first.

If Tailscale was installed but not yet connected:

```bash
sudo tailscale up --ssh --operator=maha --accept-routes --accept-dns=false
```

A one-time auth key may be used instead; prefer prompting securely over storing it in cloud-init user-data. A successfully joined tailnet is not proof that your identity can SSH.

Only **after** opening a second, working SSH session over Tailscale, set:

```bash
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
echo 'TAILNET_SSH_VERIFIED="1"' | sudo tee -a /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

Keep the first root console session open. `vps-harden.sh` does not reset unrelated UFW rules.

## A failed cloud-init does not require rebuilding

If `cloud-init status --long` shows a `scripts_user` / `runcmd` error, inspect the first-boot log. A past error stays recorded until cloud-init state is reset; **do not run `cloud-init clean` on a live instance simply to clear the status**.

A common mistake is setting `BASE` to a file URL ending in `cloud-init.yaml` and then appending `/vps-bootstrap.sh`: that always returns 404. `BASE` must be a directory such as:

```text
https://raw.githubusercontent.com/MahaKoala/VPSsetup/main
```

For manual recovery on an already running VPS, download the one-line installer and reuse the saved config:

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh \
  -o /root/vps-init.sh
sudo bash -n /root/vps-init.sh
sudo NONINTERACTIVE=1 bash /root/vps-init.sh
```

The workers are intended to be re-runnable; review any custom UFW rules, SSH drop-ins, or server-specific changes before applying hardening again.

## Production validation

- Test `ssh -o PasswordAuthentication=no USER@HOST` with the expected private key from a second machine/session.
- Check `sshd -T`, `ufw status`, `fail2ban-client status sshd`, and Tailscale access.
- Verify active swap with `swapon --show` (unless `SWAP_MODE=off`).
- Run `VerifyChecklist.sh` and review warnings.
- Ensure DNS `A` / `AAAA` records for your chosen hostname are configured separately.
- Never include long-lived auth keys in cloud-init; user-data is persisted on the server by cloud-init.
