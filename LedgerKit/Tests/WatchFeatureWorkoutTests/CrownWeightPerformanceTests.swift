import LedgerDesign
import LedgerDomain
import LedgerSnapshotTesting
import LedgerTestSupport
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 non-functional, the crown's budget: a detent shows on the next frame, with `.ledgerFont`'s per-body font
/// construction included (F06 review N2). One update is the dial for the next detent and the numeral drawn from it
/// (`ImageRenderer`: body, both `.ledgerFont`s, layout and drawing), held under half a 60 Hz frame at the median of
/// 20 runs after one warm-up; the font construction alone is reported beside it. A timing is only meaningful without
/// other suites competing for the CPU, so this is nightly lane only (testing-strategy §6).
@MainActor
@Suite(
    "CrownWeight · timing",
    .tags(.watch),
    .serialized,
    .enabled(if: TestLane.isNightly, "a timing test: nightly lane only")
)
struct CrownWeightPerformanceTests {
    static let update: Duration = .microseconds(8333)
    static let runs = 20

    @Test("A crown detent's numeral update is drawn in under half a frame (8.3 ms)")
    func detentUpdate_underBudget() {
        var crown = CrownWeightModel()
        let target = CrownWeightModel.Target(exerciseIndex: 0, setID: SetID(Fixtures.uuid(1)))
        crown.follow(CrownWeightModel.Reading(target: target, weight: .pounds(185), step: .pounds(5), units: .lb))
        var drawn = 0
        let work = {
            crown.rotate(to: crown.value + 5)
            guard let dial = WatchPresentation.crownDial(crown, locale: WatchWorkoutComponentTests.locale) else {
                return
            }
            let view = CrownWeight(dial: dial, onRotate: { _ in }, onRest: {}).ledgerWatchPage()
            drawn += RenderedImage.render(view, dynamicTypeSize: WatchSize.mm46.dynamicTypeSize) == nil ? 0 : 1
        }
        work()
        let clock = ContinuousClock()
        let timings = (0 ..< Self.runs).map { _ in clock.measure(work) }
        #expect(drawn == Self.runs + 1)
        let verdict = PerformanceRunner.verdict(timings, budget: Self.update, statistic: .median)
        #expect(verdict.isWithinBudget, "\(verdict)")
        let fonts = (0 ..< Self.runs).map { _ in
            clock.measure {
                let size = LedgerFont.scaledSize(.watchNumeral, dynamicTypeSize: WatchSize.mm46.dynamicTypeSize)
                _ = LedgerFont.font(.watchNumeral, size: size)
            }
        }
        let fontMedian = PerformanceRunner.statistics(fonts).median
        let report = "Crown update: median \(verdict.median), p95 \(verdict.percentile95); "
            + "the numeral's font: median \(fontMedian)"
        Attachment.record(report, named: "crown-weight.txt")
    }
}
