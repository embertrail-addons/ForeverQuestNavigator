# Regular release authorization — 0.2.5

- [x] On 2026-11-26 the user measured the performance changes in the real client with `/fqn perf` (planning 91 ms → 0.3 ms average; quest log refresh about 20 ms → 12 ms) and explicitly accepted publishing with the remaining check (the installation that first reported stutters) open.
- [x] On 2026-11-26 the user explicitly requested publication of 0.2.5 ("Ja, veröffentlichen").
- [x] Publish as a regular Release only. No alpha, beta or release-candidate publication.
- [x] Automated validation passed (see validation-0.2.5.md).

This records publication authorization, not a claim that unreported in-game tests passed. The tag is pushed only after the main-branch workflow including luacheck has passed.

Publish unused regular tag v0.2.5 through the configured Actions workflow to CurseForge project 1812992. Use only the Embertrail Addons noreply Git identity. Inspect ambiguous uploads before retrying.
