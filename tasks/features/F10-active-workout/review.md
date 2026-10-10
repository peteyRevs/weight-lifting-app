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

## Slice S3 — review (G3 reviewer, 2026-10-05)

Reviewed: `git diff 95ac9b8..f8c513d` in the worktree `F10-s3` (33 files, the committed slice only). The tester's
files changed in the tree while I worked and were not read. Paths are under `LedgerKit/` unless they start with
`docs/` or `tasks/`. `Repositories` is `Sources/LedgerDomain/Protocols/Repositories.swift`, `Protocol`
`Sources/LedgerDomain/Protocols/WorkoutSessionClient.swift`, `GRDB`
`Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift`, `Events`
`Sources/LedgerPersistence/Events/GRDBWorkoutEventStore.swift`, `Recovery`
`Sources/LedgerSync/LocalWorkoutSessionActor+Recovery.swift`, `Fake`, `FakePrograms` and `FakeEvents` the three
`Sources/LedgerFakes/InMemory{Workout,Program}Repository.swift` and `InMemoryWorkoutEventStore.swift`, `Linked`
`Sources/LedgerTestSupport/Persistence/WorkoutRepositoryContract+Linked.swift`, `Probe`
`Sources/LedgerTestSupport/Engine/StoreProbe.swift`. Findings are numbered `S3-SF…` and `S3-N…`, so that "SF5"
stays S2's.

### Verdict

**Approved: 0 Blocking, 5 Should fix, 6 Nits.**

I found no way to lose or duplicate a workout, to leave one half saved, or to write a row of another program,
through the committed code over the GRDB stores. The save is one transaction, its order is right, every named
refusal comes before the first write outside history, and the host does the right thing with both answers.

One way to overwrite a program exists, and the slice does not create it so much as give it something to write: a
materialisation that lands after the lifter edited the same slot sets the slot back to the swap (S3-SF2). One
phone on one database cannot produce that order in M1 short of a workout save that fails while a program save
succeeds. F17 can, and the protocol's documentation says the opposite today.

The two forms of `materialize` are safe as committed and wrong as an end state (S3-SF1).

### Blocking

None.

### Should fix

**S3-SF1. Two requirements for one save, the new one with a default and `@discardableResult`. End state: one.**
- Where: `Repositories:72` (the old requirement), `:86-87` (the new one, discardable), `:109-115` (the default);
  `GRDB:55-57` and `Fake:38-40` (the old form calls the new one).
- What is wrong:
  1. A conformer or wrapper that implements only the old call gets the default, and its host saves and compacts
     in two transactions. Nothing fails and nothing is logged: S2's SF5 comes back for that host. The trap the
     orchestrator asked about (a host that believes a log dropped when it was not) does **not** exist in this
     form: the default answers `false`, and the host then compacts (`Recovery:157-161`). What is lost silently is
     the one transaction. Only `WorkoutRelaunchTests.saveThatCannotDropTheLog_savesNothing`, which runs through
     `AppComposition`, would notice a wrapper added to the app's wiring.
  2. The answer is the only signal that the log is still there, and the call is `@discardableResult`. A caller
     that passes `droppingLog: true` and ignores the answer leaves a finished log behind every store that is not
     one database, and the next launch materialises it again (S3-SF2).
  3. The two forms are defined through each other: the default builds the new form on the old, and both shipped
     conformers build the old on the new. Remove the three-argument method from either conformer and the file
     still compiles, and the first save recurses for ever. Loud, but only at run time.
- Why it matters: F17 is where a wrapper around the repository becomes likely (a rebuild path, a sync
  decorator), and it is where "saved and still live" does real damage.
- End state: `materialize(_:slotUpdates:droppingLog:) -> Bool` is the one requirement, with no default and not
  discardable. The two-argument call becomes an extension method, not a requirement, that passes
  `droppingLog: false` and drops the answer. Every conformer then states what it holds.
- How to get there, one mechanical change, before F13 and F17 are planned:
  1. the tester's four types (`HistoryModel`, `SiegeWorkoutRepository`, `SabotagedWorkoutRepository`,
     `BriefWorkoutRepository`), `SeparateWorkoutRepository` and `UnimplementedWorkoutRepository` implement the
     three-argument form: save and answer `false`, or forward where they wrap a linked store and want the one
     transaction under siege;
  2. the old requirement and the default are deleted; the extension convenience is added; the two forwarding
     methods in `GRDB` and `Fake` go;
  3. the contract keeps `dropsTheLog` as the guard on a conformer that answers `true`.
  The tester is editing those files in this slice, so now is the cheapest moment; otherwise a chore PR.

**S3-SF2. A second materialisation is not "nothing" for the program once the slot was edited, and the protocol
says it is.**
- Where: `Repositories:58-59` ("materialising the same workout again changes nothing, the program included");
  `GRDB:231-244`; `Recovery:60` and `Events:67` (the order of a pass).
- What is wrong: an entry is applied whenever the slot does not hold its exercise. So a materialisation made after
  the lifter set that slot to something else sets it back, with no log line. The notes say so (decision 4, open
  question 2); the protocol does not, although it carries the same warning for misses (`:62-63`). Three paths
  materialise late or twice:
  - a waiting end that is saved after a relaunch, or a log held for a later version (`incompleteLog`), days
    after the swap;
  - the two-step path and "a store that lies", where the retry saves again from memory;
  - F17's rebuilds (ADR-004: a rebuild emits `.materialize` again), and a peer's finished workout that carries
    the peer's `programUpdates`.
  With two ended logs in one pass the order is the store's (`SELECT DISTINCT workout_id`, no `ORDER BY`), so two
  workouts that swapped one slot leave whichever was saved last (S3-N5).
- Why it matters: it is a way to corrupt a program, silently: the lifter's later choice is replaced by an older
  one. In M1 on one database it needs a workout save that keeps failing while a program save succeeds, which a
  full disk does not give. It is not Blocking for that reason, and because criterion 3 is met as written (the
  same workout, the same program).
- Fix:
  - now, wording: `Repositories:58-59` gains "as long as the program was not edited in between", and the
    `programUpdates` bullet gains "an entry is applied by every materialisation: one made after the slot was
    edited sets it back. Store an older workout again without its `programUpdates`, as without its slots.";
  - in the ADR-004 amendment, the same rule for a rebuild (below);
  - with O10, when S8 starts: let the swap carry the exercise the slot held, and apply an update only while the
    slot still holds it. That makes the write compare-and-set, safe at any time and in any order.

**S3-SF3. ADR-008 and standards §4 no longer describe the event store fake.**
- Where: `FakeEvents:9-13`, `:73-75`; `docs/adr/ADR-008-ledger-fakes-module.md:37` ("Settings and the event store
  stand alone, as their tables do"), `:59-60` ("The event store, whose protocol is all `async`, stays an
  actor"); `docs/engineering-standards.md:102-104`.
- What is wrong: the event store is now held by the workout store and written under its lock, and its state sits
  behind a `Mutex` with a `nonisolated` synchronous entry. It is an actor by keyword only. Is that allowed by
  decision 4? By its letter, half: it "stays an actor". By its reason, no: decision 4 and §4 allow the `Mutex` so
  that `observe…()` registers synchronously, and name the event store as the fake that needs none. This is a
  second reason (a write that spans two stores cannot await an actor), so it is an extension. It is a sound one:
  awaiting the event store after the history write would rebuild S2's SF5 inside the fake.
- Why it matters: an accepted ADR, decided by Pete, now states two things the code contradicts, and §4's
  exception gives a reason that does not cover this use. I read it as inside the exception's letter (a
  `LedgerFakes` store behind a `Mutex`, Debug only, no `@unchecked`). If the orchestrator reads it as a waiver of
  §4, G5 sends the PR to Pete before the merge.
- Fix: one amendment to ADR-008, in the PR that carries ADR-004's: decision 1 says the event store is linked to
  the workout store; decision 4 says every linked store keeps its state behind a `Mutex`, for either reason, and
  that one lock over the six would also close the reader's gap in the notes' decision 6. §4's clause drops "so
  that `observe…()` registers synchronously" or adds the second reason. Then the mechanical follow-up the notes
  recommend: a `final class`, no caller changes.

**S3-SF4. A wait in the probe that nothing can end, on a call this slice made optional.**
- Where: `Probe:68-72` (`waitUntilHeld()`); `Tests/LedgerSyncTests/LocalWorkoutSessionActorEndTests.swift:45`,
  `:52` (the case `(.compact, false)`).
- What is wrong: the test holds `.compact` and waits for it. When the host does not compact, the continuation is
  never resumed, and a time limit cannot cancel it. Mutants H2 and D1 did exactly that: the suite hung, twice,
  and the helper had to be killed by hand (notes, "Mutants"; open question 8). Before S3 every finish compacted,
  so the wait always ended. Now whether it ends depends on which path the host takes.
- Why it matters: testing-strategy §3 rule 2 gives every async suite a time limit so that no test waits for
  ever. A regression here shows as a hung `swift test` for an agent, and as a runner killed at 60 s under
  xcodebuild, which takes the other results of that process with it.
- Fix: about eight lines in `StoreProbe`: `waitUntilHeld()` inside `withTaskCancellationHandler`, resuming and
  clearing `arrivals` when the waiting task is cancelled. The test then fails at its next expectation.

**S3-SF5. The new host suite compares whole programs inside `#expect`, and the notes say no new suite does.**
- Where: `Tests/LedgerSyncTests/LocalWorkoutSessionActorProgramTests.swift:52`, `:55`, `:72`, `:81`, `:83`, `:86`,
  `:98`, `:102`; notes decision 11 (`implementation-notes.md:2662`).
- What is wrong: eight expectations compare whole `Program` values, seven of them the seed program with its
  days, slots and weeks. A failure prints both sides.
  `Program.difference(from:)` (`Linked:38-66`), written in this slice for this purpose, is not used here.
  `WorkoutRelaunchTests` was changed as the notes say: it now prints one line (`Launch.difference`), checked.
  `LocalWorkoutSessionActorSaveTests:51` and `WorkoutRelaunchTests:97` compare workout states, as S2's suites
  do throughout; I leave those to the orchestrator's rule for S2.
- Why it matters: output only, not correctness. It is the rule the orchestrator set during this slice.
- Fix: `#expect(try await Self.program(in: subject).difference(from: expected) == nil)` at the eight lines.

### Nits

- **S3-N1.** `Tests/LedgerPersistenceTests/LinkedSaveDifferentialTests.swift:22`, `:58`: the thirty scripts are
  the first thirty of `PropertySeed.all`, which holds `LEDGER_PROPERTY_SEED_COUNT` seeds. With the variable at 1,
  `scripts_holdEveryKindOfStep` fails (run: `kinds == […]` at `:60`). It is S1's N2 again. Build the thirty seeds
  in the suite and use that list for the PR cut.
- **S3-N2.** One lane check, three spellings: `TestLane.isNightly` (`Tests/LedgerSyncTests/Support/Tags.swift:19-25`),
  `TestLane.runsSlowTests` (Persistence, Design), and the variable read inline
  (`LocalWorkoutSessionActorPerformanceTests.swift:15`). Use one name. `Seeds.hostSeeds`
  (`WorkoutSessionClientContractTests.swift:29`) is `seeds` in the nightly lane, which is fewer than the PR's
  twenty when the count is set below 20: take the union. Testing-strategy §1's table still says "200 seeds/PR"
  for Sync and §6 describes only a single gated test: one sentence there for a matrix cut by lane.
- **S3-N3.** `GRDB:60-62`, `:86`: the repository answers `droppingLog` because "both stores are tables of one
  database". That holds for `LedgerStores`, the only composition, and nothing checks it. Built over another queue
  than the host's event store, it deletes from its own empty table and answers `true`, the host never compacts,
  and every launch saves the workout again. One line on `init` (`:24`): the event store given to the same host
  must be over this queue.
- **S3-N4.** `GRDB:214-245`: the "exercise is stored" query is a second copy of `ProgramRows`' private
  `Query.exercise` (`Records/ProgramRows.swift:150`), for the same rule. Share one helper, so that a change to
  what "stored" means (a deleted exercise, say) cannot reach only one of them. `guard let program` sits inside
  the loop, so an ad-hoc workout logs one notice per entry: return before the loop.
- **S3-N5.** `Recovery:60`, `Events:67`: a pass completes ended logs in the store's order. Sort them by start
  (then id) before completing, so that the later workout's swap and misses are written last. Two lines.
- **S3-N6.** Wording.
  - `Protocol:64-68` says the save is "one transaction of its database" and that `finish` "never throws for a
    workout that is in history", and qualifies both at `:88-90`. Say "a host whose stores are one database" in
    the first sentence. A second `finish` after a success throws `noLiveWorkout` for a workout that is in
    history; the sentence means the call that saved it.
  - `Protocol:93-94`: the bullet "`discard` saves the workout" should add "with its program changes". `:68`
    says a discarded workout changes no program, and S7's author will read both.
  - Notes `:2982`: "a custom exercise deleted before the save makes the update a skipped one" is not what the
    code does. A soft-deleted exercise keeps its row and the update is applied
    (`WorkoutRepositoryLinkedTests.whatCannotBeApplied_writesNoSlot`), and `ExerciseRepository` has no delete
    today.

### The transaction: sound

`GRDB:69-87`, one `queue.write`, which GRDB wraps in one transaction and rolls back on any throw.

| Step | Writes | Refuses |
|---|---|---|
| before the transaction | nothing | `notFinished` (`:70-72`) |
| the workout's place in history (`Scope`) | nothing (reads) | every named refusal is thrown in these three steps: `duplicateIdentifier`, `nulInText`, `inexactWeight`, `nonFiniteDate` |
| `rows.write` | `workout`, `workout_exercise`, `logged_set` | (the same) |
| `redetect` | `personal_record`, `pr_count` | (the same) |
| `writeMisses` | `slot_miss` | nothing: an unstored slot is skipped |
| `writeProgramUpdates` | `slot.exercise_id`, `slot.updated_at` | nothing: see below |
| `deleteLog` | every `workout_event` row of this workout | nothing |

- **One transaction: yes.** `save_isOneTransaction_inOrder` reads the statements between `BEGIN` and `COMMIT`;
  `lateFailure_rollsEverythingBack` fails each of the three late statements with a trigger and compares every
  row of ten tables; `WorkoutRelaunchTests.saveThatCannotDropTheLog_savesNothing` shows it on a file through the
  app's composition. All pass here on both pools.
- **Order: right.** Every named refusal is thrown before the first write outside history, so a refused workout
  has touched no slot and no log even before the rollback. The log goes last.
- **Idempotence: yes, for an unchanged program.** A second save runs no `INSERT` and no `UPDATE`, with the log
  gone or put back (`secondSave_writesNoRow`); the `DELETE` then matches no row. S3-SF2 is the limit.
- **The answer.** `true` only when asked, after the commit. The host returns on `true` and compacts on `false`
  (`Recovery:155-161`); a discarded workout is compacted as before. Mutants G7, G11, H1, H2, H3 and D1 are
  killed.
- **The repository deleting event rows.** Contained: one internal static function, `Events:92-97`, the statement
  `compact` runs; the repository holds no SQL of that table. Named honestly on the type (`GRDB:15-17`), on the
  method and on the protocol (`Repositories:78-80`). The one thing left unsaid is S3-N3.
- **Not in the transaction:** the completeness check (`Recovery:148`) and the read of the program for the
  misses (`:156`). Both are reads of their own, as before S3. In M1 only the host writes a log, one operation at
  a time. F17 must close the first (below).

### Program updates: the rule holds

What is written: `exercise_id` and `updated_at` of that one `slot` row, nothing else. `created_at`, the numbers,
the position, the day's and the program's rows and the slot's misses stay
(`programUpdate_writesTwoColumnsOfOneRow` reads every other column). That is what a program save writes for the
same change (`SyncedRecord.write`: the changed row's content and its `updated_at`), so a sync that sends rows by
`updated_at` will carry it. One thing for M4's sync ADR: the stamp is the save's time, not the swap's, so a save
that lands late beats an edit made on another device in between. It is S3-SF2 across devices.

| Bypass tried | Result |
|---|---|
| a slot of another program | not written: the query joins `slot`, `day_template`, `program` on the workout's `programID` (`GRDB:216-222`). `estrangedSlot_isSkipped` case 4, the clause's `stranger`, mutant G1 |
| a deleted slot, a deleted day, a deleted program | not written: three `deleted_at IS NULL`; mutants G2, G3, G4 each killed by its own case |
| an ad-hoc workout, an unstored program | not written |
| the same slot twice | cannot be given: a dictionary; applied in slot-id order |
| an update and a miss for one slot | both written, in separate rows, in either order (`appliesProgramUpdates`). The miss is judged on the replacement's sets against the targets the swap kept; it follows from Pete's default 2 (the slot keeps its numbers), and S8 should confirm it |
| an exercise with no row | skipped before the foreign key could fail the save; mutant G5 |
| a soft-deleted exercise | applied, as a program save accepts it (`ProgramRows.refuseUnknownExercises`). No call deletes an exercise today |
| a slot of another day of the same program | applied. Criterion 1 allows it ("a stored slot of the workout's own program") |
| the workout's program is not the active one | applied, while no miss is sent (ruling O9). Pinned by `finish_anotherProgramActive_changesTheWorkoutsProgram` |

Against F05 S2's B1: no row moves between programs and none of another program's is written. No rule of
`Program.init` or `Slot.init` depends on a slot's exercise, so the update cannot leave a program that no longer
loads.

Observers are told once: one transaction is one notification to `observeActive()` and one to
`observeRecent(limit:)`; a save that changes no program emits nothing (`observersHearTheSave`). The fake writes
its programs in one step (`FakePrograms:81-93`), though no test can tell (mutant F8).

A skipped update is silent to the lifter (the notes' open question 6): `materialize` answers only whether the
log went. S8 decides before the sheet ships.

### The API

S3-SF1. As committed it is safe: the default errs on the side of a second step, and the app's wiring is pinned
to one transaction by a test on a file. As an end state it is a trap for F17. One requirement, no default, not
discardable; the two-argument call as a convenience.

### The host: matches both tables

`complete(_:)` (`Recovery:147-162`) against the notes' failure table:

| Row | Result |
|---|---|
| append, any event; append that stored and threw; the clock | Unchanged from S2. |
| the save, one transaction | Matches. `ending` is set after the append, `settle()` throws the store's error, `live` stays. Retry by `finish` saves and drops in one call, publishes once, returns the first end. `apply` and `discard` complete it and throw `noLiveWorkout`; `start` throws `workoutInProgress`; the foreground pass completes it without a haptic. |
| the save that stored and then threw | Matches. The retry finds no log (`unreadableCount` 0), saves again from memory, gets `true`, publishes once. |
| `compact` after the save, separate stores only | Matches: `false`, then `compact` throws, the end waits, the retry saves again and compacts. |
| `compact` after `.discarded` | Unchanged. |
| a read during recovery; a save during recovery | Match. A failed save leaves that log whole and nothing of its save. |

The recovery table matches row for row. "Saved, and the log still there" is no longer produced over the
database and is still handled (`savedLog_isSavedAgainAndDropped` on both kinds of store,
`logLeftBehindASavedWorkout_isSavedAgainUnchanged` on a file).

- **Published and played:** nothing changed. The two sites are S2's (`conclude` from `settle()` and from
  `recoverEnded`), and recovery still plays no haptic.
- **The protocol's documentation** is true of the code, with S3-N6's two sentences.
- **A waiting end, better:** it is one state now. A failed save has changed nothing, so "in history and still
  live" is gone over the database, and `finish` cannot throw after its transaction.
- **A waiting end, worse or new:**
  - it now holds a program change back, and writes it whenever it is completed: at a retry, at the next
    foreground, at a launch days later (S3-SF2);
  - "Discard" on a waiting finish now saves the workout **and** changes the program (S3-N6);
  - the case with no exit in this process (S2's SF2, case 3) is as it was.

### The fakes (ADR-008)

- **Atomicity and order.** `Fake:53-66`: the workout is stored and its records detected first, the only steps
  that throw; then the programs and the log, under the history's lock. A refused save has touched neither
  (mutant F6). Lock order is history → programs → exercises and history → events, and no path takes them the
  other way. A reader of history never sees half a save; a reader of only the programs and the log can, for an
  instant (the notes' decision 6). I agree it is not worth one lock over six stores today.
- **The event store:** S3-SF3. Sound, and an extension of decision 4 that the ADR should record.
- **77 lines against 20.** Twenty-eight are the event store's state moved behind the lock, sixteen the one-step
  program write, the rest the link and the answer. Two behaviours are ones no database has, both documented and
  both the stand-alone stores' older rule: an unlinked `InMemoryWorkoutRepository()` holds no log and answers
  `false` (it is the protocol's default), and its programs check no exercise, so an update naming an unknown
  exercise is applied there (`unlinkedWorkouts_holdNoLog` pins it). The linked stores, which previews and store
  tests use, do neither.
- The fake's `writeMisses` reaches any live program's slot while `writeExercises` reaches only the workout's own.
  That is the database's pair of rules too (`GRDB:174-194` checks only that the slot is live).

### Contract and differential tests; the mutants

- **The six clauses** are independent of both implementations: each builds its expected program by hand and
  names what differs. Both event-log clauses fail for a subject with no event store, so none passes by running
  nothing. They run on GRDB and on the linked fakes, and pass on both pools.
- **The differential** is not an oracle and does not claim to be: it compares the two implementations step by
  step over scripts built from the seed alone. A rule both get wrong the same way passes it; the clauses are what
  pin the rules. It can fail (mutants G1, G5, G8, F1, F2, F3b, F5, F6). Seeds are the fixed sequence, thirty in
  the PR lane and every seed of the lane in the nightly one, and a failure names its seed and step. S3-N1.
- **24 of 26.** The survivors:
  - *F3, the fake changes a deleted program:* equivalent. A deleted program comes back only through `save`, which
    replaces it whole, and no call shows it meanwhile. The database's rule is G4, killed.
  - *F8, the fake writes misses and exercises in two steps:* not observable without a race, since a stream keeps
    its newest value. It does not matter for the product. It is the same gap as the reader's instant above.
  Neither needs a test. H2 and D1 are killed by a hang, not by a failure: S3-SF4.
- I did not re-run the mutants (I may not edit product code).

### Criterion 9

- **Every clause, store and fault in the PR lane: yes.** My host run: 144 clause cases (24 × 6 set-ups), 120
  sequential and 120 concurrent scripts on the host (20 × 6), the fake's 200 of each, the ten overlap faults.
  The faulty-client suite is not in the diff. The twenty seeds are the ones `scripts_reachEveryCallAndRefusal`
  and `scripts_holdEveryKindOfAction` already vouch for. Stores that are not one database are in no matrix of
  the implementer's, only in six of its tests and, by the notes, in the tester's siege.
- **The nightly lane is the full matrix by the code:** `seeds` × six set-ups, as before the slice, 2,000 in the
  Nightly plans. Nobody has run it at 2,000 on a simulator.
- **It cannot silently run nothing:** `fixedSeeds` is twenty, `seeds` is at least one, and a lane value that is
  not exactly `nightly` (the device lane, a typo, `swift test`) runs the PR cut. S3-N2 for the count below 20.
- **The mechanism is the repo's own.** Testing-strategy §6 has lanes "confirmed by the `LEDGER_TEST_LANE` env
  var", F06 gates a single slow test with `TestLane.runsSlowTests`, and F05's tester already cuts a seed list by
  lane on `main`. No plan and no `project.pbxproj` change is the right call. S3-N2 for the three spellings.
- **The figure.** The implementer's suites went to 23 %; the session suites as a whole to 64 %. The rest is in
  tester files, outside this range. I did not measure.

### No migration, budgets, documents, boundaries

- **No migration:** `Migrations.swift` and every fixture are untouched; the version-1 fixture takes the new save
  and the applied migrations are still two (`open_savesWithAProgramUpdateAndTheLogDropped`, passes).
- **Criterion 8:** the timing test follows the suite's pattern (nightly only, a warm-up, twenty runs, the 95th
  percentile, the budget in `PerformanceBudget`, an attachment). My one host run: p95 29.6 ms, median 14.2 ms,
  against 50 ms, at a load average of 15 with other lanes running; the notes have 16.0 ms. Not on a simulator.
- **Architecture §5, §6, §7, §15** say what the code does. §6 keeps "where nothing can be started over it"
  with "in this process", as S2 left it.
- **ADR-004 rule 5** is stale, as the notes say. ADR-008 is stale too (S3-SF3).
- **Boundaries:** `Package.swift` and the graph file are untouched; `deleteLog(of:in:)` is internal to
  `LedgerPersistence`; no GRDB type leaves it; the Domain gained no import.
- Nothing of S4 to S9 is in the tree: no screen, no notification effect, and the swap event's payload is
  unchanged. No lint suppression was added (the diff holds none; I did not run the linter). Nothing reads as
  compressed. Product lines are 70, the fakes 77.

### What the ADR-004 amendment must state

1. **Rule 5's last sentence.** A finished workout's log is dropped in the transaction that materialises it
   where history and the log are one database, and after it, as a step that can fail alone, where they are not.
   A discarded workout's log is compacted by the event store.
2. **What a materialisation is.** The rows, the records, the slots' misses and the program changes of
   `programUpdates`, together or not at all. An update touches only a live slot of the workout's own program and
   names a stored exercise; anything else is logged and skipped.
3. **A materialisation is not free to repeat.** Each one writes the misses and the program updates again, on
   the program as stored then. A rebuild that stores an older workout again sends no slots and no
   `programUpdates` (or the swap becomes compare-and-set, with O10).
4. **A saved workout has no log on that device.** A late envelope for it finds no `started`, replays to nothing
   and is kept. The amendment must say what F17 does then, since a resend of the peer's own envelopes cannot
   rebuild it; and so the host loop's "a rebuild emits `.materialize` again" needs its condition.
5. **Completeness.** "Never materialise or compact a log with rows this version cannot read" is checked by the
   host before the transaction. Once a peer can append, the check and the drop must be one step: the append in
   the host's queue, or a drop that is refused when the log is not the one that was replayed.
6. **The waiting end** (owed since S2): between the stored `finished` and the save, this device shows the
   workout as it stood, while a peer that received `finished` shows it ended.
7. **Recovery.** The row "materialised, not compacted" exists only for stores that are not one database; ended
   logs of one pass are completed in start order.

### The seven review points

| # | Point | Result |
|---|---|---|
| 1 | Module boundaries | Pass. No edge added; the cross-store delete is one internal function in `LedgerPersistence`. |
| 2 | Concurrency | Pass with S3-SF3. No task, no `@unchecked`, no lock in product code; one `Mutex` in a Debug fake that ADR-008 does not yet describe. The clock is injected. |
| 3 | Error handling | Pass. Nothing swallowed: a skipped update is logged at notice with ids only, and the two `try?` in tests carry their reason. |
| 4 | Design fidelity | Not applicable: no screen. |
| 5 | Accessibility | Not applicable. |
| 6 | Test quality | Pass with S3-SF4, S3-SF5, S3-N1. Behaviour is asserted through rows, statements and the protocol; no sleep, no wall clock, a time limit on every suite; the new clauses print one line. |
| 7 | Brief compliance | Criteria 1 to 8 each have tests that pass here. Criterion 8 is measured on the host only. Criterion 9 is met for the implementer's suites and not yet as a whole. |

### What later work must be told

- **S7.**
  - When `finish` returns, the workout is in history, the program holds its swaps and the log is gone. A failed
    save has changed nothing; "Try again" is `finish` and keeps the first end date.
  - "Discard" after a failed save saves the workout and changes the program.
  - Nothing tells the lifter that a program update was skipped.
  - `FakeWorkoutSessionClient` stores nothing: a test that the program changed at Finish needs the host over
    `InMemoryStores`, as `LocalWorkoutSessionActorProgramTests` does.
- **S8.**
  - The program changes at the save, never at a discard, and only for an exercise with a `slotID`.
  - A later swap of the same slot with the toggle off leaves the earlier entry, and S3 now writes it. Decide
    with O10 before the sheet ships.
  - The slot keeps its numbers and its misses, and this workout's miss is recorded on it, judged on the
    replacement's sets.
  - The update goes to the workout's program even when another is active.
  - A save that lands late overwrites an edit of that slot: carry the exercise the slot held (S3-SF2).
  - An update naming a soft-deleted exercise is applied, not skipped (S3-N6).
- **F13.**
  - Over the database a workout in history has no log, so History may edit or delete any workout it lists, and
    the phone's own finish can no longer bring one back. One exception in this process: a save that committed
    and was answered as a failure is saved again from memory at the next call or foreground.
  - `delete(id:)` undoes neither the program change nor the misses.
  - A workout read from history has no `programUpdates`: storing it again touches no program.
- **F17.**
  - S3-SF2: every materialisation applies the program updates again, and a peer's workout brings the peer's.
  - The completeness check and the drop are two steps (item 5 above).
  - A late envelope for a saved workout meets no log (item 4).
  - A wrapper around `WorkoutRepository` must forward the three-argument call, or S3-SF1 is done first.
  - `GRDBWorkoutRepository` answers for its own queue only (S3-N3); order a pass by start (S3-N5).
  - The contract's script must still run with no peer traffic (S2's note).

### The `/code-review` pass

Run through the Skill tool at effort `high` on the range. Ten items, none a crash or a loss over the real
stores. Kept: the slot set back by a later materialisation (S3-SF2), the default that hides a lost transaction
(S3-SF1), the unconditional `true` (S3-N3), the copied exercise query and the guard in the loop (S3-N4), the
order of a recovery pass (S3-N5), the check and the drop two reads apart (F17, item 5). Passed on as inputs, not
findings on this diff: the engine never clears an entry when a later swap has the toggle off (F04's rule, S8),
and a swapped slot keeping the old exercise's numbers and misses (Pete's default 2). Not kept: the fake's two
ownership rules, which are the database's too.

### What I ran

- On the host, `env -u SDKROOT swift test --package-path LedgerKit --only-use-versions-from-resolved-file`, one
  build, then `--skip-build`:
  - `LinkedSaveDifferentialTests`, `WorkoutRepositoryLinkedTests`, `WorkoutRepositoryTests`,
    `InMemoryContractTests`, `MigrationCompatibilityTests`: 36 tests in 5 suites passed;
  - the host's save, program, end, recovery and contract suites, the two contract suites of the seam and
    `WorkoutRelaunchTests`: 56 tests in 8 suites passed;
  - all of those but the migration suite again with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`: passed;
  - `LinkedSaveDifferentialTests` with `LEDGER_PROPERTY_SEED_COUNT=1`: one failure, S3-N1;
  - `LEDGER_TEST_LANE=nightly … --filter RecordReplayPerformanceTests/finishWithProgramUpdatesAndTheLog_underBudget`,
    once: passed, the figure above.
- Logs are in the scratch folder `f10s3-g3`. No helper process is left running.

### What I did not check

- Anything on a simulator, the full gate, `scripts/check.sh --lint-only`, the Release build, coverage, and the
  line counts in the notes.
- The mutants: read from the notes' table, not re-run.
- Criterion 9's figures, and the nightly matrix at 2,000 seeds.
- The tester's files, and the test that fails by ruling. The tree held the tester's changes in progress when my
  one build ran, so the binary holds some of them; the suites I ran are the implementer's.
- S3-SF2's order of events on a device: reasoned from the code, not reproduced. S3-SF1's recursion and S3-N3's
  two queues: reasoned, not run.
- That the 60 s allowance ends a hung probe wait under xcodebuild: the notes say so.
- A process killed by the system, watchOS, and anything on a device.

## Slice S4 — review (G3 reviewer, 2026-10-08)

Reviewed: `git diff d61a3c4..46d4103` (one commit, `46d4103`), read in the worktree `F10-s4`. The tester's
untracked files were not read.

**Verdict: APPROVE. Blocking 0 · Should fix 5 · Nit 11.**

The lifecycle is sound. The session is the one source of truth for what is live; the launcher holds only
"what is presented" and the store only "what the session last published plus this cover's dialogs". I found no
path on which two workouts are live, a workout is lost without the lifter choosing "Discard", a choice runs
twice, or the cover goes on showing a workout that ended. The five Should-fix items are one product call (the
invisible Cancel), one test that proves less than its name, one alert line that claims more than the launcher
knows, and two small pins.

**The `/code-review` pass** ran at effort `high` as a forked agent, given the range and this worktree and told
to read only. It returned ten findings, none a correctness bug that blocks. What I did with each:

| Its finding | Disposition |
|---|---|
| A cancelled "Discard and start new" ends `idle` with the old workout already discarded (`WorkoutLauncher.swift:109`) | Not reachable on the host: `inTurn` runs each call in the actor's own task and a cancelled caller's `task.value` does not throw, and nothing but `session.start` stands between the discard and the start. A session that did throw `CancellationError` there would lose the word, so the comment at `:97-99` should say "on a host that completes its calls". No finding. |
| "was kept" said when the old workout was discarded and a third one is live (`:159`) | True on two devices only. Folded into S4-N4. |
| `onRoute` fires before the cover is down | S4-N2. |
| The loading cover has no control | S4-N9 (new). |
| The failure alert's title goes empty as it dismisses (`WorkoutCover.swift:68`) | S4-N10 (new); not verified. |
| The "same workout" rule is written in the launcher as well as in `SessionBuilder.resumable` | By criterion 3's own wording. Carried to "What S5 and F09 S5 must be told" for the watch. |
| VoiceOver hears no elapsed time | Open question 1, already ruled for S4. |
| `today.waitForExistence` after Minimize and Discard is vacuous (`Smoke.swift:51`, `:64`) | Right. Folded into S4-SF2. |
| The dismissal binding, the logger accessor and the run-once guard are each written twice | S4-N11 (new). |
| A store is made on every evaluation of the cover's content | S4-N7. |

### Should fix

- **S4-SF1. The conflict dialog offers a destructive choice and no visible way out.**
  `LedgerKit/Sources/FeatureWorkout/WorkoutCover.swift:60-65`; `screenshots/s4/conflict-dialog-light.png`,
  `conflict-dialog-dark.png`. On iOS 27 the dialog draws "Resume it" and, in red, "Discard and start new";
  the `role: .cancel` button is not drawn, and the only way to back out is a tap outside the card, which
  nothing on screen says. A lifter who tapped the wrong day's "Start workout" has two visible choices, and
  neither is "leave things as they are, show me nothing". The brief's "Copy (exact)" names only the two
  buttons, but the S4 amendment's criterion 4 names three choices ("resume the live one; discard it and start
  the new one; cancel"), and the finish dialog in the same slice already solved this the other way (a plain
  button with no role is drawn). The two dialogs of one feature should not differ here, and the one that can
  destroy a workout from outside the cover is the one that most needs the button.
  **Fix (smallest):** drop `role: .cancel` at `:64`, as `WorkoutRoot.swift:37` does for "Keep lifting"; the
  dismissal binding still sends `.cancelConflict` for a tap outside, and `accept` already takes the two in
  either order. One line, no new copy ("Cancel" is in the catalog), no reference changes (the dialog is not
  in a snapshot). **Alternative, if Pete wants it harder to do by accident:** an `.alert` with the same three
  buttons: an alert draws every button and a tap outside does not dismiss it. I recommend the first now and
  leave the second to Pete. Either way retake the two screenshots when Today can reach the dialog (F09 S5).
- **S4-SF2. The UI test does not prove "0:00 advances"; it can pass on the cover's own animation.**
  `Apps/LedgerUITests/Smoke.swift:42-48`. `atStart` is the first screenshot of the element, taken right after
  `waitForExistence` and three synchronous reads, which can be inside the cover's slide-up; the expectation is
  then "any later screenshot differs". A frame of the transition, or the dot's antialiasing settling,
  satisfies it with a timer that never counts, and nothing in the test ever reads "0:00" (the element's label
  is the fixed "Elapsed time"). Criterion 10 asks that the test "sees '0:00' advance". **Fix:** take the first
  picture only when the cover has settled (wait for `minimize.isHittable`, then until two consecutive
  screenshots are equal), then wait for a third that differs; and say in the test's comment that the reading
  itself ("0:00", "1:01:05") is pinned by `WorkoutSnapshotTests`, not here. If a real reading is wanted in the
  app, the cheap way is open question 1's (a value made when asked), which S6 is to decide.
  The same test's `today.waitForExistence` after Minimize (`:51`) and after Discard (`:64`) proves nothing:
  the title exists under the cover, which is why `:37` asks `isHittable`. Wait for `today.isHittable` in both
  places; the second long press on the title then also stops racing the cover's way down.
- **S4-SF3. "Nothing was changed. Try again." is said when the launcher does not know that.**
  `WorkoutLauncher.swift:147-168` with `WorkoutPresentation.swift:65`. After a `.start` that threw, the
  launcher reads the session again; when that read also throws, `aftermath` stays `.unknown` and is then
  dropped, because `.notStarted` carries only a `Reason`. The alert says "Nothing was changed." Row L19 of
  the implementer's own table is the case where that is false: the write went through and its answer was
  lost. The notes say of the replace path that an unreadable session gives a line that "claims nothing"; the
  start path should hold to the same rule. **Fix:** when the re-read fails, return a failure whose line is
  `WorkoutCopy.tryAgain` (for instance `.notStarted(.unknown)` mapped to "Try again.", or reuse
  `.notOpened`), keep "Nothing was changed. Try again." for a start that failed with the session read; one
  test beside `sessionCannotBeRead_opensNothing`, which today pins the wrong line for this case.
- **S4-SF4. Criterion 7's "no unstructured task" is pinned by nothing; the notes say a test pins it.**
  `LedgerKit/Tests/FeatureWorkoutTests/FeatureWorkoutSourceTests.swift:28-31`; notes, "Criteria → tests",
  row 7 ("no `Task {` and no sleep in the module: `sources_neverCountTime` and review"). The list holds
  `Task.sleep` and no spelling of a task being made. The module is clean today (I searched), but S5 adds the
  intent pump and S6 the rest effects, which is exactly where a `Task { }` in a store gets written.
  **Fix:** a third list, `["Task{", "Task(", "Task.detached", "Task.init"]`, and a test
  `sources_startNoTaskOfTheirOwn`; the existing `check_findsASpelling…` loop then covers it. (`FeatureToday`'s
  and `FeatureProgram`'s source tests lack it too: the ambient list here is theirs word for word, so this
  module knows what they learned and no more. Worth one follow-up for all three.)
- **S4-SF5. The translator's comment on the one two-value key does not say which number is which.**
  `WorkoutCopy.swift:39` and the catalog's `"Exercise %lld of %lld"` (`Localizable.xcstrings:120`): "Which
  exercise of the workout is the current one". `FeatureToday` writes the order for every such key ("The
  program week, counted from 1, then the number of weeks in the block", `TodayCopy+Cards.swift:17`), because a
  language that turns the phrase round needs it. **Fix:** "The current exercise's place in the workout,
  counted from 1, then the number of exercises", in both files, word for word (the gate compares them).

### Nit

- **S4-N1. A cover asked for again while the last one is still going down could, in principle, be handed
  the old store.** `WorkoutCover.swift:44-50`, `WorkoutRoot.swift:10`. The store is `@State` of the cover's
  content, and a store whose `exit` is set answers nothing (`WorkoutStore.swift:85`) and disables both
  buttons. If SwiftUI ever keeps the content's state across `isPresented` going false then true inside one
  dismissal, the lifter gets a cover with no way out. I do not know that it does: UIKit ignores touches under
  a transition, and the UI test's second start goes through the Debug sheet, which is slow. **What would
  settle it:** F09 S5's UI test tapping "Resume" straight after "Minimize". **Cheap insurance now:**
  `WorkoutRoot { … }.id(launcher.request?.number)` at `:45`, so each accepted request is a new store by
  construction rather than by SwiftUI's habit.
- **S4-N2. `onRoute` is documented as told "after it has closed"; it is told as the dismissal begins.**
  `WorkoutCover.swift:9`, `:45-49`: `launcher.send(.coverClosed)` and `onRoute(route)` run in the same turn.
  Harmless for `.saved` → `selectedTab = .today` (under the cover). It will matter if a route ever presents
  something (a sheet cannot go up over a cover that is still going down: `MainRoot`'s own comment on the
  Debug sheet). Fix the sentence, or call `onRoute` from the cover's `onDismiss`.
- **S4-N3. Two quiet outcomes on Resume.** (a) `WorkoutLauncher.swift:164`: a `.resume` whose first read
  threw and whose second read finds a live workout still shows "Couldn't open this workout"; it could return
  `.cover`. (b) Row L14: "Resume it" after the live workout ended elsewhere does nothing at all, with no word.
  Both are rare; (b) is right for a phone alone and worth a line once the watch can end a workout (F15+).
- **S4-N4. A replacement that cannot be built does not say why.** `WorkoutLauncher.swift:165`: `.replace`
  drops the error, so a block that has ended gives "Couldn't start the new workout / Your workout in progress
  was kept." and the same again on every try. `.notReplaced` could carry the `Reason` when the live workout
  was kept. Product owner's call; one more text. The same lines (`:156-159`) call the aftermath `liveKept`
  whenever anything is live: if the discard went through and another device started a third workout before
  the start, the alert says "was kept" of a workout that is gone. Two devices only; the launcher would need
  the id of the workout it set out to replace (the use case's `.conflict(live:)` has it; `.conflict(source)`
  drops it). For F15's list.
- **S4-N5. The header's dot is `LedgerColor.accent`; every other small orange mark on paper is
  `accentText`.** `Views/WorkoutHeader.swift:45` against `ProgressSegments.swift:73` ("the orange that reads
  on paper too"), `WeekStrip.swift:94`, `SetRow.swift:185`. In `cover-after-24-minutes-light.png` the dot and
  the current segment, 100 pt apart, are two different oranges. The prototype has one orange, on a dark
  ground only. Also `:18` is a raw `5` in a feature view; the standards' token list does not cover a shape's
  size, so this is not a violation, but the dot belongs to `LedgerDesign` the day a second screen draws it
  (Today's Resume card, the Live Activity).
- **S4-N6. The plan's surface is stale in two places** (notes, "S4 — cover and header": `start` is `async`,
  `WorkoutRoot` is `public`). The code follows the later rulings; correct the block so F09 S5 does not copy it.
- **S4-N7. `WorkoutRoot.init(onExit:)` makes a `WorkoutStore` on every evaluation of the cover's content**
  (`WorkoutRoot.swift:14`), each with four `@Dependency` wrappers, of which `@State` keeps the first. It is
  the pattern `MainRoot`'s comment sanctions, and S4's store is cheap. Tell S5–S9: nothing in
  `WorkoutStore.init`, ever.
- **S4-N8. Sixteen or seventeen?** The notes' table has 17 rows, their open question 5 says "Sixteen texts
  are mine". Seventeen: the table is right.
- **S4-N9. The loading cover has no way out.** `Views/WorkoutScreen.swift:23-24`: `.loading` draws the ground
  alone, and a full-screen cover cannot be swiped away. It should last one turn: the launcher has already
  awaited `current()`, which waits for the same recovery `updates()` waits for. If the stream's first element
  were ever late, the lifter would face a blank screen until they killed the app. A "Minimize" in the loading
  state costs a few lines; at least S5 should not make loading any longer.
- **S4-N10. The failure alert's title is read from live state, its message from `presenting:`.**
  `WorkoutCover.swift:68`: `failure?.title ?? ""` is empty the moment "OK" sets the phase to `idle`, while the
  message is still held. If SwiftUI redraws the alert as it goes down, it shows a message under no title. Not
  verified (no alert was screenshot or driven). What would settle it: one look on the simulator at a refused
  start. Fix if seen: keep the last failure's model in the launcher until the next request.
- **S4-N11. Three small things are each written twice**: the dismissal binding (`WorkoutCover.swift:80`,
  `WorkoutRoot.swift:60`), the logger accessor and the run-once guard (launcher and store). Fine at this size;
  fold them when S5 adds a third.

### The points asked about

**The lifecycle (criteria 1–5): sound.** Read against the table, row by row.

| Question | Answer |
|---|---|
| Two workouts live? | No. The launcher never starts one itself: the use case does, and the host's `start` refuses while one is live (`workoutInProgress`). A second request is dropped while `working` or `cover` (`WorkoutLauncher.swift:86`); `run()` is single-flight (`:102`). |
| One lost? | Only by "Discard" or "Discard and start new". The replace order is the use case's: build, then discard, then start (`StartWorkoutUseCase.swift:96-104`), so a day that cannot be built discards nothing (L12) and a discard that fails starts nothing (L10). L11 (discarded, start failed) leaves none live and says so; that is the one unavoidable loss and it is told truthfully. |
| Cover showing a workout that ended? | No. The store shows only what `updates()` publishes and leaves on the first update that is not live (`WorkoutStore.swift:136-139`); a new stream starts with the present state, so a cover put up late closes itself (S11). |
| A failure swallowed? | No error is dropped unlogged or unshown, cancellation apart (standards §8). Three outcomes are quiet by design: L5, L14, S7. One line overclaims: S4-SF3. |
| A choice run twice? | No. The dialog's dismissal and its button arrive in either order and make one request (`accept`); "Discard" twice is one attempt (`isDiscarding`, `isDiscardRunning`). Tested (S5, L17). |
| Resume through `StartWorkoutUseCase.start`? | Never: `.resume` reads `current()` only; `.start` for the live day returns before the use case (`:124-126`), and compares `source` exactly as `SessionBuilder.resumable` does, so the two cannot disagree. L3 tests a deleted and an emptied day, with a control. |
| An update during a dialog or a call? | Store: a change keeps the finish dialog up (S8); an end takes it down with the cover (S9, S10). Launcher: it does not follow the stream, and need not: each choice reads the session afresh (L13, L14). An update that lands while `discard` is in flight is harmless: `leave` is idempotent and the first reason stands. |

One thing the table does not say and the protocol does: the session's `discard` names no workout. If another
device replaced the live workout between the lifter's tap and the call, the new one is discarded. That is
S1's contract, not this slice's, and cannot happen on a phone alone; it should be on F15's list.

**Two owners: sound, and I recommend the deviation be accepted.** The conflict dialog shows with no cover up,
so it cannot live in an object that lives with the cover. Who owns "which workout is showing": nobody but the
session. `WorkoutLaunchPhase.cover` deliberately carries no workout id, and the store keeps no workout of its
own, so there is no second copy to drift. The seam between the two is one value in one direction
(`WorkoutExit`, through `onExit`). It will hold for S5–S9 provided they keep to it: everything inside the
cover grows the store; the launcher gains nothing. Two places will strain:
- **S7.** `follow()` leaves the cover on the update that carries the finished state
  (`WorkoutStore.swift:136-138`, `:153`). The cover's own save must instead stay up for the receipt. S7 has to
  tell "finished by this cover" from "finished elsewhere" before that line, and `WorkoutRoute.saved` is then
  sent by "Done".
- **F09 S5 and the builder.** Callers hold the one launcher from `MainRoot`; a second launcher, or a second
  `.workoutCover`, would give two presenters over one session. Keep it to one, passed down as intents.

**The store and the conventions (criterion 7): met.** `@MainActor @Observable final`, dependencies
`@ObservationIgnored @Dependency`, intents synchronous and state-only, both pieces of work run from
`WorkoutRoot`'s `.task` and `.task(id:)`, `Loadable<WorkoutState>`, no `Task`, no stored task. Minimize and
show again: a new `WorkoutRoot`, so a new store and a new stream; the old `.task` is cancelled with the view,
its `for await` ends, and the host prunes ended continuations when it next publishes
(`LocalWorkoutSessionActor.swift:154-160`). Nothing is missed in between, because a stream's first element is
the present state. Cancelling the root's task is not treated as a failure (`:142`, `:177`), and the host
finishes a call in its own task (S13, L18 test both). See S4-N1 for the one assumption in this paragraph.

**Concurrency: clean.** No `nonisolated(unsafe)`, no `@unchecked Sendable`, no detached or unstructured work
in product code. Everything that crosses to the session is a `Sendable` value; the use case is built per
request from `Sendable` dependencies, and its two closures capture the date and UUID generators, not `self`.
`WorkoutTimeline`'s environment entry is `nonisolated` for the reason its comment gives.

**The elapsed time (criterion 6): met.** One `Text(timerInterval:pauseTime:countsDown:)`, in
`WorkoutTimeline`, pinned by the source test; the header reads the timeline from the environment and no
clock. Fixed in previews, snapshots and the tree. "1:01:05" is in a reference. A start in the future reads
"0:00" until it comes; a start outside the calendar's range cannot trap. VoiceOver hears "Elapsed time" and
no frozen number, as ruled; open question 1 (a value made when asked) is a fair S6 item and I support it.

**The presentation and the words (criterion 8): met, with S4-SF5.** `WorkoutPresentation` is pure and
`nonisolated`; no view or store holds a literal. The brief's ten texts are character for character
("Exercise %lld of %lld", "You have a workout in progress", "Resume it", "Discard and start new",
"End workout?", "Discard", "Keep lifting", "Minimize", "Finish"; "Cancel" borrowed from the swap sheet). The
three refusal reasons map one to one (`emptyDay`; `programNotActive` and `dayNotInProgram` together;
`weekOutOfRange`), and `unknownExercise` falls to "Nothing was changed. Try again.", which is true. The
`debugOnly` exemption of `WorkoutLauncher+Sample.swift` is confirmed: the file is wholly inside `#if DEBUG`
and its one literal is the Debug row's title.

**The dialogs:** S4-SF1 for the conflict. The finish dialog (`finish-dialog-dark.png`) is acceptable as an
interim: both choices are drawn, "Keep lifting" is a real button, a tap outside keeps lifting. Its red
"Discard" sits first, directly under the title; when S7 rebuilds it as a sheet, "Save workout" should be the
first and prominent choice and "Discard" the last.

**Design fidelity: acceptable, with three things for Pete.** Against `Ledger v2.dc.html:134-149`:
row, dot, time and pill are where the prototype puts them; the time is the spec's 700 15 pt where the
prototype draws 500 14 px (the notes say which wins); the bars are 16 pt under the row for the prototype's 18.
- "Minimize" without its chevron reads as a label more than as a way back. Accept for S4; the notes' plan
  (an optional leading icon on `PillButton` in S6) is right. It should not slip past S6.
- The workout's name as an eyebrow is not in v2. It answers criterion 1, but S5 puts "Exercise 2 of 5", also
  an eyebrow, a few points under it. Pete should look at the two together in S5's screenshots.
- "The current segment wins over done": right. It is what the prototype does (`:578`, `i === exIdx` is
  orange whatever the sets), and it keeps the orange bar and the spoken "Exercise n of m" on the same
  exercise. The implementation is stricter than the prototype for the others (done means every set done, not
  "left of the cursor"), which `cover-past-an-hour-dark.png` shows: the fourth bar is not done while the fifth
  is current. That is the truthful reading of a superset and I would keep it.

**The shell (criterion 9): met.** The modifier is on `MainRoot.body`, above `content`, where the conventions
reserve it; `AppRouter.resolve(_: WorkoutRoute)` is three lines and tested; the Debug row starts the sample
from the sheet's `onDismiss`. `WorkoutRoot` internal: **accept.** Convention 3 already says a feature that
presents itself exports "its presenter and modifier", and `LedgerAppKit` uses exactly `WorkoutLauncher`,
`View.workoutCover(_:onRoute:)` and `WorkoutRoute`. A public `WorkoutRoot` would let the app present the
cover a second way.

**Tests (criterion 10): met, with S4-SF2 and S4-SF4.** Every row L1–L19 and S1–S13 has a test that I could
find by name; the failure rows run on the real host over probed stores, with held calls and no sleep (waits
are `Observations` or a gate). No test compares a whole `WorkoutState` inside `#expect` (they compare ids or
bind a `Bool` first). Names follow §6. Not covered anywhere but by the one UI test: the wiring in
`WorkoutCover` and `WorkoutRoot` (bindings, `onChange` → `onExit` → `onRoute`). Not exercised in the app at
all: "Discard and start new", a failure alert, and kill-and-relaunch into the cover. The first two cannot be
reached until Today asks for a second day; they belong in F09 S5's UI test.

**Size, boundaries, tokens: accept 952.** Nothing here belongs to a later slice: about 150 lines are the
failure states criteria 4 and 5 ask for, about 115 are Debug-only (previews, the sample). `WorkoutRoute.saved`
and its mapping are six lines of the planned surface. `LedgerDomain` gained `checkedCursor` (planned, tested);
`LedgerDesign` gained `DebugMenu.Action` (Debug only). Imports are inside the feature spine; `LedgerFakes` is
imported in two files, both wholly `#if DEBUG`. Tokens only in the views (S4-N5 apart). No lint suppression
was added, and no `project.pbxproj` or test plan changed.

### Rulings I recommend

| Deviation or open question | Recommendation |
|---|---|
| D1 two objects | Accept. |
| D2 `start` synchronous | Accept; fix the plan's block (S4-N6). |
| D3 `WorkoutRoot` internal | Accept. |
| D4 `Text(timerInterval:)` | Accept; criterion 6 supersedes the older line. |
| D5 current wins over done | Accept. |
| D6 the name as an eyebrow | Accept for S4; Pete looks again with S5's page under it. |
| D7 / OQ2 no chevron | Accept for S4; due in S6 with `PillButton`'s icon. |
| D8 system finish dialog | Accept until S7. |
| D12 Minimize disabled during a discard | Accept: the host's discard is two local store calls. Revisit if a discard ever waits on a peer. |
| D15 / OQ3 invisible Cancel | Do not accept as is: S4-SF1. |
| OQ1 VoiceOver and the elapsed time | S6, as proposed. |
| OQ4 "was kept" while an end waits | Leave, as proposed; ADR-004's paragraph first. |
| OQ5 the invented texts | Pete reads the table below before S5 merges. |
| OQ6 `.saved` selects Today | Keep until S7. |
| OQ7 the header at the largest sizes | S5, as proposed; `.accessibility5` has not been drawn by anyone. |

### For the product owner: the invented texts

Seventeen. None is in a screenshot (the alerts were not captured); two are spoken only.

| Text | Shows when | Judgement |
|---|---|---|
| "Elapsed time" | VoiceOver, the header's time | Good. |
| "Workout progress" | VoiceOver, the bars; value "Exercise 2 of 5" | Good. |
| "OK" | every alert's one button | Good. |
| "Couldn't start this workout" | alert title, a start refused | Good. |
| "This day has no exercises yet." | its line, an empty day | Good; "yet" invites the fix. |
| "This day is no longer in your program." | its line, the day or its program is gone | Good. Also said when the whole program was replaced, where it is still true. |
| "Your program's block has ended." | its line, the week is past the block | True but a dead end: it does not say what to do. Consider "Your program's block has ended. Start a new block in Program." once F11 has that action. |
| "Nothing was changed. Try again." | its line, anything else | Good when true; see S4-SF3. |
| "Couldn't start the new workout" | alert title, "Discard and start new" failed | Good. |
| "Your workout in progress was kept." | its line, the old one is still live | Good. Says nothing of why (S4-N4). |
| "Your workout in progress was discarded." | its line, the old one is gone and the new did not start | Honest and blunt, which is right; this is the worst outcome the slice has. Consider adding "Try starting again." |
| "Try again." | its line when the app cannot tell; and under "Couldn't open this workout" | Thin as a whole message, but claims nothing. Fine. |
| "Couldn't open this workout" | alert title (Resume could not read); title on the cover when it loses the session | Good. |
| "Close this screen and try again." | under that title, on the cover | Good. |
| "Close" | the button under it | Good. |
| "Couldn't discard this workout" | alert title over the cover | Good. |
| "It's still in progress. Try again." | its line | Good. |

Tone is consistent (contractions, no blame, no product name, full stops on lines and none on titles).

### For the product owner: what to look at

| Choice | Screenshot | Note |
|---|---|---|
| The conflict dialog has no visible Cancel | `conflict-dialog-light.png`, `conflict-dialog-dark.png` | S4-SF1. |
| The dialog does not name the workout in progress or what discarding loses | the same | "Upper A · 6 of 15 sets logged" as the dialog's message would make the red button an informed choice. Not in the brief; a later slice. |
| The finish dialog: red "Discard" first | `finish-dialog-light.png`, `finish-dialog-dark.png` | Interim until S7. |
| "Minimize" with no chevron | `cover-just-started-*.png` | Due in S6. |
| The name as an eyebrow, in capitals | `cover-after-24-minutes-light.png` | The lifter's own day name is drawn in capitals by `Eyebrow`. |
| Two oranges in light | `cover-after-24-minutes-light.png` | S4-N5. |
| The fourth bar not done while the fifth is current | `cover-past-an-hour-dark.png` | Truthful for a superset; differs from the prototype's colouring by position. |

### The seven points

1. **Module boundaries:** clean; no new edge in `Package.swift` but the target's resources.
2. **Concurrency:** clean; structured work only, injected date and UUID.
3. **Error handling:** nothing swallowed; one line overclaims (S4-SF3).
4. **Design fidelity:** tokens only; matches v2's header but for the chevron, the name and the dot (above).
5. **Accessibility:** five stops pinned at two sizes, 44 pt targets tested; above `.accessibility3` undrawn.
6. **Test quality:** behaviour, not implementation; no sleeps; one weak UI assertion (S4-SF2), one unpinned
   rule (S4-SF4).
7. **Brief compliance:** each of the eleven criteria has a test or a screenshot; criterion 2's relaunch and
   criterion 4's replace path are proven below the UI only.

### What S5 and F09 S5 must be told

**S5 (and S6–S9):**
- Grow the store, never the launcher. No workout is kept outside `workout`, which only `follow()` writes.
- Nothing in `WorkoutStore.init`; no `Task` anywhere in the module (S4-SF4 pins it if taken).
- The intent pump must not write `workout` from a call's return; take the return as the base of the next
  intent only, as the notes say.
- `isBusy` must reach the page's controls, or a set can be logged into a workout that is being discarded.
- S7: `follow()` closes the cover on a finished update today; the cover's own save must not.
- S6: the chevron, and VoiceOver's elapsed value, are both parked on you.

**F09 S5:**
- One launcher, `MainRoot`'s. `start(_:)` and `resume()` are synchronous, and a call made while the launcher
  is working or the cover is up is dropped without a word: do not disable Today's button on the launcher's
  state, there is none public.
- Today need not look at the session before calling: same day resumes, another day asks, a refusal shows its
  own alert.
- The UI test owes what S4 could not reach: the conflict dialog with each choice in the running app
  (dialog down, then cover up, in one go), a start alert, "Resume" tapped straight after "Minimize"
  (S4-N1), and kill-and-relaunch into Resume.
- The plan's surface block is stale (S4-N6); the notes' "Inputs for F09 S5" is the one to read.

**F15 and any other caller of `StartWorkoutUseCase`:** criterion 3 is kept by the launcher looking at the
session before the use case does. A caller without a launcher (the watch, an intent) still meets the refusal
for a live workout whose day was emptied or deleted. The lasting cure is in the use case: look for a
resumable live workout before validating the program.

### What I did not check

- **I ran no build and no test.** Disk had 11 GB free; the tester was changing the tree, and the
  orchestrator's gate on this tree had exited 0. Every claim above is from reading.
- Nothing on a simulator: the dialogs and the cover are judged from the ten committed screenshots (I opened
  four: `conflict-dialog-light`, `finish-dialog-dark`, `cover-after-24-minutes-light`,
  `cover-past-an-hour-dark`) and the code. The four alerts have no screenshot.
- S4-N1 is reasoned, not reproduced. So is S4-SF2's animation path: I did not make the test pass falsely.
- The five snapshot references were not opened; the notes' descriptions of them were taken as given.
- `WorkoutLauncherTests`, `WorkoutLauncherRefusalTests`, `WorkoutPresentationTests`,
  `WorkoutAccessibilityTests`, `WorkoutCopyTests` and `PreviewTests` were read by their test names and
  display names only; the store's, the conflict's and the failure suites were read in full.
- The catalog was not diffed key by key against the copy file: the gate's catalog step does that and passed.
- Coverage, lint, the Release build, watchOS (`DebugMenu` builds there too), and the line count of 952.
- The tester's files, by instruction.

## S6 — review, round 1 (G3 reviewer, 2026-10-10)

Range `main..9dadbe0` on `feat/F10-s6-rest` (one code commit, `bf452eb`, holds everything; three notes
commits follow. Noted, no action). Read: the S6 amendments and the G1 rulings, the brief's criteria 3, 6, 7,
13 and its non-functional section, the notes' "S6 — rest and haptics, as built" and O5, ADR-004's clock
rule, architecture §13's line on the rest timer, every product file of the diff in full, the store's and
the root's files whole, and the tests named below. Nothing was built or run.

**Verdict: changes requested.** One blocking item, and it is the question the orchestrator asked: the
tick. Everything else the slice promises is there and is tested by checks that are real: the Domain's
`shownRest`, the two edits through the one queue, the haptics played once, `.restOver` and its window, the
host's notification effects, the full-width pill. If the orchestrator rules that the tick stays as built,
nothing else blocks.

### Blocking

- **S6-B1. A tick each second rebuilds the whole cover, against the brief's non-functional line; confine
  what reads `moment` to the panel.** `WorkoutStore.swift:57` (`moment`), `:92-101` (`model` reads it),
  `WorkoutRoot.swift:29` (`store.model` read in the root's body), `WorkoutModel.swift:19`,
  `WorkoutPresentation.swift:17,34`. The brief (`F10-active-workout.md:81`) says "no per-second store
  updates"; `docs/architecture.md:320-321` says views render the rest with `TimelineView`. As built,
  `keepRestTime()` writes `moment` each second, `model` reads it, so the root's body runs each second,
  `WorkoutPresentation.screen` rebuilds header, page and panel, and because `send: store.send` is a new
  closure each time SwiftUI cannot skip `WorkoutHeader` or `WorkoutPage` and evaluates every body under
  them. A rest runs for most of a workout, so this is the cover's normal state, and S7 to S9 would build
  their sheets and the block on a root that is invalidated at 1 Hz.
  **Proposed change (option c below):** keep `moment`, `keepRestTime()` and every store test as they are;
  take `rest` out of `WorkoutModel` and `now:` out of `WorkoutPresentation.screen` (it returns to S5's
  signature, and deviation 4 goes with it); give the store `var restPanel: RestPanelModel?` (the one
  reader of `moment`, calling `WorkoutPresentation.rest(_:at:…)` with a date that is not optional); give
  `WorkoutScreen` a slot for the bottom inset, filled by the root with a small view whose body reads
  `store.restPanel`, and by previews and tests with `RestPanel(model:)`. Observation then invalidates that
  one view at a tick and nothing else. Pin it on the host:
  `withObservationTracking { _ = store.model } onChange: { … }` must not fire when a second goes by, and
  must fire for `store.restPanel`. About 25 product lines moved, none added to the count that matters;
  `RestBench.panel` reads `store.restPanel`; `screen_needsAMoment` and `withoutThePanel` go.
  Then amend the brief's line and architecture §13 to what is true: "the rest's time is the store's
  reading of the injected date once a second; only the rest panel reads it".

### The tick: the three ways

| | (a) as built | (b) `TimelineView` in `RestPanel.swift` | (c) `moment` read by the panel only |
|---|---|---|---|
| Code | done; 75 lines in the store | the view computes the model from the timeline's date, so the presentation is called from a view body and the model is no longer "every string final"; the store still needs a task for `.restOver` (one wait to the end); `WorkoutTimeline` gains the timeline's date or an offset | (a) with the reader moved: about 25 lines moved |
| Clocks | one, injected | two for one fact: the view says "Rest over" by the system's clock, the store buzzes and "+30s" judges `extendsShownRest` by the injected one. They agree in the app and part under `-LEDGER_UITEST_NOW` (the rest's `endsAt` is in injected time), unless the offset is carried into the view too | one, injected |
| Tests | every instant is chosen; stepped clock | the inner panel can be pinned through `workoutTimeline.pausedAt`, as S4's header is; the wrapper and the flip to "Rest over" cannot, and the tester's check takes a one-file exemption, which is a precedent | as (a), plus the observation test |
| Each second | root body, whole presentation, every view body under the screen | the panel only; SwiftUI stops the timeline off screen | the panel only |
| Ring | stepped, eased over the second | could be smooth, at the cost of redrawing at the display's rate for minutes | as (a) |

S4's `Text(timerInterval:)` lives with the ambient clock because it is given two injected dates and draws
only digits, with no event at a boundary; `UITestClock`'s comment already records what that costs (the
header reads the offset). The rest panel has a boundary (zero) and two things that must agree with it (the
haptic and "+30s"), which is why (b) is the worse fit here even though the brief named it. **I recommend
(c).** It keeps the ruling's reasons (the injected date, a panel drawn at a chosen instant, the tester's
check unedited) and meets what the brief's line was written to prevent. Taken to the letter the store
still changes once a second; the letter should be amended, not the design.

**Does a tick, as built, disturb anything else?** By reading, no. The steppers are plain buttons with no
held state (`SetRowSteppers`, `StepperField`: no `@State`, no gesture); a button's pressed state, the
scroll position (`@State position`, moved only by `onChange` of the exercise index) and the dialogs'
bindings survive a body evaluation; the tick touches no part of the pump (`queue`, `ahead`, `selection`),
and `moment` written by a tap and by a tick is in both cases the newest reading. The implicit animation is
scoped to `RestReading` by its value (`RestPanel.swift:39`). What I could not see is motion: a dialog up
over a ticking root is exercised only by the nightly `WorkoutRest` (its discard), and nobody watched it.
So (a) is wasteful and fragile for later slices, not wrong today.

**`.restOver` and its one-second window.** Under (a) and (c) it is the code as built, and it is sound: the
wait is on the continuous clock, the date is read again after it, `sawItRun` keeps a reopened cover
silent, `rest == shownRest` after the wait keeps a stale task silent with no suspension point between that
check and the play, and `restPlayedOver` is set before the `await`. A return from the background within a
second of the end still buzzes, half a second late, which is right. Under (b) the store keeps a task
anyway (a view cannot play a haptic without sending an action from its body); one wait to `endsAt` with
the same window would do, so (b) saves the loop and not the task.

### Should fix

- **S6-SF1. Nothing in the PR gate fails if `WorkoutRoot` stops running `keepRestTime()`.**
  `WorkoutRoot.swift:61-63`. Every timing test calls `store.keepRestTime()` itself; only the nightly
  `WorkoutRest` ("counts down by itself") sees the `.task(id:)`. Delete the three lines and the gate is
  green with a panel that never moves. Proposed: one simulator test that hosts `WorkoutRoot(store:)` on
  `RestBench`'s clock, logs a set and expects `clock.sleeps` to rise, then "+30s" and expects it to rise
  again (the id changed).
- **S6-SF2. How much page is left at the largest sizes is not measured.** `RestPanelTests.swift:205`
  (`screen_keepsRoomForThePanel`) shows the inset is at least the panel's height at `.accessibility5`; it
  does not show that anything of the page is visible between the header and the panel. At Accessibility XL
  on 402 × 874 the screenshot shows about 240 pt; the panel grows with the text and a drag that starts on
  it does not scroll (deviation 3), so on 375 pt at `.accessibility5` the lifter may be left with no page
  to drag and only "Skip rest" to get it back. Proposed: measure `scroll.frame.height − panel height` at
  `.accessibility3` and `.accessibility5` on 375 and 402 pt and require at least two rows' worth (say
  120 pt); if it fails, the panel needs a compact form at those sizes (lines beside the ring, or one row
  of buttons), which is look decision 4 and goes to Pete with the number.
- **S6-SF3. The documents still describe the other design.** `docs/architecture.md:320-321`
  ("Views render with `TimelineView`/`Text(timerInterval:)`") and the brief's non-functional line 81 were
  not touched; the diff edits only §11. Whichever way B1 is ruled, both say what is built before merge.
- **S6-SF4. The phone's buzz at zero does not consult `Settings.watchBuzz`.** Spec §4.5: "a WatchKit
  haptic at zero, plus the phone's own haptic; both should honour `watchBuzz`"; `testing-strategy.md:345`
  (D11) expects it. `WorkoutStore+Rest.swift:59-62` plays regardless. The setting has no screen yet and
  defaults to on, so nothing is wrong on screen today. Proposed: no code in this slice; record in the
  notes' inputs which slice owns the gate (the settings feature or F18), so that it is not found by a
  tester later.
- **S6-SF5. The ring is still draining for a second after "0:00" and the buzz.** `RestPanel.swift:27-29,
  39`: every change of `fraction` is eased over one second, the last one too, so the arc's last step
  (12° of a 30 s rest) empties during the second after "Rest over" appears; the notes say it "empties as
  0:00 arrives". Proposed: no animation when `model.isOver`
  (`ringAnimation(reduceMotion: reduceMotion || model.isOver)` or a third case), and the test at
  `RestPanelTests.swift:152` gains that case. Not seen in motion by anyone; say so if it is left.

### Notes

- **S6-N1.** `WorkoutStore+Rest.swift:65`: `date.now != now` is a branch of product code that only a test's
  fixed date with an immediate clock can take. It is the cheapest way not to spin, and its comment is
  honest; leave it.
- **S6-N2.** `WorkoutStore.swift:193,205`: `follow()` now awaits the haptics client before it takes the
  next update. `LiveHaptics` returns at once; a client that waits (the watch's, later) would hold the page.
  Write that on `HapticsClient.play` ("returns promptly") for F18.
- **S6-N3.** `AppComposition.swift:159`: the haptics are bound inside `if let session`. Harmless (no cover
  without a session); it reads as if haptics depended on the host.
- **S6-N4.** `LocalWorkoutSessionActor.swift:195-198`: a `start` onto a kept log goes through recovery and
  so schedules nothing for a snapshot that holds a rest. Rare, and inert while the client is nil; for F23.
- **S6-N5.** Criterion 14's test (`RestPanelTests.swift:152`) checks the function, not that the view uses
  it; the use is one line and read (`RestPanel.swift:39`). Reduce Motion in motion is unverified, as the
  notes say.
- **S6-N6.** `WorkoutCopy+Rest.swift:33`: in a locale with its own digits the line mixes them
  ("Set ٣ · 185 lb × ٥"), because the weight is the Domain's text. S5's rows do the same; one decision for
  all of them when a second language is real.
- **S6-N7.** `LiveHaptics.swift`: generators made at the moment, on the main actor, never prepared. Right
  for sets minutes apart. `.restOver` as `.warning` and `.setLogged` as `.rigid` were never felt.
- **S6-N8.** Standards: no lint waiver, no unstructured task in product code, no `try!`, sizes within the
  limits, nothing compressed. The comments are long but each says a why.

### Criteria

| # | Verdict | On what evidence |
|---|---|---|
| 1 | met | presentation and store tests; `RestPanelPlaceTests`; the four app screenshots |
| 2 | met | `ShownRestTests` through the engine; `shownRest` reads no clock and is total (a rest of no length, dates that are no dates) |
| 3 | met as amended; B1 | `WorkoutStoreRestTimeTests` are real: nothing is read between two seconds, 40 s away, the end while away |
| 4 | met | `zero_playsRestOverOnce` (600 s on), `extend_atRestOver_thenSkip` |
| 5 | met | `WorkoutRestPlanTests`, the store's five |
| 6 | met | Domain, plan and store each pin it; S5's guard tests untouched |
| 7 | met; SF4 | once per update, per rest, across restarts; never felt on a device |
| 8 | met | `HostRestNotificationTests`; the app's own composition runs a rest with no client |
| 9 | met | the six re-recorded references (one opened: light, accessibility3) |
| 10 | met, by the list | no test pins it; the criterion allows a list |
| 11 | met | the catalog's 63 keys; four texts for Pete, one of the brief's unused |
| 12 | met from the tree | `tree_isExactlyTheTable`, 44 pt; VoiceOver not listened to |
| 13 | met at the sizes it names; SF2 | probe sweeps; AX XL screenshots |
| 14 | met by reading; N5 | |
| 15 | met on the implementer's run | not run by me |

### The deviations and the edits

The notes list nine numbered deviations; the orchestrator's message counts eleven. I rule by subject.

| Subject | Ruling |
|---|---|
| Criterion 3 amended, the store ticks (notes 1) | B1: keep the tick, narrow its reader |
| The host takes an optional `NotificationsClient`, nil in the app | **Accept.** A stub that logs a fault at each set would cry wolf. F23 must flip `rest_runsWithoutANotificationsClient` into a test that fails when the client is missing: a default of nil will not tell it |
| Effects run once the envelope is stored and the update is out | **Accept.** Right order. They run inside the host's turn, so F23's client must be quick or the tap's round trip (30 ms budget) pays for it |
| Recovery schedules nothing | **Accept for now.** A pending system notification does outlive the process, so a relaunch mid-rest keeps it. One window stays: killed between the stored envelope and `notify`. F23 should make recovery assert what the recovered state says (schedule when a rest is running, cancel when no workout is live); `scheduleRestOver` replaces, so it is idempotent |
| "+30s" and "Skip rest" send nothing with no rest shown (notes 2) | **Accept.** It is ADR-004's "what the screen showed" |
| The panel is the scroll view's bottom inset; a drag on it does not scroll (notes 3) | **Accept**; SF2 measures its cost |
| `screen(… now: Date? = nil …)` (notes 4) | **Reject the default.** It is exactly an optional that hides a missing argument: a caller that forgets it draws no panel and no test of that caller fails. B1's change removes the parameter; if (a) stays, make it required |
| The date is read per tap and per tick, not at an update | **Accept.** The storm test's reason is sound. The cost (a change from elsewhere drawn at the last reading; one frame with no panel when a cover opens on a rest) is nothing on one phone; F17 must revisit |
| Previews with a logged set show a panel (notes 5) | **Accept** |
| `WorkoutLogging` skips each rest; the scroll-view count (notes 6) | **Accept.** The new check is stronger than the old (one scroll view holds the title, and the cover adds exactly one). That the old one fails on `main` is plausible and **not verified**: no nightly has run since #50, and I ran none. The tester should look at `WorkoutLoggingAdversarial.swift:80` (`scrollViews.firstMatch` may be Today's) |
| `haptics` left `DependencyKeysTests`' list; `withTestDependencies` gives a fresh `FakeHaptics` (notes 7) | **Accept.** `haptics_defaultsToAFreshFake` shows two calls get two fakes and that the key still fails outside; `boot_bindsTheLiveHaptics` starts from the live values and fails on an unbound key. Lost: a store test no longer fails on a haptic nobody expected. Small |
| The brief's VoiceOver announcements not built (notes 8) | **Accept for S6, and write it into S7's criteria** rather than "if wanted": "Rest over" spoken at zero is the only non-visual word a VoiceOver user gets besides the buzz. It needs an injected announcer (posting is ambient), which is its own 30 lines |
| Files split for length; `haptics`, `clock`, `restPlayedOver` lost `private` (notes 9) | **Accept.** The split follows the pump's. `play(_:)` sits in the rest's file though it is the stream's; the file's header says so |
| The tester's file: nine keys added; `scanned` blanks `RestTimer` | **Accept both.** The blanking is the exact spelling, and `testersScan_stillCatchesATimer` is a real control. Under (c) no further exemption is needed |

### By eye

Opened: the four app screenshots, four of the references (panel rest over light, panel resting dark, panel
resting accessibility3 dark, whole screen resting dark), one re-recorded pill gallery (light,
accessibility3), and the v2 prototype's rest card (`design/prototype/Ledger v2.dc.html:219-239`).

- The panel matches the prototype's structure: ring, muted line over the next set, two buttons of equal
  width. The prototype's ring and its "Skip rest" are both `#FF5B22` too, so two oranges on the card is the
  design's. By the brief's criterion 13 the rule is one orange *action* per surface, and it names the rest
  card as a surface of its own: met. With the panel up the cover shows two orange actions (the shown row's
  check ring and "Skip rest"); that is the open S5 question, unchanged.
- In light the check disc and the progress segment are `accentText` (`#B2390E`) and the ring and "Skip
  rest" are `accent`: two different oranges an inch apart. Both are the design system's choices; Pete
  should see them side by side (`app-resting-light.png`).
- "+30s" at 54 pt and 16 pt bold reads as a second primary button more than as the prototype's quiet
  42 px outline. It works; it is heavier than drawn.
- At the default size the panel covers rows 4 and 5 and "+ Add set". With a history line and the fifth
  row shown, the row's check is clear and its steppers are partly under the panel; a sixth row is under
  it. Since "Rest over" stays until dismissed, the panel is always up when the lifter comes back to log.
- At the accessibility sizes: half the screen, the ring alone on its row with empty space beside it, and
  page content showing in the strip under the panel (a cut "1 REP" in
  `app-accessibility-xl-resting-light.png`). "+30s" sits a few points low in its pill beside "Skip rest";
  the other pills do the same at those sizes, so it is the component's, more visible at this height.

### For the product owner

1. The tick (B1), if the orchestrator wants Pete's word on amending the brief's line.
2. Texts the brief does not give: "Resting" (the watch's promise left out), "Add 30 seconds", the kilogram
   line, "Drop set · %@ lb × %lld" and its kilogram form. "Set %lld · next exercise" is unused: the line
   names the next exercise's first set instead. And "Skip rest" is still the button's word at "Rest over",
   where nothing is left to skip.
3. The panel over the rows (above): should the page scroll the shown row clear of the panel when a rest
   begins? I recommend yes, as a follow-up, once Pete has used it.
4. The panel at accessibility sizes (look decision 4), with SF2's number.
5. The two oranges in light; "+30s" as heavy as "Skip rest"; the opaque card with no blur or shadow.
6. Until F23 nothing tells the lifter a rest has ended when the phone is locked, the app is in the
   background or the cover is minimized: the buzz is the cover's alone.
7. `watchBuzz` (SF4), and the haptic patterns, which nobody has felt.

### What I did not check

- **I ran nothing**: no build, no test, no simulator; the tester had the build directory. Every claim is
  from reading and from the committed images.
- That `app.scrollViews.count == 1` fails on `main`; the nightly UI tests; the implementer's run table.
- Motion of any kind: the ring's easing, Reduce Motion, the panel arriving, a dialog over a ticking root.
- The per-second cost in numbers: B1 is argued from how Observation and SwiftUI compare views, not from
  a profile.
- The visible page at `.accessibility5` (SF2) is a concern from arithmetic, not a measurement.
- Seven of the eleven new references and five of the six re-recorded ones were not opened;
  `WorkoutRestPlanTests`, `HostRestNotificationTests`, `WorkoutStoreRestTests` and most of
  `ShownRestTests` were read by their names and first cases only.
- Coverage, lint, the line count of 394, watchOS, and the tester's new files.
