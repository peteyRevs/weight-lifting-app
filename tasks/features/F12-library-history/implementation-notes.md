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
