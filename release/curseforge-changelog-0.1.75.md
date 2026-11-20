# 0.1.75

Local beta: simpler navigator lists and stable notices. No public tag or upload.

- Combined the current-objective caption with destination quality, removing the duplicate destination-type line from the navigator. The external direction display retains its concise quality indication.
- Shortened the active XP line to a numeric reward and remaining XP to the next level, or a possible level-up. Detailed level/difficulty reasoning remains in Details.
- Added a separate Turn in badge to ready quest rows, with reserved spacing before XP text. Ordinary rows do not acquire another state label; recommended offers retain their explicit recommendation.
- Replaced wheel paging with visible Show more buttons. New batches append to the list; the mouse wheel scrolls exclusively, including at boundaries. Initial row settings still control the initial count and batch size.
- Reserved a fixed notice area for arrival instructions and temporary recommendation messages. Showing or expiring a notice does not move quest rows or resize the window.
- Extended anchor and parentage tests to retain multiple anchors and correctly model text/texture parents. Added checks for badge/XP spacing, unchanged list prefixes/map identity, fixed notices, merged target captions and XP forecasts.

Reload after updating from 0.1.74. Actual rendering still needs in-game confirmation; no screen or window access was used.
