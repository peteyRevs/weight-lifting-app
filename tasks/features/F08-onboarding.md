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

## Plan amendments — slice S2, the onboarding screen (orchestrator, 2026-10-05)

S1 (the template generator) is ready and waits for Pete; the localization rule and helper are F09 S1's (#28, in
review). S2 is built locally on both and its PR opens after both are on `main`. This section is S2's
specification; where it and the body above disagree, this section wins. Signatures and line references are in
`F08-onboarding/implementation-notes.md` ("Inputs the implementer needs › S2", "Test plan changes", the rulings).

S2 builds the three-step onboarding screen in `FeatureOnboarding`, drawn and tested on its own. It is **not wired
into the app**: the app still opens on the tabs, and S3 adds the root's branch.

1. **Start.** `OnboardingRoot` opens on step 1 of 3 with "Both, honestly" picked, and the progress bars read "Step 1
   of 3".
2. **Picking and moving.** Tapping an option picks it and unpicks the others; the picked one shows the orange check
   (a checkmark glyph, not colour alone). "Continue" goes to step 2, where "4 days" is picked by default, and again
   to step 3. Steps 2 and 3 have a "Back" pill; the picks survive going back and forth.
3. **Step 3 is a read-only list** (no ticks; it is not tappable): every day of the split the lifter picked, in order,
   each as the day's name with " — " replaced by " · " and its preview line (for example "Upper A · Push focus" /
   "Bench, incline, row, pulldown, laterals"), from `ProgramTemplates.preview(days:)`. The body reads "{program
   name}, 8 weeks, {pounds|kilograms}. Editable any time.", the unit being the stored setting's.
4. **"Start training"** saves exactly one program: the one `ProgramTemplates` generates from the picks, with the
   stored settings' units, the start date `ProgramTemplates.startDate(containing:weekStart:calendar:)` gives for the
   injected date, calendar and the settings' week start, the stored catalog, and ids from the injected generator. It
   is active. The screen makes no navigation call: the root (S3) follows the active program. A second tap while a
   save is in flight, or after it succeeded, saves nothing more.
5. **"Skip setup"**, on any step, saves the `both` × four-day program in the same way, whatever was picked.
6. **Kilograms.** With stored units kg, step 3's body says "kilograms" and the saved program's start loads are the
   catalog's kilogram loads.
7. **Failure.** If reading the settings or the catalog, generating, or saving fails (an unseeded catalog makes the
   generator throw `unknownExercise`; a repository may throw), the screen shows "Couldn't save your program. Try
   again." with "Retry", nothing is saved, and the failure is logged. "Retry" first awaits the `prepareRetry`
   closure the root was given (S3 passes the launch's seed step), then tries again with the same picks.
8. **VoiceOver.** Each option is one button whose label is "{label}, {sub}", with the selected trait when picked and
   no value. The progress bars are one element, "Step 1 of 3". The tree of each step is written in the notes and
   pinned by a test.
9. **Copy.** Every string is in `FeatureOnboarding`'s String Catalog and resolved in `OnboardingCopy.swift`, as
   `docs/engineering-standards.md` §7 requires; the texts are the body's "Copy (exact)" (with "This sets how your
   loads progress week to week."), plus "Back". No string names the product. Program and day names and preview
   lines are the Domain's data, shown as given.
10. **Type sizes and themes.** Option rows wrap and nothing truncates up to the largest accessibility size the
    snapshot matrix has; light and dark. Snapshot references: step 1, step 2, step 3 for four days and for six days,
    and the failure state (18 images, as the plan's matrix says).
11. **Surface.** `OnboardingRoot(prepareRetry:)` is the module's only public type. The store follows the M1
    conventions (no task that outlives the view; pure presentation; tokens only).

Defaults in force until Pete answers (asked 2026-10-04): step 3 is the read-only list above; first-launch units and
week start are whatever the stored settings say (pounds and Monday today).
