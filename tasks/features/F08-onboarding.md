# F08 — Onboarding → template program generation

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F02, F03, F05, F06, F07 |
| Branch | `feat/F08-onboarding` |
| Design refs | `design/prototype/Ledger v2.dc.html` → screen labels: `Onboarding`, `Today` (landing); `design/prototype/Ledger.dc.html` → `Program builder` (seed day contents only) |
| Spec refs | `docs/product-spec.md` §2.4, §2.5, §3.10 (Onboarding), §6.4, §6.7, §7.1, §7.2; `docs/product-decisions.md` #1, #2, #9, #17, #18, #19 |

## Goal
On first launch a lifter answers three questions (goal, days per week, program preview) — or skips — and lands on Today with a real 8-week `Program` saved to disk, anchored to a `startDate`, and a session ready to start. Before this ships the app has no way to get from zero to a program.

## User stories
- As a lifter, I can pick a goal and a days-per-week so that the app writes a sensible first block for me instead of an empty builder.
- As a lifter, I can skip setup so that I still get a usable 4-day program without answering anything.
- As a lifter, I can see exactly which training days I am getting before I commit, so that nothing on Today surprises me.

## Scope
**In:** `OnboardingRoot` (3 steps, v2 visual), `ProgramTemplates` (pure Domain generator: 3 / 4 / 5 / 6-day templates × 4 goals), "Skip setup", `startDate` anchoring (decision #18), persisting the program as active, routing to Today. Shown only when no active program exists (first launch, or after Settings → Delete all data in F14).
**Out (explicitly):** editing the generated program (F11), "Start next block" / block end (F24), watch program push (F19), accounts/auth (none — decisions #2, #19), custom exercises (F12).

## Touches
- `LedgerKit/Sources/LedgerDomain/Programs/TrainingGoal.swift` (new: `TrainingGoal`, `DaysPerWeek`)
- `LedgerKit/Sources/LedgerDomain/Programs/ProgramTemplates.swift` (new, pure)
- `LedgerKit/Sources/FeatureOnboarding/OnboardingRoot.swift`, `OnboardingStore.swift`, `OnboardingRoute.swift`
- `LedgerKit/Sources/FeatureOnboarding/Views/OnboardingStepView.swift`, `OnboardingOptionRow.swift`, `ProgramPreviewList.swift`, `StepProgressBars.swift`
- `LedgerKit/Sources/FeatureOnboarding/Resources/Localizable.xcstrings`
- `LedgerKit/Sources/LedgerTestSupport/Fixtures/ProgramFixtures.swift` (add `Program.fourDayDefault(startDate:)` built from the template)
- `LedgerKit/Tests/LedgerDomainTests/ProgramTemplatesTests.swift`
- `LedgerKit/Tests/FeatureOnboardingTests/OnboardingStoreTests.swift`, `OnboardingSnapshotTests.swift`
- `Apps/Ledger/Sources/RootView.swift` (F07-owned; one branch: no active program → `OnboardingRoot`, else tabs)

## Domain changes
```swift
public enum TrainingGoal: String, Codable, Sendable, CaseIterable { case stronger, muscle, both, consistent }
public enum DaysPerWeek: Int, Codable, Sendable, CaseIterable { case three = 3, four, five, six }

public enum ProgramTemplates {
    /// Deterministic: same inputs + same `ids` sequence → identical Program. `catalog` is the F03 seed.
    public static func program(goal: TrainingGoal, days: DaysPerWeek, units: Units, startDate: Date,
                               catalog: [Exercise], id: ProgramID, ids: () -> UUID) -> Program
    public static func preview(goal: TrainingGoal, days: DaysPerWeek) -> [DayPreview]   // name, tag, previewLine
    public static let weeks = 8
}
```
`Program.goal: TrainingGoal` and `Program.daysPerWeek: DaysPerWeek` are the F02 fields (architecture §5); if F02 typed them differently, adapt F02 and note it. `Program.startDate` = `WeekCalendar.startOfWeek(containing: today, weekStart: settings.weekStart)` (decision #18). Week 8 (`index 7`) is `isDeload = true`; weeks 1–7 are not.

**Role table** — every slot has a role; the goal sets the prescription (all values within spec §7.1 ranges):

| goal | primary `P` | secondary `S` | accessory `A` |
|---|---|---|---|
| `stronger` | 5×5 (hi 7), RPE 8, 180 s, linear | 4×6 (hi 8), RPE 8, 150 s, linear | 3×8 (hi 10), RPE 8, 90 s, linear |
| `muscle` | 4×8 (hi 10), RPE 8, 120 s, double | 3×10 (hi 12), RPE 8, 90 s, double | 3×12 (hi 15), RPE 9, 60 s, double |
| `both` | 5×5 (hi 7), RPE 8, 150 s, linear | 3×8 (hi 10), RPE 8, 120 s, linear | 3×12 (hi 14), RPE 9, 75 s, double |
| `consistent` | 3×5 (hi 7), RPE 7, 120 s, linear | 3×8 (hi 10), RPE 7, 90 s, fixed | 2×12 (hi 14), RPE 7, 60 s, fixed |

**Exception (canonical seed):** `both` × `four` is spec §6.4 verbatim (sets/reps/repsHi/RPE/rest/progression per slot, superset on Upper A 4–5 and Lower A 3–4, drop set on Upper B 4, fixed calf raise) with the §6.4 schedule (weeks 1–7 Mon UA · Wed LA · Fri UB · Sat LB; week 8 Mon UA · Wed LA · Fri UB, deload). Other goals on the 4-day keep the same exercises, supersets and drop set, and take prescriptions from the role table.
Start load = `exercise.defaultStartLoad` rounded to the unit's step (`Equipment.defaultStep(in:)`: lb barbell and kettlebell 5, others 2.5; kg barbell 2.5, kettlebell 2, others 1.25 — decision #22); `Slot.step = nil` (resolve per unit at read time, F14). Deload maths is `ProgressionRules` (F02), not the template.

**Templates** (day name · tag: slots with role → preview line). Every name must resolve in the F03 catalog (test-enforced).
- 4-day "Upper / Lower" — UA/LA/UB/LB exactly §6.4; roles UA: Bench P, Incline DB S, CS Row S, Pulldown A, Lateral A · LA: Squat P, RDL S, Leg Press A, Calf A · UB: Pull-Up P, OHP S, Row S, Curl A · LB: Deadlift P, Front Squat S, Leg Curl A. Schedule as above.
- 3-day "Full Body", Mon/Wed/Fri:
  - `Full Body A — Squat focus` · FA: Back Squat P, Barbell Bench Press S, Lat Pulldown A, Cable Lateral Raise A, Barbell Curl A → "Squat, bench, pulldown, laterals, curl"
  - `Full Body B — Bench focus` · FB: Barbell Bench Press P, Romanian Deadlift S, Chest-Supported Row S, Leg Press A, Cable Triceps Pushdown A → "Bench, RDL, row, leg press, pushdown"
  - `Full Body C — Deadlift focus` · FC: Deadlift P, Overhead Press S, Weighted Pull-Up S, Seated Leg Curl A, Rear Delt Fly A → "Deadlift, OHP, pull-up, leg curl, rear delt"
- 5-day "Push / Pull / Legs", Mon Tue Wed · Fri Sat:
  - `Push — Chest focus` · PU: Barbell Bench Press P, Overhead Press S, Incline DB Press A, Cable Lateral Raise A, Cable Triceps Pushdown A → "Bench, OHP, incline, laterals, pushdown"
  - `Pull — Back focus` · PL: Weighted Pull-Up P, Barbell Row S, Lat Pulldown A, Rear Delt Fly A, Incline DB Curl A → "Pull-up, row, pulldown, rear delt, curl"
  - `Legs — Squat focus` · LG: Back Squat P, Romanian Deadlift S, Leg Press A, Seated Leg Curl A, Standing Calf Raise A → "Squat, RDL, leg press, leg curl, calves"
  - `Upper — Accessories` · UP: Weighted Dip S, Chest-Supported Row S, Low-to-High Cable Fly A, Overhead Cable Extension A, Barbell Curl A → "Dip, row, fly, extension, curl"
  - `Lower — Hinge focus` · LW: Deadlift P, Front Squat S, Seated Leg Curl A, Standing Calf Raise A → "Deadlift, front squat, leg curl, calves"
- 6-day "Body-Part Split", Mon–Sat:
  - `Chest` · CH: Barbell Bench Press P, Incline DB Press S, Weighted Dip A, Low-to-High Cable Fly A → "Bench, incline, dip, fly"
  - `Back` · BK: Barbell Row P, Weighted Pull-Up S, Lat Pulldown A, Chest-Supported Row A → "Row, pull-up, pulldown, chest-supported row"
  - `Legs — Quad focus` · LQ: Back Squat P, Front Squat S, Leg Press A, Standing Calf Raise A → "Squat, front squat, leg press, calves"
  - `Shoulders` · SH: Overhead Press P, Cable Lateral Raise A, Rear Delt Fly A, Overhead Cable Extension A → "OHP, laterals, rear delt, extension"
  - `Arms` · AR: Barbell Curl S, Cable Triceps Pushdown S, Incline DB Curl A, Overhead Cable Extension A → "Curl, pushdown, DB curl, extension"
  - `Legs — Hinge focus` · LH: Deadlift P, Romanian Deadlift S, Seated Leg Curl A, Standing Calf Raise A → "Deadlift, RDL, leg curl, calves"

**Copy (String Catalog, exact):** step titles/bodies/options/CTAs from spec §6.7: "What are you training for?" / "This sets how your loads progress week to week." (was "…how Ledger progresses your loads…"; shipped copy never names the app — see `docs/product-decisions.md` › Naming) / options "Get stronger — Low reps, linear load increases", "Build muscle — Moderate reps, volume tracking", "Both, honestly — Barbell strength + accessory volume", "Stay consistent — Habit first, numbers second"; "How many days a week?" / "Pick the number you will actually hit, not the one you want to hit." / "3 days — Full body each session", "4 days — Upper / lower split", "5 days — Push, pull, legs + accessories", "6 days — Body-part split"; "Your program" / body `"%@, %lld weeks, %@. Editable any time."` (program name, 8, "pounds" | "kilograms" per `Settings.units`; default renders "Upper / Lower, 8 weeks, pounds. Editable any time."); CTAs "Continue", "Continue", "Start training"; secondary "Skip setup". 4-day preview lines are §6.7 verbatim except Lower B → "Deadlift, front squat, leg curl" (the seed has no abs slot; see Risks). Error: "Couldn't save your program. Try again." + "Retry".

## Acceptance criteria
1. Given a fresh install (no active program), when the app launches, then `OnboardingRoot` is shown full-screen with step 1 selected, progress bars 1/3 orange, default pick "Both, honestly"; the tab bar is absent.
2. Given step 1, when I tap an option, then only that option shows the orange check and "Continue" advances to step 2 with default "4 days"; the picks survive going back and forth (steps do not reset).
3. Given step 3, when it renders, then the preview rows are read-only (no check icons), list every day of the chosen template in order as "{name with ' — ' replaced by ' · '}" + preview line (e.g. "Upper A · Push focus" / "Bench, incline, row, pulldown, laterals"), and the body reads "{name}, 8 weeks, {pounds|kilograms}. Editable any time.".
4. Given step 3, when I tap "Start training", then exactly one `Program` is saved via `programRepository` with `isActive == true`, `goal`/`daysPerWeek` from my picks, 8 weeks, last week deload, `startDate` = start of the current week per `settings.weekStart`, and the root switches to the tabs with Today selected.
5. Given any step, when I tap "Skip setup", then the `both` × `four` program is generated and saved exactly as in 4, and I land on Today.
6. Given `both` × `four`, when generated, then every slot equals spec §6.4 (assert full table) and the schedule equals the §6.4 seed including week 8's three days.
7. Given any (goal, days) pair, when generated, then every slot value is inside spec §7.1 ranges (sets 1–12, reps 1–30, repsHi 2–40 and > reps, RPE 5–10 step 0.5, rest 30–300 step 15), every exercise name resolves in the F03 catalog, and the schedule has exactly `days` training days per week for weeks 1–7.
8. Given units = kg (set before onboarding via F14 fixture), when generated, then every start load is a multiple of the kg step (2.5 kg barbell / 2 kg kettlebell / 1.25 kg other) and the step-3 body says "kilograms".
9. Given the same inputs and the same `uuid` sequence, when generated twice, then the two programs are `==` (determinism).
10. Given a repository save failure, when I tap "Start training", then the screen shows "Couldn't save your program. Try again." with "Retry", nothing navigates, and Retry re-attempts with the same picks.
11. Given onboarding completed on a Wednesday (2026-09-16, week start Monday), when Today loads, then `WeekCalendar.currentWeekIndex` is 0 and Today shows week 1 of 8 (`Program.startDate == 2026-09-14`).
12. Given VoiceOver, when I focus an option, then it reads "{label}, {sub}, {selected|not selected}, button" and the progress bars are a single element "Step 1 of 3".

## Test plan
- Unit (LedgerDomainTests): `test_templates_bothFourDay_matchesSpecSeedTable`, `test_templates_bothFourDay_scheduleMatchesSeedIncludingWeek8`, `test_templates_allGoalsAllDays_withinSpec71Ranges`, `test_templates_allNamesResolveInCatalog`, `test_templates_lastWeekDeloadOnly`, `test_templates_daysPerWeek_matchesScheduleCount`, `test_templates_kgStartLoads_multiplesOfKgStep`, `test_templates_deterministic_sameIDsSameProgram`, `test_templates_roleTable_appliedForStrongerFourDay`, `test_preview_fourDay_copyMatchesSpec67`.
- Unit (FeatureOnboardingTests): `test_store_defaults_bothFourDayUpperA`, `test_store_pickPersistsAcrossSteps`, `test_store_startTraining_savesActiveProgramAndRoutesToday`, `test_store_skipSetup_savesFourDayDefault`, `test_store_startDate_isStartOfCurrentWeekPerSettings`, `test_store_bodyCopy_kgSaysKilograms`, `test_store_saveFailure_showsRetryAndDoesNotRoute`, `test_store_retry_afterFailureSucceeds`.
- Integration (LedgerPersistenceTests): `test_programRepository_saveTemplate_roundTripsAllSlotsAndSchedule` (uses `ProgramTemplates` output).
- Snapshot (FeatureOnboardingTests): `OnboardingStepView` step1 / step2 / step3(4-day) / step3(6-day) / error × {light, dark} × {default, XL type}.
- UI (LedgerUITests): F15 flow `onboard_start_log_finish_history` (first three steps).

## Non-functional
- Performance budget: `ProgramTemplates.program` < 5 ms; save + navigate < 100 ms on device; contributes nothing to cold launch beyond the "active program?" query (< 10 ms).
- Accessibility: options are a radio group (`.isSelected` trait, one `accessibilityValue`); progress bars are one element; CTA ≥ 44 pt; Dynamic Type to AX5 with option rows wrapping (no truncation); orange check has a non-colour cue (checkmark glyph).
- Offline behaviour: fully local; no network.

## Risks / unknowns
- Spec §6.7's Lower B line promises "abs" but the §6.4 seed has no abs slot; this brief corrects the copy rather than the template. Product may prefer adding an abs slot — implementation notes must flag whichever way it lands.
- v2 shows step 3 as tickable options; spec §3.10 asks the product to clarify. This brief makes step 3 a read-only preview.
- Step-2 copy says "Upper / lower split" for 4 days but 3/5/6-day templates are new here (spec §9 gap); exercise selection is a reasoned default, not prototype-derived.
- `TrainingGoal`/`DaysPerWeek` typing must match F02's `Program`; a mismatch is fixed in F02 with a migration if already merged.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `ProgramTemplates` at 100 % line coverage; §6.4 table asserted field-by-field.
- [ ] Every template name resolves in `exercises.json` (test in LedgerDomainTests).
- [ ] String Catalog contains every string above; no literals in `Text(...)`.
- [ ] Screenshots of all three steps at default and AX5 attached to the PR.
- [ ] Fresh-install run on simulator: onboarding → Today shows "Week 1 of 8" with the chosen day.

---
_Filled in by agents during delivery:_
- `F08-onboarding/implementation-notes.md`
- `F08-onboarding/test-findings.md`
- `F08-onboarding/review.md`

## Inputs from F07 (2026-10-03, S1 fix round 1)
- Saving a program whose slot names an exercise that is not stored throws
  `RepositoryError.unknownExercise("exercise <id>")` (the first such slot, in slot order), on GRDB and on
  LedgerFakes' linked `InMemoryStores`, and saves nothing. Until the catalog is seeded (product decision #28: a
  failed seed is logged and retried), the seed program's save fails this way: catch this case to offer the
  retry, and test it on `InMemoryStores` whose exercise store lacks the catalog (`.inMemoryStores(seed: .empty)`).
- Programs given to `InMemoryStores` through its `Seed` are stored state and are not checked; only `save` is.

## Plan amendments (orchestrator, 2026-10-04)

The body above was written before M0 existed. Where it disagrees with this section, this section wins. The slice
plan and its evidence are in `F08-onboarding/implementation-notes.md`.

**Delivery.** Three slices: S1 the template generator (Domain), S2 the onboarding screen (not yet in the app), S3
the root gate and the UI tests.

**Slice S1 — template generator**
1. Types. `TrainingGoal` is the type on `main`, with its cases: the body's `stronger`, `muscle`, `both`,
   `consistent` are `.strength`, `.hypertrophy`, `.both`, `.consistency`. `Program.daysPerWeek` stays `Int?` and
   stores `days.rawValue`; `DaysPerWeek` types the generator's input only. `Program.startDate` is a `CivilDate`
   (ADR-007), so the generator takes `startDate: CivilDate`, and `ProgramTemplates.startDate(containing:weekStart:
   calendar:)` gives decision #18's date. The code lives in `LedgerDomain/Templates/`. `preview(days:)` takes no
   goal (no goal changes a name or a line).
2. Criterion 6 reads: given `both` × `four`, every slot equals spec §6.4 in every column **except load and step**,
   and the schedule equals the §6.4 seed including week 8's three days. A slot's start load is the catalog's
   `startLoad(in: units)` for its exercise, copied into the slot, and `step` is nil (product decisions #21 and #24
   are later than this brief: Bench starts at 45 lb, not 180).
3. Criterion 8 reads: with units kg, every start load is the catalog's kilogram load, a multiple of the kg step.
4. Exercise names are the catalog's full names, matched exactly among non-custom exercises. The 4-day role line's
   shorthand means: Bench → Barbell Bench Press, Incline DB → Incline DB Press, CS Row → Chest-Supported Row,
   Pulldown → Lat Pulldown, Lateral → Cable Lateral Raise, Squat → Back Squat, RDL → Romanian Deadlift, Calf →
   Standing Calf Raise, Pull-Up → **Weighted Pull-Up**, OHP → Overhead Press, Row → Barbell Row, Curl → Barbell
   Curl, Leg Curl → Seated Leg Curl. A template exercise missing from the catalog given throws
   `ProgramTemplateError.unknownExercise`.
5. Week 8 of the 3, 5 and 6-day splits keeps the full schedule (a deload changes loads, not days); the 4-day drops
   Saturday in week 8 for every goal, as §6.4 does.
6. The fixture is `Fixtures.defaultProgram(startDate:)` in `LedgerFakes` (ADR-008), built by the generator;
   `Fixtures.seedProgram()` is unchanged.
7. Program names, day names, tags and preview lines are English data in the Domain, not String Catalog entries.
8. Test names follow `docs/testing-strategy.md` §6, not the `test_…` names above. "100 % line coverage" of
   `ProgramTemplates` is checked by the reviewer from the file's coverage; the gate is per module.

## Plan amendments — slices S2 and S3 (orchestrator, 2026-10-18)

The plan's S2 (the onboarding screen) and S3 (the root gate and the UI tests) as **one pull request** on
`feat/F08-s2-onboarding`, cut from `main` @ `16a2e52` (S1 merged as #61). Where this section and anything
above it, or the notes' "Slice plan", "Seams", "Decisions for the orchestrator" and "Test plan changes"
(notes:6-337), disagree, this section wins. Line references are to `main` @ `16a2e52` unless a commit is named.

**The slices were built once already.** S2 and S3 were specified, built, attacked and reviewed on 2026-10-05 and
never merged, because S1 waited for Pete's decision 3 and the "no stacked PRs" rule held the rest behind it. Both
are on `origin`: `feat/F08-s2-onboarding-ui` @ `24b610b` (S2: G2 closed, G3 approved, the orchestrator's full gate
green, 671 product lines) and `feat/F08-s3-root-gate` @ `7c0b78f` (S3, stacked on S2: G2 closed, G3 approved,
gate green with F10 S1–S2 merged, 64 product lines). Their specifications (`ec6c370`, `4a59443`), notes, findings
and reviews are on those branches only; `main`'s copy of this brief and its notes stop at S1. `main`'s docs
already describe S2's files as the model of a screen that scrolls (`docs/testing-strategy.md:238-247`:
`OnboardingScreen.swift`, `OnboardingPage.swift`, `OnboardingFooter.swift`, `Support/OnboardingParts.swift`,
`OnboardingRootTests.swift` …), none of which exists on `main`. This slice is therefore a **port** of that work
onto today's `main`, with the changes `main` now requires (ruling R1), not a new design.

### What changed since the plan of 2026-10-04

| The plan said | `main` has now | So |
|---|---|---|
| S3 wraps `TodayPlaceholder` in `AppRoot`'s `.ready` switch, or F09's shell (notes:15, 118) | `AppRoot` draws `MainRoot` in `.ready` (`AppRoot.swift:25-26`); `MainRoot` has three members, `body` (the workout's cover, `MainRoot.swift:30-33`), `content` ("F08 adds its 'no active program' branch here", `:35-38`), `tabs` (`:41-55`); architecture:186-196 fixes that shape. `TodayPlaceholder` is gone; `today.title` is `FeatureToday/Views/TodayHeader.swift:24`, its long press reaches the Debug menu through `AppTabs.swift:23` | S3 edits `MainRoot.content` and `AppRoot`, as the 2026-10-04 rulings (notes:466-467) said |
| L0: localization scaffolding still to build; `OnboardingStrings.swift`; `StringCatalogScan` (notes:16, O1) | One catalog and copy file per module (standards:174-418), `scripts/check-string-catalogs.sh`, `CopyAudit` + `ModuleCopyTests` (`LedgerAppKitTests/ModuleCopyTests.swift`); counted texts take `locale.forCountedText` (`LedgerDomain/Units/CountedText.swift:22`, `FeatureWorkout/WorkoutCopy.swift:140-145`); `logger.category("onboarding")` is allowed by the audit and named in standards:293, :490 | The S2 branch already follows all of it except `forCountedText` (its counted body sentence predates it: R8) |
| O2: store pattern; `saveAttempt` ticket from `.task(id:)` | The convention as `TodayStore`/`WorkoutStore`/`ProgramStore` hold it (F11 brief:754-770): empty init (`TodayStore.swift:42-47`), synchronous intents, work in the root's `.task`s, internal `init(store:)` for tests (`TodayRoot.swift:30-41`), no `Task {}`/`Timer`/`TimelineView`/`.formatted(`; F11 chose a wake stream over a ticket for its save loop (F11 brief:1004-1007) | The S2 store already matches; its `.task(id: attempt)` is kept (R7) |
| O3, O13: `OnboardingRoot(prepareRetry:)` wired to `composition.resume(in: .active)` | `resume(in:)` now also runs the workout's recovery and activates WatchConnectivity (`AppComposition.swift:120-136`) | S3's review already narrowed "Retry" to `AppComposition.retrySeed()`, the database half alone (`DatabaseLaunch.swift:105`); kept |
| The page scrolls only when it does not fit (S2 G1) | The scrolling-screen convention (standards:154-156, testing-strategy:234-291) was lifted out of S2 by #41; the hosted reader refuses a scroll view; `PillButton` has its disabled look and `flush` | The S2 branch's final tree is that convention; nothing of #41 is redone |
| Shared one-line files: `snapshotTestTargets`, `required`, `registeredModules` | None lists `FeatureOnboarding` (`Package.swift:67-69`, `scripts/coverage-thresholds.json:15`, `PreviewScan.swift:9-11`); the target has no `resources` (`Package.swift:133`); `defaultLocalization` is set (`:81`) | S2 adds the module's name to each, and `resources: [.process("Resources")]` |
| O11: the existing UI tests reach Today by tapping "Skip setup"; three tests look for `today.title` (notes:85, 327-329) | **16** UI test files launch with `-LEDGER_UITEST` and wait for `today.title`; **12** of them get a program from the Debug menu's sample, which saves `Fixtures.seedProgram()` only when there is no active program (`FeatureWorkout/WorkoutLauncher+Sample.swift:41-47`), and the dated ones read week 5 of its 2026-08-17 block under `-LEDGER_UITEST_NOW` (`Apps/LedgerUITests/Today.swift:6-13`); five assertions read Today's "No program yet" (`Today.swift:33`, `TodayAuditAdversarial.swift:27-46`) | "Skip setup" would save a different program (this week's start, the catalog's loads) and make the sample's seed branch dead: R2 replaces O11 |
| F09's "No program" card becomes unreachable (notes:125-128) | It shipped: "No program yet" (`FeatureToday/TodayCopy+Cards.swift:201`) with `.setUpProgram` (`TodayPresentation+Card.swift:272`), which selects the Program tab (`Routes+Today.swift:20-23`) | Kept as the defensive state (R3) |
| CI: no sweep rule | `TestSweep` (`LedgerTestSupport/Sweeps/TestSweep.swift`) reduces size sweeps on the hosted PR run; the iOS test step has a 3,120 s deadline (`docs/ci-cd.md:79-104`) | The ported tests' size sweeps go through `TestSweep` (criterion 25) |
| Hosted root tests: none read a ready root | `LedgerAppKitTests/Adversarial/AppRootAdversarialTests.swift:86-139` reads a ready `AppRoot` as Today's scroll view | A new root's gate draws the ground first: sanctioned edit (criterion 22, R9) |
| `DatabaseUnavailableView` names the product (notes:134-135) | Fixed (`AppCopy.swift:37-43`) | Closed |
| Pete decisions 1–5 open | Answered: 1 A, 2 A, 3 A, 4 A, 5 C | Built as the defaults already were; 5 C adds an F14 input (R11) |
| Lanes in flight: F09, F10 | F11 S14 (`feat/F11-s14-program-tab`) edits `MainRoot.swift`, `Routes.swift`, `Routes+Today.swift`, `AppTabs.swift` (F11 brief:937); F10 S7b (`feat/F10-s7b-receipt`) is likely to add workout UI tests that launch to Today | Merge order and the UI-test seam: R10 |

### What S2 is (the screen, not yet shown by the app)

`FeatureOnboarding` as the S2 branch left it (`24b610b`): `OnboardingRoot` (public), `OnboardingStore`,
`OnboardingState` (step, picks, units, phase; `OnboardingAction`; `OnboardingSaveAttempt`), the pure
`OnboardingPresentation`, `OnboardingCopy.swift` and `OnboardingCopy+Options.swift` with
`Resources/Localizable.xcstrings`, `Views/OnboardingScreen`, `OnboardingPage`, `OnboardingFooter`,
`OnboardingOptionRow`, and `Onboarding+Previews.swift`. The placeholder `FeatureOnboarding.swift` and its test go.
Changes on the way in: R6 (the announcement moves into the root), R8 (`forCountedText`), criterion 25 (sweeps).

### What S3 is (the app opens on it)

`LedgerAppKit/RootGate.swift` (`.loading / .onboarding / .main` from `ProgramRepository.observeActive()`, after the
launch's first pass), `AppRoot` owning the gate (internal `init(composition:gate:)` for tests), the switch in
`MainRoot.content`, the shell started again when onboarding appears (R4), `AppComposition.retrySeed()`, the UI-test
program seam (R2), and every UI test brought to the new first screen. The S3 branch's product delta
(`git diff 5ff87ff 7c0b78f` plus `git diff 24b610b aff5855`, `LedgerKit/Sources` only) is re-applied by hand to
today's files; its tests are ported and adapted.

### Store conventions (as `TodayStore`, `WorkoutStore`, `ProgramStore` hold them)

- `OnboardingStore` is `@MainActor @Observable final class` with an empty initializer; `OnboardingRoot` keeps it
  in `@State` and takes one in an internal `init(store:prepareRetry:announce:)` for tests (`TodayRoot.swift:30-41`,
  `ProgramRoot.swift:44-54`). `RootGate` follows the same rule (nothing in its `init`).
- Intents are synchronous and only change state (`send(_:)`); an accepted tap on "Start training", "Skip setup" or
  "Retry" makes the next `OnboardingSaveAttempt`, the id of the root's `.task(id:)`, which runs `save(prepareRetry:)`
  (R7). `loadUnits()` runs from a plain `.task`. The gate's `follow` runs from `AppRoot`'s `.task(id: scenePhase)`.
- No `Task {}`, `Task.detached`, `DispatchQueue`, `Timer`, `TimelineView`, `.formatted(`, `Date()`,
  `Calendar.current`, `Locale.current` (standards §4, §11). Time, ids, calendar and locale are the injected
  `\.date`, `\.uuid`, `\.calendar`, `\.locale`; the store logs through `logger.category("onboarding")` and never logs
  a cancellation (standards:490).
- Every lookup is in `OnboardingCopy*.swift`; the counted body takes `locale.forCountedText`; no other file holds a
  literal a lifter reads or hears. Display values come only from `OnboardingPresentation.make`.
- The feature has no route and makes no navigation call (architecture:197-198): saving the active program is the
  navigation, and the gate follows it.

### Acceptance criteria

**The screen (S2).** Criteria 1–11 are the S2 branch's specification (`ec6c370`, brief section "Plan amendments
— slice S2"), restated with today's amendments.

1. **Start.** `OnboardingRoot` opens on step 1 of 3 with "Both, honestly" picked; the bars read "Step 1 of 3".
2. **Picking and moving.** A tap picks one option and unpicks the others; the picked one shows the orange check
   (a glyph, not colour alone). "Continue" goes to step 2 ("4 days" picked) and step 3. Steps 2 and 3 have a
   "Back" pill (O9); the picks survive going back and forth.
3. **Step 3 is a read-only list** (Pete 2 = A): every day of `ProgramTemplates.preview(days:)`
   (`ProgramTemplates.swift:61`) in order, each "{name with ' — ' replaced by ' · '}" over its line ("Upper A ·
   Push focus" / "Bench, incline, row, pulldown, laterals"); not buttons, no check. The body reads "{program name},
   8 weeks, {pounds|kilograms}. Editable any time.", in the stored settings' unit. Lower B's line is "Deadlift,
   front squat, leg curl" (Pete 1 = A; the Domain's data).
4. **"Start training"** saves exactly one program: `ProgramTemplates.program(_:catalog:id:newID:)` (`:94`) over the
   picks, the stored units, `startDate(containing:weekStart:calendar:)` (`:71`) for the injected date, calendar
   and the stored week start (Pete 4 = A), `exerciseRepository.all()`, the program's id from `\.uuid` first and
   then the generator's ids. It is active. A second tap while a save runs, or after one succeeded, saves nothing.
5. **"Skip setup"**, on any step, saves `both` × four days in the same way, whatever is picked.
6. **Kilograms.** With stored units kg the body says "kilograms" and the start loads are the catalog's kilogram
   loads. Units and week start are whatever the stored settings say (Pete 5 = C: pounds and Monday today).
7. **Failure.** A failure to read the settings or the catalog, to generate (an unseeded catalog throws
   `ProgramTemplateError.unknownExercise`), or to save shows "Couldn't save your program. Try again." with
   "Retry"; nothing is saved; it is logged once under "onboarding". "Retry" awaits `prepareRetry`, then saves the
   failed attempt's picks again. While the failure shows, picks and "Back" are locked. A cancelled task is not a
   failure and logs nothing; a save cancelled before its write leaves the phase as before the tap.
8. **VoiceOver.** The trees of the S2 branch's notes ("The intended VoiceOver trees", notes @ `24b610b`
   :1019-1083) hold, copied into this lane's notes and pinned by `OnboardingAccessibilityTests` from
   `Support/OnboardingParts` (testing-strategy:248-254): each option one button "{label}, {sub}", `.isSelected`
   when picked, no value; the bars one element "Step n of 3" with no value; the title a header; preview rows
   static text; on step 1 "Back" is no stop; while saving every button is not enabled. When the failure line
   appears it is announced once, through the root's `announce` (R6), pinned by a root test.
9. **Copy.** Every text below is in `FeatureOnboarding`'s catalog and looked up in its copy files; the counted
   body passes `locale.forCountedText` (R8). `ModuleCopyTests` passes with no exemption for the module, and the
   gate's catalog step (`scripts/check-string-catalogs.sh`) passes. No text names the product.
10. **Type sizes, themes and scrolling.** The screen is its pinned footer plus `ScrollView { OnboardingPage }`;
    one layout at every size; going to another step starts it at its top (`OnboardingScrollTests`). Option rows
    wrap and nothing truncates or is cut, light and dark, up to `.accessibility5`, on a 375 pt phone.
11. **Surface.** `OnboardingRoot(prepareRetry:)` is the module's only public symbol (`OnboardingSurfaceTests`); a
    new `FeatureOnboardingSourceTests` reads the module for the spellings listed under "Store conventions", as
    `FeatureTodaySourceTests` does.

**The app (S3).** Criteria 12–21 are the S3 branch's specification (`4a59443`), restated.

12. **Fresh install.** With no active program, once the database is open and the launch's first pass
    (`composition.resume(in:)`) has returned, the root shows onboarding on step 1, full screen, no tab bar.
    Before that it draws the ground colour only (O12): neither screen flashes by.
13. **A lifter with a program** opens on the tabs with Today selected, and onboarding never flashes by.
14. **Finishing.** "Start training" or "Skip setup" switches the root to the tabs with Today selected and every
    stack empty, the second time as the first (R4). Nothing but the stored active program makes the switch.
15. **Following.** The program going away (F14's "Delete all data") shows onboarding; one appearing (F28) shows
    the tabs. An observation that ends on a task nobody cancelled shows the tabs, never onboarding. A cancelled
    follow changes nothing, so a phase change keeps onboarding's step and picks.
16. **Retry** runs `AppComposition.retrySeed()` (`database.resume(isForeground: true)` alone), which always
    returns, then saves. Pinned by `failedSeed_isRetriedByTheCallRetryMakes`, and by a hosted root test of the
    line in `MainRoot` that passes it if `LedgerTestSupport` on `main` can host it without sleeping; otherwise
    the gap (S3 review SF1) is written in the notes again.
17. **The week** (brief criterion 11). Saved through onboarding at `Fixtures.now` (Wednesday 2026-09-16, weeks
    from Monday): `startDate` 2026-09-14, in week index 0, on a real database (the words on Today are F09's).
18. **Relaunch** opens on the tabs: a package test boots twice on one database file.
19. **Unchanged:** the Debug menu opens from a long press on Today's title once a program exists; the
    database-unavailable screen; the watch app; launch-to-first-frame is still measured at the root's first
    appearance, which is now the ground colour (architecture §14 says so: S3 review SF3).
20. **The UI-test program** (R2). `-LEDGER_UITEST_PROGRAM seed` beside `-LEDGER_UITEST`, read in Debug builds only
    as `UITestSaveFailures` reads its argument (`UITestSaveFailures.swift:11-42`): after the launch's first pass
    and before the gate's first read, when there is no active program, `Fixtures.seedProgram()` is saved as the
    active one, once; a Release build reads nothing. Tests as `UITestSaveFailuresTests` (argument absent,
    present, malformed, without `-LEDGER_UITEST`; the gate reads `.main` on its first value).
21. **UI tests** (`Apps/LedgerUITests`):
    a. `Smoke.test_launchesToToday` becomes `test_freshInstall_skipsSetupToToday` (in `Smoke`, so the PR plan's
       selection is unchanged): `onboarding.title`, tap `onboarding.skip`, then `today.title` reads "Today".
    b. `Onboarding` (nightly, from the S3 branch): the three steps with their picks; the VoiceOver order of each
       step inside the real scroll view at an accessibility size; a step opening at its top; "Start training"
       landing on Today. `OnboardingAdversarial*` (the tester's, with its three audit exclusions) come too.
    c. `DebugMenu` reaches Today by "Skip setup" and reads `debug.diagnostics.rows.program` 1, `program_week` 8,
       `day_template` 4, `slot` 16: criteria 4 and 5 on the real database.
    d. `LaunchPerformance`'s report step skips setup first.
    e. Every other launch (the other Smoke tests, `Tabs`, `TabsAdversarial`, `Today`, `TodayAuditAdversarial`,
       `Workout*`) adds `-LEDGER_UITEST_PROGRAM seed` to its launch arguments, one line per launch helper and
       nothing else. The five "No program yet" assertions are removed; `TodayAuditAdversarial`'s three
       no-program audits are replaced by the onboarding audits of `OnboardingAdversarial+Audit` (R3).
    The identifiers stay the S3 branch's: `onboarding.title`, `.progress`, `.option.<n>`, `.preview.<n>`,
    `.cta`, `.skip`, `.back`, `.error`.

**Throughout.**

22. **Hosted root tests.** Tests that read a ready `AppRoot` (`AppRootAdversarialTests.swift:86-139`) hand it a
    gate already at `.main` through `init(composition:gate:)`; `RootGateTests`, `RootGateLaunchTests`,
    `AppRootTests` and the tester's root suites from the S3 branch cover `.loading`, `.onboarding`, `.main`.
23. **Shared files.** `FeatureOnboarding` gains `resources: [.process("Resources")]` (`Package.swift:133`) and is
    added to `snapshotTestTargets` (`:67-69`), `coverage-thresholds.json` `required` (`:15`) and
    `PreviewScan.registeredModules` (`PreviewScan.swift:9-11`): its name only (M1 convention 4).
    `package-graph.expected.txt` does not change.
24. **Coverage and gate.** `FeatureOnboarding` at or above its threshold (70; the S2 branch had 99.85 %); coverage
    does not decrease elsewhere; `scripts/check.sh` green; the nightly UI run green.
25. **CI time.** Each ported test that sweeps text sizes over hosted views takes `TestSweep.sizes(…)` (or names its
    finding's size in `also:`) unless it checks all sizes at once; the implementer measures the seconds the
    slice adds to the iOS test step under `TEST_RUNNER_LEDGER_SWEEP=pr` and writes them in the notes.
26. **Docs.** architecture §4 (the gate in the root bullet, `docs/architecture.md:165-196`) and §14
    (launch-to-first-frame ends at the ground colour); testing-strategy §2.7's first flow is
    `Smoke.freshInstall_skipsSetupToToday`, and the UI-test program argument is written under §2.7's launch
    bullet (:324-326); F14's "Inputs from F08" gains the locale week-start follow-up (R11).

### Texts

Exact, from `docs/product-spec.md` §6.7 (:672-680) and the brief's "Copy (exact)" (above, :82):

| Where | Text | Source |
|---|---|---|
| Step 1 title / body | "What are you training for?" / "This sets how your loads progress week to week." | spec §6.7; brief :82 (no product name) |
| Step 1 options | "Get stronger" — "Low reps, linear load increases"; "Build muscle" — "Moderate reps, volume tracking"; "Both, honestly" — "Barbell strength + accessory volume"; "Stay consistent" — "Habit first, numbers second" | spec §6.7 |
| Step 2 title / body | "How many days a week?" / "Pick the number you will actually hit, not the one you want to hit." | spec §6.7 |
| Step 2 options | "3 days" — "Full body each session"; "4 days" — "Upper / lower split"; "5 days" — "Push, pull, legs + accessories"; "6 days" — "Body-part split" | spec §6.7 |
| Step 3 title / body | "Your program" / "%@, %lld weeks, %@. Editable any time." with "pounds" / "kilograms" | spec §6.7; brief :82 |
| Buttons | "Continue", "Start training", "Skip setup", "Retry" | spec §6.7, §3.10 (:366); brief :82 |
| Failure | "Couldn't save your program. Try again." | brief :82 |
| Spoken | "Step %lld of %lld" | brief criterion 12 ("Step 1 of 3") |
| **Invented** | "Back" (O9; the design draws none). The singular form "%@, %lld week, %@. Editable any time." (the plural rule's `one`; never shown at 8 weeks). Every translator's comment | the S2 branch |

Not copy: the program, day names, tags and preview lines (`ProgramTemplates`, Domain data; O7). The S3 slice adds
no text: the gate draws the ground colour or another feature's root.

### Accessibility

As criterion 8, plus the manual list from the S2 and S3 branches: focus moves to the new title after "Continue"
(`@AccessibilityFocusState`, `OnboardingPage`); every button at least 44 pt (`OnboardingAccessibilityTests`);
Dynamic Type to AX5 by hand on the simulator; Apple's audit in the nightly `OnboardingAdversarial+Audit` with its
three exclusions and their reasons (white on the accent "contrast nearly passed", F06's decision; "text clipped"
on display roles whose line height is below Archivo's natural one; a line hidden behind the pinned footer measured
against it), light and dark.

### Snapshot references

The S2 branch's 18 (O10), drawn from `Support/OnboardingParts` (page then footer) at 402 pt: step 1 light and dark
× `.large`, `.xLarge`, `.accessibility3` (6); step 2 light and dark × `.large` (2); step 3 four days, the full
matrix (6); step 3 six days, dark × `.large`, `.accessibility3` (2); step 3 failed, light and dark × `.large` (2).
They are ported as recorded on 2026-10-05; if the gate shows a difference, each re-recorded reference names its
visual cause in the PR (testing-strategy:209-213). Under 20, so no `chore(snapshots):` PR. No LedgerAppKit
reference changes (`ShellSnapshotTests` draws the shell, not the root). The PR also carries the DoD's screenshots:
the three steps at the default size and at AX5, a fresh install's first screen, and Today after "Start training",
light and dark.

### Tests the criteria ask for

Ported from the branches (names as there): `OnboardingStore*Tests`, `OnboardingPresentation*Tests`,
`OnboardingCopyTests`, `OnboardingAccessibilityTests` + `OnboardingAccessibilityTrees`, `OnboardingSnapshotTests`,
`OnboardingScrollTests`, `OnboardingRootTests`, `OnboardingSurfaceTests`, `PreviewTests`, the tester's 22
`Adversarial/` files; `RootGateTests`, `RootGateLaunchTests`, `AppRootTests`, `Support/GateSupport`, the tester's
`RootGate*`/`AppRoot*` adversarial suites (only the F08 ones: the S3 branch also carries F10 S1–S2's, already on
`main` in their final form). New: `FeatureOnboardingSourceTests` (11), a root test of the announcement (8), the
`UITestProgram` suite (20), the root test of `retrySeed` wiring if hostable (16), `AppRouterTests` or
`MainRootTests` for the second onboarding opening on Today with empty stacks (14), the edited
`AppRootAdversarialTests` (22). UI: `Onboarding`, `OnboardingAdversarial*`, `Support/LaunchedApp` (its "Skip setup"
helper), and the edits of 21.

### Not in this slice

Editing the generated program (F11); "Delete all data" and the unit change's effect on stored loads (F14); a
first-launch region default for units or week start (Pete 5 = C; F14); a UI-test launch mode that keeps its
database across launches (F15); the launch screen's colour (a target change: Question 3); an abs slot on Lower B
(Pete 1 = A); "Start next block" (F24); anything on the watch; any change to `LedgerDomain` but the comment in R11;
any change to the program tables (Pete 3 = A: as written, the double-progression and `consistency` points not
applied).

### Product lines, estimated (standards §10: code only, not tests, catalogs, docs or comments)

| Part | File | Lines |
|---|---|--:|
| S2 | `FeatureOnboarding/OnboardingStore.swift` | 120 |
| S2 | `OnboardingState.swift` | 41 |
| S2 | `OnboardingPresentation.swift` | 121 |
| S2 | `OnboardingCopy.swift` (+ `forCountedText`, R8) | 89 |
| S2 | `OnboardingCopy+Options.swift` | 84 |
| S2 | `OnboardingRoot.swift` (+ `announce`, R6) | 29 |
| S2 | `Views/OnboardingScreen.swift`, `OnboardingPage.swift`, `OnboardingFooter.swift` (− the announcement), `OnboardingOptionRow.swift` | 24 + 62 + 28 + 33 |
| S2 | `Onboarding+Previews.swift` | 49 |
| S2 | the placeholder `FeatureOnboarding.swift` removed | −3, not counted |
| | **S2** | **~680** |
| S3 | `LedgerAppKit/RootGate.swift` (new) | 32 |
| S3 | `AppRoot.swift` (the gate, the task, the test init) | ~9 |
| S3 | `MainRoot.swift` (the switch, onboarding's branch, the new router on appear) | ~15 |
| S3 | `AppComposition.swift` (`retrySeed()`, the program seam's field and call) | ~8 |
| S3 | `LedgerAppKit/UITestProgram.swift` (new, R2) | ~22 |
| S3 | `FeatureWorkout/WorkoutLauncher+Sample.swift` (the seed made callable, Debug only, R2) | ~6 |
| | **S3** | **~92** |
| | **Total** | **~770** |

S2's lines are measured, not planned (the branch's files counted as standards §10 counts, plus the two small
changes); S3's are the branch's 64 re-applied plus R2's seam. **One pull request:** inside the 700–900 band and
under 1,000. The 50–90 % overruns seen were fresh builds against a plan; here 87 % of the lines exist and are
counted, and even +20 % (~925) stays under the split line. **Past about 950 the implementer stops and reports.**
The split, if needed: S2 alone (~680; not wired, so safe to merge alone, and it makes testing-strategy:238-247
true), merged first; then S3 from `main` (~92). No stacked pull requests.

### Project file and test plans (human-owned: flagged, not planned)

- **No `project.pbxproj` change.** `Apps/LedgerUITests` is a synchronized folder (`Ledger.xcodeproj/project.pbxproj:90`),
  so `Onboarding.swift`, `OnboardingAdversarial*.swift` and the new `Support/LaunchedApp.swift` need no entry (the
  S3 branch added them so). Every product file is in `LedgerKit`.
- **No test-plan change.** `FeatureOnboardingTests` is already in both plans (`TestPlans/PR.xctestplan:94`,
  `Nightly.xctestplan:94`); `PR` selects `Smoke` in `LedgerUITests` (`PR.xctestplan:160-162`), and the renamed test
  stays in `Smoke`; `Nightly` runs every UI test.
- **The UI tests that wait for `today.title` after a fresh launch** (all 16 files; criterion 21) stop finding it
  the moment the gate lands: a fresh `-LEDGER_UITEST` database now opens on onboarding. S3 keeps them passing in
  the same pull request: the PR-lane `Smoke` launch-to-Today test goes through onboarding ("Skip setup"), the
  ones that need the spec's seed program launch with `-LEDGER_UITEST_PROGRAM seed` and are otherwise unchanged,
  and the no-program assertions go. Any UI test another lane adds before this merges needs the same one line.

### Rulings needed from the orchestrator

- **R1. Port, not rebuild.** Bring the S2 branch's `FeatureOnboarding` sources, catalog, tests and references,
  and the S3 branch's F08 tests, onto `feat/F08-s2-onboarding` as files (`git show <branch>:<path>` or `git
  restore --source=<branch> -- <path>`), and re-apply the S3 branch's product delta and the shared one-line files
  by hand. Do not merge either old branch: `git merge-tree main feat/F08-s3-root-gate` conflicts in 36 files, most
  of them pre-squash copies of #28 and #41. Carry the branches' S2/S3 notes, findings and review sections into this
  lane's files, marked as of 2026-10-05. Then a G2 and a G3 on the port: the tester re-runs every ported
  adversarial test and attacks what is new (R2's seam, the gate over today's `MainRoot`, the router replaced, the
  UI-test edits); the reviewer reads the delta against `24b610b` / `7c0b78f` and the new files whole.
  *Recommendation:* as written; rebuilding would re-spend two reviewed slices and leave the docs' model files
  missing meanwhile.
- **R2. How the UI tests get a program** (replaces O11). *Recommendation:* the Debug-only launch argument of
  criterion 20, saving `Fixtures.seedProgram()` through the function the Debug sample already uses (made callable
  from `LedgerAppKit` inside `#if DEBUG`, so no package edge is added and `package-graph.expected.txt` stays). The
  alternative, a helper that taps "Skip setup" everywhere, saves this week's block with the catalog's loads, makes
  the sample's seed branch dead, and means rewriting every week-5 and load assertion in 12 tester files. F15 still
  owns a launch mode that keeps its database.
- **R3. Today's "No program yet".** *Recommendation:* keep the card, its texts and `.setUpProgram` as the state
  shown when the gate's read failed and Today can still read (defensive, nothing removed from F09); remove the UI
  assertions that reach it on a fresh database and replace the three no-program audits with onboarding's.
- **R4. Starting the shell again.** The S3 fix for F8-S3-1 added `AppRouter.reset()`. F11 S14 adds state to the
  router (the requested week). *Recommendation:* `MainRoot` replaces its router with a new `AppRouter()` when
  onboarding appears, so no reset method has to keep up with the router's fields; pinned by a test that pushes a
  screen, goes through onboarding and finds Today with every stack empty.
- **R5. The workout's cover stays on `MainRoot.body`**, around the gate's content, as architecture:194-196 has
  it. *Recommendation:* keep. No workout can start while onboarding shows; one recovered at launch has a program,
  so the gate shows the tabs under it.
- **R6. The failure's announcement** is posted from `OnboardingFooter` on the branch (`AccessibilityNotification
  .Announcement(...).post()` in a view). *Recommendation:* move it to `OnboardingRoot`, through an `announce`
  closure in its internal init with the posting default, as `ProgramRoot.swift:44-54, 76-80` does, so a root test
  hears it once.
- **R7. `.task(id: store.attempt)`, not a wake stream.** *Recommendation:* keep the attempt id: an attempt is
  accepted only while no save runs, so a change of id never cancels a write (the reason F11 took a stream), and the
  branch's tests pin it.
- **R8. The counted body sentence** is a plural key looked up with the plain locale on the branch.
  *Recommendation:* add `var forCountedText: Locale { forCountedText(in: .module) }` to the copy file and pass it,
  as `WorkoutCopy.swift:140-145`; a test with `fr_FR` that still reads "weeks".
- **R9. Sanctioned edits of testers' files:** `AppRootAdversarialTests` (criterion 22); the launch lines of
  `Tabs`, `TabsAdversarial`, `Today`, `TodayAuditAdversarial`, `Workout*Adversarial`, `WorkoutLogging`,
  `WorkoutRest`, `WorkoutSaveFailure`; the five no-program assertions. *Recommendation:* the implementer makes
  them, lists each with its diff in the notes, and the tester audits that list (F11 R11's way).
- **R10. Order with the lanes in flight.** F11 S14 edits `MainRoot.swift` and `Routes.swift`; F10 S7b may add UI
  tests that wait for `today.title` on a fresh launch. *Recommendation:* build now; open this PR after S14 and
  S7b have merged (merge `main` in, gate, push once), and tell both lanes now that a UI test written for `main`
  after this lands needs `-LEDGER_UITEST_PROGRAM seed` or "Skip setup".
- **R11. Pete 5 = C.** *Recommendation:* one bullet in F14's "Inputs from F08" (`F14-settings.md:76`): decision #15
  (week start from the iPhone's region on first launch) is unimplemented and onboarding copies the stored units
  and week start into the block; F14 decides whether first launch reads the region. And the comment at
  `LedgerDomain/Model/Settings.swift:36-39` stops saying the app seeds the week start ("F14 decides"); comment
  only, no product line.
- **R12. The retry wiring's test** (criterion 16; S3 review SF1, left open on 2026-10-05). *Recommendation:*
  require the hosted root test if `ProbedStores` / `StoreProbe` can refuse the seed and the root can be driven
  without a sleep; otherwise say so in the notes, not a blocker.

### Open questions for the product owner (the default holds until answered)

1. **"Back" on steps 2 and 3.** The design has no way back; the screen draws a small "Back" pill. Default: keep it.
2. **"Skip setup" after picking** saves the 4-day "Both, honestly" program, not the picks. Default: as now (the
   design's "Skip" means "skip the questions").
3. **The launch screen is white in light mode** and the first frame is cream, so a fresh launch fades from white
   to cream. Default: leave it for F26 (it is a change to the app target, yours to make).
4. **The first screen waits for the launch's first pass** (the ground colour for a moment, hidden under the launch
   screen on the simulator), for lifters with a program too. Default: keep; F26 measures it on a device.
5. **Apple's accessibility audit** flags white text on the orange button as "contrast nearly passed" (3.1:1,
   decision of F06) and long titles as "may be clipped" (tight line heights). Default: keep both as decided; F15
   lists them again.
