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

## Slice S2

The catalog and programs, on `feat/F05-s2` (from `main` 1db1cf9, which holds S1). Closes criteria 2 and 11.
Schema v001 is unchanged: everything fits it.

### What landed

- `LedgerPersistence/Records/`:
  - `SyncedRecord.swift`: the protocol every row of a synced table conforms to, `upsert` and the child diff
    `write(_:over:in:at:)`;
  - `ColumnReader.swift`: strict column reads, and `JSONArray`;
  - `ExerciseRecord.swift`, `ProgramRecords.swift` (program, week, day template), `SlotRecords.swift` (slot, miss);
  - `ProgramRows.swift`: a program as its rows, the save diff and the load.
- `LedgerPersistence/Repositories/GRDBExerciseRepository.swift` (with `ExerciseSearch`) and
  `GRDBProgramRepository.swift`.
- `LedgerPersistenceError`: two new cases, `duplicateIdentifier` and `missingRow`, and the documentation of the
  errors that reach callers unwrapped (review N8).
- `LedgerTestSupport/Persistence/`: `Seeders` (`catalog(count:version:)`, `program(…)`), and the contracts
  `ExerciseRepositoryContract` (8 clauses) and `ProgramRepositoryContract` (6), on a shared `ContractClause`.
- Docs: product decision #23, a line in F12's brief, and "Inputs from F05" in F07's brief.

### Decisions and deviations

1. **Search (Pete, 2026-09-30; product decision #23).** The query matches a substring anywhere in the name,
   and also the short name.
   - It ignores case and diacritics: both sides are trimmed and folded with `.caseInsensitive` and
     `.diacriticInsensitive`, `locale: nil`, so the result is the same in every locale.
   - The equipment filter and the muscle filter combine with the text. The muscle filter is the **primary
     muscle** only (my reading: the prototype has one muscle per exercise; F12 maps its pills to groups).
   - Aliases are not stored or searched.
   - The text is matched in Swift, never in SQL, so `%` and `_` are plain characters (contract clause
     `searchWildcards`). SQL filters `deleted_at`, equipment and muscle.
   - Only rows whose name or short name match are decoded, which took the median search from 5.3 ms to
     1.5 ms on the host.
   - `all()`, `search` and `observeAll` return name order: the folded name, then the id.
2. **Seeding (criterion 11, with the orchestrator's rule of 2026-09-30).** *Amended in fix round 1 (SF1,
   product decision #24): an upgrade now also refreshes the live catalog rows it lists; see "S2 fix round 1".*
   - The applied version is `MAX(catalog_version)` over catalog rows. `seedIfNeeded` does nothing unless the
     given version is higher, so the same version twice, or a lower one, changes nothing. *(Fix round 1: read
     strictly, so a value that is not an integer throws `malformedColumn`.)*
   - An upgrade inserts every entry whose id is not stored. *(Fix round 1: a live catalog row of an older
     version that the catalog lists is refreshed in place.)* A deleted row is never written again, so re-seeding
     never duplicates or revives a catalog row.
   - **An entry is never skipped over a name.** An entry named like a stored exercise, custom or not, is
     inserted by its id beside it, and the clash is logged at notice level. Alternatives, program templates
     and history refer to catalog ids, so every one must exist (orchestrator, from F03's adversarial round).
     "Existing names are not duplicated" means catalog rows are not duplicated.
   - Every catalog row the catalog lists then records the new version. So the applied version moves up even
     when an upgrade adds nothing (a content-only bump), and a later launch does no work. Catalog rows are
     never synced (architecture §7), so this metadata write needs no `updated_at`. *(Fix round 1: only the rows
     it inserts or refreshes; deleted rows keep their version.)*
   - Custom rows are never written (`… AND is_custom = 0`). Every entry is stored as a catalog row, whatever
     its `isCustom` says.
   - ~~An upgrade only adds~~ *(superseded by decision #24)*: an entry a later catalog drops stays, with its old
     version and content.
   - It all runs in one write transaction. An inexact start load throws `inexactWeight`, and the entries
     written before it roll back.
3. **Soft deletes (ADR-002, architecture §7).**
   - A save soft-deletes the weeks, days, slots and misses a program no longer has, setting `deleted_at` and
     `updated_at`. `delete(_:)` does the same to the program and all its rows, in one transaction.
   - Every read skips deleted rows.
   - Saving a program again revives its rows, with the same ids and their `created_at`.
   - Deleting an unknown program does nothing. Hard deletes are F29's.
4. **The diff.**
   - `ProgramRows.write` reads the program's live rows from all five tables before writing any, since
     soft-deleting a day first would hide its slots. It then writes parents first, so every foreign key an
     insert names already exists.
   - Each record is compared with its stored row **as column values**, never decoded. An unchanged row is
     left alone and keeps its `updated_at`. A new or changed one is upserted (`INSERT … ON CONFLICT (id) DO
     UPDATE`, with `created_at` written once and `deleted_at` cleared).
   - Because nothing is decoded, a save repairs a damaged row rather than failing on it, as S1's event store
     does.
   - Only rows that change get a new `updated_at`, which is what M4's last-writer-wins sync needs.
   - `save` with `isActive` makes every other program inactive. `setActive` flips only the flags that change;
     an unknown or deleted program throws `missingRow`.
   - If a sync ever leaves two programs active, `active()` returns the one updated last.
5. **Re-validation (F02 review N2).**
   - `save` rebuilds every slot through `Slot.init` and the program through `Program.init` before it
     writes, so a `var` assigned out of range throws `SlotValidationError` or `ProgramValidationError`.
   - Every read validates the same way. A stored value out of range throws the same errors, never a crash.
   - The domain errors are not wrapped (the call N8 left to S2): the same error means the same thing
     whether it was caught on save or on load.
   - Two weeks, days, slots or misses with one id throw `duplicateIdentifier`, since both would land in one
     row. `Program.init` does not check ids.
   - A slot whose exercise is not stored fails the `slot.exercise_id` foreign key, and the whole save rolls
     back. F07 must seed the catalog before any program is saved.
6. **Strict column reads.** A damaged-row test showed that GRDB's `Int64` conversion **truncates a `REAL`**:
   an `_e7g` weight of 1.5 read as 1, with no error. `ColumnReader` therefore accepts:
   - for an integer column, only `INTEGER` storage that fits the type (on arm64_32, `Int` is 32 bits);
   - for a flag, only an integer;
   - for text, `TEXT` or a `BLOB` holding UTF-8;
   - for an enum or an id, only a value it can parse;
   - for a JSON array, only JSON that decodes.

   Anything else throws `malformedColumn("table.column")` or `malformedIdentifier`. **For S3:** read the
   history columns through `ColumnReader`. S1's `payload_version` reads use GRDB's `Int` conversion, so
   `2.5` reads as 2; `DamagedColumnAdversarialTests` pins that it then throws `unknownPayloadVersion(2)`.
7. **Unreadable exercise rows follow S1's event rows.** A row with a muscle group a later version added, or
   with damage, is left out of `all()`, `search` and `observeAll`, logged with its id, and kept.
   `exercise(id:)` throws by name. A program, by contrast, is one aggregate: any bad row makes `active()`
   and `program(id:)` throw, and ends `observeActive`. Leaving a slot out would let the next save delete it.
8. **`slot_miss.id` is derived**: the RFC 9562 name-based UUID (version 5, SHA-1, via CryptoKit) of the week
   index in the slot's namespace.
   - One miss has one id on every device, so a sync merges the two copies rather than keeping both.
     ADR-002 allows no `UNIQUE` constraint to prevent the duplicate.
   - A miss removed and added again revives its row.
   - The repository needs no UUID source.
9. **JSON array columns** (`secondary_muscles`, `curated_alternatives`) go through `JSONArray`, a `Codable`
   `DatabaseValueConvertible`. GRDB writes it as JSON **text**, e.g. `["triceps","shoulders"]`.
   `String(decoding:as:)` is refused by the lint, and the failable initializer would leave an unreachable
   branch.
10. **`program(id:)`** is public on `GRDBProgramRepository` but not on the protocol, so the Domain is
    unchanged. Criterion 2 loads inactive programs with it; F11 may promote it.
11. **Contracts (for F07's fakes).**
    - `ContractClause<Repository>` generalises S1's `WorkoutEventStoreContract.Clause`, which is unchanged.
    - The two new contracts use public API only.
    - A program clause needs a repository that accepts `ProgramRepositoryContract.exercises`; a GRDB one
      needs them seeded first, because of the foreign key.
12. **Timing** follows S1's `MigrationTimingTests`. `CatalogTimingTests` (`.performance`, nightly lane only)
    times seeding 214 synthetic entries into a new **file** database, against `PerformanceBudget.catalogSeed`
    (300 ms), and a search over 221 rows against `exerciseSearch` (10 ms, F12's per-keystroke budget). Each
    uses the median of 5 runs after a warm-up, and attaches it to the result bundle. The PR lanes assert no
    wall-clock time.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 2. program 8 × 4 round trip with misses | `ProgramRepositoryTests.eightByFour_roundTripsEqual_includingMisses` (active and inactive, by `active()` and `program(id:)`); contract clause `roundTrip` |
| 11. seed idempotent, custom kept, additive upgrade, no duplicates | contract clauses `seedIdempotent`, `seedUpgrade`, `seedNameClash` (a custom exercise named like an entry: both exist, the catalog id resolves); `ExerciseRepositoryTests.seed_writesCatalogRows_withTheirVersion`, `upgrade_recordsItsVersion_evenWhenItAddsNothing`, `seed_neverRevivesADeletedCatalogRow`, `seed_214Entries_storesThemAll`, `inexactStartLoad_isRefused` (rollback) |
| Search (decision #23) | contract clauses `searchText` (a substring mid-name, a short name, case, diacritics and blanks, no match, blank query), `searchFilters` (with equipment and muscle), `searchWildcards` (`%`, `_`, `B%h`) |
| Diff in one transaction | `ProgramRepositoryTests.partialUpdate_diffsChildren` (row counts; unchanged rows keep `updated_at`; removed ones soft-deleted in one stamp), `failedSave_changesNothing` (a foreign-key failure on the last slot leaves every row as it was); contract clause `saveReplaces` |
| Re-validation, and invalid stored data as an error | contract clause `revalidates`; `DamagedProgramRowTests` (18 damages across the five tables: `Slot`/`Program` validation errors, `malformedColumn`, `malformedIdentifier`; reads throw, `observeActive` ends, the row is kept, a save repairs it); `DamagedExerciseRowTests` (9 damages, and a malformed id) |
| Active program, delete | contract clauses `oneActive`, `deleteHides`; `ProgramSoftDeleteTests` (soft delete and revival, `setActive` touching only changed rows, derived miss ids); `ProgramRepositoryTests.setActive_unknownProgram_throws`, `duplicateIdentifiers_areRefused`, `inexactLoad_isRefused` |
| Observation, on the watch simulator too | `ObservationTests` (3 tests: emissions per change and none for an unchanged write), contract clauses `observeAll` and `observeActive`; all run in PR-Watch |
| Seeding time on the watch (risk) | `CatalogTimingTests` (nightly), measured by hand below |
| Columns as documented | `ExerciseRepositoryTests.save_writesTheDocumentedColumns`, `ProgramRepositoryTests.save_writesTheDocumentedColumns` |

### Code lines

Measured as in S1: non-blank Swift lines that are not whole-line `//` or `///` comments, SQL strings included,
in product sources only. Counted with a script over `git ls-files --others` plus the added lines of
`git diff -- LedgerKit/Sources`.

- **684 lines, over the 500 target** (standards §10: under ~1,000, so no forced split). The plan estimated ~380.
- New files: 682.
  - `Records/`: `ProgramRows` 127, `ProgramRecords` 121, `SlotRecords` 82, `ColumnReader` 70, `SyncedRecord` 51,
    `ExerciseRecord` 43.
  - `Repositories/`: `GRDBExerciseRepository` 120, `GRDBProgramRepository` 68.
- `LedgerPersistenceError`: +2.
- Not counted: `LedgerTestSupport` 455 (seeders and the two contracts), tests 672, docs.
- **Why above the estimate:**
  - strict reads (`ColumnReader`, decision 6);
  - soft deletes and the row diff (`SyncedRecord`, `ProgramRows.write`);
  - four record types written out column by column, one per line.
- **The split considered:** (a) the record layer (`SyncedRecord`, `ColumnReader`) and exercises, about 285
  lines, closing criterion 11; then (b) programs, about 400, closing criterion 2. Rejected:
  - (a) would ship `SyncedRecord.write`, the diff, with no caller, so its tests would move to (b);
  - the slice plan pairs the two criteria in S2;
  - a second PR costs another full gate and review round for about 285 lines.

  It remains a clean seam if the orchestrator prefers it.

### Gate and coverage (2026-09-30, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0)

- **`scripts/check.sh --fast`: green.** `LedgerPersistenceTests` 130 tests on the host (then 132, with the two
  coverage tests below); `LedgerDomainTests` 689.
- **Full gate, through the lock: green** (`scripts/check.sh`, 300 s; log `scratchpad/f05s2-check.log`).
  - Format, lint, package graph and pins, and script tests: OK.
  - **17/17** PR targets passed on iOS, and **8/8** PR-Watch targets on watchOS.
  - `LedgerPersistenceTests`, on each simulator: 125 passed, and 4 skipped by design. The skips are the
    protection read-back and three nightly timings.
- **Coverage:** LedgerPersistence **99.46 %** (1110/1116; threshold 90), LedgerDomain 98.99 %, LedgerDesign
  96.46 %, overall 98.48 %.
  - The 6 lines are closures that never run:
    - the two `now: Date.init` default arguments (tests inject a clock);
    - `SyncedRecord.write`'s `uniquingKeysWith:` (ids are primary keys);
    - the `slotsByDay[…, default: []]` fallback;
    - two fallbacks for a name or id that is not UTF-8.
  - After that run I added two tests that exercise the last three: `emptyParts_roundTripEqual` (a day with no
    slots) and two damages (`name = x'80'`, and an id `x'80'`).
- **Re-run after those test-only additions:** see "Final gate" below.

### Final gate (orchestrator, 2026-09-30, on the tree as committed)

- The implementer's session ended before its re-run. The orchestrator ran `scripts/check.sh` through the lock on
  the final tree: **OK in 289 s**. 17/17 PR targets on iOS and 8/8 PR-Watch targets on watchOS passed.
- **Coverage:** LedgerPersistence **99.73 %** (1113/1116), LedgerDomain 98.99 %, LedgerDesign 96.46 %.
  - The 3 lines still uncovered are the two `now: Date.init` default arguments and `SyncedRecord.write`'s
    `uniquingKeysWith:`.

### Watch seeding timing, by hand (`Nightly-Watch` plan, Apple Watch Series 12 (46mm) simulator, 27.0)

`-only-testing:LedgerPersistenceTests/CatalogTimingTests`; log `scratchpad/f05s2-timing.log`, attachments exported
from `scratchpad/f05s2-timing.xcresult`. Both tests passed.

- **Seeding 214 entries into a new file database: median 9.2 ms** (runs 9.1–9.5 ms; warm-up 11.5 ms), against
  the 300 ms budget. F05's risk ("seed after the first frame if > 300 ms") does not trigger. F07 can seed
  during launch; its "Inputs from F05" says so.
- **Search ("press") over 221 rows: median 1.75 ms** (warm-up 3.6 ms), against 10 ms.
- Host, debug: seeding 9.6 ms, search 1.5 ms (5.3 ms before rows were matched before decoding).
- The simulator runs on the Mac's CPU, so this rules out a design problem but is not the watch's figure. F20's
  device protocol should time a real first launch, as for S1's migration.

### How to verify by hand

1. `scripts/check.sh --fast`: on the host, `LedgerPersistenceTests` passes (132 tests, the timings skipped).
2. Criterion 2: `swift test --package-path LedgerKit --filter ProgramRepositoryTests`. Look at
   `eightByFour_roundTripsEqual_includingMisses` and `partialUpdate_diffsChildren`; its expected row counts are
   worked out in its comments.
3. Criterion 11 and search: `swift test --package-path LedgerKit --filter ExerciseRepositoryTests`. The contract
   clauses are listed by name, e.g. `seedNameClash` and `searchWildcards`.
4. The diff bites. Make each change below, run `swift test --package-path LedgerKit --filter
   'ProgramRepositoryTests|ProgramSoftDeleteTests'`, and revert:
   - In `SyncedRecord.write`, always upsert (drop the unchanged `continue`): `partialUpdate_diffsChildren` fails
     (unchanged rows get a new `updated_at`).
   - Drop the soft-delete loop: `saveReplaces`, `deleteHides` and the row counts fail.
5. Strict reads bite: in `ColumnReader.integer`, use `Value.fromDatabaseValue` instead. The `start_load_e7g =
   0.5` and `sets = 3.5` damages then read as 0 and 3 and fail.
6. Watch timing: under the simulator lock, run `xcodebuild test -project Ledger.xcodeproj -scheme LedgerWatch
   -testPlan Nightly-Watch -destination "$(scripts/sim-destination.sh 'platform=watchOS Simulator,name=Apple
   Watch Series 12 (46mm),OS=27.0')" -derivedDataPath .derivedData -clonedSourcePackagesDirPath
   .derivedData/SourcePackages -onlyUsePackageVersionsFromResolvedFile
   -only-testing:LedgerPersistenceTests/CatalogTimingTests -resultBundlePath /tmp/seed.xcresult`. Then run
   `xcrun xcresulttool export attachments --path /tmp/seed.xcresult --output-path /tmp/att`; the
   `catalog-seed` and `exercise-search` texts hold the medians.
7. Full gate: `scripts/check.sh`, through the shared lock.

### S2 fix round 1 (2026-09-30): the adversarial round and the review

Inputs: `test-findings.md` "# Slice S2 — adversarial round 1" (S2-1 to S2-4) and `review.md` "# Slice S2 review"
(B1, SF1–SF3, N1–N8), at `ec6da47`. Every decision below was made by the orchestrator or Pete before the round.

**B1 / S2-1 (blocking): a save never takes over another program's rows.**
- **Change.** `ProgramRows.write` reads the stored rows, then, before any upsert, `refuseOtherProgramsIDs` looks
  up the incoming week, day and slot ids under any *other* program, live or deleted (slots through their
  day). A hit throws `duplicateIdentifier("<table> <id>")` and the transaction rolls back. Misses are covered,
  because their ids derive from the slot's. Re-saving or reviving the program's own rows is unaffected: the
  lookup excludes its own `program_id`.
- **Contract.** New clause `otherProgramsIDs`: a second program naming the first one's slot, day or week id
  is refused by name, and the first program reads back unchanged; after the first is deleted, the slot is
  still refused, and saving the first again restores it whole.
- **F24.** Its brief gains "Inputs from F05": `NextBlock.rollForward` mints new program, week, day and slot ids
  from an injected UUID source.
- **Tests.** The tester's `ProgramIdentityAdversarialTests.idsOfAnotherProgram_areRefused` (slot, day, week) and
  `idsOfADeletedProgram_areRefused` now pass, as does the clause.

**S2-2: the applied catalog version is read strictly.** `appliedVersion` reads `MAX(catalog_version)` through
`ColumnReader.optionalInteger`, so anything but `INTEGER` (or `NULL` before the first seed) throws
`malformedColumn("exercise.catalog_version")`. Test: `DamagedExerciseRowTests.damagedCatalogVersion_throwsByName`
(`9.3e18`, `1.5`, `'v1'`, `x'01'`: throws by name, seeds nothing); the tester's `damagedCatalogVersion_neverTraps`
passes (it accepts either outcome).

**S2-3: a blob id is repaired like a text id.** Of the two options I took keying, because it is the more general
one. `SyncedRecord.write` keys stored rows by their `id` **value as stored** (`DatabaseValue`), whatever its
storage class, and soft-deletes a removed row by that same value. A blob id, valid UTF-8 or not, matches no
record and is soft-deleted, so the save repairs the program. Before, the blob was keyed as text, and the soft
delete then bound the key as text, which never matches a `BLOB`. Test: the tester's
`ProgramWeightAdversarialTests.saveOverDamagedID_repairs("x'00'")` now passes, beside `'nope'` and `7`.

**S2-4 (decided: refuse, don't truncate).**
- **Change.** A new case, `LedgerPersistenceError.nulInText("table.column")`. The check is in one place,
  `SyncedRecord`'s private `upsert`, which every record write goes through: exercises (save and seed) and all
  five program tables. Text holding U+0000 throws before the statement runs, and the transaction rolls back.
  Other control characters are stored whole.
- **Tests.** `NulTextTests`: exercise name and short name, by save and by seed; a day's name and tag; other
  control characters round-trip.
- **The one change to the tester's tests:** `ProgramRoundTripAdversarialTests.nul_cutsTheName` documented the
  cut. It now expects `nulInText("program.name")` and no rows written. Its name stayed; its title and doc
  comment say what changed and why.

**SF1 (Pete, 2026-09-30): catalog upgrades refresh catalog rows in place. Product decision #24.**
- **Change.** `seedIfNeeded`, when `version` is above the applied one, writes:
  - every entry whose id is not stored (an insert, as before, never skipped over a name);
  - every entry whose id is a **live** row with `is_custom = 0` and `catalog_version < version`.
  Both go through `ExerciseRecord.write`, the same diff programs use. So a refreshed row keeps its `id` and
  `created_at`, and its `updated_at` moves only if its content changed. Each row written then records
  `version`. Custom rows, deleted rows and rows the catalog no longer lists are not written at all, and keep
  their old version.
- **One rule I added, which needs the orchestrator's confirmation: a lifter's `save` clears
  `catalog_version`.** The tester's `ExerciseSeedingAdversarialTests.upgrade_leavesStoredRowsAsTheyAre` saves
  an edit of a catalog exercise (`isCustom` false), then upgrades, and expects the edit to survive. Under
  decision #24 as worded, that row is a live catalog row of an older version, so it would be refreshed and
  the test would fail, and I may not change it. With the version cleared, a saved row is the lifter's, and
  `catalog_version < version` excludes it, so the decision's own selection rule stays as worded.
  - Clearing is metadata like the seed's mark: it never moves `updated_at`.
  - Product-wise it changes nothing today, since F12 edits custom exercises only.
  - If the orchestrator prefers the plain reading, drop the one `UPDATE` in `save`, and the tester's test
    and the clause `seedLeavesTheLifters` need changing.
- **Duplicate ids in one catalog** keep the "last entry wins" behaviour the tester documents: the entries are
  made unique by id first (see N3).
- **Contract.** Two new clauses:
  - `seedRefresh`: a corrected entry reads back corrected, an unlisted one stays, and a same-version reseed
    changes nothing;
  - `seedLeavesTheLifters`: a custom exercise holding a catalog id, and a catalog exercise the lifter saved,
    survive an upgrade that changes them.
  `seedUpgrade` is reworded ("adds the new ids without duplicating one").
- **GRDB tests** (`CatalogUpgradeTests`):
  - `upgrade_refreshesListedCatalogRows_inPlace`: per row, `created_at`, `updated_at`, version and a load, for a
    corrected, an unchanged, an unlisted and a new entry;
  - `upgrade_leavesADeletedCatalogRow`: the deleted row is byte for byte unchanged, its version included;
  - `save_ofACatalogExercise_clearsItsVersion`.
- **Docs.**
  - `docs/product-decisions.md` #24, right after #23.
  - Decision 2 above is amended.
  - The protocol doc of `seedIfNeeded` is reworded.
  - F07's seeding line now says the seed also refreshes. F03's files are untouched (PR #14 rewords them).

**SF2 (decided: the rule moves into LedgerDomain; an approved exception to the brief's "no Domain type
changes").**
- **Change.** A new public, pure, Foundation-only helper, `LedgerDomain/Rules/ExerciseSearch.swift`:
  - `key(_:)`;
  - `matches(_:query:)`, and `matches(name:shortName:needle:)` for undecoded rows;
  - the comparator `isInNameOrder(_:_:)`, and `sorted(_:)`, which folds each name once.
  Persistence's internal copy is deleted. `GRDBExerciseRepository` matches rows before decoding through
  `matches(name:shortName:needle:)` and orders with `sorted`.
- **The contract** drops its `String.folded` copy, which also lacked the trim, and takes its expected order
  from `ExerciseSearch.sorted`.
- **Briefs.** F12's line now says that `search` takes one primary muscle, so the group pills filter
  `observeAll()` in memory through `ExerciseSearch`, mapping each pill to its `MuscleGroup` set. F07's inputs
  point the fakes at the helper.
- **Tests.** `LedgerDomainTests/Rules/ExerciseSearchTests` (key, matching, name order: the comparator and
  `sorted` agree), plus every search clause.

**SF3: behaviour the fakes must share is now contract, and the protocols say it.**
- **New clauses:**
  - `ProgramRepositoryContract.setActiveMissing` (`missingRow` for an unsaved and a deleted program);
  - `duplicateChildren` (`duplicateIdentifier` for a slot, a day and a week id used twice; nothing saved);
  - `otherProgramsIDs` (B1);
  - `ExerciseRepositoryContract.seedCatalogRows` (an entry marked custom is stored as a catalog row).
  The new program clauses are in `ProgramRepositoryContract+Identity.swift`; the contract imports
  `LedgerPersistence` for the error.
- **Clause counts.** The exercise contract now has 11 clauses and the program contract 9.
- **Protocol docs** (`LedgerDomain/Protocols/Repositories.swift`):
  - `ExerciseRepository`: `all` (name order), `search` (`ExerciseSearch`, decision #23), `save` (a saved
    exercise is the lifter's), `seedIfNeeded` (decision #24, replacing "Seeds or additively upgrades"),
    `observeAll`;
  - `ProgramRepository`: `save` (what it throws; nothing written on failure), `setActive` (`missingRow`),
    `delete` (soft, and it makes the program inactive).

**Nits.**

| Nit | Done? | Change, and the test that pins it |
|---|---|---|
| N1 exercise `save` stamps an unchanged row | Done | `save` reads the live row and goes through `ExerciseRecord.write`, which skips an unchanged row. `save_writesTheDocumentedColumns` now checks that an identical save keeps `updated_at` and a changed one moves it. |
| N2 `delete` leaves `is_active = 1` | Done | `delete` clears the flag on the live row, in the same transaction, before the soft delete. `ProgramSoftDeleteTests.delete_clearsTheActiveFlag`: the flag reads 0, and a sync-style revival with a later stamp leaves the other program active. |
| N3 duplicate ids in one catalog | **Skipped** | The fix (throw `duplicateIdentifier`) contradicts the tester's `ExerciseSeedingAdversarialTests.duplicateIDsInTheCatalog`, a "(documents)" test pinning "the last entry wins", and item 4 is the only tester test I may change. Today the seed makes entries unique by id (the last wins) before its diff, so behaviour is unchanged. Throwing instead is a one-line change in `seedIfNeeded` plus that test, if the orchestrator wants it. F03 validates unique ids, so only a broken bundle reaches this. |
| N4 "unchanged write emits nothing" could not fail | Done | `observeAll` and `observeActive` build their observation in `allObservation()` and `activeObservation()` (typed `DistinctObservation`). `ObservationTests` starts those same observations into an **unbuffered** stream, then makes a write that changes no value (`UPDATE … SET x = x`) before a real change. A spurious emission would now be read first. Mutant: `removeDuplicates(by: { _, _ in false })` fails both tests. |
| N5 `Seeders` traps on inputs it accepts | Done | `program` and `slot` throw `Seeders.UnsupportedShape(parameter:value:)` outside the documented ranges: `days` 0–7, `slotsPerDay` 0–32, a slot `position` 0–31, and a non-empty `exercises`. I chose throwing over `precondition` because the functions already throw, and a trap cannot be tested on the simulators. `SeedersTests` covers each bound, and that the largest shape builds with distinct ids. |
| N6 F07's lines | Done | F07's lines now have `try await … seedIfNeeded(ExerciseCatalog.seed(), …)` and the failure path. F05 recommends logging at fault level and carrying on, since the seed rolls back and retries next launch; F07 decides. The simulator caveat stays: F20 times a real watch. |
| N7 F05 brief "search by prefix" | Done | The test plan points at decisions #23 and #24. |
| N8 `rpe_x2` through `NSDecimalNumber.intValue` | **Skipped** | `RPE` holds whole half-points 10…20, for which `intValue` is exact. The review's first fix exposes `RPE`'s half-points in Domain, an API change outside the approved SF2 exception. The other, a rounded conversion with a `guard`, adds a branch no test can reach (coverage). Revisit if `RPE` ever gains a public half-point accessor. |

**Mutation check (host, one at a time, file restored after each; scratchpad `f05s2-fix1-mut/`).** Every
mutant was killed:

| Mutant | Killed by |
|---|---|
| B1: no `refuseOtherProgramsIDs` | tester's two identity tests; clause `otherProgramsIDs` |
| S2-2: the original lenient `Int.fetchOne` | `damagedCatalogVersion_throwsByName` |
| S2-3: the original text keying | tester's `saveOverDamagedID_repairs` (`x'00'`) |
| S2-4: no NUL check | `NulTextTests` (2), tester's `nul_cutsTheName` |
| SF1: no refresh / no clearing on save / refreshing deleted rows / refreshing custom rows / stamping every refreshed row | `CatalogUpgradeTests` and clauses `seedRefresh`, `seedLeavesTheLifters`; tester's `upgrade_leavesStoredRowsAsTheyAre` and `idClash_leavesTheCustomRow`; `upgrade_recordsItsVersion_evenWhenItAddsNothing` |
| SF2: no diacritic folding / no id tie-break | `ExerciseSearchTests`; clause `searchText` |
| SF3: `setActive` without its check / no duplicate check / seed keeps `isCustom` | clauses `setActiveMissing`, `duplicateChildren`, `seedCatalogRows` |
| N1, N2, N4 (each observation), N5 | the tests named in the nit table |

**Code lines** (same method as above; it reproduces 684 at `641e4b2`): **775**, up 91 (target 500, split
threshold ~1,000).
- `GRDBExerciseRepository` 147 (+27: refresh, strict version, save through the diff, the observation);
- `ProgramRows` 152 (+25: B1);
- `ExerciseSearch` (LedgerDomain, new) 25; the old copy in `GRDBExerciseRepository` is gone, inside its +27;
- `GRDBProgramRepository` 75 (+7: N2, the observation);
- `SyncedRecord` 54 (+3: the NUL check; the unused instance `upsert` is removed);
- `LedgerPersistenceError` +1, `DistinctObservation` +3.
- Not counted: `LedgerTestSupport` (three clauses for programs, three for exercises, `UnsupportedShape`),
  tests, docs.

**Gate after fix round 1 (2026-09-30, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0):**
- **`scripts/check.sh --fast`: green.** On the host, `LedgerPersistenceTests` has 214 tests. That includes the
  tester's four former failures, now passing, and the timing tests, skipped. `ExerciseSearchTests` has 3.
- **Full gate, through the lock: green, exit 0** (344 s; log `scratchpad/f05s2-fix1.log`).
  - Format, lint, the package graph and pins, and the script tests: OK.
  - **17/17** PR targets passed on iOS, and **8/8** PR-Watch targets on watchOS.
  - `LedgerPersistenceTests` on each simulator: **209 passed, 4 skipped** by design (the protection
    read-back and three nightly timings).
- **Coverage:** LedgerPersistence **99.91 %** (1189/1190), LedgerDomain 99.00 %, LedgerDesign 96.46 %,
  overall 98.64 %.
- These notes were finished after the gate. They are docs only.

### S2 fix round 2 (2026-09-30): S2-5, the review's nits, the search key, F03 criterion 8

Inputs: `test-findings.md` "# Slice S2 — close-out round" (S2-5, S2-N1, S2-N2), `review.md` "# Slice S2 review —
fix round 1" (N-a to N-d), and F03 criterion 8, which is F05's now that F03 is on `main` (merged at `07fb6c8`).
Every fix was checked by a mutant: the fix undone, the named test seen failing, the file restored (host, one at a
time; script and results in scratchpad `f05s2-fix2-mut/`).

**S2-5 (minor bug): a save repairs a week or day whose `program_id` names no program again.**
- **Change.** As the tester proposed: the three owner queries of `refuseOtherProgramsIDs` count a row as another
  program's only when its `program_id` (a slot: its day's) names a **stored** program, live or deleted:
  `AND program_id IN (SELECT id FROM program)`. A dangling or blob `program_id` is damage, so the upsert writes
  it back, as before fix round 1. The error now always names a real program's row.
- **Test.** The tester's `ProgramIdentityCloseoutAdversarialTests.danglingParent_isRepairedBySave` (4 cases)
  passes; it failed 3 of 4 before. Mutant (the filter removed): that test fails, and only it. The ten takeover
  tests and every B1 test still pass.

**N-a: NUL is now contract, and F11 and F12 refuse control characters.**
- **Contract.** Two clauses named `refusesNul`:
  - exercises: a name, then a short name, holding U+0000 throws `nulInText("exercise.name")` /
    `("exercise.short_name")`, and so does a seed with one such entry; `all()` is then still `[landmine]`;
  - programs: a program name, a day name, a day tag (edits of a stored program), and a new active program's name
    throw `nulInText` by column; `active()` is still the stored program.

  The exercise contract now imports LedgerPersistence, as the program contract already did. Clause counts: 13
  for exercises, 10 for programs.
- **Briefs.** F12's `CustomExerciseDraft` name rule and a new "Names" line in F11's domain section: refuse
  control characters (Unicode `Cc`, U+0000 included) before `save`. The error copy is left to F12 and F11.
- **Protocol docs.** `ExerciseRepository.save` and `ProgramRepository.save` name `nulInText`.
- **Mutant** (the NUL check off): both `refusesNul` clauses fail.

**N-b: `otherProgramsIDs` covers a slot a live program dropped.** Before the delete, the clause saves the first
program with day 0's first slot removed and expects the second program's copy of that slot to throw
`duplicateIdentifier("slot …")`. Mutant (slot owners counted only while live, or under a deleted program, which
is the fake the review describes): the clause fails.

**N-c: writes run in one order on every launch.**
- **Changes.**
  - `seedIfNeeded` dedupes with a seen-set over the reversed catalog and restores the catalog's order. The last
    entry of a repeated id still wins, at its last position. Inserts, refreshes, version marks and clash logs
    follow the catalog.
  - `SyncedRecord.write` soft-deletes removed rows in `stored`'s order, which is each query's `ORDER BY`.
- **Tests.**
  - `CatalogUpgradeTests.seed_writesInCatalogOrder`: rowid order equals the bundled catalog's order.
  - `ProgramSoftDeleteTests.softDeletes_runInStoredOrder`: a statement trace (`Repositories.statements`)
    of `delete` shows the 20 slot soft deletes in `position, id` order.
- **Mutants** (the `Dictionary(…).values` seed, the `storedByID.keys` deletes): each fails its test.

**N-d: the doc of `seedIfNeeded`** now says the applied version moves up whenever the upgrade writes a row;
otherwise the next launch checks again, as a no-op. Docs only.

**S2-N1 and S2-N2: the search key folds width, and folds before it trims.**
- **Change.** `ExerciseSearch.key` is now
  `folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)`, then
  `trimmingCharacters(in: .whitespacesAndNewlines)`. Fullwidth `ＢＥＮＣＨ` finds "Bench", and the blank that folding
  uncovers in `"bench \u{301}"` is trimmed.
- **`ı` and `Ø`: left as they are, by choice.** They are letters, not a base letter plus a mark, so
  Foundation's locale-neutral folding keeps them. Mapping them would need a transliteration (`Latin-ASCII`) or
  a hand table. The first also rewrites `ß`, ligatures and more, at a cost on every key. The second is a list
  to maintain. Neither is trivial and safe, and the catalog is English. `ExerciseSearch`'s doc says so.
- **Residue, documented in no test.** One fold is not always idempotent: a run of two or more lone combining
  marks after a blank loses one mark per pass, and so do halfwidth kana sound marks. No keyboard types these,
  and the tester's laws property test still passes. Folding to a fixed point would cost a second fold on every
  key.
- **Decision #23's row** now reads "ignoring case, diacritics and character width". F12's line, the contract
  clause `searchText` (a new fullwidth `ＲＤＬ` case) and the GRDB doc comments follow it.
- **Tests.**
  - `ExerciseSearchTests.key_foldsWidth_thenTrims`: fullwidth letters, the uncovered blank, a key being its own
    key, and `ı`/`Ø` kept;
  - a fullwidth case in `matches_nameOrShortName`;
  - the contract's `searchText`.

  Mutants: without `.widthInsensitive`, those tests and the clause fail; trimming first, the key test fails.
- **The one change to the tester's tests.** `ExerciseSearchCloseoutAdversarialTests` pinned the old behaviour
  "(documents)", so it changes with the decision, as `nul_cutsTheName` did for S2-4:
  - the two fullwidth folding cases now expect a match;
  - `blankWithAMark_isNotTrimmed` now expects the blank trimmed (its name is kept; its title and doc say
    why);
  - the suite's doc comment records the change.

  Every other case, `ı`, `Ø`, inner blanks and U+200B included, is unchanged.

**F03 criterion 8: the seed contract against `CatalogSeedFixture`.**
- **Contract clause `seedBundledCatalog`.** It follows the fixture's doc-comment scenario on the real catalog:
  - `base()` seeds one exercise per entry, and `all()` equals the entries;
  - after `custom` is saved, seeding `base()` again changes nothing;
  - `upgrade()` adds `added` and `clash`, `clash` despite its name, and leaves `custom` as it was.
- **GRDB test `CatalogUpgradeTests.bundledCatalog_upgradeStampsOnlyNewRows`.** Decision #24's refresh on 224
  rows:
  - the 224 base rows keep `created_at` and `updated_at`, and only `catalog_version` moves to the upgrade's;
  - the two new rows carry the upgrade's stamp;
  - the custom row stays byte for byte.
- **Mutants.**
  - A clash entry skipped: `seedBundledCatalog` and `seedNameClash` fail.
  - The refresh stamping every row: the GRDB test and `upgrade_refreshesListedCatalogRows_inPlace` fail.

**Skipped:** nothing. All four nits were cheap, and none conflicted with a tester's test.

**Code lines** (same method; it reproduces 775 at `07fb6c8` against `main` 7740bd9): **777**, up 2 (target 500,
split threshold ~1,000). The S2-5 filter and the seed's dedupe are written out one clause per line; the N-c change
replaced a dictionary with a filter at no net cost. Not counted: `LedgerTestSupport` (+3 clauses), tests and docs.

**Gate (orchestrator, 2026-10-01, on the tree as committed; Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0).**
The round was cut off by a restart before its gate, so the orchestrator ran it: full `scripts/check.sh` exit 0
in 460 s (iOS tests 180 s, watchOS tests 126 s). Coverage: LedgerPersistence **99.91 %** (1190/1191),
LedgerDomain 99.05 %, LedgerDesign 97.20 %, overall 98.52 %. `ProgramIdentityCloseoutAdversarialTests`
(S2-5's `danglingParent_isRepairedBySave` among them) and the search suites pass on the host too, which is the
tester's condition for closing G2. The mutant results named above were in a scratchpad the restart removed; the
tests they were checked against are in the tree.

## Slice S3

History and stats, on `feat/F05-s3` (from `feat/F05-s2` a38ed78, which is S2 awaiting merge as PR #17). Closes
criteria 3, 4, 5, 6, 9, 10 and 12, and re-closes criterion 8 with a `materialize` → `compact` test (S1 review N9).
Schema v001 is unchanged: everything fits it.

### What landed

- `LedgerPersistence/Records/`:
  - `WorkoutRecords.swift`: `WorkoutRecord` and `WorkoutExerciseRecord`;
  - `LoggedSetRecords.swift`: `LoggedSetRecord` (computes `e1rm_e7g`) and `PersonalRecordRecord`;
  - `WorkoutRows.swift`: a workout as the rows of its four tables, the write diff, the owner check, and the
    read (`fetch`) over a `Selection` of workouts.
- `LedgerPersistence/Repositories/GRDBWorkoutRepository.swift` and `LedgerPersistence/Stats/GRDBStatsQueries.swift`.
- Small additions to S1/S2 files:
  - `LedgerPersistenceError.notFinished`;
  - `ColumnCodec.derivedID(named:in:)`: S2's version-5 UUID, moved out of `SlotMissRecord` so `personal_record`
    rows use it too (`SlotMissRecord.id` now calls it; the ids are unchanged);
  - `ColumnReader.reps`, `date`, `optionalDate`; `isNull` is no longer private;
  - `Row.readable(as:_:)`: read a row, or log it and leave it out.
- `LedgerTestSupport/Persistence/`:
  - `Seeders+History.swift`: `Seeders.workout(…)`, `SetSpec`, `ExerciseLog`, and
    `Seeders.history(exercises:workouts:setsPerWorkout:rng:endingAt:)`;
  - `WorkoutRepositoryContract` (12 clauses) and `StatsQueriesContract` (9), both over `HistoryStores` (a
    workout repository, stats queries and a program repository on one store), public API only;
  - `ContractCheck.first(…)`: the first failed check of several, each of which may `await`.
- Tests (`LedgerPersistenceTests`): `WorkoutRepositoryTests`, `WorkoutRowDiffTests`, `StatsQueriesTests`,
  `DamagedWorkoutRowTests`, `MigrationCompatibilityTests`, `Performance/StatsQueriesPerformanceTests`, two tests
  in `ObservationTests`, two in `SeedersTests`; `Fixtures/db-v001.sqlite`.

### Decisions and deviations

1. **`materialize` is an upsert keyed by the workout's id, in one write transaction.**
   - It reads the workout's live rows from all four tables, then writes parents first through S2's
     `SyncedRecord.write`: a new or changed row is upserted, an unchanged row is left alone, and a row the
     workout no longer has is soft-deleted.
   - So a second materialisation of the same state runs no `INSERT` or `UPDATE` at all, and a rebuild that
     changed one set stamps only that row. A deleted workout comes back, with its `created_at`.
   - `delete(id:)` is the same write with no rows: it soft-deletes the workout, its exercises, sets and
     records (ADR-002; hard deletes are F29's). It does not undo the misses the workout recorded, and it leaves
     `workout_health`.
2. **Only a finished workout is stored (new error `notFinished`).** `materialize` throws unless the phase is
   `.finished` and `endedAt` is set, and stores nothing. History, and every stats range, is keyed on `ended_at`,
   so a live or endless workout has no place in it. A discarded workout is not stored: when a late discard
   overtakes a finish (F04 input 6), the host calls `delete(id:)`.
3. **The totals come from the state, not from `summary`.** `volume_e7g_reps`, `done_sets` and `total_sets` are
   computed from the sets being written, and `pr_count` is `prs.count`. `summary` is
   `WorkoutEngine.summary(workout, prs:)`, a function of the other two arguments, so it holds nothing else to
   store, and columns taken from it could disagree with the rows. The parameter is unused (open question 1).
4. **`slotUpdates` write misses only, and never fail the workout.** For each slot, its stored `slot_miss` rows
   are made its `misses` through the diff a program save uses (derived ids, so a kept miss keeps its row). No
   other slot field is written. A slot that is not stored, or is deleted (the program was edited or deleted
   during the workout), is logged at notice level and skipped. The alternative, a foreign-key error, would
   make that workout impossible to materialise for good.
5. **`programUpdates` is not applied.** F10's input 7 leaves open whether a swap reaches the program at the
   swap or from `.materialize`; `ProgramRepository` has no call for it yet.
6. **History reads reset the live-only fields.** `cursor`, `rest`, `programUpdates` and each exercise's
   `lastPerformance` are not stored and read back empty; `autoRest` reads back `true`.
   `WorkoutRepositoryContract.stored(_:)` is that mapping, for F07's fake.
7. **A workout's date is when it ended.** `recent`, `workouts(in:)`, every stats range, the week of a volume or
   an e1RM, and the date of the "Last" line all use `ended_at` (the column `idx_workout_ended` indexes). A
   workout then belongs to exactly one week, whenever its sets were ticked, and an edit that re-ticks a set
   cannot move its volume to another week. Lists are newest first (`ended_at DESC`, then id). A limit below 1
   gives none (SQLite reads a negative `LIMIT` as no limit).
8. **e1RM is stored for every done set of at most 12 reps, whatever its kind** (the schema's comment). The
   **bests** (`bestSet`, `bestE1RM`, `e1RMByWeek`) count only `.working` and `.added` sets, the sets
   `PersonalRecords.detect` lets set a record (decision #3). Otherwise a drop or warm-up set could hold a best
   that no record-eligible set is ever compared with. Volume counts every kind (rule 34), and the "Last" line
   only `.working` sets (criterion 4).
9. **The "Last" line** (criterion 4, rule 14) is the most recent workout in which the exercise has a done
   working set: its end date, how many such sets, and the load and reps of the heaviest of them (of two as
   heavy, the one with more reps). **`bestSet`** is the heaviest set, then more reps, as F12's brief words it.
10. **`e1RMByWeek(lastWeeks:)`** covers the `lastWeeks` stats weeks ending with the one that holds the injected
    `now`. Each workout's week is `calendar.firstDayOfWeek(containing:)`, compared in whole civil days, and the
    key is `calendar.isoWeekKey(for:)`. Nothing loops over weeks, so `lastWeeks: .max` is safe; a `now` no
    calendar holds gives `[:]`. The query reads every session of the exercise, since `WeekCalendar` cannot turn
    a civil day back into a date for a SQL bound (1 ms at 20,000 sets).
11. **`weeklyVolume`** follows the S1 plan: SQL groups by `weight_e7g` and sums only the reps; the products are
    summed in `Decimal`. Exact at any size (`StatsQueriesTests.weeklyVolume_isExact`).
12. **`sessionsCompleted`** counts the finished workouts that ended in the range, with or without a done set.
    **`sessionCount`** counts the workouts with a done set of the exercise, of any kind. **`personalRecords`** is
    newest first, and within a workout the estimated 1RM before the weight at reps. **`recentlyLogged`** orders
    exercises by their latest workout, then by id.
13. **`updateSets`** loads the workout that holds the exercise, replaces that exercise's sets and writes the
    workout back through the same diff, in one transaction. So e1RMs and the workout's totals are computed
    again, removed sets are soft-deleted, and unchanged rows keep `updated_at`. The record rows and `pr_count`
    are left as they are (open question 4). An exercise of no live workout throws `missingRow`.
14. **Ids are never taken over** (the class of S2's B1). An exercise or set id that another stored workout
    holds, live or deleted, throws `duplicateIdentifier` before any row is written, from `materialize` and from
    `updateSets`. Two exercises or two sets sharing an id in one workout throw the same. As in S2-5, a row whose
    parent names no stored workout is damage, and a write repairs it.
15. **`personal_record.id` is derived**: the version-5 UUID of the record's place among its workout's records,
    in the workout's namespace. Materialising the same records again writes the same rows, with no UUID source.
    The table is local-only, so the ids need not agree across devices.
16. **Damaged rows** (S1 and S2's rule: kept, logged, never a trap).
    - Every history column is read through `ColumnReader`. A `REAL` in an integer column, a date that is not a
      finite `REAL`, reps below 1, an unknown case, a source with only some of its three columns, or a
      malformed id throws by name.
    - A workout is one aggregate. `workout(id:)` and `updateSets` throw; `recent`, `workouts(in:)` and
      `observeRecent` log the workout, leave it out and return the rest, and the stream goes on.
    - A stats aggregate over a damaged value throws by name. `personalRecords` and `recentlyLogged` leave an
      unreadable row out.
    - Nothing is deleted, and materialising the workout again repairs it, because the diff compares stored
      rows as column values.
    - Unlike S1's event store there is no count of unreadable workouts on the protocol (open question 9).
17. **Refusals.** Text holding U+0000 throws `nulInText` (S2's check, in `SyncedRecord`). A weight that is not a
    whole number of 10⁻⁷ g throws `inexactWeight`. A date that is not finite (`startedAt`, `endedAt`, a set's
    `doneAt`, a record's `achievedAt`) throws `nonFiniteDate`. Each leaves the database as it was.
18. **`fixtures/db-v001.sqlite`** (241 KB) is a database file that v001's code wrote through the repositories:
    7 exercises (one custom), an active program and a deleted one, three workouts (one with records and
    edited sets, one deleted), settings, the 13 `PayloadV1` envelopes as an uncompacted log, and one
    `workout_health` and one `device` row. It is in rollback-journal mode, so it is one file.
    - The one-off generator was deleted, as for S1's payload fixtures; the file is never regenerated.
    - `MigrationCompatibilityTests` expects written-out values, not `Seeders` output, so a later change to a
      seeder cannot move them.
    - The test-only `v002_testOnly` adds a column to `workout`, a table with a foreign key to it, and an index.
    - **Deviation from testing-strategy §2.2**, which describes `.sql` dumps and a `migrations.lock`: the brief's
      Definition of Done names the `.sqlite` file, and S1 already pins the migration list
      (`SchemaTests.inMemory_foreignKeysOn_v001Applied`) and the DDL (`schema-v001.sql`).
19. **`StatsQueriesPerformanceTests`** seeds 400 workouts × 50 sets through `materialize` into a file database,
    and checks each of the nine methods (and all-time volume) against `PerformanceBudget.statsQuery` (50 ms).
    - **It asserts the 95th percentile of 20 runs**, as criterion 9 says, where testing-strategy §2.2 says the
      median of five.
    - It is `.performance` and `.slow` (a new tag), and enabled only in the nightly lane by
      `TestLane.runsSlowTests`, as S1's and S2's timing tests are. The PR plans' `skippedTests` are unchanged.
20. **Brief paths.** `Stats/StatsQueries.swift` in "Touches" is `Stats/GRDBStatsQueries.swift`, after the type.
    `TestDatabase.swift` was never created: tests use `LedgerDatabase.inMemory()` (S1). `Seeders.history` has one
    more parameter than the brief's, `endingAt`, with a default.
21. **Not changed, on purpose:** `LedgerDomain` (no line), `docs/`, the other briefs, the test plans,
    `Package.swift`, and `project.pbxproj`.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 3. five exercises materialise as rows with e1RM, records and misses, in one transaction; a failure leaves no rows | `WorkoutRepositoryTests.materialize_writesEveryTable_inOneTransaction` (row counts; a statement trace shows one `BEGIN` and one `COMMIT`), `materialize_computesE1RM` (all 19 sets), `materialize_writesTheDocumentedColumns`, `failedMaterialize_leavesNoRows` (a trigger fails the first record insert, after the workout, exercises and sets; then an inexact weight in the last set: every row and stamp as before), `nonFiniteDates_areRefused`; contract clauses `roundTrip`, `materializeTwice`, `replaces`, `notFinished`, `writesMisses`, `refusesNul` |
| 4. `lastPerformance` after 34 bench sessions | contract clause `lastPerformance` (34 sessions; drop, added and undone sets ignored; a later workout without a done working set skipped; the 34th deleted) ; `StatsQueriesTests.exerciseTwiceInAWorkout_isOneSession` |
| 5. `e1RMByWeek(lastWeeks: 8)` over 10 weeks | contract clause `e1RMByWeek` (two workouts in one week, a week with none, a week of 15-rep sets, weeks 8 and 9 outside, next week outside; `lastWeeks` 0 and 1); `StatsQueriesTests.e1RMByWeek_followsTheWeekStart` (Sunday against Monday start; `lastWeeks: .max`; a non-finite `now`) |
| 6. `weeklyVolume` of two consecutive weeks, and the delta | contract clause `weeklyVolume` (drop, added and warm-up sets counted, undone not; a workout on the week's first instant; the delta); `StatsQueriesTests.weeklyVolume_isExact` |
| 8. compaction after materialisation (S1 N9) | `WorkoutRowDiffTests.materializeThenCompact_keepsTheWorkout` |
| 9. each stats method under 50 ms at 20,000 sets | `StatsQueriesPerformanceTests.everyQuery_underBudget` (nightly lane; run by hand below) |
| 10. `observeRecent(limit: 10)` emits on materialise | `ObservationTests.observeRecent_emitsTheMaterialisedWorkout`, `observeRecent_emitsOnChange_only` (unbuffered: no value for a no-op write, a repeated materialise, or a workout outside the limit); contract clause `observeRecent`. All run in PR-Watch too |
| 12. a v001 database with data survives a v002 | `MigrationCompatibilityTests.v002_keepsTheData`, `fixture_isAtV001` (applied migrations, DDL equal to `schema-v001.sql`, integrity, foreign keys, row counts), `open_readsAndWritesTheFixture` (the app's own `open(at:)`) |
| Test plan: `updateSets`, delete cascades | `WorkoutRowDiffTests.updateSets_recomputesE1RM_andTotals`, `updateSets_unchanged_writesNoRow`, `delete_cascades_softly` (soft deletes in stored order; revival keeps `created_at`), `materializeTwice_writesNoRow`, `rematerialize_diffsRows`, `misses_ofASlotNotStored_areSkipped`, `recordIDs_areDerived`; contract clauses `updateSets`, `deleteHides`, `newestFirst`, `duplicateIDs`, `otherWorkoutsIDs` |
| Test plan: PR history, sessions this week, recently logged | contract clauses `personalRecords`, `sessions`, `recentlyLogged`, `bests`, `emptyHistory`, `followsEdits`; `StatsQueriesTests.onlyLiveRowsOfFinishedWorkouts_count` |
| Invalid stored data | `DamagedWorkoutRowTests` (23 damages across the three tables: `workout(id:)` and `updateSets` throw by name, the lists and the stream leave the workout out, the row is kept, a new materialise repairs it; three dangling parents; stats over damaged values; unreadable record rows and exercise ids) |
| Seeder | `SeedersTests.history_isDeterministic_andSized`, `history_smallShapes_build` |

**Mutation check (host, by hand, one at a time, file restored after each; script and results in scratchpad
`f05s3/mut/`).** 26 mutants, all killed. Two survived the first run and each got a test: the misses of a slot
that is not stored (the contract's unknown slot had no misses, so nothing was written either way), and a
workout row soft-deleted on its own (its children's `deleted_at` hid it already). The others: e1RM for undone
sets; undone sets counted; the bests or the "Last" line counting every kind; no owner check; no `notFinished`
guard; an unclamped limit (both); duplicate emissions; the e1RM window a week too long; either range closed at
the top; `workout(id:)` leaving a damaged workout out; `updateSets` clearing the records or `pr_count`; either
list oldest first; the phase filter dropped; wrong totals; a partial source read as none; `bestSet` ties; a
lenient date read; `sessionCount` counting rows; misses never cleared.

### Code lines

Measured as in S1 and S2: non-blank Swift lines that are not whole-line `//` or `///` comments, SQL strings
included, in product sources only (`LedgerDomain`, `LedgerPersistence`). Counted with a script over
`git ls-files --others` plus the added lines of `git diff -U0 -- LedgerKit/Sources/LedgerDomain
LedgerKit/Sources/LedgerPersistence` (scratchpad `f05s3/count.sh`).

- **662 lines added (655 net), over the 500 target** (standards §10: under ~1,000, so no forced split, and under
  the ~700 at which this slice was to stop and propose one). The plan estimated ~455.
- New files: 621.
  - `Stats/GRDBStatsQueries` 162;
  - `Records/WorkoutRows` 139, `WorkoutRecords` 123, `LoggedSetRecords` 103;
  - `Repositories/GRDBWorkoutRepository` 94.
- Existing files: +41, −7 (`ColumnReader` readers and `Row.readable`, `ColumnCodec.derivedID`, the error case).
- `LedgerDomain`: 0.
- Not counted: `LedgerTestSupport` (the seeders and the two contracts), tests, the fixture, docs.
- **Why above the estimate:** strict reads and the leave-out rule for lists; the owner check; four record types
  written out one column per line; ten SQL statements laid out a clause per line.
- **The split considered: repository vs stats** (the plan's). (a) records, `WorkoutRows`, the repository, the
  fixture and migration tests, about 500 lines, closing 3, 10 and 12; then (b) `GRDBStatsQueries` and its
  contract, about 162, closing 4, 5, 6 and 9. Not taken: the slice stayed under the stop line, the stats tests
  need the repository to seed anything, and (b) alone is a small PR that costs a second full gate and review
  round. It remains a clean seam if the orchestrator prefers it.

### Gate and coverage (2026-10-01, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0)

- **Host:** `swift test --filter LedgerPersistenceTests`: 270 tests in 63 suites passed (the timing suites
  skipped by design).
- **Full gate, through the lock: green, exit 0** (`scripts/check.sh`, 402 s; log `scratchpad/f05s3/check-1.log`).
  - Format, lint, the package graph and pins, and the script tests: OK.
  - **17/17** PR targets passed on iOS (1,295 passed, 8 skipped by design), and **8/8** PR-Watch targets on
    watchOS (1,186 passed, 8 skipped). The new suites ran on both: 33 test cases passed and 1 skipped (the
    stats timing).
  - Warnings: none new. The build prints the two "will never be executed" warnings of
    `PayloadVersionAdversarialTests.swift:29` and `SettingsDecodingAdversarialTests.swift:123`, which S2's gate
    log has too. This run compiled from scratch, so xcbeautify also printed "the following command failed with
    exit code 0 but produced no further output" beside the files of that warning's compile batch (22 lines,
    none of them a file of this slice; another worktree's log of the same morning has the same lines).
- **Coverage:** LedgerPersistence **99.84 %** (1914/1917; threshold 90), LedgerDomain 99.05 %, LedgerDesign
  97.20 %, overall 98.67 %.
  - The 3 lines are closures that never run: the `now: Date.init` default arguments of the two new types (tests
    inject a clock), and S2's `uniquingKeysWith:` in `SyncedRecord.write`.
- These notes were written after the gate. They are docs only.

### Criterion 9, by hand (`Nightly` and `Nightly-Watch` plans, under the lock)

`-only-testing:LedgerPersistenceTests/StatsQueriesPerformanceTests`; script `scratchpad/f05s3/perf.sh`, log
`perf.log`, attachments exported from `perf-ios.xcresult` and `perf-watch.xcresult`. Both runs passed. 20,000
sets in 400 workouts, 12 exercises, a file database; 95th percentile of 20 runs after a warm-up, budget 50 ms:

| Query | iPhone 17 simulator | Watch Series 12 simulator | Host (debug) |
|---|--:|--:|--:|
| `lastPerformance` | 0.86 ms | 0.85 ms | 0.59 ms |
| `bestSet` | 0.70 ms | 0.69 ms | 0.41 ms |
| `bestE1RM` | 0.65 ms | 0.65 ms | 0.37 ms |
| `e1RMByWeek` (8 weeks) | 1.09 ms | 1.12 ms | 0.80 ms |
| `weeklyVolume` (one week) | 0.13 ms | 0.13 ms | 0.13 ms |
| `weeklyVolume` (all time) | 4.68 ms | 4.70 ms | 3.55 ms |
| `sessionsCompleted` | 0.05 ms | 0.05 ms | 0.05 ms |
| `sessionCount` | 0.66 ms | 0.69 ms | 0.39 ms |
| `personalRecords` | 0.31 ms | 0.36 ms | 0.33 ms |
| `recentlyLogged` | 6.92 ms | 6.95 ms | 3.67 ms |

The slowest, `recentlyLogged`, scans every done set. The simulators run on the Mac's CPU, so this rules out a
design problem but is not a device's figure (F20).

### How to verify by hand

1. `scripts/check.sh --fast`: on the host, `LedgerPersistenceTests` passes (270 tests).
2. Criterion 3: `swift test --package-path LedgerKit --filter 'WorkoutRepositoryTests|WorkoutRowDiffTests'`.
   `failedMaterialize_leavesNoRows` compares every row and stamp of five tables before and after.
3. Criteria 4 to 6: `swift test --package-path LedgerKit --filter StatsQueriesTests`. The contract clauses are
   listed by name; each one's doc comment in `StatsQueriesContract` works its expected values out.
4. The tests bite. Make each change, run `swift test --package-path LedgerKit --filter LedgerPersistenceTests`,
   and revert:
   - in `GRDBStatsQueries`, empty `SQL.recordKinds`: the `bests` clause fails;
   - in `WorkoutRows.write`, drop `refuseOtherWorkoutsIDs`: the `otherWorkoutsIDs` clause fails;
   - in `LoggedSetRecord.encode`, compute the e1RM for undone sets: `materialize_computesE1RM` fails.
5. Criterion 12: `sqlite3 LedgerKit/Tests/LedgerPersistenceTests/Fixtures/db-v001.sqlite 'SELECT * FROM
   grdb_migrations; PRAGMA integrity_check; SELECT name, phase, done_sets, quote(deleted_at) FROM workout'`, then
   `swift test --package-path LedgerKit --filter MigrationCompatibilityTests`.
6. Criterion 9: on the host, `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter
   StatsQueriesPerformanceTests`. On a simulator, under the lock: `xcodebuild test -project Ledger.xcodeproj
   -scheme Ledger -testPlan Nightly -destination "$(scripts/sim-destination.sh 'platform=iOS Simulator,name=iPhone
   17,OS=27.0')" -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages
   -onlyUsePackageVersionsFromResolvedFile -only-testing:LedgerPersistenceTests/StatsQueriesPerformanceTests
   -resultBundlePath /tmp/stats.xcresult`, then `xcrun xcresulttool export attachments --path /tmp/stats.xcresult
   --output-path /tmp/att`; `stats-queries.txt` holds each query's p95 and median.
7. Full gate: `scripts/check.sh`, through the shared lock.

### Open questions for the orchestrator

Each is implemented in the conservative reading named, and none changed a doc, an ADR or a Domain protocol.

1. **`materialize`'s `summary` parameter is unused** (decision 3). Recommendation: keep storing totals computed
   from the state, and drop the parameter when F10 next touches the protocol (F10's brief assumed a
   `finish(_:) -> WorkoutSummary` that does not exist either).
2. **Who deletes a workout when a late discard overtakes its finish** (F04 input 6, F17 item 2). F05 now offers
   what the host needs: `delete(id:)`, a soft delete that a later `.materialize` reverses. Recommendation: the
   host calls it on `.discardLog`, then compacts.
3. **`programUpdates`** is not applied (decision 5). Recommendation: F10 adds `replaceSlotExercise` to
   `ProgramRepository`, as its brief plans, and calls it beside `materialize`; or the orchestrator asks F05 for
   it inside `materialize`'s transaction, which is about 15 lines.
4. **`updateSets` does not detect personal records again** (decision 13; F13's risk). The stored records can go
   stale after an edit. Recommendation: a follow-up before F13, in which `updateSets` re-runs
   `PersonalRecords.detect` for the exercise from that workout forward. It needs question 5's query.
5. **`StatsQueries` has no query for `PersonalRecords.detect`'s `bestWeightAtReps` input** (`[Reps: Weight]` per
   exercise); `bestSet` gives one set. F10 cannot detect weight-at-reps records from the protocol as it is.
   Recommendation: add `bestWeightByReps(exerciseID:) -> [Reps: Weight]`, with a contract clause, in F10 or a
   small F05 follow-up (one `GROUP BY reps` query).
6. **Which sets count for the bests** (decision 8). Criterion 5 says "done sets"; F12's brief says only
   `.working`; this slice follows decision #3 and `PersonalRecords.detect` (`.working` and `.added`).
   Recommendation: keep it, and align F12's line.
7. **A workout's date is `ended_at`** (decision 7). A workout started on Sunday night that ends after midnight
   counts for Monday's week. Recommendation: keep it (one rule, indexed); the other choice is `started_at`.
8. **The shape of the "Last" line when sets differ** (decision 9): the count of done working sets, and the
   heaviest one's load and reps. Recommendation: keep it; rule 25's "Repeat last" then writes the top set.
9. **Unreadable workouts are logged and left out of lists, but not counted on the protocol** (decision 16).
   Recommendation: none needed until a screen wants to say "part of your history needs a newer Ledger"; then
   add a count, as `unreadableCount(for:)` in S1.
10. **Protocol doc comments.** `WorkoutRepository` and `StatsQueries` in `Repositories.swift` do not yet say what
    the contracts pin (newest first, `ended_at`, limits below 1, `notFinished`, `missingRow`,
    `duplicateIdentifier`, which sets count). I did not edit them, since that states a protocol's meaning.
    Recommendation: approve copying the GRDB types' doc comments up, as S2's SF3 did.
11. **Input lines for other briefs**, not written here:
    - F07: run `WorkoutRepositoryContract.clauses` and `StatsQueriesContract.clauses` against the fakes, over a
      `HistoryStores` whose stats read `StatsQueriesContract.now`; `GRDBStatsQueries(queue, now:)` takes the
      injected date.
    - F10: questions 1, 3 and 5; `materialize` throws `notFinished` for a live state; a slot update for a
      slot that is no longer stored is skipped.
    - F13: question 4; a damaged workout is missing from the list and `workout(id:)` throws.
    - F17: question 2.
12. **Criterion 9 asserts p95 of 20 runs**; testing-strategy §2.2 says the median of five (decision 19).
    Recommendation: reword the strategy line to match the criterion.

### S3 fix round 1 (2026-10-01): the adversarial round and the review

Inputs: `test-findings.md` "# Slice S3 — adversarial round 1" (S3-1 to S3-4, S3-Q1 to S3-Q4, S3-N1 to S3-N4) and
`review.md` "# Slice S3 review" (SF1 to SF4, N1 to N7), at `9664f9c`. Every decision below was made by the
orchestrator before the round. Each fix was checked by a mutant: the fix undone, the named test seen failing, the
file restored (host, one at a time; script and results in scratchpad `f05s3/fix1-mut/`).

**S3-1 = review SF1: a record that names another workout is refused.**
- **Change.** `WorkoutRows.refuseOtherWorkoutsIDs` throws, before any row is written, when a record's
  `workoutID` is not the workout being written. The false comment ("it cannot clash") is corrected.
- **The error is `duplicateIdentifier("personal_record of workout <id>")`**, naming the workout the record
  belongs to. I used the existing case, as S2 did for cross-owner ids: it is the same fault (a row another
  owner holds would be taken over), and callers already handle it from `materialize`. The payload names the
  workout, not the derived row id, so a fake can produce it from public API. A record naming a workout that is
  not stored is refused the same way, by name, where it used to fail on the foreign key.
- **Tests.** The tester's `WorkoutIdentityAdversarialTests.recordOfAnotherWorkout_doesNotReplaceItsRecords` now
  passes, unedited. Mine: `WorkoutRowDiffTests.recordOfAnotherWorkout_isRefused` (the error by name; every row
  and stamp unchanged). Mutant (the check off): both fail.
- **The contract clause is written and verified, but not in the tree: see "Blocked" below.**

**S3-2: a rebuild repairs a workout whose row, or an exercise row, was soft-deleted alone.**
- **Change.** `WorkoutRows.write` diffs the children against every live row under the workout's id, whatever
  the state of the rows above them: exercises and records through `Selection.stored` (the workout row, live or
  deleted), sets through `Query.setsUnderAnyExercise` (the workout's exercise rows, live or deleted). The
  stored workout row itself is still read live only, so a deleted row is revived. `delete` clears such
  leftovers too. Notes decision 16 ("materialising again repairs it") now holds for this state.
- **Tests.** The tester's `WorkoutRepairAdversarialTests.loneSoftDelete_isRepaired` (both cases) passes. Mine:
  `WorkoutRowDiffTests.loneSoftDeletedParent_hidesNoRows`. Mutants: exercises and records through the live row
  only, both fail; sets through live exercise rows only, the tester's fails.

**S3-3: a parent row whose id is a blob is damage, never an empty parent.**
- **Change.** `WorkoutRows.fetch` requires `TEXT` storage for the id of a workout row and of an exercise row,
  and throws `malformedColumn("workout.id")` or `("workout_exercise.id")` otherwise. So `workout(id:)` throws
  for a blob exercise id, the lists log the workout and leave it out, and a workout is never listed twice.
- **The residue, one part closed.** `sessionsCompleted` now has `AND typeof(id) = 'text'`, so a blob workout row
  is not counted. It is one predicate on a row the query already reads for `deleted_at` and `phase`, and the
  range still enters through `idx_workout_ended`. Every other query missed such a row already, because its
  children's text `workout_id` never equals a blob.
- **The residue that stays (accepted as damage-only).**
  - A blob workout row is never removed: a new materialisation stores the workout under its text id beside it.
    It is in no list, count or query.
  - The sets under a blob exercise id are invisible to the stats until a write repairs the row (the join
    compares text with a blob). The workout is unreadable meanwhile, so no screen shows it with the wrong
    totals; the weekly volume is short by those sets until then.
- **Tests.** The tester's `blobExerciseID_neverReadsAsAnEmptyExercise` and `blobWorkoutID_neverReadsAsAnEmptyWorkout`
  pass. Mine: `DamagedWorkoutRowTests.blobExerciseID_isDamage` and `blobWorkoutID_isDamage` (by name; left out;
  not counted; listed once after a rebuild; the blob row kept). Mutants: either check off, or the `typeof`
  predicate off, each fails its tests.

**S3-4 + review SF2: the contracts catch all 25 wrong fakes.** Changes are in `LedgerTestSupport` only, inside
the existing clauses (the clause count stays 21):

| Wrong fake | What now catches it |
|---|---|
| lists tie-break in insertion order | `newestFirst`: two workouts end at one instant, the larger id stored first; `lastPerformance`: the same for the "Last" line's workout |
| the Last line shows the first done working set | `lastPerformance`: the 34th session starts with 180 × 4 and 175 × 5 |
| the bests count warm-ups; `bestE1RM` counts drops (SF2) | `bests`: a 250 × 1 drop and a 240 × 2 warm-up, both heavier and with higher estimates than the best |
| `e1RMByWeek` counts excluded kinds (SF2) | `e1RMByWeek`: every workout has a 500 × 1 drop and a 450 × 2 warm-up |
| `e1RMByWeek` ignores the calendar's week start | `e1RMByWeek`: a Sunday-noon workout, read with `StatsQueriesContract.calendar(weekStart: .sunday)` |
| a workout's week is its best set's tick | `e1RMByWeek`: the current week's best ended ten minutes into the week |
| `sessionsCompleted` needs a done set (SF2) | `sessions`: the empty workout is inside last week |
| `personalRecords` ordered by the workout's end | `personalRecords`: the older workout's record was achieved last |
| `recentlyLogged` ties in row order | `recentlyLogged`: the newest workout has two done exercises, the larger id first |
| `updateSets` drops the records | `followsEdits`: `personalRecords` after the edit, and after the delete |
| `observeRecent` emits on every write | `observeRecent`: a repeated materialise and a delete of an unknown id between two changes |
| an exercise twice in one workout (SF2) | `sessions`: one session, and one "Last" line of its four sets |

- **The one sanctioned change to a tester's test.** `HistoryContractAdversarialTests.wrongFake_isCaughtOrListed`
  listed the ten gaps in `uncaught`. That set is now empty, and the test's title and doc say that every fault
  must break a clause. Its body is unchanged. `honestFake_keepsEveryClause` is untouched and passes: the honest
  model keeps all 21 clauses as strengthened.

**SF3: `updateSets` and stale records. No behaviour change.**
- `GRDBWorkoutRepository.updateSets`' doc now states the fact: the records and the count are left as they are
  and can be stale, and nothing can detect them again yet.
- Input lines are written into the briefs:
  - **F10**: `notFinished`; detection needs the bests as they stood before the workout (an ADR-004 rebuild
    against all-time bests stores no records); no weight-at-reps query; every record must name the workout;
    `programUpdates` is not applied; `slotUpdates` replace a slot's whole miss set (review N2); the "Last" line;
    the refusals.
  - **F13**: stale `personal_record` and `pr_count` after `updateSets`; no query returns a workout's records for
    the badge (review N3); unreadable workouts are left out, uncounted, and take a place of the limit (S3-N1);
    ordering; the reset fields; delete against a late materialise (S3-Q4).
  - **F17**: late discard → `delete(id:)`, then compact; a late `.materialize` on an uncompacted log brings back
    a deleted workout and overwrites `updateSets` edits (S3-Q4).
  - **F07**: what the fakes must honour, clause by clause.

**F05 follow-up before F10** (not in this round; it changes the Domain protocols, so it is serialized):
1. **Bests that exclude a workout, or are as of a date**, for both record kinds: the best e1RM and the best
   weight at each rep count (`[Reps: Weight]`), per exercise. `PersonalRecords.detect` needs them as they stood
   before the workout; today's all-time `bestE1RM` and `bestSet` include the workout once it is stored, and no
   query gives weight at reps.
2. **Where re-detection lives.** After `updateSets`, and on a rebuild, records must be detected again for the
   exercise from that workout forward (each later workout against the bests before it). Recommendation: inside
   F05, in the transaction of `updateSets` and of `materialize`, so `prs` stops being the caller's to compute;
   the alternative is a use case in F10 and F13 over query 1.
3. **Drop `materialize`'s unused `summary` parameter**, before F07 writes a fake that carries it.
4. Optional, for F13's badge: `personalRecords(workoutID:)` (`idx_pr_workout` serves it).

**SF4: the Domain protocol docs.** `LedgerDomain/Protocols/Repositories.swift`, comments only: `WorkoutRepository`
and `StatsQueries` now say what the contracts pin (the upsert, what is and is not stored, the errors, newest
first then id, limits below 1, the reset fields, which sets each query counts, ties, weeks). The false "its
summary" is gone. The two open product questions (set kinds for the bests, `ended_at` as the date) are stated as
today's behaviour with a pointer to the open question; nothing in `docs/product-decisions.md`, criterion 5 or
F12's line was touched.

**Nits.**

| Nit | Done? | Change, and the test that pins it |
|---|---|---|
| Review N1 = tester S3-N2: the lists filter on `phase` like the stats | **Blocked** | See below: the tester's "(documents)" test pins today's behaviour, and it is not the one test this round may edit. |
| Review N2: `slotUpdates` replace the whole miss set | Done (docs) | `materialize`'s doc, the protocol doc, and F10's input 6. |
| Review N3: nothing reads `pr_count` | Done (docs) | F13's input 2; follow-up item 4. |
| Review N4: a record read from a row had the wrong `rowID` | Done | `PersonalRecordRecord` stores its `rowID`: derived in the writing initialiser, the row's own `id` in `init(row:)`. `WorkoutRowDiffTests.recordIDs_areDerived` reads the rows back. Mutant (derived from place 0): fails. |
| Review N5: `updateSets`' doc overpromised | Done (docs) | "used twice in the workout, or held by another workout (live or deleted)". |
| Review N6: `GRDBExerciseRepository` kept its own `readable` | Done | It calls `Row.readable(as:_:)`; S2's `DamagedExerciseRowTests` still pass. No mutant: the change is a refactor, and the log line is the only difference a mutant could make. |
| Review N7: `SQL.count` summed the rows of a `COUNT` | Done | `Int.fetchOne(…) ?? 0`, with the comment that the `0` is never used. That line's `?? 0` is now one of the three uncovered lines. |
| Tester S3-N1: an unreadable workout takes a place of the limit | Documented | Not small: `recent` would have to read past its limit until it has enough readable workouts, which is no longer one indexed `LIMIT` query. It is on F13's input 3, and the tester's "(documents)" test stays as it is. |
| Tester S3-N3: `SUM(reps)` can overflow across workouts | Documented | 2⁶³ reps at one weight make SQLite fail the query, loudly; unreachable by lifting. Pinned by the tester's test. |
| Tester S3-N4: `weeklyVolume` at 33 to 35 ms of 50 in the worst shape | Documented | 20,000 distinct weights; the time is the `Decimal` product per distinct weight. A real history has a few hundred. F20 measures a device. |

**Blocked: two changes that need a second edit to the tester's files.** The round allows one edit to a tester's
test (`wrongFake_isCaughtOrListed`). These two need others, so they are not in the tree. Both are written and
verified: applied together in place they pass all 334 host tests and the lint, and were then reverted. The
patch is `scratchpad/f05s3/fix1-blocked/blocked-changes.diff` (apply with `patch -p1` from the worktree root).
1. **The contract clause for S3-1** (decision 1). A clause "a record naming another workout is refused; nothing
   is stored" makes the contracts 22 clauses, and the tester's honest fake does not refuse such a record. So it
   needs a three-line guard in `Adversarial/HistoryModel+Repositories.swift` and `21` → `22` in
   `HistoryContractAdversarialTests.honestFake_keepsEveryClause`. Until then the refusal is pinned for GRDB only
   (the tester's test and mine), and F07's input line marks the clause as pending.
2. **Review N1, the `phase` filter on the lists** (decision 7). `AND phase = 'finished'` in `Selection.recent` and
   `Selection.ended(in:)` makes `HistoryReadAdversarialTests.foreignPhase_isListedButNotCounted` fail: it is the
   tester's "(documents)" pin of today's behaviour. The patch flips its two expectations and adds a line to
   `StatsQueriesTests.onlyLiveRowsOfFinishedWorkouts_count`.

**Not decided, and left exactly as they were:** which set kinds count toward the bests (S3-Q1, question 6) and a
workout's date being `ended_at` (S3-Q2, question 7). The tester's "(documents)" tests for them are untouched.

**Also changed:** `docs/testing-strategy.md` §2.2 now says the 95th percentile of 20 runs, as criterion 9 does.

**Code lines** (same method; it reproduces 662 at `f5ab3fb` against `a38ed78`): **687**, up 25 (target 500, split
threshold ~1,000). `WorkoutRows` 163 (+24: the foreign-record check, the text-id check, `Selection.stored` and
`setsUnderAnyExercise`), `GRDBStatsQueries` 163 (+1), `LoggedSetRecords` 100 (−3), `GRDBExerciseRepository` −5.
`LedgerDomain`: 0 code lines (comments only). Not counted: `LedgerTestSupport`, tests, docs.

**Gate after fix round 1 (2026-10-01, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0):**
- **Host:** `swift test --filter LedgerPersistenceTests`: 334 tests in 76 suites pass, the tester's four former
  failures among them.
- **Full gate, through the lock: green, exit 0** (381 s; log `scratchpad/f05s3/check-fix1.log`). 17/17 PR targets
  on iOS (1,357 passed, 10 skipped by design) and 8/8 PR-Watch targets on watchOS (1,248 passed, 10 skipped).
  No new warning: the log has only the two "will never be executed" warnings of S1's and S2's adversarial
  tests.
- **Coverage:** LedgerPersistence **99.84 %** (1932/1935), LedgerDomain 99.05 %, LedgerDesign 97.20 %, overall
  98.67 %. The 3 lines: `GRDBStatsQueries`' `now: Date.init` default, the `?? 0` of `SQL.count`, and S2's
  `uniquingKeysWith:`.
- These notes were written after the gate. They are docs only.

**Orchestrator, 2026-10-01: the two held-back changes are applied.** The implementer stopped on two changes
that each need an edit to a tester's file beyond the one sanctioned test, and left them as a patch. Both follow
from this round's decisions, so the orchestrator applied the patch as written:
- decision 1's contract clause `foreignRecord` (22 clauses now), with the same refusal added to the tester's
  honest in-memory model and its clause count;
- review N1 / tester S3-N2: `recent` and `workouts(in:)` filter on `phase = 'finished'`, as the stats do, and
  the tester's "(documents)" pin `foreignPhase_isListedButNotCounted` now expects the row in neither list.

The tester audits both edits in the close-out round. The gate below ran on the tree with the patch applied.

### S3 fix round 2 (orchestrator, 2026-10-01): S3-5

The close-out round closed S3-1 to S3-4 and found **S3-5** (minor, foreign writer only): a workout or exercise
row whose id is its uuid in lowercase passed the text check, matched none of its uppercase children, and read as
an empty parent. The fix is the tester's, applied by the orchestrator: `WorkoutRows.requireTextID` also throws
`malformedColumn` when the text parses as a uuid but is not its `uuidString`, so such a row is damage like a
blob id (logged and left out, or thrown by the strict read). The same residue as S3-3 stays: until a write
repairs it, `sessionsCompleted` counts such a workout row and it takes a place of `recent`'s limit. The
tester's two tests (`HistoryCloseoutAdversarialTests.lowercase…`) pass unedited. Code lines: 687 → 691.

### S3 fix round 3 (Pete's decisions #25–#27)

Inputs: product decisions #25 to #27 (Pete, 2026-10-02) at `cd5d368`. The first pass did #25 and #27 and stopped
on #26, because #26 breaks tester tests beyond the one sanctioned "(documents)" test. The orchestrator then
sanctioned those edits within stated limits (2026-10-02), and the round was finished. HEAD and the branch never
moved: `git branch --show-current` printed `feat/F05-s3` at the start and the end of both passes.

**#25: working and added sets count toward bests. No code change; docs aligned.**
- F05 criterion 5 (`tasks/features/F05-persistence.md`) now says "done working and added sets", citing #25.
- F12's set-kinds line (`tasks/features/F12-library-history.md`) says working and added sets feed e1RM and best,
  and warm-ups and drop sets never count toward a best.
- Doc comments cite #25 instead of "open question 6": `StatsQueries` (`Repositories.swift`), `GRDBStatsQueries`
  and its `SQL.recordKinds`, and `StatsQueriesContract`.
- **Sanctioned tester edit:** `StatsQueriesAdversarialTests.kinds_countAsDocumented`. The title drops
  "(documents)" and cites #25, and the doc comment is reworded. Every assertion is unchanged.

**#27: records after an edit. Docs only; the build is the F05 follow-up.** The `updateSets` docs
(`GRDBWorkoutRepository` and `WorkoutRepository`) say the F05 follow-up re-checks the records inside the edit's
write, per #27. F13's "Inputs from F05" already hands this to the F05 follow-up.

**#26: a workout belongs to the day and week it started.**
- **Queries changed** (`ended_at` → `started_at`):
  - `recent(limit:)`: newest start first, then id (`WorkoutRows.Selection.recent`, and `Query.workouts`' order);
  - `workouts(in:)` (`Selection.started(in:)`, renamed from `ended(in:)`);
  - the "Last" line: which workout it reads, and its date;
  - `e1RMByWeek`: each workout's week and key;
  - `weeklyVolume` and `sessionsCompleted`: the range;
  - `recentlyLogged`: an exercise's latest workout.
- **`ended_at` still means the end** in `notFinished`, in elapsed time (`WorkoutState.elapsed`), and in the
  filter below. `personalRecords` orders by `achievedAt`, the record's own time, so it is unchanged.
- **A finished row with no end** (orchestrator decision, 2026-10-02) is foreign damage: `materialize` refuses a
  workout without one. The lists (`Selection.recent`, `.started(in:)`) and the stats (`SQL.doneSets`,
  `sessionsCompleted`, `personalRecords`) require `phase = 'finished' AND ended_at IS NOT NULL`. So such a row is
  listed nowhere and counted nowhere, and the "Last" line skips it.
- **Migration `v002_workoutStartedIndex`** creates `idx_workout_started ON workout(started_at DESC, id)`.
  - **Deviation from the brief's `(started_at)`, on purpose.** With `(started_at)` alone, `recent`'s selection
    (`ORDER BY started_at DESC, id LIMIT ?`) still scans `workout` and sorts it, as the old `ended_at` version did.
    `(started_at DESC, id)` is that order, so `recent` reads straight from the index and stops at its limit.
    Ranges still search it.
  - `idx_workout_ended` (v001) stays, frozen. No query uses it now (`QueryPlanTests` pins that).
  - `Fixtures/schema-v002.sql` is new: v001's file plus the one index line.
  - `SchemaTests` now checks each migration's schema against its fixture
    (`migrator.migrate(_:upTo:)`), a new database against the latest, and the migration list (v001, v002).
  - The test-only migration in `MigrationCompatibilityTests` is now `v003_testOnly`, so the v001 fixture migrates
    through the real v002, then v003.
- **Query plans** (`QueryPlanTests`, all 7 changed queries; no `ANALYZE`, as in the app). Each statement the call
  runs is traced and passed to `EXPLAIN QUERY PLAN`. Each must reach the workouts through its index, scan no
  history table bare, and never touch `idx_workout_ended`:

  | Query | Entry |
  |---|---|
  | `recent` | `SCAN workout USING INDEX idx_workout_started` (the index order, stopped at the limit) |
  | `workouts(in:)`, `weeklyVolume`, `sessionsCompleted` | `SEARCH workout USING INDEX idx_workout_started (started_at>? AND started_at<?)` |
  | `lastPerformance`, `e1RMByWeek` | `SEARCH workout_exercise USING INDEX idx_wex_exercise_workout (exercise_id=?)` |
  | `recentlyLogged` | `SCAN workout_exercise USING INDEX idx_wex_exercise_workout` (every exercise row, by design) |

  The children follow by `idx_wex_workout`, `idx_logged_set_wex` and the primary key. With `(started_at)` alone
  the `recent` pin fails (mutant I1).
- **Late-workout pins** (`WorkoutDateTests`):
  - Tuesday 23:30 → Wednesday 00:40 is Tuesday's: its day range, `sessionsCompleted`, `weeklyVolume`, the "Last"
    line's date, and the list order beside a workout begun after it and ended before it.
  - Sunday 23:30 → Monday 00:40 with weeks from Monday, and Saturday 23:30 → Sunday 00:40 with weeks from Sunday,
    are last week's: `workouts(in:)`, `sessionsCompleted`, `weeklyVolume` and `e1RMByWeek`.
  - `StatsQueriesTests.finishedRowWithNoEnd_countsNowhere`.
- **Contracts, so a fake that dates by the end fails.**
  - `newestFirst`: a long workout started before the newest but ended after it.
  - `lastPerformance`: a long workout started earlier and ended later.
  - `e1RMByWeek`: last week's best began at 23:30 on Sunday, with its bench sets ticked after midnight. It also
    keeps catching dating by tick.
  - `weeklyVolume` and `sessions`: a Sunday-night workout that ends on Monday is last week's.
  - Every clause's fixtures now place a workout's **start** on the edge it tests (`WorkoutRepositoryContract.ending(startedAt:minutes:)`).
  - The tester's model now has a `.datedByEnd` fault, which the `newestFirst` clause catches. All 25 faults are
    caught, and the honest model keeps all 21 clauses.
- **Sanctioned tester edits for #26** (orchestrator, 2026-10-02). Each changes only what #26 or the real v002
  changes, and every other assertion is kept:
  - `HistoryReadAdversarialTests.rangesAndLimits_atTheirEdges`: workout *i* now **starts** at day *i* (it ends 45
    minutes later), so `:41`, `:43` and `:53` test the same edges by the start. No assertion changed.
  - `HistoryReadAdversarialTests.foreignPhase_isListedButNotCounted`, second half: a finished row with no end is
    now listed nowhere, counted nowhere, and the "Last" line skips it. `recent == []` replaces the listed `[nil]`,
    `lastPerformance == nil` replaces the `malformedColumn` throw, and `sessionsCompleted` and `weeklyVolume` are
    checked too. The title and doc comment say so.
  - `StatsWeeksAdversarialTests`:
    - `session(_:at:minutes:)` now takes the start (the end is `minutes` later), so every case puts its start on
      the edge it tests: the clock-change offsets (`:51`, 6 zones), the week before (`:107`) and the week-start
      grid. In `everyWeekStart_groupsByItsOwnWeeks`, `inWeek` filters on `startedAt`.
    - `midnightCrossing_countsForTheWeekItEndedIn` is now `midnightCrossing_countsForTheWeekItStartedIn`, titled
      with #26. A workout from Sunday 23:30 to Monday 00:40, one set ticked on Monday, is last week's whole:
      volume, sessions, `workouts(in:)` and the e1RM key (2026-W37).
  - `StatsQueriesAdversarialTests.lastPerformance_tieOfWorkouts`: the expected line's date is the start (45 minutes
    before the end); "ended together" is now "started together" in the title.
  - `WorkoutValuesAdversarialTests.extremeDates_roundTripAndTrapNoQuery`: the extreme date is now the **start**,
    and its mirror the end, so both columns still hold every extreme. The bit-for-bit check reads `startedAt`.
  - The oracle. `HistoryModel.date(_:)` dates by the start, and `.datedByStart` becomes `.datedByEnd`.
    `HistoryModel+Stats` reads the "Last" line's date and each workout's week through `date(_:)`.
    `HistoryCloseoutAdversarialTests.catchingClause` takes the renamed key, mapped to the same clause.
  - `HistoryScript` (the model test's fixture). `endDate()` is now `startDate()`, and the chosen instant is the
    start (the end is `minutes` later), so the model test's week-edge instants still fall on the edges.
    Without it, the nightly `The model test bites` stopped catching `.closedRanges`. Only the fixture changed; no
    assertion.
  - Real v002:
    - `SchemaAdversarialTests.migrateAgain_changesNothing` and
      `FileDatabaseAdversarialTests.unusualPath_opensAndReopens` expect the applied list (v001, v002) instead of
      one row.
    - `MigrationFixtureAdversarialTests.fixtureSchema_equalsAFreshDatabase` migrates the v001 fixture before
      comparing it with a new database.
    - `migratingTheFixture_changesNoRow` expects v001 alone before, and every migration completed after
      `migrate` and after `open`.
  - **No tester assertion changed beyond these limits.**
- **Mutants** (host, one at a time, file restored after each; script and results in scratchpad
  `f05s3/fix3-mut/`). All 16 were killed:
  - each of the nine queries dated by the end again (`recent`'s selection, the read order, `workouts(in:)`, the
    Last line's choice and its date, `e1RMByWeek`, `weeklyVolume`, `sessionsCompleted`, `recentlyLogged`);
  - each of the five no-end filters removed;
  - v002 back to `(started_at)` alone.

  The `personalRecords` no-end filter survived the first run and got
  `StatsQueriesTests.finishedRowWithNoEnd_countsNowhere`.
- **Criterion 9, under the lock** (`Nightly` and `Nightly-Watch`, `StatsQueriesPerformanceTests`; log
  `scratchpad/f05s3/round3/perf.log`): both pass. The worst p95 is `recentlyLogged` at 6.9 ms on the iPhone and
  6.7 ms on the watch, as before the change.
  - The tester's worst-case timing (`StatsWorstCaseAdversarialTests`, nightly lane, host) failed twice while the
    Mac's load average was about 20 (other worktrees' gates), and passed three times alone.
  - Its tight query is `weeklyVolume` over 20,000 distinct weights (33 to 35 ms of 50 in round 1, S3-N4). The
    cost there is the `Decimal` product per weight, which #26 does not touch.
- **Code lines** (same method; vs `a38ed78`): **701**, up 5 from 696 at `cd5d368` (+25, −20).
- **Gate** (2026-10-02, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0):
  - `scripts/check.sh --fast` OK on the host: `LedgerPersistenceTests` 349, `LedgerDomainTests` 762.
  - **Full gate, through the lock: green, exit 0** (384 s; log `scratchpad/f05s3/check-fix3.log`). 17/17 PR
    targets on iOS (1,372 passed, 10 skipped by design) and 8/8 PR-Watch targets on watchOS (1,263 passed, 10
    skipped).
  - No new warning: only S1's adversarial `PayloadVersionAdversarialTests.swift:29` "will never be executed",
    with xcbeautify's "exit code 0" lines beside its compile batch, as in earlier gates.
  - **Coverage:** LedgerPersistence **99.84 %** (1955/1958), LedgerDomain 99.05 %, LedgerDesign 97.20 %, overall
    98.68 %.
  - These notes were finished after the gate; docs only.

## Follow-up: records (decision #27)

On `feat/F05-records`, from main `efe0691` (S1–S3 merged). Product decision #27 (Pete, 2026-10-02): a corrected
typo must never leave a false record. HEAD and the branch never moved: `git branch --show-current` printed
`feat/F05-records` at the start and the end. No migration changed and no schema change was needed:
`personal_record`, `pr_count`, `idx_wex_exercise_workout` and `idx_pr_workout` are v001's.

### The invariant, and how each write keeps it

> After every write, the live `personal_record` rows and each workout's `pr_count` equal
> `PersonalRecords.detect` replayed over the live finished workouts in history's order (by start, then id;
> decision #26), each workout judged against the bests as they stood **before** it, with `achievedAt` the
> workout's start.

A write changes one workout, so only the records of the exercises it touched, in that workout and the ones after
it, can change. Each write computes that scope before it writes, writes its rows, then re-detects the scope
(`RecordReplay.redetect`), all in its own write transaction:

| Write | Scope: exercises | Scope: from |
|---|---|---|
| `materialize` (new, rebuild, revival, a late workout landing before stored ones) | the exercises of its live rows and live records before the write, and of the new state | the earlier of its stored place (if live) and its new place |
| `updateSets` | the edited row's exercise only (the others keep their sets) | the workout's place |
| `delete(id:)` | the exercises of its live rows and records | its place (its own records go with the soft delete) |

`redetect`:
1. **Bests before the start**: one aggregate query over the exercises' record sets of the workouts before it
   (`GRDBStatsQueries.bests(for:before:in:)`, also behind the public query below).
2. **The walk**: one query, in history's order, of each later workout's record sets of those exercises, grouped
   per workout, exercise and rep count (the heaviest weight and the best stored `e1rm_e7g`). Each workout's tally
   of an exercise is judged by `PersonalRecords.found` against the running bests (never for a deload, whose sets
   still raise the bests), then raises them. Only what decision #3 compares is read.
3. **The diff**: the found records against the live stored records of those exercises in the live finished
   workouts from the start on (`SyncedRecord.write`): unchanged rows keep their stamps, a changed value updates
   its own row, a lost record is soft-deleted.
4. **The counts**: `pr_count` of the written workout and of every workout whose records were found or stored in
   the scope, set to its live records, in one `UPDATE`, only where it changed (a no-op write runs no `UPDATE`).

Statements run in one order for one history (ids sorted, rows ordered), and the record rows are a function of the
history, whatever order the workouts were stored in (`RecordReplayTests.sameHistory_sameRows_sameStatements`).

### Decisions and deviations

1. **Records are no longer given.** `WorkoutRepository.materialize(_:summary:prs:slotUpdates:)` is now
   `materialize(_:slotUpdates:)`: `prs` went because the store computes them, and `summary` because it was
   never stored (S3 open question 1). So S3-1's refusal of a record naming another workout went too (it cannot
   happen), with its contract clause and the tests of it (below).
2. **`achievedAt` is the workout's start** (orchestrator brief: "your call, say why"). Records are a function of
   history, so `achievedAt` must be one too; `now` at finish no longer exists for a rebuild or an edit. The start
   is the workout's date everywhere else (decision #26): a record of a session begun at 11:30 pm is that day's,
   in History and in the PR list alike, and `personalRecords`' newest-first order is the replay order reversed.
   The end would put such a record on the next day. (Open question 1.)
3. **`personalRecords` ties.** Records of workouts that started at the same instant now list by workout id (as
   `recent`), then the estimate first; before, the second key was the kind and then the derived row id, which
   is arbitrary. Since `achievedAt` is the start, such ties are now ordinary, so the order had to be total and
   meaningful. Protocol doc updated.
4. **Record row ids** are the version-5 UUID of (workout, exercise, kind), not of the record's place in the
   workout's list. `detect` finds at most one record of each kind per exercise and workout, so this is unique; a
   changed value updates its own row, and the replay can rewrite one exercise's records without knowing the
   workout's other exercises. Rows written by S3's code (the v001 fixture) are replaced when their workout is
   next written; the table is local-only.
5. **Domain additions.** `PersonalRecords` gained:
   - `Bests` (per exercise: best estimate, best weight at each rep count; `bestSet(of:)`; `include(_:)`, which
     folds a workout in) and `detect(workout:against:now:)`: what the query returns and F10 passes to `detect`;
   - `Tally<Value>`, `Found<Value>` and `found(_:over:)`: decision #3's rule for one exercise of one workout, over
     any exactly ordered weight. `detect` calls it with `Weight`s; the replay calls it with whole 10⁻⁷ g, which
     order the same (ADR-007). One rule, two units: the replay never does decimal arithmetic. `detect`'s
     behaviour is unchanged (its 26 tests, F02's and the tester's, pass unedited).
6. **The new query: `StatsQueries.bests(before workout: WorkoutState, for exerciseIDs: Set<ExerciseID>) async
   throws -> PersonalRecords.Bests`.**
   - *Before a workout, not before a date, and not "excluding a workout"*: history's order is (start, id), so a
     date alone cannot place two workouts that started together, and "every other workout" would count later
     ones (an ADR-004 rebuild of an old workout would then be judged against its successors).
   - *A `WorkoutState`*: F10 has the live workout, which is not stored; its start and id are its place. A
     stored workout is excluded by the same rule, so the same call serves a rebuild.
   - *For given exercises*: the workout's own, or one exercise after a swap.
   - *Returns `Bests`*, exactly `detect`'s two inputs (and `bestSet(of:)`, derived from the weights).
   - It counts `.working` and `.added` done sets only (#25), deload workouts included, through
     `idx_wex_exercise_workout`.
7. **Strict reads.** The walk and the bests read history as the stats queries do: a damaged value that an
   aggregate returns (a text weight, reps below 1, a malformed exercise id) throws `malformedColumn` by name, and
   the write stores nothing. Never judging a record against history it cannot read is #27's point; it only
   happens with foreign damage, and materialising the damaged workout repairs it
   (`RecordReplayTests.damagedLaterWorkout_failsTheReplay`). The scope itself is read leniently, so a write can
   still repair a damaged row of its own workout. (Open question 2.)
8. **Performance work in shared code.** `SyncedRecord.write` now builds its upsert statement once per write
   instead of once per row (records of one type share their columns): about 3 ms of the worst case. No behaviour
   change; every repository's suites pass.
9. **Not changed:** migrations, `project.pbxproj`, `Package.swift`, test plans, ADRs, `docs/`.

### Protocol changes, and whom they affect

```swift
// WorkoutRepository
- func materialize(_ workout: WorkoutState, summary: WorkoutSummary, prs: [PersonalRecord], slotUpdates: [Slot]) async throws
+ func materialize(_ workout: WorkoutState, slotUpdates: [Slot]) async throws
// StatsQueries
+ func bests(before workout: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests
```
Docs: `WorkoutRepository` states the invariant; `updateSets` and `delete` say they re-detect; `personalRecords`
states `achievedAt` and the tie order. `WorkoutEngine.summary`'s doc says where its `prs` come from.

- **F07**: fakes implement both; "Inputs from F05" rewritten (13 + 10 clauses, the invariant, the simplest
  honest fake).
- **F10**: no longer detects records for storage; for the live "PR!" moment it calls `bests(before:for:)` and
  `detect(workout:against:now:)`. Inputs 1–4 and 8 rewritten; input 7's "ended" corrected to "started" (#26).
- **F13**: criterion 4 holds through the repository; input 1 rewritten, input 2 notes `pr_count` is now right,
  input 4's "ended" corrected (#26).
- **F17**: a rebuild materialises the state alone; M4 sync that writes rows without `materialize` must re-detect.

### Tests, and the tester-owned files this PR edits

**New (mine):**
- `RecordReplayTests` (7): counts through the typo, fixed and undone; a revived workout's count; a workout moved
  later; an exercise dropped by a rebuild; an edit reads and writes only its exercise from its workout on; one
  history, one set of rows and statements; strict reads of a damaged later workout.
- `PersonalRecordsBestsTests` (3, Domain): `include`, `bestSet(of:)`, and `detect(against:)` replaying a history.
- `Performance/RecordReplayPerformanceTests` (nightly lane): the worst case, below.
- `QueryPlanTests`: `bests(before:for:)` and `updateSets`' replay reach the history through
  `idx_wex_exercise_workout` and scan no history table bare.
- Contract (`LedgerTestSupport`, `StatsQueriesContract+Records.swift`): clauses `personalRecords` (rewritten: six
  workouts stored newest first; warm-up, drop, deload, a tie of starts by id, a delete), `bestsBefore` (new) and
  `recordsFollowEdits` (new, replaces `foreignRecord`: the 2,250 lb typo through `updateSets`, `delete` and a
  rebuild). `followsEdits` now expects the records to follow the edit. 23 clauses (13 + 10).

**My S3 tests updated**: `WorkoutRepositoryTests.Scenario` stores an earlier workout (bench at 180 lb) first so
the contract workout still sets two records, now detected; counts and stamps follow; `recordIDs_areDerived`
checks the new derivation and that a changed value keeps its row; `recordOfAnotherWorkout_isRefused` deleted
(S3-1 is moot); `DamagedWorkoutRowTests` and `StatsQueriesTests` store the earlier workout first.

**Tester-owned edits.** The brief sanctions updating every caller of the old `materialize`; where a test's
subject was a given record, its expectations had to become detected ones. Each is listed so the tester can audit:
- `S3Kit` (helper): `record(_:_:over:in:)` takes the previous best and uses the start; new `baseline` and
  `mixedRecords(of:)` (a workout before every `mixed` one, and the two records a mixed workout sets over it).
  `S3Database.Stack.materialize(_:slots:)` lost `prs`.
- `HistoryModel` (the oracle): records are no longer stored as given but replayed from scratch after every write
  with `PersonalRecords.Bests` (a different algorithm from the store's incremental one); `bests(before:for:)`
  added. Faults: `recordsByWorkoutDate` and `recordsInGivenOrder` removed (no longer expressible: records are
  computed, `achievedAt` is the workout's date, and `detect` fixes the order); `editDropsRecords` kept (an edit
  clears the workout's records); four added: `recordsAgainstAllTime`, `recordsAgainstOtherWorkouts`,
  `recordsSkipLaterWorkouts`, `bestsBeforeIncludeIt`. `HistoryCloseoutAdversarialTests.catchingClause` maps
  them; `HistoryContractAdversarialTests` counts 23 clauses. Every fault breaks its own clause, and the honest
  model keeps all 23.
- `HistoryScript` no longer makes records; `HistoryModelAdversarialTests` also compares `bests(before:for:)`
  before every stored workout and an unstored one (without it the nightly "model test bites" missed
  `bestsBeforeIncludeIt`).
- Rewritten for detected records (subject kept): `WorkoutEditAdversarialTests.edit_leavesRecordsStale` (the S3-Q3
  "(documents)" pin of the very gap this closes) is now `edit_detectsRecordsAgain` (the typo leaves no record; an
  earlier edit gives a later workout its records); `StatsQueriesAdversarialTests.personalRecords_orderIsDeterministic`
  (three workouts that start together, each setting records, in six store orders);
  `WorkoutFixCloseoutAdversarialTests.damagedRecordRows_areRepaired`, `delete_isIdempotent_andClearsLeftovers`,
  `repairs_touchOnlyTheirOwnWorkout` (store `S3Kit.baseline` first); `WorkoutAtomicityAdversarialTests`
  (baseline first; one changed record; the set edit also fails on a record `UPDATE`);
  `WorkoutLifecycleAdversarialTests.materialize_isIdempotent`; `WorkoutValuesAdversarialTests.extremeDates…`
  (a twin sets records achieved at the extreme date); `HistoryReadAdversarialTests.observation_emitsOnlyOnChange`
  (a baseline outside the list changes only records: no value); `MigrationFixtureAdversarialTests.fixtureWorkouts_rematerialiseAsNoOps`
  (every row but the derived records stays; the fixture's given records are detected again).
- Deleted (their subject, a given record naming another workout, no longer exists):
  `WorkoutFixCloseoutAdversarialTests.foreignRecord_isRefusedByName` (6 cases),
  `WorkoutIdentityAdversarialTests.recordOfAnotherWorkout_doesNotReplaceItsRecords` and
  `recordOfAnUnknownWorkout_isRefused`, replaced by `records_nameTheirWorkout_andAreCounted` (its `pr_count`
  check kept).
- Unused record arguments dropped: `WorkoutStartDateAdversarialTests`, `StatsQueriesAdversarialTests.onlyDeletedWorkouts_readAsEmpty`,
  `WorkoutLifecycleAdversarialTests.rematerializeAfterDelete…`, `StatsWeeksAdversarialTests`, the perf seeders.
- **Sanctioned edit 1** (orchestrator): `StatsWorstCaseAdversarialTests` now has about 450 distinct weights
  (every 2.5 lb, up to 1,122.5 lb) instead of 20,000; still 20,000 sets of one lift in one week, and every workout
  after the first sets two records (399 × 2, asserted), now detected. `weeklyVolume` there: 3.9 ms (was 35).
- **Sanctioned edit 2** (orchestrator): `HistoryReadAdversarialTests.foreignPhase_isListedButNotCounted` is now
  `foreignPhase_isListedNowhere_andCountedNowhere`. Name only.

### Criteria → tests

| What #27 and the brief ask | Tests |
|---|---|
| A corrected typo leaves no false record; a later real lift becomes one | clause `recordsFollowEdits`; `RecordReplayTests.recordCounts_followEveryWrite`; `WorkoutEditAdversarialTests.edit_detectsRecordsAgain` |
| `materialize` re-detects from its place on, a late workout before stored ones included | clause `personalRecords` (stored newest first); `HistoryModelAdversarialTests` (random histories against a from-scratch replay) |
| `updateSets` and `delete` re-detect forward | clauses `recordsFollowEdits`, `followsEdits`, `personalRecords` (delete); `RecordReplayTests` |
| Judged against the bests **before** the workout, by start then id | clauses `personalRecords` (twins), `bestsBefore`; faults `recordsAgainstAllTime`, `recordsAgainstOtherWorkouts`, `bestsBeforeIncludeIt` |
| Scope: old place and old exercises | `RecordReplayTests.movedWorkout_redetectsFromItsOldPlace`, `droppedExercise_redetectsItsLaterWorkouts` |
| Bounded: only the touched exercise, from the workout on, indexed | `RecordReplayTests.edit_touchesOnlyItsExercise_fromItsWorkoutOn`; `QueryPlanTests` (2 new) |
| `pr_count` always equals the live records | `RecordReplayTests` (3), `WorkoutIdentityAdversarialTests.records_nameTheirWorkout_andAreCounted`, `WorkoutFixCloseoutAdversarialTests.damagedRecordRows_areRepaired` |
| Same history, same rows, same statements | `RecordReplayTests.sameHistory_sameRows_sameStatements`; `StatsQueriesAdversarialTests.personalRecords_orderIsDeterministic` |
| #25: working and added count, warm-ups and drops never | clauses `personalRecords`, `bestsBefore`; `PersonalRecordsBestsTests.include_countsRecordSetsOnly` |
| One transaction: a failure writes nothing | `WorkoutAtomicityAdversarialTests` (record `INSERT`/`UPDATE` in every write), `RecordReplayTests.damagedLaterWorkout_failsTheReplay` |
| The worst case within budget | `RecordReplayPerformanceTests` (nightly), below |

### Mutants

Host, one at a time, the file restored after each; runner and results in scratchpad `f05rec/mut/`
(`run.py`, `results-round1.txt`, `progress2.log`). A mutant is killed when at least one named test fails.

27 mutants, all killed (named: the tests that failed, or how many did):

| Mutant | Killed by |
|---|---|
| `updateSets` does not re-detect | clause `recordsFollowEdits`, `RecordReplayTests` (11 tests) |
| the walk covers only the changed workout (no forward walk) | `recordsFollowEdits`, `droppedExercise_…`, the fixture test (10) |
| the bests "before" include the workout itself | 32 tests, clauses `bestsBefore`, `personalRecords` |
| the bests are all-time | 32 tests |
| `materialize`'s scope ignores the old place | `movedWorkout_redetectsFromItsOldPlace`; the model test |
| `materialize`'s scope ignores the stored exercises | `droppedExercise_redetectsItsLaterWorkouts` (3) |
| `delete` does not re-detect | the model test; clauses `personalRecords`, `recordsFollowEdits` |
| the written workout is not recounted | `revivedWorkout_countsItsRecordsAgain` |
| no `pr_count` at all | 9 tests |
| `achievedAt` is not the start | 14 tests |
| a deload sets records | clause `personalRecords` |
| a deload's sets do not raise the bests | clause `personalRecords` |
| the walk counts warm-ups and drops | clause `personalRecords`; the model test |
| records of one instant tie by kind, not workout | `personalRecords_orderIsDeterministic` |
| a tie is a record (`>=` in `found`) | 18 tests, Domain and persistence |
| `Bests.include` counts warm-ups | `PersonalRecordsBestsTests.include_countsRecordSetsOnly`; the honest-model test |
| a record's id ignores its kind | 48 tests |
| groups split by workout only (exercises merged) | 11 tests |
| groups keyed by start, not workout id | `personalRecords_orderIsDeterministic`; the model test |
| a group keeps the previous group's tally | 15 tests |
| an edit's scope covers every exercise | `edit_touchesOnlyItsExercise_fromItsWorkoutOn` |
| the weight record's ceiling ignores more reps | Domain `PersonalRecordsTests` (5) |
| `Tally.add(_:)` drops the estimate | 12 tests |
| stale stored records are not replaced | 14 tests |
| `delete` leaves its own records | `WorkoutAtomicityAdversarialTests`, `WorkoutFixCloseoutAdversarialTests` (4) |
| the weight read from the wrong column | 27 tests |
| reps below 1 clamped, not refused | `damagedLaterWorkout_failsTheReplay` |

Contract clauses against wrong fakes: the tester's model with each of the four new faults
(`recordsAgainstAllTime`, `recordsAgainstOtherWorkouts`, `recordsSkipLaterWorkouts`, `bestsBeforeIncludeIt`) breaks
its own clause (`HistoryCloseoutAdversarialTests.wrongFake_isCaughtByItsOwnClause`), and in the nightly lane the
model test bites for each of them. After the walk was restructured (the `Walk` type, reads by index), the
mutants that touch it were run again on the final code, and all were killed again.

### Worst case, timed

`RecordReplayPerformanceTests` (nightly lane; `.performance`, `.slow`). 400 workouts of one lift, 50 sets each
(20,000 sets), set *j* of workout *n* at 2.5 × (*n* + *j* + 1) lb for 1 + *j* % 12 reps, so every workout after
the first sets both records (798, asserted). Each timed run is `updateSets` on the **first** workout, alternately
writing a 2,250 lb typo into its first set (399 estimate records go) and fixing it (they come back): the replay
walks all 400 workouts and rewrites 399 records each time. Also timed: `bests(before:for:)` before a new
workout, and materialising that new workout (it replays only itself). 95th percentile of 20 runs after a
warm-up, against `PerformanceBudget.statsQuery` (50 ms), the budget the brief names.

| Timed | iPhone 17 simulator | Watch Series 12 simulator | Host (Debug) |
|---|--:|--:|--:|
| `updateSets` of the first of 400 workouts (the worst case) | 46.9 ms | 47.6 ms | 41–43 ms |
| `bests(before:for:)` before a new workout | 9.2 ms | 9.2 ms | 6.1 ms |
| materialising a new workout of the lift | 11.3 ms | 11.6 ms | 8.1 ms |

Both simulators under the lock (`Nightly` and `Nightly-Watch`, with `StatsQueriesPerformanceTests` and
`StatsWorstCaseAdversarialTests`, all passing; script `f05rec/perf.sh`, attachments `att-ios-v4`,
`att-watch-v4`). Criterion 9 is unchanged (worst p95 `recentlyLogged` 7.6 ms), and the worst-case stats test's
`weeklyVolume` is now 4.4 ms on the iPhone and 4.6 ms on the watch (was 33 to 35 ms).

**How it got there.** The first cut read the walked workouts whole (`WorkoutRows.fetch`) and ran `detect` on
them: 310 ms on the host. Then, each measured with a sampling profile: (1) the walk reads only per workout,
exercise and rep count the heaviest weight and best stored estimate, grouped in SQL, and compares whole
10⁻⁷ g through `PersonalRecords.found` (no decimal arithmetic): about 50 ms; (2) `found` finds the weight record
in one pass over the reps, from most to fewest: −10 ms; (3) record rows hold their columns as integers, and
`SyncedRecord.write` builds its upsert once per write, and the walk reads its columns by index: −8 ms. What is left is about a third SQLite (the walk's
`GROUP BY` over 20,000 rows) and two thirds the 399 rows written and the 798 compared.

### Code lines

Same method as S1 to S3 (non-blank Swift lines that are not whole-line `//` or `///` comments, SQL included,
product sources only; new files whole plus the diff's added lines; scratchpad `f05rec/count.sh`):
**461 lines added, 357 net**, under the 500 target.
- New: `Records/RecordReplay` 201.
- `LedgerDomain/Rules/PersonalRecords` +106 −35 (`Bests`, `Tally`, `Found`, `found`; `detect` now calls `found`);
  `Repositories` +2 −2 (the rest is doc comments).
- `Records/LoggedSetRecords` +71 −27 (`PersonalRecordRecord` over integer columns), `Stats/GRDBStatsQueries` +44 −1,
  `Records/SyncedRecord` +16 −11, `Repositories/GRDBWorkoutRepository` +13 −9, `Records/WorkoutRows` +7 −12,
  `Records/WorkoutRecords` +1 −7.
- Not counted: `LedgerTestSupport` (contract clauses), tests, docs.

### Gate and coverage

2026-10-02, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0.
- **Host:** `swift test --filter LedgerPersistenceTests` 360 tests in 83 suites, `LedgerDomainTests` 765 in 126,
  pass. Nightly lane on the host: the model tests (every seed, all 27 faults), the three timing suites, pass.
- **Full gate, through the lock: green, exit 0** (`scripts/check.sh`, 370 s; log `scratchpad/f05rec/check-2.log`).
  Format, lint, the package graph and pins, and the script tests: OK. **17/17** PR targets on iOS (1,385 passed,
  11 skipped by design: the timing suites, one more than before) and **8/8** PR-Watch targets (1,276 passed,
  11 skipped).
- Warnings: none new; the log has only S1's `PayloadVersionAdversarialTests.swift:29` "will never be executed".
- **Coverage:** LedgerPersistence **99.86 %** (2219/2222; threshold 90), LedgerDomain 99.08 % (1946/1964),
  LedgerDesign 97.20 %, overall 98.75 %. The 3 persistence lines are S3's (the `now: Date.init` defaults and the
  `?? 0` of `SQL.count`).
- These notes were written after the gate; docs only.

### Open questions for the orchestrator

1. **`achievedAt` is the workout's start** (decision 2). Recommendation: keep; it is the workout's date
   everywhere else (#26). The alternative, the end, puts a record of a late session on the next day.
2. **Strict reads in a write** (decision 7). A damaged value of the same exercise in the history a write
   replays (foreign damage only: a text weight, reps below 1) makes `materialize`, `updateSets` or `delete`
   throw `malformedColumn` and store nothing, so a finish can fail until the damaged workout is materialised
   again. Recommendation: keep (a record is never judged against unreadable history); F10 already keeps the log
   uncompacted when `materialize` throws. The alternative is to leave unreadable rows out of the bests, which
   can store a false record.
3. **Timing margin.** The worst case is under the budget on both simulators, but the watch's p95 (47.6 ms; the iPhone 46.9 ms) is
   close to 50 ms in a Debug build, as `StatsWorstCaseAdversarialTests` was before this PR's sanctioned edit. It
   is a nightly test, so a loaded Mac can fail it. Recommendation: accept for now and let F20 time a device in
   Release; if the nightly flakes, give writes their own budget in `PerformanceBudget` (an edit in History is a
   user action, not a frame) rather than shrink the shape.
4. **Records written before this PR** (the v001 fixture; no shipped database has workouts yet, F07 is not
   wired) keep their old row ids and caller-given values until their workout is next written, when they are
   detected again. Recommendation: nothing now. When M4 sync (F17) writes workout rows without `materialize`, it
   must call the replay from the earliest workout it wrote (F17 input written).
5. **Domain API added beyond the query**: `PersonalRecords.Bests`, `Tally`, `Found`, `found(_:over:)`,
   `detect(workout:against:now:)`. `found` is the one rule both units share. Recommendation: keep; F10 needs
   `Bests` and `detect(against:)`, and the replay needs `found`.
6. **Tester-owned edits** beyond the two sanctioned ones are all forced by the protocol change (listed above):
   two faults removed, four added, three tests deleted with the behaviour they pinned. Recommendation: the
   tester audits them in the adversarial round, as in S3 round 3.
7. **F13's badge** still has no `personalRecords(workoutID:)` (S3 open question, F13 input 2). Recommendation:
   F13 adds it if it wants `pr_count`-free reads; `pr_count` is now always right.

### Records fix round 1

Inputs: `test-findings.md` "# Follow-up: records — adversarial round 1" (R-1, R-Q1, R-Q2) and `review.md`
"# Follow-up: records review" (R-SF1, R-SF2, R-N1 to R-N3), at `5f9823e`, with the orchestrator's binding decisions.
HEAD and the branch never moved: `git branch --show-current` printed `feat/F05-records` at the start and the end.
Each change was checked with a mutant (undone, the named test failing, restored; host, one at a time; runner
`scratchpad/f05rec/mut/run.py`, results in `results.txt`).

**1. R-1: History writes get a budget of their own.**
- `docs/architecture.md` §15 has two new rows, and `PerformanceBudget` two constants:
  - `recordNewWorkout` (50 ms): recording a new workout at the end of history, its replay included, at 20,000
    sets;
  - `historyWrite` (250 ms): a History write that re-detects records (edit, delete, late or moved workout), at
    20,000 sets, 400 workouts and up to 5 lifts, p95 on a simulator, Debug.
- `RecordReplayPerformanceTests` now times three things, each against its own budget:
  - the typo fixed in the first workout (`historyWrite`);
  - `bests(before:for:)` (`statsQuery`);
  - 20 **new** workouts recorded at the end of history (`recordNewWorkout`). Before, the same workout was
    re-materialised; now this is exactly the finish path.
- Sanctioned edit: `RecordReplayWorstCaseAdversarialTests.worseShape_underBudget` now asserts `historyWrite`. Its
  title and doc say so; the shapes are unchanged.
- **The cheap win** (about 30 lines): records already stored as found are left out of the diff.
  - `PersonalRecordRecord.content` is one list of column values, used by both `encode(to:)` and
    `isStored(in:)`, so they cannot disagree.
  - The replay compares each found record with its stored row by index, and passes only the changed ones (and
    the stored rows they replace) to `SyncedRecord.write`.
  - Before, every record in scope was encoded and compared by column name; in a five-lift history that is
    about 4,000 rows for a write that changes ten.
  - No convergence or early-exit scheme was built.
  - Mutants: "every record counts as stored" and "a record is stored when its id is" each fail 15 tests.

| Write (20,000 sets, 400 workouts), p95 | Before, iPhone / watch / host | After, iPhone 17 sim | After, Watch S12 sim | After, host |
|---|--:|--:|--:|--:|
| One lift, the typo fixed in the first workout (implementer's) | 47.0 / 47.9 / 54 ms | 45.8 ms | 46.2 ms | 48 ms |
| One lift, a 12-rep typo: both records of 399 workouts flip | 55 / 57 / 59 ms | 58.1 ms | 58.4 ms | 59 ms |
| Five lifts, the first workout deleted from History | 110 / 114 / 117 ms | 63.9 ms | 64.5 ms | 61 ms |
| Five lifts, a forgotten session lands first and is deleted | 147 / 153 / 153 ms | 103.4 ms | 118.0 ms | 96 ms |
| Five lifts, the first rebuilt with a typo in each lift (3,990 records flip) | 203 / 213 / 197 ms | 218.3 ms | 220.9 ms | 199 ms |
| A new workout recorded at the end (`recordNewWorkout`) | (11–12 ms, a rebuild) | 19.1 ms | 19.3 ms | 14 ms |
| `bests(before:for:)` before a new workout | 9.2 ms | 9.2 ms | 9.4 ms | 6.6 ms |

- **Where the numbers come from.**
  - "Before" is the tester's round 1 on both simulators. The host column is measured on this machine with the
    filter undone and redone in one sitting.
  - "After" is the `Nightly` and `Nightly-Watch` plans under the lock, nothing else of mine running. Script
    `f05rec/perf.sh`; attachments `att-ios-r1` and `att-watch-r1`.
  - Every timing suite passed on both simulators: `RecordReplayPerformanceTests`,
    `RecordReplayWorstCaseAdversarialTests`, `StatsQueriesPerformanceTests` and `StatsWorstCaseAdversarialTests`.
    Criterion 9's worst stats p95 is `recentlyLogged`, 7.0 ms.
- **What the filter does not help.** A write whose records mostly change still pays for every row it writes. The
  five-lift rebuild is at 221 ms of 250 on the watch. Only an early exit or fewer rows written would lower it,
  and this round builds neither.

**2. R-Q1: skip and log.**
- **The walk** (`Records/RecordReplay+Walk.swift`, moved to its own file for the 300-line file limit) now reads
  a workout at a time.
  - It buffers each exercise's tally until the next workout begins. If any of the workout's rows, or its own
    columns, cannot be read, the whole workout is left out: judged for nothing, counted in no best, logged at
    error level, and added to `skipped`.
  - The diff then leaves the skipped workouts' stored records alone (`RecordReplay.redetect`), so they keep
    their rows until a write repairs the workout.
- **The bests before a write** (`GRDBStatsQueries.bests(for:before:in:)`) try the one aggregate query first. If
  it meets a damaged value, they walk the same history a workout at a time (`RecordReplay.walkedBests`) and
  leave the damaged one out.
- **Tests:**
  - `RecordReplayTests.damagedWorkout_isLeftOutOfTheReplay`:
    - the lifter's edit and a new workout go through;
    - the new one is judged against the readable history (over 190, not the damaged 210);
    - the damaged workout's record rows are unchanged, its squat too when a rebuild walks past its bench;
    - repairing it restores its records;
    - `reps = 0` is left out the same way.
  - `bestsOverDamage_leaveItOut_andNeverCountTheWorkout` covers the walked bests.
  - Sanctioned edit: the tester's "(documents)" pin is now
    `RecordReplayEdgeAdversarialTests.damagedHistory_isLeftOutOfWritesOfItsLift`, retitled with the decision.
    It asserts the writes go through, and keeps the list, `workout(id:)` throws and delete-by-id checks.
- **Mutants:**
  - skipped workouts lose their stored records;
  - a failed workout is judged anyway;
  - no fallback for damaged bests;
  - the fallback counts the workout itself;
  - the walk excludes nothing.

  All are killed.

**3. R-SF2 = R-Q2: a recount does not stamp `updated_at`.**
- `RecordReplay.writeCounts` sets `pr_count` alone, and only where it changed.
- `RecordReplayTests.recount_stampsNoWorkoutRow`: fixing a typo in the first of five workouts changes the counts
  of the four after it and none of their `updated_at`.
- Mutant (stamp again): 2 tests fail.
- `F28-icloud-sync.md` input: `pr_count` is derived locally, must not be synced or merged, and is rebuilt by
  replay after a sync.

**4. R-SF1: `bests(before:for:)` never counts the workout itself, not even a stored copy that started earlier.**
- `GRDBStatsQueries.bests(for:before:in:)` adds `AND workout.id IS NOT ?`; the walked fallback excludes the same
  id.
- The protocol doc (`Repositories.swift`) and F10 input 3 say so.
- Contract `bestsBefore` gains "never its own earlier copy": the twin asked about a day later than it is stored.
  Mutant: the GRDB contract clause fails.
- **Forced edit to the tester's `HistoryModel+Stats.swift`**: the honest model's `bests(before:for:)` excludes
  its own stored copy, and the `.bestsBeforeIncludeIt` fault counts that copy when it is at or before the
  place. Without it the honest model broke the strengthened clause. Every fault is still caught by its own
  clause.

**5. Nits.**
- **R-N1**: F10 input 3 says to detect with `now: state.startedAt`. The doc comments of `WorkoutEngine.summary`
  (F04's file, comment only) and of `StatsQueries.bests` say why: the store stamps `achievedAt` with the start.
- **R-N2**: contract `recordsFollowEdits` ends with `rebuildsMoveOrDrop`. A rebuild moves the typo workout after
  the last one, then one drops its bench. The mutants "scope ignores the old place" and "scope ignores the
  stored exercises" are now killed by the GRDB contract clause too, so a fake that replays incrementally is
  caught.
- **R-N3**: F12 (a new "Inputs from F05" section) and F13 input 1 say that a deload sets no record but can be
  the "previous" a later record beats.

**6. `ProtocolsAdversarialTests`** (`LedgerDomainTests/Adversarial`, the F02/F04 tester's suite) was edited by
the `prs:` removal in the first pass. This edit was forced and changes no assertion:
- its `BriefWorkoutRepository` stub now declares `materialize(_:slotUpdates:)`;
- its `BriefStatsQueries` stub gained `bests(before:for:)`, returning `PersonalRecords.Bests()`.

**Code lines** (S3 method, against `efe0691`): **547 added, 438 net** for the whole PR. That is over the 500
target, under the ~700 stop line and the ~1,000 split line.
- This round alone: +180 −99 (net +81). Of that, 113 lines are the new `RecordReplay+Walk.swift`, about 70 of
  which moved out of `RecordReplay.swift` for the 300-line file limit.
- The rest: the skip-and-log buffering (about 35), the unchanged-record filter (about 30), the bests fallback (about 12).
- The split considered: the Domain and replay core in one PR, and the round-1 fixes in another. Not taken:
  every fix changes code that is not merged yet, and a stacked PR is ruled out.

**Gate**: see "Gate (fix round 1)" below.

**Gate (fix round 1)**, 2026-10-03, Xcode 27.0, iPhone 17 and Apple Watch Series 12 (46mm) on 27.0:
- **Host:** `LedgerPersistenceTests` 370 tests in 86 suites pass; `LedgerDomainTests` 765 pass. Nightly lane on
  the host: the model, oracle and contract-fault suites pass.
- **Timing, both simulators, under the lock:** every timing suite passes (table above).
- **Full gate, through the lock: green, exit 0** (`scripts/check.sh`, 379 s; log `scratchpad/f05rec/check-r1b.log`).
  - **17/17** PR targets on iOS: 1,394 passed, 12 skipped by design.
  - **8/8** PR-Watch targets: 1,285 passed, 12 skipped.
- Warnings: none new. The only one is S1's `PayloadVersionAdversarialTests.swift:29` "will never be executed".
- **Coverage:** LedgerPersistence **99.69 %** (2290/2297), LedgerDomain 99.08 % (1946/1964), LedgerDesign
  97.20 %, overall 98.70 %.
