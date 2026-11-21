# Forever Quest Navigator

FQN helps you choose and navigate outdoor quests in World of Warcraft Forever. It compares known distance, level suitability, possible XP and supported follow-ups, including targets across zone borders.

**Current version: 0.1.79.** FQN publishes regular releases only. Beta, alpha and release-candidate uploads are disabled in the publication pipeline.

The navigator has two views: **Focus** (active quest, current objective and expandable further objectives) and **Overview** (adds Next and expandable Surroundings). The collapse button, title menu and settings select the same views. Three color designs, high contrast, reduced colors and example preview remain available. Background opacity does not fade text; settings dialogs stay opaque.

Open **Plan outing** or `/fqn plan` -> **Quest areas** (expand one) / **Next round** -> **Build outing from area**. Review pickups, objectives and known hand-ins before explicit Start. Pause/resume preserves progress; quests are accepted and handed in manually. Arrival alone cannot complete a pickup. **Round progress** still offers advisory tracking without navigation.

Quest menus add **Compare objective areas** and **Edit personal note**. Repeatables default to informational display in finder/offers, with levelling/hide options in settings. Starter items and prerequisites are shown where known. Settings can be filtered by display versus recommendations and opened with example preview. Map legend includes clear-FQN-markers. Saved access-route lengths affect ranking; unknown terrain and XP remain explicit. [Release notes](release/curseforge-changelog-0.1.79.md) · [Pending in-game checks](release/ui-smoketest-0.1.79.md) · [Publication authorization](release/acceptance-0.1.79.md).

[CurseForge](https://www.curseforge.com/wow/addons/forever-quest-navigator) · [Source and issues](https://github.com/embertrail-addons/ForeverQuestNavigator)

## Install

Install the Forever build, then restart WoW. For a manual installation, extract the ZIP so that `Interface/AddOns/ForeverQuestNavigator/ForeverQuestNavigator.toc` exists.

Questie and QuestieDB are optional integrations for supported objective positions, nearby offers and follow-ups. The screenshot demo requires both. FQN does not bundle, disable, uninstall or overwrite Questie. Its ZIP contains only the ForeverQuestNavigator directory. The CurseForge app and the game must use the same WoW installation.

The addon targets Forever 1.60.1 (interface 16001). English and German interfaces are available. In-game quest names and objective text come from the client or Questie.

## Questing

The navigator emphasizes the active quest and its current objective. The navigation target has a labelled accent instead of a repeated `>` symbol. Known counters appear to the right of the objective description, with a subtle progress bar when reliable counts exist. Normal quest titles have no state glyph. A status line explains automatic recommendations or manual priority, with Resume automatic beside a manual priority. Special turn-in and group statuses remain visible.

Detailed view shows open objectives. Compact and collapsed views keep the current objective, progress and distance, with a button to disclose additional objectives; completed objectives remain separately expandable. Quieter sections labelled Other active quests and To accept distinguish the next choices. Strong nearby recommendations retain an explicit Recommended label.

Click a quest name to open its map and quest text. Right-click for additional actions. The small **i** button opens full details without expanding the list; active quest details use **Details**. Details open beside the navigator when there is space, or in the shared tool window on a narrow screen. Long content scrolls. Skip an accepted quest from its context menu or the labelled **Skip quest** button in its details. Inline skip buttons are hidden; the existing undo and skipped list restore quests. Nearby offers have no skip action.

The movable screen arrow emphasizes the current objective and distance. Hover it to reveal the quest name and full text. Turning off the separate arrow keeps direction inside the navigator. Opacity changes the background while keeping text readable. Quest rows retain their order while you interact with the navigator or read a detail pane; ranking and automatic navigation continue using current data.

Right-click the navigator title for Current objective only, Active quest or All recommendations. These are presentation choices; they do not change ranking or priority. Settings also provide navigator width and maximum height (default 600 UI pixels, adjustable from 360 to 1000). The quest title and priority stay pinned while the content underneath scrolls. Scroll position is retained during updates and resets for a different active quest. Each list starts with the configured number of entries. Show more appends another batch without replacing the displayed prefix. The mouse wheel only scrolls; there is no paging at the boundaries.

Opened details mark their corresponding quest row and change its detail button to a close action. The current-objective caption includes the destination type instead of repeating it on a separate line. Zone and short XP forecasts share a consistent information line; detailed level assessments remain in Details. A zone is only named when it differs from the player's current zone. Ready quests have a separate labelled Turn in badge; particularly useful offers retain Recommended. Short tooltips retain full quest titles; complete explanations and rewards remain in the detail pane. Empty selections and missing coordinates explain the available next action.

A compact, single-line notice area is reserved while navigating a quest or detour. When no notice is active, it shows the open-objective/ready-quest summary in the full view. Arrival instructions and temporary recommendation notices replace that summary without adding rows above the lists. Their appearance and expiry leave quest-row positions unchanged. Longer text is available in its tooltip or the quest details. Empty area summaries are hidden. The active information line uses the full width, with map/detail actions on a separate row underneath.

Appearance preview offers live font-size, width and background-opacity controls with an example quest and objective progress. Restore previous appearance returns to the appearance saved when that preview was opened; Keep changes closes it. Changes apply immediately, including when the preview is closed with X. Ranking, skips, notes and navigation are outside this appearance snapshot.

The active quest can display an owned quest-action item explicitly associated by the game client, with count and cooldown. Use it by left-clicking its icon outside combat. Item actions are hidden in combat and revalidated afterwards. Collected objective items and Questie source items are not turned into action buttons. A use-item arrival instruction additionally requires a positive range result from the client.

The navigator and external direction display distinguish a quest giver, entrance, quest object, quest area, approximate destination and unknown position. Arrival instructions remain visible in the navigator as well as the direction display. They do not treat an approximate area as an exact NPC location.

Use **Arrange interface** in settings or `/fqn arrange` to position both displays together. Center and 16-pixel edge guides assist dragging, with snapping near those guides. Done and lock saves and locks both positions; Cancel or Escape restores the positions from when editing started. The direction display can also be centered from the editor.

See the [0.1.79 release notes](release/curseforge-changelog-0.1.79.md) and [pending in-game checks](release/ui-smoketest-0.1.79.md). Restart WoW after updating from 0.1.76 or earlier to load the new modules.

- See the active quest, all known objective progress, distance and optional approximate XP.
- Navigate toward the nearest usable unfinished objective with the movable direction arrow.
- Compare suitable quests by distance and level; supported forecasts consider up to two unambiguous follow-ups.
- Open destinations on the world map. Compact, removable FQN pins track map pan/zoom, group co-located route numbers and highlight matching tracker entries on hover.
- Left-click quest rows to open the map. Explicit quest-log/context-menu actions set a manual priority.
- Prioritize until objectives complete or until turn-in, then return to automatic selection.
- Skip an accepted quest without abandoning it; restore it from the skipped list or quest finder.
- Unfinished dungeon, raid and PvP objectives stay out of normal recommendations. Completed special quests remain visible for turn-in. An unknown/instance hand-in does not receive a fabricated outdoor target.
- Labels describe the current objective, priority, turn-in and group states without relying only on color. Normal navigator titles have no leading objective symbol. Other tool windows retain their compact state symbols and explanatory tooltips.

Optional route details show straight-line travel-time estimates, conservative zone suggestions, known reward base-stat comparisons and travel preparation. Estimates do not establish a safe terrain path or account for combat, every transport connection or personal XP bonus. Missing information remains unknown.

## Find quests and build a tour

Open **My quest tour** or **Find quests** in settings, or use `/fqn tour` and `/fqn find`.

The finder searches quest names, IDs and known zones across accepted quests, nearby offers and skipped entries. Click a row for its known map destination. Separate buttons prioritize a quest, add it to a tour or restore a skip. It never accepts a quest for you.

A tour holds up to 20 distinct accepted quests. New unfinished stops mean completing their objectives; already completed stops mean turning in the quest. Reorder/remove stops before starting. Stops advance when quest state changes, rather than merely when you arrive at coordinates. An explicit manual priority pauses the tour; **Start tour** resumes it.

**Suggest order** produces a preview using known straight-line distances, with a bounded improvement pass that considers the return point when all legs are known. Unknown positions remain last. **Apply order** is required to adopt the preview; a stale preview cannot overwrite later changes. This does not promise an optimal route.

To finish near an inn or city, stand at the desired outdoor location and choose **Return here afterwards**. **Turn-in round** previews ready hand-ins with known outdoor destinations, followed by that return point. Review/apply it, then start. The return leg finishes within 12 yards; it never uses a hearthstone or performs gameplay actions.

**Remember quest tour and priority** is on by default and saves per character. After login, FQN offers `/fqn resume`; it never starts the saved plan automatically. Resume checks current quest state, skips and the next known target. An unusable plan can be discarded. Turning the setting off removes the saved copy while leaving the current in-memory tour available.

## Display and planning tools

Tools now share one window with **Quests, Planning, Activity, Settings and Help** sections. Only one tool panel is visible at a time. Related tools use short tabs; Back returns to the previous view, and searches, filters and planning pages are retained while navigating. The window adapts to smaller UI surfaces and keeps its header position when the content changes size. Escape closes it.

Settings show five common options first. Search includes advanced settings and their categories. Boolean choices use checkboxes, numbers have explicit minus/plus buttons, and languages/display modes use direct selection menus. Tools are reached through the shared navigation instead of a button grid in settings.

The finder highlights its selected filter and shows counts, manual priorities, tour membership and unavailable quest states. Tour actions depend on context: preview controls appear only while reviewing an order, and return-point maintenance lives in a small menu. Empty lists explain the next step. The tracker hides routine recommendation summaries while keeping important priority/tour/turn-in/risk hints, objective progress and distances visible; full explanations remain in tooltips and expandable details.

Use Compact or Detailed display, collapse secondary content, resize the tracker and adjust text size, background opacity and row counts. Text stays opaque independently of the background; default background opacity is 80%. The gold FQN minimap button controls visibility, opens settings with right-click and moves with left-button dragging.

Other tools include a zone overview, shared quest/item targets, ready turn-in planning, a quest notepad, saved access waypoints with notes, temporary detours, appearance profiles, high contrast, optional quiet combat/taxi views and configurable key bindings. Appearance export/import includes a preview and excludes quest progress, notes and positions.

## Commands

| Command | Opens or performs |
| --- | --- |
| `/fqn` | Toggle tracker |
| `/fqn settings` | Settings |
| `/fqn tools` | Last tool view in the shared window |
| `/fqn find [text]` | Search accepted quests, nearby offers and skips |
| `/fqn tour` | Edit/review a quest tour and return point |
| `/fqn resume` | Explicitly resume a saved priority or tour |
| `/fqn plan`, `/fqn zones` | Automatic planning and zone overview |
| `/fqn notes`, `/fqn access` | Quest notes and saved access routes |
| `/fqn detour` | Temporary outdoor destination |
| `/fqn session` | Session overview |
| `/fqn profiles`, `/fqn share` | Appearance profiles and display transfer |
| `/fqn history`, `/fqn undo` | Supported addon-setting changes and undo |
| `/fqn problem` | Copy a minimal problem report |
| `/fqn status`, `/fqn debug`, `/fqn markers` | Integration and detailed diagnostics |
| `/fqn whatsnew`, `/fqn help` | Update notes and introduction |

## Problems and screenshots

Use `/fqn problem` for a copyable report with version, quest ID, target position and selected technical state. The report uses an allowlist and excludes character names, personal notes and saved access-route names. Review it before sharing. FQN sends nothing automatically. Include reproduction steps and a Lua error, if available, in a [GitHub issue](https://github.com/embertrail-addons/ForeverQuestNavigator/issues).

If Questie is not loaded, check its entry in the game's addon list and `/fqn status`. A missing UI, disabled addon, load error and a missing installation are different conditions.

`/fqn demo` opens labelled screenshot scenes using installed Questie data with simulated character state. `demo next`, `demo map`, `demo plan`, `demo shot` and `demo off` switch scenes, open the map/planning, hide controls and leave the demo. Tours and resume actions are blocked during the demo; it does not alter real quests or saved plans.

## Development

Run Lua 5.1 `tests/run.lua`, the JSON fixtures through `scripts/replay.py`, and `python -m unittest discover -s tests -p "test_*.py"`. Validate metadata with `python scripts/check_release.py`; build with `python scripts/package.py --channel beta`.

Planning state, search, report generation and tracker presentation have separate modules. UI tests exercise actual controls with game API mocks; they do not replace in-game visual verification.

Matching version tags trigger the existing tested GitHub Actions upload to CurseForge. Ordinary main pushes perform a read-only configuration check. The local 0.1.67–0.1.69 changes are not tagged or published.

See [current changelog](release/curseforge-changelog-0.1.69.md), [UX changes](release/curseforge-changelog-0.1.68.md), [0.1.66 release evidence](release/acceptance-0.1.66.md) and [historical development notes](release/development-notes-through-0.1.66.md).

Copyright (c) 2026 Embertrail Addons. All rights reserved. See [LICENSE](LICENSE).
