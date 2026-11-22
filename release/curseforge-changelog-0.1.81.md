# Forever Quest Navigator 0.1.81 — local development

Not published. No commit, push, tag or upload is included in this development step.

1. **Before departure:** a compact list of useful pickups with giver coordinates, prerequisites and free-log information. Acceptance stays manual. Open Tour assistant in Overview or `/fqn assist`.
2. **Time budgets:** cycle 0 / 15 / 30 / 60 minutes in the outing preview. Timed subsets retain whole quests with known returns and measurable coordinate legs. Bounds are heuristic assumptions, not calibrated predictions: 180–420 yards/min, 4–12 min per unfinished quest, 2 per pickup and 1 per hand-in. The upper heuristic selects the subset. Terrain, drops, combat and transport can invalidate it; unknown/over-budget quests are explicitly omitted. Start remains explicit.
3. **Blocked target:** the quest menu's “I cannot continue here” pauses and retains the outing, temporarily marks that quest blocked and opens suitable alternatives. Map is read-only; Choose explicitly changes priority. Resume the retained outing from its recap/preview.
4. **Together:** optional native `C_QuestLog.IsUnitOnQuest` checks for party/raid members. Confirmed same-quest counts are separate from unknown results and do not imply matching objective progress. Five-second caching while the panel is open; no addon communication, names or peer data persistence. Disabled by default; available in settings or Together.
5. **After levelling:** improved-difficulty quests are reviewable; the existing target is briefly retained for up to 60 seconds. Manual priorities and running plans win; hand-in/removal clears an invalid hold. Choose or Recalculate releases the temporary hold. The notice opens the actionable review.
6. **Personal corrections:** save your current outdoor position for a selected indexed unfinished objective or hand-in from the quest menu. Corrections are labelled, stored per character and separately resettable under Corrections. Other objectives remain unchanged; completed/missing objectives ignore the correction. Questie data is not edited. Stand at the actual destination before saving. Existing access-route tools remain available for entrances.
7. **Direct actions:** named known hand-ins say “Speak to …”; access names and literal current objective text remain visible. No inferred mob identity or fabricated quest instruction.
8. **Tour revisions:** extra suitable objectives within 400 coordinate yards of unfinished outing objectives are offered for review. The proposal retains still-pending pickups and current quests. Reviewing or closing it does not replace the old tour. Explicit Start adopts the new plan.
9. **Consistent secondary windows:** shared close/button hit areas, explicit Map/Details controls in planning, persistent planning pages and Tour assistant tabs, and preserved excursion pagination. Full row information is accessible through Details rather than depending on hover alone.
10. **Color-independent cues:** optional short difficulty words (default on), textual recommendation/selection labels and larger utility hit areas. Turn-ins use an action label rather than a misleading high-level warning.

## Manual acceptance still required

No screen access or real-client rendering test was performed. Restart WoW for the new modules, then test:

- Tour assistant in English/German and at 80%/140% fonts, narrow/wide layouts and all three themes. Check tab/footer wrapping, Map/Details/Choose and page restoration after closing.
- Useful pickups with a full log and missing Questie data. Timed previews with zero feasible quests, missing finishers and cross-zone legs; compare estimates against actual travel without treating them as guarantees.
- Native party/raid checks enabled and disabled, unsupported API and out-of-range/unavailable members. Confirm that same-quest counts are not treated as objective completion.
- Level-up during ordinary navigation, an explicit priority and a running outing. Check the 60-second hold, Choose, Recalculate, removal and actual turn-in.
- Personal objective/hand-in correction, reload persistence, reset, objective completion and another map. Save only at the intended target; test coexistence with Questie/map pins.
- Block an outing target, choose an alternative and resume. Accept a nearby matching quest, review the revised tour, close it without Start, then explicitly Start. Pending pickups must remain visible.

API reference inspected during implementation: [Questie's source/API audit](https://github.com/Questie/Questie/blob/master/docs/forever-object-tooltip-api-audit.md). Runtime availability is checked; unsupported reads remain unknown.
