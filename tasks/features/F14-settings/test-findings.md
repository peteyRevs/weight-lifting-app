# F14 — test findings

## S1a — G2 findings (2026-10-28)

**Outcome: no Critical or Major findings. Three Medium findings and four Low ones.** The save queue keeps its main
promises: saves run one at a time, the last value wins, a change shows at once, and a random script always ends on
the lifter's value. Its gaps are at the edges, where an observation's echo arrives late or the root's task
restarts. One Medium finding is a gap in the spec, about installs made before F14. Every finding has a test, wrapped in
`withKnownIssue`. No product code was changed in the commit; one line was changed for a moment to prove the property
test fails when it should (below), then put back.

The slice under test: `feat/F14-settings` at `712f293` (`bd2d26c..HEAD`: `a374175`, `0d0508d`, notes `712f293`).
S1b (the views) is not on the branch and was not tested. Everything ran on the host (`swift test`); S1a has no
hosted suite, so no simulator command was run.

### What was attacked, and what held

- **R7 against an oracle.** `SettingsSavePropertyAdversarialTests` runs 40 seeded scripts of 40 steps over
  `ScriptedSettings`, a repository whose every save waits until the test commits or refuses it. The steps send random
  changes to all six fields (some of them no-ops) and commit or refuse held saves in any order, settling after each.
  After every step:
  - the screen shows the oracle's value at once;
  - a held save is of the whole latest value;
  - never more than one save runs.

  At the end the row, the screen and the oracle agree, nothing is pending, and there are no more saves than changes.
  All 40 seeds pass. **Mutant:** with `receive(_:)`'s `if value == pending` changed to `if true` (so any echo clears
  `pending`), the suite fails with 68 issues. The line was then restored, and `git diff -- Sources` is empty.
- **R7 over real GRDB.** `SettingsReachAdversarialTests.grdb_burstsConverge` (6 seeds × 60 changes, random yields
  between them, `GRDBSettingsRepository` on an in-memory queue). The run always converges: the row equals the
  lifter's last value and nothing is left pending. Along the way the screen sometimes leaves the lifter's value: see
  F14-S1-3.
- **Pins that pass.**
  - A failure after a success leaves the row at the success.
  - A tap back to the stored value during a save writes the stored value back.
  - The store's own suites (folding, the echo during a held save, failure and revert, N2 and re-following, a change
    before the run) were re-run and pass.
- **seedIfAbsent and the launch.**
  - On GRDB, a seed racing a save never beats the save (20 rounds).
  - Two seeds at once leave one whole row (20 rounds).
  - A seed is observed once, and a second seed is not observed.
  - The implementer's contract covers unreadable rows (a later version, invalid JSON, non-UTF-8), the double launch,
    the watch's nil, and a seed that fails.
  - `WatchComposition` builds its `DatabaseLaunch` without `regionalSettings`, so the watch seeds nothing.
  - Found F14-S1-5.
- **Regional defaults (N3), as Foundation reports CLDR.** Each region gives:

  | Region | Units | Week starts |
  |---|---|---|
  | en_US | lb | Sunday |
  | en_GB (UK system) | kg | Monday |
  | de_DE, fr_FR | kg | Monday |
  | ja_JP | kg | Sunday |
  | ar_SA | kg | Sunday |
  | fa_IR | kg | Saturday |
  | en_US@measure=metric | kg | Sunday |
  | en_US@fw=mon | lb | Monday |
  | en_001 | kg | Monday |
  | en_LR | lb | Monday |
  | my_MM | kg | Sunday |

  - **Saudi Arabia starts weeks on Sunday, not Saturday.** CLDR says Sunday, under both the Gregorian and the Umm
    al-Qura calendars. The Saturday case is Iran (`fa_IR`, Persian calendar). A brief that expects Saturday for SA is
    mistaken.
  - Every `firstWeekday` from 1 to 7 maps to its `Weekday`, and the week start follows the calendar even when the
    locale disagrees.
  - A locale with no region (`en`, `""`, `und`) reports US units and so seeds pounds. A device always has a region,
    so this is pinned, not a finding.
- **Cross-store criteria.**
  - Criterion 2 is restated in the plan as "a saved rest is what `ExercisePickerStore` gives a **new** slot". After a
    45 s rest is saved, the new slot gets 45 s and every slot already in the program keeps its rest, which pins the
    other half.
  - Criterion 7 (Today's strip moves and the block's weeks don't) is covered by `SettingsReachTests`.
    `ProgramStore+Sources` uses Monday on purpose (C10).
- **Copy and presentation.**
  - The About line's eight fallbacks are covered by the implementer.
  - With stray spaces in the values, the line keeps them: F14-S1-7.
  - The seven weekdays are distinct, named, and listed from the calendar's first day under the Persian, Umm al-Qura,
    Hebrew and Japanese calendars, and Gregorian ar_AE.
  - The rest in words follows the language ("1 Minute … 30 Sekunden").
  - There are no plural keys in S1a (`%lld` doesn't appear), so there are no plural rules to check.
  - The catalog has 26 keys, none holding the product's name. `Ledger` appears only in two doc comments. The N6
    source test checks literals only, which is correct.
  - The rest's drawn value ("1:30", "45s", "2 min") is the Domain's English `RestDuration.label`, as the plan says.
    It is unlocalized, but that predates F14.
- **The UI-test region.** `-LEDGER_UITEST` installs now seed the simulator's region. Under en_US, that means pounds and
  Sunday weeks. No UI test reads the strip's first day.
  - Programs come from `Fixtures.seedProgram()`, whose start date is fixed, so "WEEK 1" and "week 5" don't move.
  - The onboarding tests assert "…, pounds." in their sentence, so they now depend on the simulator being in a
    US-measure region: F14-S1-6.

### Findings

**F14-S1-1 — Low (spec question). A change made while a save runs is dropped untried when that save fails.**
- **Repro:**
  1. Tap KG. The save is held.
  2. Tap Plate math off while it is held.
  3. The KG save fails.

  `savePending` sets `pending = nil` and shows `stored`. The Plate math change, which was never attempted, goes with
  it: there is no second save, and the line reads "Couldn't save **that** change." N1 says "reverts **the control**".
  Whether the later control should revert too is not settled.
- **Test:** `SettingsSaveQueueAdversarialTests.changeDuringAFailingSave_isTried` (known issue).
- **Suggested fix (after a ruling):** remember the value being saved. On failure, if `pending` differs from it, keep
  the fields changed since the save began, applied on top of `stored`, and save that next. Otherwise drop `pending`
  as now.

**F14-S1-2 — Low. A failure reverts to the observation's last value, which can be older than the row; the next change
then undoes a committed change.**
- **Repro:**
  1. Tap KG, and the save commits. GRDB's `.task`-scheduled echo has not arrived yet.
  2. A Friday change, folded into the next save, fails.
  3. The screen draws `stored`, which is still lb, although the row holds kg.
  4. A Plate math tap now saves lb + Plate math, undoing the committed KG.
- **Test:** `SettingsSaveQueueAdversarialTests.failure_beforeTheEarlierEcho_revertsToTheRow` (two known issues).
- **Suggested fix:** on a successful save, take the written value as the stored one (`stored = wanted`), or revert
  to `written ?? stored` on failure.

**F14-S1-3 — Medium. N1's "doesn't flicker back" fails when an earlier save's echo arrives after `pending` was
cleared. It reproduces intermittently over real GRDB.**
- **Repro (deterministic, held echoes):**
  1. Tap KG, and the save commits (its echo is held).
  2. Tap LB, and the save commits.
  3. `savePending` sees `pending == stored` (lb, the old echo) and clears `pending` at once: "a save that changed
     nothing stored".
  4. KG's late echo arrives and is drawn. The control shows KG until LB's echo follows.
- **Over GRDB:** `grdb_burstsConverge` saw the screen leave the lifter's value (pending nil, shown lb, stored lb,
  lifter kg) in about 3 of 20 runs of 6 × 60 changes. The run always converged.
- **Tests:**
  - `SettingsSaveQueueAdversarialTests.lateEcho_afterTapBack_doesNotFlicker` (known issue).
  - `SettingsReachAdversarialTests.grdb_burstsConverge` (`withKnownIssue(isIntermittent: true)`).
- **Suggested fix:** keep a FIFO of committed values that have not been echoed yet. An echo that matches an earlier
  entry drops the entries up to it and updates `stored`, but the screen keeps showing the lifter's latest value while
  entries remain. Clear `pending` on the no-change path only when the FIFO is empty.

**F14-S1-4 — Medium (low likelihood, silent loss). A restarted run saves beside the old one, and the old run's end
switches off saving for the new one.**
- **Repro:** this is a `.task` restart on the same `@State` store, for example switching tabs away from Settings and
  back during a save.
  1. Run 1 is cancelled while its save is held. It cannot leave `savePending` until the save returns.
  2. Run 2 starts, finds `pending`, and starts a second save. Two saves now run at once (`mostAtOnce == 2`).
  3. When run 1 ends, it sets `saveMark` and `followMark` to nil, and those are run 2's.
  4. Every later change is drawn but never saved while the screen stays up. It is lost on the next launch.
- **Test:** `SettingsSaveQueueAdversarialTests.restartDuringASave_keepsSaving` (three known issues).
- **Suggested fix:** give each run a token, and have `run()` clear the marks only when they are still its own. Have
  `savePending` stop between saves when its task is cancelled. Serialize saves across runs, for example with an
  `isSaving` flag or a single saver the store owns, so a new run waits for the old run's save.

**F14-S1-5 — Medium (spec gap; needs a ruling). An install made before F14 is seeded as if new.**
- **What happens:** nothing saved settings before F14 (C1), so every existing install has no settings row and runs on
  `Settings.default`: pounds and Monday weeks. Its program's block copied those values at onboarding (C2). The first
  launch after the update finds no row and seeds the region's settings:
  - a lifter in Germany switches to kilograms, unasked, while the active block was built in pounds (Q1's conversion
    is S2's);
  - a US lifter's Today strip and "this week" switch to Sunday.

  N3 is built as written ("writes it only when there is no row"), but decision #15 and the commit say "a new
  install's first launch".
- **Repro:**
  1. Launch with `regionalSettings: nil`, which is a pre-F14 launch, and save the seed program.
  2. Relaunch the same file with the regional kg/Sunday settings.
  3. `launch.settings` is kg/Sunday.
- **Test:** `SettingsSeedAdversarialTests.installBeforeF14_keepsItsSettings` (LedgerPersistenceTests, known issue).
- **Suggested fix:** add a migration that writes `Settings.default` for a database that already has a `device` row and
  no settings row. It runs once, on upgrade, so a pre-F14 install keeps what it ran on. Alternatively, seed only when
  `DatabaseLaunch` has just created the device row. Either way it needs Pete's or the orchestrator's ruling.
  TestFlight installs are the affected population.

**F14-S1-6 — Low (test determinism). UI tests now depend on the simulator's region.** `-LEDGER_UITEST` launches
seed `.regional(.autoupdatingCurrent, …)`. `Onboarding.swift` and `OnboardingAdversarial*.swift` assert "…, pounds.
Editable any time.", and the nightly strip and "this week" now count from the simulator's first weekday. A runner
in en_GB, or with a metric preference, would fail them.
- **Test:** none on the host. This is recorded from the sources (`Apps/LedgerUITests/Onboarding.swift:39, 169`;
  `OnboardingAdversarial.swift:95, 138`; `OnboardingAdversarial+Tables.swift:43`).
- **Suggested fix:** pass `-AppleLocale en_US -AppleLanguages (en)` in the UI tests' launch helpers, or have
  `Environment.live` use a fixed region (en_US) when `-LEDGER_UITEST` is set.

**F14-S1-7 — Low (cosmetic). The About line keeps the spaces around a value.** `present(_:)` uses trimming only to
test for blank, and returns the untrimmed value. Name `"App "`, version `" 1.2.3"` and build `"45\n"` draw as
`"App   1.2.3 · build 45\n"`.
- **Test:** `SettingsPresentationAdversarialTests.about_trimsItsValues` (known issue).
- **Suggested fix:** return the trimmed text from `present(_:)`.

### Tests added

- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/ScriptedSettingsAdversarialSupport.swift`: `ScriptedSettings`
  (held saves, commit or refuse, held echoes, at-once count) and `ScriptedSettingsScene`.
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/SettingsSaveQueueAdversarialTests.swift`: 2 pins, plus
  F14-S1-1 to F14-S1-4.
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/SettingsSavePropertyAdversarialTests.swift`: the oracle property
  test, 40 seeds.
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/SettingsPresentationAdversarialTests.swift`: weekdays under five
  calendars, the rest in words, and F14-S1-7.
- `LedgerKit/Tests/LedgerDomainTests/Adversarial/SettingsRegionalAdversarialTests.swift`: the region table, every
  first weekday, the calendar over the locale, and no region.
- `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/SettingsSeedAdversarialTests.swift`: seed and save races, two
  seeds, observation, and F14-S1-5.
- `LedgerKit/Tests/LedgerAppKitTests/Adversarial/SettingsReachAdversarialTests.swift`: criterion 2's existing slots,
  and R7 over GRDB (F14-S1-3, intermittent).

### Runs (host, `LedgerKit/`)

- `swift build --build-tests`: clean.
- `swift test --skip-build --filter FeatureSettingsTests`: 38 tests in 7 suites passed, with 9 known issues.
- `swift test --skip-build --filter "LedgerAppKitTests|LedgerPersistenceTests|LedgerDomainTests"`:
  - persistence: 582 tests passed, with 3 known issues;
  - domain: 1,417 tests passed;
  - AppKit: 332 tests passed, with 1 known issue.
- `mise exec -- swiftformat --lint` and `mise exec -- swiftlint lint --strict` on the seven new files: clean.

## S1b

G2, adversarial tester, 2026-10-29. Branch `feat/F14-settings-screen` at `d02995b`. No product code was changed.

### What was attacked, and what held

- **VoiceOver.**
  - The pinned tree held with German, Finnish, Tamil and Arabic words: one stop per row, 14 stops in the
    save-failed state.
  - The units' group held. Walking up UIKit's tree from "pounds" finds a container labelled "Units" whose
    type is a semantic group, so VoiceOver can speak it. The design suite left this to a manual DoD check;
    it is now pinned.
  - A Persian week's Saturday is the menu's spoken value, with the days listed from Saturday.
  - `SegmentedChoice` disabled: every option reads as dimmed, and activating one chooses nothing.
- **Dynamic Type and right to left.** Nothing fell outside the page, had no size or overlapped another stop:
  - German, Finnish and Tamil (whose Thursday, "வியாழக்கிழமை", is the longest weekday name) at xSmall,
    large, xxxLarge, accessibility3 and accessibility5;
  - Arabic, right to left, at the same sizes, with LB on the right and the stops in reading order.

  The gallery's three-option `SegmentedChoice` ("Left", "Both", "Right") fits inside the page's margins up to
  accessibility5. Mirrored right to left, each option is still a 44 pt target and keeps the hint.
- **Reduce Motion.** Settings' only animation is `LedgerToggleStyle`'s, which drops it under Reduce Motion
  (`withAnimation(reduceMotion ? nil : …)`, covered by `LedgerToggleStyleTests`). `SegmentedChoice` and the menu
  don't animate. No new test.
- **The root.**
  - Loading title: the root's title before the settings are read stands exactly where the page's title will,
    at every size, so the screen doesn't jump. A first attempt that hosted the two separately differed at
    accessibility sizes. That was the hosted reader centring a view taller than its window, not the screen;
    measured in one `ZStack`, they match.
  - Unreadable row: the root leaves the loading title for `Settings.default`, shows no "Couldn't save" line,
    and a change saves over the row.
  - Failed save: the switch goes back, and "Couldn't save that change." is VoiceOver's second stop. But see
    F14-S1b-2.
  - Rapid toggling: each of the three switches was double-tapped five times through VoiceOver while every
    save was held. Each ends flipped, on screen and as read. The taps fold into one save, never more than one
    runs at once, and the row ends on the lifter's values.
- **Reach.** Today, the Program builder and History ran over one set of stores while Settings took a burst of
  five changes across units and week start, made during its saves. All three converged without navigating:
  - Today: "kg moved", and the strip starts on Wednesday the 16th;
  - Program: the week starts on Wednesday;
  - History: the row's volume is in kg.

  The test was stable over 15 host runs.
- **Routes.**
  - Diagnostics, resolved from Settings on Today's stack while History holds a workout, raises the sheet each
    time. It moves no tab and no stack.
  - Release: `swift build -c release --target LedgerAppKit` builds cleanly, with no warning in
    `Routes+Settings.swift`, `SettingsRoute.swift`, `AppTabs` or `MainRoot`. `SettingsRoute` has no case there,
    and `resolve`'s switch is empty.
- **`AppAbout(bundle:)`**, from real bundles written to disk:
  - Every key present: the display name beats `CFBundleName`.
  - Display name missing: `CFBundleName` is used.
  - No keys: "Version unknown".
  - A number where a string belongs (`CFBundleVersion` as an integer): no value, and no crash.

  But see F14-S1b-1.

### Findings

**F14-S1b-1 — Minor. A blank `CFBundleDisplayName` hides `CFBundleName`, and the About line loses the app's name.**
- **Steps to reproduce:**
  1. Give the bundle `CFBundleDisplayName` = "" (or spaces), `CFBundleName` = "Internal",
     `CFBundleShortVersionString` = "0.15.0" and `CFBundleVersion` = "1".
  2. Read `AppAbout(bundle:)`.
- **Expected:** `name` is "Internal", and the line reads "Internal 0.15.0 · build 1". The doc says "The name is
  `CFBundleDisplayName`, else `CFBundleName`", and the presentation already treats blank as absent (F14-S1-7).
- **Actual:** `name` is "" (or the spaces). `value(…) ?? value(…)` only falls back on nil. The presentation then
  trims the blank away, and the line reads "Version 0.15.0 · build 1".
- **How it can happen:** the app sets the key from `$(PRODUCT_DISPLAY_NAME)` (`Config/Ledger.xcconfig`). That is
  blank in any configuration or target that doesn't include `Base.xcconfig`'s definition.
- **Test:** `SettingsScreenWiringAdversarialTests.about_blankDisplayName_fallsBackToTheBundleName`, for "", "   " and
  "\n" (known issue, 6 expectations).
- **Suggested fix:** in `AppAbout(bundle:)`, treat a value that is empty after trimming as nil before the `??`.

**F14-S1b-2 — Minor (accessibility). A failed save is never announced to VoiceOver.**
- **Steps to reproduce:**
  1. With VoiceOver on, double-tap a switch (Plate math).
  2. Let its save fail (`SettingsScene(failures: 1)`).
- **Expected:** VoiceOver says "Couldn't save that change." when the line appears. The app's other screens do this:
  `ProgramRoot` announces its notice when it appears or changes, and `CreateExerciseSheet` announces each problem,
  both through an injectable `announce` that posts `AccessibilityNotification.Announcement`.
- **Actual:** VoiceOver hears the switch turn on. Then the switch silently turns back off, and the line appears at
  the top of the page, away from the focus. Nothing is said. `SettingsRoot` has no `announce` and posts nothing.
  The line is in the tree (`failedSave_showsTheLine` holds), but only a lifter who swipes back to the top finds it.
- **Test:** `SettingsRootAdversarialTests.failedSave_isAnnounced` (known issue). With no injection point it can
  only read FeatureSettings' sources for an announcement. Once `SettingsRoot` takes `announce` as `ProgramRoot`
  does, the test should become behavioural.
- **Suggested fix:** give `SettingsRoot` an `announce` parameter, defaulting to
  `AccessibilityNotification.Announcement($0).post()`. Call it from `.onChange(of: store.model?.problem)` when the
  problem becomes non-nil.

### Tests added

- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/SettingsScreenAdversarialSupport.swift`:
  - `LiveSettingsPage`, the page over a running store;
  - `SettingsWords`, the German, Finnish, Arabic and Tamil words, and the model drawn in them.
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/SettingsScreenAdversarialTests.swift` (iOS):
  - long words at five sizes;
  - Arabic right to left;
  - the Persian week;
  - the units' semantic group.
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/SettingsRootAdversarialTests.swift` (iOS):
  - the loading title's place;
  - the unreadable row;
  - the failed save on screen;
  - F14-S1b-2;
  - five taps on each switch with saves held.
- `LedgerKit/Tests/LedgerDesignTests/Adversarial/SegmentedChoiceAdversarialTests.swift` (iOS):
  - three options up to accessibility5;
  - right to left;
  - disabled.
- `LedgerKit/Tests/LedgerAppKitTests/Adversarial/SettingsScreenWiringAdversarialTests.swift` (host and iOS):
  - `AppAbout(bundle:)` from bundles on disk, including F14-S1b-1;
  - Diagnostics beside History's stack;
  - the burst reaching Today, Program and History.

### Runs

- **Host (`LedgerKit/`):**
  - `swift build --build-tests`: clean.
  - `swift test --skip-build --filter "FeatureSettingsTests|SettingsScreenWiringAdversarialTests|SettingsReach"`:
    passes. The wiring suite records its 6 known issues (F14-S1b-1). The reach and wiring tests passed in 15 of
    15 repeated runs.
  - `swift build -c release --target LedgerAppKit`: clean. The release products were deleted afterwards.
- **Simulator (iPhone 17, iOS 27.0, PR plan, through the lock):** each run was `test-without-building` with
  `-only-testing`, after a `build-for-testing` in place in `.derivedData`.
  - FeatureSettingsTests (72 tests in 14 suites), plus `SegmentedChoiceAdversarialTests` and the wiring suite:
    green except the loading-title test's first form, which was then rewritten as described above.
  - `SettingsRootAdversarialTests` rerun on its own: 5 tests passed, with 1 known issue (F14-S1b-2).
- **Lint and format:** `swiftformat --lint` and `swiftlint lint --strict` are clean on the five new files.

## S2 — G2 round 1

G2, adversarial tester, 2026-11-10. Branch `feat/F14-s2-plates-export` at `f40dc55` (implementation `a472372`). No
product code was changed. The tests were written from the contract (S2, criteria 1, 3, 5, N11–N18, rulings A2/A4)
before the implementer's tests or notes were read. The contract's "135 lb becomes 62.5 kg" is taken as 60 kg
(61.23 kg on a 2.5 kg grid); see F14-S2-G2-3.

### What was attacked, and what held

- **`UnitSwitch.convert`** (hand-worked and seeded, 200 seeds per property):
  - lb → kg on a barbell: 45 → 20, 135 → 60, 225 → 102.5, 315 → 142.5, 405 → 182.5, 2.5 → 0, 3 → 2.5; kg → lb:
    20 → 45, 60 → 130, 62.5 → 140, 102.5 → 225. Kettlebells land on 2 kg and 5 lb bells (35 lb → 16 kg, 24 kg → 55 lb).
  - Steps: 18 cases over barbell, kettlebell, dumbbell and an exercise the map lacks; every step finer than a grid
    (1.25 lb, 0.5 kg, 1 kg) becomes exactly one default step. nil loads and steps stay nil. Ties go away from zero.
  - Properties: converting twice equals once (both units); every load on its grid within half a step, never
    negative; every step on its grid and at least one step; only loads and steps change, and the result decodes
    (every `Slot` range holds); lb → kg → lb drifts at most half a kg step plus half a lb step.
- **`switchUnits` on GRDB (A4):** a trigger refusing the slot update rolls the settings row back byte for byte, and
  the program rows too; with the trigger dropped, "Try again" converts both. A trigger refusing the settings write
  leaves the program. Same units: no program row is touched, even 46.25 lb. Only the active program converts; no
  program writes only the settings; a kettlebell exercise row's equipment is used. An unreadable settings row
  converts (as documented). GRDB and the in-memory stores agree through lb → kg → lb → kg → kg.
- **The store:** KG converts in one `switchUnits`; a failure shows the line and "Try again" with LB selected again,
  the row and the program untouched, and "Try again" converts. A change made while the switch is held is saved with
  `save`, converting once; flipping LB and back to KG during the held save writes no extra switch. A failed
  ordinary save offers no retry. Over an unreadable row, a rest change is not sent as a switch (the program's
  46.25 lb stays).
- **Plate editor:** the bar walks 45 → 0 in 18 steps and 0 → 100 in 40 (lb), 20 → 0 in 16 and 0 → 45 in 36 (kg),
  exactly; an off-grid bar (44 lb) steps to 42.5/45; one above the top (110 lb) cannot go up. N12's size lists per
  unit, heaviest first. Done leaves the other unit's stored inventory equal, and stores none for it when there was
  none; in kg the lb inventory is untouched. Every plate off shows the empty line; Reset gives `standard`; Cancel
  saves nothing; with Plate math off the row has no action, says "Turn on Plate math to edit", and `.editPlates`
  opens nothing. An off-list 7.5 lb plate is shown and kept by Done. But see F14-S2-G2-1.
- **CSV (`CSVExport`)**, read back by an RFC 4180 reader written apart from LedgerTestSupport's, over scalars:
  - header per unit, BOM = EF BB BF, an empty log is the header only, workouts and exercises with no sets write no
    row; eleven fields per row, CRLF throughout;
  - `set` restarts per exercise; the four kinds; `done` 1/0; weights 225 lb → 102.06 kg, 1 lb → 0.45, 0 → 0, 12345,
    no grouping; e1RM at 1 and 12 reps, empty at 13, 30 and not done; 225 × 5 → 253.13 lb / 114.82 kg;
  - quoting of commas, quotes, CR, LF, CRLF, a quote followed by a combining mark, a trailing CR;
  - N14 for = + - @ tab CR in workout, tag and exercise columns; not for a formula character later in a name, after
    a leading space, or after a `'`; a negative weight (−50 lb) and its estimate are written as numbers, never
    prefixed; −0.001 kg is written `0`, never `-0`;
  - dates by the start day across midnight (New York, Kiritimati +14, Pago Pago −11, Kolkata over New Year), both
    01:30s of New York's fall-back night and 01:59 → 03:00 in spring; Buddhist, Japanese, Persian and Umm al-Qura
    calendars still write the ISO Gregorian day;
  - seeded round trip (200 seeds) of names drawn from letters, `, " \r \n \r\n \t = + - @ '`, emoji with skin tones
    and ZWJ, Arabic, Hebrew, RLM, RLO, combining marks, BOM: every field reads back scalar for scalar (with the
    guard's `'`), and LedgerTestSupport's `CSVReader` agrees with this reader on 50 seeds.
- **Export file:** the bytes equal the BOM plus `render` over every workout oldest first (two starting together:
  smaller id first) in the units on screen; the name is `workouts-2026-09-16.csv`; an empty log gives BOM + header;
  a stray file in the directory is gone after an export, and the directory is removed when the run ends; after KG
  the file is in kg. Two writes at once both return a whole file (15 of 15 runs). A directory that cannot be made
  throws and writes nothing. FeatureSettings imports no UIKit.
- **VoiceOver (hosted, iPhone 17 simulator):** the export row is one enabled button, "Export data, CSV", hinted
  "Every set you logged, in your current units", and its line is not a separate stop; with Plate math off, "Bar and
  plates" is one dimmed button that says "Turn on Plate math to edit"; in the sheet the bar is one adjustable
  "Bar" = "45 pounds", the plates are ten stops (the off-list 7.5 lb among them), and each says on or off.
- **Nightly UI `SettingsExport`:** passed once through the lock (14.0 s); the share sheet appeared.

### Findings

**F14-S2-G2-1 — Minor. An off-list plate size disappears from the sheet once switched off.**
- **Steps to reproduce:**
  1. Store the lb inventory with plates 45 and 7.5 lb (a size off N12's list, as a later version may store).
  2. Open "Bar and plates": 7.5 lb is shown, on (as N12 says).
  3. Tap 7.5 lb to switch it off.
- **Expected:** 7.5 lb stays in the list, off, so a mistaken tap can be undone, as every listed size can.
- **Actual:** it vanishes. `PlatesPresentation.sheet` lists `sizes(units) ∪ draft.inventory.plates`, so a size that
  is off and off the list is no longer listed. Only Cancel brings it back (and loses every other edit). The chips'
  ids are their places, so every chip after it also changes identity under SwiftUI.
- **Test:** `PlatesExportAdversarialTests.offListSize_switchedOff_staysListed` (known issue).
- **Suggested fix:** keep the sizes the sheet opened with in `PlatesDraft` (e.g. `listed`, set at `.editPlates` from
  the stored inventory) and list `sizes(units) ∪ listed`; give chips the size as id.

**F14-S2-G2-2 — Nit. The failed switch's line is not N11's.**
- N11.3 says "Couldn't convert your program's weights."; the screen says "Couldn't change the units. Nothing was
  changed." The new words fit ruling A4 better (nothing is half-written), but the contract was not amended.
- **Test:** `PlatesExportAdversarialTests.failedSwitch_lineMatchesTheContract` (known issue).
- **Suggested fix:** amend N11.3 to the shipped copy, then drop the test's known issue (or delete the test).

**F14-S2-G2-3 — Nit (docs). The contract and Pete's Q1 still say "135 lb becomes 62.5 kg".**
- `tasks/features/F14-settings.md` criterion 1 (line 254) and question 1 (line 404, also "62.5 kg comes back as
  140 lb"). 135 lb is 61.23 kg, which is 60 on a 2.5 kg grid, and 60 kg comes back as 130 lb. The code's doc and
  the tests use 60 (`UnitSwitchAdversarialTests.barbell_poundsToKilograms`, `barbell_kilogramsToPounds`).
- **Suggested fix:** correct both examples.

No Critical or Major finding.

### Tests added

- `LedgerKit/Tests/LedgerDomainTests/Adversarial/UnitSwitchAdversarialTests.swift` and `+Properties.swift`: hand-worked
  conversions, kettlebells, steps, nil, ties, empty shapes; four seeded properties.
- `LedgerKit/Tests/LedgerDomainTests/Adversarial/CSVAdversarialReader.swift`: the independent RFC 4180 reader.
- `LedgerKit/Tests/LedgerDomainTests/Adversarial/CSVExportAdversarialTests.swift`, `+Guard.swift`, `+Dates.swift`:
  shape, values, e1RM, quoting, N14, negatives, dates, calendars; the seeded round trip and the readers' agreement.
- `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/SwitchUnitsAdversarialTests.swift`: A4 with refusing triggers
  and retry, same units, inactive, no program, equipment, unreadable row, differential with the in-memory stores.
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/PlatesExportAdversarialTests.swift`, `+Plates.swift`,
  `+Export.swift`: the store's switch, retry and fold; the plate editor; the export's bytes, order, directory,
  concurrency and failure (F14-S2-G2-1, -2 as known issues).
- `LedgerKit/Tests/FeatureSettingsTests/Adversarial/PlatesExportViewAdversarialTests.swift` (iOS): VoiceOver stops.

### Runs

- **Host (`LedgerKit/`):** `swift build --build-tests` clean. The domain suites (32 tests, four properties at 200
  seeds), the persistence suite (8) and the store suite (23, 2 known issues) pass. `export_twoAtOnce` passed 15 of
  15 repeated runs.
- **Simulator (iPhone 17, through the lock):** `build-for-testing` with the Nightly plan in `.derivedData`, then
  `test-without-building`: `PlatesExportViewAdversarialTests` 4 of 4 pass; `LedgerUITests/SettingsExport` passes.
- **Lint and format:** `swiftformat --lint` and `swiftlint lint --strict` clean on the eleven new files.
