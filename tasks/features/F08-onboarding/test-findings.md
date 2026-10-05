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

## Slice S2 — round 1 (G2 tester, 2026-10-05)

Independent adversarial pass over `feat/F08-s2-onboarding-ui` at `9cc5d54` (the three-step onboarding screen in
`FeatureOnboarding`, not yet in the app). I read the brief with its S2 amendments and "Copy (exact)", standards
§3–§5, §7, §8, §12, product spec §3.10 and §6.7, decisions #17, #18, #28 and Naming, and the testing strategy,
then the module's declarations and doc comments. I have not read `implementation-notes.md`. No product code, no
test of the implementer's, no snapshot reference, no test plan and no project file was edited; nothing was
committed.

Limits on that independence, for the record:

- The `grep` I used for declarations also printed a few body lines of `OnboardingStore` (the guard of `save`, the
  order of the reads in `program(for:)`, the two log messages) before my tests existed.
- My twelve suites were written and run on the host, and once on the simulator, before I read any other function
  body. That simulator run failed in my own layout harness, and I read the screen, the root, the store and the
  presentation to see why. The layout suite as it stands, the cases above the matrix's largest text size and the
  test with calendars that are not Gregorian were written after that. I read the implementer's tests last, only to
  judge them.

**Result: two low-severity bugs, two questions for the product owner, two test-quality findings.** 67 tests of
mine in 12 suites. On the simulator (PR lane) 64 pass, 1 fails (F8-S2-1) and 2 are skipped as nightly-only; in the
nightly lane on the host one of those two fails (F8-S2-2). Criteria 1 to 9 and 11 held under everything I threw at
them, and criterion 10 held up to its own bound.

### Findings

1. **F8-S2-1 — bug, low. At the largest text size on the smallest phone, the failure sentence is cut.**
   - *Line violated:* standards §7, "Dynamic Type supported up to accessibility sizes", and the brief's body,
     Non-functional: "Dynamic Type to AX5 … (no truncation)". It is **outside criterion 10's bound** ("up to the
     largest accessibility size the snapshot matrix has", accessibility3), and the S2 section wins where the two
     disagree, so the orchestrator may rule this a question instead. Criterion 10 itself holds.
   - *Repro:* `OnboardingLayoutAdversarialTests.everything_beyondTheMatrix_isStillWhole`, case `failed-6-kg, SE
     375x667, dark-accessibility5`: `OnboardingState(step: .program, days: .six, units: .kg, phase: .failed)` in
     a 375 × 667 pt window (iPhone SE, 2nd and 3rd generation, which iOS 26 runs on) at `.accessibility5`. The
     nightly lane also runs `failed-goal` there, which fails the same way.
   - *Expected:* "Couldn't save your program. Try again." whole, as it is with unlimited height (187.3 pt, three
     lines).
   - *Actual:* 125 pt, two lines, ending in an ellipsis: "Couldn't save your program. Try aga…" (picture:
     scratch `f08s2-g2/renders/failed-6-kg_SE-375x667_dark-accessibility5_top.png`). VoiceOver still reads the
     whole sentence. Accessibility4 on the same phone, and accessibility5 on 375 × 812 and 402 × 874, are whole.
   - *Likely cause, for whoever fixes it:* the pinned footer is an ordinary child of the screen's `VStack`, which
     offers it half the height (323.5 of 647 pt) before the flexible page above it; with a three-line sentence
     the footer needs a little more, and a `Text` gives up a line. Every later screen that copies "page above,
     pinned buttons below" inherits this.
   - This test fails in the PR lane on purpose (a test that exposes a bug stays failing), so **the iOS plan of
     the full gate is red until this is fixed or ruled out of scope**.

2. **F8-S2-2 — bug, low. The module logs under whichever category the injected logger has, not one of its own.**
   - *Line violated:* standards §8, "Logging via `os.Logger` with subsystem `com.petearevalo.Ledger` and a
     category per module".
   - *Repro:* `OnboardingLoggingAdversarialTests.failures_areLoggedUnderTheModulesCategory` (nightly lane: it
     reads the process's log, which takes seconds). A store built with `logger = LedgerLogger(category:
     "adversarial-f08s2")` whose save fails.
   - *Expected:* the line under a category that names the module (`LedgerLogger.category(_:)` gives one and keeps
     a disabled logger disabled).
   - *Actual:* category `adversarial-f08s2`, the injected one. In the app the key's live value is
     `LedgerLogger(category: "app")`, so onboarding's lines would be filed under "app". It is the first feature
     store, so the next ones will copy it.

3. **F8-S2-3 — spec question. After a failed save the picks are frozen.**
   - *Lines in question:* criterion 2, "Steps 2 and 3 have a 'Back' pill; the picks survive going back and
     forth", and criterion 7, "'Retry' … tries again with the same picks". Neither says the lifter may no longer
     change them.
   - *What happens:* while the failure is shown, `canEdit` is false: "Back" and the options are dimmed and send
     nothing. Only "Retry" (the failed attempt again) and "Skip setup" (the default) answer. After a failed "Skip
     setup" on step 1 or 2 the primary button reads "Retry" where "Continue" was, so the lifter cannot go on
     through the steps at all without leaving the screen. The implementer pins this
     (`OnboardingStoreFailureTests.failed_locksThePicksAndTheStep`); my tests accept either answer.
   - *Question:* is that intended, or should "Back" and the picks answer again after a failure (the next "Start
     training" then being a new attempt that still prepares first)?

4. **F8-S2-4 — spec question. A `prepareRetry` that does not return leaves a screen where nothing answers.**
   - *Line in question:* criterion 7, "'Retry' first awaits the `prepareRetry` closure the root was given".
   - *What happens:* during the retry step every control is dimmed, there is no time limit and no way to give up,
     and nothing shows that work is under way (the same is true of a slow save: the button is only dimmed). The
     closure cannot throw, so only the view going away ends the wait.
     `OnboardingFailureAdversarialTests.retry_prepareNeverReturnsUntilCancelled_savesNothingThenAnswers` shows
     nothing is saved meanwhile and that the screen answers again once the task is cancelled.
   - *Question for S3:* can the launch's seed step hang (a locked database)? If so the screen needs a way out, or
     S3 must pass a step that always returns.

5. **F8-S2-5 — test-quality. No test of the slice draws or reads the screen as a phone shows it once it scrolls.**
   - The screen is `ViewThatFits { page; ScrollView { page } }`. The slice's 18 references and its VoiceOver
     trees are drawn at 402 pt and the view's own height (`assertLedgerSnapshot`, `accessibilityElements`), which
     is always the first branch. Testing-strategy §2.5 names `.device(config:)` for screens.
   - The second branch is the common one. Measured in windows of each phone's size and safe area: a 402 × 874
     phone scrolls in every state at accessibility3; a 375 × 667 phone scrolls at the default size on step 2, on
     the five- and six-day lists and in the failure state.
   - My layout suite measures that branch from outside (the pinned buttons, the scroll view's own numbers, and
     pictures I looked at). Its VoiceOver tree nobody has read: see "Not attacked". S3's UI tests are the place:
     one onboarding run on a small phone at a large text size, with the accessibility audit.

6. **F8-S2-6 — test-quality, low. The slice's logging test runs in the PR lane and takes four seconds.**
   - `OnboardingStoreLoggingTests` reads the process's log through `OSLogStore`: 4.1 to 4.5 s on the simulator in
     my three runs of the target (its comment says "about a second"), and 11.5 s on the host, where its
     synchronous read holds the main actor while every other main-actor test waits (my 100 interleavings took
     13.3 s beside it and 2.4 s without it). Testing-strategy §6 puts a test over 2 s in the nightly lane. Mine
     of the same kind is nightly-only for that reason.

Notes that are not findings:

- **"Skip setup" stands on the bottom edge of a phone with a home button.** The footer has no bottom padding, and
  an SE has no bottom safe area: between the descenders of "Skip setup" and the edge of the screen are 2.5 pt at
  accessibility3 and 1 pt at accessibility5 (measured in the pictures). The glyphs are whole.
- **A retry cancelled during its `prepareRetry` still reads the settings and the catalog and draws ids** before
  it notices, just ahead of the write. Nothing is written, as the store's comment promises.
- **The log lines carry the error's description as public text.** Today that is a store's error or
  `unknownExercise("Barbell Bench Press")`: no lifter's data and no product name.
- **A failure's line disappears while the retry runs** and comes back if it fails again, so the pinned part
  changes height twice.

### Attacked and held

Tests are in `LedgerKit/Tests/FeatureOnboardingTests/Adversarial/`: 12 suites, 67 tests, with their support
(probed stores that count, hold and refuse each call; a scene that stands in for the root's task; a stepper;
waits that end on an event or on the test's cancellation, never on time). Expected programs are always
`ProgramTemplates.program` called in the test with the stored settings and catalog and the injected date,
calendar and ids. Expected texts are typed from the brief (`BriefCopy`).

- **Saved exactly right (criteria 4 to 6), 8 tests.** All 16 picks: one program handed to the repository, equal
  to the generator's, active, by one `save` (no `setActive`, no `delete`, no settings write), every id from the
  injected generator. Kilograms with a Sunday week start at Saturday 23:30 in Pago Pago, a Monday start at Sunday
  23:30 in Honolulu and at Monday 00:30 in Kiritimati, each with the calendar's own first weekday set the other
  way: the block starts on the zone's week (2026-09-13, -14, -21). Five device calendars that are not Gregorian
  (Buddhist, Umm al-Qura, Japanese, Hebrew, Persian): still Monday 2026-09-14. A stored catalog whose bench load
  differs from the bundled one: the stored load is saved. A date in 2031. "Skip setup" from each step, in each
  unit, with other picks made. A save before the unit was ever read. Nothing saved, no id drawn, before a tap.
- **Exactly once (criterion 4), 9 tests.** A double tap; every control tapped (and the task run again) while a
  save is held reading the settings, reading the catalog, and inside the write; every control after success;
  "Skip setup" during a save of the picks and "Start training" during a skip (the first tap's program is the one
  saved). The task cancelled while held at each read (nothing written, the same tap then saves one), cancelled
  during a write that still lands (stays saved, nothing answers), cancelled during a write that gives up (nothing
  saved, the screen answers), and run again by a returning view while the cancelled run is still held.
- **Failure and retry (criterion 7), 9 tests, and 2 in the nightly lane.** Each of the four steps failing: the
  brief's sentence, "Retry", nothing saved, no retry step run, the picks and step unchanged. "Retry": the journal
  shows `prepareRetry` started and ended once before any read or write, then one program for the same picks; no
  further prepare after success. An unseeded catalog that the retry step seeds (decision #28's case). Two
  retries failing again, then one succeeding after three prepares. A slow retry step (nothing read or written,
  no tap answers, then one program). A retry step that never returns until cancelled. Stores changed between the
  failure and the retry (catalog seeded, unit now kilograms): the retry uses what is stored then. A failed
  "Skip setup" on each step, and "Skip setup" after a failed "Start training". Logging: one line at error level
  for each failed attempt (settings, catalog, generator, write, a retry that fails again, the unit read when the
  screen opens), none for a cancelled save or a success, no product name.
- **Random walks against a model written from the brief, 2 tests.** Seeds 0 to 99 in the PR lane, 0 to 1,999 in
  the nightly lane (run on the host), 40 taps each, each tap on a control the brief puts on the screen then, 60 %
  of saves failing at a random step; after every tap the step, the picks, exactly one ticked option, the texts
  of the state, the count of stored programs and of retry steps agree with the model. No failing seed. A control
  test shows the walks reach every step in every phase and all 16 kinds of saved program.
- **Random interleavings, 2 tests.** Seeds 0 to 99 in the PR lane, 0 to 1,499 in the nightly lane (host), 45
  moves each: taps, the view going away and coming back (its task cancelled and restarted as `.task(id:)` does),
  and each store call or retry step released one at a time to pass, fail or give up on cancellation. After every
  move: never two programs, never two calls waiting, a stored program means no control can start another, and
  nothing stored with nothing running means the screen answers. At the end: exactly one program, one that was
  asked for, equal to the generator's. No failing seed. A control shows the runs reach a cancelled read, write
  and retry step with each outcome, and a save landing with the view gone.
- **The texts (criteria 1 to 3, 9), 10 tests.** All 480 models (3 steps × 4 goals × 4 day counts × 2 units × 5
  phases): every text is one of the brief's or the Domain's, none is empty, none names the product. Each step's
  title, line, options and buttons, character for character; step 3's sentence for the four splits in both
  units; every day of every split as the Domain's name with " — " drawn as " · " and its line, and the four-day
  rows against §6.7 as the brief corrects it. The bars: three equal segments, `.current` up to the step (the only
  state `ProgressSegments` draws in the accent). Numbers follow the injected locale (`ar_SA` gives Arabic digits
  in the step count and the weeks). The String Catalog's keys are exactly the brief's 31, each sound.
- **VoiceOver (criterion 8, and 2, 3), 8 tests, simulator.** Twelve states at two appearances: the reading is the
  brief's parts top to bottom and nothing else, in the order on screen. The bars are one element, "Step n of 3",
  no button. Each pick is one button "{label}, {sub}" with no value, selected only when picked, exactly one
  selected. Step 3's days are text, and activating one sends nothing. Each control sends its action once.
  During a save, during a retry and after success every control is dimmed and sends nothing. Every control is at
  least 44 pt both ways in all six appearances. The hosted root reads as its screen and its controls reach its
  store (picks, steps, one attempt for three taps).
- **Layout (criterion 10), 5 tests, simulator.** Seven states (step 1, step 2, the four-, five- and six-day
  lists, the failure on step 3 and on step 1) on 375 × 667, 375 × 812 and 402 × 874 pt, each with its own safe
  area, in the matrix's six appearances: 126 cases, all run on the simulator before I narrowed the PR lane to
  twelve of them (the nightly lane runs all). At each phone's width every element is read, lies between the
  edges, overlaps nothing, and every control is 44 pt. On the phone the primary button and "Skip setup" are
  whole, inside the safe area and not squeezed; the page either fits above them with every element at full
  height, or scrolls in one scroll view that ends where the pinned part begins and holds the page's full height.
  Above the matrix, accessibility4 and accessibility5 on all three phones: 42 cases run, 40 hold, and the two
  that do not are F8-S2-1 (the failure state on the smallest phone at accessibility5). I looked at nine of the
  pictures: on the smallest phone at accessibility3, step 1 and the six-day list in light (each at the top and
  scrolled to the end), step 2 and the failure in dark; the five-day list on 375 × 812 in light; and two at
  accessibility5. Apart from F8-S2-1: nothing cut, nothing overlapping, the tick only on the pick, no tick on
  step 3. The other pictures I did not look at; for them the measurements stand alone.
- **The root and its life (criteria 4, 6, 7, 11), 6 tests, 5 on the simulator.** The hosted root reads the stored
  unit by itself and says "kilograms". Three taps on it save one program through its own task. A failure on an
  unseeded catalog shows the sentence; "Retry" awaits the root's step once, then saves. With the view taken away
  mid-save both of its tasks are cancelled, nothing is written and the store is deallocated; the same with
  nothing running; and a store nobody shows is deallocated after a save.
- **The surface and the rules (criterion 11), 6 tests.** A file that imports the module without `@testable`
  builds `OnboardingRoot()` and `OnboardingRoot(prepareRetry:)`. A scan of the sources (comments and strings left
  out): three public declarations, all `OnboardingRoot`'s; no `Date()`, `Date.now`, `Calendar.current`,
  `Locale.current`, `TimeZone.current`, `UUID()`, no `Task` of its own, no queue, timer, lock, singleton,
  `UserDefaults`, `print`, UIKit import, `try!`, `as!` or `@unchecked`; every `try?` explained. A control plants
  each spelling and checks the scan finds it.
- **The implementer's tests, read afterwards.** They assert behaviour: the saved program against the generator,
  one save under held and cancelled runs, the retry's order, the trees as tables. I found no assertion that
  restates the code or that I think is wrong. Beyond F8-S2-5 and F8-S2-6: their expected programs are built from
  the bundled catalog, which cannot tell it from the stored one (mine does), and 4 of the 16 picks are saved.

### Not attacked

- **VoiceOver inside the scrolling branch.** A window of a test process has no scene, and there a SwiftUI
  `ScrollView` hands UIKit no accessibility children (checked on iOS 27.0: a key window, turns of the run loop
  and UIKit's private child lists change nothing). So the tree, the focus and the taps of the page were read
  only where it does not scroll. Where it scrolls I measured the pinned buttons and the scroll view and looked at
  pictures. This is the largest gap of this pass.
- **What VoiceOver is told.** The move of focus to the title on a step change and the announcement of the
  failure cannot be observed in a test process.
- **The real stores.** Everything ran on `InMemoryStores`. GRDB's own answer to a cancelled task, and the time a
  save takes (the brief's 100 ms), are S3's and the integration suite's.
- **The app.** The root's gate, the `prepareRetry` the app passes, the dependencies a store made in the app's
  root gets, and the UI tests are S3.
- **Mutants of the product code** (the rules of this pass forbid editing it), so the two random suites prove
  their reach with control tests instead.
- **Pixels.** I added no reference image. The pictures are in the scratch folder, for eyes only.
- **Other settings and devices:** Bold Text, Increase Contrast, right-to-left, a translated catalog, a real
  phone. Landscape does not apply (the app is portrait only). The module has no watch build.
- **The gate's own checks:** the catalog against the compiler's keys, coverage, and the watch plan.

### Commands and exit statuses

From the worktree root; logs in the scratch folder `f08s2-g2/`. Simulator runs went through the simulator lock
with a script of mine (`sim-run.sh`: the gate's `build-for-testing` and `test-without-building` of the `Ledger`
scheme's PR plan on the iPhone 17, iOS 27.0, with `-only-testing`). **I did not run the full gate; that is the
orchestrator's.**

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FeatureOnboardingTests\.Onboarding\w*Adversarial'` (PR lane; 49 host tests in 10 suites; `host-run-12.log`) | 0 |
| the same with `LEDGER_TEST_LANE=nightly` (2,000 walks, 1,500 interleavings, the two logging tests; `host-nightly-1.log`) | 1: F8-S2-2 alone |
| `swift test … --filter 'FeatureOnboardingTests\|ModuleCopyTests'` (the implementer's host tests, mine and the copy audit: 104 tests in 21 suites; `host-run-13.log`) | 0 |
| `scripts/check.sh --lint-only` (`lint-2.log`) | 0 |
| simulator, `-only-testing:FeatureOnboardingTests/OnboardingLayoutAdversarialTests`, all 126 cases (`sim-4.log`) | 0 |
| simulator, the whole target with the 126 cases and the 42 above the matrix (`sim-6.log`) | 65: F8-S2-1 alone (2 cases) |
| simulator, `-only-testing:FeatureOnboardingTests`, the final state (`sim-8.log`, `sim-8.xcresult`) | 65: F8-S2-1 alone |

What the last result bundle says (`xcrun xcresulttool get test-results summary`): 131 tests, 128 passed, 1
failed, 2 skipped. The 64 of the implementer's all passed, and no reference image changed. Of my 67, 64 passed,
the one that failed is F8-S2-1's, and the two skipped are the nightly-lane logging tests.

For the record:

- Earlier simulator runs failed for reasons of my own, since fixed: `sim-1` and `sim-2` did not compile (a key
  path inside `#expect`), and `sim-3` reported 532 issues, every one from my layout harness: its windows took the
  simulator's own safe area on top of the phone's, and it expected elements inside a scroll view. Three short
  probe runs found out why; the probe is deleted.
- The simulator has not run the nightly lane's larger ranges or my two logging tests: those ran on the host only.
- `tasks/features/F08-onboarding/review.md` was changed in the worktree during this pass. It is not mine; I did
  not read or change it.
