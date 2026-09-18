# ADR-002: GRDB (SQLite) for local persistence on iPhone and Apple Watch

**Status:** Accepted · **Date:** 2026-09-16 · **Evidence:** `docs/research/R2-data-architecture.md`

## Context

Ledger is offline-first on both devices. History queries (last performance per
exercise, best set, estimated-1RM by week, weekly volume and delta, PR
detection) run over tens of thousands of set rows and must be fast and
testable. Cross-device iCloud sync is planned for M4. Swift 6 strict
concurrency is on. The team is small and the delivery pipeline is agent-driven,
so predictability and testability outrank "magic".

## Options

| Option | Assessment (2026-09) |
|---|---|
| **GRDB.swift 7.11.x** | Mature SQLite toolkit; Swift 6 Sendable records; `DatabaseMigrator`; `ValueObservation` as `AsyncSequence`; in-memory `DatabaseQueue` for tests; watchOS 7+; two minor open watchOS issues (suspend-time 0xdead10cc, XCFramework archive). CloudKit via Point-Free SQLiteData 1.12 (CKSyncEngine wrapper) or hand-rolled. |
| SwiftData (iOS 26/27) | WWDC25 added inheritance; WWDC26 added `sectionBy`, `@Attribute(.codable)`, `ResultsObserver`, `HistoryObserver`. Still no SQL-pushed aggregates; CloudKit forbids unique constraints and non-optional relationships; an open iOS 26 sync regression and a watchOS termination bug; community verdict "filling gaps, not confidence-changing". |
| Core Data | Works, but the API is pre-Swift-concurrency and no easier than GRDB for aggregates; NSPersistentCloudKitContainer has the same modelling constraints as SwiftData. |
| Custom SQLite wrapper | Reinvents GRDB. |

## Decision

GRDB 7.11.x on both platforms, behind repository protocols declared in
`LedgerDomain`. Schema is **CloudKit-shaped from day one**: UUID primary keys,
no `UNIQUE` constraints, additive migrations, soft deletes, `updated_at` on
every row, so the M4 sync engine does not require a schema rewrite. Health
data tables are excluded from sync by design.

## Consequences

- Full SQL for the stats queries with indexes and performance tests.
- Deterministic integration tests on in-memory databases; no simulator needed
  for the persistence layer.
- We own migrations explicitly (a feature, not a cost, for an app whose data
  is the product).
- We skip GRDBQuery (stale, `ObservableObject`-based) and write a thin
  `ValueObservation` → `AsyncSequence` bridge ourselves.
- On the watch, keep write transactions short and never hold the database
  across suspension (known 0xdead10cc report).
