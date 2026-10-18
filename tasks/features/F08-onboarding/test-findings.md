# F08 — test findings

## Slice S1 — round 1 (G2 tester, 2026-10-04)

Independent adversarial pass over `feat/F08-s1-templates` at `fd8e747` (the template generator, `DaysPerWeek`,
`Fixtures.defaultProgram`). I read the brief with its "Plan amendments", spec §6.4, §6.7, §7.1, §7.2, decisions
#18, #21, #22, #24, ADR-007, the standards and the testing strategy, then the public declarations and doc
comments of the slice. I wrote and ran my tests before reading the implementer's tests or any function body, and
I have not read `implementation-notes.md`. No product code and none of the implementer's tests were edited;
nothing was committed.

Two limits on that independence, for the record:

- While printing the signature of `ProgramTemplates.program` I saw its first two body lines (the catalog is
  filtered to non-custom exercises and keyed by name, first wins). The doc comment says the same.
- I looked up the 22 template exercises in `exercises.json` (F03's data, not this slice's) before I wrote down
  decision #21's loads for them, so `BriefTemplates.catalogRows` restates the decision and is known to agree with
  the file.

**Result: no bug found.** 79 tests of mine (1,715 cases on the PR lane's 200 seeds), all passing. One spec
question for the product owner, no test-quality finding.

### Findings

1. **F8-S1-1 — spec question (no defect; the code does what the brief says).**
   - *Line in question:* the brief's role table, row `stronger`, column accessory: "3×8 (hi 10), RPE 8, 90 s,
     linear"; against the user story "the app writes a sensible first block" and spec §6.4, where the prototype
     puts no accessory on linear progression: Lat Pulldown, Cable Lateral Raise, Leg Press, Seated Leg Curl and
     Barbell Curl are double, Standing Calf Raise is fixed.
   - *What happens:* under `.strength` every accessory adds a step every week (spec §7.2 rule 9). From decision
     #21's loads the small lifts more than double in six weeks: Cable Lateral Raise 10 → 25 lb by week 7 (5 →
     12.5 kg), Rear Delt Fly 10 → 25 lb, Incline DB Curl 10 → 25 lb a hand, Barbell Curl 25 → 55 lb. The jump is
     the same from any start: +15 lb on a lateral raise in six weeks.
   - *Repro:* `TemplatesDownstreamAdversarialTests.sessionBuilder_buildsEveryDayOfEveryWeek`, input `strength ×
     6 days in lb`, day "Shoulders", week 7. The test passes, because it asserts the brief.
   - *Expected versus actual:* identical; nothing to fix in S1. The question is whether "Get stronger" should
     keep accessories linear, or give them double progression as `both` does. The miss rule (a missed week holds
     the load) softens it but does not remove it. A change would be one row of the role table, in the brief and in
     `ProgramTemplates+Prescriptions.swift`.

No finding of severity *bug*. No finding of severity *test-quality*: the implementer's suites assert behaviour
against a second transcription of the brief (`TemplateOracle`), cover all 32 inputs, both stores and the fixture,
and I found no assertion that restates the code or that I think is wrong.

Notes that are not findings:

- **Ids are drawn before a missing exercise is noticed** (documented: "some ids are drawn by then"). Measured:
  9 ids when the first exercise is missing (the eight weeks and the first day), 27 of 28 on the 4-day split when
  the last one is. With `uuid = .incrementing`, a retry after `unknownExercise` therefore gets ids that start
  later than a first success would. S2's retry test should not pin ids across a failed attempt.
- **Two non-custom exercises with one name:** the first given wins (documented and pinned by
  `duplicateCatalogName_firstWins`), so the result depends on the order of the catalog given. Not reachable today:
  catalog names are unique (F03) and no screen edits a catalog row.
- **Names against the brief's sketch:** `weekCount` for `weeks`, `DayPreview.exercises` for "previewLine", and
  `preview(days:)` returns a `Preview` that also carries the program name. The amendments do not mention these;
  S2 is the only caller.
- **A doc nit:** the type's doc comment says program names, day names, tags and preview lines "are stored in the
  program"; preview lines are not (they exist only in `preview(days:)`).

### Attacked and held

Tests are in `LedgerKit/Tests/LedgerDomainTests/Templates/Adversarial/` (64 tests),
`LedgerPersistenceTests/Adversarial/TemplateProgramStoreAdversarialTests.swift` (8) and
`LedgerDependenciesTests/Adversarial/FixturesTemplatesAdversarialTests.swift` (7). Expected values come from
`BriefTemplates*.swift`: my transcription of the role table, the "Templates" list as amended, spec §6.4, and spec
§7.2, §7.3 and decision #14 worked out by hand. Seeded tests take `PropertySeed.all`: 200 seeds on the PR lane
(`17 + 7919 × i`, `i` in 0…199), 2,000 nightly. No seed failed.

- **The whole input space** (4 goals × 4 day counts × 2 units = 32 inputs), `TemplatesTableAdversarialTests`,
  12 tests: every slot's exercise, sets, reps, repsHi, RPE, rest, progression, superset flag and drop sets; every
  day's name and tag; the program name; every week's schedule, index and deload flag; goal, day count, start date
  and `isActive`; spec §6.4's 16 rows a second time as literal text; the seed rows used on four days only; other
  goals on four days keeping exercises, supersets and drop set; the preview's names, tags and lines, spec §6.7's
  four lines, and the preview agreeing with the program for every goal.
- **Structural invariants** on all 32 inputs, `TemplatesInvariantAdversarialTests`, 12 tests: all ids unique and
  none the program's; every schedule entry names a day and every day is scheduled; every exercise is in the
  catalog and not custom; no empty day, no leading superset slot, no repeated exercise in a day; the block
  re-validates through `Slot.init` and `Program.init` and survives JSON; one deload and it is week 8; spec §7.1's
  ranges; no misses; start load equal to the catalog's for the unit, non-nil, a positive multiple of the unit's
  step in lb and in kg, and equal to decision #21's policy value; `step` nil; lb and kg blocks equal once loads
  are cleared.
- **Determinism and its limits**, `TemplatesDeterminismAdversarialTests`, 10 tests: equal programs from equal
  inputs (32); ids drawn in the documented order and count, 28 on four days (16); random 128-bit id sequences
  change ids only (200 seeds); a shuffled catalog gives the same block (200 seeds); a random start date in years
  1…9999 is kept and changes nothing else (200 seeds), with 0001-01-01, 9999-12-31 and a leap day by hand; an id
  source that returns one UUID for ever does not trap; 64 concurrent calls equal the serial ones.
- **The catalog given**, `TemplatesCatalogAdversarialTests`, 13 tests: each of the 22 exercises removed in turn
  for each split, 88 cases (used: `unknownExercise` naming it; not used: the usual block); an empty catalog names
  the first exercise of the first day (32); three missing names the first in day and slot order; custom
  exercises reusing all 22 names, before and after the catalog's, are ignored (16); a custom-only Deadlift is
  unknown; nine near-miss spellings of "Weighted Pull-Up" are not matched while "Pull-Up" is present; a short name
  is not matched; the catalog listed three times over; a load in the other unit only (converted, on the step); no
  load (zero, no trap); a negative load (`SlotValidationError.negativeStartLoad`, as documented).
- **Downstream**, `TemplatesDownstreamAdversarialTests`, 7 tests: `SessionBuilder` builds every day of every week
  for all 32 inputs (1,152 sessions), each exercise checked against spec §7.2 and §7.3 computed by hand (load,
  sets, reps, RPE, rest, step, superset flag, drop row at 85 % on the step, every weight storable under ADR-007);
  the spec's worked examples from decision #21's loads; `ProgressionRules.prescribe` over eight weeks with random
  misses stays inside §7.1 and on the step (200 seeds); a catalog refresh after generation moves no load
  (decision #24); `TimeEstimate` equals decision #14 by hand in a normal week and in the deload (18 to 57 and 11 to
  43 minutes); on the calendar, every day of the 56 is the brief's training day or rest for all seven week starts.
- **The start-date helper**, `TemplatesStartDateAdversarialTests`, 10 tests: all seven week starts on criterion
  11's Wednesday; every day from 2026-01-01 to 2027-01-15, at its first instant, a second later, noon and its last
  second, in 12 zones (Havana, Santiago, Cairo and Beirut change at midnight; Kiritimati and Pago Pago; Lord Howe
  and Kolkata), for every week start: 127,680 dates, each compared with Foundation's UTC arithmetic; the result's
  weekday is the week start; `WeekCalendar.weekIndex(for:)` is 0 for every instant of the block's first week, −1
  the second before and 1 the instant after (4,560 blocks); 14 year-end and leap-day cases by hand; 11 other
  calendar systems (Buddhist, Japanese, Hebrew, Islamic, Persian …) give the Gregorian day; the calendar's own
  first weekday, minimum first week and locale are ignored; instants outside years 1…9999, ±∞ and NaN give `nil`
  without trapping.
- **Stores**, `TemplateProgramStoreAdversarialTests`, 8 tests: all 32 blocks saved to GRDB and to
  `InMemoryStores` and read back equal to the original and to each other; a block written from each store's own
  `all()` equals the one written from the bundle (32); custom namesakes saved in the store change nothing; 16
  blocks side by side with the last one active (row counts 16 / 128 / 72 / 316 / 0); the columns (civil start,
  goal, day count, exact `start_load_e7g`, `NULL` step, week 8's `NULL` Saturday); an unseeded store refuses the
  block with `unknownExercise("exercise <first slot's id>")` and stores nothing, in both; the two program fixtures
  save into one database in either order; four whole blocks trained as prescribed (up to 48 workouts each)
  materialise in both stores and read back alike.
- **The fixture**, `FixturesTemplatesAdversarialTests`, 7 tests: `defaultProgram()` equals the generator's `both`
  × four block in pounds for 2026-09-14 with ids from `uuid(1001)`; every promise of its doc comment (own id,
  active, Bench 45 lb against `seedProgram`'s 180, `now` in week 1, ids 1001…1028 in order); it differs from
  `seedProgram` in loads, start and ids only; the two share no id and one store holds both; a given start date is
  used as is; `SessionBuilder` runs it.
- **Can these tests fail?** I changed my own transcription in seven places at once (a role-table repsHi, two
  lifts swapped, a preview line, a §6.4 rest, a start load, a deload rest day, the week-start arithmetic). Eight
  tests failed with 4,477 issues, each change caught; I then restored the files (compared byte for byte).
- **The implementer's performance test**, which runs on the nightly lane only, run once by hand on the host:
  passes (under 5 ms).

### Not attacked

- **Slices S2 and S3:** the onboarding screen and store, the root gate, the String Catalog, UI tests.
- **Mutants of the product code.** The rules of this pass forbid editing product code and copying the repository,
  so I mutated my transcription instead (above). It shows the same disagreements, from the other side.
- **Wall-clock time.** My tests assert no timing. The < 5 ms budget is checked only by the implementer's
  nightly-lane test.
- **Line coverage** of `ProgramTemplates` (the brief leaves it to the reviewer).
- **A block read in the other unit** than it was written in (a pound block under kilogram settings): steps
  resolve per unit at read time, which the brief gives to F14.
- **Stores whose catalog rows were deleted or renamed:** no repository method or screen does either today. The
  generator would throw `unknownExercise` for such a store, and F14's "Delete all data" should keep that in mind.
- **Other tz database versions and real devices:** the zone tests ran on the host and, in the gate, on the two
  pinned simulators.
- **The watch's use of a program** (F19) and anything that edits a generated block (F11).

### Commands and exit statuses

From the worktree root; logs in the scratch folder `f08s1-g2/`.

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'TemplateProgramStoreAdversarialTests\|FixturesTemplatesAdversarialTests\|LedgerDomainTests.Templates.*AdversarialTests'` (my 79 tests; `run7.log`) | 0 |
| the same filter with my transcription mutated (`mutation1.log`) | 1, as intended |
| `scripts/check.sh --lint-only` (`lint3.log`) | 0 |
| `scripts/check.sh --fast` (875 host tests; `fast1.log`) | 0 |
| `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter ProgramTemplatesPerformanceTests` (`perf.log`) | 0 |
| `/usr/bin/python3 <sim-lock> scripts/check.sh` (full gate; `gate1.log`, lock acquired after 498 s, gate 585 s) | 0 |

The full gate is green with my tests in place: format, lint, the iOS PR plan (17 test targets), the watchOS
PR-Watch plan (8 test targets) and the coverage gate (LedgerDomain 99.17 %, LedgerFakes 98.82 %, overall
98.50 %). No test of mine fails, so none makes it red.

What the gate's result bundles say of my suites (read with `xcrun xcresulttool get test-results tests`, not from
the log, which lists targets only):

- **iOS simulator:** all 8 suites ran: 79 tests, 1,715 cases, every one passed.
- **watchOS simulator:** 7 suites ran: 72 tests, 1,703 cases, every one passed. The fixture suite
  (`FixturesTemplatesAdversarialTests`, 7 tests) is in `LedgerDependenciesTests`, which the PR-Watch plan does
  not run, so it ran on iOS and on the host only.

Three things about this evidence a reader should know:

- The host log `run7.log` lacks the "passed" line of one of the 79 tests (`onlyACustomNamesake_isUnknown`, 4
  cases); its "started" lines are there, the run's summary counts 64 of 64 domain tests passed, the exit status
  is 0, and the same test has its line in the three earlier runs and passed on both simulators in the gate. I take
  it for a dropped line in the redirected output, not a result.
- After `run7.log` and `lint3.log` I changed one test's display name (a string). That file was re-linted alone
  (format and `swiftlint --strict`, clean); the full gate was the first build to compile it.
- `scripts/check.sh --fast` ran before I switched the four seeded tests from 64 seeds to `PropertySeed.all`, took a
  `.property` tag off the start-date suite and made that display-name change. The host run of my suites, the lint
  and the full gate are all later than these.

`tasks/features/F08-onboarding/review.md` appeared in the worktree during this pass. It is not mine; I did not
read or change it.
