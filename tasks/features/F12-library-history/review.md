# F12 — review

## Slice S1 — review (G3, 2026-10-21)

The orchestrator relayed this review to G1 in brief; it is recorded as given. Verdict: **not approved**.

**M1 (Major). `Apps/LedgerUITests/LibraryAuditAdversarial.swift`: the measurement test cannot fail on the defect,
and the exclusion is too wide.** The test only shows that some ink lies between the pill's strokes.
- **(a) No height floor.** Text clipped by the TextField's own bounds passes, and those bounds sit about 24 px
  inside the pill at 3×. A one-row sliver passes too. The ink has to span at least the expected glyph height, or be
  compared with an unclipped `Text` of the same string in `.ledgerFieldFont(.body)`, the way `FieldFontTests`
  measures "Gyp".
- **(b) No horizontal check.** In the XXXL picture the ink spans 312 pt and ends 4 pt inside the 16-pt trailing
  padding. On a 375 or 390 pt phone the field's inner width is about 306 pt or less, so the placeholder probably
  truncates there for real, in the Library and in F11's picker.
- **(c) No control.** Nothing shows the guards fail on a clipped or truncated placeholder.
- **The exclusion matches by label alone** (about line 109). The field's `accessibilityLabel` stays the placeholder
  while a query is typed (`SearchField.swift:33`), so a real clip of an edited query would be excluded too. It
  should match on element type `.textField` with an empty value.

**m1 (minor). `LibraryAuditAdversarial.swift:114`: the contrast exclusion is by frame alone.** It would also hide a
real contrast failure on a tab-bar item. It should exclude only elements that are not tab items, as Today's
precedent does. The comment at about line 89 has to match.

**m2 (minor). "New exercise" does nothing until S3.** This goes to Pete in the PR.

**m3 (minor). `FilterChipRow` and `SearchField` have no snapshot suite of their own.** Standards §11 and plan flag
A3 require one.

**m4 (minor). The "· Custom" wording in RECENTLY LOGGED** ("Barbell · Chest · 1 session · Custom") is G1's own.
This goes to Pete in the PR.

**n1 (nit). "PR 1 pounds".** A one-unit best is spoken with a plural unit. Recorded as a follow-up.

**n2 (nit). `GRDBStatsQueries+Library.swift:29` logs an exercise id as a `workout_exercise` row id.**

**n3 (nit).** Recorded as a follow-up, as the orchestrator ruled.

### Orchestrator's ruling (round 4)

- **Fix M1 (a), (b), (c), the exclusion's match, m1, m3 and n2.**
- **(b) is to be verified in a hosted LedgerDesign test** of `SearchField` at narrow widths and `.accessibility5`,
  through `TestSweep`.
  - If the placeholder truncates, the product falls back to a shorter placeholder when "Search N exercises" does
    not fit. Any new wording is flagged for Pete.
  - If it does not truncate, a trailing-column guard is added anyway.
- **n1 and n3** are follow-ups in the notes.
- **m2 and m4** are open questions for Pete in the PR.

## Slice S1 — round 2 (G3 reviewer, 2026-10-21)

Reviewed `34783dd..b3343d3` and the merge of #69 at `15925b5`. Host-only; `scripts/check.sh --lint-only` exit 0.

**Verdict: approved.** No blocker or major.

- **M1 and m1:** fixed. Real truncation is caught by the host test `SearchFieldFitTests`, which can't pass vacuously, and its control proves it measures the real font and width. The "Text clipped" exclusion is narrowed to an empty `.textField`. The contrast exclusion spares the four tab buttons.
- **m3 and n2:** fixed.
- **The short-placeholder switch:** there is no layout loop. `room` comes from `onGeometryChange` on the greedy `TextField`; `needed` comes from a hidden `.fixedSize()` `Text`.

### Minor and nits, deferred to S2's first commit (orchestrator's ruling)

- **R2-1 (minor):** the UI test's trailing-padding guard (b) can't see a real "…", because UIKit truncates inside `placeholderRect`. Reword the comments in `LibraryAuditAdversarial.swift`, or drop guard (b).
- **R2-2 (minor):** `SearchField` switches at `needed <= room` with no margin. Its measure is SwiftUI's; the truncation happens in UIKit's `placeholderRect`. Add a margin (+1 pt or the measured inset), or add 393, 430 and 440 pt to `SearchFieldFitTests.widths`.
- **R2-3 (minor):** no test asserts that VoiceOver reads the whole placeholder while "Search" is drawn. Add one `XCTAssertEqual(field.label, …)` in the guard test.
- **R2-4 (nit):** FeatureLibrary doesn't assert `LibraryModel.Search.shortPlaceholder`.
- **R2-5 (nit):** the in-memory `bestSets()` from `46838db` is the same rule, but it now makes several reads, and its differential clause has become circular. Restore the single walk.
- **R2-6 (nit):** branch-only product lines are 996–998, under 1,000.

### Orchestrator's gate

`scripts/check.sh` on `15925b5`, with `main` `2c9b66a` in: exit 0, "check.sh OK", 1,862 s in total (iOS tests 1,494 s, watchOS tests 237 s).

## Slice S2 — review (G3, 2026-10-24)

Reviewed `d92cc15...118c91a` (S1's R2 fixes in `1c1a688` skimmed only). Read-only. I wrote two scratch timing and
probe tests on the host, ran them, and deleted them; no product file or test was changed.

**Verdict: changes needed.** One Major (N11 is measured under the specified load, and misses it at that load).
The rest is Minor or Nit. What holds: the fold against the spec; the tags (N10, criterion 7); the GRDB query and
its order, which matches `recent`; the parity of the in-memory store; the store's overtaken-read and failure paths;
cancellation, because the stream's `onTermination` cancels GRDB; the dates (N14); the descriptor; the hosted sweeps
through `TestSweep`; the bounded waits in G2's suite. The S1-convention `eventually` waits are ended by the suite's
time limit, as in S1.

**F12-S2-R1-1 (Major). N11's fold budget is measured at about 1,700 sets, and at the brief's 2,000 it misses.**
- `StatsQueriesPerformanceTests.swift:78` times `ExerciseHistory.make` over the main lift's sessions of the
  20k-set seed (about 1,703 sets; the notes give 4.1 ms p95 against 5 ms). N11 says 2,000 sets.
- I measured on the host, Debug: 400 sessions × 5 sets took **5.5–5.9 ms**.
- 3.4 ms of that is `estimate(of:)` (`ExerciseHistory.swift:83`). It runs a `Decimal` Brzycki for every counted
  set, and then again in each week (`:96`).
- **Fix:** keep the heaviest weight per rep count in one walk (`PersonalRecords.Tally.atReps` is that tally
  already), then take Brzycki of at most 12 candidates. Brzycki, and its rounding to the gram, rise with the
  weight at fixed reps, so the maximum is the same exactly.
  - The best set is the maximum over the same tally, as `Bests.bestSet(of:)` does.
  - Measured on the host: 3.4 ms → 0.38 ms. The fold should land near 2.5 ms.
- Make the performance test fold 2,000 sets: a seed exercise with 2,000 sets, or the brief's figure named
  honestly in `PerformanceBudget.historyFold`'s comment.

**F12-S2-R1-2 (Minor). The presentation takes about 24 ms on the main actor per rebuild at 2,000 sets, and no
budget covers it.**
- `ExerciseHistoryStore.rebuild` runs `ExerciseHistoryPresentation.make` on `@MainActor`. It runs on every
  emission of `observeAll` (any exercise saved), of the settings, and of the sessions.
- Measured on the host, Debug: 23.9–25.1 ms. The cost is mostly each set's `String(localized:)` and
  `formatted(in:)`, and each entry's date style. That is more than a frame.
- **Fix:** the input is `Sendable` and `make` is `nonisolated`, so build the model off the main actor and assign
  it on return. Alternatively, keep the log's strings across rebuilds that change neither the units nor the
  sessions.
- Either way, add the presentation at 2,000 sets to the Nightly performance suite with a budget (a frame,
  16 ms, is a reasonable line).

**F12-S2-R1-3 (Minor). The store discards the observed sessions and reads them again.**
- `ExerciseHistoryStore.swift:95-98` keeps nothing of the emitted `[ExerciseSession]`. `readHistory` (`:167`)
  then runs `exerciseSessions` again.
- So every change of the exercise's sessions costs two full fetches (13 ms p95 each at the N11 seed), and the
  emitted value is never used.
- **Fix:** keep the value (`kept.sessions = value; kept.records = nil; kept.generation += 1`). Read only
  `personalRecords` in `readHistory`, with the same generation guard. This is simpler, it halves the I/O, and the
  failed-read and overtaken-read paths stay as they are.

**F12-S2-R1-4 (Minor). The sessions caption (F12-S2-2) works by string surgery in the copy file.** The
caption-question section below gives the assessment and the recommendation.

**F12-S2-R1-5 (Minor, wording for Pete). An exercise logged only above 12 reps reads "Log a session to start the
chart." for ever.**
- `ExerciseHistoryPresentation.swift:92` shows `noChart` whenever no week has an estimate.
- Curls, raises and other accessories are often logged at 15–20 reps. Such an exercise shows sessions in its log,
  a best set and a count, and the chart keeps telling the lifter to log a session. The brief scoped the message
  to "no working sets at all".
- **Fix:** when the log has entries but no week has an estimate, show a second message, for example "No set of
  12 reps or fewer in the last 8 weeks." This is new wording for Pete. Keep the current text for an empty
  history.

**F12-S2-R1-6 (Minor). The contract's "a write of another exercise emits nothing" cannot fail.**
- In `StatsQueriesContract+Library.swift:104-106`, the row's write is followed by the older bench workout's write
  before the next `values.next()`. The bridges buffer only the newest value (`.bufferingNewest(1)`), so an
  emission for the row would be replaced unseen. The same holds at `:111-113`.
- A mutant without `removeDuplicates()` would pass, so the clause's "unheard" overclaims.
- **Fix:** after the other exercise's write, race `values.next()` against a short bounded deadline (for example
  200 ms) and expect the deadline to win.
  - Or, for GRDB, pin `sessionsObservation` directly by counting `onChange` calls around an unrelated write.
  - Or drop "unheard" from the labels and record that the clause does not pin it.

**F12-S2-R1-7 (Nit, VoiceOver).**
- (a) The delta is its own stop, "+28 lb" with no context, right after the heading. The chart element then says
  "Up 28 lb over 8 weeks" again (`E1RMChart.swift:22`). Hide the delta from accessibility when the bars are
  drawn, since the chart's value speaks it. Keep it in the list layout and when the chart is empty.
- (b) "Up 28 lb over 8 weeks" is said even when the first point is W5. "Up 28 lb since W5", or dropping "over 8
  weeks", would be exact. Wording for Pete.
- (c) The spoken unit is "lb" here and "pounds" in S1's rows ("PR 195 pounds"). The stat tiles speak no unit at
  all ("219, 1RM est"). One spoken vocabulary would be better: the S1 n1 follow-up ("1 pounds") belongs with it.

**F12-S2-R1-8 (Nit).** The sessions tile's value is `String(history.sessions)` (`ExerciseHistoryPresentation.swift:61`):
"1234", in Latin digits. Its spoken text and the Library row write "1,234", or "١٬٢٣٤" in ar_EG. Format the
value with the number the counted lookup writes (`count.formatted(.number.locale(locale.forCountedText))`). The
estimate's `String(Int)` is the same nit, but it is only reachable above 999.

**Note, no change.** The GRDB observation's region is every column of `logged_set` and the joined columns, so any
set write in the database re-runs the 13 ms fetch off the main actor, and `removeDuplicates` then drops the
value. `recentObservation` has the same nature, and the screen's task ends when it disappears. Acceptable.

### The sessions caption (F12-S2-2): assessment and recommendation

**What it does.** `LibraryCopy.sessionsCaption` (`LibraryCopy+History.swift:20-26`):
1. Looks up the row's counted "%lld sessions".
2. Formats `count` again with `.number.locale(locale.forCountedText)`.
3. Deletes the first occurrence of that text and trims spaces.

**Assessment.** It is correct today for every locale the shipping catalog can answer. `forCountedText` always
resolves to English, and the two formatters agree: G1's test covers en_US, de_DE, fr_FR, hi_IN and ar_EG, and I
confirmed the grouping and digits on the host.

It is fragile in exactly the ways the brief names, and each failure is silent:
- A translation that writes the number as a word ("one session") makes `range(of:)` return nil. The tile then
  reads "1" over "one session".
- A translation where the number sits mid-phrase, or is wrapped in bidi isolates or marks, leaves those marks or
  a double space; `.whitespaces` does not trim U+200F or U+2068.
- The same digits appearing earlier in the phrase would be deleted instead.
- Two formatters must stay byte-identical for ever.
- It also breaks standards §7, which says a copy file "holds lookups and nothing else".

**Alternatives I looked at.**
1. **`AttributedString(localized:)` and `localizedNumericArgument`**, deleting the runs the formatter marks as
   the argument. I probed it on the host. For a key with plural variations, the whole string is one run tagged
   as the argument ("1,234 sessions"). It only isolates the number in plain keys ("W" + "3"). **Not viable.**
2. **Today's precedent** ("sessions this week" under "2" "/4") is a fixed plural caption. It works there only
   because the denominator makes the plural right. It does not transfer.
3. **A `StatTile` that takes the whole counted text.** It would still need to find the number to draw it large.
   That moves the same surgery into LedgerDesign. **No.**
4. **A counted caption key whose forms omit the number** ("one": "session", "other": "sessions"). This is the
   standard Apple mechanism: a plural form need not print its argument, and stringsdict and String Catalogs
   allow it. The lookup becomes a plain catalog lookup, and translators get every plural category.
   - It needs a **sanctioned exception in `StringCatalog.pluralProblems`**: for keys listed as captions (an
     allow-list in the audit, or a comment prefix the audit reads), every form holds no specifier, and the
     "other" form is the key without `%lld `.
   - It needs a key distinct from the row's "%lld sessions", for example "%lld sessions (count shown above)".
     The xcstrings key is unique per string, and the English value differs from the key.
   - It needs one paragraph in standards §7.
   - Cost: about 15 lines in `LedgerTestSupport` plus audit tests, a standards edit (an orchestrator ruling, A6
     said "no change"), and an odd-looking key.
5. **Keep the surgery, but guard it.** A `ModuleCopyTests`-style check that every form of "%lld sessions" in
   every localization of the catalog is exactly `%lld` + one space + words with no digit, so a translation that
   breaks the assumption fails CI and names this member. Move the derivation out of the copy file, into
   `ExerciseHistoryPresentation`, or keep it with a §7 note. Fix R1-8 so the value and the caption share one
   formatter. Cost: about 10 test lines.

**Recommendation.** Do **5 now**: it is cheap, it is correct for the only language that ships, and it turns the
silent failure modes into a CI failure. Record **4** as the follow-up for when the first translation is
commissioned. That is the point where 5's guard would fire, and where the audit exception earns its cost. If the
orchestrator prefers no string surgery at all in S2, 4 is the clean option. It is the only alternative I found
that is both robust and catalog-native, at about 25 lines and one standards ruling.

### Orchestrator's ruling (S2 review round 1)

Recorded by G1 as handed down, 2026-10-24.

1. **R1-1 (Major):** as G3 proposes: one pass keeping the heaviest weight per rep count (reuse/mirror
   `PersonalRecords.Tally.atReps`), Brzycki only on those candidates, best set from the same tally. Results must
   stay identical (the property/differential tests are the proof). The performance test folds 2,000 sets, budget
   unchanged at 5 ms.
2. **R1-2:** add the model build at 2,000 sets to the Nightly performance suite with a 16 ms budget. If it fails,
   build the model off the main actor (its input is Sendable, the builder nonisolated), keeping the generation
   guard. Report the measured number either way.
3. **R1-3:** use the sessions the observation emits; read only `personalRecords` per change, same generation guard.
4. **R1-4 (caption):** G3's option 5: keep the stripping for now, but move it out of the copy file (copy files hold
   lookups only, standards §7) into the presentation, have the tile number and the stripped caption use one
   formatter, and add a catalog test: every plural form of "%lld sessions" in every localization is exactly
   `%lld`, one space, then words with no digit. A comment points to the follow-up (option 4, a numberless caption
   key with an audit exception), which is Pete's call.
5. **R1-5:** when sessions exist but no week has an estimate, the chart says "No set of 12 reps or fewer in the
   last 8 weeks." (new key; wording goes to Pete). The no-session message stays.
6. **R1-6:** make "another exercise's write emits nothing" able to fail: race `next()` against a bounded deadline
   (~200 ms) and expect the deadline; prove it by temporarily removing `removeDuplicates()` (the test must fail),
   then restore and say so.
7. **R1-7:** hide the delta's own VoiceOver stop when the bars are drawn (the chart's value says it); the spoken
   summary names the actual span ("over 4 weeks" when the first point is W5; 8 when W1); speak units the way S1's
   Library rows speak them. Stat tiles unchanged.
8. **R1-8:** the sessions tile number uses the locale's number format (the same formatter as item 4).

Budget: S2 at 899 net product lines; up to about 1,000 allowed, stop and report beyond.

## Slice S2 — round 2 (G3 reviewer, 2026-10-24)

Reviewed `22699d0..7eb7490` (fix `d8b909c`) against "Orchestrator's ruling (S2 review round 1)". Read-only. Host
`swift test --filter 'LibraryCopyTests|ExerciseHistory|InMemoryContract|StatsQueriesTests'`: green (one known
issue, already there). No simulator runs.

**Verdict: approved.** No Blocker, Major or Minor. Two nits, both optional.

**R1-1 to R1-8, each resolved as ruled.**
- **R1-1.**
  - The fold walks the counted sets once into `Tally<Weight>.atReps`, then takes Brzycki of at most 12
    candidates. This is exact, because Brzycki rounded to the gram is monotonic at fixed reps.
  - The best set is the maximum of the tally on (weight, reps), as `Bests.bestSet(of:)` takes it. The weeks reuse
    the same function lazily.
  - The domain, property and differential tests are unchanged and pass.
  - The Nightly suite now folds 2,000 sets: 2.49 ms p95 against 5.
- **R1-2.**
  - The budget is 16 ms over 2,000 seeded sets (9.17 ms measured).
  - `SetTexts` caches per weight × reps, per model.
  - The model is built off the main actor.
- **R1-3.** The store keeps the emitted sessions and reads only `personalRecords`, with the generation guard
  unchanged.
- **R1-4.** The copy file now holds lookups only. `sessionsStat` sits in the presentation, one formatter gives the
  value and the stripped number, and the follow-up is named.
- **R1-5.** `noEstimate` shows when sessions exist but no week has an estimate. "Log a session…" stays for an
  empty history.
- **R1-6.** The clause can now fail. G1 proved it with a mutant that removed `removeDuplicates()`.
- **R1-7.**
  - The delta is hidden from VoiceOver where the bars speak it. It stays a stop at accessibility sizes, in list
    form.
  - The span is counted inclusively, as ruled: W5→W8 reads "over 4 weeks".
  - The unit is spoken as S1 speaks it.
- **R1-8.** The tile's number is the locale's: "1,234", and Arabic digits in ar_EG.

**(a) The model built off the main actor: can a stale model be the last one shown?** No.
- Builds never overlap. `run()` drains the marks in one loop (`for await _ in marks { await rebuild() }`), and
  each `rebuild` awaits `@concurrent model(_:)` before the loop takes the next mark. Two builds are never in
  flight in one run, so they assign `state` in order, and an older model cannot overwrite a newer one.
- A change made during a build marks the channel (`bufferingNewest(1)`), so the loop's next turn rebuilds from
  the newest sources. A transiently stale model can be shown, but it is always followed by a current one.
- This holds even for a mixed pair. `sessions` is captured before `await readRecords()`, so a records read can be
  paired with the previous sessions for one turn, and the generation keeps it from being cached.
- Across runs (`.task(id: scenePhase…)` restarts without waiting for the old task), the old run's `rebuild`
  checks `Task.isCancelled` after the build, and `readRecords` checks it before writing `sources`. A cancelled
  run's late model or records therefore never lands in the new run's state, even when the two generation
  counters coincide.

**(b) `SetTexts`.** Correct.
- The cache is per model, so the units and locale are fixed for its life.
- It is keyed by `Weight` (exact `Decimal` grams) and the reps. The text is a pure function of the key and the
  input, so a hit cannot return a wrong string.
- Even if `Decimal`'s hash ever split equal values, the cost would only be a miss.

**(c) `StreamArrivals` and the 200 ms window.**
- **No flake risk in the direction that matters.** A correct store never emits for the row's writes, so a slow
  runner only means waiting longer.
- The reads that expect a value wait up to 5 s, which is generous for a commit-to-callback hop. They used to wait
  without bound, so a broken implementation now fails in seconds.
- **The false-pass window is narrow, and the clause's order closes most of it.** A spurious emission that arrives
  after the 200 ms is queued in order, so it becomes `afterOlder` (`["1"]` rather than `["1", "2"]`) or
  `afterDelete`, and the clause still fails.
- One case can pass falsely. If the reader task is starved long enough for the bridge's buffer of one to replace
  the spurious value with the next real one, the spurious value is never seen. That needs the starvation and the
  defect at once, and it is acceptable.
- The cost is about 0.4 s per contract run per store kind.

**(d) The counted spoken-summary keys.**
- Each of the five has exactly one `%lld`, which picks the plural form. The `%@` is the pre-formatted weight.
- The `one` and `other` forms are present and marked translated, the `other` form is the key, and the comments
  match the code. The catalog audit passed in G1's gate.
- They are looked up with `forCountedText`, as standards §7 requires.
- The `one` forms are unreachable (a change needs two weeks), as the notes say. "Up 1 pounds" remains S1's n1
  follow-up.

**(e) `sessionsForms_areTheNumberThenWords`.** It guards what it claims. Every form of "%lld sessions" in every
localization must:
- start with `"%lld "`;
- continue with a letter, so a second space, a bidi mark (U+200F, U+2068) or punctuation fails;
- contain no other digit and no `%`.

A form that spells the number ("one session"), moves it to the end, or puts it mid-phrase fails. A localization
with variations other than `plural` has no `stringUnit`, so it fails too, which is conservative. Together with the
five-locale presentation test of the formatter, this is everything the stripping relies on. The `range(of:)` then
finds the leading number, because the form starts with it.

**Nits (optional).**
- **R2-1.** `StreamArrivals.next(within:)` polls every 5 ms. A `withTaskGroup` race of the stream's `next()`
  against a sleep would be event-driven. It is test support and fine as written.
- **R2-2.** "Up 28 pounds over 4 weeks" from W5 counts weeks inclusively: three weeks pass between the two points.
  This is what the ruling asked for. Pete may prefer "since W5" when he reads the wording.

## S3 — G3 review (round 1, 2026-10-26)

Reviewed `235e845..c16cce1` (S3 as built, G2's adversarial round, fix round 1) against the brief's S3, the "S3
amendments (orchestrator, 2026-10-26)", Q2/Q4/Q5 as A and §4's flags. I did not re-open the orchestrator's rulings
(N19 "counts" = working or added; S3-2's normalised stored name with `ExerciseSearch.key` unchanged; S3-4's 160-scalar
cap; C26's truncation). This review is read-only. I probed and mutated a `git archive` copy in my scratchpad, which I
have since deleted. No product or test file in the worktree changed.

**Verdict: changes required (small).** R1-1 leaves a hole in the S3-2 ruling, and it is a one-rule fix. R1-2 is
the orchestrator's call: fix it now or queue it as a follow-up. Everything else is a nit. What holds:
- Criterion 9 (create; "Barbell · Chest · Custom"; the picker test; the error lines) and criterion 10 ("Edit" for a
  custom exercise only, filled in).
- N15. The order of the rules, the primary muscle kept out of the secondary muscles in the store, the presentation
  and the Domain, and S3-5's subtraction.
- N16. One `save`. A double tap is dropped by the `phase` guard. A failure keeps the draft and Save works again. A
  cancellation before the write stores nothing and shows nothing.
- N17/Q4 and Q5 (all fields are rebuilt under the id; an `Exercise` has no field that the rebuild could lose).
- N18/Q2. `rowActions` is zipped with the rows. Only the receipt answers, and the cover closes once.
  `open(.exercise, in: .today)` selects Today and pushes. The exhaustive switch is updated in the adversarial cover.
- N19. One walk carries the last counted top weight.
- N20. One `ValueObservation` with `removeDuplicates()`. The in-memory observation is built from the same static
  helpers as the reads. The parity is proved by clause 27 and by G2's random scripts on GRDB and the fakes.
- Swift 6 isolation. The store is `@MainActor`. `save()` runs from the sheet's `.task(id: attempt)`, and
  `isSaveRunning` covers a re-entered task. The models are `nonisolated` and `Sendable`.
- `FilterChipRow.allowsMany` (one stored flag and one trait) and `ReceiptLayout`'s `onRow` (an optional closure,
  drawn as before, with F10's references byte-identical) each pay for themselves.
- The catalog has 22 keys with comments. There are no plurals in this slice, so no `%lld` forms to check, and no
  hard-coded user-facing strings.
- The line count reproduces: non-blank, non-comment product Swift is **+922 / −152 = net 770**. The code reads at
  normal density, so nothing was compressed to fit.
- Each sanctioned edit of another's test is justified and minimal (see the list after the findings).

**F12-S3-R1-1 (Minor; it closes the S3-2 ruling). A U+200D ZERO WIDTH JOINER still makes a name that draws as
another's a different name.**
- `CustomExerciseDraft+Name.swift:41-44` (`drawsNothingAlone`) keeps every ZWJ, so that emoji sequences survive.
  `ExerciseSearch.key` does not fold it, and `trimmingCharacters(in: .whitespacesAndNewlines)` does not trim it.
- Probe, against `bench` named "Bench Press" (G2's fixture):
  - `"Bench Press\u{200D}"`, `"\u{200D}Bench Press"` and `"Bench\u{200D} Press"` are each **accepted** (no
    error) and would be stored beside "Bench Press".
  - `"Bench Press\u{FE0F}"` is refused as `.duplicateName`, because diacritic folding drops the selector.
- So a pasted joiner gives two Library rows that look identical. That is the exact case S3-2 was ruled to close,
  and the file's own doc comment says "a name that draws as another's is that name".
- **Fix:** keep a ZWJ only between two scalars whose `properties.isEmoji` (or `isExtendedPictographic`) is true, and
  drop it elsewhere as `drawsNothingAlone` drops a word joiner. Add the three names above to G2's
  `invisibleCharacter_isDuplicate` arguments. G2's emoji pins (the family emoji counted as one character) are
  unaffected.

**F12-S3-R1-2 (Minor, performance). While the Library is up, every write to `workout`, `workout_exercise` or
`logged_set` costs seven statements on the database's one serial queue.**
- `GRDBStatsQueries+Library.swift:42-51` re-runs `recentlyLogged`, up to five `sessionCount`s and the
  `bestSets` window scan after each commit to the tracked tables. That includes the live workout's own set writes
  and a watch's synced sets, which can never change the value (`doneSets` reads finished workouts only).
- `GRDBStatsQueries.queue` is a `DatabaseQueue`, so GRDB runs the observation's fetch on that serial queue, and the
  next write waits for it.
- Measured on the host (Debug, M-series), over the 20,000-set seed of `StatsQueriesPerformanceTests` (scratch probe,
  since deleted):
  - one fetch: median 19.2 ms, p95 19.5 ms;
  - 20 `updateSets` writes averaged **3.2 ms each with no observer and 25.2 ms with `observeLibraryStats` running**,
    so the observation multiplies a write's cost by about 8.
- S1's design re-read the stats only when the newest workout changed. N20 asked for every workout to be followed, so
  some cost is inherent. But nothing budgets the observation itself, and the notes' "bounded by `bestSets`' 50 ms"
  is per statement, not per change.
- **Fix (cheap):**
  - Fold the session counts into `fetchRecentlyLogged`'s `GROUP BY` (`COUNT(DISTINCT workout.id) AS sessions` next
    to `MAX(started_at)`). The observation is then two statements, not up to seven, and `fetchSessionCount` stays
    only for the async query.
  - Add the observation's fetch to the Nightly `StatsQueriesPerformanceTests` under `PerformanceBudget.statsQuery`.
- **Fix (if wanted later):** a `DatabasePool` would move these fetches off the writer's queue. That is an ADR-level
  change and not for this slice.

**F12-S3-R1-3 (Nit, test robustness). The double-tap test detects its mutant only by hanging the run.**
- **Mutation M2:** I removed `!isSaveRunning` from `CreateExerciseStore.swift:110`.
- `doubleTap_savesOnce` recorded "Time limit was exceeded: 60.000 seconds", but the test process never exited, and I
  had to kill it after about 8 minutes.
- **Cause:** `WatchedExercises` (`Support/CreateExerciseTesting.swift:46-60`) keeps one `waiter`, so a second held
  read overwrites the first's continuation and leaks it. A CI run would sit until the job's own timeout.
- **Fix:** keep an array of waiters and resume them all in `releaseRead()`. Then assert `saves.count == 1` after
  both calls return, so the mutant fails in milliseconds.

**F12-S3-R1-4 (Nit). The sheet can be swiped down while it saves, and a filled draft is lost to a swipe.**
- `CreateExerciseSheet.swift:31-47` has no `interactiveDismissDisabled`. F10's `FinishSheet.swift:25` disables
  dismissal while its save runs.
- The N16 cancellation path makes a mid-save swipe safe. Still, `.interactiveDismissDisabled(store.phase ==
  .saving)` would match the codebase's own convention.
- Whether a dirty draft should ask before it is discarded is a product question for Pete. It is not a defect.

**F12-S3-R1-5 (Nit, localisation).**
- (a) The bounds in "Name must be 2–40 characters." (`LibraryCopy+Create.swift:58-64`) are literal text, but
  `CustomExerciseDraft.nameLength` owns them. Since S3-4, the same line also answers a two-character name with more
  than 160 scalars, which the line does not describe.
  - **Suggested:** a follow-up that formats the bounds from `nameLength`, with the locale's digits.
  - S3-4's case is accepted as ruled.
- (b) The "Core" movement pattern reuses the muscle group's key (`LibraryCopy+Create.swift:108`). A translator gets
  one string for two meanings (French: "Tronc" for the muscles, "Gainage" for the pattern). The widened comment
  flags it. A separate key costs four lines and removes the trap.

**F12-S3-R1-6 (Nit, simplicity).**
- `drawsNothing(_:)` (`CustomExerciseDraft+Name.swift:33-37`) and `storedName` (`:19-29`) walk the scalars with two
  near-identical filters.
- Blank is equivalent to `storedName.unicodeScalars.allSatisfy { $0.properties.isDefaultIgnorableCodePoint ||
  $0.properties.isWhitespace }`. That gives one source of truth for "draws nothing", which R1-1's fix then touches
  once.
- Optional.

**Sanctioned edits of others' tests: each is justified and minimal.**
- G2's `tags_predecessorWithoutCountedSets_isPassedOver` and the property oracle's `topWorking` and `earlier`
  restate N19, and nothing more.
- `statsReadFailsOnce_nextRun_…` and `FailingBests` / `UnreadableBests` change only what N20 changes: an ended
  stream in place of a thrown read, and recovery at the next run.
- The receipt's `tree`, `withRecords`, `done_sendsDone` and `receipt_nothingLeavesOrOverlaps` change the rows from
  static text to buttons, add the rows' actions, and still check the 44-pt targets.
- `WorkoutSaveAdversarialCover.exitFault` gains one case for the exhaustive switch.
- The protocol forwarders and stubs are each one function. The 26 → 27 clause count changes one number.
- No unrelated assertion was weakened.

**Tests: can they fail?** No assertion waits on wall-clock time. The waits are bounded (5 s, and the contract's
200 ms quiet window). No `#expect` compares a large value: the 2,002-scalar name is checked by `result == …` on an
error enum. Mutations, each in the scratch copy:

| # | Mutation | Result |
|---|---|---|
| M1 | Remove `try Task.checkCancellation()` (`CreateExerciseStore.swift:120`) | **Killed**: `cancellation_changesNothing`, 3 issues |
| M2 | Remove `!isSaveRunning` (`:110`) | Killed only by the 60 s time limit, and the process hangs (R1-3) |
| M3 | N19's `earlier = top ?? earlier` → `earlier = top` (`ExerciseHistory.swift:134`) | **Killed**: `tags_sessionsWithoutCountedSets_arePassedOver`, G2's pin, and the property oracle on many seeds |
| M4 | `libraryObservation`'s `.removeDuplicates()` → `.removeDuplicates(by: { _, _ in false })` | **Killed**: GRDB contract clause 27, and G2's random scripts ("emitted a value equal to the one before") |

**Runs (host, scratch copy of `c16cce1`).**
- `swift build --build-tests`: exit 0, 93 s.
- `swift test --filter "CreateExerciseStore|ExerciseHistoryTests|ExerciseHistoryAdversarial|LibraryStatsObservation|StatsQueries.*Contract|InMemoryContract|ReceiptRowRoute|CustomExerciseDraft|LibraryStore"`:
  - green, in 12 suites (114 tests);
  - one known issue, already present, in the in-memory contracts.
- Probes: ZWJ (R1-1) and the observation's timing (R1-2), with the results above.
- No simulator run. The orchestrator runs the gate.

## S3 — G3 review (round 2, 2026-10-26)

Reviewed `a930528..4f01731` (fix `6482559`, notes `4f01731`) against round 1 and the orchestrator's rulings. I did
not re-open the R1-2 ruling (set taps write `workout_event` only; about 20 ms per finish, edit or delete is
accepted, and `bestSets`' scan is a follow-up) or the "Core work" ruling. Read-only. I probed and mutated a
`git archive` copy in my scratchpad, which I have since deleted.

**Verdict: approved.** Each fix is correct and minimal. One nit remains (R2-1); I recommend it as a follow-up, not
a blocker.

**R1-1 (the joiner): fixed.** A ZWJ survives only if the scalar before it (past grapheme extenders and skin tones)
and the scalar after it are both non-ASCII emoji.
- **Mutation:** keeping every ZWJ again fails G2's `drawsAsAnother_isDuplicate` on the new arguments, and the
  property test on several seeds.
- **Spoof probe** (an existing name, and a new name that should be its duplicate):

  | Case | Result |
  |---|---|
  | A ZWJ at the end or start beside an emoji ("Curl 💪\u{200D}", "\u{200D}💪 Curl") | refused |
  | A letter–ZWJ–emoji and emoji–ZWJ–letter | refused |
  | A keycap, then ZWJ, then an emoji ("1️⃣\u{200D}💪") | refused: the skip passes U+20E3 and U+FE0F and reaches the ASCII "1" |
  | A bare keycap with a ZWJ | refused |
  | A digit, ZWJ, digit | refused |
  | A skin tone after a letter, then ZWJ, then an emoji | refused |
  | A double ZWJ between emoji | refused |
  | Tag characters U+E0067 and U+E007F, VS15, CGJ | refused (folded by the key) |
  | **"Curl 💪\u{200D}💪" against "Curl 💪💪"** | **accepted** |
  | **"Press ©\u{200D}™" against "Press ©™"** | **accepted** |
  | "Run 🇺\u{200D}🇸" against "Run 🇺🇸" | accepted, but it draws differently (the joiner breaks the flag pair), so it is not a spoof |

**R1-2 (the observation): fixed as ruled, and G1's claim verified.**
- **From the code:** the live workout's taps go through `GRDBWorkoutEventStore.append`, which writes
  `workout_event` alone. `materialize` is called only for a finish (`WorkoutEngine+Reduce.swift:200`), a replay
  and recovery. `updateSets` and `delete` belong to History. No SQL trigger writes the observed tables.
- **Measured** (host, Debug, the 20,000-set seed, with an observation that counts its fetches and uses the
  product's `libraryObservationFetch`):

  | 20 writes | Without the observer | With it | Fetches |
  |---|--:|--:|--:|
  | Set-tap appends (`append`) | 0.05 ms | 0.41 ms | **0** |
  | Edits (`updateSets`) | 3.5 ms | 24.0 ms | 20 |

- The fold into one `GROUP BY` is correct. The count is `COUNT(DISTINCT workout.id)` over the same `doneSets`
  group that `sessionCount` counts. The contract, G2's differential and the in-memory contract all pass.
- The Nightly line times the fetch under `statsQuery`.

**R1-3: fixed.** `WatchedExercises` keeps every held read, and the test releases both reads, then awaits both.
- **Mutation** (`!isSaveRunning` removed): the test now **fails in 0.012 s** with `saves.count == 1`, and the run
  exits (exit 1 after 7 s, the build included). It used to hang.

**R1-4: fixed.** `.interactiveDismissDisabled(store.phase == .saving)`, as `FinishSheet` does.

**R1-5: fixed.**
- (a) `"Name must be %@–%@ characters."` takes the bounds from `CustomExerciseDraft.nameLength`, formatted by the
  locale. It is tested in en_US and ar_EG, and the catalog key matches the interpolation.
- (b) "Core work" has its own key and comment, and the muscle's comment is back to the muscle alone (as ruled).
  G1 re-recorded the seven references for that chip alone.

**R1-6: fixed.** `drawsNothing` is derived from `storedName`, so there is one reading of "draws nothing". A lone ZWJ
is dropped, so it is still blank.

**Lines.** The count reproduces: +959 / −152, **net 807**, still under 1,000.

**F12-S3-R2-1 (Nit, follow-up). A ZWJ between two emoji that form no sequence draws as the plain pair, but counts
as a different name.**
- Seen in the probe: "Curl 💪\u{200D}💪" is accepted beside "Curl 💪💪", and "Press ©\u{200D}™" beside "Press ©™".
- **Reach:** it needs an existing name with two emoji side by side, plus a pasted joiner, so it is narrow.
- **Exact fix:** keep a joiner only inside a recommended (RGI) ZWJ sequence, which needs Unicode's emoji-sequence
  data. That is not worth it in this slice.
- **Cheap fix:** fold U+200D out of `ExerciseSearch.key` in the queued key-folding follow-up. The cost is that a
  real sequence equals its parts ("👨‍👩‍👧" = "👨👩👧"), which is acceptable for a duplicate check.

**Runs (host, scratch copy of `4f01731`).**
- `swift build --build-tests`: exit 0, 87 s.
- `swift test --filter "CreateExercise|CustomExerciseDraft|ExerciseHistory|LibraryStatsObservation|StatsQueriesTests|InMemoryContract|LibraryStore|LibraryCopy|ReceiptRowRoute"`:
  - green, 168 tests;
  - one known issue, already there.
- Probes (spoofs, and timing with fetch counts) and two mutations, with the results above.
- No simulator run.
