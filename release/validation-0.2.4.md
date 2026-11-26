# Local validation — 0.2.4

2026-11-26:

- 314 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including a new full-log test: the quest value needs at most 8 × 7 distances and repeats none while targets stay the same; shared-mob counts stay within budget. Tests confirm that a target change no longer sets raid marks from addon code.
- A source search finds no remaining call of protected functions (SetRaidTarget, TargetUnit, CastSpell and similar) from addon code.
- 24 Python tests passed.
- Six offline regression fixtures passed unchanged.
- Release input validation passed with matching English/German translation keys.
- luacheck (global variables) runs in CI.
- Installed into the local game folder with `scripts/install.py` (all files verified by SHA-256).

Not yet checked in the real client: see curseforge-changelog-0.2.4.md.
