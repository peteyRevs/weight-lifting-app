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
