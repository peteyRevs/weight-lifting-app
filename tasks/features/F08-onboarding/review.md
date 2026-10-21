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

## Slices S2 and S3 — the port, round 1 (G3 reviewer, 2026-10-19)

Reviewed: `feat/F08-s2-onboarding` @ `849db7c`, `git diff 16a2e52...HEAD` (157 files). The contract is the brief's
"Plan amendments — slices S2 and S3" with R1–R12, Pete's questions 1–5 at their defaults, his decisions 1 A, 2 A,
3 A, 4 A, 5 C, ruling B (`mainStandIn`) and F8-S2S3-4 (only the tabs audit is dated). I read the product files
whole first. Then I read the delta against `24b610b`: `FeatureOnboarding` differs only by R6, R8 and the source
test, and the 18 references are byte-identical. After that I read the new LedgerAppKit tests, the UI edits, the
notes' port sections and test-findings port rounds 1–2.

### Verdict

**Approved: 0 Blocking, 2 Should fix, 5 Nit.**

- The port is faithful. The gate, the router replaced on onboarding's appearance (R4) and the UI-test seam
  (R2) are correct, and I found no order of launch pass, phase change and store value that draws the wrong
  screen.
- **SF1 is not about this branch's code, but it must be done before the pull request opens (R10).** Since the
  notes were written, F11 S14 has added three UI-test files and edited `Tabs`/`TabsAdversarial` on the
  assumption that a UI test's database has no program. The merge is textually clean but semantically red.
- **SF2** is a race in one new root test.

### What I ran

- `git merge-tree --write-tree HEAD feat/F11-s14-program-tab` (`2487ebd`) and `… feat/F10-s7b-receipt` (`163f1d1`):
  both exit 0, no conflicted file.
- Host `swift test --package-path LedgerKit --filter 'FeatureOnboardingTests|UITestProgram|RootGate'`: exit 0,
  113 tests in 22 suites. The hosted root suites are `#if os(iOS)`, so they did not run here. For those I read
  the tester's 1,104 simulator runs (16 iterations, 0 failures).
- `git diff 24b610b HEAD` over `FeatureOnboarding` sources, tests and `__Snapshots__`.
- No simulator run, no full gate and no `/code-review` fork: I did the bug pass by hand (below).

### Criteria, briefly

- **1–11 (the screen).**
  - The store keeps the M1 convention: `@MainActor @Observable`, empty init, synchronous `send`, work only in
    the root's `.task` / `.task(id: attempt)`. Logging uses `logger.category("onboarding")` and no
    cancellation is logged.
  - A save cancelled before its write goes back to `.editing` (or to `.failed` for a retry).
  - The program id is drawn from `\.uuid` before the generator's ids (argument order,
    `OnboardingStore.swift:176`).
  - R6: the announcement is in `OnboardingRoot.swift:47-52`, through `announce`.
  - R8: `OnboardingCopy.swift:54` uses `locale.forCountedText`. `step(_:of:)` keeps the plain locale, which is
    right because its key has no plural variation.
  - Every literal is in `OnboardingCopy*`. `FeatureOnboardingSourceTests` covers the spellings, with a
    control.
- **12–15 (gate).**
  - `RootGate.follow(after:)` reads nothing before `launch` returns. A cancelled call writes nothing, including
    a value the stream had already handed over (the guard inside the loop). A stream that ends uncancelled
    gives `.main`.
  - `MainRoot` stays in the tree, so a phase change keeps onboarding's `@State` store (its step and picks).
  - R5 holds: the cover stays on `MainRoot.body`.
- **14 / R4.** `MainRoot.swift:71`: `.onAppear { router = newRouter() }` replaces the router.
  - S14's `AppRouter.programWeek` therefore goes with the old router, and no reset method has to keep up
    with it.
  - `AppRootTests.pushedScreen_isGoneAfterASecondOnboarding` (`:147-173`) checks three things. A new router was
    made. The old router still holds its pushes (so it was replaced, not emptied). The tabs after onboarding read
    over the new one.
- **16 / R12.** `retrySeed()` is the database half alone. `AppRootOnboardingAdversarialTests.retry_runsTheSeedStep_thenSaves`
  kills the `OnboardingRoot {}` mutant (test-findings, round 1, measurement 3), which closes S3-SF1 of
  2026-10-05.
- **20 / R2.**
  - `UITestProgram.liveSeeds` returns false in Release. The seam's body and its flag are `#if DEBUG`, and
    `SampleProgram` sits inside the file-wide `#if DEBUG` of `WorkoutLauncher+Sample.swift`.
  - The seam is saved once. A call that starts cancelled returns before marking itself done, and a
    `CancellationError` on a cancelled task does not mark it either.
  - `LedgerAppKit` already depended on `FeatureWorkout` (`MainRoot` imports it), so there is no new package
    edge.
  - A real failure is logged and marks the seam done (F8-S2S3-2, accepted).
- **21 (UI).**
  - Every `-LEDGER_UITEST` launch either adds the seed line, one per helper, or goes through
    `XCUIApplication.fresh()` and "Skip setup" (`Smoke`'s first test, `DebugMenu`, `LaunchPerformance`,
    `Onboarding*`).
  - I count **17** added `+= ["-LEDGER_UITEST_PROGRAM", "seed"]` lines in 14 files; the notes say 18 launches
    (notes:1053). The difference is harmless, but the notes should give the count a reader can grep.
  - The five no-program assertions are the ones removed. F8-S2S3-4's date is on the audit test alone
    (`TabsAdversarial.swift:134-137`).
- **22–26.**
  - The shared one-line files hold the module's name only, and `resources` is added.
  - `AppRootAdversarialTests`' sanctioned edits are commented and keep the old intent ("draws more than the
    ground").
  - Docs: architecture §4 and §14 are right. Testing-strategy §2.7's flow names exist (`Onboarding.swift:17, 76,
    94`). The F14 bullet and the `Settings.swift:36-40` comment (R11) are comment and brief only.
- **Seams (ruling B, R4).**
  - `AppRoot` gains one internal parameter, `mainStandIn` (nil default).
  - `MainRoot` gains `router:`, `newRouter:` and `mainStandIn:`, all internal and all defaulted, so the app's
    call sites are `AppRoot(composition:)` and `MainRoot(composition:gate:mainStandIn:)`.
  - `router:` goes beyond ruling B, but R4's test needs it: the test pushes before onboarding appears.
  - This is minimal. I would not fold `router:` into `newRouter:`, because the test reads both routers.

### Should fix

**SF1. Merging F11 S14 turns its UI tests red without a single conflict: the notes' R10 list is out of date**
(`implementation-notes.md:1053-1058`; on `feat/F11-s14-program-tab` @ `2487ebd`: `Apps/LedgerUITests/Builder.swift:151-159`,
`Tabs.swift:38`, `TabsAdversarial.swift:10, 14, 120`).

- *What.* The notes say S14 "adds no UI test" (true of `7f2b546`). S14 has since added:
  - `Builder.swift`, `DayEditor.swift` and `ProgramTabAdversarial.swift`. All three launch through
    `BuilderApp.launch(at:textSize:)` with `["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", …]` and wait for
    `today.title`. After this port they open on onboarding and fail at `Builder.swift:158`.
  - Sanctioned edits to `Tabs.swift` and `TabsAdversarial.swift` whose stated premise is "a UI test's database
    has none [no program]". Their Program tab reads "No program yet". With this port's seed line in those same
    helpers, the Program tab shows the builder over the seed program. `Tabs.swift:38-41`,
    `TabsAdversarial.swift:10/14` (the heading and label) and the AX5 height exclusion at `:120` stop
    matching.
  - `git merge-tree` reports both files clean, so nothing will flag this before the nightly.
- *Also.* `TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` will then audit the builder
  over the seed program at week 5. Neither lane has measured that state.
- *F10 S7b* (`163f1d1`) is fine. Its edits are inside launches that already carry the seed line (`Smoke`,
  `WorkoutFinishAdversarial`, `WorkoutSaveFailure*`), and it adds no launch helper.
- *Fix (when `main` with S14 is merged in, before the push, per R10).*
  - Add the one seed line to `BuilderApp.launch`. Its `seedTheProgram` then finds the seed program active and
    still works.
  - Re-edit S14's `Tabs`/`TabsAdversarial` lines so the Program tab is read over a program: the builder's
    `textFields["Program name"]`, or whatever S14 identifies the builder's heading by. Keep the AX5 exclusion
    only if the builder's heading still wraps.
  - These are sanctioned edits of another lane's testers' files: list each with its diff in the notes (R9's
    way) and have G2 re-run `Builder`, `DayEditor`, `ProgramTabAdversarial`, `Tabs` and `TabsAdversarial` on
    the Nightly plan.
  - Update notes:1053-1058 with S14's and S7b's actual files.

**SF2. `root_announcesTheFailureOnce` waits on a value nothing observes** (`LedgerKit/Tests/FeatureOnboardingTests/OnboardingRootTests.swift:16-18, 119`).

- *What.* `Heard` is a plain class. `Hosted.until { !heard.lines.isEmpty }` is an `Observations` sequence, and
  its closure reads no observable property. If the first evaluation is false, nothing can wake it, so the test
  runs into its one-minute time limit (or, if the sequence ends instead, the `#expect` on the next line
  fails).
- Whether it is already true depends on whether SwiftUI's update has run `onChange(of: model.error)` before
  `until`'s first evaluation, after the `until { phase == .failed }` above it returned. Those are two
  independent deliveries on the main actor.
- The suite is not among the tester's 16-iteration runs (those were the LedgerAppKit root suites), so its green
  is a few runs at most.
- *Fix.* Mark `Heard` `@Observable`, as `UITestProgramAdversarialTests.FirstPass` and `GateScene` are. Then
  `until` wakes on the append. One word, no change to what the test asserts.

### Nit

- **N1. `Support/LaunchedApp.swift:3-5, 25-28`: the doc comments are the S3 branch's, from before R2.**
  - They say "Eleven of the UI tests start through that helper", and that every test about "anything behind"
    onboarding "first gets to Today as a lifter who skips setup does". On this branch, three tests outside
    `Onboarding*` use it, and the rest launch with the seed program.
  - They also call `skipSetup()` "the one place that knows how" to get past onboarding, but
    `UITestProgram` is now the other place.
  - *Fix:* two sentences. The seed argument is how most tests get a program (testing-strategy §2.7); this
    helper is for tests of onboarding and of what "Skip setup" saves.
- **N2. Whole `Program` values in `#expect`** (`OnboardingStoreSaveTests.swift:30, 64, 86, 118, 136`,
  `OnboardingStoreFailureTests.swift:113, 151, 165`, `OnboardingRootTests.swift:73`,
  `Adversarial/OnboardingAdversarialScene.swift:137`).
  - These are carried unchanged from `24b610b`. A failure prints two programs of 4–6 days × 8 weeks with their
    slots.
  - The port's own new tests already compare outside `#expect` (`UITestProgramTests.swift:42-43`,
    `AppRootTests.swift:74-77`).
  - *Fix (optional, not in this PR unless touched anyway):* the same `let matches = saved == expected;
    #expect(matches, …)` with a short summary (`saved.map(\.id)`, day count) in the comment.
- **N3. Criterion 25's figure is in test-findings, not in the notes.** The notes call the seconds "open"
  (notes:1111-1115). The tester measured about +20 s on the PR sweep (test-findings, round 1, "Measurements
  asked for" (1)). *Fix:* one line in the notes pointing at it, so the PR description can quote it.
- **N4. `Today.swift` still starts and discards the Debug sample workout in every test to save the seed program**
  (`seedTheProgram(in:)`).
  - With `-LEDGER_UITEST_PROGRAM seed` that program is already active, so the step only costs nightly
    seconds. The header comment (`:11-13`) says so honestly.
  - R9 allowed one line per helper, so leave it here. *Fix:* a follow-up for F09/F15 to drop it.
- **N5. Two overlapping `saveUITestProgramIfAsked()` calls both save** (`AppComposition.swift:160-180`).
  - Only one program results, because both write the same seed program by its fixed id (the tester pinned
    this, `overlappingCalls_leaveOneProgram`).
  - The app has one gate per scene and one scene, so this is a property of the fixture, not a guarantee of
    the seam. *Fix (optional):* say in the doc comment that "once" rests on the seed program's fixed id when
    calls overlap.

### Conflict risk with F11 S14 (asked)

- **Textual: none.**
  - S14's LedgerAppKit delta is `AppTabs.swift` (+onProgramRoute), `MainRoot.swift` (one line inside `tabs`,
    `onProgramRoute: { router.resolve($0) }`), `Routes.swift` (`programWeek`, `requestProgramWeek`),
    `Routes+Today.swift` and the new `Routes+Program.swift`.
  - Of those, the port touches `MainRoot.swift` only, and only `content`, the init and the stored properties,
    away from the `AppTabs(...)` call. `merge-tree` is clean.
  - S14 constructs no `MainRoot`/`AppRoot` in its tests, so the port's new `gate:` parameter breaks nothing of
    S14's. The port's tests build no `AppTabs`: `GateTabsStandIn` is its own `TabView`.
- **Semantic: one thing, SF1 (the UI tests).** In the product, R4's new `AppRouter()` already covers S14's
  router state: `programWeek` is dropped with the old router when onboarding appears, which R4 intends.
- **Effort:** small. The merge commit itself is mechanical. SF1's follow-up is one launch line plus roughly
  three assertion sites in S14's two Tabs files, then a nightly run of five UI suites.

### For Pete (product decisions and invented wording)

- **Invented text, unchanged from 2026-10-05:**
  - "Back" (question 1; the design has no way back).
  - The singular "%@, %lld week, %@. Editable any time." (never shown at 8 weeks).
  - Every translator's comment.
  - The port adds no text a lifter sees.
- **Defaults built in, one place each:**
  - Q2: "Skip setup" saves Both × 4 whatever is picked, also from the failed state (`OnboardingStore.swift:68-69`).
  - Q3: the launch screen is untouched.
  - Q4: the first screen waits for the launch's pass (`RootGate.follow(after:)`).
  - Q5: the audit's two exclusions are kept.
- **Pete 5 = C:** units and week start are the stored settings' (pounds, Monday) until F14 decides about the
  region (the F14 bullet).
- **Follow-ups that touch product judgement, not this PR:**
  - The audit of Today over an ended block ("Open Program", "Block complete"; notes:1173-1177).
  - The three undated `TabsAdversarial` reads that rely on the seed block having ended (F8-S2S3-5).
  - The accent test's dark half on the shared simulator (an environment chore, test-findings round 2).
- **DoD screenshot still missing:** "Today after Start training", light and dark (notes:1118-1120). It is for the
  orchestrator's run of the app.

### What I did not check

- The hosted iOS suites, the UI tests and the snapshot references on a simulator. I read the tester's runs and
  the implementer's gate logs.
- A Release build: Debug-only is established by reading.
- The merged tree with S14 or S7b: only `merge-tree`, not built and not tested.
- VoiceOver by ear, Dynamic Type by hand, or a device.

---

> **Carried from the reviewed branches, as of 2026-10-05** (F08 S2/S3 port, ruling R1). The sections below are the
> review of `feat/F08-s2-onboarding-ui` @ `24b610b` (S2) and `feat/F08-s3-root-gate` @ `7c0b78f` (S3), copied
> unedited. Their line references, commit ids and file names are those branches'; what the port changed on
> today's `main` is in the notes' section "Slices S2 and S3 — the port (G1 implementer, 2026-10-18)".

## Slice S2 — review (G3 reviewer, 2026-10-05)

Reviewer pass on `feat/F08-s2-onboarding-ui` at `9cc5d54`, diff `git diff ec6c370..9cc5d54` (61 files). I read
every source and test file of the diff in full, the catalog key by key, the 11 screenshots and three of the 18
references. I did not read the adversarial tester's files and changed no code or test. The 632-line size is
ruled on and is not a finding.

### Verdict

**Changes requested.** Blocking 1 · Should fix 5 · Nit 8.

The store is sound and saves exactly once in every interleaving I could construct; the copy is the brief's word
for word; the module's boundaries and surface are clean. The one Blocking finding and the first Should fix are
the same story: the page was given two layouts so that the accessibility reader could read one of them, the
other one (the layout at every accessibility text size) is run by no test, and it has a defect.

### What I ran

- **`/code-review` at effort `high`** on the diff, through the Skill tool: 10 candidates, each checked (table
  near the end).
- **Host tests:** `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  FeatureOnboardingTests`: exit 0, 55 tests in 11 suites, 10.4 s, of which 10.3 s is the log-reading test
  (S2-SF4). `--filter ModuleCopyTests`: exit 0. The tester's `Adversarial/` folder appeared during the first run
  and did not break either build.
- **Three scratch probes on the iPhone 17 simulator (iOS 27.0), through the lock**, in a package of my own in my
  scratch folder (`f08s2-g3/axprobe/`; nothing in the repo): what a hosted SwiftUI `ScrollView` reports to an
  in-process reader, whether any switch changes that, and whether a page that swaps its content inside the same
  scroll view keeps its offset. Results under S2-B1 and "Pinning the VoiceOver tree of a screen that scrolls".
  Every accessibility preference a probe set was put back (automation 0, application accessibility 1, as found).
- **Not run:** the gate, the module's hosted suites and snapshots on the simulator, watchOS. See "What I did not
  check".

### Blocking

**S2-B1. Where the page scrolls, a step change keeps the scroll offset: the next step opens part-way down.**
`LedgerKit/Sources/FeatureOnboarding/Views/OnboardingScreen.swift:22-26` (the `ScrollView` branch), `:30-32`.
- What happens: the `ScrollView` keeps its identity from step to step and nothing resets it (no `.id`, no scroll
  position). A lifter whose page scrolls, scrolls down step 1 to read the fourth goal, taps "Continue" (pinned),
  and step 2 appears at the same offset: its title and the first line under it are above the top edge.
  The same from step 2 to step 3, and on "Back".
- Who meets it: everyone at an accessibility text size, on every phone. The references' own heights are 947 to
  1,232 pt at `.accessibility3` against 778 pt of safe height on an iPhone 17, so all three steps scroll there.
  At the default size the page fits on an iPhone 17; by the same arithmetic it does not on a 667 pt phone
  (iPhone SE: step 2 is 649 pt, so over by about 2 pt, and the six-day step 3 is 727 pt, against 647 pt),
  which iOS 26 still runs on.
  Dynamic Type at accessibility sizes is a launch requirement (`docs/product-decisions.md`, Accessibility).
- Evidence, and its limit: a probe with this screen's shape (`ViewThatFits { page; ScrollView { page } }` over a
  pinned button, rows switching between two `ForEach` kinds) on the simulator: scrolled to the bottom of step 0
  (offset 274), it arrived on step 1 at 274 and on step 2 at 274, in the same `UIScrollView`
  (`f08s2-g3/axprobe-offset.txt`). I did not run `OnboardingScreen` itself, which I may not write a test for;
  nothing in it differs in a way that would reset the offset. With VoiceOver on, the focus move at `:31` should
  scroll the title back into view, so this is a defect for sighted lifters with large text. What settles it on
  the real screen: the test below, or thirty seconds in a preview at AX3.
- Why Blocking: a functional defect of the delivered screen, in the one layout no test runs (S2-SF1), with a
  one-line fix. The screen is not in the app until S3, so no lifter meets it on merge; I still would not merge
  the template with it.

*Fix:* a new step is a new page, so give the scrolling branch the step's identity: add the step's index to
`OnboardingStepModel` (the presentation already derives `progress` from it) and `.id(model.step)` on the
`ScrollView`; or hold a `ScrollPosition` and scroll to the top in the `onChange` that moves the focus. Pin it with
a hosted test at 402 × 874 pt and `.accessibility3`: find the `UIScrollView` under the hosting view, scroll it
to the bottom, send `.advance`, expect the top. A hosted test reaches the scroll view itself; it is only the
accessibility children the reader cannot see.

### Should fix

**S2-SF1. The scrolling layout is run by no test, and the `.accessibility3` trees are read from a layout no
phone shows at that size.**
`OnboardingScreen.swift:22-26`; `LedgerKit/Tests/FeatureOnboardingTests/OnboardingAccessibilityTests.swift:63-66`,
`:76-86`; `OnboardingSnapshotTests.swift:13-15`;
`LedgerKit/Sources/LedgerSnapshotTesting/AccessibilityElements.swift:61`.
- The reader hosts a view in a window 2,000 pt tall, so `ViewThatFits` always picks the page that fits, also at
  `.accessibility3`. On a phone that size always gets the `ScrollView` branch. The snapshots draw the screen at
  its own height, which also fits by definition. The hosted root tests use 874 pt at `.large`, which fits. So
  the tree, the picture and the behaviour of the scrolling layout are checked by nothing but three hand-made
  AX5 screenshots; the implementer's coverage note says the same ("the scroll view's branch").
- Criterion 8 ("the tree of each step is … pinned by a test") and criterion 10 hold for the layout that fits.
  The notes say so honestly (decision 19); the brief does not.
- The trade, judged: what a sighted lifter sees is right at every size I have a picture of (a fixed page as the
  prototype draws it, scrolling under pinned buttons at AX5). The mechanism was chosen for the test tool, not
  for the lifter: `.scrollBounceBehavior(.basedOnSize)` on one `ScrollView` gives the same look with one layout.
  The price is a second code path that is the main one for large text, and S2-B1 is what hid in it.

*Fix, in this slice:* one reference at device height that draws the scrolling branch (for example the goal at
`.accessibility3`, dark, in a `.frame(width: 402, height: 874)`; a 19th image, which ruling O10 has to allow),
and S2-B1's test. Say in the brief's criterion 8 which layout the trees are of. `ViewThatFits` can stay in
onboarding once that branch is drawn and tested; it is not the pattern for a screen that always scrolls (see
the recommendation below).

**S2-SF2. Cancellation and failure are told apart by the task's flag in `save`, and not at all in
`loadUnits`.**
`LedgerKit/Sources/FeatureOnboarding/OnboardingStore.swift:95-101`, `:127-134`.
- `loadUnits()` catches everything and logs it at error level. When the root leaves while the read is in
  flight, a store that honours cancellation throws `CancellationError` (GRDB's async reads do), and the log
  says "Onboarding could not read the settings: CancellationError()". In onboarding the window is a few
  milliseconds. In Today, whose `.task` is cancelled on every tab change, the same four lines would write a
  false error on a normal path: this is the line a next store will copy.
- `save` asks `Task.isCancelled` instead of looking at the error, so a real failure that arrives on a cancelled
  task (the write throws a disk error just as the view goes) is neither shown nor logged. Standards §8: errors
  are never swallowed.

*Fix:* in `loadUnits`, `catch is CancellationError { return }` before the logging `catch`, with a test beside
`loadUnits_failure_keepsTheDefault`. In `save`, keep the phase rule as it is and log a non-cancellation error
before returning on a cancelled task.

**S2-SF3. Failures are logged under the category "app", not under the module's.**
`OnboardingStore.swift:40`, `:99`, `:132`; `LedgerKit/Sources/LedgerDependencies/Keys/DeviceKeys.swift:112-115`;
`LedgerKit/Sources/LedgerTestSupport/Localization/CopyAuditRules.swift:29-38`.
- Standards §8 and architecture §14 ask for a category per module. The store logs through the injected logger
  as it comes, whose live category is "app".
- It is the audit's gap, not the implementer's: `LedgerLogger.category(_:)` is the repository's own API for
  this, and the audit reads its unlabelled argument as copy (`isUnseen` knows the label `category:` and a
  logger's level calls only). A store file can take no exemption (§7), so the implementer had no clean way
  out, and was right to add no exemption and to say so.
- What a feature should do: write `logger.category("onboarding")`, after one of two one-line changes in shared
  code, whichever the orchestrator prefers: teach `isUnseen` the first argument
  of a call ending in `ogger.category`, with its case in `CopyAuditTests`; or relabel the API
  (`logger.with(category: "onboarding")`), which the audit passes as it stands because `category:` is already
  an allowed label. The second grows no regex.

*Fix:* the shared change before F09 S2's store is written, then one line here. Not in this lane alone:
`LedgerDependencies` and the audit are not this slice's files.

**S2-SF4. The log-reading test is the slowest thing in the target, holds the main actor while it reads, and is
not marked slow.**
`LedgerKit/Tests/FeatureOnboardingTests/OnboardingStoreLoggingTests.swift:15-20`, `:53`.
- Measured in my host run: 10.3 s of a 10.4 s run. `logged()` is a synchronous `OSLogStore` read on the main
  actor, so every main-actor test queued behind it reports about 10 s as well (`retry_cancelledMidFlight…`
  10.37 s, "Every preview renders" 10.03 s), each with its minute already running: the shape of F06's
  finding 19 (`LedgerDesignTests/Support/RenderingSuites.swift`).
- `docs/testing-strategy.md` §6: a test over 2 s carries `.slow` and leaves the PR lane. This one has no tag
  (the target has no `Tags.swift`) and runs in the PR lane.
- It depends on `logd` having written the entries by the time they are read. It passed every time anyone ran
  it; it is still the only committed test in the package that reads the system log, and so the only one whose
  result depends on another process.
- As the template it is wrong: every store would add 3 to 10 s to prove one log line.

*Fix:* the seam that costs nothing is a sink the logger writes to as well, which a test reads back (the
implementer's own alternative, as `DatabaseLaunch` has `record`); that is a `LedgerDependencies` change and
belongs with S2-SF3's. Until then: mark this test slow and gate it to the nightly lane as testing-strategy §6
describes, and say in the notes that the PR lane then has no proof of criterion 7's "is logged".

**S2-SF5. "Back" looks the same disabled as enabled, and sits 9 pt inside the edge everything else starts at.**
`OnboardingScreen.swift:56-61`; `LedgerKit/Sources/LedgerDesign/Components/PillButton.swift:22-35`;
`screenshots/s2/step3-save-failed-light.png`, `step2-days-dark.png`.
- In the failed state, which lasts until a save succeeds, "Back" is drawn exactly as on step 2 and does nothing
  when tapped. VoiceOver hears "dimmed"; a sighted lifter gets no cue. `PrimaryButton` reads `isEnabled`
  (`PrimaryButton.swift:33-37`); `PillButton` does not.
- At the default size the word is centred in its 44 pt target, so it starts at 35 pt where the bars, the title
  and the rows start at 26 pt. At AX5 the pill is wider than 44 pt and the word is flush: the misalignment
  comes and goes with the text size.
- The implementer tabled both and is right that the cure is `LedgerDesign`'s (open question 5). Onboarding is
  the first caller that disables a pill and the first that puts a ghost pill on a leading edge.

*Fix:* in `LedgerDesign`, before S3 puts this screen in front of a lifter: a disabled look for `PillButton`,
and a leading-aligned ghost form (the target can extend outward without moving the word). No change in the
feature beyond adopting it.

### Nit

**S2-N1. The bars are given an empty value where the component says both are required.**
`OnboardingScreen.swift:62`; `ProgressSegments.swift:23-26`. Criterion 8 and the tree ask for one element with
the label "Step 1 of 3" and no value, so the feature is right; the component's comment is what no longer
holds. *Fix:* one sentence in `ProgressSegments`' doc ("an empty value is not spoken"), or make `value`
optional, in the `LedgerDesign` chore.

**S2-N2. Passed steps are `.current` for its colour.** `OnboardingPresentation.swift:68`. The prototype wants
every bar up to this step orange (`Ledger v2.dc.html:543`), and `.done` is grey, so `.current` is the only way
to get it. If the component ever gives `.current` a meaning of its own (a pulse, a spoken word) all three bars
take it. *Fix:* a comment at `:68` now; an accent-filled state in `ProgressSegment` if a second caller wants it.

**S2-N3. No suite carries a layer tag.** `docs/testing-strategy.md` §6: "every suite carries its layer tag".
`FeatureOnboardingTests` has no `Tags.swift`; `LedgerAppKitTests` has none either, so this is the second
target without. *Fix:* decide once whether feature targets tag; S2-SF4 needs `.slow` in any case.

**S2-N4. The surface test compares source lines.** `OnboardingSurfaceTests.swift:13-22`. A declaration that
begins with an attribute or `nonisolated` (`@MainActor public struct`, `nonisolated public enum`) escapes the
`hasPrefix("public ")` filter, and wrapping the initializer over two lines fails the test with nothing wrong.
It is a tripwire, which is fine; the notes call it the proof of criterion 11. *Fix:* match `public` as a word
anywhere before the declaration keyword, or say "tripwire" in the test's comment.

**S2-N5. The footer has no bottom inset of its own.** `OnboardingScreen.swift:101-120`. On an iPhone 17 the
34 pt home-indicator area puts "Skip setup" about 48 pt from the bottom, the prototype's 46 px. On a phone
with no bottom safe area the word sits about 14 pt from the edge and its target touches it. Not in the table
of differences; no picture exists at that size. *Fix:* a bottom padding that applies when the safe area is
smaller than a token, and one picture at 375 × 667 pt.

**S2-N6. One look has no drawing anywhere: the options disabled.** After a failed "Skip setup" on step 1 the
four options dim (the plain button style's disabled look). Its tree is pinned
(`OnboardingAccessibilityTrees.swift:85-96`); there is no preview, no reference and no screenshot of it.
Standards §7 asks for a preview per meaningful state. *Fix:* a seventh `OnboardingPreview` case; no reference
needed.

**S2-N7. The hosting helper and `@testable import LedgerSnapshotTesting`.**
`OnboardingRootTests.swift:4`, `:35-46`, `:50-54`. Acceptable once: the public reader takes a synchronous body
and a root's `.task`s need a window that stays up across suspensions. Every `…Root` test from here on needs
the same twelve lines and the same `@testable import`. *Fix:* `LedgerSnapshotTesting` gains a public
`hosting(_:_:)` (async body) and `until(_:)`, in the chore; this file then drops the `@testable`.

**S2-N8. After a failed "Skip setup" on step 3, the page lists the picked split and "Retry" saves the
default.** `OnboardingStore.swift:63-68`, `:74-79`. Six days picked, "Skip setup", the save fails: the screen
reads "Your program · Body-Part Split" with six rows, and both buttons now save Upper / Lower. It follows from
decisions 7 and 8 and is tested as intended (`retry_afterAFailedSkip_savesTheDefault`); the lifter asked for
the default, so nothing wrong is saved. It is the one place the lock shows a program it will not save. For
Pete with open question 2; no change asked.

### What the next screens should copy, and what they should not

**Copy.**

- The four pieces and their edges: `XRoot` owns the store in `@State` and runs every piece of asynchronous work
  from its own `.task`s; `XScreen(model:send:)` draws a model and decides nothing; the state is one `Equatable`
  value; the presentation is a `nonisolated` function of that value and the injected locale. I found no `if`
  about domain state in a view and no `Date()`, `Calendar.current` or `Locale.current` in the module.
- `@MainActor @Observable final class`, dependencies as `@ObservationIgnored @Dependency`, and a store whose
  `init` does nothing. `OnboardingRoot.init` makes a store on every call and `@State` keeps the first
  (`OnboardingRoot.swift:16-18`): that is SwiftUI's documented cost and is harmless only while `init` stays
  empty. Keep it empty.
- A closure the app hands in stays the root's property and is passed to the store's async method on each run
  (`save(prepareRetry:)`), never stored in the store. The reason in decision 3 is right.
- "The phase follows the repository": one cancellation check straight before the write, and after the write
  returns the state says saved whatever happened to the task.
- The test kit: `StoreScene` (a store built inside `withTestDependencies`, a recorder over the fake), the `Gate`
  double for acting in the middle of an await with no sleep, `Observations` to wait on a hosted root, the trees
  written as a table before the tests.
- The copy file's layout: one lookup per case, `locale:` on every key with a value, a counted sentence tested
  with one, several, none and a second locale.

**Copy with care.**

- **One `send(_:)` with actions in the model.** Sound here: the screen has seven intents, none returns
  anything, and it lets the presentation decide that one button is "Continue", "Start training" or "Retry" with
  no `if` in the view. A stale model cannot do harm because `send` checks the phase again. It is not a
  requirement of the convention ("synchronous intents"). A screen with twenty intents that carry values (the
  workout) should not grow a twenty-case switch to imitate it; methods are as good.
- **Five phases.** `retrying` earns its place: it decides whether to prepare, what the button reads while the
  work runs, and where a cancelled attempt returns to. Model a store's phases from what its screen must
  distinguish, not from this list.

**Do not copy.**

- **`ViewThatFits` around the page** (S2-B1, S2-SF1).
- **The attempt token and `isSaveRunning` as the way to run user-initiated work.** It is correct here, and I
  could not break it: a double tap leaves the task's id unchanged, taps during a save are refused by the
  phase, a second run of the same attempt returns at once, a cancelled attempt writes nothing. But it takes an
  id type, a `.task(id:)`, a re-entry flag and a rule for what cancellation restores, about forty lines, for one
  operation; and its cancellation rule ("the view went away, so the tap is dropped") is right for onboarding
  and wrong for a logged set. Today loads and observes, which is a plain `.task`. The workout's writes belong
  to the session actor, with intents drained by one long-lived `.task`, as architecture §4 already says.
- **Locking the inputs after a failure** (decision 7). Defensible for a three-step form whose failure is rare
  and whose retry must mean "the same again"; S2-N8 and S2-SF5 are its costs. A failure on Today or in a
  workout must never disable what the lifter was doing.
- **`catch { log }` around a read that a `.task` can cancel** (S2-SF2), **the category "app"** (S2-SF3), **a
  test that reads the system log** (S2-SF4), **`@testable import LedgerSnapshotTesting`** (S2-N7).

### Pinning the VoiceOver tree of a screen that scrolls

This is the recommendation I would act on before F09 S4.

**What I measured** (iOS 27.0 simulator, a package test process, which has no `UIApplication` and no scene;
`f08s2-g3/axprobe-result.txt`, `axprobe-enabler.txt`, `axprobe-bundlewalk.txt`):

- The implementer's finding reproduces: for `VStack { ScrollView { … }; Text("Outside") }` the reader returns
  "Outside" alone. The `HostingScrollView` answers `accessibilityElements` nil and an element count of 0.
- None of these changes it: a second read; a `Task.yield`; a 50 ms run-loop turn; a key and visible window;
  content taller than the viewport; the application-accessibility preference (already on); loading
  `UIKit.axbundle` and `SwiftUI.axbundle` by hand and initialising them; and, with those loaded, the private
  walk XCTest's own snapshots use (`_accessibilityUserTestingChildren`), which answers with no children for the
  scroll view.
- So "fix the reader" is not a small chore. I found no in-process route in a package test, and the next thing
  to try is an app-hosted target (`LedgerTests`, where an application and a scene exist), which I did not try.
  Do not plan F09 S4 on it.

**What the scrolling screens should do.**

1. **Split the screen at the scroll view and pin the page.** A screen that scrolls is `XScreen` = its pinned
   parts plus `ScrollView { XPage(model:) }`, where `XPage` is everything that scrolls and never holds a scroll
   view. The tree table in the notes is the page's stops followed by the pinned parts', and the table-driven
   test hosts `XPage` and the pinned parts with the reader as it is. The snapshot helper has the same need (a
   `ScrollView` has no height of its own, so "at its own height" cannot draw `XScreen` either), and the same
   split serves it. This is fast, deterministic, needs no switch in product code, and keeps one layout in the
   product. It is what onboarding's tests already read in effect, without bending the product to get there.
2. **One UI test per scrolling screen, in the nightly lane, for what the split cannot show:** that the stops
   come in the table's order inside the real scroll view at an accessibility text size, with their selected and
   enabled states, and anything that exists only because the page scrolls (where a step change lands, what sits
   under a pinned bar). XCUITest is the only reader here that is a real accessibility client. It is too slow
   and too late to be the tree "pinned before the tester starts"; it is the backstop. S3's
   `LedgerUITests/Onboarding` should do this for onboarding at AX3.
3. **Make the reader loud.** `AccessibilityElements.swift:79-91`: when the walk meets a `UIScrollView` that
   yields no element, record an issue ("this reader cannot see inside a scroll view: host the page"). Today it
   returns a short tree in silence, and a table written from its output would pin the wrong thing. Same reason
   as the loud failure at `:107-110`.

Onboarding itself: fix S2-B1 and draw the scrolling branch (S2-SF1) now; move to the split when the convention
lands, or keep `ViewThatFits`, which is defensible for a page that fits on most phones once both branches are
tested.

### The seven review points

1. **Module boundaries:** pass. Imports are `SwiftUI`, `Observation`, `Foundation`, `Dependencies`,
   `LedgerDomain`, `LedgerDesign`, `LedgerDependencies`, and `LedgerFakes` inside `#if DEBUG` only. No new edge;
   the three shared files gained this module's name or line and nothing else; nothing of S3.
2. **Concurrency:** pass. No `Task {`, `Task.detached` or stored task in the module; the two `.task`s are the
   root's; the model, state, action and attempt are `Sendable` values; date, calendar, ids and locale are
   injected. S2-SF2 is the one gap.
3. **Error handling:** pass with S2-SF2 and S2-SF3. Every failure of the four steps maps to the one sentence;
   no raw description reaches the screen; no `try?` in product code; `startDateOutOfRange` is thrown, not
   unwrapped.
4. **Design fidelity:** pass with S2-SF5 and S2-N5. Tokens only (I found no raw colour, font, spacing or
   radius; the two `opacity` ternaries are 0 or 1). Orange on the bars, the check and the primary button and
   nowhere else, in both themes. Every difference from the prototype is read under "Deviations".
5. **Accessibility:** fails on S2-B1; S2-SF1. The trees meet criterion 8 and are what a VoiceOver user needs
   (below). Targets are 44 pt or more by test and by reading. Text wraps without truncation in every picture.
6. **Test quality:** pass with S2-SF4, S2-N3, S2-N4. No sleep, no poll; every async suite has its minute; names
   follow §6; the store suites assert what was saved and what the model shows. They also assert `attempt.number`
   and `state.phase` in places, which is the contract with the root's task and acceptable at that level.
7. **Brief compliance:** each of the eleven criteria has a test or a reference (the notes' table is accurate).
   Criteria 8 and 10 hold for the layout that fits only (S2-SF1).

### Accessibility, in detail

- **Order and traits.** "Back" (steps 2 and 3), the bars, the title as a heading, its line, the rows, the
  failure line, the primary button, "Skip setup": reading order is visual order in every state, and the tables
  in `OnboardingAccessibilityTrees.swift` equal the notes' tables stop for stop. Options are buttons with the
  selected trait on the button itself and no value, as ruling O8 asks. On step 1 "Back" is not a stop.
- **The bars** are one element with a label and no trait. Correct for something that is neither a control nor
  text. It is 2 pt tall, so it is hard to find by touch; that is `ProgressSegments`' frame, for the
  `LedgerDesign` chore, not a finding here.
- **Step 3's list.** Each day is one static-text stop, "name, line", not a button, and activating it sends
  nothing (`days_areNotTappable`). Right for a list to read.
- **The failure.** The sentence is a stop between the list and "Retry", and it is posted as an announcement
  when it appears (`OnboardingScreen.swift:33-38`). By ear I would check one thing: the focused button changes
  its label to "Retry" at the same moment, and VoiceOver may speak that over the announcement. If it does, give
  the announcement high priority (`accessibilitySpeechAnnouncementPriority`) or move focus to the sentence.
  Hosted tests cannot hear either; it is on the manual list, correctly.
- **Focus on a step change** goes to the title (`:30-32`). When the change also swaps `ViewThatFits`' branch the
  old title leaves in the same update; whether the focus lands is unverified. Manual list.
- **Dynamic Type.** The check stays at the trailing edge at every size, unlike `HairlineRow`'s accessory. The
  AX3 references and the AX5 screenshots show the labels wrapping beside it with nothing cut, so the deviation
  is fine.

### Presentation, copy, and what the localization rule made awkward

- **Purity:** `OnboardingPresentation.make(_:locale:)` reads its two arguments, `OnboardingCopy` and
  `ProgramTemplates.preview(days:)`, and nothing else. Domain data is shown as given except the brief's
  " — " to " · ".
- **The catalog against "Copy (exact)":** 31 keys, in code-unit order, every one `translated`; I compared each
  text with the brief and spec §6.7 and found no difference. No key and no text names the product. The
  counted sentence has `one` and `other` and one `%lld`. Spoken text ("Step %lld of %lld") is a lookup with
  `locale:`. I spot-checked ten comments against the code and relied on the gate's `xcstringstool` step for
  the rest.
- **What the rule made awkward, and what should change:**
  - *A logger's category reads as copy.* The audit should change (S2-SF3).
  - *`comment:` is a `StaticString`,* so it cannot be joined from two literals. The rule's text should say so:
    one sentence in standards §7.
  - *31 lookups with comments pass SwiftLint's 150-line type body.* Nothing should change: §7 already names
    `<Feature>Copy+<Area>.swift`, and the split by area reads well.
  - *The unit's name is a key of its own, placed into the sentence* (`OnboardingPresentation.swift:99-105`).
    That is the brief's key and is correct English. In a language that inflects, a translator cannot make the
    word agree. When a second language is added this becomes two counted sentences, one per unit. A note for
    §7's "Not settled", not a change now.
  - *The presentation is pure only up to the process's language.* Keys without a value take no `locale:`, by
    rule, so their language is the bundle's. Nothing to fix while the catalog is English only; worth one line
    in §7 so that nobody expects the injected locale to choose the language.

### Deviations: my reading of each

| Deviation | Reading |
|---|---|
| A fifth phase, `retrying` | Sound. See "Copy with care". |
| A failure locks the picks and the step | Acceptable for onboarding; do not copy. Costs: S2-N8, S2-SF5. A persistent failure leaves only "Retry" and "Skip setup", which is all that could help anyway. Open question 2 stays Pete's. |
| "Skip setup" after a failure prepares first | Right: without it the skip fails for the same reason. |
| One `send(_:)`, actions in the model | Sound here; optional elsewhere. |
| `prepareRetry` handed to `save`, not stored | Right, and the pattern to copy. |
| An internal `init(store:prepareRetry:)` | Fine; the public surface is unchanged. |
| A cancelled save puts the phase back and is not run again | Right for onboarding: the view going away means the lifter left. S2-SF2 is about what is logged, not this rule. |
| The unit is read on appear and again by each save | Right: the save's read decides what is written. |
| No animation between steps | Fine; nothing to turn off for Reduce Motion. |
| The page scrolls only when it does not fit | S2-B1, S2-SF1. |
| The log's category | S2-SF3. |
| `OnboardingState.swift`, `OnboardingCopy+Options.swift`; no `ProgramPreviewList`, no `OnboardingStrings` | Fine. Six lines of `HairlineRow` do not need a file. |
| `@testable import LedgerSnapshotTesting` | Acceptable once (S2-N7). |
| The log-reading test | Not acceptable as it stands (S2-SF4). |
| "3 days" … "6 days" as four keys; "pounds" and "kilograms" as keys | As the brief lists them. |
| Bars 106 pt from the top (prototype 76 px), under a row kept empty on step 1 | The reasoning holds (the bars must not jump; the status bar leaves no room above). It costs 30 pt on every step, which is what makes step 2 miss a 667 pt screen by about 2 pt. A "Back" in the footer would give it back. At accessibility sizes the word also sits straight on the first bar and reads like a tab's title (`programSixDays…dark-accessibility3.png`). Pete's call, with ruling O9; not a defect. |
| Bars 3 pt gaps, `accentText` and `hairlineStrong`; inset 26 pt; row padding 16 and 12 pt; gaps 32, 12, 32 pt | The component's and the tokens'. Accept. |
| Title at full width | Accept: a fixed measure does not scale. Both titles still break where the prototype breaks. |
| The line under the title in `.bodyLight` (13.5 pt against 15.5 px) | Ruled (O14). In the pictures it is one point larger than the option's sub line, so the step between the two that the prototype draws is nearly gone. If Pete minds, it is a type role for F06, not this slice. |
| Option label `.body`, sub `.label`, muted inks above the prototype's alphas | Accept: the prototype's 36 % and 48 % are below AA. |
| The check: 21 pt and a heavier stroke | Accept; a lighter tick is a second `LedgerIcon` (open question 6). |
| Step 3 as plain rows in full ink | The default in force (Pete's decision 2). |
| `PrimaryButton` 700; "Skip setup" 12 pt | The components'. Accept. |
| Two oranges in light (`accentText` on the bars and the check, `accent` on the button) | The tokens' design for paper. Accept. |
| Missed by the table | S2-N5 (bottom inset on a phone without a home indicator). Unverified: at large text the page scrolls under the status bar with nothing behind the clock; look at it in S3's manual pass. |

### `/code-review` candidates

| Candidate | Result |
|---|---|
| A cancelled save returns to `editing` after the re-run was turned away, so the tap is dropped | By design (decision 9), tested. Not a finding. |
| Any error on a cancelled task is treated as a cancellation | Half real: S2-SF2. The other half (a write that commits and then throws `CancellationError`, so a second tap saves twice) I do not believe: the protocol promises all or nothing and GRDB rolls back when it throws. Not tested on GRDB here (see below). |
| "Skip setup" after a failure discards the picks | By design (decision 8). S2-N8 is the visible edge. |
| A failed attempt locks the picks for good | By design (decision 7); judged above. |
| `loadUnits` logs a cancellation as an error | Real: S2-SF2. |
| `ProgressSegments` given an empty value | S2-N1. |
| Passed steps are `.current` | S2-N2. |
| The focus move can target a title `ViewThatFits` is replacing | Plausible, unverifiable without VoiceOver: manual list. |
| `OnboardingRoot.init` makes a store on every call | True and harmless while the store's `init` is empty; noted under "Copy". |
| `preview(days:)` is computed twice per model on step 3 | True, a few microseconds. No action. |

### For S3

- **Keep `OnboardingRoot`'s place in the tree while the gate reloads.** The store is the root's `@State`. If
  the gate passes through `.loading` on a scene-phase change and takes the root out for a frame, the lifter
  comes back to step 1 with the defaults.
- **After `saved` the screen is inert.** Every control is disabled and nothing here leaves. If the gate does
  not flip, the lifter is stuck; `savingAProgram_flipsToMain` is the test that matters.
- **The nightly UI test** should run the three steps at an accessibility text size as well (S2-B1, and item 2
  of the recommendation).

### What I did not check

- **`OnboardingScreen` itself for S2-B1.** The offset was measured on a replica of its shape, not on the
  screen.
- **VoiceOver by ear:** the focus move, the announcement, the order inside the scroll view.
- **The module's hosted suites and the 18 references on the simulator.** I ran the host's 55 tests; the
  accessibility, root and snapshot suites run on iOS only and I relied on the orchestrator's gate for them. I
  looked at three references and all 11 screenshots, not at all 18.
- **The gate, coverage, watchOS, CI, the nightly lane.** Not run; the 98.96 % and the per-file figures are the
  implementer's.
- **Cancellation in the middle of a real GRDB write.** The store tests use the in-memory stores and doubles,
  whose write cannot be interrupted. "Exactly once" under cancellation rests on GRDB throwing only when it
  rolled back, which I read in its contract and did not run.
- **A 667 pt phone and an iPad.** My "does not fit on an SE" is arithmetic from the references' heights.
- **An app-hosted reader** as a way to see inside a scroll view.
- **The implementer's 13 mutations,** and the tester's files and `test-findings.md`.
- **Every catalog comment against the code:** ten by eye, the rest by the gate's step.

## Slice S2 — re-review of fix round 1 (G3 reviewer, 2026-10-05)

Scoped re-review of `git diff 1efaf08..19b20eb` (70 files) against my findings above and the orchestrator's
rulings after G2 and G3; not a fresh review. I read every source, test and doc change of the diff, the fix
round's notes with "Addition: the reader's opt-in", the brief's revised criteria 7, 8 and 10, and looked at the
three new screenshots, two re-recorded references and two of the six new ones. I did not read the tester's
uncommitted files and changed no code or test.

### Verdict

**Approve.** Blocking 0 · Should fix 4 (two in this slice, two for the chore before the next lane) · Nit 3.

B1 and all five Should-fix items are closed. The approval is of the diff: `19b20eb` by itself is red in the PR
lane on twelve of the tester's tests, by ruling, until its close-out is committed.

### What I ran

- **Simulator, the three targets, on a clean tree at `19b20eb`** (`git status --short` empty before and after;
  the implementer's `sim-test.sh` through the lock, `-only-testing:FeatureOnboardingTests
  -only-testing:LedgerDesignTests -only-testing:LedgerAppKitTests`): 644 tests, 624 passed, 12 failed, 4 skipped,
  4 expected failures: the implementer's numbers. The 12 are the tester's (eight of
  `OnboardingVoiceOverAdversarialTests`, four of `OnboardingLayoutAdversarialTests`) and nothing else.
  `LedgerDesignTests` 296 passed, with F06's `sheetChrome_scrollingContent_titleAtTheTopAndWhole` and every
  existing snapshot suite among them; `LedgerAppKitTests` 208 passed.
- **The hosted suites ten times over** (`OnboardingScrollTests`, `OnboardingRootTests`, `-test-iterations 10`):
  every repetition passed. The tester's in-progress edits were in the tree by then and built.
- **The nightly logging test:** on the simulator (`TEST_RUNNER_LEDGER_TEST_LANE=nightly`) it runs and passes in
  4 s, which the notes list as not yet run; on the Mac host it passes in 6.65 s while `OnboardingStoreTests`
  beside it take 0.02 s, so the main actor is no longer held.
- **One scratch probe** (my own package, as before): a scene-less window on this simulator gives a hosted view
  the safe area 62 / 34 pt at 402 × 874 pt and 62 / 0 pt at 375 × 667 pt (`f08s2-g3/axprobe-safearea.txt`).

### Status of the first review's findings

| Item | Status | Note |
|---|---|---|
| **S2-B1** offset kept across steps | **Closed** | Below. |
| **S2-SF1** scrolling layout untested | **Closed** | One layout; trees and references from the page and the pinned part; four hosted tests on the real screen and root. What remains (the stops' order inside the real scroll view) is S3's UI test, by the convention. |
| **S2-SF2** cancellation and failure | **Closed in the code** | `loadUnits` returns on `CancellationError`; `save` logs every other error, also on a cancelled task. Pinned in the nightly lane only (RR-SF3). One corner left (RR-N1). |
| **S2-SF3** log category | **Closed** | The store logs under "onboarding"; the audit's rule is one alternation in the shared helper with two allowed cases and two lookalikes that stay findings; standards §7 and §8 say so. RR-N2. |
| **S2-SF4** log-reading test | **Closed as ruled** | Nightly, tagged `.slow`, read off the main actor (measured above). The cost and the cheap way back: RR-SF3. |
| **S2-SF5** "Back" | **Closed** | Below. |
| **F8-S2-1** (tester) | **Closed** | The pinned part takes the height its text needs; `pinnedPart_onTheNarrowestPhone_isNotSqueezed` (three states, 375 × 667 pt, accessibility5) and the picture, where the sentence stands on three whole lines. It holds for the English sentence: `fixedSize` has no upper bound, so a translation twice as long would leave the page no room there. Nothing to do now. |
| S2-N1, N2, N3, N4, N5, N6 | **Closed** | N5 has both branches under test: the two window sizes give 34 pt and 0 pt of bottom safe area (probe). N3 tags the implementer's fourteen suites. |
| S2-N7 | **Deferred**, acceptable for this PR | RR-SF4. |
| S2-N8 | No change, by ruling F8-S2-3 | Criterion 7 now states the lock. |

**B1, in the three parts asked.**

- *Reproduced on the real screen:* `OnboardingScrollTests.stepChange_startsTheStepAtItsTop` hosts `OnboardingRoot`
  at 402 × 874 pt and `.accessibility3`, scrolls the one `UIScrollView` to its end and changes the step through
  the store. The notes give its failures on the committed screen and on the new screen with the fix taken out
  (209.67 and 168.33 pt down, in both directions). I did not repeat those two runs, which need the product
  file edited; the numbers behave as my replica did.
- *Fixed:* `OnboardingScreen.swift:16`, `:24`, `:31-33`, a `ScrollPosition` sent to the top edge when
  `model.step` changes. Right at every size: there is one layout, and where the page fits the call does
  nothing. Right in both directions: the test goes to step 2, to 3, back to 2, back to 1. Within a step nothing
  moves: a pick does not change `model.step`, and `pick_keepsThePagesPlace` pins it. The failure sentence
  appearing does not change the step either, so the page stays where it is while the pinned part grows.
- *VoiceOver:* the focus move is the page's own `onChange` of the same value (`OnboardingPage.swift:24-26`), and
  both send the lifter to the top, so I see no conflict by reading. By ear it is unverified, as before.
- One thing the hosted test cannot show: it moves the scroll view through UIKit, not with a finger. A drag is
  what updates the binding in the app. S3's UI test should swipe down, tap "Continue" and find the title on
  screen.

**SF5, in the parts asked.** Tokens only (`inkFaint`, `inkMuted`, `hairline`, `hairlineStrong`). Disabled, the
ghost word goes from 51 % ink to 32 % on dark and from 62 % to 32 % on paper, the outline's word from full ink
to 32 % and its rule from 14 % to 8 %, and the filled pill takes `PrimaryButton`'s disabled pair: different in
every style and theme (`disabledPill_looksDisabled`, and plain in the two references I opened). 32 % is below
AA, which WCAG does not ask of a disabled control, and Increase Contrast lifts it to 60 %. `flush` stands the
word at the target's edge and the 44 pt target grows inward; `HorizontalEdge` keeps it right-to-left safe. Six
tests, four tree rows, six references. **No existing reference changed:** the diff holds no other PNG, the
defaults reproduce the old layout, and `PillButtonSnapshots`, the sheets and `LedgerAppKit`'s suites pass
against what is committed.

**The F06 test.** Four reader calls gain the opt-in or the parameter that carries it; no expectation moved
(`:133`, `:138` are as they were). The helper's other callers (`:80`, `:151`) and the `ideal` read (`:137`) keep
the default and still fail loudly on a scroll view.

**References.** Twelve re-recorded, all of them states that draw "Back" (days 2, program 6, six days 2, failed
2), at the heights they had; the six `goal` references are untouched, which shows that the page and the pinned
part draw what the old screen drew. Six new for `PillButtonStatesGallery`, 96 KB. Nothing else.

### The convention as built

`OnboardingScreen` is 35 lines: the pinned part under one `ScrollView` around `OnboardingPage`, bounce by size,
no second layout. Trees, targets, activation and the 18 references are taken from `OnboardingParts` (the page,
then the pinned part, on the ground) in the test target. The hosted tests of the real screen and root pin one
scroll view, where a step lands, that a pick moves nothing, the pinned part's height and its gap to the edge.
This is the split I recommended, and it is the model I would hand the next lanes.

**The loud reader.** The walk fails the test when a scroll view yields nothing, for all three readers, and
`AccessibilityReaderTests` pin both the failure and the opt-in. Those two expected failures are also the
canary: if a later iOS represents a scroll view differently, they fail first.

**Can the opt-in be misused?** Yes, by one argument: `screen.accessibilityElements(outsideScrollViews: true)`
returns the pinned part alone with no failure, and a table written from it pins half a screen. The name, the
comment and the doc say not to. That is as much as an argument can do; the rest is review. Two small
additions would help: RR-N3, and a line in the convention that the reviewer confirms each use, as for the
audit's exemptions. Today `grep -rn outsideScrollViews LedgerKit` finds the reader, its tests and F06's one
test.

### New findings

**Should fix, in this slice**

**RR-SF1. The convention's text is onboarding's case, and three cases the next lanes meet are open or read
the wrong way.** `docs/testing-strategy.md:234-255`.
- *Pinned parts above the page.* "Taken from the page followed by the pinned parts" is onboarding's order. A
  workout screen with a bar pinned above and a button pinned below reads bar, page, button.
- *A sheet whose rows scroll.* The opt-in's one example is "a sheet's title over its scrolling rows" (`:254`).
  F10's swap sheet has exactly that shape, and its implementer could read the sheet with the opt-in and never
  pin the rows. F06's test is about `SheetChrome`, which does not own the rows; a feature's sheet does.
- *A scroll view inside a page* (a row of filters that scrolls sideways; a `List`, which is a scroll view).
  "Never a scroll view" forbids it, the loud reader then fails the page's tree, and the opt-in is "never the
  way to read a page". The text gives no way through.
- *The model is not named.* Rule 7 in F08's notes names `OnboardingScreen`, `OnboardingPage`, `OnboardingFooter`
  and `OnboardingParts`; the doc, which is the source for the other lanes, names only `DesignGallery`.

*Fix:* four sentences in §2.6. "…are taken from the pinned parts and the page, stacked in the screen's
reading order, in a `<Screen>Parts` view in the test target (onboarding: `Support/OnboardingParts.swift`)." "A
feature's sheet whose content scrolls is a screen that scrolls and is split the same way; the opt-in is for a
test of the frame alone." "Not settled: a scroll view inside a page, a `List` included. The first slice that
needs one raises it with the orchestrator before writing it." "The reviewer confirms each
`outsideScrollViews: true`."

**RR-SF2. Nothing in the implementer's suites now activates a control through the real root or reads what
the root opens on.** `LedgerKit/Tests/FeatureOnboardingTests/OnboardingRootTests.swift` (the two tests removed
at `1efaf08:56-96`); `tasks/features/F08-onboarding/implementation-notes.md:1235-1236`.
- `root_opensOnStepOne` and `root_taps_pickAndStep` were the tests of the three pass-throughs (`store.send` to
  the screen, the screen's `send` to the page and to the pinned part). They went because they read the root
  with the reader. Every remaining root and scroll test sends actions to the store directly. Until S3's UI
  test exists, a screen that handed its pinned part a dead closure would pass the PR lane.
- The pinned part stands outside the scroll view, so this half can stay in the PR lane, and it is the opt-in's
  proper use: host the root, read with `withLiveAccessibilityElements(outsideScrollViews: true)`, activate
  "Continue" twice, expect the store on step 3 and the button reading "Start training"; activate "Skip setup",
  expect one attempt. About fifteen lines.
- The notes' "Criteria → tests" table still names the two removed tests for criteria 1 and 2.

*Fix:* that one test, and the table's two rows. If the tester's close-out already taps the root's pinned part,
this is closed by it and only the table remains.

**Should fix, for the chore, before the next lane's first store and first root test (not this PR)**

**RR-SF3. The PR lane cannot see a log line, so SF2's two fixes are pinned at night only.**
`LedgerKit/Sources/FeatureOnboarding/OnboardingStore.swift:104-105`, `:137-140`;
`LedgerKit/Tests/FeatureOnboardingTests/OnboardingStoreTests.swift:77`, `:86`;
`LedgerKit/Sources/LedgerDependencies/LedgerLogger.swift`.
- By reading: take out `catch is CancellationError` and `loadUnits_cancelled_keepsTheDefault` still passes (it
  asserts the same state as the failure case, and the test logger discards); take out the new log line and
  `save_failingOnACancelledTask_isNotShown` still passes. The implementer says as much.
- Is that acceptable? For this slice, yes: a log line is diagnostics, the nightly test proves it on both
  platforms, and a regression is caught within a day. As the standing answer for every store of M1, no.
- The cheap way: the implementer is right that nothing can receive an `OSLogMessage`. But both of the store's
  lines are a fixed sentence and `String(describing: error)`, all public. A method of `LedgerLogger`'s own for
  that shape, `failure(_ what: String, _ error: any Error)`, which writes the same line and also hands
  `(category, text)` to an optional sink that `category(_:)` carries along, with `LedgerLogger.recording { … }`
  for tests, is about twenty lines of `LedgerDependencies`. Stores call it; the PR lane then asserts "once,
  under the module's category, never for a cancellation" in microseconds, and the log read stays nightly as
  the end-to-end check. Lines that need other privacy keep `logger.log`.

**RR-SF4. The convention asks every scrolling screen for a hosted test, and its kit is one feature's test
support behind `@testable import`.** `LedgerKit/Tests/FeatureOnboardingTests/Support/Hosted.swift:2`, `:12-55`.
- N7's deferral was reasonable when the helper served one suite. Since this round, `Hosted.view`,
  `scrollViews(in:)`, `settle(_:)` and `until(_:)` are what "a hosted test of the screen or its root" is written
  with (`docs/testing-strategy.md:243-246`), and the doc names no helper.
- Acceptable for this PR. Not acceptable later than F09's or F10's first hosted test: that lane would copy 56
  lines and a second `@testable import`.

*Fix:* move the four functions into `LedgerSnapshotTesting` as public API, in the chore; this target then
drops the file. One sentence in §2.6 names them.

**Nit**

**RR-N1. A `CancellationError` on a task that was not cancelled is shown and not logged.**
`OnboardingStore.swift:136-146`. The two tests (the error's type for the log, the task's flag for the screen)
leave that corner: the phase becomes `failed` and nothing is written. No store here throws it that way, so it
is a corner on paper. *Fix:* log when the error is not a cancellation or the task is not cancelled.

**RR-N2. The new known limit has no limit case.** `docs/engineering-standards.md:362-366` adds
`toastLogger.category("…")` to the list whose every entry "is kept as a `limit` test";
`LedgerKit/Tests/LedgerAppKitTests/CopyAuditLimitTests.swift:26` has the level call only. *Fix:* one line
beside it.

**RR-N3. The reader's failure message ends on the opt-in without its condition.**
`LedgerKit/Sources/LedgerSnapshotTesting/AccessibilityElements.swift:115-123`. The message is otherwise what an
implementer needs: it names the class, says what to host and cites the section. Its last sentence is the first
thing a hurried reader will try. *Fix:* end it "…with `outsideScrollViews: true`, which is never the way to
read a page: what scrolls is then missing from the result."

### What the Today and workout implementers must be told

1. **Copy the four files, not the old screen:** `OnboardingScreen` (layout only), `OnboardingPage` (everything
   that scrolls, no scroll view), the pinned part, and in the test target a `<Screen>Parts` that stacks them
   in the screen's reading order on the ground. Previews keep drawing the real screen.
2. **Trees, targets, activation and every reference come from `<Screen>Parts`.** Never hand the screen or the
   root to the reader; it will fail the test and say so.
3. **One hosted suite per scrolling screen on the real screen or root:** exactly one scroll view; where each
   change of content lands (a new page at its top, a change within the page nowhere); the pinned parts at
   their full height on a 375 × 667 pt window at accessibility5. Use `Hosted` once it is in
   `LedgerSnapshotTesting` (RR-SF4); do not copy it.
4. **Where a change lands is a `ScrollPosition` and an `onChange` of a value in the model,** as
   `OnboardingScreen.swift:16-33` does it, with `.scrollBounceBehavior(.basedOnSize)` for a page that can fit.
   No `ViewThatFits`, no second layout.
5. **A hosted window has the simulator's safe area, not its size's:** 62 pt at the top in both sizes, 34 pt at
   the bottom only when the window reaches it (measured). Read `view.safeAreaInsets`, as onboarding's tests do;
   a 375 × 667 pt window is 42 pt shorter of room than a real iPhone SE, which errs on the strict side.
6. **`outsideScrollViews: true` is for the pinned parts of a real screen** (RR-SF2's test) or a frame that does
   not own its rows (F06's). Never for a page, and a feature's sheet is a screen (RR-SF1).
7. **A scroll view inside a page, a `List` included, is not settled:** ask before writing one (RR-SF1).
8. **The nightly UI test is part of the screen's slice or the one that wires it:** the stops in the table's
   order at an accessibility size, and one real swipe before a change of content.
9. **A store logs under `logger.category("<module>")`, never logs a cancellation, and proves it at night until
   RR-SF3 lands.** A `catch` around a read that a `.task` can cancel starts with `catch is CancellationError`.

### What I did not check

- **The scroll test failing without the fix.** I may not edit product code; the two failing runs are the
  implementer's.
- **VoiceOver by ear,** a finger's drag, and the stops' order inside the real scroll view: S3's.
- **The gate, coverage, watchOS, CI.** Not run. The simulator runs above are the three targets only.
- **The tester's uncommitted close-out,** including whether it restores a tap through the root (RR-SF2) and
  whether its moved tests pass. My repetition and logging runs compiled its in-progress files; I did not read
  them.
- **Bold Text and Increase Contrast on the new pill states,** and right-to-left for `flush`.
- **The new references beyond the four I opened,** other than by their suites passing.
- **F09's and F10's notes:** rule 7 says the same text is in them; this commit touches F08's only.

## Slice S3 — review (G3 reviewer, 2026-10-05)

Reviewed: `git diff 4a59443..aff5855`, 23 files, 49 product lines (`RootGate.swift`, `MainRoot.swift`,
`AppRoot.swift`). The tester's uncommitted files were not read.

### Verdict

**Approved: 0 Blocking, 4 Should fix, 5 Nit.** The gate is sound: I found no order of the launch's pass, the
store's first answer and the scene's phases in which the wrong screen is drawn. The UI tests mean what they say.
What is left is one line of criterion 5 that no test runs (S3-SF1), the rebase onto F10 S2, which changed the call
the retry and the gate both make (S3-SF2), a launch figure that changed meaning without a doc saying so (S3-SF3)
and one wrong sentence in the hand-off to F14 (S3-SF4).

### What I ran

- `/code-review` at effort high on the diff (it ran as a background fork): 8 candidates, each checked below.
- A standalone probe on this toolchain (Swift 6.4), outside the repo (scratch `f08s3-g3/probe`), for two facts:
  what a cancelled `for await` over an `AsyncStream` still hands its body (S3-N1), and whether `@Observable`
  notifies on an assignment of the same value (it does not).
- Read, not re-run: the implementer's `mut.log`, `host-mutants.log`, `final.log`, `b1.log`, `e1.log` and the two
  frame strips of its launch recordings (scratch `f08s3/`), and the orchestrator's gate log (`check.sh OK`,
  `GATE_EXIT=0`). They say what the notes say.
- **No package test and no simulator run of my own.** No suspicion needed one, and the tester's `swift test` was
  running in this worktree's build folder while I worked.

### Should fix

**S3-SF1. The line that hands onboarding its retry is run by no test, and its mutant survives**
(`LedgerKit/Sources/LedgerAppKit/MainRoot.swift:44`; criterion 5).

- *What.* `OnboardingRoot { await composition.resume(in: .active) }` is this slice's only product line for
  criterion 5. `OnboardingRoot {}` in its place passes every test and the gate (the notes say so). So does
  `OnboardingRoot()`: `OnboardingRoot.swift:20` defaults the argument to nothing, so a later edit of `content` can
  drop the retry with no compiler error.
- *Why it matters.* Bounded, which is why it does not block: without the line, after a first launch whose seed
  failed, "Retry" fails every time until the lifter leaves the app and comes back (the launch's own foreground
  retry), and nothing on screen says so. Standards §12 asks for a test or a screenshot per criterion; this one is
  held by reading.
- *Fix.* A named item with an owner, closed before M1's exit, by whichever of these lands first:
  1. With the chore's shared `Hosted` (RR-SF4) and recording logger (RR-SF3), a hosted root test in
     `LedgerAppKitTests`: a database whose seed a trigger refuses (as `failedSeed_isRetriedByTheCallRetryMakes`
     arranges it), `AppRoot(composition:gate:)` at `.onboarding`, activate "Skip setup", await the recorded
     failure, drop the trigger, activate "Retry"; then `gate.change(from: .onboarding) == .main`,
     `composition.isCatalogSeeded`, and the seed's events in the harness's log reading began, failed, began. The
     wait for the failure is the only step that needs the logger; the rest is observable today.
  2. With F15's launch modes, a UI test whose launch makes the first seed fail: "Skip setup", `onboarding.error`,
     "Retry", Today. It runs the real line in the real app.
  The same shared `Hosted` allows one more test: host `AppRoot(composition:gate:)` with a new `RootGate()` and
  await `gate.answer()`. That puts mutant U3 (the root's task never follows) in the package tests; today only
  `Smoke` sees it.

**S3-SF2. On `main`, `resume(in:)` is no longer the seed and the settings alone; the retry and the gate were
verified against the older one** (`MainRoot.swift:35-38` and `:44`; `RootGate.swift:51-56`; notes, decision 4).

- *What.* The branch is cut from before F10 S2 (#29, `6c5939d`), which added the live workout's recovery to
  `AppComposition.resume(in:)`: `database.run(.resumeWorkout, retrying: phase == .active && hasWorkLeft) { try
  await session.resumeFromStore() }`. After the rebase the gate's first answer waits for the recovery as well,
  and "Retry" runs the recovery again whenever it has work left. I read
  `LocalWorkoutSessionActor+Recovery.swift` on `main`: reads and writes of the local store, queued in the host's
  turn, so it looks bounded. But the comment at `MainRoot.swift:35-38` ("every step it reaches is … a local
  transaction that commits or throws") and decision 4's argument do not cover it, no test of this slice has run
  against it, and the gate ran on `aff5855`, not on the merge candidate.
- *Why it matters.* `OnboardingRoot`'s contract is that `prepareRetry` returns, because every control is disabled
  while it runs. Passing the whole pass makes every step any feature adds to `resume` (F10's now, the device
  steps of F16–F23 later) part of that contract without anyone deciding it.
- *Fix.* At the rebase, one of:
  1. Narrow the retry to the database half, which is ruling O13 as worded ("the launch's seed step"): in
     `AppComposition`, `func retrySeed() async { await database.resume(isForeground: true) }`, passed at
     `MainRoot.swift:44` and called by `failedSeed_isRetriedByTheCallRetryMakes`.
  2. Keep `resume(in: .active)`, re-verify the bound with the recovery in it, and write the rule on
     `AppComposition.resume(in:)` itself: onboarding's "Retry" awaits it with every control disabled, so every
     step in it must be bounded and safe to repeat.
  Either way: run the gate on the rebased commit, and say in decision 4 which was done. **Unverified:** I read
  `main`'s diff of `AppComposition.swift`, `DatabaseLaunch.swift` and the first 90 lines of the recovery file; I
  did not build or test the merge, and `main` also changed `Support/Harness.swift`, which `GateSupport.swift`
  extends.

**S3-SF3. The app's launch figure now stops at the ground colour, and no doc says so**
(`AppRoot.swift:30`; `AppComposition.swift:109-117`; `docs/architecture.md` §14 and §15).

- *What.* `rootAppeared()` fires on the root's first appearance. Before S3 that frame was the tabs with Today;
  now it is `.loading`'s ground colour, on every launch. So decision #30's figure (Diagnostics, the log line, the
  nightly `LaunchPerformance` attachment) no longer includes building either real screen, the launch's pass or
  the gate's read, while architecture §15's budget is "Cold launch to Today < 600 ms". The notes say this
  ("Launch figures"); architecture §14 and the decision's row do not, and F20/F26 make this figure a pass/fail
  check.
- *Why it matters.* Criterion 9 is met as written (one read, pinned by `observations == 1`; nothing read before
  the database is open). But the one instrument that would show a launch regression behind the gate cannot see
  it: with a program the figure reads 334, 311, 320 ms against 353, 335 before, and it would read the same
  whatever the gate cost.
- *Fix.* Now: one sentence in architecture §14 (the figure ends at the root's first appearance, which since F08
  is the ground colour; the time to the first screen is not measured). For F26 or the chore: record a second
  figure when the gate first answers (a `rootAnswered()` beside `rootAppeared()`, called on `follow`'s first
  value), show both in Diagnostics, and hold the second to §15.

**S3-SF4. The hand-off to F14 says "Retry" reseeds a deleted catalog; it does not**
(`tasks/features/F08-onboarding/implementation-notes.md:2294-2295`; `DatabaseLaunch.swift:115-116`, `:131-136`).

- *What.* "The catalog must be seeded again before the lifter can finish onboarding; if it is not, onboarding's
  'Retry' runs the seed step." `resume` retries the seed only while `isCatalogSeeded` is false, and nothing sets
  it back to false: after one successful seed in a process, `task(for: .seedCatalog, retrying: false)` returns
  nil. If "Delete all data" removes the catalog's rows, "Start training" fails with `unknownExercise` and every
  "Retry" fails the same way until the app is relaunched.
- *Fix.* Correct the two lines: F14 keeps the catalog's rows, or reseeds itself and owns the launch's flag;
  "Retry" covers only a seed that has never succeeded in this process.

### Nit

- **S3-N1. A cancelled follow can still write** (`RootGate.swift:42-44`; the comment at `:35-37` says "A cancelled
  call changes nothing"). Measured with the probe: a consumer suspended in `next()` when it is cancelled writes
  nothing, but a value already resumed into the task, and one more buffered behind it, are both handed to the
  loop body after the cancellation. They are values the store gave before the cancel, written in order and
  before the next follow's first read, so I found no wrong screen; the sentence is only not true by construction.
  Fix: `guard !Task.isCancelled else { break }` first in the loop, and a test on `ScriptedPrograms`: with a follow
  at `.onboarding`, `set(program)` then `follow.cancel()` with no suspension between, await the task, expect
  `.onboarding`.
- **S3-N2. The helper says only yes or no** (`Apps/LedgerUITests/Support/LaunchedApp.swift:22-29`). Under U1, ten
  tests failed with the same bare "XCTAssertTrue failed" at their helper line (`mut.log`). The helper is on the
  path of eleven of the fifteen UI tests, the PR lane's `Smoke` among them, and of `LaunchPerformance`'s report,
  so when it breaks the first question is which wait failed. Fix: return that (an enum, or a thrown error that
  reads "onboarding.skip did not appear" or "today.title did not appear after Skip setup; onboarding.error
  shown: …"), and have `LaunchPerformance` attach it where it now returns in silence.
- **S3-N3. `TabsAdversarial.launch` still builds its own arguments**
  (`Apps/LedgerUITests/TabsAdversarial.swift:16-17`). Right for a one-line sanctioned edit. But `LaunchedApp.swift` calls itself the one place that knows how a UI
  test starts, and F15 will change `fresh()`. The tester moves it to `XCUIApplication.fresh(arguments)`, or F15
  is told (below).
- **S3-N4. `docs/testing-strategy.md:310` still lists `Onboarding.dynamicTypeXL`** among the concrete names. The
  slice built it as `test_voiceOverReadsEachStepInOrder_insideTheScrollView_atAnAccessibilitySize` and
  `test_eachStepOpensAtItsTop_atAnAccessibilitySize`. Replace the entry.
- **S3-N5. Architecture §4 does not say what the root shows when the active program cannot be read**
  (`docs/architecture.md:165-170`; `RootGate.swift:45-47`). One clause: the tabs, never onboarding, and it reads
  again at the next change of the scene's phase. F09's Today is built against that rule (below).

### The gate

**Sound.** `destination` has three values, only `follow` writes it, and it has no value between `.loading` and
the store's first one.

- **No flash, in any order.** The first read is awaited after the launch's pass in one call
  (`RootGate.swift:39-42`), so "the store answers before the pass returns" cannot happen; the first value is a
  fresh read of the database, so it is the right one. Phase changes in the first second (the scene going
  inactive to active) cancel one follow and start another: the old one writes nothing more of consequence
  (S3-N1), the new one joins the launch's running steps and reads anew, and both give the same answer. Pinned by
  `untilTheLaunchReturns_staysLoading` (0 reads before, 1 after, both answers), `relaunch_withAProgram_answersMainFirst`
  and `firstFrame_isTheGroundAlone`; the strips of the two recordings show white, ground, onboarding on a fresh
  install and white straight to Today on a relaunch, with no frame of the other screen (simulator only).
- **When the observation ends** (a read that failed) the root shows the tabs, and it reads again only at the next
  change of the scene's phase (`afterAFailedRead_theNextFollowReadsAgain`). A lifter with no program whose read
  fails once is on the tabs until they leave the app and return; mid-onboarding, the step and picks are lost. I
  accept the choice: the alternative (stay on onboarding with no observation) strands the lifter on an inert
  screen after the save, and the failure needs an I/O or decoding error on a single-connection queue. A decoding
  error repeats, and the tabs are then the right place.
- **Database unavailable wins.** `AppRoot`'s switch draws decision #29's screen and never builds `MainRoot`; the
  follow gets no store and reads nothing; a late open goes can't-open screen, ground, answer
  (`databaseNotOpen_staysLoading_untilItOpens`, and F09's three tests unedited).
- **Background and foreground.** Each change of phase restarts the task; `destination` is kept meanwhile, so
  `OnboardingRoot` keeps its place, step and picks (`cancelled_keepsItsDestination_untilTheNextAnswer`). Cost: one
  `resume` and one read per change, two or three per round trip.
- **Isolation, ownership, lifetime.** `@MainActor`; the gate starts no task; SwiftUI owns the one that follows
  and cancels it with the view; a cancelled stream stops its database observation. One precision: a follow
  cancelled while it awaits the launch stays until the launch's running steps end (it awaits their tasks, which
  do not answer to cancellation), then returns at the guard without reading. Bounded, and it writes nothing.
- **Nothing is read before the database is ready:** the store is taken from `composition.stores` only after
  `resume` returns.

### Where it lives

**Fits architecture §4 as F09 S1 wrote it.** `MainRoot` keeps its three members; the branch is in `content`;
`body` is untouched; the §4 bullet is updated and accurate. The gate as `AppRoot`'s `@State` is the right owner:
one task awaits the launch and then follows, which is O12 with no second caller of `resume`.

The internal `init(composition:gate:)` does not mislead. Every injected gate reached its answer through
`RootGate.follow(_:in:)` itself (`Harness.gate(following:)`), so the tests that use it check what `MainRoot`
draws for a real answer. The one thing injection skips is `AppRoot`'s task calling `follow`; mutant U3 shows
`Smoke` kills that in the PR lane. A package test for it is cheap once `Hosted` is shared (S3-SF1).

`AppRootTests.labels` reads with `outsideScrollViews: true`: confirmed as the reader's first named use (the pinned
buttons of a real root, testing-strategy §2.6).

### Retry

- **Is it the launch's seed step?** On this branch, yes in effect: `resume(in: .active)` restarts the seed only
  while the catalog is unseeded, does not rerun the settings, and activates the companion once. On `main` it is
  more than that (S3-SF2).
- **Does it always return?** On this branch, yes: one transaction that commits or throws, behind SQLite's busy
  timeout. `failedSeed_isRetriedByTheCallRetryMakes` shows it return with the seed failed and with it done.
- **Can it run while the launch's own pass runs?** Yes (a phase change during a retry), and safely:
  `DatabaseLaunch.task(for:)` checks and starts on the main actor with no suspension between, so both callers
  await one task and no step begins twice; the companion's check-and-set has no suspension either. A retry that
  joins a running seed returns with that attempt's outcome, which is an attempt begun in the same moment.
- **The line no test runs:** S3-SF1.

### The UI tests

- **The helper** is mechanically robust: a pinned button found by identifier, two 10 s waits, and it passed at
  the largest text size (`TabsAdversarial`'s AX5 launch). It is also, by ruling O11, one place where eleven UI
  tests fail together when onboarding's identifier, the generator, the save or the gate breaks. That is the
  accepted price until F15; what is missing is the reason in the failure (S3-N2).
- **`Onboarding` against criterion 8 and the convention: met.** The stops of each step in order with their
  selected and enabled states at AX3, read from the running app's tree; a tap on a control of the page inside the
  scroll view; steps 2 and 3 at their top after a real swipe, with a control that the swipe moved the title;
  "Start training" on Today with the tab bar and the rows in the database (1, 8, 3, 15). "Inside the scroll
  view" is true of the app, not asserted by the walk (`stops(under:)` flattens the tree); the top-of-step test
  asserts the one scroll view. Three green runs in the logs (`b1`, `e1`, `final`), no repetition run.
- **"Shown to fail" is convincing for what it claims.** U1 shows each moved test is closed behind the root's
  branch: ten fail at their helper line and `Smoke` at its first wait, which says nothing new about their own
  assertions, and those are untouched. U3 shows `Smoke` guards the root's task in the PR lane. U2 kills each `Onboarding` test for its own
  reason. No UI test can see a flash (U2's fourth change); the package tests carry that claim.
  `LaunchPerformance` cannot fail by decision #30 and under U1 loses its attachment in silence (S3-N2).
- **`Smoke` renamed.** The PR plan selects the class, no script or plan names the method, and §2.7 has the new
  name. The remaining `launchesToToday` are the watch's test, which is right, and history in F07's and F09's
  notes.

### The sanctioned edits

**As sanctioned.** `TabsAdversarial.swift`: one line added in `launch(_:)`. `AppRootAdversarialTests.swift`: the
set-up of two tests and `throws` on each; every expectation is byte for byte what it was. Both still host
`AppRoot` and reach the shell again, through a gate that got to `.main` by the root's own call.
`root_idleAndReady_readToVoiceOver` reads Today's header through `AppRoot`, `MainRoot` and the tabs, and failed
under U1. `root_ready_draws` shows only that the shell does not trap, as before the edit.

### The hazard: a pixel buffer compared inside `#expect`

- **This slice's tests: none.** `AppRootTests.swift:69-72` compares outside and expects two `Bool`s; its
  `#require`s unwrap an optional, which records nothing when it passes and `nil` when it fails.
- **Elsewhere in `LedgerAppKitTests`, for the chore:** `Adversarial/AppRootAdversarialTests.swift:46` and `:47`
  (seven cases each), `:61` (one case) and `:73` (two cases). Nothing else: `AppTabsTests.swift:82` compares one
  `Pixel`.
- **Seen in `LedgerDesignTests` while searching, not an exhaustive list:** `BoldTextTests.swift:24`,
  `MotionTests.swift:64`, `PillButtonStateTests.swift:33`, and in `Adversarial/`:
  `SnapshotHarnessAdversarialTests.swift:39`, `NativeLineHeightAdversarialTests.swift:51` and `:62`,
  `LedgerFontSizingAdversarialTests.swift:159`, `Slice3CloseoutAdversarialTests.swift:105`,
  `ArchivoFontAdversarialTests.swift:101`, `:102`, `:118`, `:119`, `:136`.
- **On the cure** (open question 5): prove it with a red run and the bundle's size. I did not check Swift
  Testing's source; if a failure also records `String(reflecting:)` and the value's mirror, a
  `CustomTestStringConvertible` alone will not be enough and `PixelBuffer` needs a short `debugDescription` and a
  mirror with no children too.

### The seven review points

| # | Point | Result |
|--:|---|---|
| 1 | Module boundaries | Pass. `LedgerAppKit` imports `FeatureOnboarding`, an edge `Package.swift` has; `Package.swift` is untouched. The test target reaches `FeatureOnboarding` and `GRDB` through `LedgerAppKit`, as `Harness` already does. |
| 2 | Concurrency | Pass. Main actor throughout, no unstructured task in product code, no new `Sendable` claim, nothing reads the clock. S3-N1 is a comment that overstates. |
| 3 | Error handling | Pass. A failed read is logged by the store and shown as the tabs; a failed seed still answers. Nothing swallowed. |
| 4 | Design fidelity | Pass. The one new thing drawn is `LedgerColor.ground`; the four screenshots match criteria 1 and 3 in light and dark (step 1, bars 1 of 3, "Both, honestly" ticked, no tab bar; Today with the tab bar, Today selected). |
| 5 | Accessibility | Pass, with one thing unverified. While the ground alone is shown VoiceOver meets nothing, as in the root's idle state, and nothing is announced when the screen arrives; by ear this is not done. |
| 6 | Test quality | Pass. Behaviour, not implementation; no sleep and no polling (`Observations`, a latch); time limits on every suite. The gap is S3-SF1. |
| 7 | Brief compliance | Pass. Each of the ten criteria has a test or a screenshot; criterion 5's wiring is by reading (S3-SF1). |

Also checked: no new string, catalog key or exemption; no lint suppression, `try?`, sleep or skipped test in the
added lines; nothing compressed; nothing outside the slice (the brief's criterion 8 is the orchestrator's
amendment).

### `/code-review` candidates

| # | Candidate | Disposition |
|--:|---|---|
| 1 | A stream that ends shows the tabs, so one failed read on a fresh install strands the lifter | Accepted trade-off, pinned by tests ("The gate"); S3-N5 for the doc. |
| 2 | Every launch holds the ground colour until the whole pass returns | Ruling O12; its cost to the launch figure is S3-SF3. |
| 3 | The router survives a return to onboarding | Unreachable until F14; in the hand-off below (the notes' open question 2). |
| 4 | The gate observes the whole program and reassigns on every edit | Dismissed. An equal assignment does not notify on this toolchain (probe); the read is the one Today will make anyway. |
| 5 | Retry is wired to the whole pass under a claimed phase and can overlap the root's task | The overlap is safe ("Retry"); the breadth is S3-SF2. |
| 6 | Onboarding is keyed on "no active program", not "no program" | The brief's rule (criterion 4); in the hand-off below for the features that can leave no active program. |
| 7 | A cancelled follow can apply a buffered value | Confirmed by probe, harmless as far as I can find: S3-N1. |
| 8 | `TabsAdversarial` does not use `fresh(_:)` | S3-N3. |

### What F10's cover slice, F14 and F15 must be told

**F10 (the cover).**
1. `MainRoot.content` is now a conditional view. A presentation modifier put on it in `body` may be rebuilt when
   the branch changes, and F10 S2's recovery makes that the launch path: a workout recovered at launch presents
   while the gate is `.loading`, then the branch becomes the tabs. I have not proven what SwiftUI does there.
   Prove it with a hosted test (present during `.loading`, flip to `.main`, the cover is up, once), or wrap
   `content` in one stable container in `body` first.
2. Decide what the cover does while the root shows onboarding or the ground (a workout started from the watch
   with no active program on the phone; the active program deleted mid-workout).
3. After the rebase the gate's first answer waits for the workout's recovery, and onboarding's "Retry" runs it
   again (S3-SF2). Anything added to `AppComposition.resume(in:)` holds the first screen back and must be
   bounded.

**F14 ("Delete all data").**
1. Deleting rows through the open database is followed as it is: the root shows onboarding on step 1. Replacing
   the file or the stores is not: the gate observes the queue it took when its follow started.
2. "Retry" does not reseed a catalog that was seeded once in this process (S3-SF4): keep the catalog's rows, or
   reseed and own the flag.
3. The router is `MainRoot`'s state and survives a return to onboarding: after a second onboarding the tabs come
   back where they were, not on Today. Reset it when the gate leaves `.main`, with the test that reaches it.

**F15 (the UI tests' launch modes).**
1. `skipSetupToToday()` is the one place to replace, except `TabsAdversarial.launch`, which builds its own
   arguments (S3-N3).
2. A seeded program must be written before the launch's pass returns, or the gate answers onboarding first.
3. The helper should say which wait failed (S3-N2). A mode whose first seed fails gives the UI test that closes
   S3-SF1. A mode that keeps the database gives the relaunch test criterion 8 handed to a package test.
4. No UI test audits onboarding's accessibility yet.

**Others.**
- **F09 (Today):** Today's "no active program" state is now reached only when the active program cannot be read
  (the root shows the tabs) and for the instant before the gate flips. It must draw something sane there.
- **F11, F24, F28:** any flow that leaves no active program, even between two transactions, puts the lifter on
  full-screen onboarding at once, with History, Library and Settings out of reach until a program is saved.
  Replace an active program in one transaction.
- **F26 / F20:** the launch figure ends at the ground colour (S3-SF3).

### What I did not check

- **Any test run of my own,** on the host or the simulator. Green and red results are the implementer's logs and
  the orchestrator's gate log, which I read.
- **The rebase onto `main`** (S3-SF2): not built, not tested.
- **VoiceOver by ear,** a real device, and any launch timing on a device. The no-flash evidence I looked at is
  two simulator recordings.
- **Whether SwiftUI restarts `AppRoot`'s task when its own switch changes branch.** I argued both ways are
  correct; I did not observe which happens.
- **What a presentation modifier on `MainRoot.content` does across a change of branch** (F10, point 1).
- **Stability of the three `Onboarding` UI tests beyond three green runs:** no repetition run exists.
- **Whether the nightly plan is run on a schedule anywhere,** coverage, watchOS, CI.
- **Swift Testing's failure record** (the hazard's cure), and the tester's files.

## G3 review, round 2 (2026-10-20): after merging `main` (761db7e, 4a9e2b0, aaea03c, ca5b507)

Read-only review; no tests run. **APPROVED**, no must-fix.

**Merged tree:** coherent.
- `MainRoot` carries F08's `content`/`newRouter` beside S14's `onProgramRoute`.
- `AppRouter.programWeek` goes with the old router when onboarding appears (R4).
- `AppRoot`, `AppComposition` and `LaunchedApp` are unchanged by the merge.
- S7b's `Smoke` and `WorkoutSaveFailure*` edits sit inside seeded launches.

**SF1:** done in code.
- The seed line is in `BuilderApp.launch` (Builder.swift:154).
- `Tabs` is stronger: the eyebrow plus `Program name` == "Upper / Lower", which ProgramTemplates+Splits.swift:91 confirms.
- `TabsAdversarial` is equivalent.
- The AX5 exclusion's new reason holds.

**Launches:** every launch carries the seed line except the `fresh()` ones (Onboarding, OnboardingAdversarial, Smoke's fresh install, DebugMenu, LaunchPerformance), which is correct.

### Should fix

**SF-A.** `AppRootResetAdversarialTests` (:23, :39, :49; AppRootGateAdversarialHosting.swift:46-48).
- `labels == []` on `.program` is exactly Today's reading. Only `router.selectedTab` proves the tab, and that reads state, not what is drawn.
- `tabsAgain.isTabs` (:49) catches a selection that survived onto Program only while the builder is still `.loading`. That is 2 of 6 iterations.
- Fix: put the drawn tab bar's selection in `GateShown`, require `selected == "Today"` in `isTabs`, and expect `shown.selected` at :39 and :82. Add `router.selectedTab == .today` after :49, and update notes :1066-1070.

**SF-B.** The nightly `TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` is red with 26 builder issues (contrast, partial Dynamic Type, clipping), the first audit of the builder at week 5.
- It needs a recorded ruling and an owner before the push.
- Say what the re-run covered: only Builder and Tabs, 7 of 7.

### Nits
- **N1:** delete the untracked `Apps/LedgerUITests/ZZTemporaryScreenshots.swift`. The groups are synchronized, so it would compile and run. Stage named paths.
- **N2:** notes :1095 should say 19 launches in 15 files; :1103 should point to the new "Sanctioned edits after merging main…" section.
- **N3:** hand the `Builder.test_wrappedName_…:80` "A l" flake to F11's test findings.
- **N4:** comment `GateTabsStandIn`'s `Text("Program")` (AppRootGateAdversarialHosting.swift:78) as the pre-S14 placeholder.

### Orchestrator's ruling on SF-B (2026-10-20)

Exclude nothing. The 26 issues go to F11's test findings as a follow-up slice with an owner, and the nightly stays red on that one test until it lands. F09 measured Today's audit issues the same way before excluding any.

**Taken in `2aac7a3`:**
- SF-A: `GateShown.selected`, `isTabs` needs Today selected. Mutant `MainRoot .onAppear {}` was caught.
- SF-B: F11-S14-5 (the 26 audit issues) and F11-S14-6 (the "A l" flake) are in F11 test-findings.
- N1, N2 and N4 are done.
- The dark "Today after Start training" screenshot could not be taken: the simulator draws light with the appearance set to dark (the same environment issue as the accent test).
