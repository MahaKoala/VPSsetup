# First-Login Password Prompt

When the bootstrap creates the primary user (`$VPS_USER`), it does so with `useradd -m` and never sets a password. The account is therefore in a locked-password state — usable only via SSH key. That's safe, but it leaves one rough edge: the moment someone needs a password (sudo with `ENABLE_PASSWORDLESS_SUDO=0`, console rescue, switching from key-only to password-or-key auth, etc.), the account has none and the user has to remember to run `passwd` themselves.

This hook closes that gap. The first time the user lands in an interactive bash shell — whether via `ssh user@host`, `su user`, `su - user`, or a console login — it prompts them to set a password, then disables itself.

## Files involved

| Path | Purpose |
|---|---|
| `~/.firstlogin-passwd.sh` | The hook itself. Mode `700`, owned by `$VPS_USER`. Written by the bootstrap. |
| `~/.bashrc` | Has one appended line that sources the hook. |
| `~/.password_set` | Sentinel created on success. Its presence short-circuits the hook. |

## Behavior

The hook (sourced near the bottom of `~/.bashrc`) performs these checks in order:

1. **Non-interactive shell?** Returns immediately. The hook only runs when there's a TTY (`[ -t 0 ]`), so scripted shells, `bash -c`, and SFTP-only sessions are unaffected.
2. **Sentinel exists?** Returns immediately. After a successful password set, `~/.password_set` is dropped — the hook costs nothing on subsequent logins.
3. **`sudo -n passwd -S $USER`** is read to determine state:
   - `L` (locked) or `NP` (no password) → prompt the user.
   - `P` (valid password) → silently create the sentinel, never bother again.
   - Anything else (e.g. sudo refused) → do nothing this round.
4. **Prompt:** prints a short welcome, then calls `sudo passwd "$USER"`, which prompts the user to enter and confirm a new password. On success, the sentinel is created. On Ctrl-C or mismatch, no sentinel is written and the hook tries again next login.

`sudo -n` (non-interactive) and `sudo passwd` both depend on the user having NOPASSWD sudo, which the bootstrap already grants when `ENABLE_PASSWORDLESS_SUDO=1` (the default).

## Why a userland hook instead of `chage -d 0` / `passwd -e`

The standard "force password change at next login" mechanisms (`chage -d 0 user`, `passwd -e user`) rely on PAM detecting an expired password during account/session phases. This works reliably for SSH password auth, but `su user` from root often skips the expiration prompt entirely depending on the PAM stack. Worse, both mechanisms require the account to *have* a password to mark expired; a freshly-created locked account has nothing to expire.

The userland hook in `~/.bashrc` runs unconditionally on every interactive shell, regardless of how the user got there, and is independent of PAM configuration. It also gives the user a clear human-readable prompt rather than the terse "WARNING: Your password has expired" message.

## Where the bootstrap wires it in

- **`vps-bootstrap.sh`**, section **4b. First-login password prompt** — writes `~/.firstlogin-passwd.sh` and `chown`s/`chmod`s it.
- **`vps-bootstrap.sh`**, section **9. Shell niceties** — appends the source line to `~/.bashrc` via `append_line_if_missing`.
- **`vps-init.sh`** — same edits, mirrored inside the `BOOTSTRAP_EOF` heredoc that generates `vps-bootstrap.sh`.

Both copies must stay in sync.

## Customization

| To... | Do this |
|---|---|
| Disable for a specific user after bootstrap | `touch ~/.password_set` |
| Re-trigger the prompt (e.g. you want to set a new password) | `rm ~/.password_set && passwd -l $USER` then start a new shell |
| Change the welcome wording | Edit the `cat > "$FIRSTLOGIN" <<'HOOK'` block in both `vps-bootstrap.sh` and `vps-init.sh` |
| Skip the feature entirely | Remove the `4b` section and the matching `append_*` line from both scripts |

## Caveats

- **Shell must be bash.** `~/.bashrc` is bash-specific. If `VPS_USER_SHELL` is overridden to zsh/fish/etc., the hook needs to be sourced from that shell's rc file instead.
- **Requires NOPASSWD sudo.** If `ENABLE_PASSWORDLESS_SUDO=0`, `sudo -n passwd -S` fails and the hook silently does nothing — but in that scenario the operator has clearly opted into a different password-management workflow anyway.
- **Doesn't unlock the account itself.** `useradd` leaves the password locked (`!` in `/etc/shadow`); `sudo passwd $USER` sets a new password and unlocks it as a side effect. If for some reason the account remains locked after `passwd`, run `sudo passwd -u $USER`.
- **Sentinel is per-user.** If you re-create the user's home directory or wipe `~/.password_set`, the prompt will fire again on next login. That's intentional — you want it to fire when the home directory is fresh.
