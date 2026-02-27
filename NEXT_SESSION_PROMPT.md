---
summary: "Session handoff prompt for pi-little-helpers."
read_when:
  - "Starting the next focused development session."
system4d:
  container: "Session handoff artifact."
  compass: "Resume work quickly with explicit priorities."
  engine: "Capture context, constraints, and next actions."
  fog: "Staleness risk if not updated after major changes."
---

# Next session prompt for pi-little-helpers

## Current state

- 3 extensions: `code-block-picker`, `package-update-notify`, `stash`
- 1 shared lib: `lib/package-utils.ts` (extracted from extensions folder)
- Prompts: `implementation-planning`, `security-review`

## Recent changes

- Moved `package-utils.ts` to `lib/` to fix pi extension loading error

## Potential next steps

- Add tests for extensions
- Publish to npm (run `npm run release:check` first)
- Add more prompts as needed
