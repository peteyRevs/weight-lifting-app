# Slice S1 — round 1

Independent adversarial pass over `feat/F05-persistence` at `a191aab` (S1: schema v001, exact columns, event
store, settings, observation bridge; includes F32). I wrote the tests from the brief (criteria 1, 7, 8 and
"Inputs from F04"), the implementation notes' slice plan and its "Weight encoding", "Date encoding" and
"Event store vs the contract" sections, ADR-002, ADR-004 with its amendments, ADR-007, and the public
interfaces of `LedgerPersistence` and `LedgerTestSupport/Engine`. I read "## Slice S1" and the product code
only after the tests were written, to find root causes and to separate documented decisions from findings.
No product code was edited; product-code mutants (below) were applied one at a time and reverted with
`git checkout`.

**Convention** (as in F04): a failing test is a bug or a minor bug and stays in the branch as a regression
test; a spec question is pinned by a passing test marked "(documents)".

## What I wrote

42 new tests (5 property tests on `PropertySeed.all`, tagged `.property`) in 9 files under
`LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`. None is `.slow`: the whole set runs in about 2 s on the
host. No wall-clock assertion; the observation tests synchronise on the stream and on writer barriers only.

| File | Tests | What it attacks |
|---|---|---|
| `ExactWeightColumnAdversarialTests` | 6 (1 property) | `_e7g` against an integer oracle: every 0.01 lb from −100 to 1,500 lb (h × 45,359,237), every 10 g to 500 kg and every gram to 50 kg, deload/drop loads on lb and kg steps, every Brzycki e1RM and set volume, the `Int64` edges ±1 unit, non-representable values of both signs (⅛ lb, 0.001 lb, ⅓ g, 10⁻³⁸ g) refused with the unrounded value, and a seeded "stored iff whole count in `Int64`" oracle over any exponent |
| `EventStoreDateAdversarialTests` | 5 (2 property) | stamps and every payload date (`started`, `setLogged`, `restStarted`, `restExtended`, `finished`) bit for bit: `distantPast`/`distantFuture`, ±`greatestFiniteMagnitude`, subnormals, −0, the F04 stamps and their ulp neighbours, any finite bit pattern; `wall_clock` holds the same double; SQL order vs `EventEnvelope <`; ±∞/NaN; strings spelled "NaN"/"+Infinity" |
| `EventStoreBatchAdversarialTests` | 8 | a rival mid-batch (no row, no newly listed workout, `highestSeq` unchanged), two rivals (the first given is named), duplicates within a batch, copy-then-rival, `highestSeq` on 8 seq sets across 2⁶³, compaction across ten workouts, 16 racing appends with a contested key, a reader racing a writer |
| `EventStoreModelAdversarialTests` | 2 (2 property) | the store against a dictionary model of the protocol's doc comments over random appends (duplicates, rivals, seqs 1…`UInt64.max`) and compactions, checking every result, log, `highestSeq` and listing after each step; every event kind with random weights, reps, durations and names reads back `==` |
| `EventStoreMutantAdversarialTests` | 2 | 13 plausible `GRDBWorkoutEventStore` slips on the real schema (bytes compared, since-1970 or millisecond dates, stamp read from the column, no transaction, `INSERT OR IGNORE`, stamp ignored, signed `MAX(seq)`, sorted return, non-finite stamps refused, lower-case compaction, no non-finite decoding) must each fail the contract or the GRDB suite's decoded-comparison check |
| `FileDatabaseAdversarialTests` | 5 | all 12 contract clauses on a WAL file; a copy taken mid-session without `-shm` (what a crash leaves) reopens with every committed batch, and the main file alone has none of them; a torn last WAL frame loses exactly the last batch; protection on the directory, file, `-wal` and `-shm` on every platform; a path with spaces and `%` |
| `SchemaAdversarialTests` | 6 | migrating twice with rows present; `integrity_check`/`foreign_key_check`; the declared foreign keys are the brief's with its delete rules; every child table refuses a dangling reference (`SQLITE_CONSTRAINT_FOREIGNKEY`); every foreign-key column leads an index; `UNIQUE` appears in no DDL but `uidx_event_key`, primary keys are single `id` columns, `workout_event` has no foreign key |
| `ObservationAdversarialTests` | 4 | the bridge emits the current value, then a change; cancelling the consumer or dropping the stream (iterated or never iterated) stops fetching and frees the fetch closure; settings round-trip exactly (⅓ lb bar, 10⁻⁷ g digits) through a second repository; `observe` emits another writer's save and `.default` after the row is deleted |
| `PayloadEvolutionAdversarialTests` | 4 | finding 1 (two "(documents)" tests); `append` in a task cancelled before or while it runs stores all or nothing |

## Results

- **Host** (`swift test`, part of `scripts/check.sh --fast`): all 42 pass. `LedgerPersistenceTests` 70 tests
  (28 existing + 42), `LedgerDomainTests` 687, `check.sh --fast` OK (log: scratchpad `f05s1-g2-fast.log`).
- **Full gate** (`scripts/check.sh` through `sim-lock.py`, Xcode 27.0, 333 s): **OK**. Format, lint, package
  graph and pins, and script tests pass; iOS `PR` 17/17 targets (905 tests: 901 passed, 4 skipped) and
  watchOS `PR-Watch` 8/8 targets (882 tests: 878 passed, 4 skipped). `LedgerPersistenceTests` on each
  simulator: 68 passed, 2 skipped by design (the protection read-back and the nightly timing); all 42 new
  tests pass on both, `protection_isNeverAnotherClass` included. Coverage: LedgerPersistence 100.00 %
  (333/333), overall 98.81 %. Log: scratchpad `f05s1-g2-check.log`.
- **The moved contract** is at least as strong as F04's. Its ten F04 clauses have the same bodies with
  equivalent builders (`EngineAdv.env`/`extend`/`start` → `EventBuilders.envelope` and `.restExtended(amount:
  .seconds(…))`); F05 added `fullWidthSeq`, `nonFiniteIsStored` and a second exact-read-back envelope. F04's
  14 mutants are all still killed (`EventStoreMutationAdversarialTests`, in the 687), and the in-memory
  reference still passes. Against my 13 GRDB mutants the contract alone kills 12. The survivor,
  `comparesBytes`, cannot be caught by a store-agnostic contract, which only ever hands a store its own
  encoding; the GRDB suite's `append_comparesDecodedEnvelopes_notBytes` kills it. The new stamp is
  load-bearing: a store that keeps `wall_clock` as seconds since 1970 and reads the stamp back from it passes
  F04's single-envelope clause and fails only on the new `10.493_826_8` envelope; 5,037 of 10,000 realistic
  stamps (the fixture start plus up to two hours) change through seconds since 1970.
- **My tests against product-code mutants** (one at a time, reverted): 6 of 9 killed: rounding instead of
  refusing a weight, signed `highestSeq`, `wall_clock` as seconds since 1970, foreign keys off, WAL off, and
  a wrong decode scale for one count. The 3 survivors:
  - removing `protect(…)`: a new directory created with the class passes it on to its files, so my
    new-directory test cannot see it. The existing reopen test fails with this mutant, but only on the host
    (finding 2);
  - not calling `cancellable.cancel()` in `onTermination`: equivalent, since releasing the closure releases
    the `AnyDatabaseCancellable`, whose `deinit` cancels;
  - dropping `removeDuplicates()` in settings: an optimisation that `bufferingNewest(1)` makes unobservable.

| Class | Count | Findings |
|---|---|---|
| bug | 0 | |
| minor bug | 0 | |
| spec question | 3 | 1, 2, 3 |

---

## 1. spec question — Stored JSON payloads have no version; a Codable change in LedgerDomain makes stored rows unreadable

`workout_event.payload` and `settings.payload` are the synthesized `Codable` of `EventEnvelope` and
`Settings`, with no version and no committed fixture of their shape (`EventCodableTests` checks round trips
only, so a rename still passes). Any change to that shape silently strands the rows written before it:

- **Event logs.** One payload the current codec cannot decode makes `envelopes(for:)` throw for its whole
  workout, so the readable envelopes next to it are lost too and replay (ADR-004 rule 6, recovery on launch)
  cannot start. A redelivery of that key throws `DecodingError`, not a duplicate or a conflict. The log stays
  in `uncompactedWorkoutIDs()`, so the host meets it on every launch. F04 has already renamed payload labels
  once (`setLogged(…, at:)` → `doneAt:`, F17 item 7); an app update that lands with a live or unmaterialised
  log (a watch app updates on its own schedule) is enough.
- **Settings.** F28 plans `Settings.iCloudEnabled: Bool`. With synthesized decoding, every existing settings
  row then fails `load()` with `keyNotFound`, and `observe()` finishes without emitting, on every launch.

**Repro** (both pass, "(documents)"): `PayloadEvolutionAdversarialTests.oneLegacyPayload_makesTheWholeLogUnreadable`
stores a start and a skip, then a row whose `setLogged` uses the pre-rename key `"at"`:
```swift
await #expect(throws: DecodingError.self) { try await store.envelopes(for: Contract.workout) }
await #expect(throws: DecodingError.self) { try await store.append([legacy]) }
#expect(try await store.uncompactedWorkoutIDs() == [Contract.workout])
```
`settingsWithoutANewerField_failLoad` removes one key with `json_remove(payload, '$.watchBuzz')`:
`load()` throws `DecodingError`, and `observe()` emits nothing.

**For the orchestrator:** the schema is frozen from S1, so decide now which of these holds: (a) commit golden
JSON fixtures of every `WorkoutEvent` case and of `Settings`, so a breaking change fails a test and must ship
with a row migration (S3's `fixtures/db-v001.sqlite` could carry `workout_event` and `settings` rows);
(b) a payload version, added as an additive column when first needed, with the decoder dispatching on it;
(c) tolerant decoding (`decodeIfPresent ?? default`) for `Settings`, which is a LedgerDomain change. What the
host does with an unreadable log is F17's to specify.

## 2. spec question — The file-protection assertion runs in no CI lane

`DatabaseTests.open_protectsTheFileAndItsCompanions` is `.disabled` on the simulators. The skip's premise
holds, and it hides no failure on the Mac, but nothing in CI runs the test:

- **Premise checked.** A probe built for each simulator and run with `simctl spawn` (under the lock) sets
  `.completeUnlessOpen` on a new directory and file: `attributesOfItem(…)[.protectionKey]` reads back `nil`,
  and `URLResourceValues.fileProtection` reads `.completeUntilFirstUserAuthentication` whatever was
  requested. So the simulators keep no class.
- **Mac host.** The test passes, and my `protection_isNeverAnotherClass` shows the requested class on the
  created directory, the file, `-wal` and `-shm`.
- **But** `pr.yml` and `nightly.yml` run only `check.sh`'s simulator steps, and the Device plan runs only
  `LedgerHealthTests`. So only a local `check.sh --fast` asserts protection, and a change that drops or
  breaks `protect(…)` passes CI (my mutant above: the reopen test is the only one that sees it, and only on
  the host).

**Repro:** `grep -n "swift test\|--fast" .github/workflows/*.yml` finds nothing; `TestPlans/Device.xctestplan`
lists only `LedgerHealthTests`.

**Options:** run a tolerant form everywhere (as `FileDatabaseAdversarialTests.protection_isNeverAnotherClass`
does: exact on the host, "`nil` or the requested class" on a simulator, so a wrong class still fails), add
`DatabaseTests` to the Device plan when F20 runs it, or add the host `swift test` step to CI (F01's area).

## 3. spec question — `personal_record` has no sync status

S1 adds `personal_record` with `created_at`/`updated_at`/`deleted_at`, as a synced table would have. But
architecture §7's table and F28's list of synced tables (`exercise` … `logged_set`, `settings`) predate it
and do not name it. Decide whether PR rows sync (they are then CloudKit-shaped already) or are derived and
recomputed from `logged_set` on a new device, and record it in architecture §7 and F28. No test: nothing
observable in S1.

---

## Attacked and held

- **Exact weight columns.** Every weight the rules make round-trips, and the stored count equals an integer
  computation (h × 45,359,237 for h hundredths of a pound; g × 10⁷ for g grams), so encode and decode are not
  merely consistent with each other. `Int64.min`/`.max` and ±1 unit round-trip; one unit beyond either edge,
  NaN, and exponents that overflow `Decimal` once shifted are refused as `inexactWeight(value)` with the
  unrounded value. The seeded oracle over exponents −30…14 with trailing zeros never disagreed.
  *Noted:* the codec relies on `Decimal` staying compact. A hand-built non-compact value
  (`Decimal(_exponent: −8, …, _mantissa: 450)`, i.e. exactly 45 units) prints `"45.0"` once shifted and is
  refused. No public `Decimal` operation I tried (construction, `+`, `−`, `*`, `/`, `NSDecimalRound`, string
  and JSON parsing, `Decimal(Double)`) produces one, so it is unreachable.
- **Dates.** `wallClock` and every payload date read back bit for bit, −0 and subnormals included, for any
  finite double. `wall_clock` holds the same double. `ORDER BY wall_clock, device_id, seq < 0, seq`
  reproduces `EventEnvelope <` exactly (seqs across 2⁶³, random device UUIDs, forced stamp ties). ±∞ and NaN
  are stored with `wall_clock` `NULL` and the payload strings `"+Infinity"`/`"-Infinity"`/`"NaN"`; string
  fields spelled that way stay strings. *Notes:* `NULL` sorts first, so SQL order puts a +∞ stamp before
  every finite one; the column is informational, and nothing orders by it. Any future SQL on `seq` (F17's
  "everything from your device with seq > N") must compare unsigned, as `highestSeq` does.
- **NaN re-append.** It throws `conflictingEnvelope` and rejects the batch; this is S1 decision 9 and F17's
  "Inputs from F05", pinned by the contract and by my non-finite test.
- **Event store.** A conflict anywhere in a batch leaves no row, no newly listed workout and no `highestSeq`
  change; with two rivals, the first given is named. Duplicates within a batch are stored and returned once,
  at their first position. An empty batch is a no-op. `highestSeq` is the unsigned maximum on every seq set
  tried, seq 0 included. Compaction across ten workouts unlists exactly its own; unknown and repeated
  compactions are no-ops, and a resend after compaction is new again. 200 seeded random interleavings match
  the model after every step.
- **Concurrency.** Sixteen racing appends with a contested key: exactly one version is stored, every task
  that carried it succeeds, every other one throws `conflictingEnvelope` and stores none of its batch, and
  each envelope is returned to exactly one task. A reader racing a writer saw only whole batches of 10 (a
  diagnostic run saw 0, 10, 20, … 200). An append in a cancelled task throws `CancellationError` and stores
  nothing (200 of 200 runs); none ever stored part of a batch.
- **Crash, WAL.** A copy of the database and `-wal` taken while the queue is open, without `-shm`, reopens
  with all 50 envelopes, `integrity_check` `ok`, still in WAL; the main file alone holds none of them, so the
  WAL did the work. A torn last frame loses exactly the last batch; it re-appends as new. *Noted:* GRDB's WAL
  setup sets `synchronous = NORMAL` (read back as 1). Committed data survives an app crash (above); a power
  loss may drop the newest commits, in commit order, so a lost compaction never outlives its
  materialisation.
- **Schema.** Migrating again (twice, with rows) changes nothing; the dump matches the committed fixture; the
  brief's eight foreign keys plus `personal_record.workout_id` are declared with the brief's delete rules,
  enforced and indexed; no `UNIQUE`
  beyond `uidx_event_key` (CloudKit-shaped, ADR-002); `workout_event` has no foreign key; paths with spaces
  and `%` open and reopen.
- **Settings and observation.** Defaults before a save; exact round trip through another repository; another
  writer's save and a deleted row are observed. The bridge emits the current value first; cancelling the
  consumer or dropping the stream stops all fetching after the writer's barrier, and frees the observation's
  fetch closure (0 leaks in 1,000 diagnostic runs of each path).
- **Store judges keys, not contents.** *Noted:* an envelope whose `Weight` is NaN cannot be encoded
  (`DecimalText` throws), so `append` throws `EncodingError` for its batch where the in-memory reference
  would store it. No peer can send one (decoding rejects `"NaN"`) and no rule makes one, so it is
  unreachable today.

**Verdict:** G2 can close for S1. No bug or minor bug found; criteria 1, 7 and 8 hold on the host and both
simulators, and the moved contract is stronger than F04's. Findings 1–3 are spec questions for the
orchestrator; finding 1 (payload shape is unversioned while the schema is now frozen) is the one to decide
before S2/S3 build on the settings and event payloads.

---

# Slice S1 — round 2 (close-out)

Scoped close-out over `feat/F05-persistence` at `2bcb442` (fix round `a2d8897` plus a merge of main). I attacked
only the fix round's new surface: `payload_version`, unreadable event rows and `unreadableCount(for:)`, tolerant
`Settings` decoding and the settings row's version, and the Device plans. I read round 1, the three "Orchestrator
decision (2026-09-30)" items and the fix-round notes, and `git show a2d8897`. No product code was edited: the 19
mutants below ran one at a time in a copy of `LedgerKit` in the scratchpad, never in the worktree.

## What I wrote

11 tests (1 property test on `PropertySeed.all`, tagged `.property`) in 2 files under
`LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`, about 0.3 s on the host.

| File | Tests | What it attacks |
|---|---|---|
| `PayloadVersionAdversarialTests` | 4 (1 property) | both writers store `payload_version` as the integer 1 (a batch across workouts with ±∞ and NaN stamps and seqs `.max` and 2⁶³; the settings insert and upsert), and the column is `NOT NULL` with no default in both tables, so an insert that omits it fails; 200 seeded logs over 3 workouts and 2 devices with random rows damaged in 17 ways (later, zero and negative versions, `Int64` extremes; a version stored as text or a blob; empty, non-UTF-8, truncated, `[]`, `null`, `{}`, integer and real payloads; a renamed key) or changed harmlessly (the same JSON as `TEXT`, a version written `'1'` or `1.0`): each workout's readable envelopes in insertion order, its exact unreadable count, `highestSeq` over every row, the listing, and a resend of the whole log that stores nothing and changes no byte of any row; a copy, a rival and a rival pair on an unreadable key; compaction of a log with unreadable rows |
| `SettingsDecodingAdversarialTests` | 7 | version 1's keys are exactly the seven fields; each key missing alone loads its default with the rest as saved (`load` and `observe`); unknown keys at the top and inside an inventory are ignored; a wrong type in each key fails the whole load and keeps the row; `null` values (documents); versions 0, −1, 2, 7 and `Int64.max` fail `load` and `observe` by name and are kept, and a save over them writes version 1; a damaged row fails `load` and `observe` instead of trapping (exit test, host only: finding 4) |

## Results

- **Host** (`scripts/check.sh --fast`, run while the Mac's screen was locked; log: scratchpad `f05r2-fast.log`):
  **fails on 2 tests, both expected.** Format, lint and the script tests pass. `LedgerDomainTests`: 689 pass.
  `LedgerPersistenceTests`: 85 tests, 83 pass. `damagedRow_failsLoad_neverTraps` fails (finding 4:
  `expected exit status ".success", but ".signal(SIGTRAP)"`). `DatabaseTests.open_protectsTheFileAndItsCompanions`
  fails with `SQLite error 23: authorization denied`, because the Mac was locked (finding 5).
- **Full gate** (`scripts/check.sh` through `sim-lock.py`, Xcode 27.0, 291 s; log: scratchpad
  `f05s1-closeout.log`): **OK.**
  - iOS `PR`: 17/17 targets, 921 tests (917 passed, 4 skipped).
  - watchOS `PR-Watch`: 8/8 targets, 898 tests (894 passed, 4 skipped).
  - `LedgerPersistenceTests` on each simulator: 82 passed, 2 skipped by design (protection, timing). My 10
    tests that are not host-only pass on both simulators.
  - Coverage: LedgerPersistence 100.00 % (391/391), overall 98.85 %.
- **Device plans on the simulators** (through the lock; log: scratchpad `f05r2-deviceplans.log`). The fix round
  had run only the iOS plan. `Device-Watch` on the Apple Watch Series 12 (46mm) simulator and `Device` on the
  iPhone 17 simulator each report "2 test targets ran and passed": `LedgerHealthTests` 1, and
  `LedgerPersistenceTests` 82 passed with the same 2 skipped.
- **Mutants of the fix round's code** (19, one at a time, host tests of both targets; results: scratchpad
  `f05r2-mut/results.txt`). My tests kill all 18 behaviour mutants. The fix round's own tests kill 15; these 3
  are caught only by mine:
  - an upsert that does not update `payload_version`. A save over a later-version row then leaves version-1
    bytes labelled 2, so every later `load` throws;
  - `try?` around one field's decoding, so a wrong type silently becomes the default, against the notes;
  - a renamed coding key for `plateMathEnabled`. Old rows then load its default silently: tolerant decoding turns
    a rename into lost data.

  The 19th mutant renames an `EventEnvelope` coding key with no version bump. It survives every test in both
  targets (see "Noted" below).
- **Regression.** The contract (now 13 clauses) passes on the in-memory reference, the GRDB store in memory and
  the GRDB store on a WAL file. F04's 14 mutants (`EventStoreMutationAdversarialTests`) and round 1's 13
  (`EventStoreMutantAdversarialTests`) are all still caught, on the host and on both simulators. The new clause
  `noneUnreadable` does work: a GRDB store that counts rows instead of unreadable rows fails it.

| Class | Count | Findings |
|---|---|---|
| bug | 0 | |
| minor bug | 2 | 4, 5 |
| spec question | 0 | |

## Close-out of round 1's questions

1. **Payload versions: closed, apart from finding 4.**
   - **Version 1 everywhere.** Both writers store the integer 1. No writer can leave the version out.
   - **Unreadable rows.** A later or unknown version, a version stored as text or a blob, or damaged bytes:
     each row is left out of `envelopes(for:)` and kept byte for byte. The other envelopes come back in
     insertion order, and `unreadableCount(for:)` is exact for each of three workouts (200 seeds).
     `highestSeq` and the listing still count the row.
   - **Logging.** `log show` after a run shows, at error level in `com.petearevalo.Ledger:persistence`:
     `workout_event row 3 (payload version 2) is unreadable, kept: Error Domain=LedgerPersistence.LedgerPersistenceError Code=2`.
     The row id and version are public. The error is private: only NSError's redacted domain and code appear.
   - **Re-appending a key whose row is unreadable counts as a duplicate.** It is skipped and not returned, the
     batch goes on, and the stored row is unchanged. That is right under the contract and ADR-004:
     - "the store judges keys, not contents", and `EventEnvelope`'s precondition (a key names one envelope)
       make the incoming envelope a copy;
     - a conflict would reject the whole batch on every redelivery, so sync could never get past it;
     - an overwrite would destroy a row that a later version can read ("never deleted").

     (documents) A rival, and a rival pair within one batch, are skipped as well. With the key free, the pair
     would be a conflict. The store cannot compare contents it cannot read.
   - **`compact` of such a log.** It deletes the log's unreadable rows with it, unlists the log and frees the
     keys: a resend is new again and is written as version 1. Other logs keep their unreadable rows. F17 is not
     to call `compact` while the count is above zero, and nothing in the store stops it. That matches the
     protocol ("Deletes the workout's log").
2. **File protection in CI: closed, apart from finding 5.**
   - **The plans resolve.** `xcodebuild -showTestPlans` lists `Device` under `Ledger` and `Device-Watch` under
     `LedgerWatch`. Their `LedgerPersistenceTests` entries match the PR plans' entries. Both plans run green on
     the simulators (above).
   - **No simulator-only condition is needed.** The fixture loads through `Bundle.module` and databases live
     under `temporaryDirectory`. The timing test is off in the `device` lane, and the exit tests are
     macOS-only. The slowest persistence test takes 0.21 s on the watch simulator, against a 60 s limit.
   - **Two device conditions remain:**
     - the protection test needs an unlocked device (finding 5);
     - a watchOS device build's `ARCHS` is `arm64 arm64_32`, and on arm64_32 `Int` is 32 bits. No test in
       the target narrows a 64-bit value into `Int` (checked), and mine leave out versions beyond `Int32` on a
       32-bit `Int`. For the product side, see finding 4.
3. **`personal_record`: closed.** The schema comment, the doc comment in `Migrations.swift` and F28's "Inputs
   from F05" all say it is derived and never synced, and the fixture matches. *Noted:* the table in
   architecture §7, which round 1 also named, still does not list `personal_record`.

## Audit of the tests the fix round edited

- **`PayloadEvolutionAdversarialTests`.** The two "(documents)" tests now assert the decision: the legacy row
  is left out and kept (count 1), a re-append is skipped, 3 rows remain, and the settings row loads with the
  default, which `observe` emits. Sound. Its `highestSeq(watch) == 2` cannot show that an unreadable row counts,
  because that row's seq (1) is lower. `UnreadableEventRowTests` (seq 3) and my property test do show it.
- **`SettingsRepositoryTests`.**
  - `unreadableRow_failsLoad_andEndsTheStream` now writes `'{"units": "stone"}'` instead of `'{}'`. The change
    is needed because `{}` now loads the defaults. The test still asserts a `DecodingError` and a stream that
    ends without a value. Sound.
  - `save_thenLoad_roundTrips_inOneRow` checks version 1 only after an upsert over a version-1 row. So it
    cannot see an upsert that leaves the version alone (the first survivor above).
- **`WorkoutEventStoreTests`.** The uniqueness test's `INSERT … SELECT` carries `payload_version`, so it still
  fails on `UNIQUE` and not on `NOT NULL`. Sound.
- **`EventStoreMutantAdversarialTests` and `EventStoreDateAdversarialTests`.** They only write or pass version
  1. The mutant store inherits `unreadableCount` = 0, which is right for it. All 13 mutants are still caught.
- **`SettingsTests` (Domain, new).** It covers `{}`, two missing keys, and invalid `units` and `defaultRest`.
  The names and types of the other five keys were not pinned (the second and third survivors above).

---

## 4. minor bug — A damaged settings row traps `load()` and `observe()` instead of failing them

`GRDBSettingsRepository.fetch` now reads `Row.fetchOne` and converts with the row's non-throwing subscripts:
`row["payload"] as String` and `row["payload_version"]` as `Int`. On a fetched row, GRDB traps when a value does
not convert:
```
GRDB/Row.swift:509: Fatal error: 'try!' expression unexpectedly raised an error: could not decode Int from
database value "two" - column: "payload_version"
```
- **Three damages trap:**
  - `payload_version = 'two'` (stored as text);
  - `payload_version = x'01'` (a blob);
  - `payload = x'FFFE7B7D'` (a blob that is not UTF-8).
- **This is a regression for the third damage.** Before the fix round, `String.fetchOne` read those bytes
  lossily (`"��{}"`), and `load` threw `DecodingError`. That is the behaviour
  `unreadableRow_failsLoad_andEndsTheStream` documents for an unreadable row.
- **The event store handles the same damages.** It reads through a `FetchableRecord` and treats every one of
  them as unreadable, without trapping (my property test).
- **Consequence:** the host loads settings at launch, so the app would trap on every launch until it is
  reinstalled.
- **Reach:** only damage or a foreign writer can cause it; every `save` writes an integer version and `TEXT`.
- **On arm64_32** (a watchOS device architecture), `Int` is 32 bits. GRDB's `Int(exactly:)` then returns `nil`
  for a version outside ±2³¹, so such a version traps the event store as well (`StoredPayload.version: Int`).
  This comes from the GRDB 7.11.1 source and is not run: the simulators are 64-bit.

**Repro** (fails): `SettingsDecodingAdversarialTests.damagedRow_failsLoad_neverTraps`, an exit test that runs on
the host only. It applies each damage, then requires `load()` to throw and `observe()` to end without a value.
A scratchpad trial with a tolerant `fetch` makes it pass along with the other settings tests: the columns are
read as `DatabaseValue`, and `Int.fromDatabaseValue` or `Data.fromDatabaseValue` returning `nil` throws. The fix
is the implementer's choice.

## 5. minor bug — The file-protection test fails whenever the Mac or the device is locked

`DatabaseTests.open_protectsTheFileAndItsCompanions` opens the file with `.completeUnlessOpen` (class B). While
that queue is open, the test opens the same file a second time. Class B lets a file be created while the device
is locked, but it does not let a new open succeed.
- **Result:** with `CGSSessionScreenIsLocked = true` (22:25, after hours), 3 of 3 runs failed with
  `SQLite error 23: authorization denied`. So did `check.sh --fast`.
- **A probe isolates it.** The first open succeeds and the reopen fails. The same reopen with the default class
  (`completeUntilFirstUserAuthentication`) succeeds.
- **Round 1's `protection_isNeverAnotherClass` passes while locked**, because it opens only once.
- **Consequences:**
  - `check.sh --fast` goes red whenever the Mac locks. That covers unattended runs and a screen that locks
    during a long gate. It is also the only lane that asserts protection on the Mac.
  - On the Device plans (F20), the test fails whenever the iPhone auto-locks, or the watch is off the wrist
    with a passcode, which is how a watch usually sits on its charger during a run.
- The product is not affected: the app opens with the default class, which reopens while locked after the first
  unlock.

**Repro:** lock the screen, then run
`swift test --package-path LedgerKit --filter DatabaseTests`.

**Options:**
- check class B on a single open, and check "every open sets the protection" by reopening between two classes
  that both open while locked (the default and `.none`);
- or require, and state in F20's protocol, an unlocked device, and skip the test when protected data is
  unavailable.

---

## Attacked and held

- **Version 1 everywhere.** Both writers store the integer 1, and the column is `NOT NULL` with no default in
  both tables, so a writer that leaves it out fails. Versions written `'1'` or `1.0` are stored as the integer 1
  by SQLite's affinity, and a JSON payload stored as `TEXT` reads back as it would from a blob.
- **Unreadable rows, 200 seeds.** Across 3 workouts and 2 devices, every damaged row was left out, counted in
  its own workout only and kept byte for byte (every column quoted). `highestSeq` stayed the maximum over all
  rows, and a resend of the whole log stored nothing. No damage made a row decode as a different envelope.
- **Keys of unreadable rows.** A copy or a rival is skipped. A rival of a readable key in the same batch still
  rejects the whole batch, and `highestSeq` moves only with new rows.
- **Compaction** deletes unreadable rows with their log and leaves other logs' rows alone. Resent keys are new
  again and written as version 1.
- **Settings.**
  - Each of the seven keys, missing alone, loads its default and keeps the others, through `load` and `observe`.
  - Unknown keys at the top level (`iCloudEnabled`, a nested object) and inside an inventory are ignored.
  - A wrong type in any one key fails the whole load, which is what the notes promise ("a key that is present
    must still be valid"), and leaves the row untouched.
  - Versions 0, −1, 2, 7 and `Int64.max` fail `load` by name and end `observe` empty, and the row is kept. A
    later save replaces the row with version 1 and the new payload. The notes tell F07 and F14 not to save over
    such a row. The repository still writes a version that matches its bytes.
- **Noted:**
  - **Version 1 of `EventEnvelope` is pinned by nothing.** Renaming a coding key (`workoutID` → `workout`)
    without a version bump passes every test in both targets. (The only failure in that run is the lock-dependent
    protection test, which fails in the unmutated baseline too.) After such an update, every stored row reads as
    unreadable. F17 would then keep the log from being materialised and tell the lifter to get a newer Ledger,
    which is the wrong message for rows that are older than the app. Round 1's option (a) would catch the
    rename: golden version-1 JSON for each `WorkoutEvent` case. My test pins the seven settings keys.
  - **HLC recovery sees only readable stamps.** ADR-004's "Recovery on launch" takes `newest` from the stored
    envelopes, so an unreadable row's stamp does not count, although its `wall_clock` column still holds it. The
    effect needs a rolled-back build, the case F17's input names, together with a clock that stepped back. That
    is F17's to weigh.
  - **`null` counts as missing.** A key holding JSON `null` takes its default, like a missing key (documents).
  - **Nested maps get no defaults.** A `plateInventory` without one unit decodes without that unit, as before
    the fix round.
  - **A `REAL` version of 1.5 reads as version 1**, because `sqlite3_column_int64` truncates it. Harmless.
  - **Unreadable rows are logged on every read.** `envelopes`, `unreadableCount` and `append` each log them,
    so every launch logs each unreadable row at least twice.

**Verdict:** S1 is not quite closed. Every decided behaviour holds on the host and on both simulators, and both
Device plans run green there. Two minor bugs remain: finding 4, a damaged settings column traps where it should
throw (a regression for non-UTF-8 bytes), and finding 5, the protection test fails whenever the host or device
is locked. Each needs a small fix before G2 closes. No bug, and no new spec question.

---

# Slice S1 — round 3 (close-out)

Scoped close-out over `feat/F05-persistence` at `209e364` (fix round 2). I read round 2's findings 4 and 5,
the review's SF1 to SF3, fix round 2's notes and its orchestrator decisions (with the SF2 amendment), and
`git show 209e364`. I attacked only that round's new surface. No product code was edited. The 31 mutants below
ran one at a time in a copy of `LedgerKit` in the scratchpad (`f05r3-mut/`), never in the worktree.

## What I wrote

12 tests (1 property test on `PropertySeed.all`, tagged `.property`) in 5 files under
`LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`, about 0.5 s on the host.

| File | Tests | What it attacks |
|---|---|---|
| `RowRepairAdversarialTests` | 5 | SF2 over 9 damages (versions 2, `Int64.max`, `1e30`, `x''`, `''`; a truncated payload, `x'C0'`, `x'EDA080'`, the integer 7): a conflict on *another* key later in the batch rolls the repair back; two envelopes for one unreadable key in a batch (a copy repairs once, a rival conflicts in either order and rolls back); a later version and a damaged row are repaired alike, in place (same `id` and `created_at`, version 1, the incoming bytes *and stamp*); the same device and seq in another workout repairs nothing; one batch repairs two workouts in the order given; a repair by a NaN-stamped envelope stores a `NULL` `wall_clock` |
| `ClockRecoveryAdversarialTests` | 3 (1 property) | SF3: an unreadable row in another workout holds the newest stamp, and compacting logs forgets theirs, down to `nil`; `NULL` and ±∞ written by another writer (`9e999`, `-9e999`) never count, while `-1e300` and `greatestFiniteMagnitude` do, exactly; a seeded model (200 seeds, 3 workouts, 2 devices, random damage, then 6 steps of random batches of copies, rivals and new keys, or compactions, with NaN, ±∞ and ±1e300 stamps) checks every `append` result or conflict, `envelopes`, `unreadableCount`, `highestSeq`, the listing and `newestWallClock` after each step |
| `RepairModel` | support | the model: the protocol's doc comments plus SF2's repair and SF3's clock, as plain values |
| `DamagedColumnAdversarialTests` | 3 | finding 4: 14 more damaged shapes of the settings row (versions `±1e30`, `9.3e18`, `x''`, `''`, `'1 one'`, `2.5`; payloads `x'C0'`, `x'EDA080'`, `{"u`, `x''`, `'null'`, `7`, `{}` plus a NUL): each fails `load` with the right error, `observe` ends with no value, the row is kept; an observation that is *running* when the row is damaged ends and emits nothing; (documents) a version of `1.5` reads as 1 |
| `PayloadV1SpellingAdversarialTests` | 1 | SF1's gap (below): the version-1 spelling of every case of `Equipment`, `SetKind`, `WorkoutPhase`, `Units` and `Weekday`, both ways, and a new case fails until it is listed |

## Results

- **Full gate** (`scripts/check.sh` through `sim-lock.py` after `rm -rf .derivedData`, Xcode 27.0; log: scratchpad
  `f05s1-r3.log`): **OK** (351 s).
  - iOS `PR`: 17/17 targets, 939 tests (935 passed, 4 skipped).
  - watchOS `PR-Watch`: 8/8 targets, 916 tests (912 passed, 4 skipped).
  - `LedgerPersistenceTests` on each simulator: 100 passed (88 plus my 12), and 2 skipped by design
    (protection, timing).
  - **Coverage from the clean build:** LedgerPersistence **100.00 % (405/405)**, LedgerDomain 98.99 %, overall
    98.87 %. The 13 stale watchOS lines that fix round 2 saw (405/418) are gone, so they were leftover objects
    from an incremental build, not a gap.
- **Host, with the screen locked** (`CGSSessionScreenIsLocked = Yes` before and after every run below):
  - `scripts/check.sh --fast` (log: scratchpad `f05r3-fast.log`, 93 s): **OK.** Format and lint pass with my
    files. `LedgerPersistenceTests` 103 pass (91 + my 12), the protection test included; `LedgerDomainTests` 689.
  - `swift test --filter DatabaseTests` (log: scratchpad `f05r3-locked-db.log`): 3 pass.
- **Mutants** (31, one at a time, host tests of both targets; results: scratchpad `f05r3-mut/results.txt`). All
  behaviour mutants are killed. Details are under each close-out item. Six survive the fix round's own tests and
  are caught only by mine:
  - **G01**, a repair that keeps the row's old `wall_clock`. The fix round's damages keep the original stamp,
    so nothing saw it;
  - **G04**, `newestWallClock` without its finite bound. The contract's ±∞ stamps go in through `append`, which
    stores `NULL`, so the bound is never exercised;
  - **F01, F03, F04, F13**, a renamed enum value that the fixtures do not hold (see SF1).

| Class | Count | Findings |
|---|---|---|
| bug | 0 | |
| minor bug | 0 | |
| spec question | 0 | |

## Close-out

| Item | Verdict | Evidence |
|---|---|---|
| **4.** A damaged settings column traps | **Closed** | `fetch` reads both columns as values. The fix round's 4 shapes and my 14 all throw (`malformedColumn` by name, `unknownPayloadVersion(2)` for `2.5`, `DecodingError` for UTF-8 that is not settings JSON), never trap, never return the defaults, keep the row, and end `observe` with no value, also when the observation is already running. Round 2's exit test passes in `--fast`. Mutants G08 (lossy UTF-8), G09 (a damaged version reads as the defaults) and G10 (read as version 1) are killed. On arm64_32, a version beyond `Int32` now gives `nil` (`Int.fromDatabaseValue` is `Int64.fromDatabaseValue(…).flatMap { Int(exactly:) }` in GRDB 7.11.1) and throws; read from the source, not run |
| **5.** The protection test fails while locked | **Closed** | With the screen locked: the test passes on its own and in `check.sh --fast`. **Control:** round 2's shape (open class B, then reopen), run in the same session, fails with `SQLite error 23: authorization denied`, so the lock was in force. **It still proves protection:** 6 mutants of `LedgerDatabase.open`, run while locked, all fail on an assertion rather than an error: no `protect` call, file only, companions only, the parameter ignored, only a new file, class B as the default. `-shm` is covered by round 1's `protection_isNeverAnotherClass`, which also passes while locked |
| **SF1.** Nothing pins payload version 1 | **Closed** (with my pin) | 13 envelope fixtures, one per `WorkoutEvent` case, enforced by an exhaustive switch, plus `settings.json`, with every field away from its default. **Killed:** a renamed nested key (`LastPerformance.load`), a new required field (`RestTimer`), a renamed `Weight` key, `"NaN"` spelled `"nan"`, `Units` without `CodingKeyRepresentable`, the pinned enum values (`barbell`, `live`), and `Weekday` renumbered. **Survived every test in both targets:** renaming an enum value that no fixture holds (`Equipment.dumbbell`, `.band`, `SetKind.warmup`, `WorkoutPhase.finished`). 6 of 7 equipment values, `warmup`, `finished` and `discarded` were unpinned. Stored `started` snapshots carry every one of them, and a rename would make them unreadable, the failure SF1 exists to stop. `PayloadV1SpellingAdversarialTests` now pins them and kills all four |
| **SF2.** A damaged row blocks its own repair | **Closed** | The first readable envelope repairs a later-version row and a damaged row alike, in place, and counts as new. A conflict anywhere in its batch, on its own key or another, rolls it back (the count returns to 1, row bytes unchanged). A copy in the same batch repairs once; a rival pair conflicts in either order. The repair is per workout, and `unreadableCount` drops to 0 in each workout it repaired. The 200-seed model agrees with the store on every result and read. **Parity:** the contract cannot make an unreadable envelope through the public API, so the in-memory store has none to repair and returns 0; on readable data both stores still pass all 14 clauses. Mutants G02 (the review's variant: skip later versions), G03 (repair not counted as new) and G07 (lookup ignores the workout) are killed, and G01 only by mine |
| **SF3.** HLC recovery cannot see unreadable stamps | **Closed** | `newestWallClock()` counts unreadable rows (another workout's included), skips `NULL` and ±∞ (another writer's `9e999` included), keeps finite extremes exactly, forgets compacted logs, and is `nil` when none is left. The model checks it after every step. Mutants G05 (readable rows only) and G06 (the protocol default on the GRDB store) are killed, and G04 only by mine. G11 and G12, mutants of the protocol default, fail the contract on the in-memory store |

## Audit of the tests the fix round edited

- **`DatabaseTests.open_protectsTheFileAndItsCompanions`.** Sound: it passes while locked and still kills every
  protection mutant (above). Its first check alone cannot show that `protect` runs, because the file inherits
  the directory's class; the reopen with class B does.
- **`UnreadableEventRowTests`** (rewritten). Sound over 6 damages: left out, counted, kept, the key and stamp
  still count, repair, rollback, version dispatch. It could not see G01 (its damage keeps the stamp), rollback
  caused by another key, or a repair leaking across workouts. My tests add all three.
- **`DamagedSettingsRowTests`** (new). Sound: 4 shapes, error by name, `observe` ends, row kept. It could not
  see an observation that was already running; mine adds it.
- **`PayloadV1FixtureTests` / `PayloadV1`** (new). Sound for keys, labels, nested fields, `Weight` text, the
  NaN and ±∞ strings, seq extremes and the settings keys. The fixtures hold one value per enum (SF1 above). The
  encode check compares parsed `NSDictionary`s, so `true` equals `1` there, but the strict decode check catches
  a `Bool` ↔ `Int` change, so nothing slips through.
- **`PayloadVersionAdversarialTests`** (round 2's, edited). Sound. The property test now asserts that a resend
  repairs exactly the damaged rows, in order, and leaves every other row byte-identical. The rewritten key test
  pins "first readable wins" and the rolled-back rival pair. *Noted:* its comment that a version beyond `Int32`
  traps on arm64_32 is stale since finding 4's fix. The exclusion it justifies is harmless.
- **`PayloadEvolutionAdversarialTests`** (round 2's, edited). Sound: the legacy row is repaired by a readable
  redelivery, and the row count and the unreadable count are asserted.
- **The contract's `newestFiniteStamp`** runs on both stores. Its non-finite stamps are stored as `NULL`, so it
  cannot exercise the GRDB store's finite bound (G04). My foreign-writer test does.
- **The five test conformers** now return `unreadableCount` 0 explicitly (N1). Correct for each.

## Attacked and held

- **Repair** under 9 damages, both families: rollback on the same key and on another key, copies and rival pairs
  in one batch, order with new and duplicate envelopes, two workouts in one batch, per-workout keys, row
  identity kept, stamp rewritten, and a NaN stamp stored as `NULL`. 200 seeds against the model.
- **Clock**: unreadable rows count across workouts; `NULL`, ±∞ and another writer's infinities do not;
  `±1e300` and `greatestFiniteMagnitude` are exact; compaction forgets; empty is `nil`.
- **`malformedColumn`**: 18 settings shapes in all, and the event rows' damages (the fix round's 6, and my 9 in
  repair). None traps, none returns the defaults, every row is kept, and every `observe` ends, running or not.
- **Finding 5** under a real lock, with a control and 6 mutants.
- **SF1**: 13 format mutants. The 9 the fixtures cover are killed; the 4 they miss are killed by my pin.

**Noted, not blocking:**
- **A `wall_clock` of the wrong storage class misleads `newestWallClock()`.** SQLite's `MAX` ranks text and blobs
  above numbers, and GRDB reads the winner with `sqlite3_column_double`. So one row whose `wall_clock` is text
  or a blob makes the result wrong, even though that row still reads as an envelope:
  - `'garbage'`, `''` or `x'00'` give `0` (2001-01-01), which hides the real newest stamp;
  - `x'39653939'` gives `9e99`.

  Only damage or another writer can do this, since `append` binds a `Double` or `NULL`. Then the clock recovers
  from the physical clock, which matters only if that clock also stepped back. The fix is one clause:
  `AND typeof(wall_clock) = 'real'`. Probe (scratchpad, deleted): five shapes.
- **F28 will trip the settings fixture.** F28 adds `Settings.iCloudEnabled`. Mutant F08, an additive field with
  a default, fails `settings_decodesToItsLiteral` (encode check) and round 2's seven-key pin. The fixtures'
  rule then makes it settings payload version 2, although tolerant decoding was adopted so that this very field
  could join version 1. That is safe either way: an older app sees a later version and keeps the row. But F28's
  "Inputs from F05" says nothing about it. One line there would stop F28 from "fixing" the test instead.
- **A later-version row is repaired with the version-1 copy** (decided in the SF2 amendment; the review had
  proposed keeping the skip for later versions). After a rollback and a re-upgrade, whatever version 2 held
  beyond version 1 in that envelope is gone. It needs a rollback, a peer's resend, and a version 2 that adds
  content, and a key names one envelope anyway.
- **`newestWallClock` keeps a protocol default.** A wrapper (F10, F17) that forgets to forward it silently drops
  unreadable rows' stamps: the N1 footgun, for this requirement. `unreadableCount`'s doc says a wrapper must
  forward; this one's does not.
- **A fractional `REAL` version reads as its integer part** (`1.5` as 1, `2.5` as 2), from GRDB's
  `Int64.fromDatabaseValue` (documents). Harmless.

**Verdict: G2 can close.** Finding 4, finding 5, SF1, SF2 and SF3 are closed, with evidence on the host, with
the screen locked, and on both simulators (full gate above). The fix round's one test gap in SF1, unpinned enum
values, is closed by `PayloadV1SpellingAdversarialTests`. No bug, no minor bug and no spec question remain. The
F28 input line and the `typeof` clause are optional, cheap follow-ups.

---

# Slice S2 — adversarial round 1

Independent adversarial pass over `feat/F05-s2` at `641e4b2` (S2: `GRDBExerciseRepository`, `GRDBProgramRepository`,
their records, `ColumnReader`, `SyncedRecord`, the two contracts and `Seeders`). I wrote the tests from the brief
(criteria 2 and 11), product decisions #9, #18 and #23, ADR-002, ADR-007, spec §6.1 and §7.1–§7.7, the S1 code and
tests on `main`, and the public interfaces and doc comments of the S2 code. I did not read
`implementation-notes.md`, the implementer's S2 tests or the contract bodies until my tests were written; I read
them and the product code afterwards, to find root causes and to separate documented decisions from findings. No
product code was edited. The mutants below ran one at a time in a copy of `LedgerKit` in the scratchpad
(`f05s2-mut/`), never in the worktree.

**Convention** (as in S1): a failing test is a bug or a minor bug and stays in the branch as a regression test; a
spec question is pinned by a passing test marked "(documents)".

## What I wrote

73 tests (3 property tests, tagged `.property`) in 15 files under `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`,
plus three support files (`S2Fixtures`, `S2Database`, `ProgramEditModel`). None is `.slow`: the whole set runs in
about 3 s on the host. No wall-clock assertion; the observation tests synchronise on the stream only. The fixtures
are my own (`S2Kit`), not `Seeders`, so they cannot share a blind spot with the implementer's.

| File | Tests | What it attacks |
|---|---|---|
| `ProgramRoundTripAdversarialTests` | 8 | criterion 2: 8 × 4 × 6 slots with misses through `active()`, `program(id:)` and a second repository, with exactly its live rows; a second identical save changes no byte; misses at −1, 99, `Int.min`, `Int.max`; days reversed, empty, unscheduled, one day on all seven weekdays; no days; emoji, combining marks, SQL, `%`/`_`/`\`, 10 000 characters; civil extremes 0001-01-01 and 9999-12-31, a leap day, every goal, `daysPerWeek` nil, 0, −1, `Int.min`/`.max`; a NUL (documents) |
| `ProgramEditAdversarialTests` | 7 | a slot moved to another day while its old day is removed, in one save; slots swapped across days; a slot, day, week and miss removed, then re-added with the same ids; 12 random reorders of days, slots and schedules; 2 → 20 → 2 weeks; a failed save (unknown exercise in the last slot) leaves every byte; 9 slot and 5 program `var` mutations refused at save with nothing written |
| `ProgramEditModelAdversarialTests` + `ProgramEditModel` | 1 (property, 200 seeds) | a random builder session of 8 saves (1–3 edits each: fields, adds, removals, moves across days, reorders, days and weeks added or removed, misses toggled, ids removed earlier added back, header changes; a delete then re-save at step 5): every save reads back equal with exactly its live row counts, no live row under a deleted parent, and a fresh repository agrees |
| `ProgramTimestampAdversarialTests` | 5 | ADR-002's sync columns: one slot's edit moves only that slot's `updated_at`; a removed slot and its misses get `deleted_at` = `updated_at` = the save's time; `delete` moves `updated_at` on every row; a re-added slot clears `deleted_at` and keeps `created_at`; ISO 8601 UTC text |
| `ProgramLifecycleAdversarialTests` | 8 | one active program across saves; an inactive save of the active program; `setActive` switching and repeated; `missingRow` for unknown and deleted ids; deleting the active program, twice, and an unknown id; a re-save after delete, whole and edited; delete scoped to its program; two live active rows (documents) |
| `ProgramIdentityAdversarialTests` | 3 | duplicate slot (across days and within one), day and week ids in one program; a second program reusing the first one's slot, day or week id (finding S2-1); reusing a deleted program's slot id |
| `ProgramWeightAdversarialTests` | 4 | ADR-007 on `start_load_e7g`/`step_e7g`: `Int64.max`, 1 unit, 1,000 lb on a 2.5 lb step, 1,250 g, stored as the exact count; NULL for nil; beyond `Int64`, ⅛ lb, 0.001 lb, 10⁻⁸ g, ⅓ g refused as `inexactWeight(value)` with every byte kept; a save over a damaged slot id (finding S2-3) |
| `ExerciseSeedingAdversarialTests` | 9 | criterion 11: the same version twice (and a bigger catalog at it) changes no byte; entries read back equal; 1 → 2 additive, then 1 and 2 again change nothing, then 3; entries named like the custom one in other case and accents are all seeded; an entry holding a custom row's id leaves it; an inexact entry seeds nothing and the version stays unapplied; one id twice (documents); a lifter's edit and a deleted catalog row survive an upgrade; 8 racing seeds of versions 1 and 2 |
| `ExerciseSearchAdversarialTests` | 6 (40 query cases) | decision #23: substrings mid-name, short names, case, diacritics both ways, precomposed and decomposed both ways, `%`, `_`, `\`, `[`, `*`, `?`, quotes, emoji; no match across name and short name; trimmed blanks, internal double spaces; empty, spaces, tabs and newlines with a filter; equipment and muscle by AND; primary muscle only; ß ⇄ ss (documents); `all()` order; deleted rows |
| `ExerciseSearchPropertyAdversarialTests` | 1 (property, 60 seeds) | random names from 28 pieces (accented, decomposed, Turkish i, ligature, final sigma, ǅ, wildcards, emoji); queries cut from them and re-cased or stripped; `search` equals the folded-substring oracle, in `all()` order, with and without an equipment filter |
| `ExerciseRoundTripAdversarialTests` | 6 | no loads, one unit only, `Int64` extremes, 10⁻⁷ g, negative loads; duplicate and ordered secondary muscles and alternatives; empty and 5 000-character text; every equipment × muscle; every 7th hundredth of a pound to 1,500 lb and 1.25 kg steps against the integer oracle (h × 45,359,237); inexact loads refused, the stored row kept; upsert and revival; `all()` order under 50 shuffled insert orders with folded ties |
| `DamagedExerciseAdversarialTests` | 4 (31 damages) | unknown enums, bad JSON arrays (`[`, `null`, `{}`, `[1]`, unknown muscle, bad ids), REAL and text and blob loads, `±9.3e18`, flags `0.5`/`'yes'`/blob, non-UTF-8 names, malformed ids: left out of `all()`, `search` (filtered or not) and `observeAll()`, `exercise(id:)` throws; the row kept through a seed and another save; flags of 2 and −1 (documents); a damaged `catalog_version` (finding S2-2) |
| `DamagedProgramAdversarialTests` | 4 (65 damages) | every table: bad civil dates, unknown goal and progression, fractional, text, blob and out-of-range integers, RPE ×2 of 9/21/17.5, rest 31 and 29.5, negative and zero steps, fractional loads, dangling and malformed schedule ids, bad slot and miss ids: `program(id:)` throws, `active()` throws or is nil, never a different program, the other program unaffected; a damaged active program ends `observeActive()`; a save repairs; flags of 2 (documents) |
| `RepositoryObservationAdversarialTests` | 3 | `observeActive()` through saves, a change to `slot_miss` alone, `setActive`, delete and re-save; a position-only edit by another repository; `observeAll()` through a save, a seed, another writer's soft delete and a damaged row (the stream goes on) |
| `RepositoryConcurrencyAdversarialTests` | 4 | both repositories `Sendable` across tasks; 16 racing saves of different edits leave exactly one, with exactly its rows; readers racing 16 saves see only whole programs; 8 racing `setActive` calls leave one active |

## Results

- **Host** (`swift test --filter LedgerPersistenceTests`): 204 tests, **200 pass, 4 fail**, all 4 mine and all
  expected (findings S2-1 to S2-3). My 73: 69 pass, 4 fail: the slot, day and week cases of one test, one of six `catalog_version` cases, one of three
  id cases, and one plain test.
  The implementer's and S1's tests all pass beside mine. Format and `swiftlint --strict` pass with my files.
- **Full gate** (`scripts/check.sh` through `sim-lock.py`, Xcode 27.0, 188 s; log: scratchpad `f05s2-g2.log`):
  **exit 65**, as expected. Tools, format, lint, the package graph and pins, and the script tests pass. The iOS
  `PR` plan ran 1,106 tests: 1,096 passed, 6 skipped, and 4 failed, exactly my four (S2-1 to S2-3). `set -e` then
  stopped the gate before watchOS and coverage.
- **watchOS, run separately** (the same destination and derived data, `PR-Watch` with
  `-only-testing:LedgerPersistenceTests`, through the lock; log: scratchpad `f05s2-watch.log`): 203 tests, 195
  passed, 4 skipped by design, and 4 failed, the same four. My files add no compiler warning on either platform.
- **Mutants of the S2 code** (16, one at a time, host tests of `LedgerPersistenceTests`; results: scratchpad
  `f05s2-mut/results.txt`). My tests kill all 16. The implementer's tests and contracts kill 11; these 5 are
  caught only by mine:
  - **M04**, a soft delete that leaves `updated_at` alone. A sync keyed on `updated_at` (M4) would never send the
    deletion. (The implementer's `partialUpdate_diffsChildren` checks `deleted_at` only.)
  - **M09**, **M10**, slots or days read back in id order instead of `position`. The implementer's fixtures create
    ids in position order, so the order is never tested apart from the ids.
  - **M14**, the applied catalog version taken as `MIN` instead of `MAX` of `catalog_version`.
  - **M15**, `all()` sorted by folded name only, with no id tie-break: equal folded names ("Élévation",
    "elevation", "ELEVATION") then come back in insertion order.

  The others: search without trimming (M01), without diacritic folding (M02), on the name only (M03); an upsert
  that never revives (M05); a diff that rewrites every row (M06); seeding that skips a name clash (M07), ignores
  the version (M08), or overwrites stored ids (M13); misses never soft-deleted (M11); `setActive` that does not
  clear the others (M12); `%` and `_` as wildcards (M16).

| Class | Count | Findings |
|---|---|---|
| bug | 1 | S2-1 |
| minor bug | 2 | S2-2, S2-3 |
| spec question | 1 | S2-4 |

**Verdict:** G2 cannot close for S2 yet. Criteria 2 and 11 and decision #23 hold on the host and on both simulators.
But S2-1 is a real bug: a program saved with another program's ids silently corrupts that program, the active
one included. S2-2 and S2-3 are small fixes to strict reads. S2-4 is for the orchestrator.

---

## S2-1. bug — A program that reuses another program's slot, day or week id takes that row, silently

`save` diffs a program against **its own** live rows only (`ProgramRows.write` reads them by `program_id`). A
record whose id is not among them counts as new, and `SyncedRecord.upsert` writes it with
`INSERT … ON CONFLICT (id) DO UPDATE SET program_id = excluded.program_id, …, deleted_at = NULL`. When the id
already belongs to another program, live or deleted, that row is moved into the program being saved. No error is
thrown. `duplicateIdentifier` covers only ids repeated inside one program.

Consequences, all observed:
- **A taken slot:** program 1 loses the slot. Program 2 then reads program 1's misses for that slot as its own:
  they are joined through the slot id, and program 2 saved none. So neither program reads back as saved.
- **A taken day:** program 1 is unreadable. Its weeks still schedule the day, which now belongs to program 2, so
  `active()` throws `danglingSchedule` on every launch, and `observeActive()` ends. Program 2 reads program 1's
  slots in that day as its own.
- **A taken week:** program 1 is unreadable (`nonContiguousWeeks([1, 2])`).
- **A deleted program's id:** program 2 takes the soft-deleted row and revives it. Restoring program 1 later
  (`save` after `delete`) silently takes it back, and program 2 loses the slot.

**Reach.** Every id is a primary key shared by all programs, and `Program.init` checks no ids. Rule 18's "Start
next block" (repeat with +progression, F11) copies a block. A copy that keeps its days' or slots' ids is an easy
slip, and it would corrupt the block it copied, the active one, with no error at save time. A sync merge (M4) that
moves a row between programs is the same shape.

**Repro** (fails): `ProgramIdentityAdversarialTests.idsOfAnotherProgram_areRefused` (slot, day, week) and
`idsOfADeletedProgram_areRefused`:
```swift
try await programs.save(first)                       // active
var days = second.days
days[0].slots[0] = try first.days[0].slots[0].with(sets: 1, misses: [])
try await programs.save(second.rebuilt(days: days))  // expected: throws; actual: succeeds
try await programs.active() == first                 // expected: true; actual: one slot short
// a taken day instead: active() throws danglingSchedule(weekIndex: 0, …)
```
**Expected:** the save throws (for example `duplicateIdentifier("slot <id>")`) and writes nothing; neither program
changes. **Actual:** the save succeeds, and both programs change.

**Fix options** (the implementer's choice): before upserting a record that is not among the program's stored rows,
look its id up in the whole table (deleted rows included) and throw if it exists under another parent; or add
`WHERE program_id = excluded.program_id` (the parent column for slots and misses) to the conflict clause and
throw when the statement changes no row.

## S2-2. minor bug — A `catalog_version` beyond `Int64` stops every later catalog upgrade, silently

`seedIfNeeded` reads the applied version with `Int.fetchOne(… "SELECT MAX(catalog_version) …")`. That goes through
`sqlite3_column_int64`, which does not check storage classes: a `REAL` beyond `Int64` clamps to `Int64.max`, and
text or a blob reads as 0. So one damaged row with `catalog_version = 9.3e18` makes every later `seedIfNeeded`
return without error and without seeding. New catalog exercises never appear, and a program template naming one
fails the slot foreign key. Text, a blob or `''` read as 0 and re-seed, which is harmless.

This is the non-strict read that `ColumnReader` exists to prevent (notes, decision 6), on the one column read
outside it. **Reach:** damage or a foreign writer only.

**Repro** (fails): `DamagedExerciseAdversarialTests.damagedCatalogVersion_neverTraps` with `9.3e18`: after seeding
version 1, `UPDATE exercise SET catalog_version = 9.3e18`, then
`seedIfNeeded([one, two], version: 2)`. **Expected:** it throws `malformedColumn("exercise.catalog_version")`, or it
seeds (2 rows). **Actual:** it succeeds with 1 row. **Fix:** read `MAX(catalog_version)` as a `DatabaseValue` and
require `INTEGER`, or add `AND typeof(catalog_version) = 'integer'`.

## S2-3. minor bug — A row whose id is a blob survives every save and keeps its program unreadable

`SyncedRecord.write` keys the stored rows by `String.fromDatabaseValue(row["id"])`. For a `BLOB` id that returns
`nil`, so the row is never matched, never soft-deleted, and stays live under its parent. `ColumnReader` reads the
same blob as UTF-8 text (`"\0"` for `x'00'`) and throws `malformedIdentifier`, so the program throws on every read,
even after the lifter saves it again. Notes, decision 4: "a save repairs a damaged row rather than failing on it".
Text ids (`'nope'`, `7`) are repaired, as promised. **Reach:** damage only.

**Repro** (fails): `ProgramWeightAdversarialTests.saveOverDamagedID_repairs("x'00'")`:
`UPDATE slot SET id = x'00' WHERE id = ?`, then `save(program)`. **Expected:** `active() == program`. **Actual:**
throws `malformedIdentifier("\0")`. **Fix:** key stored rows by the same text `ColumnReader` accepts (`TEXT`, or a
UTF-8 `BLOB`), or select `CAST(id AS TEXT)` in `Query`; or soft-delete any stored row whose id does not parse.

## S2-4. spec question — Text is cut at its first NUL, on write

GRDB binds a `String` with `sqlite3_bind_text(…, -1, …)`, a C string. A program, day or exercise name holding
U+0000 is stored cut at it (`"nul\0inside"` → `"nul"`, 3 bytes). A later identical save sees a change and rewrites
the row. No input path makes one today; F11 and F12 validate names. **Pinned by**
`ProgramRoundTripAdversarialTests.nul_cutsTheName` (documents). **Options:** refuse control characters in the
F11 and F12 name rules (F12 already trims), or accept the cut as GRDB's.

---

## Attacked and held

- **Criterion 2.** 8 weeks × 4 days × 6 slots with misses round-trips through `active()`, `program(id:)` and a
  fresh repository, with exactly the rows it implies. A second identical save changes no byte. Misses at any
  `Int`, days in any order, empty and unscheduled days, a day on all seven weekdays, no days, every goal, civil
  extremes, `daysPerWeek` at `Int` extremes, and hostile text all round-trip.
- **The diff** (200 seeds × 8 saves of random builder edits, delete and re-save included): every save reads back
  equal, with exact live counts and no live row under a deleted parent. A slot moved out of a day removed in the
  same save survives with its misses. Removed slots, days, weeks and misses come back by id, with no second row.
  Reorders round-trip.
- **Sync columns.** Only the changed slot's `updated_at` moves. A removal or `delete` sets `deleted_at` and
  `updated_at` to the save's time on every row it touches. A revival clears `deleted_at` and keeps
  `created_at`.
- **Atomicity and validation.** A foreign-key failure on the last slot, an inexact load, or 14 kinds of
  out-of-range `var` edits leave every byte as it was.
- **Active program.** One active program after any save or `setActive`; `missingRow` for unknown and deleted ids;
  delete, re-delete and unknown delete behave; two active rows from a sync read the same one every time
  (documents; the notes say the one updated last).
- **Exact weights.** Slot and exercise loads at `Int64.max`, `Int64.min`, 1 unit and 0 read back equal. The stored
  counts match the integer oracle for 21,429 pound values and 401 kilogram values. Five kinds of inexact value
  are refused with the value, and nothing is written.
- **Seeding (criterion 11).** Idempotent at one version, even with a bigger catalog. Additive upgrades; lower
  versions do nothing. Name clashes in any case or accent are seeded beside the custom row. A custom row holding
  a catalog id is untouched. An inexact entry rolls everything back and leaves the version unapplied. A lifter's
  edit and a deleted catalog row survive upgrades. Eight racing seeds store each id once.
- **Search (#23).** 40 query cases and 60 seeded property cases: substring on name and short name only, case and
  diacritics folded both ways (decomposed input too), `%` `_` `\` `[` `*` `?` and quotes literal, blanks
  (spaces, tabs, newlines) match all, trimmed; filters by AND, in `all()` order; deleted rows never found.
- **Strict reads.** 31 exercise damages and 65 program damages: none traps, none reads as another value. An
  unreadable exercise is left out of `all()`, `search` and `observeAll()` (which goes on); `exercise(id:)`
  throws. A damaged program throws, ends `observeActive()`, leaves the other program readable, and a save
  repairs it (apart from S2-3).
- **Observation.** `observeActive()` follows a `slot_miss`-only change, a position-only change by another
  repository, `setActive`, delete and re-save. `observeAll()` follows a save, a seed, another writer's soft
  delete, and damage.
- **Concurrency.** Both repositories are `Sendable`. Sixteen racing saves leave one whole edit with its rows.
  Readers racing them see only whole programs. Eight racing `setActive` calls leave one active.

**Noted, not findings:**
- **Flags accept any integer** (`is_custom`, `is_deload`, `is_superset_with_previous` of 2 or −1 read as true),
  while a fraction, text or a blob is refused. That is the notes' decision 6 ("for a flag, only an integer");
  pinned by two "(documents)" tests.
- **The muscle filter is the primary muscle only** (notes, decision 1, "my reading"). Decision #23 does not say
  which. F12's pills group muscles ("Legs", "Arms"), so F12 should confirm that a secondary muscle never
  matches. Pinned (documents).
- **ß and "ss" find each other**, since `.caseInsensitive` folding is full case folding. Pinned (documents).
- **A catalog listing one id twice stores the last entry.** The stored ids are read once, before the loop, so
  both entries are upserted. F03 validates unique ids. Pinned (documents).
- **The `catalog_version` of a damaged row** is still moved up by a seed that lists it. This is harmless and
  documented.

---

# Slice S2 — close-out round

Scoped close-out of fix round 1 (`57fdeb7`) on `feat/F05-s2`: S2-1 to S2-4, review SF1 (decision #24) and SF2
(`ExerciseSearch`), the new contract clauses, and nits N1, N2 and N4. I read my round 1, the S2 review, the
implementer's "S2 fix round 1" notes and the fix diff. No product code was edited. The mutants below ran one at
a time in a copy of `LedgerKit` in the scratchpad (`f05s2-close-mut/`), never in the worktree.

**The one edit to my tests.** `git diff ec6da47 57fdeb7 -- '*/Adversarial/'` touches one file,
`ProgramRoundTripAdversarialTests.swift`, and in it one test: `nul_cutsTheName` now expects
`nulInText("program.name")` and no rows, as decided for S2-4. Its doc comment says so. Nothing else of mine
changed.

## What I wrote

27 tests (3 property tests) in 9 files: 22 under `LedgerPersistenceTests/Adversarial/`, 5 under
`LedgerDomainTests/Adversarial/`. They run in under a second on the host. The fixtures are still my own (`S2Kit`,
plus `S2CatalogKit`, an exercise repository with a settable clock and row probes).

| File | Tests (cases) | What it attacks |
|---|---|---|
| `ProgramIdentityCloseoutAdversarialTests` | 4 (16) | S2-1: ten takeovers of program 1's ids by a stored program 2 (a deleted program's week, day or slot; a removed week, day or slot; a slot under a removed day; week + slot; day + slot; a taken slot after three new ones): refused by id, both programs byte for byte, then both save again and read back; the error names the table and id, weeks first; an id reused in another table (documents); a week or day whose `program_id` names no program (S2-5) |
| `StrictReadCloseoutAdversarialTests` | 2 (53) | S2-2: `catalog_version` damaged to 11 values (`±9.3e18`, `1.5`, `0.5`, `''`, `'v1'`, `x'01'`, `x''`, a text beyond `Int64`, and `1.0`/`'1'`, which affinity stores as 1) on every catalog row, one of two, a deleted row and a custom row: either `malformedColumn("exercise.catalog_version")` with no byte changed, or the upgrade seeds and every live catalog row ends at integer 2; never a quiet no-op. S2-3: a blob id (`x'00'` or the text id's own bytes) on the program, week, day, slot and miss tables: a save repairs it and a second save changes nothing |
| `NulTextCloseoutAdversarialTests` | 3 (25) | S2-4: NUL alone, leading, trailing, inside, before a combining mark, twice; in the program name, a day's name and tag (new program and edit), and an exercise's name and short name (save, seed, refresh): refused by column, no byte changed; other control characters and NUL lookalikes stored whole |
| `CatalogRefreshCloseoutAdversarialTests` | 5 | SF1: six launches (2, 2, 3, 3, 3, 1) of an unchanged catalog move only `catalog_version`; nine single-field changes each refresh one row in place (id and `created_at` kept, `updated_at` moved, the other rows' metadata unchanged); an entry marked custom is no content change; deleted rows, a custom row holding a catalog id and a lifter-saved row survive a renaming upgrade byte for byte; a lifter's revival of a deleted catalog row is not refreshed |
| `CatalogEdgeCloseoutAdversarialTests` | 5 | SF1 edges: versions 3, 2, 1, 0, −1 and `Int.min` after 3 change no byte; alternatives naming unstored ids (and one twice) refresh and read, through `all`, `exercise` and `search`; one inexact entry rolls back the whole refresh, the version stays unapplied, and the corrected catalog applies; an unlisted row keeps version 1 and is refreshed when version 5 lists it again; idempotent after that; a damaged catalog row (`equipment = 'hovercraft'`) is repaired by an unchanged upgrade |
| `RepositoryNitsCloseoutAdversarialTests` | 2 | N1: three identical saves of a custom exercise keep `updated_at`; a change and a revival move it. N2: deleting an inactive program leaves the active one; deleting the active one clears its flag; a revival with a later `updated_at` is never active; a save makes it active again |
| `SearchHelperCloseoutAdversarialTests` | 1 (60 seeds) | SF2 as a property: 14 random exercises (catalog and custom, three equipments and muscles), 10 queries each: `search(q, e, m)` equals `all()` filtered by `ExerciseSearch.matches` and both filters, and `all()` equals `ExerciseSearch.sorted` of the input |
| `ExerciseSearchCloseoutAdversarialTests` (Domain) | 5 (181) | SF2: 20 folding cases on name and short name (case, both accent forms, Turkish İ, final sigma, outer blanks incl. NBSP and U+3000; width, inner blanks, `ı` and `Ø` not folded: documents); 11 10 blank queries; the trim-before-fold nit (documents); laws over 100 seeds (the two `matches` agree, `key` is a fixed point, a name finds itself); the name order over 50 seeds (irreflexive, asymmetric, `sorted` = `sorted(by: isInNameOrder)`, shuffle-invariant) |

## Results

- **Host** (`swift test`): `LedgerPersistenceTests` 235 tests. My 22 new ones: 21 pass and 1 fails, the
  parameterised `danglingParent_isRepairedBySave` (3 of its 4 cases; finding S2-5). My 5 new Domain tests pass.
  Every other test passes, the implementer's and mine from round 1 included. Format and `swiftlint --strict` are
  clean on the new files.
- **Full gate** (`scripts/check.sh` through `sim-lock.py`, Xcode 27.0, 255 s; log: scratchpad
  `f05s2-closeout.log`): **exit 65**, as expected. Tools, format, lint, the package graph and pins, and the script
  tests pass. The iOS `PR` plan ran 1,146 tests: 1,139 passed, 6 skipped, and 1 failed, exactly S2-5's test.
  `set -e` then stopped the gate before watchOS and coverage.
- **watchOS, run separately** (`PR-Watch` with `-only-testing:LedgerPersistenceTests`, through the lock; log:
  scratchpad `f05s2-closeout-watch.log`): 235 tests, 230 passed, 4 skipped by design, and 1 failed, the same one.
- **Mutants of the fix** (19, one at a time, host; results: scratchpad `f05s2-close-mut/results*.txt`): all 19
  are killed. Two are killed by my close-out tests alone, and a third by my tests only:
  - **B1, weeks and days checked against live rows only** (`AND deleted_at IS NULL` in the owner queries). The
    implementer's clause covers a deleted program's slot only, so a removed week or day, or a deleted program's
    week or day, could be taken again.
  - **SF2, width folding added** (`.widthInsensitive`). Only my "(documents)" cases pin that width is not
    folded.
  - **S2-3, stored rows keyed as text again**: killed by my close-out blob tests and round 1's
    `saveOverDamagedID_repairs`, by no test of the implementer's.

  Killed by both suites: B1 without the slot check, or without the week check, or with live slots only; SF1
  refreshing deleted rows, refreshing custom and lifter rows, stamping every refreshed row, not clearing the
  version on save, refreshing at an equal version, not recording the version; S2-2 read leniently; S2-4
  checking `name` only; SF2 without the trim; N1 stamping every save; N2
  keeping the flag. **N4:** the two observation mutants, `removeDuplicates(by: { _, _ in false })`, are killed
  by the implementer's `ObservationTests`, so those tests now fail on a spurious emission.

| Class | Count | Findings |
|---|---|---|
| minor bug | 1 | S2-5 (new: a regression of the S2-1 fix) |
| nit | 2 | S2-N1, S2-N2 (new, pinned "(documents)") |

## Close-out of round 1's findings

| Finding | Status | Evidence |
|---|---|---|
| S2-1 (bug) | **Closed** | My round-1 tests pass. All ten takeover variants are refused by id, both programs stay unchanged, and both save again afterwards. Mutants that check live rows only, or skip slots or weeks, are killed. The fix has one regression, S2-5 below. |
| S2-2 (minor bug) | **Closed** | All 44 damage cases either throw `malformedColumn` by name and write nothing, or seed. None returns quietly. A custom row's damage is ignored, as it should be. |
| S2-3 (minor bug) | **Closed** | A blob id is repaired on all five tables, including a blob with the text id's own bytes. A second save is a no-op. |
| S2-4 (spec question, decided) | **Closed** | NUL is refused by column in all five text columns that domain values reach, by save, seed and refresh, and no byte is written. The JSON array columns hold enum raw values and UUIDs only, so a NUL cannot reach them. |

SF1, SF2, N1, N2 and N4 hold as well; see "Attacked and held".

## S2-5. minor bug — A save no longer repairs a week or day whose `program_id` names no program

This regresses the B1 / S2-1 fix. `refuseOtherProgramsIDs` treats any `program_id IS NOT <this program>` as
"another program holds this id", including a `program_id` that names **no** program: `'nope'`, or a blob of the
program's own bytes. Such a row is damage or a foreign writer's, since a foreign key forbids it otherwise. The
damaged week or day drops out of its program, so the program is unreadable (`danglingSchedule` or
`nonContiguousWeeks`), and `active()` throws on every launch. Before fix round 1, saving the program repaired
it: the upsert wrote `program_id` back. Now that save is refused with
`duplicateIdentifier("day_template <id>")`, which names an owner that does not exist. So no save can ever
repair the program. This breaks the notes' decision 4 ("a save repairs a damaged row rather than failing on it").
A slot whose `day_template_id` names no day is still repaired, because the slot owner query joins
`day_template`. **Reach:** damage only, the same class as S2-2 and S2-3.

**Repro** (fails): `ProgramIdentityCloseoutAdversarialTests.danglingParent_isRepairedBySave`, three of its four
cases:
```swift
try await programs.save(first)                                   // 2 weeks, 2 days, active
UPDATE day_template SET program_id = 'nope' WHERE id = <day 2>   // foreign keys off
try await programs.save(first)  // expected: repairs; actual: throws duplicateIdentifier("day_template <day 2>")
try await programs.active()     // expected: first; actual: throws danglingSchedule
```
The same happens for `program_week.program_id = 'nope'` and for `day_template.program_id = CAST(program_id AS BLOB)`.

**Verified in the scratchpad copy:**
- Without `refuseOtherProgramsIDs`, as before the fix, this test passes.
- With the fix below, every identity test passes: round 1's, the clause tests and my ten takeovers.

**Fix:** refuse only ids whose owner is a stored program, by adding
`AND program_id IN (SELECT id FROM program)` to `weekOwners` and `dayOwners`, and
`AND day_template.program_id IN (SELECT id FROM program)` to `slotOwners`. That is three query strings, and the
error then always names a real program's row.

## S2-N1. nit — `ExerciseSearch.key` trims before it folds, so it is not a fixed point

`key("bench \u{301}")` is `"bench "`. Folding strips the combining mark and uncovers a blank, which the trim
already passed over. `key(key(x))` then differs from `key(x)`, and that query misses "Bench". The same holds for
a fullwidth letter followed by a lone combining mark, where Foundation needs two passes. No keyboard types a lone
combining mark after a space, so this only matters to anyone relying on `key` being idempotent: fakes, or a
cached key. **Fix (optional):** fold, then trim. Pinned by `blankWithAMark_isNotTrimmed` (documents). The laws
property test leaves lone combining marks out.

## S2-N2. nit — The fold does not cover width, `ı` or `Ø`, while U+200B counts as a blank

All four are pinned "(documents)", as consequences of decision #23's wording ("case and diacritics") and of
Foundation:
- fullwidth Latin (`ＢＥＮＣＨ`, as a Japanese IME can type it) finds nothing;
- `ı` and `Ø` are letters, not marks, so `ilik` and `oresund` miss them;
- Foundation's whitespace set still holds U+200B, so a zero-width space is trimmed as an outer blank.

If F12 wants width folding, the fix is to add `.widthInsensitive` to `key`. The catalog is English, so this is
F12's call, not a defect.

---

## Attacked and held

- **S2-1 / B1.** Ten takeovers are refused by `duplicateIdentifier("<table> <id>")`, weeks before days before
  slots:
  - a deleted program's week, day or slot;
  - a removed week, day or slot of a live program;
  - a slot under a removed day;
  - two ids at once;
  - a taken slot listed after three new ones.

  Each refusal leaves every row of both programs byte for byte. Afterwards both programs save again with their
  own ids and read back, with exact live counts and the right one active. An id reused in another table is
  accepted (documents).
- **S2-2.** Forty-four damage cases: none returns quietly without seeding. A `REAL`, `TEXT` or `BLOB` maximum
  throws `malformedColumn("exercise.catalog_version")` and writes nothing. A damaged row below an integer
  maximum is refreshed to integer 2, so the seed repairs it. A custom row's damage is ignored. `1.0` and `'1'`
  are no damage, since the column's `INTEGER` affinity stores them as 1.
- **S2-3.** A blob id is repaired on all five program tables, including a blob holding the text id's own bytes.
  The second save is a no-op. A blob program row is left as an inert, inactive orphan that nothing reads.
- **S2-4.** NUL in any of the five text columns domain values reach is refused by column, as a new row and as
  an edit, by save, seed and refresh, and nothing is written; a refused refresh leaves the version unapplied.
  The JSON array columns cannot hold a NUL. U+0001, DEL, U+2400, a literal `\0`, a BOM and other controls are
  stored whole.
- **SF1 / decision #24.**
  - Six launches of an unchanged catalog (2, 2, 3, 3, 3, 1) move only `catalog_version`. `created_at` and
    `updated_at` stay.
  - Each of nine field changes refreshes its row in place and moves only that row's `updated_at`. An entry
    marked custom is no change, and the row stays a catalog row.
  - Deleted rows, a custom row holding a catalog id, a lifter-saved row and a lifter-revived row are never
    written.
  - Lower and equal versions, down to `Int.min`, change no byte.
  - Alternatives naming unstored ids refresh and read through `all`, `exercise` and `search`.
  - One inexact entry rolls back the whole refresh, and the corrected catalog then applies.
  - A row the catalog stops listing keeps its version, and is refreshed when a later catalog lists it again.
  - A damaged catalog row is repaired by an unchanged upgrade.
  - Every case is idempotent across repeated launches.
- **SF2.** Over 60 seeds, `search` equals `all()` filtered by `ExerciseSearch.matches` and both filters, and
  `all()` equals `ExerciseSearch.sorted`. Both `matches` agree. A name finds itself. The name order is a strict
  total order that `sorted` follows whatever the input order. Folding holds across case, both accent forms,
  Turkish İ, final sigma, and outer blanks including NBSP, U+3000, U+0085 and U+2028. Empty and blank queries
  match everything, even an empty name.
- **N1.** Three identical saves of a custom exercise keep `updated_at`. A change and a revival move it. A
  lifter's unchanged save of a catalog row clears the version without moving `updated_at`.
- **N2.** Deleting an inactive program leaves the active one. Deleting the active one clears its flag. A revival
  with a later `updated_at` is never active, and a save makes it active again.
- **N4.** See the mutants: the observation tests fail on a spurious emission.

**Noted, not findings:**
- **A lifter's save clears `catalog_version` without moving `updated_at`, so the change does not sync.** Under
  M4, another device would still see the row as a catalog row. It could refresh the row over the lifter's edit,
  and its newer `updated_at` would then win the merge. Today nothing reaches this, because F12 edits custom
  exercises only. M4 should decide whether "the lifter's" is synced state.
- **One damaged `catalog_version` maximum stops every upgrade, loudly and for good.** It throws on every launch
  (F07 logs and carries on), and no seed repairs it. Only a lifter's save of that row clears it. This is the
  outcome round 1 accepted. It is no longer silent.

## Verdict

**G2 cannot close for S2 yet, but it is one small fix away.**
- S2-1 to S2-4 are closed.
- SF1, SF2, N1, N2 and N4 hold on the host and on both simulators.
- Every one of 19 mutants of the fix is killed.
- The only edit to my tests is the decided S2-4 one.
- S2-5 is a minor, damage-only regression of the S2-1 fix: three query strings, verified in the scratchpad.

Once S2-5's test passes, G2 closes. A re-run of `ProgramIdentityCloseoutAdversarialTests` and the gate is
enough; no further adversarial round is needed. S2-N1 and S2-N2 are nits that do not block.

---

# Slice S3 — adversarial round 1

Independent adversarial pass over `feat/F05-s3` at `f5ab3fb` (S3: `GRDBWorkoutRepository`, `GRDBStatsQueries`,
their records and `WorkoutRows`, the two history contracts, `Seeders+History`, the v001 fixture). As the
orchestrator's brief for this round asked, I read the brief, the S3 notes and the product code first; my
fixtures are still my own (`S3Kit`), not `Seeders` or the contracts' workouts, and my oracle (`HistoryModel`) is
written from the protocols' doc comments and the notes' decisions, never from the SQL. No product code and no
test of the implementer's was edited. Mutants and the proposed fixes ran in copies of `LedgerKit` in the
scratchpad (`f05s3-g2/mut`, `f05s3-g2/fix`), never in the worktree.

**Convention** (as in S1 and S2): a failing test is a bug or a minor bug and stays in the branch as a regression
test; a spec question or a nit is pinned by a passing test marked "(documents)".

## What I wrote

60 tests in 14 files under `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`, plus five support files (`S3Kit`,
`S3Database`, `HistoryModel` in three files, `HistoryScript`). Two are nightly-lane only (`.slow`). No wall-clock
assertion outside the nightly timing test; the observation test synchronises on the stream only.

| File | Tests | What it attacks |
|---|---|---|
| `HistoryModelAdversarialTests` + `HistoryModel`, `HistoryScript` | 2 (property; 60 seeds in the PR lane, all seeds nightly) | a random script of 14 operations per seed (materialise, rebuild, set edit, delete; about one in four spoiled: not finished, another workout's row or set id, an id twice) under a random time zone, week start and current time. After every operation the database and the in-memory model must have thrown the same error or neither, a refused call must change no row, and every read (`recent` at five limits, `workout(id:)`, four ranges) and every stats query (all nine, `e1RMByWeek` at six `lastWeeks` up to `.max`) must agree. The second test (nightly) shows the first one bites: a model with any one of 22 faults disagrees within 60 seeds |
| `HistoryContractAdversarialTests` | 2 (25 faults) | the model with no fault keeps all 21 contract clauses; with each of 25 single faults (a plausible wrong fake) the contracts must catch it, or it is listed as a gap (S3-4) |
| `WorkoutAtomicityAdversarialTests` | 4 (17 cases) | criterion 3: a trigger fails the `INSERT` or the `UPDATE` on each of the five tables in turn, for a first materialisation, a rebuild that changes and removes rows on every table, a set edit and a delete: every row and stamp as before, and the same call then succeeds |
| `WorkoutIdentityAdversarialTests` | 4 (10 cases) | seven takeovers of another workout's row or set id (live, deleted, removed, a set under a removed row), through `materialize` and `updateSets`; a workout moving its own ids; a record naming another workout (S3-1), and one naming no stored workout |
| `WorkoutRepairAdversarialTests` | 4 (5 cases) | a workout or exercise row soft-deleted on its own, then rebuilt (S3-2); a blob id on the workout row and on an exercise row (S3-3); a soft-deleted set under a live row |
| `WorkoutValuesAdversarialTests` | 6 (31 cases) | every stored e1RM against an integer oracle (8 weights × 1 to 13 reps, every kind); weights at `Int64.max`, `.min`, ±1 unit and 0, reps and targets at `Int32`'s ends; five values beyond a column (⅛ lb, 10⁻⁸ g, an estimate and a volume beyond `Int64`, NaN) refused with every byte kept; nine dates at the ends of `Double` read back bit for bit and trap no query; nine hostile texts; U+0000 at six places in three columns |
| `WorkoutLifecycleAdversarialTests` | 8 (13 cases) | three identical materialisations change no byte; five not-finished states leave a stored workout of that id; odd durations; a deleted workout rebuilt with other rows; five slot-update edges (unknown, removed, deleted program, one slot twice, inactive program); a miss cleared and recorded again, and a negative week; each of 19 stored fields changed one at a time; delete keeps misses and `workout_health` (documents) |
| `WorkoutEditAdversarialTests` | 5 (9 cases) | an edit's e1RMs and totals, and which rows it stamps; removing every set; five targets no live workout has; four bad edits (a sibling row's set, an id twice, an inexact weight, a non-finite tick); what an edit leaves stale (documents, notes question 4) |
| `HistoryReadAdversarialTests` | 6 (11 cases) | ties on `ended_at` in six storage orders; ranges and limits at their edges (empty, ±∞, `.max`, `.min`); an unreadable workout inside the limit (documents, S3-N1); rows of another phase or with no end (documents, S3-N2); the observation through records, misses, a no-op edit, a workout outside the limit, damage and repair; sixteen racing rebuilds |
| `StatsQueriesAdversarialTests` | 8 (20 cases) | which kinds each query counts (documents, notes question 6); ties for the Last line, the bests and `recentlyLogged`; `personalRecords` order under ties, in six storage orders; a swapped or dropped row; only deleted workouts; reps summing beyond `Int64` (documents, S3-N3) |
| `StatsWeeksAdversarialTests` | 5 (51 cases) | 6 time zones × 7 week starts; the week's first instant on five clock-change days and Samoa's skipped day, to the millisecond; ISO week 53 of 2026; a workout that crosses midnight (documents, notes question 7); `lastWeeks` at `.min`, −1, 0, 1, `.max`, and a `now` long before or after every workout |
| `MigrationFixtureAdversarialTests` | 5 | criterion 12: the fixture's `sqlite_master`, columns, foreign keys and indexes equal a fresh `LedgerDatabase.inMemory()`; today's migrator and `open(at:)` change no row; every stored estimate and total recomputed; each fixture workout rematerialises as a no-op; a `v002` that rebuilds `workout` (create, copy, drop, rename) and drops an index keeps every row |
| `StatsWorstCaseAdversarialTests` | 1 (nightly) | criterion 9 in the worst shape: 20,000 sets of one lift, each at its own weight, 400 workouts in one week, two records each |

## Results

- **Host** (`swift test --filter 'LedgerDomainTests|LedgerPersistenceTests'`, exit 1 as expected):
  `LedgerPersistenceTests` 330 tests, **326 pass, 4 fail**, all 4 mine and all expected (S3-1 to S3-3).
  `LedgerDomainTests` 762 pass. The implementer's and the S1/S2 tests all pass beside mine.
- **Lint** (`scripts/check.sh --lint-only`): exit 0. Format, `swiftlint --strict`, the package graph and pins and
  the script tests pass with my files; they add no compiler warning.
- **Simulators** (through `sim-lock.py`; `-only-testing:LedgerPersistenceTests`; logs: scratchpad
  `f05s3-g2/sim-*.log`). I did not run the full gate, since four bug tests fail by design.
  - iOS (`PR`, iPhone 17, 27.0): exit 65. 329 tests: 318 passed, 7 skipped by design, 4 failed, the same four.
  - watchOS (`PR-Watch`, Apple Watch Series 12 (46mm), 27.0): exit 65. The same 318 / 7 / 4.
- **Criterion 9, worst case** (`Nightly` and `Nightly-Watch`, `StatsWorstCaseAdversarialTests` alone): passes on
  both, exit 0. Eight queries are under 8 ms. `weeklyVolume` over 20,000 distinct weights is **33 ms on the iPhone
  simulator, 34 ms on the watch simulator** and 35 ms on the host, of a 50 ms budget (S3-N4).
- **Model test at depth** (host, by hand): 3,000 seeds × 14 operations agree; all 22 visible faults are caught.
- **Proposed fixes** (scratchpad `f05s3-g2/fix/proposed-fixes.diff`, 35 added lines in two files): with them the
  whole of `LedgerPersistenceTests` passes on the host, the implementer's tests included.
- **Mutants** (84, one at a time, host, the whole of `LedgerPersistenceTests`; `f05s3-g2/mut/mutants.py` and
  `final-status.txt`). 78 are killed, 6 survive.
  - **The 6 survivors change nothing through the API**; they differ only on rows the repository never writes:
    M30 (`Query.sets` without the exercise's `deleted_at`), M41 and M42 (`updateSets`' owner query without either
    `deleted_at`: the strict read that follows refuses anyway), M60 (`lastWeeks >= 0`: an empty window), M74 and
    M78 (`personalRecords` without the workout's `deleted_at` or phase). M30 and M74 differ exactly in S3-2's
    state.
  - **17 are killed by my tests only**, so the implementer's tests and contracts miss them:
    - a column: `original_exercise_id` written as the performed exercise (M08), `is_superset_with_previous`
      (M09) and `is_deload` (M10) always false (no fixture of theirs sets one), a record's `achieved_at` rounded
      to the second (M17);
    - identity: the exercise owner check on live rows only (M19; their clause removes no row), deleted record
      rows counted as stored, so never revived (M33), a cleared miss never recorded again (M44), negative weeks
      dropped (M48);
    - order: ties of `recent` and `workouts(in:)` (M24, M25, M83), of the Last line's workout (M52), of
      `recentlyLogged` (M76), of `personalRecords` (M79);
    - stats: warm-ups counted for the bests (M54), `bestE1RM` counting every kind (M56: their drop set has the
      lower estimate), the week key taken an hour before the end (M80).
  - 8 are killed by the implementer's tests only (strict reads of damaged rows, which I did not repeat), and 53
    by both.

| Class | Count | Findings |
|---|---|---|
| bug | 0 | |
| minor bug | 4 | S3-1, S3-2, S3-3 (failing tests), S3-4 (contract gaps, pinned) |
| spec question | 4 | S3-Q1 to S3-Q4 (pinned "(documents)"; three are the notes' own questions 4, 6, 7) |
| nit | 4 | S3-N1 to S3-N4 |

**Verdict:** G2 cannot close for S3 yet, and it is three small fixes away. Criteria 3, 4, 5, 6, 9, 10 and 12 hold
on the host and both simulators, and the repository and the nine queries agree with an independent model over
3,000 random histories. No finding is reachable by a lifter today: S3-1 needs a caller's mistake, S3-2 and S3-3
need damage or a foreign writer.

---

## S3-1. minor bug — A record that names another workout replaces that workout's record row, silently

`PersonalRecordRecord.rowID` derives from `record.workoutID` and the record's place in `prs`, and `encode` writes
`workout_id = record.workoutID`. `materialize(workout, …, prs:)` never checks that a record names `workout`. So
`materialize(B, prs: [r])` with `r.workoutID == A` computes the id of **A's** record at that place and upserts
over it. `WorkoutRows.refuseOtherWorkoutsIDs` says "a personal record's id derives from its workout's, so it
cannot clash"; that holds only when the record's workout is the one being written. This is the class of S2-1,
on the one table the owner check leaves out.

Observed:
- A's stored bench record is gone; in its row is B's squat record, still under `workout_id = A`.
  `personalRecords(bench)` loses A's record and `personalRecords(squat)` shows one for A, which did no squat.
- B stores `pr_count = 1` and no record row; A's `pr_count` still counts the record it lost.
- A record naming a workout that is not stored fails on the foreign key (`DatabaseError`, SQLite 19) and stores
  nothing: loud, but not by name.

**Reach.** `PersonalRecords.detect` stamps `workout.id`, so only a caller passing records detected for another
workout hits it: F10 materialising with a list it kept from the previous finish, or a rebuild that reuses one.
Nothing at the call says so, and the damage is to the other workout.

**Repro** (fails): `WorkoutIdentityAdversarialTests.recordOfAnotherWorkout_doesNotReplaceItsRecords`:
```swift
try await stack.materialize(first, prs: [own])            // own: bench e1RM, workoutID = first
let foreign = S3Kit.record(squat, .estimatedOneRepMax(.pounds(999)), in: first)
try? await stack.materialize(second, prs: [foreign])      // expected: throws, or stores under second
try await stats.personalRecords(exerciseID: bench)        // expected: [own]; actual: []
```
**Fix** (verified in the scratchpad): refuse it before any row is written, three lines in `materialize`:
`if let foreign = prs.first(where: { $0.workoutID != workout.id }) { throw … }`, with a contract clause. The
other choice, deriving the id and `workout_id` from the workout being written, makes the record read back with
another `workoutID` than it was given.

## S3-2. minor bug — A rebuild does not repair a workout whose row, or one of whose exercise rows, was soft-deleted alone: rows the workout no longer has stay live

`WorkoutRows.write` reads the stored children through the **live** workout row (`Selection.one`) and, for sets,
the **live** exercise rows (`Query.sets`). A live row under a soft-deleted parent is in none of those lists, so
the diff never soft-deletes it. The upsert then revives the parent, and the old children are back.

Observed, after `UPDATE workout SET deleted_at = …` (or the same on `workout_exercise`) and a rebuild with one
exercise fewer and three sets fewer: `workout(id:)` returns two exercises where the state has one, and five sets
where it has two; the live row counts and `weeklyVolume` include them. Nothing throws. The notes' decision 16
says "materialising the workout again repairs it".

**Reach.** Damage or a foreign writer only: the repository's own `delete` soft-deletes every row. Under M4's
sync, rows arrive one at a time, so a parent's deletion can be applied before its children's; a rebuild in
between then leaves this state for good, since the children's deletions are then older than their rows.

**Repro** (fails, both cases): `WorkoutRepairAdversarialTests.loneSoftDelete_isRepaired`.

**Fix** (verified in the scratchpad, about 15 lines in `WorkoutRows`): diff the children against every live row
under the workout's id, whatever the state of the rows above them: exercises and records by `workout_id` with
no `deleted_at` test on the workout, and sets through the workout's exercise rows, live or deleted. The stored
workout row itself stays "live only", or an unchanged deleted row would not be revived. `delete` then also
clears such leftovers. Every other test passes with it.

## S3-3. minor bug — A workout or exercise row whose id is a blob reads as a workout with no exercises, or an exercise with no sets

`ColumnReader.text` accepts a `BLOB` holding UTF-8, so `identifier("id")` accepts an id stored as a blob of its
own text. SQL does not: `workout_exercise.workout_id IN (…)` and the join on `logged_set.workout_exercise_id`
compare a blob with text and match nothing. `fetch` groups children by the id's `DatabaseValue`, with the same
result.

Observed, after `UPDATE workout_exercise SET id = CAST(id AS BLOB)` on one row:
- `workout(id:)`, the strict read, returns the workout with that exercise holding **no sets**, and throws
  nothing. `recent` lists it the same way. The stats lose the sets (the volume drops, silently). A new write
  repairs it, as for any damaged id (S2-3).

And after `UPDATE workout SET id = CAST(id AS BLOB)`:
- `recent` lists the workout with **no exercises**; `workout(id:)` returns `nil`.
- A new materialisation inserts a second row beside it, since the text id finds no row. `recent` then lists the
  workout **twice**, once whole and once empty, under one `WorkoutID` (a `ForEach` over it has a duplicate id),
  and `sessionsCompleted` counts two. No write ever removes the blob row.

This breaks the rule the notes and `DamagedWorkoutRowTests` state: a damaged workout "throws by name" or is
"left out", "never … a rounded number", that is, never another value. It is the kin of the dangling-parent
case, which the implementer's `danglingParent_isRepaired` accepts as "reads without the row until a write"; the
difference is that here the reader holds the damaged row in its hands, and the workout-row case is never
repaired. **Reach:** damage or a foreign writer only, the class of S2-3.

**Repro** (fail): `WorkoutRepairAdversarialTests.blobExerciseID_neverReadsAsAnEmptyExercise` and
`blobWorkoutID_neverReadsAsAnEmptyWorkout`. Each accepts either sound outcome: the read fails or leaves the
workout out, or it reads whole.

**Fix** (verified in the scratchpad, 9 lines in `WorkoutRows.fetch`): require `TEXT` storage for the `id` of a
workout row and of an exercise row, and throw `malformedColumn("workout.id")` otherwise. `workout(id:)` then
throws, the lists leave the workout out, and after a new materialisation it is listed once. Left as it is by
that fix, and for the orchestrator to accept or not: the blob workout row still counts in `sessionsCompleted`
(`AND typeof(id) = 'text'` there would end it), and the stats cannot see the sets under a blob exercise id until
a write repairs it.

## S3-4. minor bug (contract gap) — Ten plausible wrong fakes pass both history contracts

F07's in-memory fakes are tied to the GRDB semantics by `WorkoutRepositoryContract` and `StatsQueriesContract`
alone. An honest in-memory history keeps all 21 clauses, so the contracts are implementable without a database.
Of 25 single-fault fakes, the clauses catch 15 and let these 10 through. Each is observable against the GRDB
types (the model test catches every one within 60 seeds), and six match a mutant of the product code that only
my tests kill.

| Fault the contracts miss | Why no clause sees it |
|---|---|
| lists tie-break in insertion order, not by id | no two contract workouts end at one instant |
| the Last line shows the first done working set, not the heaviest | the heaviest set is the first in both clauses that read it |
| the bests count warm-ups | no warm-up is heavier than the best |
| `e1RMByWeek` ignores the calendar's week start and time zone | the contract's calendar is Monday, UTC (the Sunday case is in `StatsQueriesTests`, for GRDB only) |
| a workout's week is its best set's tick, not its end | every contract workout lasts an hour, midweek |
| `sessionsCompleted` counts only workouts with a done set | the clause's empty workout lies outside both ranges |
| `personalRecords` ordered by the workout's end, not `achievedAt` | every fixture record is achieved at its workout's end |
| `recentlyLogged` ties in row order, not id order | each workout of the clause has one done exercise |
| `updateSets` drops the workout's records | no clause reads records after an edit |
| `observeRecent` emits on every write | every write of the clause changes the list |

**Pinned by** `HistoryContractAdversarialTests.wrongFake_isCaughtOrListed` (passes): the ten are listed in
`uncaught`, so a clause that closes a gap fails the test until the list shrinks. **Fix:** one fixture line or
one check each; the cheapest are a tie on `ended_at` in `newestFirst`, a done warm-up above the best in `bests`,
the empty workout moved inside `lastWeek` in `sessions`, two done exercises in one workout in `recentlyLogged`,
and a `personalRecords` read after `updateSets`. This blocks nothing in S3; it should land before F07 writes
its fakes.

---

## Spec questions, pinned

- **S3-Q1 (notes question 6): which sets count for the bests.** Criterion 5 says "done sets"; the slice counts
  `.working` and `.added` for `bestSet`, `bestE1RM` and `e1RMByWeek`, `.working` only for the Last line, and
  every kind for volume, `sessionCount` and `recentlyLogged`. So a session of warm-ups only is a session of the
  exercise with no Last line. Pinned for all four kinds by `StatsQueriesAdversarialTests.kinds_countAsDocumented`.
- **S3-Q2 (notes question 7): a workout's date is when it ended.** A workout begun on Sunday night and ended at
  00:10 on Monday counts whole for Monday's week, for volume, sessions, `workouts(in:)` and the e1RM chart, even
  when every set was ticked on Sunday. Pinned by `StatsWeeksAdversarialTests.midnightCrossing_countsForTheWeekItEndedIn`.
- **S3-Q3 (notes question 4): what `updateSets` leaves stale.** Exactly the `personal_record` rows and
  `pr_count`. Everything computed from sets moves. So after a lifter corrects a typo (225 to 125), History still
  lists both records of that workout, above the best estimate any stored set gives, and a later edit that would
  deserve a record never creates one. Pinned by `WorkoutEditAdversarialTests.edit_leavesRecordsStale`, for F13.
- **S3-Q4 (new): a later `.materialize` brings back a workout the lifter deleted.** `delete` is a soft delete
  that the next materialisation reverses, by design for F04 input 6. But decision #11's delete in History uses
  the same call, and ADR-004 emits `.materialize` again when a late envelope changes a finished log that is not
  yet compacted. The deleted workout then returns, with any `updateSets` edit overwritten by the log's state.
  The host must compact before History may edit or delete, or the delete must be remembered. For F17 and F13;
  pinned by `WorkoutLifecycleAdversarialTests.rematerializeAfterDelete_storesTheNewState`.

## Nits

- **S3-N1. An unreadable workout takes a place of the limit.** `recent(limit:)` picks its rows, then reads them:
  with a damaged workout among the newest two, `recent(limit: 2)` returns one workout though three more are
  readable. A History screen would show a short page. Fix, if wanted: none cheap in SQL; note it on the
  protocol. Pinned (documents).
- **S3-N2. The lists and the stats filter differently.** The stats require `phase = 'finished'`; `recent` and
  `workouts(in:)` do not, and `recent` lists a row with no `ended_at` (last), which `lastPerformance` then fails
  on by name. Only a foreign writer makes such a row. Fix: the same `phase` test in `Selection`. Pinned
  (documents).
- **S3-N3. `weeklyVolume` sums reps per weight in SQL.** Each workout's volume must fit its column, but across
  workouts 2⁶³ reps at one weight overflow `SUM`, and SQLite fails the query ("integer overflow"). Loud, and
  unreachable by lifting. Pinned (documents; 64-bit only).
- **S3-N4. `weeklyVolume` is the one query near its budget in the worst shape:** 33 to 35 ms of 50 over 20,000
  distinct weights, against 4.7 ms in the implementer's shape. The time is the `Decimal` product per distinct
  weight, not the SQL. A real history has a few hundred distinct weights, so this is a margin to know about,
  not a defect; F20 measures a device.

---

## Attacked and held

- **Criterion 3.** A failed statement on any of the five tables, as an insert or an update, in a first
  materialisation, a rebuild, an edit or a delete, leaves every row and stamp, and the call then succeeds. Three
  identical materialisations change no byte after the first. Five not-finished states are refused by id and
  leave a stored workout of that id alone. Every stored e1RM equals the integer oracle; 13 reps and undone sets
  store `NULL`. Each of 19 stored fields is written and diffed.
- **Ids (the class of S2-1), apart from S3-1.** Seven takeovers of a row or set id (of a live or deleted
  workout, a removed row or set, a set under a removed row) are refused by table and id through `materialize`
  and `updateSets`, with every byte of both workouts kept; both then save again. The model test adds random
  takeovers, with the same error text on both sides. A workout moves its own ids freely, and a re-added id
  revives its row, never a second one.
- **Values.** Weights at both ends of `Int64`, one unit and zero, and reps and targets at `Int32`'s ends read
  back equal. ⅛ lb, 10⁻⁸ g, an estimate or a volume beyond `Int64` and NaN are refused as `inexactWeight` with
  nothing written. Dates at ±1e300, ±`greatestFiniteMagnitude`, `leastNonzeroMagnitude`, −0.0 and sub-microsecond
  fractions read back bit for bit, order the lists, and trap no query under UTC, Samoa or Newfoundland time.
  Emoji, SQL, wildcards, control characters and 10,000 characters are stored whole; U+0000 is refused by column
  at six positions.
- **Edits.** e1RMs and totals are exact after an edit; only changed rows are stamped; an edit to no sets, and
  back, revives rows by id. Unknown, deleted and removed rows, and a set or workout id passed as a row id,
  throw `missingRow` and change nothing. Four bad edits change nothing.
- **Lists.** Ties on `ended_at` list by id in every storage order, under a limit too. Ranges hold the lower
  bound and not the upper; empty, infinite and far ranges and limits of `Int.max` and `Int.min` are safe.
- **Observation (criterion 10).** No emission for a change of records or misses only, a no-op edit, a delete of
  an unknown workout, or a workout outside the limit; one for each change of the list; damage hides a workout,
  the stream goes on, and a repair brings it back.
- **Stats (criteria 4 to 6).** 3,000 random histories agree with the model on all nine queries, under four time
  zones, seven week starts and three current times. Ties are deterministic: the Last line's workout by id, the
  best set by reps, `recentlyLogged` by exercise id, `personalRecords` the same in six storage orders. A swapped
  or dropped row stops counting. With only deleted workouts, every query answers as on an empty database.
- **Weeks.** 42 time zone and week start pairs group 24 daily workouts as `WeekCalendar`'s own ranges. On five
  clock-change days and Samoa's skipped day, a workout 1 ms before the week's first instant is last week's and
  one on it is this week's. The last week of 2026 is keyed 2026-W53 on 2 January 2027. `lastWeeks` below 1 gives
  none, `.max` every past week, and no value counts a later week.
- **Criterion 12.** The fixture's schema equals a fresh database's object by object, column by column, with the
  foreign keys and indexes; its header is clean; migrating and opening it change no row; every estimate and
  total in it is what today's code computes; its workouts rematerialise as no-ops; a table-rebuild migration
  keeps every row. The committed file equals the generator's output kept in the scratchpad, and no test opens
  it in place.
- **Criterion 9.** Passes in the worst shape on both simulators (S3-N4).
- **Concurrency.** Sixteen racing rebuilds of one workout: readers see only whole states, and the stored rows
  are exactly one of them.
- **Slot updates.** Unknown, removed and deleted slots are skipped and the workout is stored; one slot twice
  takes the last; an inactive program's slot is written; a cleared miss comes back, once.

**Noted, not findings:**
- **The same records in another order rewrite the record rows**, since a row's id is its place in `prs`. It is
  harmless (the table is local-only), and `detect`'s order is stable.
- **Deleting a workout keeps the misses it wrote and its `workout_health` row** (the notes, decision 1). Pinned
  (documents).
- **`materialize`'s doc on the protocol** says it stores the summary; nothing of it is stored (notes question 1).

## Verdict

**G2 cannot close for S3 yet.**
- S3-1, S3-2 and S3-3 are minor: one needs a caller's mistake, two need damage. Each has a fix verified in the
  scratchpad (35 lines in all, in `GRDBWorkoutRepository.materialize` and `WorkoutRows`), after which all 330
  host tests pass.
- S3-4 is ten gaps in the contracts, pinned; it should be closed before F07 relies on them, and can be closed in
  the same fix round.
- S3-Q1 to S3-Q3 are the notes' own questions, now characterised; S3-Q4 is new and is F17's and F13's.
- The four nits block nothing.

Once the four failing tests pass (`recordOfAnotherWorkout_doesNotReplaceItsRecords`, `loneSoftDelete_isRepaired`,
`blobExerciseID_neverReadsAsAnEmptyExercise`, `blobWorkoutID_neverReadsAsAnEmptyWorkout`), a re-run of
`WorkoutIdentityAdversarialTests`, `WorkoutRepairAdversarialTests` and the gate is enough to close G2; a short
close-out is only needed if the fixes take another shape than the ones above.
