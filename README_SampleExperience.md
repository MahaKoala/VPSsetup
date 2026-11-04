# Sample Experience — portable VPSsetup (current)

This walkthrough illustrates the **current shared-worker installer** rather than the previous embedded 70 KB wizard. Command output is illustrative; the exact hostname and keys depend on your configuration.

## Entry point A — Hetzner cloud-init

1. Create a Hetzner Ubuntu 24.04 VPS, selecting a known-good public SSH key.
2. Open [cloud-init.yaml](cloud-init.yaml) and set `VPS_USER`, `VPS_HOSTNAME` and `SSH_ID`.
3. Copy the whole file (starting `#cloud-config`) into Hetzner's Cloud config field.
4. Boot; the wrapper downloads `vps-init.sh` and the shared workers.

```text
=== VPSsetup: main ===
Downloading shared standalone worker scripts
=== Stage 1: dynamic swap ===
[swap] RAM=3806MB; creating 1903MB at /swapfile
=== Stage 2: OS packages, user, SSH keys ===
--- User: maha ---
  + valid key from sshid.io/mahakoala
=== Stage 3: SSH, UFW, Tailscale, security ===
=== Stage 5: verification ===
=== VPSsetup finished ===
```

The exact RAM number is read from `/proc/meminfo`; it is **not hardcoded**. If an endpoint such as `sshid.io/mahakoala/RSA` returns non-key data, the bootstrap ignores invalid content and retains existing valid keys.

## Entry point B — Any Linux VPS without cloud-init

Log in as root in the provider console, then:

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | sudo bash
```

The installer asks for an admin username, SSH key source, optional hostname, Tailscale authentication, and optional Homebrew/AI packages. It creates `/etc/vps/bootstrap.env` and downloads the same workers used by Hetzner.

For noninteractive operation:

```bash
sudo env VPS_USER=maha SSH_ID=mahakoala NONINTERACTIVE=1 RUN_VERIFY=1 \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | bash'
```

## Validate SSH-key-only login

The new account has **no default password**. First verify server-side keys:

```bash
sudo ssh-keygen -lf /home/maha/.ssh/authorized_keys
sudo passwd -S maha
sudo sshd -T | grep -E 'passwordauthentication|pubkeyauthentication'
```

From another machine, connect with its matching private key. In Windows PowerShell:

```powershell
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no maha@YOUR_SERVER_IP
```

If you see a password prompt without the two `-o` flags, it is not a password the installer created. Check key fingerprints and the client-side identity selection. Do not close your root console until a **new session** succeeds.

## Tailscale and optional lockdown

Tailscale may be installed but not authenticated if `TAILSCALE_AUTHKEY` is empty. You can join interactively:

```bash
sudo tailscale up --ssh --operator=maha --accept-routes --accept-dns=false
```

If Tailscale SSH access is denied, verify both TCP/22 network grants and SSH policy, plus device tag `tag:vps` in your active Tailscale admin policy. The example [tailscale.json](tailscale.json) does not automatically apply itself.

After a **second working tailnet SSH session**, set `PUBLIC_SSH_ALLOWED=0` and `TAILNET_SSH_VERIFIED=1` in `/etc/vps/bootstrap.env` and rerun `vps-harden.sh`.

## Optional tools and independent maintenance

Homebrew and agent tools are not installed in the lightweight cloud-init example by default. Set `INSTALL_BREW=1`, `INSTALL_BREW_PACKAGES=1` and `INSTALL_TOOLS=1` to opt in, then rerun the relevant workers.

```bash
sudo /usr/local/sbin/vps-swap.sh
sudo /usr/local/sbin/vps-bootstrap.sh
sudo /usr/local/sbin/vps-harden.sh
sudo /usr/local/sbin/vps-tools.sh
sudo /usr/local/sbin/VerifyChecklist.sh
```

There is no cloud-init requirement for those commands. Logs are in `/var/log/vps-bootstrap.log`; Hetzner's cloud-init wrapper also logs to `/var/log/hetzner-firstboot.log`.

For troubleshooting and recovery, see [the Hetzner deployment guide](docs/HETZNER.md) and [README_Troubleshooting.md](README_Troubleshooting.md).
