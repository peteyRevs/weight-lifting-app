# F02 — Adversarial test findings

Independent test pass on `feat/F02-domain-core` @ `f30d94e`. The tester did not read
`implementation-notes.md` or the implementer's tests. It saw the implementation only through its
public declarations and doc comments. Expected values come from the brief, spec §6.1/§7 and
decisions #3–#5, #7, #9, #14, #15 and #18.

- **Tests:** 209 `@Test` functions in 25 files under `LedgerKit/Tests/LedgerDomainTests/Adversarial/` (31 suites, all `.domain`; property suites also `.property`).
- **Result (PR lane, 200 seeds):** 201 pass, **8 fail**. The 8 failures come from 3 bugs (A–C below). All failing tests stay in place as regression tests.
- **Nightly lane (`LEDGER_PROPERTY_SEED_COUNT=2000`):** the same 3 bugs and nothing new. The seeds that failed are pinned through `PropertySeed.all(plus:)`, so the 200-seed PR lane runs them too.
- **Gate:** `scripts/check.sh --fast` passes format, strict lint and the package graph. `swift test` fails only on the 8 tests above.

## Bugs

### A. An 11 kg step is read as 24.25 lb, so exact multiples round off the kilogram lattice — bug (low)
- **Test:** `WeightAdversarialTests.roundedToStep_everyRule_matchesSwiftSemantics`, rows `33 kg / 11 kg` (every rule).
- **Attacks:** criterion 2, brief `rounded(toStep:)` ("nearest multiple of step"), decision #9.
- **Repro:** `Weight.kilograms(33).rounded(toStep: .kilograms(11))` gives `32999 g`. Expected `33000 g`: 33 = 3 × 11 is already a multiple of the step, so every rounding rule must return it unchanged.
- **Cause (seen from the outside):** 11,000 g is also the nearest gram to 24.25 lb, so the step is handled in the pound lattice (3 × 24.25 lb = 32,998.9 g → 32,999 g). The other 25 g multiples up to 100 kg that are misread the same way include 64.75, 75.75 and 86.75 kg. Realistic plates and steps (0.5–25 kg, 4 kg kettlebell steps) are unaffected. Tested: `24 kg / 4 kg` passes.

### B. Week ranges are off by an hour around days that have no midnight (DST at 00:00) — bug (medium)
Zones that spring forward at 00:00 → 01:00 include Africa/Cairo (last Friday of April), America/Santiago, America/Havana and Asia/Beirut. Every range the calendar builds from such a day's start (01:00) keeps 01:00 as its wall-clock time.
- **Tests:**
  - `WeekCalendarAdversarialTests.dst_santiagoMissingMidnight`
  - `.dst_havanaStartWithoutMidnight`
  - `.dst_cairoMissingMidnight_statsWeek`
  - `WeekCalendarPropertyAdversarialTests.weeks_agreeWithCalendarDays`, with pinned seeds 4664308, 7823989, 9708711, 12535794 and 15212416
- **Attacks:** decisions #15 and #18 ("current week = weeks since startDate"; stats week = done/scheduled in the current week), criterion 10's DST coverage, and the doc contract that "DST weeks are 7 days long".
- **Repros (expected = calendar-day midnights):**
  1. **Cairo, Monday start, `week(containing: Fri 2026-04-24 12:00)`:**
     - Got `Mon Apr 20 01:00 ..< Mon Apr 27 01:00`. Expected `00:00 ..< 00:00`.
     - `week(containing: Mon Apr 20 00:30)` and `previousCompleteWeek(before: Apr 29)` both return the correct midnight range. The same week therefore gets different bounds depending on the query date, and Mon Apr 27 00:00–01:00 falls in two weeks.
  2. **Havana, block starting Sun 2026-03-08 (no midnight), `weekIndex(for: Sun Mar 15 00:30)`:**
     - Got `0`. Expected `1`: Mar 15 is calendar day 7.
     - `bounds(ofWeek: 1)` is `Mar 15 01:00 ..< Mar 22 01:00`. The first hour of **every** week of the block goes to the previous week for the whole block.
  3. **Santiago, Sunday start, block from Sun Aug 30:**
     - `bounds(ofWeek: 1)` is `Sep 6 01:00 ..< Sep 13 01:00`, and `bounds(ofWeek: 2)` starts at `Sep 13 00:00`, so the two overlap by an hour.
     - `weekIndex(Sep 13 00:30)` is 2, but `bounds(ofWeek: 1)` also contains it.
- **Impact:** a set logged in that hour can count toward the wrong week's volume or sessions, or toward two weeks. When a block starts on such a day, week assignment is wrong for an hour each week for the whole block.
- **Suggested direction (not prescriptive):** compute every boundary as `calendar.startOfDay(for: <civil date>)` of the target day. Don't add days to an earlier start-of-day instant.

### C. Deload and drop-set ties on a 1.25 lb step are decided by gram noise — bug (low)
- **Tests:**
  - `ProgressionRulesDeloadAdversarialTests.deload_poundTies_roundAwayFromZero`, row `212.5 / 1.25`
  - `SessionBuilderEdgeAdversarialTests.build_dropRow_quarterStepTie`
  - `ProgressionRulesPropertyAdversarialTests.prescribe_matchesSpecOracle`, pinned seed 3587324 (lb, double progression, start 210, step 1.25, week 21, deload)
- **Attacks:** rule 12, rule 15, decision #3 ("load × 0.85 rounded to the exercise's weight step") and the brief's `rounded(toStep:)` rule (ties away from zero).
- **Repro:**
  - A deload (or drop row) on a 212.5 lb load with a 1.25 lb step gives **180 lb**.
  - Expected **181.25 lb**: 212.5 × 0.85 = 180.625 lb = exactly 144.5 steps, and ties go away from zero, so 145 × 1.25 = 181.25.
  - Other ties come out right, e.g. 12.5 → 11.25 and 112.5 → 96.25.
- **Cause (seen from the outside):**
  - The half-step sits at a half-hundredth (x.xx5 lb). The product passes through grams: 96,388 g × 0.85 = 81,930 g = 180.6247 lb, which lands just under the tie.
  - Whether a tie rounds up or down therefore depends on sub-gram error.
  - Ties on 2.5 lb and 5 lb steps land on whole hundredths and are unaffected, and kilogram steps are exact.
- **Suggested direction:** do the × 0.85 on the exact decimal value in the step's unit (as the spec §7.2 pseudo-code does), then round once.

## Spec questions (not encoded as assertions)
1. **Is the first set at a rep count a PR?** Decision #3 says "new best weight at ≥ the same reps". The brief makes `PersonalRecord.previous` optional, which suggests PRs with no previous record exist.
   - The implementation reports **no PR** when there is no history (a first session is a baseline), and also when history exists only at *fewer* reps. Probe: 200 × 5 against a history of only 150 × 3 → no PR.
   - Which is intended? The property oracle keeps a 20-rep history entry so it never depends on the answer.
2. **Should `Weight +` stay on the pound lattice?** `.pounds(185) + .pounds(2.5)` added 6 times is 90,719 g, but `.pounds(200)` is 90,718 g.
   - The display is still "200", but the values compare as unequal. A stepper (rule 6/28) that uses `+` would therefore record a false `weightAtReps` PR against a stored `.pounds(200)`. The drift appears after 5 steps from 185 lb.
   - `advanced(bySteps:of:)` is exact and is tested.
   - Should F04/F07 be required to use it, or should `+` / PR comparison tolerate sub-quantum differences?
3. **Is `Volume` drift acceptable in long-range stats?** Storage is gram·reps, so pound volume drifts about 0.41 g per rep at 185 lb. 1,000 reps × 185 lb formats as "185,001" instead of "185,000". A realistic week (400 reps → "74,000") is exact and tested. Is drift acceptable for monthly or lifetime aggregates (F05 `StatsQueries`), or should volume keep a finer unit?
4. **What should the cursor be for an empty day?** The brief says the cursor starts at (0, 0). For a day with no slots the implementation sets it to `nil`. `nil` looks right, but the brief doesn't cover this case, so it isn't asserted.
5. **Should program weeks move when the lifter travels?** `Program.startDate` is an instant. `WeekCalendar` takes the start of day in the *current* calendar's zone, so after travelling west the block's weeks can start a day early (NY midnight → Sunday 21:00 in LA). Should the start be stored as a civil date instead?
6. **Brief signatures that changed:** these look deliberate, but should be confirmed in review.
   - Typed IDs have no `init(_: UUID = UUID())` default. This follows standards §4.
   - `PlateMath.Breakdown.perSide` is `[PlateCount]`, not a tuple array, because tuples aren't Hashable. It also gains a `remainder`.
   - `ReceiptRow.actual` is `[String]`. This matches spec §6.1's `actual[]`, where the brief has `String`.
7. **Is it acceptable that `Slot`'s ranged fields are `public var`?** Setting `slot.sets = 13` builds an invalid slot. It encodes, but decoding then throws, so a persisted invalid slot can't be read back. The brief declares these fields `var`, so this is by design; please confirm editors always rebuild through `init`.

## What was attacked (all passing unless listed above)
- **Weight:**
  - Nearest-gram conversion in both units, including half-gram ties and negative values.
  - Criteria 1–2.
  - Every `FloatingPointRoundingRule` on ties and non-ties, positive and negative, in lb and kg, including rounding across units.
  - Non-positive steps; `advanced(bySteps:)` and `scaled(by:)` exactness.
  - Formatting: exact quarter values, one-decimal converted values, no trailing zeros.
  - Ordering, arithmetic, and Codable at `Int.max` and `Int.min + 1`.
  - Properties: round-trip at 0.01 lb and 1 g; idempotence; lattice membership; monotonicity; symmetry under negation; nearest and directed bounds; format length and accuracy.
- **Reps, RPE, RestDuration:** every bound, including NaN and off-grid values; `8 == 8.0` with equal hashes; rule 39 labels for all 19 legal rests; decode re-validation.
- **Volume:** gram·reps; separators; `compact` to one decimal plus "k"; arithmetic; a realistic week with no drift.
- **Equipment and Weekday:** default steps per unit; Foundation weekday mapping; locale first weekday.
- **Slot:** every range in criterion 13, including both boundaries, several violations at once, and negative start or zero step. Codable round-trip; tampered JSON (sets, reps, repsHi, RPE 4.75 and 7.25, rest 100 and 15, drop 2, negative start, zero step).
- **Program:** too few weeks; five non-contiguous shapes; unsorted weeks both built and decoded; a dangling schedule; 104 weeks; tampered JSON.
- **ProgressionRules:** criteria 3–5; a linear misses table; double progression with a miss, the narrowest span and the 1–40 span; fixed progression over 12 weeks.
  - Deload: floors, pound and kilogram ties, keeping double-progression reps, the held flag during deload, the week after a deload, zero load.
  - Start and step: kg defaults and steps; overrides; start-load fallback conversion; a 52-week block; `targetLine`.
  - Property: exact spec §7.2 oracle; load monotonic across weeks.
- **SessionBuilder:**
  - Rows per slot; header fields; progression by week; drop row; drop row on a deload week.
  - Snapshot fields (rule 16) and history.
  - Determinism with unique derived IDs; IDs disjoint across workouts.
  - Every error case, including `Int.max`; kg settings; auto-rest snapshot; off-schedule day; empty day.
  - Resume rule 17: same source only, live only.
- **SupersetRounds:**
  - Criterion 8; unequal set counts both ways; blocks of 3 and 5 members; drop rounds for two members; a drop on the shorter member; an empty member; solo blocks.
  - Grouping with a leading flag; group rest as the maximum; empty or out-of-range blocks.
  - Properties: exact round-major oracle for order and last-of-round; permutation; partition.
- **OneRepMax:** criteria 7 and 12; the kg 1–12 table; reps up to `Int.max` return nil; one rep; zero. Properties: within 0.5 g of the exact formula; monotonic in reps.
- **PersonalRecords:**
  - Criterion 12, checked exactly including `previous`, `achievedAt` and `workoutID`.
  - Cases that must not count: ties, deload, undone sets, drop-only and warm-up-only exercises. Added sets do count.
  - Reps over 12 give a weight PR only; the "≥ same reps" table; best across sets; the same exercise twice; several exercises.
  - Properties: oracle; set order doesn't matter; deload gives nothing; once history absorbs the workout's bests, there are no PRs.
- **PlateMath:**
  - Criterion 6 plus 9 more lb loads (up to 1,045 lb); loads below the smallest plate or the bar.
  - Kilograms: 8 loads, plus loads below the smallest plate.
  - Unusual inventories: no 25s, 25 kg plates, greedy leftover, inexact remainder, empty plates; normalisation on init and decode; standard sets.
  - Properties: every 5 lb load matches the greedy oracle exactly; every 2.5 kg load is exact.
- **TimeEstimate:**
  - Criterion 9 (2,541 s → 42 min; superset 522 s → 9 min); the seed Upper A day (39 min).
  - Drop sets, including inside a superset; three members; unequal members; deload sets.
  - Half-minute rounds up; empty day; a leading superset flag.
  - Property: decision #14 oracle.
- **WeekCalendar:**
  - Criterion 10; floored negative weeks; a start that has a time of day; negative bounds.
  - DST: New York spring (167 h) and autumn (169 h), Berlin both ways, Santiago, Havana, Cairo.
  - Calendar: year boundary; Sunday start; Settings override beats the calendar's `firstWeekday`; non-Gregorian calendars.
  - Week keys: ISO keys including week 53; Sunday-start keys; `WeekKey` ordering.
  - Block helpers: scheduled day, block end, skipped weeks.
  - Properties in 10 zones, including Lord Howe (30-minute DST), Chatham and Kiritimati: calendar-day oracle; contiguity; ISO key against Foundation's `.iso8601`.
- **MissTracking:**
  - Criterion 11; a deload leaves the slot identical; drop, added and warm-up shortfalls don't count; an undone working set; too few working rows.
  - Drop or added sets can't mask a miss; surplus sets, surplus reps or a lighter load aren't misses.
  - Removing a miss; only `misses` changes; `recordSkippedWeek`, including deload and out-of-range weeks.
  - Property: oracle, idempotence, order doesn't matter.
- **Models:**
  - RestTimer remaining time and fraction, including clamping.
  - Workout totals, volume and elapsed time (frozen at the end, never negative).
  - `LastPerformance.line`: time zones, the de_DE locale, the Buddhist calendar, kg.
  - Receipt rule 30: grouping, "—", gaps, alternating sets, drop sets, a kg target.
  - `shortTitle`, `Settings.default`, derived-ID uniqueness.
- **Codable:** every identifier (bare UUID; malformed input rejected); every enum case; exercise, week and day templates; a finished workout with a rest timer, sub-second dates and history, plus a bare one; fractional `Duration` in RestTimer and WorkoutSummary; PR kinds; settings; inventories; week keys; `Volume(Int.max)`.
- **Protocols:** conformances written from the brief's signatures for every repository, query and shape protocol compile and run.
- **Trap-freedom** (macOS exit tests): `prescribe`, `skippedWeeks` and `MissTracking.update` with week indices before the block. `WeekCalendar` produces these indices, and none of the three traps.

## Round 2: after ADR-007 (`f8e1687`)

The same independence rules applied: I read ADR-007, the brief, the spec, the public declarations
and doc comments, and the "Adversarial tests changed" part of `implementation-notes.md`. I did not
read implementation bodies or the implementer's own tests.

- **Tests:** 253 adversarial tests (37 suites): the 209 from round 1 plus 44 new ones (43 in 5 new files, plus 1 exit test in `TrapAdversarialTests`).
- **Result:** all pass.
- **Gate:** `scripts/check.sh --fast` passes: format, strict lint, package graph and 413 tests.
- **Nightly lane:** `LEDGER_PROPERTY_SEED_COUNT=2000` over all of `LedgerDomainTests` passes too.
- **Round-1 bugs A–C:** the 8 failing tests pass unedited. A, B and C are fixed.

### Audit of the implementer's edits to the adversarial tests

**Verdict: accepted.** Every change is either a compile-only adaptation or follows from ADR-007.
None weakens the original intent. I checked the assertions in all 25 round-1 files against what I
wrote and found no changes that the implementation notes don't list.

| Test | Implementer's change | Verdict |
|---|---|---|
| Compile-only adaptations (`Adversarial.startDay`; `CivilDate(start, in: calendar)` in the WeekCalendar, Trap, Stats and property helpers; `Decimal(_:)` wraps in 13 tests) | Types only | Faithful. Each `CivilDate` is taken in the test's own zone, so every DST and round-1 bug-B assertion keeps its meaning. |
| `pounds185_convertsAndFormats_matchesCriterion1` | 83,915 → 83,914.58845 g | Follows ADR (criterion 1 amended). Stronger, because the value is now exact. |
| `pounds_nearestGram_table`, `kilograms_nearestGram_tiesAwayFromZero` | Nearest-gram values → exact gram strings | Follows ADR and is stronger. I renamed them `pounds_exactGrams_table` / `kilograms_exactGrams_table` because the old names now describe the wrong behaviour. |
| `scaled_exactDecimal_nearestGram` | Exact products; adds `== pounds("242.25")` | Follows ADR and is stronger. I renamed it `scaled_isExactProduct`. |
| `arithmetic_andOrdering_inGrams` | Exact 185 lb | Follows ADR. |
| `rounded_respectsBounds` | Slack 6 g → 0 | Stronger. Accepted. |
| `brzycki_200x5_is225`, `detect_criterion12_bothKinds` | `== pounds("225")` → `== Weight(grams: 102_058)`, with `wholeValue == 225` kept | Follows ADR ("the e1RM stays rounded to the nearest gram"). I removed a stale comment. |
| `brzycki_oneRepAndZero` | 1 rep of 185 lb → 83,915 g, plus `wholeValue == 185` | Follows the brief and ADR rounding. The display name still said "estimates exactly the weight lifted", so I reworded it (see D). |
| `volume_ofSet_isGramsTimesReps` | `83914.58845 × 5` | Follows ADR. |

**What I strengthened** now that weights are exact:
- `poundsRoundTrip_hundredths_isIdentity` also asserts `Weight.pounds(x).pounds == x` exactly.
- `perSide_standardPounds_isExactAndDescending` asserts the plates per side add up to exactly `.pounds((load − 45) / 2)` in grams.
- I fixed stale gram figures in comments in `brzycki_criterion7` and the Volume tests.

### What was attacked

**Exact weights** (`ExactWeightAdversarialTests`):
- Stepper drift is gone:
  - 185 lb + 6 × 2.5 lb with `+` is exactly `.pounds(200)`.
  - 100 × 2.5 lb, 1,000 × 0.01 lb, 64 × 1.25 kg and 80 × −2.5 lb all land exactly.
- That stepper-built 200 lb **no longer fakes a PR** against a stored 200 lb best (round-1 question 2).
- Mixed-unit arithmetic is exact and reversible (0.45359237 kg == 1 lb).
- lb → g → lb and kg → g → kg are the identity for 8 values, down to 0.0001 and up to 123,456.789.
- **Equality, hash and order agree** across eight construction paths for 2.5 lb:
  - `.pounds`, a float literal, grams, kilograms, trailing zeros, a difference, a product.
  - 1 == 1.0 == 1.00 g, and every route to zero (including `.zero.scaled(by: -1)`) gives one value and one hash.
  - Inside `PRKind` as well.
- **Formatting:** a negative near-zero difference (185 lb − 83.915 kg = −0.41 g) never prints "-0".
- **Extremes:** 10⁻⁷ g and 20-digit pound values keep every digit.
- **Ties:**
  - The exact 1.25 lb tie at ±180.625 lb follows all six rounding rules.
  - A cross-unit exact tie (1.133980925 kg = ½ × 5 lb) rounds as a tie.
  - The 11 kg and 64.75 kg steps (round-1 bug A) stay exact.
- **Volume:** 1,000 reps × 185 lb formats as "185,000", and 50,000 reps is exactly 9,250,000 lb (round-1 question 3).

**Codable** (`ExactCodableAdversarialTests`):
- `{"grams": "83914.58845"}` shape.
- Digit-for-digit round-trips, including 38-digit, 10⁻²⁰, 10³⁰ and ⅓ lb values.
- 14 malformed payloads are rejected for both `Weight` and `Volume`:
  - a JSON number;
  - partial numbers `"12abc"`, `"1.2.3"`, `"1,5"`, `"1 2"`, `"0x10"`;
  - `"NaN"`, `null`, a missing key, bare values.
- A tampered `Slot` start load given as a number is rejected.
- `Program.startDate` encodes as `"2026-08-17"`, and impossible or badly shaped dates are rejected.

**CivilDate** (`CivilDateAdversarialTests`):
- 15 impossible dates (Feb 30, Feb 29 in 2023, 1900 and 2100, month 0 or 13, day 0 or 32, years 0, 10000 and −1) are nil.
- The leap and range-end dates are accepted.
- Day numbers and weekdays match proleptic Gregorian, from 0001-01-01 to 9999-12-31, including 1582-10-04/15.
- Arithmetic across leap days and year ends is correct, and so is ordering.
- 22 malformed "YYYY-MM-DD" texts are rejected: unpadded, full-width digits, en dash, trailing newline, `T00:00Z`, signs, 5-digit years…
- Zero-padded years such as "0005-01-02" work.
- An instant's civil day uses only the zone: it is the same under Islamic, Buddhist, Hebrew and Japanese calendars.
- `startOfDay` is 01:00 on Cairo's missing-midnight day.
- Exit test: `Int.max` / `Int.min` components give nil rather than trapping.

**Travel and DST** (`WeekCalendarTravelAdversarialTests`):
- **The same local date gives the same program week in 11 zones** (UTC−11 to UTC+14, Lord Howe, Cairo, Santiago, Havana), and gives the same bounds, civil date and `firstDayOfWeek` (round-1 question 5).
- The same scheduled day and block end also hold in every zone.
- One instant falls in different weeks in Los Angeles and Tokyo, as it should.
- **DST-at-midnight cases:**
  - Havana, block starting on its 01:00 day: week 0 starts at 01:00 and week −1 ends there.
  - Beirut: the week holding the missing midnight still ends at Monday 00:00.
  - Cairo, Friday week start: week 0 starts on the transition Friday at 01:00.

**Properties** (`ExactPropertyAdversarialTests` and `TravelPropertyAdversarialTests`):
- `+` sums equal the pound literal of the decimal sum.
- Hashes are numeric.
- `Weight` and `Volume` Codable round-trips are exact.
- Half-step ties round away from zero, or to even under `.toNearestOrEven`, on 7 steps.
- Up to 2,000 sets of volume equal the exact pound total.
- CivilDate matches Foundation for 1600–2399, and text, JSON and `startOfDay` round-trips hold in 13 zones (Tehran and Asunción included).
- Two random zones agree on week, weekday and week start for the same local date-time.
- Week bounds are starts of their own civil days.

### Findings

**No new bugs.** Two low-severity items:

- **D. Stale doc: `OneRepMax.brzycki` says "One rep returns `weight`" — doc (low).**
  - The implementation (following the brief and ADR-007: "the e1RM stays rounded to the nearest gram") returns 83,915 g for 1 × 185 lb, while `weight` is 83,914.58845 g.
  - The behaviour is consistent: every e1RM is whole grams, so e1RM PR comparisons are unaffected.
  - The doc sentence should say "One rep returns `weight` rounded to the nearest gram". No failing test, because the behaviour matches the ADR.
- **Q8. `CivilDate.adding(days:)` can leave the valid range — spec question.**
  - `CivilDate(9999-12-31).adding(days: 1)` returns `10000-01-01`, which encodes as `"10000-01-01"` but fails to decode, and `CivilDate(iso8601:)` rejects it too. The same happens with `0001-01-01 − 1` → `0000-12-31`.
  - So the type can produce a value that breaks its own Codable round-trip.
  - This is unreachable for real training dates. Options are to clamp, return optional, trap, or widen the year range. It isn't asserted.
- **Observation, not a finding:** `Weight`/`Volume` decoding is strict. `".5"`, `"+12"` and `"1e3"` are rejected. The encoder never emits these forms, so that is consistent with "decoding accepts only that shape".

Round-1 questions 2, 3 and 5 are answered by ADR-007 and now covered by passing tests. Questions 1, 4, 6 and 7 are unchanged.
