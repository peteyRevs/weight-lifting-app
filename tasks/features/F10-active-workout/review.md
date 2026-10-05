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

## Slice S1 — re-review of fix round 1 (G3 reviewer, 2026-10-04)

Scoped: `git diff 0950170..9ad8fc6` against my findings above, the tester's round 1 and the orchestrator's three sets
of rulings. Not a fresh full review. Files were read as committed (`git show 9ad8fc6:…`); the tester's uncommitted
work was not read.

### Verdict

**Approve: 0 Blocking, 2 Should fix, 3 Nits.** B1, SF1 to SF4 and N1 to N7 are all closed. The two Should-fix items
are new and small: one makes two of the new overlap clauses bite by construction instead of by the scheduler's
choice, the other writes a ruling where the next lane will read it. Neither changes the API, so both can ride with
S2's first commit if the orchestrator prefers.

### Status of the first review's findings

| Item | Status | Evidence |
|---|---|---|
| B1 | **Closed** | `WorkoutSessionError.invalidEndDate`, no payload (`Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift:110-112`). The fake's guard tests the outcome (`FakeWorkoutSessionClient.swift:82-95`, `finished.phase != .live`), as does the model (`…Contract+Model.swift:105-112`). Clause 8 is the split clause (`+Lifecycle.swift:179-196`); clause 16 keeps both terminal events at a date that is not finite as ignored events through `apply` (`+Updates.swift:134-140`); clause 5 pins `noLiveWorkout` first when nothing is live (`+Lifecycle.swift:114-116`). Docs on `apply`, `finish`, `discard` and the case agree. "Inputs for S2" says to test the outcome (notes `:1113-1116`) |
| SF1, F10-S1-3, F10-S1-4 | **Closed**, see R1 | The history walk and four clauses (`+Overlap.swift`). No over-constraint and no hang found (below) |
| SF2 | **Closed** | 26 faults, at least one per clause, the re-entrancy one among them (`FaultyWorkoutSession.swift:101-103`, `:181-185`) |
| SF3 | **Closed** | `WorkoutSessionClient.swift:47-48`, `:57-58`; the host test is in "Inputs for S2" (notes `:1117-1122`); F09's input reloads history and reads `state?.phase` (`:1150-1168`) |
| SF4 | **Closed** | `init(live:)` only (`FakeWorkoutSessionClient.swift:27`); the stamp is fixed (`:97-105`); the clock-read test is gone |
| N1 | Closed | `WorkoutSessionClient.swift:13-15` |
| N2 | Closed | `fixedSeeds`; I ran the suites with `LEDGER_PROPERTY_SEED_COUNT=1`: 14 tests pass |
| N3 | Closed | `+Updates.swift:171-173`. A client with no first element still waits for the time limit, as documented |
| N4 | Closed | `ClockText.elapsed(_:)` |
| N5 | Closed, as a type | `haptics: [Haptic]` reaches the protocol, the fake, the contract, the model, every test and the brief. One stale comment (N-c) |
| N6 | Closed, cost accepted | One generator; see N-b for its home |
| N7 | Closed | No lock, no `onTermination`, no `@testable import LedgerFakes`. The one remaining test is behavioural (`FakeWorkoutSessionClientTests.swift:120-150`) |

### The six checks

1. **B1: closed.** Nothing about the case is wrong. For the consumers: S7's finish flow gets a throw and a workout
   that is still live and unpublished, which is exactly what the cover shows. The watch is the same. For "Discard
   and start new", `invalidEndDate` now stops before `start`, which is right. One thing for S2 to write, not a
   finding here: when `discard` throws `noLiveWorkout` because the workout ended in between (the watch finished it),
   `StartWorkoutUseCase(replacingLive:)` should go on to `start`, not fail. The cause-named case with an
   outcome-tested guard is safe only because the host checks its own stamp before `reduce`, which "Inputs for S2"
   already says (notes `:1128-1130`).
2. **Overlap clauses: closed, with R1.**
   - *Can a correct host fail them?* No. Each judges the outcome as a set (one winner, the rest refused; a history
     in which every update follows from the one before by an event not yet seen), every fixture event is distinct
     and changes the state, and nothing depends on which call wins. The fake passed 30 of 30 runs here at a load
     average of 14, and 12 of 12 on a one-thread pool.
   - *Can any hang?* Not for the faults listed: every stream is registered before the mark is made. A host that
     registers a stream after returning it can miss the mark and wait for the time limit, as before.
   - *Can a racy host pass most of the time?* For clauses 18, 19 and 20, no: each call is its own task, all are
     queued before the first one's suspension ends, and their faults showed even on a one-thread pool. For clauses
     21 and 22, yes under the wrong conditions: R1.
   - *Is 80 of 80 good enough?* For this slice, yes: the gate is green and the contract says plainly that one green
     run is weak evidence. It is a statement about a ten-core host, though, and R1 is the cheap way to stop
     depending on it.
3. **SF2: closed.** `everyClause_hasAFault` is a real check of the table: every clause name is claimed by a fault,
   and every fault's prefix matches exactly one clause, so a new clause without a fault, or a renamed one, fails
   it. It does not show that a fault bites; `fault_breaksItsClause` does, for each of the 26. Together they prove
   what SF2 asked for.
4. **SF3, SF4, N1 to N7: as ruled** (table above). N6 is acceptable; a cleaner home is N-b.
5. **New code.**
   - The fake: 90 lines, no suspension, so no re-entrancy; ended streams are held until the next publication and
     no longer, which is the measured 234 bytes each. Nothing a host could not do, apart from accepting a start
     under an ended workout's id (open question 4, S2's). One nit on `publish` (N-a).
   - `+Overlap.swift` and `FaultyWorkoutSession+Fault.swift`: sound; R1 on two loops.
   - Standards: no unstructured task, no sleep, no lock; every async suite has its time limit; names follow §6.
     `Task.yield()` appears once, inside the faulty stand-in, which is where it belongs.
6. **Stale or broken:** R2 and N-c. Architecture §13 needed no change. "The one update that ends it"
   (`WorkoutSessionClient.swift:69-70`, the brief `:190`) was left as it was; `updates()` now says a host may
   publish further updates, which is room enough, and F17 rewrites the sentence when it has a case. The tester's own
   stale names (`minutesSeconds_…`, "four cases") are the tester's close-out.

### New findings

**Should fix**

**R1. Clauses 21 and 22 overlap their calls only when a second thread happens to run.**
- Where: `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract+Overlap.swift:170-172` (six tasks, each
  making twelve `apply` calls in a row, beside one `finish`) and `:228-230` (one task making sixty `apply` calls in
  a row, beside eight `updates()` calls); the test that allows ten tries,
  `Tests/LedgerSyncTests/WorkoutSessionClientContractFaultTests.swift:35-44`.
- What is wrong: a task that makes its calls in a row never gives way between them, because an uncontended hop to
  an actor does not suspend. Whether the other tasks get in is then up to real parallelism. In clauses 18 to 20
  every call is a task of its own, so they do not have this shape.
- Evidence:
  - Default pool: the three suites passed 30 of 30 runs.
  - Cooperative pool narrowed to one thread (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`): 12 of 12 runs failed, each
    time on exactly `appliesAfterTheEnd` and `registersAfterASuspension`, so neither showed in 120 tries. The other
    three overlap faults and every test on a correct client passed.
  - A standalone model of the two shapes (`f10s1-g3/overlap/main.swift` in the scratch folder, 200 runs each): as
    written, the faults showed in 76 and 23 runs on the default pool and in 0 and 0 on one thread. With
    `await Task.yield()` after each of the clause's own calls: 200 and 200, on both pools. The model's calls are
    cheaper than the engine's, so its default-pool rates are lower than the real clauses' 80 of 80.
- Why it matters: nobody runs the gate on one thread, but a starved CI runner is the same thing for a millisecond,
  and these two clauses are the ones that hold S2's `updates()` and its end path to "one call at a time".
  Standards §9 also says retries are not a fix, and the ten tries are one.
- Fix:
  1. `await Task.yield()` after each call in the two loops (two lines). A correct client still passes whatever the
     scheduler does; I did not run this in the real contract, because I may not edit it.
  2. In "Inputs for S2": run the contract on the host over stores whose every method yields first (a ten-line
     wrapper in test support). A host's own suspension is an actor hop, which lets nobody in when the store is
     idle; the wrapper makes each `await` on a store a real one, for all five overlap clauses.
  3. Once 1 is in, try `fault_breaksItsClause` with one try for the overlap faults and keep the ten only if a fault
     needs them.

**R2. The ruling "exactly one subscriber plays haptics, on the workout side" is not written where F09 and F18 will
read it.**
- Where: `tasks/features/F10-active-workout/implementation-notes.md:1169-1172` ("Inputs for F09 S6" still says
  "Feedback: play `update.haptics`, as given and in order", with two cautions); the ruling is 290 lines below
  (`:1459-1461`). `Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift:66-67` and `:72-73` say "what the
  screen should play".
- Why it matters: every subscriber gets every update, Today stays subscribed under the cover, and the bullet
  tells Today to play. `HapticsClient` has no `play` until F10 S6, so nothing buzzes twice today.
- Fix: replace the bullet with "Today reads `state` only and never plays `update.haptics` (ruling after fix
  round 1)", and add to the `haptics` doc: "Every subscriber receives them; exactly one, on the workout side, plays
  them."

**Nits**

- **N-a.** `Sources/LedgerFakes/FakeWorkoutSessionClient.swift:113-119`: the publishing is done by the predicate of
  `removeAll`. It is correct today (the standard library calls the predicate once per element, in order), but that
  is not promised, and "Inputs for S2" tells the host to forget streams "as the fake does" (notes `:1124-1125`).
  Write the loop: yield to each, keep the ones that did not answer `.terminated`.
- **N-b.** `Sources/LedgerFakes/FakeLinkBus.swift:186-203`: `SplitMix64` is now the shared generator but lives in the
  link bus's file. Move it to `LedgerFakes/Support/SplitMix64.swift`. Keeping it in `LedgerFakes` is right: it is
  the only module both users can reach, and the `#if DEBUG` around the scripts is the price.
- **N-c.** Stale text. `tasks/features/F10-active-workout.md:199` still says "current state first (no effects)".
  The plan's "What F09 gets from S1" (notes `:75-126`) still shows `effects`, `feedback(from:)`,
  `ClockText.minutesSeconds` and the fake's `device:` and `now:`; add one line at its top pointing to the brief's
  revised amendments and "Inputs for F09 S6".

### What I ran

- `swift test --filter 'WorkoutSessionClientContract|FakeWorkoutSessionClientTests'` on the host: 14 tests in 3
  suites pass (22 clauses, 200 seeds, 26 faults). Then the same 30 times with `--skip-build`: 30 green.
- The same 12 times with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`: 12 red, as under R1.
- The same with `LEDGER_PROPERTY_SEED_COUNT=1`: green.
- The standalone model under R1. No helper process is left running, and pid 5917 from the first review is gone.

### What I did not check

- The Release build, the simulators, the full gate (the orchestrator's on `9ad8fc6`: exit 0) and the round's mutants.
- R1's fix in the real contract: modelled, not run.
- The tester's files. I skimmed the three committed edits the notes call more than mechanical and left the audit to
  the tester. The tester was editing six of its files while I worked, so the binary I ran may hold its uncommitted
  edits; the three suites I ran are the implementer's. I did not run the tester's racy tests on one thread; they
  lean on the same two clauses.
- The host against the new clauses, recovery, storage, and a save that fails: S2's.

## Slice S2 — review (G3 reviewer, 2026-10-05)

Reviewed: `git diff 48403f5..3c960e8` in the worktree `F10-s2` (33 files, the committed slice only). The tester's
untracked files (`Tests/LedgerSyncTests/Adversarial/Host…`) appeared while I worked and were not read. Paths are
under `LedgerKit/` unless they start with `docs/` or `tasks/`. `Actor` is
`Sources/LedgerSync/LocalWorkoutSessionActor.swift`, `Recovery` its `+Recovery.swift`, `Protocol`
`Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift`, `UseCase`
`Sources/LedgerDomain/UseCases/StartWorkoutUseCase.swift`.

### Verdict

**Approved: 0 Blocking, 5 Should fix, 10 Nits.**

I found no way to lose, duplicate or corrupt a workout through the committed code over the GRDB stores, with or
without one store call failing. The queue is correct, memory changes only after the store has taken the envelope, an
end is complete only when its log is gone, and recovery is one pass that can be run again at any point.

The weak part is what a failed save leaves behind (decision 3). The behaviour is safe, but the protocol's
documentation promises more than the host does (SF1), and three consequences that S4, S7 and F09 will meet are
written nowhere (SF2). Two questions in it are not the implementer's to answer and are listed under "For the
orchestrator and the product owner".

### Blocking

None.

### Should fix

**SF1. The protocol's documentation promises two things the host does not do.**
- Where: `Protocol:13-16` (the type), `:29-30` (`current`), `:65-71` (`finish`); `docs/architecture.md:289-291`;
  `Actor:15-19`.
- What is wrong:
  1. "A call that throws changes nothing a reader can see: no update is published" (`Protocol:13-14`). An `apply`
     or a `discard` made while a finish waits completes that finish first, publishes the ending update, and then
     throws `noLiveWorkout` (`Actor:186-189`). `LocalWorkoutSessionActorEndTests.pendingEnd_isCompletedBeforeAnyChange`
     (`:143-151`) asserts exactly that. After an append that threw, the next call, a `current()` included, may
     publish the state it finds stored (`Recovery:97-100`) and then throw.
  2. "no second workout can be started over one that is not yet in history" (`Protocol:67-68`), "still the one
     workout there may be, until the host has completed its end" (`:15-16`), "so nothing can be started over it"
     (architecture `:290`). This holds only until the process ends. After a relaunch nothing is live while the save
     keeps failing, and `start` succeeds: `LocalWorkoutSessionActorRecoveryTests.unsavedWorkout_afterARelaunch_leavesNothingLive`,
     and decision 3's own caveat.
  3. `current()` is "the state of the last update" (`Protocol:29`). After an end, the last update's state is the
     finished workout and `current()` is nil. It is the last update's `live`.
  4. `Actor:17-18`, "a call that throws leaves all of them as they were": a finish whose save fails has stored its
     envelope, so the clock and `seq` have advanced, as the notes' failure table says.
- Why it matters: criterion 4 makes this documentation the deliverable, and S4, S7 and F09 S6 are written from it.
- Fix: wording only.
  - The type: "A call that throws stores and publishes nothing of its own. Two things can still reach readers while
    it runs: an end that was waiting, which the call completes first, and, after a write that failed, the state the
    host finds in its store."
  - `finish`: add "in this process: after a relaunch the unsaved workout is no longer shown, another can be started,
    and the launch step saves the first when it can."
  - `current`: "the `live` of the last update".

**SF2. What a waiting end means for callers is not written down, and one case has no exit.**
- Where: `Actor:170-172`, `:186`, `:215-220`; `Recovery:113-115`, `:124-130`; `UseCase:83-97`; the notes' "Inputs
  for S3 and S4, and for F09 S6".
- What is wrong: between a failed save and its completion `current()` returns a state whose phase is `.live`, and
  nothing tells a reader that the end is stored. Three consequences follow from the code, and none is on the
  protocol or in the inputs:
  1. `discard` saves the workout. It completes the waiting finish and throws `noLiveWorkout`. A lifter who answers
     a failed save with "Discard" gets the workout in history.
  2. `StartWorkoutUseCase` treats it as an ordinary live workout. For the same day it returns `.resumed`, and the
     cover opens a workout that accepts no change. For another day it returns `.conflict`; then
     `start(_:replacingLive: true)` either saves the old workout, throws `noLiveWorkout` and starts nothing (the
     notes mention the throw, not the save), or throws the store's error and starts nothing.
  3. A save that can never succeed leaves no exit in this process. `finish`, `apply` and `discard` all go through
     `settle()` and rethrow the store's error; `start` answers `workoutInProgress`; every return to the foreground
     runs the failing step again and logs a fault. Only a relaunch frees the slot. The same holds for a waiting end
     whose log gains unreadable rows (`Recovery:113-115` returns without clearing `ending`), which needs a peer.
- Why it is not Blocking: nothing is lost (the log is kept and a later pass saves it), and M1's inputs cannot make a
  save fail for good. Child ids are derived from the workout's id (`SessionBuilder`), and a name holding U+0000 is
  refused when the program or exercise is saved. That leaves a full or locked disk, which passes.
- One caution for S4: the Debug "Start sample workout" row (O15) must make a new workout id for each start. With a
  fixed fixture id the second finish throws `duplicateIdentifier` every time, which is case 3.
- Fix: add 1 to 3 to `finish`'s doc and to the notes' inputs for S4, S7 and F09. The two rulings are below.

**SF3. A test polls.**
- Where: `Tests/LedgerAppKitTests/WorkoutSessionWiringTests.swift:162-165`.
- What is wrong: `for _ in 0 ..< 1000 where Self.began(harness) < 2 { await Task.yield() }`, then
  `#expect(Self.began(harness) == 2)`. Testing-strategy §3 rule 2 says no polling. Between the caller's start and the
  second "began" there is a hop to the session actor (`needsRecovery`) on the cooperative pool, while the loop spins
  on the main actor. If the pool is slow to serve the hop, the loop runs out and the expectation fails.
- It did not fail in my nine runs (six on one thread), so this is a flakiness vector, not a flaky test.
- Fix: let the harness's `record` feed an `AsyncStream<LaunchEvent>` and await the second
  `.began(.resumeWorkout)`, as `DatabaseLaunchStepTests.run_cancelledCaller_neverCancelsTheStep` does with its
  `began` stream (`Tests/LedgerPersistenceTests/DatabaseLaunchStepTests.swift:44-57`).
- The other yield loops (`LocalWorkoutSessionActorSerialTests.swift:26`, `:102`, `:123`;
  `DatabaseLaunchStepTests.swift:61`) gate no expectation: each test passes whether or not the other callers arrived,
  and only bites harder when they did. They can stay.

**SF4. Criterion 11's judge accepts a refusal whenever it was thrown.**
- Where: `Sources/LedgerTestSupport/Engine/WorkoutSessionClientContract+ConcurrentHistory.swift:17`, `:33-36`;
  `…+ConcurrentScripts.swift:198-236`; `Tests/LedgerSyncTests/WorkoutSessionConcurrentScriptTests.swift:64-75`.
- What is wrong:
  1. A call that published nothing passes when the rules allow its outcome at any point of the history. The history
     always begins with "no workout" (`:17`). So an `apply`, `finish` or `discard` that throws `noLiveWorkout`
     passes whenever it was thrown, and so does a `workoutInProgress` naming any workout that was ever live. A host
     that refuses an edit under overlap, while the workout is live the whole time, passes every script. No fault in
     `FaultyWorkoutSession` does this, so nothing shows the gap.
  2. The weakest fault, `judgesAnIgnoredEndLater`, is reported by 6 of 20 seeds (8 on one thread), and
     `overlapFault_breaksAScript` asks for one. Which seeds report it is the scheduler's choice. An ignored end is
     5 % of the actions, so about one script in six holds none, and one that holds it need not have a real end in
     flight beside it.
- Why it matters: criterion 11 says "every refusal is one the protocol allows for that call", and the commonest
  refusal is never judged. The host passes for the right reason today, but this script is what F17 will lean on
  when it adds operations to the queue.
- Is 6 of 20 enough? For the criterion's last clause ("a fault shows it can fail"), yes, and the test passed in all
  eleven of my runs. As a guard it rests on scheduling, and it can be made firm cheaply.
- Fix, about twenty lines in the judge and the writer:
  - Give `Call` its task and its position. A task's calls are sequential, so a refusal or an ignored call must be
    allowed at a state between the update of that task's previous published call and that of its next one. The
    opening call is judged against the first state only.
  - Add a fault that refuses an `apply` while another call is inside the client.
  - Write every script with an ignored end and a real end at the same position of two tasks, then ask
    `overlapFault_breaksAScript` for more than one seed.

**SF5. A saved workout whose log could not be dropped is in history and still live (decision 4). For S3, not this
PR.**
- Where: `Recovery:146-149`.
- What is wrong: `materialize` and `compact` are two transactions on one database. When the second throws, the
  workout is in History and is also what `current()` returns, `finish` has thrown, and every retry and every launch
  materialises it again from the log. F17's "Inputs from F05 (slice S3)" names the hazard: a late materialise brings
  back a workout deleted in History and overwrites `updateSets` edits.
- Why it is not Blocking: it needs a delete to fail right after a commit, and it bites only once History can edit
  or delete (F13). I agree with the notes' one rule ("an end is complete when its log is gone") over the
  alternative in open question 3.
- Fix: S3 already changes `materialize`'s transaction. Let it drop the workout's log in the same transaction (a
  parameter on `materialize`, a contract clause, the fake following). Then "saved, not compacted" cannot exist over
  GRDB, `finish` no longer throws for a workout that is in history, and recovery's fourth row is left for stores
  that are not one database.

### Nits

- **N1.** `Actor:170-172`, `:216-221`: after an append that stored and then threw, the retry answers as a failure.
  `finish` completes the end inside `ready()`, publishes it, and throws `noLiveWorkout`; `start` adopts its own
  workout and throws `workoutInProgress` naming it. GRDB rolls back on a throw, so this needs a store that lies. Say
  it in `finish`'s doc, or return the ended state when `ready()` has just completed this workout's end.
- **N2.** `Actor:249` discards `append`'s result. For an own envelope, "already stored" (an empty result) can only
  mean that memory is behind the store. Mark the host unrecovered and throw. Three lines.
- **N3.** `Recovery:85-91`: when memory holds a live workout and the store has no log that replays to it (damage:
  its `started` row unreadable), the pass ends "recovered" with the stale workout, and later events go to a log that
  replays to nothing. Log a fault there at least.
- **N4.** `Sources/LedgerPersistence/DatabaseLaunch.swift:129`: `run` takes any `LaunchStep` and shares `running` and
  `ended` with the launch's own steps. `run(.seedCatalog, …)` would return the seed's task, or nothing, and never
  run its body. A precondition, or one sentence in the doc.
- **N5.** `Actor:114`: "No operation may call a method that queues" is a comment. Breaking it stops the host for
  good, silently: the operation waits for one queued behind it. F17 adds operations. A task-local set while an
  operation runs, asserted at the top of `inTurn`, turns that into a test failure.
- **N6.** The 30 ms budget is inline (`Tests/LedgerSyncTests/LocalWorkoutSessionActorPerformanceTests.swift:20`;
  testing-strategy §2.2 wants budgets in a `PerformanceBudget.swift`, though `ReplayPerformanceTests` is inline too),
  and criterion 12 and the suite cite architecture §15, whose table has no such row. Add the row.
- **N7.** The plan asked for the start latency to be measured in S2 (notes `:416-418`, budget 200 ms). The S2 notes
  hold no figure and do not list it under "Not verified". `UseCase:105-108` makes up to sixteen reads one after
  another. Measure once on the 20,000-set seed before S4 decides on the cover's loading state.
- **N8.** `UseCase:94`: `discard(endedAt:)` names no workout (S1's protocol), so the use case discards whatever is
  live at that moment, not the workout `current()` returned at `:83` and the lifter agreed to replace. It needs an
  end and a start by another caller in between, which one phone in M1 cannot produce. A peer can: an input for F17.
- **N9.** Decision 15: the host completes an end from the state's phase, not from `.materialize` or `.discardLog`.
  Nothing pins that the two agree. One property over the engine (an accepted terminal event's effects hold
  `.materialize(state)` or `.discardLog`, and no other event's do) before S6 adds effects.
- **N10.** Time limits under contention. On the host the parameterised cases starve the single tests:
  `endedStreams_disturbNoOne` took 16 s, `noFault_isOneHistory` 18 s and two serial tests 9 s, of a 19 s run (load
  average 7 to 10), against `.timeLimit(.minutes(1))`. That is a margin of three on this Mac and unknown on a CI
  simulator. The first CI run's times for these four settle it.

### Re-entrancy (decisions 1 and 2): sound

- **No interleaving, arrival order.** `inTurn` (`Actor:116-124`) takes its place before its first suspension: `start`,
  `apply`, `finish`, `discard`, `resumeFromStore` and `recovered` reach it with no hop. Each task awaits the one
  before, then runs. "Arrival" is the order the calls reach the actor, which is all the protocol promises.
- **No deadlock, no starvation.** An operation waits for one earlier task and for the stores. None of `begin`,
  `perform`, `end`, `recover`, `ready`, `settle`, `complete` calls `inTurn` (checked by reading; see N5). A waiter
  raises the priority of the task it awaits, so a low-priority operation does not hold a high-priority one back
  longer than its own work.
- **No unbounded growth.** The chain holds the last task only: a finished task releases its closure, and with it
  the task before. I ran the queue copied into a standalone program: 1.6 million operations one after another left
  one result alive and resident memory flat; 2,000 callers at once, one in seven already cancelled, were all
  applied, once each, with no overlap, on both pools.
- **A store that never returns** stops the queue: every later call waits, one suspended task each, and nothing can
  cancel the owned task. `current()` and `updates()` still answer once recovery has run. That is what a held
  database lock does to any design; GRDB times out rather than hangs.
- **Cancellation is right.** The task is not the caller's, and `Task.value` does not end early when its awaiter is
  cancelled. So a cancelled caller's event is stored, and the caller still waits for, and gets, the true result.
  The notes say "only waits", which is accurate; the caller does not stop waiting.
- **The two rejected alternatives.** Both claims hold. A gate that leaves the work in the caller's task lets GRDB
  see the cancellation and refuse the write. `withTaskCancellationShield` is iOS 27.0 / watchOS 27.0 and later in
  Apple's documentation today; the minimum is 26.
- **Decision 2.** `live` is assigned in the same synchronous stretch as its `publish` at every site (`Actor:138-139`,
  `:174-175`, `:208-209`; `Recovery:98-99`). `current()` and `updates()` read `live` and register in one turn. So
  they see the last publication and never half of an operation. `ending`, `seq`, the clock and `isRecovered` do
  change between publications, and no reader sees them except through `needsRecovery`.
- **Standards §4.** The actor-owned `Task` fits §4 as written. The bullet forbids `Task.detached`, and a
  fire-and-forget `Task { }` in stores. This task is neither detached nor forgotten (its caller and its successor
  await it), and the host is not a store (§3). It follows F07 S2's binding decision that the launch owns its step
  tasks (`DatabaseLaunch.task(for:retrying:_:)`, on `main`), and the plan the orchestrator accepted names "a chain
  of tasks the actor owns". Criterion 10's "no unstructured task" is about subscribers and is kept. No waiver and
  no product-owner ruling is needed. §4 would be clearer with one sentence saying when an owner may hold a task;
  this is the second use.

### Failure (decisions 3, 4, 5): safe, with SF1, SF2 and SF5

The failure table against the code, row by row:

| Row | Result |
|---|---|
| append refused | Matches. Nothing is committed (`Actor:173-174`, `:200-201`), `persist` marks the host unrecovered. |
| append stored, then threw | Matches. The next call's pass adopts the log, publishes without a haptic, and completes an end. See N1 for what the retry answers. |
| clock not finite | Matches: `noFiniteStamp` before `reduce`, nothing stored. |
| `materialize` after `.finished` | Matches, including "clock and `seq` advanced". SF1 and SF2 are about this row. |
| `compact` after the save | Matches. SF5. |
| `compact` after `.discarded` | Matches. |
| a read during recovery | Matches but for "memory as before the pass": ended logs met before the failing read are already completed, the clock has observed, and `ending` may be set. Harmless, because the pass is idempotent. |
| a save during recovery | Matches: collected, the rest dealt with, thrown by the step and not by a protocol call. |

- **Decision 3** is a defensible contract for S7's finish flow: "Try again" is `finish`, and the retry keeps the
  first call's end date, so repeated attempts do not stretch the workout. For the conflict dialog and Today it works
  only if their authors know SF2's three consequences. The host behaves differently in the process (the slot is
  held) and after a relaunch (the slot is free), so holding the slot is a choice about the screen and not something
  safety needs. That is why I put the questions to the orchestrator and not to the implementer.
- One more consequence after a relaunch: a second workout of the same day and week can be finished before the
  unsaved one is saved. When the first is saved later, its miss for that week replaces the newer one on each slot
  (`MissTracking.update` sets the week from the workout it is given). Rare; it belongs with open question 2.
- **Decision 4:** acceptable for S2. SF5 removes its cost.
- **Decision 5:** right. Re-reading costs a few queries after a failure and makes a lying store harmless.

### Recovery (decision 6; criterion 6): matches the table

| Table row | Code |
|---|---|
| nothing stored | `Recovery:59`: no log, nothing done. |
| a live log | `:64-65`, `:95-100`: resumed, `seq` from the store, published only when it differs from what readers have, haptics `[]`. |
| finished, not materialised | `:69`, `:146-149`, with misses from the program as stored now (`:155-173`). |
| materialised, not compacted | The same path. `MissTracking.update` is idempotent, and `killedBeforeTheDrop_isSavedAgainUnchanged` compares six tables. |
| discarded, not compacted | `:149`. |
| replays to nothing | `:60-62`: kept, a notice. |
| unreadable rows | Live: resumed from what `envelopes(for:)` returns. Ended: kept (`:139-145`, `:113-115`), and no failure. |
| a save that throws | `:116-118`, `:78`, `:35-37`: the log kept, the other logs dealt with, the step throws, `needsRecovery` stays true. |

- Running it twice changes nothing, and a cancelled scene-phase task cancels neither the launch's task nor the
  queue's.
- **Published, and haptics:** two sites only, both with no haptics: `:99` when the resumed workout differs from
  what readers were told, `:110` when the ended workout is the one readers still see. Nothing is published for
  another workout's end, and no effect is run. I found nothing that should not be published.
- **Two live logs:** as decided; the fault is logged and the rule is F17's.
- **A read that fails for one log** stops the whole pass, and every call throws until a pass reads through. I
  agree: a log that cannot be read may be the live one, and carrying on could let `start` make a second live log.
  `/code-review` reported this as a defect; I do not keep it.

### The clock and `seq` (decision 7): as ADR-004's amendment asks

- A stamp is taken on a copy of the clock and kept only once the envelope is stored (`Actor:164-174`, `:190-201`).
- Every operation runs `ready()` before it stamps, so no stamp is made before a pass has read
  `newestWallClock()` (`Recovery:54-56`). The GRDB store reads the column, unreadable rows included, and skips a
  stamp that is not finite; `observe` skips one too. No stored stamp is clamped or restamped.
- `seq`: the store's highest after recovery (`Recovery:95-96`; unreadable rows count), unchanged after an ignored
  event (`Actor:193-195`) and after a refused append, 0 after an end (`Actor:138`), 1 at a start (`:165`).
- Decision 9 is safe over GRDB: an uncompacted log of the same id from this device makes `append` throw
  `conflictingEnvelope`, so nothing is overwritten quietly. F17 decides the rule.
- `stamp(now:) -> Date?`: agree. The plan's `Date` could not say "no stamp" before `reduce`.
- A finite stamp far in the future drags every later stamp until its log is compacted. That is the drift bound,
  F17's, and the amendment says it acts on receipt only.

### The launch (decisions 11, 12; criterion 9): right

- `run` uses the launch's own `task(for:retrying:_:)`, so the launch owns the step's task and a second call waits
  for it. The step runs in the first `resume` that finds the database open, in any phase, and again only in the
  foreground while `needsRecovery` is true (`Sources/LedgerAppKit/AppComposition.swift:115-120`).
- The host is built in `opened` (`:44-51`) and reads nothing until it is called. The lazy `database` captures
  `self` weakly. The unconditional `import LedgerSync` uses an edge that was already there. No file of the watch
  composition is in the diff.
- `needsRecovery` is read before `run`, a check and an act with an `await` between them. The worst case is one
  extra idempotent pass and a second "began". Not worth a finding.
- **The sanctioned edit** to `LaunchAdversarialTests` is ten added lines and none removed: one flag, one comment,
  one `if` that logs "began resumeWorkout" once. Nothing else in the file changed. The model still constrains the
  launch: the test compares the whole log over 60 seeds, so the step's place, its running once, and its running in
  any phase are all pinned. The step's failure and retry are not in the model; `WorkoutSessionWiringTests` has them.

### `StartWorkoutUseCase` and the misses (decisions 13, 14): as specified

- Criterion 8's three outcomes and three errors are there. The session is built before the live workout is
  discarded, and the same source is resumed whatever `replacingLive` says (rule 17). `exercise(id:)` per slot is a
  fair change from the plan. Open points: SF2 (a waiting end), N7 (latency), N8 (which workout is discarded).
- The misses follow F05's item 6 and ruling O9: the program as stored at the save, only when its id is the
  workout's, each slot updated from its stored value, a slot no longer in the program left out, nothing for an
  ad-hoc workout. Re-sending them on a retry is safe because the update is idempotent.

### Criterion 11 and the repeated runs

- **What it checks:** rules 1, 2, 4 and 5 as the criterion lists them, and the haptics, because an update is
  compared whole. Rule 3 is weaker than it reads (SF4).
- **Independence:** the judge is `Model`, written against the engine in S1, and shares no code with the fake or
  the host. Both implementations and the judge share `WorkoutEngine`, which is the specification.
- **Can a correct host fail it?** Not in these set-ups. One limit for F17: rule 2 ("nothing else is published")
  forbids what the protocol allows a host ("further updates for changes that do not come from this client's
  calls"), so the script must run with no peer traffic.
- **The repeated runs** (60 per pool by the implementer, 4 and 7 more by me, none failing, and mutant M1 failing at
  once) are enough for the host on macOS. The gaps: one run on each simulator, and a fixed three yields per store
  call. A nightly run with a seeded number of yields would vary the interleavings for almost nothing.

### The fifteen decisions

| # | Decision | Reading |
|---|---|---|
| 1 | A queue of tasks the actor owns | Agree. Correct, bounded, and within §4 as written. N5. |
| 2 | `live` changes only in the publishing turn | Agree. Checked at every site. |
| 3 | Readers see the workout as it stood until it is saved | Safe. SF1 (the documentation), SF2 (the consequences); two rulings needed. |
| 4 | A log that cannot be dropped is a failed save | Agree for S2. SF5 for S3. |
| 5 | After a throwing append, read the store first | Agree. N1, N2. |
| 6 | Recovery is one idempotent pass | Agree. N3. |
| 7 | The clock and `seq`; `stamp(now:)` optional | Agree. |
| 8 | A typed throw and a fault log | Accepted by the orchestrator; not reviewed. |
| 9 | `start` stamps seq 1 | Agree for M1. A reused id fails loudly over GRDB. F17's to settle. |
| 10 | Unreadable rows: finish refused, discard keeps the log | Agree. It is F05's rule, and the lifter is never stuck. |
| 11 | `needsRecovery` | Agree. It is what lets the launch retry without re-running a step that succeeded. |
| 12 | Lazy `database`; unconditional import | Agree. |
| 13 | `exercise(id:)` per slot; build before discard | Agree. N7, N8. |
| 14 | Misses by the program's id, on the stored slot | Agree. |
| 15 | Effects as straight-line code | Agree: one way to complete an end. N9. |

### For the orchestrator and the product owner

1. **Standards §4:** no ruling needed (see "Re-entrancy"). A clarifying sentence is the orchestrator's choice.
2. **Product owner: may a lifter abandon a workout that cannot be saved?** Today no call does it (SF2, case 3), and
   "Discard" after a failed save saves the workout (case 1). S7's failure screen depends on the answer.
3. **Orchestrator, before S7: are readers told that an end is waiting?** Today a reopened cover and Today's Resume
   show a workout that looks live and accepts no change. S7's store can remember a failure it saw, but not one from
   before the cover was reopened.
4. **ADR-004:** the amendment's host loop does not have the state "ended in the log, shown as it stood until
   saved". F17 sends `.finished` after `.persist` and before the save, so a peer can show the workout finished
   while this device shows it live. A paragraph in the amendment, before F17 is planned; an ADR change is Pete's to
   review.
5. **S3:** SF5, the log dropped in `materialize`'s transaction.
6. **S7 and ADR-008:** the fake cannot fail a save. When S7 gives it a scriptable failure, the rules of a waiting
   end should become contract clauses, or the fake and the host will drift on exactly the behaviour S7 tests.

### The seven review points

| # | Point | Result |
|---|---|---|
| 1 | Module boundaries | Pass. `Package.swift` and the graph file are untouched; `LedgerSync` imports Foundation, `LedgerDomain` and `os`; the two new Domain files import Foundation. `LedgerSyncTests` now imports `LedgerPersistence` in three files, through `LedgerTestSupport`'s edge and not one of its own; criterion 1 needs the GRDB stores there. |
| 2 | Concurrency | Pass. One unstructured task, owned and awaited; no lock, no `@unchecked`, no detached task; the clock and the id source are injected. |
| 3 | Error handling | Pass. Typed errors per module, no `try?` in product code. `updates()` logs what it cannot throw; `ready()` drops failures that `recoverEnded` has already logged at fault level and that `needsRecovery` remembers. |
| 4 | Design fidelity | Not applicable: no screen. |
| 5 | Accessibility | Not applicable. |
| 6 | Test quality | Pass with SF3, SF4, N10. No sleep, no wall clock, a time limit on every async suite, names as testing-strategy §6 asks, behaviour asserted through the stores and the streams. The timing test follows the stats suite's pattern (warm-up, 20 runs, the 19th fastest, nightly only). |
| 7 | Brief compliance | Each of the twelve criteria has tests. Criterion 4's documentation half carries SF1. Criterion 7's kills are a trigger and a second composition, not a killed process. Criterion 12 is measured on the host only. |

Also checked: the six files outside the slice's list each have a sound, recorded reason; nothing of S3 to S9 is in
the tree (no notification effect, no `programUpdates`, no screen); no lint suppression was added; nothing reads as
compressed; architecture §6 says what the code does, but for SF1's sentence at `:290`.

### The `/code-review` pass

Run through the Skill tool at effort `high` on the range. Ten items, no crash and no data loss over the real
stores. Kept: the session with no exit and the use case's view of a waiting end (SF2), the re-materialise over
History (SF5), the retry answers after a lost acknowledgement (N1), the stale workout with no log (N3), `run`
taking any step (N4), the serial reads (N7), the discard that names no workout (N8). Not kept: the read failure
that stops the whole pass (deliberate and the safe choice, above), and the log decoded twice at a finish (one more
read of a few hundred rows, once per workout).

### What I ran

- `swift test --filter 'LocalWorkoutSessionActor|WorkoutSessionConcurrentScriptTests'` on the host, on the committed
  tree before the tester's files appeared: 61 tests in 9 suites passed on the default pool, and again with
  `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`.
- With `--skip-build`, the contract, the concurrent scripts, the wiring, the relaunch and the launch suites: six
  times on one thread and three on the default pool, all green.
- The queue copied into a standalone program outside the repo (see "Re-entrancy").
- Apple's documentation for `withTaskCancellationShield`.
- `xcresulttool` on the two result bundles in the worktree's `.derivedData/Results` (05:54 and 05:58, just before
  the commit): every suite of this slice passed on the iOS and the watchOS simulator, and nothing failed. Their
  durations are not usable.
- No helper process is left running.

### What I did not check

- Anything on a simulator myself, the full gate (the orchestrator's on `3c960e8`: exit 0), the Release build, and
  the coverage and line counts in the notes.
- The mutants. I may not edit product code, so I did not re-run any; I rely on the notes' table.
- The implementer's sixty runs per pool; I ran four and seven.
- Criterion 12 in the nightly lane, and the start latency (N7).
- The tester's files. The tree was clean when my one build started and the tester's first files appeared while it
  ran, so the binary may hold some of them; every later run reused it (`--skip-build`), and the suites I ran are
  the implementer's.
- That SF3's loop can fail in practice: reasoned, not shown.
- A process killed by the system, and anything on a device.
