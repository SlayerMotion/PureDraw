# Rules

This folder holds shared rules consumed by other repos via `@`-import from `AGENTS.md`.

- Entry point for AI agents: `AGENTS.md` (lists every rule file under `swift/` and `universal/`)
- Swift-specific rules: `swift/<rule>.md` (and `swift/exp/<file>.md` for the ExtremePackaging folder)
- Cross-cutting rules: `universal/<rule>.md`
- Trigger guide for self-direction: `universal/rule-loading.md`
- Global config that pulls these into `~/.claude/CLAUDE.md` on every Mac: `mihaela-agents/GLOBAL_CLAUDE.md`

Communication, attribution, voice-alert, and writing-style rules are global and live in `mihaela-agents/GLOBAL_CLAUDE.md`, not here.
