# F10 — test findings

## Slice S1 — round 1 (G2 tester, 2026-10-04)

Independent adversarial pass over `feat/F10-s1-session-seam` at `c972f5d`: the `WorkoutSessionClient` protocol with
`WorkoutSessionUpdate` and `WorkoutSessionError`, the `workoutSession` key with its stub and preview value,
`FakeWorkoutSessionClient`, the shared `WorkoutSessionClientContract`, and `ClockText`.

**How I worked.** I read the brief (its "Plan amendments" hold S1's eight criteria), ADR-004 with its amendments,
ADR-008, architecture §6 and §13, the standards and the testing strategy, then the seam's public surface and doc
comments. Expected values come from the criteria and from `WorkoutEngine.reduce`, run by `SeamOracle` in my
support files. I have not read `implementation-notes.md`. No product code, contract or implementer test was
edited, and nothing was committed.

Independence, exactly: the suites on the fake, `ClockText`, the update type and the key, the differential model,
and 36 of the wrong clients were written and run before I read any function body, any clause or any test of the
implementer's. Before that point I had seen only declarations and doc comments (my grep of the contract files also
showed a few `var` lines inside bodies), the tag names in `LedgerSyncTests/Support/Tags.swift`, and the three
`LedgerDependenciesTests` files as they are on `main`, for their patterns. After reading the contract I added six
wrong clients aimed at what its clauses do not exercise (`.terminalApplyMovesTheEnd`,
`.judgesSnapshotsByPhaseAndStart` and the four of F10-S1-4), the documenting test of F10-S1-1 on the contract,
and I turned my race tests into checks that any client can be put through.

**Convention** (as in F04, F05 and F07): a bug or a contract gap has a failing test that stays failing until the
fix. A spec question is pinned by a passing test marked "(documents …)", which fails once the behaviour I propose
is adopted.

### Summary

| # | Severity | Finding | Failing test |
|---|---|---|---|
| F10-S1-1 | spec question | `finish` and `discard` with an end date that is not finite return as if they had worked, and the workout stays live | none (3 documenting tests pass) |
| F10-S1-2 | bug (minor) | A fake whose clock is not finite refuses every start as `notStartable` and ignores every event | `stamp_nonFiniteClock_changesNothing` (3 cases) |
| F10-S1-3 | contract gap | The one concurrent clause accepts updates published out of order | `racyClient_isRejectedByAClause` (1 of its 5 failing cases) |
| F10-S1-4 | contract gap | No clause overlaps a start, an end or a subscription with another call | `racyClient_isRejectedByAClause` (4 of its 5 failing cases) |
| F10-S1-5 | contract gap (minor) | `notStartable` is checked for two ended snapshots and one start date only | `faultyClient_isRejectedByAClauseOrAScript` (1 of 32 cases) |
| F10-S1-6 | test-quality | Two clauses compare the client with itself, and eight clauses have no fault that shows they can fail | none (noted in `notForTheClauses`) |

The fake itself held against everything I threw at it except F10-S1-2. The contract is strong on calls made one
after another (31 of my 32 one-fault clients are rejected) and thin where calls overlap, which is where the S2
host, an actor that awaits its store and its recovery, is most likely to go wrong.

### F10-S1-1. spec question — `finish` and `discard` with an end date that is not finite

- **Rule.** Brief, "Plan amendments", criterion 4: "Given a live workout, `finish(endedAt:)` returns the finished
  state, publishes it in one update, and afterwards `current()` is nil and a new stream starts with a nil state;
  `discard(endedAt:)` likewise." Standards §8: "Errors are never swallowed."
- **Repro.** `finish_nonFiniteDate_returnsTheWorkoutStillLive_contraryToCriterion4` and
  `discard_nonFiniteDate_returnsNormally_leavingTheWorkoutLive` (`FakeSessionEndingAdversarialTests`), each for +∞,
  −∞ and NaN: start the seed session, log two sets, call `finish(endedAt: .infinity)`.
- **Expected** (criterion 4, read literally): the finished state, or a refusal.
- **Actual.** `finish` returns the workout with `phase == .live` and `endedAt == nil`, publishes nothing, and
  `current()` is still the live workout. `discard` returns normally and discards nothing; the caller's next
  `start` throws `workoutInProgress` (the brief's "Discard and start new" path).
- **Judgement.** The behaviour follows ADR-004 ("Malformed envelopes": no state change and no effects) and is
  written in the protocol's doc comments, so it is a deliberate reading, not an accident. It still contradicts
  criterion 4 as written, and the caller cannot see it: `finish` hands back a live workout through the return type
  that means "finished", and `discard` hands back nothing at all. No caller passes such a date while end dates come
  from `@Dependency(\.date)`.
- **The contract pins it.** Its "ignored" clause calls `finish(endedAt: never)` and `discard(endedAt: never)` and
  expects the workout back unchanged, so the S2 host must behave this way too. A client that throws instead is
  rejected (`clientThatThrowsForANonFiniteEnd_isRejectedByTheContract`, passing, documents).
- **Question for Pete or the orchestrator.** Either add the exception to criterion 4, or have both calls throw
  (a new `WorkoutSessionError` case) so that a caller never treats a live workout as finished or discarded.
  Deciding before S2 matters, because S7's finish flow and the watch will code against whichever it is.

### F10-S1-2. bug (minor) — a fake whose clock is not finite refuses everything

- **Rule.** `FakeWorkoutSessionClient`'s documentation: "Nothing a caller can observe depends on the stamp."
- **Repro.** `stamp_nonFiniteClock_changesNothing` (3 cases): `FakeWorkoutSessionClient { Date(timeIntervalSinceReferenceDate: .infinity) }`,
  then `start(Seam.session(1))`.
- **Expected.** The workout starts, and a logged set returns the engine's state.
- **Actual.** `start` throws `notStartable(id)` for a snapshot the engine starts, `current()` stays nil, and every
  later `apply` is refused. The stamp's wall clock makes every envelope malformed, so the engine ignores all of
  them.
- **Why minor.** Only a test or preview that injects such a clock meets it, and it is loud. The error names the
  wrong cause, though, and the `now` parameter has no other observable effect (a finite clock running backwards a
  day per call changes nothing: `stamp_deviceAndABackwardsClock_changeNothing`, 20 seeds). Fix: stamp with a fixed
  finite date when `now()` is not finite, or drop the parameter.
- **Note for S2.** The host has the same shape: an own envelope whose stamp is not finite would make `start`
  throw `notStartable` for a startable snapshot. ADR-004's recovery rule guards the stored stamps; nothing yet
  says what `start` throws when the host's own clock is at fault.

### F10-S1-3. contract gap — the concurrent clause accepts updates published out of order

- **Rule.** `WorkoutSessionClient.updates()`: "then one update for every event the engine accepts, in the order
  they were applied." Criterion 1: "every later change arrives in order". Criterion 3: `apply` returns "the state
  after the event, equal to the next update's state".
- **Repro.** `racyClient_isRejectedByAClause(.racyScrambled)` (`SessionContractBiteAdversarialTests`).
  `WrongSessionClient(.racyScrambled)` commits overlapping applies in turn, as it should, then publishes their
  updates with the first two swapped and the last in place. A subscriber sees an edit appear, vanish and return.
- **Expected.** Some clause complains.
- **Actual.** `violations(of:)` returns nothing: 0 of 300 runs in exploration, 0 of 10 in the committed test.
  The clause "callers at once" checks the number of updates, the first one, the last one's state, that the
  published states and the returned states are the same set, and that both subscribers agree. It never checks that
  an update follows from the one before it. My `SeamHistory` check rejects the same client
  (`racyClient_isRejectedByThisSuitesOverlapChecks`).
- **Why it matters.** The host reduces, awaits its store, then publishes, and an actor is re-entrant at every
  await. A host that commits before the await and publishes after it can publish out of order; today the contract
  notices only when the stale update happens to be the last of the burst. A screen would show a logged set as not
  logged until the next change.
- **Fix.** In `callersAtOnce`, walk the first subscriber's stream: each update must be the engine's update of the
  state before it for exactly one of the edits not yet seen. About fifteen lines; `SeamHistory` in
  `SessionSeamHistoryAdversarialSupport.swift` does it for adds and logs.

### F10-S1-4. contract gap — no clause overlaps a start, an end or a subscription with another call

- **Rule.** The protocol's documentation: `start` throws "`workoutInProgress` while one is" live; `finish` "Ends
  the live workout … which one last update carries"; `updates()` returns a stream "registered before the call
  returns, so it misses no later update".
- **Repro.** `racyClient_isRejectedByAClause`, four cases. Each client is correct when calls come one at a time
  and has one suspension between a check and its commit:

  | Client | What it does when calls overlap |
  |---|---|
  | `.racyDoubleStart` | every overlapping `start` succeeds; the last one's workout replaces the others |
  | `.racyDoubleEnd` | every overlapping `finish` and `discard` returns an ended state and publishes one |
  | `.racyApplyAfterEnd` | an `apply` that overlaps a `finish` is published after the finished update and returns a live state |
  | `.racyLateRegistration` | a stream opened during applies starts at one update and misses those published before it was registered |

- **Expected.** Some clause complains.
- **Actual.** All 17 clauses accept all four: 0 of 100 exploration runs each, 0 of 10 in the committed test. The
  only clause with overlapping calls is 18 commuting stepper edits; `start`, `finish`, `discard` and `updates()`
  are only ever called alone.
- **Why it matters.** These are the reentrancy faults an actor with awaits inside is prone to, and criterion 5
  ("every protocol method waits for recovery") puts an await at the top of every host method. Two starts from a
  double tap would leave two logs in the store; two ends would publish two receipts.
- **Fix.** Four clauses. The checks exist and pass on the fake: `Seam.startRaceFault`, `Seam.endRaceFault`,
  `Seam.applyVersusEndFault` and `Seam.lateJoinFault` (`SessionSeamRacesAdversarialSupport.swift`). Together with
  the history check they reject each of these clients in 100 of 100 exploration runs
  (`racyClient_isRejectedByThisSuitesOverlapChecks`, 10 cases, is the committed form).

### F10-S1-5. contract gap (minor) — `notStartable` is checked for two ended snapshots and one date

- **Rule.** `WorkoutSessionError.notStartable`: "`start` with a snapshot the engine would not start: one that is
  not live, or is malformed." ADR-004, "Malformed envelopes": any date in a `started` snapshot that is not finite,
  or a snapshot rest's `total` outside `0 ... WorkoutEngine.longestRest`.
- **Repro.** `faultyClient_isRejectedByAClauseOrAScript(.judgesSnapshotsByPhaseAndStart)`: a client that starts
  any snapshot whose phase is live and whose start date is finite.
- **Expected.** A clause or a script complains.
- **Actual.** All 17 clauses and all 12 scripts accept it. The clause's unstartable snapshots are a finished one,
  a discarded one and one started at +∞; the scripts' is a finished one. A snapshot with a rest of an hour and a
  nanosecond, a rest ending at +∞, a set done at −∞, a last performance dated NaN or an end date of NaN is never
  offered. My oracle rejects the client within 25 seeds, and `start_unstartableSnapshot_throwsNotStartable_andChangesNothing`
  holds the fake to 12 kinds of snapshot.
- **Why minor.** A host that asks the engine, as the fake does, cannot have this fault. Fix: add a rest that is
  too long and one inner date to `unstartable` (two snapshots).

### F10-S1-6. test-quality — clauses that compare the client with itself, and clauses never shown to fail

- **Self-comparison.** The clauses "a terminal event through apply ends the workout as finish and discard do" and
  "after a workout ends another can start" take the expected ended state from what the client returned, and check
  only its phase against anything else. `WrongSessionClient(.terminalApplyMovesTheEnd)`, which ends a workout
  through `apply` a second later than the event says, passes all 17 clauses. The scripts catch it (their model asks
  the engine), so the contract as a whole rejects it; `notForTheClauses` in my suite records the exception.
- **Clauses never shown to fail.** `WorkoutSessionClientContractFaultTests` says "the clauses must be able to
  fail" and ties each of its 11 faults to one clause, which covers 9 of the 17. No test of the implementer's
  asserts that the other eight can fail: "a new client has no workout", "start makes a live snapshot current",
  "a second start", "a terminal event through apply", "after a workout ends another can start", "two
  subscribers", "callers at once" and "a subscriber whose task is cancelled". They can: among my 32 one-fault
  clients each of the 17 clauses is broken by at least one (tabulated in exploration: from 1 fault for "a new
  client has no workout" to 15 for "two subscribers"), so this is a hole in the fault suite, not in the clauses.
- **A missing first element is found by the clock.** A client whose streams have no first element keeps
  `violations(of:)` waiting until the suite's time limit (measured: 60 s, then all 17 clauses complain). The
  contract's documentation says so, and `scriptViolation` reports the same client in 5 ms, so this is a note, not
  a gap: when the host's contract suite times out, run a script first.

### Attacked and held

Counts are from the host run of my suites: 65 tests (about 940 cases with the parameterized ones), 62 passing.

- **Differential model** (`FakeSessionDifferentialAdversarialTests`): 200 seeds × 120 calls (seeds
  `29 + 6151·n`, n = 0…199; `LEDGER_PROPERTY_SEED_COUNT` scales it). Each script mixes legal calls with refused
  and ignored ones: starts on a live workout, 7 kinds of spoiled snapshot, calls with nothing live, rows and sets
  that do not exist, negative and huge weights, dates at ±∞ and NaN, rests at 0, exactly one hour and just outside,
  a second `started`, both ends by both routes. Every return value, every thrown error, `current()` after every
  call, `applied`, and every update on two subscribers (one from the start, one joining at a seeded step) equalled
  the oracle's. `scripts_coverTheRules` proves the scripts reach all 16 outcome kinds. No failing seed.
- **The oracle has teeth**: it rejects 31 of 31 one-fault clients it is asked about within 25 seeds, and accepts
  an independent correct client (`WrongSessionClient()` with no fault, which also keeps all 17 clauses and 12
  scripts of the contract).
- **Criterion 1 (streams).** First element before a start, at the start, straight after a haptic and after an
  end; 50 subscribers joining one per change; a subscriber that reads nothing through 5,000 updates and a finish;
  a subscriber cancelled after exactly four updates while another keeps reading; a subscriber that applies from
  inside its own loop 200 times; old subscribers seeing the next workout start after each of the four ways to end.
- **Streams the fake forgets.** 5,000 streams opened and dropped leave at most one held, and only the one live
  reader once it subscribes; 200 readers cancelled mid-workout leave only the kept one after the next publication.
- **Criterion 2.** 12 unstartable snapshots, with and without a live workout (`notStartable` wins, naming the
  snapshot); 8 odd but startable ones; a second start with another id, the same snapshot, and the same id with
  other content (`workoutInProgress` names the live workout each time); 9 calls with nothing live;
  `init(live:)`, also with each unstartable snapshot (an issue is reported, no workout is held).
- **Criterion 3.** 10 events that change the workout, 9 the engine accepts without changing anything (each
  published once), 14 it ignores (returned unchanged, nothing published, listed in `applied`); re-log, un-log and
  re-log; a superset round (the rest starts and no rest effect is forwarded).
- **Criterion 4.** `finish`, `discard`, `apply(.finished)` and `apply(.discarded)` mid-rest: the engine's ended
  state once, the haptic only for a finish, `current()` nil, a new stream starting at nil; finite end dates as far
  away as `distantPast` and 1e300 are accepted (no validation window).
- **Concurrency on the fake.** 16 tasks × 20 adds and logs: one engine history, the same for both subscribers,
  each `apply` returning its own event's update. 50 starts at once: one winner, 49 refusals naming it, one update.
  A finish racing 320 applies: every apply lands before the end or is refused, per task never after a refusal. 40
  ends at once: one wins. 40 streams opened during 400 applies: each starts at some update and misses none. 59
  streams opened while a discard runs: each reads live, discarded, next, or nil, next.
- **Criterion 6 (the key).** The test value fails the test naming `@Dependency(\.workoutSession)`. The live value's
  `updates()` ends at once on every call, and `current`, `start`, `apply`, `finish` and `discard` each throw
  `unimplemented(key: "workoutSession")`, twice over. The preview value is a `FakeWorkoutSessionClient` with no
  workout that runs a workout on the real engine. Three test functions each start a workout on their preview value
  and none meets another's. **Caveat, documented by a passing test:** within one test function (the cases of a
  parameterized test included) and within one preview process, every reader of the key shares one fake, as the
  key's comment says; a preview that needs its own workout binds `FakeWorkoutSessionClient(live:)`.
- **Criterion 7 (Release).** `swift build -c release` of the package exits 0. `Release/LedgerFakes.o` is 1,176
  bytes with one symbol against 135 `FakeWorkoutSessionClient` symbols in Debug; no Release object names
  `FakeWorkoutSessionClient` or the `LedgerFakes` module; `UnimplementedWorkoutSession` is there.
- **Criterion 8 (`ClockText`).** 21 boundary rows (0, 59 s, 60 s, 59:59, one hour, 1:01:05, 10 and 100 hours),
  12 sub-second rows on both sides of a second, 8 negative rows down to the most negative `Duration`, 4 extremes
  (2^63 s, the largest `Duration`), every second of 30 hours against integer arithmetic with ASCII-only output,
  and 200 seeded durations across the whole `Int64` range read back to their seconds.
- **`WorkoutSessionUpdate`.** `feedback(from:)` against a filter written from criterion 3: all four haptics kept,
  8 other effects dropped, 200 seeded mixes in order with repeats, and the engine's own effects for six events and
  a start. `live` for each phase; equality and hashing; the error's cases.
- **The contract on calls made one after another.** 31 of 32 one-fault clients are rejected, 30 of them by a named
  clause alone; five racy faults (a lost update, reversed publication, a second subscriber in another order, a
  dropped update, a returned state that is another caller's) are caught in every one of 200 exploration runs.

### Not attacked

- **The host** (`LocalWorkoutSessionActor`), recovery, stamps and storage: S2. `WorkoutSessionError.incompleteLog`
  is only compared for equality, because nothing in S1 throws it.
- **Mutants of the product code.** I ran none. The one-fault clients show that the contract and my oracle can
  fail; they are not mutants of `FakeWorkoutSessionClient`.
- **Another device locale.** `ClockText` is checked for ASCII digits and colons and, read afterwards, builds its
  text from integer interpolation only. I did not run the tests under a non-English locale.
- **The stub's fault-level logging**: not observed.
- **A fake released while a subscriber waits.** Its stream never ends, as any `AsyncStream` whose continuation is
  dropped; I did not test it.
- **A subscriber that never reads.** The stream is unbounded by design, so its memory grows with the workout.
- **The racy clients are scheduler-dependent.** A racy fault shows only if two calls are inside the client at
  once, which no test can force. Each such test therefore allows ten runs and needs one complaint. In exploration
  the five faults the contract catches were caught in 200 of 200 runs, the five it accepts in 0 of 100 or more,
  and my own checks caught those five in 100 of 100; I did not measure my checks' rate on the other five beyond
  the committed test. The tests on the fake itself assert nothing that depends on which task wins.
- **One green full gate.** The gate stops at its first failing step, so I ran its watchOS step and its coverage
  step by their own commands afterwards (see Commands). No single `check.sh` run covered all five steps.

### Notes for S2

- The fake accepts a `start` under the id of a workout that just ended (it keeps no history, and the engine
  starts it). A host with a store may not; the contract uses a fresh id each time and does not say.
- F10-S1-1's ruling changes the "ignored" clause, so it is cheaper to take before the host is written.

### Commands

Run from the worktree root unless noted. Logs are in the session scratchpad, `f10s1-g2/`.

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FakeSession.*AdversarialTests\|SessionContractBiteAdversarialTests\|ClockTextAdversarialTests\|WorkoutSessionUpdateAdversarialTests\|WorkoutSessionKeyAdversarialTests'` | 1 | 65 tests: 62 pass, 3 fail (9 failing cases: F10-S1-2 × 3, F10-S1-3 × 1, F10-S1-4 × 4, F10-S1-5 × 1); 13 known issues, all expected |
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file` (whole package, host) | 1 | failures: my two suites above, and `LedgerDesignTests`' Archivo font suites (host only, as on `main`) |
| `scripts/check.sh --lint-only` | 0 | format, `swiftlint --strict`, package graph, script tests |
| `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file` | 0 | 35 s |
| `/usr/bin/python3 <sim-lock> scripts/check.sh` (full gate, at the end) | **65 (red)** | Steps 0 to 2 pass (tools, format, lint, script tests) and the iOS build passes. Step 3, the iOS PR plan: 1,717 tests, 1,693 pass, 12 skipped, 9 expected failures, **3 fail, all mine** (the 9 cases above, all in `LedgerSyncTests`). `check.sh` stops there, so its steps 4 and 5 did not run |
| `/usr/bin/python3 <sim-lock> f10s1-g2/watch-step.sh` (step 4's own commands, copied from `check.sh`'s `test_platform`, because the gate stops at step 3) | build 0, tests 65 | watchOS PR-Watch plan: 1,536 tests, 1,516 pass, 12 skipped, 5 expected failures, **3 fail, the same three** |
| `scripts/coverage-gate.sh .derivedData/Results/PR-iOS.xcresult .derivedData/Results/PR-watchOS.xcresult` (step 5's command) | 0 | LedgerDomain 99.12 %, LedgerFakes 98.96 %, LedgerDependencies 96.20 %, LedgerSync 91.17 %, overall 98.51 %; every threshold met |

The gate is red only because of my three failing tests, which document F10-S1-2 to F10-S1-5. With those four
findings fixed (or the tests re-ruled), nothing else in either plan fails.
