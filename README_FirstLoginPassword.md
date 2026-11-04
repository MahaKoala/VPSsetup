# SSH-key-only accounts and optional first-login password prompt

VPSsetup creates `$VPS_USER` with `useradd -m`. New accounts do **not** get a default password. A password-locked Linux account can still authenticate with authorized SSH public keys when OpenSSH is configured appropriately.

## Recommended default: SSH-key-only

`FIRST_LOGIN_PASSWORD_PROMPT=0` is the default in `bootstrap.env` and `cloud-init.yaml`. The bootstrap removes its own `~/.firstlogin-passwd.sh` if it exists, leaves a newly created account without a password, and uses `ALLOW_PASSWORD_AUTH=no` and `KbdInteractiveAuthentication no` through `vps-harden.sh`.

**Do not expect a password to be assigned**. A password prompt from your SSH client usually means it has not offered a matching private key; compare `ssh-keygen -lf ~/.ssh/authorized_keys` on the server with public-key fingerprints on your workstation. To avoid the fallback prompt:

```bash
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no maha@SERVER_IP
```

For existing Linux users, switching this flag does not automatically delete a previously set password; it disables the project-generated first-login prompt. OpenSSH password authentication is disabled separately by the hardening worker.

## Opt-in password prompt

Set `FIRST_LOGIN_PASSWORD_PROMPT=1` in `/etc/vps/bootstrap.env`, then run `sudo /usr/local/sbin/vps-bootstrap.sh`. For users who specifically want it, the worker creates `~/.firstlogin-passwd.sh`, sourced by `~/.vps-shell.sh` in interactive Bash shells. It prompts once and creates `~/.password_set` on successful password creation. It requires `ENABLE_PASSWORDLESS_SUDO=1`. It is **not** needed for SSH-key authentication.

To disable it later, set the flag back to `0` and rerun only the bootstrap worker. You do **not** need cloud-init or the full installer.

## Verify

```bash
sudo passwd -S "$USER"          # L: password locked, P: password set
sudo sshd -T | grep -E 'passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication'
sudo /usr/local/sbin/VerifyChecklist.sh
```

The installer never generates or prints a default password. Keep Hetzner's console or another verified root session open until a new SSH-key login has been tested.
