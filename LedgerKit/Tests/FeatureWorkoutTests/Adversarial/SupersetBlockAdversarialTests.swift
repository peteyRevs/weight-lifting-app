@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// G2, F10 S9: the superset block's model attacked with blocks of three members and unequal counts, added
/// sets that change the rounds, drop rounds, un-logs in the middle of a round, labels past 9, swaps of a member,
/// "REMAINING" around a block jumped into from the middle, the rest panel's line, the header and the receipt.
/// Every set is logged through the real engine and every tap through `WorkoutEditPlan`, as the pump does.
@Suite("Superset block (adversarial, F10 S9)", .tags(.feature))
struct SupersetBlockAdversarialTests {
    typealias Cards = WorkoutPresentationCardTests

    /// Bench (2 × 5, solo), then A Lat Pulldown (3 × 12 @ 100, 75 s), B Face Pull (1 × 15 @ 30, 60 s) and C Cable
    /// Lateral Raise (2 × 15 @ 15, 90 s) as one block, then Curl (2 × 10, solo).
    static func three(units: Units = .lb) -> WorkoutState {
        var state = EventBuilders.session([
            .init("Barbell Bench Press", .barbell, sets: 2, reps: 5, pounds: 185, restSeconds: 150),
            .init("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75),
            .init("Face Pull", .cable, sets: 1, reps: 15, pounds: 30, restSeconds: 60, superset: true),
            .init("Cable Lateral Raise", .cable, sets: 2, reps: 15, pounds: 15, restSeconds: 90, superset: true),
            .init("Barbell Curl", .barbell, sets: 2, reps: 10, pounds: 75, restSeconds: 60)
        ])
        state.units = units
        return state
    }

    /// A walk of taps: each edit is planned on the workout as it stands and its events reduced by the engine.
    struct Walk {
        var state: WorkoutState
        var selection: WorkoutSelection?
        var seq: UInt64 = 2
        var now = EventBuilders.start

        init(_ state: WorkoutState) {
            self.state = state
        }

        mutating func tap(_ edit: WorkoutEdit) {
            now = now.addingTimeInterval(10)
            let plan = WorkoutEditPlan.make(edit, in: state, selection: selection, now: now) {
                SetID(EventBuilders.uuid(0xA00 + Int(seq)))
            }
            for event in plan.events {
                let envelope = EventBuilders.envelope(event, seq: seq, at: now)
                seq += 1
                state = WorkoutEngine.reduce(state, envelope).0 ?? state
            }
            selection = plan.selection
        }

        var page: WorkoutPageModel {
            Cards.page(state, selection: selection)
        }

        var block: SupersetBlockModel? {
            page.block
        }

        var header: WorkoutHeaderModel {
            WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale, selection: selection)
        }

        /// The shown row's check, as the lifter taps it.
        mutating func logTheShownRow() throws {
            let row = try #require(block?.rows.first { $0.state == .active })
            tap(row.check)
        }
    }

    // MARK: Three members, unequal counts: every cursor position

    /// What the block and the header show at one position of the walk.
    struct Position {
        let title: String
        let current: [Bool]
        let label: String
        let header: String
    }

    @Test("A walk of a 3-member block (3, 1, 2 sets): title, legend, shown row, header, rest line at every position")
    func threeMembers_everyCursorPosition() throws {
        var walk = Walk(Self.three())
        walk.tap(.jump(exerciseIndex: 1))
        let expected = [
            Position(title: "Round 1 of 3", current: [true, false, false], label: "A1", header: "Exercise 2 of 5"),
            Position(title: "Round 1 of 3", current: [false, true, false], label: "B1", header: "Exercise 3 of 5"),
            Position(title: "Round 1 of 3", current: [false, false, true], label: "C1", header: "Exercise 4 of 5"),
            Position(title: "Round 2 of 3", current: [true, false, false], label: "A2", header: "Exercise 2 of 5"),
            Position(title: "Round 2 of 3", current: [false, false, true], label: "C2", header: "Exercise 4 of 5"),
            Position(title: "Round 3 of 3", current: [true, false, false], label: "A3", header: "Exercise 2 of 5")
        ]
        for (step, want) in expected.enumerated() {
            let block = try #require(walk.block, "step \(step)")
            #expect(block.title == want.title, "step \(step)")
            #expect(block.legend.map(\.isCurrent) == want.current, "step \(step)")
            #expect(block.rows.first { $0.state == .active }?.label == want.label, "step \(step)")
            #expect(walk.header.progressValue == want.header, "step \(step)")
            #expect(block.restLine == "Rest 1:30 after C", "step \(step)")
            #expect(block.eyebrow == "Superset · block 2 of 3", "step \(step)")
            try walk.logTheShownRow()
        }
        #expect(walk.block == nil, "the block is done: the curl's card is shown")
        #expect(walk.page.card?.title == "Barbell Curl")
        #expect(walk.page.remaining?.rows.map(\.name) == ["Barbell Bench Press"])
    }

    @Test("Q12 and the Texts: the rest line names the longest rest and the last letter, with auto rest off too")
    func restLine_words_autoRestOff() throws {
        var state = Self.three()
        state.autoRest = false
        let page = Cards.page(state, selection: WorkoutSelection(exerciseIndex: 1, setID: nil))
        let block = try #require(page.block)
        #expect(block.restLine == "Rest 1:30 after C")
        #expect(block.restLineSpoken == "Rest 1 minute, 30 seconds after C")
        #expect(block.addSet == "+ Add set")
        #expect(block.current?.lastLabel == "Last")
        #expect(block.legend.map(\.spoken) == [
            "A, Lat Pulldown, 3 × 12 @ 100 lb", "B, Face Pull, 1 × 15 @ 30 lb", "C, Cable Lateral Raise, 2 × 15 @ 15 lb"
        ])
        #expect(block.legend.map(\.swap) == ["Swap Lat Pulldown", "Swap Face Pull", "Swap Cable Lateral Raise"])
    }

    @Test("Rows of a 3-member block in display order, labelled by member: A1 B1 C1 A2 C2 A3")
    func threeMembers_rows() throws {
        let page = Cards.page(Self.three(), selection: WorkoutSelection(exerciseIndex: 2, setID: nil))
        let block = try #require(page.block)
        #expect(block.rows.map(\.label) == ["A1", "B1", "C1", "A2", "C2", "A3"])
        #expect(block.rows.map(\.exerciseIndex) == [1, 2, 3, 1, 3, 1])
        #expect(block.legend.map(\.letter) == ["A", "B", "C"])
        #expect(block.legend.map(\.target) == ["3 × 12 @ 100 lb", "1 × 15 @ 30 lb", "2 × 15 @ 15 lb"])
    }

    // MARK: Added sets change the rounds

    @Test("+ Add set on B (current) makes B2, so round 2 holds A2 B2 C2; + Add set on A makes a 4th round")
    func addedSets_changeTheRounds() throws {
        var walk = Walk(Self.three())
        walk.tap(.jump(exerciseIndex: 1))
        try walk.logTheShownRow() // A1; B1 is shown
        #expect(walk.block?.current?.exerciseIndex == 2)
        walk.tap(.addSet(exerciseIndex: 2))
        let afterB = try #require(walk.block)
        #expect(afterB.rows.map(\.label) == ["A1", "B1", "C1", "A2", "B2", "C2", "A3"])
        #expect(afterB.title == "Round 1 of 3")
        #expect(afterB.rows.first { $0.state == .active }?.label == "B1", "the shown row stays")
        // B2 is now in the middle of round 2: logging it starts no rest.
        for _ in 0 ..< 3 {
            try walk.logTheShownRow() // B1, C1, A2
        }
        #expect(walk.state.rest == nil, "A2 ended C1's rest (Q4)")
        #expect(walk.block?.rows.first { $0.state == .active }?.label == "B2")
        walk.tap(.addSet(exerciseIndex: 2))
        let fourRounds = try #require(walk.block)
        #expect(fourRounds.rows.map(\.label) == ["A1", "B1", "C1", "A2", "B2", "C2", "A3", "B3"])
        #expect(fourRounds.title == "Round 2 of 3", "B3 joins round 3; still three rounds")
    }
}

// MARK: - Drop rounds, un-logs, re-logs and labels past 9

extension SupersetBlockAdversarialTests {
    // MARK: Drop rows as the final round

    @Test("Drop rows AD and BD form the final round: Round 4 of 4, labels, spoken drop rows, the panel's AD line")
    func dropRound() throws {
        let workout = EventBuilders.session([
            .init("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75, dropSet: true),
            .init(
                "Cable Lateral Raise", .cable, sets: 3, reps: 15, pounds: 15, restSeconds: 60, superset: true,
                dropSet: true
            )
        ])
        var walk = Walk(workout)
        for _ in 0 ..< 6 {
            try walk.logTheShownRow()
        }
        let block = try #require(walk.block)
        #expect(block.rows.map(\.label) == ["A1", "B1", "A2", "B2", "A3", "B3", "AD", "BD"])
        #expect(block.title == "Round 4 of 4")
        let active = try #require(block.rows.first { $0.state == .active })
        #expect(active.label == "AD")
        #expect(active.checkLabel == "Log set AD")
        #expect(active.summary == "Lat Pulldown, drop set, 100 pounds, 12 reps")
        let panel = WorkoutPresentation.rest(
            walk.state, at: walk.now, selection: walk.selection, isBusy: false, locale: Fixtures.locale
        )
        #expect(panel?.next?.line == "AD · 100 lb × 12")
        try walk.logTheShownRow() // AD: ends B3's rest
        #expect(walk.state.rest == nil)
        #expect(walk.block?.rows.first { $0.state == .active }?.label == "BD")
        try walk.logTheShownRow() // BD: the group's rest
        #expect(walk.state.rest?.total == .seconds(75))
        let done = try #require(walk.block)
        #expect(done.title == "Round 4 of 4")
        #expect(done.current == nil && done.steppers == nil)
        #expect(done.rows.last?.checkLabel == "Undo set BD")
    }

    // MARK: Un-logging in the middle of a round

    @Test("Un-logging A1 after A1 B1 A2: the title goes back to round 1, the shown row stays B2, A1 logs again")
    func unlogMidRound() throws {
        let pair = EventBuilders.session([
            .init("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75),
            .init("Cable Lateral Raise", .cable, sets: 3, reps: 15, pounds: 15, restSeconds: 60, superset: true)
        ])
        var walk = Walk(pair)
        for _ in 0 ..< 3 {
            try walk.logTheShownRow()
        }
        let rowA1 = try #require(walk.block?.rows.first)
        #expect(rowA1.checkLabel == "Undo set A1")
        walk.now = walk.now.addingTimeInterval(5) // past the one-second guard
        walk.tap(rowA1.check)
        let block = try #require(walk.block)
        #expect(block.rows.first?.state == .pending)
        #expect(block.rows.first?.checkLabel == "Log set A1")
        #expect(block.title == "Round 1 of 3")
        #expect(block.rows.first { $0.state == .active }?.label == "B2", "un-logging moves nothing (rule 22)")
        #expect(block.legend.map(\.isCurrent) == [false, true])
        // Logging A1 again: not the last of round 1, so it starts no rest, and the cursor goes on from A1.
        walk.tap(block.rows[0].check)
        #expect(walk.state.rest == nil)
        #expect(walk.block?.title == "Round 2 of 3")
    }

    @Test("Re-logging B1 after an un-log (it ends round 1) starts the group's rest again; the panel names A2")
    func relogTheRoundsLast() throws {
        let pair = EventBuilders.session([
            .init("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75),
            .init("Cable Lateral Raise", .cable, sets: 3, reps: 15, pounds: 15, restSeconds: 60, superset: true)
        ])
        var walk = Walk(pair)
        try walk.logTheShownRow()
        try walk.logTheShownRow()
        let first = try #require(walk.state.rest)
        let rowB1 = try #require(walk.block?.rows[1])
        walk.now = walk.now.addingTimeInterval(5)
        walk.tap(rowB1.check)
        #expect(walk.state.rest == first, "un-logging keeps the rest (rule 22)")
        let pending = try #require(walk.block?.rows[1])
        walk.tap(pending.check)
        #expect(walk.state.rest?.endsAt == walk.now.addingTimeInterval(75))
        let panel = WorkoutPresentation.rest(
            walk.state, at: walk.now, selection: walk.selection, isBusy: false, locale: Fixtures.locale
        )
        #expect(panel?.next?.line == "A2 · 100 lb × 12")
    }

    // MARK: Labels past 9

    @Test("Labels past 9: A10 … A12 and B10 … B12, spoken and checked by label")
    func labelsPastNine() throws {
        let pair = EventBuilders.session([
            .init("Lat Pulldown", .cable, sets: 12, reps: 12, pounds: 100, restSeconds: 75),
            .init("Cable Lateral Raise", .cable, sets: 12, reps: 15, pounds: 15, restSeconds: 60, superset: true)
        ])
        let block = try #require(Cards.page(pair).block)
        let labels = block.rows.map(\.label)
        #expect(labels.suffix(6) == ["A10", "B10", "A11", "B11", "A12", "B12"])
        #expect(block.title == "Round 1 of 12")
        let a10 = try #require(block.rows.first { $0.label == "A10" })
        #expect(a10.summary == "Lat Pulldown, set 10, 100 pounds, 12 reps")
        #expect(a10.checkLabel == "Log set A10")
        let b12 = try #require(block.rows.last)
        #expect(b12.checkLabel == "Log set B12")
    }
}
