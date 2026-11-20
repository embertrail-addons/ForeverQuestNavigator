# Forever Quest Navigator 0.1.76

This release includes the navigator and planning improvements developed since 0.1.66.

## Quest navigation

- Redesigned quest cards, separate objective counters and progress bars, with clear current-objective and destination-quality labels.
- Short XP forecasts show estimated rewards and remaining XP to the next level, or a possible level-up. Detailed reasoning remains in Details.
- Ready quests have a Turn in badge; particularly useful nearby offers retain Recommended.
- Full-width quest information with actions underneath; empty area summaries are hidden.
- Show more appends quest entries. The mouse wheel scrolls without replacing displayed rows.
- Adjustable width and maximum height keep the quest title and priority pinned above scrollable content. Headers share row positioning and clipping.
- A fixed notice area shows arrival instructions or quest-log progress without moving the lists.
- Complete details open beside the navigator or in the tools window when space is limited; the corresponding quest stays highlighted.

## Planning and tools

- Character-specific tours with up to 20 accepted quests, editable order, reviewed order suggestions and a saved outdoor return point.
- Unified finder for accepted quests, nearby offers and persistent skips, with separate map, priority, tour and restore actions.
- Optional saved plans and quest priorities with explicit resume after login.
- Shared tools window: Quests, Planning, Activity, Settings and Help. Back preserves views, searches and filters.
- Improved settings and live appearance preview for font size, width and opacity, with restoration of the opening appearance.
- Completed dungeon, raid and PvP quests remain available for turn-in. Unfinished special objectives stay outside ordinary recommendations; unknown destinations are not invented.

## Interaction

- Quest-item buttons for owned items explicitly associated by the client, with count, cooldown and range feedback. Use requires a player click outside combat; actions are revalidated afterwards.
- Arrival messages can suggest item use when the client confirms range, while preserving access and turn-in instructions.
- Improved external direction display and larger, separated click areas.
- Arrange interface in settings or `/fqn arrange`: position both displays with guides and snapping. Done locks them; Cancel or Escape restores prior positions.
- Copyable technical problem reports omit character names, personal notes and route labels. Nothing is transmitted automatically.

Existing character skips, tours, access routes and notes are retained. Questie and QuestieDB remain optional, separately installed integrations; FQN does not modify or bundle them. TomTom is not required.

**Restart WoW after updating from 0.1.66** to load the new module files. Built for Forever 1.60.1 (interface 16001).
