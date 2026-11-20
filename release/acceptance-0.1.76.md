# 0.1.76 release acceptance

## Publication authorization

- [x] On 2026-11-20 the user explicitly requested publication of the current version, clarified "Nein, Release!!!" and instructed "Keine Veröffentlichungen als Beta mehr".
- [x] The publication pipeline rejects alpha, beta and release-candidate uploads before network requests. Regular release tag: `v0.1.76`.
- [x] Local validation passed: 158 Lua 5.1 tests and 19 Python tests, including rejection of prerelease uploads.

This records authorization to publish the current tested state as a regular Release. It does not assert unreported in-game checks. The user provided screenshots of 0.1.73 and 0.1.75 during the UI iteration; the latest 0.1.76 spacing refinements have automated regression coverage but no new in-game visual confirmation.

## Follow-up client checks

The existing manual checklist remains at `release/ui-smoketest-0.1.73.md`. Actual rendering with the latest spacing, secure item input, combat state transitions, dragging and ordinary questing remain follow-up checks, not claims of completed validation. The explicit publication request supersedes the earlier local-only development status.

## Release contents

The version-specific CurseForge changelog consolidates all changes since the previous public release, 0.1.66. The archive contains only the ForeverQuestNavigator directory and required runtime/documentation files, without Questie, tests, scripts or saved variables. English/German parity and matching tag/TOC/package metadata are checked by the release pipeline.

Commit under the existing Embertrail Addons noreply identity and push `main` plus the new, unused `v0.1.76` tag. The configured GitHub Actions job uploads to CurseForge project 1812992 as Release using the repository secret. Do not repeat a possibly accepted upload automatically; inspect the returned file ID and moderation status first.
