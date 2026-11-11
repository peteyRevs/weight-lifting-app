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

## Plan amendments (planner, 2026-11-11, against main 2f452dd)

The planner's report. Where it and the brief above disagree, this section and the rulings after it win.

Paths are relative to the repository root. Line numbers are as of 2f452dd. F10 S9 (supersets, #92) is treated as merged: its `Apps/LedgerUITests/WorkoutSuperset.swift`, its edits to `WorkoutLogging.swift`, `WorkoutLoggingAdversarial.swift` and `WorkoutRest.swift`, and the seed's Upper A ending in a Lat Pulldown + Cable Lateral Raise superset (`LedgerFakes/Fixtures/Fixtures+Program.swift:55-79` on that branch).

**The short version.** F08–F14 delivered most of F15 piecemeal. On `main` there are 37 UI-test files (about 5,100 lines), five suites that run `performAccessibilityAudit`, a hosted accessibility-tree test and layout sweep for every feature module, and nine snapshot folders. What is still missing:
- one chained end-to-end flow that starts from onboarding and uses Today's real "Start workout";
- seeded history for UI tests;
- audits of the screens under the tab roots: the workout cover, the receipt, the Day editor, the exercise history, the workout detail and Settings;
- an accessibility-5 reachability pass on the screens that have no running-app check yet;
- the labels checklist;
- a green nightly run to link for the M1 exit.

None of that touches the PR lane except `Smoke`. The CI deadline problem is not F15's, but every F15 PR pays it, so a `chore(ci)` goes first.

## 1. Corrections to the brief

**What already exists, criterion by criterion**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C1 | Criterion 1: `-ledger-test-mode seeded\|empty`, `-ledger-units kg`, `-ledger-clock …`, a `TestMode.swift` | **Mostly done, under other names.** `-LEDGER_UITEST 1` opens a fresh database file in a new temporary directory, with US region settings. `-LEDGER_UITEST_PROGRAM seed` saves `Fixtures.seedProgram()` as the active program. `-LEDGER_UITEST_NOW <instant>` moves the clock. `-LEDGER_UITEST_FAIL_FINISH <n>` fails saves. All of them are Debug only and unit-tested. **Missing:** "4 weeks of history". Keep the `-LEDGER_UITEST_*` family; renaming would touch 37 files for nothing. No `-ledger-units`: the Settings UI test already switches units through the screen (C6) | `LedgerAppKit/AppComposition.swift:155-180, 262-287`; `UITestProgram.swift`, `UITestClock.swift`, `UITestRegion.swift`, `UITestSaveFailures.swift`; `LedgerAppKitTests/UITest{Clock,Program,SaveFailures}Tests.swift`; testing-strategy §2.7 |
| C2 | `LedgerDesign/Accessibility/A11yID.swift` identifier constants | **Not to be built.** UI-test targets link no package product, so identifiers are spelled as strings. The convention `<feature>.<screen>.<element>` is already in §2.7. FeatureWorkout has 23 identifiers, Onboarding 8, Settings 6, Library 5, History 5, **Today 1 (`today.title`) and Program 0**. Flows find Today and the builder by their labels ("Start workout", "MY PROGRAM"). F15 adds an identifier only where a label is ambiguous or changes with units (A4) | testing-strategy §2.7 "Identifiers"; `git grep accessibilityIdentifier(` by module; `TodayAuditExclusionsAdversarial.swift:8` ("F15 adds them") |
| C3 | Criterion 2: `Smoke.test_onboardToFirstSet` | Smoke has four tests: a fresh install skips setup to Today; the sample workout starts, minimizes, resumes and is discarded; the "workout in progress" conflict; and a set logged, saved, and shown as logged on Today. **What is missing:** a lifter's path through Today's real "Start workout" (Smoke uses the Debug menu's sample row), and the rest panel appearing. Smoke costs 96.5 s on a developer Mac (four launches) and is the PR lane's second-largest suite. Q3 | `Apps/LedgerUITests/Smoke.swift`; `tasks/chores/ci-test-time-2.md:28, 99` |
| C4 | Criterion 3: `Flows.test_fullWorkoutToHistory` | **Every step exists, but in separate tests that start from the Debug menu:** logging (`WorkoutLogging`), rest and "Skip rest" (`WorkoutRest`), superset rounds (`WorkoutSuperset`), swap (`WorkoutSwap`), finish and receipt (`Smoke`), the History list and detail (`WorkoutHistory`), the receipt row to the exercise history (`LibraryCreate.test_receiptRow_…`), and the history chart (`HistoryVoiceOverAdversarial`). **Missing:** the one chained run from onboarding through Today's Start to the chart, which is the M1 exit's own wording. The brief's order needs one correction: a swap is offered only before the exercise's first set is logged (F10 S8 ruling Q2), so exercise 2 is swapped before any of its sets | files named; F10 S8 Q2 |
| C5 | Criterion 4: edit tomorrow's day, then relaunch with a new `-ledger-clock` | **A relaunch cannot see the same data.** Every `-LEDGER_UITEST` launch makes a new `LedgerUITest-<UUID>` directory, and §2.7 says so: "what needs the same database twice is not a UI test until F15's test mode". Today already follows the program live through `observe`, and relaunch recovery is pinned hosted (`WorkoutRelaunchTests`). Q2 | `AppComposition.swift:266`; testing-strategy §2.7 last sentence; `LedgerAppKitTests/WorkoutRelaunchTests.swift` |
| C6 | Criterion 5: `Flows.test_unitsSwitch`, a set row reads "185" then "84" | **Half done:** `Settings.test_kilograms_chosenInSettings_reachToday` switches to KG and Today's volume tile reads kg. **The number is wrong:** F14 Q1 shows finished workouts converted exactly in the current unit (225 lb shows as 102.06 kg), so 185 lb is 83.91 kg, not 84. Program weights round to the equipment step (F14 S2). The missing half is a *finished* set row converting, which needs history (C1). Q9 | `Apps/LedgerUITests/Settings.swift`; F14 brief Q1 (line 403-407) |
| C7 | Criterion 6: every §2.2 screen passes `performAccessibilityAudit()` with zero issues, and each exemption has an issue link | **Audited today:** the three onboarding steps (light and dark); Today in four states, light and dark; the four tab roots (Today, the Program builder, Library, the History list); the Library root at three sizes; and the Delete-all sheet (three audit types only). **Not audited:** the active-workout cover (solo card, superset block, rest panel, swap sheet, finish sheet), the session receipt, the Day editor and its exercise-picker sheet, New/Edit exercise, the exercise history, the workout detail and its edit-sets sheet, the Settings root and its "Bar and plates" sheet. **Exemptions** are a measured exclusion named by the audit's words plus the element, with a comment and a finding ID, and a test that each exclusion "excuses nothing wider". That is in place of an issue link, because none of them is a system bug. Q5 | `TabsAdversarial.swift:144-190`; `TodayAuditAdversarial.swift`; `TodayAuditExclusionsAdversarial.swift`; `LibraryAuditAdversarial.swift`; `OnboardingAdversarial+Audit.swift`; `SettingsDeleteAllVoiceOver.swift:79` |
| C8 | Criterion 7: each screen at `accessibility5`, primary actions `isHittable`, nothing clipped | **The hosted layer covers this better than the brief's screenshots can.** Every feature module has layout or room tests that sweep every text size through `TestSweep`: Workout ×6, Program ×7, Library ×3, History ×2, Settings, Today, Onboarding. Snapshot references at `.accessibility3` exist for every screen. **In the running app at Accessibility XXXL** (`accessibility5` is `UICTContentSizeCategoryAccessibilityXXXL`) there are already checks of the tab titles, the onboarding steps, Today, the builder, the Day editor, the workout page and rest panel, the finish sheet at four sizes, the exercise history, and the Library. **Missing in the running app:** Settings and Bar and plates, the receipt, the swap sheet, the superset block, the workout detail and edit sheet, and New exercise | `LedgerKit/Tests/Feature*Tests/*Layout*`, `*Room*`; `WorkoutFinishAdversarial.swift:14-40`; `TabsAdversarial.swift:111`; `HistoryVoiceOverAdversarial.swift:34` |
| C9 | Criterion 8: icon-only buttons' labels, listed in `docs/accessibility-labels.md` | The labels are pinned already, in hosted accessibility trees for every module: 25 `*Accessibility*` test files, including `WorkoutAccessibilityTrees` and `TodayAccessibilityTrees`. **Missing:** the checklist document. F15 writes it as an index: each icon-only control, its label, and the test that pins it. It adds no new assertion layer | `ls LedgerKit/Tests/*/ \| grep Accessibility` |
| C10 | Folders `Smoke/`, `Flows/`, `Accessibility/`, `DynamicType/`, and `Support/Screens/*` screen objects | `Apps/LedgerUITests` is a flat synchronized folder with one file per feature flow, plus `Support/LaunchedApp.swift`. Keep it flat. The new files are `Flows.swift`, `Flows+Program.swift`, `AuditWorkout.swift` and so on (S1, S2). The helpers are duplicated: 16 copies of `attachScreenshot`, 15 `launch`, 8 `startSampleWorkout`, 5 `discard`. F15 adds one `Support/` set for its own tests. Migrating the old files is a separate chore (Q7) | `wc -l Apps/LedgerUITests/*.swift`; grep of helper names |
| C11 | Unit test `TestModeTests` | As C1: per-argument suites exist. S1 adds `UITestHistoryTests` in the same shape | as C1 |
| C12 | Non-functional: full flows ≤ 12 min | The nightly plan allows 600 s per test (`Nightly.xctestplan`, `maximumTestExecutionTimeAllowance`). The chained flow must fit that on the runner, so it targets ≤ 4 min on a Mac. "Full flows ≤ 12 min" is read as F15's new UI tests together, on a Mac | `TestPlans/Nightly.xctestplan` |
| C13 | DoD: link a green nightly run | **The nightly workflow has never run on GitHub** (`gh run list --workflow nightly.yml` is empty). It is manual only, and minutes are free while the repository is public. On `main`, the nightly lane has at least one red test (R1) and two load flakes (R2, R3). A green run needs the `chore(test)` below first | `.github/workflows/nightly.yml:3-8`; known failures listed in R1–R3 |
| C14 | `docs/testing-strategy.md` §2.7: update the flow list | The list names tests that never existed under those names (`Workout.startLogThreeSetsRestFinishReceipt`, `Workout.swapExercise`, `History.editThenDeleteWorkout`, `Accessibility.auditEveryTabRoot` …). S2 rewrites it to the real names, `Flows` included | testing-strategy §2.7 |

**Conventions**
- UI tests are XCTest, so they keep the `test_` prefix. Swift Testing's naming (§6) is for package tests.
- Each test sets `continueAfterFailure = false`, launches its own app, and waits only with `waitForExistence` or predicates. No `sleep`.
- **How lines are counted:** non-blank, non-comment Swift under `LedgerKit/Sources`, `LedgerKit/Tests` and `Apps`. **Test code counts** (F15 is mostly tests), and so do the UI-test target and LedgerFakes. Documents do not count.
- **Stop rule:** a slice stops and reports past about 950 lines.

## 2. Slices

There are two F15 slices, run one after the other. Two chore PRs come before them and one runs beside them (§2.4). F15 adds nothing to the PR lane except `Smoke`, so its own CI cost is small (R6).

### Order of all PRs

1. **`chore(ci)`: split PR Check's iOS tests across two parallel jobs** (§2.4 a). This comes first, because #88 already ran past the 4,500 s deadline and #91's first run took 72 min. Every later PR, F15's included, waits on it.
2. **`chore(test)`: a nightly that can be green** (§2.4 b). It can run in parallel with 1, since neither touches the other's files. It must merge before F15 S2's M1-exit run.
3. **F15 S1**: test-mode history, Smoke through the real Start, and the `Flows` suite. It needs F10 S9 merged.
4. **F15 S2**: audits and accessibility-5 reachability on every remaining screen, the labels checklist, §2.7, and the M1-exit nightly.
5. **`chore(snapshots)`: reference precision** (§2.4 c). It runs after S1 merges, in parallel with S2. It touches no F15 file. It is out of M1's critical path, but it should land before M2's first watch snapshots.

### S1: test mode history, Smoke through Today, and the critical flows (about 720 lines)

**Scope**
- `-LEDGER_UITEST_HISTORY <weeks>`, Debug only (Q1).
- Smoke's fresh-install test becomes `test_onboardToFirstSet` (Q3).
- `Flows`:
  - `test_fullWorkoutToHistory`;
  - `test_programEditReflectsOnToday`, as restated in Q2;
  - `test_unitsSwitch_convertsAFinishedSet`.
- F15's shared `Support/` steps.

**Criteria owned**
- **1 (restated, C1):** with `-LEDGER_UITEST 1 -LEDGER_UITEST_PROGRAM seed -LEDGER_UITEST_HISTORY 4 -LEDGER_UITEST_NOW 2026-09-16T12:00:00Z`, the app opens on Today. The four weeks of `Fixtures.history(weeks: 4)` are stored, and their records are derived by `WorkoutRepository` (A1). The History list shows them, and an exercise's history chart has their points. **Guards:**
  - Without `-LEDGER_UITEST` the argument is ignored.
  - A Release build ignores it (`#if DEBUG`, as `UITestProgram.liveSeeds`).
  - A value that is not an integer from 1 to 16 stops the launch with a message.
  - `-LEDGER_UITEST_HISTORY` without `-LEDGER_UITEST_PROGRAM seed` stops the launch with a message. The fixture's workouts belong to the seed program.
  - The history is stored only when the database holds no workout, so a second pass stores nothing.
- **2 (Q3 = A):** `Smoke.test_onboardToFirstSet`:
  - fresh install, onboarding full screen with no tab bar (kept from today's test);
  - "Skip setup", Today, then Today's **"Start workout"** (not the Debug menu);
  - "Log set 1", then the rest panel's `workout.rest.skip` exists;
  - "Finish", then "Discard", and the tabs come back.
  - Budget: under 90 s on the runner. One launch replaces one launch, so the PR lane's time is flat. Measure it and record it in the notes.
- **3 (C4):** `Flows.test_fullWorkoutToHistory`, one launch, on a fresh install with `-LEDGER_UITEST_NOW` on a session day of the program onboarding saves (pinned in the test, R8):
  - onboarding with its defaults, then Today's card names the day;
  - "Start workout", then three sets of exercise 1, each starting a rest. The third set's rest is ended with "Skip rest", and the panel goes;
  - exercise 2 swapped from its card's "Swap exercise" for the sheet's first row, before any of its sets are logged (C4). The card's name reads the replacement;
  - "+ Add set" on exercise 2, then one set logged;
  - a "REMAINING" jump to the superset block: A1 logged starts no rest, and B1 logged starts the group's rest (as `WorkoutSuperset` asserts);
  - "Finish", then "Save workout". The receipt's volume tile and its set rows are there, then "Done";
  - Today shows the session as logged;
  - the History tab lists the workout first, and its detail lists the swapped exercise;
  - Library, then the logged exercise, opens its history. The chart, which has one point per week, has a point for this week, and SESSION LOG lists today's session.
  - Target ≤ 4 min on a Mac (C12).
- **4 (Q2 = A):** `Flows.test_programEditReflectsOnToday`. On the seed program, at a session day:
  - Today's card shows the day's first exercise;
  - Program tab, then that day's Day editor, then an exercise added at the end (picker sheet, first search hit), then back;
  - Today's card, or its exercise count, reflects the change **without a relaunch**;
  - then the day's first exercise is deleted in the editor, and Today's card names the next one.
- **5 (restated, C6):** `Flows.test_unitsSwitch_convertsAFinishedSet`. With seeded history at week 5:
  - the History list, then the newest workout's detail, where a known set row reads in lb;
  - Settings, then KG, then back to the same detail, where the row reads the kg value;
  - Today's volume tile reads kg.
  - The expected text is computed in the test from the stored pounds × 0.45359237, in the Domain's two-decimal rule, and stated in a comment. It is never hard-coded from a screenshot.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerAppKit/UITestHistory.swift`: parse, guards, `liveWeeks(arguments:)` (Debug only) | 45 |
| `LedgerAppKit/AppComposition.swift`: `Environment.seedsUITestHistory`, and `saveUITestHistoryIfAsked()` after the program's save | 35 |
| `LedgerFakes/Fixtures/Fixtures+History.swift`: nothing, unless A1's clock finding needs `history(weeks:endingAt:)` | 0–20 |
| `LedgerAppKitTests/UITestHistoryTests.swift`: arguments, guards, the Release path through the same seam `UITestProgramTests` uses | 70 |
| `LedgerAppKitTests`: a launch test. The program and the history are saved once, before the gate reads them, and a second pass saves nothing | 45 |
| `Apps/LedgerUITests/Support/Steps.swift`: launch(arguments), `startFromToday`, `logSet`, `skipRest`, `finishAndSave`, `closeReceipt`, `discard`, `attachScreenshot`, `becomesHittable` | 130 |
| `Apps/LedgerUITests/Smoke.swift`: the fresh-install test becomes `test_onboardToFirstSet` | +40 |
| `Apps/LedgerUITests/Flows.swift`: `test_fullWorkoutToHistory` and its private steps | 210 |
| `Apps/LedgerUITests/Flows+Program.swift`: criterion 4 | 75 |
| `Apps/LedgerUITests/Flows+Units.swift`: criterion 5 | 65 |
| Identifiers that labels can't name (A4), if any: one or two lines each | 0–15 |
| **Total** | **about 720 (715–750)** |

**Tests**
- Unit: `UITestHistoryTests`:
  - absent, present, missing value, `0`, `17`, a non-number;
  - present without `-LEDGER_UITEST`;
  - present without the seed program;
  - the Release path stores nothing.
- Launch: the history is saved after the program and once. A failure is logged and the launch goes on, as the program's does.
- UI (nightly): `Flows` ×3.
- UI (PR): `Smoke.test_onboardToFirstSet`.
- Sanctioned edits, listed in the notes:
  - `Smoke.test_freshInstall_skipsSetupToToday` is replaced (Q3);
  - `Settings.swift` is unchanged. Its kg check stays, and `Flows+Units` adds the finished row.
- Before review, a local nightly run of `LedgerUITests` alone, with each test's seconds in the notes.

**Needs:** F10 S9 merged. Q1–Q4 and Q9 answered or defaulted. The `chore(ci)` merged first, or S1's PR may hit the deadline.

### S2: every remaining screen audited and reachable at Accessibility XXXL, the labels checklist, and the M1 exit (about 830 lines)

**Scope**
- One shared audit runner for F15's audits.
- The audits of every screen C7 lists as not audited.
- Accessibility-XXXL reachability of every screen C8 lists as missing.
- Fixes for the audit's real findings.
- `docs/accessibility-labels.md`.
- The rewrite of testing-strategy §2.7.
- The M1-exit nightly run.

**Criteria owned**
- **6 (restated, C7 and Q5, Q6):** for each screen below, `performAccessibilityAudit(for: .all)` is run in light at the default size, in dark at the default size, and in light at Accessibility XXXL. It reports no issue beyond that screen's measured exclusions. Every issue, excused or not, is attached to the result with the element's type, label and frame, and a picture of the element. Screens, and how each is reached:
  - **Workout:** the solo card; the superset block; the rest panel; the swap sheet; the finish sheet; the receipt. Reached through the Debug menu's sample, as the existing workout tests are.
  - **Program:** the Day editor; its exercise-picker sheet.
  - **Library:** New exercise; Edit exercise; an exercise's history, with seeded history so the chart has points.
  - **History:** the workout detail; its edit-sets sheet. With seeded history.
  - **Settings:** the root; "Bar and plates".
  - Out of scope: the share sheet (the system's) and the Debug menu (Debug only).
- **Exclusions:** each one is named by the audit's words and the element. It carries a comment with the measurement and a finding ID (`F15-S2-n`). Each screen's exclusions get a table-driven "excuses nothing wider" test, with no app launched, as `OnboardingAdversarial+Audit.test_auditExclusions_excuseNothingWider` does. Contrast findings on our own tokens are fixed in the tokens, never excluded (the brief's risk). Findings on the glass tab bar or under a pinned panel reuse the "scrolls clear" proof that `TodayAuditAdversarial.test_sessionDay_theLastLineScrollsClearOfTheTabBar` uses.
- **7 (restated, C8):** `DynamicType.swift`, launched at `UICTContentSizeCategoryAccessibilityXXXL`. On each screen C8 lists as missing, every primary action is scrolled to and is `isHittable`, and the screen's title is whole on screen. One screenshot is attached per screen. A screen whose only action sits under a pinned bar proves the action stands clear of the bar. Screens that already have a running-app check are not repeated.
- **8 (C9):** `docs/accessibility-labels.md` lists every icon-only control: the Today gear, the swap button, the set check and undo, minimize, the steppers' "−" and "+", the rest panel's "+30s" and "Skip rest", the builder's add and delete, and the Library's filter chips. For each it gives the identifier, the spoken label and value, and the hosted test that pins it (file:line). A source test checks that every identifier the document names exists in `LedgerKit/Sources`, so the document cannot drift silently.
- **DoD:** after S2 merges, one dispatched `Nightly` run on `main`: both matrix legs green, linked in `tasks/todo.md`'s M1 exit line.

**Files and estimates**

| File | Lines |
|---|--:|
| `Apps/LedgerUITests/Support/Audit.swift`: `AuditFinding`, `AuditExclusion`, the runner (all types, attach, filter), `auditThreeWays(_:)` | 140 |
| `Apps/LedgerUITests/AuditWorkout.swift`: six screens × three ways, plus exclusions | 190 |
| `Apps/LedgerUITests/AuditProgramLibrary.swift`: the Day editor, the picker, New/Edit exercise, the exercise history | 140 |
| `Apps/LedgerUITests/AuditHistorySettings.swift`: the detail, the edit sheet, the Settings root, Bar and plates | 110 |
| `Apps/LedgerUITests/AuditExclusionsTests.swift`: "excuses nothing wider" per screen (no launch) | 70 |
| `Apps/LedgerUITests/DynamicType.swift`: seven screens at Accessibility XXXL | 120 |
| `LedgerKit/Tests/LedgerAppKitTests/AccessibilityLabelsDocTests.swift`: the document's identifiers exist in sources (A8) | 40 |
| Reserve: product fixes for real findings (labels, traits, hit regions, tokens), each with its hosted test in the owning module | about 120 |
| **Total** | **about 830 (710 with no findings)** |

**Tests:** as above.
- Each audit file's tests sit in the nightly lane.
- A product fix lands with a hosted tree or layout test in its feature module, so the PR lane sees it.
- Snapshot references change only if a fix changes ink: fewer than 20 PNGs, or the fix goes to its own PR.

**Split point if S2 runs over:**
- S2a: the audit runner, the audits, the exclusions and the fixes (about 670).
- S2b: `DynamicType`, the labels document and its test, §2.7, and the M1-exit run (about 160).

**Needs:** S1 merged (seeded history, `Support/Steps.swift`), and the `chore(test)` merged (for the green nightly).

### 2.4 The chore PRs (not F15; for the orchestrator to brief separately)

**(a) `chore(ci)`: shard the PR iOS tests. First. About 150–250 lines of YAML, script and script tests; no product code.**
- **The facts:**
  - #91's re-run broke down as 137 s macOS script tests, 691 s iOS build and **2,251 s iOS tests**, 3,128 s in all (run 43059048691).
  - Cold first runs add about 700 s of build.
  - The tests are about 70% of the step. Smoke is 96.5 s on a Mac; the drawing suites are the rest (`ci-test-time-2.md` §1).
  - Another round of per-suite trimming buys 5–10%; the levers left are listed in `ci-test-time-2.md:102-104`.
- **The recommendation (Q10 = A):** `Check` becomes a matrix of two jobs on `xcode-27`:
  - **shard 1:** the Domain, Persistence, Sync, Health, ActivityKit, Dependencies, AppKit and `LedgerTests` targets, plus `LedgerUITests/Smoke`;
  - **shard 2:** `LedgerDesignTests` and every `Feature*Tests`;
  - the shards are balanced by the measured times in the result bundles.
  - Each shard restores the same compilation cache and builds warm (`main-cache.yml` already saves it). Both run `test-without-building` with `-only-testing` lists taken from one checked-in shard file.
  - A third small job, `Coverage`, downloads both bundles and runs `coverage-gate.sh` over both, which it already accepts.
  - `check.sh` gains `--shard <n>`. The local full gate stays unsharded.
  - A script test asserts that the two shards' union is exactly the `PR` plan's targets, so a new target can't fall out of CI.
  - Expected per shard: about 150 + 700 + 1,150 ≈ 2,000 s (33 min) warm.
  - The deadline comment in `pr.yml:126-139` is updated, and `docs/ci-cd.md` gains "Shards".
- **Alternatives:**
  - B: raise the deadline again. It is free while the repository is public, but feedback stays over an hour.
  - C: move the slowest hosted sweeps to nightly. That loses PR coverage of exactly the layouts F15 relies on.
- **Cost:** two macOS jobs per PR, free while the repository is public. If it goes private again, it bills about 1.3× today's minutes for half the wall time.

**(b) `chore(test)`: a nightly that can be green. In parallel with (a). About 150–300 lines, mostly tests.**
1. **`WorkoutLogging.test_sampleWorkout_stepsLogsUndoesAddsAndJumps` fails at :48** (`XCTAssertTrue(title.isHittable, "the next exercise's name is on screen")`, after the sixth bench set moves the card to Incline DB Press).
   - Likely cause: before F10 S9, the page did not scroll to its top when the card changed exercise. F10 S9's review fix SF2 (`91f183d`: `WorkoutPageModel.shownPlace` keys `WorkoutScreen`'s scroll to the top, pinned by `SupersetBlockTests.scroll_followsTheShownPlace`) is exactly that change.
   - **First step:** re-run the test on `main` after #92. If it is green, record it and close the item. If it is still red, find the cause in `WorkoutScreen`'s scroll (a product bug: a lifter would not see the next exercise's name) and fix it with a hosted test, not by editing the UI test's assertion.
2. **`WorkoutRestAdversarialTests.walk_panelAndHaptics`** was one `restOver` short under load (seeds 102964, 158397). The oracle counts a rest's end as owed a buzz when `cover.run` let time pass (`lateness = 0`, `WorkoutRestAdversarialTests.swift:70-72`). A loaded runner wakes the app's rest task late, past its one-second window, so the app rightly plays nothing.
   - **Fix the oracle, not a tolerance:** take lateness from when the cover's tasks actually resumed, as `RestCover`'s probe clock records it, so a buzz is owed only when the app's own wake was on time. Prove it under load, as `ci-test-time.md` §4 did (busy loops beside the suite), and with both seeds.
3. **Hosted `eventually` timeouts under parallel load** (`WorkoutUpdatesAdversarialTests`, `WorkoutSwapAdversarial*`, the walk suite). Their `eventually` (`WorkoutAdversarialWaiting.swift:20-49`) is bounded by 10 s of the wall clock. Under load, a hosted suite's main-actor work can wait more than 10 s for its turn: other suites' work in the same process, or a starved three-core runner. The chore first confirms which: does Swift Testing's in-process parallelism stay on under `-parallel-testing-enabled NO`, and on which lanes?
   - **The fix (Q12 = A):** where the condition reads observable state, wait by `Observations`, as the non-adversarial helper (`WorkoutScene.swift:197-202`) does. Keep the time bound only as a hang guard, set to the suite's `.timeLimit` minus a margin, never as the test's verdict.
   - Add `.serialized` only to a suite proven to contend with itself.
   - The flaky-test policy's "widened tolerances are not fixes" holds: no expectation changes.
4. From `tasks/todo.md:163-164`, "three tests that fail in the nightly lane on one thread": re-check them on `main`, and fix them or report them in the same PR.
5. **Nightly workflow duration.** It has never run on the runner. The full sweeps, 2,000 seeds and about 140 UI tests may pass `timeout-minutes: 120`. Dispatch it once on the chore's branch and record each step's time. If the iOS leg passes about 100 min, split it into two matrix legs (UI tests; package tests) in the same PR.

**(c) `chore(snapshots)`: reference precision. After S1, in parallel with S2.**
- Build the proposal already written in `tasks/chores/2026-10-12-m1-batch-b.md` §4:
  - (1) `assertPhoneSnapshot` measures at the scale the image is drawn at, so long pages are no longer cut 1–23 pt at each end. This re-records about 99+ references, more since #54 and #55;
  - (2) the tolerance becomes a pixel budget (`SnapshotConfig.pixelBudget`) instead of a fraction, so a long page is held as tightly as a short one. `cover_noHistory` passed with a new button drawn (F10 review SF3).
- The budget comes from one hosted run at precision 1.
- Over the 20-PNG rule, so it is its own PR. It touches testers' files (the five tests that pin 0.995) and §2.5's sentence: sanctioned edits.
- It is not in F15: F15 adds no references, and M1's exit doesn't depend on it.

## 3. Open questions

Each will be built to its recommended default until it is answered.

1. **How do UI tests get past workouts?**
   - A: a Debug-only `-LEDGER_UITEST_HISTORY <weeks>` stores `Fixtures.history(weeks:)` (the seed program's sessions, every set done) at launch.
   - B: each test logs and saves the workouts it needs through the UI (about 30 s each).
   - Recommended: A. The exercise chart, the History list and the unit conversion of a finished set all need more than one workout.
2. **Criterion 4 asks for a relaunch on a later date, but every UI-test launch is a fresh database.**
   - A: edit the program and check that Today follows it in the same launch. Today observes the program live, and relaunch recovery is already pinned hosted.
   - B: add `-LEDGER_UITEST_STORE <name>`, a named database directory that a relaunch reopens (about 30 lines, Debug only), and test exactly as the brief says.
   - Recommended: A. B adds a second database lifetime to the test mode for one test.
3. **Smoke in the PR lane.**
   - A: the fresh-install test becomes `test_onboardToFirstSet`, keeping its onboarding checks, and continues to Today's real Start, a logged set and the rest panel. One launch, so PR time is flat.
   - B: add it as a fifth Smoke test (about +25 s on a Mac, +60 s on the runner).
   - Recommended: A.
4. **Should flows start from Today's real "Start workout" or the Debug menu's sample?**
   - A: F15's `Flows` and Smoke use Today. The existing feature tests keep the Debug menu.
   - B: move every test to Today.
   - Recommended: A. It proves the lifter's path once, without churning 18 files.
5. **Audit exemptions: the brief asks for an issue link.**
   - A: a measured exclusion, named by issue and element, with a comment, a finding ID in the notes, and an "excuses nothing wider" test. An issue or Feedback link only when the system itself is wrong.
   - B: a GitHub issue per exclusion.
   - Recommended: A. It is what F08, F09 and F12 shipped, and none of their exclusions is a bug to track.
6. **How many ways is each screen audited?**
   - A: three: light at the default size, dark at the default size, light at Accessibility XXXL.
   - B: light at the default size only.
   - C: the full text-size range.
   - Recommended: A. Contrast differs by appearance, and clipping by size. The hosted sweeps already cover every size.
7. **The 37 UI-test files duplicate their helpers.**
   - A: F15's new `Support/Steps.swift` and `Support/Audit.swift` are used by F15's tests only. Migrating the old files is a later `chore(test)` (about −300 lines).
   - B: migrate them in F15.
   - Recommended: A. Minimal impact, and the old tests are nightly-only and green but one.
8. **Evidence for the M1 exit.**
   - A: one dispatched `Nightly` run on GitHub after S2 merges, linked in `tasks/todo.md`.
   - B: a local nightly run's summary.
   - Recommended: A. The minutes are free, and it proves the runner too.
9. **The units criterion's number.**
   - A: a finished 185 lb set reads 83.91 kg, as F14's ruling shows finished workouts, exact in the current unit. The test computes it and says why.
   - B: round it to "84" as the brief wrote, which would change F14's shipped display.
   - Recommended: A.
10. **How should the PR job be made shorter?**
    - A: two parallel test shards by target, plus a coverage job (§2.4 a).
    - B: raise the deadline again.
    - C: move hosted sweeps to nightly.
    - Recommended: A.
11. **When should the snapshot-precision chore land?**
    - A: after F15 S1, in parallel with S2.
    - B: before F15.
    - C: in M2.
    - Recommended: A. It is independent of F15, and it should be done before the watch's references multiply.
12. **How should the hosted `eventually` timeouts be fixed?**
    - A: wait on `Observations` where the state is observable. Keep the wall-clock bound only as a hang guard near the suite's time limit.
    - B: mark the three suites `.serialized`.
    - C: raise the 10 s bound.
    - Recommended: A, with B only for a suite proven to contend with itself. C is a widened tolerance (flaky-test policy).

## 4. Architecture flags

- **A1. Seeded history goes through `WorkoutRepository.save`, never raw inserts.**
  - Records are derived by the repository (`Repositories.swift:76-81`), so stats, PRs and the chart read as after real workouts.
  - `Fixtures.history(weeks:)` is anchored to the fixture's own week (`thisMonday = 2026-09-14`, week 5 current), not to the app's clock. So the flag needs `-LEDGER_UITEST_NOW` in that week, and S1's tests use 2026-09-16 as `Settings.swift` does.
  - If a test needs another week, add `history(weeks:endingAt:)`, about 15 lines in LedgerFakes; don't move the fixture.
- **A2. Debug only, as the other test arguments.** The parse is `#if DEBUG`, and Release reads nothing. `Fixtures` is already compiled into Debug builds through `SampleProgram`. No Release symbol is added.
- **A3. No project-file or test-plan edits.** `Apps/LedgerUITests` is a synchronized folder (F14 A7). The `Nightly` plan runs all of `LedgerUITests`, and the `PR` plan selects `Smoke` only. No pbxproj edits.
- **A4. Identifiers.** Product code gains an identifier only where a flow cannot name the element by a stable label, under §2.7's convention. Example: a set row's value changes with the unit, so `Flows+Units` may need `history.detail.setRow.<n>`. An identifier changes no ink and no hosted tree, so no reference or tree changes.
- **A5. Product fixes from the audit** land in their feature module, with a hosted test there, inside S2's reserve. A fix that changes a design token, or more than 20 references, stops and reports.
- **A6. Each UI test owns its state.** It launches fresh and never relies on order (the plans run in random order). A test that leaves a workout running ends it ("Finish", then "Discard").
- **A7. Sanctioned edits of others' tests**, each listed in the notes: `Smoke.test_freshInstall_skipsSetupToToday` (S1, Q3), and §2.7's flow list (S2). Nothing else.
- **A8. A drift guard for the labels document.** A LedgerAppKitTests source test reads `docs/accessibility-labels.md` and asserts that each identifier it names is spelled in `LedgerKit/Sources`. The existing source tests already read the repository from tests, as `PreviewScan` does.

## 5. Risks

- **R1. The red nightly test** (`WorkoutLogging` :48). It is probably fixed by #92's scroll-to-top (§2.4 b-1). If not, it is a product bug, not a test bug.
- **R2. The walk's wall-clock oracle** (§2.4 b-2). Until it is fixed, a loaded runner can fail the nightly, and rarely the PR lane: the walk is in `FeatureWorkoutTests`, which the PR plan runs with 40 seeds.
- **R3. Host `eventually` under load** (§2.4 b-3). Same exposure as R2. Sharding (§2.4 a) gives each shard more cores per suite and lowers it, but doesn't fix it.
- **R4. Audit false positives** on the glass tab bar, eyebrows and the accent button (as F09 and F12 found), and new ones on the workout cover's dark surfaces and the rest panel. Each is measured before it is excluded, and contrast on our tokens is fixed in the tokens. The size of S2's reserve is the uncertainty: if findings need more than about 120 lines, use the S2a/S2b split.
- **R5. A long XCUITest flow on a loaded runner.** The chained flow stays under the nightly's 600 s per-test allowance by targeting ≤ 4 min on a Mac. Every wait is `waitForExistence` with 5–10 s, and the flow attaches a screenshot at each stage, so a failure shows where it stopped.
- **R6. CI time for F15's own PRs.** S1 changes Smoke (flat by Q3) and adds two LedgerAppKit unit suites (under 1 s). S2 adds only nightly UI tests plus product fixes' hosted tests (a few seconds). F15 barely moves the PR lane. The risk is the existing step's length, which §2.4 a addresses.
- **R7. Nightly duration.** It has never run on the runner, and its 120-minute job may be too short. §2.4 b-5 measures it before the M1-exit run depends on it.
- **R8. Onboarding's program on a frozen date.** The chained flow needs the date's scheduled day to be the one it asserts. S1 pins the date by reading which day onboarding's default program schedules (the template's `specSeed`, F08), and states it in the test. If onboarding's generated week ever changes, the test fails at the first card, with a clear message.
- **R9. F10 S9 dependency.** S1's superset step and the edited `WorkoutLogging` assume #92 merged as reviewed. If #92 changes, S1 re-reads `WorkoutSuperset.swift` before writing its steps.
- **R10. Simulator UI-automation churn** (Xcode 27 preview image). An XCUITest API or audit behaviour can change with the image. The audit runner keeps all issue reporting in one place (`Support/Audit.swift`), so a change is fixed once.

### Critical files
- `LedgerKit/Sources/LedgerAppKit/AppComposition.swift`, `UITestProgram.swift` (the pattern for `UITestHistory`)
- `LedgerKit/Sources/LedgerFakes/Fixtures/Fixtures+History.swift`
- `Apps/LedgerUITests/Smoke.swift`, `Support/LaunchedApp.swift`, `WorkoutSuperset.swift` (on #92), `WorkoutSwap.swift`, `TodayAuditAdversarial.swift`, `OnboardingAdversarial+Audit.swift` (the exclusion pattern)
- `TestPlans/PR.xctestplan`, `TestPlans/Nightly.xctestplan`, `scripts/check.sh`, `.github/workflows/pr.yml`, `.github/workflows/nightly.yml` (the chores)
- `LedgerKit/Tests/FeatureWorkoutTests/Adversarial/WorkoutAdversarialWaiting.swift`, `WorkoutRestAdversarialTests.swift` (the `chore(test)`)
