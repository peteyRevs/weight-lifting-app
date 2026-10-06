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
| **S5** builder presentation — `feat/F11-s5-builder-presentation` | `FeatureProgram/`: `ProgramRoute.swift` (~12), `ProgramBuilderModel.swift` (~90), `ProgramPresentation.swift` (~110), `ProgramPresentation+Weeks.swift` (~70), `ProgramPresentation+Days.swift` (~60), `ProgramCopy.swift` (~130, with the equipment names), `Resources/Localizable.xcstrings`. The placeholder `FeatureProgram/FeatureProgram.swift` and its test are deleted. `LedgerKit/Package.swift:127` gains `resources`; `scripts/coverage-thresholds.json:15` gains `"FeatureProgram"`. **~470 lines.** No view. | After #28. S1. | `ProgramPresentationTests` (criterion 1 word for word, criteria 2–6 as display models), a seeded property suite, the module's catalog checks (they run by themselves once the module has a catalog). | After #28. |
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

