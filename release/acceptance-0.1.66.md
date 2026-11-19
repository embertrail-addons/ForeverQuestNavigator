# 0.1.66 release acceptance

Implementation and automated checks can be completed without logging into WoW. Public release is held until the following client checks have actually passed. Do not mark a client result passed based on mocked tests.

## Required client checks (pending)

- [ ] Restart the client, log in and wait for Questie. No Lua error appears.
- [ ] Normal mode: left-click an accepted quest with known objective coordinates. Its map opens and an FQN marker is visibly at the guided target.
- [ ] Repeat with a ready turn-in and a nearby offer; confirm the target matches that specific row.
- [ ] Close/reopen the map, switch to a neighboring zone and back, pan and zoom. The marker follows the same actual coordinates.
- [ ] Right-click an FQN marker. It disappears and stays removed during subsequent distance updates and map reopen.
- [ ] Repeat with Questie disabled where native quest coordinates are available, and with the user's usual map addon enabled.
- [ ] `/fqn demo`, `/fqn demo map`, `/fqn demo plan`: labels and pins appear. Co-located stops display grouped numbers without fabricated offset coordinates.
- [ ] Resize/change the demo scene while its map is open. Markers are refreshed rather than removed. Exit the demo; normal selection, skips, notes and settings are retained.
- [ ] During normal play, compare a quest recommendation and its reason. A manual selection remains authoritative. Automatic change notices are suppressed in quiet combat/taxi mode.
- [ ] Approach a known quest giver and an objective search area. The arrival text differentiates turning in from searching nearby; no gameplay action is automated.
- [ ] Update notes appear once for an existing installation, can be disabled and reopened with `/fqn whatsnew`.
- [ ] `/fqn perf on`, move/stand still, `/fqn perf`, `/fqn perf off`: timings populate locally, and normal navigation is unchanged.
- [ ] `/fqn markers` and `/fqn debug` report the current renderer and target/pin count.

## Automated release checks

- Lua 5.1 behavior/UI regression suite and the offline ranking fixtures.
- Python packaging, upload and release-check tests.
- `python scripts/check_release.py --tag v0.1.66`: version/changelog, EN/DE parity, required TOC/XML assets and runtime-only ZIP.
- Reproducible package content; installed files equal the candidate ZIP; previous installation backed up.

## First stable upload

Once the client checks above pass, commit the final reviewed state and push matching tag `v0.1.66`. GitHub Actions validates, builds `ForeverQuestNavigator-0.1.66.zip` and uploads it to CurseForge project 1812992 as **Release** using the existing repository secret. Ordinary `main` pushes remain read-only for CurseForge. Do not create the tag before acceptance or reuse a published version tag. CurseForge moderation still applies. Project description and gallery changes are separate from the file upload.
