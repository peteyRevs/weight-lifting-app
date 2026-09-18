# F32 — Xcode 27 / Swift 6.4 migration

| | |
|---|---|
| Milestone | M5 (or earlier if runners ship Xcode 27) |
| Status | proposed |
| Depends on | Xcode 27 available on GitHub `macos-26` runners; hard deadline: April 2027 App Store SDK requirement |
| Branch | `chore/F32-xcode-27` |
| Design refs | none |
| Spec refs | `docs/research/R1-apple-platform.md` §1; R3 §1, §4; ADR-006 |

## Goal
Move the toolchain pin from Xcode 26.6 / Swift 6.3 to Xcode 27 / Swift 6.4 on every machine and both CI systems in one PR, before Apple requires the iOS 27 / watchOS 27 SDKs for submissions (April 2027), without changing behaviour.

## Scope
**In:** `.xcode-version` → `27.x`, `SWIFT_VERSION` unchanged (6), fix new warnings-as-errors, adopt deprecation replacements (`WKExtension` → `WKApplicationDelegate` already; check `HKWorkoutSession` / ActivityKit deltas from R1), verify min deployment stays iOS 26 / watchOS 26, update `mise.toml` if SwiftLint/SwiftFormat need bumps for Swift 6.4 syntax, re-record snapshots only if rendering changed (review diffs), update Xcode Cloud workflow environment, update `docs/architecture.md` §1 and `docs/engineering-standards.md` §1, remove the `#available(iOS 27)` guards that become baseline only if the min OS is raised (it is not, in this brief).
**Out:** raising the minimum OS.

## Touches
- `.xcode-version`, `Config/Base.xcconfig` (if flags change), `mise.toml`, `.github/workflows/*.yml` (`XCODE_VERSION`), `docs/ci-cd.md`, `docs/architecture.md`, `docs/engineering-standards.md`, snapshot references as needed

## Domain changes
None.

## Acceptance criteria
1. Given the runner image README lists Xcode 27.x, then `pr.yml` selects it and `Check` is green with zero warnings.
2. Given the local machine on Xcode 27, then `scripts/check.sh` is green and `xcodebuild -version` matches `.xcode-version`.
3. Given Xcode Cloud "Beta" on Xcode 27, then a TestFlight build is produced and the watch app installs on watchOS 26 and 27 devices.
4. Given snapshot diffs, then each changed reference is reviewed and justified in the PR (font rendering deltas are expected; layout deltas are bugs).
5. Given the migration PR, then no product code changes except deprecation replacements; behaviour tests unchanged and green.

## Test plan
- Full PR + nightly suites; device sanity on both OS generations (F20 subset).

## Rollback
- Revert the PR; pins return to 26.6 (runners keep 26.6 available through 2027 per the image policy — verify at the time).

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F32-xcode-27-migration/{implementation-notes,review}.md`
