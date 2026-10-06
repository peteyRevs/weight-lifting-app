# F11 test findings (Adversarial Tester)

## Slice S3 — round 1 (G2 tester, 2026-10-06)

Commit under test: `57d12ab` on `feat/F11-s3-program-update` (specification `312728c`), Swift 6.4.

I wrote the tests from the specification's eleven criteria, the planner's sections of the notes ("Saving and a
live workout", "Inputs the implementer needs › S3") and the doc comment of `ProgramRepository.update`. The
expected values come from a model of my own (`UpdateModel`: programs as values) and from `save` given the same
result. I read the two implementations, the implementer's tests and the new contract clauses only after my
tests had been written and run once (31 tests then; three expectations of mine were wrong, see "Corrected").
I have not read the implementer's section of the notes.

**Result: no bug found. One spec question (F11-S3-1). Every test of mine passes (32 tests, 282 cases).**

### What was written

All under `LedgerKit/Tests/LedgerPersistenceTests/Adversarial/`. Three kinds of store: an in-memory database,
a WAL file opened as the apps open it, and the in-memory stores (`UpdateKit.Place`).

| File | Tests (cases) | What it attacks |
|---|---|---|
| `ProgramUpdateRefusalAdversarialTests.swift` | 6 (59) | Criteria 2 to 4. Sixteen results that must be refused, each on three stores: ids another program holds (week, day, slot), a slot id used twice, an exercise that is not stored, another program id (unused; program 2's with program 1's rows; program 2 itself), U+0000 in a name and in a tag, one week, a dangling schedule, a gap in the week indices, 99 sets, an inexact load, a change that throws after computing. The error is the one `save` gives for the same result (or `duplicateIdentifier` naming the result's id), the same on the database and in memory; every row of every table, `updated_at` included, is as before; the change ran once; no watcher heard anything. A program not stored or deleted: `setActive`'s error, the change never runs. Deleted, replaced by `save`, updated again |
| `ProgramUpdateRowsAdversarialTests.swift`, `…EditsAdversarialSupport.swift` | 5 (55) | Criteria 5 and 6. Five routes back to the stored program (as given; rebuilt through every `init` with the weeks backwards; through JSON; reversed and restored; fields taken away and put back), on the active and the inactive program: SQLite counts no changed row, no row differs, no watcher hears it. Fifteen edits: the rows written are exactly the ones the edit names (by table and id), the same rows `save` writes on a twin database, and the two databases are then equal row for row; in memory against `save` and against the database. A watcher hears a ten-row update as one whole program |
| `ProgramUpdateActivityAdversarialTests.swift` | 3 (9) | Criterion 6's last clause: fifteen updates of the inactive program leave the active one active; a result that turns `isActive` on deactivates the other, and one that turns it off leaves none, as `save`. History: a finished workout reads the same after an update deletes its day and every other |
| `ProgramUpdateLostAdversarialTests.swift`, `…LaneAdversarialSupport.swift` | 5 (33) | Criterion 7. The losing sequence through `save` (loses both) and through `update` (keeps both). A hundred concurrent increments through two repositories over one queue end at 100 and return 1 to 100. Sixty increments over two connections to one file. Six lanes racing updates, workout saves with misses and swaps, reads, saves of the other program and `setActive`; half of the seeds through `ProbedStores(yields: 2)`. **A self-check:** the same lanes and the same counter against `ThreeStepPrograms` (read, change, save) do report losses (on 7 or 8 of 8 seeds in my runs; the test asks for half) |
| `ProgramUpdateModelAdversarialTests.swift` | 2 (81) | Criterion 7 against a model: 40 seeds of 36 calls on the database and in memory (updates with nine edits, a change that throws, a refused result, workout saves on either program's slots with stored and unknown exercises, a builder's stale whole save, delete, `setActive`), compared with `UpdateModel` after every call, `isActive` included. A second test shows the scripts reach every case |
| `ProgramUpdateCancelAdversarialTests.swift`, `…CancelRaceAdversarialTests.swift` | 5 (33) | Criterion 8, with a change of ten rows in three tables. Cancelled before the call; from inside the change, before and after it computed; while waiting behind another update whose change is held at a gate (0, 5, 200 and 5,000 yields); at 80 moments that close in on the commit (a call cancelled too early doubles the canceller's wait, one cancelled too late halves it); 30 of 60 concurrent calls cancelled beside a lane of workout saves. Each time: all stored and returned, or none stored and `CancellationError`; no call that was never cancelled fails; the store then takes an update and a workout's save |
| `ProgramUpdateProbeAdversarialTests.swift` | 6 (12) | Criterion 9 and the app's edges: the probe forwards results and errors and records each call; a held update stores nothing, and when let go applies to the program as stored then (a workout's save and another update landed meanwhile); `fail` before and after storing; a held update cancelled; a change that starts another update without waiting for it; fourteen updates and a workout's save read back after the file is closed and reopened |
| `ProgramUpdateAdversarialSupport.swift` | | `UpdateKit` (the three stores, a read that does not disturb activity, SQLite's change count), `UpdateSnapshot`, `UpdateGate` (a change waits at it for at most 20 s, so no test can hang), `ThreeStepPrograms` |

Seeds: `PropertySeed.all.prefix(8)` for the lanes (17, 7936, 15855, 23774, 31693, 39612, 47531, 55450),
`prefix(40)` for the model scripts (17 + 7919·n, n = 0…39), 1106 for the moments of cancellation, and 3, 58,
2026 for the cancelled half. No sleeps; nothing depends on a wall clock.

### Findings

#### F11-S3-1 — spec question — criteria 8 and 9: a cancelled update ends differently on the two stores

Both stores keep criterion 8 as written (all or none; `CancellationError` only for none). They choose
differently, at the same moment:

| The task is cancelled… | Database (memory and file) | In-memory stores |
|---|---|---|
| before the call | `CancellationError`, change not called, none | the same |
| inside the change (before or after it computed) | `CancellationError`, **none** (rolled back) | returns, **all** stored |
| while the call waits behind another write | `CancellationError`, **none**, change not called | returns, **all** stored (none only if the task had not yet entered the call) |
| at seeded moments around the write | none or all | all, except when the task had not started |

Counted in one run of the cancellation tests: the database ended 165 calls with none and 10 with all; the
in-memory stores 83 with all and 5 with none.

Minimal repro (the in-memory half; my tests pin the database's half, which is what ruling 5 asks for):

```swift
let stores = InMemoryStores(seed: …)                    // any stored program `id`
let handle = Mutex<Task<Program, any Error>?>(nil)
let task = Task { try await stores.programs.update(id) { program in
    handle.withLock { $0?.cancel() }                    // set by the test before the change runs
    return renamed(program)
} }
// database: `await task.result` is .failure(CancellationError) and the name is unchanged
// in memory: .success, and the new name is stored
```

Expected: not stated. Criterion 8 allows both; criterion 9 says the in-memory stores follow the database, and
the fake's doc comment says it does not here ("a task cancelled later stores its change whole, where the
database rolls back"), so the implementer chose this knowingly. Why it is worth a ruling: S13's store is tested
over the in-memory stores, and the case it must handle on a phone (the screen goes away while a write is in
flight: `CancellationError`, nothing stored, edits still waiting) is the one the fake never produces after the
call has started. A fake that checked `Task.isCancelled` once more under its lock, after the change returned
and before storing, would end the first two rows as the database does. No test of mine fails for this.

### Attacked and held

- **Criteria 2 to 4** — 16 refusals × 3 stores, the missing and the deleted program × 3 stores, watchers on 2:
  the error equals `save`'s (or `setActive`'s) each time and nothing at all was written.
- **Criterion 5** — 5 routes × 2 programs × 3 stores: zero rows changed by SQLite's count, no watcher woken.
  (An unchanged update of the active program still runs one `UPDATE program SET is_active …` that matches no
  row, exactly as `save` does. It writes nothing and wakes nobody.)
- **Criterion 6** — 15 edits × 2 databases against the rows I listed and against `save`; 15 in memory.
- **Criterion 7** — 100 concurrent increments × 3 stores; 60 over two connections (all 60 stored, none
  refused); 8 seeds × 3 stores of six racing lanes (144 calls each); 40 seeds × 2 stores of 36 modelled calls.
  Inside every change the lane checks that the program it is given holds its own last workout save: it always
  did. The three-step update fails these same tests, so they can see a loss.
- **Criterion 8** — never a part of a change stored, in the 263 cancelled calls one run judges; never an error for a
  caller that was not cancelled; the database's three deterministic endings are pinned (`wasCancelled`).
- **Criterion 9** — probe forwards, holds, fails, and a held call applies to what is stored at release.
- **Criteria 10 and 11** — read, not tested: the four doubles' edits are mechanical (`git diff 312728c 57d12ab`);
  the stub throws as its neighbours do and its test lists the call; no existing contract clause changed (the
  diff of the contract files only adds clauses), no migration, no fixture touched. The whole
  `LedgerPersistenceTests` target passes on the host (see the commands).
- **The implementer's tests** (read afterwards) assert behaviour: results are compared with expected programs
  and row sets, not only "does not throw".
- Ten consecutive host runs of the final suites: no failure.

### Corrected (mistakes of mine, not findings)

Three expectations of mine were wrong and are corrected; none was the product's fault.

1. The first "unchanged writes nothing" test traced SQL statements and failed on the active program: the
   zero-row `UPDATE` above. A statement that matches no row is not a write, and `save` runs the same one, so
   the test now uses SQLite's count of changed rows (`totalChangesCount`) and the row-for-row dump.
2. On the simulator (first run) the race around the commit failed its own self-check, "some cancelled call was
   stored": it cancelled after at most 400 yields, and there no update commits that soon, so all 80 calls ended
   with none. All 80 verdicts held. The canceller's wait now adapts (see the table), so the test reaches the
   commit on any machine.
3. The self-check of the lanes asked the three-step update to lose on 8 of 8 seeds; one host run in about ten
   gave 7. A loss needs two callers to overlap, which no seed promises. It now asks for half.

### Not attacked

- **A change that calls the store synchronously** (for example `queue.read` inside the change). GRDB traps on
  re-entrant access, which would kill the test process; the type already keeps a change from awaiting anything.
  Left out, as the task allows.
- **Two processes** on one file, and a crash (kill) in the middle of an update. Two connections in one process
  are covered; a relaunch after a clean close is covered.
- **The unimplemented stub and the four doubles by a test of my own** (the stub is internal to
  `LedgerDependencies`, which this test target does not link). Read only.
- **A program whose rows are damaged** when `update` reads it.
- **Row timestamps in memory**: the in-memory stores expose none, so "nothing written" is judged there by both
  programs, the active one and the watchers.
- Not S3's, noted in passing: `save`, `update`, `setActive` and `delete` all take their timestamp before they
  wait for the writer, so a write that waited can stamp a row earlier than the write that ran before it. It is
  the behaviour on `main`; whether M4's sync minds is that brief's question.

### Commands and exit statuses

| Command | Exit |
|---|---|
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'ProgramUpdate.*Adversarial'` (ten times, final tests) | 0 each: 32 tests in 8 suites, 282 cases (the filter also runs F10 S3's 7 tests in LedgerSyncTests, which pass) |
| `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'LedgerPersistenceTests'` | 0: 549 tests in 125 suites, 1 known issue (not mine) |
| `scripts/check.sh --lint-only` | 0 |
| iOS simulator, PR plan, `-only-testing:LedgerPersistenceTests` (through the lock) | Run 1: 65. 548 counted, 536 passed, 10 skipped, 1 expected failure, **1 failed**: my own race around the commit, its self-check ("Corrected" 2). Run 2, after that correction and with the history test: **0**. 537 passed, 0 failed, 10 skipped, 1 expected failure. Both result bundles read and deleted |
