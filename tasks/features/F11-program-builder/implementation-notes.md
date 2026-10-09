# F11 — implementation notes

Planning pass against `main` at `4d35069` (2026-10-05). Read-only: nothing below has been built or run. No test
was executed for this plan; every statement about behaviour is read from the source at the line given.

How paths are written. A path that starts with a module name (`LedgerDomain/…`, `LedgerPersistence/…`) is under
`LedgerKit/Sources/`. A path that starts with `Tests/` is under `LedgerKit/`. Every other path is from the
repository root. A file that exists only on a waiting branch is written `branch:path:line`, with the branch
shortened: **#28** is `origin/feat/F09-s1-tab-shell` (pull request #28, the tab shell and the localization
rule), **F08 branch** is `origin/feat/F08-s3-root-gate` (it contains #28 and all of F08), **F09 branch** is
`origin/feat/F09-s3-presentation`. "The brief" is `tasks/features/F11-program-builder.md`, "the spec" is
`docs/product-spec.md`, "v1" is `design/prototype/Ledger.dc.html`.

Two words are used in one sense only. A **block** is the training block, the program's run of weeks; the run
of exercises joined as a superset, which the brief also calls a block, is a **superset group** here. The
**library sheet** is the brief's exercise picker, the sheet titled "Exercise library"; the Library tab (F12) is
always named in full.

Where the prototype draws these screens (v1): the Program builder's markup is lines 92–163; the Day editor's is
224–357, of which 311–356 is the exercise library sheet. The script that drives them: superset grouping 844–848;
the chip lists 898–899; the prescription 969–987; set counts, minutes and the rest label 1095–1098; the field
steppers, start load and progression 1099–1118; superset and drop toggles 1122–1123; the library's matches
1145–1148; weeks up and down 1247–1254; the builder's values 1279–1326; the Day editor's 1328–1391; the
library sheet's 1393–1428. `design/prototype/Ledger v2.dc.html` has no builder (its own list of next steps says
so at line 364; spec §9, `docs/product-spec.md:929`), so it gives the visual system only.

## Slice plan

Fourteen slices, one pull request each. Product lines are non-blank, non-comment lines outside tests,
`LedgerTestSupport`, `LedgerSnapshotTesting`, docs and string catalogs (the rule of
`docs/engineering-standards.md:258-261`). Every slice is cut from `main`; none is stacked on another slice's
branch. "After #28" means: cut from `main` once pull request #28 is merged.

**S1 to S4 can be built and merged today.** They touch different files and can run side by side. S5 to S14
wait for #28, because every one of them holds copy or uses the tab shell, and neither the String Catalog rule
nor the shell is on `main` (`LedgerKit/Package.swift:72-80` has no `defaultLocalization`; #28 adds it at
`F09-s1-tab-shell:LedgerKit/Package.swift:79`).

| Slice and branch | Contents (planned product lines) | Needs | How it is tested | Merge |
|---|---|---|---|---|
| **S1** block editing — `feat/F11-s1-program-editing` | New `LedgerDomain/Programs/ProgramEditing.swift` (~120): names, weeks (add, remove last, deload), schedule (cycle, copy previous, apply to later). New `ProgramEditing+Days.swift` (~70): add, rename, delete a day, and `updateDay` (applies a day-level change inside a program). `LedgerDomain/Errors.swift` (+8): `ProgramEditError`. **~200 lines.** | `main`. Nothing else. | `Tests/LedgerDomainTests/Programs/ProgramEditingTests.swift` (one test per worked example of criteria 2–6) and `ProgramEditingPropertyTests.swift` (seeded). 100 % line coverage of the new files. | **Today.** |
| **S2** day editing — `feat/F11-s2-day-editing` | New `LedgerDomain/Programs/DayEditing.swift` (~110): `SlotField`, new slot (rule 7), add and remove slots, progression, drop set, superset, the superset groups of a day. New `DayEditing+Fields.swift` (~110): set a field with its clamp and the reps coupling; the value one step away. New `DayEditing+Move.swift` (~60). `LedgerDomain/Model/Slot.swift` (+8: the three ranges as public constants), `Units/RPE.swift` and `Units/RestDuration.swift` (+8 each: a clamping initializer), `Rules/ProgressionRules.swift` (+12: a slot's prescription for every week), `Rules/ExerciseSearch.swift` (+55: the library's muscle chips and one combined filter). **~370 lines.** | `main`. Independent of S1 (it works on a `DayTemplate`, not on a `Program`). | `Tests/LedgerDomainTests/Programs/DayEditingTests.swift`, `DayEditingMoveTests.swift`, `DayEditingPropertyTests.swift` (seeded), additions to `Rules/ProgressionRulesTests.swift` and `Rules/ExerciseSearchTests.swift`. 100 % line coverage of the new files. | **Today.** |
| **S3** atomic program update — `feat/F11-s3-program-update` | `LedgerDomain/Protocols/Repositories.swift` (+1): `ProgramRepository.update(_:_:)`. `LedgerPersistence/Repositories/GRDBProgramRepository.swift` (+20), `LedgerFakes/InMemoryProgramRepository.swift` (+16), `LedgerDependencies/Unimplemented/UnimplementedStores.swift` (+4). **~45 lines**, plus support and test code that is not counted: `LedgerTestSupport/Engine/ProbedStores.swift`, new contract clauses, four test doubles. | `main`. Independent of S1 and S2 (the change is a closure). | New clauses in `ProgramRepositoryContract` and `WorkoutRepositoryContract+Linked` (run against GRDB and the in-memory stores), a seeded interleaving test of `update` against `materialize` on both. | **Today.** Adds a protocol requirement: see Risks 2. |
| **S4** form controls — `feat/F11-s4-form-controls` | `LedgerDesign/Components/`: new `StepperField.swift` (~75: a label, a value, "−" and "+"; one adjustable element to VoiceOver), `LedgerToggleStyle.swift` (~50), `WrapLayout.swift` (~50: children wrap onto further rows). Their cases in `Components+Previews.swift` and their gallery section (~45). **~220 lines.** | `main`. Pete's decision 1 (default stated there). No copy: the components take `String`s. | Snapshot references at the six cells of `docs/testing-strategy.md:163-166`, one pinned VoiceOver tree per component, 44 pt targets, the gallery and preview tests. | **Today.** |
| **S5** builder presentation — `feat/F11-s5-builder-presentation` | `FeatureProgram/`: `ProgramRoute.swift` (~12), `ProgramBuilderModel.swift` (~90), `ProgramPresentation.swift` (~110), `ProgramPresentation+Weeks.swift` (~70), `ProgramPresentation+Days.swift` (~60), `ProgramCopy.swift` (~130; the equipment names come with S6, the first slice that shows one: S5 review S-4), `Resources/Localizable.xcstrings`. The placeholder `FeatureProgram/FeatureProgram.swift` and its test are deleted. `LedgerKit/Package.swift:127` gains `resources`; `scripts/coverage-thresholds.json:15` gains `"FeatureProgram"`. **~470 lines.** No view. | After #28. S1. | `ProgramPresentationTests` (criterion 1 word for word, criteria 2–6 as display models), a seeded property suite, the module's catalog checks (they run by themselves once the module has a catalog). | After #28. |
| **S6** day editor presentation — `feat/F11-s6-day-presentation` | `FeatureProgram/DayEditor/`: `DayEditorModel.swift` (~80), `DayEditorPresentation.swift` (~130: header, meta, superset headers, each slot's row and sub line, the delete confirmation), `ProgramCopy+DayEditor.swift` (~110). **~320 lines.** | After #28. S2, S5. | `DayEditorPresentationTests`. | After #28. |
| **S7** slot editor presentation — `feat/F11-s7-slot-presentation` | `FeatureProgram/DayEditor/`: `SlotEditorModel.swift` (~80), `SlotEditorPresentation.swift` (~110: fields, progression chips and note, drop set, superset actions, move, remove), `SlotEditorPresentation+Preview.swift` (~60: the selected week's line and the strip of every week), `ProgramCopy+SlotEditor.swift` (~150). **~400 lines.** | After #28. S2, S5. | `SlotEditorPresentationTests` (criteria 7–11 as display models). | After #28. |
| **S8** library presentation — `feat/F11-s8-picker-presentation` | `FeatureProgram/Picker/`: `ExercisePickerModel.swift` (~50), `ExercisePickerPresentation.swift` (~90), `ProgramCopy+Picker.swift` (~120, with the muscle names). **~260 lines.** | After #28. S2, S5. Pete's decision 3. | `ExercisePickerPresentationTests` (criterion 12 as a display model). | After #28. |
| **S9** builder views — `feat/F11-s9-builder-views` | `FeatureProgram/Views/`: `ProgramScreen.swift` (~30), `ProgramPage.swift` (~60), `BlockHeader.swift` (~50), `WeekChips.swift` (~55), `ScheduleStrip.swift` (~60), `WeekActions.swift` (~40), `DayCard.swift` (~70); `Program+Previews.swift` (~60). `LedgerKit/Package.swift:67` and `LedgerTestSupport/Previews/PreviewScan.swift:9` gain the module's name. **~430 lines.** Drawn from a model only; not in the app. | After #28. S4, S5. Pete's decision 1. | Snapshots and one pinned VoiceOver tree, both from the page; preview tests. | After #28. |
| **S10** day editor views — `feat/F11-s10-day-views` | `FeatureProgram/DayEditor/`: `DayEditorScreen.swift` (~40), `DayEditorHeader.swift` (~60), `DayEditorPage.swift` (~60), `SlotCard.swift` (~80), previews (~50). **~300 lines.** Not in the app. | After #28. S4, S6. | As S9. | After #28. |
| **S11** slot editor views — `feat/F11-s11-slot-views` | `FeatureProgram/DayEditor/`: `SlotEditorPanel.swift` (~70), `SlotFields.swift` (~40), `ProgressionPicker.swift` (~45), `WeekPreviewStrip.swift` (~35), `SlotActions.swift` (~50), previews (~40). **~280 lines.** Not in the app. | After #28. S7, S10 (the panel is drawn inside `SlotCard`). | As S9. | After #28. |
| **S12** library sheet views — `feat/F11-s12-picker-views` | `FeatureProgram/Picker/`: `ExercisePickerScreen.swift` (~50), `ExercisePickerPage.swift` (~60), `FilterChips.swift` (~40), `ExercisePickerRow.swift` (~50), previews (~40). **~240 lines.** Not in the app. | After #28. S4, S8. | As S9. | After #28. |
| **S13** builder store — `feat/F11-s13-builder-store` | `FeatureProgram/`: `ProgramEditSession.swift` (~80: the stored program, the edits not yet stored, the one save loop), `ProgramStore.swift` (~160), `ProgramRoot.swift` (~50). **~290 lines.** The root exists and is tested; the app still shows #28's placeholder. | After #28. S1, S3, S9. | `ProgramStoreTests`, `ProgramRootTests`, both on the in-memory stores, with no sleep. | After #28. |
| **S14** day editor store, library store and wiring — `feat/F11-s14-day-store-wiring` | `FeatureProgram/`: `DayEditorStore.swift` (~170), `ExercisePickerStore.swift` (~90), `DayEditorRoot.swift` (~70, presents the sheet). `LedgerAppKit/`: `Routes.swift` (+3: `AppDestination.day`), new `Routes+Program.swift` (~35), `AppTabs.swift` (the Program tab draws `ProgramRoot`; the destination draws `DayEditorRoot`). **~430 lines.** This is the slice that puts all three screens in the app at once. | After #28. S2, S11, S12, S13. | `DayEditorStoreTests`, `ExercisePickerStoreTests`, `DayEditorRootTests`, `ProgramRouteMappingTests` (`LedgerAppKitTests`); nightly UI tests. | After #28. |

Notes on the plan:

- **Total.** About 4,250 planned product lines in fourteen pull requests. F09's presentation slice was planned
  at about 570 lines and its files on the F09 branch count 808 by the same rule, so the estimates of S5 to S8
  are the ones to watch: if S5 lands above about 650, S6 to S8 are estimated again before they start.
- **What runs side by side.** Today: S1, S2, S3 and S4. After #28: S5 alone first (it creates the copy file,
  the catalog and the target's `resources`); then S6, S7 and S8 together (each adds one copy file of its own
  and its keys to the one catalog, a text merge the orchestrator resolves); then S9, S10 and S12 together,
  with S13 beside them; S11 after S10; S14 last.
- **No dead ends.** S1 to S13 change nothing the app shows: the Program tab keeps #28's placeholder
  (`F09-s1-tab-shell:LedgerKit/Sources/LedgerAppKit/AppTabs.swift:22-24`). S14 replaces it with a builder
  whose every button leads somewhere: the Day editor and its library sheet land in the same slice.
- **Splits considered.** S10 and S11 were one slice of about 580 lines; they are apart because the plan's own
  estimates have run low before. S14 holds the wiring (about 45 lines) with the last two stores; if it grows
  past about 600 lines the wiring becomes a fifteenth slice, at the cost of one more cycle. S2 carries the
  library's filter (55 lines) although it is not day editing, because a separate 55-line pull request costs a
  full implement, test and review cycle; the orchestrator may hand that part to F12 instead (see "M1 shared
  conventions", proposal 3).
- **Fixtures.** No slice needs F08. Criterion 1 names "the F08 default program", but its numbers and criterion
  7's are those of the spec's seed, which `main` has as `Fixtures.seedProgram()`
  (`LedgerFakes/Fixtures/Fixtures+Program.swift:139`); see "Brief vs main", row 22.

## Brief vs main

Where the brief, the spec and the code disagree, the last column says which the plan follows.

| # | The brief says | What exists | The plan does |
|---|---|---|---|
| 1 | Routes are added in `Apps/Ledger/Sources/Navigation/ProgramDestinations.swift` (brief:34). | `Apps/Ledger/` holds `LedgerApp.swift` and assets only. On #28 the screens a stack can push are cases of `AppDestination` (`F09-s1-tab-shell:LedgerKit/Sources/LedgerAppKit/Routes.swift:12-15`), drawn by `AppTabs.screen(for:)` (`…/AppTabs.swift:49-53`); a feature's routes are mapped in `Routes+<Feature>.swift` (`F09-s1-tab-shell:docs/architecture.md:179-185`). | The convention wins. S14 adds `AppDestination.day` and `LedgerAppKit/Routes+Program.swift`. |
| 2 | `DayEditorView`, `ExercisePickerSheet` (brief:22, :28-29). | Convention 2 and `F09-s1-tab-shell:docs/architecture.md:183`: every public entry view is named `…Root`, owns its store and takes `onRoute`; a screen is `XScreen(model:)`. | `DayEditorRoot` (public, pushed by the app), `DayEditorScreen`, `ExercisePickerScreen`. The library sheet is presented by `DayEditorRoot` itself: it is the same feature. |
| 3 | `ProgramRoute`: `.day(DayTemplateID)` (brief:58). | A pushed screen owns its own store (row 2), so the Day editor cannot read the builder's selected week, which the prototype shares as one global (`docs/product-spec.md:196`). | `case day(DayTemplateID, weekIndex: Int)` and `case closeDay` ("Done", or the day is gone). `ProgramRoot(week:onRoute:)` takes the week Today's "Edit week" asks for (`tasks/features/F09-today.md:40`). |
| 4 | Per-file test names and `test_…` functions (brief:32-33, :78-82). | `docs/testing-strategy.md:363-368`: one suite per source type, `subject_condition_expectation`, a sentence as the display name. | Renamed; see "Test plan changes". |
| 5 | `ProgramEditing` in `LedgerDomain/Programs/` (brief:31). | The folder does not exist; pure rules live in `LedgerDomain/Rules/`. | The brief's folder is used; it is new. Day-level functions go in a second namespace, `DayEditing`, so that S1 and S2 share no file. |
| 6 | `addWeek(_ p:)`, `addDay(_ p:, ids: () -> UUID)`, `addSlots(…, ids:)` (brief:40, :44, :46). | Every week, day and slot has an id (`LedgerDomain/Model/Week.swift:36-37`, `DayTemplate.swift:4-5`, `Slot.swift:14-15`), and an id is never made inside the Domain (`LedgerDomain/Identifiers.swift:6-7`). | Each function takes the new id as a typed parameter (`WeekID`, `DayTemplateID`, `SlotID`). A closure would draw a fresh id each time the edit is applied; the store applies an edit twice (once to show it, once inside the save), and both must give the same day. Tests pass fixed ids; stores draw from `@Dependency(\.uuid)`, which is `.incrementing` in tests (`LedgerTestSupport/WithTestDependencies.swift:88`). |
| 7 | `addDay` makes "New day" (brief:44). | The Domain holds no copy (`F09-s1-tab-shell:LedgerKit/Tests/LedgerAppKitTests/ModuleCopyTests.swift:17-19`); a day's name is stored data. | `addDay(_:id:name:)`; the feature passes its catalog's "New day". The tag "D{n}" is data, as `LedgerDomain/Model/DayTemplate.swift:8` says. |
| 8 | `removeLastWeek(_ p:)` throws `.weekHasLoggedSessions(n)` "if a finished workout has `source.weekIndex == last`" (brief:41, :57). | A `Program` knows nothing of workouts (`LedgerDomain/Model/Program.swift:12-22`). | The function is told: `removeLastWeek(_:loggedWeeks: Set<Int>)`. See "How a week is known to have logged sessions" below. |
| 9 | `ProgramEditError` has `.dayHasNoExercises` (brief:53), yet "the day is still assignable" (brief:60). | — | Not an error: a function that throws returns no program. `cycleSchedule` assigns the day; the presentation shows the notice when the day just assigned has no slot. |
| 10 | `set(_ field: SlotField, _ value: Int\|Decimal, …)` (brief:47). | Not Swift. The ranges are literals inside a private function (`LedgerDomain/Model/Slot.swift:76-89`). | `enum SlotField` whose cases carry their value; `DayEditing.set(_:slot:in:)` clamps. S2 makes the three ranges public constants on `Slot` and uses them in both places. |
| 11 | "Clamps" (brief:47), and the DoD: no clamping in views or stores (brief:97). | `Slot.init` throws (`Slot.swift:38-52`), and its comment asks an editor to rebuild the slot through `init` (`Slot.swift:10-13`). `RPE` and `RestDuration` have only failable initializers (`Units/RPE.swift:11`, `Units/RestDuration.swift:10`); `Reps` has a clamping one (`Units/Reps.swift:18`). | Clamping lives in `DayEditing.set` and in two new clamping initializers that mirror `Reps(clamping:)`. The edited fields are assigned directly: a rebuild through a throwing `init` with values already in range would leave an error path no test can reach, against the DoD's 100 % coverage (brief:96). Instead a property test rebuilds every result through `Slot.init` and `Program.init`, and the repository does so again at every save (`LedgerPersistence/Records/ProgramRows.swift:17-32`). |
| 12 | `setProgression`: "double: `repsHi = max(repsHi, reps + 2)`" (brief:48); criterion 9 starts from "reps 8 and repsHi 8" (brief:71); the spec: "sets `repsHi = reps + 2` if it isn't already above `reps`" (`docs/product-spec.md:242`). | `repsHi` is always above `reps` (`Slot.swift:86-88`), so criterion 9's start cannot exist and the spec's rule would never fire. | The brief's formula. Criterion 9 is read as "reps 8, top of range 9": choosing Double makes the top 10. |
| 13 | `toggleSuperset(_ p:, slot:, on:)`; `move(_ p:, slot:, direction:)` take a `Program` (brief:49-50). | — | `DayEditing.setSuperset(_:slot:in:)` and `DayEditing.move(_:slot:_:)` take a `DayTemplate`; `ProgramEditing.updateDay` applies them in a program. |
| 14 | `weekLoads(_ p:, slot:) -> [Prescription]` (brief:51). | A prescription needs the exercise and the units (`LedgerDomain/Rules/ProgressionRules.swift:21-27`). F24 plans `ProgressionRules.table(program:exercises:units:)` (`tasks/features/F24-progression-states.md:27`). | `ProgressionRules.prescriptions(for:weeks:exercise:units:)`, one slot's row of F24's table. |
| 15 | `addSlots(…, defaultRest: Duration, …)` (brief:46). | `Settings.defaultRest` is a `RestDuration` (`LedgerDomain/Model/Settings.swift:7`). The start load is per unit (`LedgerDomain/Model/Exercise.swift:71`). | `DayEditing.newSlot(id:exercise:units:defaultRest:)` builds one slot by rule 7 with the start load copied in, as decision #24 expects ("programs copy loads into their slots", `docs/product-decisions.md:33`); `addSlots(_:_:)` appends slots. |
| 16 | Names "refuse control characters … an error a Feature cannot match" (brief:55). | The error is now in the Domain: `RepositoryError.nulInText` (`LedgerDomain/Protocols/RepositoryError.swift:33-35`), thrown at `LedgerPersistence/Records/SyncedRecord.swift:28-32`. | Still cleaned at the edit: `ProgramEditing` removes Unicode `Cc` scalars and trims; a blank name is not saved. |
| 17 | The exact copy prints "lb" (brief:60). | Both units ship (decision #9). The F09 branch writes one key per unit (`F09-s3-presentation:LedgerKit/Sources/FeatureToday/TodayCopy.swift:75-80`). | One key per unit for each line that prints a load. |
| 18 | "%lld exercises · %lld sets · ~%lld min" and five more lines with two or more numbers (brief:60). | A key holds one counted value; fragments are joined with " · " (convention 1; `F09-s1-tab-shell:docs/engineering-standards.md:195-199`). | One key per fragment. "BLOCK · %lld WEEKS", "%lld DAYS", "It's scheduled in %lld weeks. …" and "Add %lld exercises" are plural keys with `one` and `other`. |
| 19 | Ten all-caps labels on the Day editor with a slot open, and orange in ten places (brief:60; v1:242, 261, 302). | Decision #17: at most six all-caps eyebrows a screen, orange once (`docs/product-decisions.md:26`). | Pete's decision 1. |
| 20 | "weekday letters per `Settings.weekStart`" (brief:60). | A program week is seven days counted from `startDate`, whatever the week start is now (`LedgerDomain/Rules/WeekCalendar.swift:53-56`). | The strip starts on the weekday of `program.startDate` (`LedgerDomain/Model/CivilDate.swift:70`), so left to right is the order the days come in. It equals `Settings.weekStart` unless the lifter changed that setting after the block began. |
| 21 | Card meta "recomputed by `TimeEstimate`", to be documented here (criterion 1, brief:63). | `TimeEstimate.minutes(day:prescriptions:)` (`LedgerDomain/Rules/TimeEstimate.swift:16-29`). Upper A is 39 minutes, pinned by `Tests/LedgerDomainTests/Rules/TimeEstimateTests.swift:45-48`. | The four seed days read **~39, ~38, ~37, ~31 min**, where the spec prints 40, 37, 37, 31 (`docs/product-spec.md:191`). The last three are worked by hand from the formula (2,250 s, 2,220 s and 1,845 s, rounded half up) and are asserted in S5 through `TimeEstimate.minutes`, never as literals. Decision #14 settles which formula; this is not a question for Pete. |
| 22 | Criterion 1 opens on "the F08 default program"; criterion 7 expects Incline DB Press from 50 and Back Squat week 8 at 240 (brief:63, :69). | F08's fixture carries the catalog's start loads (Bench 45 lb: `F08-s3-root-gate:LedgerKit/Sources/LedgerFakes/Fixtures/Fixtures+Templates.swift:12-14`), under which week 8 of Back Squat is not 240. The spec's seed loads (50, 250) are in `Fixtures.seedProgram()` (`LedgerFakes/Fixtures/Fixtures+Program.swift:56-134`, `:139-165`). | Criteria 1–7 are tested on `Fixtures.seedProgram()`. It starts 2026-08-17, so `Fixtures.now` is in its week 5 (`LedgerFakes/Fixtures/Fixtures.swift:33-34`); the tests that expect week 1 selected re-date it (`Program.startDate` is `var`, `LedgerDomain/Model/Program.swift:17`). |
| 23 | Criterion 13: "`programRepository.save` is called within 300 ms (debounced)" (brief:75). | Stores own no task that outlives the view (`docs/engineering-standards.md:83-84`, `:109-110`; convention 2). `save` writes the whole program (`LedgerDomain/Protocols/Repositories.swift:27-32`). | No timer, and not `save`. See "Saving and a live workout". |
| 24 | Two `LedgerPersistenceTests`: an edited program round-trips, deleting a day removes its slots (brief:80). | Both exist: the contract's `saveReplaces` (`LedgerTestSupport/Persistence/ProgramRepositoryContract.swift:82-92`, whose edit removes a day at `:41-46`), `partialUpdate_diffsChildren` (`Tests/LedgerPersistenceTests/ProgramRepositoryTests.swift:79`), and a seeded random builder session (`Tests/LedgerPersistenceTests/Adversarial/ProgramEditModelAdversarialTests.swift:13`). | Not added again. S3 adds the clauses for `update`. |
| 25 | Snapshots: every state × light, dark × default, XL (brief:81); text to AX5 (brief:86). | `docs/testing-strategy.md:163-166`: six cells a state, the largest `.accessibility3`. The F08 branch records six cells for a screen's main states and two for the rest (`F08-s3-root-gate:LedgerKit/Tests/FeatureOnboardingTests/__Snapshots__/OnboardingSnapshotTests/`). | As F08 does; see "Test plan changes". AX5 is checked by hand on the simulator for the screenshots the DoD asks for (brief:99). |
| 26 | The library search is "debounced 100 ms" (brief:85). | 224 exercises (`LedgerDomain/Resources/exercises.json`); matching is a string fold and a `contains` (`LedgerDomain/Rules/ExerciseSearch.swift:14-28`). | No debounce: the store folds each name once and filters on every keystroke. A nightly timing test holds the 10 ms budget. |
| 27 | Muscle chips "All, Chest, Back, Shoulders, Legs, Arms"; equipment chips "All, Barbell, Dumbbell, Cable, Machine, Bodyweight" (brief:60). | Eleven muscle groups and seven kinds of equipment (`LedgerDomain/Model/Exercise.swift:4-5`, `:21-23`). `ExerciseRepository.search` takes one muscle group (`LedgerDomain/Protocols/Repositories.swift:13`), so it cannot ask for "Legs". The catalog has 26 core, 15 kettlebell and 11 band exercises (counted in `exercises.json`). | S2 adds `ExerciseSearch.MuscleFilter` (legs = quads, hamstrings, glutes, calves; arms = biceps, triceps, forearms) and filters `observeAll()` in memory, as the F12 brief also plans (`tasks/features/F12-library-history.md:53`). Which chips exist is Pete's decision 3. |
| 28 | `LedgerDesign` is taken to have steppers, chips, toggles and cards. | It has `PillButton` (`LedgerDesign/Components/PillButton.swift:7-16`; `.filled` is spoken as selected, `:34`), `SheetChrome` (`SheetChrome.swift:13-25`), `HairlineList` (`HairlineList.swift:6`), `HairlineRow` (`HairlineRow.swift:10`), `Eyebrow` (`Eyebrow.swift:5`), `EmptyState` (`EmptyState.swift:10`), `PrimaryButton` (`PrimaryButton.swift:8`), `IconPillButton` (`IconPillButton.swift:5`), and the icons arrow, check, chevron, swap, minus, plus (`LedgerIcon.swift:8-16`). The only stepper is private to the set row (`SetRowSteppers.swift:51`). `WeekStrip` draws dated days with a dot and cannot be tapped (`WeekStrip.swift:10-42`). There is no stepper field, no toggle, no wrapping layout and no card. | S4 adds the three missing controls. Chips are `PillButton`s in the wrapping layout. The week chips, the schedule cells and the library rows are the feature's own views (as onboarding draws its own row, `F08-s3-root-gate:LedgerKit/Sources/FeatureOnboarding/Views/OnboardingOptionRow.swift:11-42`). |
| 29 | "Depends on F02, F03, F05, F06, F07" (brief:7). | The copy rule and the shell are in #28. | S5 to S14 depend on #28 as well. |
| 30 | Criterion 2: with four days, the Tuesday cell reads LB "after the fifth tap" and REST after the sixth (brief:64). | Rule 5 is rest → day 1 → … → last day → rest (`docs/product-spec.md:723`), and the prototype does that (v1:1308-1312): from REST, four taps reach the fourth day and the fifth returns to REST. | Rule 5. The test reads UA, LA, UB, LB, REST after taps one to five; the criterion's count is one too many. |

### The editing functions, as proposed

Every function is pure and total: given an id the program or day does not hold, it returns its input unchanged.
`week` is the week's zero-based index (`Week.index`, `LedgerDomain/Model/Week.swift:38`). Only two functions
throw, both with typed throws.

```swift
// S1 — LedgerDomain/Errors.swift
public enum ProgramEditError: Error, Equatable, Sendable {
    case minimumTwoWeeks                              // rule 4
    case weekHasLoggedSessions(weekNumber: Int)       // one-based, as the message prints it
}

// S1 — LedgerDomain/Programs/ProgramEditing.swift, ProgramEditing+Days.swift
public enum ProgramEditing {
    public static func cleanedName(_ text: String) -> String?                 // Cc scalars removed, trimmed; nil when blank
    public static func renameProgram(_ program: Program, to name: String) -> Program
    public static func addWeek(_ program: Program, id: WeekID) -> Program     // the last week's schedule, not a deload
    public static func removeLastWeek(_ program: Program, loggedWeeks: Set<Int>) throws(ProgramEditError) -> Program
    public static func toggleDeload(_ program: Program, week: Int) -> Program
    public static func cycleSchedule(_ program: Program, week: Int, weekday: Weekday) -> Program   // rule 5
    public static func copyPreviousWeek(_ program: Program, week: Int) -> Program
    public static func applyToLaterWeeks(_ program: Program, week: Int) -> Program
    public static func addDay(_ program: Program, id: DayTemplateID, name: String) -> Program      // rule 8
    public static func renameDay(_ program: Program, day: DayTemplateID, to name: String) -> Program
    public static func deleteDay(_ program: Program, day: DayTemplateID) -> Program
    public static func updateDay(_ program: Program, day: DayTemplateID,
                                 _ change: (DayTemplate) -> DayTemplate) -> Program
}

// S2 — LedgerDomain/Programs/DayEditing.swift, DayEditing+Fields.swift, DayEditing+Move.swift
public enum SlotField: Hashable, Sendable {           // a field, with the value it is set to
    case sets(Int), reps(Int), repsHi(Int), rpe(Decimal), restSeconds(Int), startLoad(Weight)
    public enum Kind: Hashable, Sendable, CaseIterable { case sets, reps, repsHi, rpe, rest, startLoad }
}
public enum StepDirection: Hashable, Sendable { case down, up }
public enum MoveDirection: Hashable, Sendable { case up, down }

public enum DayEditing {
    public static func newSlot(id: SlotID, exercise: Exercise, units: Units,
                               defaultRest: RestDuration) throws(SlotValidationError) -> Slot      // rule 7
    public static func addSlots(_ day: DayTemplate, _ slots: [Slot]) -> DayTemplate
    public static func removeSlot(_ day: DayTemplate, slot: SlotID) -> DayTemplate
    public static func set(_ field: SlotField, slot: SlotID, in day: DayTemplate) -> DayTemplate   // rules 2, 3, 6
    public static func stepped(_ kind: SlotField.Kind, _ direction: StepDirection, of slot: Slot,
                               exercise: Exercise, units: Units) -> SlotField                      // rules 1, 6
    public static func setProgression(_ progression: Progression, slot: SlotID, in day: DayTemplate) -> DayTemplate
    public static func setDropSet(_ isOn: Bool, slot: SlotID, in day: DayTemplate) -> DayTemplate
    public static func setSuperset(_ isOn: Bool, slot: SlotID, in day: DayTemplate) -> DayTemplate
    public static func move(_ day: DayTemplate, slot: SlotID, _ direction: MoveDirection) -> DayTemplate
    public static func groups(of day: DayTemplate) -> [[SlotID]]          // superset groups, in order
}
public extension ProgressionRules {
    static func prescriptions(for slot: Slot, weeks: [Week], exercise: Exercise, units: Units) -> [Prescription]
}
public extension ExerciseSearch {
    enum MuscleFilter: Hashable, Sendable, CaseIterable { case chest, back, shoulders, legs, arms
        public var groups: Set<MuscleGroup> }      // legs: quads, hamstrings, glutes, calves; arms: biceps, triceps, forearms
    static func filter(_ exercises: [Exercise], query: String, muscle: MuscleFilter?, equipment: Equipment?) -> [Exercise]
}
```

- **New ids** are parameters (row 6). `addWeek` and `addDay` given an id the program already holds, and
  `addSlots` given a slot whose id the day already holds, add nothing.
- **Clamping** is in `DayEditing.set`: sets 1…12, reps 1…30, top of range 2…40, RPE 5…10 by 0.5, rest 30…300 s
  by 15, start load at least zero. After the clamp, the coupling: reps set at or above the top makes the top
  `reps + 1`; the top set at or below reps makes it `reps + 1`. `stepped` gives the neighbouring value and does
  not clamp; the stepper buttons send `set(stepped(…))`, so a store adds nothing and clamps nothing.
- **Start load.** `stepped(.startLoad, …)` starts from `slot.startLoad ?? exercise.startLoad(in: units)` and
  the step `slot.step ?? exercise.equipment.defaultStep(in: units)`, the same two fallbacks as
  `LedgerDomain/Rules/ProgressionRules.swift:29-30`, and goes to the next multiple of the step in that
  direction, never below zero.

### Group-aware move, defined

A day's slots are s₀ … sₙ₋₁. A **superset group**, a group for short, is a maximal run of slots in which
every slot after the first has `isSupersetWithPrevious == true`; a slot on its own is a group of one. This is
the grouping the estimate and the live workout already use (`LedgerDomain/Rules/SupersetRounds.swift:61-71`,
where the first slot's flag is ignored, `:7`). **Normal form:** the first slot of the day has the flag false. Every `DayEditing` function
returns a day in normal form, and so the first slot of every group has the flag false.

`move(day, slot: x, direction)`, with x the j-th member of group Gₖ of m groups:

- **Down.** If x is not the last member of Gₖ, x and the member after it change places; the group keeps its
  place and its size, and its flags are rewritten (first false, the others true). If x is the last member
  (or Gₖ is a group of one): when Gₖ is the last group, nothing changes; otherwise Gₖ and Gₖ₊₁ change
  places, each keeping its members' order and flags.
- **Up** is the mirror: not the first member → change places with the member before; the first member →
  Gₖ and Gₖ₋₁ change places, or nothing when k = 0.

Criterion 10 follows: from [1, 2, 3A, 3B, 4], "Move down" on 2 gives [1, 3A, 3B, 2, 4]; "Move down" on 3A
swaps it with 3B; "Move up" on 3A gives [1, 3A, 3B, 2, 4].

What the property test asserts, on seeded random days of 0 to 8 slots in normal form, with random flags after
the first, for a random slot and direction (and for an id the day does not hold). A day that arrives with the
first flag true is read as its normal form; one fixed test covers it.

1. The result holds the same slot ids, each once, and no field of any slot changed except the flag.
2. The result is in normal form.
3. `groups(of:)` of the result, taken as sets of ids, equals that of the input: moving never changes who is
   in a superset with whom.
4. The sequence of groups differs from the input's by nothing, or by one swap of two neighbouring members
   inside one group, or by one swap of two neighbouring groups; never by anything else.
5. Moving the first member of the first group up, the last member of the last group down, or an unknown id,
   returns the input.
6. When a move changed the day, and it moved a group of one or swapped two members inside a group, the
   opposite move restores the input. (For a group of two or more moved from its edge it does not: after
   "Move down" on 2B in [2A, 2B], [3], "Move up" on 2B swaps it with 2A. Pete's decision 2 shows this case.)

### How a week is known to have logged sessions

`removeLastWeek` is given `loggedWeeks`, the week indices that hold a finished workout of this program, and
throws `.weekHasLoggedSessions` when the last index is among them. The builder's store computes the one entry
that matters. It reads `WorkoutRepository.workouts(in:)` (`LedgerDomain/Protocols/Repositories.swift:96`; by
start date, and a deleted workout is never read: `LedgerPersistence/Repositories/GRDBWorkoutRepository.swift:7`)
from one day before the last week's first day (`WeekCalendar.bounds(ofWeek:)`,
`LedgerDomain/Rules/WeekCalendar.swift:61`) to `Date.distantFuture`, and keeps
the workouts whose `source` names this program and that week (`LedgerDomain/Model/WorkoutState.swift:9-19`,
`:36`). No workout can be built for a week past the block (`LedgerDomain/Rules/SessionBuilder.swift:27-29`),
so the read is at most a week or two of workouts. The extra day covers a workout started just before midnight
in another time zone. A query on the stored `week_index` column (`LedgerPersistence/Migrations.swift:128-129`)
would be exact; it is not planned, because it adds a second protocol requirement for a check whose failure is
harmless: a workout that names a removed week keeps its own name, tag and numbers (`Migrations.swift:131-133`)
and is read without the program.

## Saving and a live workout

### What `programRepository.save` does today

`GRDBProgramRepository.save` (`LedgerPersistence/Repositories/GRDBProgramRepository.swift:43-52`) rebuilds the
program through `Slot.init` and `Program.init` (`LedgerPersistence/Records/ProgramRows.swift:17-32`) and then,
in one write transaction, reads every live row of the program before it writes any (`ProgramRows.swift:53-60`),
refuses an id another program holds (`:61`, `:74-78`) and a slot whose exercise has no row (`:62`, `:84-92`),
and compares each table's rows with the stored ones (`:64-68`). A row whose columns all equal the stored row is
left alone (`LedgerPersistence/Records/SyncedRecord.swift:72-74`); a new or changed row is written with a new
`updated_at` (`:35-36`, `:75`); a stored row the program no longer has is soft-deleted (`:78-84`). The in-memory
store keeps the same rules under one lock (`LedgerFakes/InMemoryProgramRepository.swift:133-167`,
`LedgerFakes/Support/ObservedState.swift:41-61`).

| Edit | What `save` does with it | Where it is pinned |
|---|---|---|
| Program or day renamed | That one row is rewritten. A name holding U+0000 is refused and nothing is saved (`SyncedRecord.swift:28-32`). | `ProgramRepositoryContract.swift:117-141` |
| Week added, week removed, schedule changed, deload toggled | One `program_week` row each; the schedule is seven columns of it (`LedgerPersistence/Records/ProgramRecords.swift:87-89`). A removed week is soft-deleted. | `Tests/LedgerPersistenceTests/Adversarial/ProgramEditAdversarialTests.swift:96` |
| Day deleted | The day's row is soft-deleted. Its slots and their misses were read before the write and are missing from the new rows, so they are soft-deleted in the same transaction (`ProgramRows.swift:54-60`, `:67-68`). | `Tests/LedgerPersistenceTests/ProgramRepositoryTests.swift:79` |
| Slots reordered | A slot's place is its `position` column (`ProgramRows.swift:38`, `LedgerPersistence/Records/SlotRecords.swift:48`), so each slot that moved is rewritten; the order is read back by position (`ProgramRows.swift:168`). | `ProgramEditAdversarialTests.swift:67` |
| A slot's numbers changed, a slot added | That slot's row. A new slot's exercise must be stored (`ProgramRows.swift:84-92`); the library lists stored exercises only. | `ProgramRepositoryContract.swift:82-92` |
| A slot removed that a finished workout refers to | The slot's row is soft-deleted, never removed. A finished workout holds the slot's id and the day's id as plain text with no foreign key (`LedgerPersistence/Migrations.swift:153`, `:130`), keeps its own name and tag (`:131-132`) and each exercise's own name (`:154`), and is read without any program table (the ids are only decoded: `LedgerPersistence/Records/WorkoutRecords.swift:48`, `:111`). History does not change. | — (S3 adds a clause) |
| Nothing changed | No row is written, and observers hear nothing (`GRDBProgramRepository.swift:91-93`). | For a workout saved twice: `WorkoutRepositoryContract+Linked.swift:210`. For a program: S3 adds a clause. |
| **Misses and a slot's exercise** | **Written as the given program has them.** Stored misses the given program lacks are soft-deleted (`ProgramRows.swift:40-42`, `:68`); `exercise_id` is an ordinary column of the slot's row (`SlotRecords.swift:49`). | `ProgramRepositoryContract.swift:41-72` |

### What F11 needs that `save` does not do

The last row is the problem. A workout's save writes into the program too, in its own transaction: each
slot's misses, whole (`LedgerPersistence/Repositories/GRDBWorkoutRepository.swift:174-194`;
`LedgerDomain/Protocols/Repositories.swift:64-65`), and, for a swap made with "Also update program", the
slot's exercise (`GRDBWorkoutRepository.swift:205-249`). A builder that holds a copy of the program and saves
it whole writes both back as they were when it read them. The order "builder reads; a workout is saved; builder
saves" loses the workout's misses and its swap, silently. A lost miss matters: the next week's load then goes
up when it should hold (`LedgerDomain/Rules/ProgressionRules.swift:28`). On one phone the gap between the read
and the write is short. With the watch (F17) a finished workout can reach the phone at any moment, while the
lifter is tapping steppers.

S3 adds one requirement to `ProgramRepository`:

```swift
/// Applies `change` to the program `id` as it is stored now and saves the result, in one step that no
/// other write can come between. Returns the program as stored afterwards.
func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program
```

- A program that is not stored, or is deleted, throws `missingRow` (`LedgerDomain/Protocols/RepositoryError.swift:36-38`).
- When `change` throws, the error is rethrown and nothing is written. The result is checked and refused as
  `save` checks and refuses; a result with another id is refused.
- A change that returns the program unchanged writes no row and wakes no observer.
- GRDB: one `queue.write`, as `save` uses (`GRDBProgramRepository.swift:46-51`), that reads with
  `ProgramRows.program(_:in:)` (`ProgramRows.swift:120`), applies the change, and writes with
  `ProgramRows.write` (`:53`). In memory: one `state.write`, the lock a workout's save takes as well
  (`InMemoryProgramRepository.swift:81-92`).

Every builder edit is then sent as a change, `{ ProgramEditing.toggleDeload($0, week: 2) }`. No function of S1
or S2 writes the misses or the exercise of a slot that already exists, so a workout's save and a builder edit
give the same program in either order. S2 pins that with a property test.

Two smaller ways were weighed. The store could copy the misses and the exercises from the newest program it has
observed into its copy before each `save`: that closes most of the gap, not the part between the store's last
observation and its write. `update` could have a default body in a protocol extension (read `active()`, change,
`save`), which would spare other lanes' test doubles: but that body is the very sequence that loses the
update, and the last requirement added to a repository deliberately has none ("there is no default",
`LedgerDomain/Protocols/Repositories.swift:83`).

### The 300 ms debounce

The brief asks that `save` be called "within 300 ms (debounced)" (brief:75). The plan builds no timer.

- An intent is synchronous. It applies the edit to the program the screen shows, at once, and adds it to the
  session's list of edits that are not stored yet.
- The root runs the save from `.task(id: store.saveTicket)`. The ticket changes only when edits are waiting and
  no save is running, so a new edit never cancels a save that has started. The save takes every waiting edit,
  calls `update` once with all of them, drops them when it returns, and goes round again if more arrived
  meanwhile.
- So the first edit is written at once, well inside 300 ms, and edits made during a write go together in the
  next one. That is what the debounce was for (few writes), and each write touches only the rows that changed.
- A timer was rejected for a reason of the store convention. A store keeps no task of its own
  (`docs/engineering-standards.md:83-84`, `:109-110`), so the 300 ms wait would live in the view's task, and
  SwiftUI cancels that task when the view goes away. An edit followed within 300 ms by a tap on the Today tab
  would stay unsaved for as long as the lifter stays away, and Today would show the old program, against
  criterion 13. For the Day editor, whose store goes with the screen, the edit would be gone.
- What is left of that risk: a write that is in flight at the instant the screen goes away is cancelled, and
  then either all of it is stored or none (S3 pins this for a change that throws; onboarding accepts the same
  for its save, `F08-s3-root-gate:LedgerKit/Sources/FeatureOnboarding/OnboardingStore.swift:120-157`). The
  builder's store outlives a tab switch and sends its waiting edits when the tab returns. The Day editor's
  "Done", "Delete day" and the builder's "+ Add training day" emit their route only after the save has
  returned. A name is saved as it is typed, not when its field is left, for the same reason.
- When a save fails, the waiting edits are dropped, the screen shows the stored program again with one line
  of text (Pete's decision 6), and the error is logged.

The test of criterion 13 needs no clock: `ProgramStoreTests.edit_isSavedAtOnce_andEditsMadeMeanwhileGoTogether`
holds the first `update` with a probe, sends three more edits, lets go, and counts two writes.

### A live workout, and a finished one

A live workout is a copy taken at its start (rule 16; `LedgerDomain/Rules/SessionBuilder.swift:9-10`), and it
lives in the event log, which no builder edit touches. When it finishes, the host reads the program as stored
then and works out misses only for the slots that still exist (`LedgerSync/LocalWorkoutSessionActor+Recovery.swift:206-224`,
the lookup at `:213-215`), and each verdict is taken against the workout's own targets
(`LedgerDomain/Rules/MissTracking.swift:14-16`).

| The lifter edits, while a workout is live | The workout | At its finish |
|---|---|---|
| A slot's sets, reps, load, rest, progression | Unchanged. | The miss is judged on what the workout asked for; the next session is built from the edited slot. |
| A slot removed | Unchanged; the exercise stays in the workout. | No miss is recorded for it; the save skips a slot that is not stored (`GRDBWorkoutRepository.swift:177-185`). The workout is saved whole. |
| The workout's day deleted | Unchanged. | Saved under its own name and tag; no miss is recorded, as no slot is left. |
| The workout's week removed (it holds no finished workout yet, so the builder allows it) | Unchanged. | Its misses are written for a week index the block no longer has; a prescription counts only earlier weeks (`ProgressionRules.swift:28`), so nothing reads them. |
| The schedule, the block's length, names | Unchanged. | Nothing. |

A finished workout that refers to a deleted day or slot is unaffected (the sixth row of this section's first
table). Stored
again later by recovery, it writes misses for the slots that are still stored and skips the rest.

One thing could not be established, because the workout's screens are not built: how a minimised workout is
resumed. `StartWorkoutUseCase.start` refuses a day the program no longer holds, and a day with no exercise,
before it looks at the live workout (`LedgerDomain/UseCases/StartWorkoutUseCase.swift:81-87`). If F10's resume
goes through it, a lifter who deletes or empties the day of a running workout cannot get back to that workout.
F10 S4 must resume from the session's own state, or the builder must refuse those two edits while that day's
workout is live (Pete's decision 4, alternative).

### F10 S3's late slot updates, and the question in pull request #32

Today every save of a workout applies each of its swaps to a live slot of its own program, unless the slot
already holds that exercise (`GRDBWorkoutRepository.swift:205-249`); an older workout stored again therefore
sets a slot back, which the contract pins (`LedgerTestSupport/Persistence/WorkoutRepositoryContract+Linked.swift:184`).
Pete is asked which should win (`origin/docs/adr-004-amendment-saves:tasks/decisions-for-pete-2026-10-05-saves.md`,
decision 2). The letters below are that document's; the ADR amendment's table orders them differently.

Two things hold under every answer:

1. **F11 cannot produce the case as the question tells it.** The Day editor has no control that exchanges a
   slot's exercise (brief:22), and no function of S1 or S2 writes the `exerciseID` of an existing slot. In the
   builder, "I set that slot to Incline Bench" is "I removed Bench Press and added Incline Bench": a new slot
   with a new id. Monday's swap then names a slot that is not stored and is skipped, today already
   (`GRDBWorkoutRepository.swift:229-234`).
2. **The opposite direction is F11's to prevent:** a builder edit must not undo a swap, or a miss, that landed
   while the builder was open. That is S3, and it is needed under every answer.

| Pete's answer | What F11 must do |
|---|---|
| **A.** Your later choice wins (the swap is applied only while the slot still holds the exercise that was swapped out). | Nothing more. S2's property test keeps rule 1 true. If a later feature lets the builder exchange an exercise in place, A already protects it. |
| **B.** The swap wins (the code today). | Nothing more, and rule 1 must stay: an exchange in place would be overwritten without a word. While the Day editor is open, a swap that lands redraws the slot with the new exercise, because the store follows the stored program. |
| **C.** The newer by the clock wins. | Nothing in F11's own code, but one condition on whoever builds C: the clock cannot be the slot's `updated_at`. Every builder edit of a slot's numbers, and every reorder, rewrites that row (`SyncedRecord.swift:35-36`, `:75`; `SlotRecords.swift:48`), so a rep changed on Tuesday would defeat Monday's swap. C needs a time for the exercise alone, as the amendment says (`origin/docs/adr-004-amendment-saves:docs/adr/ADR-004-event-sourced-workout-engine.md:321`), and builder edits leave it untouched. |

## Decisions for Pete

Six, in order of how much of the feature each one shapes. Each has a default, so none blocks a slice; S1, S2
and S3 depend on none of them.

**1. How the three screens look.**
The builder, the Day editor and the exercise library exist only in the old light design: white cards, orange in
ten places, a dozen small all-caps labels. The dark design, the one that ships, never drew them.
- **A (recommended).** Draw them in the dark design's language now: flat on the dark ground, hairlines between
  rows, pill buttons, the type of Today. Three things you would notice:
  - *Orange* only on the one thing that matters on each screen: the word "DELOAD" on a deload week (builder),
    the open exercise's week line, "WEEK 8 · DELOAD" or "· HELD" (Day editor), and the "Add 3 exercises" button
    (library). "SUPERSET", the drop-set switch, "Remove", "already in this day" and the selected equipment
    chip become ink or grey.
  - *Labels.* With one exercise open the old design shows ten all-caps labels; the dark design allows six a
    screen. The six field labels become "Sets", "Reps", "Top of range", "Start load", "Target RPE", "Rest" in
    the small grey label style.
  - *Week chips* wrap onto a second row (eight weeks make two rows) instead of scrolling sideways.

  You see screenshots on the pull requests of S4 (the new controls) and S9 to S12 (the screens), before any of
  it is in the app.
- **B.** Design these screens first. S4 and S9 to S12 wait for the design.
- By default: A. Used first by S4, today.

**2. Move up and Move down when exercises are in a superset.**
Take a day with 1 Bench, 2 Incline, 3A Pulldown, 3B Lateral raise, 4 Curl.
- **A (the brief; recommended).** A superset stays together. "Move down" on Incline puts it below the whole
  superset: Bench, Pulldown, Lateral raise, Incline, Curl. Inside a superset, Move changes the order of its
  exercises: "Move down" on Pulldown makes Lateral raise A and Pulldown B. From the edge of a superset, Move
  carries the whole superset: "Move down" on Lateral raise puts both below Curl. One oddity: "Move down" and
  then "Move up" on Lateral raise does not put things back, because the first carries the superset past Curl
  and the second swaps Lateral raise with Pulldown.
- **B.** Move only ever moves the one exercise, one place; crossing the edge of a superset takes it out of the
  superset. The opposite button always undoes it, but one mis-tap can take a superset apart, and a superset
  cannot be moved as a whole.
- By default: A. "Break out" remains the way to take an exercise out. S2 builds A; changing to B later is one
  function and its tests.

**3. The filter chips of the exercise library** (the same question for the Library tab, F12).
The catalog has 224 exercises. The brief's chips are Chest, Back, Shoulders, Legs, Arms, and Barbell, Dumbbell,
Cable, Machine, Bodyweight. Fifty-two exercises fit no chip: 26 for the core (planks, crunches, the ab wheel),
15 with a kettlebell and 11 with a band. You would find a plank only under "All" or by typing its name.
- **A (recommended).** Add "Core" to the muscle chips, and "Kettlebell" and "Band" to the equipment chips. The
  chips wrap onto another row.
- **B (the brief).** Keep the ten chips; those exercises are under "All" and search.
- By default: B, because the brief states it. A is three more chips; S2 and S8 take either.

**4. Deleting a training day.**
The brief gives the confirmation ("Delete Lower B?", "It's scheduled in 8 weeks. Those days become rest.") but
not where the button is, nor what happens in two cases.
- *Where.* Recommended: a "Delete day" button at the foot of the Day editor, under "+ Add exercise from
  library". The alternative, a swipe on the day's card in the builder, is hidden and harder with VoiceOver.
- *A Lower B workout is running, minimised, when you delete Lower B.* Recommended: allowed. The workout carries
  on and is saved to History under its name; it leaves no "missed" marks, as there is no day left to mark. The
  alternative is to refuse with "Finish or discard your workout first".
- *Deleting the last day that is left.* Recommended: allowed. The builder then shows only "+ Add training day",
  and Today shows rest days.
- By default: as recommended. First used by S6.

**5. The two-letter tag of a day you add.**
A day you add is named "New day" and tagged "D5". You can rename it "Arms", but the tag stays "D5" on the
schedule strip, on Today and in History: the brief has no field for the tag.
- **A (the brief; recommended for now).** Tags cannot be edited in this feature. If "D5" is taken, because a
  day was deleted and another added, the new day gets the next free number.
- **B.** A short field for the tag, up to three letters, beside the day's name.
- By default: A. B is a small follow-up once you have used it, and needs a look.

**6. Wording the brief does not have.**
- The delete button: "Delete day".
- The confirmation's second line for one week: "It's scheduled in 1 week. Those days become rest." For a day
  that is scheduled nowhere, no second line.
- No program (seen only until onboarding guards the tabs): "No program yet", "Your program appears here once
  you have set one up."
- The program cannot be read: "Can't show your program right now", "Your workouts are still on this iPhone.
  Open the app again to try once more." (the wording Today uses by default).
- An edit could not be saved: "That change wasn't saved. Try again."
- What VoiceOver says for controls that show only a letter or a number ("Week 3, 4 days", "Tuesday, rest",
  "Sets, 5"): listed with each screen's VoiceOver table in S9 to S12.
- By default: this wording.

What you do **not** need to look at: the minutes on the day cards (39, 38, 37 and 31 where the old design
printed 40, 37, 37 and 31: your one formula, decision 14, gives them); how an edit is saved, and the change to
the program store that keeps a finished workout's results safe; the dropped 300 ms delay; where routes and
strings live; that the tests use the spec's sample program; the names of the new functions.

## Behaviour the brief leaves open

Engineering choices and edge cases the plan decides itself. Each is pinned by the test named.

| # | The case | The choice | Pinned by |
|---|---|---|---|
| 1 | Which week the builder opens on. | The block's week that holds today (`LedgerDomain/Rules/WeekCalendar.swift:53`); week 1 before the block starts, the last week after it ends. A week asked for through `ProgramRoot(week:)` wins. | S13 `ProgramStoreTests.firstLoad_selectsTheWeekThatHoldsToday`, `requestedWeek_isSelected` |
| 2 | The selected week after "−" and "+". | After "−", the selection stays inside the block (v1:1253); after "+", the new week is selected (criterion 4). | S13 `removeWeek_keepsTheSelectionInsideTheBlock` |
| 3 | "Copy week n−1" on week 1. | Nothing changes; the button reads "First week" and is disabled (v1:1291-1292 does nothing there). | S1 `copyPreviousWeek_onTheFirstWeek_changesNothing`; S5 `weekActions_firstWeek_isDisabled` |
| 4 | The tag of an added day when "D{n}" is taken. | The next free number (Pete's decision 5). | S1 `addDay_tagSkipsNumbersInUse` |
| 5 | Names. | Saved as typed, control characters removed, trimmed; a blank name is not saved and the stored one stays; no length limit (the views limit lines). | S1 `cleanedName_removesControlCharactersAndTrims`, `renameDay_blank_changesNothing` |
| 6 | Cycling onto a day with no exercise. | The day is assigned; the notice shows until the next edit or another week is selected. | S5 `cycleOntoAnEmptyDay_showsTheNotice` |
| 7 | Removing the first exercise of a superset [A, B]. | B leads what is left: its flag becomes false. The prototype only removes the row (v1:1389), which would join B to the exercise before A. | S2 `removeSlot_firstOfAGroup_theNextMemberLeads` |
| 8 | "Break out" on the middle of [A, B, C]. | B and C stay together as a new superset: the flag says "with the previous" (v1:1122, 1355). | S2 `setSuperset_off_inTheMiddle_splitsTheGroupThere` |
| 9 | "Superset with next" when the next exercise leads a superset. | The two groups become one. | S2 `setSuperset_on_mergesWithTheGroupAhead` |
| 10 | A start load off the unit's steps (180 lb shown in kilograms is 81.6; `LedgerDomain/Units/Weight.swift:101-109`). | "+" goes to the next multiple of the step above (82.5), "−" to the next below (80); never below zero. | S2 `steppedStartLoad_offTheSteps_goesToTheNextMultiple` |
| 11 | A stepper at its limit. | It stays enabled and the value stays (v1:1104-1106). | S2 `set_clampsEveryField` |
| 12 | Leaving "Double". | The top of the range is kept, hidden. | S2 `setProgression_awayFromDouble_keepsTheTop` |
| 13 | Sets and minutes in a deload week. | The Day editor's line starts with "Week n", so it counts that week's prescription (one set fewer per exercise; `LedgerDomain/Rules/TimeEstimate.swift:14-15`). The builder's cards, "shared by every week", count the slots' own numbers. The prototype uses the slots' own numbers for both (v1:1320, 1331) while its rows show the week's (v1:1371). | S6 `meta_deloadWeek_countsThePrescribedSets`; S5 `dayCard_meta_isTheSlotsOwn` |
| 14 | The library's picks. | Added in the order picked (v1:1412, 1422-1423); the same exercise may be added twice (`docs/product-spec.md:260`); the two filters are kept for as long as the Day editor stays open. | S14 `add_appendsInPickOrder_andKeepsTheFilters` |
| 15 | The stored program changes under the screen (a workout is saved). | The screen redraws from the stored program with its waiting edits on top; an open exercise that is gone closes; a Day editor whose day is gone emits `.closeDay`. | S13 `storedProgramChanges_isShown`; S14 `dayRemovedElsewhere_closesTheEditor` |
| 16 | No active program; the program's stream ends before a value (`LedgerPersistence/Observation/ValueObservation+AsyncStream.swift:15-17`). | An empty state; a failed state (Pete's decision 6 for both texts). | S13 `noActiveProgram_showsTheEmptyState`, `streamEndsBeforeAValue_showsFailed` |
| 17 | A save fails. | The waiting edits are dropped, the stored program is shown, one line says so, the error is logged. | S13 `saveFails_showsTheStoredProgramAndSaysSo` |
| 18 | An id the program or day does not hold. | Every editing function returns its input. | S1 and S2 property suites |
| 19 | A slot whose exercise is not among the live exercises. Nothing deletes an exercise in M1 (`tasks/features/F12-library-history.md:23`). | The row is still listed, named by a dash, and "Remove" works. | S6 `slotOfAMissingExercise_isListedAndRemovable` |
| 20 | Weekday letters and spoken weekday names. | From the injected calendar and locale, not catalog entries (they are the system's words). | S5 `scheduleStrip_lettersFollowTheLocale` |

## Test plan changes

**Renamed and re-cut** (`docs/testing-strategy.md:363-368`; the suite is named after its source type):

| Brief (brief:78-79) | Slice, suite and test |
|---|---|
| `test_editing_addWeek_copiesScheduleNotDeload` | S1 `ProgramEditingTests.addWeek_copiesTheLastWeeksSchedule_notADeload` |
| `test_editing_removeWeek_minTwo`, `…_loggedSessionsThrows` | S1 `removeLastWeek_atTwoWeeks_throwsMinimumTwoWeeks`, `removeLastWeek_loggedWeek_throwsWithItsNumber` |
| `test_editing_cycleSchedule_order` | S1 `cycleSchedule_restThenEachDayThenRest` |
| `test_editing_copyPrevious_applyLater_deloadUntouched` | S1 `copyPreviousWeek_takesTheScheduleOnly`, `applyToLaterWeeks_leavesTheDeloadFlags` |
| `test_editing_addDay_nameTag`, `test_editing_deleteDay_clearsSchedule` | S1 `addDay_isNamedAndTaggedByCount_withNoSlots`, `deleteDay_turnsItsScheduleEntriesIntoRest` |
| `test_editing_addSlots_rule7Defaults` | S2 `DayEditingTests.newSlot_hasRule7Defaults`, `addSlots_appendsInOrder` |
| `test_editing_reps_pushesRepsHi`, `…repsHi_snapsAboveReps`, `…clamps_allFields` | S2 `setReps_atOrAboveTheTop_pushesTheTop`, `setRepsHi_atOrBelowReps_snapsAbove`, `set_clampsEveryField` (a table) |
| `test_editing_double_setsRepsHiPlus2` | S2 `setProgression_double_widensTheRangeToTwo` |
| `test_editing_move_soloPastBlock`, `…withinBlock_swapsAndReletters`, `…blockAsUnit` | S2 `DayEditingMoveTests.move_soloSlot_passesTheWholeGroup`, `move_insideAGroup_swapsTheTwoMembers`, `move_fromAGroupsEdge_carriesTheGroup` |
| `test_editing_move_invariant_firstOfBlockNotSuperset` (property) | S2 `DayEditingPropertyTests.move_keepsEveryGroupAndTheNormalForm(seed:)`, the six assertions of "Group-aware move, defined" |
| `test_editing_toggleSuperset_breakOut` | S2 `setSuperset_joinsAndBreaksOut` |
| `test_editing_weekLoads_doubleProgressionExample`, `…deloadRoundsToStep` | S2 `ProgressionRulesTests.prescriptions_inclineDBPress_followRule10`, `prescriptions_backSquatWeek8_isTheDeload` |
| `test_store_builder_defaultProgramPresentation` | S5 `ProgramPresentationTests.seedProgram_readsAsCriterionOne` |
| `test_store_save_debounced` | S13 `ProgramStoreTests.edit_isSavedAtOnce_andEditsMadeMeanwhileGoTogether` |
| `test_store_validation_messages` | S5 `message_twoWeeks`, `message_loggedWeek`; S13 `removeWeek_atTwoWeeks_showsTheMessage_andChangesNothing` |
| `test_dayEditor_subLine_formats` | S6 `DayEditorPresentationTests.subLine_linearDoubleFixedDropAndNoRest` |
| `test_dayEditor_previewStrip_text` | S7 `SlotEditorPresentationTests.weekStrip_marksTheDeloadWeek`, `weekLine_deloadAndHeld` |
| `test_dayEditor_restLabel_formats` | Not added: the label is the Domain's (`LedgerDomain/Units/RestDuration.swift:26`) and has its table (`Tests/LedgerDomainTests/Units/RepsRPERestTests.swift:16-19`). |
| `test_picker_filtersCombine` | S2 `ExerciseSearchTests.filter_queryMuscleAndEquipmentCombine` |
| `test_picker_alreadyInDay_flag`, `test_picker_ctaLabel_pluralisation` | S8 `ExercisePickerPresentationTests.row_alreadyInTheDay_saysSo`, `cta_noneOneAndMany` |
| `test_picker_clearFilters`, `test_picker_customExercisesIncluded` | S14 `ExercisePickerStoreTests.clearFilters_resetsQueryMuscleAndEquipment`, `customExerciseSavedWhileOpen_appears` |

**Not added.** The brief's two persistence tests (row 24 of "Brief vs main"). The brief's UI flow
`program_edit_reflects_on_today` is F15's (`tasks/features/F15-ios-ui-tests.md:37`).

**Added.**
- S1: `ProgramEditingPropertyTests` (below); `removeLastWeek_leavesEveryDayAndSlotUntouched`; the behaviours
  3–5.
- S2: `DayEditingPropertyTests`; `clampingInitializers_roundToTheStepAndStayInRange` for `RPE` and
  `RestDuration`; `noFunction_changesMissesOrTheExerciseOfAnExistingSlot` (what "Saving and a live workout"
  relies on); the behaviours 7–12.
- S3: contract clauses "update applies the change to what is stored and returns it", "a change that throws
  writes nothing", "update of a program that is not stored throws missingRow", "update refuses what save
  refuses", "an update that changes nothing wakes no observer"; in the linked contract, "a builder edit sent
  after a workout's save keeps the save's misses and its swap", and, as a documented counter-example, the same
  sequence through `save` losing both.
- S5–S8: one seeded property suite per presentation (it never traps and never returns an empty label, for any
  program of 2–52 weeks and 0–12 days); `FeatureProgramSourceTests.storesAndPresentations_neverClamp` (no
  `min(`, `max(` or assignment to `repsHi` in a store or presentation file: the DoD's line, brief:97).
- S9–S12: the VoiceOver trees and the snapshots below; preview tests.
- S13–S14: the behaviours 1, 2, 14–17; `route_isEmittedOnce_afterTheSaveReturned`;
  `viewGoesAwayDuringASave_storesAllOrNothing`; `ProgramRouteMappingTests` (`LedgerAppKitTests`); nightly UI
  tests `Builder.addDayAddExerciseChangeProgression` (`docs/testing-strategy.md:246`) and one per screen that
  scrolls (`F08-s3-root-gate:docs/testing-strategy.md:259-263`).

**Properties and seeds.** Each runs over `PropertySeed.all` (200 seeds in the pull-request lane, 2,000 nightly;
`Tests/LedgerDomainTests/Support/SeededGenerator.swift:22-38`) and carries `.tags(.property)`
(`Tests/LedgerDomainTests/Support/Tags.swift:10`); a failing seed becomes a fixed case.
- S1 `ProgramEditingPropertyTests.randomEdits_keepTheProgramValid(seed:)`: a random program (2–12 weeks, 0–6
  days) and thirty random edits; after each, the result passes `Program.init`, its week indices are 0…n−1, no
  schedule names a missing day, ids are unique. Also: cycling one cell (days + 1) times returns the start;
  `addWeek` then `removeLastWeek` is the identity.
- S2 `DayEditingPropertyTests`: the move property; `set_anyValue_givesASlotTheModelAccepts(seed:)` (every result
  rebuilt through `Slot.init`); `randomEdits_keepTheNormalForm(seed:)`.
- S3 `ProgramUpdateInterleavingTests.updatesAndWorkoutSaves_loseNothing(seed:)` on GRDB and in memory, with the
  fixed seed list the session suites use in the pull-request lane (`docs/testing-strategy.md:379-385`).

**One pinned VoiceOver tree per screen** (convention 5), written here as intended and confirmed in the views
slice's own notes before any view is written. Each is read from the screen's pinned parts and its page,
stacked in reading order and hosted without the scroll view (`F08-s3-root-gate:docs/testing-strategy.md:234-258`).

- *Builder* (S9). "MY PROGRAM", heading. The program's name: a text field labelled "Program name". Block
  length: one adjustable element, value "8 weeks" (up adds a week, down removes the last). One button per
  week: "Week 1", value "4 days" or "Deload", selected when it is. "WEEK 1" or "WEEK 8 · DELOAD", heading.
  Seven buttons: "Tuesday", value "Rest" or the day's short title, with the hint that it assigns the next
  day. "Copy week 2" (or "First week", disabled), "Apply to later weeks", "Deload" (selected when on).
  "TRAINING DAYS", heading; the summary line; the helper line. One button per day: its name, value "5
  exercises · 18 sets · ~39 min" (the chips of short names are hidden from VoiceOver). "+ Add training day".
- *Day editor* (S10, S11). Pinned: the back button, "DAY 1 OF 4" as heading, "Done", the day's name as a text
  field labelled "Day name", the summary line. Page: for a superset, "SUPERSET" as heading with its note; one
  button per exercise, "4A, Lat Pulldown", value "3×12, 100 lb, Cable · Reps 12–14 · RPE 9 · no rest", saying
  whether it is open. Under an open exercise: the week line as text; one adjustable element per field ("Sets",
  value "3"); "PROGRESSION", heading; three buttons, one selected; the note; "Drop set", a switch with the
  note as its hint; "Break out" or "Superset with next"; "Move up", "Move down", "Remove"; the loads of every
  week as one text element. Then "+ Add exercise from library" and "Delete day".
- *Exercise library* (S12). Pinned: "Exercise library" as heading, "Cancel", the search field; at the foot the
  button "Add 3 exercises", or "Select exercises to add", disabled. Page: the muscle chips and the equipment
  chips, one selected in each; one button per exercise, its name, value "Machine · Back" (with "already in
  this day" when so), selected when picked; or "Nothing matches that filter." and "Clear filters".

**Snapshots**, from the same parts, as F08 records them: a screen's main state at the six cells of
`docs/testing-strategy.md:163-166`, the others at light and dark, `.large`.

| Slice | States | Images |
|---|---|---|
| S4 | `StepperField`, the toggle style, the wrapping layout, six cells each | 18 |
| S9 | default (6); deload week selected, a day with no exercise, the two-weeks message (2 each) | 12 |
| S10 | all closed (6); a day with a superset (2) | 8 |
| S11 | open, linear (6); open, double; drop set on (2 each) | 10 |
| S12 | results (6); three picked; nothing matches (2 each) | 10 |

The DoD's screenshots at the default size and at AX5 (brief:99) are taken by hand on the simulator in S14.

**What the adversarial tester should attack hardest.**

| Slice | Attack |
|---|---|
| S1 | Chains of edits that end in a program `Program.init` refuses. Cycling with no day, one day, a day scheduled twice in a week. "Apply to later weeks" on the last week. Names of only control characters, of combining marks, of 10,000 characters. `loggedWeeks` holding indices outside the block. An id used twice. |
| S2 | The move property at 2,000 seeds. Coupling at the limits (reps 30 with top 31; top 2; reps 1). Values off the step handed to `set`. Start loads: none, zero, off the steps, kettlebells in kilograms, a custom exercise with one unit or a negative load. Flags after chains of remove, add and move. The filter: diacritics, full-width letters, a blank query, who is in "Legs". |
| S3 | Seeded interleavings of `update`, `save`, `materialize`, `delete` and `setActive` on both stores. A change that throws half-way. A change that returns another program's id, a slot another program holds, an unknown exercise. Exactly one emission per update that changes something. A cancelled task. |
| S4 | Accessibility sizes, Bold Text, Increase Contrast, right-to-left. The adjustable action at its limits. The 44 pt targets. The wrapping layout with no child, one child, a child wider than the row. |
| S5–S8 | No day; 2 and 52 weeks; a week with no day and one with one (the plural forms); kilograms; a day scheduled twice in one week; a block that started mid-week with another week start set; a locale that groups digits differently. |
| S9–S12 | The trees at `.accessibility3`. Long names. Sixteen weeks. Twelve exercises in a day. The sheet at accessibility sizes. Any scroll view inside a page. |
| S13–S14 | An `update` held by a probe while edits arrive. A workout saved between two edits, on GRDB. The view going away during a save. A route emitted twice. A failure, then a success. The day deleted under the Day editor. A double tap on "+ Add training day". |

**Existing tests that are affected.**

| Test | What happens | Slice |
|---|---|---|
| `Tests/FeatureProgramTests/FeatureProgramTests.swift:7` | Its subject, the placeholder, is deleted. | S5 deletes it. |
| `scripts/coverage-gate.sh` with `scripts/coverage-thresholds.json:15` | The module has code, so it must be in `required`. | S5. |
| `LedgerDesignTests`' preview scan (`LedgerTestSupport/Previews/PreviewScan.swift:9`) | Fails once `FeatureProgram` has a `#Preview` and is not registered. | S9. |
| Every type that conforms to `ProgramRepository` | Does not compile until it has `update`. Listed under Risks 2. | S3. |
| The contract suites (`Tests/LedgerPersistenceTests/ProgramRepositoryTests.swift:23-24`, `InMemoryContractTests.swift:37-38`) | Run the new clauses by themselves. | S3. |
| `LedgerDesignTests`' gallery and preview tests | Need the three new components' entries. | S4. |

## Risks

Ranked. Each ends with what would show it early.

1. **A builder save loses a finished workout's misses or its swap.** This is why S3 exists ("Saving and a live
   workout"). *Early sign:* S3's first test is the losing sequence run through `save`; it must fail before
   `update` is written and pass through `update` after.
2. **S3 adds a protocol requirement with no default.** On `main` four types in `Sources` conform
   (`LedgerPersistence/Repositories/GRDBProgramRepository.swift:7`, `LedgerFakes/InMemoryProgramRepository.swift:14`,
   `LedgerDependencies/Unimplemented/UnimplementedStores.swift:35`, `LedgerTestSupport/Engine/ProbedStores.swift:121`)
   and four test doubles (`Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:76`,
   `Tests/LedgerSyncTests/Adversarial/HostSiegeStoresAdversarialSupport.swift:122`,
   `Tests/LedgerSyncTests/LocalWorkoutSessionActorMissTests.swift:131`,
   `Tests/LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift:28`). The F08 branch holds seven more
   doubles that `main` does not have (`F08-s3-root-gate:LedgerKit/Tests/FeatureOnboardingTests/Adversarial/OnboardingAdversarialStores.swift:11`,
   `…/FeatureOnboardingTests/Support/StoreDoubles.swift:13` and `:54`,
   `…/LedgerAppKitTests/Adversarial/AppRootGateAdversarialProbes.swift:19`, `…/RootGateAdversarialScript.swift:116`,
   `…/RootGateStoreAdversarialSupport.swift:133`, `…/LedgerAppKitTests/Support/GateSupport.swift:77`). Each
   needs about five lines when `main` is merged into its branch. *Early sign:* that merge stops compiling. If
   the orchestrator finds the cost too high, the default body weighed and rejected above is the fallback, with
   the contract still pinning the two real stores.
3. **The screens have no design** (Pete's decision 1). Rework is likely after the first screenshots. *Early
   sign:* S4's gallery references are the first thing he can look at. The presentations (S5 to S8) hold no
   look, so they survive a change of it.
4. **The estimates run low.** Fourteen slices at about 4,250 lines leave little room for it.
   *Early sign:* S5's count (see the notes under the slice table).
5. **Ten of fourteen slices wait for #28.** *Early sign:* none F11 can act on; S1 to S4 are the work until then.
6. **Screens that scroll.** The convention is on the F08 branch only
   (`F08-s3-root-gate:docs/testing-strategy.md:234-290`). Three of its points bite here: a row that scrolls
   sideways inside a page is "not settled" (`:276`), so the week chips wrap; a sheet whose content scrolls is
   split like a screen (`:272`); a multi-line text field reads as a scroll view (`:283`), so every field here
   is one line. *Early sign:* S9's tree test, which hosts the page: an element missing from the tree means a
   scroll view crept in.
7. **Names saved as they are typed** mean a write per keystroke, each of one row. *Early sign:* S13's test
   types ten letters against a held probe and expects two writes.
8. **One catalog file edited by S6, S7 and S8 at once.** Its keys must stay in code-unit order
   (`F09-s1-tab-shell:docs/engineering-standards.md:206`). *Early sign:* the gate's catalog step on the
   merged branch.
9. **Resuming a workout whose day was deleted or emptied** ("A live workout, and a finished one"). *Early
   sign:* F10 S4's specification; it should name this case.
10. **A block written in pounds and shown in kilograms** has start loads off the kilogram steps (behaviour 10),
    and the strip of weekly loads prints them to one decimal. *Early sign:* S7's kilogram test.
11. **Performance** (brief:85). Every edit rebuilds the whole display model; prescriptions for every week are
    computed for the open exercise only. *Early sign:* S5's nightly timing of `ProgramPresentation` at 16 weeks
    × 6 days (budget 100 ms for the first frame) and at 52 × 12.
12. **Slot fields assigned without `Slot.init`** ("Brief vs main", row 11). *Early sign:* S2's property test
    that rebuilds every result through `Slot.init`.

## Inputs the implementer needs

S1, S2, S3 and S4 can start today. Each section below, the brief and the standards are enough to start that
slice. The later slices get their inputs from the slice before them, as F09's did.

### S1 — block editing

**Read.** `docs/engineering-standards.md` §2 (the Domain imports Foundation only; `Tests/LedgerDomainTests/ModuleBoundaryTests.swift`
checks it), §4, §5, §9–§12; `docs/testing-strategy.md` §2.1, §3, §6; the brief's "Domain changes" and criteria
2–6; the spec §3.2 (`docs/product-spec.md:172-202`) and rules 4, 5 and 8 (`:722-726`); v1:1247-1254 (weeks),
1292-1299 (copy, apply, deload), 1308-1312 (cycle), 1323-1326 (add a day); in this file, "Brief vs main" rows
5–9, 16 and 30, "The editing functions, as proposed", and behaviours 3–5 and 18.

**Signatures on `main`.**
- `Program` — `LedgerDomain/Model/Program.swift:12`. `name`, `startDate`, `weeks`, `days` are `var` (`:14-19`).
  Its `init` throws `ProgramValidationError` (`:24-33`) and checks: at least two weeks (`:47`), week indices
  exactly 0…n−1 (`:50-52`), no schedule entry naming a day the program lacks (`:54-59`). `week(at:)` — `:64`.
- `Week` — `LedgerDomain/Model/Week.swift:36-47`: `id` (`:37`), `index` (`:38`), `isDeload` (`:39`),
  `schedule: [Weekday: DayTemplateID]` (`:40`). A weekday missing from the schedule is a rest day (`:35`): rest
  is the absence of a key. `Weekday` — `:7-8`, Monday = 1, `CaseIterable`.
- `DayTemplate` — `LedgerDomain/Model/DayTemplate.swift:4-17`; `init(id:name:tag:slots:)` — `:12`.
- `WeekID`, `DayTemplateID` — `LedgerDomain/Identifiers.swift:38-50`, each `init(_ rawValue: UUID)`.
- `ProgramValidationError` — `LedgerDomain/Errors.swift:4-11`: the shape for `ProgramEditError`
  (`Error, Equatable, Sendable`), which goes at the end of that file.
- Test support, all in the test target: `Fixtures.week(_:deload:schedule:)` —
  `Tests/LedgerDomainTests/Support/Fixtures+Program.swift:67`; `Fixtures.program(days:weekCount:startDate:)` —
  `:73` (it schedules the first three days on Monday, Wednesday and Friday, and week index 7 is the deload);
  `Fixtures.uuid(_:)` — `Tests/LedgerDomainTests/Support/Fixtures.swift:33`; `Fixtures.programID` — `:30`;
  `SeededGenerator` and `PropertySeed.all` — `Tests/LedgerDomainTests/Support/SeededGenerator.swift:4`, `:34`;
  the tags `.domain` and `.property` — `Tests/LedgerDomainTests/Support/Tags.swift:8`, `:10`. A property test
  to copy the form of: `Tests/LedgerDomainTests/Rules/SupersetRoundsTests.swift:111-112`.

**Fixture to add** (to `Fixtures+Program.swift` in the test target): `Fixtures.fourDayProgram()`, the spec's
seed schedule (`docs/product-spec.md:660`): four days with no slots, tagged UA, LA, UB, LB, with ids
`uuid(300)`, `uuid(310)`, `uuid(320)`, `uuid(330)`; eight weeks from `week(0)` to `week(7)`; weeks 1–7 train
UA on Monday, LA on Wednesday, UB on Friday, LB on Saturday; week 8 trains the first three and is the deload.

**What each function does, and the rule it enforces.**

| Function | Behaviour | Rule |
|---|---|---|
| `cleanedName` | Removes every scalar of general category `Cc`, then trims white space and newlines; `nil` when nothing is left. | brief:55 |
| `renameProgram`, `renameDay` | Sets the cleaned name. A blank name, or a day the program lacks: unchanged. | — |
| `addWeek(_:id:)` | Appends a week with `index = weeks.count`, the last week's schedule, `isDeload = false`. An id in use: unchanged. | 4 (`docs/product-spec.md:722`) |
| `removeLastWeek(_:loggedWeeks:)` | Two weeks or fewer: throws `.minimumTwoWeeks` (checked first). The last index in `loggedWeeks`: throws `.weekHasLoggedSessions(weekNumber: lastIndex + 1)`. Otherwise drops the last week. | 4 |
| `toggleDeload(_:week:)` | Flips that week's flag. | — |
| `cycleSchedule(_:week:weekday:)` | Rest → `days[0]` → … → the last day → rest, in the order of `program.days`. Rest removes the key. No days: unchanged. | 5 (`:723`) |
| `copyPreviousWeek(_:week:)` | The week takes the schedule of the week before; its deload flag stays. Week 0: unchanged. | spec `:198` |
| `applyToLaterWeeks(_:week:)` | Every later week takes this week's schedule; every deload flag stays. | spec `:199` |
| `addDay(_:id:name:)` | Appends a day with the cleaned name, no slots, and the tag "D{n}", n the new number of days, or the next number whose tag is free. An id in use, or a blank name: unchanged. | 8 (`:726`) |
| `deleteDay(_:day:)` | Removes the day and every schedule entry that names it. | — |
| `updateDay(_:day:_:)` | Replaces the day by `change(day)`. A result with another id is ignored. | — |

Every function returns a program that `Program.init` accepts; the property test proves it by rebuilding each
result through `Program.init`. Fields are assigned directly ("Brief vs main", row 11).

**The criteria as input → output**, on `Fixtures.fourDayProgram()` (`p`):

- Criterion 2. `cycleSchedule(p, week: 0, weekday: .tuesday)` applied one to five times: Tuesday of week 1
  holds UA, then LA, UB, LB, then no entry. The number of scheduled weekdays in week 1 goes 5, 5, 5, 5, 4.
- Criterion 3. `copyPreviousWeek(p, week: 2)`: `weeks[2].schedule == weeks[1].schedule`.
  `applyToLaterWeeks(q, week: 2)`, with `q` a program whose week 3 trains Tuesday as well: weeks 4–8 have
  week 3's schedule, week 8 is still the only deload and now trains Saturday and Tuesday too.
  `toggleDeload(p, week: 2)`: `weeks[2].isDeload == true`.
- Criterion 4. A two-week program: `removeLastWeek` throws `.minimumTwoWeeks` whatever `loggedWeeks` holds.
  `removeLastWeek(p, loggedWeeks: [7])` throws `.weekHasLoggedSessions(weekNumber: 8)`.
  `removeLastWeek(p, loggedWeeks: [0, 3])` returns seven weeks. `addWeek(p, id: WeekID(uuid(208)))`: nine
  weeks; `weeks[8]` has index 8, week 8's schedule (three days) and is not a deload.
- Criterion 5. `addDay(p, id: DayTemplateID(uuid(340)), name: "New day")`: `days[4]` is "New day", tagged "D5",
  with no slots; no schedule changed.
- Criterion 6. `deleteDay(p, day: DayTemplateID(uuid(330)))`: three days are left; no week has a Saturday
  entry; weeks 1–7 train three days.

**Files S1 creates or changes.**
- new `LedgerKit/Sources/LedgerDomain/Programs/ProgramEditing.swift`
- new `LedgerKit/Sources/LedgerDomain/Programs/ProgramEditing+Days.swift`
- `LedgerKit/Sources/LedgerDomain/Errors.swift` (appends `ProgramEditError`)
- new `LedgerKit/Tests/LedgerDomainTests/Programs/ProgramEditingTests.swift` and `ProgramEditingPropertyTests.swift`
- `LedgerKit/Tests/LedgerDomainTests/Support/Fixtures+Program.swift` (appends `fourDayProgram()`)
- this file (the slice's own section)

Nothing else: `LedgerKit/Package.swift` needs no change for a new folder, and `LedgerFakes` is not touched.
The two source files exist because of the lint limits (`.swiftlint.yml:52-60`).

### S2 — day editing

**Read.** The brief's criteria 7–12; the spec §3.4 (`docs/product-spec.md:219-260`), rules 1–3, 6 and 7
(`:719-725`), §7.2 (`:728-746`) and rule 44 (`:792`); decisions #9, #22, #24; v1:844-848 (superset groups), 1104-1123
(steppers, start load, progression, superset, drop set), 1354-1356 (which superset action is offered),
1387-1389 (move, remove), 1420-1428 (add); in this file, "Brief vs main" rows 10–15 and 27, "The editing
functions, as proposed", "Group-aware move, defined", and behaviours 7–12 and 18.

**Signatures on `main`.**
- `Slot` — `LedgerDomain/Model/Slot.swift:14`; its fields are `var` (`:16-34`); `init` and the order of its
  checks — `:36-52`; the ranges — `:76-101`. `Progression` — `:4-6`.
- `RPE` — `LedgerDomain/Units/RPE.swift:7`; failable `init` — `:11`; `private init(halfPoints:)` — `:19`;
  `value` — `:24`. `RestDuration` — `LedgerDomain/Units/RestDuration.swift:6`; `init?(seconds:)` — `:10`;
  `private init(validSeconds:)` — `:17`; `defaultRest` — `:22`; `label` — `:26`. The model for the two new
  clamping initializers: `Reps(clamping:)` — `LedgerDomain/Units/Reps.swift:18`.
- `Weight` — `LedgerDomain/Units/Weight.swift:14`; `.zero` — `:21`; `rounded(toStep:_:)` — `:69-78` (it takes
  a rounding rule, so `.up` and `.down` give the next multiple of a step); `advanced(bySteps:of:)` — `:81`.
- `Exercise.startLoad(in:)` — `LedgerDomain/Model/Exercise.swift:71`; `Equipment.defaultStep(in:)` — `:9`;
  `Equipment` — `:4`; `MuscleGroup` — `:21`.
- `ProgressionRules.prescribe(week:weekIndex:slot:exercise:units:)` — `LedgerDomain/Rules/ProgressionRules.swift:21`.
- `SupersetRounds.groups(joiningPrevious:)` — `LedgerDomain/Rules/SupersetRounds.swift:61` (internal;
  `DayEditing.groups(of:)` calls it); `letter(forMemberAt:)` — `:51`. `TimeEstimate` groups the same way —
  `LedgerDomain/Rules/TimeEstimate.swift:18`.
- `ExerciseSearch` — `LedgerDomain/Rules/ExerciseSearch.swift:11`; `key(_:)` — `:14`;
  `matches(name:shortName:needle:)` — `:26`; `sorted(_:)` — `:37`.
- Test support: `Fixtures.upperA()` — `Tests/LedgerDomainTests/Support/Fixtures+Program.swift:42` (slots 301 to
  305, the last two a superset, start loads `nil`, so they come from the exercise); `upperB()` — `:58` (one
  slot with a drop set); `slot(…)` — `:9`; the exercises `bench`, `inclineDB`, `backSquat` —
  `Tests/LedgerDomainTests/Support/Fixtures.swift:88-93`; `rpe(_:)`, `rest(_:)` — `:72`, `:76`. For the
  filter: `ExerciseCatalog.seed()` — `LedgerDomain/Catalog/ExerciseCatalog.swift:78`.

**What each function does, and the rule it enforces.**

| Function | Behaviour | Rule |
|---|---|---|
| `newSlot` | 3 sets, reps 8, top of range 10, RPE 8, rest `defaultRest`, linear, start load `exercise.startLoad(in: units)` copied in, no step of its own, no superset, no drop set, no misses. | 7 (`docs/product-spec.md:725`), 3 |
| `addSlots` | Appends the slots in order; one whose id the day holds is left out. | spec `:260` |
| `removeSlot` | Removes it. If it led a superset group, the next member leads (behaviour 7). | — |
| `set(.sets)`, `.rpe`, `.restSeconds` | Clamped to 1…12; to 5…10 on the half; to 30…300 on the 15. | 3 (`:721`) |
| `set(.reps)` | Clamped to 1…30; then, if the top of the range is not above it, the top becomes `reps + 1`. | 2 (`:720`) |
| `set(.repsHi)` | Clamped to 2…40; then, if it is not above reps, it becomes `reps + 1`. | 2 |
| `set(.startLoad)` | Never below zero. | 6 (`:724`) |
| `stepped` | The field one step away from the slot's value: ±1; ±0.5 for RPE; ±15 s for rest; for the start load, the next multiple of the step in that direction (see "The editing functions"). It does not clamp. | 1 (`:719`), 6 |
| `setProgression` | Sets it; for `.double`, the top of the range becomes `max(top, reps + 2)`. | brief:48 |
| `setDropSet` | `dropSets` 1 or 0. | spec `:246` |
| `setSuperset` | Sets the slot's flag; the day's first slot always ends false. | spec `:247` |
| `move` | "Group-aware move, defined". | brief:56 |
| `groups(of:)` | The slot ids in their superset groups, in order. | 44 (`:792`) |
| `ProgressionRules.prescriptions` | `prescribe` for each of `weeks`, with the week's own index. | §7.2 |
| `ExerciseSearch.filter` | Folds the query once; keeps the exercises whose primary muscle is in the chip's groups, whose equipment is the one asked for, and whose name or short name holds the query; in name order. | decision #23 |

`RPE(clamping:)` rounds to the nearest half and clamps to 5…10. `RestDuration(clampingSeconds:)` rounds to the
nearest 15 and clamps to 30…300. `Slot.setsRange`, `repsRange` and `repsHiRange` replace the literals at
`Slot.swift:77`, `:80`, `:83`.

**The criteria as input → output.**

- Criterion 7. For `upperA()`'s Incline DB Press (slot 302: double, 10 to 12, start 50 lb from the exercise,
  step 2.5 lb) over eight weeks whose last is a deload: loads 50, 50, 50, 52.5, 52.5, 52.5, 55, then
  55 × 0.85 = 46.75 → 47.5; reps 10, 11, 12, 10, 11, 12, 10, 11; week 8 has 2 sets at RPE 6. For Back Squat,
  5 × 5 linear from 250 lb by 5: week 8 is 285 × 0.85 = 242.25 → 240 lb, 4 sets, RPE 6 (`docs/product-spec.md:745`).
  With `misses = [2]`, the fourth week's prescription has `isHeld`.
- Criterion 8. From reps 8 and top 10: `set(.reps(9))` → 9 and 10; `set(.reps(10))` → 10 and 11;
  `set(.repsHi(8))` → 8 and 9. `set(.sets(0))` → 1; `.sets(13)` → 12; `.rpe(4.5)` → 5; `.rpe(10.5)` → 10;
  `.restSeconds(15)` → 30; `.restSeconds(315)` → 300; `.startLoad(.pounds(-5))` → zero. `stepped(.rest, .up, …)`
  from 150 s is `.restSeconds(165)`.
- Criterion 9, as read in "Brief vs main" row 12. Reps 8, top 9: `setProgression(.double, …)` → top 10. Reps
  8, top 12: the top stays 12.
- Criterion 10. A day of slots a, b, c, d, e with flags false, false, false, true, false (it reads 1, 2, 3A,
  3B, 4). `move(day, slot: b, .down)` → a, c, d, b, e with flags false, false, true, false, false.
  `move(day, slot: c, .down)` → a, b, d, c, e with flags false, false, false, true, false.
  `move(day, slot: c, .up)` → a, c, d, b, e.
- Criterion 11. Five slots, none joined: `setSuperset(true, slot: fifth, in: day)` → `groups(of:)` is four
  groups, the last holding the fourth and fifth; `setSuperset(false, …)` → five groups again.
- Criterion 12. `newSlot(id:exercise: Fixtures.bench, units: .lb, defaultRest: .defaultRest)`: 3 × 8, top 10,
  RPE 8, rest 90 s, linear, start load 180 lb. On `ExerciseCatalog.seed()`,
  `filter(…, query: "row", muscle: .back, equipment: .machine)` is exactly "Chest-Supported Row".

**Files S2 creates or changes.**
- new `LedgerKit/Sources/LedgerDomain/Programs/DayEditing.swift`, `DayEditing+Fields.swift`, `DayEditing+Move.swift`
- `LedgerKit/Sources/LedgerDomain/Model/Slot.swift` (the three ranges as public constants)
- `LedgerKit/Sources/LedgerDomain/Units/RPE.swift`, `Units/RestDuration.swift` (one clamping initializer each)
- `LedgerKit/Sources/LedgerDomain/Rules/ProgressionRules.swift` (`prescriptions`)
- `LedgerKit/Sources/LedgerDomain/Rules/ExerciseSearch.swift` (`MuscleFilter`, `filter`)
- new `LedgerKit/Tests/LedgerDomainTests/Programs/DayEditingTests.swift`, `DayEditingMoveTests.swift`,
  `DayEditingPropertyTests.swift`; additions to `Rules/ProgressionRulesTests.swift`,
  `Rules/ExerciseSearchTests.swift`, `Units/RepsRPERestTests.swift`
- this file

### S3 — atomic program update

**Read.** `docs/architecture.md` §7; ADR-002 and ADR-008 (the in-memory stores keep the database's rules); in
this file, "Saving and a live workout" (the requirement's rules are there) and Risks 1 and 2.

**Signatures on `main`.**
- The protocol — `LedgerDomain/Protocols/Repositories.swift:25-39`.
- GRDB — `LedgerPersistence/Repositories/GRDBProgramRepository.swift`: `save` — `:43-52` (the transaction and
  the activation to copy); `program(id:)` — `:27-29`; `activate` — `:107-115`.
  `LedgerPersistence/Records/ProgramRows.swift`: `init(_:)` — `:17`; `write(_:at:)` — `:53`;
  `program(_:in:)` — `:120`.
- In memory — `LedgerFakes/InMemoryProgramRepository.swift`: `save` — `:53-55`; the stored state — `:15-30`;
  `store(_:in:exercises:)` — `:133-167`; `writeSave` — `:81-92` (what a workout's save does under the same
  lock). `ObservedState.write` — `LedgerFakes/Support/ObservedState.swift:41-61`.
- The stub — `LedgerDependencies/Unimplemented/UnimplementedStores.swift:35-57`. The probe —
  `LedgerTestSupport/Engine/ProbedStores.swift:121-145` (it forwards everything but `active()`).
- The four test doubles to extend: Risks 2.
- The contracts — `LedgerTestSupport/Persistence/ProgramRepositoryContract.swift:14-28` (the clause list),
  `:34` (`program()`), `:41` (`edited(_:)`); `LedgerTestSupport/Persistence/WorkoutRepositoryContract+Linked.swift:184-205`
  (a clause that orders program writes and a workout's save: the model for the new one). Where they run:
  `Tests/LedgerPersistenceTests/ProgramRepositoryTests.swift:23-24`, `InMemoryContractTests.swift:37-38`. The
  form of a seeded test over both stores: `Tests/LedgerPersistenceTests/LinkedSaveDifferentialTests.swift`.

**Files S3 creates or changes.** `LedgerDomain/Protocols/Repositories.swift`;
`LedgerPersistence/Repositories/GRDBProgramRepository.swift`; `LedgerFakes/InMemoryProgramRepository.swift`;
`LedgerDependencies/Unimplemented/UnimplementedStores.swift`; `LedgerTestSupport/Engine/ProbedStores.swift`;
`LedgerTestSupport/Persistence/ProgramRepositoryContract.swift` (or a new `+Update.swift` beside it) and
`WorkoutRepositoryContract+Linked.swift`; the four test doubles; new
`Tests/LedgerPersistenceTests/ProgramUpdateInterleavingTests.swift`; this file. No migration and no schema
change.

### S4 — form controls

**Read.** `docs/engineering-standards.md` §7; `docs/architecture.md` §11; `docs/testing-strategy.md` §2.5; the
controls in v1: a stepper field 264–273, the toggle 283–291, chips that wrap 150–154 and 322–331; Pete's
decision 1.

**Signatures on `main`** (all under `LedgerDesign/`).
- The look and the VoiceOver behaviour to match: the private `StepperPill` — `Components/SetRowSteppers.swift:51-89`
  (one adjustable element, `:66-75`).
- `PillButton` — `Components/PillButton.swift:7-52`; `ledgerHitTarget()` — `Components/ControlStyle.swift:7`;
  `LedgerPressStyle` — `:56` (internal, so usable here); `LedgerIconView(_:sizedAs:)` — `Components/LedgerIcon.swift:52-58`,
  icons `.minus`, `.plus` — `:16`.
- Tokens: `LedgerSpacing` — `Tokens/LedgerSpacing.swift:5-13`; `LedgerRadius` — `Tokens/LedgerRadius.swift:4-12`;
  `LedgerHairline` — `Tokens/LedgerHairline.swift:5`; `LedgerColor` — `Tokens/LedgerColor.swift:18-52`;
  the type roles — `Tokens/LedgerFont.swift:13-18`.
- Where a component is registered: the preview registry — `Components/Components+Previews.swift:7-12`; the
  gallery — `Gallery/DesignGallery.swift:11-41`. Tests to extend, in `Tests/LedgerDesignTests/`:
  `ComponentSnapshotTests.swift`, `AccessibilityTreeTests.swift`, `ComponentAccessibilityTests.swift`,
  `DesignGalleryTests.swift`, `PreviewTests.swift`.

**Shape.**
- `StepperField(_ label: String, value: String, onStep: @escaping (StepperField.Direction) -> Void)`: the label
  in the small label style, the value in a numeral role, "−" and "+" as two 44 pt buttons. VoiceOver reads one
  adjustable element with the label and the value. The parts stack at accessibility sizes.
- `LedgerToggleStyle`, used as `.toggleStyle(.ledger)`: an ink track when on (not orange, by decision 1's
  default) and a knob that reads on both themes; VoiceOver keeps SwiftUI's switch.
- `WrapLayout(spacing:lineSpacing:)`, a `Layout`: children run along a row and wrap onto the next; a child
  wider than the row is given the row's width.

The components take `String`s and look nothing up. They compile for watchOS as well, as every `LedgerDesign`
addition does (`tasks/features/F10-active-workout/implementation-notes.md:443`). The same controls are what
Settings needs (`tasks/features/F14-settings.md:38`, `:44`).

**Files S4 creates or changes.** New `LedgerDesign/Components/StepperField.swift`, `LedgerToggleStyle.swift`,
`WrapLayout.swift`; `Components+Previews.swift`; `Gallery/DesignGallery.swift`; the five test files above and
their new references; this file.

## M1 shared conventions

The orchestrator's text, copied whole from `m1-shared-conventions.md` as the other features' notes carry it. Once #28 is on `main`, `docs/engineering-standards.md` §7 and `docs/architecture.md` §4 are the source for rules 1 and 3.


### M1 shared conventions (orchestrator, 2026-10-04; the same text is in the F08, F09 and F10 notes)

The three planners proposed the same patterns with small differences. These are the rulings; they hold for every M1
feature. F09 S1 lands the localization scaffolding and writes rules 1 and 3 into `docs/engineering-standards.md` §7 and
`docs/architecture.md` §4; once that slice is on `main`, the docs are the source and this block is a summary.

1. **Localization.**
   - One hand-written `Resources/Localizable.xcstrings` per module that has copy. Source language English. The key is
     the English text with its format specifiers. The target gains `resources: [.process("Resources")]`;
     `defaultLocalization: "en"` is set once in `Package.swift` (F09 S1).
   - All of a module's copy is resolved in its copy file(s): `<Feature>Copy.swift` (and `<Feature>Copy+<Area>.swift`
     when it grows), a `nonisolated enum` whose members return `String`, or `Text` only where the string embeds a live
     view such as a timer. No other file in the module holds a user-facing literal or a localized lookup: views,
     stores, presentation builders and `LedgerDesign` components receive `String`s.
   - Lines the Domain already formats (weights, volumes, receipt rows, the last-performance line, rest labels, clock
     text) and data (program and day names, catalog names) are shown as given and are not catalog entries.
   - One shared helper in `LedgerTestSupport/Localization/` and one test per module: every key the copy files use is in
     the catalog and the reverse; no lookup or user-facing literal outside the copy files; a plural key has `one` and
     `other`. A key holds at most one counted value; fragments are joined with " · ".
   - Shipped copy never contains the product name (`docs/product-decisions.md` › Naming).
2. **Stores.** `XRoot` (public; owns the store in `@State`; runs its async work from `.task` / `.task(id:)`),
   `XScreen(model:)` (only draws a state; what previews, snapshots and accessibility tests use), `XStore`
   (`@MainActor @Observable final class`; dependencies as `@ObservationIgnored @Dependency`; synchronous intents; no
   stored `Task` and no `Task { }` in a store or a view), `XPresentation` (a `nonisolated` namespace of pure functions
   from inputs to a display model). State is `Loadable<Model>` (`LedgerDomain`, lands with F09 S2) when the states
   are exactly loading / loaded / failed, otherwise a store-specific enum. Tests never sleep: they call the async
   method directly or await `Observations`.
3. **Routing.** A feature exposes `public nonisolated enum XRoute: Hashable, Sendable` and
   `XRoot(onRoute: @escaping @MainActor (XRoute) -> Void)`. `onRoute` is **synchronous**: a route is an intent, and the
   app resolves it (`LedgerAppKit/Routes.swift`, `Routes+<Feature>.swift`; every tab's stack is keyed by the one
   `AppDestination`). A feature never presents another feature. A feature with no exit the app must resolve
   (onboarding) has no route. A feature that presents itself over the tabs (the workout) exports its presenter and
   modifier; its start and resume entry points are synchronous intents as well, drained by its own `.task`.
4. **Shared one-line files** (`Package.swift` `snapshotTestTargets`, `scripts/coverage-thresholds.json` `required`,
   `LedgerTestSupport/Previews/PreviewScan.swift` `registeredModules`): add only your module's name. The orchestrator
   resolves the conflicts when it merges `main` into a branch.
5. **Accessibility.** One intended VoiceOver tree per component or screen, written down in these notes and pinned by a
   table-driven test before the tester starts (F06's lesson).
6. **Test names** follow `docs/testing-strategy.md` §6 (`subject_condition_expectation`, a sentence as the display
   name), not the briefs' `test_…` names.

### What in F11 does not fit them, with a proposal for each

1. **A row that scrolls sideways.** The prototype scrolls the week chips sideways (`docs/product-spec.md:179`).
   A scroll view inside a page is "not settled", and the first slice that needs one must raise it
   (`F08-s3-root-gate:docs/testing-strategy.md:276-282`). *Proposal:* the chips wrap, so no page holds a
   scroll view and the convention needs no exception. If Pete prefers the sideways row (decision 1), the
   orchestrator rules on the convention before S9.
2. **Names of Domain values shown by more than one feature** are "not settled", and the first slice that needs
   one in a second module must raise it (`F09-s1-tab-shell:docs/engineering-standards.md:247-251`). F11 shows
   equipment names (the Day editor's lines, the library), muscle names (the library) and progression names;
   F12's Library and F10's swap sheet show equipment and muscle names too. *Proposal:* each module's catalog
   holds its own entry for each name it shows. The key is the English text, so two modules cannot differ in
   English, and nothing shared has to be built. A shared copy module would need a new edge in the package
   graph and an ADR.
3. **One filter, two features.** The library's chips and its combined filter are needed by S8 and by F12
   (`tasks/features/F12-library-history.md:53`). *Proposal:* S2 writes them once in `ExerciseSearch`; F12 uses
   them. If F12's Domain slice starts first, S2 drops those 55 lines.
4. **One set of form controls, two features.** S4's controls are also F14's. *Proposal:* S4 builds them in
   `LedgerDesign`; F14 does not build its own.
5. **Convention 2 and saving.** A store's work runs from the view's task, so F11 builds no debounce timer, and
   a save in flight when a screen goes away is cancelled ("The 300 ms debounce"). No change to the convention
   is proposed.
6. **Convention 3 and two screens on one program.** The Day editor is pushed by the app and so owns a store of
   its own: two stores edit one program, which is safe only through S3's `update`. The Day editor asks the app
   to pop it (`ProgramRoute.closeDay`) and does not dismiss itself. How the shell hands `ProgramRoot` the week
   of Today's "Edit week" (`tasks/features/F09-today.md:40`) is settled in S14 with F09 S5, which maps that
   route. *Proposal:* the router keeps the week asked for beside its paths
   (`F09-s1-tab-shell:LedgerKit/Sources/LedgerAppKit/Routes.swift:21-37`), and `AppTabs` passes it on.
7. **Convention 4 and S3.** S3 touches every type that conforms to `ProgramRepository`, on `main` and on the
   waiting F08 branches (Risks 2); that is more than a one-line file. *Proposal:* the orchestrator adds
   `update` to those branches' test doubles when it merges `main` into them, or chooses the default body.

## Orchestrator rulings on the plan (2026-10-05)

1. **The plan is accepted.** Its S1 and S2 are built as one slice, S1 (about 570 product lines planned, one
   pull request while it stays under about 1,000): the two halves are the same kind of code, are tested the
   same way, share criterion 12 of the slice ("what editing never writes"), and a separate cycle of
   implementer, tester, reviewer and CI for 200 lines costs more than it buys. The number S2 is not used. If
   the slice is heading past about 950 lines, `ExerciseSearch.filter` and `ProgressionRules.prescriptions`
   move to the slice that first uses them (S8 and S7).
2. **Order.** S1 now. S3 (the atomic `update`) next: when `main` is later merged into the waiting F08 and F09
   branches, the orchestrator has `update` added to their test doubles (proposal 7; no default body). S4 (form
   controls) is built when S9 to S12 are near, since nothing uses it before them and its look is Pete's
   decision 1. S5 to S14 wait for pull request #28; their sizes are estimated again after S5.
3. **Proposals 1 to 6 on the conventions are accepted** as written: the week chips wrap; each module's catalog
   holds its own entry for each Domain name it shows (standards §7 gets that sentence in S5's pull request);
   the library's filter is written once in the Domain and F12 uses it; the form controls live in
   `LedgerDesign` and F14 uses them; no debounce timer; the Day editor has its own store and asks the app to
   pop it.
4. **For F10 S4** (recorded here because this plan found it): a minimised workout is resumed from the
   session's own state, never through `StartWorkoutUseCase.start`, which refuses a day the program no longer
   holds before it looks at the live workout.
5. **For S3:** what GRDB does with a write whose task is cancelled is established there, by a test, before
   S13 relies on "all of it is stored or none".

## Slice S1 — program and day editing (G1 implementer, 2026-10-05)

Built on `feat/F11-s1-program-editing` at `fee3c70`, on the host only. Nothing is committed. Paths are written
as in the rest of this file. Two numberings appear below: **S1 criterion n** is one of the thirteen of "Plan
amendments — slice S1" in the brief; **F11 criterion n** is one of the brief's acceptance criteria, whose
worked examples the tests use.

### What landed

Product, all in `LedgerDomain`:

- new `LedgerDomain/Programs/ProgramEditing.swift`: `cleanedName`, `renameProgram`, `addWeek`,
  `removeLastWeek`, `toggleDeload`, `cycleSchedule`, `copyPreviousWeek`, `applyToLaterWeeks`.
- new `LedgerDomain/Programs/ProgramEditing+Days.swift`: `addDay`, `renameDay`, `deleteDay`, `updateDay`.
- new `LedgerDomain/Programs/DayEditing.swift`: `SlotField` and `SlotField.Kind`, `StepDirection`,
  `MoveDirection`, and `DayEditing.newSlot`, `addSlots`, `removeSlot`, `setProgression`, `setDropSet`,
  `setSuperset`, `groups(of:)`.
- new `LedgerDomain/Programs/DayEditing+Fields.swift`: `DayEditing.set` and `stepped`.
- new `LedgerDomain/Programs/DayEditing+Move.swift`: `DayEditing.move`, alone in its file.
- `LedgerDomain/Errors.swift`: `ProgramEditError`, appended.
- `LedgerDomain/Model/Slot.swift`: `Slot.setsRange`, `repsRange`, `repsHiRange`, used by `validate`.
- `LedgerDomain/Units/RPE.swift`: `RPE(clamping:)`. `LedgerDomain/Units/RestDuration.swift`:
  `RestDuration(clampingSeconds:)`.
- `LedgerDomain/Rules/ProgressionRules.swift`: `prescriptions(for:weeks:exercise:units:)`.
- `LedgerDomain/Rules/ExerciseSearch.swift`: `MuscleFilter` (five chips) and `filtered` (named `filter` until fix round 1).

Tests, all in `Tests/LedgerDomainTests/`:

- new `Programs/ProgramEditingTests.swift` (names, weeks), `ProgramEditingScheduleTests.swift`,
  `ProgramEditingDaysTests.swift`, `ProgramEditingPropertyTests.swift`.
- new `Programs/DayEditingTests.swift` (slots, progression, drop set, superset),
  `DayEditingFieldsTests.swift`, `DayEditingStartLoadTests.swift`, `DayEditingMoveTests.swift`,
  `DayEditingNormalFormTests.swift`, `DayEditingPropertyTests.swift`.
- new `Programs/EditingTestSupport.swift`, `EditingTestSupport+Differences.swift`,
  `EditingTestSupport+Edits.swift`: seeded programs and days, random edits, the rebuild through
  `Program.init` and `Slot.init`, and short differences.
- new `Rules/ProgressionRulesPrescriptionsTests.swift`.
- additions to `Rules/ExerciseSearchTests.swift`, `Units/RepsRPERestTests.swift` and
  `Support/Fixtures+Program.swift` (`fourDayProgram()`, `fourDayIDs`). Each is an appended extension; no
  existing test changed (the diff of the three files has no removed line).

No other module, no repository, no feature code, no `Package.swift` change. `ExerciseSearch.filtered` and
`ProgressionRules.prescriptions` are both in: the slice is far under the size at which they were to move.

### Decisions and deviations

Deviations from the plan's text. Each was forced by the code or the lint, and none changes a rule.

1. **The direction cases are `upward` and `downward`, not `up` and `down`**
   (`LedgerDomain/Programs/DayEditing.swift:21`, `:27`). SwiftLint's `identifier_name` refuses a name under
   three characters, and its exclusions are `id`, `lb`, `kg` and the spacing steps (`.swiftlint.yml:41-46`).
   A suppression is not allowed and the lint's configuration is not this slice's. Call sites read
   `DayEditing.move(day, slot: id, .downward)` and `DayEditing.stepped(.rest, .upward, of: …)`.
2. **The tests of `prescriptions` are in a new file**, `Rules/ProgressionRulesPrescriptionsTests.swift`, not
   in `Rules/ProgressionRulesTests.swift`: that file has 285 lines and the lint stops at 300
   (`.swiftlint.yml:52-54`).
3. **More test files than the plan lists**, for the same limit and for the 150-line limit on a type's body
   (`.swiftlint.yml:55-57`): one suite per source file or topic (the list above), and three support files.
   The support is shared by ten suites, so it is not private to one of them.
4. **`RPE.step` and `RestDuration.stepSeconds`** (`LedgerDomain/Units/RPE.swift:24`,
   `LedgerDomain/Units/RestDuration.swift:22`), two internal constants beside the two clamping initializers
   the plan asks for. `DayEditing.stepped` reads them, so the size of a step is written once.
5. **One sentence added to `Slot`'s comment** (`LedgerDomain/Model/Slot.swift:13-14`). It told every editor
   to rebuild a slot through `init`; `DayEditing` now assigns fields, as "Brief vs main" row 11 decided.

Decisions the plan left to the implementer:

6. **Normal form and an unknown id.** Every `DayEditing` function reads the day as its normal form and returns
   a day in normal form (`DayEditing.swift:135-141`, `:144-151`). So a slot id the day does not hold returns
   the day unchanged when the day is in normal form, which every day these functions return is, and returns
   the normal form of a day that arrived with its first slot joined. The two sentences of S1 criteria 1 and 8
   disagree only on that one input (a day not in normal form and an unknown id); "always in normal form" was
   chosen because the plan says such a day "is read as its normal form". Pinned by
   `DayEditingNormalFormTests.firstSlotArrivesJoined_isReadAsItsNormalForm`.
7. **A week is found by its place in `weeks`** (`LedgerDomain/Programs/ProgramEditing.swift:105-112`), which
   `Program.init` keeps equal to `Week.index`. No function does arithmetic on a week index it was handed,
   so `Int.min` and `Int.max` cannot trap; `removeLastWeek` reports `weeks.count` as the week's number
   (`ProgramEditing.swift:52-66`).
8. **No edit traps on a slot whose numbers are outside the model.** A slot's fields are `var`, so a slot
   can hold `Int.max` reps. Sums on a slot's own numbers saturate (`DayEditing.saturatingSum`,
   `DayEditing.swift:155-161`), used by `stepped`, by the top-of-range coupling
   (`DayEditing+Fields.swift:48`) and by `setProgression`. For such a slot the result is not promised to be
   valid, only that nothing traps. Pinned by `DayEditingNormalFormTests.slotOutsideTheModel_noEditTraps`.
9. **A NaN** is no number and `Decimal` orders it below every number. `RPE(clamping: .nan)` is 5 and a NaN
   start load becomes zero (`DayEditing+Fields.swift:54`), with no branch written for it. Both are rows of
   `DayEditingFieldsTests.set_clampsEveryField`.
10. **The start load's step** (`DayEditing+Fields.swift:63-75`): the load is rounded to a multiple of the
    step towards the side asked for; if that multiple is not past the load (the load was on a multiple), it
    moves one step further; the result is never below zero. A step of zero, which only a slot set outside
    the model can hold, moves nothing.
11. **`addSlots` also leaves out an id that comes twice in one call**: the first wins
    (`DayEditing.swift:79`). The store draws a fresh id per pick, so this is a guard only.
12. **`deleteDay` of a day the program does not hold returns the program** before it looks at any schedule
    (`ProgramEditing+Days.swift:32`). `cycleSchedule` has no special case for a program with no days: the
    cell stays at rest (`ProgramEditing.swift:80-82`). An entry naming a day the program lacks, which
    `Program.init` refuses, would go to the first day.
13. **`cleanedName` removes control characters and does not put a blank in their place**: "A⇥B" becomes
    "AB". It trims what Foundation calls white space, which includes the zero-width space.
14. **Nothing was added to the proposed signatures**: no `SlotField.kind`, no `CaseIterable` on the
    directions. `DayEditing.editing`, `normalized` and `saturatingSum` are internal.

### Criteria → tests

Suites are in `Tests/LedgerDomainTests/Programs/` unless a folder is given.

| S1 criterion | Tests |
|---|---|
| 1 Pure and total | `ProgramEditingPropertyTests.randomEdits_keepTheProgramValid(seed:)` (every result rebuilt through `Program.init` and `Slot.init`), `unknownIDsAndWeeks_changeNothing(seed:)`; `ProgramEditingScheduleTests.weekOutsideTheBlock_changesNothing` (−1, 8, 9, `Int.max`, `Int.min`); `ProgramEditingTests.blockWithNoWeeks_noFunctionTraps`; `DayEditingNormalFormTests.unknownSlot_changesNothing`, `emptyDay_staysEmpty`, `slotOutsideTheModel_noEditTraps`; `DayEditingPropertyTests.randomEdits_keepTheNormalForm(seed:)`. Typed throws: `ProgramEditingPropertyTests.removeLastWeek_followsRuleFour(seed:)` and `DayEditingTests.newSlot_negativeStartLoad_throws` each hold a closure that compiles only with the typed error. |
| 2 Names | `ProgramEditingTests.cleanedName_removesControlCharactersAndTrims` (11 rows), `cleanedName_longName_isKept`, `renameProgram_setsTheCleanedName`, `renameProgram_blank_changesNothing`; `ProgramEditingDaysTests.renameDay_setsTheCleanedName`, `renameDay_blank_changesNothing` |
| 3 Weeks (F11 criterion 4) | `ProgramEditingTests.addWeek_copiesTheLastWeeksSchedule_notADeload`, `addWeek_idInUse_addsNothing`, `removeLastWeek_atTwoWeeks_throwsMinimumTwoWeeks`, `removeLastWeek_loggedWeek_throwsWithItsNumber`, `removeLastWeek_lastWeekNotLogged_dropsIt`, `removeLastWeek_leavesEveryDayAndSlotUntouched`, `toggleDeload_flipsOneWeek`; `ProgramEditingPropertyTests.addWeek_thenRemoveLastWeek_isTheIdentity(seed:)`, `removeLastWeek_followsRuleFour(seed:)` |
| 4 Schedule (F11 criteria 2, 3) | `ProgramEditingScheduleTests.cycleSchedule_restThenEachDayThenRest`, `cycleSchedule_fromADay_goesToTheNext`, `cycleSchedule_noDays_changesNothing`, `cycleSchedule_oneDay_alternates`, `copyPreviousWeek_takesTheScheduleOnly`, `copyPreviousWeek_onTheSecondWeek_takesTheFirstWeeks`, `copyPreviousWeek_onTheFirstWeek_changesNothing`, `applyToLaterWeeks_leavesTheDeloadFlags`, `applyToLaterWeeks_onTheLastWeek_changesNothing`; `ProgramEditingPropertyTests.cycleSchedule_daysPlusOneTimes_returnsToTheStart(seed:)` |
| 5 Days (F11 criteria 5, 6) | `ProgramEditingDaysTests.addDay_isNamedAndTaggedByCount_withNoSlots`, `addDay_tagSkipsNumbersInUse`, `addDay_toAProgramWithNoDays_isTaggedD1`, `addDay_blankNameOrIDInUse_addsNothing`, `deleteDay_turnsItsScheduleEntriesIntoRest`, `deleteDay_scheduledTwiceInAWeek_clearsBoth`, `deleteDay_everyDay_leavesAValidProgram`, `deleteDay_unknownDay_changesNothing`, `updateDay_replacesTheDay`, `updateDay_resultWithAnotherID_isIgnored`, `updateDay_unknownDay_changesNothing` |
| 6 Slots (F11 criterion 12) | `DayEditingTests.newSlot_hasRule7Defaults`, `newSlot_kilogramsAndAnotherDefaultRest`, `newSlot_exerciseWithOneUnitOrNone_stillHasAStartLoad`, `newSlot_negativeStartLoad_throws`, `addSlots_appendsInOrder`, `addSlots_sameExerciseTwice_isAllowed`, `addSlots_idTheDayHolds_isLeftOut`, `addSlots_toAnEmptyDay_firstSlotIsNeverJoined`, `removeSlot_firstOfAGroup_theNextMemberLeads`, `removeSlot_otherPlaces_keepTheGroups`, `removeSlot_onlySlot_leavesAnEmptyDay` |
| 7 Fields (F11 criterion 8) | `DayEditingFieldsTests.set_clampsEveryField` (49 rows: each limit, each side of it, `Int.min`, `Int.max`, NaN, values off the step), `setReps_atOrAboveTheTop_pushesTheTop`, `setRepsHi_atOrBelowReps_snapsAbove`, `setStartLoad_isStoredExactly`, `stepped_isOneStepAway`, `stepped_atALimit_doesNotClamp`, `setStepped_atALimit_theValueStays`, `setStepped_repsAgainstTheTop_keepsTheRange`; `DayEditingStartLoadTests.steppedStartLoad_goesToTheNextMultiple` (13 rows, pounds and kilograms, kettlebells), `steppedStartLoad_offTheSteps_goesToTheNextMultiple`, `steppedStartLoad_manySteps_staysExact`, `steppedStartLoad_exerciseWithOneUnit_usesTheConvertedLoad`, `steppedStartLoad_neverBelowZero`; `DayEditingPropertyTests.set_anyValue_givesASlotTheModelAccepts(seed:)`, `steppedStartLoad_landsOnTheNextMultiple(seed:)`; `Units/RepsRPERestTests.rpeClampingInitializer_roundsToTheHalfAndStaysInRange`, `restClampingInitializer_roundsToFifteenAndStaysInRange`. The ranges: the existing `Model/SlotValidationTests` and `Adversarial/SlotAdversarialTests`, untouched. |
| 8 Progression, drop set, superset (F11 criteria 9, 11) | `DayEditingTests.setProgression_double_widensTheRangeToTwo`, `setProgression_awayFromDouble_keepsTheTop`, `setDropSet_isOneOrNone`, `setSuperset_joinsAndBreaksOut`, `setSuperset_off_inTheMiddle_splitsTheGroupThere`, `setSuperset_on_mergesWithTheGroupAhead`, `setSuperset_onTheFirstSlot_staysOff`, `groups_followTheFlags`; `DayEditingNormalFormTests.firstSlotArrivesJoined_isReadAsItsNormalForm`; `DayEditingPropertyTests.randomEdits_keepTheNormalForm(seed:)` |
| 9 Move (F11 criterion 10) | `DayEditingMoveTests.move_soloSlot_passesTheWholeGroup`, `move_insideAGroup_swapsTheTwoMembers`, `move_fromAGroupsEdge_carriesTheGroup`, `move_table` (15 rows), `move_changesOnlyOrderAndFlags`, `move_groupFromItsEdge_thenBack_swapsInsideTheGroup` (decision 2's oddity), `move_unknownSlotOrEmptyDay_changesNothing`, `move_firstSlotArrivesJoined_isReadAsItsNormalForm`; the six properties, numbered in the test: `DayEditingPropertyTests.move_keepsEveryGroupAndTheNormalForm(seed:)` |
| 10 Every week's prescription (F11 criterion 7) | `Rules/ProgressionRulesPrescriptionsTests.prescriptions_inclineDBPress_followRule10`, `prescriptions_backSquatWeek8_isTheDeload`, `prescriptions_missedWeek_marksTheNextAsHeld`, `prescriptions_useEachWeeksOwnIndex` |
| 11 The library's filter (F11 criterion 12) | `Rules/ExerciseSearchTests.filtered_queryMuscleAndEquipmentCombine`, `filtered_noChipsAndBlankQuery_givesEverythingInNameOrder`, `muscleFilter_groups`, `filtered_usesThePrimaryMuscleAndTheEquipment` |
| 12 What editing never writes | `DayEditingPropertyTests.noFunction_changesMissesOrTheExerciseOfAnExistingSlot(seed:)` (thirty random edits of a seeded program, drawn from every function of both namespaces, the day's functions through `updateDay`), `everyDayEdit_onDrawnSlots_leavesMissesAndExercise(seed:)`; `DayEditingNormalFormTests.everyEdit_leavesMissesAndTheExercise` |
| 13 The Domain's rules | Foundation only: the existing `ModuleBoundaryTests.sources_importFoundationOnly`. Exact decimals: `setStartLoad_isStoredExactly`, `steppedStartLoad_manySteps_staysExact` and the start-load rows compare grams; no `Double` is written in the new code. The ranges: every existing test of `Slot`, `RPE` and `RestDuration` passes as it was. Coverage: below. |

"Behaviour the brief leaves open": 3 `copyPreviousWeek_onTheFirstWeek_changesNothing`; 4
`addDay_tagSkipsNumbersInUse`; 5 `cleanedName_removesControlCharactersAndTrims`,
`renameDay_blank_changesNothing`; 7 `removeSlot_firstOfAGroup_theNextMemberLeads`; 8
`setSuperset_off_inTheMiddle_splitsTheGroupThere`; 9 `setSuperset_on_mergesWithTheGroupAhead`; 10
`steppedStartLoad_offTheSteps_goesToTheNextMultiple`; 11 `set_clampsEveryField`,
`setStepped_atALimit_theValueStays`; 12 `setProgression_awayFromDouble_keepsTheTop`; 18 the property suites
and `unknownSlot_changesNothing`.

How the tests were checked. Forty-one deliberate bugs were put into the product code in two batches, one
per function or rule (a clamp's bound, the order of `removeLastWeek`'s two checks, a coupling off by one, a
flag copied, the normal form dropped, the move reversed, `misses` cleared by `setDropSet`, …), and the suite
run on each batch. Forty were caught by a test of the function they were in. One survived:
`copyPreviousWeek` refusing week 2. `copyPreviousWeek_onTheSecondWeek_takesTheFirstWeeks` was added for it.
`setDropSet` clearing the misses was caught by the two seeded properties only, so
`everyEdit_leavesMissesAndTheExercise` was added as a fixed case. The product files were restored from
copies and the runs below are of the restored tree.

No test hands a program, a day or an array of slots to `#expect`. They compare ids, tags, flags and counts,
or expect `EditingTestSupport.difference(_:_:)` or `faults(in:)` to be empty; a failure prints a few words. The
log of a run with twenty bugs in the code at once was 7.8 MB.

### Code lines per file

Non-blank, non-comment lines added outside tests (`docs/engineering-standards.md:258-261`). Counted when
the block editing was done and again at the end.

| File | Lines |
|---|---|
| `LedgerDomain/Programs/ProgramEditing.swift` (new) | 71 |
| `LedgerDomain/Programs/ProgramEditing+Days.swift` (new) | 56 |
| `LedgerDomain/Errors.swift` | +4 |
| **Block editing** | **131** (planned about 200) |
| `LedgerDomain/Programs/DayEditing.swift` (new) | 97 |
| `LedgerDomain/Programs/DayEditing+Fields.swift` (new) | 60 |
| `LedgerDomain/Programs/DayEditing+Move.swift` (new) | 28 |
| `LedgerDomain/Model/Slot.swift` | +6 (3 replaced) |
| `LedgerDomain/Units/RPE.swift` | +4 |
| `LedgerDomain/Units/RestDuration.swift` | +5 |
| `LedgerDomain/Rules/ProgressionRules.swift` | +8 |
| `LedgerDomain/Rules/ExerciseSearch.swift` | +28 |
| **Day editing** | **236** (planned about 370) |
| **Total** | **367** (planned about 570) |

Tests and their support: thirteen new files of 2,250 lines in `Programs/`, one of 62 in `Rules/`, and 143
lines appended to three existing files.

### Runs

All from the worktree root, on the host, on the final tree. No simulator, no `xcodebuild`, no full gate.

| Command | Result |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerDomainTests` | exit 0. 939 tests in 149 suites passed, no issue, no compiler warning. Before the slice, on the same tree with only the product code added: 838 tests in 138 suites. |
| the same with `--enable-code-coverage` | exit 0. 939 tests in 149 suites. |
| `LEDGER_PROPERTY_SEED_COUNT=2000 swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'DayEditingPropertyTests\|ProgramEditingPropertyTests'` | exit 0. The 11 seeded tests, 2,000 cases each. |
| `scripts/check.sh --lint-only` | exit 0 (format, SwiftLint strict, package graph and pins, catalog version, script tests). |
| `git status --short` | the six product files and three test files above as modified; `Sources/LedgerDomain/Programs/`, `Tests/LedgerDomainTests/Programs/` and `Rules/ProgressionRulesPrescriptionsTests.swift` as new; this file. |

Not run by this slice: `scripts/check.sh` in full, the iOS and watchOS simulators, CI. `LedgerDomainTests`
also runs on both simulators in the gate; nothing here was seen there.

### Coverage

`xcrun llvm-cov report LedgerKit/.build/out/Products/Debug/LedgerDomainTests.xctest/Contents/MacOS/LedgerDomainTests
-instr-profile=LedgerKit/.build/out/Products/Debug/codecov/default.profdata <files>`, after the coverage run:

| File | Lines | Missed | Regions missed | Functions missed |
|---|---|---|---|---|
| `Programs/ProgramEditing.swift` | 84 | 0 | 0 of 38 | 0 of 20 |
| `Programs/ProgramEditing+Days.swift` | 60 | 0 | 0 of 27 | 0 of 12 |
| `Programs/DayEditing.swift` | 95 | 0 | 0 of 35 | 0 of 19 |
| `Programs/DayEditing+Fields.swift` | 51 | 0 | 0 of 33 | 0 of 8 |
| `Programs/DayEditing+Move.swift` | 40 | 0 | 0 of 14 | 0 of 6 |
| `Model/Slot.swift` (whole file) | 66 | 0 | 0 of 39 | 0 of 4 |
| `Units/RPE.swift` (whole file) | 40 | 0 | 0 of 16 | 0 of 9 |
| `Units/RestDuration.swift` (whole file) | 46 | 0 | 0 of 21 | 0 of 8 |
| `Rules/ProgressionRules.swift` (whole file) | 42 | 0 | 0 of 13 | 0 of 6 |
| `Rules/ExerciseSearch.swift` (whole file) | 53 | 0 | 0 of 24 | 0 of 17 |

The five new files and every line added elsewhere are covered, by line, region and function.
`Errors.swift` has no executable line. `LedgerDomain` as a whole on the host: 2,514 lines, 29 missed,
98.85 % (the gate asks 95 %, from the simulator bundles).

### Open questions, with a recommendation each

1. **`upward` and `downward`** (deviation 1). *Recommendation:* keep them. If the plan's `up` and `down` are
   wanted, add `"^up$"` to `identifier_name.excluded` in `.swiftlint.yml` in a change of its own, then rename
   two cases.
2. **An unknown id on a day that is not in normal form returns the normal form, not the day as it came**
   (decision 6). The tester should take "unchanged" as: unchanged for a day in normal form. *Recommendation:*
   keep. For S3's "a change that returns the program unchanged writes no row", the only effect is that the
   first edit of a stored day whose first slot is joined rewrites that one slot's row once.
3. **`ProgressionRules.prescribe` can trap or run for a very long time on input outside the model, and
   `prescriptions` is that function mapped.** `weekIndex - 1` overflows at `Int.min`
   (`LedgerDomain/Rules/ProgressionRules.swift:58`); `repsHi - reps + 1` overflows for a slot set to the ends
   of `Int` (`:37`); a week index near `Int.max` counts that many weeks (`:28`). No program or slot the
   model accepts reaches any of them, and the code is F02's, not this slice's. *Recommendation:* leave
   `prescribe` as it is unless the tester's brief asks for totality of `prescriptions` over any `[Week]`;
   then harden those three lines in a change of its own, with F02's tests as the guard.
4. **`newSlot` throws for an exercise whose start load is below zero**, as the signature says. Only a custom
   exercise can hold one. *Recommendation:* F12's form refuses a negative start load; S14's store builds the
   picked slots before it queues the edit, and leaves out and logs an exercise that throws.
5. **`ExerciseSearch.filter(…).isEmpty` tripped SwiftLint's `contains_over_filter_is_empty`**
   (`.swiftlint.yml:33`), which matches the name `filter`. *Settled in fix round 1 (S1 criterion 16):* the
   function is `ExerciseSearch.filtered(_:query:muscle:equipment:)`, and `filtered(…).isEmpty` passes the lint.
6. **A name can be invisible.** `cleanedName` removes category `Cc` and trims white space, as specified; a
   name of only a combining mark, a byte-order mark or a joiner is kept. *Recommendation:* accept for M1; a
   rule "a name has a visible character" is a product decision.
7. **Pete's decision 2** (a superset moves as one). Unchanged: the rule is `DayEditing.move`, 28 lines in its
   own file, with `DayEditingMoveTests` and one property. The other rule replaces those and nothing else.

### Inputs for S3 and for the presentations

What a store sends, and how:

- A block edit is one call: `{ ProgramEditing.toggleDeload($0, week: 2) }`. A day edit is one call inside
  `updateDay`: `{ ProgramEditing.updateDay($0, day: id) { DayEditing.setDropSet(true, slot: slot, in: $0) } }`.
  Days and slots are named by id, and a stepper's value is absolute (`stepped` once, then `set`). Four
  functions are relative, and every `week:` is a place in the block, not a `WeekID`: `toggleDeload` flips,
  `cycleSchedule` goes to the next value, `move` carries a slot one place, `removeLastWeek` names "the last".
  Applied once to the program on screen and once to the stored program inside `ProgramRepository.update`,
  they agree. Applied twice to the stored program they do not: a deload toggled twice is off, a cell cycled
  twice skips a day. So S13 must let each queued edit reach the stored program exactly once: after an
  `update` that failed or was cancelled, the waiting edits are dropped and the screen is redrawn from the
  stored program; they are never sent again (corrected in fix round 1, review S-3). The other functions give
  the same result applied twice.
- **Misses of a removed week.** No edit writes misses (S1 criterion 12), so `removeLastWeek` leaves the
  removed week's index in a slot's misses, and a workout finished late may write one for a week the block
  no longer has. "Nothing reads them" (the table of "A live workout, and a finished one", this file's line
  347) holds only until "+" adds a week at that index again: then that week counts as missed and the week
  after it shows " · HELD".
- **A stepper** works out the new value once, from the slot on screen:
  `let field = DayEditing.stepped(.rest, .upward, of: slot, exercise: exercise, units: settings.units)`, and
  queues `DayEditing.set(field, slot: slot.id, in: $0)`. It does not call `stepped` again inside the save.
- **New ids** (`addWeek`, `addDay`, `newSlot`) are drawn once from `@Dependency(\.uuid)` when the lifter
  taps, and captured by the queued edit.
- **`newSlot` is called before the edit is queued**, once per picked exercise, with `settings.units` and
  `settings.defaultRest`; the edit is `DayEditing.addSlots($0, slots)`. It throws only for a start load below
  zero (open question 4).
- **`removeLastWeek`** is tried on the program on screen first, to choose between the edit and one of the
  two messages; `loggedWeeks` comes from the store ("How a week is known to have logged sessions").
  `.weekHasLoggedSessions(weekNumber:)` carries the number the message prints.
- **Names**: the store passes the text as typed to `renameProgram` and `renameDay`. A blank text changes
  nothing; the field may show what was typed while the stored name stays. `addDay` takes the catalog's
  "New day".
- **Superset actions** (spec §3.4 e). "Break out", offered on a slot that is not the first of its group, is
  `setSuperset(false, slot: thatSlot)`. "Superset with next", offered on the last of its group when it is not
  the day's last slot, is `setSuperset(true, slot: theNextSlot)`: the id passed is the next slot's.
- **Groups and letters**: `DayEditing.groups(of:)` gives the ids in their groups, in order; a member's letter
  is `SupersetRounds.letter(forMemberAt:)`. A presentation never reads `isSupersetWithPrevious` itself.
- **The strip of weekly loads**: `ProgressionRules.prescriptions(for: slot, weeks: program.weeks, exercise:,
  units:)`, one prescription per week, each with `isDeload` and `isHeld`.
- **The library**: `ExerciseSearch.filtered(exercises, query:, muscle:, equipment:)` with `nil` for "All";
  `ExerciseSearch.MuscleFilter.allCases` is the chips' order. The result is in name order.
- **The limits**, should a view need them for VoiceOver: `Slot.setsRange`, `repsRange`, `repsHiRange`.

What a store or a presentation must not do:

- Clamp, round or couple anything: no `min(`, no `max(`, no assignment to `repsHi`, no arithmetic on a
  load, a rest or an RPE. `set` and `stepped` are the only path (the DoD's line, brief:97).
- Assign a slot's field, build an edited slot through `Slot.init`, or reorder, insert or remove in
  `day.slots` or `program.weeks` itself.
- Write `misses` or `exerciseID` of a slot that exists. No function here does, and S3's argument that a
  builder edit and a workout's save commute rests on it (S1 criterion 12).
- Expect `updateDay` to accept a day with another id, or an edit with an unknown id or a week outside the
  block to fail: each returns its input, so an edit queued for a day or slot that a later stored program no
  longer holds is a no-op, not an error.

## Slice S1 — fix round 1 (G1 implementer, 2026-10-06)

On `feat/F11-s1-program-editing` at `4812a2e`, uncommitted, host only. The rulings are the brief's "Plan
amendments — slice S1 after round 1" (S1 criteria 14 to 17); the items are `review.md`'s. The round was cut
once by a usage limit; every run below was made after it, on the final tree.

### What changed, per item

| Item | Change |
|---|---|
| S1 criterion 14 (S-1) | `DayEditing.setProgression` returns the day as it was when the slot already has that progression: a guard as the first line of its closure (`LedgerDomain/Programs/DayEditing.swift:104-106`). Linear to double still makes the top at least reps + 2. New test `DayEditingTests.setProgression_doubleAgain_keepsANarrowedRange` (double 8–9 and 9–10 stay; linear 8–9 to double gives 10; linear again changes nothing). |
| S1 criterion 15 (S-2) | New `Tests/LedgerDomainTests/Programs/EditingSourceTests.swift`, in the form of `ModuleBoundaryTests`: it reads `Sources/LedgerDomain/Programs/*.swift`. `sources_everyEditIsInThePropertysTables`: every `static func` whose result is `Program` or `DayTemplate` is a row of `EditingTestSupport.dayEdits` or `programEdits`, bar the two helpers named in the suite (`editing`, `normalized`); and every row names a function, bar `set(stepped)`. `sources_onlyNewSlotNamesWhatAWorkoutOwns`: no code line outside `newSlot` names `misses` or `exerciseID`, or holds `Slot(` or `Slot.init(`. The check is by name, so a line that only reads them fails too; that is said in the suite's comment. Two tests of the scanner on a sample (`scanner_findsFunctionsByTheirResult`, `scanner_flagsWhatOnlyNewSlotMayName`). The second caught a real hole while it was written: Swift's `Regex` reads `\b` by Unicode's word rules, under which "slot.misses" is one word; the scanner uses simple boundaries. Shown to fail on the real sources: with a function `sneaky(_:) -> DayTemplate` that cleared a slot's misses planted in `DayEditing.swift`, and the guard of criterion 14 removed, both source tests and the new progression test failed; the file was restored from a copy. |
| S1 criterion 16 (N-1) | `ExerciseSearch.filter` is `ExerciseSearch.filtered` (`LedgerDomain/Rules/ExerciseSearch.swift:74`). My four call sites and three test names in `Rules/ExerciseSearchTests.swift` follow (`filtered_…`). My S1 section above says `filtered`; the planner's sections are left as written. |
| S-3 | No code change. In "Inputs for S3 and for the presentations" above, the sentence "never a position or a difference" is replaced: it names the four relative functions and what that requires of S13. A bullet beside it carries the reviewer's sentence on misses of a removed week. The planner's table at line 347 is not mine and is unchanged; the bullet points at it. |
| N-2 | `set`'s comment: an RPE or a rest off its step goes to the nearest step; a start load is stored as given. |
| N-3 | `cleanedName`'s comment names U+0000, the tab, LF, CR and NEL, and says U+2028 and U+2029 are trimmed at the ends and kept inside. The characters removed are unchanged. |
| N-4 | Each limit is written once. `RPE.range` (5…10), read by `RPE(_:)`, `RPE(clamping:)` and `deloaded()`; the last held the lower limit a third time as ten half points, which the review did not list, and is now `RPE(clamping: value - 2)`, so the private `init(halfPoints:)` it alone used is gone. `RestDuration.secondsRange` (30…300) and the existing `stepSeconds`, read by both initializers. `Program.minimumWeeks`, read by `Program.init`'s check and by `removeLastWeek`. All three are internal. No behaviour changed: the existing tests of `RPE`, `RestDuration` and `Program` pass untouched. |
| N-5 | `prescriptions`' comment says the weeks are a program's and the slot one `Slot.init` accepts, as for `prescribe`. |
| N-6 | A seeded test records at most a line or two for a seed. The two tests of criterion 12 compute the slots rewritten by a step (`DayEditingPropertyTests.rewritten(from:to:)`, fixture numbers only) and stop at the first with `try #require`; "since the start" is checked once, after the thirty edits. The same in the other step loops (`randomEdits_keepTheNormalForm`, `randomEdits_keepTheProgramValid`, `cycleSchedule_daysPlusOneTimes_returnsToTheStart`); `unknownIDsAndWeeks_changeNothing` and the move property's first check collect and expect once. |
| N-7 | `clampingInitializers_roundToTheStepAndStayInRange` is `rpeClampingInitializer_roundsToTheHalfAndStaysInRange`. `everyDayEdit_onEverySlot_leavesMissesAndExercise` is `everyDayEdit_onDrawnSlots_leavesMissesAndExercise`, with a display name and a comment that say the slots are drawn. The support type is `EditingTestSupport`, as its three files are named; the three block suites take the `Support` alias the day suites already had. |
| N-8 | Not this slice (S7). |
| N-9 | `addSlots`' comment says an appended slot keeps its own superset flag. `ProgramEditing`'s header says `updateDay` stores the day its closure returns, so only `DayEditing`'s functions go in it. |

Not changed, as ruled: the direction cases, invisible names, `prescriptions`' preconditions.

### Sanctioned edits to the tester's files

The word `filter` became `filtered` at each call of `ExerciseSearch.filter(`; each file was compared with
`HEAD` and differs by that word alone.

- `Tests/LedgerDomainTests/Adversarial/Programs/ExerciseFilterAdversarialTests.swift`: lines 80, 106, 123,
  142, 151, 154, 157, 159, 165, 166, 172, 187, 190, 192. The suite's display name on line 8,
  "ExerciseSearch.filter (adversarial)", is a string and was left.
- `Tests/LedgerDomainTests/Adversarial/Programs/EditingPublicSurfaceAdversarialTests.swift`: line 95.

### Tester's pins that now fail, for the tester to update

Both pin the behaviour criterion 14 replaced. Neither was touched.

1. `DayEditingFieldsAdversarialTests.setProgression_fromEveryPair_keepsOrRaisesTheTop`
   (`Adversarial/Programs/DayEditingFieldsAdversarialTests.swift:80`, the expected value at `:87`). Old: for
   every starting progression, a target of double expects the top `max(top, reps + 2)`. New: when the slot
   is already double, the top stays as it is; from linear or fixed, as before. 30 of its 6,615 cases fail:
   double to double with the top at reps + 1.
2. `DayEditingModelAdversarialTests.editSequence_matchesTheModelAtEveryStep(seed:)`
   (`Adversarial/Programs/DayEditingModelAdversarialTests.swift:50`), through its reference
   `DayModel.setProgression` (`Adversarial/Programs/DayModelAdversarialSupport.swift:223-232`). Old: double
   always makes the top `max(top, reps + 2)`. New: a row that already has the progression is left as it is.
   11 of the 200 seeds fail: 134640, 308858, 506833, 760241, 807755, 863188, 918621, 1116596, 1465032,
   1472951, 1575898 (first: seed 134640, step 73, top expected 29, found 28).

### Product lines now

Non-blank, non-comment lines added outside tests, against `fee3c70`: **377** (367 after the first round).
`DayEditing.swift` 100 (+3, the guard), `Model/Program.swift` +2 (new to the slice), `Units/RPE.swift` +7
(was +4; one initializer of three lines removed), `Units/RestDuration.swift` +7 (was +5); the others as
before: `ProgramEditing.swift` 71, `ProgramEditing+Days.swift` 56, `DayEditing+Fields.swift` 60,
`DayEditing+Move.swift` 28, `Errors.swift` +4, `Slot.swift` +6, `ProgressionRules.swift` +8,
`ExerciseSearch.swift` +28.

### Runs

From the worktree root, on the host, on the final code tree, after the cut.

| Command | Result |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter LedgerDomainTests` | exit 1, as expected. 1,098 tests in 169 suites (1,093 in 168 before the round: one progression test and the four of `EditingSourceTests`). 1,096 pass; **2 fail, with 12 issues, both tester's pins listed above** and no other: `setProgression_fromEveryPair_keepsOrRaisesTheTop` (1 issue) and `editSequence_matchesTheModelAtEveryStep(seed:)` (11 seeds). No compiler warning. |
| the same with `--enable-code-coverage` | exit 1, the same two tests. Because the run failed, SwiftPM merged no profile; the run's 63 raw profiles were merged by hand with `xcrun llvm-profdata merge -sparse`. |
| `scripts/check.sh --lint-only` | exit 0. |

Coverage, `xcrun llvm-cov report` on that profile: lines, regions and functions all without a miss in the
five new files (`ProgramEditing.swift` 84 lines, `ProgramEditing+Days.swift` 60, `DayEditing.swift` 101,
`DayEditing+Fields.swift` 51, `DayEditing+Move.swift` 40) and in the whole of the six edited ones
(`Slot.swift` 66, `Program.swift` 50, `RPE.swift` 38, `RestDuration.swift` 46, `ProgressionRules.swift` 42,
`ExerciseSearch.swift` 53).

Not run: the seeded suites at 2,000 seeds this round; `scripts/check.sh` in full; the simulators; CI.
`EditingSourceTests` reads source files by `#filePath`, as `ModuleBoundaryTests` does; it was run on the
host only.
## Slice S3 — the atomic program update (G1 implementer, 2026-10-06)

`ProgramRepository.update(_:_:)`: one requirement, no default body, on the database and on the in-memory
stores, with the contract clauses, seeded interleavings and cancellation tests that prove it. Not committed;
no pull request. Paths below are under `LedgerKit/` unless they start with `tasks/` or `scripts/`.

### What landed (files)

Product (38 lines added, 3 removed; "Code lines per file" below):
- `Sources/LedgerDomain/Protocols/Repositories.swift:33-57` — the requirement, its rules, and what a caller
  must not do in `change`.
- `Sources/LedgerPersistence/Repositories/GRDBProgramRepository.swift:51-84` — `update`: the read, the change
  and the write in one `queue.write`. `:138-145` — `write(_:isActive:in:at:)`, the one path `save` (`:43-49`)
  and `update` write through.
- `Sources/LedgerFakes/InMemoryProgramRepository.swift:57-79` — `update` in one `state.write`, the lock
  `writeSave` takes (`:105-116`).
- `Sources/LedgerDependencies/Unimplemented/UnimplementedStores.swift:46-48` — the stub's `update`.
- `Sources/LedgerDomain/Protocols/RepositoryError.swift:27-34`, `:38-40` — comments only: the two cases name
  `update`.

Test support (`Sources/LedgerTestSupport/`, not counted):
- `Engine/StoreProbe.swift:11-16` — the call `.updateProgram`. `Engine/ProbedStores.swift:120-139` — `update`
  goes through the probe.
- `Persistence/ProgramRepositoryContract+Update.swift`, `+UpdateEffects.swift` (new) — eight clauses, added at
  the end of `ProgramRepositoryContract.clauses` (`ProgramRepositoryContract.swift:28`).
  `Persistence/ProgramRepositoryContract+Storage.swift:12-15`, `:57-81` — one storage clause.
- `Persistence/WorkoutRepositoryContract+LinkedUpdate.swift` (new) — two linked clauses, added at the end of
  `linkedClauses` (`WorkoutRepositoryContract+Linked.swift:42`).
- `Persistence/TaskCancelSwitch.swift` (new) — a task that what it runs can cancel.

Tests (`Tests/LedgerPersistenceTests/` unless said):
- `ProgramUpdateInterleavingTests.swift`, `+Script.swift`, `+Edits.swift` (new) — the losing sequence, the
  seeded scripts on both stores against a model, the concurrent test.
- `ProgramUpdateTests.swift` (new) — the GRDB repository's rows, statements and emissions.
- `ProgramUpdateCancellationTests.swift` (new) — what a cancelled write does.
- `ProbedProgramRepositoryTests.swift` (new) — the probe holds, counts and fails an update, on both stores.
- `Tests/LedgerDependenciesTests/UnimplementedStubTests.swift:50` — the stub's `update` in the list of calls.
- The four test doubles: "The sanctioned edits" below.

No migration, no schema change, no fixture, no feature code, nothing of S1.

### The losing sequence, before `update` existed (Risks 1)

Run on the tree before any product change, with the builder's edit written through `save` and the test
expecting what a lifter expects (`swift test … --filter ProgramUpdateInterleavingTests`, exit 1, 4 issues, 2
cases):

```
stores → inMemory: Expectation failed: stored.misses == [2]            (stored.misses → [])
stores → inMemory: Expectation failed: stored.exerciseID == replacement (…0CA00000, expected …0CA00001)
stores → database: Expectation failed: stored.misses == [2]            (stored.misses → [])
stores → database: Expectation failed: stored.exerciseID == replacement (…0CA00000, expected …0CA00001)
```

Both stores lose the miss and the swap alike. The sequence is kept twice in the suite:
`wholeSave_afterAWorkoutsSave_losesItsMissAndItsSwap` asserts the loss (why `update` exists), and
`update_afterAWorkoutsSave_keepsItsMissAndItsSwap` sends the same edit through `update` and keeps both.

### Decisions and deviations

1. **A result under another id throws `duplicateIdentifier("program <the result's id>")`**, checked before any
   other check, on both stores (`GRDBProgramRepository.swift:78-80`, `InMemoryProgramRepository.swift:73-75`).
   The specification says "refused" and names no error, and `save` has none of its own for it: saved whole,
   such a result is another program, or is refused for the week ids it shares. No case was added to
   `RepositoryError`, a Domain enum outside this slice's files. Alternative: a case of its own (open
   question 1).
2. **`isActive` is saved as `save` saves it.** Criterion 6 says "which program is active does not change".
   The plan asks for `save`'s activation to be copied (this file, "Inputs the implementer needs › S3": "the
   transaction and the activation to copy"), and a store cannot keep both when a change sets the flag. Built:
   `update` is `save` of the changed program, activation included (`GRDBProgramRepository.swift:81`,
   `:140-145`). So an update whose change leaves the flag alone never changes which program is active and
   writes no other program's row (`ProgramUpdateTests.update_leavesOtherProgramsAndTheActiveFlag`; clause
   `updateKeepsActivity`), which is every builder edit: no editing function touches `isActive`. A change that
   does set or clear it is stored as `save` stores it (same clause). Alternatives: ignore a changed flag
   (silent), or refuse it (no error fits). Open question 2.
3. **The in-memory `update` checks its task first** (`InMemoryProgramRepository.swift:67`,
   `try Task.checkCancellation()`): one product line the specification does not name. Criterion 9 says the
   in-memory stores follow, the cancellation tests show the database throws `CancellationError` and stores
   nothing when cancelled before it starts or while it waits, and S13's store test runs on the in-memory
   stores behind the probe. With the line, a held update whose task is cancelled stores nothing on both
   (`ProbedProgramRepositoryTests.heldUpdate_cancelled_storesNothing`). The in-memory `save`, `setActive`,
   `delete` and `materialize` do not check their task, as before (open question 3).
4. **`update` returns the program read back**, in the same transaction or under the same lock
   (`GRDBProgramRepository.swift:82`, `InMemoryProgramRepository.swift:77`), not the change's result:
   `Program.init` sorts the weeks (`Sources/LedgerDomain/Model/Program.swift:34`), so a result can differ from
   what is stored. Clause `updateApplies` pins it with a change that reverses the weeks. The `?? changed` on
   those two lines cannot be reached (the row was just written); it stands where a force unwrap would.
5. **No special case for an unchanged result.** It goes through `save`'s row diff, which writes nothing
   (`Sources/LedgerPersistence/Records/SyncedRecord.swift:72-74`); the activation statement touches only rows
   whose flag changes (`GRDBProgramRepository.swift:148-155`); the in-memory streams yield only a value that
   differs (`Sources/LedgerFakes/Support/ObservedState.swift:53`). Pinned by
   `ProgramUpdateTests.updateThatChangesNothing_writesNoRow` and `observation_emitsOncePerUpdateThatChanges`.
6. **`save` and `update` share `write(_:isActive:in:at:)`** (`GRDBProgramRepository.swift:138-145`): `save`'s
   three lines moved into it (`:47`). `save` behaves as before: it still validates before it asks for the
   writer (`:44`), and every existing suite passes untouched.
7. **A program whose rows cannot be read cannot be updated.** `update` throws what the read throws and never
   calls `change`; a whole `save` repairs the row, as before. The specification does not name the case; it
   follows from "applies `change` to the program as stored".
   `ProgramUpdateTests.update_ofAProgramThatCannotBeRead_throwsWhatReadingThrows`.
8. **Seeded interleavings are scripts of awaited calls; concurrency has a test of its own.** Criterion 7 says
   "in the order they were taken". A workout's save gives a test no way to learn when the store took it, so
   in the seeded scripts each call is awaited before the next and the order is the script's; both stores are
   held to a model after every call. `concurrentUpdatesAndSaves_loseNothing` then makes 200 updates and 8
   saves at once, where the order the store took the updates in is recorded from inside each change.
9. **Files beyond the plan's list** (this file, "Files S3 creates or changes"): `StoreProbe.swift` (the probe
   holds and counts by call, so `update` needs one); `RepositoryError.swift` (comments); the storage clause in
   `ProgramRepositoryContract+Storage.swift`, where the two storage refusals live; the clause files split in
   two, and the linked clauses in a file of their own, for lint's 300-line limit
   (`WorkoutRepositoryContract+Linked.swift` is at 297); `TaskCancelSwitch.swift`; three more test files and
   two extension files beside `ProgramUpdateInterleavingTests.swift`; one line of
   `UnimplementedStubTests.swift` (criterion 9's stub).
10. **What the observation clause cannot show.** A repository's stream keeps its newest value only, so clause
    `updateObserved` shows that no update that changed nothing is ever seen as a change, not that nothing
    was emitted. For the database `observation_emitsOncePerUpdateThatChanges` counts every emission on a
    stream that drops none. For the in-memory store it holds by construction (`ObservedState.swift:53`).

### Criteria → tests

"Both" means the clause runs on the GRDB repository (`ProgramRepositoryTests`, `WorkoutRepositoryTests`) and
on the in-memory stores (`InMemoryContractTests`), each on a fresh store. Suites are in
`Tests/LedgerPersistenceTests/`.

| Criterion | Tests |
|---|---|
| 1 The requirement | Every conformer compiles (`swift build … --build-tests`, exit 0). Clause `updateApplies` (both): the change meets the program as stored now, also after another update and after a whole save, and the answer is the program as stored. `ProgramUpdateTests.update_isOneTransaction_withItsChangeBetweenTheReadAndTheWrite`: one `BEGIN`, the read, the change, the rows, one `COMMIT`. `concurrentUpdatesAndSaves_loseNothing` (both stores). |
| 2 Nothing to update | Clause `updateMissing` (both): unknown and deleted, `missingRow`, the change called 0 times, nothing left behind. The seeded scripts hold more than ten calls on a deleted program. |
| 3 A change that throws | Clause `updateRethrows` (both). `ProgramUpdateTests.refusedUpdate_leavesEveryRow` (every row of the five tables as it was). No observer: clause `updateObserved` (both), `observation_emitsOncePerUpdateThatChanges`. |
| 4 A result `save` would refuse | Clause `updateRefuses` (both): six results, each refused by `save` and by `update` with the very same error (a slot out of range, one week, a name holding U+0000, a slot twice, a slot and a day another program holds), then a result under a stored program's id and under an id no program holds. Storage clause `updateRefusesAtTheBoundary` (both): an inexact step, an unknown exercise. `refusedUpdate_leavesEveryRow`: a result refused after most of its rows were written. |
| 5 An unchanged result | `ProgramUpdateTests.updateThatChangesNothing_writesNoRow` (the stored program returned as it is, and with its weeks reordered: no row written). `observation_emitsOncePerUpdateThatChanges`. Clause `updateObserved` (both). |
| 6 Rows | `update_writesOnlyTheRowsThatChanged`: the counts `save` gives for the same edit, changed rows stamped, removed rows soft-deleted. `update_leavesOtherProgramsAndTheActiveFlag`: one row written, no flag changed. Clause `updateKeepsActivity` (both). Linked clause `updateLeavesHistory` (both): a slot, then a day, a stored workout came from is removed; the workout reads as before and can be stored again. |
| 7 Nothing lost | `wholeSave_afterAWorkoutsSave_losesItsMissAndItsSwap` and `update_afterAWorkoutsSave_keepsItsMissAndItsSwap`, each on both stores. Linked clause `updateAndSaveInEitherOrder` (both). `interleavedCalls_matchTheCallsAppliedInOrder`: 30 fixed seeds on the host and in the PR lane, every seed of the lane nightly; 25 calls a script; a failure names its seed and the call. `scripts_holdEveryKindOfCall` vouches for the 30. `concurrentUpdatesAndSaves_loseNothing` (both stores). |
| 8 Cancellation | `ProgramUpdateCancellationTests` (six tests, next section). Clauses `updateCancelledBefore` and `updateCancelledInside` (both). `ProbedProgramRepositoryTests.heldUpdate_cancelled_storesNothing` (both stores). |
| 9 The in-memory stores follow | `InMemoryContractTests` runs the eight clauses, the storage clause and the two linked clauses. The stub: `UnimplementedStubTests.programRepository`. The probe: `ProbedProgramRepositoryTests`, four tests on both stores. |
| 10 Every other conformer | The build; "The sanctioned edits" below. |
| 11 No migration, no schema | `git status --short` shows no migration, fixture or lock file. The existing clauses are untouched: both lists gain entries at their end. `MigrationCompatibilityTests`, `SchemaTests` and every existing suite pass in the runs below. |

What the tests catch, tried by breaking the code and restoring it (each a filtered host run, exit 1):

| Broken on purpose | Caught by |
|---|---|
| GRDB `update` as three steps: read, change, `save` (the default body that was rejected) | `update_isOneTransaction…`, four of the six cancellation tests, and `concurrentUpdatesAndSaves_loseNothing` on the database (updates lost) |
| The in-memory `update` reading under the lock, changing outside it, saving under it again, with no check of its task | Clause `updateCancelledBefore` and `heldUpdate_cancelled_storesNothing`, every run. `concurrentUpdatesAndSaves_loseNothing`: 8 runs of 8 |
| GRDB returning the change's result, not what is stored | Clause `updateApplies`; `updateThatChangesNothing_writesNoRow` |
| GRDB without the id check | Clause `updateRefuses`; the seeded scripts (13 seeds) |
| The in-memory store applying the change to a copy that forgot one slot's misses | `update_afterAWorkoutsSave_keepsItsMissAndItsSwap`, linked clause `updateAndSaveInEitherOrder`, the concurrent test, the seeded scripts |

*Corrected in fix round 1 (review, "Atomicity in memory"): the in-memory store is atomic by construction, as
the database is; what follows is only how a test would notice if `change` were later moved outside the lock.*
No test shows by construction that the in-memory store runs `change` under its lock; the concurrent test
would notice by overlap. With 24 short updates it caught the broken store in 1 run of 3, with
200 in 2 of 6; with some work inside each change (the test encodes the program) in 8 of 8, on this Mac. On
one core it would pass over a broken store. The lock itself is one `state.write`
(`InMemoryProgramRepository.swift:68`).

### What was established about cancellation (criterion 8; ruling 5)

By `Tests/LedgerPersistenceTests/ProgramUpdateCancellationTests.swift`, six tests on the GRDB repository,
none of which waits on a clock: the task is cancelled from inside the write (by the change, by a statement
trace, by a transaction observer), or while another access holds the writer.

| The task is cancelled | What `GRDBProgramRepository.update` does | Test |
|---|---|---|
| before the call | `CancellationError`; `change` is never called; no row written | `cancelledBeforeItStarts_storesNothing` |
| while the write waits for the writer | the same | `cancelledWhileItWaitsForTheWriter_storesNothing` |
| inside `change` (after the read, before any row) | `CancellationError`; rolled back | `cancelledInsideItsChange_storesNothing` |
| as any statement before the commit starts, rows written or not | `CancellationError`; rolled back; GRDB starts at most the statement it was in and the rollback | `cancelledAtAnyStatementBeforeTheCommit_storesNothing` |
| as the commit itself starts | the commit fails and is rolled back: `CancellationError`, nothing stored | `cancelledAsTheCommitStarts_storesNothing` |
| once the commit has succeeded, before the call returns | too late: the change is stored whole and the call returns it | `cancelledOnceCommitted_storesEverything` |

So: **a cancelled `update` stores all of its change or none of it, and it throws `CancellationError` only when
it stored none.** A caller that keeps what a cancelled call could not store, and sends it again, never sends
a change twice.

Why, in GRDB 7.11.1 (`LedgerKit/.build/checkouts/GRDB.swift`): an async access checks its task as it starts
(`GRDB/Core/SerializedDatabase.swift:256-266`, `try Task.checkCancellation()` before the caller's block), which
covers "before" and "while it waits" alike; a cancellation during the access marks the connection and
interrupts SQLite (`GRDB/Core/Database.swift:1245-1268`), after which every statement but a rollback throws
`CancellationError` before it runs (`:1391-1393`, `:1428`), the commit included, and `inTransaction` rolls back
(`:1545-1553`). Nothing checks the task after the block returns, so a commit that succeeded is reported as
a success.

Two things I expected and the tests corrected:
- I expected a cancellation that arrives as the commit starts to come too late (the statement trace fires
  inside `sqlite3_step`). It does not: on the host's SQLite 3.54.0 the interrupt reaches the commit, which
  fails, and GRDB rolls back. That row of the table is SQLite's doing, not GRDB's; the test says so, and should
  a later SQLite finish that commit, it alone fails and the rule above still holds.
- "While it waits": the test cancels once `update` has read its clock and before the held writer is freed.
  Whether the cancellation lands just before or just after GRDB queued the access cannot be told from
  outside; both go through the one check at `SerializedDatabase.swift:264`.

The in-memory store (decision 3): an already cancelled task throws `CancellationError` before anything is
read, as the database does before it starts and while it waits; nothing in it suspends, so a task cancelled
later (from inside `change`) stores its change whole and returns. Two contract clauses hold both stores to
what they share: `updateCancelledBefore` (cancelled before the call: `CancellationError`, no call of `change`,
nothing written) and `updateCancelledInside` (all or none, and `CancellationError` only for none).

### The sanctioned edits to other conformers (criterion 10)

Each is the new method only, in the double's own style; `git diff --numstat` gives the sizes.

| File | Double | Diff | What it does |
|---|---|---|---|
| `Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:92-101` | `HistoryModel`, F05's oracle (a tester's file) | +11 −0 | Under its lock, as its `save` and `setActive`: applies the change to its stored program, or throws `missingRow`. Nothing calls it. |
| `Tests/LedgerSyncTests/Adversarial/HostSiegeStoresAdversarialSupport.swift:134-136` | `SiegeProgramRepository`, F10's siege (a tester's file) | +4 −0 | Passes the call to its base, past the gate, as its `save`. |
| `Tests/LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift:34-36` | `BriefProgramRepository`, F02's shape check (a tester's file) | +4 −0 | Throws `missingRow`: it stores no program (`active()` is `nil`). |
| `Tests/LedgerSyncTests/LocalWorkoutSessionActorMissTests.swift:150-152` | `AnotherProgramWithTheSameSlots` | +4 −0 | Throws `Unused()`, as its other writes. |

Three of the four are under `Adversarial/`, not two as Risks 2 counts them. No test, assertion or other line
of those files changed.

### Code lines per file

Non-blank, non-comment lines outside tests and `LedgerTestSupport`, counted from `git diff -U0`:

| File | Added | Removed |
|---|---|---|
| `Sources/LedgerDomain/Protocols/Repositories.swift` | 1 | 0 |
| `Sources/LedgerPersistence/Repositories/GRDBProgramRepository.swift` | 20 | 3 |
| `Sources/LedgerFakes/InMemoryProgramRepository.swift` | 14 | 0 |
| `Sources/LedgerDependencies/Unimplemented/UnimplementedStores.swift` | 3 | 0 |
| `Sources/LedgerDomain/Protocols/RepositoryError.swift` | 0 | 0 (comments) |
| **Total** | **38** | **3** |

Planned: about 45.

### The runs

All on the final tree, from the worktree root, on 2026-10-06, and all run again after the session's last
interruption, with the same counts.

| Run | Command | Result |
|---|---|---|
| Host build, every conformer | `swift build --package-path LedgerKit --only-use-versions-from-resolved-file --build-tests` | exit 0; no new warning |
| Host, `LedgerPersistenceTests` | `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter '^LedgerPersistenceTests\.'` | exit 0; 517 tests in 117 suites passed; 1 known issue (the F7-10 seed test's own `withKnownIssue`) |
| Host, `LedgerSyncTests` | the same with `'^LedgerSyncTests\.'` | exit 0; 276 tests in 48 suites passed; 13 known issues (the fake session client's own) |
| Host, `LedgerDomainTests` | the same with `'^LedgerDomainTests\.'` | exit 0; 838 tests in 138 suites passed |
| Host, `LedgerDependenciesTests` (the stub) | the same with `'^LedgerDependenciesTests\.'` | exit 0; 63 tests in 11 suites passed; 17 known issues (its own) |
| Lint tier | `scripts/check.sh --lint-only` | exit 0 ("check.sh (--lint-only) OK") |
| iOS simulator, through the lock (run twice: the session was interrupted after the first, and the second, on the final tree, gave the same counts) | `/usr/bin/python3 …/scratchpad/sim-lock.py /bin/bash …/scratchpad/f11s3/sim-run.sh`: `scripts/sim-destination.sh`, `scripts/sim-boot.sh`, then `xcodebuild build-for-testing` and `xcodebuild test-without-building -project Ledger.xcodeproj -scheme Ledger -testPlan PR -destination 'platform=iOS Simulator,id=…'` (iPhone 17, iOS 27.0) `-derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages -onlyUsePackageVersionsFromResolvedFile -only-testing:LedgerPersistenceTests -only-testing:LedgerSyncTests -collect-test-diagnostics never -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -quiet` | exit 0. The result bundle, read with `xcresulttool`: Passed; 796 tests, 782 passed, 0 failed, 11 skipped, 3 expected failures; both bundles Passed; the four new suites ran, the commit test among them. Bundles deleted |

The fakes' contract tests are `InMemoryContractTests`, in `LedgerPersistenceTests`: on the host and on the
simulator the program contract ran 18 clauses on each kind of store (10 existing, 8 new), the storage
contract 3 (2 and 1), the linked contract 9 (7 and 2).

Not run by me: the full gate, the watchOS plan, CI, the nightly lane (every seed of the lane; the host and
the PR lane run the 30 fixed scripts), any UI test. `git status --short` shows the files listed under "What
landed" and nothing else.

### Open questions, each with a recommendation

1. **The error for a result under another id.** Built: `duplicateIdentifier("program <id>")`. A case of its
   own would say it better and costs a line of a Domain enum and its doc. *Recommendation:* keep. The builder
   cannot produce it (`Program.id` is a `let` and no editing function builds a program under another id); it
   is a programmer's error, named in the protocol's doc and pinned by a clause.
2. **`isActive` in a change** (decision 2). *Recommendation:* keep "as `save` saves it". If Pete wants
   `update` never to change which program is active, it needs either an error case or a silently ignored
   flag; `setActive` already exists for the purpose.
3. **The in-memory stores' other writes do not check their task.** GRDB's `save`, `setActive`, `delete` and
   `materialize` throw `CancellationError` when cancelled before they start; LedgerFakes' run to the end.
   *Recommendation:* leave it until a store test needs it; then it is one line a method and one clause a
   contract, as here. Not F11's.
4. **The commit row of the cancellation table is SQLite's behaviour.** The test is strict about it on
   purpose. I ran it on the host and on the iOS simulator; watchOS is the orchestrator's gate. *Recommendation:*
   keep it strict; if it ever fails on a runtime, read `cancelledAsTheCommitStarts_storesNothing`'s comment
   before changing anything: the rule S13 relies on is the other five tests'.
5. *(Closed in fix round 1: the code is atomic by construction; this is about the test only.)* **The
   concurrent test finds a non-atomic in-memory store by overlap, not by construction** ("Criteria →
   tests", the limit). A check by construction needs a hook into `ObservedState`'s lock, which is product
   code of LedgerFakes. *Recommendation:* accept.
6. **The older program clauses print whole programs when they fail** (`ContractCheck.expect`,
   `Sources/LedgerTestSupport/Persistence/ContractClause.swift:23-25`, used with programs throughout
   `ProgramRepositoryContract.swift`). The new clauses use `same(_:_:_:)`, which prints a line. Left alone:
   criterion 11 says the existing clauses are untouched. *Recommendation:* a follow-up that moves them to
   `same`, since a red run of 8 × 4 × 5 programs is what filled the disk before.
7. **Risks 2 counts two testers' files; three of the four doubles are under `Adversarial/`.** No action
   needed; the audit list above has all four.

### Inputs for S13 and S14

**How a store calls it.**

```swift
@Dependency(\.programRepository) var programs

// `waiting`: the edits not stored yet, as Sendable values; `stored`: the program the screen was built from.
let edits = waiting
let saved = try await programs.update(stored.id) { program in
    try edits.reduce(program) { try $1.applied(to: $0) }
}
```

- The answer is the program as stored after the write, with whatever a workout's save put there meanwhile
  (misses, a swap). Build the screen from it. `observeActive` emits the same program once, for an update that
  changed something; an update that changed nothing emits nothing, so never wait for an emission after one.
- **What the closure may hold.** Sendable values only: the edits, ids, the lifter's units. It is
  `@Sendable` and synchronous, and on the database it runs on GRDB's writer queue, inside the transaction.
  It must not hold the store (`self`, which is `@MainActor`), call a repository, or wait. It is called at
  most once, and not at all for a missing program or a cancelled task. It may throw: `ProgramEditError` from
  `removeLastWeek` comes back as it is, and nothing is stored.
- **Apply the edits to the argument, never to a copy the store holds.** That is the whole point: an edit
  that writes a slot's misses or its exercise from the screen's copy would undo a workout's save. S1's
  criterion 12 keeps the editing functions clear of both.
- **Errors.** `missingRow` (the program was deleted meanwhile); whatever `save` throws for the result
  (`nulInText`, `unknownExercise`, a validation error); `CancellationError`.
- **Cancellation** (the table above). `CancellationError` means nothing was stored: keep the waiting edits
  and send them again. A return means all of it was stored: drop them. There is no third case, which matters
  because edits such as "add a week" are not idempotent.
- **S14.** `DayEditorStore` goes the same way: `update(programID) { ProgramEditing.updateDay($0, …) }`. A day
  that was deleted meanwhile is the editing function's "id the program does not hold": the program comes back
  unchanged, nothing is written, and the store sees that the day is gone from the answer.

**How a test holds a write with the probe** (`ProbedProgramRepositoryTests` is the worked example):

```swift
let memory = InMemoryStores(seed: seed)
let probed = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
// give the store `probed.programs` as its `programRepository`
await probed.probe.hold(.updateProgram)       // the next update parks before it reaches the store
store.send(first)                             // the save loop calls update
try await probed.probe.waitUntilHeld()        // nothing of it is stored yet
store.send(second); store.send(third)
await probed.probe.release()
// … once the store is idle:
#expect(await probed.probe.calls.count { $0 == .updateProgram } == 2)
```

- `hold` holds one call, the next (`Sources/LedgerTestSupport/Engine/StoreProbe.swift:139-140`).
  `ProbedProgramRepository` has no public initialiser; `ProbedStores` builds it.
- `fail(.updateProgram)` throws `StoreProbe.Refusal` before the store (nothing stored); with
  `afterStoring: true` the change is stored and the call still throws (an answer lost).
- A held update whose task is cancelled, then released, throws `CancellationError` and stores nothing, on the
  in-memory stores and on the database.
- To cancel a task from inside the store's write, at an exact point and without a clock: `TaskCancelSwitch`
  (`run(_:)` starts the task, `fire()` cancels it from the change).

### Inputs for the branches that still wait to merge

When `main` with S3 is merged into them, every `ProgramRepository` conformer needs
`func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program`.
Read with `git grep` on the local branches on 2026-10-06: `feat/F08-s3-root-gate` holds seven doubles, at the
places Risks 2 lists; `feat/F08-s2-onboarding-ui` holds the three under `FeatureOnboardingTests`; the F09
branches and `feat/F11-s1-program-editing` hold none.

| The double (on `feat/F08-s3-root-gate`, under `LedgerKit/Tests/`) | What to add |
|---|---|
| Wraps another repository: `ProbedPrograms` (`FeatureOnboardingTests/Adversarial/OnboardingAdversarialStores.swift:11`), `GateProbedPrograms` (`LedgerAppKitTests/Adversarial/AppRootGateAdversarialProbes.swift:19`), `GateRelayedPrograms` (`LedgerAppKitTests/Adversarial/RootGateStoreAdversarialSupport.swift:133`) | `try await base.update(id, change)` (or `inner`), with the double's own journal note or script step around it where its `save` has one. Pass `change` on as it came; never call it outside the wrapped store. |
| Records or scripts, with no store behind it: `RecordingPrograms` and `FailingPrograms` (`FeatureOnboardingTests/Support/StoreDoubles.swift:13`, `:54`), `GateScriptedPrograms` (`LedgerAppKitTests/Adversarial/RootGateAdversarialScript.swift:116`), `ScriptedPrograms` (`LedgerAppKitTests/Support/GateSupport.swift:77`) | What its `save` does with a call nobody makes there: note it and throw, or throw its `error`. Onboarding and the root gate never call `update`. One that holds a program can do as `HistoryModel` does here: under its own lock, the stored program or `missingRow`, then `change`, then store. |

None of them should implement `update` as `active()` and then `save`, awaited apart: that is the sequence this
slice replaces. F08's onboarding saves a new program with `save`, which stays right: `update` is for a
program that is already stored.

## Slice S3 — fix round 1 (G1 implementer, 2026-10-06)

After the tester's round 1 (F11-S3-1) and the review (S1, S2, nine nits), on top of d77550f. Not committed.
Paths are under `LedgerKit/`. Rulings: the brief's criteria 12 to 14.

### What changed

- **Criterion 12** (F11-S3-1, review S1). `Sources/LedgerFakes/InMemoryProgramRepository.swift:69-86`: the
  in-memory `update` checks its task twice, both under the lock: as the write begins (`:71`), which covers a
  task cancelled before the call and one cancelled while it waited for the lock, and `change` is then not
  called; and once `change` has returned (`:76`), before the id check and the store. Either throws
  `CancellationError`, and `ObservedState.write` leaves the state as it was. The check before the lock is
  gone: the first check under it does its work and the waiting case too. The database's "cancelled once
  committed" has no counterpart: nothing follows the store but the return. The doc comment says so (`:57-68`).
- **The clause is strict.** `Sources/LedgerTestSupport/Persistence/ProgramRepositoryContract+UpdateEffects.swift:100-120`:
  `updateCancelledInside` now requires `CancellationError` and the program as saved, on both stores; its name
  in the list reads "update on a task cancelled inside its change throws CancellationError and writes
  nothing". `updateCancelledBefore` was strict already.
- **Criterion 13** (review S2). `Sources/LedgerDomain/Protocols/Repositories.swift:33-35`: `save` says it is for
  a new program or a whole replacement, and that an earlier copy saved there writes back the misses and the
  exercises a workout's save stored since; it points to `update`.
- **Criterion 14** needed no code: it is what was built (clauses `updateKeepsActivity`, `updateRefuses`).
- **The notes.** "Criteria → tests" and open question 5 above said the in-memory store's atomicity is shown
  "by overlap". Corrected in place: it holds by construction (one `state.write`, a `Mutex.withLock` around a
  synchronous body, and `change` is synchronous, so nothing can come between the read, the change and the
  store; a workout's save writes through the same lock). The overlap is only how a test would notice a
  later regression.

Not pinned by a contract clause: "cancelled while it waited for the lock". From outside a store, a test
cannot tell that a call is waiting, on either store, without a hook; for the database it is
`cancelledWhileItWaitsForTheWriter_storesNothing`, and for both stores the held probe
(`ProbedProgramRepositoryTests.heldUpdate_cancelled_storesNothing`) and the tester's
`cancelledWhileWaiting_storesAllOrNothing`. In the in-memory store it is the same line as "before the call"
(`:71`), which the strict clause `updateCancelledBefore` pins.

### The review's nits

| Nit | Done or declined |
|---|---|
| N1 activate only when the flag turns on | **Declined, for F17.** It changes what `update` does when two programs are flagged active, a state no path produces today; `save` does the same through the shared `write`, and the ruling was "nothing that changes behaviour beyond the criteria". Whoever builds the sync that can leave two active should change both. |
| N2 the clock is read before the wait for the writer | **Declined:** the module's convention in every write; flagged for F17, as the review says. |
| N3 the unreachable `?? changed` | **Done.** Both stores throw `missingRow` there (`GRDBProgramRepository.swift:82-85`, `InMemoryProgramRepository.swift:81-84`). |
| N4 "on a thread of the store's own" | **Done:** removed (`Repositories.swift:56`). |
| N5 what the compiler already refuses | **Done:** the doc says `change` is synchronous, so only `observeActive()` compiles there, and that it deadlocks or traps (`Repositories.swift:56-60`). |
| N6 three reads of five tables | **Declined:** no profile asks for it; the review's own remedy is noted for S13. |
| N7 the fixture's shape as numbers | **Done:** `concurrentUpdatesAndSaves_loseNothing` derives them from `program.daysPerWeek` and the slots. |
| N8 helpers written twice | **Declined:** each pair sits on two sides of `LedgerTestSupport`'s public boundary; merging them makes five test helpers public for a few lines saved. |
| N9 `HistoryModel.update` | **No action:** a tester's file; the review accepts the mechanical edit. |

### For the tester: your pins

I expected some of your tests to pin the in-memory store's old answer (stores everything and returns). None
does: every one asserts "all or nothing", which the new behaviour keeps, so **no test of yours fails** and
none was touched. These now accept more than either store does, and could be made strict:

| Test (`Adversarial/ProgramUpdateCancelAdversarialTests.swift`) | In memory, before | In memory, now (as the database) |
|---|---|---|
| `cancelledInsideTheChange_storesAllOrNothing` (both `afterComputing`) | returns, all stored | `CancellationError`, none |
| `cancelledWhileWaiting_storesAllOrNothing` | returns, all stored (none only if the task had not entered the call) | `CancellationError`, none, unless the write finished before the cancellation |
| `cancelledBeforeTheCall_storesAllOrNothing` | `CancellationError`, none | the same |

The counts in F11-S3-1 (in memory: 83 calls with all, 5 with none) will have moved towards none.

### Code lines

This round: `InMemoryProgramRepository.swift` +7 −3, `GRDBProgramRepository.swift` +4 −1, against 57d12ab.
The slice in all: 45 added, 3 removed against 312728c (planned: about 45).

### The runs

On the final tree of this round, from the worktree root:

| Run | Result |
|---|---|
| `swift build --package-path LedgerKit --only-use-versions-from-resolved-file --build-tests` | exit 0 |
| Host `LedgerPersistenceTests` (`swift test … --filter '^LedgerPersistenceTests\.'`), the tester's suites included | exit 0; 549 tests in 125 suites passed; 1 known issue (the F7-10 seed test's own). **Failing tests: none.** |
| The fakes' contract tests, in that run (`InMemoryContractTests`) | program contract 18 clauses, storage 3, linked 9, all passed; the same counts on the GRDB repository |
| Host `LedgerSyncTests` | exit 0; 276 tests in 48 suites passed; 13 known issues (the fake session client's own) |
| `scripts/check.sh --lint-only` | exit 0 |
| iOS simulator (iPhone 17, iOS 27.0), through the lock, `-only-testing:LedgerPersistenceTests`, otherwise the command of the first round | exit 0; bundle Passed: 548 tests, 537 passed, 0 failed, 10 skipped, 1 expected failure; bundle deleted |

Not run: `LedgerDomainTests` and `LedgerDependenciesTests` (nothing of theirs changed but a doc comment in
the Domain), `LedgerSyncTests` on the simulator, the full gate, watchOS, CI, the nightly seeds. No mutation
check was repeated for the two new checks; the strict clause is what holds them.

### Fix round 2 (F11-S3-2, 2026-10-06)

A task cancelled inside a change whose result is refused before any statement threw the refusal on the
database and `CancellationError` in memory. The database's order after `change` is: the id check
(`Sources/LedgerPersistence/Repositories/GRDBProgramRepository.swift:78-80`), `ProgramRows.init`'s
re-validation through `Slot.init` and `Program.init` (`:81`, `Records/ProgramRows.swift:17-32`), and only then
its first statement (`ProgramRows.swift:56`), where GRDB throws `CancellationError`. The in-memory `update` now
does the same: id check, `revalidated`, the cancellation check, then `store`
(`Sources/LedgerFakes/InMemoryProgramRepository.swift:77-85`). Nothing in the database's order is beyond the
fake: every later refusal (another program's ids, an unknown exercise, U+0000, an inexact weight) comes after
a statement, so after the cancellation on both. `store` validates the result a second time; that is one
redundant pass, kept so that `save`'s path is not touched. Product lines: +1 (46 in all).

The tester's `ProgramUpdateCancelAlikeAdversarialTests.cancelledInsideTheChange_everyResult_sameEndingOnBothStores`
passes unedited. Runs: host `LedgerPersistenceTests` exit 0, 552 tests in 126 suites passed (1 known issue, its own);
host `LedgerSyncTests` exit 0, 276 tests in 48 suites passed; `scripts/check.sh --lint-only` exit 0. No
simulator run this round (the orchestrator's gate follows).


## Slice S5 — the builder's presentation (G1 implementer, 2026-10-06)

Branch `feat/F11-s5-builder-presentation`, on the specification commit `7055d80`. Not committed: the
orchestrator commits. This section was started before the code and extended as the work went; a part still
marked *(pending)* was not reached.

### The model and the actions (written first, as the interface)

`ProgramPresentation.make(_ input: ProgramBuilderInput) -> ProgramBuilderModel`, all in `FeatureProgram`,
all `nonisolated`, internal to the module (only `ProgramRoute` is public).

**The input** (`ProgramBuilderInput`): `program: Program`; `exercises: [ExerciseID: Exercise]` (by id, as
`TodayInput` takes them, so no order can reach the model); `settings: Settings` (its `weekStart` orders the
cells); `selectedWeek: Int`, a place in the block counted from 0, read as the nearest week when it is outside
the block; `loggedWeeks: Set<Int>`, the places of the weeks that hold a finished workout; `notice:
ProgramBuilderNotice?`, the notice the store is showing; `calendar` and `locale`.

**The model** (`ProgramBuilderModel`, `Equatable`, every string final):

| Part | Fields | What the view does with it |
|---|---|---|
| `header` | `eyebrow` "MY PROGRAM", `name` (the program's, as stored), `namePlaceholder` "Program name" | Draws the eyebrow and a one-line text field. The field is bound to a draft the store keeps, seeded from `name`, never to `name` itself (the stored name is cleaned: a field bound to it loses a trailing space and cannot be emptied); the placeholder is also the field's spoken label. The field sends `ProgramBuilderAction.rename(text)` (fix round 1, criterion 14). |
| `block` | `title` "BLOCK · 8 WEEKS"; `spokenLabel` "Block length", `spokenValue` "8 weeks"; `removeWeek`, `addWeek` (the actions of "−" and "+"); `chips` | Draws the title, the two buttons as icons and one chip per week. To VoiceOver the two buttons are one adjustable element (label, value; down is `removeWeek`, up is `addWeek`). |
| `block.chips[i]` | `title` "W1", `subtitle` "4 DAYS" or "DELOAD", `isDeload`, `isSelected`, `spokenLabel` "Week 1", `spokenValue` "4 days" or "Deload", `action` `.selectWeek(i)` | A button; `isDeload` picks the accent, `isSelected` the filled look and the selected trait. |
| `week` | `title` "WEEK 3" or "WEEK 3 · DELOAD", `hint` "Tap to assign", `cells` (seven), `copyPrevious`, `applyToLater` (nil on the last week), `deload` | A heading, the hint, the strip, up to three buttons. |
| `week.cells[i]` | `weekday` (identity), `letter` "T", `label` "UA" or "REST", `isRest`, `spokenLabel` "Tuesday", `spokenValue` "Rest" or the day's short title, `spokenHint` (optional), `action` (optional) | A button; with no training day in the program both are nil and the cell is drawn but is no button and has no hint (fix round 1, criterion 13). |
| `week.copyPrevious` | `title` "First week" or "Copy week 2", `action` (nil = disabled) | A button, disabled when `action` is nil. |
| `week.deload` | `title` "Deload", `isOn`, `action` | A button with the selected trait when on. |
| `days` | `title` "TRAINING DAYS", `summary` "4 days · 58 sets a week", `helper`, `cards`, `addDay` (title "+ Add training day", action) | A heading, two lines, the cards, one button. |
| `days.cards[i]` | `id`, `tag`, `name`, `meta` "5 exercises · 18 sets · ~39 min" or "No exercises yet", `chips` (short names, at most four, then "+2"), `spokenLabel` (the name), `spokenValue` (the meta), `action` `.route(.day(id, weekIndex:))` | A button; the chips are hidden from VoiceOver. |
| `notice` | `String?` | One line when not nil. |

**The actions** (`ProgramBuilderAction`, `Hashable`, `Sendable`): what a tap means, with nothing left to
decide.

| Case | What the store does |
|---|---|
| `.selectWeek(Int)` | Selects that week and drops the notice. Nothing is stored. |
| `.edit(ProgramBuilderEdit, notice: ProgramBuilderNotice?)` | Queues the edit (one `ProgramEditing` call, below) and sets its notice to `notice`: nil drops the one showing. |
| `.addWeek(selecting: Int)` | Draws a `WeekID`, queues `.addWeek(id)`, selects week `selecting`, drops the notice. |
| `.addDay(name: String, weekIndex: Int)` | Draws a `DayTemplateID`, queues `.addDay(id, name: name)`, drops the notice, emits `ProgramRoute.day(id, weekIndex: weekIndex)`. |
| `.notice(ProgramBuilderNotice)` | Changes nothing and shows the notice ("−" at two weeks, or on a logged week). |
| `.route(ProgramRoute)` | Emits the route. |

**The edits** (`ProgramBuilderEdit`, `Hashable`, `Sendable`): a queued edit, complete with its ids, and
`applied(to:) throws(ProgramEditError) -> Program`, which is exactly one `ProgramEditing` call:

| Case | The call | Relative? |
|---|---|---|
| `.renameProgram(String)` | `renameProgram(_:to:)` | no |
| `.addWeek(WeekID)` | `addWeek(_:id:)` | no (an id in use adds nothing) |
| `.removeLastWeek(loggedWeeks: Set<Int>)` | `removeLastWeek(_:loggedWeeks:)`, the one that throws | **yes** |
| `.setDeload(Bool, week: Int)` | `setDeload(_:_:week:)` | no (fix round 1, criterion 12; was `.toggleDeload`) |
| `.setSchedule(week: Int, weekday: Weekday, day: DayTemplateID?)` | `setSchedule(_:week:weekday:day:)` | no (fix round 1; was `.cycleSchedule`) |
| `.copyPreviousWeek(week: Int)` | `copyPreviousWeek(_:week:)` | no |
| `.applyToLaterWeeks(week: Int)` | `applyToLaterWeeks(_:week:)` | no |
| `.addDay(DayTemplateID, name: String)` | `addDay(_:id:name:)` | no (an id in use adds nothing) |

Since fix round 1 only `removeLastWeek` is relative here; `move` is the Day editor's (S7 and S14). A relative
edit reaches the stored program exactly once (the brief's "For S13 and S14").

**The notices** (`ProgramBuilderNotice`): `.minimumTwoWeeks`, `.weekHasLoggedSessions(weekNumber:)`,
`.dayHasNoExercises`; `init(_ error: ProgramEditError)` maps the Domain's two errors, for an `update` that
throws on the stored program. The presentation turns the input's notice into `model.notice`.

### What landed

Paths under `LedgerKit/`.

- `Sources/FeatureProgram/ProgramRoute.swift` (new, public): `.day(DayTemplateID, weekIndex: Int)` and
  `.closeDay`, as "Brief vs main" row 3 plans them. Nothing maps it yet: the mapping is S14's, in
  `LedgerAppKit`, which this slice does not touch.
- `Sources/FeatureProgram/ProgramBuilderInput.swift` (new): the one input value.
- `Sources/FeatureProgram/ProgramBuilderModel.swift` (new): the display model.
- `Sources/FeatureProgram/ProgramBuilderAction.swift` (new): `ProgramBuilderAction`, `ProgramBuilderEdit`
  with `applied(to:)`, `ProgramBuilderNotice` with `init(_: ProgramEditError)`.
- `Sources/FeatureProgram/ProgramPresentation.swift` (new): `make`, the notice's text, the one reading of the
  schedule (`scheduledDay(in:week:on:)`), the input resolved once (`Context`: the selected week's place, the
  cells' order, the weekday symbols). `ProgramPresentation+Weeks.swift`: the block, the chips, "−", the
  selected week, the cells, the cycle and its notice. `ProgramPresentation+Days.swift`: the summary, the cards,
  "+ Add training day".
- `Sources/FeatureProgram/ProgramCopy.swift` and `ProgramCopy+Days.swift` (new): every lookup.
  `Sources/FeatureProgram/Resources/Localizable.xcstrings` (new): 33 keys, 8 of them counted.
- `Sources/FeatureProgram/FeatureProgram.swift` and `Tests/FeatureProgramTests/FeatureProgramTests.swift`:
  deleted (the placeholder and its test).
- `Package.swift`: the target declares `resources: [.process("Resources")]`.
  `scripts/coverage-thresholds.json`: `FeatureProgram` joins `required`.
- Tests, all new, in `Tests/FeatureProgramTests/`: `ProgramPresentationTests.swift` with `+Week`, `+Days`,
  `+Notices`, `+Total`; `ProgramBuilderActionTests.swift`; `ProgramCopyTests.swift`;
  `ProgramPresentationPropertyTests.swift` with `+Inputs`; `FeatureProgramSourceTests.swift`;
  `Support/ProgramTesting.swift` (tags, the seeded generator, fixtures, and `BuilderScreen`, which applies an
  action exactly as the table above says a store does, so that criteria 2 to 6 are tested as "tap a control of
  the model, read the next model").

No view, no store, nothing of the Day editor or the library, no change to `LedgerDomain`, `LedgerAppKit`,
`LedgerTestSupport`, a test plan or the project file. `ModuleCopyTests.exemptions` has no entry for
`FeatureProgram`.

### Decisions and deviations

1. **The cells follow `Settings.weekStart`, not the weekday the block began on.** "Brief vs main" row 20
   plans the strip from the weekday of `program.startDate`; the S5 specification (criterion 3) and the brief
   (brief:60) say the settings' week start, and the orchestrator's task repeats it. Built as specified
   (`Sources/FeatureProgram/ProgramPresentation.swift:77-78`). Consequence, for Pete only if he asks: when the
   lifter changes the week start after the block began, left to right is no longer the order the days come
   in (a block begun on a Monday, shown from Sunday, draws week 3's Sunday first although it is that program
   week's last day). Open question 1.
2. **Edits are values with `applied(to:)`, in this slice** (`ProgramBuilderAction.swift:27-59`). The plan's
   S5 row has no such file; S3's "Inputs for S13 and S14" already writes the save as
   `edits.reduce(program) { try $1.applied(to: $0) }` over "the edits not stored yet, as Sendable values".
   Built here because the specification asks for actions "the store can apply without deciding anything",
   and because the worked examples of criteria 2 to 6 need the same mapping to be tested as display models.
   It is 22 product lines, each case one `ProgramEditing` call, pinned by
   `ProgramBuilderActionTests.applied_isTheOneProgramEditingCall`. S13's `ProgramEditSession` then holds only
   the queue and the loop.
3. **"−" is decided here, by asking the Domain** (`ProgramPresentation+Weeks.swift:22-30`).
   `ProgramEditing.removeLastWeek` is run on the program on screen with the input's logged weeks: the action
   is the edit when it returns and the notice when it throws. S1's "Inputs" had the store do this; moving it
   here leaves the store nothing to choose. The edit carries the logged weeks the model was built from, so
   the check is as fresh as `loggedWeeks` in the input and no fresher: `update` applies the same set to the
   stored program and reads no workout, so a workout finished in the last week between the tap and the write
   does not stop the removal (the plan accepts that window, "How a week is known to have logged sessions").
   S13 reads the logged weeks again before it sends this edit. (Corrected in fix round 1, review S-2.)
4. **The notice for an empty day rides on the cell's action** (`ProgramPresentation+Weeks.swift:106-112`).
   The Domain's cycle is run once per cell on the program on screen, only to see which day the tap assigns;
   the action is `.edit(.cycleSchedule(…), notice: .dayHasNoExercises)` when that day has no slot. The day is
   assigned all the same (brief:60). The presentation holds no cycle rule: reordering the Domain's cycle
   would change the notice with it.
5. **A schedule entry that names a day the program does not hold reads as rest**, on the chip's count and
   in the cell, through one function (`ProgramPresentation.swift:44-49`), which is how
   `ProgramEditing.cycleSchedule` reads it too (it restarts from the first day). `Program.init` refuses such
   a program; a mutated value can hold one.
6. **A program emptied of its weeks does not trap** (`ProgramPresentation.swift:71-76`,
   `ProgramPresentation+Weeks.swift:50-53`): no chip, "WEEK 1", seven rest cells whose actions the Domain
   ignores. Not in the specification's list; `weeks` is `var`, so the case can be written, and total was
   cheaper than a precondition.
7. **`WeekCalendar` is not used.** Criterion 10 names it among the Domain's sources; nothing the builder
   draws is a date. Which week holds today is behaviour 1, the store's (S13), and the input carries no
   moment. The injected calendar gives the weekday symbols only, with the injected locale set on a copy
   (`ProgramPresentation.swift:79-82`): its own locale, first weekday and time zone do not reach the model
   (`calendarsOwnSettings_doNotReachTheModel`).
8. **A day's set count is summed here** (`ProgramPresentation+Days.swift:30-32`): `sets + dropSets` over
   the slots, the brief's definition (brief:57). The Domain has no function for it (`TimeEstimate` holds the
   same sum privately, `LedgerDomain/Rules/TimeEstimate.swift:24`). A sum of stored numbers, not a rule; if
   S6 needs the same number for a week's prescription it should ask for a Domain function instead of
   writing the sum a third time.
9. **No equipment name is in the catalog.** Criterion 7 says "the equipment names this slice needs are
   entries of this catalog", and the plan's S5 row sizes `ProgramCopy.swift` "with the equipment names". The
   builder shows none (the cards show short names, which are data), and the gate fails a catalog key no code
   looks up. The first slice that draws one (S6, the Day editor's sub line) adds them.
10. **Two copy files.** `ProgramCopy.swift` passed SwiftLint's 150-line type body, so the training days and
    the notices are in `ProgramCopy+Days.swift`, the family the standard allows.
11. **"WEEK 3 · DELOAD" is two keys**, "WEEK %lld" and "DELOAD", joined with " · " (one counted value per
    key and the M1 join; the brief prints it as one line, brief:60). "DELOAD" is the chip's key too.
12. **"−" and "+" have no text in the model.** They are drawn as the design system's minus and plus icons;
    the model gives their two actions and the one spoken label and value the plan's VoiceOver tree asks for
    ("Block length", "8 weeks": one adjustable element).
13. **A cell's spoken value is "Rest" or the day's short title** ("Upper A"), not its tag: the plan's
    VoiceOver tree. The specification's example "Tuesday, rest" is the label and the value as VoiceOver
    joins them; the capital is the tree's.
14. **`exercises` is a dictionary by id**, as `TodayInput` has it, so criterion 9's "any order of the
    exercises" holds by the type; `exercises_inAnyOrder_giveTheSameModel` builds it in shuffled orders.
15. **The property inputs are lighter than the plan's line** ("2–52 weeks and 0–12 days"): 2 to 16 weeks,
    one block in sixteen of 52, so that the suite stays near 5 s on the host and needs no `.slow` tag (which
    would need an entry in the test plans). `make` alone measured about 0.8 ms for 16 weeks by 6 days of 7
    slots (Debug, host, 200 calls, a throwaway test not kept): the brief's 100 ms budget is not near.
    No timing test was added: a `.performance` suite must be listed in the plans' `skippedTests`, and the
    plans are not this slice's to edit. Open question 4.

### Criteria → tests

Suites: `ProgramPresentationTests` (PT), `ProgramBuilderActionTests` (AT), `ProgramCopyTests` (CT),
`ProgramPresentationPropertyTests` (PP), `FeatureProgramSourceTests` (ST).

| Criterion | Tests |
|---|---|
| 1 One input, one model | PT `seedProgram_readsAsCriterionOne`; AT `applied_isTheOneProgramEditingCall`, `applied_removeLastWeek_throwsTheDomainsErrors`, `applied_unknownPlace_changesNothing`, `relativeEdits_appliedTwice_differ`; PP `actions_randomProgram_applyToAValidProgram` |
| 2 The header and the block | PT `header_holdsTheNameAndItsPlaceholder`, `header_rename_isOneEdit`, `block_namesItsLengthAndMarksTheSelectedChip`, `chips_readTheDaysOrDeload_andSpeakTheSame`, `chips_oneDayAndNoDay_takeThePluralForm`, `chip_tap_selectsItsWeek`, `addWeek_appendsTheLastWeeksScheduleAndSelectsIt`, `removeWeek_dropsTheLastWeek_andTheSelectionStaysInside` |
| 3 The selected week (brief criteria 2, 3) | PT `cell_taps_cycleThroughTheDaysAndBackToRest`, `cells_eachCarriesTheCycleOfItsWeekday`, `cells_speakTheWeekdayAndWhatIsDrawn`, `cells_sundayStart_beginOnSunday`, `cells_anyWeekStart_beginOnIt`, `scheduleStrip_lettersFollowTheLocale`, `symbol_isTheOneAtTheWeekdaysPlaceFromSunday`, `weekActions_copyPrevious_takesTheWeekBefore`, `weekActions_firstWeek_isDisabled`, `weekActions_applyToLater_copiesTheScheduleNotTheDeload`, `weekActions_lastWeek_hasNoApplyToLater`, `weekActions_deload_togglesTheWeek` |
| 4 The seed program | PT `seedProgram_readsAsCriterionOne`, `seedProgram_minutesAreTimeEstimates` |
| 5 The day cards (brief criteria 5, 6) | PT `trainingDays_holdTheirFixedTexts`, `dayCard_chips_nameFourThenCountTheRest`, `dayCard_carriesTheRouteAndSpeaksWhatIsDrawn`, `dayCard_meta_isTheSlotsOwn`, `dayCard_meta_oneExerciseOneSet_isSingular`, `addDay_makesNewDayAndOpensIt`, `deletedDay_isGoneFromTheCardsAndTheSchedule` |
| 6 Notices (brief criterion 4, behaviour 6) | PT `message_twoWeeks`, `message_loggedWeek`, `removeWeek_loggedEarlierWeeks_isTheEditWithThem`, `notices_haveTheirLines`, `cycleOntoAnEmptyDay_showsTheNotice`, `notice_goesWhenAnotherWeekIsSelected`, `cycle_ontoTheOnlyDay_whenEmpty_carriesTheNotice` |
| 7 Words | CT `plainTexts_areTheBriefs`, `writtenTexts_areTheNotes`, `textsWithValues_areTheBriefs`, `countedTexts_haveOneAndOther`, `values_followTheLocaleHandedIn`; `ModuleCopyTests` (`LedgerAppKitTests`) for the audit and the built bundle; the gate's string-catalog step |
| 8 Spoken texts | PT `chips_readTheDaysOrDeload_andSpeakTheSame`, `cells_speakTheWeekdayAndWhatIsDrawn`, `dayCard_carriesTheRouteAndSpeaksWhatIsDrawn`, `block_namesItsLengthAndMarksTheSelectedChip`; PP `checkBlock` and `checkWeek` (the spoken value agrees with the drawn one on every random program) |
| 9 Pure and total | ST `sources_neverReadTheClockOrTheCurrentCalendar`, `check_findsASpellingInCodeAndInInterpolations`; PT `noDays_showsRestAndNoCard`, `everyWeekADeload_readsDeloadEverywhere`, `sixteenWeeksBySixDays_isWhole`, `selectedWeek_outsideTheBlock_readsAsTheNearest` (seven cases), `scheduleNamingAMissingDay_readsAsRest`, `noWeeks_doesNotTrap`, `dayCard_missingExercise_isCountedAndNamedByADash`, `exercises_inAnyOrder_giveTheSameModel`, `calendarsOwnSettings_doNotReachTheModel`, `dayWithoutNameOrTag_isDrawnAsStored`; PP `make_randomProgram_keepsTheInvariants` |
| 10 No rule of its own | ST `storesAndPresentations_neverClamp`; PT `seedProgram_minutesAreTimeEstimates`, `scheduleNamingAMissingDay_readsAsRest`; PP `cell_cycledThroughEveryDay_returns`, `checkBlock` ("−" is the edit exactly when the Domain removes the week) |
| 11 Wiring | `ModuleCopyTests.auditedModule_followsTheStandard("FeatureProgram")` and `builtBundle_resolvesEveryKey(of: "FeatureProgram")`, with no exemption; the string-catalog step; the coverage gate (the orchestrator's run) |

The plan's behaviour rows given to S5: 3 `weekActions_firstWeek_isDisabled`; 6
`cycleOntoAnEmptyDay_showsTheNotice`; 13 `dayCard_meta_isTheSlotsOwn`; 20
`scheduleStrip_lettersFollowTheLocale`. Row 2's display half ("the selection stays inside the block") is
`removeWeek_dropsTheLastWeek_andTheSelectionStaysInside`; rows 1 and 16 are the store's.

The property suite, per seed (200 in the pull-request lane): two random inputs checked for a whole model
(seven cells, each weekday once, from the week start; as many chips as weeks, one selected, the nearest;
each chip's count equal to a reference counted here from the stored schedule, and the selected chip's equal
to its cells that are not rest; every action naming the selected week or a day the program holds; "−" the
edit exactly when the Domain removes; every card's counts and minutes; no empty text); eight random actions
applied as a store applies them, the program rebuilt through `Program.init` after each; one cell cycled
through every day and back, the notice showing exactly on a day with no slot.

Checked by breaking the code (each change made, the suite run, the change undone): the week start ignored
(4 tests fail), the empty-day notice never set (3), a selection past the block read as the first week (3), a
card's route carrying the raw selection (2), drop sets left out (7), the locale not set on the calendar (2),
"Apply to later weeks" present on the last week (2), "Copy week" numbered one too high (2).

### The catalog's keys

All from the brief's "Copy (exact)" paragraph (brief:60) unless another line is given. "Counted" keys have
`one` and `other`.

| Key | Used for | From |
|---|---|---|
| `MY PROGRAM` | eyebrow | brief:60 |
| `Program name` | the name field's placeholder and spoken label | brief:60; the label is the plan's tree |
| `BLOCK · %lld WEEKS` (counted; one: `BLOCK · %lld WEEK`) | block title | brief:60 |
| `W%lld` | chip title | brief:60 |
| `%lld DAYS` (counted; one: `%lld DAY`) | chip subtitle | brief:60 |
| `DELOAD` | chip subtitle; second fragment of the week's title | brief:60 |
| `WEEK %lld` | the week's title | brief:60 |
| `Tap to assign` | hint | brief:60 |
| `REST` | a cell with no day | brief:60 |
| `First week`, `Copy week %lld`, `Apply to later weeks`, `Deload` | the week's buttons | brief:60 |
| `TRAINING DAYS` | section title | brief:60 |
| `%lld days` (counted), `%lld sets a week` (counted) | the summary, joined with " · " | brief:60 |
| `Shared by every week. The schedule above decides which day you train, and when.` | helper | brief:60 |
| `%lld exercises` (counted), `%lld sets` (counted), `~%lld min` (counted, both forms alike) | the card's meta, joined with " · " | brief:60 |
| `No exercises yet` | an empty day's meta | brief:60 |
| `+%lld` | the card's last chip | brief:60 |
| `+ Add training day` | button | brief:60 |
| `New day` | the name passed to `addDay` | brief:67 (criterion 5); plan, "Brief vs main" row 7 |
| `A block needs at least 2 weeks.` | notice | brief:60, brief:66 |
| `Week %lld has logged sessions and can't be removed.` | notice | brief:60, brief:66 |
| `Add at least one exercise before scheduling this day.` | notice | brief:60 |

**Texts the brief does not give, written here (for Pete):**

| Key | Where it is heard or seen | Why this wording |
|---|---|---|
| `Block length` | VoiceOver: the label of "−" and "+" as one adjustable control | the plan's VoiceOver tree ("Block length: one adjustable element") |
| `%lld weeks` (counted; one: `%lld week`) | VoiceOver: that control's value, "8 weeks" | the plan's tree |
| `Week %lld` | VoiceOver: a chip's label, "Week 3" | decision 6 ("Week 3, 4 days") |
| `%lld days` as a chip's spoken value, `Deload` as a deload chip's | VoiceOver: "4 days", "Deload" | decision 6; both keys are the brief's, reused |
| `Rest` | VoiceOver: a rest cell's value ("Tuesday, Rest") | decision 6 and the plan's tree; the drawn text stays "REST" |
| `Double-tap to assign` | VoiceOver: a cell's hint | the brief's accessibility line, "Tuesday, rest, button — double-tap to assign" (brief:86) |
| `—` | a card's chip for a slot whose exercise is not stored | the plan's behaviour 19 names such a slot "by a dash" in the Day editor; the card does the same |

Also written: the one forms of the counted keys that can never show ("BLOCK · 1 WEEK", "1 week": a block has
at least two weeks), which the catalog rule requires all the same.

Weekday letters ("M", "T") and names ("Tuesday") are not keys: they are the injected calendar's symbols in
the injected locale (behaviour 20).

### Code lines per file

Non-blank, non-comment lines, counted twice: when the model and the weeks were done (535 with the days and
the copy already written) and at the end.

| File (`LedgerKit/Sources/FeatureProgram/`) | Planned | Lines |
|---|---|---|
| `ProgramRoute.swift` | 12 | 5 |
| `ProgramBuilderInput.swift` | (in the model's) | 12 |
| `ProgramBuilderModel.swift` | 90 | 80 |
| `ProgramBuilderAction.swift` (actions, edits, notices) | not planned | 50 |
| `ProgramPresentation.swift` | 110 | 72 |
| `ProgramPresentation+Weeks.swift` | 70 | 93 |
| `ProgramPresentation+Days.swift` | 60 | 54 |
| `ProgramCopy.swift` | 130 | 115 |
| `ProgramCopy+Days.swift` | | 53 |
| **The module** | **about 470** | **534** |
| `LedgerKit/Package.swift` | | +6, −1 |
| `FeatureProgram.swift` (the placeholder, deleted) | | −4 |

539 lines written, 535 net: 14 % over the plan, under the 650 at which the plan re-estimates S6 to S8. The
excess is the copy (168 against 130: every lookup with a locale and a translator's comment takes five to
eight lines) and the action file. Tests: 1,451 lines in eleven files, not counted.

### The runs

- Host, `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'FeatureProgramTests|ModuleCopyTests'`: exit 0. `FeatureProgramTests`: 61 tests in 5 suites passed (about
  5 s, nearly all of it the three property tests at 200 seeds). `ModuleCopyTests`: 6 tests in 1 suite passed,
  `FeatureProgram` among the audited modules and among those whose built bundle resolves every key.
- `scripts/check.sh --lint-only`: exit 0 ("check.sh (--lint-only) OK"; format, lint, package graph, pins,
  script tests).
- Simulator, once, through the lock (iPhone 17, iOS 27.0, a cold `.derivedData` in the worktree, as
  `check.sh` step 3 does it): `xcodebuild build-for-testing` of scheme `Ledger`, plan `PR`: exit 0. Then
  `scripts/check-string-catalogs.sh`: exit 0, "string catalog matches the code:
  LedgerKit/Sources/FeatureProgram/Resources/Localizable.xcstrings (keys: 33)", and `LedgerAppKit`'s (7).
  Then `test-without-building -only-testing:FeatureProgramTests -only-testing:LedgerAppKitTests`: exit 0,
  297 tests passed, none failed or skipped (`FeatureProgramTests` 61, `LedgerAppKitTests` 236). The result
  bundles were read and deleted. No product or test source was edited after that build.
- **Not run:** the full gate, the watchOS build, the other test targets on the simulator, the coverage gate
  script (`scripts/coverage-gate.sh` reads the full PR result bundle), the nightly lane's 2,000 seeds.

### Coverage

Host, `swift test --enable-code-coverage --filter FeatureProgramTests`, read with `llvm-cov report` on the
test bundle:

| File | Lines | Regions |
|---|---|---|
| `ProgramPresentation.swift` | 63 / 63 | 28 / 28 |
| `ProgramPresentation+Weeks.swift` | 97 / 97 | 30 / 30 |
| `ProgramPresentation+Days.swift` | 56 / 56 | 13 / 13 |
| `ProgramBuilderAction.swift` | 26 / 26 | 16 / 16 |
| `ProgramBuilderInput.swift` | 2 / 2 | 2 / 2 |
| `ProgramCopy.swift`, `ProgramCopy+Days.swift` | 162 / 162 | 33 / 33 |
| **The module** | **406 / 406, 100 %** | **122 / 122** |

`ProgramBuilderModel.swift` and `ProgramRoute.swift` hold no executable line. The simulator's figure, which
is the gate's, was not read.

### Open questions, each with a recommendation

1. **Which weekday the strip starts on** (deviation 1). Built: the settings' week start, as the
   specification says. The plan's row 20 wanted the weekday the block began on. *Recommendation:* keep the
   specification's; it is what Today's strip does, and the two screens then agree. Change "Brief vs main"
   row 20 to say so. It is one line (`ProgramPresentation.swift:78`) and two tests either way.
2. **Standards §7's sentence on Domain names.** Ruling 3 of 2026-10-05 says "standards §7 gets that sentence
   in S5's pull request" (each module's catalog holds its own entry for a Domain name it shows), replacing
   "Not settled" at `docs/engineering-standards.md:249-253`. Not done here: the file is outside this slice's
   scope as handed over, and this slice shows no such name. *Recommendation:* the orchestrator adds the
   sentence to this pull request, or S6, the first slice with an equipment name, carries it.
3. **The empty and failed states' texts** (decision 6: "No program yet", "Can't show your program right
   now", "That change wasn't saved. Try again.") are not in the catalog: the specification's input has a
   program, and a catalog key no code looks up fails the gate. *Recommendation:* S13 adds the three states
   with their members in `ProgramCopy`; if S9 is to draw them first, S9 adds them.
4. **No timing test** (deviation 15). *Recommendation:* the orchestrator decides whether a `.performance`
   suite for `ProgramPresentation` at 16 × 6 and 52 × 12 is wanted in the nightly plan; it needs the plans'
   `skippedTests` edited. Measured by hand: about 0.8 ms a call at 16 × 6.
5. **The VoiceOver hint "Double-tap to assign"** names the gesture, which Apple's guidance for hints advises
   against (VoiceOver adds "double-tap to activate" itself when hints are on). It is the brief's wording
   (brief:86). *Recommendation:* ask Pete with S9's VoiceOver table; "Assigns the next training day" is the
   alternative, one key.
6. **A stale selection after "−".** The store may keep a selected place past the block's end; the model reads
   it as the last week, and "+" names the place it selects. *Recommendation:* S13 keeps it that way and
   stores nothing back; `model.block.chips` says which week is selected if it needs to know.

### Inputs for S9 (what each view is handed)

The table under "The model and the actions" is the contract. Beyond it:

- A view takes a part of the model and `(ProgramBuilderAction) -> Void`; it never builds an action, except
  the name field, which sends `.edit(.renameProgram(text))` with the text as typed (the Domain cleans it and
  ignores a blank one).
- Identity for `ForEach`: `DayCard` is `Identifiable`; cells by `\.weekday`; chips by their offset (a week's
  place is its identity on screen: `.selectWeek(place)`).
- A `Control` whose `action` is nil is drawn disabled ("First week"). `applyToLater == nil` means the button
  is not drawn; whether the row keeps its place for it is the view's layout.
- Accent: `WeekChip.isDeload` and `SelectedWeek.deload.isOn` are the only facts that pick a colour; `Cell.isRest`
  picks the filled or the outlined look. The title "WEEK 8 · DELOAD" is one string: if the view colours
  "DELOAD" alone it must not split the string itself; ask for a second field instead.
- VoiceOver, as the plan's tree: chip = `spokenLabel`, value `spokenValue`, selected trait from `isSelected`;
  cell = `spokenLabel`, value `spokenValue`, hint `spokenHint`; card = `spokenLabel`, value `spokenValue`,
  chips hidden; "−" and "+" = one adjustable element with `block.spokenLabel` and `block.spokenValue`,
  decrement `block.removeWeek`, increment `block.addWeek`; the name field's label is `header.namePlaceholder`;
  `block.title`, `week.title` and `days.title` are headings; the deload button is selected when `isOn`.
  If S9 draws "−" and "+" as two separate VoiceOver buttons instead, it needs two labels this slice did not
  write.
- A cell's `letter` can repeat (T, T; S, S); `weekday` tells them apart. A day whose tag or name is empty is
  drawn empty: data is shown as stored.
- `notice` is one line under the block; the model does not say where. For snapshots: any
  `ProgramBuilderInput` with `notice` set gives the state ("the two-weeks message").
- Previews and snapshots build models with `ProgramPresentation.make` from `Fixtures.seedProgram()`, fixed
  calendar and locale; nothing in the model needs a store.

### Inputs for S13 (what the store fills, and how it applies each action)

- **Fills:** `program` = the stored program with the waiting edits applied in order (`applied(to:)`);
  `exercises` = `observeAll()` keyed by id; `settings`; `selectedWeek` (behaviour 1 for the first value;
  `ProgramRoot(week:)` wins); `loggedWeeks` (the plan's "How a week is known to have logged sessions": only
  the last week's entry matters, a superset is harmless); `notice` (its own state, nil at first); `calendar`
  and `locale` from the dependencies.
- **Applies an action** exactly as the action table says; `Tests/FeatureProgramTests/Support/ProgramTesting.swift`
  (`BuilderScreen.tap`) is that table as fifteen lines of code. Ids for `.addWeek` and `.addDay` are drawn
  once, at the tap, and captured in the queued `ProgramBuilderEdit`.
- **Saves:** `programs.update(id) { program in try edits.reduce(program) { try $1.applied(to: $0) } }`.
  `ProgramBuilderEdit` is `Sendable` and holds only values, so the closure captures the array and nothing
  of the store.
- **Three of the edits are relative** (`removeLastWeek`, `toggleDeload`, `cycleSchedule`;
  `ProgramBuilderActionTests.relativeEdits_appliedTwice_differ` shows it): each queued edit reaches the
  stored program exactly once; after a failure the waiting edits are dropped, never sent again.
- **"−" is checked against `loggedWeeks` as the input had them**, not by the write: `update` cannot see a
  workout finished meanwhile. S13 reads the logged weeks again when the screen appears, whenever the recent
  workouts change, and before it sends `.removeLastWeek`. An `update` that throws `ProgramEditError` can only
  mean the stored block has another length than the screen's; then nothing was stored: drop the waiting
  edits, redraw from the stored program, set `notice = ProgramBuilderNotice(error)`. (Corrected in fix round
  1, review S-2.)
- **The notice** is replaced by every action that carries one and dropped by every other edit and by
  `.selectWeek` (behaviour 6). The cell's action already says whether the day it assigns is empty, judged on
  the program on screen.
- **`.addDay`** emits its route after the edit is queued; whether the route waits for the save is S13's
  (`route_isEmittedOnce_afterTheSaveReturned` in the plan says it does).
- **The save-failed line and the empty and failed states** have no text yet (open question 3).

## Slice S5 — fix round 1 (G1 implementer, 2026-10-06)

On f22bc30 (the slice f922c69, `main` merged, the tester's files and the review). Not committed. The brief's
"Plan amendments — slice S5 after round 1" (criteria 12 to 16) is the specification of this round. The
interface tables of the section above were brought up to date in place; each changed row says so.

### What changed, per item

Paths under `LedgerKit/` unless they begin with `docs/` or `tasks/`.

| Item | Change |
|---|---|
| **Criterion 12** (review S-1): absolute edits, in the Domain | `Sources/LedgerDomain/Programs/ProgramEditing.swift` gains `setDeload(_:_:week:)`, `nextInCycle(after:in:)` (the cycle's order: rest, each day in the order of `days`, rest; an entry that names a missing day counts as rest; no days stays at rest) and `setSchedule(_:week:weekday:day:)` (nil is rest; a day the program lacks changes nothing). `toggleDeload` is `setDeload` with the other state; `cycleSchedule` is `setSchedule` with `nextInCycle` of the entry the week holds. Their existing tests are untouched and green. New tests: `Tests/LedgerDomainTests/Programs/ProgramEditingAbsoluteTests.swift` (10 tests: the order of the cycle; a missing day; no day and one day; set to a day, to rest, twice; an unknown day or week; `setSchedule` with `nextInCycle` equal to `cycleSchedule` on all 56 cells of the seed block; `setDeload` on, off, twice, equal to the toggle; weeks outside the block). Rows `setDeload` and `setSchedule` in `EditingTestSupport.programEdits` (`Tests/LedgerDomainTests/Programs/EditingTestSupport+Edits.swift`), so S1's criterion-12 property draws both and `EditingSourceTests.sources_everyEditIsInThePropertysTables` passes; `nextInCycle` returns no program and needs no row. |
| **Criterion 12**, in the feature | `ProgramBuilderEdit.toggleDeload(week:)` and `.cycleSchedule(week:weekday:)` are replaced by `.setDeload(Bool, week:)` and `.setSchedule(week:weekday:day:)` (`Sources/FeatureProgram/ProgramBuilderAction.swift`). The deload button's action is `.setDeload(!isOn, week:)`. A cell asks `ProgramEditing.nextInCycle` for the value after the entry its week holds and hands out `.setSchedule` with it; the empty-day notice is judged on that same named day, so the notice and the edit cannot disagree (`ProgramPresentation+Weeks.swift`, `cycle`). The speculative `cycleSchedule` per cell is gone. Tests: `cells_eachNamesWhatItsWeekdayBecomes`, `cell_actionAppliedTwice_givesWhatOneGives`, `weekActions_deload_togglesTheWeek` (the drawn action applied twice), `ProgramBuilderActionTests.edits_appliedTwice_onlyRemoveLastWeekDiffers` (replaces `relativeEdits_appliedTwice_differ`), the property suite's `checkWeek` (the named day is rest or a day the program holds, never the one shown). |
| **Criterion 13** (F11-S5-2): no day, nothing offered | `Cell.action` and `Cell.spokenHint` are optional and nil when the program has no training day; the spoken label and value stay ("Monday", "Rest"). Tests: `noDays_showsRestAndNoCard_andTheCellsOfferNothing`, `oneDay_everyCellOffersItsCycle`, the property suite. The strip's drawn hint "Tap to assign" is still in the model for such a program: the criterion names the cell; open question below. |
| **Criterion 14** (S-3): the name is a draft | `ProgramBuilderAction.rename(_:)` (static, three lines); `Header.name`'s comment says it seeds the field and a view binds a draft the store keeps. Test: `rename_isTheRenameEditWithTheTypedText`; `header_rename_isOneEdit` goes through it. |
| **Criterion 15** | Nothing changed. |
| **Criterion 16, S-2** | The two sentences of the section above are corrected in place (deviation 3 and "Inputs for S13"): the check is as fresh as the input's `loggedWeeks`; S13 reads them again before it sends the edit. The case's doc comment says the set is the one the model was built from. |
| **Criterion 16, S-4** | `docs/engineering-standards.md` §7: the bullet "Not settled: display names shared by several features" is replaced by the reviewer's "A Domain value's name is each module's own", word for word. The plan's S5 row no longer reads "with the equipment names". |
| **Criterion 16, S-5** | No whole `Program` inside an expectation: `ProgramPresentationPropertyTests` (the notice case), `+Notices` (two weeks); the third place (`+Total`) went with criterion 13. |
| **Criterion 16, S-6** | `FeatureProgramSourceTests` has the `inexact` list and `presentationsCopyAndModels_neverNameDouble` over files named Presentation, Copy or Model, with its line in the self-check. |

**The nits.**

| Nit | Done or declined |
|---|---|
| N-1 `.addWeek(selecting:)` from the drawn model | Declined here, as the reviewer says. For S13: select the last week of the program the edit was just applied to, or rebuild the model between intents. |
| N-2 chips without identity | Done: the comment on `DayCard.chips` says they are identified by their place. |
| N-3 the clamp tripwire's files | Done: it reads every file but those named Copy, Model or Route (`canHoldLogic`), so a session or a view is read too. |
| N-4 four keys without a comment | Done, in the code and the catalog (below). |
| N-5 "Deload" as one key for a button and a spoken state | Declined: the cure is a new English text ("Deload week"), which is Pete's to choose. Nothing breaks while English alone ships. Listed for him below. |
| N-6 two test names | Done: `removeWeek_twoWeeks_showsTheNoticeAndChangesNothing`, `removeWeek_loggedLastWeek_namesTheWeek`. |
| N-7 how VoiceOver says "~39 min" | Not changed: needs ears on a simulator, which is S9's VoiceOver pass. |
| N-8 `BuilderScreen` beside the store | Not changed here; for S13: drive these scenarios through the store, or build `BuilderScreen` on its session. |
| N-9 size | For the pull request's description: see the count below. |

### Catalog texts

No key added, removed or reworded: 33 keys. Four keys gained a translator's comment (N-4): "%lld sets a
week" ("Every training day's sets together, after the number of training days"), "%lld exercises" ("On a
day's card: the number of exercises the day has"), "%lld sets" ("On a day's card: the day's sets, its drop
sets among them"), "Week %lld has logged sessions and can't be removed." ("Shown when the last week cannot
be removed: the week's number, counted from 1").

### Sanctioned edits to the tester's files

The S5 tester's files under `Tests/FeatureProgramTests/Adversarial/`, each the smallest edit for the target
to compile. A removed case is replaced by the new case with a placeholder payload (`true`, `day: nil`), not by
what the new behaviour is: what a test expects was left to the tester. Nothing of the S1 tester's files was
touched.

| File:line | Edit |
|---|---|
| `ProgramAdversarialSupport.swift:179` | `case .toggleDeload(week)` calling `toggleDeload` → `case .setDeload(isDeload, week)` calling `setDeload` |
| `ProgramAdversarialSupport.swift:180-181` | `case .cycleSchedule(week, weekday)` calling `cycleSchedule` → `case .setSchedule(week, weekday, day)` calling `setSchedule` |
| `ProgramActionsAdversarialTests.swift:19` | `cells.map { (…, $0.action) }` → `cells.compactMap { cell in cell.action.map { (…, $0) } }` (the action is optional) |
| `ProgramActionsAdversarialTests.swift:35` | the pattern's `.toggleDeload(week)`, `.cycleSchedule(week, _)` → `.setDeload(_, week)`, `.setSchedule(week, _, _)` |
| `ProgramActionsAdversarialTests.swift:175` | `AdvStore.apply(cell.action, …)` → `try AdvStore.apply(#require(cell.action), …)` |
| `ProgramCountsAdversarialTests.swift:45` | the same `try … #require(…)` around `cells[0].action` |
| `ProgramCountsAdversarialTests.swift:109` | `.toggleDeload(week: nearest)` → `.setDeload(true, week: nearest)` |
| `ProgramAdversarialScreen.swift:140` | `.toggleDeload(week: place)` → `.setDeload(true, week: place)` |
| `ProgramAdversarialScreen.swift:154-156` | `.cycleSchedule(week: place, weekday: weekday)` → `.setSchedule(week: place, weekday: weekday, day: nil)`, wrapped over three lines to keep the file at 300 |
| `ProgramWeekdaysAdversarialTests.swift:66` | `.cycleSchedule(week: 0, weekday: $0.weekday)` → `.setSchedule(week: 0, weekday: $0.weekday, day: nil)` |
| `ProgramWeekdaysAdversarialTests.swift:165` | `hints.insert(cell.spokenHint)` → `hints.insert(cell.spokenHint ?? "")` |
| `ProgramWordsAdversarialTests.swift:50-51` | the hint taken out of the array of texts and added through `compactMap` (it is optional) |
| `ProgramWordsAdversarialTests.swift:104-108` | the same `try … #require(…)` around `cells[0].action`, wrapped by the formatter |
| `ProgramSeedAdversarialTests.swift:80` | `.toggleDeload(week: 7)` → `.setDeload(true, week: 7)` |
| `ProgramSeedAdversarialTests.swift:98` | `.cycleSchedule(week: 0, weekday: .tuesday)` → `.setSchedule(week: 0, weekday: .tuesday, day: nil)` |
| `ProgramSeedAdversarialTests.swift:99`, `:199` | the same `try … #require(…)` around the cell's action |

### The tester's pins that now fail, for the tester

Nine tests, all in `Tests/FeatureProgramTests/Adversarial/`, all because they pin the relative edits or the
cells of a program with no days. No other test of the two targets fails.

| Test | It expects | Now |
|---|---|---|
| `ProgramSeedAdversarialTests.seed_everyWeek_matchesTheTestersScreen` (8 cases) | the tester's screen (`ProgramAdversarialScreen.swift:140`, `:154`): the deload's action is the toggle of the week, a cell's the cycle of its weekday | the deload's is `.setDeload(!isOn, week:)`; a cell's is `.setSchedule(week:weekday:day:)` with `ProgramEditing.nextInCycle` of the entry the week holds, and nil with no days |
| `ProgramActionsAdversarialTests.walk_everyStep_matchesTheTestersScreen` (60 cases; both expectations, the second because the walk stops at the first difference) | the same screen | the same |
| `ProgramActionsAdversarialTests.testersModel_isNotBlind` | the same screen | the same |
| `ProgramCountsAdversarialTests.selectedWeek_outOfRange_isTheNearestWeek` (9 cases; `:109` and the screen) | `.toggleDeload(week: nearest)` | `.setDeload(!isOn, week: nearest)` |
| `ProgramCountsAdversarialTests.blockLengths_readTheirWeeks` (3 cases) | the same screen | the same; every week there is a deload, so `.setDeload(false, week:)` |
| `ProgramSeedAdversarialTests.seed_deloadWeek_readsAsTheBrief` (`:80`) | `.toggleDeload(week: 7)` | `.setDeload(false, week: 7)`: week 8 is a deload, the button turns it off |
| `ProgramSeedAdversarialTests.seed_tuesdayTappedFiveTimes_cyclesAndCounts` (`:98`) | `.cycleSchedule(week: 0, weekday: .tuesday)` at every tap | `.setSchedule(week: 0, weekday: .tuesday, day:)` with UA, LA, UB, LB, then nil; what the taps draw is unchanged |
| `ProgramWeekdaysAdversarialTests.sundayStart_seed_rotatesTheStripOnly` (`:66`) | each cell `.cycleSchedule(week: 0, weekday:)` | each cell `.setSchedule(week: 0, weekday:, day:)` with the next day of its own cycle |
| `ProgramCountsAdversarialTests.noDays_readsZeroAndRests` (`:45`) | a cell of a program with no days carries an action whose tap changes nothing and says nothing | the cell has no action and no hint (criterion 13); `#require` at `:45` stops the test |

### Product lines now

| File | Round 0 | Now |
|---|---|---|
| `ProgramBuilderAction.swift` | 50 | 53 |
| `ProgramCopy+Days.swift` | 53 | 73 (four comments, each lookup now over six lines) |
| `ProgramPresentation+Weeks.swift` | 93 | 101 |
| `ProgramPresentation.swift`, `ProgramBuilderModel.swift`, `ProgramCopy.swift`, `ProgramPresentation+Days.swift`, `ProgramBuilderInput.swift`, `ProgramRoute.swift` | 72, 80, 115, 54, 12, 5 | unchanged |
| **`FeatureProgram`** | **534** | **565** |
| `LedgerDomain/Programs/ProgramEditing.swift` | 71 | 92 (+21) |
| `Package.swift` | +5 net | unchanged |

591 in the pull request (565 + 21 + 5), against 470 planned and the 500-line target of standards §10; the
description should say so and name the split considered and not taken (the action file with the Domain's
three functions, about 75 lines, is not worth a cycle). Under the 650 at which S6 to S8 are estimated again.

### Open, with a recommendation

- **"Tap to assign" over a strip that offers nothing** (a program with no days): `week.hint` is still in the
  model. Criterion 13 names the cell only. *Recommendation:* leave it; S9 may dim it, and a block with no
  day is one tap on "+ Add training day" away from having one. If it should go, `SelectedWeek.hint` becomes
  optional: two lines and one test.
- **For Pete, with S9's VoiceOver table:** "Deload" spoken for a deload week's chip is the button's key
  (N-5); "Double-tap to assign" names the gesture (round 0's open question 5).

### Inputs for S13, changed by this round

- Two edits changed shape (the table above); the cell and the deload are safe to draw or apply twice. Only
  `.removeLastWeek` is relative in this screen: it reaches the stored program exactly once.
- The name field: the store keeps the draft and sends `ProgramBuilderAction.rename(text)` as it is typed;
  `model.header.name` seeds the draft and is not written back into the field while it has focus. A test:
  "Upper Lower" typed letter by letter stores "Upper Lower" (review S-3).
- "−": read the logged weeks again before sending `.removeLastWeek` (review S-2).
- N-1 and N-8 above.

### The runs

- Host, `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'FeatureProgramTests|LedgerDomainTests'`: exit 1, by the nine pins alone. `LedgerDomainTests`: 1,212 tests
  in 185 suites passed (the ten new ones, S1's own and the S1 tester's among them, none edited).
  `FeatureProgramTests`: 109 tests in 11 suites, 100 passed, 9 failed with 156 issues: exactly the nine of
  the table above. All 65 of the implementer's tests pass.
- `scripts/check.sh --lint-only`: exit 0.
- Simulator, once, through the lock (iPhone 17, iOS 27.0): `build-for-testing` exit 0;
  `scripts/check-string-catalogs.sh` exit 0, "string catalog matches the code: …/FeatureProgram/Resources/Localizable.xcstrings
  (keys: 33)"; `test-without-building` of `FeatureProgramTests` and `LedgerAppKitTests`: exit 65, 345 tests,
  336 passed, 9 failed: `LedgerAppKitTests` 236 passed (`ModuleCopyTests` in it, no exemption);
  `FeatureProgramTests` 109 with the same nine failing, by name. The result bundle was read and deleted. No
  source was edited after that build.
- Coverage, host, the raw profiles merged with `llvm-profdata` (the run exits 1, so SwiftPM merges nothing)
  and read with `llvm-cov export -summary-only`: `ProgramPresentation.swift` 63/63 lines, 28/28 regions;
  `+Weeks` 107/107, 36/36; `+Days` 56/56, 13/13; `ProgramBuilderAction.swift` 29/29, 17/17; the copy files
  182/182; the module 439/439. `LedgerDomain/Programs/ProgramEditing.swift` 98/98 lines, 49/49 regions, the
  three new functions in it.
- **Not run:** the full gate, the watchOS build, `LedgerDomainTests` and the other targets on the simulator,
  the coverage gate script, the nightly seeds, and on the host any target but the two. No source or test
  outside `LedgerDomain/Programs`, `LedgerDomainTests` and `FeatureProgramTests` calls `cycleSchedule` or
  `toggleDeload` (searched).

### Fix round 1, addendum: the week's hint (orchestrator's ruling on criterion 13)

With no training day the whole strip offers nothing: `SelectedWeek.hint` is optional and nil then
(`ProgramPresentation+Weeks.swift`, `selectedWeek`); test `noDays_theWeeksHintIsAbsent`, and the property
suite's `checkWeek`. The open point above is closed. Two more sanctioned edits to the tester's files, in
their own idiom for an absent text: `Adversarial/ProgramWordsAdversarialTests.swift:41`
(`model.week.hint` → `model.week.hint ?? "REST"`) and `Adversarial/ProgramAdversarialScreen.swift:229`
(`.text(week.hint)` → `.text(week.hint ?? "absent")`): nineteen in all.

## Slice S6 — the Day editor's and the slot editor's presentation (G1 implementer, 2026-10-08)

Branch `feat/F11-s6-day-slot-presentation`, on the specification commit `7e15f61`. Not committed: the
orchestrator commits. The plan's S6 and S7 as one slice. This section was started before the code and extended
as the work went; a part still marked *(pending)* was not reached.

### The models and the actions (written first, as the interface)

`DayEditorPresentation.make(_ input: DayEditorInput) -> DayEditorModel`, all in `FeatureProgram/DayEditor/`,
all `nonisolated` and internal to the module. The panel under the open exercise is built by
`SlotEditorPresentation` and is a field of the open row.

**The input** (`DayEditorInput`): `program: Program` (the program on screen); `day: DayTemplateID`;
`exercises: [ExerciseID: Exercise]`; `settings: Settings` (its units); `weekIndex: Int`, the week shown, a
place in the block from 0, read as the nearest week when it is outside the block; `openSlot: SlotID?`, read as
none when the day does not hold it; `locale`.

**The model** (`DayEditorModel`, `Equatable`, every string final): `.dayIsGone` when the program does not
hold the day (the store emits `ProgramRoute.closeDay`), or `.editing(Content)`:

| Part | Fields | What the view does with it |
|---|---|---|
| `id` | the day's id | Passed to `DayEditorAction.rename(_:day:)` by the name field. |
| `header` | `back` ("Program"), `position` "DAY 1 OF 4", `done` ("Done"), `name` (as stored; seeds a draft the store keeps, as the builder's name does), `nameLabel` "Day name" (placeholder and spoken label), `tag` "UA", `meta` "Week 1 · 5 exercises · 18 sets · ~39 min" | The pinned header. `position` is a heading. |
| `groups[i]` | `header` (nil for an exercise on its own): `title` "SUPERSET", `note` "2 exercises back to back · rest after B", `spokenLabel` "Superset"; `rows` | One visual block per group; the header is a heading whose value is the note. |
| `groups[i].rows[j]` | `id` (the slot's), `index` "4A", `name` (or "—"), `sub` "Cable · Reps 12–14 · RPE 9 · no rest", `scheme` "3×12", `load` "100 lb" (nil when the exercise is not stored), `hasDropSet`, `isOpen`, `spokenLabel` "4A, Lat Pulldown", `spokenValue` "3×12 · 100 lb · Cable · …", `action` (opens it, or closes it when open), `panel: SlotEditorModel?` (not nil exactly when open) | A button; under it the panel when `panel` is not nil. |
| `addExercise` | "+ Add exercise from library", `.openLibrary` | A button. |
| `deleteDay` | `title` "Delete day"; `confirmation`: `title` "Delete Lower B?", `message` "It's scheduled in 7 weeks. Those days become rest." (nil when scheduled nowhere), `confirm` ("Delete", the edit), `cancel` "Cancel" | The button presents a confirmation drawn from these values; whether it is showing is the view's own presentation flag. |

**The panel** (`SlotEditorModel`): `details` (nil when the exercise is not stored: such a slot can only be
moved, joined, broken out or removed), `supersetActions` (none, "Break out", "Superset with next", or both),
`moveUp`, `moveDown` (each nil when the Domain's move would leave the day as it is), `remove`.

| `details` part | Fields |
|---|---|
| `week` | `eyebrow` "WEEK 8 · DELOAD", "WEEK 3 · HELD" or "WEEK 1"; `isDeload`, `isHeld`; `line` "4 × 5 @ 240 lb · RPE 6" |
| `fields[i]` | `kind` (identity), `label` "SETS", `value` "5", `spokenLabel` "Sets", `decrement`, `increment`: one adjustable element (label `spokenLabel`, value `value`). Five fields; six with "TOP OF RANGE" under double progression. Both directions are always offered (behaviour 11). |
| `progression` | `title` "PROGRESSION"; `chips` (title, `isSelected`, `action`, nil on the selected one); `note` |
| `dropSet` | `title` "Drop set", `note` (one of two), `isOn`, `action` |
| `strip` | `text` "W1 50 · W2 50 · … · W8 47.5 (deload)"; `entries` (each `text`, `isDeload`, `isHeld`, `isShown`) |

**The actions** (`DayEditorAction`, `Hashable`, `Sendable`):

| Case | What the store does |
|---|---|
| `.open(SlotID?)` | Sets the open slot to it (nil closes). Nothing is stored. |
| `.edit(DayEditorEdit, closesPanel: Bool)` | Queues the edit; when `closesPanel`, sets the open slot to nil. |
| `.openLibrary` | Presents the exercise library (S8, S14). |
| `.route(ProgramRoute)` | Emits the route (`.closeDay` for back and "Done"). |

**The edits.** `DayEditorEdit.applied(to: Program) -> Program` is exactly one `ProgramEditing` call, and never
throws:

| Case | The call | Relative? |
|---|---|---|
| `.renameDay(String, day:)` | `renameDay(_:day:to:)` | no |
| `.deleteDay(DayTemplateID)` | `deleteDay(_:day:)` | no |
| `.slot(SlotEdit, day:)` | `updateDay(_:day:) { edit.applied(to: $0) }` | as the slot edit |

`SlotEdit.applied(to: DayTemplate) -> DayTemplate` is exactly one `DayEditing` call:

| Case | The call | Relative? |
|---|---|---|
| `.set(SlotField, slot:)` | `set(_:slot:in:)`; the field holds the value `DayEditing.stepped` gave when the model was built | no |
| `.setProgression(Progression, slot:)` | `setProgression(_:slot:in:)` | no |
| `.setDropSet(Bool, slot:)` | `setDropSet(_:slot:in:)` | no |
| `.setSuperset(Bool, slot:)` | `setSuperset(_:slot:in:)`; "Superset with next" names the next slot | no |
| `.move(MoveDirection, slot:)` | `move(_:slot:_:)` | **yes** |
| `.remove(slot:)` | `removeSlot(_:slot:)` | **marked yes** (see Decisions) |

`isRelative` on both edit types is the mark: a relative edit reaches the stored program exactly once.

### What landed

Paths under `LedgerKit/`.

- `Sources/FeatureProgram/DayEditor/` (new folder): `DayEditorInput.swift` (the one input value);
  `DayEditorModel.swift` and `SlotEditorModel.swift` (the display models); `DayEditorAction.swift`
  (`DayEditorAction`, `DayEditorEdit`, `SlotEdit`, each edit with `applied(to:)` and `isRelative`);
  `DayEditorPresentation.swift` (`make`, the header, the meta line, "Delete day", the input resolved once:
  `Context` and `Shown`); `DayEditorPresentation+Rows.swift` (the groups, a superset's header, a row and its sub
  line); `SlotEditorPresentation.swift` (the panel, the progression and its note, the drop set, the superset
  actions, move, remove); `SlotEditorPresentation+Fields.swift` (the steppers);
  `SlotEditorPresentation+Preview.swift` (the shown week's line and the strip of every week);
  `ProgramCopy+DayEditor.swift` and `ProgramCopy+SlotEditor.swift` (every lookup).
- `Sources/FeatureProgram/Resources/Localizable.xcstrings`: 33 keys before, 101 now (68 new, 2 of them
  counted); three existing keys' comments reworded because the key gained a second use.
- `Sources/FeatureProgram/ProgramPresentation.swift`: `nearestPlace(to:in:)`, the builder's reading of a
  selection outside the block taken out of `Context.init` so that the Day editor reads its week the same
  way; no behaviour changed. `ProgramPresentation+Days.swift`: `setCount(of:prescriptions:)` takes a week's
  prescriptions (default none, so the builder's cards are as they were). `ProgramCopy.swift`: three comments.
- `Sources/LedgerDomain/Model/Slot.swift`: `resolvedStartLoad(exercise:units:)` and
  `resolvedStep(exercise:units:)` (criterion 8), now the one place the pair of fallbacks is written
  (`Slot.swift:118`, `:124`). `Rules/ProgressionRules.swift:29-30` and
  `Programs/DayEditing+Fields.swift:70-71` call them in place of the repeated pair; no existing Domain test
  was edited.
- Tests, all new: in `Tests/FeatureProgramTests/`, `DayEditorPresentationTests.swift` with `+Groups`, `+Loads`,
  `+Total`; `SlotEditorPresentationTests.swift` with `+Progression`, `+Preview`; `DayEditorActionTests.swift`
  with `+Model`; `DayEditorPresentationPropertyTests.swift` with `+Inputs`; `ProgramCopyTests+DayEditor.swift`;
  `Support/DayEditorTesting.swift` (fixtures, and `DayScreen`, which applies an action exactly as the table
  above says a store does). `FeatureProgramSourceTests.swift` gained four lines: the Day editor's files are
  seen to be among those the three source checks read. In `Tests/LedgerDomainTests/Model/`,
  `SlotResolvedLoadTests.swift`.

No view, no store, nothing of the exercise library, no change to `LedgerAppKit`, `LedgerTestSupport`, a test
plan, the project file or a tester's file.

### Decisions and deviations

1. **A rename and a delete are `ProgramEditing`'s own calls**, not an `updateDay` around a `DayEditing` call
   as criterion 1 words every action: `renameDay(_:day:to:)` and `deleteDay(_:day:)` are the functions the
   Domain has for them (`LedgerDomain/Programs/ProgramEditing+Days.swift:19`, `:31`). Each edit is still
   exactly one Domain call, pinned by `DayEditorActionTests.edit_applied_isTheOneProgramEditingCall`.
2. **Two actions store nothing and are not routes**: `.open(SlotID?)` and `.openLibrary`. Criterion 1 lists
   "an edit or a `ProgramRoute`"; opening a panel and presenting the library sheet are the store's own
   state (the sheet is presented by `DayEditorRoot` itself, "Brief vs main" row 2), as `.selectWeek` is in
   the builder.
3. **The input has no calendar.** Criterion 1 lists "the calendar and locale"; the Day editor draws no date
   and no weekday, so a calendar would be a field nothing reads. The locale is there.
4. **Whether the panel closes is on the action** (`.edit(_, closesPanel:)`). The spec has the superset
   actions and Remove close it and a move keep it open (`docs/product-spec.md:247-248`); the model says so,
   and the store does not decide. Deleting the day closes it too.
5. **A removal is marked relative, and is in fact safe to apply twice.** The specification's decision is
   "move and remove the only relative ones"; `SlotEdit.isRelative` marks both. By the evidence only a move
   differs when applied twice: a removal names its slot, so a second one finds nothing
   (`DayEditorActionTests.edits_appliedTwice_onlyAMoveDiffers` shows both facts). The mark on a removal is
   therefore the cautious reading (which member then leads a superset is decided by the day the edit meets)
   and costs nothing, since every queued edit reaches the stored program once anyway. Open question 1.
6. **Nothing is offered that does nothing, by asking the Domain.** A move and a superset action are in the
   model only when the edit, applied to the day on screen, changes `DayEditing.groups`
   (`DayEditorPresentation.swift:157`, `Context.rearranges`); the presentation has no rule of its own for
   "first of its group" or "last of the day". The selected progression's chip has no action (choosing it
   again changes nothing, S1 criterion 14). The two exceptions are the steppers, which offer both directions
   at their limits (behaviour 11), and the drop set, which always has another state.
7. **"Break out" and "Superset with next" can both apply** (the last member of a superset that is not the
   day's last exercise, `docs/product-spec.md:247`), so the panel carries `supersetActions`, an array of
   none, one or two, not "the action that applies" of criterion 4.
8. **A row shows the shown week's prescription; the fields show the slot's own numbers.** Sets, reps, load
   and RPE on a row are the week's, as the prototype's are (`design/prototype/Ledger.dc.html:1336`,
   `:1370-1372`), so a deload week's rows read a set fewer and RPE two lower while the steppers keep the
   written values. The range in "Reps 10–12" is the slot's; "+5/wk" is the prescription's step.
9. **A slot whose exercise is not stored** (behaviour 19) is named "—", shows its own sets, reps and RPE, no
   load, a sub line without the equipment and the progression ("RPE 8 · 2:30 rest"), and a panel with no
   `details`: it can be moved, joined, broken out and removed. Its fields cannot be edited here, because the
   start load and its step need the exercise. A program emptied of its weeks is drawn the same way (no
   prescription can be worked out); `Program.init` refuses such a program, `weeks` is `var`.
10. **A day with no exercise reads "Week 1 · No exercises yet"**: the builder's text for an empty day after
    the week, in place of "0 exercises · 0 sets · ~0 min". The brief gives the meta line's form only.
11. **The day's sets in a week are summed in the feature, once**: `ProgramPresentation.setCount` takes the
    week's prescriptions and counts their sets with each slot's drop sets, as `TimeEstimate.minutes` does
    inside (`LedgerDomain/Rules/TimeEstimate.swift:21-24`). S5's deviation 8 asked that S6 use a Domain
    function instead of writing the sum again; it is not written again, but it is still not the Domain's.
    Open question 2.
12. **Lines are fragments joined with " · "**, as S5's are: the sub line is up to five keys, the superset's
    note two ("%lld exercises back to back", counted, and "rest after %@"), the week's line two
    ("%lld × %lld @ %@ lb" and "RPE %@"), the eyebrow two or three ("WEEK %lld", "DELOAD" or "HELD"). The
    brief prints each as one format.
13. **A week carries one mark.** A deload week whose week before was missed reads "DELOAD", as the prototype
    has it (`Ledger.dc.html:1373`); `WeekLine.isHeld` and `Entry.isHeld` are false there, so the flags agree
    with the words.
14. **The strip marks a held week "(held)"**, a text the brief does not give: it gives "W8 240 (deload)" and,
    for the eyebrow, " · HELD". " · " separates the strip's weeks, so "W4 260 · HELD" would read as two
    entries.
15. **Field labels are the brief's capitals; the spoken labels are in sentence case** ("Sets", "Rep floor").
    Pete's decision 1 (default A) draws the labels in sentence case: those are the same words as the spoken
    labels, so S11 can draw either field of the model without a new text.
16. **Digits.** Counts printed through a key follow the injected locale, as S5's do. A stepper's whole number
    is formatted with the injected locale (`SlotEditorPresentation+Fields.swift`), not looked up: a key of
    "%lld" alone would be a catalog entry with no word. Loads, RPEs and rests are the Domain's text and keep
    its digits (standards §7, "Not copy").
17. **"Delete day"'s confirmation is always in the model**, as values; whether it is showing is the view's
    presentation flag (the input of criterion 1 has no field for it). The second line counts weeks, not
    weekdays (a day trained twice in a week counts once), and the title names the day by its short title
    ("Delete Lower B?" for "Lower B — Hinge focus"). Confirming is one edit; the next model is `.dayIsGone`
    and the store closes the editor, which is also what happens when the day is deleted elsewhere
    (behaviour 15).
18. **One key, two uses, in three places**: "REST" (a rest day's cell, and the stepper's label), "Rest" (a
    rest day's spoken value, and the stepper's spoken label), "Fixed" (the row's mark and the chip), "Week
    %lld" (a chip's spoken label, and the meta line). The key is the English text, so the catalog cannot
    hold two; each comment now names both uses. A translation that needs two words for "rest" needs a
    second English text first (S5's nit N-5 is the same case). Open question 4.
19. **A row's spoken value joins with " · "** ("3×12 · 100 lb · Cable · …"), where the plan's VoiceOver tree
    writes commas after the scheme and the load: a comma needs a key, the separator does not.
20. **`Group.id` is optional** (the id of its first row): a group is never empty, and an optional id avoids
    a branch no test could reach.
21. **The model is an enum**: `.editing(Content)` or `.dayIsGone`. Views take `Content`.
22. **`DayEditorEdit` has no case for the library's picks** (`DayEditing.addSlots`): the library is S8's and
    S14's, and the task leaves it out of this slice.
23. **The property inputs** are blocks of 2 to 12 weeks, one to four days and 0 to 8 slots, drawn from the
    whole range of each field with the ends often; the plan's "2–52 weeks and 0–12 days" would add nothing
    here, since `make` reads one day and the suite must stay near a second (it runs in about 1.2 s).
24. **Size.** 1,007 product lines against 720 planned and the 1,000 at which a pull request is split. The
    count was not taken when the day editor's half was done, as the task asked: the two halves were written
    together (the row embeds the panel), and the first count was at the end. See "Code lines per file" for
    where the excess is and for the seam.

### Criteria → tests

Suites: `DayEditorPresentationTests` (DT), `SlotEditorPresentationTests` (ST), `DayEditorActionTests` (AT),
`DayEditorPresentationPropertyTests` (PP), `ProgramCopyTests` (CT), `FeatureProgramSourceTests` (SrcT),
`SlotResolvedLoadTests` in `LedgerDomainTests` (DomT).

| Criterion | Tests |
|---|---|
| 1 One input, one model | DT `seedDay_readsAsTheBrief`, `missingDay_isGone`, `header_backAndDone_closeTheDay`, `row_tap_opensAndCloses`; AT `slotEdit_applied_isTheOneDayEditingCall`, `edit_applied_isTheOneProgramEditingCall`, `edit_unknownDayOrSlot_changesNothing`, `stepperAction_carriesTheSteppedValue`, `closesPanel_isSetOnTheActionsThatCloseIt`; PP `taps_randomDay_leaveAValidProgram` |
| 2 The header and the meta line (behaviour 13) | DT `seedDay_readsAsTheBrief`, `meta_deloadWeek_countsThePrescribedSets`, `meta_dropSet_isCounted`, `header_rename_isOneEdit`, `noSlots_showsNoRow`, `oneSlot_offersOnlyRemove`, `weekIndex_outsideTheBlock_readsAsTheNearest` (7 cases) |
| 3 The rows (brief criteria 7, 10, 11; behaviours 7, 9, 19) | DT `subLine_linearDoubleFixedDropAndNoRest`, `subLine_rest_takesTheDomainsLabel` (5 cases), `row_speaksWhatIsDrawn`, `rows_kilograms_showLoadsAndStepsInKilograms`, `row_ownStepAndTheExercisesStartLoad`, `supersetHeader_countsAndNamesTheLastLetter`, `superset_ofThree_lettersAndRests`, `moveDown_soloAboveASuperset_passesTheWholeSuperset`, `moveDown_insideASuperset_swapsAndReletters`, `moveUp_firstOfASuperset_carriesTheSuperset`, `moves_atTheDaysEdges_areNotOffered`, `supersetWithNext_joinsTheNextExercise`, `breakOut_detachesTheExercise`, `supersetWithNext_beforeAnotherSuperset_mergesTheTwo`, `remove_firstOfASuperset_theNextMemberLeads`, `slotOfAMissingExercise_isListedAndRemovable` |
| 4 The open slot's fields (brief criteria 8, 9; behaviours 10, 11, 12) | ST `fields_linear_areFive`, `fields_double_areSix`, `fields_deloadWeek_showTheSlotsOwn`, `reps_raisedToTheTop_pushTheTop`, `topOfRange_loweredToReps_snapsAbove`, `sets_clampAtOneAndTwelve`, `rpe_stepsByHalves`, `rest_stepsByFifteenSeconds`, `startLoad_pounds_stepsAndFloorsAtZero`, `startLoad_kilograms_stepsByTheUnitsStep` (3 cases), `startLoad_offTheSteps_goesToTheNextMultiple`, `progression_chips_markTheSlotsOwn`, `progression_notes_areTheBriefs`, `progression_notes_kilograms`, `chooseDouble_widensTheRangeAndRelabels`, `leaveDouble_keepsTheTop`, `dropSet_turnsOnAndOff`; PP `controls_randomDay_allDoSomething` |
| 5 Every week's prescription (brief criterion 7) | ST `weekStrip_inclineDBPress_followsRuleTen`, `weekLine_inclineDBPress_followsRuleTen` (6 cases), `weekStrip_marksTheDeloadWeek`, `weekLine_deloadAndHeld`, `weekLine_deloadAfterAMiss_readsDeload`, `weekStrip_kilograms`, `weekStrip_fixed_staysAtTheStartLoad`, `weekStrip_followsTheBlockAndTheStartLoad`; PP `checkPanel` (one entry a week, the marks against the weeks and the misses) |
| 6 Delete day | DT `deleteDay_confirmation_namesTheDayAndItsWeeks`, `deleteDay_oneWeekAndNowhere`, `deleteDay_confirm_removesTheDay`, `deleteDay_theOnlyDay_isAllowed` |
| 7 Words | CT `dayEditor_plainTexts_areTheBriefs`, `dayEditor_writtenTexts_areTheNotes`, `equipment_namesEachKind`, `dayEditor_textsWithValues_areTheBriefs`, `loads_haveBothUnits`, `dayEditor_countedTexts_haveOneAndOther`; DT `locale_picksTheDigits`; `ModuleCopyTests` (`LedgerAppKitTests`) for the audit and the built bundle; the gate's string-catalog step |
| 8 No rule of its own | SrcT `storesAndPresentations_neverClamp` (now seen to read the Day editor's files); AT `stepperAction_carriesTheSteppedValue`; PP `checkPanel` (a move is offered exactly when the Domain's move changes the order), `checkRows` (the groups are `DayEditing.groups`); DomT all six tests |
| 9 Pure and total | SrcT `sources_neverReadTheClockOrTheCurrentCalendar`, `presentationsCopyAndModels_neverNameDouble`; DT `noSlots_showsNoRow`, `oneSlot_offersOnlyRemove`, `weekIndex_outsideTheBlock_readsAsTheNearest`, `openSlot_notInTheDay_isNoneOpen`, `noWeeks_doesNotTrap`, `firstSlotFlagged_isReadAsNormalForm`, `slotIDTwice_doesNotTrap`, `sameInput_givesTheSameModel`; PP `make_randomDay_keepsTheInvariants` |
| 10 Absolute where it can be | AT `isRelative_marksMoveAndRemove`, `edits_appliedTwice_onlyAMoveDiffers`, `rename_isTheRenameEditWithTheTypedText`; PP `actions_randomDay_nameTheDayAndAreSafeTwice` |

The plan's behaviour rows given to S6 and S7: 7 `remove_firstOfASuperset_theNextMemberLeads`; 9
`supersetWithNext_beforeAnotherSuperset_mergesTheTwo`; 10 `startLoad_offTheSteps_goesToTheNextMultiple`; 11
`sets_clampAtOneAndTwelve` and PP `controls_randomDay_allDoSomething`; 12 `leaveDouble_keepsTheTop`; 13
`meta_deloadWeek_countsThePrescribedSets`; 19 `slotOfAMissingExercise_isListedAndRemovable`. Row 8 ("Break
out" in the middle of three) is the Domain's and has its test there; here `superset_ofThree_lettersAndRests`
draws three. The plan's test names `subLine_linearDoubleFixedDropAndNoRest`, `weekStrip_marksTheDeloadWeek`
and `weekLine_deloadAndHeld` are kept.

The property suite, per seed (200 in the pull-request lane): two random inputs checked for a whole model (the
rows are the day's slots in order, in the Domain's groups; a header exactly over a group of two or more; only
a group's last member rests; at most one row open, the input's, with a panel exactly there; no empty text; a
move offered exactly when the Domain's move changes the order; details exactly when the exercise is stored;
five fields or six; one strip entry a week with the deload and held marks a reference written in the test
gives); every action's edit naming the day and a slot it holds, and every edit not marked relative applied
twice; every offered control seen to change the program, and every stepper tapped at whatever value it has,
the slot staying within the model's ranges; ten random taps applied as a store applies them, the program
rebuilt through `Program.init` after each and the day in normal form after each slot edit.

Checked by breaking the code (each change made, the Day editor's suites run, the change undone; the count is
of tests that then fail, a parameterised or seeded test counted once): a deload week counted with the slots'
own sets (2), "no rest" never written (7), a row showing the slot's own reps (1), a move always offered (8),
"Superset with next" naming the slot itself (7), the held mark dropped (3), the strip printed in pounds
whatever the unit (1), "−" stepping upward (7), the selected chip offering its own progression (5), the
confirmation counting weekdays (1), Remove leaving the panel open (4), the note taking the pound step in
kilograms (1).

### The catalog's new keys

From the brief's "Copy (exact)" paragraph (brief:60) unless another line is given. "Counted" keys have `one`
and `other`. A line the brief prints with " · " inside is its fragments (deviation 12); a line that prints a
load has a key for each unit ("Brief vs main" row 17).

| Key | Used for | From |
|---|---|---|
| `Program`, `Done` | back and done | brief:60 |
| `DAY %lld OF %lld` | the header's eyebrow | brief:60 |
| `SUPERSET` | a superset's header | brief:60 |
| `%lld exercises back to back` (counted), `rest after %@` | the header's note, joined | brief:60 ("%lld exercises back to back · rest after %@") |
| `%lld%@` | a row's index, "4A" or "4" | brief:60 (index "4A") |
| `Barbell`, `Dumbbell`, `Cable`, `Machine`, `Bodyweight` | the sub line's equipment | brief:60 (the library's chips; standards §7, a Domain value's name) |
| `+%@/wk`, `Reps %lld–%lld`, `Fixed` | the sub line's progression; `Fixed` is the chip too | brief:60 |
| `drop`, `RPE %@`, `%@ rest`, `no rest` | the sub line | brief:60 |
| `%lld×%lld` | a row's scheme | brief:60 |
| `%@ lb`, `%@ kg` | a row's load; the start load's value | brief:60 ("%@ lb"); row 17 |
| `+ Add exercise from library` | button | brief:60 |
| `Delete %@?`, `Delete`, `Cancel` | the confirmation | brief:60 |
| `It's scheduled in %lld weeks. Those days become rest.` (counted) | the confirmation's second line | brief:60; its `one` form is decision 6's |
| `HELD` | the eyebrow's mark | brief:60 (" · HELD") |
| `%lld × %lld @ %@ lb`, `… kg` | the week's line, before "RPE %@" | brief:60 |
| `W%lld %@`, `W%lld %@ (deload)` | a strip entry | brief:60 ("W1 185", "W8 240 (deload)") |
| `SETS`, `REPS`, `REP FLOOR`, `TOP OF RANGE`, `START LOAD`, `TARGET RPE` (and `REST`, already there) | the steppers' labels | brief:60 |
| `PROGRESSION`, `Linear`, `Double` | the progression's title and chips | brief:60 |
| `Adds %@ lb a week from %@ lb. A week with a missed set holds the load.`, `… kg …` | linear's note | brief:60 |
| `Adds a rep each week up to %lld, then +%@ lb back at %lld.`, `… kg …` | double's note | brief:60 |
| `Stays at %@ lb for the whole block.`, `… kg …` | fixed's note | brief:60 |
| `Drop set`, `One extra set at −15% after the last working set.`, `One extra set at −15%, straight after the last working set.` | the drop set | brief:60 |
| `Break out`, `Superset with next`, `Move up`, `Move down`, `Remove` | the slot's actions | brief:60 |

**Texts the brief does not give, written here (for Pete):**

| Key | Where it is seen or heard | Why this wording |
|---|---|---|
| `Delete day` | the button at the foot of the editor | decision 6 |
| `It's scheduled in %lld week. Those days become rest.` (the `one` form) | the confirmation for a day one week trains | decision 6 |
| `Day name` | the name field's placeholder and spoken label | the plan's VoiceOver tree ("a text field labelled 'Day name'") |
| `Kettlebell`, `Band` | the sub line of a kettlebell or band exercise | the Domain has seven kinds of equipment; the brief names five |
| `W%lld %@ (held)` | a strip entry for a week held after a miss, "W4 260 (held)" | parallel to the brief's "(deload)" (deviation 14) |
| `%@, %@` | VoiceOver: a row's label, "4A, Lat Pulldown" | the plan's tree |
| `Superset` | VoiceOver: a superset header's heading | the drawn "SUPERSET" in sentence case, as "Rest" is for "REST" |
| `Sets`, `Reps`, `Rep floor`, `Top of range`, `Start load`, `Target RPE` (and `Rest`, already there) | VoiceOver: each stepper's label; also the labels Pete's decision 1 draws in sentence case | decision 1 (A) and decision 6 ("Sets, 5") |
| `%lld exercise back to back` (the `one` form) | never shown: a superset has two members | the catalog rule asks for it |
| "Week 1 · No exercises yet" | the meta line of a day with no exercise | two existing keys joined (deviation 10) |

Not keys: a load, an RPE and a rest ("52.5", "8.5", "2:30"), which the Domain prints; a stepper's whole
number, formatted in the injected locale; names and tags, which are data.

### Code lines per file

Non-blank, non-comment lines, counted once, at the end (deviation 24).

| File | Planned | Lines |
|---|---|---|
| `FeatureProgram/DayEditor/DayEditorInput.swift` | (in the model's) | 11 |
| `DayEditorModel.swift` | 80 | 65 |
| `SlotEditorModel.swift` | 80 | 66 |
| `DayEditorAction.swift` (actions and edits) | not planned | 61 |
| `DayEditorPresentation.swift` | 130 | 118 |
| `DayEditorPresentation+Rows.swift` | | 91 |
| `SlotEditorPresentation.swift` | 110 | 91 |
| `SlotEditorPresentation+Fields.swift` | | 80 |
| `SlotEditorPresentation+Preview.swift` | 60 | 54 |
| `ProgramCopy+DayEditor.swift` | 110 | 160 |
| `ProgramCopy+SlotEditor.swift` | 150 | 193 |
| **The folder** | **720** | **990** |
| `FeatureProgram/ProgramCopy.swift` (three comments, two lookups now over five lines) | | 115 → 123 |
| `FeatureProgram/ProgramPresentation.swift` (`nearestPlace`) | | 72 → 73 |
| `FeatureProgram/ProgramPresentation+Days.swift` (`setCount`) | | 54 → 54 |
| `LedgerDomain/Model/Slot.swift` (the two functions) | | 108 → 116 |
| `LedgerDomain/Rules/ProgressionRules.swift`, `Programs/DayEditing+Fields.swift` | | unchanged in count |
| **The slice** | **about 720** | **1,007** |

40 % over the plan and seven lines over the 1,000 at which a pull request is split. Where the excess is: the
copy (353 against 260: 68 keys, most with a translator's comment, and eight per-unit pairs each a `switch`),
the action file (61, not in the plan, the same addition S5 made), and the presentations (434 against 300:
the rows and the fields each took a file). Tests: 1,619 lines in fourteen files, not counted.

If it is to be two pull requests, the seam is the one the task names: **the week strip and the shown week's
line** (`SlotEditorPresentation+Preview.swift`, 54; `WeekLine`, `WeekStrip` and `Entry` in
`SlotEditorModel.swift`, 16; the five lookups under "The prescription, week by week" in
`ProgramCopy+SlotEditor.swift`, 51; `Details.week` and `.strip` and their two lines in `details(of:)`), about
125 lines with `SlotEditorPresentationTests+Preview.swift`, and **the delete confirmation** (`deleteDay` in
`DayEditorPresentation.swift`, `DeleteDay` and `Confirmation` in the model, five lookups), about 60. Without
both the slice is about 820. Nothing else reads them; S10 and S11 need both before they draw. Not split
here: the orchestrator's call.

### Coverage

Host, `swift test --enable-code-coverage`, read with `llvm-cov export -summary-only` on each test bundle:

| File | Lines | Regions |
|---|---|---|
| `DayEditor/DayEditorAction.swift` | 42 / 42 | 27 / 27 |
| `DayEditor/DayEditorModel.swift` | 3 / 3 | 1 / 1 |
| `DayEditor/DayEditorPresentation.swift` | 113 / 113 | 24 / 24 |
| `DayEditor/DayEditorPresentation+Rows.swift` | 117 / 117 | 32 / 32 |
| `DayEditor/SlotEditorModel.swift` | 6 / 6 | 2 / 2 |
| `DayEditor/SlotEditorPresentation.swift` | 91 / 91 | 25 / 25 |
| `DayEditor/SlotEditorPresentation+Fields.swift` | 71 / 71 | 17 / 17 |
| `DayEditor/SlotEditorPresentation+Preview.swift` | 69 / 69 | 15 / 15 |
| `DayEditor/ProgramCopy+DayEditor.swift`, `ProgramCopy+SlotEditor.swift` | 345 / 345 | 90 / 90 |
| **The new folder** | **857 / 857, 100 %** | **233 / 233** |
| The module's other files (S5's) | 449 / 449 | 133 / 133 |
| `LedgerDomain/Model/Slot.swift` (from `LedgerDomainTests`) | 74 / 74 | 43 / 43 |
| `LedgerDomain/Rules/ProgressionRules.swift`, `Programs/DayEditing+Fields.swift` (the same) | 40 / 40, 49 / 49 | 11 / 11, 31 / 31 |

`DayEditorInput.swift` holds no executable line. The simulator's figure, which is the gate's, was not read.

### Open questions, each with a recommendation

1. **Is a removal relative?** (deviation 5). Marked so, as specified; applied twice it gives what one
   application gives. *Recommendation:* keep the mark and let S14 treat every queued edit alike (each reaches
   the stored program once); nothing should ever rely on a removal being unsafe to repeat. If the mark is to
   mean only "differs when applied twice", it is one line (`DayEditorAction.swift:70`) and two tests.
2. **A Domain function for a day's sets in a week** (deviation 11). The smallest addition that would do:
   `TimeEstimate.setCount(day:prescriptions:) -> Int` beside `minutes`, which already works the same sum out
   inside. *Recommendation:* add it with F09's next Domain change (Today counts a session's sets too) and
   make `ProgramPresentation.setCount` call it; not done here because the task allows this slice two
   functions on `Slot` and nothing else in the Domain.
3. **Size** (deviation 24): one pull request of 1,007 lines, or two at the seam above. *Recommendation:* one.
   The two halves are tested through each other (a row embeds its panel), the overrun is copy, and a second
   cycle for 185 lines costs more than it buys.
4. **"REST", "Rest" and "Fixed" each serve two meanings** (deviation 18). Nothing breaks while English alone
   ships. *Recommendation:* ask Pete with S11's VoiceOver table whether the stepper should read "REST TIME"
   or stay "REST"; a second English text is what makes a second key possible.
5. **The strip to VoiceOver.** `WeekStrip.text` is drawn text ("W1 50 · W2 50 …"); VoiceOver will read "W
   one fifty". The plan's tree has "the loads of every week as one text element" and gives no wording.
   *Recommendation:* S11's VoiceOver pass decides; a spoken form ("Week 1, 50 lb") is three keys and one
   field of `Entry`.
6. **"(held)" in the strip** (deviation 14) is new wording. *Recommendation:* show Pete with S11's
   screenshots; dropping the mark from the strip (the eyebrow still says HELD on the shown week) is one
   lookup and one test.
7. **A slot whose exercise is not stored cannot be edited** (deviation 9), only moved and removed. Nothing
   deletes an exercise in M1. *Recommendation:* leave it; revisit when F12 can delete a custom exercise.
8. **Whether the model should say what "+ Add exercise from library" hands the library** (the day's
   exercises, for "already in this day"). Not built: the library is S8's. *Recommendation:* S8's input takes
   the program and the day's id, as this one does.

### Inputs for the views (S10, S11)

The tables under "The model and the actions" are the contract. Beyond them:

- A view takes a part of the model and `(DayEditorAction) -> Void`; it builds no action but the name
  field's, `DayEditorAction.rename(text, day: content.id)`, with the text as typed. The field is bound to a
  draft the store keeps, seeded from `header.name`, never to `header.name` itself (the stored name is the
  cleaned one). `header.nameLabel` is its placeholder and its spoken label. `header.tag` is drawn, not
  editable.
- `DayEditorModel.dayIsGone` has nothing to draw: the screen is given `Content` only.
- Identity for `ForEach`: `Group` (the id of its first row), `Row` (the slot's id), `Field` (its kind),
  `Chip` (its progression); the strip's entries by their place.
- A superset is one `Group`: its `header`, when not nil, is drawn once above the rows, and the rows share
  one visual block. A view never reads a flag to find the groups, and never works out a letter.
- A row is a button with `action`; `isOpen` picks the caret and the accent of `scheme`; `load == nil` draws
  no load. `panel` is not nil exactly when `isOpen`; the panel is drawn from it and from nothing else.
- In the panel, an absent control is not drawn: `details == nil` (no week line, fields, progression, drop
  set or strip), an empty `supersetActions`, a nil `moveUp` or `moveDown`. A chip whose `action` is nil is
  the selected one: drawn selected, not a button.
- A stepper: `label` and `value` drawn (or `spokenLabel` drawn, by Pete's decision 1); to VoiceOver one
  adjustable element with `spokenLabel` and `value`, decrement and increment sending the two actions. Both
  are always there; at a limit the value simply stays.
- Accent: `WeekLine.isDeload` or `isHeld` (the eyebrow), `Entry.isDeload`, `isHeld`, `isShown`, `DropSet.isOn`
  and `Row.isOpen` are the only facts that pick a colour. `week.eyebrow` and `strip.text` are whole strings:
  a view that colours a part must not split one, and asks for a field instead. The strip can be drawn as
  `text` or entry by entry (`entries[i].text`), never joined by the view.
- VoiceOver, as the plan's tree: `header.position` a heading; a superset header a heading, label
  `spokenLabel`, value `note`; a row label `spokenLabel`, value `spokenValue`, with the expanded or collapsed
  state from `isOpen`; the drop set a switch, `title`, `isOn`, hint `note`; the chips a radio group.
- "Delete day": the button presents a confirmation from `deleteDay.confirmation` (`title`, `message` when
  not nil, a destructive button `confirm`, `cancel`). Whether it is showing is the view's own flag;
  "Cancel" sends nothing.
- Previews and snapshots build models with `DayEditorPresentation.make` from `Fixtures.seedProgram()`:
  Upper A with `openSlot` nil (all closed), the bench press open (linear), Incline DB Press open (double),
  Upper B's curl (drop set on), any day at `weekIndex: 7` (the deload).

### Inputs for the stores (S14)

- **Fills:** `program` = the stored program with the waiting edits applied in order; `day` = the id of the
  route; `exercises` = `observeAll()` keyed by id; `settings`; `weekIndex` = the route's (`ProgramRoute.day(_,
  weekIndex:)`); `openSlot` (its own state, nil at first); `locale` from the dependencies.
- **Applies an action** exactly as the action table says; `Tests/FeatureProgramTests/Support/DayEditorTesting.swift`
  (`DayScreen.tap`) is that table as twelve lines. `.open(id)` sets the open slot; `.edit(edit,
  closesPanel:)` queues the edit and, when the flag is set, clears the open slot; `.openLibrary` presents the
  sheet; `.route` is emitted.
- **Saves:** `programs.update(id) { program in edits.reduce(program) { $1.applied(to: $0) } }`.
  `DayEditorEdit` is `Sendable`, holds only values and never throws. With the builder's edits in the same
  queue the element type is the store's choice (an enum of the two, or two sessions); the builder's
  `applied(to:)` throws, this one does not.
- **A stepper's value is worked out when the model is built**, from the slot on screen, and the edit
  carries it: the store does not call `DayEditing.stepped`. Two quick taps on "+" therefore need the model
  rebuilt between them (the second tap's edit comes from the model drawn after the first), which a store
  that applies an edit to its program on screen before the next intent gives for free. A store that queued
  two taps from one model would set the same value twice.
- **Relative edits**: `edit.isRelative` is true for a move and a removal. Each queued edit reaches the
  stored program exactly once; after a failed or cancelled `update` the waiting edits are dropped and the
  screen is redrawn from the stored program (the brief's "For S13 and S14").
- **The day is gone** (`make` returns `.dayIsGone`): emit `ProgramRoute.closeDay`, once. This is how
  "Delete" ends too: its action is the edit alone, and the next model says the day is gone. Whether the
  route waits for the save is S14's, as for the builder's `.addDay`.
- **The open slot** needs no repair: an id the day no longer holds is read as none open. A move keeps the
  slot's id, so the moved exercise stays open.
- **The name**: keep the draft, send `DayEditorAction.rename(text, day:)` as it is typed; do not write
  `header.name` back into the field while it has focus.
- **The library's picks** need one more case on `DayEditorEdit` (`.slot(.add([Slot]), day:)` around
  `DayEditing.addSlots`), with the slots built once by `DayEditing.newSlot` at the tap (S1's "Inputs").
- **Deleting a day whose workout runs** is allowed and needs nothing here (Pete's decision 4; orchestrator
  ruling 4 of 2026-10-05 for F10).

### The runs

- Host, `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'FeatureProgramTests|LedgerDomainTests|ModuleCopyTests'`: exit 0. `FeatureProgramTests`: 199 tests in 16
  suites passed (109 before; the tester's S5 suites among them, none edited). `LedgerDomainTests`: 1,218 tests
  in 186 suites passed (1,212 before, the six of `SlotResolvedLoadTests` new, no existing test edited).
  `ModuleCopyTests`: 6 tests passed, with no exemption for `FeatureProgram`. The Day editor's property suite
  alone runs in about 1.2 s at 200 seeds.
- `scripts/check.sh --lint-only`: exit 0 ("check.sh (--lint-only) OK"), on the final sources.
- Simulator, once, through the lock (iPhone 17, iOS 27.0, a cold `.derivedData` in the worktree, as
  `check.sh` step 3 does it): `xcodebuild build-for-testing` of scheme `Ledger`, plan `PR`: exit 0, the
  result bundle "succeeded", 0 errors. Its log prints, fifteen times, "error: the following command failed
  with exit code 0 but produced no further output" beside compile steps of `LedgerPersistenceTests`, a target
  this slice does not touch; the build went on and succeeded (another worktree's gate had just released the
  simulators; not looked into further). Then `scripts/check-string-catalogs.sh`: exit 0, "string catalog
  matches the code: LedgerKit/Sources/FeatureProgram/Resources/Localizable.xcstrings (keys: 101)", and
  `FeatureToday`'s (55) and `LedgerAppKit`'s (7). Then `test-without-building -only-testing:FeatureProgramTests
  -only-testing:LedgerAppKitTests`: exit 0, 435 tests passed, none failed or skipped (`FeatureProgramTests`
  199, `LedgerAppKitTests` 236). The result bundles were read and deleted. No product or test source was
  edited after that build.
- **Not run:** the full gate, the watchOS build, `LedgerDomainTests` and every other target on the simulator,
  the coverage gate script (it reads the full PR result bundle), the nightly lane's 2,000 seeds, and on the
  host any target but the three named.

## Slice S6 — fix round 1 (G1 implementer, 2026-10-08)

On 90fadb4 (the slice 63f397f, the tester's files, findings and the review). Not committed. The brief's "Plan
amendments — slice S6 after round 1" (criteria 11 to 16) is the specification of this round. Written before
the long runs; "The runs" was filled in after them.

### What changed, per item

Paths under `LedgerKit/`.

| Item | Change |
|---|---|
| **Criterion 11** (review S-1): a superset shows the rest the workout takes | `Sources/LedgerDomain/Rules/SupersetRounds.swift` gains `groupRest(of rests: [RestDuration]) -> RestDuration` (the longest; no rests gives the default). The Domain had the rule twice and for no slot: `groupRest(block:exercises:)` over a workout's exercises (what `WorkoutEngine+Reduce.swift:85` rests for) and `rests.max()` inside `TimeEstimate.minutes`. Both now call the new function, so the workout, the minutes and the row read one rule. In the feature, `DayEditorPresentation+Rows.swift`: `Place.isLast` became `Place.rest`, the group's rest for the last member and nil for the others, and `subLine` prints it or "no rest". The seed's Upper A reads "Cable · Reps 15–17 · RPE 9 · 1:15 rest" on 4B; Lower A's calf raise reads "1:30 rest". A member's own REST stepper still shows its own value. Tests: `DayEditorPresentationTests.superset_lastRow_showsTheGroupsRest` (new; the row follows a step of either member's rest), `subLine_linearDoubleFixedDropAndNoRest` (the two expected lines changed); `SupersetRoundsTests.groupRestOfRests_isTheLongest`. |
| **Criterion 12** (review S-3): set counts from the Domain | `Sources/LedgerDomain/Rules/TimeEstimate.swift` gains `setCount(day:prescriptions:)` (every slot's prescribed sets, or its own, and its drop sets) and `setCount(days:)` (several days as written, for the builder's "58 sets a week"). `minutes` is written with the first: work is `setCount × 42 s`, and the rests are summed per group as before. `ProgramPresentation.setCount` is gone, with the parameter round 0 added; `ProgramPresentation+Days.swift` and `DayEditorPresentation.swift` call the Domain and sum nothing. Tests: `TimeEstimateTests.setCount_day_countsSetsAndDropSets`, `setCount_prescriptions_overrideTheSlotsSets`, `setCount_days_addsTheDaysUp`; every existing `minutes` test passes untouched. |
| **Criterion 13** (review S-2): no queued edit is safe to send twice | The comment on `DayEditorEdit.isRelative` (`DayEditor/DayEditorAction.swift`) now says the mark is about one edit drawn again over a program that already has it, not about a queue, and that every queued edit reaches the stored program exactly once. Test: `DayEditorActionTests.queue_replayed_givesAnotherProgram` ("Superset with next" on the second of three, then "Remove" on it: replayed over its own result, the join finds another slot before the third and joins it there). Run, not only read: the reviewer's example holds. |
| **Criterion 14** (F11-S6-4): "Rest" the day and "rest" the pause | **Not built, by the orchestrator's ruling during the round (option B).** Standards §7 makes the key the English text and the catalog check refuses a plain key whose English text is not its key (`Sources/LedgerTestSupport/Localization/StringCatalog.swift`, pinned at `Tests/LedgerAppKitTests/StringCatalogTests.swift:96`), so two keys cannot hold the same English. The one key "REST" and the one key "Rest" stay, each with the comment that names both uses; the brief's "REST" label is unchanged. Open below. |
| **Criterion 15** | Nothing changed. |
| **Criterion 16** (review S-4): no whole model in an expectation | The eight places: `DayEditorPresentationTests+Total.swift` (four `== .dayIsGone`, now `model.isGone`, a flag in `Support/DayEditorTesting.swift`; two `details == nil`, now `hasDetails`), `DayEditorPresentationPropertyTests.swift` (`model.isGone`; `isDeleted`). |

**The nits.**

| Nit | Done or declined |
|---|---|
| N-1 a removal is marked relative and is not | Kept, as criterion 15 rules. The comment on `SlotEdit` now says the mark follows the criterion's list, not the definition. |
| N-2 two comments promise more than the model gives | Done: both say "but a stepper, which offers both directions at its limit". |
| N-3 stale file name in a test comment | Done. |
| N-4 the source test does not name the steps' file | Done: `SlotEditorPresentation+Fields.swift` is in the list. |
| N-5 `Row.hasDropSet` has no stated use | Kept, with its use stated in its comment (a view that marks such a row; it picks no colour). The tester's screen reads it, so removing it is not this round's. |
| N-6 one-word keys without a comment | Done, on the lines named: the seven kinds of equipment, "+ Add exercise from library", "Cancel", "Superset with next", "Move up", "Move down". No line added. |
| N-7 a program with no weeks is drawn as if every exercise were missing | Declined, as the reviewer allows: `Program.init` refuses such a program, and splitting the guard is a branch for a state only a test reaches. |
| N-8 "HELD" on a fixed slot | Not changed: the flag is the Domain's and spec §7.2's. For Pete with F24. |
| N-9 every week's prescription for every slot | Declined: far inside the budget; S14's timing test decides. |
| N-10 two test names lack their expectation | Done: `weekStrip_kilograms_printsKilogramsByTheUnitsSteps`, `progression_notes_kilograms_nameKilogramsAndTheUnitsStep`. |
| N-11 `Group.id` is optional | Declined: a stored id needs a branch no test can reach (round 0's deviation 20). |

### Catalog texts

No key added, removed or reworded: 101 keys. Twelve keys gained a translator's comment (N-6): "Barbell"
("Equipment: a barbell"), "Dumbbell" ("Equipment: dumbbells"), "Cable" ("Equipment: a cable machine"),
"Machine" ("Equipment: a weight machine"), "Bodyweight" ("Equipment: the lifter's own body"), "Kettlebell"
("Equipment: a kettlebell"), "Band" ("Equipment: a resistance band"), "+ Add exercise from library" ("Button
under a day's exercises"), "Cancel" ("Dismisses the confirmation; the day stays"), "Superset with next"
("Joins the next exercise to this one"), "Move up" and "Move down" ("Carries an exercise towards the top of
its day", "… the foot …").

**What a lifter reads differently:** the last row of a superset shows the longest rest of its members, where
round 0 (and the prototype) showed that row's own. Listed for Pete in the brief.

### The tester's pins that now fail, for the tester

Seven tests in `Tests/FeatureProgramTests/Adversarial/`, all because they pin the last member's own rest
(criterion 11). No file of the tester's was edited; all compile. No other test of the two targets fails.

| Test | It expects | Now |
|---|---|---|
| `DayEditorSeedAdversarialTests.seed_upperA_rowsReadAsTheSpec` (`:32`) | 4B "Cable · Reps 15–17 · RPE 9 · 1 min rest" | "… · 1:15 rest" (Lat Pulldown's 75 s is the longer) |
| `DayEditorSeedAdversarialTests.seed_progressionAndDropSet_readAsTheBrief` (`:137`) | Lower A's calf raise "Machine · Fixed · RPE 9 · 1 min rest" | "… · 1:30 rest" (Leg Press's 90 s) |
| `DayEditorTotalityAdversarialTests.slotOfAMissingExercise_isListedUnderADashAndRemovable` (`:105`) | the third row "RPE 8 · 1:30 rest" | "RPE 8 · 2:30 rest": it closes a superset whose other member rests 2:30 |
| `DayEditorSeedAdversarialTests.seed_everyDayWeekUnitAndOpenSlot_agreesWithTheTestersScreen` (`:192`) | the tester's screen (`DayEditorAdversarialScreen.swift:130`): the last member's `slot.rest.label` | the group's rest, `SupersetRounds.groupRest(of:)` over the members' rests |
| `DayEditorModelAdversarialTests.seededDays_outsideADeload_agreeWithTheTestersScreen` (`:39`) | the same screen | the same |
| `DayEditorModelAdversarialTests.seededDays_inADeloadWeek_agreeWithTheTestersScreen` (`:63`) | the same screen | the same |
| `DayEditorActionsAdversarialTests.everyAction_appliedAndRedrawn_isTheTestersScreen` (`:45`) | the same screen | the same |

### Product lines now

| File | Round 0 | Now |
|---|---|---|
| `FeatureProgram/DayEditor/DayEditorPresentation+Rows.swift` | 91 | 92 |
| The folder's ten other files | 899 | 899 (comments and one-line lookups changed; no line added) |
| `FeatureProgram/ProgramPresentation+Days.swift` | 54 | 51 (`setCount` gone) |
| `FeatureProgram/ProgramCopy.swift`, `ProgramPresentation.swift` | 123, 73 | unchanged |
| `LedgerDomain/Model/Slot.swift` | 116 | unchanged |
| `LedgerDomain/Rules/TimeEstimate.swift` | 18 | 23 |
| `LedgerDomain/Rules/SupersetRounds.swift` | 67 | 70 |
| **The slice** (against 7e15f61) | **1,007** | **1,013** |

Counted before the round (1,007) and after (1,013): six lines, under the 1,050 at which the seam is taken.

### Open, with a recommendation

- **Two uses of one English text** (criterion 14). The localization rule has no way to tell them apart: a
  standards matter, not this slice's. *Recommendation:* before the first translation, either Pete gives the
  pause a second English text, or §7 and its three checks learn a key that is not its text (a lookup with a
  default value); "REST" and "Rest" here are the first case, "Deload" in the builder the second (S5's N-5).
- **For the stores (S14), changed by this round:** the mark `isRelative` says nothing about a queue. Sent
  edits are dropped before the screen is redrawn from the stored program; no queue is ever applied to a
  program that already holds it (`queue_replayed_givesAnotherProgram` is the example).
- **For the views (S10):** a superset's last row shows the group's rest, and that member's REST stepper its
  own; when the two differ the row does not change with the stepper until it passes the longest. If that
  reads as a bug on a screenshot, the header's note ("rest after B") is where a word could go; Pete's.

### The runs

- Host, `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'FeatureProgramTests|LedgerDomainTests|ModuleCopyTests'`: exit 1, by the seven pins alone.
  `LedgerDomainTests`: 1,222 tests in 186 suites passed (1,218 before; the four new ones). `ModuleCopyTests`:
  6 passed. `FeatureProgramTests`: 254 tests in 24 suites, 247 passed, 7 failed: exactly the seven of the
  table above. The implementer's own suites, run without the tester's (`--skip Adversarial`): 147 tests in 9
  suites passed.
- `scripts/check.sh --lint-only`: exit 0, on the final sources.
- Coverage, host, `llvm-cov export -summary-only` on each bundle: `FeatureProgram` 1,305 / 1,305 lines from
  the implementer's suites alone, the Day editor's folder complete in lines and regions.
  `LedgerDomain/Model/Slot.swift` 74 / 74. `Rules/TimeEstimate.swift` 36 / 38 and `Rules/SupersetRounds.swift`
  89 / 90: the three lines are the `?? 0` fallbacks of a `max()` over a group's members (`TimeEstimate.swift:23`,
  twice; `SupersetRounds.swift:99`), which no group reaches because a group is never empty. The first two
  fallbacks stood in `minutes` before this round (the same expressions, on other lines; their coverage was
  not measured then); the third is untouched.
- Simulator, once, through the lock (iPhone 17, iOS 27.0, the worktree's `.derivedData`): `build-for-testing`
  exit 0; `scripts/check-string-catalogs.sh` exit 0, "string catalog matches the code:
  …/FeatureProgram/Resources/Localizable.xcstrings (keys: 101)", `FeatureToday`'s (55), `LedgerAppKit`'s (7);
  `test-without-building` of `FeatureProgramTests` and `LedgerAppKitTests`: exit 65, 490 tests, 483 passed,
  7 failed: `LedgerAppKitTests` 236 passed; `FeatureProgramTests` 254 with the same seven failing, by name.
  The result bundles were read and deleted. No source was edited after that build.
- **Not run:** the full gate, the watchOS build, `LedgerDomainTests`, `FeatureTodayTests` and every other
  target on the simulator, the coverage gate script, the nightly seeds, and on the host any target but the
  three named. `FeatureToday` calls `TimeEstimate.minutes`, whose body changed: its host tests were run for
  that reason, `--filter FeatureTodayTests`, 216 tests in 19 suites passed.

## Slice S8 — the form controls and the library's presentation (G1 implementer, 2026-10-08)

Branch `feat/F11-s8-controls-library`, on the specification commit `48794bd`. The plan's S4 and S8 as one
slice; the brief's "Plan amendments — slice S8" (criteria 1 to 13) is the specification. Committed by the
implementer in three commits (the library's presentation, the controls, these notes). "The runs" was filled
in after the runs; nothing else of the tree changed after them.

### What landed

Paths under `LedgerKit/`.

**Part one, `Sources/LedgerDesign/`.**

- `Components/StepperField.swift`: `StepperField(_ label:, value:, spokenValue: = nil, onDecrement:,
  onIncrement:)`, each closure optional; the private `StepButton`; `StepperFieldGallery`.
- `Components/LedgerToggleStyle.swift`: `LedgerToggleStyle`, `ToggleStyle.ledger`; the private `LedgerToggle`
  and `LedgerToggleTrack`; `LedgerToggleLook` (the switch's colours, internal, read by the contrast test);
  `LedgerToggleGallery`.
- `Components/WrapLayout.swift`: `WrapLayout(spacing:lineSpacing:)`, a `Layout`; its arithmetic is the
  internal `arrangement(of:in:)`, which both entry points call; `WrapLayoutGallery`.
- `Components/Components+Previews.swift`: three cases of `DesignPreview` and their `#Preview`s.
  `Gallery/DesignGallery.swift`: three sections, appended last.
- Tests, in `Tests/LedgerDesignTests/`: new `StepperFieldTests.swift` (8 tests),
  `LedgerToggleStyleTests.swift` (6), `WrapLayoutTests.swift` (9 of the arithmetic, which also run on the
  host, and 5 drawn), `AccessibilityTreeFormTables.swift` (19 rows of `AccessibilityTreeTests`' table).
  Extended: `ComponentSnapshotTests.swift` (the suite `FormControlSnapshots`, 7 tests, 23 references),
  `ComponentAccessibilityTests.swift` (3 tests, each at two sizes), `AccessibilityTreeTests.swift` (the table
  gains `forms`), `DesignGalleryTests.swift` (the three names). `PreviewTests` needed no edit: it reads the
  registry.
- References: 23 new files in `__Snapshots__/ComponentSnapshotTests/` (each control at the six cells; the
  layout right to left; the three controls together under Increase Contrast in both themes, pressed, and at
  accessibility5). One existing reference recorded again: the gallery's (see "The gallery's reference").

**Part two, `Sources/FeatureProgram/`.**

- `Picker/` (new folder): `ExercisePickerInput.swift`, `ExercisePickerModel.swift`,
  `ExercisePickerAction.swift`, `ExercisePickerPresentation.swift`, `ProgramCopy+Picker.swift`.
- `DayEditor/DayEditorAction.swift`: `SlotEdit.add([Slot])`, applied by `DayEditing.addSlots`; not relative.
- `DayEditor/ProgramCopy+DayEditor.swift` and the catalog: the comment of "Cancel" names its second use.
- `Resources/Localizable.xcstrings`: 25 new keys (table below), one of them counted; 125 in all.
- Tests, in `Tests/FeatureProgramTests/`: new `ExercisePickerPresentationTests.swift` with `+Chips` and
  `+Picks` (26 tests), `ExercisePickerPresentationPropertyTests.swift` with `+Checks` (4 seeded tests),
  `ProgramCopyTests+Picker.swift` (4), `Support/ExercisePickerTesting.swift` (fixtures, and `PickerScreen`,
  which applies an action exactly as `ExercisePickerAction`'s comments say a store does). Edited:
  `FeatureProgramSourceTests.swift` (the library's three files are seen to be among those the source checks
  read), `Support/DayEditorTesting.swift` (`SlotEdit.slot` is optional: `.add` names no slot).

No view of a screen, no store, no change to `LedgerAppKit`, the project file, a test plan or the set row.

### The models and the actions

`ExercisePickerPresentation.make(_ input: ExercisePickerInput) -> ExercisePickerModel`, `nonisolated`,
internal to the module.

**The input:** `exercises: [Exercise]` (the stored ones, any order); `dayExercises: Set<ExerciseID>`; `query`;
`muscle: ExerciseSearch.MuscleFilter?` and `equipment: Equipment?` (nil is "All"); `picks: [ExerciseID]` in
the order picked; `locale`.

**The model** (`Equatable`, every string final):

| Part | Fields |
|---|---|
| `title`, `cancel` | "Exercise library"; "Cancel" with `.cancel` |
| `search` | `placeholder` "Search exercises" (also the spoken label), `query` (the input's) |
| `muscles`, `equipment` | `spokenLabel` "Muscle" / "Equipment"; `chips`: `id` (place, 0 is "All"), `title`, `spokenLabel` "Muscle: Chest", `isSelected`, `action` |
| `content` | `.rows([Row])` (never empty) or `.nothingMatches(Empty)`: `message` "Nothing matches that filter.", `clear` "Clear filters" with `.clearFilters` |
| `Row` | `id` (the exercise's), `name`, `detail` "Machine · Back", `inDayMark` "already in this day" or nil, `line` (the two joined), `isPicked`, `pickMark` "2" or nil, `spokenLabel` (the name), `spokenValue` (the line), `action` |
| `foot` | `title` "Select exercises to add" / "Add 1 exercise" / "Add 3 exercises"; `action` `.add(ids)` or nil (disabled) |

**The actions** (`ExercisePickerAction`, `Hashable`, `Sendable`; each says what becomes true):

| Case | What the store does |
|---|---|
| `.setQuery(String)` | The query is this text. A view sends it through `ExercisePickerAction.search(_:)`. |
| `.setMuscle(MuscleFilter?)`, `.setEquipment(Equipment?)` | The chip chosen is this one. |
| `.setPicked(Bool, exercise:)` | True: the exercise goes to the end of the picks unless it is among them. False: it leaves them. |
| `.clearFilters` | The query is emptied and both chips are "All". The picks stay. |
| `.add([ExerciseID])` | For each id in order: draw a `SlotID`, build a slot with `DayEditing.newSlot` (the settings' units and default rest); queue the Day editor's `.edit(.slot(.add(slots), day:))`; empty the query and the picks, keep the chips, close the sheet. |
| `.cancel` | Close the sheet, add nothing; empty the query and the picks, keep the chips (the prototype closes the same way for both, `Ledger.dc.html:1395`, `:1427`). |

### Decisions and deviations

1. **`StepperField` takes two optional closures, not `onStep: (Direction) -> Void`** as "Inputs", S4, sketched
   it. Criterion 1 asks for one closure per step and for a step that can be switched off; an absent closure
   is the switch, so there is no flag that could disagree with the closure, and S6's field model
   (`decrement`, `increment`) maps onto it one to one.
2. **How a switched-off step is spoken.** VoiceOver has no "this direction is off" for an adjustable element.
   The swipe towards the step does nothing, so VoiceOver repeats the value, which is how a system stepper at
   its limit sounds; with both steps off, or the field disabled, the element is dimmed (`.notEnabled`).
   Nothing more is said, because the control looks up no text. Open question 1.
3. **Behaviour 11 against criterion 1.** S6's model offers both directions at a limit (the plan's behaviour
   11), so the Day editor's steppers never switch a step off; the control can, for whoever wants it
   (Settings, or S11 if the model changes).
4. **The stepper's buttons are round**, 44 pt, outlined, as `IconPillButton` is; the prototype's are squares
   of 12 pt corners in the old light design. The label is the `label` role in muted ink (decision 1: "the
   small grey label style"), the value `numeralM`.
5. **The toggle.** On: a track filled with ink and a knob of the ground's colour. Off: an outlined track
   (`hairlineStrong`) and a knob of muted ink. Disabled: fainter steps of the same inks. The prototype's
   52 × 32 pt track and 26 pt knob are kept and do not grow with the text size. The whole row is the tap
   target. To VoiceOver the style is represented by a system `Toggle` with `.switch` and the same label and
   binding (`accessibilityRepresentation`), so the label, the value ("0", "1"), the traits and the
   double-tap are SwiftUI's own; `LedgerToggleStyleTests.toggle_accessibility_isSwiftUIsSwitch` compares the
   two.
6. **`WrapLayout` mirrors nothing itself**: SwiftUI mirrors a layout's placements under a right-to-left
   layout direction (`WrapLayoutRenderingTests.rightToLeft_runsFromTheRight`, and a reference). Children of a
   row are centred on the row's height. A child wider than the row is asked again for its size at the row's
   width, so a pill whose title wraps reports the height it then needs.
7. **A narrow pill stands in the middle of its 44 pt target**, so a short first chip ("All") starts a few
   points inside the row's edge; that is `PillButton`'s own behaviour (`flush:` exists for it) and is left to
   S12, which draws the chips.
8. **The gallery sections come last**, after the watch components, so that the pages above stay where they
   were (see "The gallery's reference").
9. **The input holds the day's exercise ids**, not the program and the day's id as S6's open question 8
   recommended: criterion 6 lists "the exercises already in the day", and the sheet reads nothing else of the
   program.
10. **Equipment that has no chip is read as "All"** (an input holding `.kettlebell` or `.band`): otherwise the
    list would be narrowed with no chip selected. One chip is selected in each row, always.
11. **A row's muscle is the exercise's primary muscle group**, eleven names ("Barbell · Quads"), not the
    chip it falls under ("Legs"): the Domain's groups are finer than the chips (decision #12), and core,
    which has no chip, needs a word anyway.
12. **The chips' lists.** Equipment: `ExercisePickerPresentation.equipmentChips`, five entries; "Kettlebell"
    and "Band" are two more entries there and nothing else (their names are in the catalog since S6).
    Muscles: `ExerciseSearch.MuscleFilter.allCases`, the Domain's list; "Core" is one more case there, with
    its `groups`, and one more line in `ProgramCopy.muscleFilter` (the compiler asks for it). So decision A is
    "three more entries" in the sense of criterion 7 for equipment, and one Domain case for the muscle.
13. **The selected chip carries its action too.** Criterion 7 says each chip is an action that names the
    filter it sets; the selected one's changes nothing. (S6's selected progression chip has none; there the
    criterion asked that nothing be offered that does nothing.)
14. **Picked is said by the selected state, not by a word.** A row's `spokenValue` is its line; the view
    sets the selected trait from `isPicked`, as `PillButton` does for a filled pill, and VoiceOver says
    "selected" in the system's words. Criterion 12 lists "a row with its line and whether it is picked" among
    the spoken texts; no text was written for it. Open question 2.
15. **A pick's place is a string** (`pickMark`, "2"), formatted in the injected locale as S6's stepper
    numbers are, not a catalog entry. The place is among all the picks, also those the filter hides.
16. **Picks: each exercise once.** An id that comes twice in the input counts once, at its first place; an
    id that is not stored is ignored; the foot counts what is left. Picks the filter hides are still counted
    and added.
17. **"Cancel" empties the query and the picks**, as "Add" does. The brief says so only for "Add"; the
    prototype does both the same way.
18. **`.add` is a case of `SlotEdit`** (criterion 11) and is not marked relative: the slots carry their ids,
    and `addSlots` leaves out a slot the day holds (`addEdit_isAddSlots_andSafeTwice`).
19. **One lint rule is switched off on one function**: `ProgramCopy.muscle(_:)` has one lookup for each of
    the eleven muscle groups (standards §7: each case its own lookup), which is one branch more than
    `cyclomatic_complexity` allows. `// swiftlint:disable:this`, as `SessionBuilder.build` does for its rule.
20. **Size.** 580 product lines against about 480 planned (table below); under the 800 at which the slice
    stops.

### Sanctioned edits to the tester's files

Ruled by the orchestrator on 2026-10-08, before the edit.

| File:line | Edit |
|---|---|
| `Tests/FeatureProgramTests/Adversarial/DayEditorAdversarialSupport.swift:100` | One line added to the exhaustive switch of `AdvDay.edited(_:_:)`: `case let .add(slots): DayEditing.addSlots(day, slots)`. Nothing else in the file. |

Not edited, for the tester: `DesignGalleryAdversarialTests.publicViews` (`Tests/LedgerDesignTests/Adversarial/`)
lists the public views of `Components/` as of 2026-09-30; `StepperField` is a new one and has its heading.

### The gallery's reference

`__Snapshots__/DesignGalleryTests/designGallery_dark_matchesReference.dark-large.png` was recorded again (the
only existing reference that changed; ruled by the orchestrator, twice, on 2026-10-08). The old file is
402 × 7010, the new one 402 × 8176: three sections at the end.

The old image is **not** the top of the new one row for row: its content stands one pixel row lower.
Measured with two scripts written for this (CoreGraphics, both files decoded to 8-bit sRGB; they are not in
the tree):

- `swift gallery-top.swift <old> <new>`: "rows of the old image that differ in the new one: 3758".
- `swift gallery-shift.swift <old> <new>`, old row r against new row r − shift: shift −2: 4,207 of 7,010 rows
  differ; −1: 3,989; 0: 3,758; **1: 15 of 7,009**; 2: 3,758 of 7,008. So every old row but the first is the
  new image's row one higher; the old image began with one more row of ground.
- The 15 rows that still differ hold 28 pixels in all, each one level of 255 apart in its largest channel
  ("largest channel difference after the shift: 1"). Old rows 3083 (the label of `PrimaryButton`'s "Start
  workout"), 3369, 3525, 3618, 3628, 3632, 3635, 3645, 3646 (`PillButton`'s and `IconPillButton`'s outlines
  and labels), 4972 (`WeekStrip`'s dots), 5383 (`SheetChrome`'s edge), 6072, 6073 (`WatchPrimaryButton`'s
  first button), 6409, 6411 (`WatchRestRing`'s arc). Edge blending; no glyph, colour or element changed.

The cause is a reading, **not proven**: the gallery is drawn at its own height; the old total was probably
not a whole number of points, the host rounded it up and the spare part of a point stood above the content;
with three more sections the total rounds another way. No section above the new ones was edited, and every
other existing reference of the target passes unchanged.

### Criteria → tests

Suites, part one: `StepperFieldTests` (SF), `LedgerToggleStyleTests` (TS), `WrapLayoutTests` (WL, the
arithmetic), `WrapLayoutRenderingTests` (WR), `AccessibilityTreeTests` with `TreeTables.forms` (Tree),
`ComponentAccessibilityTests` (CA), `FormControlSnapshotTests` (Snap), `DesignGalleryTests` (DG),
`PreviewTests` (PT). Part two: `ExercisePickerPresentationTests` (PK), `ExercisePickerPresentationPropertyTests`
(PP), `ProgramCopyTests` (CT), `FeatureProgramSourceTests` (SrcT).

| Criterion | Tests |
|---|---|
| 1 `StepperField` | SF `field_accessibility_isOneAdjustableElement`, `field_adjust_callsTheMatchingClosure`, `field_oneStepOff_onlyTheOtherSteps`, `field_bothStepsOffOrDisabled_isDimmedAndInert`, `field_adjustedAtItsLimits_announcesTheValue`, `buttons_areFortyFourPointTargets`, `switchedOffStep_isDrawnAsSuch`, `buttons_atAccessibilitySizes_standUnderTheText`; Tree, 8 rows; CA `stepperField_accessibility_adjustableWithTarget` |
| 2 `LedgerToggleStyle` | TS `toggle_accessibility_isSwiftUIsSwitch` (on and off, enabled and disabled, against a system switch), `toggle_activated_flipsTheBinding`, `toggle_disabled_doesNotFlip`, `toggle_onAndOff_differByFillAndSide`, `toggle_drawsNoAccent`, `knob_contrast_meetsThreeToOne` (both themes, with and without Increase Contrast); Tree, 5 rows; CA `ledgerToggle_accessibility_switchWithTarget`; Snap `formControls_increasedContrast_matchesReference` |
| 3 `WrapLayout` | WL `noChild_takesNoRoom`, `oneChild_standsAtTheStart`, `childrenThatFit_runAlongOneRow`, `childThatDoesNotFit_startsTheNextRow`, `childEndingAtTheEdge_stays`, `childAsWideAsTheRow_hasARowToItself`, `noWidth_isOneRow`, `rowOfMixedHeights_isCentred`, `reportedSize_isTheRoomTheChildrenTake` (6 widths); WR `drawnSize_isTheSizeOfItsRows`, `rightToLeft_runsFromTheRight`, `childWiderThanTheRow_getsTheRowsWidth`, `longPill_wrapsInsideTheRow`, `noChildAndOneChild_draw`; Snap `wrapLayout_rightToLeft_matchesReference` |
| 4 Registered and shown | PT `registry_listsEveryPreview`, `preview_renders` (the three new cases); DG `sections_names_coverEveryComponentAndTokenType`, `gallery_accessibilityTree_namesEverySectionAndToken`, `designGallery_dark_matchesReference`; Snap `stepperField_`, `ledgerToggleStyle_`, `wrapLayout_appearance_matchesReference` (six cells each), `formControls_pressed_`, `formControls_accessibility5_matchesReference`; Tree, 19 rows (the layout's 6 with pill buttons); CA `wrapLayout_pills_keepTheirTargets`. watchOS: the gate's watch build compiles `LedgerDesign` |
| 5 The set row is not touched | `git diff 48794bd -- LedgerKit/Sources/LedgerDesign/Components/SetRow*.swift` is empty; its references pass unchanged |
| 6 One input, one model | PK `noFilter_listsTheCatalogInNameOrder`, `list_isExerciseSearchFiltered` (20 cases × 6 equipment values), `exercisesInAnyOrder_giveTheSameList`, `search_isTheQueryAsTyped`; PP `make_randomInput_keepsTheInvariants` (`checkList`) |
| 7 The chips | PK `chips_areTheBriefs`, `chips_actionsNameTheirFilter`, `chips_areSpokenWithTheirRow`, `chips_tapped_selectAndFilter`, `chips_areBuiltFromOneListEach`, `equipmentWithNoChip_isReadAsAll`; PP `checkChips` |
| 8 The rows (the brief's criterion 12) | PK `rowBackMachine_isExactlyChestSupportedRow`, `customExercise_isARowLikeAnyOther`, `row_readsEquipmentMuscleAndTheDaysMark`, `rows_nameEveryEquipmentAndMuscle`, `rowInTheDay_canBePicked`, `picks_carryTheirPlace_andUnpick`, `pickAction_appliedTwice_isOnePick`; PP `checkRows` |
| 9 Nothing matches | PK `nothingMatches_offersClearFilters`, `noExercises_givesTheEmptyState`; PP `clearFilters_randomInput_showsEveryStoredExercise` |
| 10 The foot | PK `foot_readsTheBriefsTexts`, `foot_carriesThePicksInOrder`, `picks_twiceOrNotStored_areReadOnce`, `noFilter_listsTheCatalogInNameOrder` (title, "Cancel", placeholder); PP `checkFoot`, `taps_randomInput_keepThePicksInOrder` |
| 11 The picks become slots | PK `add_appendsRuleSevenSlotsInPickOrder`, `addEdit_isAddSlots_andSafeTwice`, `cancel_closesAndAddsNothing` |
| 12 Words | CT `picker_plainTexts_areTheBriefs`, `picker_addExercises_hasOneAndOther`, `picker_writtenTexts_areTheNotes`, `picker_chipAndRow_shareTheGroupsName`; `ModuleCopyTests` (`LedgerAppKitTests`) and the gate's string-catalog step for the catalog |
| 13 Pure and total | SrcT `sources_neverReadTheClockOrTheCurrentCalendar`, `storesAndPresentations_neverClamp` (now seen to read the library's files), `presentationsCopyAndModels_neverNameDouble`; PK `sameInput_givesTheSameModel`, `picks_twiceOrNotStored_areReadOnce`, `noExercises_givesTheEmptyState`; PP all four, `actions_randomInput_areSafeTwice` among them |

The brief's criterion 12, second half ("keeping the muscle/equipment filters but clearing query and
selection") is what `PickerScreen` does on `.add`, by the action's comment; the store that really does it is
S14's (`add_appendsInPickOrder_andKeepsTheFilters`, the plan's behaviour 14).

Checked by breaking the code (each change made in `ExercisePickerPresentation.swift`, the library's suites
run on the host, the change undone; every one made tests fail): the picks not read once; picks that are not
stored kept; equipment with no chip left to filter; a row that never unpicks; a muscle chip that sets "All";
the day's mark on the wrong rows; the foot's picks reversed; the query ignored. The controls' tests were not
checked this way.

**The pinned VoiceOver trees** (`AccessibilityTreeFormTables.swift`; each row is exact: count, order, label,
value, traits, no container):

| Control | State | Tree |
|---|---|---|
| `StepperField` | both steps on; at accessibility3 | adjustable "Sets", value "5" |
| | a spoken value | adjustable "Rest", value "2 minutes 30 seconds" (drawn "2:30") |
| | no "−"; no "+" | adjustable, the label and the value; not dimmed |
| | both off; disabled | adjustable and dimmed |
| | the gallery | five adjustable stops; the rules are none |
| `.toggleStyle(.ledger)` | off; on; at accessibility3 | button with the switch's trait, "Drop set", value "0" or "1" |
| | disabled | the same, dimmed |
| | a label of two texts | one stop, "Drop set, One extra set at −15%, straight after the last working set." |
| `WrapLayout` | no child | nothing |
| | pills on one row; right to left | "All" (selected), "Chest", "Back", in this order |
| | thirteen pills over three rows; at accessibility3 | the pills in their order, row by row |
| | a pill longer than the row | "Legs" (selected), the long title, "Arms" |

### The catalog's new keys

From the brief's "Copy (exact)" (brief:60) unless marked.

| Key | Used for |
|---|---|
| `Exercise library` | the sheet's title |
| `Search exercises` | the field's placeholder and spoken label |
| `All` | the first chip of each row |
| `Chest`, `Back`, `Shoulders` | a muscle chip, and the muscle on a row |
| `Legs`, `Arms` | a muscle chip |
| `already in this day` | a row's mark |
| `Nothing matches that filter.`, `Clear filters` | the empty state |
| `Select exercises to add` | the foot with no pick |
| `Add %lld exercises` (counted; `one`: `Add %lld exercise`) | the foot |

"Cancel" and the seven equipment names were in the catalog; "Cancel"'s comment now names both uses.

**Texts the brief does not give, written here (for Pete):**

| Key | Where it is seen or heard | Why this wording |
|---|---|---|
| `Quads`, `Hamstrings`, `Glutes`, `Calves`, `Biceps`, `Triceps`, `Forearms`, `Core` | on a row, after the equipment: "Barbell · Quads" | the catalog has eleven muscle groups; the brief names the three that are chips (deviation 11) |
| `Muscle`, `Equipment` | VoiceOver only: the name of a row of chips | the brief's own words for the two filters (criterion 12 of the brief) |
| `%@: %@` | VoiceOver only: a chip, "Muscle: Chest", "Equipment: All" | both rows have an "All"; criterion 12 asks for the chip with its row's name |

Not keys: an exercise's name (data); a pick's place, "2", formatted in the injected locale.

In the design gallery and the previews only (debug builds; `LedgerDesign` has no catalog): "Sets", "Rest",
"Target RPE", "Start load for the first week", "Top of range", "Drop set", "Keep the screen awake" and the
chips' words, as sample text.

### Product lines per file

Non-blank, non-comment lines.

| File | Planned | Lines |
|---|---|---|
| `LedgerDesign/Components/StepperField.swift` | 75 | 95 |
| `LedgerToggleStyle.swift` | 50 | 96 |
| `WrapLayout.swift` | 50 | 75 |
| `Components+Previews.swift` | 45 with the gallery | 157 → 172 |
| `Gallery/DesignGallery.swift` | | 71 → 74 |
| **Part one** | **220** | **284** |
| `FeatureProgram/Picker/ExercisePickerInput.swift` | (in the model's) | 11 |
| `ExercisePickerModel.swift` | 50 | 57 |
| `ExercisePickerAction.swift` | not planned | 13 |
| `ExercisePickerPresentation.swift` | 90 | 109 |
| `ProgramCopy+Picker.swift` | 120 | 99 |
| `DayEditor/DayEditorAction.swift` (`.add`) | | 61 → 64 |
| `DayEditor/ProgramCopy+DayEditor.swift` ("Cancel" over five lines) | | 160 → 164 |
| **Part two** | **260** | **296** |
| **The slice** | **about 480** | **580** |

Where the excess is: each control's file holds its gallery (17, 23 and 20 lines), which the plan counted
with the previews; the toggle has a view for the environment, one for the track and the colours apart for
the contrast test. Tests: about 1,680 added lines in 21 files, not counted.

### Open questions, each with a recommendation

1. **A switched-off step to VoiceOver** (deviation 2): silent but for the repeated value. *Recommendation:*
   keep; it is what the system's stepper does. If Pete wants words ("At minimum"), the control gains an
   optional `limitHint: String` the feature fills from its catalog; nothing uses a switched-off step yet.
2. **A picked row to VoiceOver** (deviation 14): the selected trait, no word, and the place among the picks
   is not spoken. *Recommendation:* keep, and decide with S12's VoiceOver table; a spoken "2 of 3" is one
   counted key and one field of `Row`.
3. **"Muscle: Chest"** for a chip is new wording. *Recommendation:* show Pete with S12's table. The
   alternative that needs no row name is "All muscles" and "All equipment" for the two first chips and the
   bare title for the others: two keys in place of three.
4. **Decision 3, A** (Core, Kettlebell, Band): the muscle chip needs `ExerciseSearch.MuscleFilter.core` in the
   Domain (deviation 12). *Recommendation:* if Pete chooses A, S12 or F12's Domain slice adds the case; here
   it is one line of copy.
5. **The toggle's track does not grow with the text size** (deviation 5); the label does.
   *Recommendation:* keep, as the system's switch does; the row is the target.
6. **One stepper for the design system** (criterion 5): `SetRowSteppers`' private pill and `StepperField`
   are two looks of one idea (the pill shows the step between its buttons, the field a label and a value
   beside them) and share the adjustable behaviour. *Recommendation:* a later chore, after S11 has drawn a
   screen with `StepperField`; nothing forces it.
7. **The controls' taps are tested through VoiceOver's actions only** (increment, decrement, activate):
   the host reader cannot tap a button that is not an accessibility stop of its own. *Recommendation:* the
   nightly UI test of the Day editor (S14) taps "+" and the switch.
8. **The gallery's reference moved by a pixel row** (above): accepted by the orchestrator; the cause is
   unproven. *Recommendation:* if it matters, give `DesignGalleryContent` a whole-point height in a chore
   and record once more; every later addition to the gallery risks the same.

### Inputs for S12 (the library's views)

The model table above is the contract. Beyond it:

- A view takes a part of the model and `(ExercisePickerAction) -> Void`; it builds no action but the search
  field's, `ExercisePickerAction.search(text)`. The field can be bound to `search.query` through that action
  (the query is stored as typed, unlike a name), or to a draft the store keeps; `search.placeholder` is its
  placeholder and its spoken label.
- The sheet scrolls: the title, the search field and the chips above (or in) `ScrollView {
  ExercisePickerPage(model:) }`, the foot pinned below; trees and references from an `ExercisePickerParts`
  view (testing-strategy §2.6). Which of the top parts are pinned is S12's to decide and say.
- Chips: `WrapLayout { ForEach(row.chips) { PillButton($0.title, style: $0.isSelected ? .filled : .outline) … } }`
  with `.accessibilityLabel($0.spokenLabel)`; a filled pill already says "selected". `row.spokenLabel` is for
  a container or a heading if the table wants one. A short first chip stands inside its 44 pt target
  (deviation 7): `flush: .leading` on the first of a row is not knowable from outside the layout, so S12
  either accepts it or the pill gains a minimum-width option.
- Rows: `ForEach(rows)` by `id`. Draw `name`, then `detail` and, when not nil, `inDayMark` after " · " in its
  own style (decision 1 draws it in ink or grey, not orange), or `line` whole. `isPicked` picks the mark's
  look and the selected trait; `pickMark` may be drawn in the mark ("2") or ignored. VoiceOver: label
  `spokenLabel`, value `spokenValue`.
- `content` is `.rows` or `.nothingMatches`: `EmptyState` fits the second (`message` as its title or body,
  `clear` as its action); `LedgerDesign`'s tree for that already exists.
- The foot: `PrimaryButton(foot.title)`, disabled when `foot.action == nil`. It is the screen's one orange
  thing (decision 1).
- Previews and snapshots build models with `ExercisePickerPresentation.make` from `ExerciseCatalog.seed()`:
  no filter; "row" + Back + Machine (one row); three picks with one exercise in the day; "zzz" (nothing
  matches); no exercise at all.

### Inputs for S14 (the library's store)

- **Fills:** `exercises` = `observeAll()` as it comes (the presentation sorts through `ExerciseSearch`);
  `dayExercises` = the exercise ids of the day on screen, with the Day editor's waiting edits applied;
  `query`, `muscle`, `equipment`, `picks` = its own state; `locale` from the dependencies.
- **Applies an action** exactly as the action table says; `Tests/FeatureProgramTests/Support/ExercisePickerTesting.swift`
  (`PickerScreen.tap`) is that table as code. The two chips are kept for as long as the Day editor stays
  open (the plan's behaviour 14), so they live with the Day editor's store or root, not with a sheet that is
  made anew each time it opens.
- **`.add(ids)`:** for each id in order, the exercise from the stored ones (skip one that has gone meanwhile),
  a `SlotID` from `@Dependency(\.uuid)`, `try DayEditing.newSlot(id:exercise:units:defaultRest:)` with the
  settings' units and default rest; then the Day editor's `.edit(.slot(.add(slots), day: day))`, once. The
  slots are built at the tap and travel in the edit, so the edit applied to show the day and applied again
  inside the save gives the same day. `newSlot` throws only for an exercise whose start load is below zero
  (S1's open question 4): log it and leave that exercise out. `ExercisePickerPresentationTests.edit(adding:…)`
  is this paragraph as a test helper.
- **Typing:** no debounce ("Brief vs main" row 26). `make` runs `ExerciseSearch.filtered` over the whole
  list on every keystroke; the plan's nightly timing test of the 10 ms budget belongs to this slice's store
  test, with 224 exercises.
- **Stale state needs no repair:** a pick or a day exercise that is no longer stored is ignored by the
  presentation, and equipment without a chip reads as "All".

### The runs

All on 2026-10-08, in the worktree; every simulator command through the lock (iPhone 17 and Apple Watch
Series 12 46 mm, both 27.0). The sources were not edited after the last full gate and the last fast gate;
this section was written after them.

- Host, `swift test --only-use-versions-from-resolved-file --filter 'FeatureProgramTests|ModuleCopyTests|WrapLayout'`
  in `LedgerKit`: exit 0. `FeatureProgramTests`: 294 tests in 27 suites passed (the tester's suites among
  them, with the one sanctioned line); `ModuleCopyTests` 6; `WrapLayoutTests` 9.
- Simulator, `xcodebuild test … -testPlan PR -only-testing:LedgerDesignTests`, four times. First: the build
  failed (a gallery list read from a nonisolated table; fixed). Second: 351 tests, 10 failed: 7 that recorded
  their 23 missing references, the gallery's (402 × 8176 against the reference's 402 × 7010), and two
  expectations of mine in `WrapLayoutRenderingTests` that were wrong (a wrapped pill is 8 pt higher than a
  one-line pill, not 10; `ImageRenderer` gives no image for an empty padded view), corrected. Third, with the
  old gallery reference deleted: 1 failed, the gallery's, recorded. Fourth: exit 0, 351 tests, 344 passed,
  none failed, 1 skipped, 6 known issues. No reference other than the gallery's changed (`git status` after
  the fourth run).
- `scripts/check.sh`, the full gate, three times. First: exit 1 after 77 s at the string-catalog step, "the
  code looks up "Nothing matches that filter." …, which is not a key of the catalog" (the key was missing;
  added). Second: exit 0 in 719 s. Its coverage table showed `ExercisePickerInput.swift` at 0 of 3 lines,
  three default values no test used; the defaults were removed (the store fills every field). **Third, on
  the final sources: exit 0, "check.sh OK", 688 s** (lint 71 s, iOS build 17 s, iOS tests 338 s, watchOS
  build 15 s, watchOS tests 244 s). iOS: 3,293 tests, 3,266 passed, none failed, 14 skipped, 13 known
  issues. watchOS: 2,255 tests, 2,236 passed, none failed, 14 skipped, 5 known issues. String catalogs:
  `FeatureProgram` 125 keys, `FeatureToday` 58, `LedgerAppKit` 7. Coverage: `FeatureProgram` 1,523 / 1,523
  lines; `LedgerDesign` 2,634 / 2,731 (96.44 %). Of the new files, from the second gate's bundle:
  `ExercisePickerPresentation.swift` 114 / 114, `ProgramCopy+Picker.swift` 95 / 95, `DayEditorAction.swift`
  44 / 44, `WrapLayout.swift` 104 / 105, `LedgerToggleStyle.swift` 127 / 135, `StepperField.swift` 133 / 145:
  the lines not run are the buttons' tap closures and `@unknown default` (open question 7).
- `scripts/check.sh --fast` on the final sources: exit 0, "check.sh (--fast) OK", 119 s
  (`LedgerDomainTests` 1,222 tests passed; `LedgerPersistenceTests` 552 passed with 1 known issue).
- **Not run:** the nightly lane (2,000 seeds, UI tests); a device; the controls on a watch simulator beyond
  the gate's watch build and its test plan (no watch test draws them).

Screenshots for Pete, copies of the references: `tasks/features/F11-program-builder/screenshots/s8/`, each
control dark and light at the default size and at accessibility3, the three together under Increase
Contrast in both themes, and the layout right to left.

## Slice S8 — review, round 1 (G3 reviewer, 2026-10-08)

Reviewed `git diff main...96f4187` (commits `449cb9c`, `07bc713`, `96f4187`) by reading only: no build, no
test, no simulator. Paths under `LedgerKit/` unless said otherwise.

**Verdict: approve with should-fix.** No blocking item. Twelve of thirteen criteria are met; criterion 1 is
met in part (a switched-off step is drawn but not spoken), which I accept as a recorded amendment and not as
a code change. Three should-fix items, all small.

### Blocking

None.

### Should-fix

- **S-1. A new lint suppression against the Definition of Done.**
  `Sources/FeatureProgram/Picker/ProgramCopy+Picker.swift:72` switches `cyclomatic_complexity` off. Standards
  §12 says "No new lint suppressions"; §11 allows one only with its reason. The function is right as it is
  (§7 asks for one lookup per case, and eleven flat cases are not complex); what is wrong is that the rule
  counts them. *Proposed:* in `.swiftlint.yml` add `cyclomatic_complexity: { ignores_case_statements: true }`
  and delete the inline waiver: every later "one lookup per case" member over ten cases would need the same
  waiver otherwise. This is a change of the lint configuration, so it is the orchestrator's ruling. If it is
  refused, keep the waiver, put the reason on the line as `SessionBuilder.swift:16` does
  (`// swiftlint:disable:this cyclomatic_complexity - standards §7: one lookup per case`) and record the
  exception to §12 in the pull request. Splitting the switch in two to get under ten would be worse than
  either.
- **S-2. A disabled field does not look disabled, only its buttons do.**
  `Sources/LedgerDesign/Components/StepperField.swift:45-50`: the label stays `inkMuted` and the value `ink`
  when `isEnabled` is false (reference `stepperField_appearance…dark-large`, last field "Top of range 12": the
  text is as strong as on the live fields). `PillButton.swift:72-75` sets the house rule ("Disabled, it looks
  disabled": `inkFaint`). *Proposed:* `.foregroundStyle(isEnabled ? LedgerColor.ink : LedgerColor.inkFaint)`
  on the value and `inkMuted`/`inkFaint` on the label; record the six `stepperField` references and the four
  `formControls` ones again (all new in this slice). The same holds for the toggle
  (`LedgerToggleStyle.swift:41`), but there the label is the caller's view; see "For Pete", 1.
- **S-3. The pull request is over the 500-line target and its third commit is misnamed.** I count 592 added
  non-blank, non-comment lines under `Sources/` without the catalog (the notes say 580; the same within a
  few). Standards §10: the description says so in one line and names the split considered (the natural seam
  is part one, `LedgerDesign`, against part two, `FeatureProgram`; one pull request is right, both parts are
  small and neither is used yet). Commit `96f4187` is `docs(program)` and carries a catalog key
  (`Localizable.xcstrings`, "Nothing matches that filter.") and a source change
  (`ExercisePickerInput.swift`); `449cb9c` therefore did not pass the string-catalog step alone. With a
  squash merge only the title survives: *proposed:* no rewrite of history; the squash title is
  `feat(program): …` or `feat(design): …`, never `docs`.

### Nits

- **N-1.** `Sources/FeatureProgram/Picker/ProgramCopy+Picker.swift:100-102`, `nothingMatches` has no
  translator's comment, alone among the 25 new keys. §7 allows that ("where a translator needs one"); "that
  filter" means the search text and both chip rows together, which a translator cannot know. Add
  `comment: "Shown in the exercise library when the search and the two chip rows leave no exercise"` in the
  code and the catalog.
- **N-2.** `ExercisePickerModel.swift:98-101`: `Row.spokenLabel` is always `name` and `Row.spokenValue` is
  always `line`; four fields for two values. Keep them only if S12's table is expected to make them differ
  (it will if open question 2 is answered with a spoken place); otherwise cut both.
- **N-3.** `ExercisePickerAction.swift:26-28`: `search(_:)` is a second name for `.setQuery`. S6's `rename`
  builds a nested edit; this builds nothing. Cut it, or keep it for symmetry; no behaviour depends on it.
- **N-4.** `Tests/FeatureProgramTests/FeatureProgramSourceTests.swift:88-92` names three of the five new
  files as "seen to be read"; add `ExercisePickerModel.swift` and `ProgramCopy+Picker.swift`.
- **N-5.** `WrapLayout.swift:37-46` and `:25-26`: placement asks an over-wide child for its size again at
  `bounds.width`, which is the width the layout reported (the child's fitted width), not the width it was
  first asked at. It agrees as long as a child asked at its own fitted width answers the same; `Text` does,
  and `longPill_wrapsInsideTheRow` and the references show it. Say so in the comment. A zero width
  (`ProposedViewSize.zero`, SwiftUI's minimum probe) gives width 0 and one child per row, which is a sane
  minimum; no test names it (`noChild_takesNoRoom` has the only zero).
- **N-6.** A long pill at accessibility3 and 5 (`wrapLayout…accessibility3`,
  `formControls_accessibility5…`): the wrapped title's first and last lines come close to the capsule's
  round ends. It is `PillButton`'s shape, not the layout's, and no real chip is a sentence. No change here.

### The criteria

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | `StepperField` | **partly** | Strings and one optional closure per step, no lookup: `StepperField.swift:25-37`. One adjustable element, label and value, spoken value apart: `:58-70`; tree rows `AccessibilityTreeFormTables.swift:12-50`. 44 pt buttons: `:90`, `StepperFieldTests.buttons_areFortyFourPointTargets`. Stacks: `:40-42`, reference at accessibility3. A switched-off step is drawn (`:83-93`, `switchedOffStep_isDrawnAsSuch`, which also pins that the left button follows `onDecrement`) but **not spoken** (deviation 2). |
| 2 | `LedgerToggleStyle` | met | Ink track on, no accent token anywhere: `LedgerToggleStyle.swift:87-102`; `toggle_drawsNoAccent`. Knob 3:1 in four settings and the on-track 3:1 on the ground: `knob_contrast_meetsThreeToOne`. VoiceOver is a system switch by `accessibilityRepresentation` (`:48-51`), compared trait for trait with `.switch` in `toggle_accessibility_isSwiftUIsSwitch`. |
| 3 | `WrapLayout` | met | Both entry points call `arrangement` (`WrapLayout.swift:21-33`); I checked by hand that arranging in the reported width gives the arrangement of the proposed width (no row ends past `widest`, and a child that did not fit in the wider row does not fit in the narrower). nil and infinite give one row (`:53`); no child gives zero (`:77`). Right to left is SwiftUI's mirroring, pinned by `rightToLeft_runsFromTheRight` and a reference I looked at. No cache, and none is needed for a dozen chips. |
| 4 | Registered and shown | met (watchOS not checked by me) | `Components+Previews.swift:27-29, 56-58, 174-184`; `DesignGallery.swift:82-85`; 18 matrix references plus 5; 19 tree rows; `ComponentAccessibilityTests` three tests. The watch compile is the implementer's gate run; I ran nothing. Nothing in the three files is iOS-only by reading (`AnyLayout`, `accessibilityRepresentation`, `.toggleStyle(.switch)`, `accessibilityAdjustableAction` all exist on watchOS). |
| 5 | The set row is not touched | met | No `SetRow*` file in `git diff --stat main...96f4187`. |
| 6 | One input, one model | met | `ExercisePickerPresentation.swift:22-61`; the only list is `ExerciseSearch.filtered`'s (`:25-30`), mapped, never sorted or filtered again. `list_isExerciseSearchFiltered`. |
| 7 | The chips | met | `:17-20`, `:37-52`, `:86-104`; actions absolute (`.setMuscle($0)`, `.setEquipment($0)`). Equipment is one list; the muscle list is the Domain's (deviation 12). |
| 8 | The rows | met | `:108-126`; mark apart (`inDayMark`) and joined (`line`); `isPicked`, `pickMark`; `.setPicked(place == nil, …)` is absolute. |
| 9 | Nothing matches | met | `:53-58`; `noExercises_givesTheEmptyState`. |
| 10 | The foot | met | `:65-69` (once each, stored only), `:129-137`; counted key with `one` and `other` in the catalog. |
| 11 | Slots through the Domain | met | `DayEditorAction.swift` `SlotEdit.add([Slot])` → `DayEditing.addSlots`; the presentation names ids only. The two product switches over `SlotEdit` (`isRelative`, `applied`) both have the case; no other product code switches on it (`DayEditorPresentation.swift:150-158` passes it through). |
| 12 | Words | met, with the two spoken gaps of deviation 14 | Every lookup is in `ProgramCopy+Picker.swift`; 25 keys, all `translated`, keys are the English text, comments equal the code's, `Add %lld exercises` has `one`/`other`; equipment names not added again. A picked row has no spoken text and the place is not spoken. |
| 13 | Pure and total | met | No clock, calendar or ambient locale in the five files (read); locale is the input's. Unstored picks and day ids are ignored (`:65-69`, `:111`). |

### The deviations

| # | Judgement |
|---|---|
| 1 Two optional closures | **Accept.** It is the criterion's own wording ("one closure per step"), there is no flag that could disagree with a closure, and it maps onto S6's field model. Better than `onStep`. |
| 2 A switched-off step is not spoken | **Accept, as an amendment of criterion 1** (orchestrator to record). There is no system trait for one direction; a hint needs a text the control may not look up; and no caller switches a step off (deviation 3). The claim that a system stepper at its limit sounds the same is not something I verified. |
| 3 Behaviour 11 against criterion 1 | Accept. Consequence to keep in mind: the off state is unused code until Settings or S11 uses it. |
| 4 Round buttons, label in the small grey role | Accept; it follows `IconPillButton`. For Pete, 2. |
| 5 The toggle | Accept the build (`accessibilityRepresentation` is the right tool). For Pete, 1, on how off and disabled look. |
| 6 `WrapLayout` mirrors nothing itself | Accept; correct for a `Layout`. |
| 7 A narrow pill inside its target | Accept; S12's to settle. Visible in the references: "All" starts about 3 pt inside the edge. |
| 8 Gallery sections last | Accept. |
| 9 The input holds the day's exercise ids | Accept; it is what criterion 6 lists. |
| 10 Equipment without a chip reads as "All" | Accept. It is a normalising of the filter's value, not a second filter. |
| 11 A row's muscle is the primary group | Accept; for Pete, 3 (eight new words). |
| 12 The chips' lists | Accept. Criterion 7's "three more entries" is two entries and one Domain case; said plainly in the notes. |
| 13 The selected chip carries its action | Accept. |
| 14 Picked said by the selected trait; the place unspoken | **Accept for this slice, on a condition:** S12's VoiceOver table must pin `.isSelected` on a picked row, since nothing in the model forces it. The place decides the order of the added slots and a VoiceOver user cannot hear it: Pete decides (For Pete, 4). |
| 15 A pick's place is a formatted number | Accept. |
| 16 Picks once each | Accept. |
| 17 "Cancel" empties the query and the picks | Accept; For Pete, 5. |
| 18 `.add` is not relative | Accept; `addSlots` leaves out an id the day holds (`DayEditing.swift:79-85`). |
| 19 The lint waiver | **Should-fix, S-1.** |
| 20 Size | Accept; S-3 for the description line. |

(The task named ten deviations; the notes list twenty decisions. All twenty are judged.)

### The open questions

1. A switched-off step to VoiceOver: keep; amend criterion 1.
2. A picked row to VoiceOver: keep now; Pete decides on the spoken place before S12's table is written.
3. "Muscle: Chest": keep for now; Pete sees it with S12.
4. Decision 3 A needs a Domain case: agreed, nothing to do here.
5. The track does not grow with the text: keep; the row is the target (references at accessibility3 and 5
   show no clipping).
6. One stepper for the design system: a later chore, agreed.
7. Taps tested only through VoiceOver's actions: **a real gap, accepted until S14.** The sighted path of the
   toggle (`LedgerToggleStyle.swift:35-39`) runs in no test: an empty button action would pass every test of
   this slice. The stepper's buttons are better off: the same optional closure drives the faint look and the
   tap, and the look is pinned per side. S14's UI test must tap "+", "−" and the switch.
8. The gallery's reference: see below; accept.

### The gallery's reference

I decoded both PNGs myself (a short script, pure Python, in the scratchpad) and compared every row: old row
r equals new row r − 1 for all but 15 of 7,009 rows, and in those the largest channel difference is 1 of 255;
with no shift 3,758 rows differ. That confirms the implementer's numbers and row list exactly. By eye, on
old and new strips side by side (rows 0–700, 2900–3700, 6400–7010): the same content, one pixel row higher;
no glyph, colour, spacing or element above "StepperField" changed. The cause stays unproven; the effect is
harmless.

### Tests

They pin the criteria. The picker's tests compare whole values and exact strings, tap the model's own
actions through `PickerScreen`, and the eight mutations the implementer lists are the ones I would have
tried. `WrapLayout`'s arithmetic is tested as a function and again as drawn pixels. What could pass with the
code broken: the toggle's sighted tap (question 7); a disabled look of the texts (S-2, nothing asserts it);
`sizes(of:)` at a zero width (N-5). The controls' tests were not mutation-checked by the implementer and I
ran nothing.

### For Pete, in plain words

1. **The switch.** On is clear in both themes: a filled ink track, no orange. Off is a grey knob in a very
   faint outline, and a switched-off-and-disabled one is only a shade darker, with its label still in full
   ink. Look at `screenshots/s8/ledgerToggleStyle-dark-large.png`: rows 1 and 4 are "off" and "off,
   disabled". If they read too alike, the off knob can be a stronger ink and a disabled label can dim.
2. **The stepper.** Round "−" and "+" (the prototype had rounded squares), a small grey label over a bold
   value. A step at its limit is faint. A disabled field keeps its text at full strength (S-2 proposes to dim
   it).
3. **Eight new words** on an exercise's row: Quads, Hamstrings, Glutes, Calves, Biceps, Triceps, Forearms,
   Core ("Barbell · Quads"), and for VoiceOver "Muscle", "Equipment" and "Muscle: Chest".
4. **VoiceOver and the order of picks.** A picked exercise is announced as "selected"; that it is the second
   of three is drawn ("2") but not said. The order is the order the exercises are added in. Say whether it
   should be spoken.
5. **"Cancel" forgets the search text and the picks** and keeps the two chips, as "Add" does.

### Not checked

No build, test, lint or simulator run (by instruction). The watchOS compile, the test counts and the
coverage are the implementer's. VoiceOver on a device. The tester's `Adversarial` files. Of the images I
opened eight of the fifteen screenshots (the toggle dark and light at large and dark at accessibility3; the
stepper light at large and dark at accessibility3; the layout right to left and dark at accessibility3; the
three under Increase Contrast, dark), the accessibility5 reference and the gallery's new sections; not the
xLarge references, the pressed sheet, or the other seven screenshots. `ExercisePickerPresentationPropertyTests` and `+Chips` I did not read line by line.

## Slice S8 — adversarial testing, round 1 (G2 tester, 2026-10-08)

Tested `96f4187` in the worktree; the tests are commits `53a857f` (`test(program)`) and `f74a6b6`
(`test(design)`). No product code was changed. Paths under `LedgerKit/`.

**Result: two findings with a failing test each, one test gap, no other defect found.** 43 new tests in 8
files; 41 pass, 2 fail knowingly and stay in the tree.

### What was attacked, and with what

| Part | File (`Tests/…/Adversarial/`) | Tests | How |
|---|---|---|---|
| The library's model | `FeatureProgramTests/…/ExercisePickerAdversarialSupport.swift`, `ExercisePickerModelAdversarialTests.swift` | 9 | The tester's own reading of the sheet (`AdvPicker.lines`: words, filter, order, picks, actions, written from criteria 6 to 13) against `make`, line for line: 200 seeds × 4 inputs over exercises of the tester's making (names with diacritics, full width, emoji, Arabic, Hebrew, empty, blank, format text; picks repeated and not stored; day exercises not stored; equipment without a chip); 200 seeded chains of ten taps, each action applied as documented and then once more (absolute); the bundled catalog under all 6 × 8 chip pairs and five queries; blank queries of seven kinds; "Clear filters"; no exercise stored; 10,000 exercises with 1,000 picks; an exercise stored twice |
| The library's words | `ExercisePickerWordsAdversarialTests.swift` | 7 | The foot in eleven locales; the count in Arabic and Devanagari digits; names as data; the five sources of `Picker/` read for ambient reads, for text outside the copy file and for lookups; each of the copy file's 24 lookups against the catalog's keys |
| The picks as slots | `ExercisePickerAddAdversarialTests.swift` | 4 | Rule 7's defaults for all 224 catalog exercises in lb and kg; 60 seeds of picks tapped, added to a day of the seed program (order, the day's other slots, the other days and the weeks untouched, safe twice); an empty list, slots the day holds, one id three times; the same exercise added twice over |
| `WrapLayout`, arithmetic | `LedgerDesignTests/…/WrapLayoutAdversarialTests.swift` | 5 (host too) | The tester's model of a wrapping row against `arrangement(of:in:)`: 300 seeds × 11 widths (none, 0, 1, 44, 100, 137.5, 402, 100,000, unbounded, −1, −100), none to forty children, six spacings; nothing outside the reported size and the size no bigger than used; rows greedy and in order; arranged again in its own reported width; children of no size, spacing wider than the row, a width that is no number; 5,000 children |
| `WrapLayout`, drawn | `WrapLayoutDrawnAdversarialTests.swift` | 4 | Fifteen pills at four widths (120 to 402) and four text sizes (to accessibility5), read by their VoiceOver frames: inside the row, above the view under the layout, 44 pt, none overlapping, in reading order; right to left the exact mirror; the layout padded, under and beside other views; a long text at four widths |
| `StepperField` | `StepperFieldAdversarialTests.swift` | 8 | Eight cells (the six, xxxLarge, accessibility5) × both directions: both buttons drawn 44 pt, the gap, long texts leaving the buttons whole, one adjustable 44 pt element, each swipe its closure once; Bold Text; a switched-off step in both themes with and without Increase Contrast; a field with no step or disabled |
| `.toggleStyle(.ledger)` | `LedgerToggleAdversarialTests.swift` | 6 | From pixels: the knob against what it stands on and the on track against the ground, both themes, with and without Increase Contrast; four states as four drawings; the track in eight cells with a short and a long label; right to left; VoiceOver against the system's switch in eight cells; a binding that counts its sets |
| The gallery | `DesignGalleryAdversarialTests.publicViews` | (existing test) | The three new names added to the list |

### Findings

- **F11-S8-1 (bug, medium): the foot takes another language's plural form.** `ProgramCopy.addExercises` gives
  "Add 1 exercises" with a locale whose language has no singular (ja_JP, zh_CN, ko_KR) and "Add 21 exercise",
  "Add 101 exercise" with ru_RU: the catalog is English only and `String(localized:locale:)` chooses the
  plural form by the injected locale's rules. Criterion 10 asks for "Add 1 exercise" and "Add %lld
  exercises". en_US, en_GB, en_JP, de_DE, fr_FR, pl_PL, he_IL, ar_AE and ar_EG read right for the counts
  tried. *Test (fails):* `ExercisePickerWordsAdversarialTests.foot_pluralForms_areEnglishInEveryLocale`, 5
  issues in 4 of its 11 cases. The same cause is on `main`: measured with a throwaway test,
  `ProgramCopy.exercises(1, locale: ja_JP)` is "1 exercises" and `ProgramCopy.weeks(1, locale: ja_JP)` is
  "1 weeks" (S5 and S6; `FeatureToday` has six counted keys and was not measured). Not established here:
  which locale the app injects on a device whose language the app has no localization for. The seeded
  suites leave ja_JP out of their locales for this reason, and say so (`AdvPicker.locales`).
- **F11-S8-2 (defect against criterion 1 as written, low today): one switched-off step is not spoken.**
  With "−" or "+" switched off, VoiceOver is handed exactly what it is handed with both on: label "Sets",
  value "5", traits 4096 (adjustable), no hint, no custom action. Criterion 1: "a switched-off step is drawn
  and spoken as such". With both off the field is dimmed, which is spoken. *Test (fails):*
  `StepperFieldAdversarialTests.oneStepOff_isSpokenAsSuch`. See deviation 2 below.
- **F11-S8-3 (test gap, confirmed by mutation): the visible buttons can do nothing and every test passes.**
  With `StepButton`'s tap made empty and the switch's `configuration.isOn.toggle()` removed (both at once),
  the whole of `LedgerDesignTests` gives the same result as without them: 374 tests, the one failure of
  F11-S8-2. VoiceOver's paths are tested (the adjustable action; the system switch of the representation);
  a finger's are not, and a hosted test has no tap. This is the implementer's open question 7, now measured;
  my suites do not close it. *No test.* The nightly UI test of S14 is the first thing that would notice.

### Deviations 2, 3 and 5

- **Deviation 2 (a switched-off step to VoiceOver): a defect against criterion 1's wording** for one step
  off, F11-S8-2. The reason given ("the control looks up no text") does not hold it up: the control takes
  `String`s, as `spokenValue` shows, so a caller can hand it the words. It costs nothing today, since no
  caller switches one step off (deviation 3). Either the control gains the words (the notes' own
  `limitHint`) or criterion 1 is amended; the G3 review proposes the amendment. The failing test goes or
  is turned round with whichever is ruled.
- **Deviation 3 (S6's model never switches a step off): not a defect of this slice.** Criterion 1 asks that
  the control can, and it does, drawn and tested. The consequence is S11's: at a limit the Day editor will
  draw a live "+" that changes nothing, and the switched-off look is drawn nowhere in the app until a model
  hands over a nil closure.
- **Deviation 5 (the switch): not a defect.** Measured from the drawn pixels, not from `LedgerToggleLook`:
  the knob has 3:1 against what it stands on and the filled track 3:1 against the ground, light and dark,
  with and without Increase Contrast; the four states are four drawings; the track keeps its size and its
  place in eight cells; VoiceOver finds the system switch's label, value and traits in eight cells, and one
  double-tap sets the binding once. Criterion 12 is not touched: the value is the system's, no text of
  ours. Not measured: the off track's outline against the ground (a hairline, as every outlined pill).

### The implementer's tests, checked by breaking the code

Each change made in place, the tests run, the file restored from a copy kept outside the tree (compared
byte for byte afterwards). The simulator runs each held several changes at once, in different controls or
failing different tests; a cell says which tests failed in that run. "Theirs" are the implementer's tests without the snapshot references.

| Change | Caught by theirs | By references | By mine |
|---|---|---|---|
| `WrapLayout`: `>` to `>=`; no centring; the widest row read from a row's first child; line spacing after the last row; spacing dropped (five runs on the host) | yes, each | not run | yes, each |
| `WrapLayout`: a non-finite width not read as none | no | not run | no (the same result for every width tried: equivalent) |
| `WrapLayout`: a wide child not held to the row's width | yes | yes | yes |
| `WrapLayout`: `bounds.minY` dropped; `bounds.minX` dropped | no; yes (right to left) | yes | yes |
| `WrapLayout`: children placed with no proposal | no | yes | yes |
| `StepperField`: the two swipes exchanged | yes | no | yes |
| `StepperField`: not disabled with both steps off | yes | yes | yes |
| `StepperField`: a switched-off button drawn live | yes | yes | yes |
| `StepperField`: `guard isEnabled` removed from the adjustable action | **no** | no | **no** |
| `StepperField`: the spoken value ignored; never stacked; the buttons' 44 pt target removed; children combined | yes, each | yes | yes |
| The switch: `accessibilityRepresentation` removed | **no** | no | **no** |
| The switch: the knob's colour not following the state; the knob always leading; the 44 pt target removed | yes, each | yes | yes |
| The switch: the off track filled (in one run with the 44 pt change, which fails the same test of theirs first) | not told apart | yes | yes |
| **The buttons' taps and the switch's tap emptied** | **no** | **no** | **no** (F11-S8-3) |

`guard isEnabled` survives because a disabled element is handed no adjustable action in the first place:
the guard is not what keeps a disabled field still. A note, not a finding.

The switch without its `accessibilityRepresentation` reads and acts the same in every test, mine included:
one stop, the system switch's label, value and traits in eight cells, and a double-tap that sets the binding
once. So no test shows what the representation adds, and with it in place VoiceOver's double-tap goes to the
representation's switch and never through the visible button's action (which is why emptying that action
goes unseen). A note for the implementer: either it can go, and the tap closure is then covered by the
double-tap test, or the notes say what needs it.

### Questions

- **F11-S8-Q1.** An exercise stored twice under one id gives two rows of one `id` (`Identifiable`), both
  picked together, and is added once (`exerciseStoredTwice_isAddedOnce` pins only the last). The stored
  exercises have one row per id by the schema, so this is unreachable today. Is "ignored, not trapped on"
  (criterion 13) meant to cover it for S12's `ForEach`?
- **F11-S8-Q2.** A blank or empty name is a row whose name and spoken label are empty ("", "   "); the Day
  editor writes "—" for a missing name. Custom exercises come with F12: whose rule is a blank name?

### Notes

- 10,000 exercises with 1,000 picks are one right model; the test allows two seconds and the whole suite of
  nine ran in 1.4 s on the host. The plan's 10 ms budget at 224 exercises was not measured.
- A text or pill whose own smallest width is more than the row (a 44 pt pill in a 30 pt row) is reported at
  the row's width and drawn wider; no phone row is that narrow. Not tested.
- `SlotEdit.add([])` and `.add` of slots the day holds leave each of the seed program's days as they were.

### Not attacked

A finger's tap on any of the controls (F11-S8-3). What VoiceOver says at a switched-off step, and where its
double-tap lands on a `StepperField` (the element has no activation of its own); VoiceOver on a device. The
controls on a watch simulator. The pressed look and Reduce Motion. Whether a long value is ever cut short
with "…". The plain texts' dependence on the process's language (`String(localized:bundle:)` without a
locale; the catalog is English only). `ExerciseSearch`'s folding itself (the Domain's; my reading uses the
same Foundation call). The 2,000-seed nightly lane.

### The runs

All on 2026-10-08 in the worktree; every simulator command through the lock (iPhone 17, 27.0).

- Host, `swift test --only-use-versions-from-resolved-file --filter 'FeatureProgramTests|WrapLayout'` in
  `LedgerKit`: `FeatureProgramTests` 314 tests in 30 suites, 1 failed with 5 issues (F11-S8-1);
  `WrapLayout` 14 tests in 2 suites passed.
- Simulator, `xcodebuild test … -testPlan PR -only-testing:LedgerDesignTests`: 374 tests, 366 passed,
  1 failed (F11-S8-2), 1 skipped, 6 known issues; about a minute. Before my files it was 351.
- Five more such runs with the changes of the table above, each ending with the sources restored; six
  host runs for the layout's arithmetic. No reference was recorded or changed.
- `scripts/check.sh --fast`: exit 0, "check.sh (--fast) OK", 113 s. `scripts/check.sh --lint-only` clean.
- **Not run:** the full gate, the watch plan, the nightly lane.

## Slice S8 — fix round 1 (G1 implementer, 2026-10-08)

On `7770a27` (the slice, the tester's suites and notes, the review, the rulings). The brief's "Plan amendments
— slice S8 after round 1" is the specification: criteria 14 and 16 to 18 are this round's. Two commits,
`764a165` (`fix(design)`) and `d33b71b` (`fix(program)`), then these notes. Paths under `LedgerKit/`.

### What changed, per item

| Item | Change |
|---|---|
| **14** F11-S8-1, the plural form | One computed property, `Locale.forCountedText`, in an extension at the foot of `Sources/FeatureProgram/ProgramCopy.swift` (17 code lines). Each of the module's eleven counted lookups now passes `locale: locale.forCountedText`: `block(weeks:)`, `weeks`, `scheduledDays`, `days` (`ProgramCopy.swift`); `setsAWeek`, `exercises`, `sets`, `estimate(minutes:)` (`ProgramCopy+Days.swift`); `backToBack`, `scheduledInWeeks` (`ProgramCopy+DayEditor.swift`); `addExercises` (`ProgramCopy+Picker.swift`). No lookup that is not counted changed. Details below. |
| **16** S-2, a disabled field | `StepperField.swift`: the label and the value are drawn in `inkFaint` when the field is disabled or has no step to take (both closures nil: the field disables itself then, so it is drawn as it is spoken). One step off dims that button only. Pinned by the new suite `StepperFieldDisabledTests.disabledField_drawsItsTextFaint` (both themes: the text less than half as strong as a live field's, still there, the same drawing for "disabled" and "no step", full strength with one step off). |
| **17** S-1, the lint waiver | Kept, on the function's line with its reason: `// swiftlint:disable:this cyclomatic_complexity - §7 lookups`; the doc comment above says the rest (eleven groups, one lookup each, one branch over the limit). The longer reason the reviewer worded does not fit the line: with it the line passes 120 columns and the formatter breaks the declaration, after which the waiver no longer stands on the line the rule reports. `disable:next` cannot be used either: above the doc comment it does not reach the function, under it the lint reports an orphaned doc comment. The lint configuration is untouched. **For the pull request:** this is the one exception to standards §12 ("no new lint suppressions"); the reviewer's alternative is `cyclomatic_complexity: { ignores_case_statements: true }` in `.swiftlint.yml`. |
| **18** N-1 | "Nothing matches that filter." has its translator's comment, in the code and the catalog: "Shown in the exercise library when the search and the two chip rows leave no exercise". |
| N-2 | `ExercisePickerModel.Row.spokenLabel` and `.spokenValue` are gone: the label is `name`, the value `line`, and `Row`'s comment says so. A chip's and a chip row's `spokenLabel` stay (they are texts of their own). |
| N-3 | `ExercisePickerAction.search(_:)` is gone; a view sends `.setQuery(text)`. My test of the alias became `setQuery_keepsTheQueryAsTyped` (the field keeps the text as typed while the filter trims it). |
| N-4 | `FeatureProgramSourceTests.presentationsCopyAndModels_neverNameDouble` now sees `ExercisePickerPresentation.swift`, `ExercisePickerModel.swift` and `ProgramCopy+Picker.swift` among the files it reads. The other list (`storesAndPresentations_neverClamp`) reads the files that can hold logic, which a model and a copy file are not by that suite's own rule, so the two names went where those files are read. |
| N-5 | `WrapLayout.sizes(of:in:)`'s comment says that the layout measures at the proposed width and places at the width it reported, that the two agree while a child asked again at its own fitted width answers the same (as `Text` does), and what a width of zero gives. Two tests: `WrapLayoutTests.zeroWidth_isOneChildARow` (the arithmetic) and `WrapLayoutRenderingTests.zeroProposal_withChildren_isOneChildARow` (a probe layout asks the real layout for its size at `ProposedViewSize.zero`: no width, one row a child). |

Not done, as ruled: criterion 15's test (`StepperFieldAdversarialTests.oneStepOff_isSpokenAsSuch`) is the
tester's to replace and still fails. `StepperField`'s comment no longer claims that VoiceOver repeats the
value at a switched-off step (the reviewer could not verify it, nor can I): it says one step off is not
spoken.

### Criterion 14, exactly

`Locale.forCountedText` is this locale with its language replaced by the language the catalog answers in.

- **What it reads:** `Bundle.module.localizations` (the languages this module's built catalog holds; "en"
  today) and the locale it is called on, which is the one the copy member was handed. It calls
  `Bundle.preferredLocalizations(from:forPreferences:)` with exactly those two, a pure function of its
  arguments. It reads no current locale, no preferred languages of the device and no user defaults; the
  module's source test (`sources_neverReadTheClockOrTheCurrentCalendar`) reads the file as before.
- **What it decides:** the language, and with it the plural rule. While the catalog holds only English that
  is English for every locale: "Add 1 exercise" under ja_JP, zh_CN, ko_KR; "Add 21 exercises" under ru_RU.
  When a translation is added to the catalog, a locale of that language takes that language's forms with no
  change here (tried on the function's arithmetic with the lists ["en"] and ["en", "fr", "ja"]: fr_FR then
  resolves to fr, ja_JP to ja, ru_RU to en).
- **What still follows the lifter's locale:** the digits (the numbering system is carried over: "Add ٣
  exercises" under ar_EG, "१,२३४ sets a week" under hi_IN with Devanagari digits) and the region, and so the
  grouping of the region ("1.234 sets a week" under de_DE, "12 345" with a narrow space under fr_FR).
- **What does not, and did before:** a grouping that belongs to the language and not to the region. One
  case found: fr_CA writes "1 234 567", and English in Canada (which is what the lookup now sees) "1,234,567".
  No count of this module reaches four digits in use (weeks, days, sets, exercises, minutes).
- **Known limit, unchanged by this round:** which catalog language the *words* come from is the bundle's
  choice, made from the device's languages, not from the injected locale; that was so before and is the
  same for every lookup of every module. With one language in the catalog the two cannot differ.
- **Where it stands:** the criterion asks for "one place in `ProgramCopy`". It is one place, in
  `ProgramCopy.swift`, but an extension of `Locale`, not a member of the `ProgramCopy` enum. The reason is
  the checks that read the copy files as text, all outside this slice's reach: the tester's two suites on
  `main` require the text `locale: locale` in every lookup with a value
  (`ProgramWordsAdversarialTests.swift:181`, `DayEditorWordsAdversarialTests`), so `locale:
  counted(locale)` fails them; and `CopyAudit` (`LedgerTestSupport`) reports a lookup that stands after
  `return` or inside a closure as "not `String(localized: "…"`", so a member cannot resolve the locale in a
  statement of its own first. `locale: locale.forCountedText` passes all of them with no edit to any. Both
  other forms were built and seen to fail before this one was chosen.
- **Tests:** the tester's `foot_pluralForms_areEnglishInEveryLocale` passes unedited (11 locales), as do its
  digit test and the three source scans. Mine: `ProgramCopyTests.countedTexts_takeTheCatalogsPluralForm` (nine
  locales with other plural rules; `exercises` and `weeks` at 0, 1, 2, 5, 11, 21, 22 and 101, and each of
  the other nine counted texts at one) and `counting_keepsRegionAndDigits`. One test of S5 changed its
  expectation: `values_followTheLocaleHandedIn` expected "0 day" under fr_FR ("French counts none as one");
  it is "0 days" now, which is the ruling.
- **Not here:** `FeatureToday`'s and `LedgerAppKit`'s copy files have the same cause (the tester's note);
  standards §7 still describes the old behaviour ("`fr_FR` gives "0 fixture set"", pinned in `LedgerAppKit`
  by `CatalogBuildAdversarialTests`). Both belong to the chore the ruling names.

### The references

Recorded again, all this slice's own and none on `main`: the six of
`stepperField_appearance_matchesReference` (light and dark at large, xLarge and accessibility3) and the four
that hold the three controls together (`formControls_increasedContrast…` light and dark,
`formControls_pressed…`, `formControls_accessibility5…`). Only the stepper's last field differs in them: "Top
of range 12" is faint. Compared against the old references before recording, one cell failed
(`stepperField` dark-accessibility3); the other nine were within the tolerance and were recorded all the
same, so that no reference shows the old look. The six screenshots in `screenshots/s8/` that show the stepper
were copied again.

**Not recorded again: the design gallery's reference.** It is on `main` in its older form and was recorded
once by this slice; its `StepperField` section holds the same disabled field, now faint, and the test still
passes against the reference within the tolerance. The round's instruction allows only references that are
not on `main`, so it is left: it shows the old look of one field's text until the gallery is next recorded.
For the orchestrator to rule.

### Mechanical edits to the tester's files

For the two removed names (N-2, N-3), the smallest edit each; no expectation of the tester's reading changed.

| File:line | Edit |
|---|---|
| `Tests/FeatureProgramTests/Adversarial/ExercisePickerAdversarialSupport.swift:150-151` | `row.spokenLabel` → `row.name`, `row.spokenValue` → `row.line` in the line the model is printed as (the tester's own reading at `:130` prints the name and the line there) |
| `ExercisePickerModelAdversarialTests.swift:51` | `ExercisePickerAction.search(…)` → `ExercisePickerAction.setQuery(…)` |
| `ExercisePickerWordsAdversarialTests.swift:59` | `#expect(row?.name == name && row?.spokenLabel == name)` → `#expect(row?.name == name)` |

For the tester: its notes on the changes that survived every test still hold (`guard isEnabled` in the
adjustable action; the switch's `accessibilityRepresentation`; a finger's tap). None was changed in this
round: they were not among the rulings.

### Product lines now

| File | After the slice | Now |
|---|---|---|
| `LedgerDesign/Components/StepperField.swift` | 95 | 96 |
| `LedgerToggleStyle.swift` | 96 | 96 |
| `WrapLayout.swift` | 84 | 84 |
| `Components+Previews.swift`, `Gallery/DesignGallery.swift` (added) | 18 | 18 |
| **Part one** | **293** | **294** |
| `FeatureProgram/Picker/ExercisePickerInput.swift` | 11 | 11 |
| `ExercisePickerModel.swift` | 57 | 55 |
| `ExercisePickerAction.swift` | 13 | 10 |
| `ExercisePickerPresentation.swift` | 109 | 107 |
| `ProgramCopy+Picker.swift` | 99 | 103 |
| `DayEditor/DayEditorAction.swift`, `ProgramCopy+DayEditor.swift` (added) | 7 | 7 |
| `ProgramCopy.swift` (the helper; four lookups) | 123 → | 144 (+21) |
| `ProgramCopy+Days.swift` (one lookup over six lines) | 73 → | 78 (+5) |
| **Part two** | **296** | **319** |
| **The slice** | **589** | **613** |

`WrapLayout.swift` reads 84 where the slice's table said 75: the formatter put the gallery's lists over more
lines when they became `nonisolated`, before the slice's last commit; the table was not counted again then.
The reviewer's 592 is the same tree counted from the diff.

### The runs

All on 2026-10-08, in the worktree; simulator commands through the lock.

- Host, `swift test --only-use-versions-from-resolved-file --filter 'FeatureProgramTests|ModuleCopyTests'` in
  `LedgerKit`, on the final sources: `FeatureProgramTests` 316 tests in 30 suites passed, the tester's plural
  test among them, unedited; `ModuleCopyTests` 6 passed. Before the last form of the helper the same run
  failed twice, which is how the two other forms were ruled out (see "Where it stands").
- Simulator, `xcodebuild test … -testPlan PR -only-testing:LedgerDesignTests`, four times. First: the build
  failed (the probe layout of the new zero-proposal test was main-actor isolated; fixed). Second, against
  the old references: 377 tests, 2 failed: the tester's `oneStepOff_isSpokenAsSuch` and `stepperField` at
  dark-accessibility3. Third, with the ten references deleted: they were recorded. Fourth: 377 tests, 369
  passed, 1 failed (`oneStepOff_isSpokenAsSuch`), 1 skipped, 6 known issues. `git status` then showed the ten
  references and nothing else among the images.
- `scripts/check.sh`, the full gate, on the two commits: **exit 65 after 418 s, at the iOS test plan, by the
  one test criterion 15 leaves to the tester.** Lint, the iOS build and the string catalogs passed
  (`FeatureProgram` 125 keys). iOS: 3,341 tests, 3,313 passed, 1 failed
  (`StepperFieldAdversarialTests.oneStepOff_isSpokenAsSuch`), 14 skipped, 13 known issues. The gate stops
  there, so its watchOS and coverage steps did not run.
- Those two steps by hand, with the gate's own commands (`build-for-testing` and `test-without-building` of
  scheme `LedgerWatch`, plan `PR-Watch`; `scripts/check-test-results.sh`; `scripts/coverage-gate.sh` on both
  bundles), 248 s: watch build exit 0; watchOS 2,261 tests, 2,242 passed, none failed, 14 skipped, 5 known
  issues; the results check exit 0; the coverage gate exit 0 (`FeatureProgram` 1,547 / 1,547 lines,
  `LedgerDesign` 2,638 / 2,735, 96.45 %; overall 98.58 %). So the full gate is not green as one run: it
  will be once the tester's test is replaced.
- `scripts/check.sh --fast`: exit 0, "check.sh (--fast) OK", 118 s (`LedgerDomainTests` 1,222 passed,
  `LedgerPersistenceTests` 552 passed with 1 known issue).
- No source was edited after these runs; this section was written after them.
- **Not run:** the nightly lane; a device. The round's changes were not checked by breaking the code, bar
  criterion 14, whose test failed before the change (the tester's run) and passes after it.

### Fix round 1, addendum: the gallery's reference (orchestrator's ruling, 2026-10-08)

Ruled after the round's report: the design gallery's reference is recorded again, so that it shows the
disabled field as it is now drawn. Only `__Snapshots__/DesignGalleryTests/designGallery_dark_matchesReference.dark-large.png`
changed (`git status` after the runs: that one file).

Against the reference of commit `96f4187`, measured with a script written for this (CoreGraphics, both files
decoded to 8-bit sRGB, compared pixel for pixel at the same place; not in the tree), `swift gallery-rows.swift
<96f4187's> <new>`: "old 402 × 8176, new 402 × 8176 … rows that differ: 30 of 8176, in runs [7345...7357,
7368...7384]; columns 26…92; pixels 643; largest channel difference 167". The same size and no shift. The two
runs of rows are, by eye on a crop of rows 7230 to 7410, the label "Top of range" and the value "12" of the
`StepperField` section's last, disabled field, which stand at the content's leading edge (column 26); they
are faint now. Nothing else in the image differs, not by one level.

Runs, through the lock: `xcodebuild test … -testPlan PR -only-testing:LedgerDesignTests`, twice. First, with
the reference deleted: 377 tests, 2 failed, the gallery's (recorded) and the tester's
`oneStepOff_isSpokenAsSuch`. Second: 377 tests, 369 passed, 1 failed, the tester's. No gate was run after
this commit, as ruled.

## Slice S8 — adversarial testing, round 2 (G2 tester, 2026-10-08)

Tested `7e0440a` in the worktree. No product code changed. **No test is left failing.** Six new tests, one
replaced; no new defect; two notes on criterion 14's fix that are not defects today. Paths under `LedgerKit/`.

### What was done

1. **Criterion 15.** `StepperFieldAdversarialTests.oneStepOff_isSpokenAsSuch` is replaced by
   `switchedOffSteps_areDrawn_andSpokenOnlyWhenTheFieldIsOff`: with one step off the field is handed to
   VoiceOver exactly as with both on (label, value, the adjustable trait alone, no hint, no custom action),
   is drawn unlike it, and its text is as strong; with no step, or disabled, the traits are adjustable and
   not enabled and the two are one drawing, unlike the live one.
2. **The three mechanical edits to my files: none weakened a check.** `Row.spokenLabel` and `.spokenValue`
   no longer exist, so there is nothing left to hold them to; `name` and `line` were and are compared on the
   same line. The two columns the edit left printing `name` and `line` a second time are taken out of both
   sides of `AdvPicker`'s reading (they compared a field with itself). `.setQuery` for `.search` is the same
   action. `ExercisePickerWordsAdversarialTests.swift:59` keeps the name's check.
3. **Criterion 14**, new suite `ProgramCountedTextAdversarialTests` (5 tests, host):
   - 37 locales (no identifier, `und`, unknown languages, scripts, `@numbers=`, `@calendar=`, `@rg=`,
     `@currency=`, POSIX, Arabic, Persian, Devanagari, Burmese and Thai digits, Welsh, Irish, Slovenian and
     Lithuanian plural rules): `addExercises` and `sets` at 1, 2, 3, 5, 11, 21, 101 and 999, and `days(0)`,
     `weeks(0)`, are English's form with the count in the locale's own digits; the locale used is English with
     the lifter's region, numbering system and calendar, and the same locale in gives the same out.
   - A region's grouping is kept: en_IN and hi_IN "12,34,567", de_DE, de_CH, fr_FR, ar_EG, fa_IR.
   - `countedLookups_allGoThroughTheOnePlace` reads every `ProgramCopy*.swift` of the module (over 100
     lookups): each lookup of one of the catalog's 11 counted keys passes `locale: locale.forCountedText`,
     no other lookup does, and each counted key is looked up.
   - `forCountedText_readsNothingAmbient`: the helper's body names no current locale, preferred languages,
     defaults or main bundle, and its preferences are its own locale alone; there is one such helper.
4. **Criterion 16**, `StepperFieldAdversarialTests.disabledField_labelAndValue_areEachFaint`: the label alone
   and the value alone, light and dark, with and without Increase Contrast: disabled is under 0.8 of the live
   text's contrast against the ground, still at least 1.5:1, and equal to a field with no step.

### Can the tests fail

Each change made in place, the tests run, the file restored from a copy outside the tree and compared.

| Change | Fails theirs | Fails mine |
|---|---|---|
| One counted lookup (`sets`) with the lifter's locale again | `ProgramCopyTests` | counted texts |
| The numbering system not carried over | `ProgramCopyTests`, `ExercisePickerPresentation` (+ properties) | counted texts, the library's model and words |
| The region not given to the language | `ProgramCopyTests` | counted texts, the library's words |
| The helper returns the locale it was given | `ProgramCopyTests` | counted texts, the library's words |
| A lookup that is not counted sent through the helper | no | counted texts (the source scan) |
| A disabled field's label and value both at full strength | `disabledField_drawsItsTextFaint`, one reference | `disabledField_labelAndValue_areEachFaint` |
| Only the value left strong; only the label left strong (two runs) | yes, each | yes, each |
| A field with no step not dimmed (`isLive = isEnabled`) | yes | both of my two tests |

So criterion 16's test can fail, for the label and for the value each.

### The two consequences the implementer names

- **`days(0)` under fr_FR is "0 days": not a defect.** The words are English, and English counts none as
  many; it is criterion 14 as ruled. "0 day" was the bug's other face.
- **fr_CA groups four-digit counts the English way: not a defect in use, and wider than stated.** Up to 999
  every one of the 37 locales writes the count exactly as the lifter's own locale does. From 1,000 on, these
  differ from the lifter's own writing (measured at 1,234, 12,345 and 1,234,567): fr_CA ("1 234" becomes
  "1,234"); es_ES, it_IT, pl_PL, pt_PT, hu_HU, bg_BG (their own "1234" becomes grouped, and pl_PL's "12 345"
  becomes "12.345"); `und`, unknown languages and en_US_POSIX (ungrouped becomes "1,234"). Grouping that is
  the language's and not the region's is lost with the language. No count of the module reaches four digits
  (weeks, days, sets, exercises, a day's minutes), so nothing is seen. A note for the chore that takes the
  helper to the other modules: a count that can pass 999 would show it.

### Notes on the helper, by reading and by its arithmetic

- **F11-S8-N1 (latent, not reachable while the catalog holds one language).** The helper answers "the
  catalog's language that fits the injected locale"; the words come from the language the bundle chose from
  the device's languages. With two languages in the catalog the two can part (an injected fr_FR on a device
  the bundle answers in English: English words, French plural rule, the bug of F11-S8-1 again). The
  implementer's "known limit" says the same; the helper's comment ("the language the catalog answers in")
  says more than it does. To settle when a second language is added.
- **F11-S8-N2 (not established).** `Bundle.preferredLocalizations(from:forPreferences:)` with no match (a
  Russian preference) answered "en" for the lists ["en", …], ["fr", "en"] and ["de", "en", "fr"], and the
  list's first, "fr", for ["fr", "ja"]. Whether "en" is chosen there by a rule or because the host runs in
  English could not be told on this machine; if the latter, the helper reads the device after all in that
  one case. With one language in the catalog the answer is that language either way.
- en_US_POSIX applied twice comes back spelled another way (`va=posix` as a keyword); its texts are right.

### Not attacked

A catalog with a second language, run (read only, above). `FeatureToday`'s and `LedgerAppKit`'s counted
texts (the ruled chore). The gallery's re-recorded reference beyond its test passing. A finger's tap
(F11-S8-3, for S14). The watch.

### The runs

All on 2026-10-08 in the worktree; simulator commands through the lock (iPhone 17, 27.0).

- Host, `swift test --only-use-versions-from-resolved-file --filter 'FeatureProgramTests|WrapLayout'`:
  `FeatureProgramTests` 321 tests in 31 suites passed; `WrapLayout` 15 tests in 2 suites passed.
- Simulator, `xcodebuild test … -testPlan PR -only-testing:LedgerDesignTests`: exit 0, 378 tests, 371
  passed, none failed, 1 skipped, 6 known issues.
- Four more such runs and five host runs with the changes of the table, each restored. No reference
  recorded or changed.
- `scripts/check.sh --fast`: exit 0, "check.sh (--fast) OK", 115 s; lint clean.
- **Not run:** the full gate, the watch plan, the nightly lane.

## Slice S9 — the builder's and the library's views (G1 implementer, 2026-10-09)

Branch `feat/F11-s9-builder-library-views`, cut from `main` at `407c99a`. The plan's S9 and S12 as one slice:
the views of the Program builder and of the exercise library sheet, drawn from the two models that are on
`main`. No store, nothing in the app, no change to `LedgerAppKit`, the project file or a test plan. **No
presentation, model, action or copy file was changed, and no key was added to the catalog.**

### What landed

Product, all in `LedgerKit/Sources/FeatureProgram/Views/` (why there: deviation 1):

| File | What it is |
|---|---|
| `ProgramScreen.swift` | The builder: `ScrollView { ProgramPage }` on the ground. Nothing pinned. |
| `ProgramPage.swift` | Everything the builder scrolls: header, block, selected week, training days, `xxl` apart. |
| `ProgramHeader.swift` | "MY PROGRAM" over the name as a one-line field in the title's type, with its draft. |
| `SectionLine.swift` | A section's first line: the eyebrow (a heading) and a trailing part (a muted note, or "−" "+"); stacked at accessibility sizes. |
| `BlockSection.swift` | "BLOCK · 8 WEEKS", "−" and "+" as one adjustable element, the chips, the notice. |
| `WeekChips.swift` | One two-line pill per week in `WrapLayout`. |
| `WeekSection.swift` | The week's title and "Tap to assign", the strip, the three actions in `WrapLayout`; `ControlPill` (a `Control` as an outlined pill, disabled without an action). |
| `ScheduleStrip.swift` | Seven cells in one row while they fit, wrapped when they do not. |
| `TrainingDaysSection.swift` | "TRAINING DAYS" with the summary, the helper, the rows, "+ Add training day". |
| `DayCard.swift` | One day: a hairline row that is one button. |
| `ExercisePickerScreen.swift` | The sheet: `SheetChrome`, the pinned `ExerciseSearchField`, `ScrollView { ExercisePickerPage }`, the pinned `ExercisePickerFoot`. |
| `ExercisePickerPage.swift` | What the sheet scrolls: the two chip rows, then the rows or "Nothing matches that filter." with "Clear filters". |
| `FilterChips.swift` | One row of `PillButton`s in `WrapLayout`. |
| `ExercisePickerRow.swift` | `HairlineRow` as one button, with the pick mark as its accessory. |
| `Program+Previews.swift` | `ProgramPreview`, the module's one registry: eight cases, eight `#Preview`s, the fixed inputs. |

Two one-line registrations: `LedgerKit/Package.swift` (`snapshotTestTargets` gains `FeatureProgram`) and
`LedgerTestSupport/Previews/PreviewScan.swift` (`registeredModules` gains it).

Tests, in `LedgerKit/Tests/FeatureProgramTests/`: `ProgramSnapshotTests.swift`,
`ProgramAccessibilityTests.swift` with `ProgramAccessibilityTrees.swift`, `ProgramTextFieldTests.swift`,
`ProgramScreenTests.swift`, `ProgramViewsLayoutTests.swift`, `ProgramOrangeAuditTests.swift`,
`ProgramViewsSourceTests.swift`, `PreviewTests.swift`; support in `Support/ProgramParts.swift`,
`Support/ProgramViewStops.swift`, `Support/ProgramDrawing.swift`; `Support/ProgramTesting.swift` gains the
`snapshot` tag. 28 references in `__Snapshots__/ProgramSnapshotTests/`. Copies for Pete in
`tasks/features/F11-program-builder/screenshots/s9/` (28 files, named state-theme-size).

### The VoiceOver trees (confirmed; `ProgramTrees` pins them)

- **Builder.** "MY PROGRAM", heading. *(The name field: see "Text fields" below.)* "BLOCK · 8 WEEKS", heading.
  "Block length", adjustable, value "8 weeks". One button per week: "Week 1", value "4 days" or "Deload",
  selected when it is. The notice, when there is one, as text, here. "WEEK 1" or "WEEK 8 · DELOAD", heading.
  "Tap to assign", text. Seven buttons: "Monday", value "Upper A" or "Rest", hint "Double-tap to assign".
  "First week" (dimmed) or "Copy week 7"; "Apply to later weeks" (absent on the last week); "Deload",
  selected when on. "TRAINING DAYS", heading; "4 days · 58 sets a week"; the helper line. One button per
  day: "Upper A — Push focus", value "5 exercises · 18 sets · ~39 min"; the short names and the tag are not
  read. "+ Add training day". In a program with no training day a weekday is text ("Tuesday", value "Rest"),
  with no hint, and "Tap to assign" is absent.
- **Exercise library.** "Exercise library", heading. "Cancel". *(The search field.)* Six buttons "Muscle: All"
  … "Muscle: Arms", one selected; six "Equipment: All" … "Equipment: Bodyweight", one selected. One button
  per exercise: "Lat Pulldown", value "Cable · Back · already in this day", selected when picked. Or
  "Nothing matches that filter." as text and "Clear filters". Then the foot: "Add 3 exercises", or
  "Select exercises to add", dimmed. VoiceOver's escape gesture cancels (`SheetChrome`'s).

The same trees at `.large` and at `.accessibility3`, with Bold Text and right to left.

**Text fields: a limit of the hosted reader, new with this slice.** In a package test process UIKit does not
make a `UITextField` an accessibility element (measured on iOS 27.0: `isAccessibilityElement` is false with
the automation switch on), so `accessibilityElements` passes a one-line `TextField` **in silence**: unlike a
scroll view, nothing is recorded. The two fields are therefore in no pinned tree. What is pinned instead,
through UIKit (`ProgramTextFieldTests`): each screen has exactly one field, with its placeholder ("Program
name", "Search exercises") and its text; and `fields_areNotReadByTheHostedReader` fails when the reader
learns to read one. A hosted field also takes no typing from a test (text set on it is put back; no key
reaches it). So two things wait for the UI tests of S13 and S14: that VoiceOver reads the fields by their
labels, and that typing sends `.rename` and `.setQuery`. *For the orchestrator:* the reader's silence here is
worth a line in testing-strategy §2.6 beside the multi-line limit; I did not edit the docs.

### Decisions and deviations

1. **Every view file is in `Views/`, the sheet's and the previews file too**, not in `Picker/` and at the top
   level as the plan's rows have them. Two testers' scans collide with those places and I may not edit them
   unasked: `ExercisePickerWordsAdversarialTests.sources_readNothingAmbient` pins the files of `Picker/` to
   S8's five, and `ProgramWordsAdversarialTests.sources_holdNoCopyOutsideTheCopyFiles` allows no string
   literal in a top-level file (a previews file's names are literals). Both read one folder and not its
   subfolders. FeatureToday keeps its sheet's views in `Views/` as well. The orchestrator was told by
   message. The plan's places need two mechanical edits to those tests (four names in the list;
   `+Previews.swift` skipped). **S10/S11 meet the same** with `DayEditorWordsAdversarialTests` (it reads
   `DayEditor/`).
2. **The name field keeps its draft in the view** (`@State` in `ProgramHeader`), where S5's notes have the
   store keep it. The page then takes only `model` and `send`, as criterion 2 writes it. The rule: the draft
   starts as the stored name; a change that leaves it other than the stored name sends `.rename(text)`; when
   the field loses focus, or the stored name changes while it has none, the draft takes the stored name. S13
   may lift the draft into the store by giving `ProgramHeader` a binding: one parameter.
3. **The name field is one line**, so a name longer than the line ends in "…" while it is not being edited
   (the reference `sixteenWeeks`). A field of several lines is a text view, which the reader cannot host
   (F8-S2-8). Open question 1.
4. **The search field is bound to the model's query through `.setQuery`** (S8's first option): no draft.
5. **The strip changes from one row to wrapped rows by fit** (`ViewThatFits`), not by the text size's class.
   A program with long tags wraps earlier instead of cutting them. Pinned, with the seed program: one row
   at `.large` (402 and 375 pt), wrapped at `.accessibility3`; no fault at `.xxxLarge` or `.accessibility5`.
6. **The strip's targets touch** (`HStack(spacing: 0)`), and what is drawn stands `xs` inside each, with the
   strip set `xs` out on both sides. With a gap between targets a cell would be 42.7 pt wide on a 375 pt
   phone.
7. **"Nothing matches" is not `EmptyState`** (S8's notes suggest it): that component needs a title and a
   body and makes the title a heading; the model has one sentence. It is that sentence in `bodyLight` over
   an outlined pill.
8. **A library row is `HairlineRow`**, with the label, value and selected trait set from outside it. The
   whole `line` is drawn in the row's detail grey, so "already in this day" is grey and not apart;
   `detail`, `inDayMark` and `pickMark` are not used by any view.
9. **Criterion 1's "takes its part of the model":** `ExercisePickerPage` takes the whole model, as the
   criterion's own `ExercisePickerPage(model:)`, and reads `muscles`, `equipment` and `content`.
10. **No shared component was added.** Proposed, not built: (a) `SectionLine` is FeatureToday's
    `CardEyebrowLine` with any trailing view; one of them could move to `LedgerDesign`. (b) A two-line pill
    (the week chip) and (c) a small non-interactive tag pill (the day's tag, the short names) are
    feature-local here; S10/S11 may want (c). (d) `LedgerPressStyle` is internal to `LedgerDesign`, so the
    three buttons a feature draws itself (week chip, strip cell, day row) use `.buttonStyle(.plain)`; making
    the press style public would give them the components' pressed look.

### Looks the prototypes do not settle (for Pete; all in the screenshots)

Decision 1 A says "the dark design's language"; the dark design never drew these screens. Each choice:

1. **No cards.** The builder is flat on the ground; the days are hairline rows, as Today's "RECENT".
2. **The program's name** is the screen's title (the 32 pt title role), editable in place. The old design's
   gear button beside it is not drawn: the model carries no Settings route for it (Today has the gear).
3. **"−" and "+"** are F06's round outlined 44 pt buttons, at the trailing edge of "BLOCK · 8 WEEKS".
4. **A week chip** is a two-line pill, "W3" over "4 DAYS"; the selected one is filled with ink, as a selected
   filter. Eight make two rows of four and leave room at the trailing edge; they do not stretch.
5. **Orange in the builder** is one thing at a time: "DELOAD" under the deload week's chip while another week
   is selected; while the deload week is selected its chip is ink (orange on the ink fill is 2.8:1 and
   3.0:1, below AA) and the title "WEEK 8 · DELOAD" is orange, whole. The title is one string of the model
   and is not split. If only the word should be orange there, the model needs the mark as a second field.
6. **A strip cell** is a tall pill: a training day's has the quiet fill (the disabled button's) and its tag in
   ink; a rest day's is an outline with "REST" in grey. No cell is ink-filled: four white blocks in a row
   read as four selected things.
7. **The week's actions** are three outlined pills that wrap; "Deload" is filled with ink while on, not
   orange. "First week" is the disabled pill.
8. **The notice** stands under the week chips in ink (not orange, not red), for all three notices.
9. **A day's row**: the tag in a small quiet-fill pill (the strip's look for that day), the name, the meta
   line, the short names as small outlined chips, a chevron (none at accessibility sizes, as Today).
10. **"+ Add training day"** is an outlined pill at the leading edge, not the old full-width dashed box.
11. **The sheet**: the search field is an outlined 44 pt pill; both chip rows use the same pill (the old
    design drew the equipment row smaller); "Arms" and "Bodyweight" wrap to a second line on an iPhone 17.
12. **A library row's mark**: a plus in an outlined circle; picked, a check on an ink-filled circle. The
    pick's number ("2") is in the model and is not drawn (open question 3). A picked row has no other mark.
13. **The foot** is a rule over the orange button; disabled it is the grey `PrimaryButton`.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 1 Drawn from the model only | `ProgramViewsSourceTests.views_decideNothing`, `views_importOnlySwiftUIAndTheDesignSystem`; `ProgramAccessibilityTests.builder_buttons_sendTheirModelsActions` (5 states), `builder_seedProgram_sendsTheBriefsActions`, `blockStepper_adjusts`, `noDays_cellsAreText`, `library_buttons_sendTheirModelsActions` (3 states), `library_picked_sendsTheBriefsActions`; the copy audit (`LedgerAppKitTests.ModuleCopyTests`) reads the views for literals. |
| 2 Both screens scroll as the convention says | `ProgramScreenTests` (4): one scroll view per screen in every state, none in the parts, nothing pinned on the builder, the sheet's list between its pinned parts; `ProgramViewsSourceTests.onlyTheScreens_holdAScrollView`. |
| 3 The builder, 4 the sheet | The trees and the references below; `ProgramViewsLayoutTests.weekChips_wrapIntoRows`, `scheduleStrip_defaultSize_isOneRowOfEqualTargets`, `scheduleStrip_accessibilitySize_wraps`, `filterChips_wrap`; `ProgramTextFieldTests.builder_nameField_holdsTheName`, `library_searchField_holdsTheQuery`, `nameField_withoutFocus_followsTheStoredName`, `nameField_withFocus_keepsItsDraft`. |
| 5 Previews and snapshots | `PreviewTests` (5); `ProgramSnapshotTests`: builder 6, deload week 2, empty day 2, two-weeks message 2; library 6, three picked 2, nothing matches 2 (the table's 22), plus sixteen weeks 2, right to left 2, Increase Contrast 2. |
| 6 VoiceOver | `ProgramAccessibilityTests.tree_isExactlyTheTable` (8 states × 2 sizes), `targets_areAtLeast44Points`, `headings_areTheSectionTitles`; `ProgramTextFieldTests.fields_areNotReadByTheHostedReader`. |
| 7 Sizes and settings | `ProgramViewsLayoutTests.parts_layOutSanely` (8 states × 16 settings: `.large`, `.xxxLarge`, `.accessibility3`, `.accessibility5`, each plain, bold, right to left, both), `parts_everySetting_readTheSameStops`; the references at `.accessibility3`, of sixteen weeks, right to left and under Increase Contrast, which I looked at. A word cut inside its own frame is visible only there. |
| 8 The orange audit | `ProgramOrangeAuditTests` (5, both themes): by the hue of the pixels each part draws. |
| 9 No rule of its own | `ProgramViewsSourceTests`; the lint (`ledger_raw_*`); deviation 10. |

**Checked by breaking the code** (six changes, each made and undone): a week chip without its spoken value
(`tree_isExactlyTheTable` fails in all five builder states); the deload chip's "DELOAD" in grey
(`builder_orangeIsTheDeloadChip`, both themes, and the builder's references); the strip inside a sideways
scroll view (`onlyTheScreens_holdAScrollView`, the trees, the 44 pt and row tests; it also showed
`builder_seedProgram_sendsTheBriefsActions` trapping on a short list, which now requires the count first); a
library row without the selected trait (`tree_isExactlyTheTable`, three picked); a gap between the strip's
targets (`scheduleStrip_defaultSize_isOneRowOfEqualTargets` on 375 pt, and the references); the name field
not following the stored name (`nameField_withoutFocus_followsTheStoredName`).

### Product lines per file

Non-blank, non-comment: `BlockSection` 34, `DayCard` 65, `ProgramHeader` 41, `ProgramPage` 16,
`ProgramScreen` 14, `ScheduleStrip` 70, `SectionLine` 31, `TrainingDaysSection` 22, `WeekChips` 46,
`WeekSection` 33 (**builder 372**); `ExercisePickerPage` 28, `ExercisePickerRow` 29, `ExercisePickerScreen`
55, `FilterChips` 14 (**library 126**); `Program+Previews` 111. **609 in `Views/`**, plus one changed line in
each of `Package.swift` and `PreviewScan.swift`. Planned about 670.

### Text not given by the brief

None is drawn or spoken: every text on both screens is a string of a model. The preview names and the
previews' long program name ("Upper / Lower with an accessory day, autumn block before the meet") are
Debug-only.

### Open questions, each with a recommendation

1. **A program name longer than one line is cut with "…"** while it is not being edited. *Recommendation:*
   accept for M1; names are short, and the whole name shows while editing. The alternative is a field of
   several lines, which needs the reader's limit F8-S2-8 lifted first.
2. **"WEEK 8 · DELOAD" orange as a whole, or only its last word** (look 5). *Recommendation:* whole, as built
   and as the Day editor's week line is planned; one model field if Pete prefers the word alone.
3. **The pick's number on a picked row, and whether VoiceOver says a pick's place** (S8's question for this
   table). *Recommendation:* neither: the check and the selected trait, as built. The exercises are added
   in the order picked and can be moved in the Day editor. Drawing "2" in the mark is a three-line change.
4. **"Deload" for a deload week's chip and "Double-tap to assign"** (S5's two questions for this table) are
   read as the model has them. *Recommendation:* keep both.
5. **The helper line at accessibility sizes** takes four lines. *Recommendation:* keep; it is the only
   explanation of how days and weeks relate.
6. **File places** (deviation 1): orchestrator's call.

### Inputs for S10 and S11 (the Day editor's views)

- The form to follow is this slice's: `XScreen` = pinned parts + `ScrollView { XPage(model:send:) }`; a
  `Parts` view in the tests; `ProgramPreview` gains the Day editor's cases (one registry for the module) and
  `ProgramParts`/`Subject` a third screen. `ProgramPreview.builders` and `.libraries` are the lists the
  parameterised tests take; add `.dayEditors`.
- Reuse: `SectionLine` (eyebrow + trailing), `ControlPill` (it takes the builder's `Control`; the Day
  editor's control type needs its own or a shared shape), `ViewStop`/`firstDifference`/`placedStops`
  (`Support/ProgramViewStops.swift`), `ProgramViewsLayoutTests.faults(in:)` and `rows(of:)`,
  `ProgramDrawing.orangePixels` (it renders the layer; `ImageRenderer` draws a text field as a yellow
  placeholder and `drawHierarchy` draws nothing without a host app).
- **The day's name is a text field**: it is not in the hosted tree (above); pin it as
  `ProgramTextFieldTests` does, and copy `ProgramHeader`'s draft rule.
- `HairlineRow` takes `.accessibilityLabel`, `.accessibilityValue` and `.accessibilityAddTraits` from
  outside and stays one button (measured here).
- A `PillButton` narrower than 44 pt stands inside its target, so the first pill of a wrapped row starts a
  few points inside the content's edge (`flush` cannot know which pill is first).
- `ProgramViewsSourceTests` reads every file of `Views/` but the previews: a Day editor view that spells
  `ScrollView` outside its screen file, or reaches for the copy, fails it. Add the new screen file to
  `screens`.
- Put the files in `Views/` unless the orchestrator rules otherwise (deviation 1).

### Inputs for S13 and S14 (the stores)

- `ProgramScreen(model:send:)` and `ExercisePickerScreen(model:send:)` are all a root needs: `send` is the
  store's one intent. Neither screen holds state but the name field's draft and the two fields' focus.
- **S13, the name:** the view sends `.rename(text)` on every change of the draft that differs from the stored
  name, a blank one too (the Domain ignores it). The store applies it at once, so `model.header.name`
  follows; the field does not take it back while it has focus. Nothing else is needed from the store.
- **S13, empty and failed states:** `ProgramScreen` takes a model, not a `Loadable`; the root draws
  `EmptyState` for "No program yet" and for the failed read (decision 6's texts are not in the catalog yet).
- **S13, the notice** is drawn under the chips and is not announced to VoiceOver when it appears; an
  announcement (`AccessibilityNotification.Announcement`) belongs with the store's change of `notice`.
- **S14:** the Day editor presents `ExercisePickerScreen` with `.sheet`; `SheetChrome` sets the sheet's
  background and corners. The search field's binding reads `model.search.query` and writes `.setQuery`, so
  the store must apply `.setQuery` synchronously or typing will lag. All rows are built at once (a `VStack`
  in `HairlineList`): 224 rows on open; S14's timing test should measure the first frame too.
- **The nightly UI tests** owe: the two fields' spoken labels; typing a name and a query; the stops inside
  the real scroll views at an accessibility size; a finger's tap on "−", "+", a chip, a cell and a row.

### The runs

All on 2026-10-09, in the worktree; every simulator command through the lock (iPhone 17 and Apple Watch
Series 12 46 mm, both 27.0). No source or test was edited after the full gate and the fast gate below;
these notes and the screenshots' copies were written while and after they ran.

- Simulator, `xcodebuild test … -testPlan PR -only-testing:FeatureProgramTests` (and, earlier, two suites
  alone), nine times: two to record the references and read the trees as built; three probes of how a hosted
  text field is seen (the limit above); two that did not compile (iOS-only test code the host build does not
  read: an isolation error, a slice compared with an array); the run that compared the new references and
  left one failure, a spelling of my own source test that also matched `ExerciseSearchField`; and two with
  the code broken on purpose (above). The references were recorded once in their final form, in the
  library's missing-reference mode, and compared by the next run and by the gate. No reference that was on
  `main` changed (`git status`: only new files under `FeatureProgramTests/__Snapshots__/`).
- **`scripts/check.sh`, the full gate, once, on the final sources: exit 0, "check.sh OK", 912 s** (lint 124 s,
  iOS build 24 s, iOS tests 455 s, watchOS build 47 s, watchOS tests 257 s). iOS: 3,568 tests, 3,541 passed,
  none failed, 14 skipped, 13 known issues. watchOS: 2,262 tests, 2,243 passed, none failed, 14 skipped, 5
  known issues. String catalogs: `FeatureProgram` 125 keys, as before. Coverage: `FeatureProgram` 2,265 /
  2,277 lines (99.47 %); overall 98.55 %.
- **`scripts/check.sh --fast`: exit 0, "check.sh (--fast) OK", 152 s.**
- `FeatureProgramTests` on the simulator: 369 tests in 39 suites (294 in 27 before this slice); this slice
  adds 48 test functions in 8 suites.
- **Not run:** the nightly lane (2,000 seeds, UI tests); a device; VoiceOver itself; the two screens in the
  app (they are in none). The twelve lines of `FeatureProgram` the coverage does not reach were not listed
  per file; by reading, they are the closures a hosted test cannot run (the two fields' tap-to-focus and the
  search field's binding setter, `@unknown default`).

## Slice S9 — review, round 1 (G3 reviewer, 2026-10-09)

Read: `git diff main...2f15f75` (the fifteen files of `Views/`, the eight test files and four support files,
the two registrations), the two models, the `LedgerDesign` components the views use, FeatureToday's
`CardEyebrowLine`, `RecentList`, `TodayScreen`, `OffScheduleSheet`, testing-strategy §2.5–§2.6, and 18 of
the 28 screenshots (list at the end). **Nothing was built or run** (the brief forbids it): every statement
about behaviour is from reading the code and the committed images; the implementer's gate figures are
taken as reported.

### Verdict: request changes — one blocking fault, small; the rest is approve with should-fix

The shape is right: two screens that are a scroll view around a page, parts that take a piece of the model
and `send`, no task, no ambient read, every text from the model, trees that match the tables. One thing on
screen is wrong and is pinned as a reference.

### Blocking

**B-1. "REST" is cut to "RE…" in the schedule strip at `.xLarge`, in both themes, and the references pin
it.** `screenshots/s9/builder-dark-xLarge.png` and `builder-light-xLarge.png` (the same files as
`__Snapshots__/ProgramSnapshotTests/builder_matchesReferences.{dark,light}-xLarge.png`): the three rest
cells read "RE…". Cause, `Views/ScheduleStrip.swift:20-27` with `:64` and `:67`: `ViewThatFits` takes the
one-row candidate when the **sum** of the cells' ideal widths fits, but the row then gives every cell an
**equal share** (`maxWidth: .infinity`), and the texts may shrink (`lineLimit(1)`); a cell whose ideal is
wider than a seventh is cut although the row "fits". Deviation 5's sentence "wraps earlier instead of
cutting them" is therefore not true between `.xLarge` and the first size at which the sum overflows, and
it will be worse on a 375 pt phone and in a language whose "REST" is longer. No test can see it:
`ProgramViewsLayoutTests.faults(in:)` reads frames, and `scheduleStrip_defaultSize_isOneRowOfEqualTargets`
runs at `.large` only. Proposed change (one of):
  - simplest: `.fixedSize(horizontal: true, vertical: false)` on the two `Text`s of `ScheduleCell.label`
    (`:57-62`). A cell's least width is then its ideal, the row hands a wide cell what it needs and shares
    the rest, and the row is chosen exactly when nothing is cut. Cells stay equal at `.large` (the existing
    test holds) and differ by a few points above it;
  - or, to keep the cells equal: a ten-line `Layout` for the first candidate whose ideal width is seven
    times the widest cell's, so `ViewThatFits` falls to the wrapped rows as soon as one cell would be cut.
  Either way add a test that fails today: at `.xLarge`, `.xxLarge`, `.xxxLarge` × 402 and 375 pt, each
  cell's frame in the strip is at least as wide as the same cell's in a strip given unlimited width; and
  re-record the two `.xLarge` builder references with the cause stated.

### Should-fix

- **S-1. The name field's rule is logic in a view, and its one sending path has no test.**
  `Views/ProgramHeader.swift:41-55`: three `onChange`s decide when a draft is sent and when it is thrown
  away. `ProgramTextFieldTests` pins two of the three (follows the stored name unfocused; keeps the draft
  focused, takes the stored name on blur); `if text != model.name { send(.rename(text)) }` (`:42-44`) is run
  by nothing, because a hosted field takes no typing. Accept the draft as view state for this slice (see
  deviation 2), but: (a) `ProgramBuilderModel.swift:17-20` still says "a view binds the field to a draft the
  store keeps"; correct the comment in this PR (a comment, not a presentation change) so S13 does not build
  the second draft; (b) write the debt into S13's criteria by name: "Upper Lower" typed letter by letter
  stores "Upper Lower" (S5 review S-3), a blank draft sends and is ignored, blur restores the stored name;
  as a UI test, since no hosted test can.
- **S-2. Crowding at accessibility sizes in the two pills this slice draws itself.**
  `builder-dark-accessibility3.png`: in the wrapped strip "REST" spans its outline edge to edge
  (`ScheduleStrip.swift:65`, 4 pt of side padding inside a capsule), and a week chip's second line ("4
  DAYS", "DELOAD") sits on the capsule's lower curve (`WeekChips.swift:39-40`). Nothing is cut, so criterion
  7 holds by the letter, but both read as tight beside `PillButton`. Proposed: in the wrapped branch give
  the cell `LedgerSpacing.m` at the sides (`fillsItsShare == false`); give the week chip `LedgerSpacing.m`
  vertically at accessibility sizes, or a rounded rectangle there instead of a capsule.
- **S-3. The search field has no vertical padding.** `Views/ExercisePickerScreen.swift:47-52`: the pill is
  `ledgerHitTarget`'s 44 pt and nothing more; in `library-dark-accessibility3.png` the text all but fills
  it, and at `.accessibility5` the line is taller than 44 pt and will touch the outline. Add
  `.padding(.vertical, LedgerSpacing.s)` before `ledgerHitTarget`. No test sees this (the field is in no
  tree and `faults` has no field to measure, see N-5).
- **S-4. The hosted reader should be loud about a text field, in `LedgerSnapshotTesting`, not per
  feature.** The UIKit pin is sound for what it claims (one `UITextField` per screen, its placeholder and
  text, and a canary that fails when the reader learns to read one), and it is honest about what it does
  not claim (the spoken label, typing). But §2.6's principle is "the reader is loud", and a field is passed
  in silence: S10/S11 (the day's name) and F12 will each need to remember the canary. For the orchestrator,
  as a chore before S10: the reader's walk fails on a `UITextField` unless the caller opts in (as
  `outsideScrollViews:`), or records a `.field` stop from its placeholder and text; and testing-strategy
  §2.5 gains the sentence beside the scroll-view limit: "A one-line `TextField` is no accessibility element
  in a package test process (measured iOS 27.0, F11 S9): pin it through UIKit (`ProgramTextFieldTests`);
  its spoken label and typing are the nightly UI test's." Not this PR's to fix; the sentence is.
- **S-5. The check mark is mirrored right to left.** `rightToLeft-library-dark-large.png`: a picked row's
  mark has its short arm on the right. `LedgerIconShape` is a `Shape`, which SwiftUI mirrors with the
  layout; right for the chevron, wrong for a check (and for `SetRow`'s, `LedgerDesign/Components/
  SetRow.swift:175`). A `LedgerDesign` fault this slice's reference now pins: fix it there in its own
  chore (`LedgerIconView` un-mirrors `.check`), then re-record; do not fix it in `PickMark`.

### Nits

- **N-1.** `Views/DayCard.swift:33,56`: the chevron stands at the row's top (`alignment: .top`); Today's
  rows centre it (`HairlineRow`). Deliberate for a row with chips, or not? Say so in the comment, or centre
  the chevron alone (`.frame(maxHeight: .infinity)` is not needed: `alignmentGuide` on the chevron).
- **N-2.** `Views/SectionLine.swift:16`: `.center`, where `CardEyebrowLine` uses `.firstTextBaseline`. With a
  note the two texts should share a baseline as on Today; with the stepper, centre. Take the alignment as a
  parameter defaulting to the baseline, `.center` from `BlockSection`.
- **N-3.** `Views/ExercisePickerScreen.swift:65-66` with `HairlineList`'s closing rule: two rules 8 pt apart
  above the foot whenever the list is at its end (`library-dark-large.png`, bottom). Drop the foot's rule
  or the list's closing one on this sheet.
- **N-4.** `Views/FilterChips.swift:12`: "All" (narrower than 44 pt) starts 3 pt inside the edge that
  "Arms" and "Bodyweight" stand on in the next line, and a chip row's own second line is as far from its
  first as the other row is. The two rows are hard to tell apart once each wraps (`library-dark-large.png`).
  Raise the gap between the rows to `l`; the 3 pt is `PillButton`'s to solve (a `flush` that the layout
  sets), later.
- **N-5.** `ProgramViewsLayoutTests.swift:54` counts `.field` as a target, but no field is ever read, so the
  44 pt of the two fields is pinned nowhere. Either measure the SwiftUI frame around the `UITextField` in
  `ProgramTextFieldTests` (its superview's height) or delete `.field` from the check and say so.
- **N-6.** `Views/ScheduleStrip.swift:80-90`: `spokenHint` switches the view's branch on an optional. The
  model gives a hint exactly when it gives an action (`ProgramPresentation+Weeks.swift:99`), and the button
  branch is the only caller: `accessibilityHint(cell.spokenHint ?? "")` or a non-optional hint on an
  actionable cell would remove the helper. Small; a model change, so later.
- **N-7.** `ControlPill` lives in `WeekSection.swift:32` and is used by `TrainingDaysSection.swift:23` and
  promised to S10; give it its own file when S10 touches it.
- **N-8.** `ExercisePickerScreen.cancel` (`:27-30`) is copied in the tests' `ExercisePickerParts`
  (`Support/ProgramParts.swift:45-47`); the real one is activated by no test. The convention allows the
  copy (onboarding's does the same); one hosted test with `outsideScrollViews: true` that activates
  "Cancel" and the foot on the real `ExercisePickerScreen` would close it.

### Criteria

| # | Verdict | Evidence |
|---|---|---|
| 1 Drawn from the model only | **Met**, with S-1 | Parts take a model piece and `send` (`ProgramPage.swift:16-19`, `ExercisePickerPage.swift:14-27`). No format, filter, count, clock or locale in `Views/` (read; `ProgramViewsSourceTests.views_decideNothing`). Every `Text`/title is a model string. The decisions a view does make: the draft's rule (S-1), `model.deload.isOn ? .accent : .muted` (`WeekSection.swift:16`), `cards.isEmpty`/`chips.isEmpty` (drawing nothing for nothing), the tag's least width in ems (`DayCard.swift:17,40`): layout, acceptable. Actions pass through unchanged (`builder_buttons_sendTheirModelsActions`, `library_buttons_sendTheirModelsActions`). No `Task`. |
| 2 Scroll convention | **Met** | `ProgramScreen.swift:15-17`, `ExercisePickerScreen.swift:16-23`; `ProgramScreenTests` (one `UIScrollView` per screen, none in the parts); `onlyTheScreens_holdAScrollView`. Trees and references from `ProgramParts`. |
| 3 The builder | **Met** | Header field, "BLOCK · 8 WEEKS" with "−" "+", chips two rows of four, strip of seven, three actions, "TRAINING DAYS", helper, cards, add, notice: `builder-dark-large.png`, `emptyDay-dark-large.png`, `twoWeeks-dark-large.png`; `weekChips_wrapIntoRows`. |
| 4 The library sheet | **Met**, loosely on the mark | `library-dark-large.png`, `libraryPicked-light-large.png`, `libraryNothing-dark-large.png`. "already in this day" is drawn inside the grey line, not as a mark apart (deviation 8, for Pete). |
| 5 Previews and snapshots | **Met** | Eight cases, eight `#Preview`s, one registry; 28 references (22 of the table + 6); `Package.swift` and `PreviewScan` registered; `PreviewTests`. |
| 6 VoiceOver | **Met**, fields excepted | `ProgramTrees` read line by line against the S9/S12 table above: chip "Week 3" value "4 days" selected; cell "Tuesday" value "Rest" with the hint; a day's short names hidden (`DayCard.swift:77`); one selected chip per row; row = button, line as value, selected when picked; foot dimmed. Headings: `headings_areTheSectionTitles`. 44 pt: `targets_areAtLeast44Points` at both sizes. Not pinned: the two fields' spoken labels and targets (S-4, N-5). |
| 7 Sizes and settings | **Partly** | At `.accessibility3` nothing is cut (opened), but tight (S-2). At `.xLarge` "REST" is cut (**B-1**). Right to left lays out (S-5 the check). Sixteen weeks and the long name lay out; the name ends in "…" (deviation 3). Bold Text: by `parts_layOutSanely` only; no image, not seen. |
| 8 Orange audit | **Met** | `ProgramOrangeAuditTests`, by hue, both themes, with a control (`count_seesTheAccentAndNoInk`). By eye: "DELOAD" under W8, or the title "WEEK 8 · DELOAD"; the foot's button. Nothing else orange in any image opened. |
| 9 No rule of its own | **Met** | Tokens and components throughout; three self-drawn pills (week chip, strip cell, tag/short-name chip) are declared and proposed, not added to `LedgerDesign`. |

### The deviations

1. **Everything in `Views/`: accept.** It is FeatureToday's form, and it is the better answer than editing
   two testers' pins. The module stays readable at 15 files; at S10/S11 it will hold about 30, and then
   `Views/Builder`, `Views/Library`, `Views/DayEditor` are worth it (`ProgramViewsSourceTests.isView` reads
   by the `Views/` prefix, so only its `screens` list changes). **Coverage of `Views/` by the scans:** the
   two adversarial scans read one folder each and do not read `Views/`, and should not be widened (their
   rule, no literal and no `Text(`, cannot hold for a view). What does cover it: `FeatureProgramSourceTests`
   reads every Swift file of the module through `CopyAudit.sources(ofModule:)`, which walks subfolders, so
   the ambient list applies to `Views/`; `LedgerAppKitTests.ModuleCopyTests` audits the whole module for
   stray literals and lookups; `ProgramViewsSourceTests` adds the view-only bans. That is enough. Nothing
   needs editing for S9; the testers' file lists need no change either.
2. **The draft as view state: accept for S9, with S-1.** Can a store edit and a typed draft fight? Not as
   written: while the field has focus the stored name is never written into it (`:51-55`), so a cleaned or
   late echo of the lifter's own typing cannot move the cursor or eat a trailing space; a programmatic
   `draft = model.name` re-enters `onChange(of: draft)` with equal values and sends nothing, so there is no
   loop. With a store that applies `.rename` late, blur shows the old name for a frame and then the new one
   (`:46-50` then `:51-55`); harmless, and S13's store applies it at once. When the name changes under an
   open draft from elsewhere (a sync, an undo): the draft stays, the next keystroke overwrites the outside
   change, and with no further keystroke blur shows the outside name: last writer wins, without notice.
   Acceptable for M1 (one device edits a program); S13 should know it.
3. **One-line name field: accept** for M1 (open question 1).
4. **Search bound through `.setQuery`: accept.** S14's store must apply it synchronously (already noted).
5. **`ViewThatFits` for the strip: accept the mechanism, fix B-1.** Choosing by fit is right; the first
   candidate must not be able to cut.
6. **Touching targets in the strip: accept.** Measured need (42.7 pt on 375 pt), pinned at 375 pt.
7. **"Nothing matches" not `EmptyState`: accept.** One sentence and a pill; a heading there would be wrong.
8. **A row on `HairlineRow`, three model fields unused: accept the view; the fields are Pete's to settle,
   not this PR's.** Reusing `HairlineRow` is right. But "already in this day" in the same grey as "Cable ·
   Back" is easy to miss in a long list (`library-dark-large.png`, second row), and it was planned as a
   mark apart. Two honest ends: draw it apart (needs `HairlineRow` to take a second detail, or the row to
   stop being `HairlineRow`), or drop `detail` and `inDayMark` from the model with their tests once Pete
   says the grey line is enough; `pickMark` goes or is drawn with open question 3. Do not leave three
   tested, undrawn fields past F11.
9. **`ExercisePickerPage(model:)` takes the whole model: accept**; the criterion writes it so.
10. **No shared component added: accept.** On the four proposed: **(a) `SectionLine` → `LedgerDesign`: now,
    as its own chore before S10**, replacing `CardEyebrowLine` (two features hold the same view today, and
    S10 would be the third); with N-2's alignment. **(d) `LedgerPressStyle` public: in the same chore**; three
    buttons here have `.plain`'s pressed look and every other control has the design's. **(c) the small tag
    pill: at S10**, when the Day editor's header draws the same tag. **(b) the two-line week pill: never**,
    unless a second screen wants one.

### Open questions

1. Long name cut: accept for M1. 2. Title orange as a whole: accept; the eyebrow is one string, and a
second model field for one word is not worth it. 3. The pick's number: agree with "neither" for the spoken
side; drawing it is Pete's call (the order picked is the order added, and nothing on screen says so).
4. "Deload" as the chip's value and "Double-tap to assign": keep. 5. Helper line at accessibility sizes:
keep. 6. File places: `Views/` (deviation 1).

### Tests, size, simplicity

- **Tests pin the criteria** where a hosted test can. The trees are exact and ordered, the action tests
  compare whole sequences, the audit has a control. Holes: truncation inside a frame (B-1; the notes say so
  and then missed one in a reference they "looked at"), the rename path (S-1), the fields' labels and
  targets (S-4, N-5), the real sheet's "Cancel" (N-8).
- **Size:** 609 non-blank, non-comment lines in `Views/` recounted file by file; matches the claim. One
  pull request is right.
- **What a staff engineer would cut:** little. `SectionLine`'s `SectionNote?` initialiser and
  `ScheduleStrip`'s `spokenHint` are the only indirections that do not pay yet (N-2, N-6). `DayCard`
  repeats `HairlineRow`'s frame (rule, button, padding, layout switch) because it needs a leading tag and
  chips; fine until a second such row appears.

### For Pete, in plain words

1. **A bug to see fixed:** with text one step larger than default, the rest days in the week strip read
   "RE…". It goes back for a fix.
2. **Look at `builder-dark-large.png`:** a rest day (outlined, grey "REST") is tappable, and sits one row
   above "First week", which is greyed out because it is switched off. Are the two different enough?
3. **Look at `library-dark-large.png`, second row:** "already in this day" is small grey text in the same
   line as "Cable · Back". Enough, or should it stand out? And picked rows show a check, not "1, 2, 3".
4. **Look at the two rows of filter chips:** with "Arms" and "Bodyweight" wrapping, it is not obvious which
   row is muscles and which equipment; neither row has a title.
5. **`deloadWeek-dark-large.png`:** the whole of "WEEK 8 · DELOAD" is orange, and the "Deload" pill is
   white, not orange. Matches decision 1 A as you meant it?
6. **`builder-dark-accessibility3.png`:** at the largest text the week pills and rest cells are tight.

**Screenshots opened (18 of 28):** builder dark `large`, `xLarge`, `accessibility3`; builder light `large`,
`xLarge`; deloadWeek dark; emptyDay dark; twoWeeks dark; sixteenWeeks dark `large`; library dark `large`,
`xLarge`, `accessibility3`; libraryPicked light; libraryNothing dark; rightToLeft builder and library;
increaseContrast builder and library. **Not opened:** the light `accessibility3` pair, sixteenWeeks
`accessibility3`, deloadWeek/emptyDay/twoWeeks light, library light `large`/`xLarge`, libraryPicked dark,
libraryNothing light. **Not checked:** anything that needs a run (the gate, the trees as read, coverage, the
six mutations), VoiceOver itself, a device, Bold Text by eye, whether a tap inside the field's text still
places the cursor under `.onTapGesture`, and the 375 pt width by eye.
