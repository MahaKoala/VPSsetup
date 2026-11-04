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
