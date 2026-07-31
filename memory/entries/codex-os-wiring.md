---
name: codex-os-wiring
description: codex-os skills reach Codex through directory junctions, not copies or a plugin install
type: decision
created: 2026-07-27
---

`~/.codex/skills/<name>` are Windows directory junctions pointing into
`E:\Workspace\codex-os\skills\<name>`. `global/AGENTS.md` is the one exception — it is copied to
`~/.codex/AGENTS.md` by `scripts/sync.ps1`, because a single file cannot be junctioned.

**Why:** junctions make edits live — change a `SKILL.md` and the next thread sees it, with no
reinstall step. Copies drift silently. The plugin path (`.codex-plugin/plugin.json` +
`~/.agents/plugins/marketplace.json`) is the official distribution mechanism but requires a
cachebuster bump and reinstall on every edit, which is the wrong trade for a repo edited daily.
Junctions work across volumes (E: to C:) without admin rights, unlike symlinks and hardlinks.

The plugin manifest exists in the repo but is deliberately **not registered** in any marketplace.
Registering it while the junctions exist would load every skill twice.

**Applies to:** all Codex work on this machine. See [[loop-status-contract]].
