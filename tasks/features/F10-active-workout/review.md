# F10 — review

## Slice S1 — review (G3 reviewer, 2026-10-04)

Reviewed: `git diff 92a63bd..c972f5d` in the worktree `F10-s1` (23 files, the committed slice only). The tester's
untracked files were not read. Paths are under `LedgerKit/` unless they start with `docs/` or `tasks/`.

### Verdict

**Changes requested: 1 Blocking, 4 Should fix, 7 Nits.**

The slice is careful work: the protocol is small, the fake is 111 lines with no re-entrancy, the contract reads
streams without a clock, and the scripts' model is separate from the fake. I found no crash, no data loss and no
flaky test. The one Blocking finding is an API decision that the shared contract pins the wrong way round, and it is
cheap to change today (about 25 lines) and expensive after S2 and S7 are written against it.

### Blocking

**B1. `finish(endedAt:)` and `discard(endedAt:)` at a date that is not finite do nothing and report success;
`finish` returns a workout that is still live.**
- Where: `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift:41-52` (the two doc comments say so),
  `Sources/LedgerFakes/FakeWorkoutSessionClient.swift:116-122`,
  `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract+Updates.swift:185-186` and `:189-197` (clause 16 pins
  it), `…Contract+Model.swift:45-48`, and the instruction to S2 at
  `tasks/features/F10-active-workout/implementation-notes.md:1102`.
- What is wrong: criterion 4 says `finish(endedAt:)` "returns the finished state" and that afterwards `current()` is
  nil, with no exception. As built, every caller of `finish` must check the phase of what it got back, and a caller
  of `discard`, which returns nothing, cannot tell that nothing was discarded without a second call. That is a
  swallowed failure (standards §8).
- Why it blocks: the behaviour is a clause of the contract S2's host must pass, and "Inputs for S2" tells the host
  to copy it. `StartWorkoutUseCase(replacingLive:)` (S2) would call `discard` and then get `workoutInProgress` from
  `start`, a misleading symptom; S7's receipt would need a phase check that the return type says is unnecessary.
  It cannot be reached through `@Dependency(\.date)` today, so there is no user-visible risk in this PR. The cost is
  in changing a shared contract after two more slices depend on it.
- Fix: see answer (a) below. One new error case, a two-line guard in the fake's `finish` and `discard`, the model's
  two arms, clause 16 split in two, a fault in `FaultyWorkoutSession`, the two doc comments, and line 1102 of the
  notes.

### Should fix

**SF1. The contract has no clause for a stream opened, or two starts made, while calls are in flight.**
- Where: `…Contract+Updates.swift:112-141` (clause 14 opens both subscribers before the task group and sends only
  `apply`); every other clause and every script subscribes and starts sequentially.
- Wrong hosts the contract accepts today:
  1. `updates()` reads the state, suspends (on recovery or the store), then registers. A subscriber that joins
     during an `apply` misses that update or gets it twice. The protocol promises the opposite
     (`WorkoutSessionClient.swift:15`, "registered before the call returns, so it misses no later update"), and
     "Inputs for S2" (notes `:1088-1089`) asks for it in words only.
  2. `start` suspends between "nothing is live" and the commit, so two starts at once both succeed. The plan's own
     invariant is that this cannot happen ("Two live logs cannot arise on one device, because `start` refuses").
- Fix: two clauses, both of which a correct host always passes.
  - "a stream opened while calls are in flight starts with a state the client published and carries every later
    update": start; open one subscriber; in a task group run the eighteen edits of clause 14 beside six
    `client.updates()` calls; mark; each late stream's first element has no effects and equals the state of update
    `k` of the first subscriber, and the rest equals updates `k+1…`.
  - "starts at once: one succeeds, the others throw `workoutInProgress` naming it": six `start` calls with six
    snapshots from a task group; exactly one returns, five throw naming the winner, `current()` is the winner and
    the stream holds one start.
- These are additive, so they may land with S2 if the orchestrator prefers; they belong here because the fake must
  pass them too.

**SF2. Eight of the seventeen clauses have no fault that shows they can fail, including the one that guards S2's
largest risk.**
- Where: `Tests/LedgerSyncTests/Support/FaultyWorkoutSession.swift:11-53`. The eleven faults name nine clauses
  (4, 5, 6, 7, 10, 11, 13, 15, 16). Clauses 1, 2, 3, 8, 9, 12, 14 and 17 have none, and the mutants in the notes are
  all on the synchronous fake, which cannot lose an edit between callers.
- Why it matters: clause 14 ("callers at once") is the only check on the re-entrancy the plan names first under
  "Risks". I believe it catches a host that suspends between reading and committing (all eighteen tasks would read
  the start state), but nothing in the tree shows it. Decision 11's own rule is "a new clause should come with a
  fault that breaks it".
- Fix: add at least `losesAnEditBetweenCallers` (an `await Task.yield()` between reading `live` and committing, for
  clause 14), `secondStartReplaces` (clause 3), `terminalThroughApplyStaysLive` (clause 8) and
  `cancellationEndsEveryStream` (clause 17), plus one fault per clause added under SF1 and B1.
- Also `FaultyWorkoutSession.swift:5-8` says it is "written from the protocol's documentation, not copied". It has
  the fake's shape line for line (a synchronous actor, the same `guard let next = reduced, !effects.isEmpty`, the
  same `live = next.phase == .live ? next : nil`), so "a second implementation the clauses accept" is weak evidence
  that the contract does not over-fit the fake. The real second implementation is S2's host. Soften the sentence.

**SF3. The protocol does not say that the ending update follows the save, and F09 needs exactly that.**
- Where: `WorkoutSessionClient.swift:41-42` and `:48-49`; notes `:1118-1123` (the snippet F09 S6 will copy).
- What is wrong: F09 criterion 3 wants Today to flip to "Logged" "within one stream update". Today's Logged card
  comes from history queries that are not live streams (`workoutsOn(dates:)`, F09 "Domain changes"), so Today must
  re-read history when the ending update arrives, and the workout must already be stored. The plan's host order
  does publish last, but the protocol does not promise it and the F09 guidance does not mention the reload: with
  `liveWorkout = update.live` alone, Today hides Resume and shows "Start workout" for a day that was just finished.
- Fix: one sentence on `finish` and `discard` ("the update is published once the workout is stored, or its log
  dropped, so a consumer may read history when it arrives"), a matching bullet in "Inputs for S2" with a host test,
  and in "Inputs for F09 S6": reload history when an update's `state` is not live, and use `update.state?.phase` to
  tell finished from discarded.

**SF4. `FakeWorkoutSessionClient.init`'s `device:` and `now:` are public parameters with no observable effect.**
- Where: `Sources/LedgerFakes/FakeWorkoutSessionClient.swift:35-39`, `:124-126`;
  `Tests/LedgerSyncTests/FakeWorkoutSessionClientTests.swift:83-105`.
- What is wrong: decision 7 says so itself ("no caller can see their effect"). I checked: nothing in
  `LedgerDomain/Engine` reads an envelope's `wallClock`, `device` or `seq` except the sort order and
  `isWellFormed`. A test author who passes `now:` will expect `elapsed`, `doneAt` or a rest to follow it, and none
  does. The one thing `now:` can do is harm: a clock that returns a date that is not finite makes `start` throw
  `notStartable` for a good snapshot and every `apply` return unchanged. The test that covers the pair pins the
  number of times a private clock is read (`ticks.count == 4`, line 104), which is implementation, not behaviour.
- Fix: drop both parameters and stamp with `Fixtures.deviceID` and `Fixtures.now`; delete
  `stamp_changesNothingObservable` and mutant M11. F09 and F18 have not called the initialiser yet, so this is free
  today. If the orchestrator wants the plan's signature kept, say in the parameter docs that neither changes
  anything a caller sees.

### Nits

- **N1.** `WorkoutSessionClient.swift:12-13`: "one update for every event the engine accepts" will be false once
  F17's host takes a peer's envelopes (a rebuild publishes once, and only when the state changed). Write "one update
  for each call whose event the engine accepts", and leave room: "a host may publish further updates for changes
  that do not come from this client's calls".
- **N2.** `Tests/LedgerSyncTests/WorkoutSessionClientContractTests.swift:74` and
  `WorkoutSessionClientContractFaultTests.swift:15`, `:32` take `seeds.prefix(20)`, but `seeds` has
  `LEDGER_PROPERTY_SEED_COUNT` elements. Confirmed: with the variable set to 1, `scripts_reachEveryCallAndRefusal`
  and `fault_isNoticedByAScript(startsThroughApply)` fail; with 5 they pass. Every test plan sets 200 or 2,000, so
  only a quick local run is hit. Give the three tests their own twenty fixed seeds.
- **N3.** `…Contract+Updates.swift:203-217` (clause 17) and `FakeWorkoutSessionClientTests.swift:126-138`: the
  `listening` stream is never finished, so a client whose stream ends at once, or has no first element, hangs the
  clause until the time limit instead of failing it. `defer { signal.finish() }` in the child task turns the first
  case into a normal complaint.
- **N4.** `Sources/LedgerDomain/Units/ClockText.swift:9`: `minutesSeconds` returns "1:01:05" from sixty minutes. The
  name is the brief's, and the format past an hour is with Pete. If "1:01:05" stands, rename it (`elapsed(_:)`)
  before Today, the header and the receipt call it.
- **N5.** `WorkoutSessionClient.swift:62-67`: `effects` is `[Effect]`, of which only `.haptic` can occur, and the
  public initialiser accepts any effect. The signature is the orchestrator's (O5) and `[Effect]` leaves room for a
  later kind of feedback, so I only note the cost: every consumer filters `if case .haptic`, and only the contract
  stops a host that forwards `.persist`. `[Haptic]` would make the rule a type.
- **N6.** `…Contract+Scripts.swift:219-233`: `ScriptGenerator` is the same SplitMix64 as
  `Sources/LedgerFakes/FakeLinkBus.swift:187`, which `LedgerTestSupport` already links, and testing-strategy §3
  rule 5 names one `SeededGenerator`. Make one of them the shared one.
- **N7.** `FakeWorkoutSessionClientTests.swift:3`, `:107-170`: three tests read the internal `subscriberCount`
  through the first `@testable import LedgerFakes` in the repo. They are honest about why (mutants M1 and M2 have no
  behaviour a caller can see), but they test bookkeeping. They go away if answer (e) is taken for the fake as well.

### Answers to the orchestrator's questions

**(a) `finish` and `discard` at a date that is not finite: throw.** The orchestrator's leaning is right.
- A method documented to return the finished state should have that as a postcondition, and `discard` has no return
  value to inspect at all.
- Keep `apply` as it is. `apply(.finished(endedAt: never))` still returns the workout as it stands and publishes
  nothing: `apply`'s rule ("an event the engine ignores changes nothing") is the same for every event, and
  `finish` and `discard` add a postcondition on top. One path stays one path: `finish` is `apply`, then "still live?
  throw".
- The case: `WorkoutSessionError.invalidEndDate`, with no payload (a `Date` payload breaks `Equatable` for NaN, and
  the caller already knows the workout). The guard should test the outcome (the returned state is still live), not
  the date, so that the engine's rule is not written a second time.
- The clause, replacing the last third of clause 16: **"finish and discard at a date the engine ignores throw
  `invalidEndDate`, end nothing and publish nothing"**: start; subscribe; `finish(endedAt: never)` and
  `discard(endedAt: never)` each throw `.invalidEndDate`; `current()` is still the workout; after the mark the
  stream holds the first element only. Clause 16 keeps `.finished(endedAt: never)` and `.discarded(endedAt: never)`
  through `apply` as ignored events.

**(b) The publishing rule holds, for a client's own calls.**
- Against ADR-004: `reduce` returns `.persist` exactly when it accepts an envelope, also when the state is
  unchanged ("belongs in every log"), and nothing at all when it ignores one. "One update per accepted call" is
  therefore the same test as "entered the log", it gives each `apply` exactly one update (criterion 3), and it
  carries the haptic of a set logged twice, which "publish when the state changed" would drop.
- The cost is a rare update equal to the one before it (a duplicate `setAdded`, an un-log of an undone set). A store
  that assigns an equal state re-renders once. Acceptable.
- Against F17: it does not extend to received envelopes, and should not. `effects(from:to:)` returns nothing when a
  rebuild changes nothing (`WorkoutEngine+Replay.swift:37-39`), so the rule there is "publish when the rebuild
  changed the state", as open question 5 says. Two things to keep open now: the wording in N1, and
  `WorkoutSessionUpdate.state`'s "the one update that ends it" (`WorkoutSessionClient.swift:58-59`), because a late
  envelope that sorts before a `finished` changes the finished state and F17 may want to publish it again.

**(c) No nil update after the end: enough for both, with SF3.** The ending update carries the finished or discarded
state, which says more than nil would: a screen shows the receipt from it or dismisses, the watch's summary mode
(F18) reads `phase == .finished` from it, and a stream opened afterwards starts with nil. A trailing nil would only
add an element every consumer has to ignore. What is missing is not in the type: the promise that the update comes
after the save, and the line in F09's guidance (SF3). One case stays open for S2 to write onto the protocol: what
open streams see when the save fails.

**(d) Both decisions are right.**
- Snapshot before session: an argument that can never be started is refused the same way every time, whatever
  else is going on. Pinning the order costs S2 nothing (`reduce(nil, started)` before the live check).
- `apply(.started)` with nothing live throws `noLiveWorkout`, and a terminal event through `apply` ends the workout
  as `finish` and `discard` do: the alternative for the second is a fifth error case for a call nobody makes. With
  (a), the two spellings differ only for a date that is not finite, which is documented.

**(e) The `Mutex` does not fit §4's exception as written; S2 should prune when `yield` reports `.terminated`.**
- As written the exception is for "state that a system framework callback writes synchronously on the framework's
  own queue", ruled for `MirroringStartRegistrar` by name, and the paragraph ends "Product stores use actors".
  `onTermination` is called by the Swift runtime on whichever thread cancels the consumer or drops the stream,
  which can be the host's own executor. The reason behind the exception does apply (the actor can be reached only
  after the callback has returned); the letter does not. So option A is an extension of a standard, which G5 sends
  to Pete, not a ruling the orchestrator can make alone.
- Option B needs no ruling, no lock and no task. Its cost, measured (a standalone release build on the host,
  `f10s1-g3/measure/main.swift` in the scratch folder): **234 bytes per subscription that ended with nothing
  published since**; 100,000 dropped streams held 23 MB and one publication pruned all 100,000. A thousand visits to
  Today without a workout is 0.23 MB, freed at the next start.
- A fire-and-forget `Task` from `onTermination` is not forbidden outside stores by §4's letter, but it is the
  pattern the rule exists for, and it makes "forgotten" a race. Not recommended.
- If B is chosen, the fake should follow it: the `Mutex`, `dropEnded`, `subscriberCount` and three tests go (N7).
  If the orchestrator prefers the bounded version, take A to Pete as one line in §4 that names
  `AsyncStream.Continuation.onTermination`, and let the same line cover the fake: its `Mutex` is inside ADR-008's
  precedent (`ObservedState.swift:75-77`) but outside the purpose that exception names ("so that `observe…()`
  registers synchronously").

### The API from each consumer's side

- **Today (F09):** `updates()`, `update.live` and `ClockText` are all it needs. Missing guidance: SF3.
- **The workout store:** one `apply` per tap works. Haptics arrive only in the stream, and nothing on an update says
  whether it answers the store's own call, so the store should draw from the stream alone and use `apply`'s result
  only as the base for its next intent; drawing from both lets a late stream element put back an older state for a
  frame. That is S5's design, not a change here.
- **The host (S2):** nothing in the signatures blocks it. Three behaviours it must write onto the protocol when it
  has them: a failed append (throws, nothing changed, nothing published), a failed save at `finish` and its retry,
  and what `updates()`, which cannot throw, returns when recovery failed.
- **The watch (F18):** covered; its summary reads the ending update.
- **Public surface:** nothing is public that should not be, apart from SF4's two parameters.

### The fake, the contract, the scripts

- **Fake:** imports `Foundation`, `IssueReporting`, `LedgerDomain`, `Synchronization` only; the whole file is inside
  `#if DEBUG`, and `SessionKeys.swift` guards both the import and the preview value; no method suspends, so there is
  no re-entrancy; deterministic. `applied` lists every ask, refused ones too, which is what criterion 7 says.
  `init(live:)` on a snapshot the engine refuses reports an issue and holds nothing, as `InMemoryStores` does.
  Behaviour a host might not share: it accepts a start with the id of a workout that already ended (open
  question 4), and it never fails.
- **Clauses:** protocol only (`any WorkoutSessionClient`; the fake is not named in `LedgerTestSupport`).
  Over-constraint: none that hurts S2. I checked the one the notes left open by reading: `workout_exercise.exercise_id`
  has no foreign key (`Sources/LedgerPersistence/Migrations.swift:151`), weights are whole pounds and dates finite,
  so `materialize` should accept every workout the clauses and scripts finish. Under-constraint: SF1; also a host
  may publish anything after a clause's last change unseen (the reader stops at the mark), which I do not think is
  worth a clause.
- **Hangs:** a clause waits only when its last change never reaches a subscriber (a bounded stream that drops the
  newest, a live subscriber pruned), or in clause 17 (N3). The suite's one-minute limit turns both into a failure
  that names the clause. Without a clock there is no better way.
- **Model:** independent of the fake (it does not name it and has its own start, refusal and ending rules). It
  shares `WorkoutEngine.reduce`, "no effects means ignored" and `feedback(from:)` with the fake, by design; a wrong
  `feedback(from:)` is caught only by `WorkoutSessionUpdateTests`, as mutant M12 records.
- **Seeds:** fixed (`n × 7919 + 17`), 200 on a PR and 2,000 nightly, and a failure names its seed.
- **Unbounded streams:** right for a stream that carries haptics. The cost is one retained update per accepted
  event for a subscriber that stops reading without cancelling; a workout is a few hundred events, so well under
  1 MB. The real cost is that a stalled consumer is silent.
- **`ClockText`:** correct. Truncating division on `Int128` rounds a positive duration down and a negative one to
  zero before `max`; no value traps; digits come from `Int128.description`, so no locale is involved.
- **Key, stub, preview value:** the same pattern as the store keys (a computed preview value, the stub on
  `Unimplemented`, the test value left to the library). Architecture §13 is updated; §6 is S2's, as recorded.

### The seven review points

| # | Point | Result |
|---|---|---|
| 1 | Module boundaries | Pass. No new edge; `Package.swift` and the graph file are untouched. |
| 2 | Concurrency | Pass. Actor fake, a `Mutex<[Int]>` for ended ids only, no unstructured task, the clock injected. See (e) for the host. |
| 3 | Error handling | B1: two calls that do nothing and report success. Otherwise nothing is swallowed and there is no `try?`. |
| 4 | Design fidelity | Not applicable (no UI). `ClockText` past an hour is with Pete. |
| 5 | Accessibility | Not applicable. |
| 6 | Test quality | Pass with SF2, SF4, N2, N3, N7. No sleeps, no wall clock, every async suite has a time limit, names follow §6. |
| 7 | Brief compliance | Each of the eight criteria has a test. Criterion 4 is not met for a date that is not finite (B1). The second half of criterion 5 cannot be tested before S2, as the notes say. |

Also checked: nothing of S2 is in the tree; the three files outside the slice's list have a recorded reason
(decision 14); no lint suppression was added; nothing reads as compressed, and comments are full (the notes count
93 product lines against an estimate of 115; I did not recount).

### The fifteen decisions

| # | Decision | Reading |
|---|---|---|
| 1 | Publish exactly when an event enters the log | Agree (answer b). Its stated consequence for `finish` and `discard` is B1. |
| 2 | `start` judges the snapshot first | Agree. |
| 3 | `apply` never starts; a terminal event through `apply` ends the workout | Agree. |
| 4 | No update after the ending one | Agree, with SF3. |
| 5 | The contract uses the protocol only and waits on no clock | Agree. Gaps: SF1. |
| 6 | Ended subscribers noted in a `Mutex` | Works and is tested. More than a fake needs; see (e). |
| 7 | The stamp is deterministic and unobservable | Agree with the stamp, disagree with keeping the two parameters (SF4). |
| 8 | `applied` lists every ask | Agree; it is the criterion's wording. |
| 9 | `init(live:)` runs the engine and reports an issue | Agree. |
| 10 | A model and seeded scripts in the contract | Agree. The strongest part of the slice. |
| 11 | `FaultyWorkoutSession` | Agree with the idea; coverage is nine clauses of seventeen (SF2). |
| 12 | `ClockText` counts in `Int128` | Agree. |
| 13 | The preview value is computed | Agree. |
| 14 | Files outside the list | Reasons recorded and sound. |
| 15 | `finish`'s retry sentence and architecture §6 left to S2 | Agree. Add the two other sentences S2 owes (see "The host" above). |

### The `/code-review` pass

Run through the Skill tool at effort `high` on the range. It reported nine items and no crash or data-loss bug.
Kept: the seed prefix (N2, which I then confirmed by running), the SplitMix64 copy (N6), the `minutesSeconds` name
(N4), the clock that is not finite (in SF4). Not kept, with reasons: the fake never finishing its streams when it is
deallocated (the protocol says a stream ends only when its consumer stops); the reader stopping at the mark (covered
above); "ignored" inferred from empty effects (it is the engine's documented result); the rules written three times
(that is the point of an independent model and a faulty twin); a `Tag.property` per test target (the repo's existing
pattern).

### What I ran

- `swift test --filter 'WorkoutSessionClientContract|FakeWorkoutSessionClientTests'` on the committed tree, before
  the tester's files appeared: 15 tests in 3 suites passed (17 clauses, 200 seeds, 11 faults) in 0.34 s.
- The same with `LEDGER_PROPERTY_SEED_COUNT=1` (two failures, N2) and `=5` (passes).
- The notes' step-1 filter, by which time the tester's files were in the tree: `LedgerDependenciesTests` 54 passed.
  I do not count the `LedgerSyncTests` part of that run, because it included files I was told not to read.
- A standalone measurement of option B's cost (answer e), outside the repo.

### What I did not check

- The Release build and the symbol check: read the `#if DEBUG` guards only.
- Anything on a simulator, and the full gate (the orchestrator's: exit 0).
- The mutants' log and the coverage numbers in the notes.
- That clause 14 catches a re-entrant host, and that the clauses proposed under SF1 pass on the fake: I may not add
  test files, so both are argued, not run. A fault with `await Task.yield()` settles the first.
- `materialize` against the scripts' workouts: read the schema and the in-memory store, did not run it.
- Recovery, the stamp, storage and every effect the host runs: S2's.
- The tester's files and `test-findings.md`.

### Housekeeping (not part of the diff)

A test helper from the implementer's mutant run is still alive: pid 5917, `swiftpm-testing-helper … LedgerDependenciesTests`,
started 17:54:27, parent 1, idle. It predates the gate and looks like mutant M6's hung run. I left it alone.
