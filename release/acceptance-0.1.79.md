# Regular release authorization — 0.1.79

- [x] On 2026-11-21 the user explicitly instructed "Version veröffentlichen" for the installed 0.1.79 build after being informed that in-game acceptance remains open.
- [x] Publish as a regular Release, following the user's standing instruction: no alpha, beta or release-candidate publications.
- [x] Automated validation passed: 212 Lua 5.1 tests, 19 Python tests, five replay fixtures and metadata/translation parity (822 keys per language).
- [x] Runtime callback tests cover explicit outing start/pause, waiting for acceptance, zero-distance arrival, notes and current-quest selection.

The publication request supersedes the preceding local-only status. This records authorization to publish the tested state; it does not assert that any unreported gameplay or visual test has passed. The release validator and regular-release-only upload policy remain unchanged.

## Open real-client follow-ups

These checks have **not** been performed for 0.1.79 and remain listed in ui-smoketest-0.1.79.md:

- Actual WoW Forever rendering and Questie map coexistence, including legend and marker removal.
- Reviewed outings across acceptance, all objectives, turn-in, pause/resume and repeatable hand-in in game.
- Settings/notes at 80%/140% text, Focus/Overview, reload persistence and combat transitions.
- Longer-session performance and ordinary gameplay verification.

No screen access was used. Commit and push under the Embertrail Addons noreply identity, then publish the unused regular tag v0.1.79 through the configured Actions upload to CurseForge project 1812992. An ambiguous upload must be inspected before any retry.
