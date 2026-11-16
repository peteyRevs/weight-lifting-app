import CoreGraphics
@testable import LedgerDesign
import LedgerTestSupport
import Testing

/// F11 S8 adversarial round 1, by measurement: `WrapLayout` arranges 5,000 children in a phone's width in under
/// 4 ms, at the median of 20 runs after one warm-up (1.9-2.0 ms on the iPhone 17 and the Apple Watch Series 12
/// simulators, three runs each, 2026-11-15). That each is given a frame is
/// `WrapLayoutAdversarialTests.arrangement_manyChildren_framesEach`'s. A timing is only meaningful without other
/// suites competing for the CPU, so this is `.performance`: nightly lane only (testing-strategy §6).
@Suite(
    "WrapLayout · timing",
    .tags(.design, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct WrapLayoutPerformanceTests {
    static let arrangement: Duration = .milliseconds(4)
    static let runs = 20

    @Test("5,000 children are arranged in under 4 ms")
    func manyChildren_underBudget() {
        var random = SplitMix64(seed: 5000)
        let sizes = WrapLayoutAdversarialTests.sizes(5000, upTo: 90, using: &random)
        let layout = WrapLayout(spacing: 8, lineSpacing: 6)
        var frames = 0
        let work = { frames = layout.arrangement(of: sizes, in: 402).frames.count }
        work()
        let clock = ContinuousClock()
        let timings = (0 ..< Self.runs).map { _ in clock.measure(work) }
        #expect(frames == 5000)
        let verdict = PerformanceRunner.verdict(timings, budget: Self.arrangement, statistic: .median)
        #expect(verdict.isWithinBudget, "\(verdict)")
        Attachment.record("WrapLayout over 5,000 children: median \(verdict.median)", named: "wrap-layout.txt")
    }
}
