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
