# ADR-006: GitHub Actions for quality gates; Xcode Cloud for signing and delivery; release-please for versions

**Status:** Accepted · **Date:** 2026-09-16 · **Amended:** 2026-09-29 (Xcode 27) · **Evidence:** `docs/research/R3-tooling-ci.md` §4–§5

## Context

"No bad code hits production" needs fast, strict, scriptable gates on every
PR, plus a trustworthy path to TestFlight and the App Store. Constraints as of
2026-09-16: GitHub `macos-26` runners carry Xcode 26.0.1–26.6 with iOS/watchOS
26.x simulators preinstalled, cost $0.062/min with a 10× included-minute
multiplier; Xcode Cloud offers 25 free compute hours/month, cloud-managed
signing, native TestFlight/App Store submission, and needs a
`ci_scripts/ci_post_clone.sh`. fastlane 2.240 requires Ruby ≥ 3.1 (the system
Ruby is 2.6), and Apple has no official App Store Connect CLI.

## Decision

| Concern | Tool | Notes |
|---|---|---|
| PR gates | GitHub Actions on `macos-26` | `pr.yml`: SwiftFormat `--lint`, SwiftLint `--strict`, build iOS + watchOS, Swift Testing unit/integration/snapshot suites, coverage threshold via `xccov`, UI smoke on the iOS simulator, snapshot diffs uploaded as artifacts. Required checks + branch protection on `main`. |
| Long tests | GitHub Actions nightly | full XCUITest suites (iOS + watchOS), performance tests, dependency audit. |
| Signing, archive, TestFlight | Xcode Cloud | workflow "Beta": on push to `main` → archive iOS + watch → TestFlight internal group. Cloud-managed signing; no certificates in GitHub. |
| App Store submission | Xcode Cloud | workflow "Release": on tag `v*` → archive → TestFlight external + App Store submission (manual release in App Store Connect). |
| Versions & changelog | release-please | Conventional Commits → release PR → tag `vX.Y.Z` on merge; `MARKETING_VERSION` bumped from the release PR; build number = CI build number. |
| Screenshots / metadata | none at launch | fastlane `snapshot`/`deliver` may be added later behind a mise-pinned Ruby 3.4; not required for M0–M4. |

## Alternatives rejected

- **fastlane + match on GitHub Actions for delivery:** works, but adds a Ruby
  toolchain, a certificates repo, and App Store Connect API secrets in GitHub
  for a small team that already gets managed signing free from Xcode Cloud.
- **Xcode Cloud for everything:** fewer gates are scriptable (no coverage
  thresholds, no artifact diffs, weaker `gh` integration for the agent
  pipeline).
- **Self-hosted Mac runner:** revisit only if hosted minutes become the
  bottleneck.

## Consequences

- Two systems, two configs, but each does what it is best at; product code is
  built identically in both (same `.xcode-version`, same xcconfig).
- Xcode 27 migration (F32) must wait for hosted runner images; Xcode Cloud
  already offers 27, so the two pins are tracked together.
- Budget estimate (R3): a PR run ≈ 25–35 macOS minutes; at ~40 PR runs/month
  ≈ $75–90/month plus nightly, within the included minutes of a Team plan.
- **2026-09-27 (Pete):** GitHub Free with no branch protection, and a spending limit of $0.
  CI runs within the free macOS minutes: one macOS job per PR, a manual nightly. The merge
  gate is the orchestrator's policy of a green local `check.sh`, plus CI when it ran
  (`docs/ci-cd.md` §4).

## Amendment 2026-09-29: Xcode 27 on the `xcode-27` preview runner (Pete, F32)

The App Store updated Pete's Mac from Xcode 26.6 to Xcode 27.0 (27A266a). Rather than reinstall 26.6,
Pete decided to migrate now, which brings F32 forward from M5 to M0. The standard `macos-26` image has only
Xcode 26.x, so the PR gate and the nightly move from `macos-26` to the GitHub-hosted **`xcode-27`** label.
It is a public preview image (actions/runner-images#14404): macOS 27.0, with Xcode 27.0 as the default and
iOS/watchOS 27.0 simulators. This replaces "Xcode 27 migration (F32) must wait for hosted runner images"
above and the `macos-26` in the Decision table.

- `.xcode-version` is 27.0 on developer Macs, in GitHub Actions and in Xcode Cloud, whose workflows select
  Xcode 27.0 explicitly. The pins still move together.
- If the preview image breaks, the fallback is `macos-26` with `.xcode-version` 26.6 and the 26.5
  simulators. Rolling back means reverting F32, and locally it also means reinstalling Xcode 26.6.
- When `xcode-27` graduates or `macos-26` gains Xcode 27, choose the label again (`docs/ci-cd.md`).
