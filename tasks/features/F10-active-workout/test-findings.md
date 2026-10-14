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

## Slice S1 — round 2, close-out (G2 tester, 2026-10-04)

Scoped close-out of `9ad8fc6` (the fix round for F10-S1-1 to -6 and the review) against the brief's revised
"Plan amendments". I audited every edit the implementer made to my files (`git diff 0950170..9ad8fc6` over the
three `Adversarial/` folders, 17 files, read line by line against the notes' "Sanctioned test edits"), then
re-attacked only what changed. No product code or contract was edited; nothing was committed.

**Verdict.** F10-S1-1 to -6 are closed and the fake held again. One new contract gap, F10-S1-7, is open with one
failing test (4 cases), so **G2 cannot close green as it stands**. No further open-ended round is needed: the fix
is four small additions to the contract for which the checks already exist (below), after which my failing test
passes unchanged; or a ruling that those four cases belong to the S2 host's own tests.

### Status of round 1's findings

| # | Status | What shows it |
|---|---|---|
| F10-S1-1 | **closed** (ruled: `invalidEndDate`) | `finish_`/`discard_nonFiniteDate_throwsInvalidEndDate_leavingTheWorkoutLive` (6 cases); the new `FakeSessionInvalidEndAdversarialTests` (7 tests, 22 cases); `clientThatReturnsForANonFiniteEnd_isRejectedByTheContract`; the differential reaches "finish invalidEndDate" and "discard invalidEndDate" |
| F10-S1-2 | **closed** (the `device:` and `now:` parameters are gone; the fake stamps with `Fixtures.now`) | its failing test was deleted with its subject, which I accept |
| F10-S1-3 | **closed** | `racyClient_isRejectedByAClause(.racyScrambled)` now passes (the walk in "callers at once"); two new shapes, `.publishesWhatIsLiveLater` and `.oneSubscriberReversed`, are rejected in 30 of 30 runs |
| F10-S1-4 | **closed for the four pairs it named**; a start against an apply remains (F10-S1-7 a) | the four round 1 clients are rejected; two new shapes, `.losingEndRepublishes` and `.registersBeforeItsFirstElement`, in 30 of 30 runs |
| F10-S1-5 | **closed** | `.judgesSnapshotsByPhaseAndStart` is rejected, and each added snapshot bites alone: `.judgesAllButRestLength` and `.judgesAllButSetDates` each break the clause |
| F10-S1-6 | **closed** | the clauses alone reject all 33 of my one-fault clients with no exception list (`.terminalApplyMovesTheEnd` included), and the implementer's `everyClause_hasAFault` holds a fault to each of the 22 clauses |

Left over from F10-S1-5, as a note: the clause still offers no snapshot with a negative rest, a rest ending at a date
that is not finite, a last performance at such a date or such an end date. A host that asks the engine cannot have
that fault, and the fix I named in round 1 (a rest that is too long and one inner date) is what was done.

### Audit of the edits to my files

- **Mechanical, as claimed** (ten files whole, and the lines so marked in six more): `effects:` → `haptics:` with
  `[.haptic(x)]` → `[x]`, `feedback(from:)` → `haptics(from:)`, `minutesSeconds(` → `elapsed(`. I found no edit among
  them that changes what a test demands.
- **The oracle's `end(_:)`** (`SessionSeamOracleAdversarialSupport`): right. It refuses with `invalidEndDate` only when
  a workout is live and the engine ignored the end; with nothing live `noLiveWorkout` still wins, as criterion 2 has it.
- **`nonFiniteEndThrows` → `nonFiniteEndReturns`**: right, and forced by the ruling. It had been left outside
  `SeamFault.sequential`; I moved it in, so the clauses-or-scripts, clauses-alone and oracle tests ask about it too.
- **`forwardsEveryEffect` deleted**: forced by the type, but nothing then demanded "no haptic the engine did not ask
  for". **Restored** as `.inventsHaptics` (a `.setLogged` added to every update): rejected by a clause, the scripts
  and my oracle.
- **`WrongSessionClient.ignored`**: right. `.nonFiniteEndEnds` now drops the workout and throws; still rejected.
- **Deleted, `FakeSessionForgettingAdversarialTests`** (2 tests): accepted, their subject (`subscriberCount`) is gone.
  **Replaced** by `FakeSessionEndedStreamsAdversarialTests` (3 tests, 42 cases) on what a caller can see. One change
  of behaviour to know: an ended stream is now forgotten only when a publication finds it terminated, so streams
  dropped while nothing is published are kept until the next publication (round 1's fake dropped them at the next
  subscription). Nothing observable depends on it.
- **Deleted, the two stamp tests** (23 cases): accepted, the parameters are gone.
- **Stale names and comments, fixed by me**: `elapsed_…` (6 functions), `haptics_…` (4), "five cases" with
  `invalidEndDate` in `error_casesAreDistinct`, the bite suite's comments, `notForTheClauses` (removed: no exception is
  needed now), `.firstElementRepeatsHaptics`, and "haptics" in `Seam.brief`.

### F10-S1-7. contract gap — four pairs of calls the overlap clauses still do not run

- **Rule.** `WorkoutSessionClient`: "The rules hold when calls overlap: a client takes them one at a time, so every
  caller and every subscriber is told the same one story." Criterion 1 (order under overlap), criterion 3 (an
  update's haptics), criterion 4 (`finish` "returns the finished state"; `invalidEndDate`).
- **Repro.** `racyClient_isRejectedByAClause` in `SessionContractRoundTwoAdversarialTests`, four of its eight cases.
  `LateWrongSessionClient` is a second client written from the revised documentation; with no fault it keeps all 22
  clauses, 12 scripts, my oracle and my eight overlap checks. Each of these four has one suspension in the wrong place:

  | | Client | What it does when calls overlap | Never run by the contract |
  |---|---|---|---|
  | a | `.startPublishesLate` | commits a start, suspends, then publishes it: an apply that overlaps is published before the start | a start against an apply |
  | b | `.startCommitsLate` | publishes a start, suspends, then commits it: a subscriber told of the workout finds `current()` nil and its `apply` refused | a subscriber acting on the update it was just given |
  | c | `.dropsHapticsUnderOverlap` | publishes a logged set without its haptic when another apply is inside the client | overlapping events that buzz (the clauses overlap stepper edits and adds only) |
  | d | `.judgesAnEndByWhatIsLiveLater` | decides `invalidEndDate` by whether a workout is live after a suspension: when another end has won meanwhile, a `finish` at a date that is not finite returns a live workout | an end the engine ignores against one it takes |

- **Expected.** Some clause complains. **Actual.** None does: 0 of 30 exploration runs each, 0 of 10 in the committed
  test. My checks reject all four in 30 of 30 runs and pass on the fake.
- **How serious.** The fake is right; this is about what S2's host will be held to. (a) is the rest of F10-S1-4 and
  (d) is the new rule's own overlap, a host that reads "still live after the call" literally and looks after an
  await. (c) costs one line. (b) is the least likely host fault of the four.
- **Fix.** (a) a clause from `Seam.startVersusApplyFault`; (b) one from `Seam.reactionFault`; (c) let some of
  "callers at once"'s events be logs, as `Seam.overlapFault` does with an add and then a log per set; (d) two ends at
  a date that is not finite among "ends at once"'s twelve, which may only throw `invalidEndDate` or `noLiveWorkout`
  (`Seam.invalidEndRaceFault`). All are in `SessionSeamLateRacesAdversarialSupport.swift` and
  `SessionSeamOverlapAdversarialSupport.swift`.

A note, not a finding: `.invalidEndSticks` (a client that refuses every later end once it has refused one) passes
all 22 clauses, because the clause for an ignored end never tries an end the engine takes afterwards. The scripts
do, and reject it in 150 of the 200 PR seeds, so the contract as a whole catches it (`leftToTheScripts`).

### Re-attacked and held

- **`invalidEndDate` on the fake.** `finish` and `discard` at +∞, −∞ and NaN: refused fifty times over, the workout
  and its running rest unchanged, nothing published, each call listed in `applied`, a stream opened afterwards
  starting at the live workout, and then a valid end of the other kind returning and publishing the engine's state
  once. The same six through `apply`: the workout returned, nothing thrown. With nothing live, before a workout
  and after one: `noLiveWorkout`. Twelve such ends racing one valid finish: only that one returns. Twelve racing
  sixty adds: all refused, the history whole.
- **The rule on other clients.** Six one-fault clients for its edges (the wrong error, a throw through `apply`, the
  date judged before the workout, a discard that returns, a refusal that publishes, a refusal that sticks): five
  are each rejected by exactly one clause, the sixth by the scripts.
- **The overlap clauses and the walk.** Of eight new racy shapes, four are rejected in 30 of 30 runs (above).
- **A start against applies, and a subscriber that acts on the start**: hold on the fake.
- **Ended streams, observably.** 5,000 streams dropped with nothing published, then a whole workout on a kept reader;
  40 seeds of 60 rounds in which streams are dropped unread, read by a cancelled task or opened, around one
  publication per round (every stream still held has exactly its first element and every update since); 30 readers
  stopping at different points while 300 sets are added.
- **`haptics(from:)`.** All 24 orders of the four haptics among other effects, with repeats; and the differential,
  which compares the fake's haptics with a filter of my own over 200 seeds of 120 calls.
- **`ClockText.elapsed`.** My round 1 tests, unchanged but for the name, pass (246 cases).
- **Round 1's suites** on the new API: all pass.

### Not attacked in this round

The host; a full fault-by-clause table for the 22 clauses; anything not named above as changed. The racy clients
remain scheduler-dependent, as in round 1: each such test allows ten runs and needs one complaint.

### Commands (round 2)

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FakeSession.*AdversarialTests\|SessionContract.*AdversarialTests\|WorkoutSessionUpdateAdversarialTests\|ClockTextAdversarialTests\|WorkoutSessionKeyAdversarialTests'` | 1 | 78 tests (about 1,030 cases): 77 pass, 1 fails (F10-S1-7, 4 cases); 13 known issues, all expected |
| `scripts/check.sh --lint-only` | 0 | format, `swiftlint --strict`, package graph, script tests |
| `/usr/bin/python3 <sim-lock> scripts/check.sh` (full gate, at the end) | **65 (red)** | Steps 0 to 2 and the iOS build pass. Step 3, the iOS PR plan: 1,729 tests, 1,707 pass, 12 skipped, 9 expected failures, **1 fails, mine**: `racyClient_isRejectedByAClause` of `SessionContractRoundTwoAdversarialTests`, the four cases of F10-S1-7. `check.sh` stops there |
| `/usr/bin/python3 <sim-lock> f10s1-g2/watch-step.sh` (step 4's own commands, as in round 1) | build 0, tests 65 | watchOS PR-Watch plan: 1,548 tests, 1,530 pass, 12 skipped, 5 expected failures, **1 fails, the same test** |
| `scripts/coverage-gate.sh` on the two bundles (step 5's command) | 0 | LedgerDomain 99.12 %, LedgerFakes 98.95 %, LedgerDependencies 96.20 %, LedgerSync 91.17 %, overall 98.51 % |

The gate is red only because of the one test that documents F10-S1-7. The orchestrator's gate on `9ad8fc6` was
green; the difference is this round's new clients, not a regression in the fix round.

## Slice S2 — round 1 (G2 tester, 2026-10-05)

Independent adversarial pass over `feat/F10-s2-session-host` at `3c960e8`: `LocalWorkoutSessionActor`,
`HybridLogicalClock`, `StartWorkoutUseCase`, `LaunchStep.resumeWorkout` and the iPhone composition's wiring.

**Verdict.** I found no way to lose or double a workout. Against stores that refuse, lose their answers or die
at any store call, against relaunches, an unsteady clock, many callers at once and cancelled callers, the host
always ended where `WorkoutEngine.replay` of its stored log says. Four findings remain, none of them data loss:
one spec question and three minor ones. Five tests (9 cases, 13 issues) fail and stay failing.

**How I worked.** Expected values come from the brief's criteria, from `WorkoutEngine.reduce` / `replay` run in
my support files, from `SessionBuilder` and `MissTracking` called by me, and from a fresh store of the same kind
(`SiegeRig.asStored`). The stores are reached through wrappers of my own (`Siege`), which share nothing with
`StoreProbe`. No product code, contract, implementer test or earlier tester's file was edited; nothing was
committed. I have not read `implementation-notes.md`.

**Independence, exactly.** Before any test of mine existed I had read: the brief, ADR-004, the architecture and
standards sections named in my instructions, the protocol file whole, and the declarations and doc comments of the
new code from the grep in my instructions (it also shows a few `var` lines and log strings inside bodies). I also
listed the type names the implementer's test files declare, to avoid collisions, and a grep for how existing tests
make a store fail showed me two trigger statements of the implementer's AppKit tests. Everything in "Attacked and
held" except the items marked † was written and run before I read any function body or implementer test.
Afterwards I read `WorkoutSessionConcurrentScriptTests`, the stand-in's fault list and seeds, the concurrent
script's source, the host's two source files, the use case's `start` and the composition's diff. **F10-S2-4 was
found by reading the host's code** (`begin` passes `seq: 1`), not by a black-box test; the domain-level repro of
F10-S2-2 was written after reading the use case. F10-S2-1, F10-S2-2 (on the host) and F10-S2-3 were found
black-box. I read the names of every implementer test and the bodies of three files; I did not audit each
assertion.

**Convention** (as in S1): a bug or a contract gap has a failing test that stays failing until the fix. A spec
question is pinned by a passing test marked "(documents …)".

### Summary

| # | Severity | Finding | Failing test |
|---|---|---|---|
| F10-S2-1 | spec question | A workout the store can never save wedges the session until relaunch, and afterwards fails the launch step on every foreground | none (2 documenting tests pass) |
| F10-S2-2 | bug (minor) | "Discard and start new" throws `noLiveWorkout` and starts nothing when the live workout has ended by the time of the discard | `start_replacingLive_overAWaitingSave_startsTheNewWorkout`, `start_replacingLive_liveEndedInBetween_startsTheNewOne` |
| F10-S2-3 | contract gap (minor) | The concurrent script never reads the acting subscriber's stream past the update it reacts to | `racyHost_faultOnTheActingStream_isReported` (3 cases) |
| F10-S2-4 | bug (minor; not reachable through `StartWorkoutUseCase`) | `start` under an id whose log is kept uses `seq` 1 without reading the store: memory and store part | `start_overAKeptLog_memoryFollowsTheStore`, `apply_afterAStartOverAKeptLog_isStored` (2 cases each) |

### F10-S2-1. spec question — a workout the store can never save

- **Rule.** Criterion 4: "If the save fails, `finish` throws, the log is kept, nothing is lost, and no ending
  update is published until a save succeeds: a second `finish` retries it". The brief speaks of a save that fails
  and is retried. It does not say what becomes of a workout no retry can save. F05 input 8 lists the refusals:
  `nulInText`, `inexactWeight`, `nonFiniteDate`; `duplicateIdentifier` is a fourth.
- **Repro.** `HostUnsavableAdversarialTests` (both backings). Start `Seam.session(1)`, log two sets, log a set at
  an eighth of a pound (the engine accepts it, the event store keeps it), `finish`.
- **Actual, in the process.** `finish`, `discard` and `apply` each throw `inexactWeight`; `start` throws
  `workoutInProgress`; `current()` and every stream go on showing the workout. The end is in the log, so nothing
  is lost, and nothing the lifter can do gets rid of the workout: Discard does not discard it.
- **Actual, after a relaunch.** No workout is live and another can be started. `resumeFromStore()` throws
  `inexactWeight` on every call, `needsRecovery` stays true, so the composition runs the step, fails it and logs
  a fault on every return to the foreground for as long as the log exists. The workout never reaches history.
- **Reach.** Low today. Steppers move in whole steps, exercise names are refused with U+0000 when saved, ids are
  fresh UUIDs. I know no path through the app that produces such a workout. It is a hole behind the defences,
  not in front of them.
- **Question for Pete.** What should happen to a finished workout the store refuses for good? Options: refuse
  the finish before the end is stored when the workout would not save (it stays live and can be corrected or
  discarded); let a discard drop a log whose save keeps failing; or keep today's behaviour and have the step
  stop reporting work left for a refusal that is not transient.
- **Pinned by** `finish_neverSavable_wedgesTheSessionUntilRelaunch` and
  `recovery_neverSavable_failsOnEveryForeground`, which pass today and fail once any of the above is adopted.

### F10-S2-2. bug (minor) — replacing a live workout that has ended by the time of the discard

- **Rule.** Criterion 8: "with `replacingLive: true` the live workout is discarded and the new one started."
- **Repro on the host.** `HostStartUseCaseAdversarialTests.start_replacingLive_overAWaitingSave_startsTheNewWorkout`:
  Upper A live; `finish` fails at `materialize` once, so its end waits and every reader still sees the workout;
  `start(lowerA)` answers `.conflict`; `start(lowerA, replacingLive: true)`.
- **Repro on the fake.** `StartWorkoutRefusalAdversarialTests.start_replacingLive_liveEndedInBetween_startsTheNewOne`:
  another caller finishes the live workout between the use case's look and its discard.
- **Expected.** `.started(new)`: nothing stands in the new workout's way.
- **Actual.** The use case throws `noLiveWorkout` and starts nothing. On the host the discard completes the
  waiting save first (the protocol's documentation), so the old workout is saved, not discarded, and the lifter
  gets an error for "Discard and start new". Asking again starts the workout.
- **Cause.** `start` calls `session.discard` whenever its earlier look found a workout, and lets the client's
  `noLiveWorkout` end the call. The use case documents the same race for `start` (`workoutInProgress`, "asking
  again reports the conflict") and not for the discard.
- **Reach.** Not before S7 wires Finish and its failure. Nothing is lost either way.

### F10-S2-3. contract gap (minor) — the acting subscriber's stream is read only up to its reaction

- **Rule.** Criterion 11: the script is "checked as one history: … every success is published once … a late
  stream is a suffix of the history". Rule 5 of the script reads the acting subscriber's stream "up to the first
  that showed a workout" (`react(to:on:)` breaks there) and never again.
- **Repro.** `HostContractBiteAdversarialTests.racyHost_faultOnTheActingStream_isReported`. `RacyHost` is the
  real host over stores that give way, with one stream fault (an update repeated, dropped, or two swapped) that
  strikes once, on the second stream opened, while two calls are inside.
- **Expected.** A run in which the fault struck is reported.
- **Actual.** The fault struck in 20 of 20 runs and was reported in 0, for each of the three faults, in every
  run on both thread pools.
- **Why it matters a little.** A subscriber that acts on an update is the workout screen, and its stream is the
  one that plays the haptics. A host bug confined to the stream of a subscriber that has made a call passes the
  contract. A bug in publication that reaches every stream is caught on the other streams.
- **Fix.** Read `acting` to the mark after the reaction and judge it as the early stream is judged.

### F10-S2-4. bug (minor; not reachable through `StartWorkoutUseCase`) — a start under an id whose log is kept

- **Rule.** Criterion 2: "An event is stamped with `seq` = the highest stored for this workout and device + 1".
  The host's documentation: "Memory follows the store."
- **Repro.** `HostStartOverALogAdversarialTests` (both backings). The store holds workout 1's second and third
  envelopes without its `started` (a log that replays to nothing, which criterion 6 keeps). `start(session 1)`.
- **Expected.** Either the start is refused, or afterwards `current()` is what the store replays.
- **Actual.** `start` returns. `current()` is the bare snapshot (0 of 18 sets done); the store replays the
  snapshot plus the kept envelopes (2 of 18 done, a rest running). The next `apply` throws
  `conflictingEnvelope(seq 2)`; the call after that recovers and the workout jumps to the stored state.
- **Cause.** `begin` stamps `.started` with `seq: 1` and never asks the store what it holds under that id.
- **Reach.** `StartWorkoutUseCase` draws a new id for every workout, so only a caller that passes an id twice,
  or a store damaged in that particular way, gets here. I found it by reading `begin`, not by a test.

### Attacked and held

128 test functions in 24 suites, 1,027 cases, in 37 new files. All pass except the five named above.

- **Never lost, never doubled** (`HostNeverLostAdversarialTests`, `SiegeTrial`). A seeded script of 70 steps:
  starts, applies, finishes, discards, ignored events, relaunches with and without the launch step, clock moves,
  and store faults at a seeded store call (refused; done and answered as failed; the process dying before or
  after the write, which covers `materialize` and `compact`). After every step `current()` is compared with
  `replay` of the stored log; every call made while no store failed is compared with the brief's rules on that
  log; at the end, after one clean launch, every `seq` is 1, 2, 3 … with rising stamps, nothing is stored twice
  or unasked, every call that returned is in a log, every finished workout is in history once as replayed, no
  discarded one is. 200 seeds over the in-memory stores (`SeamSeed.all`, value 6151 · n + 29) and the first 100
  over GRDB: no violation. Over a store that forgets every fifth append, never saves, or never compacts, 20 of
  20 sieges report it (†, added after the code was read).
- **Re-entrancy** (`HostReentrancyAdversarialTests`, `SiegeStorm`). Six tasks of seven calls at once over stores
  that give way 1 to 3 times a call, judged against what the store took: one workout at a time, each `seq` once
  and in order, the first stream equal to the history `reduce` folds, late streams suffixes of it, each returned
  state the one its own update carried. 120 seeds in memory, 60 over GRDB. Two starts at once; an apply, a
  `current()` and a new stream arriving while a finish saves.
- **Cancelled callers** (`HostCancellationAdversarialTests`). Start, apply, finish and discard cancelled before,
  during and after the call, both backings: stored once, returned, published once. A launch step cancelled while
  it reads; `current()` from a cancelled task before recovery; subscribers that leave (†).
- **Failure at each step** (`HostFailureAdversarialTests`, `HostEndFailureAdversarialTests`,
  `HostDiscardFailureAdversarialTests`). Append refused and append stored-but-failed, for start, apply and
  finish; `materialize` failing once and three times; what `current()`, open streams, a new stream, `start`,
  `apply`, `discard` and a second `finish` do meanwhile; the first finish's end date kept; exactly one ending
  update; `compact` failing after a save and after a discard; a finish after a failed discard.
- **The clock and `seq`** (`HostClockAdversarialTests`, `HostClockEdgeAdversarialTests`,
  `HybridLogicalClockAdversarialTests`). Stamps equal to the formula over a clock that steps back, repeats,
  creeps by half a millisecond and jumps a century; after a relaunch; across two workouts; no `seq` or stamp for
  an ignored or refused event; a peer's envelopes; a clock that is ±∞ or NaN (`noFiniteStamp`, never
  `notStartable`); stored stamps that are not finite or centuries ahead; 50 seeds of a wandering clock.
- **Recovery** (`HostRecoveryAdversarialTests`, `HostRecoveryFaultAdversarialTests`,
  `HostIncompleteLogAdversarialTests`). Every row of the table on both backings; all kinds of log at once; the
  step twice and twice at once; a save that throws with other logs waiting; a store that cannot be read; two
  live logs; the first call of each kind before the launch step; calls during recovery; on GRDB, an unreadable
  row in the middle, at the start and at the end, and `finish` / `discard` on such a log.
- **Kill and relaunch on a database file** (`WorkoutRelaunchAdversarialTests`). The five points through
  `AppComposition` as the app boots it, and a workout carried across six relaunches with the clock stepping back.
- **`StartWorkoutUseCase`** (`StartWorkoutUseCaseAdversarialTests`, `StartWorkoutRefusalAdversarialTests`).
  The built workout against `SessionBuilder` called here for five week-and-day pairs in lb and kg; resumed;
  conflict with another day, another week and an ad-hoc workout; replace; six refusals, each with and without a
  live workout; a deleted exercise; a store that fails during the build; a day edited since.
- **Misses** (`HostMissesAdversarialTests`, `HostMissesRetryAdversarialTests`). Each slot against
  `MissTracking.update` run here; misses recorded since the start; another program active; the program deleted;
  a slot no longer stored; a deload week; the launch step after a kill; a retry after a failed compaction; a
  program that cannot be read.
- **The wiring** (`WorkoutWiringAdversarialTests`, `WorkoutLaunchRetryAdversarialTests`). The key is the one
  host; no host without a database; a database that opens on a foreground retry; the step once, after the
  settings; a failed step retried on the foreground only; a failed finish completed there; a cancelled
  scene-phase task. The watch composition's sources are untouched by `3c960e8` and its 35 tests pass.
- **Criterion 1** (`HostContractRunAdversarialTests`, †). Every clause, and the sequential and concurrent
  scripts for 80 seeds, on the host over my wrappers giving way twice a call, in memory and over GRDB.
- **Criterion 11** (`HostContractBiteAdversarialTests`, †). See below.

### What it takes to catch a racy host

On the real host over stores that give way, a fault of `RacyHost` strikes in 68 to 80 of 80 runs (one run on
each pool; seeds 7919 · n + 17, n < 80), and the script reports every strike except on the acting stream
(F10-S2-3). So where calls do suspend, one seed is nearly enough.

The gate's own stand-in is different: its two weakest faults (`judgesAnIgnoredEndLater`,
`dropsHapticsUnderOverlap`) are reported by 6 to 10 of the twenty fixed seeds, over eleven runs on both pools.
Which seeds report is mostly the script's doing: seeds n = 2, 3, 5, 7, 11, 12, 15 reported the first fault in
all four runs I listed seeds for, and n = 4, 6, 10, 12, 18 the second; on a one-thread pool the two lists were
identical run to run. The gate's "one of twenty" therefore has a wide margin, and naming three such seeds per
fault would make it exact. `standInFaults_gateSeeds_areReportedWithAMargin` asks for four of twenty; I chose
four after seeing a minimum of six.

### How my own tests changed while I wrote them

These numbers are here so the green ones above can be weighed.

- **The siege's oracle was corrected three times before it went green**: 22, 5 and 5 violations, then none.
  Every one was my rule, not the host. The protocol lets a host go on showing a workout whose end threw until a
  later call completes it, even when the store did what was asked and only the answer was lost; my rule had not
  allowed for that, nor for a retried discard returning.
- **`RacyHost` was tightened three times.** Its first version missed 1 to 34 strikes per fault, because some
  strikes were not visible wrongs: a stale answer to `apply(.started)`, which the engine ignores; a swallowed
  ignored event; a first element replaced by "no workout" when there was none. Fifteen runs of the suite and
  four of the census alone went into this. The misses that remained after each tightening were all on the
  acting stream.
- **`SiegeStorm` first checked that a returned state was some published state**, which let a stale answer
  through (0 of 33 reported). It now checks the state its own update carried.
- **Ten false failures** in the first run of the end-failure suites came from my scene reading a stream twice
  (`Seam.buffered` ends it). Four more came from my arithmetic for expected stamps and from a stream I had
  opened too early.

### Notes for later slices

- **S7.** After a failed "Save workout", `discard` saves the workout and throws `noLiveWorkout`
  (`discard_afterAFailedSave_savesTheWorkout`, documenting): the screen must not offer Discard there. A retried
  `finish` can also meet `noLiveWorkout`, when the foreground's launch step completed the save first.
- **S7.** `replacingLive` whose `start` is then refused leaves no workout at all (two documenting tests).
- **Criterion 3** says the host "reports an issue" for a clock that is not finite. It logs at fault level and
  throws; LedgerSync has no IssueReporting, so no test can see the report.
- **F17.** Past 2⁴⁴ s a stamp repeats (`stamp_pastTwoToTheFortyFour_repeats`, documenting); the drift bound must
  exist before a peer's stamp can be stored. With two live logs and an end that waits, recovery resumes the
  other log while the end still names the first; I did not test it, because only a peer can bring two.

### Not attacked

- **No simulator.** Everything ran on the Mac host with `swift test`. The full gate, on both simulators, is the
  orchestrator's.
- **A real kill.** A kill is modelled as abandoning the host or the composition and opening the same store or
  file again. No process was signalled, and SQLite's durability under power loss was not tested.
- **`prepareDependencies`.** The app's process-wide binding cannot run in a package test; every wiring test
  binds with `withDependencies`.
- **Criterion 12.** The implementer's timing test passed once by hand on the Mac host (221 applies, the whole
  test in 0.031 s). Not measured on a phone or a simulator.
- **Coverage** was not measured.
- **A caller that retries after a lost answer.** The first envelope is stored, so a retried "+30s" would extend
  twice. I did not test it; the host cannot tell a retry from a second tap.
- **The implementer's tests, assertion by assertion**, and `implementation-notes.md`.

### Commands

| Command | Exit | Result |
|---|---|---|
| `swift build --package-path LedgerKit --only-use-versions-from-resolved-file --build-tests` | 0 | warm-up |
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter '<the 24 suites>'`, 4 times | 1 | 128 tests; 13 issues, the five failing tests, the same set each time |
| the same with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`, 6 times | 1 | the same 13 issues each time |
| the six concurrency suites alone, 10 times on each pool (before the † additions) | 1 | 3 issues each time, the acting stream's |
| `swift test … --filter '^LedgerSyncTests\.'` | 1 | 239 tests in 43 suites; 11 issues of mine, 13 known issues from S1 |
| `swift test … --filter '^LedgerDomainTests\.'` | 1 | 836 tests in 137 suites; 2 issues, F10-S2-2's |
| `swift test … --filter '^LedgerAppKitTests\.'` | 0 | 63 tests in 15 suites |
| `swift test … --filter LedgerWatchAppKitTests` | 0 | 35 tests in 9 suites |
| `LEDGER_TEST_LANE=nightly swift test … --filter LocalWorkoutSessionActorPerformanceTests` | 0 | once, by hand |
| `scripts/check.sh --lint-only`, twice | 0 | format, `swiftlint --strict`, package graph, script tests |
| `scripts/check.sh` (full gate) | not run | the orchestrator's |

No test helper process was left running.

## Slice S3 — round 1 (G2 tester, 2026-10-05)

Independent adversarial pass over `feat/F10-s3-program-updates` at `f8c513d`: `materialize(_:slotUpdates:droppingLog:)`
on the GRDB repository and on LedgerFakes' linked stores, the host's one-call save, and criterion 9's lane cut.

**Verdict.** The save itself held against everything I threw at it: program changes land or are skipped as the
criteria say, a failure at any statement of the transaction changes no row, a second and a third save change no
row, and the database, the fakes and a model of my own agree on seeded scripts. One finding in how the host uses
it (F10-S3-1, latent: the app's own composition cannot reach it), and one in another tester's suite that my cut
touches (F10-S3-2). Two tests of mine (8 cases, 12 issues) fail and stay failing, for F10-S3-1.

**Independence, exactly.** Before my S3 tests existed I had read the brief's S3 section, the declarations and doc
comments of the new code from the grep in my instructions (it shows a few lines inside bodies), the workout
repository's protocol whole, `Support/Tags.swift` and the lines that use it, and the notes' subsection "Criterion
9: before and after", as sanctioned. That subsection also proposes cuts for my suites; mine differ in number but I
had read them. I had also read the first sixty lines of `LedgerPersistenceTests/Support/RepositoryTesting.swift`
while looking for a clock, and the F05 tester's kit (`S2Kit`, `S3Kit`), which I reuse. F10-S3-1 was predicted
from a doc comment ("Both stores are tables of one database, so the answer is `droppingLog`") and then shown by a
test; I read the host's `complete` only afterwards. After my tests had run I read the names of the implementer's
S3 tests, about forty lines of two of them, and the timing test's diff. I did not audit them assertion by
assertion.

### The test that failed by ruling

`WorkoutRelaunchAdversarialTests.kill_afterTheSaveBeforeTheCompaction_compactsOnRelaunch` pinned "saved, then
killed before the compaction". Over one database that state no longer exists, so the test is gone, with a comment
where it stood. What replaced it is a new suite, `WorkoutSaveKillAdversarialTests`, through the composition on a
real file:

- `kill_insideTheSaveTransaction_leavesNoRowAndTheWholeLog` (3 statements: the exercises' insert, the sets'
  insert, the log's delete): no row in any history table, the log whole with its end in it; the relaunch saves and
  drops.
- `kill_atTheProgramStatement_leavesTheProgramAndSavesOnRelaunch`: the same where the transaction reaches the
  program (`UPDATE ON slot` refused, a swap with "Also update program" pending).
- `kill_afterTheSaveCommitted_leavesTheRowAndNoLog`: the row and no event; the relaunch changes no row count.

The old state, which stores that are not one database still reach, stays pinned at the host by
`HostRecoveryAdversarialTests.recovery_savedNotCompacted_changesNothing`,
`HostEndFailureAdversarialTests.finish_compactionFails_savedOnceAndEndedOnce` and, new,
`HostLinkedSaveAdversarialTests.kill_aroundTheSave_theRelaunchCompletesIt`.

### Criterion 9: the PR-lane cut

**Result.** The session suites cost 38.2 s before my cut and 14.6 s after it, 25 % of the 58.1 s they cost before
S3; with this round's three new host suites, 16.3 s, 28 %. The target was a third, 19.4 s.

**How it was measured.** As the implementer measured, one target: `f10s3-g2/measure.sh <label>` through the lock
(`build-for-testing`, then `test-without-building -testPlan PR -only-testing:LedgerSyncTests` with `check.sh`'s
flags, iPhone 17, iOS 27.0), and the per-suite sum of run durations from the result bundle. **One run each**; the
same tree gave the implementer 36.9 s and me 38.2 s, so read a few percent as noise. Loads at the start: 4.0, 4.8,
6.0. The last run also ran `LedgerPersistenceTests`.

| Suite | Whose | Before | After the cut | With the S3 suites |
|---|---|--:|--:|--:|
| `Adversarial F10 S2 · never lost, never doubled` | mine, S2 | 12.7 s, 304 | 1.5 s, 30 | 1.5 s, 30 |
| `Adversarial F10 S1 · does the session contract bite` | S1 tester | 4.7 s, 145 | 2.1 s, 109 | 2.2 s, 109 |
| `Adversarial F10 S2 · does the concurrent script bite` | mine, S2 | 3.9 s, 17 | 1.2 s, 17 | 1.2 s, 17 |
| `Adversarial F10 S1 · the contract after the fix round` | S1 tester | 3.3 s, 39 | 1.7 s, 34 | 1.8 s, 34 |
| `Adversarial F10 S2 · the contract over this suite's stores` | mine, S2 | 3.9 s, 202 | 0.4 s, 22 | 0.4 s, 22 |
| `LocalWorkoutSessionActor · the contract` | implementer | 2.1 s, 270 | 2.0 s, 270 | 2.1 s, 270 |
| `WorkoutSessionClient · calls made at once, as one history` | implementer | 2.0 s, 335 | 2.0 s, 335 | 2.0 s, 335 |
| `Adversarial F10 S2 · many callers at once` | mine, S2 | 1.6 s, 185 | 0.3 s, 45 | 0.3 s, 45 |
| `WorkoutSessionClient · the contract notices a faulty client` | implementer | 1.0 s, 57 | 0.9 s, 57 | 0.9 s, 57 |
| `WorkoutSessionClient · the contract on the fake` | implementer | 0.7 s, 227 | 0.7 s, 227 | 0.7 s, 227 |
| `Adversarial F10 S1 · fake session vs the engine` | S1 tester | 0.9 s, 201 | 0.3 s, 41 | 0.3 s, 41 |
| `Adversarial F10 S3 · the host saves and drops in one call` | mine, S3 | — | — | 0.8 s, 34 |
| `Adversarial F10 S3 · a swap reaches the program with the save` | mine, S3 | — | — | 0.5 s, 28 |
| 33 other session suites | all | 1.5 s, 411 | 1.4 s, 411 | 1.5 s, 423 |
| **The S1 tester's** | | **9.3 s**, 556 runs | **4.7 s**, 355 | **4.8 s**, 355 |
| **The implementer's** | | **5.9 s**, 975 | **5.8 s**, 975 | **5.9 s**, 975 |
| **Mine, S2** | | **23.0 s**, 862 | **4.1 s**, 268 | **4.2 s**, 268 |
| **Mine, S3** | | — | — | **1.4 s**, 74 |
| **All session suites** | | **38.2 s**, 2,393 | **14.6 s**, 1,598 (25 %) | **16.3 s**, 1,672 (28 %) |

**What was cut, in my suites.** `SessionLane.cut(_:to:)` (new, `SessionLaneAdversarialSupport.swift`) gives a
matrix whole in the nightly lane and its first seeds elsewhere. The counts were chosen from the before-run's
per-test costs to land under the target, not from any argument about how many seeds are enough:

| Test | Nightly | PR lane and `swift test` |
|---|--:|--:|
| `HostNeverLostAdversarialTests`: sieges in memory, over GRDB | 200, 100 | 20, 6 |
| `HostReentrancyAdversarialTests`: storms in memory, over GRDB | 120, 60 | 30, 10 |
| `HostContractRunAdversarialTests`: scripts on each backing, the differential | 80, 40 | 5, 10 |
| `HostContractBiteAdversarialTests`: seeds a racy host runs, storms a fault | 20 + 60, 40 | 10 + 0, 10 |

Unchanged in every lane: the siege's coverage test (40 sieges), its sabotage test (20 sieges each), the storm's
coverage test, the stand-in's margin test (its twenty seeds), every backing, every racy fault. No assertion
changed. One failure message that said "in 80 runs" now prints the count.

**Every line changed in the S1 tester's files** (four, in three files; each is an `arguments:` list):

| File and line | Was | Is |
|---|---|---|
| `FakeSessionDifferentialAdversarialTests.swift:67` | `arguments: SeamSeed.all` | `arguments: SessionLane.cut(SeamSeed.all, to: 40)` |
| `SessionContractBiteAdversarialTests.swift:52` | `arguments: SeamFault.sequential` | `arguments: SessionLane.cut(SeamFault.sequential, to: 4)` |
| `SessionContractBiteAdversarialTests.swift:104` | `arguments: SeamFault.racy` | `arguments: SessionLane.cut(SeamFault.racy, to: 3)` |
| `SessionContractRoundTwoAdversarialTests.swift:109` | `arguments: SeamLateFault.racy` | `arguments: SessionLane.cut(SeamLateFault.racy, to: 3)` |

What that leaves out of the PR lane, plainly. Line 52: `faultyClient_isRejectedByAClauseOrAScript` runs 4 of its
33 faults; all 33 still run in `faultyClient_isRejectedByAClause`, which asks strictly more of the contract. Lines
104 and 109: the two `racyClient_isRejectedByThisSuitesOverlapChecks` tests run 3 of their 10 and 3 of their 8
faults; every racy fault still runs in `racyClient_isRejectedByAClause`. Those two tests check the S1 suite's own
overlap checks, not the contract, and were 4.6 s of the 9.3 s. The nightly lane runs all of it as before.

### Summary of findings

| # | Severity | Finding | Failing test |
|---|---|---|---|
| F10-S3-1 | bug (latent; not reachable through `AppComposition`) | A host whose workout repository and event store are not one database is told the log went with the save, and never drops it: the workout is saved again at every launch | `finish_eventStoreElsewhere_dropsItsLog`, `relaunch_afterAFinish_findsNoLogToSaveAgain` (4 cases each) |
| F10-S3-2 | test-quality (not S3's code; the S1 tester's suite) | Two of S1's overlap-check cases fail on a one-thread pool; my cut takes exactly those cases out of the PR lane | none of mine |

### F10-S3-1. bug (latent) — the repository's "the log went with the save" is believed by a host that holds another event store

- **Rule.** Criterion 5: "recovery's row "saved, not compacted" remains only for stores that are not one
  database." The protocol: "Only a host whose stores are not one database saves the workout and drops its log in
  two steps." `materialize`'s documentation: it answers `false` "from a repository that does not share a database
  with the event store, whose caller then compacts the log itself".
- **Repro.** `HostMixedStoresAdversarialTests`, four pairings, each of two real stores: the database's repository
  with an in-memory event store; with another database's event store; the fakes' linked repository with another
  in-memory event store; with the database's. Start a workout, finish it.
- **Expected.** The workout in history, and its log gone from the event store the host was given.
- **Actual.** The workout is in history and its log is still in the host's event store, in all four. At the next
  launch the log replays to a finished workout and is saved again; `relaunch_afterAFinish_findsNoLogToSaveAgain`
  deletes the workout from history first, and the relaunch brings it back. The log is never dropped, so this
  repeats at every launch. A discard is not affected: the host compacts that itself.
- **Cause.** `complete(_:)` returns as soon as `materialize(…, droppingLog: true)` answers `true`. A repository
  answers for the log in its own database (the GRDB one whenever it is asked; the fakes' when an event store is
  linked to it), and cannot know which event store the host holds. Nothing in the host's initialiser ties the two.
- **Why it matters.** Saving an old workout again is not harmless once the lifter has moved on: its misses and
  its program changes are written again over later edits
  (`LinkedSaveTwiceAdversarialTests.saveAgain_afterTheProgramWasEdited_appliesTheUpdateAgain` documents that for a
  swap, as F05's input 6 warned for misses), and a workout deleted from history returns.
- **Reach.** None in the app: `AppComposition` builds the host from one `LedgerStores`. It is reached by any test
  or later composition that pairs stores from two places, and nothing says so when it happens. The implementer's
  "not one database" set-up uses a repository that holds no log and answers `false`, so it does not meet this.
- **Fix, for whoever owns it.** Either the host does not take the answer on trust (a `compact` after the save is
  one idempotent statement), or the pairing becomes something a caller cannot get wrong.

### F10-S3-2. test-quality — two of S1's overlap-check cases fail on a one-thread pool

- **Where.** `SessionContractBiteAdversarialTests.racyClient_isRejectedByThisSuitesOverlapChecks` for
  `.racyLateRegistration`, and the round-two test of the same name for `.registersBeforeItsFirstElement`.
- **What.** With `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` and the nightly matrix both fail, 3 runs of 3 ("in ten
  runs, the overlap checks accepted a client that …"); on the default pool both pass, 2 runs of 2. The nightly
  lane runs the uncut lists, so this is as it was before my edit; S2's round did not run S1's suites on a
  one-thread pool, which is how it went unseen.
- **Why I report it.** My cut keeps the first three racy faults of each list in the PR lane, and neither of these
  two is among them. So in the PR lane these two cases no longer run in that test at all, on any pool. The gate
  uses the default pool, where they pass.

### Attacked and held

50 new test functions in 11 suites, 173 cases; 48 pass. All run on the database and on LedgerFakes' linked stores
unless they are about rows.

- **Criteria 1 and 2** (`LinkedSaveAdversarialTests`, 7 tests). An update of the workout's own slot, with misses
  for another; misses and an update for the same slot, the passed slot's other fields stale; a slot of another
  program, a slot that never was and an exercise that is not stored, beside one that applies; an ad-hoc workout
  and another program's workout; the workout's own program when it is not the active one; a slot removed during
  the workout; a program deleted, then saved again.
- **Criterion 3** (`LinkedSaveTwiceAdversarialTests`, 6 tests). A second and a third save with the clock moved an
  hour between them: every row of every table of the database identical, timestamps included, with the log
  dropped and with it kept; a second save that only now drops the log changes `workout_event` alone; an update to
  the exercise a slot already holds writes no program row.
- **Criterion 4** (`LinkedSaveFaultAdversarialTests`, `LinkedSaveLogAdversarialTests`). A trigger refuses each of
  21 statements (insert, update, delete on the seven tables a save writes), for a first save with records,
  misses, a program change and a log, and for a save over an earlier one: whenever the save fails, no row of any
  table differs, and the same save then succeeds. Five kinds of refused workout change nothing.
- **What the `Bool` says** (`LinkedSaveLogAdversarialTests`). `true` when asked, also when no log was there;
  `false` when not asked; `false` from a repository that holds no log and from a wrapper written before S3, which
  still applies the program change. What it cannot say is F10-S3-1.
- **Criterion 6** (`LinkedSaveDifferentialAdversarialTests`). Seeded scripts of 30 steps (saves of new and of
  earlier workouts, logs, a program deleted, restored, losing a slot) on both kinds of store at once and on
  `LinkedModel`: the same answers, the same programs, history and logs after every step. 6 seeds in the PR lane
  (7919 · n + 17), every seed of the lane nightly; 200 passed once on the host. A model without the "exercise is
  stored" rule fails 10 of 12 seeds, one with the log rule inverted 11 of 12. Sixteen workouts refused for one
  reason or two are refused for the same reason by both.
- **Observers** (`LinkedSaveObserverAdversarialTests`). A reader already waiting hears a save's misses and swap
  as one value, hears nothing for a save that changes no program, and hears a workout once. Three readers racing
  forty saves never see a workout in history with its log still there, a log gone without its workout, or a
  slot's new exercise without its misses.
- **Criterion 5** (`HostLinkedSaveAdversarialTests`, `HostProgramUpdateAdversarialTests`). My store wrappers now
  have a linked mode that passes the one call on. Sieges in that mode, 12 seeds in memory and 6 over GRDB in the
  PR lane (200 and 100 nightly); a finish is an append and one save, or, unlinked, save then compact; a save that
  fails twice; a save whose answer is lost; four kill points, linked and not, each on both backings. A swap with
  "Also update program" through finish, discard, a failed save and its retry, an exercise that is not stored, and
  a relaunch after the program lost a slot: 7 tests on 4 set-ups.
- **Criterion 7** (`LinkedSaveFixtureAdversarialTests`). A copy of `db-v001.sqlite`, migrated by what was there
  before S3, takes the linked save and keeps its schema. `git diff 95ac9b8 f8c513d` shows no change to
  `Migrations.swift` or to any file under `Fixtures/`.
- **Criterion 8.** The implementer's timing test ran once by hand in the nightly lane on the Mac host and passed.
  I did not read the milliseconds it measured.
- **F10-S2-1 after S3.** Unchanged, for better or worse: a workout the store can never save still wedges the
  session and still fails the launch step at every foreground; both S2 documenting tests pass as written. What
  S3 removed is the half-saved state beside it: while an end waits, no history row and no slot has changed
  (`finish_neverSavable_wedgesAsBeforeAndChangesNothing`, 4 set-ups).

Documented, not findings: a save of an old workout sets its slot back over a later edit; the host writes misses
only to the active program, and a save writes a swap to the workout's own program whether active or not.

### How my own tests changed while I wrote them

- The rewritten relaunch test first gave four disk I/O errors: its cases ran at once in one harness directory.
- I listed `INSERT ON personal_record` among the statements to kill at; a first workout sets no record, so that
  statement is now exercised only where history holds an earlier workout.
- Fourteen false failures came from my program reader, which showed a program as active after reading it.
- My list of the statements a first save runs was a guess and was two short (it also updates the workout's row
  and retires old misses); the test now asks only that each statement I name fails the save.
- Eight false failures came from comparing a stored workout with one that still carried `programUpdates`.
- Every simulator figure is one run. The differential cost 2.3 s there at 12 seeds; I then halved it to 6 and did
  not measure again.

### Not attacked

- **No full gate, no watchOS simulator, no nightly plan on a simulator.** The orchestrator's.
- **Two saves at once** that change the same slot.
- **A soft-deleted exercise or day**: no protocol call reaches one.
- **What the engine puts in `programUpdates`** (a later swap of the same slot without the flag): not S3.
- **A real kill**, and `prepareDependencies`, as in S2.
- **My S2 tests still compare whole states inside `#expect`**; only this round's tests print a short difference.
- **The implementer's S3 tests, assertion by assertion**, and the S3 notes beyond the one subsection.

### Commands

| Command | Exit | Result |
|---|---|---|
| `swift test … --filter '<my S2 suites>'`, as found | 1 | 1 test failing: the one that fails by ruling |
| `swift test … --filter '<my S2 and S3 suites and S1's session suites>'`, 4 times | 1 | 231 tests in 46 suites; 12 issues each time, F10-S3-1's |
| the same with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`, 4 times | 1 | the same 12 issues each time |
| the same with `LEDGER_TEST_LANE=nightly`, once | 1 | the same 12 issues |
| the same, nightly and one-thread, once | 1 | 14 issues: the 12, and F10-S3-2's two |
| S1's two bite suites, nightly: one-thread 3 times, default twice | 1, 0 | F10-S3-2 in 3 of 3, in 0 of 2 |
| `LEDGER_TEST_LANE=nightly swift test … --filter LinkedSaveDifferentialAdversarialTests` | 0 | 200 seeds |
| `LEDGER_TEST_LANE=nightly swift test … --filter RecordReplayPerformanceTests` | 0 | once, by hand |
| `sim-lock.py f10s3-g2/measure.sh before` | 0 | `LedgerSyncTests` 38.5 s, 2,485 runs |
| `sim-lock.py f10s3-g2/measure.sh aftercut` | 0 | `LedgerSyncTests` 14.9 s, 1,690 runs |
| `sim-lock.py f10s3-g2/measure.sh final`, with `LedgerPersistenceTests` | 65 | 6,307 passed, 11 skipped, 14 expected failures, 8 failed: F10-S3-1's eight cases and no other. `LedgerSyncTests` 16.7 s, 1,764 runs; `LedgerPersistenceTests` 79.9 s, 4,576 runs, 3.7 s of it my seven new suites |
| `scripts/check.sh --lint-only` | 0 | format, `swiftlint --strict`, package graph, script tests |
| `scripts/check.sh` (full gate) | not run | the orchestrator's |

The result bundles are deleted. No test helper process was left running.

## Chore — the racy-host storm test made deterministic (2026-10-06)

`HostContractBiteAdversarialTests.storm_wheneverARacyHostStruck_reportsIt(fault:)` failed twice in the full gate
on trees that did not touch it, and passed on the re-run. Written by another agent than the S2 tester, on the
orchestrator's order; the S2 tester's files are changed as little as the cause allows.

### The cause (observed)

Reproduced on the Mac host: 1 red run in 40 of the suite as it stood (`swift test … --filter
HostContractBiteAdversarialTests`, default pool, nothing else running), case `fault → swapsTwoUpdates`, line 113:
`reported == struck`.

Instrumented (temporary code, removed), 12 storms at once in one process: 78 misses in 3,600 storms of seed 12331
(the third of the PR lane's ten, 6151 · 2 + 29), none on the other nine seeds; every one the same:

- Seed 12331's script holds `restExtended(amount: 30 s, extendsShownRest: true, tappedAt: +110 s)` and
  `restExtended(amount: 30 s, extendsShownRest: false, tappedAt: +75 s)`. When the store takes them in that order,
  the second changes nothing: "+30s" never shortens a running rest (`extendRest`). The engine still accepts it
  (`.persist`, `.transmit`: "the envelope belongs in every log even when it changes nothing here"), so the host
  stores it and publishes an update **equal to the one before it**. That is the product doing what ADR-004 says.
- `RacyHost(.swapsTwoUpdates)` strikes at the first update after a live one that its forwarding task handles
  while two calls are inside. Which update that is, is the scheduler's choice. When it was the first of that
  equal pair, the host "swapped" two equal updates: the stream it gave was the right stream, element for
  element. It still counted a strike, the storm rightly found nothing, and `reported == struck` failed.
- So the assumption that failed is in the racy host, not in the storm: **"a strike is always a visible wrong"**.
  The S2 tester tightened `RacyHost` three times for the same reason ("some strikes were not visible wrongs");
  this is a fourth case, which needs a particular order of two calls and a particular lag of one task, hence
  about 2 % of that seed's storms and 1 run in 40 of the suite.

The same root gives two more holes, on a stream opened in flight, where `SiegeStorm.lateIssue` accepts any
suffix of the history:

- `dropsAnUpdate`, **observed** once forced (temporary test: `RacyHost(host, fault, on: .allBut(1))`, 40 seeds,
  6 lanes of 100 rounds): 72 misses in 22,392 strikes, all seed 12331, stream 2. A stream whose first element is
  the workout as it stands and which then misses an update equal to that is the stream of an honest host that
  registered it one update later. With every stream wrapped, stream 1 takes the strike first, which is why the
  gate never showed this one.
- `repeatsAnUpdate`, **inferred, not observed** (0 misses in 22,756 forced strikes): such an update twice is the
  stream of an honest host that registered it one update sooner, when the update before the stream's first
  element is equal as well. It needs three equal updates in a row; no PR-lane seed has them.

`opensAStreamOnNothing`, `answersWithAStaleState` and `swallowsAnApply` have no such case: 0 misses in 2,000
strikes each before the fix, and each is conditioned on a visible wrong already.

**The product is not at fault, and neither is the storm's checker.** No violation was missed: in every miss the
streams, the answers and the store were those of a correct host. Nothing in `LedgerKit/Sources` was read as
wrong or changed.

### The fix

`RacyHostAdversarialSupport.swift`, `updates()` and `passed(…)` only (+20 −8 lines). No test, no other support
file and no product code changed; `HostContractBiteAdversarialTests.swift` is byte for byte as it was.

- The forwarding task hands `passed` the update before (`after before:`) in place of `afterLive: Bool`.
- `repeatsAnUpdate` and `dropsAnUpdate` strike only on an update whose live workout differs from the one before
  it on that stream (`changesTheWorkout`). Then the stream is one more or one fewer than the history at a place
  where the two neighbours differ, which is no suffix of it.
- `swapsTwoUpdates` cannot know at the hold what comes next. When the next update is equal to the held one,
  nothing went wrong: the strike is taken back (`strikes = 0`, `struckAt = "nowhere"`) and the fault waits for
  its next moment. A held update that is never released stays a strike, as before.

So "struck" now means "gave a reader something no honest host gives", for every scheduling, and "whenever it
struck, it is reported" no longer depends on which update the scheduler handed the fault.

**What still depends on the scheduler, and by how much.** `#expect(struck > 0)` is the test's proof that the race
happened; whether two calls overlap in a storm is the scheduler's doing (six tasks on the global pool) and I did
not replace the storm with a scripted hand-off: that would be another test. Measured after the fix, 24 lanes at
once, 1,000 rounds of the ten seeds per fault: the fewest storms of ten in which a fault struck were 10
(`repeatsAnUpdate`, `swapsTwoUpdates`, `dropsAnUpdate`, `swallowsAnApply`), 6 (`answersWithAStaleState`) and 5
(`opensAStreamOnNothing`); on a one-thread pool, 400 rounds: 10, 10, 10, 10, 9 and 6, the same in every round.
The count is the same in every one-thread round, so which seeds strike is mostly the script's doing, as the S2
tester found for the gate's stand-in. I never saw fewer than five of ten; I did not prove that it cannot be none.

### Proof it can still fail

- **A blinded checker.** `SiegeStorm.violation` with its first-stream, late-stream and answer checks taken out
  (the log and store checks left): the test is red for all six faults, `reported == struck` at line 113, exit 1.
  `HostSiegeStormAdversarialSupport.swift` restored from a copy; `cmp` and `git status` show it unchanged.
- **The old racy host.** As found: 1 red run in 40. Fixed: 0 misses in 10,000 storms per fault (24 lanes at
  once) where the old rule gave 7 in 2,000 for `swapsTwoUpdates`.

### Runs

`<suite>` is `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --skip-build --filter
HostContractBiteAdversarialTests`, one process a run, on the Mac host.

| Command | Exit | Result |
|---|---|---|
| `<suite>`, as found, 40 times in a row | 1 once | 39 green, 1 red: `swapsTwoUpdates`, line 113 |
| `<suite>`, fixed, 100 times in a row | 0 each | 100 green |
| the same with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`, 40 times | 0 each | 40 green |
| six loops of 25 at once, as load (four plain, one `--parallel`, one `--no-parallel`) | 0 each | 150 green |
| `<suite>` with the storm's checker blinded | 1 | red for all six faults; restored |
| `swift test … --filter '^LedgerSyncTests\.'` | 0 | 276 tests in 48 suites, 13 known issues (as before, none mine) |
| `sim-lock.py <scratch>/sim-watch.sh`: `xcodebuild build-for-testing` then `test-without-building` as `check.sh` runs `PR-Watch` on the Apple Watch Series 12 (46mm) simulator, with `-only-testing:LedgerSyncTests/HostContractBiteAdversarialTests -test-iterations 20` | 0, 0 | 340 repetitions passed: the suite's 17 cases, 20 times, in one runner process |
| `scripts/check.sh --lint-only` | 0 | format, `swiftlint --strict`, package graph, script tests |
| `scripts/check.sh` (full gate) | not run | the orchestrator's |

290 green runs of the fixed suite in a row on the host, 190 of them on one thread or under load.

### Not done

- The iOS simulator: not run. The watch run and the host cover the two places it failed.
- The nightly lane (40 storms a fault, 20 + 60 script seeds): not run. The forced late-stream test above ran the
  nightly's 40 storm seeds, for two faults only.
- The watch iterations shared one process; the gate starts one process a run.
- `racyHost_wheneverItStruck_isReported` and `racyHost_faultOnTheActingStream_isReported` use the same racy host
  against the contract's script. They stayed green in every run above; I did not go through the script's rules
  for a strike it cannot see, as I did for the storm's.
- For the F10 owner, not a defect: the host publishes an update equal to the one before it when an accepted event
  changes nothing. A subscriber that redraws or plays haptics per update sees a second, identical one.

The result bundles are deleted; the temporary tests and the instrumentation are gone (`git status`: this file and
`RacyHostAdversarialSupport.swift`). No helper process was left running; the watch simulator is left booted, as
`check.sh` leaves it. The worktree's `.derivedData` (the watch build) is kept.

## Slice S4 — round 1 (G2 tester, 2026-10-08)

Independent adversarial pass on `feat/F10-s4-cover` (46d4103 on d61a3c4). Written from the specification
(brief, "Plan amendments — slice S4") and the declarations and doc comments of `FeatureWorkout`; the
implementer's notes for S4 and its tests were not read before these tests were written and run.

### The lifecycle table (written from the specification, before any test)

"Live" is what `WorkoutSessionClient.current()` answers afterwards. A is the live workout's day, B another day.

| # | Before | The lifter, or the session | Live afterwards | The cover | The lifter is told |
|---|---|---|---|---|---|
| L1 | nothing live | start A | A, new | up, A, "0:00", no segment done | nothing |
| L2 | nothing live | start a day that is empty / gone / of a program no longer active / past the block | none | down | an alert that says why |
| L3 | nothing live | start A, a store or the session throws | none (or A, if the write went through) | down (or A) | an alert, unless A is live after all |
| L4 | A live, cover down | start A | A, the same id | up, A as it is | nothing; `StartWorkoutUseCase.start` not called |
| L5 | A live; its day deleted or emptied, its program replaced or removed | start A, or resume | A, the same id | up, A | nothing; no refusal |
| L6 | A live | resume | A | up, A | nothing |
| L7 | nothing live | resume | none | down | nothing |
| L8 | A live | start B | A | down; the conflict dialog | "You have a workout in progress" |
| L9 | L8 | "Resume it" | A | up, A | nothing |
| L10 | L8 | "Discard and start new" | B only; A not in history | up, B | nothing; discard before start |
| L11 | L8 | cancel | A | down | nothing |
| L12 | L8 | "Discard and start new", the discard fails | A | down | A was kept; nothing started |
| L13 | L8 | "Discard and start new", the start fails after the discard | none | down | A was discarded, B did not start |
| L14 | L8 | "Discard and start new", B cannot be built | A | down | A was kept |
| L15 | L8, then A ends elsewhere | "Resume it" | none | not showing A | no dead workout on screen |
| L16 | L8, then A ends elsewhere | "Discard and start new" | B | up, B | nothing |
| L17 | L8 | "Discard and start new" twice | B, one discard, one start | up, B | nothing |
| L18 | cover up on A | "Minimize" | A | down; route `minimized` | nothing |
| L19 | cover up on A | "Finish" | A | up, the finish dialog | "End workout?", "Discard", "Keep lifting" |
| L20 | L19 | "Keep lifting" | A, unchanged | up | nothing |
| L21 | L19 | "Discard" | none; nothing in history | down; route `discarded` | nothing |
| L22 | L19 | "Discard", the session refuses | A | up, A | an alert; the workout stays |
| L23 | cover up on A | A finished elsewhere | none; A in history | down; route `saved(A)` | nothing |
| L24 | cover up on A | A discarded elsewhere | none | down; route `discarded` | nothing |
| L25 | cover up on A | the stream ends | unknown to the cover | a failure with a way out | it cannot be shown |
| L26 | cover up on A | an update for another workout | what the session says | that workout or nothing, never a stale A | nothing |
| L27 | a request in flight | another request | one workout at most | one answer | nothing lost |
| L28 | cover up on A | start B (the shell should not, a route could) | A | up, A | nothing changes |
| L29 | A live | resume, the session cannot be read | A | down | "Couldn't open" |

### Result

81 tests written: 80 Swift Testing tests in `LedgerKit/Tests/FeatureWorkoutTests/Adversarial/` (9 suites; 70 run
on the Mac host, 10 need the simulator) and 1 UI test (`Apps/LedgerUITests/WorkoutAdversarial.swift`, nightly
lane). 79 pass. **Two stay red, each a finding: one fails (F10-S4-1), one traps (F10-S4-2).** The lifecycle held:
every row of the table above passed over the fake and over the real host, as did 80 seeded sequences with
faults. No way was found to have two workouts live, to lose a workout the lifter did not discard, or to leave
the cover on a workout that had ended.

### Findings

**F10-S4-1 · spec question · brief criterion 13, rule 36 · a workout with every set logged never shows a
finished bar.** `WorkoutPresentation.segments(of:current:)` makes the cursor's exercise current "whatever its
sets". When the last set is logged the engine leaves the cursor on the last row, so the last segment stays
orange for good. The plan's S4 input reads "done when every set is done, current when it holds the shown row,
upcoming otherwise", which puts done first.
- Repro: four exercises of 5, 3, 4 and 2 sets, all 14 logged in order through the fake.
- Expected `5d 3d 4d 2d`; actual `5d 3d 4d 2c` (cursor on exercise 3, set 1).
- Red: `WorkoutHeaderAdversarialTests.segments_allDone`. The same rule will colour a finished exercise orange
  when S5 lets the lifter select it. One line either way; it needs a ruling, not a guess.

**F10-S4-2 · bug, low · criterion 6 · a start that is not a number traps the cover.**
`WorkoutTimeline.elapsed(since:)` guards with `start >= .distantPast && start <= .distantFuture`. `Date`'s `>=`
and `<=` are both true for NaN, so the range is built from it and SwiftUI traps in
`Text(timerInterval:pauseTime:countsDown:)` → `ResolvableTimer.format` → `Duration.init`: "Double value cannot be
converted to _Int128 because it is outside the representable range" (crash report read, iOS 27.0 simulator).
- Repro: `WorkoutTimeline.fixed(at: now).elapsed(since: Date(timeIntervalSinceReferenceDate: .nan))`.
- Expected "0:00", as the function's comment and `WorkoutTimelineTests` ("No start traps the elapsed time")
  say; actual: the process dies. ±infinity, ±`greatestFiniteMagnitude` and dates beyond both distant dates
  read "0:00" (5 cases pass).
- Reach: none through a session today. `EventEnvelope.isWellFormed` refuses a `started` snapshot whose dates
  are not finite, on the fake, the host and in recovery. It is the guard that is wrong, not a path to it.
- Red: `WorkoutCoverTreeAdversarialTests.elapsed_startNotANumber_readsZero`. **It does not fail, it traps**: the
  hosted test process exits and xcodebuild restarts it once (about 30 s), then runs the rest. It is in the
  simulator lane only (`#if canImport(UIKit)`), so `swift test` is not affected. Say if it should be kept out
  of the lane until the fix; the fix is `timeIntervalSinceReferenceDate.isFinite` in the guard.

**F10-S4-3 · copy, low · criterion 4 · after the conflict, a new day that cannot be built is not told why.**
With nothing live a refused start says why ("This day has no exercises yet.", "Your program's block has
ended."). After "Discard and start new" the same refusals all read "Couldn't start the new workout / Your
workout in progress was kept.". `StartWorkoutUseCase` checks the day before it looks at the session, so an
empty or missing day is caught before the dialog; a week past the block's end (`weekOutOfRange`) and an
exercise that is not stored are thrown by the builder, after the dialog was offered.
- Repro: Upper A live; ask for Lower A in week index 8 of the 8-week block; the dialog shows; "Discard and
  start new".
- The lifter is offered a discard that can never lead anywhere, and then is not told why. Nothing is lost:
  `replace_weekPastTheBlock_keepsTheOldWorkout` pins that nothing is discarded (green). No red test: the words
  are Pete's.

**F10-S4-4 · accessibility / spec question · criterion 4 · cancel is reachable by VoiceOver, and invisible to
everyone else.** The conflict dialog cannot be raised in the running app from the Debug menu (F10-S4-5), so
this is read from "End workout?", which is the same control. What the UI tree shows on iOS 27.0, iPhone 17:
```
Other, {{0,0},{402,874}}, identifier: 'PopoverDismissRegion', label: 'dismiss popup'
Popover, {{81,360},{240,180}}
  Sheet, label: 'End workout?'
    StaticText 'End workout?'
    Button 'workout.finish.discard' 'Discard'
    Button 'workout.finish.keep' 'Keep lifting'
```
- VoiceOver: yes. The system adds a full-screen stop, "dismiss popup", before the dialog, and the escape
  gesture works on a popover. A tap outside closes the dialog and leaves the workout up
  (`WorkoutAdversarial.test_finishDialog_treeAndTheWaysOutOfIt`, green).
- A lifter who does not know to tap outside: no. The implementer's screenshot
  (`screenshots/s4/conflict-dialog-light.png`) shows two buttons, "Resume it" and a red "Discard and start
  new", and nothing that says "not now". "Resume it" is harmless (the cover opens, Minimize closes it), so
  nobody is forced into the discard, but the third choice of criterion 4 is not on screen. "End workout?"
  does not have the problem because "Keep lifting" was given no role and is drawn. If a visible Cancel is
  wanted, the same change does it: a plain button instead of `role: .cancel`. The brief's copy lists two
  buttons for this dialog, so this is a ruling, not a defect.
- Not verified on the conflict dialog itself, nor with VoiceOver running.

**F10-S4-5 · test-quality · criteria 2 and 4 · two things cannot be reached in the running app, and why.**
- "Discard and start new": the Debug row always asks for the first day of week 0 of the active program
  (`WorkoutSample.source`), which is the live workout's own source, so it resumes and never conflicts
  (confirmed in the UI test: sample, Minimize, sample again shows the workout and no dialog). Missing: a
  second Debug row that asks for another day, or Today's start (F09).
- Kill and relaunch with a live workout: every launch with `-LEDGER_UITEST` opens a new database in a new
  directory (`AppComposition.swift:188-189`, a fresh UUID per launch), so the relaunched app has no workout.
  Without the flag the test would write into the simulator's own database, which no UI test does. Missing: a
  launch argument that names the UI-test database, so a second launch reopens it.
- Neither was forced. Below the views both are covered: `WorkoutRelaunchAdversarialTests` (a new host over
  the stores the first wrote, a new launcher: resume, the same day, a conflict and a replacement, then a
  second relaunch) and the conflict suites. The system's presentation of the conflict dialog in the app, and
  the cover going up again right after a dialog comes down, are not covered by any test.

**F10-S4-6 · test-quality, minor.**
- `WorkoutTimelineTests.elapsed_anyStart_makesAText` is titled "No start traps the elapsed time" and has no NaN
  (F10-S4-2).
- `Smoke` says VoiceOver is given no time and compares pixels. In the app's tree `workout.header.elapsed`
  ("Elapsed time") has a child `StaticText` whose label is the running time ("0:08" when read). A UI test
  can read it. Whether VoiceOver can land on that child was not checked; the hosted reader stops at the
  parent, and a time read there would be the current one, not a frozen one.
- No test of the implementer's logs every set of a workout (F10-S4-1).
- The implementer's suites are otherwise sound: no sleep, no disabled test, the same two sessions (fake and
  host), every row of their table tested. Like mine, they drive the launcher and the store without the views;
  only `Smoke` runs the real `.task` wiring.

### The texts the brief does not give (17)

| Text | When it shows | Judgement |
|---|---|---|
| Elapsed time | VoiceOver's label for the time in the header | Fine. No time is spoken there (F09 S4's ruling) |
| Workout progress | VoiceOver's label for the bar; its value is "Exercise 2 of 5" | Fine |
| OK | The one button of every alert | Fine |
| Close | The one button of a cover that cannot show the workout | Fine |
| Try again. | Under "Couldn't open this workout" (a resume that could not read the session), and under "Couldn't start the new workout" when the session could not be read afterwards | Thin but honest: it claims nothing about what is live |
| Couldn't start this workout | Title: a start that started nothing | Fine |
| This day has no exercises yet. | The day has no slot | Fine |
| This day is no longer in your program. | The day is gone, **and** the program is no longer the active one | True in both cases; acceptable |
| Your program's block has ended. | The week asked for is past the block | Fine; "block" is the spec's word |
| Nothing was changed. Try again. | A store or the session failed during a start | Accurate: verified, nothing is live afterwards, and when the write did go through the cover opens instead |
| Couldn't start the new workout | Title: "Discard and start new" did not end with the new one live | Fine |
| Your workout in progress was kept. | The discard failed, or the new day could not be built | Accurate (L12, L14). Says nothing of why (F10-S4-3) |
| Your workout in progress was discarded. | The discard went through and the start failed | Accurate (L13). Bad news said plainly; right |
| Couldn't open this workout | Title: resume failed; and the cover whose updates ended | Fine |
| Close this screen and try again. | The cover whose updates ended | Fine. The workout is still live; it could say so |
| Couldn't discard this workout | Title: the session refused the discard | Fine |
| It's still in progress. Try again. | Under it | Accurate: the workout is shown as live and a second try ends it, also over the host when the log could not be dropped |

Apostrophes are typewriter ones, as in every other catalog. The 10 the brief gives ("Minimize", "Finish",
"Exercise %lld of %lld", "You have a workout in progress", "Resume it", "Discard and start new", "Cancel",
"End workout?", "Discard", "Keep lifting") match character for character. The catalog holds these 27 and no
other. No literal stands outside `WorkoutCopy.swift` (the module's audit), and no source file reads an ambient
clock, calendar, locale or zone or starts a task (30 tokens; the only clock reader is `Text(timerInterval:)`,
which criterion 6 asks for).

### The cover's VoiceOver tree

Written first: Minimize (button) · Elapsed time (no value) · Finish (button) · the workout's name · Workout
progress, "Exercise 1 of 5". The hosted cover reads exactly that, at 0:00, 24:22 and 1:01:05, and nothing in
it holds a time. At large, xxxLarge, accessibility 3 and accessibility 5 all five stops are on screen, do not
overlap, and both buttons are at least 44 points. While a discard runs both buttons are not enabled and
activating them sends nothing. Loading reads nothing. The failed cover reads its title, its line and one
button, "Close", which closes it.

### Attacked and held

- **The table, row by row** (L1 to L29): the lifecycle, conflict, resume, store and update suites, 51 tests,
  most over both the fake and the real host
  (`LocalWorkoutSessionActor` on in-memory stores).
- **Never two, never lost**: seeds 1 to 40 × 40 steps × {fake, host}, 3,200 steps, a fault before about half
  of them (start or discard failing before or after its work, `current` failing, the program store failing).
  A second test shows the same seeds reach all eleven states they are meant to attack.
- **Criterion 3**: day emptied, day deleted, program deactivated, program deleted × {fake, host}: the live
  workout is shown by its day twice and by resume, with no read of the active program and no `start`.
- **Criterion 4**: discard before start; the discard failing (nothing starts, the old one live and reachable);
  the discard's answer lost; the start failing after the discard (none live, said so); the start's answer
  lost (the new one is shown); the choice sent twice with its dismissal in either order (one discard, one
  start); the live workout finished elsewhere under the dialog ("Resume it" shows nothing and reports no
  route, "Discard and start new" starts and history keeps the finished one); the asked day made live
  elsewhere under the dialog (nothing is discarded); the session unreadable.
- **Overlap**: two requests at once, a request and a resume while a start or a replacement is held in the
  session (one workout, the first request's); a request whose task is cancelled mid-start (the workout is live
  and reachable); Minimize and Finish while a discard is held (ignored, the route is `discarded`); Discard
  twice and its work run three times (one discard); a discard that loses to a finish elsewhere (closes as
  saved, no alert); late taps after the cover has its exit (nothing, and a workout started since is not
  touched); a cover's task cancelled and run again (it follows again).
- **Updates**: nothing live at first (closes, no route); a stream that ends (failed screen, no discard
  reaches the session, Close closes); an update for another workout (that one is shown); updates after the
  end (the exit stands); 500 at once (the last is shown).
- **Finish**: both choices, the discard refused by the session and by the host's store (shown, the workout
  stays, a second try ends it), the injected date.
- **Elapsed**: 10 values from "0:00" to "100:00:00" drawn by the timeline and equal to `ClockText`; a start 1 s
  to a day in the future reads "0:00"; 5 uncountable starts read "0:00".
- **Segments**: none done, some done, out of order, zero exercises, 120 exercises, a cursor out of range × 3,
  an added set.

### Not attacked

- The real views' `.task` wiring in a hosted test: a package test process presents no cover and no dialog.
  `AdversarialRig` plays the views' part (read against `WorkoutCover` and `WorkoutRoot` after the tests were
  written: it matches), and `Smoke` and the UI test below run the real thing for start, minimize, resume,
  both finish choices and a tap outside.
- The conflict dialog and a relaunch in the running app (F10-S4-5).
- VoiceOver itself, a real device, the watch, landscape, the cover re-presented while its dismissal animates.
- A waiting end from a failed **save**: the cover cannot finish yet (S7).
- GRDB stores: the host ran over the in-memory ones.
- A workout swapped for another on a second device between the dialog and its answer (the discard names no
  workout: review N8, F17).

### Commands and exit statuses

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter FeatureWorkoutTests` | 1 | 136 tests in 21 suites, 1 failed: `segments_allDone` (F10-S4-1) |
| Simulator, run 1 (lock): `xcodebuild test -scheme Ledger -testPlan Nightly -only-testing:FeatureWorkoutTests -only-testing:LedgerUITests/WorkoutAdversarial`, iPhone 17, iOS 27.0 | 65 | UI test passed (27.6 s). Hosted: the trap (F10-S4-2), F10-S4-1, and one failure that was my own miscount of the fixture's exercises, corrected |
| Simulator, run 2 (lock): the same with `-only-testing:FeatureWorkoutTests` | 65 | Failing: `elapsed_startNotANumber_readsZero` (trap, one restart) and `segments_allDone`; every other test of the target passed |
| `scripts/check.sh --lint-only` | 0 | OK |

Both result bundles were read and deleted; the logs are in the scratch folder. One test was added after run 2
(`replace_weekPastTheBlock_keepsTheOldWorkout`); it ran on the host only. No app or helper was left running.
The full gate was not run.

## Slice S4 — round 2 (G2 tester, 2026-10-08)

On fcb9fa0 with the implementer's fixes uncommitted on top; the rulings are the brief's "Plan amendments —
slice S4 after round 1" (criteria 12 to 18). `git diff fcb9fa0` over my round 1 files was empty when this round
began: none was touched.

### Result

The rulings hold where they were aimed: both of round 1's red tests pass unedited, the conflict shows its
three choices in the running app, and no failure line claims more than it knows in 20 fault cases. 13 tests
added (8 host, 4 simulator, 1 UI); 94 in all. **Three stay red, each a new finding (F10-S4-7 to -9).** None
loses a workout or makes two.

### Round 1's findings

| Finding | Now |
|---|---|
| F10-S4-1 all sets logged, last segment current | **Closed** (criterion 13). `segments_allDone` passes unedited. The ruling opened F10-S4-9 |
| F10-S4-2 a NaN start traps | **Closed** (criterion 14). `elapsed_startNotANumber_readsZero` passes unedited; no trap in 17 starts × 3 ways |
| F10-S4-3 no reason after the conflict | **Closed** for the usual case (criterion 15); two corners open as F10-S4-7 and -8 |
| F10-S4-4 no visible Cancel | **Closed** (criterion 12). Tree below |
| F10-S4-5 conflict and relaunch not reachable in the app | Conflict: **closed** (criterion 18). Relaunch: **deferred** to F15 by the ruling |
| F10-S4-6 test quality | **Closed**: the timeline test has NaN, `Smoke` reads the clock |

### My three expectations that criterion 15 changed

The answer to the question put: **nothing is discarded before the new day is known to be buildable.**
`StartWorkoutUseCase` refuses an empty or missing day before it looks at the session, and builds the new
session (where `weekOutOfRange` is thrown) before it calls `discard`. In all three cases the tests still
assert, and still pass, that `discard` was not called, `start` was not called and the live workout is equal
in every field to what it was. Only the words moved, as criterion 15 says they should. No finding.

| Test | Old expectation | New expectation |
|---|---|---|
| `replace_newDayEmptied_keepsTheOldWorkout` (fake, host) | "Couldn't start the new workout / Your workout in progress was kept. / OK" | "Couldn't start this workout / This day has no exercises yet. / OK" |
| `replace_weekPastTheBlock_keepsTheOldWorkout` | `.failed(.notReplaced(.liveKept))` | `.failed(.notStarted(.blockEnded))` |

One thing the new line gives up: it no longer says the workout in progress was kept. It was; "Resume" shows
it (`refusedReplacement_saysWhy` checks). `AdversarialSession.fail` gained `skipping:` (fail the Nth call),
which is the only other edit to a round 1 file.

### New findings

**F10-S4-7 · copy, low · criterion 15 · the reason is dropped when the session cannot be read afterwards.**
A replacement refused for a reason, with the launcher's second read of the session failing, says "Couldn't
start the new workout / Try again." A plain start in the same double fault says the reason. The reason needs
no read: each of these errors is thrown before the use case discards anything
(`case .replace where aftermath != .liveKept || reason == .other`: `unknown` is not `liveKept`).
- Repro: Upper A live; ask Lower A; empty Lower A (or delete it, or ask a week past the block);
  `current()` fails from then on; "Discard and start new".
- Expected a line ending "This day has no exercises yet."; actual "Try again.". The workout is untouched.
- Red: `refusedReplacement_sessionUnreadable_stillSaysWhy` (3 cases). Two faults at once; low.

**F10-S4-8 · copy, low until F17 · criteria 15 and 16 · a workout saved by another hand is called
discarded.** The live workout is finished elsewhere while the dialog shows; the replacement is then refused
for a reason (or its start fails). The launcher reads nothing live and says "Couldn't start the new workout /
Your workout in progress was discarded." It is in history, and the reason is not said. `nothingLive` is taken
to mean "we discarded it"; only a discard this request made proves that.
- Expected: no "discarded", and the reason. Red: `refusedReplacement_afterFinishElsewhere_doesNotSayDiscarded`
  (3 cases). On one phone no other hand exists yet, so this waits for the watch; it was also true in round 1
  for a start that fails after a finish elsewhere.

**F10-S4-9 · spec question · criterion 13 · with sets logged out of order, an unfinished workout often has
no current segment.** Criterion 13 as built: a finished exercise is done "also when the cursor rests on it".
The engine leaves the cursor on a finished exercise whenever the row logged was not the cursor's own, so the
bar shows no orange while the words still say "Exercise 2 of 4".
- Repro (sets 3, 1, 4, 2): log one set of exercise 2, the one set of exercise 1, then the three of exercise
  0. Bar `dduu`, cursor (1, 0), nothing current, two exercises unfinished.
- Expected, as the round was asked to check: none current only when all are done, exactly one otherwise.
  54 of seeds 1 to 60 break it within 40 random logs and unlogs. Logged in cursor order it holds at every
  count (`segments_everyCountInOrder`, green).
- Red: `segments_anyOrder`. Not reachable in S4 (no row can be logged); S5 reaches it the first time a lifter
  ticks a row that is not the selected one. Either the presentation marks the first unfinished exercise when
  the cursor's is done, or the engine's cursor must never rest on a finished exercise while another is not:
  a ruling for S5.

**Observations, no test red.**
- A resume whose first read fails and whose second finds nothing live says "Couldn't open this workout / Try
  again."; there is no workout to open, and trying again does nothing.
- The Debug sample job is not "asked" in the launcher's failure path, so a sample start whose answer is lost
  says "Nothing was changed" over a workout that is live. Debug builds only.

### The conflict dialog in the running app (criteria 12, 18)

```
Other 'PopoverDismissRegion' 'dismiss popup'  {{0,0},{402,874}}
Popover {{81,321},{240,258}}
  Sheet 'You have a workout in progress'
    StaticText 'You have a workout in progress'
    Button 'workout.conflict.resume'  'Resume it'              {{97,403},{208,48}}
    Button 'workout.conflict.replace' 'Discard and start new'  {{97,459},{208,48}}
    Button 'workout.conflict.cancel'  'Cancel'                 {{97,515},{208,48}}
```
"Cancel" is a button, drawn, enabled, 48 points high and read last. `WorkoutConflictAdversarial` (new, 55 s,
green) adds what `Smoke` does not ask: a tap outside cancels too; after each way out the first day's row shows
"Upper A" with no dialog and a clock that has not gone back; after "Discard and start new" the other day's
row shows "Lower A" with no dialog and the first day's row now raises the dialog, whose "Resume it" shows
"Lower A": one workout is left.

**The implementer's `test_sampleWorkout_anotherDay_cancelResumeAndReplace`, check by check: each can fail.**
The three labels and `isHittable` fail if a button is not drawn. "Cancel discarded nothing: it asks again"
fails if Cancel discarded (the second ask would start Lower A with no dialog). "Resume it" fails on the wrong
title, and on a new workout through `ran > 5`. "Discard and start new" fails on the title. Two soft spots:
`ran > 5` leans on the test's own pace (it read well above that here, but nothing guarantees five seconds),
and "newly started" (`< ran`) can hardly fail once the title is Lower A. It does not check that the first
workout is gone; mine does. `elapsedSeconds` fails loudly on anything that is not a time.

### Attacked and held

- **Criterion 12**: the model's three texts; the tree above; Cancel and a tap outside change nothing (host:
  L11, the sequences; app: the UI test).
- **Criterion 13**: every count 0 to 10 in order: one current until the last set, then none.
- **Criterion 14** (simulator): 17 starts (three NaNs, ±infinity, ±greatest finite, ±1e300, ±1e19, zero,
  the least number, both distant dates and one second past each) × {paused, running, in the header on both
  timelines}; the pause itself at both distant dates. Nothing traps; every uncountable start reads "0:00".
- **Criterion 15**: emptied, deleted, block ended after the dialog: the reason, no discard, the old workout
  equal in every field and reachable.
- **Criterion 16**: a start with one fault at each call (program store, first read, second read, `start`,
  `start`'s answer lost) × the session readable afterwards or not: "Nothing was changed. Try again." only
  when it was read and nothing is live; "Try again." when it could not be read; the cover when the workout
  is live and the session said so; the next try always opens the workout. A replacement with one fault
  (discard, its answer lost, start, its answer lost, program store) × readable or not: "kept" only when it
  is kept, "discarded" only when this request discarded it, "Try again." alone when unreadable, and the old
  workout gone only with its discard. 20 cases, over the host.
- Round 1's suites again: the table, the 80 sequences (seeds 1 to 40 × fake, host) and the reach test pass.

### Not attacked

Kill and relaunch in the app (F15); VoiceOver itself; the alert form of the conflict; GRDB stores; the
snapshot references the implementer re-recorded (they pass; I did not judge the pixels).

### Commands and exit statuses

| Command | Exit | Result |
|---|---|---|
| `git diff fcb9fa0 -- LedgerKit/Tests/FeatureWorkoutTests/Adversarial/ Apps/LedgerUITests/WorkoutAdversarial.swift` (at the start) | 0 | empty |
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter FeatureWorkoutTests` | 1 | 149 tests in 22 suites; failing: the three red tests only (54 + 3 + 3 cases) |
| Simulator (lock), iPhone 17, iOS 27.0: `xcodebuild test -scheme Ledger -testPlan Nightly -only-testing:FeatureWorkoutTests -only-testing:LedgerUITests/Smoke -only-testing:LedgerUITests/WorkoutAdversarial -only-testing:LedgerUITests/WorkoutConflictAdversarial` | 65 | Hosted: 168 tests in 25 suites, the same three failing, no trap. UI: 5 of 5 passed (143 s) |
| `scripts/check.sh --lint-only` | 0 | OK |

The result bundle was read and deleted; `run3.log` is in the scratch folder. The full gate was not run.

## S6, round 1 (G2 tester, 2026-10-10)

On `9dadbe0` (`feat/F10-s6-rest`). The contract is the brief's "Plan amendments — slice S6, rest and haptics"
(criteria 1 to 15) with the rulings during G1 (criterion 3 amended). No product code, implementer's test,
project file or test plan was edited. (This file held no S5 section when the round began; S5's rounds are
in the testers' files and the notes.)

### Result

The slice holds where it was aimed. On a phone whose wall clock runs forward, the panel reads the Domain's
time left for the session's rest at every step of 40 seeded walks (time by quarter seconds to 40 s, the app
away for up to 200 s, taps, the cover's tasks starting again, the cover down and up), and every haptic is
played exactly once. "+30s" and "Skip rest" in S5's storm come to the engine's one event each. The host
keeps the scheduled notification equal to the workout's rest. Criterion 13 holds at every text size up to
Accessibility 3 on three phone heights. **34 tests added (24 that also run on the Mac host, 8 simulator-only, 2 UI).
Four stay red, each a finding; none is blocking.** Seven questions go to the product owner or to later slices.

### Findings

**F10-S6-4 · should fix, or the product owner's call · the brief's accessibility line (Dynamic Type to
AX5); beyond criterion 13 · at Accessibility 4 and 5 on a 375 pt phone the panel leaves no page.**
Measured on the simulator, the screen hosted at each phone's height between its safe areas (the model
agrees with the running app: 61 pt against the 64 pt of the UI test's screenshot on the iPhone 17 at AX5):

| Page showing over the panel (pt) | AX1 | AX2 | AX3 | AX4 | AX5 |
|---|---|---|---|---|---|
| 375 pt, home button (647 pt between the safe areas) | 186 | 136 | 57 | **5** | **0** |
| 375 pt, notch (728 pt) | 267 | 217 | 138 | 83 | **11** |
| iPhone 17 (778 pt) | 317 | 267 | 217 | 133 | 61 |

The panel is 339, 363, 403, 441 and 492 pt tall at those sizes (174 pt at the default size). With no page
showing, the next set's row can be neither seen nor reached, and the page cannot be dragged (a drag that
starts on the panel scrolls nothing, the implementer's deviation 3); "Rest over" stays until the next
logged set, so the lifter must tap "Skip rest" before every set. On the home-button phone at AX5 the panel
(492 pt) is taller than the 423 pt under the header: 69 pt of the cover do not fit, and where they go was
not looked at. Up to AX3, the criterion's size, the least is 57 pt.
- Red: `WorkoutRestPanelAdversarialTests.screen_leavesThePageRoom_beyondTheCriterion` (2 cases; the
  threshold is one 44 pt target). Green beside it: `screen_leavesThePageRoom` (10 sizes up to AX3),
  `screen_roomIsMeasured` (pins the simulator's safe area and the agreement with the app), and the UI test
  `WorkoutRestAdversarial.test_rest_atTheLargestTextSize_leavesSomeOfThePage` (iPhone 17).
- The implementer's look decision 4 already puts the panel's size at these sizes to the product owner (a
  smaller ring, one row of buttons). Whether a 375 pt phone with a home button is supported at all decides
  how much this matters.
- Seen in the same screenshot, not S6's: at AX5 the header wraps "Minimi/ze" and "Finis/h" inside a word.

**F10-S6-1 · note · criterion 3 · the wall clock set back under "Rest over", then any tap: a countdown that
never moves.** Once a rest is over `keepRestTime()` has ended and only a tap reads the date. With the clock
set back (by the lifter, or a correction) the panel goes on saying "Rest over" while time is left; the next
tap of any kind (a stepper) writes the earlier date into `moment`, and the panel shows "1:00 · Resting"
with no task to count it: it stands still, never reaches zero and never buzzes, until the workout's rest
changes. With the clock set back while the rest still runs, all is right
(`clockSetBack_whileResting`, green).
- Repro: log a set; 150 s; clock back 60 s; "+" on reps; wait.
- Red: `WorkoutRestAdversarialTests.clockSetBack_atRestOver_thenATap`.

**F10-S6-2 · note · criterion 7 · a rest the session has skipped is still felt at zero if the page has not
heard.** `keepRestTime()` asks the page (`shownRest`), not the session, whether its rest is still the one
shown. Between the session taking "Skip rest" and the stream showing it, a rest that reaches zero is
played and reads "Rest over". The window is the stream's lag: microseconds on one phone.
- Red: `WorkoutRestAdversarialTests.skipped_withThePageBehind_isNotFelt`.

**F10-S6-3 · note · criterion 7 ("each once, also across the cover's tasks restarting") · a haptic is lost
when the follow starts again between a change and its update.** An update's haptics reach only the stream
that was open when it was published; a new stream's first element carries none. A set logged, the follow
cancelled before it read the update, the follow started again: the set is on the page and was never felt.
In the app the tasks start again only when the cover's view goes and comes back.
- Red: `WorkoutRestAdversarialTests.followStartedAgain_withAnUpdateBehind`.

### Questions (reported, not asserted)

1. **"+30s" and a logged set carry the date of the pump's turn, not of the tap** (criterion 5: "both read
   from the tap's injected date"; ADR-004: a payload time is "the device's clock at the action"). The date
   is read when a tap is planned. Behind a slow save the two differ: "+30s" tapped with 2 s left, applied
   5 s later behind a held stepper, sent `extendsShownRest: false, tappedAt: +153 s`; the rest ends at
   183 s, not 180 s, and its ring is of 30 s, not 180 s. S5's `doneAt` is read the same way. On a host that
   answers in milliseconds they are the same moment. Measured in a scratch test, not kept.
2. **A superset member un-logged brings "Rest over" back** (the implementer's own note; deviation "what
   `shownRest` cannot tell"). Logged after a rest's end it takes "Rest over" away; un-logged, the ended
   rest is on screen again, however long ago it ended. And a member logged while the rest runs leaves
   "Rest over" standing at its end. By the brief "Rest over" stays "until the next logged set": the first is
   against its spirit, the second against its letter. Solo exercises have neither (property, 200 seeds).
   The cover draws a superset's members as solo cards today, so both are reachable before S9. Pinned as
   built: `ShownRestAdversarialTests.supersetMember_unlogged_asBuilt`, `…loggedDuringTheRest_asBuilt`.
3. **Recovery asks the notification client for nothing** (brief criterion 12 is silent). Right after a
   kill; not after notifications were turned off and on, or a restore. For F23. Pinned as built:
   `HostRestNotificationAdversarialTests.relaunch_midRest_asBuilt`.
4. **Until F23 a rest that ends with the app in the background gives no sign at all**: no buzz by design
   (the one-second window), and no notification client. A lifter with the phone locked hears nothing.
5. **"+30s" at "Rest over" buzzes again at the new rest's end.** As built, and right by the brief as I read
   it (decision #7 makes it a new rest; criterion 6 plays `.restOver` at zero). Said because it was asked.
6. **The brief's spoken announcements** ("Rest, 1:30 remaining" on appear, "Rest over" at zero) are not
   built (the implementer's look decision 8).
7. **For F17:** a peer's second `setLogged` of a done row after a rest's end hides "Rest over"; a wall clock
   set back by more than a rest between two logs hides a running rest (`shownRest` compares `doneAt` with
   the rest's end). The second is read from the code, not run.

### Audits

| What | Verdict |
|---|---|
| The two edits to `WorkoutWordsAdversarialTests` | **Sound.** The nine keys are the panel's and no other; `scanned(_:)` blanks the exact spelling `RestTimer`, `forbidden` is unchanged, and a planted `Timer.scheduledTimer` is still caught (the implementer's control). What it gives up: an identifier that contains "RestTimer" hides that one word |
| Deviation 6, `app.scrollViews.count == 1` | **The implementer is right**: Today's scroll view is in the tree under the cover. `WorkoutLoggingAdversarial.test_jumpFromRemaining…` read `scrollViews.firstMatch`; it now reads the scroll view that holds the card's title, asserts there is one, and that it starts under the header. Whether `firstMatch` was Today's was not checked; the new query cannot be |
| Deviation 7, `DependencyKeysTests` | Sound: `haptics_defaultsToAFreshFake` pins a fresh fake per call and that the key still fails outside `withTestDependencies` |
| The six re-recorded `PillButton` references | **Verified pixel for pixel**: rows 0 to 199 (0 to 262 at `accessibility3`) are identical to `main`'s; the first differing row is 200 (263), inside the old image's 26 plain rows. No other existing reference changed |
| Orange (criterion 10) | Pinned by pixel, light and dark, resting and over: only "Skip rest" and the ring's arc; "+30s" has none; at "Rest over" the ring has none (`orange_isSkipRestAndTheArc`) |
| The app's wiring | `AppComposition.bind` binds `LiveHaptics` with the session (read, and the implementer's `boot_bindsTheLiveHaptics`); the UI tests ran the real composition without a trap. Generators are made per play and never prepared: latency of the first buzz is a device question |
| Per-second store updates | One change of `store.model` a second while a rest runs, none after its end; the header's and the page's models are equal values across it; in the hosted `WorkoutRoot` the scroll view is the same view at the same offset after three seconds. Building the whole screen's model takes 0.49 ms (Mac host, debug, mean of 2,000; measured in a scratch test, not asserted) |

### Mutations (25; every file restored from the copy read before the change, `git status` clean of product files)

| # | Change | Existing tests | This round's |
|---|---|---|---|
| M1 | `.restOver` played without the "already played" check | **missed** | `twoWaits_oneBuzz`, `twoWaits_aSlowHaptic_oneBuzz` |
| M2 | played without having seen the rest run | **missed** (their reopen is 1,000 s late) | `startedJustAfterTheEnd_playsNothing` |
| M3 | the window is 2 s | caught | |
| M4 | no "is it still the shown rest" after a wait | caught | |
| M5 | `moment` written once only | caught (9) | walk |
| M6 | the pump does not write `moment` | caught | |
| M7 | `extendsShownRest` true at zero left | caught | storm |
| M8 | "Skip rest" sent with no rest shown | caught | storm |
| M9 | "+30s" guarded by `rest`, not `shownRest` | caught | |
| M10 | haptics played twice while an answer is ahead of the page | **missed** | `laggingUpdates_eachFeltOnce` |
| M11 | `>` for `>=` in `shownRest` | caught | |
| M12 | "Rest over" from one second left | caught | |
| M13 | `nextTick` always a second | caught | walk |
| M14 | no notification call on an end | caught | property |
| M15 | "+30s" reads the date a second time | **missed** | storm (one reading a tap) |
| M16 | "already played" recorded after the haptic returns | **missed** | `twoWaits_aSlowHaptic_oneBuzz` |
| M17 | the ring's share inverted | caught | walk |
| M18 | the notification client called before the update is out | **missed** | `slowClient_doesNotHoldTheUpdate` |
| M19 | the ending update's haptics not played | **missed** | `endingUpdate_isFelt` |
| M20 | the countdown's text rounded down | caught | walk |
| S1 | `WorkoutRoot` without `.task(id: store.shownRest)` | **missed** in the PR lane (UI test only) | `root_keepsTheRestsTime` |
| S2 | the ring animated whatever Reduce Motion says | **missed** | **missed too**: the setting cannot be set in a hosted view; only the function is tested |
| S3 | "+30s" drawn filled | caught (references, trees) | |
| S4 | the panel an overlay, not the scroll view's inset | caught | `screen_roomIsMeasured` |
| S5 | no "updates frequently" trait | caught | `screen_panelComesLast` |

### What held

- `shownRest` on solo exercises against an oracle from the brief, 200 seeds × 60 events; un-logging changes
  neither `rest` nor `shownRest`.
- The walk (40 seeds × 70 steps over the real host): panel text, "Rest over", the ring within a second,
  never a panel without a rest or a rest without a panel; `.setLogged` once a logged set, `.restOver` once
  for each rest that ended within a second of a wait's end and never otherwise (late returns, reopened
  covers, restarted tasks, skipped, extended and replaced rests).
- The storm (40 seeds × 48 taps, saves held, updates lagging, up to 40 s between readings): the same events
  and the same workout as one at a time; each panel tap is the engine's one event for what the session
  showed at the tap's one reading; nothing with no rest shown.
- The host: scheduled equals the workout's rest after every one of 50 events (80 walks, auto rest on and
  off), nothing left at a finish or a discard; no client, same workout, no trap.
- The panel at all twelve text sizes × two widths × Bold Text × right to left × five models: no word cut,
  nothing outside or overlapping, both buttons 44 pt. VoiceOver meets it last, with the time in words.
- In the app (iPhone 17): two quick "+30s" are a minute; no panel on Today; a cover opened again after 3 s
  and an app back from 6 s in the background read the wall clock's time left and go on; "Skip rest".

### Not tested

- A rest's end in the running app ("Rest over", the buzz): the sample rests 150 s, each launch has its own
  database and the app's date moves only at launch. Shown by the store's tests and the hosted root only.
- Anything on a device: haptics felt, VoiceOver heard, Reduce Motion seen.
- Dark, Increase Contrast, Bold Text and right to left in the running app; 40 s in the background (6 s were).
- A refused "+30s" and a "Minimize" behind a rest tap beyond the implementer's two tests.
- The panel over a superset; two covers alive at once over one session (not reachable).
- The rest of the `Nightly` plan, watchOS, the full gate.

### Corrected while testing

My first measure of the panel's room hosted each phone at its height between the safe areas, and the
simulator's window keeps the iPhone 17's 62 pt top safe area as well: every strip came out 62 pt short, and
Accessibility 3 on the shortest phone read as a failure of criterion 13. The UI test at the largest size
passed where that model said it could not, and its screenshot showed why. The windows are now 62 pt taller,
`screen_roomIsMeasured` pins that inset, and the table above is from the corrected model.

### Edits to earlier testers' files

- `WorkoutPumpAdversarialTests.inAStorm` takes `by steps:` (default as it was), so the storm can move the
  date as far as the calm run does.
- `WorkoutLoggingAdversarial.test_jumpFromRemaining_showsTheNewExercisesName`: the scroll view (audit above).

### Commands and exit statuses (2026-10-10; iPhone 17, iOS 27.0; every simulator run through the lock)

| Command | Exit | Result |
|---|---|---|
| `scripts/check.sh --fast` | 0 | format, lint, package graph; 1,239 host tests in 188 suites |
| `swift test --filter "FeatureWorkoutTests\|LedgerSyncTests\|ShownRest"` (Mac host), three times | 1 each | FeatureWorkout 308 tests in 45 suites, **3 red** (F10-S6-1 to -3; F10-S6-4 is simulator-only); Sync 289 in 50; `shownRest` 16 in 2 |
| `PR` plan, `-only-testing:FeatureWorkoutTests`, `LedgerSyncTests/HostRestNotificationAdversarialTests`, `LedgerDomainTests/ShownRestAdversarialTests` | 65 | FeatureWorkout **369 tests in 55 suites, 4 red** (6 issues): the four findings; the other two suites 5 and 4, green |
| `Nightly` plan, `-only-testing:LedgerUITests/WorkoutRestAdversarial`, `…/WorkoutLoggingAdversarial` | 0 | 5 of 5 (2 and 3). Before the last edits (a comment and 16 pt in one assertion) `WorkoutRest` ran with them: 7 of 7 |
| Host mutants M1 to M20, simulator mutants S1 to S5 | | the table above; `git status --short -- LedgerKit/Sources Apps/Ledger` empty after |

The full gate, watchOS and the rest of `Nightly` were not run.

## S6, round 2 (G2 tester, 2026-10-11)

On `7903cc6` (the implementer's fix round 1, `91d9bbb`, and the reviewer's round 2 over it). The contract adds rulings 16 to 21 ("Plan amendments — slice
S6 after round 1") and the two rulings made during the fix round. No product code, implementer's test,
project file or test plan was edited.

### Result

The rulings hold. A tick changes the rest panel and nothing else the cover reads (16); the compact panel
leaves at least 128 pt of page on three phones at every size, also with Bold Text and the longest next-set
line (17); a tap carries the instant it was tapped, in a storm whose time goes by while saves wait (18);
F10-S6-2 and -3 are fixed and their tests pass unedited (20). **Nothing is left red.** F10-S6-1 is pinned
as built. 23 tests added (17 that also run on the Mac host, 6 simulator-only) and three assertions in a UI test. Six things are recorded for later slices, none a defect of this one; one mutant is
still not caught by any test.

### Round 1's findings

| Finding | Now |
|---|---|
| F10-S6-1 the clock set back at "Rest over" | **As built, by ruling 20**, verified, not taken on trust: `clockSetBack_atRestOver_thenATap` and `clockSetBack_atRestOver_thenPlusThirty` (below). For F17 |
| F10-S6-2 a skipped rest felt while the page is behind | **Closed.** `skipped_withThePageBehind_isNotFelt` passes unedited |
| F10-S6-3 a haptic lost when the follow starts again | **Closed.** `followStartedAgain_withAnUpdateBehind` passes unedited |
| F10-S6-4 no page left at Accessibility 4 and 5 | **Closed** (ruling 17). `screen_leavesThePageRoom_beyondTheCriterion` passes unedited; table below |
| Question 1, the time of a tap | **Closed** (ruling 18) |

### F10-S6-1 as built (what I saw, against what the notes say)

The notes are right, and one consequence is not in them. Rest over; the clock set back 60 s; a stepper:
the panel still reads "0:00 · Rest over" (the frozen "1:00 · Resting" of round 1 is gone, because the
panel's moment no longer goes back for a tap). Ten and seventy seconds on: still "Rest over", and nothing
is felt at the true end. A reopened cover reads the date and shows the rest running. **"+30s" on that "Rest
over" does not start a rest of 30 s**: it is judged at the tap's own, earlier, date, finds the rest still
running, and extends it; the lifter who saw "Rest over" and asked for half a minute gets what the clock
says was left and 30 s (90 s in the test, on a ring of 180 s). So since ruling 18 `extendsShownRest` says
what the clock says, not what the panel showed; the two differ only under a clock set back.

### For later slices (pinned as built where a test is named; none is left red)

1. **F17, clocks.** F10-S6-1 with the "+30s" case above (`WorkoutRestAdversarialTests`, two tests); a
   running rest hidden when the clock goes back by more than the rest between two logs
   (`ShownRestClockAdversarialTests`, run this round; round 1 only read it).
2. **F17, an answer older than the page.** `newestRest` asks S5's `ahead`. On one phone `ahead` is never
   older than the page. With a second hand it can be: an answer that comes back after the page has shown a
   later change by the peer is kept as "the newest". While it is, the buzz at zero is judged against it: a
   rest the peer extended ends without a buzz (`staleAnswer_takesThePeersBuzz_asBuilt`). The fault is in
   what `ahead` keeps (S5's), which also plans the next tap on the older workout.
3. **F18, a haptics client that is slow.** `follow()` does not stop when its task is cancelled: it takes
   what its stream had buffered, and at its end marks the store as not hearing the session. The phone's
   client returns at once and nothing shows. With one that does not (the notes already say the watch's
   must): a follow cancelled inside `play` overlaps the next one; a set is felt twice (the new follow's
   `missedHaptics`, then the old follow's own update), and when the old one ends the taps wait until the
   follow starts yet again (`followCancelled_duringASlowHaptic_asBuilt`). A check of `Task.isCancelled` in
   the loop ends all three.
4. **`missedHaptics`, what it is and is not** (the coordinator's questions). Twice: only as in 3. For the
   lifter's own, already felt, change: no (`followAgain_nothingChanged_playsNothing`). A burst: one buzz
   for any number of sets logged while the follow was away, none for an un-log
   (`followAgain_afterABurstElsewhere_oneBuzz`); the notes ask F17 whether a peer's set should be felt on
   return at all. A rest's end, a finish, a record missed the same way: not felt (the engine's account of
   a change between two states knows a logged set only), as the notes say. On the test's session a finish
   missed that way closed the cover with nothing to tell rather than as saved; I did not check that on the
   real host, and it is S4's path, not this round's.
5. **The reviewer's note S6-R2-N1, seen.** A tap carries its own instant (ruling 18), but a rest's end is
   felt by what the session holds when it comes. "+30s" tapped 2 s before zero and still behind a slow
   save at zero: "Rest over" and the buzz; then the tap is applied at its instant, the rest is extended to
   180 s and counts again; its new end is felt too: two buzzes for one rest
   (`extendTappedBeforeZero_appliedAfter_asBuilt`). "Skip rest" the same way is felt, then the panel goes.
   It takes a save slower than the time left. Reported, not ruled.
6. **For the product owner, looks.** Side by side at Accessibility 3 and 4 the two buttons are not the same
   height: "+30s" 54 and 56 pt, "Skip rest" 59 and 64 pt (round 1's look decision 2 made them a pair). And
   the header breaks its two words inside the word, measured: on a 375 pt phone "Minimize" from
   Accessibility 3 and "Finish" from Accessibility 4; on the iPhone 17 "Minimize" from Accessibility 4 and
   "Finish" from Accessibility 5 (from Accessibility 4 with Bold Text). S4's code; a chore.

### Audit of the implementer's edits to my files

| Edit | Verdict |
|---|---|
| `store.model.rest` → `store.restPanel` (5 sites), `WorkoutScreen(model:rest:)` (1) | Sound: the field moved, nothing else changed |
| `screen_roomIsMeasured`, `55 ... 75` → `304 ... 324` | **Sound, and the app agrees.** My model gives 313 pt again; the UI test now asserts the running app's strip within 15 pt of 314 (`test_rest_atTheLargestTextSize_leavesSomeOfThePage`), and that the next set is not drawn and still read |
| `eachSecond_oneChange_thePageUntouched`, `counting(_:)` | Sound as ruled; no strength lost. Added beside it: `tick_changesNothingTheRootReads` (everything the root's body, the header, the page and the dialogs read, by `withObservationTracking`, through ten seconds, 40 s away and the rest's end, with controls both ways) and `sources_onlyThePanelReadsTheMoment` |
| The notes' room table | **Out of date in three columns** (not an edit to my files): it gives, for the iPhone 17, 427, 395 and 328 pt at AX2, AX3 and AX4; the committed code gives 457, 430 and 368 by the same function. The least, 173 pt, is right. Measured table below |

### The compact panel (ruling 17), measured

Page showing over the panel, in pt, the preview's panel, plain text:

| | AX1 | AX2 | AX3 | AX4 | AX5 |
|---|---|---|---|---|---|
| 375 pt, home button | 360 | 326 | 269 | 173 | 182 |
| 375 pt, notch | 441 | 407 | 350 | 254 | 263 |
| iPhone 17 | 491 | 457 | 430 | 368 | 313 |

With Bold Text the buttons go one over the other a size sooner (207 pt on the home-button phone at AX3, 304
on the iPhone 17 at AX4); with the longest next-set line, or a drop set in kilograms, the line wraps (128 pt
on the home-button phone at AX4, the least of all 216 measures). `room_withBoldTextAndLongerWords` asserts
120 pt for all of them.

The buttons stand side by side exactly where "+30s", 8 pt and "Skip rest" fit the panel's width, and one
over the other elsewhere (`buttons_sideBySide_exactlyWhereTheWordsFit`, 40 settings): on a 375 pt phone up
to AX3 (AX2 with Bold Text), on the iPhone 17 up to AX4 (AX3 with Bold Text), stacked at AX5 everywhere.
"+30s" is never cut (round 1's check did not look at it). At AX5 the next set is in the stop's label, the
panel is exactly as tall as one that has no next set, and two things take a tap. Orange is "Skip rest"
alone at AX1, AX3 and AX5, both themes, resting and over.

### Ruling 18, the storm re-derived

Round 1's storm moved the date at each reading, which cannot tell a reading at the tap from one at the
tap's turn (mutant R2 passed it in my head before I ran it; it would have). `storm_eachTapAtItsOwnInstant`
moves the date before each tap and while each call waits (up to 20 s each), records when each tap was
made, and makes the same taps one at a time at those instants: same events, same workout, 40 seeds; and in
the calm run a logged set is done at its tap, "+30s" says what was running at its tap, an un-log within a
second of its set's tap sends nothing. The undo guard behind a held save is of the two taps (0.5 and
0.999 s: held; 1.0 and 1.5 s: applied, however late). A tap earlier than the event before it is taken at
its own date. "`moment` takes a tap's instant only if later": I found no sequence with a clock that runs
forward where the panel is stale for it (the rest's task reads the date at once when a rest changes; the
walk's 40 seeds still pass); with a clock set back it is F10-S6-1.

### Mutations (19 new; every file restored, product tree clean after)

| # | Change | Existing tests | This round's |
|---|---|---|---|
| R1 | `moment` takes every tap's instant | caught | `clockSetBack_atRestOver_thenATap` |
| R2 | the plan reads the date at the tap's turn | caught (3 of his, S5's storm) | `storm_eachTapAtItsOwnInstant`, `undoGuard_behindAHeldSave` |
| R3 | `model` reads `moment` | caught | `tick_changesNothingTheRootReads`, `sources_…` |
| R4 | zero does not ask `newestRest` | my round 1 test only | `extended_withThePageBehind_feltAtTheNewEnd` |
| R5 | `newestRest` prefers the page | my round 1 test only | the same |
| R6 | no `missedHaptics` | my round 1 test only | `followAgain_afterABurstElsewhere_oneBuzz` |
| R7 | `missedHaptics` at every update | caught (26; three tests hang until their time limit) | |
| R8 | a queued tap takes the time of the tap before it | caught | storm |
| R9 | the store's panel is never disabled | **missed** | `panel_isDisabledWhileTheCoverCloses` |
| R10 | `missedHaptics` compares with nothing | caught | |
| R11 | `moment` set by the first tap only | caught | storm |
| T1 | the view passes `isOver: false` to the ring's animation | **missed** | **missed too** (as S2 in round 1: only the function is tested) |
| T2 | the next set drawn at AX5 | caught (his room test) | `largest_nextSetIsSpokenNotDrawn`, room |
| T3 | "Skip rest" not at its own width | caught (the reference) | `buttons_sideBySide_…` |
| T4 | compact buttons from AX3 only | **missed** | `buttons_sideBySide_…` |
| T5 | the store's panel sends its taps nowhere | **missed** in the PR lane | `storePanel_sendsToTheStore` |
| T6 | the root draws no panel | **missed** in the PR lane | `root_keepsTheRestsTime` (the panel's room under the page, against the same root with no rest) |
| T7 | the compact time not at its own width | **missed** | **missed too**: nothing changed at any size I measure; likely an equivalent mutant |
| T8 | the buttons always one over the other | caught | `buttons_sideBySide_…` |

### A test run that did not end

During the mutants two test processes of this worktree were left spinning for hours, and the coordinator
killed them. What I found: under R7 and R10 (haptics that are played too often) tests that wait without a
bound for an exact list of haptics never see it, and a suite's time limit does not end a loop that only
yields; my first mutant driver had no time limit of its own and did not kill the test helper. Mine were
three such waits (`twoWaits_aSlowHaptic_oneBuzz`, `drainSlowly`, `slowClient_doesNotHoldTheUpdate`): each
is now a bounded number of steps and then a failure. The driver now ends a run after 300 s, and every host
run of mine has a limit and kills this worktree's helpers after it. **Still unbounded, the implementer's**:
`eventuallyPlayed` and `RestBench.settled` (`Support/RestBench.swift`), which hang three of his tests under
those mutants; not mine to edit. No test hangs on the code as it is.

### What held from round 1

Everything: the walk (40 seeds), both storms, the host's notification property, `shownRest`'s property, the
panel at twelve sizes, the hosted root (now ten ticks, and the panel's room under the page), orange, the
VoiceOver order, and the UI tests.

### Not tested

- As in round 1: a rest's end in the running app; anything on a device; the ring in motion.
- The compact panel on a real 375 pt phone, or in the running app with Bold Text, dark or right to left.
- How many times SwiftUI evaluates the page's body at a tick: no cheap count without a hook in product
  code. What is pinned is what each view reads (observation and sources) and, in the hosted root, that the
  scroll view is the same view at the same offset after ten ticks.
- A finish missed by a follow on the real host (4 above).
- The rest of `Nightly`, watchOS, the full gate.

### Commands and exit statuses (2026-10-11; iPhone 17, iOS 27.0; every simulator run through the lock)

| Command | Exit | Result |
|---|---|---|
| `scripts/check.sh --fast` | 0 | format, lint, package graph; 1,241 host tests in 189 suites |
| `swift test --filter "FeatureWorkoutTests\|LedgerSyncTests\|ShownRest"` (Mac host, 8-minute limit) | 0 | FeatureWorkout 329 tests in 46 suites; Sync 289 in 50; `shownRest` 18 in 3 |
| `PR` plan, `-only-testing:FeatureWorkoutTests`, `LedgerSyncTests/HostRestNotificationAdversarialTests`, `LedgerDomainTests/ShownRestAdversarialTests`, `…/ShownRestClockAdversarialTests` | 0 | FeatureWorkout **398 tests in 57 suites**; 5 in 1; 6 in 2 |
| `Nightly` plan, `-only-testing:LedgerUITests/` `WorkoutRestAdversarial`, `WorkoutLoggingAdversarial`, `WorkoutAdversarial`, `WorkoutConflictAdversarial` | 0 | **7 of 7** (2, 3, 1, 1) |
| Host mutants R1 to R11, simulator mutants T1 to T8 | | the table above; `git diff --stat -- LedgerKit/Sources Apps/Ledger` empty after; no test helper left running |

The full gate, watchOS and the rest of `Nightly` were not run.

## S7a — round 1 (G2 tester, 2026-10-13)

On `f43c4d4` (range `77b33ec..f43c4d4`), against criteria 1 to 24 and 38 to 40 of "Plan amendments — slice
S7" and "Rulings before G1 — slice S7". No product code, implementer's test, project file or test plan was
edited; the UI test class is a new file the synchronized group picks up.

### Result

The store holds everywhere I attacked it. No logged set is lost, a workout ends once, every failure is shown
and loses nothing, and the announcements are said once each. **Nothing is left red.** Two findings are
measured in the running app (S7a-1, S7a-2), the rest are as built and recorded for the product owner or for
F17. The dark-appearance question is answered: **the simulator** (below).

### Findings

| Id | Severity | Finding |
|---|---|---|
| S7a-1 | P3 | **"Keep lifting" is 42.2 pt tall in the running app** (criterion 38: every target 44 pt). Measured by XCUITest on the iPhone 17 at half height: L, XXXL and AX1 give 42.25 pt (56×42, 80×42, 95×42), AX3 43, AX5 52; mirrored the same. "Save workout" and "Discard" are 51 pt. The hosted reader the implementer used measures the same button at ≥ 44 pt: in the app the sheet's content is 339 pt wide on a 402 pt phone (31 pt margins, not 24), so the presented sheet draws its content about 4 % smaller than the hosted parts. Pinned with `XCTExpectFailure` (non-strict) in `WorkoutFinishAdversarial`. Reproduce: run any `test_sheet_*` and read `G2-SHEET`/the expected failure. Whether it is the system's own sizing of a sheet at its half height (and so not the frame's to fix) I did not establish |
| S7a-2 | P3 | **The failed save's alert coming back after "Try again" is still not pinned by a committed test.** There is no committed hook to make a save fail in the app, so no UI test can. A hosted test cannot either: in a package test's window (no scene) a presentation's dismissal never completes, measured: after the store took the sheet down and said `.saveFailed`, `presentedViewController` was still the sheet's `PresentationHostingController` and no `UIAlertController` was ever presented (round's first runs of `WorkoutRootSaveAdversarialTests`, removed). Adding a Debug launch argument that fails `finish` would be product code: reported, not added. The two-alerts-by-parity spelling stays pinned only by `FeatureWorkoutSourceTests.root_presentsASheet` |
| S7a-3 | P4, as built (O3, R10) | **After a failed save and "Close", the sheet's "Discard" saves the workout** and the cover closes as `.saved`: the alert offers no Discard, but "Finish" opens the sheet with one, and the host completes the waiting end first (contract). `close_thenDiscard_savesTheWorkout_asBuilt`. For the product owner: the lifter tapped Discard |
| S7a-4 | P4, as built (F17) | **Closed as saved on a workout another hand discarded**, unheard: the notes' F17 input, reproduced (`discardedElsewhere_unheard_closesAsSaved_asBuilt`). The notes' "one phone cannot do it" holds on the real host, verified: a discard whose task is cancelled is not let go before its call ends, so no Save can be tapped over it (`host_cancelledDiscard_staysADiscard`). A session client that throws `CancellationError` to a cancelled caller (as the test target's `HeldFinishSession` does, and as a watch proxy might) would make it reachable on one phone: the discard sets `isDiscarding` false, Save is taken, and the new stream's first `nil` reads as saved |
| S7a-5 | P4, as built | **An end the engine will not take can never be saved by "Try again"** (same non-finite end each time); "Close" then a new "Save workout" saves. Unreachable from a system clock. `invalidEnd_tryAgainNeverSaves_asBuilt` |
| S7a-6 | P4, for the product owner | **One line, two ways of writing numbers** outside en_US: "1.234 of 1.250 sets logged · 617,000 lb moved" (de_DE), "١٬٢٣٤ of ١٬٢٥٠ sets logged · 617,000 lb moved" (ar_EG): the counts are the lifter's, the volume the Domain's (rule 34). `numbers_inAnotherLocale_asBuilt` |
| S7a-7 | P4 | "Couldn't save this workout" is the only one of the eight new catalog keys with no translator's comment |

Not findings, recorded: a rest equal by value to the one announced before (same end, same length, which
needs two logs at one instant) is not announced again; and the rest's task is not stopped by `exit`, so a
rest that ends during a held save, or in the instant the cover is going, is still felt and said.

### The dark appearance (item 10): the simulator

With no test harness at all (`simctl` alone, `scratchpad/s7a-g2/dark-probe.sh`): `simctl ui appearance
dark` reads back "dark" and the device's `com.apple.uikitservices.userInterfaceStyleMode` holds
`UserInterfaceStyleMode = 2`, yet **the system's own Settings app draws light**, and so does Ledger launched
by `simctl launch` and Ledger running when the switch is made (three screenshots). So it is neither the app
nor the test: the iPhone 17 simulator (iOS 27.0, C67249F5…) has stopped applying its appearance.
`TabsAdversarial.test_selectedTab_…lightAndDark` fails in its dark half on this tree the same way ("Today is
not in the accent", accent share 0.0). I did not build `main` in a second worktree: 5–6 GB free, a build
needs about 4 GB, and the Settings app settles the question without it. Likely fix (not done; the simulator
is shared): shut down and boot the device, or erase it. The appearance was set back to light after every run.

### Audit of the implementer's two edits to `WorkoutWordsAdversarialTests`

Both sound, no strength lost: the 71-key list still compares both directions plus `catalog.problems`, and
`dialogs_areTheBriefs` compares the same three strings. What the old finish-dialog check covered and the new
model no longer did by itself (the whole sheet model, "Save workout", the line) is now pinned word for word
by `WorkoutFinishWordsAdversarialTests.model_isTheCriterias` (every count, both units, saving or not) and
`texts_areTheSpecifications` (the eight keys, the three invented texts exactly, "Try again" against S4's
"Try again.").

### What held, with numbers

- **No logged set is lost** (`storm_savesWhatTheCalmRunSaves`, 40 seeds by default, 200 run on the host and
  the simulator): up to 40 taps of every kind in bursts, every call held, the page behind, the date moving,
  "Save workout" at a seeded point; then late taps and every control. Same calls, same finished workout,
  same exit as the calm run; ended at the tap, asked once. First 40 seeds: 35 saves, **415 taps still waiting
  at the tap on Save**, 109 sets saved, 681 calls. Taps after "Save workout" are dropped, as criterion 8 says.
- **Exactly once**: double tap and every control while saving; Discard then Save; restart mid-finish in both
  answer orders and with the new stream's first update held back; the updates ending mid-finish and while
  the save waits for a tap; the cover gone for good. And a seeded walk of 90 steps (taps, sheet, alert,
  restarts, held and failing calls, ends elsewhere), 200 seeds: never two ends, two exits, a finish asked for
  an end no tap gave, or a cover at rest still ending. First 40: 60 saves, 17 retries, 116 restarts.
- **Failures**: "Try again" failing 1, 2, 3 and 8 times in a row (four kinds of error, a `CancellationError`
  from an uncancelled task among them): the alert each time on its own attempt, the workout untouched, the
  first end every time. Close on the real host: live, not in history, Minimize answers; **a relaunched host
  saves it, ended at the tap**. Refusals under the open sheet and under a waiting save; a queue that leaves no
  set; deviation 2's "nothing to show".
- **Announcements**: a walk of logs, un-logs, +30s, skips, time, time away, restarts, reopens and redraws on
  the real host, 200 seeds: each new rest said once in words written independently, "Rest over" exactly as
  often as it is felt (first 40: 587 rests said, 32 Rest over, 87 reopens); said after the haptic, once; ten
  times in words with singular forms, three English locales.
- **Words**: the model for nine counts × two units × saving; English plural forms under twelve locales whose
  rules differ.
- **Accessibility**: VoiceOver order, traits, dimming, on-phone and no-overlap at all twelve text sizes × two
  widths × Bold × RTL × eight models; orange is Save's fill alone at four sizes × 16 settings × both themes
  (a one-pixel row 1.3 pt under its frame at AX5 is the fill); in the app at half height **both buttons show
  without scrolling at every size measured** (iPhone 17: Discard's bottom at 627 pt at L, 817 pt at AX5, of
  874); mirrored, Keep lifting at the left; a swipe down keeps the workout; two quick taps on Save save once,
  one Logged card, no alert. In the root: two detents, and no swipe while saving.

### Mutations (15; product tree clean after)

Host, `scratchpad/s7a-g2/mutants.py`, each caught: M1 a second tap answers while saving; M2 Try again ends at
the retry; M3 finish without waiting for the taps; M4 a refusal does not withdraw the save; M5 saved on any
empty first update; M6 `noLiveWorkout` shown as a failure; M7 every pass announces; M8 Rest over said before
it is felt; M9 Save answers while saving; M10 updates ending keep the save; M11 Try again answers any dialog;
M12 a cancelled save is a failure; M13 zero sets saved; M14 a queue left with no set still finishes.
Simulator: T1 no `interactiveDismissDisabled` (caught by `sheet_isPresented_andHeldWhileSaving`). Not
mutated: the two alerts' parity (no test can see it, S7a-2).

### Tests added

`FeatureWorkoutTests/Adversarial/`: `WorkoutSaveAdversarialSession`, `…Cover` (doubles),
`WorkoutSaveAdversarialTests` (+`Once`, `Walk`, `Failures`, `Deviations`), `WorkoutAnnouncementAdversarialTests`,
`WorkoutFinishWordsAdversarialTests` (host and simulator: 42 tests), `FinishSheetAdversarialTests`,
`WorkoutRootSaveAdversarialTests` (simulator only: 4). `Apps/LedgerUITests/WorkoutFinishAdversarial` (7, nightly).

### Not checked

VoiceOver on a device; a save that really fails in the app (S7a-2); the 375 pt phones and dark in the
running app (only one simulator; dark broken); Bold Text in the app; the watch; `main` built.

### Commands and exit statuses (2026-10-13; iPhone 17, iOS 27.0; every simulator run through the lock)

| Command | Exit | Result |
|---|---|---|
| `swift test --filter "WorkoutSaveAdversarialTests\|WorkoutAnnouncementAdversarialTests\|WorkoutFinishWordsAdversarialTests"` (host, 3 runs) | 0 | 35 tests in 3 suites each run |
| the same, `LEDGER_PROPERTY_SEED_COUNT=200` | 0 | after fixing my own `settle()` (it read the session once) |
| host mutants M1–M14 | 1 each | all caught |
| `PR` plan, `-only-testing:FeatureWorkoutTests` | 65 | 499 tests in 71 suites; the only failures were in my two new simulator suites (the AX5 orange row, the scene-less presentation), since fixed or removed |
| `PR` plan, `FinishSheetAdversarialTests`, `WorkoutRootSaveAdversarialTests` | 0 | 4 tests in 2 suites |
| `Nightly` plan, `LedgerUITests/WorkoutFinishAdversarial` | 0 | 7 of 7 (S7a-1 as an expected failure) |
| `Nightly` plan, `TabsAdversarial/test_selectedTab_…lightAndDark` | 65 | dark half fails: the simulator |
| simulator mutant T1 | 65 | caught |
