# 0.1.66 release acceptance

This file records the user's marker acceptance and explicit stable-release authorization. Automated tests do not substitute for unreported client tests.

## Observed client result

The user confirmed on 2026-11-19 that RC2 made the markers visible and supplied a normal quest-map screenshot. After reviewing the compact RC3 appearance, the user wrote "sieht super aus!" and then "funktioniert alles" following the requested marker interaction checks. The user subsequently authorized the five final features and a Release.

## Required marker acceptance - user confirmed

- [x] Markers are visibly rendered in the game client; screenshot evidence supplied.
- [x] Compact appearance and requested marker interactions, including zoom/reopen and right-click removal, confirmed by the user.
- [x] Stable release explicitly authorized by the user after these results.

## Optional follow-up client checks

The following are not additional release approval requirements and have not been reported as manually completed for the new features:

- Hover grouped pins and tracker quests after changing map destinations.
- Try both temporary-priority policies and verify automatic selection resumes at the chosen boundary.
- Check travel time on foot and mounted, and toggle its setting.
- Review a suitable neighboring-zone cluster and known reward stats, then swap equipped gear.
- Exercise Questie-disabled operation, other map addons and unusual client states.
- Review demo state restoration, arrival hints, update notices and local performance timing during ordinary play.

## Automated release checks

- Lua 5.1 behavior/UI regression suite and the offline ranking fixtures.
- Python packaging, upload and release-check tests.
- `python scripts/check_release.py --tag v0.1.66`: version/changelog, EN/DE parity, required TOC/XML assets and runtime-only ZIP.
- Reproducible package content; installed files equal the candidate ZIP; previous installation backed up.

## First stable upload

Commit the final reviewed state and push matching tag `v0.1.66`. GitHub Actions validates, builds `ForeverQuestNavigator-0.1.66.zip` and uploads it to CurseForge project 1812992 as **Release** using the existing repository secret. Ordinary `main` pushes remain read-only for CurseForge. Do not reuse a published version tag. CurseForge moderation still applies. Project description and gallery changes are separate from the file upload.
