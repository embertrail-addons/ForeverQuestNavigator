# Forever Quest Navigator 0.1.83

Regular Release, including the changes developed since 0.1.79. Real-client gameplay/rendering acceptance remains open; the automated checks below do not replace it.

## Also included since 0.1.79

- A quieter navigator with one Next action, reviewable area tours, grouped return advice and a dismissible recap using actual quest reward XP.
- Tour assistant with three groups: Plan, On the way, Remember & review. Explicit Map/Details actions, content-sized panels, actionable empty states and an optional Simple navigator.
- Before-departure checks, blocked-target alternatives, optional native group quest checks, level-up review, personal target corrections and explicit tour revisions.
- Optional 15/30/60-minute tour previews with visible heuristic assumptions. Unknown finishers/routes are omitted from timed subsets; these are planning estimates, not completion-time guarantees.
- Hand-ins on the way, contextual later reminders, distinct area-tour comparisons and expandable known quest chains.
- Clearer manual quest-item actions with count/range/cooldown, bag-space warnings for collecting quests and suggestions using only explicitly saved merchant visits. No automatic item use, quest acceptance, abandonment, hand-in or selling.

## Mixed rounds

- Pickups, objectives and hand-ins share one bounded plan. Two-stop lookahead considers coordinate travel, downstream known objectives/returns, level suitability and potential XP; near/shared objective areas provide a modest pickup preference. It does not prove shared enemies or walkable paths.
- Preserve per-quest precedence and simulate free quest-log slots, including reserve. A real hand-in may precede and make room for a later acceptance. Merely arriving or completing objectives does not free a slot in game.
- Add ready hand-ins with at most 400 extra coordinate yards toward the planned area. Omit pickups whose best known insertion detour among existing targets/returns exceeds 400 yards. Unknown transforms keep the order provisional. At most three pickups and twenty stops are considered; whole quests are bounded before truncation.
- Read starter pins Questie has already generated near the player, current destination and up to three pending pickup locations. Do not query every possible world quest or force Questie to redraw. Distant suggestions are labelled as near the destination; their distance remains measured from the player.
- Keep unknown finishers and XP explicit. Future quest chains stay forecasts unless actually available; no speculative future quest is accepted or represented as confirmed.
- After an actual recommended acceptance, pause and offer review. Refresh known active objective/return targets in an independent preview. Missing active coordinates prevent resume. Explicit Start adopts the reviewed plan; closing it leaves the old paused plan intact.

## Pickup choices

- **Skip step:** remove the unaccepted pickup and its own objective/hand-in plus represented transitive unaccepted dependencies. Keep already-active quests. Recompute potential XP and open-step counts; never abandon a quest.
- **Remind me later:** perform the same removal and create an after-round reminder.
- **Don't recommend again:** additionally persist the pickup exclusion per character across reload and restart.
- Main Next rows and outing previews expose Skip. Additional choices are in the pickup menu, with a three-button fallback if the native context-menu API is unavailable. Offer-list menus also support the choices, including future pickups in the current outing.
- **Undo:** show a temporary notice and a contextual Undo action. Restore an unchanged plan/choice only; real progress, another plan, changed reminder/exclusion data or manual acceptance prevents stale rollback. History remains inspectable through the existing undo tools.
- **Hidden pickups:** separate Tour assistant view under Remember & review, with single-entry restoration. Restoring makes suggestions eligible again; it does not inject steps into a running plan. Active-quest skips remain separate. A manually accepted hidden quest is still ranked as an active quest.
- Round-only omissions remain through the current outing's revisions and time-budget previews. A new independent outing, closing the completed recap, or reload resets applicable session-only exclusions; permanent exclusions remain. Choices made before starting an outing are session-only until a new outing is started or reloaded.

## UI and validation

- Pickup-only controls do not appear on objective/hand-in rows. Row/action heights account for text; assistant action buttons have more room for German labels.
- The simple navigator retains Skip, acceptance-review prompts and valid Undo. Full descriptions and all twelve assistant views remain available through Details/selector.
- No screen access or live-client gameplay verification was performed. Automated tests are not a claim of completed game acceptance.

## In-game follow-up

Automated checks passed: 255 Lua 5.1 tests, 19 Python tests, five regression fixtures and 934 matching translation keys. Publication was explicitly authorized on 2026-11-22 while the following checks remain open.

1. Restart WoW. Preview a mixed tour and verify that a nearby objective may precede a pickup and hand-ins follow prerequisites. Check the displayed distances against Questie.
2. At a full log, preview a known ready hand-in before a pickup. Actually hand it in, accept manually, review changed targets and explicitly resume.
3. Skip a current and a future pickup. Verify its work/hand-in disappear, unrelated active quests remain and XP/counts update. Try Undo immediately, then after real progress; stale progress must not be rolled back.
4. Try Later and Hide. Reload/restart, restore one hidden pickup, and manually accept a hidden quest. Active quests must remain usable and the active skip list must remain separate.
5. Change time budget after a skip; revise a running round. Declined pickups must not silently return to that round. Check a destination-area pickup outside the player radius.
6. Test unknown coordinates, unavailable Questie pins, repeatables, 80%/140% text and a narrow navigator. A review must not resume toward unverified actual objectives.
