# Crush Vibe-Coding Setup (`vps-vibecode-crush.sh`)

Configures [Charm Crush](https://github.com/charmbracelet/crush) on a VPS for structured vibe-coding, deployment, and agentic workflows. Installs LSP binaries, writes a global config (MCP servers, models, slash commands), and stages opt-in project templates for fuller stacks. Sets everything up for **both** `root` and `$VPS_USER` so `crush` works the same regardless of which account invokes it.

Quickstart (after `vps-bootstrap.sh` and `vps-tools.sh` have run):

```
sudo bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-vibecode-crush.sh)
```

Then per-user, in your shell rc:

```
export ANTHROPIC_API_KEY=sk-ant-...
```

That's it — `crush` from any directory and you have Tier 1 MCPs + 6 LSPs + 5 slash commands ready.

---

## What it does

1. Sources `/etc/vps/bootstrap.env` for `$VPS_USER` (must be run as root because the env file is mode 600).
2. Installs LSP binaries + `uv` once as `$VPS_USER` so brew/npm globals land on the shared `linuxbrew` prefix that root also has on PATH:
   - **brew:** `uv`, `ruff`, `gopls`, `rust-analyzer`
   - **npm -g:** `@vtsls/language-server`, `@biomejs/biome`, `basedpyright`
3. Stages config files in a single temp dir, then deploys to **both** `/root/.config/crush/` and `/home/$VPS_USER/.config/crush/`. Single source-of-truth = no drift.
4. Emits `[STATUS] ok|warn|fail` lines into `/var/log/vps-bootstrap.log` so `vps-init.sh`'s end-of-install report picks them up alongside the rest.

The Crush binary itself is installed by `vps-tools.sh` (via `brew tap charmbracelet/tap/crush`); this script just configures it. If `crush` isn't on PATH it logs a `[STATUS] warn` and continues — config still gets written.

## File layout (per user)

```
~/.config/crush/
├── crush.json                       # global: providers, models, MCPs, LSPs, perms
├── commands/
│   ├── plan.md                      # /plan — numbered impl plan before editing
│   ├── ship.md                      # /ship — diff → tests → commit → PR
│   ├── review.md                    # /review — diff-aware bug/sec/perf review
│   ├── debug.md                     # /debug — repro → bisect → fix → verify
│   └── scaffold.md                  # /scaffold — feature gen following conventions
└── templates/
    ├── frontend.crush.json          # Tier 2: playwright + shadcn (opt-in per project)
    └── deploy.crush.json            # Tier 3: github + vercel + cloudflare-workers
                                     #         + neon + supabase + sentry (opt-in)
```

## What's in the global `crush.json`

- **Provider:** Anthropic, key from `$ANTHROPIC_API_KEY` env (interpolated by Crush at load time, so the file stays committable).
- **Models:** `claude-sonnet-4-6` as `large`, `claude-haiku-4-5-20251001` as `small`. If Crush's bundled model list rejects an ID, run `crush` and use `/models` to pick interactively — the choice persists.
- **Tier 1 MCP servers** (every project, no creds needed):
  - `filesystem` — sandboxed file ops, rooted at `$HOME` (Crush interpolates per-user).
  - `memory` — knowledge-graph persistence across sessions.
  - `sequential-thinking` — structured reasoning for multi-step tasks.
  - `context7` — version-pinned library docs at query time. Defeats stale-training-data hallucinations; the single biggest quality win for vibe-coding.
  - `fetch` — URL → markdown.
  - `git` — local repo introspection (log, diff, blame) without shelling out.
- **LSPs** (6, dual-server where it helps):
  - `vtsls` + `biome` for TS/JS — vtsls for type info (replaces typescript-language-server in 2026, much faster on monorepos), biome for fast lint/format.
  - `basedpyright` + `ruff` for Python — basedpyright restores Pylance-only features over plain pyright; ruff for lint/format.
  - `gopls` for Go, `rust-analyzer` for Rust.
- **Permissions:** read-only by default (`view`, `ls`, `glob`, `grep`). Crush still prompts for edits and shell. Add `"edit"`, `"write"`, or `bash(...)` patterns once you trust it.
- **Context paths:** auto-loads `CRUSH.md`, `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/*.md`, `.github/copilot-instructions.md` into every session.

## Project opt-in (Tier 2/3)

Templates stay out of the global config so every session doesn't pay for MCPs the project doesn't need. Opt in per-repo:

```
# Frontend project (playwright + shadcn)
cp ~/.config/crush/templates/frontend.crush.json ./crush.json

# Full-stack project — merge both then trim what you don't use
jq -s '.[0] * .[1]' \
    ~/.config/crush/templates/frontend.crush.json \
    ~/.config/crush/templates/deploy.crush.json \
    > ./crush.json
# Then edit ./crush.json — delete neon OR supabase, vercel OR cloudflare, etc.
```

Crush deep-merges global + project `mcp` blocks, so the project layer **adds** to Tier 1 rather than replacing it. Commit `./crush.json` so the team gets the same MCPs; put any keys/PATs in `./.crush.local.json` (gitignored).

## Resolved Design Decisions

- **Tier 1 global, Tier 2/3 project** — every session pays the cost (npx cold-start, model context tokens) of every configured MCP. Tier 1 (filesystem / memory / git / context7 / sequential-thinking / fetch) is broadly useful and zero-cred. Tier 2 (playwright, shadcn) and Tier 3 (deploy/infra) are stack-specific — a Go backend project gets nothing from shadcn — so they're staged as templates the operator opts into per-repo. Templates live in `~/.config/crush/templates/` rather than as commented blocks in the global config because Crush's JSON parser doesn't reliably handle JSONC comments across versions.
- **Dual install for root and `$VPS_USER`** — matches the `claude-statusline` pattern from `vps-tools.sh`. The script stages once into a `mktemp -d`, then `cp -f` deploys to both `$HOME/.config/crush/` paths, then `chown -R "$user:$group"` on each user's tree. Same source-of-truth file in both places means no drift if the script is re-run.
- **LSPs installed once as `$VPS_USER`, not duplicated for root** — brew lands on the shared `linuxbrew` prefix that root has on PATH via `vps-bootstrap.sh`'s `/etc/profile.d/linuxbrew.sh`. Brew's `node` puts npm's global prefix under `/home/linuxbrew/.linuxbrew`, also shared. So `vtsls`, `biome`, `basedpyright` installed by `$VPS_USER` are immediately on root's PATH too. No need to run `npm i -g` twice.
- **`uv` is a prerequisite, not optional** — `fetch` and `git` MCPs use `uvx mcp-server-{fetch,git}` (the canonical Python implementations from `modelcontextprotocol/servers`). Node alternatives exist but quality varies; the official Python ones are the path of least surprise. `uv` ships as a brew formula and cold-starts much faster than `pipx`.
- **GitHub MCP is docker + PAT, not the Copilot remote endpoint** — `https://api.githubcopilot.com/mcp` requires a GitHub Copilot subscription, which most users don't have. The docker-based `ghcr.io/github/github-mcp-server` runs locally with a `GITHUB_PERSONAL_ACCESS_TOKEN` env var, no subscription needed. The README/script comments show the swap-in syntax for users who do have Copilot.
- **Remote OAuth MCPs (vercel, neon, supabase, sentry)** — these vendors all ship official remote MCP endpoints that handle OAuth in-browser on first connect, so no keys need to live in `crush.json`. Better security posture than the older PAT-in-config pattern.
- **Cloudflare deploy template only includes Workers** — Cloudflare's MCPs are fragmented per-service (Workers, R2, DNS, Zero Trust, Vectorize each have their own endpoint). Including all of them would bloat every project that just wants edge deploys. Workers covers the common case; the README points users at `https://docs.mcp.cloudflare.com/` to add others.
- **`linear`/`slack`/`gmail`/`drive`/`calendar` deliberately excluded** — these are typically already wired up via Claude.ai integrations at the user/workspace level. Duplicating them in Crush would force the user to OAuth twice and would split memory (e.g. drafts saved in one wouldn't appear in the other). The README/script comments call this out so future-you doesn't add them back by reflex.
- **`$ANTHROPIC_API_KEY` not sourced from `bootstrap.env`** — keys belong in shell rc (or a secrets manager), not in a mode-600 file that's also bundled into cloud-init `user-data` and persisted under `/var/lib/cloud/instances/`. The script prints a clear next-step reminder rather than silently leaving the user with a non-working `crush`.
- **Tee to `/var/log/vps-bootstrap.log` + `[STATUS]` lines** — same protocol as the rest of the suite, so `vps-init.sh`'s end-of-install report includes vibecode-crush's results in the tally automatically. No special-casing.
- **`cp -f` overwrites global config on re-run** — explicitly idempotent: re-running the script always restores config to a known-good state. Project-level `./crush.json` files are NEVER touched, so per-project customization survives. The header comment makes this loud so an operator who's hand-edited `~/.config/crush/crush.json` knows their changes will be lost on re-run.
- **Read-only default permissions** — `allowed_tools: ["view", "ls", "glob", "grep"]` means Crush prompts for everything else (edits, shell, writes). Better default for unattended VPS use; operators graduate to broader perms once they trust the agent. `--yolo` and `permissions.skip_requests: true` are documented as escape hatches but not enabled.

## Caveats

- **Anthropic key required** — without `$ANTHROPIC_API_KEY` in env, `crush` fails at startup. The script prints the export line in its summary; the operator has to paste their own key.
- **GitHub MCP needs `GITHUB_TOKEN`** — only matters if you opt the project into the deploy template. The token needs `repo` + `workflow` scopes for full functionality.
- **First MCP launch is slow** — `npx -y` and `uvx` download packages on first invocation per user (`~/.npm/_npx`, `~/.cache/uv`). Subsequent launches are cached and fast.
- **Browser OAuth flows on remote MCPs** — vercel/neon/supabase/sentry open a browser on first use. On a headless VPS, `crush` prints a URL for the operator to open locally; the OAuth callback completes via device-code flow.
- **Custom edits to `~/.config/crush/crush.json` get overwritten** — re-running `vps-vibecode-crush.sh` restores global config. If you want persistent customization, do it at the project level (`./crush.json`) where this script never reaches.
