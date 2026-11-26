# Forever Quest Navigator 0.2.3

Smarter recommendations and more reliable target marks. Existing settings are kept.

## Smarter recommendations

- **XP per minute instead of distance alone:** travel, remaining kills, items and other objectives and the way to the turn-in become an estimated time; quests with a clearly better rate rank earlier. The effect is bounded, so distance and level still matter.
- **Nearly finished quests first:** with one to three kills or items left, a quest gets a strong bonus, and the unavoidable way back to its turn-in no longer counts against it. Unknown turn-ins are estimated as long as the way there, so they no longer look cheaper.
- **Look-ahead:** a quest whose end lies next to another quest ranks earlier; dead ends rank later.
- **Follow-ups, finishing the zone and shared mobs:** quests that unlock follow-ups, the last few quests on the current map and quests whose mobs also count for another open quest rank a little earlier.
- **Learns from you (per character):** real travel speed, minutes per kill or item and your preferred kind of quest (kill, collect, other) from your manual picks – bounded and reversible. `/fqn learn` shows the values, `/fqn learn reset` clears them.
- **Explained:** the quest tooltip shows why (for example "~650 XP/min · next step close · 2 follow-up quests") and why it beats the runner-up.

## Target marks

- **Marks with /tm:** clicks in the Mark targets window target by exact name and mark with `/tm` inside the same secure click – this works where addons may not set raid marks by themselves. Marking from addon code is used only where the client allows it and switches itself off after a blocked call.
- **Clicks cycle:** each click on a mob row moves on to the next living mob of that name (from nameplates) and marks it, also in combat; dead mobs are skipped.
- **No error when the NPC is not nearby:** nothing is marked, and an old target is never marked by mistake.
- **Key bindings:** "Target and mark the next quest mob" (cycles through all mobs of the active quest) and "Target and mark the turn-in NPC" – no friendly nameplates needed.
- **Shared mobs:** "Also counts for: …" in the navigator and a +1 in the window when a mob counts for several quests (for example kill murlocs and collect murloc eyes).

## Manual checks

Confirmed in the real client by the user: marking via the window works, clicks cycle to the next mob, no error when the NPC is not nearby.

Not yet checked in the real client: the new recommendation weighting over a longer session, `/fqn learn`, the two new key bindings, the shared-mob note.
