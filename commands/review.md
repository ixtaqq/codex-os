Review the current working diff (`git diff` plus staged changes; if the tree is clean, review the
last commit).

Report only defects that would change the code, in this order:

1. **Correctness** — logic that produces a wrong result, unhandled cases, broken invariants.
   For each, give the concrete input or state that triggers it and what goes wrong.
2. **Security** — injection, path traversal, secrets in code or logs, missing authz checks.
3. **Reuse** — code that duplicates something that already exists in this repo. Name the existing
   function and its path.
4. **Simplification** — genuinely simpler equivalents, not stylistic preferences.

Rules:

- Read enough surrounding code to confirm each finding before reporting it. Anything you could not
  confirm goes in a separate "unverified" list.
- No praise, no summary of what the diff does, no style nits the project does not enforce.
- If nothing survives verification, say exactly that.
