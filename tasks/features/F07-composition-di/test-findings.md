# Slice S1 — adversarial round 1

Independent adversarial pass (G2) over `feat/F07-s1-keys-fakes` at `87812d2` (`git diff a8080ff..87812d2`: the
dependency keys and `Unimplemented*` stubs, the `LedgerFakes` module, `withTestDependencies`, the `RepositoryError`
move, `assertLedgerSnapshot`). I read the brief (criteria 3, 4, 5 and "Inputs from F05"), the implementation notes,
ADR-008, product decisions #23–#30, the F05 contracts and the F05 findings, then the code. No product code was
edited and nothing was committed. Mutants ran one at a time in a copy of `LedgerKit` in the scratchpad
(`f07s1-g2/mut-src/`), never in the worktree.

**Convention** (as in F05): a failing test documents a bug, minor bug or nit and stays failing until the fix; a
spec question is pinned by a test that fails on the behaviour I propose, and says so in its name.

## What I wrote

The differential suites drive GRDB in-memory and `InMemoryStores` with the same seeded script and compare every
outcome (same error or none) and every read after every step. They reuse F05's generators (`HistoryScript`,
`ProgramEditor`, the event store model's envelopes) and read helpers (`HistoryModelAdversarialTests.reads/stats/
bests`), so the fakes are held to what GRDB was held to. No wall-clock assertion anywhere; the observation tests
synchronise on the streams only.

| File | Tests | What it attacks |
|---|---|---|
| `LedgerPersistenceTests/Adversarial/FakesHistoryDifferentialAdversarialTests` | 2 (property, 60 seeds each) | `HistoryScript` (materialise, spoiled workouts, `updateSets` across workouts, deletes and takeovers of deleted ids) on both: outcomes, a refused call leaves the fake unchanged, every read, every stats query under random zones/week starts/now, `bests(before:for:)`; then two programs with workouts materialised with slot updates (live, dropped, deleted, unknown, repeated slots), saves dropping and restoring a slot, deletes and activations: outcomes, `active()`, `recent` |
| `…/FakesCatalogDifferentialAdversarialTests` | 2 (property, 60 seeds each) | `ProgramEditor` builder sessions on program 1 while program 2 takes slot, day and week ids program 1 holds or held, U+0000 in a name or tag (with and without a repeated slot), deletes, `setActive` of live, deleted and unknown ids; catalog seeds at random versions 0–4 with repeated ids, clashing names (case, diacritics, full width, `%`, `_`), U+0000, interleaved with custom and catalog saves: outcomes, `all()`, `exercise(id:)`, 36 searches |
| `…/FakesStoreDifferentialAdversarialTests` | 2 (property, 60 seeds each) | settings with random fields saved in turn; event appends (duplicates, rivals, seqs across 2^63, every event kind with extreme fields) and compactions: results, logs, `highestSeq`, listings, `unreadableCount`, `newestWallClock` |
| `…/FakesBoundaryAdversarialTests` | 5 (19 cases) | one call on fresh GRDB and fresh fakes: ⅛ lb weights, a 10⁹ kg set, ±∞ dates, unnormalised plates, NaN weights, a slot naming an unstored exercise, two faults in one workout; deleted programs/workouts and held set ids |
| `…/FixturesDatabaseAdversarialTests` | 4 | the preview seed stored through GRDB as launch would (catalog seeded first), and the preview's fakes answering every read and stats query as that database does; the seed session materialised with slot updates; `history(weeks: 20/60)` ids distinct, deterministic, storing whole |
| `LedgerDependenciesTests/Adversarial/FakeObservationAdversarialTests` | 13 | first value before the call returns, only changes emitted, a refused write emits nothing, 50 subscribers, 500 racing writers (the stream sees exactly 0…500 in order), racing materialisations keep records a function of history, a consumer writing back from inside the stream, cancelled and dropped streams, slot updates reaching `observeActive`, 100 racing appends; `withTestDependencies` in 19 parallel tasks, fresh UUIDs per run, the stats' date (F7-6) |
| `LedgerSyncTests/Adversarial/FakeLinkBusAdversarialTests` | 11 | determinism with every knob on (5 endpoints, broadcast, loss, duplication, delay, partition and heal), no duplicate unless configured (50 seeds), duplication 1 → exactly two copies, arrival order and send order on ties, FIFO without delay, partitions symmetric and per pair, heal before arrival, 200 endpoints, empty bus, loss 1; negative `advance` and a foreign endpoint (F7-7) |

## Results

- **Host**, my suites: 39 tests; **32 pass, 7 fail**, all expected: the four boundary tests F7-1 to F7-4 (16 of 19
  cases; the 3 "held" cases pass), F7-6, and the two F7-7 tests. Every random differential (8 × 60 seeds) passes:
  inside what the contracts and F05's generators exercise, the fakes answer exactly as GRDB does.
- **Host**, the implementer's suites beside mine (`InMemoryContract|Fixtures|DependencyKeys|PreviewValue|
  UnimplementedStub|FakeTransport|SettingsRepository|EventStore`): all pass.
- **Lint**: `scripts/check.sh --lint-only` exit 0 with my files (format, `swiftlint --strict`, package graph, script tests).
- **Full gate**: not run, by the brief's rule (my documenting tests fail by design).
- **Release** (criterion of ADR-008): see F7-5 and "Attacked and held".
- **Full host run** (`swift test`, whole package, exit 1): every failure is either `LedgerDesignTests`' Archivo
  font suites (52 issues, host-only, as on `main`) or one of my 7 documenting tests; all other tests
  pass, with the implementer's 13 known issues (criterion 3) recorded as known.
- **Mutants of the new code** (24, one at a time in a scratchpad copy; results `f07s1-g2/mutants/results.txt`):
  every non-equivalent mutant is killed by the implementer's tests, mine, or both.
  - Killed by both (15): tie order of `newestFirst` (M1), ids held by another workout accepted (M2), delete not
    replaying records (M3), `updateSets` reaching a deleted workout (M4), a saved catalog row keeping its version
    (M8), unchanged values emitted (M9), no first value (M10), drop sets counted in bests (M11), event append not
    all-or-none (M16), week ids of other programs unchecked (M18), `recentlyLogged` counting undone sets (M21),
    "Last" showing the lightest set (M22), misses merged instead of replaced (M23), `setActive` of a deleted
    program (M24); and the delivery order of messages due together (M14).
  - Killed by the implementer's only (3): partition not checked at delivery (M13), reads keeping `lastPerformance`
    (M17), `withTestDependencies` leaving the calendar (M19). Covered; my scripts never set those inputs.
  - Survived both, **equivalent** (6): misses written into a deleted program (M5) and a deleted program left
    active (M6) — a deleted program is unreadable and a revival replaces it whole; seeding refreshing a row of the
    same version (M7) — unreachable behind the applied-version guard; `bests(before:)` with `<=` (M12) — equal
    place means equal id, already excluded; writes not done on a copy (M15) — every write body throws before it
    mutates, so the copy is defensive today (it matters once F7-1 adds checks); duplication drawn with `<=` (M20) —
    differs only when the generator returns exactly 0.0.

| Class | Count | Findings |
|---|---|---|
| bug | 1 | F7-1 |
| minor bug | 2 | F7-2, F7-5 |
| spec question | 2 | F7-3, F7-6 |
| nit | 4 | F7-4, F7-7, F7-8, F7-9 |

**Verdict:** G2 cannot close for S1 yet. Criteria 3, 4 and 5 hold: every contract runs on the fakes, the fakes match
GRDB on every random script inside the contracts' ground, observation is race-free, and the keys fail by name. But
F7-1 is a real gap in what the fakes are for: they accept every weight and date the database refuses at ADR-007's
boundary, so F08–F15 tests cannot see that error path. F7-2 and F7-5 are small fixes. F7-3 and F7-6 are for the
orchestrator; the nits can ride along.

---

## F7-1. bug — The fakes accept weights and dates the database refuses (ADR-007's storage boundary)

The GRDB stores refuse, at the column codecs, any weight that is not a whole number of 10⁻⁷ g or lies beyond
`Int64` (`inexactWeight`), and any non-finite date (`nonFiniteDate`): set weights, targets, steps, start loads,
the derived e1RM and volume, `startedAt`, `endedAt`, `doneAt`. ADR-007 put that check at the storage boundary on
purpose: the domain may compute a weight that cannot be stored exactly, and the store must say so rather than
round. None of the fakes checks either. Every case below succeeds on the fake and throws on GRDB:

| Call | GRDB |
|---|---|
| `materialize` with a set of ⅛ lb, a target load of ⅛ lb, or a 10⁹ kg set | `inexactWeight(…)` |
| `materialize` with `startedAt`, `endedAt` or a set's `doneAt` at +∞ | `nonFiniteDate` |
| `updateSets` with a ⅛ lb set | `inexactWeight(227079.68023125)` |
| `ProgramRepository.save` with a slot start load of ⅛ lb | `inexactWeight(56.69904625)` |
| `ExerciseRepository.save` / `seedIfNeeded` with a default load of ⅛ lb | `inexactWeight(56.69904625)` |

**Reach.** The fakes are what F08–F15 are tested against (and what previews run on). A feature that hands the
store an unrounded weight — a kg ⇄ lb conversion at three decimals, a percentage of a training max, a plate
remainder — passes every store test and throws on the device, where the app's error path for a failed
materialisation (the lifter's finished workout) has never run. This is exactly the bug class ADR-007 exists for,
and the fake hides it.

**Repro** (fails): `FakesBoundaryAdversarialTests.exactness_fakeAnswersAsGRDB` (10 cases), e.g.
```swift
var workout = S3Kit.workout(1, [RowSpec(bench, [set(100, 5)])])
workout.exercises[0].sets[0].weight = .pounds(0.125)
try await grdb.workouts.materialize(workout, slotUpdates: [])   // throws inexactWeight(227079.68023125)
try await fakes.workouts.materialize(workout, slotUpdates: [])  // succeeds; recent() has it
```

**Fix.** Share the predicate rather than copy it, as `ExerciseSearch` is shared: move "a whole number of 10⁻⁷ g
within `Int64`" (today `ColumnCodec.e7g`) and "a finite date" into `LedgerDomain` (e.g. `Weight.storageUnits()
throws(RepositoryError)`), have `ColumnCodec` call it, and have each fake run it over every weight and date GRDB
encodes (including the e1RM and volume it derives) before its own checks, in GRDB's order (see F7-4). Then add the
cases above to the contracts (`WorkoutRepositoryContract`, `ProgramRepositoryContract`,
`ExerciseRepositoryContract`), so both implementations are held to them by name.

## F7-2. minor bug — Settings and envelopes are stored as given, not as their encoding stores them

`GRDBSettingsRepository.save` stores `Settings` as JSON, and `load()` decodes it; `GRDBWorkoutEventStore.append`
encodes each envelope. The fakes keep the Swift value. Where the encoding is not the identity, they differ:

- `PlateInventory.plates` is a `public var`. Its `init` and decoder normalise (positive, no repeats, heaviest
  first), assignment does not. Saved with `plates = [5, 45, 5, 0]` lb, GRDB loads `[45, 5]`; the fake loads
  `[5, 45, 5, 0]`.
- A NaN weight (`Weight(grams: .nan)`) in settings or in an envelope: GRDB throws `EncodingError.invalidValue`
  ("A non-finite decimal has no exact text"); the fake stores it and returns it.

**Reach.** F14's plate-inventory editor is the obvious writer of `plates`. Its tests would pass on the fake with an
unsorted list the app never shows; plate math (rule 38) reading the inventory back would see a different list in
tests and in the app. The NaN case is the event-store twin of F7-1: F10/F17 tests would never meet the
`EncodingError` the device throws.

**Repro** (fails): `FakesBoundaryAdversarialTests.encoding_fakeAnswersAsGRDB` (3 cases).

**Fix.** `InMemorySettingsRepository.save` encodes with the same `JSONEncoder` settings (sorted keys) and stores the
decoded value (so it throws `EncodingError` and normalises as GRDB does); `InMemoryWorkoutEventStore.append` encodes
each envelope first. Both are a few lines. The random settings differential (`settings_fakeMatchesGRDB`) then also
covers unnormalised inventories.

## F7-3. spec question — A program whose slot names an exercise that is not stored saves on the fake

GRDB refuses it with SQLite's foreign-key `DatabaseError` (F05 "Inputs": seed the catalog before any program is
saved). `InMemoryProgramRepository` says in its doc comment that it does not check, "which only a database's
foreign key can do". But `InMemoryStores` holds the exercises beside the programs, so the linked fake could check,
and F07 S2's own launch order (seed, then programs) is exactly what such a check would test.

**Reach.** F08 (onboarding writes the seed program) and F11 (builder, custom exercises) can save a program naming
an exercise that was never saved — a custom exercise created in the same flow, saved in the wrong order — and pass
every test.

**Repro** (fails on the behaviour proposed): `FakesBoundaryAdversarialTests.foreignKeys_fakeAnswersAsGRDB`.

**Question for the orchestrator.** (a) Have GRDB translate the foreign-key failure into a named case (e.g.
`RepositoryError.missingRow("exercise <id>")`), add a contract clause, and let the linked `InMemoryStores` program
repository refuse the same way (the standalone `InMemoryProgramRepository()` stays permissive for the contracts'
`ProgramRepositoryContract.exercises`); or (b) accept and document it in the brief's "fakes differ from GRDB" list
(which does not exist yet; F7-1/F7-2 would go there too if not fixed). I recommend (a): a raw `DatabaseError` is
also what F05's error doc says callers must not need to understand.

## F7-4. nit — With two faults in one workout, the fake throws a different error than GRDB

`InMemoryHistory.store` says it throws "`duplicateIdentifier` as the GRDB repository orders it", and it checks all
ids first, then U+0000. GRDB checks other workouts' ids, then writes the workout row (its U+0000 check), then the
exercise rows (repeated exercise ids, then each exercise's U+0000), then the set rows (repeated set ids). So:

| Workout | GRDB | fake |
|---|---|---|
| name with U+0000 and a repeated set id | `nulInText("workout.name")` | `duplicateIdentifier("logged_set …")` |
| an exercise name with U+0000 and a repeated set id | `nulInText("workout_exercise.name")` | `duplicateIdentifier("logged_set …")` |

Only the error differs (both store nothing). **Repro** (fails): `FakesBoundaryAdversarialTests.precedence_fakeAnswersAsGRDB`.
**Fix:** order the fake's checks as GRDB writes (other workouts' ids; workout text; repeated exercise ids; each
exercise's text; repeated set ids), or soften the doc comment. Fold into F7-1's fix, which adds checks to the same
sequence.

## F7-5. minor bug — The package no longer builds in Release: `LedgerTestSupport` names fakes outside `#if DEBUG`

ADR-008: "Release builds link an empty module. Nothing outside `#if DEBUG` may name a fake." Every `LedgerFakes`
file is wrapped, and `LedgerDependencies` imports and names fakes only under `#if DEBUG`. But
`LedgerTestSupport/WithTestDependencies.swift` names `InMemoryStores` and `Fixtures` unconditionally, so in Release
`LedgerTestSupport` (and `LedgerSnapshotTesting` and every test target after it) does not compile:

```
$ cd LedgerKit && swift build -c release --only-use-versions-from-resolved-file   # exit 1
Sources/LedgerTestSupport/WithTestDependencies.swift:59:40: error: cannot find type 'InMemoryStores' in scope
Sources/LedgerTestSupport/WithTestDependencies.swift:73:26: error: cannot find 'Fixtures' in scope  (+4 more)
```
On `main` (`a8080ff`, `git archive` into the scratchpad) the same command builds everything: exit 0.

**Reach.** No lane builds the package in Release today, and the apps' Release builds do not compile
`LedgerTestSupport` (see "Attacked and held"), so nothing ships broken. But `swift build -c release`, `swift test
-c release` (e.g. timing the F05 performance budgets in an optimised build) and any Release test plan now fail to
compile, and the ADR's rule is broken in the one module that re-exports the fakes.

**Fix.** Wrap `WithTestDependencies.swift` (and `inMemoryStores(seed:)`) in `#if DEBUG`, as every fake is; check
`swift build -c release` passes (about 40 s on this Mac for the whole package; a candidate for the nightly lane).

## F7-6. spec question — `inMemoryStores(seed:)` freezes the stats' date when it is called

The stats of `inMemoryStores` read `date` "as it stands when called" (documented). So
```swift
withTestDependencies { $0.inMemoryStores(); $0.date = .constant(later) } operation: { … }
```
gives a test whose `@Dependency(\.date)` is `later` while `statsQueries` decides "this week" from `Fixtures.now`.
The order of two lines in `configure` silently changes which week the stats call current; the GRDB stores in S2
will read the injected date at query time.

**Repro** (fails on the behaviour proposed): `TestDependenciesAdversarialTests.statsDate_isTheDateWhenBound`
("F7-6: the stats of inMemoryStores read the date the test set, even when set after binding them").

**Proposal.** Read the date at query time: `InMemoryStores(seed: seed, now: { @Dependency(\.date) var date;
return date.now })` (the task-local values of the operation), which is what S2's composition root will do for
GRDB (`now:` closures over the dependency). Or keep it and make the doc comment a warning in the testing strategy.

## F7-7. nit — `FakeLinkBus` accepts inputs that break its own guarantees

- `advance(by:)` a negative interval moves the bus's time back, so an inbox's arrivals can decrease
  (`[10 s, −10 s]`), breaking "in arrival order". **Repro** (fails):
  `FakeLinkBusAdversarialTests.negativeAdvance_keepsArrivalsMonotonic`.
- An endpoint of another bus (`Bus(endpoints: 8).endpoints[7]` used on a two-endpoint bus) gets an inbox, which no
  broadcast reaches. **Repro** (fails): `FakeLinkBusAdversarialTests.foreignEndpoint_isNotAnInbox`.
- A delay range wider than `Int64.max` nanoseconds (~292 years) traps in `duration(in:using:)`
  (`Int64(Double.random(in: 0 ... 1) * span)`). No test: a trap would take the test process down.

**Fix:** `precondition`/`reportIssue` on a negative interval, an unknown endpoint and an out-of-range delay (or
clamp and drop). Tests of F17 are the only users; cheap to close now.

## F7-8. nit — `InMemoryExerciseRepository(catalog:)` says the catalog was seeded at version 1

Its `version` defaults to 1, while `ExerciseCatalog.version` is 3 and `InMemoryStores.Seed.catalogVersion`
defaults to `ExerciseCatalog.version`. A test that builds the repository with `ExerciseCatalog.seed()` and then
runs the launch's `seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)` goes through the upgrade
path (refreshing every catalog row) instead of the no-op the app performs on a seeded database. **Fix:** default
`version` to `ExerciseCatalog.version`. No test (no observable difference with today's catalog).

## F7-9. nit — `assertLedgerSnapshot` can assert nothing and pass

On a simulator it draws only its own platform's cells, and `themes: []` or `devices: [.watch(…)]` on iOS (or
`[.phone]` on watchOS) leaves the loop with no cell to draw: the test passes with no reference recorded or
compared. The Mac host drawing none is documented (F06 N3); on a simulator it is a silent false green. **Fix:**
`reportIssue` when a simulator run draws zero cells. No test (the wrapper only draws on simulators; the lane runs
there).

## Attacked and held

- **Fakes vs GRDB inside the contracts' ground** — 8 random differentials × 60 seeds: every outcome and read
  agrees for history (records replayed per decision #27 incl. late inserts, edits and deletes; #25's set kinds;
  #26's start dates; ranges, limits ≤ 0, ties by id; `bests(before:)` of stored and unstored workouts), slot
  updates (dropped, deleted, unknown and repeated slots; misses replaced whole; revival), programs (ids held by
  another program live or deleted, U+0000 precedence within programs, deletes, `setActive` of deleted/unknown,
  one active), exercises (#23 search incl. full width, diacritics, `%`/`_`; #24 seeding incl. version 0, repeated
  ids last-wins, saved catalog rows never refreshed, NUL rolling back the whole seed), settings, the event store.
  A refused call never changes the fake (all-or-nothing writes).
- **Observation** (`ObservedState`, `Mutex` + continuations yielded under the lock): the first value is there
  before `observe…()` returns; only changes; a refused write emits nothing; 50 subscribers; 500 racing saves are
  all kept and the stream sees exactly the states 0…500 in order (no lost or reordered emission); a consumer that
  saves from inside the loop does not deadlock (yield only enqueues); cancelled and never-iterated streams end
  without affecting others; slot updates emit on `observeActive` as GRDB's `slot_miss` tracking does; racing
  materialisations leave records equal to the same history stored in turn; 100 racing event appends.
- **Keys (criterion 3)**: the implementer's 13 known-issue cases name each key; the library's default `testValue`
  reports and falls back to the preview value, so an unconfigured test fails loudly. `withTestDependencies` is
  per-task: 19 parallel tests with their own `inMemoryStores` never see each other's writes; UUIDs restart at 0
  every run; no `prepareDependencies` anywhere. `deviceID` live is the nil UUID and logs (documented deviation 6).
- **Fixtures**: the preview seed stores whole in GRDB with the catalog seeded first (every slot names a catalog
  exercise), and the preview's fakes answer every read and per-exercise stats query exactly as that database does;
  the seed session materialises with slot updates; `history(weeks: 20/60)` keeps workout, exercise and set ids
  distinct and is deterministic.
- **`FakeLinkBus` (criterion 5)**: deterministic per seed with every knob on (and different across seeds); never a
  duplicate without duplication (50 seeds × 4 endpoints × 200 broadcasts); duplication 1 gives exactly two copies;
  arrival order with send order on ties; FIFO per pair without delay; partitions cut both directions and only
  their pair; a partition healed before arrival delivers; 200 endpoints broadcast 39,800 messages correctly.
  Criterion 5's "≥ 70" is per seed: I agree with the implementer's open question 2.
- **`RepositoryError` move**: all nine cases identical to the old `LedgerPersistenceError`; `LedgerDomain` imports
  Foundation only; no case carries a GRDB/SQLite type; the typealias keeps every call site.
- **Package graph**: features reach `LedgerDomain`, `LedgerDesign`, `LedgerDependencies`, `LedgerFakes` and
  swift-dependencies only; `LedgerDependencies → LedgerFakes → LedgerDomain`; no feature reaches
  `LedgerTestSupport`, `LedgerPersistence`, `LedgerHealth` or `LedgerSync`, directly or transitively; no feature
  source imports them.
- **Release (ADR-008), apps**: `xcodebuild -configuration Release build` of `Ledger` (generic iOS Simulator) and
  `LedgerWatch` (generic watchOS Simulator), through `sim-lock.py`, fresh derived data: both exit 0, no compiler
  warning. Neither binary has a `LedgerFakes`, `InMemoryStores`, `Fixtures`, `PreviewStores` or `FakeLinkBus`
  symbol. On the host, `swift build -c release` compiles `LedgerFakes` to an object with no global symbols and
  `LedgerDependencies` with no fake symbol; only `LedgerTestSupport` fails (F7-5). (Seen in passing, not part of
  S1: the Release app binaries carry `__profc`/`__profd` coverage counters, presumably from the test plans'
  coverage setting; worth a look before the first archive.)

---

# Slice S1 — close-out round

Close-out of fix round 1 (`git diff 260eb0c..6b63c0f`, notes "### S1 fix round 1"), at `6b63c0f`. Scoped to the
fixes: findings F7-1 to F7-9 and the review's S1-SF1 to SF4, the sanctioned edits to tests, regressions the fixes
could cause, and mutants on the changed lines. No product code edited, nothing committed; mutants ran in a
scratchpad copy (`f07s1-g2/mut2/`), since deleted.

## What I wrote

| File | Tests | What it attacks |
|---|---|---|
| `LedgerPersistenceTests/Adversarial/FakesFaultOrderAdversarialTests` | 3 (property, 100 seeds each) | one to four random faults per value, on GRDB and the linked fakes: workouts (⅛ lb weight/target/step, ±∞ start/end/done, U+0000 in name/tag/exercise, repeated set and exercise ids, ids another workout holds, a volume beyond the column); programs (⅛ lb load/step, two unknown exercises, U+0000 in name/day/tag, a repeated slot, a slot id another program holds); exercises (⅛ lb, NaN kg, U+0000 in either text; save or seed). Same error or none, same state |
| `…/FakesCloseoutAdversarialTests` | 5 | GRDB's `unknownExercise`: a soft-deleted and a custom exercise still count as stored; refused before any row is written, naming the first in slot order; the edit `failedEdit_leavesTheSavedVersion` lost (a day removed, schedules cleared) made to fail midway again with a ⅛ lb last slot, rolling back whole; a volume beyond the column with every set fitting; an e1RM beyond the column with weight and volume fitting (kills N6) |
| `LedgerDependenciesTests/Adversarial/StoresCloseoutAdversarialTests` | 3 | a program seeded without the catalog saved back unchanged (F7-10); stats of `inMemoryStores` queried after the operation (F7-11); inside the operation the stats follow the date, set before or after binding |

Plus my own one-line fix: the unnecessary `try` at `FakeObservationAdversarialTests.swift:213` (the warning the
fix round reported) is gone.

## Results

- **Host, whole package** (`swift test`, exit 1): the round-1 documenting tests all pass now (F7-1 to F7-4, F7-6,
  both F7-7). The failures are F7-10 and F7-11 (mine, expected) and `LedgerDesignTests`' Archivo font suites (52
  issues, host-only, as on `main`). The other runs (415, 770, 19 and 1 tests) all pass. No warning from my files.
- **Lint** (`scripts/check.sh --lint-only`): exit 0.
- **Full gate**: not run, by the rule (F7-10 and F7-11 fail by design). The orchestrator's gate on `6b63c0f` was green.
- **Byte-identical since round 1** (`git diff 260eb0c..6b63c0f`): `FakesBoundaryAdversarialTests`,
  `FakesCatalogDifferentialAdversarialTests`, `FakesStoreDifferentialAdversarialTests`,
  `FixturesDatabaseAdversarialTests`, `FakeLinkBusAdversarialTests`, and in `FakeObservationAdversarialTests` the
  `TestDependenciesAdversarialTests` suite (F7-6's test unedited). Edited: the sanctioned hunks audited below,
  nothing else.

## Close-out of round 1

| Finding | Status | Evidence |
|---|---|---|
| F7-1 (+ none in review) | **closed** | `exactness_fakeAnswersAsGRDB` 10/10 pass, unedited; the fault-combination differential (300 values) and the volume and e1RM probes agree with GRDB, error payloads included |
| F7-2 | **closed** | `encoding_fakeAnswersAsGRDB` 3/3, unedited; random settings and event differentials still pass |
| F7-3 / S1-SF3 | **closed** (option a) | `foreignKeys_fakeAnswersAsGRDB` passes, unedited; `unknownExercise` names the first unknown in slot order on both, before any write on GRDB. See F7-10 for the seeded-state edge |
| F7-4 | **closed** | `precedence_fakeAnswersAsGRDB` 2/2, unedited; random combinations of up to four faults agree on 300 values |
| F7-5 / S1-SF1 | **closed** | `WithTestDependencies.swift` is wrapped in `#if DEBUG`; the orchestrator's `swift build -c release` exits 0 (ADR consequence added). I didn't rebuild the apps in Release this round: their graph is unchanged since round 1, where both built clean |
| F7-6 | **closed**, with a regression: F7-11 | `statsDate_isTheDateWhenBound` passes, unedited; `statsDate_followsTheOperationsDate` |
| F7-7 | **closed** | both F7-7 tests pass, unedited; foreign sends dropped in either role (N11), delay range trapped at `init`/`setLink`, draw clamped |
| F7-8 | **closed** | default `version` is `ExerciseCatalog.version` (`FakeStoreTests`) |
| F7-9 | **closed** (simulator-only) | `SnapshotMatrixTests.noCellHere_failsTheTest`, run by the orchestrator's gate |
| S1-SF2 | **closed** | `.bufferingNewest(1)`, as GRDB's bridge (`ValueObservation+AsyncStream.swift:14`); `FakeStoreTests.slowConsumer_seesTheNewestOnly` kills N13 |
| S1-SF4 | **closed** | standards §4 carries the `Mutex` exception |

## Audit of the sanctioned edits

- **`FakesHistoryDifferentialAdversarialTests.firstLinkedMismatch`** (fake saves `S2Kit.slotExercises`):
  faithful. The GRDB stack holds exactly these exercises, so both sides start from the same database; nothing is
  asserted differently.
- **`FakeObservationAdversarialTests`, eight tests** for newest-only buffering:
  - `firstValue_isTheStateWhenObserved`, `cancelledConsumer_endsOnlyItsStream`, `slotUpdates_emitTheActiveProgram`,
    `refusedWrite_emitsNothing`, `manySubscribers_seeEveryChange`: faithful. Each still proves its claim. The
    first value is read before any write, and "nothing emitted" is proven by the next real change being the very
    next value.
  - `consumerWritingBack_doesNotDeadlock`: faithful. The handshake only removes a race the old code allowed under
    newest-only buffering (120 overwritten before the consumer started); the write-back from inside the loop,
    the point of the test, is unchanged.
  - `unchangedWrites_emitNothing`: **weakened, unavoidably.** With newest-only buffering, a spurious repeat that
    a later change overwrites before the consumer reads is invisible to any consumer. The `removeDuplicates`
    property is now held by the contracts' observe clauses and `FakeStoreTests`. Acceptable; the implementer's
    note says the same.
  - `racingWriters_loseNothing` → `racingWriters_endOnTheFinalState_inOrder`: **weakened, unavoidably.** It now
    proves "no lost update, monotone order", not "every state seen", which GRDB doesn't promise either. Its
    lost-update half (the final state is 500) is intact.
- **`ProgramRepositoryTests.failedSave_changesNothing`** (F05): faithful. A ⅛ lb last-slot load is encoded at the
  slot's write, after the program, weeks, days and other slots (`SlotRecord.encode`). So the fault still fires
  midway and the test still needs the transaction. That agrees with the implementer's statement trace.
- **`ProgramEditAdversarialTests.failedEdit_leavesTheSavedVersion`** (F05 tester): **weakened.** Its fault now
  fires before any row is written, so "every row as it was" no longer proves a rollback of that edit's shape
  (a day removed and schedules cleared in one save). Covered again by my
  `FakesCloseoutAdversarialTests.failedEditMidway_rollsBackWhole` (a ⅛ lb last slot in the same edit), which
  passes: the rollback holds. No finding; recommend the next round of F05 tests keep both.
- Nothing else in my files was edited.

## Attacks on the fixes

- **`StorageBoundary` moved out of `ColumnCodec`:** the bodies moved verbatim (`ColumnCodec.e7g/grams/seconds`
  now delegate); `inexactWeight` keeps the grams given, `nonFiniteDate` unchanged. Every F05 persistence suite
  passes (415 tests, the storage, damage, payload and record suites included), as do all my round-1
  differentials.
- **Codecs in LedgerDomain:** `EnvelopeCodec` and `SettingsCodec` moved with the same bodies (the diff shows only
  `public`, the import, and `LedgerPersistenceError` → `RepositoryError`, the same type). `PayloadV1FixtureTests`
  (committed v1 payloads decode and re-encode equal) pass.
- **`unknownExercise` on GRDB:** raised inside the transaction after other programs' ids and before any write;
  first unknown in slot order (N3 killed); a soft-deleted exercise counts as stored, as the foreign key sees it
  (N2 killed only by my test); a custom exercise counts. Precedence against U+0000, repeats and inexact loads
  agrees with the fake in every random combination.
- **Linked vs unlinked program store:** `InMemoryStores` links (N8 killed); the bare `InMemoryProgramRepository()`
  and seeded programs are unchecked, by design. That gives F7-10.
- **Check order in the fakes:** 300 random multi-fault values agree with GRDB (N5, N7 killed).
- **`FakeLinkBus`:** drop rules hold for a foreign sender or recipient, and time never moves back. The delay trap
  is untested (a trap ends the process).
- **`.bufferingNewest(1)`:** the same policy as GRDB's bridge; both remove duplicates against the last fetched
  value. GRDB's first value is asynchronous, the fake's synchronous (documented, ADR-008 decision 4).
- **Stats reading `@Dependency(\.date)` per query:** right inside the operation, wrong outside it: F7-11.
- **`materialize` writing misses under the history lock:** the lock order is always history → programs; no path
  takes them the other way, so no deadlock. The round-1 nit about a reader seeing the workout before its misses is
  gone.

## Mutants of the changed lines

14 mutants (`f07s1-g2/mut2/out/results.txt`), one at a time. Every non-equivalent one is killed.

| Mutant | Killed by |
|---|---|
| N1 GRDB lets the foreign key fail | implementer (storage clause, `failedEdit`), mine (fault combinations, close-out) |
| N2 GRDB counts only live exercises | **mine only** (`deletedAndCustomExercises_areStored`) |
| N3 GRDB names the last unknown | both |
| N4 dates: only NaN refused | both |
| N5 fake skips the volume | both |
| N6 fake skips the e1RM | **mine only**, after adding `estimateBeyondTheColumn_isRefusedAlike`. It needs a negative set beside it: otherwise the volume, which is never smaller than the e1RM, overflows first |
| N7 fake exercise checks kg before lb | **mine only** (exercise fault combinations) |
| N8 `InMemoryStores` unlinked | both |
| N9 settings encoded, not decoded back | both |
| N10 events kept as given, not as decoded | survives, **equivalent** (the v1 codec round-trips every envelope exactly; GRDB compares decoded with given the same way) |
| N11 bus checks only the sender | mine |
| N12 bus time moves back | mine |
| N13 streams buffer everything | implementer only (`FakeStoreTests.slowConsumer_seesTheNewestOnly`) |
| N14 stats date at bind | mine |

## F7-10. spec question — A program seeded without the catalog can't be saved back

`InMemoryStores(seed: Seed(programs: [Fixtures.seedProgram()]))` stores the program unchecked (decision 4: a seed
is stored state). But saving that same program back unchanged then throws `unknownExercise`, because the linked
exercise store is empty. No database can hold that state: the slots' foreign key means a stored program's
exercises are stored. So the fake refuses its own program. The implementer's
`DependencyKeysTests.inMemoryStores_linksEveryStore` uses exactly this seed shape; it never re-saves. A
feature test (F09/F11 editing the active program) that does will fail on the fake for a reason the app can't
meet.

**Repro** (fails): `StoresCloseoutAdversarialTests.seededProgram_savesBackUnchanged`.

**Options:** (a) `InMemoryStores.init` adds to the exercise store any exercise its seeded programs name that the
catalog lacks (a minimal stand-in, or an issue reported); (b) report an issue when a `Seed`'s programs name
exercises its `catalog` lacks, so the fixture is fixed at its source; (c) document it in `Seed`'s doc. I recommend
(b): it keeps the fake honest and points at the test's own seed.

## F7-11. minor bug — Stats of stores bound in `configure` fail the test when queried after the operation

Fix decision 6 makes the stats read `@Dependency(\.date.now)` on every query. Inside the operation that is right.
Outside it, a store a test kept from `configure` reads the library's test value: the library records
"@Dependency(\.date) has no test implementation" and falls back to the wall clock, which standards §9 forbids in
tests. Before the fix this pattern was deterministic:
```swift
var bound: InMemoryStores?
try await withTestDependencies { bound = $0.inMemoryStores() } operation: { /* materialise */ }
try await bound!.stats.e1RMByWeek(…)   // issue recorded, then answers for today's date: [:]
```
**Repro** (fails, 2 issues): `StoresCloseoutAdversarialTests.statsAfterTheOperation_needNoDependency`.

**Reach:** any store test that asserts on stats after its `withTestDependencies` block, or that hands
`stores.stats` to a context without the dependencies (a `Task.detached`, which the standards forbid, or a
long-lived object outside the scope).

**Fix options:** read the dependency when one is bound and fall back to the date bound at `inMemoryStores` time
otherwise (e.g. `withEscapedDependencies` at bind, or `now: { DependencyValues._current … }` with a captured
default); or keep per-query reading and say in `inMemoryStores`' doc, with a test, that its stats answer only
inside the operation.

| Class | Count | Findings |
|---|---|---|
| minor bug | 1 | F7-11 |
| spec question | 1 | F7-10 |

**Verdict:** G2 does not close yet, though it is close. All nine round-1 findings and the review's SF1–SF4 are
closed with evidence, and the fixes hold under random multi-fault differentials and 14 mutants. The sanctioned
edits are faithful, two of them unavoidably weaker, and none hides a regression. Two new items come from the fix
round itself. F7-11 is a small regression of the F7-6 fix (non-deterministic stats outside the operation). F7-10
is a seed-shape edge of the F7-3 fix, for the orchestrator. If the orchestrator accepts F7-10 as documented and
F7-11 is fixed, or documented with its test turned into a "(documents)" one, G2 closes.

## Fix round 2 verification

Scoped verification of `git diff 7362bd9..ab5c11d` (notes "### S1 fix round 2"), at `ab5c11d`: no re-attack.

**Closed.**
- **F7-10:** `InMemoryStores.init` reports an issue naming every exercise a seed's programs name that its catalog
  lacks (`Seed.missingExercises`, sorted, once each). `seededProgram_savesBackUnchanged` passes (with one known
  issue, as sanctioned). A legal seed (the preview seed, or the program with exactly its exercises) reports
  nothing.
- **F7-11:** `statsAfterTheOperation_needNoDependency`, `statsDate_isTheDateWhenBound` and
  `statsDate_followsTheOperationsDate` pass, all three unedited.

**Audit of the sanctioned edits.** These are the only changes to my files:
- `slotUpdates_emitTheActiveProgram`: the seed gains `ExerciseCatalog.seed()`. Setup only, and faithful: the
  assertions are unchanged.
- `seededProgram_savesBackUnchanged`: faithful to the decision. The illegal seed now fails at its source (a known
  issue matching bench press's id, which the program names first). The original claim, that a stored program
  saves back unchanged, is asserted on the legal seed, the only state a database can hold.
- Nothing else in my files changed.

**Regression check of the two changes**, in a new file
`LedgerDependenciesTests/Adversarial/StatsClockRegressionAdversarialTests` (6 tests, all pass):
- two stores bound in one `configure` both keep the date `configure` ended with;
- nested `withTestDependencies`: inside the inner operation the outer stores read the current (inner) date, then
  the outer one again, and after both operations the outer configured date;
- stores bound by a plain `withDependencies` keep the date at binding and need no dependency;
- the synchronous overload binds kept stores too;
- the preview seed and an exact seed report nothing;
- an illegal seed names each missing exercise once.

A seed with a deleted exercise doesn't apply: a `Seed`'s catalog is a list of exercises, and the in-memory
exercise store has no deletion.

**Mutants of the changed lines** (8, scratchpad copy, since deleted). All killed:

| Mutant | Killed by |
|---|---|
| Q1 `missingExercises` always empty | implementer's `seeds_holdOnlyWhatADatabaseCould`; mine (2) |
| Q2 the illegal seed not reported | the same |
| Q3 the clock always reads the dependency | implementer's `keptStores_answerWithTheConfiguredDate`; mine (4) |
| Q4 the clock never reads the dependency | mine only (`statsDate_followsTheOperationsDate`, the nested case) |
| Q5 the sync overload never binds the configured date | **mine only**, after adding `synchronousOverload_keepsTheConfiguredDate` (no test used the sync overload with kept stores) |
| Q6 the async overload never binds it | implementer; mine (2) |
| Q7 clocks not registered | implementer; mine (2) |
| Q8 bound before `configure` runs | implementer; mine (2) |

**Runs.**
- Targeted host suites (`StatsClockRegression`, `StoresCloseout`, `TestDependencies`, `FakeObservation`): 22 tests
  pass, 2 of them with their known issue.
- `scripts/check.sh --lint-only`: exit 0.
- **Full gate** (`scripts/check.sh` through `sim-lock.py`): **exit 0, `check.sh OK`**. 17 test targets passed (PR)
  and 8 (PR-Watch); coverage thresholds met (LedgerFakes 98.88 %, LedgerDependencies 95.56 %); 492 s.

**Verdict: G2 closes for S1.** Every finding from the three rounds (F7-1 to F7-11) and the review's SF1 to SF4 is
closed with a passing test. The sanctioned edits are faithful, and the fix round's changes hold under the
regression shapes and mutants above.

---

# Slice S2 — adversarial round 1

Independent adversarial pass (G2) over `feat/F07-s2-boot` at `6306b8d` (`git diff f991d69..6306b8d`). Sources: the
brief's launch sequence and criteria 1, 2 and 6; decisions #28, #29 and B4; the notes' "## Slice S2"; then the code.
No product code edited, nothing committed. Mutants ran one at a time in a scratchpad copy (`f07s2-g2/`), since
deleted.

## What I wrote

| File | Tests | What it attacks |
|---|---|---|
| `LedgerAppKitTests/Adversarial/LaunchAdversarialTests` | 4 (one property, 60 seeds) | a first `resume` cancelled by a phase change (what `.task(id: scenePhase)` does); two overlapping resumes; a model of the notes' state machine (first resume in any phase, retries only on `.active`, reopen then reseed, settings and WatchConnectivity once) against random phase sequences with an open or a seed failing until a random step |
| `LedgerWatchAppKitTests/Adversarial/WatchLaunchAdversarialTests` | 4 (the same, 60 seeds) | the same model on the watch, so the two parallel state machines are held to one spec |
| `LedgerAppKitTests/Adversarial/LaunchStorageAdversarialTests` | 7 (10 cases) | #29: a file mode 000, a directory mode 555 (no file may appear), a valid SQLite file that is not Ledger's; #28: programs refused (`unknownExercise`) while unseeded; four unreadable settings rows (later version, non-UTF-8 payload, invalid JSON value, version as text) unchanged across three boots and retries; every store key and `deviceID` bound to the GRDB stores; `-LEDGER_UITEST` gives a new temporary file per launch |
| `LedgerWatchAppKitTests/Adversarial/WatchLaunchStorageAdversarialTests` | 7 (10 cases) | the same on the watch |
| `LedgerPersistenceTests/Adversarial/LocalDeviceAdversarialTests` | 3 (12 cases) | two connections opening one new file at once (10 rounds); rows of the other kind, older and many; a lowercase stored id |

## Results

- **Host, whole package** (`swift test`, exit 1): the failures are my 8 documenting tests (4 per platform: F7-S2-1 ×3,
  F7-S2-2) and `LedgerDesignTests`' Archivo font suites (host-only, as on `main`). Everything else passes,
  the implementer's S2 suites included; the only warning is F05's `PayloadVersionAdversarialTests.swift:29`.
- **The model property test passes on both platforms** (60 seeds each): apart from F7-S2-1, the iOS and watch
  launches follow the notes' sequence, and each other.
- **Lint** (`scripts/check.sh --lint-only`): exit 0.
- **Full gate**: not run, by the rule (my bug tests fail by design).
- **Mutants** (12, `f07s2-g2/out/results.txt`, since deleted): **all killed.** Killed by both the implementer's tests and mine:
  - retries in any phase (iOS R1, watch R6), never reopening (R2, R7), a failed seed marked seeded (R3, R8);
  - WatchConnectivity activated on every resume (R4), settings reloaded on every foreground (R5);
  - the UI-test database being the real one (R10), a device row of any kind chosen (R11).

  Killed by one side only:
  - **R9** (the stats key not bound) by mine only (`everyStoreKey_isBound`);
  - **R12** (the newest device row wins) by the implementer's only (`oldest of two`).

| Class | Count | Findings |
|---|---|---|
| bug | 1 | F7-S2-1 |
| minor bug | 1 | F7-S2-2 |

**Verdict:** G2 cannot close for S2 yet. Criterion 6, #28's and #29's main paths, B4, the bindings and the UI-test
database hold, and the two platforms agree. But F7-S2-1 is a real bug in the state machine: a phase change during
the first resume, which `.task(id: scenePhase)` turns into a cancellation, leaves the lifter's settings unloaded
until the next launch, logged as a fault.

---

## F7-S2-1. bug — A resume cancelled by a phase change leaves the settings unloaded until the next launch

`.task(id: scenePhase)` cancels the running `resume` whenever the phase changes. That happens on any launch whose
phase moves while the first resume awaits: a workout launches the app in the background and the lifter opens it,
or a launch passes through `.inactive` to `.active`. GRDB's async `read`/`write` then throw `CancellationError`.
In `Launch.swift` (both platforms):
- `loadSettings` sets `hasLoadedSettings = true` **before** its `await`. The cancelled load leaves `settings` at
  `Settings.default`, and no later resume retries it. A lifter who chose kilograms sees pounds until the next cold
  launch. And any feature that writes `composition.settings` back (F14) would save the defaults over the row.
- `seedCatalog` and `loadSettings` log the cancellation at **fault** level as `.failed(...)`, though nothing failed.
- `hasResumed = true` before the awaits, and `isCatalogSeeded = true` only after: an overlapping resume (the phase
  changes while the first awaits, before the cancellation lands) starts a second seed (`began seedCatalog` twice).
  It's harmless to the data, since the seed is idempotent, but it does twice the work.

**Reach:** every user whose first launch phase changes during the settings read; with background workout
launches (watch, F17/F20), routinely. Settings drive units, rest, plate math and week start.

**Repro** (fail, iOS and watch):
- `LaunchAdversarialTests.cancelledFirstResume_settingsStillLoad`: kg settings saved, a first resume cancelled,
  then `.active` → `settings == .default`;
- `cancelledFirstResume_logsNoFailure` (`.failed(.seedCatalog)` and `.failed(.loadSettings)` recorded);
- `overlappingResumes_runEachStepOnce` (`began seedCatalog` ×2);
- the `Watch…` twins of all three.

**Fix:** set each "done" flag only after its step succeeded (`hasLoadedSettings` after the load returns, or when
it fails with a real error, keeping #29's "not retried" for an unreadable row). Treat `CancellationError` as "not
attempted": don't log a fault, and leave the step for the next resume. Make the steps idempotent across overlap,
for example with an in-flight flag per step or by serialising `resume` (a stored `Task` that later calls await).
Apply the fix to both copies (open question 1).

## F7-S2-2. minor bug — A failed open writes to the file it could not open

`LedgerStores.open` and decision #29 promise the file is "left exactly as it was" when it cannot be opened. That
holds for bytes that aren't a database (the implementer's case), a directory, an unreadable file and an
unwritable directory (all held here). It doesn't hold for a **valid SQLite file that isn't Ledger's**, or one
whose migration fails partway:
- `DatabaseQueue` switches it to WAL on open;
- the migrator commits `grdb_migrations` (and any migration that succeeds before the failing one) in separate
  transactions.

The file grows from 8,192 to 16,384 bytes, and `-wal` and `-shm` appear, before the launch shows #29's screen.

**Reach:** a file at the app's path that isn't Ledger's arrives only through a botched restore or a foreign
writer. But the same path writes partial migrations whenever a future migration fails on real data. That is the
case #29's "never touch the file" exists for: the next version, or support, would find the file changed.

**Repro** (fails, iOS and watch): `LaunchStorageAdversarialTests.foreignDatabase_isUnavailable_andUntouched` and its
`Watch…` twin (`["ledger.sqlite": 8192] → ["ledger.sqlite": 16384, "-wal": 0, "-shm": 32768]`).

**Fix options:**
- before migrating, check the file read-only: empty, or `grdb_migrations` holding only known ids, with its tables
  as the migrator expects (`hasSchemaChanges` / `hasBeenSuperseded`); throw without writing otherwise;
- or run every pending migration in one transaction (GRDB's migrator can't by default), so a failure rolls all of
  them back;
- or correct the doc and #29's wording to "never deleted, moved or replaced".

The first is the honest one; the WAL switch would still need opening without `journalMode = .wal` until the check
passes.

## Attacked and held

- **Criterion 6:** the handler is assigned first and synchronously on iOS; the watch has no handler. Both state
  machines match the model over 60 random phase sequences with open or seed faults healed at random steps:
  - the first resume runs in any phase;
  - later ones run only on `.active`, reopening then reseeding;
  - settings and WatchConnectivity run once.
- **#29:** bytes that aren't a database, a directory at the path, a file of mode 000 and a directory of mode 555
  all give `databaseUnavailable`, with the listing and every byte unchanged (no file created in the unwritable
  directory); each recovers on the next `.active` once the cause is gone; nothing is bound meanwhile.
- **#28:** a failed seed carries on; no retry in the background; the next `.active` seeds. Meanwhile a program
  naming catalog exercises is refused by name (`unknownExercise`), never half-saved.
- **Settings fallback:** a later payload version, a non-UTF-8 payload, an invalid JSON value and a version stored
  as text each leave `Settings.default` in memory and the row byte for byte the same after three boots with
  retries.
- **LocalDevice (B4):**
  - two connections opening one new file at once agree on one row, in 10 rounds;
  - five older rows of the other kind are never chosen;
  - a lowercase stored id reads as the same device, with no new row;
  - the oldest row of a kind wins (implementer).
- **Binding:** after boot every store key is the GRDB store and `deviceID` is the device row, so none is left on
  a stub or fake. `prepareDependencies` runs only when `preparesDependencies` (the app); tests use
  `withDependencies`.
- **`-LEDGER_UITEST`:** a new temporary file per launch; without it, `Application Support/Database/ledger.sqlite`.
- **Registrar and activator** (by reading; the implementer's suites cover them):
  - sessions behind a `Mutex`, 50 concurrent calls all kept (implementer);
  - the live registrar and activator are held strongly by the composition's environment closures, so the weak
    captures never drop a session;
  - activation runs once per composition (`isCompanionActive`).
