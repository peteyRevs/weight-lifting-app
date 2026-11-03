# F13 — test findings

## S1 — G2 findings (2026-10-28)

**Outcome: no Critical, Major or Medium defect.** The list query, its observation, the store, the week grouping and
the routes held under attack: no wrong row, no wrong order, no missed or extra emission, and no stuck state was found.
The PR badge agrees with the receipt's count for every workout of every random history. Three Low findings are about
words at the edges (F13-S1-1 to F13-S1-3), each with a test wrapped in `withKnownIssue`. Three informational notes
record behaviour as built for a decision (F13-S1-4 to F13-S1-6).

Slice under test: `feat/F13-workout-history` at `dacf3e9` (`34aa260..HEAD`: `ff536cd`, `093a4ec` and the notes). No
product code was changed. Host runs used `swift test`; the one simulator run went through the shared lock.

### What was attacked, and what held

- **The list query against the in-memory store, the receipt's rule and `recent`, over random histories.**
  - `HistoryListAdversarialTests.historyList_agreesEverywhere` runs F05's `HistoryScript` for 40 seeds × 14 steps:
    materialisations valid and refused, `updateSets`, deletes, tied starts, week edges, zero loads, kg beside lb, and
    every set kind.
  - After every step, GRDB's `historyEntries()` must equal the fake's, entry for entry. Its ids must equal
    `recent(limit: 1000)`'s, which pins the tie order (start, then id) on both reads.
  - Each GRDB entry must equal `HistoryEntry(workout(id:), prCount:)`, with `prCount` counted as the receipt counts
    it: `PersonalRecords.detect` against `stats.bests(before:for:)`, which is `WorkoutStore.records(of:)`.
  - The GRDB observation must have emitted each changed list exactly once. On a quarter of the seeds, nothing may come
    within 200 ms after the last step.
  - All 40 seeds agree. At least 30 of them listed two workouts or more, so the agreement is not vacuous.
- **The damaged-sets rule (A5), on GRDB.**
  - A workout whose `logged_set.weight_e7g` is text still lists, with its stored volume, while `recent` leaves it out.
  - A workout whose own `started_at` is text is left out, and the observation keeps running (a later delete still
    emits).
- **Weeks.**
  - `HistoryWeeksAdversarialTests` puts a workout every 5 h 17 min, over five weeks, into five zones: São Paulo 2018,
    where a day began at 01:00; Lord Howe, which moves by half an hour; Havana, which changes at midnight; Chatham at
    the year's end; and New York.
  - It checks all seven first days of the week. Every workout is inside its week, the weeks never overlap, each starts
    on its first day, and `lastDay` is six civil days on and inside the week.
  - Feature level (`HistoryRowAdversarialTests`): every first day of the week across New Year 2026 names both years
    ("Dec 29, 2025 – Jan 4, 2026"), except Thursday's "Jan 1 – 7". A week from 2026, seen from 2027, names its year
    once. A workout begun at 23:30 on the Sunday New York's clocks go back stays in that week and reads "Sun · 90 min".
- **Store (`HistoryStoreAdversarialTests`).**
  - A failed observation is left by the next run.
  - The first day of the week changed live through all seven days regroups the list each time.
  - A late save with an old start lands mid-list in its week.
  - A settings change that moves neither the units nor the week start leaves the model equal.
- **Words.**
  - Plurals: "1 min" and "1 minute", "1 lb" and "1 pound", "1 PR", "2 PRs", and no badge at 0 with no trailing ", ".
  - Ten hours reads "600 min". A volume of 453,139 kg reads whole.
  - Probed, without new tests: en_US, en_GB, de_DE, ja_JP, ar_EG, fr_FR, ru_RU and hi_IN headers; Arabic and Persian
    digits; and Buddhist and Japanese calendars.
- **Routes (Q1 A).** The mapping and the sanctioned edits were read. Today's `.openWorkout` pushes on `.today`
  explicitly; the Library's and History's push on `selectedTab` (F13-S1-6). The placeholder detail means a deep link
  to a deleted workout cannot be judged until S2.
- **Performance (N4).**
  - **The model.** Reproduced on the host (debug, Apple silicon) with the nightly lane on. `HistoryPerformanceTests`
    measured a median of 16.2 ms (the notes say 14.5 ms). A probe of the same fixture gave 14.0–14.7 ms over five
    runs.
  - **Varied data.** With varied lengths (25–144 min), weights and record counts, so the counted-text cache misses
    more, the probe gave 17.5–17.9 ms, under the 30 ms budget.
  - **The query.** `HistoryQueriesPerformanceTests` measured a p95 of 14.6 ms against its 20 ms budget: 27 % headroom
    on the host. Simulator: see "Runs".

### Findings

**F13-S1-1 — Low. Outside English, a row's spoken value mixes two languages.**
- **Repro.**
  - Present any entry with `HistoryInput.locale` set to de_DE. `spokenValue` is "Mittwoch, 58 minutes, 24.180 Pfund,
    1 PR".
  - The same row under ja_JP is "水曜日, 58 minutes, 24,180ポンド, 1 PR", and under ar_EG "الأربعاء, ٥٨ minutes,
    ٢٤٬١٨٠ رطلًا, ١ PR".
- **Cause.**
  - A6's `Volume.spoken(in:locale:)` asks Foundation's measurement style for the unit's word in the lifter's locale.
  - Every other word of the row comes from the module's catalog in the language it answers in (`forCountedText`),
    English.
  - The two project rules disagree. `CountedText.swift` says a lookup "takes its words from the catalog", and keeps
    only the region's digits and grouping.
  - A6's ruling asked for the injected locale, so this is a consequence of the ruling, not a slip. It reaches S3's
    steppers and the Library's "Up 1 pound" fix too.
- **Test.** `HistoryRowAdversarialTests.spokenValue_speaksOneLanguage` (de_DE, ja_JP, ar_EG and fr_FR), known issue.
- **Suggested fix.** Pass `SpokenMass.text` the catalog's language with the locale's region and numbering system, which
  is what `forCountedText(in:)` builds: "24.180 pounds" in de_DE. The plural form stays Foundation's. Alternatively,
  rule that VoiceOver text follows the device language and localise the catalog. Orchestrator's call.

**F13-S1-2 — Low. A workout shorter than a minute reads "0 min", spoken "0 minutes".**
- **Repro.**
  - An entry with `elapsed` of 59 s or 0 s reads "Wed · 0 min · 24,180 lb", spoken "Wednesday, 0 minutes, …".
  - The nightly UI test's own sample workout, saved within seconds, is such a row (its predicate `CONTAINS ' minute'`
    matches "0 minutes").
  - A workout whose end a clock moved before its start is clamped to 0 and reads the same.
- **Cause.** Whole minutes rounded down (Q6 A, as Today's RECENT rounds them).
- **Test.** `HistoryRowAdversarialTests.underAMinute_doesNotReadZero`, known issue.
- **Suggested fix.** A product word for Pete. Either read 1–59 s as "1 min", or add a "< 1 min" key with its spoken
  form, in `HistoryPresentation.row`. Today's RECENT has the same rule, and could share the answer.

**F13-S1-3 — Low (pre-existing pattern, now on a second screen). In ar_EG a drawn row writes numbers in two
numbering systems.**
- **Repro.** Under ar_EG the meta is "أربعاء · ٥٨ min · 24,180 lb" beside the badge "١ PR".
- **Cause.** The minutes and the badge keep the locale's numbering system (`forCountedText`), while the volume is the
  Domain's `Volume.formatted(in:)`, ASCII with "," grouping. Today's RECENT row has the same mix, so this is
  app-wide, not S1's own.
- **Test.** `HistoryRowAdversarialTests.arabic_drawnRow_usesOneNumberingSystem`, known issue.
- **Suggested fix.** Queue it with the other locale follow-ups. Format the drawn volume with the injected locale's
  numbering system (as `spoken(in:locale:)` already does for the spoken one), in one shared helper for Today and
  History.

**F13-S1-4 — Info. The badge counts record kinds: one heavier bench session reads "2 PRs". It agrees with the
receipt.**
- **Numbers.**
  - In `HistoryFixtures.twelve()`, each workout from the second on raises the bench by 5 lb and holds two records: an
    estimated 1RM and a weight at 5 reps. Their `prCount`s, newest first, are [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0].
  - The receipt's line for the same workout is "2 new PRs this session". It counts `PersonalRecords.detect` against
    the same bests, and the differential test above proves the two equal for every stored workout.
- **No defect.** This is the implementer's open question 1 with numbers. If Pete wants "1 PR" per lift, both the
  badge and the receipt (and S2's records line) must change together, or they disagree.

**F13-S1-5 — Info. A day that never happened breaks the week arithmetic.**
- Pacific/Apia skipped Friday 2011-12-30.
  - A Friday-start week then begins on the Saturday.
  - A Saturday-start week's `lastDay` is the next week's first instant, so its header would name one day too many.
- The case is fifteen years old, in one zone, and is excluded from the property test with a comment. No fix is
  suggested.

**F13-S1-6 — Info. The Library's and History's workout routes push on `selectedTab`, not on the tab that asked.**
- `Routes+History.swift` and `Routes+Library.swift` push `.workout(id)` on `router.selectedTab`. That is right while a
  route is delivered on the tab that drew it, which the roots' `.task(id: pendingRoute)` ensures today.
- A route handed over after a tab switch (a delivery that waited) would open the workout on the wrong stack, and its
  back button would lead elsewhere.
- No test: no current path delivers late. **For S2:** the detail's rows will push `.exercise` on History's stack, and
  sessions there push `.workout` again (stacks can grow without bound, as F12's do). Keep the pending-route guard
  there too.

### Tests added

| File | Suite | Tests | Known issues |
|---|---|--:|---|
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/HistoryListAdversarialTests.swift` | Adversarial F13 S1 · the History list on GRDB and in memory | 3 | — |
| `LedgerKit/Tests/LedgerDomainTests/Adversarial/HistoryWeeksAdversarialTests.swift` | Adversarial F13 S1 · history weeks across zones | 1 (5 zones × 7 week starts) | — |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/HistoryRowAdversarialTests.swift` | Adversarial F13 S1 · the History list's words | 8 (incl. 7 + 4 arguments) | F13-S1-1, -2, -3 |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/HistoryStoreAdversarialTests.swift` | Adversarial F13 S1 · the History store | 4 | — |

### Runs

- `swift test --filter HistoryListAdversarialTests`: 3 tests passed (4.0 s).
- `swift test --filter HistoryWeeksAdversarialTests`: passed (5 cases).
- `swift test --filter "FeatureHistoryTests\."`: 49 tests in 9 suites passed, with 8 known issues (all this round's).
- `swift test --filter "LedgerDomainTests\."`: 1,419 tests passed.
- `swift test --filter "LedgerPersistenceTests\."`: 579 tests, 1 known issue (already there).
  - The first run failed `ProgramUpdateCancelAdversarialTests` ("Cancelled while it waits behind another write",
    memory, 5,000 yields: F11 S3's), while another lane's gate was loading the machine.
  - That suite alone passed twice, and the whole target passed on the rerun. It is pre-existing and load-sensitive,
    and unrelated to F13.
- `swift test --filter "LedgerAppKitTests.(SwiftSource|CopyAudit|StringCatalog|CopyFile)"`: 103 tests passed.
- `LEDGER_TEST_LANE=nightly swift test --filter "HistoryPerformanceTests|HistoryQueriesPerformanceTests"`: both
  passed. The model's median was 16.2 ms; the query's p95 was 14.6 ms (median 13.7 ms), and the observation's fetch
  p95 was 14.5 ms.
- **Simulator** (through the lock; iPhone 17, iOS 27.0, Nightly plan): `sim-lock.py sim-targeted.sh Nightly none
  FeatureHistoryTests/HistoryPerformanceTests LedgerPersistenceTests/HistoryQueriesPerformanceTests`: exit 0, 2
  passed. The model's median was 13.6 ms (budget 30). `historyEntries` had a p95 of 14.5 ms (median 14.1); the
  observation's fetch had a p95 of 14.4 ms (budget 20).
  - N4's claims reproduce on the host and the local simulator.
  - The query keeps about 28 % headroom, so a CI runner 1.4× slower than this machine would fail the nightly. Watch
    the first nightly.
- `swiftformat --lint` and `swiftlint lint --strict` on the four files: clean.
- **Not done:** a mutant run of the differential test (flipping the tie order in the SQL). The temporary product edit
  would have raced the queued simulator build, and the tool denied it once, so the product code stayed untouched.

## S2

G2 findings, 2026-10-29. Slice under test: `feat/F13-history-detail` at `cce902e` (`e10cbe0..HEAD`: `fac1f94`,
`cfb9bd5` and the notes). No product code was changed.

**Outcome: no Critical or Major defect.** The observation, delete, routes, N13 parity and R1-5 held under attack.
- **Minor (one):** F13-S2-1. A settings observation that ends turns every detail into "This workout can't be read",
  with Delete offered.
- **Nit (two):** F13-S2-2, which has the same root cause as F13-S2-1, and F13-S2-3, the delete's run-once guard.
- Each of the three is pinned under `withKnownIssue`.
- **Info (three):** F13-S2-4 to F13-S2-6.

### What was attacked, and what held

- **`observeWorkout(id:)` on GRDB against the fake** (`WorkoutDetailObservationAdversarialTests`).
  - F05's `HistoryScript` ran 24 seeds × 14 steps of finishes (valid and refused), `updateSets` and deletes, while all
    six of the script's workouts were observed on GRDB.
  - After every step each GRDB read (`fetchRecordedWorkout`) equals the fake's value, records and their order
    included.
  - Each stream emitted exactly the changed values, once each. Nothing came in the 150 ms after the last step.
  - Records of two lifts come in the same order from both sides. A workout holds at most one weight-at-reps record per
    lift, so `ORDER BY exercise_id, kind` is a total order.
- **Records recompute after a delete.**
  - Setup: a 150 baseline, a 225 holder, then 200 and 210.
  - Deleting the holder emits 200's detail with an estimated 1RM and a weight at 5 (it now beats 150), and 210's with
    both.
  - `personalRecords` lists exactly those two workouts, and the list's badges read [2, 2, 0].
  - A lift's first session holds no record by rule, which the fixtures had to allow for.
- **Writes that change nothing emit nothing** (`WorkoutDetailDamageAdversarialTests`):
  - the same sets written again
  - the same workout re-materialised (a sync's resend)
  - set taps (`workout_event`) logged against the workout's own id
  - a settings save

  Its own delete still emits nil.
- **Damage.**
  - Damage to another workout (its `started_at`, a set's weight, a record's kind) leaves the stream running.
  - Damage to the workout's own row, an exercise's `equipment`, a set or a record ends the stream (N10), and a later
    delete emits nothing.
  - A workout damaged before it is observed ends at once without a value, while the list still shows it (A5). Its
    detail is reachable and says N10, as ruled.
- **Delete once** (`WorkoutDetailStoreAdversarialTests`).
  - A confirmation during an in-flight delete is dropped, and the repository is asked once.
  - A failed delete keeps the screen. A later delete elsewhere still closes it.
  - The observation's nil arriving before `delete(id:)` returns hands only close routes (F13-S2-5).
- **A delete elsewhere.**
  - Two details of one workout (two tabs) and one detail of another were run together.
  - Deleting the first workout closes both of its details, one route each, and leaves the other detail loaded with
    nothing pending.
  - A row's route still waiting is replaced by the close.
- **Routes** (`HistoryDetailAdversarialTests`, router level).
  - A late `.exercise` from History and a late `.openWorkout` from a session log land on their own stack after a tab
    switch.
  - The same workout on two tabs: each tab's close pops only its own detail, and a second close pops nothing.
  - `[detail, exercise, detail]` (a session log reopening it): two closes pop the top detail only. After the lifter
    pops the exercise history, the lower detail's close pops it.
  - A detail under its row's exercise history: the close pops nothing until the history comes off, then pops the
    detail.
  - A close of another workout pops nothing.
- **N13 in both units, seven locales** (`WorkoutDetailParityAdversarialTests`).
  - 120 random finished workouts:
    - every set kind, sets edited off their target, sets not done
    - 102.3 lb, 90.7 kg and 1,234,567 lb
    - no exercise at all
    - times of 0 s, 59 s and 10 h
    - none, one or several records
  - Each was checked in lb and kg, under en_US, en_GB, de_DE, fr_FR, ar_EG, ja_JP and hi_IN.
  - In every case the detail equals `WorkoutPresentation.receipt` of the same workout drawn in that unit, string for
    string: tiles, records line, rows, day and name.
  - A pound workout of 200 lb drawn in kilograms reads 90.7 everywhere.
  - Units switched kg → lb → kg live redraw the detail to the presentation's model each time, and no record moves.
- **R1-5** (`SpokenWeightRoundTripAdversarialTests`, 53,952 cases).
  - The weights:
    - quarter pounds and quarter kilograms to 1,000
    - pounds and half pounds converted
    - 400 random 10⁻⁷ g weights
    - the edges: 90.7, 90.72, 90.718474, 2.249, 2.2449, 2.2451, 0.124 to 0.126, 99.95, 999.975, 1,234,567.25, 1e-7
      and 9,999,999,999.75, in both units
  - `formatted(in:)` reads back as `shownValue(in:)`, digit for digit.
  - The spoken text, with its unit's word removed, parses back to `shownValue` in 12 locales. Those include de_CH,
    en_IN (lakh grouping), ar_EG, fa_IR, Devanagari and Thai digits.
  - The only text without digits is Arabic's dual "رطلان" (two pounds), which is correct.
  - 200 lb reads "90.7 kilograms" and "90,7 Kilogramm"; 90.7 kg reads "200 pounds".
- **Accessibility.**
  - The VoiceOver order of every state, the 44 pt targets and the AX3 stacking are the implementer's suites. I read
    them, and they pin the tree exactly.
  - Added (`WorkoutDetailMirrorAdversarialTests`, simulator), with and without records and in the unreadable state,
    at `.large` and at `.accessibility5` with Bold Text, right to left:
    - the stops and their order equal left to right
    - the day, the name and "Delete workout" are mirrored to within 1 pt
  - The delete alert's words are model strings pinned by `HistoryCopyTests`. The hosted reader cannot open a SwiftUI
    alert, so the alert is not read here (the nightly UI test answers it).

### Findings

**F13-S2-1 — Minor. A settings observation that ends makes every detail say "This workout can't be read", with
Delete offered.**
- **Repro.**
  - Give the detail's store a `SettingsRepository` whose `observe()` ends. `GRDBSettingsRepository.observe()` does,
    at once and on every run, for a settings row this app can't read, such as a later version's payload.
  - Open any readable workout.
  - Also: let the settings yield their first value, so the receipt is drawn, then end the stream.
- **Expected.**
  - The workout is shown. `GRDBSettingsRepository`'s documentation says F07 and F14 "fall back to the defaults in
    memory" when that stream ends.
  - At the least, the screen does not blame the workout.
- **Actual.**
  - `state == .unreadable`: "This workout can't be read. It stays in your history. You can still delete it."
  - The receipt already drawn is replaced the same way.
  - The words blame a workout that reads fine, and point at Delete, which can't be undone.
  - The condition persists for as long as the settings row stays unreadable, so it holds for every workout and every
    visit.
- **Cause.** `rebuild()` maps any ended source to `.unreadable` (decision 4 in the as-built notes: "a settings failure
  is then worded as the workout's; it was judged too rare for its own state").
- **Judgement.**
  - This is wrong. It is rare, but the failure it describes is persistent, and the remedy it suggests destroys data.
  - S1's list shows a generic failed state for the same case, so this is less reachable from History. It is still
    reachable from Today's "View session" and from a Library session log.
- **Tests.** `WorkoutDetailSettingsAdversarialTests.settingsEndAtOnce_doesNotBlameTheWorkout` and
  `.settingsEndAfterFirstValue_doesNotBlameTheWorkout`, known issues.
- **Suggested fix.** In `WorkoutDetailStore.follow`, keep the ended flag per source:
  - The settings' end falls back to `Settings.default` units, or to the last value seen.
  - Only the workout's own end shows N10.

**F13-S2-2 — Nit. Once a source has ended, a delete elsewhere no longer closes the detail.**
- **Repro.** Settings that end at once, as in F13-S2-1. Then delete the workout in the store (another tab, or the
  watch's sync).
- **Expected.** `.gone`, and `.closeWorkout(id)` handed to the app.
- **Actual.**
  - The detail stays on "This workout can't be read. It stays in your history." for a workout that is gone.
  - Tapping Delete then deletes nothing (a no-op on GRDB and in memory) and closes it.
- **Cause.** `rebuild()` checks `sources.hasEnded` before it looks at the workout's nil.
- **Test.** `WorkoutDetailSettingsAdversarialTests.settingsEnded_thenDeletedElsewhere_closes`, known issue.
- **Suggested fix.** F13-S2-1's fix removes it. Otherwise, handle `sources.workout == .some(nil)` before the ended
  check.

**F13-S2-3 — Nit. The delete's run-once guard reads the wrong flag.**
- **Cause.**
  - `delete()` runs while `isDeleting` is true, which means "a delete was confirmed", not "this confirmation has not
    run yet".
  - Its `defer` resets the flag whether the delete succeeded, failed or was cancelled.
  - The root runs it from `.task(id: store.deletion)`, which SwiftUI cancels when the view disappears and runs again,
    with the same id, when the view reappears.
- **Repro (store level, a repository gated before its write).**
  - (a) Confirm, then start `delete()` and cancel it while it waits. This is the view going away (a tab switch or a
    back swipe) before the write starts; GRDB throws `CancellationError` there. Then run `delete()` again, as the
    reappearing view's task does.
  - (b) Confirm, start `delete()`, and start it again while the first is in flight.
- **Expected.**
  - (a) The workout is deleted, or the lifter is told.
  - (b) The repository is asked once.
- **Actual.**
  - (a) Nothing is deleted and nothing is said. The workout is still there when the lifter comes back.
  - (b) The repository is asked twice. The second delete is a no-op on GRDB, but it is a second write and record
    replay.
- **Reach.** Both need the view to go and come back within the few milliseconds of the write, hence Nit.
- **Tests.** `WorkoutDetailStoreAdversarialTests.deleteCancelled_isNotLostSilently` and
  `.deleteRunTwice_whileInFlight_deletesOnce`, known issues.
- **Suggested fix.**
  - Key the run on the confirmation: keep `confirmedDeletion: Int?` and `ranDeletion: Int?`, and run only when they
    differ.
  - On a cancellation, leave the confirmation pending so the next run performs it. Or run the delete in an unowned
    `Task`, since a confirmed delete should not depend on the view staying up.

**F13-S2-4 — Info. A late route also selects its tab.**
- `resolve(_:from:)` calls `open(_:in:)`, which sets `selectedTab`. A route delivered after a tab switch therefore
  lands on its own stack, as fixed, and also brings the lifter back to that tab.
- No current path delivers late: a hidden root's task runs again only when its tab is shown.
- Pinned as built in `HistoryDetailAdversarialTests.lateRoute_landsOnItsOwnStack`.

**F13-S2-5 — Info. Two closes can reach the app for one delete.**
- When the observation's nil reaches the store before `delete(id:)` returns, and the root hands that close over first,
  the delete's own `close()` makes a second `.closeWorkout(id)`.
- This is harmless:
  - By then the view is popped and its route task cancelled.
  - The router pops only a `.workout(id)` on top, so a second close pops nothing (shown on `[detail, exercise,
    detail]`).
- Pinned in `WorkoutDetailStoreAdversarialTests.nilBeforeDeleteReturns_closesOnly`.

**F13-S2-6 — Info. Closing a covered detail relies on SwiftUI re-running its task, which no test exercises.**
- **The design.**
  - When a detail is under its row's exercise history (or under itself, via a session log) and its workout is
    deleted, the covered detail's close pops nothing.
  - The detail goes only when the lifter comes back to it: its `.task` runs again, finds it gone and closes (decision
    3). That depends on NavigationStack sending a covered view `onDisappear`/`onAppear`, which it does today.
- **What is tested.** The router half above, and `runAgain_onAGoneWorkout_closesAgain` for the store.
- **What is not.** The SwiftUI half. The nightly UI tests delete only from a detail on top.
- **A side effect.** A covered detail whose task was cancelled still holds its last `.loaded` model. Coming back, the
  deleted workout's receipt, with a live Delete, shows for a frame before the close.
- **Suggestion.** One nightly UI test: open a workout's detail on History, push its row's exercise history, open the
  same workout from Today's "View session", delete it there, return to History and go back. The detail must pop.

### Tests added

| File | Suite | Tests | Known issues |
|---|---|--:|---|
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/WorkoutDetailObservationAdversarialTests.swift` | Adversarial F13 S2 · observeWorkout on GRDB and in memory | 3 | — |
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/WorkoutDetailDamageAdversarialTests.swift` | Adversarial F13 S2 · observeWorkout against writes and damage | 4 (incl. 4 arguments) | — |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/WorkoutDetailStoreAdversarialTests.swift` | Adversarial F13 S2 · the detail's store | 7 | F13-S2-3 (2) |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/WorkoutDetailSettingsAdversarialTests.swift` | Adversarial F13 S2 · the detail when the settings end | 4 | F13-S2-1 (2), F13-S2-2 |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/WorkoutDetailMirrorAdversarialTests.swift` | Adversarial F13 S2 · the detail right to left (iOS) | 1 (4 arguments) | — |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/WorkoutDetailAdversarialSupport.swift` | support: `GatedDetailScene`, `GatedWorkouts`, `EndingSettings`, `settles` | — | — |
| `LedgerKit/Tests/LedgerAppKitTests/Adversarial/HistoryDetailAdversarialTests.swift` | Adversarial F13 S2 · the detail's routes | 5 | — |
| `LedgerKit/Tests/LedgerAppKitTests/Adversarial/WorkoutDetailParityAdversarialTests.swift` | Adversarial F13 S2 · the detail is the receipt | 2 | — |
| `LedgerKit/Tests/LedgerDomainTests/Adversarial/SpokenWeightRoundTripAdversarialTests.swift` | Adversarial F13 S2 · R1-5, the spoken weight's round trip | 3 | — |

### Runs

- **Host, `swift test`:**
  - The filter `FeatureHistoryTests\.|LedgerAppKitTests\.(SwiftSource|CopyAudit|StringCatalog|CopyFile|HistoryDetail|WorkoutDetailParity|HistoryRouteMapping|ReceiptParity)|WorkoutDetailObservationAdversarialTests|WorkoutDetailDamageAdversarialTests|SpokenWeight`
    passed in every target:
    - FeatureHistoryTests: 87 tests, 7 known issues (F13-S1-3 and this round's six).
    - LedgerAppKitTests: 117 tests.
    - LedgerPersistenceTests: 7.
    - LedgerDomainTests: 8.
  - The GRDB property test takes 24 s on the host.
- **Simulator** (through the lock, iPhone 17, iOS 27.0, PR plan): `f13s2-targeted.sh PR none` with the eight new
  suites. Exit 0: 30 passed, 5 expected failures (the known issues), 0 failed.
- `swiftformat --lint` and `swiftlint lint --strict` on the nine files: clean.

## S3 — G2 findings (2026-11-02)

**Outcome: no Critical or Major defect, and no corruption of exact weights.** The batched write is one transaction
with one replay. It is all-or-nothing when a row write or the replay fails halfway, and it leaves every other row and
column alone, stamps included. Records after random edits equal a freshly materialised history. A delete racing a
save never brings the workout back. Untouched sets keep their exact `Decimal`, including off-multiple and
kg-in-pound weights.

The findings: coverage is below the standard, and the notes misstate its baseline (Should fix). There are two Low
findings with data effects: a quick reopen of the sheet is stale, and so is a sheet snapshot under a concurrent
writer. One Low finding is about digits. The rest are Info.

Slice under test: `feat/F13-s3-edit-sets` at `a787452` (base `33048c5`). No product code was changed.

### Findings

**F13-S3-1. Should fix: FeatureHistory coverage fell further than the notes say, and is still below S2's after G2's
tests.**
- **Baseline.** The S2 merge gate (`f13s2-merge-gate2.log`) measured FeatureHistory at **99.09 %** (985 / 994), not
  98.53 %. The 98.53 % in the notes is S2's own G1 figure, from before its fix rounds.
- **S3.** The G1 gate measured 96.65 % (1,416 / 1,465): a fall of 2.44 points, with 9 uncovered lines becoming 49.
- **With G2's tests.** On iOS, FeatureHistory, LedgerAppKit, LedgerPersistence and LedgerDomain tests together, PR
  plan: **98.50 %** (1,443 / 1,465).
- **Still uncovered.**
  - `WorkoutDetailRoot` 41 and 54–56: the `.sheet` content closure and the item binding's setter. A scene-less window
    presents no sheet. The nightly UI tests reach them, but the PR plan doesn't.
  - `EditSetsSheet` 23: the default `announce`.
  - One line each in `EditSetsStore` and `EditSetsPage`.
- **What to do.** Either the orchestrator waives the root's sheet lines (they need a scene), or the implementer
  extracts the binding into a testable function on the store (for example `editingBinding`).
- **FeatureLibrary.**
  - Main measured 97.05 % (2,139 / 2,204, S2 merge gate) and 97.01 % on CI #81.
  - On this branch, my PR run measured 97.03 % (2,124 / 2,189) and G1's gate 96.93 % (2,122 / 2,189).
  - Uncovered lines are the same 65 as on main. The percentage dips because A6 removed 15 *covered* lines. G1's 67 is
    run-to-run timing (two lines that differ by task timing).
  - Not a regression in substance, but the number is lower than main's.

**F13-S3-2. Low (fixed by tests): the sheet's "Nothing logged" and its Save tap were never exercised.**
- No preview, tree, layout or hosted test drew an exercise with nothing logged (`EditSetsPage` 21–25 were uncovered).
  No test tapped Save's closure (`EditSetsScreen` 41–43).
- `EditSetsHostedAdversarialTests` now reads both:
  - "Nothing logged" follows its heading, with no stepper under it.
  - Save sends `.save` only when it has an action.

**F13-S3-3. Low: Edit reopened before the observation's next value opens on the old sets, and its save undoes the
first fix.**
- **How.** `WorkoutDetailStore.edit()` builds the request from `sources.workout`, the observation's last value. After
  a save, `editClosed` lets "Edit" open at once. Until GRDB's next value lands, the new sheet holds the pre-save sets.
  Saving any change to the same exercise then writes the old values back.
- **Repro.** `EditSetsAdversarialTests.reopenedBeforeTheNextValue_opensStale`, a scripted observation, pinned as
  built.
- **Reach.** The window is GRDB's observation latency (milliseconds) against the sheet's dismissal, so a tap is
  unlikely to land in it. Not seen in the UI test.
- **Fix if wanted.** Keep the saved draft in the detail until a value newer than the save arrives, or read
  `workout(id:)` when "Edit" is tapped.

**F13-S3-4. Low (as designed, decision 3): a stale snapshot overwrites a concurrent edit to the same exercise.**
- **How.** `SetEditing.changes` hands over whole exercises. A sibling set of a changed exercise, edited by another
  writer after the sheet opened, is reverted. Exercises the sheet didn't change survive, because `replace` re-reads
  the workout inside the write.
- **Repro.**
  - `BatchedEditRaceAdversarialTests.staleSnapshot_overwritesTheSameExerciseOnly`.
  - `EditSetsAdversarialTests.sheetSave_leavesOtherExercisesAlone`.
- **Today.** No second writer exists on one device. F05 item 6 and F17 are where it bites: a late watch envelope, or a
  sync merge.
- **Exact weights.** The reverted values are the exact old `Decimal`s, not approximations.

**F13-S3-5. Low: in Arabic locales the sheet's reps are Arabic digits beside a weight in Western digits; the receipt's
are Western.**
- **Cause.** `EditSetsPresentation.row` formats reps with `IntegerFormatStyle(locale:)`, but weights with
  `Weight.formatted(in:)` (ASCII), as the receipt does.
- **Result.** In `ar_EG` the sheet shows "187.5 lb" over "١٢", while the detail's chip reads "187.5×12".
- **Repro.** `EditSetsAdversarialTests.digits_matchTheReceipt`, with a known issue for `ar_EG`. `hi_IN`, `ja_JP`,
  `de_DE` and `fr_FR` match.

**F13-S3-6. Info: "This workout was deleted" is said when only an exercise is gone, and the detail closes over a
workout that still stands.**
- **How.** `updateSets` throws `missingRow` for an unknown exercise too, and the store maps every `missingRow` to
  `.workoutGone`.
- **Today.** Unreachable, since nothing removes an exercise from a stored workout. An input for F17.
- **Repro.** `EditSetsAdversarialTests.missingExercise_saysDeleted_whileTheWorkoutStands`, pinned as built.

**F13-S3-7. Info: the notes' decision 7 is only half right.**
- **The claim.** "In the workout's own units a step and its way back turn Save off."
- **What holds.** That is true only from a multiple of the step. Off a multiple (187 lb on 5 lb), up goes to 190 and
  down to 185.
- **The kg case.** A pound workout stepped in kg never returns: 225 lb up then down is 101.25 kg on 1.25 kg steps.
- **Nothing is silent.** In both cases Save stays on, the screen shows the new number, and only Cancel restores the
  original. No untouched set moves, and every result is a whole 10⁻⁷ g, so storage is exact (ADR-007).
- **Repro.**
  - `SetEditingAdversarialTests.ownUnits_offAMultiple_hasNoWayBack`.
  - `SetEditingAdversarialTests.kilogramsOnPounds_hasNoWayBack`.

**F13-S3-8. Info: swiping away a changed sheet discards the draft, unasked (decision 8).**
- **What is lost.** Only the unsaved draft; the stored workout is untouched.
- **Repro.** The nightly UI test `test_editCancelAndSwipe_discardTheStep`: step, Cancel, reopen shows the stored value;
  step, swipe down, reopen shows it again with Save off.
- **Decision.** Whether to confirm before discarding is Pete's.

**F13-S3-9. Info: `editClosed(workoutGone: false)` after `editClosed(workoutGone: true)` rebuilds over `.gone`.**
- **When.** The binding's `set(nil)` would do this after the alert's OK. SwiftUI sends no `set` when the store cleared
  the item, so it is not seen in practice.
- **Effect.** The receipt would redraw for a frame until the nil lands. Exactly one close route is still waiting.
- **Repro.** `EditSetsGoneAdversarialTests.goneFlow_bothSignals_leaveOneClose`.

### What was attacked, and what held

- **Exact weights (ADR-007).**
  - Steps land on a whole multiple, on the side tapped, within one step, never below 0, and representable in
    10⁻⁷ g: 4,000 random weights × 5 steps, lb and kg.
  - From a multiple, up then down is exact (0–800 steps).
  - Random walks of 40 steps move only the set and field tapped. Ids, kinds, `doneAt`, sets not logged, other
    exercises and every workout field stay equal.
  - On GRDB, 40 rounds of random steps in either unit read back `==` the draft. The list's volume is their exact sum.
- **Untouched rows (GRDB).**
  - All four tables were dumped column by column before and after a two-exercise edit (one of them in kg on a pound
    workout).
  - Untouched sets, every `workout_exercise` row and other workouts keep every column, `updated_at` included.
    Other workouts may change only `pr_count`.
  - Edited sets change only `weight_e7g`, `reps`, `e1rm_e7g` and `updated_at`. The edited workout changes only
    `volume_e7g_reps`, `pr_count` and `updated_at`.
- **One write, one replay.** SQLite's trace shows one `BEGIN IMMEDIATE`/`COMMIT`, exactly one replay walk naming all
  three exercises, and one read of the stored records. This answers the notes' decision 11 directly.
- **Atomicity.**
  - Triggers aborted the write on the second exercise's set, on a record insert, and on a record update. Each time,
    every row stayed as it was. With the trigger dropped, the same map saves.
  - A set id held by another workout, or used twice in one call, is refused on GRDB (and in memory), and nothing
    moves.
- **Records after an edit.** 24 seeds × 8 random batched edits (steps in both units, large fixes both ways): records
  per exercise and `historyEntries()` equal a fresh database that materialised the final workouts. More than 20
  records were compared.
- **Followers (C19).** A fix that keeps the volume (200 × 5 to 250 × 4) reaches the detail, `observeRecent`, the
  Library's stats and the exercise's sessions.
- **Races.**
  - Delete against save, 40 rounds in both orders: the workout always ends deleted, with no live records. The save
    either stored or threw `missingRow`. The newer workout gets its record back.
  - Two saves on different exercises both land.
  - A save cancelled after 0–30 yields stores all or nothing, on GRDB alone and through the sheet's store. The store
    says `.saved` exactly when it stored, and never shows a failure line for a cancel.
- **The gone flow, end to end.**
  - In memory, the chain runs: delete, the detail hears the nil and waits, Save, `.workoutGone`, nothing moves behind
    the alert, OK, `.gone`, one close route, and the save brings nothing back.
  - On GRDB, `missingRow` reaches the alert, not the failure line.
  - Cancel or a swipe after a delete closes the detail too.
  - "The nil waits" is shown positively: after the nil, a later value from the same stream is seen, and still no
    route. A control without a sheet closes at once. This replaces `deletedUnderTheSheet_closesAfterIt`'s
    `Task.yield`.
- **Saving.**
  - Fail, fail, succeed is three writes, one per tap. A rerun task writes nothing. A saved sheet writes no more.
  - While a write is held at a gate, steps, a second Save, Cancel and VoiceOver's escape are refused, and the model is
    off.
  - A failure line is announced each time, not only the first.
  - A database that refuses the write gives the failure line, not "deleted", and the same draft then saves.
- **VoiceOver.** Adjustable swipes reach the draft, and nothing moves at the limit or when disabled. Cancel's
  activation closes with `workoutGone == false` and stores nothing. The app's own `init(request:)` draws the sheet.

### Tests added

| File | Suite | Tests | Known issues |
|---|---|--:|---|
| `LedgerKit/Tests/LedgerDomainTests/Adversarial/SetEditingAdversarialTests.swift` | Adversarial F13 S3 · SetEditing's arithmetic and what it leaves alone | 8 (incl. 5 arguments) | — |
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/BatchedEditAdversarialTests.swift` | Adversarial F13 S3 · the batched edit, at the rows | 7 | — |
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/BatchedEditRaceAdversarialTests.swift` | Adversarial F13 S3 · the batched edit against others | 6 | — |
| `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/BatchedEditAdversarialSupport.swift` | support: `BatchedEditKit` (row dumps, trace, history) | — | — |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/EditSetsAdversarialTests.swift` | Adversarial F13 S3 · the sheet's saves and words | 7 (incl. 6 arguments) | F13-S3-5 |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/EditSetsGoneAdversarialTests.swift` | Adversarial F13 S3 · a workout deleted under the sheet | 5 | — |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/EditSetsHostedAdversarialTests.swift` | Adversarial F13 S3 · the sheet hosted (iOS) | 7 | — |
| `LedgerKit/Tests/FeatureHistoryTests/Adversarial/EditSetsAdversarialSupport.swift` | support: `ScriptedWorkouts`, `EditAdversarialScene` | — | — |
| `LedgerKit/Tests/LedgerAppKitTests/Adversarial/EditSetsOnDiskAdversarialTests.swift` | Adversarial F13 S3 · the sheet on the real database | 4 | — |
| `Apps/LedgerUITests/WorkoutHistory+EditDiscard.swift` | `WorkoutHistory.test_editCancelAndSwipe_discardTheStep` (nightly) | 1 | — |

### Runs

- **Host, `swift test`.** The filter `SetEditingAdversarialTests|BatchedEdit|EditSets.*AdversarialTests` exited 0.
  The F13-S3-5 known issue is expected.
- **Simulator, PR plan, through the lock** (iPhone 17, iOS 27.0, `TEST_RUNNER_LEDGER_SWEEP=pr`):
  - **The four targets that hold this slice's tests** (FeatureHistory, LedgerAppKit, LedgerPersistence and
    LedgerDomain tests): exit 65 with 2,579 passed and 1 failed. The failure is `LoadableAdversarialTests` ("Loadable
    is Sendable…"), which exceeded its 1-minute time limit. It is outside this slice.
  - **The whole PR plan, twice:** exit 65 both times.
    - About 33 failures, all `FeatureWorkoutTests` "never came in 10.0 seconds", plus that Loadable timeout and a
      FeatureProgram time limit.
    - The first run also failed my own `cancelledSave_isWholeOrNothing_andSilent`. That was a test bug: the second
      exercise steps by 2.5 lb, not 5. It was fixed and passed in the second run.
    - Every run began with a stall of about 78 s.
  - **FeatureWorkoutTests on main's tree** (`git archive 33048c5`, same simulator, same lock): exit 65, with 32 of 471
    failing the same way. These failures are this machine's simulator today, not S3. The orchestrator's gate should
    be re-run on a quiet machine.
- **Simulator, Nightly plan, through the lock:** `test_editCancelAndSwipe_discardTheStep` and
  `test_editASet_showsInTheDetailAndTheList` exited 0, 2 of 2 passed.
- **Lint:** `swiftformat --lint` and `swiftlint lint --strict` on the 11 new files are clean.
