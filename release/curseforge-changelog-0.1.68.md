# 0.1.68

Local beta build; not yet published.

## Interface and usability

- Tools share one window with Quests, Planning, Activity, Settings and Help sections. Related tools use short tabs; only the selected tool panel remains visible.
- Back navigation restores the previous view, including switching between the finder and tour on their shared frame. Searches, filters, planning views and pages are retained while navigating.
- The window fits smaller UI surfaces, preserves its header position when panel sizes change and supports the normal Escape-to-close behavior. Saved display preferences are not reset.
- Settings focus on five common options and searchable advanced options. Checkboxes show boolean state; numeric controls have explicit minus/plus buttons; languages and display modes use direct selection menus. The old tool-button grid is replaced by shared navigation.
- Finder filters show counts and a selection indicator. Rows indicate manual priority, tour membership and unavailable quest states; duplicate tour additions are disabled. Empty results explain the next step.
- Tour controls appear according to state. Order previews have Apply/Close actions; return-point maintenance is grouped into a small menu. A saved-return-only plan has a clear Return now action.
- Automatic planning uses one view selector for shared targets, ready hand-ins, items and chains rather than a grid of mode buttons.
- The tracker retains objective progress, distances and important priority, tour, hand-in and difficulty hints. Routine recommendation summaries stay available in tooltips without occupying a permanent line. Expandable information uses consistent Details labels.
- Quest context menus keep common map/priority/tour actions near the top; duration choices and less frequent actions are grouped.
- A Help overview gathers instructions, problem reports, diagnostics and update notes. Copy dialogs are raised when reopened; update-note height follows its text.
- Screenshot demos retain separate read-only controls and planning, and close the normal tool window when starting. Normal tool navigation is blocked while a demo is active.

## Also includes the unpublished 0.1.67 work

- Personal tours with up to 20 accepted quests, reviewed order suggestions and a saved outdoor return point.
- Unified finder for quest-log entries, nearby offers and persistent skips.
- Optional character-specific saved plans and quest priorities, with explicit resume after login.
- Consistent quest-state symbols and minimal copyable technical problem reports.
- Completed dungeon/special quests stay visible for hand-in even without a known outdoor destination. Unknown instance destinations receive no fabricated outdoor navigation.
- Dedicated modules for planning state/actions, native runtime access, search, reporting and tracker presentation; shorter README with historical notes preserved separately.

Commands: `/fqn tools` opens the last tool view. Existing commands and the settings/minimap shortcuts continue to work.

Automated tests cover navigation, controls, model behavior, read-only demo boundaries and routing compatibility. In-game visual verification is still pending. Restart WoW after installation to load the added module.
