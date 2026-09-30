# F05 Persistence — review

## Slice S1

Reviewer pass on `feat/F05-persistence` at `2bcb442` (main merged in), diff `git diff main...HEAD`
(45 files; about 580 lines of code against the 500 target, split considered and named in the notes, so it
complies with engineering-standards §10). Scope: schema v001, the exact column codecs, `GRDBWorkoutEventStore`,
`GRDBSettingsRepository`, the `ValueObservation` bridge, the contract moved to `LedgerTestSupport`, and the
fix-round-1 decisions (versioned payloads, tolerant `Settings` decoding, `unreadableCount(for:)`).

### What I ran

- `/code-review high` on the diff. It raised 10 candidates. Each one is ranked below or answered under "Considered and not raised".
- `swift test --package-path LedgerKit` (in a private scratch build directory, so it could not disturb the tester's
  gate), filtered to `LedgerPersistenceTests`, `WorkoutEventStoreContractTests`, `SettingsTests` and
  `Round4StoreAdversarialTests`: **74 persistence tests pass on the macOS host** (the protection test
  included; the nightly timing suite is skipped by design), and the 13 contract clauses pass on the in-memory store.
- `scripts/check-package-graph.sh`: matches `package-graph.expected.txt`.
- Schema: I extracted the SQL from `Migrations.swift`, ran it in `sqlite3` 3.54, and dumped `sqlite_master` with
  `SchemaTests.dump`'s query. The dump is **byte-identical** to `Fixtures/schema-v001.sql`.
- `EXPLAIN QUERY PLAN` on every event-store statement: all of them use `uidx_event_key`. Only `highestSeq` also
  sorts in a temporary B-tree (N6).
- Weight codec: a probe with `Decimal(string:)`, non-compact significands, `×`/`+` results, `1e20` and
  `Int64.max + 1` units. `Decimal(sign:exponent:significand:)` compacts, and every out-of-range or fractional count
  gives `nil`, which throws. Nothing rounds.

### Blocking

None.

### Should fix

**SF1. Nothing pins what "payload version 1" is, so the version number cannot detect the change it exists for.**
`LedgerKit/Sources/LedgerPersistence/Events/EnvelopeCodec.swift:18,33-50`,
`LedgerKit/Sources/LedgerPersistence/Repositories/GRDBSettingsRepository.swift:61-78`.
Version 1 decodes with whatever `EventEnvelope`/`WorkoutEvent`/`Settings` synthesize today in LedgerDomain.
The next Domain change to those shapes compiles and passes every test, because each test encodes with the
current codec. The adversarial round's own example shows it: a renamed label, as F04 already did
(`at:` → `doneAt:`). After that change, every stored v1 row is "damaged" rather than "a later version". The
unreadable-row rules then skip every readable copy of those keys (SF2), keep the log listed forever, and have
F17 tell the lifter to install a newer Ledger. The tester's finding 1 offered (a) golden fixtures and (b) a
version. The decision took (b) without (a), but (b) only works on top of (a). This is the payload
counterpart of `schema-v001.sql`.
*Fix:* commit `LedgerKit/Tests/LedgerPersistenceTests/Fixtures/payload-v001/` with:
- one envelope per `WorkoutEvent` case, including a `started` snapshot, a `Weight` as decimal text, a
  sub-millisecond date, and the `"+Infinity"`/`"NaN"` strings;
- one `Settings` payload.

Add a test that decodes each fixture with `decode(_:version: 1)`, compares the result with a hand-built value,
and checks that `encode` of that value reproduces the committed bytes. After that, a shape change fails CI and
must ship as `case 2` (or a row migration). Freeze these fixtures with v001.

**SF2. A damaged version-1 row blocks its own repair.**
`LedgerKit/Sources/LedgerPersistence/Events/GRDBWorkoutEventStore.swift:40-45` (doc at :24-25).
`append` treats every unreadable stored row alike: it keeps the row and skips the incoming envelope with that
key. That is right for `payload_version > EnvelopeCodec.version`, which a later build can read. It is wrong for
a row in a version this build knows but cannot decode, whether from corruption or from the drift in SF1: no
later version will read that row either. Meanwhile a peer's gap replay delivers a readable copy of the same
key, and a key names one envelope. As written, `unreadableCount` stays above zero forever. Under F17's rule the
workout is then never materialised or compacted, and the "needs a newer Ledger" message is false.
*Fix:* when the stored row's `payload_version <= EnvelopeCodec.version` and it fails to decode, `UPDATE` that
row's `payload`, `payload_version` and `wall_clock` from the incoming `EnvelopeRow`, and return the envelope as
newly stored so the host rebuilds. Keep the skip only for later versions. Then split
`UnreadableEventRowTests.unreadableRow_isSkippedCountedAndKept`: the "damaged bytes" case expects the repair,
and the "later version" case keeps today's expectations. This amends the orchestrator's 2026-09-30 decision, so
the call is the orchestrator's. At minimum, the F17 "Inputs from F05" text
(`tasks/features/F17-live-sync.md:212-228`) should state that it only covers later-version rows.

**SF3. HLC recovery cannot see unreadable rows' stamps, and `wall_clock` is written but never read.**
`LedgerKit/Sources/LedgerPersistence/Migrations.swift:201`, `GRDBWorkoutEventStore.swift:122-124`,
`LedgerKit/Sources/LedgerDomain/Protocols/WorkoutEventStore.swift:40-42`.
ADR-004's amendment says "every stored stamp counts toward `newest`". The protocol offers only
`envelopes(for:)` to reach stamps, and that leaves unreadable rows out. The notes say "`MAX(wall_clock)` over
the uncompacted logs is exactly the HLC recovery value", but no API runs that query, and F17's host cannot
reach the column because LedgerSync does not import LedgerPersistence. The case is rare: a rollback or a
damaged row, followed by a device clock that stepped back. It is still a gap against a normative rule, and it
is cheap to close now.
*Fix (either):*
- add `newestFiniteWallClock() async throws -> Date?` to `WorkoutEventStore`, backed by
  `SELECT MAX(wall_clock) FROM workout_event`. Give it a contract clause, and let the in-memory store compute it
  from its envelopes;
- or add one bullet to F17's "Inputs from F05" saying that recovery from `envelopes(for:)` misses unreadable
  rows' stamps, and that F17 should add that method.

### Nit

**N1. The `unreadableCount(for:)` default of 0 is a footgun for wrappers.**
`LedgerKit/Sources/LedgerDomain/Protocols/WorkoutEventStore.swift:47-52`. A decorator that F10 or F17 might add
(logging, metrics) and that forgets to forward the call reports every log as complete. The host would then
compact rows a later version needs. *Fix:* drop the default and implement it in the five test conformers
(`InMemoryEventStore`, `MutantEventStore`, `LossyEventStore`, `Since1970StampStore`, `MutantGRDBStore`), about
3 lines each. Or state on the requirement that wrappers must forward it.

**N2. `GRDBSettingsRepository.observe()` ends silently on an unreadable row.**
`GRDBSettingsRepository.swift:42-46`, `Observation/ValueObservation+AsyncStream.swift:15-18`. With a row from a
later version, the stream finishes with no value, and a later `save` never reaches that subscriber. This is
consistent with the documented bridge, but F07/F14 need to know. *Fix:* add a line to the notes and to
F07/F14's inputs: on an empty or finished stream, fall back to `load()`'s defaults and re-subscribe after
saving.

**N3. `Settings.init(from:)` treats an explicit `null` as missing.**
`LedgerKit/Sources/LedgerDomain/Model/Settings.swift:58-73`. `decodeIfPresent` returns `nil` for
`{"units":null}`, so the default is used, while the doc comment says a key that is present must be valid.
*Fix:* either say "missing or null" in the doc and test it, or use `container.contains(key) ? decode : fallback`.

**N4. A row with a wrongly typed column traps instead of counting as unreadable.**
`GRDBWorkoutEventStore.swift:143-147`. `row["payload_version"]` as `Int` and `row["payload"]` as `Data` are
GRDB's non-optional subscripts, which call `fatalError` when a value cannot be converted (for example
`payload_version` stored as text `'x'`). *Fix:* read them as `Int?`/`Data?`, and have `envelope()` return `nil`
(logged, counted) when either is missing.

**N5. Reads decode and log twice, and `append` compiles its statements for every envelope.**
`GRDBWorkoutEventStore.swift:64-70,105-113,152-160,32-56`.
- `envelopes(for:)` followed by `unreadableCount(for:)`, which F17's rules call together, fetches and decodes
  the whole log twice, in two snapshots, with a new `JSONDecoder` per row.
- Each unreadable row is logged on every call.
- `append`'s loop builds a new statement for the `SELECT` and the `INSERT` for every envelope. The adversarial
  batches run up to 1,000 envelopes, against the watch's "≤ 10 ms typical" write budget.

*Fix:* read both from one fetch, reuse one decoder per call, and use `database.cachedStatement(sql:)` in the loop.

**N6. `highestSeq` sorts a temporary B-tree.**
`GRDBWorkoutEventStore.swift:79-82`. `ORDER BY seq < 0 DESC` cannot use `uidx_event_key`'s order.
*Fix (checked in `sqlite3`: both parts are covering-index searches with the same result):*
`SELECT COALESCE((SELECT MAX(seq) … AND seq < 0), (SELECT MAX(seq) …))`.

**N7. Optional: add a byte-equality fast path to `append`.**
`GRDBWorkoutEventStore.swift:40-44`. The payload is deterministic (`.sortedKeys`), so compare
`stored.bytes == row.payload` first and decode only when the bytes differ. The common duplicate then skips the
decode, and a NaN envelope's exact redelivery becomes a no-op instead of a batch-wide `conflictingEnvelope`.
F17 still drops non-finite stamps on receipt (decision 9).

**N8. Errors that escape are not documented.**
`LedgerKit/Sources/LedgerPersistence/LedgerPersistenceError.swift:3-14`. GRDB's `DatabaseError`, `EncodingError`
(`append` of an envelope with a NaN `Weight`, where the in-memory store accepts it), `DecodingError`
(`Settings` load) and `CancellationError` all reach Domain-protocol callers unwrapped. Nothing is swallowed, but
a caller cannot match a `DatabaseError` without importing GRDB. *Fix:* before S2 adds four repositories, either
document on `LedgerPersistenceError` which foreign errors can escape, or add `case database(…)` and wrap them.

**N9. Tracking: criterion 8 is only partly closed.**
Criterion 8 says "after materialization". S1 compacts a stored log, which is correct for S1. S3 should re-close
it with a `materialize` → `compact` test.

### Considered and not raised

- NaN re-append conflicts (code-review #2): decided and routed to F17 (notes decision 9; F17 "Inputs from F05").
  N7 is the optional store-side mitigation.
- `DatabaseQueue` rather than `any DatabaseWriter` (code-review #10): the brief's public API specifies `DatabaseQueue`.
- `DatabaseTests.open_protectsTheFileAndItsCompanions` is `.disabled(if:)` on simulators. This is a platform
  limitation, not §11's "disable to get green": the simulators keep no protection class. The test runs on the
  host (`check.sh --fast`) and in both Device plans (orchestrator decision, finding 2).

### The review points

1. **Module boundaries.** Clean. LedgerPersistence imports `Foundation`, `GRDB`, `LedgerDomain` and `os`, and the
   package-graph check passes. The Domain changes stay Foundation-only. The contract in LedgerTestSupport imports
   only `LedgerDomain` (not `@testable`) and not `Testing`, so it uses public API only.
2. **Concurrency.** Clean.
   - Repositories are `Sendable` structs over `DatabaseQueue`, with injected clocks.
   - Envelopes are encoded before the write transaction, and no transaction spans an `await`.
   - Database work runs on GRDB's queue, never the main thread.
   - The bridge uses the `.task` scheduler with `bufferingNewest(1)`, and cancels on termination. The adversarial
     tests prove that a cancelled consumer and a dropped stream both stop fetching and free the observation.
   - `open(at:)` is synchronous by the brief's API. F07 should call it off the main actor; it took 4.6 ms on the
     watch simulator.
3. **Error handling.** Nothing is swallowed.
   - Unreadable rows are logged with `Logger.persistence`: row id and version public, the error private by
     default. They are counted and kept.
   - The observation logs and finishes on error.
   - `try?` appears only in test cleanup, with comments.
   - See SF2, N4 and N8.
4. **Design fidelity** and 5. **Accessibility.** N/A (no UI).
6. **Test quality.** Good.
   - Tests assert behaviour: contract clauses, row shapes and seeded round trips. There are no sleeps, and the
     observation tests synchronise on write barriers.
   - The only timing is `MigrationTimingTests`, tagged `.performance` and nightly-only, with its budget in
     `PerformanceBudget`.
   - Every suite carries `.persistence`. Property tests use `PropertySeed`.
   - The gap is SF1 (no golden payloads).
7. **Brief compliance.** Criteria 1, 7 and 8 have tests (table below). The deviations from the brief's DDL are
   all recorded in the notes and are additive or local-only: `_e7g` columns, `REAL` history dates,
   `workout.units`, `personal_record`, the `workout_event` rowid, no `elapsed_seconds`, FK indexes, and
   `payload_version`.

### Criteria → evidence

| Criterion | Evidence | Verdict |
|---|---|---|
| 1. Tables, indexes, `foreign_keys` on | `SchemaTests.v001_newDatabase_matchesCommittedDDL` (fixture confirmed identical by hand), `inMemory_foreignKeysOn_v001Applied`, `foreignKeys_rejectOrphans_andCascade`, `uniqueIndexes_areOnlyPrimaryKeys_andTheEventKey`; `DatabaseTests.open_newFile_isWALAndMigrated` (WAL); `SchemaAdversarialTests` (integrity, FK list, FK indexes) | Met |
| 7. Duplicates once; `highestSeq` per device | `WorkoutEventStoreTests.appendTwice_keepsEachKeyOnce_highestSeqPerDevice`; contract clauses `newInGivenOrder`, `highestSeqIsMaximum`, `fullWidthSeq`, `readsBackExactlyOnce`; `EventStoreBatchAdversarialTests` (in-batch duplicates, 16 racing appends) | Met |
| 8. `compact` removes rows and unlists | `WorkoutEventStoreTests.compact_deletesRows_andUnlistsTheWorkout`; clause `compactOne`; `EventStoreBatchAdversarialTests` (ten workouts, repeated compacts) | Met for S1 (N9) |
| F04 "Inputs" 1–4 | GRDB store passes all 13 clauses (host run above); decoded, not byte, comparison; exact dates (seeded) | Met |
| ADR-007 storage | `ColumnCodecTests`, `ExactWeightColumnAdversarialTests`: exact, refuses rather than rounds, edges at `Int64` | Met |

### Schema vs S2 and S3

Nothing in v001 blocks S2 or S3. I mapped every stored field of `Exercise`, `Program`, `Week`, `DayTemplate`,
`Slot` (`misses` → `slot_miss`), `WorkoutState` (`source`, `units`, `phase`), `WorkoutExercise`, `LoggedSet`,
`PersonalRecord` (both kinds and `previous`) and `WorkoutSummary` to a column. Live-only fields (`cursor`,
`rest`, `autoRest`, `programUpdates`, `lastPerformance`) are rebuilt on read, as the plan says. History tables
have no foreign keys to `exercise` or `slot`, so history survives edits. For the slices that follow:

- `slot_miss.id` and `personal_record.id` have no Domain counterpart, so S2 and S3 must mint ids. For the synced
  `slot_miss`, use an id derived from `(slot_id, week_index)`, such as a name-based UUID. Two devices' misses
  then converge under CloudKit, which has no `UNIQUE` constraint to rely on (ADR-002). Random ids would duplicate
  a miss on every re-save or merge.
- A user-entered `Slot.step` or `startLoad` that is not a whole number of 10⁻⁷ g (an eighth of a pound) makes
  `save` throw `inexactWeight` (ADR-007). S2 should surface that as a validation error for F08. Plate weights
  are safe, because they live in the settings JSON as decimal text.
- S3's `fixtures/db-v001.sqlite` must be generated from exactly this v001. It could also carry the SF1 golden
  rows.

### Verdict

**Approve for G3: 0 Blocking, 3 Should fix, 9 Nits.**
- SF1 and SF2 should land before any build that persists user data, and ideally in this PR while the payload
  format is still unshipped.
- SF3 can be the one-line F17 input.

For G5: this PR carries architecture decisions made by the orchestrator, not Pete:
- a new requirement on the Domain protocol `WorkoutEventStore` (`unreadableCount`);
- versioned payloads;
- tolerant decoding of `Settings`;
- `personal_record` kept local-only;
- the DDL deviations listed above.

Per `docs/subagent-workflow.md` G5, the orchestrator should stop for Pete's review before merging, unless he
has already signed off on them.
