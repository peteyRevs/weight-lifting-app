# F13 — review

## S1 — G3 review (round 1, 2026-10-28)

Reviewed `34aa260..81b2855` on `feat/F13-workout-history` (`ff536cd`, `093a4ec`, G2's `cf0eae9`, fix round 1
`0bbf19e`, and the notes), against the plan amendments' S1 and the rulings before G1. Rulings Q1–Q8, A3, the
`pr_count` badge, History-only "<1 min", F13-S1-3 and F13-S1-6 were taken as settled.

**Verdict: approved, with minors.** No blocker or major. R1-1 to R1-3 are worth fixing in a short fix round
(tests and notes only, about 30 lines, no product change); the nits can ride with S2.

### What was checked, and held

- **Swift 6 isolation.** `HistoryStore` is `@MainActor`; `follow` and `rebuild` are main-actor methods, so
  `sources` is touched on one actor only. The model is built by a `@concurrent nonisolated static` function over a
  `Sendable` `HistoryInput`; `HistoryPresentation`, `HistoryModel`, `HistoryRoute` and `HistoryInput` are
  `nonisolated`. Cancellation ends `marks` and both followers, as in `LibraryStore`/`TodayStore`.
- **The query.** `SELECT * FROM workout WHERE deleted_at IS NULL AND phase = 'finished' AND ended_at IS NOT NULL
  ORDER BY started_at DESC, id`: the same predicate and order as `WorkoutRows.recent`, served by
  `idx_workout_started (started_at DESC, id)`, one statement, no join. The in-memory `newestFirst` sorts the same
  way (start descending, then id text ascending). The observation tracks `workout` alone with `removeDuplicates`, so
  each commit to `workout` costs one re-read of the rows (~14 ms at 1,000) and a `workout_event` append costs none.
- **Weeks.** `HistoryWeeks.group` uses `WeekCalendar.week(containing:)` and finds `lastDay` by civil-day count, not
  by subtracting 86,400 s; the header adds the year when either end is outside `now`'s year.
- **Routes.** Today's `.openWorkout` pushes on `.today`; the Library's and History's push on `selectedTab`
  (`open(_:in:)` also selects it); "Go to Today" only selects Today. The mapping tests pin each stack's depth.
- **Accessibility and copy.** The VoiceOver tree is pinned exactly per state and size; week headers are headings
  (`Eyebrow` adds `.isHeader`); targets are at least 44 pt; no accent. The catalog has 13 keys, all `en`
  "translated"; both plurals (`%lld PRs`, `%lld minutes`) carry `%lld` in `one` and `other`. No literal outside
  `HistoryCopy.swift` other than the `" · "` / `", "` joiners, as Today does.
- **Lines.** Recounted against `98b340d` (non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps`, without
  `LedgerTestSupport` and the UI tests): **net 710**, matching the notes file by file. No line over 120 columns, and
  no sign of compression: the densest lines (`group.addTask { … }` in `+Sources`) are the house pattern.
- **Sanctioned edits.** Each is the minimum C3/Q1 needs, and each carries its "Sanctioned edit" comment. The
  conformer stubs forward or stub the two new requirements. `ProbedWorkouts.base` going internal (to split the
  file under the 300-line lint) is justified.

### Mutation checks (scratch copy from `git archive HEAD`, host `swift test`)

| Mutant | Killed by |
|---|---|
| History SQL tie order flipped to `ORDER BY started_at DESC, id DESC` (G2 could not run this one) | **Killed twice.** `HistoryListAdversarialTests.historyList_agreesEverywhere` failed 7 of 40 seeds. `WorkoutRepositoryTests`' history clause 1 ("historyEntries lists every stored workout newest first…") failed on GRDB |
| `lastDay = bounds.upperBound − 86,400 s` | **Killed.** `HistoryWeeksTests.group_acrossDaylightSaving_endsOnItsSeventhDay`, and `HistoryWeeksAdversarialTests` in 4 of 5 zones |
| `removeDuplicates()` → `removeDuplicates { _, _ in false }` (the observation emits on every `workout` commit) | **Survived** both the contract and the differential test: R1-1 |
| `HairlineRow`'s title `.lineLimit(1)` (criterion 8), on the simulator | **Killed only at `.accessibility5`** (row 228 pt, name 261 pt) on the PR sweep; it **survived** at `.xSmall`, `.large` and `.xxxLarge`, plain and bold right to left: R1-2 |

### Findings

**R1-1 (minor). N2's "and for no other write" is not pinned: the duplicate-suppression mutant survives.**
`Sources/LedgerDomain/Protocols/Repositories.swift:142-145` and
`Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository+History.swift:15-17,26` promise that "a write to a
workout that leaves every entry as it was emits nothing". With `removeDuplicates` disabled, every test still passes:
the contract only checks a `workout_event` append (another table), and no step of F05's `HistoryScript` writes
`workout` without changing an entry. The cost of the regression is small (one more rebuild, `show` drops an equal
model), but S3's batched edit and its performance budget lean on this promise.
*Fix:* a fourth clause in `WorkoutRepositoryContract+History.swift`: after the first value, `updateSets` that
changes only a not-done set's weight (or rewrites the same sets), then `values.next(within: StatsQueriesContract.quiet)`
is nil, on GRDB and in memory.

**R1-2 (minor). Criterion 8's guard can't fail below accessibility sizes, and has no control.**
`Tests/FeatureHistoryTests/HistoryLayoutTests.swift:83-104` compares the whole row's height with the long name's
text height. The row also holds the meta line, the badge and 2 × `LedgerSpacing.l` of padding, so at `.xSmall`
to `.xxxLarge` a row whose name is cut to one line is still taller than the name's two or three lines.
The simulator mutant shows it: with the title cut to one line, the PR sweep (`TEST_RUNNER_LEDGER_SWEEP=pr`)
fails only at `.accessibility5`, by 33 pt, and passes the six other settings. `.accessibility3`, the size criterion 8
names, is not in the PR sweep, and the 33 pt margin at AX5 suggests AX3's would be thin.
*Fix:* compare against what the row must hold: the name's height plus the meta's (both measured as `Text` at the
row's text column width), or measure the name `Text` itself inside the row; and add a control that a
`.lineLimit(1)` copy of the row fails the same guard (as F12's `SearchFieldFitTests` does).

**R1-3 (minor). F14 coordination: one semantic break `git merge-tree` can't see, and one test edit that leans on
F14's placeholder.**
- `git merge-tree --write-tree feat/F13-workout-history feat/F14-settings` (F14 at `bcdeacb`) conflicts textually
  only in `LedgerKit/Package.swift` (the adjacent `FeatureHistory`/`FeatureSettings` target lines) and
  `scripts/coverage-thresholds.json` (`required` is one line): trivial, as A10 expected. But F14 adds
  `SettingsRepository.seedIfAbsent(_:)` with no default, and F13 adds a new conformer,
  `Tests/FeatureHistoryTests/HistoryStoreTests.swift:164` `EndedSettings`. That merge auto-resolves and then fails to
  compile FeatureHistoryTests.
- `Tests/LedgerAppKitTests/AppTabsTests.swift:73-75` now proves "selecting a tab swaps the screen" by pushing
  `.settings` on Program and reading the heading "Settings". That is the placeholder F14 replaces with its
  `SettingsRoot`, which (like every feature root in a scene-less window) may read nothing there.
*Fix:* add both to the notes' "Inputs for S2" / A10 list, so whichever lane lands second adds `seedIfAbsent` to
FeatureHistoryTests' `EndedSettings` and re-points this test (for example at `.workout`'s placeholder,
`history.workout.title`, which F13 owns until S2). The other F13 registration edits are line-local:
`snapshotTestTargets` appends to F12's line (a one-line conflict if F14 does too), `PreviewScan` puts
`"FeatureHistory"` on its own line, and `AppTabs`/`MainRoot` add one line each.

**R1-4 (nit). The spoken "<1 min" capitalises mid-row.** `Sources/FeatureHistory/HistoryCopy.swift:48-53`: the
row reads "Wednesday, Under a minute, 24,180 pounds". Every other spoken part is lower case ("58 minutes"). *Fix:*
key the spoken form "under a minute", in the case of the words around it.

**R1-5 (nit). `Weight.spoken` round-trips through a string, and has no S1 caller.**
`Sources/LedgerDomain/Units/SpokenWeight.swift:17-19` parses `formatted(in:)` back with `Decimal(string:) ?? 0`,
so a format change would silently speak "0 pounds". `Volume.spoken` (`:26`) re-derives `value(in:)` by hand. *Fix:*
expose the rounded `Decimal` that `formatted(in:)` prints (or round `value(in:)` the same way) and pass it to
`SpokenMass.text`; `Volume.spoken` can call `value(in: units).roundedToInt()`. The helper is ruled into S1 (A6) and
its first product caller is S3, so this can land there.

**R1-6 (nit). Two copies of the entries-with-records builder.** `Views/History+Previews.swift:49-58`
(`HistoryPreviewData.entries`, counted product lines) and `Tests/FeatureHistoryTests/Support/HistoryTesting.swift:74-83`
(`HistoryFixtures.entries`) are the same ten lines. *Fix:* the test fixture calls `HistoryPreviewData.entries`
(the test target already imports the module `@testable`, and is `DEBUG`-only like the preview).

**R1-7 (nit). `.workout`'s placeholder has no `.id(destination)`.** `Sources/LedgerAppKit/AppTabs.swift:73-75`.
Harmless while it is stateless; S2's root needs it, as the notes already say.

### Tests: wall clock and sizes

- Wall-clock asserts are confined to the two nightly `.performance` suites (gated by `TestLane.runsSlowTests`).
  Elsewhere time appears only as a negative wait (`next(within: quiet)`, 200 ms, for "nothing arrives") or a
  generous upper bound (`within: .seconds(5)`); the store tests wait by Observation (`eventually`), not by time.
- No large `#expect` literal: the longest is the four week titles; the 1,000-row model asserts a count.

### Commands run

- `git diff --stat 34aa260..HEAD`; `df -h /` (21 GiB free at the start).
- `git archive HEAD | tar -x -C <scratchpad>/g3-f13s1`; `swift build --build-tests`: Build complete (123 s).
- `swift test --skip-build --filter "FeatureHistoryTests|HistoryListAdversarialTests|HistoryWeeks|SpokenWeight|
  WorkoutRepositoryTests|InMemoryContractTests|HistoryRouteMapping"`: all passed (FeatureHistoryTests 51 tests in
  9 suites with 1 known issue, F13-S1-3; persistence 29 tests with 1 known issue already on `main`; 11 and 2 more).
- Mutants as in the table, each rebuilt and run, then reverted (`diff` against `git show HEAD:` clean).
- `LEDGER_TEST_LANE=nightly swift test --skip-build --filter "HistoryPerformanceTests|HistoryQueriesPerformanceTests"`:
  both passed (while F14's gate loaded the machine).
- `git merge-tree --write-tree --name-only feat/F13-workout-history feat/F14-settings`: conflicts in
  `LedgerKit/Package.swift` and `scripts/coverage-thresholds.json` only.
- Net product lines recounted per file against `98b340d`: 710.
- Simulator, through `sim-lock.py` (it waited behind F14's gate), from the scratch copy with its own derived data,
  the `.lineLimit(1)` mutant: `xcodebuild test-without-building -testPlan PR -only-testing:FeatureHistoryTests/HistoryLayoutTests`
  with `TEST_RUNNER_LEDGER_SWEEP=pr`: exit 65. `parts_layOutSanely` passed all 24 cases. `longName_wrapsWhole` failed
  at `accessibility5` (both settings) and passed the other six.

## S2 round 1 — G3 review (2026-10-29)

Reviewed `e10cbe0..2d6db25` on `feat/F13-history-detail`:
- `fac1f94` and `cfb9bd5`, the slice
- `cce902e`, the notes
- G2's `b01052b`
- fix round 1, `3d7694a` and `2d6db25`

The reference is the plan amendments' S2, the rulings before G1, and the carried items F13-S1-6 and R1-5 to R1-7. Pete's questions Q1, Q5 and Q8 (built to A), ruling A3 and G2's F13-S2-4 and -5 (accepted as built) were taken as settled.

**Verdict: APPROVED WITH MINORS.** There is no blocker or major finding.
- **S2-R1-1 (minor)** is a real hole in the fix round's promise that "a confirmed delete is never lost". It is a one-line fix plus one test, and should land before merge.
- **The nits** are tests, plus one simplification. They can ride with S3.

### What was checked, and held

**Correctness against the spec**
- Criterion 3: the tiles, the records line and the rows (rule 30) are drawn in the lifter's units, under "Wednesday, September 16" and the name. A row emits `.exercise(id)`, which pushes on the same stack.
- Criterion 5 and N9: one alert, then one `delete(id:)`, then `.closeWorkout(id)`, which pops only a `.workout(id)` on top.
- Criteria 6, 7 and 8 (detail parts), N8, N10, N13, N14 and N6: each traces to a test in the notes' table.
- Net product lines, recounted against `e10cbe0` per file: **667**, matching the notes.

**The delete state machine** (`idle → confirmed → running → done`)
- "Delete" is accepted only from `idle`, on a detail that is not `.gone`.
- `delete()` runs only from `confirmed`.
- A cancellation before the write returns to `confirmed`. A failure returns to `idle`, says so in the alert, and can be retried.
- Cancellation is safe at every point of the write, because GRDB's async write is one transaction:
  - Cancelled while waiting for the writer: it throws `CancellationError` at `Task.checkCancellation()` once its block starts.
  - Cancelled while the write runs: `db.cancel` interrupts it, and it rolls back with `CancellationError`.
  - So the "re-run on return" design never half-deletes.
- One sequence loses the delete: S2-R1-1.

**What ends a source** (`follow(_:keep:ended:)`)
- Only the workout's own end shows N10.
- The settings' end keeps the last settings seen, or `.default`.
- A cancelled run's end changes nothing, though that is not pinned (S2-R1-3).
- The nil is checked first, so a delete elsewhere always closes the detail.
- A re-run resets `sources` but not `state`. A `.gone` detail found gone again asks to close again (decision 3).

**N10's promise, "You can still delete it"**
- `delete(id:)` reads its scope leniently (`RecordReplay.Scope(ofStored:)`), and the replay leaves out a workout it can't read.
- A scratch probe deleted each of G2's four own-damage cases on GRDB, and each workout left `historyEntries()`. It holds, but the repo does not pin it (S2-R1-5).

**`observeWorkout(id:)` on GRDB**
- One `ValueObservation`: the strict `WorkoutRows.fetch(.one(id))` plus `personal_record WHERE workout_id = ? AND deleted_at IS NULL ORDER BY exercise_id, kind` (`idx_pr_workout`), then `removeDuplicates`.
- **Region.** The ids are text, so the region is the four tables whole. A commit to `workout`, `workout_exercise`, `logged_set` or `personal_record` (any workout's) costs each running detail one re-read of one workout and its records, a few ms.
- **What does not wake it.** `workout_event` appends (set taps) and settings saves don't touch those tables, and an equal value is dropped.
- **While the workout is nil**, the region is `workout` alone, which is enough, since its insert writes `workout`.
- **Hidden tabs** don't pay, since their tasks are cancelled (R5).

**Route origin (F13-S1-6)**
- Every caller is updated:
  - `MainRoot` passes `$1`.
  - `AppTabs` hands `.library` and `.history` to the tab roots.
  - `screen(for:in:)` hands the stack's own `tab` to `ExerciseHistoryRoot` and `WorkoutDetailRoot`.
- `Routes+Today` and `Routes+Workout` were already explicit (`.today`).
- No path can push on the wrong stack: the tab is the stack's own, captured when the destination is drawn.
- `.closeWorkout` does not select a tab. `.exercise`/`.workout` do (F13-S2-4, accepted).
- `.id(destination)` is on all three pushed roots.
- Two of the four `in: tab` sites are unpinned (S2-R1-2).

**N13 parity**
- `WorkoutDetailPresentation.make` is F10's `receipt` with:
  - the lifter's units in place of the workout's
  - `ReceiptRow(exercise:units:)` in place of `summary.rows`, which also drops F10's `zip` hazard
  - no "Done"
- `ReceiptParityTests` covers five previews, and G2's adversarial version covers 120 workouts × 2 units × 7 locales.
- **Duplication.** Ruling A3 accepted the copied keys and builder. Two copied helpers need no catalog (S2-R1-4).

**Catalog**
- 36 keys, all `en` "translated".
- Both new plurals carry `one` and `other`, and match FeatureWorkout's entries character for character:
  - `%lld new PRs this session`
  - `%@ of %lld sets logged`
- `setsLogged`/`newRecords` use `forCountedText` and `moved`/`spoken…` use `locale`, as F10 does.

**Accessibility**
- The name is a heading and the day sits above it.
- The receipt reads as F10's: each tile is one stop, "LOGGED" is a heading, each row is a button with its spoken text, and the note is hidden.
- "Delete workout" is a ghost `PillButton` in ink, with its identifier, and the alert's "Delete" is the one red.
- The implementer's trees and G2's right-to-left mirror pin the reading order and the 44 pt targets.
- No navigation title, as on `ExerciseHistoryRoot`.

**Idiom and comment density**
- The store, the root and the views follow `ExerciseHistoryStore`/`ExerciseHistoryRoot` line for line:
  - `.task(id: scenePhase == .background)`
  - `.task(id: pendingRoute)`
  - a store that does nothing when made
- Doc comments are as dense as the surrounding feature code. No line is over 120 columns.

### Mutation checks

Run in a scratch copy (`git archive 2d6db25`), host `swift test --skip-build`, each mutant rebuilt, run, then restored (`diff` against the worktree clean). The filter was:
- FeatureHistoryTests
- the History/Library route-mapping and detail-adversarial suites
- both parity suites
- `WorkoutRepositoryTests`, `InMemoryContractTests`, and G2's two persistence suites

The baseline is green, with only the known F7-10 and F13-S1-3 issues.

| # | Mutant | Result |
|---|---|---|
| m1 | `confirmDelete` accepts any `deleting` (no `== .idle`) | **Killed**: `delete_confirmedTwice_deletesOnce`, `confirmDuringDelete_isDropped` |
| m2 | `delete()` also runs from `.running` | **Killed**: `deleteRunTwice_whileInFlight_deletesOnce` |
| m3 | a cancelled run goes to `.idle`, not `.confirmed` | **Killed**: `deleteCancelled_isNotLostSilently` |
| m4 | a failure goes to `.done`, not `.idle` (no retry) | **Killed**: `delete_failed_keepsTheScreen` ("a later one may try again") |
| m5 | success goes to `.idle`, not `.done` | **Survived**: `.done` is unobservable (S2-R1-3) |
| m6 | the cancellation test drops `&& Task.isCancelled` | **Survived**: equivalent (GRDB throws `CancellationError` only for a cancelled task) |
| m7 | settings' end sets `workoutHasEnded` (the pre-fix F13-S2-1) | **Killed**: both `WorkoutDetailSettingsAdversarialTests` F13-S2-1 tests |
| m8 | settings' end leaves `settings` nil (no `.default`) | **Killed**: `settingsEndAtOnce_doesNotBlameTheWorkout` |
| m9 | the workout's end does nothing | **Killed**: `unreadable_saysSo_andDeletes` |
| m10 | no nil check in `rebuild()` | **Killed**: 4 store-adversarial tests (`deleteElsewhere_closesOnlyItsDetails`, `runAgain_onAGoneWorkout_closesAgain`, …) |
| m11 | the nil check after the `workoutHasEnded` guard (the pre-fix order) | **Survived**: equivalent since the fix (a nil can't be followed by the workout stream's own end, and the settings no longer set it) |
| m12 | `follow`'s end runs when cancelled (`if !Task.isCancelled` → `if true`) | **Survived**: S2-R1-3 |
| g1 | GRDB: no `removeDuplicates()` | **Killed**: the detail contract clause on GRDB, `observeWorkout_agreesWithTheFake_andEmitsOncePerChange` (25 issues), `damageElsewhere_keepsTheStream` |
| g2 | GRDB region without `personal_record` (`tracking(regions: [workout, workout_exercise, logged_set])`) | **Killed only by** `ownDamage_endsTheStream` (the record-damage case). The contract and the property test pass: S2-R1-5 |
| g3 | records `ORDER BY kind, exercise_id` | **Killed**: the property test, `manyRecords_sameOrderOnBoth` |
| g4 | `strict: false` | **Killed**: `ownDamage_endsTheStream` (4 cases), `damagedBeforeObserving_endsWithoutAValue` |
| g5 | records without `deleted_at IS NULL` | **Killed**: the GRDB detail clause, the property test |
| r1 | `Routes+History` `.workout` pushes on `selectedTab` | **Survived**: S2-R1-2 |
| r2 | `Routes+History` `.exercise` pushes on `selectedTab` | **Killed**: `lateRoute_landsOnItsOwnTab`, `lateRoute_landsOnItsOwnStack` |
| r3 | `Routes+Library` `.openWorkout` pushes on `selectedTab` | **Killed**: `HistoryDetailAdversarialTests.lateRoute_landsOnItsOwnStack` |
| r4 | `Routes+Library` `.exercise` pushes on `selectedTab` | **Survived**: S2-R1-2 |
| r5 | `.closeWorkout` pops when the stack `contains` the detail | **Killed**: `closeWorkout_popsOnlyTheDetailOnTop` and 3 adversarial route tests |
| r6 | `.closeWorkout` pops whatever is on top | **Killed**: the same 4 |
| s1 | simulator: the root's `.task(id: store.deletion)` → `.task` | **Killed**: `WorkoutDetailRootTests.root_deletesOnce_andCloses`, `root_failedDelete_keepsTheDetail` |
| s2 | simulator: `AppTabs` hands the detail's routes `.history`, not its stack's `tab` | **Survived** the PR-plan suites (`AppTabsTests`, `HistoryRouteMappingTests`). By reading, only the nightly UI test `test_deleteFromToday_leavesNoRecentRow` would catch it: the close would not pop the detail on Today. This is S2-R1-2's gap one level up |

### Findings

**S2-R1-1 (minor). A cancelled delete can be stranded: the screen comes back while the cancelled run is still waiting for the writer.**
- **The sequence.** `Sources/FeatureHistory/WorkoutDetailStore.swift`, `delete()`:
  1. The lifter confirms. Run A starts (`deleting = .running`) and waits for GRDB's writer, which is busy with a sync's or a settings write.
  2. The lifter switches tab. SwiftUI cancels A, but GRDB does not see the cancellation while waiting: `SerializedDatabase.execute` sets its cancel hook only once the block starts.
  3. The lifter switches back. The root's `.task(id: deletion)` runs again, as run B. `deleting` is still `.running`, so B returns at once.
  4. The writer frees up. A starts, throws `CancellationError`, and sets `deleting = .confirmed`, with no task left to run it.
- **The failure.** The workout is not deleted, and nothing is said.
  - A new "Delete" in the alert is silently ignored, since `confirmDelete()` accepts only `.idle`.
  - This lasts until the screen goes and comes back once more.
- **The test that reproduces it.**
  - The test is `G3DeleteRaceProbeTests` in the scratch copy. Its repository's delete waits ignoring cancellation, then checks it, as GRDB's queue does.
  - It fails: `stored == nil` is false, and `deletion` stays 1.
  - G2's `GatedWorkouts.Gate.before` returns as soon as it is cancelled, so it cannot model this.
- **How likely.** The writer must be busy, and the tab switch and return must both happen within that wait. That is rare, but it is silent, and it breaks the round's own promise.
- **Fix (one line, verified in the scratch copy).** In the cancellation branch, also make the next `deletion`:

  ```swift
  guard !(error is CancellationError && Task.isCancelled) else {
      deleting = .confirmed
      deletion = (deletion ?? 0) + 1
      return
  }
  ```
  - A new `.task(id:)` then runs the confirmed delete when the screen is up, or next comes up.
  - With it, the probe passes, and `WorkoutDetailStoreTests`, `WorkoutDetailStoreAdversarialTests` and `WorkoutDetailSettingsAdversarialTests` stay green (23 tests).
  - Add the probe as a store test, with a gate that ignores cancellation while it waits.

**S2-R1-2 (nit). F13-S1-6 is only half pinned: two of the four `in: tab` sites survive as `selectedTab`.**
- **The sites.**
  - `Sources/LedgerAppKit/Routes+History.swift`, `.workout(id)` (r1).
  - `Sources/LedgerAppKit/Routes+Library.swift`, `.exercise(id)` (r4).
- **Why it is harmless today.** Each is sent only from its own tab's root, whose task is cancelled while hidden.
- **The risk.** The doc comments promise that "a route handed over late still lands on the stack it came from", and a later sender (S3's sheet, or another tab hosting the list) would break that unnoticed.
- **Also.** `AppTabs` passing its stack's `tab` to the detail (s2) is caught only by the nightly UI test.
- **Fix.**
  - In `HistoryRouteMappingTests`, select Today and resolve `HistoryRoute.workout(id)` from `.history`. Expect History's stack to be `[.workout(id)]` and Today's to be empty.
  - Do the same in `LibraryRouteMappingTests` for `LibraryRoute.exercise(id)` from `.library`.

**S2-R1-3 (nit). Two store behaviours are unpinned: a cancelled run's end, and `Deleting.done`.**
- **A cancelled run's end (m12).**
  - With `if !Task.isCancelled` removed, every test still passes. Yet cancelling a run would then set `state = .unreadable` on every covered or backgrounded detail: "This workout can't be read." shows when the lifter comes back, until the new run's first values arrive.
  - Fix: a store test that runs to `.loaded`, cancels the run, awaits it, and expects `.loaded` still.
- **`.done` (m5).**
  - After a successful delete, `state == .gone` already makes `confirmDelete()` a no-op, so `.done` is never observed.
  - It differs only if the workout comes back while the store lives (R1's late envelope, F17). There it makes "Delete" dead on that screen for good.
  - Fix: return to `.idle` on success, so three states remain and `.gone` guards. Or pin why `.done` is wanted.

**S2-R1-4 (nit). Two helpers are copied from F10 although they need no catalog.**
- **The helpers.** `WorkoutDetailPresentation.spokenElapsed` and `startDay` (about 25 lines) are verbatim copies of `WorkoutPresentation.spokenElapsed`/`startDay`.
- **Why A3 does not cover them.** A3's reason for the copy is each module's own catalog. These two are pure `Duration.UnitsFormatStyle` and `Date.FormatStyle` calls, with no key.
- **Fix.** Move them once beside `ClockText.elapsed` (LedgerDesign), and have both presentations call them. N13 then has less to pin.
- **When.** Optional, with S3.

**S2-R1-5 (nit). Two GRDB promises hold, but no test states them.**
- **The `personal_record` part of the region (g2).**
  - Without it, the contract and the property test still pass, because each replay that moves this workout's records also rewrites `pr_count` on its `workout` row.
  - A record that changes with its count unchanged would be missed. For example, a later replay gives this workout's record a new `previous` after an earlier workout's edit.
  - Only the damage test (`kind = 'fastest'`) kills it.
  - The detail draws only the count today, so nothing visible is wrong. S3's edits make this path common, though.
  - Fix: a contract clause in which an earlier workout's edit changes this workout's record, but not its count, and the observation emits.
- **N10's "You can still delete it" on GRDB.**
  - `ownDamage_endsTheStream` calls `try? delete` and checks only the stream.
  - My probe shows the delete succeeds and the list loses the workout in all four cases.
  - Fix: write `try` and add `#expect(!historyEntries().contains(id))`.

### Commands run

- `git log`/`git diff --stat e10cbe0..2d6db25`. `df -h /`: 23 GiB free at the start.
- `git archive HEAD | tar -x -C <scratchpad>/g3f13s2`, then `swift build --build-tests`.
- Baseline: `swift test --skip-build --filter "<the filter above>"`. All passed, with the known F7-10 and F13-S1-3 issues.
- **Probes**, deleted afterwards:
  - `G3DamagedDeleteProbeTests`: 4 of 4 passed.
  - `G3DeleteRaceProbeTests`: failed as S2-R1-1 describes, then passed with the one-line fix (reverted).
- Each mutant: rebuild, run, then `cp` back from the worktree and check with `diff -q`.
- Net lines: `netlines.py e10cbe0`, giving 667.
- Simulator, through `sim-lock.py`, which waited behind F14's gate. From the copy, with its own derived data, and with s1 and s2 applied together: `xcodebuild test-without-building -testPlan PR` (sweep `pr`) on `FeatureHistoryTests/WorkoutDetailRootTests`, `LedgerAppKitTests/AppTabsTests` and `LedgerAppKitTests/HistoryRouteMappingTests`. Exit 65: only the two root tests failed.
- Removed the copy's `.build` and `.derivedData` at the end.
