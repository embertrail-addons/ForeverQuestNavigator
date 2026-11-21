# Forever Quest Navigator 0.1.78

Local development build. Not published; in-game acceptance is pending.

- Local follow-up fix: settings/tools dialogs open with an opaque background immediately, independent of navigator opacity and without needing a color-design switch.
- Navigator presentation is reduced to Focus and Overview. The collapse button and settings use the same state; both previous focused views migrate to Focus. Complete quest lists are available through Surroundings, without a separate layout option. Legacy display imports remain supported.

- New default Now / Next / Surroundings navigator: current goal first, up to three next actions, expandable complete lists. Ranking is unchanged by presentation choices.
- Graphite & Gold, Parchment & Bronze and Midnight & Turquoise designs, with theme preview, opening-state rollback and a design reset. High contrast and reduced semantic colors remain available.
- Neutral quest titles with level-only difficulty coloring in the guided view; green hand-in labels, blue XP information and text-based group warnings. Background opacity affects surfaces without fading text.
- Consistent map and ... actions, larger click targets, measured wrapping and detail sections for quest, travel, reasoning and rewards.
- Unified next-step advice combines useful pickups, approach objectives, hand-ins and suitable active quests without changing navigation priority.
- Planning adds hand-ins grouped by destination, nearby session-closing suggestions, decision comparisons and reviewable explanation exports.
- Explicitly remember an advisory round for the current session. Acceptance and chosen-objective progress update from quest-log evidence; removed quests and repeatable completion history are not claimed as newly completed.
- Round XP is a known subtotal plus unknown rewards, not a guaranteed amount. Available pickups disappear from the checklist once accepted.
- Additional temporary feedback for missing enemies, waiting for a group, inaccessible targets and objectives in a bounded 400-yard area. Ready hand-ins remain available; feedback expires after ten minutes or relevant quest changes and can be cleared or undone.
- Shared-item requirements, follow-up area previews and existing tour tools remain available through planning. Demo data stays isolated from live-character rewards and navigation.

No automatic quest acceptance, abandonment or priority change is introduced. Distances and area matches use coordinates and do not verify terrain or shared enemies.
