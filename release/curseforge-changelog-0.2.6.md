# Forever Quest Navigator 0.2.6

Fix release. Existing settings are kept.

## Fixes

- **Blocked-action message at login** ("Frame:RegisterEvent()" reserved for the Blizzard UI): since 0.2.2 FQN registered the combat log for the loot reminder and the respawn estimate. Newer clients forbid that for addons. FQN no longer uses the combat log; kills are noticed when a quest mob is seen dying on its nameplate or as your target and was not tagged by someone else. A guard test keeps the combat log and addon-set raid marks out of the code.

## Easier to use

- **Skip from the quest menu:** "Skip this quest in FQN" is now a direct entry in the quest menu ("..." next to the quest, or right-click on the quest title), not only at the bottom of the "Why this quest?" panel.

## Diagnostics

- When WoW blocks an action and names FQN, the protected function is recorded in the FQN error log (shown in `/fqn problem`) and named once in chat.

## Manual checks

Confirmed in the real client by the user: `/fqn problem` named "forbidden Frame:RegisterEvent()" before the fix.

Not yet checked in the real client: absence of the message after the fix; loot reminder and respawn estimate with the new kill detection; the skip entry in the quest menu.
