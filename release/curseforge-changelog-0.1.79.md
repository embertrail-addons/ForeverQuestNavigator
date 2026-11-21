# Forever Quest Navigator 0.1.79

Regular release covering the changes since 0.1.76.

- Focus and Overview replace the overlapping navigator views. The collapse button, title menu and settings use the same state; complete lists are available through Surroundings.
- Graphite & Gold, Parchment & Bronze and Midnight & Turquoise designs, with preview/reset, high contrast and reduced colors. Settings dialogs have an opaque background independent of navigator opacity.
- Clear Now / Next / Surroundings layout, consolidated quest/travel/reason/reward details, larger action targets and pickup-versus-objective information.
- Capacity-aware pickup advice, expandable destination clusters, known follow-up previews, remembered round progress, grouped hand-ins, session-closing advice and decision explanations.

- Reviewed outings from suggested areas: pickups, quest objectives and known hand-ins. Explicit start, pause/resume and evidence-based advancement; arrival cannot complete a pickup, and removed/skipped quests pause the outing.
- Spawn-area comparisons include nearby active-quest combinations and stable selection during travel. Explicit choices remain until their objective changes or the area is unavailable.
- Known saved-access length now influences ranking instead of only the entrance distance, without double-counting that access leg in return-travel preference. Unknown terrain stays unverified.
- Recommendation-change notices distinguish new accepted quests, completed objectives, observed hand-ins and closer known hand-in locations.
- Repeatable modes: include in levelling, finder/offers only (default), or hide. Informational repeatables do not dominate automatic highlights; unknown repeatability is preserved.
- Questie starter metadata shows supported required bag items, prerequisites, extra requirements and group needs. Missing inventory or metadata stays unknown.
- Personal Unicode quest notes with scrolling, clear-text action, undo and per-character persistence. Active notes appear in details separately from the automatic explanation export.
- FQN map legend and clear-markers action, alongside right-click removal, without changing other map providers.
- Quick settings separate appearance/display from recommendations/data and link directly to example-data preview.
- Offline gameplay scenarios, runtime outing tests, a known-access replay and pending in-game acceptance checklist.

Coordinate estimates do not verify terrain, mountain paths, doors or shared enemies. Previews show known starting locations; navigation follows remaining objectives. Unknown finishers and rewards are explicit.

Validation: 212 Lua 5.1 tests, 19 Python tests and five replay fixtures. Real-client gameplay/visual acceptance for this version remains pending; automated coverage does not certify it.
