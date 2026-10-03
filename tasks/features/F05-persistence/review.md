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

# Slice S2 review — fix round 1

Reviewer pass on `feat/F05-s2` at `57fdeb7`, diff `git diff ec6da47 57fdeb7` (29 files), with the notes' "### S2 fix
round 1" section. Decisions taken after my first review and checked here, not re-argued: SF1 is decision #24
(Pete), including the lifter-save rule; SF2 moves search into `LedgerDomain/Rules/ExerciseSearch.swift` (approved
exception); S2-4 refuses NUL with `nulInText`. As before, I did not review the tester's untracked files.

### What I ran

- `swift test --package-path LedgerKit --filter 'LedgerPersistenceTests|ExerciseSearchTests|LedgerTestSupport'` on a
  `git archive 57fdeb7` copy in my scratchpad. **All pass**: 214 persistence tests (the timing suites skipped by
  design) and 3 `ExerciseSearch` tests.
- Two throwaway probes on that copy, not committed anywhere. Both pass:
  - a slot that a **live** program dropped (soft-deleted under its own live day) is still refused to a second
    program by name, and stays under the first program's day;
  - an **active** copy that reuses a week id is refused, writes no `program` row, and leaves the first program
    active. So the refusal runs inside the save transaction, before `activate`.
- `/code-review high` on the diff. It raised 8 candidates. Each one is ranked below or answered under
  "Considered and not raised".
- SQLite affinity check (for code-review #1): `INSERT` of `1350000000.0` or `CAST(7 AS REAL)` into an `INTEGER`
  column is stored as `integer`. Only `9.3e18` and `1.5` stay `real`.

### Prior findings

| Finding | Status | Evidence |
|---|---|---|
| **B1** cross-program takeover | **Resolved** | `ProgramRows.swift:61` calls `refuseOtherProgramsIDs` after every stored-row read and before the first upsert (`:63`). `:73-93` throws `duplicateIdentifier("<table> <id>")`. The owner queries at `:157-162` have **no `deleted_at` filter on any table**, so deleted weeks, days and slots count. Slots are found through their day's `program_id`, so a slot under any day of another program is caught. `IS NOT ?` also catches a `NULL` owner. It runs in `GRDBProgramRepository.save`'s `queue.write` (`GRDBProgramRepository.swift:46-51`), so a refusal rolls back, and the probe confirms it. Contract clause `otherProgramsIDs` (`ProgramRepositoryContract+Identity.swift:47-81`). F24's brief has the UUID-source line (`F24-progression-states.md:53-56`). |
| **SF1** catalog corrections | **Resolved** (decision #24) | `GRDBExerciseRepository.swift:119-146`: new ids are inserted, and live rows with `is_custom = 0 AND catalog_version < version` are refreshed. Deleted rows, custom rows and lifter-saved rows (`NULL` version) are excluded. The refresh goes through `ExerciseRecord.write` with the stored rows as `replaced`, so `created_at` is never rewritten and `updated_at` moves only on a content change. The `mark` at `:109-112` writes no `updated_at`, and `CatalogUpgradeTests:24-48` pins this per row. Lifter-save rule: `:70-73`, also without `updated_at` (`CatalogUpgradeTests:14-22`; clause `seedLeavesTheLifters`). Decision #24 is at `docs/product-decisions.md:31`. |
| **SF2** one search rule | **Resolved** | `LedgerDomain/Rules/ExerciseSearch.swift:10-46` is public and pure. LedgerDomain still imports only Foundation (46 files, nothing else). The persistence copy and the contract's `String.folded` are gone. GRDB uses it at `GRDBExerciseRepository.swift:42-50` and `:194`; the contract uses it at `ExerciseRepositoryContract.swift:91`. F12:53 is reworded for group pills, and F07:113 points the fakes at it. |
| **SF3** contract gaps and docs | **Resolved** | Clauses `setActiveMissing`, `duplicateChildren` and `otherProgramsIDs` (`ProgramRepositoryContract+Identity.swift:8,23,47`), and `seedCatalogRows` (`ExerciseRepositoryContract+Seeding.swift:51`). Protocol docs: `Repositories.swift:8-34`. |
| N1 exercise save stamps an unchanged row | Resolved | `GRDBExerciseRepository.swift:64-69`; `ExerciseRepositoryTests.swift:39-46` |
| N2 delete leaves `is_active` | Resolved | `GRDBProgramRepository.swift:76-80`; `ProgramSoftDeleteTests.swift:47` |
| N3 duplicate catalog ids | Skipped; **the reason holds** | The tester's "(documents)" test pins "last wins", and F03 validates unique ids at build time. Behaviour is unchanged and stated at `GRDBExerciseRepository.swift:93`. Throwing remains a one-line change if the orchestrator wants it. See also new N-c on ordering. |
| N4 observation checks could not fail | Resolved | `ObservationTests.swift:17-31` uses an unbuffered stream over the repository's own `DistinctObservation`. The no-op writes at `:42` and `:58` fire the update hook, and the notes' mutant (`removeDuplicates` never equal) fails both tests. |
| N5 `Seeders` traps | Resolved | `Seeders.swift:69-74`, `:116-121`, `:150`; `SeedersTests` |
| N6 F07 lines | Resolved | `F07-composition-di.md:100-108` (`try`, the failure path, the F20 caveat) |
| N7 "search by prefix" | Resolved | `F05-persistence.md:104` |
| N8 `rpe_x2` via `intValue` | Skipped; **the reason holds** | `RPE` stores `halfPoints: Int`, and `value` is `Decimal(halfPoints) / 2` (`RPE.swift:8,24-25`). So `value * 2` is always a small, compact `Decimal`, and `intValue` is exact. No reachable input misreports. |

Adversarial items:
- **S2-2:** `appliedVersion` (`:161-167`) is resolved.
- **S2-3:** keying by `DatabaseValue` (`SyncedRecord.swift:57-75`) is resolved.
- **S2-4:** the single NUL check in `upsert` (`SyncedRecord.swift:23-28`) is resolved. Every record write goes through it, and the
  only other text writers bind UUIDs or JSON, which escapes NUL.

### Blocking

None.

### Should fix

None.

### Nit

**N-a. The NUL refusal is GRDB-only: the contract has no clause, and no input brief knows about it.**
`SyncedRecord.swift:23-28`; `ExerciseRepositoryContract.swift`, `ProgramRepositoryContract.swift`;
`F12-library-history.md:49`.
F07's fakes will store `"a\u{0}b"` and read it back, so a store tested against them never sees `nulInText`. In the
app, a pasted name holding U+0000 in F12's `CustomExerciseDraft`, or in F11's day name or tag, reaches `save` and
throws an error that a Feature cannot match, because Features never import LedgerPersistence.
*Fix:*
- Add one clause per contract: "text holding U+0000 is refused with `nulInText("table.column")`; nothing is
  saved". The program contract already imports LedgerPersistence, and the exercise contract can too.
- Add one line to F12's draft rules, and the same to F11's inputs: names and tags refuse U+0000, or strip it,
  before `exercise(id:)`.

**N-b. `otherProgramsIDs` does not pin a row that a live program dropped, or deleted days and weeks.**
`ProgramRepositoryContract+Identity.swift:47-81`.
The clause checks a deleted program's slot only, and the live program's ids only while they are live. A fake that
checks "other programs' rows, live rows only, plus every row of a deleted program" passes, yet hands a second
program a slot the first one dropped in an edit. That slot is the one its history still points at.
*Fix:* before the delete, save `first` with day 0's first slot removed, and expect `second`'s copy of that slot to
throw `duplicateIdentifier("slot …")`. My probe does exactly this, and GRDB passes it.

**N-c. Write order is no longer deterministic** (code-review #5).
`GRDBExerciseRepository.swift:94-101`, `SyncedRecord.swift:69`.
- The seed dedupes through `Dictionary(…).values`, so inserts, marks and clash logs come in a per-launch hash
  order. Before, they followed the catalog's order.
- `removed` lost its `.sorted()` because `DatabaseValue` is not `Comparable`, so soft deletes now run in hash order too.

Nothing observable changes today. But logs and statement order should be reproducible, and M4's change capture may
read them.
*Fix:*
- Dedupe with a seen-set while walking `catalog` in reverse (last wins), then restore the catalog's order.
- Build `removed` by walking `stored` in its query order (`stored.map { $0["id"] }.filter { !ids.contains($0) }`).

**N-d. The doc overclaims that the applied version always moves up** (code-review #3).
`GRDBExerciseRepository.swift:87-88`.
"So the applied version moves up even when an upgrade changes nothing" holds only when at least one listed row is
inserted or refreshable. If every row a later catalog lists is lifter-saved or deleted, and it adds no ids,
nothing is marked. Every launch then re-runs the three scans in a write transaction, as a no-op. No screen can
reach this today, because nothing saves catalog rows.
*Fix:* reword the doc to "…moves up whenever the upgrade writes a row; otherwise the next launch re-checks, as a
no-op". Moving the applied version into its own metadata row is out of proportion for a state no screen can
reach.

### Considered and not raised

- **code-review #1: a damaged `REAL` equal to the integer content is never repaired by a save.** It is
  unreachable. Every compared numeric column is declared `INTEGER` (`Migrations.swift:45-49`, `:99-103`), and
  SQLite's affinity stores an integral `REAL` as `integer` (checked above). A `REAL` that stays `REAL`
  (`1.5`, `9.3e18`) never equals an `Int64` content value, so the diff rewrites it.
- **code-review #2: a save that changes nothing still clears `catalog_version`.** That is decision #24's
  lifter-save rule as confirmed ("a save clears `catalog_version`"). Catalog rows are not synced, so the
  cross-device divergence in the scenario cannot happen. No screen saves a catalog row.
- **code-review #4: a row deleted with `is_active = 1` before this fix keeps the flag.** Pre-fix S2 never
  shipped: it is unmerged, with no TestFlight build. M4's revival path sets its own rules.
- **code-review #6, the three owner queries on every save.** Three indexed `IN` lookups of at most 224 ids each,
  on a rare write. Filtering to the ids missing from the stored sets would save microseconds and add a branch.
- **code-review #7, folding twice** (same as code-review #9 in the first review). Within budget.
- **code-review #8, `isInNameOrder` has no production caller.** My SF2 fix asked for a comparator, and F07's fakes
  and F12's in-memory filter are its intended callers. `ExerciseSearchTests` pins that it agrees with `sorted`.
- **The protocol docs name `duplicateIdentifier` and `missingRow`, which Features cannot import.** These are
  programmer errors: `rollForward` mints ids, and the builder only activates saved programs. A Feature handles
  them as unexpected. N-a is the only user-reachable case.
- **The contract now imports LedgerPersistence.** LedgerTestSupport already depended on it (`Package.swift:128-137`),
  and F07's fakes live there. Module boundaries are unchanged.

### PR size

775 code lines (+91), still under the ~1,000 split threshold, and the notes reproduce the count method. **Complies.**

### Verdict

**Approved for G3: 0 Blocking, 0 Should fix, 4 Nits.**
- B1 is fixed at the root and pinned by a contract clause:
  - deleted rows and slots under another program's days are covered;
  - the check runs inside the save transaction.
- SF1–SF3 implement the decisions as made. N3 and N8 are skipped for sound reasons.
- N-a and N-b are cheap contract additions, best made before F07 builds its fakes. They can land in this PR or
  in S3's first commit, as the orchestrator prefers. N-c and N-d are optional.

# Slice S3 review

Reviewer pass on `feat/F05-s3` at `f5ab3fb`, diff `git diff feat/F05-s2..f5ab3fb` (28 files). Scope: the four
history record types and `WorkoutRows`, `GRDBWorkoutRepository`, `GRDBStatsQueries`, the additions to
`ColumnCodec`, `ColumnReader` and `LedgerPersistenceError`, the two LedgerTestSupport contracts and the history
seeders, the fixture and the new tests. I did not review the adversarial tester's untracked files under
`Adversarial/`, and I changed no code or test.

### What I ran

- Host tests on a `git archive f5ab3fb` copy in my scratchpad (`f05s3-g3/copy`), so the tester's worktree was not
  disturbed: `WorkoutRepositoryTests`, `WorkoutRowDiffTests`, `DamagedWorkoutRowTests`, `StatsQueriesTests`,
  `MigrationCompatibilityTests`, `ObservationTests`, `SeedersTests`, `ProgramRepositoryTests`. **All pass** (44
  tests and contract clauses, 8 suites).
- `LEDGER_TEST_LANE=nightly swift test --filter StatsQueriesPerformanceTests` on the host: passes (criterion 9's
  assertion, host only; I ran no simulator).
- Three throwaway probes on that copy, not committed anywhere:
  - a personal record naming another workout (SF1): confirmed;
  - `EXPLAIN QUERY PLAN` of every stats statement and of the list reads, over 400 workouts × 50 sets;
  - three workouts ending at the same instant: `recent` and `lastPerformance` break the tie by id, ascending.
- `/code-review high` on the diff. It raised 10 candidates. Each is ranked below or answered under "Considered
  and not raised".
- `sqlite3` and Python on a copy of `Fixtures/db-v001.sqlite`: `journal_mode` is `delete` (one file),
  `integrity_check` is `ok`, `foreign_key_check` is empty, and only `v001_createSchema` is applied.
- Derived ids: all 33 `slot_miss` ids in the fixture equal Python's `uuid.uuid5(slot_id, str(week_index))`, and
  the two `personal_record` ids equal `uuid5(workout_id, "personal_record 0")` and `"… 1"`.
- The 662-line count, with my own script over `git diff -U0` (see "PR size").

**Line-by-line reading of the SQL and the write path:**
- **Transaction.** `materialize`, `updateSets` and `delete` each run in one `queue.write`
  (`GRDBWorkoutRepository.swift:52-55`, `:88-106`, `:114`). The clock is read before the transaction, and
  nothing awaits inside it.
- **Upsert and stale children.** Every live row of the four tables is read before any is written
  (`WorkoutRows.swift:40-44`), so a dropped exercise's sets are soft-deleted with it. Parents are written first.
  An unchanged row is not written. A deleted workout comes back with its `created_at`.
- **Exactness.** Weights and e1RMs go through `Weight.e7g()` and are read through `ColumnReader.integer`. SQL
  only compares, orders and takes `MAX` of the `_e7g` integers. Volume sums reps per distinct weight in SQL and
  multiplies in `Decimal` (`GRDBStatsQueries.swift:126-136`). I found no `Double` path for a weight. Dates are
  `REAL` by design, and `ColumnReader.date` refuses anything else.
- **Weeks.** `e1RMByWeek` uses `calendar.firstDayOfWeek(containing:)` for both the injected `now` and each
  workout, and `isoWeekKey` honours `weekStart` (`WeekCalendar.swift:39,94-97`), so one stats week has one key.
  No SQLite date function is used.
- **Ordering.** Every list has a total order: `ended_at DESC, id`; children by `position, id`; records by
  `achieved_at DESC, kind, id`; `recentlyLogged` by latest end, then exercise id.
- **Indexes.** No stats query scans `logged_set`. The per-exercise queries enter through
  `idx_wex_exercise_workout`, the range queries through `idx_workout_ended` then `idx_wex_workout`, and
  `personalRecords` through `idx_pr_exercise`. `recentlyLogged` walks every `workout_exercise` row by design
  (the notes time it at 3.7 ms on the host at 20,000 sets).

### Blocking

None.

### Should fix

**S3-SF1. A personal record that names another workout overwrites that workout's record row.**
`Records/WorkoutRows.swift:25`, `Records/LoggedSetRecords.swift:63-65,88`; the claim at `WorkoutRows.swift:57-58`
and notes decision 14 ("ids are never taken over").
A record's row id and `workout_id` column both come from `record.workoutID`, never from the workout being
written, and nothing compares the two. Probe: workout A is stored with one record (e1RM 200 lb). Then
`materialize(B, prs: [a record whose workoutID is A's])` succeeds. Afterwards:
- A's record row holds B's value (999 lb), under A's id `uuid5(A, "personal_record 0")`;
- B has `pr_count = 1` and no record row;
- `personalRecords` reports the wrong value for A's workout.

This is the takeover class of S2's B1, on the one table the owner check skips. `PersonalRecords.detect` always
stamps `workout.id`, so no specified caller does this today. That is why it is not Blocking. Question 4's
follow-up (re-detecting "from that workout forward") is the first caller that will hold records of several
workouts at once.

*Fix:*
1. In `WorkoutRows.init(_:records:)` or `write`, throw when a record's `workoutID` is not the workout's. A new
   `LedgerPersistenceError` case is clearer than reusing `duplicateIdentifier`.
2. Add a `WorkoutRepositoryContract` clause: "a record naming another workout is refused; nothing is stored, and
   the other workout's records are unchanged".
3. Correct the comment at `WorkoutRows.swift:57-58`.

**S3-SF2. The contracts let a fake pass while it is wrong on four rules the notes state.**
`LedgerTestSupport/Persistence/StatsQueriesContract.swift:144-158`,
`StatsQueriesContract+Weeks.swift:9-48,82-104`, `WorkoutRepositoryContract.swift:180-199`.
- **Which sets feed `bestE1RM` and `e1RMByWeek`.** In `bests`, the only set of an excluded kind is a drop of
  210 × 1 (e1RM 210 lb), below the expected 185 × 8 (229.7 lb). A fake that counts drop and warm-up sets returns
  the same `bestE1RM`. `e1RMByWeek` holds working sets only. GRDB is safe because its three queries share
  `SQL.recordKinds`; a fake has no such link.
- **`sessionsCompleted` "with or without a done set"** (decision 12). The clause's empty workout (number 3) ends
  one second before last week, so it is in neither range. Only the GRDB-only
  `StatsQueriesTests.onlyLiveRowsOfFinishedWorkouts_count` pins the rule.
- **Ties.** "Then id" is documented for `recent`, `workouts(in:)`, `lastPerformance` and `recentlyLogged`
  (`GRDBWorkoutRepository.swift:64-71`, `GRDBStatsQueries.swift:175-177`), and no test, contract or GRDB, has
  two workouts ending at one instant, or two exercises in one workout for `recentlyLogged`.
- **An exercise twice in one workout** is one session and one "Last" line. This is GRDB-only
  (`StatsQueriesTests.swift:106-122`).

*Fix:* in `bests`, make the drop set the best estimate (for example 250 × 1) and add a done warm-up above the
expected best. Give one `e1RMByWeek` week a better drop set. Move the empty workout inside last week and expect 2.
Add a same-instant pair to `newestFirst`, and a two-exercise workout to `recentlyLogged`. Move the twice-in-one-
workout test into the contract. This is about 25 lines of LedgerTestSupport, and cheap before F07 builds its fakes.

**S3-SF3. `updateSets` leaves stale records, and its doc hands the repair to a caller that cannot do it.**
`Repositories/GRDBWorkoutRepository.swift:80-81`; `tasks/features/F13-workout-history.md:17,51`; open questions 4
and 5.
- F13's story is "editing a past set updates my PRs", and its brief says "recompute PRs … (F05 `updateSets`
  contract; add if missing)". The doc here says the opposite: "detecting them again … is the caller's (F13)".
- The caller has no way to do it. `PersonalRecords.detect` needs the bests **as they stood before the workout**.
  `bestE1RM` and `bestSet` are all-time and include the workout itself, and no query gives weight at reps.
- The same gap reaches `materialize`. ADR-004 emits `.materialize` again after a late envelope. A host that
  detects against `bestE1RM` then compares the workout with itself. Ties are not records, so the rebuild stores
  **no** records and `pr_count` 0 for a workout that set one.

Not Blocking: the F05 brief asks `updateSets` only for e1RMs, and the open question is declared. But the doc and
the missing hand-off must not merge as they are.

*Fix, in this PR:*
1. Reword `:80-81` to state the fact: "the records and `pr_count` are left as they are, and can be stale after an
   edit; see F13 inputs".
2. Write the input lines (question 11) into F13 and F10 with the two traps above.

*Follow-up before F10 starts* (see questions 4 and 5): a query for the bests before a given workout, and the
decision on where re-detection lives.

**S3-SF4. The Domain protocol docs say less than the contracts pin, and one line is now false.**
`LedgerDomain/Protocols/Repositories.swift:41-50,61-74`; open question 10.
`materialize` is documented as storing "its summary", which it does not. Nothing on the two protocols says:
newest first by end date, a limit below 1 gives none, `notFinished`, `missingRow`, `duplicateIdentifier`, which
set kinds each query counts, or that a history read resets the live-only fields. F07's fakes, and F10, F12 and
F13, are written against the protocol. S2's SF3 fixed the same gap for the other two protocols in its own PR.

*Fix:* copy the GRDB types' doc comments up, as S2 did. This is comments only, so it adds no code lines.

### Nit

**S3-N1. The history lists do not filter on `phase`, and the stats do.**
`Records/WorkoutRows.swift:129,137` against `Stats/GRDBStatsQueries.swift:203`.
A live row whose phase is not `finished` (a later version, or M4's sync) shows in `recent` and `workouts(in:)`
but in no stat, so a list of N + 1 sits beside a count of N.
`StatsQueriesTests.onlyLiveRowsOfFinishedWorkouts_count` checks the stats side only. *Fix:* add
`AND phase = 'finished'` to the two selections and a line to that test, or drop the filter from both.

**S3-N2. `slotUpdates` replace a slot's whole miss set with the caller's snapshot.**
`Repositories/GRDBWorkoutRepository.swift:151-152`; the doc at `:25-27` says materialising again is safe.
Materialising an older workout again with its original slots would clear misses recorded since. It is safe only
when the host builds `slotUpdates` from the stored program at that moment. *Fix:* say so in the doc, and add an
F10 input line: apply `MissTracking` to the program as stored now, never to a copy taken when the workout
started.

**S3-N3. `pr_count`, `volume_e7g_reps`, `done_sets` and `total_sets` are written, and nothing reads them.**
`Records/WorkoutRecords.swift:27-28,78-83`.
No protocol method returns a workout's records or its count. F13's list badge (its criterion 1) must call
`personalRecords(exerciseID:)` for each exercise and filter by workout. *Fix:* an F13 input line; or a
`personalRecords(workoutID:)` query in the question 5 follow-up, which `idx_pr_workout` already serves.

**S3-N4. A `PersonalRecordRecord` read from a row has the wrong `rowID`.**
`Records/LoggedSetRecords.swift:83`.
`position = 0` is a placeholder, defended by a comment ("a row read back is never written"). The next caller that
writes fetched records gets silent id collisions. *Fix:* keep the stored `id` text on the record and return it
from `rowID`, deriving it only in the writing initialiser.

**S3-N5. `updateSets`' doc promises more than the check does.**
`Repositories/GRDBWorkoutRepository.swift:83-84`, `Records/WorkoutRows.swift:185-190`.
"Held by another exercise" throws only when that exercise's set is live, as the duplicate within the workout. A
soft-deleted set of another exercise of the same workout is revived and moved. That is harmless inside one
workout, and right for `materialize`. *Fix:* reword to "used twice in the workout, or held by another workout".

**S3-N6. `GRDBExerciseRepository` keeps its own copy of `Row.readable`.**
`Repositories/GRDBExerciseRepository.swift:199-206`, `Records/ColumnReader.swift:124-141`. *Fix (optional):* call
the new helper.

**S3-N7. `SQL.count` sums the rows of a one-row `COUNT`.**
`Stats/GRDBStatsQueries.swift:209-212`. `fetchAll(…).reduce(0, +)` reads as if several rows could come back.
*Fix (optional):* `Int.fetchOne(…) ?? 0`, with the comment saying why the `nil` arm cannot run.

### Deviations

| Deviation | Verdict | Reason |
|---|---|---|
| New error `notFinished` (decision 2) | **Accepted** | Every range and order is keyed on `ended_at`, so a live or endless workout has no place in history. It is refused before the transaction, and clause `notFinished` pins it. A discard is `delete(id:)`. |
| Totals from the state, not from `summary` (decision 3) | **Accepted** | `summary` is `WorkoutEngine.summary(workout, prs:)`, a pure function of the other arguments. Columns copied from it could disagree with the rows. The parameter is then dead: question 1. |
| Slot updates for slots that are not stored are skipped (decision 4) | **Accepted** | The alternative is a foreign-key error that makes the workout impossible to store for good. It is logged with the slot id, and `misses_ofASlotNotStored_areSkipped` pins it. See N2 for the snapshot. |
| p95 of 20 runs (decision 19) | **Accepted** | It is the criterion's own wording, and stricter than the strategy's median of five. `timings[18]` of 20 sorted values is the 19th fastest. The slowest query has about 7× headroom. |
| Binary `.sqlite` fixture (decision 18) | **Accepted** | The brief's Definition of Done names the file. A real file also tests what a dump cannot: the header, page layout and `grdb_migrations`. I checked it (above). `fixture_isAtV001` would catch a regenerated or newer file. |
| `ColumnCodec.derivedID` moved out of `SlotMissRecord` (S2's miss ids) | **Accepted; the claim is verified** | The new function is the old body with the name as a parameter (`Columns.swift:51-57`, `SlotRecords.swift:94-96`). Independently, every miss id in the fixture equals RFC `uuid5(slot, week)`. `WorkoutRowDiffTests.swift:198` pins RFC 9562's own example. |

Also accepted: bests over `.working` and `.added` sets (question 6), `ended_at` as the date (question 7), and
`programUpdates` not applied (question 3), each subject to the category below.

### Open questions

Category: **(a)** settle now, in this slice or its PR; **(b)** hand off to a later brief; **(c)** Pete decides.

| # | Question | Recommendation | Category |
|---|---|---|---|
| 1 | `summary` is unused | Agree: keep the totals from the state. Drop the parameter in the protocol follow-up of question 5, before F07 writes a fake that carries it, not "when F10 next touches it". | (b) F05 follow-up before F07, else F10 |
| 2 | Who deletes after a late discard | Agree: the host calls `delete(id:)` on `.discardLog`, then compacts. F05 has what it needs. | (b) F17 item 2; F10 for the local host |
| 3 | `programUpdates` not applied | Agree to leave it. One constraint for F10: if a swap is to land with the workout, it must be in `materialize`'s transaction (about 15 lines in F05). A separate `replaceSlotExercise` call beside it is not atomic. | (b) F10 input 7 |
| 4 | `updateSets` does not re-detect records | Not in this slice, but before F13, and SF3's doc fix and input lines now. F13's brief already assigns it to F05 ("add if missing"). Re-detection needs question 5's query in its "before this workout" form. | (b) F05 follow-up, consumed by F13 |
| 5 | No `bestWeightByReps` | Add it before F10 starts, as a small F05 follow-up with a contract clause. Shape it for both callers: bests **excluding a workout, or before a date** (`bestE1RM` too). An all-time query makes a rebuild erase the workout's own records (SF3). It is a Domain protocol change, so it is serialized. | (b) F05 follow-up before F10 |
| 6 | Which sets count for the bests | Keep `.working` and `.added`: a best must be comparable with what `PersonalRecords.detect` (shipped in F02) lets set a record. Three sources disagree (criterion 5 "done sets", `F12-library-history.md:51` "only `.working`", the code), and the lifter sees the result in F12's header. Note also that `sessionCount` counts a warm-up-only workout. | **(c) Pete**, then align F12:51 and criterion 5 |
| 7 | A workout's date is `ended_at` | Keep it for this slice: it is the brief's indexed column, and one rule for every query. It is user-visible in two cases: a workout that crosses midnight, and one left open and finished the next morning, which lands on the wrong day and week. `started_at` is the other choice. Changing later costs an index migration and a contract change, so decide before F13 ships. | **(c) Pete** (not urgent) |
| 8 | Shape of the "Last" line | Keep: the count of done working sets, and the heaviest one's load and reps. It overstates a session with one short set ("5×5 @ 180" for four fives and a four), which is what rule 25's "Repeat last" wants. Name it in the PR description. | (a) |
| 9 | Unreadable workouts are not counted | Agree: nothing until a screen needs the message. | (b) F13, or F29 |
| 10 | Protocol doc comments | Do it now (SF4), as S2's SF3 did. | (a) |
| 11 | Input lines for F07, F10, F13, F17 | Write them at merge. F10 and F13 must carry SF3's two traps and N2; F13 also N3. | (a) orchestrator |
| 12 | p95 of 20 against the strategy's median of five | Reword testing-strategy §2.2 to the criterion. | (a) docs |

### Considered and not raised

- **code-review #2: materialising over a workout row that is deleted while its children are live.** `delete(id:)`
  always deletes the children with it, so only a partly applied sync or damage produces that state. A foreign
  writer is out of scope, as in S1 and S2. It is a line for F28's inputs.
- **code-review #4: `e1RMByWeek` and `lastPerformance` throw on one workout with a damaged `ended_at`,** where
  the lists leave it out. That is decision 16 and S2's split: an aggregate that silently drops a workout returns
  a wrong number, and a list does not. `DamagedWorkoutRowTests.swift:119` pins it. F12 must show the error
  state.
- **code-review #7: `Row.readable` catches every error.** The closure only decodes a row already fetched, so
  nothing but a `LedgerPersistenceError` can arise. S2's exercise list does the same.
- **code-review #8: `e1RMByWeek` reads every session of the exercise.** The notes time it at 0.8 ms on the host for
  about 170 sessions. A bound in SQL needs a week's first instant from `WeekCalendar`, which it does not offer.
- **code-review #9: two statements per slot in `writeMisses`.** A day has about five slots, on the finish path,
  once.
- **code-review #10: `SQL.bounds` duplicates `Selection.ended(in:)`'s arguments; `rpe_x2` via `intValue`.** The
  first is two lines. The second is S2's N8, settled there.
- **Whole-second dates.** `ColumnReader.date` accepts only `REAL` storage. The columns are declared `REAL`, so
  SQLite stores `811228800.0` as `real` (`materialize_writesTheDocumentedColumns` shows `typeof`).
- **Misses outside the program's weeks.** `Slot.misses` is not validated on load (`ProgramRows.swift:121`), so a
  stray week index cannot make the program unreadable.
- **A user-deleted workout that a rebuild brings back.** Revival is what a late finish needs (F04 input 6), and
  a rebuild only happens until the log is compacted.
- **Write time on the watch** (brief: "≤ 10 ms typical"). Not measured for `materialize` in this slice. A
  50-set workout is about 60 short statements in one transaction; F20 times a device.
- **The log line's `\(error)` has no privacy level** (`ColumnReader.swift:136`). It follows S1 and S2.
- **S2 fix round N-a** (a NUL clause in the contracts) is done here for workouts: clause `refusesNul`.

### The review points

1. **Module boundaries.** Clean. LedgerPersistence imports Foundation, GRDB, LedgerDomain, `os` and CryptoKit
   (moved from `SlotRecords` to `Columns`). The contracts use public API only: no `@testable`, no `Testing`.
   LedgerDomain has no changed line.
2. **Concurrency.** Clean. Both new types are `Sendable` structs over the queue with an injected `now`. No UUID
   source is needed, because record ids are derived.
3. **Error handling.** Nothing is swallowed. Refusals throw by name before or inside the transaction, and a
   skipped slot or row is logged with its id. SF1 is the gap.
4. **Design fidelity** and 5. **Accessibility.** N/A (no UI).
6. **Test quality.** Good. The tests assert stored values with the arithmetic written out, stamps from a
   `ManualClock`, and a statement trace for the transaction. There are no sleeps. The observation tests use the
   unbuffered stream from S2's N4. Weak spot: SF2.
7. **Brief compliance.** Table below.

### Criteria → evidence

| Criterion | Evidence | Verdict |
|---|---|---|
| 3. Five exercises, e1RM, records and misses in one transaction; a failure leaves no rows | `WorkoutRepositoryTests.materialize_writesEveryTable_inOneTransaction` (one `BEGIN IMMEDIATE`, one `COMMIT`; counts `1 5 19 2 17`), `materialize_computesE1RM` (19 sets against `OneRepMax.brzycki`, one literal), `failedMaterialize_leavesNoRows` (a trigger fails the first record insert after every other table was written; every row and stamp compared) | Met |
| 4. `lastPerformance` after 34 bench sessions | Clause `lastPerformance` (drop, added and undone sets ignored; a later workout with no done working set skipped; the 34th deleted) | Met; the shape for uneven sets is question 8 |
| 5. `e1RMByWeek(lastWeeks: 8)` over 10 weeks | Clause `e1RMByWeek` (two workouts in a week, an empty week, a 15-rep week, weeks 8 and 9 and next week outside); `StatsQueriesTests.e1RMByWeek_followsTheWeekStart` | Met with a deviation: "done sets" is read as done `.working` and `.added` sets (question 6) |
| 6. `weeklyVolume` of two weeks and the delta | Clause `weeklyVolume` (every kind counted, undone not, a workout on the week's first instant, one literal: 2,867.5 lb); `weeklyVolume_isExact` | Met |
| 8. Compaction after materialisation (S1 N9) | `WorkoutRowDiffTests.materializeThenCompact_keepsTheWorkout` | Met |
| 9. Each stats method under 50 ms at 20,000 sets | `StatsQueriesPerformanceTests.everyQuery_underBudget` asserts all nine methods. I ran it on the host only (pass). The simulator figures are the notes' | Met as far as I can verify; nightly lane only |
| 10. `observeRecent(limit: 10)` emits on materialise | `ObservationTests.observeRecent_emitsTheMaterialisedWorkout`, `observeRecent_emitsOnChange_only`; clause `observeRecent` | Met |
| 12. v001 data survives a v002 | `MigrationCompatibilityTests.v002_keepsTheData`, `fixture_isAtV001`, `open_readsAndWritesTheFixture`; written-out expectations | Met |
| ADR-007 exact columns | `materialize_writesTheDocumentedColumns`, the `inexactWeight` half of `failedMaterialize_leavesNoRows`, the `REAL` damage cases | Met |
| S1 and S2 rules: damage kept and logged, ids not taken over, NUL refused, statement order | `DamagedWorkoutRowTests`; clauses `otherWorkoutsIDs`, `duplicateIDs`, `refusesNul`; `delete_cascades_softly` | Met for exercises and sets; SF1 for records |

### PR size

**662 code lines added (7 removed), confirmed.** I counted the added lines of `git diff -U0 feat/F05-s2..f5ab3fb
-- LedgerKit/Sources/LedgerDomain LedgerKit/Sources/LedgerPersistence` that are neither blank nor whole-line
comments. Per file: `GRDBStatsQueries` 162, `WorkoutRows` 139, `WorkoutRecords` 123, `LoggedSetRecords` 103,
`GRDBWorkoutRepository` 94, `ColumnReader` 31, `Columns` 8, and 1 each in `LedgerPersistenceError` and
`SlotRecords`. LedgerDomain: 0.

It is over the 500 target and under the ~1,000 split threshold, and the notes name the split considered
(repository, then stats). **Complies with §10. No split is warranted:** the stats contract can seed nothing
without the repository, so the second PR would be about 160 lines behind a second full gate. SF1's fix adds
about 10 lines; SF2 to SF4 add none to the count.

### Verdict

**Approved for G3: 0 Blocking, 4 Should fix, 7 Nits.**
- Criteria 3, 4, 5, 6, 9, 10 and 12 each have a test that fails when the behaviour is wrong. The write path is
  one transaction, exact, and idempotent.
- SF1 is a 10-line guard and one clause, and should land in this PR: it is the one place the "never taken over"
  rule does not hold. SF2 and SF4 are cheap now and expensive after F07 builds fakes on the contracts. SF3 is a
  doc line and input lines now, and a follow-up before F10.
- Two questions need Pete: which sets count for the bests (6), and whether a workout's date is its end (7).
  Neither blocks the merge, because the code takes the conservative reading and the contract names it.
- The G5 rule applies: this PR carries product decisions (6, 7), so the orchestrator stops for Pete before
  merging, or records why they can wait.

# Follow-up: records review

Reviewer pass on `feat/F05-records` at `aca3a82`, diff `git diff efe0691..aca3a82` (51 files), against product
decisions #25–#27 and the notes' "## Follow-up: records (decision #27)". Scope: `RecordReplay`, its callers in
`GRDBWorkoutRepository`, `bests(before:for:)`, the `PersonalRecordRecord` and `SyncedRecord` changes, the Domain
additions in `PersonalRecords`, the two protocol changes, the contracts, the four briefs' input lines, and the edits
to the tester's suites. I changed no code or test.

### What I ran

- **Host tests** on a `git archive aca3a82` copy in my scratchpad (`f05rec-g3/copy`), so the tester's worktree was
  not disturbed. In the default lane, `LedgerPersistenceTests` and the `PersonalRecords` Domain suites pass.
- **The nightly lane**, run alone:
  - `HistoryModelAdversarialTests` and `HistoryCloseoutAdversarialTests`: 8 tests, pass;
  - `RecordReplayPerformanceTests`: passes alone. It **failed** once when I ran it beside every other persistence
    suite, as did S2's catalog timing tests. That is the contention risk of open question 3.
- **An independent invariant probe** (throwaway, not committed). Six seeds × 120 random operations each:
  - new workouts, and rebuilds under an existing id that move the start or change the exercises;
  - `updateSets` and `delete`;
  - starts that collide exactly; drop, warm-up, added and undone sets; reps 1–14; 10 % deloads.

  After every operation the probe compared every live record and every `pr_count` with a from-scratch replay. The
  replay sorted history by (start, id text) and folded `PersonalRecords.Bests.include` and `detect(now: start)`,
  written from the protocol docs and not from the SQL. **0 mismatches in 720 writes.** The same probe found R-SF1.
- **`EXPLAIN QUERY PLAN`** of the walk, the bests, the stored-records read and the count check (below).
- **A stamp probe:** after editing the first of 30 bench workouts, **all 30** workout rows had a new `updated_at`
  (R-SF2).
- **The 461-line count**, with my own script (see "Size").

**Line-by-line reading.**
- **Transactions.** Each of the three writes is one `queue.write`. `materialize` reads its scope, writes its rows,
  replays, then writes misses (`GRDBWorkoutRepository.swift` `materialize`). `updateSets` and `delete` do the same.
  Every read the replay makes runs inside that transaction.
- **Scope.** The scope is the union of:
  - the stored workout's live exercises and the exercises of its live records (`RecordReplay.swift:71-79`);
  - the exercises of the new state (`:90-98`).

  It starts from the earlier of the stored place (when that workout is live and finished) and the new place. That
  is **sufficient**: records of exercise E can change only in workouts at or after the earliest place whose sets of
  E changed. It is **minimal** too. `updateSets` narrows it to the edited exercise (`:84-88`), which is right,
  because the workout cannot move and its other rows keep their sets.
- **Revival.** A deleted workout has no live rows, so its stored place is `nil` and the scope starts at its new
  place, where it had no influence before.
- **Deletion.** `delete` soft-deletes the workout's own records with its rows, then replays from its place.
- **Counts.** `pr_count` is recounted for the written workout, and for every workout with a found or a stored
  record in scope. That set is complete: a workout outside the scope keeps all of its records.
- **The rule.** `found` is `detect`'s old rule, step for step.
  - The ceiling is the heaviest prior weight at the same or more reps; on a tie the one with more reps is met
    first, because the scan goes from most reps down and compares strictly.
  - Among the workout's weights at each rep count, the heaviest that beats its ceiling wins; on a tie, more reps.
  - The estimate needs a prior estimate. Ties are not records.

  F02's and the tester's 26 `detect` tests pass unedited.
- **Grouping.** The walk's grouping (per workout, exercise and rep count: `MAX(weight_e7g)` and
  `MAX(e1rm_e7g)`) is exactly the tally that `found` reads.
- **Exactness.** The stored `e1rm_e7g` is `OneRepMax.brzycki(...).e7g()`, the same whole-gram value `detect`
  computes, so `Int64` and `Weight` order alike (ADR-007). No decimal arithmetic runs in the walk.
- **#25 and deloads.** `SQL.recordKinds` serves both the walk and the bests. A deload is skipped for records, and its
  tally still raises the bests (`Walk.close`, `RecordReplay.swift:254-270`), as `Bests.include` does.
- **Determinism and ids.**
  - The walk is ordered by start, id, exercise and reps. Scope ids are sorted. Upserts follow walk order and soft
    deletes follow id order.
  - Row ids are `uuid5(workout, "personal_record <exercise> <kind>")`, unique because `found` returns at most one
    record of each kind.
  - S3's position-derived rows are in the stored set, match no new id, and are soft-deleted when their workout is
    next written.
- **Indexes.** The walk and the bests enter through `idx_wex_exercise_workout`, then the workout primary key and
  `idx_logged_set_wex`; only `GROUP BY` and `ORDER BY` use a temporary B-tree. The stored-records read uses
  `idx_pr_exercise`, and the count check `idx_pr_workout` per workout. No history table is scanned bare, which
  `QueryPlanTests` also pins.

### Blocking

None.

### Should fix

**R-SF1. `bests(before:for:)` counts the workout's own stored copy when that copy starts earlier.**
`LedgerPersistence/Stats/GRDBStatsQueries.swift` (`bests(for:before:in:)`: `(workout.started_at, workout.id) <
(?, ?)` has no `workout.id IS NOT ?`); `LedgerDomain/Protocols/Repositories.swift:129`;
`tasks/features/F10-active-workout.md:154` ("The workout itself is never counted, stored or not").
- When the workout is stored at an earlier start than the state passed (a rebuild whose start moved later), the
  stored copy sorts before it and its sets count.
- My probe hit this 9 times in 720 writes. **Every** mismatch between "detect against `bests(before:)`, then
  materialise" and the stored records was this case. All fresh workouts matched.
- The store's own replay is unaffected: it runs after the workout's rows are rewritten, so the old copy no longer
  exists. That is why the invariant probe found 0 mismatches.

So the stored records are right, but the public query does not do what F10's line promises. A rebuild's "PR!" or
receipt would then disagree with what is stored. A start that moves is rare: it takes an F17 merge that revises
the start.

*Fix:*
- Add `AND workout.id IS NOT ?` (the position's id) to the bests query. The replay is unchanged by it, because the
  written workout is at or after its start.
- Say "never counts `workout` itself" in the protocol doc.
- Add a `bestsBefore` case: the twin stored at an earlier start, then asked about at a later one.

This is about 2 lines and one clause, best made before F07 writes a fake against it.

**R-SF2. Every write recount stamps the `updated_at` of each workout row it touches, on a synced table.**
`LedgerPersistence/Records/RecordReplay.swift:210-216` (`UPDATE workout SET pr_count = …, updated_at = ?`);
`tasks/features/F28-icloud-sync.md:55` (only `personal_record` is called derived and local).
`pr_count` is derived data on the synced `workout` row. Fixing a typo in the first of N workouts of a lift changes
the counts of up to N − 1 later workouts. My probe: all 30 of 30 rows were restamped.
- Under M4's row-level last-writer-wins, that one edit uploads every later workout.
- Each of those copies can overwrite a real concurrent edit of the same row on the other device (a renamed workout,
  an edited set total).
- Both devices derive the same counts anyway (F17's new line), so the stamp carries no information.

*Fix:* decide this now, while no workout has synced:
- **either** leave `updated_at` alone for a recount: the count is derived, and each device derives it;
- **or** keep the stamp, and write in F28's inputs that `pr_count` is excluded from the synced fields and
  recomputed on receipt.

The first is one token, and keeps S3's rule that only a content change moves `updated_at`. Either way, add the F28
line.

### Nit

**R-N1. The finish screen's records match the stored ones only if F10 passes the start as `now`.**
`tasks/features/F10-active-workout.md:150-156`, `LedgerDomain/Engine/WorkoutEngine.swift:87` ("the same ones"),
`LedgerDomain/Rules/PersonalRecords.swift:15` ("`achievedAt` is `now`"). `detect` stamps the `now` it is given, and
the store stamps the start. *Fix:* in F10's input 3, write `detect(workout: state, against: bests, now:
state.startedAt)`, or say that only the kinds and values agree.

**R-N2. No contract clause moves a stored workout's start later, or drops an exercise in a rebuild.**
`RecordReplayTests.swift:82,98` pin both, but only for GRDB. F07's suggested fake replays from scratch and passes
anyway. A fake that replays incrementally from the new place would pass every clause while wrong. *Fix
(optional):* one step in `recordsFollowEdits` that materialises the typo workout again a day later.

**R-N3. A deload sets no record, yet can stand as the "previous" a later record beats.** This follows decision #27
and the contract (255 × 3 "over 250 × 5", the deload). It is correct, but F12 and F13 should expect a record whose
"previous" comes from a deload. *Fix:* an F12 and F13 input line, if the session log shows "over …".

### Deviations

| Deviation | Verdict | Reason |
|---|---|---|
| `materialize(_:slotUpdates:)`: `summary` and `prs` dropped (decision 1) | **Accepted** | Records are now a function of history, so a caller-supplied list could only disagree. S3-1's refusal is moot, because nothing names a workout. It also settles S3 open question 1. |
| `achievedAt` = the workout's start (decision 2) | **Accepted** | A rebuild or an edit has no "now at finish"; the start is the workout's date under #26. See R-N1 for F10's call. |
| `personalRecords` ties by workout id, then kind (decision 3) | **Accepted** | Starts now tie routinely, and the old key (derived row id) was arbitrary. |
| Row id = v5 of (workout, exercise, kind) (decision 4) | **Accepted** | Unique by construction. A changed value updates its own row, so stamps move only on change. The table is local, so the re-keying of S3's rows is invisible. |
| Strict reads in the walk (decision 7) | **Accepted** | Judging a record against history the app cannot read is what #27 forbids. Only foreign damage triggers it, and F10's log stays uncompacted. |
| `SyncedRecord.write` builds the upsert once per write (decision 8) | **Accepted** | Same SQL. The statement is rebuilt whenever the column set changes (`statement?.columns != columns`), so mixed column sets stay correct. |

### Forced edits to the tester's suites

From a reviewer's side, **no behavioural coverage was lost**:
- The three deleted tests (`foreignRecord_isRefusedByName`, `recordOfAnotherWorkout_…`, `recordOfAnUnknownWorkout_…`)
  pinned behaviour of the `prs` argument, which no longer exists. `records_nameTheirWorkout_andAreCounted` keeps
  their invariant part.
- The two removed model faults describe behaviour that is now required (`recordsByWorkoutDate`) or inexpressible
  (`recordsInGivenOrder`). The four new faults cover the real ways to be wrong under #27, and each breaks its own
  clause.
- The model (`HistoryModel.redetect`) is a from-scratch replay written from the protocol, independent of the SQL.
  My probe is a second, separate one, and agrees.
- One loss, and it is acceptable. `StatsWorstCaseAdversarialTests` no longer times `weeklyVolume` over 20,000
  distinct weights, now about 450. That shape was unrealistic, and it flaked (S3-N4). Exactness does not depend on
  how many weights there are, and `weeklyVolume_isExact` covers it.

The tester's own audit of these edits is open question 6.

### Domain API

- **Kept small for what it must do.** RecordReplay lives in LedgerPersistence, so `found`, `Tally` and `Found` must
  be visible across modules. `package` access would not hide them, because the Feature targets are in the same
  package. `Bests` and `detect(against:)` are what F10 needs, and `bestSet(of:)` serves F12.
- **Additive except `materialize`.** `materialize` has no consumer yet (F07 and F10 are unbuilt), so this is the
  cheapest moment to change it.
- **`bests(before: WorkoutState, …)`** uses only the start and the id. Passing the state lets F10 hand in the live
  workout unchanged, and serves a rebuild. Fine, given R-SF1.
- **Input lines.** F07, F13 and F17 are accurate. F10 is accurate except item 3's "never counted, stored or not"
  (R-SF1) and the finish screen's `achievedAt` (R-N1). F28 has no line yet (R-SF2).

### Open questions

Category: **(a)** settle now; **(b)** hand off (brief named); **(c)** owner decides.

| # | Question | Recommendation | Category |
|---|---|---|---|
| 1 | `achievedAt` is the workout's start | Keep. It follows #26 (Pete's), and a rebuild or an edit has no other stable instant. Tell F10 to pass the start (R-N1). | (a) |
| 2 | Strict reads in a write | Keep. A false record is worse than a finish that waits for a repair, and only foreign damage reaches it. F10's and F13's lines already say what to do. | (a) |
| 3 | Timing margin (worst case 41–48 ms of 50, Debug) | Accept: the shape (400 workouts, 20,000 sets of **one** lift, every workout a record) is far past real use, and the realistic finish costs about 1 ms per lift. It is still a flake risk: I saw it fail once under CPU contention. If the nightly flakes, add a write budget for a history edit to architecture §15 (an edit is a user action on the phone, not a frame) instead of shrinking the shape. F20 times a device in Release. | (b) F20; a new §15 budget is the orchestrator's |
| 4 | Records written before this PR | Nothing now: no shipped database holds workouts, and a write re-keys them. F17's line covers M4 writes that bypass `materialize`. Add R-SF2's F28 line. | (a) |
| 5 | Domain API beyond the query | Keep (see "Domain API"). | (a) |
| 6 | Tester-owned edits | The tester audits them in this round. From my side no behavioural coverage was lost (above). | (a) tester |
| 7 | F13's badge has no `personalRecords(workoutID:)` | F13 adds it if it needs it. `pr_count` is now right, but no API reads it either. | (b) F13 |

### Considered and not raised

- **The scope reads the stored place leniently** (`try?` on `started_at`, `RecordReplay.swift:68`). A damaged stored
  start drops the old place from the scope. Only foreign damage produces one, and the write then repairs the row.
- **A `DatabaseQueue` blocks reads during a write.** The worst-case edit holds it for about 50 ms (Mac CPU). Edits
  happen on the phone, in History, as a user action. F20 will tell whether a device needs a pool.
- **Two statements per write even when nothing changed** (the count check). The no-op path runs no `UPDATE`, and
  `WorkoutRowDiffTests.materializeTwice_writesNoRow` checks that no stamp moves.
- **`Tally.add` keeps a `nil` estimate for sets above 12 reps** while still raising the weights: it matches `detect`
  and decision #4.
- **The bests query takes an exercise list of any size.** It is bounded by one workout's exercises (≤ 10), far below
  SQLite's variable limit.

### Size

**461 code lines added, 104 removed, 357 net: confirmed.** My script counts the added and removed lines of `git diff
-U0 efe0691..aca3a82 -- LedgerKit/Sources/LedgerDomain LedgerKit/Sources/LedgerPersistence` that are neither blank
nor whole-line comments, which is the S3 method. Under the 500 target, so §10 is met with no split. R-SF1 and R-SF2
add about 3 lines.

### Verdict

**Approved for G3: 0 Blocking, 2 Should fix, 3 Nits.**
- The invariant holds on every write path. An independent from-scratch replay agreed on all 720 random writes,
  including moved starts, tied starts, revivals, deloads and every set kind.
- The rule is `detect`'s, in exact integers. The scope is sufficient and minimal, and every query is indexed.
- R-SF1 is a two-line fix to new public API, best made before F07 writes a fake against it.
- R-SF2 is a design choice for synced rows that costs nothing now and much after M4. It needs a one-line decision
  and an F28 line.
- Nothing here needs Pete: #25–#27 are his, and this PR implements them as written.
