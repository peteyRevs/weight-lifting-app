import Foundation
@testable import LedgerDomain
import Testing

/// One invalid slot input and the `SlotValidationError` the brief's ranges (rules 1–3, 6) demand.
struct InvalidSlotCase: Sendable, CustomStringConvertible {
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

    static let all: [Self] = [
        Self(sets: 13, expected: .setsOutOfRange(13), description: "sets 13"),
        Self(sets: 0, expected: .setsOutOfRange(0), description: "sets 0"),
        Self(sets: -1, expected: .setsOutOfRange(-1), description: "sets -1"),
        Self(reps: 0, expected: .repsOutOfRange(0), description: "reps 0"),
        Self(reps: 31, repsHi: 40, expected: .repsOutOfRange(31), description: "reps 31"),
        Self(reps: 1, repsHi: 1, expected: .repsHiOutOfRange(1), description: "repsHi 1"),
        Self(repsHi: 41, expected: .repsHiOutOfRange(41), description: "repsHi 41"),
        Self(reps: 10, repsHi: 10, expected: .repsHiNotAboveReps(reps: 10, repsHi: 10), description: "repsHi == reps"),
        Self(reps: 12, repsHi: 9, expected: .repsHiNotAboveReps(reps: 12, repsHi: 9), description: "repsHi < reps"),
        Self(
            reps: 30,
            repsHi: 30,
            expected: .repsHiNotAboveReps(reps: 30, repsHi: 30),
            description: "reps 30 = repsHi"
        ),
        Self(rpe: dec("4.75"), expected: .rpeOutOfRange(dec("4.75")), description: "rpe 4.75"),
        Self(rpe: dec("4.5"), expected: .rpeOutOfRange(dec("4.5")), description: "rpe 4.5"),
        Self(rpe: dec("10.5"), expected: .rpeOutOfRange(dec("10.5")), description: "rpe 10.5"),
        Self(rpe: dec("7.25"), expected: .rpeOutOfRange(dec("7.25")), description: "rpe 7.25"),
        Self(rest: 100, expected: .restOutOfRange(seconds: 100), description: "rest 100"),
        Self(rest: 15, expected: .restOutOfRange(seconds: 15), description: "rest 15"),
        Self(rest: 315, expected: .restOutOfRange(seconds: 315), description: "rest 315"),
        Self(dropSets: 2, expected: .dropSetsOutOfRange(2), description: "drop 2"),
        Self(dropSets: -1, expected: .dropSetsOutOfRange(-1), description: "drop -1"),
        Self(startLoad: Weight(grams: -1), expected: .negativeStartLoad(Weight(grams: -1)), description: "start -1 g"),
        Self(step: .zero, expected: .nonPositiveStep(.zero), description: "step 0"),
        Self(step: pounds("-5"), expected: .nonPositiveStep(pounds("-5")), description: "step -5 lb")
    ]

    func make() throws -> Slot {
        try Slot(
            id: SlotID(Fixtures.uuid(700)),
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
}

@Suite("Slot (adversarial)", .tags(.domain))
struct SlotAdversarialTests {
    static func valid() throws -> Slot {
        try Fixtures.slot(
            Fixtures.bench,
            id: 701,
            sets: 5,
            reps: 5,
            repsHi: 8,
            rpe: dec("8.5"),
            rest: 150,
            startLoad: pounds("185"),
            step: pounds("5"),
            superset: true,
            dropSets: 1,
            misses: [1, 4]
        )
    }

    static func decode(_ data: Data) throws -> Slot {
        try JSONDecoder().decode(Slot.self, from: data)
    }
}

extension SlotAdversarialTests {
    @Test(
        "Each out-of-range input throws its matching SlotValidationError (criterion 13).",
        arguments: InvalidSlotCase.all
    )
    func init_outOfRange_throwsMatchingCase(row: InvalidSlotCase) {
        #expect(throws: row.expected) { try row.make() }
    }

    @Test("The range boundaries themselves are accepted (rules 2, 3, 6).")
    func init_boundaries_areAccepted() throws {
        let edges = [
            InvalidSlotCase(
                sets: 1,
                reps: 1,
                repsHi: 2,
                rpe: 5,
                rest: 30,
                expected: .setsOutOfRange(0),
                description: "low"
            ),
            InvalidSlotCase(
                sets: 12, reps: 30, repsHi: 40, rpe: 10, rest: 300, dropSets: 1, startLoad: .zero,
                expected: .setsOutOfRange(0), description: "high"
            )
        ]
        for edge in edges {
            #expect(throws: Never.self) { try edge.make() }
        }
    }

    @Test("Several violations report the first in the documented order (sets before reps before rest).")
    func init_multipleViolations_reportsFirst() {
        let row = InvalidSlotCase(
            sets: 13,
            reps: 0,
            repsHi: 0,
            rest: 100,
            expected: .setsOutOfRange(13),
            description: ""
        )
        #expect(throws: SlotValidationError.setsOutOfRange(13)) { try row.make() }
    }

    @Test("A valid slot survives a Codable round-trip unchanged.")
    func codable_roundTrip_isIdentity() throws {
        let slot = try Self.valid()
        #expect(try Adversarial.roundTrip(slot) == slot)
    }

    @Test(
        "Tampered JSON with an out-of-range field is rejected on decode.",
        arguments: [
            ("sets", 13), ("sets", 0), ("reps", 0), ("repsHi", 5), ("repsHi", 41),
            ("rpe", 4.75), ("rpe", 7.25), ("rest", 100), ("rest", 15), ("dropSets", 2)
        ] as [(String, Double)]
    )
    func decode_tamperedField_throws(key: String, value: Double) throws {
        let data = try Adversarial.tampered(Self.valid()) { $0[key] = value }
        #expect(throws: (any Error).self) { try Self.decode(data) }
    }

    @Test("Tampered JSON with a negative start load or a zero step is rejected on decode.")
    func decode_tamperedWeights_throw() throws {
        let negative = try Adversarial
            .tampered(Self.valid()) { $0["startLoad"] = try Adversarial.fragment(Weight(grams: -5)) }
        #expect(throws: (any Error).self) { try Self.decode(negative) }
        let zeroStep = try Adversarial.tampered(Self.valid()) { $0["step"] = try Adversarial.fragment(Weight.zero) }
        #expect(throws: (any Error).self) { try Self.decode(zeroStep) }
    }

    @Test("Untampered JSON with optional loads removed still decodes, with nil loads.")
    func decode_withoutOptionalLoads_decodesNil() throws {
        let data = try Adversarial.tampered(Self.valid()) {
            $0["startLoad"] = nil
            $0["step"] = nil
        }
        let slot = try Self.decode(data)
        #expect(slot.startLoad == nil)
        #expect(slot.step == nil)
        #expect(slot.misses == [1, 4])
    }
}
