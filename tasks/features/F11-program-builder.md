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
