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
