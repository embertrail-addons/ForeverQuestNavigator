# Forever Quest Navigator 0.2.0

Larger update: easier first steps, one tool window, new planning aids and optional group sync. Existing settings are kept.

## Easier to use

- **Setup on first start:** new installations get a three-step setup: navigator with arrow or arrow only, use Questie data or not, and Simple / Standard / Expert. Only choices you click are applied; Skip keeps the defaults. `/fqn setup` reopens it.
- **Simple and expert mode:** the existing "Simple navigator" setting is now **Simple mode**. It also hides advanced tool pages, settings and commands. New installations start in simple mode; existing players keep their current choice. A page you open explicitly stays reachable.
- **One tool window:** Outing and Tour assistant are now pages of the tool window, in the new **On the road** group. What's new and the full command list are Help pages. The window remembers its position.
- **Command menu:** `/fqn menu` lists every command with a search field. Right-clicking the minimap button opens a short menu of common commands. `/fqn` help is generated from the same list, so it now includes `demo`, `tools`, `assist`, `share` and others that were missing.
- **Symbols instead of words:** route stops, area overview and pickup plans show quest symbols for accept, objective and turn-in. The full word is in the tooltip. You can switch this off in the settings.
- Text and diagnostics windows now close with Escape.

## Planning

- **Route line on the world map:** consecutive numbered stops are connected; gold marks the next leg. A started outing shows up to six upcoming stops. Toggle it in the map legend or the settings.
- **Level forecast:** when no single turn-in levels you up, the details show how many of the nearest ready turn-ins reach the next level. Where Questie draws them, it also shows how many nearby quests unlock then.
- **Session recap:** turn-ins record their zone. The session overview shows XP per hour, the zone with the most turn-ins and a zone suggestion for next time. After 30 minutes away, the next login offers the recap or a new session.

## Group sync (optional, off by default)

- New setting **Share quest progress with my group**. When on, FQN sends your active quest IDs, objective counts (for example 3/5) and your current target quest to your own party or raid as addon messages. It sends at most every 3 seconds and never during combat.
- Members who also use FQN see shared quests with progress in the navigator and the Tour assistant. Quests several members still need rank slightly earlier.
- Messages are strictly checked and accepted only from current group members. Nothing is saved; data from a member is dropped when they leave. Without this setting, FQN sends no addon messages, as before.

## Behind the scenes

- Bag, durability, equipment and mount changes now only recompute items, travel preparation and distances, without re-reading the quest log. Full refreshes during combat are combined over one second.
- The quest item button only polls while the navigator is visible and combines frequent cooldown events.
- `Core/Bootstrap.lua` is split up: flight points, settings defaults and the command registry are separate modules. Grouped state keeps it well below Lua 5.1's 200-local limit, and a test guards that limit for every file.
- Update notes show only the latest three versions.
- luacheck (global variables only) runs in CI.

## Manual checks still open

These were checked with automated tests and mocks only, not yet in the real client:

- Setup on a fresh character; switching between simple and expert mode; command menu and minimap right-click menu.
- Outing and Tour assistant inside the tool window, including closing and Back.
- Route line rendering, thickness and zoom on the world map; legend toggle.
- Recap notice after a re-login more than 30 minutes later.
- Group sync with a second player using FQN 0.2.0 (party and raid), including a member leaving.
