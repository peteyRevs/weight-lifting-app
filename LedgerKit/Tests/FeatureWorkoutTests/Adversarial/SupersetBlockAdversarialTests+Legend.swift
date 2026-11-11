@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

// MARK: - Legend jumps and the display order

extension SupersetBlockAdversarialTests {
    /// Criteria 7 and 8: a legend tap shows the member at "its first undone row"; the block's own order is the
    /// display order (working rounds, then drop rounds), where an added set after a drop set (B4) comes before
    /// the drop row (BD). The tap should show the row the block draws first, as the cursor and the fallback do.
    @Test("A legend tap on B, whose B4 was added after BD, shows B4 (first in the block's order), not BD")
    func legendJump_addedAfterDrop_showsDisplayOrderFirst() throws {
        var state = EventBuilders.session([
            .init("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75),
            .init(
                "Cable Lateral Raise", .cable, sets: 3, reps: 15, pounds: 15, restSeconds: 60, superset: true,
                dropSet: true
            )
        ])
        state.exercises[1].sets.append(LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(15), reps: Reps(clamping: 15), kind: .added
        ))
        var walk = Walk(state)
        for _ in 0 ..< 6 {
            try walk.logTheShownRow() // A1 B1 A2 B2 A3 B3
        }
        #expect(walk.block?.rows.map(\.label) == ["A1", "B1", "A2", "B2", "A3", "B3", "B4", "BD"])
        #expect(walk.block?.rows.first { $0.state == .active }?.label == "B4", "the cursor goes on to B4")
        // The lifter taps B's row on the legend.
        walk.tap(.jump(exerciseIndex: 1))
        let shown = walk.block?.rows.first { $0.state == .active }?.label
        #expect(shown == "B4", "B's legend tap should show B4, the block's next row; it shows \(shown ?? "nothing")")
    }
}
