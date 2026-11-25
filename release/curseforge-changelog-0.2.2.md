# Forever Quest Navigator 0.2.2

Quest marks in the world, a target window for the active quest and many small helpers while questing. Existing settings are kept; group sync is now on by default.

## Mark your quest targets

- **Mark targets window** (setting, `/fqn marks` or a key binding): a small movable window lists the NPCs of the **active quest** only – mobs to kill, every mob that drops a needed quest item, or the turn-in NPC. A click targets the NPC by exact name and marks it: **skull** for mobs, **star** for the turn-in NPC. Works in combat; the list itself changes only out of combat.
- The window appears only when the active quest has targets or a usable quest item, has no close button (switch it off in the settings), follows the navigator transparency and hides with "hide all" on the minimap icon and inside instances.
- **Real raid marks:** targeting a mob of the active quest sets the real skull raid mark (turn-in NPC: star). Never replaces an existing mark; in raids only as leader or assistant.
- **Quest marks above mobs:** every other visible mob of the active quest shows the mark and its progress (for example 3/8) above its nameplate (nameplates on, key V).
- **Quest item** of the active quest as a button in the window, **loot reminder** for killed quest-item droppers not yet looted, **respawn estimate** when no quest mob is left in sight, and **danger hints** for elite mobs or mobs three or more levels above you.
- With group sync, the mobs of your **group members' current quests** get a faded skull with the member's name.

## Navigator

- **All open objectives** of the shown quest are listed without expanding (setting, on by default).
- **Unobtrusive in instances:** in dungeons, raids, battlegrounds and arenas the navigator shows one faded line, the screen arrow and all quest marks are hidden.
- **Compact arrow bar** (setting): the screen arrow as one narrow line.
- **Quest sounds** (setting): a soft sound when an objective is finished or the recommendation changes by itself.

## Hints on the way

- Entering a dungeon lists your open quests filed under its name; leaving it names the next turn-in.
- **Turn-in collector:** once, when three or more ready turn-ins lie close together.
- **Hearthstone hint** when it is ready, you are far away and two or more turn-ins wait near your inn (bind your hearthstone once after updating so FQN knows the inn).
- **Bag check** when a tour starts, with grey items you could sell.
- **`/fqn time 45`** opens the tour planner for the given minutes.
- **`/fqn profile`** gives the current character its own appearance settings.

## Also new since 0.2.1

- Install script with SHA-256 verification (`scripts/install.py`), better tour order (2-opt), flight vs. walking comparison, session history (`/fqn session history`), key bindings for the command menu and the next recommendation, tour as chat text with preview, group test mode (`/fqn selftest group`), cues that do not rely on colour alone.
- **Group sync is on by default.** Existing players are switched on once; a later "off" is kept.

## Manual checks still open

Automated tests cover the new features. Not yet checked in the real client:

- Mark targets window: targeting and raid marks by click and by targeting, item button, loot reminder, respawn estimate, danger hints.
- Nameplate marks, including group members' marks with a second FQN player.
- Instance summary and turn-in hint after leaving, quiet navigator inside instances.
- Hearthstone hint, turn-in collector, bag check, `/fqn time`, compact bar, quest sounds, per-character profiles.
