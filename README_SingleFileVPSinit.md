# One-line VPSsetup: providers without cloud-init

**The same worker scripts power every setup method.** The one-line installer is a small *orchestrator*, not a second embedded copy of the workers. It downloads each worker from the same repository ref and stores them in `/usr/local/sbin`. You can later run any worker individually. Network access to GitHub is needed on the first installation.

## Interactive one-liner

Log in through SSH or the provider console, then:

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | sudo bash
```

The installer asks for admin username, optional hostname, SSHID/GitHub key source, Homebrew, optional AI tools, and Tailscale. The fresh account has no password by default. Never close your existing root session before a new SSH-key login succeeds.

## Noninteractive one-liner

Supply a key source *before* running. Set `VPS_SETUP_REF` to a reviewed release/tag/SHA for reproducibility, or omit to use `main`.

```bash
sudo env VPS_USER=maha SSH_ID=mahakoala \
  VPS_HOSTNAME=hel4.deployed.digital NONINTERACTIVE=1 RUN_VERIFY=1 \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | bash'
```

The `VPS_SETUP_REF` value selects the worker versions. New configuration is saved at `/etc/vps/bootstrap.env` with mode `0600`. An existing configuration is preserved unless `OVERWRITE_CONFIG=1` is deliberately supplied.

## What the installer actually does

1. Downloads the shared `bootstrap.env` defaults when no saved configuration exists.
2. Saves a shell-escaped configuration and fetches `vps-swap.sh`, `vps-bootstrap.sh`, `vps-harden.sh`, `vps-tools.sh`, and `VerifyChecklist.sh`.
3. Runs swap, base bootstrap, and hardening, in that order.
4. Runs the optional full tools worker only when `INSTALL_TOOLS=1` and `INSTALL_BREW=1`.
5. **Separately**, runs the modular Crush worker only if `INSTALL_VIBECODE_CRUSH=1`. This does not require `INSTALL_TOOLS=1`.
6. Runs verification with `RUN_VERIFY=1` or for interactive installations.

Cloud-init calls **this same** `vps-init.sh` with its prewritten environment file. It does not contain or run a separate copy of bootstrap/harden logic.

## Independent workers

```bash
sudo /usr/local/sbin/vps-swap.sh           # RAM-aware swap only
sudo /usr/local/sbin/vps-bootstrap.sh      # packages, user, validated SSH keys
sudo /usr/local/sbin/vps-harden.sh         # SSH/UFW/Tailscale security
sudo /usr/local/sbin/vps-tools.sh          # optional developer tools (requires brew)
sudo /usr/local/sbin/VerifyChecklist.sh    # audit
```

All workers read `/etc/vps/bootstrap.env` when present; they do not depend on any cloud-init execution history. To run a single worker before the main installer, copy `bootstrap.env` to `/etc/vps/bootstrap.env`, edit the settings, and download just the requested worker.

## Configuration highlights

| Setting | Default | Meaning |
|---|---|---|
| `FIRST_LOGIN_PASSWORD_PROMPT` | `0` | SSH-key-only initial user; never invents a password |
| `SSH_ID_TYPED_KEYS` | `RSA ECDSA-SK` | Additional typed SSHID fetches; failure does not remove valid base keys |
| `SWAP_MODE` | `auto` | Independent RAM-aware swap worker; `off` skips |
| `SWAP_PERCENT` | `50` | 50% of detected RAM, bounded by configured minimum/maximum |
| `INSTALL_BREW` | `0` | Optional Homebrew |
| `INSTALL_TOOLS` | `0` | Optional complete agent suite; requires Homebrew |
| `INSTALL_VIBECODE_CRUSH` | `0` | **Optional Crush worker only**, separate from full agent suite |
| `CRUSH_MCP_PROFILE` | `core` | `none`, `core`, or `extended` MCPs |
| `CRUSH_LSP_PROFILE` | `web,python` | Selected language servers: `web,python,go,rust,none` |
| `CRUSH_INSTALL_ROOT` | `0` | Root Crush profile is opt-in; user account default |
| `PUBLIC_SSH_ALLOWED` | `1` | Leave public SSH available initially |
| `TAILNET_SSH_VERIFIED` | `0` | Must be `1` **after** a successful separate tailnet SSH login to disable public SSH |
| `TAILSCALE_AUTHKEY` | empty | Installs Tailscale; authenticate later without storing a permanent key in user-data |

## Optional modular AI setup (without cloud-init)

To install Crush **without** the full AI toolkit, select it explicitly at first boot:

```bash
sudo env VPS_USER=maha SSH_ID=mahakoala NONINTERACTIVE=1 \
  INSTALL_BREW=1 INSTALL_VIBECODE_CRUSH=1 \
  CRUSH_MCP_PROFILE=core CRUSH_LSP_PROFILE=web,python \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | bash'
```

This opt-in is independent of the minimal `cloud-init.yaml` defaults. If the user already exists, you can run just `vps-vibecode-crush.sh` instead. [See the Crush guide](README_VibecodeCrush.md).

## Tailscale and public SSH lockdown

Tailscale network access and **Tailscale SSH** are different permissions; the sample `tailscale.json` must be applied in your Tailscale admin portal and the VPS must have `tag:vps` for its policy to match.

After you have opened a second SSH session over Tailscale:

```bash
sudo sed -i 's/^PUBLIC_SSH_ALLOWED=.*/PUBLIC_SSH_ALLOWED="0"/' /etc/vps/bootstrap.env
echo 'TAILNET_SSH_VERIFIED="1"' | sudo tee -a /etc/vps/bootstrap.env
sudo /usr/local/sbin/vps-harden.sh
```

The hardener preserves unrelated UFW rules and manages the project SSH rules. Keep your original console session until new access works.

## Logs and recovery

```bash
sudo tail -n 100 /var/log/vps-bootstrap.log
sudo tail -n 100 /var/log/hetzner-firstboot.log    # cloud-init only
sudo /usr/local/sbin/VerifyChecklist.sh
```

See [Hetzner deployment guide](docs/HETZNER.md) and [troubleshooting](README_Troubleshooting.md).
