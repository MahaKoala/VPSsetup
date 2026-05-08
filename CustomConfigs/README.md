To restore on a new machine:

1. Install dependencies:
   - jq (brew install jq  /  apt install jq)
   - bc (usually preinstalled)

2. Copy the script:
   mkdir -p ~/.claude
   cp statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh

3. Add to ~/.claude/settings.json (merge with existing settings):
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline-command.sh"
     }
   }

   See settings.snippet.json for the full settings.json from the source machine.

4. Restart Claude Code.
