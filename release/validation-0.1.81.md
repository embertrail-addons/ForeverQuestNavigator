# Local validation — 0.1.81

2026-11-22:

- 232 Lua 5.1 tests passed.
- 19 Python packaging/upload-policy tests passed (mocked services only).
- Five offline regression fixtures passed.
- Metadata/package validation passed with 874 matching English/German translation keys.

Coverage includes departure/manual acceptance, unknown and full quest capacity, confirmed/negative/unknown/error group reads, scoped/resettable objective versus hand-in corrections, completed/missing objective handling, whole-quest time subsets, unknown return exclusion, change proposals without plan mutation, explicit selection, preserved tab/pages, time controls hidden on running plans, direct actions and compact difficulty text. The runtime mock verifies that level-up preserves a valid prior target until explicit Recalculate; removal/hand-in and the existing routing tests still pass.

Manual gameplay/rendering acceptance is still open. The checklist and estimate/privacy limits are in curseforge-changelog-0.1.81.md. No screen access, commit, push, tag or publication was performed.
