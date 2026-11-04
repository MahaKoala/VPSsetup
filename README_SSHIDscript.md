# SSHID public-key installation and rotation

VPSsetup supports both the base `sshid.io/<id>` response and type-specific endpoints. SSH public keys are never passwords; the server cannot authenticate a client unless that client has the matching private key.

## Automatic bootstrap

Set in `/etc/vps/bootstrap.env`:

```bash
SSH_ID="mahakoala"
SSH_ID_TYPED_KEYS="RSA ECDSA-SK"
SSH_GH_USER=""
SSH_AUTHORIZED_KEYS=""
```

The standalone `vps-bootstrap.sh` tries:

```text
https://sshid.io/mahakoala
https://sshid.io/mahakoala/RSA
https://sshid.io/mahakoala/ECDSA-SK
```

It verifies each public-key line using `ssh-keygen`, skips HTML/error pages or malformed lines, deduplicates by key type and payload, and mirrors valid keys to root's recovery account. A 404 from a typed endpoint does **not** delete or invalidate valid base keys.

Neither cloud-init nor the one-line installer is required when running the bootstrap independently:

```bash
sudo /usr/local/sbin/vps-bootstrap.sh
```

## Standalone key management

- [`addnew-sshid-key.sh`](addnew-sshid-key.sh) can create the target account if explicitly requested.
- [`addupdate-sshid-key.sh`](addupdate-sshid-key.sh) updates an existing account's `authorized_keys`.
- Supported typed key selectors include `RSA`, `ED25519`, `ECDSA` and `ECDSA-SK`. `ALL` requests all supported types.

```bash
# Example: add ECDSA-SK public key to an existing 'maha' account
sudo bash addupdate-sshid-key.sh -i mahakoala -u maha -t ECDSA-SK

# Example: create a different user and install available types
sudo bash addnew-sshid-key.sh -i mahakoala -u operator -c -t ALL
```

Every fetched line is validated, and unchanged keys aren't re-appended. Keep root console access while rotating/removing keys. This repo does **not** revoke old keys automatically; review and remove obsolete entries manually after confirming new access.

## Check fingerprints

On the server:

```bash
sudo ssh-keygen -lf /home/maha/.ssh/authorized_keys
```

On Windows PowerShell:

```powershell
Get-ChildItem "$env:USERPROFILE\.ssh\*.pub" | ForEach-Object { ssh-keygen -lf $_.FullName }
```

Compare fingerprints, not just key comments. A hardware-backed `ECDSA-SK` private-key stub and physical security key may be needed on the connecting workstation. See [Hetzner recovery](docs/HETZNER.md).
