# 0.1.69

Local beta bug fix. No GitHub push, public tag or CurseForge upload.

- Fixed settings opening only once. After closing the shared tool window, showing an embedded child panel did not fire OnShow while its parent remained hidden.
- Explicit panel opens now reveal the parent window first through a shared helper. The same correction covers the other embedded tool pages and preserves standalone demo/modal behavior.
- Regression tests model ancestor visibility rather than treating a child's shown flag as proof that it is visible. They cover repeated opening, closing, a shown child beneath a hidden parent, and reopening different tools.

Install the updated local package and reload the UI or restart WoW. In-game confirmation is pending; no screen or window access was used for this fix.
