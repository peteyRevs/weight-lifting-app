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
