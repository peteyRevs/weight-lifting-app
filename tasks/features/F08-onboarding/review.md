# F08 — review

## Slice S1 — review (G3 reviewer, 2026-10-04)

Reviewer pass on `feat/F08-s1-templates` at `fd8e747`, diff `git diff 8d5a991..fd8e747` (19 files, all new
except one line in `docs/architecture.md` and the appended notes section). I read every file of the diff in
full. I did not read the adversarial tester's untracked files and changed no code or test.

### Verdict

**Approve.** Blocking 0 · Should fix 1 · Nit 4.

The data is right: every exercise, role, set, rep, `repsHi`, RPE, rest, progression, superset, drop set,
weekday, day name, tag and preview line equals the brief, spec §6.4 / §6.7 and the prototype (see "Data
comparison"). The approval does not lift the ruling that the S1 PR waits for Pete's decision 3.

### What I ran

- **`/code-review` at effort `high`** on `8d5a991..fd8e747`, through the Skill tool. It returned 10 unverified
  candidates; I checked each (table under "`/code-review` candidates").
- **A comparison script of my own** (`compare.py` in my scratch folder, not in the repo): see "Data comparison".
- **Coverage, from the gate's result bundles** (`.derivedData/Results/PR-iOS.xcresult` 18:14:44,
  `PR-watchOS.xcresult` 18:19:53; the commit is 18:20:29, and the worktree still had no untracked file when I
  first looked at 18:26), read with
  `xcrun xccov view --report --json`: `ProgramTemplates.swift` 100 / 100, `ProgramTemplates+Splits.swift` 22 / 22,
  `ProgramTemplates+Prescriptions.swift` 31 / 31 on both; `Fixtures+Templates.swift` 22 / 23 on iOS. The claim
  holds.
- **Host tests:** `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'ProgramTemplates|DaysPerWeekTests|FixturesTemplatesTests|TemplateProgramRoundTripTests'`: exit 0. Every suite
  of the slice passed (the timing suite skipped, "nightly lane only"); the GRDB suite takes 0.38 s. The run also
  compiled and ran one of the tester's untracked suites, whose name matched the filter.
- **Release build, host:** `env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file` in
  `LedgerKit`: exit 0, no warning (42 s, incremental). Release `LedgerFakes.o` holds one symbol
  (`___swift_reflection_version`) and none of the fixture's; Release `LedgerDomain.o` holds the generator. So
  `LedgerFakes` still compiles out of Release.
- **Not run:** see "What I did not check".

### Blocking

None.

### Should fix

**S1-SF1. The fixture suite has an async test and no time limit.**
`LedgerKit/Tests/LedgerDependenciesTests/FixturesTemplatesTests.swift:9` (the suite), `:92`
(`defaultProgram_savesAndReadsBack() async throws`).
- Rule: `docs/testing-strategy.md` §3 rule 2, "Every async suite carries `.timeLimit(.minutes(1))`". No gate
  step checks the trait.
- Why it matters: an `await` that never returns would hold the run instead of failing in a minute with the
  suite named.
- Why it is not Blocking: the two awaits are on `InMemoryStores`, whose state sits behind a `Mutex` (there is no
  suspension to hang on), and the five other suites of this target already on `main` have async tests and the
  same gap (`FixturesTests`, `FakeStoreTests`, `DependencyKeysTests`, `PreviewValueTests`,
  `UnimplementedStubTests`; not this slice's to fix). If the orchestrator reads "a standards violation the gate
  does not catch" strictly, the fix is the same one line.

*Fix:* `@Suite("Fixtures · default program", .timeLimit(.minutes(1)))`.

### Nit

**S1-N1. A failed generation has already drawn ids.**
`LedgerKit/Sources/LedgerDomain/Templates/ProgramTemplates.swift:101-104`, `:125-129`; documented at `:90-91`.
- What a caller observes when a template exercise is missing: `ProgramTemplateError.unknownExercise(name)` for
  the first missing lift in day and slot order, no `Program`, and its id source advanced by the 8 week ids, one
  id per day reached and one per slot built before the miss (9 draws with an empty catalog). Nothing else
  changes; the function is pure.
- Harmless with random UUIDs. With an incrementing source a retry gets later ids, which is why the notes'
  "Inputs for S2" has to warn test authors.

*Fix:* resolve every lift before drawing anything (`let resolved = try split.days.map { day in try
day.lifts.map { … guard let exercise … } }`), then draw in the documented order. A failure then draws nothing,
and the caveat in the doc comment and in the notes can go. Coverage stays at 100 %. S2's store still draws the
program's own id first, so this is tidiness, not a behaviour S2 depends on.

**S1-N2. A split's weekdays and days are parallel arrays, joined by `zip`.**
`ProgramTemplates+Splits.swift:52`, `:56`; `ProgramTemplates.swift:151`.
- `zip` truncates silently and a repeated weekday overwrites: a day added without a weekday generates a valid
  program with a day that is never scheduled. Only tests stop that today
  (`program_weeks1to7_scheduleExactlyDaysPerWeek`, `program_schedule_isOnTheBriefsWeekdays`), and they do.
- `deloadRestDays` and `seed` (`:55`, `:59`) are `var` only to get defaulted memberwise parameters on a constant
  table.

*Fix:* give `Day` its weekday (`Day("Chest", tag: "CH", on: .monday, preview: …)`) and build the schedule from
the days, so the mismatch cannot be written; an explicit `Split.init` lets the two properties be `let`.

**S1-N3. `exercises` means two things.**
`ProgramTemplates.swift:48` (`DayPreview.exercises`) and `ProgramTemplates+Splits.swift:37` (`Day.exercises`)
hold the preview *line* ("Bench, incline, row, pulldown, laterals"); `Lift.exercise` (`+Splits.swift:16`) is a
catalog name, and the oracle's `Day.exercises` (`TemplateOracle+Splits.swift:25`) is the list of names. In
`ProgramTemplatesSplitsTests.swift:18` and `:89` the same word is read both ways.
- The public name is the plan's signature, so the implementer followed it. Renaming is free until S2 writes
  against it and an API change afterwards.

*Fix (orchestrator's call):* `DayPreview.line` (the brief said `previewLine`) and `Day.preview`.

**S1-N4. The notes hold two signatures for `program`, and the ruling names the one that was not built.**
`tasks/features/F08-onboarding/implementation-notes.md:20-53` ("Corrected `ProgramTemplates` signatures", the
flat seven-parameter form the rulings accept) against `:558-576` ("The API as built", `program(_:catalog:id:
newID:)` with `Request`).
- S2's implementer is told to read "this file's signatures". I accept `Request` (decision 1 below); what is
  missing is the orchestrator saying so.

*Fix:* one ruling line accepting decision 1, and a pointer on the old block to "The API as built".

### The seven review points

| # | Point | Result |
|---|---|---|
| 1 | Module boundaries | Pass. The four Domain files import Foundation only; the fixture file imports Foundation and LedgerDomain and is wholly inside `#if DEBUG` (`:1`, `:41`); `Package.swift` and `package-graph.expected.txt` are untouched; nothing in `Sources/` outside the slice names the new symbols. |
| 2 | Concurrency | Pass. No task, actor or shared mutable state. Every new type is `Sendable`; the tables are immutable `static let`s. Ids come from `newID`, the instant from a parameter; no `Date()` or `UUID()`. `newID` is rightly neither `@Sendable` nor escaping, so a `@MainActor` store can pass `{ uuid() }`. |
| 3 | Error handling | Pass, with S1-N1. Nothing swallowed, no `try?`. `ProgramTemplateError` is `Equatable` and `Sendable` and carries a template name, not lifter data. Mapping to the retry state is S2's. |
| 4 | Design fidelity | No UI in this slice. The strings a screen will draw (day names, tags, the four §6.7 lines) match `design/prototype/Ledger v2.dc.html:432-435` (Lower B per decision 1) and `Ledger.dc.html:873-896`. |
| 5 | Accessibility | No UI in this slice. |
| 6 | Test quality | Pass, with S1-SF1. Details under "Tests". |
| 7 | Brief compliance | Pass. Every S1 criterion as amended has a test (table below); nothing of S2 or S3 is in the diff; no file outside the slice's list changed. |

### Data comparison

What I compared, and how:

1. **By eye, line by line.** `ProgramTemplates+Splits.swift` beside the brief's "Templates" list with amendment
   4's full names; `ProgramTemplates+Prescriptions.swift` beside the brief's role table and spec §6.4's table;
   the weekdays and `deloadRestDays` beside §6.4's schedule line and amendment 5; the preview lines beside spec
   §6.7 and the brief's "Copy" paragraph.
2. **Mechanically, sharing nothing with `TemplateOracle`.** The script parses, as text at `fd8e747`, the
   brief's "Templates" list and role table, spec §6.4's table and §6.7's step-3 row, and the two Swift files,
   and compares:
   - 4 program names, their weekdays, deload rest days and which split has the seed;
   - 18 days: name, tag and preview line;
   - 79 lifts: exercise, role and order (16 + 15 + 24 + 24);
   - the flags and their positions: supersets on Upper A slot 5 and Lower A slot 4, the drop set on Upper B
     slot 4, none anywhere else;
   - 12 role cells × sets, reps, `repsHi`, RPE, rest, progression, and the goal → table wiring;
   - 16 §6.4 rows × the same six columns, and each row's slot position;
   - every scheme against spec §7.1's ranges;
   - each of the 22 distinct exercise names appearing exactly once in `exercises.json`.
   **Result: no mismatch.** Eight negative controls (a §6.4 rest, a role-table `repsHi`, a role, a preview
   line, a weekday, the drop set, a hyphen for the dash, two lifts swapped) were each reported.
3. **Against the prototype itself.** `Ledger.dc.html:873-896` (`DAYS`, `DOUBLE`, the fixed calf raise, `sup`,
   `drop`) and `:908-910` (`sched`, week 8 without Saturday) say what the product tables say.
4. **The dash.** Day names use " — " with U+2014, the separator `DayTemplate.shortTitle` splits on.

Not compared: the catalog's start loads against decision #21's policy (F03's data; the generator copies them).
For reference, the default block starts Bench 45 lb / 20 kg, Deadlift 95 / 40, Weighted Pull-Up +10 / +5.

### Tests

- **Oracle.** `TemplateOracle` and `TemplateOracle+Splits` name only model types (`Slot`, `Progression`,
  `Weekday`, `DaysPerWeek`, `TrainingGoal`); they read nothing from `ProgramTemplates`. The same agent wrote
  both copies from one brief, so a shared misreading was possible; my parse of the brief closes that for this
  revision.
- **Would a wrong template pass?** I found no field of the product tables that no test pins: program name,
  day name, tag, exercise and order (`program_everyGoalAndSplit_isTheBriefsTemplate`); role, through the scheme
  it gives under each goal, and the three roles' schemes differ under every goal
  (`program_everySlot_takesItsRolesScheme_exceptTheSeed`); the §6.4 rows and flag positions
  (`program_bothFourDay_matchesSpec64_exceptLoad`); weekdays, from the oracle and again as literals; week 8;
  preview lines (`preview_everySplit_isTheBriefs`).
- **Tests on internals.** Two read internal tables through `@testable`
  (`templates_everyExerciseName_isInTheBundledCatalog`, `specSeed_namesTheFourDaySplitsExercises`). The second
  is a structure test, and it earns its place: five seed rows equal the `both` role-table scheme for their
  role (Bench, RDL, Front Squat, Lat Pulldown, Seated Leg Curl), so a misspelt seed key would change nothing a
  behaviour test sees today.
- **Property tests and seeds.** `startDate_isOnTheWeekStart_atMostSixDaysBack` enumerates 7 week starts × 14
  days; nothing is random, so there is no seed to fix.
- **Sleeps and clocks.** None in the PR tier. The one wall-clock assertion is in
  `ProgramTemplatesPerformanceTests`, disabled unless `LEDGER_TEST_LANE` is `nightly`, the same shape as
  `ExerciseCatalogPerformanceTests`.
- **Start-date rows.** I checked the 18 expected dates by hand (weekdays, the Los Angeles evening, Havana's
  2026-03-08 and Cairo's 2026-04-24 transitions): all right.
- **Names** follow testing-strategy §6; every Domain suite carries `.domain`; file name equals suite name.
- **Coverage.** Verified above. The uncovered line is `Fixtures+Templates.swift:27`, the `throw` for a start
  date that cannot be computed from `Fixtures.now`. A failable `CivilDate` leaves no non-throwing spelling
  without a force unwrap, and `Fixtures+Program.swift:153` has the same line. It takes `LedgerFakes` from
  98.88 % to 98.82 % while LedgerDomain and the overall figure rise. I accept it; the orchestrator should
  accept the 0.06-point dip knowingly (standards §12, "coverage does not decrease").

| Criterion (as amended) | Test I read |
|---|---|
| 6, columns | `ProgramTemplatesSeedTests.program_bothFourDay_matchesSpec64_exceptLoad` (16 rows × lb, kg) |
| 6, schedule | `program_fourDay_scheduleMatchesSeed_includingWeek8` (4 goals) |
| 7, ranges | `ProgramTemplatesTests.program_everyGoalAndSplit_staysInsideSpec71` (32) |
| 7, names | `ProgramTemplatesCatalogTests.templates_everyExerciseName_isInTheBundledCatalog`, `program_fourDay_pullUpIsTheWeightedOne` |
| 7, days a week | `program_weeks1to7_scheduleExactlyDaysPerWeek` (16) |
| 9 | `program_sameInputsAndIDs_isEqual` (32), `program_drawsIDs_weeksThenEachDayAndItsSlots` |
| 3, data | `ProgramTemplatesSplitsTests.preview_fourDay_matchesSpec67`, `preview_everySplit_isTheBriefs` |
| 8, data | `program_kilograms_startLoadsAreMultiplesOfTheStep` (16), `program_startLoads_areTheCatalogs` (32) |
| 11, data | `ProgramTemplatesStartDateTests.startDate_criterion11_wednesdayIsInWeek1` |
| Amendments 4, 5, 6 | `program_emptyCatalog_…`, `program_missingExercise_…`, `program_customExercise…_isIgnored`; `program_deloadWeek_keepsItsDays_exceptTheFourDaySaturday`; `FixturesTemplatesTests` (5) |

### Public API, determinism, size

- **Surface.** `DaysPerWeek`, `ProgramTemplateError`, and on `ProgramTemplates`: `weekCount`, `Request`,
  `DayPreview`, `Preview`, `preview(days:)`, `startDate(containing:weekStart:calendar:)`,
  `program(_:catalog:id:newID:)`. S2 needs each of them and nothing more that I can see: the step-3 body takes
  `programName` and `weekCount`, the rows `preview(days:)`, the save `Request` and `program`. Roles, lifts,
  splits and schemes are internal. `DayPreview` and `Preview` have no public initializer, which is right while
  S2 builds its own display model from `preview(days:)`.
- **Documentation.** Every public declaration has a comment, and the ones I checked against the code are
  true: the id order and the 28 calls, the first-duplicate rule, the copied load and nil step, week 8.
- **Determinism.** Ids are drawn in three sequential `map`s; no `Set` or `Dictionary` order reaches the output
  (the schedule is a dictionary compared as one). What would break the documented order: reordering the week
  draw after the days (pinned by `program_drawsIDs_…`), or a catalog list that orders two same-named catalog
  exercises differently (documented; `ExerciseRepository.all()` orders by name key, then id).
- **Architecture §5 bullet** (`docs/architecture.md:241`): accurate, including the signature.
- **Size and style.** 388 Domain + 25 LedgerFakes code lines by my count, the notes' figures. Nothing is
  compressed, nothing existing is reformatted (the diff has no deleted line), and there is no lint
  suppression, `try?`, force unwrap or `@unchecked` in it.

### The implementer's 14 decisions

| # | Decision | Judgement |
|---|---|---|
| 1 | `Request` in place of the flat signature | Accept. The flat form needs the repo's second `function_parameter_count` suppression (I confirmed the rule is unconfigured and `SessionBuilder.swift:16` is the only one), against the DoD's "no new lint suppressions". Needs the orchestrator's ruling on record: S1-N4. |
| 2 | `startDate` anchors its throwaway calendar on the epoch | Accept. `firstDayOfWeek` reads the week start and zone only (`WeekCalendar.swift:77-79`, `:106-109`); one `nil` path, tested. |
| 3 | The §6.4 exception is data on the split | Accept. Both branches are reached; the key set is pinned. |
| 4 | A `RoleSchemes` per goal | Accept. |
| 5 | Week 8 through `deloadRestDays` | Accept: amendment 5 and O17, for every goal. |
| 6 | Exact name among non-custom exercises, first of two wins | Accept (O5). No M1 path stores two catalog exercises with one name. |
| 7 | Ids drawn before a failure | Accept as documented; S1-N1 offers the tidier form. |
| 8 | Preview lines; `DayPreview.name` keeps " — " | Accept. |
| 9 | Fixture tests in a new file | Accept (`type_body_length`). |
| 10 | `defaultProgramID` and ids 1001…1028 | Accept. I checked the other fixtures' ids (200…, 300…, `0x0700_0000`…, 9001–9003): no collision. |
| 11 | Test names against the plan | Accept. 49 tests, 27 of them parameterized over 409 cases, as the notes say. |
| 12 | The oracle is a second copy | Accept; see "Tests". |
| 13 | No unreachable branch; one uncovered fixture line | Accept; verified. |
| 14 | No public initializer on the preview types, no `units:` on the fixture | Accept. |

### `/code-review` candidates

| Candidate | Disposition |
|---|---|
| Start load frozen in the onboarding unit, step resolved per unit (`ProgramTemplates.swift:140`) | True, and as ruled (amendment 2, O6, decision #24). Not S1's: see "For other features". |
| Templates bind by name, not id (`:100`) | As ruled (O5). Its "a saved catalog row is filtered out by `!isCustom`" is wrong: `save` clears `catalog_version` and leaves `isCustom`. |
| `unknownExercise` can be permanent (`:7`) | Not reachable in M1: `ExerciseRepository` has no delete, and a custom exercise cannot shadow a catalog one. |
| `zip` truncates (`:151`) | Confirmed: S1-N2. |
| Strength accessories progress linearly (`+Prescriptions.swift:72`) | The brief's table, implemented as written: see "For Pete". |
| Days with no primary lift under `consistency` (`+Splits.swift:174`) | The brief's lists, implemented as written: see "For Pete". |
| The seed is a special case in the scheme lookup (`+Prescriptions.swift:47`) | A design preference; decision 3 is sound. |
| §6.4 is written out three times (`:104`) | By amendment 6 (`seedProgram` unchanged), and the oracle is a copy on purpose. A drift test guards the two fixtures. |
| Preview lines are hand-written (`+Splits.swift:37`) | They are §6.7's abbreviations and cannot be derived; the oracle pins each line. No action. |
| The fixture decodes the catalog on every call (`Fixtures+Templates.swift:32`) | True; `Fixtures.catalogByID()` on `main` does the same. No action. |

### For Pete (decision 3) and for other features

These are not findings against S1: the slice implements the brief's tables as written.

- **Strength makes every accessory linear** (`ProgramTemplates+Prescriptions.swift:72`). Cable Lateral Raise,
  Rear Delt Fly and Incline DB Curl start at 10 lb with a 2.5 lb step, so "Get stronger" prescribes 25 lb for
  3 × 8 in week 7, two and a half times the start load in six weeks. Under `both` the same lifts use double
  progression. Worth Pete's eye when he reads the lists.
- **Under `consistency` two days never change** (`+Prescriptions.swift:91-95`; `+Splits.swift:174-180`,
  `:219-224`). Secondary and accessory lifts are fixed there, and "Upper — Accessories" (5-day) and "Arms"
  (6-day) have no primary lift, so they prescribe the same loads and reps for seven weeks.
- **F14, changing units after onboarding** (`ProgramTemplates.swift:140`). The slot keeps the load it was given
  (Bench 45 lb is 20.41 kg) while its step, being nil, becomes the kilogram step: 20.41, 22.91, 25.41 kg.
  `Fixtures.seedProgram` has the same property. F14 has to decide what a unit change does to stored start loads.

### What I did not check

- **The full gate, the simulators, watchOS and CI.** I ran no `xcodebuild` and no `scripts/check.sh`; I relied
  on the orchestrator's exit 0 and read coverage from its result bundles.
- **The nightly timing test.** Two attempts to run it on the host failed to build because of the tester's
  in-progress untracked files, so the 5 ms budget (the notes' 0.13 ms median) is unverified by me.
- **The implementer's 17 mutations.** Not reproduced: I may not edit code. My negative controls were against
  my own script, not the Swift tests.
- **Module coverage totals** (2162 / 2180 and the like): I verified the per-file figures only.
- **The tester's files and `test-findings.md`:** not read.
- **Whether the 3-, 5- and 6-day programs are good programs.** I checked that they are the brief's.
- **S2 and S3**, beyond whether this API serves the call the notes describe.
