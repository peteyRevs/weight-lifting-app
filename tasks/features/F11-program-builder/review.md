# F11 — review

## Slice S1 — review (G3 reviewer, 2026-10-05)

Reviewed: `git diff fee3c70..9660227` on `feat/F11-s1-program-editing`, the committed slice only. Paths are
from the worktree root; `Programs/…` product files are under `LedgerKit/Sources/LedgerDomain/`, test files
under `LedgerKit/Tests/LedgerDomainTests/`. Line numbers are those of `9660227`. "The notes" is
`tasks/features/F11-program-builder/implementation-notes.md`.

### Verdict

**Approved: 0 Blocking, 3 Should fix, 9 Nits.**

The code does what the thirteen criteria ask. I found no trap, no result the model refuses, and no write of a
slot's misses or exercise. The three Should-fix items are one behaviour the criteria leave open
(re-selecting "Double"), one guard the criterion-12 property lacks, and one sentence of the notes that is
wrong and that S13 would build on. None of them stops the merge; S-1 needs a one-line ruling first.

### Should fix

**S-1. Selecting "Double" on a slot that is already double widens a range the lifter narrowed.**
`Programs/DayEditing.swift:99-106` (the `max` at `:103`).
- What happens: a double slot at 8–10. The lifter steps "TOP OF RANGE" down to 9, which `set` allows
  (`Programs/DayEditing+Fields.swift:48`). A tap on the "Double" chip, which is already selected, calls
  `setProgression(.double, …)` and the top goes back to 10. The same after raising "REP FLOOR" to 9 (9–10
  becomes 9–11). The weekly strip changes although the lifter changed nothing.
- Why it matters: a store adds no rule, so it sends the tap as it is; and the call is not a no-op, so S3
  writes a row. The prototype widens only when the top is not above reps
  (`design/prototype/Ledger.dc.html:1114-1118`), so a second tap there changes nothing. Slice criterion 8
  ("choosing double progression makes the top at least reps + 2") is met as written; it does not say what
  a second choice does, and no test covers it.
- I am not sure this is unintended: it follows the brief's formula literally. What settles it is the
  orchestrator's reading of "choosing".
- Fix, if the reading is "changing to Double": make the function a no-op when the slot already has that
  progression, as its first line inside the closure:
  `guard slots[index].progression != progression else { return }`. Add
  `setProgression_doubleAgain_keepsANarrowedRange` (double, reps 8, top 9 → still 9) to
  `Programs/DayEditingTests.swift`. Linear → Double keeps today's behaviour (9 → 10).

**S-2. The criterion-12 property covers the functions someone remembered to list.**
`Programs/EditingTestSupport+Edits.swift:47` (`dayEdits`) and `:102` (`programEdits`), read by
`Programs/DayEditingPropertyTests.swift:173-193` and `:195-216`.
- What is wrong: the two tables are written by hand. Today they are complete: I checked them against every
  `static func` of the five files (eleven of `ProgramEditing` that return a program, seven of `DayEditing`
  that return a day). A function added later is tested only if its author adds a row. Nothing fails if they
  forget.
- Why it matters: S3's argument that a builder edit and a workout's save commute rests on this property and
  on nothing else. The likeliest future break is a new function, or a refactor that rebuilds a slot through
  `Slot.init` and leaves out `misses:`, which has a default.
- Fix: one source-scan test in the form of `ModuleBoundaryTests.sources_importFoundationOnly`
  (`ModuleBoundaryTests.swift:40`), over `Sources/LedgerDomain/Programs/*.swift`: every `static func`
  whose result is `Program` or `DayTemplate` is named in one of the two tables; and no line assigns
  `.misses` or `.exerciseID` or calls `Slot(` outside `newSlot`. About 25 lines.

**S-3. The notes tell S13 that every edit is absolute. Four functions are not.**
`tasks/features/F11-program-builder/implementation-notes.md:1247-1249`: "Every function takes ids and
absolute values, never a position or a difference".
- What is wrong: `toggleDeload` flips (`Programs/ProgramEditing.swift:69-71`); `cycleSchedule` goes to the
  next value (`:77-84`); `move` is relative (`Programs/DayEditing+Move.swift:19`); `removeLastWeek` names
  "the last" (`Programs/ProgramEditing.swift:52`); every `week:` is a place, not a `WeekID`. Only the
  steppers were made absolute (`stepped` once, then `set`).
- Why it matters: applied once to the screen and once to the stored program, these agree. Applied twice to
  the stored program they do not: a deload toggled twice is off, a cell cycled twice skips a day. That is
  what happens if S13 ever sends a batch again after a write whose outcome it could not see (the cancelled
  write of orchestrator ruling 5).
- Fix: correct the sentence, and bind S13 in its specification: each queued edit reaches the stored program
  exactly once; after any failed or cancelled `update`, the waiting edits are dropped and the screen is
  redrawn from the stored program, never sent again. No code change in this slice. (Absolute forms,
  `setDeload(_:week:)` and a `setSchedule` beside a pure "next in the cycle", would remove the condition for
  those two; `move` has no small absolute form, so the condition stays either way.)
- The same section's table says of misses written for a removed week that "nothing reads them"
  (notes `:347`). That holds only until "+" adds a week at that index again; then the next week shows
  " · HELD". Worth one sentence there.

### Nits

- **N-1. `ExerciseSearch.filter(…).isEmpty` fails the lint** (`Rules/ExerciseSearch.swift:74`). Confirmed
  with the project's SwiftLint 0.65.1 and configuration: `contains_over_filter_is_empty`, an error under
  `--strict`; a function named `filtered` does not trip it. Rename to `filtered(_:query:muscle:equipment:)`
  now, beside `sorted(_:)`: one declaration, four call sites in `Rules/ExerciseSearchTests.swift`, and the
  notes' mentions. S8, S14 and F12 are then spared the false positive.
- **N-2. `set`'s comment promises rounding the start load does not get**
  (`Programs/DayEditing+Fields.swift:9`: "A value off the field's step goes to the nearest step"). A start
  load is floored at zero and stored as given, which `setStartLoad_isStoredExactly` pins. Say "RPE and rest
  go to the nearest step; a start load is stored as given".
- **N-3. `cleanedName`'s comment says "the line breaks"** (`Programs/ProgramEditing.swift:16-18`). U+2028
  and U+2029 are not `Cc`: they are trimmed at the ends and kept inside a name (probed on the host). Either
  say "LF, CR and NEL", or remove `Zl` and `Zp` as well, which no one-line name needs.
- **N-4. Three limits are written twice.** RPE's 5…10 at `Units/RPE.swift:13` (as 10 and 20 half points)
  and `:29`; rest's 30…300 by 15 at `Units/RestDuration.swift:11` and `:27-28`; the two-week minimum at
  `Model/Program.swift:47` and `Programs/ProgramEditing.swift:57`. The tests pin each pair equal. Name them
  once, as the slice did for `Slot`'s ranges.
- **N-5. `prescriptions` does not say what it inherits** (`Rules/ProgressionRules.swift:63-64`). Add: "the
  weeks are a program's (indices 0 … n − 1) and the slot is one `Slot.init` accepts, as for `prescribe`".
- **N-6. Seeded tests that assert inside nested loops** (`Programs/DayEditingPropertyTests.swift:186-191`,
  `:203-213`). Each value compared is small, but a broad regression records up to steps × slots failures
  per seed, and "since the start" repeats the same fact on every later step. Collect the mismatches and
  expect the list empty once per seed, or stop at the first with `try #require`.
- **N-7. Three names.** `clampingInitializers_roundToTheStepAndStayInRange` tests RPE alone
  (`Units/RepsRPERestTests.swift:102`). `everyDayEdit_onEverySlot_leavesMissesAndExercise` draws a random
  slot as many times as there are slots, not each slot (`Programs/DayEditingPropertyTests.swift:199-204`).
  `Programs/EditingTestSupport.swift` declares `EditingSupport`.
- **N-8. The start load and step a slot resolves to have no accessor.** The pair
  `slot.startLoad ?? exercise.startLoad(in:)` and `slot.step ?? exercise.equipment.defaultStep(in:)` is now
  written at `Rules/ProgressionRules.swift:29-30` and `Programs/DayEditing+Fields.swift:69-70`. S6 and S7
  need both for the "START LOAD" value, the row's load and the progression note, and would write it a third
  time, in a presentation. Two small public functions on `Slot`, used in both places, when S7 starts.
- **N-9. Two comments say less than the code does.** `addSlots` keeps an appended slot's own superset flag,
  so a slot arriving with it set joins the day's last slot (`Programs/DayEditing.swift:75-76`; pinned by
  `addSlots_toAnEmptyDay_firstSlotIsNeverJoined`). "No function here writes a slot"
  (`Programs/ProgramEditing.swift:11`) leaves out `updateDay`, which stores whatever its closure returns.

### The bug pass (`/code-review`, effort high)

Run through the Skill tool on the same range; it returned nine candidates from reading alone, with nothing
run. What I made of each (its second candidate is two rows here):

| Candidate | Result |
|---|---|
| `setProgression(.double)` widens again | Confirmed by reading; S-1. |
| `cleanedName`: U+200B kept | **Wrong.** A probe on the host gives `nil` for a name of U+200B alone. |
| `cleanedName`: control characters deleted, not replaced; U+2028 kept inside | True and as specified ("A⇥B" → "AB", decision 13). N-3 for the comment. |
| `removeLastWeek` leaves the week's index in `misses` | By design: criterion 12 forbids writing misses. The consequence is under S-3. |
| A zero or negative `slot.step` | Outside the model; no trap; decision 10 documents it. No finding. |
| `set`'s comment and the start load | N-2. |
| `addSlots` keeps the incoming flag | Intended and tested; N-9 for the comment. |
| Ranges kept in two places (`Slot.init` and `DayEditing`) | The plan's decision ("Brief vs main" row 11); guarded by the rebuild property and by the repository. See "Validity". |
| `filter` folds names twice and sorts again | No budget risk: a replica of `key`, `matches` and `sorted` over the 224 catalog names takes 0.25 ms optimised and 1.1 ms unoptimised on the host, against 10 ms. No finding. |
| `move` rewrites every flag | Correct for a day in normal form; no finding. |

### Verdict on each point

**Every rule against the code.**

| Rule | Where | Complete here | Written twice or differently |
|---|---|---|---|
| 1 step per equipment and unit | `Equipment.defaultStep(in:)` (F02), read at `DayEditing+Fields.swift:70` | Yes; the store passes `exercise` and `units` | The fallback pair is the same expression as `ProgressionRules.swift:29-30` (N-8) |
| 2 reps 1–30, top 2–40, top above reps | `DayEditing+Fields.swift:44-48` | Yes | No: `Slot.repsRange` and `repsHiRange` serve both `Slot.init` and `set` |
| 3 sets 1–12, RPE 5–10 by 0.5, rest 30–300 by 15, default rest | `:43`, `:50`, `:52`; `newSlot(defaultRest:)` | Yes | Sets: no. RPE and rest: twice inside their own files (N-4) |
| 4 at least two weeks, no maximum, a new week copies the last and is no deload | `ProgramEditing.swift:39-66` | Yes; selecting the new week is the store's | The literal 2 is also in `Program.init` (N-4) |
| 5 rest → each day → rest | `ProgramEditing.swift:77-84` | Yes | No |
| 6 start load ± step, never below zero | `DayEditing+Fields.swift:54`, `:63-75` | Yes | The floor is in `stepped` and in `set`, as criterion 7 asks; `Slot.init` refuses the same values |
| 7 a new exercise's defaults | `DayEditing.swift:56-73` | Yes; the store must handle the throw (question 4) | No |
| 8 "D{n}", no slots | `ProgramEditing+Days.swift:9-16`, `:64-71` | Yes; the name is the feature's | No |
| §7.2 | `ProgressionRules.swift:65-72` maps `prescribe` | Yes | Nothing re-implemented |
| 44 superset groups and letters | `DayEditing.swift:126-129` on `SupersetRounds.groups` | Yes | One grouping for the editor, the estimate and the workout |

A store has nothing to add, with one exception that is S-1.

**Totality.** Every function of the two namespaces is total for every value the types allow, by reading
each index, sum and subscript. Places are found by `firstIndex` or guarded by `indices.contains`; sums are on
clamped or guarded values or go through `saturatingSum`; `Decimal` arithmetic does not trap (an overflow is a
NaN, probed); a NaN becomes 5 or zero through `Decimal`'s ordering (probed on the host, and pinned by rows
the gate ran on both simulators); a zero step moves nothing; `freeTag` loops at most once per day. One oddity
without a trap: `Program.init` accepts two days with one id, and `cycleSchedule` then never leaves the first
of them; `addDay` cannot produce it.
- *Decision 8 (saturating sums):* accept. It costs seven lines, is covered, and never engages on a slot the
  model accepts. It does not repair such a slot, and the next call on it, `prescriptions`, may still trap;
  both are unreachable from storage and from these functions.
- *Open question 3:* acceptable, and not to be hardened in this slice. Every program a view model holds was
  read through `Program.init` and `Slot.init` or came out of these functions, so its weeks are 0 … n − 1 and
  its slots are in range. The cost is n² set lookups per slot for n weeks, nothing at 52. Criterion 1's
  "never traps" names the two editing namespaces, not `ProgressionRules`. N-5 asks for the sentence.

**Validity.** Given a program and slots the model accepts, every result is one it accepts. I checked each
assignment against each check of `Slot.init` (sets, reps, top, top above reps, RPE, rest, drop sets, start
load, step) and of `Program.init` (two weeks, indices, schedules naming a day): none is missed. `step` is
never written. Three ways in from outside stay open by design and are not validated: the slots handed to
`addSlots`, the day returned by `updateDay`'s closure, and a slot id that another day of the program already
holds (`addSlots` checks the day only). Assigning fields rather than rebuilding is sound here because
`EditingSupport.faults(in:)` rebuilds every result through both initializers after every random edit.

**The move, and the normal form.** `move` is the definition, line for line, and gives criterion 10's three
examples. The property test checks all six properties, and its fifth (the day's edges) is what catches a
reversed direction. Every `DayEditing` function returns a day in normal form; `ProgramEditing.renameDay` and
`updateDay` pass a day through as they find it, which is right. *Decision 6:* accept. Every reader ignores
the first slot's flag, so the normal form is the same day. For S3 it means: the first `DayEditing` call on a
stored day whose first slot is joined, even one with an unknown id, returns an unequal day and writes that
one slot's row once.

**Clamp then couple; steps; decimals.** Clamp first, then couple, in both directions
(`DayEditing+Fields.swift:45-48`); the coupled top cannot leave 2…40 because reps is at most 30. `stepped`
does not clamp, except the start load's floor at zero, which criterion 7 asks for. The start load's stepping
is right in both units, on and off the steps, for kettlebells and for an exercise with one unit (rows of
`DayEditingStartLoadTests`). No `Double` and no float literal is in the product diff (searched); exact
multiples divide exactly (probed up to 123,456 steps of 5 lb).

**Criterion 12.** True by reading every function: none assigns `misses` or `exerciseID`, none builds a slot
except `newSlot`, and `addSlots` leaves out an id the day holds instead of replacing its slot (pinned with a
different exercise by `addSlots_idTheDayHolds_isLeftOut`). The property is strong for the functions that
exist: seeded slots carry misses, all eighteen functions are drawn, and each step is compared with the step
before and with the start. It is not strong against a function added later: S-2.

**The API as later slices will use it.**
- *`upward` and `downward`:* keep. A lint exclusion for `up` would allow that name everywhere, for two enum
  cases that read well as they are. Two direction types rather than one is right: "upward" is a larger value
  for a stepper and an earlier place for a move.
- *A main-actor store:* yes. `LedgerDomain` is built with `defaultIsolation(nil)` and `FeatureProgram` with
  `MainActor`. A scratch package of that shape, with stand-in types of the same signatures, compiles clean
  in Swift 6 mode: synchronous intents that build `@Sendable (Program) throws -> Program` closures, the
  nested `updateDay { … }`, the typed throw of `removeLastWeek`, a queue of such closures folded inside
  `update`. Everything an edit captures is `Sendable`.
- *Public and internal:* as they should be. `RPE.step` and `RestDuration.stepSeconds` are internal; F14's
  default-rest stepper will want the second, or a stepping function, when it is built.
- *`nonisolated` and `Sendable`:* as the neighbours. The value types are `Hashable, Sendable`; the two
  namespaces are caseless enums like `ProgressionRules`.
- *Two wrinkles to tell the presentations, not to change:* "Superset with next" passes the next slot's id;
  `stepped` wants an `Exercise` for every field, though only the start load reads it.

**Names.** `cleanedName` does what criterion 2 says: `Cc` removed, then trimmed, `nil` when nothing is left.
Trimming includes U+200B and the wide and non-breaking blanks. Open question 6 is under the rulings.

**Unchanged behaviour.** The edits to `Slot`, `RPE`, `RestDuration`, `ProgressionRules` and `ExerciseSearch`
are additive; `Slot.validate` uses the three constants with the same bounds. The diff of existing test files
has no removed line. The three files touched, each by an appended extension:
`Rules/ExerciseSearchTests.swift` (+76: a fixture helper and four tests of `filter` and `MuscleFilter`),
`Support/Fixtures+Program.swift` (+26: `fourDayIDs`, `fourDayProgram()`),
`Units/RepsRPERestTests.swift` (+41: two tests of the clamping initializers).

**Tests.**
- Behaviour, not implementation, with two small exceptions that pin internal constants
  (`RPE.step == 0.5`, `RestDuration.stepSeconds == 15`); harmless.
- Each of the thirteen criteria has tests; I checked the notes' table against the files.
- Seeds: `PropertySeed.all`, every message carries the seed, and no dictionary or set order feeds a
  generator, so a failing seed reproduces.
- **No program, day, or array of slots or weeks is compared inside `#expect`.** The largest values compared
  directly are a week's schedule, at most seven pairs (`Programs/ProgramEditingScheduleTests.swift:77`, and
  seeded at `Programs/ProgramEditingPropertyTests.swift:56`); one `Prescription` against another
  (`Rules/ProgressionRulesPrescriptionsTests.swift:58`); and nested slot ids, at most eight
  (`Programs/DayEditingPropertyTests.swift:55`, `:64`). None is large. What is left of the disk risk is the
  number of failures, N-6.
- Names follow testing-strategy §6, with N-7. More than one suite per source type is forced by the lint's
  limits and has a precedent (`WorkoutEngineLawsTests`).
- Coverage: the five new files and the five edited ones are at 100 % of lines (84, 60, 95, 51, 40; 66, 40,
  46, 42, 53) in the iOS bundle `.derivedData/Results/PR-iOS.xcresult`, and the five new files again in
  `PR-watchOS.xcresult`. They were written at 20:22 and 20:26, just before the commit (20:26) and before the
  tester's first file (20:35); I take them to be the gate's run on the committed tree.

**Brief, boundaries, size, lint.** Foundation is the only import. No lint or format suppression, no force
unwrap, no `try?` in product code. 367 product lines, under the 500 target. Nothing the plan asked for is
missing: every function of "The editing functions, as proposed" exists with its signature, bar the two
renamed cases; the shortfall against 570 is the estimate.

### Rulings recommended on the seven open questions

1. **`upward`, `downward`.** Keep. No lint change.
2. **An unknown id on a day not in normal form.** Accept. Amend criterion 1's sentence to "returns the day
   unchanged, read as its normal form". S3's clause "a change that returns the program unchanged writes no
   row" should build its fixture in normal form.
3. **`prescribe`'s traps.** Leave `prescribe` alone; `prescriptions` is acceptable as it is. One sentence of
   documentation (N-5). If F02's function is ever hardened, as a change of its own.
4. **`newSlot` throws on a start load below zero.** Keep, as criterion 1 specifies. F12's form refuses such
   a load; S14 builds the slots before it queues the edit. Know the asymmetry: `stepped` and `set` floor the
   same load at zero. If S14's "left out and logged" branch turns out to need a rule of its own, floor in
   `newSlot` instead and let only `removeLastWeek` throw.
5. **`filter(…).isEmpty` and the lint.** Rename to `filtered` now (N-1).
6. **An invisible name.** Accept for M1. A name of only U+FEFF, U+200D, U+2060, U+00AD, a bidi mark or a
   blank letter such as U+3164 is kept (probed). Do not remove category `Cf`: it would break emoji joined
   with U+200D and Persian text. Add two rows to `NameRow.all` so that the behaviour is pinned as chosen.
7. **Pete's decision 2.** Nothing to rule. The claim holds: `move` is alone in
   `Programs/DayEditing+Move.swift`, and `MoveDirection` is used by nothing else.

### The seven review points

1. **Module boundaries:** pass. Foundation only, in all five new files.
2. **Concurrency:** pass. Pure static functions, `Sendable` values, new ids as parameters, no clock.
3. **Error handling:** pass. Two typed throws, nothing swallowed.
4. **Design fidelity:** not applicable; no view.
5. **Accessibility:** not applicable; no view.
6. **Test quality:** pass, with S-2, N-6 and N-7. No sleep, no clock, no order dependence.
7. **Brief compliance:** pass. Each of the thirteen criteria has tests; decision 6 departs from the letter
   of criterion 1 and is flagged by the implementer.

### What S3 and the presentations must be told

S3 and S13:
- Each queued edit reaches the stored program exactly once (S-3). `toggleDeload`, `cycleSchedule`, `move`
  and `removeLastWeek` are not idempotent; `addWeek`, `addDay`, `deleteDay`, `addSlots`, `removeSlot`,
  `set`, `setProgression`, `setDropSet`, `setSuperset`, the renames, `copyPreviousWeek` and
  `applyToLaterWeeks` are.
- `removeLastWeek` throws inside a batch. If S13 folds several edits into one `update`, one throw loses the
  batch; the store has already tried it on the screen's program, so inside the batch a refusal should leave
  the program as it is.
- Criterion 12 is a property of the functions, not of the types. `updateDay` stores whatever its closure
  returns: only `DayEditing` functions go in it.
- A new slot's id must be new in the program, not only in its day.
- A stored day whose first slot is joined is rewritten once by its first day edit (question 2).
- A slot's misses may name a week the block no longer has, and are read again if a week is added at that
  index.

Presentations and the stores of S13 and S14:
- A name field keeps its own draft. `renameDay` and `renameProgram` store the cleaned name; a field redrawn
  from the stored name would eat the space the lifter has just typed.
- "Superset with next" sends the id of the slot after the one tapped; "Break out" sends the slot's own.
- `stepped` needs the slot's `Exercise` for every field. A slot whose exercise is missing ("Behaviour the
  brief leaves open", 19) has none: decide there whether its steppers are shown.
- The start load and the step shown for a slot are the resolved ones (N-8), not `slot.startLoad`.
- `prescriptions` takes `program.weeks`, never weeks built by hand.
- Until N-1 lands, bind `ExerciseSearch.filter(…)` to a constant before asking `isEmpty`.
- Until S-1 is ruled, a tap on the selected "Double" chip changes the range.

### What I did not check

- **No test ran for this review.** Two host runs of the slice's thirteen suites at 2,000 seeds, at 20:41 and
  20:46, stopped at the build. Both errors were in the tester's files in progress, none in the commit:
  `Adversarial/Programs/ProgramEditingDaysAdversarialTests.swift:118` ("call can throw, but it is not marked
  with 'try'") and, the second time, also `DayEditingExamplesAdversarialTests.swift:212` ("ambiguous use of
  operator '=='"). I did not open either file. The committed slice's green is the orchestrator's gate on
  `9660227`; the implementer's 2,000-seed run and its forty-one mutations are unverified by me. I could not
  mutate code.
- Coverage is read from the two result bundles in the worktree, lines only. I did not measure it again or
  check regions, and I infer from their times, not from a record, that they are the gate's run on the
  committed tree.
- The probes ran on the host alone: trimming and `Decimal`'s NaN ordering against Foundation directly, the
  lint against a stand-in file, the isolation check and the filter's timing against stand-ins, not against
  `LedgerDomain`. For iOS and watchOS I rely on the gate having run the tests that pin the first two.
- Whether Swift Testing on this toolchain records the arguments of a helper called inside `#expect`, which
  decides how large a red run of `difference(a, b).isEmpty` is. The implementer reports 7.8 MB for a run
  with twenty bugs.
- The tester's files, by instruction. The persistence code behind the plan's statements about `save`. The
  prototype beyond lines 1099–1123. No simulator, no full gate, no CI.


## Slice S3 — review (G3 reviewer, 2026-10-06)

Reviewed: `git diff 312728c..57d12ab` (one commit, 26 files, +2141 −12; 38 product lines). Paths are under
`LedgerKit/` unless they start with `tasks/` or `docs/`. The tester's untracked files were not read.

### Verdict

**Approved: 0 Blocking, 2 Should fix, 9 Nit.**

The requirement is atomic on both stores by construction, the checks and row rules are `save`'s own, the
cancellation rule S13 relies on ("all or none, `CancellationError` only for none") is established by sound
tests, and no existing test was weakened. The two Should-fix items are a line each and neither changes the
protocol.

### Should fix

**S1. The fake stores a change the database rolls back, when the task is cancelled inside `change`.**
`Sources/LedgerFakes/InMemoryProgramRepository.swift:67-78`. The one cancellation check is before the lock
(`:67`). A task cancelled while `change` runs stores the change and returns; `GRDBProgramRepository.update`
throws `CancellationError` and stores nothing at that same point
(`ProgramUpdateCancellationTests.cancelledInsideItsChange_storesNothing`). Both keep "all or none", but they
are not the same behaviour, which is what ADR-008 decision 5 asks for, and the contract clause has to accept
either answer to pass on both (`Sources/LedgerTestSupport/Persistence/ProgramRepositoryContract+UpdateEffects.swift:103-126`,
the `.success` arm at `:115`). Why it matters: S13's store tests run on the fake, so the path "cancelled
mid-write, nothing stored, keep the waiting edits and send them again" can only be reached there through the
held probe, never from inside the write.
*Fix:* add `try Task.checkCancellation()` after `let changed = try change(stored.program)` (`:72`) and before
`Self.store`. It is synchronous, so it is legal under the lock, and `ObservedState.write` already leaves the
state as it was on a throw. Then make `updateCancelledInside` strict: `CancellationError`, and `active()` is
the program as saved. Update the doc comment at `:63-65`. (The database's "cancelled once committed" case has
no counterpart in the fake, which has no commit; that is fine and should be said in the comment.)

**S2. `save`'s own documentation does not say what this slice found.**
`Sources/LedgerDomain/Protocols/Repositories.swift:25-32`. The hazard is described only on `update`
(`:36-40`). The next caller who wants to edit a stored program reads `save`, which still reads as the way to
do it; the loss is silent and both stores reproduce it
(`wholeSave_afterAWorkoutsSave_losesItsMissAndItsSwap`). *Fix:* one sentence on `save`: "For a new program,
or to replace one whole (an import, a repair). To edit a program that is already stored use `update`: a
copy read earlier and saved here writes back the misses and exercises a workout's save stored since."

### Nit

- **N1. `update` can change which program is active when two are flagged active.**
  `Sources/LedgerPersistence/Repositories/GRDBProgramRepository.swift:81`, `:140-145`. `write` runs `activate`
  whenever the result is active, also when the stored program already was. `fetchActive` (`:127-136`) allows
  for two active programs after a sync; renaming the one that is not the winner then clears the other's
  flag, against the protocol's "a change that leaves it alone leaves which program is active alone"
  (`Repositories.swift:38-39`). No code path produces that state today (F17 would), and `save` does the same,
  so it is not this slice's defect. *Fix, here or with F17:* in `update`, activate only when
  `changed.isActive && !stored.isActive`; an unchanged flag then runs no activation statement at all.
- **N2. The clock is read before the wait for the writer.** `GRDBProgramRepository.swift:72`. A row written by
  an update that queued behind a workout's save gets an `updated_at` earlier than the row it replaces. This
  is the convention of every write in the module (`save` `:45`, `GRDBWorkoutRepository.swift:74`, `:119`,
  `:149`), so it should not be changed in one method; flag it for F17, where `updated_at` starts to order
  things. Note that `cancelledWhileItWaitsForTheWriter_storesNothing` uses the early read as its signal.
- **N3. The unreachable `?? changed`.** `GRDBProgramRepository.swift:82`, `InMemoryProgramRepository.swift:77`.
  If it ever ran, the caller would be handed the change's result (weeks unsorted, not read from the store) as
  "the program as stored". *Fix:* throw `missingRow` there, which is true of the state it would describe.
- **N4. "on a thread of the store's own"** (`Repositories.swift:52`) is true of the database only; the fake
  runs `change` on the caller's thread under its lock. *Fix:* "inside the store's write, while every other
  call on that store waits".
- **N5. What the compiler already refuses is not said.** `Repositories.swift:52-56`. `change` is synchronous,
  so it cannot `await`, and every repository call but `observeActive()` is `async`: the doc's "must not call
  this repository" is enforced for all of them. The one call that compiles is `observeActive()`, which on the
  fake takes the non-re-entrant lock (`ObservedState.swift:67`) and hangs or traps. Worth one clause, since
  it is the only real way to break the rule.
- **N6. Three reads of five tables per update**, on the writer: the read (`:74`), `ProgramRows.write`'s own
  read of the stored rows (`Records/ProgramRows.swift:56-60`), the read back (`:82`). Fine at these sizes.
  If S13's "a write per keystroke" (Risks 7) ever shows on a profile, return `stored` when
  `changed == stored` and skip the rest.
- **N7. `concurrentUpdatesAndSaves_loseNothing` holds the fixture's shape as numbers.**
  `Tests/LedgerPersistenceTests/ProgramUpdateInterleavingTests.swift:160-169`: `4 ..< 204`, `204`,
  `number / 5`, `number % 5`. *Fix:* derive them from `program.daysPerWeek` and the slots' places.
- **N8. Helpers written twice.** `renamed` (`ProgramRepositoryContract+Update.swift:95`,
  `ProgramUpdateTests.swift:47`); `ChangeFailure` and `ChangeRefused`; `brief` and `line`; `moved(_:to:)`
  and the inline program in `ProgramUpdateInterleavingTests+Edits.swift:110-117`; `Tally` and `StatementLog`
  used as a counter.
- **N9. `HistoryModel.update`** (`Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:92-101`,
  a tester's file) has no id check and does not clear other programs' flag as its `save` does. Nothing calls
  it and no contract runs on it, so the mechanical edit is acceptable; whoever first routes an update through
  the oracle must finish it.

### Verdict on each point asked

**Atomicity on GRDB: holds, by construction.** `update` (`GRDBProgramRepository.swift:71-84`) is one
`queue.write`: GRDB's `inTransaction` around the closure, on the one `DatabaseQueue` every repository shares,
so the read (`:74`), `change` (`:77`), the write (`:81`) and the read back (`:82`) are in one `BEGIN IMMEDIATE …
COMMIT` and any throw rolls back. `save` and `update` write through one function (`:140-145`), which is
`ProgramRows.write` plus the activation, so the checks, their order, the errors and the row rules are
identical; `update` adds only the id check, before them. Nothing is observable between: observers are told
after the commit, and a `ValueObservation` fetch queues behind the write. `save` still validates before it
asks for the writer (`:44`); `update` validates inside (`:81`), which it must.
*The closure:* the doc comments (`Repositories.swift:52-56`, `GRDBProgramRepository.swift:62-64`) are right.
They are sufficient with N4 and N5. A deadlock is not refused at run time, only documented, but the
signature refuses nearly all of it: a synchronous closure cannot call an `async` repository method. What
remains is `observeActive()` and deliberate blocking (a semaphore, a synchronous GRDB access, which traps).
No run-time guard is worth adding.

**Atomicity in memory: by construction, not only by overlap.** The implementer's note undersells it.
`update` is one `state.write` (`InMemoryProgramRepository.swift:68-78`); `ObservedState.write`
(`Support/ObservedState.swift:41-61`) is `Mutex.withLock` around a synchronous body; `change` is a
synchronous function, so no suspension point can exist between the read (`:69`), the change (`:72`) and the
store (`:76`); and a workout's save writes through the same `state.write` (`writeSave`, `:105-116`). What is
"shown by overlap" is only that a *test* would notice if someone later moved `change` outside the lock;
the code as written cannot interleave. No finding. The implementer's open question 5: accept.

**Criteria 2 to 6 and 11, by the code paths.**
- 2: `missingRow` before `change` on both (`GRDB :74-76`, where `ProgramRows.program` reads live rows only;
  fake `:69-71`). Holds.
- 3: `try change(...)` rethrows untouched; rollback on the database, `ObservedState.write` discards its copy
  of the state on the fake. Holds.
- 4: the same function refuses on each store; the order of faults matches (id, re-validation, other programs'
  ids, exercises, then rows). Holds, and the clause compares `save`'s error text with `update`'s.
- 5: no special case; the row diff writes nothing and `activate` touches only rows whose flag changes; the
  fake yields only a changed value. Holds.
- 6: rows as `save`. "Which program is active does not change" holds for every change that leaves the flag
  alone, except in the two-active state of N1.
- 11: no migration, schema, fixture, `Package.swift` or script changed; both clause lists only gain entries at
  their end.

**The deviations.**
- *`duplicateIdentifier("program <id>")` for a result under another id:* acceptable. No other code throws
  `duplicateIdentifier` with the table `program` (the others name `program_week`, `day_template`, `slot`,
  `workout_exercise`, `logged_set`), so a store could tell it apart by the prefix, but it should not have to:
  the builder cannot produce it (`Program.id` is a `let`), so a store should treat it as any unexpected
  error. Keep; no new case.
- *`isActive` saved as `save` saves it:* acceptable, and better than the alternatives. Ignoring a changed
  flag is silent; refusing needs an error nobody can act on. The change receives the stored flag, so only a
  closure that sets it on purpose changes it. Criterion 6's wording should be amended to say so (below).
- *The fake checks cancellation first:* right, and it should go one line further (S1).

**Cancellation (criterion 8): the six tests are sound.** Each cancels at an exact point with no clock:
before the call (the task cancels itself); while waiting (cancel, then free the held writer: GRDB's check at
`SerializedDatabase.swift:264` runs only after the writer is free, so the order is fixed); inside `change`;
at every statement from `BEGIN` to the last before `COMMIT` (fifteen-odd fresh databases, each must end
`.nothing`, and the control run must have written five or more rows); at `COMMIT`; after the commit (a
transaction observer). `Outcome` compares every row of the five tables with its stamp, so "nothing" means
nothing, and a `CancellationError` with rows written, or a return without the edit, is `.broken`. I read the
GRDB source they cite and it says what the notes say. The commit-time test depends on SQLite, is labelled so,
and its failure would not break the rule. The fake is the same before the call and while held, and differs
inside `change` (S1).

**The losing sequence: fair, and clear.** `Opened` is the real order (read; a workout's save with a miss and a
swap; write the copy with an unrelated edit), on both stores. The test asserts the loss, is titled "Why update
exists", and its twin sends the same edit through `update`. A reader will not take it for a bug to fix. S2
puts the same warning where a caller of `save` looks.

**Other conformers.**
- Stub (`Sources/LedgerDependencies/Unimplemented/UnimplementedStores.swift:46-48`): reports as its
  neighbours; in the stub test's list.
- Probe (`Sources/LedgerTestSupport/Engine/ProbedStores.swift:137-139`, `StoreProbe.swift:15`): yes, S13 can
  `hold(.updateProgram)`, `waitUntilHeld()`, `release()` and count `calls`. It holds before the store, passes
  `change` on untouched, and `leave` does not check the task, so a stored change is never reported as
  cancelled by the probe. Nothing iterates `Call.allCases`.
- The four doubles, each the new method only, no other line touched:
  `Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:92-101` (+11, tester's; N9);
  `Tests/LedgerSyncTests/Adversarial/HostSiegeStoresAdversarialSupport.swift:134-136` (+4, tester's; forwards);
  `Tests/LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift:34-36` (+4, tester's; `missingRow`);
  `Tests/LedgerSyncTests/LocalWorkoutSessionActorMissTests.swift:150-152` (+4; throws `Unused()`).
  Three are testers' files, not two.

**Protocol design: right.** A synchronous, non-escaping, throwing `@Sendable` closure is the shape that makes
the misuse hard: it cannot await, cannot be kept, and must capture Sendable values, which keeps a
`@MainActor` store out of it. Returning the program as stored is needed (the weeks are sorted on the way in,
and a workout's writes come back with it), and `update(id) { $0 }` is incidentally a read of any program by
id that writes nothing. `save` should be documented (S2). The seven doubles on the F08 branches: the notes'
table is right; add one line to it after S1 (below).

**Tests.** They assert behaviour, with one deliberate look at statements
(`update_isOneTransaction…`), which is the criterion itself. All eight clauses, the storage clause and the
two linked clauses run on both stores (I ran them: 18, 3 and 9 cases a store). Seeds are the test's argument
and are in the failure text. No sleep, no clock, no polling; every suite has a time limit. **No large value
is compared directly inside `#expect`**: programs and row lists are compared outside and the Bool or a
one-line difference is expected (`ProgramUpdateTests.swift:84-85`, `:111-112`, `:160-161`, `:209-210`;
`ProgramUpdateInterleavingTests.swift:168-172`); what is compared inline is a small enum, a name, or a few
short strings. Names follow §6 loosely, as their neighbours do; the two suites not named for a source type
follow `LinkedSaveDifferentialTests`. Edits to existing test files: `UnimplementedStubTests.swift:50` gains
one call in the list (stronger); the four doubles above; in test support, `clauses` and `linkedClauses` gain
`+ updateClauses` / `+ linkedUpdateClauses`, `storageClauses` one entry, and a doc comment. Nothing removed
or loosened.

**Boundaries, size, lint, docs.** Domain: the requirement and comments. Persistence: `update` and the shared
`write`. Fakes: `update`. Dependencies: the stub. TestSupport: clauses, the probe's call, `TaskCancelSwitch`
(imports `Synchronization` only). No new import crosses a module rule; no migration or schema change; 38
product lines against 45 planned; no `swiftlint:disable`, `@unchecked Sendable` or `nonisolated(unsafe)`
added. `docs/architecture.md` §7 names the repository protocols, not their calls (`:341-347`), so it needs no
sentence.

### Ruling recommendations

| Item | Recommendation |
|---|---|
| Deviation 1, open question 1 (`duplicateIdentifier` for another id) | Keep. |
| Deviation 2, open question 2 (`isActive` as `save` saves it) | Keep. Amend criterion 6 to: "an update whose change leaves `isActive` alone does not change which program is active; a changed flag is saved as `save` saves it." Take N1's condition now or record it for F17. |
| Deviation 3 (the fake checks its task first) | Keep, and add the second check (S1). |
| Deviation 4 (returns the program read back) | Keep; replace `?? changed` (N3) at leisure. |
| Deviations 5, 6, 8, 9, 10 | Accept as built. |
| Deviation 7 (an unreadable program cannot be updated) | Accept. S13 must show the error and must not "repair" by saving its own copy, which is the losing sequence. |
| Open question 3 (the fake's other writes do not check their task) | Leave, as recommended. |
| Open question 4 (the commit row is SQLite's) | Keep strict; watchOS is the gate's to confirm. |
| Open question 5 (atomic by overlap) | Accept; it is by construction in the code (above). |
| Open question 6 (older clauses print whole programs) | Follow-up, as recommended. |
| Open question 7 (three testers' files) | Noted; all four audited above. |

### The seven points

1. Module boundaries: clean; no new cross-module import.
2. Concurrency: sound; one transaction, one lock, a synchronous `@Sendable` closure, the clock injected; S1 is the one gap, in the fake.
3. Error handling: nothing swallowed; errors are `save`'s; `CancellationError` only when nothing was stored.
4. Design fidelity: not applicable (no UI).
5. Accessibility: not applicable.
6. Test quality: behaviour, both stores, seeded and reported, no timing; N7 and N8 only.
7. Brief compliance: criteria 1 to 11 each have a test or a build; criterion 6's wording needs the amendment above.

### What S13, S14 and the waiting branches must be told

- The notes' "Inputs for S13 and S14" stand. Add: after S1, a task cancelled inside the write throws and
  stores nothing on the fake as on the database, so a store test can reach "keep the waiting edits" with
  `TaskCancelSwitch` and not only with the held probe.
- Never `save` a program the store read earlier, including to recover from an error `update` threw
  (deviation 7).
- The closure must not call `observeActive()` (N5), and must not set `isActive`; use `setActive`.
- An update that changes nothing emits nothing: never await an emission after one.
- F08 branches: the notes' table is right. A double that keeps a program should also check the task and the
  result's id if any test will route an update through it; one that only records may throw.
- F17: N1 (two active programs) and N2 (`updated_at` taken before the wait).

### What I did not check

- The full gate, the simulator, watchOS, CI and the nightly lane (every seed) were not run. I ran on the host
  `--filter 'ProgramUpdate|ProbedProgramRepositoryTests|InMemoryContractTests|ProgramRepositoryTests'`: 49
  tests in 8 suites passed (the tester's in-progress files did not break the build at that moment).
- The `/code-review` pass (effort high) ran as a separate agent that read the commit without building; its
  nine candidates are folded in above (S1, N1, N2, N3, N6, N7, N8, N9, and deviation 7). I did not reproduce
  N1 with a test; it follows from reading `:81` and `:148-155`.
- The implementer's break-and-restore table and the "8 of 8" overlap rates were not repeated.
- That `fixedSeeds` are the first thirty of `PropertySeed.all` was not verified.
- The seven doubles on the F08 branches were not read.
- The tester's files under `Tests/LedgerPersistenceTests/Adversarial/` were not read, as instructed.

---

## Slice S5 — review (G3 reviewer, 2026-10-06)

Reviewed: `git diff 7055d80..f922c69` (the committed slice; the merge of `main` at the tip and the tester's
untracked files under `Tests/FeatureProgramTests/Adversarial/` were not read). Paths below are under
`LedgerKit/` unless they begin with `docs/` or `tasks/`; `Tests/…` is `Tests/FeatureProgramTests/…`.

### Verdict

**Approved: 0 Blocking, 6 Should fix, 9 Nit.** The slice does what its eleven criteria ask. The model is
drawn from the input alone, every text is the brief's character for character, each edit is one
`ProgramEditing` call, and the module holds no rule of the block. Nothing found changes what the seed program
reads as. The Should-fix items are one design ruling the orchestrator owes S13 (S-1), two places where the
notes tell S9 and S13 something that is not so (S-2, S-3), the standards sentence ruling 3 gave this pull
request (S-4), and two small test items (S-5, S-6). None of them needs product code to change in this pull
request except S-4 (a doc) and the two test items.

**I could not run the tests.** `swift test --filter FeatureProgramTests` does not build on this tree: the
tester's in-progress `Adversarial/ProgramAdversarialSupport.swift` fails to compile (`:57`
`MovementPattern` has no member `push`; `:117` `Fixtures.Invalid.init` is internal). Every statement below
is from reading; the pass and coverage figures are the implementer's and the orchestrator's, not mine.

### Should fix

**S-1. Two of the relative edits should become absolute before S13 is written; rule on it now.**
`Sources/FeatureProgram/ProgramBuilderAction.swift:32-33` (`toggleDeload(week:)`,
`cycleSchedule(week:weekday:)`), built at `ProgramPresentation+Weeks.swift:71` and `:106-112`.
- *What.* The store shows "the stored program with the waiting edits applied" and sends the same edits
  through `update`. `update` returns the stored program, and `observeActive` emits that same program once
  (S3's "Inputs for S13"). If the emission reaches the store before it has dropped the edits it just sent,
  the screen is drawn as stored + edits a second time: with a relative edit that is a wrong screen (Tuesday
  reads LA where the lifter chose UA; a deload flips back), and the model built from it hands out actions
  judged on that wrong program (the cell's empty-day notice, "−"). With absolute edits the same race draws
  the right screen, because applying them again changes nothing. The brief's "each queued edit reaches the
  stored program exactly once" then guards two edits (`removeLastWeek`, and `move` in S14) instead of four.
- *Also stale here.* `cycle` (`+Weeks.swift:108-111`) decides the notice from the day the tap would assign
  on the program on screen; the queued edit says only "the next". When the two differ (the race above; two
  activations from one drawn model) the notice describes a day that was not assigned.
- *Fix (recommended).* A cell's action names the day it will become, which `cycle` already computes:
  `.setSchedule(week:weekday:day: DayTemplateID?)`; the toggle names its state: `.setDeload(week:isOn:)`.
  Each needs one small Domain function (`ProgramEditing.schedule(_:week:weekday:day:)`, ignoring a day the
  program does not hold; `setDeload(_:week:to:)`), about 15 Domain lines with tests, so it is not this
  slice's to make (the slice may not touch `LedgerDomain`). Do it as a small slice before S13, with two
  cases of `ProgramBuilderEdit`, `+Weeks.swift:71,111` and the tests that name those cases. The cycle stays
  the Domain's: the presentation still asks `cycleSchedule` which day comes next.
- *The other choice.* Keep them relative and bind S13 to it in writing: the returned program is adopted and
  the sent edits dropped in one synchronous step; a stored program that arrives from `observeActive` while a
  save is in flight is never combined with edits already handed to `update`; one store test holds the
  observation ahead of the return and reads the screen. That is a rule S13 can get wrong without a failing
  test in this slice, which is why I recommend the first.
- `removeLastWeek` stays relative either way (see S-2); `addWeek`, `addDay`, `renameProgram`,
  `copyPreviousWeek`, `applyToLaterWeeks` are already safe to apply twice
  (`ProgramBuilderActionTests.relativeEdits_appliedTwice_differ` shows both halves).

**S-2. The notes say `update` can refuse a "−" because a workout finished meanwhile. It cannot.**
`tasks/…/implementation-notes.md`, S5 "Decisions and deviations" 3 and "Inputs for S13" ("An `update` that
throws `ProgramEditError` (the last week was logged meanwhile)"); `ProgramBuilderAction.swift:31`,
`+Weeks.swift:23-26`.
- *What.* The edit carries the logged weeks as they were when the model was built. Inside `update` the same
  set is applied to the stored program, so `weekHasLoggedSessions` is decided by the stale set, not by
  anything stored: a workout finished in the last week between the tap and the write does not stop the
  week's removal. (`/code-review` found the same.) Inside `update` the edit can only throw when the stored
  block has another length than the screen's, which only this store changes, so
  `ProgramBuilderNotice(error)` is close to unreachable.
- *Why it matters.* S13 would write a test and a path for a refusal that never comes, and believe the last
  week is protected by the write. The plan already accepts the window ("How a week is known to have logged
  sessions": the failure is harmless, the workout keeps its own name and numbers), so nothing is lost; the
  notes must stop claiming more.
- *Fix.* Correct both sentences: "the check is as fresh as `loggedWeeks` in the input; S13 reads it again
  whenever `observeRecent` emits and when the screen appears". Say on the case's doc comment (`:31`) that the
  set is the one the model was built from. No code change.

**S-3. The program's name: the model leaves the view a decision, and following the notes makes a field
that cannot be typed in.** `Sources/FeatureProgram/ProgramBuilderModel.swift:17-19`; notes, "Inputs for S9"
("a one-line text field holding `name`"; the view "sends `.edit(.renameProgram(text))` with the text as
typed") and the plan's "a name is saved as it is typed".
- *What.* `header.name` is the cleaned, stored name. A field bound to it that sends every keystroke loses
  each trailing space as it is typed ("Upper " comes back as "Upper", so two words cannot be entered) and
  cannot be emptied (a blank name changes nothing, so the last letter returns). Whether the field shows the
  model or a draft is a decision, and the model's comment points the view at the wrong one. It is also the
  one place a view builds an action, naming `ProgramBuilderEdit` itself.
- *Fix.* Doc comment and notes: "`name` is the stored name and seeds the field; while the field has focus
  it shows the lifter's own text, kept by the view or the store, and is not written back from the model."
  Add `static func rename(_ text: String) -> ProgramBuilderAction` beside the enum (3 lines) so the view
  calls it and never names an edit. S13 gets a test: typing "Upper Lower" letter by letter stores
  "Upper Lower".

**S-4. The sentence ruling 3 gave this pull request is not in it.** `docs/engineering-standards.md:249-253`
still reads "Not settled: display names shared by several features". The implementer's reason (the slice
shows no such name) is true and beside the point: S6, S7 and S8 start in parallel from this merge and each
writes such names. Replace the bullet with:

> - **A Domain value's name is each module's own.** Where the name of a Domain enum's case (a kind of
>   equipment, a muscle group, a progression rule) is shown, the module that shows it holds its own entry
>   for it in its own catalog and its own member in its own copy file, one lookup per case. The key is the
>   English text, so two modules cannot differ in English; no module looks up another module's key, and
>   nothing shared is built (orchestrator, 2026-10-05, on F11's proposal 2).

and drop "The equipment names this slice needs are entries of this catalog" from the S5 row's reading of
`ProgramCopy.swift` in the notes ("with the equipment names"), since S6 adds the first.

**S-5. Three whole programs are compared inside `#expect`.** The suite's own habit (`let isSame = …;
#expect(isSame)`, as at `ProgramBuilderActionTests.swift:37`, `ProgramPresentationTests+Total.swift:112`)
is not kept at:
- `Tests/ProgramPresentationPropertyTests.swift:54` — `#expect(after == before, …)`, in a test that runs
  200 seeds × 8 actions;
- `Tests/ProgramPresentationTests+Notices.swift:18` — `#expect(screen.input.program == program)`;
- `Tests/ProgramPresentationTests+Total.swift:22` — the same.
Fix: compare outside, expect the Bool with a message. Everything else compared directly is small: a
`Control` and a `Toggle` of two and three fields (`+Week.swift:120`, `:153`), arrays of at most eight
actions or ids (`ProgramPresentationTests.swift:76`, `+Week.swift:32`, `+Days.swift:31-32`), strings.

**S-6. The source test dropped `FeatureToday`'s second list.**
`Tests/FeatureProgramSourceTests.swift:17-27`. Its `ambient` list is `FeatureTodaySourceTests`'s, spelling
for spelling (`.dateTime`, `Calendar(identifier:`, bare `.formatted()`, the three formatter classes, the
`.now` forms): good. The `inexact` list (`Double`, `Float`, `CGFloat`, `TimeInterval`, `.doubleValue`,
`.floatValue`) and its test are gone. This slice prints no weight, so nothing is wrong today; but the test
says it reads "the views and the stores when they come", S6 and S7 print loads next, three slices start
from this file at once, and none of them owns it. Fix: add the list and
`presentationsCopyAndModels_neverNameDouble` over files named `…Presentation…`, `…Copy…`, `…Model…`, with
its line in `check_findsASpellingInCodeAndInInterpolations`. If the orchestrator would rather not touch the
slice for it, give it to S7 by name.

### Nit

- **N-1. `.addWeek(selecting:)` is a place taken from the drawn model**
  (`ProgramPresentation+Weeks.swift:15`). Two activations from one model (VoiceOver's increment twice, a UI
  test) append two weeks and select the first of them, not the newest (criterion 4). Either the store
  selects the last week of the program it has just applied `.addWeek` to, or S13 pins that the model is
  rebuilt between intents. Not worth a change here.
- **N-2. `DayCard.chips` has no identity and can repeat** (`ProgramBuilderModel.swift:133-134`,
  `ProgramPresentation+Days.swift:45`): the same exercise twice, two missing exercises ("—", "—"), as the
  slice's own test shows (`+Total.swift:58`, `+Days.swift:117`). The notes give identity for cards, cells
  and week chips, not for these. Add to the comment: "identified by their place". The "+2" chip cannot be
  told from a name; the prototype draws it the same, so that is right as long as S9 does too.
- **N-3. The clamp tripwire reads files named `Presentation` or `Store`**
  (`FeatureProgramSourceTests.swift:54-56`). S13's `ProgramEditSession.swift` is neither. Read every file
  but `…Copy…`, `…Model…`, `…Route…`, or add `Session`. It is a tripwire for `min(`/`max(` only: the
  nearest-week reading at `ProgramPresentation.swift:72-76` is written with a ternary and passes, rightly
  (criterion 9 asks for it), which also shows what the check cannot see.
- **N-4. Four keys that carry a value have no translator's comment**
  (`ProgramCopy+Days.swift:13, 24, 28, 70`): "%lld sets a week" (every day's sets together, not a week's
  schedule), "%lld exercises", "%lld sets" (a day's, with its drop sets), "Week %lld has logged sessions
  and can't be removed." (the week's number, counted from 1). No key holds two values, so the rule on
  those has nothing to check.
- **N-5. "Deload" is one key for two things** (`ProgramCopy.swift:147-153`): the button that makes a week
  a deload (a verb in many languages) and a deload chip's spoken value (a state). The catalog cannot hold
  one English text twice, so the cure is another English text for the spoken one ("Deload week"), which is
  an invented text and Pete's (below). Nothing breaks while only English ships.
- **N-6. Two test names stop at the condition** (`+Notices.swift:11`, `:22`): `message_twoWeeks`,
  `message_loggedWeek`. Testing-strategy §6 wants `subject_condition_expectation`:
  `removeWeek_twoWeeks_showsTheNoticeAndChangesNothing`, `removeWeek_loggedLastWeek_namesTheWeek`.
- **N-7. A card's spoken value is the drawn line** (`ProgramPresentation+Days.swift:47`):
  "5 exercises · 18 sets · ~39 min". It agrees with what is drawn (criterion 8). How VoiceOver says "~"
  and "min" I did not hear; S9's VoiceOver pass on a simulator settles it, and if it says "tilde" the
  card wants a spoken estimate ("about %lld minutes", one key).
- **N-8. `BuilderScreen` is a second implementation of "apply an action"**
  (`Tests/Support/ProgramTesting.swift:149-171`). It is the right tool for this slice (criteria 2 to 6 read
  as "tap, read the next model"). Once S13 lands there are two, and these tests stay green if the store
  drifts. S13 either drives the same scenarios through the store or builds `BuilderScreen` on its session.
- **N-9. The pull request is over the 500-line target** (534 product lines, recounted file by file; 470
  planned). Standards §10: its description says so in one line and names the split considered (the action
  file, 50 lines, is the natural one and not worth a cycle). Under the 650 at which S6 to S8 are estimated
  again.

Looked at and not a finding: the seven speculative cycles and one speculative "−" per `make`
(`+Weeks.swift:25, 108`) copy the week array eight times; the implementer measured 0.8 ms at 16 × 6, and a
Domain query ("the day a tap would assign", "can the last week go") would be tidier but is a Domain change.
`SeededGenerator` and `PropertySeed` are a third copy in a test target: the standing pattern
(`FeatureTodayTests/Support/TodayTesting.swift` is the same text), for the reason the file gives.

### The bug pass (`/code-review`, effort high)

Run as a separate agent on the commit, without building. Nine candidates, all folded in: the stale logged
weeks (S-2); the week start (deviation 1, below); "sets a week" (for Pete, below); the empty-day notice's
wording (for Pete, below); the hand-written nearest-week reading (N-3; specified by criterion 9, kept);
`chips` without identity (N-2); `.addWeek(selecting:)` (N-1); the speculative edits' cost and the copied
generator (not findings, above). It found no trap, no wrong count and no wrong text, and neither did I.

### Verdict on each point

**The model as an interface: sound, with one hole (S-3).** `ProgramBuilderModel` is what the prototype's
eleven rows need and little else: every string final, every colour decision a Bool (`isDeload`,
`isSelected`, `isRest`, `isOn`), a disabled control a nil action, an absent one a nil control, identity for
cards (`id`) and cells (`weekday`). Not in it, and S9 must not invent: the name field's draft (S-3);
separate spoken labels for "−" and "+" (one adjustable element is given, as S4's `StepperField` is built);
identity for a card's chips (N-2); where the notice stands and that it is announced. "WEEK 8 · DELOAD" is
one string; the prototype draws it in one colour, so that is right. The input is fillable from `main` with
no new requirement: `observeActive()`, `observeAll()` keyed by id, `SettingsRepository.observe()`, the
store's own selection and notice, the two dependencies, and `loggedWeeks` from `workouts(in:)` as the plan's
"How a week is known to have logged sessions" reads it. That last one is a read, not a stream: S13 repeats
it (S-2). `Settings` is handed whole for one field, as `TodayInput` does.

**The actions: correct as built; two should change shape before S13 (S-1).**
`applied(to:)` (`ProgramBuilderAction.swift:40-59`) is one `switch`, each arm exactly one `ProgramEditing`
call with the case's own values and nothing else; pinned case by case against the Domain
(`applied_isTheOneProgramEditingCall`). It is `nonisolated`, synchronous, with typed throws, and the edits
hold only `String`, `Int`, `Set<Int>`, `Weekday` and typed ids, so `edits.reduce(program) { try
$1.applied(to: $0) }` fits `update`'s `@Sendable` synchronous closure and captures nothing of the store.
`ProgramBuilderAction`, `ProgramBuilderEdit`, `ProgramBuilderNotice` and `ProgramRoute` are `Hashable` and
`Sendable`. Double application: nothing here sends an edit twice; what makes a second application more
likely to *show* is the store's "stored + waiting" rule meeting `observeActive` (S-1), and three values are
taken from the drawn program and can go stale: the cell's notice, `removeLastWeek`'s logged weeks (S-2),
`.addWeek(selecting:)` (N-1). Weeks are named by place, not by `WeekID`: safe, because only this store adds
or removes weeks and `ProgramEditing` is written on places. Recommendation: make the cell and the deload
absolute (S-1); leave "−" relative.

**Weeks, cells, counts: right.** The selection is read as the nearest week in one place
(`ProgramPresentation.swift:71-76`) and every action, the card's route and "+ Add training day" carry that
place, not the raw one (`selectedWeek_outsideTheBlock_readsAsTheNearest`, seven cases with `Int.min` and
`Int.max`). A chip's count and the strip read the schedule through one function (`:44-49`), which counts an
entry only when it names a day the program holds, as the prototype does (`v < s.days.length`) and as
`cycleSchedule` reads it. Each cell's weekday, letter and name are tied to the weekday, not to the cell's
place: `symbol(of:in:)` uses `calendarWeekday - 1` on Foundation's Sunday-first symbols, so reordering the
strip cannot shift a letter. "Copy week 2" on week 3 is `place`, "Apply to later weeks" is absent exactly on
the last week. Cards count `sets + dropSets` over the slots as written and take minutes from
`TimeEstimate.minutes(day:prescriptions: [:])`, so a deload week changes no card
(`dayCard_meta_isTheSlotsOwn`). **"4 days · 58 sets a week" is the number of training days in the program
and the sum of all their sets**, exactly the prototype's `daySummary` (`s.days.length`, `Σ setsOf(d)`). It is
not what a week trains: week 8 of the seed trains three days and still reads "4 days · 58 sets a week";
a day added and not scheduled counts; a day trained twice a week counts once. Built as the brief and the
prototype have it. For Pete, below.

**The words: the brief's, exactly.** Every key the brief gives is in the catalog character for character
(checked by script against brief:60, the middle dot U+00B7 included); 33 keys, in code-unit order, all
`translated`, source language `en`; eight counted keys each with `one`, `other` and one `%lld`. The splits
follow §7: "%lld days" + "%lld sets a week", "%lld exercises" + "%lld sets" + "~%lld min", "WEEK %lld" +
"DELOAD", each joined by the one " · " (`ProgramPresentation.swift:15`). No split is wrong for another
plural rule: each fragment carries its own count, and nothing is built from a word and a number held apart.
What a translator cannot do is reorder fragments across the " · ", which is the convention's limit, not
this slice's. "~%lld min" is counted with both forms alike, as `FeatureToday`'s is. "W%lld", "WEEK %lld",
"Week %lld", "Copy week %lld" and "+%lld" are rightly not counted (a number that names, not one that
counts). Valued members take `locale:`; plain ones do not, as §7 says. The spoken texts are copy and agree
with what is drawn. Comments: N-4, N-5.

**Purity and structure: clean.** Every type is `nonisolated`; the copy is a `nonisolated enum` and its
extension. No clock is read anywhere (the input has no moment). The calendar is copied, given the input's
locale and asked only for two symbol lists (`:79-82`), so its own locale, first weekday and zone cannot
reach the model (`calendarsOwnSettings_doNotReachTheModel`). The source test: S-6, N-3. Files 5 to 115 code
lines, the longest function about 25; nothing compressed, comments say why. `Package.swift` gains only
`resources`; `coverage-thresholds.json` gains `FeatureProgram` in `required`; the placeholder and its test
are gone and nothing else named them. Imports: `Foundation` and `LedgerDomain` only, in every file. No
change to `LedgerDomain`, `LedgerAppKit`, a test plan or the project. No lint suppression in sources or
tests.

**Tests: behaviour, with the caveat of N-8.** Criterion 1 is one test that reads the brief's line word for
word (`seedProgram_readsAsCriterionOne`: the block title, the eight chips as one line, the strip, the
summary, four names, tags and meta lines) and a second that ties the minutes to `TimeEstimate`. Criteria 2
to 6 are "tap a control of the model, read the next model". The property suite checks real invariants
against a reference written apart from the code (a chip's count from the stored schedule, the nearest week,
"−" against the Domain, every action's week and ids, a rebuild through `Program.init` after each of eight
random actions, a cell cycled through every day and back with the notice exactly on an empty day); seeds
are `PropertySeed.all`, printed by the case's description; inputs cover six locales, every week start,
selections two outside each end, a day trained twice, a missing exercise. S-5, N-6. Coverage 406/406 is the
orchestrator's figure; I did not measure it. The suite takes about 5 s on the host by the notes and has no
`.slow` tag, as `FeatureToday`'s has none.

**Brief compliance, boundaries, leaks, size.** Each of the eleven criteria has a test or a gate step (the
notes' table is accurate where I checked it against the files). `ProgramRoute.closeDay` is S14's route but
the plan's S5 row puts the file here. Nothing else of S6 to S14 is in the diff. Size: N-9.

### Ruling recommendations: the deviations and the open questions

1. **The strip follows `Settings.weekStart`: keep, and amend "Brief vs main" row 20.** *Order of the
   cells:* the brief (brief:60, "weekday letters per `Settings.weekStart`"), the S5 specification's
   criterion 3, and Today's strip (`TodayPresentation+WeekStrip.swift`, "from the settings' week start")
   all say the week start; row 20 alone says the weekday the block began on, and the S5 section is the
   later text. The spec's prototype is fixed Monday to Sunday and decides nothing. Row 20's worry is real
   but narrow: F08 starts a block on the week start, so the two differ only after the lifter changes the
   setting mid-block, and then the leftmost cell is that program week's last day. Two screens that order a
   week differently would be worse. Record it for F14 (Settings): changing the week start mid-block does
   not move the block. *Letters and spoken names:* these belong to the weekday, not to the order, and come
   from the injected calendar's standalone symbols in the injected locale. Right under either order.
2. **"−" and the empty-day notice decided in the presentation: a display of the Domain's answer, not a
   rule.** Both run the Domain's own function on the program on screen and report what it did; no limit
   and no order is written here, and reordering the Domain's cycle would move the notice with it
   (`cell_cycledThroughEveryDay_returns`). "Brief vs main" row 9 gave the notice to the presentation.
   Criterion 10 holds. The cost is staleness, not duplication: S-1, S-2.
3. **No equipment names in the catalog: accept.** The builder draws none; a key no code looks up fails the
   gate. Criterion 7's sentence asks for "the names this slice needs", which is none. S6 adds the first,
   under the sentence of S-4.
4. **`WeekCalendar` unused: accept, and it is the right division.** Nothing the builder draws is a date.
   "The week that holds today" is one Domain call in S13
   (`WeekCalendar(startDate:weekStart:calendar:).weekIndex(for: now)`), handed over raw; the presentation's
   nearest-week reading turns a negative index into week 1 and one past the end into the last week, which
   is behaviour 1 word for word. S13 writes no clamp.
5. **The property inputs' sizes: accept.** 2 to 16 weeks with one block in sixteen of 52, 0 to 12 days of
   0 to 7 slots, reaches the plan's range without a `.slow` suite.
6. **No timing test: accept for this pull request.** The 100 ms budget is a first-frame budget, which the
   view owns; 0.8 ms (the implementer's figure, not repeated) is far from it. Decide with S9 whether the
   nightly plan gets a `.performance` suite for the page.
7. **The action file (unplanned): accept.** It is what "an action the store can apply without deciding"
   means, and S3's notes already assumed it.
8. Open question 2 (the standards sentence): add it now, S-4. 3 (the empty, failed and not-saved texts):
   S13 adds them with the states. 5 ("Double-tap to assign"): Pete's, below; I would change it. 6 (a stale
   selection after "−"): keep; the store stores nothing back.

### For the product owner: the texts this slice wrote, and three things the brief's wording does

| Text | Where | Judgement |
|---|---|---|
| "Block length" | VoiceOver, the label of "−" and "+" read as one control | Good. Plain, and what the control changes. |
| "8 weeks" (`%lld weeks`) | VoiceOver, that control's value | Good. |
| "Week 3" (`Week %lld`) | VoiceOver, a week chip ("Week 3, 4 days") | Good; your decision 6's example. |
| "4 days" / "Deload" | VoiceOver, a chip's value | Good. A deload week does not say how many days it trains, as its chip does not draw it. If you want "Deload week" spoken, say so (N-5). |
| "Rest" | VoiceOver, a rest cell ("Tuesday, Rest") | Good; the drawn "REST" stays. |
| "Double-tap to assign" | VoiceOver, the hint of each weekday cell | **Change recommended.** It is your brief's accessibility line, but Apple's guidance is that a hint says what happens and does not name the gesture. "Assigns the next training day" says what the tap does. One key. |
| "—" | On a day's card, in place of an exercise that is no longer stored | Fine. Rare (nothing deletes an exercise in M1); never spoken. |

Three things that are the brief's own wording, built as written, that you may not have meant:
- **"4 days · 58 sets a week"** counts the training days you have defined and all their sets, not what a
  week trains. A deload week with three days scheduled still reads "4 days · 58 sets a week"; a new day not
  yet scheduled adds to it; a day trained twice a week counts once.
- **"Add at least one exercise before scheduling this day."** shows after the empty day *has* been
  scheduled (your brief: "the day is still assignable"). The sentence reads as a refusal. "This day has no
  exercises yet." would say what is true.
- **The week starts where Settings says**, on the builder and on Today alike. If you change the week start
  in the middle of a block, the builder's leftmost day is no longer the first day of that program week.

### The seven review points

1. **Module boundaries:** `Foundation` and `LedgerDomain` only; nothing outside `FeatureProgram`, its tests,
   `Package.swift` (one target's `resources`) and the thresholds file.
2. **Concurrency:** all `nonisolated` values, `Sendable`; no task, no clock, no id made here (ids are
   parameters of the edits); `applied(to:)` fits `update`'s closure.
3. **Error handling:** the one typed `catch` (`+Weeks.swift:27`) turns each Domain error into its notice;
   nothing is swallowed. What the notes say that path means inside `update` is wrong (S-2).
4. **Design fidelity:** no view. The words and the rows are the prototype's; the model carries the facts
   the dark design's accents need and no colour.
5. **Accessibility:** spoken label, value and hint exist for chips, cells, cards and the block's length,
   all copy. For S9: the hint's wording (Pete), the notice announced, N-7.
6. **Test quality:** behaviour, seeded, no sleep, no clock; S-5, N-6, N-8.
7. **Brief compliance:** eleven of eleven criteria have a test or a gate step; ruling 3's sentence is
   missing (S-4).

### What S9 and S13 must be told

**S9.**
- The name field shows the lifter's draft while it has focus; `header.name` only seeds it (S-3).
- A card's chips are identified by their place; names can repeat (N-2). Cells by `weekday` (letters
  repeat: T, T; S, S). Week chips by place.
- The model gives one adjustable element for "−" and "+". Two separate buttons need two labels that do not
  exist: ask, do not write them in the view.
- `notice` appearing or changing is announced to VoiceOver; a lifter who decrements the block's length by
  swipe otherwise hears nothing when it is refused. The model does not say where the line stands.
- Do not split "WEEK 8 · DELOAD" to colour a word; the prototype draws it in one colour.
- Listen to a card's value ("~39 min") in the VoiceOver pass (N-7).

**S13.**
- The ruling on S-1 decides the store's shape. If the edits stay relative: adopt `update`'s answer and drop
  the sent edits in one synchronous step, never draw an observed program with edits already sent, and test
  it with the observation held ahead of the return.
- `loggedWeeks` is as fresh as the last read; read it again when `observeRecent` emits and when the screen
  appears. `update` will not refuse a "−" for a workout finished meanwhile (S-2).
- Hand `selectedWeek` over raw (`WeekCalendar.weekIndex(for:)`, or `ProgramRoot(week:)`); write no clamp.
- An action is applied to the program the model was built from; rebuild the model before the next intent
  is taken, or `.addWeek(selecting:)` and a cell's notice can speak for the wrong program (N-1).
- `.addDay` emits its route with the id drawn at the tap; the plan has the route wait for the save.
- `ProgramEditSession.swift` is not read by the clamp tripwire until N-3 is done.
- Drive this slice's worked examples through the real store, or build `BuilderScreen` on the session
  (N-8). Add: a name typed letter by letter with a space in it.
- The empty, failed and not-saved texts are yours to add (open question 3).

### What I did not check

- **No test was run by me.** The test target does not build on this tree while the tester's files are in
  progress (above), and I was told not to copy the repository. The 61 tests, the 406/406 coverage, the
  catalog step ("keys: 33") and the gate are the implementer's and the orchestrator's results.
- The implementer's break-and-restore table (eight mutations) and the 0.8 ms timing were not repeated.
- How VoiceOver pronounces any of the spoken texts; no simulator.
- Whether nested types of a `nonisolated` struct are themselves `nonisolated` under the module's
  `MainActor` default: taken from the fact that `nonisolated` test suites read them and the gate built.
- An injected calendar that is not Gregorian, and locales beyond those the tests name: by reading only
  (`symbol(of:in:)` returns "" rather than trapping when a symbol is missing).
- The tester's files and findings for this slice were not read, as instructed.
- `docs/architecture.md`: §4's routing rules and §12 were read; §5 and §11 were not (no Domain change and
  no view in this slice).
