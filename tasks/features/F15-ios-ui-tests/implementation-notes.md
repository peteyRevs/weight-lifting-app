# F15 — implementation notes

## S1 — as built (G1 implementer, 2026-11-12)

Branch `feat/F15-s1`, cut from `main` at `c92e963` plus the plan (`e15b74d`) and its rulings (`166e376`). The
specification is the brief's "Plan amendments" (C1–C14, slice S1, Q1–Q12 at the planner's defaults) and "Rulings on
the F15 plan".

### What landed

- **`-LEDGER_UITEST_HISTORY <1–16>`** (`LedgerAppKit/UITestHistory.swift`, Debug only). Beside `-LEDGER_UITEST` and
  `-LEDGER_UITEST_PROGRAM seed` it stores `Fixtures.history(weeks:)` (through `SampleProgram.history(weeks:)`, since
  LedgerAppKit links no LedgerFakes) right after the seed program, in `saveUITestProgramIfAsked()`: once in a process,
  and only over a database that holds no workout. A value that is no whole number from 1 to 16, or the argument
  without the seed program, stops the launch. A failure is logged and the launch goes on.
- **One write (G2-1).** The history is stored by `GRDBWorkoutRepository.materialize(_ workouts:)`, a new method of the
  concrete repository (not of the protocol) that saves several workouts as one save each would, in one transaction.
  A pass that is cancelled or fails therefore leaves none of them, and the next pass, over an empty database, stores
  them whole. The single save is the same code, moved into a static body both call.
- **`Apps/LedgerUITests/Support/Steps.swift`**: F15's steps, used by F15's tests only (Q7).
- **`Smoke.test_onboardToFirstSet`** (criterion 2) and **`Flows`** (criteria 3–5, nightly): `test_fullWorkoutToHistory`,
  `test_programEditReflectsOnToday`, `test_unitsSwitch_convertsAFinishedSet`.
- **No test-plan, shard or project change.** `PR` selects `LedgerUITests/Smoke`; `Flows` runs in nightly leg 4, which
  holds `LedgerUITests` whole; `Apps/LedgerUITests` is a synchronized folder.
- `docs/testing-strategy.md` §2.7 gains the argument; its flow list (still naming `Smoke.freshInstall_skipsSetupToToday`)
  is S2's to rewrite.

### Sanctioned edits

- `Smoke.test_freshInstall_skipsSetupToToday` is replaced by `test_onboardToFirstSet` (Q3), which keeps its onboarding
  checks.
- `Settings.swift` is unchanged: its kilogram check stays, and `Flows+Units` adds the finished row.

### Decisions (autopilot)

1. **The units number is "83.9", not "83.91".** The Domain prints a converted weight to hundredths only when that is a
   whole number of quarter kilograms, otherwise to one decimal (`Weight.shownValue(in:)`): 185 lb reads 83.9, 225 lb
   102.1. The test computes the expected text from the pounds the row reads, by that rule. No product change.
2. **The history is saved inside the program's launch step**, not a second `saveUITestHistoryIfAsked()`: it needs the
   seed program, shares its once-flag and cancellation handling, and kept `AppComposition.swift` under 300 lines.
3. **The fixture is reached through `SampleProgram.history(weeks:)`** (FeatureWorkout, Debug only), not by linking
   LedgerFakes to LedgerAppKit (a `Package.swift` change).
4. **Smoke's clock is Monday 2026-09-14 noon UTC (`Flows.monday`)**: on a real rest day there is no "Start workout".
5. **The full flow onboards with Continue, Continue, "Start training"**; Smoke keeps "Skip setup".
6. **The full flow** reaches exercise 2 from REMAINING and swaps it before any set; it skips each rest before the next
   jump, so no tap lands under the panel; "a point for this week" is the chart element drawn and its empty text absent.
7. **The program edit** finds Today's rows by their label's prefix; Barbell Row is added as Lower A's row "4" (its rows
   are 1, 2, 3A, 3B) and the first exercise is removed with the slot's "Remove". No identifier was added (A4).
8. §2.7's old Smoke name is left for S2.
9. The nightly run below was let finish past the 60-minute check, which it projected and did not reach.
10. **G2-1 fixed with one write rather than the guard.** The concrete repository could take several workouts in one
    transaction with a small refactor; the guard ("every stored workout is a fixture's, store the missing") would have
    brought back a seeded workout a test deleted, and left part of a history after a failure.

### Times (local Mac, iPhone 17, iOS 27.0)

- `Smoke.test_onboardToFirstSet`: 20.0–20.1 s across three runs, against the 90 s budget (one launch replaced one).
- Flows, fix round 1: full 81.5 s, program 43.6 s, units 28.9 s (with the chart check). First round: 74.2, 43.8, 22.4 s.

**Local nightly run of `LedgerUITests` alone** (Nightly plan, before fix round 1): 95 tests, 93 passed, 2,514 s with
the build. The two failures are known, outside S1, and recorded earlier: `TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` (the Program tab's audit findings; F08 test-findings) and `TabsAdversarial.test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark` (F10 notes). `WorkoutLogging.test_sampleWorkout_stepsLogsUndoesAddsAndJumps` (R1) passed. G2's re-runs are G2's to add.

| Test | Result | Seconds |
|---|---|--:|
| Builder.test_addDayAddExerciseChangeProgression | passed | 30.324 |
| Builder.test_atAnAccessibilitySize_readsItsStopsInOrder | passed | 39.875 |
| Builder.test_blockLength_fingerOnMinusAndPlus | passed | 21.405 |
| Builder.test_name_typedLetterByLetter_isReadBack | passed | 29.531 |
| Builder.test_wrappedName_takesTheFocus_andABlankDraftShowsThePlaceholder | passed | 25.366 |
| DayEditor.test_atAnAccessibilitySize_readsItsStopsInOrder | passed | 41.453 |
| DayEditor.test_backAndSwipeBack_andTheNextDayIsItsOwn | passed | 32.306 |
| DayEditor.test_deleteAlert_cancelThenDelete | passed | 25.876 |
| DayEditor.test_fingerOnARowAStepperAChipAndTheSwitch | passed | 35.093 |
| DayEditor.test_library_queryChipThreePicks | passed | 32.956 |
| DayEditor.test_swipeBack_control_popsAScreenWithTheSystemBar | passed | 18.533 |
| DebugMenu.test_diagnostics_showsTheSeededCatalog | passed | 11.846 |
| Flows.test_fullWorkoutToHistory | passed | 74.299 |
| Flows.test_programEditReflectsOnToday | passed | 43.549 |
| Flows.test_unitsSwitch_convertsAFinishedSet | passed | 22.229 |
| HistoryVoiceOverAdversarial.test_history_accessibilityXXXL_readsTheWeeksAsAList | passed | 23.140 |
| HistoryVoiceOverAdversarial.test_history_defaultSize_readsHeadingStatsChartAndLog | passed | 22.769 |
| HistoryVoiceOverAdversarial.test_history_sessionTap_pushesTheWorkoutOnTheLibrary | passed | 27.258 |
| LaunchPerformance.test_launchToFirstFrame | passed | 36.916 |
| Library.test_queryChipsRow_opensTheHistory_andBackKeepsTheFilter | passed | 16.424 |
| LibraryAuditAdversarial.test_lastRow_scrollsClearOfTheTabBar | passed | 65.091 |
| LibraryAuditAdversarial.test_libraryRoot_passesTheAudit_butForItsMeasuredFalsePositives | passed | 71.090 |
| LibraryAuditAdversarial.test_placeholderGuards_failOnAClippedAndOnATruncatedPicture | passed | 11.911 |
| LibraryAuditAdversarial.test_searchPlaceholder_isDrawnWholeInsideTheField | passed | 33.840 |
| LibraryCreate.test_newExercise_isListedAndPicked_andEditRenamesIt | passed | 50.293 |
| LibraryCreate.test_receiptRow_opensTheExercisesHistoryOnToday | passed | 19.989 |
| Onboarding.test_eachStepOpensAtItsTop_atAnAccessibilitySize | passed | 9.619 |
| Onboarding.test_threeStepsGenerateProgram | passed | 18.089 |
| Onboarding.test_voiceOverReadsEachStepInOrder_insideTheScrollView_atAnAccessibilitySize | passed | 8.916 |
| OnboardingAdversarial.test_aStepScrolledDown_isFollowedByAStepAtItsTop_atTheLargestTextSize | passed | 18.387 |
| OnboardingAdversarial.test_auditExclusions_excuseNothingWider | passed | 0.044 |
| OnboardingAdversarial.test_eachStep_passesTheSystemsAccessibilityAudit | passed | 33.210 |
| OnboardingAdversarial.test_eachStep_passesTheSystemsAccessibilityAudit_atTheLargestTextSize | passed | 33.950 |
| OnboardingAdversarial.test_eachStep_readsInTheTablesOrder_insideTheRealScrollView_atTheLargestTextSize | passed | 7.540 |
| OnboardingAdversarial.test_freshInstall_opensOnStepOne_fullScreen_andNothingOfTodayIsSeenFirst | passed | 4.766 |
| OnboardingAdversarial.test_leavingTheAppMidOnboarding_keepsTheStepAndThePicks | passed | 14.374 |
| OnboardingAdversarial.test_picksSurviveBackAndForth_andStartTrainingSavesThem_landingOnToday | passed | 20.794 |
| OnboardingAdversarial.test_skipSetup_fromEachStep_savesTheDefaultProgram_andLandsOnToday | passed | 40.127 |
| ProgramTabAdversarial.test_contentSwipe_onAFreshDayEditor_pops | passed | 26.428 |
| ProgramTabAdversarial.test_edgeSwipe_onAFreshDayEditor_pops | passed | 26.470 |
| ProgramTabAdversarial.test_editThisWeek_thenAnotherWeek_isKeptAfterTheDayEditorAndATabSwitch | passed | 27.861 |
| Settings.test_kilograms_chosenInSettings_reachToday | passed | 17.006 |
| SettingsDeleteAll.test_deleteAllData_confirmedTwice_showsOnboarding | passed | 18.306 |
| SettingsDeleteAllVoiceOver.test_rowWarningAndSheet_readInOrder | passed | 25.733 |
| SettingsDeleteAllVoiceOver.test_rowWhileAWorkoutIsInProgress_isDimmedAndSaysWhy | passed | 16.122 |
| SettingsExport.test_export_presentsTheShareSheet | passed | 13.763 |
| Smoke.test_onboardToFirstSet | passed | 19.896 |
| Smoke.test_sampleWorkout_anotherDay_cancelResumeAndReplace | passed | 33.245 |
| Smoke.test_sampleWorkout_logASet_saveWorkout_todayShowsItLogged | passed | 23.545 |
| Smoke.test_sampleWorkout_startsCountsMinimizesResumesDiscards | passed | 23.474 |
| Tabs.test_eachTab_showsItsOwnScreen_andTodayKeepsItsTitle | passed | 21.210 |
| Tabs.test_fourTabs_todaySelected_inTheBarsOrder | passed | 6.090 |
| TabsAdversarial.test_debugMenu_opensFromTodaysTitleAfterATourOfTheTabs_andFromNoOtherTitle | passed | 32.928 |
| TabsAdversarial.test_deviceTurned_theAppStaysUpright | passed | 5.780 |
| TabsAdversarial.test_eachTab_showsThePlaceholderThatNamesIt_andIsTheOnlyOneSelected | passed | 38.024 |
| TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit | failed | 35.967 |
| TabsAdversarial.test_largestTextSize_everyTitleIsWholeAndOnScreen | passed | 21.164 |
| TabsAdversarial.test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark | failed | 29.801 |
| TabsAdversarial.test_tabBar_holdsTheFourTabsInOrder_todaySelected | passed | 5.943 |
| Today.test_restDay_offScheduleSheet_cancelsAndPicksADay | passed | 33.144 |
| Today.test_sessionDay_atAnAccessibilitySize_readsInOrderAndStarts | passed | 17.169 |
| Today.test_sessionDay_startWorkoutOpensTheCover | passed | 29.936 |
| TodayAuditAdversarial.test_restDay_andItsSheet_passTheAudit | passed | 20.421 |
| TodayAuditAdversarial.test_sessionDay_dark_passesTheAudit | passed | 22.904 |
| TodayAuditAdversarial.test_sessionDay_theLastLineScrollsClearOfTheTabBar | passed | 44.633 |
| TodayAuditAdversarial.test_sessionDay_upNextThenResume_passTheAudit | passed | 26.879 |
| WorkoutAdversarial.test_finishDialog_treeAndTheWaysOutOfIt | passed | 30.600 |
| WorkoutConflictAdversarial.test_conflict_itsTree_bothWaysOut_andOneWorkoutAfterReplacing | passed | 57.162 |
| WorkoutFinishAdversarial.test_rightToLeft_theSheetIsMirrored | passed | 20.066 |
| WorkoutFinishAdversarial.test_sheet_accessibilityExtraLarge_buttonsCanBeReached | passed | 20.122 |
| WorkoutFinishAdversarial.test_sheet_accessibilityLargest_buttonsCanBeReached | passed | 20.067 |
| WorkoutFinishAdversarial.test_sheet_accessibilityMedium_buttonsCanBeReached | passed | 20.012 |
| WorkoutFinishAdversarial.test_sheet_defaultSize_bothButtonsShowAtHalfHeight | passed | 19.921 |
| WorkoutFinishAdversarial.test_sheet_extraExtraExtraLarge_buttonsCanBeReached | passed | 20.241 |
| WorkoutFinishAdversarial.test_swipeDown_keepsTheWorkout_thenTwoQuickTapsSaveOnce | passed | 25.005 |
| WorkoutHistory.test_coveredDetail_deletedElsewhere_popsOnReturn | passed | 38.024 |
| WorkoutHistory.test_deleteFromHistory_emptiesTheList | passed | 26.542 |
| WorkoutHistory.test_deleteFromToday_leavesNoRecentRow | passed | 25.918 |
| WorkoutHistory.test_editASet_showsInTheDetailAndTheList | passed | 33.483 |
| WorkoutHistory.test_editCancelAndSwipe_discardTheStep | passed | 33.364 |
| WorkoutHistory.test_savedWorkout_isListed_andOpensItsDetail | passed | 32.533 |
| WorkoutLogging.test_sampleWorkout_atAnAccessibilitySize_readsItsStopsInOrder | passed | 20.786 |
| WorkoutLogging.test_sampleWorkout_stepsLogsUndoesAddsAndJumps | passed | 51.099 |
| WorkoutLoggingAdversarial.test_doubleTapOnACheck_logsTheSetOnce | passed | 15.404 |
| WorkoutLoggingAdversarial.test_jumpFromRemaining_showsTheNewExercisesName | passed | 15.650 |
| WorkoutLoggingAdversarial.test_secondTouchOnTheSameCheck_doesNotLoseTheSet | passed | 16.897 |
| WorkoutRest.test_rest_atAnAccessibilitySize_thePageScrollsClearOfThePanel | passed | 24.265 |
| WorkoutRest.test_rest_countsDown_extends_skips_andComesBack | passed | 21.311 |
| WorkoutRestAdversarial.test_rest_atTheLargestTextSize_leavesSomeOfThePage | passed | 17.017 |
| WorkoutRestAdversarial.test_rest_twoQuickExtends_minimized_backgrounded_skipped | passed | 37.806 |
| WorkoutSaveFailure.test_close_thenTheSheetOffersNoDiscard_andSaveSaves | passed | 23.574 |
| WorkoutSaveFailure.test_tryAgain_eachFailureShowsTheAlertAgain_thenSaves | passed | 25.508 |
| WorkoutSaveFailureAdversarial.test_failuresAcrossACoverOpenedAgain_eachShowsTheAlert | passed | 31.733 |
| WorkoutSuperset.test_superset_loggedRoundByRound | passed | 20.248 |
| WorkoutSwap.test_swapTheFirstExercise_logFinish_receiptListsTheReplacement | passed | 21.449 |

## S2a — as built (G1 implementer, 2026-11-13)

Branch `feat/F15-s2`, cut from `main` at `a10a2c2` (S1 merged). The orchestrator took the plan's split up front: S2a is
the audit runner, the audits of every screen C7 lists as not audited, the measured exclusions, the "excuses nothing
wider" tests and the fixes; `DynamicType.swift`, `docs/accessibility-labels.md` and its test, the §2.7 rewrite and the
M1-exit run are S2b's.

### What landed

- **`Apps/LedgerUITests/Support/Audit.swift`**: `AuditWay` (light, dark, light at Accessibility XXXL; question 6, A),
  `ScreenIssue`, `ScreenExclusion` and `ScreenAudit`, the one runner. `threeWays(launching:walk:)` launches once per
  way and runs the walk; the walk calls `audit(_:screen:pinned:)` on each screen, which runs
  `performAccessibilityAudit(for: .all)`, keeps each issue with the element's type, identifier, label and frame (and the
  tab bar's and a pinned part's frames), and attaches the screen and each reported element. The verdict attaches every
  issue with its verdict and fails on any no exclusion excuses. `expectScrollsClear` (from review round 1) is the "scrolls clear"
  proof each "under the tab bar" exclusion needs. **Open findings** (`open:`): a real finding not fixed in S2a is a
  strict `XCTExpectFailure` on exactly what it names, so the test stays green, catches everything else, and goes red
  the day the finding is fixed.
- **`Support/Audit+Kinds.swift`**: the five kinds of measured false positive (F15-S2-3 to 7), each F08's, F09's or
  F12's precedent; each screen names the screens and elements it excuses.
- **`AuditWorkout.swift`** (the solo card, swap sheet, rest panel, superset block, finish sheet, receipt; through the
  Debug menu's sample), **`AuditProgramLibrary.swift`** (Day editor, its picker; with `-LEDGER_UITEST_HISTORY 4`, the
  bench press's history, New exercise, Edit exercise), **`AuditHistorySettings.swift`** (with history: the newest
  workout's detail and its edit-sets sheet; Settings and Bar and plates). Nightly only (leg 4 holds `LedgerUITests`
  whole); `PR.xctestplan` is unchanged.
- **`AuditExclusionsTests.swift`**: no launch; per screen family, the excused issues as measured and their near misses,
  and the open findings naming only their issue.
- `Support/Steps.swift`: `startSampleWorkout()`, and `scrollUntilHittable(_:back:)` can swipe down.
- **Dark.** On the iOS 27.0 simulator `XCUIDevice.appearance` (and `simctl ui appearance`) does not reach a launched
  app: round 1's "dark" pictures were the light ones, pixel for pixel. The dark way launches with
  `-LEDGER_UITEST_APPEARANCE dark`, the Debug seam of the tabs fix (`fix/tabs-audit`), which merges before this PR; until
  it is merged here the dark way draws light. **The dark passes are to be run after that merge** (with the shared
  "really dark" guard of `Support/Appearance.swift` called in `threeWays`).

### Findings (F15-S2-n)

| ID | Screen(s) | Issue as the audit says it | Measured | Verdict |
|---|---|---|---|---|
| F15-S2-1 | superset block | Contrast failed, the legend letter "B" | (193, 193, 191) on (255, 255, 255): 1.80:1; `inkFaint` | **Fixed**: `inkMuted` on that element (≥ 4.5:1 on the surface, `MutedTextContrastAdversarialTests`); no token changed |
| F15-S2-2 | cover header | Hit area is too small, "Elapsed time" (other, 42 × 15) | an element of no kind, no action | **Fixed**: the static-text trait; the audit no longer reports it |
| F15-S2-3 | every family | Dynamic Type partially unsupported, the eyebrows | 10 pt at the default size, 37 pt tall at XXXL | Excluded by label (F09-S5-2) |
| F15-S2-4 | every family | Text clipped, texts in the caption, eyebrow, button, heading and title roles; the Day name and Edit exercise name fields at the default size | every glyph whole in the element's picture | Excluded by label or identifier (F09-S5-3/4) |
| F15-S2-5 | Day editor (XXXL), exercise history, workout detail, Settings | Contrast failed under the tab bar | inside the bar's frame; each page scrolls clear (proved in the walk) | Excluded by frame, never a tab |
| F15-S2-6 | rest panel, exercise picker, edit sets | Contrast failed on a line under a pinned part | hidden in the pictures; the panel starts 17 pt over `workout.rest.status`, a sheet's rule 11 pt over its button (margin 24) | Excluded by frame; the rest page scrolls clear (`WorkoutRest`), and every sheet with a pinned foot scrolls clear of it in every way (`expectScrollsClear`: the picker and edit sets from S2a's review round 1; New exercise, Bar and plates and Delete all data from S2b) |
| F15-S2-7 | rest panel, finish sheet, New/Edit exercise | Contrast nearly passed, "Skip rest", "Save workout", "Save" | white on the accent, 3.10:1 (16 pt bold) | Excluded by label (F09-S5-1) |
| F15-S2-8 | workout detail | Contrast failed and Dynamic Type partially unsupported, the system's bar button "Edit" | (0, 0, 0) on the glass's (253, 253, 249), 20.5:1 | Excluded by identifier |
| F15-S2-9 | receipt | Hit area is too small, the date (12 pt) | no control; VoiceOver's escape is set on the receipt's stack and so on each element (`ReceiptTests.escape_isDone`) | Excluded |
| F15-S2-10 | cover header, XXXL | Text clipped, "Minimize" | drawn "Minimi / ze"; "Finish" is drawn "Finis / h" (not reported) | **Fixed in S2b**: `HeaderRowLayout`, one row while it fits, else the time over the two buttons, never a broken word (layout: for Pete); pinned by `WorkoutHeaderLayoutTests` at Accessibility 3 and 5 |
| F15-S2-11 | Edit exercise, XXXL | Text clipped, the name field | "Landmine Squ…" (whole at the default size) | **Fixed in S2b**: the name drawn as wrapping text under the field (`NameField`'s pattern, ported); `CreateExerciseLayoutTests.name_longerThanItsLine_isDrawnWhole`. The field's own hidden line is still reported, and excused as F15-S2-4 (measured whole) |
| F15-S2-12 | Settings, default size | Potentially inaccessible text, twice, no element, no frame | still there scrolled to the end (not the bar); absent at XXXL. **Hypothesis refuted**: with SegmentedChoice's options labelled by their drawn "LB"/"KG" (an uncommitted experiment, reverted) both issues remain | **Fixed in S2b**: bisected to the "Week starts on" row's title and line, drawn beside its menu and hidden from VoiceOver; now drawn inside the menu's button |

Round 1 reported 151 issues on 13 screens with nothing excluded; the last run, 0 unexcused.

### Fixes, hosted tests, references

- `SupersetLegendRow.letterInk(isCurrent:)` (FeatureWorkout), pinned by
  `SupersetBlockTests.letterInk_isReadableOnBothFills`.
- `WorkoutHeader`'s elapsed time `.isStaticText`, pinned by `WorkoutAccessibilityTrees.header` (sanctioned edit:
  `Stop("Elapsed time", [])` becomes `.staticText`).
- The legend letter's change lies inside the references' tolerance: the 723 tests of `FeatureWorkoutTests` pass with
  no reference re-recorded (`cover_supersetRound2*` and the drop set's, which draw the block), so none was.

### Decisions (autopilot, and the orchestrator's rulings during the slice)

1. The split was taken up front (orchestrator). The audits are grouped by path: one launch per way walks several
   screens (six tests, not thirteen), each screen still audited three ways and named in every issue.
2. Own appearance mechanism dropped for the tabs fix's `-LEDGER_UITEST_APPEARANCE` (orchestrator).
3. Real findings that need a layout change (F15-S2-10, 11) and the unexplained one (F15-S2-12) are open findings,
   strict expected failures matched as narrowly as the exclusions (orchestrator, B); all three go to one follow-up PR.
   F15-S2-12 matches only exactly two element-less issues per way on Settings at the default size.
4. The fixes are per element, never a token: `inkFaint` keeps its value and its other uses.
5. The Settings walk reaches Bar and plates before the "scrolls clear" proof: from the page's end a swipe back did
   not bring the row within reach at XXXL. The page is audited at rest only; an audit of it scrolled to its end
   (an experiment) reports the rows under the navigation bar's glass, which no exclusion covers.
6. No shard change: leg 4's estimate stays under `nightly-shards.txt`'s ~6,300 s rebalance mark (below).

### Times (local Mac, iPhone 17, iOS 27.0; the dark way drew light, see above)

| Test | Seconds |
|---|--:|
| AuditWorkout.test_cardSwapSheetAndRestPanel_passTheAudit | 114.2 |
| AuditWorkout.test_supersetFinishSheetAndReceipt_passTheAudit | 104.9 |
| AuditProgramLibrary.test_dayEditorAndItsPicker_passTheAudit | 117.2 |
| AuditProgramLibrary.test_historyNewAndEditExercise_passTheAudit | 247.5 |
| AuditHistorySettings.test_workoutDetailAndEditSets_passTheAudit | 99.7 |
| AuditHistorySettings.test_settingsAndBarAndPlates_passTheAudit | 91.6 |
| AuditExclusionsTests (5 tests) | 0.04 each |

775 s on the Mac, about 1,160 s on the runner (× 1.5). Leg 4 (`nightly-shards.txt`: `LedgerUITests` 1,840, the
package targets 775, S1's `Flows` about 210) becomes about 3,990 s of tests, short of the ~6,300 s rebalance mark and ~3,800 s short
of the 7,800 s deadline with a 1,500 s build: no rebalance.

Other runs: `FeatureWorkoutTests` whole (PR plan): 723 tests passed, 3 known issues, 620 s. `check.sh --lint-only`:
green.

### Review round 1 (G3: request changes), phase 1: light and Accessibility XXXL

Phase 2 (after `main`'s appearance seam is merged here) runs the dark passes and re-measures every contrast excuse
in dark; until then every "light and dark" above means light only (the dark way drew light).

- **B1, pinned parts.** `PinnedPart` names a part's top element, its measured margin (17 pt over
  `workout.rest.status`, 11 pt over a sheet's button; the old blanket 24 pt is gone) and its own elements. Each issue
  records whether its element is one of the part's (`inPinnedPart`, by identifier, else label), and F15-S2-6 never
  excuses those: "Skip rest", the rest status, the picker's and the edit sheet's buttons.
- **B2/B3, scrolls clear.** `expectScrollsClear(_:screen:anchor:last:above:)` replaces the tab-bar-only proof: the
  page is the scroll view holding `anchor` (never a page behind a push or a sheet), dragged near its leading edge
  from above the bar or foot until two drags leave its picture unchanged; its lowest labelled text or button must be
  the one named (`last`, or its start) and stand above the bar's top or the foot's. Proved on: Day editor ("Delete
  day"), exercise history ("Aug 24"), workout detail ("Delete workout"), Settings ("Ledger …", the version line),
  edit sets ("16", the last set's reps), and the picker's "Press" list ("Smith Machine Overhead Press").
- The picker's proof at Accessibility XXXL first failed with its last row below the screen: the drags started on the
  sheet's foot, which moves nothing. They now start above the bar or foot, and it passes; no finding.
- **B4, per screen.** F15-S2-3 and 4 are keyed by screen, as measured (`[screen: labels]`). "Day name" is measured
  whole at both sizes in the screen's pictures (at XXXL the field's own frame cuts the drawn name's second line).
- **S1.** `letterInk`'s doc and test no longer claim the current row: its accent on the dark `ink` fill (#F4F2ED) is
  about 2.8:1, for phase 2 to measure and fix (token or element). The test is
  `letterInk_offTheCurrentRow_isInkMuted`.
- **S2.** F15-S2-5 takes texts and buttons only, whose middle lies inside the bar; a button wholly inside the bar is
  the bar's own, whatever its label.
- **S3, F15-S2-9 kept.** With `ReceiptScreen` containing its elements under the escape action
  (`.accessibilityElement(children: .contain)`) the audit stopped reporting the date's hit area, but
  `ReceiptTests.escape_isDone` failed: the first element no longer performs the escape. Reverted; the exclusion
  stays, now by the frozen clock's label. Why the date alone: SwiftUI hands the stack's escape to each element,
  which the audit counts as a control, and of the pinned header's three only the date (12 pt) is under the size;
  the name is 29 pt, "Done" 44 pt. In the contained run the date's "Text clipped" (caption role) was reported too,
  and it is excused by label on the receipt (F15-S2-4).
- **S4.** The "Audit issues" report is attached in a teardown block, also when a walk stops midway; each line gives
  the issue's type and its verdict (excused, open, or not excused).
- **S6.** F15-S2-12's hypothesis is recorded as refuted; its issue type is `.elementDetection` (2), which the open
  finding now also matches.
- **Nits.** `AuditWorkout` freezes the clock (Wednesday 2026-09-16); the Library's search is found by its label's
  start and the history's back by "BackButton". "Finish" is reported "Text clipped" from this round on: at the default
  size with "Minimize" (whole, F15-S2-4), and at XXXL with it in F15-S2-10 (open).
- **Settling.** Each audit now waits (at most ten pictures, no sleep) until two pictures of the screen in a row are
  the same, so a selection or sheet still moving is not measured half-way.
- **The simulator turned dark mid-round.** From about 13:25 on 2026-11-14 the shared simulator's own appearance was
  dark (another lane's work), and without the seam every way drew dark. That run reported three issues the light
  runs never did, all dark: "Contrast failed" on the current legend row's accent "A" on the dark `ink` fill (S1's
  2.8:1), on the Day editor's name field, and an element-less "Contrast nearly passed" on the rest panel. They are
  phase 2's to measure and fix. The last all-light run of every audit (12:49 build) passed but for the picker proof's
  then-expected failure, since removed.
- `AuditWorkout`'s frozen clock leaves the header's elapsed time counting from the frozen start to the wall clock
  ("1424:17:08" on 2026-11-14): the test mode moves the app's clock, not the timeline's. The header's issues are the
  same as with the real clock; noted for the follow-up PR's header layout.

## Follow-up from fix/tabs-audit (2026-11-13)

- `LedgerKit/Sources/LedgerAppKit/AppComposition.swift` is at 300 lines, the lint's warning limit, after
  `Environment.colorScheme` (`-LEDGER_UITEST_APPEARANCE`). The next addition moves `Environment.live(arguments:)`
  out to a file of its own (e.g. `AppComposition+Environment.swift`) first.
- A UI test in light or dark launches with `LaunchAppearance` and checks it with `assertDrawn(in:_:)`
  (`Apps/LedgerUITests/Support/Appearance.swift`); the iOS 27.0 simulator does not apply
  `XCUIDevice.shared.appearance`. `assertDrawn` reads the top of the screen, so it holds on paper-ground screens
  only: S2a's audits of dark-by-design screens (the workout cover) need another signal.

### Review round 1, phase 2: the appearance seam and dark (2026-11-14, after `main` e7cbbcc was merged)

- **The seam.** `AuditWay` takes its appearance from `LaunchAppearance` (`-LEDGER_UITEST_APPEARANCE light|dark`), and
  each launch calls `assertDrawn(in:)` on Today, before the walk: no pass depends on the shared simulator.
- **Dark findings, fixed or open:**
  - **F15-S2-14, fixed.** The current superset member's accent letter on its inverted `ink` fill: in dark the plain
    accent on #F4F2ED is 2.8:1 ("Contrast failed" on "A"). The letter now reads `accentText` in the other scheme:
    the plain accent on the near-black fill in light (unchanged), the deep accent #B2390E on #F4F2ED in dark. No
    token changed (`SupersetLegendRow.letterScheme`, pinned by `SupersetBlockTests.letterScheme_isInvertedOnTheCurrentRowOnly`).
  - **F15-S2-13, open.** "Contrast failed" on the Day editor's name field in dark only. `NameField` draws the field's
    own text clear while unfocused and the name as wrapping text under it; the audit reads the field's text colour,
    not its pixels (black on paper passes, black on #0B0B0D fails). The drawn name is 17:1. Changing how the field's
    text is hidden touches `NameField`'s measured layout and hosted tests, so it goes to the follow-up PR; a strict
    expected failure, dark, that field only.
  - **The rest panel's element-less near pass** is not a dark finding: from this phase on it comes in light and dark
    alike, one a way, while the labelled "Skip rest" near pass is gone from the same runs; the panel has no other
    accent control. It is F15-S2-7 with its element lost, excused once a way on the rest panel only
    (`skipRestUnnamed`, count-checked like F15-S2-12; exclusions now take a per-way count too).
- **Dark re-measured** (all excused in the last run): F15-S2-5 under the tab bar (Settings' "DATA", "Apple Health",
  "Not connected"; the detail's "Delete workout"; the history's last session) and each page scrolls clear in dark;
  F15-S2-6 under the edit sheet's foot and the rest panel; F15-S2-7, white on the accent, which is #FF5B22 in both
  schemes: 3.10:1; F15-S2-8, the bar's "Edit", its picture's ink 20.5:1; F15-S2-12: two element-less issues on
  Settings in dark too.
- **The frozen clock** is dropped from `AuditWorkout`: the header's elapsed time is `Text(timerInterval:)`, drawn by
  the system from the wall clock, so it cannot read the test mode's moved clock without a timeline of its own
  (more than this slice). The receipt's date is matched by its shape ("Saturday, November 14"), for its hit area
  (F15-S2-9) and its native line (F15-S2-4).
- **The last run** (Nightly plan, the audits and `AuditExclusionsTests` only): 12 tests passed; 222 issues reported
  (85 light, 86 dark, 51 at XXXL), 213 excused, 9 open (F15-S2-10 ×3, 11 ×1, 12 ×4, 13 ×1), none left.

| Test | Seconds |
|---|--:|
| AuditWorkout.test_cardSwapSheetAndRestPanel_passTheAudit | 135.4 |
| AuditWorkout.test_supersetFinishSheetAndReceipt_passTheAudit | 114.4 |
| AuditProgramLibrary.test_dayEditorAndItsPicker_passTheAudit | 268.9 |
| AuditProgramLibrary.test_historyNewAndEditExercise_passTheAudit | 272.6 |
| AuditHistorySettings.test_workoutDetailAndEditSets_passTheAudit | 279.8 |
| AuditHistorySettings.test_settingsAndBarAndPlates_passTheAudit | 104.1 |
| AuditExclusionsTests (6 tests) | under 0.1 each |

1,175 s on the Mac, about 1,760 s on the runner (× 1.5): the scroll proofs added about 400 s. Leg 4 becomes about
4,590 s of tests, under `nightly-shards.txt`'s ~6,300 s rebalance mark; the next rebalance could move an audit class to
leg 5.

### Review round 2 (G3: small changes)

- **SF1, the element-less "Skip rest".** The excuse now also needs the default size, a detail naming a
  `SwiftUI.AccessibilityNode` (as the labelled one's did), and no labelled "Skip rest" near pass on the same screen in
  the same way; near misses for XXXL, a labelled one beside it, and a frame. Which change lost the element, from the
  runs already made (no further run was needed to separate the two): the frozen clock is ruled out, as the 12:49
  run had it and named "Skip rest", and the 13:25 run had it too and did not; the appearance seam is ruled out, as
  the 13:25 run had no seam and already lost the element. What changed between those two runs was outside the
  code: the shared simulator's own appearance turned dark (with the app's code for the cover unchanged but for the
  receipt's revert). Not fixable in this slice; it stays excused as narrowed.
- **SF2, F15-S2-13 fixed (ruling A, as a token).** The ink at no opacity in `NameField` made the dark audit pass
  (one run), but a raw alpha in a view breaks the token rule and the Program views' source tests. So it is a
  LedgerDesign token: `LedgerColor.inkConcealed`, ink's own colour at alpha 0 (Increase Contrast too), "text drawn
  but not shown", which an audit reads as ink. `NameField` draws its hidden text and its unfocused field in it, and
  spells no `Color` at all; the one sanctioned edit is `ProgramViewsSourceAdversarialTests`' colour pin, now empty
  (F15-S2-13). The token is listed wherever the token tests list every token (`PhoneToken`, `TokenValueTests`, the
  gallery and its names). Closed for the Day editor's "Day name" and the builder's "Program name", the same
  `NameField` (the latter not audited in dark here: the builder root is the tabs lane's).
- **SF1, observation.** The element-less "Skip rest" tracks the shared simulator's own appearance: present from the
  moment it turned dark, absent before, whatever the app was told by the seam.
- **SF3.** `settle` compares the screen's first scroll view, not the whole screen, so the cover's running clock
  and the rest ring no longer keep it from settling.
- **SF4.** "Wednesday, September 30", the longest date the receipt writes, measured at Accessibility XXXL with the
  clock at 2026-09-30 (one run, reverted): frame 240 × 76 at (26, 78), two lines, whole in the picture; reported
  "Text clipped" and excused as F15-S2-4. The date excuses (F15-S2-4 and 9) take no date longer than it.
- **N1.** `expectScrollsClear` stops as soon as `last` ends above the bar or foot, and measures where `last` ends by
  its text where it has one: a row's button reaches below its text by its padding (the picker's last row at XXXL
  ended 1 pt under the foot's rule by its frame, its text well above).
- **N2.** The letter's test resolves the colours in both schemes and asserts 4.5:1 on both fills (it replaces the
  scheme-only test). **N3.** The report's open findings are counted among the issues not excused. **N4/N5** above.

## S2b — as built (G1 implementer, 2026-11-14)

Branch `feat/F15-s2b`, cut from `main` at `80b330c` (S2a merged). Scope from the orchestrator's brief: fix the open
findings, prove sheet reachability, criterion 7 (`DynamicType`), criterion 8 (`docs/accessibility-labels.md` and its
source test), the §2.7 rewrite, and nightly placement. One PR (the orchestrator's ruling on the plan); the M1-exit
nightly link is the orchestrator's, after merge.

### What landed

- **F15-S2-10, fixed.** `WorkoutHeader`'s row is `HeaderRowLayout`, a `Layout` of its three subviews, each at its own
  width: one row while they fit (the time centred between the buttons, as before); else the time on its own line
  over "Minimize" and "Finish" at either edge; else each on its own line. No smaller type, no truncation, no
  tracking. The lines touch: the pills' own padding parts them, and the rest panel's room tests (ruling 17: at least
  120 pt of the page, and the page's measured room) failed by 4 pt with an 8 pt gap. VoiceOver's order stays
  Minimize, time, Finish (sort priorities inside a containing element: by itself VoiceOver read the time first when
  it stood above, which `WorkoutAccessibilityTests` caught past an hour at Accessibility 3). `WorkoutHeaderLayoutTests`: at
  Accessibility 3 and 5, in all eight settings (both widths, bold, right to left), each button is as wide as by
  itself and no taller, and nothing leaves the phone or overlaps; at the default size it is one row.
  - First built with `ViewThatFits` (three arrangements). The audit then reported "Dynamic Type font sizes are
    partially unsupported" on "Minimize", "Finish" and the time at the default size, light and dark, and three
    element-less "Text clipped" at Accessibility XXXL: the header held three copies of its controls. A layout
    keeps one of each; the audit reports nothing on the header in any way now.
- **F15-S2-11, fixed, by porting `NameField`'s pattern** into `CreateExerciseNameField`, not by moving `NameField`
  to LedgerDesign: moving it would re-point the pins of `ProgramViewsSourceAdversarialTests` and four Program test
  files that read `FeatureProgram/Views/NameField.swift`, and the Library's field differs (body role, outlined box,
  identifier, a store-owned text and no draft). Unfocused, the name is drawn as wrapping text under the field,
  whose own text is `inkConcealed`; focused, the field draws it on one line. `CreateExerciseLayoutTests
  .name_longerThanItsLine_isDrawnWhole` (Accessibility 3 and 5: the field grows by every further line the name
  takes). At Accessibility XXXL the audit still reports "Text clipped" on the field (its hidden one-line text); the
  picture shows "Landmine / Squeeze Press" whole, so F15-S2-4's `wholeName` now takes every way.
- **F15-S2-12, fixed.** Bisected in Debug runs (reverted), light only, Settings' audit:
  - Units and Week starts on hidden: both issues gone;
  - Units alone hidden: both remain;
  - Week starts on alone hidden: both gone.
  The two were the row's title and line (`SettingsRowLabel`, hidden from VoiceOver), drawn beside the menu that
  speaks for them. They are now drawn inside the menu's button (a tap anywhere on the row opens the menu); the label,
  value and hint VoiceOver reads are unchanged. Units' label, drawn the same way beside `SegmentedChoice`, is not
  reported. The open finding and its test are gone.
- **Runner.** `ScreenAudit.run(_:launching:walk:)` takes the ways (`threeWays` calls it with all three);
  `audit(_:screen:pinned:types:)` takes the audit types; `reach(_:screen:_:in:)`, in the Accessibility XXXL way only,
  pictures the screen and scrolls each primary action into reach (`Steps.scrollIntoReach`, up then down) and
  asserts it is hittable. `expectScrollsClear`'s "lowest element" counts text fields too (Delete all's last row is
  its field).
- **Criterion 7.** In S2a's walks, the XXXL way reaches each screen's primary actions (the orchestrator's ruling: no
  second clip audit of a screen S2a audits). `DynamicType.swift` audits `.textClipped` at Accessibility XXXL on the
  screens no audit covers at that size, and reaches their actions: Today on a session day (Settings, Start
  workout), the Program builder (+ Add training day), the Library root (New exercise, search; audited by
  `LibraryAuditAdversarial`), the History list (the newest workout), Today on a rest day (Settings, Train
  off-schedule) and the off-schedule sheet (Cancel, a day). Onboarding is audited at the largest size by
  `OnboardingAdversarial`, which taps its pinned button on every step. The text size is UIKit's launch argument,
  `-UIPreferredContentSizeCategoryName`, per launch (no new seam).
- **Sheet reachability.** `expectScrollsClear` in every way (default and Accessibility XXXL included) on New exercise
  (last row: the movement pattern's chips), Bar and plates ("Reset to standard") and Delete all data (its field), on
  top of S2a's picker and edit sets.
- **Criterion 8.** `docs/accessibility-labels.md` and `AccessibilityLabelsDocTests` (LedgerAppKitTests, a source
  rule like `ModuleCopyTests`).
- §2.7 rewritten; nightly placement: superseded in review round 1 (below).

### Findings (S2b)

| ID | Screen | Issue | Measured | Verdict |
|---|---|---|---|---|
| F15-S2-4 (S2b) | Today, Today rest day, Program builder (XXXL) | Text clipped: the date, "Week 5 of 8 · ~38 min", "Lower A — Squat focus"; "Thursday, September 17", "SCHEDULED REST", "No session today"; "BLOCK · 8 WEEKS" | every glyph whole in the screen's picture, each wrapped between words | Excluded by label per screen (`DynamicType.exclusions`), near misses in `AuditExclusionsTests` |
| F15-S2-4 (S2b) | Edit exercise (XXXL) | Text clipped, the name field | drawn whole on two lines | `wholeName` takes every way |

No layout bug was found among the clipped texts: each wraps between words and draws whole.

### Sanctioned edits

- `AuditWorkout`, `AuditProgramLibrary`, `AuditHistorySettings`: the open findings F15-S2-10, 11 and 12 removed (fixed),
  with `AuditExclusionsTests+Open.swift`; their walks gain `reach` and the new scrolls-clear proofs.
- `AuditExclusionsTests`: `Edit exercise`'s name at XXXL moves from near miss to excused (re-pinned: F15-S2-11 fixed,
  measured whole).
- Five `CreateExerciseSnapshotTests` references re-recorded: the name is drawn by a text, not the field (about 1 pt
  higher at the default size), and wraps whole at Accessibility 3.
- Eight `SettingsSnapshotTests` references re-recorded: "Week starts on"'s row is the menu's label now; its value
  "Sunday" moves by a fraction of a point (the difference image shows only its glyphs' edges). The menu centred the
  row's wrapped line until the label took `.multilineTextAlignment(.leading)`.
- No workout reference changed: the header's layout at `.large`, `.xLarge` and the two `.accessibility3` covers is
  the one row it was.

### Times (local Mac, iPhone 17, iOS 27.0; the last run of each, on the final code)

| Test | Seconds |
|---|--:|
| AuditWorkout.test_cardSwapSheetAndRestPanel_passTheAudit | 169.5 |
| AuditWorkout.test_supersetFinishSheetAndReceipt_passTheAudit | 127.9 |
| AuditProgramLibrary.test_dayEditorAndItsPicker_passTheAudit | 323.5 |
| AuditProgramLibrary.test_historyNewAndEditExercise_passTheAudit | 539.1 |
| AuditHistorySettings.test_workoutDetailAndEditSets_passTheAudit | 296.3 |
| AuditHistorySettings.test_settingsAndBarAndPlates_passTheAudit | 158.1 |
| DynamicType.test_todayBuilderLibraryAndHistory_atAccessibilityXXXL | 88.1 |
| DynamicType.test_restDayAndOffScheduleSheet_atAccessibilityXXXL | 22.7 |
| AuditExclusionsTests (6 tests) | under 0.1 each |
| Smoke (4 tests) | 101.7 |

The reach steps and the three new scrolls-clear proofs add about 375 s to S2a's audits (1,175 s before, 1,614 s
now), and `DynamicType` adds 111 s. **Nightly placement** (superseded in review round 1, below) (runner time estimated as local × 1.5, the orchestrator's
rule; `docs/ci-cd.md` measured 2.4–3.1 times on package targets, so these are lower bounds): `AuditProgramLibrary`
(863 s, ~1,290 on the runner) moves to leg 5. Leg 4 holds `LedgerUITests`' other classes (1,840) plus `Flows`,
`AuditWorkout`, `AuditHistorySettings` and `DynamicType` (~1,525) and the package targets (775): about 4,140 s. Leg 5
is about 4,820 s (2,244 + 1,277 + 1,290). Both are under the ~6,300 s rebalance mark.

Other gates on the final code: `FeatureWorkoutTests` (726 tests, 3 known issues), `FeatureLibraryTests` (159),
`FeatureSettingsTests` (156) and `LedgerAppKitTests` (426) whole on the PR plan with recording off, snapshots included:
green. `check.sh --lint-only`: green. `pr-shards.adv.sh`: 31 passed.

### Review round 1 (G3: one blocker, four should-fixes; the orchestrator's rulings)

- **B1, under the nightly's 600 s a test.**
  - `Steps.scrollUntilHittable` is the one scroll helper (`scrollIntoReach` folded in). It swipes toward the
    element: down while it stands above the page's middle, up while below. `back` is kept for an element a lazy
    list has not made. Each way used to waste ten upward swipes after a scrolls-clear proof.
  - The walks are split so no UI test takes over 240 s on a Mac:
    - by screen: Day editor and picker; the exercise history, New exercise and Edit exercise (new class
      `AuditLibrary`); the workout detail and edit sets; Settings in a class of its own (`AuditSettings`), so the
      nightly can place it;
    - by way, where one screen's three ways still took over four minutes (the picker; New exercise): light and dark
      apart from Accessibility XXXL.
- **S1, placement at local × 3.** Every leg, with a build of up to 2,100 s, ends at most at about 6,050 s (the table
  below).
- **S2, the labels document bound to the shipped label.**
  - A "Wired by" column names the presentation file that hands the button its copy; the test checks the file names it.
  - "Pinned by" must hold the English words (each `\(…)` matched by any text) or the copy (the component, for a row
    with no copy), not only exist.
  - "Log drop set" is pinned by `AccessibilityTreeSetRowTables`. "Undo drop set" is pinned by
    `WorkoutPresentationCardTests` (the label handed to the row), as no hosted tree draws a logged drop set; the
    document says so.
- **S3, the detector.** It reads `Button(`, `Button {`, `Menu(` and `Menu {` with an icon label (`LedgerIconView`,
  `SetRowCheck`, `Image(`) on the same line or the line after the brace or `label: {`, and `.labelStyle(.iconOnly)`.
  A fixture test checks each form, two buttons with words and a comment. A malformed row throws `MalformedRow` with
  its line (N6).
- **S4, the guard of `wholeName`.** The reference `CreateExerciseSnapshotTests.longName_accessibility5_matchesReference`
  (the field alone, a four-line name, light, AX5), cited in the exclusion's comment beside
  `name_longerThanItsLine_isDrawnWhole`.
- **N1.** `DynamicType.exclusions` take Accessibility XXXL only, with a near miss at the default size.
- **N2.** The open-finding machinery is removed (none is left, and an untested strict path is dead code); §2.7
  says a real finding is fixed or reported. `reach` lost its unused `in page:`.
- **N3.** `OnboardingAdversarial`'s largest-size audit pictures each step and checks "Skip setup", Continue or
  "Start training", and "Back" after the first step, can be tapped.
- **N5.** `WorkoutHeaderLayoutTests.readingOrder_staysTheRows`: Minimize, time, Finish in all eight settings at
  `.large`, AX3 and AX5, and on a 200 pt phone, where at AX5 each button has a line of its own (checked). And
  `rows_byTheWidthThereIs` pins the three arrangements' boundaries. Known and accepted: crossing an hour widens the
  time ("59:59" to "1:00:00"), which can move the header from one arrangement to the next at a boundary width.
- **N4 and N8:** skipped by the orchestrator's ruling; known gaps, as G3's review records them.
- W97 of `check-wiring.adv.sh` re-pinned (sanctioned: its subject, leg 7's selection, changed).

**Times after the change** (local Mac, iPhone 17, iOS 27.0, Nightly plan):

| Class | Test | Seconds |
|---|---|--:|
| AuditWorkout | test_cardSwapSheetAndRestPanel_passTheAudit | 145.0 |
| AuditWorkout | test_supersetFinishSheetAndReceipt_passTheAudit | 125.3 |
| AuditProgramLibrary | test_dayEditor_passesTheAudit | 97.4 |
| AuditProgramLibrary | test_exercisePicker_lightAndDark_passesTheAudit | 113.4 |
| AuditProgramLibrary | test_exercisePicker_atAccessibilityXXXL_passesTheAudit | 148.2 |
| AuditLibrary | test_exerciseHistory_passesTheAudit | 97.1 |
| AuditLibrary | test_newExercise_lightAndDark_passesTheAudit | 137.9 |
| AuditLibrary | test_newExercise_atAccessibilityXXXL_passesTheAudit | 117.7 |
| AuditLibrary | test_editExercise_passesTheAudit | 122.0 |
| AuditHistorySettings | test_workoutDetail_passesTheAudit | 87.1 |
| AuditHistorySettings | test_editSets_passesTheAudit | 227.0 |
| AuditSettings | test_settingsAndBarAndPlates_passTheAudit | 142.5 |
| DynamicType | test_todayBuilderLibraryAndHistory_atAccessibilityXXXL | 76.6 |
| DynamicType | test_restDayAndOffScheduleSheet_atAccessibilityXXXL | 22.3 |
| OnboardingAdversarial | test_eachStep_passesTheSystemsAccessibilityAudit_atTheLargestTextSize | 29.3 |
| Flows | the three | 45.4, 81.5, 29.3 |
| Smoke | the four | 20.1, 22.4, 23.5, 33.4 |

**Legs** (test seconds on the runner from `nightly-shards.txt`; F15's classes at local × 3; + a build of up to
2,100 s; the rebalance mark is ~6,300 s):

| Leg | Tests | + F15 | Tests total | With a 2,100 s build |
|---|---|---|--:|--:|
| 1 | 3,072 + 84 + 55 + 38 = 3,249 | Flows 156 × 3 = 469 | 3,718 | 5,818 |
| 2 | 2,736 + 31 + 15 + 2 + 2 = 2,786 | AuditWorkout 270 × 3 = 811 | 3,597 | 5,697 |
| 3 | 4,365 | none | 4,365 | **6,465** |
| 4 | 1,840 + 301 + 203 + 166 + 105 = 2,615 | AuditHistorySettings 314 × 3 = 942, DynamicType 99 × 3 = 297 | 3,854 | 5,954 |
| 5 | 2,244 + 1,277 = 3,521 | AuditSettings 143 × 3 = 428 | 3,949 | 6,049 |
| 6 | 2,406 + 1,539 = 3,945 | none | 3,945 | 6,045 |
| 7 | 2,767 | AuditProgramLibrary 359 × 3 = 1,077 | 3,844 | 5,944 |
| 8 | 985 + 1,451 = 2,436 | AuditLibrary 475 × 3 = 1,424 | 3,860 | 5,960 |

F15's tests put no leg past about 6,050 s. **Leg 3 is over the mark on its own**: `WorkoutAnnouncementAdversarialTests`
is one suite of 4,365 s, and leg 6 is near it. Neither holds an F15 test. This is for the next rebalance, from a newer
run's bundles. The shards file's own note says the slowest build seen was 2,092 s.
