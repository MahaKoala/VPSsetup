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
