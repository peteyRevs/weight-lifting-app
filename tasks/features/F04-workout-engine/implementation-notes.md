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
| 1 `started` | `ReduceStartedTests`: `started_onNil_yieldsSnapshot`, `started_onExistingState_isIgnored`, `eventBeforeStarted_isIgnored`, `started_invalidSnapshot_isIgnored`, `envelope_forAnotherWorkout_isIgnored`, `replay_buffersEventsSortedBeforeStarted`, `replay_withoutStarted_isNil`; `Adversarial/Round3EffectsAdversarialTests.startedWithRest_reduceSchedulesItToo` |
| 2 terminal | `ReduceTerminalTests`: `criterion6_afterFinished_everythingIsIgnored` (13 cases, one per event kind), `afterDiscarded_everythingIsIgnored` (13), `firstTerminalWins` |
| 3 `setLogged` | `ReduceSetLoggedTests`: `criterion1_firstSet_startsRestAndAdvances`, `criterion2_superset_restsAfterRound_roundRobin`, `criterion3_lastSetOfExercise_movesToNextExercise`, `cursor_wrapsToEarliestUndoneRow`, `cursor_staysAfterLastRowOfWorkout`, `autoRestOff_startsNoRest`, `relog_updatesValuesOnly`, `negativeWeight_isClampedToZero`, `unknownSet_changesNothing` (3), `supersetDropRound_restsAfterLastDropRow` |
| 4 `setUnlogged` | `ReduceUnlogTests`: `criterion4_unlog_keepsCursorAndRest`, `relogAfterUnlog_isTransitionAgain`, `unlog_unknownOrUndone_changesNothing` |
| 5 `setTargetChanged` | `ReduceTargetLWWTests`: `criterion11_laterWallClockWins_inAnyArrivalOrder`, `lastWriterWins_perField`, `targetChange_touchesOnlyTheSet`, `clampAndNoOps` |
| 6 `setAdded` | `ReduceAddRepeatSwapTests`: `setAdded_appendsUndoneAddedRow`, `setAdded_isIdempotentBySetID` |
| 7 `allSetsRepeated` | `ReduceAddRepeatSwapTests.allSetsRepeated_writesEveryRow` |
| 8 `exerciseSwapped` | `ReduceAddRepeatSwapTests`: `exerciseSwapped_replacesIdentityOnly`, `criterion12_programUpdate_survivesFinish`, `programUpdates_latestPerSlot` |
| 9 rest | `ReduceRestTests`: `criterion5_extendWithNoRest_startsRestFromNow`, `extend_runningRest_growsEndsAtAndTotal`, `extendTwice_addsBoth`, `extend_afterRestIsOver_startsFreshRest`, `extend_followsTheLiftersIntent_notTheClock`, `extend_unshown_neverShortensARunningRest`, `longestRest_holdsGrownRests`, `longestRest_saturatesAHostileStateRest`, `restStarted_isAbsolute`, `skip_clearsRest` |
| 10 `finished` / `discarded` | `ReduceTerminalTests`: `finished_endsAndMaterializes`, `discarded_endsAndDropsLog`, `summary_ofFinishedWorkout`, `summary_ofLiveWorkout_hasZeroElapsed`, `summary_ofCorruptEndedAt_saturatesElapsed`, `summary_usesSnapshottedUnits`, `stillLifting_finishOpenedLater_endsAtTheLastSet`; `EffectTests.effects_finished` |
| 11 `exerciseSelected` | `ReduceSelectTests`: `select_undoneRow_movesCursor`, `select_doneRow_isIgnored`, `select_missingRow_isIgnored` (4) |
| 12 convergence | `ReplayTests`: `criterion7_shuffled100Times_sameState`, `criterion8_duplicatedLog_equalsDedupedReplay`, `replay_equalsSequentialReduce` (property), `resume_midWorkout_restoresState`, `foldOrder_dedupesAndLeadsWithStarted`, `foldOrder_leadsWithUsableStarted_andKeepsOnlyItsWorkout`. `ConvergenceTests`: `criterion9_partition_thenHeal_converges`, `randomPartition_converges` (property), `wallClockTie_breaksByDeviceThenSeq`. `EnvelopeOrderingTests`: `order_wallClockFirst`, `order_tieBreaksOnDevice`, `order_tieBreaksOnSeq`, `key_isDeviceAndSeq`, `order_isTotal_andMatchesUUIDStringOrder` (property) |

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
- **`EffectsFromToTests`** (a rebuild's effects, ADR-004 host loop): `unchanged_andStarted`,
  `remoteSetLog_buzzesAndSchedules`, `remoteRestChanges`, `terminals`, `lateEnvelope_rematerializes`,
  `setHaptic_oncePerRebuild`, `setHaptic_neverWhenTheWorkoutEnded`, and the properties
  `matchesReduce_onEveryStep` and `rebuildEffects_materializeInEveryArrivalOrder`.
- **`EnvelopeWellFormedTests`** (`isWellFormed`): `payloadDates_mustBeFinite`, `nonFiniteStamp_isMalformed`,
  `restLengths_liesWithinTheBound`, `startedSnapshot_isInternallyPossible`, `reduce_ignoresMalformed`,
  `replay_dropsMalformed`.
- **`WorkoutEventStoreContractTests`**: the store contract's 10 clauses on `InMemoryEventStore`.
- **`ExtremeValuePropertyTests.extremeValues_neverTrap_andStateEqualsItself`**: the fuzz.

_Refreshed in the review should-fix round (N4). `extend_atExactEnd_startsFreshRest` was deleted in fix
round 2 (B)._

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
   - Tests: `extend_afterRestIsOver_startsFreshRest`, `extend_atExactEnd_startsFreshRest` (deleted in fix round 2, B: "+30s" now carries `extendsShownRest`).
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

---

## Fix round 1 (2026-09-29)

Input: `test-findings.md` (findings 1–8, tests in `Engine/Adversarial/`) and the orchestrator's answers to
the spec questions. Before this round, 15 adversarial tests failed on the host (13 on the simulators).
All of them now pass, and no test is skipped or disabled apart from the nightly-only `.slow` replay-timing
test.

### Bugs

**1. `Duration` overflow traps (bug).**
- **Change:**
  - New `WorkoutEngine.longestRest`, **one hour**. Rule 3 caps an exercise's rest at 300 s, and only
    "+30s" grows a rest, so an hour is twelve times the longest configured rest. It is small enough that
    no `Duration` sum near it can overflow, and it keeps the rest ring's scale meaningful.
  - `startRest(_:at:)` holds every rest the engine writes: `total` is clamped into `0 ... longestRest`,
    and `endsAt` to at most `longestRest` after the rest starts. A rest starts at the envelope's
    `wallClock`, or at the set's `doneAt` for an automatic rest. Anchoring on `doneAt` matches rule 3,
    and it keeps `logSet` within SwiftLint's five-parameter limit.
  - `extendRest` adds totals with `saturatingSum` (`Int128` attoseconds with overflow reporting), then
    clamps. Saturation is still needed after the clamp, because a `started` snapshot's own `rest` is
    decoded unvalidated and can hold any `Duration`.
  - Out-of-range values are clamped, not rejected. A rejected value would have to fail at decode, and a
    stored envelope that no longer decodes would strand its whole log.
  - `ModelOracle` writes the same bound independently (`restLimit`: cut each term to ±1 h, add, cap),
    because the garbage property extends rests by up to a year.
- **Found while fixing:**
  - `Duration.seconds(Double)` traps on a non-finite value, or on one beyond about 1.7e20 s.
  - A binary plist decodes an infinite `Date`, and JSON carries a finite one such as 1e21.
  - Before this round, a decodable `finished(endedAt: 1e21)` therefore trapped `reduce` itself, through
    the summary built for `.materialize`. After finding 8's change it would have trapped F05's
    `WorkoutEngine.summary` call instead: the same crash loop, one step later.
  - `WorkoutState.elapsed(at:)` now saturates at `Int64.max` seconds, and NaN gives zero.
- **Tests:**
  - `EngineTrapAdversarialTests.decodedMaxDurationThenPlus30_doesNotTrap` and `hugeDurations_doNotTrap`,
    the tester's macOS exit tests, now pass unchanged.
  - New, and run on the simulators too:
    - `ReduceRestTests.longestRest_holdsHostileRests`;
    - `ReduceRestTests.longestRest_saturatesASnapshotRest`, with both `Duration` extremes, which covers
      the saturation branch;
    - `ReduceTerminalTests.summary_ofCorruptEndedAt_saturatesElapsed` (1e21, +∞, NaN).

**2. An unusable `started` reordered the log and dropped buffered envelopes (minor bug).**
- **Change:** `foldOrder` finds the first *usable* `started` with `WorkoutEngine.snapshot(startedBy:)`,
  the rule-1 predicate now shared with `step`, and moves only that envelope to the front. An unusable
  `started` stays where it sorts, and `step` ignores it there.
- **Tests:**
  - `StartedTerminalAdversarialTests.invalidFirstStarted_doesNotDropBufferedEnvelopes` and
    `GarbagePropertyAdversarialTests.garbage_replayMatchesOracle` now pass unchanged, including at 3,000
    seeds.
  - New: `ReplayTests.foldOrder_leadsWithUsableStarted_andKeepsOnlyItsWorkout` pins the fold order.

**3. The dedupe ran before the workout filter (minor bug).**
- **Change:**
  - `foldOrder` keeps only the envelopes of the workout that the first usable `started` begins, and
    dedupes by key after that.
  - A log with no usable `started` has no workout, so `foldOrder` returns `[]`. `replay` returns `nil`,
    as it did before.
  - `ModelOracle.replay` gets the same fix, in its own loops (`first(where:)`, a filter loop and its own
    `sameKey`). It still never calls `WorkoutEngine` or `SupersetRounds`.
- **Tests:**
  - `PartitionRaceAdversarialTests.strayWorkoutEnvelope_doesNotShadowSameKey` now passes unchanged,
    including its assertion on the oracle.
  - `ReplayTests.foldOrder_leadsWithUsableStarted_andKeepsOnlyItsWorkout` puts a stray envelope with the
    same key before this workout's envelope.

### Spec questions

**4. Persisting ignored envelopes. Orchestrator decision (2026-09-29): option (b).**
- **Rule:** the host (the live-workout actor, F17) appends every envelope it receives for the workout to
  `WorkoutEventStore` before it reduces it, whatever the effects. The append is idempotent on the key.
  `.persist` is only for envelopes this device creates.
- **Where it is written down:** the doc comments on `reduce`, `Effect.persist` and `WorkoutEventStore`.
- **Late envelopes after materialisation:** materialisation is an idempotent upsert keyed by
  `WorkoutID`. The host materialises again when replaying a finished log gives a different final state.
  This is a rule for F05 and F17, documented on `Effect.materialize`; F04 has no code for it.
- **Tests:** `TerminalOutcomeAdversarialTests.{lateEnvelopeSortingBeforeFinish,envelopeBeforeStarted,
  losingStarted}_isStoredByHost`. These replace the tester's three `…_isPersisted` tests; see "Tests
  edited" below.

**5. Duplicate delivery. Orchestrator decision (2026-09-29).**
- **Rule:**
  - `reduce` stays a pure function with no log.
  - **Precondition:** the caller dedupes by `EnvelopeKey`, so it reduces only the envelopes the store
    newly accepted.
  - `WorkoutEventStore.append` now returns `[EventEnvelope]`: the envelopes it newly stored, in the
    order given. A batch is all or nothing; when `append` throws, it stores none of it.
  - ADR-004's idempotence law is `replay`'s.
- **Where it is written down:** the doc comments on `reduce` and `append`.
- **Tests:**
  - `EffectsAdversarialTests.duplicateInLog_replayEqualsOnce`, retargeted from `reduceTwice_equalsOnce`.
  - `duplicateSetLogged_noSecondHaptic` and `duplicateRestExtended_extendsOnce`, now through the host
    path.
  - `WorkoutEventStoreContractTests.append_returnsNewEnvelopes_andIsIdempotent`.
- **Deferred to F17:** which effects a remote envelope may run. On reconnect, N remote `setLogged`s would
  play N haptics, and a rest notification whose `endsAt` has passed would be scheduled.

**6. Clock skew. Orchestrator decision (2026-09-29): hybrid logical clock stamping.**
- **Rule:** `wallClock = max(now, newest wallClock seen or sent + 1 ms)`. The host stamps it (F10/F17);
  the reducer does not. It keeps each device's `seq` order and the causal order.
- **Where it is written down:** "Amendment (2026-09-29): hybrid logical clock stamping" in ADR-004, and
  the doc comment on `EventEnvelope.wallClock`.
- **Tests:**
  - The three `ClockSkewAdversarialTests` now build their envelopes with `HLCDevice`, a test-support
    HLC stamper. They pass with their original assertions.
  - `withoutHLCPrecondition_rawSkewedStamps_convergeOnStampOrder` keeps the three raw-stamp logs as
    documentation of the precondition.
- **For F17:**
  - An HLC takes a received stamp as a lower bound. A peer whose clock is far ahead, or a corrupt stamp,
    would therefore drag this device's clock with it. Standard HLCs reject a remote stamp beyond a
    maximum drift; F17 should do the same.
  - That check also protects `RestTimer.remaining(at:)` (F02, UI only), which still converts with
    `Duration.seconds(Double)`. A rest ends at most an hour after its start, but a hostile start (the
    stamp or `doneAt`) could still put `endsAt` out of `Duration`'s range from `now`.

**7. Conflicting keys. Orchestrator decision (2026-09-29).**
- **Rule:**
  - Unique keys are a precondition. `WorkoutEventStore.append` enforces it with
    `EngineError.conflictingEnvelope`, and F17 must check keys on receive.
  - A device takes its next `seq` from `highestSeq` in its store, and runs `.persist` before `.transmit`,
    so a `seq` it has sent is always in its store.
  - `replay` breaks no tie.
- **Where it is written down:** the doc comments on `EventEnvelope` (the precondition and who keeps it),
  `Effect` (the order), `replay` and `highestSeq`.
- **Test:** `CodableOrderingAdversarialTests.conflictingKey_storeRejectsSecond_replayPrecondition`; see
  "Tests edited".

**8. The materialisation hand-off. Orchestrator decision (2026-09-29).**
- **Change:**
  - `WorkoutEventStore.unmaterializedWorkoutIDs()` lists logs that hold a terminal envelope and have not
    been compacted. On launch the host replays each one, materialises it if finished or drops it if
    discarded, then compacts it.
  - `.materialize` now carries the final `WorkoutState`. F05 writes the sets and `programUpdates` from
    it, and computes the `WorkoutSummary`, with PRs from history, through `WorkoutEngine.summary`.
  - The reducer no longer builds a summary.
- **Tests:**
  - `EffectTests.effects_finished`, `ReduceTerminalTests.finished_endsAndMaterializes`,
    `ReduceAddRepeatSwapTests.criterion12_programUpdate_survivesFinish` and the adversarial terminal
    cases, all updated.
  - `WorkoutEventStoreContractTests.liveAndUnmaterialized_untilCompacted`.

### Tests edited, and why

The tester's adversarial tests:

| Test | Edit | Justification |
|---|---|---|
| `EffectsAdversarialTests.reduceTwice_equalsOnce` | Renamed `duplicateInLog_replayEqualsOnce`. For every case it asserts `replay(before + [e, e]) == replay(before + [e])`, and that both equal one `reduce` of `e` | Finding 5: the law moves to `replay`. Why this is not a weakening is explained below |
| `EffectsAdversarialTests.duplicateSetLogged_noSecondHaptic` | The two deliveries go through `StoringHost`: store first, then reduce what is new | Finding 5's precondition. The assertions are unchanged: no second haptic or notification, same state |
| `EffectsAdversarialTests.duplicateRestExtended_extendsOnce` | Same, plus `replayed() == state` | Same. `endsAt` is still +30 s once, through the host and through replay |
| `EffectsAdversarialTests.terminalCases` (`finished`) | Expects `.materialize(final state)` | Finding 8. The expected list is unchanged otherwise |
| `TerminalOutcomeAdversarialTests.materialized` and its callers | Returns states; `summaries` computes receipts through `WorkoutEngine.summary`, F05's path | Finding 8. Every numeric assertion is unchanged, plus `materialized == [ended]` |
| `TerminalOutcomeAdversarialTests.lateEnvelopeSortingBeforeFinish_isPersisted`, `envelopeBeforeStarted_isPersisted` and `losingStarted_isPersisted` | Now `…_isStoredByHost`. Each asserts that `reduce` emits nothing, that the host's store holds the envelope, and that the store's replay applies it | Finding 4 (b). The tester's concern, that the envelope reaches the log replay reads so both logs agree, is asserted on the store. The empty effect list is now the documented contract |
| The three `ClockSkewAdversarialTests` | Stamped by `HLCDevice`. Assertions unchanged; two of them also assert that the HLC ordered the stamp after the envelope it followed | Finding 6 |
| New: `ClockSkewAdversarialTests.withoutHLCPrecondition_rawSkewedStamps_convergeOnStampOrder` | The tester's three raw-stamp logs. It asserts convergence over 24 arrival orders, and the documented stamp-order outcome (the causally later action loses) | Finding 6: kept as documentation, named for the precondition |
| `CodableOrderingAdversarialTests.conflictingKey_replayDependsOnArrival` | Renamed `conflictingKey_storeRejectsSecond_replayPrecondition`. In both arrival orders the store keeps the first envelope, throws `conflictingEnvelope` for the second, and replay of the stored log equals replay with only the first | Finding 7: there is no replay tiebreak, so the test asserts the enforcement of the precondition. The old assertion required order-independence exactly where the design says the precondition is violated |
| `EngineAdversarialSupport` | Adds `StoringHost` and `HLCDevice` | Support only |

The implementer's tests:

| Test | Edit | Justification |
|---|---|---|
| `EffectTests.effects_finished`, `ReduceTerminalTests.finished_endsAndMaterializes` and `ReduceAddRepeatSwapTests.criterion12_programUpdate_survivesFinish` | Expect `.materialize(state)` | Finding 8. Criterion 12 is now met through the state F05 receives |
| `ReplayTests.foldOrder_dedupesAndLeadsWithStarted` | `foldOrder` of a log without a `started` is now `[]` | Findings 2 and 3: with no usable `started` there is no workout to fold. `replay` was already `nil` and is unchanged |

**Why retargeting idempotence at `replay` is not a weakening.**
- ADR-004's law is a property of the system: a device that receives an envelope twice ends where one copy
  would have left it. That now holds, and is tested, on both paths where it can hold:
  - replay, for every event kind (`duplicateInLog_replayEqualsOnce`, and criterion 8);
  - the host path (`append` returns only new envelopes; the two `duplicate…` host tests).
- The host tests also pin "no repeated side effects", which the old state-only check did not.
- `reduce(reduce(s, e), e) == reduce(s, e)` cannot hold for a relative event like `restExtended` in a
  function with no memory.
  - Making it hold would mean carrying the set of seen keys in `WorkoutState`, which is the log itself,
    stored a second time.
  - A per-device high-water `seq` would not do: it would drop legitimate out-of-order arrivals.
  - Either way, every state comparison would then include delivery bookkeeping.
- The retargeted test still ties `reduce` to `replay` for every case.

**New test code:**
- `Engine/Support/InMemoryEventStore.swift`: the protocol's contract in memory, all-or-nothing batches.
  F17 may promote it to `LedgerTestSupport`.
- `Engine/WorkoutEventStoreContractTests.swift`, 5 tests: new envelopes and idempotence; conflicting
  batches; keys per workout; `highestSeq`; live, unmaterialised and compacted logs. They go through
  `any WorkoutEventStore`, so F05 can run the same assertions against GRDB.
- `LedgerTestSupport/Engine/ModelOracle+Edits.swift`: `ModelOracle.swift` would have passed SwiftLint's
  300-line `file_length` with the fixes. The per-row, rest and terminal edits moved to this sibling file
  unchanged, and `Model` went from `private` to internal so they can extend it. This is one file
  outside Touches.

### Open for F05 and F17

- **Compaction and late envelopes:**
  - After `compact`, a late envelope for that workout arrives at a log with no `started`. It is not
    live, not unmaterialised, and replays to `nil`, so the re-materialisation rule cannot apply to it.
  - F05 and F17 should either compact only once the peer's handshake shows nothing older is in flight,
    or drop envelopes for materialised workouts.
  - Either way, a log with no `started` should not linger.
- **The HLC drift bound** (finding 6) and **effects for remote envelopes** (finding 5), both above.

### Product lines

`git diff --numstat main -- LedgerKit/Sources/LedgerDomain`: **557 added + 7 deleted = 564 changed
product lines, over the 500 budget by 64.**
- This round added 120 lines (76 doc-comment lines, 41 code lines, 3 blank) and deleted 43.
- Nothing was compressed to fit, as instructed. The orchestrator declares the budget.

| File | +/− vs `main` |
|---|---|
| `Engine/WorkoutEngine+Reduce.swift` | +231 |
| `Engine/WorkoutEngine.swift` | +91 |
| `Engine/EventEnvelope.swift` | +60 |
| `Engine/WorkoutEngine+Replay.swift` | +41 |
| `Engine/WorkoutEvent.swift` | +41 |
| `Engine/Effect.swift` | +38 |
| `Protocols/WorkoutEventStore.swift` | +28 / −3 |
| `Model/WorkoutState.swift` | +13 / −2 |
| `Engine/EngineError.swift` | +11 |
| `Rules/SessionBuilder.swift` | +3 / −2 |

### Gate

The full `scripts/check.sh` ran through `sim-lock.py` on 2026-09-29 and is **green**: 224 s, after 287 s
waiting for the lock. The log is `scratchpad/f04-fix1-check.log` (orchestrator scratchpad).

| Step | Result |
|---|---|
| 0–2: tools, format, lint (`--strict`), package graph | OK: 0 of 189 files need formatting; lint is clean; the package graph is unchanged |
| 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed.** xcresult: 608 tests, 607 passed, **0 failed**, 1 skipped |
| 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed.** xcresult: 599 tests, 598 passed, **0 failed**, 1 skipped |
| 5: coverage gate | Not yet wired (F01); coverage was read by hand below |

- The one skip in each bundle is `ReplayPerformanceTests` ("Replaying 500 shuffled envelopes takes
  under 5 ms"), which is `.slow` and runs on the nightly lane only.
- `scripts/check.sh --fast`: 601 tests in 97 suites, all passing. The macOS exit tests are among them,
  including the two finding-1 trap tests.
- Nightly settings on the host (`LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=3000`): all 598
  domain tests pass. That includes the 5 ms replay budget, and the garbage and oracle properties at 3,000
  seeds (finding 2 had failed at 2,000).

### Coverage

Read from `xcrun xccov view --report --json .derivedData/Results/PR-{iOS,watchOS}.xcresult`, over
`Sources/LedgerDomain/Engine/`. The figures are identical on both platforms:

| File | Lines |
|---|---|
| `WorkoutEngine.swift` | 43/43 |
| `WorkoutEngine+Replay.swift` | 23/23 |
| `WorkoutEngine+Reduce.swift` | 188/189. The miss is the unreachable `default:` in `applyClockEvent` (line 49) |
| `EventEnvelope.swift` | 17/17 |
| **`Engine/` total** | **271/272 = 99.63 %** (brief: ≥ 95 %) |

- `WorkoutState.swift` is 48/48.
- Host `llvm-cov` agrees (`Engine/` 99.63 %), with the same missed line.
- The saturation branch of `saturatingSum` is covered on the simulators by
  `longestRest_saturatesASnapshotRest`.

---

## Fix round 2 (2026-09-29)

Input: `test-findings.md`, "# Round 2" (findings 9–14; tests in `Engine/Adversarial/`), and the orchestrator's
decisions A–G. Before this round, 5 tests failed on the host and 3 on the simulators, all of them finding 9.
Every test now passes. The only skip is the `.slow` replay-timing test.

### Scope boundary

- **F04 owns** the pure engine: the events, the envelope, validation (`isWellFormed`), `reduce`, `replay`,
  `summary` and `effects(from:to:)`. It also owns the `WorkoutEventStore` protocol and its contract suite.
- **F17 owns** the host: the live-workout actor loop, the HLC state and its persistence, the resend
  handshake, and running effects on a rebuild.
- F04 writes down what the host must do: the ADR-004 amendment, the doc comments, and "Inputs from F04" in
  `tasks/features/F17-live-sync.md`. It builds no host. The host models (`SimHost`, `StoringHost`,
  `LaunchStep`) live in the tests only. `StoringHost` was not promoted to `LedgerTestSupport`.

### A. Hostile or absurd payload values (finding 9)

**Orchestrator decision (2026-09-29, round 2).** One well-formedness predicate on `EventEnvelope`, used at
the top of `reduce` and in `replay`'s filter. Separately, no Date or Duration arithmetic in `LedgerDomain`
may trap on any input. A seeded property fuzzes extreme doubles.

**Change:**
- `EventEnvelope.isWellFormed`, public, in `EventEnvelope.swift`. An envelope is malformed when:
  - its `wallClock` is not finite;
  - any date it carries lies more than `EventEnvelope.payloadTimeWindow` (24 h) from its `wallClock`. That
    covers `doneAt`, a `setAdded` set's `doneAt`, `restStarted.endsAt`, `tappedAt` and `endedAt`. In a
    `started` snapshot it covers `startedAt`, `endedAt`, the rest's `endsAt` and every set's `doneAt`.
    `abs(Δ) <= window` fails for NaN, so a non-finite date never lies within the window;
  - a rest length (`restStarted.total`, `restExtended.amount`, a snapshot rest's `total`) lies outside
    `0 ... longestRest`;
  - a `started` snapshot's rest ends more than `longestRest` after the snapshot's `startedAt`: internally
    invalid.
- **Why 24 h is generous.** Both clocks read the same moment on one device, so a real envelope sits within
  seconds of its stamp. The margin covers HLC drift, where `wallClock` runs ahead of the device clock by a
  peer's skew. It also covers a long pause, for example a finish ended at the last set after hours of
  "Still lifting?" (decision #8). The window only has to catch the absurd.
- `reduce` returns `(state, [])` for a malformed envelope: no state change and no effects, not even
  `.persist` or `.transmit`. A device that creates one therefore neither stores nor sends it. One received
  from a peer stays stored, because the store judges keys, not contents.
- `foldOrder` drops malformed envelopes before it sorts, so a malformed `started` never picks the workout.
- Because every rest length is now validated, the reducer no longer clamps `restStarted` or the automatic
  rest. Only "+30s" on a shown rest is still held, because it grows: its `total` saturates at the bound, and
  its `endsAt` is at most `longestRest` after `tappedAt`, a payload time. `saturatingSum` now overflows only
  upwards, since an amount is never negative. It is still needed: `reduce` may be handed any state.
- A finite but absurd `wallClock` (say 1e21) is well-formed. It is only an ordering key, and F17's drift
  bound owns it. The ring can no longer trap on it (A.2).
- **Clamp or reject.** Finding 9's fix direction named both options: hold the dates, or saturate the ring.
  The orchestrator chose rejection plus saturation, so both hold. The tester's tests that assumed the clamp
  were retargeted to "malformed → ignored"; see the table below. A rejected envelope is not "a stored
  envelope that no longer decodes", round 1's reason for clamping. It still decodes and is still stored;
  the engine just skips it.

**A.2 audit** of `LedgerKit/Sources/LedgerDomain`: every `.seconds(`, `Duration.seconds`, `Int(`,
TimeInterval→Duration conversion, and `*` or `+` on Durations.

| Site | Before | Now |
|---|---|---|
| `RestTimer.remaining(at:)` | `.seconds(max(0, Δ))` trapped at ±∞ and beyond ~1.7e20 s | saturates at 2^63 s. A non-finite interval (a non-finite `endsAt` or `now`, NaN included) is **zero: no rest** |
| `RestTimer.fraction(at:)` | trapped through `remaining` | 0 when no rest is left, which covers every non-finite case |
| `WorkoutState.elapsed(at:)` | saturating since round 1 | unchanged; the doc now says 2^63 s (the tester's nit) |
| `RestDuration.duration` | `.seconds(Int)` of a value validated to 30…300 on decode | safe |
| `WorkoutEngine.longestRest`, `EventEnvelope.payloadTimeWindow` | constants | safe |
| `Date.adding(_:)` (Reduce), `isWellFormed` | `Duration / Duration` → Double; Date ± Double; `abs`, comparisons | never trap |
| `saturatingSum` | overflow-reporting `Int128` add | safe |
| `NumberText.fixed`: `Int(scaled.magnitude / divisor)` | not Date or Duration; called only with one fraction digit (divisor 10), so the quotient fits `Int` | safe |
| `roundedToInt` (`NSDecimalNumber.intValue`), `CivilDate` `Int(String)` / `Double(dayNumber)`, `Identifiers` widenings | no trapping conversion | safe |

The non-finite rule differs between the two saturating functions, deliberately. `elapsed(at: +∞)` is the
cap: round 1's rule, which the tester's `elapsed_realisticAndSaturated` pins. `remaining(at:)` of a
non-finite interval is zero, the orchestrator's "no rest" rule for A.2. Each doc comment states its rule.
After A.1, no state the engine folds holds a non-finite date. So these rules matter only for a caller's own
dates or a hostile `now`.

**Tests:**
- New `EnvelopeWellFormedTests` (7 tests): the window is a day; every payload date at and just beyond both
  edges, ±∞ and NaN, for all six dated events; a non-finite stamp; rest lengths at and beyond both bounds;
  the snapshot clauses; `reduce` returns `(state, [])`; `replay` and `ModelOracle.replay` drop a malformed
  `started`.
- New `ExtremeValuePropertyTests.extremeValues_neverTrap_andStateEqualsItself` (`.property`, seeded, on
  `PropertySeed.all`):
  - It builds logs whose dates are ±1e308, ±1e21, ±∞ or NaN about half the time, with stamps extreme 30 %
    of the time, and whose Durations range from `.min` to `.max` attoseconds.
  - It passes every log through a **binary property list**, because JSON cannot carry a non-finite date.
  - It asserts: no trap; `replay(log) == replay(log)`; replay of a shuffle; `ModelOracle.replay`; every
    folded state equals itself.
  - At ten extreme `now` values it reads `elapsed`, `rest.remaining`, `rest.fraction`, `doneSets`,
    `totalSets`, `volume`, `summary` and `effects(from:to:)` both ways.
- New `RestTimerTests.remainingAndFraction_saturate` (F02's model suite).
- `ModelOracle` gained `accepts`, written independently: it collects every payload date and rest length,
  then checks them with its own arithmetic. So the oracle property, the garbage property (whose durations
  reach a year and whose dates reach ±100,000 s) and the fuzz all compare two separate implementations of
  the predicate.

### B. The engine no longer judges intent from a clock (finding 14)

**Orchestrator decision (2026-09-29, round 2).** `restExtended` carries the lifter's intent, decided on the
originating device: `restExtended(amount: Duration, extendsShownRest: Bool, tappedAt: Date)`.

**Change:**
- When `extendsShownRest` is set and the state has a rest, the reducer extends it: `endsAt += amount` and
  `total += amount`, held to `longestRest` as described in A, whatever any timestamp says. Otherwise it
  starts `RestTimer(endsAt: tappedAt + amount, total: amount)` (decision #7).
- The reducer reads no `wallClock` for behaviour any more. `apply` and `applyClockEvent` lost their
  `at time:` parameter. The only remaining comparison of a payload time with `wallClock` is A's sanity
  bound.
- The clock rule is written into the ADR-004 amendment, the `WorkoutEvent` doc and the
  `EventEnvelope.wallClock` doc:
  - payload times (`doneAt`, `tappedAt`, `restStarted.endsAt`, `endedAt`) are the originating device's
    clock at the action;
  - `wallClock` is the HLC ordering stamp only.
- The doc on the case tells the UI how to set the flag: the rest is shown running while
  `RestTimer.remaining(at: now) > .zero`.
- Round 1's deviation 3 ("a rest counts as running when `endsAt > wallClock`") is superseded: the
  originating device decides.
- `ModelOracle` implements the same rule in its own code.

**Tests:**
- `ReduceRestTests`:
  - criterion 5, with both flag values when there is no rest;
  - `extend_afterRestIsOver_startsFreshRest`, where the device says the rest is not shown;
  - new `extend_followsTheLiftersIntent_notTheClock`: a shown rest extends although both clocks say it is
    over, and a rest shown as over restarts although both say it runs. It replaces
    `extend_atExactEnd_startsFreshRest`, whose premise, a judgement at the stamp, is gone.
- The tester's `hlcDraggedStamp_turnsAnExtendIntoARestart` and `dragStamps_judgeRunningRestsOver` now pass
  with the lifter's outcome (see the table below).

### C. The store contract suite kills every mutant (finding 10)

**Orchestrator decision (2026-09-29, round 2).** Fold the tester's store probes into
`WorkoutEventStoreContractTests`, so that the suite kills every mutant. Keep the mutation test as the
suite's own guard.

**Change:**
- `WorkoutEventStoreContractTests.swift` now holds `WorkoutEventStoreContract`: 9 named clauses, each run
  on a fresh store. It returns `nil` when the store keeps the clause, or what the store did instead.
  `violations(of:)` runs them all, so F05 can run the same list against its GRDB store.
- The clauses are the tester's nine probes, adapted to D, plus my five round-1 cases, which they subsume:
  1. new envelopes are returned in the order given, the stored set is right, and a re-append is a no-op;
  2. a conflict across batches throws and stores nothing from the batch;
  3. a conflict within one batch throws, stores nothing, and a retry succeeds;
  4. the same key and event with another stamp is a conflict;
  5. keys are per workout;
  6. `highestSeq` is the maximum per workout and device, and `nil` before anything is stored;
  7. every log is listed until it is compacted, whatever it holds: an early envelope, live, finished or
     discarded;
  8. `compact` deletes and unlists one workout's log and resets its `highestSeq`;
  9. new: a malformed envelope is stored like any other.
- The tester's `EventStoreContractProbes.swift` is deleted; its content lives in the suite.
- `EventStoreMutationAdversarialTests` now runs `WorkoutEventStoreContract.violations`, not `StoreProbe`.
- Two mutants mutated lists that no longer exist, so they were replaced:
  - `liveIgnoresStarted` → `listsOnlyStartedLogs`: it misses an envelope that arrived before its `started`;
  - `finishedOnlyIsTerminal` → `unlistsEndedLogs`: the old live list, which loses a workout killed before
    materialisation.
- One mutant was added: `dropsMalformed`. **The suite kills all 11**, and `InMemoryEventStore` passes it.

### D. One lifecycle list (finding 11)

**Orchestrator decision (2026-09-29, round 2).** Replace `liveWorkoutIDs()` and
`unmaterializedWorkoutIDs()` with `uncompactedWorkoutIDs()`. The host classifies each log by `replay`.

**Change:**
- `WorkoutEventStore.uncompactedWorkoutIDs()` lists every stored, uncompacted log. The doc gives the
  launch step: classify each log by `replay`.
  - Live: resume it.
  - Finished or discarded: materialise it or drop it, then compact it.
  - `nil`: **never compact it**. Keep it and request a resend.
- `InMemoryEventStore` implements it.
- Whether the resend handshake should use the highest *contiguous* seq per device is F17's call. It is
  recorded in the hand-off (G).

**Tests:**
- Contract clauses 7 and 8.
- `EventStoreAdversarialTests`:
  - its `Snapshot` is now `(listed, replayed)`;
  - a test-side `LaunchStep` models the host rule;
  - the three "(documents)" finding-11 tests now assert the contract.
- `MaterializeAdversarialTests` uses the new list.

### E. HLC recovery on launch (finding 12)

**Orchestrator decision (2026-09-29, round 2).** On launch, the HLC's `newest` is the largest stored
`wallClock` across the store's uncompacted logs. The host stamps no envelope before that recovery.

**Change:**
- The ADR-004 amendment gains "Recovery on launch". It adds that recovery skips a stored stamp that the
  host's drift bound would reject on receipt, so a corrupt stamp cannot drag the clock.
- The docs on `EventEnvelope.wallClock` and `uncompactedWorkoutIDs` point to it.

**Tests:**
- `SimHost.relaunch` (tests only) recovers from every envelope of every uncompacted log.
- `HostContractAdversarialTests.hlcAfterRelaunch_mustBeRecoveredFromTheLog` asserts the rule:
  - the first stamp after the relaunch sorts after the stored log;
  - the un-log stands, both in replay and on the phone's screen;
  - the forgetful host remains as the control.
- At scale, `hlc_convergesAndKeepsEveryAction` asserts no early stamp across the relaunches in every
  seeded session.

### F. The host loop and rebuild effects (finding 13)

**Orchestrator decision (2026-09-29, round 2).** Fix the docs on `append` and `reduce` to state the correct
loop. Add one pure helper, `WorkoutEngine.effects(from:to:)`, and make the tester's `SimHost` use it.

**Change:**
- **The loop**, now in the `reduce` doc, the `append` doc and the ADR-004 amendment:
  - append first;
  - if everything `append` newly stored sorts after the newest envelope applied, reduce it in sort order;
  - otherwise rebuild once by `replay`;
  - for received envelopes, run only `effects(from:to:)`.
  The phrase "the host reduces exactly these" is gone.
- **`WorkoutEngine.effects(from old:, to new:) -> [Effect]`**, public, in `WorkoutEngine+Replay.swift`:
  - when the workout has just ended: `.materialize(new)` if finished or `.discardLog` if discarded, then
    `.cancelRestNotification`;
  - when a finished workout changed: `.materialize(new)` again, an idempotent upsert. That includes a
    rebuild from `nil`, the finding-13c case;
  - otherwise, when the rest changed: schedule the new rest, or cancel;
  - `.updateLiveActivity` whenever the state changed;
  - **no haptics**, and no persist or transmit.
- `.updateLiveActivity` goes beyond the decision's list (phase change, rest change, no haptics). A remote
  weight change must still redraw the Live Activity (F21), and `reduce` emits the same effect under the same
  condition. The order matches `reduce`'s.

**Tests:**
- New `EffectsFromToTests` (7 tests):
  - one test per branch, including a late discard that overtakes a finish;
  - property `matchesReduce_onEveryStep`: at every step of seeded random sessions, the rebuild effects
    equal `reduce`'s own effects, less persist, transmit and haptics, and less a schedule or cancel that
    leaves the rest unchanged;
  - `rebuildEffects_materializeInEveryArrivalOrder`: 60 arrival orders, each materialising exactly the
    replayed state. It closes 13c, where 20 of 60 orders never materialised.
- `SimHost` runs `reduce`'s effects for its own envelopes and `effects(from:to:)` for received and rebuilt
  ones. It tracks the notification, the materialised workout, a dropped log and remote haptics.
  `hlc_convergesAndKeepsEveryAction` asserts, for every host of every seeded session:
  - notification == `state.rest?.endsAt`;
  - materialised == the final state when finished, or the log was dropped when discarded;
  - zero remote haptics.
- `HostContractAdversarialTests.arrivalOrderReduce_divergesFromReplay` and
  `rebuildThenReduceInOneBatch_appliesTwice` assert the documented loop on `SimHost`, with the wrong loops
  kept as controls.

### G. Hand-off to F17

**Orchestrator decision (2026-09-29, round 2).** Append "## Inputs from F04 (2026-09-29)" to
`tasks/features/F17-live-sync.md`.

It lists:
- the host loop (F);
- remote effects only from `effects(from:to:)`. This contradicts F17's criterion 9 and its Actor rule,
  which play `.haptic` for remote envelopes, so they must be amended;
- that F05 must delete a materialised workout when a late discard overtakes its finish;
- HLC recovery (E);
- the launch step, never compacting a log that replays to `nil`, and the open contiguous-seq question (D);
- malformed envelopes;
- F10's "Still lifting?" finish must not backdate `endedAt` beyond 24 h;
- non-finite dates must be rejected at wire decode, because NaN ≠ NaN would make a re-sent copy a conflict;
- the lossless date encoding: `.iso8601` drops sub-seconds and breaks ordering (round 1's finding);
- the renamed event labels, including the new `restExtended` shape and what `WorkoutIntent.extendRest`
  must carry.

### Tests edited, and why

The tester's adversarial tests:

| Test | Edit | Justification |
|---|---|---|
| `RestBoundAdversarialTests.taps` (support) and its three callers | "+30s" in the new shape, `extendsShownRest: true`. Every tap in them lands before its rest's end | B. The assertions are unchanged |
| `RestBoundAdversarialTests.bound_edges` | Four rows (one hour + 1 as, −1 as, `.max`, `.min`) now expect `nil`. The kept rows are unchanged | A: reject, not clamp; the tester named both options |
| `RestBoundAdversarialTests.zeroAndNegativeExtensions` | A negative +N now leaves the rest as it was. "Shown" is modelled from the watch's screen. The zero rows are unchanged | A (a negative length is malformed) and B |
| `autoRest_absurdDoneAt_endsNearItsEnvelope` → `…_isIgnored`; `snapshotRest_absurdEndsAt_isHeld` → `…_isIgnored`; `nanEndsAt_isHeld_andStateEqualsItself` → `nanEndsAt_isIgnored_andStateEqualsItself` | Same inputs. Each now asserts the envelope is malformed, the state has no rest (or nothing starts), and replay equals replay without it. The NaN test still asserts `replay == replay` | A. The question ("can this date reach the ring or break `==`?") is unchanged. The answer is now "it is ignored" |
| The two finding-9 exit twins | Unchanged, plus a direct call of `remaining` and `fraction` on the decoded hostile date | With rejection, the engine path no longer reaches the ring. Without the extra call the twins would pass vacuously. A strengthening (A.2) |
| `EventStoreAdversarialTests` lifecycle tests | `Snapshot(listed, replayed)`. An early-only log is now listed. `lifecycle_discarded` also runs the launch step | D |
| `EventStoreAdversarialTests`: `unusableStarted_isLive_butReplaysToNil`, `compactedThenPeerResend_orphanLog`, `holeBeforeTerminal_neverHeals_andLaunchStepDropsIt` | Renamed `unusableStarted_isListed_andKeptForResend`, `compactedThenPeerResend_isListed_andKeptUntilHealed`, `holeBeforeTerminal_isKept_untilTheResendHeals`. They assert that the log is listed, kept by the launch step, and materialised once the resend fills it | D: the orchestrator's "(documents) → assertions of the new contract". The hole test still pins `highestSeq == 3` as F17's open question |
| `EventStoreContractProbes.swift` | Deleted; its nine probes are the contract clauses | C |
| `EventStoreMutationAdversarialTests` | Runs the contract suite. Two mutants replaced, one added (see C) | C and D. The mutated lists no longer exist |
| `MaterializeAdversarialTests.rematerialization_convergesInEveryArrivalOrder` | `unmaterializedWorkoutIDs` → `uncompactedWorkoutIDs`, plus `replay` is finished | D. The count assertion is unchanged |
| `HostContractAdversarialTests.hlcAfterRelaunch_mustBeRecoveredFromTheLog` | Asserts rule E: stamp order, and the set stays undone. The forgetful host is kept as a control | E |
| `HostContractAdversarialTests.arrivalOrderReduce_divergesFromReplay`, `rebuildThenReduceInOneBatch_appliesTwice` | Assert the documented loop on `SimHost`. The tester's wrong loops are kept, unchanged, as controls | F |
| `HostContractAdversarialTests.hlcDraggedStamp_turnsAnExtendIntoARestart` | The tap carries `extendsShownRest: true` and `tappedAt`. It expects the lifter's outcome on both devices: `endsAt` 280 s, `total` 180 s, and a ring at 40/180. It still asserts that the stamp lands after the rest's end | B: "must now pass, with the lifter's expected outcome" |
| `HLCConvergenceAdversarialTests.dragStamps_judgeRunningRestsOver` | Asserts that taps stamped after their rest's end still occur (dragged > 0) and that none did other than what the lifter saw (0) | B |
| `HLCConvergenceAdversarialTests.hlc_convergesAndKeepsEveryAction` | Adds the effects assertions (see F) | F; a strengthening |
| `forgottenClockOnRelaunch_stampsEarly`, `naiveHostLoop_leavesReplay` | Display names "(documents)" → "(control for decision E/F)" | Answered questions. They remain the controls that show the rules have teeth |
| `HLCHostAdversarialSupport.SimHost`, `HLCScenarioAdversarialSupport` (support) | `SimHost`: E recovery and F effects. `HLCScenario`: its "+30s" metric now compares with the lifter's expectation, and it counts the dragged stamps | E, F, B |
| `RestAdversarialTests.extend` (support) and `concurrentExtends_bothCount` | The helper models the originating device: shown iff `remaining > 0` at the tap on its clock. All assertions are unchanged | B. The judgement moves to the device. With one clock the outcomes are identical |
| `EngineAdversarialGenerators` (`EngineGen.plus30`), `EngineAdversarialSupport` (`EngineAdv.extend`) | "+30s" as the device sends it | B; support only |
| `GarbagePropertyAdversarialTests`, `EngineTrapAdversarialTests`, `EffectsAdversarialTests`, `StartedTerminalAdversarialTests`, `BoundsAdversarialTests`, `CodableOrderingAdversarialTests` | The event shape only. Garbage now draws a random flag, which changes each seed's stream | B. The assertions are unchanged |

The implementer's tests:

| Test | Edit | Justification |
|---|---|---|
| `ReduceRestTests`: criterion 5, `extend_runningRest…`, `extendTwice…`, `extend_afterRestIsOver…` | The new event shape. Criterion 5 runs with both flag values | B |
| `ReduceRestTests.extend_atExactEnd_startsFreshRest` | Replaced by `extend_followsTheLiftersIntent_notTheClock` | B: the engine no longer judges "at the exact end" |
| `ReduceRestTests.longestRest_holdsHostileRests` | Now `longestRest_holdsGrownRests`: well-formed extensions past the bound | A: the hostile inputs are malformed now (`EnvelopeWellFormedTests`) |
| `ReduceRestTests.longestRest_saturatesASnapshotRest` | Now `…_saturatesAHostileStateRest`, through a caller's state | A: such a snapshot is rejected. The saturation still guards `reduce`'s input |
| `ReduceTerminalTests.summary_ofCorruptEndedAt_saturatesElapsed` | The finish is ignored. Saturation is asserted on a state that holds the date | A |
| `ReduceTerminalTests.lateEvents`, `ConvergenceTests.criterion9…`, `EffectTests` "restExtended" row, `RandomWorkout` | The event shape only | B |
| `WorkoutEventStoreContractTests` | Rewritten as the clauses | C and D |

### Gate

The full `scripts/check.sh` ran once through `sim-lock.py` on 2026-09-29 and is **green**. It took 545 s; the
lock was free. The log is `scratchpad/f04-fix2-check.log` (orchestrator scratchpad).

| Step | Result |
|---|---|
| 0–2: tools, format, lint (`--strict`), package graph | OK: 0 of 200 files need formatting; lint is clean; the package graph is unchanged |
| 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed.** xcresult: 653 tests, 652 passed, **0 failed**, 1 skipped |
| 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed.** xcresult: 644 tests, 643 passed, **0 failed**, 1 skipped |
| 5: coverage gate | Not yet wired (F01); coverage was read by hand below |

- The one skip in each bundle is `ReplayPerformanceTests` ("Replaying 500 shuffled envelopes takes under
  5 ms"), which is `.slow` and runs on the nightly lane only.
- `scripts/check.sh --fast`: 648 tests in 106 suites, all passing, the macOS exit tests included.
- Nightly settings on the host (`LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=3000`): all 646
  domain tests pass. That includes the 5 ms replay budget, and at 3,000 seeds the fuzz, the rebuild-effects
  property, the HLC property with its effects assertions, the garbage property and the oracle property.
  The log is `scratchpad/f04-fix2-nightly.log`.

### Coverage

Read from `xcrun xccov view --report --json .derivedData/Results/PR-{iOS,watchOS}.xcresult`, over
`Sources/LedgerDomain/Engine/`. The figures are identical on both platforms:

| File | Lines |
|---|---|
| `WorkoutEngine.swift` | 43/43 |
| `WorkoutEngine+Replay.swift` | 46/46 |
| `WorkoutEngine+Reduce.swift` | 184/185. The miss is still the unreachable `default:` in `applyClockEvent` |
| `EventEnvelope.swift` | 65/65 |
| **`Engine/` total** | **338/339 = 99.71 %** (brief: ≥ 95 %) |

- `Model/RestTimer.swift` is 17/17.
- Host `llvm-cov` agrees: `Engine/` 99.71 % of lines, and 100 % of functions.

### Product lines

`git diff --numstat main -- LedgerKit/Sources/LedgerDomain`: **699 added + 10 deleted = 709 changed product
lines**, over the 500 budget by 209. Round 1 ended at 564.
- This round added 219 lines (127 comment, 85 code, 7 blank) and deleted 80 (48 comment, 32 code).
- Nothing was compressed. The overage goes to Pete, who chooses between a waiver and a split.

| File | Changed vs `main` | Split |
|---|---|---|
| `Engine/WorkoutEvent.swift` | 50 | A |
| `Engine/EventEnvelope.swift` (with `isWellFormed`) | 135 | A |
| `Engine/Effect.swift` | 39 | A |
| `Engine/EngineError.swift` | 11 | A |
| `Protocols/WorkoutEventStore.swift` | 39 | A |
| `Model/RestTimer.swift` | 14 | A |
| `Model/WorkoutState.swift` | 16 | A |
| `Rules/SessionBuilder.swift` | 5 | A |
| `Engine/WorkoutEngine.swift` | 101 | 17 in A, 84 in B |
| `Engine/WorkoutEngine+Reduce.swift` | 227 | B |
| `Engine/WorkoutEngine+Replay.swift` (with `effects(from:to:)`) | 72 | B |

**A clean split:**
- **PR A, "event vocabulary + validation + store contract": 326 lines.**
  - It holds every file marked A.
  - It also holds the head of `WorkoutEngine.swift`: `public enum WorkoutEngine` with `longestRest` only
    (17 lines). `isWellFormed` needs that bound, and it is the only code dependency across the split.
  - Its tests: `EnvelopeWellFormedTests`, `EventCodableTests`, `EnvelopeOrderingTests`,
    `WorkoutEventStoreContractTests`, `EventStoreMutationAdversarialTests`, `EventStoreAdversarialTests`
    (less its host test), `CodableOrderingAdversarialTests`, `RestTimerTests`, `InMemoryEventStore`, and
    `EventBuilders`.
- **PR B, "reduce/replay/summary/effects": 383 lines.**
  - It holds the rest of `WorkoutEngine.swift` (`reduce`, `step`, `snapshot`, `summary`), all of
    `+Reduce` and all of `+Replay`.
  - Its tests: every other engine suite, `ModelOracle`, and the host models.
- Both halves are under 500. A lands first; B depends on it.

### Orchestrator correction (2026-09-29): remote haptics

Decision F said "no haptics for remote changes". That contradicts F17 criterion 9 and the architecture's Actor rule, a planned UX. Narrowed: a received envelope reduced in order runs `reduce`'s effects without `.persist`/`.transmit` (so its haptic plays); only a rebuild uses `effects(from:to:)`, which has no haptics. ADR-004 "The host loop", the `effects(from:to:)` doc comment and F17's hand-off say so.

---

## Re-plan (2026-09-29): final fix round

Input: `test-findings.md`, "# Round 3" (findings 15–22, "Out of scope, noted"; tests in `Engine/Adversarial/`), and
the re-plan the orchestrator agreed with Pete after G2 failed three times. F04 is frozen: this round fixes the
listed findings, simplifies where told, and adds no mechanism. Before it, 8 tests failed on the host (17
issues); now every test passes, and the only skip is the `.slow` replay-timing test.

### Decisions → changes → tests

| # | Decision (owner) | Change | Tests |
|---|---|---|---|
| 1 | Both devices stay fully live (Pete) | None: the context for 2–4 | — |
| 2 | Validation has no time windows (Pete; findings 15, 16) | `EventEnvelope.payloadTimeWindow` and every comparison of a payload date with `wallClock` are gone. `isWellFormed` is now one allocation-free switch: malformed only when a date it carries is not finite (`wallClock`, every payload date, every snapshot date, `lastPerformance.date` included) or a rest length is outside `0 ... longestRest` (a snapshot rest's `total` included). The snapshot clause "its rest ends at most `longestRest` after `startedAt`" went too: it is a window between two dates, and Pete's list names only non-finite dates and out-of-bound lengths. `ModelOracle.accepts` rewritten independently to match | `Round3WellFormed…stillLifting_finishOpenedDaysLater_isKept` (unchanged, passes); new `ReduceTerminalTests.stillLifting_finishOpenedLater_endsAtTheLastSet` (30 h and 30 days); `EnvelopeWellFormedTests` (rewritten, below); the fuzz, strengthened |
| 3 | The host loop is simplified (orchestrator; Pete's haptic rule; findings 13, 17, 18, 19) | Docs: ADR-004 "The host loop" rewritten; `reduce`, `append`, `envelopes(for:)`, `Effect`, `persist`, `replay` and `effects(from:to:)` docs; F17 "Inputs from F04" items 1, 2, 5. Code: `effects(from:to:)` leads with at most one `.haptic(.setLogged)`, when `new` is live and a set is done in `new` that was not in `old` (the live condition is the orchestrator's addition, below) | New `EffectsFromToTests.setHaptic_oncePerRebuild` (a single remote set: 1; a batch of 10: 1, also from `nil`; an un-log: 0; no newly done set, a re-log, a skip, a finish: 0) and `setHaptic_neverWhenTheWorkoutEnded`; `remoteSetLog_buzzesAndSchedules`; the host models and their tests (below) |
| 4 | "+30s" never shortens a running rest (Pete; finding 20) | `extendRest`: with `extendsShownRest == false`, a state rest whose `endsAt` is later than `tappedAt + amount` is kept unchanged (no own effects), else the fresh rest starts. `true` is unchanged. The oracle's `extendRest` gained the same rule, in its own code | New `ReduceRestTests.extend_unshown_neverShortensARunningRest` (kept, replaced, and the tie, which restarts); `Round3RestIntent…unseenRest_plus30KeepsTheLongerRest` |
| 5 (21) | `reduce` schedules a `started` snapshot's rest | `step` returns `.scheduleRestNotification(endsAt:)` for a snapshot with a rest | `Round3Effects…startedWithRest_reduceSchedulesItToo` (unchanged, passes); `matchesReduce_*` properties |
| 5 (22) | The store contract catches lossy stores | New clause "an envelope reads back once and exactly, to below a millisecond": an HLC stamp and a payload date between milliseconds, appended twice, read back as exactly `[envelope]` (array, so the count counts). `envelopes(for:)`'s doc states it. Three new mutants: `keepsCopies`, `stampToMilliseconds`, `payloadToMilliseconds` | `EventStoreMutationAdversarialTests`: all **14** mutants killed, `InMemoryEventStore` passes. A probe showed each new mutant, and each `LossyEventStore` loss, is killed by the new clause alone (`iso8601JSON` also by `conflictOnStampOnly`). `Round3Store…contract_catchesLossyStores` passes for all three losses |
| 5 (19) | Docs and tests agree with decision 3 | No doc or test says "remote changes never buzz" or implies a per-envelope remote buzz (grep for `never buzz`, `remote change`, `in order`, `newest … applied`, `reduced in order`, `per envelope` over sources, tests, ADR-004, F17 and F23) | — |
| 6 | Out of scope stays out | F17 "Inputs from F04" item 8: dropping a log at the terminal, the drift bound, F05's stale brief. F23 gains "Inputs from F04": the "Still lifting?" Finish (and that the prompt is F23's, not F10's), rests already over (F18 needs criterion 1's rule), and the notification's "+30s" sending `extendsShownRest: false` | — |

**Finding 16, re-checked under decision 2:**
- **a** (`lastPerformance.date`): fixed. Every snapshot date is checked for finiteness. The fuzz now also
  replays two independent decodes of each log, which share no storage, so a nested NaN can no longer hide
  behind `Array ==`'s identity shortcut; its snapshots now carry extreme `lastPerformance` dates. What no
  predicate can fix: a store that compares by value calls a NaN envelope's resend a conflict (NaN ≠ NaN).
  That is F17's decode guard (hand-off item 5), and the tester's test now pins it.
- **b** (`setAdded` dropped over a far `doneAt`): fixed; a finite `doneAt` no longer drops the add. A NaN
  `doneAt` still makes it malformed, by Pete's rule ("a date it carries").
- **c** (a well-formed rest showing 23 h left): accepted by decision. Bounding a rest's end by its stamp is a
  time window. The rest is applied as given, and the ring saturates (`remaining`, `fraction` ≤ 1).

**Host loop, as now written** (ADR-004, `reduce`'s doc, F17 item 1):
- own action: stamp (HLC), `reduce`, run its effects in order; `.persist` is the append, before `.transmit`.
  The HLC sorts it after everything stored, so this equals `replay` (stated in the ADR and the doc);
- received envelopes: append; if anything is new, rebuild with `replay` and run `effects(from:to:)`. There is
  no in-order path, so finding 17's "already applied" has nothing left to mean;
- launch: the launch step replays each log and plays no haptic. This one sentence is new, and forced by
  decision 3: once `effects(from:to:)` carries a haptic, a host that ran `effects(from: nil, to:)` on launch
  would buzz for every set already done. The host models therefore run no effects on relaunch (the
  notification and the stored workout survive it, as they would on a device).

**Orchestrator addition (2026-09-29, after the first gate): the haptic only while the workout is live.**
`effects(from:to:)` plays its `.haptic(.setLogged)` only when `new` is live. A rebuild that ends finished or
discarded never buzzes, even when a late set became done: a set that arrives after a peer's finish but sorts
before it (it re-materialises, silently), or a discarded log that arrives whole. "The launch step plays no
haptic" stands. ADR-004 and F17 item 2 say "while the workout is live".
- Code: one condition, `new?.phase == .live`, on `newlyDone`.
- Tests: new `EffectsFromToTests.setHaptic_neverWhenTheWorkoutEnded` (a late set before a peer's finish: 0,
  with the re-materialisation; a discarded log with a done set, from `nil` and from live: 0; the live single
  set and a live batch: exactly 1, also from `nil`). `setHaptic_oncePerRebuild` still passes unchanged in
  its assertions. The two property filters (`matchesReduce_onEveryStep`, `matchesReduce_onIntentLogs`) keep
  the set haptic only for a live `new`.
- Reverted to the tester's original: `Round3Effects…discardLog_order` (from `nil`, a discard is exactly the
  drop again, no haptic).

**Also changed, for the replay budget:** the first version of the new predicate built arrays per envelope and
cost 0.6 ms of a 2.3 ms replay of 500 envelopes (host, debug), and the nightly run measured a 6.7 ms median
under full parallel load. The single switch allocates only for a `started`: the predicate now costs 0.15 ms
and replay 1.8 ms, round 1's figure, and it is 6 lines shorter.

### Tests edited, and why

The implementer's tests:

| Test | Edit | Why |
|---|---|---|
| `EnvelopeWellFormedTests.payloadWindow_isADay` | Deleted | Decision 2: the window is gone |
| `EnvelopeWellFormedTests.payloadDates_liesWithinTheWindow` | Now `payloadDates_mustBeFinite`: a day and a millisecond away, 30 days, 1e21, −1.8e308 and `distantFuture` are well-formed; ±∞ and NaN are not; all six dated events | Decision 2 |
| `EnvelopeWellFormedTests.startedSnapshot_isInternallyValid` | Now `…_isInternallyPossible`: far dates and a rest ending 2 h after the start are well-formed; a non-finite date anywhere (a `lastPerformance.date` included) and a negative or over-an-hour total are not | Decision 2; finding 16a |
| `EnvelopeWellFormedTests.reduce_ignoresMalformed`, `replay_dropsMalformed` | The malformed fixture is a NaN or ∞ `doneAt`, not 1e9 s | 1e9 is finite, so well-formed now. Assertions unchanged |
| `ReduceRestTests.extend_followsTheLiftersIntent_notTheClock` | The running rest in the second half ends at 30 s, not 100 s | Decision 4 keeps a rest ending after the fresh one (100 s > 35 s). With 30 s, the tap still restarts although both clocks say the rest runs: the case's point, unchanged |
| `ReduceTerminalTests.summary_ofCorruptEndedAt_saturatesElapsed` | A 1e21 finish is kept (the phase is finished) and saturates; ±∞ and NaN are still ignored | Decision 2 |
| `EffectsFromToTests.remoteSetLog_schedulesWithoutHaptic` | Now `remoteSetLog_buzzesAndSchedules`; expects the haptic first | Decision 3 |
| `EffectsFromToTests.lateEnvelope_rematerializes` | The "changed" case changes reps; a new case adds a late set log, which re-materialises without a buzz | Decision 3 and the orchestrator's addition (no haptic once the workout ended); the re-materialisation assertion is unchanged |
| `EffectsFromToTests.matchesReduce_onEveryStep` | The filter keeps `.haptic(.setLogged)` when a set became done in a live workout | Decision 3 and the orchestrator's addition |
| `EffectsFromToTests.rebuildEffects_materializeInEveryArrivalOrder` | `remoteHaptics == 0` → at most one per delivery, and at most 3 in all (an order that brings a set after both finishes plays none for it) | Decision 3 (finding 19's rejected assertion) and the orchestrator's addition |
| `ExtremeValuePropertyTests` | Snapshots also vary `lastPerformance.date`; two independent decodes must replay equal | A strengthening: closes finding 16a's blind spot |
| `WorkoutEventStoreContract.malformedIsStored` | Its malformed fixture is a 2 h "+30s", not a `doneAt` of 1e12 s | 1e12 is finite, so well-formed now |

The tester's tests:

| Test | Edit | Why |
|---|---|---|
| `Round3WellFormed…peerClockADayAhead_dragsStamps` | The 24.5 h row is now kept, and a 30-day row is added | Decision 2: there is no window to drop a dragged action |
| `Round3WellFormed…edges_atARealisticStamp` | A day and a millisecond either side is well-formed; DST part unchanged | Decision 2: no edges |
| `Round3WellFormed…snapshotLastPerformanceNaN_breaksEquality` | The first two assertions are unchanged and pass. The third (the store accepts the NaN resend) now asserts the conflict | NaN ≠ NaN, so any store that compares by value calls the resend a conflict; no predicate changes that. F17 rejects non-finite dates on decode (item 5) |
| `Round3WellFormed…eventRests_endWithinLongestRestOfTheirStamp` | Now `eventRests_farFromTheirStamp_areAppliedAsGiven` (documents): well-formed, applied as given, the ring saturates | Decision 2: bounding a rest's end by its stamp is a time window |
| `Round3RestIntent…unseenRest_plus30Shortens` | Now `unseenRest_plus30KeepsTheLongerRest`: the phone's 160 s / 150 s rest is unchanged and still shows 145 s; a tap at 140 s restarts (170 s) | Decision 4, as the orchestrator required |
| `Round3RestIntent…rest` (helper) | Message text only | `Replica` now only rebuilds |
| `Round3Effects…matchesReduce_onIntentLogs` (`rebuildShare`) | Keeps the set haptic when a set became done in a live workout; "never buzzes" → at most one set haptic and no finish haptic | Decision 3 and the orchestrator's addition |
| `LiteralHost` (`Round3HostAdversarialSupport`) | One path: own → reduce; received → append, rebuild, `effects(from:to:)`. `Applied`, `newestApplied` and the `.inOrder` path removed; relaunch runs no effects | Decision 3 |
| `Round3Scenario` | The `applied` parameter removed; the generator stream is unchanged | Decision 3 |
| `Round3Host…literalHost_convergesAndRebuildsNeverBuzz` | Now `…_convergesAndBuzzesOncePerDelivery`: `largestBurst <= 1`; every other assertion unchanged | Decision 3, Pete's rule |
| `Round3Host…inOrderRemoteEnvelopes_buzz` | Now `remoteSetLogs_buzz`: rebuild haptics > 0 | Decision 3: the haptic comes from the rebuild |
| `Round3Host…appliedMeaning_decidesALostFirstMessage` | Now `lostFirstMessage_staysOnReplay`: 0 mismatches, both sets shown, 2 buzzes. The reading-B control and its 100-seed count are removed | Finding 17 asked which reading of "applied" holds; decision 3 removes the phrase, so reading B no longer describes any host |
| `Round3Host…rawStamps_literalLoopLeavesReplay` | Now `rawStamps_oneLoopStaysOnReplay`: 0 mismatches (was 1), set done | Decision 3: a received envelope is never reduced, so the raw-stamp case the old loop got wrong now rebuilds |
| `Round3Host…reconnectBatch_inOrder_buzzesPerSet` | Now `reconnectBatch_buzzesOnce`: 1 buzz whether or not the phone acted (was 5 and 0) | Decision 3, Pete's rule (finding 18) |
| `Round3Host…simHost_playsTheInOrderRemoteHaptic` | Now `remoteSetLog_buzzesOnEveryHostModel`: `.rebuild` key; `SimHost` plays 1 | Decision 3 (finding 19): both models agree |
| `Round3Store…contract_catchesLossyStores` | The contract assertion is unchanged and passes. The read-back assertion is flipped to `!=` | `LossyEventStore` is lossy by construction, so `==` could never hold (it failed for all three losses before and after any fix). It now pins that the loss is real |
| `Round3Store…iso8601Store_losesAnUnlog` | Asserts the un-log is lost on that store, and that the contract suite rejects the store | The same: the store cannot be fixed, only rejected. The consequence is documented |
| `SimHost` (`HLCHostAdversarialSupport`) | One path, as `LiteralHost`; `remoteHaptics` counts rebuild haptics, and `largestRemoteBurst` is new; relaunch runs no effects; `newestApplied` removed | Decision 3 (finding 19) |
| `HLCConvergence…hlc_convergesAndKeepsEveryAction` | `remoteHaptics == 0` → `largestRemoteBurst <= 1` | Decision 3; finding 19's rejected assertion |
| `HLCConvergence…rawClocks_loseActions` | `host.state == expected` and `replayMismatches == 0` → `replay(host.log) == expected`; the lost-action assertions are unchanged | Decision 3: a host reduces its own envelope, which equals replay only under the HLC. With raw clocks a host's screen can leave replay; its log still converges, which is what the control is about |
| `HostContract…hlcAfterRelaunch_mustBeRecoveredFromTheLog` | The control's `forgotten.shown` is now `false`; the recovered case is unchanged | The old `SimHost` rebuilt its own envelope when it sorted early; the loop now reduces it. So the forgetful phone shows the un-log that its log, and every peer's, has lost: the breach is still visible (`forgotten.done`) |
| `HostContract…arrivalOrderReduce_divergesFromReplay` | Name text; the control reduces in arrival order with `Adv.state(after:)` | `StoringHost` now follows the loop, so it can no longer be the control |
| `HostContract…rebuildThenReduceInOneBatch_appliesTwice` | Name text only | Decision 3 |
| `Replica` (`EngineAdversarialSupport`) | Rebuilds on every new envelope; `newest` and `rebuilds` removed | Decision 3 |
| `StoringHost` (`EngineAdversarialSupport`) | Append; if anything is new, rebuild and return `effects(from:to:)` | Decision 3: it was round 1's per-envelope loop, a per-envelope remote buzz (finding 19) |
| `ConvergenceProperty…incremental_matchesReplayAtEveryStep` | Also asserts that an envelope sorting after everything held reduces to replay's state | With `Replica` always rebuilding, the old check alone was vacuous. This keeps the reduce path under test: the own-action path's guarantee |
| `EventStore…host_reducesEachNewEnvelopeOnce` | Now `host_appliesEachNewEnvelopeOnce`: the second batch's effects are the rebuild's (`[schedule 190 s, redraw]`), not `reduce`'s | Decision 3 |
| `TerminalOutcome…lateEnvelopeSortingBeforeFinish_isStoredByHost` | Effects `[]` → `[materialize(replayed), redraw]` | Decision 3: the rebuild re-materialises, which the old per-envelope loop left to F05/F17; no haptic, the workout is over |
| `TerminalOutcome…losingStarted_isStoredByHost` | Effects `[]` → `[redraw]`; the host's state has the watch's snapshot | Decision 3. The old loop kept the phone's snapshot, off replay |
| `EffectsAdversarial…duplicateSetLogged_noSecondHaptic` | Name and doc text only | Decision 3 |
| `RestBound…autoRest_absurdDoneAt_isIgnored`, `snapshotRest_absurdEndsAt_isIgnored` | Now `…_saturatesTheRing`: well-formed, applied, the ring pinned at its cap and full, `==` holds. The NaN test and both exit twins are unchanged (comments only) | Decision 2: finding 9's second option, saturation, is now the only one |
| `EventStoreMutationAdversarialTests` | Three mutants added | Decision 5 (22) |

Unchanged and passing: every other adversarial test, including `MaterializeAdversarialTests` (its
`Materializer` now receives the rebuild's `.materialize`) and the `Replica` convergence tests.

### Gate

- **`scripts/check.sh --fast`** (host): OK. 674 tests in 111 suites pass; format (0 of 207 files) and lint
  `--strict` are clean. Log: scratchpad `f04-fix3-fast.log`.
- **Full `scripts/check.sh` through `sim-lock.py`, once** (2026-09-29): **green**, 219 s; the lock was free.
  Log: scratchpad `f04-fix3-check.log`.

  | Step | Result |
  |---|---|
  | 0–2: tools, format, lint (`--strict`), package graph | OK: 0 of 207 files need formatting; lint is clean; the graph matches |
  | 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed.** xcresult: 679 tests, 678 passed, **0 failed**, 1 skipped |
  | 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed.** xcresult: 670 tests, 669 passed, **0 failed**, 1 skipped |
  | 5: coverage gate | Not yet wired (F01); read by hand below |

  The one skip on each platform is `ReplayPerformanceTests` ("Replaying 500 shuffled envelopes takes under
  5 ms"), `.slow`, nightly only.
- **Nightly settings on the host** (`LEDGER_TEST_LANE=nightly LEDGER_PROPERTY_SEED_COUNT=3000`): all 672
  domain tests pass, including the 5 ms replay budget and, at 3,000 seeds, the literal-host and HLC host
  properties, both `matchesReduce_*` effect properties, the fuzz, the garbage property and the oracle
  property. Log: scratchpad `f04-fix3-nightly.log`.

**Second gate, after the orchestrator's live-only addition** (2026-09-29):
- `scripts/check.sh --fast`: OK, 675 tests in 111 suites pass. Log: scratchpad `f04-fix3b-fast.log`.
- Nightly settings on the host (3,000 seeds): all 673 domain tests pass, the 5 ms replay budget included.
  Log: scratchpad `f04-fix3b-nightly.log`.
- Full `scripts/check.sh` through `sim-lock.py`, once: **green**, 202 s; the lock was free. Log: scratchpad
  `f04-fix3b-check.log`.

  | Step | Result |
  |---|---|
  | 0–2: tools, format, lint (`--strict`), package graph | OK: 0 of 207 files need formatting; lint is clean; the graph matches |
  | 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed.** xcresult: 680 tests, 679 passed, **0 failed**, 1 skipped |
  | 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed.** xcresult: 671 tests, 670 passed, **0 failed**, 1 skipped |
  | 5: coverage gate | Not yet wired (F01); read by hand below |

  The one skip on each platform is still `ReplayPerformanceTests` (`.slow`, nightly only).

### Coverage

Read from `xcrun xccov view --report --json .derivedData/Results/PR-{iOS,watchOS}.xcresult` of the second
gate, over `Sources/LedgerDomain/Engine/`. Identical on both platforms:

| File | Lines |
|---|---|
| `EventEnvelope.swift` | 54/54 |
| `WorkoutEngine.swift` | 46/46 |
| `WorkoutEngine+Replay.swift` | 57/57 |
| `WorkoutEngine+Reduce.swift` | 188/189. The miss is still the unreachable `default:` in `applyClockEvent` |
| **`Engine/` total** | **345/346 = 99.71 %** (brief: ≥ 95 %). The first gate read 343/344, before the live condition |

`Model/RestTimer.swift` is 17/17.

### Line counts

Measured from the merge base with `main` (`8404d02`; `main` has since moved on with F06, so a plain
`git diff main` would count F06's files as deletions) to the working tree, after the live-only addition.

- **Code only, `LedgerKit/Sources/LedgerDomain`: 392 lines changed** (387 added, 5 deleted). This is the
  product code; `LedgerTestSupport` (`EventBuilders` and the oracle, 465 code lines) counts as test code
  (orchestrator, 2026-09-29). All of `LedgerKit/Sources` together: 857. Measured by filtering
  `git diff 8404d02 -- <path>` to `+`/`-` lines whose trimmed text is neither blank nor starts with `//` (so
  `///` doc comments are excluded too). At `c696a4f` `LedgerDomain` was 393: this round changed 73 of its
  code lines (36 added, 37 deleted). Removing the window and the second predicate switch paid for the
  haptic, decision 4 and finding 21.
- **Plain `git diff --numstat 8404d02`:** `LedgerDomain` 694 + 10 = **704** (710 at `c696a4f`);
  `LedgerKit/Sources` 1,258 + 10 = 1,268; `LedgerKit/Tests` 7,504 + 1 = 7,505.
- **PR body:** 392 product code lines is under Pete's 500 target, so no split line is needed. The split
  considered earlier (fix round 2's A "event vocabulary + validation + store contract", B
  "reduce/replay/summary/effects") stays on record in "Product lines" above.

---

## Review should-fix round (2026-09-29)

Input: `review.md` (S1–S5, N1–N7) and `test-findings.md` "# Round 4" → "Out of scope, noted". F04 is frozen:
the one code change is S5, in a test. Everything else is in docs and briefs. No `LedgerDomain` source
changed, so the doc comments the review names in sources (`WorkoutEngine.swift`, `WorkoutEventStore.swift`,
`Effect.swift`, `EventEnvelope.swift`) are unchanged; each points to ADR-004's amendment, which now
carries the rules.

| Item | Change |
|---|---|
| S1 | ADR-004 "Recovery on launch" gains two rules. **Recovery skips only non-finite stamps:** `newest` is the largest *finite* stored `wallClock`, so a stored `+∞` cannot make every later own envelope malformed. **A drift bound acts only on receipt:** it may reject a received stamp before `append` (not stored, not seen by the clock), and never makes the host skip, clamp or restamp a stored envelope. The old "skip a stored stamp the drift bound would reject" is gone. The own-action bullet now points to the two rules, and the received bullet says "once past F17's receipt checks". F17 item 3 states the same two rules, and item 1 points to them. This is the orchestrator's fix, not the review's fallback (append and replay when a stamp sorts early): with the bound only on receipt, an own stamp always sorts after everything stored |
| S2 | **F05:** criterion 8 → `uncompactedWorkoutIDs()`; the `wall_clock` column is marked full precision; the test plan names the contract suite. New "Inputs from F04" covers: the shipped protocol (`append` returns the newly stored envelopes, all or nothing); no validation windows; running the contract suite, which must first move out of the `LedgerDomainTests` target; lossless dates; `.materialize(WorkoutState)` plus `summary`; a late discard that overtakes a finish; the renamed labels. It also carries the tester's round-4 note (a seconds-since-1970 store passes the contract), with "add a second stamp fixture to the read-back clause" left for F05 to decide. **F10:** the client comments (HLC stamp, launch step, `.materialize`); the effect names (`.persist`, `.transmit`, `.materialize`, `.discardLog`; no `.saveToHealth`); `exerciseSelected(exerciseIndex:setIndex:)` and `exerciseSwapped(exerciseIndex:exerciseID:name:alsoUpdateProgram:)`, with the two risks; criterion 7's `restExtended(amount:extendsShownRest:tappedAt:)`; criterion 12's launch step. The origin filter on haptics is dropped, because the engine decides which changes buzz, so `test_store_hapticOnlyForLocalOrigin` becomes `test_store_playsForwardedHaptics`. New "Inputs from F04" says F10 is the first host: HLC stamping and recovery, ADR-004's host loop, the effects, "+30s", the launch step, no windows, `alsoUpdateProgram` against `replaceSlotExercise` (F10 decides), and the cursor bounds-check (N7) |
| S3 | `docs/architecture.md` §6: the shipped `WorkoutEngine` and `Effect` signatures, and a pointer to `LedgerDomain/Engine` and the ADR amendment. Its actor bullet now names HLC stamping and the rebuild; its recovery bullet names the launch step. ADR-004: an "Illustrative" line under the sketch |
| S4 | F17 item 1: on `EngineError.conflictingEnvelope(key)`, append the batch one envelope at a time; drop the conflicting one and log it (`os.Logger`, no health values); keep the rest; rebuild once. A resent batch then cannot fail forever |
| S5 | `Round3HostAdversarialTests.partition`: `watch.outbox.shuffled(using: &generator)` with `SeededGenerator(seed: 144)`. A grep finds no other unseeded `shuffled()`, `randomElement()` or `random(in:)` under `Engine/` |
| Round 4, note 1 (F05, seconds since 1970) | F05 "Inputs from F04" item 4 |
| Round 4, note 2 (absurd HLC stamps) | F17 item 9 |
| Round 4, note 3 (a rebuild from nothing buzzes once) | F17 item 9. F17 owns the phone joining a live workout; F18 is the watch screens. Accepted under Pete's one-per-catch-up rule |

**Nits:**

| Nit | Outcome |
|---|---|
| N1 | Done. ADR-004 now reads "'+30s' on a screen that showed no rest never shortens a running rest", and states the `tappedAt + longestRest` cap on a shown rest |
| N2 | Done in the briefs: F05 inputs items 5 (re-materialisation lasts only until compaction) and 6 (a late discard deletes a materialised workout). `Effect.swift`'s doc is skipped: it is source, and F04 is frozen |
| N3 | Skipped. `EventEnvelope.swift:13` is a source doc comment, and F04 is frozen. ADR-004 and F17 item 1 already say that a received envelope is never reduced |
| N4 | Done. The "Rules → tests" table (rules 1, 9, 10, 12) and its "Also" list (`EffectsFromToTests`, `EnvelopeWellFormedTests`, the contract suite, the fuzz) are refreshed, and deviation 3's deleted test is marked |
| N5 | Skipped. It is code in `WorkoutEngine+Reduce.swift`, and the reviewer asks for no action while F04 is frozen |
| N6 | Skipped here. The PR body is written when the PR opens. Both figures and the ruling are in "Line counts" above: `LedgerDomain` 392, all of `Sources` 857, and `LedgerTestSupport` (465) ruled test code |
| N7 | Done through S2: F10 inputs item 8, which names F18 and F21 too. The `WorkoutState.cursor` doc is source, so it is unchanged |

### Gate

- **`scripts/check.sh --fast`** (host): OK. 689 tests in 116 suites pass, as in the tester's round 4, since
  S5 adds no test. Format (0 of 253 files) and lint `--strict` are clean. Log: scratchpad
  `f04-final-fast.log`.
- **Full `scripts/check.sh` through `sim-lock.py`, once** (2026-09-29): **green** (`check.sh OK`) in 256 s.
  Log: scratchpad `f04-final-check.log`.

  | Step | Result |
  |---|---|
  | 0–2: tools, format, lint (`--strict`), package graph | OK: 0 of 253 files need formatting; lint and the four lint-rule suites are clean; the graph matches |
  | 3: iOS `PR` plan (iPhone 17, 26.5) | **17 test targets ran and passed.** xcresult: 837 tests; 835 passed, **0 failed**, 2 skipped |
  | 4: watchOS `PR-Watch` plan (Apple Watch Series 11 46 mm, 26.5) | **8 test targets ran and passed.** xcresult: 814 tests; 812 passed, **0 failed**, 2 skipped |
  | 5: coverage gate | Not wired yet (F01) |

  - The two skips on each platform are the same as round 4's: `ReplayPerformanceTests` (`.slow`, nightly
    only), and F06's font-rendering test.
  - The seeded `reconnectBatch_buzzesOnce` passed on both simulators.
  - The totals equal the tester's round-4 gate, because no test was added or removed.
