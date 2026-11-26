# Forever Quest Navigator 0.2.7

Performance release for cities and other places with many spawn points. Existing settings are kept.

## Smooth in cities

Measured in the real client with `/fqn perf` (Undercity, then in flight):

| | 0.2.6 in Undercity | 0.2.7 |
|---|---|---|
| Route planning (average) | 93 ms (up to 312 ms) | 10 ms |
| Camp choice (average) | 82 ms (up to 300 ms) | 6 ms |
| Spawn-area check (average) | 5 ms | 0.01 ms |
| Quest log update (average) | 331 ms | 30 ms |

- **Camp choice:** spawn points are grouped into camps once per quest objective (with a 100-yard grid) and reused across quest log updates; each update measures only the 8 nearest camps plus the current one.
- **World positions** are remembered per map position, so reloaded Questie markers do not convert thousands of positions again.
- **Spawn-area check** is skipped for quests whose nearest point is more than 300 yards away.
- **Questie results** stay valid for 10 minutes once Questie has finished loading (60 seconds in the first 5 minutes); changes to quests, objectives, maps or quest data still refresh them immediately.
- **Nearby quest givers** are searched every 5 seconds only while you move, otherwise every 30 seconds; quest log updates still search immediately.

## Diagnostics

- `/fqn perf` also shows the steps of the distance update (`dist:…`).

## Manual checks

Confirmed in the real client by the user: the measurements above (the last one in flight).

Not yet checked in the real client: a final measurement in Undercity with all changes.
