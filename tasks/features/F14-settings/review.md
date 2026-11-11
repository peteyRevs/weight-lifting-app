# F14 — review

## S1a — G3 review (round 1, 2026-10-28)

I reviewed `bd2d26c..61e1217`: S1a as built (`a374175`, `0d0508d`), G2's adversarial round (`fdb28bf`) and fix round 1
(`bcdeacb`, `61e1217`). I checked it against the brief's "Plan amendments" (S1 and the S1a/S1b split, N1 as ruled) and
"Rulings before G1". I did not re-open the rulings: Q1–Q7, A1–A4, the seed on the launch that creates this device's
row only, `UITestRegion`, and the split. S1b's draft patch was not reviewed. This review is read-only. I probed and
mutated a `git archive` copy in my scratchpad, which I have since deleted. No product or test file in the worktree
changed.

**Verdict: changes required (small).**
- **R1-1:** the save queue's one real gap. It is latent in S1a, because no other writer exists yet. As a minimum, the
  "harmless" claim must be corrected and the gap pinned. Whether to fix it now or before S3 is the orchestrator's call.
- **R1-2:** two branches of the FIFO that no test pins. A ready test exists for one of them.
- **R1-4:** a merge hazard with F13. It needs a decision on which lane adds a one-line method.
- **R1-3:** the orchestrator's call.
- The rest are nits.

**What holds:**
- **N1 / R7, the main promises.** I traced every interleaving I could construct:
  - Saves run one at a time, across runs. `isSaving` is set and cleared on the main actor, and the defer clears it
    before handing off.
  - Each save is the whole value, and the last change wins.
  - A change shows before `send` returns.
  - A late echo of an earlier save never draws over a newer value, because `committed = unechoed.last ?? stored` and
    `firstIndex` keeps the tail.
  - A failure partway through the FIFO reverts to `committed`, which is the newest value known to be in the row, and
    drops the queue, as ruled.
  - Echoes cannot arrive out of order: GRDB delivers in commit order, and a `DatabaseQueue` observation fetches after
    each commit. Coalescing does happen: `stream(in:)` buffers `bufferingNewest(1)` on the `.task` scheduler. A
    coalesced echo is handled whenever the delivered value's first match is the right entry. R1-1 covers the case
    where it isn't.
  - A change made elsewhere that matches no entry empties the list and is committed.
- **Task restart.** Each run has a number, and only the current run clears the marks. A cancelled run starts no
  further save and hands any queued change to the current run's saver. I wrote a test for this hand-off (R1-2): it
  passes on HEAD.
- **Swift 6 isolation.** The store is `@MainActor`. `run()` and its extension are main-actor isolated. The follower
  is a child task that awaits a main-actor method. The models, input and actions are `nonisolated` and `Sendable`.
  Nothing starts a task of its own, and the source test enforces this.
- **N2.** An ended observation draws what it last had, or `.default`, and logs once. Nothing is saved until a
  change. After that save, the follower subscribes again.
- **Seeding.**
  - `LocalDevice.open` returns `isNew` from the same write that inserts the row, and `id(…)` delegates to it.
  - `seedIfAbsent` is `INSERT … ON CONFLICT (id) DO NOTHING`, so a stored row keeps its payload, version and
    `updated_at`, even when it is unreadable. The in-memory fake tells "no row" from a stored `.default`.
  - The watch's `DatabaseLaunch` passes nil.
  - A failed seed is logged, the load goes on, and no later launch seeds again.
  - `isNewInstall` is one stored property with a defaulted init parameter, read once (see R1-3 for a way to drop it).
- **Correctness elsewhere.**
  - `Settings.regional` uses `Weekday.first(of:)`, the existing helper.
  - The weekdays are listed from the calendar's first day and named with `standaloneWeekdaySymbols` in the injected
    locale.
  - The rest steps stay within 30–300 s through the failable `RestDuration(seconds:)`.
  - The About line trims its parts (F14-S1-7).
  - `SettingsRoute` has no case in Release.
  - I found no dead code and no duplicated helper.
- **Localisation.**
  - The catalog has 26 keys, each with a comment.
  - There are no plurals, so no `%lld` forms to check.
  - I found no hard-coded user-facing literal in the module.
  - "Ledger" appears only in doc comments, never in a key or value.
- **Line count.** Non-blank, non-comment product Swift, plus `Package.swift`, against `bd2d26c` is **+668 / −17 =
  net 651**, which matches the notes. No line in FeatureSettings is over 120 columns, and the code reads at normal
  density. Nothing was compressed to fit.
- **The tests** prove the criteria (see the mutation table). No assertion waits on wall-clock time: `eventually`
  watches Observation, and the scripted waits count yields. Every suite has a time limit.

**F14-S1a-R1-1 (Minor; latent until a second writer exists). After a coalesced echo, entries can stay stale in
`unechoed`. A later change made elsewhere that equals a stale entry then leaves the screen, and the next save, on a
value that is not in the row.**
- **Where:** `SettingsStore+Sources.swift:63-72` (`receive`), and the claim in `implementation-notes.md:204-210`
  that a left-over entry "is harmless … a change made elsewhere empties the list".
- **The gap:** a change made elsewhere empties the list only if it matches **no** entry. If it matches a stale one,
  `firstIndex` treats it as an echo and drops only the entries up to that one. `committed` then becomes a later stale
  entry.
- **Probe** (scratch; `ScriptedSettings` given two helpers, one that delivers only the newest held echo, as
  `bufferingNewest(1)` does, and one for a write made elsewhere):
  1. Tap KG, then Plate math off, then Plate math on. Each save commits with its echo held, so
     `unechoed == [A, B, A]`.
  2. Deliver only the newest echo (A). `firstIndex` matches index 0, so `unechoed == [B, A]` (stale).
  3. Another writer puts B (Plate math off) in the row. `firstIndex(B) == 0`, so `unechoed == [A]`.
     **The screen shows Plate math on, while the row has it off.** The next change saves A plus that change, over the
     other writer's value.
- **`lastIndex` is not the fix.** In the scratch copy it closes this probe but reopens F14-S1-3's flash. With the
  echoes A, B, A delivered in order, the first A empties the list, then B is drawn. Every existing suite passed
  under `lastIndex`, so which index is right is not pinned either (R1-2).
- **Why it is latent.** Only `SettingsStore` writes settings in S1a (I searched every `save(` in `Sources`). The
  launch's seed runs before any store exists. The first other writers are S3's erase and F19's sync.
- **Fix, either:**
  - **(a) Exact, and about as small as the FIFO.** When the saver goes idle, restart the follower's observation. Its
    first value is the row after every commit of this store, so `receive` takes it as `stored` and empties
    `unechoed`. The old observation's late echoes die with its stream. This reuses `followMark`, but the follower
    must cancel its current observation on a new mark (one child task per mark). It costs one fetch per burst of
    saves.
  - **(b) Keep the FIFO for S1a**, but:
    - correct the notes' "harmless" paragraph and the store's doc;
    - add the probe above as a `withKnownIssue` test;
    - queue (a), or a row revision from the repository, as a prerequisite of S3's erase.

**F14-S1a-R1-2 (Minor, tests). Two branches of the FIFO survive mutation.**
- **M3:** remove `else { unechoed = [] }` from `receive` (`SettingsStore+Sources.swift:66-68`). Every suite passes,
  `FeatureSettingsTests` and the AppKit reach suites included. No test sends a change made elsewhere while the list
  is not empty.
  - **Fix:** a test that commits a save with its echo held, then writes a different value elsewhere, and expects
    `shown == row` and `unechoed` empty.
- **M5:** remove the defer's `saveMark?.yield()` (`:86-89`). Every suite passes. `restartDuringASave_keepsSaving`
  sends its only queued change after the old run has ended, so the hand-off from a cancelled run is never exercised.
  - **Fix:** add this test (it passes on HEAD and kills M5 with 3 issues). Start a run, tap KG and hold the save, tap
    Friday, cancel the run, start a second run, then commit KG. Expect the next held save to be Friday, and the row
    to end on Friday with nothing pending. I wrote it as `restart_handsTheQueuedChangeToTheNewRun` over
    `ScriptedSettingsScene`, about 18 lines.
- With R1-1 settled, add a test that pins the chosen index rule. If the FIFO stays, use the in-order A, B, A echo
  script from R1-1: it fails under `lastIndex`.
- **M1** (`!Task.isCancelled` removed from the save loop's condition) also survives. That is acceptable: a cancelled
  task's next GRDB write throws `CancellationError`, which takes the same `return` with `pending` kept. No test is
  needed.

**F14-S1a-R1-3 (Minor; the orchestrator's call). If a first launch dies before `loadSettings`, the region is never
seeded.**
- **Where:**
  - `DatabaseLaunch.swift:94`: `LedgerStores.open` inserts the device row synchronously, at open.
  - `:125`: the catalog seed runs first.
  - `:187`: then `isNewInstall` gates the regional seed.
- **The gap:** if the process ends in that window, say the lifter swipes the app away during the first launch's
  catalog seed, the next launch finds a device row. It is "not new", and the install keeps `Settings.default` (lb,
  Monday) for good. The ruling covers a seed that **fails**. This case is a seed that was never tried.
- **Fix:** seed in the same write that inserts the device row. For example, `LedgerStores.open(…, regionalSettings:)`
  calls a `Database`-level `LocalDevice.open` and, when the row is new, runs the same `INSERT … ON CONFLICT DO
  NOTHING` in that transaction. The criterion stays the one that was ruled ("the launch that creates this device's
  row"), and it becomes atomic. As a bonus, `LedgerStores.isNewInstall` and the condition in `DatabaseLaunch` go away.
- The consequence is mild (the lifter can change both in Settings), so a follow-up is acceptable.

**F14-S1a-R1-4 (Major for merge coordination; not a defect in S1a). Merging with F13 (`feat/F13-workout-history`,
`2154cfb`) conflicts twice and then fails to compile.**
- `git merge-tree --write-tree HEAD feat/F13-workout-history`:
  - **CONFLICT** in `LedgerKit/Package.swift`: the `FeatureHistory` and `FeatureSettings` targets are adjacent, and
    both lanes expand theirs.
  - **CONFLICT** in `scripts/coverage-thresholds.json`: `required` is a single-line array, and both lanes add a name.
  - Both conflicts are trivial: keep both edits.
- **Semantic break:** F13 adds `EndedSettings: SettingsRepository` (`FeatureHistoryTests/HistoryStoreTests.swift:164`)
  without `seedIfAbsent`. Once both lanes are on `main`, that test target no longer compiles.
- The other shared files (`Repositories.swift`, `UnimplementedStores.swift`, three test doubles and
  `UnimplementedStubTests.swift`) auto-merge, and their edits are line-local.
- **Fix:**
  - F13 adds `func seedIfAbsent(_: Settings) async throws { throw Unused() }` to `EndedSettings` now. A method the
    protocol doesn't require yet is legal, so F13 stays green on its own.
  - Whoever merges second resolves the two conflicts by keeping both sides.
  - Consider writing `required` one name per line in a chore, so later lanes merge line by line.

**F14-S1a-R1-5 (Nit, tests). Large values are compared inside `#expect`.** The F11 and F12 reviews hold the line
that a large value is compared outside `#expect` and the Bool expected. These compare a whole `Settings`,
`SettingsModel` or `Program` inline:
- `SettingsStoreTests.swift:47, 85, 115`
- `SettingsStoreTests+Unreadable.swift:17`
- `SettingsReachTests.swift:101`
- `DatabaseLaunchTests+Regional.swift:18, 26, 35, 50, 66`
- `SettingsRepositoryTests.swift:47, 71`
- `AppCompositionTests` (two new tests)

G2's suites already bind to a `let …Is… = a == b` first. **Fix:** the same here.

**F14-S1a-R1-6 (Nit, localisation and simplicity).**
- `SettingsCopy.version(_:locale:)` and `build(_:locale:)` (`SettingsCopy+Names.swift:34-51`), and
  `SettingsPresentation.about(_:locale:)`, thread a `locale` that changes nothing. `String(localized:locale:)` uses
  the locale only to format interpolated values, and these interpolate `String`s. **Fix:** drop the parameter, or
  say why it is kept.
- `about`'s `"{name} {version}"` is joined in code (`SettingsPresentation.swift:131`), not in a catalog key, unlike
  "Version %@". It is harmless while only English ships. A key such as `"%1$@ %2$@"`, with a comment, would give a
  translator the order.

**F14-S1a-R1-7 (Nit, test speed). `restartDuringASave_keepsSaving` spins 200,000 yields in its passing case.**
- **Where:** `SettingsSaveQueueAdversarialTests.swift:160` waits for a second save that must **not** come, so it
  always runs to the bound. It took 2.8–3.2 s per run, the slowest test in FeatureSettings.
- **Fix:** 1,000 yields, as `changeDuringAFailingSave_isDroppedWithIt` uses. That is enough for the second run's
  start to reach `savePending`.

**Simpler design?** The FIFO is the smallest **value-based** design that keeps F14-S1-3's promise. Values alone
cannot tell an echo from an equal change made elsewhere, which is R1-1. The resubscribe-after-drain variant (R1-1 (a))
is exact, and it is no larger. Either way, `isSaving`, `runNumber` and the hand-off are needed, and they are as small
as they can be.

**Sanctioned edits of others' tests: each is justified and minimal.**
- The nine `SettingsRepository` doubles each gain one `seedIfAbsent`. Each one forwards, throws or does nothing,
  matching its double's existing style.
- `UnimplementedStubTests` gains one closure.
- In `DatabaseLaunchTests.Subject`, `init` gains two defaulted parameters. Every existing call is unchanged.
- `FeatureSettingsTests.swift` is removed with the placeholder.
- `AppCompositionTests` gains two tests.
- No unrelated assertion was weakened.

**Mutations, each in the scratch copy** (`FeatureSettingsTests`, plus the targets named):

| # | Mutation | Result |
|---|---|---|
| M1 | `!Task.isCancelled` removed from the save loop (`+Sources:91`) | Survives; equivalent in practice (R1-2) |
| M2 | `guard !isSaving` removed (`:80-82`) | **Killed**: `restartDuringASave_keepsSaving` (`mostAtOnce`) |
| M3 | `else { unechoed = [] }` removed (`:66-68`) | **Survives**, also against the AppKit reach suites (R1-2) |
| M4 | `if runNumber == number` → `if true` (`:34`) | **Killed**: `restartDuringASave_keepsSaving`, 2 issues |
| M5 | The defer's `saveMark?.yield()` removed (`:86-89`) | **Survives**; killed by the proposed hand-off test (R1-2) |
| M6 | `committed = unechoed.last ?? stored` → `stored` (`SettingsStore.swift:83`) | **Killed**: criteria 1/2/7/8 (6 cases), criterion 1, F14-S1-2, F14-S1-3 |
| M7 | `removeFirst(echoed + 1)` → `remove(at: echoed)` (`+Sources:65`) | **Killed**: the property oracle, seeds 0, 4, 12, 39 |
| M8 | `if let regionalSettings, stores.isNewInstall` → without `isNewInstall` (`DatabaseLaunch.swift:187`) | **Killed**: `deviceRowWithoutSettings_isNotSeeded`, `installBeforeF14_keepsItsSettings` |
| M9 | `firstIndex` → `lastIndex` (`+Sources:64`) | Survives every suite; R1-1's in-order script kills it |

**Runs (host, scratch copy of `61e1217`; `diff -r Sources` against the worktree was empty before the mutations).**
- `df -h /`: 17 GiB free.
- `swift build --build-tests`: exit 0, 98 s.
- `swift test --skip-build --filter "FeatureSettingsTests|Settings|DatabaseLaunch|AppComposition|UnimplementedStub|LocalDevice"`:
  green, in eight test runs (38 tests / 7 suites in FeatureSettings; 50 / 9; 17 / 6; 16 / 6; 9 / 1; 3 / 2; 2 / 2;
  1 / 1), with no known issues left.
- `grdb_burstsConverge` (6 seeds × 60 changes over GRDB): 10 of 10 runs passed.
- Probes (R1-1): the stale-entry script **fails** on HEAD (the screen shows Plate math on, the row has it off). The
  in-order A, B, A script passes on HEAD and fails under `lastIndex`. The hand-off test passes on HEAD and fails
  under M5.
- `git merge-tree --write-tree HEAD feat/F13-workout-history`: two conflicts (R1-4).
- No simulator run. The orchestrator runs the gate.

## Round 2

**S1a — G3 review (round 2, 2026-10-28), of `git diff 2df12aa..5762717` (code `c8a52ac`, notes `5762717`).**

**Verdict: APPROVED WITH MINORS.** R1-1, R1-2, R1-3, R1-5, R1-6 and R1-7 are fixed. Two Minors (R2-1, R2-2) and a
Nit (R2-3) remain. None of them breaks a promise the lifter can reach today. R2-1 should be fixed or ruled before
merge. R2-2 is a test gap with the test written below, and R2-3 is a one-condition simplification. R1-4 (the F13
merge) is outside this diff and still the orchestrator's call.

**What holds (verified, not taken from the notes):**
- **R1-1, the restart design.** I traced every interleaving I could build:
  - Restart and retire both run on the main actor: `observationNumber` is bumped by the follower, and each value is
    checked against it before `receive`. A retired observation can never write `stored` or `isUnreadable`, at its
    values or at its end. M4 kills on the in-order A, B, A test.
  - **Stale-forever check.** Every save that returns, and every failure, ends with a restart mark (M6, M8 killed).
    A fresh first value is suppressed only while a save runs or since one returned. That save's own idle then marks
    the follower again. So the chain ends in a first value that is taken, with one exception: R2-3, where `pending`
    is set and no save follows. A change made elsewhere is therefore never hidden past the next restart, outside
    R2-3.
  - **Cancelled runs.** A cancelled run's returning save yields the *current* run's `followMark` (it is read when the
    defer runs). With no run on, the next `run()` marks the follower at its start. A cancelled save that throws
    hands off to the current saver, as in round 1.
  - **Cancellation and hangs.** `AsyncStream` iteration returns nil on cancellation, and the end guard's
    `Task.isCancelled` keeps a cancelled observation from logging "could not be read". `run()`'s group drains:
    - the saver's `for await` ends
    - the follower's `for await marks` ends
    - each `observe` child ends at cancellation

    No hang was found. The leak in R2-1 lasts only while a run lives.
  - **`ScriptedSettings` against GRDB (asked).** Routing a held echo only to the observations open at its commit
    matches GRDB:
    - An observation started after a commit sees it in its initial fetch, and gets no separate notification for it.
      `DatabaseQueue` registers the observer and fetches in one access.
    - `removeDuplicates` is modelled by `lastSent`.

    It differs from GRDB in two ways:
    - (a) The double yields an observation's first value at subscription. GRDB fetches it and delivers it later
      through `.task`. This is why M1 and M11 cannot be killed (R2-2).
    - (b) `deliverNextEcho()` after `writeElsewhere(_:)` delivers an older value after a newer one. GRDB's serial
      delivery never does that. This is stricter than real life and harmless.
- **R1-2.** `restart_handsTheQueuedChangeToTheNewRun` kills round 1's M5 (the defer's `saveMark?.yield()` removed):
  `nextIsFriday` and `rowIsFriday` fail, with 4 issues. M3's branch went with the FIFO.
- **R1-3, atomic.** `LedgerStores.open` runs `LocalDevice.open(in:)` and `seedIfAbsent(_:at:in:)` in one
  `database.write`, which is one transaction. A thrown seed rolls back the device row. Two mutations, both killed:
  - **RA:** the seed moved to a second `write`. `deviceRowAndSeed_areOneWrite` fails (`deviceRows == 0` and
    `seeded`).
  - **RB:** `device.isNew` dropped. The pre-F14 tests fail, in `DatabaseLaunchTests+Regional` and in
    `SettingsSeedAdversarialTests`.

  No caller is left on the removed APIs. `git grep` finds no `isNewInstall`, no `LocalDevice.open(in: queue…)`
  (now internal, taking a `Database`), and no `LedgerStores(…, isNewInstall:)` in any target or in the app projects.
  The remaining `LedgerStores(` callers use `(queue, deviceID:, now:)`, which is unchanged.
- **R1-5.** The listed sites now bind a Bool. **R1-7:** the bound is 1,000 yields.
- **R1-6.** The `"%@ %@"` key carries a comment that gives the translator `%1$@`/`%2$@`. The reason for keeping
  `locale:` is true: `docs/engineering-standards.md` lines 219–231 and 377 require `locale:` on every lookup whose key
  carries a value, and `ModuleCopyTests` audits it. Not reopened.

---

**F14-S1a-R2-1 (Minor, resources). A retired observation stays open until the row's value next changes, and every
failing save adds one.**
- **Where:** `follow` / `observe`, `SettingsStore+Sources.swift:46-79`, and the defer at `:106-114`.
- **Cause:** A retired observation ends only "at its next value". The repository's observation has
  `.removeDuplicates()`, so a save that fails produces no value. The failure still restarts, so each failure leaves
  one more GRDB `ValueObservation` registered on the `DatabaseQueue`. Each of them refetches the row after every
  commit to `settings`, until the row changes or the run ends.
- **Failure scenario:**
  - The database refuses writes (disk full, or a read-only file after a restore).
  - The lifter taps 50 times on the open screen. Every tap fails.
  - 51 live observations are left, and the next successful commit wakes all of them at once.
- **Probe P2:** 20 failing saves of KG over `ScriptedSettings` leave `observationCount == 21`; the start is 1.
- **Normal flow stays bounded:** after a successful save, the retired observation either takes its echo after the
  bump and returns, or lingers until the next distinct value. At most one is left over.
- **Fix:**
  - Preferred: cancel the retired observation itself. Run each observation in an unstructured `Task` whose handle
    the store keeps. Cancel it on retire, and forward the group's cancellation with
    `withTaskCancellationHandler { await handle.value } onCancel: { handle.cancel() }`, so nothing outlives the
    screen.
  - Otherwise: rule the leak acceptable, correct the doc comment ("ends at its next value" is true but unbounded),
    and pin P2's count.

**F14-S1a-R2-2 (Minor, tests). Two of the new load-bearing conditions survive mutation.**

| Mutant | Result | Why |
|---|---|---|
| M1 `readsTheRowAfresh: isFirst` (drop `writes == writesBefore`) | **Survives** | the double's first value is synchronous |
| M11 `writes += 1` removed | **Survives** | same as M1 |
| M7 `hasWrittenOrFailed = true` dropped on the failure path | **Survives**; killed by P3 below | untested branch |

- **M1 / M11, failure scenario (real GRDB, `.task` delivery):**
  1. The idle saver restarts. Observation D starts, and GRDB fetches D's first value (row = A) on the queue.
  2. The lifter taps B. The save of B commits and returns, and the saver goes idle.
  3. D's pre-B first value is delivered after that, but before the follower handles the new mark.
  4. Without the `writes` check, `written` is dropped and the screen flashes A over the lifter's B (the F14-S1-3
     class). It lasts until the next observation's first value.

  `ScriptedSettings` cannot express this, because its `observe()` yields the row at subscription. **Fix:** give the
  double a way to hold an observation's first value, as GRDB does, and add a test that fails under M1.
- **M7, failure scenario:**
  1. Save A returns. The lifter taps B before the fresh observation's first value, so that value is suppressed and
     `written == A`.
  2. B's save fails. Without the restart, `written` stays A.
  3. A change made elsewhere then never reaches the screen until the next successful save.

  **Fix:** add P3, which passes on HEAD and fails under M7 with `shownIsTheRow`:
  - save KG
  - `until pending == nil`
  - `send(.setWeekStart(.friday))`
  - hold the save, then fail it
  - `writeElsewhere(kilograms with Thursday)`
  - expect `shown ==` that value

**F14-S1a-R2-3 (Nit, simplicity and a theoretical stale window). `receive`'s `pending == nil` is not needed, and it
is the one way out of the restart chain. `!isSaving` is the condition that matters.**
- **Where:** `SettingsStore+Sources.swift:88`.
- **Why `pending == nil` adds nothing:** given `!isSaving` and `writes == writesBefore`, every save of this store
  either returned before the observation started, so the fresh read includes it, or never ran. The fresh value is
  then what is committed, whatever is pending.
- **Why `!isSaving` alone is redundant today (M2, an equivalent mutant):** `pending` is non-nil for the whole of a
  save loop, and the failure path sets it to nil and returns without suspending.
- **Failure scenario that keeping it opens:**
  1. Two `send`s in one main-actor turn, a change and then its undo, land after the idle saver's restart mark and
     before the fresh first value.
  2. The first value is suppressed (`pending != nil`).
  3. The saver then finds `pending == committed`, saves nothing, and does not restart.
  4. `written` is stuck, and a change made elsewhere stays hidden until the lifter's next save.

  Human taps cannot do this: one tap per turn starts a save, whose idle restarts. My probe P1 could not reach it
  over the double either.
- **Fix:** test `readsTheRowAfresh, !isSaving` and update the doc comment. Dropping `pending == nil` (M3) keeps every
  suite green, P1 and P3 included.

---

**Mutation table, round 2** (host, scratch copy of `5762717`, `swift test --filter FeatureSettingsTests`; source
restored and `diff -r Sources` empty after):

| # | Mutation (`SettingsStore+Sources.swift`) | Result |
|---|---|---|
| M1 | `isFirst && writes == writesBefore` → `isFirst` | **Survives** (R2-2) |
| M2 | drop `!isSaving` | Survives: equivalent given `pending == nil` (R2-3) |
| M3 | drop `pending == nil` | Survives everything but P2's leak count: the condition is unneeded (R2-3) |
| M4 | drop `number == observationNumber` on values | Killed (A, B, A in order) |
| M5 | drop `number == observationNumber` at the end | Survives: only a duplicate unreadable log from a retired observation ending in the same error (harmless) |
| M6 | no follow mark when idle | Killed (4 tests) |
| M7 | failure does not set `hasWrittenOrFailed` | **Survives** the suite; killed by P3 (R2-2) |
| M8 | write does not set `hasWrittenOrFailed` | Killed |
| M9 | every value may clear `written`, not only the first | Survives: near-equivalent and benign |
| M10 | `written` never cleared | Killed |
| M11 | `writes += 1` removed | **Survives** (R2-2) |
| M12 | restart even after an idle with no save | Survives: benign, costs one refetch |
| R1-M5 | defer's hand-off `saveMark?.yield()` removed | Killed by `restart_handsTheQueuedChangeToTheNewRun` |
| RA | seed in a second `write` (`LedgerStores.swift`) | Killed by `deviceRowAndSeed_areOneWrite` |
| RB | seed without `device.isNew` | Killed (2 tests) |

**Runs:**
- `swift test --filter FeatureSettingsTests` on an unmodified copy: 42 tests / 7 suites, green.
- `--filter "DatabaseLaunch|LocalDevice|SettingsRepository|SettingsSeed|AppComposition"`: 41 / 7 and 10 / 1, green.
- Probes P1–P3 lived only in the scratch copy.
- No simulator run. The orchestrator runs the gate.

## Round 3

**S1a — G3 review (round 3, 2026-10-28), of `git diff ba60919..b71502c` (code `262bb8f`, notes `b71502c`).**

**Verdict: APPROVED WITH MINORS.** R2-1, R2-2 and R2-3 are fixed in the product code, and the fakes deadlock fix is
correct. What remains is two test-quality Minors (R3-1, R3-2) and two Nits. None of them is a product defect. They
can ride with S1b, or go in a small follow-up before merge, as the orchestrator prefers.

**What holds (verified):**
- **R2-1, closing retired observations.**
  - `follow` finishes the old observation's `retired` stream before it bumps `observationNumber`.
  - `observe(_:until:)` runs the observation and a waiter in a one-use group, and calls `cancelAll()` there once
    `next()` returns. That group's only other child is the observation or the waiter, so nothing else is cancelled.
    The follower's long-lived group is never cancelled, so round 2's "added tasks start cancelled" trap cannot occur.
  - The ways an observation ends:
    - **Retire:** the waiter ends, then the observation is cancelled, and its stream terminates, which cancels GRDB's
      observer.
    - **The observation ending by itself:** the waiter is cancelled.
    - **The run cancelled:** every level is cancelled structurally.
  - Finishing a stale `retireObservation` from a previous run is a no-op.
  - No leak or hang was found. `failingSaves_leaveOneObservationOpen` holds, and both mutations are killed:
    - R3a: `finish()` removed.
    - R3b: `cancelAll()` removed.
- **R2-3.** `receive` tests `readsTheRowAfresh, !isSaving`. The doc comment is right.
- **The fakes deadlock fix (extra).** It is correct, and other features see no change in meaning.
  - `onTermination` now only sets an `Atomic` flag.
  - `ObservedState.write` filters ended observers under the `Mutex` before yielding. An ended observer is never
    yielded to, and yielding to a terminated continuation would be a no-op anyway.
  - The only difference is that an ended observer's closure is freed at the next write, not at once. No API exposes the
    observer count.
  - Re-run on the scratch copy, all green: FeatureToday (287), FeatureProgram (475), FeatureLibrary (126),
    FeatureOnboarding (113) and LedgerAppKit (333).
  - **Production is not exposed to the same deadlock.** I read GRDB's `ValueWriteOnlyObserver`. It reads
    `onChange` under its `NSLock` and calls it outside the lock, and `cancel()` holds the lock only to clear the
    callbacks. The bridge's `onTermination` → `cancellable.cancel()` therefore cannot form the same ABBA.
- **The restart-mark hold in `firstValueReadBeforeASave_isNotTheRow` is a legitimate reproduction.**
  - Taking `followMark` and handing it back later only reorders two main-actor jobs: the follower's resume and D's
    value delivery. Under GRDB's `.task` delivery that order is reachable.
  - No code path is bypassed, and the store's own `followMark.yield()` is what restarts afterwards.
- **No hangs found.** FeatureSettingsTests (45 tests) passed in 8 of 8 back-to-back runs. Every mutant run finished.

---

**F14-S1a-R3-1 (Minor, test fidelity). With `holdsFirstValues`, a later commit's echo overtakes the held first value.
So `firstValueReadBeforeASave_isNotTheRow` does not run the scenario it describes.**
- **Where:** `ScriptedSettings.broadcast(_:to:)` sends to an observation whose first value is still in
  `waitingFirstValues`.
- **What GRDB does:** it delivers an observation's values in order on one serial scheduler: the initial fetch (A),
  then the B commit's fetch.
- **What runs in the test:**
  - D receives B's echo first. My probe: just before A is delivered, `stored == B`, `written == B`.
  - Then D receives A as a *later* value.
  - Under M1 the kill comes from that impossible order: B's echo, taken as the first value, clears `written`, and the
    late A then draws.
- **The test still pins M1 in the faithful order.** I patched the double in scratch so broadcasts to an observation
  with a held first value queue behind it. On that double:
  - On HEAD, the suite (13 tests) passes.
  - Under M1, the test still fails (`stillB`).
- **Fix:** make the double faithful. While an observation's first value is held, append broadcasts for it to a
  per-observer backlog, and send them right after the first value in `deliverNextFirstValue()`. Then check the test's
  narrative still holds (A arrives first, while `writes != writesBefore`).

**F14-S1a-R3-2 (Minor, test reliability). The M7 kill by `failureBeforeTheFreshRead_stillReadsTheRow` is
schedule-dependent now that R2-3 removed `pending == nil`.**
- **Why:** the test needs D's first value to be consumed while B's save is in flight (`isSaving`). If D runs before
  the saver starts, the value is now taken, `written` is cleared, and M7 is harmless on that schedule.
- **Measured under M7:**

  | Run | Killed |
  |---|---|
  | The test alone | 20 of 20 |
  | The whole FeatureSettingsTests | 9 of 10 |
  | My first mutation pass | survived (the 1 in 10) |

- **Fix:** run it with `holdsFirstValues: true`, and deliver D's first value only after `untilHeld()` for B. The read
  then always lands while `isSaving`, deterministically.

**F14-S1a-R3-3 (Nit, test gap). M4, dropping `number == observationNumber` from the per-value guard
(`SettingsStore+Sources.swift:83`), now survives.**
- **Why:** retire cancels the old observation quickly, so the in-order A, B, A test no longer reaches the gap.
- **The guard is still needed:** between `retireObservation?.finish()` and the child's cancellation, which lands
  later on the pool, a value already buffered or in flight would otherwise still be received.
- **Fix (optional):** a test that holds the old observation's echo, and delivers it after the restart mark and before
  the main actor turns.

**F14-S1a-R3-4 (Nit, docs). In `ObservedState.swift`, `EndedFlag` was inserted between `ObservedState`'s doc comment
and its declaration.**
- The paragraph "An in-memory store's state behind a `Mutex`…" (`:4-11`) now documents `EndedFlag`, and
  `ObservedState` has no doc comment.
- **Fix:** move `EndedFlag` (with its own two lines) above that paragraph, or below `ObservedState`.

Also noted, not a finding: M2 (drop `!isSaving`) survives, and it is now near-equivalent. During a save `pending` is
set, so the screen shows `pending`. After the save returns, `written` is set again. After a failure, the fresh
pre-save read is the row anyway. Keeping `!isSaving` is the conservative choice.

---

**Mutation table, round 3** (host, scratch copy synced to `b71502c`, `swift test --filter FeatureSettingsTests`;
`diff -r` of Sources and Tests against the worktree empty after every run):

| # | Mutation | Result |
|---|---|---|
| M1 | `isFirst && writes == writesBefore` → `isFirst` | Killed (`firstValueReadBeforeASave_isNotTheRow`, 2 issues); also killed with an order-faithful double (R3-1) |
| M11 | `writes += 1` removed | Killed (same test, and R1-1's coalesced-echo test) |
| M7 | failure leaves `hasWrittenOrFailed` false | Killed 20/20 alone, 9/10 in the suite; **survived** one full pass (R3-2) |
| M2 | drop `!isSaving` | Survives: near-equivalent (above) |
| M4 | drop `number == observationNumber` on values | **Survives** (R3-3) |
| M6 | no follow mark when idle | Killed (5 tests) |
| R3a | `retireObservation?.finish()` removed | Killed (`failingSaves_leaveOneObservationOpen`, 2 issues) |
| R3b | `group.cancelAll()` removed in `observe(_:until:)` | Killed (same test, 2 issues) |

**Runs:** FeatureSettingsTests passed 8 of 8 back-to-back (45 tests). The fakes' other consumers are listed above. The
probes and the faithful-double patch lived only in scratch. No simulator run; the orchestrator runs the gate.

## S1b round 1

**S1b — G3 review (round 1, 2026-10-29), of `git diff e10cbe0..76945c7`** (S1b as built `ae9a84a`, R3-1 to R3-4
`346fe53`, the gallery reference `3571ecd`, notes `d02995b`, G2's tests `a57d9cd`, fix round 1 `76945c7`). I checked it
against the brief's S1 criteria (1, 2, 4, 7, 8, N1–N10) and the rulings. This review is read-only: I probed and mutated
a `git archive` copy in my scratchpad, and its build products are deleted. No product or test file in the worktree
changed.

**Verdict: APPROVED WITH MINORS.** No product defect found. One Minor (a wiring test gap, Debug-only behaviour) and
three Nits. None blocks the merge; R1-1 is worth a small test before or soon after.

**What holds (verified):**
- **The views keep the store's contract.**
  - They read only `model` and `pendingRoute`, and send only `SettingsAction`s.
  - Pending versus written is invisible to them, as it should be: `model` is made from `shown`
    (`pending ?? written ?? stored`), so a control shows the lifter's value at once and an echo never flickers it.
  - Loading: the root draws `SettingsHeader` alone while `model` is nil. G2's test shows it stands exactly where the
    page's title will. An unreadable row leaves loading for `Settings.default`.
  - The problem line sits under the title only while `model.problem` is set, and the next change clears it.
- **The announce fix (F14-S1b-2)** is `ProgramRoot`'s idiom line for line: an injectable `announce`, defaulting to
  `AccessibilityNotification.Announcement`, and `.onChange(of: store.model?.problem)` announcing only a non-nil
  line.
  - A second failure is announced again, because every change that reaches the saver clears `saveFailed` first.
  - Nothing re-announces while the line stays: an echo or fresh read publishes no new `problem`.
  - `failedSave_isAnnounced` is behavioural. It kills both "never announces" (V1) and "announces the cleared line"
    (V2), so G1's unverified kill is now verified.
- **`AppAbout(bundle:)` (F14-S1b-1).** A blank value counts as absent before `??`, for every key, so a blank display
  name falls back to `CFBundleName`. The presentation trims what is kept. H1–H3 are killed.
- **`#if DEBUG`.**
  - `SettingsRoute.debugMenu`, the presentation's Diagnostics link, `resolve`'s case and the previews are all
    Debug-only.
  - In Release, `SettingsRoute` is uninhabited, `resolve` switches over no case, and `model.diagnostics` is always nil.
    G2 built `-c release` cleanly.
  - The page's `if let diagnostics` branch and `SettingsCopy.diagnostics` still compile in Release but can never be
    reached. That meets N7 in behaviour, and putting `#if` into the view would be worse.
- **Wiring and routes.**
  - `AppTabs` draws `SettingsRoot(about: .main, …)` under the stack's bar, so the back button is kept (N8).
  - `MainRoot` resolves `.debugMenu` by raising its existing sheet.
  - `resolve` moves no tab and no stack (pinned).
  - The F13 merge lines (History beside Settings) are both kept.
- **`SegmentedChoice` as a component.**
  - Its API mirrors `FilterChipRow`'s, the house idiom for string-only choice controls: closures for title, spoken
    label and selection, and `onSelect` hands back the caller's own option.
  - It is ink, never orange, dims when disabled, and is fixed-size with 44 pt options.
  - To VoiceOver it is a container named by `label`, with buttons carrying `.isSelected` and the hint.
  - Its doc comment is accurate.
  - `isSelected` as a predicate cannot enforce "exactly one", but `FilterChipRow` makes the same trade-off and the
    model documents the invariant. That is not a finding.
- **Simplicity and idiom.**
  - The files are small and decide nothing. Every string comes from the model, and the source tests enforce it.
  - The comment density matches the surrounding modules.
  - `SettingsRowLabel` and `SwitchRow` each spell out title-over-detail (the switch's label must stay accessible,
    unlike `SettingsRowLabel`), which is acceptable.
  - `SettingsViewStops` is the fifth copy of `ViewStop` across the feature test targets. That is pre-existing
    practice; hoisting it into `LedgerTestSupport` is a cross-feature follow-up, not this slice's.
- **R3-1 to R3-3: the windows are real GRDB orders.**
  - **R3-1.** GRDB delivers one observation's values in order on one scheduler: the initial fetch (A), then the
    fetch after B's commit. With the consumer suspended at `for await`, A is handed over directly rather than
    coalesced by `.bufferingNewest(1)`. So "D receives A, then B's echo" is the order production produces, and the
    double now queues behind the held first value to match.
    - The `withObservationTracking` check is the right way to see a transient flash that the final state hides.
    - M1 is killed 3/3.
  - **R3-2.** D's first value can land after the second save's saver has started: the tap's `send`, the saver's
    resume and GRDB's delivery are independent main-actor jobs. So holding the read until `untilHeld()` is a
    reachable order, now deterministic. M7 is killed 3/3, through the whole FeatureSettingsTests run.
  - **R3-3.** The mechanism is real: `follow` bumps `observationNumber` in the same job that finishes `retired`, and
    the old loop's cancellation lands jobs later. But see R1-4 on how wide the test holds it. M4 is killed 3/3.
  - **R3-4.** The comment is moved, and nothing else.

---

**F14-S1b-R1-1 (Minor, test gap). Nothing pins that Settings' Diagnostics reaches `MainRoot`'s sheet.**
- **Failure scenario:** a refactor of `AppTabs` or `MainRoot`, such as the next lane's merge of a route line (K1),
  drops either:
  - `onSettingsRoute: { router.resolve($0) { isDebugMenuShown = true } }` in `MainRoot`, or
  - `onRoute: onSettingsRoute` in `AppTabs`.

  Both fall back to the `{ _ in }` default, so tapping "Diagnostics" in a Debug build does nothing, and every test
  stays green.
- **Measured:**
  - H5 (`MainRoot`'s argument removed) and H6 (`AppTabs` passes `{ _ in }`) both **survive** all 341
    LedgerAppKitTests.
  - No hosted or UI test activates Diagnostics through the app: `SettingsRouteMappingTests` calls `resolve` directly,
    and `AppTabsTests` only pushes `.settings`.
  - Today's long press, the other way into the same sheet, has UI tests (`DebugMenu`, `TabsAdversarial`).
- **Fix:** add one step to the nightly `Settings` UI test or to `DebugMenu.swift`: Today → gear → "Diagnostics" → the
  Debug menu's sheet appears. Alternatively, add a hosted `AppTabs` test that pushes `.settings`, activates
  "Diagnostics" and checks that the injected `onSettingsRoute` received `.debugMenu`. The UI step covers both lines.

**F14-S1b-R1-2 (Nit, test placement). `SegmentedChoice`'s group semantics are pinned only by a FeatureSettings test.**
- V9 removes `.accessibilityElement(children: .contain)` and `.accessibilityLabel(label)`. All 7 LedgerDesign
  `SegmentedChoice` tests pass under it. It is killed only by G2's
  `SettingsScreenAdversarialTests.unitsOptions_sitInAGroupNamedUnits`.
- **Failure scenario:** a second feature adopts the control (S2's plate inventory unit, say), and Settings later
  stops using it. An edit that drops the group would then pass the whole suite, and VoiceOver would stop naming the
  choice.
- **Fix:** move G2's UIKit parent-group probe, or a copy of it, into `SegmentedChoiceTests`, so the design system
  pins its own documented contract.

**F14-S1b-R1-3 (Nit, docs). Stale comment in `SettingsStore.swift:15-16`.**
- It reads: "`SettingsRoot`, the screen over it, is S1b's; until then only the tests make one." S1b has landed, and
  the app makes one.
- **Fix:** drop the second clause.

**F14-S1b-R1-4 (Nit, test fidelity). R3-3 holds the retire window open far wider than production can.**
- The first observation stays uncancelled across a whole second save and a third observation's fresh read, then
  receives A's echo. In production, cancellation lands a few main-actor jobs after `finish()`, long before another
  GRDB write and restart.
- The guard still matters, and the test still kills M4. The reachable form of the hazard is narrower: the old
  observation's late value lands just after the *next* observation's first value. With a change from elsewhere in
  between, that would draw an older row over a newer one.
- **Fix (optional):** say this in the test's doc comment, so the scenario isn't read as a production order, or
  re-shape the test to that narrower order (old echo after observation 2's first value, with an outside write).

---

**Mutation table, round 1.**
- **Host:** `swift test` on a `git archive` copy of `76945c7`.
- **Simulator:** iPhone 17, iOS 27.0, PR plan, `build-for-testing` outside the lock, then
  `test-without-building` through `sim-lock.py`, running FeatureSettingsTests and LedgerDesign's `SegmentedChoice`
  tests, snapshots and adversarial suite.
- **Baselines:** host 54 + 8 tests green; simulator 72 + 6 green.
- **Clean-up:** after every mutant, `diff -r` of Sources against the worktree was empty.

| # | Mutation | Where | Result |
|---|---|---|---|
| V1 | announce never called | `SettingsRoot` `onChange` | Killed (`failedSave_isAnnounced`, 3 issues) |
| V2 | `announce(problem ?? "")`, so a cleared line is announced | `SettingsRoot` `onChange` | Killed (`failedSave_isAnnounced`) |
| V3 | `.task(id: pendingRoute)` → `.task` | `SettingsRoot` | Killed (`root_runsTheStore_savesAndHandsARouteOnce`) |
| V4 | loading draws `Color.clear`, not the title | `SettingsRoot` | Killed (`loading_drawsTheTitle`, `loadingTitle_standsWhereThePagesWill` ×5) |
| V5 | problem line never drawn | `SettingsPage` | Killed (tree ×4, `failedSave_showsTheLine`, Arabic ×5) |
| V6 | `.isSelected` trait never added | `SegmentedChoice` | Killed (`options_readTheirNames…` ×2, Settings tree ×12) |
| V7 | `onSelect(options[0])` | `SegmentedChoice` | Killed (`activating_handsTheChosenOption`, `controls_sendTheirModelsActions`) |
| V8 | ink pill drawn on the unselected option | `SegmentedChoice` | Killed (component snapshots ×6, Settings snapshots) |
| V9 | group container and label removed | `SegmentedChoice` | Killed only by G2's `unitsOptions_sitInAGroupNamedUnits`; survives LedgerDesign's own tests (R1-2) |
| V10 | switch binding reads `true` | `SwitchRow` | Killed (tree, rapid-tap test, snapshot) |
| V11 | menu's `accessibilityValue` removed | `WeekStartRow` | Killed (tree ×12, Persian week, Arabic) |
| V12 | never stacks at accessibility sizes | `SettingsRowLayout` | Killed (`controls_moveUnderTheirLabels`, snapshots) |
| V13 | rest's hint removed | `RestRow` | Killed (tree ×12) |
| V14 | Diagnostics row sends nothing | `SettingsPage` | Killed (`controls_sendTheirModelsActions`) |
| H1 | blank check removed | `AppAbout(bundle:)` | Killed (`about_blankDisplayName…` ×3, 6 issues) |
| H2 | `CFBundleName` before the display name | `AppAbout(bundle:)` | Killed (`about_everyKey`) |
| H3 | `.whitespacesAndNewlines` → `.whitespaces` | `AppAbout(bundle:)` | Killed (the `"\n"` case) |
| H4 | `showDebugMenu()` not called | `Routes+Settings` | Killed (`debugMenu_raisesTheSheet`, `debugMenu_leavesHistoryAlone`) |
| H5 | `onSettingsRoute:` argument removed | `MainRoot` | **Survives** all 341 LedgerAppKitTests (R1-1) |
| H6 | `AppTabs` passes `{ _ in }` to `SettingsRoot` | `AppTabs` | **Survives** all 341 LedgerAppKitTests (R1-1) |
| M1 | `isFirst && writes == writesBefore` → `isFirst` | store (R3-1) | Killed 3/3 (`firstValueReadBeforeASave_isNotTheRow`) |
| M4 | `number == observationNumber` dropped per value | store (R3-3) | Killed 3/3 (`retiredObservationsValue_isNeverReceived`) |
| M7 | failure leaves `hasWrittenOrFailed` false | store (R3-2) | Killed 3/3 in the full FeatureSettingsTests run (`failureBeforeTheFreshRead_stillReadsTheRow`) |

**Runs:** H5 and H6 were not run on the simulator or in the UI tests. A grep shows that no test in either references
`onSettingsRoute` or activates Settings' Diagnostics. The full gate is the coordinator's.

## S2 — G3 round 1

**S2: G3 review (round 1, 2026-11-10), of `git diff da6470d...4ae944b`** (implementation `a472372`, notes `f40dc55`,
G2's tests `4ae944b`). I checked it against the brief's "### S2" (criterion 1's program part, 3 and 5; N11–N18), the
"Rulings before G1" (A2, A4), `docs/engineering-standards.md`, `docs/architecture.md` and the seven review points. I ran
`/code-review` at high and triaged its findings below. The review is read-only: I read files with `git show 4ae944b:…`
and ran the host tests on a `git archive` copy in my scratchpad. No file in the worktree changed except this one. I
left out G2's three findings (F14-S2-G2-1 to -3), because the concurrent fix round owns them.

**Verdict: APPROVED WITH SHOULD-FIXES. 0 Blocking, 4 Should fix, 8 Nits.** Ruling A4 is built as ruled: GRDB uses one
`queue.write`, it is proven by a commit counter and by G2's refusing triggers, and the fake agrees. The CSV's shape,
quoting, formula guard and BOM are correct and covered by two independent RFC 4180 readers. No module-boundary,
UIKit, `Task.detached` or force-unwrap violation. The four Should-fixes are small, and two of them (S2 and S3) close
flakiness or glitch vectors before they reach the nightly lane.

### What holds (verified)

- **`switchUnits`, one transaction (A4).**
  - `GRDBSettingsRepository.switchUnits` (`:38–49`) does the read-before, the upsert and
    `GRDBProgramRepository.convertActive` in one `queue.write`. A throw anywhere rolls both back: the program's own
    `ProgramRows` checks, an unreadable active program, or a trigger. `grdb_oneTransaction` counts exactly one commit,
    and G2 rolled back byte for byte with triggers on both tables.
  - **GRDB and the fake agree on every observable rule**:
    - With no row, both compare against `Settings.default`: GRDB's `fetch` returns `.default`, and the fake holds
      `.default` with `isRow == false`.
    - Same units convert nothing.
    - With no active program, only the settings are written.
    - Only the active program converts.
    - Equipment includes deleted exercises (GRDB selects every `exercise` row; the fake reads `rows`).
    - G2's lb → kg → lb → kg → kg differential passes.
  - The fake checks the codec first, converts next (the only step that can throw), and writes the settings last.
    That keeps "both or neither" for failures. Its two-lock race is Nit N5.
  - `convertActive` writes through `write(ProgramRows(…))`, as `update` does, so only changed rows are touched and
    `observeActive` hears one change.
- **The 11 doubles.** Each forwards to its base, as its `seedIfAbsent` does (`ProbedSettings` and the AppRoot probe
  also journal), or is a no-op or throwing stub that matches its own `save`. `ScriptedSettings` routes the switch
  through `save`'s hold-and-refuse script, and `WatchedSettings` records switches separately. None changes an
  existing test's meaning.
- **`UnitSwitch.convert`** is pure, 36 lines, idempotent (property-tested at 200 seeds by G2), with steps floored at
  one grid step and `nil` kept as `nil`. Assigning fields without `Slot.init` is safe, as the doc says: a rounded
  non-negative load stays non-negative, and a step stays at least one grid step.
- **CSV (N13–N15).**
  - The header is per unit, and rows end with CRLF.
  - Quoting is by Unicode scalar, so a quote followed by a combining mark is still doubled.
  - The formula guard covers `= + - @ \t \r` on the three free-text columns only. `date`, `time`, `kind` and numbers
    are never prefixed, and a negative weight stays a number.
  - Weights are rounded to hundredths, away from zero, with no `-0`.
  - The BOM is EF BB BF, written once by the writer and never by `render`.
  - Dates use the lifter's calendar and come out as ISO Gregorian days, even under Buddhist, Persian and Japanese
    calendars (G2).
- **The ShareLink / Transferable lifecycle (A2, N16, N18).**
  - `FileRepresentation(exportedContentType: .commaSeparatedText)` calls `write` only when a destination is
    picked.
  - `SentTransferredFile(url)` uses the default `allowAccessingOriginalFile: false`, so the system hands the
    receiver a copy. Clearing `Export/` when Settings goes away (`run()`'s end, only for the latest run) therefore
    cannot pull the file from under a transfer that is still going.
  - The write runs off the main actor (a `nonisolated static` closure), and the workouts' dependency is captured
    whole and resolved only then.
  - FeatureSettings imports `CoreTransferable` and `UniformTypeIdentifiers`, never UIKit.
  - The log message carries an error description, no health data.
- **Accessibility.** The plate sheet's tree is pinned exactly at four sizes (xSmall to accessibility5):
  - the bar is one adjustable element with a spoken value;
  - "Plates you own" is a heading;
  - each plate is a toggle named by its spoken weight;
  - then the empty line, "Reset to standard" and "Done".

  No stop is under 44 pt or overlaps another. The disabled "Bar and plates" row is one dimmed button whose line says
  why. The export row is one button, "Export data, CSV", with its line as the hint. A failed switch's line differs
  from S1's, so S1b's `onChange(of: problem)` announcement fires for it too.
- **Copy.** All 17 new strings are in `SettingsCopy+Plates` and `SettingsCopy+Export`, each with a translator
  comment. Spoken text is copy ("Export data, CSV"). The file name's comment warns translators to keep it a valid
  name. The `"Export"` path literal exemption in `ModuleCopyTests` is a path that is never drawn. **Confirmed**
  (standards §7: the reviewer confirms each exemption).
- **Test quality.** The added tests contain no sleeps, `Task.yield` loops or `asyncAfter`. The hosted trees use exact
  equality, and the store tests assert bytes and rows, not calls. The one flakiness vector is S2 below.
- **Host run (my copy at `4ae944b`)**: `swift test --enable-code-coverage --filter "FeatureSettingsTests|SwitchUnits|UnitSwitch|CSVExport|SettingsRepository|InMemoryContract"`
  (logs: `f14-s2-g3-host.log` in my scratchpad):
  - **Result:** exit 0, with three test runs:
    - 41 tests, 1 known issue;
    - 49 tests;
    - 94 tests in 14 suites, 2 known issues (G2-1 and G2-2, being fixed).
  - **Host coverage of the new logic:**
    - `UnitSwitch` 100 %;
    - `CSVExport` 94.3 %;
    - `PlatesPresentation` 100 %;
    - `SettingsStore+Plates` 97.4 %;
    - `SettingsStore+Export` 82.5 %;
    - `ExportFile` 89.5 %;
    - `WorkoutExport` 26.7 %.

  I did not run the simulator. The G1 gate (`check.sh` full, exit 0) and G2's hosted runs are the evidence for the
  views.

### Blocking

None.

### Should fix

**S1. The settings contract has no `switchUnits` clause.**
- **Where:** `LedgerKit/Sources/LedgerTestSupport/Persistence/SettingsRepositoryContract.swift:12–20`.
- **What's wrong:** ruling A3 set the pattern: a new `SettingsRepository` requirement comes with contract clauses
  (`seedIfAbsent` got two). `switchUnits` got none. Its settings-only behaviour is pinned only by `SwitchUnitsTests`,
  which builds the two concrete stores by hand:
  - the settings are saved, and `observe` emits them;
  - same units is an ordinary save;
  - a NaN weight is refused, and nothing is written.

  F28's iCloud-backed repository, or any third implementation, would not be held to it.
- **Fix:** add three clauses that need no program store:
  1. "switchUnits saves the settings and observe emits them";
  2. "switchUnits with the stored units is a save";
  3. "switchUnits refuses what save refuses, and writes nothing" (reuse `refusesNaN`'s settings).

  The conversion half stays in `SwitchUnitsTests`, which needs a program store.

**S2. Two exports at once race on one directory and one path, and G2's `export_twoAtOnce` can flake.**
- **Where:** `LedgerKit/Sources/FeatureSettings/Export/ExportFile.swift:26–34`;
  `Tests/FeatureSettingsTests/Adversarial/PlatesExportAdversarialTests+Export.swift:83`.
- **What's wrong:** `write` runs `clear(directory)`, then `createDirectory`, then `createFile` at a fixed name, all
  synchronously on the cooperative pool. Two calls can run truly in parallel: the share sheet loading the
  representation twice, or share, cancel and share again during a slow write. If B's `clear` lands between A's
  `createDirectory` and A's `createFile`, A's `createFile` returns false and A throws `fileWriteUnknown`. If it lands
  after A opened its handle, A writes to an unlinked inode and returns a path that holds B's file. Fifteen green
  repeats don't rule out a microsecond window. The test asserts the very outcome the race can break, so it is a
  latent P1 flake under standards §9.
- **Fix:** serialise the writer. For example, make `ExportFile`'s write go through a small `actor ExportWriter` held
  by the store and captured by `WorkoutExport.write`, so clearing and writing are one critical section. Or write each
  export to `Export/<uuid>/` with `@Dependency(\.uuid)` and clear only on the store's run end. Keep G2's test; it then
  passes by construction.

**S3. The plate sheet's content goes blank while it animates away.**
- **Where:** `LedgerKit/Sources/FeatureSettings/Views/SettingsScreen.swift:18–26`.
- **What's wrong:** the sheet is `.sheet(isPresented:)`, and its content is `if let sheet = model.platesSheet`. "Done"
  and "Cancel" set `plates = nil` first, so the model's `platesSheet` is nil during the dismissal animation. SwiftUI
  re-evaluates the content closure, and an empty sheet slides down. The hosted tests draw `PlatesParts`, not the
  presentation, so no test sees it.
- **Fix:** `.sheet(item:)` keeps the last item's content through the dismissal. Make `PlatesModel` (or a small
  wrapper keyed on the draft's units) `Identifiable` and bind `item:` with the same `cancelPlates` setter. The custom
  `isPresented` Binding then goes away.

**S4. Only the active program is converted; every other program keeps the old unit's grid.**
- **Where:** `LedgerKit/Sources/LedgerPersistence/Repositories/GRDBProgramRepository.swift:144`
  (`convertActive`), `LedgerKit/Sources/LedgerFakes/InMemoryProgramRepository.swift:119`.
- **What's wrong:** this follows criterion 1's words ("in the active program"), so it is not a defect against the
  brief. But weights are stored as unit-free grams. A lifter with blocks A (active) and B switches lb → kg: A's
  135 lb becomes 60 kg, while B keeps 61.235 kg loads and 2.27 kg steps. When B is activated later, Today and the Day
  editor show off-grid weights, and nothing will ever convert them (the switch has already happened).
- **Fix (needs the orchestrator's ruling, so not blocking):** either convert every live program in the same
  transaction (`SELECT id FROM program WHERE deleted_at IS NULL`, the same loop, so cheap), or amend criterion 1 to
  say other programs stay as they are, and record it as a known limitation for Pete.

### Nits

**N1. N17's memory measurement cannot catch the regression it names.**
- **Where:** `Tests/FeatureSettingsTests/ExportPerformanceTests.swift:65–70`; deviation 6 in the notes.
- **What's wrong:**
  - **What it measures:** `phys_footprint` after the write minus before it, so freed transient allocations never
    show.
  - **What it leaves out:** the input `[WorkoutState]` is built before `before`, and the product's
    `workouts(in: distantPast..<distantFuture)` read and the sorted copy (`ExportFile.swift:35`) are not measured at
    all. The real peak grows with the whole history.
  - **Why it can't fail:** even a true peak would not tell streaming from rendering. 10,000 rows of about 60 bytes is
    about 0.6 MB as one `String`, well under 5 MB.
- **Ruling on the deviation:** acceptable as a smoke figure. It isn't a budget proof, and the time budget is the
  meaningful half.
- **Fix:**
  - **Brief:** amend N17 to "footprint retained after the write" (or drop the memory half).
  - **If a real peak is wanted:** sample `phys_footprint` on a background task during the write, or measure the
    whole export path through the store with an `XCTMemoryMetric` test.
  - **Time budget:** 165 ms against 200 ms on the Mac host leaves a thin margin for a shared runner. Take the
    median of 5 runs.

**N2. The export silently omits damaged workouts.**
- **Where:** `SettingsStore+Export.swift:32`.
- **What's wrong:** `workouts(in:)` reads with `strict: false`, so a row this version cannot decode is logged and
  dropped. The file says "Every set you logged". This is the same rule History uses, so it is acceptable for M1.
- **Fix:** either have the writer log how many workouts were written against the stored count, or note the rule in
  the row's doc. Worth a line in the notes.

**N3. The file's name and the export are rebuilt on every `show()`.**
- **Where:** `SettingsStore.swift:185`.
- **What's wrong:** each redraw reads `date.now` and builds the localized name, and the name is frozen at the last
  redraw. Settings left open past midnight shares `workouts-<yesterday>.csv`.
- **Fix:** compute the name inside the `write` closure (the `SharePreview` title can stay the redraw's), or key the
  export on the units only.

**N4. `GRDBSettingsRepository.switchUnits` swallows every error of its read-before.**
- **Where:** `GRDBSettingsRepository.swift:43`.
- **What's wrong:** `try? Self.fetch(database)` has a comment, but it also hides a `DatabaseError` (I/O, corruption),
  not only an unreadable payload. Those are converted as if the units had changed.
- **Fix:** catch only `LedgerPersistenceError.malformedColumn` and decoding errors, and rethrow anything else.

**N5. The fake's `switchUnits` compares and writes under two separate locks.**
- **Where:** `InMemorySettingsRepository.swift:50–55`.
- **What's wrong:** two concurrent switches (kg, lb) can both read lb. One converts the program to kg, and the other
  then stores lb, so the program ends in kg under lb settings. GRDB serialises them. The store never runs two saves
  at once, so no test hits it today. The doc says "no write can fail between them" but not that they cannot
  interleave.
- **Fix:** do the comparison, `programs?.convertActive` and the settings write inside one `state.write` closure.
  Nesting programs' lock inside settings' lock is the only nesting, so there is no ordering hazard. Or say so in the
  doc.

**N6. A failed switch's draft and "Try again" edge cases.**
- **Where:** `SettingsStore+Plates.swift:16, 45`; `SettingsStore.swift:130`.
- **What's wrong:**
  1. The lifter taps KG and opens the plate sheet at once, and the switch then fails. The sheet keeps editing kg
     while the screen is back in lb. "Done" saves the kg inventory, which is correct by `draft.units`, and clears
     the failure line through `change(to:)`.
  2. If a switch ever throws after its commit, "Try again" sends `.setUnits(kg)` while `shown.units == .kg`.
     `change(to:)` returns early, and the line stays. GRDB returns, rather than throws, after a commit, so this is
     only theoretical today.
- **Fix:**
  - For the draft: close the sheet (`plates = nil`) when a failed switch reverts the units it was opened in.
  - For "Try again": clear `failedSwitch` and `saveFailed` when `shown.units` already equals it.

**N7. `CSVExport.render` is quadratic.**
- **Where:** `CSVExport.swift:57`.
- **What's wrong:** `reduce(header) { $0 + lines(…) }` copies the accumulated string on every workout. It is used by
  tests only today, and they render 10,000-set logs.
- **Fix:** `reduce(into: header(units:)) { $0 += lines(…) }`.

**N8. The sheet's chrome is outside every hosted test.**
- **Where:** `Tests/FeatureSettingsTests/PlateInventorySheetTests.swift`.
- **What's wrong:** the tree and snapshots read `PlatesParts` (page and foot). `SheetChrome`'s title and "Cancel",
  and the presentation through `SettingsScreen`, are tested nowhere in FeatureSettings. "Cancel" sending
  `.cancelPlates` is covered only through the store.
- **Fix:** one hosted test that draws `SettingsScreen` with `platesSheet` set and activates "Cancel". It would also
  catch a regression of S3's binding.

### Coverage (FeatureSettings 96.97 %, down from S1b's 98.81 %)

**Acceptable.** Strictly, DoD §12 says "coverage does not decrease", and this slice lowers FeatureSettings by
1.84 points. But the drop comes from code that unit tests cannot reach, not from untested behaviour:
- **Where the drop comes from:** the slice adds 605 coverable lines, of which 37 are uncovered (S1b had 12 uncovered
  of 1,013 lines; now 49 of 1,618).
- **What the host shows uncovered among the new logic files:**
  - `WorkoutExport.transferRepresentation` (`:21–25`): only the system's share sheet calls it, and the nightly UI
    test runs outside coverage.
  - `WorkoutExport.unavailable`'s throwing closure (`:28–30`).
  - `ExportFile.write`'s `createFile` failure and its close-on-error branch (`:30, 41–43`).
  - The store's export catch (`SettingsStore+Export.swift:35–37`) and `clearExports`' catch (`:46`).
  - The remainder are views and their guard returns, which the iOS-hosted suites cover.
- **New behaviour:** about 94 % covered, and every rule in it at 100 %.
- **Threshold:** 70 %.

**One cheap test would claw back the meaningful part.** Run the store's export over a `WorkoutRepository` whose
`workouts(in:)` throws, and assert three things:
1. `write()` rethrows;
2. one error line is logged under "settings" (the injected logger);
3. no file is left in the directory.

That covers N16's "a failure is logged", which no test asserts today. Record the accepted decrease in the notes.

### Review points

1. **Module boundaries:** clean.
   - `UnitSwitch` and `CSVExport` are in the Domain.
   - GRDB stays in Persistence.
   - FeatureSettings imports Domain, Dependencies, Design, CoreTransferable and UTType, and no UIKit (N18).
   - `CSVReader` is in LedgerTestSupport.
2. **Concurrency:**
   - The write runs off the main actor, every captured value is `Sendable`, and there is no detached or
     fire-and-forget task.
   - The clock goes through `@Dependency(\.date)`.
   - The only defect is S2's parallel writers. Optionally, `ExportFile.write`'s loop could call
     `Task.checkCancellation()` (standards §4) when the system cancels a transfer.
3. **Error handling:**
   - Failures are logged under "settings".
   - The switch's failure maps to its own line and retry.
   - The export's failure goes to the system sheet (ruling A2).
   - The `try?` uses have comments; see N4.
4. **Design fidelity:** tokens only. Ink for "Done" (no accent, C28), ghost for Reset, `SheetChrome`,
   `FilterChipRow` and `StepperField`. The references were re-recorded and looked at.
5. **Accessibility:**
   - The trees are pinned exactly.
   - Every stop is at least 44 pt up to accessibility5.
   - The disabled row says why.
   - The export has a spoken label and a hint.
   - The failed switch is announced.
   - S3 is visual only.
6. **Test quality:** behavioural, with no sleeps. S2's race is the one flakiness vector, and N8 is a gap.
7. **Brief compliance:**
   - **Criterion 1 (program part):** `UnitSwitchTests`, `SwitchUnitsTests`, `SettingsUnitsStoreTests`.
   - **Criterion 3:** `SettingsPlatesExportStoreTests`, the sheet's tree and snapshots.
   - **Criterion 5:** the export's bytes against BOM + `render`, oldest first; the nightly UI test.
   - **N11:** reworked by A4; G2-2 amends its copy.
   - **N12–N16:** tested.
   - **N17:** nightly, with N1's caveat.
   - **N18:** source test with no UIKit, plus the UI test.

   Every criterion has a test.
