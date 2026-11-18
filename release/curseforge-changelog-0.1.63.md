Local development build 0.1.63 — not published.

- Saved access routes support up to eight ordered manual waypoints, retaining existing single-point saves.
- Access management includes a route editor for mapping, reordering and deleting individual points.
- Navigation advances through waypoints in order; approach/return estimates include the saved path. Taxi flight does not mark points visited.
- Added configurable key bindings for quest planning, another known area for the active objective, and temporary feedback. No keys are assigned automatically.
- Added optional money and item reward information in quest tooltips, distinguishing guaranteed items from choose-one rewards and missing data from reported zero rewards.
- Reward reads are cached, support item-loading refreshes, and do not change quest selection, reward choice or recommendation scores.

Saved paths are manual guidance and straight-line estimates, not terrain pathfinding. Game-client validation is still required before publishing. Existing skips, notes and character progress are preserved.
