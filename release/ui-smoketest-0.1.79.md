# 0.1.79 gameplay and UI acceptance — not yet performed

Restart WoW after installation to load the new modules. These checks require a person playing the game; automated tests do not certify the real client or its Questie data.

1. Cross a zone boundary with a quest whose objective is in a neighbouring zone. Confirm map, destination and recommendation remain consistent.
2. Compare two known areas for a kill objective. Inspect versus choose; small movements should not flip areas. A finished/removed objective releases the choice.
3. Use a saved access route around a barrier. Its known length should influence ranking; unknown terrain is never a verified shortcut.
4. Fill the quest log. Check highlight limits, nearby hand-in advice and refusal to start a pickup-first outing without space.
5. Test repeatable modes, a manual priority in show-only mode and an actual repeatable hand-in.
6. Quest planning -> Quest areas (expand an area) or Next round -> Build outing from area. Inspect before Start; no quest or priority changes before that explicit action.
7. Start, pause and resume. Arrival waits for acceptance; all remaining objectives finish before hand-in. Abandoning/skipping a needed quest pauses the outing.
8. Inspect starter items and prerequisites. Missing data remains unknown; items granted by the giver are not missing starter requirements.
9. Save, clear and undo a multiline German note. Reload; verify per-character persistence, details and full notepad tooltip.
10. Verify FQN legend colors/numbers and clear only FQN markers alongside Questie; test right-click removal.
11. Settings categories, advanced search and example preview: small/wide windows, 80%/140% text, Focus/Overview, zero navigator opacity and readable settings dialogs.
12. Longer play session: recommendation notices, stable frame times, flight/combat transitions and statistics. Record any Lua error verbatim.

Record actual results in acceptance-0.1.79.md. Leave unperformed checks unchecked.
