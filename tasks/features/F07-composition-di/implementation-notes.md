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
