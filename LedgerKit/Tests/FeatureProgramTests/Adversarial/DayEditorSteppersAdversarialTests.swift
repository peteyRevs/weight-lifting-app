@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: the six steppers, pressed (criterion 4 of the slice; criterion 8 of the brief;
/// product spec §7.1 rules 1 to 3 and 6; decisions #9 and #22). The expected values come from a counter the
/// tester keeps by the brief's limits, never from the feature. Seeds 1 to 12, 250 presses each.
@Suite("Adversarial F11 S6 · the steppers, pressed", .tags(.feature))
nonisolated struct DayEditorSteppersAdversarialTests {
    /// One slot of `exercise` on a day of its own, open.
    static func input(
        exercise: Int = 1,
        units: Units = .lb,
        progression: Progression = .double,
        startLoad: Weight? = .pounds(50),
        step: Weight? = nil,
        rpe: Decimal = 8
    ) throws -> DayEditorInput {
        let slot = try Slot(
            id: SlotID(Fixtures.uuid(51000)), exerciseID: AdvDay.exercise(exercise).id, sets: 3, reps: 10,
            repsHi: 12, rpe: rpe, restSeconds: 90, progression: progression, startLoad: startLoad, step: step
        )
        let day = AdvProgram.day(1, slots: [slot])
        let program = try AdvProgram.program(weeks: 4, days: [day])
        return AdvDay.input(program, day: day.id, exercises: AdvDay.stored(), units: units, open: slot.id)
    }

    static func press(_ kind: SlotField.Kind, plus: Bool, _ input: DayEditorInput) throws -> DayEditorInput {
        let field = try #require(AdvDay.field(kind, input))
        return AdvDay.apply(plus ? field.increment : field.decrement, to: input).input
    }

    /// A load of `quarters` quarter units, as the brief prints one: "52.5", never "52.50".
    static func text(quarters: Int) -> String {
        "\(quarters / 4)\(["", ".25", ".5", ".75"][quarters % 4])"
    }

    /// The tester's counter: the brief's limits and coupling (criterion 8).
    struct Counter {
        var sets = 3
        var reps = 10
        var top = 12
        var halfRPE = 16
        var rest = 90
        var steps: Int
        let quartersAStep: Int

        mutating func press(_ kind: SlotField.Kind, plus: Bool) {
            let delta = plus ? 1 : -1
            switch kind {
            case .sets: sets = Swift.min(12, Swift.max(1, sets + delta))
            case .reps:
                reps = Swift.min(30, Swift.max(1, reps + delta))
                top = reps >= top ? reps + 1 : top
            case .repsHi:
                top = Swift.min(40, Swift.max(2, top + delta))
                top = top <= reps ? reps + 1 : top
            case .rpe: halfRPE = Swift.min(20, Swift.max(10, halfRPE + delta))
            case .rest: rest = Swift.min(300, Swift.max(30, rest + 15 * delta))
            case .startLoad: steps = Swift.max(0, steps + delta)
            }
        }

        func values(unit: String) -> [String] {
            let restText = rest < 60 ? "\(rest)s" : (rest % 60 == 0 ? "\(rest / 60) min" : "\(rest / 60):\(rest % 60)")
            let rpe = halfRPE.isMultiple(of: 2) ? "\(halfRPE / 2)" : "\(halfRPE / 2).5"
            let load = DayEditorSteppersAdversarialTests.text(quarters: steps * quartersAStep)
            return ["\(sets)", "\(reps)", "\(top)", "\(load) \(unit)", rpe, restText]
        }
    }

    @Test(
        "Any run of presses draws what the brief's limits and coupling give",
        arguments: 1 ... 12 as ClosedRange<UInt64>
    )
    func anyRunOfPresses_drawsTheBriefsValues(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let isKilograms = seed.isMultiple(of: 2)
        // A dumbbell lift: 50 lb by 2.5 lb, or 20 kg by 1.25 kg.
        var input = try Self.input(
            units: isKilograms ? .kg : .lb,
            startLoad: isKilograms ? .kilograms(20) : .pounds(50)
        )
        var counter = Counter(steps: isKilograms ? 16 : 20, quartersAStep: isKilograms ? 5 : 10)
        var wrong: [String] = []
        for press in 0 ..< 250 {
            let kind = SlotField.Kind.allCases[Int.random(in: 0 ..< 6, using: &rng)]
            // Runs in one direction, so that every limit is reached.
            let plus = (press / 25 + Int(seed)).isMultiple(of: 2) ? Int.random(in: 0 ... 4, using: &rng) > 0
                : Int.random(in: 0 ... 4, using: &rng) == 0
            input = try Self.press(kind, plus: plus, input)
            counter.press(kind, plus: plus)
            let fields = try #require(AdvDay.panel(input)?.details).fields
            let expected = counter.values(unit: isKilograms ? "kg" : "lb")
            if fields.map(\.value) != expected {
                wrong.append("press \(press) \(kind) \(plus ? "+" : "−"): \(fields.map(\.value)) is not \(expected)")
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(3))")
        let row = try #require(AdvDay.rows(input).first)
        #expect(row.sub.contains("Reps \(counter.reps)–\(counter.top)"))
    }

    @Test("At each limit both buttons are offered and the value holds: sets 1 and 12, RPE 5 and 10, rest 30s and 5 min")
    func everyLimit_holdsTheValue() throws {
        let down: [(SlotField.Kind, String)] = [
            (.sets, "1"), (.reps, "1"), (.rpe, "5"), (.rest, "30s"), (.startLoad, "0 lb")
        ]
        let upward: [(SlotField.Kind, String)] = [
            (.sets, "12"), (.reps, "30"), (.repsHi, "40"), (.rpe, "10"), (.rest, "5 min")
        ]
        for (place, (kind, text)) in (down + upward).enumerated() {
            let plus = place >= down.count
            var input = try Self.input()
            for _ in 0 ..< 45 {
                input = try Self.press(kind, plus: plus, input)
            }
            #expect(AdvDay.field(kind, input)?.value == text, "\(kind)")
            let held = try Self.press(kind, plus: plus, input)
            let isHeld = held.program == input.program
            #expect(isHeld, "\(kind)")
        }
        var input = try Self.input()
        for _ in 0 ..< 45 {
            input = try Self.press(.reps, plus: true, input)
        }
        #expect(AdvDay.field(.repsHi, input)?.value == "31")
        input = try Self.press(.repsHi, plus: false, input)
        #expect(AdvDay.field(.repsHi, input)?.value == "31")
        #expect(AdvDay.field(.reps, input)?.value == "30")
    }
}

nonisolated extension DayEditorSteppersAdversarialTests {
    @Test("The start load steps by the equipment's step in the lifter's unit", arguments: [
        (0, Units.lb, "5 lb"), (1, .lb, "2.5 lb"), (2, .lb, "2.5 lb"), (3, .lb, "2.5 lb"), (4, .lb, "2.5 lb"),
        (5, .lb, "5 lb"), (6, .lb, "2.5 lb"), (0, .kg, "2.5 kg"), (1, .kg, "1.25 kg"), (2, .kg, "1.25 kg"),
        (3, .kg, "1.25 kg"), (4, .kg, "1.25 kg"), (5, .kg, "2 kg"), (6, .kg, "1.25 kg")
    ])
    func startLoad_stepsByTheEquipmentsStep(exercise: Int, units: Units, step: String) throws {
        var input = try Self.input(exercise: exercise, units: units, progression: .linear, startLoad: .zero)
        let unit = units == .lb ? "lb" : "kg"
        #expect(AdvDay.field(.startLoad, input)?.value == "0 \(unit)")
        #expect(AdvDay.panel(input)?.details?.progression.note
            == "Adds \(step) a week from 0 \(unit). A week with a missed set holds the load.")
        #expect(AdvDay.rows(input).first?.sub.contains("· +\(step.dropLast(3))/wk ·") == true)
        input = try Self.press(.startLoad, plus: true, input)
        #expect(AdvDay.field(.startLoad, input)?.value == step)
        #expect(AdvDay.rows(input).first?.load == step)
        input = try Self.press(.startLoad, plus: false, input)
        input = try Self.press(.startLoad, plus: false, input)
        #expect(AdvDay.field(.startLoad, input)?.value == "0 \(unit)")
    }

    @Test("A slot's own step wins over the equipment's, and a load off the steps goes to the next multiple")
    func ownStepAndOffStepLoad_areSteppedAsTheDomainSteps() throws {
        var input = try Self.input(exercise: 0, units: .kg, progression: .linear, startLoad: .pounds(180))
        #expect(AdvDay.field(.startLoad, input)?.value == "81.6 kg")
        #expect(AdvDay.rows(input).first?.load == "81.6 kg")
        #expect(try AdvDay.field(.startLoad, Self.press(.startLoad, plus: true, input))?.value == "82.5 kg")
        #expect(try AdvDay.field(.startLoad, Self.press(.startLoad, plus: false, input))?.value == "80 kg")
        input = try Self.input(exercise: 1, progression: .linear, startLoad: .pounds(50), step: .pounds(10))
        #expect(AdvDay.panel(input)?.details?.strip.text == "W1 50 · W2 60 · W3 70 · W4 80")
        #expect(AdvDay.rows(input).first?.sub == "Dumbbell · +10/wk · RPE 8 · 1:30 rest")
        #expect(try AdvDay.field(.startLoad, Self.press(.startLoad, plus: true, input))?.value == "60 lb")
    }

    @Test("A hundred steps up and a hundred down give the load back to the digit, in pounds and in kilograms")
    func manyStepsUpAndDown_areExact() throws {
        for (units, top) in [(Units.lb, "302.5 lb"), (.kg, "148.75 kg")] {
            var input = try Self.input(units: units, startLoad: .pounds(52.5))
            #expect(AdvDay.field(.startLoad, input)?.value == (units == .lb ? "52.5 lb" : "23.8 kg"))
            for _ in 0 ..< 100 {
                input = try Self.press(.startLoad, plus: true, input)
            }
            #expect(AdvDay.field(.startLoad, input)?.value == top)
            for _ in 0 ..< 100 {
                input = try Self.press(.startLoad, plus: false, input)
            }
            #expect(AdvDay.field(.startLoad, input)?.value == (units == .lb ? "52.5 lb" : "23.75 kg"))
        }
    }

    @Test("A very large load and a half RPE are drawn whole: 1000000 lb, RPE 8.5")
    func largeLoadAndHalfRPE_areDrawnWhole() throws {
        let input = try Self.input(exercise: 0, progression: .linear, startLoad: .pounds(1_000_000), rpe: 8.5)
        let details = try #require(AdvDay.panel(input)?.details)
        #expect(details.fields.map(\.value) == ["3", "10", "1000000 lb", "8.5", "1:30"])
        #expect(details.week.line == "3 × 10 @ 1000000 lb · RPE 8.5")
        #expect(details.strip.text == "W1 1000000 · W2 1000005 · W3 1000010 · W4 1000015")
        #expect(details.progression
            .note == "Adds 5 lb a week from 1000000 lb. A week with a missed set holds the load.")
        let row = try #require(AdvDay.rows(input).first)
        #expect(row.sub == "Barbell · +5/wk · RPE 8.5 · 1:30 rest")
        #expect(row.load == "1000000 lb")
        #expect(try AdvDay.field(.rpe, Self.press(.rpe, plus: false, input))?.value == "8")
    }
}
