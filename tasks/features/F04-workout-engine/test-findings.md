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
