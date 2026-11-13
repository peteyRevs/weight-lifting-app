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
