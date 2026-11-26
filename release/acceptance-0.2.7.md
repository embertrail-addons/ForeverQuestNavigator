# Regular release authorization — 0.2.7

- [x] On 2026-11-26 the user measured the city performance changes in the real client with `/fqn perf` (Undercity and in flight; planning 93 ms → 10 ms average) and explicitly accepted publishing with a final Undercity measurement open.
- [x] On 2026-11-26 the user explicitly requested publication of 0.2.7 ("Ja, veröffentlichen").
- [x] Publish as a regular Release only. No alpha, beta or release-candidate publication.
- [x] Automated validation passed (see validation-0.2.7.md).

This records publication authorization, not a claim that unreported in-game tests passed. The tag is pushed only after the main-branch workflow including luacheck has passed.

Publish unused regular tag v0.2.7 through the configured Actions workflow to CurseForge project 1812992. Use only the Embertrail Addons noreply Git identity. Inspect ambiguous uploads before retrying.
