# F11 Program builder — review

## Slice S3 — review (G3 reviewer, 2026-10-06)

Reviewed: `git diff 312728c..57d12ab` (one commit, 26 files, +2141 −12; 38 product lines). Paths are under
`LedgerKit/` unless they start with `tasks/` or `docs/`. The tester's untracked files were not read.

### Verdict

**Approved: 0 Blocking, 2 Should fix, 9 Nit.**

The requirement is atomic on both stores by construction, the checks and row rules are `save`'s own, the
cancellation rule S13 relies on ("all or none, `CancellationError` only for none") is established by sound
tests, and no existing test was weakened. The two Should-fix items are a line each and neither changes the
protocol.

### Should fix

**S1. The fake stores a change the database rolls back, when the task is cancelled inside `change`.**
`Sources/LedgerFakes/InMemoryProgramRepository.swift:67-78`. The one cancellation check is before the lock
(`:67`). A task cancelled while `change` runs stores the change and returns; `GRDBProgramRepository.update`
throws `CancellationError` and stores nothing at that same point
(`ProgramUpdateCancellationTests.cancelledInsideItsChange_storesNothing`). Both keep "all or none", but they
are not the same behaviour, which is what ADR-008 decision 5 asks for, and the contract clause has to accept
either answer to pass on both (`Sources/LedgerTestSupport/Persistence/ProgramRepositoryContract+UpdateEffects.swift:103-126`,
the `.success` arm at `:115`). Why it matters: S13's store tests run on the fake, so the path "cancelled
mid-write, nothing stored, keep the waiting edits and send them again" can only be reached there through the
held probe, never from inside the write.
*Fix:* add `try Task.checkCancellation()` after `let changed = try change(stored.program)` (`:72`) and before
`Self.store`. It is synchronous, so it is legal under the lock, and `ObservedState.write` already leaves the
state as it was on a throw. Then make `updateCancelledInside` strict: `CancellationError`, and `active()` is
the program as saved. Update the doc comment at `:63-65`. (The database's "cancelled once committed" case has
no counterpart in the fake, which has no commit; that is fine and should be said in the comment.)

**S2. `save`'s own documentation does not say what this slice found.**
`Sources/LedgerDomain/Protocols/Repositories.swift:25-32`. The hazard is described only on `update`
(`:36-40`). The next caller who wants to edit a stored program reads `save`, which still reads as the way to
do it; the loss is silent and both stores reproduce it
(`wholeSave_afterAWorkoutsSave_losesItsMissAndItsSwap`). *Fix:* one sentence on `save`: "For a new program,
or to replace one whole (an import, a repair). To edit a program that is already stored use `update`: a
copy read earlier and saved here writes back the misses and exercises a workout's save stored since."

### Nit

- **N1. `update` can change which program is active when two are flagged active.**
  `Sources/LedgerPersistence/Repositories/GRDBProgramRepository.swift:81`, `:140-145`. `write` runs `activate`
  whenever the result is active, also when the stored program already was. `fetchActive` (`:127-136`) allows
  for two active programs after a sync; renaming the one that is not the winner then clears the other's
  flag, against the protocol's "a change that leaves it alone leaves which program is active alone"
  (`Repositories.swift:38-39`). No code path produces that state today (F17 would), and `save` does the same,
  so it is not this slice's defect. *Fix, here or with F17:* in `update`, activate only when
  `changed.isActive && !stored.isActive`; an unchanged flag then runs no activation statement at all.
- **N2. The clock is read before the wait for the writer.** `GRDBProgramRepository.swift:72`. A row written by
  an update that queued behind a workout's save gets an `updated_at` earlier than the row it replaces. This
  is the convention of every write in the module (`save` `:45`, `GRDBWorkoutRepository.swift:74`, `:119`,
  `:149`), so it should not be changed in one method; flag it for F17, where `updated_at` starts to order
  things. Note that `cancelledWhileItWaitsForTheWriter_storesNothing` uses the early read as its signal.
- **N3. The unreachable `?? changed`.** `GRDBProgramRepository.swift:82`, `InMemoryProgramRepository.swift:77`.
  If it ever ran, the caller would be handed the change's result (weeks unsorted, not read from the store) as
  "the program as stored". *Fix:* throw `missingRow` there, which is true of the state it would describe.
- **N4. "on a thread of the store's own"** (`Repositories.swift:52`) is true of the database only; the fake
  runs `change` on the caller's thread under its lock. *Fix:* "inside the store's write, while every other
  call on that store waits".
- **N5. What the compiler already refuses is not said.** `Repositories.swift:52-56`. `change` is synchronous,
  so it cannot `await`, and every repository call but `observeActive()` is `async`: the doc's "must not call
  this repository" is enforced for all of them. The one call that compiles is `observeActive()`, which on the
  fake takes the non-re-entrant lock (`ObservedState.swift:67`) and hangs or traps. Worth one clause, since
  it is the only real way to break the rule.
- **N6. Three reads of five tables per update**, on the writer: the read (`:74`), `ProgramRows.write`'s own
  read of the stored rows (`Records/ProgramRows.swift:56-60`), the read back (`:82`). Fine at these sizes.
  If S13's "a write per keystroke" (Risks 7) ever shows on a profile, return `stored` when
  `changed == stored` and skip the rest.
- **N7. `concurrentUpdatesAndSaves_loseNothing` holds the fixture's shape as numbers.**
  `Tests/LedgerPersistenceTests/ProgramUpdateInterleavingTests.swift:160-169`: `4 ..< 204`, `204`,
  `number / 5`, `number % 5`. *Fix:* derive them from `program.daysPerWeek` and the slots' places.
- **N8. Helpers written twice.** `renamed` (`ProgramRepositoryContract+Update.swift:95`,
  `ProgramUpdateTests.swift:47`); `ChangeFailure` and `ChangeRefused`; `brief` and `line`; `moved(_:to:)`
  and the inline program in `ProgramUpdateInterleavingTests+Edits.swift:110-117`; `Tally` and `StatementLog`
  used as a counter.
- **N9. `HistoryModel.update`** (`Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:92-101`,
  a tester's file) has no id check and does not clear other programs' flag as its `save` does. Nothing calls
  it and no contract runs on it, so the mechanical edit is acceptable; whoever first routes an update through
  the oracle must finish it.

### Verdict on each point asked

**Atomicity on GRDB: holds, by construction.** `update` (`GRDBProgramRepository.swift:71-84`) is one
`queue.write`: GRDB's `inTransaction` around the closure, on the one `DatabaseQueue` every repository shares,
so the read (`:74`), `change` (`:77`), the write (`:81`) and the read back (`:82`) are in one `BEGIN IMMEDIATE …
COMMIT` and any throw rolls back. `save` and `update` write through one function (`:140-145`), which is
`ProgramRows.write` plus the activation, so the checks, their order, the errors and the row rules are
identical; `update` adds only the id check, before them. Nothing is observable between: observers are told
after the commit, and a `ValueObservation` fetch queues behind the write. `save` still validates before it
asks for the writer (`:44`); `update` validates inside (`:81`), which it must.
*The closure:* the doc comments (`Repositories.swift:52-56`, `GRDBProgramRepository.swift:62-64`) are right.
They are sufficient with N4 and N5. A deadlock is not refused at run time, only documented, but the
signature refuses nearly all of it: a synchronous closure cannot call an `async` repository method. What
remains is `observeActive()` and deliberate blocking (a semaphore, a synchronous GRDB access, which traps).
No run-time guard is worth adding.

**Atomicity in memory: by construction, not only by overlap.** The implementer's note undersells it.
`update` is one `state.write` (`InMemoryProgramRepository.swift:68-78`); `ObservedState.write`
(`Support/ObservedState.swift:41-61`) is `Mutex.withLock` around a synchronous body; `change` is a
synchronous function, so no suspension point can exist between the read (`:69`), the change (`:72`) and the
store (`:76`); and a workout's save writes through the same `state.write` (`writeSave`, `:105-116`). What is
"shown by overlap" is only that a *test* would notice if someone later moved `change` outside the lock;
the code as written cannot interleave. No finding. The implementer's open question 5: accept.

**Criteria 2 to 6 and 11, by the code paths.**
- 2: `missingRow` before `change` on both (`GRDB :74-76`, where `ProgramRows.program` reads live rows only;
  fake `:69-71`). Holds.
- 3: `try change(...)` rethrows untouched; rollback on the database, `ObservedState.write` discards its copy
  of the state on the fake. Holds.
- 4: the same function refuses on each store; the order of faults matches (id, re-validation, other programs'
  ids, exercises, then rows). Holds, and the clause compares `save`'s error text with `update`'s.
- 5: no special case; the row diff writes nothing and `activate` touches only rows whose flag changes; the
  fake yields only a changed value. Holds.
- 6: rows as `save`. "Which program is active does not change" holds for every change that leaves the flag
  alone, except in the two-active state of N1.
- 11: no migration, schema, fixture, `Package.swift` or script changed; both clause lists only gain entries at
  their end.

**The deviations.**
- *`duplicateIdentifier("program <id>")` for a result under another id:* acceptable. No other code throws
  `duplicateIdentifier` with the table `program` (the others name `program_week`, `day_template`, `slot`,
  `workout_exercise`, `logged_set`), so a store could tell it apart by the prefix, but it should not have to:
  the builder cannot produce it (`Program.id` is a `let`), so a store should treat it as any unexpected
  error. Keep; no new case.
- *`isActive` saved as `save` saves it:* acceptable, and better than the alternatives. Ignoring a changed
  flag is silent; refusing needs an error nobody can act on. The change receives the stored flag, so only a
  closure that sets it on purpose changes it. Criterion 6's wording should be amended to say so (below).
- *The fake checks cancellation first:* right, and it should go one line further (S1).

**Cancellation (criterion 8): the six tests are sound.** Each cancels at an exact point with no clock:
before the call (the task cancels itself); while waiting (cancel, then free the held writer: GRDB's check at
`SerializedDatabase.swift:264` runs only after the writer is free, so the order is fixed); inside `change`;
at every statement from `BEGIN` to the last before `COMMIT` (fifteen-odd fresh databases, each must end
`.nothing`, and the control run must have written five or more rows); at `COMMIT`; after the commit (a
transaction observer). `Outcome` compares every row of the five tables with its stamp, so "nothing" means
nothing, and a `CancellationError` with rows written, or a return without the edit, is `.broken`. I read the
GRDB source they cite and it says what the notes say. The commit-time test depends on SQLite, is labelled so,
and its failure would not break the rule. The fake is the same before the call and while held, and differs
inside `change` (S1).

**The losing sequence: fair, and clear.** `Opened` is the real order (read; a workout's save with a miss and a
swap; write the copy with an unrelated edit), on both stores. The test asserts the loss, is titled "Why update
exists", and its twin sends the same edit through `update`. A reader will not take it for a bug to fix. S2
puts the same warning where a caller of `save` looks.

**Other conformers.**
- Stub (`Sources/LedgerDependencies/Unimplemented/UnimplementedStores.swift:46-48`): reports as its
  neighbours; in the stub test's list.
- Probe (`Sources/LedgerTestSupport/Engine/ProbedStores.swift:137-139`, `StoreProbe.swift:15`): yes, S13 can
  `hold(.updateProgram)`, `waitUntilHeld()`, `release()` and count `calls`. It holds before the store, passes
  `change` on untouched, and `leave` does not check the task, so a stored change is never reported as
  cancelled by the probe. Nothing iterates `Call.allCases`.
- The four doubles, each the new method only, no other line touched:
  `Tests/LedgerPersistenceTests/Adversarial/HistoryModel+Repositories.swift:92-101` (+11, tester's; N9);
  `Tests/LedgerSyncTests/Adversarial/HostSiegeStoresAdversarialSupport.swift:134-136` (+4, tester's; forwards);
  `Tests/LedgerDomainTests/Adversarial/ProtocolsAdversarialTests.swift:34-36` (+4, tester's; `missingRow`);
  `Tests/LedgerSyncTests/LocalWorkoutSessionActorMissTests.swift:150-152` (+4; throws `Unused()`).
  Three are testers' files, not two.

**Protocol design: right.** A synchronous, non-escaping, throwing `@Sendable` closure is the shape that makes
the misuse hard: it cannot await, cannot be kept, and must capture Sendable values, which keeps a
`@MainActor` store out of it. Returning the program as stored is needed (the weeks are sorted on the way in,
and a workout's writes come back with it), and `update(id) { $0 }` is incidentally a read of any program by
id that writes nothing. `save` should be documented (S2). The seven doubles on the F08 branches: the notes'
table is right; add one line to it after S1 (below).

**Tests.** They assert behaviour, with one deliberate look at statements
(`update_isOneTransaction…`), which is the criterion itself. All eight clauses, the storage clause and the
two linked clauses run on both stores (I ran them: 18, 3 and 9 cases a store). Seeds are the test's argument
and are in the failure text. No sleep, no clock, no polling; every suite has a time limit. **No large value
is compared directly inside `#expect`**: programs and row lists are compared outside and the Bool or a
one-line difference is expected (`ProgramUpdateTests.swift:84-85`, `:111-112`, `:160-161`, `:209-210`;
`ProgramUpdateInterleavingTests.swift:168-172`); what is compared inline is a small enum, a name, or a few
short strings. Names follow §6 loosely, as their neighbours do; the two suites not named for a source type
follow `LinkedSaveDifferentialTests`. Edits to existing test files: `UnimplementedStubTests.swift:50` gains
one call in the list (stronger); the four doubles above; in test support, `clauses` and `linkedClauses` gain
`+ updateClauses` / `+ linkedUpdateClauses`, `storageClauses` one entry, and a doc comment. Nothing removed
or loosened.

**Boundaries, size, lint, docs.** Domain: the requirement and comments. Persistence: `update` and the shared
`write`. Fakes: `update`. Dependencies: the stub. TestSupport: clauses, the probe's call, `TaskCancelSwitch`
(imports `Synchronization` only). No new import crosses a module rule; no migration or schema change; 38
product lines against 45 planned; no `swiftlint:disable`, `@unchecked Sendable` or `nonisolated(unsafe)`
added. `docs/architecture.md` §7 names the repository protocols, not their calls (`:341-347`), so it needs no
sentence.

### Ruling recommendations

| Item | Recommendation |
|---|---|
| Deviation 1, open question 1 (`duplicateIdentifier` for another id) | Keep. |
| Deviation 2, open question 2 (`isActive` as `save` saves it) | Keep. Amend criterion 6 to: "an update whose change leaves `isActive` alone does not change which program is active; a changed flag is saved as `save` saves it." Take N1's condition now or record it for F17. |
| Deviation 3 (the fake checks its task first) | Keep, and add the second check (S1). |
| Deviation 4 (returns the program read back) | Keep; replace `?? changed` (N3) at leisure. |
| Deviations 5, 6, 8, 9, 10 | Accept as built. |
| Deviation 7 (an unreadable program cannot be updated) | Accept. S13 must show the error and must not "repair" by saving its own copy, which is the losing sequence. |
| Open question 3 (the fake's other writes do not check their task) | Leave, as recommended. |
| Open question 4 (the commit row is SQLite's) | Keep strict; watchOS is the gate's to confirm. |
| Open question 5 (atomic by overlap) | Accept; it is by construction in the code (above). |
| Open question 6 (older clauses print whole programs) | Follow-up, as recommended. |
| Open question 7 (three testers' files) | Noted; all four audited above. |

### The seven points

1. Module boundaries: clean; no new cross-module import.
2. Concurrency: sound; one transaction, one lock, a synchronous `@Sendable` closure, the clock injected; S1 is the one gap, in the fake.
3. Error handling: nothing swallowed; errors are `save`'s; `CancellationError` only when nothing was stored.
4. Design fidelity: not applicable (no UI).
5. Accessibility: not applicable.
6. Test quality: behaviour, both stores, seeded and reported, no timing; N7 and N8 only.
7. Brief compliance: criteria 1 to 11 each have a test or a build; criterion 6's wording needs the amendment above.

### What S13, S14 and the waiting branches must be told

- The notes' "Inputs for S13 and S14" stand. Add: after S1, a task cancelled inside the write throws and
  stores nothing on the fake as on the database, so a store test can reach "keep the waiting edits" with
  `TaskCancelSwitch` and not only with the held probe.
- Never `save` a program the store read earlier, including to recover from an error `update` threw
  (deviation 7).
- The closure must not call `observeActive()` (N5), and must not set `isActive`; use `setActive`.
- An update that changes nothing emits nothing: never await an emission after one.
- F08 branches: the notes' table is right. A double that keeps a program should also check the task and the
  result's id if any test will route an update through it; one that only records may throw.
- F17: N1 (two active programs) and N2 (`updated_at` taken before the wait).

### What I did not check

- The full gate, the simulator, watchOS, CI and the nightly lane (every seed) were not run. I ran on the host
  `--filter 'ProgramUpdate|ProbedProgramRepositoryTests|InMemoryContractTests|ProgramRepositoryTests'`: 49
  tests in 8 suites passed (the tester's in-progress files did not break the build at that moment).
- The `/code-review` pass (effort high) ran as a separate agent that read the commit without building; its
  nine candidates are folded in above (S1, N1, N2, N3, N6, N7, N8, N9, and deviation 7). I did not reproduce
  N1 with a test; it follows from reading `:81` and `:148-155`.
- The implementer's break-and-restore table and the "8 of 8" overlap rates were not repeated.
- That `fixedSeeds` are the first thirty of `PropertySeed.all` was not verified.
- The seven doubles on the F08 branches were not read.
- The tester's files under `Tests/LedgerPersistenceTests/Adversarial/` were not read, as instructed.
