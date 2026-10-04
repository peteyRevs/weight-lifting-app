# Slice S1 review

Reviewer pass (G3) on `feat/F07-s1-keys-fakes` at `87812d2`, diff `git diff a8080ff..87812d2` (63 files). Scope:
ADR-008 and the package graph, `RepositoryError` and its alias, the keys, stubs and `LedgerLogger` in
`LedgerDependencies`, the new `LedgerFakes` module, `withTestDependencies`, `SettingsRepositoryContract`,
`assertLedgerSnapshot`, the new tests and the doc edits. I did not review the adversarial tester's untracked files
(`Adversarial/Fakes*AdversarialTests.swift`), and I changed no code or test.

### What I ran

- **Release build, host:** `env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file` in my
  scratchpad (`f07s1-g3/rel`). **It fails**, in `LedgerTestSupport` only: six errors in `WithTestDependencies.swift`
  (`:59`, `:61`, `:73`, `:76`, `:77`: `InMemoryStores` and `Fixtures` are not in scope). The same command on a
  `git archive a8080ff` copy of main **passes** (38.5 s), so this slice causes it. See SF1.
- **The release build of what the apps link:** `--target LedgerAppKit`, `LedgerWatchAppKit` and `LedgerFakes`
  each build in Release. `nm -gU` on Release `LedgerFakes.o` lists **0** global symbols (the object is 1,264
  bytes), and Release `LedgerDependencies.o` has no symbol naming a fake, a fixture, `InMemory…` or a preview
  value. Every one of the 14 `LedgerFakes` files starts with `#if DEBUG` and ends with its `#endif`, with no
  other conditional. Outside `LedgerFakes`, `LedgerTestSupport` and `LedgerSnapshotTesting`, only
  `LedgerDependencies/Keys/*.swift` names a fake, and only inside `#if DEBUG`.
- **Host tests:** `swift test --filter 'DependencyKeys|UnimplementedStub|PreviewValue|Fixtures|FakeTransport|
  InMemoryContract|SettingsRepository|SnapshotMatrix|WorkoutRepository|StatsQueries|ProgramRepository|
  ExerciseRepository|EventStore'`. **All pass** (119 tests in 22 suites). `DependencyKeysTests` reports 13 known
  issues, one per key, each the library's `@Dependency(\.<key>) has no test implementation` message.
- **The library's default `testValue`** (`swift-dependencies` 1.17.1, `DependencyKey.swift:200-250`): in DEBUG it
  reports the issue naming the `@Dependency` key path, then returns `previewValue`. So an unconfigured key fails
  the test and the test then runs on a seeded fake. That is fine: the issue already failed it.
- **GRDB, to check the fakes where the contracts say nothing:** all four `observe…()` use `.removeDuplicates()`
  and the `stream(in:)` bridge (`ValueObservation+AsyncStream.swift:14`: `.bufferingNewest(1)`, delivered on
  `.task`). `updateSets` and `materialize` soft-delete the replaced set rows, so their ids stay taken, as in the
  fake. `writeMisses` skips a slot that is not stored, as the fake does.
- **Size,** by F05's method (added lines of `git diff -U0` that are neither blank nor whole-line comments). See
  "Size".
- **Not run:** `/code-review` (a separate code-review agent is active in this session), `xcodebuild`, the
  simulators and `scripts/check.sh` (the orchestrator's full gate on `87812d2` is green, with coverage
  `LedgerDependencies` 95.56 % and `LedgerFakes` 98.74 %).

### Blocking

None.

### Should fix

**S1-SF1. `swift build -c release` of the package no longer compiles, and the ADR's rule is broken in its own
diff.**
`LedgerKit/Sources/LedgerTestSupport/WithTestDependencies.swift:59-77`; ADR-008 `:71-72` ("Nothing outside
`#if DEBUG` may name a fake").
- `LedgerFakes` is empty in Release.
- `WithTestDependencies.swift` names `InMemoryStores` and `Fixtures` without `#if DEBUG`, so `LedgerTestSupport`
  fails to compile in Release. Main builds in Release.
- Nothing ships broken: the apps' Release graph builds, and no gate builds `LedgerTestSupport` in Release. But
  the package was buildable in both configurations until now, and a later lane that builds or tests in Release
  (a profiling run, `swift test -c release`, an Instruments session) would break on this. The ADR states the rule
  that would have prevented it.

*Fix:* wrap `WithTestDependencies.swift` in `#if DEBUG` (it is the only file that names a fake). Then check
`swift build -c release` on the host and record the result in the notes. Optionally add one line to the ADR's
Consequences: "`LedgerTestSupport` names fakes only inside `#if DEBUG`".

**S1-SF2. The fakes' streams buffer every value, and GRDB's keep only the newest.**
`LedgerKit/Sources/LedgerFakes/Support/ObservedState.swift:64` vs
`LedgerPersistence/Observation/ValueObservation+AsyncStream.swift:14`.
- GRDB's bridge is `AsyncStream(bufferingPolicy: .bufferingNewest(1))`: "a consumer that falls behind gets only
  the newest".
- `ObservedState` uses `makeStream()`, which buffers without limit, so a slow consumer of a fake sees every
  intermediate value.
- The contracts cannot tell the two apart, because each clause reads `next()` after every write (I checked all
  five observe clauses). A feature store test can. For example, a test that saves twice and expects both values
  passes on the fakes and fails against the database. This is the kind of drift the brief asks the fakes to avoid
  where the contracts say nothing.

*Fix:* `AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))` (one line), and say so in the type's
doc. All five observe clauses still hold, since each one reads after every write.

**S1-SF3. The fakes accept a program whose slots name exercises that are not stored. GRDB refuses it, and product
decision #28 depends on that refusal.**
`LedgerFakes/InMemoryProgramRepository.swift:7-8`, `InMemoryStores.swift:5-6,58-65`; ADR-008 `:34` ("over one
shared state"); `docs/product-decisions.md` #28; F05 input "Seed the catalog before any program is saved".
- `slot.exercise_id` is a foreign key, so `GRDBProgramRepository.save` throws when the catalog has not been
  seeded.
- Decision #28 makes that a user-visible path: "saving a program that names one fails, so F08's onboarding
  offers a retry".
- With `InMemoryStores`, the program store never sees the exercise store, so F08 cannot test its retry on the
  fakes. The doc comment says so, but the ADR and `InMemoryStores` describe the bundle as one database.

*Fix:* either
1. **now (about 15 lines):** give `InMemoryProgramRepository` an optional exercise lookup that `InMemoryStores`
   passes in. A save naming an unknown exercise then throws and stores nothing. Add a
   `ProgramRepositoryContract` clause, "a slot naming an exercise that is not stored is refused, and nothing is
   stored" (any error), which both implementations run; or
2. **hand off:** write it as an F08 input, and correct "over one shared state" in ADR-008 `:34` and the
   `InMemoryStores` doc to say what is linked (workouts → stats, workouts → program misses) and what is not.

I recommend option 1. It is cheap now, and F08 is the next consumer.

**S1-SF4. Standards §4 still forbids what ADR-008 decision 4 allows.**
`docs/engineering-standards.md:101` ("Shared mutable state lives in an `actor`") and `:103` ("no `NSLock` … in
product code"); `LedgerFakes/Support/ObservedState.swift`, `FakeLinkBus.swift:62`.
- The slice edited standards §2 and §7, but not §4.
- `Mutex` is the right tool here (see "Considered and not raised"), and `LedgerFakes` is compiled into Debug app
  builds.
- The next reviewer will flag it, and the next implementer may copy it into a store.

*Fix:* one line in §4: "Exception: `LedgerFakes`' in-memory stores keep their state behind a
`Synchronization.Mutex` so that `observe…()` registers synchronously (ADR-008 decision 4); product stores use
actors."

### Nit

**S1-N1. The live `deviceID` is a quiet nil UUID** (`LedgerDependencies/Keys/DeviceKeys.swift:102-105`,
deviation 6). Every store stub throws, but this one value is used. If S2 ever leaves it unbound, phone and watch
would both stamp events with device `00000000-…`, and `(device, seq)` keys would collide in sync. No code reads it
yet, so this is not a risk in S1. *Fix:* hand off to S2: a test that the composed app's `deviceID` is not the nil
UUID. Optionally add `assertionFailure` beside the fault log, so a Debug run stops on it.

**S1-N2. A preview that needs linked stores cannot use `inMemoryStores(seed:)`**
(`LedgerTestSupport/WithTestDependencies.swift:58-69`; `StoreKeys.swift:102-104` tells previews to bind one
`InMemoryStores` by hand). Features cannot import `LedgerTestSupport`. *Fix (optional):* move a `#if DEBUG`
`DependencyValues.bind(_ stores: InMemoryStores)` into `LedgerDependencies`, and let the test helper call it.

**S1-N3. `materialize`'s slot misses land in a second, separate write** (`InMemoryWorkoutRepository.swift:36-40`).
GRDB writes the workout and the misses in one transaction. A concurrent reader of the fake can see the workout
without its misses, and `observeRecent` yields before `observeActive`. Sequential tests cannot tell. *Fix
(optional):* note it in the type's doc.

**S1-N4. Doc precision.**
- ADR-008 `:52` says `observe…()` yields the current value before it returns "as GRDB's `ValueObservation`
  does". GRDB's bridge delivers asynchronously on `.task`. What GRDB guarantees is that no write after `start` is
  missed, because the first fetch is queued on the writer before any later write. The conclusion stands, but the
  wording should match.
- Architecture §13 (`:443-446`) says every `liveValue` stub "logs at fault level and throws". The six device
  stubs have no methods and log nothing, and `deviceID` returns a value.

**S1-N5. All 17 test targets gain a direct `LedgerFakes` edge to make coverage measurable**
(`Package.swift:188-190`). The edge is honest: test targets already reach `LedgerFakes` through
`LedgerTestSupport`, no app or library target changes, and it is recorded in the graph and the ADR. But it is
tool-driven, and broader than needed. Three suites exercise the fakes (`LedgerPersistenceTests`,
`LedgerDependenciesTests`, `LedgerSyncTests`). *Fix (optional):* narrow the edge to those three, or, when the
test plans are next edited, give `LedgerFakes` its own `LedgerFakesTests` target (the package's "one test target
per source target" rule) and drop the edges.

**S1-N6. No test ends an observation early.** `ObservedState.observe`'s `onTermination`
(`ObservedState.swift:73-75`) removes the observer, but no test cancels a consumer or drops a stream. *Fix
(optional):* a clause-free test that cancels a task iterating `observeRecent`, then writes, and checks the next
write still succeeds and a fresh observer still gets it.

**S1-N7. `FakeLinkBus.advance(by:)` accepts a negative interval** (`FakeLinkBus.swift:119-123`), which moves the
bus's time back. *Fix (optional):* `precondition(interval >= .zero)`.

### Deviations

| Deviation (notes) | Verdict | Reason |
|---|---|---|
| 1. `RepositoryError` moved to `LedgerDomain`, `LedgerPersistenceError` a typealias | **Accepted** | Moved unchanged: the nine cases and their payloads are `Decimal`, `Int` and `String`, with no GRDB or SQLite type. The alias keeps 170 references compiling. The comment at `RepositoryError.swift:9-14` still lists GRDB's `DatabaseError` among the errors that pass through unwrapped. That is prose about one implementation, not a dependency. It is minimal and correct. |
| 2. `Mutex`, not actors | **Accepted** | See "Considered and not raised" for the stream analysis. No `@unchecked Sendable` anywhere in the diff. SF4 is the doc gap. |
| 3. Fixtures promoted as a catalog-id copy; F02's stays | **Accepted** | `FixturesTests.catalogIDs_matchTheBundledCatalog` pins all 16 ids and `benchPress` to `ExerciseCatalog.seed()`. The ids do not collide: weeks 200–207, days 300/310/320/330, slots 301–333, the session, device and program 9001–9003, and history workouts `0x0700_0000 + …`. Exercise and set ids are derived by `SessionBuilder`, so they are deterministic. |
| 4. Fixtures that can fail throw | **Accepted** | `force_try` is an error, and each throwing fixture is exercised by `FixturesTests`. |
| 5. One seeded `InMemoryStores` per key's `previewValue` | **Accepted** | The library caches each key's preview value per process. One shared store would be global mutable state (standards §11). The only cost is that a live preview's write does not reach the other keys' stores. That is documented, and N2 makes the workaround easier. |
| 6. `deviceID` live = nil UUID until S2 | **Accepted** | There is no protocol to stub, and the value cannot throw. N1 is a hand-off. |
| 7. `FakeLiveWorkoutTransport` added | **Accepted** | It is needed for the key's preview value. |
| 8. Bus time and seeded chance | **Accepted** | SplitMix64 per bus, delivered by `(arrival, order)`, so it is fully deterministic. A partition drops a message both at send and at delivery. `sameSeed_sameDeliveries` pins it. |
| 9–10. `withTestDependencies` defaults; `inMemoryStores` reads `date` when called | **Accepted** | The defaults are set before `configure`, so `configure` overrides them (`withTestDependencies_configureOverridesTheDefaults`). Reading `date` inside the setting closure cannot trip the library, because it is set first. |
| 11. No `LedgerFakesTests` target | **Accepted with N5** | |
| 12. `assertLedgerSnapshot` draws per platform; only its matrix is tested | **Accepted** | Its references keep `assertPhoneSnapshot`'s and `assertWatchSnapshot`'s steps. `SnapshotMatrixTests` pins the default matrix to F06's. S3 draws its first images. |
| Every test target → `LedgerFakes` | **Accepted with N5** | |

### Open questions

Category: **(a)** settle now, in this slice or its PR; **(b)** hand off to a later brief or slice; **(c)** Pete
decides.

| # | Question | Recommendation | Category |
|---|---|---|---|
| 1 | Drop the `LedgerPersistenceError` alias later | Agree: keep it as a transition. It costs nothing, and renaming 170 references in this slice would bury the diff. Do a mechanical `chore:` rename right after F07 merges, before F09 and F10 write new code against the old name. | (b) chore PR after F07 S3 |
| 2 | Reword criterion 5's "≥ 70" | Agree. With loss 0.3, 100 Bernoulli trials reach 70 only about 55 % of the time, so "≥ 70" holds for a chosen seed, not for the link. The test pins seed 2026 plus a 200-seed rate check (13,700–14,300, about ±4.6 σ). Reword the brief's criterion 5 to: "a seeded run delivers about 70 % (the 200-seed total within ±5 σ of 14,000), and never a duplicate unless duplication is configured". This clarifies the criterion without changing scope. | (a) orchestrator edits the brief |
| 3 | Repoint `LedgerDomainTests` at `LedgerFakes.Fixtures` | Agree not to. The F02 suites test rules against the prototype's numbers (for example a 180 lb exercise default), which the catalog no longer holds. The local `enum Fixtures` shadows the imported one, and both compile. | (a) settled: no |
| 4 | One shared preview store across keys | Agree not to (deviation 5): it would be global mutable state in Debug. A preview that needs linked stores binds one `InMemoryStores`, which N2 makes a one-liner. | (a) settled: no; N2 optional |
| 5 | Does `LedgerFakes` count as product code under §10? | No: it is test-double code, empty in Release (verified), so the "tests" exclusion applies, as it did for `LedgerTestSupport` in F05. But the PR description should give both numbers (product ≈ 383, `LedgerFakes` 1,175), because every later store test relies on those lines. A one-line note in §10 would settle it for later slices. | (a) PR description; (c) Pete for the §10 line |
| 6 | SF3: link programs to exercises now or in F08 | Now (option 1). | (a), else (b) F08 input |
| 7 | N1: a guard that S2 binds `deviceID` | A test in S2's composition suite. | (b) F07 S2 |

### Considered and not raised

- **`ObservedState` yields while holding the lock** (`ObservedState.swift:53,70`). This is safe, and it is what
  keeps values in order:
  - `Continuation.yield` only appends to the stream's buffer or resumes a waiting consumer by enqueueing it. It
    runs no user code and never calls `onTermination`.
  - The only closures run under the lock are the stores' own value projections.
  - `onTermination` runs on the cancelling thread or at stream deinit, never inside `write`, so it cannot
    re-enter the lock.
  - Yielding after unlocking would let two concurrent writers deliver out of commit order, so a stream could end
    on a stale value.
  - Registration and the first value happen under one lock, so a write after `observe` returns is always the
    stream's next value. Emit-on-change compares with each observer's last value (GRDB's `removeDuplicates()`).
  - Iterating `guarded.observers.keys` while assigning into the dictionary iterates a copy.
- **A dropped store leaves its streams unfinished.** The continuations are released with it, but the streams are
  never finished, so a consumer waits until it is cancelled. GRDB's observation of a closed queue does not finish
  its stream either, and a preview or test cancels its task.
- **`try?` in the seeds and in `PreviewStores.make()`** (`InMemoryWorkoutRepository.swift:25`,
  `InMemoryProgramRepository.swift:36`, `StoreKeys.swift:109`). Each is commented, Debug-only and limited to
  fixture data, and `FixturesTests` proves the fixtures build.
- **Device stubs that neither log nor throw.** The protocols have no methods, so there is nothing to call. The
  file says the brief that adds a method adds its logging stub.
- **`testValue` falls back to the seeded preview stores after the issue** (library behaviour). The test has
  already failed with the key's name, so a follow-on failure cannot hide it.
- **`history(weeks: 8)` holds workouts dated before the program's start** (weeks 0–2 back repeat week 0). This is
  documented in the fixture, and only previews use eight weeks.
- **Each preview key decodes the catalog and builds 29 workouts** (six times per preview process). That is a
  one-time cost per key, cached by the library.
- **`LedgerLogger` exposes `os.Logger` publicly.** Interpolation then keeps each value's privacy, which the doc
  asks for. A wrapper API would lose that.
- **`assertLedgerSnapshot`'s `fileID: … = #file`** matches the existing `assertPhoneSnapshot` and
  `assertWatchSnapshot`, and Swift 6 makes `#file` the file ID.
- **A Release-only `LedgerDependencies → LedgerFakes` edge.** SwiftPM has no configuration condition on target
  dependencies, so an unconditional edge to a Release-empty module is the only option.

### The review points

1. **Module boundaries.**
   - `LedgerFakes` imports Foundation, LedgerDomain and Synchronization only.
   - No feature source imports `LedgerTestSupport` (grep).
   - The spine change does what B1 asked, without collateral: no feature loses an import, and `LedgerAppKit` and
     `LedgerWatchAppKit` are unchanged.
   - `LedgerDomain` gains only `Clients.swift` and `RepositoryError.swift`.
2. **Concurrency.**
   - The keys are internal enums in a `defaultIsolation(nil)` target, and every value is `Sendable` (the
     protocols refine `Sendable`).
   - The stores are `final class`es with `let` properties over a `Mutex`, or an actor.
   - `LedgerLogger` and `Unimplemented` are `Sendable` structs.
   - No `Task {}`, `Task.detached`, `DispatchQueue` or `@unchecked Sendable`.
   - Time is injected everywhere: the stats' `now`, the bus's own clock, and `withTestDependencies`' date, uuid
     and clock.
3. **Error handling.**
   - The stubs log at fault level, naming the key and the method, then throw
     `LedgerDependencyError.unimplemented(key:)`.
   - The fakes throw `RepositoryError` by name, in GRDB's order.
   - SF3 is the one refusal the fakes do not make.
4. **Design fidelity** and 5. **Accessibility.** N/A (no UI). `assertLedgerSnapshot` encodes F06's matrix
   exactly (`SnapshotMatrixTests.defaultMatrix_isF06s`).
6. **Test quality.**
   - The tests are behavioural: each criterion-3 case uses `withKnownIssue`, so a key that failed to fail would
     fail the test.
   - The bus tests are deterministic and seeded, and the stubs test every method.
   - No sleeps: `clock.sleep(for: .seconds(3600))` runs on `ImmediateClock`.
   - Weak spots: N6, and SF2, which the contracts cannot see.
7. **Brief compliance.** Table below.

### Criteria → evidence

| Criterion | Evidence | Verdict |
|---|---|---|
| 3. An unconfigured key fails the test, naming it | `DependencyKeysTests.test_unimplementedDependencyFailsLoudly`: 13 keys, each inside `withTestDependencies`, each a `withKnownIssue` matching `@Dependency(\.<key>)`. I saw the 13 issues on the host. `logger` discards by design (A1): `logger_testValue_discardsWithoutAnIssue`. The library's five keys are set by `withTestDependencies` (`withTestDependencies_fixesTimeIDsAndPlace`) | Met |
| 4. Every contract passes on GRDB and on the `InMemory*` stores | `InMemoryContractTests` runs all six contracts against fresh fakes (workouts and stats over linked `InMemoryStores`). The GRDB suites run the same clauses, and the new `SettingsRepositoryContract` runs on GRDB in `SettingsRepositoryTests.contract_clauseHolds`. Three settings clauses are enough for a single value: defaults, whole replacement with exact plate weights, and emit-on-change including an unchanged save. Unreadable rows are GRDB-only, as the type says | Met; SF2 and SF3 cover what the contracts cannot see |
| 5. Two endpoints, loss 0.3, 100 sent: ≥ 70 received, never a duplicate unless configured | `FakeTransportTests.test_lossy_deliversAtLeast70_neverADuplicate` (seed 2026), `lossyLink_losesAboutItsRate_overSeeds` (200 seeds, total within 13,700–14,300, no duplicate in any), `duplicates_onlyWhenConfigured`. It is on `FakeLinkBus`, which F17's transport will be built on (A1) | Met as worded for one seed; open question 2 rewords it |
| Test plan: `FixturesTests` | The 16 catalog ids, the §6.4 shape, a save round-trip through re-validation, the session, history at 0, 1 and 8 weeks materialised whole, settings, the preview seed | Met |
| 8 (data half). Preview values | `PreviewValueTests`: every key in `.preview` context is a fake, and the stores hold the catalog, the program, 29 workouts and the settings | Met for S1; the render half is S3 |

### Docs

- **ADR-008** is well argued, in the house format: Context, Decision, Alternatives rejected, Consequences. The
  alternatives are the right ones, and the error move is justified (matching by description would let a fake
  drift). Two of its sentences overstate (N4, and "over one shared state", SF3), and one of its rules is broken in
  the diff (SF1).
- **Architecture** is accurate: §2 layout, the §3 diagram text and isolation table, the open question closed with
  B1, §9's `FakeHealthStore`, and §13's key list including `deviceID`. §13 has one imprecision (N4).
- **Standards** §2 and §7 and **testing-strategy** §2.2, §3 rule 6 and §4 thresholds are accurate. §4 needs SF4.
- **`docs/README.md`** lists ADR-007 and ADR-008. **Product decisions** #28–#30 match the notes' B2, B3 and B5.

### Size

By F05's method (added lines of `git diff -U0 a8080ff..87812d2`, excluding blank lines and whole-line comments):

| Path | Added | Removed |
|---|--:|--:|
| `LedgerDomain` (`Clients`, `RepositoryError`) | 16 | 0 |
| `LedgerPersistence` (enum → alias) | 2 | 12 |
| `LedgerDependencies` | 360 | 3 |
| `Package.swift` | 5 | 2 |
| **Product** | **383** | **17** |
| `LedgerFakes` | 1,175 | 0 |
| `LedgerTestSupport` / `LedgerSnapshotTesting` | 111 / 68 | 3 / 0 |
| Tests | 548 | 65 |

- **The notes' ≈ 375 is confirmed.** The 8-line difference is the notes counting `Package.swift`'s comment lines
  differently.
- **Should `LedgerFakes` count as product code?** No, by §10's letter: it is test-double code, compiled into Debug
  builds only and empty in Release (verified above), the same class as `LedgerTestSupport`, which F05 excluded.
  Counted anyway, the PR would be about 1,560 lines, over the ~1,000 split threshold. A natural seam exists
  (keys, stubs and fixtures first; the stores second), but splitting now would only re-review ported code: about
  40 lines are the moved event store, and the history stores are a port of F05's reviewed `HistoryModel`. **No
  split is warranted.** The PR description should state both numbers (open question 5). The fixes add about 20
  lines in total: SF1 2, SF2 1, SF3 about 15 with its clause.

### Verdict

**Approved for G3: 0 Blocking, 4 Should fix, 7 Nits.**
- Criteria 3, 4 and 5 each have a test that fails when the behaviour is wrong. The graph does what B1 asked: the
  features reach fixtures without Persistence, Health or Sync. The Release app graph carries no fake code.
- SF1 (`#if DEBUG` on one file) and SF2 (one buffering argument) are one-line fixes and should land in this PR.
- SF3 is about 15 lines and a clause now, or an F08 hand-off plus corrected wording.
- SF4 is one sentence in the standards.
- G5: this PR carries an ADR (ADR-008) and product decisions #28–#30, so the orchestrator stops for Pete before
  merging, as the gate table requires.

# Slice S2 review

Reviewer pass (G3) on `feat/F07-s2-boot` at `6306b8d`, diff `git diff f991d69..6306b8d` (37 files). Scope:
`LocalDevice`, `LedgerStores`, `MirroringStartRegistrar`, `CompanionSessionActivator`, both compositions, their
`Launch.swift` and root views, `WatchAppDelegate`, the two `App` files, the hosted smoke tests, the doc and
threshold edits and the new tests. I did not review the tester's untracked `LedgerAppKitTests/Adversarial/`, and I
changed no code or test.

### What I ran

- **Host tests** on a `git archive 6306b8d` copy in my scratchpad (`f07s2-g3/copy`), filter
  `LaunchOrder|AppComposition|WatchComposition|LocalDevice|MirroringStart|CompanionSession`. All of the slice's
  suites pass on the host: Launch order, AppComposition, AppComposition · failed launch steps, WatchComposition,
  WatchComposition · failed launch steps, LocalDevice 7 and Mirroring start registrar 4. The activator suite is
  iOS and watchOS only.
- **One probe, added to the copy only (`ReviewProbeTests`).** The first `resume` runs in a task that is already
  cancelled, standing in for a phase change during the first `.task(id: scenePhase)`; then `resume(in: .active)`
  runs, over a database whose settings row holds `units = .kg`.
  - The cancelled pass records `failed(seedCatalog)` and `failed(loadSettings)`, both logged at fault level,
    because GRDB's async read and write throw `CancellationError` in a cancelled task (`DatabaseReader.swift:216`,
    `DatabaseWriter.swift:131`).
  - The `.active` pass re-seeds but **never reloads the settings**: `settings.units == .lb`, and the expectation
    fails. See SF1.
- **`swift-dependencies` 1.17.1 `prepareDependencies`** (`WithDependencies.swift:102-121`,
  `DependencyValues.swift:296-366`): a key already read or cached cannot be prepared afterwards. DEBUG reports an
  issue, and Release silently keeps the old value. See N2.
- **IssueReporting `isTesting`** (`IsTesting.swift`): it reads `XCTestBundlePath`, `XCTestBundleInjectPath`,
  `XCTestConfigurationFilePath`, `XCTestSessionIdentifier` and the test-runner arguments. See open question 3.
- **The two platforms side by side:** `diff` of the iOS and watch `Launch.swift` and composition files with the
  type names normalised. They differ only in the mirroring step, `kind: .phone`/`.watch`, the HealthKit imports
  and doc comments.
- **Size** by F05's method; see "Size".
- **Not run:** `xcodebuild`, the simulators and `check.sh` (the orchestrator's gate on `6306b8d` is green, and its
  Release build exits 0). I did not see either app launch, and I could not check `isTesting` inside an
  XCUITest-launched app.

### Blocking

None.

### Should fix

**S2-SF1. A phase change during the first launch pass leaves the stored settings unloaded for the rest of the
session, and logs two false faults.**
`LedgerAppKit/Launch.swift:95-103` and `LedgerWatchAppKit/Launch.swift` (the same lines), driven by
`AppRootView.swift:26-28` and `WatchRootView.swift:28-30`.
- `.task(id: scenePhase)` cancels the running pass whenever the phase changes. GRDB's async calls then throw
  `CancellationError`.
- `loadSettings` sets `hasLoadedSettings = true` **before** its `await`, so the cancelled load counts as done, and
  no later `.active` reloads it. `composition.settings` then stays `Settings.default` (pounds, Monday) for a lifter
  who saved kilograms. The probe shows it.
- An overlapping pass has the same effect. If the old pass is suspended in `load()` when the new `.active` pass
  arrives, the new pass sees `hasLoadedSettings == true` and skips the load, and the old pass's load is then
  cancelled.
- The seed recovers, since `isCatalogSeeded` is set only on success. But both steps log a cancellation as a
  fault-level failure and record `.failed`, which also misleads decision #30's diagnostics.
- When it happens: a quick background on the iPhone's first launch, and on the watch the first launch the phone
  starts (`handle(_:)`). That launch begins in `.background` and comes to the front while the first seed (224
  rows, far slower on a watch than the simulator's 9 ms) is still running.
- Not Blocking only because nothing reads `composition.settings` before S3. It must not merge as is, because S3
  and F09 build on it.

*Fix:*
1. Set `hasLoadedSettings` only once the load has an outcome other than cancellation.
2. In `seedCatalog` and `loadSettings`, catch `CancellationError` and return without logging or recording a
   failure, leaving the step for the next pass.
3. Add the probe as a test on each platform: an already-cancelled first `resume`, then `.active`, expects the
   stored settings and no `.failed` event.

This is about 6 lines per platform, which is the cost of open question 1's duplication.

**S2-SF2. Standards §4 does not yet allow the registrar's `Mutex`.**
`LedgerHealth/MirroringStartRegistrar.swift:13-19`; `docs/engineering-standards.md:101-104`, whose exception names
LedgerFakes only.
- The design is right. HealthKit calls the handler synchronously on its own queue, and an actor could be reached
  only through an unstructured `Task` after the handler had returned.
- But this is product code, and the standard forbids it as written (open question 2).

*Fix:* widen the exception by one clause, in this PR: "…and product state that a framework callback writes
synchronously on its own queue, where an actor could only be reached after the callback returns
(`MirroringStartRegistrar`)." It widens a standard, so it goes to Pete at the G5 stop, which this PR needs anyway.

### Nit

**S2-N1. `-LEDGER_UITEST` is dead if `isTesting` is true in an XCUITest-launched app**
(`AppComposition.swift:50-56`, `WatchComposition.swift`). `launch()` returns an idle composition before it reads
the arguments. Point-Free's guidance suggests a UI-tested app does not see the XCTest variables, and the notes'
simulator check launched with the argument through `simctl`, not XCUITest. Nobody has observed the case. *Fix
(optional, one condition):* boot when `-LEDGER_UITEST` is present, whatever `isTesting` says. Hosted unit tests
never pass it. Otherwise S3's `launchesToToday` settles it (open question 3).

**S2-N2. A late `prepareDependencies` (#29 recovered on a foreground) is refused for any key read before it.**
`Launch.swift:72-74`. While #29's screen shows, nothing reads a store key today. But if S3's root, Diagnostics or a
store reads one before `state == .ready`, the recovery leaves that key on its stub silently in Release: the app
says ready, and every store call throws `unimplemented`. *Fix:* hand off to S3, so that no view or store reads a
store key unless the composition is `.ready`. Optionally add a DEBUG test that boots unavailable, reads nothing,
recovers, and checks that `prepareDependencies` reported no issue.

**S2-N3. The app's HealthKit hookup is verified only by a manual simulator launch** (deviation 8;
`MirroringStartRegistrar.swift:48-56`). The hosted `Apps/LedgerTests` bundle runs inside the app, with its
entitlement. *Fix (optional):* a hosted test that registers a registrar over its own `HKHealthStore` and expects
`workoutSessionMirroringStartHandler != nil`.

**S2-N4. The registrar keeps every mirrored session for the process's life** (`MirroringStartRegistrar.swift:19,
39-45`). That is harmless for now. *Fix:* an F17 input line: hand each session over and drop it when it ends.

**S2-N5. Doc drift.** Architecture §4's iPhone bullet (`docs/architecture.md:155-157`) still lists WatchConnectivity
registration among the launch-time steps. It now follows the first frame, as the watch bullet already says. The
notes' size table (601 / ≈ 48) does not match F05's method (see "Size").

### Deviations

| Deviation (notes) | Verdict | Reason |
|---|---|---|
| 1. `deviceID` in `LedgerStores` | **Accepted** | One throwing call opens the file and reads the device. `deviceID_isTheDeviceRow` (both platforms) closes S1-N1. |
| 2. `logger` not rebound | **Accepted** | Its live value is already the real logger. |
| 3. `prepareDependencies` in the app only; tests use `withDependencies` | **Accepted** | `preparesDependencies` is `true` only in `Environment.live`, and the harnesses pass `false`. See N2 for the late-recovery case. |
| 4. `isTesting` in `launch()` | **Accepted** | The apps link only the umbrellas. The package suites (`launch_whileTesting_bootsNothing`) and both hosted smoke tests check it. See N1. |
| 5. `.task(id: scenePhase)`: first pass in any phase, then retries only on `.active` | **Accepted in shape, with SF1** | It matches #28 (no background retry) and #29 (retry on the foreground). Its cancellation handling is SF1. |
| 6. Opening on the main actor in `App.init` | **Accepted** | A-decision; the first frame then knows ready or unavailable. F20 times it on a device. |
| 7. Watch opens in `App.init`, not `applicationDidFinishLaunching` | **Accepted** | `App.init` runs earlier, the delegate keeps the workout entry points, and architecture §4 is updated. |
| 8. Generic registrar | **Accepted with N3** | Real HealthKit stays out of package tests (testing-strategy §3). The convenience init is two lines. |
| 9. `Mutex` in the registrar | **Accepted with SF2** | |
| 10. `-LEDGER_UITEST`, a new temporary directory per launch | **Accepted with N1** | |
| 11. Two parallel compositions | **Not accepted as the end state; see open question 1** | |

### Open questions

Category: **(a)** settle now, in this slice or its PR; **(b)** hand off to a later brief or slice; **(c)** Pete
decides.

| # | Question | Recommendation | Category |
|---|---|---|---|
| 1 | Share the launch between the platforms? | **Share the database half now, in `LedgerPersistence`.** No new edge or ADR is needed: both umbrellas already depend on it, and it already owns `LedgerStores`, `LocalDevice`, the settings fallback and the catalog seed (see the sketch below). | (a) |
| 2 | Extend standards §4's `Mutex` exception | Yes, narrowly (SF2). | (c) Pete, at the G5 stop; the orchestrator drafts the clause |
| 3 | Is `isTesting` false in a UI-tested app? | Probably, but unverified. S3's `launchesToToday` and its Diagnostics ≥ 200 rows test fail if it is not; N1 removes the question for one condition. | (b) F07 S3, or (a) with N1 |
| 4 | Fault level for an unreadable settings row | Agree: a later payload version is expected in a mixed-version pair. F14 lowers it to `error` with the resubscription. | (b) F14 |
| 5 | #29 copy: "Can't open your data right now" / "Your workouts are still on this iPhone. Ledger tries again when you come back to it." | The title is decision #29's own. The body is accurate: the file is never touched, and the retry happens on return to the foreground, and it names the device. If Pete wants it plainer: "Ledger will try again when you return to the app." Both stay plain strings until a string catalog exists. | (c) Pete; (b) the localisation brief for the catalog |
| 6 | Size 601 over the 500 target | It complies with §10: over the target, under ~1,000, and the PR names the split it considered. By F05's method it is 573. Sharing (question 1) brings it to about 470. | (a) PR description |
| 7 | (new) Nothing may read a store key before `.ready` | N2. | (b) F07 S3 |

**Question 1 in detail.** The shared part would be a `@MainActor @Observable public final class DatabaseLaunch`
in `LedgerPersistence`.
- It holds `state` (idle, ready or unavailable), `settings`, `isCatalogSeeded` and `stores`.
- `open()` is synchronous and implements #29.
- `resume(isForeground:) async` runs the seed (#28), the settings load and the retries, with SF1's fix.
- `onOpen: (LedgerStores) -> Void` lets the umbrella bind through `prepareDependencies`, and a `record` closure
  reports each event.
- `LaunchStep` and `LaunchEvent` move with it.

Each umbrella keeps only what differs, about 30 lines each: `launch()` with the `isTesting` guard, `boot()` (the
mirroring handler first on iOS, then `open()`), `resume(in: ScenePhase)` (forwards `phase == .active`, then
activates WatchConnectivity once), `bind`, and `Environment.live`.

Why this home:
1. **SF1 lands once, with one test.** Otherwise it lands twice now, and every later fix lands twice too.
2. **#28 and #29 come under a coverage gate.** `LedgerAppKit` and `LedgerWatchAppKit` are excluded from coverage
   (`coverage-thresholds.json`), so today the launch logic behind #28 and #29 has no coverage gate. In
   `LedgerPersistence` it is gated at 90 %, and the recovery tests run once, on the host and both simulators.
3. **No new edge or ADR.** `LedgerDependencies` cannot see `LedgerStores` without one, and every feature imports
   it. A new `LedgerComposition` target needs an ADR for about 100 lines.
4. **Product falls under 500 lines.**

What does not fit the module (WatchConnectivity, HealthKit, SwiftUI's `ScenePhase`, the binding) stays in the
umbrellas. Waiting for F16/F17 does not help: their platform steps belong in the umbrellas either way, and the
database half stays identical. The cost is one `import Observation` and an explicit `@MainActor` type in a
nonisolated module. Record it in architecture §4 with one line.

### Considered and not raised

- **Criterion 6 holds by construction.** `boot()` is synchronous and called from `App.init` (via `@State`'s
  initial value). The handler is first, and it is assigned even when opening fails
  (`boot_handlerFirst_evenWhenOpeningFails`). The registrar is retained by the composition's environment closure,
  which `@State` keeps for the app's life, and so is the WC activator that `WCSession` holds weakly.
- **#29 never touches the file.** `LedgerDatabase.open` creates only the directory. A non-database file refuses
  every write, and the test checks the bytes and the directory listing after a retry. Nothing is bound while the
  database is unavailable (`openFailure_isUnavailable…`, whose `bind` leaves `deviceID` unchanged).
- **A damaged `device` row makes the whole database "unavailable"** (`LocalDevice.id` throws
  `malformedIdentifier` inside `LedgerStores.open`), and the retry never succeeds. It is damage-only, the file is
  still never touched, and F28's repair tooling can own it.
- **#28: no retry in the background, retry on `.active` and on the next launch.** Pinned by
  `seedingFailure_carriesOn_thenRetries`, including `resume(in: .background)` doing nothing.
- **The settings fallback never saves.** The composition calls no `save`, and `unreadableSettings_fallBack_rowUntouched`
  compares the row byte for byte.
- **Binding completeness.** The six stores and `deviceID` are bound. `date`, `uuid`, `calendar`, `locale`,
  `continuousClock` and `logger` keep their real live values. The six device keys keep their logging stubs by
  design until F16–F23. No key is left on a value that is wrong in production.
- **WatchConnectivity activates after the seed and the settings,** not in `App.init`. That is the brief's order,
  it costs milliseconds, and the first pass runs in any phase, so a background launch activates it too.
- **`CompanionSessionActivator` is a `Sendable` `NSObject` without `@unchecked`.** It is final, and its only
  stored property is an `os.Logger`. `sessionDidDeactivate` reactivates, as Apple's watch-switch guidance asks.
- **`HKHealthStore()` and the activator are constructed even under test** (`Environment.live` runs before the
  `isTesting` check). Neither assigns or activates anything until `boot`.
- **`LocalDevice` opens a write transaction on every launch** to read one row. It is one statement, and it makes
  the read-or-insert atomic.

### The review points

1. **Module boundaries.** Clean. Every import was already a graph edge: the package graph is unchanged, and
   HealthKit and WatchConnectivity sit behind `#if os(iOS)` / `#if canImport`.
2. **Concurrency.**
   - The compositions are `@MainActor`, and the registrar and activator are `Sendable` without `@unchecked`.
   - There are no unstructured tasks: async work runs from `.task`.
   - Time and new ids are injected (`Environment.now`, `newID`).
   - SF1 is the cancellation gap, and SF2 the standards gap.
3. **Error handling.** Every failed step is logged at fault level and recorded, nothing is swallowed, and #29 is
   mapped to a user-facing screen. SF1: a cancellation is reported as a failure.
4. **Design fidelity.** #29's screen uses `EmptyState` and `LedgerSpacing.screen` (tokens only), and the watch
   version scrolls. S3 owns the real screens.
5. **Accessibility.** `EmptyState` is F06's component, and the strings are plain text that Dynamic Type sizes.
6. **Test quality.**
   - The tests are behavioural, on real files in temporary directories, with no sleeps.
   - The recovery tests use real causes: a trigger, non-database bytes, a directory in the file's place.
   - Gaps: cancellation (SF1), and the real HealthKit assignment (N3).
7. **Brief compliance.** Table below.

### Criteria → evidence

| Criterion | Evidence | Verdict |
|---|---|---|
| 6. The handler is assigned before any `await` | `boot()` is synchronous, so the compiler enforces it. `LaunchOrderTests.boot_assignsTheHandlerFirst`, `launch_runsTheStepsInOrder` (the brief's five steps), `boot_handlerFirst_evenWhenOpeningFails`, `resume_again_runsNothingTwice` | Met (the real `HKHealthStore` hookup: N3) |
| 1 (data half). The file is in Application Support and the catalog is seeded (≥ 200) | `AppCompositionTests.boot_opensTheFile_andBindsTheStores` (the file at `Database/ledger.sqlite`; the bound repository holds every catalog entry), `liveEnvironment_databaseURL`, `LocalDeviceTests.defaultURL_isItsOwnDirectory`; the notes' simulator check (224 rows, one `device` row) | Met; the UI half (`launchesToToday`) and launch time are S3 |
| 2 (data half). The watch has its own database | `WatchCompositionTests` (kind `watch`, its own order); the notes' watch simulator check | Met |
| #28 | `seedingFailure_carriesOn_thenRetries` (both platforms) | Met |
| #29 | `openFailure_isUnavailable_andTheFileIsUntouched`, `openFailure_retriedOnForeground` (both platforms) | Met |
| F05 inputs (seed once; settings fallback without saving) | `secondBoot_seedsNothing`, `unreadableSettings_fallBack_rowUntouched`, `savedSettings_areLoaded` | Met, except SF1's cancelled pass |
| B4 / S1-N1 (`deviceID` bound, not nil) | `deviceID_isTheDeviceRow` (both), `LocalDeviceTests` (per kind, the oldest of two, a malformed id kept, kept across opens) | Met |

### Size

By F05's method (added lines of `git diff -U0 f991d69..6306b8d`, excluding blank lines and whole-line comments,
doc comments included in the exclusion):

| Path | Added | Removed |
|---|--:|--:|
| `LedgerPersistence` (`LocalDevice`, `LedgerStores`) | 73 | 0 |
| `LedgerHealth` (registrar) | 37 | 3 |
| `LedgerSync` (activator) | 49 | 3 |
| `LedgerAppKit` | 200 | 5 |
| `LedgerWatchAppKit` | 209 | 5 |
| `Apps/Ledger`, `Apps/LedgerWatch` | 5 | 2 |
| **Product** | **573** | **18** |
| Tests (package 824 / 36, hosted smoke 6 / 6) | 830 | 42 |

- **The notes' "601 added, ≈ 48 removed" is not reproduced.** Their per-module figures for Persistence, Health and
  Sync match mine exactly. The umbrellas differ by 5 lines each, and "Apps +23 / −20" probably counts the hosted
  smoke tests or whole files.
- **Either figure complies with §10:** over the 500 target, so the PR description says so and names the split
  considered (iOS then watch), and well under ~1,000. No split is warranted.
- **Sharing the database half** (open question 1) removes about 100 lines and puts the PR under the target.

### Verdict

**Approved for G3: 0 Blocking, 2 Should fix, 5 Nits.**
- Criterion 6 holds by construction and by test. #28 and #29 behave as decided, including the file left untouched
  and nothing bound while the database is unavailable. `deviceID` is the device row, and the package graph is
  unchanged.
- SF1 is a real launch bug (reproduced on the host) with a few-line fix and a test, and should land in this PR.
- SF2 is one clause in the standards, for Pete.
- I recommend doing open question 1 in this PR before SF1, so the fix and its test land once and the launch logic
  comes under the coverage gate. If the orchestrator defers it, SF1 must land on both platforms, each with its test.
- G5: SF2 widens a standard and question 5 is Pete's copy, so the orchestrator stops for Pete before merging.

## S2 fix rounds re-review

A scoped pass over `git diff 6571cca..bce0150` (fix rounds 1 and 2). `9400fea` is a tree-identical merge of
main. I ran no simulator and changed no code or test.

### What I ran

- **Host tests** on a `git archive HEAD` copy (`384ca41`, which carries G2's close-out tests), filter
  `DatabaseLaunch|Preflight|LaunchOrder|Composition|LocalDevice|Closeout`. **All pass**: 105 tests in 24 suites,
  1 known issue from an F07 S1 close-out suite.
  - The suites that pass include `DatabaseLaunch`, `DatabaseLaunch · cancelled and overlapping calls`,
    `LedgerDatabase · preflight`, the tester's open-preflight and launch close-out suites on both platforms, and
    `AppComposition`, `WatchComposition` and `Launch order`.
  - The open-preflight suite takes 5.2 s: its held-lock case waits out the busy timeout.
- **My S2-SF1 probe** (an already-cancelled first `resume`, then `.active`) is covered, on both platforms, by
  `cancelledFirstResume_logsNoFailure` and the F7-S2-3 repro, which now assert the stored settings.
- **Size** by F05's method, `f991d69..bce0150`: product **632 added / 18 removed**, confirmed.
  - Per module: Persistence +230, Health +37 / −3, Sync +49 / −3, AppKit +152 / −5, WatchAppKit +159 / −5,
    Apps +5 / −2.
  - It is over the 500 target and under ~1,000, so it complies with §10 provided the PR description says so.
  - My earlier "about 470 if shared" was wrong. `DatabaseLaunch` (123 lines) is larger than the `Launch.swift` it
    replaced (87), the preflight adds 34, and the compositions kept about 115–132 lines each.

### Prior findings

| Finding | Status |
|---|---|
| S2-SF1 (a cancelled pass leaves the settings unloaded, and logs false faults) | **Fixed, by design.** Each step runs in a task the launch owns, so cancelling a caller cancels no step. A step begins once and always reaches an outcome, and no `CancellationError` can reach `fail`. Pinned on both platforms. |
| S2-SF2 (standards §4) | **Fixed.** `engineering-standards.md:101-107` narrows the exception to state a framework callback writes synchronously on its own queue (Pete, 2026-10-04), and the registrar's doc cites it. |
| Open question 1 (share the launch) | **Done** as `LedgerPersistence/DatabaseLaunch.swift`, with no new edge. #28, #29 and the settings fallback are now under `LedgerPersistence`'s 90 % gate. |
| N1 (`-LEDGER_UITEST` vs `isTesting`) | **Fixed:** `AppComposition.swift:76-78` and the watch twin. See N-c. |
| N2, N3, N4 | **Handed off** in the notes: to S3, F16 and F17. |
| N5 (architecture §4) | **Fixed:** `docs/architecture.md:154-164`. |

### Judgement

**`DatabaseLaunch`: correct and about as simple as the requirement allows.**
- **Ownership.**
  - `task(for:retrying:)` (`DatabaseLaunch.swift:125-143`) checks and starts a step in one main-actor turn, so two
    calls cannot start a step twice. A caller that finds a step running awaits that same task.
  - `running` holds a task only while it runs, and `ended` makes "run once, retry only the seed, only in the
    foreground" a plain set test.
  - The tasks are plain `Task {}` on the main actor, not `Task.detached`. They are owned and awaited, not
    fire-and-forget, which is the only kind standards §4 forbids.
- **Lifetime.** Each step's closure holds `self` strongly, and `running` holds the task. The cycle lasts only
  until the step ends, when `running[step] = nil` releases the task and its closure. So no leak persists. A
  composition dropped mid-step lives until the step ends: one GRDB call, bounded by the seed's duration plus the
  5 s busy timeout.
- **Teardown.** A process killed mid-seed loses only an uncommitted transaction, which the WAL rolls back, and
  the seed's version stays unapplied for the next launch (#28).
- **State machine.**
  - The open is retried only when a call is not the first, is in the foreground, and finds the database
    unavailable (`:107-109`).
  - The seed is retried only in the foreground and only while unseeded (`:114`).
  - The settings load runs once (`:118`), as decided.
  - A database that opens only on a later retry seeds and loads on that same call (`openFailure_retriedOnForeground`).

**The preflight's acceptance rule is right** (`Database.swift:57-84`).
- A missing or empty file is a new database.
- A file is accepted only if it holds `grdb_migrations` with identifiers this build knows, or no schema object
  at all.
- It refuses, with no write: anything SQLite cannot read, a foreign SQLite file (`notLedgerDatabase`), and a later
  schema (`laterSchema`, a TestFlight downgrade).
- It reads through SQLite, so WAL frames count.
- What it lets through and later fails (a damaged Ledger file whose `device` table is missing) still writes
  nothing.
- `LedgerStores.open`'s doc correctly states the one residue: migrations committed before a later one fails stay
  applied, which is GRDB's per-migration commit.

**The busy timeout on the main actor is acceptable now.**
- Today no other connection exists at launch: the preflight's reader closes (`defer`) before the main queue
  opens.
- The 5 s worst case appears only when another process holds the lock, which F21's widget extension will
  introduce. The notes hand that to F21 (short extension writes) and F20 (time a contended launch on a device).
- The 5 s stays far below the launch watchdog. A shorter timeout for the launch open alone would only turn a wait
  into decision #29's screen.

**The compositions (about 115–132 lines each) could shrink, but only a little** (N-b).

### Blocking

None.

### Should fix

None.

### Nit

**S2-N-a. A downgrade shows a #29 screen that never recovers** (`Database.swift:79-82`, `OpenError.laterSchema`).
"Ledger tries again when you come back to it" is false until the app is updated, and only a TestFlight tester can
reach this. *Fix (optional):* when S3 or the localisation brief adds the string catalog, give `laterSchema` its own
line ("Update Ledger to open your data"). That is (c) Pete's copy.

**S2-N-b. Cheap trims in the compositions (about 15–20 lines each).**
- Make `database` public and read `composition.database.state` in the root views. That drops the four forwarders
  (`AppComposition.swift:47-63` and the watch twin).
- Move `boots(arguments:isTesting:)` and the `-LEDGER_UITEST` URL choice (`:76-78`, `:148-150`) into
  `LedgerPersistence`, for example `LedgerStores.launchURL(arguments:)`.
- `bind` has to stay in each umbrella: `LedgerPersistence` cannot see `DependencyValues` without a new edge.
- Optional, and not worth a gate run alone.

**S2-N-c. If `isTesting` were ever true in a UI-tested app, booting is not the whole story.** swift-dependencies
would also run in its `.test` context. Every key not prepared (the device keys) would then report an issue and
fall back to its preview fake. The premise is still unverified, and S3's `launchesToToday` settles it. If it holds,
prepare `$0.context = .live` along with the stores.

**S2-N-d. Say why the step tasks are unstructured** (`DatabaseLaunch.swift:100-102`, `:136`). The doc explains the
behaviour. One clause naming F7-S2-3 ("a step must outlive a cancelled `.task`") would stop a later reviewer from
"fixing" it back into the caller's task.

### Verdict

**Still approved for G3: 0 Blocking, 0 Should fix, 4 Nits.** Both prior Should-fix findings are fixed, the shared
launch is correct and under the coverage gate, and the preflight's rule is sound. The G5 stop for Pete stands only
for the #29 copy (open question 5, and N-a if he wants it); his §4 decision is already recorded.

# Slice S3 review

Reviewer pass (G3) on `feat/F07-s3-roots` at `c9b978a`, diff `git diff 2ca2317..c9b978a` (50 files). Scope: the
roots and Today placeholders, `DebugMenu`, `DiagnosticsPage` and the loader, the umbrellas' diagnostics,
`DatabaseDiagnostics`, `HealthAuthorization`, `ProcessStart` and launch-to-first-frame, the preview registries,
`PreviewScan` and `renderPreview`, the UI tests, the snapshots, the M0 screenshots and the doc edit. I changed no
code or test, and I ignored the tester's untracked files.

### What I ran

- **Host tests** on a `git archive c9b978a` copy, filter
  `PreviewTests|DiagnosticsTests|TodaySnapshot|DatabaseDiagnostics|HealthAuthorization|ProcessStart|AppComposition|WatchComposition|LaunchOrder`.
  All of the slice's suites pass: both apps' Diagnostics, Previews and Today snapshot suites (the snapshot suites
  draw no cell on the host), Database diagnostics, Health authorization, Process start, and the composition and
  launch-order suites.
- **One probe, in the copy only.** `renderPreview` of a view that reads `@Dependency(\.programRepository)` records
  "`@Dependency(\.programRepository)` has no test implementation". See SF1.
- **The M0 screenshots,** looked at: `watch-today.png` is "Today" on the watch ground. `iphone-diagnostics.png`
  shows the UI test's temporary file, a device UUID, "Not determined", 2280 ms, "live", and 224 `exercise` and 2
  `grdb_migrations` rows.
- **The test plans:** `PR` and `PR-Watch` select `Smoke` only in the UI targets, and the Nightly plans run every UI
  test.
- **Size** by F05's method; see "Size".
- **Not run:** `xcodebuild`, the simulators and the UI tests. The orchestrator's gate is green, its Release build
  exits 0, and the notes' Nightly UI runs pass.

### Blocking

None.

### Should fix

**S3-SF1. `renderPreview` draws in the test context, so the first preview that reads a dependency fails the smoke
test instead of using its preview value.**
`LedgerKit/Sources/LedgerSnapshotTesting/PreviewRendering.swift:11-28`, called by every
`PreviewTests.preview_renders`.
- Xcode runs a `#Preview` in swift-dependencies' `.preview` context, where S1's keys give their seeded fakes.
- The smoke test runs in `.test`, where every key's default `testValue` reports an issue. The probe shows it on
  `programRepository`.
- S3's previews read no key, so nothing fails yet. But F08–F15's store-driven previews (the reason S1 built the
  `previewValue`s) would fail criterion 8's test for a reason unrelated to the preview. The obvious workaround,
  binding keys by hand in each test, defeats "renders as the preview does".

*Fix* (about 3 lines plus a test):
1. Build and draw the view inside `withDependencies { $0.context = .preview } operation: { … }`.
2. Add one `renderPreview` test whose view reads a store key and expects no issue.
3. Optionally, one line in testing-strategy's preview section.

### Nit

**S3-N1. `DesignPreview` ships in Release** (`LedgerDesign/Components/Components+Previews.swift:6-97`).
`AppPreview` and `WatchPreview` are inside `#if DEBUG`, but LedgerDesign's registry, and the galleries it names, are
not. F06's `#Preview`s were ungated before, so this is consistency rather than a regression. *Fix (optional):* wrap
the file's registry in `#if DEBUG`, as the umbrellas do.

**S3-N2. The scan checks names, not bodies** (`LedgerTestSupport/Previews/PreviewScan.swift:32-49`). A
`#Preview("Today") { SomethingElse() }` passes `registry_listsEveryPreview`, while the smoke test renders the
registry's `TodayPlaceholder`. *Fix (optional):* the scan also requires the declaration's body to contain
`.<case>.content`. Or leave it to code review, since the pattern is visible at every `#Preview`.

**S3-N3. The committed Diagnostics screenshots carry the Mac's absolute simulator path**
(`screenshots/iphone-diagnostics.png`: `/Users/…/CoreSimulator/…`). Harmless in a private repo. If the repository is
ever public, retake them with a plain launch, whose path is the container's.

**S3-N4. The watch's #29 screen sits in a bare `ScrollView`** (`LedgerWatchAppKit/WatchRoot.swift:44-49`), and the
iPhone's has `.background(LedgerColor.ground)`. The watch's ground is black by default, so nothing is visible, but
the iPhone version paints its ground explicitly and the watch's doesn't. Add `.background(LedgerColor.watchGround)`
for symmetry.

### Questions 1 and 2

**1. The debug menu and Diagnostics page in `LedgerDesign/Gallery` (deviation 2): accept.**
- `LedgerDesign` is the only UI module both umbrellas import. A feature module can't host it, because
  `LedgerWatchAppKit` sees none of the iOS features.
- What moved there knows no Persistence, Health or Dependencies type. `DiagnosticsPage` is a list of label/value
  strings (a component), and `DebugMenu` is two rows into `DesignGallery`, which was already Debug-only in that
  module.
- The domain knowledge stays in each umbrella (`AppComposition+Diagnostics.swift`, about 34 lines each), which is
  where the brief's `LedgerAppKit/DebugMenu.swift` wanted it.
- Everything is under `#if DEBUG`, and Release builds.
- The alternatives without new targets are per-umbrella copies of the page and menu: about 120 duplicated lines,
  as the notes measured (649 against 560).
- A rename to make the generality explicit (`DiagnosticsPage` → a generic "label/value page") is not worth it now.

**2. Criterion 8's mechanism (registry, scan, `renderPreview`): proportionate and robust; keep it.**
- **Why a registry.** Swift gives tests no way to enumerate `#Preview`s. The alternatives are a runtime scan of the
  macro-generated `PreviewRegistry` conformances, which is heavier and tied to an Xcode-private shape, or
  re-rendering only what the snapshot suites cover, which misses previews.
- **Cost per new preview.** One enum case plus `.content` in the `#Preview` body: 2–3 lines, about 155 product
  lines across the three modules so far.
- **Robustness.**
  - The scan fails loudly in three cases: an unregistered preview, an unnamed one, and a module with previews but
    no registry (`everyModuleWithPreviews_isRegistered`).
  - Its line rule (a declaration starts a line, with an optional literal name) is pinned by `scan_parsesDeclarations`.
  - `renderPreview`'s iOS window path avoids the `ImageRenderer` release trap, which is a SwiftUI quirk, not a design
    flaw.
- **Maintainability for F08–F15** needs SF1, and N2 is optional.
- **A lighter design that still meets "every `#Preview` renders"** would be one registry per module without the
  scan. It saves about 60 lines of test support, but loses the guard that makes the registry complete, so it is
  not worth it.

### Correctness

- **State → view** (`AppRoot.swift:24-38`, `WatchRoot.swift`): `.ready` → Today (with the sheet in Debug),
  `.databaseUnavailable` → #29's screen, `.idle` (only a process hosting unit tests) → the ground. Today, and so the
  debug menu, exists only once the database is open.
- **No early key reads (S2-N2): holds.**
  - Today reads nothing.
  - Diagnostics reads `composition.stores`, never a store key. `diagnostics_readTheCompositionsStores` runs with no
    key bound, so a key read would fail it by name.
  - The only dependency read is `@Dependency(\.context)`, which `prepareDependencies` never sets, and it happens
    after `.ready`.
- **Launch-to-first-frame (#30) is recorded once.** `rootAppeared()` is guarded by `launchToFirstFrame == nil`
  (`AppComposition.swift:109-117`), so a later appearance (state change, scene reconnect) does not overwrite it, and
  `rootAppeared_measuresOnce` pins that. It runs in Release too and logs at notice level, as #30 wants. It starts at
  the kernel's process start, so dyld, `App.init` and the synchronous open count.
- **The Health probe never asks.** `HealthAuthorization.workouts()` reads `isHealthDataAvailable()` and
  `authorizationStatus(for:)` only. It is evaluated only when Diagnostics opens, in the app.
- **Debug-only code is absent from Release.** `DebugMenu`, `DiagnosticsPage`, the loader, the umbrellas'
  `diagnostics()`, the `.sheet` and `.onLongPressGesture` are all under `#if DEBUG`, and the orchestrator's Release
  build exits 0. The exception is `DesignPreview` (N1).

### UI tests

- **The PR/Nightly split is right for the CI budget.**
  - PR `Smoke.test_launchesToToday` (about 6 s per platform) fails on any regression that keeps the app from
    reaching `.ready`: an open failure shows #29's screen, which has no `today.title`.
  - A seeding or settings regression still reaches Today, but the package suites catch it on every PR
    (`AppCompositionTests`, `DatabaseLaunchTests`, `DiagnosticsTests`).
  - The Nightly `DebugMenu` tests add the on-screen proof: ≥ 200 rows, `live`, a non-nil device id, and the path.
- **The identifiers** (`today.title`, `debug.menu.*`, `debug.diagnostics.*`) follow §2.7's dotted form. They are
  strings because the UI targets link no package product (open question 2).
- **`LaunchPerformance`** uses a new temporary database on each of its five launches, so it measures first-launch
  work (migrations) every time. That is pessimistic and consistent, and it reports only (#30).
- **What none of them check:** criterion 1's "in Application Support". The UI tests use the temporary file. It is
  covered by the package's `liveEnvironment_databaseURL` and the notes' plain `simctl` launches (the
  `iphone-today` and `watch-today` screenshots).

### Deviations

| Deviation (notes) | Verdict |
|---|---|
| 1. `isTesting` false under XCUITest (S2-N-c settled, the context pinned by the UI tests) | Accepted |
| 2. Debug UI in `LedgerDesign/Gallery` | Accepted (question 1) |
| 3. Diagnostics reads the composition's stores | Accepted: the strongest form of S2-N2 |
| 4. First frame ends at the root's first `onAppear` | Accepted |
| 5. `health` a defaulted parameter | Accepted: the package host has no entitlement (S2 deviation 8) |
| 6. The page draws, a loader reads; iOS renders in a window | Accepted: it is SwiftUI's trap, and the split matches F09's store-driven screens |
| 7. One page in watch type | Accepted |
| 8. `DebugMenu` UI tests Nightly only | Accepted (open question 5) |
| 9. `.idle` renders the ground | Accepted |

### Open questions

Category: **(a)** settle now, in this slice or its PR; **(b)** hand off to a later brief; **(c)** Pete decides.

| # | Question | Recommendation | Category |
|---|---|---|---|
| 1 | The XCUITest launch figure (about 2.5 s) against the lifter's launch | Agree: report only. F20 times a plain cold launch on a device, and F26 gates it. | (b) F20 / F26 |
| 2 | Testing-strategy §2.7 drift | One line each: `Launch.coldLaunchUnder600ms` → `LaunchPerformance.test_launchToFirstFrame` (reports, #30); the watch's `Smoke.launchesToIdle` → `launchesToToday` until F18; identifiers are strings because the UI targets link no product (replacing the "link the umbrellas, share enums, verify in F01" sentence). | (a) orchestrator, docs |
| 3 | Previews with an appearance action | Agree: previews draw a state, and the root loads it. Add that line to testing-strategy beside SF1's. | (a) docs, with SF1 |
| 4 | Debug menu in `LedgerDesign` | Accept (question 1). | (a) |
| 5 | `DebugMenu` UI tests in PR? | No: Nightly only, as now. | (a) |
| 6 | The watch Diagnostics' long path | Leave it: Debug only, and it scrolls. A middle-truncated path would be the cheap fix if it bothers. | (a) leave |
| 7 | Size 560 over the 500 target | It complies with §10 (see "Size"). The PR description says so and names the split it considered. | (a) |

### Considered and not raised

- **The roots and the diagnostics builders are near-twins across the umbrellas** (about 100 lines). The graph
  forces it: no module both umbrellas import can see the compositions, SwiftUI, LedgerHealth and LedgerDesign
  together. Sharing would need a new target, which is not worth it for placeholders that F09 and F18 replace.
- **The `isDebugMenuShown` state and the `TodayPlaceholder` closure exist in Release** and do nothing there, since
  the gesture is compiled out. That costs one `@State` and keeps the call sites free of `#if`.
- **`ProcessStart` reads `sysctl(KERN_PROC_PID)` for its own process,** which is permitted. It returns nil rather
  than guess, and Diagnostics then says "Not measured".
- **`DatabaseDiagnostics` counts every table** in one read with quoted identifiers. Debug-only, on demand.
- **`.onAppear` on a conditional root** may fire again when the state changes, but the guard makes that harmless.

### Size

By F05's method (`git diff -U0 2ca2317..c9b978a`, excluding blank lines and whole-line comments):

| Path | Added | Removed |
|---|--:|--:|
| `LedgerAppKit` | 127 | 26 |
| `LedgerWatchAppKit` | 126 | 27 |
| `LedgerDesign` | 228 | 31 |
| `LedgerPersistence` / `LedgerHealth` / `LedgerDependencies` | 37 / 26 / 13 | 0 |
| `Apps/*`, `Package.swift` | 3 | 3 |
| **Product** | **560** | **87** |
| of which `*+Previews.swift` | 147 | |
| `LedgerTestSupport` / `LedgerSnapshotTesting` | 41 / 25 | 0 / 1 |

- **560 added is confirmed.** The notes' 36 removed treats `AppRootView` → `AppRoot` and `WatchRootView` →
  `WatchRoot` as renames. `git diff` without rename detection counts the old files' 51 lines as removed. Either way
  the net is under 525.
- **It complies with §10:** over the 500 target, under ~1,000, the split considered is named, and about 147 lines
  are preview registries. No split is warranted.

### Verdict

**Approved for G3: 0 Blocking, 1 Should fix, 4 Nits.**
- Each part of criteria 1, 2, 7 and 8 (and the DoD screenshots) has a test or a screenshot. S2-N2 holds by
  construction, #30 is measured once and logged in Release, the Health probe never prompts, and every Debug-only
  surface is compiled out of Release.
- SF1 is a 3-line fix that keeps criterion 8's mechanism usable for F08–F15, and should land in this PR.
- G5: this slice carries no new ADR or product decision. Open question 2 is a docs edit for the orchestrator.
