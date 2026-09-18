# F30 — TestFlight beta program

| | |
|---|---|
| Milestone | M4 |
| Status | proposed |
| Depends on | F01, F29 |
| Branch | `chore/F30-testflight-beta` (process + small fixes) |
| Design refs | none |
| Spec refs | `docs/ci-cd.md` §5, §7; R3 §6 |

## Goal
Real lifters run Ledger on their own iPhones and watches for at least two weeks, the sync scenarios from F20 pass in the wild, and crash/hang diagnostics flow back, before anything is submitted to the App Store.

## Scope
**In:** Xcode Cloud "Beta" workflow verified live (F01), internal group (Pete + 2–5 people), external group with Beta App Review submission, in-app "Send feedback" (TestFlight screenshot feedback + a mailto fallback), MetricKit diagnostics collection (`MXMetricManager` payloads written to local logs and surfaced in Diagnostics), triage process and labels, beta exit criteria and a go/no-go checklist.
**Out:** analytics SDKs (none), paid beta tools.

## Touches
- `LedgerKit/Sources/LedgerAppKit/{MetricKitCollector,FeedbackEntry}.swift`, `LedgerKit/Sources/FeatureSettings/FeedbackRow.swift`
- `docs/beta/{plan.md,triage.md,exit-criteria.md,results-YYYY-MM-DD.md}`
- `.github/ISSUE_TEMPLATE/beta-bug.yml`

## Domain changes
None.

## Acceptance criteria
1. Given a merge to `main`, then the internal group receives the build within 30 minutes and release notes are populated from the release-please changelog section (manual paste acceptable; automate if Xcode Cloud post-action supports it — verify).
2. Given the first external build, then Beta App Review passes on first submission (review notes from F29 attached).
3. Given ≥ 3 external testers with a watch, then each completes the F20 scenarios "start from wrist", "phone in bag 10 min", "finish on watch" and reports via the template; results recorded.
4. Given MetricKit payloads, then crash-free sessions ≥ 99.5 % and hang rate < 0.5 % over the last 7 beta days (from the Diagnostics export + Xcode Organizer).
5. Given the exit checklist, then every item is ticked with evidence links before F31 starts.

## Test plan
- Unit: `MetricKitCollectorTests` (payload parsing into the local log format).
- Process: `docs/beta/results-*.md` per week.

## Definition of Done
- [ ] Exit criteria met and signed off by Pete in `tasks/todo.md`.

---
_Filled in by agents during delivery:_ `F30-testflight-beta/{implementation-notes,review}.md`
