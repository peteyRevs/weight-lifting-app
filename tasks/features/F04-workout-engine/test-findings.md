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

---

# Round 3 — after fix round 2 (ab8faa1)

Independent adversarial pass over `feat/F04-workout-engine` at `ab8faa1`: fix round 2 plus the orchestrator's
correction on remote haptics. The contract is the brief, ADR-004 with its amendments (hybrid logical clock, the
clock rule, malformed envelopes, recovery on launch, the host loop and its effects, as corrected), and the
orchestrator decisions A–G and the correction in `implementation-notes.md`. I wrote the new tests from those
texts and the public interfaces. My host model, `LiteralHost`, follows ADR-004's loop as written, with the
corrected remote effects; it is not `SimHost`, `StoringHost` or `Replica`. I read the product code only to find
root causes. No product code was edited.

**Convention** (as in round 2): a failing test is a bug or a minor bug, and stays in the branch as a regression
test. A spec question is pinned by a passing test marked "(documents)".

## What I wrote

24 new tests in 7 files under `LedgerKit/Tests/LedgerDomainTests/Engine/Adversarial/`:

| File | Tests | What it attacks |
|---|---|---|
| `Round3WellFormedAdversarialTests` | 7 | the predicate: false positives, its edges, dates it misses or checks for nothing; findings 15, 16 |
| `Round3RestIntentAdversarialTests` | 5 | "+30s" intent under phone/watch races; finding 20 |
| `Round3EffectsAdversarialTests` | 3 (1 property) | `effects(from:to:)` against `reduce`; the discard's order; finding 21 |
| `Round3HostAdversarialSupport` | support | `LiteralHost`: the ADR-004 loop read literally, with a switch for the two readings of "applied" |
| `Round3ScenarioAdversarialSupport` | support | seeded 2–3-device sessions: ±30 s skew, clock steps back, cut links, random-subset deliveries (a lost message, then its resend), shuffles, copies, relaunches |
| `Round3HostAdversarialTests` | 6 (1 property) | the literal loop's convergence and effects; findings 17, 18, 19 |
| `Round3StoreAdversarialTests` | 3 (one with 3 cases) | the contract suite against lossy stores; decision D around a discard; finding 22 |

- **Host:** 16 pass and 8 fail: findings 15, 16 (three tests), 19, 21 and 22 (two tests).
- **Simulators:** the same 24 tests run (none is an exit test); see "Gate".
- **Property tests:** two on `PropertySeed.all`; two aggregates on its first 100 seeds.

## Gate

**Gate (2026-09-29):**
- `scripts/check.sh --fast` (host): 672 tests in 111 suites; 664 pass and 8 fail. The 8 are this round's
  regression tests for findings 15, 16 (three), 19, 21 and 22 (two). Format and lint pass. Log: scratchpad
  `f04-g2r3-fast.log`.
- Full `scripts/check.sh` through `sim-lock.py` (log: scratchpad `f04-g2r3-check.log`; the lock was acquired
  after 285 s):
  - Format passes (0 of 207 files), lint `--strict` passes, and the package graph matches.
  - iOS `PR` plan: 677 tests; 668 pass, **8 fail**, 1 skipped (`ReplayPerformanceTests`, `.slow`). The 8 are
    this round's. `check.sh` stops here (exit 65).
- watchOS `PR-Watch` plan: I ran it on its own, with check.sh step 4's exact command, under the lock (log:
  `f04-g2r3-watch.log`). 668 tests; 659 pass, **8 fail** (the same 8), 1 skipped.
- No pre-existing test fails on any lane.

**Nightly settings on the host** (`LEDGER_PROPERTY_SEED_COUNT=3000`):
- `literalHost_convergesAndRebuildsNeverBuzz`, `matchesReduce_onIntentLogs`, the implementer's
  `matchesReduce_onEveryStep` and `extremeValues_neverTrap_andStateEqualsItself`, and round 2's
  `hlc_convergesAndKeepsEveryAction` all pass at 3,000 seeds (log: scratchpad `f04-g2r3-3000.log`).
- Across those 3,000 literal-host sessions: 118,422 envelopes, 0 departures from replay, 0 haptics in a rebuild
  or relaunch, and 17,980 remote haptics on the in-order path. 190 sessions end finished and 171 discarded.

## Close-out of findings 9–14

| # | Status | Evidence |
|---|---|---|
| 9 | **Resolved**, with residuals filed as finding 16 | The three retargeted `RestBoundAdversarialTests` and both exit twins pass. A JSON `doneAt` of 1e21, a 1e21 snapshot rest and a NaN `endsAt` are ignored, and none reaches the ring. The same decoded dates handed to `RestTimer` directly do not trap. `ExtremeValuePropertyTests` passes at 3,000 seeds. Residuals: a snapshot date the predicate never checks still breaks `==` (16a), and a well-formed rest can still show 23 h left (16c). |
| 10 | **Resolved**, with a residual filed as finding 22 | `EventStoreMutationAdversarialTests`: the contract suite kills all 11 mutants and passes `InMemoryEventStore`. The two replaced mutants are the faithful analogues on the one remaining list. Residual: two more plausible stores pass every clause (22). |
| 11 | **Resolved by decision** (D) | One list, `uncompactedWorkoutIDs()`, classified by `replay`; a log that replays to `nil` is never compacted. The three former "(documents)" tests now assert this contract, and they pass. The contiguous-seq question went to F17. The orphan logs left after a compaction or a discard are noted under "Out of scope". |
| 12 | **Resolved by decision** (E) | ADR-004 "Recovery on launch". `hlcAfterRelaunch_mustBeRecoveredFromTheLog` passes, with the forgetful host kept as its control. `hlc_convergesAndKeepsEveryAction` passes at 3,000 seeds. `LiteralHost` recovers the clock from every uncompacted log. |
| 13 | **Resolved by decision** (F and the correction) | The loop is written into ADR-004, `reduce`'s doc and `append`'s doc, and `effects(from:to:)` exists. `LiteralHost`, following the ADR's text, leaves replay 0 times in 3,000 sessions. Residuals: what "already applied" means (17), the reconnect burst on the in-order path (18), and docs and tests still stating the rule the correction replaced (19). |
| 14 | **Resolved by decision** (B) | `restExtended(amount:extendsShownRest:tappedAt:)`. `hlcDraggedStamp_turnsAnExtendIntoARestart` passes with the lifter's outcome on both devices. `dragStamps_judgeRunningRestsOver` counts dragged stamps (more than 0) and taps that did otherwise than the lifter saw (0). The races hold (see "Attacked and held"). Residual: finding 20. |

## Audit of the tests fix round 2 edited

Every file `git show ab8faa1 -- LedgerKit/Tests` lists, plus the `ModelOracle` in `LedgerTestSupport`. Two
assertions are rejected, both for the same reason (finding 19). Everything else is accepted.

| Test (edit) | Verdict | Reason |
|---|---|---|
| `BoundsAdversarialTests`, `StartedTerminalAdversarialTests`, `GarbagePropertyAdversarialTests`, `CodableOrderingAdversarialTests` (event shape; garbage draws a random flag) | Accept | Decision B; the assertions are unchanged |
| `EffectsAdversarialTests` (`restExtended` case and `duplicateRestExtended_extendsOnce`, shown rest) | Accept | Decision B; the effects expected are unchanged |
| `EngineAdversarialSupport.extend`, `EngineAdversarialGenerators.plus30`, `RestAdversarialTests.extend`: shown iff `remaining > 0` at the tap, on the tapping device's clock | Accept | Exactly the rule the case's doc gives the UI (decision B). With one clock the outcomes are identical |
| `RestAdversarialTests.concurrentExtends_bothCount` (both shown) | Accept | Both taps land before the rest's end; the assertion is unchanged |
| `EngineTrapAdversarialTests.hugeDurations_doNotTrap` (amounts through `extend(on:)`) | Accept, with a note | Every huge amount is now malformed, so this round-1 exit test no longer reaches the saturation path. `longestRest_saturatesAHostileStateRest` covers that path |
| `RestBoundAdversarialTests.taps`, `bound_edges`, `zeroAndNegativeExtensions` | Accept | Decision A rejects lengths outside `0 ... longestRest`, where round 1 clamped. The kept rows are unchanged |
| `RestBoundAdversarialTests`: the three finding-9 tests retargeted to "…_isIgnored" | Accept | The question ("can this date reach the ring or break `==`?") stands, and the NaN test still asserts `replay == replay` |
| The two finding-9 exit twins, which now also call `remaining` and `fraction` directly | Accept | A strengthening: without the direct call they would pass vacuously |
| `EventStoreAdversarialTests`: lifecycle tests, `LaunchStep`, the three finding-11 tests | Accept, with a note | Decision D. `compactedThenPeerResend_isListed_andKeptUntilHealed` heals only because its comment has the watch relay the phone's own `started` (line 186). ADR-004 rule 4 resends a device's own envelopes only, and no brief specifies a relay (see "Out of scope") |
| `EventStoreContractProbes` deleted; `EventStoreMutationAdversarialTests` runs the contract suite; two mutants replaced and one added | Accept | Decision C. The replaced mutants mutated lists that no longer exist; `listsOnlyStartedLogs` and `unlistsEndedLogs` are their analogues on the one list. All 11 are killed |
| `MaterializeAdversarialTests.rematerialization_convergesInEveryArrivalOrder` | Accept | Decision D. The count assertion is unchanged, and it now also requires a finished replay |
| `HostContractAdversarialTests`: `hlcAfterRelaunch…`, `arrivalOrderReduce…`, `rebuildThenReduceInOneBatch…` | Accept | Decisions E and F. Each asserts the rule, and keeps the wrong reading as a control |
| `HostContractAdversarialTests.hlcDraggedStamp_turnsAnExtendIntoARestart` | Accept | Decision B: the lifter's outcome on both devices, and the stamp still lands after the rest's end |
| `HLCConvergenceAdversarialTests.dragStamps_judgeRunningRestsOver`, and the controls' display names | Accept | Decision B; the hazard is still counted, so the test has teeth |
| `HLCConvergenceAdversarialTests.hlc_convergesAndKeepsEveryAction`: notification, materialisation and dropped-log assertions | Accept | Decision F |
| `hlc_convergesAndKeepsEveryAction`: `remoteHaptics == 0` | **Reject** | The orchestrator's correction: a remote envelope reduced in order plays its haptic (F17 criterion 9). Finding 19 |
| `HLCHostAdversarialSupport.SimHost`: recovery on relaunch | Accept | Decision E |
| `SimHost`: `effects(from:to:)` for every received envelope | **Reject** | The same correction. On the in-order path the host runs `reduce`'s effects less persist and transmit. Finding 19 |
| `HLCScenarioAdversarialSupport` ("+30s" metric against the lifter's expectation; dragged stamps counted) | Accept | Decision B |
| `ConvergenceTests`, `EffectTests`, `ReduceTerminalTests.lateEvents`, `EngineTesting.extend`, `RandomWorkout` (random flag) | Accept | The event shape only; `RandomWorkout` now covers both branches of the flag |
| `ReduceRestTests`: criterion 5 with both flags; `extend_afterRestIsOver…`; `extend_followsTheLiftersIntent_notTheClock` replacing `extend_atExactEnd…` | Accept | Decision B: the engine no longer judges "at the exact end" |
| `ReduceRestTests.longestRest_holdsGrownRests`, `longestRest_saturatesAHostileStateRest` | Accept | Decision A. The hostile inputs moved to `EnvelopeWellFormedTests`; the saturation still guards `reduce`'s input |
| `ReduceTerminalTests.summary_ofCorruptEndedAt_saturatesElapsed` | Accept | The finish is ignored, and the saturation is asserted on a state that holds the date |
| New `EffectsFromToTests`, except the next row | Accept, with a note | `matchesReduce_onEveryStep` is sound, but `RandomWorkout`'s snapshots never carry a rest, so it misses finding 21 |
| `EffectsFromToTests.rebuildEffects_materializeInEveryArrivalOrder`: `host.remoteHaptics == 0` through `SimHost` | **Reject** (that assertion only) | In arrival orders where a remote set log sorts after everything applied, the corrected loop plays its haptic. The materialisation and notification assertions are accepted |
| New `EnvelopeWellFormedTests` | Accept, with a note | One clause per test, at both edges. The predicate's list of dates misses `lastPerformance.date` (16a) |
| New `ExtremeValuePropertyTests` | Accept, with a note | Its `replay(log) == replay(log)` cannot see a NaN nested in `exercises`: both states share the decoded array's storage, and `Array ==` returns early on identical storage (16a) |
| `InMemoryEventStore.uncompactedWorkoutIDs`; `WorkoutEventStoreContractTests` rewritten as nine clauses | Accept, with a note | Decisions C and D. Its fixtures sit on whole and half seconds, so it cannot see a lossy store (finding 22) |
| New `RestTimerTests.remainingAndFraction_saturate` | Accept | A.2 |
| `ModelOracle`: `accepts`, and "+30s" by intent (`LedgerTestSupport`) | Accept | It is written independently and never calls the engine. Its date list mirrors the engine's, so it shares 16a |

## New findings

| Class | Count | Findings |
|---|---|---|
| bug | 1 | 15 |
| minor bug | 4 | 16, 19, 21, 22 |
| spec question | 3 | 17, 18, 20 |

### 15. bug — The 24 h payload window drops a "Still lifting?" Finish made more than a day after the last set; the workout stays live

**Repro** (`Round3WellFormedAdversarialTests.stillLifting_finishOpenedDaysLater_isKept`):
```swift
replay([ start,
         setLogged(0, 0, doneAt: 3600)          @ 3600,
         finished(endedAt: 3600)                @ 3600 + 30 h ])   // the app is opened 30 h later
// expected: .finished, endedAt 3600, elapsed 1 h.   actual: .live, endedAt nil.
// Opened 20 h later (the control), it finishes.
```

**Expected:** F23 criterion 6 says: "Given a live workout with `lastActivityAt` older than 4 h, when the app
opens, then a sheet offers Finish / Discard / Keep going; Finish uses the last activity time as `endedAt`."
Decision #8 prompts "on next open", which can be days later: a workout left open from Saturday and opened on
Monday. `payloadTimeWindow`'s own doc names this case as what the generous window is for
(`EventEnvelope.swift:61`).

**Actual:**
- `endedAt` lies 30 h before the stamp, so the envelope is malformed.
- On the device that creates it, `reduce` returns `(state, [])`: no `.persist`, no `.transmit` and no error. The
  Finish does nothing, and the prompt comes back on every open.
- Discard, at the current time, still works. "Keep going" and a later Finish record a workout of several days,
  the "9-hour workouts" decision #8 exists to prevent.
- No host can make this finish well-formed: the hybrid logical clock never stamps in the past.

**Why it is F04's:** the predicate is F04's. The hand-off (`F17-live-sync.md:160–162`) tells F10 not to backdate
beyond 24 h. But F10 excludes the prompt (`F10-active-workout.md:24`), and F23, which owns it, requires the
opposite.

**Fix direction:** the window exists to stop traps and NaN (ADR-004, "Malformed envelopes"). `endedAt` feeds only
`elapsed`, which saturates, so a finite `endedAt` needs no lower bound, or a far wider one. The alternative is an
orchestrator decision to amend F23 criterion 6, which then stores a wrong duration.

### 16. minor bug — The predicate misses a date it should check, and checks one it should not

All three need input no real device produces.

**a. A snapshot's `lastPerformance.date` is never checked**
(`snapshotLastPerformanceNaN_breaksEquality`):
- With a NaN date, carried by a binary plist, the `started` is well-formed.
- Two decodes of the same bytes replay to unequal states.
- A re-sent copy makes `InMemoryEventStore.append` throw `conflictingEnvelope`, and the batch is all or nothing.
- A single decoded log does not show it: `replay(log) == replay(log)` passes, because both states share the
  snapshot's array storage and `Array ==` returns early on identical storage. `ExtremeValuePropertyTests` has the
  same blind spot for any date nested in `exercises`.
- JSON cannot carry NaN. F17's wire guard (hand-off item 5) covers it only if it rejects every non-finite date in
  a frame.

**b. A `setAdded` is dropped over a date `reduce` discards** (`setAdded_ignoredDoneAt_dropsTheAdd`). `reduce` adds
the row undone and ignores the set's `doneAt`. Yet a `doneAt` more than a day from the stamp drops the whole add.

**c. A well-formed rest can show 23 h left** (`eventRests_endWithinLongestRestOfTheirStamp`):
- `restStarted(endsAt: stamp + 23 h, total: 90 s)` and `setLogged(doneAt: stamp + 23 h)` are both well-formed.
- They give rests showing 23 h left against totals of 90 s and 150 s.
- A `started` snapshot's rest must end within `longestRest` of its start ("a rest the engine could hold"), but the
  event clauses have no such bound.
- Round 1 clamped `endsAt` to `longestRest` after the rest's start. Round 2 removed that clamp because "every rest
  length is now validated", but only `total` is.

**Fix direction:**
- check every date a snapshot carries for finiteness;
- skip or clear `set.doneAt` in `setAdded`;
- bound a rest's end by the stamp plus `longestRest`. A device's payload time never runs ahead of its own
  stamp, so the window can be asymmetric.

### 17. spec question — "The newest envelope already applied": the loop is right under one reading only

ADR-004 (line 149), `reduce`'s doc (`WorkoutEngine.swift:26`) and F17's hand-off (line 133) all say the same:
reduce when everything newly stored "sorts after the newest envelope already applied", else rebuild. That phrase
has two readings.

**A. Every envelope handed to `reduce` or `replay`, ignored or not.** This is the newest envelope stored before
this append. `LiteralHost` under this reading leaves replay 0 times in 3,000 sessions.

**B. Only envelopes `reduce` accepted** (`appliedMeaning_decidesALostFirstMessage`):
1. The watch starts a workout (decision #16).
2. The phone gets the watch's seq 2, a set log, before seq 1, the `started`: a lost message, then the resend.
3. Seq 2 is ignored on `nil` and not counted as applied.
4. The `started` then sorts after everything applied, so the phone reduces it, and never applies seq 2.
5. Every later envelope also sorts after, so the phone shows set 1 undone until a relaunch. The watch shows it
   done.

Under reading B, the 3,000 random sessions leave replay 1,801 times.

**Raw clocks** (`rawStamps_literalLoopLeavesReplay`):
- ADR-004 says raw stamps "still converge, but on stamp order" (line 116), and that holds for `replay`.
- A literal host under reading A still leaves replay: a third device hears a peer's early set log (stamp 91 s)
  before the `started` (100 s), then reduces the `started` on the in-order path.
- `Replica` and `SimHost` take the reduce path only when the state is not `nil`, which the ADR does not say, so
  they rebuild instead.

**Question:** should the loop say "every newly stored envelope sorts after the newest envelope stored before
this append, **and** the state is not `nil`"? Those are the two conditions the test hosts already use.

### 18. spec question — The in-order path buzzes once per envelope of a reconnect batch

ADR-004 (lines 158–159) says a rebuild plays no haptic, "so a reconnect that applies many envelopes at once does
not buzz for each". The doc on `effects(from:to:)` (`WorkoutEngine+Replay.swift:29–30`) says "a reconnect that
delivers a dozen sets plays nothing". Both hold only when the reconnect rebuilds.

**Repro** (`reconnectBatch_inOrder_buzzesPerSet`):
- During a partition only the watch acts: it logs five sets.
- The phone's reconnect batch all sorts after what the phone applied, so the phone reduces it in order and, per
  the correction, plays `reduce`'s haptics: five buzzes.
- Had the phone tapped Skip during the partition, the same batch would rebuild and play nothing.
- In 3,000 random sessions the largest burst from one batch was 10.

Which device buzzes depends on which one acted during the partition, not on anything the lifter chose.

**Question:** should the in-order path play `reduce`'s haptics only for a batch of one envelope, or only for the
last set log of a batch? F17 criterion 9 covers a single remote set.

### 19. minor bug — The remote-haptics correction did not reach `reduce`'s and `Effect`'s docs, or the host model and its tests

The correction reached ADR-004, the doc on `effects(from:to:)` and F17's hand-off. It is missing from:
- `WorkoutEngine.swift:30–32`, which says the host "runs `effects(from:to:)` …, and only those, for what it
  received. It runs the effects below only for an envelope it created".
- `Effect.swift:15–16`, which says: "For envelopes it received, the host runs only
  `WorkoutEngine.effects(from:to:)`".
- `SimHost` (`HLCHostAdversarialSupport.swift:42–44, 70, 175–180`). It runs `effects(from:to:)` for a remote
  envelope it reduced in order, and counts any remote haptic as a failure.
- The tests built on `SimHost`: `hlc_convergesAndKeepsEveryAction` (`HLCConvergenceAdversarialTests.swift:34`)
  and `rebuildEffects_materializeInEveryArrivalOrder` (`EffectsFromToTests.swift:155`) assert
  `remoteHaptics == 0`.

So no test exercises the corrected in-order path, and both properties would fail a host that follows the
corrected ADR. F17's implementer reads `reduce`'s and `Effect`'s docs first.

**Repro** (`simHost_playsTheInOrderRemoteHaptic`): a remote set log that sorts after everything the host applied
plays one haptic on `LiteralHost`, and none on `SimHost`.

**Fix:**
- correct the two doc comments;
- make `SimHost` run `reduce`'s effects, less persist and transmit, on the in-order path;
- assert that a rebuild plays no haptic, rather than that no remote envelope does. `LiteralHost`'s property does
  this: over 3,000 sessions, 0 haptics in a rebuild and 17,980 on the in-order path.

### 20. spec question — "+30s" on a device that shows no rest replaces the peer's longer running rest

**Repro** (`unseenRest_plus30Shortens`):
1. The phone logs bench set 1 at 10 s. Its rest runs to 160 s.
2. The watch has not heard of the log yet, from latency or a partition, so it shows no rest.
3. The lifter taps +30s on the watch at 15 s: `extendsShownRest` is false, so a fresh 30 s rest starts at the tap.
4. That tap is stamped after the log, so it replaces the 150 s rest.
5. After a "+30s", the phone's ring drops from 145 s left to 30 s.

The devices converge in every arrival order.

**Question:** should a fresh "+30s" keep the later of the running rest's end and the tap plus the amount, so that
"+30s" never shortens a rest? Or is this accepted, on the reading that the watch meant "start a rest"?

### 21. minor bug — `reduce` never schedules a `started` snapshot's rest; the rebuild effects do

**Repro** (`startedWithRest_reduceSchedulesItToo`): a `started` whose snapshot holds a rest ending at 90 s, total
90 s, which is well-formed.
- `effects(from: nil, to: state)` includes `.scheduleRestNotification(90 s)`.
- `reduce(nil, started)` returns `[persist, transmit, updateLiveActivity]`.

A device that applies its own `started`, or a received one in order, never schedules the rest-over notification;
a device that rebuilds does.

This input is contrived: `SessionBuilder`'s snapshots carry no rest. `matchesReduce_onEveryStep` cannot see it,
because `RandomWorkout`'s snapshots carry none either.

**Fix:** either `step` returns the snapshot rest's schedule on a `started`, or `isWellFormed` rejects a snapshot
that has a rest.

### 22. minor bug — The contract suite passes a store that loses sub-second precision, and one that keeps a copy per re-append

**Repro** (`contract_catchesLossyStores`, with `LossyEventStore`):
- **`millisecondsJSON` passes all nine clauses.**
  - GRDB's default encoder for JSON columns writes dates as `.millisecondsSince1970`, and multiplying by 1,000
    then dividing does not round-trip a `Date`.
  - 508 of 1,000 sub-second stamps near the fixture read back different, as do 520 of 1,000 stamps spaced like
    HLC stamps (probe: scratchpad `r3probe`).
- **`keepsCopies`** (no unique index) passes all nine too, because the clauses compare what is stored as a `Set`.
  F05's own criterion 7 would catch this one.
- **`iso8601JSON`** (whole seconds; F17's brief sketches that codec) is caught, but only by the one half-second
  fixture, in `conflictOnStampOnly`.

Every other fixture sits on a whole or half second, which all three encodings round-trip exactly.

**Consequence** (`iso8601Store_losesAnUnlog`):
- A store that keeps whole seconds makes two causal envelopes from two devices within one second tie on
  reload, so they sort by device ID.
- The phone's un-log of the watch's set is then lost on replay: finding 6 again.
- With millisecond loss, a re-sent envelope differs from the stored copy. A store that compares the incoming copy
  with what it reads back then throws `conflictingEnvelope`, and rejects the whole batch.

**Fix:**
- add a clause: an envelope whose `wallClock` and payload dates are not whole milliseconds reads back `==`, and
  re-appending it changes nothing;
- compare stored logs as arrays, with a count check.

## Out of scope, noted

1. **Dropping a log at the terminal (F05 and F17).**
   - The phone discards and runs `.discardLog`. The partitioned watch's envelopes then land in an empty log, which
     replays to `nil`.
   - Decision D keeps that log and asks for a resend, for ever: under ADR-004 rule 4 the watch resends only its
     own envelopes, never the phone's `started` (`discardLogThenLatePeer_orphanIsKeptForever`).
   - The watch never hears of the discard from the phone either, because the phone has no log left to resend.
   - Compaction after materialisation has the same shape (round 1, "Open for F05 and F17").
   - F17 should drop or compact a log only after the peer has acknowledged the terminal, or keep a tombstone.
2. **F17's drift bound must stay well under `payloadTimeWindow`.**
   - With a peer 24 h or more ahead, the hybrid logical clock drags this device's stamps so far from its payload
     times that every timed action it creates is malformed.
   - `reduce` then returns `(state, [])`, so the tap is neither stored nor sent, and nothing reports it
     (`peerClockADayAhead_dragsStamps`: kept at 23 h, dropped at 24.5 h).
   - The host should check `isWellFormed` before it creates an envelope, and report a failure.
3. **Rest notifications in the past.** A late remote rest reaches the rebuild or in-order path with `endsAt`
   already past, and is scheduled anyway. F23 criterion 1 handles this on the phone ("fires immediately if already
   past"); the watch (F18) needs the same rule.
4. **F05's brief is stale.**
   - Criterion 8 still names `liveWorkoutIDs()`, which no longer exists.
   - Its `workout_event.wall_clock TEXT` column holds milliseconds at most, if F05 ever orders or rebuilds
     envelopes from it (finding 22).
5. **The hand-off's "Still lifting?" item names F10.** The prompt belongs to F23 (finding 15).

## Attacked and held

**The predicate (decision A):**
- These are well-formed and applied: a 3 h workout, a 45-minute rest before a set, a "+30s" after an hour's pause,
  and a finish 20 h after the last set (`realisticLongSessions_areWellFormed`).
- A peer 23 h ahead drags the stamps 23 h past the payload times, and the device's actions are kept.
- The window's edges are inclusive at a realistic fractional 2026 stamp: within the binade, adding and
  subtracting 86,400 s is exact. One millisecond beyond either edge is excluded.
- DST changes nothing, because dates are absolute. Leap seconds cannot appear in a `Date`.
- The verdict is plain IEEE arithmetic, so both devices reach the same one, given the lossless encoding the
  hand-off requires.

**Saturating arithmetic.** I grepped all of `LedgerDomain` for Duration, TimeInterval and Int conversions.
Nothing on an engine path can trap:
- `RestTimer.remaining`, `RestTimer.fraction` and `elapsed` saturate.
- `Duration / Duration`, `Date ± Double` and `abs` never trap.
- `saturatingSum` can overflow only upwards, and is pinned there.
- `NumberText.fixed` is only ever called with one fraction digit, so its `Int(…)` fits.
- `roundedToInt` goes through `NSDecimalNumber.intValue`, which does not trap.
- The UUID derivation uses wrapping operations.
- The fuzz passes at 3,000 seeds.

**"+30s" under races (decision B).** Each race gives the same state in every arrival order, and `Replica`, which
reduces or rebuilds, agrees with replay:
- both devices extend: both count, +60 s in all;
- a skip and an extend race: the later one wins. Skip first gives a fresh 30 s rest from the tap; extend first
  gives no rest;
- an extend lands after the rest was replaced: it grows the rest now running;
- decision #7: "+30s" on a rest shown as over starts a fresh 30 s rest at the tap.

**`effects(from:to:)` (decision F):**
- It equals `reduce`'s effects, less persist, transmit, haptics and no-op schedules. That holds on 3,000 seeded
  two-device intent logs with stale rows, both "+30s" flags, terminals and envelopes after the end.
- It never plays a haptic.
- A discard's order: `reduce` gives persist, transmit, `discardLog`, cancel, then redraw; a rebuild gives
  `discardLog`, cancel, then redraw; from `nil` it gives the same.
- It materialises on a rebuild from `nil` and on a finished state that changed. In every finished session of the
  literal-host property, the stored workout equals the final state.

**The literal host loop, under reading A:**
- 3,000 seeds and 118,422 envelopes, over 2–3 devices with ±30 s skew, clock steps, partitions, lost and resent
  messages, shuffles, copies and relaunches.
- It leaves replay 0 times after any delivery, and every device converges.
- The notification always equals the rest's end.
- The stored workout equals the final state in all 190 finished sessions, and the log is dropped in all 171
  discarded ones.
- A rebuild or relaunch plays no haptic, while 17,980 remote haptics play on the in-order path.

**The store:**
- The contract suite kills all 11 mutants.
- Classification by replay holds through the lifecycle:
  - a log with only an early envelope is kept;
  - a live log is resumed;
  - a finished log is materialised and compacted;
  - a discarded log is dropped and compacted;
  - a hole before the terminal is kept until the resend fills it.

---

**Verdict:** G2 cannot close because finding 15 (bug): the 24 h payload window silently drops a "Still lifting?" Finish opened more than a day after the last set (F23 criterion 6), so the workout stays live; the rest held, and findings 16–22 are minor or spec questions.

---

# Round 4 — close-out after the re-plan (07c6794)

A scoped close-out pass over `feat/F04-workout-engine` at `92313c0`: fix commit `07c6794`, plus a merge of `main`.
The contract is the re-plan that the orchestrator agreed with Pete on 2026-09-29:
- both devices stay fully live;
- validation rejects only non-finite dates and out-of-range rest lengths;
- received envelopes always rebuild by replay, and `effects(from:to:)` plays at most one set haptic, only while
  the workout is live;
- "+30s" never shortens a running rest;
- F04 is frozen.

The sources are ADR-004 as it now reads, the "Re-plan (2026-09-29)" section of `implementation-notes.md`, and
`git show 07c6794`. I opened no new design area. I read the product code only to aim the attacks, and edited
none.

**Bar for a finding (this round):** a bug counts only if it falls in the re-plan's scope and is a trap, a
divergence, a lost lifter action, or a wrong state on realistic input. Anything else goes under "Out of scope,
noted".

## What I wrote

14 new tests in 5 files under `LedgerKit/Tests/LedgerDomainTests/Engine/Adversarial/`. All pass. None is an
exit test, so every one of them also runs on both simulators.

| File | Tests | What it attacks |
|---|---|---|
| `Round4WellFormedAdversarialTests` | 4 | The narrowed predicate. It must catch ±∞ and NaN in all 13 date slots, and every rest-length edge. It must also keep legitimate late, long and backdated envelopes |
| `Round4ExtremeDateAdversarialTests` | 1 (6 cases) | 1e15 s, `distantFuture`, `distantPast` and ±`greatestFiniteMagnitude`, in every slot and all at once: no trap, and the state equals itself |
| `Round4EffectsRestAdversarialTests` | 5 (1 property) | The set haptic: exactly one per rebuild, with a check of its coverage. Its cases, and the launch. "+30s" in both modes against 50 kinds of prior rest |
| `Round4ReduceReplayAdversarialTests` | 2 (1 property) | Reduce against replay for a device's own HLC-stamped envelopes, with a raw-clock control. It uses its own driver, not `LiteralHost`, `SimHost` or `Replica` |
| `Round4StoreAdversarialTests` | 2 | The 14 mutants, and which clause kills the new ones. A store that keeps its stamps as seconds since 1970 (out of scope, for F05) |

## Gate

**Gate (2026-09-29):**
- `scripts/check.sh --fast` (host): OK. 689 tests in 116 suites pass (675 before, plus these 14). Format
  (0 of 253 files) and lint (`--strict`) are clean. Log: scratchpad `f04-r4-fast.log`.
- **Nightly seeds on the host** (`LEDGER_PROPERTY_SEED_COUNT=3000`): 38 tests pass. They are this round's
  tests plus the re-plan's host, HLC, effects and fuzz suites (`Round3Host…`, `HLCConvergence…`,
  `EffectsFromTo…`, `Round3Effects…`, `ExtremeValueProperty…`). Log: scratchpad `f04-r4-3000.log`.
- **Full `scripts/check.sh` through `sim-lock.py`, once:** **green** (`check.sh OK`) in 255 s. The lock was free. Log: scratchpad
  `f04-closeout-check.log`.

| Step | Result |
|---|---|
| 0–2: tools, format, lint (`--strict`), package graph | OK: 0 of 253 files need formatting, lint and the four lint-rule suites are clean, and the graph matches |
| 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed.** xcresult: 837 tests; 835 passed, **0 failed**, 2 skipped |
| 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed.** xcresult: 814 tests; 812 passed, **0 failed**, 2 skipped |
| 5: coverage gate | Not wired yet (F01) |

- The 14 Round 4 tests ran and passed on both simulators.
- The two skips on each platform are `ReplayPerformanceTests` (`.slow`, nightly only) and a font-rendering
  test from F06, which came in with the merge of `main`: "font(role, dynamicTypeSize:legibilityWeight:) draws
  what .ledgerFont draws in that environment".
- The totals are above fix round 3's 680 and 671 because of that merge (F06's tests) and this round's 14.

## Close-out of findings 15–22

| # | Status | Evidence |
|---|---|---|
| 15 | **Resolved** | These pass:<br>• `Round3WellFormed…stillLifting_finishOpenedDaysLater_isKept` (unchanged).<br>• `ReduceTerminalTests.stillLifting_finishOpenedLater_endsAtTheLastSet` (30 h and 30 days).<br>• `Round4WellFormed…stillLifting_thirtyDaysLate_onTwoHosts`: two HLC hosts; the Finish ends the workout at the last set on both, with elapsed 1 h, and the watch's rebuild materialises it without a buzz.<br>• `ownHLCEnvelope_reduceEqualsReplay`: 60 sessions end with a 30-day-late Finish (901 at 3,000 seeds), and every one ends finished |
| 16 | a **Resolved**; b **Resolved**; c **Resolved by decision** (2) | a: `snapshotLastPerformanceNaN_breaksEquality` passes. So does `Round4WellFormed…everyNonFiniteDate_isMalformed`, which covers the last exercise's `lastPerformance.date` and a drop row's `doneAt`.<br>b: `setAdded_ignoredDoneAt_dropsTheAdd` passes.<br>c: `eventRests_farFromTheirStamp_areAppliedAsGiven` (documents) passes, and the ring saturates |
| 17 | **Resolved by decision** (3) | There is one path per source, so "already applied" means nothing any more. `lostFirstMessage_staysOnReplay` and `rawStamps_oneLoopStaysOnReplay` pass |
| 18 | **Resolved by decision** (3, Pete's rule) | `reconnectBatch_buzzesOnce` passes: one buzz whether or not the phone acted. `Round4EffectsRest…setHaptic_exactlyOncePerRebuildWithANewlyDoneSet` passes |
| 19 | **Resolved** | I grepped the sources, ADR-004, F17 and F23 for the superseded rule ("never buzz", "remote change", "in order", "already applied", "per envelope"). Only the new wording remains. `remoteSetLog_buzzesOnEveryHostModel` passes on `LiteralHost` and `SimHost` |
| 20 | **Resolved by decision** (4) | These pass: `unseenRest_plus30KeepsTheLongerRest`, `ReduceRestTests.extend_unshown_neverShortensARunningRest` and `Round4EffectsRest…plus30_neverShortensARunningRest` (100 cases) |
| 21 | **Resolved** | `startedWithRest_reduceSchedulesItToo` passes unchanged. The `matchesReduce_*` properties pass at 3,000 seeds |
| 22 | **Resolved** | These pass: `EventStoreMutationAdversarialTests` (14 of 14 mutants killed, and the reference store passes), and `contract_catchesLossyStores` (3 of 3). `Round4Store…contract_killsItsFourteenMutants`: each of the three new mutants fails the new exact read-back clause. A lossy encoding outside the 14 is noted for F05 (below) |

## Audit of the tests 07c6794 edited, retargeted or removed

Every test file `git show 07c6794 -- LedgerKit` lists, plus `ModelOracle`. Nothing is rejected: every weakening
rests on a re-plan decision.

| Test (edit) | Verdict | Reason |
|---|---|---|
| `EnvelopeWellFormedTests.payloadWindow_isADay` (deleted) | Accept | Decision 2: there is no window |
| `…payloadDates_mustBeFinite`, `…startedSnapshot_isInternallyPossible` (retargeted) | Accept | Decision 2. They keep both edges (finite in, non-finite out), and gain `lastPerformance.date` (16a) |
| `…reduce_ignoresMalformed`, `…replay_dropsMalformed` (fixture now NaN or ∞) | Accept | 1e9 is finite now. The assertions are unchanged |
| `ReduceRestTests.extend_followsTheLiftersIntent_notTheClock` (the running rest ends at 30 s) | Accept | Decision 4 would keep a rest ending at 100 s. With 30 s the case still shows that "not shown" restarts although both clocks say a rest runs |
| `ReduceTerminalTests.summary_ofCorruptEndedAt_saturatesElapsed` (1e21 is kept) | Accept | Decision 2. Non-finite dates are still ignored |
| `EffectsFromToTests.remoteSetLog_buzzesAndSchedules`, `lateEnvelope_rematerializes`, `matchesReduce_onEveryStep` | Accept | Decision 3 and the live-only rule. The property still ties each step to `reduce` |
| `EffectsFromToTests.rebuildEffects_materializeInEveryArrivalOrder` (at most one per delivery, and at most 3 in all) | Accept | This is round 3's rejected `== 0`, corrected as I asked |
| `ExtremeValuePropertyTests` (a second decode; `lastPerformance` dates) | Accept | A strengthening. It closes 16a's `Array ==` blind spot |
| `WorkoutEventStoreContract.malformedIsStored` (fixture: a 2 h "+30s") | Accept | A `doneAt` of 1e12 is finite now, so it is well-formed |
| `Round3WellFormed…peerClockADayAhead_dragsStamps` (24.5 h is kept; a 30-day row is added) | Accept | Decision 2 |
| `Round3WellFormed…edges_atARealisticStamp` | Accept | Decision 2. The DST half is unchanged |
| `Round3WellFormed…snapshotLastPerformanceNaN_breaksEquality` (the store's conflict on the resend is now asserted) | Accept, with a note | NaN ≠ NaN, so no predicate can make a store accept the resend. The first two assertions now pin the fix. F17 item 5 guards the wire. Note: its display name, and 16b's, still describe the round-3 bug |
| `Round3WellFormed…eventRests_farFromTheirStamp_areAppliedAsGiven` (documents) | Accept | Decision 2 accepts 16c. The ring is asserted saturated |
| `Round3RestIntent…unseenRest_plus30KeepsTheLongerRest`, and the `rest` helper's message | Accept | Decision 4. It also pins that a tap near the rest's end still restarts |
| `Round3Effects…matchesReduce_onIntentLogs` (`rebuildShare` keeps the live set haptic; at most one) | Accept | Decision 3 and the live-only rule |
| `LiteralHost`, `Round3Scenario` (one path; no `applied`; the relaunch runs no effects) | Accept | Decision 3. The generator stream is unchanged |
| `literalHost_convergesAndBuzzesOncePerDelivery`, `remoteSetLogs_buzz`, `lostFirstMessage_staysOnReplay`, `rawStamps_oneLoopStaysOnReplay`, `reconnectBatch_buzzesOnce`, `remoteSetLog_buzzesOnEveryHostModel` | Accept | Decision 3. Each asserts the new rule. The reading-B control went with the path it described |
| `Round3Store…contract_catchesLossyStores` (read-back flipped to `!=`) | Accept | My round-3 `==` failed by construction: the store is lossy. The contract assertion, which is the finding, is unchanged and passes |
| `Round3Store…iso8601Store_losesAnUnlog` (documents; the suite rejects the store) | Accept | A lossy store can only be rejected, and the test now asserts that it is |
| `SimHost` (one path; `largestRemoteBurst`; the relaunch runs no effects) | Accept | Decision 3 and finding 19 |
| `HLCConvergence…hlc_convergesAndKeepsEveryAction` (`largestRemoteBurst <= 1`) | Accept | This is round 3's rejected `remoteHaptics == 0`, corrected |
| `HLCConvergence…rawClocks_loseActions` (the host's state becomes `replay(host.log)`) | Accept, with a note | Weaker. But raw stamps break the own-action path's precondition by design. My raw-clock driver shows it: 207 of 7,693 own actions leave replay at 200 seeds (`rawClocks_reduceLeavesReplay`) |
| `HostContract…hlcAfterRelaunch_mustBeRecoveredFromTheLog` (`forgotten.shown` is now false) | Accept | The recovered case is unchanged. The breach is still visible (`forgotten.done`) |
| `HostContract…arrivalOrderReduce_divergesFromReplay` (the control uses `Adv.state(after:)`), `rebuildThenReduceInOneBatch_appliesTwice` (the name only) | Accept | `StoringHost` now follows the loop, so it can no longer be the control |
| `Replica` (always rebuilds), with `ConvergenceProperty…incremental_matchesReplayAtEveryStep` (now also checks `reduce` when an envelope sorts last) | Accept | The added check keeps the reduce path under test |
| `StoringHost` (append, rebuild, `effects(from:to:)`), `EventStore…host_appliesEachNewEnvelopeOnce`, `TerminalOutcome…lateEnvelopeSortingBeforeFinish_isStoredByHost`, `…losingStarted_isStoredByHost`, `EffectsAdversarial…duplicateSetLogged_noSecondHaptic` (the name only) | Accept | Decision 3. The expected effects are the rebuild's, and each equals what I derive from the ADR |
| `RestBound…autoRest_absurdDoneAt_saturatesTheRing`, `…snapshotRest_absurdEndsAt_saturatesTheRing` | Accept | Decision 2 takes finding 9's second option, saturation. The NaN test and both exit twins are unchanged |
| `EventStoreMutationAdversarialTests` (three mutants added) | Accept | Decision 5 (22). Each dies on the new clause |
| `ModelOracle` (`accepts` has no window; `extendRest` keeps the later rest; `lastPerformance` dates) | Accept | The code is its own and never calls the engine. It agrees with the engine on every Round 4 input, the extreme dates included |

## New findings

None. Nothing I tried in the re-plan's scope traps, diverges, loses a lifter action, or reaches a wrong state
on realistic input.

## Out of scope, noted

1. **F05: a store that keeps `wallClock` as seconds since 1970 passes the contract.**
   - The new exact read-back clause has one stamp fixture, `10.493_827_3`, and it happens to survive
     `Date(timeIntervalSince1970: d.timeIntervalSince1970)`. About half of real sub-second stamps do not: they
     read back one ulp (about 0.1 µs) off.
   - GRDB offers this encoding as `databaseDateEncodingStrategy = .timeIntervalSince1970`, a natural choice for a
     `REAL` column that SQL can sort. `JSONEncoder`'s `.secondsSince1970` has the same loss.
   - Pinned by `Round4Store…since1970Stamps_passTheContract_butAlterHalfOfRealStamps` (documents):
     - such a store passes all 10 clauses, and alters 496 of 1,000 stamps spaced 0.731 s apart;
     - when it compares a duplicate delivery with what it reads back, it throws `conflictingEnvelope`, and the
       new envelope in that batch is not stored.
   - That heals on the next `seq > N` resend, so this is not a round-4 bug.
   - F05 should store `timeIntervalSinceReferenceDate`, or use the default codec. A second stamp fixture, such
     as `10.493_826_8`, would let the clause catch it.
2. **F17: a hybrid logical clock at an absurd magnitude cannot advance.**
   - Above 2^44 s (about 1.76e13 s, some 560,000 years out), `+ 1 ms` rounds away, so a new stamp cannot sort
     after the stored one it follows.
   - Only a corrupt stamp gets there. F17's drift bound, and the recovery step's skip, must keep such stamps out
     of `newest`. The engine itself stays well-behaved there (see "Attacked and held").
3. **UX: a rebuild from nothing buzzes once.** An example is the phone first hearing of a watch-started workout
   that already has done sets. This is intended (`setHaptic_oncePerRebuild`, "also from `nil`"), and is listed
   only so product can confirm it.

## Attacked and held

**The narrowed `isWellFormed` (decision 2):**
- **Non-finite dates.** ±∞ and NaN are malformed in all 13 slots:
  - `wallClock`, `setLogged.doneAt`, and the `doneAt` of a `setAdded` set;
  - `restStarted.endsAt`, and `restExtended.tappedAt` in both modes;
  - `finished` and `discarded` `endedAt`;
  - the snapshot's `startedAt`, `endedAt` and `rest.endsAt`;
  - the last exercise's drop row `doneAt`, and its `lastPerformance.date`.

  For each, `reduce` returns `(state, [])`, `replay` ignores the envelope, and the oracle agrees.
- **Rest lengths.** These are well-formed: 0, 30 s and exactly one hour. These are malformed: −1 attosecond,
  one hour plus one attosecond, and both `Duration` extremes. That holds in `restStarted`, in `restExtended`
  (both modes) and in a snapshot's rest, and the oracle agrees.
- **Legitimate envelopes are kept:**
  - a 30-day-late "Still lifting?" Finish, through two HLC hosts;
  - a 4 h two-device workout with a 7 s skew: 18 of 18 sets done, several "+30s" taps, and an elapsed time of
    exactly 14,400 s. The sorted reduce fold and the reversed oracle agree;
  - a watch finish whose `endedAt` is 10 s before `startedAt`: finished, with elapsed 0;
  - a discard stamped 30 days after its `endedAt`.

**Extreme finite dates, with no windows left.** I tried 1e15 s, −1e15 s, `distantFuture`, `distantPast` and
±`greatestFiniteMagnitude`, first in each of the 13 slots and then all in one log. That log holds a snapshot
carrying the date everywhere, then every dated event, and a "+30s" of one hour. In every case:
- The envelope is well-formed and applied, and nothing traps.
- The state equals itself across two JSON decodes and two binary-plist decodes.
- The sorted reduce fold and `ModelOracle` agree with it.
- Every value a host reads can be computed:
  - `elapsed`, `remaining` (never negative), and `fraction` (in 0…1), at the extreme date and at ordinary ones;
  - `summary`;
  - `effects(from: nil, to:)`.

**`effects(from:to:)` and the set haptic (decision 3 and the live-only rule):**
- **The property.** Seeded two-device logs are delivered to one device in shuffled batches of 1–12. Each
  rebuild plays exactly one `.haptic(.setLogged)` when the new state is live and holds a set ID that is done
  but was not done before. Otherwise it plays none, and it never plays another haptic.
  - At 200 seeds: 1,544 rebuilds and 201 buzzes. At 3,000: 22,995 and 2,884.
  - The coverage is checked: 117 live rebuilds brought at least 2 sets at once, 202 ended with new sets, and
    53 lost done sets (1,624, 2,933 and 778 at 3,000 seeds).
- **By case:**
  - five remote sets: 1;
  - a log together with an un-log: 1;
  - an un-log alone: 0;
  - a re-log after an un-log: 1, because the set is newly done;
  - a finish or discard that brings sets: 0, from live and from `nil`;
  - no change: no effects.
- **The launch.** `effects(from: nil, to:)` of a resumed log with a done set would buzz, so the launch step must
  not run it. ADR-004 "Launch", the doc on `effects(from:to:)` and F17 item 2 all say so. Both host models'
  relaunches play nothing.

**"+30s" never shortens a running rest (decision 4), in both modes.** I tapped at 1,000 s against 50 prior rests:
none; over 0 s, 1 ms, 45 s or an hour ago; and running with 1 ms to 3,630 s left, at totals of 30 s, 150 s and
one hour. That is 100 cases. In every case `reduce` equals replay, and persist and transmit come first.
- **Not shown:** the rest ends at the later of the running end and the tap plus 30 s. It never ends earlier.
- **Shown, on a running rest:** it never ends earlier, with one exception. The one-hour cap on the end (the tap
  plus `longestRest`) binds only when more than an hour is left: 6 cases, at 3,600.001 s and 3,630 s left. A
  rest total is capped at an hour, so that needs a rest already at the cap, and a tap on a device whose clock
  runs behind the device that set it. It is not realistic input, and it is unchanged by the re-plan.
- **Shown, on an expired rest:** it extends the state's rest as given (decision B, unchanged). A device shows a
  rest running only when that rest runs at its tap, so this needs a peer to have replaced the rest.

**Reduce against replay for own HLC-stamped envelopes.** My own driver runs 2–3 devices with:
- ±30 s skew, and clock steps back;
- relaunches that recover the clock;
- partial and shuffled deliveries of each device's own envelopes;
- sometimes a Finish 30 days later.

Every own action's stamp sorts after everything its device stored. `reduce` on the replayed state equals
`replay` of the log with the new envelope:

| Seeds | Own actions | Early stamps | Mismatches |
|---|---|---|---|
| 200 | 7,693 | 0 | 0 |
| 3,000 | 114,952 | 0 | 0 |

The control, with raw device clocks over 200 seeds, gives 776 early stamps and 207 mismatches. So the property
has teeth, and the HLC is what makes it hold.

**The store contract (decision 5, finding 22):**
- The suite kills all 14 mutants, and the reference store passes all 10 clauses.
- `keepsCopies`, `stampToMilliseconds` and `payloadToMilliseconds` each fail the new exact read-back clause.

---

**Verdict:** G2 can close. Findings 15–22 are resolved or resolved by decision. Every edit 07c6794 made to the
tests is accepted. This round found no new bug in the re-plan's scope, and the full gate is green on both simulators.
