# Local validation — 0.2.2

2026-11-25:

- 309 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new tests for the target-mark window (secure targeting, raid marks, combat lock, visibility, opacity), nameplate marks, loot reminder, respawn estimate, group members' marks, danger lookups, instance summaries, quest log headings, turn-in collector, hearthstone hint, bag check, quest sounds, per-character profiles, compact bar, quiet instance view, group sync default migration and a guard against creation-order frame lookups in UI tests.
- 24 Python tests passed, including the install script.
- Six offline regression fixtures passed.
- Release input validation passed with 1144 matching English/German translation keys.
- Every addon file keeps the required free top-level locals (headroom test passed; Bootstrap.lua 2390 lines).
- luacheck (global variables) runs in CI; the configuration lists the new globals.
- Installed into the local game folder with `scripts/install.py` (all files verified by SHA-256).

Not yet checked in the real client: see "Manual checks still open" in curseforge-changelog-0.2.2.md.
