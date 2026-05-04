

# SSH Key Installer with User Auto-Creation

Updated script adds a `-c` / `--create-user` flag. When enabled, it ensures the target user exists (defaulting the username to the sshid itself) and grants sudo privileges.

## Run `addnew-sshid-key.sh`
For new user

## Key behaviors

|Flags|Target user|
|---|---|
|_(none)_|`root`|
|`-c`|`$SSHID` (e.g. `mahakoala`)|
|`-u pink`|`pink`|
|`-u pink -c`|`pink` (created if missing)|

When `-c` is passed and the user doesn't exist:

1. **Username validation** — rejects anything that's not `^[a-z_][a-z0-9_-]{0,31}$`.
2. **Home dir created** with `adduser --disabled-password` on Debian/Ubuntu, or `useradd -m` + `passwd -l` on RHEL/Alpine/others.
3. **Password is locked** — the account can only be accessed via SSH key.
4. **Default shell**: `/bin/bash` (override with `--shell /usr/bin/zsh` etc.).
5. **Sudo group**: added to `sudo` (Debian/Ubuntu) or `wheel` (RHEL/Arch), whichever exists.
6. **Passwordless sudo**: on by default via `/etc/sudoers.d/90-<user>`, validated with `visudo -cf` before install. Disable with `--no-nopasswd`.

If the user already exists, `-c` only ensures sudo group membership and sudoers entry — it won't recreate or touch the home directory.

- Refuses to operate on any existing user with UID < 1000 (except explicit `root`).
- Refuses invalid usernames outright.
- Falls back gracefully if neither `sudo` nor `wheel` group exists (warns instead of failing).
- `visudo -cf` is run against the new sudoers file before it's trusted; on syntax error it's rolled back and the script aborts.

## Usage

```
# Create user 'mahakoala' with sudo + install RSA key
sudo bash add-sshid-key.sh -c

# Create user 'pink', install all sshid key types for mahakoala into pink
sudo bash add-sshid-key.sh -i mahakoala -u pink -c -t ALL

# Create user but require password for sudo
sudo bash add-sshid-key.sh -c --no-nopasswd
# One-liner recovery via curl (e.g. from web console)
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/add-sshid-key.sh \
  | sudo bash -s -- -i mahakoala -c
```

## Verify afterwards

```
# From the VPS
id mahakoala
sudo -l -U mahakoala
cat /home/mahakoala/.ssh/authorized_keys

# From your laptop
ssh mahakoala@<vps-ip>
# inside: sudo -n true && echo "passwordless sudo works"
```


# SSH Key Installer Update (preexisting user) Script

A hardened, idempotent script that wraps your sequence into something safer to run repeatedly and across different SSH id sources.

## Run `addupdate-sshid-key.sh`
For existing user (maha)


## Save and run

```
# Save it once
sudo install -m 0755 /dev/stdin /usr/local/sbin/add-sshid-key.sh <<'EOF'
# ... paste script above ...
EOF

# Default: install mahakoala/RSA into root
sudo add-sshid-key.sh

# Install into a non-root user
sudo add-sshid-key.sh -u maha

# Fetch ALL key types
sudo add-sshid-key.sh -i mahakoala -t ALL

# Different id, different user, skip reload
sudo add-sshid-key.sh -i someone -u maha -t ED25519 --no-reload
```

## What it does beyond your original snippet

|Original behavior|Script improvement|
|---|---|
|`grep -qxFf file1 file2` checks each line of file1 against any line of file2, but the shortcut "present → skip, else append whole file" meant a single new key would re-append the whole file.|Dedupes **line-by-line**, so partial overlaps don't duplicate existing keys.|
|Hard-coded `root` user|`-u USER` flag; resolves real `$HOME` via `getent`; fixes ownership to that user.|
|Hard-coded `RSA`|`-t RSA|
|No validation of fetched content|Rejects HTML/error pages that aren't SSH keys.|
|Temp file left on failure|`trap` cleans up on any exit path.|
|`systemctl reload ssh` only|Falls back to `sshd.service`; warns (rather than fails) if neither exists. Notes that reload isn't actually required since `sshd` re-reads `authorized_keys` on every login.|
|Blind `chmod/chown`|`install -d -m 700 -o USER -g USER` creates `~/.ssh` with correct ownership from the start.|
|No logging|Colored `[ok]`, `[warn]`, `[fail]` output and a final summary.|
|No error handling|`set -Eeuo pipefail`, arg validation, curl timeouts, and a clear error on bad sshid.|

## Integration with your `vps-init.sh`

You can drop this in as a helper that the bootstrap script calls, or use it standalone for quick recovery:

```
# Recover access to a VPS where you only have console/web-shell:
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/add-sshid-key.sh \
  | sudo bash -s -- -i mahakoala -u root
```



---