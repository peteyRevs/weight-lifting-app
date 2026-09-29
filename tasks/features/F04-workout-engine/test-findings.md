# F04 — WorkoutEngine: adversarial test findings (G2)

Independent adversarial pass over `feat/F04-workout-engine` at `1ef35db`. I wrote the tests from the brief,
ADR-004, architecture §6, spec §4.2/§5.3/§6.3/§7.4–§7.6 and decisions #6/#7/#13, using only the public
interfaces. I read the product code after the first round, to find root causes. None of the
implementer's tests or notes were read.

The accepted deviations (no `now:` parameter; `doneAt:`/`exerciseID:`/`amount:`/`endedAt:` labels) are
not findings. Their semantics are tested and hold (see "Attacked and held").

**Tests:** 101 new tests in `LedgerKit/Tests/LedgerDomainTests/Engine/Adversarial/` (16 files; 11 property
tests tagged `.property` on `PropertySeed.all`, plus 2 on its first 50 seeds; 5 macOS-only exit tests).
On the host, 86 pass and 15 fail. On the simulators, which skip the exit tests, 96 run and 13 fail. The
failing tests are left in place as regression tests.

**Gate (2026-09-28):**
- `scripts/check.sh --fast` (host): 591 tests, 576 pass, 15 fail (all adversarial, as listed below).
- Full `scripts/check.sh`, run under the simulator lock:
  - Format and lint pass.
  - iOS `PR` plan: 598 tests, 584 pass, 13 fail, 1 skipped (`ReplayPerformanceTests`, `.slow`).
    `check.sh` stops here (exit 65).
  - watchOS `PR-Watch` plan: run on its own with check.sh step 4's exact command, under the lock.
    589 tests, 575 pass, 13 fail, 1 skipped.
  - Every simulator failure is one of this pass's 13 non-exit tests; no pre-existing test fails.
- Logs: scratchpad `f04-g2-check.log` and `f04-g2-watch.log`.

| Class | Count | Findings |
|---|---|---|
| bug | 1 | 1 |
| minor bug | 2 | 2, 3 |
| spec question | 5 | 4, 5, 6, 7, 8 |

---

## 1. bug — Rest `total` overflows `Duration` and traps; the envelope is persisted, so every relaunch traps again

**Repro** (`EngineTrapAdversarialTests.decodedMaxDurationThenPlus30_doesNotTrap`, macOS exit test):
```swift
// Duration is Codable as [high, low] attoseconds, and any pair decodes:
let event = try JSONDecoder().decode(WorkoutEvent.self, from: Data(
    #"{"restStarted":{"endsAt":…,"total":[9223372036854775807,18446744073709551615]}}"#.utf8))
WorkoutEngine.replay([start, env(event, watch, seq: 1, at: 0), env(.restExtended(amount: .seconds(30)), seq: 2, at: 10)])
// → SIGTRAP (Int128 overflow in `running.total + amount`, WorkoutEngine+Reduce.swift:172)
```
The same trap fires when `.restExtended(amount: .seconds(Int64.max))` is repeated about 19 times
(`hugeDurations_doNotTrap`).

**Expected:** "Bounds … must never trap" (this pass's brief). The engine is the one piece that takes a
peer's decoded values unvalidated. **Actual:** the process crashes. Per ADR-004 rules 5–6 the envelope is
already in the local log, so recovery replays it and crashes again: a crash loop on both devices. Fix
direction: saturate or clamp `total`/`amount` (rest is 30–300 s by domain rule 3), or reject absurd
durations when decoding.

## 2. minor bug — `replay` moves the first `started` to the front even when it is unusable, and drops the envelopes it was meant to buffer

**Repro** (`StartedTerminalAdversarialTests.invalidFirstStarted_doesNotDropBufferedEnvelopes`):
```swift
replay([ started(snapshot with phase .finished) @ t=-20 (tablet, 1),
         started(snapshot for another WorkoutID)  @ t=-15 (tablet, 2),
         setLogged(0, set 0)                      @ t=-5  (watch, 1),
         started(seed)                            @ t=0   (phone, 1),
         setLogged(0, set 1)                      @ t=15  (phone, 2) ])
// expected: sets (0,0) and (0,1) done. actual: (0,0) undone.
```
**Expected:** rule 1 says an early envelope is "buffered by replay ordering". `foldOrder`'s own doc says
it "is applied after it rather than dropped", and `ModelOracle.replay` buffers until the first *usable*
started. **Actual:** `foldOrder` (WorkoutEngine+Replay.swift:24–35) moves the first `started` of any
kind. `step` ignores it, and every envelope before the real start is applied to `nil` and lost. The
property `GarbagePropertyAdversarialTests.garbage_replayMatchesOracle` fails on 46 of 200 seeds (571 of
3,000). At 2,000 seeds with no injected bogus start it still fails 21 times, through a `started` carried
by another workout's envelope. I confirmed that every divergence comes from this one cause.

## 3. minor bug — `replay` dedupes by `(device, seq)` before it drops other workouts' envelopes, so a stray envelope shadows this workout's

**Repro** (`PartitionRaceAdversarialTests.strayWorkoutEnvelope_doesNotShadowSameKey`):
```swift
let stray = env(.restSkipped, watch, seq: 1, at: 5, workoutID: otherWorkout)
let mine  = env(setLogged(0, set 0), watch, seq: 1, at: 10)
reduce-fold [start, stray, mine] → set done      // reduce ignores the other workout
replay([start, stray, mine])     → set NOT done  // `mine` deduplicated away
```
**Expected:** `reduce`'s documented rule ("an envelope for another workout" is ignored) and rule 12
dedupe mean the stray changes nothing. **Actual:** `EnvelopeKey` has no `workoutID`, and seqs restart at 1
per workout (`EventEnvelope.seq` doc), so keys collide across workouts. `foldOrder` keeps the earlier
stray and discards this workout's envelope. **`ModelOracle.replay` has the same dedupe and the same
bug** (the test asserts on both), so criterion 10 cannot catch it. The fix is to filter by workout before
deduping, or to key on workout too. `WorkoutEventStore` is keyed per workout, so the store path is safe;
the risk is a mixed transport buffer (F17).

## 4. spec question — Who persists an envelope that `reduce` ignores but `replay` applies?

**Repro** (all in `TerminalOutcomeAdversarialTests`):
- `envelopeBeforeStarted_isPersisted`: `reduce(nil, setLogged@5)` → `(nil, [])`.
- `lateEnvelopeSortingBeforeFinish_isPersisted`: P finished @100. W's `setLogged@90` (logged during the
  partition) arrives afterwards. `reduce(finished, it)` → `[]`, yet `replay` of both applies the set
  (`setLoggedBeforePeersFinish_convergesOnReplay` passes).
- `losingStarted_isPersisted`: P started @5. W's own `started@3` for the same workout arrives, and
  `reduce` returns `[]`. `replay` picks W's.

**Question:** rule 1 says early envelopes are "buffered" and ADR-004 rule 3 says terminals ignore
*later* envelopes (later in envelope order, not arrival). Replay applies all three, but `reduce` emits no
`.persist`, which is its only signal to "append the envelope to the local log" (`Effect.persist` doc). If
F17 stores remote envelopes only on `.persist`, the two logs differ and criterion 9 fails. The
gap-healing handshake ("seq > N", ADR-004 rule 4) then never resends the lost envelopes, because N has
moved past them. Decide one of:
- (a) `reduce` returns `.persist` for every envelope of this workout, even when ignored.
- (b) F17 persists every received envelope for the workout regardless of effects. `reduce`'s doc should
  say so.

Also decide what happens to a late pre-terminal envelope that arrives after `.materialize` and
`compact`: the replayed state now differs from the stored workout.

## 5. spec question — `reduce` is not idempotent for a duplicate delivery; effects repeat

**Repro** (`EffectsAdversarialTests`):
- `duplicateRestExtended_extendsOnce`: `reduce(reduce(s, +30 s), same envelope)` → `endsAt` +60 s
  (replay correctly gives +30 s).
- `reduceTwice_equalsOnce` fails only for its `restExtended` case.
- `duplicateSetLogged_noSecondHaptic`: the second delivery re-emits `.haptic(.setLogged)`, `.persist`
  and `.transmit`.

**Question:** ADR-004 lists "idempotence: apply twice → same state" under Consequences (line 94), and
testing-strategy §2.1 (line 80) names `reduce_isIdempotentForDuplicates(seed:)`. `reduce` has no log, so it
cannot dedupe; the caller must dedupe by `EnvelopeKey` first, and neither the brief nor `reduce`'s doc
says so. Either document that precondition and retarget the law at replay, or give the state what it
needs (for example a per-device high-water seq) to drop duplicates.

Related: effects ignore origin and age. On reconnect a device that reduces N remote `setLogged`s plays N
haptics and may schedule a rest notification whose `endsAt` is already past. F17 needs a rule for which
effects a remote envelope may run.

## 6. spec question — Wall-clock ordering loses the lifter's action under realistic clock skew

**Repro** (`ClockSkewAdversarialTests`; the devices still converge, but on the wrong state):
- `logOfPeerAddedSet_behindClock_isKept`: W adds a set @100. P, whose clock is 10 s behind, sees it and
  logs it @95. Replay applies the log first (unknown set, no-op) and then the add, so **the set is not
  done**. P showed it done before rebuilding.
- `unlogOfPeerLog_behindClock_isKept`: W logs @100. P, 5 s behind, un-logs it @95. The set comes back
  done.
- `ownUnlogAfterClockStepBack_isKept`: one device logs (seq 2, @100), NTP steps its clock back, then it
  un-logs (seq 3, @98). Live the set is undone; after a relaunch replay (ADR-004 rule 6) it is done
  again. The device's own seq order is not respected.

**Question:** the user story says "in any order of arrival, with no lost sets". ADR-004 rule 2 orders by
`(wallClock, device, seq)` only. Should F17 stamp envelopes with a hybrid logical clock
(`wallClock = max(now, newest wallClock seen or sent + 1 ms)`), which keeps each device's seq order and
causal order? That needs an ADR-004 note. Otherwise, accept and document the skew window.

## 7. spec question — Two different envelopes that share a key make `replay` depend on arrival order

**Repro** (`CodableOrderingAdversarialTests.conflictingKey_replayDependsOnArrival`): `setLogged` and
`restExtended`, both `(watch, 1) @10`. `replay([start, a, b]) != replay([start, b, a])`.

**Question:** `EventEnvelope`'s doc makes a unique key a precondition, and only `WorkoutEventStore.append`
enforces it (`EngineError.conflictingEnvelope`). Two paths can still break it: the transport receive path
(F17), and a watch that recovers with a truncated log and reuses a seq it already transmitted
(`persist` and `transmit` are separate effects). Should `replay` break the tie deterministically, or must
F17 check keys on receive? Either way, rule 12 ("a pure function of the envelope set") holds only under
that precondition, and the brief should say so.

## 8. spec question — Materialization hand-off has a crash window and a thin payload

No test; this is protocol shape, not reducer behaviour.
- `WorkoutEventStore.liveWorkoutIDs()` returns only logs with no terminal. If the app is killed after the
  `finished` envelope persists but before F05's materialization commits, the relaunched app sees no live
  workout and has no query for "finished, not yet materialized". The workout never reaches history, and
  its log is never compacted.
- `.materialize(WorkoutSummary)` carries receipt strings and counts, but no sets and no
  `programUpdates`. F05 needs the final `WorkoutState` to write `logged_sets` and apply decision #13, so
  criterion 12 is met through the state only.

Add an `unmaterializedWorkoutIDs()` (or widen `liveWorkoutIDs`) and state in F05's brief where the final
state comes from.

---

## ModelOracle independence (criterion 10)

`ModelOracle` never calls `WorkoutEngine` or `SupersetRounds` (verified by reading and grep). It uses its
own loops and its own copy of the order comparator (`uuidString`), and it agrees with the engine on 3,000
seeds of this pass's multi-device generator and on garbage logs. But it was written "from the brief and
F04's implementation notes", so it shares the engine's interpretations, and four blind spots follow:
- It **shares finding 3** (dedupe before the workout filter).
- Its `apply` is equally non-idempotent (finding 5).
- It models **no effects**, so criterion 10 checks no effect list.
- It orders purely by wall clock (finding 6).

It **disagrees** with the engine in one place (finding 2), which shows the implementer's criterion-10
generator never produced an unusable `started`.

## Attacked and held

- **Rule 1:** started on nil gives the snapshot; a second started (even a different snapshot) is ignored
  with no effects. A non-live or mismatched-ID started never starts the workout. An envelope that sorts
  before the started is applied by replay.
- **Rule 2 / criterion 6:** after finished or discarded, every event kind from either device changes
  nothing and emits nothing. With two terminals, the first by envelope order wins (tie broken by device
  ID). A terminal whose wall clock sorts before the started ends the workout, and incremental devices
  agree in every arrival order.
- **Rule 10 / spec §7.6:** finished sets phase and endedAt, clears rest, and materializes a summary:
  elapsed frozen at endedAt, and exact volume. That volume is 1677.5 lb·reps for 187.5×5 + 185×4. A
  finish before the start gives elapsed 0. Discard emits `discardLog` and cancel, with no receipt.
- **Criterion 12:** a swap with `alsoUpdateProgram` survives finishing in `programUpdates`. A one-off
  swap records nothing.
- **Rule 3 / criteria 1–4:** criteria 1–4 hold exactly. Rest is anchored to `doneAt`, not the wall clock.
  A relog of a done set overwrites its values but leaves rest and cursor alone.
- **Supersets:** three members with unequal counts (A3 B2 C4) rest only after each round's last member,
  for the group maximum of 120 s, and the cursor walks the round-robin order into the next block. An added
  set to B makes A2 no longer last of its round. Unlog then relog restarts rest and advances the cursor
  again. Drop rows form the final round: AD does not rest and BD does. An added row sits after the drop row
  in storage but before it in display order.
- **Rule 20 edges:** the cursor wraps to the earliest undone row. It goes to the first set of the next
  block even when that set is done (prototype `nextOf`). It stays put when the last block is complete. A
  next block whose first member is empty starts at C1, and an empty next block never leaves the cursor
  on a missing row.
- **Rest (rule 9, decision #7, criterion 5):**
  - Extending with no rest starts one at wall clock + 30 s. Extending twice accumulates.
  - Extending exactly at zero, after zero, or after a skip restarts a fresh 30 s rest; 1 ms before zero,
    it extends.
  - Skipping with no rest is harmless. Skipping a running rest clears it and cancels the notification.
  - Extends and restarts reschedule the notification.
  - A manual rest is overtaken by a later auto rest, but survives a set that is not last of its round,
    and survives when auto-rest is off.
  - Two devices extending concurrently both count, in any arrival order.
- **Rules 5–8 and 11:** LWW is per field (criterion 11 holds in every arrival order).
  - Every written weight is clamped to ≥ 0 (setLogged, target, repeat, added).
  - Exact Decimal weights pass through, including 187.5 lb, 102.5 kg and 1e-7 g, with exact volume.
  - Rows added with the same ID from two devices collapse to one, and the first by order wins. An added
    ID taken by another exercise is ignored. An added row is normalized to undone `.added`.
  - Repeat covers drop and added rows and keeps done times.
  - A swap changes only the ID and name, including inside a superset.
  - Select works on undone rows and ignores done or missing rows.
- **Bounds:** every index-addressed event at −1, count, `Int.max`, `Int.min` and `Int.max − 1` changes
  nothing and emits no haptic or live-activity update. So do unknown set IDs and IDs sent to the wrong
  exercise. An empty session, and a snapshot with a wild cursor, do not trap.
- **Exit tests pass** for ±infinity and distant dates, NaN and ±`greatestFiniteMagnitude` weights through
  finish and summary, `seq = UInt64.max`, and extreme indices.
- **Effects:** each event emits exactly persist + transmit + its own effects + one `updateLiveActivity`
  (10 cases). Ignored envelopes emit nothing. An accepted no-op emits persist and transmit only. Unlog
  never cancels the rest notification.
- **Convergence (properties, 200 seeds on the PR lane and 3,000 seeds locally, all green):**
  - Replay is invariant under shuffles and under duplicating any envelopes (criteria 7–8).
  - 2–3 devices with skewed clocks, wall-clock ties, equal wall clock and device, and partitions converge
    after healing, with shuffled and duplicated delivery (criterion 9).
  - A device following ADR-004 rule 2 (reduce when in order, else replay) matches replay after every
    arrival.
  - A sorted fold of reduce equals replay.
  - Engine and `ModelOracle` agree step by step and on replay (criterion 10).
- **Hand-built races:** same set at the same instant (log, target, unlog); both devices log the same set
  (one done row, the first logger's rest); swap vs log; a third device hearing a log before the add it
  depends on; three devices editing disjoint fields.
- **Garbage (200 and 3,000 seeds):** no traps. The exercise list is fixed, rows only grow, set IDs stay
  unique, weights stay ≥ 0, terminals stick, and a cursor that has pointed at a real row keeps doing so.
- **Codable and ordering:**
  - Every event case round-trips through JSON and binary plist. So do envelopes with sub-microsecond
    wall clocks, `seq` near `UInt64.max`, and wall-clock ties; their keys and sort order survive.
  - A random log replays identically after a JSON round trip.
  - Reps 0 on the wire fails to decode.
  - `<` is a strict total order on distinct keys. It equals the spelled-out
    `(wallClock, uuidString, seq)` order and `ModelOracle.precedes` for random device UUIDs.

---

# Round 2 — after fix round 1 (d2de958)

Independent adversarial pass over `feat/F04-workout-engine` at `d2de958`. The contract is the brief, ADR-004
with its 2026-09-29 amendment (hybrid logical clock), and the orchestrator decisions on findings 4–8
recorded in `implementation-notes.md` ("Fix round 1"). I wrote the new tests from those texts and the public
interfaces. The host models (`HybridClock`, `SimHost`) are my own, not the implementer's `HLCDevice` or
`StoringHost`. I read the product code only to find root causes. No product code was edited.

**Convention.** A test that fails is a bug or minor bug; it stays in the branch as a regression test. A
spec question is pinned by a passing test marked "(documents)". That test shows the behaviour under each
reading of the contract, so the gate stays red only for bugs.

## What I wrote

35 new tests in 9 files under `LedgerKit/Tests/LedgerDomainTests/Engine/Adversarial/`:

| File | Tests | What it attacks |
|---|---|---|
| `RestBoundAdversarialTests` | 11 (2 macOS exit) | `longestRest`, the saturating +30s sum, `elapsed`; finding 9 |
| `EventStoreAdversarialTests` | 10 | `append` returning what it newly stored; live vs unmaterialized vs replay; finding 11 |
| `EventStoreContractProbes` | support | 9 contract probes (`StoreProbe.violations`), usable by F05 against GRDB |
| `EventStoreMutationAdversarialTests` | 2 (11 cases) | the probes pass `InMemoryEventStore` and kill 10 mutant stores; finding 10 |
| `MaterializeAdversarialTests` | 3 (1 property) | `.materialize(finalState)`, `summary` from it, the re-materialisation rule |
| `HLCHostAdversarialSupport` | support | `HybridClock` (the amendment's formula); `SimHost`, a host that stores first and reduces or rebuilds |
| `HLCScenarioAdversarialSupport` | support | seeded 2–3-device sessions: ±30 s skew, clock steps back, per-link partitions, relaunches, batched, shuffled and duplicated delivery |
| `HLCConvergenceAdversarialTests` | 5 (1 property) | HLC convergence and "every lifter action kept"; controls for findings 12–14 |
| `HostContractAdversarialTests` | 4 | minimal repros for findings 12–14 |

- **Host:** 30 pass, 5 fail. All five failures are finding 9: three plain tests and both exit tests.
- **Simulators** (no exit tests): 33 run, 3 fail.
- **Property tests:** the two `.property` tests run on `PropertySeed.all`; four aggregate tests run on its
  first 100 seeds.

## Results per plan

**Gate (2026-09-29):**
- `scripts/check.sh --fast` (host): 636 tests in 103 suites; 631 pass, 5 fail (finding 9).
- `scripts/check.sh --lint-only`: format and lint (`--strict`) pass.
- Full `scripts/check.sh` through `sim-lock.py` (log: scratchpad `f04-g2r2-check.log`):
  - Format passes (0 of 198 files), lint `--strict` passes, and the package graph is unchanged.
  - iOS `PR` plan: 641 tests; 637 pass, **3 fail**, 1 skipped (`ReplayPerformanceTests`, `.slow`).
    The 3 failures are finding 9's plain tests, and `check.sh` stops here (exit 65).
- watchOS `PR-Watch` plan: I ran it on its own, with check.sh step 4's exact command, under the lock (log:
  `f04-g2r2-watch.log`). 632 tests; 628 pass, **3 fail** (the same three), 1 skipped.
- No pre-existing test fails on any lane. The first full run (`f04-g2r2-check-run1.log`) compiled before
  the final assertion of `hlcDraggedStamp_turnsAnExtendIntoARestart` existed. The run reported above covers
  the final code.

**Nightly settings on the host** (`LEDGER_PROPERTY_SEED_COUNT=3000`):
- The HLC property and the materialise property pass at 3,000 seeds. Across those sessions: 92,738
  envelopes, 20,255 last-word actions checked, none lost, 0 early stamps.
- The round-1 regressions for findings 2 and 3 pass at 5,000 seeds.

## Close-out of findings 1–3

| # | Status | Evidence |
|---|---|---|
| 1 | **Resolved**, with a residual filed as finding 9 | Both round-1 exit tests (`decodedMaxDurationThenPlus30_doesNotTrap`, `hugeDurations_doNotTrap`) pass unchanged on the host. The clamp and the saturation hold at every edge I tried (see "Attacked and held"). The residual: the bound is measured from an anchor that is itself unchecked, so a stored envelope can still crash the rest UI. |
| 2 | **Resolved** | `invalidFirstStarted_doesNotDropBufferedEnvelopes` passes. `garbage_replayMatchesOracle` passes at 200 seeds and at 5,000 (it failed at 2,000 before the fix). `foldOrder` now fronts only a usable `started`. |
| 3 | **Resolved** | `strayWorkoutEnvelope_doesNotShadowSameKey` passes, including its assertion on the oracle. `foldOrder` filters before it dedupes: `$0.workoutID == workout && seen.insert($0.key).inserted`. The `&&` short-circuit is load-bearing, and a stray key is never inserted. The oracle's fix is its own loop code. |

## Audit of the tests fix round 1 edited

No edit is rejected. Every weakening or retarget rests on an orchestrator decision.

| Test (edit) | Verdict | Reason |
|---|---|---|
| `EffectsAdversarialTests.reduceTwice_equalsOnce` → `duplicateInLog_replayEqualsOnce` | Accept | Decision 5 moves the idempotence law to `replay`. It still ties replay to a single `reduce` for every case. `reduce` has no log, so it cannot be idempotent for `restExtended`. |
| `duplicateSetLogged_noSecondHaptic`, through `StoringHost` | Accept | Decision 5's precondition (dedupe by key before reducing). The assertions are unchanged. |
| `duplicateRestExtended_extendsOnce`, through `StoringHost`, plus `replayed() == state` | Accept | Same decision, and the test is stronger. |
| `terminalCases` (`finished`) expects `.materialize(final state)` | Accept | Decision 8. |
| `TerminalOutcomeAdversarialTests.materialized` / `summaries` and callers | Accept | Decision 8. The numeric assertions are unchanged, and `materialized == [ended]` is added. |
| The three `…_isPersisted` → `…_isStoredByHost` | Accept, with a note | Decision 4(b): the assertion moves from the effects to the host's store. Note: `envelopeBeforeStarted_isStoredByHost` asserts on `host.replayed()`, not `host.state`. `StoringHost.state` keeps that early set undone even after the `started` arrives. That is right for the decision, but `StoringHost` is not a correct host (finding 13). |
| The three `ClockSkewAdversarialTests`, stamped by `HLCDevice` | Accept | Decision 6. `HLCDevice` uses the amendment's formula, identical to my independent `HybridClock`. The assertions are unchanged. |
| New: `withoutHLCPrecondition_rawSkewedStamps_convergeOnStampOrder` | Accept | It documents the precondition, and asserts convergence over 24 arrival orders. |
| `conflictingKey_replayDependsOnArrival` → `conflictingKey_storeRejectsSecond_replayPrecondition` | Accept | Decision 7 says `replay` breaks no tie. The old assertion demanded exactly what the decision rules out. The new one asserts that the store enforces the precondition in both arrival orders. |
| `EffectTests.effects_finished`, `ReduceTerminalTests.finished_endsAndMaterializes`, `criterion12_programUpdate_survivesFinish` | Accept | Decision 8. |
| `ReplayTests.foldOrder_dedupesAndLeadsWithStarted`: a log with no `started` folds to `[]` | Accept | Findings 2 and 3. `foldOrder` is internal, and `replay` of that log is `nil` as before. |
| `EngineAdversarialSupport`: `StoringHost`, `HLCDevice` added | Accept as support | `StoringHost` must not be promoted to `LedgerTestSupport` as it is (finding 13). |
| `ModelOracle.replay`, filter before dedupe (`LedgerTestSupport`) | Accept | The oracle had finding 3's bug. The fix is its own loop code, and it still never calls the engine. |

## New findings

| Class | Count | Findings |
|---|---|---|
| bug | 1 | 9 |
| minor bug | 1 | 10 |
| spec question | 4 | 11, 12, 13, 14 |

### 9. bug — Absurd or non-finite dates escape the rest bound: the rest ring traps on a JSON value, and NaN breaks `==`

The fix measures "at most `longestRest` after the rest starts" from the rest's own anchor. It never checks
the anchor.

**Repro 1** (`RestBoundAdversarialTests.autoRest_absurdDoneAt_endsNearItsEnvelope`, and its exit twin):
```swift
// Default JSONDecoder; 1e21 is a finite JSON number.
let event = decode(#"{"setLogged":{…,"doneAt":1e21}}"#)
let rest = replay([start, env(event, watch, seq: 1, at: 20)])!.rest!   // auto rest anchored at doneAt
rest.endsAt.timeIntervalSince(engineTime(20))   // 1e21, not ≤ 3600
rest.remaining(at: now)                         // SIGTRAP: Duration.seconds(1e21 s)
```

**Repro 2** (`snapshotRest_absurdEndsAt_isHeld` and its exit twin): a JSON `started` snapshot whose `rest`
ends at 1e21. The engine takes the snapshot's rest verbatim; only rests it writes are clamped. So
`fraction(at:)` traps too.

**Repro 3** (`nanEndsAt_isHeld_andStateEqualsItself`): a binary-plist `restStarted(endsAt: NaN)`.
- `min(NaN, bound)` returns NaN, so the clamp keeps it.
- `rest.endsAt` is NaN, and the notification is scheduled at NaN.
- `replay(log) != replay(log)`, because `Date(NaN) != Date(NaN)`.
- `Date`'s `<=` passes NaN, so a date comparison hides it.

**Expected:** fix round 1's own bar, "no decodable envelope traps", and a replayed state that equals
itself. **Actual:**
- The envelope is stored (decision 4). Every relaunch replays it, and every rest view calls
  `RestTimer.remaining` (F02), which traps: finding 1's crash loop, one layer up.
- The fix notes hand hostile stamps to F17's HLC drift bound. That bound checks `wallClock` only. It
  covers neither `doneAt` nor a snapshot's rest, so they have no owner.

**Fix direction:** either
- hold every date the engine takes from a payload (`doneAt`, `restStarted.endsAt`, the snapshot's `rest`)
  to within `longestRest` of the envelope's `wallClock`, mapping non-finite values there; or
- make `RestTimer.remaining` saturate, as `elapsed` now does, and state the NaN rule.

The three plain tests assume the first option.

### 10. minor bug — The store contract suite passes 6 of 10 plausible buggy stores

`WorkoutEventStoreContractTests` is what F05 will run against its GRDB store. I ran it against ten
single-fault mutants of `InMemoryEventStore`. Each mutant was a temporary patch, restored afterwards; the
log is scratchpad `f04-r2-mutation.log`.

It **misses six**:

| Mutant | Why it matters |
|---|---|
| `append` returns new envelopes sorted by `seq`, not in the order given | The first batch in the suite is already sorted. |
| A conflict inside one batch keeps the first envelope instead of throwing | The suite has no conflict within a batch. |
| A same-key envelope with the same event but another `wallClock` is treated as a duplicate | That is a different envelope, and it breaks decision 7. |
| `highestSeq` is the latest stored `seq`, not the maximum | The suite appends seqs in ascending order. |
| `liveWorkoutIDs` lists a log that has no `started` | A received envelope that arrived before the `started` would be "resumed" as a workout that replays to `nil`. |
| Only `finished` is terminal | A discarded workout is listed live forever, resumed on every launch, and never compacted. |

It catches four: `append` returning the whole batch, keeping part of a rejected batch, keys shared across
workouts, and `compact` deleting every log.

**Repro:** `EventStoreMutationAdversarialTests` (`MutantEventStore`). My nine probes in `StoreProbe`
catch all ten mutants and pass `InMemoryEventStore`.

**Fix:** fold the probes, or equivalent cases, into `WorkoutEventStoreContractTests`.

### 11. spec question — The store's lifecycle lists are predicates on event kinds, not on what replay makes of the log

Three cases, all pinned by passing "(documents)" tests in `EventStoreAdversarialTests`:

**a. A live log that replays to `nil`** (`unusableStarted_isLive_butReplaysToNil`). A log whose only
`started` is unusable (not live, or for another workout) is listed live for ever. Resume replays it to
`nil`.

**b. An orphan log after compaction** (`compactedThenPeerResend_orphanLog`). Compaction resets
`highestSeq` to `nil`. If F17 runs the "seq > N" handshake for that workout, the peer resends its whole
log, with no `started`:
- with no terminal in it, the log is on neither list and lingers (the implementer's open item);
- with the peer's finish in it, it is listed unmaterialized and replays to `nil`.

**c. A hole that never heals** (`holeBeforeTerminal_neverHeals_andLaunchStepDropsIt`):
1. The phone receives the watch's seq 3 (its finish) without seq 1–2, for example a dropped mirroring
   message.
2. `highestSeq` is 3, so the handshake asks only for seq > 3, and the hole never heals.
3. The documented launch step (replay, materialise or drop, then compact) finds `nil` to materialise, and
   compacts.
4. On the phone, which materialises, the workout never reaches history.

**Questions:**
- What does the launch step do with an unmaterialized log that replays to `nil`? Keep it and re-request
  it, rather than compact it?
- Should the handshake base be the highest *contiguous* seq per device, not the maximum?
- Should the two lists be defined by replay (live means `replay` is live; unmaterialized means `replay` is
  terminal)?

### 12. spec question — The HLC's newest stamp must survive a relaunch; the amendment does not say where it lives

The amendment defines `wallClock = max(now, newest seen or sent + 1 ms)` but not where "newest" lives. A
host that keeps it in memory starts empty after a kill (ADR-004 rule 6).

**Repro** (`HostContractAdversarialTests.hlcAfterRelaunch_mustBeRecoveredFromTheLog`):
1. The phone logs a set at 100 s.
2. It relaunches, and its clock steps back 5 s.
3. It un-logs the set: stamp 97 s < 100 s.

Replay applies the un-log first, so the set is **done again on every device**. The phone's own screen
flips back as it rebuilds, which is finding 6 again.

Recovering "newest" from the store's maximum `wallClock` fixes it. After decision 4 the store holds
everything seen or sent. In random sessions a forgetful host stamped 38 envelopes early, in 19 of 100
sessions (`forgottenClockOnRelaunch_stampsEarly`).

**Question:** should the amendment say "on launch, `newest` = the largest stored `wallClock` of the
workout"?

### 13. spec question — The host loop is underspecified: "reduce exactly what `append` returns" is not replay, and a rebuild has no effects

The docs give two readings:
- `append`'s doc says "the host reduces exactly these"; `reduce`'s precondition says the same.
- ADR-004 rule 2 and `replay`'s doc say a remote envelope is applied by rebuilding from the merged log.

Three things go wrong between them:

**a. Reducing in arrival order is not replay** (`arrivalOrderReduce_divergesFromReplay`). The fix round's
`StoringHost` reduces every newly stored envelope in arrival order:
1. W, partitioned, sets set 1's weight to 200 at 10 s.
2. P logs it at 185 at 20 s.
3. On healing, P shows 200, while W and replay show 185.

The devices disagree until something rebuilds. In random partition sessions this loop left replay 1,081
times, in 92 of 100 sessions (`naiveHostLoop_leavesReplay`).

**b. Rebuilding for one envelope, then reducing the next, applies it twice**
(`rebuildThenReduceInOneBatch_appliesTwice`). The store already holds the whole batch, so a rebuild
covers every envelope in it. Reducing a later envelope of the same batch applies that envelope twice: one
+30s gave +60 s. My own first host model had exactly this bug, and it cost me an investigation. A loop that
holds:
- if every newly stored envelope sorts after the newest one applied, reduce them in sort order;
- otherwise, rebuild once.

`SimHost` does this, with 0 departures from replay over 3,000 seeds.

**c. A rebuild returns no effects, and a finish reduced on `nil` is lost.** In
`rematerialization_convergesInEveryArrivalOrder`, 20 of 60 arrival orders never ran a `.materialize`
live: both finishes arrived before the `started`. Decision 4's "materialise *again*" assumes a first
materialisation. Those workouts wait for the next launch (`unmaterializedWorkoutIDs` then covers them).
A remote skip or finish applied by a rebuild likewise cancels no rest notification.

**Question:** should the loop be written into `reduce`'s and `append`'s docs, or ADR-004 rule 2, as
follows?
- Reduce, or rebuild once, as in b.
- On a rebuild, derive effects by diffing old and new state: a phase change gives materialise or
  `discardLog` plus cancel; a rest change gives schedule or cancel.
- Materialise whenever the replayed log is finished and differs from what is stored, including when
  nothing is stored.

F17 should then be given a correct host model, not `StoringHost`.

### 14. spec question — Under HLC stamps, a "+30s" near the end of a rest restarts it instead of extending it

`restExtended` carries no time of its own; ADR-004's `restExtended(by:at:)` did. So rule 9 judges "is a
rest running?" at the envelope's `wallClock`. The HLC drags that stamp up to the peer's skew ahead of the
lifter's clock. The rest's `endsAt` was anchored on the device clock (`doneAt`, which hosts fill from
`now`, as the fix round's own `ClockSkewAdversarialTests` do).

**Repro** (`hlcDraggedStamp_turnsAnExtendIntoARestart`), with the watch's clock 20 s ahead:
1. At real 100 s the phone logs bench set 1. The rest runs to 250 s by the phone's clock.
2. At real 232 s the lifter turns the watch crown for set 2's weight. The watch stamps 252 s.
3. At real 240 s the phone shows 10 s of rest left, and the lifter taps +30s.
4. The phone stamps 252.001 s, at or after the rest's end, so the engine starts a fresh 30 s rest: `endsAt`
   282.001 s, total 30 s.
5. The lifter expected `endsAt` 280 s and total 180 s. The ring jumps back to full.

With raw clocks, the same tap extends (stamp 240 s), so the amendment introduced this. It hit 7 of 100
random 40-step sessions (`dragStamps_judgeRunningRestsOver`).

**Question:** should `restExtended` carry the device-clock time of the tap (as ADR-004 first had it), or
the `endsAt` the lifter saw? Or is this accepted and documented? Either way, the amendment should say which
clock the payload times (`doneAt`, `restStarted.endsAt`, `endedAt`) use.

## Attacked and held

**Rest bound (`longestRest`) and the +30s sum:**
- Rests of 60–600 s, plus ten +30s taps, are unchanged (6 cases).
- A 300 s automatic rest reaches exactly one hour after 110 taps. The 111th tap pins the total, and
  `endsAt` still grows. The remaining time stays ≤ the total, so `fraction` ≤ 1.
- 130 taps in 13 s hold `endsAt` at the last tap + 1 h.
- Edges:
  - exactly one hour is kept, and one attosecond more is cut;
  - a zero total stays, and −1 attosecond goes to zero;
  - both `Duration` extremes are handled;
  - a rest already over when stamped is kept.
- Zero and negative +N follow rule 9's arithmetic, with only the total floored at zero.

**`elapsed`:**
- A 3 h workout is exact to 10,800.25 s, in both `elapsed` and the receipt.
- It is zero before the start.
- Saturation starts only near 2^63 s; 1e18 s is below the cap.
- Nit: the doc says "saturates at `Int64.max` seconds", but the value is `Double(Int64.max)` = 2^63 s, one
  second more.

**`append`:**
- A partial batch returns only its new envelopes, once each, in the order given.
- A conflict inside one batch rejects the whole batch, and a retry succeeds.
- The same event with another stamp is a conflict.
- One batch can carry the same key for two workouts.
- An empty batch returns nothing.
- A host fed a repeated envelope, then a half-new batch, runs exactly the new envelope's effects.

**Lifecycle:**

| Log | Live | Unmaterialized | Replays to |
|---|---|---|---|
| Early envelope only | no | no | `nil` |
| Started | yes | no | live |
| Finished | no | yes | finished |
| Compacted | no | no | `nil`, and `highestSeq` is reset |
| Discarded | no | yes | discarded |
| Two racing terminals | no | yes | the first terminal |

**Store contract:** `InMemoryEventStore` passes all nine probes.

**Materialise:**
- On a 3 h two-device workout, `.materialize` carries exactly the final state, which equals replay of the
  reversed log.
- `programUpdates` and the watch's weight bump survive.
- `summary` from that state is exact: elapsed 3 h, 3 of 18 sets, 2,227.5 lb·reps, the PR passed
  through, and the rows carry the swap.
- On 3,000 random sessions there is exactly one payload when the first terminal is a finish, none for a
  discard, and it equals the reduced state and shuffled replay.
- Re-materialisation: in 40 of 60 arrival orders the record ends as replay of the whole log. The other 20
  are listed unmaterialized.

**HLC (200 seeds on the PR lane, 3,000 locally):**
- Hosts that store first and then reduce or rebuild never leave replay.
- Every stamp sorts after everything its device held.
- All hosts converge, and none misses an envelope.
- Not one of 20,255 last-word logs or un-logs is lost.
- The control shows the property has teeth: raw clocks give 817 early stamps and 4 lost actions in 100
  sessions.
