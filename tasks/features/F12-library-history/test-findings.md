# F12 — test findings

## Slice S1 — round 1 (G2 tester, 2026-10-21)

**Outcome: one real defect (F12-S1-1, Major, open for G1), and the audit's other five Library issues measured and
excluded as false positives (F12-S1-2, fixed).** The store, the presentation and `bestSets()` held under attack:
no wrong number, no wrong row and no stuck state was found. Two low findings record behaviour as built for a
decision.

Slice under test: `feat/F12-s1-library` at `e5c2ce0` (6 commits on `main` @ `011ab3d` plus the plan, `e9b7aa0`).
Scratch `scratchpad/f12s1-g2/`; every simulator command ran through the lock. No product code was changed in the
commit; one product line was changed temporarily to prove a test (below) and put back.

### What was attacked, and what held

- **`bestSets()` (N3), GRDB against the in-memory stores and the model.** F05's random history scripts
  (`HistoryScript`: materialisations valid and refused, `updateSets`, deletes, zero loads, kg beside lb, 13 and
  20 reps, every kind of set, undone sets) never asked `bestSets`, which did not exist when they were written.
  `BestSetsAdversarialTests` runs 60 seeds × 14 steps and after every step checks GRDB's `bestSets()` against its
  own `bestSet(exerciseID:)` one by one, against `HistoryModel` and against LedgerFakes. All agree. Edges one at
  a time: one weight entered in kg and in lb (100 lb = 45.359237 kg exactly) ties and goes to more reps; a
  bodyweight exercise at zero load has an entry; one exercise on two rows of a workout gives one entry, the best
  of both; a set edited away takes its best with it, and a deleted workout empties the map. **Mutant:** the SQL's
  `reps DESC` flipped to `ASC` fails three of the six tests (five seeds of the property test); restored and
  compared.
- **Store (N1, criteria 1, 2, 8).** A failed stats read is left at the next change and the model comes back with
  the query typed meanwhile; the newest workout deleted while the Library is up takes its PR and its recent row
  with it ("1 session" after); seven logged exercises give five recent rows, the latest first; a change of units
  with a query and a chip on keeps both. All pass.
- **Search and chips.** Combinations, blank and whitespace queries (`ExerciseSearch.key` trims), an equipment
  with no chip, an exercise recent but filtered out, and "Nothing matches" with Clear filters: covered by the
  implementer's suites and by the above; nothing new failed.
- **F11's references.** `git diff main...HEAD --stat` on `FeatureProgramTests`, `FeatureTodayTests`,
  `FeatureWorkoutTests` and `FeatureOnboardingTests` shows no `__Snapshots__` file at all (two Swift test files
  only, both sanctioned). The only reference changed outside FeatureLibrary is the design gallery's dark one,
  for its new section. Byte-identical, as R5 asks.
- **Conventions (N5).** `grep` over `FeatureLibrary` and the two moved components: no `Task {`, `Timer`,
  `TimelineView`, `DispatchQueue`, `Date()` or `Locale.current`; the one `.formatted(` is the Domain's
  `Weight.formatted(in:)`. Every `String(localized:)` is in `LibraryCopy*.swift`; both counted texts ("Search %lld
  exercises", "%lld sessions") use `locale.forCountedText`. The implementer's `FeatureLibrarySourceTests` pins the
  same.
- **Accessibility sizes.** Pictures of the running app at the default size, Accessibility L and Accessibility
  XXXL, with a query typed; the layout and VoiceOver suites' sweeps. Found F12-S1-1.

### Findings

**F12-S1-1 — Major. The search field cuts a query's tails while it is edited, at accessibility
sizes; it is also the audit's "Text clipped" on "Search 224 exercises".**
- **G1 round 2 (2026-10-21): the tails are fixed in `d5704eb`** (`.ledgerFieldFont(.body)`, the ruling's one
  line). `searchField_edited_drawsItsTailsWhole` passes, unedited. **F12-S1-1 is fixed (the tails) in `d5704eb`.**
  The audit's "Text clipped" on the empty field persisted, also with an explicit `prompt:` (round 3, reverted),
  and is F12-S1-5 below.

**Round 4 (G3's review M1, G1).**
- **The placeholder was truncated for real** on 375- and 390-pt phones from `.accessibility3`, and on a 320-pt
  phone from `.accessibility2`. The field now draws "Search" where the whole placeholder doesn't fit.
- **The measurement is tightened.** It gained a height-for-width floor per drawn text, a trailing-padding guard,
  and a control that is shown to fail.
- **The exclusion is narrowed** to an empty text field.

See the notes' "Round 4".

**F12-S1-5 — note, excluded (G1 round 3, ruling's Option 2). The audit's "Text clipped" on the empty search
field is a false positive.** The placeholder "Search 224 exercises" has no descender, and it is drawn whole
between the pill's two strokes at all three sizes. The evidence is the field's picture at each size, kept with the
result, and `LibraryAuditAdversarial.test_searchPlaceholder_isDrawnWholeInsideTheField`, which reads that picture
row by row. It finds the two strokes, and finds the placeholder's ink clear of both by more than 2 px. The reported
frames are the field's own: 350 × 44, 51 and 72 pt. The audit gave the same verdict with the system's
placeholder and with an explicit prompt in the field's font. That exact line, the label "Search … exercises" on
"Text clipped", is now excluded in `LibraryAuditExclusions`.
- Cause: `LedgerDesign/Components/SearchField.swift:21` sets the field with `.ledgerFont(.body)`, the role's own
  line of 1.2. `ledgerFieldFont(_:)` exists for exactly this: its doc comment and F11 S10's ruling 22 say UIKit
  clips an edited field's text to its line and that 1.2 cuts the tails from `.accessibility3`; a one-line field
  takes `ledgerFieldFont`, which sets 1.3. The field was moved unchanged from F11's picker, so the picker has
  the same defect on `main`; S1 puts it on a tab root.
- Repro: Library tab, Accessibility XXXL, type "lying": the bottoms of the y and the g are cut flat (picture
  "Accessibility XXXL: field typed lying" in the round's result bundle; also visible at Accessibility L).
- Failing tests:
  - `LedgerDesignTests/Adversarial/SearchFieldLineAdversarialTests.swift`,
    `searchField_edited_drawsItsTailsWhole`: at `.accessibility5` the edited field's "Gyp" is 37.33 pt of ink
    against 38.33 for a text of the role (`FieldFontTests`' measurement, on the component itself). **With the one
    line changed to `.ledgerFieldFont(.body)` it passes** (run `field-fixed`); the line was put back.
  - `Apps/LedgerUITests/LibraryAuditAdversarial.swift`,
    `test_libraryRoot_passesTheAudit_butForItsMeasuredFalsePositives`: "Text clipped" on the field at all three
    sizes (frames 350 × 44, × 48.7, × 68.3).
  - `TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit`: its one Library line.
- Fix for G1: `.ledgerFont(.body)` → `.ledgerFieldFont(.body)` in `SearchField`. **It needs a ruling first:** the
  line grows by 0.1 of the size, so the field is about 1.5 pt taller at `.large`, and F11's picker references and
  the gallery's would be re-recorded. That breaks R5's "byte-identical" in the letter; R5 was about the move, not
  about keeping a defect. Then re-run the audit: if "Text clipped" stays on the field once the tails are whole,
  measure it and exclude it with its reason.

**F12-S1-2 — fixed (by the tester). Five of the six Library issues the audit reports are false positives, of the
kinds already judged on Today; they are now excluded on the Library alone.**
- Evidence, from the audit run with frames (`LibraryAuditAdversarial`, at rest, iPhone 17, iOS 27.0; tab bar
  frame y 791–874):
  - "Dynamic Type font sizes are partially unsupported" on "ALL EXERCISES": the frame is 10 pt tall at the
    default size, 22.3 at Accessibility L and 74 (two lines) at XXXL. It grows at every size above the default
    and does not shrink below it: `Eyebrow`'s Caption 2 curve, Today's F09-S5-2. Program's identical eyebrows
    report the same on `main`.
  - "Text clipped" on "ALL EXERCISES": the frame is the eyebrow's line, as tall as its size, as Today's
    F09-S5-4; capitals have no tails, and the element's pictures at all three sizes show it whole.
  - "Contrast failed" on "Band External Rotation", its "—" and "Band · Shoulders" (default size; at
    Accessibility L "—" and "Back Extension", at XXXL "ALL EXERCISES"): every element reported lies inside the
    tab bar's frame (y 821, 832, 843; 789–849; 737–811), none above it. It is the bar's glass measured over them.
    Scrolled to its end the last row stands clear of the bar at the default size and at XXXL
    (`test_lastRow_scrollsClearOfTheTabBar`, passes). One more of the kind shows only once scrolled: a meta line
    passing under the status bar (y 35), which the at-rest audits do not reach.
  - The sixth issue, "Text clipped" on the search field, is F12-S1-1 and is **not** excluded.
- Change: `LibraryAuditExclusions` (in `LibraryAuditAdversarial.swift`), by the issue's words and the element's
  label (eyebrows) or frame (under the bar), as `TodayAuditExclusions`. **Sanctioned edit of
  `TabsAdversarial.swift`:** the exclusion test moved into a small helper in its extension that asks Today's
  exclusions on Today and the Library's on the Library (the class body had to stay under the lint's 150 lines);
  no other line changed.
- Result: Nightly `TabsAdversarial`'s audit now lists Program's 26 issues (F11-S14-5, unchanged) and the one
  F12-S1-1 line.

**F12-S1-3 — low, question for Pete. A bodyweight exercise done at no added load reads "0" and is spoken "PR 0
pounds".**
- Rule: the brief, "PR value on Library rows = `bestSet.weight` in user units, '—' if none". As built, a Push-Up
  logged at 0 lb has a best set (0 × 15), so its row reads "0", while one never logged reads "—".
- Test: `LibraryStoreAdversarialTests.zeroLoadBest_readsZero_andSpeaksIt` pins it as built (passes);
  `BestSetsAdversarialTests.bestSets_zeroLoadOnly_isAnEntryWithMostReps` pins the query.
- Options: keep it, or show "—" (or reps, "×15") for a zero-load best. A change lives in
  `LibraryPresentation.row`.

**F12-S1-4 — low, note. A set whose weight cannot be read takes its exercise's whole entry out of `bestSets()`.**
- The query reads only the first of each exercise's ranking, and SQLite orders a text above every integer, so a
  damaged weight on even a light set ranks first; it is then logged and left out, and the exercise has no entry
  although its real best is readable. Every other exercise keeps its best, which is what the doc comment
  promises. `bestSet(exerciseID:)` throws for that exercise, so S2's history will fail where the Library shows
  "—". Foreign damage only.
- Test: `BestSetsAdversarialTests.bestSets_damagedWeight_leavesOutOnlyItsExercise` (passes, pins both halves).
- No change asked; if wanted, rank only `typeof(weight_e7g) = 'integer'` rows, or read the next row on failure.

### The accent test

`TabsAdversarial.test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark` **fails on `main` too**, with the
same words ("Today selected: Today is not in the accent", `:94`). Run on a detached worktree of `main` @ `011ab3d`
(`main-tabs`), Nightly plan, same simulator. It is the known environment issue of F08's round 2 (the shared
simulator does not apply the dark appearance), not this slice's. On `main` the audit test fails with Program's 26
issues and nothing on the Library placeholder, so the six Library issues were all new with this slice.

### Tests added

| File | Tests | Result |
|---|---|---|
| `LedgerPersistenceTests/Adversarial/BestSetsAdversarialTests.swift` | 6 (one over 60 seeds) | pass |
| `FeatureLibraryTests/LibraryStoreAdversarialTests.swift` | 5 | pass |
| `LedgerDesignTests/Adversarial/SearchFieldLineAdversarialTests.swift` | 1, swept through `TestSweep` | **fails: F12-S1-1** |
| `Apps/LedgerUITests/LibraryAuditAdversarial.swift` (Nightly) | 2 | audit **fails: F12-S1-1**; scroll passes |
| `Apps/LedgerUITests/TabsAdversarial.swift` (sanctioned edit) | — | audit fails on Program (F11-S14-5) and F12-S1-1 |

None of the CI chore's files was touched (`ProgramViewsRoomAdversarialTests`, `DayEditorViewsRoomAdversarialTests`,
`NameFieldLineTests`, `PixelBuffer`).

### Commands and exit statuses

| Command | Exit |
|---|---|
| host `swift test --filter BestSetsAdversarialTests` | 0 (6 tests) |
| host, same, with the SQL's `reps DESC` → `ASC` (mutant, restored) | 1 (3 tests fail) |
| host `swift test --filter LibraryStoreAdversarialTests` | 0 (5 tests) |
| sim, Nightly, `main` worktree, `TabsAdversarial` accent + audit (`main-tabs`) | 65: both fail, as above |
| sim, Nightly, probe of the Library audit with frames and pictures (`branch-probe`) | 0 (probe only records) |
| sim, PR, `SearchFieldLineAdversarialTests` as built (`field-asis`) | 65: fails at `.accessibility5` |
| sim, PR, same with `SearchField` on `ledgerFieldFont(.body)` (`field-fixed`, restored) | 0 |
| `scripts/check.sh --lint-only` | 0 |
| sim, PR, `TEST_RUNNER_LEDGER_SWEEP=pr`, `FeatureLibraryTests` + `BestSetsAdversarialTests` + `SearchFieldLineAdversarialTests` (`final-pr`) | 65: 71 pass, the one F12-S1-1 test fails |
| sim, Nightly, `LibraryAuditAdversarial` + `TabsAdversarial` + `Library` (`final-ui`) | 65: 7 pass; fail: the two audits (F12-S1-1, and Program's F11-S14-5) and the accent test (environment) |

## Slice S2 — round 1 (G2 tester, 2026-10-24)

**Outcome: three real defects, none of them a wrong number. F12-S2-3 (Minor, latent) is a stale open history
after a workout that is not the newest. F12-S2-1 (Minor) is "+0 lb" read as a gain. F12-S2-2 (Minor) is "1
sessions". All three are open for G1. Two low findings record behaviour as built.** The fold held under attack
against `PersonalRecords` (200 random histories) and against GRDB's `e1RMByWeek`. The second check covered 21
zone, week-start and change-of-clocks cases, which the implementer's differential (UTC, Monday) did not reach. The
store's failure, overtaken-read, rename and week-start paths held, and so did the N14 dates.

Slice under test: `feat/F12-s2-history` at `c1c6f03` (3 commits on `main` @ `d92cc15`). Scratch
`scratchpad/f12s2-g2/`; every simulator command ran through the lock. An earlier, interrupted round had left five
untracked test files. They were reviewed, run, kept and finished here. The commit changes no product code. Three
product lines were changed for a while to prove tests (below), and each was put back.

### What was attacked, and what held

- **The fold against `PersonalRecords` (N9, N10).** The test generated 200 random histories with every set kind,
  kg beside lb, 1–15 reps and random deloads. Records were detected one workout at a time against the bests before
  it, as F05 stores them. In every history, PR is exactly the detected workouts, so a deload never reads "PR".
  "+Δ" is the exact step between top working sets, and the oldest entry has no step. The estimate and the best set
  are `PersonalRecords.Bests`' own. All pass.
- **Brzycki's edges (criterion 6).** One rep gives the weight. 12 reps count and 13 do not, so a lighter 12-rep
  set gives the estimate over a heavier 13-rep set. 40 reps give no estimate and no trap, and stay the best set.
  A zero load gives an estimate of 0, not none. In the presentation, 100×13 reads "—", "100" "×13", and the chart
  shows its message. A warm-up and a drop set heavier than the working set stay in the log only. All pass.
- **The weeks (N9, decision #15).** The weeks run unbroken across New Year from Monday, Sunday and Saturday. On New
  York's spring forward, the 167-hour week holds its own last minute. Santiago's skipped midnight opens its week at
  01:00. A calendar's own `firstWeekday` is ignored. W1's first instant is in the window and the instant before it
  is out. Older history only gives eight empty weeks while the stats are kept. **New:** GRDB's `e1RMByWeek` (with
  a program's `WeekCalendar`) was checked against the fold as the store calls it (`weekStart:calendar:`, weeks
  from the epoch). The sessions sat at the first and last minute of the 21 days around a change of clocks, in New
  York, Santiago, Lord Howe (a 30-minute change) and UTC, from Monday, Sunday and Saturday, with `now` on both
  sides of the change. They agree in all 21 cases. **Mutant:** with the fold's week start forced to Monday, 14 of
  the 21 cases fail (every Sunday and Saturday case). Restored.
- **Tags across units.** 100 lb after 45.359237 kg is "—", exactly. The step from 45 kg to 100 lb is exact. Two
  rows of one workout compare the heavier row. Two sessions that started together follow list order. All pass;
  F12-S2-1 was found here.
- **Store (N13, failed state).** All of these pass:
  - The newest workout deleted while the history is up leaves the screen.
  - A read that fails once shows the failed state, and the next change of units brings the history back.
  - A read overtaken by a finished workout ends on the history that holds it.
  - A change of the first day of the week moves the weeks.
  - The exercise taken away shows the failed state, and the history returns when it is given back.

  F12-S2-3 was found here.
- **Dates (N14).** These pass:
  - In New York at 10:00 on Jan 1, a Dec 31 22:00 session (already 2027 in UTC) reads "Dec 31, 2026" and a 00:30
    session reads "Jan 1".
  - In Tokyo, a Jan 1 07:00 session (Dec 31 in UTC) reads "Jan 1".
  - fr_FR, de_DE and en_GB write the date in their own form.

  **Mutant:** with the format style on GMT, both New Year tests fail. Restored.
- **The running app (DoD VoiceOver pass, criterion 11).** The Nightly UI test saves a sample workout, then opens
  Library → RECENTLY LOGGED → the history. It logs the accessibility tree in reading order and keeps it, with
  pictures, in the result bundle. At the default size the order is heading, three stats ("202, 1RM est", "180×5,
  best set", "1, sessions"), the chart as one element "Estimated 1RM by week", then SESSION LOG and the session as
  one button "Aug 17", value "—, 180×5". At Accessibility XXXL the stats stack, there are no bars, and the weeks
  are a list "W1, —" … "W8, 202". Tapping the session selects the History tab. All three pass. The first session
  reads "—", a baseline, as criterion 7 says.

### Findings

**F12-S2-1 — Minor. A step up smaller than the shown precision reads "+0 lb" (or "+0 kg"), a gain of nothing.**
- `ExerciseHistory` tags `.heavier(top − earlier)` from exact weights. The presentation writes the step with
  `Weight.formatted(in:)`, which rounds to one decimal. A step under 0.05 of the shown unit therefore reads "+0".
  A change of units makes such steps easily:
  - 100 kg, then 220.5 lb, is +0.04 lb. Both sessions read "220.5×5" in the log, and the later one says "+0 lb".
  - 225 lb, then 102.1 kg, reads "+0 kg".
- Failing test: `FeatureLibraryTests/ExerciseHistoryAdversarialTests.swift`,
  `tag_tinyStepAcrossUnits_neverReadsPlusZero` (both units).
- Fix for G1, in `ExerciseHistoryPresentation.entry`: a step that formats as zero in the shown unit reads "—".
  The other option is to compare the shown values, as the chart's change does (Q7). It needs a ruling on which.

**F12-S2-2 — Minor. The sessions stat reads "1 sessions" (VoiceOver "1, sessions").**
- The DoD says "Every string above in the String Catalog with plurals (sessions, exercises)". `sessionsCaption`
  is a fixed "sessions", not a counted key. The Library's own row uses "%lld sessions" with `forCountedText`.
  The running app shows the defect too: the default-size dump reads "1, sessions".
- Failing test: `ExerciseHistoryAdversarialTests.sessionsCaption_oneSession_isSingular`.
- Fix for G1: make the caption a plural key ("session" / "sessions") looked up with `locale.forCountedText`, and
  hand it the count.

**F12-S2-3 — Minor (latent; Major once F13's delete and edit or the watch's sync land). An open history misses
any workout change that leaves the newest workout as it was.**
- The store reads again only when `observeRecent(limit: 1)` emits. That observation emits "for no other write"
  (`Repositories.swift:135`; GRDB `removeDuplicates`; the fakes do the same). So none of these changes reach an
  open history:
  - A workout finished that started before the newest, as a watch workout saved after a phone one would. Its log
    entry, best set and PR never appear.
  - A workout deleted that is not the newest. Its entry stays, routing to a workout that is gone, and the count
    and bests keep it.
  - An `updateSets` on an older workout.
- Today no production code deletes or edits an older workout, and one device cannot finish two overlapping
  workouts, so this is latent. N13 names "a finished workout" without saying "the newest".
- Failing tests:
  - `olderWorkoutFinished_whileShown_shows`: the log stays at 3 entries and the best set at "195".
  - `olderWorkoutDeleted_whileShown_leaves`: the log stays at 3 entries and the count at "3".

  Each waits 2 s, bounded (`eventually(within:)`), so it fails fast.
- **Mutant:** with the store on `observeRecent(limit: Int.max)`, both tests pass. Restored. That is one possible
  fix, but it re-reads the whole history on every write. A narrower one is an observation of the exercise's
  sessions, or of a stats change counter. It needs a ruling. The Library's S1 store follows
  `observeRecent(limit: followedWorkouts)` and shares this class of miss for older workouts.

**F12-S2-4 — low, note. The chart speaks only its name. Its week values are read only through the chart
descriptor (the "Describe chart" rotor and the audio graph).**
- At the default size the bars are one element, labelled "Estimated 1RM by week", with no value. The descriptor's
  `summary` is nil. The dump confirms the element. The XCUI tree cannot show the descriptor (R3), and this round
  did not listen to VoiceOver by ear, so the DoD's "VoiceOver reading week values" is still unconfirmed.
- Option: give the chart an `accessibilityValue` or a descriptor summary, such as "W8 202 pounds, up 28 over 8
  weeks". That would be new wording for Pete.

**F12-S2-5 — low, note. "+Δ" compares only with the session just before. When that session has no working set
(added sets or warm-ups only), the next session reads "—", even if it is heavier than the session before that.**
- Pinned as built: `LedgerDomainTests/Adversarial/ExerciseHistoryAdversarialTests.swift`,
  `tags_predecessorWithoutWorkingSets_isSame` (passes). N10 says "the previous session's", which this matches
  literally.
- Option: compare with the latest earlier session that has a working set. The change belongs in
  `ExerciseHistory.entry`.

### Tests added

| File | Tests | Result |
|---|---|---|
| `LedgerDomainTests/Adversarial/ExerciseHistoryAdversarialTests.swift` | 15 (weeks over 3 and 4 arguments) | pass |
| `LedgerDomainTests/Adversarial/ExerciseHistoryPropertyAdversarialTests.swift` | 1 × 200 seeds | pass |
| `LedgerPersistenceTests/Adversarial/ExerciseHistoryWeeksAdversarialTests.swift` | 1 × 21 cases | pass (1.2 s on the simulator) |
| `FeatureLibraryTests/ExerciseHistoryAdversarialTests.swift` (+ `Support/HistoryAdversarialDoubles.swift`) | 15 | **4 fail: F12-S2-1, -2, -3 (×2)**; 11 pass |
| `Apps/LedgerUITests/HistoryVoiceOverAdversarial.swift` (Nightly) | 3 | pass |

No hosted view sweep was added, so the PR sweep gains nothing through `TestSweep`. The new PR-plan time is about
1.5 s of non-hosted tests, plus the two bounded F12-S2-3 waits (2 × 2.4 s) while they fail.

### Commands and exit statuses

| Command | Exit |
|---|---|
| host `swift test --filter 'Adversarial F12 S2\|ExerciseHistoryAdversarialTests'` (the interrupted round's files, as left) | 1: F12-S2-1 and -2 fail; the rest pass |
| host, same, plus the new store, date and reps tests (before the waits were bounded) | 1: the F12-S2-3 tests hit the 60 s limit |
| host `swift test --filter FeatureLibraryTests.ExerciseHistoryAdversarialTests` (bounded waits) | 1: 4 tests fail (7 issues), 11 pass |
| host, same, with the store on `observeRecent(limit: Int.max)` (mutant, restored) | 0: both F12-S2-3 tests pass |
| host `…/date_` with the date format on `.gmt` (mutant, restored) | 1: both New Year tests fail |
| host `swift test --filter ExerciseHistoryWeeksAdversarialTests` | 0 (21 cases) |
| host, same, with the fold's week start forced to `.monday` (mutant, restored) | 1: 14 of 21 cases fail |
| sim `xcodebuild build-for-testing`, Nightly plan, iPhone 17 / iOS 27.0 | 0 |
| sim, Nightly, `-only-testing:LedgerUITests/HistoryVoiceOverAdversarial` | 0 (3 tests) |
| sim, PR plan, `TEST_RUNNER_LEDGER_SWEEP=pr`, the three package adversarial suites | 65: the 4 tests above fail; the 28 others pass |
| `scripts/check.sh --lint-only` | 0 |
| host, final: the two adversarial suite names | 1: domain 16 and persistence 1 pass; FeatureLibrary 4 fail as above |

**Not tested.**
- VoiceOver by ear (F12-S2-4).
- Rename from S3: the screen does not exist yet; the store's rename path is the implementer's test.
- Clipping and orange at sizes beyond what the implementer's sweeps cover. No hosted sweep was added, so the CI
  budget stays as it is.
- The N11 budgets, which are the implementer's Nightly performance suite and were not re-run.

### Orchestrator's ruling (S2 round 1)

1. **F12-S2-1 ("+0 lb"): fix.** The tag compares what the screen shows. When the step, rounded to the display
   precision in the current unit, is not positive, the tag is "—", as for a drop. The PR tag is unaffected. G2's
   `tag_tinyStepAcrossUnits_neverReadsPlusZero` is to pass as written.
2. **F12-S2-2 ("1 sessions"): fix.** The caption becomes a plural string-catalog key read through the shared
   `Locale.forCountedText(in:)` helper, as Today and Workout do. The VoiceOver label is to read naturally too.
3. **F12-S2-3 (older workout changes missed): fix.** The history follows its own data, not the newest workout:
   an observed form of the sessions query, `observeExerciseSessions(exerciseID:) -> AsyncStream<[ExerciseSession]>`
   beside `exerciseSessions` (GRDB `ValueObservation` with `removeDuplicates()`, the in-memory store and the
   Unimplemented stub to match), with a contract clause: it emits on finishing, deleting or editing an older
   workout of that exercise, and not for another exercise's change. The history store follows it instead of
   `observeRecent(limit: 1)`. Not `observeRecent(limit: Int.max)`.
   - **Follow-up F12-S2-6 (for S3 or F13), out of scope here.** The S1 Library store (`LibraryStore`) follows
     `observeRecent(limit: followedWorkouts)` and shares the class of miss: a change to a workout older than the
     followed ones does not reach RECENTLY LOGGED, the session counts or the best sets. `LibraryStore` is not
     changed in S2.
4. **F12-S2-4 (the chart speaks only its name): fix.** The chart descriptor gets a summary (the change line,
   "Up 10 lb over 8 weeks", or the no-data message), and the chart element an accessibility value with the same
   summary.
5. **F12-S2-5 ("+Δ" against the session just before): keep as built.** The spec says "the previous session"; the
   passing pin stays. A candidate for Pete: compare with the latest earlier session that has a working set. No code.

## S3 — G2 findings (2026-10-26)

Branch `feat/F12-s3-create` at `bf65baf` (slice `526575a`…`bf65baf` over the spec commit `235e845`). Read: the brief's
S3, the S3 amendments (N19, N20), §3 Q2/Q4/Q5 as A, and the implementer's "S3 — as built". Ruling taken as given:
N19's "counts" is `PersonalRecords.countsTowardBests` (working or added) for both sides of "+Δ".

### What was attacked, and what held

- **N15 name rules.** Trimming, 2–40 graphemes (emoji ZWJ sequences, flags, skin tones, combining marks, Hangul,
  Arabic), every `Cc` (C0, DEL, C1, U+0085), uniqueness by `ExerciseSearch.key` (case, diacritics, width, NFD vs
  NFC), the edited exercise left out, the rules' order, the primary muscle among the secondaries for every muscle.
  All hold as written. A zero-width space U+200B at the ends is trimmed (Foundation counts it a blank). What does
  not hold is the class of characters the rule does not name: S3-1, S3-2, S3-3.
- **Deleted exercises.** No API deletes an exercise (`ExerciseRepository` has none), so "live" is every exercise;
  nothing to attack.
- **N16 saving.** Double tap, failure then retry, cancellation before the write: the implementer's tests cover them
  and they pass. A cancellation during the write is GRDB's: its async write throws `CancellationError` and rolls
  back, so the store's "cancelled → nothing" reading is right on the device. Edit of an already logged exercise
  (Q5 A) pinned: the Library follows the id (new name, new equipment, same 2 sessions and PR), the stored workouts
  keep the name they were logged under. The one gap is an edit of a row the sheet never wrote (S3-5).
- **N17/Q4.** Short name is the name, start load 0 in both units, no alternatives, also after an edit (pinned).
- **N18.** Rows' actions zip with the rows; a second tap and "Done" after a row change nothing; before the receipt a
  row does nothing; a swapped exercise routes to the exercise done (`exerciseID`, not `originalExerciseID`). The
  router appends to Today's path: two workouts in a row whose receipts each open a history leave two histories on
  Today's stack, which is "one step deeper" each time and is accepted.
- **N19.** A differential oracle written apart from the code (quadratic, literal) over 200 random histories the S2
  generator never makes: undone sets, sessions with no set, runs of warm-up-only or drop-only sessions, records at
  random, equal masses written in two units (100 lb ≡ 45.359237 kg). It agrees everywhere. Mutant check: with
  `earlier = top` (a session without counted sets resets the comparison) it fails 64 of 200 cases.
- **N20.** A GRDB-against-fakes differential over `HistoryScript` (materialise new and older workouts, edit sets,
  delete, refused calls), 25 seeds × limits 1, 2 and 5, 14 steps each: after every step both observations reach
  exactly what their own three reads return, the two reads agree, and neither ever emits a value equal to the one
  before. 24 of 25 scripts show stats (the guard asks for ¾). Mutant check: the observation reading
  `recentLimit + 1` fails it (37 issues). Observation failure behaviour (left until the next run) is the
  implementer's open question 3 and is not re-filed.
- **Strings.** All 22 new keys are in the catalog with comments; none stale; no plural forms are new; no hard-coded
  user-facing text in the new views. "Core" serving both a muscle and a pattern is one key by design (commented).
- **Accessibility.** Selected and toggle traits are pinned by the implementer's tree tests and hold. Gaps: S3-6
  (the problem is never announced), S3-7 (chip identity). G1's truncated name field at accessibility sizes is
  already open question 1 and is not re-filed.

### Findings

**S3-1 (minor). A name of invisible characters only is saved.**
- Repro: type or paste U+2060 U+2060 (word joiners), U+FEFF U+FEFF, U+200E U+200F, or U+202E U+202C; Save. The
  draft builds an exercise whose name draws as nothing; the Library lists an empty row. N15's "Enter a name." is
  the intent for a name with nothing to read.
- Cause: `trimmingCharacters(in: .whitespacesAndNewlines)` does not take format characters (`Cf`, other than
  U+200B), and the `Cc` check does not see them.
- Test: `LedgerDomainTests/Adversarial/CustomExerciseDraftAdversarialTests.swift`
  `invisibleOnly_isBlank` (4 arguments, `withKnownIssue`).
- Fix: before the rules, drop `Cf` scalars (or Unicode's default-ignorable code points) from the name, or refuse
  them as `controlCharacter`; then the blank check catches an all-invisible name.

**S3-2 (minor). A name that draws exactly as another exercise's passes the duplicate rule.**
- Repro, with "Bench Press" live: "\u{FEFF}Bench Press", "Bench Press\u{2060}", "Bench\u{200B} Press",
  "Bench\u{00A0}Press" (a no-break space, as text copied from a web page has), "Bench  Press" (two spaces),
  "Bench\u{2009}Press" (thin space), and "\u{202E}sserP hcneB" (a right-to-left override that draws "Bench Press").
  Each is saved; the Library then shows two identical names.
- Cause: `ExerciseSearch.key` folds case, diacritics and width only; it keeps format characters and every kind and
  run of space. Search is affected the same way: "bench press" does not find "Bench\u{00A0}Press".
- Test: `CustomExerciseDraftAdversarialTests.drawsAsAnother_isDuplicate` (6 arguments) and
  `directionOverride_isDuplicate`, both `withKnownIssue`.
- Fix: in the draft, store a normalised name (format characters dropped as in S3-1, every run of `Zs` collapsed to
  one U+0020); optionally fold the same in `ExerciseSearch.key` so search and the rule agree. Decision #23's key is
  F11's too, so a key change wants the orchestrator's word.

**S3-3 (minor). A line or paragraph separator inside a name is saved.**
- Repro: "Bench\u{2028}Press" or "Bench\u{2029}Press"; Save. The name is stored with a line break, though the
  sheet's own copy says a line break is refused ("…a tab, a line break or another control character…"). One-line
  rows then draw two lines or cut.
- Cause: U+2028/U+2029 are `Zl`/`Zp`, not `Cc`. "\n", "\r\n" and U+0085 are refused (pinned).
- Test: `CustomExerciseDraftAdversarialTests.lineSeparators_areRefused` (2 of 5 arguments under `withKnownIssue`;
  the `Cc` ones pass).
- Fix: refuse `Zl` and `Zp` with `controlCharacter` (or `CharacterSet.newlines` anywhere in the trimmed name).

**S3-4 (nit). 2–40 bounds graphemes, not storage.**
- Repro: "a" + 1,000 × U+0301 + "b" + 1,000 × U+0308 is 2 characters and is saved: 2,002 scalars in the name and
  the short name, drawn as a tall smear over neighbouring rows.
- Test: `CustomExerciseDraftAdversarialTests.combiningMarks_areUnbounded` (passes; pins today's behaviour).
- Fix, if wanted: cap combining marks per grapheme (for example 4), or cap the UTF-8 length (for example 200 bytes).

**S3-5 (nit). An edit of a stored exercise whose secondary muscles hold its primary can never be saved.**
- Repro: a custom exercise stored with primary Chest and secondaries [Chest, Triceps] (no sheet writes this today,
  but a sync, an import or a later version can); "Edit"; change the name; Save → "Couldn't save the exercise. Try
  again.", every time. The sheet offers no Chest chip under Secondary muscles, so the lifter cannot see or clear it;
  only changing the primary muscle and back gets out.
- Test: `FeatureLibraryTests/CreateExerciseAdversarialTests.swift` `edit_primaryAmongStoredSecondaries_canBeSaved`
  (`withKnownIssue`).
- Fix: `CustomExerciseDraft.init(_ exercise:)` removes the primary from the secondaries, as `setPrimaryMuscle` does.

**S3-6 (minor, accessibility). The problem Save finds is never announced.**
- Repro: VoiceOver on, a blank name, focus on Save (pinned at the foot), double-tap. "Enter a name." appears under
  the name field, at the top of the scroll view, and nothing is spoken; with the fields scrolled (any accessibility
  size), the line is also off screen for a sighted lifter. Program and Onboarding announce their notices
  (`ProgramRoot`, `OnboardingRoot`: `AccessibilityNotification.Announcement`).
- Test: `CreateExerciseAdversarialTests.saveProblem_isAnnounced` (a source check, `withKnownIssue`).
- Fix: inject `announce` into `CreateExerciseSheet` as `ProgramRoot` does and post the name's or the foot's problem
  when it appears; scroll the name field into view (`ScrollViewReader`) for a name problem.

**S3-7 (nit, accessibility). Secondary-muscle chips are identified by place.**
- Repro: primary Chest: Shoulders is chip 1; choose primary Triceps: Shoulders is chip 2 and chip 1 is Back.
  `ForEach` identity follows the place, so a chip's view (its pressed state, its accessibility element) becomes
  another muscle when the primary changes.
- Test: `CreateExerciseAdversarialTests.secondaryChipIdentity_isTheMuscle` (`withKnownIssue`).
- Fix: identify chips by their value (`Chip.id` as the field plus the enum's raw value).

### Tests added

All failing tests are wrapped in Swift Testing's `withKnownIssue` (none `.disabled`), so the branch builds, the
suites pass, and each turns into a "known issue not recorded" failure the moment its fix lands.

| File | Tests | State |
|---|---|---|
| `LedgerKit/Tests/LedgerDomainTests/Adversarial/CustomExerciseDraftAdversarialTests.swift` | 12 (S3-1…S3-4 and 7 pins) | S3-1, S3-2, S3-3 known issues; S3-4 and pins pass |
| `LedgerKit/Tests/LedgerDomainTests/Adversarial/StepOracleAdversarialTests.swift` | 3 (N19 oracle × 200 seeds, 2 pins) | pass |
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/LibraryStatsObservationAdversarialTests.swift` | 1 (N20 differential, 25 seeds × 3 limits) | pass |
| `LedgerKit/Tests/FeatureLibraryTests/CreateExerciseAdversarialTests.swift` | 6 (S3-5, S3-6, S3-7, 3 pins incl. Q5 A) | S3-5, S3-6, S3-7 known issues; pins pass |

### Commands and exit statuses

| Command | Result |
|---|---|
| host `swift test --filter "LedgerDomainTests.(CustomExerciseDraftAdversarialTests\|…StepOracle…)"`, first run | 1: 3 cases' "known issue not recorded" (U+200B is trimmed); cases moved to pins |
| host `swift test --filter LedgerDomainTests.CustomExerciseDraftAdversarialTests` | 0: 12 tests, 13 known issues |
| host `swift test --filter FeatureLibraryTests.CreateExerciseAdversarialTests` | 0: 6 tests, 4 known issues |
| host `swift test --filter LedgerPersistenceTests.LibraryStatsObservationAdversarialTests` | 0: 1.3 s |
| host, N19 oracle with `earlier = top` (mutant, restored by copy) | 1: 64 of 200 cases fail |
| host, N20 differential with the observation on `recentLimit + 1` (mutant, restored by copy) | 1: 37 issues |
| host, final: the four new suites plus `CustomExerciseDraft`, `CreateExerciseStoreTests`, `ExerciseHistoryAdversarialTests`, `LibraryStoreTests` | 0: 1 + 42 + 42 tests, 13 + 4 known issues |
| `swiftformat --lint` and `swiftlint lint --strict` on the four files | 0 |

**Not run.** No simulator run: the four suites are host-pure (no hosting), and the orchestrator runs the gate.
VoiceOver by ear. The Nightly UI tests.
