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
