# F02 — implementation notes

Branch `feat/F02-domain-core` (based on `00a504b`). Implementer pass, 2026-09-26.

## What was built

`LedgerDomain` now holds every F02 type and rule, importing Foundation only:

- `Identifiers.swift`: nine typed IDs sharing a `TypedIdentifier` protocol, plus deterministic
  child-ID derivation (`WorkoutExerciseID.derived`, `SetID.derived`).
- `Units/`: `Units`, `Weight`, `Reps`, `RPE`, `RestDuration`, `Volume`, and `NumberText`
  (internal, locale-free number text plus `Decimal` rounding).
- `Model/`: every model struct and enum in the brief's sketch.
- `Rules/`: `ProgressionRules`, `SessionBuilder`, `SupersetRounds`, `OneRepMax`,
  `PersonalRecords`, `PlateMath`, `TimeEstimate`, `WeekCalendar` (+ `WeekKey`), `MissTracking`.
- `Protocols/`: `ExerciseRepository`, `ProgramRepository`, `WorkoutRepository`,
  `SettingsRepository`, `StatsQueries`, plus the empty `HealthStore`, `LiveWorkoutTransport`,
  `CompanionTransport` and a reserved `WorkoutEventStore`.
- `Errors.swift`: `ProgramValidationError`, `SlotValidationError`, `SessionBuilderError`.

The placeholder `LedgerDomainModule` and its test are deleted. `Resources/exercises.json` was
not touched.

## Verification

| Check | Result |
|---|---|
| `scripts/check.sh --fast` (format, strict lint, package graph, `swift test` for Domain + Persistence) | **OK**: 150 tests in 29 suites (148 domain tests in 27 suites, plus F00's 2 persistence tests) |
| LedgerDomain line coverage | **98.91 %** (1192 lines, 13 missed) |

Coverage commands, run from the worktree root:

```sh
swift test --package-path LedgerKit --filter LedgerDomainTests --enable-code-coverage
BIN=$(swift build --package-path LedgerKit --show-bin-path)
xcrun llvm-cov report "$BIN/LedgerKitPackageTests.xctest/Contents/MacOS/LedgerKitPackageTests" \
  -instr-profile="$BIN/codecov/default.profdata" LedgerKit/Sources/LedgerDomain
# TOTAL … Lines 1192, Missed 13, Cover 98.91%
```

All 13 missed lines are the autoclosures of `??` fallbacks that cannot fire (for example
`Weekday(calendarWeekday:) ?? .monday` on `Calendar.firstWeekday`, or `.max() ?? 0` on a
non-empty group). `llvm-cov report -show-functions` lists every one as an `…Xefu_` autoclosure.

Property tests read `LEDGER_PROPERTY_SEED_COUNT` (default 200) and run one parameterized case per
seed through a SplitMix64 `SeededGenerator`. `LEDGER_PROPERTY_SEED_COUNT=2000 swift test …` runs
the nightly count.

## Acceptance criteria → tests

| # | Test(s) |
|---|---|
| 1 | `WeightTests.pounds_toGrams_exact` |
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

Every test name that testing-strategy §2.1 lists for F02's suites exists under that exact name
(checked by grep). None of the test names carry a `test` prefix.

## Decisions

1. **Exact pound arithmetic through unit lattices.** A pound weight is not a whole number of
   grams, so doing the arithmetic in grams breaks the spec in three places:
   - Criterion 2's tie: 242.5 lb = 109 995 g, and 109 995 / 2 268 = 48.4999, which rounds to
     240 instead of 245.
   - Drift: 50 lb + 20 × 2.5 lb = 45 360 g, but `.pounds(100)` = 45 359 g. That gram would later
     make "100 lb" look like a PR over "100 lb".
   - Plate math: 185 lb gives 31 751.5 g per side, and 45 + 25 lb = 31 752 g, so a greedy fill in
     grams misses the 25.

   So `rounded(toStep:)`, `advanced(bySteps:of:)` and `PlateMath` work in whole *quanta* of the
   step's unit (lb: 0.01 lb ≈ 4.54 g, which maps one-to-one onto grams; kg: 1 g) and convert back
   once. The unit comes from `Units.denominating(_:)`: a weight that is a whole number of quarter
   pounds is a pound weight, anything else is a kilogram weight. This keeps the brief's
   call-site-free signature (`rounded(toStep: .pounds(5))`). I checked the rule exhaustively:
   every 0.25 lb multiple up to 250 lb reads as lb, and every 0.25 kg multiple up to 60 kg reads as
   kg, **except 11 kg** (= 24.25 lb to the gram; it is then computed 0.4 g off). The test
   `WeightTests.denominating_standardLattices` pins 0.25–100 lb, 0.25–60 kg and the 11 kg case.
   As a result, every prescribed pound load equals `Weight.pounds(x)`, e.g. 250 + 7 × 5 lb ==
   `.pounds(285)`.
2. **Formatting is locale-free and hand-rolled** (`NumberText`), following the spec's own formats:
   '.' as the decimal point, ',' as the thousands separator, `×`, `·`, `—`. No `Locale`,
   `NumberFormatter` or `FormatStyle` is used, so output is identical on any host.
   - **Weights**: a value that is a whole number of quarter units (every plate and step: 1.25,
     2.5, 52.5, 46.25) prints exactly with trailing zeros dropped. Anything else prints to one
     decimal. This rule is the only one that satisfies criterion 1 ("83.9" for 83.915 kg) and
     criterion 6's "1.25" plate together.
   - **Volume**: `formatted` gives whole units with thousands separators; `compact` always gives
     one decimal plus "k", like JS `toFixed(1)` ("24.0k").
   - **`LastPerformance.line`**: day and month come from a Gregorian calendar in the passed
     calendar's time zone. The month name comes from a fixed English table ("Aug"), as in the spec.
3. **Decimal constants are built exactly.** 453.59237 and 0.85 are built from integers. On this
   toolchain a `Decimal` float literal `453.59237` evaluates to `453.5923699999999488` (probed),
   while dyadic literals such as 242.25 and 52.5 are exact. The `Weight.pounds` doc comment warns
   about this.
4. **Rounding** maps `FloatingPointRoundingRule` onto `NSDecimalRound`: `.plain` is half away from
   zero; `towardZero` and `awayFromZero` pick `.up` or `.down` by sign. Every rule is covered by the
   table test.
5. **`Duration` is natively `Codable`** (checked with sosumi), so the brief's "seconds wrapper if
   needed" is not needed. It encodes as `[high, low]` attosecond words. `WorkoutState` and
   `WorkoutSummary` round-trip in tests.
6. **`WeekCalendar`**:
   - All arithmetic is in calendar days, in the passed calendar's time zone. DST weeks are 167 or
     169 hours long (tested in Europe/Berlin and America/New_York; several rows would fail with
     168-hour weeks).
   - The internal calendar is Gregorian, with `firstWeekday` set to `weekStart` (the Settings
     override) and `minimumDaysInFirstWeek` set to 4, so `isoWeekKey` is the ISO week when the week
     starts on Monday.
   - `weekIndex` floors, so dates before the block are negative.
   - `startDate` is normalised to the start of its day but not snapped to `weekStart`.
7. **`SessionBuilder` derives child IDs.** The brief's signature has no ID source, and
   standards §4 forbid calling `UUID()`. Exercise and set IDs are UUIDv8 values derived from the
   workout ID with SplitMix64. They are deterministic, distinct, and can never equal a random v4 ID.
   Building is therefore a pure function (tested).
8. **PR rules (decision #3):**
   - A PR needs history to beat: the first session of an exercise, or a rep count with no history
     at or above it, is a baseline and produces no PR. This avoids "10 PRs" on day one.
   - At most one e1RM PR and one weight PR are reported per exercise ID (both may fire). The
     weight PR is the heaviest set that beat its record.
   - Only done `.working` and `.added` sets count. `achievedAt` is `now`.
9. **Decision #18 skipped weeks.** Two helpers implement this:
   `WeekCalendar.skippedWeeks(before:trainedWeeks:weekCount:)` and
   `MissTracking.recordSkippedWeek(_:in:)`. A skipped *deload* week is not recorded as a miss,
   because decision #5 says deload weeks never count as misses. This resolves a tension between
   #18 and #5.
10. **`TimeEstimate` (decision #14)** treats each superset block as `max(sets)` working rounds, plus
    one drop round when any member has a drop set (the same rounds as `SupersetRounds`). It rests
    once per round for the longest member rest, then rounds half up to whole minutes.
11. **Validation on decode.** `Slot`, `Program`, `Reps`, `RPE`, `RestDuration` and `PlateInventory`
    have custom decoders that re-run construction, so a tampered payload throws.
12. **`RPE` is stored as half points.** This makes `8` and `8.0` the same value with the same hash.
13. **Typed throws** (`throws(SlotValidationError)` etc.) are used on `Slot.init`, `Program.init`
    and `SessionBuilder.build`.

## Deviations from the brief

1. **Typed IDs have no `= UUID()` default.** Standards §4 require injected UUIDs, and a silent
   default makes non-deterministic IDs the easy path. `ExerciseID(uuid)` reads the same as before.
   All IDs conform to a small public `TypedIdentifier` protocol, which encodes them as a bare UUID
   string.
2. **`Slot.init` takes raw `rpe: Decimal` and `restSeconds: Int`.** Criterion 13 expects
   `SlotValidationError` cases for "rpe 4.75" and "rest 100", which a typed `RPE`/`RestDuration`
   argument could never carry. The stored properties are still `RPE` and `RestDuration`. The brief
   wrote the parameter list as `...`. Extra error cases: `dropSetsOutOfRange`, `negativeStartLoad`
   (rule 6) and `nonPositiveStep`.
3. **`PlateMath.Breakdown.perSide` is `[PlateMath.PlateCount]`**, not `[(plate:, count:)]`.
   - Why: an array of tuples is not `Hashable`, so the sketch does not compile.
   - Call sites: `.plate` and `.count` read the same; tuple destructuring does not.
   - Placement: `PlateCount` sits at `PlateMath` level because SwiftLint allows only one level of
     type nesting.
   - Addition: `Breakdown.remainder` is the per-side weight the plates could not make up (the
     prototype silently drops it).
4. **`ReceiptRow.actual` is `[String]`**, one chip per run, not a single `String`. Spec §6.1 names it
   `actual[]`, and the prototype renders each run as its own chip. `["—"]` means no sets were done.
5. **`WorkoutState.doneSets`, `totalSets` and `volume` are computed properties**, not stored ones,
   so they can never go stale as F04 mutates sets. They read the same at call sites and are not
   encoded.
6. **`WorkoutState.autoRest` was added** (default `true`, taken from `settings.autoRest` in
   `SessionBuilder`). F04's rule 3 reads `WorkoutState.autoRest`.
7. **`WorkoutEventStore` lives in `Protocols/WorkoutEventStore.swift`**, not `Repositories.swift`.
   F04's Touches list that exact file, so F04 overwrites the placeholder without a merge conflict.
8. **Two inline SwiftLint suppressions**, despite the DoD's "no new lint suppressions". Both carry
   a justification. The alternative is a `.swiftlint.yml` change, which is outside my Touches.
   - `identifier_name` on `case lb, kg`: the brief names the cases, and SwiftLint's minimum name
     length is 3.
   - `function_parameter_count` on `SessionBuilder.build`: the brief's signature has 9 parameters,
     and the limit is 5.

   The orchestrator may prefer a config exclusion instead.
9. **Tags, fixtures and the seeded RNG live in `LedgerKit/Tests/LedgerDomainTests/Support/`**, not
   `LedgerTestSupport`, per F00 notes #6: feature targets link `LedgerTestSupport`, so these would
   pull swift-testing into app code. This covers `Tags.swift` (`.domain`, `.property`),
   `Fixtures*.swift` and `SeededGenerator.swift` (with `PropertySeed`).
10. **`Settings.default.weekStart` is `.monday`.** Decision #15 wants the locale's first weekday,
    but the domain cannot read the locale. The app seeds it with `Weekday.first(of: calendar)` on
    first launch (F07/F08).
11. **Plate inventory has no per-plate counts.** The brief has `plates: [Weight]` and rule 38 fills
    greedily without limits, so plates are sizes, each available in unlimited pairs. The list is
    normalised to unique, positive and descending. The catalogue's property
    `perSide_neverExceedsInventoryCount` therefore asserts that only inventory plates are used,
    counts are ≥ 1, the plates never exceed the per-side load, and the leftover is below the
    smallest plate.
12. **`ModuleBoundaryTests` reads `Sources/LedgerDomain/**` via `#filePath`** (criterion 14's "grep
    test"). This is the only file-system read in the domain tests. It is read-only and stays inside
    the repository, the same way snapshot tests locate their references.
13. **`Program.init` sorts weeks by index** before checking that the indices are 0…n − 1.
14. **Public API added beyond the sketch**, each needed by a rule, a test in the §2.1 catalogue, or
    a downstream brief:
    - Units: `Weight.advanced(bySteps:of:)`, `Weight.wholeValue(in:)`, `Reps(clamping:)`,
      `RPE.label`, `RestDuration.defaultRest`, `RestDuration.duration`, `Volume(weight:reps:)`,
      all units `Comparable`.
    - Weekday: `Weekday(calendarWeekday:)`, `.calendarWeekday`, `.first(of:)`.
    - Model: `Exercise.startLoad(in:)`, `Program.week(at:)`, `ReceiptRow(exercise:units:)`.
    - Rules: `SessionBuilder.resumable(_:program:weekIndex:day:)` for rule 17 /
      `build_resumesSameWeekAndDay`; `WeekCalendar.week(containing:)`, `scheduledDay(on:in:)`,
      `isBlockComplete(_:on:)` and `skippedWeeks(…)`; `MissTracking.recordSkippedWeek(_:in:)`;
      `OneRepMax.maximumReps`; `TimeEstimate.secondsPerSet`.

## Brief and spec disagreements (flagged, not bent)

- **`RestDuration.label` for 90 s.** The brief's comment says `"90s"`, but rule 39 and the
  prototype's `restLbl` give **"1:30"**: 90 is not under 60 and not a whole minute. I followed
  rule 39. The label tests cover 30…300.
- **Criterion 7 (219 vs 218).**
  - Arithmetic: 195 lb = 88 451 g; × 36 / 32 = 99 507.375 → 99 507 g = 219.375 lb, which presents
    as **219**.
  - The spec's "218" and the chart's "+22 lb" are prototype placeholders.
- **Criterion 9 (5 straight slots).**
  - Formula: 5×(42+150) + 3×(42+90) + 4×(42+90) + 3×(42+75) + 3×(42+60) = 2541 s = 42.35 min →
    **42**.
  - The spec's hard-coded strings are not reproduced by any formula: Upper A "~40 min" (39 by
    decision #14 with its superset; 37 by the builder formula; 42 by the Today formula) and the v2
    "~52 min". F11 already expects this.
  - The superset case: 6 × 42 + 3 × 90 = 522 s → **9 min**.
- **Criterion 4 matches the formula** (285 × 0.85 = 242.25 → 240), as does criterion 12
  (200 × 5 → 225 lb exactly equal to `.pounds(225)`).

## Known limitations

- **PR size.** Product code is about 2,200 lines, or about 1,600 without comments and blank lines.
  That is well over engineering-standards §10's 500-line PR budget. The brief's scope (every model
  and rule in one feature) makes this unavoidable. If the orchestrator wants to split it, there are
  natural seams:
  1. Identifiers + Units.
  2. Model + Errors + Protocols.
  3. Rules.

- Rounding ties are exact only for weights that are whole hundredths of a pound. A tie at a third
  decimal (e.g. 100.625 lb on a 1.25 lb step) cannot be recovered from grams, since 0.001 lb < 1 g.
- Model properties are `var`, as in the brief, so a caller can mutate a slot outside its ranges.
  Validation runs at `init` and decode only; editors should rebuild through `init`.
- Domain strings are the spec's English/US forms. Localising them (decimal comma, month names) is a
  later feature concern, and the String Catalog applies only in features.
- `WeekCalendar` always computes in Gregorian (week-key years included), whatever calendar
  identifier the caller passes.
- The property-seed list is read at test discovery, so `LEDGER_PROPERTY_SEED_COUNT` must be set in
  the environment of the test process.

## Documentation lookups

- sosumi: `NSDecimalRound(_:_:_:_:)`, `NSDecimalNumber.RoundingMode` (plain = half away from zero;
  up/down are toward ±∞), `Decimal`, `Duration` (conforms to `Codable`).
- Probed on the pinned toolchain (Swift 6.3.3): `Decimal` literal exactness, `Duration` JSON shape,
  protocol-extension `Codable` taking precedence over synthesis for the ID types,
  `CodingKeyRepresentable` dictionary encoding, `Calendar` `firstWeekday` for en_US (1) and
  de_DE (2), and day arithmetic across the Berlin DST change.

## How to verify

```sh
cd <worktree>
scripts/check.sh --fast                                   # format, strict lint, graph, tests
swift test --package-path LedgerKit --filter LedgerDomainTests
LEDGER_PROPERTY_SEED_COUNT=2000 swift test --package-path LedgerKit --filter LedgerDomainTests
# coverage: see "Verification" above
```

The full `scripts/check.sh` (simulator builds and test plans) needs the Xcode project, which is
still F00's pending human step. The orchestrator runs it after rebasing.
