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
- **Free minutes (Pete, 2026-09-27); paid since 2026-09-30, with a $60 monthly limit.** `pr.yml` has one
  macOS job, `Check` (`check.sh --ios-only --skip-static`). It runs after two Linux jobs: `Scope` skips
  both later jobs when only files under `docs/`, `tasks/` or `design/`, or `*.md` at the repository root,
  change (renames count at both paths). `Static checks` comes next (below). Nightly is manual;
  release-please runs on Linux, and CI never runs on its release PR. §4: no protection.
  §9 is superseded: before the changes below, a green `Check` job took 846–1,302 s (15–22 billed
  minutes) over the six green iOS-only runs to 2026-10-01, 805–1,262 s of it in `check.sh`. The notes
  under "CI efficiency" say what is measured after them, and what only CI can measure.
- **CI efficiency (2026-09-30; `tasks/features/F01-ci-gates/ci-efficiency-notes.md`).**
  - *Static checks on Linux.* The `Static checks` job (`ubuntu-latest`, tools from `mise.toml`) runs
    `check.sh --static-only`: format, lint, the package graph and pins, the catalog version, and every
    script suite that runs anywhere. It has no Xcode, so step 0 checks only the tools. `Check` `needs:` it:
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
    `/Users/runner/work/<repo>/<repo>`. A PR's first run has nothing to restore, since no job saves on
    `main`; its later pushes and re-runs do. Measured on a developer Mac (2026-10-01; notes, "Measured"):
    the iOS `build-for-testing` took 58–59 s with the cache off, 57 s filling an empty cache (1,113 misses)
    and 17–18 s from a full one with nothing else built and every source's mtime moved (1,003–1,018 hits, no
    miss). The cache was 1.0 GB, 343 MB through `tar | zstd`. The runner's figures are not known until a
    PR's second run there.
  - *No `main` warm-up job.* One would cost about as much per merge as it saves on each PR's first run
    (notes). Revisit if most PRs get one run only.
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
    `.large`, `.xxxLarge` and the largest of its list (and its own ends), and the two setting sweeps
    (`LayoutSetting` in FeatureWorkoutTests, `ViewsSetting` in FeatureProgramTests) keep the iPhone 17 plain
    beside the 375 pt phone with Bold Text and right to left. Every reduced list is a subset of the full one.
    Unset, as in the full local gate (§4), the nightly and `swift test`, every sweep runs whole; to run what
    `Check` runs, export both `TEST_RUNNER_` variables before `scripts/check.sh`. Checks over all sizes at
    once (the least room, a switch between arrangements, a control) keep their lists. Why: on `main` the
    iOS test step took about 1,255–1,293 s on a developer Mac at the plan's seeds, so a PR's first run (cold
    build) reached the deadline whatever its code; the sweeps were the largest part. Measured on the Mac
    with 40 seeds: 903 s with every sweep, 576 s under `pr` (FeatureProgramTests 374 → 196 s of cases,
    FeatureWorkoutTests 185 → 64 s). The rest is the UI smoke (65 s), launches, the seeded suites and
    single-case hosted tests, which no sweep reaches.
  - *Deadline (2026-10-17; `tasks/chores/2026-10-17-pr-sweeps.md`).* `LEDGER_XCODEBUILD_DEADLINE` is
    3,120 s; the step's timeout is 54 min, 2 min after the deadline, and the job's 59. A PR's first run
    restores no compiled output and built in 1,140–1,221 s on 2026-10-08 and -09, after about 125 s of
    script tests. Under both runner variables the tests take 576 s on a developer Mac. The runner took 2.0
    to 3.2 times the Mac's time for the same commits on 2026-10-09 (3.6 for #49, whose suites the Mac run
    lacked), so the deadline is sized for 2.5×: 1,221 + 125 + 1,440 s of tests is about 2,786 s, and 5 min
    more is 3,120 s. A run stopped by the deadline costs its minutes and a re-run's; a green run bills
    only what it uses, so headroom costs nothing until something hangs (then 10 more paid minutes than at
    2,520 s). The deadline was 2,400 s until 2026-10-09 and 2,520 s until 2026-10-17; at 2,400 s two first
    runs of 2026-10-09 were interrupted in their tests with no test failing (builds of 1,140 and 1,145 s;
    the tests then needed 855 s and 1,497 s on the re-runs).
- **PR CI runs iOS only (Pete, 2026-09-30).** `Check` runs `scripts/check.sh --ios-only` (with
  `--skip-static` since the split above; steps 1–2 then run in `Static checks`): steps 0–3
  and 5, no watchOS step, and the coverage gate reads the iOS bundle alone. Why: F32's first `xcode-27`
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

GitHub Free, private: nothing blocks a direct push or a red merge. G5 merges only when the
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
