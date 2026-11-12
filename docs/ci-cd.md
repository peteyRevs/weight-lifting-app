# Ledger — CI/CD

Decision: ADR-006. Evidence: `docs/research/R3-tooling-ci.md` (2026-09-16).
Local parity: `docs/testing-strategy.md` §7 (`scripts/check.sh`) and §8 (test plans).

**Verified 2026-09-27 (F01), runner updated 2026-09-29 (F32).** `.github/`, `ci_scripts/` and `scripts/` are
authoritative; the plan differs:
- **Xcode 27 (Pete, 2026-09-29, F32).** Every macOS job runs on `xcode-27` (arm64), a **public preview**
  image (actions/runner-images#14404): macOS 27.0, Xcode 27.0 (27A266a) at `/Applications/Xcode_27.app`,
  linked as `Xcode_27.0.app`, and iPhone 17 and Apple Watch Series 12 (46mm) on 27.0 (no Series 11). The
  standard `macos-26` image has only Xcode 26.x. It still carries 26.6, but rolling back to 26.6 means
  reverting F32 as a whole, lockfiles and snapshot references included, and each later merge makes that
  harder (ADR-006 amendment). `.github/actionlint.yaml` names the label, which actionlint 1.7.12 does not
  know yet.
- Xcode from `.xcode-version`, and `check.sh` step 0 fails on any other Xcode (as `bootstrap.sh` does);
  SHA-pinned actions; `$(PROJECT_DIR)` expands in test plans. Simulators by UDID (`sim-destination.sh`).
- **Package pins (F32).** Every `xcodebuild` in `check.sh` and the nightly passes
  `-onlyUsePackageVersionsFromResolvedFile`, and `--fast` passes `--only-use-versions-from-resolved-file`,
  so a stale `Package.resolved` fails instead of being rewritten. Both tools trust existing checkouts, so
  only a cold package directory proves it: the PR cache restores on an exact key only (no `restore-keys`).
  Verify a PR that changes pins after `rm -rf .derivedData/SourcePackages`. `xcodebuild` reads only the
  project's lockfile, so `check.sh` step 2 (`scripts/check-package-pins.sh`) fails unless
  `LedgerKit/Package.resolved` pins exactly the same packages, versions and revisions.
- Test runs pass `-collect-test-diagnostics never`: on a failure Xcode 27 runs `simctl diagnose`, which
  timed out after 600 s per platform (F32). The result bundle keeps the failures, logs and attachments.
- **Free minutes (Pete, 2026-09-27); paid from 2026-09-30; free again since the repository went public
  (2026-10-20: standard runners).** `pr.yml`'s macOS jobs are `Check`, since 2026-11-11 two shards
  (`Check (shard 1/2)` and `Check (shard 2/2)`, each `check.sh --ios-only --skip-static --shard <n>/2`), and
  `Coverage` after both ("Shards", below). They run after two Linux jobs: `Scope` skips
  every later job when only files under `docs/`, `tasks/` or `design/`, or `*.md` at the repository root,
  change (renames count at both paths). `Static checks` comes next (below). `main-cache.yml` builds on
  each code push to `main` to save `main`'s caches ("What is main-scoped", below). Nightly is manual;
  release-please runs on Linux, and CI never runs on its release PR. §4: no protection.
  §9 is superseded: before the changes below, a green `Check` job took 846–1,302 s (15–22 billed
  minutes) over the six green iOS-only runs to 2026-10-01, 805–1,262 s of it in `check.sh`. The notes
  under "CI efficiency" say what is measured after them, and what only CI can measure.
- **CI efficiency (2026-09-30; `tasks/features/F01-ci-gates/ci-efficiency-notes.md`).**
  - *Linux image pinned.* Every Linux job names `ubuntu-24.04`, not `ubuntu-latest`. By 2026-10-24
    `ubuntu-latest` was Ubuntu 26.04, which has no `libxml2.so.2`, so mise's SwiftLint binary failed to
    load (exit 127) and every PR's `Static checks` went red. Move the pin deliberately, with a green run.
  - *Static checks on Linux.* The `Static checks` job (`ubuntu-24.04`, tools from `mise.toml`) runs
    `check.sh --static-only`: lint, the package graph and pins, the catalog version, and every script
    suite that runs anywhere. Format (step 1) runs in `Check` instead: since the ubuntu-24.04 image of
    2026-10-21, SwiftFormat 0.63.0's Linux binary segfaults at random (exit 139; Pete, 2026-10-26). It has no Xcode, so step 0 checks only the tools. `Check` `needs:` it:
    a red static check skips `Check`, costs no macOS minutes, and the run is red. `Check` runs the
    adversarial suites whose header says `# needs macOS:` (one of their cases needs xcodebuild, xcrun,
    Apple's `/usr/bin` shims or BSD sed): catalog-version-attack, ci-post-clone, coverage-gate,
    string-catalogs, string-catalogs-tester and xcode27.
    `adversarial/run.sh` picks the half from `LEDGER_ADV_SUITES` (`portable`, `macos`; unset runs all).
    SwiftLint's Linux build loads SourceKit from the image's Swift toolchain, where the job points
    `LINUX_SOURCEKIT_LIB_PATH`; without the library SwiftLint 0.65.1 stops with a fatal error, and the
    lint-rules fixtures fail if a rule stops firing. `check-package-graph.sh` runs `swift package
    describe`, so it too needs the image's Swift (6.4; `LedgerKit` asks for 6.2 or later). The full local
    gate, and `--lint-only`, still run everything on the Mac, whatever `LEDGER_ADV_SUITES` the shell exports.
  - *Compilation cache.* `Check` sets `LEDGER_COMPILATION_CACHE=YES`, so `check.sh`'s builds pass
    `COMPILATION_CACHE_ENABLE_CACHING=YES` (Xcode 26+; locally it stays off). Xcode then keeps each Swift
    and Clang compilation's result in `.derivedData/CompilationCache.noindex`, keyed by a hash of the
    compiler, its arguments and every input's contents. Mtimes play no part, so a fresh checkout reuses it,
    and a changed input always compiles. `pr.yml` restores it before `check.sh` and saves it after, on a red
    run too, but not when cancelled. Keys hash `.xcode-version` and both lockfiles, plus the commit;
    `restore-keys` are the key without the commit, so a run starts from its PR's newest cache, or main's.
    The SwiftPM checkout cache stays exact-key (above). Xcode validates the cache once per boot
    (`ValidateCAS`; `builtin/v1.validation` holds the boot time it last did), so a runner validates what
    it restored: a corrupted cache was dropped and filled again there (`recovered from invalid data`),
    while one corrupted after that check, on the same boot, failed the build (notes, "Measured"). The
    keys are taken to hold absolute paths (not tested from a second path); GitHub keeps the checkout at
    `/Users/runner/work/<repo>/<repo>`. Measured on a developer Mac (2026-10-01; notes, "Measured"):
    the iOS `build-for-testing` took 58–59 s with the cache off, 57 s filling an empty cache (1,113 misses)
    and 17–18 s from a full one with nothing else built and every source's mtime moved (1,003–1,018 hits, no
    miss). The cache was 1.0 GB, 343 MB through `tar | zstd`. On the runner (2026-10-08 and -10) a PR's
    second push built in 750 s against 1,221 s cold, and re-runs of the same commit in 452 s and (#59,
    2026-10-17) 760 s against 1,458 s: the driver's planning, linking and signing are not cached, so a warm
    cache about halves the runner's build.
  - *What is main-scoped (2026-10-20; `tasks/chores/2026-10-17-main-cache.md`, `tasks/chores/ci-test-time.md`).* GitHub scopes caches by
    branch: a PR's run reads its own ref's caches and `main`'s, never another PR's, and `pr.yml` never runs
    on `main`. Until 2026-10-20 nothing saved on `main`, so every PR's first run found no cache (`Cache not
    found for input keys: compilation-…`) and built cold: 937–1,458 s for #58–#61, and #59 reached the
    deadline in its tests at a 1,458 s build. `.github/workflows/main-cache.yml` runs on each push to
    `main` that changes more than `docs/`, `tasks/`, `design/` or root-level `*.md` (Scope's allowlist, as
    `paths-ignore`). Its one job, on `xcode-27`, repeats Check's checkout, Xcode, mise, package-cache and
    restore steps field for field (WF69) and runs `scripts/check.sh --build-only`: step 0 and step 3's iOS
    `build-for-testing` through the same code, so the compiler's arguments, and every entry's key, are
    Check's (check-wiring W77); nothing is tested. It saves the compilation cache under Check's key scheme,
    and `actions/cache` saves the package checkouts under their exact key, both in `main`'s scope, after a
    green build only: a cancelled run (a newer push cancels it; `concurrency: main-cache`) or a red one saves
    nothing. A PR's first run therefore restores `main`'s newest cache and compiles only what differs from
    it; its later pushes and re-runs restore its own. Expected first-run build: about 450–760 s on the
    runner, as a PR's warm runs above, against 937–1,458 s cold. Locally `--build-only` took 114 s cold and
    28–34 s warm (cache 1.5 GB, 452 MB through `tar | zstd`). Each save is an entry of about 450 MB; GitHub
    keeps 10 GB per repository and evicts the least recently used, so `main`'s older entries, which no
    restore picks once a newer one exists, go first. Cost: one warm build per code merge, about 10–14 macOS
    minutes. Held back on 2026-10-17 for that cost (chore file, "Cost"); shipped 2026-10-20
    (`tasks/chores/ci-test-time.md`) once the repository was public, where standard runner minutes are free.
    Should it go private again, revisit both this and the deadline below: `main-cache.yml` would bill about
    10–14 macOS minutes per code merge, and the deadline's headroom bills only on a hang (about 12 minutes
    more than at 3,120 s). Run by hand (`workflow_dispatch`) on `main`, it rebuilds a cache that was evicted
    or that a red or cancelled run did not save.
  - *Seeds on the runner (2026-10-09; `tasks/chores/2026-10-09-pr-lane-time.md`).* `Check` sets
    `TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40`. `xcodebuild` hands a `TEST_RUNNER_` variable to the test
    runner without the prefix, and there it replaces the PR plan's `LEDGER_PROPERTY_SEED_COUNT` (200): every
    seeded property runs its first 40 seeds on the runner. No test, test plan or tester's file changed. The
    full local gate (§4) runs the plan's 200, the nightly its 2,000; to run what `Check` runs, export the
    variable before `scripts/check.sh`. Why: the iOS test step took 855–1,497 s there on 2026-10-09 (419 s
    on a developer Mac), tests run one at a time, and the 200-seed cases were about a fifth of it. Expected
    after: 670–940 s on `main`, by each test's measured runner time and its new case count. 20 seeds fail
    one control (`HLCConvergenceAdversarialTests.rawClocks_loseActions`, which looks for a lost action in
    the seeds it is given); 30, 40 and 50 pass. The rest of the step is many small hosted-view and
    text-size cases and the UI tests, which the seed count does not reach (the chore file lists them).
  - *Sweeps on the runner (2026-10-17; `tasks/chores/2026-10-17-pr-sweeps.md`).* `Check` sets
    `TEST_RUNNER_LEDGER_SWEEP=pr`, which the test runner reads as `LEDGER_SWEEP` through one helper,
    `TestSweep` in `LedgerTestSupport`. There a hosted view's sweep over text sizes keeps the smallest,
    `.large`, `.xxxLarge` and `.accessibility5`, plus any size a test names because a finding was seen
    there. The two setting sweeps (`LayoutSetting` in FeatureWorkoutTests, `ViewsSetting` in
    FeatureProgramTests) keep the iPhone 17 plain beside the 375 pt phone with Bold Text and right to left.
    Every reduced list is a subset of the full one. Unset, as in the full local gate (§4), the nightly and
    `swift test`, every sweep runs whole; to run what `Check` runs, export both `TEST_RUNNER_` variables
    before `scripts/check.sh`. Checks over all sizes or settings at once keep their lists: the least room,
    the compact rest panel's switch between its two arrangements (`LayoutSetting.everySetting`), controls.
    A test that reads a swept list's count or positions must take its list whole. Why: on `main` the
    iOS test step took about 1,255–1,293 s on a developer Mac at the plan's seeds, so a PR's first run (cold
    build) reached the deadline whatever its code; the sweeps were the largest part. Measured on the Mac
    with 40 seeds: 903 s with every sweep, 595 s under `pr` (FeatureProgramTests 374 → 205 s of cases,
    FeatureWorkoutTests 185 → 66 s). The rest is the UI smoke (65 s), launches, the seeded suites and
    single-case hosted tests, which no sweep reaches. On 2026-10-20 (`tasks/chores/ci-test-time.md`) six suites added
    since, which swept every size or setting, ask through `TestSweep` too: NameFieldLine (and its Room and
    Round 2 files), FieldFont, the receipt's layout and LOGGED cut, the "End workout?" sheet's adversarial
    suite, and the seed names of the F11 S10 name field. A check pinned to a size where a measure stands
    nearest its bound names that size (`also:`). On 2026-10-21 (`tasks/chores/ci-test-time-2.md`) four more:
    the name field's tails, the week chip's room and the long tag's strip, the Day editor's pinned bar and
    the rows under it, and the rest panel's room; and `PixelBuffer` draws straight into its pixels' storage
    (the per-pixel copy cost as much as a drawing unoptimized). The PR plan's cases on a developer Mac: 931 →
    801 s, a floor taken on a loaded host (196 s saved where faster).
  - *Shards (2026-11-11; `tasks/features/F15-ios-ui-tests.md`, plan amendments §2.4 a and Q10).* One
    `Check` job had reached its deadline (#88), and #91 took 72 min, its re-run's tests 2,251 of 3,128 s. `Check` is now a matrix of
    two jobs (`fail-fast: false`), each on `xcode-27` with the same checkout, Xcode, mise, package cache and
    compilation-cache restore as before. Each runs `check.sh --ios-only --skip-static --shard <n>/2`: steps
    0–2 as before, the same iOS build (`--build-only`'s arguments, its result bundle's name aside, so both
    shards and `main-cache.yml` share cache keys; check-wiring W84), then the tests of the targets `scripts/pr-shards.txt` gives shard
    `<n>`, the other shard's passed to `xcodebuild` as `-skip-testing`. `check-test-results.sh` then checks
    that the bundle ran exactly those targets and they passed; step 5 is skipped. Each green shard packs
    its bundle into one tar (download-artifact failed to extract a bundle's ~35,000 files on the macOS runner)
    and uploads it as the artifact `PR-iOS-shard<n>` (overwritten by a re-run, since "Re-run failed jobs" does
    not re-run a green shard); a red one uploads `results-<run>-<attempt>-shard<n>` as before. Only shard 1
    saves the compilation cache: both build the same thing under one key. `Coverage` (`xcode-27`, 15 min)
    needs both shards, selects and checks the Xcode as `check.sh` step 0 does, downloads both tars, unpacks them
    where `check.sh` wrote the bundles and runs `scripts/check-shards.sh`: each bundle against its shard's targets, the shards' targets together
    against the PR plan (every enabled target once), then `coverage-gate.sh --ios-only` over both bundles,
    at the same thresholds. `gh pr checks` lists `Scope`,
    `Static checks`, `Check (shard 1/2)`, `Check (shard 2/2)` and `Coverage`.
    - *The split.* By each target's wall time on the runner, the "Launch <target>" sections of the action
      log (`xcrun xcresulttool get log --type action`), in the only two full bundles kept (#91's first
      attempt and #88's, failure uploads): shard 1 is FeatureProgramTests, LedgerPersistenceTests,
      LedgerDesignTests and LedgerDomainTests, 1,280 / 1,298 s; shard 2 the other 13 targets, 1,270 / 1,033
      s. FeatureTodayTests moved to shard 1 on 2026-11-12 (see "Deadline"). Per shard, then: about 165 s of format and script tests, the build (452–1,630 s), and 1,300 s of
      tests, about 2,000 s warm against one job's 3,128 s. When one shard's tests run clearly longer, move
      a target in `scripts/pr-shards.txt` by a newer bundle's times. A target added to the PR plan fails
      `pr-shards.adv.sh` until it is placed in a shard.
    - *Coverage.* In one run every test target's copy of a source file reports the same covered lines,
      those any test of the run executed (#91's report: 109 files measured in several targets, every one
      identical), so the unsharded gate counts the union of all tests. A shard's bundle counts its own
      shard's, and `coverage-gate.sh` keeps each file's best measurement over both bundles: never more
      covered than one run would count, so the gate is at least as strict, never weaker. A union was tried
      and dropped: `xcrun xcresulttool merge` keeps only the first bundle's coverage (`xccov` then cannot
      read the merged report), and `xcrun xccov merge` of #91's report with itself moved modules both ways
      (LedgerDomain 99.36 → 99.96 %, FeatureLibrary 96.98 → 96.48 %), so it is no union of the same
      measure. Measured on a developer Mac (2026-11-11, plan seeds and full sweeps): both shards green on
      their own (shard 1 tested for 785 s, shard 2 for 907 s), and `check-shards.sh` over them gated
      98.41 % overall against the unsharded full gate's 98.44 % on the same Mac: 10 covered lines fewer,
      in four modules (at most 0.12 points), none more, as the gate's rule says.
    - *Cost.* Two macOS test jobs and a short Coverage job per PR: free while the repository is public; if
      it goes private again, about 1.3 times today's minutes for about half the wall time.
  - *Deadline (2026-11-12).* `LEDGER_XCODEBUILD_DEADLINE` is 4,500 s per shard; the step's timeout is 77
    min, 2 min after the deadline, and the job's 82. The first day's 3,600 s (step 62, job 67) stopped
    shard 2 of #94's second run in its tests after a 1,864 s build with the compilation cache restored;
    the run before built the same tree in 496 and 1,090 s. A shard's worst is then that build, 165 s of
    format and script tests, 12 s of catalogs and boot and a slow runner's ~1,600 s of tests, about
    3,640 s; 4,500 s leaves about 860 s. A green run still takes about 35 minutes. FeatureTodayTests moved
    to shard 1 the same day: shard 2 had tested for 1,303 s against shard 1's 928 s.
  - *Deadline until 2026-11-11 (one Check job).* `LEDGER_XCODEBUILD_DEADLINE` was 4,500 s; the step's
    timeout 77 min, 2 min after the deadline, and the job's 82. #72 (F12 S2) restored its compilation
    cache and still built for 1,062 s, then 1,630 s on a re-run (646–920 s on the four PRs before it), and
    the re-run was stopped at 3,840 s in its tests. The runner's worst seen, 1,630 s of build, 150 s of script tests and #67's 2,402 s of
    tests, is about 4,180 s; the deadline is 5 min past that. Minutes are free while the repository is public.
  - *Deadline until 2026-10-26 (`tasks/chores/ci-test-time.md`).* 3,840 s; the
    step's timeout was 66 min, 2 min after the deadline, and the job's 71. On 2026-10-19 and -20 both PRs'
    first runs (#65, #66) restored nothing, built cold (865 and 1,424 s, after 96 and 150 s of script tests)
    and were stopped by the 3,120 s deadline in their tests; their re-runs built warm (441 and 758 s) and
    tested for 2,099 and 2,210 s (2,635 and 3,124 s in all). Since then a first run restores `main`'s cache
    ("What is main-scoped", above), and the sweeps of six more suites keep their representatives
    ("Sweeps on the runner"): 297 s of their cases on a developer Mac become 170 s, which at the runner's 2.0
    to 3.0 times saves about 250–380 s there, so the tests are about 1,960 s at most. A warm first run is then
    about 150 + 758 + 1,960, near 2,870 s (48 min); the deadline also covers a cold one, for a PR whose
    lockfiles or Xcode no cache matches: 1,424 + 150 + 1,960 is about 3,534 s, plus 5 min, set to 3,840 s.
    Standard minutes are free on this public repository (2026-10-20), so headroom costs nothing until
    something hangs; if it goes private again, a hang bills about 12 minutes more than at 3,120 s (revisit,
    with `main-cache.yml`'s cost above). On 2026-10-21 (#67, F08 added) the runner tested for 2,407 s
    warm; the cuts of `tasks/chores/ci-test-time-2.md` (129–197 s on the Mac, 2.4–2.6 times on the runner)
    bring that to about 1,900–2,100 s, so a cold first run is about 150 + 1,450 + 2,100 = 3,700 s at worst,
    140–340 s inside the deadline: not yet room for a large feature's tests (that file lists the next
    levers). Earlier: 2,400 s until 2026-10-09, 2,520 s until 2026-10-17 and 3,120 s until
    2026-10-20, each sized for a cold build and stopped by the tests' growth (`tasks/chores/2026-10-17-pr-sweeps.md`).
  - *arm64 only (2026-10-18; `tasks/chores/2026-10-18-arm64-only.md`).* Every `xcodebuild` in `check.sh`
    passes `ARCHS=arm64`, on both lanes and on the build and the test run alike (check-wiring W76). The
    iOS build also builds the embedded watch app, and the active-arch rule covers only the destination's
    platform, so its 16 watch-simulator modules were built for x86_64 as well. Measured on a developer Mac,
    cache on: 546 → 422 compile tasks, 75 → 59 modules, 81 → 63 links; compile task time 824–945 → 706–805
    s; wall 116–142 → 107–114 s cold, 29–57 → 23–28 s warm; the cache 1.5 → 1.25 GB. Every simulator here
    is Apple silicon (the `xcode-27` image is arm64); an Intel Mac could no longer run the gate. The
    nightly built both until 2026-11-12; its legs now run `check.sh` too ("Nightly legs").
  - *Nightly legs (2026-11-12).* The first nightly on the runner
    (run 43144335050, `main` 71533ae) left nothing: its one iOS job reached the job's 120 min while testing,
    which also skipped the upload, and its one watch job lost its runner at 61 min ("The hosted runner lost
    communication with the server"), with no log. `nightly.yml`'s `test` job is now a matrix of legs
    (`fail-fast: false`), each running `check.sh --nightly --<ios|watch>-only --skip-lint --shard <n>/<count>`:
    step 0 (the Xcode against `.xcode-version`, the tools), that platform's build, boot and the leg's tests,
    then `check-test-results.sh` over the leg's targets, as a PR shard; no format, lint or coverage gate.
    `--nightly` makes steps 3 and 4 test the Nightly plans (bundles `Nightly-iOS…`, `Nightly-watchOS…`, a test
    without its own allowance 600 s, the plans' maximum, against the PR plans' 60) and skips step 5;
    `--watch-only` is `--ios-only`'s other half. `--shard` reads the tested plan's file,
    `scripts/<plan, lowercase>-shards.txt`: `nightly-shards.txt` (four iOS legs) and `nightly-watch-shards.txt`
    (two). `pr-shards.adv.sh` holds every shards file to its plan (every enabled target in exactly one leg),
    and `workflows.adv.sh` the matrix to the files (WF76). The leg's own bundles and snapshot diffs are packed
    into one tar and uploaded as `nightly-<platform>-leg<n>-<run>-<attempt>` on a red or interrupted leg too
    (`!cancelled()`). The report job still needs `test`, so any red leg opens or comments on the issue.
    - *The legs.* By each target's local test time on a developer Mac (seconds; the action log's "Launch
      <target>" sections, 2026-11-11 and -12; ~ an estimate), aiming at 50–60 min of a runner's tests at the
      1.3–1.5 times the Mac's time assumed: iOS leg 1 FeatureWorkoutTests (~3,150); leg 2 LedgerUITests (~92
      tests, ~2,760) and the four small targets (under 40); leg 3 LedgerPersistenceTests (1,481),
      LedgerDesignTests (87), FeatureOnboardingTests (70) and FeatureTodayTests (42), about 1,680; leg 4
      FeatureProgramTests (861), LedgerDomainTests (369), LedgerSyncTests (370) and four Feature and app-kit
      targets (97), 1,697 (measured: `check.sh --nightly --ios-only --skip-lint --shard 4/4` with Domain in leg 3
      tested its other six targets in 1,375 s, green). Legs 1 and 2 are each one target larger than the aim: a runner tests them
      in about 70–80 min. Splitting one needs suites in the leg lists (`-only-testing:<target>/<suite>`), the
      next lever if the runner's times confirm it. watchOS leg 1 is LedgerPersistenceTests, leg 2 the plan's
      other seven targets. Rebalance from a nightly's bundles (its "Launch" times) when one leg tests clearly
      longer than the rest.
    - *The watch job's lost runner.* No cause was found in the code. The watch plan runs the same seeded
      targets as iOS at 2,000 seeds, plus the nightly-only `.performance` and `.slow` suites (20,000-set
      databases in files under the temporary directory); nothing in them grows without bound, and the tests run
      one at a time. The one job had about 2,300 s of iOS-equivalent tests and lost the runner after about
      an hour. So the watch plan is split in two, which halves each runner's test time and, if a leg loses its
      runner again, names the half; each leg now has the deadline and the tar upload, so a leg that stops any
      other way leaves its bundle.
    - *Deadline.* `LEDGER_XCODEBUILD_DEADLINE` is 7,800 s in every leg; the step's timeout is 132 min, 2 min
      after it, and the job's 145, for checkout, Xcode, mise and the tar and upload. The largest leg tests
      for about 4,100–4,700 s at 1.3–1.5 times the Mac's 3,150 s, after the runner's slowest build seen
      (1,864 s, #94) and about 100 s of tools, catalogs and boot: about 6,100–6,700 s, which leaves
      1,100–1,700 s. The nightly restores no compilation cache, so each leg builds cold (937–1,458 s in the
      PR runs above). Minutes are free while the repository is public.
- **PR CI runs iOS only (Pete, 2026-09-30).** `Check` runs `scripts/check.sh --ios-only` (with
  `--skip-static` since the split above; step 2 then runs in `Static checks`, and `--shard` since
  2026-11-11; step 5 then runs in `Coverage`): steps 0–3 and 5, no watchOS step, and the coverage gate
  reads iOS bundles alone. Why: F32's first `xcode-27`
  run (36652681235) passed lint, the script tests and all 17 iOS test targets, then reached
  `LEDGER_XCODEBUILD_DEADLINE` (1,500 s) in the watchOS tests and stopped, exit 75, as designed. Its iOS
  build took 684 s, including a cold package resolve. watchOS is still tested before every merge by
  the full local `check.sh` (§4), which runs both platforms, and by the manual nightly. A required
  module that only a watch bundle can measure is listed in `watchOnly` in
  `scripts/coverage-thresholds.json` (none today). Only `--ios-only` excuses it, and only while no
  bundle measures it.
- **String catalogs (F09).** Step 3 of `check.sh` runs `scripts/check-string-catalogs.sh` right after the
  iOS build and before the iOS tests, in every mode that builds iOS: `Check` (`--ios-only --skip-static`)
  runs it, and so does the full local gate. The watch build is never read. During the build the compiler
  writes the keys it extracted from each source file (`.stringsdata`, under `.derivedData`). The script
  compares each `LedgerKit/Sources/<Module>/Resources/Localizable.xcstrings` with its module's keys: the
  catalog must hold exactly those keys, byte for byte, and read as `xcrun xcstringstool sync` would write
  it. A red step names each lookup that is not in a copy file, each key the copy files look up that the
  catalog lacks and each catalog key no code looks up, or shows a diff against the tool's output. The
  author corrects the catalog, or the lookup, and pushes again. A catalog with no `.stringsdata` to compare with fails as well, so a build folder
  laid out differently cannot pass unnoticed; a catalog in a watch module fails the same way, since `Check`
  builds no watch target (they get catalogs with F18). A record run (`--record-snapshots`) stops at a failing
  catalog before it records. A build served from the compilation cache writes the files too: a cache hit
  replays a compile's `.stringsdata` with its other outputs (`Using CAS output localization-strings` in
  the build log). Measured on a developer Mac on 2026-10-04 with `COMPILATION_CACHE_ENABLE_CACHING=YES`:
  one module's object folder was moved aside, the next build replayed every one of its compiles from the
  cache, and the step passed on the files it wrote. Not yet seen: the runner itself, with a cache that
  another run saved.
- §5: scripts run from `ci_scripts/` (use `$CI_PRIMARY_REPOSITORY_PATH`); external TestFlight
  needs a clean build; App Review submission is manual. §6: `bootstrap-sha` skips pre-F01 history.

## 1. Flow

```
feature branch ──PR──▶ GitHub Actions: Lint ─▶ Check (iOS + watchOS tests, coverage, snapshots)
                          │ required checks + review + adversarial test + human approval
                          ▼
                        main ──push──▶ Xcode Cloud "Beta": archive iOS (+ watch) ─▶ TestFlight internal
                          │
                release-please PR (version bump + CHANGELOG) ──merge──▶ tag vX.Y.Z
                          │
                        tag v* ──▶ Xcode Cloud "Release": archive ─▶ TestFlight external ─▶ App Store (manual release)
nightly 09:00 UTC ──▶ GitHub Actions: full UI suites, performance tests, dependency report
```

Two systems, one build definition: both read `.xcode-version` (27.0), the
same `Config/*.xcconfig`, and run the same `xcodebuild` invocations.

## 2. `.github/workflows/pr.yml`

Two jobs. `Lint` fails in ~2 min; `Check` runs `scripts/check.sh` exactly as
a developer would. Both are required checks.

```yaml
name: PR
on:
  pull_request:
    branches: [main]
  merge_group:
concurrency:
  group: pr-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
  checks: write
  pull-requests: write
env:
  XCODE_VERSION: "26.6"            # keep in sync with .xcode-version; verify in F01 that the image exposes /Applications/Xcode_26.6.app
jobs:
  lint:
    name: Lint
    runs-on: macos-26
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
      - uses: jdx/mise-action@v3            # installs swiftlint/swiftformat/lefthook/xcbeautify pinned in mise.toml
      - run: mise x -- swiftformat --lint --swift-version 6.3 LedgerKit Apps
      - run: mise x -- swiftlint lint --strict --quiet --reporter github-actions-logging
      - run: scripts/check-package-graph.sh
  check:
    name: Check (iOS + watchOS)
    runs-on: macos-26
    timeout-minutes: 75
    needs: lint
    steps:
      - uses: actions/checkout@v5
      - uses: jdx/mise-action@v3
      - name: Select Xcode
        run: |
          sudo xcode-select -s "/Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer"
          xcodebuild -version
          xcrun simctl list runtimes | grep -E "iOS 26|watchOS 26"
      - name: Cache SPM checkouts
        uses: actions/cache@v4
        with:
          path: .derivedData/SourcePackages
          key: spm-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-${{ hashFiles('LedgerKit/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-
      - name: Cache DerivedData (build products only)
        uses: actions/cache@v4
        with:
          path: |
            .derivedData/Build
            .derivedData/ModuleCache.noindex
          key: dd-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-${{ github.ref_name }}-${{ github.sha }}
          restore-keys: |
            dd-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-${{ github.ref_name }}-
            dd-${{ runner.os }}-xcode${{ env.XCODE_VERSION }}-main-
      - name: Build and test (check.sh, lint already done)
        env:
          XCBEAUTIFY_RENDERER: github-actions
        run: scripts/check.sh --skip-lint
      - name: Coverage gate
        if: always()
        run: scripts/coverage-gate.sh .derivedData/Results/PR-iOS.xcresult .derivedData/Results/PR-watchOS.xcresult | tee coverage-summary.md
      - name: Publish coverage summary
        if: always()
        run: cat coverage-summary.md >> "$GITHUB_STEP_SUMMARY"
      - name: Upload result bundles and snapshot diffs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: results-${{ github.run_id }}
          path: |
            .derivedData/Results/*.xcresult
            .derivedData/SnapshotArtifacts
          retention-days: 7
          if-no-files-found: ignore
```


`scripts/coverage-gate.sh` (written in F01): runs
`xcrun xccov view --report --json <xcresult>` for each bundle, merges by
target, and fails when any threshold in `docs/testing-strategy.md` §4 is
missed (Domain ≥ 95, Persistence ≥ 90, Sync ≥ 90, Features ≥ 70, overall ≥ 80).
It prints a Markdown table (target, lines covered, %, threshold, ✓/✗).

## 3. `.github/workflows/nightly.yml`

```yaml
name: Nightly
on:
  schedule: [{ cron: "0 9 * * *" }]   # 09:00 UTC ≈ 04:00 Chicago
  workflow_dispatch:
permissions: { contents: read }
env: { XCODE_VERSION: "26.6" }
jobs:
  full:
    runs-on: macos-26
    timeout-minutes: 180
    strategy:
      fail-fast: false
      matrix:
        include:
          - { scheme: Ledger,      plan: Nightly,       dest: "platform=iOS Simulator,name=iPhone 17,OS=26.5" }
          - { scheme: LedgerWatch, plan: Nightly-Watch, dest: "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5" }
    steps:
      - uses: actions/checkout@v5
      - uses: jdx/mise-action@v3
      - run: sudo xcode-select -s "/Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer"
      - run: |
          xcodebuild test -project Ledger.xcodeproj -scheme ${{ matrix.scheme }} -testPlan ${{ matrix.plan }} \
            -destination '${{ matrix.dest }}' -derivedDataPath .derivedData \
            -clonedSourcePackagesDirPath .derivedData/SourcePackages \
            -resultBundlePath .derivedData/Results/${{ matrix.plan }}.xcresult \
            -parallel-testing-enabled YES -quiet | mise x -- xcbeautify --renderer github-actions
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: nightly-${{ matrix.plan }}-${{ github.run_id }}, path: .derivedData/Results, retention-days: 14 }
  dependencies:
    runs-on: macos-26
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v5
      - run: swift package --package-path LedgerKit show-dependencies --format json > deps.json
      - run: swift package --package-path LedgerKit update --dry-run | tee outdated.txt   # report only; bumps are deliberate PRs
      - uses: actions/upload-artifact@v4
        with: { name: dependency-report-${{ github.run_id }}, path: "deps.json\noutdated.txt" }
```

Nightly failures open a GitHub issue via the workflow's `if: failure()`
step (`gh issue create --label nightly`) — add in F01.

## 4. No branch protection (Pete, 2026-09-27)

GitHub Free, public since 2026-10-20, with no protection rule: nothing blocks a direct push or a red merge. G5 merges only when the
full local `scripts/check.sh` is green on the merge candidate and CI is green whenever it ran. Since
2026-09-30 CI tests iOS only, so that full local run is a PR's only watchOS gate.
A skipped `Check` counts only when Scope's log says `code=false` (the docs-only notice). When the free
minutes run out, CI does not run and the local gate output is the G4 evidence. Seeding the package
cache on `main` costs a full Check: only if first runs show slow resolution. A red `Static checks` skips
`Check`; that run is red, not docs-only. Revisit with Pro or a 2nd maintainer.

## 5. Xcode Cloud

Workflows are configured in Xcode ▸ Product ▸ Xcode Cloud (human, F01), then
exported to `docs/xcode-cloud/*.md` as screenshots/notes.

| Workflow | Start condition | Actions | Post-actions |
|---|---|---|---|
| **Beta** | Branch changes on `main` | Archive `Ledger` (iOS, watch app embedded automatically) — Release config | TestFlight Internal Testing → group "Ledger Team" |
| **Release** | Tag changes matching `v*` | Archive `Ledger` — Release config | TestFlight External Testing → group "Beta"; App Store Connect submission with **manual release** |
| **PR sanity** (optional, off by default) | Pull request to `main` | Build only | none — GitHub Actions is the PR gate |

- Signing: cloud-managed (Xcode Cloud creates and rotates certificates). No signing assets anywhere else.
- Environment: Xcode 27.0 selected explicitly in the workflow, matching `.xcode-version` (F32; not *Latest Release*).
- Build number: `CURRENT_PROJECT_VERSION` = `CI_BUILD_NUMBER`, injected by `ci_scripts/ci_post_clone.sh`:

```bash
#!/bin/sh
set -eu
# Xcode Cloud runs this after clone, before resolving packages.
echo "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}" >> Config/Base.xcconfig
# Fonts and packages are in-repo; nothing to install. Simulators are only needed for the optional PR workflow:
if [ "${CI_XCODEBUILD_ACTION:-}" = "test-without-building" ] || [ "${CI_XCODEBUILD_ACTION:-}" = "test" ]; then
  xcodebuild -downloadPlatform iOS -quiet || true
fi
```

- The watch app is archived and uploaded with the iOS app because it is an
  embedded watchOS app target of `Ledger` (ADR-003 project layout); no separate workflow.

## 6. release-please

`release-please-config.json`:
```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "include-component-in-tag": false,
  "tag-separator": "",
  "bump-minor-pre-major": true,
  "changelog-sections": [
    { "type": "feat", "section": "Features" },
    { "type": "fix", "section": "Fixes" },
    { "type": "perf", "section": "Performance" },
    { "type": "chore", "section": "Maintenance", "hidden": true }
  ],
  "packages": {
    ".": { "extra-files": [ { "type": "generic", "path": "Config/Base.xcconfig" } ] }
  }
}
```
`.release-please-manifest.json`: `{ ".": "0.1.0" }`.
`Config/Base.xcconfig` carries `MARKETING_VERSION = 0.1.0 // x-release-please-version`
so the release PR bumps it. Workflow `.github/workflows/release-please.yml`
runs `googleapis/release-please-action@v4` on push to `main` (needs
`contents: write`, `pull-requests: write`). Merging the release PR creates
tag `vX.Y.Z` → Xcode Cloud "Release".

Commit types → bumps (pre-1.0): `feat` → minor, `fix`/`perf` → patch, `feat!`
or `BREAKING CHANGE:` → minor until 1.0, then major.

## 7. Versioning, TestFlight, hotfixes

- Marketing version `MAJOR.MINOR.PATCH`; build number = Xcode Cloud build number (monotonic across workflows).
- TestFlight: internal builds appear within minutes of a `main` merge. The **first** external build needs Beta App Review (~1–2 days); later builds usually auto-pass. Builds expire after 90 days. Limits: 100 internal, 10 000 external testers; at most 6 submissions per 24 h (R3 §6).
- Hotfix: `git checkout -b hotfix/vX.Y.Z+1 vX.Y.Z` → cherry-pick → PR into `main` (normal gates) → release-please cuts the patch tag → "Release" workflow. If `main` already contains unreleased work that must not ship, tag the hotfix branch head directly (`vX.Y.Z+1`) after CI passes on it; document in the release log.
- Rollback: App Store — "Remove from sale" is never used; instead expedite a patch. TestFlight — expire the bad build in App Store Connect.

## 8. Secrets and permissions

| Where | What |
|---|---|
| GitHub | nothing signing-related. `GITHUB_TOKEN` least-privilege per job (`contents: read`; release-please writes; the nightly report writes issues). |
| Xcode Cloud | cloud-managed certificates/profiles; App Store Connect access via the team's Xcode Cloud role. |
| Developer Macs | Xcode automatic signing for local device runs only. |

No `.p8`, `.p12`, `.mobileprovision` in the repo (gitignored) or in GitHub secrets.

## 9. Cost and runtime (from R3 §4)

| Item | Estimate |
|---|---|
| `Lint` job | ~2 min |
| `Check` job | ~15 min warm cache, ~25 min cold |
| macOS rate | $0.062/min; included minutes count 10× |
| Per PR run | ≈ 20–27 macOS minutes ≈ $1.25–1.70 |
| 40 PR runs + 30 nightlies / month | ≈ 800 + 900 minutes ≈ $105/month before included minutes |
| Xcode Cloud | 25 free hours/month; a Beta archive ≈ 15–20 min → ~60 builds/month free |

Levers if cost matters: run `Check` only when Swift/config files change
(`paths:` filter), nightly on weekdays only.

## 10. Local parity

`scripts/bootstrap.sh` contract (F00):
1. `brew install mise` if missing; `mise install` (pins in `mise.toml`: swiftlint 0.65.x, swiftformat 0.63.x, lefthook 2.1.x, xcbeautify).
2. `xcodebuild -version` must match `.xcode-version`, 27.0 (else print the `.xcode-version` hint and exit 1).
   `scripts/check-xcode-version.sh` does it, for `bootstrap.sh` and for `check.sh` step 0 in every mode.
3. `xcodebuild -downloadPlatform iOS` and `-downloadPlatform watchOS` if the 27.0 runtimes are missing.
4. `mise x -- lefthook install`.
5. `scripts/check.sh --fast` as a smoke.

`lefthook.yml`:
```yaml
pre-commit:
  parallel: true
  commands:
    swiftformat:
      glob: "*.swift"
      run: mise x -- swiftformat --lint --swift-version 6.3 {staged_files}
    swiftlint:
      glob: "*.swift"
      run: mise x -- swiftlint lint --strict --quiet {staged_files}
commit-msg:
  commands:
    conventional:
      run: grep -Eq '^(feat|fix|perf|refactor|test|docs|chore|ci|build)(\([a-z0-9-]+\))?!?: .{1,72}' {1} || (echo "commit message must follow Conventional Commits" && exit 1)
```
