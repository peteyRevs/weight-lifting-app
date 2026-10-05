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
