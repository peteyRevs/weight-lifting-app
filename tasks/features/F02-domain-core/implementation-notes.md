# F02 — implementation notes

Branch `feat/F02-domain-core` (based on `00a504b`).
- **Implementer pass:** 2026-09-26 (commit `f30d94e`).
- **Revision 1:** 2026-09-27. It applies ADR-007 (exact weights and a calendar-date program
  start, decided by Pete) and resolves the adversarial findings; see "Revision 1" below.

## What was built

`LedgerDomain` now holds every F02 type and rule, importing Foundation only:

- `Identifiers.swift`: nine typed IDs sharing a `TypedIdentifier` protocol, plus deterministic
  child-ID derivation (`WorkoutExerciseID.derived`, `SetID.derived`).
- `Units/`: `Units`, `Weight`, `Reps`, `RPE`, `RestDuration`, `Volume`, and `NumberText`
  (internal, locale-free number text, `Decimal` rounding, and the exact decimal-text codec
  `DecimalText`).
- `Model/`: every model struct and enum in the brief's sketch, plus `CivilDate` (ADR-007).
- `Rules/`: `ProgressionRules`, `SessionBuilder`, `SupersetRounds`, `OneRepMax`,
  `PersonalRecords`, `PlateMath`, `TimeEstimate`, `WeekCalendar` (+ `WeekKey`), `MissTracking`.
- `Protocols/`: `ExerciseRepository`, `ProgramRepository`, `WorkoutRepository`,
  `SettingsRepository`, `StatsQueries`, plus the empty `HealthStore`, `LiveWorkoutTransport`,
  `CompanionTransport` and a reserved `WorkoutEventStore`.
- `Errors.swift`: `ProgramValidationError`, `SlotValidationError`, `SessionBuilderError`.

The placeholder `LedgerDomainModule` and its test are deleted. `Resources/exercises.json` was
not touched.

## Verification (after revision 1)

| Check | Result |
|---|---|
| `scripts/check.sh --fast` (format, strict lint, package graph, `swift test` for Domain + Persistence) | **OK**: 369 tests in 61 suites (367 domain tests in 59 suites, plus F00's 2 persistence tests) |
| `LEDGER_PROPERTY_SEED_COUNT=2000 swift test --package-path LedgerKit --filter LedgerDomainTests` | **OK**: 367 tests, 59 suites |
| LedgerDomain line coverage | **98.87 %** (1326 lines, 15 missed) |

The 367 domain tests are my 158 plus the adversarial tester's 209. Nothing is skipped or disabled.

Coverage commands, run from the worktree root:

```sh
swift test --package-path LedgerKit --filter LedgerDomainTests --enable-code-coverage
BIN=$(swift build --package-path LedgerKit --show-bin-path)
xcrun llvm-cov report "$BIN/LedgerKitPackageTests.xctest/Contents/MacOS/LedgerKitPackageTests" \
  -instr-profile="$BIN/codecov/default.profdata" LedgerKit/Sources/LedgerDomain
# TOTAL … Lines 1326, Missed 15, Cover 98.87%
```

All 15 missed lines are autoclosures of `??` fallbacks that cannot fire, for example
`Weekday(calendarWeekday:) ?? .monday`, `parts.year ?? 1970` on components Foundation always
returns, or `.max() ?? 0` on a non-empty group. `llvm-cov report -show-functions` lists every one
as an `…Xefu_` autoclosure.

Property tests read `LEDGER_PROPERTY_SEED_COUNT` (default 200) and run one parameterized case per
seed through a SplitMix64 `SeededGenerator`. The tester's regression seeds are pinned with
`PropertySeed.all(plus:)`.

## Acceptance criteria → tests

| # | Test(s) |
|---|---|
| 1 | `WeightTests.pounds_toGrams_exact` (ADR-007: `grams == 83914.58845`) |
| 2 | `WeightTests.roundedToStep_table` (the first two rows), `roundedToStep_isIdempotent` (property) |
| 3 | `ProgressionRulesTests.double_repsClimbThenLoadRisesAndRepsReset` |
| 4 | `ProgressionRulesTests.deload_loadTimes085RoundedToStep_minusOneSet_minusTwoRPE` |
| 5 | `ProgressionRulesTests.linear_missedWeekHoldsLoad`, `held_flagSetWhenPreviousWeekMissed` |
| 6 | `PlateMathTests.perSide_185lb_is45plus25`, `…180lb…`, `…250lb…`, `perSide_belowSmallestPlate_isNil` |
| 7 | `OneRepMaxTests.brzycki_195x5_is219lb`, `brzycki_returnsNil_above12Reps` |
| 8 | `SupersetRoundsTests.displayOrder_isRoundMajor_A1B1A2B2`, `isLastOfRound_trueOnlyForLastMember` |
| 9 | `TimeEstimateTests.minutes_solo_isSumOf42PlusRestPerSet`, `minutes_superset_countsRestOncePerRound` (the formula and its arithmetic are written in the test) |
| 10 | `WeekCalendarTests.weekIndex_fromStartDate` (first two rows), `criterion10_weekdayAndPreviousCompleteWeek` |
| 11 | `MissTrackingTests.workingSetShortOfTargetReps_marksWeekMissed`, `deloadWeek_neverMarksMissed`, `shortDropSet_doesNotMarkMissed` |
| 12 | `PersonalRecordsTests.detect_newBestE1RM` |
| 13 | `SlotValidationTests.init_invalidRange_throwsMatchingCase` (sets 13, reps 0, repsHi ≤ reps, rpe 4.75, rest 100, and more) |
| 14 | `ModuleBoundaryTests.sources_importFoundationOnly`, plus `scripts/check-package-graph.sh` (unchanged graph, green) |

Every test name that testing-strategy §2.1 lists for F02's suites exists under that exact name.
None of the test names carry a `test` prefix.

## Decisions

1. **Exact weights (ADR-007, which replaced my original unit-lattice design).**
   - `Weight.grams` is an exact `Decimal`, never rounded on construction: `.pounds(185)` is
     83,914.58845 g.
   - `+`, `-`, `scaled(by:)` and `advanced(bySteps:of:)` are exact.
   - `rounded(toStep:_:)` is `(grams / step.grams).rounded(rule) × step.grams`. There is no unit
     inference, so ties on any step are real ties.
   - The only other rounding is the Brzycki e1RM, which is an estimate kept to the nearest gram
     (decision #4).
   - `Volume.gramReps` is exact too.
   - Equality, hashing and ordering are `Decimal`'s own and numeric. I probed this on the
     toolchain: 1 == 1.00 and 0.1 + 0.2 == 0.3, each with equal hashes. `equality_isNumeric_hashesAgree`
     pins it.
   - Codable writes exact decimal text: `{"grams": "83914.58845"}` and `{"gramReps": "…"}`.
     `DecimalText.parse` accepts only `-?digits(.digits)?`, and rejects numbers, "1e3", "NaN",
     "12abc" and "1,5".
   - Why text rather than a JSON number: `JSONEncoder` writes exact number text, but other
     consumers (e.g. `JSONSerialization`, which the tester's tamper helpers use) read numbers
     through `Double`.
   - What was removed: the original design inferred a step's unit from its gram value
     (`Units.denominating`) and computed on 0.01 lb "quanta". That code is deleted.
2. **Calendar-date program start (ADR-007).**
   - `Program.startDate` is a `CivilDate` (year, month, day; `Hashable`, `Comparable`,
     `Sendable`, encoded as `"YYYY-MM-DD"`, validated on init and decode).
   - Day arithmetic uses Howard Hinnant's integer `days_from_civil` / `civil_from_days`, so it
     never touches an instant.
   - `WeekCalendar` maps each instant to its civil day in the calendar's zone
     (`civilDate(of:)`). Every boundary is `CivilDate.startOfDay(in:)` of the target day (start +
     7·i). That is `startOfDay` of that day's noon, so a day whose midnight DST skips starts at
     01:00 without moving any other boundary.
   - New `WeekCalendar.firstDayOfWeek(containing:)` gives F08 a new block's `startDate`.
3. **Formatting is locale-free and hand-rolled** (`NumberText`), following the spec's own formats:
   '.' as the decimal point, ',' as the thousands separator, `×`, `·`, `—`. No `Locale`,
   `NumberFormatter` or `FormatStyle` is used, so output is identical on any host.
   - **Weights**: a value that is a whole number of quarter units (every plate and step: 1.25,
     2.5, 52.5, 46.25) prints exactly with trailing zeros dropped. Anything else prints to one
     decimal. This satisfies both criterion 1 ("83.9" for 83.91458845 kg) and criterion 6's
     "1.25" plate.
   - **Volume**: `formatted` gives whole units with thousands separators; `compact` always gives
     one decimal plus "k", like JS `toFixed(1)` ("24.0k").
   - **`LastPerformance.line`**: day and month come from a Gregorian calendar in the passed
     calendar's time zone. The month name comes from a fixed English table ("Aug"), as in the spec.
4. **Decimal constants are built exactly.** 453.59237 and 0.85 are built from integers. On this
   toolchain a `Decimal` float literal `453.59237` evaluates to `453.5923699999999488` (probed),
   while dyadic literals such as 242.25 and 52.5 are exact. The `Weight.pounds` doc comment warns
   about this.
5. **Rounding** maps `FloatingPointRoundingRule` onto `NSDecimalRound`: `.plain` is half away from
   zero; `towardZero` and `awayFromZero` pick `.up` or `.down` by sign. Every rule is covered by the
   table tests.
6. **`Duration` is natively `Codable`** (checked with sosumi), so the brief's "seconds wrapper if
   needed" is not needed. It encodes as `[high, low]` attosecond words.
7. **`WeekCalendar`, other points:**
   - The internal calendar is Gregorian, with `firstWeekday` set to `weekStart` (the Settings
     override) and `minimumDaysInFirstWeek` set to 4, so `isoWeekKey` is the ISO week when the week
     starts on Monday.
   - `weekIndex` floors, so dates before the block are negative.
8. **`SessionBuilder` derives child IDs.** The brief's signature has no ID source, and standards §4
   forbid calling `UUID()`. Exercise and set IDs are UUIDv8 values derived from the workout ID with
   SplitMix64. They are deterministic, distinct, and can never equal a random v4 ID.
9. **PR rules (decision #3, spec question 1):**
   - No PR without a comparable prior record. The first session of an exercise, or a rep count
     with no history at or above it, is a baseline. The orchestrator confirmed this rule and the
     `PersonalRecords.detect` doc comment states it.
   - At most one e1RM PR and one weight PR are reported per exercise ID (both may fire). The weight
     PR is the heaviest set that beat its record.
   - Only done `.working` and `.added` sets count. `achievedAt` is `now`.
10. **Decision #18 skipped weeks.** Two helpers implement this:
    `WeekCalendar.skippedWeeks(before:trainedWeeks:weekCount:)` and
    `MissTracking.recordSkippedWeek(_:in:)`. A skipped *deload* week is not a miss (decision #5).
11. **`TimeEstimate` (decision #14)** treats each superset block as `max(sets)` working rounds, plus
    one drop round when any member has a drop set. It rests once per round for the longest member
    rest, then rounds half up to whole minutes.
12. **Validation on decode.** `Slot`, `Program`, `Reps`, `RPE`, `RestDuration`, `PlateInventory`,
    `CivilDate`, `Weight` and `Volume` have custom decoders that re-run construction or validation.
13. **`RPE` is stored as half points.** This makes `8` and `8.0` the same value with the same hash.
14. **Typed throws** are used on `Slot.init`, `Program.init` and `SessionBuilder.build`.

## Deviations from the brief

1. **Typed IDs have no `= UUID()` default** (standards §4). `ExerciseID(uuid)` reads the same as
   before. All IDs conform to a public `TypedIdentifier` protocol, which encodes them as a bare
   UUID string.
2. **`Slot.init` takes raw `rpe: Decimal` and `restSeconds: Int`**, so criterion 13's "rpe 4.75"
   and "rest 100" cases can be thrown. Extra error cases: `dropSetsOutOfRange`,
   `negativeStartLoad` (rule 6) and `nonPositiveStep`.
3. **`PlateMath.Breakdown.perSide` is `[PlateMath.PlateCount]`**, not a tuple array.
   - Why: tuples aren't `Hashable`.
   - Call sites: `.plate` and `.count` read the same.
   - Placement: `PlateCount` is at `PlateMath` level because of SwiftLint's nesting limit.
   - Addition: `Breakdown.remainder` is exact per-side leftover.
4. **`ReceiptRow.actual` is `[String]`**, one chip per run. This matches spec §6.1's `actual[]`, and
   the prototype renders chips.
5. **`WorkoutState.doneSets`, `totalSets` and `volume` are computed properties** (never stale, not
   encoded).
6. **`WorkoutState.autoRest` was added**, snapshotted from settings. F04's rule 3 reads it.
7. **`WorkoutEventStore` lives in `Protocols/WorkoutEventStore.swift`**, the file F04 replaces.
8. **Two inline SwiftLint suppressions**, despite the DoD's "no new lint suppressions". Both are
   justified inline; the alternative is a `.swiftlint.yml` change outside my Touches.
   - `identifier_name` on `case lb, kg`: the brief names the cases.
   - `function_parameter_count` on the brief's 9-parameter `SessionBuilder.build`.
9. **Tags, fixtures and the seeded RNG live in `LedgerDomainTests/Support/`**, not
   `LedgerTestSupport` (F00 notes #6).
10. **`Settings.default.weekStart` is `.monday`.** The app seeds it from `Weekday.first(of:)`
    (decision #15).
11. **Plate inventory lists sizes, each with unlimited pairs** (rule 38). The list is normalised to
    unique, positive and descending. `perSide_neverExceedsInventoryCount` asserts that only
    inventory plates are used, that the plates plus the remainder make up exactly the per-side
    load, and that the remainder is below the smallest plate.
12. **`ModuleBoundaryTests` reads `Sources/LedgerDomain/**` via `#filePath`** (criterion 14). This
    is the only file-system read, and it is read-only.
13. **`Program.init` sorts weeks by index** before validating.
14. **ADR-007 supersedes the sketch** (authorised by Pete).
    - `Weight.grams` / `init(grams:)` and `Volume.gramReps` are `Decimal`.
    - `pounds(_:)` and `scaled(by:)` no longer round.
    - `Program.startDate` and `WeekCalendar.init(startDate:)` take a `CivilDate`.

    The F02 brief, architecture §5, product decision #9 and engineering-standards §5 are amended
    to match.
15. **Public API added beyond the sketch:**
    - Units: `Weight.advanced(bySteps:of:)`, `Weight.wholeValue(in:)`, `Reps(clamping:)`,
      `RPE.label`, `RestDuration.defaultRest`, `RestDuration.duration`, `Volume(weight:reps:)`,
      all units `Comparable`.
    - Weekday: `Weekday(calendarWeekday:)`, `.calendarWeekday`, `.first(of:)`.
    - Model: `CivilDate` (with `init?(year:month:day:)`, `init(_:in:)`, `init?(iso8601:)`,
      `adding(days:)`, `days(since:)`, `daysSinceEpoch`, `weekday`, `startOfDay(in:)`);
      `Exercise.startLoad(in:)`, `Program.week(at:)`, `ReceiptRow(exercise:units:)`.
    - Rules: `SessionBuilder.resumable(…)` (rule 17); `WeekCalendar.civilDate(of:)`,
      `firstDayOfWeek(containing:)`, `week(containing:)`, `scheduledDay(on:in:)`,
      `isBlockComplete(_:on:)` and `skippedWeeks(…)`; `MissTracking.recordSkippedWeek(_:in:)`;
      `OneRepMax.maximumReps`; `TimeEstimate.secondsPerSet`.

## Brief and spec disagreements (flagged, not bent)

- **`RestDuration.label` for 90 s** is "1:30" (rule 39), not the brief's original "90s". The brief
  was corrected in `76ebbdb`.
- **Criterion 7 (219 vs 218).**
  - Arithmetic: 195 lb = 88,450.51215 g; × 36 / 32 = 99,506.826… → 99,507 g (219.38 lb), which
    presents as **219**.
  - The spec's "218" is a prototype placeholder.
- **Criterion 9.**
  - 5×(42+150) + 3×(42+90) + 4×(42+90) + 3×(42+75) + 3×(42+60) = 2541 s → **42 min**.
  - Superset: 6 × 42 + 3 × 90 = 522 s → **9 min**.
  - The spec's "~40 min" and "~52 min" strings are hard-coded, not formula output.
- **Criterion 12.**
  - 200 × 5 → exact 102,058.28325 g → the e1RM estimate is **102,058 g**, presented as 225 lb.
  - Under ADR-007 it no longer equals `.pounds(225)`, which is exact.
- **ADR-007 storage range.** The revision brief gave "~922 t per value" for an `Int64` count of
  10⁻⁷ g. The arithmetic is 9,223,372,036,854,775,807 × 10⁻⁷ g = 922,337,203,685 g ≈
  **922,337 t (≈ 922 kilotonnes)**, so the ADR states that figure. It also records that a lifetime
  volume aggregate (50 t/week × 50 years = 1.3 × 10¹⁸ units) has only about 7× headroom, which is
  why aggregates must be overflow-safe.

## Known limitations

- **PR size.** Product code is about 2,400 lines (about 1,750 without comments and blank lines),
  well over the §10 budget of 500. Natural seams if the orchestrator wants to split:
  1. Identifiers + Units.
  2. Model + Errors + Protocols.
  3. Rules.
- `Decimal` has 38 significant digits. Realistic weights use fewer than 20, and domain call chains
  are shallow (one scale, one round).
- Unrounded intermediates are not always whole 10⁻⁷ g (e.g. × 0.85 before rounding; 0.125 lb).
  F05's storage boundary should reject rather than round them (ADR-007).
- `CivilDate(_:in:)` uses Foundation's Gregorian calendar, which is Julian before 1582-10-15, so
  instants before that map to Julian days. `CivilDate`'s own arithmetic is proleptic Gregorian.
- Model properties are `var` by design (orchestrator decision on spec question 7). `Slot`'s doc
  comment says validation happens only at `init` and decode, so editors must rebuild through
  `init`.
- Domain strings are the spec's English/US forms; localisation is a later feature concern.
- `LEDGER_PROPERTY_SEED_COUNT` must be set in the test process environment; it is read at test
  discovery.

## Revision 1 (2026-09-27): ADR-007 and the adversarial findings

### What changed

- **Code:**
  - `Weight` and `Volume` became exact `Decimal` values, with decimal-text Codable.
  - `Units.denominating`, `Weight.quanta(in:)` and `Weight.init(quanta:in:)` were deleted.
  - `PlateMath` works on exact weights.
  - `OneRepMax` rounds only the estimate.
  - `CivilDate` was added, `Program.startDate` became a `CivilDate`, and `WeekCalendar` was
    rewritten on civil days.
  - Doc comments for `Slot` (spec question 7) and `PersonalRecords` (question 1) were updated.
- **Docs:**
  - New: `docs/adr/ADR-007-exact-weights-and-civil-program-start.md`.
  - Amended: `docs/product-decisions.md` #9 (and #18's start date), `docs/architecture.md` §5
    (Weight/CivilDate sketch, Program row, WeekCalendar bullet), and the `Weight` line in
    `docs/engineering-standards.md` §5.
  - F02 brief: spec refs, the Weight/Volume/Program/CivilDate/WeekCalendar sketches, criteria 1
    and 12, and the non-functional line.
  - F05 brief: a one-line ADR-007 pointer in its schema section.
  - A grep of `docs/` and `tasks/` for "grams (Int)" / "Int grams" leaves only deliberate
    historical references.
- **My tests:**
  - Rewrote `WeightTests` for the exact contract, keeping the catalogue names. New tests:
    `equality_isNumeric_hashesAgree`, `arithmetic_noDrift`, `codable_exactDecimalText`,
    `roundedToStep_exactTiesAndMultiples` (bugs A and C).
  - Updated `OneRepMaxTests`, `PersonalRecordsTests`, `VolumeTests` (plus `sum_isExact_noDrift`
    for question 3), `PlateMathTests`, `PlateInventoryTests`, `ProgramTests` and
    `WeekCalendarTests`. The last gains `missingMidnight_onlyThatDayStartsLate` and
    `civilDate_isZoneDayOfTheInstant` (question 5).
  - Added the `CivilDateTests` suite, including a property test against Foundation's calendar.

### Findings resolved

| Finding | Resolution | Proof |
|---|---|---|
| A: 11 kg step read as 24.25 lb | No unit inference; exact division | `WeightAdversarialTests.roundedToStep_everyRule_matchesSwiftSemantics` (33 kg / 11 kg rows) and `WeightTests.roundedToStep_exactTiesAndMultiples` pass |
| B: boundaries at 01:00 after a skipped midnight | Civil-day boundaries | `WeekCalendarAdversarialTests.dst_santiagoMissingMidnight`, `.dst_havanaStartWithoutMidnight`, `.dst_cairoMissingMidnight_statsWeek`, and `WeekCalendarPropertyAdversarialTests.weeks_agreeWithCalendarDays` (pinned seeds 4664308, 7823989, 9708711, 12535794, 15212416) pass at 200 and 2,000 seeds |
| C: 1.25 lb ties decided by gram noise | Exact × 0.85, then one rounding | `ProgressionRulesDeloadAdversarialTests.deload_poundTies_roundAwayFromZero` (212.5 / 1.25 → 181.25), `SessionBuilderEdgeAdversarialTests.build_dropRow_quarterStepTie`, and `ProgressionRulesPropertyAdversarialTests.prescribe_matchesSpecOracle` (pinned seed 3587324) pass |
| Q1: first PR at a rep count | Baseline rule kept; doc comment states it | `PersonalRecords.detect` doc |
| Q2: `+` drift | `+` is exact | `WeightTests.arithmetic_noDrift`: 185 + 6 × 2.5 lb == `.pounds(200)` |
| Q3: volume drift | `Volume` is exact | `VolumeTests.sum_isExact_noDrift`: 1,000 × 185 lb → "185,000" |
| Q4: nil cursor on an empty day | Kept (orchestrator) | `SessionBuilderTests.build_emptyDay_hasNoCursor` |
| Q5: travel moves the block | `CivilDate` start | `WeekCalendarTests.civilDate_isZoneDayOfTheInstant` |
| Q6: brief signature changes | For the reviewer | Deviations 1, 3, 4 above |
| Q7: `var` ranged fields | Kept by design; `Slot` doc comment says rebuild through `init` | `Slot` doc |

### Adversarial tests changed

All 209 tester tests are kept, and none is skipped or weakened on unchanged behaviour. A–C were
fixed in code, so their 8 failing tests needed no edits and now pass.

**Compile-only adaptations** (new types; assertion semantics unchanged):

- `AdversarialSupport.swift`: added `Adversarial.startDay`, the civil date of `Adversarial.start`
  in the fixture calendar.
- `startDate: Adversarial.start` became `startDate: Adversarial.startDay` in
  `ProgramAdversarialTests` (helper) and `SessionBuilderEdgeAdversarialTests` (3 sites).
- A `Date` start became `CivilDate(start, in: calendar)` in:
  - `WeekCalendarAdversarialTests.weeks(...)` (the shared helper; the instant's civil day in the
    test's own zone);
  - `TrapAdversarialTests.skippedWeeks_beforeStart_doesNotTrap`;
  - `WeekCalendarStatsAdversarialTests.nonGregorianCalendar_usesTimeZoneOnly` (via `startDay`);
  - `WeekCalendarPropertyAdversarialTests.weeks_agreeWithCalendarDays` and
    `.isoWeekKey_matchesISOCalendar`.
- `Int` → `Decimal` wraps in:
  - `CodableAdversarialTests` (`Volume(gramReps: Int.max)` round-trip);
  - `ProgressionRulesDeloadAdversarialTests.deload_kilograms_roundToKiloStep`;
  - `PlateMathAdversarialTests.perSide_standardKilos_isExact`;
  - `OneRepMaxAdversarialTests.brzycki_kiloTable`, and `OneRepMaxPropertyAdversarialTests`'
    `.brzycki_matchesExactFormula` and `.brzycki_monotonicInReps`;
  - `WeightAdversarialTests.codable_roundTrip_extremes`;
  - `WeightPropertyAdversarialTests`: `kilogramsRoundTrip_grams_isExact`, `rounded_isIdempotent`,
    `rounded_landsOnStepLattice`, `rounded_isMonotonic`, `rounded_negation_isSymmetric`,
    `formatted_anyWeight_isCloseAndShort` and `comparable_agreesWithGrams`.

**Contracts superseded by ADR-007** (assertion changed; same function name):

| Test | Change | Reason |
|---|---|---|
| `WeightAdversarialTests.pounds185_convertsAndFormats_matchesCriterion1` | `grams == 83915` → `== 83914.58845` | Criterion 1 amended: weights are exact |
| `WeightAdversarialTests.pounds_nearestGram_table` | Nearest-gram `Int` expectations → exact gram strings (e.g. 1 lb = 453.59237, 242.5 lb = 109,996.149725, 0.001 lb = 0.45359237); display name reworded | No rounding on construction |
| `WeightAdversarialTests.kilograms_nearestGram_tiesAwayFromZero` | Half-gram ties → exact sub-gram values (0.0025 kg = 2.5 g, …); display name reworded | No rounding on construction |
| `WeightAdversarialTests.scaled_exactDecimal_nearestGram` | 104,938,271 → 104,938,270.65 g and 109,883 → 109,882.7516325 g; added `== pounds("242.25")`; display name reworded | `scaled(by:)` is exact; only `rounded(toStep:)` rounds |
| `WeightAdversarialTests.arithmetic_andOrdering_inGrams` | `pounds("185") == Weight(grams: 83915)` → `Weight(grams: 83914.58845)` | Exact weights |
| `WeightPropertyAdversarialTests.rounded_respectsBounds` | Slack 6 g → 0 (a **stronger** assertion) | The slack existed only for the removed 0.01 lb quantum |
| `OneRepMaxAdversarialTests.brzycki_200x5_is225` | `estimate == pounds("225")` → `== Weight(grams: 102_058)`; `wholeValue == 225` kept | e1RM rounds to the nearest gram; exact 225 lb (102,058.28325 g) is not a whole gram |
| `OneRepMaxAdversarialTests.brzycki_oneRepAndZero` | 1 rep of 185 lb `== pounds("185")` → `== Weight(grams: 83915)`, plus `wholeValue == 185` | Same rounding rule applied to a 1-rep estimate |
| `PersonalRecordsAdversarialTests.detect_criterion12_bothKinds` | `e1RM("200", 5) == pounds("225")` → `== Weight(grams: 102_058)`, plus `wholeValue == 225` | Same as above; the exact-set comparison of both records is unchanged and passes |
| `VolumeAdversarialTests.volume_ofSet_isGramsTimesReps` | `gramReps == 83915 * 5` → `== 83914.58845 * 5` | `Volume` is exact |

## Documentation lookups

- sosumi: `NSDecimalRound(_:_:_:_:)`, `NSDecimalNumber.RoundingMode`, `Decimal`, `Duration`
  (conforms to `Codable`).
- Probed on the pinned toolchain (Swift 6.3.3):
  - `Decimal`: literal exactness; numeric `==` and hash (1 vs 1.00, 0.1 + 0.2 vs 0.3); exact tie
    division (180.625 / 1.25 lb in grams = 144.5); exact JSON number round-trip; description
    without exponent notation.
  - `Duration` JSON shape; `CodingKeyRepresentable` dictionaries; `Calendar` `firstWeekday` per
    locale.

## How to verify

```sh
cd <worktree>
scripts/check.sh --fast                                   # format, strict lint, graph, tests
LEDGER_PROPERTY_SEED_COUNT=2000 swift test --package-path LedgerKit --filter LedgerDomainTests
# coverage: see "Verification" above
```

The full `scripts/check.sh` (simulator builds and test plans) needs the Xcode project, which is
still F00's pending human step.
