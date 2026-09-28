# F04 — implementation notes

Branch `feat/F04-workout-engine` (from `main` at `8404d02`). Implementer pass: 2026-09-28.

## What was built

- **`LedgerDomain/Engine/`**
  - `WorkoutEvent`: the brief's 13 events.
  - `EventEnvelope` and `EnvelopeKey`.
  - `Effect` and `Haptic`.
  - `EngineError`.
  - `WorkoutEngine`:
    - `reduce(_:_:)`, plus `step(_:_:)`, its in-place transition;
    - `summary(_:prs:)`;
    - `replay(_:)`, plus `foldOrder(_:)`, its fold order;
    - the rule edits, a private extension on `WorkoutState` in `WorkoutEngine+Reduce.swift`.
- **`LedgerDomain/Protocols/WorkoutEventStore.swift`**: the brief's five-method protocol. It replaces F02's reserved empty protocol.
- **`LedgerTestSupport/Engine/`** (shared with F17):
  - `EventBuilders`: devices, the §6.3 seed session, the criterion 2 superset, `session(_:)` from `ExerciseSpec`s, `setID`, `envelope`, and `log(from:device:)`.
  - `ModelOracle`: the independent oracle.
- **`LedgerDomainTests/Engine/`**: 15 suites, plus `Support/EngineTesting.swift` (shorthands and the `.slow` tag) and `Support/RandomWorkout.swift` (the seeded generator of sessions and two-device logs).

`reduce` and `replay` never read a clock, and there is no `Date()` anywhere in `Engine/`.

## Rules → tests

Every rule has at least one named test. File name = suite name, under `LedgerKit/Tests/LedgerDomainTests/Engine/`.

| Rule | Tests |
|---|---|
| 1 `started` | `ReduceStartedTests`: `started_onNil_yieldsSnapshot`, `started_onExistingState_isIgnored`, `eventBeforeStarted_isIgnored`, `started_invalidSnapshot_isIgnored`, `envelope_forAnotherWorkout_isIgnored`, `replay_buffersEventsSortedBeforeStarted`, `replay_withoutStarted_isNil` |
| 2 terminal | `ReduceTerminalTests`: `criterion6_afterFinished_everythingIsIgnored` (13 cases, one per event kind), `afterDiscarded_everythingIsIgnored` (13), `firstTerminalWins` |
| 3 `setLogged` | `ReduceSetLoggedTests`: `criterion1_firstSet_startsRestAndAdvances`, `criterion2_superset_restsAfterRound_roundRobin`, `criterion3_lastSetOfExercise_movesToNextExercise`, `cursor_wrapsToEarliestUndoneRow`, `cursor_staysAfterLastRowOfWorkout`, `autoRestOff_startsNoRest`, `relog_updatesValuesOnly`, `negativeWeight_isClampedToZero`, `unknownSet_changesNothing` (3), `supersetDropRound_restsAfterLastDropRow` |
| 4 `setUnlogged` | `ReduceUnlogTests`: `criterion4_unlog_keepsCursorAndRest`, `relogAfterUnlog_isTransitionAgain`, `unlog_unknownOrUndone_changesNothing` |
| 5 `setTargetChanged` | `ReduceTargetLWWTests`: `criterion11_laterWallClockWins_inAnyArrivalOrder`, `lastWriterWins_perField`, `targetChange_touchesOnlyTheSet`, `clampAndNoOps` |
| 6 `setAdded` | `ReduceAddRepeatSwapTests`: `setAdded_appendsUndoneAddedRow`, `setAdded_isIdempotentBySetID` |
| 7 `allSetsRepeated` | `ReduceAddRepeatSwapTests.allSetsRepeated_writesEveryRow` |
| 8 `exerciseSwapped` | `ReduceAddRepeatSwapTests`: `exerciseSwapped_replacesIdentityOnly`, `criterion12_programUpdate_survivesFinish`, `programUpdates_latestPerSlot` |
| 9 rest | `ReduceRestTests`: `criterion5_extendWithNoRest_startsRestFromNow`, `extend_runningRest_growsEndsAtAndTotal`, `extendTwice_addsBoth`, `extend_afterRestIsOver_startsFreshRest`, `extend_atExactEnd_startsFreshRest`, `restStarted_isAbsolute`, `skip_clearsRest` |
| 10 `finished` / `discarded` | `ReduceTerminalTests`: `finished_endsAndMaterializes`, `discarded_endsAndDropsLog`, `summary_ofFinishedWorkout`, `summary_ofLiveWorkout_hasZeroElapsed`, `summary_usesSnapshottedUnits`; `EffectTests.effects_finished` |
| 11 `exerciseSelected` | `ReduceSelectTests`: `select_undoneRow_movesCursor`, `select_doneRow_isIgnored`, `select_missingRow_isIgnored` (4) |
| 12 convergence | `ReplayTests`: `criterion7_shuffled100Times_sameState`, `criterion8_duplicatedLog_equalsDedupedReplay`, `replay_equalsSequentialReduce` (property), `resume_midWorkout_restoresState`, `foldOrder_dedupesAndLeadsWithStarted`. `ConvergenceTests`: `criterion9_partition_thenHeal_converges`, `randomPartition_converges` (property), `wallClockTie_breaksByDeviceThenSeq`. `EnvelopeOrderingTests`: `order_wallClockFirst`, `order_tieBreaksOnDevice`, `order_tieBreaksOnSeq`, `key_isDeviceAndSeq`, `order_isTotal_andMatchesUUIDStringOrder` (property) |

Also:

- **`EffectTests`**:
  - `effects_exactListPerEvent`: 16 rows, the exact effect list per event, including the no-op variants;
  - `effects_finished`;
  - `effects_ignoredEnvelopes_areEmpty`.
- **`EventCodableTests`**:
  - every event kind round-trips through JSON inside an envelope;
  - the new snapshot fields round-trip;
  - `EngineError` equality.
- **`ModelOracleTests.oracle_reproducesCriteria1And2`** shows that the oracle is not vacuous.

## Acceptance criteria → tests

| # | Test |
|---|---|
| 1 | `ReduceSetLoggedTests.criterion1_firstSet_startsRestAndAdvances` |
| 2 | `ReduceSetLoggedTests.criterion2_superset_restsAfterRound_roundRobin` |
| 3 | `ReduceSetLoggedTests.criterion3_lastSetOfExercise_movesToNextExercise` |
| 4 | `ReduceUnlogTests.criterion4_unlog_keepsCursorAndRest` |
| 5 | `ReduceRestTests.criterion5_extendWithNoRest_startsRestFromNow` |
| 6 | `ReduceTerminalTests.criterion6_afterFinished_everythingIsIgnored` (all 13 event kinds) |
| 7 | `ReplayTests.criterion7_shuffled100Times_sameState` (a 61-envelope two-device log, shuffled 100 times) |
| 8 | `ReplayTests.criterion8_duplicatedLog_equalsDedupedReplay` |
| 9 | `ConvergenceTests.criterion9_partition_thenHeal_converges`, plus the property `randomPartition_converges` (every seed, arrival shuffled, with repeats, also checked against `ModelOracle.replay`) |
| 10 | `ModelOracleTests.reduce_matchesOracle_atEveryStep`. Each seed runs 5 sequences of 61 envelopes, compared at every step, so the PR lane's 200 seeds cover **1,000 sequences** and nightly (2,000 seeds) covers 10,000. Also `replay_matchesOracleReplay`. |
| 11 | `ReduceTargetLWWTests.criterion11_laterWallClockWins_inAnyArrivalOrder` |
| 12 | `ReduceAddRepeatSwapTests.criterion12_programUpdate_survivesFinish` |

**The oracle catches real bugs.** I checked this by mutating the reducer by hand, then restoring it. `ModelOracleTests` killed all four mutants:

| Mutant | Issues recorded |
|---|---|
| Dropped the "earliest undone earlier" cursor branch | 215 |
| Rest from the exercise's own rest instead of the group rest | 127 |
| "+30s" extends a rest that is already over | 154 |
| `setAdded` idempotent within the exercise only | 170 |

## Decisions

1. **Time comes from the envelope, not a `now` parameter.**
   - An event that carries no time happens at its envelope's `wallClock`, the originating device's clock when the user acted. That is F17's "`wallClock` from the intent's date".
   - `restExtended` is the only event that needs it. Deviation 1 explains why.
2. **`replay` buffers events that sort before `started` (rule 1).**
   - `foldOrder` sorts the log, dedupes by key (keeping the first sorted copy), then moves the first `started` to the front.
   - An envelope from a peer whose clock runs slightly behind is therefore applied after the start, not dropped.
   - `replay` is exactly `step` folded over `foldOrder`, so `replay(log) == fold(reduce)` over that order. The property test `replay_equalsSequentialReduce` checks this.
3. **Effects contract:**
   - An ignored envelope (rules 1 and 2, another workout) yields `[]`.
   - An accepted one yields `.persist(e)`, `.transmit(e)`, the event's own effects, then `.updateLiveActivity` iff the state changed.
   - `persist` and `transmit` are emitted even when the event is a no-op here, such as selecting a done row. A peer that orders the log differently may apply it, so every accepted envelope belongs in every log.
   - `transmit` is emitted for remote envelopes too, because the reducer does not know which device is local. F17's brief already says the actor never re-transmits remote envelopes.
   - Own effects per event:
     - `setLogged`: `.haptic(.setLogged)`, plus `.scheduleRestNotification` when it starts a rest.
     - `restStarted` and `restExtended`: `.scheduleRestNotification(endsAt:)`, a replace.
     - `restSkipped`: `.cancelRestNotification`.
     - `finished`: `.materialize(summary with prs: [])`, `.haptic(.workoutFinished)`, `.cancelRestNotification`.
     - `discarded`: `.discardLog`, `.cancelRestNotification`.
     - Every other event has no own effects.
   - `EffectTests` pins every list.
   - The engine never emits `.haptic(.restOver)` or `.haptic(.personalRecord)`. Rest reaching zero is not an event (F18 plays that haptic), and the engine has no history for PRs (F05 detects them).
4. **The `started` snapshot must be live and have the envelope's `workoutID`.** Otherwise it is ignored like any pre-start event.
5. **A set's weight is never below zero.** Rule 5 clamps. So do `setLogged`, `setAdded` and `allSetsRepeated`, which is spec rule 1 applied to every write. Reps are ≥ 1 by type.
6. **`setAdded` normalises its set** to an undone `.added` row (rule 26). It is idempotent by set ID across the whole workout, not only within the exercise, so a set ID can never appear twice.
7. **`finished` and `discarded`** set `endedAt`, which freezes elapsed time (spec rule 24), and clear `rest` (spec rule 31), matching the `.cancelRestNotification` they emit.
8. **Program updates.**
   - `WorkoutState.programUpdates` is `[SlotID: ExerciseID]`.
   - A swap with `alsoUpdateProgram` records the slot's new exercise, and the latest such swap per slot wins.
   - A later one-off swap leaves the recorded update alone.
   - An exercise with no slot (ad hoc) records nothing.
   - F05 reads the map from the finished state it materialises. `WorkoutRepository.materialize` already takes the state.
9. **Device order without strings.**
   - The brief orders devices by `uuidString`.
   - Foundation's `UUID` is `Comparable` in byte order, which is the same order: 200,000 random pairs agreed in a probe on this toolchain.
   - `EnvelopeOrderingTests.order_isTotal_andMatchesUUIDStringOrder` pins the equivalence against `ModelOracle.precedes`, which compares `uuidString` literally.
   - So `<` compares `device.rawValue` and allocates nothing.
10. **The dispatch is split** into `apply` (9 cases) and `applyClockEvent` (5 cases). One 13-case switch breaks SwiftLint's `cyclomatic_complexity` (10) under `--strict`, and suppressions are not allowed. The one `default:` in `applyClockEvent` cannot be reached; it is the only uncovered line in `Engine/`.
11. **`ModelOracle` is independent.**
    - It never calls `WorkoutEngine` or `SupersetRounds`.
    - It finds blocks by walking the superset flags, rebuilds rounds with loops, and compares `uuidString` directly.
    - It keeps its own `Row` type.
    - It shares only the domain value types and `Duration` arithmetic.
12. **`EngineError.conflictingEnvelope(EnvelopeKey)`**
    - The reducer never fails: invalid events are ignored by rule.
    - The one error case belongs to the `WorkoutEventStore` contract: `append` throws it when a stored envelope with the same key differs.
    - This protects the invariant that `replay`'s determinism relies on: a key names exactly one envelope.
13. **The timing test (brief non-functional) is nightly-only.**
    - `ReplayPerformanceTests` is tagged `.slow` and enabled only when `LEDGER_TEST_LANE == "nightly"`.
    - Replaying 500 shuffled envelopes has a median of **1.8 ms** on the host in a debug build, in isolation. Most of that is the debug-build sort of large envelope values.
    - Under the parallel domain suite, one early run measured 6.6 ms, so it would be flaky on the PR lane.
    - The nightly-settings run (2,000 seeds, parallel) passed it.
    - `replay` folds in place through `step`, so a rebuild neither copies the state nor compares states per envelope.
14. **Where the random generator lives.** `RandomWorkout` needs `SeededGenerator`, which lives in the test target (F02 notes, deviation 9), so it sits in `LedgerDomainTests/Engine/Support/`. The shared, dependency-free fixtures sit in `LedgerTestSupport/Engine/`.

## Deviations from the brief

1. **No `now:` parameter.** The signatures are `reduce(_:_:)` and `replay(_:)`, as in architecture §6 and ADR-004.
   - The brief's `replay(_ log:, now:)` would make the state depend on when a device replays. Every device rebuilds by replay on each remote envelope (ADR-004 rule 2, F17). So a `restExtended` hitting no rest would get a different `endsAt` on the phone and the watch, and a new one on every rebuild. That breaks rule 12 and ADR-004's "`endsAt` is absolute".
   - Using the envelope's `wallClock` keeps rule 9's formula (`endsAt = now + by`) with `now` = the moment the user tapped "+30s" on the originating device.
   - Criterion 5 is tested exactly so.
2. **Associated-value labels.** Under `--strict`, SwiftLint's `identifier_name` (minimum 3 characters) rejects `at:`, `to:` and `by:` as enum associated-value names. Suppressions are not allowed and `.swiftlint.yml` is outside Touches. The labels now name the state field they write:

   | Brief | Now |
   |---|---|
   | `setLogged(…, at:)` | `setLogged(…, doneAt:)` |
   | `exerciseSwapped(…, to:, …)` | `exerciseSwapped(…, exerciseID:, …)` |
   | `restExtended(by:)` | `restExtended(amount:)` |
   | `finished(at:)` | `finished(endedAt:)` |
   | `discarded(at:)` | `discarded(endedAt:)` |
   | `Effect.scheduleRestNotification(at:)` | `Effect.scheduleRestNotification(endsAt:)` |

   **Orchestrator call:** F17's `WorkoutIntent` sketch uses `at:` everywhere and will hit the same rule. Either allowlist `^at$`, `^to$`, `^by$` in `.swiftlint.yml` (as F02 did for `lb`/`kg`) and restore the brief's labels, or keep these.
3. **Rule 9 also restarts a rest that is already over.** The brief says "if `rest == nil`". A rest that reached zero stays in the state, because reaching zero is not an event. So a literal reading makes "+30s" after zero extend a past `endsAt`, leaving the timer at zero: exactly the hole decision #7 closes ("'+30s' at zero restarts a 30 s rest").
   - A rest counts as running when `endsAt > wallClock`.
   - Tests: `extend_afterRestIsOver_startsFreshRest`, `extend_atExactEnd_startsFreshRest`.
4. **Additive F02 changes:**
   - `WorkoutState.units: Units` (default `.lb`, snapshotted by `SessionBuilder` from `settings.units`, like `autoRest`). `summary` needs it for the receipt rows (`ReceiptRow(exercise:units:)`), and the reducer builds the summary for `.materialize`.
   - `WorkoutState.programUpdates: [SlotID: ExerciseID]` (default `[:]`; rule 8, criterion 12).
   - `SessionBuilder.build` passes `units:`, and its doc comment says so.
   - Both new fields have init defaults, so every F02 call site compiles unchanged. The synthesized `Codable` shape of `WorkoutState` gains two keys; no persisted data exists yet.
5. **Adversarial test adaptation, compile-only.** `ProtocolsAdversarialTests.BriefShapes` declared an empty conformance to F02's reserved, empty `WorkoutEventStore`. F04 gives the protocol its members, as F02's notes said it would, so `WorkoutEventStore` was removed from that struct's conformance list. The test body never used it as a store. F05's `WorkoutEventStoreTests` will be the store's contract test.
6. **Effects:**
   - The list order is the contract in decision 3, not the brief's prose order.
   - `finished` and `discarded` also emit `.updateLiveActivity`, because the state changed. The Live Activity has to end (F21).
7. **Tests beyond the plan:**
   - `ReduceSelectTests` (rule 11 had no file in the plan);
   - `EventCodableTests`;
   - `ReplayPerformanceTests` (the brief's measured test);
   - `Support/*`.
8. **`EngineError.swift`** holds only the store-contract error (decision 12). There is no engine failure path to model.

## Known limitations

- **Incremental `reduce` does not converge on out-of-order arrival.**
  - A device must rebuild with `replay` when an envelope arrives that sorts before one it has already applied (ADR-004 rule 2; F17's actor does this).
  - `replay` returns only the state. F17 derives the local effects for a remote envelope itself, for example by reducing it on the pre-rebuild state for haptics and notifications.
- **For F17: the wire format must round-trip `wallClock` exactly.**
  - F17's sketch encodes dates with `.iso8601`, which drops fractional seconds.
  - The sender would then sort its own envelope by the precise time and the receiver by the truncated one. Two envelopes in the same second could fold in different orders, and the devices would diverge.
  - Fixes: encode with full precision (the default `.deferredToDate` round-trips exactly, as checked by `EventCodableTests`), or truncate `wallClock` at envelope creation.
- **Key uniqueness is an invariant, not something the engine enforces.**
  - If two different envelopes share a key and also tie on `wallClock`, `replay` keeps whichever arrived first.
  - Stores must reject such an envelope with `EngineError.conflictingEnvelope`.
- **Clock skew decides last-writer-wins.** A device whose clock runs far ahead wins every conflict. This is inherent in ADR-004's `(wallClock, device, seq)` ordering.
- **Validation gaps:**
  - `restExtended` with a negative amount is not rejected (no UI produces one).
  - `restStarted` with a past `endsAt` is stored as given.
- **The cursor is `(exerciseIndex, setIndex)`.** This is correct because a live workout never adds, removes or reorders exercises (brief risk 2).
- **`ModelOracle` and `EventBuilders` ship wherever `LedgerTestSupport` is linked**, which includes the feature targets. This is architecture §3's open question.
- **The `.slow` tag** is declared in `Engine/Support/EngineTesting.swift`, because `Support/Tags.swift` is outside Touches. Move it to `Tags.swift` when a second suite needs it.

## PR size

`git diff --numstat main -- LedgerKit/Sources/LedgerDomain`: **479 added + 6 deleted = 485 changed product lines**, within the 500 budget. Comments and formatting are not compressed.

| File | +/− |
|---|---|
| `Engine/WorkoutEngine+Reduce.swift` | +214 |
| `Engine/WorkoutEngine.swift` | +67 |
| `Engine/EventEnvelope.swift` | +49 |
| `Engine/WorkoutEvent.swift` | +41 |
| `Engine/WorkoutEngine+Replay.swift` | +39 |
| `Engine/Effect.swift` | +29 |
| `Engine/EngineError.swift` | +11 |
| `Protocols/WorkoutEventStore.swift` | +16 / −3 |
| `Model/WorkoutState.swift` | +10 / −1 |
| `Rules/SessionBuilder.swift` | +3 / −2 |

Test code, including `LedgerTestSupport/Engine`, adds about 1,970 lines.

## Gate

The full `scripts/check.sh` ran through `sim-lock.py` on 2026-09-28 and is **green** (217 s). Its log is
`scratchpad/f04-check.log` (orchestrator scratchpad).

| Step | Result |
|---|---|
| 0–2: tools, format, lint (`--strict`), package graph | OK; graph unchanged |
| 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed**. xcresult: 502 tests, 501 passed, 0 failed, 1 skipped |
| 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed**. xcresult: 493 tests, 492 passed, 0 failed, 1 skipped |
| 5: coverage gate | Not yet wired (F01); coverage was read by hand below |

- **The skipped test** in both bundles is `ReplayPerformanceTests.replay_500Envelopes_under5ms`, which is nightly only (decision 13).
- **`scripts/check.sh --fast`:** OK, 490 tests in 82 suites (488 domain tests in 80 suites, plus 2 persistence tests).
- **Nightly settings on the host:** `LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=2000` passed all 488 domain tests, including the 5 ms replay budget and 10,000 oracle sequences.

**Coverage.** Read from `xcrun xccov view --report --json .derivedData/Results/PR-{iOS,watchOS}.xcresult`,
over files whose path contains `Sources/LedgerDomain/Engine/`. Identical on both platforms:

| File | Lines |
|---|---|
| `WorkoutEngine.swift` | 37/37 |
| `WorkoutEngine+Replay.swift` | 30/30 |
| `WorkoutEngine+Reduce.swift` | 178/179 (the unreachable `default:` in `applyClockEvent`) |
| `EventEnvelope.swift` | 17/17 |
| **`Engine/` total** | **262/263 = 99.61 %** (brief: ≥ 95 %) |

- `WorkoutEvent`, `Effect` and `EngineError` have no executable lines.
- `WorkoutState.swift` 48/48 and `SessionBuilder.swift` 84/84.
- All `LedgerDomain` sources: 1646/1664 = 98.9 %.
- Host `llvm-cov` agrees: `Engine/` 99.6 %, with the same missed line.

## How to verify by hand

From the worktree root:

```sh
scripts/check.sh --fast                                               # format, lint, host domain tests
swift test --package-path LedgerKit --filter 'Reduce|Replay|Convergence|ModelOracle|Envelope|Effect|EventCodable'
LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=2000 \
  swift test --package-path LedgerKit --filter LedgerDomainTests      # nightly settings, incl. the 5 ms replay budget

# Host coverage of Engine/
swift test --package-path LedgerKit --filter LedgerDomainTests --enable-code-coverage
BIN=$(swift build --package-path LedgerKit --show-bin-path)
xcrun llvm-cov report "$BIN/LedgerKitPackageTests.xctest/Contents/MacOS/LedgerKitPackageTests" \
  -instr-profile="$BIN/codecov/default.profdata" LedgerKit/Sources/LedgerDomain/Engine
```

To check that the oracle has teeth, break a rule in `WorkoutEngine+Reduce.swift`, for example delete the
`?? order.prefix { $0 != ref }.first(where: isUndone)` line. Then run
`swift test --package-path LedgerKit --filter ModelOracleTests`: it fails with the seed, the sequence,
the step and the event.
