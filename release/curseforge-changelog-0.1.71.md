# 0.1.71

Local beta: clearer quest states and objective progress. No public tag or upload.

- Removed repeated `>` indicators from navigator titles and objectives. The current target uses a labelled accent and a restrained background; fixed targets are explicitly labelled.
- Added an automatic/manual priority status line with Resume automatic next to manual priority. Turn-in and group statuses use text, including in compact alternative rows.
- Separated reliably known objective counters from descriptions and added subtle progress bars. Invalid or missing counters retain the original text without inventing progress. Original objective text remains in tooltips.
- Hid inline skip actions. Accepted quests can still be skipped through their context menu or labelled detail action and restored through undo or the skipped list.
- Compact and collapsed views retain the current objective and distance, with an explicit button for additional open objectives. Completed objectives stay separately expandable.
- Renamed list sections to Other active quests and To accept. Strong nearby recommendations keep their explicit Recommended label.
- Retained quest-map actions, separate details, external direction display and local saved settings.

Reload the UI after updating from 0.1.70; restart WoW when upgrading from an older build. In-game visual confirmation is pending. No screen or window access was used.
