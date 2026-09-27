# ADR-007: Exact weights and a calendar-date program start

**Status:** Accepted · **Date:** 2026-09-27 · **Decided by:** Pete (product owner) · **Evidence:** `tasks/features/F02-domain-core/test-findings.md` (bugs A–C, spec questions 2, 3 and 5)

Amends product decision #9 ("Domain stores weight in grams (`Int`)") and decision #18's `startDate`.

## Context

F02 stored `Weight` as whole grams (`Int`), rounding every construction to the nearest gram. A
pound is 453.59237 g, so pound weights were never exact. To land on pound values, the
implementation inferred a step's unit from its gram value and did all arithmetic on a
0.01 lb lattice. The adversarial pass on F02 (`f30d94e`) showed this design leaks in several
places:

- **Bug A: a unit was guessed wrongly.**
  - 11 kg (11,000 g) is also the nearest gram to 24.25 lb, so an 11 kg step was treated as a
    pound step.
  - As a result, `Weight.kilograms(33).rounded(toStep: .kilograms(11))` gave 32,999 g instead of
    33,000 g, although 33 kg is already a multiple.
  - 64.75, 75.75 and 86.75 kg collide in the same way.
- **Bug C: ties were decided by gram noise.** A deload of 212.5 lb on a 1.25 lb step should be
  180.625 lb, exactly 144.5 steps, which rounds away from zero to 181.25 lb. Instead:
  - 212.5 lb was stored as 96,388 g, and × 0.85 gave 81,930 g = 180.6247 lb, just under the tie.
  - The result was therefore 180 lb.
- **Spec question 2: `+` drifted.**
  - `.pounds(185)` plus six additions of `.pounds(2.5)` is 90,719 g, but `.pounds(200)` is 90,718 g.
  - The display matches, but the values are unequal. A stepper built on `+` would record a false
    "weight at reps" PR.
- **Spec question 3: volume drifted.** Summing whole-gram weights gained 0.41 g per rep at 185 lb.
  1,000 reps of 185 lb formatted as "185,001" lb moved.

`Program.startDate` was an instant, and `WeekCalendar` derived every boundary by adding days to
an earlier start-of-day instant:

- **Bug B: an hour went to the wrong week.** In zones where DST skips midnight (Africa/Cairo,
  America/Santiago, America/Havana, Asia/Beirut), that day starts at 01:00. Every boundary
  computed from it kept 01:00.
  - In Havana, a block starting on Sun 2026-03-08 put the first hour of every later week
    (e.g. Sun Mar 15 00:30) in the previous week.
  - In Santiago, week 1 and week 2 overlapped by an hour.
  - In Cairo, the same stats week had different bounds depending on which day was asked about.
- **Spec question 5: travel moved the block.** The start of day was taken in the *current*
  zone, so after flying west a block's weeks could start a day early. Midnight in New York is
  Sunday 21:00 in Los Angeles.

## Decision

1. **Exact weights.**
   - **Type:** `Weight` holds an exact mass, `public let grams: Decimal`, and is never rounded on
     construction. `.pounds(x)` is exactly `x × 453.59237` g, with the constant built from
     integers; criterion 1's 185 lb is 83,914.58845 g.
   - **Exact arithmetic:** `+`, `-` and `scaled(by:)` are exact.
   - **Rounding only where a rule says so:**
     - `rounded(toStep:_:)` is `(grams / step.grams).rounded(rule) × step.grams`, with no unit
       inference. `Units.denominating` and the quanta/lattice machinery are deleted.
     - The Brzycki e1RM (decision #4) is an estimate and stays rounded to the nearest gram.
   - **Volume:** `Volume.gramReps` is exact too.
   - **Numeric identity:** equality, hashing and ordering are numeric (1.0 g == 1.00 g, with
     equal hashes).
   - **Codable:** a weight encodes as exact decimal text, `{"grams": "83914.58845"}`, so no JSON
     consumer can degrade it through `Double`. Decoding accepts only that shape.
   - **Formatting** is unchanged ("185" lb, "83.9" kg).
2. **Calendar-date program start.**
   - **Type:** `Program.startDate` is a `CivilDate` (year, month, day), a date with no time and
     no zone. It is `Hashable`, `Comparable`, `Sendable`, and encodes as `"YYYY-MM-DD"`.
   - **Week arithmetic:** `WeekCalendar` maps each instant to its civil day in the calendar's
     zone, then does pure day arithmetic.
   - **Boundaries:** every boundary is `startOfDay` of the target civil day, i.e. start + 7·i
     days. It is never an earlier instant plus n days.

## Persistence (F05)

F05 must store weights exactly. **Recommended:** an integer count of 10⁻⁷ g.

- 1 g = 10,000,000 units, and 0.01 lb = 4.5359237 g = 45,359,237 units. Every whole hundredth of
  a pound, every quarter pound, and every weight to 10⁻⁷ g is therefore an exact integer.
- Everything the rules hand to storage is a whole number of 10⁻⁷ g: prescribed and logged
  loads, rounded deload and drop loads, and e1RM in whole grams.
- Only unrounded intermediate products are not, e.g. `scaled(by: 0.85)` before
  `rounded(toStep:)`, or eighth-pound values such as 0.125 lb = 56.69904625 g. The storage
  boundary should reject such values rather than round them silently.

Range:

- **Per value:** `Int64` holds ±9,223,372,036,854,775,807 units = ±922,337,203,685 g ≈
  **±922,337 t** (about 922 kilotonnes) per value. Any single weight or set volume fits with
  enormous margin.
- **Aggregates:** volume *aggregates* must not overflow.
  - A lifetime total of 50 t moved per week for 50 years is 1.3 × 10¹⁸ units, only about 7×
    below the `Int64` limit.
  - So an SQL `SUM` over raw 10⁻⁷ g volume columns can approach overflow. F05 must choose an
    aggregate strategy that cannot overflow (e.g. a coarser unit for stored volume totals, or
    summing in `Decimal`) and test it at the 20,000-set scale and beyond.
- Column naming and aggregate design are left to F05.
- `Program.start_date` stores the `CivilDate` as `"YYYY-MM-DD"` text.

## Alternatives rejected

- **Keep `Int` grams and patch unit inference** (e.g. whole quarter pounds only, with an 11 kg
  exception). It fixes A but not C, question 2 or question 3, and keeps a heuristic that has to
  be proven collision-free for every inventory a lifter might enter.
- **Store the entry unit alongside grams.** Two equal masses would compare unequal across units,
  and every rule would need unit-aware equality.
- **An integer count of 10⁻⁷ g as the in-memory type.** Exact for everything stored, but products
  such as × 0.85 and × 36 / (37 − r) are not integers, so the rules would still need an exact
  intermediate type. `Decimal` gives exact arithmetic at domain scale with no scaling code.
- **Keep an instant start, but compute boundaries from start-of-day of the civil day.** This
  fixes B but not question 5. The start's civil day would still depend on the zone the app was in
  when it read it.

## Consequences

- **Source compatibility:** `Weight(grams:)` takes a `Decimal`. Integer literals still work.
  Callers that hold an `Int` wrap it with `Decimal(_:)`.
- **Performance:** `Decimal` arithmetic is slower than `Int`, but domain calls touch tens of sets.
  Heavy aggregates run in SQL on F05's integers.
- **Precision:** `Decimal` has 38 significant digits; realistic weights use fewer than 20.
- **Exact comparisons:** a PR can no longer come from a gram of noise, and ties on 1.25 lb steps
  are real ties.
- **Downstream briefs** that sketch `startDate: Date` (F08, F09, F24) pass a `CivilDate` instead:
  - F08 uses `WeekCalendar.firstDayOfWeek(containing: today)` for a new block's start.
  - Week indices come from `WeekCalendar.weekIndex(for:)`.
- **Codable shapes changed** (no persisted data exists yet):
  - `Weight` and `Volume` encode as decimal strings.
  - `Program.startDate` encodes as `"YYYY-MM-DD"`.
