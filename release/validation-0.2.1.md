# Local validation — 0.2.1

2026-11-25:

- 297 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new tests for the notice queue, list scrolling, self-test, error log, tour sharing, follow-up unlock detection, daily goal, minimap arrow, settings help lines, a full quest log scenario with time budgets and a guard against unescaped texture paths.
- 22 Python tests passed, including the release preparation script and icon packaging.
- Six offline regression fixtures passed, including the new 25-quest full log.
- Release input validation passed with 1077 matching English/German translation keys. A tagged release check is blocked on purpose until acceptance-0.2.1.md is completed.
- Every addon file keeps at least 30 free top-level locals (Bootstrap.lua: 93 of 200 used, 2082 lines).
- luacheck (global variables) runs in CI; the configuration lists the new globals.

Real client (reported by the user): `/fqn selftest` showed 29 of 29 interfaces OK and no errors; the minimap arrow points correctly and is no longer covered; compass icons in the addon list and on the minimap button; settings help lines no longer overlap.

Not yet checked in the real client: tour sharing and group sync with a second FQN player, the daily goal over a session, the notice queue with several due windows, and scrolling with long lists. No push, tag or upload was performed.
