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
