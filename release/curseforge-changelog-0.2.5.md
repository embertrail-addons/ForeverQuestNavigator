# Forever Quest Navigator 0.2.5

Performance release. Existing settings are kept.

## Smoother play

Measured in the real client with `/fqn perf` (same character, normal questing):

| | before | after |
|---|---|---|
| Route planning (on movement) | 91 ms average, up to 407 ms | 0.3 ms average, up to 0.6 ms |
| Quest log update (on kills, quest changes) | about 20 ms, up to 80 ms | about 12 ms, up to 26 ms |

- **Turn-in positions are remembered:** every quest log update used to clear them, so the next planning pass queried the Questie database for every quest again. Found positions are now kept per quest; unknown ones are retried.
- **Questie results survive kills:** objective spawn points, the mobs belonging to each quest and quest chains only change when an objective finishes, a quest comes or goes, the map or level changes or new quest data arrives – not on every kill. They are reused until then (at most 60 seconds).
- Quest-giver offers nearby stay uncached on purpose, because Questie can redraw its quest-giver pins at any time.

## Diagnostics

- `/fqn perf` shows each step of the route planning (`plan:…`), of quest log updates (`refresh:…`) and of nearby offers (`offers:…`).

## Manual checks

Confirmed in the real client by the user: the measurements above.

Not yet checked in the real client: the installation that first reported stutters.
