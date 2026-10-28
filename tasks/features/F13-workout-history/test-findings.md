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
- `swiftformat --lint` and `swiftlint lint --strict` on the four files: clean.
