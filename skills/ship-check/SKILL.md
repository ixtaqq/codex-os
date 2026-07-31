---
name: ship-check
description: Run the pre-ship verification pass before calling work done, opening a PR, committing, or deploying. Use when the user says ship it, is this ready, done?, before I push, or when finishing any non-trivial change. Checks build, tests, lint, and the diff itself, and reports failures verbatim rather than summarizing them away.
metadata:
  short-description: Verify before shipping
---

# Ship Check

The point is evidence, not reassurance. Every claim below must be backed by a command you actually
ran and output you actually read.

## Order

Cheapest signal first - stop and report as soon as something fails hard.

1. **Diff review.** `git status` then `git diff` (staged and unstaged). Look for: debug prints,
   commented-out code, hardcoded paths or secrets, `TODO` left in the change, files touched that
   have nothing to do with the task.
2. **Build / typecheck.** Whatever the project uses. If there is no build step, say so.
3. **Tests.** Run the suite, or the closest targeted subset if the suite is slow - and name which
   you ran.
4. **Lint / format.** Only if the project has it configured. Do not introduce a formatter.
5. **Run the actual path.** Execute the thing that changed at least once. A green test suite that
   never touches the new code proves nothing.

## Report

Emit exactly this shape:

```
Diff:   <n files, one line on what changed>
Build:  pass | fail | n/a  (<command>)
Tests:  pass | fail | n/a  (<command>, <n passed / n failed>)
Lint:   pass | fail | n/a  (<command>)
Ran:    <what you executed to prove it works>
Verdict: ready | not ready - <one sentence>
```

Rules:

- A step that was not run is `n/a` with the reason. Never `pass`.
- Failures get the real output pasted, not paraphrased.
- `not ready` on any hard failure. Do not soften it.
- Do not commit, push, or open a PR as part of this check unless the user asked.

## Notes

- Unrelated pre-existing failures: report them separately and say they predate the change (verify
  with `git stash` or by checking the base commit - do not assume).
- If the project has its own `AGENTS.md` verification steps, those win over this list.
