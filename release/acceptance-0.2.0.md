# Regular release authorization — 0.2.0

- [x] On 2026-11-23 the user explicitly requested commit, push and CurseForge publication of 0.2.0, after in-game screenshots of the navigator, settings and tool pages and after disclosure that several real-client checks remain open.
- [x] Publish as a regular Release only. No alpha, beta or release-candidate publication.
- [x] Automated validation passed locally: 285 Lua 5.1 tests, 19 Python tests, five regression fixtures and 1048 matching English/German translation keys (see validation-0.2.0.md).
- [x] luacheck runs for the first time in CI; the tag is pushed only after the main-branch workflow including luacheck has passed.

This records publication authorization, not a claim that unreported in-game tests passed. Open manual checks are listed in curseforge-changelog-0.2.0.md (setup on a fresh character, route line, recap notice, group sync with a second FQN player and others).

Publish unused regular tag v0.2.0 through the configured Actions workflow to CurseForge project 1812992. Use only the Embertrail Addons noreply Git identity. Inspect ambiguous uploads before retrying.
