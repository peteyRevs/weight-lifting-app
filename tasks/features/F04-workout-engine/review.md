# F04 — review

Reviewer pass, 2026-09-29. Branch `feat/F04-workout-engine` at `92313c0` (main merged in; merge base
`638013d`). Diff: `git diff main...HEAD`, 74 files. Reviewed against the brief, engineering standards
(§10 as amended 2026-09-29), architecture §6, ADR-004 with its amendments, the reviewer's seven points, and
the settled decisions in `implementation-notes.md` (the "Orchestrator decision" sections, the remote-haptics
correction and "Re-plan (2026-09-29)").

**Verdict: approve. 0 Blocking, 5 Should fix, 7 Nits.**

The engine code is correct against the brief, ADR-004 and the settled decisions. Every Should fix is a doc
or hand-off edit, plus one line in a test. None touches `LedgerDomain` code, so F04 stays frozen. They are
cheap, and they should land in this PR before the merge.

## How this was checked

| Check | Result |
|---|---|
| `/code-review` at `high` on the diff | 10 candidates; how each was handled is at the end |
| `scripts/check.sh --fast` | **OK**: format clean, lint `--strict` clean, 675 tests in 111 suites, 15 s |
| `swift test --filter LedgerDomainTests --enable-code-coverage`, then `llvm-cov report` | 673 tests pass. `Engine/` **345/346 lines = 99.71 %**; the one miss is the unreachable `default:` at `WorkoutEngine+Reduce.swift:44`. 100 % of functions. `RestTimer.swift` and `WorkoutState.swift` 100 % |
| Code-only line count | Reproduced; see "PR size" |
| Not run | The full simulator gates (the tester's), and the nightly `ReplayPerformanceTests` (see the note below) |

**Note: another agent's files.** During the review, three untracked files appeared in this worktree:
`Engine/Adversarial/Round4{EffectsRest,ExtremeDate,WellFormed}AdversarialTests.swift`. They look like
another agent's work in progress.
- When I saw them they did not compile: `EngineScenario` has no member `run`, and there were missing `try`s.
- They are not part of `92313c0`.
- My runs above came before they appeared: the test counts match the implementation notes exactly.
- They blocked my re-run of the nightly 5 ms replay test, which I did not re-verify.

## Blocking

None.

## Should fix

### S1. The own action's "`reduce` equals `replay`" claim fails once the drift bound withholds a stored stamp

**Where:**
- `LedgerKit/Sources/LedgerDomain/Engine/WorkoutEngine.swift:23-26`;
- `docs/adr/ADR-004-event-sourced-workout-engine.md:142-146` and `:153-156`;
- `LedgerKit/Sources/LedgerDomain/Protocols/WorkoutEventStore.swift:34-35`;
- `tasks/features/F17-live-sync.md:133-135` and `:152-154`.

**How the claim breaks.** The ADR says the host appends every received envelope "whatever they hold".
Recovery "skips a stored stamp that its drift bound would reject on receipt". A drift bound that rejects a
stamp on receipt does the same thing. So the store can hold a well-formed envelope stamped later than the
HLC's `newest`. Then the own-action rule is no longer true: "the HLC sorts the envelope after everything
stored, so reducing it on the host's state gives what `replay` of the log with it would give".

**Failure:**
1. The watch's clock runs an hour ahead, beyond F17's bound. Its `setLogged` for set (0, 1) is stored on
   the phone, and the rebuild shows the set done.
2. The lifter un-logs it on the phone. `reduce` shows the set undone; the phone persists and transmits
   the un-log.
3. The un-log sorts before the watch's envelope. So the phone's own log, and the watch's rebuild, both
   replay the set as done.
4. On the phone's next rebuild, `effects(from:to:)` sees a newly done set. The screen flips back and the
   phone **buzzes** as if the watch had just logged it.

Losing an update to clock skew is already a documented limitation ("clock skew decides last-writer-wins").
What nothing acknowledges is that a host's screen can leave its own log.

**Second gap: a non-finite stamp.** Store contract clause 9 keeps malformed envelopes. So "the largest
stored `wallClock`" can be non-finite. With `+∞`, every later own envelope is stamped `+∞`, and `reduce`
drops it as malformed: no `.persist`, no `.transmit`, no error, and every action is lost. F17's decode guard
(item 5) keeps such stamps off the wire, but the recovery rule should not depend on it.

**Fix (docs only):**
- In the `reduce` doc, ADR-004's "Its own action" bullet and F17 item 1, state the precondition. The host
  reduces its own envelope only when the stamp sorts after every well-formed stored envelope. Otherwise
  (the drift bound withheld a later stamp), it appends the envelope, rebuilds with `replay`, and runs
  `effects(from:to:)` plus `.transmit`.
- In ADR-004's "Recovery on launch", the `uncompactedWorkoutIDs` doc and F17 item 3, write "the largest
  `wallClock` among well-formed stored envelopes (`EventEnvelope.isWellFormed`)".
- The protocol doc (`WorkoutEventStore.swift:34-35`) also leaves out the drift-bound skip that the ADR
  states. Make the two say the same.

### S2. F05 and F10 still specify the pre-F04 engine; the hand-off reached only F17 and F23

**F10 is the first host.** ADR-004:109 names "the host (F10/F17)", and F10 ships in M1, before F17. Its brief
still says:
- `tasks/features/F10-active-workout.md:52`:
  - it uses `.persistEnvelope`, `.transmitEnvelope` and `.saveToHealth`, none of which exist;
  - it runs `.haptic` only when `origin == thisDevice`.
- `:64`: `restExtended(by:)`. The store has no decision about `extendsShownRest` or `tappedAt`.
- `:46`: "local intent → EventEnvelope(device, seq) → reduce → persist". There is no HLC.
- `:69`: criterion 12 resumes a workout that finished but was not materialised. That is now the launch
  step over `uncompactedWorkoutIDs`.

Even with no peer, a phone that stamps raw clocks loses an un-log after an NTP step-back or a relaunch
(findings 6 and 12).

**F05** (`tasks/features/F05-persistence.md`):
- `:97` still has `liveWorkoutIDs()`.
- `:67` has `wall_clock TEXT` with no precision rule.
- `:92` does not say that materialisation receives `.materialize(WorkoutState)` and computes the receipt
  through `WorkoutEngine.summary`.
- It never mentions:
  - running `WorkoutEventStoreContract.violations` against the GRDB store;
  - `append` returning the new envelopes, all or nothing;
  - deleting a materialised workout when a late discard overtakes its finish.

F17 item 8 notes that F05's brief is stale. But F05's implementer will not read F17's brief.

**Fix (docs only):** append "Inputs from F04 (2026-09-29)" to both briefs. Point to F17's section for the
shared rules, and list what each needs:
- **F10:** HLC stamping and its recovery; the effect names; how the store sets `extendsShownRest` and
  `tappedAt`; the launch step; `.persist` before `.transmit`.
- **F05:** the contract suite; lossless dates; `uncompactedWorkoutIDs`; `.materialize(WorkoutState)` plus
  `summary`; a late discard that overtakes a finish.

### S3. `docs/architecture.md` §6 and ADR-004's sketch still show the superseded API

**Where:**
- `docs/architecture.md:235-248` shows `public struct WorkoutEngine`, a non-optional
  `reduce(_ state: WorkoutState, _:)`, `replay(_:) -> WorkoutState`, `persistEnvelope`, `transmitEnvelope`
  and `saveToHealth`. It has no `effects(from:to:)`, `.materialize` or `.discardLog`.
- `docs/adr/ADR-004-event-sourced-workout-engine.md:24-50` shows the same kind of sketch: SlotID-addressed
  events, `restExtended(by:at:)`, a non-optional `reduce`. Nothing points to what shipped.

The review brief asks that the docs, ADR-004 and F17's inputs say the same thing. These two places don't.

**Fix:**
- Replace §6's code block with the shipped signatures, or with a pointer to `LedgerDomain/Engine` and
  the ADR amendment.
- Add one line under ADR-004's sketch: "Illustrative. The shipped API is F04's: see the amendment and F17
  'Inputs from F04' item 7."

### S4. One conflicting envelope blocks a whole received batch, and no rule says what the host does next

**Where:**
- `LedgerKit/Sources/LedgerDomain/Protocols/WorkoutEventStore.swift:11-13` (all or nothing; settled);
- `tasks/features/F17-live-sync.md:136-138` ("append every envelope … first").

**Failure.** A device can reuse a seq: the tester names a watch that recovers with a truncated log
(test-findings, finding 7), and a restore from backup can do the same.
1. The reused seq arrives inside a gap-replay batch.
2. `append` throws `conflictingEnvelope` and stores nothing from the batch.
3. The next handshake resends the same batch, and it fails the same way.

So every valid envelope in that batch is lost too, and the devices never converge. The atomicity is
settled. Nothing acknowledges this consequence.

**Fix (F17 item 1, docs only; keeps the atomicity):** add: "On `conflictingEnvelope(key)`, drop the
envelopes with that key from the batch, log it (`os.Logger`, no health values) and append the rest. Never
retry a batch unchanged."

### S5. An unseeded shuffle in an adversarial test

**Where:** `LedgerKit/Tests/LedgerDomainTests/Engine/Adversarial/Round3HostAdversarialTests.swift:144`:
`watch.outbox.shuffled()` uses the system generator.

It is the only unseeded randomness in the engine suites. If a regression made the host depend on arrival
order, this test would fail only sometimes, and the failing order could not be reproduced. That breaks
engineering-standards §9 and testing-strategy §3 rule 5.

**Fix:** `var generator = SeededGenerator(seed: 144)`, then `watch.outbox.shuffled(using: &generator)`. Or
loop over a few fixed permutations.

## Nits

- **N1. "Never shortens" is stated without its condition.** ADR-004:129 says, in bold, that "+30s" never
  shortens a running rest.
  - On a shown rest, `WorkoutEngine+Reduce.swift:182` caps `endsAt` at `tappedAt + longestRest`, so a
    running rest that ends more than an hour after the tap gets shorter.
  - With no time windows this can happen: a peer whose clock is hours ahead puts an automatic rest hours
    out.
  - Fix: qualify the sentence ("…when the screen showed none"), which is what `WorkoutEvent.swift:41-43`
    already says. If the rule is meant to hold always, use `max(running.endsAt, min(…))` instead.
- **N2. Two effect docs are incomplete** (`Effect.swift:32-38`):
  - `.discardLog` says only "drop the discarded workout's log". `effects(from:to:)` also emits it when a
    late discard overtakes a finish that was already materialised (`WorkoutEngine+Replay.swift:43-48`).
    F05 must then delete the workout too (F17 item 2).
  - `.materialize` promises re-materialisation, but that holds only until the log is compacted (F17
    item 8).

  Say both.
- **N3. One stale phrase.** `EventEnvelope.swift:13` says the receiving host "checks keys the same way
  before it reduces". The host never reduces a received envelope. Fix: "…through `WorkoutEventStore.append`,
  before it rebuilds".
- **N4. The "Rules → tests" table is out of date.** The DoD asks for this table
  (`implementation-notes.md:29-42`). Row 9 still lists `extend_atExactEnd_startsFreshRest`, which fix
  round 2 deleted. The table also lacks:
  - `extend_followsTheLiftersIntent_notTheClock`, `extend_unshown_neverShortensARunningRest` and
    `longestRest_holdsGrownRests` (rule 9);
  - `Round3EffectsAdversarialTests.startedWithRest_reduceSchedulesItToo` (rule 1);
  - `EffectsFromToTests` and `EnvelopeWellFormedTests`.

  Refresh the table.
- **N5. Repeated work in `logSet`** (`WorkoutEngine+Reduce.swift:78-88`):
  - it computes `SupersetRounds.blocks` before the `wasDone` guard;
  - `isLastOfRound` and `displayOrder` (twice) each rebuild the rounds;
  - `reduce` compares the whole state (`next == state`, `WorkoutEngine.swift:48`).

  All of it stays O(sets) and within the replay budget. No action while F04 is frozen; move `blocks`
  below the guard the next time this file is opened.
- **N6. State both size figures in the PR body.** Under §10, the orchestrator ruled `LedgerTestSupport`
  (465 lines) to be test code, so the product count is 392. All of `Sources` together is 857, which is over
  the 500 target. Put both figures and the ruling in the PR body, so that a reader applying §10 literally
  does not ask for the split line.
- **N7. A snapshot's cursor is not bounds-checked.** That is by decision ("nothing else is checked"), and
  `logSet` keeps whatever cursor it has (`?? cursor`, `WorkoutEngine+Reduce.swift:88`). So F10, F18 and F21
  must bounds-check `cursor` before they index `exercises`. Say so in the `WorkoutState.cursor` doc or in
  S2's hand-off.

## `/code-review` candidates, and what became of them

| Candidate | Outcome |
|---|---|
| The atomic `append` loses a whole batch on one conflict | **S4** |
| HLC recovery takes an unfiltered maximum (`+∞`) | Folded into **S1** |
| A late discard after a materialised finish leaves the workout in history | Acknowledged (F17 item 2). The doc gap is **N2** |
| The new `units` and `programUpdates` keys break decoding of older `WorkoutState` payloads | Not taken. Nothing is shipped or persisted (notes, deviation 4), and compatibility across builds belongs to F17's versioned codec. F17 should know that `WorkoutState` has no decode defaults |
| Re-materialisation stops working after compaction | Acknowledged: F17 item 8, and the notes' "Open for F05 and F17" |
| A snapshot's `cursor` is not validated | By decision. The note for consumers is **N7** |
| `nextCursor` moves to a done first row of the next block, or stops at an empty block | Not taken. This is spec rule 20 and brief rule 3(b) word for word ("first set of the next block"), and a slot has at least one set |
| `setAdded` with a NaN `doneAt` is rejected, although `doneAt` is dropped | Not taken: Pete's rule ("a date it carries"), finding 16b |
| `programUpdates` keeps B after a later one-off swap back to A | Not taken. Decision #13 says a swap is one-off unless the toggle is on, so a one-off swap leaves the program alone (implementer decision 8) |
| Rounds rebuilt repeatedly; `reduce` compares the whole state | **N5** |

## The seven review points

1. **Module boundaries.**
   - Every changed source in `LedgerDomain` imports only `Foundation`. `LedgerTestSupport` adds
     `LedgerDomain`.
   - `Package.swift`, `Ledger.xcodeproj`, the lint config and `scripts/` are untouched.
   - The diff touches only `LedgerDomain` (11 files), `LedgerTestSupport` (3), `LedgerDomainTests` (55),
     ADR-004 and four task docs.
   - Every file outside the brief's Touches is documented: `RestTimer`, `WorkoutState`, `SessionBuilder`,
     `ModelOracle+Edits`, `ProtocolsAdversarialTests` and `RestTimerTests`.
2. **Concurrency and purity.**
   - The engine has no `Date()`, `UUID()`, `.now`, randomness, `static var`, `@unchecked`,
     `nonisolated(unsafe)` or locks. `longestRest` is an immutable `Sendable` constant.
   - Every public type is `Sendable`. `WorkoutEventStore` is a `Sendable` protocol with async methods.
   - **Determinism.** `replay` filters with `isWellFormed`, sorts by `(wallClock, device, seq)`, picks the
     workout of the first usable `started`, dedupes by key, moves that `started` to the front, and folds
     with `step`.
     - Under the documented key precondition, that is a function of the envelope set.
     - The only case that depends on arrival order is a key conflict that also ties on `wallClock`. The
       store rejects it.
     - `Set` and `Dictionary` are used only for membership and equality, never for iteration order.
     - NaN never reaches the sort.
3. **Error handling.**
   - `EngineError.conflictingEnvelope` is the only error, and it belongs to the store contract.
   - The product code has no `try?`, `try!`, `as!` or force unwrap.
   - The reducer ignores unusable input by rule and never fails.
4. **Design fidelity:** not applicable; there is no UI.
5. **Accessibility:** not applicable.
6. **Test quality.**
   - The suites assert behaviour: exact effect lists, whole states, and seeded properties over
     `PropertySeed.all` (`LEDGER_PROPERTY_SEED_COUNT`).
   - `ModelOracle` never calls `WorkoutEngine` or `SupersetRounds`, and the notes record the four mutants
     it killed. The store contract suite kills 14 mutants.
   - There are no sleeps. No test reads the wall clock except the brief's own measured timing test, which
     is `.slow` and nightly only.
   - One flakiness vector: **S5**.
   - The `foldOrder_*` tests pin an internal order, but each is paired with a `replay` assertion. That is
     acceptable.
7. **Brief compliance.** Every acceptance criterion and every reduction rule has a test (table below). The
   deviations are documented and settled:
   - no `now:` parameter;
   - the renamed labels;
   - `.materialize(WorkoutState)`;
   - `uncompactedWorkoutIDs`;
   - the order of effects.

**Also checked:**
- **API naming and doc agreement.** The code, the ADR-004 amendment and F17 "Inputs from F04" agree on:
  - `restExtended(amount:extendsShownRest:tappedAt:)`;
  - `effects(from:to:)` and its single set haptic, only while live;
  - `isWellFormed` (only non-finite dates and out-of-range rest lengths);
  - `longestRest`;
  - `uncompactedWorkoutIDs`;
  - the host loop.

  The exceptions are S1 (the own-action precondition and the recovery filter), S3 (architecture §6 and the
  ADR sketch), N1 and N3.
- **F02 types changed only additively.**
  - `WorkoutState` gains `units` and `programUpdates`, both with init defaults.
  - `SessionBuilder` snapshots `units`.
  - `RestTimer.remaining`/`fraction` and `elapsed` change only where they used to trap.
  - `WorkoutEventStore` replaces F02's reserved empty protocol, which has no conformers on `main`. The one
    test that conformed to it is edited (deviation 5).
  - No persisted fixture exists.
- **PR size, reproduced.** Measured with `git diff main...HEAD` from the merge base `638013d`, counting `+`
  and `-` lines that are not blank and do not start with `//`:

  | Path | Added | Deleted | Changed |
  |---|---|---|---|
  | `LedgerKit/Sources/LedgerDomain` | 387 | 5 | **392** |
  | `LedgerKit/Sources/LedgerTestSupport` | | | 465 |
  | All of `LedgerKit/Sources` | | | 857 |
  | `LedgerKit/Tests` | | | 6,431 |

  A plain `--numstat` for `LedgerDomain` gives 694 + 10 = 704. The implementer's 392 is correct and under
  the 500 target (N6).
- **`Ledger.xcodeproj`:** not touched.

## Criteria → evidence

Test files are under `LedgerKit/Tests/LedgerDomainTests/Engine/`.

| # | Brief criterion | Evidence | Status |
|---|---|---|---|
| C1 | Seed session, set 0 logged: rest `at + 150 s`, cursor (0, 1), haptic and schedule | `ReduceSetLoggedTests.criterion1_firstSet_startsRestAndAdvances` | Met |
| C2 | Superset A1: no rest, cursor B1. B1: 90 s rest, cursor A2 | `ReduceSetLoggedTests.criterion2_superset_restsAfterRound_roundRobin` | Met |
| C3 | Last set of exercise 0 logged: cursor (1, 0) | `ReduceSetLoggedTests.criterion3_lastSetOfExercise_movesToNextExercise` | Met |
| C4 | Un-log keeps the cursor and the rest | `ReduceUnlogTests.criterion4_unlog_keepsCursorAndRest` | Met |
| C5 | "+30s" with no rest: `RestTimer(now + 30 s, 30 s)` | `ReduceRestTests.criterion5_extendWithNoRest_startsRestFromNow`, with both flag values | Met: `now` is `tappedAt` (deviation 1, decision B) |
| C6 | After `finished`: state unchanged, no effects | `ReduceTerminalTests.criterion6_afterFinished_everythingIsIgnored`, 13 event kinds | Met |
| C7 | 100 shuffles give identical states | `ReplayTests.criterion7_shuffled100Times_sameState`: 61 envelopes, seeded | Met |
| C8 | A duplicated log equals the deduplicated replay | `ReplayTests.criterion8_duplicatedLog_equalsDedupedReplay` | Met |
| C9 | A partition, then heal: both devices converge | `ConvergenceTests.criterion9_partition_thenHeal_converges`, plus the `randomPartition_converges` property | Met |
| C10 | 1,000 seeded sequences match `ModelOracle` at every step | `ModelOracleTests.reduce_matchesOracle_atEveryStep`: 200 seeds × 5 = 1,000 on the PR lane, 10,000 nightly. Also `replay_matchesOracleReplay` | Met |
| C11 | W's 190 at t = 10 beats P's 195 at t = 9, in any order | `ReduceTargetLWWTests.criterion11_laterWallClockWins_inAnyArrivalOrder` | Met |
| C12 | `alsoUpdateProgram` survives the finish | `ReduceAddRepeatSwapTests.criterion12_programUpdate_survivesFinish`, through `.materialize(WorkoutState).programUpdates` | Met (round 1, decision 8) |
| R1 | `started` on `nil`; a second one ignored; earlier events buffered | `ReduceStartedTests` (7 tests); `ReplayTests.foldOrder_*`; `Round3EffectsAdversarialTests.startedWithRest_reduceSchedulesItToo` | Met |
| R2 | Terminal: everything later is ignored | `ReduceTerminalTests`: criterion 6, `afterDiscarded_everythingIsIgnored`, `firstTerminalWins` | Met |
| R3 | `setLogged`: values, rest on the round's last row, cursor per rule 20 | `ReduceSetLoggedTests`: criteria 1–3, wrap, stay, auto rest off, re-log, clamp, unknown set, drop round | Met |
| R4 | `setUnlogged` moves neither the cursor nor the rest | `ReduceUnlogTests` (3 tests) | Met |
| R5 | `setTargetChanged`: last writer wins per field; clamped | `ReduceTargetLWWTests` (4 tests) | Met |
| R6 | `setAdded`: idempotent by ID; appended | `ReduceAddRepeatSwapTests.setAdded_appendsUndoneAddedRow`, `setAdded_isIdempotentBySetID` | Met |
| R7 | `allSetsRepeated` writes every row; done flags kept | `ReduceAddRepeatSwapTests.allSetsRepeated_writesEveryRow` | Met |
| R8 | `exerciseSwapped` replaces the identity only; program updates | `ReduceAddRepeatSwapTests.exerciseSwapped_replacesIdentityOnly`, `programUpdates_latestPerSlot`, criterion 12 | Met |
| R9 | Rest: start, extend, fresh on none, skip | `ReduceRestTests`: criterion 5, `extend_runningRest…`, `extendTwice…`, `extend_afterRestIsOver…`, `extend_followsTheLiftersIntent_notTheClock`, `extend_unshown_neverShortensARunningRest`, `longestRest_*`, `restStarted_isAbsolute`, `skip_clearsRest` | Met (see N1) |
| R10 | `finished` / `discarded`: phase, `endedAt`, effects | `ReduceTerminalTests.finished_endsAndMaterializes`, `discarded_endsAndDropsLog`, `stillLifting_finishOpenedLater_endsAtTheLastSet`; `EffectTests.effects_finished` | Met |
| R11 | `exerciseSelected` only onto a row that exists and is undone | `ReduceSelectTests` (3 tests, 4 cases) | Met |
| R12 | Convergence: order-independent, duplicate-tolerant, total tie-break | `ReplayTests`; `ConvergenceTests`; `EnvelopeOrderingTests` (including `order_isTotal_andMatchesUUIDStringOrder`); `EffectsFromToTests` properties | Met, under the key precondition |
| NF | `replay` of 500 envelopes < 5 ms; no `Date()` in the engine | `ReplayPerformanceTests` (nightly; median 1.8 ms per the notes, **not re-run here**); grep shows no clock reads | Met by the notes; the clock rule verified here |
| DoD | `Engine/` coverage ≥ 95 %; notes map every rule to a test | 99.71 %, re-measured; the notes' table exists but is stale in one row (N4) | Met |

## Verdict

**Approve: G3 passes with zero Blocking findings.**
- S1–S4 are doc and hand-off edits: ADR-004, the doc comments in `WorkoutEngine.swift`,
  `WorkoutEventStore.swift` and `EventEnvelope.swift`, architecture §6, and the F05, F10 and F17 briefs.
- S5 is a one-line change in a test.

Land them in this PR before the merge, or at the latest before F05 or F10 starts. None of them changes how
the engine behaves.
