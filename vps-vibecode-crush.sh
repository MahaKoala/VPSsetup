#!/usr/bin/env bash
# vps-vibecode-crush.sh — configure Charm Crush for vibe-coding workflows
#
# Sets up the GLOBAL Crush config (~/.config/crush/) for both root and
# $VPS_USER, plus opt-in PROJECT-level templates:
#
#   global  crush.json                      Anthropic provider, Sonnet/Haiku
#                                           models, Tier 1 MCPs (filesystem,
#                                           memory, sequential-thinking,
#                                           context7, fetch, git), 6 LSPs
#   global  commands/{plan,ship,review,
#                     debug,scaffold}.md    universal slash commands
#   global  templates/frontend.crush.json   Tier 2 (playwright + shadcn)
#   global  templates/deploy.crush.json     Tier 3 (github docker+PAT, vercel,
#                                           cloudflare-workers, neon, supabase,
#                                           sentry)
#
# Also installs the LSP binaries and `uv` (for uvx-based MCPs) via brew + npm.
# Crush itself is expected to already be installed by vps-tools.sh
# (brew tap charmbracelet/tap/crush).
#
# Project opt-in (run in a project's repo root):
#   cp ~/.config/crush/templates/frontend.crush.json ./crush.json
#   # or merge both:
#   jq -s '.[0] * .[1]' ~/.config/crush/templates/frontend.crush.json \
#                       ~/.config/crush/templates/deploy.crush.json \
#                       > ./crush.json
#
# Crush deep-merges global + project mcp blocks, so the project layer ADDS
# to Tier 1 rather than replacing it. Commit ./crush.json so the team gets
# the same MCPs; put any keys/PATs in ./.crush.local.json (gitignored).
#
# Usage:
#   sudo /usr/local/sbin/vps-vibecode-crush.sh
#   sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-vibecode-crush.sh)
#
# Idempotent. Re-running OVERWRITES global crush config files to a known-good
# state. Project-level ./crush.json files are never touched.

set -Eeuo pipefail

# Root check first — /etc/vps/bootstrap.env is mode 600.
[[ $EUID -eq 0 ]] || { echo "Must run as root (try: sudo $0)"; exit 1; }

ENV_FILE="${ENV_FILE:-/etc/vps/bootstrap.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE — run vps-bootstrap.sh first"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

[[ -n "${VPS_USER:-}" ]] || { echo "VPS_USER not set in $ENV_FILE"; exit 1; }
id -u "$VPS_USER" &>/dev/null || { echo "User $VPS_USER does not exist; run vps-bootstrap.sh first"; exit 1; }

LOG=/var/log/vps-bootstrap.log
exec > >(tee -a "$LOG") 2>&1

echo "===== vps-vibecode-crush @ $(date -Is) ====="
echo "Configuring Crush for: root and $VPS_USER"

_st() { printf '[STATUS] %s|%s|%s\n' "$1" "$2" "${3:-}"; }

# ---------------------------------------------------------------------------
# 1. Install LSP binaries + uv as $VPS_USER.
#
# Brew installs land on the shared linuxbrew prefix (already on root's PATH
# via /etc/profile.d/linuxbrew.sh in vps-bootstrap.sh), so installing once
# as $VPS_USER makes the binaries available to root too. Same for npm
# globals when npm's prefix is brew's node prefix.
# ---------------------------------------------------------------------------
echo "--- installing LSP binaries + uv ---"
sudo -Hu "$VPS_USER" bash -l -s <<'INNER_EOF'
set +e
cd "$HOME"

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
else
    echo "[STATUS] fail|brew|not found at /home/linuxbrew/.linuxbrew/bin/brew — skipping"
    exit 0
fi

_st() { printf '[STATUS] %s|%s|%s\n' "$1" "$2" "${3:-}"; }

# brew formulas: uv (provides uvx for fetch+git MCPs), ruff (Python LSP),
# gopls (Go LSP), rust-analyzer (Rust LSP).
for pkg in uv ruff gopls rust-analyzer; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
        _st ok "brew $pkg" "already installed"
    elif brew install "$pkg"; then
        _st ok "brew $pkg" "installed"
    else
        _st warn "brew $pkg" "install failed"
    fi
done

# npm globals: vtsls (TS LSP — replaces typescript-language-server),
# biome (lint/format LSP), basedpyright (Python LSP — pyright fork).
if command -v npm >/dev/null; then
    for pkg in @vtsls/language-server @biomejs/biome basedpyright; do
        if npm i -g "$pkg" >/dev/null 2>&1; then
            _st ok "npm $pkg" "installed"
        else
            _st warn "npm $pkg" "install failed"
        fi
    done
else
    _st warn "npm" "not found; skipping JS/Python LSPs (vtsls, biome, basedpyright)"
fi

if command -v crush >/dev/null; then
    _st ok "crush" "$(crush --version 2>&1 | head -1)"
else
    _st warn "crush" "binary not found — run vps-tools.sh to install"
fi
INNER_EOF

# ---------------------------------------------------------------------------
# 2. Stage config files in a temp dir, then copy to both root's and
#    $VPS_USER's $HOME/.config/crush/. Single source = no drift between
#    the two installs.
# ---------------------------------------------------------------------------
echo "--- staging crush config ---"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE"/{commands,templates}

# Global crush.json — Anthropic provider, Tier 1 MCPs only, all 6 LSPs.
# Single-quoted heredoc → no shell interpolation here. $ANTHROPIC_API_KEY
# and $HOME are interpolated by Crush at config-load time, so they resolve
# per-user when each user runs `crush`.
cat > "$STAGE/crush.json" <<'CRUSH_JSON'
{
  "$schema": "https://charm.land/crush.json",

  "providers": {
    "anthropic": { "api_key": "$ANTHROPIC_API_KEY" }
  },

  "models": {
    "large": { "provider": "anthropic", "model": "claude-sonnet-4-6" },
    "small": { "provider": "anthropic", "model": "claude-haiku-4-5-20251001" }
  },

  "permissions": {
    "allowed_tools": ["view", "ls", "glob", "grep"]
  },

  "options": {
    "tui": { "theme": "charm" },
    "context_paths": [
      "CRUSH.md",
      "AGENTS.md",
      "CLAUDE.md",
      ".cursor/rules/*.md",
      ".github/copilot-instructions.md"
    ],
    "data_directory": ".crush"
  },

  "mcp": {
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$HOME"]
    },
    "memory": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    },
    "sequential-thinking": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "fetch": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "git": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-server-git"]
    }
  },

  "lsp": {
    "typescript": {
      "command": "vtsls",
      "args": ["--stdio"],
      "filetypes": ["ts", "tsx", "js", "jsx", "mjs", "cjs"]
    },
    "biome": {
      "command": "biome",
      "args": ["lsp-proxy"],
      "filetypes": ["js", "jsx", "ts", "tsx", "json", "jsonc"]
    },
    "python": {
      "command": "basedpyright-langserver",
      "args": ["--stdio"],
      "filetypes": ["py"]
    },
    "ruff": {
      "command": "ruff",
      "args": ["server"],
      "filetypes": ["py"]
    },
    "go": {
      "command": "gopls",
      "filetypes": ["go"]
    },
    "rust": {
      "command": "rust-analyzer",
      "filetypes": ["rs"]
    }
  }
}
CRUSH_JSON

# --- slash commands ---

cat > "$STAGE/commands/plan.md" <<'PLAN_MD'
---
description: Produce a numbered implementation plan before editing
---

Produce a numbered implementation plan for: $ARGUMENTS

Before writing the plan:
1. Read the relevant code/files to ground yourself in the current state. Don't assume — verify.
2. Note constraints you discover (existing tests, conventions, dependencies, framework idioms).
3. List any open questions where the requirement is ambiguous.

Output format:
- **Goal** — one sentence restating what we're building.
- **Steps** — numbered list. Each step names the file path(s) it touches and what changes.
- **Tests** — what to verify and how (existing test command, manual check, or new test to add).
- **Open questions** — only if something is genuinely ambiguous.

Do NOT begin editing. Wait for confirmation or feedback on the plan first.
PLAN_MD

cat > "$STAGE/commands/ship.md" <<'SHIP_MD'
---
description: Review diff, run tests, commit, push, open PR
---

Ship the current branch. Steps:

1. Run `git status` and `git diff` to see all pending changes. Run `git log --oneline -10` to match the repo's commit style.
2. Detect and run the project's test command (check package.json scripts, Makefile, pyproject.toml, go.mod, Cargo.toml). If tests fail, STOP and report — do not commit failing code.
3. Stage relevant files explicitly by path. Never `git add -A` — it can sweep in secrets, build artifacts, or scratch files.
4. Write a conventional-commit message: `<type>(<scope>): <subject>` (≤72 chars), followed by a body that covers **what changed**, **why**, and any **caveats or follow-ups**. Match the depth of a chat summary, not a one-liner.
5. Commit using a HEREDOC for the message. Do NOT add a Co-Authored-By trailer.
6. Push to origin. If the branch has no upstream, use `git push -u origin <branch>`.
7. Open a PR with `gh pr create`. Title = commit subject. Body = `## Summary` (1–3 bullets) + `## Test plan` (checklist).

Hard rules:
- Never push to `main`/`master` without explicit confirmation.
- Never use `--no-verify`, `--force`, or `--amend` unless I ask.
- If a pre-commit hook fails, fix the underlying issue and create a NEW commit — do not amend.
SHIP_MD

cat > "$STAGE/commands/review.md" <<'REVIEW_MD'
---
description: Review pending changes for bugs, security, perf, style
---

Review the pending changes on this branch.

1. Find the merge base: `git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master`. Then `git diff <base>..HEAD` for the full diff. If there are uncommitted changes too, include `git diff` and `git status`.
2. For each changed file, look for:
   - **Bugs** — logic errors, off-by-one, wrong async handling, mishandled errors, broken edge cases.
   - **Security** — injection (SQL/command/XSS), auth/authz gaps, secrets in code, unsafe deserialization, SSRF, missing input validation at trust boundaries.
   - **Performance** — N+1 queries, unbounded loops, missing indexes, sync I/O on hot paths, leaked resources.
   - **Consistency** — divergence from surrounding code's conventions (naming, error patterns, layering).
   - **Test coverage** — untested behavior, especially error paths.
3. For each finding, give: `path:line — issue — suggested fix`.
4. Group output by severity: **Blockers** (must fix before merge) / **Warnings** (should fix) / **Nits** (taste/optional).
5. End with one sentence: ship-ready or not, and why.

Do NOT make edits. This is a review, not a refactor.
REVIEW_MD

cat > "$STAGE/commands/debug.md" <<'DEBUG_MD'
---
description: Reproduce, root-cause, and fix an error
---

Debug: $ARGUMENTS

1. **Reproduce.** Run the failing command/test/scenario yourself. If you can't reproduce from the description alone, ask for exact repro steps before guessing.
2. **Locate.** Find the failing code path. Read the actual files — don't assume from stack traces.
3. **Bisect if regression.** If this used to work, run `git log --oneline -30` on the relevant files. If the introducing commit isn't obvious, use `git bisect run <test-cmd>` to find it.
4. **Hypothesize.** State your hypothesis for the root cause in one sentence BEFORE writing any fix. Distinguish symptom from cause.
5. **Fix minimally.** Apply the smallest change that fixes the root cause. No drive-by refactors. No defensive try/catches that hide the real issue.
6. **Add a regression test** if the codebase has tests and the bug is reproducible in code.
7. **Verify.** Re-run the original failing scenario. Confirm it passes. Run the broader test suite to check you didn't break anything else.
8. **Report.** One paragraph: what was broken, why, what you changed, what to watch for.
DEBUG_MD

cat > "$STAGE/commands/scaffold.md" <<'SCAFFOLD_MD'
---
description: Generate a feature following existing repo conventions
---

Scaffold: $ARGUMENTS

1. **Learn the conventions first.** Find 2–3 of the most similar existing features and read them end-to-end. Note: file layout, naming, how routes/handlers/components are wired, error handling patterns, test structure, import style, type conventions.
2. **Plan briefly.** List the files you'll create or touch and which existing pattern each one mirrors. One bullet each.
3. **Generate.** Build the feature matching those patterns *exactly*. Do not introduce new abstractions, libraries, or styles. Three similar lines is better than a premature helper.
4. **Wire it up.** Routes registered, exports added, types exported, migrations created, tests stubbed (or written if the codebase has good test coverage of similar features).
5. **Verify it builds.** Run typecheck/build/lint. Fix any errors before reporting done. Don't ship code that doesn't compile.
6. **Report.** What you created (paths), what conventions you followed, and any TODOs you intentionally left for follow-up.

Do not invent new patterns. If you think a convention is wrong, flag it as an open question — don't unilaterally change it.
SCAFFOLD_MD

# --- project templates ---

cat > "$STAGE/templates/frontend.crush.json" <<'FRONTEND_JSON'
{
  "$schema": "https://charm.land/crush.json",
  "mcp": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    },
    "shadcn": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "shadcn@latest", "mcp"]
    }
  }
}
FRONTEND_JSON

cat > "$STAGE/templates/deploy.crush.json" <<'DEPLOY_JSON'
{
  "$schema": "https://charm.land/crush.json",
  "mcp": {
    "github": {
      "type": "stdio",
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "$GITHUB_TOKEN" }
    },
    "vercel": {
      "type": "http",
      "url": "https://mcp.vercel.com"
    },
    "cloudflare-workers": {
      "type": "sse",
      "url": "https://workers.mcp.cloudflare.com/sse"
    },
    "neon": {
      "type": "http",
      "url": "https://mcp.neon.tech/mcp"
    },
    "supabase": {
      "type": "http",
      "url": "https://mcp.supabase.com/mcp"
    },
    "sentry": {
      "type": "http",
      "url": "https://mcp.sentry.dev/mcp"
    }
  }
}
DEPLOY_JSON

# ---------------------------------------------------------------------------
# 3. Deploy staged files to each user's $HOME/.config/crush/.
# ---------------------------------------------------------------------------
deploy_to_user() {
    local target_user=$1
    local target_home target_group dest
    target_home=$(getent passwd "$target_user" | cut -d: -f6)
    target_group=$(id -gn "$target_user")
    [[ -d "$target_home" ]] || { _st fail "config $target_user" "home $target_home not found"; return; }

    dest="$target_home/.config/crush"
    mkdir -p "$dest/commands" "$dest/templates"
    cp -f "$STAGE/crush.json"        "$dest/crush.json"
    cp -f "$STAGE/commands/"*.md     "$dest/commands/"
    cp -f "$STAGE/templates/"*.json  "$dest/templates/"

    chown -R "$target_user:$target_group" "$target_home/.config/crush"
    _st ok "config $target_user" "$dest"
}

deploy_to_user root
deploy_to_user "$VPS_USER"

# ---------------------------------------------------------------------------
# 4. Operator-facing summary. Anthropic API key is the one thing this script
#    can't supply — flag it explicitly rather than silently leaving Crush
#    broken at first run.
# ---------------------------------------------------------------------------
echo
echo "===== vps-vibecode-crush done ====="
echo
echo "Required next step (per user, in their shell rc):"
echo "    export ANTHROPIC_API_KEY=sk-ant-..."
echo
echo "Project opt-in (Tier 2/3) — from a project's repo root:"
echo "    cp ~/.config/crush/templates/frontend.crush.json ./crush.json"
echo "  or merge both:"
echo "    jq -s '.[0] * .[1]' \\"
echo "        ~/.config/crush/templates/frontend.crush.json \\"
echo "        ~/.config/crush/templates/deploy.crush.json \\"
echo "        > ./crush.json"
echo
echo "Caveats on the deploy template:"
echo "  - github uses docker + PAT; export GITHUB_TOKEN=ghp_... before \`crush\`."
echo "    With a Copilot subscription, swap the github block to:"
echo '      {"type":"http","url":"https://api.githubcopilot.com/mcp"}'
echo "  - vercel/neon/supabase/sentry are remote OAuth — browser flow on first use."
echo "  - cloudflare MCPs are per-service; this template includes Workers."
echo "    Add others from https://docs.mcp.cloudflare.com/ as needed."
echo "  - linear/slack/gmail are NOT included; Claude.ai integrations cover them."
