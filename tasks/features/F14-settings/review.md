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
