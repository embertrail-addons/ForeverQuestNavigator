# Regular release authorization — 0.1.83

- [x] On 2026-11-22 the user explicitly instructed “Neue Version veröffentlichen” for installed 0.1.83 after being informed that in-game acceptance remains open.
- [x] Publish as a regular Release only, following the standing instruction against alpha, beta and release-candidate publications.
- [x] Automated validation passed: 255 Lua 5.1 tests, 19 Python tests, five regression fixtures and 934 matching English/German translation keys.
- [x] Runtime/UI mocks cover mixed rounds, actual acceptance review, skip/later/hide, separate restoration and undo conflict handling.

The explicit publication request supersedes the preceding local-only status. It authorizes publishing the tested build; it does not assert that unreported gameplay or rendering tests passed. Release validation and upload policy are unchanged.

## Open real-client follow-ups

These checks have not been performed and remain documented in curseforge-changelog-0.1.83.md and the preceding local-version checklists:

- Actual WoW rendering, 80%/140% fonts, narrow layouts, map/Questie coexistence and combat transitions.
- Mixed pickup/objective/hand-in navigation, a full-log hand-in freeing a slot, actual acceptance and explicit reviewed resume.
- Skip/later/hide, dependent-step removal, saved exclusions through reload/restart, manual acceptance and single-entry restoration in game.
- Timed previews, group reads, merchant visits, reminders, longer-session performance and ordinary gameplay verification.

No screen access was used. Commit/push under the Embertrail Addons noreply identity, then publish unused regular tag v0.1.83 through the configured Actions upload to CurseForge project 1812992. Inspect any ambiguous upload before retrying.
