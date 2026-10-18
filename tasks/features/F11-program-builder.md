# F11 — Program builder, Day editor, Exercise picker

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F02, F03, F05, F06, F07 |
| Branch | `feat/F11-program-builder` |
| Design refs | `design/prototype/Ledger.dc.html` → screen labels: `Program builder`, `Day editor` (incl. Exercise library sheet); `design/prototype/Ledger v2.dc.html` → visual system only (no builder designed) |
| Spec refs | `docs/product-spec.md` §3.2, §3.4, §7.1 (rules 1–8), §7.2 (preview), §7.7 rules 37, 39, 44; `docs/product-decisions.md` #1, #3, #9, #14, #17, #18, #19 |

## Goal
The lifter can write and reshape a block at home: how many weeks, which day lands on which weekday each week, which weeks are deloads, and — per training day — every exercise's sets, reps, RPE, rest, start load, progression, superset and drop-set flags, with the prescription for every week visible before the gym. Move up/down finally respects superset grouping.

## User stories
- As a lifter, I can add/remove weeks and assign days to weekdays per week so that my calendar matches my life.
- As a lifter, I can edit a slot's prescription within safe ranges and see "W1 185 · W2 190 …" so that I know what each week will ask of me.
- As a lifter, I can chain two exercises into a superset or add a drop set so that my day matches how I actually train.
- As a lifter, I can search a large catalog by name, muscle and equipment and add several exercises at once.

## Scope
**In:** `ProgramRoot` (builder), `DayEditorView`, `ExercisePickerSheet`; block weeks (min 2, +/−, deload toggle, copy previous, apply to later); schedule strip cycling (rule 5); training-day cards with meta; add/rename/delete day; slot editor with steppers, progression picker + notes, drop set, superset actions, group-aware move up/down, remove; per-week prescription preview; validation messages; program rename; edits persisted immediately.
**Out (explicitly):** Settings entry (gear moved to Today — F14, decision #19), custom exercise creation (F12; picker shows custom exercises via live query), block-level prescription table and "Start next block" (F24), multiple programs (post-launch), per-set schemes (spec §9).

## Touches
- `LedgerKit/Sources/FeatureProgram/ProgramRoot.swift`, `ProgramStore.swift`, `ProgramRoute.swift`, `ProgramPresentation.swift`
- `LedgerKit/Sources/FeatureProgram/Views/BlockHeader.swift`, `WeekChips.swift`, `ScheduleStrip.swift`, `WeekActions.swift`, `DayCard.swift`
- `LedgerKit/Sources/FeatureProgram/DayEditor/DayEditorView.swift`, `DayEditorStore.swift`, `SlotCard.swift`, `SlotFields.swift`, `ProgressionPicker.swift`, `WeekPreviewStrip.swift`
- `LedgerKit/Sources/FeatureProgram/Picker/ExercisePickerSheet.swift`, `ExercisePickerStore.swift`, `FilterChips.swift`
- `LedgerKit/Sources/FeatureProgram/Resources/Localizable.xcstrings`
- `LedgerKit/Sources/LedgerDomain/Programs/ProgramEditing.swift` (new pure editing functions, see below)
- `LedgerKit/Tests/LedgerDomainTests/ProgramEditingTests.swift`
- `LedgerKit/Tests/FeatureProgramTests/ProgramStoreTests.swift`, `DayEditorStoreTests.swift`, `ExercisePickerStoreTests.swift`, `ProgramSnapshotTests.swift`
- `Apps/Ledger/Sources/Navigation/ProgramDestinations.swift` (F07-owned; add `.day(DayTemplateID)`)

## Domain changes
Pure editing in `LedgerDomain` (all return a new `Program`; every rule from spec §7.1 enforced here, not in views):
```swift
public enum ProgramEditing {
    public static func addWeek(_ p: Program) -> Program                       // copies last week's schedule, isDeload=false
    public static func removeLastWeek(_ p: Program) throws(ProgramEditError) -> Program   // .minimumTwoWeeks
    public static func cycleSchedule(_ p: Program, week: Int, weekday: Weekday) -> Program // rest→day1→…→dayN→rest
    public static func copyPreviousWeek / applyToLaterWeeks / toggleDeload(...)
    public static func addDay(_ p: Program, ids: () -> UUID) -> Program         // "New day", tag "D{n}", no slots
    public static func deleteDay(_ p: Program, day: DayTemplateID) -> Program   // schedule refs → rest
    public static func addSlots(_ p: Program, day: DayTemplateID, exercises: [Exercise], defaultRest: Duration, ids:) -> Program // rule 7
    public static func set(_ field: SlotField, _ value: Int|Decimal, slot: SlotID, in p: Program) -> Program  // clamps + repsHi coupling
    public static func setProgression(...)                                     // double: repsHi = max(repsHi, reps + 2)
    public static func toggleSuperset(_ p: Program, slot: SlotID, on: Bool) -> Program
    public static func move(_ p: Program, slot: SlotID, direction: .up | .down) -> Program   // group-aware, below
    public static func weekLoads(_ p: Program, slot: SlotID) -> [Prescription]  // via ProgressionRules for every week
}
public enum ProgramEditError: Error { case minimumTwoWeeks, weekHasLoggedSessions(Int), dayHasNoExercises }
```
**Names:** a program name, a day name and a day tag the lifter types refuse control characters (Unicode `Cc`, which includes U+0000) before `programRepository.save`: F05 refuses U+0000 as `nulInText`, an error a Feature cannot match (F05 S2 review N-a).
**Group-aware move (fixes the v1 gap):** blocks = maximal runs where `isSupersetWithPrevious == true` joins the previous slot. If the slot and its neighbour in the move direction are in the same block, swap them inside the block (letters recompute). Otherwise the whole block moves past the neighbouring block as a unit. Superset flags are recomputed so the first slot of every block has `isSupersetWithPrevious == false`.
Builder meta uses `TimeEstimate.minutes` (decision #14) and `Σ(sets + dropSets)` for set counts. Deload preview uses `ProgressionRules` (decision #3: ×0.85 rounded to the slot's unit step). Removing the last week throws `.weekHasLoggedSessions(n)` if a finished workout has `source.weekIndex == last`.
`ProgramRoute`: `.day(DayTemplateID)`. Loads display in `Settings.units` with per-unit steps (lb 5 / 2.5, kg 2.5 / 1.25; kettlebell 5 lb / 2 kg, decision #22); `Slot.step == nil` resolves to the equipment default for the current unit.

**Copy (exact):** eyebrow "MY PROGRAM", title = program name (tap to rename; placeholder "Program name"); "BLOCK · %lld WEEKS"; chips "W%lld" + "%lld DAYS" / "DELOAD"; "WEEK %lld" / "WEEK %lld · DELOAD"; hint "Tap to assign"; weekday letters per `Settings.weekStart`; slot "REST" or tag; buttons "First week" / "Copy week %lld", "Apply to later weeks", "Deload"; "TRAINING DAYS" + "%lld days · %lld sets a week"; helper "Shared by every week. The schedule above decides which day you train, and when."; card meta "%lld exercises · %lld sets · ~%lld min" or "No exercises yet"; chips of short names + "+%lld"; "+ Add training day"; delete confirm "Delete %@?" / "It's scheduled in %lld weeks. Those days become rest." / "Delete" / "Cancel". Day editor: "Program" (back), "DAY %lld OF %lld", "Done", meta "Week %lld · %lld exercises · %lld sets · ~%lld min"; "SUPERSET" + "%lld exercises back to back · rest after %@"; index "4A"; sub "%@ · %@ · RPE %@ · %@ rest" with `progShort` "+%@/wk" / "Reps %lld–%lld" / "Fixed", optional " · drop", "no rest" for non-last members; scheme "%lld×%lld", "%@ lb"; preview "WEEK %lld" / " · DELOAD" / " · HELD" + "%lld × %lld @ %@ lb · RPE %@"; week strip "W1 185 · W2 190 · W3 195 …" (deload weeks "W8 240 (deload)"); fields "SETS", "REPS" / "REP FLOOR", "TOP OF RANGE", "START LOAD", "TARGET RPE", "REST"; "PROGRESSION" chips "Linear" / "Double" / "Fixed"; notes "Adds %@ lb a week from %@ lb. A week with a missed set holds the load." / "Adds a rep each week up to %lld, then +%@ lb back at %lld." / "Stays at %@ lb for the whole block."; "Drop set" + "One extra set at −15% after the last working set." / "One extra set at −15%, straight after the last working set."; "Break out", "Superset with next"; "Move up", "Move down", "Remove"; "+ Add exercise from library". Picker: "Exercise library", "Cancel", placeholder "Search exercises", muscle chips "All, Chest, Back, Shoulders, Legs, Arms", equipment chips "All, Barbell, Dumbbell, Cable, Machine, Bodyweight", row meta "%@ · %@" / "%@ · %@ · already in this day", "Nothing matches that filter.", "Clear filters", CTA "Select exercises to add" / "Add 1 exercise" / "Add %lld exercises". Validation: "A block needs at least 2 weeks.", "Week %lld has logged sessions and can't be removed.", "Add at least one exercise before scheduling this day." (shown when cycling to an empty day; the day is still assignable).

## Acceptance criteria
1. Given the F08 default program, when the builder opens, then it shows "BLOCK · 8 WEEKS", chips W1–W7 "4 DAYS" and W8 "DELOAD", the schedule strip for W1 as M UA · T REST · W LA · T REST · F UB · S LB · S REST, "4 days · 58 sets a week", and four day cards with the spec seed meta values recomputed by `TimeEstimate` (documented in implementation notes).
2. Given W1 selected, when I tap the Tuesday slot four times, then it cycles REST → UA → LA → UB, and the chip's "DAYS" count updates; after the fifth tap it reads LB, sixth → REST.
3. Given week 3 selected, when I tap "Copy week 2", then W3's schedule equals W2's; "Apply to later weeks" copies W3's schedule to W4–W8 leaving deload flags untouched; "Deload" toggles W3 and the chip reads "DELOAD".
4. Given "−" on weeks, when the count is 2, then the message "A block needs at least 2 weeks." shows and nothing changes; when the last week has a finished workout, then "Week 8 has logged sessions and can't be removed." shows. Given "+", then a copy of the last week's schedule is appended (not deload) and selected.
5. Given "+ Add training day", when tapped, then a day "New day" / "D5" with no slots is created and the Day editor opens on it; the builder card later reads "No exercises yet".
6. Given a day scheduled in 8 weeks, when I delete it and confirm, then it is removed and every schedule reference becomes rest; cancel leaves everything intact.
7. Given Incline DB Press (double, 10–12, step 2.5, start 50), when the slot is expanded, then the week strip reads "W1 50 · W2 50 · W3 50 · W4 52.5 · …" and reps preview per week follows rule 10; for Back Squat the W8 preview reads "W8 240 (deload)" and the eyebrow "WEEK 8 · DELOAD"; a slot whose previous week is a miss shows " · HELD".
8. Given "REPS" raised to ≥ repsHi, then repsHi becomes reps + 1; given "TOP OF RANGE" lowered to ≤ reps, then it snaps to reps + 1; "SETS" clamps 1–12, RPE 5–10 by 0.5, REST 30–300 by 15 (label "45s" / "2 min" / "2:30"), START LOAD steps by the unit step and floors at 0.
9. Given "Double" chosen on a slot with reps 8 and repsHi 8, then repsHi becomes 10 and the label switches to "REP FLOOR" / "TOP OF RANGE"; the note reads "Adds a rep each week up to 10, then +5 lb back at 8.".
10. Given slots [1, 2, 3A, 3B, 4], when I "Move down" slot 2, then the order becomes [1, 3A, 3B, 2, 4] (block moved as a unit); when I "Move down" 3A, then it becomes 3B/3A swapped within the block with letters recomputed; "Move up" on 3A (first of block) moves the whole block above slot 2. Superset flags stay consistent (test property: first of each block has `isSupersetWithPrevious == false`).
11. Given "Superset with next" on slot 4 of 5, then slot 5 gets `isSupersetWithPrevious = true`, the header reads "2 exercises back to back · rest after B", slot 4's sub shows "no rest"; "Break out" on B detaches it.
12. Given the picker, when I type "row" with muscle "Back" and equipment "Machine", then only matching exercises (incl. custom ones) appear; rows already in the day show "· already in this day" in orange; selecting three enables "Add 3 exercises"; adding appends three slots with rule-7 defaults (3×8 @ RPE 8, rest = `Settings.defaultRest`, linear, repsHi 10, load = default start load) and closes the sheet, keeping the muscle/equipment filters but clearing query and selection.
13. Given every edit, when applied, then `programRepository.save` is called within 300 ms (debounced) and a live workout in progress is unaffected (rule 16); after relaunch the edit persists; Today reflects the change (F15 flow).

## Test plan
- Unit (LedgerDomainTests): `test_editing_addWeek_copiesScheduleNotDeload`, `test_editing_removeWeek_minTwo`, `test_editing_removeWeek_loggedSessionsThrows`, `test_editing_cycleSchedule_order`, `test_editing_copyPrevious_applyLater_deloadUntouched`, `test_editing_addDay_nameTag`, `test_editing_deleteDay_clearsSchedule`, `test_editing_addSlots_rule7Defaults`, `test_editing_reps_pushesRepsHi`, `test_editing_repsHi_snapsAboveReps`, `test_editing_clamps_allFields`, `test_editing_double_setsRepsHiPlus2`, `test_editing_move_soloPastBlock`, `test_editing_move_withinBlock_swapsAndReletters`, `test_editing_move_blockAsUnit`, `test_editing_move_invariant_firstOfBlockNotSuperset` (property, random programs), `test_editing_toggleSuperset_breakOut`, `test_editing_weekLoads_doubleProgressionExample`, `test_editing_weekLoads_deloadRoundsToStep`.
- Unit (FeatureProgramTests): `test_store_builder_defaultProgramPresentation`, `test_store_save_debounced`, `test_store_validation_messages`, `test_dayEditor_subLine_formats`, `test_dayEditor_previewStrip_text`, `test_dayEditor_restLabel_formats`, `test_picker_filtersCombine`, `test_picker_alreadyInDay_flag`, `test_picker_ctaLabel_pluralisation`, `test_picker_clearFilters`, `test_picker_customExercisesIncluded`.
- Integration (LedgerPersistenceTests): `test_programRepository_saveEditedProgram_roundTrip`, `test_programRepository_deleteDay_cascadesSlots`.
- Snapshot (FeatureProgramTests): `ProgramRoot` × {default, deloadSelected, emptyDay, twoWeeksError}; `DayEditorView` × {collapsed, expandedLinear, expandedDouble, supersetBlock, dropOn}; `ExercisePickerSheet` × {results, selected, empty} — each × {light, dark} × {default, XL}.
- UI (LedgerUITests): F15 flow `program_edit_reflects_on_today`.

## Non-functional
- Performance budget: builder first frame < 100 ms with 16 weeks × 6 days; slot edit → UI < 16 ms; picker search over 200+ exercises < 10 ms per keystroke (in-memory filter, debounced 100 ms).
- Accessibility: schedule slots read "Tuesday, rest, button — double-tap to assign"; steppers are `.adjustable`; chips are radio groups; superset header is a heading; Dynamic Type to AX5 with the 7-slot strip wrapping to two rows at AX sizes; ≥ 44 pt targets.
- Offline behaviour: fully local.

## Risks / unknowns
- Builder has no v2 design (spec §9); apply v2 tokens/hairlines to v1 layout and expect reviewer design-fidelity notes.
- Group-aware move semantics are defined here, not in the prototype; product may prefer "move members only".
- `TimeEstimate` (decision #14) produces different minutes than the spec seed strings ("~40 min"); tests assert the formula, not the seed strings.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `ProgramEditing` at 100 % line coverage incl. the move property test.
- [ ] No clamping or coupling logic in views/stores — only `ProgramEditing`.
- [ ] Every string above in the String Catalog with plurals (weeks, days, sets, exercises).
- [ ] Builder + Day editor screenshots at default and AX5 on the PR.

---
_Filled in by agents during delivery:_
- `F11-program-builder/implementation-notes.md`
- `F11-program-builder/test-findings.md`
- `F11-program-builder/review.md`

---

## Plan amendments (orchestrator, 2026-10-05)

The plan is `F11-program-builder/implementation-notes.md`. Where it and the text above differ, the plan and
this section are the specification. The differences that change behaviour:

- **Slices.** The feature is delivered as slices, one pull request each (the plan's "Slice plan"). The plan's
  S1 and S2 are built together as **S1** (below); the number S2 is not used; S3 to S14 keep the plan's numbers.
- **Criterion 2's count.** From rest, a weekday cycles through the program's days in order and back to rest:
  with four days, taps one to four give UA, LA, UB, LB and the fifth gives rest.
- **Signatures** are the plan's ("The editing functions, as proposed"), not the sketch under "Domain changes":
  new ids are parameters; block editing works on a `Program` and day editing on a `DayTemplate`; the weeks that
  hold a finished workout are handed to `removeLastWeek`; `ProgramEditError` has two cases.
- **Saving.** No 300 ms timer is built. An edit is applied on screen at once and stored through
  `ProgramRepository.update` (S3) by one save loop; edits made while a write runs go together in the next one
  (the plan's "The 300 ms debounce"). Criterion 13 reads: the first edit is written at once, the stored program
  after any sequence of edits is the program on screen, and a workout saved meanwhile loses nothing.
- **Fixtures.** "The F08 default program" in criterion 1 is the spec's seed program (`Fixtures.seedProgram()`);
  the day cards' minutes are `TimeEstimate`'s (39, 38, 37, 31).
- **Routes and strings** follow the M1 conventions: `ProgramRoute` in the feature, the mapping in
  `LedgerAppKit`; one catalog and one copy file family in `FeatureProgram`. Names of Domain values a module
  shows (equipment, muscles, progression) are entries of that module's own catalog.
- **Defaults built until Pete answers** (the plan's "Decisions for Pete"): the screens are drawn in the dark
  design's language, the week chips wrap; a superset moves as one (the brief's rule); the library has the
  brief's ten chips; "Delete day" sits at the foot of the Day editor and is allowed while that day's workout
  runs; a day's tag is not editable; the plan's wording for the texts the brief lacks.

## Plan amendments — slice S1, program and day editing in the Domain (orchestrator, 2026-10-05)

The plan's S1 and S2 as one pull request, cut from `main`: every editing rule of spec §7.1 as pure functions
of `LedgerDomain`, with no screen, no store and no repository. About 570 product lines planned. The functions,
their behaviour row by row and the worked examples are in the plan: "The editing functions, as proposed",
"Group-aware move, defined", and "Inputs the implementer needs › S1" and "› S2". The slice is accepted when:

1. **Pure and total.** Every function of `ProgramEditing` and `DayEditing` is a pure function of its
   arguments, never traps, and returns its input unchanged when given an id the program or day does not hold.
   Only `removeLastWeek` and `newSlot` throw, with typed throws. Every program a `ProgramEditing` function
   returns is accepted by `Program.init`, and every slot a `DayEditing` function returns by `Slot.init`.
2. **Names.** `cleanedName` removes every scalar of category `Cc`, trims, and is `nil` when nothing is left;
   `renameProgram` and `renameDay` set the cleaned name and change nothing for a blank one.
3. **Weeks** (criterion 4). `addWeek` appends a week with the next index, the last week's schedule and no
   deload flag. `removeLastWeek` throws `.minimumTwoWeeks` at two weeks whatever else holds, then
   `.weekHasLoggedSessions(weekNumber:)` (one-based) when the last index is among the logged weeks, and
   otherwise drops the last week. `toggleDeload` flips one week's flag.
4. **Schedule** (criteria 2 and 3). `cycleSchedule` goes rest, first day, …, last day, rest, in the order of
   the program's days; `copyPreviousWeek` and `applyToLaterWeeks` copy schedules and leave every deload flag.
5. **Days** (criteria 5 and 6). `addDay` appends a day with no slots and the tag "D{n}", or the next number
   whose tag is free; `deleteDay` removes the day and every schedule entry that names it; `updateDay` replaces
   one day and ignores a result with another id.
6. **Slots.** `newSlot` builds rule 7's defaults (criterion 12: 3 × 8, top 10, RPE 8, the default rest,
   linear, the exercise's start load in the lifter's unit); `addSlots` appends and leaves out an id the day
   holds; `removeSlot` removes one, and the next member leads if it led a superset.
7. **Fields** (criterion 8). `set` clamps (sets 1…12, reps 1…30, top of range 2…40, RPE 5…10 on the half, rest
   30…300 s on the 15, start load never below zero) and then keeps the top of the range above reps. `stepped`
   gives the value one step away and does not clamp; the start load goes to the next multiple of the slot's
   step, or of the equipment's default step in the lifter's unit, and never below zero.
8. **Progression, drop set, superset** (criteria 9 and 11). Choosing double progression makes the top of the
   range at least reps + 2; a drop set is 1 or 0; a day is always returned in normal form (its first slot is
   never joined to a previous one).
9. **Move** (criterion 10): as "Group-aware move, defined", with its six properties checked on seeded days.
10. **Every week's prescription** (criterion 7): `ProgressionRules.prescriptions` gives Incline DB Press 50,
    50, 50, 52.5, 52.5, 52.5, 55 and 47.5 lb with reps 10, 11, 12, 10, 11, 12, 10, 11, and Back Squat 240 lb in
    the deload week; a missed week marks the next as held.
11. **The library's filter** (criterion 12): on the seed catalog, "row" with Back and Machine is exactly
    "Chest-Supported Row"; the five muscle chips map to muscle groups as the plan lists.
12. **What editing never writes.** No function changes the misses or the exercise of a slot that already
    exists (a property over every function, on seeded programs). S3 relies on it.
13. **The Domain's rules.** Foundation only; exact decimals, no `Double`; public pure types `nonisolated` and
    `Sendable` as their neighbours are; the three ranges of `Slot` become public constants with no change in
    behaviour (the existing tests pass untouched); 100 % line coverage of the new files.

## Plan amendments — slice S1 after round 1 (orchestrator, 2026-10-06)

The tester found no bug (154 tests; findings F11-S1-1 to -3 are two questions and a note on test quality) and
the reviewer approved with three should-fix items and nine nits. Rulings, which add to S1's thirteen criteria:

14. **Choosing the progression a slot already has changes nothing** (review S-1). `setProgression` returns the
    day as it was when the slot already has that progression, so a second tap on "Double" never widens a range
    the lifter narrowed. Changing from linear to double still makes the top of the range at least reps + 2.
15. **Criterion 12 cannot be escaped** (review S-2): a source test over `LedgerDomain/Programs` fails when a
    function that returns a `Program` or a `DayTemplate` is missing from the property's tables, or when a line
    outside `newSlot` assigns a slot's misses or exercise or builds a `Slot`.
16. **The library's filter is `ExerciseSearch.filtered(_:query:muscle:equipment:)`** (review N-1), beside
    `sorted(_:)`; nothing else about it changes.
17. **Kept as built:** the direction cases `upward` and `downward` (F11-S1-2); a name of only invisible
    characters is stored (F11-S1-1; a rule "a name has a visible character" is not in the specification);
    `prescriptions` is for a stored program's weeks and a valid slot, as `prescribe` is, and says so.

**For S13 and S14** (review S-3). `toggleDeload`, `cycleSchedule`, `move` and `removeLastWeek` are relative:
applied twice they do not give what one application gives. Each queued edit therefore reaches the stored
program exactly once. After an `update` that failed or was cancelled, the waiting edits are dropped and the
screen is redrawn from the stored program; they are never sent again. **For S7** (review N-8): the start load
and the step a slot resolves to (its own, or the exercise's and the equipment's default in the lifter's unit)
become two small functions on `Slot`, used by `ProgressionRules` and `DayEditing`, before a presentation
writes that pair a third time.
18. **Recorded, not fixed** (F11-S1-4, round 2): the source test of criterion 15 is a tripwire for the likely
    mistakes (a new `static func` left out of the tables; a line that assigns a slot's misses or exercise). It
    does not see an instance or `mutating` method, a write through a key path or a whole-slot assignment, or
    code outside `LedgerDomain/Programs`. The property test over the listed functions remains the proof; a
    reviewer of any later change to these files checks criterion 12 by reading.
## Plan amendments — slice S3, the atomic program update (orchestrator, 2026-10-06)

Cut from `main`, independent of S1. One new requirement on `ProgramRepository`, so that a builder edit is
applied to the program as it is stored at that moment and can never write back an older copy of what a
workout's save put there (a slot's misses; a swap's exercise). The plan's "Saving and a live workout" gives
the reasons and the code it stands on; "Inputs the implementer needs › S3" gives the signatures and files;
Risks 1 and 2 apply. About 45 product lines; most of the slice is contract and tests. Accepted when:

1. **The requirement.** `func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program`
   on `ProgramRepository`, with no default body. It applies `change` to the program `id` as stored now and
   saves the result, in one step that no other write can come between, and returns the program as stored
   afterwards.
2. **Nothing to update.** A program that is not stored, or is deleted, throws the repository's missing-row
   error; `change` is not called and nothing is written.
3. **A change that throws** is rethrown as it is; nothing is written and no observer is woken.
4. **A result that `save` would refuse** (an id another program holds, a slot whose exercise has no row, text
   the store refuses) is refused with the same error, and so is a result with another id; nothing is written.
5. **A change that returns the program as it was** writes no row and wakes no observer.
6. **Rows.** Only rows that changed are written, a row the result no longer has is soft-deleted, as `save`
   does; which program is active does not change.
7. **Nothing is lost between a builder and a workout's save.** The losing sequence is the slice's first test:
   read a program, save a finished workout that records a miss and a swap on it, then write the builder's edit.
   Through `save` the miss and the swap are gone (the test shows it); through `update` both are kept. For
   seeded interleavings of `update` calls and workout saves, the stored program equals the calls applied one
   at a time in the order they were taken, on the database and on the in-memory stores alike.
8. **Cancellation.** A call whose task is cancelled stores all of its change or none of it. What GRDB does
   with a write whose task is cancelled is established by a test and written down, since S13 relies on it.
9. **The in-memory stores follow** (ADR-008 decision 5): the same clauses of the shared contract pass on both;
   the in-memory repository works under the one lock a workout's save takes. The unimplemented stub reports as
   its neighbours do, and the probe forwards `update` and can hold it (S13's store test holds the first write).
10. **Every other conformer compiles**: the four test doubles on `main` gain the requirement by a mechanical
    edit, each listed in the notes (two are testers' files; the edit is sanctioned and audited).
11. **No migration, no schema change**; the version fixtures and every existing contract clause are untouched
    and pass.

## Plan amendments — slice S3 after round 1 (orchestrator, 2026-10-06)

The tester found no bug (32 tests, 282 cases; one question, F11-S3-1) and the reviewer approved with two
should-fix items. Atomicity holds by construction on both stores. Rulings, which add to S3's eleven criteria:

12. **The in-memory store cancels as the database does** (F11-S3-1, review S1; ADR-008 decision 5). A call
    whose task is cancelled before the change, inside the change, or while it waited for the lock throws
    `CancellationError` and stores nothing; one cancelled after its write is stored whole and returns. The
    contract's cancellation clauses are strict on both stores, so a store tested over the fakes sees the same
    rollback path.
13. **`save` says what it costs** (review S2): its documentation warns that saving an earlier copy of a stored
    program writes back the misses and the exercise a workout's save put there, and points to `update`.
14. **Criterion 6, as built:** `update` leaves which program is active as it was when the change does not touch
    the flag; a change that sets the flag is saved as `save` saves it. A result under another id is refused
    with the duplicate-identifier error.
15. **One ending on both stores** (F11-S3-2, round 2): when a call is cancelled inside a change whose result
    is also refused, both stores report what the database reports. The in-memory store makes the database's
    checks in the database's order: the result's id and validity, then cancellation, then the write.

## Plan amendments — slice S5, the builder's presentation (orchestrator, 2026-10-06)

Cut from `main`, which now holds the tab shell and the localization rule (#28), the editing rules (S1) and the
atomic update (S3). The logic and the words of the Program builder screen, with no view and no store: one pure
function, `ProgramPresentation.make(_:) -> ProgramBuilderModel`, in the form `FeatureToday`'s presentation
has on `main`. The views (S9) only draw the model and the store (S13) only fills the input and sends the
model's actions to `ProgramEditing`. About 470 product lines planned (the plan's S5 row lists the files). The
slice is accepted when:

1. **One input, one model.** `make` takes one input value (the program, the exercises, the settings, the
   selected week, the weeks that hold a finished workout, a notice if one is showing, the calendar and the
   locale) and returns a model whose every string is final and whose every action is a value the store can
   apply without deciding anything: an edit named by ids and places, or a `ProgramRoute`.
2. **The header and the block** (criterion 1): the eyebrow "MY PROGRAM", the program's name with its
   placeholder, "BLOCK · 8 WEEKS", "−" and "+", and one chip per week reading "W1" with "4 DAYS", or "DELOAD"
   for a deload week, the selected one marked.
3. **The selected week** (criteria 1 to 3): "WEEK 3" or "WEEK 3 · DELOAD"; the seven cells in the order of the
   settings' week start, each with the weekday's letter from the injected calendar and locale and the day's
   tag or "REST"; each cell's action is the cycle of that weekday; the hint "Tap to assign"; the week's
   actions "First week" (disabled) or "Copy week 2", "Apply to later weeks" (absent on the last week), and
   the deload toggle with its state.
4. **The seed program reads as criterion 1 gives it:** W1 to W7 "4 DAYS", W8 "DELOAD"; week 1's strip
   M UA · T REST · W LA · T REST · F UB · S LB · S REST; "4 days · 58 sets a week"; four day cards whose
   minutes are `TimeEstimate`'s (39, 38, 37, 31).
5. **The day cards** (criterion 5): name, tag, the meta line from the slots' own numbers (exercises, sets as
   Σ(sets + drop sets), minutes), "No exercises yet" for an empty day, each carrying `ProgramRoute.day(id)`;
   and "+ Add training day".
6. **Notices** (criterion 4 and behaviour 6): "A block needs at least 2 weeks.", "Week 8 has logged sessions
   and can't be removed.", and the notice for a weekday assigned to a day with no exercises, each a final
   string the store shows from an error or an edit's result, built here.
7. **Words.** Every text is the brief's "Copy (exact)" or the plan's decision 6, resolved in `ProgramCopy`
   from `FeatureProgram`'s own String Catalog under standards §7 (one counted value per key; `locale:` when
   a key carries a value; spoken texts are copy; no literal outside the copy files but "" and " · "). The
   equipment names this slice needs are entries of this catalog. Texts the brief does not give are listed
   in the notes for Pete.
8. **Spoken texts** for the chips, the cells ("Tuesday, rest") and the cards exist, are copy, and agree with
   what is drawn.
9. **Pure and total.** No `Date()`, `Calendar.current`, `Locale.current` or `TimeZone.current` in the module
   (a source test in the form of `FeatureToday`'s); nothing traps for a program with no days, a selected week
   out of range (read as the nearest week), a day with no slots, a slot whose exercise is not stored; the
   same input gives the same model in any order of the exercises handed in.
10. **No rule of its own.** Counts, minutes, limits and the cycle come from `LedgerDomain`
    (`ProgramEditing`, `TimeEstimate`, `WeekCalendar`); the presentation adds no clamp and no schedule rule.
11. **The module is wired as `FeatureToday` is:** the target's `resources`, `FeatureProgram` in the coverage
    thresholds, the placeholder file and its test gone; the gate's string-catalog step and `ModuleCopyTests`
    pass with no exemption.

## Plan amendments — slice S5 after round 1 (orchestrator, 2026-10-06)

The tester found no bug (44 tests, 300 cases; findings F11-S5-1 to -4 are questions and notes) and the reviewer
approved with six should-fix items. Rulings, which add to S5's eleven criteria:

12. **The screen's edits of a cell and of a deload are absolute** (review S-1). A cell's action names what the
    cell becomes (a day's id, or rest) and the deload switch names the state it turns to, so an edit drawn or
    applied twice gives what one application gives. `LedgerDomain` gains `ProgramEditing.setSchedule(_:week:weekday:day:)`
    (a day the program lacks changes nothing) and `setDeload(_:_:week:)`; the cycle's order (rest, first day, …,
    last day, rest) is one pure function the presentation asks for the next value. `cycleSchedule` and
    `toggleDeload` stay and are written in terms of them. Adding a week, removing the last week and moving
    stay relative, and the note "For S13 and S14" still holds for them.
13. **With no training day, a cell offers nothing** (F11-S5-2): no action, no hint, and its spoken text says
    only the weekday and "rest".
14. **The name is a draft in the store** (review S-3): the model carries the stored name and a `rename` action
    that takes the typed text; the comment says a view binds a draft, not the model's name.
15. **Kept as built:** the seven cells follow the settings' week start (criterion 3; F11-S5-1), with the
    letters and spoken names from the injected calendar and locale. Digits and plural forms follow the injected
    locale (F11-S5-3): as for Today, the store hands in the app's locale, which is English while the catalogs
    hold English only.
16. **Housekeeping from the review:** no whole `Program` is compared inside an expectation (S-5); the source
    test checks the `Double` spellings as Today's does (S-6); the notes no longer claim that `update` refuses
    "−" when a workout finished meanwhile (S-2: the store reads the logged weeks again before it sends that
    edit, which is S13's to build); standards §7 gains the sentence of ruling 3 (S-4), as the reviewer words it.
17. **Criterion 14, as built** (F11-S5-5, round 2): the rename is the action `ProgramBuilderAction.rename(_:)`,
    which takes the typed text; it is not a field of the model, since the model cannot know the text.

## Plan amendments — slice S6, the Day editor's and the slot editor's presentation (orchestrator, 2026-10-08)

The plan's S6 and S7 as one pull request (Pete asked on 2026-10-08 for larger batches; the number S7 is not
used). Cut from `main`, which holds the builder's presentation (S5) and the editing rules. The logic and the
words of the Day editor screen, including the panel that opens under one exercise, with no view and no store:
pure functions in `FeatureProgram/DayEditor/` in the form `ProgramPresentation` has, and their copy files and
catalog entries. About 720 product lines planned (the plan's S6 and S7 rows list the files); one pull request
while it stays under about 1,000. The slice is accepted when:

1. **One input, one model.** `DayEditorPresentation.make` takes one input value (the program, the day's id,
   the exercises, the settings, the week shown, the open slot if any, the calendar and locale) and returns a
   model whose every string is final and whose every action is a value the store applies with one
   `ProgramEditing.updateDay` around one `DayEditing` call, or a `ProgramRoute`. A day the program no longer
   holds gives a model that says so (the store closes the editor).
2. **The header and the meta line** (brief, "Copy (exact)"): the day's name and tag, "Week n" with the counts
   of that week's prescription (behaviour 13: a deload week counts its own sets and minutes), back and done.
3. **The rows** (criteria 7, 10, 11): each exercise's name, its sub line (sets × reps or range, load in the
   lifter's unit, RPE, rest as "45s" / "2 min" / "2:30", "no rest" inside a superset), the superset headers
   ("2 exercises back to back · rest after B") with letters A, B, …, a drop set's mark; a slot whose exercise
   is not stored is listed under a dash and can be removed (behaviour 19).
4. **The open slot's fields** (criteria 8, 9): the six steppers with their labels ("REPS" / "REP FLOOR" and
   "TOP OF RANGE" for double progression), each value drawn, each "−" and "+" an action carrying
   `DayEditing.set(DayEditing.stepped(…))`'s field so that the store adds nothing; the progression chips with
   the note ("Adds a rep each week up to 10, then +5 lb back at 8."), the drop-set switch, the superset
   action that applies ("Superset with next" or "Break out"), move up, move down and remove, each present
   only when it can do something.
5. **Every week's prescription** (criterion 7): the selected week's line and the strip "W1 50 · W2 50 · …"
   from `ProgressionRules.prescriptions`, with "(deload)" and " · HELD" where they apply, the eyebrow
   "WEEK 8 · DELOAD", in pounds and in kilograms.
6. **Delete day** (Pete's decision 4, default): the button, and the confirmation's title and lines ("Delete
   Lower B?", "It's scheduled in 8 weeks. Those days become rest.", one week, nowhere), as values.
7. **Words.** Every text is the brief's "Copy (exact)" or the plan's decision 6, resolved in the module's
   copy files from `FeatureProgram`'s catalog under standards §7; equipment and progression names are entries
   of this catalog; spoken texts (each stepper as one adjustable element with its value; rows; headers) are
   copy. Texts the brief does not give are listed in the notes for Pete.
8. **No rule of its own.** Limits, coupling, steps, groups, moves, counts and minutes come from
   `LedgerDomain`. The start load and the step a slot resolves to become two small functions on `Slot`
   used by `ProgressionRules`, `DayEditing` and this presentation (the note "For S7" of S1's rulings).
9. **Pure and total.** No ambient clock, calendar, locale or zone (the module's source test covers the new
   files); nothing traps for a day with no slots, one slot, a week out of range, an open slot the day no
   longer holds (read as none open); the same input gives the same model.
10. **Absolute where it can be.** Field edits name the value they set; the drop set and the superset name
    the state they turn to; only move and remove are relative, and the model marks them so.

## Plan amendments — slice S6 after round 1 (orchestrator, 2026-10-08)

The tester found no bug (53 tests against its own model of the screen; six questions and notes) and the
reviewer approved with four should-fix items and recommends one pull request at about 1,007 lines (the seam
is taken only if fixes pass about 1,050). Rulings, which add to S6's ten criteria:

11. **A superset shows the rest the workout takes** (review S-1): the line after a superset's last exercise
    reads the rest the Domain gives the group (the longest of its members'), not that row's own. The seed's
    Upper A superset reads 1:15. (The prototype printed the row's own; listed for Pete.)
12. **Set counts come from the Domain** (review S-3): `TimeEstimate` gains the count of sets for a day and
    for a week's prescription; the builder's and the Day editor's presentations call it and sum nothing.
13. **No queued edit is safe to send twice** (review S-2): the comment on `isRelative` says that the mark is
    about drawing an edit again over a program that already has it, not about replaying a queue; a test
    pins an example in which two unmarked edits replayed give another program.
14. **"Rest" the day and "rest" the pause are different texts** (F11-S6-4): separate keys with translators'
    comments, although the English is the same.
15. **Kept as built:** in a deload week a row's line shows that week's prescription, RPE included
    (F11-S6-1, -3); `isHeld` is false in a deload week (F11-S6-2); remove is marked relative (F11-S6-6); both
    superset actions can show (spec §3.4 e); a slot whose exercise is missing is listed and removable only.
16. **Housekeeping:** no whole model inside an expectation (review S-4).

**For F15** (F11-S6-5): spoken texts that reuse drawn abbreviations ("+5/wk", "3×12", "45s") are reworded for
VoiceOver in the accessibility pass, with the product owner's wording.

**Criterion 14 of this section is withdrawn** (orchestrator, 2026-10-08; F11-S6-7): standards §7 makes the
English text the key, so "rest" the day and "rest" the pause stay one key with a translator's comment that
names both uses. How the localization rule tells two uses of one English text apart is a question for the
first translation and for the product owner; it is not decided here.

## Plan amendments — slice S8, the form controls and the exercise library's presentation (orchestrator, 2026-10-08)

The plan's S4 and S8 as one pull request (larger batches; the number S4 is not used again). Cut from `main`,
which holds the builder's and the Day editor's presentations. Two parts in two modules, with no view of a
screen and no store: three controls in `LedgerDesign` that every later view slice of F11 (and F14) draws with,
and the logic and words of the exercise library sheet in `FeatureProgram/Picker/`. About 480 product lines
planned (the plan's S4 and S8 rows list the files; "Inputs the implementer needs", S4, gives the shapes); one
pull request while it stays under about 1,000; past about 800 the implementer stops and reports before
going on. The slice is accepted when:

**Part one: the controls (`LedgerDesign/Components/`).**

1. **`StepperField`**: a label, a value, "−" and "+". It takes `String`s and one closure per step and looks
   nothing up; either step can be switched off (a value at its limit), and a switched-off step is drawn and
   spoken as such. To VoiceOver it is one adjustable element with the label and the value; a spoken value
   can be given apart from the drawn one. Both buttons are 44 pt targets; the parts stack at accessibility
   sizes.
2. **`LedgerToggleStyle`** (`.toggleStyle(.ledger)`): an ink track when on, no orange (Pete's decision 1,
   default A); the knob reads in both themes and under Increase Contrast; VoiceOver keeps SwiftUI's switch
   with its value.
3. **`WrapLayout`**: children run along a row and wrap onto the next; right-to-left runs from the right; no
   child, one child and a child wider than the row (it gets the row's width) all lay out; the size it
   reports is the size it uses.
4. **Registered and shown**: each control has its cases in the preview registry and a section of the design
   gallery; snapshot references at the six cells of testing-strategy §2.5; one pinned VoiceOver tree each
   (the layout's with pill buttons inside it); the 44 pt check. They compile for watchOS.
5. **The set row is not touched.** Its private stepper stays as it is; whether the two become one is a
   later chore, named in the notes.

**Part two: the exercise library's presentation (`FeatureProgram/Picker/`).**

6. **One input, one model.** `ExercisePickerPresentation.make` takes one input value (the stored exercises,
   the exercises already in the day, the query, the muscle and equipment chosen, the picks in the order
   picked, the locale) and returns a model whose every string is final and whose every action is a value.
   The list is `ExerciseSearch.filtered`'s, in its order; the presentation filters and sorts nothing itself.
7. **The chips** (Pete's decision 3, default B): "All, Chest, Back, Shoulders, Legs, Arms" and "All,
   Barbell, Dumbbell, Cable, Machine, Bodyweight", one selected in each row, each an action that names the
   filter it sets (absolute). The chips are built from one list each, so that decision A (Core, Kettlebell,
   Band) is three more entries and no other change.
8. **The rows** (criterion 12): the name; the line "Machine · Back", with " · already in this day" when the
   day holds the exercise (the mark is a separate value too, so that the view can draw it apart); whether
   it is picked, and its place among the picks; the action that picks or unpicks it. An exercise in the day
   can still be picked (the spec allows it twice). Custom exercises are rows like any other.
9. **Nothing matches**: "Nothing matches that filter." and "Clear filters", whose action resets the query
   and both chips. A catalog with no exercise at all gives the same model and does not trap.
10. **The foot**: "Select exercises to add" (disabled), "Add 1 exercise", "Add %lld exercises" by the
    catalog's plural forms; its action carries the picked exercises' ids in the order picked, each at most
    once per pick, and only those still stored. Title "Exercise library", "Cancel", placeholder "Search
    exercises".
11. **The picks become slots through the Domain.** The Day editor's edit gains the one case S6's notes
    name (`.slot(.add…)` around `DayEditing.addSlots` and `newSlot`): rule 7's defaults come from there, and
    the presentation builds no slot.
12. **Words.** Every text is the brief's "Copy (exact)", resolved in `ProgramCopy+Picker.swift` from the
    module's catalog under standards §7; the muscle names are entries of this catalog; the equipment names
    are the entries S6 added and are not added again. Spoken texts (a chip with its row's name, a row with
    its line and whether it is picked, the foot) are copy. Texts the brief does not give are listed in the
    notes for Pete.
13. **Pure and total.** No ambient clock, calendar, locale or zone (the module's source test covers the new
    files); the same input gives the same model; picks or day exercises that are no longer stored are
    ignored, not trapped on.

**Not in this slice:** the library's views (S12, with the builder's views next), its store (S14), any change
to `LedgerAppKit`, the project file or a test plan.

## Plan amendments — slice S8 after round 1 (orchestrator, 2026-10-08)

The tester found one bug, one defect against a criterion's wording and one test gap (43 tests, two left
failing); the reviewer approved with three should-fix items and recommends one pull request at about 590
lines. Rulings, which add to S8's thirteen criteria:

14. **The plural form is English's while the catalog is English** (F11-S8-1). A text with a plural takes its
    form by the rules of the language the catalog resolves to, not by the lifter's locale: "Add 1 exercise"
    under ja_JP, "Add 21 exercises" under ru_RU. The fix is one place in `ProgramCopy` that every plural of
    the module goes through, so `exercises` and `weeks` (on `main` since S5) are right too; the tester's
    test passes unedited. The other modules' copy files have the same cause and are a chore of their own,
    not this slice. If the fix needs more than one helper of about thirty lines, or a change outside
    `FeatureProgram`, the implementer stops and reports.
15. **Criterion 1 is amended** (F11-S8-2, review): a switched-off step is drawn as off; it is spoken only
    when both steps are off or the field is disabled (the element is then dimmed). There is no trait for one
    direction and no caller switches one step off. The tester replaces its failing test with one that pins
    this.
16. **A disabled stepper field looks disabled** (review S-2): its label and value take the faint ink
    `PillButton` gives disabled text; the slice's own references are recorded again (none of them is on
    `main`).
17. **The lint waiver stays, with its reason on the line** (review S-1), as an exception to standards §12
    that the pull request names for the product owner, with the reviewer's alternative (the rule ignoring
    case lists) as his option. The lint configuration is not changed here.
18. **Housekeeping** (review N-1 to N-5): the missing translator's comment; `Row`'s two spoken fields that
    only repeat `name` and `line` go, as does the action that is an alias of `setQuery`; the source test's
    list names the two new files; `WrapLayout`'s comment says what it asks of an over-wide child, and a
    zero-width proposal with children is tested.
19. **Accepted as built**: `StepperField`'s two optional closures; a picked row spoken through the selected
    trait (S12's VoiceOver table pins the trait); the other decisions of the implementer's notes.

**For S14** (F11-S8-3): no hosted test can tap, so a finger's tap on "−", "+" and the switch is covered by
nothing until the nightly UI test of the Day editor taps all three. **For S12**: whether VoiceOver says a
pick's place is the product owner's question, asked with S12's VoiceOver table. **Not covered by criterion
13** (tester's Q1, Q2): two stored exercises under one id (the schema forbids it) and a blank name (F12's
rule for custom exercises).

## Plan amendments — slice S9, the builder's and the exercise library's views (orchestrator, 2026-10-09)

The plan's S9 and S12 as one pull request (larger batches; the number S12 is not used again). Cut from `main`,
which holds the builder's and the library's presentations and the three form controls. Views drawn from a
model only: no store, nothing in the app (the Program tab keeps its placeholder until S14). About 670
product lines planned (the plan's S9 and S12 rows list the files); views have landed close to plan; past
about 850 the implementer stops and reports. Pete's decision 1 is taken at its default A (the dark design's
language; orange only on "DELOAD" in the builder and on the library's "Add n exercises" button). The slice is
accepted when:

1. **Drawn from the model only.** Every view takes its part of `ProgramBuilderModel` or `ExercisePickerModel`
   and closures over the model's action values; no view decides what is shown, formats a number, filters a
   list or reads a clock, calendar or locale. Every text on screen is a string of the model or a lookup the
   model does not carry (none is expected; any is listed for Pete).
2. **Both screens scroll as the convention says** (testing-strategy §2.5–§2.6): `ProgramScreen` and
   `ExercisePickerScreen` are their pinned parts plus a `ScrollView` around one page view
   (`ProgramPage(model:)`, `ExercisePickerPage(model:)`); snapshots and VoiceOver trees are taken from the
   pages; no page holds a scroll view.
3. **The builder** (criteria 1–6 of the brief, drawn): the header with the program's name as a field, "BLOCK
   · 8 WEEKS" with "−" and "+", the week chips in `WrapLayout` (eight weeks make two rows), the selected
   week's schedule strip of seven cells that wraps at accessibility sizes, the week's actions, "TRAINING
   DAYS" with its helper, one card per day, "+ Add training day", and the validation message where the
   model carries one.
4. **The library sheet** (criterion 12 of the brief, drawn): `SheetChrome` with "Exercise library" and
   "Cancel", the search field, the two chip rows in `WrapLayout`, the rows with their line and the "already
   in this day" mark, a picked row shown as picked, "Nothing matches that filter." with "Clear filters", and
   the pinned foot button, disabled with "Select exercises to add".
5. **States have previews and snapshots** (the notes' snapshot table): builder: default at six cells; deload
   week selected, a day with no exercise, the two-weeks message at two each. Library: results at six cells;
   three picked, nothing matches at two each. One preview registry for the module; `Package.swift`'s
   snapshot targets and `PreviewScan.registeredModules` gain `FeatureProgram`.
6. **VoiceOver** (the notes' tables for S9 and S12): the pinned trees match them: a week chip "Week 3, 4
   days", a cell "Tuesday, rest" with its hint, the chips' short names hidden on a day card, chip rows as
   one-selected groups, a library row as a button with its line as value and the selected trait when picked
   (S8 criterion 19), the foot. Headings are headings. Every target is 44 pt.
7. **Sizes and settings**: nothing clips or overlaps at `.accessibility3`, with Bold Text, Increase
   Contrast and right-to-left; sixteen weeks and a long program name lay out.
8. **The orange audit** (decision 1 A): a test or a pinned list shows where the accent is used on each
   screen.
9. **No rule of its own**: the views use `LedgerDesign`'s components and tokens (`StepperField` is not
   needed here; `PillButton`, `WrapLayout`, `SheetChrome`, `HairlineRow`, `PrimaryButton`); a new shared
   component is proposed in the report, not added quietly.

**Not in this slice:** the Day editor's views (S10, S11), any store (S13, S14), `LedgerAppKit`, the project
file or a test plan, and any change to a presentation beyond a field a view provably needs (listed).

## Plan amendments — slice S9 after round 1 (orchestrator, 2026-10-09)

The reviewer asked for changes (one blocking fault, five should-fix items) and the tester found the same
fault wider, plus two minor ones (46 tests, six left failing; fifteen mutations). Rulings, which add to S9's
nine criteria:

10. **The schedule strip never cuts a word** (review B-1, F11-S9-1): at every text size, at 375 and 402 pt,
    with Bold Text and right to left, with the seed's tags and with ten days ("D10"), each cell draws its
    word whole. The strip is one row of seven equal cells while every cell's word fits its share, and wraps
    into rows of equal cells otherwise. At the default size on a 375 pt phone it stays one row if trimming
    the cells' inner spacing by a point or two achieves that (the miss is one point); if not, it wraps there
    and the existing test `scheduleStrip_defaultSize_isOneRowOfEqualTargets` is changed to say so. The
    tester's four tests pass unedited; the two references that pinned "RE…" are recorded again.
11. **Room at the largest sizes** (review S-2, S-3; F11-S9-2): the search field's text stands inside its
    pill at every size; a wrapped "REST" and a week chip's second line clear their outlines at
    `.accessibility3`.
12. **The search field sends only a changed query** (F11-S9-3), as the name field already does.
13. **Housekeeping** (review S-1, N-1 to N-3, N-6): the comment on the model's name says where the draft
    lives now; the day row's chevron and the section line align as Today's do; one rule above the sheet's
    foot; the unneeded hint helper goes.
14. **Accepted as built:** all views in `Views/`; the name's draft as view state (last writer wins); a
    library row on `HairlineRow`; no `EmptyState` for one sentence; `DayCard`'s tag measure stays in the
    feature until S10.

**For S13** (review S-1; tester's mutations 2, 3, 6): the UI test of the builder types a name and reads it
back, taps the drawn "−" and "+" and checks which way the block moved, and reads both fields' labels; the
store knows that a name changed from outside under an open draft is overwritten by the next keystroke.
**For S14** (review deviation 8): the model's `detail`, `inDayMark` and `pickMark` are drawn or removed
before F11 ends; the product owner chooses. **Chores, not this slice:** the hosted reader fails on (or
records) a text field, with testing-strategy §2.5 saying so (review S-4); icons that must not mirror right
to left, the check mark first, in `LedgerDesign` (review S-5; the set row has it too); `SectionLine` and a
public press style in `LedgerDesign` before S10; the reference precision on long pages (tester's note 1:
three visible mutations passed every reference at 0.995).

## Plan amendments — slice S10, the Day editor's and the slot editor's views (orchestrator, 2026-10-10)

The plan's S10 and S11 as one pull request (larger batches; the number S11 is not used again). Cut from
`main` at release 0.10.0, which holds the Day editor's presentation (S6), the form controls (S8) and the
builder's views (S9). Views drawn from a model only: no store, nothing in the app (S14 puts it there).
About 580 product lines planned (the plan's S10 and S11 rows list the files); views have landed close to
plan; past about 800 the implementer stops and reports. Pete's decision 1 stays at its default A. The
notes' "Inputs for the views (S10, S11)" and "Inputs for S10 and S11" are part of this contract. The slice
is accepted when:

1. **Drawn from the model only.** Every view takes its part of `DayEditorModel.Content` and
   `(DayEditorAction) -> Void`; it builds no action but the name field's `rename`, decides nothing that is
   shown, formats no number and reads no clock, calendar or locale. Every text on screen is a string of the
   model; a lookup the model does not carry is not expected, and any is listed for Pete.
2. **The screen scrolls as the convention says** (testing-strategy §2.5–§2.6): `DayEditorScreen` is its
   pinned header plus a `ScrollView` around `DayEditorPage(model:send:)`; snapshots and VoiceOver trees are
   taken from the page and the header; the page holds no scroll view.
3. **The files live in `FeatureProgram/Views/`** (S9's deviation 1 is the rule now); the folder scans of
   earlier testers (`DayEditorWordsAdversarialTests` reads `DayEditor/`, `ProgramViewsSourceTests` reads
   `Views/`) pass unedited except for adding the new screen file to `screens`.
4. **The header**: the back control, `header.position` ("DAY 1 OF 4"), "Done", the day's name as a text
   field bound to a draft (S9's `ProgramHeader` rule: seeded from `header.name`, sends `rename` with the
   text as typed, does not take the stored name back while focused), `header.tag` drawn, the summary line.
5. **The page, closed**: per `Group`, the superset header once above its rows where it is not nil, the rows
   as one visual block; a row with its code, name, scheme, load where not nil, and a caret by `isOpen`;
   "+ Add exercise"; "Delete day" presenting the confirmation from `deleteDay.confirmation`, whose "Cancel"
   sends nothing.
6. **The panel, open** (drawn from `row.panel` and nothing else, inside the row's block): the week line;
   one `StepperField` per field; "PROGRESSION" with its chips in `WrapLayout`, the selected one not a
   button, and its note; the drop set as `.toggleStyle(.ledger)` with its note; the superset actions; "Move
   up", "Move down", "Remove"; the week strip. A control the model does not carry is not drawn (`details ==
   nil`, an empty `supersetActions`, a nil move).
7. **A stepper is drawn with `label` and `value`** and is one adjustable element to VoiceOver with
   `spokenLabel` and `value` (the plan's default; the other reading of decision 1 is listed for Pete with
   a screenshot, not built).
8. **Colour**: only the facts the notes name pick the accent (`WeekLine.isDeload`/`isHeld`,
   `Entry.isDeload`/`isHeld`/`isShown`, `DropSet.isOn`, `Row.isOpen`); no view splits `week.eyebrow` or
   `strip.text`. An orange audit, as S9's, pins where the accent is on this screen, and its list is given
   to Pete.
9. **States have previews and snapshots** (the notes' snapshot table, rows S10 and S11): all closed at six
   cells; a day with a superset, open double, drop set on at two each; open linear at six; plus the deload
   week once. `ProgramPreview` gains `.dayEditors`; one registry for the module.
10. **VoiceOver** (the plan's tree, notes line 571 on): `header.position` a heading; the name field
    labelled `header.nameLabel` (pinned as `ProgramTextFieldTests` does, since the hosted reader does not
    see a text field); a superset header a heading with label `spokenLabel` and value `note`; a row a
    button with `spokenLabel`, `spokenValue` and its open or closed state; each stepper adjustable, its
    two actions sent by decrement and increment; the chips a one-selected group; the drop set a switch
    with `note` as hint. Every target is 44 pt.
11. **Sizes and settings**: no word is cut and nothing overlaps at the twelve text sizes on 375 and 402 pt,
    with Bold Text, Increase Contrast and right to left; a long exercise name and a long day name lay out.
    Truncation is checked by measurement (S9's cut-word checks), not by a reference image alone.
12. **Each control sends exactly its model's action, once**: pinned by a test that walks the page.
13. **No rule of its own**: `LedgerDesign`'s components and tokens, the feature's `SectionLine` and
    `ControlPill` (generalised if the Day editor's control type needs it, not copied). A new shared
    component is proposed in the report, not added quietly.

**Not in this slice:** any store (S13, S14), the exercise library sheet's presentation from the Day editor,
`LedgerAppKit`, the project file or a test plan, the chores queued after S9 (`SectionLine` into
`LedgerDesign`, the reader and a text field), and any change to a presentation beyond a field a view
provably needs (listed).

## Plan amendments — slice S10 after round 1 (orchestrator, 2026-10-10)

The reviewer asked for changes (one blocking item, four should-fix) and the tester left one test failing
(`smallPhone_headerIsNotSqueezed`) and two questions as known issues. Rulings, which add to S10's thirteen
criteria:

14. **Only the bar is pinned.** `DayEditorScreen` pins the row "Program … Done" alone; the title block
    (`header.position`, the name field, `header.tag`, the summary line) is the first thing in
    `DayEditorPage` and scrolls with it. Criteria 2 and 4 and the plan tree's "Pinned:" list are amended to
    this. The pinned bar keeps its own height on every screen: it is never squeezed (review B-1 step 2,
    tester F11-S10-2).
15. **The day's name is drawn whole at every text size** on 375 and 402 pt, plain and bold, for the four
    seed day names and the long name: it wraps onto further lines while it is not being edited. The
    one-line `TextField` is kept (a field with a vertical axis is a `UITextView`, which the hosted reader
    refuses and the source test bans); a wrapping `Text` of the draft is drawn while the field has no
    focus, hidden from accessibility and from hit testing. The layout must not jump the keyboard's target
    off screen at the moment focus arrives.
16. **One `NameField` in `Views/`** holds the draft rule and this wrapping, used by the Day editor's title
    block and by `ProgramHeader`, so that a long program name wraps too. Of S9's references only those
    whose name wraps may change; if any other changes by a pixel, `ProgramHeader` stays as it is and the
    implementer reports.
17. **Stepper labels are "Sets", "Reps", … in the small grey label style** (decision 1 A's own words win
    over criterion 7): `spokenLabel` is drawn, and the then redundant `.accessibilityLabel` goes (review
    S-1). The tree stays one adjustable element with that label and `value`.
18. **The week's eyebrow uses `Eyebrow`** with its tint (review S-4).
19. **The cut-word sweep is thinned** (review S-2): the wide drawing once per part, size, weight and
    direction; right to left at four sizes; in `words_otherStates_areDrawnWhole` only the open row and its
    panel's parts. The title is swept under the four seed day names and the long name, not "Arms";
    `dayName_isCutInItsOneLineField` goes. Target: `DayEditorLayoutTests` under about 50 s on the simulator.
20. **Not changed, recorded for the product owner or later slices:** a one-word exercise name breaking
    across lines at `.accessibility4` and above (tester F11-S10-4); `.alert` against F10's dialog for
    destructive questions; "Remove" looking like "Move down"; "Program" and "Done" sending the same action;
    the empty band between two exercises; `row.hasDropSet` removed in S14; for S14: `.id(model.id)` or a
    new screen per day (the draft, the focus and `isConfirming` are keyed by place), and `rename` applied
    synchronously by the store.

## Plan amendments — slice S10 after round 2 (orchestrator, 2026-10-11)

The reviewer's second pass found one blocking item (B-2) and two smaller ones (S-5, S-6); the tester's second
round closed round 1's two findings, left two tests red on purpose (F11-S10-5, F11-S10-6) and refuted S-5
and S-6 by measurement. Rulings, which add to the twenty before:

21. **The name stands clear of the tag at every text size** (tester F11-S10-6, review B-2): no descender of
    the name's last line, wrapped or one line, reaches the tag's pill, at all twelve sizes on 375 and 402 pt,
    plain and bold; `name_standsAboveTheTag` passes unedited. The gap under the name is a spacing token, no
    literal points. *As built and accepted:* the token stands outside the field, in `DayEditorHeader` (`xs`
    and `s` under the name), because room inside `NameField` turned four of the tester's other tests red;
    the name does not move, everything under it moves down 8 pt.
22. **Under the focus the name's descenders are cut, and that is not fixed in this slice.** The field's frame
    is the title role's line height, which is `LedgerDesign`'s; no change of a view makes it higher
    (measured), and `ProgramHeader` on `main` clips the same way. The fix is a design-system change and
    belongs to the queued chore, with `ProgramHeader` adopting `NameField` and the re-recording of its
    references. `focus_doesNotCutTheDescenders` is left as it is, red, until the tester marks it a known
    issue that names the chore. The notes hold the chore's input in full.
23. **Review S-5 is refuted by measurement** (the bar is rigid: 60.0 / 61.3 / 70.3 pt alone, in the parts and
    on screen). The screen's `.fixedSize(vertical:)` on the bar goes if `bar_isNeverSqueezed` stays green
    without it.
24. **Review S-6 is refuted as written** (an emptied draft moves the rows below by 2.3 to 2.7 pt at
    accessibility sizes, inside the gap; nothing overlaps). Nothing is built for it.
25. **Stale comments are corrected:** `DayEditorAccessibilityTests.swift:15`, `DayEditorSnapshotTests.swift:8`,
    `DayEditorLayoutTests.swift:40-41`, and `NameField.swift:4-5`, which said it serves the builder.
26. **Recorded for S14 and the product owner, not built:** a draft of only spaces shows neither letters nor
    the placeholder; while being edited a name is one line and runs out of the field from `.xLarge` on 375
    pt; that a tap on the name gives it the focus, and that the drawn text follows the draft while typing,
    are for S14's UI tests.

No tester file is edited in this round.

## Plan amendments — slices S13 and S14, the builder's stores and the Program tab in the app (orchestrator, 2026-10-18)

The plan's S13 and S14 as one pull request on `feat/F11-s13-stores` (larger batches; the product owner's
rule of 2026-10-08). Cut from `main`, which holds every presentation (S5, S6, S8), every view (S9, S10), the
editing rules (S1) and the atomic update (S3). This is the slice that puts the three screens in the app at
once: before it the Program tab shows #28's placeholder (notes:65-67), after it every button of the builder,
the Day editor and the library leads somewhere. The notes' "Inputs for S13 and S14" (notes:1654-1711), "Inputs
for S13" (notes:2200-2227, 2341-2350), "Inputs for the stores (S14)" (notes:2802-2833, 2943-2946), "Inputs for
S14 (the library's store)" (notes:3325-3346) and the two "Inputs for S13 and S14" of the views (notes:4176-4192,
5047-5068, 5236-5240) are part of this contract; where they and this section differ, this section wins.

**What S13 is.** The edit session and the builder's store, with no change to what the app shows:
- one save loop over `ProgramRepository.update` (S3) that a store's synchronous intents feed (brief:121-124;
  notes:305-333), so the first edit is written at once and edits made meanwhile go together in the next write;
- each queued edit reaches the stored program exactly once (brief:196-199, 314-320; notes:1241-1256), and a
  write whose task is cancelled stores all or nothing (S3 criteria 8 and 12, brief:233-234, 248-252), which
  ruling R1 below turns into what the store does;
- `ProgramStore`: the program as stored with the waiting edits on top, the selected week (behaviours 1 and
  2), the logged weeks read again before "−" is written (brief:328-332), the notice, the name applied as typed
  (brief:333-334, 579-581), routes; `ProgramRoot`, public, with its empty and failed states (decision 6's
  texts, notes:452-463).

**What S14 is.** The Day editor's and the library's stores, and the app:
- `DayEditorStore` on the same session, `ExercisePickerStore` beside it, `DayEditorRoot` (public, pushed,
  presenting the library sheet);
- in `LedgerAppKit`: `AppDestination.day`, `Routes+Program.swift`, the Program tab drawing `ProgramRoot` in
  place of its placeholder, Today's "Edit week" handed to the builder with its week (notes:979-981);
- navigation builder → Day editor → library sheet, with `.id` per day so a draft, a focus or a confirmation
  never outlives its day (brief:682-684; review:1400-1403);
- the clean-up owed to S14: `row.hasDropSet` and `Field.label` removed (brief:682; notes:5236), S9's
  `detail`, `inDayMark` and `pickMark` drawn or removed (brief:582-583, Question 4);
- the nightly UI tests no hosted test can be (brief:503-505, 579-581, 711-714; notes:4191-4192, 5063-5067).

**Not in this slice:** any change to `LedgerDomain` or `LedgerPersistence`; the project file and the test
plans (flagged below, for a human); F12's custom exercise form; F15's `program_edit_reflects_on_today`.

### Store conventions (the M1 convention as `TodayStore` and `WorkoutStore` hold it on `main`)

- Every store is `@MainActor @Observable final class`; its initializer is empty, so `@State` keeping the
  first store costs nothing (`TodayStore.swift:42-43`, `WorkoutStore.swift:26-27`). The roots take a store
  in an internal `init` for the tests (`TodayRoot.swift:30-41`).
- Intents are synchronous and only change state: an edit is applied to the program on screen and the model
  rebuilt before the intent returns; nothing waits inside an intent.
- All async work runs from the root's `.task`s and ends with them: the stores' observation `run()`, the
  session's save loop, the route hand-over (`TodayRoot.swift:44-53`, `WorkoutRoot.swift:55-67`). No
  unstructured `Task {}`, no `Task.detached`, no `DispatchQueue`, no `Timer`, no `TimelineView`, no
  `.formatted(` (standards §4, §11; architecture:325).
- Time, ids and the locale are injected (`\.date`, `\.uuid`, `\.calendar`, `\.locale`); the logger is the
  injected one under the category `"program"` (standards §8).
- Every lookup is in `ProgramCopy*.swift`; a counted text passes `locale.forCountedText`
  (`ProgramCopy.swift:28-33`); the stores and roots hold no literal a lifter reads or hears.
- No clamp, coupling or schedule rule in a store (brief:97): only `ProgramEditing`, `DayEditing` and the
  presentations decide.

### Acceptance criteria

**The edit session (S13).**

1. **One session, one loop.** `ProgramEditSession` holds the program as last stored (observed, or returned
   by `update`), the edits not stored yet in order, and whether a write runs. The program on screen is the
   stored one with the waiting edits applied in order. `enqueue` is synchronous. `run()`, started from the
   root's `.task`, is the one loop: it takes every waiting edit, calls `update(id) { edits.reduce($0) { try
   $1.applied(to: $0) } }` once, and goes round while edits wait. Pinned with no clock and no sleep:
   `edit_isSavedAtOnce_andEditsMadeMeanwhileGoTogether` (the probe holds the first `update`, three more edits
   arrive, it is released: two calls, and the stored program equals the one on screen).
2. **The closure holds values only.** It is `@Sendable`, captures the array of edits and nothing of a store,
   calls no repository, and applies the edits to its argument, never to a copy the store holds
   (notes:1671-1679). Pinned by S3's losing sequence driven through the store, on the in-memory stores and
   on GRDB: read; a workout's save writes a miss and a swap; a builder edit is written; both are kept.
3. **Exactly once, drawn once.** When `update` returns, the store adopts the program it returns and drops
   exactly the edits it sent, in one synchronous step. An emission of the stored program that arrives while
   a write runs is not drawn under the edits in flight: it is kept aside and the returned program wins
   (review:914-917). Pinned with the emission delivered before the call returns, for `.removeLastWeek` and
   for a move (a double that stores, emits and then holds its return; `LedgerTestSupport` gains it if
   `ProbedStores` cannot do it).
4. **An edit that changes nothing is not queued** (review:1223-1224): when `edit.applied(to: shown) ==
   shown`, nothing is written (a stepper at its limit, a rename to the stored name, a cell with no day).
5. **A write that fails** (any error but the cancellation of criterion 6): every waiting edit, sent or not,
   is dropped; the screen is drawn from the stored program; one line says so (criteria 12 and 22); the error
   is logged. The store never calls `save` to recover (review:543-544). `saveFails_showsTheStoredProgramAndSaysSo`;
   a failure, then an edit that is stored normally.
6. **A write whose task is cancelled** (ruling R1). `CancellationError` thrown while the task is cancelled
   means nothing was stored (S3's table, notes:1531-1572): the sent edits go back to the front of the waiting
   edits and nothing is shown as failed; the next `run()` sends them, once. A call that returns although its
   task was cancelled stored everything: its edits are dropped. Pinned with `TaskCancelSwitch` and with a held
   probe whose task is cancelled: `viewGoesAwayDuringASave_storesAllOrNothing`, then a new run stores the
   edits and an added week is added once.

**The builder's store and root (S13).**

7. **Sources.** `ProgramStore.run()` follows the active program, the settings, the exercises and the
   recent workouts in one task group, as `TodayStore.run()` does; the model is made once every source has
   spoken. No active program gives the empty state, and an observation that ends gives the failed state,
   with decision 6's texts (`noActiveProgram_showsTheEmptyState`, `streamEndsBeforeAValue_showsFailed`). Once
   loaded it is never loading again. A workout saved meanwhile is shown under the waiting edits
   (`storedProgramChanges_isShown`, behaviour 15).
8. **The logged weeks** are read as "How a week is known to have logged sessions" says (notes:224-239): on
   every run, whenever the recent workouts change, and by the loop before a write that holds
   `.removeLastWeek`, whose `loggedWeeks` the loop replaces with the fresh set (brief:328-332). A workout
   finished in the last week between the tap on "−" and the write removes nothing and shows "Week 8 has
   logged sessions and can't be removed." (ruling R4 for the rest of that write).
9. **The selected week** (behaviours 1 and 2). The first model selects `WeekCalendar.weekIndex(for:)` of the
   injected date, handed in raw; a week asked for through `ProgramRoot(week:)` wins, and a new request while
   the root is alive selects it again. "+" selects the week it added, read from the program the edit was
   applied to (review N-1, notes:2255); after "−" the selection is kept raw (notes:2168-2170).
   `firstLoad_selectsTheWeekThatHoldsToday`, `requestedWeek_isSelected`, `removeWeek_keepsTheSelectionInsideTheBlock`.
10. **Actions as the table says** (notes:1866-1876): ids for `.addWeek` and `.addDay` are drawn from
    `\.uuid` once, at the tap; the model is rebuilt before the next intent, so two quick "+" add two weeks.
    The worked examples of the brief's criteria 2 to 6 are driven through the real store (review N-8), and
    `removeWeek_atTwoWeeks_showsTheMessage_andChangesNothing` holds.
11. **The name.** `.rename(text)` is applied at once, so `header.name` follows the typing; the store keeps no
    draft (S9 ruling 14: the draft is the view's). "Upper Lower" sent letter by letter stores "Upper Lower";
    ten letters against a held probe are two writes (Risks 7, notes:652-653); a blank text stores nothing. A
    name changed from elsewhere under an open draft is overwritten by the next keystroke (brief:581), said in
    the store's comment and pinned at the store.
12. **Notices.** Replaced by an action that carries one, dropped by every other edit and by `.selectWeek`
    (behaviour 6). A failed write shows "That change wasn't saved. Try again." in the same line, as a new
    `ProgramBuilderNotice` case with its copy. The root announces a notice to VoiceOver when it appears or
    changes (notes:4185-4186; review:908-909).
13. **Routes.** One route waits at a time and is handed on by the root's `.task(id:)`, then forgotten
    (`TodayStore.send`/`deliverRoute`). `.addDay`'s route is emitted only once the write holding the new day
    has returned (notes:325-327), so the Day editor never opens on a day the store does not hold yet; a
    second tap on "+ Add training day" while that route waits adds nothing; a failed write emits no route.
    `route_isEmittedOnce_afterTheSaveReturned`, `addDay_doubleTap_addsOneDay`.
14. **`ProgramRoot`** is public: `ProgramRoot(week:onRoute:)`, owning its store in `@State`, drawing
    `ProgramScreen(model:send:)` when loaded and `EmptyState` for the empty and failed states; its tasks run
    the store and the session. `ProgramRootTests` on the in-memory stores, with no sleep.

**The Day editor's and the library's stores (S14).**

15. **`DayEditorStore`** fills `DayEditorInput` and applies `DayEditorAction` exactly as notes:2802-2833
    say, on the same session type with `DayEditorEdit`: `.open` and `closesPanel` set the open slot, which
    needs no repair; a stepper's edit carries the value the model was built with, and the model is rebuilt
    before the next intent, so two quick taps on "+" are two steps (notes:2815-2819); the drop-set switch and
    every edit are applied synchronously (notes:5060-5061).
16. **The day is gone.** `.closeDay` is emitted once when the model is `.dayIsGone`, judged only after the
    first stored program has arrived: after "Delete" and when the day is deleted elsewhere
    (`dayRemovedElsewhere_closesTheEditor`).
17. **Leaving waits for the write.** "Done", "Program" and the day being gone hand `.closeDay` to the app
    only once no edit waits and no write runs; a write that fails drops the route and shows the Day editor's
    failure (Question 1). The system's swipe back pops at once; a write in flight then is cancelled whole
    (ruling R5), pinned by `viewGoesAwayDuringASave_storesAllOrNothing` for the Day editor.
18. **One screen per day.** Each `.day` route pushes its own `DayEditorRoot`, whose store is fixed to the
    route's day, and the root's content carries `.id(day)` (ruling R8): pushing day B where day A stood never
    shows A's draft, focus or delete confirmation, and the first keystroke renames B.
19. **`ExercisePickerStore`** is owned by the Day editor's store and lives as long as the Day editor, so the
    two chips are kept between openings (behaviour 14); it fills `ExercisePickerInput` with the day's
    exercises from the program on screen and applies every action synchronously (`.setQuery` included,
    notes:4187-4189). `.add(ids)` builds the slots with `DayEditing.newSlot` and ids from `\.uuid` at the tap,
    skips an exercise that has gone and logs one whose `newSlot` throws, queues one `.slot(.add(slots), day:)`,
    empties the query and the picks, keeps the chips and closes the sheet; `.cancel` does the same and adds
    nothing (notes:3325-3346). `add_appendsInPickOrder_andKeepsTheFilters`,
    `clearFilters_resetsQueryMuscleAndEquipment`, `customExerciseSavedWhileOpen_appears`.
20. **`DayEditorRoot`** is public, takes the route's day and week and `onRoute`, hides the navigation bar and
    keeps the swipe back (notes:5051-5052), presents `ExercisePickerScreen` with `.sheet` on `.openLibrary`
    (a swipe down sends `.cancel`), and shows "Delete day" and a failed write as Questions 1 and 3 settle.
    `DayEditorRootTests`.
21. **The clean-up.** `DayEditorModel.Row.hasDropSet` and `SlotEditorModel.Field.label` are removed, with any
    copy member and catalog key only they used; S9's `detail`, `inDayMark` and `pickMark` as Question 4
    settles. The gate's catalog step passes with no exemption.

**The app (S14).**

22. **Destinations and routes.** `AppDestination.day(DayTemplateID, weekIndex: Int)`; `Routes+Program.swift`
    maps `ProgramRoute.day` to `open(.day(…), in: .program)` and `.closeDay` to popping the Program stack's
    top when it is a `.day` (a second `.closeDay` pops nothing). `ProgramRouteMappingTests` in
    `LedgerAppKitTests`.
23. **The Program tab** draws `ProgramRoot`; the destination draws `DayEditorRoot`; Library and History keep
    `PlaceholderScreen`. Today's `.editWeek(program:weekIndex:)` selects the Program tab, pops its stack to the
    builder (Question 2) and selects that week (ruling R10); `.openProgram` and `.setUpProgram` select the
    tab only. `TodayRouteMappingTests` are updated for `.editWeek`.
24. **Nightly UI tests** in `Apps/LedgerUITests` (new files; the `PR` plan selects `Smoke` only), each with
    screenshots attached:
    a. the builder: a name typed letter by letter with a space in it is read back; a finger on the drawn "−"
       and "+" moves the block's length the right way; both name fields' spoken labels ("Program name", "Day
       name") are read (brief:579-581);
    b. a tap on a wrapped name gives it the focus, the drawn text follows the draft while typing, and a draft
       of only spaces shows as Question 5 settles (brief:711-714);
    c. the Day editor: a finger on a row (VoiceOver's "expanded" and "collapsed"), on a stepper's "−" and "+"
       (one step each), a progression chip, the drop-set switch, and the delete alert's two buttons
       (brief:503-505; notes:5064-5067);
    d. the library: a query typed, a chip tapped, three exercises picked and added;
    e. `Builder.addDayAddExerciseChangeProgression` (testing-strategy:308);
    f. the stops inside the real scroll views at an accessibility size (notes:4191-4192).
    The DoD's screenshots of the builder and the Day editor at the default size and at AX5 (brief:99) are
    taken on the simulator and put on the pull request (notes:594).
25. **The tab shell's tests follow.** `Tabs.swift` and `TabsAdversarial.swift` find the Program tab by its
    placeholder's `program.title` and the label "Program"; they are edited to find the builder (a sanctioned,
    audited edit of a tester's file, listed in the notes). `ShellSnapshotTests` keep rendering the
    placeholder type, which stays.

**Throughout.**

26. **The conventions above hold, by test.** `FeatureProgramSourceTests` covers the new files: no `Task {`,
    `Task.detached`, `Timer`, `TimelineView`, `.formatted(`, `DispatchQueue`, `Date()`, `Calendar.current`,
    `Locale.current`; no lookup outside `ProgramCopy*.swift`; the clamp tripwire reads the session and the
    stores. The hosted tests and `ModuleCopyTests` pass with no exemption; coverage does not decrease and
    `FeatureProgram` keeps its threshold.
27. **Budgets** (brief:85), measured by a `.performance` suite (ruling R12): the builder's first model at 16
    weeks × 6 days under 100 ms, a slot edit to the next model under 16 ms, a keystroke's library model over
    the 224 exercises under 10 ms.
28. **The attacks the plan names** (notes:606) each have a test: an `update` held while edits arrive; a
    workout saved between two edits, on GRDB; the view going away during a save; a route emitted twice; a
    failure, then a success; the day deleted under the Day editor; a double tap on "+ Add training day".

### Product lines, estimated

Counted by standards §10 (code only; not tests, `LedgerTestSupport`, catalogs, docs or comments).

| Part | File | Lines |
|---|---|---|
| S13 | `FeatureProgram/ProgramEditSession.swift` (the session, its loop, and the small protocol both edit types conform to) | ~120 |
| S13 | `FeatureProgram/ProgramStore.swift` (state, intents, the model) | ~150 |
| S13 | `FeatureProgram/ProgramStore+Sources.swift` (the four observations, the logged weeks, the week that holds today) | ~90 |
| S13 | `FeatureProgram/ProgramRoot.swift` (tasks, routes, the empty and failed states, the announcement) | ~70 |
| S13 | `FeatureProgram/ProgramCopy+States.swift` and `ProgramBuilderAction.swift` (+1 notice case) | ~35 |
| S14 | `FeatureProgram/DayEditor/DayEditorStore.swift` | ~160 |
| S14 | `FeatureProgram/Picker/ExercisePickerStore.swift` | ~80 |
| S14 | `FeatureProgram/DayEditor/DayEditorRoot.swift` (tasks, the sheet, the bar, the failure, `.id`) | ~90 |
| S14 | `LedgerAppKit/Routes.swift` (+`.day`, the requested week), `Routes+Program.swift`, `Routes+Today.swift`, `AppTabs.swift`, `MainRoot.swift` | ~65 |
| S14 | Removals (`hasDropSet`, `Field.label`, possibly S9's three fields) | about −15, not counted |
| | **Total** | **~860** |

Inside the ~700–900 band and under the 1,000-line split line, so one pull request. Store slices have run
above plan before (S6: 720 planned, 1,007 landed; F09's presentation: 570, 808). **Past about 950 the
implementer stops and reports.** The split, if needed, is at the seam the plan drew: S13 alone (the session,
the builder's store and root, ~465, nothing in the app, cut and merged first), then S14 from `main` (~395).
No stacked pull requests.

### Dependency: the chore #60 lands before S14

Pull request #60 (`chore/name-field-line-height`: `ledgerFieldFont` in `LedgerDesign`, `ProgramHeader` on
`NameField`, S9's references recorded again) must merge before S14 puts the screens in the app, since that is
when a lifter first types in these fields (review:1706-1709; brief:698-702). S13 does not depend on it and
does not touch `ProgramHeader`. The implementer may build S13 at once; before S14's part starts, `main` (with
#60) is merged into the branch. If #60 has not merged by then, the implementer stops and reports. Criteria
that depend on #60: **14** in so far as the builder's header is drawn by `NameField`, **18** (the name field's
draft keyed by day), **20**, **23** (the builder drawn in the tab), **24 a and b** (typing a name, the wrapped
name's focus and the blank draft), and the DoD's screenshots.

### Project file and test plans (human-owned: flagged, not planned)

- **No `project.pbxproj` change**: the new UI test files go into `Apps/LedgerUITests`, a synchronized folder
  (standards §1; ADR-003). Every product file is in `LedgerKit`.
- **No test-plan change is required**: the `Nightly` plan runs all of `LedgerUITests` and the `PR` plan
  selects `Smoke` (`TestPlans/PR.xctestplan:154-162`).
- **One optional edit, if ruling R12 is taken**: a `.performance` suite is skipped in the PR plans by name
  (testing-strategy:435-438, :564), so `PR.xctestplan` would gain `ProgramPerformanceTests` under
  `skippedTests`. That is Pete's edit in Xcode, or the orchestrator's by hand if the plan's JSON is ruled
  editable; until then the suite stays out.

### Questions for Pete

1. **When a change in the Day editor can't be saved.** The builder shows one line under the block ("That
   change wasn't saved. Try again."). The Day editor has no such line.
   - A: an alert with that sentence and "OK"; the Day editor shows the program as stored. *Recommended.*
   - B: the same sentence as a line under the Day editor's header, until the next change.
   - By default: A.
2. **"Edit this week" on Today while a Day editor is open in the Program tab.**
   - A: the Program tab goes back to the builder, with that week selected. *Recommended* (the prototype's
     "Edit this week" always lands on the builder).
   - B: the Day editor stays on top; the builder underneath has the week selected.
   - By default: A.
3. **"Delete day" asks in an alert, the workout's questions in a dialog** (S10 ruling 20).
   - A: keep the alert: it shows "Cancel" (an iOS 26 dialog draws none). *Recommended.*
   - B: a dialog from the bottom, as "Finish workout" is, cancelled by tapping outside.
   - By default: A.
4. **"already in this day" in the library.** The brief draws it in orange; your decision 1 A makes it grey,
   and today it is drawn as the end of the grey line ("Machine · Back · already in this day").
   - A: keep it as it is drawn, and remove the three unused fields behind it. *Recommended.*
   - B: draw the words apart, in orange, as the brief says (orange twice on that sheet).
   - By default: A.
5. **A name emptied to only spaces** shows neither letters nor the placeholder while being edited.
   - A: show the placeholder ("Program name", "Day name") whenever the name is blank. *Recommended.*
   - B: leave it.
   - By default: A.

### Rulings needed from the orchestrator

- **R1. A cancelled write: keep its edits, or drop them.** The S1 ruling says that after an `update` that
  "failed or was cancelled" the waiting edits are dropped (brief:196-199). S3 then established that a
  cancelled `update` throws `CancellationError` only when it stored nothing (notes:1531-1572), and its inputs
  say "keep the waiting edits and send them again" (notes:1681-1683). *Recommendation:* keep them on that
  error (they never reached the store, so sending them again is their first and only arrival), drop them on
  every other failure; amend brief:196-199 to say so. Dropping them would lose every edit made just before a
  tab switch, against criterion 13 of the brief.
- **R2. The save loop: a wake stream, not a ticket.** The plan runs the save from `.task(id: saveTicket)`
  (notes:311-316). *Recommendation:* one `run()` from a plain `.task`, woken by an `AsyncStream` that keeps
  only the newest signal, as `WorkoutStore.pump()` does on `main` (`WorkoutStore+Pump.swift:41-50`): no
  ticket to keep right, and a write is never cancelled by a change of id.
- **R3. One session type for both stores.** *Recommendation:* `ProgramEditSession<Edit>` over a protocol
  both edit types conform to (`applied(to:) throws -> Program`; the Day editor's never throws), rather than
  two copies of the loop. The notes leave it to the store (notes:2811-2814).
- **R4. "−" refused at the write, inside a batch.** The notes drop the whole write and show the notice
  (notes:2218-2222); the S1 review would skip the refused edit and keep the rest (review:281-283).
  *Recommendation:* the notes': it can only happen when a workout finished in the last week since the tap,
  the lifter sees the notice and the stored program, and a skip would be the store deciding what an edit
  means.
- **R5. A swipe back during a write.** *Recommendation:* accept that a write in flight at the swipe is
  cancelled whole (milliseconds on a local database); "Done" and "Program" wait for it (criterion 17). The
  alternative, one session per Program tab owned by `AppTabs` and run from a task on its stack, loses
  nothing but moves a store's work into the app shell and breaks ruling 3 of 2026-10-05.
- **R6. Emissions during a write** (criterion 3): kept aside and the returned program adopted. Needs a
  probe in `LedgerTestSupport` that stores, emits and then holds its return, if `ProbedStores` has none.
  *Recommendation:* add it there (support code, not counted).
- **R7. An edit that changes nothing is not queued** (criterion 4, review:1223-1224). *Recommendation:* yes;
  it spares a write per tap at a limit and needs no rule of the store's own (an equality).
- **R8. `.id(day)` as well as a screen per route** (brief:682-684). *Recommendation:* both: each route is its
  own destination value and its own store, and `.id` costs one line against SwiftUI reusing a view at the
  same place in the stack.
- **R9. The library's store** is a class of its own owned by the Day editor's store (criterion 19), not state
  inside it and not made with the sheet. *Recommendation:* as written; it keeps the chips for as long as the
  Day editor stays open.
- **R10. How the requested week reaches the builder.** *Recommendation:* the router keeps the request beside
  its paths, with a number that tells two taps on the same week apart (as `TodayPendingRoute`), and
  `AppTabs` passes it to `ProgramRoot(week:)`, which selects it when it changes (notes:979-981).
- **R11. The tester's tab tests** (criterion 25) are edited by the implementer as a sanctioned, audited edit,
  or by the tester first. *Recommendation:* the implementer, listed in the notes, as S3 did with its doubles.
- **R12. The budgets' suite** (criterion 27) needs the PR plan's `skippedTests` (flagged above).
  *Recommendation:* build it tagged `.performance` and have the plan edited; if the edit cannot be made in
  this slice, the suite waits and criterion 27 is measured by hand and written in the notes.

### Rulings before G1 — slices S13 and S14 (orchestrator, 2026-10-18)

- **R1–R11 as recommended above.** R1 amends lines 196–199: a write that throws `CancellationError` (it stored
  nothing, per S3) keeps its waiting edits and sends them again; every other failure drops them and shows the
  notice.
- **R6, amended in S13 fix round 1 (F11-S13-1):** a write during which no emission was heard adopts the
  program `update` returned. A write during which one was heard trusts neither blindly (the emission may be
  older than the write, or newer: a workout saved after the commit and before the return): the session reads
  the stored program once, inside its loop, and adopts that; a read that fails leaves the returned program.
- **R12:** no test-plan edit in this slice (test plans are human-owned). Criterion 27 is measured by hand and
  written in the notes; the `.performance` suite is not built.
- **Questions for Pete 1–5:** built to their defaults (A in each) until he answers; each is S14's, so S13 does
  not wait. A different answer is a fix round before the PR.
- **Order:** S13 first. S14 starts only after #60 is on `main` (merge `main` in first); if #60 has not merged
  when S13 is done, stop and report. Past about 950 product lines, stop and report (split at S13 | S14).
