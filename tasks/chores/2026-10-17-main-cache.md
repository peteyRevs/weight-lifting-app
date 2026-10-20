# main's compilation cache (2026-10-17)

**Status (2026-10-20):** not merged on 2026-10-17, for its cost ("Cost" below). Cherry-picked into
`chore/ci-test-time` once the repository was public and standard runner minutes free; check-wiring's
`--build-only` cases are W77 and W78 there (the arm64 chore had taken W76). See `tasks/chores/ci-test-time.md`.

Branch `worktree-agent-a92dc1ccb90626738`, cut from `main` at `5070b5b`. It follows the sweeps chore
(`tasks/chores/2026-10-17-pr-sweeps.md`) and reverses one decision of the CI efficiency notes
(`tasks/features/F01-ci-gates/ci-efficiency-notes.md`, "No warm-up job on `main`").

## The problem

`Check` restores `.derivedData/CompilationCache.noindex` with restore-keys meant to find "its PR's newest, then
main's". GitHub scopes caches by branch: a `pull_request` run may read its own ref's caches and the base
branch's, nothing else, and no workflow ever saved one on `main` (`pr.yml` runs on `pull_request` and
`workflow_dispatch` only). So every PR's first run built cold. On 2026-10-17 the first runs of #58–#61 logged
`Cache not found for input keys: compilation-…` and built iOS in 937–1,458 s. #59 reached the 3,120 s
deadline (exit 75, build 1,458 s, no test failing); #60 passed with about 90 s to spare (build 1,096 s, tests
1,917 s). The package checkouts had the same hole: their exact-key cache was only ever saved in a PR's scope.

The runner's own warm builds, from the logs of earlier runs (`gh run view --log`, 2026-10-08 and -10):

| Run | Restored | iOS build |
|---|---|--:|
| 37821177162 (F10 S4, first push) | nothing | 1,221 s |
| 37859418999 (F10 S4, second push) | its PR's cache of the first push | 750 s |
| 38068802970 (F10 S5, re-run) | the exact key: same commit | 452 s |
| #59, first run (2026-10-17) | nothing | 1,458 s |
| #59, re-run (2026-10-17; the coordinator's figure) | the exact key: same commit | 760 s |

Restoring took 8–16 s for 414–439 MB compressed, saving about 20 s. A build with every compile a hit is still
452–760 s on the runner, about half of cold: a warm cache halves the build there, it does not make it minutes.

### What a warm build still does

`xcodebuild … -showBuildTimingSummary` on the Mac, the build-only arguments, everything under `.derivedData` but
the packages and the cache deleted (task times are summed over parallel tasks; wall 117 s cold, 27 s warm):

| Task | Cold | Warm |
|---|--:|--:|
| SwiftCompile (546 tasks) | 771 s | 11.5 s (replayed hits) |
| SwiftDriver (75: planning and the dependency scan) | 60 s | 65 s |
| SwiftEmitModule (75) | 64 s | 1.2 s |
| Ld (81 links) | 20 s | 34 s |
| CodeSign (36) | 5 s | 8 s |
| ExtractAppIntentsMetadata (59) | 6 s | 6.4 s |
| everything else | about 6 s | about 8 s |

So a warm build is the driver's planning per module, linking, signing and the App Intents extraction: about
135 s of task time, uncached by design, which 3 runner cores and 7 GB of memory turn into 452–760 s. The runner's
own split is not known: `-quiet` hides it (a `-showBuildTimingSummary` on Check's build would show it; it changes
no compile argument). Package resolution is not part of it once the package cache hits.

**A cheap lever found:** the iOS `build-for-testing` also builds the embedded watch app, and its 16 package
modules for the watch simulator in **both arm64 and x86_64** (`SwiftDriver … normal x86_64`,
`CreateUniversalBinary`, 18 tasks). With `ARCHS=arm64` on the command line, the same build had 422 compile tasks
instead of 546, 59 modules instead of 75 and 63 links instead of 81: wall 100 s cold (from 117) and 22 s warm
(from 27), and 683 s of compile task time instead of 771. `EXCLUDED_ARCHS[sdk=watchsimulator*]=x86_64` on the
command line did not take. Every lane runs on Apple silicon (the `xcode-27` image is arm64). On a 3-core runner,
where task time is what counts, this should cut a cold build by roughly 10–20% and a warm one by 15–20%. It
changes every build's arguments (each cache starts over once) and needs the full gate; it is not in this
change, which keeps `check.sh`'s build as it was.

## The change

1. **`scripts/check.sh --build-only`.** Step 0 (the Xcode pin, the tools), then step 3's iOS
   `build-for-testing` through the same `test_platform` code, so the scheme, the `PR` plan (whose coverage
   setting changes the compiler's arguments), the simulator by UDID, the paths, the package pins and
   `LEDGER_COMPILATION_CACHE` are Check's by construction. No simulator boot, string catalogs, tests, watchOS
   or coverage. It takes no other flag (exit 2). Internally it sets `IOS_ONLY` and `SKIP_LINT`, which the
   rest of the script already reads.
2. **`.github/workflows/main-cache.yml`**, one job (`warm`, "Build main's cache") on `xcode-27`:
   - `on: push: branches: [main]` with `paths-ignore: docs/**, tasks/**, design/**, *.md`: Scope's docs-only
     allowlist as a filter (GitHub skips the run only when every changed path matches; `*` stops at `/`, so
     `*.md` is root-level only, as in Scope). A rename into `docs/` that Scope counts as code can skip this
     run; the cost is a cache one merge older, not a missed check.
   - `concurrency: main-cache`, `cancel-in-progress: true`: one at a time, the newest push wins.
   - Checkout (full history), Select Xcode, mise, the package cache (`actions/cache`, exact key) and the
     compilation-cache restore are Check's steps, field for field (WF69). The build step runs
     `scripts/check.sh --build-only` with `LEDGER_COMPILATION_CACHE=YES` and no other variable.
   - The save runs on `success()` only, when the restore did not hit the exact key. A cancelled run (a newer
     push, or the job's timeout) and a red build save nothing, so main's newest cache is always a whole
     green build; `actions/cache` saves the package checkouts in its post step, also only after a green job.
   - Timeouts: the job 40 min, the step 35 min (a cold build was up to 1,458 s on 2026-10-17). No deadline:
     nothing reads the build's result bundle.
3. Tests: WF68–WF71 in `workflows.adv.sh` (the trigger, the filter against Scope's own step, concurrency,
   permissions; the setup steps equal to Check's; the one run step; the save's condition and key), and the
   suite's every-workflow cases (WF11, WF14, WF16, WF47, WF52, WF66, WF67) now read it too. `xcode27.adv.sh`
   WF54, WF56, WF57 and WF60 count its job among the Mac jobs. `check-wiring.adv.sh` W76 (the calls, and the
   build's arguments equal to the `--ios-only` iOS build's, the cache setting included) and W77 (a failed build
   fails it; any other flag exits 2).
4. Docs: `docs/ci-cd.md` ("Compilation cache", the `main` warm-up bullet, "Deadline"), `pr.yml`'s comment.

### Why a second workflow, not a job in `pr.yml`

A `push` trigger in `pr.yml` would run `Scope` and `Static checks` on main too (Linux minutes for nothing), put
a branch on every job's `if:` and into the concurrency group, and change WF02–WF09, which pin `pr.yml` as the
PR gate. A reusable workflow or a composite action would single-source the YAML steps but restructure `Check`,
which every WF case reads. The new file is 70 lines; what must match is single-sourced where it decides the
cache keys: the compiler arguments come from `check.sh` itself, and the five setup steps are compared with
Check's on every gate run (WF69), so a drift fails CI rather than silently missing the cache.

## Measured

On a developer Mac, under the simulator lock, `LEDGER_COMPILATION_CACHE=YES scripts/check.sh --build-only`
(script: scratchpad `measure.sh`). Between builds everything under `.derivedData` was deleted except
`SourcePackages` and, for a warm build, `CompilationCache.noindex`; before a warm build every tracked file
under `Apps` and `LedgerKit` was touched, as a fresh checkout would leave it.

| Build | iOS build | Cache after |
|---|--:|---|
| Fresh: packages resolved, then cold (not a timing) | 152 s | 1,510 MB, 3,131 files |
| Cold: empty cache, packages present | 114 s | 1,509 MB, 3,131 files |
| Warm: the cache alone | 34 s | 1,526 MB, 3,161 files |
| Warm again | 28 s | 1,538 MB, 3,182 files |

- **Size.** 1.5 GB on disk, **452 MB through `tar | zstd`** (how `actions/cache` stores it), in line with the
  414–439 MB the runner saved on 2026-10-08 and -10. It was 1.0 GB / 343 MB on 2026-10-01; the code has grown.
- **Growth.** A warm build with nothing changed added 12–17 MB. The cache is never pruned between saves (Xcode
  has `COMPILATION_CACHE_LIMIT_SIZE` and `_PERCENT`; neither is set here), so each merge adds what it
  recompiled. It starts over whenever the Xcode or either lockfile changes, since the key hashes them. If it
  grows past about 1 GB compressed, restoring costs more seconds; nothing breaks.
- **Storage.** Each `main` save is one entry of about 450 MB, as each PR save is. GitHub keeps 10 GB per
  repository and evicts the least recently used entry (and any not read for 7 days). `main`'s newest entry is
  read by every PR's first run, so it stays; older `main` entries are never picked once a newer one exists, so
  they go first. At about five merges and five PR pushes a day, 10 GB is two days of entries, more than any
  restore needs.
- **The keys match Check's.** From the cache the warm build-only runs left, after the same wipe and touch, Check's
  own command (`LEDGER_COMPILATION_CACHE=YES TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40 TEST_RUNNER_LEDGER_SWEEP=pr
  scripts/check.sh --ios-only --skip-static`) built iOS in **32 s** against 114 s cold, and the cache grew by
  7 MB (9 files): its compiles were hits. Exit 0; iOS tests 582 s; 656 s in all.

## Cost (for Pete)

**Plainly: in billed minutes the warm-up costs about what it saves.** It runs once per push to `main` that changes
code, release-please merges included (`Config/Base.xcconfig` and the manifest change). Each run is a warm build
on the runner, 452–760 s (the table above; a push also compiles what the merged PR changed, so expect the upper
end), plus about 60–80 s of checkout, Xcode, mise, restoring and saving: **about 10–14 billed macOS minutes per
code merge**, and once, after this merges, a cold build of about 25 min. At the rate implied by the "$1–2 per PR
push" estimate (roughly $0.05 a minute) that is about $0.50–0.70 per merge.

It saves each PR's first run the difference between a cold and a warm build: 937–1,458 s against 452–760 s,
about **8–12 minutes**. With one PR per merge the two cancel; every release-please merge (no PR first run to
save) tips it into a small loss, roughly 10–14 minutes per release.

What the minutes buy is headroom, not savings: a PR's first run gains about 700 s under the 3,120 s deadline,
which #59 reached on a 1,458 s cold build. A first run stopped by the deadline costs its 52 minutes plus a
re-run, so the job pays for itself if about one first run in four or five would otherwise hit the deadline
(one of the four on 2026-10-17 did, and #60 cleared it by 90 s).

Options to weigh before it ships, none done here:
- `ARCHS=arm64` in `check.sh`'s builds ("What a warm build still does"): no recurring cost, cuts every build,
  cold first runs included, by an estimated 10–20%. It could ship instead of this, or with it.
- Skip release-please merges in this workflow (a version bump recompiles little; not measured).
- `workflow_dispatch` only, run by hand when several PRs are about to open.

## Verification

- `scripts/tests/adversarial/workflows.adv.sh`: 74 passed. `xcode27.adv.sh`: 44 passed, 2 skipped (the opt-in
  `ADV_REAL_SIMCTL` and `ADV_COLD_PINS` cases, as before). `check-wiring.adv.sh`: 140 passed.
- Mutants of `main-cache.yml`, each caught: restore-keys renamed (WF69), save on `!cancelled()` (WF71), a path
  dropped from the filter, `cancel-in-progress: false`, another branch (WF68), `--ios-only --skip-static` instead
  of `--build-only` (WF70, WF71), the cache off (WF70), `fetch-depth: 1` (WF47, WF69). Mutants of `check.sh`: no
  return after the build, an extra build argument in `--build-only`, the flag check removed, a boot added (W76,
  W77, and W02 onward).
- `scripts/check.sh --lint-only`: exit 0, 81 s.
- Full gate, `scripts/check.sh` with no variables (cache off, cold build): **exit 0, 1,475 s** (iOS build 112 s,
  iOS tests 978 s, watchOS build 55 s, watchOS tests 244 s).
- A first full-gate attempt run with `LEDGER_COMPILATION_CACHE=YES` exported failed in check-wiring W65, whose
  "unset" case inherited the export. Not this change's doing, but W76 lives beside it, so the suite now unsets
  the variable at its start; with it exported the suite passes (140).
- Not shown until it runs on GitHub: that a push to `main` saves both caches in `main`'s scope, that a PR's first
  run then logs `Cache restored from key: compilation-…` from it, and the runner's warm-build time.
