# ADR-008: A `LedgerFakes` module for previews and tests

**Status:** Accepted · **Date:** 2026-10-03 · **Decided by:** Pete (product owner, decision B1); the error move
by the orchestrator (2026-10-03) · **Evidence:** `tasks/features/F07-composition-di/implementation-notes.md`
(slice plan, decisions, "Slice S1")

Changes the module graph in architecture §3 (F00's target table) and closes its open question about
`LedgerTestSupport` in the features' spine.

## Context

F00 gave every feature target an edge to `LedgerTestSupport` so that `#Preview` bodies could use its
fixtures. `LedgerTestSupport` depends on Persistence, Health, Sync and Design, so every feature had a
transitive link to the whole stack, which the module rule ("a feature never imports Persistence, Health or
Sync") exists to prevent. The cost stayed invisible while the modules were placeholders; F07 makes it real:

- every dependency key needs a `previewValue` (architecture §13), which must be an in-memory store seeded with
  fixtures. The keys live in `LedgerDependencies`, which the apps link, so those stores must be reachable from an
  app-linked module without pulling GRDB, HealthKit or WatchConnectivity code into it;
- the same in-memory stores back the store tests (`withTestDependencies`), and must keep the F05 repository
  contracts (criterion 4), so previews and tests must share one implementation.

A second problem surfaced while building the fakes. The contracts check the errors the protocols promise by name
(`missingRow`, `duplicateIdentifier`, `nulInText`, `notFinished`) as `LedgerPersistenceError`, which lived in
`LedgerPersistence`. A fake that depends on `LedgerDomain` alone could not throw them.

## Decision

1. **A new `LedgerFakes` target**, depending on `LedgerDomain` only, every source file wrapped in `#if DEBUG`
   (empty in a Release build). It holds:
   - the in-memory stores: `InMemoryExerciseRepository`, `InMemoryProgramRepository`,
     `InMemorySettingsRepository`, `InMemoryWorkoutEventStore` (moved from `LedgerDomainTests`),
     `InMemoryWorkoutRepository` and `InMemoryStatsQueries` (ported from F05's adversarial `HistoryModel`, without
     its fault injection), bundled as `InMemoryStores`, linked where one database links them: the stats read the
     workouts' history, a materialised workout's slot updates reach the programs in the same step, and a program
     saved with a slot naming an exercise the exercise store lacks is refused (`unknownExercise`, the slot's
     foreign key; product decision #28). Settings and the event store stand alone, as their tables do;
   - `Fixtures` (the spec's seed program with catalog ids, a session, a history, settings);
   - `FakeLinkBus`, a protocol-free in-memory network for sync tests, and empty fakes of the device protocols.
2. **Edges.**
   - `LedgerDependencies → LedgerFakes`, so each key's `previewValue` (compiled `#if DEBUG`) is a seeded fake.
   - The features' spine swaps `LedgerTestSupport` for `LedgerFakes`: a `#Preview` reaches fixtures without
     linking Persistence, Health or Sync.
   - `LedgerTestSupport → LedgerFakes`, re-exported (`@_exported import`), so a test that imports
     `LedgerTestSupport` gets the fakes, `withTestDependencies` and the contracts.
   - `LedgerTestSupport` is no longer linked by any library target: only test targets and
     `LedgerSnapshotTesting` use it.
   - The test targets that run the fakes (`LedgerPersistenceTests`, `LedgerDependenciesTests`,
     `LedgerSyncTests`) also depend on `LedgerFakes` directly: Xcode measures coverage only of a test target's
     direct dependencies, and the fakes are gated (the first full gate measured none of their lines).
3. **`RepositoryError` moves to `LedgerDomain`**, beside the protocols that promise its cases, unchanged. The
   GRDB stores keep throwing it under its old name: `LedgerPersistence` declares
   `public typealias LedgerPersistenceError = RepositoryError`, so no call site, contract or suite changed. No case
   carries a GRDB or SQLite type.
4. **Shared state behind a `Mutex`, not an actor.** The repository protocols' `observe…()` methods are
   synchronous, and no write made after the call may be missed. GRDB guarantees that by queueing the
   observation's first fetch on the writer before any later write; a fake registers its observer, and yields
   its first value, under a `Synchronization.Mutex` before `observe…()` returns, and runs each write whole under
   it. A stream keeps only its newest value (`.bufferingNewest(1)`), as GRDB's bridge does. The event store,
   whose protocol is all `async`, stays an actor. No `@unchecked Sendable` is needed.
5. **The fakes refuse what the database refuses, by one rule** (S1 fix round 1). `StorageBoundary` in
   `LedgerDomain` (a weight is a whole count of 10⁻⁷ g within `Int64`, a date is finite: ADR-007's storage
   rules) is what LedgerPersistence's `ColumnCodec` and every fake call, as `ExerciseSearch` is shared.
   `SettingsCodec` and `EnvelopeCodec` moved to `LedgerDomain` with it, so the fakes keep settings and
   envelopes as their encoding stores them. Each fake checks a value in the order the database's rows meet its
   faults, so two faults throw the same error on both. The contracts' `storageClauses` hold both
   implementations to this; F05's in-memory oracles, which model history and not columns, run only `clauses`.

**Amendment (2026-10-03, F07 S1 fix round 2; flagged to Pete at merge):** `LedgerFakes` also depends on
swift-issue-reporting's `IssueReporting`, which is Foundation-only and already linked through Dependencies, so
that `InMemoryStores` can fail the test that seeds a state no database could hold: a program naming exercises the
seed's catalog lacks (finding F7-10).

## Alternatives rejected

- **Keep `LedgerTestSupport` in the spine.** Leaves the transitive link to the whole stack that the module rule
  forbids, and puts GRDB in every feature's build graph.
- **Preview values in `LedgerTestSupport`.** `LedgerDependencies` would have to depend on it, pulling the whole
  stack into the apps.
- **A fixtures-only `LedgerPreviewFixtures`** (architecture §3's alternative). Previews need working stores, not
  just values, and the stores must be the ones the contracts prove, so the stores and fixtures belong together.
- **`LedgerFakes` depending on `LedgerPersistence` for its errors.** Breaks decision 1 and links GRDB into every
  feature. Matching errors by description, or changing the contracts, would let a fake drift from the database.
- **Actors for every fake.** `observe…()` would have to register its observer from an unstructured `Task`, so a
  write made right after the call could be missed: the contracts' observation clauses would flake.

## Consequences

- The apps' Debug builds link `LedgerFakes` (through `LedgerDependencies`); Release builds link an empty module.
  Nothing outside `#if DEBUG` may name a fake: `LedgerDependencies`' preview values and `LedgerTestSupport`'s
  `withTestDependencies` are wrapped too, so `swift build -c release` of the package builds.
- `scripts/check-package-graph.sh` was re-recorded (`LedgerKit/package-graph.expected.txt`).
- Coverage: `LedgerFakes` and `LedgerDependencies` are gated at 90 % (`scripts/coverage-thresholds.json`);
  `LedgerTestSupport` and `LedgerSnapshotTesting` stay excluded.
- `LedgerFakes` has no test target of its own (like `LedgerTestSupport`): the contracts run its stores in
  `LedgerPersistenceTests`, `FixturesTests` runs in `LedgerDependenciesTests` and `FakeTransportTests` in
  `LedgerSyncTests`.
- A later brief that adds a method to a device protocol grows its fake here, and its stub in
  `LedgerDependencies`.
- A later mechanical rename may drop the `LedgerPersistenceError` alias (an open question in the F07 notes).
