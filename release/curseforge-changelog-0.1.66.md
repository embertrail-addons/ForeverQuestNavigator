# 0.1.66

- Reworked shared map markers for accepted quests, offers, route stops and screenshot demo scenes. Canvas-anchored pins track map pan/zoom and map changes without sharing other addons' native pin pools.
- Pending targets survive delayed map loading. Right-click clears a marker; co-located route stops show grouped numbers at their actual coordinates.
- Pins explicitly follow the map's display strata, render above the map layers and have an opaque border. Expanded `/fqn markers` output reports actual visibility, alpha, position and renderer revision.
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
