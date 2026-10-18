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

---

## Slice S6 — review (G3 reviewer, 2026-10-08)

Reviewed: `git diff 7e15f61..63f397f` on `feat/F11-s6-day-slot-presentation` (the committed slice; the
tester's untracked `Adversarial/DayEditor…` files were not read). Paths are under `LedgerKit/` unless they
begin with `docs/`, `design/` or `tasks/`; `DayEditor/…` is `Sources/FeatureProgram/DayEditor/…` and
`Tests/…` is `Tests/FeatureProgramTests/…`.

### Verdict

**Approved: 0 Blocking, 4 Should fix, 11 Nit.** The slice does what its ten criteria ask. `make` reads its
input and nothing else; every text is the brief's, character for character, or is listed for Pete; each edit
is one Domain call; the numbers are the Domain's in both units; nothing of a view or a store is in it.

What I ran, on the host: `swift build --build-tests` exit 0, with no error or warning line (an incremental
build of an up-to-date tree, about 4 s). The tester's files then appeared and stopped `FeatureProgramTests`
from compiling (`Adversarial/DayEditorAdversarialScreen.swift:143`, `:194`: `AdvDayPanel` not in scope), so
the tests were run with `swift test --skip-build` from the binaries of that first build, which was made from
the committed tree alone: `FeatureProgramTests` 199 tests in 16 suites passed; the Domain suites named
`DayEditing…`, `ProgressionRules…` and `Slot · resolved start load and step` 157 tests in 19 suites passed;
`ModuleCopyTests` 6 passed. No helper process was left running.

### Should fix

**S-1. The last member of a superset shows its own rest; the workout rests the longest member's.**
`DayEditor/DayEditorPresentation+Rows.swift:98`, under the header built at `:41-44`.
- *What.* A row of a superset's last member prints `slot.rest`. The Domain rests a superset once a round
  for the longest rest among its members (decision #7; `Sources/LedgerDomain/Rules/SupersetRounds.swift:43-47`),
  and `TimeEstimate.minutes` counts that rest (`Rules/TimeEstimate.swift:22`, `:26`). The seed program shows
  the difference on its first day: Lat Pulldown rests 75 s and Cable Lateral Raise 60 s
  (`Sources/LedgerFakes/Fixtures/Fixtures+Program.swift:73`, `:78`), so Upper A reads "4A … no rest" and
  "4B … 1 min rest" under "rest after B" (pinned at `Tests/DayEditorPresentationTests.swift:42-43`), while
  the workout rests 1:15 and the header's "~39 min" counts 1:15. Stepping 4A's REST changes the minutes and
  no row shows why; stepping 4B's below 4A's changes the row and not the workout.
- *Why it is not Blocking.* It is the prototype's line (`design/prototype/Ledger.dc.html:1370`) and the
  brief's ("no rest" for non-last members), so the slice is built as specified. The specification and the
  Domain disagree, and criterion 8 says a rest is the Domain's to decide.
- *Fix.* A ruling, then a few lines. Recommended: the last member's row prints the group's rest, from a
  Domain function over slots (for example `SupersetRounds.rest(of slots: [Slot]) -> RestDuration`, which
  `TimeEstimate.minutes` then also calls), and `subLine` takes that value; one test on Upper A ("1:15 rest").
  If Pete prefers the prototype's line, record it as a decision so that S11 does not rediscover it.

**S-2. `isRelative` reads as a promise that the other edits may be sent again; a queue of them may not.**
`DayEditor/DayEditorAction.swift:30-31` ("such an edit reaches the stored program exactly once, and is never
sent again after a failed save") and `:55-57`; the notes' "Inputs for the stores", "Relative edits".
- *What.* Every edit not marked is safe applied twice on its own, and the tests show it
  (`Tests/DayEditorActionTests.swift:104-114`, the property at `DayEditorPresentationPropertyTests.swift:49-53`).
  A queue of them is not. On the day [Z, A, B]: "Superset with next" on A is `setSuperset(true, slot: B)`,
  then "Remove" on A leaves [Z, B] with B leading (`Sources/LedgerDomain/Programs/DayEditing.swift:88-95`).
  Applied again to that result, `setSuperset(true, slot: B)` joins B to Z (`DayEditing.swift:125-129`: the
  edit means "the slot before it", whoever that now is) and the removal finds nothing: the day ends as
  [Z, B joined to Z]. This is read from the code, not run. A superset edit is absolute in its state and
  relative in its neighbour.
- *Why it matters.* S5's ruling 12 made edits absolute so that a screen drawn as "stored + waiting edits"
  when the stored program already holds them is still right. For the Day editor that holds for one edit and
  not for every queue, and a store author who reads the mark as "safe to re-apply" builds the wrong thing.
- *Fix.* No behaviour changes. Reword the comment at `DayEditorAction.swift:30-31` and the notes: every
  queued edit, marked or not, reaches the stored program exactly once, and the sent edits are dropped
  before the screen is redrawn from the stored program; the mark says only which single edits differ when
  repeated. Add the example above as one test in `DayEditorActionTests` so the limit is pinned.

**S-3. The day's sets are still summed in the feature, after a second deferral.**
`Sources/FeatureProgram/ProgramPresentation+Days.swift:31-33`, called at `DayEditor/DayEditorPresentation.swift:64`.
- *What.* Criterion 8 lists counts among what comes from `LedgerDomain`. `setCount` knows two things the
  Domain also knows inside `TimeEstimate.minutes` (`Rules/TimeEstimate.swift:21-24`): a prescription's sets
  replace the slot's, and a drop set is one more set. S5's deviation 8 left this for S6; S6 leaves it for F09.
- *Why it matters.* The header prints the count beside minutes worked out from the same sum; two copies can
  part, and no test would say which is wrong.
- *Fix.* Now, since this pull request already changes `LedgerDomain`: `TimeEstimate.setCount(day:prescriptions:) -> Int`
  beside `minutes`, used by `minutes` and by `ProgramPresentation.setCount` (about six lines and one test). If
  the orchestrator prefers not to touch the Domain again here, amend criterion 8 to say so; do not defer a
  third time without a named slice.

**S-4. Whole models are compared inside expectations** (S5's ruling 16, for `Program` there). A failure
prints the entire `DayEditorModel`, `Details` or `DayTemplate`. Every place:
`Tests/DayEditorPresentationTests+Total.swift:41`, `:51`, `:61`, `:63` (`… == .dayIsGone`), `:129`, `:145`
(`details == nil`); `Tests/DayEditorPresentationPropertyTests.swift:22` (`model == .dayIsGone`), `:101`
(`screen.day == nil`).
- *Fix.* As the files do elsewhere: `let isGone = model == .dayIsGone; #expect(isGone)`, or a small
  `var isGone: Bool` on the model in `Support/DayEditorTesting.swift`; `details == nil` as
  `let hasDetails = … != nil`. The other comparisons in the new files are of strings, flags, ids or three
  edits at most, and are fine.

### Nit

- **N-1. A removal is marked relative and is not.** `DayEditor/DayEditorAction.swift:73`. By the brief's own
  definition ("applied twice they do not give what one application gives") and by this slice's test
  (`Tests/DayEditorActionTests.swift:121-126`) a removal is absolute; criterion 10 names it relative. See the
  ruling below; either way the comment at `:55-57` should say which definition the mark follows.
- **N-2. Two comments promise more than the model gives.** `DayEditor/DayEditorModel.swift:24` and
  `SlotEditorModel.swift:5`: "A control that could do nothing is absent", yet a stepper at its limit and
  its two actions are always there (`SlotEditorModel.swift:43-44` says so). Add "but a stepper" to both.
- **N-3. Stale file name in a comment.** `Tests/DayEditorPresentationTests.swift:8-9` says "Delete day" is in
  `+Delete`; it is in `+Total`.
- **N-4. The source test does not name the file that holds the steps.**
  `Tests/FeatureProgramSourceTests.swift:82-88` lists five Day editor files; add
  `SlotEditorPresentation+Fields.swift`, the one a clamp would most likely be written in. (It is read today:
  the check reads every file of the module; the list only proves it.)
- **N-5. `Row.hasDropSet` has no stated use.** `DayEditor/DayEditorModel.swift:91-92`. The sub line already
  says "drop", and the notes' list of facts that pick a colour leaves it out. Say what S10 does with it, or
  remove it.
- **N-6. One-word keys without a translator's comment.** `DayEditor/ProgramCopy+DayEditor.swift:90-96`
  ("Band", "Cable" and "Machine" read as other things alone), `:176`, `:208`, and
  `ProgramCopy+SlotEditor.swift:227`, `:231`, `:235`. Not required by §7 (no value), cheap to add.
- **N-7. A program with no weeks is drawn as if every exercise were missing.**
  `DayEditor/DayEditorPresentation.swift:122`: stored exercises read "—". `Program.init` refuses such a
  program, so nothing reaches it but a test (`+Total.swift:136`); leave it, or split the guard so the name
  survives.
- **N-8. "HELD" on a slot that holds nothing.** `DayEditor/SlotEditorPresentation+Preview.swift:60-62` takes
  the Domain's `isHeld`, which is "the week before was missed" for every progression. A fixed slot then
  reads "W5 160 (held)" under "Stays at 160 lb for the whole block." The flag is the Domain's and spec §7.2's;
  a question for Pete with F24, not for this slice.
- **N-9. Every week's prescription is worked out for every slot on each `make`**
  (`DayEditorPresentation.swift:125-131`), though only the open slot's strip needs the block. About
  slots × weeks calls; far inside the 16 ms budget at 8 × 16. Leave unless S14's timing test says otherwise.
- **N-10. Two test names lack their expectation** (testing-strategy §6):
  `Tests/SlotEditorPresentationTests+Preview.swift:82` `weekStrip_kilograms`,
  `SlotEditorPresentationTests+Progression.swift:33` `progression_notes_kilograms`.
- **N-11. `Group.id` is optional** (`DayEditor/DayEditorModel.swift:62-64`) to avoid an unreachable branch.
  It works as an `Identifiable` id; a stored `let id: SlotID` set where the group is built
  (`DayEditorPresentation+Rows.swift:32`) would be plainer. Leave if it costs a branch.

### The bug pass (`/code-review`, effort high)

Run through the Skill tool on the range and the worktree path, told to run no `git checkout`, `switch`,
`reset`, `stash` or `commit`; afterwards the main checkout is on `main`, clean, with no stash, and this
worktree is on its branch.
It returned ten candidates. Kept: the superset's rest (S-1); the superset edit's dependence on order, which
I narrowed to the queue case (S-2); the no-weeks fold (N-7); HELD on a fixed slot (N-8); every week for
every slot (N-9); derived state (N-11). Not findings: steppers offered at their limit (the plan's behaviour
11, pinned); two taps from one model give one step (the cost of absolute edits, in "What the views and the
stores must be told"); the row's spoken value in drawn form (the plan's VoiceOver tree writes it so; S11's
pass); "REST" with two meanings (deviation 18, ruled below).

### The split: recommendation

**One pull request.** Its description must carry the line standards §10 asks for: 1,007 code lines, and the
split considered (the week strip and the delete confirmation, about 185).

- *Why one.* The figure is seven lines past "about 1,000", and 353 of the lines are copy lookups that are
  checked mechanically (I compared the 68 keys with the brief by script, and the gate compares catalog and
  code). The logic is 434 lines in five files, none over 161 lines, all pure, at 100 % line coverage, and
  it was reviewable in one sitting. The two halves test each other: a row embeds its panel, and the strip
  is how criteria 5 and 7 are read.
- *Cost of one.* A precedent a hair past the line, and a fix round that must not grow it: S-1 and S-3 add
  about twelve Domain lines and remove none here. If the fix round takes it past about 1,050, take the
  smaller seam then (the delete confirmation, about 60 lines, which nothing else reads).
- *Cost of two.* A second G1 to G5 cycle and a second paid CI run for 185 lines; no stacked pull requests,
  so the second waits for the first to merge; S10 and S11 need both before they draw, so nothing starts
  sooner; and the first half would ship a panel with no week line, which no criterion describes.
- *For the plan.* The overrun is the copy (353 against 260) and an action file the plan again did not list.
  Planning figures for a presentation slice should count about five lines a key and the action file.

### Verdict on each point

**The models as interfaces: sound.** A view is handed final strings, ids for `ForEach`, flags for accents,
and an action per control; I found no decision left to a view but two that are design's: which of `label`
and `spokenLabel` a stepper draws (Pete's decision 1), and what `hasDropSet` is for (N-5). The store fills
seven fields and applies four action cases, and `DayScreen.tap` (`Tests/Support/DayEditorTesting.swift:125-139`)
is that contract in fifteen lines. `.open` and `.openLibrary` storing nothing is right: both are screen
state, as `.selectWeek` is in the builder. **The store owns the open slot**, because the model is a function
of it (the panel is built for that slot alone); the view owns only whether the delete confirmation and the
library sheet are showing. `.dayIsGone` as a case, not an optional, is the right shape (standards §5).

**The actions: sound, with S-2.** `SlotEdit.applied` is one `DayEditing` call per case
(`DayEditorAction.swift:78-93`) and `DayEditorEdit.applied` one `ProgramEditing` call (`:41-50`): `renameDay`
and `deleteDay` are the Domain's own functions for those edits and `updateDay { DayEditing.… }` the rest,
which is the honest reading of criterion 1. All three are synchronous, non-throwing and hold only `Sendable`
values, so `programs.update(id) { edits.reduce($0) { $1.applied(to: $0) } }` compiles inside the `@Sendable`
closure of `Repositories.swift:61`. **The marks:** `move` is truly relative; `remove` is not (N-1). A wrong
mark on `remove` costs S13 and S14 nothing as specified, because every waiting edit is dropped after a
failed `update` whatever its mark; it would cost something only if a store gave marked edits a heavier path
(waiting for the write, disabling the control), which Remove would then take for no reason. **`closesPanel`
is a display fact**, the spec's (`docs/product-spec.md:247-248`), carried on the action so the store decides
nothing; it is not a rule of training. It is needed only for the two superset actions: after a removal or a
delete the open slot is read as none anyway.

**Numbers: correct.** Loads, steps and start loads go through `Weight.formatted(in:)`, RPE and rest through
their `label`; no `Double` (source test, and by reading). The strip is `ProgressionRules.prescriptions`
(`DayEditorPresentation.swift:125`), one entry a week, with "(deload)" and "(held)", a deload winning over
a hold as the prototype does (`Ledger.dc.html:1373`). The meta line counts the shown week's sets and minutes
(`:59-65`), and a slot without a stored exercise counts its own, as `TimeEstimate` does. Kilograms: the
equipment's step in the lifter's unit, kettlebell 2 kg, pinned. The one wrong number on screen is S-1.

**`Slot.resolvedStartLoad` / `resolvedStep`: correct.** `Sources/LedgerDomain/Model/Slot.swift:118`, `:124`
are the two fallbacks word for word; `ProgressionRules.swift:29-30` and `DayEditing+Fields.swift:70-71` call
them and nothing else changed there; no other copy of the pair is left in `Sources`. The only existing test
file the diff modifies is `FeatureProgramSourceTests.swift` (ten added lines); the Domain's suites pass
untouched.

**The words: as the brief.** Of the 44 texts "Copy (exact)" quotes for the Day editor, 34 are catalog keys
character for character (×, –, − included; compared by script); the other ten are joined lines or examples
("W8 240 (deload)", "4A"), present as their fragments under §7's rule of one counted value a key. The
confirmation's four texts, quoted in the builder's half of that paragraph, are keys too. Every key with two or more values has a translator's comment naming their
order. The two counted keys have `one` and `other`. Equipment (seven) and progression (three) names are this
catalog's own entries, one lookup a case. Splits and other languages: "%@, %@", "W%lld %@ (held)" and
"DAY %lld OF %lld" hold no counted value and can be reordered with positional specifiers; the fragments
"drop", "no rest", "%@ rest" and "rest after %@" are lower-case pieces of a " · " list, which a language
that capitalises nouns handles and one that needs agreement across the dot cannot, as with every joined line
in M1. "%lld%@" and "%lld×%lld" are keys with no word: harmless, and they carry the locale's digits.

**Purity and structure: sound.** Every new type is `nonisolated`; imports are Foundation and `LedgerDomain`;
no ambient read (the one formatter is given the injected locale,
`SlotEditorPresentation+Fields.swift:52`); the three source checks read the new folder (N-4). Largest file
241 lines, largest function about 25; no suppression; nothing reads as squeezed (the comments are full
sentences and the lookups one a line).

**Tests: good, with S-4.** They tap the model's controls and read the next model, as a store will; expected
strings are written out; criteria 7 to 11 of the brief each have a test that quotes it (the strip and reps
of rule 10, "W8 240 (deload)" and "WEEK 8 · DELOAD", HELD; the reps and top-of-range coupling and each
clamp; Double from 8 and 9 to 10 with the note; the three moves on [1, 2, 3A, 3B, 4]; "Superset with next"
and "Break out"). The properties check the model against the Domain on seeded days in both units and six
locales, with the limits drawn often; no sleeps, no clock. Coverage: the orchestrator's 1,306 of 1,306 was
not re-measured.

**Boundaries and the brief.** Nothing of a view or a store is in the diff; no `LedgerAppKit`, project file,
test plan or lint change. Criteria 1 to 10 each map to tests in the notes' table, and I found the tests
named.

**The "transient compiler error lines".** They were printed by `xcodebuild` on the simulator beside
`LedgerPersistenceTests`. On the host the package's tests build with exit 0 and no error or warning line,
but that build compiled only what was stale, so it neither reproduces nor explains them. Not settled here;
what would settle it is the same `build-for-testing` on a quiet machine with the log kept.

### Ruling recommendations: the deviations and the open questions

| # | Matter | Recommendation |
|---|---|---|
| D-3 | No calendar in the input | **Accept**, and amend criterion 1: the Day editor draws no date and no weekday; a field nothing reads would be dead. |
| D-7 | Both superset actions can show | **Accept.** It is the spec's rule (`docs/product-spec.md:247`): the last member of a superset that is not the day's last exercise has both. Criterion 4's "or" was loose. |
| D-9, Q7 | A slot whose exercise is missing: listed, movable, removable, not editable | **Accept for M1** (nothing deletes an exercise). Note for F12: sets, reps, RPE, rest, drop set and a double or fixed mark do not need the exercise; only the load, the step and the strip do. |
| D-11, Q2 | The set count summed in the feature | **Add the Domain function now** (S-3). A sum of the brief's formula is small, but which sets it sums is a rule the Domain already holds. |
| — | `ProgramPresentation` gained `nearestPlace` and a `prescriptions` parameter | **Accept.** `nearestPlace` is the three removed lines moved; the default `[:]` leaves the builder's cards on the slots' own numbers, and S5's tests (58 sets a week; 39, 38, 37, 31) still pin that and passed. |
| D-18, Q4 | "REST", "Rest", "Fixed", "Week %lld" used twice | "Fixed" and "Week %lld" mean one thing in both places: **fine**. "REST" and "Rest" mean a rest day and a rest between sets; a translation will want two words. **Ask Pete** for a second English text (for example "REST TIME") before the first translation, not before this merge. |
| D-5, Q1 | Is a removal relative? | **Rule that it is absolute** and change `DayEditorAction.swift:73`, two tests and criterion 10's wording; or keep the mark and say in the comment that it follows the criterion's list, not the definition. I prefer the first: a mark the suite itself shows to be untrue will be misread. Either way S-2's rewording stands. |
| D-4 | `closesPanel` on the action | **Accept** (a display fact from the spec). |
| D-10 | "Week 1 · No exercises yet" | **Accept**; for Pete below. |
| D-13, D-14, Q6 | One mark a week; "(held)" in the strip | **Accept** the first (the prototype's). Show Pete "(held)" with S11's screenshots, and N-8 with it. |
| D-16 | A stepper's number formatted, not looked up | **Accept**: the locale is the injected one. |
| D-19, Q5 | The row's spoken value and the strip to VoiceOver | **S11's VoiceOver pass decides both**; expect three or four more keys there ("+5/wk", "2:30", "W1 50" are drawn forms). |
| D-24, Q3 | Size | One pull request (above). |
| Q8 | What the library is handed | S8's input takes the program and the day's id, as the notes say. |

### For the product owner: the texts this slice wrote

| Text | Where | Judgement |
|---|---|---|
| "Delete day" | The button at the foot of the editor | Good; plain and parallel to "Delete" in the confirmation. |
| "It's scheduled in 1 week. Those days become rest." | The confirmation, for a day one week trains | Correct as a plural form. "Those days" reads oddly when it is one weekday in one week; the brief's sentence does the same. Consider "It becomes rest there." only if it bothers you. |
| "Day name" | The name field's placeholder and VoiceOver label | Good; matches "Program name". |
| "Kettlebell", "Band" | The sub line of such an exercise | Needed (the Domain has seven kinds). "Band" alone is thin; "Resistance band" is clearer if the row has room. |
| "W4 260 (held)" | The strip, a week after a missed one | Reasonable and parallel to "(deload)". See it on a screenshot before keeping it; see also N-8. |
| "4A, Lat Pulldown" | VoiceOver, a row's label | Good. |
| "Superset" | VoiceOver, a superset header's heading | Good. |
| "Sets", "Reps", "Rep floor", "Top of range", "Start load", "Target RPE" (and "Rest") | VoiceOver, each stepper; also what decision 1 would draw | Good. "Rest" is the word with two meanings (D-18). |
| "1 exercise back to back" | Never shown (a superset has two) | Only there because the catalog rule asks for a `one` form. |
| "Week 1 · No exercises yet" | The header of a day with no exercise | Fine; "Week 1" says little on an empty day, and dropping it there is one line if you prefer. |
| "%@ kg" and the kilogram form of each line with a load | Everywhere a load is printed in kilograms | The plan's row 17; the same sentences with "kg". |
| "1 min rest" on the last exercise of a superset | A row | The brief's wording, but the number can be wrong (S-1). |

### The seven review points

1. **Module boundaries:** pass. `FeatureProgram` imports Foundation and `LedgerDomain`; the Domain gains two functions on `Slot` and imports nothing new.
2. **Concurrency:** pass. Pure `nonisolated` `Sendable` values; no task, clock or id made here.
3. **Error handling:** pass. Nothing throws; an unknown day or slot changes nothing; a missing day is a case of the model.
4. **Design fidelity:** not applicable (no view). The model follows the prototype's lines, S-1 included.
5. **Accessibility:** spoken labels and values exist as copy for rows, headers and steppers; the strip and the row's value are drawn forms, left to S11 (D-19).
6. **Test quality:** pass with S-4, N-3, N-10. Behaviour through the model; seeded; no sleeps.
7. **Brief compliance:** pass. Criteria 1 to 10 each have tests; the deviations are recorded and ruled on above.

### What the views (S10, S11) and the stores (S14) must be told

- **Stores.** Every queued edit reaches the stored program exactly once, whatever `isRelative` says, and the
  edits just sent are dropped before the screen is redrawn from the stored program (S-2). Do not re-send
  after a failed or cancelled `update`.
- **Stores.** A stepper's edit carries a value worked out when the model was built. Apply each edit to the
  program on screen and rebuild the model before the next intent is handled; two taps taken from one model
  set one step, not two. That is a lost tap, never a wrong value.
- **Stores.** A stepper at its limit, and a rename to the stored name, give an edit that changes nothing.
  Compare `edit.applied(to: program)` with `program` and queue nothing when they are equal, so that no
  write is made for it.
- **Stores.** The open slot is the store's; it needs no repair after a move, a removal or a change from
  elsewhere. `closesPanel` is the only thing that clears it besides `.open(nil)`.
- **Stores.** The builder's edits (`ProgramBuilderEdit`) carry no `isRelative`; if S13 and S14 share a
  queue, do not branch on the mark.
- **Views.** Draw whole strings; never split `eyebrow`, `sub`, `strip.text` or `meta`, and never join
  entries. Colour from the flags only. Say what `hasDropSet` does or ask for its removal (N-5).
- **Views.** A stepper's VoiceOver adjustable action sends `increment` or `decrement` from the model on
  screen; the same one-model rule as above applies to repeated swipes.
- **Views.** "Expanded" and "collapsed" for a row have no text in the model. If the system trait does not
  say it, S11 needs two spoken keys.
- **Views.** A selected chip has no action: draw it selected and keep it in the radio group for VoiceOver.
- **Both.** Until S-1 is ruled, the rest on a superset's last row is that exercise's own.

### What I did not check

- The simulator, the full gate, the watch build and coverage: not run; the orchestrator's figures stand.
- A clean host build: mine was incremental, so the simulator's "transient error lines" are not explained.
- The tests after the tester's files appeared were run from binaries built before them; no later source of
  the committed slice differs, but nothing was rebuilt.
- S-2's example is from reading `DayEditing`, not from a run.
- The tester's files and findings: not read, as instructed.
- `docs/architecture.md` and `docs/testing-strategy.md` beyond §6: not re-read for this slice (no route, no
  view, no store, no migration); `docs/product-spec.md` only at `:236-248` and decision #7.
- The catalog's layout and order against `xcstringstool`: left to the gate's string-catalog step, which the
  orchestrator's run passed.
- The plural rule and word order in any language but English: by reasoning only.

## S10 — review, round 1 (G3 reviewer, 2026-10-10)

Reviewed: `git diff main..de60be7` on `feat/F11-s10-day-editor-views` (`b367052` the views, `de60be7` the
notes), the committed range only; the tester's uncommitted files were not read. Product paths are under
`LedgerKit/Sources/FeatureProgram/Views/`, test paths under `LedgerKit/Tests/FeatureProgramTests/`; line
numbers are those of `de60be7`. "The notes" is the implementer's section "S10 — the Day editor's views".
Nothing was built or run: every statement about behaviour is from reading the sources and the tests, and
every statement about the look is from the committed images, which I opened.

### Verdict: changes requested — one blocking item, small in code; the rest is approve with should-fix

The views are simple, read like the builder's, and hold no rule of their own. Criteria 1 to 10, 12 and 13
are met on the evidence. **Criterion 11 is not met, and by more than the notes say**: the day's name is cut
well below the accessibility sizes (B-1). The fix I recommend also answers the pinned header's height
(the notes' finding 2), and needs one line of ruling from the orchestrator because it changes what is
pinned. The stepper labels need a ruling too (S-1): the slice's criterion 7 and decision 1 A's own text say
different things.

### Blocking

**B-1. The day's name is cut from about `.xxLarge` on a 375 pt phone, not only "at accessibility sizes";
criterion 11 is not met.** `DayEditorHeader.swift:43-50`; the test that keeps it "known" is
`DayEditorLayoutTests.swift:147-160`.

- *Evidence, from the committed screenshots.* The ink of the name is 297 pt wide for "Upper A — Push focus"
  (`day-closed-dark-large.png`), 307 pt for "Lower A — Squat focus" (`day-superset-dark-large.png`), and
  312 pt for Upper A at `.xLarge` (`day-closed-dark-xLarge.png`: 1.05 times, as `.largeTitle` scales). The
  field's line is 375 − 2 × 26 = 323 pt on a 375 pt phone and 350 pt on an iPhone 17. So, **computed, not
  run**: "Lower A — Squat focus" is at the line's edge at `.xLarge` on 375 pt (322 to 323 pt) and cut at
  `.xxLarge`; "Upper A — Push focus" is cut at `.xxLarge` on 375 pt (about 328 pt) and at `.xxxLarge` or
  `.accessibility1` on an iPhone 17; Bold Text is wider still. These are the seed program's own names at
  ordinary text sizes. `day-openLinear-dark-accessibility3.png` shows the end state: "Upper A — Pus…".
- *Why the tests pass.* `words_areDrawnWhole` measures the header under the name "Arms"
  (`DayEditorLayoutTests.swift:59-61`), and `dayName_isCutInItsOneLineField` looks at two sizes only and
  expects the cut. The sweep that would have found the sizes in between was never pointed at a real name.
- *Why it blocks.* Criterion 11: "no word is cut … at the twelve text sizes on 375 and 402 pt". S9 accepted
  an ellipsis for an unusually long program name; here it is every seeded day's title on the screen whose
  purpose is to edit that day. It is the same class of defect as S9's "RE…".
- *The fix I recommend, one answer for B-1 and for the notes' finding 2.*
  1. **The name wraps while it is not being edited.** Keep the one-line `TextField` (a field with a vertical
     axis is a `UITextView`, which the hosted reader refuses: testing-strategy §2.6, F8-S2-8, and
     `ProgramViewsSourceTests` bans the spelling), and draw the name over it as a `Text` that wraps while the
     field has no focus. A sketch, not compiled:
     ```swift
     ZStack(alignment: .topLeading) {
         TextField(label, text: $draft)
             .ledgerFont(.title)
             .foregroundStyle(isEditing ? LedgerColor.ink : .clear)   // the Text below shows the name
             .submitLabel(.done)
             .focused($isEditing)
             .ledgerHitTarget(alignment: .leading)
             .onTapGesture { isEditing = true }
             .accessibilityLabel(label)
         if !isEditing {
             Text(draft)
                 .ledgerFont(.title)
                 .foregroundStyle(LedgerColor.ink)
                 .multilineTextAlignment(.leading)
                 .ledgerHitTarget(alignment: .leading)   // one line sits where the field's line sits
                 .allowsHitTesting(false)
                 .accessibilityHidden(true)
         }
     }
     ```
     The field stays the one accessibility element and the one `UITextField` (`DayEditorTextFieldTests`
     keep passing); an empty draft shows the placeholder as today; while editing, the name is one line that
     scrolls sideways, as every field. About ten lines more than today. No number, no new state.
  2. **Pin the row "Program … Done" only; the title block scrolls.** With a name that wraps, a header pinned
     whole grows: by my estimate one more title line from `.xxLarge` (about +40 pt), about 330 pt of 812 at
     `.accessibility3` and about 500 pt at `.accessibility5` (the notes measure 270 and 362 today with the
     name cut). That is too much to pin. So: `DayEditorBar(header:send:)`, pinned, is the two buttons;
     `DayEditorTitle` ("DAY 1 OF 4", the name, the tag and the summary line) is the first thing in
     `DayEditorPage`. The pinned part becomes about 68 pt at the default size and stays under about 100 pt
     at the largest (estimated from `PillButton`'s target and the `m` padding; to be measured). This is how
     the builder already stands: `ProgramHeader` scrolls with its page. Side effects, all good: the
     VoiceOver order on screen and in the plan agree without argument (bar: "Program", "Done"; page: the
     heading, the field, the line), `DayEditorParts` and the seven trees do not change, and the bar takes
     `Header` alone (deviation 3 shrinks to the title).
     **This changes the wording of criteria 2 and 4 ("pinned header") and the plan tree's "Pinned:" list,
     so the orchestrator rules before it is built.** If the ruling is to keep everything pinned, do step 1
     alone and move the summary line into the page (the notes' own option for finding 2); I do not
     recommend pinning a wrapped title with nothing moved.
  3. **Tests.** Delete `dayName_isCutInItsOneLineField`. Make `words_areDrawnWhole` measure the real title
     under each of the four seed day names (twelve sizes, two widths, plain and Bold Text), and the long day
     name with them; `ProgramScreenTests.dayEditor_headerIsPinnedAboveItsPage` then pins the bar's height
     (`scroll.frame.minY` between 44 and about 110 at `.large` and `.accessibility5`) in place of
     `> 150`. Re-record the references; add the title at `.accessibility3` to the screenshots.
- *Rejected alternatives.* A cap on the name's text size or a `minimumScaleFactor`: the name must shrink
  below the default size's ratio already at `.xxLarge` on 375 pt, so the cap would sit under the lifter's
  chosen size at ordinary settings. Lifting the reader's limit for a vertical field: a chore of its own
  (testing-strategy §2.6), not this slice's.

### Should fix

**S-1. The stepper labels: "Sets", not "SETS" (needs the orchestrator's one-line ruling).**
`SlotDetails.swift:56-62`. Decision 1 A, which the contract says "stays at its default A", reads
(implementation-notes, "Decisions for Pete", 1 A, *Labels*): "With one exercise open the old design shows ten
all-caps labels; the dark design allows six a screen. **The six field labels become "Sets", "Reps", "Top of
range", "Start load", "Target RPE", "Rest" in the small grey label style.**" Criterion 7 of this slice says
"drawn with `label`", which is the capitals. The two disagree; A's text is the product owner's decision and
`docs/product-decisions.md` #17 (at most six all-caps eyebrows a screen) is the rule behind it. As built,
an open double exercise shows ten lines in capitals ("DAY 1 OF 4", "WEEK 1", six fields, "PROGRESSION",
"SUPERSET"); with `spokenLabel` it shows four. By eye (`alternative-stepper-labels-dark-large.png` against
`day-openDouble-dark-large.png`) the capitals are also the wrong capitals: untracked `label` type, not the
eyebrow's. *Change:* `StepperField(field.spokenLabel, …)` and delete the then redundant
`.accessibilityLabel(field.spokenLabel)` (`:62`); re-record. `Field.label` then joins `hasDropSet` on the
list of fields to remove before F11 ends.

**S-2. The cut-word sweep is where the gate's time went; thin it without losing a check.**
`DayEditorLayoutTests.swift:103-136`. Counted from the parameters: `words_areDrawnWhole` is 12 sizes × 6
settings × 19 parts × 2 drawings = 2,736 hostings; `words_otherStates_areDrawnWhole` is 3 states × 4 sizes ×
6 settings × about 17 parts × 2 ≈ 2,450; `longExerciseName_isDrawnWhole` 12 × 6 × 5 × 2 = 720. About
5,900 hostings, twice the notes' "about 2,900", and half of them 2,400 pt wide. Beside that, the seven new
states add 84 cases to the S9 tester's `previews_layOutSoundly` and 7 × the settings to
`parts_layOutSanely`, which is the registry doing its job. In order:
  1. *No check lost:* the wide drawing does not depend on `setting.width`, yet `cut` draws it once per width
     (`:109-110`). Draw `whole` once per part, size, weight and direction: a quarter of all hostings gone.
  2. *No check lost in practice:* right to left mirrors a layout and breaks no line differently; sweep it at
     the four sizes of `words_otherStates…` and keep plain and Bold Text at all twelve.
  3. `words_otherStates_areDrawnWhole`: measure the open row and its panel's parts only; the closed rows of
     those days are the same view with other words of the same length, already swept twelve ways.
  Together about half. I did not time anything; the implementer's 832 s against 508 s on another lane is
  the only measurement, and the difference (about 320 s) is the size this count predicts at 50 ms a hosting.

**S-3. The name field's rule should be one view once B-1 lands.** `DayEditorHeader.swift:22-29, 43-50,
62-76` is `ProgramHeader.swift:19-27, 32-39, 41-56` with two names changed. Twenty copied lines were
defensible (deviation 2, below). With B-1's overlay it is about thirty-five lines of subtle behaviour, and
the builder's name has the same cut for a long name. *Change:* `NameField(label:name:onRename:)` in
`Views/NameField.swift`, holding the draft, the focus, the three `onChange` and the wrap; the Day editor's
title uses it now with `onRename: { send(.rename($0, day: model.id)) }`. `ProgramHeader` adopts it in the
same round only if the orchestrator accepts re-recording S9's long-name references; otherwise queue it. The
tester's pinned lists (`views_keepNoStateButTheDraft`, `views_sendOnlyTheModelsActions`) change by the
file's name only.

**S-4. The week's eyebrow re-spells the design system's `Eyebrow`.** `SlotDetails.swift:34-36` is
`Eyebrow.swift:22-24` written out (the `eyebrow` role, `accentText` or `inkMuted`). Criterion 13.
*Change:* `Eyebrow(week.eyebrow, tint: week.isDeload || week.isHeld ? .accent : .muted)`; the group's
`.accessibilityElement(children: .ignore)` (`:41`) already keeps `Eyebrow`'s heading trait out of the tree,
which `tree_isExactlyTheTable` confirms. `ProgramViewsSourceTests.dayEditorViews_tintOneThing` pins the new
line instead of the old.

### Notes (no change asked, or a line each)

- **N-1. `ControlPill` is both screens' now and still lives in `WeekSection.swift`**
  (`WeekSection.swift:31-58`); `dayEditorViews_standInViews` has to name that file as an exception. Its own
  file, `Views/ControlPill.swift`, when the tester's count of files is next touched. Same for `DayTag` in
  `DayCard.swift:82-98`, which reads `DayCard.tagEms`.
- **N-2. A draft or a flag that outlives its day.** `DayEditorHeader`'s `draft` and focus and
  `DeleteDayButton.isConfirming` are keyed by the view's place, not by the day. Nothing in this slice can
  show a second day in the same screen; S14 must either push a new screen per route or put
  `.id(model.id)` on `DayEditorScreen`. With the field focused and the model swapped under it, the next
  keystroke would rename the new day with the old draft. For S14's inputs.
- **N-3. The draft rule loses a keystroke under an asynchronous store** (same as S9's): type "X", delete it
  before the store has answered, and the second change equals the stale `header.name` and is not sent
  (`DayEditorHeader.swift:62-66`). The notes already require the store to apply `rename` synchronously;
  keep that sentence in S14's contract.
- **N-4. `ExerciseDisclosure` gates the panel twice** (`ExerciseRow.swift:21-23` and `:98-100`); harmless,
  `isOpen` and `panel != nil` are one fact. Leave.
- **N-5. The chosen progression chip** (`ProgressionChips.swift:16-23`): three modifiers to make a
  `PillButton` not a button. Correct and tested (the stop is text, selected, sends nothing). To VoiceOver a
  selected text among two buttons is less usual than "selected, button" on all three, which is what the
  plan's tree had; criterion 6 chose this. For the nightly UI test to hear, not to change.
- **N-6. `Program+Previews.swift:99`** replaces a list of cases by `default:`; the compiler no longer says
  when a builder case is added without its input. Debug only; leave or restore the list.
- **N-7. The caret** (`ExerciseRow.swift:41-43`): the chevron is not mirrored right to left
  (`LedgerIcon.swift:37`), so the quarter turn points down and up in both directions; the right-to-left
  reference shows it. Fine.
- **N-8. Standards.** No lint waiver, no `try!`, no `as!`, no unchecked sendability in the diff. Largest new
  product file 103 lines (`ExerciseRow.swift`), largest type 68. Comments are as dense as `ProgramHeader`'s
  and `DayCard`'s. No literal text in a view; the two `90`s are the only numbers. Names are plain, though
  `ExerciseGroup` and `ExerciseRow` say less than `DayExerciseRow` would beside `ExercisePickerRow`; leave.
- **N-9. Identity.** `ForEach` over `groups`, `rows`, `fields` and `chips` uses the model's ids, as the
  inputs say; the strip's entries and the superset actions use their place (`SlotPanel.swift:21, 51`), which
  the inputs allow for the strip and which is safe for two stateless pills.

### Criteria

| # | Verdict | Evidence, and whether the test is a real check |
|---|---|---|
| 1 | Met | No view imports more than SwiftUI and `LedgerDesign`; the only action built is `send(.rename(text, day: model.id))` (`DayEditorHeader.swift:64`); no literal, format, clock or locale. The source scans read the new files; `everyControl_sendsItsModelsAction_once` compares what each stop sends with the model, stop by stop: real. |
| 2 | Met as written | `DayEditorScreen.swift:17-25`. `screen_isOneScrollView`, `parts_holdNoScrollView`: real. `dayEditor_headerIsPinnedAboveItsPage` pins a third of the screen at `.accessibility3` on an iPhone 17 only; at `.accessibility5` on 375 pt the notes' own 362 of 812 is unpinned. B-1's second step replaces it. |
| 3 | Met | Eight files in `Views/`; `dayEditorViews_standInViews`. The scans were edited beyond "adding the new screen file" by their pinned counts and lists, each ruled below. |
| 4 | Met but for the name's cut (B-1) | Back, position, "Done", the field with the draft rule, the tag, the line. The two draft tests host the header and drive the real `UITextField`'s focus: real. Typing sends `rename`: not tested by any hosted test, pinned as a spelling only; owed by S14's UI test (accepted, as S9). |
| 5 | Met | Trees; `superset_rowsShareOneBlock`; `deleteDay_asksFirst` reads the presented `UIAlertController` and calls each button's handler: real, though through UIKit's private `handler` key, which an SDK may rename (the test would fail loudly, not pass). |
| 6 | Met | Drawn from `row.panel` alone (`ExerciseRow.swift:21-23`, `SlotPanel.swift`). `unstoredExercise_panelIsItsActions`, `oneExercise_andNone`: real. |
| 7 | Met as the criterion is written; see S-1 | One adjustable element, "Sets", "5"; down then up sends `decrement`, `increment`. |
| 8 | Met | One use of the accent in the eight files (`SlotDetails.swift:36`), by the two flags. The audit counts orange pixels per part in both themes and swaps the flags against the words: real, and the best test of the slice. |
| 9 | Met | Seven previews in the one registry; 24 references = 6 + 2 + 6 + 2 + 2 + 2, plus long names 2, right to left 1, Increase Contrast 1. |
| 10 | Met, within the reader's limit | Tree exact at two sizes for seven states; the row's state is UIKit's expanded status read in the test; targets 44 pt. The trees are a hand-written table, not a second derivation: the S10 tester's oracle is the independent check (below). Not heard in VoiceOver. |
| 11 | **Not met** | B-1. The rest of the sweep is real and well calibrated (`measure_seesACut` proves the measure both ways); it was aimed around the one element that fails. |
| 12 | Met | `everyControl_sendsItsModelsAction_once` over seven states and `seedDay_sendsTheBriefsActions` with literal expected edits: real. The name field and the alert's buttons are outside the walk and covered by their own tests. |
| 13 | Met but for S-4 | `ControlPill` generalised, not copied; `SectionNote` reused; nothing added to `LedgerDesign`. |

### The deviations (numbered as in the notes; the orchestrator's numbers in brackets where they differ)

1. **[3] The row and its panel are a `DisclosureGroup` with a style of its own: accept.** I know of no
   SwiftUI modifier that sets the expanded status; the honest alternatives are a word in the row's value
   ("expanded"), which the model does not carry and review S6 said would need two new keys, or UIKit. The
   claim that it holds no state is true: `isExpanded` is a binding built in `body` from `row.isOpen` whose
   setter ignores its argument and sends `row.action` (`ExerciseRow.swift:20`), so the group cannot open
   without the model. What it rests on is undocumented (a `Button` inside a `DisclosureGroupStyle` inherits
   the status); `rows_sayWhetherTheyAreOpen` and the trees fail the day that stops, which is the right
   guard. The nightly UI test must hear "expanded" once.
2. **[4] The draft rule copied from `ProgramHeader`, not shared: accept as committed; share it with B-1's
   fix (S-3).** The reason given (S13 may move the draft) argues for one place to change, not two.
3. **[5] `DayEditorHeader` takes the whole `Content`: accept.** Someone must hold the day's id and a view
   cannot spell its type. With B-1's split only the title needs it.
4. **[6] An alert, not a confirmation dialog: accept, with a note for the orchestrator.** Criterion 5 asks
   for "the confirmation", not for a dialog; the alert shows "Cancel", gives both buttons their roles, and
   the test reads both. But F10 met the same iOS 26 behaviour and kept its dialogs, with a cancelling button
   that has no role (`FeatureWorkout/WorkoutCover.swift:53-68`). The app now has two answers to one
   problem; choose one before M1 ends. I would keep the alert for "Delete …?" questions.
5. **[7] The superset's note under "SUPERSET", `SectionLine` unused: accept.** I looked:
   `alternative-stepper-labels-dark-large.png` has the note beside the eyebrow and it breaks after "· rest"
   at the default size on an iPhone 17. Under the eyebrow it is one line and the same at every size.
   Criterion 13 names `SectionLine` as available, not as required; `SectionNote` is reused.
6. **The strip drawn entry by entry: accept.** Each entry is a whole string; the spoken text is the
   model's; nothing is joined (`SlotPanel.swift:49-59`).
7. **[8] `row.sub` drawn, `row.hasDropSet` unused: accept; `hasDropSet` is a dead field, not a missing
   mark.** The prototype's row has no drop-set mark: its second line carries "· drop"
   (`design/prototype/Ledger.dc.html:1370`), which is `sub`, and `sub` is on the prototype's row
   (`:248-249`), so drawing it is criterion 5's omission, not an addition. Review S6 (N-5) already asked
   what `hasDropSet` is for. Remove it from the model in S14's clean-up; this slice may not change a
   presentation.
8. **Blocks `l` apart: accept; the look is Pete's.** By eye, the closing rule of one block and the opening
   rule of the next, 16 pt apart with nothing between, read as an empty row (`day-closed-dark-large.png`).
9. **No shared component added; the caret is the chevron turned: accept.** `chevronDown` in `LedgerDesign`
   is the right follow-up and removes both `90`s; queue it with `SectionLine`'s move.

The three differences from the plan's tree: (1) "Done" before the heading: accept, and it stops being a
difference with B-1's split; (2) the chosen chip is no button: accept, criterion 6 says so (N-5); (3) the
expanded status: deviation 1.

### The implementer's edits to earlier testers' files

| Edit | Verdict |
|---|---|
| `scan_readsEveryView` 14 → 22 | Mechanical. |
| `views_sendOnlyTheModelsActions`, ten lines added | Mechanical; each new line is a model's action or the one `rename`. The check is as strict as before. |
| `views_keepNoStateButTheDraft`: the header's draft and focus, `isConfirming`, three more `.onChange` | Accept. `isConfirming` is a new kind of state, which the inputs ask for ("whether it is showing is the view's own flag"). The test's name, "no state but the draft", is now untrue: rename it. |
| `views_readOnlyTheTextSize` 2 → 4 | Mechanical; the set is still the text size alone. |
| `views_numbers_areTheTwo`: `ExerciseRow.swift: 90` twice | Accept, not mechanical: it admits a new number. It is an angle, not layout arithmetic, and the regular expression still catches any other. The title ("the tag's width … and the strip cell's one line") is stale: say three things, and drop the `90`s when `chevronDown` exists. |
| `registry_holdsTheNamedStates`, seven names | Mechanical. |
| `tables_areTheOraclesTrees`: `allCases` → `builders + libraries`, and `throw` for `.dayEditor` | Accept; it does not weaken S9's check. The eight states are still compared, `PreviewTests.cases_areSplitBetweenTheThreeScreens` forces a new builder or library state into those lists, and the `throw` fails the test if a Day editor state ever reaches it. What it leaves open is the Day editor: its trees have no second derivation. **For the S10 tester:** write the oracle's `.dayEditor` arm from the model and put `allCases` back. |

### For the product owner

1. **The day's name** (B-1): today it ends in "…" from two sizes above the default on a small phone. The
   proposal: the name breaks onto a second line instead, and only the "Program" and "Done" row stays fixed
   while the name and the summary scroll away with the exercises.
2. **"SETS" or "Sets"** (S-1): your decision 1 A says "Sets". The slice drew "SETS". Both are in the
   screenshots (`alternative-stepper-labels-*.png`). I recommend "Sets".
3. **The looks the notes list** (ten, all in `screenshots/s10/`). Two I would look at first: the empty band
   between two exercises (deviation 8), and "Remove" looking exactly like "Move down" beside it.
4. **"Program" and "Done" do the same thing** (both close the day; the model's since S6). If "Done" is to
   stay, it is one control more than the screen needs.
5. **Alert or dialog** for a destructive question, app-wide (deviation 4).

### What I looked at by eye

All of `screenshots/s10/` at the level of the whole page for: closed dark large, open linear light large,
superset dark large, open linear dark accessibility3 (whole page and the header enlarged), long names dark
large and accessibility3 (header and last rows enlarged), right to left (both halves enlarged), deload week
light (top enlarged), drop set dark (panel enlarged), Increase Contrast (top enlarged), both
`alternative-stepper-labels` images in part. Found by eye: the cut name (and from it, by measuring the
images, the sizes in B-1); the capitals' weight (S-1); the empty band (deviation 8); nothing overlapping,
nothing else cut, the carets right in both directions, the orange only on "WEEK 8 · DELOAD". The references
under `__Snapshots__/DayEditorSnapshotTests/` were not opened one by one: the notes say the screenshots are
copies of them, and I did not compare the bytes.

### What I did not verify

- Nothing was compiled or run: no host build, no simulator, no gate. The sketch in B-1 is not compiled.
- B-1's sizes are computed from three screenshots and `.largeTitle`'s scale, not measured in a hosted test;
  the first cut may be one size earlier or later than stated, and Bold Text was not measured at all.
- The header heights after the fix are estimates.
- S-2's count is of hostings, from the parameters; no time was measured.
- That VoiceOver says "expanded" and "collapsed", and how it reads a selected text among buttons.
- The 375 pt width by eye: every image is 402 pt wide.
- The coverage figure, the lint run and the string catalogs: the notes' figures stand.
- The tester's uncommitted files and findings: not read.

## S10 — review, round 2 (G3 reviewer, 2026-10-11)

Reviewed: `git diff 454bcc4..4d22ec9` (`fe10b4b` the code, `4d22ec9` the notes) against round 1's items and
rulings 14 to 20. The committed range only; the tester's working files were not read. Line numbers are those
of `4d22ec9`. Nothing was built or run. The images were read from the commit (`git archive`), opened, and
three of them measured row by row; the numbers below are pixel rows of 1× images, so points.

### Verdict: changes requested — one blocking item of one line; two should-fix of one line each

Every round-1 item is resolved as ruled. `NameField` is correct in its rule, its accessibility and its
focus behaviour, and close to as simple as it can be. What is left is where the new, taller name meets the
row under it (B-2), found by measuring the references, and two smaller things the references show or the
code implies (S-5, S-6).

### Round 1's items

| Item | Verdict |
|---|---|
| **B-1** the name cut | **Resolved.** The name wraps (`NameField.swift:42-50`); by eye at `.large`, `.xLarge`, `.accessibility3` and for the long name at both sizes. The sweep now weighs `NameField` alone under the four seed names and the long one at twelve sizes, two widths, plain and bold (`DayEditorLayoutTests.swift:89-97, 168-176`). The pinned bar is 60 to 70 pt. |
| **S-1** "Sets" | **Resolved** (`SlotDetails.swift:54-59`); the redundant label went; by eye in five images. |
| **S-2** the sweep | **Resolved**; below. |
| **S-3** one `NameField` | **Resolved for the Day editor; the builder queued, as ruled.** I see no reason against the chore: the ruling's own fallback fired on evidence (every S9 reference moves). Two conditions: do it before S13 touches `ProgramHeader`, so the rule is not edited in two places, and after B-2 and S-6 below, so S9's twenty references are recorded once. Until then `NameField.swift:4-5` ("the program's name on the builder") says more than is true; one clause. |
| **S-4** `Eyebrow` | **Resolved** (`SlotDetails.swift:33`); the source test pins the new line and now looks for any `.accent`. |

### Blocking

**B-2. A wrapped name's descender reaches into the tag's pill under it.** `NameField.swift:42-59` with
`DayEditorHeader.swift:19` (the `xs` spacing).

- *Measured in the committed images.* The title's lines are about 0.98 of its size apart, so the text's
  frame ends above its descenders. In `day-closed-dark-accessibility3.png` the first line's baseline is row
  138 and the "pp" of "Upper" hangs to row 146: eight rows. The last line's baseline is row 186 and the
  "UA" pill starts at row 191: four rows of ground. In `day-longNames-dark-large.png` the last baseline is
  row 173 and the pill starts at row 178, with a descender of five rows at that size (rows 110 to 114 under
  baseline 109 in `day-closed-dark-large.png`).
- *So, from those numbers, not seen:* any name whose last line holds a g, j, p, q or y puts that letter's
  tail on the pill: by about 4 pt at `.accessibility3`, and touching it at the default size once the name
  has two lines. "Lower A — Squat focus" and "Lower B — Hinge focus" are two of the four seed days, and
  they wrap as Upper A does ("… —" over "Squat focus"), from `.xxLarge` on a 375 pt phone. No reference
  shows it only because the registry's wrapped names end in "Push focus" and "block".
- *Why no test sees it.* The frames do not overlap (the ink leaves its frame); both views are hidden from
  the reader; and the ink measure weighs the same with a tail on a pill.
- *Why it did not exist in round 0.* One line of 31 pt stood in the middle of a 44 pt target, 6 pt clear
  either side. Top-aligned and wrapped, a name taller than 44 pt has only the stack's 4 pt under it.
- *Fix, one line:* `.padding(.bottom, LedgerSpacing.s)` on the `Text`, before `.overlay`
  (`NameField.swift:50`). Inside the 44 pt target it costs a one-line name nothing at the default size
  (31 + 8 < 44), so only the wrapped references move; a wrapped name gets 12 pt to the pill against a tail
  of 8 at `.accessibility3` and 9 at `.accessibility5`. *Check:* draw `DayEditorHeader` under "Lower A —
  Squat focus" at `.xxLarge` on 375 pt and at `.accessibility3`, and expect no row to hold both the name's
  ink and the pill's fill; or add that day at `.accessibility3` to the references and look.

### Should fix

**S-5. The references draw the bar squeezed at `.accessibility3`; the screen does not.**
`Support/ProgramParts.swift:59-62` against `DayEditorScreen.swift:19-20`. In
`day-closed-dark-accessibility3.png` the "Done" pill's outline is at rows 2 and 47: 2 pt above it and 2
under, a bar of 49 pt, where the notes measure 61.3 pt on the screen and the padding is 8. `DayEditorParts`
stacks the bar without the `.fixedSize(horizontal: false, vertical: true)` the screen gives it, so the six
references and the trees' frames at accessibility sizes are of a bar the app never draws. *Change:* move the
modifier from the screen into `DayEditorBar.body` (`DayEditorBar.swift:18`), so that the bar keeps its
height wherever it stands, and record the accessibility references again. I did not measure whether the
squeeze is the stack's or the snapshot host's; the image is the evidence.

**S-6. An emptied name at accessibility sizes (by reading; not run).** `NameField.swift:42-59`. With the
draft empty the base `Text` has no line, so the view is its 44 pt minimum, while the field over it is one
title line: about 59 pt at `.accessibility3` and 70 pt at `.accessibility5`. The lifter who clears the name
to type another has the placeholder and the caret hanging 15 to 26 pt over the tag and the summary line, and
the rows under it jump up and back at the first letter. Below `.accessibility1` the line is under 44 pt and
nothing shows. *Change:* let the base text be the placeholder when the draft is empty, in clear:
`Text(draft.isEmpty ? label : draft)` with `.foregroundStyle(isEditing || draft.isEmpty ? .clear : ink)`.
One line of the title's height is then always there. *Check:* host `NameField(label:name: "")` at
`.accessibility3` over a spacer and expect the field's frame inside the view's. If the hosted measurement
says an empty `Text` keeps a line's height, drop this item.

### `NameField`, the questions asked

- **Correct and simple?** Yes, with B-2 and S-6. Twenty lines of body, no number, the two pieces of state
  round 0 had. `fixedSize(horizontal: isEditing, …)` with `frame(minWidth: 0, …)` (`:48-49`) is the least
  obvious part; `lineLimit` would say it more plainly but brings a number into a view. Keep.
- **Accessibility.** One element: the `UITextField`, labelled, its value the draft whatever colour it is
  drawn in. The text is hidden (`:50`), and `nameField_isNotReadByTheHostedReader` now also expects no stop
  holding "Upper A", which is the right guard against the name being read twice.
- **Hit testing.** Ruling 15 says the text is "hidden from hit testing"; the code does not disable it, and
  should not: the text has no gesture, the field covers its first line, and the further lines fall to the
  container's tap (`:59-61`), which is what focuses the field from there. The notes' sentence is loose, the
  behaviour right. A finger on the second line is unverified, as the notes say.
- **The placeholder** is the field's own and is not affected by the clear foreground; reached only while
  focused (the store keeps no blank name). See S-6 for its room.
- **The draft rule** is round 0's, line for line (`:62-76` against `ProgramHeader.swift:41-56`), with
  `onRename` for `send`. The two draft tests pass on it unedited, by the notes.
- **The 0.7 to 1.0 pt rise on focus: acceptable.** Two or three device pixels, vertical only, at the moment
  a caret appears and the lines under the name move anyway. Closing it takes a literal in a view. I checked
  the other direction in the images: the name's ink is 297 and 307 pt wide, exactly round 0's field, so the
  tracking is the same in both drawings and nothing shifts sideways.
- **Top-aligned in its target: acceptable**, and the cause of B-2. By eye the title sits a little closer to
  "DAY 1 OF 4" and reads as one block with it.
- **`Color.clear`:** accept. It is the absence of a colour, not a rule of the feature's own.

### The split

Clean. `DayEditorBar` takes `Header` alone; `DayEditorHeader` is the title block and still takes `Content`
for the id. Left over from the old shape, all comments: "the pinned header over the page" in
`DayEditorAccessibilityTests.swift:15` and `DayEditorSnapshotTests.swift:8` (the implementer's files), and
the tester's own titles. `DayEditorPage.swift:16-24`: the header pads itself and an inner stack exists only
to pad the rest; one padding on the page and none on the header would be three lines fewer, but the tests
host the header alone at the screen's inset. Leave. The trees did not change (the first two stops from the
bar, the next two from the page); `dayEditor_barIsPinnedAboveItsPage` pins 44 to 110 pt at `.large` and
`.accessibility5` with a literal 62 for the window's inset, commented.

### The tester's files

All ruling-forced and no wider: `page_showsAtLeastTwoRows`' known-issue cells narrowed (ruling 14, the
expectation untouched); `stepper_drawsTheLabel` and `DayViewsText.place(of:)` flipped to the spoken label
(ruling 17); in `ProgramViewsSourceAdversarialTests` the count 22 → 24 and the same sends, state and
`onChange` lines under their new file names. The notes count these as six edits in four files; that is
what the diff holds. Stale titles ("draws the label", "the pinned header") are the tester's to change.
`seedNames_aboveTheDefaultSize_areDrawnWhole` now measures a field whose text is not drawn: the tester
re-points or deletes it, as the notes say.

### The thinned sweep

No check is lost. The wide drawing once per part, size, weight and direction; right to left at four sizes
on the fullest page; the other states' open parts only; the closed rows of those states were the same view.
The 1,200 pt wide drawing is narrower than the long day name at the larger ordinary sizes (about 1,050 pt
at `.large`), so that name wraps in its "whole" drawing too; harmless, since both drawings hold every
letter, but the comment at `:40-41` names the wrong longest line.

`measure_seesACut` (`:199-211`) is a real proof for round 1's case: "Lower A — Squat focus" on one line at
`.xLarge` on 375 pt must fail the band, and the same name at `.xSmall` must pass. It is made with a `Text`
of one line, not with the old field, which draws the same ellipsis. Its limit, to keep known: the band is
6 % and a seed name is twenty letters, so one lost letter would pass. Nothing in the new view can lose
one (the text has no line limit), so I ask for no change.

### By eye

Enlarged, from the commit: closed dark `.large` beside `before-round1-capital-labels-pinned-header`; closed
dark `.accessibility3` (top); long names dark `.large` and `.accessibility3` (top); right to left (top
half); open linear light `.accessibility3` (top and the steppers); open double dark `.large` (the panel);
closed light `.xLarge` (top). Good: the title block in the page, the name whole on two, three and six
lines, "Sets", "Rep floor", "Top of range" in the small grey style, the mirror image. Odd: the wrapped
name's last line stands close on the pill (B-2); the "Done" pill touches the top of the picture at
`.accessibility3` (S-5). Nothing cut, nothing else overlapping. Not opened this round: the deload, drop
set, superset and Increase Contrast images, and the 24 files under `__Snapshots__` one by one.

### Not verified

- Nothing compiled or run. B-2's overlap is arithmetic on measured rows, not a picture of "Squat focus"
  wrapped; S-6 rests on an empty `Text` having no height, which I did not measure; S-5's cause is not
  established, only its effect in the image.
- The focus itself: the caret, the one line scrolling, a real keyboard, a tap on a wrapped line, VoiceOver.
- The notes' timings and gate figures (47 s, 372 s, 826 s) and the rows-under-the-bar table.
- That `__Snapshots__` and `screenshots/s10/` hold the same pictures.

## S10 — review, round 3 (G3 reviewer, 2026-10-11)

Reviewed: `git diff b4f1ce0..412033e` (the tester's round 2 `89e878b`, the fix `92a66af`, the notes
`412033e`) against round 2's items and rulings 21 to 26. The product change is seven lines in three files.
Nothing was built or run; the images were read from the commit and two of them measured by row.

### Verdict: approved

| Round 2 item | Verdict |
|---|---|
| **B-2** the name's tails on the tag | **Closed.** `DayEditorHeader.swift:22-24`: `s` under the name, a token, outside the field. Measured in the re-recorded images: at `.accessibility3` the last baseline is row 186 and the pill starts at row 199, twelve rows of ground against a tail of eight (it was four); for the long name at `.large`, baseline 173 and pill 186, twelve against five. The placement outside `NameField` is the better one, not only the one that kept the tester's tests green: the field's frame stays the name's own, and the room is the title block's to give. At `.accessibility5` 12 pt against the tester's 10.3 pt tail is 1.7 pt clear: enough, and `name_standsAboveTheTag` holds it at twelve sizes, plain and bold. When `ProgramHeader` takes `NameField` it needs the same room over whatever stands under it. |
| **S-5** the bar squeezed | **Withdrawn; I misread the image.** The bar is 61 pt in the reference too: "DAY 1 OF 4" starts where a 61 pt bar puts it. Removing the screen's `.fixedSize` is right. What I saw is still in `day-closed-dark-accessibility3.png` and is something else; note 1. |
| **S-6** an emptied name | **Closed, refuted by measurement** (2.3 to 2.7 pt, inside the gap). My premise that an empty text has no height was wrong. |
| Stale comments (ruling 25) | Closed: the four places read true now. |

### On the deferral of F11-S10-5 (ruling 22): agreed

Under the focus the field cuts the tails of its one line. It is not this slice's doing and not this slice's
to mend: `ProgramHeader` on `main` cuts the same way, the frame is the title role's line height, and a view
cannot raise it without a number of its own. One chore then carries three things that must land together:
the role's variant for a field, `ProgramHeader` on `NameField` (with the room B-2 needed), and S9's twenty
references. Two conditions: the tester's known issue names that chore, and the chore lands before S14 puts
the Day editor in the app, since that is when a lifter first types in this field.

### Notes (none blocks)

1. **"Done" at `.accessibility3`.** In `day-closed-dark-accessibility3.png` the pill's outline is at rows 2
   and 47 while its word's ink is rows 19 to 38: the outline stands 2 pt from the top of the picture, where
   the bar's padding is 8, and about 6 pt high of its word. At `.large` it is centred. The bar's height is
   not in doubt (above); this is how `PillButton` draws at an accessibility size, or how the reference crops,
   and I could not tell which by reading. One measurement by the tester (the pill's outline against the
   bar's frame at `.accessibility3`) would say; if it is the pill, it belongs in the same design-system
   chore as the title's line height.
2. **The default size is looser under the name now**: a one-line name has its 12 pt of slack in the target
   and the new 8 pt, so the tag stands about 20 pt under the baseline's tails, against 4 pt between
   "DAY 1 OF 4" and the name. By eye it reads as intended spacing, not as a fault; for the product owner
   with the other looks.

### By eye

From `412033e`: closed dark `.accessibility3` (top), superset light `.large` ("Lower A — Squat focus", one
line, the q well clear of "LA"), right to left dark `.large` (top), long names dark `.large` (three lines,
clear of "UA"). No committed image holds "Squat focus" or "Hinge focus" wrapped; that case rests on the
tester's `name_standsAboveTheTag`. Nothing cut, nothing overlapping, nothing odd from the 8 pt move but
note 2.

### Not verified

Nothing compiled or run; the tester's figures (the bar's heights, the tails, the emptied draft) are taken
from `test-findings.md`, not re-measured; the tester's new test files were read by their names and
findings only; the cause of note 1.

## Slice S13 — review (G3 reviewer, 2026-10-18)

Reviewer pass on `feat/F11-s13-stores` at `1b0c07a` (`git diff origin/main...1b0c07a`). Every product file read in
full, with the implementer's tests and the sanctioned edits to testers' files; compared with `TodayStore`/`TodayRoot`,
`WorkoutStore+Pump` and `GRDBProgramRepository.update`. Committed by the orchestrator (the reviewer was read-only).

### Verdict

**Approve**, with three should-fix items. Blocking 0 · Should fix 3 · Nit 8.

What holds: the save loop drops exactly what it sent (`sent` taken before `prepare`; `waiting` only grows while
writing); R1, R4, R7 and amended R6 as ruled; a run started while an old write is in flight is woken by that
write's `defer`; Swift 6 isolation clean, no unstructured task; 474 product lines recounted; conventions hold;
no smaller design found for criteria 1–6.

### Should fix

1. `ProgramStore+Sources.swift:90` (with `ProgramStore.swift:59-60`): one `hasFailed` flag serves both a failed
   read and an ended observation, so a later successful logged-weeks read clears an ended observation's failed
   state within the run (the builder is drawn over a dead observation). Keep a per-run "ended" flag a read cannot
   clear, as Today's `sources.hasEnded`; keep deviation 8's cross-run behaviour.
2. `ProgramRoot.swift:52-54`: `run()` is not restarted on a return from the background, so the failed copy's
   "Open the app again to try once more" is false. Key `run()` on the scene phase as `TodayRoot` does; keep
   `save()` unkeyed so backgrounding never cancels a write. May land with S14 if written down as S14's.
3. `ProgramEditSession.swift:151`: after a write that heard an emission, a successful read naming another program
   or none is discarded for the returned program (same as G2's F11-S13-7 and -8). Adopt whatever a successful read
   returns; `adopt` already drops edits made on another program.

### Nit

1. `ProgramStore.swift:153-160`: `routeAfterSave` is never cleared if `adopt` drops the waiting new-day edit, so
   "+ Add training day" stops working for the store's life.
2. `ProgramStore+Sources.swift:18,73`: `followedWorkouts = 1` does not observe a non-newest workout deleted or
   edited in History; logged weeks stay stale for the run (errs safe). Say so in the type's comment.
3. Notes, "How it works", sentence 3, and deviation 5 still describe the pre-fix behaviour.
4. The R6 amendment was written in the implementer's commit; the orchestrator should confirm it.
5. `implementersTripwire_missesTwoSpellings`: the identifier says the opposite of what it now asserts.
6. `ProgramEditSessionTests.losingSequence` and the `again` tasks in `+Cancellation` are cancelled without being
   awaited; use `Running.cancel()`.
7. On GRDB a write's own emission can arrive before `update` returns, so the post-write read may run after many
   writes; the notes should not call it rare.
8. `ProgramStore.swift:56-60`: say in a comment why four properties are module-writable.

### For S14's wiring

The public API fits. Pin with UI tests: whether `onChange(of: week, initial: true)` fires again when the root
reappears (a stale request overriding the lifter's selection), and that the builder's waiting edits are re-sent on
return from a pushed Day editor (R5).

### What I did not check

`swift test` (a tester's untracked file was in the tree), any simulator run, the adversarial suites line by line,
`onChange(initial:)` on reappearance, how often GRDB emits before `update` returns, the by-hand budgets, the
in-memory `update`'s `CancellationError` after a released hold, and criteria 15–25.

## Slice S13 — review round 2 (G3 reviewer, 2026-10-18)

Pass on `git diff 1b0c07a..60ff64e` (fix round 2, notes, testers' rounds 2–3, re-amended R6). Host
`swift test --filter FeatureProgramTests` at `60ff64e`: 447 tests in 49 suites passed (200 seeds). Committed by the
orchestrator.

**Verdict: approve.** Blocking 0 · Should fix 0 · Nit 3. S-1, S-2, S-3 and N-1 to N-8 resolved as ruled; the fixes
introduce no new defect (re-read with cancellation and a later throw; `adopt(nil)` then a stored write; a new run's
`hasEnded` reset racing an old run's end; a builder created in the background).

Nits, carried to S14 by the orchestrator: (1) `ProgramEditSession.swift:157-158` a later read that throws could return
the last successful read instead of `saved` (F11-S13-10); (2) `:152` the re-read loop has no bound (F11-S13-11),
unreachable in M1, cap it if sync ever writes continuously; (3) `ProgramRootTests.root_backFromTheBackground_
followsAgain` waits on a counter Observation cannot see and may hang if an equal value does not notify. F11-S13-12
(a card tapped during "+ Add training day"'s write drops the day's route): a note for S14.

Not checked: the iOS-only root suites (relied on the full gates at `c29faa5` and `a8c1035`), any simulator run,
the round 2–3 adversarial bodies, `@Observable`'s equal-value behaviour, S14.
