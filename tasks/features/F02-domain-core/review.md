# F02 — Review

Reviewer pass on `feat/F02-domain-core` @ `eb52f60`. The diff reviewed is `git diff 00a504b...HEAD`
(5 commits, 110 files). The reviewer is a fresh agent and did not write this code.

## Verdict

**Approved: 0 Blocking, 4 Should fix, 9 Nits.**

- **Exact weights (ADR-007).** Correct and well tested. Every rounding rule matches Swift's
  semantics, and equality and hashing are numeric. I verified this on the toolchain:
  `Decimal` stores equal values in one compact form. No lattice or unit-inference code is left.
- **`CivilDate` and `WeekCalendar`.** DST and travel cases are handled correctly.
- **Should fix, before or right after merge.** All four are cheap:
  - two known low items (D, Q8);
  - one latent consistency bug in `SessionBuilder`;
  - one lint suppression that belongs in `.swiftlint.yml`.

## Gate and checks run

| Check | Result |
|---|---|
| `scripts/check.sh --fast` | **OK**. Format: 0/144 files need formatting. `swiftlint --strict` passes and the package graph matches. `swift test` (Domain + Persistence): **413 tests in 67 suites pass** in 0.35 s. |
| Clean `swift build --target LedgerDomain` | Builds with 0 warnings. |
| Host line coverage for `LedgerDomain` (`llvm-cov`) | **98.87 %** (1,326 lines, 15 missed), matching the implementation notes; ≥ 95 % required. |
| Full `scripts/check.sh` (iOS/watchOS plans, coverage gate) | **Cannot run on this base.** `00a504b` has no `Ledger.xcodeproj`, which arrived in F00's `ff02613`. **Merge precondition:** rebase F02 onto F00's final tip (`7847bb0` plus the TestPlans/`check.sh` edits still uncommitted in the main checkout), then run the full gate. This is not a code finding. |
| Probes (compiled against the module sources in the scratchpad; no repo edits) | `Decimal` equality and hashing, 1RM rounding, the `CivilDate` range, and formatting edges. Results are cited in the findings below. |

## Findings

### Blocking

None.

### Should fix

**S1. `CivilDate` can leave 0001…9999 and produce a value that encodes but will not decode (tester Q8).**
- **Where:**
  - `LedgerKit/Sources/LedgerDomain/Model/CivilDate.swift:41` (the private `init(daysSinceEpoch:)` skips validation);
  - `:61` (`adding(days:)`);
  - `:30` (`init(_:in:)` for far-future instants);
  - `:88` (`description` for years ≤ 0);
  - `Rules/WeekCalendar.swift:60` (`7 * index`).
- **What:** I probed each case:
  - `9999-12-31 + 1` encodes `"10000-01-01"`, which fails to decode.
  - `0001-01-01 − 1` encodes `"0000-12-31"`, which fails to decode.
  - `0001-01-01 − 400` prints `"00-1-11-28"`.
  - An instant at 1e12 s gives `"33658-09-26"`, which fails to decode.
  - `bounds(ofWeek:)` with |index| > `Int.max / 7`, and `adding(days:)` near `Int.max`, trap on overflow.
- **Why it matters:**
  - The type documents a 1…9999 invariant, and its public producers break it.
  - A program whose `startDate` crossed the range would persist fine and then be unreadable: F05 stores `"YYYY-MM-DD"` and decodes through `init?(iso8601:)`.
  - None of this is reachable with real training dates, hence Should fix rather than Blocking.
- **Fix (preferred):** make the invariant total at the public producers.
  - `adding(days:) -> CivilDate?`: `nil` outside 0001…9999; use `addingReportingOverflow`.
  - `init(_:in:)` → `init?`.
  - Have `WeekCalendar` work on `Int` day numbers internally, through a private `startOfDay(daysSinceEpoch:in:)`, so its non-optional API is unchanged.
  - Use `multipliedReportingOverflow` in `bounds(ofWeek:)`.
- **Fix (minimal alternative, if the ripple is judged too big for an unreachable case):**
  - `encode(to:)` throws `EncodingError.invalidValue` for years outside 1…9999, so the value fails at write time instead of read time.
  - Document the range on `adding(days:)`.
- Either way, add the tester's Q8 cases as tests.

**S2. `OneRepMax.brzycki` doc says "One rep returns `weight`", but the result is rounded to the gram (tester D).**
- **Where:** `LedgerKit/Sources/LedgerDomain/Rules/OneRepMax.swift:10`.
- **What:** `brzycki(.pounds(185), .one)` is 83,915 g, but `.pounds(185)` is 83,914.58845 g (probed).
- **Why it matters:** the doc comment is the public contract. A caller comparing `brzycki(w, 1) == w`, for example a PR or "true 1RM" display, would be wrong.
- **Fix:** keep the behaviour: every e1RM is whole grams (ADR-007), so e1RM comparisons stay consistent. Do **not** special-case one rep. Reword to: "One rep returns `weight` rounded to the nearest gram." The test `brzycki_oneRep_returnsWeight` already asserts this and its display name already says it; only the source doc is stale.

**S3. `SessionBuilder.build` checks only the day's ID against `program`, then builds from the caller's `day`.**
- **Where:**
  - `LedgerKit/Sources/LedgerDomain/Rules/SessionBuilder.swift:29-33`;
  - pinned by `Tests/LedgerDomainTests/Rules/SessionBuilderTests.swift:79`.
- **What:** a `DayTemplate` value whose slots differ from `program`'s copy (stale or edited) passes the ID guard. The session is then built from those slots. `SessionBuilderTests.swift:79` builds an edited `upperA` against the unedited `program` and expects the edit, so the test encodes the inconsistency.
- **Why it matters:**
  - The session's `slotID`s, targets and set counts can disagree with the program that `MissTracking.update` and `materialize(slotUpdates:)` later write back to.
  - A store that holds `program` (observed) and a separately captured `selectedDay` hits this silently.
  - Spec rule 16 is about template edits not leaking into a *built* session, not about building from a copy that differs from the program.
- **Fix:**
  - Resolve the day from the program: `guard let day = program.days.first(where: { $0.id == day.id }) else { throw .dayNotInProgram(day.id) }`, then use it.
  - Update `SessionBuilderTests.swift:79` to rebuild the program with the edited day.
  - Add a test that a stale `day` copy cannot override the program's slots.
  - The adversarial suites pass fixture days identical to the program's and are unaffected.

**S4. Inline SwiftLint suppressions (implementation deviation 8) vs. DoD "No new lint suppressions".**
- **Where:**
  - `LedgerKit/Sources/LedgerDomain/Units/Units.swift:8` (`identifier_name`);
  - `Rules/SessionBuilder.swift:15` (`function_parameter_count`).
- **`identifier_name`: a config change is better.** `lb` and `kg` are domain vocabulary the brief names. The same violation will recur wherever another module declares `lb`/`kg`, for example a formatter enum or a local `let kg`.
  - Add `identifier_name: { excluded: ["^id$", "^lb$", "^kg$"] }` to `.swiftlint.yml`. `"^id$"` is SwiftLint's own default and must be kept.
  - Delete the inline comment.
  - The orchestrator should approve the one-line edit outside F02's Touches.
- **`function_parameter_count`: keep it inline.**
  - Raising the global threshold (default error 8) would loosen every module.
  - Wrapping the parameters in a struct would change the brief's signature, which F04 and F07 build on.
  - The suppression is targeted and justified, which is what standards §11 asks for. Record an explicit DoD waiver in the PR description, because the DoD box cannot be ticked otherwise.

### Nits

- **N1. `ProgressionRules.prescribe(week:weekIndex:…)` accepts a pair that disagrees** (`Rules/ProgressionRules.swift:20-27, 44`).
  - Deload comes from `week`; advancement and HELD come from `weekIndex`, and nothing checks that `week.index == weekIndex`.
  - `SessionBuilder` always passes a consistent pair. The signature is the brief's, so this is documented rather than wrong.
  - When a later brief touches this, derive the index from `week.index`, or state the precondition in the doc.
- **N2. Validated fields are `public var`** (`Model/Slot.swift:14-34`, `Model/Program.swift:18`, `Model/PlateInventory.swift:10`).
  - A direct mutation (`slot.reps = 35`, `program.weeks.removeLast()`) encodes fine but no longer decodes. This re-raises code-review #1.
  - Q7 settled this "by design", and the `Slot` doc says so.
  - Recommend adding one line to the F05 brief: re-validate through `Slot.init` / `Program.init` before writing. Also make F09's editors rebuild through `init`. That way a bad value fails at save time, not at load time.
- **N3. `DecimalText.parse` silently truncates beyond 38 significant digits** (`Units/NumberText.swift:99-107`).
  - `"1234567890123456789012345678901234567890.5"` decodes as `…890`, losing the `.5`, while the doc says decoding "rejects anything else".
  - The encoder never emits such text, so only a tampered payload is affected.
  - Reject input whose significant-digit count exceeds 38.
- **N4. Unreachable-in-practice `Weight` edges** (`Units/Weight.swift:16, 98-105, 126-129`; `Units/NumberText.swift:19-21`).
  - `Weight(grams: .nan)` is constructible. It encodes as `"NaN"`, which won't decode, and formats as `"0.9"`.
  - `roundedToInt()` goes through `NSDecimalNumber.intValue`, which wraps silently: 10¹⁸ lb formats as `"-844674407370955161.6"`.
  - Suggested fixes:
    - make `encode` throw on NaN;
    - make `formatted` render from `Decimal` digits, or clamp, instead of going through `Int`.
- **N5. `LastPerformance.line` re-implements the date → civil day mapping** (`Model/LastPerformance.swift:23-26`). Use `CivilDate(date, in: calendar)` and read `.month` and `.day`, so there is one conversion path.
- **N6. Small redundancies.**
  - `PlateMath.perSide` re-filters and re-sorts plates the inventory already normalised (`Rules/PlateMath.swift:42`). This is defensive only because `plates` is `var`; `private(set)` would let it go.
  - `SupersetRounds.isLastOfRound` rebuilds every round on each call (`Rules/SupersetRounds.swift:39-41`), which is O(rows²) if F07 asks per row. The row count is small, so there is no action now. If a store renders it per row, compute rounds once.
- **N7. Public API beyond the brief (deviation 15).** It is justified overall. Three trims to consider:
  - `Weight.advanced(bySteps:of:)` (`Units/Weight.swift:80`) is no longer load-bearing now that `+` is exact. Keep it as a readable helper or make it internal.
  - `CivilDate.daysSinceEpoch` (`Model/CivilDate.swift:56`) is an implementation detail; `days(since:)` covers callers.
  - `CivilDate(_:in:)` and `WeekCalendar.civilDate(of:)` are two public paths to the same value.
- **N8. Test hygiene.**
  - `Tests/LedgerDomainTests/Units/WeightTests.swift:255` uses `.kilograms(61.2)`, a non-dyadic float literal. This is exactly the footgun the `Weight.pounds` doc warns about; the row passes only because the result rounds to 60. Use `dec("61.2")`.
  - Consider a SwiftLint custom rule for `LedgerKit/Sources` that flags float literals in `.pounds(` / `.kilograms(` calls.
  - A few test names don't state an expectation (§6 `subject_condition_expectation`): `reps_bounds`, `build_kilograms`, `actual_kilograms`, `codable_roundTrips`.
  - The exit tests live in `Adversarial/TrapAdversarialTests.swift` rather than §2.1's `ExitTests.swift`. They are correctly `#if os(macOS)`-gated.
- **N9. Notes for downstream briefs (no F02 change needed).**
  - (a) `Slot.misses: Set<Int>` encodes in hash order, so identical slots produce different bytes across launches. F05 and F19 should sort it if they hash or diff payloads.
  - (b) `Settings.default.weekStart = .monday` (`Model/Settings.swift:46`). F05 or F07's first-launch seeding must use `Weekday.first(of:)` (decision #15).
  - (c) `Duration` encodes as `[high, low]` attosecond words, and the low word can exceed `Double` precision. This is fine for `JSONDecoder`. Encode seconds if a non-Swift consumer ever reads it (M4/CloudKit).
  - (d) A slot with a lb `startLoad` prescribed under kg settings mixes a lb start with kg steps. That is brief-compliant, but the unit-switch feature should define what happens.

### Code-review skill findings rejected

- **#6: "an undone working row is a miss even when `targetSets` working sets were done".** The brief's wording is "any `.working` set is not done … or fewer done `.working` sets than `targetSets`", and `MissTracking` implements it exactly. `SessionBuilder` creates exactly `targetSets` working rows, and "+ Add set" rows are `.added`, so the scenario needs an engine that invents working rows. Not a defect.
- **#7: "a new Gregorian `Calendar` per `CivilDate` conversion is a hot spot".** Measured at about 0.36 µs per conversion (20,000 in 7 ms). Not a hot spot.

## Standards checklist (subagent-workflow §Reviewer)

| # | Check | Result |
|---|---|---|
| 1 | Module boundaries | **Pass.** All 38 source files `import Foundation` only. The package graph is unchanged and green, and `ModuleBoundaryTests.sources_importFoundationOnly` pins it. |
| 2 | Concurrency | **Pass.** Every type is a `struct`/`enum` and `Sendable`, with no classes or actors. No `static var`, `@unchecked`, `DispatchQueue` or `Task`. No `Date()`, `UUID()`, `Calendar.current`, `Locale.current`, `TimeZone.current` or randomness in Sources. The only `static let`s are immutable constants. Child IDs are derived deterministically (UUIDv8 via SplitMix64; version and variant bits checked). |
| 3 | Error handling | **Pass.** There is no `try?`, `try!`, `as!`, `fatalError` or `precondition`. `Slot.init`, `Program.init` and `SessionBuilder.build` use typed throws. Every validated type re-validates on decode with a `DecodingError` that carries context. The `??` fallbacks are documented and unreachable, except `groupRest`'s 90 s default for an empty or out-of-range block, which is documented. See S1 for the one invariant gap. |
| 4 | Design fidelity | n/a (pure logic). |
| 5 | Accessibility | n/a (pure logic). |
| — | User-visible strings | **Pass.** Checked against spec rules 14, 30, 34, 38, 39 and §6.3: `"5 × 5 @ 185 lb · RPE 8"`; receipt target before `" · "`; `"{n} × {w}×{r}"`, `"{w}×{r}"`, `"—"`; `"24,180"` and `"41.2k"`/`"24.0k"`; `"45 + 2×10 + 2.5 / side"` (no line below 2.5 per side); `"45s"`, `"2 min"`, `"1:30"`; `"Aug 12 · 5×5 @ 180 lb"`; weights `"185"`, `"52.5"`, `"46.25"`, `"83.9"`. Output is locale-free and never prints "-0". |
| 6 | Test quality | **Pass**, with Nit N8. Tests assert behaviour from spec-derived expectations, often with the arithmetic written out. There are no sleeps or wall clock (fixed `Fixtures.now` and calendar). Property tests use seeded SplitMix64 with `LEDGER_PROPERTY_SEED_COUNT` and meaningful oracles (the spec §7.2 prescription oracle, a greedy plate oracle, a round-major oracle, a Foundation day-arithmetic oracle), and failing seeds are pinned. Parameterized rows carry descriptions. Nothing is disabled. Every test name in testing-strategy §2.1 exists. |
| 7 | Brief compliance | **Pass.** Every criterion is mapped below. |

## Areas given extra scrutiny

- **Exact `Weight`:**
  - **Equality and hashing:** `Decimal`'s `==` compares numerically, and its hash is its `doubleValue`. I probed that equal values always share one compact representation: `"1.00"`, 25 × 4 and rounding results are all normalised. So equal weights hash equally, including 30-digit values; a `Set` dedupes them correctly.
  - **Codable:** strict text only. JSON numbers, exponents, NaN and partial input are rejected. Round-trips are exact (N3 is the one gap).
  - **Rounding:** all six `FloatingPointRoundingRule`s map correctly onto `NSDecimalRound`, sign-aware for `towardZero` and `awayFromZero`, and are tested positive and negative. A 38-digit quotient cannot fake a tie: the gap from a half-step is at least about 10⁻²⁶, against a division error below about 10⁻³⁵.
  - **Leftovers:** no lattice, quanta or `denominating` code remains.
  - **Performance:** a few `Decimal` operations per call; nothing hot.
- **`CivilDate` and `WeekCalendar`:**
  - Hinnant's integer day arithmetic is correct across 0001…9999 (tester property test).
  - Every boundary is the `startOfDay` of its civil day. Skipped-midnight days (Havana, Cairo, Santiago, Beirut) start at 01:00 without moving the other boundaries, and 167/169 h DST weeks are handled.
  - Travel keeps the same local date → the same week across 11 zones.
  - The only gap is the range edge in S1.
- **Lint suppressions:** see S4.
- **Public API beyond the brief:** see N7.

## Acceptance criteria → tests

| # | Criterion | Tests (implementer · adversarial) |
|---|---|---|
| 1 | 185 lb = 83,914.58845 g; "185" lb, "83.9" kg | `WeightTests.pounds_toGrams_exact` · `WeightAdversarialTests.pounds185_convertsAndFormats_matchesCriterion1` |
| 2 | 242.25 → 240; 242.5 → 245 | `WeightTests.roundedToStep_table` (rows 1–2) · `WeightAdversarialTests.roundedToStep_criterion2_tieAwayFromZero` |
| 3 | Incline DB double: 50×10, 50×11, 50×12, 52.5×10 | `ProgressionRulesTests.double_repsClimbThenLoadRisesAndRepsReset` · `ProgressionRulesAdversarialTests.double_incline_matchesCriterion3AndBeyond` |
| 4 | Back Squat deload week 7: 240 lb, 4 sets, RPE 6 | `ProgressionRulesTests.deload_loadTimes085RoundedToStep_minusOneSet_minusTwoRPE` · `ProgressionRulesAdversarialTests.deload_backSquat_matchesCriterion4` |
| 5 | misses {1}: week 3 adv 2, not held; week 2 held | `ProgressionRulesTests.linear_missedWeekHoldsLoad`, `held_flagSetWhenPreviousWeekMissed` · `ProgressionRulesAdversarialTests.linear_missInWeek1_matchesCriterion5` |
| 6 | Plate lines 185 / 180 / 250; 47.5 → nil | `PlateMathTests.perSide_185lb_is45plus25`, `perSide_180lb_is45_2x10_2p5`, `perSide_250lb_is2x45_10_2p5`, `perSide_belowSmallestPlate_isNil` (kg cases: `perSide_kg_20kgBar_usesKgInventory`) |
| 7 | 195 × 5 → 219 lb; 13 reps → nil | `OneRepMaxTests.brzycki_195x5_is219lb`, `brzycki_returnsNil_above12Reps` · `OneRepMaxAdversarialTests.brzycki_criterion7` |
| 8 | A1 B1 A2 B2 A3 B3 AD; last of round B1 B2 B3 AD | `SupersetRoundsTests.displayOrder_isRoundMajor_A1B1A2B2`, `isLastOfRound_trueOnlyForLastMember` · `SupersetRoundsAdversarialTests.displayOrder_criterion8` |
| 9 | Formula stated: 2,541 s → 42 min; superset 3 × 90 s → 9 min | `TimeEstimateTests.minutes_solo_isSumOf42PlusRestPerSet`, `minutes_superset_countsRestOncePerRound` · `TimeEstimateAdversarialTests.minutes_fiveStraightSlots_criterion9` |
| 10 | Aug 19 → week 0, Wednesday; Sep 14 → week 4; previous week Sep 7–14 | `WeekCalendarTests.weekIndex_fromStartDate` (rows 1–2), `criterion10_weekdayAndPreviousCompleteWeek` · `WeekCalendarAdversarialTests.criterion10` |
| 11 | Short working set inserts; deload unchanged; drop alone does not | `MissTrackingTests.workingSetShortOfTargetReps_marksWeekMissed`, `deloadWeek_neverMarksMissed`, `shortDropSet_doesNotMarkMissed` · MissTracking adversarial criterion-11 tests |
| 12 | 200 × 5 vs 219 lb → e1RM 102,058 g (225 lb) + weightAtReps | `PersonalRecordsTests.detect_newBestE1RM` · `PersonalRecordsAdversarialTests.detect_criterion12_bothKinds` |
| 13 | sets 13, reps 0, repsHi ≤ reps, rpe 4.75, rest 100 → matching error | `SlotValidationTests.init_invalidRange_throwsMatchingCase` (15 rows, including all five) |
| 14 | Foundation-only imports | `ModuleBoundaryTests.sources_importFoundationOnly` plus `scripts/check-package-graph.sh` (green in the gate) |

Test-plan extras are also covered: every property test the brief names, the kg plate lines, a Sunday week start, a DST week, receipt grouping, the last-performance line, a first session with `nil` history, and ties and deloads producing no PRs.

## Deviation verdicts (implementation-notes "Deviations from the brief")

| # | Deviation | Verdict |
|---|---|---|
| 1 | No `= UUID()` default on typed IDs; shared `TypedIdentifier` | **Acceptable.** Standards §4 outranks the sketch; the call-site spelling is unchanged. |
| 2 | `Slot.init` takes raw `rpe: Decimal` and `restSeconds: Int`, plus 3 extra error cases | **Acceptable.** Required so criterion 13 can throw `rpe 4.75` and `rest 100`; the extra cases are rule-backed (spec §6.1 drop 0/1, rule 6, positive step). |
| 3 | `PlateMath.PlateCount` instead of a tuple, plus `remainder` | **Acceptable.** Tuples can't be `Hashable`; `.plate` and `.count` read the same. |
| 4 | `ReceiptRow.actual: [String]` | **Acceptable.** Matches spec §6.1 `actual[]` and the chip rendering; the brief's `String` was lossy. |
| 5 | `doneSets`, `totalSets`, `volume` are computed | **Acceptable.** They can never go stale. |
| 6 | `WorkoutState.autoRest` added | **Acceptable.** A decision #7 snapshot that F04 needs; no persisted data exists yet. |
| 7 | `WorkoutEventStore` in its own file | **Acceptable.** The brief says F02 reserves the name, and F04 replaces the file cleanly. |
| 8 | Two inline SwiftLint suppressions | **`identifier_name`: not acceptable as is. Move it to `.swiftlint.yml` (S4).** **`function_parameter_count`: acceptable** with a recorded DoD waiver. |
| 9 | Tags, fixtures and the seeded RNG in the test target | **Acceptable** (F00 note #6). Revisit if `LedgerTestSupport` gains a test-only split. |
| 10 | `Settings.default.weekStart = .monday` | **Acceptable.** The domain cannot read the locale; the seeding duty is carried forward (N9b). |
| 11 | Plate sizes with unlimited pairs | **Acceptable.** Rule 38 and decision #10 define no counts; the property test checks exactness and the remainder. |
| 12 | `ModuleBoundaryTests` reads Sources via `#filePath` | **Acceptable.** Criterion 14 asks for a grep test; the read is read-only and inside the repo, and works on simulators. |
| 13 | `Program.init` sorts weeks | **Acceptable.** It normalises, and decode round-trips stay equal. |
| 14 | ADR-007 supersedes the sketch | **Settled** (Pete). The docs amendments (brief, architecture §5, decisions #9/#18, standards §5, F05 pointer) are consistent. |
| 15 | Public API beyond the sketch | **Acceptable.** Each item implements a numbered rule or decision a later feature needs; see N7 for three optional trims. |
