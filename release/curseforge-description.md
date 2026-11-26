# Forever Quest Navigator

**Choose your next quest with distance, level suitability and known follow-ups in view.**

Forever Quest Navigator (FQN) is a quest companion for **World of Warcraft: Forever 1.60.1**. It compares your accepted quests across zone borders, shows where to go next and guides you there. You stay in control: FQN never accepts, completes or turns in quests for you.

## New in 0.2.7

*   **Smooth in cities:** route planning in Undercity dropped from about 93 ms to 10 ms per update.

## New in 0.2.6

*   Fixes the blocked-action message at login, and **skip a quest** directly from the quest menu.

## New in 0.2.5

*   **Much smoother:** route planning is about 300 times faster and quest log updates about twice as fast.

## New in 0.2.4

*   Fixes the "only available to the Blizzard UI" message and micro stutters while the navigator is shown.

## New in 0.2.3

*   **Smarter recommendations:** FQN now weighs **XP per minute**, the way to the turn-in, what comes next, follow-up quests and **nearly finished quests** – not only distance. The quest tooltip tells you why, and why it beats the runner-up.
*   **Learns how you play** (per character): your real travel speed, kill pace and preferred kind of quest. `/fqn learn` shows it, `/fqn learn reset` clears it.
*   **Target marks that just work:** clicks mark with `/tm`, **each click jumps to the next living quest mob**, and two key bindings target and mark the next quest mob or the turn-in NPC – no friendly nameplates needed.
*   **Shared mobs:** "Also counts for: …" when one mob counts for two of your quests.

## Added in 0.2.2

*   **Mark targets window:** lists the mobs of your active quest (including every mob that drops a needed item) or its turn-in NPC. One click targets and marks it: **skull** for mobs, **star** for the turn-in NPC. It shows up only when there is something to mark.
*   **Real raid marks** with one click or key, and **quest marks with progress** (for example 3/8) above every other quest mob's nameplate.
*   **Loot reminder, respawn estimate and danger hints** for elite or much stronger quest mobs; the quest item sits in the window too.
*   **All open objectives** at a glance, and a **quiet navigator inside dungeons and raids**.
*   **Hints on the way:** dungeon quest summary, next turn-in after leaving, hearthstone and turn-in collector hints, bag check before a tour, `/fqn time 45` for a tour that fits your time.
*   **Compact arrow bar**, soft **quest sounds** and **per-character profiles** (`/fqn profile`).
*   **Group sync is now on by default**; group members' quest mobs get a faded skull with their name.

## Added in 0.2.1

*   **Daily goal:** `/fqn goal 40` sets a level goal for today; the session overview shows progress and how many turn-ins are roughly left.
*   **Share your tour with the group:** send your quest order to party members who also use FQN; they confirm before anything changes.
*   **Arrow on the minimap edge (optional)** pointing to your current target.
*   **Every list scrolls** with the mouse wheel, and automatic windows open one at a time, never in combat or on a taxi.
*   **`/fqn selftest`** checks the game interfaces FQN uses; `/fqn problem` now includes recent FQN errors for bug reports.
*   The FQN compass in the addon list and on the minimap button.

## Added in 0.2.0

*   Quick setup on first start and **Simple mode** for new installations; expert mode adds tours, planning, outings and history.
*   One tool window with a **searchable command menu** (`/fqn menu` or right-click on the minimap button).
*   **Route line on the world map**, a **distance bar**, a **level forecast** over several turn-ins and a **session recap**.
*   **Group sync** with party members who also use FQN (on by default since 0.2.2).

## Quest navigation

*   The navigator shows your active quest, objective progress, distance and approximate XP when known. One "Next" step and a compact row of actions keep the following decision in view.
*   A separate, movable direction arrow follows the current target, with a progress bar for the current leg. FQN normally chooses the nearest known unfinished objective; you can select or temporarily avoid a goal yourself.
*   Optionally, a small arrow on the minimap edge points the same way, for rotating and north-up minimaps.
*   Local Questie spawn areas and enemies you are actually fighting help recognize when you are already working on an objective.
*   During ghost runs, corpse navigation takes priority with a stable destination. Quest navigation resumes after resurrection.
*   Quest items get a click-to-use button with count and cooldown outside combat.
*   Open destinations on the world map with removable FQN pins. Upcoming stops are numbered and connected by a route line.
*   Compare known follow-up routes, nearby shared stops and ready turn-in rounds. Level-up forecasts show when your next turn-ins reach a new level and which known follow-up quests unlock then.
*   Pin a quest through the quest log or a quest's context menu. Ordinary clicks only open the map and never override automatic selection.

## Plan your outing

*   **Outings** combine pickups, objectives and known hand-ins in one reviewed order, using coordinate travel, level suitability, possible XP and quest-log capacity. Start, pause and resume explicitly.
*   **Tour assistant:** departure checks, tour comparisons, hand-ins on the way, level-up review, quest chains, bag warnings and reminders.
*   Build a personal tour of up to 20 accepted quests, reorder stops, save a return point and share the tour with your group.
*   Search accepted quests, nearby offers and skipped quests by name, ID or zone.
*   Discover nearby quests to accept through Questie, with level, estimated XP and why they fit your route.
*   Browse quest targets by zone, review shared item requirements, save personal access routes with notes and set temporary outdoor stops.
*   Skip a quest or a suggested pickup without abandoning anything; restore it any time. A character-specific notepad keeps your own notes.
*   The session overview records turn-ins, XP per hour and zones, offers a recap when you return and tracks a daily level goal.

## Group sync

When **Share quest progress with my group** is enabled, FQN sends your active quest IDs, objective counts (for example 3/5) and your current target quest to your own party or raid, at most every 3 seconds and never during combat. Only when you click **Share with group** does it also send your tour's quest order; members confirm before adopting it, and adopting only adds quests from their own log. Members who also use FQN see shared quests and progress, and quests several members still need rank slightly earlier. Nothing is saved, and a member's data is dropped when they leave. The setting is on by default since 0.2.2; with it off, FQN sends no addon messages.

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
*   `/fqn goal 40` — level goal for today (`/fqn goal off` removes it)
*   `/fqn arrange` — position navigator and arrow
*   `/fqn problem` — copyable problem report
*   `/fqn selftest` — check the game interfaces FQN uses

## Questie integration

FQN works with the game's quest log and map data on its own. For spawn locations, nearby quest offers and follow-up planning, install the **Forever-compatible versions of Questie and QuestieDB** separately. They are optional; TomTom is not required.

## How to read the recommendations

Distances, routes and travel times use known coordinates and straight lines. They do not account for every mountain, cave, enemy, flight path or obstacle. Missing targets stay marked as unknown. XP marked with `~` is an estimate. Item hints do not guarantee that an item can be used at your exact position.

Outdoor elite and group quests are included. Unfinished dungeon, raid and PvP objectives are excluded from normal recommendations; completed ones remain available for turn-in. FQN gives recommendations and navigation; you accept, complete and turn in quests, travel and use items yourself.

Source code, documentation and issue reports: [GitHub](https://github.com/embertrail-addons/ForeverQuestNavigator).

**License: All Rights Reserved.**
