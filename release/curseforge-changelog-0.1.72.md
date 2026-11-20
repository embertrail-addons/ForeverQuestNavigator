# 0.1.72

Local beta: navigator readability, scrolling and appearance preview. No public tag or upload.

- Unified zone, XP and important notices in consistent information lines. Nearby offers compare their target zone with the player's current zone.
- Marked the quest whose details are open and reflected the open/close state in its detail action. Closing clears the selection immediately.
- Added a title context menu and settings choices for Current objective only, Active quest and All recommendations. These affect presentation only.
- Added adjustable navigator width and maximum height (360–1000 UI pixels, default 600). The title and priority remain pinned; lower content scrolls. Updates retain scroll position, while a new active quest starts at the top. List paging remains available at scroll boundaries.
- Added useful messages and actions for empty selections and targets without known coordinates.
- Shortened hover explanations while preserving full quest names. Complete objective, recommendation and reward information is available in the detail pane.
- Added live appearance-preview controls for font size, width and background opacity. Restore returns to the appearance from when the preview was opened; Keep changes closes it. Preview changes apply immediately and do not alter quest ranking, skips or navigation.
- Extended display import/export to include the new presentation options.

Automated checks cover retained scrolling, small screens, list boundaries, detail selection and rewards, view switching, empty states, zone summaries and appearance restoration. In-game visual confirmation is pending. No screen or window access was used.

Restart WoW after updating: this build adds a Lua module.
