# F26 — Performance and polish pass

| | |
|---|---|
| Milestone | M3 |
| Status | proposed |
| Depends on | M1, M2 complete |
| Branch | `feat/F26-performance-polish` |
| Design refs | all screens; v2 motion notes (spec §8.8) |
| Spec refs | `docs/architecture.md` §15 budgets; `docs/engineering-standards.md` §7; F20 results |

## Goal
Measure every budget in architecture §15, fix what misses, and finish the interaction details that make the app feel native: animation timing, haptics, Reduce Motion alternatives, contrast for low-alpha text, and signposts so regressions are visible in nightly runs.

## Scope
**In:** measurement harness (XCTMetrics + signposts), fixes, haptic map (setLogged light, restOver double, PR success, finished notification style), `LedgerMotion` tuning, contrast audit of `.inkFaint`/`.inkMuted` text, list/scroll performance with 1,000 workouts, watch crown responsiveness, binary size report.
**Out:** new features; iCloud (M4).

## Touches
- `Apps/LedgerUITests/Performance/*.swift`, `LedgerKit/Tests/LedgerPersistenceTests/StatsQueriesPerformanceTests.swift` (extend)
- `LedgerKit/Sources/LedgerDesign/Tokens/{LedgerMotion,LedgerColor}.swift` (tuning only), `LedgerKit/Sources/LedgerDependencies/Keys/Haptics.swift`
- `docs/performance-report.md` (new: numbers before/after, device + simulator)

## Domain changes
None.

## Acceptance criteria
1. Given an iPhone 15-class device, then cold launch to Today ≤ 600 ms (XCTApplicationLaunchMetric, 5 iterations, p50), recorded in the report.
2. Given 20,000 sets, then every `StatsQueries` method p95 ≤ 50 ms on the simulator and ≤ 80 ms on device.
3. Given a set logged on one device with the other reachable, then the other reflects it ≤ 1 s (F20 protocol, 10 trials, p90).
4. Given a crown detent on the watch set-ready screen, then the weight label updates on the next frame (signpost interval < 16 ms) and a `.click` haptic plays per detent.
5. Given Reduce Motion on, then no translate/scale animations run anywhere (audit via a test-mode flag that asserts on animation creation) and the rest "GO" buzz becomes an opacity pulse.
6. Given all text at `.inkMuted` or lighter that conveys information (numbers, labels), then contrast ≥ 4.5:1 against `ground`; decorative text is listed as exempt in the report.
7. Given the Release build, then the iOS app ≤ 15 MB and the watch app ≤ 8 MB (App Thinning report).
8. Given the History list with 1,000 workouts, then scrolling stays ≥ 58 fps (XCTOSSignpostMetric on the scroll signpost).

## Test plan
- Performance (nightly, `.slow`): launch metric, stats p95, scroll signpost, watch crown signpost (device lane).
- Unit: haptic map tests (`FakeHaptics` records the right pattern per effect), Reduce Motion tests.
- Manual: contrast audit table in the report.

## Non-functional
- The report is the deliverable; every number has a date, device, build.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `docs/architecture.md` §15 updated with measured values.

---
_Filled in by agents during delivery:_ `F26-performance-polish/{implementation-notes,test-findings,review}.md`
