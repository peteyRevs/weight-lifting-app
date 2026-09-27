import Foundation
@testable import LedgerDomain
import Testing

@Suite("Slot validation", .tags(.domain))
struct SlotValidationTests {
    /// One invalid slot per row; unspecified fields are valid defaults.
    struct InvalidRow: Sendable, CustomStringConvertible {
        var sets = 3
        var reps = 8
        var repsHi = 10
        var rpe: Decimal = 8
        var rest = 90
        var dropSets = 0
        var startLoad: Weight?
        var step: Weight?
        let expected: SlotValidationError
        let description: String

        func make() throws(SlotValidationError) -> Slot {
            try Slot(
                id: SlotID(Fixtures.uuid(1)),
                exerciseID: Fixtures.bench.id,
                sets: sets,
                reps: reps,
                repsHi: repsHi,
                rpe: rpe,
                restSeconds: rest,
                progression: .linear,
                startLoad: startLoad,
                step: step,
                dropSets: dropSets
            )
        }

        static let all: [InvalidRow] = [
            InvalidRow(sets: 13, expected: .setsOutOfRange(13), description: "sets 13 (criterion 13)"),
            InvalidRow(sets: 0, expected: .setsOutOfRange(0), description: "sets 0"),
            InvalidRow(reps: 0, expected: .repsOutOfRange(0), description: "reps 0 (criterion 13)"),
            InvalidRow(reps: 31, repsHi: 32, expected: .repsOutOfRange(31), description: "reps 31"),
            InvalidRow(
                reps: 8,
                repsHi: 8,
                expected: .repsHiNotAboveReps(reps: 8, repsHi: 8),
                description: "repsHi == reps (criterion 13)"
            ),
            InvalidRow(
                reps: 10,
                repsHi: 6,
                expected: .repsHiNotAboveReps(reps: 10, repsHi: 6),
                description: "repsHi < reps (criterion 13)"
            ),
            InvalidRow(reps: 1, repsHi: 1, expected: .repsHiOutOfRange(1), description: "repsHi 1"),
            InvalidRow(repsHi: 41, expected: .repsHiOutOfRange(41), description: "repsHi 41"),
            InvalidRow(rpe: dec("4.75"), expected: .rpeOutOfRange(dec("4.75")), description: "rpe 4.75 (criterion 13)"),
            InvalidRow(rpe: dec("10.5"), expected: .rpeOutOfRange(dec("10.5")), description: "rpe 10.5"),
            InvalidRow(rest: 100, expected: .restOutOfRange(seconds: 100), description: "rest 100 (criterion 13)"),
            InvalidRow(rest: 315, expected: .restOutOfRange(seconds: 315), description: "rest 315"),
            InvalidRow(dropSets: 2, expected: .dropSetsOutOfRange(2), description: "drop sets 2"),
            InvalidRow(startLoad: .pounds(-5), expected: .negativeStartLoad(.pounds(-5)), description: "start −5 lb"),
            InvalidRow(step: .zero, expected: .nonPositiveStep(.zero), description: "step 0")
        ]
    }

    @Test("Each invalid range throws its own SlotValidationError case (criterion 13)", arguments: InvalidRow.all)
    func init_invalidRange_throwsMatchingCase(row: InvalidRow) {
        #expect(throws: row.expected) {
            try row.make()
        }
    }

    @Test("The boundaries of every range are accepted (rules 1–3, 6)")
    func init_boundaries_areValid() throws {
        let low = try Fixtures.slot(
            Fixtures.bench,
            id: 1,
            sets: 1,
            reps: 1,
            repsHi: 2,
            rpe: 5,
            rest: 30,
            startLoad: .zero
        )
        let high = try Fixtures.slot(
            Fixtures.bench,
            id: 2,
            sets: 12,
            reps: 30,
            repsHi: 40,
            rpe: 10,
            rest: 300,
            dropSets: 1
        )
        #expect(low.sets == 1 && low.reps == 1 && low.repsHi == 2 && low.rest.seconds == 30)
        #expect(high.sets == 12 && high.reps == 30 && high.repsHi == 40 && high.dropSets == 1)
        #expect(try high.rpe == (Fixtures.rpe(10)))
    }

    @Test("A slot round-trips through JSON")
    func codable_roundTrips() throws {
        let slot = try Fixtures.slot(
            Fixtures.inclineDB, id: 7, sets: 3, reps: 10, repsHi: 12, rpe: 8.5, rest: 75,
            progression: .double, startLoad: .pounds(50), step: .pounds(2.5), superset: true, misses: [1, 4]
        )
        let data = try JSONEncoder().encode(slot)
        #expect(try JSONDecoder().decode(Slot.self, from: data) == slot)
    }

    @Test("Decoding re-validates ranges")
    func decoding_invalidRange_throws() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 8, sets: 5, reps: 5)
        let json = try Fixtures.json(slot)
        let tampered = json.replacingOccurrences(of: #""sets":5"#, with: #""sets":13"#)
        #expect(tampered != json)
        #expect(throws: SlotValidationError.setsOutOfRange(13)) {
            try JSONDecoder().decode(Slot.self, from: Data(tampered.utf8))
        }
    }
}
