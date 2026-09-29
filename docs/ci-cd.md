# Ledger — CI/CD

Decision: ADR-006. Evidence: `docs/research/R3-tooling-ci.md` (2026-09-16).
Local parity: `docs/testing-strategy.md` §7 (`scripts/check.sh`) and §8 (test plans).

**Verified 2026-09-27 (F01), runner updated 2026-09-29 (F32).** `.github/`, `ci_scripts/` and `scripts/` are
authoritative; the plan differs:
- **Xcode 27 (Pete, 2026-09-29, F32).** Every macOS job runs on `xcode-27` (arm64), a **public preview**
  image (actions/runner-images#14404): macOS 27.0, Xcode 27.0 (27A266a) at `/Applications/Xcode_27.app`,
  linked as `Xcode_27.0.app`, and iPhone 17 and Apple Watch Series 12 (46mm) on 27.0 (no Series 11). The
  standard `macos-26` image has only Xcode 26.x. Fallback if the preview breaks: `macos-26` with
  `.xcode-version` 26.6 and the 26.5 destinations (iPhone 17, Series 11 (46mm)). `.github/actionlint.yaml`
  names the label, which actionlint 1.7.12 does not know yet.
- Xcode from `.xcode-version`, and `check.sh` step 0 fails on any other Xcode (as `bootstrap.sh` does);
  SHA-pinned actions; `$(PROJECT_DIR)` expands in test plans. Simulators by UDID (`sim-destination.sh`).
- **Package pins (F32).** Every `xcodebuild` in `check.sh` and the nightly passes
  `-onlyUsePackageVersionsFromResolvedFile`, and `--fast` passes `--only-use-versions-from-resolved-file`,
  so a stale `Package.resolved` fails instead of being rewritten. Both tools trust existing checkouts, so
  only a cold package directory proves it: the PR cache restores on an exact key only (no `restore-keys`).
  Verify a PR that changes pins after `rm -rf .derivedData/SourcePackages`.
- Test runs pass `-collect-test-diagnostics never`: on a failure Xcode 27 runs `simctl diagnose`, which
  timed out after 600 s per platform (F32). The result bundle keeps the failures, logs and attachments.
- **Free minutes (Pete, 2026-09-27).** `pr.yml` is one macOS job, `Check` (all of `check.sh`),
  behind a Linux `Scope` job that skips it when only files under `docs/`, `tasks/` or `design/`,
  or `*.md` at the repository root, change (renames count at both paths). Nightly is manual;
  release-please runs on Linux, and CI never runs on its release PR. §4: no protection.
  §9 is superseded: a code PR costs about 13–18 macOS minutes, so ~200 cover 11–15 runs.
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
full local `scripts/check.sh` is green on the merge candidate and CI is green whenever it ran.
A skipped `Check` counts only when Scope's log says `code=false` (the docs-only notice). When the free
minutes run out, CI does not run and the local gate output is the G4 evidence. Seeding the package
cache on `main` costs a full Check: only if first runs show slow resolution. Revisit with Pro or a 2nd maintainer.

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
