# Codex OS specification

## Purpose

Codex OS is a personal Windows-first operating layer for Codex: reusable skills,
explicit workflows, bounded loops, durable memory, and safe installation wiring.

## Required behavior

- Keep this repository as the source of truth for skills, global guidance, loops,
  commands, templates, and memory.
- Keep Codex runtime state, credentials, sessions, caches, and logs out of Git.
- Make installation idempotent and previewable before changing `~/.codex`.
- Never silently overwrite a changed installed global guidance file.
- Give loops explicit exit conditions, budgets, and resumable session identity.
- Validate skill metadata, loop definitions, vendor selections, and repository shape.
- Preserve project-specific instructions instead of replacing them with global defaults.

## Boundaries

This repository targets Windows PowerShell 5.1 and Codex installations that use
`~/.codex`. Cross-platform support is a future portability concern, not a reason
to weaken the current Windows wiring.

It does not manage credentials, Codex history, runtime databases, downloaded
plugin state, or third-party source contents under `vendor/`.

## Acceptance criteria

- `scripts/validate.ps1` exits 0 on a structurally healthy checkout.
- `scripts/doctor.ps1` reports the installed wiring as healthy.
- Sync and loop dry-runs make no changes and show their planned actions.
- Pester regression tests pass when Pester is available.
- Every skill has valid frontmatter whose `name` matches its directory.
