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
