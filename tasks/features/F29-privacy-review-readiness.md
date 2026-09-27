# F29 — Privacy manifest, HealthKit strings, App Review readiness

| | |
|---|---|
| Milestone | M4 |
| Status | proposed |
| Depends on | F14, F16 |
| Branch | `feat/F29-privacy-review-readiness` |
| Design refs | none |
| Spec refs | `docs/research/R3-tooling-ci.md` §6; R1 §3.3–§3.4; `docs/architecture.md` §16 |

## Goal
Everything App Review checks before it looks at the app: privacy manifests on every target, accurate HealthKit usage strings, visible HealthKit use in-app (Guideline 2.5.1), account-free data export/delete (already built), truthful App Privacy labels, and reviewer notes explaining how to test with a watch.

## Scope
**In:** `PrivacyInfo.xcprivacy` for iOS app, watch app, both widget extensions (collected data types: Health & Fitness — not linked to identity, not used for tracking; required-reason APIs: UserDefaults `CA92.1`, file timestamps `C617.1` if used); `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` reviewed for clarity on both apps; HealthKit onboarding explainer screen before the system prompt (why we read HR and write workouts); App Privacy questionnaire answers documented; review notes + demo video script; terms/privacy policy URLs (static pages in the repo `docs/legal/`, hosted by Pete).
**Out:** App Store metadata/screenshots (F31).

## Touches
- `Apps/Ledger/PrivacyInfo.xcprivacy`, `Apps/LedgerWatch/PrivacyInfo.xcprivacy`, `Apps/LedgerWidgets/PrivacyInfo.xcprivacy`, `Apps/LedgerWatchWidgets/PrivacyInfo.xcprivacy`
- `Apps/Ledger-Info.plist`, `Apps/LedgerWatch-Info.plist` (usage strings via `Config/*.xcconfig` `INFOPLIST_KEY_*`)
- `LedgerKit/Sources/FeatureWorkout/HealthExplainerView.swift` (shown once before authorization)
- `docs/app-review/{privacy-answers.md,review-notes.md,demo-script.md}`, `docs/legal/{privacy-policy.md,terms.md}`

## Domain changes
None.

## Acceptance criteria
1. Given the archived build, when `xcrun` privacy report is generated (Xcode ▸ Product ▸ Generate Privacy Report), then every target's manifest is present and the report lists Health & Fitness with "not linked, not tracking" and the required-reason APIs actually used (a script diffs declared vs. `nm`/`strings` findings — best effort, recorded).
2. Given a fresh install, when the user first taps Start workout, then the explainer appears ("%@ reads your heart rate during workouts and saves them to Apple Health…", `%@` = `CFBundleDisplayName`), then the system HealthKit prompt; declining leaves the app fully usable without HR.
3. Given the usage strings, then each states the specific data and purpose in one sentence and matches the explainer copy.
4. Given `docs/app-review/privacy-answers.md`, then every App Privacy question has an answer with the code path that justifies it.
5. Given `review-notes.md`, then it explains: watch required for HR, how to test without a watch, that no account exists, where export/delete live, and that no health data is stored in iCloud.
6. Given third-party code (GRDB, swift-dependencies, chosen sync lib), then their privacy manifests (if any) are included and no tracking domains exist (`NSPrivacyTrackingDomains` empty).

## Test plan
- Unit: `HealthExplainerFlowTests` (shown once; sequence before prompt), `UsageStringsTests` (keys present on both targets — build-time plist assertion).
- Scripts: `scripts/privacy-report.sh` producing the report into the PR.
- Manual: reviewer checklist walk-through recorded in implementation notes.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Pete has read and approved the legal pages and review notes.

---
_Filled in by agents during delivery:_ `F29-privacy-review-readiness/{implementation-notes,test-findings,review}.md`
