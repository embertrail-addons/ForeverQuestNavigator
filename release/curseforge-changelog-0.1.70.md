# 0.1.70

Local beta: navigator interface refinement. No public release, tag or upload.

- Emphasized the active quest with a restrained accent and highlighted navigation objective. Open objective progress remains visible.
- Aligned status, quest, direction, distance and detail actions across quest lists. Reduced row contrast and secondary text emphasis.
- Moved routes, upcoming stops and complete nearby-offer information into a shared scrollable detail pane. Opening details no longer changes tracker or row height.
- Details use the free side of the navigator, or the shared tool window when neither side has space. Both layouts support closing and reopening.
- Replaced skip checkboxes with action buttons. Accepted quest details also offer a labelled Skip quest action, with the existing undo/restore behavior. Offers do not get a skip action.
- Kept quest rows under the cursor stable while interacting or reading details, without changing live ranking, navigation or the mapping between a quest and its route/rewards. Removed entries are removed immediately.
- Nearby rows show a short summary; full recommendation, objective travel and reward information remains available in details and tooltips.
- The external arrow emphasizes the current objective and distance, reveals the quest on hover, and uses the same quest-state indicators as the navigator. Background opacity and saved dragging behavior remain supported.
- Automatic quest switches explain their reason briefly through the external display, or in the tracker when that display is disabled.

Automated checks cover pane placement, repeated opening, the narrow-screen tool fallback, compact view, quest/map association, skip behavior, interaction ordering and the external arrow layout. In-game visual confirmation is still required. No screen or window access was used.

Restart WoW after installing: this build adds a Lua module.
