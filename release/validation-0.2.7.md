# Local validation — 0.2.7

2026-11-26:

- 318 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new checks: grid and plain camp grouping produce the same camps; 4000 spawn points group within budget and later passes reuse the camps; a rebuilt marker list with the same markers is not regrouped, a changed one is; reloaded markers at the same place reuse their world position; the Questie result lifetime is short while loading and long afterwards.
- 24 Python tests passed.
- Six offline regression fixtures passed unchanged.
- Release input validation passed with matching English/German translation keys.
- luacheck (global variables) runs in CI.
- Installed into the local game folder with `scripts/install.py` (all files verified by SHA-256).

Real client (measured by the user with `/fqn perf`): Undercity planning 93 ms → 28.6 → 15.5 ms average over three builds; last measurement (in flight) planning 10.3 ms, spawn-area check 0.01 ms, quest log update 30 ms average.
