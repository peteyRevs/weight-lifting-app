# F12 — implementation notes

## S1 — as built (G1 implementer, 2026-10-21)

Branch `feat/F12-s1-library`, cut from `main` at `011ab3d` plus the spec commit `e9b7aa0`. The specification is
the brief's "Plan amendments (planner, 2026-10-21)" (C1–C27, slice S1: criteria 1, 2, 3, 8 for the Library, and
N1–N8) and "Rulings before G1" (R1–R7). **Pete, 2026-10-21: Q1–Q8 = A** (confirmed, no longer provisional); S1
builds Q6 and Q8.

Commits:
- `c52a73c` refactor(design): FilterChipRow and SearchField in LedgerDesign (R5).
- `5fe2c3e` feat(library): `StatsQueries.bestSets()` (N3).
- `5fe3d57` feat(library): the Library tab (F12 S1).
- this notes commit (docs only).

### What landed

Paths under `LedgerKit/`.

- **Domain.** `LedgerDomain/Model/BestSet.swift` (weight and reps). `StatsQueries.bestSets() -> [ExerciseID:
  BestSet]` in `Protocols/Repositories.swift`. `ExerciseSearch.equipmentFilters`, the equipment chips' list, moved
  out of `ExercisePickerPresentation`, which now reads it.
- **Persistence.** `LedgerPersistence/Stats/GRDBStatsQueries+Library.swift`: one `ROW_NUMBER() OVER (PARTITION BY
  exercise ORDER BY weight DESC, reps DESC)` pass over `recordSets` (decision #25). A row it cannot read is logged
  and left out, as `recentlyLogged` does. `GRDBStatsQueries.queue` went from `private` to internal so the
  extension in its own file can read it.
- **Fakes and stubs.** `InMemoryStatsQueries.bestSets()` (one walk, `bestSet`'s rule);
  `UnimplementedStatsQueries.bestSets()`.
- **Contract.** `LedgerTestSupport/Persistence/StatsQueriesContract+Library.swift`, one clause, run on GRDB, on the
  in-memory stores and on the adversarial `HistoryModel`: it is empty on an empty history; a 200 × 3 added set beats
  a heavier undone set, a heavier drop set and a heavier warm-up; of two sets as heavy the one with more reps wins;
  a deleted workout counts for nothing; warm-ups alone give no entry; and every exercise's entry equals
  `bestSet(exerciseID:)`.
- **LedgerDesign (R5).** `Components/FilterChipRow.swift` is generic over the caller's chips. It reads the title, the
  spoken label and the selection through closures, so FeatureProgram's adapter can still send `chip.action`.
  `Components/SearchField.swift` holds the field and its focus. Both are string-only. The gallery gains a
  "FilterChipRow · SearchField" section, and its dark reference was re-recorded: the new section is the only change,
  and I looked at it.
- **FeatureProgram.** `FilterChips` and `ExerciseSearchField` keep their names. Each is now a thin adapter over the
  shared component, which kept the edits to F11's tests small. F11's references are byte-identical: 670
  FeatureProgram tests passed on the simulator, and none was re-recorded.
- **FeatureLibrary**, new:
  - `LibraryRoute` has `.exercise(ExerciseID)` only. `.openWorkout` is S2's.
  - `LibraryAction` holds the query, the two chips, "Clear filters", "New exercise" and a route.
  - `LibraryInput` and `LibraryFilter`.
  - `LibraryModel`.
  - `LibraryPresentation` works in two steps: `rows(_:)` when a source changes, and `make(_:filter:)` on each
    keystroke (R2 of the plan's risks: a keystroke formats no row).
  - `LibraryCopy.swift` and `LibraryCopy+Names.swift`: 39 keys, two of them counted.
  - `LibraryStore` and `LibraryStore+Sources`.
  - `LibraryRoot`.
  - `Views/LibraryScreen`, `LibraryPage` (with its private header), `LibrarySection` (with `LibraryRow`) and
    `Library+Previews` (5 states).
  - `Resources/Localizable.xcstrings`.
  - The placeholder `FeatureLibrary.swift` and its test were removed.
- **LedgerAppKit.**
  - `AppDestination.exercise(ExerciseID)`.
  - `Routes+Library.swift` pushes the history on the selected tab's stack.
  - The Library tab draws `LibraryRoot`. `.exercise` draws `PlaceholderScreen("Exercise history", identifier:
    "library.history.title")`, which uses a new `AppCopy.exerciseHistoryTitle` and its catalog key.
  - `MainRoot` passes `onLibraryRoute`.
- **Module setup (C22).** `Package.swift` gives FeatureLibrary its `resources` and adds it to `snapshotTestTargets`.
  It is also added to `scripts/coverage-thresholds.json` `required` and to `PreviewScan.registeredModules`.
- **Tests.**
  - `FeatureLibraryTests` holds 10 suites, the timing suite included, plus support files.
  - `LedgerAppKitTests/LibraryRouteMappingTests` is new.
  - The nightly UI test `Apps/LedgerUITests/Library.swift`.
  - One `bestSets` line in `StatsQueriesPerformanceTests`.

No change to the project file, a test plan or `.github/`.

### Pete's answers (Pete, 2026-10-21: Q1–Q8 = A), and where S1's live

| Question | Built (A) | The one place to change it |
|---|---|---|
| 6. Chips and casing | Chips "All, Chest, Back, Shoulders, Legs, Arms" and "All, Barbell, Dumbbell, Cable, Machine, Bodyweight"; meta "Barbell · Chest" | Chip order: `LibraryPresentation.muscleChips` (the Domain's `MuscleFilter.allCases`). Casing: `LibraryCopy+Names.swift` |
| 8. No exercise at all | "No exercises yet." and an outlined "New exercise" under the chips | `LibraryPresentation.content(_:filter:equipment:)`'s first guard |

### "New exercise" in S1 (C5)

The button is drawn in the page's header, at the title's trailing edge, and under the title at accessibility sizes.
Tab roots hide the navigation bar, so it can't be a toolbar item. It sends `LibraryAction.newExercise`. The store
sets `isNewExerciseShown = true` and does nothing else, so no sheet opens.

**For S3:** present `CreateExerciseSheet` from `LibraryRoot` with `.sheet(isPresented:)` bound to that flag, and
add an intent that sets it back on dismissal (the flag is `private(set)`). The same action is behind the empty
state's button.

### Criteria → tests

Suites:
- In `FeatureLibraryTests`: `LibraryPresentationTests` (+`Words`) (P), `LibraryStoreTests` (S), `LibraryCopyTests`
  (C), `FeatureLibrarySourceTests` (SRC), `LibraryAccessibilityTests` (AX, iOS), `LibraryLayoutTests` (L, iOS),
  `LibraryRootTests` (R, iOS), `LibrarySnapshotTests` (SN, iOS), `PreviewTests`, `LibraryPerformanceTests` (PERF,
  nightly).
- Elsewhere: `LibraryRouteMappingTests` (RM, LedgerAppKitTests), `StatsQueriesContract` (K), UI `Library` (UI,
  nightly).

| Criterion | Tests |
|---|---|
| 1. Sections | P `sections_recentInItsOrder_withSessionsAndPR`, `sections_allInNameOrder_withPROrDash`, `customExercise_readsCustom`, `noHistory_drawsNoRecentSection`, `recent_notStored_isLeftOut`. S `run_firstModel_showsRecentAndAll` |
| 2. Filters and "Clear filters" | P `filter_rowBackMachine_leavesChestSupportedRow` (both sections), `filter_query_ignoresCaseAndDiacritics`, `filter_shortName_matches`, `filter_nothing_saysSoWithClearFilters`, `filter_equipmentWithoutAChip_isAll`, `chips_areThePickers`. S `filters_applyAtOnce_andClearFiltersResetsAll`, `filter_beforeTheFirstModel_isInIt`. UI `test_queryChipsRow_opensTheHistory_andBackKeepsTheFilter` |
| 3. Row → history | S `rowTapped_twice_isOneRoute`. R `root_runsTheStore_andHandsARouteOnce`. RM `exercise_pushesItsHistoryOnTheLibrarysStack`, `exercise_pushesOnTheSelectedTab`. `AppTabsTests.exerciseDestination_drawsItsPlaceholder`. UI (above) |
| 8. kg (Library) | P `units_kilograms_convertThePRs`. S `unitsChanged_redrawsThePRs` (no navigation) |
| N1. Live | S `customExerciseSaved_whileRunning_appears`, `workoutFinished_whileRunning_updatesRecentAndPR`, `unitsChanged_redrawsThePRs`, `newRun_keepsTheModelOnScreen` |
| N2. Counted placeholder | P `placeholder_countsEveryExercise`, `noExercises_saysSoWithNewExercise`. C `searchExercises_oneAndSeveral`, `countedText_takesTheCatalogsPluralForm` |
| N3. `bestSets` | K "bestSets is bestSet of every exercise in one read…" (GRDB, in memory, `HistoryModel`) |
| N4. Budgets | PERF `firstModel_underBudget` (250 exercises, < 100 ms), `keystroke_underBudget` (< 10 ms). `StatsQueriesPerformanceTests` `bestSets` (< 50 ms p95, 20k sets). All three pass on the Nightly plan on the simulator |
| N5. Conventions | SRC, all seven tests: ambient clock and locale, no task or timer or `.formatted(` in the store and root, no `Double`, every lookup in `LibraryCopy*`, views decide nothing, imports, one scroll view. Plus `ModuleCopyTests` with no exemption |
| N6. No orange | SRC `views_wearNoAccent` |
| N7. VoiceOver | AX `tree_isExactlyTheTable` (5 states × sizes), `populatedRows_readTheirMetaAndPR`, `targets_areAtLeast44Points`, `controls_sendTheirModelsActions`. P `row_spokenValue_readsTheMetaAndThePR` |
| N8. The tab | `AppTabsTests.selectedTab_showsItsOwnScreen` (sanctioned edit). UI `Library` finds `library.title` reading "Library"; `Tabs` and `TabsAdversarial.test_eachTab…` pass |
| Failed state | S `observationEnds_showsFailed`, `statsReadFails_showsFailed`. R `root_drawsTheFailedMessage` |
| Layout | L `parts_layOutSanely` (5 states × settings), `header_titleKeepsOneLine` |

**Seen failing first.** Three tests were written before the code they test was right, and failed:
- `workoutFinished_…`, on an order assumption I then corrected in the test: two exercises of one workout come in
  id order.
- `filter_beforeTheFirstModel_…`, which first named an exercise that doesn't exist.
- The snapshots, which fail on their first run (`.missing`).

Every other test was written alongside its code, not ahead of it, and passed on its first run.

### Decisions and deviations

1. **The whole page scrolls; nothing is pinned.** The title and the search field scroll with the rest, as in v2.
   The picker pins its field, but it is a sheet. With nothing pinned, the trees and the references are the page
   itself (`LibraryParts`).
2. **Rows written once per change of a source** (`LibraryPresentation.Rows`). Each keystroke filters ids and lays
   the screen out again; the row strings are cached. Measured under budget (N4).
3. **A custom exercise reads "· Custom" in both sections.** In RECENTLY LOGGED it comes after the sessions:
   "Barbell · Chest · 1 session · Custom". The brief gives only the separate formats, so this combination is mine.
4. **The spoken row** has the label `name` and the value `"Barbell, Chest, 34 sessions, PR 195 pounds"`. VoiceOver
   reads "Barbell Bench Press, Barbell, Chest, 34 sessions, PR 195 pounds, button" (N7). A row with no PR reads no
   PR. The drawn "—" is never read.
5. **The chip rows are not wrapped in an accessibility container.** They follow the picker exactly: each chip reads
   "Muscle: Chest" and selected. N7's "labelled groups" is met through the chips' own labels, so the picker's tree
   didn't change. Open question 2.
6. **`bestSets` leaves out a row it cannot read**, whereas `bestSet` throws. One damaged set should not blank every
   PR in the Library.
7. **The history placeholder needs its own title**, so LedgerAppKit gains one key, "Exercise history". S2 removes it
   when it draws the real screen, and the two counts below go back with it.
8. **The failed state's wording is new** (open question 1).
9. **`LibraryStore.State` is its own enum** (`loading`, `loaded`, `failed`), as `ProgramStore.State` is. There is
   no `Loadable`, because the failed state carries no error.
10. **Previews and snapshots use 18 exercises**: the seed program's 16, the two chest-supported rows and one
    custom. The full catalog would make 15,000-pt references. The history is `Fixtures.history(weeks: 8)`,
    folded in the preview file.

### Sanctioned edits

None of the files the parallel CI chore touches was edited here: `ProgramViewsRoomAdversarialTests`,
`DayEditorViewsRoomAdversarialTests`, `NameFieldLineTests` and LedgerTestSupport's `PixelBuffer` are unchanged.

| File | Edit | Why |
|---|---|---|
| `LedgerAppKitTests/AppTabsTests.swift` | `(.library, "Library")` → `(.library, nil)`, with a note in the doc comment; new test `exerciseDestination_drawsItsPlaceholder`; `import LedgerDomain` | C4 |
| `LedgerAppKitTests/Adversarial/AppTabsAdversarialTests.swift` | `rootHeaders(of:)`: the Library tab, like Today and Program, has no heading outside the scroll view in a window with no scene | C4 (found by the first full gate) |
| `LedgerAppKitTests/Adversarial/AppRootResetAdversarialTests.swift` | `titles[.library]` is `[]`, not `["Library"]` | C4 (same) |
| `LedgerAppKitTests/ModuleCopyTests.swift` | `unresolvedKeys(in: .main).count == 7` → `8` | The "Exercise history" key (decision 7) |
| `LedgerAppKitTests/Adversarial/AppCopyAdversarialTests.swift` | `shellStrings` gains "Exercise history" | Same |
| `FeatureProgramTests/Adversarial/ProgramViewsSourceAdversarialTests.swift` | The kept-state list loses `ExercisePickerScreen.swift: @FocusState private var isEditing: Bool` | R5: the field's focus moved into `SearchField`. The test's title still says "the two fields' focus" (one field now); I left the tester's words alone |
| `LedgerDesignTests/DesignGalleryTests.swift` | `components` gains "FilterChipRow", "SearchField" | R5; the gallery's reference was re-recorded for the new section |
| `LedgerPersistenceTests/Adversarial/HistoryContractAdversarialTests.swift` | 23 → 24 clauses | N3 |
| `LedgerPersistenceTests/Adversarial/HistoryModel+Stats.swift` | `bestSets()` from its own `bestSet` | A protocol requirement (N3) |
| `LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift` | `BriefStatsQueries.bestSets()` returns `[:]` | Same |
| `FeatureWorkoutTests/Support/ReceiptSupport.swift` | `BestsSession.bestSets()` forwards to its base | Same |
| `LedgerDependenciesTests/UnimplementedStubTests.swift` | The stats stub list gains `bestSets()` | Same |
| `LedgerPersistenceTests/Performance/StatsQueriesPerformanceTests.swift` | One line: `("bestSets", …)` | N4. This line replaces the separate `LibraryQueriesPerformanceTests` the plan named, so the 20k-set seeding isn't done twice |

No FeatureProgram test names `FilterChips` or `ExerciseSearchField` differently. Both names are kept as adapters, so
none of the tests that name them by type changed.

### Product lines per file

These are non-blank, non-comment Swift lines in `LedgerKit/Sources` and `Apps`. `LedgerTestSupport`, the UI-test
targets and the catalogs are excluded. Measured against `e9b7aa0`.

| File | + | − |
|---|--:|--:|
| `FeatureLibrary/LibraryCopy.swift` | 129 | |
| `FeatureLibrary/LibraryPresentation.swift` | 121 | |
| `FeatureLibrary/LibraryStore+Sources.swift` | 113 | |
| `FeatureLibrary/Views/Library+Previews.swift` | 87 | |
| `FeatureLibrary/LibraryStore.swift` | 80 | |
| `FeatureLibrary/Views/LibraryPage.swift` | 56 | |
| `FeatureLibrary/LibraryModel.swift` | 52 | |
| `LedgerDesign/Components/FilterChipRow.swift` (with the gallery view) | 50 | |
| `FeatureLibrary/LibraryCopy+Names.swift` | 43 | |
| `FeatureLibrary/LibraryRoot.swift` | 39 | |
| `LedgerDesign/Components/SearchField.swift` | 35 | |
| `LedgerPersistence/Stats/GRDBStatsQueries+Library.swift` | 29 | |
| `FeatureLibrary/Views/LibrarySection.swift` | 28 | |
| `FeatureLibrary/LibraryInput.swift` | 15 | |
| `FeatureLibrary/Views/LibraryScreen.swift` | 14 | |
| `LedgerFakes/InMemoryStatsQueries.swift` | 14 | |
| `FeatureLibrary/LibraryAction.swift` | 9 | |
| `LedgerDomain/Model/BestSet.swift` | 9 | |
| `LedgerAppKit/Routes+Library.swift` | 9 | |
| `LedgerAppKit/AppTabs.swift` | 6 | 1 |
| `FeatureLibrary/LibraryRoute.swift` | 4 | |
| `LedgerAppKit/AppCopy.swift` | 3 | |
| `LedgerDependencies/…/UnimplementedStatsQueries.swift` | 3 | |
| `FeatureProgram/Views/FilterChips.swift` | 2 | 5 |
| `FeatureProgram/Views/ExercisePickerScreen.swift` | 1 | 22 |
| `FeatureProgram/Picker/ExercisePickerPresentation.swift` | 1 | 1 |
| `LedgerPersistence/Stats/GRDBStatsQueries.swift` | 1 | 1 |
| `LedgerAppKit/MainRoot.swift`, `Routes.swift`, `LedgerDesign/Gallery/DesignGallery.swift`, `LedgerDomain/…/Repositories.swift`, `ExerciseSearch.swift` | 1 each | |
| `Package.swift` | 5 | |
| **Total** | **963 added** | **30 removed (net 933)** |

The plan was about 790 lines, with a stop line at about 950. **Added lines are 13 over the stop line; the net count
(933) is under it.** The excess, against the plan's table:
- The copy file: 129 + 43 lines, planned 115. Every lookup is wrapped by the formatter, and the failed state's two
  texts weren't planned.
- The store and its sources: 193, planned 150. Kept-stats bookkeeping as Today's, plus three follow methods.
- The previews: 87, planned 55. Recent, sessions and bests are folded from the fixture history.

Nothing was compressed to fit. The PR is over the 500-line target (A6). The split considered was "the query and the
LedgerDesign move" first, then "the Library". The two halves are about 140 and 820 lines.

### PR-sweep seconds (R6)

These durations were measured on the simulator with `TEST_RUNNER_LEDGER_SWEEP=pr` and
`TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40`, on the PR plan. Each is the sum of the per-argument durations in the
xcresult.

| Suite | Cases | Seconds |
|---|--:|--:|
| Library accessibility | 42 | 2.28 |
| Library layout | 48 | 1.80 |
| LibraryRoot | 3 | 0.60 |
| Library snapshots | 5 (12 references) | 0.57 |
| FeatureLibrary sources | 7 | 0.41 |
| Previews | 7 | 0.19 |
| LibraryStore | 11 | 0.08 |
| LibraryPresentation | 18 | 0.04 |
| LibraryCopy | 13 | 0.01 |
| Library · timing | 2 (skipped) | 0.00 |
| Library routes (AppKit) | 2 | 0.00 |
| AppTabs' new test | 1 | ~0.1 |
| **Added** | | **≈ 6.1 s** |

That is far under the plan's 30–40 s estimate. Unreduced (local gate), FeatureLibraryTests took 8.9 s.

### Runs

- Host: `swift test` over the whole package is green, apart from one known issue that was already there.
- Simulator, targeted through the lock on the PR plan:
  - `FeatureLibraryTests`, 60 tests: green on the second run, after the first recorded the 12 references.
  - `FeatureProgramTests`, 670 tests: green, no reference re-recorded, so F11's references are byte-identical.
  - `LedgerAppKitTests` `AppTabsTests`, `LibraryRouteMappingTests`, `ModuleCopyTests`: green.
  - `LedgerDesignTests`, 392 tests: only the gallery's reference changed, and it was re-recorded.
- Simulator, Nightly plan:
  - `LibraryPerformanceTests` (2), `StatsQueriesPerformanceTests` (with `bestSets`), UI `Library` and UI `Tabs`:
    green.
  - `TabsAdversarial`: 5 of 7 green; two fail. See open question 3.
- **Full gate:** green on `4231d65`; see "The gate" below.
- References: I looked at all 12 Library references, and at the gallery's new section.

### Open questions, each with a recommendation

1. **Wording of the failed state.** The brief has none. Built: "Can't show the library right now" / "Your exercises
   and workouts are still on this iPhone. Open the app again to try once more.", modelled on the builder's (decision
   6). *Recommendation:* accept, or reuse Program's two lines word for word.
2. **N7's "labelled groups" for the chip rows.** Built as the picker's: each chip carries its row's name. A
   container with a label would change the picker's tree too, since both use the same component. *Recommendation:*
   accept the picker's pattern.
3. **Nightly `TabsAdversarial`.** Two tests fail on this branch:
   - **`test_everyTabRoot_passesTheSystemsAccessibilityAudit`.** The Program tab's findings were already there
     before this branch (F11 S14 drew the builder). The Library tab adds six findings:
     - "Dynamic Type partially unsupported" and "Text clipped" on the "ALL EXERCISES" eyebrow. Program's eyebrows
       report the same.
     - "Text clipped" on the search placeholder.
     - Contrast on the last visible row, "Band External Rotation", its "—" and its meta. That row stands under the
       tab bar.

     *Recommendation:* a follow-up like `TodayAuditExclusions`, measuring each finding and fixing or excluding it.
     I did not add exclusions in this slice.
   - **`test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark`** ("Today selected: Today is not in the
     accent"). It concerns the tab bar's tint on Today, which this slice doesn't touch. *Recommendation:* run it on
     `main` to confirm it was already failing. I didn't have the time to build `main`.
4. **Placeholder count in the app.** A fresh database reads "Search 224 exercises", counting every live exercise,
   per N2.

### Inputs for S2 and S3

- **S2:**
  - Replace `.exercise`'s `PlaceholderScreen` in `AppTabs.screen(for:)` with `ExerciseHistoryRoot(exercise:
    onRoute: onLibraryRoute).id(destination)`.
  - Remove `AppCopy.exerciseHistoryTitle` and its key. `ModuleCopyTests` goes back to 7, and `shellStrings` loses
    "Exercise history".
  - Add `.openWorkout` to `LibraryRoute` and `Routes+Library.swift`.
  - `LibraryCopy+Names.swift` already has the equipment and muscle names for the eyebrow (Q6 A, "Barbell · Chest").
  - `LibraryFixtures` and `LibraryViewStops` in the test target can be reused.
- **S3:**
  - The intent is wired: present the sheet from `LibraryStore.isNewExerciseShown` and add a dismiss intent.
  - A custom exercise saved through `exerciseRepository.save` already shows live
    (`customExerciseSaved_whileRunning_appears`).
  - `LibraryFixtures.custom` is a catalog-free name ("Landmine Squeeze Press", C13).
- **Both:** `StatsQueries` gained a requirement. A new conformer (a test double) needs `bestSets()`.

### The gate

- **First run, on `5fe3d57`: exit 65.** Two AppKit adversarial suites still expected the Library placeholder's
  "Library" heading (`AppTabsAdversarialTests`, `AppRootResetAdversarialTests`). Both edits are sanctioned
  (above), in `a5ab3cb`.
- **Second run, on `4231d65`: exit 0, "check.sh OK", 2,061 s.**
  - lint 81 s, iOS build 5 s, catalogs 1 s (FeatureLibrary: 39 keys).
  - iOS tests 1,677 s, watchOS build 44 s, watchOS tests 248 s.
  - Coverage 3 s: FeatureLibrary 98.94 %, overall 98.69 %.
- The only commit after `4231d65` is this paragraph.

## S1 — round 2 (G1 implementer, 2026-10-21)

**Ruling (orchestrator):**
- Fix F12-S1-1 in this slice: `SearchField` takes `.ledgerFieldFont(.body)` in place of `.ledgerFont(.body)`.
- R5 is amended for this one case. "Byte-identical" guarded the move; a defect fix in the moved component is a
  separate change, and it may change the references that draw the field.
- The line count is accepted as is.
- F12-S1-3 and F12-S1-4 stay pinned; F12-S1-3 goes to Pete in the PR.

**Commit:** `d5704eb` fix(design). It changes one line of `LedgerDesign/Components/SearchField.swift` and
re-records the four references below.

**Re-recorded references.** Record mode was `failed`, so only references that no longer matched were rewritten. I
looked at each image and measured each against its old version.

| File | What changed |
|---|---|
| `FeatureLibraryTests/__Snapshots__/LibrarySnapshotTests/populated_matchesReferences.light-accessibility3.png` | The search pill is 3 pt taller (4,255 → 4,258 px) |
| `FeatureLibraryTests/__Snapshots__/LibrarySnapshotTests/populated_matchesReferences.dark-accessibility3.png` | The same |
| `FeatureProgramTests/__Snapshots__/ProgramSnapshotTests/library_matchesReferences.light-accessibility3.png` | The same in F11's picker (2,047 → 2,050 px) |
| `FeatureProgramTests/__Snapshots__/ProgramSnapshotTests/library_matchesReferences.dark-accessibility3.png` | The same |

How the comparison was done, per pixel:
- **Above the field:** every row is identical to the old image. The Library's differences start at row 134, the
  picker's at row 112.
- **Below the field:** with the 3 px shift applied, every row is identical. The last differing row is 188 for the
  Library and 166 for the picker.
- **So the changes lie only in the field's band:** the pill's height and the placeholder's place in it.
- **No other reference changed.** That includes the gallery, the `.large` and `.xLarge` references, and every
  other F11 reference.

**Runs** (targeted, through the lock; I did not run the full gate):
- **PR plan,** recording failed references: `LedgerDesignTests`, `FeatureProgramTests/ProgramSnapshotTests`,
  `FeatureProgramTests/DayEditorSnapshotTests`, `FeatureLibraryTests`. The run exited 0 and recorded the four
  references.
- **PR plan, compare run:** the same suites, exit 0, all green:
  - 393 LedgerDesign tests, 27 of them known issues;
  - 19 FeatureProgram snapshot tests;
  - 65 FeatureLibrary tests.
  G2's `SearchFieldLineAdversarialTests.searchField_edited_drawsItsTailsWhole` passed, unedited.
- **Nightly plan,** UI `Library` and `LibraryAuditAdversarial`: exit 0. `Library` passed.
  `LibraryAuditAdversarial.test_libraryRoot_passesTheAudit_butForItsMeasuredFalsePositives` **still fails**. Its
  only lines are "Text clipped" on "Search 224 exercises", at:
  - the default size (field 350 × 44);
  - Accessibility L (350 × 51);
  - Accessibility XXXL (350 × 72).

  Its other test passed.

**Open (for the orchestrator).** The field's line height was not what the audit's "Text clipped" reports on. The
audit flags the empty field's placeholder even at the default size, where an edited query was never cut. The
placeholder is drawn by the `TextField` from its title, without the field's font.

Candidates, none built:
- an explicit `prompt:`, as F11 gave `NameField` in its SF-2;
- or, if the audit misjudges the placeholder of a system field, an exclusion measured as for F12-S1-2.

I recommend trying the `prompt:` first. It would change the same four references again, and the picker's along
with them.

## S1 — round 3 (G1 implementer, 2026-10-21)

**Ruling (orchestrator):** try Option 1, an explicit `prompt:` in the field's font and colour. If the audit still
reports "Text clipped", revert it, prove the placeholder whole, and exclude that one line (Option 2).

**It ended as Option 2.**
- **Option 1 was tried.** `TextField(text:prompt:)` with `Text(placeholder).foregroundStyle(LedgerColor.inkFaint)`
  under `.ledgerFieldFont(.body)`. Nightly `LibraryAuditAdversarial` still reported "Text clipped" on "Search 224
  exercises" at all three sizes, with the same frames. The change was reverted before any reference was recorded,
  so the references are still those of `d5704eb`.
- **Option 2: evidence.** I added `test_searchPlaceholder_isDrawnWholeInsideTheField` to `LibraryAuditAdversarial`.
  This is a sanctioned addition to G2's file; their test was not edited. At the default size, Accessibility L and
  Accessibility XXXL it:
  - keeps the field's picture with the result;
  - finds the pill's two strokes in it;
  - requires the placeholder's ink to lie between them, clear of each by more than 2 px.

  I looked at the pictures at the default size and at XXXL: the placeholder is whole, with room above and below it.
  The text has no descender. The audit's reported frames are the field's own (350 × 44, 51 and 72 pt).
- **Option 2: the exclusion.** `LibraryAuditExclusions` excludes "Text clipped" on a label "Search … exercises",
  with the evidence in its comment. This is F12-S1-5 in `test-findings.md`. F12-S1-1 is marked fixed for the tails
  (`d5704eb`).

**Re-recorded references:** none in this round.

**Runs** (targeted, through the lock; I did not run the full gate):
- **Nightly, `Library` and `LibraryAuditAdversarial`, with the prompt:** exit 0, one test failed (the audit, as
  above).
- **Nightly, the same two suites, after the revert, with the exclusion and the new test:** exit 0. 4 tests, 0
  failures. Both audit-suite tests the orchestrator named pass: the audit and `test_lastRow_scrollsClearOfTheTabBar`.
  So do the new measurement test and the Library UI test.
- **PR plan, `LedgerDesignTests`, `ProgramSnapshotTests`, `DayEditorSnapshotTests` and `FeatureLibraryTests`:**
  exit 0, all green, nothing recorded. That is 393 tests (27 known issues), 19 tests and 65 tests.

## S1 — round 4 (G1 implementer, 2026-10-21)

G3's review was not approved (`review.md`, "Slice S1 — review"). The orchestrator ruled to fix M1, m1, m3 and n2.

### M1 (b): the truncation was real

`LedgerDesignTests/SearchFieldFitTests` measures the hosted `UITextField`: the drawn placeholder's width against
`placeholderRect(forBounds:)`. It does this on phones 320, 375, 390 and 402 pt wide with the screen's margins, at
every text size, through `TestSweep`.

**Before the fix**, "Search 224 exercises" needed this much width (pt):

| Size | Needed | Room at 320 | 375 | 390 | 402 |
|---|--:|--:|--:|--:|--:|
| `.accessibility2` | 261 | 236 | | | |
| `.accessibility3` | 312 | 236 | 291 | 306 | 318 |
| `.accessibility4` | 362 | | | | 318 |
| `.accessibility5` | 420 | | | | 318 |

It was cut short on 375- and 390-pt phones from `.accessibility3`, on a 320-pt phone from `.accessibility2`, and on
the iPhone 17 from `.accessibility4`.

The exercise library's "Search exercises" was also cut short:
- at `.accessibility5` on every width (it needs 337, with at most 318 of room);
- on a 320-pt phone from `.accessibility3` (it needs 250, with 236 of room).

**The fix** follows the ruling's fallback:
- `SearchField(_:short:text:onChange:)` draws `short` when the whole placeholder is wider than the field. It
  measures the whole placeholder in a hidden, fixed-size `Text` in the field's font and compares it with the
  field's width (two `@State` widths, `onGeometryChange`). The spoken label stays the whole placeholder.
- The Library passes `LibraryModel.Search.shortPlaceholder`, the new `LibraryCopy.search`.
- The picker passes `ExercisePickerModel.Search.shortPlaceholder`, the new `ProgramCopy.search`.

**New wording for Pete:** "Search", in both catalogs, as the short placeholder.

**After the fix,** every case of the fit suite passes:
- the Library's placeholder fits, whole or short;
- the picker's placeholder fits;
- the whole placeholder is drawn on the iPhone 17 at the default size, and on a 375-pt phone at `.xxxLarge`;
- a control field without `short` still overflows at `.accessibility5` on 375 pt.

On the iPhone 17 the snapshots' sizes still draw the whole placeholder, so no existing reference changed. That
covers `.large`, `.xLarge` and `.accessibility3`, F11's picker references included.

**The two readers disagree on the iPhone 17 at Accessibility XXXL.** The hosted measure (`.accessibility5`)
says the whole placeholder does not fit there. The running app's XXXL picture in round 3 drew it whole, 312 pt
wide, and its `placeholderValue` is now "Search". The app now draws "Search" at XXXL, and the UI test asserts it.

### M1 (a) and (c): the measurement and its control

- **`Apps/LedgerUITests/PlaceholderInk.swift` (new)** reads the field's picture. It finds:
  - the pill's two strokes;
  - the placeholder's ink rows and columns.
- **Its guards** are:
  - the ink is clear of both strokes;
  - **(a)** the ink is at least as tall for its width as a whole line of the drawn text. Measured on the running
    app: "Search 224 exercises" 0.0744 at the default size and 0.0762 at Accessibility L; "Search" 0.236 at
    Accessibility XXXL. The floors are 0.065 and 0.2, and an unknown text is a fault;
  - **(b)** the ink ends short of the trailing padding (16 pt).
- **`test_searchPlaceholder_isDrawnWholeInsideTheField`** checks the drawn text (`placeholderValue`) at the
  default size, Accessibility L and Accessibility XXXL.
- **(c) `test_placeholderGuards_failOnAClippedAndOnATruncatedPicture`** doctors the real XXXL picture two ways:
  - its lower third painted over with the pill's ground;
  - a column of ink drawn into the trailing padding.

  The guards report on both doctored pictures (attachment "the guards on the doctored pictures"):
  - `clipped: ["too short for its width: 63 px tall, 401 px wide, 0.157"]`;
  - `truncated: ["too short for its width: 95 px tall, 953 px wide, 0.0997", "into the trailing padding: ink to
    column 1007 of 1050"]`.

  **The control failed first, on two flaws of my own:**
  - The doctoring painted only the middle columns, which left the "S" whole.
  - A floor shared by both texts (0.07, then a share of the pill's height) let a clipped "Search" pass.

  Both were seen failing (`a clip passes`) before the guards were fixed.

### The exclusions (M1, m1)

- **"Text clipped"** now matches the search field only as an empty text field: element type `.textField`, with a
  value that is empty or is its placeholder. `isKnownFalsePositive` takes the element. `TabsAdversarial`'s helper
  passes it, a one-line sanctioned edit. An edited field is never excluded.
- **"Contrast failed"** under the tab bar excludes only elements whose label is not one of the four tabs', so a
  tab whose contrast really fails still fails. The comments say so.

### m3: component snapshots

`ComponentSnapshotTests.FilterChipRowSnapshotTests` runs `FilterChipRowGallery` on `phoneMatrix`. That draws the
field empty and with "row", and the muscle row with Back selected. It recorded six new references, and I looked at
all six. At `.accessibility3` the whole placeholder still fits on 402 pt.
- `LedgerDesignTests/__Snapshots__/ComponentSnapshotTests/filterChipRowAndSearchField_appearance_matchesReference-_.{light,dark}-{large,xLarge,accessibility3}.png`

The gallery passes `short: "Search"`. The gallery's dark reference is unchanged; it compared clean.

### n2

`GRDBStatsQueries.bestSets()` now logs a row it leaves out under `exercise`, the table its id names, not
`workout_exercise`.

### Line budget

Two changes kept the slice under 1,000:
- `InMemoryStatsQueries.bestSets()` is now `bestSet(exerciseID:)` over every exercise the live workouts perform:
  7 lines instead of 14, and the contract clause still passes.
- `SearchField` picks its placeholder inline.

**Product lines now: 991 added, 31 removed (net 960)** in `LedgerKit/Sources` and `Apps` without the UI tests.
`Package.swift`'s 5 bring it to 996.

### Sanctioned edits (round 4)

| File | Edit | Why |
|---|---|---|
| `FeatureProgramTests/Adversarial/ExercisePickerWordsAdversarialTests.swift` | 24 → 25 lookups | The picker's "Search" |
| `FeatureProgramTests/ExercisePickerPresentationTests.swift` (my own) | `Search` with `shortPlaceholder: "Search"` | M1 (b) |
| `Apps/LedgerUITests/LibraryAuditAdversarial.swift` (G2's) | The measurement test reworked, the control added, both exclusions narrowed, `isKnownFalsePositive(issue:element:tabBar:)` | M1, m1 |
| `Apps/LedgerUITests/TabsAdversarial.swift` | The Library's exclusions are handed the element | M1 |

### Follow-ups, and questions for Pete in the PR

- **n1, a follow-up.** "PR 1 pounds": a one-unit best is spoken with a plural unit.
- **n3, a follow-up.** As G3 recorded it.
- **m2, open question.** "New exercise" does nothing until S3. *Recommendation:* accept for S1; S3 follows.
- **m4, open question.** RECENTLY LOGGED reads "· 1 session · Custom". *Recommendation:* accept; the alternative
  is to drop "Custom" in that section.
- **New wording.** "Search" as the short placeholder.

## S2 — as built (G1 implementer, 2026-10-22)

Branch `feat/F12-s2-history`, cut from `main` at `d92cc15` (S1 merged, #70). The specification is the brief's
"Plan amendments" (slice S2: criteria 4–8, 11, 12 as restated, N9–N14) and "Rulings before G1" (R1–R7).

**Pete, 2026-10-22: S1 questions 1–5 approved as built** (the failed-state wording, "Search", "New exercise" visible
though inert until S3, "· Custom", the zero-load best reading "0" / "PR 0 pounds"). Nothing in the code changed for
them.

### Commits

- `1c1a688` fix(library): G3's deferred S1 findings, R2-1 to R2-5 (first commit, as ruled).
- the S2 commit: feat(library): an exercise's history.
- the gate paragraph (docs only), if any.

### R2-1 to R2-5 (first commit)

- **R2-2.** The fit suite measured UIKit's `placeholderRect(forBounds:)` on the hosted field at 320, 375, 390, 393,
  402, 430 and 440 pt and every size: **inset 0 pt everywhere** (the rect is as wide as the field SwiftUI lays
  out). `SearchField` now keeps `placeholderMargin = 1` pt (measured inset 0, plus UIKit's rounding of the text's
  width up to a whole point); the closest whole fit measured is 6 pt (402 pt, `.accessibility3`). The fit suite
  sweeps the three new widths and asserts the inset stays within the margin. No reference changed.
- **R2-3.** `LibraryAuditAdversarial`'s guard test asserts `field.label == "Search 224 exercises"` while "Search"
  is drawn (Nightly, passes).
- **R2-1.** Guard (b) is kept; its comments (`LibraryAuditAdversarial`, `PlaceholderInk`) now say it sees ink out
  of the field's frame, not a "…", which UIKit draws inside the placeholder rect; truncation is the fit suite's.
- **R2-4.** `placeholder_countsEveryExercise` asserts `shortPlaceholder == "Search"`.
- **R2-5.** `InMemoryStatsQueries.bestSets()` is one walk of the live workouts' sets again.

### What landed (S2)

- **Domain.** `Model/ExerciseSession.swift`; `StatsQueries.exerciseSessions(exerciseID:)` (N9);
  `PersonalRecords.countsTowardBests` is public; `Rules/ExerciseHistory.swift`, the pure fold: estimate, best set,
  sessions, the 8 weeks (walked back as ranges from the week holding now, so a DST week is one week), and the log
  tagged `.record` / `.heavier(Δ)` / `.same` (N10: PR from `personalRecords`' workout ids; "+Δ" compares working
  sets only). An overload takes `weekStart` and a `Calendar`, so a Feature needs no program start date.
- **Persistence.** `GRDBStatsQueries.exerciseSessions`: one read of `logged_set.*` joined to its workout, ordered
  `started_at DESC, workout.id, workout_exercise.position, logged_set.position`; a set that cannot be read throws, as
  `bestSet` does. `GRDBStatsQueries.doneSets` exposes the shared SQL (one line).
- **Fakes, stub.** In memory (an extension, keeping the struct under the lint's body length) and Unimplemented.
- **LedgerDesign.** `StatTile(isValueAccented:)` (the gallery's "218" tile wears it, as v2 does);
  `LedgerHairline.bar = 2` (the chart's 2-pt bar, R2).
- **FeatureLibrary.** `LibraryRoute.openWorkout`; `ExerciseHistoryModel` (+ input), `ExerciseHistoryPresentation`,
  `ExerciseHistoryStore`, `ExerciseHistoryRoot`, `LibraryCopy+History`; views `ExerciseHistoryScreen` (screen and
  page), `E1RMChart` (bars; a list of week and value at accessibility sizes, N12), `E1RMChartDescriptor` (the one
  `import Accessibility`, R2), `SessionLog` (F06 hairline rows), `History+Previews` (4 states over
  `Fixtures.history(weeks: 8)`, records detected honestly). No `import Charts`.
- **LedgerAppKit.** `.exercise` draws `ExerciseHistoryRoot`; `.openWorkout` selects the History tab (Q1 A);
  `AppCopy.exerciseHistoryTitle` and its catalog key are removed.

### Decisions

1. **The chart's message** ("Log a session to start the chart.") shows when none of the 8 weeks has an estimate,
   which covers criterion 5's "no working sets at all" and also older-only history.
2. **Bar heights**: the lowest shown week at 25 % of the 96-pt track (3 × `xxl`; v2 draws its lowest at about a
   quarter of 89 px), the highest at 100 %, linear between; one value alone is full height.
3. **PR tag**: bold ink (`numeralS`), never orange (criterion 12, Q3 A); "+5 lb" `inkSecondary`; "—" too.
4. **Session rows** are F06's `HairlineRow` (date as the title, sets joined by spaces as the detail, the tag as the
   accessory), one button each; VoiceOver reads the date, then "PR, 180×5, …".
5. **Failed state**: a source that ends, a read that fails, or an exercise that is not stored. Title new (below),
   body the Library's.
6. **The history's title** keeps the identifier `library.history.title`, so the nightly `Library` UI test now finds
   the real screen (label "Chest-Supported Row").
7. **The PR-sweep fold budget** is close: 4.1 ms p95 against 5 ms on the Debug simulator (N11).

### New wording for Pete

All in `LibraryCopy+History.swift`: "1RM est", "best set", "sessions", "×5", "ESTIMATED 1RM · 8 WEEKS", "W1"…"W8",
"Log a session to start the chart.", "SESSION LOG", "No sessions yet.", "PR", "180×5", "+22 lb" / "−22 lb" / "0 lb"
(and kg), from the brief. **Not in the brief:** "Can't show this exercise's history right now" (failed title);
VoiceOver's "Estimated 1RM by week", "Week", "Pounds" / "Kilograms" (chart descriptor). The "—" key's comment now
covers every dash.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 4 (219, 195×5, weeks, +28 lb) | `ExerciseHistoryPresentationTests.criterion4_statsWeeksAndChange`; domain `e1RM_isBrzyckiOfTheBestSetUpTo12Reps` |
| 5 (gaps, no data) | domain `weeks_eightEndingNow_emptyWeeksNil`, `noCountedSet_hasNothing`; presentation `noData_saysSo`, `oneWeek_hasNoChange`; snapshots `gaps`, `noData` |
| 6 (100×15) | domain `e1RM_ignoresRepsOver12`; presentation `repsOver12_haveNoEstimate` |
| 7 (C12 fixture) | domain `tags_criterion7_prUpSame` (records detected by `PersonalRecords`), `tags_firstSessionIsSame_recordWins`, `tags_compareWorkingSetsOnly`; presentation `criterion7_tagsAndDates` |
| 8 (kg) | presentation `kilograms_convertEverything`, `change_fallAndNone`; store `unitsChanged_redraws`; snapshot `kilograms` |
| 11 | presentation `entry_routesToItsWorkout`; store `route_isDeliveredOnce`; root `root_runsTheStore_andHandsARouteOnce`; AX `sessions_sendTheirRoutes`; `LibraryRouteMappingTests.openWorkout_selectsTheHistoryTab` |
| 12 (descriptor, orange) | AX `descriptor_readsTheWeeksValues` (R3's fallback: `makeChartDescriptor()` read directly); `ExerciseHistoryOrangeAuditTests` (2 × 2 themes); SRC `views_wearNoAccent` |
| N9 | contract clause `exerciseSessions` (GRDB, in memory, `HistoryModel`); `ExerciseSessionsPropertyTests` (40 seeds × 14 steps: GRDB = model = fakes, fold = GRDB's queries) |
| N10 | domain tag tests; deload: the contract history includes one |
| N11 | Nightly `StatsQueriesPerformanceTests`: `exerciseSessions` 13.1 ms p95 (budget 50); fold over 1,703 sets 4.1 ms p95 (budget 5) |
| N12 | AX `tree_isExactlyTheTable` (list at AX sizes), layout `stats_stackAtAccessibilitySizes`, snapshot `logged` at `.accessibility3` |
| N13 | store `workoutFinishedAndRename_show` |
| N14 | presentation `date_ofAnotherYear_carriesItsYear` |
| Failed state | store `failures_showFailed`; root `root_drawsTheFailedMessage` |

All written alongside the code; the snapshots failed first (`.missing`), and the descriptor test failed to
compile first (point values are refined for Swift out of reach; it reads the points' labels).

**VoiceOver (DoD).** Not checked by ear: the hosted reader does not hand the descriptor over (R3); the descriptor
is tested directly. A manual VoiceOver pass on the simulator remains for review.

### Sanctioned edits of others' tests

| File | Edit | Why |
|---|---|---|
| `LedgerPersistenceTests/Adversarial/HistoryModel+Stats.swift` | `exerciseSessions` from its own live workouts | A protocol requirement (N9) |
| `LedgerPersistenceTests/Adversarial/HistoryContractAdversarialTests.swift` | 24 → 25 clauses | N9 |
| `LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift` | `BriefStatsQueries.exerciseSessions` returns `[]` | Requirement |
| `FeatureWorkoutTests/Support/ReceiptSupport.swift` | forwards `exerciseSessions` | Requirement |
| `FeatureLibraryTests/LibraryStoreAdversarialTests.swift` (G2's) | `FailingBests` forwards it | Requirement |
| `LedgerDependenciesTests/UnimplementedStubTests.swift` | the stub list gains it | Requirement |
| `LedgerPersistenceTests/Performance/StatsQueriesPerformanceTests.swift`, `PerformanceBudget.swift` | one query line, the fold timing and `historyFold` | N11 |
| `LedgerAppKitTests/ModuleCopyTests.swift` | 8 → 7 | S1's edit reverted |
| `LedgerAppKitTests/Adversarial/AppCopyAdversarialTests.swift` | "Exercise history" out of `shellStrings` | Reverted |
| `LedgerAppKitTests/AppTabsTests.swift` | `exerciseDestination_drawsItsPlaceholder` and its `import LedgerDomain` removed | Reverted |
| `LedgerDesignTests/__Snapshots__/PhoneComponentSnapshotTests/statTile_*` (6) | re-recorded | The gallery's "218" is orange; per-pixel diff confined to the value's box in each; looked at |
| `Apps/LedgerUITests/LibraryAuditAdversarial.swift`, `PlaceholderInk.swift` (G2's) | R2-1 comments, R2-3 assertion | Ruled |

My own (S1) tests amended: `FeatureLibrarySourceTests` (store files, the descriptor's import, two screens' scroll
views, the accent spelled only in `E1RMChart`), `PreviewTests` (history previews), `LibraryStoreTests`
(`UnreadableBests` forwards), `LibraryRouteMappingTests` (+1 test), UI `Library` (history title).

### References (10 new, looked at each)

`FeatureLibraryTests/__Snapshots__/ExerciseHistorySnapshotTests/`: `logged` light/dark at `.large` and
`.accessibility3`, `gaps`, `noData`, `kilograms` light/dark at `.large`. Bars rise W1→W8 with W8 orange; W3 and W6
keep their labels with no bar; the list replaces the bars at `.accessibility3` with the stats stacked; kg reads
102 / 90.7×5 / +10 kg.

### Product lines

Against `d92cc15`, non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps` without `LedgerTestSupport`, the
UI tests and the catalogs: **842 added, 16 removed (net 826)**; `Package.swift` unchanged. Of it the R2 commit is
about 10. By area: FeatureLibrary 671 (store 148, presentation 122, previews 74, copy 74, chart 74, model 57, screen
48, root 40, session log 27, descriptor 25, route and copy edits 3); Domain 94; Persistence 23; Fakes and stub 21;
LedgerDesign 9; LedgerAppKit −1 net. Under the 950 stop line; the plan's 895 held.

### PR-sweep seconds (R6)

`TEST_RUNNER_LEDGER_SWEEP=pr`, PR plan, sums of per-argument durations: accessibility 1.16 s (22), layout 1.60 s
(40), orange 0.25 s, snapshots 0.43 s, root 0.13 s, store and presentation 0.03 s, previews' new cases about 0.2 s,
SearchField fit +0.15 s for the three widths. **Added ≈ 4.0 s.**

### Runs

- Host `swift test` over the whole package: green (one known issue, already there).
- Simulator, PR plan, PR sweep: `FeatureLibraryTests`, `LedgerDesignTests`, `LedgerAppKitTests`: 861 tests, 0
  failures (after recording the 10 history references and the 6 StatTile ones).
- Nightly: UI `Library` and `LibraryAuditAdversarial` (5 tests) pass; `StatsQueriesPerformanceTests` passes.

### The gate

`scripts/check.sh` through the lock on `057391d`: **exit 0, "check.sh OK", 1,894 s** (lint 78 s, iOS build 21 s,
iOS tests 1,507 s, watchOS build 46 s, watchOS tests 237 s, coverage 2 s; overall 98.69 %). The only commit after
`057391d` is this paragraph.

### Fix round 1 (G1, 2026-10-24): G2's F12-S2-1 to -4, as the orchestrator ruled

The ruling is in `test-findings.md`, "Orchestrator's ruling (S2 round 1)". F12-S2-5 is kept as built (a candidate
for Pete); F12-S2-6 (the Library store's same miss) is a follow-up for S3 or F13, and `LibraryStore` is unchanged.

- **F12-S2-1 ("+0 lb").** `ExerciseHistoryPresentation.heavier`: the step is written with `formatted(in:)`, and a
  step that writes as zero does (`Weight.zero.formatted(in:)`) reads "—", as the two sets read the same. The PR tag
  is untouched. G2's `tag_tinyStepAcrossUnits_neverReadsPlusZero` passes as written.
- **F12-S2-2 ("1 sessions").** `LibraryCopy.sessionsCaption(_:locale:)` is the Library row's counted "%lld
  sessions" (looked up with `locale.forCountedText`), without its number. **Why not a plural key of the bare
  word:** standards §7 and the catalog audit (`StringCatalog.pluralProblems`) require a counted key to hold its
  `%lld` in every form, so a form "session" with no number fails the gate. The caption is therefore the counted
  text with the number removed, written as the lookup writes it (`count.formatted(.number.locale(…))`): the
  catalog picks the form, and the number is the tile's value. Tested at 0, 1, 2, 1,234 and 1,000,000 in en_US,
  de_DE, fr_FR, hi_IN and ar_EG. The old "sessions" key is gone. **VoiceOver:** `Stat.spoken` is the whole counted
  text, handed to `StatTile(accessibilitySummary:)`, so the tile reads "1 session" (it read "1, sessions").
- **F12-S2-3 (older workout changes missed).** `StatsQueries.observeExerciseSessions(exerciseID:)`: GRDB
  `ValueObservation` of the same fetch with `removeDuplicates()` (`sessionsObservation`, beside
  `recentObservation`; `exerciseSessions` reads through the same `fetchSessions`), in memory over the history's
  `ObservedState`, and the Unimplemented stub's empty stream. `ObservedState` now takes the value type per
  `observe` call (its observers are closures), so one state can be observed as two types; its four users lose
  the second generic argument. Contract clause 26: the observation emits after the newest workout, after an
  older one, after `updateSets` and `delete` of the older one, and nothing for writes of another exercise alone.
  The store follows it instead of `observeRecent(limit: 1)`; on each emission it reads the sessions and records
  together, as before, so the failed-read and overtaken-read paths are unchanged. `workoutRepository` is no longer
  a dependency of the history's store. Both G2 store tests pass.
- **F12-S2-4 (the chart speaks only its name).** `Chart.spokenSummary`: "Up 28 lb over 8 weeks" / "Down …" / "No
  change over 8 weeks", or the no-data message; nil when one week alone has a value (no change to read). It is the
  descriptor's `summary` and the bars element's `accessibilityValue`.

**New wording for Pete:** "Up %@ lb over 8 weeks", "Down %@ lb over 8 weeks", the two kg forms and "No change over
8 weeks" (VoiceOver only). The visible caption is unchanged but for "session" under 1.

**Sanctioned edits of others' tests:** `HistoryContractAdversarialTests` 25 → 26 clauses; `HistoryModel` (+Stats)
observes sessions (its own observer list, `emitsEveryWrite` honoured); the forwarding doubles (`ReceiptSupport`,
`FailingBests`, `UnreadableBests`, `UnreadableSessions`, G2's `GatedSessions`) forward
`observeExerciseSessions`; `BriefStatsQueries` returns a finished stream; `UnimplementedStubTests` checks the new
stream ends. My own: `ExerciseHistoryAccessibilityTests` (the stats read `spoken` when there is one; the chart
element has the summary as its value), `ExerciseHistoryLayoutTests` (finds the tiles by the same labels),
`ExerciseHistoryOrangeAuditTests` (the new field), `ExerciseHistoryPresentationTests` (+1 test over 5 locales;
summary and spoken expectations). No snapshot reference changed (nothing drawn changed at the fixtures' counts).

**Product lines** (same rules): against `d92cc15`, **939 added, 40 removed (net 899)**; this round +73 net. Under
the 950 stop line.

**Runs.**
- Host `swift test` over the whole package: exit 0, no ✘ lines (the known issues already there).
- `scripts/check.sh --lint-only`: exit 0.
- Simulator, PR plan, `TEST_RUNNER_LEDGER_SWEEP=pr`: `FeatureLibraryTests`, `LedgerDesignTests`, `LedgerAppKitTests`,
  G2's three adversarial suites, `StatsQueriesTests`, `InMemoryContractTests`, `HistoryContractAdversarialTests`,
  `UnimplementedStubTests`. First run exit 65: the accessibility tree and layout tests still expected "6, sessions"
  and no chart value (updated above). Second run: exit 0, 916 passed, 0 failed, 3 skipped.
- Simulator, Nightly: `LedgerUITests/HistoryVoiceOverAdversarial` and `LedgerUITests/Library`: exit 0, 4 passed.

**The gate (fix round 1).** `scripts/check.sh` through the lock on `a8a041a`: **exit 0, "check.sh OK", 1,858 s**
(lint 79 s, iOS build 15 s, string catalogs 1 s, iOS tests 1,480 s, watchOS build 51 s, watchOS tests 231 s,
coverage 1 s; overall 98.70 %). The only commit after `a8a041a` is this paragraph.

### Review round 1 (G1, 2026-10-24): G3's F12-S2-R1-1 to -8, as the orchestrator ruled

The ruling is in `review.md`, "Orchestrator's ruling (S2 review round 1)".

- **R1-1 (the fold at 2,000 sets).** `ExerciseHistory.make` walks the counted sets once into
  `PersonalRecords.Tally<Weight>.atReps` (the heaviest weight at each rep count) and takes Brzycki of those
  candidates only; the best set is the heaviest of the same tally (as `Bests.bestSet(of:)`), and each week does
  the same over its sessions. Brzycki, rounded to the gram, rises with the weight at fixed reps, so the results
  are the same; the domain, property and differential tests pass unchanged. The Nightly fold now times 2,000 sets
  in 400 sessions from `Seeders.exerciseSessions(of:sessions:setsPerSession:rng:)` (new, LedgerTestSupport: one
  lift's `Seeders.history`, every row done), budget still 5 ms; `PerformanceBudget.historyFold`'s comment says so.
- **R1-2 (the model at 2,000 sets).** `LibraryPerformanceTests.historyModel_underAFrame`: the model over the same
  2,000 sets, median of five, budget 16 ms. **First measured 24.1 ms on the host (Debug): it failed.** Most of it
  was 2,000 `LibraryCopy.set` lookups (13 ms). Two changes, as ruled and to make the budget hold:
  - `ExerciseHistoryPresentation.SetTexts` writes each weight × reps once per model (a lifter repeats a few):
    **9.2 ms on the simulator, 8.8 ms on the host**;
  - the store builds the model off the main actor (`@concurrent nonisolated static func model(_:)`; input and model
    are `Sendable`), because 2,000 sets of 2,000 different weights still take 24 ms (measured by hand on the host,
    not committed). The generation guard on the records read is unchanged; a model a change overtook while it was
    built is shown, and the change's turn builds the next, as with an overtaken read.
- **R1-3.** The store keeps the sessions the observation emits (`Sources.sessions`), and reads only
  `personalRecords` per change (`readRecords()`), with the same generation guard. The failed and overtaken-read
  doubles now act on the records read: G2's `SessionsGate`/`GatedSessions` are `RecordsGate`/`GatedRecords`, my
  `UnreadableSessions` is `UnreadableRecords`; both G2 tests pass as written otherwise.
- **R1-4.** The caption's derivation left `LibraryCopy` (now lookups only) for
  `ExerciseHistoryPresentation.sessionsStat(_:locale:)`: one `count.formatted(.number.locale(locale.forCountedText))`
  is the tile's value and what is removed from "%lld sessions". Its comment names the follow-up (a numberless
  caption key with an audit exception), Pete's call. `LibraryCopyTests.sessionsForms_areTheNumberThenWords` reads
  the catalog and holds every form of "%lld sessions" in every localization to `%lld`, one space, then a word
  with no digit and no `%`.
- **R1-5.** With sessions but no week with an estimate, the chart (and its spoken summary) reads "No set of 12 reps
  or fewer in the last 8 weeks." (`LibraryCopy.noEstimate`); "Log a session to start the chart." stays for no
  session at all.
- **R1-6.** `StatsQueriesContract.observeExerciseSessions` reads the stream through `StreamArrivals`
  (LedgerTestSupport, new): one task takes every value as it is sent, so none is replaced unseen in the bridge's
  buffer of one, and after the row's workout and after the row's edit a read waits `quiet` (200 ms) and must get
  nothing. **Proved:** with `removeDuplicates()` taken out of `GRDBStatsQueries.sessionsObservation`, the GRDB
  clause failed ("a value after the row's workout, which is unheard: got Optional(["1"]), expected nil"); restored,
  it passes (`git diff` of LedgerPersistence empty).
- **R1-7.** (a) The delta is hidden from VoiceOver where the bars are drawn (their value speaks the change); it
  stays a stop at accessibility sizes, where the weeks are a list. (b) The spoken change names its span, from the
  first week with a value to the last, both counted: "Up 11 pounds over 4 weeks" from W5, "over 8 weeks" from W1.
  The five keys are counted ("%lld weeks", one and other forms). (c) The unit is spoken as S1's rows speak it
  (`spokenRecord`'s "pounds" / "kilograms"). Stat tiles unchanged.
- **R1-8.** The sessions tile's value is that same formatter's: "1,234", and Arabic digits in ar_EG.

**New wording for Pete:** "No set of 12 reps or fewer in the last 8 weeks." (visible and spoken); VoiceOver's
"Up %@ pounds over %lld weeks", "Down %@ pounds over %lld weeks", the two kilograms forms and "No change over %lld
weeks" (singular "week" forms exist but are unreachable: a change needs two weeks). They replace round 1's "Up %@
lb over 8 weeks" and its siblings. Like S1's "PR 1 pounds" (n1 follow-up), a change of 1 reads "Up 1 pounds".

**Sanctioned edits of others' tests:** G2's `HistoryAdversarialDoubles` and `ExerciseHistoryAdversarialTests`
(the gate moves to the records read, R1-3); `StatsQueriesPerformanceTests`, `PerformanceBudget` (R1-1). My own:
`ExerciseHistoryPresentationTests` (spoken wording, R1-5's message, +1 span test, the sessions stat over 5 locales
with its value), `ExerciseHistoryAccessibilityTests` (the delta is a stop only at accessibility sizes),
`ExerciseHistoryStoreTests` (`UnreadableRecords`), `LibraryCopyTests` (+1), `LibraryPerformanceTests` (+1). No
snapshot reference changed (nothing drawn changed at the fixtures).

**Product lines** (same rules): against `d92cc15`, **984 added, 40 removed (net 944)**; this round +45 net. Under
the 1,000 line.

**Measured** (Nightly plan, simulator, Debug): fold over 2,000 sets **2.49 ms p95** (budget 5; round 1's 1,703
sets took 4.1 ms); model over 2,000 sets **9.17 ms median** (budget 16); `exerciseSessions` 13.3 ms p95,
`personalRecords` 0.28 ms p95. Host, Debug: fold 2.4–2.5 ms, model 8.6–9.1 ms.

**Runs.**
- Host `swift test` over the whole package: exit 0, no ✘ lines.
- `scripts/check.sh --lint-only`: exit 0 (after wrapping a line, splitting the presentation's helpers into an
  extension, and extracting the fold timing into `foldUnderBudget`).
- Simulator, PR plan, `TEST_RUNNER_LEDGER_SWEEP=pr`: `FeatureLibraryTests`, `LedgerDesignTests`,
  `LedgerAppKitTests`, `StatsQueriesTests`, `InMemoryContractTests`, `HistoryContractAdversarialTests`,
  `HistoryCloseoutAdversarialTests`, `ExerciseSessionsPropertyTests`, `ExerciseHistoryWeeksAdversarialTests`, the
  domain's `ExerciseHistoryTests`, `ExerciseHistoryAdversarialTests`, `ExerciseHistoryPropertyAdversarialTests`,
  `UnimplementedStubTests`: exit 0, 947 tests, 936 passed, 0 failed, 4 skipped, 7 expected failures.
- Simulator, Nightly: `StatsQueriesPerformanceTests`, `LibraryPerformanceTests`, UI `HistoryVoiceOverAdversarial`
  and `Library`: exit 0, 8 passed.

**The gate (review round 1).** `scripts/check.sh` through the lock on `d8b909c`: **exit 0, "check.sh OK", 1,885 s**
(lint 77 s, iOS build 17 s, string catalogs 1 s, iOS tests 1,501 s, watchOS build 32 s, watchOS tests 256 s,
coverage 1 s; overall 98.68 %). The only commit after `d8b909c` is this paragraph.

## S3 — as built (G1 implementer, 2026-10-26)

Branch `feat/F12-s3-create`, cut from `main` at `20aac83` plus the spec commit `235e845`. The specification is the
brief's slice S3 (criteria 9 and 10 as restated per C13 and C14, N15–N18), the "S3 amendments (orchestrator,
2026-10-26)" (N19, N20), and Pete's Q2 = A, Q4 = A/A, Q5 = A.

### Commits

- `526575a` feat(library): `CustomExerciseDraft`, the lifter's exercise built from the form (N15).
- `03a0de5` feat(library): the "+step" tag passes over sessions with no set that counts (N19).
- `afbd81c` feat(library): the Library follows every workout of the history (N20, F12-S2-6).
- `64e1955` feat(library): New exercise and Edit, the lifter's own exercise in a sheet.
- `4ab36d3` feat(workout): a receipt row opens its exercise's history (N18).
- this notes commit (docs only).

### What landed

Paths under `LedgerKit/`.

- **Domain.**
  - `LedgerDomain/Exercises/CustomExerciseDraft.swift` (the brief's path). The draft holds the name as typed,
    the equipment, the primary muscle, a `Set` of secondary muscles and the pattern. `exercise(id:among:)
    throws(CustomExerciseError)` checks, in this order: the trimmed name is blank; it is not 2–40 `Character`s;
    it holds a Unicode `Cc` scalar (U+0000 among them); another live exercise has the same `ExerciseSearch.key`
    (the one with `id` is left out, so an edit keeps its own name); the primary muscle is among the secondaries.
    It then builds a custom `Exercise`: the short name is the name, the start load is 0 in both units, there are
    no curated alternatives, and the secondaries are in `MuscleGroup.allCases` order (Q4 A/A). The step is the
    equipment's default, `Equipment.defaultStep(in:)`, which an `Exercise` does not store.
  - `CustomExerciseError` lives in `Errors.swift`, beside `ProgramEditError` (C9).
  - `Model/LibraryStats.swift` holds the recent ids, their session counts and every best set. It was FeatureLibrary's
    private struct; it moved to the Domain for N20.
  - `StatsQueries.observeLibraryStats(recentLimit:)` (N20).
  - N19: `ExerciseHistory.log(of:records:)` makes one walk from the oldest session. It carries the latest top
    weight of a session that has a counted set.
- **Persistence, fakes, stub.**
  - `GRDBStatsQueries+Library.swift` gains `libraryObservation(recentLimit:)`. It is one `ValueObservation`
    that reads `recentlyLogged`, each recent exercise's `sessionCount` and `bestSets` in one access, with
    `removeDuplicates()`.
  - The three reads became static fetchers inside a database access (`fetchRecentlyLogged`,
    `fetchSessionCount`, `fetchBestSets`), shared by the async queries and the observation. The first two
    moved into the `+Library` file to keep `GRDBStatsQueries.swift` under the lint's 300 lines.
  - `InMemoryStatsQueries` does the same over the history's `ObservedState`, with three static helpers.
  - The Unimplemented stub returns its empty stream.
- **Contract.** `StatsQueriesContract` gains clause 27, `observeLibraryStats`. It runs on GRDB, on the in-memory
  stores and on `HistoryModel`. The stream emits:
  - the empty stats first;
  - after the newest workout, and after an older one;
  - after an oldest workout, whose exercise has a best but is not recent (limit 2);
  - nothing within `quiet` after a workout with nothing done;
  - after `updateSets` of an older workout;
  - after the newest workout is deleted.

  Each value equals what the three reads return.
- **FeatureLibrary.**
  - `CreateExerciseModel.swift` holds `CreateExerciseAction`, `CreateExerciseProblem`, `CreateExerciseInput` and
    `CreateExerciseModel`.
  - `CreateExercisePresentation`, `CreateExerciseStore`, and `LibraryCopy+Create` (the sheet's words and the ten
    pattern names).
  - `CreateExerciseSheet` is the owner view. It holds the store, runs the save from `.task(id: attempt)`, and
    closes when the phase is `.saved`.
  - `Views/CreateExerciseScreen.swift` holds the screen, page, name field and foot, on `SheetChrome`.
  - `Views/Create+Previews.swift` has five states: empty, filled in, name taken, save failed, edit.
  - `LibraryRoot` presents the sheet from `isNewExerciseShown`, and a new `LibraryAction.newExerciseClosed` sets
    the flag back.
  - `ExerciseHistoryModel.edit` is "Edit" for a custom exercise and nil otherwise. The history store has
    `edit()` and `editClosed()` and keeps `editedExercise`. `ExerciseHistoryRoot` presents the sheet with
    `.sheet(item:)`, and `ExerciseHistoryScreen` puts "Edit" in the bar (`library.history.edit`).
  - `LibraryStore+Sources` follows `observeLibraryStats` in place of `observeRecent(limit: 1)` and the stats
    read. `followedWorkouts`, `readStats()`, the stale counter and the store's `workoutRepository` dependency are
    gone.
- **LedgerDesign (A3).**
  - `FilterChipRow(…, allowsMany:)`: each chip of such a row carries the `.isToggle` trait, so VoiceOver reads
    it as a switch with the value "1" or "0". It draws as before, and the default `false` changes nothing for
    F11 or S1.
  - `ReceiptLayout(model:onRow:)`: with an action, each row is a `Button` (`LedgerPressStyle`, the same
    `spoken` label) that hands back its place.
- **FeatureWorkout and LedgerAppKit (N18, Q2 A).**
  - `WorkoutAction.openExercise(ExerciseID)` and `WorkoutRoute.exercise(ExerciseID)`.
  - `ReceiptScreenModel.rowActions` comes from the same zip as the rows, so the two keep the same order.
    `ReceiptPage` sends `rowActions[place]`.
  - The store accepts `.done` and `.openExercise` on the receipt only (`WorkoutAction.isReceipts`). Both close
    the cover once, through `closeReceipt(showing:)`.
  - `Routes+Workout` resolves `.exercise(id)` with `open(.exercise(id), in: .today)`: Today, as for "Done", one
    step deeper. The push is no presentation, so it may happen as the cover goes down. The nightly UI test
    proves it on the simulator.
- **Catalog.** 22 new keys. The comments of "New exercise", "Equipment" and "Core" were widened: each key now also
  serves the sheet's title, a field heading and the core pattern.

No change to `Package.swift`, the project file, a test plan or `.github/`.

### Decisions and deviations

1. **N19, the amendment's parenthetical read literally.** "Has a working set (working or added, decision #25's
   rule, `PersonalRecords.countsTowardBests`)" defines the sets that are compared. So both sides of "+Δ" now use
   `countsTowardBests`:
   - a session's top weight is its heaviest working or added set;
   - the comparison is with the latest earlier session that has one.

   **This changes S2's rule.** "+Δ" no longer ignores added sets (S2's `tags_compareWorkingSetsOnly`, now
   `tags_compareCountedSetsOnly`). The other reading, working sets alone with only the skip changed, would make an
   added-only session reset nothing and step from nothing. Sessions with only warm-ups or drop sets are passed
   over and read "—". *If the orchestrator meant `.working` alone, the change is one filter in
   `topCountedWeight(of:)`, plus the two tests and G2's oracle.*
2. **N20: the observation emits the Library's stats themselves,** not a signal to read them again. The history's
   sessions observation works the same way, and the store keeps no stale counter.
   - **Consequence:** a failed read ends the stream (GRDB's `ValueObservation`), so the failed state is left at the
     next run (the tab or the app coming back), no longer at the next change.
   - G2's `statsReadFailsOnce_nextWorkout_…` became `…_nextRun_…` (a sanctioned edit). Its double makes the
     observation end.
   - Cost: one GRDB re-read of the three queries per write to the tracked tables while the Library's task runs,
     which includes the live workout's own writes. The reads run on GRDB's reader, off the main actor, and the
     duplicates are dropped. The S1 budget for `bestSets` (under 50 ms p95 over 20k sets) bounds each one.
3. **A new draft** starts with Barbell, Chest and Horizontal push, the first case of each enum, so every
   single-choice field has a chip chosen. The brief gives no error for "no pattern chosen".
4. **The primary muscle has no chip among the secondary muscles** (10 chips, not 11). Choosing a primary muscle
   removes it from the secondaries. The Domain still refuses the overlap (`primaryAmongSecondaries`); were it ever
   thrown, the sheet would show the save-failed line.
5. **"Save" is the foot's `PrimaryButton`,** the sheet's one orange, as the picker's "Add" is. `SheetChrome` has no
   second header button. While a save runs it is disabled.
6. **Problems** are shown when Save finds them, not while the lifter types. A change to any field clears the line.
   The name's rules show under the field; a failed save (and the unreachable muscle rule) shows over Save.
7. **A catalog exercise is never saved from the sheet.** The history offers no "Edit" for one. If the sheet were
   given one, the store would refuse it before any write (`CreateExerciseStoreError.catalogExercise`), log it, and
   show the save-failed line.
8. **Edit (Q5 A)** builds the exercise again from the draft under its id. Every field can change, and the start
   load stays 0. Workouts keep their snapshot name; the open history and the Library follow `observeAll` (N13).
9. **"Edit" is a system bar button.** It takes the stack's tint, as the back button beside it does (`AppTabs` sets
   each stack back to the system's tint). It is not one of criterion 12's three oranges.
10. **The receipt's row action** has no gallery reference of its own: it draws exactly as the plain row. F10's
    receipt references are now drawn with the action, and all of them compared clean, which is the proof. The
    LedgerDesign tree table gains two cases (rows as buttons, at the default size and stacked at `.accessibility3`),
    and `ReceiptLayoutRowActionTests` activates each row.
11. **The sheet's owner is a module-level file** (`CreateExerciseSheet.swift`, in `FeatureLibrarySourceTests`'
    store files), as the roots are. Its drawing lives in `Views/`, with the third screen-level scroll view.

### New wording for Pete

- From the brief: "Edit exercise", "Cancel", "Save", "Name", "Primary muscle", "Secondary muscles",
  "Movement pattern", "Enter a name.", "Name must be 2–40 characters.", "An exercise with that name already
  exists.". "New exercise" and "Equipment" reuse S1's keys.
- **Not in the brief:**
  - "Edit" (the history's bar button);
  - "That name holds a character that can't be saved." (a pasted tab, line break or other control character);
  - "Couldn't save the exercise. Try again.";
  - the ten pattern names: "Horizontal push", "Horizontal pull", "Vertical push", "Vertical pull", "Squat",
    "Hinge", "Lunge", "Carry", "Isolation", and "Core" (the muscle's key).

  Spoken chips read "Primary muscle: Chest" and "Secondary muscles: Triceps", through S1's "%@: %@".

### Criteria → tests

Suites, all new unless marked:
- In `FeatureLibraryTests`: `CreateExerciseStoreTests` (+`Saving`) (S), `CreateExercisePresentationTests` (P),
  `ExerciseHistoryEditTests` (E), `CreateExerciseAccessibilityTests` (AX, iOS), `CreateExerciseLayoutTests` (L,
  iOS), `CreateExerciseSnapshotTests` (SN), `LibraryStoreTests+History` (LS), and `PreviewTests` (edited).
- Elsewhere:
  - in `LedgerDomainTests`: `CustomExerciseDraftTests` (D) and `CustomExerciseDraftPropertyTests` (DP);
  - in `FeatureWorkoutTests`: `ReceiptRowRouteTests` (RR), plus the edited `ReceiptTests` and
    `ReceiptLayoutTests`;
  - in LedgerDesignTests: `ReceiptLayoutRowActionTests` (RA), plus two tree cases;
  - in LedgerAppKitTests: `LibraryRouteMappingTests` (RM);
  - the contract (K), and the Nightly UI test `LibraryCreate` (UI).

| Criterion | Tests |
|---|---|
| 9 (create, list, picker, errors) | S `save_insertsAndCloses`, `save_appearsInTheLibrary` ("Barbell · Chest · Custom"), `errorsShown`; D `buildsCustomExercise`; UI `test_newExercise_isListedAndPicked_andEditRenamesIt` (Library row with "Custom", then the Day editor's picker finds it). The swap clause is F10 S8's (C14) |
| 10 (Edit, custom only) | P `historyEdit_customOnly`; E `edit_custom_opensAndCloses`, `edit_catalog_opensNothing`; S `editCustom_storesUnderItsID`, `editCatalog_isRefused`; UI (Edit renames the open history) |
| N15 | D (all), DP `randomName_keepsTheRules` (`PropertySeed.all` × 20 names of letters, marks, fullwidth, emoji, blanks, line breaks and controls, against a plain reading of the rule); S `primaryMuscle_isNeverSecondary` |
| N16 | S `doubleTap_savesOnce` (a held read; the second `save()` and taps do nothing; one `save`), `failure_keepsTheSheet` (then Save works again), `cancellation_changesNothing` (cancelled while the read is held: no write, no line) |
| N17 / Q4 | D `buildsCustomExercise` (short name, start 0 in both units, no alternatives) |
| N18 / Q2 | RR (three tests); RA; RM `receiptRow_pushesTheHistoryOnToday`; `ReceiptTests.done_sendsDone` (sanctioned); UI `test_receiptRow_opensTheExercisesHistoryOnToday` (receipt row → history title, Today selected, back is Today) |
| N19 | `ExerciseHistoryTests.tags_compareCountedSetsOnly`, `tags_sessionsWithoutCountedSets_arePassedOver`; G2's pin and property oracle (sanctioned) |
| N20 | LS `olderWorkoutChanges_whileRunning_show` (older finished, edited, deleted); K clause 27 on GRDB, in memory and `HistoryModel`; `LibraryStoreTests.statsReadFails_showsFailed` |
| Sheet accessibility | AX `tree_isExactlyTheTable` (5 states × sizes), `secondaryMuscles_areSwitches`, `controls_sendTheirActions`, `saving_dimsSave`, `targets_areAtLeast44Points`, `nameField_isTheOneField` (the one `UITextField`, placeholder "Name") |
| Sheet layout | L `parts_layOutSanely` (5 states × settings), `header_titleAndCancel` |

All were written alongside their code. The snapshots failed first (missing). `receipt_nothingLeavesOrOverlaps`
(F10's) failed first on the rows that are now buttons, which is the sanctioned edit below. I did not watch the N20
store test fail against the old store.

### References (7 new, I looked at each)

`FeatureLibraryTests/__Snapshots__/CreateExerciseSnapshotTests/`:
- `empty` and `filled`, light and dark, at `.large`;
- `nameTaken`, light and dark, at `.large`;
- `filled` at `.accessibility3`, dark (`filled_matchesReferences.filledAccessibility3-dark-accessibility3.png`).

What they show:
- the title with "Cancel" beside it, under it at `.accessibility3`;
- the NAME eyebrow over an outlined field, and the duplicate line under it;
- four chip fields, with the chosen chips filled;
- the secondary row without the primary's chip;
- an orange Save under a rule.

**No existing reference changed.** That includes the gallery, `FilterChipRow` and F10's receipt references.

**A known limit, visible in the `.accessibility3` reference.** While the name field has no focus, a name longer
than its line is cut with "…" ("Landmine Squeeze…"), as every one-line `TextField` is. C26 prescribes a plain
one-line field. F11's `NameField` draws the whole name as text that wraps, but it is FeatureProgram's. Open
question 1.

### Sanctioned edits of others' tests

| File | Edit | Why |
|---|---|---|
| `LedgerDomainTests/Adversarial/ExerciseHistoryAdversarialTests.swift` (G2) | `tags_predecessorWithoutWorkingSets_isSame` became `tags_predecessorWithoutCountedSets_isPassedOver`: the middle session holds warm-ups and a drop set, and the expectation is `[+10, —, —]` | N19 overturns F12-S2-5's pin |
| `LedgerDomainTests/Adversarial/ExerciseHistoryPropertyAdversarialTests.swift` (G2) | The oracle's `topWorking` counts working and added sets, and compares with the latest earlier session that has one | N19 |
| `FeatureLibraryTests/LibraryStoreAdversarialTests.swift` (G2) | The failed read is left at the next run; `FailingBests.observeLibraryStats` ends the stream for each failure; the header comment | N20 |
| `FeatureLibraryTests/Support/HistoryAdversarialDoubles.swift` (G2), `FeatureWorkoutTests/Support/ReceiptSupport.swift` | Forward `observeLibraryStats` | A protocol requirement |
| `LedgerPersistenceTests/Adversarial/HistoryModel.swift`, `HistoryModel+Stats.swift` | `writeSignals`, and `observeLibraryStats` over the three queries (every write with `.emitsEveryWrite`) | Requirement, clause 27 |
| `LedgerPersistenceTests/Adversarial/HistoryContractAdversarialTests.swift` | 26 → 27 clauses | N20 |
| `LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift` | `BriefStatsQueries` returns a finished stream | Requirement |
| `LedgerDependenciesTests/UnimplementedStubTests.swift` | The stub's `observeLibraryStats` ends at once | Requirement |
| `FeatureWorkoutTests/ReceiptTests.swift` | The rows are `.button` stops in `tree` and in `withRecords`; `done_sendsDone` expects Done plus each row's `rowActions` | N18 (A7) |
| `FeatureWorkoutTests/ReceiptLayoutTests.swift` | `receipt_nothingLeavesOrOverlaps`: the buttons are Done plus the rows, each still a 44-pt target | N18 (A7) |
| `FeatureWorkoutTests/Support/ReceiptParts.swift` | `ReceiptPage(model:rowActions:send:)` | N18 |
| `FeatureWorkoutTests/Adversarial/WorkoutSaveAdversarialCover.swift` (G2) | `exitFault` handles `.route(.exercise)` as a saved close | The exhaustive switch |
| `LedgerDesignTests/AccessibilityTreeReceiptTables.swift` | Two cases with the row action | A3 |

My own tests amended:
- `ExerciseHistoryTests` (N19);
- `LibraryStoreTests`: `UnreadableBests` ends the observation, and the New exercise test closes the sheet;
- `ExerciseHistoryStoreTests`: forwarding;
- `FeatureLibrarySourceTests`: the store files, and the third screen with a scroll view;
- `PreviewTests`: `CreatePreview`;
- `LibraryRouteMappingTests`: one test.

### Product lines

Measured against `235e845`, by the same rules as S1 and S2: non-blank, non-comment Swift in `LedgerKit/Sources`
and `Apps`, without `LedgerTestSupport`, the UI tests or the catalogs.

**854 added, 152 removed: net 702.** `Package.swift` is unchanged. The plan was about 675; the stop line is
about 1,000.

By area:
- FeatureLibrary: the sheet's stack 513 (screen 103, store 97, presentation 90, copy 85, previews 60, model 54,
  sheet 24), the edits to the roots, stores and copy net +54, and `LibraryStore+Sources` −45.
- Domain: 104 added, 15 removed (the draft 64).
- Persistence: net +19.
- Fakes and stub: net +28.
- LedgerDesign: net +20.
- FeatureWorkout and LedgerAppKit: net +24.

### PR-sweep seconds (R6)

These are the sums of the per-argument durations in the gate's `PR-iOS.xcresult`, under the PR sweep:

| Suite | Cases | Seconds |
|---|--:|--:|
| ReceiptLayout row action | 1 | 0.40 |
| Exercise sheet snapshots | 3 (7 references) | 0.33 |
| Exercise sheet accessibility | 6 | 0.22 |
| Exercise sheet layout | 2 | 0.07 |
| CreateExerciseStore | 9 | 0.04 |
| Receipt rows | 3 | 0.04 |
| CreateExercisePresentation | 5 | 0.01 |
| ExerciseHistoryStore · Edit | 3 | 0.01 |
| **Added** | | **≈ 1.1 s** |

The domain suites run on the host. This is far under the plan's 25–35 s.

### Runs

- Host `swift test`: the touched suites of LedgerDomain, LedgerPersistence (contract, GRDB, in memory,
  `HistoryModel`), FeatureLibrary (120 tests), FeatureWorkout, LedgerAppKit and LedgerDependencies all pass.
- Simulator, PR plan, `TEST_RUNNER_LEDGER_SWEEP=pr`:
  - first run, recording missing references: the 7 references were recorded, and F10's
    `receipt_nothingLeavesOrOverlaps` failed (fixed by its sanctioned edit);
  - compare run over `FeatureLibraryTests`, `FeatureWorkoutTests`, `LedgerDesignTests`, `LedgerAppKitTests` and
    `LedgerDependenciesTests`: **exit 0. 1,566 tests: 1,549 passed, 0 failed, 4 skipped, 13 expected failures.**
- Simulator, Nightly plan: UI `LibraryCreate` (2 tests) and `Library` (1 test): exit 0, 3 passed.
- **Not done:** listening to VoiceOver on the simulator (the S2 DoD item is still open), and `TabsAdversarial` and
  the audit suites on the Nightly plan.

### The gate

`scripts/check.sh` through the lock on `4ab36d3`: **exit 0, "check.sh OK", 1,977 s.**
- Steps: lint 81 s, iOS build 15 s, string catalogs 1 s (FeatureLibrary: 89 keys), iOS tests 1,554 s, watchOS
  build 48 s, watchOS tests 275 s, coverage 2 s.
- Coverage overall 98.45 %, FeatureLibrary 96.08 % (98.94 % after S1; the threshold is 70 %), LedgerDomain
  99.42 %.
- The FeatureLibrary drop is the sheet's presentation code in `LibraryRoot`, `ExerciseHistoryRoot`, the toolbar
  and `CreateExerciseSheet`'s task. Hosted package tests don't present these; the nightly UI test does.
- I did not measure per-file coverage. Every branch of `CustomExerciseDraft` has a test.
- The only commit after `4ab36d3` is these notes.

### Open questions, each with a recommendation

1. **The name field cuts a long name at accessibility sizes while it has no focus** (see References).
   *Recommendation:* a follow-up that moves F11's `NameField` technique (whole text under the field) into
   LedgerDesign for both features. Building it here would change F11's references and widen the slice.
2. **N19's reading** (decision 1). *Recommendation:* keep the counted-sets rule. "+Δ" then compares the same
   sets the records and the bests do.
3. **N20's failure recovery** (decision 2): a failed stats read is now left at the next run, not at the next
   change. *Recommendation:* accept. It is the history's own behaviour since F12-S2-3.

### S3 fix round 1 (G1, 2026-10-26): G2's S3-1 to S3-7, as the orchestrator ruled

**Commit:** `ff30d8c` fix(library). The ruling is the orchestrator's message; G2's findings are in `test-findings.md`
under "S3 — G2 findings".

**S3-1, S3-2, S3-3 (the name).** Changes in `LedgerDomain/Exercises/CustomExerciseDraft+Name.swift` (new) and the
draft:
- **Blank.** A name is blank (`blankName`, "Enter a name.") when nothing is left once its default-ignorable code
  points, blanks and line breaks are removed.
- **The stored name, `storedName`.**
  - Every default-ignorable scalar that stands alone is dropped, at the ends and inside the name: a zero-width
    space, a word joiner, a byte order mark, direction marks, a Hangul filler.
  - Kept are a ZWJ, any grapheme extender (variation selectors) and direction controls, which the next step
    refuses.
  - Every `Zs` becomes U+0020, a run of spaces collapses to one, and the result is trimmed.
  - The length rule, the duplicate check (`ExerciseSearch.key` of the stored name) and the stored name and short
    name all use it.
  - `ExerciseSearch.key` is unchanged, as ruled.
- **Refused (`controlCharacter`):** `Cc`; `Zl` and `Zp` inside the name (at the ends they are trimmed as line
  breaks); direction embeddings, overrides and isolates (U+202A–U+202E, U+2066–U+2069), so U+202E is refused under
  S3-1; and any other `Cf` that is not default-ignorable (U+0600, for example).
- **How I resolved the ruling:**
  - *Bidi controls.* "Refuse, or trim at the ends" and "drop interior default-ignorables" overlap on them. I refuse
    them wherever they stand, which G2's `directionOverride_isDuplicate` (refused) needs. A name of them alone is
    still blank (G2's `invisibleOnly_isBlank`).
  - *ZWJ and variation selectors.* These are default-ignorable but are kept, because dropping them would split
    emoji sequences: G2's grapheme pin counts the family emoji as one character.

**S3-4.** Besides 2–40 graphemes, a name of more than 160 scalars is refused with `nameLength`. The comment on
`nameScalars` explains why. G2's pin `combiningMarks_areUnbounded` held the old behaviour; it is now
`combiningMarks_overTheScalarCap_areRefused` (2,002 scalars refused; exactly 160 kept). This is a sanctioned edit,
since the ruling changes the behaviour.

**S3-5.** `CustomExerciseDraft.init(_ exercise:)` subtracts the primary muscle from the secondaries.

**S3-6.**
- `CreateExerciseSheet` takes `announce` (default `AccessibilityNotification.Announcement`), as `ProgramRoot` does.
- The store counts the problems Save finds (`problemNumber`, in the model), so each one is announced, including the
  same line twice.
- When the problem is the name's, the screen scrolls to the top (`ScrollPosition`), where the name field stands.
- G2's source check is replaced, as ruled, by a hosted behavioural test (iOS). It announces "Enter a name." twice,
  then "Couldn't save the exercise. Try again.".
- The scroll has no automated test.

**S3-7.** `CreateExerciseModel.Chip.id` is the value's raw value ("shoulders"), not its place.

**Tests.**
- Every `withKnownIssue` in G2's two files is gone, and each test passes as a plain test with its assertions as
  written. The one exception is S3-4's pin, above.
- My `CustomExerciseDraftTests` gain 3 tests: the stored name, invisible names and separators, and S3-5.
- The property test's oracle follows the new rule, written as a plain reading of it. It collapses spaces by scalar,
  because a space under a combining mark is still a space. Its scalar pieces now include format characters,
  separators, thin and ideographic spaces, a Hangul filler and U+0600. It passes at 200 seeds and at 2,000.
- No reference changed.

**New wording:** none. "Enter a name." and "That name holds a character that can't be saved." cover the new cases.

**Product lines** (same rules as before): this round adds 83 and removes 15, net +68. Against `235e845` the slice
is now **922 added, 152 removed, net 770**.

**Runs.**
- Host: `LedgerDomainTests` draft and history suites (51 tests) and `FeatureLibraryTests` (125 tests) pass.
- Simulator, PR plan, PR sweep: `FeatureLibraryTests` and `LedgerDomainTests`, 1,529 tests: 0 failed, 6 skipped.

**The gate.** `scripts/check.sh` through the lock on `ff30d8c` exited 0 with "check.sh OK" in 1,934 s.
- Lint 73 s, iOS build 13 s, string catalogs 1 s, iOS tests 1,537 s, watchOS build 40 s, watchOS tests 267 s,
  coverage 2 s.
- Coverage overall 98.53 %, FeatureLibrary 96.98 %, LedgerDomain 99.42 %.
- The only commit after `ff30d8c` is these notes.
