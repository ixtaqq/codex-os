# Commands

Reusable prompt bodies. Paste one into a thread, or feed it straight to Codex:

```powershell
Get-Content E:\Workspace\codex-os\commands\review.md -Raw | codex exec -
```

These are prompts, not skills: a skill triggers on its own when the situation matches, a command
runs when you invoke it. Anything you find yourself typing twice belongs here; anything Codex
should reach for unprompted belongs in `skills/`.
