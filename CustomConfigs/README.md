# Claude Code statusline (Ava's setup)

Custom statusline for Claude Code showing:

- Model name (color-coded by family)
- Current working directory (with `~` for `$HOME`)
- Git branch + dirty file count
- Context window usage
- 5-hour and 7-day rate limits with pace arrows and time-to-reset
- Prompt cache hit rate

## Install

```bash
tar xzf claude-statusline-export.tar.gz
cd claude-statusline-export
./install.sh
```

Then restart Claude Code.

## What `install.sh` does

1. Checks for `jq` and `bc` (and bails out with a hint if either is missing).
2. Copies `statusline-command.sh` into `~/.claude/` and makes it executable.
3. Merges the `statusLine` block into `~/.claude/settings.json` using `jq`. If the file already exists, a timestamped backup is saved alongside it (`settings.json.bak.YYYYMMDD-HHMMSS`).

No manual JSON editing required.

## Dependencies

- `jq` — `brew install jq` (macOS) or `sudo apt install jq` (Debian/Ubuntu)
- `bc` — typically preinstalled

## Customising

The script honours `$CLAUDE_CONFIG_DIR` if set (otherwise uses `~/.claude`).

## Notes

- Designed for Claude Pro / Max plans (reads `rate_limits` from the statusline JSON).
- The script's `budget`, `usage`, and `sync` subcommands use BSD/macOS `sed -i ''` syntax and won't work on Linux without modification — but those are only used for API-plan budget tracking and aren't relevant for Pro/Max users.
