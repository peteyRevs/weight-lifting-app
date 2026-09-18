# R2 — Data Architecture Research for "Ledger"

**Date:** 2026-09-16
**Scope:** Local persistence (iPhone + Apple Watch), history/aggregate queries, future iCloud sync, Swift 6 strict concurrency, testability, DI/architecture, Swift Charts, variable fonts.
**Local toolchain (verified on this machine):** Xcode 26.6 (17F113), Apple Swift 6.3.3.
**Method:** Every fact below was checked on 2026-09-16 against a live source; each claim carries a URL. Items that could not be verified are marked **UNCONFIRMED**.

---

## 0. Executive summary and recommendation

**Recommendation: GRDB.swift 7.11.x as the single persistence layer on both iPhone and Watch, with a CloudKit-ready schema from day one, and CKSyncEngine (either hand-rolled or via Point-Free's SQLiteData `SyncEngine`) added later. Do not use SwiftData for this app. Do not adopt TCA.**

Why, in one paragraph: Ledger's core requirements are (a) fast aggregate history queries over tens of thousands of set rows (last performance per exercise, e1RM trends, weekly volume, PR detection), (b) offline-first on the Watch, (c) in-memory databases in tests, and (d) Swift 6 strict concurrency. GRDB gives SQL-pushed aggregates, `ValueObservation`, `DatabaseMigrator`, an in-memory `DatabaseQueue` for tests, Sendable struct records, watchOS 7+ support, and a 7.x line that has shipped monthly through June 2026 with Swift 6.1+/Xcode 26 support ([releases](https://github.com/groue/GRDB.swift/releases), [CHANGELOG](https://github.com/groue/GRDB.swift/blob/master/CHANGELOG.md)). SwiftData, even after WWDC25 (inheritance) and WWDC26 (sectioned queries, `.codable`, `ResultsObserver`, `HistoryObserver`), still has no SQL-pushed aggregate queries ([Blake Crosley, 2026-06-15](https://blakecrosley.com/blog/swiftdata-performance-storage-engine)), forbids unique constraints and non-optional relationships under CloudKit ([Apple](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)), has an open iOS 26 CloudKit-sync regression thread ([Apple Forums, Jan 2026](https://developer.apple.com/forums/thread/811675)) and a watchOS termination bug when CloudKit is enabled ([FB17685611, May 2025](https://developer.apple.com/forums/thread/785378)), and the 2026 community verdict is "filling key gaps rather than making a leap significant enough to fundamentally change confidence in it" ([Fatbobman, 2026-06-09](https://fatbobman.com/en/weekly/issue-139/)).

---

## 1. Toolchain / platform snapshot (September 2026)

| Item | Fact | Source |
|---|---|---|
| Xcode 26.6 | Includes Swift 6.3; SDKs for iOS/watchOS 26.5; requires macOS Tahoe 26.2+ | [Apple release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes) |
| Swift 6.3.3 | Tagged `swift-6.3.3-RELEASE` 2026-06-30 (6.3 released 2026-03-24) | [swiftlang/swift releases](https://github.com/swiftlang/swift/releases), [swift.org 6.3 post](https://www.swift.org/blog/swift-6.3-released/) |
| Xcode 27 | Shipped 2026-09-14 (build 27A266a); Swift 6.4; iOS/watchOS 27 SDKs; requires macOS 26.6+, Apple silicon only; **raises minimum watchOS deployment target 8 → 9**; hard breaks around `@State`-in-init ordering and SE-0508 | [Blake Crosley, 2026-09-14](https://blakecrosley.com/blog/xcode-27-release), [mjtsai 2026-09-15](https://mjtsai.com/blog/2026/09/15/xcode-27/) |
| Swift 6.4 | Released 2026-09-15. App-relevant: SE-0506 fine-grained continuous `@Observable` change notifications; SE-0518 `~Sendable`; SE-0493 async `defer`; SE-0504 task-cancellation shields | [swift.org 6.4 post](https://www.swift.org/blog/swift-6.4-released/), [SwiftLee 2026-06-21](https://www.avanderlee.com/concurrency/swift-6-4-whats-new-in-concurrency/) |
| Xcode 27 defaults to Swift 6 language mode for new projects | **UNCONFIRMED** (appeared only in a search snippet; not verified against Apple release notes) | — |

Implication: staying on Xcode 26.6 is fine today, but Xcode 27 is available if you want iOS/watchOS 27 APIs. All the third-party packages below ship versioned manifests that build on Swift 6.1–6.3 (verified per-tag, see §5).

---

## 2. GRDB.swift

### 2.1 Version, cadence, requirements
- **Latest release: v7.11.1, published 2026-06-18** (GitHub API `published_at`). Change: migration registration made O(1) in DEBUG. [Releases](https://github.com/groue/GRDB.swift/releases) · [CHANGELOG](https://github.com/groue/GRDB.swift/blob/master/CHANGELOG.md)
- Recent line (all dates from the CHANGELOG):
  - 7.11.0 (2026-06-01): option to disable change filtering in `TransactionObserver`; upsert fix for `WITHOUT ROWID` tables.
  - 7.10.0 (2026-02-15): Android/Linux/Windows adjustments; configurable UPSERT column updates.
  - 7.9.0 (2025-12-13): **requirements raised to Swift 6.1+ / Xcode 16.3+**; SQLCipher flag now `SQLITE_HAS_CODEC`; FTS5 task-cancellation crash fix; merged-migration ergonomics.
  - 7.8.0 (2025-10-02): **Merged Migrations** (`registerMigration(_:merging:)`).
  - 7.7.0 (2025-09-23): **Xcode 26 support**; persistable database views.
- Repo is active: last push 2026-09-15, 8,651 stars ([GitHub API](https://api.github.com/repos/groue/GRDB.swift)).
- **Requirements:** iOS 13+ / macOS 10.15+ / tvOS 13+ / **watchOS 7+**, SQLite 3.20+, Swift 6.1+ / Xcode 16.3+ ([README](https://github.com/groue/GRDB.swift/blob/master/README.md)). `Package.swift` is `swift-tools-version:6.1` and lists `.watchOS` among Darwin platforms ([Package.swift](https://github.com/groue/GRDB.swift/blob/master/Package.swift)). Zero external dependencies.
- Performance benchmarks (GRDB 7.0.0 vs FMDB, SQLite.swift, Core Data, Realm, raw C API) last updated 2025-01-26: GRDB fetch-by-index 0.06s vs raw SQLite 0.04s; Codable records 0.24s ([Performance wiki](https://github.com/groue/GRDB.swift/wiki/Performance)).

### 2.2 Swift 6 strict concurrency
Source: [SwiftConcurrency.md (repo docs)](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/SwiftConcurrency.md) — the Swift Package Index mirror returned HTTP 403 during this research.
- "All safety guarantees of Swift 6 are enforced during database accesses." `DatabaseQueue` serializes; `DatabasePool` allows parallel reads + one writer; both expose `read`/`write` sync and async plus `ValueObservation`.
- **Records must be `Sendable`.** Recommended shape is `struct Player: Codable, Identifiable` + `FetchableRecord, PersistableRecord`. The `Record` base class "is not `Sendable`, and its use is actively discouraged since GRDB 7."
- `static let databaseSelection: [any SQLSelectable]` must become a **computed** property under strict checking.
- Enable upcoming feature `InferSendableFromCaptures` (`SWIFT_UPCOMING_FEATURE_INFER_SENDABLE_FROM_CAPTURES=YES`) to silence the shorthand-closure warning (`writer.read(Player.fetchCount)`).
- For `@Observable` models the guide recommends **two types**: an `@Observable` class for the view and a plain record struct for the database.
- Synchronous access from the main thread is explicitly allowed ("SQLite is very fast"), async preferred for slow queries; note a compiler gap where a missing `await` inside a `Task {}` closure isn't diagnosed ([swiftlang/swift#74459](https://github.com/swiftlang/swift/issues/74459)).
- **Default Actor Isolation = MainActor gotcha (applies to GRDB record structs):** with the Xcode 26 default, un-annotated model types are inferred `@MainActor`, which breaks decoding them on GRDB's database threads. Fixes: mark record types `nonisolated`, or put the persistence layer in its own SwiftPM target that keeps the `nonisolated` default ([Fatbobman, 2025-07-30](https://fatbobman.com/en/posts/default-actor-isolation/); [Donny Wals, 2025-06-10](https://www.donnywals.com/setting-default-actor-isolation-in-xcode-26/)). The GRDB tracker shows no MainActor-default issues filed since June 2025 (GitHub issue search, 1 unrelated hit), so the recommended pattern appears stable.
- Tests/previews: "Application previews and tests prefer to use an in-memory `DatabaseQueue` connection" (same doc). The demo app's `AppDatabase` is unit-tested against an in-memory queue ([GRDBDemo README](https://github.com/groue/GRDB.swift/blob/master/Documentation/DemoApps/GRDBDemo/README.md)).

### 2.3 Migration API
Source: [Migrations.md](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Migrations.md)
- `DatabaseMigrator` + `registerMigration("name") { db in ... }`; `migrator.migrate(dbQueue)`; `migrate(_, upTo:)` for tests; `hasCompletedMigrations(db)` / `hasBeenSuperseded(db)` for read-only extensions and "database too new" checks.
- Each migration runs in its own transaction; foreign-key checks are deferred to the end of the migration (use `foreignKeyChecks: .immediate` when renaming FKs).
- Applied-migration memory is stored in a reserved table. `eraseDatabaseOnSchemaChange` exists for DEBUG iteration (README).
- 7.8+ **merged migrations** let you collapse old migrations for fresh installs ([CHANGELOG 7.8.0/7.9.0](https://github.com/groue/GRDB.swift/blob/master/CHANGELOG.md)).

### 2.4 Aggregates and history queries
- `fetchCount`, `select { max($0.score) }` + `Int.fetchOne(db, request)`, multi-aggregate rows, custom SQL functions/aggregates — all pushed to SQLite ([README: Fetching Aggregated Values](https://github.com/groue/GRDB.swift/blob/master/README.md#fetching-aggregated-values), [Custom SQL Functions and Aggregates](https://github.com/groue/GRDB.swift/blob/master/README.md#custom-sql-functions-and-aggregates)). Window functions / CTEs are available through raw SQL and the `SQL` interpolation API. This is exactly what "last performance per exercise", weekly volume, and PR detection need.

### 2.5 ValueObservation for SwiftUI
- `ValueObservation.tracking { db in ... }` with `.start(in:onError:onChange:)`, `for try await x in observation.values(in: db)` (AsyncSequence), or `.publisher(in:)` (Combine) ([README](https://github.com/groue/GRDB.swift/blob/master/README.md); [DatabaseObservation.md](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseObservation.md)).
- Official demo pattern (2026): `AppDatabase` (owns the writer + migrator) injected via SwiftUI environment; `PlayerListModel` is an **`@Observable` object that observes the database** and is unit-tested ([GRDBDemo README](https://github.com/groue/GRDB.swift/blob/master/Documentation/DemoApps/GRDBDemo/README.md)).

### 2.6 GRDBQuery package status
- Latest release **0.11.0, 2025-03-15**; **no commits since** (last commit "v0.11.0" 2025-03-15 per GitHub API). Requires iOS 14+/watchOS 7+, Swift 6+/Xcode 16+, GRDB ≥ 7.0. Provides `@Query` (view-level) and `@EnvironmentStateObject` (which is `ObservableObject`-based, not `@Observable`) ([README](https://github.com/groue/GRDBQuery), [Package.swift](https://github.com/groue/GRDBQuery/blob/main/Package.swift), [releases](https://github.com/groue/GRDBQuery/releases)).
- Assessment: usable but effectively frozen for 18 months and built around `ObservableObject`. For a Swift 6 / `@Observable` codebase, prefer the GRDBDemo pattern (a small `@Observable @MainActor` model that starts a `ValueObservation`) and skip the dependency.

### 2.7 watchOS: support and known issues
- Officially supported (watchOS 7+; README install steps mention the watch extension target) ([README](https://github.com/groue/GRDB.swift/blob/master/README.md)).
- **Open issue #998 (2021-06-24, still open):** `0xdead10cc` termination when a watch extension is backgrounded while GRDB (with SQLCipher 4.2 / GRDB 5.1, watchOS 7.5) holds a lock; `observesSuspensionNotifications` did not help in that report; no maintainer resolution ([#998](https://github.com/groue/GRDB.swift/issues/998)).
- **Open issue #1808 (2025-09-02, no response):** archiving a watchOS framework with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` fails ("no such module 'GRDBSQLite'") — only relevant if you ship GRDB inside a binary XCFramework; SwiftPM source dependency is unaffected ([#1808](https://github.com/groue/GRDB.swift/issues/1808)).
- Mitigation API: `Configuration.observesSuspensionNotifications` + `Database.suspendNotification` / `resumeNotification` (marked EXPERIMENTAL) ([DatabaseSharing.md](https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseSharing.md)). On watchOS, post `suspendNotification` from `WKExtension`/scene-phase background transitions and keep writes short.
- **UNCONFIRMED:** whether the #998 lock-on-suspend problem reproduces on watchOS 26 with plain (non-SQLCipher) GRDB 7 and `DatabaseQueue`. Plan a device test early.

### 2.8 CloudKit sync with GRDB — options and community state (2025–2026)
- **Maintainer thread** [Discussion #1569](https://github.com/groue/GRDB.swift/discussions/1569) (opened 2024-07-08, updated through 2026): three approaches discussed — Harmony (high-level), SQLiteChangesetSync (raw changesets, weak for new-device onboarding), and a minimalist `TransactionObserver` → `CKSyncEngine` bridge. @groue's advice: **drop foreign keys in a CloudKit-synced store** (or keep two stores) because records arrive out of order. Later posts point to Point-Free's sqlite-data (May 2025) and PowerSync's GRDB alpha (May 2026).
- **SQLiteData (pointfreeco/sqlite-data)** — "a fast, lightweight replacement for SwiftData ... built on top of the popular GRDB library"; **1.12.0 released 2026-08-31**; depends on GRDB ≥ 7.6; platforms iOS 16+/watchOS 9+; tag ships `Package@swift-6.1.swift` so it builds on Xcode 26.6 ([repo](https://github.com/pointfreeco/sqlite-data), [releases](https://github.com/pointfreeco/sqlite-data/releases), [Package.swift @1.12.0](https://github.com/pointfreeco/sqlite-data/blob/1.12.0/Package.swift)). Its `SyncEngine` wraps `CKSyncEngine`, uses SQLite triggers to detect local changes, supports CloudKit sharing, and documents strict schema rules ([CloudKitSync article](https://github.com/pointfreeco/sqlite-data/blob/main/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md)):
  - Primary keys must be globally unique (`TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())`), **on every table including join tables**, single-column only.
  - Foreign keys are allowed (parent-first ordering, child records cached until the parent arrives); `ON DELETE` limited to `CASCADE`/`SET NULL`/`SET DEFAULT`.
  - **No `UNIQUE` constraints** other than the PK; migrations must be backwards-compatible (add tables/columns only).
  - Conflicts: **field-wise last-edit-wins, not customizable**.
  - Tests/previews work by bootstrapping `defaultDatabase` + `defaultSyncEngine` via `prepareDependencies`.
  - `SyncEngine` availability iOS 17 / watchOS 10 (per search summary of `SyncEngine.swift`; **UNCONFIRMED** directly).
  - Cost: pulls in swift-dependencies, swift-sharing, swift-structured-queries, swift-perception, etc. ([Package.swift](https://github.com/pointfreeco/sqlite-data/blob/main/Package.swift)). A March 2026 "incomplete sync" report was traced to an old version and fixed in 1.4.3 ([Discussion #419](https://github.com/pointfreeco/sqlite-data/discussions/419)).
- **Harmony (aaronpearce/Harmony)** — "CloudKit sync for GRDB and only GRDB"; iOS 17+/watchOS 10+; GRDB ≥ 7.6; **no foreign-key support**; hides direct writes (you must write through Harmony); 219 stars; commits 2026-09-07 ("support aggregate deletion", "handle failed CloudKit deletions") and 2026-01-20 ("nonisolated fixes"); manifest still `swift-tools-version: 5.9` ([README](https://github.com/aaronpearce/Harmony), [Package.swift](https://github.com/aaronpearce/Harmony/blob/main/Package.swift)). Small but alive.
- **PowerSync GRDB (alpha)** — added in Swift SDK v1.9.0; it syncs to a Postgres/PowerSync backend, **not CloudKit**; not applicable if iCloud is the target ([docs](https://docs.powersync.com/client-sdks/orms/swift/grdb)).
- **Hand-rolled pattern (Christian Selig, 2026-01-07):** GRDB + `CKSyncEngine`, a `cloudKitInfo` column holding the encoded `CKRecord` system fields, per-type conflict policy (server-wins for most; "higher value wins" for monotonic counters), persist state on every `stateUpdate`, never use enums in synced fields, one engine per database, don't call `fetchChanges()`/`sendChanges()` from delegate callbacks, 1 MB batch cap ([post](https://christianselig.com/2026/01/cksyncengine/)).
- **Aggregated 2026 experience** ([mjtsai, 2026-04-01](https://mjtsai.com/blog/2026/04/01/cksyncengine/)): Selig calls it "one of the best APIs Apple has built"; Sean Heber reports fresh installs replaying months of deletion tombstones ("could take hours") — workaround: fetch current records manually before starting the engine; quota-exceeded pauses don't requeue automatically.
- A 2026 comparison blog names "GRDBCloudKit" and warns about "sync storms" causing throttling ([Pi Stack, 2026-08-11](https://www.pistack.xyz/posts/2026-08-11-grdb-swiftdata-core-data-swift-persistence-comparison/)); the library itself was not located — **UNCONFIRMED**.

---

## 3. SwiftData as of iOS 26 / iOS 27

### 3.1 What changed (Apple's own changelog)
Source: [SwiftData updates](https://developer.apple.com/documentation/updates/swiftdata.md)
- **June 2024 (iOS 18):** `#Index` (single/compound), `#Unique`, unidirectional relationships (`inverse: nil`), persistent history (`fetchHistory`, `deleteHistory`, `HistoryProviding`), custom stores via `DataStore` protocol.
- **June 2025 (iOS 26):** class **inheritance** through `@Model`; `HistoryDescriptor.sortBy`. Session details: subclasses are returned by parent-type queries, filter with `#Predicate { $0 is PersonalTrip }`, adding inheritance is a lightweight migration; also `propertiesToFetch`, `relationshipKeyPathsForPrefetching`, `withObservationTracking` on models ([WWDC25 291](https://developer.apple.com/videos/play/wwdc2025/291/)).
- **June 2026 (iOS 27):** `@Query(... sectionBy:)`, `@Attribute(.codable)` (opaque blob; no filter/sort/migration), **`ResultsObserver`** (query observation outside views, `@Observable`), **`HistoryObserver`** (observes remote/CloudKit history transactions). Both new classes are **iOS 27+/watchOS 27+ only** ([ResultsObserver](https://developer.apple.com/documentation/swiftdata/resultsobserver.md), [HistoryObserver](https://developer.apple.com/documentation/swiftdata/historyobserver.md), [WWDC26 274](https://developer.apple.com/videos/play/wwdc2026/274/)). Third-party write-ups also mention enum values in predicates — **UNCONFIRMED** against Apple docs ([dev.to](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5)).
- Availability: SwiftData iOS 17+/watchOS 10+ ([Apple](https://developer.apple.com/documentation/swiftdata.md)).

### 3.2 Reliability reputation (2025–2026)
- Paul Hudson on WWDC25: "As for SwiftData… well, it's not great news" ([HWS, 2025-06-19](https://www.hackingwithswift.com/articles/278/whats-new-in-swiftdata-for-ios-26)).
- Fatbobman on WWDC25: "SwiftData added only one feature this year—model inheritance"; on WWDC26: still "lacks cloud syncing for public/shared data and clearer performance improvements ... filling key gaps rather than making a leap significant enough to fundamentally change confidence in it" ([mjtsai WWDC25 roundup](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/), [Fatbobman #139, 2026-06-09](https://fatbobman.com/en/weekly/issue-139/)). The same roundup quotes Tony Arnold that serious use cases ended up converting to Core Data + CloudKit.
- Point-Free's WWDC26 review (2026-07-13): sectioning only by exact stored string fields; `.codable` is a black box; `ResultsObserver` API diverges from `@Query`; reference-type models force duplicate state and optional relationships for iCloud ([ep. 372](https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata)).
- Cocoacasts chose Core Data over SwiftData for a 15-entity app: auto-save "can fail silently", unpredictable bidirectional relationships and collection ordering, eager-loading slowdowns on large data, lightweight-only migrations ([Cocoacasts](https://cocoacasts.com/why-i-chose-core-data-over-swift-data-for-hive-notes)).
- Fatbobman's limitations list (2025-03-12): incomplete predicate support, no comprehensive batch ops, only `PersistentIdentifier`/`ModelContainer` are `Sendable`, iOS 18 `@ModelActor` view-refresh bug; recommends GRDB/SQLite.swift when SQL control matters ([post](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/)).
- Open Apple Forums threads: "SwiftData CloudKit sync broken on iOS 26" (`BAD_REQUEST`, Jan 2026, engineer asked for sysdiagnose, unresolved) ([811675](https://developer.apple.com/forums/thread/811675)); "SwiftData + CloudKit causes watchOS app termination during WKExtendedRuntimeSession" (FB17685611, May 2025; workaround `cloudKitDatabase: .none`) ([785378](https://developer.apple.com/forums/thread/785378)).
- Core Data got no new features at WWDC25 ([mjtsai](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/)); Fatbobman's 2026 position is "modernize Core Data via CoreDataEvolution" rather than switch ([2026-03-11](https://fatbobman.com/en/posts/why-i-am-still-thinking-about-core-data-in-2026/)).

### 3.3 CloudKit constraints (official)
[Apple: Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices): SwiftData sync is `NSPersistentCloudKitContainer` underneath; `@Attribute(.unique)` unsupported; **all relationships must be optional**; `.deny` delete rule unsupported; CloudKit schema is additive-only after promotion to production; no public/shared DB sync. (Fatbobman adds: not real-time, account switch clears local data — [post](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/).)

### 3.4 Aggregate-query performance
"SwiftData lacks equivalents to Core Data's `NSExpression` for SQL-pushed operations (sum, average, min, max)"; the documented escape hatch is to run a Core Data stack against the same store; `fetchCount`/`fetchIdentifiers` are the only cheap paths ([Blake Crosley, 2026-06-15](https://blakecrosley.com/blog/swiftdata-performance-storage-engine); [HWS fetchCount](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-count-results-without-loading-them)). For e1RM trends / weekly volume over tens of thousands of rows this means loading objects into memory or maintaining denormalized rollups. A "GRDB ~20x faster inserts" figure circulated in search snippets is **UNCONFIRMED** (source article gave no numbers: [Pi Stack](https://www.pistack.xyz/posts/2026-08-11-grdb-swiftdata-core-data-swift-persistence-comparison/)).

### 3.5 watchOS
SwiftData runs on watchOS 10+, but CloudKit-on-watch has real problems: watchOS 10 `NSPersistentCloudKitContainer` sync only reliably ran while charging (FB13183124; migrating from extension to single-target app helped) ([737661](https://developer.apple.com/forums/thread/737661)); initial CloudKit import on watch never completed above ~10k entities ([737126](https://developer.apple.com/forums/thread/737126)); plus the FB17685611 termination above.

### 3.6 Testability
`ModelConfiguration(isStoredInMemoryOnly: true)` → `ModelContainer` works with XCTest and Swift Testing; tests touching `mainContext` must be `@MainActor` ([HWS](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-write-unit-tests-for-your-swiftdata-code), [AzamSharp 2026-08-02](https://azamsharp.com/2026/08/02/building-testable-swiftdata-apps.html)). Adequate, but the store is still Core Data underneath, and `isStoredInMemoryOnly` has been reported ineffective with iCloud on macOS ([forum 744671](https://developer.apple.com/forums/thread/744671)).

### 3.7 Honest 2026 assessment for Ledger

| Criterion | GRDB 7.11 | SwiftData (iOS 27) | Core Data |
|---|---|---|---|
| SQL-pushed aggregates (e1RM, volume, PRs) | Yes, first-class | No (in-memory or Core Data coexistence) | Yes (`NSExpression`) |
| Sendable / Swift 6 strict | Structs, documented, enforced | Models are non-Sendable classes; `@ModelActor` | `NSManagedObject` non-Sendable; awkward |
| In-memory tests | `DatabaseQueue()` | `isStoredInMemoryOnly` | `NSInMemoryStoreType` |
| watchOS | 7+; suspension caveat (#998) | 10+; CloudKit termination bug | Mature |
| Migrations | Explicit, transactional, mergeable | Versioned schema, lightweight bias | Full mapping models |
| iCloud sync | DIY via CKSyncEngine, or SQLiteData/Harmony | Built-in via NSPersistentCloudKitContainer, with schema restrictions and open iOS 26 bug | Built-in, mature |
| Dependencies | 1 (GRDB) | 0 | 0 |
| Community confidence 2026 | High, active | Mixed; "filling gaps" | Stable but "frozen" |

Verdict: GRDB for Ledger. Core Data would be the fallback only if built-in CloudKit sync had to ship on day one; SwiftData is the weakest fit because the aggregate-query gap goes to the heart of the product.

---

## 4. CKSyncEngine (iOS 17+)

### 4.1 Availability and contract (Apple docs)
[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5.md): **iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS**. Create one early at launch per database (multiple engines are allowed only for *different* databases, e.g. private + shared); requires CloudKit + Remote-notifications entitlements; you must persist the opaque `State` on every `StateUpdate` event; you queue work with `state.add(pendingRecordZoneChanges:)` and supply records from `nextRecordZoneChangeBatch(_:syncEngine:)`; results arrive as `sentRecordZoneChanges`/`fetchedRecordZoneChanges` events; **never use it for the public database**. Sync scheduling is indeterminate; `fetchChanges()`/`sendChanges()` force it.

### 4.2 Apple sample
[apple/sample-cloudkit-sync-engine](https://github.com/apple/sample-cloudkit-sync-engine): last push 2024-01-12; iOS 17/macOS 14; requires a physical device (push). Architecture: `SyncedDatabase` owns the engine, an in-memory/JSON `AppData`, and the pending-change bookkeeping; `SyncTests.swift` simulates multiple devices. Conflict handling ([SyncedDatabase.swift](https://github.com/apple/sample-cloudkit-sync-engine/blob/main/SyncEngine/SyncedDatabase.swift)): on `.serverRecordChanged` it calls `contact.mergeFromServerRecord(serverRecord)`, `setLastKnownRecordIfNewer(serverRecord)`, then re-queues `.saveRecord`; on `.zoneNotFound` it queues `.saveZone` and retries; on `.unknownItem` it clears the cached server record. Session: [WWDC23 10188](https://developer.apple.com/videos/play/wwdc2023/10188/).

### 4.3 Best-practice architecture for a GRDB store (synthesis of 2025–2026 sources)
1. **Local schema is CloudKit-shaped from day one:** UUID string PKs on every table (incl. join tables), no `UNIQUE` except PK, additive-only migrations, avoid enums in synced columns (store raw strings), defaults for every column ([SQLiteData rules](https://github.com/pointfreeco/sqlite-data/blob/main/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md), [Selig](https://christianselig.com/2026/01/cksyncengine/)).
2. **Per-row CloudKit metadata** in a sidecar table or `cloudKitInfo` blob: encoded `CKRecord` system fields + last-known server record, so conflict resolution has the server's etag/tags ([Selig](https://christianselig.com/2026/01/cksyncengine/), [Superwall tutorial](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui)).
3. **Change capture via GRDB `TransactionObserver`** (or triggers into an outbox table) → `state.add(pendingRecordZoneChanges:)`; 7.11's option to disable change filtering exists for exactly this ([Discussion #1569](https://github.com/groue/GRDB.swift/discussions/1569), [CHANGELOG 7.11.0](https://github.com/groue/GRDB.swift/blob/master/CHANGELOG.md)).
4. **Wrap the engine + delegate in an `actor`** rather than `@unchecked Sendable` classes; keep the engine `let`; Apple DTS endorsed the actor route for Core Data + CKSyncEngine under Swift 6 ([Apple Forums 798758](https://developer.apple.com/forums/thread/798758)).
5. **Conflict policy per record type:** server-wins for immutable log rows (sets), field-wise LWW for editable entities (exercise names, notes), "max wins" for monotonic counters ([Selig](https://christianselig.com/2026/01/cksyncengine/); SQLiteData implements field-wise LWW).
6. **Fresh-install bootstrap:** fetch current records directly (`CKFetchRecordZoneChangesOperation`/query) before starting the engine to avoid replaying months of deletion tombstones ([Sean Heber via mjtsai](https://mjtsai.com/blog/2026/04/01/cksyncengine/)).
7. Persist `State` on every `stateUpdate`; re-initialize the engine (and wipe serialized state) on sign-out/account switch, not on sign-in ([Selig](https://christianselig.com/2026/01/cksyncengine/), [Apple docs](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5.md)).
8. Only real devices sync (no push in Simulator) ([Apple sample](https://github.com/apple/sample-cloudkit-sync-engine)).

### 4.4 Can watchOS use CloudKit / CKSyncEngine directly in 2026?
- **API-wise yes:** CKSyncEngine is watchOS 10+ ([Apple](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5.md)); Harmony and SQLiteData both declare watchOS 10.
- **Operationally risky:** watch background sync historically only ran on charger (watchOS 10, FB13183124) ([737661](https://developer.apple.com/forums/thread/737661)); large initial imports stall ([737126](https://developer.apple.com/forums/thread/737126)); SwiftData+CloudKit terminated watch apps during extended runtime sessions ([785378](https://developer.apple.com/forums/thread/785378)). None of the 2026 CKSyncEngine write-ups (Selig, mjtsai roundup) discuss watchOS at all.
- **UNCONFIRMED:** whether watchOS 26/27 improved background CloudKit scheduling. Treat the Watch as phone-fed (WatchConnectivity) with its own GRDB store, and add a watch-side CKSyncEngine only after device testing.
- Counterpoint worth knowing: one team left CloudKit for Supabase in May 2026 citing zero visibility into server-side failures; commenters argued the pain was `NSPersistentCloudKitContainer`, not CloudKit ([mjtsai, 2026-05-21](https://mjtsai.com/blog/2026/05/21/leaving-cloudkit/)).

---

## 5. Dependency injection and architecture (2026)

### 5.1 swift-dependencies (Point-Free)
- **Latest: 1.17.1, 2026-08-28** (1.17.0 2026-08-24 adds `preferredLocales`, drops XCTestDynamicOverlay dependency; 1.15.0 2026-08-11 "Drop swift-tools-version to 6.1"; 1.14.0 2026-06-17 adds the **`@DependencyEntry`** macro) ([releases](https://github.com/pointfreeco/swift-dependencies/releases)).
- Platforms iOS 15+/watchOS 9+; package traits `Clocks`, `CombineSchedulers`, `Foundation`, `FoundationNetworking`; swift-syntax `509..<605` ([Package.swift](https://github.com/pointfreeco/swift-dependencies/blob/main/Package.swift)).
- **Toolchain compatibility verified per tag:** 1.17.1 ships `Package.swift` (tools 6.4), `Package@swift-6.3.swift`, `Package@swift-6.0.swift` — so it resolves on Xcode 26.6 / Swift 6.3.3 (GitHub contents API @1.17.1).
- Swift 6: the library is Swift-6-mode and documents concurrency support ([docs: ConcurrencySupport](https://swiftpackageindex.com/pointfreeco/swift-dependencies/main/documentation/dependencies/concurrencysupport)).
- Test ergonomics: `@Suite(.dependencies { ... })` / `withDependencies` (used by SQLiteData's own testing guide).

### 5.2 The Composable Architecture
- **Latest: 1.26.2, 2026-08-28**; iOS 16+/watchOS 9+; `Package@swift-6.1.swift` present; traits `ComposableArchitecture2Deprecations` signal a 2.0 in preparation ([releases](https://github.com/pointfreeco/swift-composable-architecture/releases), [Package.swift](https://github.com/pointfreeco/swift-composable-architecture/blob/main/Package.swift)).
- Point-Free's own FAQ: "We do not recommend people use TCA when they are first learning Swift or SwiftUI"; start vanilla and "transition to TCA later if there is a need for any of its powers" ([FAQ](https://www.pointfree.co/blog/posts/141-composable-architecture-frequently-asked-questions)).
- Independent guidance: MVVM for teams < 3 devs / < 3-month timelines; TCA for 5+ devs, multi-year enterprise apps, 80%+ coverage targets; ~65% more code on simple features ([Ali Çınaroğlu, 2024-12-30](https://alicinaroglu.dev/mvvm-vs-the-composable-architecture-when-to-pick-which/)); 2026 round-ups repeat "indie/small: MVVM wins" ([7Span](https://7span.com/blog/mvvm-vs-clean-architecture-vs-tca), [Medium 2026](https://medium.com/@chandra.welim/ios-architecture-in-2026-which-one-should-you-actually-use-793917181411)).
- Verdict: **not advisable** for a small-team lifting log. Take swift-dependencies (or a hand-rolled environment) without TCA.

### 5.3 `@Observable` + MVVM-lite and Apple's MainActor guidance
- Apple DTS (Xcode 26 beta 6): view models "should generally be main-actor bound," achieved either by explicit `@MainActor` or by the **Default Actor Isolation = MainActor** build setting; DTS expects most UI apps to use the build setting; note Swift Language Version still defaulted to 5 in that beta ([Apple Forums 798211](https://developer.apple.com/forums/thread/798211)).
- WWDC25 "Embracing Swift concurrency": start single-threaded on the main actor, add `async` for latency, `@concurrent` for CPU work, actors when the main actor becomes the bottleneck; keep UI models non-Sendable on the main actor; `nonisolated` for library code that should run wherever it's called ([WWDC25 268](https://developer.apple.com/videos/play/wwdc2025/268/)).
- Swift 6.2 (released 2025-09-15) shipped SE-0466 default isolation (`-default-isolation MainActor`; SwiftPM `.defaultIsolation(MainActor.self)`; opt out per-declaration with `nonisolated`; actors and `SendableMetatype`-conforming declarations are excluded) and SE-0461 `nonisolated(nonsending)` ([swift.org 6.2](https://www.swift.org/blog/swift-6.2-released/), [SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)).
- Xcode 26 build settings: "Default Actor Isolation" = `MainActor` (new projects) / `nonisolated` (existing); "Approachable Concurrency" YES/NO ([Donny Wals, 2025-06-10](https://www.donnywals.com/setting-default-actor-isolation-in-xcode-26/), [SwiftLee 2025-06-16](https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/)). The underlying `SWIFT_DEFAULT_ACTOR_ISOLATION` / `SWIFT_APPROACHABLE_CONCURRENCY` xcconfig keys are widely cited but were not confirmed from an Apple page here — **UNCONFIRMED (names)**.
- Debate: Matt Massicotte argues against MainActor-by-default for people still learning concurrency ("can make those encounters much more difficult to understand") ([massicotte.org 2025-11-20](https://www.massicotte.org/blog/mainactor-by-default/), [mjtsai roundup 2025-11-20](https://mjtsai.com/blog/2025/11/20/no-mainactor-by-default/)); van der Lee and Apple recommend it for UI modules. Practical resolution for Ledger: MainActor default in app/UI targets, `nonisolated` default in the persistence package (Fatbobman's module-split advice, [2025-07-30](https://fatbobman.com/en/posts/default-actor-isolation/)).
- Swift 6.4 (SE-0506) makes `@Observable` change notifications fine-grained and continuous — relevant if you move to Xcode 27 ([swift.org](https://www.swift.org/blog/swift-6.4-released/)).

Recommended shape ("MVVM-lite"): `@Observable @MainActor final class ExerciseHistoryModel` that owns a `ValueObservation` task and exposes plain value-type state; views are dumb; `AppDatabase` (GRDB) and clocks/UUID generators injected via swift-dependencies; records are `nonisolated` `Sendable` structs in a separate `LedgerData` package.

---

## 6. Swift Charts and typography

### 6.1 Swift Charts on iOS 26+ and watchOS
- Framework availability **iOS 16+ / watchOS 9+** ([Apple](https://developer.apple.com/documentation/charts.md)); `LineMark` watchOS 9+ ([doc](https://developer.apple.com/documentation/charts/linemark.md)); `chartScrollableAxes` iOS 17+/**watchOS 10+** ([doc](https://developer.apple.com/documentation/swiftui/view/chartscrollableaxes(_:).md)); vectorized `LinePlot`/`AreaPlot` (June 2024) iOS 18+/**watchOS 11+** ([doc](https://developer.apple.com/documentation/charts/lineplot.md)).
- **Chart3D / SurfacePlot (June 2025):** iOS 26, macOS 26, visionOS 26 only — **no watchOS or tvOS** ([doc](https://developer.apple.com/documentation/charts/chart3d.md), [updates page](https://developer.apple.com/documentation/updates/swiftcharts.md)).
- Apple's "Swift Charts updates" page has entries for June 2024 and June 2025 but **none for June 2026**, i.e. no headline Charts API at WWDC26 ([updates page](https://developer.apple.com/documentation/updates/swiftcharts.md)). One iOS 27 note: a type-check slowdown for deeply branching chart content when the deployment target is < 27, fixed by extracting branches into a `@ChartContentBuilder` function ([onmyway133, 2026-06-09](https://onmyway133.com/posts/whats-new-in-swiftui-in-ios-27)).
- Complications/widgets can render Swift Charts (`.complicationForeground()` on marks) ([Apple Forums 725980](https://developer.apple.com/forums/thread/725980)).
- **UNCONFIRMED:** watchOS availability of `chartXSelection(value:)` (the doc page did not render as markdown). Assume iOS 17+/watchOS 10+ but verify in Xcode.
- Fit for Ledger: e1RM trend = `LineMark` + `PointMark` + `RuleMark` (PR line) with `chartScrollableAxes(.horizontal)` on iPhone; on Watch keep to `LineMark`/`AreaMark` without scrolling/selection.

### 6.2 Variable fonts (Archivo, `wdth` axis) in SwiftUI on iOS and watchOS
- Custom fonts: bundle the file and list it under `UIAppFonts` ([Apple: Adding a custom font](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app.md)); `Font.custom(_:size:)` is watchOS 6+ ([doc](https://developer.apple.com/documentation/swiftui/font/custom(_:size:).md)); use `Font.custom(_:size:relativeTo:)` for Dynamic Type.
- `Font.width(_:)` / `Font.Width` exist on iOS 16+/watchOS 9+ ("A width to use for fonts that have multiple widths"; `.compressed/.condensed/.standard/.expanded` or `Width(CGFloat)`) ([doc](https://developer.apple.com/documentation/swiftui/font/width.md)). Every write-up demonstrates it only with SF ([Sarunw](https://sarunw.com/posts/swiftui-font-width/)). **UNCONFIRMED whether `.width()` drives a custom font's `wdth` axis**; do not rely on it.
- Reliable route: Core Text variation attributes. `UIFontDescriptor` is watchOS 2+ ([doc](https://developer.apple.com/documentation/uikit/uifontdescriptor.md)) and `kCTFontVariationAttribute` is watchOS 2+ ([doc](https://developer.apple.com/documentation/coretext/kctfontvariationattribute.md)). Build a descriptor with `[kCTFontVariationAttribute: [2003072104 /* 'wdth' */: 87, 2003265652 /* 'wght' */: 600]]`, create the `UIFont`/`CTFont`, wrap in `Font(uiFont)`. A November 2025 field report found `CTFontCreateCopyWithAttributes` more reliable than the `UIFontDescriptor` path ([aplus.rs, 2025-11-13](https://aplus.rs/2025/using-variable-custom-font-4-italic-condensed-black/)); Moving Parts documents the same descriptor approach ([movingparts.io](https://movingparts.io/fonts-in-swiftui)). Apple's CoreText docs note that if no font matches the requested axes the attribute is ignored, and iOS does not synthesize faux widths ([v-fonts support](https://v-fonts.com/support/)) — so the bundled Archivo file must actually be the variable build with a `wdth` axis. **UNCONFIRMED here:** Archivo's exact `wdth` range; check the font's `fvar` table.
- Helper package: [frzi/swift-variablefonts](https://github.com/frzi/swift-variablefonts) 1.1.0 (2024-10-13; watchOS 6+; `UIFont(name:size:axes: [.width: 80])`, `Font.custom(..., axes:)`, `allAxes()`). Small, MIT, but no commits since October 2024 — vendor the ~200 lines rather than depend on it.
- Watch-specific: keep the number of distinct axis instances small (each is a separate `CTFont` cache entry) and test rendering in complications, which may not honor custom fonts — **UNCONFIRMED**.

---

## 7. Recommended architecture for Ledger

1. **Persistence:** GRDB 7.11.1 via SwiftPM, in a `LedgerData` SwiftPM target with `defaultIsolation: nil` (nonisolated). Records are `Sendable` `Codable` structs (`Exercise`, `Workout`, `SetEntry`, …). `AppDatabase` wraps a `DatabasePool` on device and `DatabaseQueue()` in memory for tests/previews. Enable `InferSendableFromCaptures`.
2. **Schema (CloudKit-ready now):** `TEXT` UUID PKs with `NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())` on every table; FKs with `ON DELETE CASCADE`; no `UNIQUE` (enforce uniqueness in code); `createdAt/updatedAt` on every row; indexes on `(exerciseId, performedAt)` and `(workoutId)`; additive migrations only once shipped.
3. **Queries:** SQL views / `SQLRequest` for "last performance per exercise" (window `ROW_NUMBER() OVER (PARTITION BY exerciseId ORDER BY performedAt DESC)`), weekly volume (`strftime('%Y-%W')` group), e1RM (`weight * (1 + reps/30.0)` computed in SQL), PR detection via `MAX(...)` compared per insert. All via `ValueObservation` so screens stay live.
4. **UI:** SwiftUI views + `@Observable @MainActor` models; Default Actor Isolation = MainActor in app targets; Approachable Concurrency on; Swift 6 language mode.
5. **DI:** swift-dependencies 1.17.1 (`@DependencyEntry` for `database`, `clock`, `uuid`, `syncEngine`). No TCA.
6. **Watch:** same `LedgerData` package, own GRDB store, phone → watch via WatchConnectivity (`transferUserInfo`/file transfer of recent sets); post `Database.suspendNotification` on background; verify #998 doesn't reproduce on a physical watch.
7. **Sync (later):** either adopt SQLiteData's `SyncEngine` (fast path, field-wise LWW, watchOS 10+, adds the Point-Free dependency graph) or hand-roll an `actor CloudSync` around `CKSyncEngine` with a `TransactionObserver` outbox and a `cloudKitMetadata` table per §4.3. Because the schema rules above match SQLiteData's, both remain open. Decide when sync is scheduled, not now.
8. **Charts:** `LineMark`/`AreaMark`/`RuleMark` shared across iPhone and Watch; `chartScrollableAxes` on iPhone only; no `Chart3D`.
9. **Type:** `Font.archivo(size:width:weight:relativeTo:)` implemented with Core Text variation attributes; vendor the axis helper.

---

## 8. Open items marked UNCONFIRMED
- Xcode 27 defaulting new projects to Swift 6 language mode.
- GRDB #998 (0xdead10cc on watch suspend) reproducibility with GRDB 7 + plain SQLite on watchOS 26.
- SQLiteData `SyncEngine` exact `@available` line (reported iOS 17 / watchOS 10).
- Existence/quality of a "GRDBCloudKit" library named in a 2026 comparison post.
- SwiftData iOS 27 enum-in-predicate support (third-party claim only).
- watchOS 26/27 improvements to background CloudKit scheduling.
- xcconfig key names `SWIFT_DEFAULT_ACTOR_ISOLATION` / `SWIFT_APPROACHABLE_CONCURRENCY` (UI names confirmed; keys not confirmed from an Apple page).
- `chartXSelection` watchOS availability.
- Whether `Font.width(_:)` affects custom variable fonts; Archivo's `wdth` axis range; custom-font rendering inside watch complications.

---

## 9. Source index
GRDB: https://github.com/groue/GRDB.swift/releases · https://github.com/groue/GRDB.swift/blob/master/CHANGELOG.md · https://github.com/groue/GRDB.swift/blob/master/README.md · https://github.com/groue/GRDB.swift/blob/master/Package.swift · https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/SwiftConcurrency.md · https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Migrations.md · https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseObservation.md · https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseSharing.md · https://github.com/groue/GRDB.swift/blob/master/Documentation/DemoApps/GRDBDemo/README.md · https://github.com/groue/GRDB.swift/wiki/Performance · https://github.com/groue/GRDB.swift/issues/998 · https://github.com/groue/GRDB.swift/issues/1808 · https://github.com/groue/GRDB.swift/discussions/1569 · https://github.com/groue/GRDBQuery
Sync: https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5.md · https://github.com/apple/sample-cloudkit-sync-engine · https://developer.apple.com/videos/play/wwdc2023/10188/ · https://christianselig.com/2026/01/cksyncengine/ · https://mjtsai.com/blog/2026/04/01/cksyncengine/ · https://mjtsai.com/blog/2026/05/21/leaving-cloudkit/ · https://developer.apple.com/forums/thread/798758 · https://github.com/pointfreeco/sqlite-data · https://github.com/pointfreeco/sqlite-data/blob/main/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md · https://github.com/pointfreeco/sqlite-data/discussions/419 · https://github.com/aaronpearce/Harmony · https://docs.powersync.com/client-sdks/orms/swift/grdb · https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui · https://developer.apple.com/forums/thread/737661 · https://developer.apple.com/forums/thread/737126
SwiftData: https://developer.apple.com/documentation/updates/swiftdata.md · https://developer.apple.com/documentation/swiftdata.md · https://developer.apple.com/documentation/swiftdata/resultsobserver.md · https://developer.apple.com/documentation/swiftdata/historyobserver.md · https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices · https://developer.apple.com/videos/play/wwdc2025/291/ · https://developer.apple.com/videos/play/wwdc2026/274/ · https://www.hackingwithswift.com/articles/278/whats-new-in-swiftdata-for-ios-26 · https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/ · https://fatbobman.com/en/weekly/issue-139/ · https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/ · https://fatbobman.com/en/posts/why-i-am-still-thinking-about-core-data-in-2026/ · https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata · https://cocoacasts.com/why-i-chose-core-data-over-swift-data-for-hive-notes · https://blakecrosley.com/blog/swiftdata-performance-storage-engine · https://developer.apple.com/forums/thread/811675 · https://developer.apple.com/forums/thread/785378 · https://www.hackingwithswift.com/quick-start/swiftdata/how-to-write-unit-tests-for-your-swiftdata-code · https://www.pistack.xyz/posts/2026-08-11-grdb-swiftdata-core-data-swift-persistence-comparison/
Architecture/concurrency: https://github.com/pointfreeco/swift-dependencies/releases · https://github.com/pointfreeco/swift-dependencies/blob/main/Package.swift · https://github.com/pointfreeco/swift-composable-architecture/releases · https://www.pointfree.co/blog/posts/141-composable-architecture-frequently-asked-questions · https://alicinaroglu.dev/mvvm-vs-the-composable-architecture-when-to-pick-which/ · https://developer.apple.com/forums/thread/798211 · https://developer.apple.com/videos/play/wwdc2025/268/ · https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md · https://www.swift.org/blog/swift-6.2-released/ · https://www.swift.org/blog/swift-6.3-released/ · https://www.swift.org/blog/swift-6.4-released/ · https://www.donnywals.com/setting-default-actor-isolation-in-xcode-26/ · https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/ · https://www.massicotte.org/blog/mainactor-by-default/ · https://mjtsai.com/blog/2025/11/20/no-mainactor-by-default/ · https://fatbobman.com/en/posts/default-actor-isolation/ · https://www.avanderlee.com/concurrency/swift-6-4-whats-new-in-concurrency/
Toolchain: https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes · https://blakecrosley.com/blog/xcode-27-release · https://mjtsai.com/blog/2026/09/15/xcode-27/ · https://github.com/swiftlang/swift/releases
Charts/fonts: https://developer.apple.com/documentation/charts.md · https://developer.apple.com/documentation/updates/swiftcharts.md · https://developer.apple.com/documentation/charts/chart3d.md · https://developer.apple.com/documentation/charts/lineplot.md · https://developer.apple.com/documentation/charts/linemark.md · https://developer.apple.com/documentation/swiftui/view/chartscrollableaxes(_:).md · https://onmyway133.com/posts/whats-new-in-swiftui-in-ios-27 · https://developer.apple.com/documentation/swiftui/font/width.md · https://developer.apple.com/documentation/swiftui/font/custom(_:size:).md · https://developer.apple.com/documentation/uikit/uifontdescriptor.md · https://developer.apple.com/documentation/coretext/kctfontvariationattribute.md · https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app.md · https://aplus.rs/2025/using-variable-custom-font-4-italic-condensed-black/ · https://movingparts.io/fonts-in-swiftui · https://sarunw.com/posts/swiftui-font-width/ · https://github.com/frzi/swift-variablefonts · https://v-fonts.com/support/
