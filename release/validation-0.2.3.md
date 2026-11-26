# Local validation — 0.2.3

2026-11-26:

- 313 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new tests for the quest value model (XP per minute, way to the turn-in, look-ahead, follow-ups, finishing the zone, learned preference, learned travel and work speed, explanations and runner-up comparison), the two reported cases (one kill left with a far turn-in; mobs shared by two quests), /tm macros with [exists], the secure click-cycling snippet run in a simulated restricted environment, blocked-action handling and the two key-binding buttons.
- 24 Python tests passed.
- Six offline regression fixtures passed unchanged.
- Release input validation passed with 1164 matching English/German translation keys.
- Every addon file keeps the required free top-level locals (headroom test passed).
- luacheck (global variables) runs in CI; the configuration lists the new globals.
- Installed into the local game folder with `scripts/install.py` (all files verified by SHA-256).

Real client (reported by the user): window marking via /tm works, clicks cycle to the next living mob, no error when the NPC is not nearby. Open checks: see curseforge-changelog-0.2.3.md.
