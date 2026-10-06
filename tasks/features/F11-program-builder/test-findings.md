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
