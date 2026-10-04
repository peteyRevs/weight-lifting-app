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
