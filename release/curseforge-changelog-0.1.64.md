Local development build 0.1.64 — not published.

- Shared Undo history for profile applications, saved-access edits and removal of temporary feedback. Newer edits and expired feedback are protected (`/fqn undo`, `/fqn history`).
- Shared item requirements across active quests with matching item IDs. Bag inventory is subtracted once; missing inventory remains unknown.
- Quest-chain view in planning, including supported follow-up steps, target areas and known shared stops. Unknown continuations remain unknown.
- Clickable level-up hint and a list of quests whose known level fit improved (`/fqn levels`).
- Optional adaptive display for narrow trackers or large text, with compact metadata and shorter distance labels.
- Fewer repeated distance/ranking computations while stationary; quest events, explicit changes and temporary-state expiry still refresh promptly.

Shared item counts and route estimates remain planning aids. Undo applies to recorded addon changes, not gameplay or inventory. Client validation is still required. Existing saved character data and skips are preserved.
