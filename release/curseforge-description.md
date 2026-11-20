# Forever Quest Navigator

**Choose your next quest with distance, level suitability and known follow-ups in view.**

Forever Quest Navigator (FQN) is a quest companion for **World of Warcraft: Forever 1.60.1**. It compares accepted quests across zone borders and helps you decide where to go next, while you control the gameplay.

## Quest navigation

- A configurable tracker shows your active quest, all objective progress, distance and approximate XP when known.
- A separate, movable direction arrow follows the current target. FQN normally chooses the nearest known unfinished objective; you can select or temporarily avoid a goal yourself.
- Clear objective counters, progress bars, short XP forecasts and labelled turn-in/recommendation states keep the next action readable.
- Open complete quest details beside the navigator. Adjustable height keeps the quest title pinned while content scrolls; Show more appends entries without wheel paging.
- A compact notice area shows arrival instructions or quest-log progress without moving the lists.
- Supported native quest items have a click-to-use button with count and cooldown outside combat. Item-use arrival prompts additionally require confirmed range.
- Open destinations on the world map with removable FQN pins. Supported previews show numbered upcoming stops.
- Compare known follow-up routes, including up to two unambiguous follow-up quests, nearby shared stops and ready turn-in rounds.
- Review possible level-up opportunities and known return travel when comparing quests.
- Pin a quest through the quest log or an accepted quest's context menu. Ordinary list clicks open the map without overriding automatic selection.

## Plan your outing

- Build and review a personal tour of up to 20 accepted quests, reorder stops and start navigation explicitly.
- Preview a closing hand-in round with a saved outdoor return point. Order suggestions use known straight-line distances and require confirmation before changing the tour.
- Search accepted quests, nearby offers and skipped entries by name, ID or known zone through the unified quest finder.
- Optionally remember a tour and quest priority per character, then choose whether to resume it after login.
- Hover map pins and tracker quests to highlight their matching entries. Co-located route stops keep grouped numbers.
- Choose a temporary quest priority until objectives are complete or the quest is turned in; automatic selection then resumes.
- Enable approximate travel times in route details. These are straight-line estimates at walking/current mounted speed, excluding terrain, combat and transport.
- See advisory suggestions when another zone has a compact group of at least three suitable quests with a clear distance advantage.
- Compare known reward base stats and armor against equipped items in tooltips. Accessory slots are compared separately; melee weapons, effects, damage and set bonuses are excluded. There is no automatic upgrade score.
- Discover nearby quests to accept through Questie, with level, estimated XP and explanations of useful overlap or route fit when known.
- Browse quest targets by zone and review shared item requirements across active quests.
- Temporarily lower a quest's priority or try another known area for the same objective.
- Save personal access routes with up to eight ordered waypoints and notes for individual steps.
- Set a temporary stop using an outdoor map ID and coordinates, then automatically resume quest navigation on arrival.
- Get supported quest-action item hints, quest-log capacity reminders and optional travel-preparation warnings.
- Keep persistent skips and a character-specific quest notepad. Skipping never abandons a quest.

## Make it yours

Tools share a window with **Quests, Planning, Activity, Settings and Help** sections. Related views stay together, Back restores your previous view, and searches and filters are retained while navigating. Settings start with common options and provide searchable advanced options with checkboxes, numeric controls and direct selection menus.

Choose Compact or Detailed display, resize the tracker, collapse secondary content and adjust text size, background opacity and visible list lengths. Text remains readable independently of background opacity. Appearance profiles, optional high contrast, adaptive narrow layouts, quiet combat/taxi views and configurable key bindings are included.

Right-click the navigator title to choose Current objective only, Active quest or All recommendations. Try font size, width and opacity in the live appearance preview and restore the previous values if desired. Arrange interface positions both displays with guides and snapping; Done locks both positions.

Share display settings through a copyable code with a preview before applying. Quest progress, skips, positions and notes are excluded. Selected addon changes can be undone through the local change history. **English and German** interfaces are available.

## Getting started

Install FQN for the Forever client and restart WoW. The gold **FQN minimap button** switches display modes; right-click it for settings and drag it with the left mouse button to reposition it.

Useful commands:

- `/fqn` — toggle the tracker
- `/fqn settings` — common settings and tools
- `/fqn arrange` — position the navigator and direction display
- `/fqn plan` — quest planning, turn-ins, shared items and supported chains
- `/fqn detour` — temporary stop
- `/fqn access` — saved access routes and waypoint notes
- `/fqn share` — export/import appearance
- `/fqn notes` — character quest notepad
- `/fqn history` — recorded addon changes and undo
- `/fqn status` — Questie integration status

## Questie integration

FQN can read the game's quest log and map data on its own. For objective spawn locations, nearby offers and supported follow-up planning, install the **Forever-compatible versions of Questie and QuestieDB** separately. They are optional integrations; TomTom is not required.

## How to read the recommendations

Distances and route comparisons use known coordinates and straight-line measurements. They do not account for every mountain, cave, enemy, flight connection or terrain obstacle. Missing targets and unsupported follow-ups remain unknown. XP marked with `~` is an estimate; later-level rewards may change. Item hints do not guarantee that an item is usable at your exact position.

Outdoor elite/group quests are included. Unfinished dungeon, raid and PvP objectives are excluded from normal recommendations; completed special quests remain available for turn-in. FQN gives recommendations and navigation information; you accept, complete and turn in quests, travel and use items yourself.

Source code, documentation and issue reports: [GitHub](https://github.com/embertrail-addons/ForeverQuestNavigator).

**License: All Rights Reserved.**
