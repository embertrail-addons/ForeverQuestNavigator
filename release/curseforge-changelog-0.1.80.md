# Forever Quest Navigator 0.1.80 — local development

Not published. No release tag, commit or upload is part of this development step.

- Review an area tour directly from the guided navigator: active quests, pickups, known return destinations and potential quest XP. Unknown XP/finishers remain explicit. Preview the existing ordered pickup/objective/hand-in plan before Start.
- A shared short explanation includes recommendation context, level fit and known follow-ups. Compare the nearest measured alternative in planning; a closer target is not asserted to be a better or faster route.
- Nearby pickup distance alone no longer qualifies for a strong highlight. Large pickup detours lose that highlight even when objectives share an area. Nearby objectives do not prove shared enemies.
- Contextual return advice combines two or more ready hand-ins within 600 yards of an anchor with an approach of at most 2,500 yards. Dungeon hand-ins remain eligible; feedback exclusions and missing transforms cannot create a cluster. View potential XP and known follow-up chains before travelling.
- The guided main window shows one Next action. Full lists remain under Surroundings; XP, route information and explanations remain in Details. Hide absent tour/return/recap controls and empty Next headings. Keep phase/manual/group warnings concise.
- Existing recommendation hysteresis is covered by repeated small-movement tests; substantial advantages still allow a switch. Actual turn-ins, acceptance and objective completion retain distinct temporary change notices.
- Explicitly started outings expose a dismissible recap: real deduplicated hand-in count, actual quest reward XP, unknown rewards and remaining unique quests. Arrival does not grant XP or complete quests. No combat, exploration or estimated XP is counted. Recaps are session-local; paused plans remain resumable.
- Reuse action-row layout, tour summaries and recommendation explanations. Guard unavailable map APIs and incomplete measurements instead of inventing distances.

## Manual checks still required

No game screen was accessed. In-game rendering, addon coexistence and a longer gameplay session have not been verified for this version.

1. Restart WoW to load the updated TOC. Review a tour from Overview; map clicks must not start it or change manual priority.
2. Compare English/German, 80%/140% fonts, narrow/wide windows and all themes. Check two-line tour/return buttons and Details scrolling.
3. Accept a useful nearby quest; compare with a pickup whose objectives require a detour. Check a full log, absent Questie, missing coordinates and a cross-zone destination.
4. Complete several quests with clustered finishers, including an outdoor dungeon hand-in. Check return advice, unknown XP and known follow-ups against quest text.
5. Start/pause/resume an outing, actually hand in quests, open recap and dismiss it. Test zero/unknown XP and verify estimates are never presented as received XP.
6. Walk near competing targets: small differences should remain stable; completion, acceptance, skip, large distance changes and manual selections should still update correctly.
