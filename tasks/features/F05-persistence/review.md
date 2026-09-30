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

# Slice S2 review

Reviewer pass on `feat/F05-s2` at `641e4b2`, diff `git diff 1db1cf9...HEAD` (28 files). Scope: `SyncedRecord`
and its child diff, `ColumnReader`/`JSONArray`, the five program record types and `ProgramRows`,
`GRDBExerciseRepository` (search and seeding), `GRDBProgramRepository`, the two new `LedgerPersistenceError`
cases, the LedgerTestSupport contracts and seeders, product decision #23, and the F07 and F12 brief lines.
I did not review the adversarial tester's untracked files under `Adversarial/`.

### What I ran

- `/code-review high` on the diff. It raised 10 candidates. Each one is ranked below or answered under
  "Considered and not raised".
- `swift test --package-path LedgerKit --filter LedgerPersistenceTests` on the macOS host. I ran it on a
  `git archive 641e4b2` copy in my scratchpad, so it could not disturb the tester's worktree. **All committed tests
  pass**, with the timing suites skipped by design. That copy also held three throwaway probe tests (B1), which
  are not committed anywhere.
- SQL: every statement in the diff binds its values. The only interpolated identifiers are static table names
  and `databaseDictionary` keys. Search runs no `LIKE`: the text is matched in Swift, so there is nothing to
  escape. The equipment and muscle filters are bound named parameters.
- Seeding: an entry whose name clashes with a stored exercise is logged and **still inserted** by its id
  (`GRDBExerciseRepository.swift:93-101`). No path skips a catalog id over a name, and clause `seedNameClash`
  pins this.
- Exact weights (ADR-007): every weight column is a nullable `_e7g` `INTEGER`. They are written through
  `Weight.e7g()`, which throws `inexactWeight` and never rounds, and read only from `INTEGER` storage
  (`ColumnReader.integer`, which refuses the `REAL` truncation GRDB would do). I checked `47.25 lb` →
  `214322394825` by hand. Criterion 2's round trip covers both lb and kg loads.
- `SlotMissRecord.id`: I checked the RFC 9562 v5 layout. The namespace bytes are in network order, and the
  version and variant masks are right (`&` binds tighter than `|` in Swift).

### Blocking

**B1. Saving a program that reuses another program's week, day or slot ids silently takes those rows over and
corrupts the other program.**
`LedgerKit/Sources/LedgerPersistence/Records/ProgramRows.swift:53-67`,
`LedgerKit/Sources/LedgerPersistence/Records/SyncedRecord.swift:29-33,53-59`.
`write` diffs only against the saving program's own live rows. An incoming id that is live under another
program is not in `storedByID`, so it is upserted. `ON CONFLICT (id) DO UPDATE` then rewrites that row's
`program_id` or `day_template_id` to the new program. `duplicateIdentifier` only catches clashes inside one
save. I confirmed three outcomes with probes on the host:
- **Copied block.** Program A is active. B gets a new `ProgramID` but reuses A's weeks and days, and is
  saved. `save` succeeds, and every `day_template` row now belongs to B. `program(id: A)` then throws
  `tooFewWeeks(count: 0)` on every read. Had A stayed active, `active()` would throw and `observeActive` would
  end for good.
- **Slots only.** B reuses A's day 0 slots under B's own days. `save` succeeds, and A reads back with day 0
  empty. That is silent data loss with no error at all.
- **Misses cleared on the copy** (what F24's `NextBlock.rollForward` specifies: "misses cleared"). A's live
  `slot_miss` rows for the taken slots were never in B's stored set, so they are neither soft-deleted nor
  replaced. B reads back **16 misses it does not have**, and the round trip is unequal.

History makes this worse. `workout_exercise.slot_id` points at slot ids, so after the takeover block 1's
sessions point at block 2's slots.

This is not a far-fetched caller. F24's brief specifies
`NextBlock.rollForward(_ program:…) -> Program` as a pure helper with no UUID source
(`tasks/features/F24-progression-states.md:26`), so the obvious implementation keeps every child id. `rollForward` also cannot
mint new ids without an injected UUID source.

*Fix:*
1. In `ProgramRows.write`, after reading the stored rows and before any upsert, take the incoming week, day and
   slot ids that are not among this program's stored rows. Refuse any of them that exists, live or deleted,
   under another program:
   - weeks and days: `SELECT id FROM program_week WHERE id IN (…) AND program_id != ?`, and the same for
     `day_template`;
   - slots: `SELECT slot.id FROM slot JOIN day_template ON day_template.id = slot.day_template_id WHERE
     slot.id IN (…) AND day_template.program_id != ?`.

   Throw `LedgerPersistenceError.duplicateIdentifier("<table> <id>")`, which rolls back like every other
   refusal. Misses are covered, because their ids derive from the slot's.
2. Add a `ProgramRepositoryContract` clause: "a program naming another program's week, day or slot id is
   refused, and the other program reads back unchanged". F07's fakes then keep the same rule.
3. Add a line to F24's brief inputs saying that `rollForward` must mint new program, week, day and slot ids
   from an injected UUID source.

### Should fix

**SF1. A catalog correction to a shipped id can never reach an installed device.**
`GRDBExerciseRepository.swift:93-103`; notes decision 2 ("An upgrade only adds").
A stored id is never written again. So a later catalog that fixes an existing entry is recorded as applied
(its version is marked) but its content is dropped, whether the fix is a start load (F03 has already revised
these twice: `4d7cf28`, `f0b444e`), curated alternatives or a typo. F03's brief says `version` is bumped "on
every content change", which suggests content changes are meant to ship. Catalog rows are never synced
(architecture §7) and never edited by the lifter (F12 edits custom exercises only), so updating them in place
is safe.

*Fix (decide, then act):*
- **either** on an upgrade, overwrite the content of stored catalog rows the new catalog lists: live rows
  with `is_custom = 0` and `catalog_version < version`, keeping `created_at`. Deleted rows stay deleted;
- **or** keep additive-only and state it in F03's brief: after release, a shipped id's content is frozen, and
  a correction needs a new id.

The choice belongs to the orchestrator or Pete. The code today matches neither statement cleanly.

**SF2. The search rule has one implementation, and neither F12 nor F07's fakes can reach it. The F12 line
promises more than `search` gives.**
`GRDBExerciseRepository.swift:145-168`, `tasks/features/F12-library-history.md:53`,
`LedgerTestSupport/Persistence/ExerciseRepositoryContract.swift:148-153`.
- `ExerciseSearch` is internal to LedgerPersistence, and a `Feature*` target never imports LedgerPersistence
  (engineering-standards, module rules). F12's new line says in-memory filtering of `observeAll()` "must match
  the same way", so F12 has to reimplement the fold. So does F07's `InMemoryExerciseRepository`.
- The contract already carries a third copy, `String.folded`, which omits the trim that `key` applies.
- F12's muscle pills are groups ("Legs", "Arms"). `search` takes one `MuscleGroup` and matches the primary
  muscle only, so "`ExerciseRepository.search` implements it" is not true for those pills.

*Fix:*
1. Move the rule into LedgerDomain as one public pure helper, for example
   `ExerciseSearch.key(_:)`, `matches(_ exercise:query:)` and a name-order comparator. Use it in
   `GRDBExerciseRepository`, the contract's expected orders and F07's fake. This is a Foundation-only
   addition; the brief says "no Domain type changes", so the orchestrator decides.
2. Reword F12:53: `search` takes one primary muscle, so the group pills filter `observeAll()` in memory
   through the shared helper, mapping each pill to its `MuscleGroup` set.

**SF3. The contract leaves out behaviour that F07's fakes must share, and the Domain protocols do not
document it.**
`LedgerTestSupport/Persistence/ProgramRepositoryContract.swift:11-18`,
`ExerciseRepositoryContract.swift:10-19`, `LedgerDomain/Protocols/Repositories.swift:7-24`.
Several behaviours are pinned only by GRDB-only tests, so a fake that differs still passes F07 criterion 4:
- `setActive` of an unknown or deleted program throws `missingRow` (`ProgramRepositoryTests.swift:159-173`);
- duplicate child ids throw `duplicateIdentifier` (`:129-142`);
- B1's cross-program refusal;
- `seedIfNeeded` stores every entry as a catalog row whatever its `isCustom` says
  (`ExerciseRepositoryTests.swift:75-89`).

Meanwhile the contract asserts an order for `search` and `all()` (folded name, then id) that no protocol doc
states. F10, F11 and F24's stores are written against the protocol and tested against the fakes.

*Fix:* promote those four behaviours to clauses; `LedgerPersistenceError` is reachable from
LedgerTestSupport. Add one-line doc comments to `ExerciseRepository.all/search/observeAll` (order and
matching, pointing to decision #23) and to `ProgramRepository.save/setActive/delete` (what each throws, and
that deletion is soft).

### Nit

**N1. `GRDBExerciseRepository.save` bumps `updated_at` even when nothing changed** (`GRDBExerciseRepository.swift:52-56`).
The program path deliberately leaves unchanged rows alone for M4's last-writer-wins sync (notes decision 4).
Saving an unchanged custom exercise could later overwrite a real edit made on the other device. *Fix:* fetch the
stored row and go through `ExerciseRecord.write([record], over: stored, in:at:)`. It already skips unchanged rows.

**N2. `delete` leaves `is_active = 1` on the deleted program** (`GRDBProgramRepository.swift:70-73`, `:95-102`).
`activate` skips deleted rows, so the flag never clears. A later revival, by a sync (M4) or by `save` from a
stale copy, can bring back two active programs. `fetchActive` then picks the one updated last, which is the
revived one. *Fix:* in `delete`, also set `is_active = 0` on the program row in the same transaction.

**N3. `seedIfNeeded` does not refuse duplicate ids inside one catalog** (`GRDBExerciseRepository.swift:93-103`).
`storedIDs` is not updated inside the loop, so the second entry silently overwrites the first. F03 tests id
uniqueness, but the program path throws for the same fault. *Fix:* check the ids up front and throw
`duplicateIdentifier("exercise <id>")`.

**N4. The two "unchanged write emits nothing" checks cannot fail** (`ObservationTests.swift:21-23`, `:35-37`).
The bridge buffers `bufferingNewest(1)`, so a spurious emission from the no-op write is replaced by the next
real one before `next()` reads it. The tests pass with or without `removeDuplicates()`. *Fix:* count
`onChange` calls with GRDB's `ValueObservation.start(in:onError:onChange:)` behind a write barrier, or drop
"and none for an unchanged write" from the test names.

**N5. Public `Seeders.program` traps on inputs it accepts** (`LedgerTestSupport/Persistence/Seeders.swift:65-67`, `:99-100`).
- `days > 7`: the weekday wraps and `Dictionary(uniqueKeysWithValues:)` traps.
- `slotsPerDay > 32`: slot ids collide across days.
- `exercises: []`: `% 0` traps.

*Fix:* add `precondition`s with messages, or document the ranges; later features will reuse this seeder.

**N6. F07's new input lines** (`tasks/features/F07-composition-di.md:98-103`).
- `ExerciseCatalog.seed()` throws (F03 brief), so the call needs `try`. The brief should also say what launch
  does when `seed()` or `seedIfNeeded` throws: log it and carry on without a catalog, or fail boot.
- "9.2 ms … so it need not wait for the first frame" comes from the simulator running on the Mac's CPU. Keep
  the notes' caveat, "F20 times a real watch".

**N7. The F05 brief's test plan still says "search by prefix"** (`tasks/features/F05-persistence.md:104`).
*Fix:* point it at decision #23.

**N8. `rpe_x2` goes through `NSDecimalNumber.intValue`** (`Records/SlotRecords.swift:54`).
The value is safe here, because it is always exact 10…20, but `intValue` is known to misreport some `Decimal`s.
*Fix (optional):* expose `RPE`'s half-points in Domain, or use a rounded `Int` conversion with a `guard`.

### Considered and not raised

- Lower-case stored ids (code-review #4). Every writer uses `ColumnCodec.text`, which is upper-case `uuidString`,
  and M4 will write through the same codec. A foreign writer is out of scope, as in S1.
- The seed runs 2×214 statements (code-review #8), folds names twice per search (#9), and `observeActive`
  re-fetches on writes to an inactive program (#10). All of these are within budget: seeding took 9.2 ms and
  search 1.75 ms on the watch simulator, and program edits on the watch are rare. They are worth revisiting
  only if F20's device numbers disagree.
- Unreadable exercise rows are left out of `all()`, `search` and `observeAll`, while a program read throws.
  This is the right split: a program is one aggregate, and leaving out a slot would let the next save delete
  it (notes decision 7).
- Decision #23 skips #21 and #22. Those two are on `feat/F03-exercise-catalog` ("Catalog start loads",
  "Kettlebell step"), so the numbering is consistent. Whichever branch merges second must keep the table in
  order.
- The `now: Date.init` default arguments follow S1's precedent. Tests and F07 inject the clock.

### PR size

684 code lines, against the 500 target and under the ~1,000 split threshold, with the split considered and named
(standards §10). The argument holds: slice (a) would ship `SyncedRecord.write` with no caller, so its tests
would have to wait for (b), and a second gate costs more than about 285 lines of review. B1's fix adds about
20 lines. **Complies.**

### The review points

1. **Module boundaries.** Clean.
   - LedgerPersistence adds a `CryptoKit` import, a system framework available on watchOS, used for the v5
     UUID.
   - The contracts import only `Foundation` and `LedgerDomain`: no `@testable`, no `Testing`.
   - No Domain file changes.
2. **Concurrency.** Clean.
   - Both repositories are `Sendable` structs over `DatabaseQueue`, with an injected clock.
   - No UUID source is needed, because miss ids are derived.
   - Records are built and validated before `queue.write`, and no transaction spans an `await`.
   - Folding runs inside the read closure, off the main actor.
3. **Error handling.** Nothing is swallowed.
   - Unreadable exercise rows are logged with their id and kept, matching S1. Seed name clashes are logged at
     notice level.
   - Domain validation errors pass through unwrapped, as documented on `LedgerPersistenceError`.
   - B1 is the gap: a save that should be refused succeeds.
4. **Design fidelity** and 5. **Accessibility.** N/A (no UI).
6. **Test quality.** Good.
   - The tests assert behaviour: round trips, row counts with the arithmetic in comments, timestamps from a
     `ManualClock`, and damage tables.
   - There are no sleeps. Timing is nightly-only and uses medians.
   - Weak spots: N4, and the missing cross-program case (B1).
7. **Brief compliance.** Criteria 2 and 11 have tests (table below). Search follows decision #23 rather than
   the brief's "prefix". F02 review N2's re-validation is done on both save and load.

### Criteria → evidence

| Criterion | Evidence | Verdict |
|---|---|---|
| 2. 8 × 4 program round-trips equal, misses included | `ProgramRepositoryTests.eightByFour_roundTripsEqual_includingMisses`, clauses `roundTrip`, `saveReplaces` | Met for one program; B1 breaks it once two programs share ids |
| 11. Seed idempotent, custom kept, additive upgrade, no duplicates | clauses `seedIdempotent`, `seedUpgrade`, `seedNameClash`; `ExerciseRepositoryTests` seed tests | Met (SF1 is a policy gap beyond the criterion) |
| Decision #23 search | clauses `searchText`, `searchFilters`, `searchWildcards` | Met in GRDB; SF2 for its other consumers |
| Soft deletes and child diff in one transaction | `partialUpdate_diffsChildren`, `failedSave_changesNothing`, `ProgramSoftDeleteTests`, `DamagedProgramRowTests` (repair) | Met within one program; B1 across programs |
| ADR-007 exact columns | `save_writesTheDocumentedColumns` (both repositories), `inexactLoad_isRefused`, `inexactStartLoad_isRefused`, `REAL` damage cases | Met |

### Doc updates

- **Decision #23:** accurate, and it matches the code and the contract.
- **F07 (`:98-106`):** the foreign-key ordering, the seeding behaviour and the contract instructions are
  accurate. See N6 (`try`, the failure path, the simulator caveat) and SF3 (the contract gaps the fakes inherit).
- **F12 (`:53`):** not accurate as written for the group pills, and it asks F12 to copy a rule it cannot
  import (SF2).

### Verdict

**Changes requested for G3: 1 Blocking, 3 Should fix, 8 Nits.**
- B1 must be fixed before merge. It is a silent cross-program data loss through the public API, and F24's
  specified `rollForward` would trigger it.
- After B1 and its contract clause, this is approvable. SF1 needs a decision (orchestrator or Pete). SF2 and
  SF3 are cheap now and expensive after F07 builds fakes against the current contract.
