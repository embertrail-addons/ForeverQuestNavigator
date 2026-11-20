# 0.1.73

Local beta: quest-item actions, clearer navigation and layout editing. No public tag or upload.

- Added a quest-item button for native client associations and owned items, with count, cooldown and range feedback. Use is an explicit left click outside combat. Protected click surfaces are independent of the movable tracker, hidden in combat and revalidated afterwards; their attributes and position are not changed during combat.
- Arrival messages can suggest using an item when the client positively reports it in range. Turn-in and access instructions retain precedence. Unknown range does not become a use-item recommendation.
- Added concise destination-quality labels to both navigator and direction display. Arrival instructions also remain in the navigator while the external display is enabled.
- Expanded hit areas for settings, collapse, close, detail and section actions. Header spacing prevents the enlarged areas from overlapping.
- Added Arrange interface in settings and `/fqn arrange`, with center/edge guides, position snapping and a center-direction-display action. Done locks both displays; Cancel or Escape restores prior positions and visibility.
- Added an automated UI stress matrix covering English/German, 80/140 percent text, 330/640 pixel widths, 360/600 pixel height caps, long titles and many objectives.

The quest-item action uses the game client's secure item-click mechanism; it does not call an item-use API from refresh/timer code. Implementation reference: [Classic SecureTemplates source](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua).

Automated UI tests do not replace the pending in-game check of actual rendering, item input, combat state transitions and dragging. See [the manual test checklist](ui-smoketest-0.1.73.md). No screen or window access was used.

Restart WoW after updating: this build adds Lua modules.
