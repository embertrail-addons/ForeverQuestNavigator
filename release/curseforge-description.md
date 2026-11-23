# Forever Quest Navigator

**Choose your next quest with distance, level suitability and known follow-ups in view.**

Forever Quest Navigator (FQN) is a quest companion for **World of Warcraft: Forever 1.60.1**. It compares your accepted quests across zone borders, shows where to go next and guides you there. You stay in control: FQN never accepts, completes or turns in quests for you.

## New in 0.2.0

*   **Quick setup on first start:** choose navigator or arrow only, Questie data on or off, and Simple, Standard or Expert detail.
*   **Simple mode:** new installations start with the essentials. Switch to expert mode for tours, planning, outings and history. Existing players keep their current view.
*   **One tool window** for quests, planning, outings, activity, settings and help, plus a **searchable command menu** (`/fqn menu` or right-click on the minimap button).
*   **Route line on the world map** connecting the next stops, and a **distance bar** showing how much of the way is already covered.
*   **Level forecast:** see how many of the nearest turn-ins reach your next level.
*   **Session recap** with XP per hour, the zones you played and a suggestion for next time.
*   **Optional group sync:** share quest progress with party members who also use FQN (off by default).
*   A calmer navigator with quest symbols, one row of actions and scrollable lists.

## Quest navigation

*   The navigator shows your active quest, objective progress, distance and approximate XP when known. One "Next" step and a compact row of actions keep the following decision in view.
*   A separate, movable direction arrow follows the current target, with a progress bar for the current leg. FQN normally chooses the nearest known unfinished objective; you can select or temporarily avoid a goal yourself.
*   Local Questie spawn areas and enemies you are actually fighting help recognize when you are already working on an objective.
*   During ghost runs, corpse navigation takes priority with a stable destination. Quest navigation resumes after resurrection.
*   Quest items get a click-to-use button with count and cooldown outside combat.
*   Open destinations on the world map with removable FQN pins. Upcoming stops are numbered and connected by a route line.
*   Compare known follow-up routes, nearby shared stops and ready turn-in rounds. Level-up forecasts show when your next turn-ins reach a new level.
*   Pin a quest through the quest log or a quest's context menu. Ordinary clicks only open the map and never override automatic selection.

## Plan your outing

*   **Outings** combine pickups, objectives and known hand-ins in one reviewed order, using coordinate travel, level suitability, possible XP and quest-log capacity. Start, pause and resume explicitly.
*   **Tour assistant:** departure checks, tour comparisons, hand-ins on the way, level-up review, quest chains, bag warnings and reminders.
*   Build a personal tour of up to 20 accepted quests, reorder stops and save a return point.
*   Search accepted quests, nearby offers and skipped quests by name, ID or zone.
*   Discover nearby quests to accept through Questie, with level, estimated XP and why they fit your route.
*   Browse quest targets by zone, review shared item requirements, save personal access routes with notes and set temporary outdoor stops.
*   Skip a quest or a suggested pickup without abandoning anything; restore it any time. A character-specific notepad keeps your own notes.
*   The session overview records turn-ins, XP per hour and zones, and offers a recap when you return.

## Group sync (optional)

When **Share quest progress with my group** is enabled, FQN sends your active quest IDs, objective counts (for example 3/5) and your current target quest to your own party or raid, at most every 3 seconds and never during combat. Members who also use FQN see shared quests and progress, and quests several members still need rank slightly earlier. Nothing is saved, and a member's data is dropped when they leave. With the setting off (the default), FQN sends no addon messages.

## Make it yours

*   Simple or expert mode, Focus or Overview navigator, compact or detailed tracker.
*   Adjust text size, width, height and background opacity; text stays readable at any opacity. Try changes in a live preview.
*   Three color designs, high contrast and reduced colors. Quest symbols or action words.
*   Position the navigator and arrow with guides (`/fqn arrange`), use appearance profiles and key bindings, and share display settings as a code with preview.
*   Undo supported changes through the change history. **English and German** interfaces are available.

## Getting started

Install FQN for the Forever client and restart WoW. New installations start with a short setup. The gold **FQN minimap button** switches display modes; right-click it for common commands and settings, and drag it to reposition it.

Useful commands:

*   `/fqn` — show or hide the navigator
*   `/fqn menu` — searchable list of all commands
*   `/fqn settings` — settings with search
*   `/fqn setup` — run the setup again
*   `/fqn tools` — the tool window
*   `/fqn find [text]` — search quests
*   `/fqn plan` — planning, turn-ins and quest chains
*   `/fqn assist` — Tour assistant
*   `/fqn session` — session overview and recap
*   `/fqn arrange` — position navigator and arrow
*   `/fqn problem` — copyable problem report

## Questie integration

FQN works with the game's quest log and map data on its own. For spawn locations, nearby quest offers and follow-up planning, install the **Forever-compatible versions of Questie and QuestieDB** separately. They are optional; TomTom is not required.

## How to read the recommendations

Distances, routes and travel times use known coordinates and straight lines. They do not account for every mountain, cave, enemy, flight path or obstacle. Missing targets stay marked as unknown. XP marked with `~` is an estimate. Item hints do not guarantee that an item can be used at your exact position.

Outdoor elite and group quests are included. Unfinished dungeon, raid and PvP objectives are excluded from normal recommendations; completed ones remain available for turn-in. FQN gives recommendations and navigation; you accept, complete and turn in quests, travel and use items yourself.

Source code, documentation and issue reports: [GitHub](https://github.com/embertrail-addons/ForeverQuestNavigator).

**License: All Rights Reserved.**
