# F15 — iOS UI tests, accessibility audit, Dynamic Type pass

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F08–F14 |
| Branch | `feat/F15-ios-ui-tests` |
| Design refs | all iPhone screens |
| Spec refs | `docs/testing-strategy.md` §2 (UI), §6 (tags/lanes), §8 (test plans); `docs/engineering-standards.md` §7 |

## Goal
Prove the M1 exit criterion end-to-end on the simulator: a new user onboards, runs a full workout including a superset round and a swap, finishes, and finds the result in History and the exercise chart — with every screen passing Xcode's accessibility audit and remaining usable at the largest Dynamic Type sizes.

## User stories
- As the orchestrator, one nightly run tells me whether the critical path still works on iOS.
- As a VoiceOver user, every control has a meaningful label and the flows are navigable.

## Scope
**In:** `LedgerUITests` suites `Smoke` (PR lane) and `Flows`, `Accessibility`, `DynamicType` (nightly), launch-argument test mode with seeded database, accessibility identifier convention, VoiceOver label review checklist.
**Out:** watch UI tests (F18/F20), performance metrics beyond launch (F26).

## Touches
- `Apps/LedgerUITests/{Smoke,Flows,Accessibility,DynamicType}/*.swift`, `Apps/LedgerUITests/Support/{App,Screens/*.swift}` (screen objects)
- `LedgerKit/Sources/LedgerAppKit/TestMode.swift` (launch arguments `-ledger-test-mode seeded|empty`, `-ledger-units kg`, `-ledger-clock 2026-08-19T10:00:00Z`)
- `LedgerKit/Sources/LedgerDesign/Accessibility/A11yID.swift` (identifier constants: `A11yID.today.startButton` → `"today.start"`)
- `TestPlans/PR.xctestplan`, `TestPlans/Nightly.xctestplan` (selected tests)
- `docs/testing-strategy.md` §2 UI (update the flow list if it changed)

## Domain changes
None.

## Acceptance criteria
1. Given `-ledger-test-mode seeded`, when the app launches, then the database is replaced by `LedgerTestSupport.Fixtures.seedProgram` + 4 weeks of history and the clock is frozen at the given date (all screens deterministic).
2. Given `Smoke.test_onboardToFirstSet` (PR lane), when run, then it onboards with defaults, starts today's workout, logs one set, and asserts the rest card appears — in < 90 s.
3. Given `Flows.test_fullWorkoutToHistory` (nightly), then: onboarding → Today shows "Upper A" → Start → log 3 sets of exercise 1 → rest appears and "Skip rest" works → superset day: log A1 then B1 and assert rest starts only after B1 → swap exercise 2 via the sheet → "+ Add set" → Finish → receipt shows volume and set rows → Done → History lists the workout → open exercise history → chart has a new point.
4. Given `Flows.test_programEditReflectsOnToday`, then editing tomorrow's day in the builder changes Today's UP NEXT preview after the frozen clock advances a day (relaunch with a new `-ledger-clock`).
5. Given `Flows.test_unitsSwitch`, then switching to kg in Settings changes a known set row from "185" to "84" (F02 rounding rule stated in the test).
6. Given every screen listed in `docs/product-spec.md` §2.2 (iPhone), when `performAccessibilityAudit()` runs with all audit types, then zero issues (exemptions require a comment and an issue link).
7. Given Dynamic Type `accessibility5`, when each screen is snapshotted (XCUIScreenshot attached), then no primary action is off-screen and no text is clipped (manual review of attachments + `isHittable` assertions for primary buttons).
8. Given VoiceOver simulated via accessibility inspection, then icon-only buttons (swap, gear, check, minimize) expose the labels listed in the checklist `docs/accessibility-labels.md` (created here).

## Test plan
- UI: as above; screen objects encapsulate identifiers so tests read as flows.
- Tags: `Smoke` selected in `PR`; everything in `Nightly`.
- Unit: `TestModeTests` (launch arguments parse; seeded mode never runs in Release builds — `#if DEBUG`).

## Non-functional
- Smoke ≤ 90 s; full flows ≤ 12 min; no `sleep`, only `waitForExistence(timeout:)`.
- Tests reset state per test via launch arguments, never via shared simulator state.

## Risks / unknowns
- Accessibility audit false positives on custom fonts (contrast) — record and tune tokens, not exemptions.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `tasks/todo.md` M1 exit checked with a link to a green nightly run.

---
_Filled in by agents during delivery:_
- `F15-ios-ui-tests/implementation-notes.md`
- `F15-ios-ui-tests/test-findings.md`
- `F15-ios-ui-tests/review.md`
