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
  line). `searchField_edited_drawsItsTailsWhole` passes, unedited. **The audit's "Text clipped" is not fixed:**
  Nightly `LibraryAuditAdversarial` still reports it on the field, at the default size, at Accessibility L and at
  Accessibility XXXL. That part stays open; see the implementation notes' "Round 2".
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
