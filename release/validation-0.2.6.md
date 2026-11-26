# Local validation — 0.2.6

2026-11-26:

- 316 Lua 5.1 tests passed (Lupa runtime via `.local/tools/lua5.1.cmd`), including new checks: no addon file registers the combat log or calls SetRaidTarget (comments excluded); kills are noticed once per mob from nameplate health and plate removal, not for mobs tagged by someone else; blocked actions naming FQN are recorded and told once, other addons are ignored; the quest menu offers "Skip this quest in FQN".
- 24 Python tests passed.
- Six offline regression fixtures passed unchanged.
- Release input validation passed with matching English/German translation keys.
- luacheck (global variables) runs in CI.
- Installed into the local game folder with `scripts/install.py` (all files verified by SHA-256).

Real client: the user's `/fqn problem` report before the fix named "forbidden Frame:RegisterEvent()". Open checks: see curseforge-changelog-0.2.6.md.
