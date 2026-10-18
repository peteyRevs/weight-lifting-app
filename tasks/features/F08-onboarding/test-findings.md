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

---

> **Carried from the reviewed branches, as of 2026-10-05** (F08 S2/S3 port, ruling R1). The sections below are the
> findings of `feat/F08-s2-onboarding-ui` @ `24b610b` (S2) and `feat/F08-s3-root-gate` @ `7c0b78f` (S3), copied
> unedited. Their line references, commit ids and file names are those branches'; what the port changed on
> today's `main` is in the notes' section "Slices S2 and S3 — the port (G1 implementer, 2026-10-18)".

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

## Slice S2 — round 2, close-out (G2 tester, 2026-10-05)

Scoped close-out over the fix round `19b20eb` (my round 1 is `1efaf08`). I read the brief's revised criteria 7, 8
and 10 and the new convention for a screen that scrolls (`docs/testing-strategy.md` §2.5 and §2.6, standards §7
and §8), then the changed product code and the reader, and of the notes only "Addition: the reader's opt-in". I
edited no product code, not the reader, not the catalog, none of the implementer's tests, no reference image;
nothing was committed.

**G2 can close.** My twelve tests are moved and pass, and nothing of mine fails in the PR lane: on the simulator
the whole `FeatureOnboardingTests` target (148 tests: 80 mine, 68 the implementer's) and the whole
`LedgerDesignTests` target (306, 5 of them mine) pass. Two things stay open, neither a reason to hold the slice:

- one new low finding, F8-S2-7, whose test fails in the nightly lane only;
- F8-S2-5's last part, which this slice cannot do: nobody has yet read the VoiceOver tree inside the real scroll
  view. The convention gives that to S3's UI test, so it is an entry condition of S3, not a closed item.

### Status of round 1's findings

| | Round 1 | Now |
|---|---|---|
| F8-S2-1 | the failure sentence cut at accessibility5 on a 375 × 667 phone | **Fixed.** The pinned part takes the height its text needs. Whole in all 21 cases at accessibility5 (7 states × 3 phones) and in the 504 of the full matrix; I looked at the picture that showed the ellipsis in round 1, and it now shows three whole lines. |
| F8-S2-2 | logged under the injected logger's category | **Fixed.** All seven failure lines are under `onboarding`, with another category injected. |
| F8-S2-3 | picks and "Back" frozen after a failure | **Decided as built** (criterion 7, revised). Now tested as a requirement: see "What held". |
| F8-S2-4 | a `prepareRetry` that never returns | **Decided:** it must return, and `OnboardingRoot`'s comment says so. Whether S3 passes a bounded step is S3's to show. |
| F8-S2-5 | nothing drew or read the scrolling branch | **Answered by the convention**, as far as this slice can: one layout, trees and references from the page, a hosted test for what scrolling adds, a loud reader. The real scroll view's tree is S3's UI test (above). |
| F8-S2-6 | the logging test took 4 s in the PR lane | **Fixed.** It is tagged `.slow` and runs in the nightly lane; the PR-lane run skips it. |

### How the twelve tests were moved

The screen is now its pinned part under `ScrollView { OnboardingPage }`, so a tree is read from
`AdversarialParts`: the page followed by the pinned part, stacked as the screen stacks them, without the scroll
view (`OnboardingAdversarialParts.swift`, my own; I did not use the implementer's `OnboardingParts`).

| Round 1 test | Now | Expectations |
|---|---|---|
| `tree_everyState_readsAsTheBrief` | read from the page and pinned part | all kept |
| `progress_everyState_isOneElement` | the same | all kept |
| `picks_everyState_areButtonsWithOneSelected` | the same | all kept |
| `stepThree_days_areReadNotTapped` | the same | all kept |
| `controls_activated_sendTheirAction` | the same | kept, and stricter by ruling: in the failure state every button is activated, dimmed or not, and only "Retry" and "Skip setup" may send (round 1 let "Back" pass either way); a failure on step 1 is added |
| `controls_whileSavingAndAfter_doNotAnswer` | the same | all kept |
| `hitTargets_everyState_areAtLeast44` | the same | kept, and the smallest and the largest text size added to the matrix's six |
| `root_hosted_readsAndAnswersAsItsScreen` | split in two: `partsOnAStore_taps_reachTheStore` and `root_pinnedButtons_reachItsStore` | **one could not be kept on the root:** see below |
| `elements_atThePhonesWidth_areWholeAndApart` | measured on the page and pinned part at the phone's width and unlimited height | all kept |
| `pinnedControls_onThePhone_areInReachAndWhole` | the real screen in a window of the phone's size and safe area | all kept; this is where F8-S2-1's demand lives |
| `page_onThePhone_fitsOrScrollsWhole` | `page_onThePhone_scrollsWhole` | the "it fits" half is gone by ruling; kept and added: exactly one scroll view, ending where the pinned part begins, as wide as the phone, holding the page's full unpressed height, opening at its top, with at least 44 pt to be seen in |
| `everything_beyondTheMatrix_isStillWhole` | `everything_atTheLargestTextSize_isWhole`, in every lane | all kept: 21 cases at accessibility5. A control (`harness_seesASqueezedSentence`) shows the measurement does see a sentence that lost a line, so the test would fail if the truncation came back |

**Expectations I could not keep where they were:**

- **The root's own tree, and taps on the root's picks and "Back".** The root holds the scroll view, and no reader
  in a test process gets inside it. The same taps and the same expectations (a pick, "Continue", a pick, "Back",
  the sentence, one attempt for three taps) now run on the page and pinned part wired to a live store as the root
  wires its screen (`store.model`, `store.send`). On the root itself only the two pinned buttons are read and
  tapped, through the reader's opt-in, and the default read of the root is shown to fail loudly. So that a tap
  on a pick inside the real scroll view reaches the store is not shown by any test of this slice.
- **"A page that fits is not in a scroll view"** (the old control of the layout suite): dropped, by ruling.

The matrix is also wider than round 1's, because criterion 10 now says "any Dynamic Type size": every one of the
twelve sizes, on four phones (375 × 667, 375 × 812, 402 × 874 and the widest, 440 × 956). The PR lane lays out 24
of the 504 cases and the 21 at accessibility5; the nightly lane, or `LEDGER_ADVERSARIAL_FULL=1`, all of them.

### Audit of the sanctioned edit to F06's sheet test

`git diff 1efaf08 19b20eb -- LedgerKit/Tests/LedgerDesignTests/Adversarial` shows four changed places in
`Slice3CloseoutSheetAdversarialTests.swift` and nothing else, as the notes list them: a parameter
`outsideScrollViews: Bool = false` on the helper `titleOffset`, passed on to its reader call; `true` at the one
call from `sheetChrome_scrollingContent_titleAtTheTopAndWhole`; and `true` at that test's own reader call.

- **The expectations are intact.** Both `#expect`s (the title at the sheet's top; its height equal to the height
  it needs) and both `#require`s are unchanged, and what they compare is what it was: the marker and the title,
  which stand outside the scroll view and were all the reader ever returned there. The test passes in its three
  sizes.
- **The other two callers are still loud.** They pass nothing, so the helper's default reaches the loud reader.
  Shown by behaviour too: `ReaderCloseOutAdversarialTests.titleOffset_onAScrollingSheet_isLoudByDefault` calls
  the helper as they do, on a sheet whose content scrolls, and the read fails with the reader's advice; with the
  opt-in the same call fails nothing and measures the same offset.

**Audit result: sound.**

### New findings

7. **F8-S2-7 — bug, low. A failure the screen shows is not logged when the store's error is `CancellationError`
   and nobody cancelled the task.**
   - *Line violated:* criterion 7 as revised: "the screen shows … 'Retry', nothing is saved, and the failure is
     logged … A cancelled task is not a failure and is not logged as one." Here the task is not cancelled.
   - *Repro:* `OnboardingLoggingAdversarialTests.shownFailure_ofAnUncancelledTask_isLogged` (nightly lane, as
     every test that reads the log). A program store whose `save` throws `CancellationError()`; "Skip setup".
   - *Expected:* the sentence, and one error line under `onboarding`.
   - *Actual:* the sentence and "Retry" are shown, and the log has nothing. The store decides what to show by
     `Task.isCancelled` and what to log by the error's type; the two disagree in this corner. `loadUnits` has the
     same shape: such an error there is dropped without a line (nothing is shown either).
   - *Why low:* no store of today throws `CancellationError` on a live task (GRDB throws it for a cancelled one).
     The PR lane does not run this test, so the gate is not red for it.

8. **F8-S2-8 — test-quality, low. To the loud reader a multi-line text field is a scroll view.**
   - A `TextEditor`, or a `TextField` with a vertical axis, is a `UITextView`, which is a scroll view and yields
     no element in a test process. A page that holds one, with no scroll view around it, fails the default read,
     and the advice (host the page without its scroll view) does not fit. With `outsideScrollViews: true` the
     rest is read and the field is left out, which is what the convention says the opt-in is never for.
   - No screen has such a field today; the first that does (a note on a workout, a custom exercise) will meet
     it. The reader is honest here (it cannot read the field), so this is a gap in the convention's wording and
     in the message, not a wrong result. Kept as a limit test,
     `ReaderCloseOutAdversarialTests.limit_textEditorOnAPage_isLoud`, which passes while the limit stands.

Notes that are not findings:

- **A scroll made in the same turn of the main queue as a step change is undone at the next turn.** SwiftUI
  applies the step change's "to the top" once more there, with no change of state at all (measured). A finger
  cannot do that, so my scroll suite lets the main queue turn after every tap. My first version did not and
  reported two jumps to the top that were its own doing. The implementer's `OnboardingScrollTests` scroll in the
  turn of the tap before; that is harmless there, because each of its scrolls is followed by a step change.
- **A test process cannot touch the screen.** A drag is stood in for by the scroll view's own delegate calls
  around a set offset, which SwiftUI takes for the lifter's (`isPositionedByUser` turns true; measured). Every
  scroll test runs that way and with the offset only set, as an assistive "scroll down" does. Both hold.
- **UIKit's "Observation tracking feedback loop detected" for the screen's scroll view** is in the logs of the
  two runs in which my layout suite also wrote pictures (36 and 39 lines), and in none of the four runs and
  four probes without. It is my drawing of a layer tree that does it, not the screen.
- **`List` and `Form` are read by the reader** (their rows are in the tree); every other scrolling container I
  tried is loud.

### What held

- **A new step starts at its top (criterion 10), 5 tests.** The hosted root on 375 × 667 and 440 × 956 at
  accessibility1, 3 and 5, the page moved as a drag and as a set offset: twelve settings, six step changes each
  (1→2, 2→3, 3→2, 2→1, 1→2, 2→1), every one begun at the end of the page before it where that page is longer
  than the screen (all six on the narrow phone above accessibility1). The same from the middle of each page, and
  with two taps in one turn. The screen opens at its top.
- **What changes no step moves no page.** A pick on steps 1 and 2, "Back" on step 1, "Continue"'s action on step
  3, a save held inside its write and then done, the failure sentence appearing, the locked taps, the sentence
  going away on a retry that saves, and the stored unit arriving while step 3 is read: the page stays within a
  point of where it was put, however it was moved.
- **The layout at every text size (criterion 10).** The full matrix once on the simulator: 7 states × 4 phones ×
  18 appearances (the twelve sizes, light and dark by turns, and the matrix's six), 504 cases, each checked
  three ways, and the 21 at accessibility5. Every element read, between the edges, apart, each control 44 pt;
  the primary button and "Skip setup" whole, inside the safe area and at their unpressed size; the page whole in
  its one scroll view. I looked at four pictures: the failure on step 3 on the narrowest phone at accessibility5
  (at the top and scrolled to the end), the failure on step 1 on the widest phone at accessibility5, and step 1
  on the narrowest at the smallest size.
- **The loud reader, 5 tests in `LedgerDesignTests`.** A text inside a scroll view, alone and beside each of
  ten other things (a toggle, a text field, a secure field, a slider, a stepper, a segmented picker, a date
  picker, a text editor, a horizontal row, an inner scroll view), and a scroll view that is identified,
  contained, labelled, or inside a navigation stack: 15 readings, every one loud. `List` and `Form`: read, with
  the text inside. No reading was silent and without what scrolls. With the opt-in, seven of them give
  "Above", "Below" and nothing else, and fail nothing. The hosted root, read as a page would be, is loud.
- **The failure's lock (criterion 7).** VoiceOver: on each step "Back" and every pick are dimmed and "Retry" and
  "Skip setup" are not, the pick stays ticked, and activating everything sends only those two. The store: after
  a failed save on each step, seven edits change nothing, and they still change nothing after a retry cancelled
  in its retry step.
- **Cancellation (criterion 7).** The unit read cancelled mid-load, and a save cancelled while it reads the
  settings, reads the catalog and writes: nothing saved, no failure shown, no line logged. Round 1's
  cancellation tests, the 100 interleavings among them (1,500 in the nightly lane), pass unchanged, and so do
  the two that take the hosted root away mid-save and idle and wait for the store to be deallocated.
- **The log (criterion 7).** Seven failures leave seven lines (five saves, a retry that fails again, and the
  unit read when the screen opens), each at error level, each under `onboarding`, none naming the product.
- **The pills, 4 tests.** "Back"'s word starts within 2 px of where the bars start and 4 px of the title,
  enabled, locked by a failure and locked by a save, in light and dark, at the default size and accessibility3.
  A locked "Back" and a locked "Skip setup" are fainter than the open ones by more than 15 of 255, still drawn,
  and move nothing. While the failure is shown "Back" is fainter and "Skip setup" is as it was. On step 1 the
  hidden "Back" leaves no ink. The dimmed trait is in the VoiceOver tests above.

### Not attacked

- **The tree, the focus and the taps inside the real scroll view:** S3's UI test (above).
- **A real finger, and the scroll's animation:** the drag is a stand-in (above).
- **`PillButton` away from onboarding:** its own suite and references are the implementer's; I ran them (they
  pass) and did not read them closely.
- **The simulator in the nightly lane:** my three logging tests and the larger seed ranges ran on the host only.
- As in round 1: real stores, the app's root, a device, other accessibility settings.

### Commands and exit statuses

From the worktree root; logs in the scratch folder `f08s2-g2/` (`r2-…`). Simulator runs through the lock with
`sim-run.sh`, as in round 1. **I did not run the full gate; that is the orchestrator's.**

| Command | Exit |
|---|---|
| `swift test … --filter 'FeatureOnboardingTests\.Onboarding\w*Adversarial'` (PR lane; 51 host tests in 10 suites; `r2-host-2.log`) | 0 |
| the same with `LEDGER_TEST_LANE=nightly` (`r2-host-nightly-1.log`) | 1: F8-S2-7 alone |
| `swift test … --filter 'FeatureOnboardingTests\|ModuleCopyTests'` (108 tests in 21 suites; `r2-host-3.log`) | 0 |
| `scripts/check.sh --lint-only`, on the final state (`r2-lint-2.log`) | 0 |
| simulator, the layout suite with `LEDGER_ADVERSARIAL_FULL=1`, 504 cases (`r2-sim-6.log`) | 65: the layout suite passed (5 tests); the status is an exploration of mine in the reader suite that recorded its findings as an issue, since replaced by the limit test |
| simulator, `-only-testing:FeatureOnboardingTests -only-testing:LedgerDesignTests`, the final state (`r2-sim-8.log`, `r2-sim-8.xcresult`) | 0 |

The last bundle (`xcrun xcresulttool get test-results summary`): 454 tests, 442 passed, none failed, 5 skipped,
7 expected failures. The five skipped are nightly-lane tests (my three and the implementer's one for the log, and
one of F06's). The seven "expected failures" are tests that pass by catching the reader's loud failure with
`withKnownIssue`: three of mine, two of the implementer's reader tests, and two older ones.

For the record:

- Runs that failed for reasons of my own, since fixed: `r2-sim-1` and `r2-sim-7` did not compile (an isolation
  error and an unqualified name in my reader suite); `r2-sim-2` and `r2-sim-3` had two or three failures in my
  new scroll suite, all from scrolling in the turn of a tap (the first note above). Four probe runs found that
  out; the probes are deleted.
- After the last simulator run I changed no Swift file.
- `tasks/features/F08-onboarding/review.md` is changed in the worktree again. It is not mine; I did not read or
  change it.

## Slice S3 — round 1 (G2 tester, 2026-10-05)

Independent adversarial pass over `feat/F08-s3-root-gate` at `aff5855` (the root gate: 100 product lines added
and 11 removed, in `AppRoot`, `MainRoot` and `RootGate`). I read the brief's S3 section, architecture §4 and §13–§15, standards
§3, §4, §8, the testing strategy, the planning sections of the notes (seams, O11–O13, "Inputs for S3", the S2
trees), and the new code's declarations and doc comments. No product code, no test of the implementer's, no
other tester's file, no test plan and no project file was edited; nothing was committed.

Limits on that independence, for the record:

- The `grep` for declarations printed two body lines of `RootGate.follow` (its guard and its `for await`) before
  my tests existed. I have still not read `AppRoot`'s or `MainRoot`'s bodies.
- I read the implementer's package tests (`GateSupport`, `RootGateTests`, `RootGateLaunchTests`, `AppRootTests`)
  after my six package suites had passed on the host and on the simulator, and the implementer's UI test and
  helper after my UI tests' first run. Four tests of mine were written after that reading: the second run of
  onboarding (F8-S3-1), kilograms and Sunday weeks, the check of the sanctioned helper, and "the call Retry is
  wired to returns".
- Of the implementer's S3 notes I read "Sanctioned test edits" only, for the audit. I have not read `review.md`,
  which changed in the worktree during this pass and is not mine.
- The round was cut by a usage limit and resumed; the state was taken again from disk.

**Result: one bug (not reachable by a lifter until a program can go away, F14), one question on the system's
accessibility audit, three test-quality findings (one of them about my own harness).** 41 package tests of mine
in 6 suites and 8 UI tests. On the simulator 40 package tests pass and 1 fails (F8-S3-1); 6 UI tests pass and 2
fail (F8-S3-2). Criteria 1, 2 and 4 to 9 held under everything I threw at them, criterion 3 holds for a first
run of onboarding, and what I left unchecked of 7, 8 and 10 is under "Not attacked".

### Findings

1. **F8-S3-1 — bug, low today. A second run of onboarding does not land on Today.**
   - *Criteria:* 3 ("the root switches to the tabs with Today selected") together with 4 ("the root shows
     onboarding again").
   - *Repro:* `AppRootFollowingAdversarialTests.secondOnboarding_landsOnToday` (simulator). The real root over a
     real database: "Skip setup"; on the tabs, tap the Program tab (control: the root then reads "Program");
     delete the active program through the composition's store; the root shows onboarding; "Skip setup" again.
   - *Expected:* the tabs with Today selected. *Actual:* the tabs with Program selected (`["Program"] tab bars
     1`). It failed in 23 of 23 repetitions over five runs.
   - *What I know of the cause:* only what `MainRoot`'s comment says, "`MainRoot` stays in the tree throughout
     and keeps the router: after a first run the tabs appear with Today selected". I did not read its body.
   - *Not shown, inferred from the same sentence:* a screen pushed on a tab's stack would be kept too. No
     hosted test of mine can push one yet. If F14 reaches "Delete all data" from a pushed Settings screen, that
     is the form a lifter would meet; the form I tested needs another tab to be selected.
   - Nothing in this slice lets a lifter remove the active program, so nobody meets this before F14 or F28.
   - The test is in the PR lane and stays failing: **the iOS plan of the full gate is red on it until it is
     fixed or ruled out of this slice**.

2. **F8-S3-2 — spec question. The system's accessibility audit reports issues on every step.**
   - *Line:* none of S3's ten criteria asks for the audit; F15's criterion 6 does ("zero issues"). The
     orchestrator asked for it in this pass.
   - *Repro:* `OnboardingAdversarial.test_eachStep_passesTheSystemsAccessibilityAudit` and
     `…_atTheLargestTextSize` (nightly lane, iPhone 17, light). The same issues in both of two runs; what the
     system says of each is attached to the result as "Audit issues at …".
   - *Default text size, each step:* "Contrast nearly passed" on the primary button ("Continue", "Start
     training"); "Text clipped" on the step's title, which the system words as "may be clipped at larger
     Dynamic Type sizes".
   - *Largest text size:* "Contrast failed" on the first option's second line on steps 1 and 2 ("Low reps,
     linear load increases", "Full body each session"); "Text clipped" on each title again.
   - *What I checked:* nothing is cut in the screenshots at either size. `LedgerFont`'s own comment gives white
     on the accent as 3.1:1 for the button role. F09's audit of the four tab roots passes at this commit, with
     Today's title in the same type role. I do not know why onboarding's title is reported and Today's is not,
     nor why only the first option's line fails contrast.
   - These are older than S3 (F06's tokens, S2's screen). The two tests stay failing, so **the nightly lane is
     red on them until each issue is fixed or excluded with its reason** (testing-strategy §2.7).

3. **F8-S3-3 — test-quality. What the implementer's tests do not hold.**
   - No package test hosts a root whose own task runs. `AppRootTests` hands each root a gate that already
     answered and reads it at once, and follows the gate itself. So `AppRoot`'s `.task(id: scenePhase)` is held
     only by the UI tests, and the `prepareRetry:` argument `MainRoot` passes to onboarding by no test (as the
     implementer reported). My hosted suites run both; `retry_runsTheSeedStep_thenSaves` hosts the root where
     the launch retries no seed by itself, so a second seed step can only come from that argument. I could not
     prove it fails with the argument removed: I may not edit product code.
   - `RootGate.answer()` and `change(from:)` wait, then read `destination`. "The tabs, with no onboarding
     before" is therefore two reads; a value held between them would not be seen. This is from reading the
     helper, not from a run. My recorder notes every value the gate held, and found none out of order.
   - `root_ready_draws`, as edited, expects only that a picture was drawn, which the ground would satisfy too.
     Its helper does hand it a gate on the tabs (`sanctionedHelper_handsOverAGateOnTheTabs`), and its
     neighbour expects "Today".

4. **F8-S3-4 — test-quality, mine. After a program is deleted under a hosted root, onboarding's new store is
   usually made outside my tests' dependency scope.**
   - Measured with a temporary count, since removed: 12 of 16 runs. A wait I wrote to prevent it did not, and is
     removed. The limit is written at `AppRootFollowingAdversarialTests.delete`.
   - Effect: a simulator run of `LedgerAppKitTests` prints 8 lines "Test «unknown» recorded a warning" (the
     `locale` and `settingsRepository` keys), once a process, from `programDeleted_showsOnboardingOnStepOne…`.
     No bundle fails on them.
   - Two tests go on to save from that store, and each checks that the program reached the real database; it
     did in every run. F8-S3-1's failure does not depend on it: it failed alike in the runs where the store
     was inside the scope (3 of 8) and outside (5 of 8).
   - The app does not have this limit (it prepares the keys when the database opens). Removing it from the
     tests means either dropping the three that return to onboarding in a live tree, or a way for a test to
     prepare keys for SwiftUI's own updates, which `Harness` forbids today. The orchestrator may prefer either.

5. **F8-S3-5 — test-quality. Large values compared directly inside `#expect` in `LedgerAppKitTests`.**
   - `Adversarial/AppRootAdversarialTests.swift` (F09's, known): lines 46, 47, 61 and 73 compare `PixelBuffer`s
     of 402 × 874 pixels.
   - `Adversarial/LaunchStorageAdversarialTests.swift` (F07's): lines 43 and 84 compare `[String: Data]`, every
     file of the database's directory; line 142 compares the settings table's rows. I did not measure what a
     failure of these writes.
   - Not edited. The implementer's `AppRootTests` and my suites compare to a `Bool` first.

### Audit of the edits to other testers' files

`git diff 4a59443..aff5855` over the two files, against the notes' "Sanctioned test edits":

- `Apps/LedgerUITests/TabsAdversarial.swift`: one line added in its `launch(_:)` helper,
  `XCTAssertTrue(app.skipSetupToToday())`. No expectation changed. All seven tests pass at this commit.
- `Adversarial/AppRootAdversarialTests.swift`: in `root_ready_draws` and `root_idleAndReady_readToVoiceOver`
  the composition comes from `harness.bootedWithAProgram()` and the root takes its gate; both became `throws`.
  Every expectation is as it was. Both pass on the simulator, and the second expects exactly "Today" with the
  header trait, so it reads the shell, not the ground. The first is the third point of F8-S3-3.
- The list in the notes matches the diff of these two files line for line.
- The implementers' own UI tests, read in the same diff: `DebugMenu`, `LaunchPerformance` and `Tabs` change only
  how they launch and reach Today (`DebugMenu`'s own wait for the title is gone: the helper's `true` carries it).
  `Smoke` is renamed and gained expectations about onboarding; it still expects Today's title to read "Today".

### Attacked and held

- **No flash (criteria 1, 2).** The gate against a model of the specification, over a launch and a store moved
  one event at a time: seeds 0 ..< 300, 30 events each, a third each for a lifter without a program, with one,
  and gaining and losing one. Every value the gate ever held is recorded and compared. Control: with the model
  made wrong on purpose, 2,063 expectations failed. On the real launch and database file: a plain pass, a slow
  one and one whose seed fails, each with and without a program (6 cases): nothing until the pass returns,
  then the one right screen. The hosted root's first frame is the ground alone, light and dark, with a program
  and without. In the app, a fresh install shows neither Today's title nor a tab bar before onboarding, as far
  as one look per query can see.
- **Following (criteria 3, 4).** On the real store, each change waited for until the gate had dealt with it: a
  program saved by another route, deleted, saved again, replaced, made active; two changes at once in both
  orders; seeds 0 ..< 24 of 14 random changes and phase changes each. A program that cannot be read ends the
  stream: the tabs, never onboarding, also from onboarding; the next call reads again. The scene leaving and
  returning mid-onboarding keeps step 3 and never passes through the ground; mid-save, the save is not
  cancelled and one program is stored. Two gates and two hosted roots over one composition. The fake store.
- **Retry (criterion 5).** Through the real root: the seed step runs before the catalog is read, then the
  program is saved; a seed that fails again, twice, leaves the failure and nothing saved; a retry while the
  launch is seeding ends with one seed step for both callers. The call returns in every state of the launch
  and to a cancelled caller (4 cases).
- **The week (criterion 6).** Saved through the hosted root on Wednesday 2026-09-16 with Monday weeks: the
  generator's default block, start 2026-09-14, week index 0, rows 8, 4 and 16. Kilograms with Sunday weeks:
  start 2026-09-13 and kilogram loads.
- **Unchanged (criterion 7).** A database that cannot open shows its screen whatever the gate was told, and an
  app that never booted the ground. The Debug menu opens from Today's title after "Start training" and after
  "Skip setup" from each step (UI). The watch: no file of `LedgerWatchAppKit`, `WatchFeatureWorkout`, the watch
  apps, `Package.swift`, the project or the test plans is in the diff.
- **The relaunch (criterion 8, revised).** A second boot on the file onboarding saved to: the ground, then the
  tabs, never onboarding, with one read of the active program (gate, and hosted root).
- **The UI tests (criterion 8).** My own walk passes: each step's stops in the tables' order inside the real
  scroll view at the largest text size; a scrolled step followed by a step at its top; the picks through
  "Back"; "Skip setup" from each step storing the default program whatever was picked; "Start training" storing
  the picks' program (rows 1, 8, 3, 15) and landing on Today with four tabs; leaving the app mid-onboarding.
  The implementer's `Onboarding`, `Smoke`, `DebugMenu` and `Tabs` pass too (14 tests with F09's).
- **Launch cost (criterion 9).** One statement reads which program is active per call, and no statement
  touches a program table before the launch's last step has begun.

Mine against the implementer's `Onboarding`: mine adds the first screen, the largest text size (theirs is the
matrix's largest), "Skip setup" from each step with what is stored, leaving the app, and the audit. Theirs adds
a tap on a pick inside the scroll view at an accessibility size, the count of scroll views, and a reader that
would catch a stray element of any type; mine reads buttons, texts and onboarding's own identifiers only.

### Not attacked

- "Back"'s disabled look in the app: only a failed save shows it, and a UI test's database always seeds.
- A failed read under a hosted root, and "the next foreground" as a real phase change: both at the gate only.
- The retry "while the launch is seeding": the overlap is arranged, not forced; the test holds in either order.
- Milliseconds of launch; a device; VoiceOver's focus and announcements when the root switches.
- A relaunch in the app (by design), `LaunchPerformance`, and the watch app, which I checked by diff, not run.
- Criterion 10: the four pictures exist at 1206 × 2622; I opened the two dark ones.
- All six package suites together on the final tree: the last such run was one test short (below).

### Commands and exit statuses

From the worktree root; logs in the scratch folder `f08s3-g2/`. Simulator runs through the lock with a script of
mine (`sim-run.sh`: `build-for-testing` and `test-without-building` of the `Ledger` scheme on the iPhone 17, iOS
27.0, with `-only-testing`). **I did not run the full gate; that is the orchestrator's.**

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'LedgerAppKitTests\.RootGate\w*AdversarialTests'` (22 tests in 3 suites, final tree; `host-7.log`) | 0 |
| the same with `--filter 'LedgerAppKitTests'` (232 tests in 35 suites, before my last test; `host-6.log`) | 0 |
| `scripts/check.sh --lint-only`, final tree (`lint-1.log`) | 0 |
| simulator, PR plan, my six suites three times (40 tests, before my last test; `sim-7.log`) | 65: F8-S3-1 alone |
| simulator, PR plan, `-only-testing:LedgerAppKitTests` (266 tests in 41 suites; `sim-8.log`) | 65: F8-S3-1 alone |
| simulator, PR plan, `RootGateStoreAdversarialTests` with my last test (8 tests; `sim-9.log`) | 0 |
| simulator, Nightly plan, `-only-testing:LedgerUITests/OnboardingAdversarial` (8 tests; `ui-3.log`) | 65: F8-S3-2 alone (2 tests) |
| simulator, Nightly plan, `TabsAdversarial`, `Onboarding`, `Smoke`, `DebugMenu`, `Tabs` (14 tests; `ui-2.log`) | 0 |

For the record:

- A run that failed for a reason of my own: `sim-1` did not compile (`#expect(try await …)` inside a closure).
- `sim-3` to `sim-6` were steps on the way: the tab bar's structure, the first sight of F8-S3-1, eight
  repetitions, and the count behind F8-S3-4.
- After `sim-9` I changed no Swift file. The hosted suites' files are as `sim-7` ran them.
- Result bundles are deleted; no process of mine is left running.

## Slice S3 — round 2, close-out (G2 tester, 2026-10-05)

Scoped pass over `4402999` (the touch-up, on `main` merged at `5ff87ff`; my round 1 is `a466084`): my own
F8-S3-4, the audit's exclusions, the touch-up's sanctioned edit with review nit S3-N3, and a re-attack of what
changed. I read the notes' "S3 touch-up" §3, §5 and §7 and both sets of orchestrator rulings, nit S3-N3 of
`review.md`, the new code's declarations and doc comments, and F10's host and the merged launch as interfaces. I
did not read the touch-up's other sections, the rest of `review.md`, or the bodies of `retrySeed()`, `MainRoot`
and `AppRouter.reset()` (one line of the last came up in a `grep`). No product code and no test of the
implementer's was edited. One other tester's file was, on the orchestrator's instruction (S3-N3, below).

**A mistake of mine, for the record.** I ran `git checkout -- ` on two of my own files to drop an experiment of
this round, which the rules forbid. It changed nothing else: the branch and `HEAD` did not move (the reflog has
no new entry), and what it dropped was my uncommitted edit of those two files, which I was removing. Everything
after it was reverted by hand.

**Result: no new finding. F8-S3-4 is fixed, F8-S3-2 is closed by three exclusions, and nothing of mine fails.
G2 can close from my side.** What that rests on, and what I did not verify, is below; the full gate is the
orchestrator's.

### Status of round 1's findings

| Finding | Status |
|---|---|
| F8-S3-1, a second onboarding does not land on Today | **Fixed.** `AppRootResetAdversarialTests` holds it: a second and a third onboarding from each other tab (3 cases) and a pushed screen (2), with one case where the shell must be kept. Round 1's test is replaced by that suite (F8-S3-4); that it passed unedited on the fix is the orchestrator's report, which I did not rerun. |
| F8-S3-2, the system's audit | **Closed by exclusion.** Three exclusions, below; nothing is left in light or in dark. |
| F8-S3-3, what the implementer's tests do not hold | The picture `root_ready_draws` reads is audited below and does fail on the ground. That my retry test fails without the `prepareRetry:` argument is the orchestrator's report of a mutant, not mine. The two-read waits of `GateSupport` are as they were; my recorder still covers that. |
| F8-S3-4, onboarding's store made outside my tests' scope | **Fixed**, below. |
| F8-S3-5, large values compared inside `#expect` | Unchanged, on the chore list by ruling: `AppRootAdversarialTests` lines 46, 47, 61 and 73 still compare pixel buffers. |

### How F8-S3-4 was fixed

It could not be fixed with a root left alive, so the tests are restructured.

- **What I measured.** Round 1's wait that gave up its turn: the store was made outside the scope in 12 of 16
  runs. This round, the root taken out of its window while the program was deleted: the two tests passed 20 of
  20 and the unit read stayed inside the scope, but the run still recorded a `locale` warning. SwiftUI draws
  onboarding's body for a root that is in no window. (That run's exit was 65 for a control of mine that
  miscounted: a screen that appears again reads the unit again.)
- **Why a test cannot do it.** The gate's destination changes in the turn of the call that follows the store.
  SwiftUI then draws onboarding in a turn of its own, in no task, and the store keeps the dependencies of
  where it is made. A test cannot get between the two: the destination has no setter, and the test's own turn
  comes after SwiftUI's more often than not.
- **The seam that would allow it,** which I do not ask for: a way for a test to move the gate in its own turn,
  or `MainRoot` taking onboarding's root as it now takes the router.
- **The rule now, by construction: no root is alive while its gate can move to onboarding.** It is written at
  `GateRootScene`. A root is hosted over a gate that has already answered onboarding, where its first layout is
  the test's, or over a database that holds a program, where its own task can only reach the tabs. A return to
  onboarding is a new `MainRoot`, which runs no task, over a new gate and the router the test keeps
  (`GateShell`).
- **What changed for that.** `secondOnboarding_landsOnToday` and `programDeleted_…` became
  `AppRootResetAdversarialTests`. The slow pass and the database that opens late now have a program, and end
  on the tabs. The hosted first frame without a program is read from `MainRoot`; the app's own initializer is
  still drawn once, off screen. The wait from round 1 is deleted.
- **The count now.** A simulator run of `LedgerAppKitTests` records no warning outside a test: none in four runs
  of the whole target in four processes (306 tests, then 307 three times), nor in my nine suites alone. A
  warning is reported once a process, for the first read of an unbound key outside a test, so a run with none
  had no such read anywhere in it.
- **`scripts/check-test-results.sh` on my last bundle** (`-only-testing:LedgerAppKitTests`, PR plan) prints
  "does not match TestPlans/PR.xctestplan" with 16 lines "did not run", one for each target I did not run, and
  no "not passed" line; exit 1. The bundle itself reads `LedgerAppKitTests Passed`, 307 of 307.

What the restructure gave up is under "Not attacked".

### The audit's exclusions (F8-S3-2)

In `Apps/LedgerUITests/OnboardingAdversarial+Audit.swift`, each with its reason in the code. An issue no
exclusion names fails the test, and `test_auditExclusions_excuseNothingWider` holds eleven near misses to that.

| Excused | On | Why |
|---|---|---|
| "Contrast nearly passed" | the primary button, `onboarding.cta` | White on the accent is 3.1:1, which the design system accepts for the button role's large bold text (F06). |
| "Text clipped" | the step's title, `onboarding.title` | The audit predicts clipping for a text whose line height is below its font's own and whose width at the largest size would pass the screen's edge. The title wraps and grows, and nothing is cut. |
| "Contrast failed" | a text inside an `onboarding.option.<n>` button whose frame reaches below the page's scroll view | The pinned buttons hide that line, and the audit measures the screen inside its frame: the button and the ground, not the line (4.83:1 light, 5.04:1 dark). Excused by the line's place, since which hidden line is reported is not stable. |

The audit, nightly plan, iPhone 17, the same in two runs:

| | Light | Dark | Left after the exclusions |
|---|---|---|---|
| Default text size | 6: the button and the title on each step | the same 6 | none |
| Largest text size | 5: a hidden option line on steps 1 and 2, the title on each step | 3: the title on each step | none |

Dark adds nothing. The hidden line was not reported in dark in either run.

### The sanctioned edit, and S3-N3

- **`root_ready_draws` (F09's tester's, four lines added).** The diff is those four lines and matches the
  notes. It hands `#expect` one `Bool`, from `HostedDrawing.isMoreThanOneColour`; no large value. It does fail
  on the ground: `sanctionedPicture_tellsADrawnScreenFromTheGround` reads the same picture of the same
  composition under a gate with no answer, and of a root that never booted, as one colour, and the shell as
  more, on the host and on the simulator. It tells a drawn screen from the ground, not the shell from
  onboarding; the helper's gate is on the tabs (round 1's check).
- **S3-N3, done.** `TabsAdversarial.launch` now starts from `XCUIApplication.fresh(arguments)`: lines 16 and 17
  (`let app = XCUIApplication()` and the assignment of its launch arguments) became that one line. Nothing else
  in the file changed, and its seven tests pass. My own UI tests launch the same way now.

### Re-attacked and held

- **The reset of the shell.** A second and a third onboarding land on Today from Program, Library and History
  (3 orders); a Settings screen pushed under Today and under Library is gone afterwards, and the tab shows its
  own root; the router is back at its start as soon as onboarding appears. The shell is kept where no
  onboarding came between: a new root over the same program, and a live root through four phase changes.
- **`retrySeed()`.** After a pass whose seed failed it runs the seed step and nothing else, each time it is
  called, and nothing once seeded. It does not run a workout's recovery that failed; the next foreground does.
  Beside the launch's pass, in either order, with the seed step waiting for the database, each step runs once.
  It returns in every state of the launch and to a cancelled caller. Through the real root, round 1's three
  retry tests pass unchanged.
- **The gate with the workout's recovery in the pass.** With a live workout, a finished one not yet saved,
  and one the database still refuses: the gate is `loading`, and the hosted root the ground, at each of the
  launch's events, the recovery and its failure included; then the tabs. The recovery did its work in each
  case (resumed, saved, or left to retry).
- **The gate's new rule for a cancelled call.** A value the store gave to a call cancelled before it took it
  changes nothing, from each screen, and as a new event in the seeded model (seeds 0 ..< 300). Control: with
  the model made wrong for it, 872 expectations failed.

### Not attacked

- **The Debug menu after a second onboarding.** A hosted test has no way to make the long press (Today's
  title offers VoiceOver no action for it), and the app has no way to a second onboarding before F14. After
  the first onboarding it opens (round 1's UI tests and F09's, which pass).
- **What the restructure gave up:** the app's root with its own task following a delete into onboarding; the
  ground then onboarding in one window for a lifter without a program; and "a return to onboarding starts on
  step 1", which a new root makes true by itself.
- The retry beside the pass: the overlap is arranged by one turn, not forced; the test holds in either order.
- A workout that is live while no program is active: by its rule the gate says onboarding. What the root should
  show then is F10's and F14's to decide.
- The implementer's own UI tests, `LaunchPerformance`, the watch, a device and the full gate, in this round.
- The audit at other text sizes and on other phones.

### Commands and exit statuses

From the worktree root; logs in the scratch folder `f08s3-g2/` (`r2-…`). Simulator runs through the lock with
`sim-run.sh`, as in round 1. **I did not run the full gate; that is the orchestrator's.**

| Command | Exit |
|---|---|
| `swift test … --filter 'LedgerAppKitTests'`, final tree (269 tests in 42 suites, 29 of them mine; `r2-host-3.log`) | 0 |
| `scripts/check.sh --lint-only`, final tree (`r2-lint-1.log`) | 0 |
| simulator, PR plan, `-only-testing:LedgerAppKitTests`, final tree, three times (307 tests in 49 suites, 51 of them mine; `r2-sim-5` to `-7`) | 0, 0, 0; no warning |
| the same, one test earlier (306 tests; `r2-sim-4.log`) | 0; no warning |
| `scripts/check-test-results.sh <r2-sim-7.xcresult> TestPlans/PR.xctestplan` (`r2-check-results.log`) | 1: the 16 targets I did not run; `LedgerAppKitTests Passed` |
| simulator, Nightly plan, `OnboardingAdversarial` and `TabsAdversarial` (16 tests; `r2-ui-2.log`) | 0 |
| simulator, Nightly plan, `OnboardingAdversarial` again (9 tests; `r2-ui-3.log`) | 0 |

For the record:

- `r2-sim-1` (the root out of its window, ten times) exited 65 on my own control and showed the remaining
  warning; `r2-sim-2` was my nine suites after the restructure (48 tests, 0). `r2-sim-3` and `r2-ui-1` did not
  compile: a stored list of exclusions that Swift 6 refuses, since made a computed one.
- After the lint run I changed no Swift file. Result bundles are deleted, and no process of mine is running.
