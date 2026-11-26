# Forever Quest Navigator 0.2.4

Fix release for 0.2.3. Existing settings are kept.

## Fixes

- **"Only available to the Blizzard UI" message:** FQN tried to set a raid mark by itself when you targeted a quest mob. WoW Forever does not allow addons to do that. This automatic marking is removed (together with its setting). Marks are set with a click in the Mark targets window or with its two key bindings, which use `/tm` and work as before.
- **Micro stutters while the navigator is shown:** several new features recalculated in the background and created short-lived data that the game then had to clean up.
  - Questie NPC lookups (names, levels, turn-in NPC) are remembered per NPC.
  - The target list is built once per second and shared by the window, the nameplate marks and the key bindings.
  - Mobs shared by several quests are recalculated only when the quest log changes, not on every step.
  - The look-ahead in the recommendations checks the 8 nearest quests and remembers distances while targets stay the same.

If stutters remain, `/fqn perf on`, some play and then `/fqn perf` show which part takes how long.

## Manual checks still open

Not yet checked in the real client: absence of the blocked-action message and of stutters on the affected installation; marking by click and key bindings after the change.
