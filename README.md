# codex-os

A personal operating system for Codex, as a folder. Skills, loops, standards, templates, and memory
live here; `~/.codex` points back at them, so every project on this machine gets them.

## How it is wired

`scripts/sync.ps1` creates a Windows **directory junction** at `~/.codex/skills/<name>` for each
folder in `skills/`. Junctions are live: edit a `SKILL.md` here and the next Codex thread sees it,
with no reinstall. The one exception is `global/AGENTS.md`, which is *copied* to `~/.codex/AGENTS.md`
because a single file cannot be junctioned — re-run sync after editing it.

## The three commands

Wire everything up (idempotent, safe to re-run):

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Workspace\codex-os\scripts\sync.ps1
```

Check the wiring:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Workspace\codex-os\scripts\doctor.ps1
```

Validate the repository itself:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Workspace\codex-os\scripts\validate.ps1
```

Run a loop:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Workspace\codex-os\scripts\loop.ps1 -Loop repo-health
```

`sync.ps1` takes `-DryRun` and `-Force`. `loop.ps1` takes `-DryRun`, `-MaxIterations`, and
`-IntervalSeconds`. Each loop run records its Codex session ID and resumes that exact session on
later passes, so concurrent Codex work cannot be picked up by accident.

## Layout

| Path | What it is |
| --- | --- |
| `global/AGENTS.md` | Personal defaults loaded into every session, everywhere |
| `skills/` | Reusable workflows Codex triggers on its own — one folder each, junctioned into `~/.codex/skills` |
| `commands/` | Prompt bodies you invoke by hand (`review`, `debug`, `ship-it`) |
| `loops/` | Loop definitions (`*.loop.md`) for headless, repeating work |
| `scripts/` | `sync`, `doctor`, `loop`, `schedule-loop`, plus the loop status schema |
| `SPEC.md`, `ROADMAP.md`, `TASKS.md` | Requirements, phase boundaries, and validated work |
| `codex-home/agents/` | Read-only Codex role layers copied into `~/.codex/agents/` |
| `templates/` | Starters: project `AGENTS.md`, project `.codex/config.toml`, new skill |
| `vendor/` | Third-party skill repos, cloned as-is. `enabled.txt` picks which ones go live |
| `memory/` | Durable decisions — one fact per file, `INDEX.md` on top |
| `logs/` | Loop run output. Generated, gitignored |
| `.codex-plugin/` | Packaging manifest. Dormant — see below |

## Skills that ship with it

| Skill | Fires when |
| --- | --- |
| `loop-runner` | Work needs repeated passes — "keep going until", polling, grinding tests green |
| `project-bootstrap` | A repo needs an `AGENTS.md` and Codex settings |
| `memory-keeper` | Something is worth remembering across sessions |
| `ship-check` | Before calling a change done, committing, or deploying |

## Vendored skills

`vendor/` holds upstream skill repos; `vendor/enabled.txt` decides which are junctioned into
`~/.codex/skills`. **42 vendored skills are live** — mattpocock's `engineering/` + `productivity/`,
karpathy's guidelines, all of taste-skill, and six curated ECC skills for verification, loops,
GitHub operations, security, repository scanning, and skill audits. ECC's unified-memory skill is
vendored but off because `memory-keeper` remains the canonical memory system here. Hyperframes is
vendored but off; every skill in it needs the hyperframes CLI and Remotion.

Enable or disable by editing `enabled.txt`, then:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Workspace\codex-os\scripts\sync.ps1 -Force
```

`-Force` is required to unlink a disabled skill; without it sync reports it as `STALE` and leaves it.
It is also required before sync overwrites a changed `~/.codex/AGENTS.md`; sync saves its previous
contents as `~/.codex/AGENTS.md.bak`. Unlinking removes the junction only — the vendored files are never touched. Details and update
commands: [vendor/README.md](vendor/README.md).

Never edit anything under `vendor/`. To customize an upstream skill, copy it into `skills/`.

## Adding things

**A skill** — copy `templates/skill/SKILL.md` into `skills/<name>/SKILL.md`, set frontmatter `name`
to the folder name, write the `description` as *when to use this* (it is the only text Codex reads
before deciding), then run `sync.ps1`.

**A loop** — copy a file in `loops/`, set `cwd` and a checkable `exit_when`, run
`loop.ps1 -Loop <name> -DryRun` first. Format: `loops/_schema.md`.

**A command** — drop a markdown prompt in `commands/`.

**A memory** — ask Codex to remember it; the `memory-keeper` skill handles the file and the index.

## Scheduling

```bash
powershell -NoProfile -File E:\Workspace\codex-os\scripts\schedule-loop.ps1 -Loop repo-health -Daily 09:00
```

Tasks land under `\CodexOS\` in Task Scheduler. `-List` shows them, `-Remove` unregisters one.
Registering may need an elevated shell.

## The plugin manifest

`.codex-plugin/plugin.json` is valid and passes the bundled validator, so this folder can be
published as a Codex plugin later without restructuring. It is deliberately **not** registered in
any marketplace — junctions plus an installed plugin would load every skill twice. Register it only
if you drop the junctions first.

## Requirements

Windows PowerShell 5.1 (no `pwsh` needed), Codex CLI installed. Junctions work across volumes
without admin rights; only `schedule-loop.ps1` may require elevation.
