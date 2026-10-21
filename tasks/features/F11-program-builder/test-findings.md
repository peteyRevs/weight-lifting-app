# F11 — test findings

## Slice S1 — round 1 (G2 tester, 2026-10-06)

**Outcome: no bug found.** Every one of the thirteen criteria held under attack. Three findings are recorded:
two spec questions and one note on the implementer's tests, all low, none of which fails a test. All 154 of
the tester's tests pass; the whole `LedgerDomainTests` target passes on the host (1,093 tests).

Slice under test: `feat/F11-s1-program-editing` at 9660227 (the specification is fee3c70). The tester's
suites are the 24 files under `LedgerKit/Tests/LedgerDomainTests/Adversarial/Programs/` (19 suites, 5 support
files, 4,399 lines), uncommitted; the orchestrator commits. No product code and no test of the implementer's
was edited.

The round was cut once by an authentication error on the service side. Nothing from before the cut is used
as evidence: every number below comes from a run made after it, listed under "Commands".

### How the tests were written

- Before any test existed the tester read the brief's two "Plan amendments" sections, the planner's sections
  of the implementation notes, the product documents the brief names, and the code's declarations and doc
  comments only. The implementer's section of the notes was never read; `review.md` was never read.
- One leak, stated plainly: the `grep` the brief gives for learning the declarations matches `case` lines,
  so it printed the six arms of the `switch` inside `DayEditing.stepped`, one line each. No other function
  body was read before the tests existed.
- After the suites had run green, the product code (367 lines) and then the implementer's tests were read,
  to look for cases the black-box suites had missed and to judge the tests (finding 3). That reading added
  the commutation suite, the public-surface suite, the 38-digit RPE cases and the reach suite.
- Expected values come from the specification and from reference models written in the test target, never
  from the code under test: `BlockModel` (weeks, schedule, days, tags), `DayModel` (a day as its superset
  groups, every number a whole number, the flags derived from the groups), `EditAdv.moved` (the group-aware
  move from its definition), `EditAdv.referenceName` (category `Cc` as its 65 code points),
  `EditAdv.referenceStep` (the next multiple of a step in whole 10⁻⁷ g, so 52.49999 cannot pass as 52.5),
  and spec §7.2 in whole numbers for the prescriptions.
- The suites were shown to be able to fail. Ten references were made wrong on purpose (the rest rounding,
  `Cc` without U+007F, the step, the move's direction, the tag rule, the cycle order, the Legs chip, linear
  progression, the break-out, double progression): 15 tests failed, each naming a seed or a smallest case in
  one short line, and the run's log was 0.7 MB. The files were then restored and compared byte for byte with
  their copies. A temporary exit test that returned a wrong value failed with `EXIT_FAILURE`, and one that
  trapped failed with `SIGTRAP`; a temporary file under a plain `import LedgerDomain` that named an internal
  symbol did not compile. All three temporary files are gone.

### Findings

**F11-S1-1 — spec question, low. A name with nothing visible in it is stored.**
- Rule: slice criterion 2 and the plan's behaviour 5 ("a blank name is not saved and the stored one stays").
- Repro: `ProgramEditingNamesAdversarialTests.cleanedName_formatCharactersAlone_isStored`. Smallest input:
  `"\u{200E}"` (a left-to-right mark). Also U+2060 with U+FEFF, U+00AD, U+200D, U+3164 (Hangul filler) and
  U+2800 (Braille blank).
- Expected by the rule as written: stored, since none of them is of category `Cc` or white space. Actual:
  stored. The code meets the rule; the question is whether the rule meets its purpose. The builder's title
  and a day card would then show an empty line, and the title is what the lifter taps to rename. U+FEFF and
  U+2060 arrive with text pasted from other apps.
- The test passes: it pins the behaviour as built, and is named so, until someone decides. Either leave it
  (one lifter, their own device) or treat a name with no visible scalar as blank in `cleanedName`.

**F11-S1-2 — spec question (documentation), low. Two enums are not spelled as the plan's signatures.**
- Rule: "Plan amendments", "Signatures are the plan's ('The editing functions, as proposed')", which give
  `StepDirection { case down, up }` and `MoveDirection { case up, down }`.
- Actual: `case downward, upward` and `case upward, downward` (`DayEditing.swift:20-28`). Every other
  signature is the plan's, name for name. The cause is probably the lint's three-letter minimum for an
  identifier (`up` is two letters); the tester did not read the implementer's notes and cannot say whether it
  is recorded there.
- Repro: `EditingPublicSurfaceAdversarialTests` compiles only with the built spellings.
- Consequence: none in this slice. The plan's rows for the slices that call these still say `.up` and
  `.down`; their briefs should use the built names.

**F11-S1-3 — test-quality, low. Nothing to change before the merge.**
The implementer's suites assert behaviour: the worked examples are written out by hand, results are rebuilt
through `Program.init` and `Slot.init`, differences are compared as a few words (no large value inside
`#expect`), and the existing tests are untouched (three existing test files gained lines, none lost any).
Three gaps, each now covered by the tester's suites:
- Trap-freedom is tested in the test process (`DayEditingNormalFormTests.slotOutsideTheModel_noEditTraps`,
  `ProgramEditingTests.blockWithNoWeeks_noFunctionTraps`), where a trap ends the whole run instead of failing
  one test, and no test passes a week of `Int.min` or `Int.max` (the seeded weeks run from −4 to the count).
  Covered by 18 exit tests.
- `DayEditingPropertyTests.move_keepsEveryGroupAndTheNormalForm` reads both sides of properties 3 and 4
  through `DayEditing.groups(of:)`, part of the code under test, and draws one move per seed (200 in the PR
  lane). Covered by all 7,172 moves against a grouping and a move written from the definition.
- The seeded sequences (`randomEdits_keepTheProgramValid`, `randomEdits_keepTheNormalForm`) check that each
  result is valid, not that it is the right result; the rules rest on the fixed examples. Covered by the two
  model suites, which compare every step.

Observations, not findings:
- `cleanedName` also trims U+200B (zero-width space) from the ends: Foundation's white space holds it, the
  Unicode `White_Space` property does not. Harmless; the tester's reference follows Foundation.
- Read from the code, not tested: a program holding one day id twice, which `Program.init` accepts but
  `addDay` and the store's primary key never produce, would cycle a weekday through the days without coming
  back to rest. No function traps on such a program (tested).

### Attacked and held

Seeds are `PropertySeed.all`: seed *i* is 7919 × *i* + 17, for *i* in 0 to 199 in the PR lane; the six suites
that use all of them were also run once with 2,000 seeds (*i* to 1,999). No seed failed.

| Criterion | Attack | Cases | Suite |
|---|---|---|---|
| 1 never traps | Weeks `Int.min`, `Int.min + 1`, −1, 8, 9, `Int.max − 1`, `Int.max` through every function that takes a week; logged weeks at both ends of `Int`; two rounds of every edit on blocks with no weeks, one week, no days, one day, one day id twice, one week id twice, weeks out of order, indices that are not places (the last `Int.max`), a schedule naming a lost day | 10 exit tests | `ProgramEditingTotality…` |
| 1 never traps | Every field set to both ends of `Int`, NaN and the largest decimals; slots holding `Int.min`, `Int.max`, 0 and −1; one slot id two and three times; days of no slot and one slot; loads and steps of NaN, zero, below zero and the largest decimals in slot and exercise (12,288 presses); two rounds of every edit | 8 exit tests | `DayEditingTotality…` |
| 1, 3, 4, 5 | Seeded block edits against `BlockModel` at every step, each result rebuilt through `Program.init`, slots and the program's other fields untouched, then encoded and decoded | 200 seeds × 60 edits (2,000 × 60 once) | `ProgramEditingModel…` |
| 1, 6, 7, 8, 9, 12 | Seeded day edits against `DayModel` at every step: order, flags, every field of every slot, normal form, `Slot.init`, then encoded and decoded; and each edit applied twice (purity) | 200 seeds × 80 edits (2,000 × 80 once); 40 × 30 | `DayEditingModel…` |
| — | The first forty seeds meet every rule the two models hold (both errors, an id in use, a tag past the count, a deleted scheduled day, joins, splits, both kinds of move, the coupling) | 24 rules | `EditingReach…` |
| 2 names | Every scalar of the first plane and every 257th above it, alone, inside a name and at both ends; seeded names over 29 boundary scalars; 31 hand-written names (CR LF, a mark after a removed NUL, emoji joined by U+200D, right-to-left marks kept); 300,000 scalars; the three functions that store a name | 202,704; 200 seeds × 40 | `ProgramEditingNames…` |
| 3 weeks | The two errors in their order, for 2 to 6 weeks and every set of logged weeks from −1 to one past the end; weeks added and removed; a week id in use | 992 | `ProgramEditingModel…`, `…Examples…` |
| 4 schedule | Criteria 2 and 3 value for value; copy onto the first and the deload week; apply from the first and the last week; 81 weeks outside the block through five calls | 405 | `ProgramEditingExamples…`, `…Model…` |
| 5 days | Tags after add, delete, add in five orders; a tag already held; the first day of none; every day deleted; the cycle after a delete and after an add; `updateDay` with another id and with an unknown day | 20 tests | `ProgramEditingDays…` |
| 6 slots | Rule 7's defaults in both units; an id the day holds, also twice in one call; a slot arriving joined into an empty day; every slot of every day of 0 to 7 slots removed | 1,538 | `DayEditingExamples…`, `…Supersets…` |
| 7 fields | Reps and the top set to −5…50 from each of the 735 valid pairs; sets and rest for −1,000…1,000; RPE for every hundredth from −2 to 15, the 30 ties going up, 4.75, 5.25, 9.99, values a `Double` cannot tell from a tie; steppers at both ends of each range | 82,320; 4,002; 1,701 | `DayEditingFields…` |
| 7 start load | Every quarter pound and kilogram from 0 to 400 stepped both ways by 5, 2.5, 1.25 and 2, in its own unit and in the other; each equipment's step in each unit; the slot's own step; from zero; forty presses up and down to the gram; `set` storing −3…30 in hundredths | 51,232; 6,748; 6,602 | `DayEditingStartLoad…` |
| 8 progression, superset | Double progression from each of the 735 pairs and each progression; joining and breaking out every slot of each of 255 days, the first slot's flag set as well; an unknown id through ten calls | 6,615; 6,152; 5,100 | `DayEditingFields…`, `…Supersets…` |
| 9 move | Every day of 0 to 8 slots with every flag pattern (511 days), every slot, both directions, against the definition; properties 1 to 6, property 4 by a classifier that does not use the reference; the 1,020 moves at a day's edge; the case the opposite move does not restore | 7,172 moves | `DayEditingMove…` |
| 10 prescriptions | Criterion 7's numbers by hand; a missed week; weeks in any order and number; every slot of the seed program with seeded misses in both units, against `prescribe` and against spec §7.2 in whole numbers | 25 seeds × 16 slots × 2 units × 8 weeks | `ProgressionPrescriptions…` |
| 11 filter | Every chip or none × every equipment or none × 20 queries (blank, spaces, case, an accent, full width, short name only, a control character) against the tester's filter, in its order; a shuffled catalog; the 26 core exercises under no chip; two custom exercises of one name | 960; 20 seeds | `ExerciseFilter…` |
| 12 never writes | Seeded programs with misses on every slot, block edits mixed with day edits through `updateDay`; every function on every slot; and, beyond the criterion, each edit commutes with a save of one slot's misses and exercise | 200 seeds × 100 edits; 132; 200 × 40 and 200 × 60 | `EditingNeverWrites…`, `EditingCommutes…` |
| 13 | The ranges are 1…12, 1…30, 2…40 and `Slot.init` accepts exactly them, throwing in the old order; both clamping initializers agree with the failable ones on every valid value and hold −5…15 by hundredths and −1,000…1,000 s; every editing function, type and constant is public, `Hashable` and `Sendable` where the plan says, callable from a detached task | 363; 4,002; 4 tests under a plain import | `EditingRanges…`, `EditingPublicSurface…` |

Also checked by hand: the slice is 367 product lines; the five new files import Foundation alone and hold no
`Double`; `git diff --numstat fee3c70 9660227 -- LedgerKit/Tests` shows no line removed from an existing test.

### Not attacked

- **Coverage.** The slice's claim of 100 % line coverage of the new files was not measured.
- **Simulators and the full gate.** Host only, as briefed. The 18 exit tests are compiled on macOS alone
  (`#if os(macOS)`, as `TrapAdversarialTests` is), so a simulator run has 136 of the 154.
- **`ProgressionRules.prescriptions` with a week whose index is `Int.min` or `Int.max`.** Not tested, read
  from the code: it calls the existing `prescribe` (F02), which computes `weekIndex − 1` and counts the weeks
  below `weekIndex`, so `Int.min` would overflow and `Int.max` would not return. No valid program holds such a
  week (`Program.init` keeps indices 0 … n − 1), and criterion 1's "never traps" names `ProgramEditing` and
  `DayEditing` only. Recorded so that nobody reads criterion 1 as covering it.
- **What a caller hands to `updateDay`.** The closure's result is stored as returned: a day not in normal
  form, or a name that was not cleaned, would be stored. Nothing in this slice forbids it; the stores of the
  later slices must go through `DayEditing` and `renameDay`.
- **Performance.** No timing test. For scale only: the tester's 154 tests, 960 filters of the 224-exercise
  catalog among them, run in under two seconds of wall-clock time.
- **Anything outside the Domain**: the store, the repository's `update` (S3), the screens.
- The implementer's section of the implementation notes and `review.md`, by the independence rules.

### Commands

All from the worktree root, after the cut, on the final tree. The full gate (`scripts/check.sh`, the
simulators, coverage) is the orchestrator's and was not run.

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'LedgerDomainTests\.(ProgramEditing\|DayEditing\|Editing\|ProgressionPrescriptions\|ExerciseFilter)\w*AdversarialTests'` | 0 | 154 tests in 19 suites passed |
| 2 | The same with `LEDGER_PROPERTY_SEED_COUNT=2000` | 0 | 154 tests in 19 suites passed; six suites at 2,000 seeds |
| 3 | `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerDomainTests` | 0 | 1,093 tests in 168 suites passed |
| 4 | `scripts/check.sh --lint-only` | 0 | format, lint, package graph, pins, script tests: OK |
| 5 | Command 1 with ten references made wrong on purpose (then restored) | 1, as intended | 15 tests failed |
| 6 | Command 1 with a temporary canary suite of two exit tests (then removed) | 1, as intended | both canaries failed: `EXIT_FAILURE`, `SIGTRAP` |
| 7 | Command 1 with a temporary file naming an internal symbol under a plain import (then removed) | 1, as intended | did not compile |

Commands 1 to 4 are the evidence; 3 and 4 ran last, with no edit after them. Free disk stayed at 15 GB.

## Slice S1 — round 2 (G2 tester, 2026-10-06)

**Outcome: no bug found; criteria 14 and 16 hold.** One new finding, F11-S1-4 (test-quality, low): the source
test of criterion 15 guards the spellings in use today and lets other spellings through. All 165 of the
tester's tests pass; the whole `LedgerDomainTests` target passes on the host (1,109 tests).

Specification: the brief's "Plan amendments — slice S1 after round 1" (criteria 14 to 17). Under test: 4812a2e
with the implementer's fixes uncommitted on top. The tester's files are now 26 (21 suites, 4,628 lines); two
are new and uncommitted. No product code and no test of the implementer's was edited.

### Round 1's findings

| Finding | State |
|---|---|
| F11-S1-1, a name of only invisible characters is stored | Closed by ruling (criterion 17: kept as built). The pinning test stays and passes. |
| F11-S1-2, `upward` and `downward` for the plan's `up` and `down` | Closed by ruling (criterion 17: kept as built). |
| F11-S1-3, three gaps in the implementer's tests | Closed for this slice: covered by the tester's suites, as round 1 said. Not re-examined: whether the implementer's own tests changed in those three places. |

### The implementer's edit to the tester's files

`git diff 4812a2e -- LedgerKit/Tests/LedgerDomainTests/Adversarial/Programs/` before the tester touched
anything: 15 lines changed in `ExerciseFilterAdversarialTests.swift` and 1 in
`EditingPublicSurfaceAdversarialTests.swift`, each `ExerciseSearch.filter(` to `ExerciseSearch.filtered(` and
nothing else. As sanctioned.

### The two expectations changed for criterion 14

Both changes follow the criterion's wording ("returns the day as it was when the slot already has that
progression"; "changing from linear to double still makes the top of the range at least reps + 2"). Nothing
else in either test changed, and both pass with the change alone: neither failed for another reason.

| Where | Old expected value | New expected value |
|---|---|---|
| `DayEditingFieldsAdversarialTests.setProgression_fromEveryPair_keepsOrRaisesTheTop` | Target Double: top = max(top, reps + 2), from any progression | Target Double from Linear or Fixed: top = max(top, reps + 2). Target Double from Double: top unchanged. (Other targets: top unchanged, as before.) |
| `DayModel.setProgression`, the model behind `DayEditingModelAdversarialTests.editSequence_matchesTheModelAtEveryStep(seed:)` | Sets the progression; for Double, top = max(top, reps + 2) | Returns at once when the slot already has that progression; otherwise as before |

The display name of the first test was reworded to match. Of that test's 6,615 cases, 30 expect another
value than in round 1: Double to Double for the 30 pairs with top = reps + 1. The reach suite still meets
all 24 rules with the new model.

### Findings

**F11-S1-4 — test-quality, low. The source test of criterion 15 catches today's spellings, not the intent.**
- Rule: criterion 15, "a source test over `LedgerDomain/Programs` fails when a function that returns a
  `Program` or a `DayTemplate` is missing from the property's tables, or when a line outside `newSlot` assigns
  a slot's misses or exercise or builds a `Slot`."
- The test does what it says for the code as it is written now, and
  `EditingSourceScannerAdversarialTests.scanner_catchesTheSpellingsItWasWrittenFor` shows it: a new
  `static func … -> DayTemplate`, a line naming `misses` or `exerciseID`, and `Slot(` are all caught.
- What it would miss, each shown by feeding the line to the implementer's own scanner (the two "pinned as
  built" tests of the same suite, which pass today and are to be turned round if the scanner is widened):
  - **An edit that is not a `static func` with a bare result.** Not found, so never asked to be in the
    tables: an instance method (`func resettingMisses() -> DayTemplate`), a `mutating func`, a `class func`,
    a result of `DayTemplate?`, `[DayTemplate]` or `(Program, Bool)`, an `inout Program` parameter, and a
    signature with a `where` clause after the result.
  - **A write that names neither field.** Not flagged: a whole slot assigned (`slots[index] = slots[index - 1]`,
    `slots = other.slots`), a key path (`slots[index][keyPath: field] = value`), a slot built as
    `let copy: Slot = try .init(…)` or decoded (`decode(Slot.self, …)`), and any code after `//` inside a
    string literal on the same line (the comment stripper cuts the line there).
  - **Read from the test, not run:** only the folder `LedgerDomain/Programs` is scanned, so an edit added
    under `Rules/` or as an extension in `Model/` is not seen; a table row is matched by its name, not by
    what its closure calls, so a row named after a function that it does not call passes; `editing` and
    `normalized` are exempt by name, so a write placed inside either is drawn by the property only through
    the rows that call them.
- Expected against actual: the criterion's words ("a function that returns…", "assigns…", "builds a `Slot`")
  are wider than the scanner. Nothing is wrong today: the property itself still catches any of these writes
  in a function that is in the tables. The gap is a new function in an unrecognised form.
- Smallest repro: `EditingSourceTests.editFunctions(in: ["func resettingMisses() -> DayTemplate {"])` is
  empty.
- Options: leave it and say so in the test's comment; or match `func` in any form with a result that
  mentions `Program` or `DayTemplate`, and flag any assignment to `slots[…]` or `.slots` outside the helpers.

### Attacked and held

Seeds as in round 1 (`PropertySeed.all`, 200 in the PR lane; the six seeded suites once more at 2,000). No
seed failed.

| Criterion | Attack | Cases | Suite |
|---|---|---|---|
| 14 | The progression a slot already has, chosen again, returns the same day by value (a three-slot day, the slot joined and with a miss), from each of the 735 pairs and each progression | 2,205 | `EditingRoundTwo…` |
| 14 | A range narrowed to reps + 1 after Double stays narrow under a second and a third Double, for reps 1 to 30, coming from Linear and from Fixed | 180 checks | `EditingRoundTwo…` |
| 14 | To Double, away, to Double twice, away, from each pair and from Linear and Fixed: the top is max(top, reps + 2) after every step and never more; every slot accepted by `Slot.init` | 735 × 2 sequences of 5 | `EditingRoundTwo…` |
| 14 | Reps pushed under Double (8–10 to 10–11), then Double again: unchanged | 1 | `EditingRoundTwo…` |
| 14 | Every pair × every progression from × every progression to, with the new expectation; 16,000 seeded day edits (160,000 once) against the updated model; purity; the commutation with a save | 6,615; 200 seeds × 80 | `DayEditingFields…`, `DayEditingModel…`, `EditingCommutes…` |
| 16 | The renamed `filtered` against the tester's own filter: every chip or none × every equipment or none × 20 queries, in its order; the shuffled catalog; core, kettlebell, band, short names, custom exercises; public under a plain import | 960; 20 seeds | `ExerciseFilter…`, `EditingPublicSurface…` |
| limits named once | `RPE.range` is 5…10 and `RPE(_:)` accepts exactly the eleven halves in it over every hundredth from −5 to 15, refuses NaN and 5.000…01; a deload is still 2 lower and never below 5 for all eleven; `RestDuration.secondsRange` is 30…300, the step 15, and `init(seconds:)` accepts exactly nineteen values in −1,000…1,000 and neither end of `Int`; `Program.minimumWeeks` is 2, `Program.init` refuses 0 and 1 weeks with `tooFewWeeks`, "−" refuses 2 and takes 3 | 2,001; 11; 2,001; 5 | `EditingRoundTwo…` |
| 1 to 13 | Everything of round 1 again, unchanged but for the two expectations above: the 18 exit tests, both models, the 7,172 moves, the names, the start loads, the prescriptions | 154 tests | as round 1 |

### Not verified

- Coverage, the simulators and the full gate, as in round 1.
- `EditingSourceTests` itself was read and its scanner driven, but the tester did not add a function to the
  product to watch the real test fail: product code is not the tester's to edit.
- The implementer's other test changes (14 files modified) were not reviewed.
- The implementer's notes and `review.md` were not read.
- The mutation check of round 1 was not repeated for the two new suites.

### Commands

All from the worktree root on the final tree; 3 and 4 ran last, with no edit after them. The full gate is the
orchestrator's and was not run. Free disk: 12 GB.

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'LedgerDomainTests\.(ProgramEditing\|DayEditing\|Editing\|ProgressionPrescriptions\|ExerciseFilter)\w*AdversarialTests'` | 0 | 165 tests in 21 suites passed |
| 2 | The same with `LEDGER_PROPERTY_SEED_COUNT=2000` | 0 | 165 tests in 21 suites passed |
| 3 | `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerDomainTests` | 0 | 1,109 tests in 171 suites passed |
| 4 | `scripts/check.sh --lint-only` | 0 | OK |

An earlier run of command 4 in this round exited 2 on one line of the tester's own new file that was three
characters too long; the test's display name was shortened and commands 1 to 4 were run again.


## Slice S3 — round 1 (G2 tester, 2026-10-06)

Commit under test: `57d12ab` on `feat/F11-s3-program-update` (specification `312728c`), Swift 6.4.

I wrote the tests from the specification's eleven criteria, the planner's sections of the notes ("Saving and a
live workout", "Inputs the implementer needs › S3") and the doc comment of `ProgramRepository.update`. The
expected values come from a model of my own (`UpdateModel`: programs as values) and from `save` given the same
result. I read the two implementations, the implementer's tests and the new contract clauses only after my
tests had been written and run once (31 tests then; three expectations of mine were wrong, see "Corrected").
I have not read the implementer's section of the notes.

**Result: no bug found. One spec question (F11-S3-1). Every test of mine passes (32 tests, 282 cases).**

### What was written

All under `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`. Three kinds of store: an in-memory database,
a WAL file opened as the apps open it, and the in-memory stores (`UpdateKit.Place`).

| File | Tests (cases) | What it attacks |
|---|---|---|
| `ProgramUpdateRefusalAdversarialTests.swift` | 6 (59) | Criteria 2 to 4. Sixteen results that must be refused, each on three stores: ids another program holds (week, day, slot), a slot id used twice, an exercise that is not stored, another program id (unused; program 2's with program 1's rows; program 2 itself), U+0000 in a name and in a tag, one week, a dangling schedule, a gap in the week indices, 99 sets, an inexact load, a change that throws after computing. The error is the one `save` gives for the same result (or `duplicateIdentifier` naming the result's id), the same on the database and in memory; every row of every table, `updated_at` included, is as before; the change ran once; no watcher heard anything. A program not stored or deleted: `setActive`'s error, the change never runs. Deleted, replaced by `save`, updated again |
| `ProgramUpdateRowsAdversarialTests.swift`, `…EditsAdversarialSupport.swift` | 5 (55) | Criteria 5 and 6. Five routes back to the stored program (as given; rebuilt through every `init` with the weeks backwards; through JSON; reversed and restored; fields taken away and put back), on the active and the inactive program: SQLite counts no changed row, no row differs, no watcher hears it. Fifteen edits: the rows written are exactly the ones the edit names (by table and id), the same rows `save` writes on a twin database, and the two databases are then equal row for row; in memory against `save` and against the database. A watcher hears a ten-row update as one whole program |
| `ProgramUpdateActivityAdversarialTests.swift` | 3 (9) | Criterion 6's last clause: fifteen updates of the inactive program leave the active one active; a result that turns `isActive` on deactivates the other, and one that turns it off leaves none, as `save`. History: a finished workout reads the same after an update deletes its day and every other |
| `ProgramUpdateLostAdversarialTests.swift`, `…LaneAdversarialSupport.swift` | 5 (33) | Criterion 7. The losing sequence through `save` (loses both) and through `update` (keeps both). A hundred concurrent increments through two repositories over one queue end at 100 and return 1 to 100. Sixty increments over two connections to one file. Six lanes racing updates, workout saves with misses and swaps, reads, saves of the other program and `setActive`; half of the seeds through `ProbedStores(yields: 2)`. **A self-check:** the same lanes and the same counter against `ThreeStepPrograms` (read, change, save) do report losses (on 7 or 8 of 8 seeds in my runs; the test asks for half) |
| `ProgramUpdateModelAdversarialTests.swift` | 2 (81) | Criterion 7 against a model: 40 seeds of 36 calls on the database and in memory (updates with nine edits, a change that throws, a refused result, workout saves on either program's slots with stored and unknown exercises, a builder's stale whole save, delete, `setActive`), compared with `UpdateModel` after every call, `isActive` included. A second test shows the scripts reach every case |
| `ProgramUpdateCancelAdversarialTests.swift`, `…CancelRaceAdversarialTests.swift` | 5 (33) | Criterion 8, with a change of ten rows in three tables. Cancelled before the call; from inside the change, before and after it computed; while waiting behind another update whose change is held at a gate (0, 5, 200 and 5,000 yields); at 80 moments that close in on the commit (a call cancelled too early doubles the canceller's wait, one cancelled too late halves it); 30 of 60 concurrent calls cancelled beside a lane of workout saves. Each time: all stored and returned, or none stored and `CancellationError`; no call that was never cancelled fails; the store then takes an update and a workout's save |
| `ProgramUpdateProbeAdversarialTests.swift` | 6 (12) | Criterion 9 and the app's edges: the probe forwards results and errors and records each call; a held update stores nothing, and when let go applies to the program as stored then (a workout's save and another update landed meanwhile); `fail` before and after storing; a held update cancelled; a change that starts another update without waiting for it; fourteen updates and a workout's save read back after the file is closed and reopened |
| `ProgramUpdateAdversarialSupport.swift` | | `UpdateKit` (the three stores, a read that does not disturb activity, SQLite's change count), `UpdateSnapshot`, `UpdateGate` (a change waits at it for at most 20 s, so no test can hang), `ThreeStepPrograms` |

Seeds: `PropertySeed.all.prefix(8)` for the lanes (17, 7936, 15855, 23774, 31693, 39612, 47531, 55450),
`prefix(40)` for the model scripts (17 + 7919·n, n = 0…39), 1106 for the moments of cancellation, and 3, 58,
2026 for the cancelled half. No sleeps; nothing depends on a wall clock.

### Findings

#### F11-S3-1 — spec question — criteria 8 and 9: a cancelled update ends differently on the two stores

Both stores keep criterion 8 as written (all or none; `CancellationError` only for none). They choose
differently, at the same moment:

| The task is cancelled… | Database (memory and file) | In-memory stores |
|---|---|---|
| before the call | `CancellationError`, change not called, none | the same |
| inside the change (before or after it computed) | `CancellationError`, **none** (rolled back) | returns, **all** stored |
| while the call waits behind another write | `CancellationError`, **none**, change not called | returns, **all** stored (none only if the task had not yet entered the call) |
| at seeded moments around the write | none or all | all, except when the task had not started |

Counted in one run of the cancellation tests: the database ended 165 calls with none and 10 with all; the
in-memory stores 83 with all and 5 with none.

Minimal repro (the in-memory half; my tests pin the database's half, which is what ruling 5 asks for):

```swift
let stores = InMemoryStores(seed: …)                    // any stored program `id`
let handle = Mutex<Task<Program, any Error>?>(nil)
let task = Task { try await stores.programs.update(id) { program in
    handle.withLock { $0?.cancel() }                    // set by the test before the change runs
    return renamed(program)
} }
// database: `await task.result` is .failure(CancellationError) and the name is unchanged
// in memory: .success, and the new name is stored
```

Expected: not stated. Criterion 8 allows both; criterion 9 says the in-memory stores follow the database, and
the fake's doc comment says it does not here ("a task cancelled later stores its change whole, where the
database rolls back"), so the implementer chose this knowingly. Why it is worth a ruling: S13's store is tested
over the in-memory stores, and the case it must handle on a phone (the screen goes away while a write is in
flight: `CancellationError`, nothing stored, edits still waiting) is the one the fake never produces after the
call has started. A fake that checked `Task.isCancelled` once more under its lock, after the change returned
and before storing, would end the first two rows as the database does. No test of mine fails for this.

### Attacked and held

- **Criteria 2 to 4** — 16 refusals × 3 stores, the missing and the deleted program × 3 stores, watchers on 2:
  the error equals `save`'s (or `setActive`'s) each time and nothing at all was written.
- **Criterion 5** — 5 routes × 2 programs × 3 stores: zero rows changed by SQLite's count, no watcher woken.
  (An unchanged update of the active program still runs one `UPDATE program SET is_active …` that matches no
  row, exactly as `save` does. It writes nothing and wakes nobody.)
- **Criterion 6** — 15 edits × 2 databases against the rows I listed and against `save`; 15 in memory.
- **Criterion 7** — 100 concurrent increments × 3 stores; 60 over two connections (all 60 stored, none
  refused); 8 seeds × 3 stores of six racing lanes (144 calls each); 40 seeds × 2 stores of 36 modelled calls.
  Inside every change the lane checks that the program it is given holds its own last workout save: it always
  did. The three-step update fails these same tests, so they can see a loss.
- **Criterion 8** — never a part of a change stored, in the 263 cancelled calls one run judges; never an error for a
  caller that was not cancelled; the database's three deterministic endings are pinned (`wasCancelled`).
- **Criterion 9** — probe forwards, holds, fails, and a held call applies to what is stored at release.
- **Criteria 10 and 11** — read, not tested: the four doubles' edits are mechanical (`git diff 312728c 57d12ab`);
  the stub throws as its neighbours do and its test lists the call; no existing contract clause changed (the
  diff of the contract files only adds clauses), no migration, no fixture touched. The whole
  `LedgerPersistenceTests` target passes on the host (see the commands).
- **The implementer's tests** (read afterwards) assert behaviour: results are compared with expected programs
  and row sets, not only "does not throw".
- Ten consecutive host runs of the final suites: no failure.

### Corrected (mistakes of mine, not findings)

Three expectations of mine were wrong and are corrected; none was the product's fault.

1. The first "unchanged writes nothing" test traced SQL statements and failed on the active program: the
   zero-row `UPDATE` above. A statement that matches no row is not a write, and `save` runs the same one, so
   the test now uses SQLite's count of changed rows (`totalChangesCount`) and the row-for-row dump.
2. On the simulator (first run) the race around the commit failed its own self-check, "some cancelled call was
   stored": it cancelled after at most 400 yields, and there no update commits that soon, so all 80 calls ended
   with none. All 80 verdicts held. The canceller's wait now adapts (see the table), so the test reaches the
   commit on any machine.
3. The self-check of the lanes asked the three-step update to lose on 8 of 8 seeds; one host run in about ten
   gave 7. A loss needs two callers to overlap, which no seed promises. It now asks for half.

### Not attacked

- **A change that calls the store synchronously** (for example `queue.read` inside the change). GRDB traps on
  re-entrant access, which would kill the test process; the type already keeps a change from awaiting anything.
  Left out, as the task allows.
- **Two processes** on one file, and a crash (kill) in the middle of an update. Two connections in one process
  are covered; a relaunch after a clean close is covered.
- **The unimplemented stub and the four doubles by a test of my own** (the stub is internal to
  `LedgerDependencies`, which this test target does not link). Read only.
- **A program whose rows are damaged** when `update` reads it.
- **Row timestamps in memory**: the in-memory stores expose none, so "nothing written" is judged there by both
  programs, the active one and the watchers.
- Not S3's, noted in passing: `save`, `update`, `setActive` and `delete` all take their timestamp before they
  wait for the writer, so a write that waited can stamp a row earlier than the write that ran before it. It is
  the behaviour on `main`; whether M4's sync minds is that brief's question.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'ProgramUpdate.*Adversarial'` (ten times, final tests) | 0 each: 32 tests in 8 suites, 282 cases (the filter also runs F10 S3's 7 tests in LedgerSyncTests, which pass) |
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'LedgerPersistenceTests'` | 0: 549 tests in 125 suites, 1 known issue (not mine) |
| `scripts/check.sh --lint-only` | 0 |
| iOS simulator, PR plan, `-only-testing:LedgerPersistenceTests` (through the lock) | Run 1: 65. 548 counted, 536 passed, 10 skipped, 1 expected failure, **1 failed**: my own race around the commit, its self-check ("Corrected" 2). Run 2, after that correction and with the history test: **0**. 537 passed, 0 failed, 10 skipped, 1 expected failure. Both result bundles read and deleted |

## Slice S3 — round 2 (G2 tester, 2026-10-06)

Under test: `d77550f` plus the implementer's uncommitted fixes for criteria 12 to 14. My round 1 files were
untouched (`git diff d77550f -- LedgerKit/Tests/LedgerPersistenceTests/Adversarial/` was empty) and all 32
tests passed on the fixed code before I changed anything.

**Result: F11-S3-1 closed. One new finding, F11-S3-2 (the two stores disagree; one test of mine fails and
stays failing). 35 tests of mine: 34 pass, 1 fails.**

### F11-S3-1 — closed

The in-memory store now ends a cancelled call as the database does. Shown by, on all three stores:
`cancelledBeforeTheCall_…`, `cancelledInsideTheChange_…` (before and after the change computed) and
`cancelledWhileWaiting_…` (0, 5, 200, 5,000 yields) in `ProgramUpdateCancelAdversarialTests`, each now
requiring `CancellationError`, nothing stored and, before the call and while waiting, that the change never
ran; and `heldAtTheProbeAndCancelled_sameEndingOnBothStores`. Each still ends with `stillWorks` (an update
and a workout's save are then taken and kept).

### F11-S3-2 — bug (minor) — criterion 12: cancelled inside a change whose result is refused before any statement, the database throws the refusal, the in-memory store `CancellationError`

Test: `ProgramUpdateCancelAlikeAdversarialTests.cancelledInsideTheChange_everyResult_sameEndingOnBothStores`
(fails, deterministically: 7 of 36 results differ; 5 runs). The task is cancelled inside the change; the
change then returns its result.

| Result returned by the cancelled change | Database | In memory |
|---|---|---|
| another program id (unused; program 2's; program 2 itself) | `duplicateIdentifier("program …")` | `CancellationError` |
| one week only | `tooFewWeeks(count: 1)` | `CancellationError` |
| a schedule naming a day the program lacks | `danglingSchedule(…)` | `CancellationError` |
| week indices with a gap | `nonContiguousWeeks(…)` | `CancellationError` |
| a slot of 99 sets | `setsOutOfRange(99)` | `CancellationError` |

Minimal repro: cancel the task from inside the change (a handle in a `Mutex`), return
`try Program(id: otherID, …)`; compare `"\(error)"` on `LinkedStores.make(.database)` and `.memory`.

Expected (criterion 12): `CancellationError` on both, nothing stored. Actual: nothing is stored on either
(checked row for row), but the database reports the refusal. Cause, from the diff: the in-memory store checks
the task again right after `change` returns; the database only notices a cancelled task at its next SQL
statement, and the id check and `ProgramRows.init` (the `init`s' validation) throw before one runs. The other
29 results agree: the 9 refusals found by a statement or a column (`CancellationError` on both), a change
that throws (its own error on both), 5 unchanged results and 15 edits (`CancellationError` on both). Either a
`Task.checkCancellation()` after `change` in the database's `update`, or a ruling that a refusal may win over
a cancellation, settles it. Impact is small: no builder edit produces such a result, and nothing is written.

### My edits

- `ProgramUpdateCancelAdversarialTests.swift`: the two `if place != .memory` guards are gone, so "inside the
  change" and "while waiting" demand `CancellationError` on the in-memory store too; the waiting call counts
  its change's runs (must be none).
- `ProgramUpdateCancelAlikeAdversarialTests.swift` (new, 3 tests): the differential above over 36 results;
  a cancelled update of a program that is not stored or deleted (same ending on both); held at the probe and
  cancelled (strict, both stores, nothing written).
- `ProgramUpdateProbeAdversarialTests.swift`: unchanged in the end.

### Also looked for, and agreed

The product diff (`git diff d77550f -- LedgerKit/Sources`): the read-back after the write now throws
`missingRow` on both stores where it returned the change's result; not reachable by a test of mine (the result
has the program's id and was just written). `save`'s new warning and the reworded `change` paragraph are
documentation (criterion 13). Criterion 14 is what round 1's activity tests already hold.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test … --filter 'ProgramUpdate.*Adversarial'` before my edits | 0: 32 tests |
| the same after my edits (five times) | 1 each: 35 tests in 9 suites, 1 issue (F11-S3-2) |
| `swift test … --filter 'LedgerPersistenceTests'` | 1: 552 tests in 126 suites, 1 failure (F11-S3-2), 1 known issue (not mine) |
| `scripts/check.sh --lint-only` | 0 |
| Simulator | not run this round, as instructed |

## Slice S5 — round 1 (G2 tester, 2026-10-06)

Attacked `ProgramPresentation.make(_:)` at 3203d25 against the S5 amendment's eleven criteria, the brief's
criteria 1 to 6 and its "Copy (exact)". **No bug found.** 44 tests of mine (300 parameterised cases among
them), all passing on the Mac host and on the iOS simulator. Two questions, one note on copy, one on test
quality. My tests were written and run before I read a function body, the implementer's tests or the catalog;
the implementer's section of the notes was not read at all.

Tests: `LedgerKit/Tests/FeatureProgramTests/Adversarial/` — `ProgramAdversarialSupport.swift` (seeded programs;
an action applied as its documentation tells the store, each edit one `ProgramEditing` call spelled by me),
`ProgramAdversarialScreen.swift` (my own model of the screen as a flat list of lines, from the brief),
`ProgramSeedAdversarialTests`, `ProgramActionsAdversarialTests`, `ProgramWeekdaysAdversarialTests`,
`ProgramCountsAdversarialTests`, `ProgramTotalityAdversarialTests`, `ProgramWordsAdversarialTests`.

### Findings

**F11-S5-1 — spec question (low) — criterion 3 against the plan's "Brief vs main" row 20: what orders the strip.**
The amendment says "the seven cells in the order of the settings' week start"; the plan's row 20 says the strip
starts on the weekday of `program.startDate`, "so left to right is the order the days come in". The code follows
the amendment (pinned by `everyWeekStart_ordersTheCellsFromIt`, seven starts). The two differ when the week start
is not the weekday the block began on (the lifter changed the setting after the block began; F08 starts a block
on the week start). Repro: the seed program (starts Monday 2026-08-17) with `settings.weekStart = .sunday`.
- Actual: "S REST · M UA · T REST · W LA · T REST · F UB · S LB".
- By the Domain (`WeekCalendar.weekIndex`, a program week is seven days from `startDate`), week 1 is Mon 17 to
  Sun 23 August: the first cell drawn is the week's last day. No day moves to another weekday; only the reading
  order is not the order the days come in.
- Asked: is the amendment's order the wanted one in that case, or row 20's? Nothing to fix if the amendment stands.

**F11-S5-2 — spec question (low) — criteria 1 and 3: a cell of a program with no training days.**
With `days == []` each of the seven cells still carries `.edit(.cycleSchedule(week:weekday:))` and speaks
"Double-tap to assign". Applied, the edit returns the program as it was (`ProgramEditing`: "a program with no
days stays at rest"), and no notice is shown: a tap that does nothing and says nothing
(`noDays_readsZeroAndRests`). `Cell.action` is not optional, so the model cannot disable a cell. S13 will send
an `update` that changes nothing (S3 criterion 5: no row written). The same holds for "Copy week n" and "Apply to
later weeks" when the schedules are already equal. Asked: intended? The implementer's tests pin it as intended.

**F11-S5-3 — copy (note, no defect of this slice) — numbers and plural forms follow the locale handed in, over
English words.** Measured on the seed program:
- `en_US` groups thousands in every text: "BLOCK · 1,200 WEEKS", chip "W1,101", "WEEK 1,101", "Copy week 1,100",
  "Week 1,200 has logged sessions and can't be removed.", "6 days · 6,480 sets a week", "~6,156 min". Reached only
  from 1,000 weeks (the block has no upper limit) or 1,000 sets.
- `ar_SA`: "BLOCK · ٨ WEEKS", "W١" / "١ DAY", "٤ days · ٥٨ sets a week", "Copy week ٧"; `hi_IN@numbers=deva` alike.
- `ja_JP` (no singular in Japanese): a week of one day reads "1 DAYS", spoken "1 days".
- `fr_FR`: "0 DAY" by the same rule (standards §7 pins it for another key).
This is standards §7 as written, and the implementer pins it for the copy members. It becomes visible only if
S13 hands in a locale whose language the catalog lacks; until a translation ships, S13 should hand in the
locale the app runs in (English), not the region's language.

**F11-S5-4 — test-quality (minor, no action asked).** The implementer's property suite takes its expected
texts from `ProgramCopy` (`checkBlock`, `checkDays`) and its `BuilderScreen.tap` applies an edit through
`ProgramBuilderEdit.applied(to:)`: both are the code under test. Nothing escapes, because `ProgramCopyTests`
pins every member against a literal and `ProgramBuilderActionTests` pins `applied` against `ProgramEditing`,
and the fixed tests assert the brief's literals. Their tests assert behaviour; their source test bans more
spellings than mine (`Calendar(identifier:`, formatters) and tests itself. My suites add the check that is
independent of both.

### Texts the brief does not give (all found on screen by `everyText_isTheBriefsOrListedOrData`)

Every other text drawn or spoken on the seed's eight weeks (with an added empty day, a missing exercise and
each notice) matched a pattern of the brief's "Copy (exact)", a weekday's letter or name, or data.

| Text | Where | Judgement |
|---|---|---|
| "Block length" | spoken label of "−" and "+" as one adjustable element | Clear. Fine. |
| "8 weeks" / "1 week" | its spoken value | Fine; "1 week" cannot be reached (two weeks at least). |
| "Week 3" | a chip's spoken label | The plan's decision 6 ("Week 3, 4 days"). Fine. |
| "4 days" / "1 day" (spoken) | a chip's spoken value; the same key as the summary's "4 days" | Fine. One key, two uses; its comment says so. |
| "Deload" (spoken) | a deload chip's spoken value; the same key as the toggle's title | Fine in English; a translator cannot split the two uses. The day count is not spoken for a deload week, as it is not drawn. |
| "Rest" | a rest cell's spoken value | The plan's "Tuesday, rest". Fine. |
| "Double-tap to assign" | every cell's spoken hint | From the brief's Accessibility line ("button — double-tap to assign"). Apple's guidance is that a hint names the result and not the gesture ("Assigns the next training day"); VoiceOver adds its own "double-tap to activate". For Pete or the S9 VoiceOver table. |
| "—" (em dash) | a card's chip for an exercise that is not stored | The plan's "named by a dash". Not spoken (chips are not). Fine. |
| "1 DAY", "1 exercise", "1 set", "1 set a week", "1 day" | singular forms | The brief gives only the plural; the plan's row 18 asks for `one`. Fine. "~1 min" has one form. |
| "BLOCK · 1 WEEK" | catalog form, cannot be reached | Fine. |
| "New day" | the name `addDay` carries | Brief criterion 5. Data once stored. |

Not in the model, so nothing to judge here: titles for "−" and "+" (icons, spoken as the adjustable above), the
delete confirmation, the empty and failed states (S6, S13).

### Attacked and held

Seeds: programs from `SplitMix64(seed)` for seeds 1…60 (actions) and 101…140 (purity); the walk's choices from
`SplitMix64(seed × 7919)`. `seeds_reachEveryState` shows the sixty programs hold: no days, six days, two weeks,
a deload, an empty day, a day of more than four slots, a drop set, a superset, an exercise that is not stored.
`testersModel_isNotBlind` shows my model tells an edit, a selection, a notice, a week start and a tag apart.

- **Criterion 1, text for text** (11 tests, one of them over the 8 weeks): header, "BLOCK · 8 WEEKS", W1–W7 "4 DAYS" and W8 "DELOAD",
  the strip, "4 days · 58 sets a week", four cards, minutes 39, 38, 37, 31 from `TimeEstimate`, chips (four names
  and "+1"), every week of the block against my model, "WEEK 8 · DELOAD" with the toggle on, "Copy week 7", no
  "Apply to later weeks"; criterion 2 as amended (UA, LA, UB, LB, REST; the chip 5, 5, 5, 5, 4 DAYS; five taps
  give the seed back); criterion 3 (copy, apply, deload; deload flags left); criterion 4 ("+" appends week 8's
  three days, not a deload, selected; "−"; the logged last week; earlier logged weeks do not hold it); criterion 5
  ("New day" / "D5" / "No exercises yet", the route with the selected week); behaviour 6 (the fifth tap carries
  the notice, the sixth drops it).
- **Every action applied** (60 seeds × 3 properties, 6 day counts × 7 weekdays, 3 more): no action of any screen
  names a week other than the selected one, a weekday twice, or a day not held, for selections from −2 to
  count + 1; every edit offered equals my one `ProgramEditing` call and "−" never offers an edit the Domain
  refuses (three sets of logged weeks); a walk of forty actions per seed keeps the whole screen, notice
  included, equal to my model after every step; the cycle on every weekday for one to six days touches no other
  cell and no other week; "−" on two weeks is the notice whatever is logged and changes nothing else.
- **Week starts and locales** (7 tests, 17 cases among them): seven week starts; letters and spoken names in English,
  German and Japanese written by hand, Arabic against a `DateFormatter` on seven known dates (seven distinct
  letters); the calendar's first weekday (1…7), time zone (four, to UTC+14 and UTC−11) and own locale change
  nothing; seven other calendar identifiers (Hebrew, Umm al-Qura, Persian, Chinese …); a cell's spoken value agrees with its label in all eight weeks.
- **The selected week** (9 cases): `Int.min`, −1000, −1, 0, 3, 4, 5, 1000, `Int.max` on five weeks: the screen is
  exactly the nearest week's, and every action names it.
- **Counts and plurals** (5 tests + 3 cases): 0, 1, 2, 7 days on a chip; one exercise, one set, one minute; no
  days; drop sets in the sets; a superset's minutes (a fixture where joining changes them); four, five and six
  exercises; blocks of 2, 16 and 52 weeks by six days with every week a deload.
- **Notices** (6 cases + 1): the three texts word for word, week numbers 1, 3, 8, 52; header, block, week and
  days unchanged by a notice.
- **Words and sources** (5 tests + 8 cases): every text classified (above); no literal but "" and " · " and no
  lookup outside the copy files; all 33 lookups name `.module`, and exactly those with a value name `locale:`;
  21 ambient spellings absent from the module's nine files. Catalog read by hand: 33 keys, all `translated`,
  seven counted keys with `one` and `other` and one `%lld` each, no key with two numbers.
- **Purity and totality** (40 seeds + 14 names + 9 locales + 2): the same input twice; the exercises inserted in
  another order into a dictionary of another capacity; unused exercises, units, start date change nothing; a
  slot of a missing exercise is counted, timed and reads "—"; names of 0 to 20,000 characters, Arabic, Japanese,
  emoji, combining marks, bidi override, format specifiers ("%@ %lld") drawn as stored; odd locales and logged
  weeks (`Int.min`, `Int.max`); a schedule entry for a day no longer held reads REST and is not counted.
- **Measured, not kept as a test**: sixteen weeks by six days of eight exercises, 100 calls in 0.74 s on the
  host in a debug build (7 ms a call; the budget is 100 ms for the first frame).

### Not attacked

- Anything a store does: which locale and calendar it hands in, that an edit reaches the stored program once,
  an edit computed on the screen's program and applied to a stored one that differs, when a notice is dropped
  (S13).
- Views, snapshots, Dynamic Type, VoiceOver as heard (S9). The spoken texts were checked as strings only.
- A program `Program.init` refuses, beyond a schedule entry for a missing day: duplicate day ids, week indices
  that are not their places. A program emptied of its weeks was not run by me (the implementer tests it).
- A translated catalog (none exists); right-to-left layout.
- `scripts/check-string-catalogs.sh`, `ModuleCopyTests`, coverage and the full gate (the orchestrator's);
  criterion 11's wiring was not checked beyond the test plan running the target.
- The ambient locale and time zone were not changed under the process; purity there rests on the two source scans.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FeatureProgramTests.*Adversarial'` (first run that compiled) | 1: 41 tests, 1 issue, in my own scan (it counted one-line lookups only; corrected, not a finding) |
| the same, final | 0: 44 tests in 6 suites, 300 parameterised cases |
| `swift test … --filter 'FeatureProgramTests'` | 0: 105 tests in 11 suites (61 the implementer's, 44 mine) |
| `xcodebuild test -project Ledger.xcodeproj -scheme Ledger -testPlan PR -destination <iPhone 17, iOS 27.0, by UDID> -only-testing:FeatureProgramTests …` through the simulator lock, once | 0: 105 tests passed, 0 failed, 0 skipped; bundle read and deleted |
| `scripts/check.sh --lint-only` | 0 |

## Slice S5 — round 2 (G2 tester, 2026-10-06)

Attacked the implementer's uncommitted fixes on f22bc30 against criteria 12 to 16. **No bug found.** 54 tests of
mine now (44 of round 1, nine of them updated, and 10 new in `ProgramAbsoluteAdversarialTests.swift`), 559
parameterised cases counted in the log, all passing on the host and on the simulator. One new question (F11-S5-5).

### Round 1's findings

| Finding | State |
|---|---|
| F11-S5-1, the strip's order | Closed by ruling 15: kept as built. Still pinned by `everyWeekStart_ordersTheCellsFromIt`. |
| F11-S5-2, a cell of a program with no days | Closed by ruling 13 and fixed: no action, no hint, no "Tap to assign"; verified in every state (below). "Copy week n" and "Apply to later weeks" on equal schedules still offer an edit that changes nothing; the ruling does not ask otherwise. |
| F11-S5-3, the locale's digits and plural forms | Closed by ruling 15: kept; the store hands in the app's locale (S13). |
| F11-S5-4, the property suite's expected texts | Closed: no action was asked. |

### New finding

**F11-S5-5 — spec question (low) — criterion 14: "the model carries … a `rename` action".** The model carries
no such value: `ProgramBuilderModel.Header` has `eyebrow`, `name` and `namePlaceholder` as before, and the
action is the static function `ProgramBuilderAction.rename(_:)`, which a view calls with the draft's text ("the
one action a view makes itself"). It behaves as the ruling wants (`rename_typedText_isCleanedOnce`: one
`renameProgram` edit of the text as typed, no notice; blank and control-only text change nothing; sent twice
it is one rename), and a function of the typed text cannot be an `Equatable` field without a closure. Asked:
is the static function what the ruling means by "carries"? If so, nothing to fix; S9's view test should then
show the field sends this function's value and no edit of its own spelling.

### Audit of the nineteen sanctioned edits (`git diff f22bc30 -- LedgerKit/Tests/FeatureProgramTests/Adversarial/`)

Nineteen change sites in seven files, all spelling at a call site; none adds, removes or weakens an
expectation by itself. No finding.

| File | Sites | What |
|---|---|---|
| `ProgramActionsAdversarialTests` | 3 | `offered` skips a cell with no action (`compactMap`); the `strays` pattern names `setDeload` and `setSchedule`; one `#require(cell.action)` |
| `ProgramAdversarialScreen` | 3 | my expected deload action respelt `.setDeload(true, …)` and my expected cell action `.setSchedule(…, day: nil)`; `week.hint ?? "absent"` |
| `ProgramAdversarialSupport` | 2 | the two cases of `AdvStore.edited` call `setDeload` and `setSchedule` |
| `ProgramCountsAdversarialTests` | 2 | `#require(cells[0].action)`; `.setDeload(true, week: nearest)` |
| `ProgramSeedAdversarialTests` | 4 | `.setDeload(true, week: 7)`; `.setSchedule(…, day: nil)`; two `#require(…action)` |
| `ProgramWeekdaysAdversarialTests` | 2 | `.setSchedule(…, day: nil)`; `spokenHint ?? ""` |
| `ProgramWordsAdversarialTests` | 3 | `week.hint ?? "REST"`; the hint listed when present; `#require(cells[0].action)` |

The six respelt payloads (`true`, `day: nil`) are placeholders: the old cases had no such value, so a value
had to be written and the right one was mine to derive. They are why the nine tests failed, and nothing else
was. `week.hint ?? "REST"` follows the file's own idiom for an absent text.

### My nine updates (each failed only on a placeholder payload or on criterion 13)

| Test | Round 1 expected | Now expected (criterion) |
|---|---|---|
| `seed_deloadWeek_readsAsTheBrief` | toggle action `.toggleDeload(week: 7)` | `.setDeload(false, week: 7)`: the week is a deload, the switch turns it off (12) |
| `seed_tuesdayTappedFiveTimes_cyclesAndCounts` | each tap `.cycleSchedule(week: 0, weekday: .tuesday)` | taps 1 to 4 name the seed's days in order, tap 5 names rest (12) |
| `sundayStart_seed_rotatesTheStripOnly` | every cell `.cycleSchedule` of its weekday | every cell names my own next of its cycle; Saturday (LB, the last day) names rest (12) |
| `selectedWeek_outOfRange_isTheNearestWeek` | `.toggleDeload(week: nearest)` | `.setDeload(` the other state `, week: nearest)` (12) |
| `noDays_readsZeroAndRests` | a cell's tap changes nothing and says nothing | no cell has an action or a hint, the week has no hint, each speaks its weekday and "Rest" (13) |
| `seed_everyWeek_matchesTheTestersScreen`, `walk_everyStep_matchesTheTestersScreen`, `blockLengths_readTheirWeeks`, `testersModel_isNotBlind` | through my model: `.toggleDeload`, `.cycleSchedule` | through my model, changed in one place: the deload action names `!isDeload`; a cell's action names `AdvScreen.next(…)?.id`, or is absent with both hints when the program has no day (12, 13). The model now also compares each cell's spoken hint |

Two more changes to my own files, neither to satisfy the feature: `strays` now also refuses a cell action that
names a day the program does not hold; my model's chip count now counts only entries of days the program holds
(spec §3.2). The second was a fault of my model that round 1 never reached; the new no-days test with dangling
entries found it, and the feature was right.

### Attacked and held (new, `ProgramAbsoluteAdversarialTests`, seeds 201…260 through `AdvProgram.random`, one slot given misses; choices from `SplitMix64(seed × 104729)`)

- **Applied twice** (60 seeds × 2): every cell action of every week, and the deload switch of every week,
  give once and twice the program with exactly that entry (my own cycle) or that flag changed; the result is
  one `Program.init` accepts; after the switch its action names the other state.
- **A program that changed meanwhile** (1 test, 6 cases in it): a cell action whose day was deleted changes
  nothing and leaves no dangling entry; after a day was added the weekday becomes the day the cell promised,
  not the new day; after the week was removed nothing changes; the deload action on a removed week changes
  nothing, and on a week switched off meanwhile leaves it off. Note for S13: a week is named by its place, so an
  edit for week 8 sent after "−" and "+" lands on the new week 8.
- **`nextInCycle`** (0 to 6 days): from rest, from every day, from an id not held; walked from rest it visits
  every day once and returns to rest.
- **`setSchedule`, `setDeload`** (60 seeds × 20 draws): weeks `Int.min`, −1, count, 1000, `Int.max` and a day not
  held change nothing; one entry or one flag changes and nothing else; days (so misses and exercises) equal;
  idempotent; valid. `cycleSchedule` and `toggleDeload` still give my cycle and the other state (60 seeds).
- **No training day** (blocks of 2, 3, 9 weeks × selections −1…count × 7 week starts × a program with no
  entries and one with entries left dangling, notices and logged weeks varied): seven cells, none with an
  action or hint, no "Tap to assign", "REST" / weekday / "Rest", and the rest of the screen equal to my model;
  after "+ Add training day" the seven actions name the new day with the empty-day notice and both hints return.
- **`rename`** (10 texts + 1): blank, spaces, control-only, trimmed, inner control characters removed, NEL,
  Japanese, emoji, format specifiers; 20,801 characters stored and drawn whole.

### Not attacked

As round 1, and: the store's use of the draft name (S13); criterion 16's housekeeping (the source test's
`Double` spellings, the notes, standards §7), which is the reviewer's; the implementer's new and changed tests
were run, not read.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test … --filter 'FeatureProgramTests.*Adversarial'` before my updates | 1: 44 tests, the nine named above failing |
| the same, after updates and new tests | 0: 54 tests in 7 suites |
| `swift test … --filter 'FeatureProgramTests'` | 0: 120 tests in 12 suites |
| `swift test … --filter 'LedgerDomainTests'` | 0: 1212 tests in 185 suites |
| `xcodebuild test … -testPlan PR -only-testing:FeatureProgramTests` (iPhone 17, iOS 27.0) through the lock, once | 0: 120 passed, 0 failed, 0 skipped; bundle deleted |
| `scripts/check.sh --lint-only` | 0 |

## Slice S6 — round 1 (G2 tester, 2026-10-08)

Attacked 63f397f against the slice's ten criteria, the brief's criteria 7 to 11 and "Copy (exact)". **No bug
found.** 53 tests of mine in 8 suites (81 cases), all passing on the host and on the simulator. Six findings:
three questions about cases the specification leaves open, two notes on copy, one note on a mark. None changes
what a lifter sees on a seed day.

Tests are in `LedgerKit/Tests/FeatureProgramTests/Adversarial/DayEditor*Adversarial*.swift` (11 files). I wrote
a model of the screen from the brief ("Copy (exact)", criteria 7 to 11), product spec §3.4 and the slice's
criteria (`DayEditorAdversarialScreen.swift`, `DayEditorAdversarialPanel.swift`). It reads the input and the
Domain and never the feature. The feature's model and mine are both written as lines "key=value" and compared
line by line. I learnt the feature from declarations and doc comments only; I read no function body, no S6
test and no implementer's note before my tests ran. Afterwards I read the feature's bodies and skimmed the
implementer's tests; I did not read the implementer's notes at all.

Where my first expectation was wrong, I say so here rather than hide it: I had the confirmation's title carry
the day's whole name (the brief's "Delete Lower B?" is the short title, which the feature prints); I had
"Bench Press" for the catalog's "Barbell Bench Press"; three sums of my own were off (a minute count, a rest, a
linear load in a deload week). The feature was right each time.

### Findings

- **F11-S6-1 — spec question (criterion 3; brief "Copy (exact)", sub line).** In a deload week a row's sub line
  prints the week's RPE, two lower, beside the slot's own range or step. Repro: seed program, Lower A, week 8:
  Back Squat reads "Barbell · +5/wk · RPE 6 · 3 min rest" (the slot holds RPE 8). The brief gives the format
  and not which RPE. The scheme and load on the same row are the week's, so the week's RPE is coherent, and I
  recommend keeping it and saying so in the spec. My model follows the feature here and says so in its comment.
- **F11-S6-2 — spec question (criterion 5).** `WeekLine.isHeld` and `Entry.isHeld` are false in a deload week
  that follows a missed week, where the Domain's prescription has `isHeld == true`. Repro: Back Squat with
  `misses = [6]`, week 8: eyebrow "WEEK 8 · DELOAD", strip "W8 240 (deload)", both flags false. The texts are
  the spec's ("DELOAD or HELD"). The flag means "printed as held", which its declaration does not say; a view
  that colours by the flag will follow the text. Recommend one sentence on the two fields.
- **F11-S6-3 — spec question (criteria 2 and 3; behaviours 13 and 19).** A slot whose exercise is not stored
  keeps its own sets and RPE in a deload week, while its neighbours lose a set and two points, and the meta
  line counts its own sets. Repro: three slots of 3, 4 (+ drop) and 3 sets, no exercise stored, a deload week:
  rows "3×8", "4×8", "3×8", meta "Week 3 · 3 exercises · 11 sets · ~25 min"; with exercises stored the first
  row reads "2×8". Rule 12's set and RPE need no exercise. It follows `TimeEstimate`'s documented fallback and
  cannot be reached in M1 (nothing deletes an exercise). Pinned as built; a ruling is wanted before F12 lets an
  exercise go.
- **F11-S6-4 — copy.** One catalog key serves two meanings: "REST" is the schedule's rest day and the
  stepper's label for rest between sets; "Rest" likewise for the two spoken texts. The comments say so. English
  is right; a translation cannot give them two words. Split when a second language comes.
- **F11-S6-5 — copy (criterion 7, spoken texts).** Spoken texts reuse the drawn abbreviations. A row's spoken
  value is "3×12 · 100 lb · Cable · Reps 12–14 · RPE 9 · no rest"; a linear row says "+5/wk"; a stepper's value
  is "45s", "2:30" or "50 lb". There is no spoken form of its own for any of them. How VoiceOver reads "×",
  "/wk" and "45s" is not established here; it belongs to the VoiceOver table of S10 and S11.
- **F11-S6-6 — note (criterion 10).** "Remove" is marked relative, as the criterion asks, and is in fact
  idempotent: over seeds 1 to 40 every removal applied twice gave what one gave (more than 50 removals, none
  differed), while moves did differ. Both statements of the implementer are true. The mark costs nothing: a relative edit is
  only never sent again, and no edit is sent again after a failed save (S1 ruling, "For S13 and S14").

Answers to the brief's direct questions:

- **Both superset actions at once** is a state the specification allows: product spec §3.4 e shows "Break out"
  on any exercise that is not the first of its group, and "Superset with next" on the last of a group that is
  not the day's last. The last member of a superset followed by another exercise meets both. Checked on
  [1, 2, 3A, 3B, 4] with 3B open, and on every grouping of up to six slots.
- **A stepper at its limit** is offered and holds the value (the plan's behaviour 11): the one control that is
  offered and can do nothing. Nothing else offered left the day as it was.
- **Criterion 1 names a calendar in the input; the input has none.** Nothing on this screen reads a weekday or
  a date, so none is needed. Not a finding.
- **Letters past Z.** The 27th member of a superset is numbered ("127" for the 27th of group 1). Thirty joined
  slots draw without a trap and with thirty different indices. Out of reach of any real day.

### Texts the brief does not give

| Text | Where | Judgement |
|---|---|---|
| "Delete day" | the button at the foot | The plan's decision 6. Fine. |
| "Day name" | the name field's placeholder and spoken label | Plain, matches "Program name". Fine. |
| "Week 1 · No exercises yet" | meta line of a day with no exercise | The builder's own words after the week. Fine. |
| "W5 190 (held)" | a held week in the strip | The brief gives " · HELD" for the eyebrow and "(deload)" for the strip. "(held)" matches the strip's form. Pete should see it once. |
| "—" | name of a row whose exercise is not stored | Behaviour 19. Fine; spoken as "2A, —", which VoiceOver may skip. |
| "drop · RPE 8 · no rest" | sub line of such a row | Equipment and progression left out. The range and "Fixed" need no exercise and could stay; minor. |
| "Sets", "Reps", "Rep floor", "Top of range", "Start load", "Target RPE", "Rest" | steppers' spoken labels | The drawn labels in sentence case. Fine. |
| "Superset" | the header's spoken label | Fine. |
| "4A, Lat Pulldown" and "3×12 · 100 lb · Cable · …" | a row's spoken label and value | See F11-S6-5. |
| "kg" for "lb" in every line that prints a load | rows, week line, notes, start load | Decision #9. Fine. |
| "Kettlebell", "Band" | equipment in the sub line | The brief's chips leave them out; the catalog has them. Fine. |
| "1 exercise", "1 set", "It's scheduled in 1 week. …" | singular forms | Decision 6 and the Definition of Done. Fine. |

### Attacked and held

- **The brief's examples, word for word** (10 tests): Upper A's header, rows 1, 2, 3, 4A, 4B with sub lines,
  schemes and loads; "Barbell · +5/wk · RPE 8 · 2:30 rest"; Incline DB Press's strip "W1 50 · W2 50 · W3 50 ·
  W4 52.5 · W5 52.5 · W6 52.5 · W7 55 · W8 47.5 (deload)" and reps 10, 11, 12, 10, 11, 12, 10, 11; Back Squat
  "W8 240 (deload)", "WEEK 8 · DELOAD", "4 × 5 @ 240 lb · RPE 6"; "WEEK 4 · HELD" after a miss; the six
  steppers' labels and values; rest "45s", "2 min", "2:30"; the three notes and both drop-set notes; the
  confirmation in 7 weeks, 8 weeks, 1 week, nowhere.
- **The whole screen against my model**: 280 seed screens (4 days × 2 units × weeks 1 to 7 × each slot open and
  none); seeds 1 to 25 × 2 units × every week × each slot open, deload weeks in a test of their own.
- **Every action applied and drawn again** (seeds 1 to 10, over 400 actions): `applied(to:)` equals the Domain
  call I spell, and the next screen equals my model of the result. Each stepper's "−" and "+" equals
  `DayEditing.set(DayEditing.stepped(…))`.
- **Steppers pressed** (seeds 1 to 12 × 250 presses, pounds and kilograms) against a counter of my own: every
  limit, the reps and top-of-range coupling, exact loads. Each limit holds with both buttons offered. Steps for
  7 kinds of equipment × 2 units (5 / 2.5 lb, 2.5 / 1.25 kg, kettlebell 5 lb / 2 kg). A slot's own step wins.
  180 lb in kilograms reads "81.6 kg" and steps to 82.5 and 80. A hundred steps up and down return "52.5 lb"
  and "23.75 kg". "1000000 lb" and "RPE 8.5" draw whole; a start load of zero holds at "0 lb".
- **Absolute and relative** (seeds 1 to 40, with slots of exercises not stored): only moves and removals are
  marked; every other edit applied twice is once.
- **Offered only when it can do something**: 321 panels (every grouping of 1 to 6 slots × each slot open):
  moves exactly when `DayEditing.move` changes the day, "Break out" and "Superset with next" by §3.4 e.
  Criteria 10 and 11 through the model's own actions; behaviours 8 and 9; the drop-set switch; remove.
- **Superset letters and headers**: all 63 groupings of 1 to 6 slots against `DayEditing.groups`.
- **Stale and odd inputs**: an open slot not held, or of another day; a day not held; weeks `Int.min` to
  `Int.max`; no slots; one slot of one set; a first slot stored as joined; exercises not stored (seeds 1 to
  30); misses in any weeks (seeds 1 to 60); actions of one program applied to it after the day was deleted, a
  slot removed or moved (seeds 1 to 8, over 800 applications): equal to the Domain's call, other days untouched.
- **Purity**: same input, same model; an extra exercise changes nothing; a German locale changes no load, RPE
  or rest. My scan of the 11 new files finds no clock, calendar, locale, zone, random draw or default, and no
  text outside the copy files but "" and " · "; every lookup names the module's bundle, and the locale when it
  carries a value.
- **The words** (seeds 1 to 16, over 2,000 texts): every text is the brief's by pattern, or one listed above.
- **`resolvedStartLoad` / `resolvedStep`**: 64 slots (the seed's 16, each four ways) × 2 units equal the old
  pair of fallbacks; 2,048 prescriptions equal spec §7.2 worked by me, with misses; the start load's stepper
  goes to the next multiple from the old pair.

### Not attacked

- The implementer's tests were skimmed for shape, not reviewed line by line; no mutation of product code.
- The catalog against the compiler's keys, and coverage: the gate's.
- VoiceOver's reading of any text; any view or store (none exists yet).
- Locales other than `en_US` beyond one German check; right-to-left; digits of other scripts (S5 ruling 15).
- A program with no weeks; a day holding one slot id twice (the implementer has a test of each, not checked).
- Performance.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'DayEditor.*Adversarial'` | 0: 53 tests in 8 suites |
| the same with `--filter FeatureProgramTests` | 0: 252 tests in 24 suites |
| `xcodebuild test -project Ledger.xcodeproj -scheme Ledger -testPlan PR -destination <iPhone 17, iOS 27.0, by UDID> -only-testing:FeatureProgramTests …` through the simulator lock, once | 0: 252 passed, 0 failed, 0 skipped; bundle read and deleted |
| `scripts/check.sh --lint-only` | 0 |

`LedgerDomainTests` was not run by me: I changed nothing there. Free disk stayed between 7.6 and 8.0 GB.

Round 1 complete.

## Slice S6 — round 2 (G2 tester, 2026-10-08)

Attacked the implementer's uncommitted fixes on 90fadb4 against criteria 11 to 16. **No bug found.** 59 tests of
mine now in 9 suites (53 of round 1, seven of them passing again after four edits, and 6 new in
`DayEditorSupersetRestAdversarialTests.swift`), all passing on the host. One new note, F11-S6-7.

`git diff 90fadb4 -- LedgerKit/Tests/FeatureProgramTests/Adversarial/` was empty before I began: none of my
files had been touched.

### Round 1's findings

| Finding | Now |
|---|---|
| F11-S6-1, the week's RPE on a deload row | Closed: kept as built (criterion 15). My model already follows it. |
| F11-S6-2, `isHeld` false in a deload week | Closed: kept as built (criterion 15). Pinned by my test. |
| F11-S6-3, a missing exercise keeps its own sets in a deload week | Closed for M1: kept as built (criterion 15). Still wants a ruling before F12 can delete an exercise. |
| F11-S6-4, one key for "rest" the day and the pause | Kept as one key with a comment; see F11-S6-7. |
| F11-S6-5, spoken texts reuse abbreviations | Deferred to F15. |
| F11-S6-6, remove is marked relative and is idempotent | Closed: kept (criterion 15); the comment on `isRelative` now says the mark follows the list. |

### My seven tests that pinned the old rest line

All seven failed for this one reason and no other; each passes after the edit. Four edits cover them.

| Test | Old expected | New expected |
|---|---|---|
| `seed_upperA_rowsReadAsTheSpec` | 4B "Cable · Reps 15–17 · RPE 9 · 1 min rest" | "… · 1:15 rest" (Lat Pulldown rests 75 s, the raise 60 s) |
| `seed_progressionAndDropSet_readAsTheBrief` | Lower A 3B "Machine · Fixed · RPE 9 · 1 min rest" | "… · 1:30 rest" (Leg Press 90 s, the calf raise 60 s) |
| `slotOfAMissingExercise_isListedUnderADashAndRemovable` | 2B "RPE 8 · 1:30 rest" | "RPE 8 · 2:30 rest" (2A rests 150 s, 2B 90 s) |
| `seed_everyDayWeekUnitAndOpenSlot_agreesWithTheTestersScreen`, `seededDays_outsideADeload_…`, `seededDays_inADeloadWeek_…`, `everyAction_appliedAndRedrawn_isTheTestersScreen` | my model printed the last member's own rest | one line of `DayEditorAdversarialScreen.swift`: the longest of the group's members' rests, taken by my own `max` |

### Findings

- **F11-S6-7 — note (criterion 14).** The brief's criterion 14 still asks for separate keys for "rest" the day
  and "rest" the pause. The code keeps one key each for "REST" and "Rest", with a comment naming both uses, as
  the orchestrator told me the criterion was withdrawn (the English text is the key). The brief's text and the
  code now disagree; the criterion should be struck or reworded in the brief so the reviewer and the gate read
  the same rule.

### Attacked and held

- **The superset's rest line, three callers agreeing**: all 63 groupings of 1 to 6 slots (192 groups) with
  rests and sets drawn per grouping. The row after each group's last member prints my own longest rest; every
  other member prints "no rest"; the workout built from the same day by `SessionBuilder` rests the same, read
  by the call the engine's reducer makes when a round's last set is logged (`SupersetRounds.groupRest(block:exercises:)`
  over `blocks(in:)`); and `TimeEstimate.minutes` equals decision #14's formula written out by me.
- **The longest rest at any place** of a superset of three (first, middle, last): shown after the last; the
  stepper still shows the slot's own rest; broken out, each row shows its own again.
- **The seed**: Upper A's superset reads 1:15 and Lower A's 1:30; Upper A's workout rests 2:30, 1:30, 1:30, 1:15.
- **Nothing else moved in the estimate**: the seed's four days are 39, 38, 37, 31; seeds 1 to 40 × every week
  (deloads, drop sets, slots of exercises not stored), with and without prescriptions, equal the old formula.
  `git diff 90fadb4` removes no line from `TimeEstimateTests.swift` or `SupersetRoundsTests.swift`: every value
  pinned before still stands.
- **`TimeEstimate.setCount`**: for a day with a week's prescription, for a day as written and for several days,
  against my own sum on the same seeds; 58 for the seed (18, 15, 15, 10); 0 for no slots and for no days; the
  builder still reads "4 days · 58 sets a week"; Upper A reads 18 sets in week 1 and 13 in week 8, Upper B 11
  in week 8 with its drop set kept.
- **Criterion 13**: an example of my own. On a fixed slot of 8 reps with top 12, the queue "top of range 9",
  "Double" gives top 10 once and top 9 sent twice; neither edit is marked relative, and each alone drawn again
  over its own result changes nothing.

### Not attacked

- The workout's rest was read through the reducer's own call on a built session, not by driving the engine set
  by set. The engine's code is unchanged by this round apart from that call's body.
- The implementer's changed tests were run, not read. No simulator run this round (the orchestrator's gate).
- Review S-4 (no whole model inside an expectation) is the reviewer's to confirm.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test … --filter 'DayEditor.*Adversarial'` before my edits | 1: 53 tests, the seven named above failing |
| the same, after the edits and the new suite | 0: 59 tests in 9 suites |
| `swift test … --filter FeatureProgramTests` | 0: 260 tests in 25 suites |
| `swift test … --filter LedgerDomainTests` | 0: 1222 tests in 186 suites |
| `scripts/check.sh --lint-only` | 0 |

Free disk stayed between 7.0 and 8.2 GB.

Round 2 complete.

---

## Slice S10 — round 1 (G2 tester, 2026-10-10)

Tested at `de60be7` (branch `feat/F11-s10-day-editor-views`); no product file changed. Six new files in
`LedgerKit/Tests/FeatureProgramTests/Adversarial/`, all named `DayEditorViews…Adversarial…`: 29 tests in 5
suites and two support files; two earlier tester files strengthened. **One test fails on purpose** (finding
2); two more record a product-owner question as a known issue (findings 1 and 3). No reference image was
recorded or changed: every check is a measurement of the hosted view.

### Verdict: one layout defect on small phones; the day's name is cut from one step above the default size, not from `.accessibility3`; the rest held

Criteria 5, 6, 7, 8, 10 and 12 held in the previews' seven states and in eight of my own. Criterion 11 is
not met in two places (findings 1 and 2).

### Findings

| # | Severity | What | Test |
|---|---|---|---|
| F11-S10-1 | **should fix, or Pete accepts** (open question 2 of the notes, with its facts corrected) | **The day's name is cut from `.xLarge`, not from `.accessibility3`.** The notes' finding 1 says the seed's name "fits at the default size and ends in '…' at `.accessibility3`". Measured from the field's own attributed text against its text rectangle, and looked at once as pictures: on a 375 pt phone "Lower A — Squat focus" and "Lower B — Hinge focus" read "Lower A — Squat foc…" from `.xLarge` (325 pt of text in 323), "Upper A — Push focus" from `.xxLarge`, "Upper B — Pull focus" from `.xxxLarge`; on an iPhone 17 the two Lower days at `.xxLarge` with Bold Text, and they and Upper A from `.xxxLarge`. Up to `.large` all four fit on both widths, plain and bold (Lower A with Bold Text by 3 pt on 375). The implementer's ink measure weighs the whole header, in which two lost letters are under its 6 % band: that is why his sweep saw the cut only at `.accessibility3`. | `DayEditorViewsFieldAdversarialTests.seedNames_aboveTheDefaultSize_areDrawnWhole` (known issue at `.xLarge`, `.xxLarge`, `.xxxLarge`, `.accessibility3`); `seedNames_upToTheDefaultSize_areDrawnWhole` passes and guards the default |
| F11-S10-2 | **should fix** (a defect; one line) | **On a short screen the pinned header is squeezed and its text cut.** `DayEditorScreen` is `VStack { header; ScrollView }` with nothing that keeps the header at its own height, so the stack offers the header half of the screen and a header that needs more gives in. Upper A's header needs 325 pt at `.accessibility5` on 375 pt. Hosted with the 647 pt an iPhone SE leaves under its status bar it is given 320 pt; with 603 pt (a 44 pt bar above it) 302 pt, a line of text less. Nothing squeezes at `.accessibility3` and `.accessibility4`, nor on an iPhone 17. No test of the implementer's hosts the screen at that height. Fix: the header at its ideal height (`.fixedSize(horizontal: false, vertical: true)` or a layout priority). | `DayEditorViewsRoomAdversarialTests.smallPhone_headerIsNotSqueezed` — **fails at `.accessibility5`**, left failing |
| F11-S10-3 | note, for Pete (the notes' finding 2, measured) | **What the pinned header leaves the page**, on the hosted screen, in closed rows of the seed program. 375 × 667 (20 pt status bar): 7.0 rows at `.large`, 4.5 at `.xxxLarge`, 2.4 at `.accessibility1`, 2.1 at `.accessibility2`, **1.5 at `.accessibility3`, 1.2 at `.accessibility4`, 0.8 at `.accessibility5`** (header 320 of 647 pt, one row is 424 pt). iPhone 17: 9.4, 7.6, 4.1, 3.0, 2.1 at `.accessibility3`, **1.8 and 1.5** at the two largest. Under two rows from `.accessibility3` on the small phone and from `.accessibility4` on an iPhone 17; a tab bar or navigation bar is not counted. On 375 pt the header is also 26 pt higher than on 402 pt at `.xxLarge` (190 against 164: the summary line wraps). | `DayEditorViewsRoomAdversarialTests.page_showsAtLeastTwoRows` (known issue at those five cells) |
| F11-S10-4 | note | **A one-word exercise name is broken in two at the two largest sizes.** "Hyperextension" (the catalog's longest word) stands whole up to `.accessibility3` on both widths, and is drawn on two lines at `.accessibility4` on 375 pt and at `.accessibility5` on both. Every letter is drawn, so no weight of ink shows it. No line holds the word at those sizes; listed, not failed. | `DayEditorViewsLayoutAdversarialTests.oneWordName_besideItsNumbers_isNotBroken`, `oneWordName_overItsNumbers_isNotBroken` (pass, up to `.accessibility3`) |

### Audit of the implementer's edits to earlier testers' files (`git diff main..de60be7 -- '*Adversarial*'`)

| File and test | Edit | Verdict |
|---|---|---|
| `ProgramViewsSourceAdversarialTests.scan_readsEveryView` | 14 → 22 | **Kept**: `Views/` holds 22 files that are no preview. |
| `…views_sendOnlyTheModelsActions` | ten lines added | **Lost a little, restored.** The list is exact. But `ProgressionChips` sends a fourth bare `send(action)`, and the pin that each bare `action` is unwrapped from the model still counted 3 with a pattern that does not know `chip`: the fourth was unpinned. Now `(cell|chip|control|model)`, 4, and the count of bare sends must equal it. |
| `…views_keepNoStateButTheDraft` | three states, three `.onChange` | **Kept**: the contract gives the alert's flag to the view. (The test's title still says "the draft and the two fields' focus".) |
| `…views_readOnlyTheTextSize` | 2 → 4 | **Kept**: the set is still the text size alone. |
| `…views_numbers_areTheTwo` | two `90`s | **Kept** (the caret's quarter turn; deviation 9a). |
| `ProgramViewsPreviewAdversarialTests.registry_holdsTheNamedStates` | seven names | **Kept.** |
| `ProgramViewsTreeAdversarialTests.tables_areTheOraclesTrees` | `allCases` → builders and libraries, `throw` for `.dayEditor` | **Lost, restored.** The Day editor's seven tables were checked against no tree but the implementer's own. `DayViewsOracle` writes them from the plan's tree and "Inputs for the views"; the test takes `allCases` again. All seven tables match. |

### Attacked and held

- **Trees (criteria 5, 6, 10)**: eight states of mine (`DayViewsState`: no exercise; a held week; an unstored
  exercise open; the deload week with a superset's first exercise open; the last exercise of the day open;
  twelve exercises with a superset of three, its last open, both superset actions; loads of "12,345.5 lb";
  a long day name, one-word and long exercise names, a superset note of three lines) read exactly the
  oracle's tree at `.large` light, `.accessibility5` dark and right to left. An absent control is an absent
  stop.
- **Actions (criterion 12)**: every stop of the fifteen states sends exactly the oracle's actions (a
  stepper swiped down, up, up); the previews at `.accessibility5` too. With a store in the loop every
  exercise of three days opens under its own row and closes again, the tree exact after each tap.
- **Criterion 1 from outside** (`everyString_isDrawnAndSpokenWhereTheNotesSay`): each of the open double
  day's 91 strings is changed in turn; the drawing changes exactly when the notes draw it and the tree
  exactly when they speak it. With every string empty no stop says a word. The placeholder and the alert's
  four texts are the model's; "Cancel" sends nothing, the confirming button the model's action once.
- **Colour (criterion 8)**: with the two facts cleared, no state of the fifteen draws an orange pixel in
  either theme; a page is orange exactly in the three states whose model says so; the orange disappears
  with the eyebrow's words and stays under other words; the same at `.accessibility5` with Bold Text.
- **Layout (criteria 10, 11)**: the eight states at `.xxxLarge`, `.accessibility1`, `.accessibility5` on
  both widths, plain, bold and right to left: no stop empty, outside the page, under 44 pt or over another.
  No chip, slot action or "Add exercise" is cut in three states. A stepper's two round buttons, which are
  no stops, are 44 pt each by their pixels (96 × 44 at `.xSmall` and `.large`). The name field's row is
  44 pt. The caret points down closed and up open, right to left too. The strip's shown week is ink (213
  against 113). A stepper draws `label`, not `spokenLabel`.
- **The name field**: four stored names (one empty, one of spaces) through focus, blur and changes of the
  stored name: the field shows what the rule says and sends nothing; after three changes under the focus a
  blur takes the last.
- **The screen**: a drag on the page dismisses the keyboard (`UIScrollView.keyboardDismissMode`).

### Mutations (23, switched at run time in the views; the sources put back, `git status` clean)

Each mutant ran against 17 groups of existing tests and 16 of mine in one process; the baseline with no
mutant recorded no issue. **The three size sweeps among the existing tests (`words_areDrawnWhole`,
`longExerciseName_isDrawnWhole`, the S9 `previews_layOutSoundly`) ran at `.large` and `.accessibility5`
only, and the source scans not at all** (the switch itself changes the sources): a miss below is a miss of
the hosted tests at those sizes.

| | Mutant | Existing tests | Mine |
|---|---|---|---|
| A | the caret never turns | **missed** (the references too) | `caret_pointsDownWhenClosed_upWhenOpen` |
| B | the strip's shown week grey, the others ink | references only | `strip_shownWeekIsInk` |
| C | a stepper draws `spokenLabel` ("Sets") | **missed** (the references too) | `stepper_drawsTheLabel`, `everyString…` |
| D | a row's place ("4A") not drawn | references only | `everyString…` |
| E | the header's tag not drawn | references only | `everyString…` |
| F | no keyboard dismissal on drag | **missed** | `screen_dragDismissesTheKeyboard` |
| G | `rename` sent for a name that came from the store | caught | caught |
| H | "Cancel" sends the delete | caught | caught |
| I | the chosen chip stays a button | caught | caught |
| J | "Move up" and "Move down" swapped | caught | caught |
| K | a held week's eyebrow grey | caught | caught |
| L | a stepper's "−" sends increment | caught | caught |
| M | a row's numbers not kept at their own width | **missed** | **missed**: the row lays out the same in every state tried (the numbers are the less flexible part and are sized first); it would differ only for numbers wider than half a row |
| N | the summary line on one line | caught | not caught |
| O | "Delete day" above "+ Add exercise" | caught | caught |
| P | a row never stacks at accessibility sizes | references only (`row_accessibilitySize_stacks` passes) | `oneWordName_overItsNumbers_isNotBroken` |
| Q | a deload week's strip entry orange | caught | caught |
| S | the chips in a row that does not wrap | caught | not caught |
| T | a superset's note on one line | caught | not caught |
| U | "Program" and "Done" exchanged | caught | caught |
| V | the name field's row not 44 pt | references only | `nameField_is44PointsHigh` |
| W | a row's sub line on one line | caught | not caught |
| X | the drop set's note not drawn (still the hint) | references only | `everyString…` |

Three were missed by every existing test and are caught now; six were caught by a reference image alone and
have a measurement now; one (M) changes nothing that can be seen.

### Gate time

`FeatureProgramTests` alone, on the same simulator and options: **212 s on `main`'s tests** (S9's last
whole-bundle run, `f11s9/fix2.log`: 425 tests; `main` has not changed the target since), **388 s at
`de60be7`** (the implementer's `run3.log`: 465 tests), **428 s with my additions** (494 tests). The whole
iOS step was 732 s on `main` earlier today (another lane's gate) and 832 s on this branch. Of the 176 s the
slice adds: `DayEditorLayoutTests` 127 s (the ink sweep: 12 sizes × 6 settings × 19 parts, each drawn
twice, one of them 2,400 pt wide), `previews_layOutSoundly` +26 s and `ProgramViewsLayoutTests` +11 s (seven
more states). My five suites cost 41 s (trees 17, orange 11, layout 11, name 1, room 1). Cheapest saving,
if the hosted deadline is near: `words_areDrawnWhole` at four sizes instead of twelve, about 85 s.

### Not tested, and why

- **Typing** into the name field: a hosted `UITextField` passes no text to SwiftUI. So that a typed name is
  sent as `rename` with the day's id, a blank draft, a trailing space, and what the field shows when the
  store cleans the name under the caret are S14's UI tests.
- **A finger** on "−" and "+", on a row, a chip, the switch and the alert's buttons: activated through
  accessibility or UIKit's handler here, never tapped. A pressed control's look.
- **Increase Contrast**: only the implementer's one reference; I measured nothing under it.
- **The existing sweeps under each mutant at all twelve sizes**, and the source scans under a mutant.
- A device, VoiceOver itself, the screen in the app (it is in none), a tab or navigation bar above it.

### Commands and exit statuses (2026-10-10, in the worktree, every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `sim-test.sh … -only-testing:FeatureProgramTests`, final sources | 65, as intended: 494 tests, 492 passed, **1 failed** (`smallPhone_headerIsNotSqueezed`), 9 known issues, 428 s |
| `scripts/check.sh --fast` | 0: 1,223 tests, lint clean, 135 s |
| seven probe runs of my suites; three runs of the mutation driver (0 each, 264 cases each) | — |

Free disk stayed at 12 GB.

---

## Slice S10 — round 2 (G2 tester, 2026-10-11)

Tested at `4d22ec9` (the fix round `fe10b4b` and its notes), with the review's second pass (`b4f1ce0`) read;
no product file changed. Three new files in `LedgerKit/Tests/FeatureProgramTests/Adversarial/`
(`DayEditorViewsName…`, `…Focus…`, `…Title…`: one new suite, 15 tests) and edits to four of my own.
**Two tests fail on purpose** (findings 5 and 6). One known issue is left, at two cells (finding 3's
remainder). No reference image was recorded or changed.

### Verdict: rulings 14, 15, 17, 18 and 19 hold; two new defects around the name, both small and both about the title's tight line

Round 1's F11-S10-1 (the name cut) and F11-S10-2 (the header squeezed) are **closed**. The name is drawn
whole at all twelve sizes; the bar is never squeezed. What is new: with the focus the field cuts the name's
descenders, and a name's descender reaches into the tag's pill from `.xLarge`.

### Findings

| # | Severity | What | Test |
|---|---|---|---|
| F11-S10-5 | **should fix** (seen in the hosted drawing and in one picture of it, not on a device) | **With the focus the name's descenders are cut.** The field then draws the name itself, and its editor clips at the field's frame, which is the title's tight line: 33.7 pt for the 32 pt type at `.large`. The letters' box is 28.0 pt high without the focus and 24.7 with it at `.large`: the tails of "y", "p", "g" end flat ("Upper A — Gyp", looked at as a picture). Without the focus the name is a `Text` and whole. The builder's `ProgramHeader` has the same one-line field in the same type; I did not measure it. Cause is the same tight line as finding 6: the field needs the type's own line height, or room under it. | `DayEditorViewsNameAdversarialTests.focus_doesNotCutTheDescenders` — **fails** at `.large` and `.accessibility3` |
| F11-S10-6 | **should fix** (the review's B-2, confirmed and wider) | **A name's descender reaches into the tag's pill.** Lowest ink of the name against the pill's first row, at 3×: a wrapped "Lower B — Hinge focus" is 2.0 pt into the pill's rows from `.xLarge` on 375 pt, "Lower A — Squat focus" 1.3 pt from `.xxLarge` (0.3 pt clear at `.xLarge`), with ink inside the pill's own box; on an iPhone 17 from `.xxLarge` with Bold Text and `.xxxLarge` plain; both names 3.0 to 6.3 pt from `.accessibility1` on both widths. **A name of one line does it too** from `.accessibility2` ("Gyp": 2.0, 4.0, 5.3, 6.0 pt; 0.3 pt clear at `.accessibility1`), which the review does not say. Up to `.large` the gap is 11 pt and more. | `DayEditorViewsNameAdversarialTests.name_standsAboveTheTag` — **fails** at `.xLarge`, `.xxxLarge`, `.accessibility3` (all twelve sizes, plain and bold, were measured once; four are kept, plain) |
| F11-S10-3 | note, for Pete (unchanged in kind) | Under the pinned bar a 375 × 667 phone has room for **1.99** closed rows at `.accessibility4` and **1.36** at `.accessibility5`: the implementer's two figures, confirmed (my measure: 1.986 and 1.360). Every other cell has two and more (small phone 8.4 at `.large`, 2.3 at `.accessibility3`; iPhone 17 10.7, 2.9, 2.5, 2.3). The count is the room under the bar; the title block is now the first thing in it, and is not taken off. | `DayEditorViewsRoomAdversarialTests.page_showsAtLeastTwoRows` (known issue at those two cells) |
| F11-S10-7 | note | **An emptied draft** (the review's S-6, refuted as it reads): the placeholder does not hang over the tag or the summary. With the focus and an empty draft the field is 2.0 pt (`.accessibility3`) and 2.7 pt (`.accessibility5`) higher than the name's target, inside the 4 pt that part it from the tag, and the target is 2.3 and 2.7 pt higher than under one letter (50.0 against 47.7; 57.3 against 54.7): the rows under the name move by that at the first letter. Nothing at `.large` (44 and 44). | `…emptyDraft_keepsALine` (passes: both under 4 pt) |
| F11-S10-8 | note | **A draft of spaces shows nothing**: no letters and no placeholder, focus or not (UIKit keeps the placeholder back for a field that is not empty). Only a draft can be spaces; the stored name is cleaned. | `…emptyName_showsThePlaceholderOnce` (pins it) |

**The review's S-5 is refuted.** The bar in `DayEditorParts`, which the references draw, is as high as on
the screen: 60.0, 61.3 and 70.3 pt at `.large`, `.accessibility3` and `.accessibility5`, the same alone, in
the parts and on the hosted screen; its two buttons are 44 pt and stand above the heading
(`parts_barIsTheScreensBar`). The bar's parts are rigid, so `.fixedSize` in the screen changes nothing
(mutant h below). No 49 pt bar exists.

### Audit of the implementer's edits to my files

| File and test | Edit | Verdict |
|---|---|---|
| `DayEditorViewsRoomAdversarialTests.page_showsAtLeastTwoRows` | `isShort` narrowed to the small phone at `.accessibility4` and above | **Kept.** A known issue that is not recorded fails the test, so the narrowing is exact; the two cells are confirmed. Title and comment brought up to date. |
| `DayEditorViewsLayoutAdversarialTests.stepper_drawsTheLabel` | the expectation flipped | **Kept** (ruling 17). Renamed `stepper_drawsTheSpokenLabel`; title and comment say what it checks. |
| `DayViewsText.place(of:)` | a stepper's `label` drawn and spoken nowhere, `spokenLabel` both | **Kept**: `everyString…` still asks all 91 strings, and `label` must now change nothing. |
| `ProgramViewsSourceAdversarialTests.scan_readsEveryView` | 22 → 24 | **Kept.** |
| `…views_sendOnlyTheModelsActions` | the three sends named in `DayEditorBar` and `DayEditorHeader` | **Lost a little, restored.** `rename` is now built from what `NameField` hands over, and the place where it hands a name over was pinned nowhere. New: `nameField_handsTheNameOverOnce` (`onRename(text)`, once). |
| `…views_keepNoStateButTheDraft` | the draft, focus and three `.onChange` are `NameField`'s | **Kept.** Renamed `views_keepNoStateButDraftsFocusAndTheAlert`, with a title that lists what it pins. |
| (not edited, but stale) `…views_numbers_areTheTwo` | — | Renamed `views_numbers_areThePinnedFour`. |
| (new) | — | `views_spellNoColourButClear`: `Color.clear` is a colour outside the tokens that the S9 bans do not name; pinned at its two uses in `NameField`. |

`seedNames_aboveTheDefaultSize_areDrawnWhole` and its helpers are **deleted** (they measured the hidden
field). In their place, with no known-issue wrapper: `seedNames_areDrawnWhole` (twelve sizes, both widths,
plain and bold) and `otherNames_areDrawnWhole`. The measure is my own and not ink weight: the name field
without the focus must draw, pixel for pixel, what a text of mine draws (the name in the title's type with
no limit of lines, at the top of a 44 pt target). `measure_seesACutAndADouble` proves it on the round-1
case. `smallPhone_headerIsNotSqueezed` became `bar_isNeverSqueezed` (both phones, twelve sizes, the screen
also hosted 150 pt high).

### `NameField`, attacked

- **Drawn whole**: the four seed names at all twelve sizes on both widths, plain and bold; a long name, a
  name of one long word and one letter at four sizes; right to left and in the light theme. All identical
  to the whole text.
- **One of the two, never both, never neither** (found by hiding the `UITextField` and drawing again):
  without the focus the drawing is the same with the field hidden, and has letters; with the focus the text
  draws no letter and the field does; twice round, for a short and a long name, right to left too. An
  empty name: the text draws nothing, the placeholder is drawn once, by the field, with the focus and
  without.
- **The shift on focus** (letters' box at 3×, a one-line name): 0 pt sideways, **0.67 pt up** at `.large`,
  and inside the test's 1.34 pt at `.accessibility3` (not read more finely); back exactly when the focus leaves. The implementer's 0 and −0.7 to
  −1.0 pt stand.
- **The target**: the name field's frame holds every line of a three-line name, is 323 pt wide and at
  least 44 pt high; the `UITextField` stands on the first line (UIKit's `hitTest` finds it there and finds
  no text field on the last line, where the tap is the view's own gesture).
- **At the moment of focus**: a long name's target goes from three lines to one (44 pt at least), its top
  does not move, and is as before when the focus leaves; the one line ends at the page's edge.
- **The stored name changing**: without the focus the drawn name is the new one, whole; with the focus the
  field keeps its draft and the text stays hidden; the blur draws the stored name on its lines again.
- **While edited** (one line, accepted by ruling 15): the four seed names are whole up to `.large` on both
  widths; at `.xLarge` the two Lower days run out of the field on 375 pt (the field scrolls under the
  caret); at `.accessibility3` all four on both.
- VoiceOver: the trees of fifteen states still match my oracle exactly, so the drawn text is no stop.

### Mutations, round 2 (19, switched at run time; sources put back, `git status` clean)

The existing sweeps ran at **all their sizes** this time; only the S9 `previews_layOutSoundly` at two. The
baseline recorded my two failing tests and nothing else.

| | Mutant | Existing tests | Mine |
|---|---|---|---|
| N | the summary line on one line | references, the sweep | — |
| S | the chips in a row that does not wrap | the sweep, `chipsAndActions_wrap` | — |
| T | a superset's note on one line | references, the sweep (`words_areDrawnWhole`; `words_otherStates` no longer) | — |
| W | a row's sub line on one line | references, the sweep | — |
| a | the text stays ink under the focus (both drawn) | **missed** | `oneOfTheTwo_isDrawn`, `storedName…` |
| b | the field's text stays ink without the focus | references, the sweep | caught |
| c | the name on one line again | references, the sweep | caught |
| d | the drawn text read by VoiceOver | the trees | the trees |
| e | the field on the name's last line | `nameField_keepsItsPlaceWhenTheFocusComes` | caught |
| f | the name's target not 44 pt | references only | `nameField_is44PointsHigh` |
| g | under the focus the hidden text still wraps (the block keeps its lines) | **missed** | `focus_longName_isOneLine` |
| h | no `.fixedSize` on the bar in the screen | **missed** | **missed**: nothing changes, the bar is rigid |
| i | the title block pinned again | caught | caught |
| j | the tag after the summary line | references only | `name_standsAboveTheTag` (by its place) |
| k | the week's eyebrow never orange | the orange audit | caught |
| l | a stepper draws `label` again | the trees | caught |
| m | a tap on the name does not focus the field | **missed** | **missed**: no hosted test has a finger |
| n | the bar without its padding | references only | `bar_isNeverSqueezed` (60 pt) |
| o | the text draws the stored name, not the draft | **missed** | **missed**: differs only while typing |

**The thinned sweep lost no catch**: N, S, T and W are caught as in round 1. Two mutants are now caught
only by my tests (a, g); two need a finger or a keyboard and are S14's UI tests (m, o); one is no change
(h).

### Held from round 1

The trees and every stop's action in fifteen states against my oracle (unchanged: the bar's two stops,
then the page's); the 91 strings drawn and spoken where the rulings put them; the orange audit over whole
pages; frames, pills, the steppers' round buttons, the caret, the strip; the name field's draft rule; the
keyboard dismissal.

### Not verified

- A finger: a tap on the name's second or third line giving the focus (mutant m), a tap on "−" and "+".
- Typing: `rename` as typed, the drawn text following the draft (mutant o), the caret's place in a long
  one-line name.
- Finding 5 on a device: the cut descenders are measured in the hosted drawing of the focused field.
- Increase Contrast: nothing measured under it (the hosted drawing here sets no contrast trait).
- `ProgramHeader`, which is as on `main`.

### Time and runs (2026-10-11, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `sim-test.sh … -only-testing:FeatureProgramTests`, final sources | 65, as intended: **510 tests in 59 suites, 508 passed, 2 failed** (`focus_doesNotCutTheDescenders`, `name_standsAboveTheTag`), 2 known issues; **426 s of tests**, 443 s with the build |
| `scripts/check.sh --fast` | 0: 1,223 tests, lint clean |
| five runs of my suites while writing them; three of the mutation driver (0 each; 322, 322 and 276 cases) | — |

`FeatureProgramTests`: 428 s at the end of round 1, 372 s in the implementer's run on `fe10b4b`, 426 s here
(a run before I thinned two tests took 442 s; the machine's runs differ by tens of seconds).
`DayEditorLayoutTests`: 127 s → 52 s here (47 s in his run). My six suites together: 70 s (trees 20, name
21, orange 13, layout 12, room 3, the draft rule under 1); they were 41 s in round 1.

Free disk stayed at 12 GB.

---

## Slice S10 — round 3 (G2 tester, 2026-10-11)

Tested at `412033e` (fix round 2, `92a66af`, and its notes), under rulings 21 to 26; no product file
changed. Edits to three of my files; one test added. **Nothing is left red.**

### Verdict: ruling 21 holds with 1.3 pt to spare at the tightest cell; nothing else moved

### Findings

| # | Status | What | Test |
|---|---|---|---|
| F11-S10-6 | **closed** (ruling 21) | The name stands clear of the tag. Measured again at the twelve sizes on both widths, plain and bold, for two wrapped seed names, one-line "Gyp" and a long name that ends on a tail: **the least room between the name's lowest ink and the pill is 1.3 pt** (the long name, Bold Text, `.accessibility5`, 375 pt); for the seed names and "Gyp" 1.7 pt (Bold Text, `.accessibility5`, both widths); 2.0 pt at `.accessibility4` and at `.accessibility5` plain. No ink inside the pill in any cell. No cell is within 1 pt, but the tightest was not among the four kept sizes, so the kept test now also runs `.accessibility5` with Bold Text and asks for a point of room. | `name_standsAboveTheTag` (passes at five sizes) |
| F11-S10-5 | **known issue, for the queued `LedgerDesign` chore** (ruling 22) | Under the focus the descenders are cut. Checked with my own measure that the builder's `ProgramHeader`, which is as on `main`, clips identically: the letters of "Gyp" without the focus and with it are 28.0 and 24.7 pt at `.large`, 42.0 and 36.3 at `.accessibility3`, 48.0 and 41.3 at `.accessibility5`, in both fields, to a third of a point. So the cut is the title role's line, not `NameField`'s. Both tests carry a known issue that names ruling 22 and the chore, and are not intermittent: each fails when the clipping stops, so the chore must remove the wrapper. | `focus_doesNotCutTheDescenders`, `focus_programHeader_doesNotCutTheDescenders` (new; it also expects the two fields to clip alike) |
| F11-S10-9 | note, for the design-system chore | **The word sits low in `PillButton`'s outline at accessibility sizes, and it is `PillButton` itself.** "Done" alone, in the bar and "+30s" alone measure the same. Room above the word's ink and under it, inside the outline: 11.7 and 8.0 pt at `.large` (outline 28 pt), **17.3 and 7.6 pt at `.accessibility3`** (45.3 pt), **20.0 and 7.6 pt at `.accessibility5`** (54.3 pt): the word's middle is 1.8, 4.8 and 6.2 pt under the outline's. The room under the word is the pill's padding; the caption role's line puts all its extra height above the letters. Not this slice's bar. | measured, no test |
| F11-S10-10 | note, for the snapshot harness (not this slice) | **The outline 2 pt from the top of `day-closed-dark-accessibility3.png` is the reference's crop.** On the hosted screen, in the bar alone and in `DayEditorParts` drawn by `ProgramDrawing`, the outline is 8.0 pt from the bar's top at `.accessibility3` and `.accessibility5` (16.0 at `.large`): the bar's padding. Drawn through the snapshot library's own path (`.image(layout: .sizeThatFits)`, 1×), the parts are 402 × 1873 and the outline is at 2 pt (3 pt at `.accessibility5`, 16 at `.large`); the bar alone and the bar over a plain block are at 8; the bar over the title block at 7; and **a bar with `.fixedSize` over the page is at 2 all the same**. So the bar is not squeezed (round 2's verdict on S-5 stands): on that path a long page at an accessibility size is drawn about 12 pt higher than the size the image is given, and the image loses 5 to 6 pt at its top (and, I take it, at its bottom: not measured). Every long accessibility reference of the module is cut that way. | measured, no test |

### Nothing else moved

- **The name's own place and the whole-name pictures**: `seedNames_areDrawnWhole` (twelve sizes, both
  widths, plain and bold), `otherNames_areDrawnWhole`, right to left and light, `oneOfTheTwo_isDrawn`,
  `focus_doesNotMoveTheName`, `target_holdsEveryLine`, `focus_longName_isOneLine`,
  `storedName_changes_theDrawnNameFollows`, `emptyDraft_keepsALine`: all pass unedited.
- **The trees and actions** in fifteen states, the 91 strings, the orange audit: pass unedited.
- **The room table**: the same two cells are short (375 × 667 at `.accessibility4` and `.accessibility5`),
  the known issue recorded at exactly those.
- **The bar without the screen's `.fixedSize`** (ruling 23): `bar_isNeverSqueezed` passes on both phones at
  the twelve sizes, also hosted 150 pt high; the outline stands 8.0 pt under the bar's top on the hosted
  screen at `.accessibility3` and `.accessibility5`.

### Mutations, round 3 (4, on the round's two changes; sources put back, `git status` clean)

| | Mutant | Existing tests | Mine |
|---|---|---|---|
| p | no room under the name | references only | `name_standsAboveTheTag` |
| q | `xs` under the name, not `s` | references only | `name_standsAboveTheTag` |
| r | the room above the name, not under it | references only | `name_standsAboveTheTag` |
| t | the bar made to give way (30 pt at most) | references, `parts_layOutSanely`, the S9 sweep, `ProgramScreenTests` | `bar_isNeverSqueezed`, `parts_barIsTheScreensBar`, `states_layOutSoundly` |

The baseline recorded no issue.

### Not verified

- The clipping, and its end, on a device; `ProgramHeader` beyond that one measure.
- Why the snapshot path draws a long page higher than it sizes it (finding 10): I measured the effect, not
  the cause, and not the bottom edge.
- A finger, typing, Increase Contrast: as in round 2.

### Runs (2026-10-11, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `sim-test.sh … -only-testing:FeatureProgramTests`, final sources | **0: 511 tests in 59 suites, all passed, 8 known issues** (the two descender tests at three sizes each; the room table's two cells); 370 s of tests, 391 s with the build |
| `scripts/check.sh --fast` | 0: 1,223 tests, lint clean |
| five probe runs of the name suite; one of the mutation driver (0; 230 cases) | — |

Free disk: 10 GB at the end.

---

## S13 — round 1 (G2 tester, 2026-10-18)

Tested at `98ca8cf` (`feat/F11-s13-stores`). No product file, implementer test, pbxproj, test plan or `.github/`
file changed. Twelve new files in `LedgerKit/Tests/FeatureProgramTests/Adversarial/`: two of support
(`StoreAdversarialSupport`, `StoreAdversarialDoubles`) and ten suites, **44 tests** (the two storms run once per
seed of `LEDGER_PROPERTY_SEED_COUNT`: 400 cases at the default 200). **One test fails on purpose** (F11-S13-1).

**Independence.** The tests were written from the slice's criteria, the rulings, the declarations and their doc
comments (`ProgramEditSession`, `ProgramStore`, `+Sources`, `ProgramRoot`, `StoreProbe.hold(_:afterStoring:)`)
before any function body, implementer test, `Support/ProgramStoreScene.swift`, `Support/ProgramDatabase.swift` or
the notes' "S13 + S14 — as built" was read. The bodies were read afterwards, for the mutations only. Limits: I
read the stored-property declarations (to know the dependency keys and that `heardDuringWrite`, `waiting`,
`routeAfterSave` are readable), and the support reuses round 1's `ProgramActionsAdversarialTests.offered` and
`ProgramFixtures`, which are on `main`.

### Verdict: the save loop holds under every storm I could make; one gap in R6, two tripwires too loose

The loop is right: 200 seeds of held bursts and 200 of forty taps from the screen with writes held and let go at
random and the scheduler free (0–2 yields inside each store call, 0–3 between taps) all store exactly what the
same edits store one at a time, draw it after every tap, and write once per burst. R1, R4, R7, the route after
"+ Add training day" and the failed state's restart all hold. Ten mutants of the session and the store, each
killed (below).

### Findings

| # | Severity | What | Test |
|---|---|---|---|
| F11-S13-1 | **should fix** (small; display only, healed by the next write or emission) | **R6 drops a program newer than the write's own.** A workout saved after the builder's write committed and before `update` returned is emitted during the write; `write` then sets `heardDuringWrite = nil` and adopts the returned program, which is older. The store has nothing more to emit, so the screen (and `session.stored`) stays without the workout's change (misses, an exercise swap) until the next edit or emission. Expected: what the store holds (rename and misses); actual: the rename without the misses. Nothing is lost in the store: the next write reads it. On GRDB the window is the hop from the commit to the return, so it is rare. A fix that keeps R6: after the write, adopt the returned program, then adopt the one heard during it only if it is not the program as it stood before this write's edits (or simply read `active()` once after a write during which something was heard). R6 as written ("the returned program wins") does not cover a newer emission; the orchestrator may rule instead. | `ProgramStoreEmissionsAdversarialTests.workoutSavedAfterTheCommit_beforeTheReturn_isDrawn` — **fails** (`session.stored == stored`, `session.shown == stored`) |
| F11-S13-2 | low (test strength) | **The sanctioned literal exemption is wider than its purpose** (audit below). | `ProgramStoreSourceAdversarialTests.sanctionedExemption_isTooWide_tighterOneHolds` (passes: it pins the hole and the tighter rule) |
| F11-S13-3 | low (test strength) | **`FeatureProgramSourceTests.startsATask` misses `Task(priority: …) {` and `Task.init {`**: it looks for `Task{` with the spaces removed. No product file spells either today. My scan (`startsATask`, a regex over `SwiftSource.code`, every file of the module and its folders) catches all six spellings and lets `addTask`, `Task.yield`, `Task.isCancelled`, `Task.checkCancellation` through. | `ProgramStoreSourceAdversarialTests.implementersTripwire_missesTwoSpellings` (pins the gap), `noTaskOfItsOwn_noTimer_noFormat` (passes) |
| F11-S13-4 | note | **A lost acknowledgement** (stored, then the call throws): `.saveFailed` is shown although the edit is stored; the screen then shows the stored program (the heard emission is adopted on failure), so it reads "not saved" over a program that holds the change. Harmless; S3 says GRDB has no such path. | `ProgramSaveFailuresAdversarialTests.lostAcknowledgement_screenEndsOnWhatIsStored` (passes) |
| F11-S13-5 | note | **The same notice twice is announced once**: "−" tapped again at two weeks leaves the notice unchanged, so VoiceOver hears nothing the second time. As criterion 12 reads ("appears or changes"); for Pete if he wants it said each time. | `ProgramRootAdversarialTests.notice_isAnnounced` (passes; a drop in between announces again) |

### What was attacked, and held

- **Storms** (`ProgramSaveLoopAdversarialTests`, seeded): held bursts of 1–6 edits (renames incl. blank, "+",
  "−" with and without the last week logged, deloads, cells incl. a day the program lacks, copy, apply, new days)
  on blocks of 2–6 weeks, with a follower feeding emissions; each edit is drawn before `enqueue` returns, is
  queued exactly when it changes the screen (R7), the store ends equal to the one-at-a-time fold, and the probe
  counts one `update` per burst that queued an edit. The store storm takes every action the model offers (no
  route, no new day) for forty taps.
- **Pinned**: three edits during a held write go in one second write; "Upper Lowe" typed against a held write is
  two writes; a rename back to the stored name during a write is written (R7 compares with the screen, not the
  store); nine no-op edits write nothing.
- **R1**: cancelled before storing (held before the store) keeps all three edits, shows no failure, and the next
  run adds the week once; cancelled after storing drops them and sends nothing again; `TaskCancelSwitch` fired in
  `prepare` keeps the edit and reports no outcome; a `CancellationError` thrown while the task runs on is a
  failure, sent once (no retry loop).
- **Other failures**: refused with two edits queued behind it drops all three, `update` called once, the line
  reads "That change wasn't saved. Try again.", the next edit clears it and is stored; a throwing `prepare` sends
  nothing.
- **R6**: "−" and a Day editor move stored and emitted before the return are drawn once (7 weeks, not 6; moved
  once); a workout's misses saved while a rename waits before the store are both kept and drawn.
- **Underneath**: "−" while the block is cut elsewhere removes one more (relative, once); cut to two, the write
  shows "A block needs at least 2 weeks." and the stored two weeks.
- **R4**: a workout finished in week 8 while "−", a deload and a rename wait behind a held write: the first write
  is stored, the whole batch is dropped, the notice names week 8; the workouts are read before the write (log).
- **Selection**: today's week (index 4) on first load; a request before the load wins; a day before the block is
  handed raw (negative) and the first chip drawn; one "+" action sent twice adds two weeks and selects the
  second; after "−" on the last week the selection stays raw.
- **Routes**: the day's route waits behind an earlier write and for its own; a double (triple) tap adds one day
  and one route, delivered once; a failed write routes nothing and does not block the next tap; a cancelled write
  routes after the next run, once.
- **Root** (hosted, iOS): empty and failed states from the root's own task; failed, then hosted again, loads (the store suite checks it never passes through loading);
  the day's route reaches `onRoute` after a sentinel route sent while its write
  was held, then once; a failed write hands nothing; four notices announced in order; a requested week wins over
  today's, a redraw with the same request selects nothing, a new number selects it again, a request made while
  the program is read wins.
- **Conventions**: no task of any spelling in the module; no timer, sleep, clock, `Date()`, `.current` or
  `.formatted(` in the S13 files; outside the copy files only `""`, `" · "`, log messages and the category.

### Audit of the implementer's sanctioned edits to the testers' files

| Edit | Verdict |
|---|---|
| `ProgramAdversarialScreen.swift:78`, `case .saveFailed` | Justified: the switch is exhaustive; the English matches the catalog (my `refusedWrite_dropsEveryWaitingEdit` reads the same line from the model). |
| `ProgramAdversarialScreen.swift:28`, a blank line | Justified (file length); no code. |
| `ProgramWordsAdversarialTests.swift:158-162`, log lines not scanned for literals | **Justified in purpose, too wide in form.** It skips *every* literal of *any* line containing `logger.log.` or `.category(`: `notice = "Saved"; logger.log.error("x")`, a labelled argument `logger.log.error("x", label: "Program")`, or any other `.category("…")` call would pass. The lookup half of the test is untouched, so its strength is kept for lookups and for every line that does not log. **Tighter alternative**, built and passing on the current sources: exempt a literal only when `SwiftSource` places it (or the literal holding it) as the first unlabelled argument of a callee ending `logger.log.<level>`, or when it is exactly `"program"` as the argument of `.category` (`ProgramStoreSourceAdversarialTests.isForTheDeveloper` and `literals_onlyInTheCopyFiles_tighterThanTheSanctionedScan`). Recommend round 1's scan adopt that rule (an edit of my file I am content for the implementer to make, listed). Note `SwiftSource` reads a callee across the code with whitespace removed, so the match must be on its end (`.saveFailedlogger.log.error` is what it reports for line 207). |
| `ProgramWordsAdversarialTests.swift:188-189`, 33 → 38 lookups | Justified: `ProgramCopy+States.swift` holds five lookups. |
| `StoreProbe.hold(_:afterStoring:)` (support, not mine) | Sound: the default is the old behaviour; `leave` parks after the store, so a test can hold a call that has stored. Used by six of my tests. |

### Mutations (10, switched in the sources and put back with `git checkout`; `git status` clean after each)

| # | Mutant | Killed by |
|---|---|---|
| 1 | a cancelled write drops its edits | the three R1 cancellation tests |
| 2 | an emission during a write is drawn at once | both R6 tests |
| 3 | a stored write drops every waiting edit | both storms and five pinned tests |
| 4 | R7 judged against the stored program | both storms, `backToTheStoredName_duringAWrite_isWritten` |
| 5 | the logged weeks not read again before "−" | `minusInABatch_weekLoggedSinceTheTap_dropsTheBatch` |
| 6 | the day's route after any stored write | `addDay_behindAnotherWrite_routeOnlyAfterItsOwnWrite` |
| 7 | any `CancellationError` keeps the edits | `cancellationErrorWithoutCancellation_isAFailure_notALoop` |
| 8 | one edit per write | both storms and four pinned tests |
| 9 | a failure keeps the unsent edits | `refusedWrite_dropsEveryWaitingEdit` |
| 10 | a failure ignores the emission heard | `lostAcknowledgement…`, `removeLastWeek_blockCutToTwoUnderneath…` |

### Not verified

- That a failure is logged: the injected logger cannot be read from a test.
- The root's drawn `EmptyState` texts: checked through `store.state`, not the accessibility tree.
- GRDB: every store test runs on the in-memory stores behind the probe; S3's GRDB contract covers `update`.

### Runs (2026-10-18, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `swift test --filter` my nine host suites, 200 seeds | 1, as intended: 37 tests, 1 failed (F11-S13-1), ~10 s |
| `xcodebuild test -testPlan PR -only-testing:` my suites (before the split into files) | 65, as intended: only F11-S13-1 failed; the root suite passed |
| mutation driver, 10 mutants at 40 seeds | each killed |
| `scripts/check.sh` (full gate) at `b8f49bc` | **65, as intended**: format, lint and the script suites clean; the iOS PR plan's only failing test is `ProgramStoreEmissionsAdversarialTests.workoutSavedAfterTheCommit_beforeTheReturn_isDrawn` (F11-S13-1; listed twice by xcodebuild); 955 s of iOS tests, 1,061 s in all. The gate stops there, so the watchOS step and the coverage gate did not run |

---

## S13 — round 2 (G2 tester, 2026-10-18)

Tested at `1b0c07a` (fix `852150b`, notes `1b0c07a`). No product or implementer-test file changed. One new
suite, `Adversarial/ProgramReadAfterWriteAdversarialTests.swift` (5 tests; the storm runs per seed: 200 at the
default count). **Three tests fail on purpose** (F11-S13-6, -7, -8); round 1's F11-S13-1 test passes unedited.

### Verdict: F11-S13-1 is fixed for the case it named; the new read reopens it in a narrower window, and drops a change of program

`newestAfter` reads `active()` after a write that heard an emission, while `isWriting` is still true; then the
synchronous step sets `heardDuringWrite = nil` and adopts the read. Two consequences:

### Findings

| # | Severity | What | Test |
|---|---|---|---|
| F11-S13-6 | **should fix** (small; display only; same class as S13-1) | **An emission heard during the read is dropped.** A workout saved after `active()` has read and before it returns is emitted, kept aside as "heard during the write", then cleared; the read (without the workout's misses) is adopted and nothing else is emitted. Expected: rename and misses on screen; actual: the rename only, until the next edit or emission. Repro is deterministic with `hold(.activeProgram, afterStoring: true)`. Fix: clear `heardDuringWrite` before the read and read again while one was heard during it (it ends: each read is the store's newest when it starts), or adopt the read and then whatever was heard after it began. | `ProgramReadAfterWriteAdversarialTests.emissionDuringTheRead_isDrawn` — **fails** |
| F11-S13-7 | should fix (low today: no M1 path makes another program active while the builder writes; F12/onboarding will) | **Another program made active during the write is not followed.** The read names it; `newestAfter` returns the program just written because the ids differ, and the emission of the new one, heard during the write, is cleared. The builder keeps showing (and editing) a program that is no longer active. Expected: the session adopts the other program (`adopt` already drops edits made on the old one); actual: `stored.id` is the seed's, header "Waiting". | `…readNamesAnotherProgram_isFollowed` — **fails** |
| F11-S13-8 | should fix (low, same reason) | **The active program deleted during the write is still shown.** `try? await programs.active()` is nil, the `guard let` returns the written program, and the heard `nil` is cleared: `.loaded` instead of `.noProgram`. Expected the empty state. Fix for -7 and -8 together: adopt the read whatever it names (nil included); keep the returned program only when the read throws. | `…readNamesNoProgram_isTheEmptyState` — **fails** |
| F11-S13-9 | note | **A read that fails leaves the returned program** and clears what was heard, as the amended R6 says; the next edit heals the screen. Pinned, passes. | `…readFails_keepsTheReturnedProgram` |

**What held.** Round 1's `workoutSavedAfterTheCommit_beforeTheReturn_isDrawn` passes unedited. A storm of 30 taps
per seed from the screen, with writes held at random before or after storing and workouts' misses saved between
taps (0–2 yields inside store calls, 0–3 between taps), ends with the screen equal to the store on all 200 seeds
(`stormWithWorkoutsSaved_endsOnTheStore`): the window of F11-S13-6 is not reached by free scheduling on the
in-memory stores, only by the held read.

### F11-S13-2 and -3 adopted: at full strength

Mutation, switched in `ProgramStore.swift` and put back with `git checkout` (`git status` clean): a log line
preceded by `let s13Mutant = "Saved";` and a `Task(priority: .high) {}` in the logger getter. Round 1's
`sources_holdNoCopyOutsideTheCopyFiles` and my `literals_onlyInTheCopyFiles…` both find `"Saved"` (round 0's
line-wide rule would have skipped it); `FeatureProgramSourceTests.sources_startNoWorkOfTheirOwn` and my
`noTaskOfItsOwn…` both find the task. The implementer's regex is mine verbatim; its self-check lists all six
spellings and the three non-tasks.

### Audit of the two sanctioned edits to my files

| Edit | Verdict |
|---|---|
| `ProgramWordsAdversarialTests.swift:155-162` | **Justified and stronger.** Literals are now read by `SwiftSource` (comments, escapes, multi-line literals handled; line numbers from the literal) and exempt only by `isForTheDeveloper`; the lookup check over every code line is unchanged; the scope (the module's own folder) is as before. Killed the mutant above. |
| `ProgramStoreSourceAdversarialTests.swift:80-81` | **Justified.** The two assertions pinned the gap F11-S13-3 closed; they now require the same spellings to be caught. The function's name (`…missesTwoSpellings`) is stale; harmless. |

### Runs (2026-10-18, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `swift test --filter` the new suite, F11-S13-1's suite, the three source suites | 1, as intended: 24 tests, 3 failed (F11-S13-6, -7, -8) |
| scan mutation (literal on a log line; `Task(priority:)`) | killed by all four scans |
| `scripts/check.sh` (full gate) at `2e4223f` | **65, as intended**: format, lint, script suites clean; the iOS PR plan's only failing tests are the three of F11-S13-6, -7, -8 (xcodebuild lists some twice); round 1's F11-S13-1 test passes; 1,089 s. The gate stops at step 3: watchOS and coverage did not run |

---

## S13 — round 3 (G2 tester, 2026-10-18)

Tested at `c641816` (fix `c29faa5`, notes `c641816`, review `d47afc8` read). No product or implementer-test file
changed. Two new suites: `Adversarial/ProgramReReadAdversarialTests.swift` (4 tests) and, iOS only,
`Adversarial/ProgramRootPhaseAdversarialTests.swift` (3 tests). One edit of my own file:
`ProgramRootAdversarialTests.swift`, the `try` dropped before the seven `Self.hosting` calls whose closure
throws nothing (lines 35, 46, 49, 84, 99, 127, 149; the warning reported at 49). **No test fails.**

### Verdict: F11-S13-6, -7 and -8 are closed; G2 can close

Every round 1 and round 2 suite passes **unedited**: `emissionDuringTheRead_isDrawn`,
`readNamesAnotherProgram_isFollowed`, `readNamesNoProgram_isTheEmptyState` included (host, 46 tests in 11
suites, 200 seeds).

### The new code, attacked

| Attack | Result | Test |
|---|---|---|
| An emission during **every** read (a store that writes while each of twenty reads runs) | The loop ends after the 21st read, the one undisturbed; the screen equals the store; an edit made while it read is written afterwards. It ends only once the store goes quiet: a store that kept writing would keep the write open (and queued edits waiting) for as long as it writes. Each write is a real change, so this needs an unbounded stream of writes; note, not a defect | `emissionDuringEveryRead_endsWhenTheStoreGoesQuiet` |
| A read that **throws on the second turn**, after the first found a newer program | The program `update` returned is kept, as R6 re-amended says ("a read that throws, at any turn, … keeps `saved`"); the screen is without a workout's misses the first read had seen, until the next edit, which heals it. Pinned as ruled (F11-S13-10) | `readThrowsOnTheSecondTurn_keepsTheNewest` |
| **Nil, then a program** (the active program deleted, then another made active during the first read) | Two reads; the builder follows the second program | `nilThenAProgram_followsTheProgram` |
| **Per-run `hasEnded`** (SF1): an observation ends in run 1, not in run 2, again in run 3 | failed → shown → failed; a cancelled run is not a failure | `endedFlag_isPerRun` |
| **Scene phase**: a write held before the store, background → active, released | Not cancelled; one `update`; nine weeks; no notice; the screen ends on the store | `ProgramRootPhaseAdversarialTests.heldBeforeStoring_acrossTheBackground_storedOnce` |
| Same, held after storing (the sources' run restarts and re-hears during the write, so the re-read runs) | Adopted once; nine weeks; one `update` | `…heldAfterStoring_acrossTheBackground_adoptedOnce` |
| Background → active is not the failed state | The builder is shown again, never `.failed` | `…background_isNotAFailure` |
| **`routeAfterSave` (nit 1)**: `newDayWaits` | Holds for every case of round 1 (behind another write, double tap, failed, cancelled: all pass unedited) and for the implementer's dropped-with-another-program case | round 1's route suite |

Mutations (switched, put back with `git checkout`, `git status` clean): the re-read loop made a single read
(`while` → `if`) fails four tests here and round 2's emission-during-the-read test; `hasEnded = false` removed
from `run()` fails `endedFlag_isPerRun`.

### Findings

| # | Severity | What | Test |
|---|---|---|---|
| F11-S13-10 | note (for the orchestrator) | On a read that throws after an earlier read succeeded, keeping the last read (`newest`) instead of `saved` would lose nothing and show more; R6 as ruled keeps `saved`. | `readThrowsOnTheSecondTurn_keepsTheNewest` (pins the ruling) |
| F11-S13-11 | note | The re-read loop runs for as long as the store emits during each read (above). | `emissionDuringEveryRead_endsWhenTheStoreGoesQuiet` |
| F11-S13-12 | note (pre-existing, not from nit 1) | If a route is emitted (a card tap) after "+ Add training day" and before its write returns, the day's route finds `pendingRoute` taken and is dropped with `routeAfterSave`: the day is added, the editor does not open. The root hands a route on within a frame, so the window is that frame. No test. | — |

### Audit of the sanctioned edit to my file

`ProgramStoreSourceAdversarialTests.swift:78`, `implementersTripwire_missesTwoSpellings` →
`…_catchesBothSpellings`: **justified**, the name I called stale in round 2; nothing else changed.

### Runs (2026-10-18, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `swift test --filter` my eleven host suites, 200 seeds | 0: 46 tests (after pinning F11-S13-10 as ruled) |
| two mutants | both killed |
| `scripts/check.sh --lint-only` | 0 |
| `scripts/check.sh` (full gate) at `a8c1035` | **0, "check.sh OK"**, 1,324 s: lint 69 s, iOS tests 977 s, watchOS tests 233 s, coverage 2 s (FeatureProgram 99.18 %); no warning in my files |

---

## S14 — round 1 (G2 tester, 2026-10-19)

Tested at `f666a9a`. No product or implementer file was changed. New files: `Adversarial/DayEditorStoreAdversarialTests.swift`
(host, 8 tests), `Adversarial/ProgramStackAdversarialTests.swift` (iOS hosted, 3 tests) and
`Apps/LedgerUITests/ProgramTabAdversarial.swift` (Nightly UI, 3 tests).

### Verdict: the stores hold; one should-fix in the app wiring (F11-S14-1); criterion 20's gap is real (F11-S14-2)

### Findings

| # | Severity | What | Test |
|---|---|---|---|
| F11-S14-1 | **should fix** (small; display only, nothing is lost) | **A week the app asked for is selected again every time the builder appears again.** `ProgramRoot` applies `week` with `.onChange(of: week, initial: true)`, and SwiftUI runs that initial action on each appearance, not once. So once Today's "Edit this week" has asked for week 5, the lifter picks week 6, opens a day and taps "Done" (or goes to Today and back), and the builder is on week 5 again: their pick is overwritten by an old request. Criterion 9 / R10 say a request selects its week, and a *new* request selects it again; coming back is not a new request. Repro: host `ProgramRoot` in a `NavigationStack` with `week = (1, weekIndex: 1)`, `.selectWeek(5)`, push, pop: `selectedWeek` is 1. The same with a `TabView` switch. One fix: the store remembers the number of the last request it applied and ignores the same request again (`select(request:)`), so neither the appearance nor a new store body matters. | `ProgramStackAdversarialTests.requestedWeek_thenPicked_survivesAPushAndPop`, `…_survivesATabSwitch`: **fail** (`selectedWeek → 1`, expected 5); on screen `ProgramTabAdversarial.test_editThisWeek_thenAnotherWeek_isKeptAfterTheDayEditorAndATabSwitch`: **fails** at both checks (after "Done" and after Today and back, week 6 is no longer selected) |
| F11-S14-2 | **for the orchestrator** (criterion 20 not met; known, the implementer's open question 1) | **No swipe back on the Day editor**, confirmed on its own: from a Day editor just opened (no field ever focused), neither the edge swipe nor iOS 26's swipe from inside the content pops it; the implementer's control (the same gesture pops Today's Settings) passes, so the gesture is fair. "Program" and "Done" work, and nothing is lost. Needs a ruling (implementer's option A, B or C) or a fix; until then my two tests fail in Nightly. | `ProgramTabAdversarial.test_edgeSwipe_onAFreshDayEditor_pops`, `test_contentSwipe_onAFreshDayEditor_pops`: **fail**; `DayEditor.test_swipeBack_control_…` passes; `test_backAndSwipeBack_…`'s strict expected failure is matched |
| F11-S14-3 | note | **Edits kept by R1 die with a popped Day editor.** A tab switch cancels the editor's tasks; a write in flight at that moment keeps its edits for the next run (R1). If Today's "Edit this week" then pops the editor (question 2, A), the store goes, and so do they. The window is that write's milliseconds, as in R5; for the record. | — (needs `AppTabs` hosted with a held write) |
| F11-S14-4 | note | The day deleted elsewhere while the editor's write on it fails: the editor closes (the day is gone) with `showsSaveFailure` set, so the alert is asked for on a screen being popped. Harmless: the edit was on a day that no longer exists. | `DayEditorStoreAdversarialTests.dayDeletedElsewhere_andTheWriteFails_closesWithTheAlertSet` (passes; pins it) |

### What was attacked, and held

| Attack | Result | Test |
|---|---|---|
| Builder and Day editor on one program: the builder's rename held before the store, the editor renames its day and steps a field (its write passes the held one), then release | Both kept; both sessions' `shown` equal the store | `builderAndEditor_interleavedDuringAHeldWrite_bothScreensEndAsStored` |
| "Done" during a write held after storing, an edit behind it, and the second write refused | No close; the alert; the day as stored ("Push", not "Push A"); a second "Done" closes | `done_thenTheSecondWriteFails_dropsTheClose_andShowsWhatIsStored` |
| "Done", then the write's task cancelled (R1) | Nothing failed; the edit stays on screen; the next run stores it, then `.closeDay` | `done_writeCancelled_closesAfterTheNextRunStoresIt` |
| The day deleted elsewhere under the editor's held stepper write | One `.closeDay`, no alert; the write does not bring the day back | `dayDeletedElsewhere_duringTheEditorsHeldWrite_closesOnce_andDoesNotBringItBack` |
| "Delete" behind a held rename | Blank while it waits; two writes; one close | `delete_behindAHeldWrite_closesOnceBothAreStored` |
| Library: two "Add"s while a write is held | The chip is kept; waiting slots already read "already in this day" (question 4); each exercise once, in order, own ids; the adds go in one write | `library_twoAddsWhileAWriteIsHeld_storeEachOnceInOrder` |
| Library: "Add" of only exercises that are gone | No write; the sheet closes | `library_addOfOnlyStrangers_writesNothing` |
| R1 hosted: the builder's write held while a screen is pushed over it | Stored once (nine weeks) | `ProgramStackAdversarialTests.heldWrite_whenAScreenIsPushed_isStoredOnce` |
| A route's week out of range (selection kept raw after "−") | Both the builder's card route and the Day editor clamp it with `nearestPlace` | read in the sources |
| Bounded re-read (5) and the throwing read | The screen can end behind the store: at the bound, and after a read that throws (what was heard is not drawn), until the next emission or edit. As ruled (G3 notes 1 and 2), pinned by the sanctioned tests | `ProgramReReadAdversarialTests` |
| Q5 and clearing a name letter by letter | `cleanedName` trims, so "Upper A" → "Upper " stores "Upper"; a blank stores nothing. Nothing worse than the implementer's case (the first letter stays if the field is left blank). The placeholder's `isWhitespace` and the Domain's blank rule differ only for control characters, which a keyboard does not type | — |
| The removals | No `hasDropSet`, `Field.label`, `detail`, `inDayMark` or `pickMark` left in `Sources` or the UI tests; the tests' `detail`/`label` are test extensions read off the line and the spoken label | grep |

### Audit of the implementer's sanctioned edits to the testers' files

All eleven rows of the notes' table are **justified** and do no more than they say: the re-read tests follow G3 notes 1 and 2
(they still pin that the screen is behind at the bound, and healed); the source scans let through exactly
`NameField.swift: .allSatisfy(` and `draft.isEmpty`; the oracles lose only the removed fields; 91 → 85 strings is the six
labels; `addDay_routeAfterTheWrite_once` now pins F11-S13-12's drop; the shell edits follow criterion 25 and question 2.

### Runs (2026-10-19, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `swift test --filter DayEditorStoreAdversarialTests` | 0: 8 tests |
| `xcodebuild … -testPlan PR -only-testing:FeatureProgramTests/ProgramStackAdversarialTests` | 65, as intended: the two F11-S14-1 tests fail, the R1 test passes |
| `xcodebuild … -testPlan Nightly` UI: `ProgramTabAdversarial` swipes, `DayEditor` swipe and control | the two swipe tests fail (F11-S14-2); the control passes; the strict expected failure is matched |
| `xcodebuild … -testPlan Nightly` UI: `ProgramTabAdversarial.test_editThisWeek_…` (a rest day of week 5, 2026-09-17) | 65, as intended: both of its checks fail (F11-S14-1, in the running app) |
| swiftformat `--lint`, swiftlint `--strict` on my three files | 0 |

---

## S14 — round 2 (G2 tester, 2026-10-19)

Tested at `0b80519` (fix round 1). No product or implementer file was changed. New:
`Adversarial/ProgramWeekRequestAdversarialTests.swift` (iOS hosted, 7 tests).

### Verdict: F11-S14-1 is fixed; no new finding; G2 can close (criterion 20 stays open, as ruled)

Round 1's tests that failed for F11-S14-1 pass **unedited** (both hosted tests, and the on-screen
`test_editThisWeek_thenAnotherWeek_isKeptAfterTheDayEditorAndATabSwitch` in the running app).

### The fix, attacked

| Attack | Result | Test |
|---|---|---|
| The same week asked for again, with a new number | Selected again; the lifter's next pick then survives a push and pop | `sameWeek_newNumber_selectsAgain_thenIsKept` |
| Question 2: a request that pops a pushed screen (stack emptied and a new request in one go, as `editProgramWeek` does) | Its week is selected; a later pick survives the next pop | `requestWhilePushed_popsAndSelects` |
| A request handed in before the store has loaded | It wins over the week that holds today, and is not applied again after a pop | `requestBeforeLoad_winsOverToday` |
| The root hosted again over the same store (a new run of its tasks) | The pick is kept | `hostedAgain_keepsThePick` |
| The active program deleted (empty state), then made active again | The old request is not applied again | `programGoneAndBack_doesNotReapply` |
| A week past the block (20 of 8) | Kept raw, drawn as the last week ("WEEK 8 · DELOAD"); the next pick holds | `requestOutOfRange_drawsTheLastWeek` |
| Two requests in one go | The second's week; neither comes back after a pop | `twoRequestsAtOnce_theSecondWins` |
| The extension move | `select(week:)` and `deliverRoute(to:)` have the same bodies and access; every store and root suite passes | `ProgramStoreTests` (host), the hosted suites |

### Round 1's candidate note: can the Program tab's root be rebuilt while the router survives? No, on this branch

- The router is `MainRoot`'s `@State`. `AppTabs` and `ProgramRoot` sit under it with no `.id` and no branch between them.
- The only branch above is `AppRoot`'s switch on `composition.state` (`DatabaseLaunch.state`). It is set only when the database opens (`.ready` or `.databaseUnavailable`) and never goes back, so the router and the tabs live and go together.
- The scene phase only re-keys `.task(id:)`s; it never changes the views' structure.
- A tab switch keeps the tab's state: the on-screen week test passes in the real `AppTabs`, and a rebuilt root would have applied the old request again.
- F08's onboarding branch will make a new `AppRouter()` (the orchestrator says so), so its request goes with it.

Not a finding. No test beyond the on-screen one: a hosted test cannot reach the store that `AppTabs` builds.

### Audit of the sanctioned edit to my file

`Apps/LedgerUITests/ProgramTabAdversarial.swift`: **justified**. In `test_edgeSwipe_…` and `test_contentSwipe_…` only the
pop's assertion is wrapped, in a strict `XCTExpectFailure` citing F11-S14-2. The gestures, the launch and the screenshot
are unchanged, and the mark fails the day the swipe pops (the ruling: criterion 20 goes to a follow-up).

### Runs (2026-10-19, in the worktree; every simulator command through the lock; iPhone 17, iOS 27.0)

| Command | Exit |
|---|---|
| `swift test --filter 'DayEditorStoreAdversarialTests\|ProgramStoreTests'` | 0: 37 tests |
| `xcodebuild … -testPlan PR -only-testing:` `ProgramStackAdversarialTests`, `ProgramWeekRequestAdversarialTests` | 65: 9 of 10 passed. The tenth, `requestOutOfRange_…`, failed on my oracle (it expected "WEEK 8"; the seed's week 8 is a deload, "WEEK 8 · DELOAD"); its other check passed. Fixed afterwards to `hasPrefix("WEEK 8")`; not re-run on the simulator |
| `xcodebuild … -testPlan Nightly -only-testing:LedgerUITests/ProgramTabAdversarial` | 0: 3 passed, the two swipe tests as matched strict expected failures |
| swiftformat `--lint`, swiftlint `--strict` on the new file | 0 |

The result bundles were deleted after each run.

## S14 — follow-ups found by F08 S2/S3 (F08 implementer, 2026-10-20)

Found by F08 S2/S3's seed program (`-LEDGER_UITEST_PROGRAM seed`), 2026-10-20, after merging `main` with S14 into
`feat/F08-s2-onboarding`; owner: F11 follow-up. Until a UI test's database had a program, the Program tab showed
"No program yet"; now it shows the builder over the seed program, at week 5 under `-LEDGER_UITEST_NOW
2026-09-16T12:00:00Z`.

1. **F11-S14-5 — the builder over a program fails the system's accessibility audit (26 issues).** Orchestrator's
   ruling: nothing is excluded; a follow-up slice measures and decides each, and the nightly stays red on this
   one test until it lands.
   - *Test:* `Apps/LedgerUITests/TabsAdversarial.swift`,
     `test_everyTabRoot_passesTheSystemsAccessibilityAudit` (`:170`), Nightly plan, iPhone 17, iOS 27.0, on the
     Program tab. Today, Library and History raise nothing new.
   - *Contrast failed (5):* "4 exercises · 15 sets · ~38 min", "SQUAT", "RDL", "LEG PRESS", "CALF".
   - *Dynamic Type font sizes are partially unsupported (17):* "INCLINE", "BLOCK · 8 WEEKS", "4 DAYS" (×8), "+1",
     "WEEK 5", "CS ROW", "PULLDOWN", "BENCH", "TRAINING DAYS", "DELOAD", "MY PROGRAM".
   - *Text clipped (4):* "4 days · 58 sets a week", "Apply to later weeks" (a button), "TRAINING DAYS",
     "BLOCK · 8 WEEKS".
   - All elements are type 48 (static text) except "Apply to later weeks" (9, button). Measured once, on the
     first nightly run after the merge.
2. **F11-S14-6 — flaky: `Builder.test_wrappedName_takesTheFocus_andABlankDraftShowsThePlaceholder` (`:80`), seen
   once.** "XCTAssertEqual failed: ("Optional("A l")") is not equal to ("Optional("A")") - a blank name is not
   stored": the name cleared letter by letter stored "A l" as its last value before the field went blank, instead
   of "A". The re-run of `Builder` (with `Tabs`) passed 7 of 7. Likely the save loop's timing at
   `AccessibilityXL`; not reproduced.
