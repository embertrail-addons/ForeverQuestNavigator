# Local validation — 0.1.83

2026-11-22:

- 255 Lua 5.1 tests passed, including all TOC modules and native runtime/UI mocks.
- 19 Python packaging/upload-policy tests passed with mocked services.
- Five offline regression fixtures passed.
- Metadata/package validation passed with 934 matching English/German translation keys.

New coverage:

- Existing objective -> pickup -> new objective -> hand-ins, with precedence retained.
- Full-log hand-in freeing capacity, reserve enforcement, no slot freed by arrival, actual acceptance pause and reviewed targets.
- Unknown coordinates/transforms, bounded known pickup detours, XP recalculation and represented transitive dependency pruning.
- Preservation of active quests, including a simulated native acceptance that arrives before the cached quest-log list.
- Separate permanent/round/session offer filters, hidden-list restore, later reminders and native undo callbacks.
- Direct preview skip/undo, three-choice menu fallback, ordinary map clicks and simple navigator review access.
- Destination-area offers outside the player's radius, labelled with player-origin distance.
- All twelve assistant views retained in language/font/theme geometry tests.

No game screen was accessed and no real-client gameplay/rendering acceptance is claimed complete. Manual follow-ups are in curseforge-changelog-0.1.83.md. No commit, push, tag or upload was performed.
