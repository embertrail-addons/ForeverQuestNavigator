# 0.1.67

Local beta build; not yet published.

- Editable, character-specific quest tours with up to 20 accepted quests. Add from a quest context menu or the new finder; reorder/remove stops and explicitly start or pause navigation.
- Tour stops advance on objective completion or turn-in/removal, not simply arrival at a coordinate. Manual quest priorities pause a running tour.
- Review a suggested straight-line order before applying it. The bounded improvement pass includes the saved return leg when positions are known. Stale previews cannot overwrite changes.
- Save the current outdoor location as a return point. Preview a closing round of known ready hand-ins, then follow the return leg. No automated turn-in, movement, hearthstone or transport action.
- Unified quest finder with literal name, ID and known-zone search across the quest log, nearby offers and persistent skips. Separate buttons open maps, prioritize, add to a tour or restore skips.
- Optional persistence of a tour and explicit quest priority per character. Saved plans are offered after login and resume only on request after validating current quest/target data. Unusable plans can be discarded.
- Consistent text symbols for accepting, completing objectives, turning in and manual priority, with explanatory tooltips.
- Minimal copyable problem reports use an allowlist of technical fields and exclude character names, personal notes and saved route names. Nothing is transmitted automatically.
- Completed dungeon and other special quests remain visible for turn-in even without an outdoor target. Unfinished special objectives remain excluded; instance/unknown hand-ins receive no fabricated outdoor navigation marker.
- Separated tour state, workspace actions, native runtime access, finder search, report generation and tracker presentation into dedicated modules. Shortened README; historical notes retained separately.

Commands: `/fqn tour`, `/fqn find [text]`, `/fqn resume`, `/fqn problem`. Tour and finder shortcuts also appear in settings. Tour/resume actions are blocked during screenshot demos.

Restart WoW after installing the new modules. This build has automated behavior/UI coverage but still needs visual and ordinary-play testing in the game client.
