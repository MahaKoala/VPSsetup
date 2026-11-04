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
