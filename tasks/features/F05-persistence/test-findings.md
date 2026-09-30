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
