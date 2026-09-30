# F05 — implementation notes

Branch `feat/F05-persistence` (from `main` e94b501). F05 ships as three sequential PRs
(engineering-standards §10, amended 2026-09-29: 500 lines of code is a target, split above ~1,000).
The plan below was produced read-only on 2026-09-29 by a planning agent and adopted by the
orchestrator. Line counts are code only: no tests, `LedgerTestSupport`, docs or comments.

## Slice plan

| Slice | Contents | Criteria | Est. | Depends on |
|---|---|---|---|---|
| **S1** schema, exact columns, event store | `Database.swift` (open/inMemory/migrator, WAL, FK, data protection) ~50; `Migrations.swift`: all of v001 as raw SQL (adds `personal_record` and `workout.units`; drops the event index that duplicates `uidx_event_key`) ~95; `Columns.swift` + `PersistenceError` ~75; `Events/GRDBWorkoutEventStore` + `EnvelopeCodec` ~100; `GRDBSettingsRepository` ~40; `Observation/ValueObservation+AsyncStream` ~30; `Package.swift` test resources ~5 | 1, 7, 8 | ~390 | main |
| **S2** catalog and programs | Exercise / Program / Week / DayTemplate / Slot / SlotMiss records; `GRDBExerciseRepository` (search, save, `seedIfNeeded`, `observeAll`); `GRDBProgramRepository` (re-validates through `Slot.init` / `Program.init`, diffs children in one write) | 2, 11 | ~380 | S1 |
| **S3** history and stats | Workout / WorkoutExercise / LoggedSet / PersonalRecord records; `GRDBWorkoutRepository` (`materialize` = idempotent upsert by `WorkoutID` in one write: rows, e1RM, PRs, `slot_miss` from `slotUpdates`, stale children deleted; `updateSets` recomputes e1RM and totals; history reads reset live-only fields); `GRDBStatsQueries` (`now` injected; week bounds from `WeekCalendar`); `Seeders.history`, committed `fixtures/db-v001.sqlite`, `MigrationCompatibilityTests` with a test-only v002 | 3, 4, 5, 6, 9, 10, 12 | ~455 | S2 |

- The **F04 contract** moves to `LedgerTestSupport/Engine` as `WorkoutEventStoreContract`, public
  API only (no `@testable`, no `import Testing`), so both the in-memory and the GRDB store run it.
  New clauses: a `wallClock` of `10.493_826_8`, `seq == UInt64.max`, and ±∞/NaN stamps that must
  still be stored.
- **Criterion 11** runs against an injected `Seeders.catalog(count:version:)`; F07 later passes
  `ExerciseCatalog.seed()`, so F03 does not block F05.
- If S3 lands over 500, the split to name is repository vs stats.

## Weight encoding (ADR-007)

- INTEGER count of **10⁻⁷ g**, columns suffixed `_e7g` (`weight_e7g`, `e1rm_e7g`,
  `volume_e7g_reps`).
- Encode: shift the Decimal exponent by +7 (`Decimal(sign:exponent:significand:)`), then
  `Int64(scaled.description)`; nil (a non-integer such as ⅛ lb, NaN, or out of range) throws
  `inexactWeight`. Never rounds. Decode: exponent −7 on `Decimal(n.magnitude)`.
- Round trip: both steps only move the exponent and `Weight ==` compares values, so
  decode(encode(w)) == w for every storable weight (0.01 lb = 45,359,237; 185 lb = 839,145,884,500).
- Range ±9.22×10¹⁸ units = ±922,337 t per value; per-workout volume up to 922,337 t·reps, throws
  beyond.
- SQL never multiplies or sums weights: `weeklyVolume` selects `weight_e7g, SUM(reps) … GROUP BY
  weight_e7g` and sums weight × reps in `Decimal`. TEXT decimals are rejected (lexical MAX/ORDER BY).

## Date encoding

- Envelopes: the payload BLOB (JSON, default `.deferredToDate` = binary64 seconds since 2001 with
  shortest round-trip digits, exact) is the source of truth;
  `nonConformingFloatEncodingStrategy = .convertToString` so malformed ±∞/NaN envelopes can be
  stored. `wall_clock` is an informational nullable REAL (SQLite maps NaN to NULL).
- History: `started_at`, `ended_at`, `done_at`, `achieved_at` are REAL seconds since 2001 (exact,
  range-queryable); only `created_at` / `updated_at` / `deleted_at` stay ISO text.
- Avoid three GRDB 7.11.1 defaults: Date as millisecond text, UUID as a 16-byte BLOB (write
  `uuidString`), and `UInt64` trapping above `Int64.max`.

## Event store vs the contract

- `append` runs in one `queue.write`. For each envelope, look up `(workout, device, seq)`: absent →
  insert and add to the returned list in the given order; present and equal (decoded `==`, not
  bytes, since JSON key order and `1.0` vs `1.00` differ) → skip; present and different → throw
  `conflictingEnvelope` and roll back the batch. Duplicates within a batch are caught because the
  transaction reads its own inserts.
- `seq` stored as `Int64(bitPattern:)`; `highestSeq` = `ORDER BY seq < 0 DESC, seq DESC LIMIT 1`
  (unsigned maximum). `uncompactedWorkoutIDs` = `SELECT DISTINCT workout_id`; `compact` =
  `DELETE … WHERE workout_id = ?`. No foreign key from `workout_event` to `workout`.

## Risks and where they are measured

- watchOS first-launch migration: S1 times `open(at:)` on a file database in PR-Watch (budget
  300 ms).
- Seeding time on the watch: S2; if > 300 ms, F07 seeds after the first frame.
- ValueObservation on watchOS: bridge in S1, emission tests on the watch simulator in S2/S3
  (hardware checks: F20).
- Schema freeze: all of v001 lands in S1; later changes are additive v002.
- Open: who deletes a materialised workout when a late discard overtakes its finish (F17 item 2).

## Slice S1

Schema v001, exact columns and the event store, on `feat/F05-persistence` (from `ac2a08a`, main + F32).
Closes criteria 1, 7 and 8.

### What landed

- `LedgerPersistence`: `Database.swift` (`LedgerDatabase.open(at:protection:)`, `inMemory()`, `migrator`),
  `Migrations.swift` (v001 as one raw-SQL migration, `v001_createSchema`), `Columns.swift` (`ColumnCodec`
  plus `Weight`/`Volume` `_e7g` conveniences), `LedgerPersistenceError.swift`, `Events/EnvelopeCodec.swift`,
  `Events/GRDBWorkoutEventStore.swift`, `Repositories/GRDBSettingsRepository.swift`,
  `Observation/ValueObservation+AsyncStream.swift`. The placeholder `LedgerPersistenceModule` and its test
  are gone.
- `LedgerTestSupport/Engine/WorkoutEventStoreContract{,+Clauses}.swift`: F04's contract, moved (public API
  only, no `@testable`, no `import Testing`). `LedgerDomainTests` keeps a 20-line suite that runs it on
  `InMemoryEventStore`, which stays where it was.
- `Package.swift`: `LedgerPersistenceTests` gets `resources: [.copy("Fixtures")]`.
- `scripts/coverage-thresholds.json`: `LedgerPersistence` added to `required` (threshold 90 %, unchanged).

### Decisions and deviations

1. **Schema v001 (frozen from here; later changes are additive v002).** Against the brief's DDL:
   - Every weight column is an `INTEGER` of 10⁻⁷ g suffixed `_e7g` (`weight_e7g`, `e1rm_e7g`, `step_e7g`,
     `target_load_e7g`, `start_load_e7g`, `start_load_{lb,kg}_e7g`, `personal_record.weight_e7g` and
     `previous_weight_e7g`), and the workout total is `volume_e7g_reps`.
   - `exercise.start_load_{lb,kg}_e7g` are **nullable** (the brief had `NOT NULL`): `Exercise.defaultStartLoad`
     may lack a unit, and `startLoad(in:)` converts from the other one.
   - History dates are `REAL` seconds since 2001: `workout.started_at`/`ended_at`, `logged_set.done_at`,
     `personal_record.achieved_at`. Only `created_at`/`updated_at`/`deleted_at` are ISO 8601 text (UTC, to
     the millisecond, fixed width).
   - Added, per the plan: `workout.units` and the `personal_record` table (kind `estimatedOneRepMax` |
     `weightAtReps`, `reps` only for the latter, `previous_*` for the record it beat).
   - **Dropped `workout.elapsed_seconds`** (deviation): `WorkoutEngine.summary` computes it as
     `state.elapsed(at: endedAt)`, which is exactly `ended_at − started_at`; a truncated integer copy could
     only disagree with the two dates.
   - **`workout_event.id` is `INTEGER PRIMARY KEY`** (the rowid), not a `TEXT` UUID (deviation): the table
     is local-only and never synced, nothing refers to a row, and a UUID would need an injected UUID source
     for nothing. `envelopes(for:)` reads in `id` order, i.e. insertion order.
   - **`workout_event.wall_clock` is `NULL` for every non-finite stamp**, ±∞ as well as NaN (the plan relied
     on SQLite turning NaN into `NULL`). `MAX(wall_clock)` over the uncompacted logs is then exactly the
     HLC recovery value, "the largest *finite* stored `wallClock`" (ADR-004 amendment). The payload still
     keeps the stamp itself.
   - Dropped `idx_event_workout_device_seq`, which duplicated `uidx_event_key` (plan).
   - **Added indexes on every foreign-key column** (deviation, additive): `idx_program_week_program`,
     `idx_day_template_program`, `idx_slot_day_template`, `idx_slot_exercise`, `idx_slot_miss_slot`,
     `idx_wex_workout`, `idx_pr_workout`, plus `idx_pr_exercise (exercise_id, achieved_at)` for
     `personalRecords(exerciseID:)`. Without them a cascade delete or a per-parent read scans the child
     table (SQLite's foreign-key documentation recommends them). `idx_workout_ended`,
     `idx_wex_exercise_workout` and `idx_logged_set_wex` are the brief's.
   - `NOT NULL` on every `TEXT PRIMARY KEY`: SQLite otherwise accepts a `NULL` key in a rowid table.
   - `SchemaTests.uniqueIndexes_areOnlyPrimaryKeys_andTheEventKey` pins ADR-002's "no `UNIQUE`" rule.
2. **`LedgerPersistenceError`, not `PersistenceError`** (deviation): GRDB exports a `PersistenceError`, so
   the name was ambiguous in every file importing both (the tests; F07's composition root will too).
   Cases: `inexactWeight(Decimal)` (also for a volume), `nonFiniteDate`, `malformedIdentifier(String)`.
3. **Weight codec as planned.** `Decimal(sign: .plus, exponent: 7, significand: grams)` then
   `Int64(description)`; nil throws `inexactWeight`. I checked that `Decimal` keeps its results compact
   (after `+`, `*`, construction), so `description` never prints a trailing `.0` for a whole count; the
   seeded round-trip property covers it. Decoding is `Decimal(sign:exponent: −7, significand: magnitude)`.
4. **Repositories take a clock**: `init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init)`,
   used only for `created_at`/`updated_at`. F07 passes `@Dependency(\.date)`; the brief's `init(_:)` call
   still compiles. Tests pass a fixed date.
5. **`open(at:protection:)`**: creates a missing directory with the protection, opens with GRDB's
   `Configuration.journalMode = .wal`, migrates, then sets the protection on the file and its `-wal`/`-shm`
   (after migrating, so the `-wal` exists). GRDB's guidance is to give the database a directory of its own;
   F07 should pass e.g. `Application Support/Database/ledger.sqlite`. `foreignKeysEnabled` is GRDB's
   default, set explicitly.
   - **The simulators keep no protection class.** On the iOS (and watchOS) simulator `setAttributes`
     accepts `.protectionKey` but a read-back is `nil`; the first full gate failed on exactly that. So
     `DatabaseTests.open_protectsTheFileAndItsCompanions` is `.disabled` on simulators with that reason
     (it shows as skipped) and runs on the macOS host (`check.sh --fast`), where the class is kept, and on
     a device. `open(at:)` still runs its protection code on the simulators, so coverage is unaffected.
     A device check belongs to F20.
6. **`ValueObservation` bridge**: GRDB's `.task` scheduler (values on the cooperative pool; no
   `DispatchQueue`, which the lint forbids in `Sources`), `bufferingNewest(1)`, the observation cancelled
   on termination, and on error an `os.Logger` line (`com.petearevalo.Ledger` / `persistence`) and
   `finish()`, since the protocols return a non-throwing `AsyncStream`.
7. **Settings payload** is written as `CAST(? AS TEXT)` of the JSON bytes. SwiftLint's
   `optional_data_string_conversion` rejects `String(decoding:as:)`, and the failable initializer would
   need an unreachable error branch (`JSONEncoder` only writes UTF-8).
8. **The contract** (`WorkoutEventStoreContract`, 12 clauses):
   - New: `fullWidthSeq` (seqs `1`, `Int64.max`, `2⁶³`, `UInt64.max`; `highestSeq == .max`),
     `nonFiniteIsStored` (stamps +∞, −∞, NaN and a `finished(endedAt: +∞)` payload are stored and read
     back; the ±∞ ones re-append as no-ops), and a second envelope stamped `10.493_826_8` in
     `readsBackExactlyOnce` (renamed "…, to the last bit"; its prefix, which F04's round-4 test matches,
     is unchanged).
   - `violations(of:)` takes a throwing factory, since a GRDB store needs `try LedgerDatabase.inMemory()`.
     `Clause` conforms to `CustomStringConvertible` (not Testing's `CustomTestStringConvertible`).
   - F04's `Round4StoreAdversarialTests.since1970Stamps_…` documented the gap F05 was to close; it now
     asserts that the since-1970 store **fails** the exact clause (`…_failTheContract_…`).
   - Mutation check, by hand: with `highestSeq` ordered signed, `fullWidthSeq` failed; without the
     non-finite JSON strategy, `nonFiniteIsStored` failed. Both restored. The 14 F04 mutants are still all
     caught.
9. **For F17 (not changed here):** `EventEnvelope`'s synthesized `==` compares `Date`s, and NaN is never
   `==` to itself. So re-appending an envelope with a NaN stamp or NaN payload date throws
   `conflictingEnvelope`, in the in-memory reference and the GRDB store alike, and rejects its whole
   batch. A duplicate delivery of such an envelope would then drop the good envelopes delivered with it.
   F17's receipt checks (the decode guard or drift bound) should reject non-finite stamps before `append`.
10. **Timing**: `MigrationTimingTests` (`.performance`, nightly lane only, median of 5 after a warm-up,
    budget in `Performance/PerformanceBudget.swift`) follows testing-strategy §6 and
    `ReplayPerformanceTests`: no wall-clock assertion on the PR lane. The plan put it "in PR-Watch"; the PR
    lanes run `DatabaseTests` (the same file open, functionally) on both simulators instead, and the watch
    figure below was measured by hand with the `Nightly-Watch` plan. The median also goes into the result
    bundle as an attachment (`first-launch-open.txt`).
11. **`SeededGenerator` is duplicated** into `LedgerPersistenceTests/Support` (the same 35 lines as
    `LedgerDomainTests`). Moving that one to `LedgerTestSupport` would touch 17 domain test files that do
    not import it yet; a follow-up can do that on its own.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 1. schema, indexes, foreign keys | `SchemaTests.v001_newDatabase_matchesCommittedDDL` (against `Fixtures/schema-v001.sql`), `inMemory_foreignKeysOn_v001Applied`, `foreignKeys_rejectOrphans_andCascade`, `uniqueIndexes_areOnlyPrimaryKeys_andTheEventKey`; file databases: `DatabaseTests.open_newFile_isWALAndMigrated`, `open_existingFile_keepsRows_andMigratesOnce`, `open_protectsTheFileAndItsCompanions` (host and device only, see decision 5) |
| 7. duplicates, `highestSeq` | `WorkoutEventStoreTests.appendTwice_keepsEachKeyOnce_highestSeqPerDevice`; contract clauses `newInGivenOrder`, `highestSeqIsMaximum`, `fullWidthSeq`, `readsBackExactlyOnce`; `append_realStamps_readBackExactly` (seeded) |
| 8. compaction | `WorkoutEventStoreTests.compact_deletesRows_andUnlistsTheWorkout`; contract clause `compactOne`. Materialisation itself is S3; this tests compaction of any stored log |
| F04 "Inputs" 1–4 | `WorkoutEventStoreTests.contract_clauseHolds` (all 14 clauses after fix round 2), `append_writesTheDocumentedColumns`, `append_comparesDecodedEnvelopes_notBytes`, `uniqueKey_refusesASecondRow` |
| ADR-007 storage | `ColumnCodecTests` (examples, refusals, seeded round-trips of weights, volumes and `REAL` dates) |
| Settings | `SettingsRepositoryTests` (defaults, round trip in one row with `payload_version` 1, `observe` emissions, missing keys, a later payload version, an unreadable row) |
| Versioned payloads (fix round 1) | `UnreadableEventRowTests` (a later version and damaged bytes: left out, counted, kept, their key skipped; version dispatch), `PayloadEvolutionAdversarialTests` (flipped to the decision), `SettingsTests.decoding_missingKeys_takeTheirDefaults`, `decoding_invalidPresentKey_throws`, contract clause `noneUnreadable` |
| Payload v1 frozen, repair, clock (fix round 2) | `PayloadV1FixtureTests` (13 envelope fixtures, settings, case coverage), `UnreadableEventRowTests` (six damages: left out, counted, kept; repaired; rollback), `DamagedSettingsRowTests`, contract clause `newestFiniteStamp`, `DatabaseTests.open_protectsTheFileAndItsCompanions` (lock-safe) |

### Code lines

Measured with a script that counts non-blank Swift lines that are not whole-line `//`/`///` comments
(SQL inside the migration string counts as code).
- **After fix round 2: about 623 lines, over the 500 target** (standards §10: under ~1,000, so no forced
  split):
  - `LedgerPersistence` sources 589 (`Migrations.swift` 205, one column per line; the event store 153);
  - `LedgerDomain` +34 (tolerant `Settings` decoding; `unreadableCount` and `newestWallClock` on the
    protocol, with the latter's default);
  - `Package.swift` +2 and `coverage-thresholds.json` ±1, minus the 3-line placeholder.
  - The Device test plans' JSON and the payload fixtures are configuration and test data, not counted.
- After fix round 1: about 580.
- **The split considered:** (a) schema, `Columns`, `Database` and the settings repository, then (b) the event
  store, its codec and the moved contract. Rejected: the event store is what the adversarial round and fix
  round 1 exercised; the payload-version columns must land in v001 with the codecs that write them; and (a)
  alone could not close criteria 7 and 8.
- Before fix round 1: 495 lines. The plan estimated ~390; the gap is the SQL layout (~95 estimated).
- Tests and `LedgerTestSupport` are not counted.

### Gate and coverage (2026-09-29, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0)

- **Full gate, through the simulator lock: green** (`scripts/check.sh`, 455 s; log
  `scratchpad/f05s1-check.log`). Format, lint, package graph and pins, and script tests are OK; **17/17** PR
  targets ran and passed on iOS and **8/8** PR-Watch targets on watchOS. `LedgerPersistenceTests` on each
  simulator: 26 passed and 2 skipped by design (the protection read-back, and the nightly-only timing).
- **The first full run failed** on the two protection read-backs in `DatabaseTests` on the iOS simulator
  (decision 5). They were split out and disabled on simulators; the second run above is green.
- **Coverage gate** (now `required`): LedgerPersistence **99.69 %** (332/333; threshold 90),
  LedgerDomain 98.97 %, LedgerDesign 95.52 %, overall 98.77 %.
- **`scripts/check.sh --fast` on the final tree: green.** LedgerPersistenceTests has 28 tests on the host,
  the protection test included; the domain run has 687.
- **Watch first-launch timing, by hand** (`Nightly-Watch` plan, `-only-testing:LedgerPersistenceTests/MigrationTimingTests`,
  Apple Watch Series 12 (46mm) simulator): **median 4.6 ms** over 5 new files, runs 4.2–5.1 ms, and a first,
  untimed warm-up of 16.8 ms, against the 300 ms budget. The simulator runs on the Mac's CPU, so this rules
  out a design problem but is not the watch's figure: F20's device protocol should time a real first
  launch. The F05 risk ("seed after the first frame if > 300 ms") does not trigger for the migration;
  seeding is S2's to measure.

### How to verify by hand

1. `scripts/check.sh --fast`: `LedgerPersistenceTests` (28 tests) and `LedgerDomainTests` pass on the
   host. The GRDB store runs every contract clause (`WorkoutEventStoreTests.contract_clauseHolds`, 12
   cases), and the in-memory store the same ones (`WorkoutEventStoreContractTests`).
2. Schema: compare `LedgerKit/Tests/LedgerPersistenceTests/Fixtures/schema-v001.sql` with the SQL in
   `Migrations.swift`. `SchemaTests.v001_newDatabase_matchesCommittedDDL` fails with the live schema in its
   message if the two ever differ.
3. The new clauses bite. Break the store and run `swift test --package-path LedgerKit --filter
   WorkoutEventStoreTests`, then revert:
   - in `GRDBWorkoutEventStore.highestSeq`, change the `ORDER BY` to `seq DESC`: the `fullWidthSeq` clause
     fails;
   - in `EnvelopeCodec.encode`, drop the non-finite strategy: `nonFiniteIsStored` fails.
4. Watch timing: under the simulator lock, run `xcodebuild test -project Ledger.xcodeproj -scheme
   LedgerWatch -testPlan Nightly-Watch -destination "$(scripts/sim-destination.sh 'platform=watchOS
   Simulator,name=Apple Watch Series 12 (46mm),OS=27.0')" -derivedDataPath .derivedData
   -clonedSourcePackagesDirPath .derivedData/SourcePackages -onlyUsePackageVersionsFromResolvedFile
   -only-testing:LedgerPersistenceTests/MigrationTimingTests -resultBundlePath /tmp/timing.xcresult`.
   Then run `xcrun xcresulttool export attachments --path /tmp/timing.xcresult --output-path /tmp/att`;
   the exported `first-launch-open` text holds the median.
5. Full gate: `scripts/check.sh` (through the shared lock when other worktrees use the simulators).

### Fix round 1 (2026-09-30): the adversarial round's spec questions

The adversarial round (`test-findings.md`, round 1) found no bug and asked three spec questions.

**Orchestrator decision (2026-09-30), finding 1: versioned payloads, in v001.**
- **Schema.** `workout_event` and `settings` gain `payload_version INTEGER NOT NULL`, with no default: every
  writer states the version. `Fixtures/schema-v001.sql` is regenerated.
- **Codecs.** `EnvelopeCodec` and `SettingsCodec` (in `GRDBSettingsRepository.swift`) write `version = 1`,
  and `decode(_:version:)` switches on the version. Only `case 1` exists; any other version throws
  `LedgerPersistenceError.unknownPayloadVersion(version)`, a new case. A v2 adds a case, and `version`
  names the newest.
- **Unreadable event rows** (a later version, or bytes the codec cannot decode) are handled like this:
  - `envelopes(for:)` returns the readable envelopes, so one bad row no longer makes the whole log throw;
  - each unreadable row is logged with `os.Logger` (`com.petearevalo.Ledger` / `persistence`: row id and
    version public, the error private) and never deleted;
  - `highestSeq` and `uncompactedWorkoutIDs` still count the row, because its key is taken;
  - `append` skips an incoming envelope whose key such a row holds, since a key names one envelope, so the
    incoming one is its copy. It is not new and not a conflict, so the batch goes on. **Amended in fix
    round 2 (SF2): the incoming readable envelope now repairs the row.**
- **The count** is a new `WorkoutEventStore` requirement, `unreadableCount(for:) -> Int`. It has a default
  of `0` in a protocol extension, which is right for any store that keeps envelopes as values, so the
  in-memory reference and the test stores are unchanged. `GRDBWorkoutEventStore` implements it. It is on
  the Domain protocol because F17's host sees only that protocol (LedgerSync does not import
  LedgerPersistence). The new contract clause `noneUnreadable` pins that a store reads back all it wrote.
- **How F17 treats such a log** (written into F17's "Inputs from F05"): while the count is above zero,
  replay and resume from the readable envelopes, but never materialise or compact the log. Compaction would
  delete rows a later version can read, and materialising would save a workout with gaps. Keep it listed and
  tell the lifter part of it needs a newer Ledger.
- **Settings.** `Settings.init(from:)` in LedgerDomain now takes `Settings.default`'s value for every missing
  key, so F28's `iCloudEnabled` cannot break `load()`. A key that is present must still be valid (an unknown
  unit or a 17 s rest still throws). This is a Domain change because the type knows its defaults. A mirror
  struct in Persistence would silently drop any field it forgot. A settings row in an unknown version makes
  `load()` throw `unknownPayloadVersion` and is left as it is. F07 and F14 should fall back to defaults in
  memory without saving over it.
- **Tests.**
  - `UnreadableEventRowTests`: a later version (a valid v1 payload marked v2) and damaged bytes are each
    left out, counted, kept, and their key skipped, while the rest of the log reads back; plus version
    dispatch.
  - `SettingsRepositoryTests`: a row missing two keys loads with their defaults; a later version throws by
    name and the row is kept; the row carries version 1.
  - `SettingsTests` (Domain): tolerant decoding and still-invalid keys.
  - The contract, now 13 clauses, passes on both stores.
  - The adversarial round's two "(documents)" tests in `PayloadEvolutionAdversarialTests` now assert the
    decided behaviour: the legacy row is left out and kept, and the settings row loads with the default.
    Its mutant store and date test write and read `payload_version`.

**Orchestrator decision (2026-09-30), finding 2: file protection in CI.**
- The Mac-host test stays in `check.sh --fast`.
- `TestPlans/Device.xctestplan` and `Device-Watch.xctestplan` already run package tests (`LedgerHealthTests`),
  so they now also run **all of `LedgerPersistenceTests`**. On a device, `open_protectsTheFileAndItsCompanions`
  runs. The simulators do not enforce protection classes (they accept one and keep none), so it is skipped
  there. The timing test is nightly-only, so it is skipped too.
  - **Why the whole target:** a test-plan selection of Swift Testing tests selected nothing on Xcode 27.
    Both `selectedTests: ["DatabaseTests"]` and the three `DatabaseTests/<function>()` identifiers, as
    the result bundle names them, made `xcodebuild` drop the bundle (`check-test-results.sh`: "did not run:
    LedgerPersistenceTests"). With no selection, the bundle runs.
  - **Checked on the iOS simulator** (Device plan, under the lock): 2 targets ran and passed.
    `LedgerPersistenceTests` had 72 passed and 2 skipped (protection, timing).
  - A real device run is F20's.
- F20's brief gains "Inputs from F05": run both Device plans on every protocol run.

**Orchestrator decision (2026-09-30), finding 3: `personal_record` is derived, local-only, never synced.**
- `CREATE TABLE personal_record ( -- derived from logged_set: local-only, never synced` in v001, and the same
  note in `Migrations.swift`'s doc comment.
- F28's brief gains "Inputs from F05" with that line.

**Gate after fix round 1 (2026-09-30):**
- **`scripts/check.sh --fast`: green.** `LedgerPersistenceTests` 74 (the protection test included);
  `LedgerDomainTests` 689 (the two new `SettingsTests`).
- **Full gate, through the lock: green** (323 s; log `scratchpad/f05s1-fix1-check.log`). 17/17 PR targets
  on iOS and 8/8 PR-Watch targets on watchOS. `LedgerPersistenceTests` on each simulator: 72 passed and 2
  skipped by design.
- **Coverage:** LedgerPersistence **100.00 %** (391/391), LedgerDomain 98.98 %, overall 98.85 %.
- **Device plan on the iOS simulator** (log `scratchpad/f05s1-deviceplan.log`): 2/2 targets ran and passed.
  The Device plans are not part of `check.sh`, so editing them after the full gate does not affect it.

### Fix round 2 (2026-09-30): the close-out round and the review

Inputs: `test-findings.md` "# Slice S1 — round 2" (minor bugs 4 and 5) and `review.md` "## Slice S1" (SF1–SF3,
N1–N9), at `0131cc7` (main `2bcb442` merged in).

**Orchestrator decision (2026-09-30), SF1: golden version-1 payloads.**
- **Fixtures.** `LedgerPersistenceTests/Fixtures/payload-v001/` holds 13 envelope fixtures, one per
  `WorkoutEvent` case, and `settings.json`. They are pretty-printed JSON written once by version 1's
  encoders; the one-off generator was deleted.
  - The fixtures cover sub-millisecond stamps and payload dates, `Weight` as decimal text, seq `UInt64.max`
    and 2⁶³, a `"NaN"` stamp, `"+Infinity"` and `"-Infinity"` payload dates, and a `started` snapshot with
    every optional field set.
- **Literals.** `Support/PayloadV1.swift` holds their literal values. Its doc comment states the rule: never
  edit a fixture; a Domain `Codable` change that fails these tests ships as payload version 2.
- **Tests.** `PayloadV1FixtureTests` checks three things:
  - each fixture decodes with `decode(_:version: 1)` to its literal (bit-exact on the NaN stamp);
  - the codec's output today is the same JSON object as the fixture;
  - every `WorkoutEvent` case has a fixture. An exhaustive `switch` in `PayloadV1.caseName` makes a new case
    fail to compile until it is listed.
- **Mutation check (by hand):** renaming `EventEnvelope`'s `workoutID` key with no version bump, the
  review's surviving mutant, fails all 14 envelope fixture cases and nothing else. Reverted.

**Orchestrator decision (2026-09-30), SF2: repair on re-append.** This amends fix round 1's "skip".
- **Behaviour.** When `append` meets a stored key whose row is unreadable (unknown version, damaged bytes, or
  a column of the wrong kind), the incoming readable envelope overwrites that row's `wall_clock`,
  `payload_version` and `payload`, and is returned as newly stored. The repair is logged at notice level.
- **Scope.** The repair is part of the batch, so a conflict later in the batch rolls it back. The store
  cannot read what it replaces, so the first readable envelope with the key wins, whichever it is. The
  test marks this as "(documents)". After that, the key judges contents again.
- **Tests:** `UnreadableEventRowTests.readableCopy_repairsTheRow` and `repair_inAConflictingBatch_rollsBack`,
  over six damages; round 2's `PayloadVersionAdversarialTests` (the property test's resend now repairs
  exactly the damaged rows, and the unreadable-key test is rewritten) and `PayloadEvolutionAdversarialTests`.
  A readable row with a different envelope still conflicts (both suites, and the contract).
- **Docs.** The protocol's `append` and `unreadableCount` doc comments, and F17's "Inputs from F05", say it.

**Orchestrator decision (2026-09-30), SF3: clock recovery.**
- **API.** `WorkoutEventStore.newestWallClock() async throws -> Date?`. `GRDBWorkoutEventStore` reads
  `MAX(wall_clock)` directly, bounded to finite values, so unreadable rows count and NULL or non-finite stamps
  do not.
- **Default.** The protocol extension computes the same value from `envelopes(for:)` of the uncompacted logs.
  That is correct for any store whose envelopes are all readable, so the in-memory reference and the test
  stores need nothing.
- **Tests.** A contract clause, `newestFiniteStamp`, runs on both stores: an empty store gives `nil`, ±∞/NaN
  are skipped, the value is exact to the sub-millisecond, and compaction removes a log's stamps.
  `UnreadableEventRowTests` shows an unreadable row's stamp is the newest.
- **Docs.** F17's "Inputs from F05" says launch recovery uses it.

**Orchestrator decision (2026-09-30), finding 4: a damaged settings column throws, never traps or defaults.**
- **Fix.** `GRDBSettingsRepository.fetch` reads both columns as values:
  - a version that is not an integer (text, a blob, or beyond `Int` on arm64_32) throws
    `LedgerPersistenceError.malformedColumn("settings.payload_version")`;
  - a payload that is not UTF-8 text throws `.malformedColumn("settings.payload")`. This is a new error case.
- **Observation.** `observe()` then ends, with the error logged.
- **Tests.** `DamagedSettingsRowTests` covers four shapes (version `'two'` and `x'01'`; payload `x'FFFE7B7D'`
  and `x'80'`), and the row is kept. Round 2's exit test `damagedRow_failsLoad_neverTraps` now passes on the
  host.
  - A number in `payload` is not this kind of damage: `TEXT` affinity stores it as text, and load fails with
    `DecodingError`, as for any invalid JSON.
- **The event store (review N4).** It reads its columns the same way. A wrongly typed version or payload
  makes the row unreadable and repairable, never a trap. `UnreadableEventRowTests` covers text and blob
  versions and non-UTF-8 payloads.

**Orchestrator decision (2026-09-30), finding 5: a protection test that passes while locked.**
- **Why it failed.** The old test opened with `completeUnlessOpen` (class B), then reopened the file, which
  a locked device refuses.
- **The fix.** It now opens with the product's class (`completeUntilFirstUserAuthentication`), which opens
  while locked after the first unlock. It then reopens with class B while the first queue is still open,
  and never reopens a class-B file.
  - It still proves that every open sets the requested class, on the file and its `-wal`.
  - It needs no `.complete`, so it stays on the host and in the Device plans (skipped on simulators, which
    keep no class).
  - `.none` could not serve as the second class: on macOS it reads back as the default class.
- **Not verified by me with a locked screen**; the reasoning is the tester's probe (a first open of either
  class succeeds while locked; only a reopen of class B fails).

**Nits.**

| Nit | Done? | What or why not |
|---|---|---|
| N1 `unreadableCount` default | Done | The default is dropped. The requirement's doc says a wrapper must forward it, and each test conformer (the in-memory store, `MutantEventStore`, `Since1970StampStore`, `LossyEventStore`, `MutantGRDBStore`) returns 0 explicitly. `newestWallClock` keeps its default because it is derived from the protocol, not a constant. |
| N2 settings stream ends silently | Done | The `observe()` doc comment, and "Inputs from F05" in F07 and F14: fall back to defaults in memory, never save over the row. |
| N3 `null` taken as missing | Done | The doc says "missing, or holding `null`"; round 2's "(documents)" test pins it. |
| N4 wrongly typed event columns trap | Done | Read as values; see finding 4. |
| N5 double decode, repeated logging, statements per envelope | Partly | `append` now prepares its three statements once per transaction (`cachedStatement`). Skipped: one fetch for `envelopes` + `unreadableCount` and log-once need an API or state change (a design call), and logs are tens to hundreds of rows. |
| N6 `highestSeq` temporary B-tree | Done | `COALESCE` of two `MAX` subqueries (negative seqs first), both covering-index searches; the contract's `fullWidthSeq` and the round-1 tests still pass. |
| N7 byte-equality fast path | Skipped | It would make the GRDB store accept an exact NaN redelivery that the in-memory reference rejects, so the two stores would diverge on the contract. F17 drops non-finite stamps on receipt instead (decision 9). |
| N8 escaping errors undocumented | Done | `LedgerPersistenceError`'s doc lists what reaches callers unwrapped. Wrapping them is S2's call. |
| N9 criterion 8 only partly closed | Tracked | S3 re-closes it with a `materialize` → `compact` test. |
| Architecture §7 lacks `personal_record` (round 2, noted) | Done | A row: derived, never synced (F05). |

**Gate after fix round 2 (2026-09-30):**
- **`scripts/check.sh --fast`: green.** `LedgerPersistenceTests` has 91 tests, round 2's exit test and the
  protection test included; `LedgerDomainTests` has 689.
- **Full gate, through the lock: green** (280 s; log `scratchpad/f05s1-fix2.log`). 17/17 PR targets on iOS
  and 8/8 PR-Watch targets on watchOS. `LedgerPersistenceTests` on each simulator: 88 passed and 2 skipped
  by design (protection, timing).
- **Coverage:** LedgerPersistence **96.88 %** (405/418; threshold 90), LedgerDomain 98.82 %, overall 98.21 %.
  - The iOS bundle measures every persistence file at 100 % (405/405).
  - The watchOS bundle adds 13 lines. They are function records with zero counts (`StoredPayload.envelope()`
    at line 152, and a closure of `envelopes(for:)` at line 65), placed where those functions stood before
    this round; the current records (line 182: 9/9) are covered. That looks like a stale object in the
    incremental watchOS build. `coverage-gate.sh` keeps the measurement with more lines, so it counts them.
    It is not a gap in the code, and a clean build should drop it; worth knowing if the watch number ever
    looks odd.
- **The Device plans** were not re-run: this round did not change them.
