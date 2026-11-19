# 0.1.66

- First stable Release, following the user's successful in-game marker tests.
- Hover a numbered map pin to highlight matching tracker quests; hover a tracker row to highlight its pin. Co-located stops stay grouped.
- Accepted-quest context menus can prioritize a quest until its objectives are complete or until it is turned in, then resume automatic selection.
- Optional approximate travel time in route details uses straight-line distance and walking/current mounted speed, excluding terrain, combat and transport.
- Advisory zone suggestions require at least three suitable quests within a compact area and a substantial distance advantage. They do not override manual selection or nearby work.
- Optional reward tooltips compare cached base stats and armor with equipped gear, including separate accessory slots. No upgrade score; melee weapons, effects, weapon damage and set bonuses are excluded. Unknown data is never treated as zero.
- Reworked shared map markers for accepted quests, offers, route stops and screenshot demo scenes. Canvas-anchored pins track map pan/zoom and map changes without sharing other addons' native pin pools.
- Pending targets survive delayed map loading. Right-click clears a marker; co-located route stops show grouped numbers at their actual coordinates.
- Compact pins explicitly follow the map's display strata and render above the map layers without a box or frame. Route numbers use white text with a shadow. Expanded `/fqn markers` output reports actual visibility, alpha, position and renderer revision.
- Fixed a tooltip heading call that passed a boolean as the native numeric alpha argument.
- Fixed demo refreshes clearing the selected map destination, and corrected mapping an individual demo offer or route stop.
- Clearer recommendation reasons and short explanations when the automatically selected quest changes.
- Target information distinguishes known quest giver/object positions, saved access points and objective search areas.
- Arrival hints describe the next manual step, such as turning in a quest or searching the nearby objective area.
- Optional, once-per-version update notes; reopen with `/fqn whatsnew` or disable in settings.
- Local performance measurements with `/fqn perf on`, `/fqn perf` and `/fqn perf off`. No global game profiling or data transmission.
- Screenshot demo with authentic Questie data and fixed simulated character states for Barrens and Elwynn. Includes objectives, turn-ins, Compact display and a separate planning window.
- Structured GitHub bug reports and expanded tests for map lifecycle, marker grouping, safe demo state, update notices and timing.
- Automatic release checks cover version/changelog matching, EN/DE translations and required package files.

Restart WoW after updating to load the new modules. Demo scenes are labelled and do not modify real quest state or saved settings. Route distances and XP remain estimates; unsupported information remains unknown. Built for Forever 1.60.1; Questie integrations are optional except for the screenshot demo.
