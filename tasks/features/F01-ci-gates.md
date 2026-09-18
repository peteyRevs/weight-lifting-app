# F01 — CI gates, delivery workflows, release automation

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | F00 |
| Branch | `feat/F01-ci-gates` |
| Design refs | none |
| Spec refs | `docs/ci-cd.md` (all), `docs/testing-strategy.md` §4, §7, §8, ADR-006 |

## Goal
Every pull request is blocked unless format, lint, both platform builds, the PR test plans, the coverage thresholds and snapshot parity all pass; every merge to `main` produces a TestFlight build without any secret leaving Apple's infrastructure; versions and changelogs are cut from Conventional Commits. After this ships, "no bad code hits production" is enforced by machines, not memory.

## User stories
- As the orchestrator, I open a PR and within ~20 minutes know from two required checks whether it is mergeable.
- As Pete, I merge to `main` and a TestFlight build appears on my phone and watch without touching certificates.
- As a reviewer, I see a coverage table and snapshot diffs in the PR summary.

## Scope
**In:** `pr.yml`, `nightly.yml`, `release-please.yml`, `scripts/coverage-gate.sh`, `ci_scripts/ci_post_clone.sh`, `CODEOWNERS`, release-please config + manifest, the human checklists for branch protection and Xcode Cloud workflows, nightly-failure issue creation.
**Out (explicitly):** fastlane, screenshots, App Store metadata (F31); Xcode 27 (F32); device-lane workflows (F20).

## Touches
- `.github/workflows/pr.yml`, `.github/workflows/nightly.yml`, `.github/workflows/release-please.yml`
- `.github/CODEOWNERS`
- `scripts/coverage-gate.sh`
- `ci_scripts/ci_post_clone.sh`
- `release-please-config.json`, `.release-please-manifest.json`
- `docs/xcode-cloud/README.md` (workflow settings as configured, with screenshots)
- `docs/ci-cd.md` (only if a verified fact differs from the plan; record what changed)

## Domain changes
None.

## Acceptance criteria
1. Given a PR touching Swift code, when it is opened, then the checks `Lint` and `Check (iOS + watchOS)` run on `macos-26` with Xcode 26.6 and finish in ≤ 30 minutes warm.
2. Given a PR that introduces a SwiftLint warning, when `Lint` runs, then it fails and the annotation points at the file and line.
3. Given a PR with one failing Swift Testing test in `LedgerDomainTests`, when `Check` runs, then the job fails and the result bundle is uploaded as an artifact.
4. Given a PR that drops `LedgerDomain` line coverage to 94 %, when the coverage gate runs, then the job fails and the step summary shows the table with the ✗ row.
5. Given a PR that changes a `LedgerDesign` snapshot, when `Check` runs, then the diff images appear under the `results-*` artifact and the test fails until the snapshot is re-recorded.
6. Given `main`'s branch protection is configured per `docs/ci-cd.md` §4, when anyone pushes directly to `main`, then GitHub rejects it (verify manually; paste the rejection in the PR).
7. Given a merge to `main`, when Xcode Cloud "Beta" runs, then a build with `CURRENT_PROJECT_VERSION == CI_BUILD_NUMBER` reaches the TestFlight internal group (verify manually; screenshot).
8. Given three commits `feat(today): …`, `fix(engine): …`, `chore: …` merged to `main`, when release-please runs, then it opens a release PR bumping `MARKETING_VERSION` in `Config/Base.xcconfig` from `0.1.0` to `0.2.0` with a changelog listing only the feat and fix.
9. Given the release PR is merged, when the tag `v0.2.0` is created, then Xcode Cloud "Release" starts (verify manually).
10. Given the nightly workflow fails, when the run completes, then an issue labelled `nightly` is created with a link to the run.

## Test plan
- Shell: `scripts/coverage-gate.sh` has a fixture test — `scripts/tests/coverage-gate.test.sh` feeds two saved `xccov` JSON reports (one passing, one with Domain at 94 %) and asserts exit codes 0 and 1 and the Markdown table contents. Run by `check.sh` step (2).
- Workflow dry-runs: open a throwaway PR per criteria 2–5 (each on its own branch: `ci-probe/lint`, `ci-probe/test`, `ci-probe/coverage`, `ci-probe/snapshot`), record the run URLs in `implementation-notes.md`, then close the PRs.
- Manual: criteria 6, 7, 9 with screenshots stored under `tasks/features/F01-ci-gates/`.

## Non-functional
- Runtime: `Lint` ≤ 3 min, `Check` ≤ 30 min warm; cache hit rate visible in logs.
- Cost: within `docs/ci-cd.md` §9 estimate; `Check` uses `paths:` filter to skip docs-only PRs (docs-only PRs still get `Lint`).
- Security: `GITHUB_TOKEN` permissions minimal per workflow; no secrets added.

## Risks / unknowns
- The `macos-26` image path for Xcode 26.6 (`/Applications/Xcode_26.6.app`) — verify from the runner image README on day one.
- `$(PROJECT_DIR)` expansion in test-plan environment variables (testing-strategy §8) — if it fails, pass `TEST_RUNNER_SNAPSHOT_ARTIFACTS` on the command line and update `check.sh`.
- Xcode Cloud requires the project to exist on the default branch before workflows can be created → F00 must be merged first.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Branch protection screenshot and Xcode Cloud workflow screenshots committed under `tasks/features/F01-ci-gates/`.
- [ ] `docs/ci-cd.md` updated with any verified deviations (marked "verified 2026-MM-DD").
- [ ] Probe PRs closed and their branches deleted.

---
_Filled in by agents during delivery:_
- `F01-ci-gates/implementation-notes.md`
- `F01-ci-gates/test-findings.md`
- `F01-ci-gates/review.md`
