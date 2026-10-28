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
