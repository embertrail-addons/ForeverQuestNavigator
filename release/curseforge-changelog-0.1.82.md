# Forever Quest Navigator 0.1.82 — local development

Not published. No commit, push, release tag or upload is part of this change.

## Features

- **Hand-ins on the way:** ready quests with at most 400 additional coordinate yards toward the current destination. Show the estimated detour; exclude blocked and already-planned hand-ins. Add opens an independent preview, preserving the old plan until explicit Start. No walking-path or travel-time guarantee is implied. Unknown cross-map transforms cannot produce a recommendation.
- **Quest items:** visible count, cooldown, known/unknown range and an explicit item-use instruction. A highlighted secure icon remains a manual action; no collected objective item is assumed usable. Existing combat restrictions remain.
- **Bags and merchants:** warn about at most three general-purpose free slots for an unfinished collecting quest. Specialized bags are excluded; incomplete reads remain unknown. Remember a merchant only while its shop is open. Suggestions use at most 20 character-local saved visits, labelled as approximate player positions; nearest visited merchant appears when space is low. It can be removed. No automatic selling.
- **Quest chains:** expand known future destinations in Tour assistant. Unknown coordinates and prerequisite availability remain explicit; opening a map never accepts or selects a future quest.
- **Later:** quest menus offer after-round, area-visit and group reminders. Save per character without changing skips, quest acceptance or priority. Relevant reminders appear contextually; remove them independently. Completed history does not suppress an explicitly active repeatable. After-round reminders track the selected session-local round; an already completed round does not immediately trigger a newly saved reminder. A lost session-local round remains reviewable in the list rather than falsely completed.
- **Tour comparison:** show a closer objective area and a distinct alternative, preferring one with more quests when available. Show potential XP, known returns and distance with limitations. These are area comparisons, not proven optimal route solutions. Pick a preview before Start; capacity is validated in the outing preview.
- **Simple navigator:** optional, off by default. Retain current objective, one Next action and access to tools/details; hide extra tour cards and lists. Relevant bag/reminder/change hints stay reachable. Disabling restores the saved overview preferences.

## UI / UX review

- Replaced the growing tab grid with three stable groups and an explicit view selector: Plan; On the way; Remember & review.
- Kept action positions consistent: Map at the right, Details or the explicit row action next to it; full row text opens Details.
- Moved long explanations behind a visible Details action while keeping a short section description. Added actionable empty-state guidance.
- Sized assistant/outing windows to visible content and font metrics, separating summaries, rows and footers. Hid unnecessary paging arrows.
- Kept the main board to one Next action; the redundant second route-planning action now opens tour comparison. The simple mode avoids adding permanent rows for every feature.
- Added geometry/state checks across English/German, 80%/140% text and graphite/parchment/midnight themes. These mock checks do not replace actual font/rendering verification in WoW.

## Acceptance still required in game

No screen access or live gameplay testing was performed.

1. Restart WoW; test `/fqn assist`, the three groups, view selector, Details, empty states and paging at both font extremes. Verify rows, footer controls and long German labels fit at your UI scale.
2. Compare a short-area and alternative-area tour. Open/close previews without Start, then Start explicitly. Check an along-route hand-in during a running outing, repeated hand-ins and unknown/cross-zone targets.
3. Check the quest item at known/unknown range and during cooldown/combat. Confirm the icon works only after your own click.
4. Try a collecting quest with full bags, specialized bags and missing bag data. Open a merchant, save the visit, close it, inspect/remove its suggestion. Verify no item is sold automatically.
5. Save each reminder type, reload, change zones, join/leave a group and finish a tracked round. Newly saved after-round reminders must not fire because a previous round was already finished.
6. Expand known/unknown chains. Check prerequisite warnings against the quest text and coexistence with Questie.
7. Toggle Simple navigator while the overview was expanded. Ensure important hints and Details remain accessible, then restore the previous view.

Existing scripted coverage also exercises level-up review, quest acceptance/removal, objective completion, real hand-ins, zone changes, absent Questie and map-marker behavior. No in-game test is claimed completed by these scripts.
