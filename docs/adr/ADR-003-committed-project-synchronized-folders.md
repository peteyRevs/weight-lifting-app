# ADR-003: Committed Xcode project with synchronized folders, umbrella package products, xcconfig

**Status:** Accepted · **Date:** 2026-09-16 · **Evidence:** `docs/research/R3-tooling-ci.md` §1

## Context

Many AI agents will add files in parallel worktrees. `project.pbxproj` merge
conflicts would stall the pipeline. The usual cure is a generator (XcodeGen or
Tuist), but as of 2026-09-16 XcodeGen 2.46 has an open blocker for watch app
embedding on Xcode 26 (issue #1613, fix PR unmerged) and Tuist shares the same
legacy embed path. Xcode Cloud also prefers a real project in the repo.

## Decision

1. **One committed `Ledger.xcodeproj`**, created once in Xcode (human, ~10
   minutes, checklist in brief F00). All app-target source folders are Xcode
   **synchronized folders** (Xcode 16+), so adding, moving, or deleting files
   never touches the pbxproj.
2. **All product code lives in the local package `LedgerKit`.** App targets
   depend on exactly one umbrella product each — `LedgerAppKit` (iOS) and
   `LedgerWatchAppKit` (watchOS) — which in turn depend on the feature targets.
   Adding a feature is a `Package.swift` edit only.
3. **Build settings live in `Config/*.xcconfig`** (text, mergeable), not in
   the pbxproj.
4. The pbxproj therefore changes only for new targets, capabilities, or
   entitlements. Those edits are made in Xcode by a human, in a dedicated
   `chore:` PR, and verified by CI. Agents never edit `project.pbxproj`.
5. If, during F00, synchronized folders prove insufficient (e.g. a needed
   per-file target membership exception), the fallback is a one-shot XcodeGen
   generation with the documented `copy: {destination: plugins}` override,
   after which the generated project is committed and XcodeGen is dropped.

## Consequences

- No generator toolchain in CI or on developer machines; Xcode Cloud works
  out of the box.
- Feature work is fully parallelisable at the package level; `Package.swift`
  conflicts are trivial text merges.
- A human is in the loop for target-level changes — rare by design.
- Revisit if XcodeGen resolves #1613 and a generator becomes worth it.
