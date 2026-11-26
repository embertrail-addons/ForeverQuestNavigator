# Local validation — 0.2.5

2026-11-26:

- 315 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new checks: found turn-in positions are not looked up again on further quest log updates; quest chains are not rebuilt by an update that finishes nothing but are rebuilt after new quest data; the Questie state key ignores kill counts but changes with finished objectives, quests and maps; `/fqn perf` lists the planning and refresh steps.
- 24 Python tests passed.
- Six offline regression fixtures passed unchanged.
- Release input validation passed with matching English/German translation keys.
- luacheck (global variables) runs in CI.
- Installed into the local game folder with `scripts/install.py` (all files verified by SHA-256).

Real client (measured by the user with `/fqn perf`): planning 0.27–0.31 ms average (before 91 ms), quest log refresh 12 ms average, max 26 ms (before about 20 ms, max 80 ms).
