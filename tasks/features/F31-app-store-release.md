# F31 — App Store release

| | |
|---|---|
| Milestone | M5 |
| Status | proposed |
| Depends on | F30 |
| Branch | `chore/F31-app-store-release` |
| Design refs | v2 visual system for screenshots |
| Spec refs | `docs/ci-cd.md` §5–§7; R3 §5–§6 |

## Goal
Ship 1.0: metadata, screenshots for every required iPhone and Apple Watch size, age rating, pricing (free), phased release, and a release checklist that ties the `v1.0.0` tag to the Xcode Cloud "Release" workflow and post-launch monitoring.

## Scope
**In:** App Store Connect listing (name "Ledger — Lifting Log" or as decided, subtitle, description, keywords, support/privacy URLs), screenshots (6.9", 6.3" iPhone; 46 mm watch — generated from the seeded test mode via XCUITest screenshot suite, or fastlane `snapshot` if adopted), app preview video optional, categories (Health & Fitness), age rating questionnaire, export compliance (no custom crypto), release checklist, phased release on, post-launch monitoring for 14 days (crashes, reviews, sync issues).
**Out:** marketing site, paid tiers.

## Touches
- `Apps/LedgerUITests/Screenshots/*.swift` (screenshot suite using `-ledger-test-mode seeded`)
- `docs/release/{checklist.md,metadata.md,screenshots/}`, `CHANGELOG.md` (release-please)

## Domain changes
None.

## Acceptance criteria
1. Given the screenshot suite, then it produces all required sizes in light and dark from deterministic seeded data, with device frames optional.
2. Given the release checklist, then it includes: F30 exit signed, F29 privacy report attached, version `1.0.0` release PR merged, tag created, Xcode Cloud Release green, build attached to the 1.0 version in App Store Connect, phased release enabled, review notes pasted, "Manual release" selected.
3. Given App Review feedback, then the process in `checklist.md` covers reply, fix-forward via hotfix flow (ci-cd §7), and re-submission.
4. Given launch day, then monitoring notes are recorded daily for 14 days in `docs/release/launch-log.md`.

## Test plan
- UI: screenshot suite (nightly, `.screenshots` tag; not part of PR).
- Manual: checklist.

## Definition of Done
- [ ] 1.0 approved and released; launch log started.

---
_Filled in by agents during delivery:_ `F31-app-store-release/{implementation-notes,review}.md`
