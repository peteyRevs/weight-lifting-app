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
| F04 "Inputs" 1–4 | `WorkoutEventStoreTests.contract_clauseHolds` (all 12 clauses), `append_writesTheDocumentedColumns`, `append_comparesDecodedEnvelopes_notBytes`, `uniqueKey_refusesASecondRow` |
| ADR-007 storage | `ColumnCodecTests` (examples, refusals, seeded round-trips of weights, volumes and `REAL` dates) |
| Settings | `SettingsRepositoryTests` (defaults, round trip in one row, `observe` emissions, unreadable row) |

### Code lines

Measured with a script that counts non-blank Swift lines that are not whole-line `//`/`///` comments
(SQL inside the migration string counts as code): `LedgerPersistence` sources **495** (of which
`Migrations.swift` 203, one column per line), `Package.swift` +2, `coverage-thresholds.json` ±1, minus
the 3-line placeholder: about **495** in all, under the 500 target. The plan estimated ~390; the gap is the
SQL layout (~95 estimated). Tests and `LedgerTestSupport`: 757 lines, not counted.

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
