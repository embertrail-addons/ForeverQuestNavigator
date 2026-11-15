# Forever Quest Navigator

Forever Quest Navigator recommends a quest from the quests you have already accepted. Phase 1 reads the Blizzard quest log and ranks quests by ascending quest level. Equal levels break by quest ID, and quests with no usable level rank after quests with a known level. Failed and session-disabled quests are ineligible.

The movable tracker shows the recommendation, its level, and the first unfinished objective with the game's progress text when available. A completed quest in the log is labeled **Ready to turn in** and remains eligible until it is handed in. The tracker refreshes at login and on quest events. Events that arrive within the same 100 ms window share a refresh.

## Client and installation

Version **0.1.1** targets **World of Warcraft: Forever 1.60.1**, interface **16001**. The quest logic and UI flow have passed mocked Lua tests. In-game validation is pending. [Blizzard's Forever launch announcement](https://news.blizzard.com/en-us/article/24315643/return-to-azeroth-in-world-of-warcraft-forever) · [Questie's Forever manifest](https://github.com/Questie/Questie/blob/master/Questie_Forever.toc)

1. Clone this repository or choose **Code → Download ZIP** on GitHub and extract the archive. Name the folder containing `ForeverQuestNavigator.toc` exactly `ForeverQuestNavigator`.
2. Copy that folder into `<World of Warcraft>/_forever_/Interface/AddOns/`. Verify the resulting path is `AddOns/ForeverQuestNavigator/ForeverQuestNavigator.toc`. The game loads the files listed in the manifest. You can omit `README.md` and `tests/` from the installation.
3. Start or restart WoW: Forever, enable **Forever Quest Navigator** in the AddOns list, and enter the world.
4. Drag the tracker by its title. `/fqn` toggles visibility, and `/fqn status` reports whether Questie and TomTom are loaded.

## Controls and settings

- **Skip quest** hides the current quest from FQN recommendations and shows the next eligible one. The quest stays in the game's quest log. The skip lasts until the quest leaves your log, you press **Reset skips**, you log out, or you reload the UI.
- **Include elite quests** is under **Options → AddOns → Forever Quest Navigator**. `/fqn settings` opens the same page. The checkbox is on by default. Turn it off to exclude quests that Blizzard's `C_QuestLog.IsEliteQuest` flags as elite, including quests ready to turn in. The elite preference, window position, and visibility are saved account-wide. [Forever quest API](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)

Questie and TomTom are optional. Phase 1 uses the Blizzard quest log for recommendations and reports the two add-ons' load state through `C_AddOns`. This repository contains FQN's own code and tests. Questie, QuestieDB, and TomTom are distributed separately under their respective licenses. [Forever addon API](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua)

## Blizzard add-on policy

FQN reads the in-game quest log and changes only its own display and preferences. The player accepts quests, completes objectives, and turns quests in. Blizzard permits UI add-ons subject to its add-on policy, including free distribution and publicly viewable source code. Its EULA prohibits unauthorized automated control of gameplay. Questie publishes a Forever build. Its use and any future FQN integration are subject to the same Blizzard rules. Consult the respective project licenses before redistributing any Questie code or data. [Blizzard add-on policy](https://eu.forums.blizzard.com/en/wow/t/wow-user-interface-add-on-development-policy/1642) · [Blizzard EULA](https://www.blizzard.com/en-gb/legal/08b946df-660a-40e4-a072-1fbde65173b1/blizzard-end-user-license-agreement) · [Questie Forever release](https://github.com/Questie/Questie/releases/tag/bundle/v12.9.0%2Bv1.1.1) · [Questie license](https://github.com/Questie/Questie/blob/master/LICENSE.md) · [QuestieDB license](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md)

## Compatibility research

- **Blizzard quest log.** Forever's generated API documents `C_QuestLog.GetNumQuestLogEntries`, `GetInfo`, `IsOnQuest`, `IsComplete`, `IsFailed`, `IsQuestDisabledForSession`, and `GetQuestObjectives`. The tracker uses the first `GetNumQuestLogEntries` return as the row count, skips headers, hidden and internal rows, and task rows, then confirms active membership with `IsOnQuest`. It uses the quest's reported `level`, which can reflect client scaling. Quest log, criteria, and watch updates trigger snapshots. `QUEST_REMOVED` supplies the quest ID used to clear a skip. Check enumeration with both open and collapsed quest headers in the live client. [Forever quest API and event definitions](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)
- **Questie.** The installed Forever package is Questie 12.9.0 with QuestieDB 1.1.1 and provider contract 4. Upstream ships Forever alongside Classic flavors including Era, TBC, Titan Reforged, and MoP. Its loader wires modules together and `QuestieCompat` adapts client differences. `Questie.API.RegisterOnReady` and `RegisterForQuestUpdates` are public entry points for readiness and quest changes. The separate `LibQuestieDB` provider offers public quest, NPC, object, and item queries. Coordinates can depend on objective entity type, item sources, spawn data, and zone mappings. Questie's DB and quest modules also apply consumer policy and show map pins. Compare provider records and actual pins before choosing an integration and keep any private calls inside a Phase 2 adapter. [Questie Forever development notes](https://github.com/Questie/Questie/blob/master/docs/forever-development.md) · [Readiness API](https://github.com/Questie/Questie/blob/master/Public/RegisterOnReady.lua) · [Quest update API](https://github.com/Questie/Questie/blob/master/Public/RegisterForQuestUpdates.lua) · [QuestieDB public API](https://github.com/Questie/QuestieDB/blob/master/docs/api.md)
- **TomTom.** The supplied GitHub repository could not be retrieved. The maintainers publish their Git source location on CurseForge. Their `v4.4.1-release` lists Forever 1.60.1 and documents quest waypoints, `AddWaypoint`, and arrow callbacks. TomTom was absent from the local Forever AddOns directory. Verify the packaged README API and waypoint creation, arrow ownership, and cleanup on Forever before connecting it to FQN. [Maintainer source listing](https://www.curseforge.com/wow/addons/tomtom/source) · [TomTom v4.4.1 release notes](https://www.curseforge.com/wow/addons/tomtom/files/9493883)
- **Map, tracking, and protected actions.** Forever's UI source exposes `C_Map.GetBestMapForUnit`, `GetPlayerMapPosition` with a nullable vector, `GetMapWorldSize` in yards, and `CanSetUserWaypointOnMap`. `C_QuestLog.GetNextWaypoint` may provide a native quest waypoint when available. Confirm outdoor, indoor, instance, and map-transition behavior before using these APIs for distance or positioning. Phase 1 reads quest state and does not change the native watch or supertrack state. Midnight's secret-value restrictions make live verification important for future combat-sensitive UI and navigation behavior. [Forever map API](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua) · [Blizzard's Midnight addon guidance](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- **Taxi.** Forever exposes `C_TaxiMap.GetAllTaxiNodes` in the current flight-master context, `GetTaxiNodesForMap` for a map, and taxi-map events. A node listing is insufficient to infer travel connections or durations. Phase 4 needs live evidence for each character's unlocks, reachable routes, and reliable timing. Booking remains a manual player action. [Forever taxi API](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TaxiMapDocumentation.lua)
- **Related work.** Guidelime demonstrates automatic guide progress updates. Shortest Path Forever provides an example of travel modeling, and Questie's bundled HereBeDragons includes Forever map-transform work. FQN derives its recommendation from the live quest log and ships no guide routes or bundled libraries in Phase 1. [Guidelime](https://github.com/max-ri/Guidelime) · [Shortest Path Forever](https://github.com/cjber/shortest-path-forever) · [Questie map compatibility notes](https://github.com/Questie/Questie/blob/master/docs/forever-development.md)

## Testing

Run `lua tests/run.lua` from the addon directory with Lua 5.1. The suite compiles the Lua files in manifest order and exercises the quest reader, ranking, skip and reset behavior, the elite filter, objective selection, optional addon detection, and tracker event flow using mocked WoW APIs.

### In-game validation

1. Enter the world and run `/console scriptErrors 1` followed by `/reload`. Run `/dump GetBuildInfo()` and confirm that the fourth result is `16001`. Check that the tracker appears and `/fqn status` matches the addons actually loaded.
2. Accept two quests of different levels. Confirm the lower-level quest appears even when neither quest is tracked. If the log offers collapsible sections, collapse and reopen a section containing the recommendation and check that it continues to appear.
3. Progress a multi-objective quest. Confirm progress text updates and the tracker skips completed objectives. Complete the quest, check **Ready to turn in**, and hand it in. Verify the recommendation advances. Also test abandoning the current recommendation and the empty-log state.
4. Click **Skip quest** and confirm the next eligible quest appears. Trigger a quest-log update to verify the skipped quest stays out of the recommendations. Click **Reset skips** to make it eligible again.
5. Accept an elite quest whose level is lower than a regular quest. Open `/fqn settings` and toggle **Include elite quests** both ways. Verify the tracker changes recommendations each time. Turn the setting off and check that it stays off after `/reload`.
6. Move and close the tracker, then run `/reload`. Confirm it stays hidden until you type `/fqn` and reopens at the saved position. Repeat with Questie and TomTom disabled, if installed, to verify standalone operation.

## Roadmap

- **Phase 2** Resolve objective and turn-in coordinates through validated metadata, then integrate TomTom waypoints through an adapter.
- **Phase 3** Add proximity and optimized modes, objective clusters, and target-switch hysteresis.
- **Phase 4** Recommend flights where unlocks, connections, and travel estimates can be verified.
- **Phase 5** Add tracker controls and configuration, verify performance and edge cases, and extend tests.

Phase 1 provides a quest recommendation and objective text. Coordinate guidance, distance, route optimization, target locks, and flight planning are future features.
