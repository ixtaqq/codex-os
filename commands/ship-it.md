Take the current change from "written" to "ready".

1. Run the `ship-check` skill and report its table verbatim.
2. If the verdict is `not ready`, fix what it found and re-run. Up to three rounds, then stop and
   report what remains.
3. When ready, propose — but do not run — the commit: the exact `git add` paths and a commit
   message whose subject line says what changed and why, under 72 characters.

Do not commit, push, or open a PR unless I say so in a following message.
