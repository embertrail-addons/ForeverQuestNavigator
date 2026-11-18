# 0.1.65 Beta

This update bundles the improvements developed in 0.1.60â€“0.1.64 and adds new travel and settings tools.

- Quest planning with nearby shared stops, ready turn-in rounds, shared item requirements and supported quest-chain previews.
- Temporary feedback and alternative known areas for the same objective, without changing persistent skips.
- Saved access routes with up to eight ordered points. Individual points now support personal notes.
- Temporary outdoor stops: navigate to entered coordinates, then resume quests on arrival or cancellation (`/fqn detour`).
- Quest-action item hints when the client supplies a reliable association and the item is owned.
- A modest nearby-turn-in preference when the log is nearly full and a known follow-up needs an acceptance slot.
- Appearance profiles, high contrast, adaptive narrow layouts, quiet navigation and simpler settings.
- Safe display export/import with preview, explicit Apply and Undo (`/fqn share`). Quest state, notes and positions are excluded.
- Shared Undo history for supported addon changes, level-up hints and additional quest reward information.
- Zone overview, travel-preparation hints and reduced distance/ranking work while stationary.
- Internal navigation/settings/event refactoring and expanded automated regression coverage.

Existing character skips, saved routes and notes are retained. Restart WoW after updating because this version adds module files.

Built for Forever 1.60.1. Questie and QuestieDB are optional, separate integrations. Distances are straight-line estimates; unknown data stays unknown. This is a beta: automated tests do not replace in-game validation.
