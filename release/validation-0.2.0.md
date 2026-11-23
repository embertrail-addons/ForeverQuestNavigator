# Local validation — 0.2.0

2026-11-23:

- 285 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new tests for settings normalization, the command registry, the event light path, release notes, the setup wizard, simple-mode tool pages, the route line, the distance bar, the navigator link row, the scrolling settings, zone and quest lists, the outing summary, session recap, level forecast and group sync encoding/validation/throttling.
- 19 Python packaging/upload-policy tests passed.
- Five offline regression fixtures passed.
- Release input validation passed with 1048 matching English/German translation keys. A tagged release check is blocked on purpose until acceptance-0.2.0.md is completed.
- Every addon file keeps at least 30 free top-level locals (Bootstrap.lua: 89 of 200 used, 1994 lines). The state-table rename and the module extraction used a scope-aware Lua tokenizer; no shadowed names were found.
- luacheck (global variables) was not run locally; it runs in CI.

No game screen was accessed. Automated mocks do not establish real-client gameplay or rendering acceptance; manual checks are listed in curseforge-changelog-0.2.0.md. No push, tag or upload was performed.
