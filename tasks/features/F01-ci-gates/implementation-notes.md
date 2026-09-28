# F01 implementation notes

Base: `main` 8404d02. Implementer pass on 2026-09-27. Nothing is committed or pushed. No GitHub or App Store Connect setting was changed.

## Decisions

1. **`check.sh` remains the only definition of the gate.** `Lint` runs `check.sh --lint-only`
   and `Check` runs `check.sh --skip-lint`. `check.sh` changed in three places, although it
   is outside Touches:
   - On GitHub Actions it passes SwiftLint `--reporter github-actions-logging` and SwiftFormat
     `--reporter github-actions-log` (criterion 2). Neither tool detects Actions on its own
     (verified). `beautify` now keys on `GITHUB_ACTIONS` too, for consistency.
   - Step 2 runs `scripts/tests/*.test.sh`, as the brief's test plan asks.
   - Step 5 always calls the coverage gate. The `coverage gate: F01` fallback is gone.
2. **Coverage gate.** A module is its folder under `LedgerKit/Sources/<Module>/`, because
   coverage is plan-wide (F00 #17). When a file is measured more than once, its best
   measurement is kept. Percentages are floored to 2 decimals, so a value never rounds up
   past a threshold. Thresholds live in `scripts/coverage-thresholds.json` (strategy §4),
   and `Feature*` is written as a pattern.
   - *Excluded:* `LedgerTestSupport`; `LedgerSnapshotTesting`, which is test-only like
     TestSupport; the umbrella modules `LedgerAppKit` and `LedgerWatchAppKit`;
     `*+Previews.swift`; and `*/Generated/*`.
   - *Missing thresholds fail.* A module that has lines but no threshold fails the gate.
     **`LedgerDependencies` has none on purpose**, since strategy §4 is silent on it. F07
     must pick one (or exclude it as wiring) when it adds code there.
3. **Docs-only PRs** skip `Check` through a job-level `if`, and a skipped job counts as passed.
   A workflow-level `paths:` filter would leave the required check pending forever.
4. **The release PR's checks.** A PR pushed with `GITHUB_TOKEN` starts no workflow.
   `release-please.yml` therefore dispatches `pr.yml` on the release branch, which needs
   `actions: write`. No secret or PAT is involved.
5. **Least privilege.** `pr.yml` has `contents: read` only. `nightly.yml` defaults to `{}`
   and grants per job: `contents: read`, plus `issues: write` for the report job only.
   release-please gets `contents`, `pull-requests`, `issues` and `actions` write.
   Actions are pinned by SHA with a version comment.
6. **Caching and artifacts.**
   - Only `.derivedData/SourcePackages` is cached (518 MB locally). The nightly saves that
     cache on `main`, which is the only scope every PR can restore.
   - DerivedData is not cached. Checkout mtimes invalidate it, it is several GB, and the
     repo's cache cap is 10 GB.
   - PR result bundles (about 79 MB each) upload only on failure, which saves private-repo
     artifact storage.
   - `include-hidden-files: true` is needed because upload-artifact skips dot-paths by default.
7. **Nightly failures.** A failure opens one issue labelled `nightly`. Later failures comment on
   that open issue instead of opening duplicates. The label is created idempotently.
8. **release-please.** The config is the one in ci-cd.md §6 without the no-op `tag-separator`.
   It adds `bootstrap-sha` = 8404d02, so the first release PR does not list all of F00/F02.
   The `simple` type writes only `CHANGELOG.md`; `version.txt` is not created.
9. **`ci_post_clone.sh`** writes to `$CI_PRIMARY_REPOSITORY_PATH/…`. Xcode Cloud runs scripts
   from `ci_scripts/`, so the plan's relative path would have failed. The script also fails
   when `CI_BUILD_NUMBER` is missing. The plan's `-downloadPlatform` branch is dropped
   because no Xcode Cloud workflow tests.

## Deviations and open items

- **Branch protection** cannot follow ci-cd.md §4 as written:
  - It needs GitHub Pro on this private personal repo. The API returns 403.
  - A sole author can never meet required approvals or Code Owner review.
  - Personal repos have no merge queue and no push restrictions. `merge_group` is dropped.
  - The checklist and ci-cd.md record these points.
- **Nightly dependency report** is written to the step summary instead of an artifact.
- **Not done (proposed follow-ups):**
  - SwiftLint analyzer (F00 #9). It is outside the brief's Scope and needs a non-`-quiet`
    full build log plus an extra build.
  - Dependabot for the SHA pins.
  - testing-strategy §4 still names the jobs `test-ios` / `pr-gate` and does not mention
    LedgerSnapshotTesting or LedgerDependencies.
- **`check.sh:47`** has a pre-existing SC2154 shellcheck false positive (F00), which is untouched.

## Verification

- **Runner image** (`macos-26` = arm64, 20260907.0351.1): Xcode 26.6 (17F113) is the default
  at `/Applications/Xcode_26.6.app`. The iOS 26.5 runtime has iPhone 17 and the watchOS 26.5
  runtime has Series 11 (46mm). jq and gh are present.
- **actionlint** 1.7.12, with shellcheck 0.11.0 on `run:` blocks: 0 errors in 3 workflows.
  shellcheck on the new scripts: clean.
- **Real coverage** (PR-iOS and PR-watchOS, identical per file): **LedgerDomain 1381/1398 =
  98.78 %**, and overall is the same. No other module has executable lines yet; they are
  placeholders. Exit 0.
- **Gate failures:**
  - `LedgerDomain` raised to 99 gives exit 1, a ✗ row, and the table in `$GITHUB_STEP_SUMMARY`.
  - A missing threshold gives exit 1.
  - A missing or incomplete bundle gives exit 2. This happened live while a run was rewriting it.
- **Fixture test:** `scripts/tests/coverage-gate.test.sh` has 7 cases, including the brief's
  94 % case. It caught both mutations tried: worst measurement wins, and an off-by-one threshold.
- **Criterion 2, locally:** a planted force unwrap produces
  `::error file=LedgerKit/Sources/LedgerDomain/CIProbe.swift,line=3,col=14::…`. A planted
  format issue produces `::warning file=…,line=2::…`.
- **Criterion 8, offline** (release-please 17.11.2 library, the config above):
  - feat + fix + chore bumps 0.1.0 to 0.2.0. The changelog has only Features and Fixes, and
    the `MARKETING_VERSION` line is bumped.
  - chore/ci/docs/test alone give an empty changelog, so no release PR is opened.
- **Post-clone**, run from `ci_scripts/` with `CI_BUILD_NUMBER=42`: `CURRENT_PROJECT_VERSION = 42`
  for Ledger and LedgerWatch (`-showBuildSettings`). The marker comment leaves the built
  `CFBundleShortVersionString` at 0.1.0.
- **Snapshots:** `$(PROJECT_DIR)` expands in `SNAPSHOT_ARTIFACTS` (read from the generated
  `.xctestrun`), so the brief's fallback is not needed.
- **Nightly dependency commands** ran locally: 0 updates, and `Package.resolved` is untouched.
- **Full `check.sh`** through the simulator lock, on the final tree: **green in 204 s**.
  The script tests passed 7/7. PR ran and passed 17 targets and PR-Watch 8. The coverage
  gate passed at 98.78 %.

## Pending (not verifiable locally)

- **Criteria 1–5 and 10** need GitHub. The first `pr.yml` run on the F01 PR covers criterion 1:
  timing, and the cache logs. The brief's probe PRs are the orchestrator's:
  - `ci-probe/lint`: a force unwrap.
  - `ci-probe/test`: a failing `#expect` in LedgerDomainTests.
  - `ci-probe/coverage`: the LedgerDomain threshold set to 99.
  - `ci-probe/snapshot`: after F06 lands snapshot tests.
  - Criterion 10: `gh workflow run nightly.yml --ref <branch with a failing test>`, once F01 is on `main`.
- **Squash title for this PR:** use `ci: …`. A `feat` title would make release-please open a
  0.2.0 release PR on merge.
- **Criteria 6, 7 and 9** are manual (Pete), in `docs/xcode-cloud/README.md` §2 and §7.
  Pete's decisions come first: GitHub Pro or a public repo, and the Actions budget.
