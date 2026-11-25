# Forever Quest Navigator 0.2.1

Follow-up to 0.2.0: easier lists, better diagnostics, tour sharing, a daily goal and a few visual fixes. Existing settings are kept.

## Easier to use

- **All lists scroll:** notepad, access points, feedback, planning, route editor, Tour assistant, command menu and outing scroll with the mouse wheel. The former page buttons became ^ / v, and a count such as "1–5 of 7" replaces "1 / 3".
- **One window at a time:** setup, introduction, update notes, the welcome-back recap and shared tours open one after another, never in combat or on a taxi.
- **Settings:** the short help line under each setting no longer overlaps the setting name; long help texts are cut with "…" (full text in the tooltip).
- **Icons:** the FQN compass appears in the addon list and on the minimap button.

## New

- **Daily goal:** `/fqn goal 40` sets a level goal for today (per character); `/fqn goal off` removes it. The session overview shows progress and an estimate of remaining turn-ins at this session's average.
- **Arrow on the minimap edge (optional):** a small arrow on the minimap rim points to the current target, for rotating and north-up minimaps. Off by default.
- **Share a tour with the group:** "Share with group" in the tour view (or `/fqn tour share`) sends the tour's quest order to your party or raid. Members using FQN confirm before anything changes; adopting only adds stops for quests in their own log. Requires "Share quest progress with my group".
- **Quests unlocking at the next level:** the level forecast also counts known follow-up quests of your active and recently turned-in quests that start in the shown zones.

## Diagnostics

- **`/fqn selftest`** checks every game interface FQN uses, the map canvas, Questie and QuestieDB, and shows the result as copyable text.
- **Error log:** Lua errors inside FQN's events, refresh and tickers are remembered (place, file:line, count, version; at most 10) and included in `/fqn problem` and the self-test. They still reach the game's error display.

## Behind the scenes

- New release preparation script (`scripts/release.py`) and a full quest log scenario (25 quests, 5 zones) with time budgets in CI.
- The packager includes the addon-list icon unchanged.

## Manual checks still open

Confirmed in the real client: self-test (29 of 29 interfaces OK, no errors), minimap arrow direction and visibility, compass icons, settings help lines.

Not yet checked in the real client:

- Tour sharing and group sync with a second player using FQN 0.2.1 (party and raid).
- Daily goal display and estimate over a play session.
- The notice queue when several automatic windows are due at once.
- Scrolling in all converted lists with long content.
