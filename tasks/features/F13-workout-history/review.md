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
