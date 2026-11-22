# Local validation — 0.1.82

2026-11-22:

- 244 Lua 5.1 tests passed, including compilation of all TOC modules and runtime UI/event mocks.
- 19 Python packaging/upload-policy tests passed with mocked services.
- Five offline regression fixtures passed.
- Package/metadata validation passed with 915 matching English/German translation keys.

Added coverage:

- Coordinate detour selection, blocked/already-planned targets and missing cross-map transforms.
- Independent hand-in insertion and actual repeatable turn-in evidence; preview receipts/progress do not mutate the running plan.
- Normal/specialized bags and error/partial reads.
- Per-character reminder persistence through plain saved tables, group/area/round contexts, repeatable activity and round identity.
- Distinct tour alternatives, partial XP and chain expansion with unknown requirements.
- Full pickup -> collecting/low bags -> actual hand-in -> reminder scenario.
- Native runtime callbacks for saving/removing a reminder and saving a merchant only from an open merchant window.
- Simple mode's hidden cards/lists and actionable warnings.
- All 11 assistant views in both languages, both font extremes and three themes: three navigation groups, description/row/footer separation, explicit preview versus priority changes.

These are automated mocks and offline replays. No real game screen was accessed and no real-client gameplay/rendering check is claimed complete. Manual acceptance remains in curseforge-changelog-0.1.82.md. No commit, push, tag or upload was performed.
