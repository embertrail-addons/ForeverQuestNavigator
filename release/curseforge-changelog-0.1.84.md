# Forever Quest Navigator 0.1.84

Regular release: improved quest activity detection and stable corpse navigation.

## Quest activity

- Preserve validated NPC IDs/source keys from Questie objective data. Combat relations are also available independently of kill-location arrows and spawn coordinates. Item-drop NPCs use explicit `m_` source keys; object IDs and vendor sources cannot be mistaken for enemies.
- Inspect only the current target/pet target with publicly readable identity, attackability and evidence of own engagement (threat or target-of-target player/pet). Match against unfinished accepted objectives; reject skipped/completed/failed/disabled or explicitly avoided objectives. No targeting, interaction, nameplate sweep or combat-log parsing is performed.
- When automatic navigation is in combat, a matching quest may replace the unrelated frozen recommendation. Explicit quest/objective priority, started tours and detours remain authoritative. Losing public identity stops the exact-match claim; missing/secret values are never decoded or inferred from a generic quest-unit relation flag.
- Recognize small local spawn neighborhoods: 80-yard entry / 110-yard exit around a spawn; same-source/same-objective points may form short corridors up to 240 yards long with a 60/80-yard width threshold. Pair work is bounded to the nearest 40 candidates. Far camps do not form a map-wide bounding box or polygon.
- Respect camp avoidance, explicit objective/camp choices and personal correction points. Non-combat vendor sources do not form enemy spawn areas. Nearby-area evidence gives a small ranking allowance and a work-phase hint, without proving a live enemy or quest completion.
- Hide the direction arrow while fighting a confirmed matching enemy or working in a known local spawn neighborhood. Keep actual coordinate distance visible; do not fabricate a zero distance or claim exact arrival at a mob.

## Corpse navigation

- Death and ghost state override quest/detour direction, including explicit priorities, and temporarily freeze automatic quest choice. Arrival-based detour return and outing navigation are suspended during recovery; existing plans and manual choices are retained.
- Before spirit release, display a waiting state. As a ghost, query native corpse position on current/death/parent maps, bounded against loops. Pin a valid native target for the run so quest recommendations and map changes cannot move it.
- If native coordinates are unavailable, use only a publicly captured position from PLAYER_DEAD and label it approximate. If neither exists, show unknown recovery coordinates and no quest arrow. Known destinations without a measurable cross-map direction also show an explicit unavailable state.
- PLAYER_UNGHOST / confirmed living state clears recovery, then normal quest navigation resumes. FQN never releases spirit, retrieves the corpse or resurrects automatically.
- Direction display opacity and position stay unchanged. Recovery can temporarily use the external display even when the ordinary quest arrow is inline; turning direction arrows off is respected.
- `/fqn activity` prints combatMatch, objective, area, recovery and corpse-data source. No raw GUID or other player identity is logged or shared.

## Manual acceptance remains open

No game screen was accessed. Tests are automated mocks and offline replays, not real-client acceptance.

1. Test a dispersed kill quest between nearby spawn points and in disconnected camps. An approximate area hint must not claim live mobs. Leave the area and verify directions return.
2. Fight a real kill/drop quest source with and without manual priority. Check target switches, pet combat, completed/avoided objectives, missing Questie data and unavailable public identities. An unrelated selected NPC must not produce a confirmed match.
3. Die, release spirit and walk from the graveyard while crossing several quest targets. Corpse direction must remain stable. Check unknown corpse coordinates, approximate fallback, map boundaries, inline-arrow settings and arrow-disabled settings.
4. Resurrect normally or through a spirit healer. Verify ordinary navigation resumes with the previous manual choice / tour intact. Test death during a temporary detour and with an empty quest log.
5. Check actual font/rendering at 80%/140% text. If detection still differs from expectations, capture `/fqn activity` while the relevant situation is current.

Source/API review: [Questie objective/source implementation](https://github.com/Questie/Questie/blob/master/Modules/Quest/QuestieQuestPrivates.lua), [public-identity limitations in Questie's Forever audit](https://github.com/Questie/Questie/blob/master/docs/forever-object-tooltip-api-audit.md), [native DeathInfo declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/DeathInfoDocumentation.lua). API declarations do not establish live availability for every corpse or map; runtime failures remain unknown.
