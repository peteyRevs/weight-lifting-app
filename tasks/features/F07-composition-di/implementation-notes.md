# F07 — implementation notes

## Slice plan (orchestrator, 2026-10-03)

From a read-only planning pass against main `a8080ff`. Product code lines exclude tests, `LedgerTestSupport`,
`LedgerSnapshotTesting`, test plans, docs and comments, as F05 counted.

| Slice | Contents | Criteria | Est. | Depends on |
|---|---|---|---|---|
| **S1** keys, stubs, fakes, fixtures (`feat/F07-s1-keys-fakes`) | Client protocols `HapticsClient`, `NotificationsClient`, `LiveActivitiesClient` in `LedgerDomain` (empty, like `HealthStore`); `LedgerDependencies`: 14 custom keys + the library's 5, `Unimplemented*` stubs (log at fault level; throw `LedgerDependencyError.unimplemented(key:)` or no-op), `LedgerLogger` (`Sendable` struct over `os.Logger`); **new `LedgerFakes` target** (decision B1 below) with the in-memory stores (exercise, program, settings, event store moved from `LedgerDomainTests`, workout + stats ported from the adversarial `HistoryModel` without its faults), fixtures (promoted from `LedgerDomainTests/Support/Fixtures+Program.swift`, catalog ids), protocol-free `FakeLinkBus` (criterion 5), empty-conformance Health/Companion/client fakes; `previewValue`s seeded from `LedgerFakes`; `withTestDependencies` from `testValue` with fixed date/uuid/clock/calendar/locale and an `.inMemoryStores(seed:)` preset; `assertLedgerSnapshot` in `LedgerSnapshotTesting`; a `SettingsRepositoryContract`; every contract run against GRDB and the fakes. ADR-008 + recorded package graph. | 3, 4, 5 | ~370 + LedgerFakes | main |
| **S2** both apps boot on a real database (`feat/F07-s2-boot`) | `LocalDevice` (read-or-insert the `device` row), `LedgerStores` (queue + six GRDB repositories given `now`), `MirroringStartRegistrar` (`LedgerHealth`, `#if os(iOS)`), `CompanionSessionActivator` (`LedgerSync`, `#if canImport(WatchConnectivity)`), `Launch` (ordered steps, injected recorder, synchronous `boot()`), `AppComposition` / `WatchComposition` / `WatchAppDelegate`, `Apps/*App.swift` (`isTesting` guard). Open failure → decision #29 screen; seed failure → decision #28. | 6; data half of 1, 2 | ~460 | S1 |
| **S3** roots, Today, debug menu, UI tests (`feat/F07-s3-roots`) | `AppRoot`/`WatchRoot` with `.task` for the async steps, Today placeholders, `DebugMenu` (`#if DEBUG`, long-press on the title) → `DesignGallery` + Diagnostics (DB path, row counts, device id, Health auth, launch ms — decision #30), UI tests (`launchesToToday`, Diagnostics ≥ 200 rows, `LaunchPerformance` nightly), preview registry + source scan (criterion 8), Today snapshots. | 1, 2, 7, 8 | ~350 | S2 |

## Decisions (2026-10-03)

**Pete:**
- **B1 — preview data lives in a new small module** (`LedgerFakes`: depends on `LedgerDomain` only, compiled `#if DEBUG`), so `previewValue`s are seeded fakes and `LedgerTestSupport` leaves the features' spine. Needs ADR-008 and the package graph re-recorded (`scripts/check-package-graph.sh --record`). Closes the open question in `docs/architecture.md` §(package graph).
- **B2 → product decision #28** (seeding fails: log, carry on, retry).
- **B3 → product decision #29** (database can't open: static screen, never touch the file, retry on foreground).
- **B5 → product decision #30** (launch time measured and shown, enforced on device later).

**Orchestrator:**
- **B4 — device id without the Keychain is accepted:** "this device" is the single `device` row of this platform's kind; a restore from backup inherits the old id, a reinstall gets a new one.
- **A1–A11 as planned:** keys and stubs in nonisolated `LedgerDependencies` (never in a MainActor-default target); library default `testValue` (fails naming the key), `logger`'s discards; `withTestDependencies` starts from `testValue`, not `previewValue` (the brief contradicts criterion 3; criterion 3 wins); snapshot wrapper in `LedgerSnapshotTesting`; criterion 5 via a protocol-free `FakeLinkBus` (F17 owns the transport protocol); the database opens synchronously in `App.init` (4.6 ms on the watch simulator), seeding/settings/WC after the first frame; registrar in `LedgerHealth`, WC activator in `LedgerSync`; `isTesting` guard + a UI-test launch argument for a fresh temp database; debug menu on long-press only; criterion 8 as a preview registry + source scan; docs drift fixed (architecture §13 `deviceID`, §14 Diagnostics, `testing-strategy.md:251`, F09:31, F17:32,36, brief's §6.3 → §6.4).

## Slice S1 — keys, stubs, fakes, fixtures (G1 implementer, 2026-10-03)

Branch `feat/F07-s1-keys-fakes`, from `a8080ff` + `e7e47ae`. No commits (orchestrator commits).

### What landed

- **ADR-008** (`docs/adr/ADR-008-ledger-fakes-module.md`): the `LedgerFakes` target (B1) and the error move below.
  Architecture §2 (layout), §3 (diagram text, isolation table; the open question is closed), §9 (`FakeHealthStore`)
  and §13 (keys, `deviceID`, what each value is) updated; standards §2 and §7, testing-strategy §2.2, §3 rule 6
  and §4 (thresholds), `docs/README.md` (ADR list) too.
- **Package graph** (`LedgerKit/Package.swift`, re-recorded `package-graph.expected.txt`; checker passes):
  - new `library LedgerFakes: LedgerDomain`;
  - `LedgerDependencies: Dependencies, LedgerDomain, LedgerFakes` (was without `LedgerFakes`);
  - every feature's spine swaps `LedgerTestSupport` for `LedgerFakes` (8 targets);
  - `LedgerTestSupport` gains `LedgerFakes`. No feature target imported `LedgerTestSupport`, so none lost
    anything (checked with `grep`).
  - every test target gains a direct `LedgerFakes` edge (beyond B1's text, test targets only): the first full
    gate failed the coverage gate with "LedgerFakes: no lines measured", because Xcode reports coverage only for
    a test target's direct dependencies (the report listed `LedgerDomain` files under `LedgerDomainTests` alone,
    and `LedgerFakes` under none).
- **LedgerDomain:** `Protocols/Clients.swift` (`HapticsClient`, `NotificationsClient`, `LiveActivitiesClient`,
  empty and `Sendable`); `Protocols/RepositoryError.swift` (moved, see deviation 1).
- **LedgerPersistence:** `LedgerPersistenceError.swift` is now `public typealias LedgerPersistenceError =
  RepositoryError`.
- **LedgerDependencies** (placeholder deleted): `Keys/StoreKeys.swift` (6 store keys), `Keys/DeviceKeys.swift`
  (health, 2 transports, 3 clients, `deviceID`, `logger`), `Unimplemented/` (the `Unimplemented` helper and a stub
  per protocol), `LedgerLogger.swift` (`Sendable` struct over `os.Logger`: `log`, `isEnabled`, `.disabled`,
  `category(_:)`), `LedgerDependencyError.swift`.
- **LedgerFakes** (all `#if DEBUG`): `InMemoryExerciseRepository`, `InMemoryProgramRepository`,
  `InMemorySettingsRepository`, `InMemoryWorkoutEventStore` (moved from `LedgerDomainTests/Engine/Support`,
  renamed, `git mv`), `InMemoryHistory` + `InMemoryWorkoutRepository` + `InMemoryStatsQueries` (ported from
  `HistoryModel{,+Repositories,+Stats}` without the faults), `InMemoryStores` (+ `Seed.empty`, `Seed.preview()`),
  `Support/ObservedState.swift` (the `Mutex` + observers every store shares), `Fixtures/` (`Fixtures`,
  `+Program`, `+History`), `FakeLinkBus`, `DeviceFakes.swift` (`FakeHealthStore`, `FakeLiveWorkoutTransport`,
  `FakeCompanionTransport`, `FakeHaptics`, `FakeNotifications`, `FakeLiveActivities`).
- **LedgerTestSupport:** `Exports.swift` (`@_exported import LedgerFakes`), `WithTestDependencies.swift`
  (`withTestDependencies` sync and async, with and without `configure`; `DependencyValues.inMemoryStores(seed:)`),
  `Persistence/SettingsRepositoryContract.swift` (3 clauses). Placeholder deleted.
- **LedgerSnapshotTesting:** `LedgerSnapshot.swift` (`SnapshotDevice`, `SnapshotCell.matrix(…)`,
  `assertLedgerSnapshot(of:named:devices:themes:typeSizes:)`).
- **Tests:** `LedgerDependenciesTests/{DependencyKeysTests, UnimplementedStubTests, PreviewValueTests,
  FixturesTests}` (placeholder deleted), `LedgerSyncTests/FakeTransportTests`,
  `LedgerPersistenceTests/InMemoryContractTests` + the settings contract in `SettingsRepositoryTests`,
  `LedgerDesignTests/SnapshotMatrixTests`; 11 `LedgerDomainTests` files renamed `InMemoryEventStore` →
  `InMemoryWorkoutEventStore` (identifier and comments only).
- `scripts/coverage-thresholds.json`: `LedgerDependencies 90`, `LedgerFakes 90`, both `required`.

### Decisions and deviations

1. **`RepositoryError` moved to `LedgerDomain`** (orchestrator-approved, 2026-10-03). The F05 contracts check
   `LedgerPersistenceError.missingRow/duplicateIdentifier/nulInText/notFinished` by type and equality, and the
   enum lived in `LedgerPersistence`, which `LedgerFakes` may not import (B1). Moved unchanged beside the protocols
   that promise its cases; `LedgerPersistence` keeps the name as a typealias, so no contract, tester suite or call
   site changed. No case carries a GRDB or SQLite type; `ModuleBoundaryTests` stays green.
2. **`Mutex`, not actors, for the shared stores** (ADR-008 decision 4). `observe…()` is synchronous and must
   yield the current value before it returns, as GRDB's `ValueObservation` does; an actor would register the
   observer from an unstructured `Task` and race the next write. `ObservedState` runs each write whole on a copy
   (all or nothing) and yields to each stream only on change (GRDB's `removeDuplicates()`). The event store stays
   an actor (its protocol is all `async`). No `@unchecked Sendable`.
3. **Fixtures: promoted as a public, catalog-id copy; the F02 copy stays.** `LedgerFakes.Fixtures` carries
   `Fixtures.swift`'s clock, calendar, ids, `uuid(_:)` and `date(…)`, and `Fixtures+Program.swift`'s day/program
   shape, rebuilt on the bundled catalog's ids with spec §6.4's `W0` loads as slot start loads. The
   `LedgerDomainTests` copy is unchanged: its 25 files (~170 call sites, F02 and its adversarial rounds) pin the
   prototype's `W0` exercises, their `uuid(1…18)` ids and their default start loads (e.g. `SessionBuilder`
   expecting 180 lb from an exercise default; catalog bench is 45 lb, decision #21). Repointing them would rewrite
   F02's expectations. The test target's own `enum Fixtures` shadows the imported one, so both compile.
4. **Fixtures that can fail validation throw** (`upperA()`, `seedProgram()`, `seedSession()`, `history(weeks:)`):
   `Slot`/`Program` inits throw and `force_try` is an error everywhere. `Fixtures.benchPress` and
   `Fixtures.CatalogID.*` are values; `FixturesTests` pins them to `ExerciseCatalog.seed()`.
5. **Preview values.** Each store key's `previewValue` is its own `PreviewStores.make()` (the library computes a
   key's preview value once), all from `InMemoryStores.Seed.preview()`: the catalog, the seed program (active),
   `history(weeks: 8)` (29 workouts up to `Fixtures.now`), `settingsLb`, stats at `Fixtures.now`. So the stores
   hold the same data, but a write in a live preview reaches only the store it went to; a preview that needs them
   linked binds one `InMemoryStores` with `withDependencies`. A seed that fails falls back to `.empty` (a
   commented `try?`; `FixturesTests.previewSeed_builds` proves it builds).
6. **`deviceID`'s live value** is the nil UUID and logs at fault level when read: there is no protocol to stub,
   and S2's `LocalDevice` binds the real one. Test value: the library default (fails naming the key). Preview:
   `Fixtures.deviceID`.
7. **`FakeLiveWorkoutTransport`** (empty conformance) added beside the planned fakes so `liveWorkoutTransport`
   has a preview value; `FakeLinkBus` stays protocol-free (F17 builds the transport over it).
8. **`FakeLinkBus` time is the bus's own** (`advance(by:)`, `flush()`), never the wall clock (standards §9):
   delay uniform in a range, Bernoulli loss and duplication, partitions per pair (dropping at send and at
   delivery), all from a SplitMix64 seeded per bus.
9. **`withTestDependencies` defaults:** `date = .constant(Fixtures.now)`, `uuid = .incrementing`,
   `continuousClock = ImmediateClock()` (a test that steps time sets a `TestClock` in `configure`),
   `calendar = Fixtures.calendar`, `locale = en_US`; then `configure`. The `configure`-less forms are separate
   overloads because a defaulted closure argument makes a `rethrows` call throwing.
10. **`inMemoryStores(seed:)` lives in LedgerTestSupport** as planned (a `DependencyValues` mutating method that
    returns the stores); its stats read the `date` dependency as it stands when called.
11. **No `LedgerFakesTests` target** (no test-plan edits): the contracts run the stores in
    `LedgerPersistenceTests`, `FixturesTests` runs in `LedgerDependenciesTests`, `FakeTransportTests` in
    `LedgerSyncTests` (as `LedgerTestSupport` has no test target either).
12. **`assertLedgerSnapshot`** draws phone cells on iOS and watch cells on watchOS through the existing helpers
    (none on the Mac host); references are named `<name>-<cell>`. Only its matrix is tested here
    (`SnapshotMatrixTests`); S3's Today snapshots are its first images.

### Criteria → tests

| Criterion | Test |
|---|---|
| 3 — an unconfigured key fails naming it | `DependencyKeysTests.test_unimplementedDependencyFailsLoudly` (13 keys, each a `withKnownIssue` matching `@Dependency(\.<key>)`); `logger_testValue_discardsWithoutAnIssue` |
| 4 — every contract on GRDB and the fakes | `InMemoryContractTests` (exercise 13, program 10, workout 13, stats 10, event store 14, settings 3 clauses) beside the GRDB suites; `SettingsRepositoryTests.contract_clauseHolds` (new contract on GRDB) |
| 5 — two endpoints, loss 0.3, 100 sent | `FakeTransportTests.test_lossy_deliversAtLeast70_neverADuplicate` (seed 2026), `lossyLink_losesAboutItsRate_overSeeds` (200 seeds: total 13,700…14,300, never a duplicate), plus determinism, duplication, delay order, partitions, `setLink` |
| (test plan) `FixturesTests` | `FixturesTests` (catalog ids and `benchPress` equal the catalog's; §6.4 shape; the program saves and reads back; session; history at 0/1/8 weeks materialises whole; settings; preview seed) |
| (8, data half) previews | `PreviewValueTests` (every key's preview value; stores seeded) |
| stubs | `UnimplementedStubTests` (every stub method throws `unimplemented(key:)`; every `observe…()` ends) |

### Code lines (non-blank, non-comment)

| Module | Lines |
|---|---|
| LedgerDomain (new: `Clients`, `RepositoryError` moved in) | +16 |
| LedgerPersistence (enum → alias) | −10 |
| LedgerDependencies | 360 (placeholder −3) |
| `Package.swift` (incl. comments) | +15 / −4 |
| **Product total** | **≈ 375** |
| LedgerFakes (counted separately; ~40 of it the moved event store) | 1,175 |
| LedgerTestSupport (new files) | 111 (placeholder −3) |
| LedgerSnapshotTesting | 68 |
| Tests (new files) | 524 |

### Gate and coverage

Full `scripts/check.sh` under the simulator lock, run 2: **exit 0, `check.sh OK`**. 17 test targets ran and
passed (PR), 8 (PR-Watch). Summary: tools 0 s, format 1 s, lint 62 s, iOS build 14 s, iOS tests 175 s, watchOS
build 14 s, watchOS tests 142 s, coverage 2 s, total 411 s. No new warnings: the only compiler warning in either
run is the existing `will never be executed` at `PayloadVersionAdversarialTests.swift:29` (an `Int.bitWidth`
branch, F05; it shows whenever that target recompiles), and the `xcbeautify` "failed with exit code 0" lines
that come with it appear in earlier F05 gate logs too.

Run 1 failed only the coverage gate (`LedgerFakes: no lines measured`): fixed by the direct test-target edge
above.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 194 / 203 | 95.56 % | 90 % | ✓ |
| LedgerDesign | 1946 / 2002 | 97.20 % | 60 % | ✓ |
| LedgerDomain | 1946 / 1964 | 99.08 % | 95 % | ✓ |
| LedgerFakes | 1254 / 1270 | 98.74 % | 90 % | ✓ |
| LedgerPersistence | 2293 / 2307 | 99.39 % | 90 % | ✓ |
| Overall | 7633 / 7746 | 98.54 % | 80 % | ✓ |

Host `swift test`: everything green except `LedgerDesignTests`' Archivo font suites (52 issues), which fail on
the Mac host only (font registration) and are untouched here; the gate's simulators run them green.

### How to verify by hand

- `cd LedgerKit && env -u SDKROOT swift test --only-use-versions-from-resolved-file --filter
  'DependencyKeys|UnimplementedStub|PreviewValue|Fixtures|FakeTransport|InMemoryContract|SettingsRepository|SnapshotMatrix'`.
  `DependencyKeysTests` reports 13 known issues, each the library's "@Dependency(\.<key>) has no test
  implementation" message.
- `scripts/check-package-graph.sh` passes; `git diff main -- LedgerKit/package-graph.expected.txt` is the graph
  change above.
- In Xcode, a `#Preview` in any feature can `import LedgerFakes` and read `@Dependency(\.programRepository)`: the
  active program is "Upper / Lower".

### Open questions (with recommendations)

1. **Drop the `LedgerPersistenceError` alias later** with a mechanical rename to `RepositoryError` across
   `LedgerPersistence`, its tests and `LedgerTestSupport` (170 occurrences). Recommend a `chore:` PR after F07,
   not in S1 (orchestrator condition 3).
2. **Criterion 5's "≥ 70" is per seed, not a property of a 30 % lossy link** (100 Bernoulli trials at 0.7 reach
   70 about 55 % of the time). The test pins one seed (2026) and the 200-seed mean. Recommend rewording the
   criterion to "about 70 (seeded), and never a duplicate unless configured".
3. **Domain fixtures:** whether to repoint `LedgerDomainTests` at `LedgerFakes.Fixtures` later (deviation 3).
   Recommend not: the F02 suites test rules against the prototype's numbers, which the catalog no longer holds.
4. **Linked preview stores:** whether previews should share one `InMemoryStores` across keys (a process-wide
   value, i.e. global mutable state in Debug) so a live preview's write reaches the stats. Recommend not until a
   preview needs it; `withDependencies` covers that preview.

### Inputs for S2
- **`deviceID` must be bound** (review S1-N1): its live value is the nil UUID until the composition root binds the
  `device` row's id. S2's composition suite should assert the composed app's `deviceID` is not the nil UUID, or
  phone and watch would stamp events with one device and `(device, seq)` keys would collide.

### S1 fix round 1 (G1 implementer, 2026-10-03)

From `test-findings.md` "# Slice S1 — adversarial round 1" (F7-1 to F7-9) and `review.md` "# Slice S1 review"
(S1-SF1 to SF4, N1 to N7), with the orchestrator's binding decisions 1–13.

**Per decision, what changed and what proves it**

| # | Finding | Change | Proving test(s) |
|---|---|---|---|
| 1 | F7-5, S1-SF1 | `LedgerTestSupport/WithTestDependencies.swift` wrapped in `#if DEBUG` (the only file naming a fake outside one). `swift build -c release` of the package exits 0 again (38 s). ADR-008's Consequences say so. **Check:** not added to `check.sh`: `scripts/tests/adversarial/check-wiring.adv.sh` pins every step `check.sh` runs, so a new step means reworking that suite, and the PR lane would pay ~40 s of macOS minutes per push. Follow-up recommendation: a `swift build -c release` step in the nightly lane | Release build exit 0; mutant M17 (unwrapped) fails with 14 errors |
| 2 | F7-1 | New `LedgerDomain/Storage/StorageBoundary.swift` (`units(ofGrams:)`, `grams(units:)`, `seconds(_:)`, `Weight/Volume.checkStorable()`): ADR-007's rules, moved out of `ColumnCodec`, which now calls it. Every fake runs it over every weight and date GRDB encodes (set weights, done dates, the e1RM, targets, steps, the workout's volume and dates, slot start loads and steps, exercise start loads), in GRDB's order. New `storageClauses` on the workout, program and exercise contracts | `WorkoutRepositoryContract.storageClauses`, `ProgramRepositoryContract.storageClauses`, `ExerciseRepositoryContract.storageClauses` on GRDB and the fakes; `StorageBoundaryTests`; the tester's `exactness_fakeAnswersAsGRDB` (10 cases) |
| 3 | F7-2 | `EnvelopeCodec` and `SettingsCodec` moved, unchanged, from LedgerPersistence to `LedgerDomain/Storage/` (now public). `InMemorySettingsRepository.save` stores `decode(encode(settings))`. `InMemoryWorkoutEventStore.append` encodes the whole batch first (an `EncodingError` stores nothing), keeps each envelope as decoded, and compares as GRDB does | `SettingsRepositoryContract.storageClauses`, `WorkoutEventStoreContract.storageClauses` on both; `StorageBoundaryTests.settingsCodec_roundTrips`/`envelopeCodec_roundTrips`; the tester's `encoding_fakeAnswersAsGRDB` (3) |
| 4 | F7-3, S1-SF3 | New `RepositoryError.unknownExercise(String)` (payload `"exercise <id>"`, the first such slot in slot order). GRDB: `ProgramRows.refuseUnknownExercises`, inside the write transaction, after other programs' ids and before any row is written; a soft-deleted exercise still counts, as the foreign key sees it. Fakes: `InMemoryProgramRepository(programs:exercises:)` checks on `save` when given an exercise store; `InMemoryStores` gives it one. A `Seed`'s programs are stored state and are not checked (only `save` checks). `ProgramRepository.save` doc, F08 input line, and ADR-008's linked-stores wording are updated | `ProgramRepositoryContract.storageClauses` ("a slot naming an exercise that is not stored throws unknownExercise", on GRDB and on the fake linked to a catalog); `InMemoryContractTests.unlinkedPrograms_checkNoExercise`; the tester's `foreignKeys_fakeAnswersAsGRDB` |
| 5 | F7-4 | `InMemoryHistory.store` checks in GRDB's order: start (the replay's place), other workouts' ids, the workout row (dates, volume, name, tag), the exercises (repeats, then step, target and name, each in turn), the sets (repeats, then weight, done date, e1RM, each in turn). The program and exercise fakes likewise (doc comments say so). Shared `LedgerFakes/Support/RowChecks.swift` | `WorkoutRepositoryContract.storageClauses` "with two faults…" (3 cases); the tester's `precedence_fakeAnswersAsGRDB` (2) |
| 6 | F7-6 | `inMemoryStores(seed:)`'s stats read `@Dependency(\.date.now)` on every query, not once at bind time | the tester's `statsDate_isTheDateWhenBound` (unedited) |
| 7 | F7-7, S1-N7 | `FakeLinkBus`: `advance(by:)` never moves time back (a negative interval moves it by nothing); a message from or to an endpoint the bus did not make is dropped, with no inbox made; a delay range outside `0 … Int64.max` ns traps at `init`/`setLink` (`precondition`; a negative delay would arrive before it was sent); the drawn delay is clamped below `Int64.max` | the tester's `negativeAdvance_keepsArrivalsMonotonic`, `foreignEndpoint_isNotAnInbox` (unedited); the trap has no test (it would end the process) |
| 8 | F7-8 | `InMemoryExerciseRepository(catalog:version:)` defaults to `ExerciseCatalog.version` | `FakeStoreTests.catalogRepository_isSeededAtTheCatalogsVersion` |
| 9 | F7-9 | `assertLedgerSnapshot` records an issue when the simulator it runs on has no cell of its own (`SnapshotCell.isDrawnHere`) | `SnapshotMatrixTests.noCellHere_failsTheTest` (simulators), `isDrawnHere_matchesThePlatform` |
| 10 | S1-SF2 | `ObservedState` streams use `.bufferingNewest(1)`, as GRDB's bridge does; doc says so | `FakeStoreTests.slowConsumer_seesTheNewestOnly` |
| 11 | S1-SF4 | `docs/engineering-standards.md` §4: the one exception sentence for ADR-008's `Mutex` fakes | — |
| 12 | S1-N3 | `materialize` writes the misses inside the history write, once nothing can throw (lock order: history, then programs; never the reverse) | `FakeStoreTests.refusedMaterialisation_writesNoMisses` |
| 12 | S1-N4 | ADR-008 decision 4 now states GRDB's real guarantee (the first fetch is queued on the writer before later writes); architecture §13 says what each kind of stub does | — |
| 12 | S1-N5 | The direct `LedgerFakes` edge is narrowed from every test target to `LedgerPersistenceTests`, `LedgerDependenciesTests` and `LedgerSyncTests` (`fakesCoverageTargets` in `Package.swift`); graph re-recorded. Coverage still measured: see the gate below | coverage table |
| 12 | S1-N6 | A test that ends an observation early, then writes, and observes again | `FakeStoreTests.endedObservation_stopsOnlyItself` |
| 12 | S1-N1 | S2 input above | — |
| 12 | S1-N2 | Noted only: a preview needing linked stores binds one `InMemoryStores` by hand (`withDependencies`); moving a `bind(_:)` into `LedgerDependencies` can wait for the first preview that needs it | — |
| 13 | Criterion 5 | Not touched (the orchestrator rewords the brief) | — |

**Storage clauses beside the contracts' `clauses`.** The new clauses live in each contract's `storageClauses`, which
the GRDB suites and `InMemoryContractTests` run. They are not part of `clauses`: F05's oracles (`HistoryModel`
with its fault list, the event-store models of F04) model history, not columns, and
`HistoryContractAdversarialTests` pins `clauses.count == 23`.

**Sanctioned edits to existing tests** (each approved by the orchestrator before it was made; the tester audits
them in the close-out). No assertion of a documenting test was weakened.
1. `FakesHistoryDifferentialAdversarialTests.firstLinkedMismatch`: the fake now saves `S2Kit.slotExercises`
   first, as the GRDB stack holds them, so both sides start from the same database (decision 4 makes the linked
   fake check slot exercises).
2. Six `FakeObservationAdversarialTests` read after each write instead of after all of them, because a stream
   keeps only its newest value (decision 10):
   - `firstValue_isTheStateWhenObserved` and `cancelledConsumer_endsOnlyItsStream`: read the first value, then
     write.
   - `unchangedWrites_emitNothing`: reads after each real change, and after an unchanged save makes the next real
     change and expects exactly it. Limit: with newest-only buffering, a spurious repeat that a later change
     overwrites before the consumer reads is invisible to any consumer, so it is not observable.
   - `refusedWrite_emitsNothing`: the first value, then the refused save, then a real save that must be the next
     value.
   - `manySubscribers_seeEveryChange`: each of the 50 subscribers reads after each write.
   - `racingWriters_loseNothing`, renamed `racingWriters_endOnTheFinalState_inOrder`: asserts the last value is
     the 500 state and every value seen is strictly increasing.
3. Two more `FakeObservationAdversarialTests` (decision 10):
   - `slotUpdates_emitTheActiveProgram`: reads the first value before `materialize`.
   - `consumerWritingBack_doesNotDeadlock`: a handshake (the consumer signals after its first value, and only
     then is 120 saved). Same `[90, 120, 150]`.
4. `ProgramRepositoryTests.failedSave_changesNothing` (F05): its mid-save fault is now a ⅛ lb start load in the
   last slot, expecting `inexactWeight`. The unknown exercise it used is now refused before any row is written.
   A statement trace confirmed the new fault fires midway: 13 `INSERT`/`UPDATE` statements, then `ROLLBACK`, in
   one transaction. So the test still fails if the save were not one transaction.
5. `ProgramEditAdversarialTests.failedEdit_leavesTheSavedVersion` (F05 tester): expects
   `unknownExercise("exercise …")` instead of `DatabaseError`; its rows-unchanged assertion stays.

**Mutants** (one at a time, in a scratchpad copy of `LedgerKit`, `f07s1/mut/`; results `f07s1/mut/mutants.txt`).
All killed:

| Mutant | Killed by |
|---|---|
| M1 `StorageBoundary.units` never refuses | the exercise, program and workout storage clauses; `StorageBoundaryTests` |
| M2 non-finite dates accepted | the workout storage clause; `StorageBoundaryTests` |
| M3 the history fake skips the volume | the workout storage clause |
| M4 the history fake checks set repeats before the workout row (old order) | the workout storage and contract clauses; the tester's F7-4 |
| M5 the program fake skips the exercise check | the program storage clause; `unlinkedPrograms_checkNoExercise`; the tester's F7-3 |
| M6 the program fake skips slot weights | the program storage clause; the tester's F7-1 |
| M7 the exercise fake skips start loads | the exercise storage clause; the tester's F7-1 |
| M8 the settings fake skips the codec | the settings storage clause; the tester's F7-2 |
| M9 the event fake skips the codec | the event storage clause; the tester's F7-2 |
| M10 GRDB lets the foreign key fail | the GRDB program storage clause; the tester's F7-3; `ProgramEditAdversarialTests.failedEdit` |
| M11 streams buffer every value | `FakeStoreTests.slowConsumer_seesTheNewestOnly` |
| M12 the stats' date frozen at bind | the tester's F7-6 |
| M13 bus time moves back | the tester's F7-7 (negative advance) |
| M14 the bus accepts foreign endpoints | the tester's F7-7 (foreign endpoint) |
| M15 exercise store at version 1 | `FakeStoreTests.catalogRepository_isSeededAtTheCatalogsVersion` |
| M16 misses written before the workout | `FakeStoreTests.refusedMaterialisation_writesNoMisses` |
| M17 `WithTestDependencies.swift` outside `#if DEBUG` | `swift build -c release` (14 errors) |
| M18 the zero-cell check removed | `SnapshotMatrixTests.noCellHere_failsTheTest` (run on the iOS simulator under the lock: TEST FAILED, only that test) |
| M19 seeded programs checked for exercises | `unlinkedPrograms_checkNoExercise`; the tester's `slotUpdates_emitTheActiveProgram` |

**Release build:** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`
exit 0 (38 s).

**Host:** `swift test`, whole package: everything passes, including every tester suite of round 1 and the
13 known issues of criterion 3. The only failures are `LedgerDesignTests`' Archivo font suites (52 issues),
which fail on the Mac host only, as on `main`.

**Full gate** (`scripts/check.sh` under the lock): **exit 0, `check.sh OK`**; 17 test targets passed (PR), 8
(PR-Watch). Summary: tools 0 s, format 0 s, lint 60 s, iOS build 40 s, iOS tests 200 s, watchOS build 29 s,
watchOS tests 174 s, coverage 1 s, total 505 s. **No new warnings.** Two warnings show, neither from this round:
- `PayloadVersionAdversarialTests.swift:29` "will never be executed" (F05, an `Int.bitWidth` branch);
- an unnecessary `try` at `FakeObservationAdversarialTests.swift:213` (the tester's round-1 line, unchanged:
  `InMemoryWorkoutEventStore.envelopes(for:)` does not throw on the concrete actor). That file is the tester's,
  so I left it.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 194 / 203 | 95.56 % | 90 % | ✓ |
| LedgerDesign | 1946 / 2002 | 97.20 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1313 / 1328 | 98.87 % | 90 % | ✓ |
| LedgerPersistence | 2257 / 2271 | 99.38 % | 90 % | ✓ |
| Overall | 7719 / 7831 | 98.56 % | 80 % | ✓ |

**Code lines** (non-blank, non-comment; tracked files by `git diff -U0`, new files counted whole):

| Module | Fix round 1 | Whole slice vs `a8080ff` |
|---|---|---|
| LedgerDomain | +83 (48 of them moved: the two codecs; new: `StorageBoundary` 31, `unknownExercise` 1, docs aside) | +99 |
| LedgerPersistence | +14 / −62 (the codecs moved out, `ColumnCodec` delegating, the exercise check +12) | +16 / −74 |
| LedgerDependencies | 0 | +360 / −3 |
| `Package.swift` | +3 / −6 | +7 / −7 |
| **Product** | **+100 / −68, net +32** (≈ 50 of it moved code) | **+482 / −84** (≈ 50 moved) |
| LedgerFakes | +103 / −57 | +1,221 |
| LedgerTestSupport | +289 / −53 (the storage clauses 232) | +347 / −3 |
| LedgerSnapshotTesting | +32 / −1 | +99 |
| Tests | +278 / −33 | +1,985 / −68 |

**Open questions**
1. A `swift build -c release` lane: nightly, not the PR gate (decision 1's budget; `check-wiring.adv.sh` pins the
   gate's steps). Recommend adding it to the nightly workflow with F01's next CI change.
2. The tester's unnecessary `try` (`FakeObservationAdversarialTests.swift:213`): a one-character fix for the
   tester's close-out.
3. Whether a workout naming an exercise that is not stored should also be refused: it is not, on either side
   (`workout_exercise.exercise_id` has no foreign key, so history keeps workouts of deleted or unknown
   exercises). No change recommended.

### S1 fix round 2 (G1 implementer, 2026-10-03)

From `test-findings.md` "# Slice S1 — close-out round" (F7-10, F7-11), with the orchestrator's decisions and
rulings.

**F7-10: a seed a database could not hold.**
- **Change.** `InMemoryStores.Seed.missingExercises` (`LedgerFakes/InMemoryStores.swift:42`) lists the exercises the
  seed's programs name that its catalog lacks. When there are any, `InMemoryStores.init` (`:71`) calls
  `reportIssue` naming their ids, which fails the test that made the seed, then stores the seed as given.
- **Dependency.** That needs `LedgerFakes → IssueReporting` (ruling A). It's in `Package.swift` (the
  `swift-issue-reporting` package was already resolved through swift-dependencies, so both `Package.resolved` files
  are unchanged and `check-package-pins.sh` agrees). The graph is re-recorded, ADR-008 has a dated amendment, and
  the architecture §3 and standards §2 lines are updated.
- **Seeds.** `Seed.preview()` already held the catalog. Every other seed in the package now holds its programs'
  exercises.
- **Proving tests.** `InMemoryContractTests.seeds_holdOnlyWhatADatabaseCould` (a legal seed saves back; an
  illegal one reports the missing id) and the tester's `seededProgram_savesBackUnchanged` (edited as sanctioned,
  below).

**F7-11: the stats' date after the operation.**
- **Change.** `withTestDependencies` (`LedgerTestSupport/WithTestDependencies.swift:21`, `:44`) sets a task-local
  `TestScope` around both `configure` and the operation. `inMemoryStores(seed:)` (`:72`) gives the stores a
  `StatsClock` and registers it with the scope. When `configure` returns, the scope binds every clock to the
  `date` it ended with.
- **The two date sources.** Inside the operation (`TestScope.current` is set), the stats read the `date`
  dependency on each query, so a `date` set after `.inMemoryStores` in `configure`, or by a nested
  `withDependencies`, is honoured (F7-6). After the operation (no scope), they read the date `configure` ended
  with, so a store the test kept needs no dependency and records no issue (F7-11). Bound outside
  `withTestDependencies`, the clock keeps the `date` as it stood at binding.
- **Proving tests.** The tester's `statsAfterTheOperation_needNoDependency`, `statsDate_isTheDateWhenBound` and
  `statsDate_followsTheOperationsDate`, all unedited. Also `DependencyKeysTests.keptStores_answerWithTheConfiguredDate`:
  the date set after binding, read after the operation.

**Sanctioned edits** (approved before they were made):
1. `FakeObservationAdversarialTests.slotUpdates_emitTheActiveProgram`: its seed gains `ExerciseCatalog.seed()`
   (setup only).
2. `StoresCloseoutAdversarialTests.seededProgram_savesBackUnchanged`: the catalog-less seed is kept, wrapped in
   `withKnownIssue` matching the missing id (bench press's). A second, legal seed (the catalog with the program)
   asserts its original claim: active, then saved back unchanged.
3. My own tests, so their seeds are legal:
   - `DependencyKeysTests.inMemoryStores_linksEveryStore`: the seed holds the catalog, and its exercise
     assertion is now the catalog's count instead of empty.
   - `FakeStoreTests.refusedMaterialisation_writesNoMisses`: the seed holds the catalog.
   - `InMemoryContractTests.unlinkedPrograms_checkNoExercise`: split. The unlinked half stays; the seeded half
     became `seeds_holdOnlyWhatADatabaseCould`.

**Mutants** (one at a time, scratchpad copy `f07s1/mut2/`, results `mut2/mutants.txt`). All killed:

| Mutant | Killed by |
|---|---|
| P1 an illegal seed is not reported | `seeds_holdOnlyWhatADatabaseCould`; tester's `seededProgram_savesBackUnchanged` |
| P2 `missingExercises` always empty | the same two |
| P3 the stats ignore the dependency inside the operation | tester's `statsDate_followsTheOperationsDate` |
| P4 the stats always read the dependency | `keptStores_answerWithTheConfiguredDate`; tester's `statsAfterTheOperation_needNoDependency` |
| P5 the configured date never bound | `keptStores_answerWithTheConfiguredDate` |

**Release build:** `swift build -c release` exits 0.

**Full gate** (`scripts/check.sh` under the lock): **exit 0, `check.sh OK`**; 17 test targets passed (PR), 8
(PR-Watch). Summary: tools 1 s, format 0 s, lint 62 s, iOS build 40 s, iOS tests 203 s, watchOS build 31 s,
watchOS tests 183 s, coverage 2 s, total 522 s.
- **Warnings:** only F05's `PayloadVersionAdversarialTests.swift:29` "will never be executed". The tester removed
  the unnecessary `try` in the close-out.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 194 / 203 | 95.56 % | 90 % | ✓ |
| LedgerDesign | 1946 / 2002 | 97.20 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerPersistence | 2257 / 2271 | 99.38 % | 90 % | ✓ |
| Overall | 7733 / 7845 | 98.57 % | 80 % | ✓ |

## Slice S2 — both apps boot on a real database (G1 implementer, 2026-10-04)

Branch `feat/F07-s2-boot`, cut from `feat/F07-s1-keys-fakes` at `f991d69` (S1 is PR #22, unmerged). No commits.

### What landed

- **LedgerPersistence**
  - `LocalDevice.swift`: `LocalDevice.id(in:kind:now:newID:)` reads this platform's `device` row (`kind` phone or
    watch) or inserts one with `newID()`, in one write (decision B4). Of two rows of one kind the oldest (then
    the lowest id) wins; a stored id that is not a UUID throws `malformedIdentifier` and the row is kept.
  - `LedgerStores.swift`: the queue, this device's id and the six GRDB stores, each given `now`;
    `LedgerStores.open(at:kind:now:newID:)` (open + migrate, then `LocalDevice`), `defaultURL`
    (`Application Support/Database/ledger.sqlite`), `seedCatalog()` (`seedIfNeeded(ExerciseCatalog.seed(),
    version: ExerciseCatalog.version)`).
- **LedgerHealth** `MirroringStartRegistrar.swift`: `MirroringStartRegistrar<Session>` keeps every session the
  handler is handed behind a `Mutex` and logs at notice level; `register()` installs the handler (capturing the
  registrar weakly). On iOS, `MirroringStartRegistrar<HKWorkoutSession>(healthStore:)` installs it as
  `workoutSessionMirroringStartHandler`. `Sendable` without `@unchecked`. Placeholder deleted.
- **LedgerSync** `CompanionSessionActivator.swift` (`#if canImport(WatchConnectivity)`): a nonisolated
  `NSObject, WCSessionDelegate, Sendable` with no mutable state; `activate()` sets itself as the default
  session's delegate and activates it (logs and stops where WC is unsupported); the callbacks log, and
  `sessionDidDeactivate` activates again (watch switch). A small internal `CompanionSession` protocol (which
  `WCSession` adopts) lets the tests hand it a stand-in. Placeholder deleted.
- **LedgerAppKit** (placeholder deleted)
  - `AppComposition.swift`: `@MainActor @Observable`; `state` (`idle` / `ready` / `databaseUnavailable`),
    `settings`, `isCatalogSeeded`; `launch()` (the live environment, then `boot()` unless `isTesting`);
    `bind(_:)` (six stores + `deviceID`); an internal `Environment` (database URL, `now`, `newID`, logger,
    recorder, the handler and WC actions, whether to `prepareDependencies`), whose `live(arguments:)` picks
    `-LEDGER_UITEST` → `tmp/LedgerUITest-<uuid>/ledger.sqlite`, else `LedgerStores.defaultURL`.
  - `Launch.swift`: `LaunchStep` (`assignMirroringHandler, openDatabase, seedCatalog, loadSettings,
    activateCompanionSession`), `LaunchEvent` (`began`/`failed`), and the sequence: `boot()` (synchronous:
    handler, then open + `prepareDependencies { bind(&$0) }`), `resume(in: ScenePhase) async` (first call:
    seed, settings, WC, in any phase; later calls, on `.active` only: reopen if unavailable (#29), reseed if
    unseeded (#28)). A failed step logs at fault level and records `.failed(step)`.
  - `AppRootView.swift`: takes the composition, shows "Ledger" or decision #29's static screen
    (`EmptyState("Can't open your data right now", …)`), and runs `.task(id: scenePhase) { await
    composition.resume(in: scenePhase) }`.
- **LedgerWatchAppKit** (placeholder deleted): `WatchComposition.swift` and `Launch.swift`, the same shape without
  the mirroring step (kind `.watch`); `WatchAppDelegate.swift` (`#if os(watchOS)`, `WKApplicationDelegate`:
  `handle(_ workoutConfiguration:)` and `handleActiveWorkoutRecovery()` read `healthStore` and log; F16 adds the
  calls); `WatchRootView.swift` as the iOS root.
- **Apps**: `LedgerApp` holds `@State var composition = AppComposition.launch()` and renders
  `AppRootView(composition:)`; `LedgerWatchApp` adds `@WKApplicationDelegateAdaptor WatchAppDelegate`.
  `Apps/*Tests/SmokeTests.swift`: the deleted `…Module.name` checks became "`launch()` boots nothing under test".
- **Coverage thresholds**: `LedgerHealth` and `LedgerSync` now have measured lines, so the gate requires them
  (`required`, at their existing 80 % and 90 %).
- **Docs**: testing-strategy §2.7 (UI tests open a fresh temporary file, not "the in-memory database seeded by
  `LedgerTestSupport.Seed.uiTest`", per A-decision); architecture §4 watch bullet (the database opens in
  `App.init`, not `applicationDidFinishLaunching`).
- **Package graph: unchanged.** Every module the compositions import was already an edge of both umbrellas;
  `scripts/check-package-graph.sh` passes with no re-record.

### Decisions and deviations

1. **`deviceID` lives in `LedgerStores`** (beside the queue and six stores of the plan): one throwing call opens
   the file and reads the device, so a composition has one value to keep and bind.
2. **`logger` is not rebound.** Its `liveValue` is already the real `LedgerLogger(category: "app")` (S1); `bind`
   sets the six stores and `deviceID`. The device keys keep their `Unimplemented*` live values until F16–F23.
3. **Binding is process-wide once, and testable without it.** `boot()` calls `prepareDependencies { bind(&$0) }`
   only in the app (`Environment.preparesDependencies`); tests bind with `withDependencies { composition.bind(&$0)
   }`, since `prepareDependencies` would change the values for every test in the process. A database that opens
   only on a foreground retry binds then (nothing reads a key while #29's screen shows).
4. **`isTesting` lives in `launch()`, not in the `App`**: the app targets link only the umbrellas, and
   `launch()` is the one call the `App` makes. Under test it returns an `idle` composition: no handler, no file;
   `resume` does nothing. The package suites and both hosted smoke tests check it.
5. **The async part runs from `.task(id: scenePhase)`**, first in whatever phase (a workout can launch the watch
   app in the background), then retries only when the phase becomes `.active` (#28, #29). An unreadable settings
   row is not retried (it reads the same until the lifter saves; F14 resubscribes).
6. **The database opens on the main actor in `App.init`** (A-decision; F05 measured 4.6 ms on the watch
   simulator), although F05's input suggested off the main actor; the plan chose the synchronous open so the
   first frame already knows ready vs unavailable.
7. **Watch: the database opens in `App.init` (`WatchComposition.launch()`), not in
   `applicationDidFinishLaunching`** as the brief's text has it, per the A-decision; the delegate keeps the
   workout entry points only.
8. **The registrar is generic over its session type.** The first gate run crashed all four registrar tests on the
   iOS simulator: the package's test host has no HealthKit entitlement, and touching `HKHealthStore`'s handler
   property there traps (testing-strategy §3 also rules out real HealthKit in tests). So the tests give the
   registrar a stand-in handler slot and session class; the app's `HKHealthStore` binding is a two-line
   convenience init, exercised by the simulator launch, not by a test.
9. **Registrar uses `Synchronization.Mutex`, not an actor.** HealthKit calls the handler on an arbitrary queue and
   the handler cannot await, so an actor would be reached only through an unstructured `Task` after the handler
   returned. Standards §4 says shared mutable state lives in an actor, with one written exception (LedgerFakes);
   see open question 2.
10. **UI-test argument `-LEDGER_UITEST`** (testing-strategy's name), a new temporary directory per launch.
11. **The two compositions are parallel, not shared** (see open question 1): ~150 lines of the watch side repeat
    the iOS side's state machine, because the plan puts Launch in `LedgerAppKit` and the watch umbrella cannot
    import it.

### Criteria → tests

| Criterion / input | Test |
|---|---|
| 6 — handler assigned before any `await` | `boot()` is synchronous (compiler-enforced); `LaunchOrderTests.boot_assignsTheHandlerFirst` (log after `boot()` = began(assign), handler, began(open), nothing async), `launch_runsTheStepsInOrder` (all five steps in the brief's order), `boot_handlerFirst_evenWhenOpeningFails`, `resume_again_runsNothingTwice` |
| 1 (data half) — file in Application Support, ≥ 200 rows | `AppCompositionTests.boot_opensTheFile_andBindsTheStores` (file at `Database/ledger.sqlite`, the bound `exerciseRepository` holds all of `ExerciseCatalog.seed()`, 224), `liveEnvironment_databaseURL`; `LocalDeviceTests.defaultURL_isItsOwnDirectory` |
| 2 (data half) — the watch's own database | `WatchCompositionTests` (same, kind `watch`, and the watch order `launch_runsTheStepsInOrder`) |
| a second boot seeds nothing | `secondBoot_seedsNothing` (both): every `exercise` row identical after a boot a day later; same device |
| settings fallback, row untouched | `unreadableSettings_fallBack_rowUntouched` (payload_version 999 row byte-for-byte unchanged, `settings == .default`, `.failed(.loadSettings)`); `savedSettings_areLoaded` |
| #28 seeding fails → log, carry on, retry | `…RecoveryTests.seedingFailure_carriesOn_thenRetries` (a trigger refuses exercise inserts: `.failed(.seedCatalog)`, settings and WC still run, state ready; no retry in background; on `.active` after the trigger is dropped, seeded) |
| #29 open fails → unavailable, file untouched, retry | `openFailure_isUnavailable_andTheFileIsUntouched` (4 KB of non-database bytes: state unavailable, bytes and directory listing unchanged after a retry, nothing bound), `openFailure_retriedOnForeground` (a directory in the file's place; once removed, `.active` opens, seeds, loads) |
| S1 input — `deviceID` bound, not nil | `deviceID_isTheDeviceRow` (both): bound value = the `device` row of this kind, ≠ nil UUID |
| `LocalDevice` | `LocalDeviceTests` (insert once and read back per kind, the other kind is never this device, oldest of two, malformed id kept, `LedgerStores.open` keeps the device across opens, `seedCatalog` once) |
| `isTesting` guard | `launch_whileTesting_bootsNothing` (both); `Apps/*Tests/SmokeTests.umbrellaProduct_links_andLaunchBootsNothing` (hosted) |
| registrar | `MirroringStartRegistrarTests` (stand-in slot and sessions): installs the handler, keeps sessions in order, 50 concurrent calls all kept, does not retain the registrar |
| activator | `CompanionSessionActivatorTests`: delegate then one activation on a stand-in, unsupported does nothing, callbacks log, deactivation activates again (iOS) |

Deterministic: fixed dates and ids, no sleeps or timing assertions; every file under the temporary directory.

### Code lines (F05's method: added lines of `git diff -U0`, blank lines and whole-line comments, doc comments included, excluded)

| Path | Added | Removed |
|---|--:|--:|
| `LedgerPersistence` (`LocalDevice`, `LedgerStores`) | 73 | 0 |
| `LedgerHealth` (registrar) | 37 | 3 |
| `LedgerSync` (activator) | 49 | 3 |
| `LedgerAppKit` | 200 | 5 |
| `LedgerWatchAppKit` | 209 | 5 |
| `Apps/Ledger`, `Apps/LedgerWatch` | 5 | 2 |
| **Product** | **573** | **18** |
| Tests | 830 | 42 |

(Corrected in fix round 1 to F05's method, as the review counted; the first table's "601 / ≈ 48" counted doc comments
and the hosted smoke tests.)

### Gate and coverage

Full `scripts/check.sh` under the simulator lock, run 3: **exit 0, `check.sh OK`**; 17 test targets ran and passed
(PR), 8 (PR-Watch). Summary: tools 1 s, format 0 s, lint 60 s, iOS build 15 s, iOS tests 196 s, watchOS build 12 s,
watchOS tests 176 s, coverage 2 s, total 464 s. New suites seen in the result bundles: iOS — LocalDevice 7,
Mirroring start registrar 4, Companion session activator 4, AppComposition 7, AppComposition · failed launch
steps 3, Launch order 4, Smoke 2 + 1; watchOS — LocalDevice 7, Companion session activator 3, WatchComposition 8,
WatchComposition · failed launch steps 3, Smoke 2 + 1.
- Run 1 failed at the iOS build: `self.` before `store` inside the watch delegate's log interpolation, which
  swiftformat had removed (`redundantSelf`); fixed with a local.
- Run 2 failed the four registrar tests (deviation 8).
- **Warnings:** only F05's `PayloadVersionAdversarialTests.swift:29` "will never be executed" (and its `@Test`
  macro expansion line). None from this slice.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 195 / 203 | 96.05 % | 90 % | ✓ |
| LedgerDesign | 1946 / 2002 | 97.20 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerHealth | 37 / 37 | 100.00 % | 80 % | ✓ |
| LedgerPersistence | 2310 / 2324 | 99.39 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 7855 / 7969 | 98.56 % | 80 % | ✓ |

(LedgerAppKit and LedgerWatchAppKit stay excluded from the gate, as before.)

**Release build:** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
exit 0 (39 s).

**Host:** `swift test` on the whole package: everything passes except `LedgerDesignTests`' Archivo font suites
(Mac host only, as on `main`).

**Simulator launch** (`f07s2/launch-check.sh` under the lock, iPhone 17 and Apple Watch Series 12 (46mm), iOS /
watchOS 27.0; the gate's builds): each app uninstalled (fresh container), installed, launched, and after 6 s
- still running (`launchctl list` shows its pid), no crash report;
- `Library/Application Support/Database/` holds `ledger.sqlite` plus `-wal` and `-shm`;
- read-only `sqlite3`: 224 `exercise` rows (`ExerciseCatalog.seed().count`) and one `device` row, `phone` /
  `iPhone` on the phone, `watch` / `Apple Watch` on the watch;
- screenshots show the "Ledger" placeholder on both;
- relaunched with `-LEDGER_UITEST 1`: a new `tmp/LedgerUITest-<uuid>/ledger.sqlite` in the app's container.

### How to verify by hand

- `cd LedgerKit && env -u SDKROOT swift test --only-use-versions-from-resolved-file --filter
  'LocalDevice|LaunchOrder|Composition|CompanionSession|MirroringStart'` (host; the activator suite is iOS/watch only).
- Launch either app in the simulator, then `sqlite3 "$(xcrun simctl get_app_container booted <bundle id>
  data)/Library/Application Support/Database/ledger.sqlite" 'SELECT COUNT(*) FROM exercise; SELECT * FROM device'`.
- #29 by hand: replace that file with a few bytes of text, relaunch: "Can't open your data right now"; the file is
  unchanged afterwards. Restore it and bring the app back to the foreground: the placeholder returns.
- Criterion 6: `LaunchOrderTests`; `boot()` has no `async`, so an `await` before the handler does not compile.

### Open questions (with recommendations)

1. **Share the launch between the platforms?** About 150 lines of `LedgerWatchAppKit` (`Launch.swift`, most of
   `WatchComposition.swift`) mirror the iOS ones, because the plan puts `Launch` in `LedgerAppKit` and the watch
   umbrella cannot import it. A shared home without a new edge would be `LedgerDependencies` (a `LiveValues` +
   launch state machine over the Domain protocols; the umbrellas pass the GRDB opener), at the cost of putting
   launch code in the module every feature imports. Recommend keeping two until F16/F17 add the platform steps,
   then deciding with the real differences in view; if shared, a small `LedgerComposition` target (an ADR and a
   graph edge) is cleaner than growing `LedgerDependencies`.
2. **Standards §4 and the registrar's `Mutex`.** §4 allows a `Mutex` only in LedgerFakes. A synchronous framework
   callback that must not await is a second legitimate case. Recommend adding it to §4's exception sentence ("…and
   state a framework callback writes synchronously, such as `MirroringStartRegistrar`").
3. **Is `isTesting` false in a UI-tested app?** IssueReporting's `isTesting` reads XCTest environment keys; if
   `XCUIApplication` passed one to the app, UI tests would see an unbooted app. The gate's UI `Smoke` only looks
   for "Ledger", which shows either way. Recommend S3's `launchesToToday` / Diagnostics ≥ 200 rows test settle
   it (it fails if the app does not boot under UI test).
4. **An unreadable settings row and the fault level.** A later payload version reaching an older app is expected
   in a mixed-version phone/watch pair; it is logged at fault level here like any failed step. Recommend F14
   lowers it to `error` when it adds the resubscription.
5. **Copy.** "Can't open your data right now" (decision #29) with "Your workouts are still on this iPhone/watch.
   Ledger tries again when you come back to it.", as plain strings: no string catalog exists yet. Recommend Pete
   confirm the body line; S3 or the localisation brief moves both into the catalog.
6. **Size.** 601 product lines, over the 500 target (PR description says so); the split considered was iOS vs
   watch, not taken because each half alone would leave criterion 2 or 6 half-done.

### S2 fix round 1 (G1 implementer, 2026-10-04)

From `test-findings.md` "# Slice S2 — adversarial round 1" (F7-S2-1, F7-S2-2) and `review.md` "# Slice S2 review"
(S2-SF1, SF2, N1–N5, open question 1), with the orchestrator's binding decisions 1–6. Branch at `6571cca`; no
tester test edited (`git diff 6571cca -- '*Adversarial*'` is empty).

**Per decision, what changed and what proves it**

| # | Finding | Change | Proving test(s) |
|---|---|---|---|
| 1 | review Q1 | New `LedgerPersistence/DatabaseLaunch.swift`: `@MainActor @Observable public final class DatabaseLaunch` (`:27`) holding `state`, `settings`, `isCatalogSeeded`, `stores`; synchronous `open()` (`:80`, #29); `resume(isForeground:) async` (`:101`, #28, the settings load, the retries); `onOpen` and `record` closures. `LaunchStep`/`LaunchEvent` (`:9`) moved here; both umbrellas' `Launch.swift` deleted. `AppComposition`/`WatchComposition` keep `launch()` with the `isTesting` guard, `boot()` (the iPhone's handler first), `resume(in: ScenePhase)` (forwards `phase == .active`, then WatchConnectivity once), `bind`, `Environment.live`, and forward `state`/`settings`/`isCatalogSeeded`/`stores` (the tester's tests read them). They are no longer `@Observable`: what the roots read is `DatabaseLaunch`'s, which SwiftUI tracks through the forwarding. Architecture §4 has the line. The umbrellas' own recovery suites moved to `LedgerPersistenceTests/DatabaseLaunchTests` (under the coverage gate) | `DatabaseLaunchTests` (8); every composition, order and tester suite unchanged and green on both platforms |
| 2 | F7-S2-1 = S2-SF1 | In `DatabaseLaunch.run(_:_:)` (`:143`): a step an overlapping call is running is not started (`running` set); `CancellationError` returns "not attempted" (`:150`) with no fault log and no `.failed`; `hasLoadedSettings` is set only when the load ran to an end (`:126`); the first pass counts as finished only if no step was cancelled (`:130`), so the next call, in any phase, runs the interrupted steps again | the tester's six, unedited: `LaunchAdversarialTests.cancelledFirstResume_settingsStillLoad`, `cancelledFirstResume_logsNoFailure`, `overlappingResumes_runEachStepOnce` and the `WatchLaunchAdversarialTests` twins; `DatabaseLaunchTests.cancelledPass_isNotAttempted_andRunsAgain` (next call in the background), `overlappingCalls_startEachStepOnce` |
| 3 | F7-S2-2 | `LedgerDatabase.open` runs `preflight` first (`Database.swift:28`, `:57`): an existing non-empty file is read through a read-only connection and accepted only if it has `grdb_migrations` whose ids this build knows, or no table at all; otherwise `OpenError.notLedgerDatabase` or `.laterSchema([ids])` (`:8`) before the WAL switch or a migration. Unreadable files throw SQLite's own error as before. `LedgerStores.open`'s doc (`:40`) says exactly that, including that a migration failing on the data after the preflight can leave earlier migrations applied | the tester's `foreignDatabase_isUnavailable_andUntouched` (+ watch twin), unedited; `DatabasePreflightTests`: foreign refused untouched, later schema refused untouched, a pending known migration migrates, an empty and a tableless file are new |
| 3+ | (gate, approved 2026-10-04) | **A change to F05's connection configuration:** `LedgerDatabase.baseConfiguration` sets `busyMode = .timeout(5)` (`Database.swift:92`), so every connection, the preflight's read-only one included, waits up to 5 s for another's lock instead of failing at once on `SQLITE_BUSY` (GRDB's default). Two first opens of one WAL file race its `-shm` recovery. The tester's `twoOpensAtOnce_oneRow` (an app and its extension) passed on the host by timing, but failed all 10 rounds on the iOS simulator in the first gate of this round, once the preflight added a connection. F21's widget extension will open the same file the same way | the tester's `LocalDeviceAdversarialTests.twoOpensAtOnce_oneRow`, unedited: passes on the host and on both simulators (10 rounds each). Without the timeout (gate run `fix1-gate.log`) it fails 10/10 on the iOS simulator |
| 4 | S2-SF2 | `docs/engineering-standards.md` §4 (`:102`): one clause for state a system framework callback writes synchronously on its own queue; the registrar's doc cites it | — |
| 5 | #29 copy | Kept. The watch's line already names the watch ("Your workouts are still on this watch. …", `WatchRootView.swift:21`); the iPhone's names the iPhone | — |
| 6 | S2-N1 | `launch(arguments:)` boots when `!isTesting || arguments.contains("-LEDGER_UITEST")` (`AppComposition.swift:76`, `WatchComposition.swift:71`) | `AppCompositionTests`/`WatchCompositionTests.boots_unlessHostingUnitTests` |
| 6 | S2-N5 | Architecture §4's iPhone bullet: WatchConnectivity follows the first frame; the G1 size table above uses F05's method | — |
| 6 | S2-N2, N3, N4 | Inputs below | — |

**The `-shm` file and "not a single byte".** A read-only connection to a WAL-mode database still updates its
`-shm`, SQLite's shared-memory index of the `-wal` (it holds no data, and SQLite rebuilds it). So on a Ledger file
from a later version the preflight leaves the database file and its `-wal` byte for byte as they were and the
listing unchanged, but the `-shm`'s read marks can change; `DatabasePreflightTests` compares everything but the
`-shm`'s bytes. A foreign rollback-journal database (the tester's case) gets no `-shm` at all.

**Inputs**
- **S3 (S2-N2, review Q7):** no view, store or Diagnostics may read a store key or `deviceID` before the composition
  is `.ready`. A late `prepareDependencies` (#29 recovered on a foreground) cannot rebind a key already read: DEBUG
  reports an issue, and Release silently keeps the stub.
- **F16 (S2-N3):** the real `HKHealthStore.workoutSessionMirroringStartHandler` assignment has no automated test (a
  package test host traps without the HealthKit entitlement); F16 owns a hosted or device check.
- **F17 (S2-N4):** the registrar keeps every mirrored session for the process's life; F17 hands each to the live
  transport and drops it when it ends.
- **F21 (busy timeout):** the widget extension opens the same file through `LedgerDatabase`, and so waits up to 5 s
  for a lock the app holds, instead of failing. The app's open runs on the main actor in `App.init`, so a lock
  that another process holds can delay the first frame by up to 5 s, where before it would have failed straight
  to decision #29's screen. F21 should keep its extension's writes short, and F20 should time a contended launch
  on a device.

**Mutants** (one at a time, scratchpad copy `f07s2/mut/`, results `mut/results.txt`). All killed:

| Mutant | Killed by |
|---|---|
| M1 settings marked loaded before the load (the old bug) | tester's `cancelledFirstResume_settingsStillLoad`; `cancelledPass_isNotAttempted_andRunsAgain` |
| M2 a cancellation logged and recorded as a failure | tester's `cancelledFirstResume_logsNoFailure`, `…settingsStillLoad`; `cancelledPass_…` |
| M3 no in-flight guard | tester's `overlappingResumes_runEachStepOnce`; `overlappingCalls_startEachStepOnce` |
| M4 a cancelled first pass counts as finished | `cancelledPass_isNotAttempted_andRunsAgain` |
| M5 no preflight | tester's `foreignDatabase_isUnavailable_andUntouched`; `foreignDatabase_isRefused_untouched`; `laterSchema_isRefused_untouched` (also the tester's `LocalDeviceAdversarialTests.twoOpensAtOnce_oneRow` that run; on the real code it passed 8 runs × 10 rounds) |
| M6 later migrations accepted | `laterSchema_isRefused_untouched` |
| M7 pending known migrations refused | `pendingKnownMigration_migrates`; F05's `MigrationCompatibilityTests` |
| M8 a foreign file with tables accepted | tester's `foreignDatabase_…`; `foreignDatabase_isRefused_untouched` |
| M9 `-LEDGER_UITEST` ignored under test | `boots_unlessHostingUnitTests` |
| M10 retries in the background | `seedFailure_carriesOn_thenRetriesInTheForeground`, `openFailure_untouched_retriedInTheForeground`; tester's `randomPhases_matchTheModel` |
| M11 `onOpen` never called | `open_thenFirstPass`, `openFailure_…` |

**Code lines** (F05's method, vs `f991d69`, the whole slice): LedgerPersistence +226 (`DatabaseLaunch` 119, the
preflight and busy timeout 34, `LocalDevice` + `LedgerStores` 73), LedgerHealth +37 / −3, LedgerSync +49 / −3, LedgerAppKit +152 / −5,
LedgerWatchAppKit +159 / −5, Apps +5 / −2: **product 628 added, 18 removed**. This round (vs `6571cca`): +268 / −213 (+153 in
LedgerPersistence, −98 net in the umbrellas). Tests this round: +273 / −188. Sharing removed the duplicated state machine, but the total did not
fall to the review's estimate of ~470, for two reasons. The fix adds the preflight (33 lines) and the cancellation
and overlap handling (about 20). And each umbrella keeps about 115–130 lines: the forwarding properties the tests
read, `bind`, and `Environment.live`. That is still over the 500 target and under ~1,000, so the PR description says so.

**Gate.** Full `scripts/check.sh` under the lock, run 2 of the round: **exit 0, `check.sh OK`**; 17 test targets
ran and passed (PR), 8 (PR-Watch). Summary: tools 0 s, format 0 s, lint 60 s, iOS build 14 s, iOS tests 198 s,
watchOS build 29 s, watchOS tests 179 s, coverage 2 s, total 482 s. The result bundles show, on both simulators,
`DatabaseLaunch`, `LedgerDatabase · preflight`, the tester's six F7-S2-1 tests and their #29 foreign-file test,
`twoOpensAtOnce_oneRow` (10 arguments) and `boots_unlessHostingUnitTests`, all passed. Run 1 failed only
`twoOpensAtOnce_oneRow` (the busy timeout above). **Warnings:** only F05's `PayloadVersionAdversarialTests.swift:29`
"will never be executed" and its `@Test` macro-expansion line.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 195 / 203 | 96.05 % | 90 % | ✓ |
| LedgerDesign | 1946 / 2002 | 97.20 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerHealth | 37 / 37 | 100.00 % | 80 % | ✓ |
| LedgerPersistence | 2438 / 2455 | 99.30 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 7983 / 8100 | 98.55 % | 80 % | ✓ |

**Release build:** `swift build -c release`: exit 0 (39 s). **Host:** the whole package passes except
`LedgerDesignTests`' Archivo font suites (host only, as on `main`).

**Simulator launch** (`f07s2/launch-check.sh` under the lock, the gate's builds, the apps uninstalled first): both
apps are still running after 6 s with no crash report. Each has `Application Support/Database/ledger.sqlite` (+
`-wal`, `-shm`) holding 224 `exercise` rows and one `device` row (`phone|iPhone`, `watch|Apple Watch`). Screenshots
show the "Ledger" placeholder, and `-LEDGER_UITEST 1` creates `tmp/LedgerUITest-<uuid>/ledger.sqlite`.

**Open questions**
1. The preflight costs one extra read-only open on every launch (a single statement pair; not timed). Recommend
   F20 include it in the device launch timing; no change now.
2. A file with Ledger's migrations but a damaged schema (a known id whose tables were altered) passes the preflight
   and fails, or partly writes, in a later migration, as the new `LedgerStores.open` doc says. Recommend
   GRDB's `hasSchemaChanges`-style check only if F28's repair tooling needs it.


### S2 fix round 2 (G1 implementer, 2026-10-04)

From `test-findings.md` "# Slice S2 — close-out round" (F7-S2-3), with the orchestrator's binding decision: the launch
owns its steps; scene-phase calls only wait for them. Branch at `2d41d18`.

**What changed** (`LedgerPersistence/DatabaseLaunch.swift`)
- `running: [LaunchStep: Task<Void, Never>]` and `ended: Set<LaunchStep>` (`:52`–`:56`) replace round 1's bookkeeping.
  `task(for:retrying:_:)` (`:125`) returns the step's running task. If none is running, it starts a new plain `Task`,
  which the launch owns, when the step has not run, or has run and `retrying`; otherwise it returns nil. The check
  and the start happen with no suspension between them on the main actor, so two calls never start a step twice.
- `resume(isForeground:)` (`:103`):
  - reopens on a foreground call after the first (#29);
  - gets the seed's task, which may be retried only on a foreground call while unseeded (`:114`, #28), and
    awaits it;
  - then gets and awaits the settings' task (never retried).

  A call that finds a step running awaits that same task, so it returns only once every step it reached has an
  outcome. Cancelling a call cancels no step: the step's task is not the caller's, so GRDB never sees the
  cancellation.
- `seedCatalog(_:)` and `loadSettings(_:)` are plain methods: record `.began`, run, record `.failed` on an error.

**Removed:**
- the `Outcome` enum (`attempted`/`cancelled`/`elsewhere`);
- the `CancellationError` catch;
- the `running` set;
- `hasFinishedFirstPass`;
- `hasLoadedSettings` (a settings step that ended is never rerun).

I also dropped the two `Task.isCancelled` guards I had planned (a cancelled caller starting no further step). A
caller's `await task.value` is not interrupted, so a cancelled caller waits like any other and then goes on to the
next step, which it may start; the step runs once either way. Mutant N5 (removing the middle guard) survived
because the guard changed nothing observable. So, per the decision ("remove what's no longer needed"), a call
starts or joins every step, and cancelling it changes nothing for the steps. The wait does not end early on
cancellation: SwiftUI does not await a cancelled `.task`, and a step is bounded by the 5 s busy timeout.

**Sanctioned edit** (approved 2026-10-04; the tester audits it): `LaunchCloseoutAdversarialTests.cancelledPass_thenBackground_runsIt`
and its `Watch…` twin keep their setup. They drop "not seeded right after the cancelled call", which is now a race,
because the seed is no longer cancelled. "began loadSettings" twice becomes **each step begins exactly once** (seed
and settings): the old count of 2 encoded the abandoned-then-restarted mechanism this round removes. They keep "no
`failed…`" and "seeded after the background call", and add "`composition.settings` equals the stored settings".
No other tester test changed (`git diff 2d41d18 -- '*Adversarial*'`: these two files only).

**Proving tests**
- The tester's F7-S2-3 repro `seedCancelledBeneathAForegroundCall_runsOnTheNextCall` and its `Watch…` twin pass
  unedited. So do every round-1 and close-out tester test and the random-phase model, on the host and on both
  simulators.
- `DatabaseLaunchConcurrencyTests` (new suite, my tests):
  - `cancelledCaller_neverCancelsTheStep`: the seed waits for a held writer, the caller is cancelled, and the seed
    still seeds, with no failure;
  - `cancelledBeforeStarting_runsEveryStepOnce` (replaces round 1's `cancelledPass_isNotAttempted_andRunsAgain`);
  - `overlappingCall_waitsForTheRunningStep`: a call that finds the seed running begins the settings only after
    the seed's outcome;
  - `overlappingCalls_startEachStepOnce`.

**Mutants** (one at a time, scratchpad copy `f07s2/mut2/`, since deleted):

| Mutant | Result |
|---|---|
| N1 the step owned by the caller (its cancellation cancels the step) | killed: `cancelledCaller_neverCancelsTheStep`, `cancelledBeforeStarting_…`; tester's F7-S2-3, `cancelledPass_thenBackground_runsIt`, `cancelledFirstResume_logsNoFailure` |
| N2 an overlapping caller does not wait for the running step | killed: `overlappingCall_waitsForTheRunningStep` |
| N3 a failed seed retried in the background | killed: `seedFailure_carriesOn_thenRetriesInTheForeground`; tester's `randomPhases_matchTheModel` |
| N6 the seed not awaited before the settings | killed: 8 tests (e.g. `open_thenFirstPass`, `overlappingCall_…`, the model) |
| N4/N5 the cancelled-caller guards removed | the guards were removed from the product (above), so these mutants no longer exist |

**Gate.** Full `scripts/check.sh` under the lock: **exit 0, `check.sh OK`**; 17 test targets passed (PR), 8
(PR-Watch). Summary: tools 1 s, format 0 s, lint 59 s, iOS build 20 s, iOS tests 211 s, watchOS build 17 s, watchOS
tests 179 s, coverage 1 s, total 489 s. **Warnings:** only F05's `PayloadVersionAdversarialTests.swift:29`.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 195 / 203 | 96.05 % | 90 % | ✓ |
| LedgerDesign | 1946 / 2002 | 97.20 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerHealth | 37 / 37 | 100.00 % | 80 % | ✓ |
| LedgerPersistence | 2441 / 2458 | 99.30 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 7986 / 8103 | 98.55 % | 80 % | ✓ |

**Release build:** `swift build -c release`: exit 0 (39 s). **Host:** the whole package passes except
`LedgerDesignTests`' Archivo font suites (host only, as on `main`).

**Code lines** (F05's method): this round +45 / −41 product, +101 / −31 tests. Whole slice vs `f991d69`: **product
632 added, 18 removed**.

## Slice S3 — roots, Today, debug menu, UI tests (G1 implementer, 2026-10-04)

Branch `feat/F07-s3-roots`, cut from `feat/F07-s2-boot` at `2ca2317` (S2 is PR #24). No commits.

### What landed

- **Roots.** `AppRootView` → `AppRoot` (`LedgerAppKit/AppRoot.swift`), `WatchRootView` → `WatchRoot` (`git mv`); the
  apps call them. Each renders the composition's state: `.ready` → the Today placeholder, `.databaseUnavailable` →
  decision #29's screen (now `DatabaseUnavailableView`, unchanged copy), `.idle` (a process hosting unit tests) →
  the ground colour. The async launch stays `.task(id: scenePhase)`; `.onAppear` calls `composition.rootAppeared()`.
- **Today placeholders** (`LedgerAppKit/TodayPlaceholder.swift`, `LedgerWatchAppKit/TodayPlaceholder.swift`): the
  title "Today" alone (`.display` on the phone, `.watchTitle` on the watch, ink on ground; identifier `today.title`).
  In Debug a long press on the title opens the debug menu (`.onLongPressGesture` under `#if DEBUG`). F09/F18 replace
  them.
- **Debug menu and Diagnostics** (`#if DEBUG`), shared by both apps in `LedgerDesign/Gallery/` beside `DesignGallery`:
  - `DebugMenu` (a sheet from `AppRoot`/`WatchRoot`): a `NavigationStack` of two `HairlineRow`s, "Design gallery" →
    `DesignGallery`, "Diagnostics" → `DiagnosticsPage`. Identifiers `debug.menu.designGallery`,
    `debug.menu.diagnostics`.
  - `DiagnosticsPage`, `DiagnosticsSection`, `DiagnosticsLine`: sections of label/value lines in the phone's or the
    watch's type roles; each value carries `debug.diagnostics.<key>`. The page only draws; `DiagnosticsLoader` (the
    menu's destination) reads the sections in `.task` when it appears.
  - Each umbrella builds the sections (`AppComposition+Diagnostics.swift`, `WatchComposition+Diagnostics.swift`):
    "App" = database path, device id, Health, launch to first frame, swift-dependencies' context; "Rows" = every
    table's row count. It reads `composition.stores` (the `LedgerStores` value), **never a dependency key**, so S2-N2
    holds by construction: the menu is reachable only from Today (`.ready`), and even then reads no key.
- **LedgerPersistence** `DatabaseDiagnostics.swift`: `LedgerStores.diagnostics()` — path, device id, and
  `SELECT COUNT(*)` per table from `sqlite_master` (SQLite's own `sqlite_*` tables left out, names quoted), one read.
- **LedgerHealth** `HealthAuthorization.swift`: `HealthAuthorization` (`unavailable`, `notDetermined`, `denied`,
  `authorized`), `init(HKAuthorizationStatus)`, and `workouts(isAvailable:status:)`, whose defaults read
  `HKHealthStore.isHealthDataAvailable()` and `authorizationStatus(for: .workoutType())` — the sharing status, as
  HealthKit reports no read status. It never requests authorization.
- **Launch to first frame (decision #30).** `LedgerDependencies/ProcessStart.swift`: the kernel's start time of the
  process (`sysctl KERN_PROC_PID`). Each composition's `Environment` gains `processStart` (memberwise default nil;
  live = `ProcessStart.date()`); `rootAppeared()` records `launchToFirstFrame = now − processStart` once and logs
  "First frame N ms after the process started" at notice level (category `launch`), so it is readable in Release too.
- **Preview registry (criterion 8).** Each module with previews has a registry enum, one case per `#Preview`, whose
  `content` the `#Preview` body shows: `DesignPreview` (LedgerDesign, F06's 18 + `DebugMenu`, `DiagnosticsPage`; the
  file's previews now read `DesignPreview.x.content`), `AppPreview` and `WatchPreview` (Today, Database unavailable).
  `LedgerTestSupport/Previews/PreviewScan.swift` reads `LedgerKit/Sources` (as `ModuleBoundaryTests` reads its
  module): each `#Preview` at the start of a line, its string-literal name or nil; `registeredModules` lists the
  modules whose tests check a registry. `LedgerSnapshotTesting/PreviewRendering.swift`: `renderPreview(_:size:)`.
- **UI tests** (string identifiers; the UI test targets link no package product):
  - `LedgerUITests/Smoke.test_launchesToToday` and `LedgerWatchUITests/Smoke.test_launchesToToday` replace the
    "Ledger" placeholder test (PR plans, as before).
  - `LedgerUITests/DebugMenu` and `LedgerWatchUITests/DebugMenu` `.test_diagnostics_showsTheSeededCatalog`: long press
    on the title, open Diagnostics, `rows.exercise` ≥ 200, path ends `/ledger.sqlite`, context `live`, launch "N ms",
    device id a non-nil UUID; attaches "Today" and "Diagnostics" screenshots (kept). Nightly only.
  - `LedgerUITests/LaunchPerformance.test_launchToFirstFrame`: `XCTApplicationLaunchMetric(waitUntilResponsive:
    true)` over 5 launches, then attaches the in-app figure from Diagnostics. No baseline, so it reports and never
    gates (#30). Nightly only.
  - Every UI test launches with `-LEDGER_UITEST 1`. Test plans unchanged: the PR plans select `Smoke`, the Nightly
    plans run every UI test.
- **Snapshots**: `TodaySnapshotTests` in `LedgerAppKitTests` (phone, light and dark, `.large`: 2 references) and
  `LedgerWatchAppKitTests` (46 mm at its default size: 1 reference), through `assertLedgerSnapshot`.
  `snapshotTestTargets` gains `LedgerAppKit`, `LedgerWatchAppKit` (an `exclude`, not a graph edge; the graph checker
  passes unchanged). Recorded with `check.sh --record-snapshots` under the lock: only the 3 new PNGs appeared; every
  existing reference re-recorded byte-identical.
- **Docs**: architecture §14's Diagnostics line (it said "in Settings"; A-decision drift, now the debug menu and what
  the page shows).
- **Screenshots (M0 exit)**: `tasks/features/F07-composition-di/screenshots/` — `iphone-today.png`,
  `watch-today.png` (plain `simctl` launches on the real Application Support database: 224 `exercise` rows, one
  `device` row each), `iphone-diagnostics.png`, `watch-diagnostics.png` (the nightly `DebugMenu` UI tests'
  attachments, so the path is the UI test's temporary file).

### Decisions and deviations

1. **N-c settled: `isTesting` is false in an XCUITest-launched app.** The `DebugMenu` UI tests read
   swift-dependencies' context from Diagnostics and it is `live` on both simulators. No `$0.context = .live` was
   needed; the UI tests now pin it (they fail if a later Xcode makes it `test`). S2-N1's `-LEDGER_UITEST` override in
   `launch()` stays as a belt.
2. **DebugMenu and the Diagnostics page live in `LedgerDesign/Gallery`, not `LedgerAppKit/DebugMenu.swift`** (the
   brief's Touches). Both apps need the same menu and page; `LedgerDesign` is the one UI module both umbrellas share,
   and it already holds the Debug-only `DesignGallery` the menu opens. The page only knows labelled strings; what
   goes in it (Persistence, Health, Dependencies types) is assembled in each umbrella, ~34 lines each. A first cut
   with per-umbrella views measured 649 product lines with ~200 duplicated; this one is 560.
3. **Diagnostics reads the composition's `LedgerStores`, not the store keys** (S2-N2): the strongest form of "no read
   before ready". `DiagnosticsTests.diagnostics_readTheCompositionsStores` runs it with no key bound, so any key read
   would fail the test naming the key.
4. **Launch-to-first-frame ends at the root's first `onAppear`** (the same run-loop turn the first frame commits in),
   and begins at the kernel's process start, so it includes dyld, `App.init` and the synchronous database open.
5. **`health` is a defaulted parameter of `diagnostics(health:)`**: the package test host has no HealthKit
   entitlement (S2 deviation 8), so the tests pass the value; the app reads HealthKit.
6. **The page draws; a separate loader reads.** Two gate runs crashed the xctest process in `ImageRenderer.deinit`
   (an `AppearanceEffect.willRemove` assertion) on the `DiagnosticsPage` preview, first on iOS, then on watchOS: an
   `ImageRenderer` that drew a scroll view holding an appearance action (`.task`) traps when it is released. So the
   page has no `.task`; `DiagnosticsLoader` holds it, and only the menu's destination makes one. Also, on iOS,
   `renderPreview` hosts the preview in a `UIHostingController` in a window and draws the hierarchy, as a preview
   shows it and as `accessibilityElements` hosts views (its `SceneLessWindow` is now internal, not private); watchOS
   and the Mac host draw with `RenderedImage`. The trap is SwiftUI's; a preview with a `.task` in a scroll view would
   need the iOS path or the same split (open question 3).
7. **Watch Diagnostics is the same page in watch type, not a cut-down list**: one shared page is less code than a
   second, smaller one, and the watch UI test reads the same identifiers.
8. **The `DebugMenu` UI tests are Nightly only** (≈ 10 s each); the PR plans keep `Smoke` (≈ 6 s). The PR gate still
   proves the data half through `AppCompositionTests`/`WatchCompositionTests` and the new `DiagnosticsTests`.
9. **`.idle` renders the ground colour**, not Today: only a process hosting unit tests is idle, and Today there would
   offer a debug menu with no database.

### Criteria → tests

| Criterion | Test |
|---|---|
| 1 — iOS launches to Today; file in Application Support; ≥ 200 rows; launch time measured (nightly) | `LedgerUITests/Smoke.test_launchesToToday` (PR); `LedgerUITests/DebugMenu.test_diagnostics_showsTheSeededCatalog` (on screen: 224 ≥ 200, `/ledger.sqlite`, context `live`); `LedgerUITests/LaunchPerformance.test_launchToFirstFrame` (nightly, reports); package: `AppCompositionTests.boot_opensTheFile_andBindsTheStores` (S2), `DiagnosticsTests.diagnostics_readTheCompositionsStores`, `rootAppeared_measuresOnce`, `noStartTime_measuresNothing`; `DatabaseDiagnosticsTests` (2); `ProcessStartTests` |
| 2 — the watch, its own database | `LedgerWatchUITests/Smoke.test_launchesToToday` (PR-Watch); `LedgerWatchUITests/DebugMenu.test_diagnostics_showsTheSeededCatalog` (nightly); `LedgerWatchAppKitTests` `Watch diagnostics` (5, the iPhone's twins, kind `watch`) |
| 7 — debug menu (Debug only, long press on the title) → DesignGallery and Diagnostics (path, row counts, device id, health) | both `DebugMenu` UI tests (long press, both rows present, Diagnostics values); `DiagnosticsTests` (both umbrellas: lines, labels, "Not open" before the database opens, the error when the database cannot be read); `HealthAuthorizationTests` (3); `PreviewTests.diagnosticsLine_formats`; Release builds without any of it (`swift build -c release`) |
| 8 — every `#Preview` renders | `PreviewTests` in `LedgerDesignTests` (20 cases), `LedgerAppKitTests` (2), `LedgerWatchAppKitTests` (2): `registry_listsEveryPreview` (scan == registry, no unnamed, no duplicate) and `preview_renders` (every case); `LedgerDesignTests` `everyModuleWithPreviews_isRegistered` (package-wide: a module with a `#Preview` and no registry fails) and `scan_parsesDeclarations` |
| Snapshot — Today placeholder light/dark | `TodaySnapshotTests` (phone light + dark; watch 46 mm) |

### Code lines (F05's method: added lines of `git diff -U0 2ca2317`, new files whole, blank and whole-line comment lines excluded)

| Path | Added | Removed |
|---|--:|--:|
| `LedgerAppKit` (root, Today, diagnostics sections, previews, launch timing) | 127 | 1 |
| `LedgerWatchAppKit` (the same) | 126 | 1 |
| `LedgerDesign` (`DebugMenu` 39, `DiagnosticsPage` and loader 80, the preview registry rewrite of `Components+Previews.swift`) | 228 | 31 |
| `LedgerPersistence` (`DatabaseDiagnostics`) | 37 | 0 |
| `LedgerHealth` (`HealthAuthorization`) | 26 | 0 |
| `LedgerDependencies` (`ProcessStart`) | 13 | 0 |
| `Apps/Ledger`, `Apps/LedgerWatch`; `Package.swift` | 3 | 3 |
| **Product** | **560** | **36** |
| of which `*+Previews.swift` (registries and `#Preview`s) | ≈ 155 | |
| `LedgerTestSupport` (`PreviewScan`) / `LedgerSnapshotTesting` (`renderPreview`) | 41 / 25 | 0 / 1 |
| Tests (package and UI) | 479 | 8 |

Over the 500 target by 60, under ~700: the PR description says so. Without the preview files it is about 406. The
split considered was "previews and registry (criterion 8)" as its own slice; not taken, because the registry has to
list S3's own new previews, so it would land after S3 and edit the same files again.

### Gate and coverage

Full `scripts/check.sh` under the simulator lock, run 4: **exit 0, `check.sh OK`**; 17 test targets ran and passed
(PR), 8 (PR-Watch). Summary: tools 0 s, format 0 s, lint 63 s, iOS build 21 s, iOS tests 205 s, watchOS build 13 s,
watchOS tests 183 s, coverage 1 s, total 487 s. **No new warnings** (the gate log has none; the scratch builds show
only F05's `PayloadVersionAdversarialTests.swift:29` "will never be executed").
- Run 1 was stopped by me before it finished (a redesign, decision 2). Runs 2 and 3 failed only
  `PreviewTests.preview_renders(.diagnosticsPage)` (the `ImageRenderer` trap, decision 6), on iOS and then on watchOS.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 204 / 213 | 95.77 % | 90 % | ✓ |
| LedgerDesign | 2113 / 2175 | 97.14 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerHealth | 47 / 48 | 97.91 % | 80 % | ✓ |
| LedgerPersistence | 2479 / 2497 | 99.27 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 8210 / 8336 | 98.48 % | 80 % | ✓ |

(LedgerAppKit and LedgerWatchAppKit stay excluded from the gate, as before.)

**Release build:** `cd LedgerKit && env -u SDKROOT swift build -c release --only-use-versions-from-resolved-file`:
exit 0 (30 s). **Host:** every new and touched suite passes on the Mac (`PreviewTests`, `DiagnosticsTests`,
`TodaySnapshotTests` (no cell drawn on the host), `DatabaseDiagnosticsTests`, `HealthAuthorizationTests`,
`ProcessStartTests`, the composition suites).

**Nightly UI suites** (run once under the lock on the final code, `-only-testing` each UI target with the Nightly
plans): iOS `Smoke` 6.5 s, `DebugMenu` 10.8 s, `LaunchPerformance` 36.7 s; watch `Smoke` 5.3 s, `DebugMenu` 9.7 s. All
passed.

**Launch to first frame** (decision #30: reported, not gated; iPhone 17 and Apple Watch Series 12 (46mm) simulators,
27.0, Debug):

| How launched | iPhone | Watch |
|---|---|---|
| `XCTApplicationLaunchMetric` (first frame, responsive), 5 launches | 2.435, 2.457, 2.586, 2.471, 2.472 s (mean 2.484 s, RSD 2.1 %) | — (iOS only, as the brief) |
| In-app, under XCUITest (Diagnostics, the log line) | 2308 ms (and 2.25–2.59 s over the metric's launches) | 1754, 1316 ms |
| In-app, plain `simctl launch` (the log line), first launch after install | 1291 ms | 431 ms |
| In-app, plain `simctl launch`, warm | 353, 335 ms | 363, 340 ms |

The UI-test launches are 1.3–2.6 s because XCUITest launches the app under its own instrumentation; a plain launch of
the same build is 0.34–0.36 s warm, inside the 600 ms budget, and 1.29 s (iPhone) / 0.43 s (watch) on the first launch
after install (dyld's first load, the new database file). None of these is the device's number (#30, F20/F26).

### How to verify by hand

- Launch either app in the simulator and long-press "Today": the Debug sheet lists "Design gallery" and "Diagnostics".
  Diagnostics shows the file under `Application Support/Database/ledger.sqlite`, this device's id (the `device` row:
  `sqlite3 … 'SELECT id, kind FROM device'`), Health "Not determined" on a fresh simulator, the launch in ms,
  "Dependencies live", and 224 `exercise` rows.
- `xcrun simctl spawn booted log show --last 5m --predicate 'subsystem == "com.petearevalo.Ledger" AND eventMessage
  CONTAINS "First frame"'` prints each launch's first-frame time.
- Criterion 8: add `#Preview("X") { Text("x") }` to any `LedgerAppKit` file and run `swift test --filter PreviewTests`:
  `registry_listsEveryPreview` fails; add one to a feature module and `everyModuleWithPreviews_isRegistered` fails.
- In Release (`swift build -c release`) `DebugMenu`, `DiagnosticsPage` and the long-press gesture do not exist.
- Screenshots: `tasks/features/F07-composition-di/screenshots/`.

### Open questions (with recommendations)

1. **Launch-time UI number vs the in-app number.** The nightly's `XCTApplicationLaunchMetric` (~2.5 s) and the in-app
   figure under XCUITest (~2.3 s) measure XCUITest's launch, not a lifter's. Recommend F20 times a plain cold launch on
   a device and F26 gates that, and the nightly keep reporting only (as #30 says); no change now.
2. **Testing-strategy §2.7 drift**, left for the orchestrator (docs are not this slice's call): it names
   `Launch.coldLaunchUnder600ms` (built as `LaunchPerformance.test_launchToFirstFrame`, per the brief),
   `Smoke.launchesToIdle` on the watch (built as `launchesToToday`, per the brief; F18 renames it when the watch's idle
   screen lands), and says the UI test targets link the umbrellas and share identifier enums (they link no product,
   so identifiers are strings, `today.title`, `debug.menu.*`, `debug.diagnostics.*`). Recommend one line each in §2.7.
3. **Previews with an appearance action.** On watchOS (and with `RenderedImage` anywhere) a preview whose content puts
   a `.task`/`.onAppear` inside a scroll view traps the smoke test's `ImageRenderer` on release. Recommend features keep
   the same split as `DiagnosticsPage`/`DiagnosticsLoader` (stores load in the root, previews draw a state), which
   F09's store-driven screens do anyway; the testing-strategy line on previews could say so.
4. **Debug menu placement in LedgerDesign** (deviation 2) versus the brief's `LedgerAppKit/DebugMenu.swift`. Recommend
   accepting: one menu and page for both apps, Debug only, beside the gallery; architecture §14 now names them.
5. **Should the `DebugMenu` UI tests join the PR plans?** About 10 s per platform per PR run (≈ 20 s of macOS minutes
   on the full gate, 10 s on CI's `--ios-only`). Recommend Nightly only, as now, given the CI budget; the PR gate keeps
   the package-level data checks.
6. **Watch Diagnostics' long path** fills the first screen on the watch (the screenshot). Recommend leaving it (Debug
   only, scrolls); F18 can trim the watch page if it grows.
7. **Size** 560 product lines, over the 500 target (PR description says so; ≈ 155 of them are preview registries).

### S3 fix round 1 (G1 implementer, 2026-10-04)

From `test-findings.md` "# Slice S3 — adversarial round 1" (F7-S3-1, F7-S3-2, V10) and `review.md` "# Slice S3 review"
(S3-SF1, N1–N4, open question 2), with the orchestrator's binding decisions 1–8. Branch at `326bb04`; no tester test
edited (`git diff 326bb04 -- '*Adversarial*'` is empty).

| # | Finding | Change | Proving test(s) |
|---|---|---|---|
| 1 | F7-S3-1 | `PreviewScan.previews(in:)` splits on `\.isNewline` (`\n`, `\r\n`, `\r`; `PreviewScan.swift:35`) and drops leading attributes before looking for `#Preview` (`droppingAttributes`, `:54`: `@name` with an optional balanced `(…)`, then spaces, repeated) | the tester's `attributedPreview_isFound`, `crlfFile_everyPreviewFound`, `attributeOnPreviousLine_andTabs_areFound`, unedited; `PreviewTests.scan_parsesDeclarations` gains `@available(iOS 18, *) @MainActor  #Preview("Attributed")`, an attributed non-preview, and a CRLF source |
| 2 | S3-SF1 | `renderPreview(size:_:)` (`PreviewRendering.swift:15`) now takes a `@ViewBuilder` closure and builds and draws it inside `withDependencies { $0.context = .preview }` (`:17`), as Xcode runs a `#Preview`; the three `PreviewTests` call it so. testing-strategy §2.6 has the line: previews draw a state, loading goes in a loader view, registry + `renderPreview` + `PreviewScan` | `PreviewTests.preview_readingAStoreKey_getsItsPreviewValue` (`LedgerDesignTests`): a view reading `@Dependency(\.programRepository)` renders with no issue and sees `InMemoryProgramRepository` |
| 3 | F7-S3-2, S3-N1 | `LedgerPersistence/DatabaseDiagnostics.swift` and all of `LedgerDesign/Components/Components+Previews.swift` (the `DesignPreview` registry and F06's `#Preview`s) are inside `#if DEBUG`; so are their tests (`DatabaseDiagnosticsTests`, LedgerDesign's `PreviewTests`) | Release symbol check below |
| 4 | S3-N4 | The watch's #29 screen paints `LedgerColor.watchGround` (`WatchRoot.swift:50`). No snapshot: a new reference costs a record run of both plans; the `Database unavailable` preview renders in `WatchPreview`'s smoke test | `WatchAppKit` `PreviewTests.preview_renders(.databaseUnavailable)` |
| 5 | S3-N2 | Noted only: the scan checks names, and a `#Preview` body that does not show its own case is a code-review matter (every body is one `Registry.case.content` line) | — |
| 6 | S3-N3 | Screenshots left as committed | — |
| 7 | Q2 | testing-strategy §2.7: `LaunchPerformance.test_launchToFirstFrame` (reports, never gates, #30) for `Launch.coldLaunchUnder600ms`; the watch's `Smoke.launchesToToday` (`launchesToIdle` once F18 replaces the placeholder); identifiers are strings because the UI test targets link no package product (replacing the "link the umbrellas, share the enums, verify in F01" sentence) | — |
| 8 | V10 | `ProcessStartTests.processStart_keepsMicroseconds`: a reference `sysctl` read of the same `p_starttime` field in the test, kept whole; the start's whole seconds equal `tv_sec` and its fraction equals `tv_usec` within 1 µs. Deterministic: both read the same kernel record of this process | itself (mutants M5, M6) |

**Mutants** (one at a time, scratchpad copy `f07s3/mut/`, since deleted; host `swift test`):

| Mutant | Killed by |
|---|---|
| M1 the scan splits on `"\n"` again | tester's `crlfFile_everyPreviewFound`; `scan_parsesDeclarations` |
| M2 no attribute skipping | tester's `attributedPreview_isFound`; `scan_parsesDeclarations` |
| M3 attribute arguments not balanced (only `)` counted) | tester's `attributedPreview_isFound`; `scan_parsesDeclarations` |
| M4 `renderPreview` in the `test` context | `preview_readingAStoreKey_getsItsPreviewValue` |
| M5 the start time without microseconds (V10) | `processStart_keepsMicroseconds` |
| M6 the start time rounded to milliseconds | `processStart_keepsMicroseconds` |

The `#if DEBUG` wraps (decision 3) and the watch's ground (decision 4) have no package mutant: the first is proved by
the Release binaries, the second is a colour the watch already shows.

**Release symbol check** (under the lock: `xcodebuild build -configuration Release`, `generic/platform=iOS Simulator`
and `watchOS Simulator`, `CODE_SIGNING_ALLOWED=NO`, scratch derived data since deleted; both exit 0). `nm -m` of
`Ledger.app/Ledger` (63,339 symbols) and `LedgerWatch.app/LedgerWatch` (62,819), demangled:
`DatabaseDiagnostics` 0, `LedgerStores.diagnostics` 0, `DesignPreview` 0, `DiagnosticsPage` 0, `DiagnosticsLoader` 0,
`DesignGallery` 0, `PreviewScan` 0, `LedgerFakes` 0, `debug.menu`/`debug.diagnostics` strings 0. What remains is by
design: `ProcessStart` (9) and `rootAppeared` (6), the #30 measurement and its Release log line; and 2 `DebugMenu`
matches, which are `AppRoot._isDebugMenuShown`'s `@State` (the review's "considered and not raised"). The tester's
round counted 81 `DatabaseDiagnostics` symbols in each binary before this change.

**Release build (package):** `swift build -c release`: exit 0.

**Code lines** (F05's method): this round vs `326bb04`, product +144 / −147, almost all the re-indentation of the two
files wrapped in `#if DEBUG`; the logic is ~+3 (the watch's ground, the `#if`s) and in test support +18 / −2
(`PreviewScan`), +10 / −1 (`renderPreview`). Whole slice vs `2ca2317`: product **+592 / −71** (the re-indented
`Components+Previews.swift` now counts its F06 lines as removed and added again). Tests this round +135 / −90.

**Gate.** Full `scripts/check.sh` under the lock: **exit 0, `check.sh OK`**; 17 test targets passed (PR), 8
(PR-Watch), the tester's round-1 suites among them. Summary: tools 1 s, format 0 s, lint 60 s, iOS build 38 s, iOS
tests 212 s, watchOS build 30 s, watchOS tests 185 s, coverage 1 s, total 527 s. **No warnings** in the gate log.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 204 / 213 | 95.77 % | 90 % | ✓ |
| LedgerDesign | 2113 / 2175 | 97.14 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerHealth | 47 / 48 | 97.91 % | 80 % | ✓ |
| LedgerPersistence | 2479 / 2497 | 99.27 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 8210 / 8336 | 98.48 % | 80 % | ✓ |
