---
name: project-bootstrap
description: Set up a repo to work well with Codex — add an AGENTS.md with the project's real conventions, a .codex/config.toml, and mark the project trusted. Use when starting a new project, when the user says bootstrap, scaffold, set up this repo, onboard this codebase, or when a repo has no AGENTS.md and repeated instructions keep being re-explained each session.
metadata:
  short-description: Wire a repo into the personal Codex OS
---

# Project Bootstrap

Templates live in `E:\Workspace\codex-os\templates\project\`. They are a starting point, not the
deliverable — a copied template with placeholders left in is worse than no file at all.

## Steps

1. **Read the repo first.** Package manifest, existing scripts, test config, CI workflow, directory
   layout. The whole value of `AGENTS.md` is the commands and conventions that are actually true
   here.

2. **Write `<repo>/AGENTS.md`** from `templates/project/AGENTS.md`. Fill in, from evidence:
   - stack and language versions,
   - the real build / test / lint commands (verify each one runs),
   - layout: where source, tests, and config live,
   - conventions the code already follows — naming, error handling, test style,
   - the verification bar for this repo.

   Delete every section you could not fill with something specific. Aim for under 50 lines.
   If `AGENTS.md` already exists, extend it — never overwrite.

3. **Add `<repo>/.codex/config.toml`** from the template only if the repo needs settings that differ
   from the global defaults (sandbox, model, reasoning effort, MCP servers). Skip it otherwise.

4. **Mark the project trusted** so Codex does not re-prompt. Append to `~/.codex/config.toml`:

   ```toml
   [projects.'<lower-case absolute path>']
   trust_level = "trusted"
   ```

   The key must be the lower-cased absolute path. Show the user the exact block and confirm before
   writing — this file is theirs.

5. **Report** which files were created, which commands you verified, and anything you could not
   determine and left out.

## Do not

- Do not invent commands you did not run.
- Do not restate global defaults (`E:\Workspace\codex-os\global\AGENTS.md`) in the project file.
  Project `AGENTS.md` is for what is *different* here.
- Do not add tooling, CI, or dependencies the user did not ask for.
