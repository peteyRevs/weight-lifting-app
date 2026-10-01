import CoreGraphics
@testable import LedgerDesign
import Testing

/// `ProgressSegments` shares its width as v2's flex row does: the gaps first, then the rest in
/// proportion to each segment's length (the exercise's set count).
@Suite("ProgressSegmentsLayout", .tags(.design))
nonisolated struct ProgressSegmentsLayoutTests {
    /// v2's workout: five exercises of 5, 3, 4, 3 and 3 sets.
    static let workout = [5, 3, 4, 3, 3].map { ProgressSegment(length: $0, state: .upcoming) }

    @Test("Five exercises share 350 pt less four 3 pt gaps in proportion to their sets")
    func widths_fiveExercises_proportionalToTheirSets() {
        let widths = ProgressSegments.widths(of: Self.workout, in: 350)
        #expect(widths.count == 5)
        #expect(abs(widths.reduce(0, +) + 4 * ProgressSegments.gap - 350) < 1e-9)
        #expect(abs(widths[0] / widths[1] - 5.0 / 3) < 1e-9)
        #expect(abs(widths[2] / widths[3] - 4.0 / 3) < 1e-9)
        #expect(widths[3] == widths[4])
    }

    @Test("A segment of zero or negative length draws nothing and takes no gap; the others share the width")
    func widths_nonPositiveLengths_drawNothingAndTakeNoGap() {
        let segments = [0, -2, 3].map { ProgressSegment(length: $0, state: .done) }
        #expect(ProgressSegments.widths(of: segments, in: 100) == [0, 0, 100])
        let middle = [3, 0, 3].map { ProgressSegment(length: $0, state: .done) }
        #expect(ProgressSegments.widths(of: middle, in: 100) == [48.5, 0, 48.5], "one 3 pt gap, not two")
    }

    @Test("No segments, no length or no room draws nothing")
    func widths_degenerateInputs_areEmptyOrZero() {
        #expect(ProgressSegments.widths(of: [], in: 350).isEmpty)
        #expect(ProgressSegments.widths(of: [0, 0].map { ProgressSegment(length: $0, state: .done) }, in: 350) == [
            0,
            0
        ])
        #expect(ProgressSegments.widths(of: Self.workout, in: 5).allSatisfy { $0 == 0 })
    }
}
