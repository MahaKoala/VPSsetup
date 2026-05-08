# Claude Code statusline (Ava's setup)

Custom statusline for Claude Code showing:

- Model name (color-coded by family)
- Current working directory (with `~` for `$HOME`)
- Git branch + dirty file count
- Context window usage
- 5-hour and 7-day rate limits with pace arrows and time-to-reset
- Prompt cache hit rate
  EXAMPLE:                 
  │ Opus 4.7 (1M) │ Model + 1M-context variant. Amber = Opus family. 
  │ ~                      │ Current dir is $HOME (you're not in a project subdir right now).                                           
  │ ctx 13%                │ This conversation has filled 13% of the model's 1M-token context window.                                    
  │ [5hr] 4h : 7% : 3%↑ 2h │ 5-hour Max quota — see breakdown below.                                                   
  │ [7d] 117h : 25% : 30%↓ │ 7-day Max quota — see breakdown below.                                                   
  │ cache 99%              │ 99% of input tokens were served from prompt cache. Excellent.                             
                                                                                           
  Decoding the [5hr] triple 4h : 7% : 3%↑ 2h:                                                                              
                                                                                           
  - 4h — time until the 5-hour window resets (a bit over 4 hours).                                                         
  - 7% — you've used 7% of your 5-hour quota.                                              
  - 3% — only 3% of the 5-hour window has elapsed (≈ 9 minutes since it started).                                          
  - ↑ — red warning arrow. You used 7% of quota in 3% of time. Projected: exhaust well before reset.                       
  - 2h — at this burn rate, you'll hit 100% in about 2 hours.                                                              
                                                                                                                           
  Decoding the [7d] triple 117h : 25% : 30%↓:                                                                              
                                                                                                                           
  - 117h — about 4.9 days until the weekly window resets.                                                                  
  - 25% — quarter of weekly quota used.  
  - 30% — 30% of the week has elapsed (≈ 50 hours in).                                                                     
  - ↓ — green, under-consuming. Projected to finish around 83% — comfortably under cap. (No time-left figure because we
  don't expect to run out.)                                                                                                
                                                                                           
  The actionable signal here: your 5-hour window is hot — you're burning faster than time is passing, and at the current   
  pace you have about 2 hours of work before you hit the 5h cap (which you'd then have to wait ~4h to reset). The 7-day
  picture is fine; just the short window is.                                                                               
                                                                                           
  Practical levers if you want to slow the 5h burn: keep using 1M context (high cache hit rate is helping a lot — that 99% 
  means most input is essentially free), avoid forcing fresh expensive operations (large WebFetch payloads, big tool
  dumps), and prefer Sonnet for routine work if not needing Opus depth. 

  Pace arrow legend (from the script): ↑ red = will exhaust before reset, → yellow = on pace, ↓ green = under-consuming.
## Install

```bash
wget https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/CustomConfigs/claude-statusline-export.tar.gz
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
