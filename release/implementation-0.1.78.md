# Local implementation map — 0.1.78

The following covers the requested UI/UX and functionality proposal. Nothing has been committed, pushed, tagged or published for this version.

| Proposal | Implementation / entry point |
| --- | --- |
| Now / Next / Surroundings | Focus and Overview; collapse button, menu and settings share one state; complete lists live under Surroundings; old focused views and imported layouts migrate |
| Three color directions | Color design setting; Graphite & Gold default, Parchment & Bronze, Midnight & Turquoise |
| Semantic colors and accessibility | Level-only title coloring, green hand-ins, blue XP, group text; high contrast, reduced colors and opaque text at zero background opacity |
| Clearer active card | Neutral title, consolidated phase/priority/group state, current objective/counter/distance, fixed Map / Why / ... action row |
| Less competing UI | Three next actions; optional complete lists; separate detail sections for quest, travel, why and rewards |
| Actionable next steps | Accept first, turn in, along the way and next suitable active quest; map actions never change priority |
| Stronger destination areas | Existing bounded area clusters now add explicit comparison context, approach distances and known/unknown round XP; follow-up previews include both supported depths |
| Pickup preparation | Capacity/reserve-aware before-departure list; actual acceptance removes the available offer; required pickups appear inside expanded areas |
| Difficult / inconvenient targets | Group text; new temporary feedback for missing enemies, waiting for a group, blocked access and bounded area avoidance; manager, clear and undo |
| Situational navigation | Travel, arrival, hand-in and flight phase text uses existing arrival hysteresis; combat/flight keep quiet views and preferences |
| Understand the calculation | Decision comparison with distance/difficulty/known XP/data quality; explanation export from planning |
| More planning information | Shared item requirements remain reachable; all known ready hand-ins grouped by destination; explicit session-closing suggestions; remembered round progress and return-to-hand-in advice |
| Better interaction | Larger next-action controls, independent menus, preserved inspection marks, wrapping constraints and spacing tested at narrow/wide widths |
| Preview and reset | Live palette selection, design reset, restore opening state; appearance export/import includes theme and layout |
| Refactoring | DecisionBrief supplies action, comparison, closing and report views; OutingLedger tracks evidence independently of navigation; theme roles are centralized; demo rewards are injected |
| Verification | Lua 5.1 integration tests, focused decision/progress tests, 12-case guided layout matrix, Python package/upload-policy tests, replay fixtures and translation parity |

Exact itineraries for an arbitrary time budget remain conditional on reliable quest-completion timing data, as in the proposal. This version does not invent combat or quest-duration estimates. Existing travel-time estimates keep their coordinate-based limitations.

In-game layout/Questie acceptance remains pending; see ui-smoketest-0.1.78.md. No screen access was used.
