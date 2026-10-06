import Foundation
@testable import LedgerDomain
import Testing

/// Slice criteria 7 and 8, exhaustively: every value of every field through `set`, far outside its range;
/// the clamp and then the coupling for every pair of reps and top of range; steppers at both ends of each
/// range; double progression from every pair. Expected values are `EditAdv`'s whole-number references.
@Suite("DayEditing fields (adversarial)", .tags(.domain))
struct DayEditingFieldsAdversarialTests {
    static let slot = EditAdv.slotID(1)

    /// Every pair `Slot.init` accepts: reps 1…30, top of range above it up to 40. 735 pairs.
    static let pairs: [(reps: Int, top: Int)] = (1 ... 30).flatMap { reps in
        (reps + 1 ... 40).map { (reps: reps, top: $0) }
    }

    static func day(reps: Int = 8, top: Int = 10, progression: Progression = .linear) throws -> DayTemplate {
        let bench = try Fixtures.slot(Fixtures.bench, id: 1, reps: reps, repsHi: top, progression: progression)
        return DayTemplate(id: EditAdv.dayID(4000), name: "Upper A", tag: "UA", slots: [bench])
    }

    /// The day's one slot after `field` is set, with the slot it was, to see what else changed.
    static func edited(_ field: SlotField, in day: DayTemplate) -> Slot? {
        DayEditing.set(field, slot: slot, in: day).slots.first
    }

    /// Whether `edited` is `original` with only `change` applied.
    static func isOnly(_ edited: Slot?, _ original: Slot, _ change: (inout Slot) -> Void) -> Bool {
        var expected = original
        change(&expected)
        return edited == expected
    }
}

// MARK: - Reps and the top of the range

extension DayEditingFieldsAdversarialTests {
    @Test(
        "Reps set to every value from −5 to 50, from every pair of reps and top: clamped to 1…30, the top kept above."
    )
    func setReps_everyValueFromEveryPair_clampsThenCouples() throws {
        var tally = Tally()
        for pair in Self.pairs {
            let day = try Self.day(reps: pair.reps, top: pair.top)
            let original = try #require(day.slots.first)
            for value in -5 ... 50 {
                let reps = EditAdv.clamped(value, 1, 30)
                let top = pair.top > reps ? pair.top : reps + 1
                let holds = Self.isOnly(Self.edited(.reps(value), in: day), original) {
                    $0.reps = reps
                    $0.repsHi = top
                }
                tally.check(holds, "reps \(pair.reps), top \(pair.top), set reps \(value): expected \(reps) and \(top)")
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 735 * 56)
    }

    @Test(
        "The top set to every value from −5 to 50, from every pair: clamped to 2…40, then reps + 1 when not above reps."
    )
    func setRepsHi_everyValueFromEveryPair_clampsThenCouples() throws {
        var tally = Tally()
        for pair in Self.pairs {
            let day = try Self.day(reps: pair.reps, top: pair.top)
            let original = try #require(day.slots.first)
            for value in -5 ... 50 {
                let clamped = EditAdv.clamped(value, 2, 40)
                let top = clamped > pair.reps ? clamped : pair.reps + 1
                let holds = Self.isOnly(Self.edited(.repsHi(value), in: day), original) { $0.repsHi = top }
                tally.check(holds, "reps \(pair.reps), top \(pair.top), set top \(value): expected \(top)")
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 735 * 56)
    }

    @Test("Double progression from every pair makes the top max(top, reps + 2); Linear and Fixed leave it.")
    func setProgression_fromEveryPair_keepsOrRaisesTheTop() throws {
        var tally = Tally()
        for pair in Self.pairs {
            for from in Progression.allCases {
                let day = try Self.day(reps: pair.reps, top: pair.top, progression: from)
                let original = try #require(day.slots.first)
                for target in Progression.allCases {
                    let top = target == .double ? max(pair.top, pair.reps + 2) : pair.top
                    let edited = DayEditing.setProgression(target, slot: Self.slot, in: day).slots.first
                    let holds = Self.isOnly(edited, original) {
                        $0.progression = target
                        $0.repsHi = top
                    }
                    let valid = edited.map { EditAdv.rejection(of: $0) == nil } ?? false
                    tally.check(
                        holds && valid,
                        "reps \(pair.reps), top \(pair.top), \(from) to \(target): expected top \(top)"
                    )
                }
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 735 * 9)
    }
}

// MARK: - Sets, RPE, rest

extension DayEditingFieldsAdversarialTests {
    @Test("Sets set to every value from −1,000 to 1,000 is held to 1…12 and nothing else changes.")
    func setSets_everyValue_clamps() throws {
        let day = try Self.day()
        let original = try #require(day.slots.first)
        var tally = Tally()
        for value in -1000 ... 1000 {
            let sets = EditAdv.clamped(value, 1, 12)
            tally.check(Self.isOnly(Self.edited(.sets(value), in: day), original) { $0.sets = sets }, "sets \(value)")
        }
        #expect(tally.passed, tally.summary)
    }

    @Test("Rest set to every second from −1,000 to 1,000 is held to 30…300 and goes to the nearest 15.")
    func setRest_everySecond_clampsToTheFifteen() throws {
        let day = try Self.day()
        var tally = Tally()
        for value in -1000 ... 1000 {
            let seconds = Self.edited(.restSeconds(value), in: day)?.rest.seconds
            tally.check(seconds == EditAdv.referenceRest(value), "rest \(value) gave \(seconds ?? -1)")
        }
        #expect(tally.passed, tally.summary)
        #expect([37, 38, 52, 53, 292, 293].map(EditAdv.referenceRest) == [30, 45, 45, 60, 285, 300])
    }

    @Test("RPE set to every hundredth from −2 to 15 is held to 5…10 on the nearest half.")
    func setRPE_everyHundredth_clampsToTheHalf() throws {
        let day = try Self.day()
        var tally = Tally()
        for hundredths in -200 ... 1500 where !EditAdv.isRPETie(hundredths: hundredths) {
            let value = Self.edited(.rpe(EditAdv.decimal(hundredths: hundredths)), in: day)?.rpe.value
            let expected = EditAdv.rpe(halves: EditAdv.referenceRPEHalves(hundredths: hundredths))
            tally.check(value == expected, "RPE \(hundredths)/100 gave \(value ?? -1), expected \(expected)")
        }
        #expect(tally.passed, tally.summary)
    }

    @Test(
        "An RPE half way between two halves goes up, as RPE(clamping:) declares: 5.25 to 5.5, 7.25 to 7.5, 9.75 to 10."
    )
    func setRPE_halfWay_goesUp() throws {
        let day = try Self.day()
        var tally = Tally()
        for hundredths in stride(from: 25, through: 1475, by: 50) {
            let value = Self.edited(.rpe(EditAdv.decimal(hundredths: hundredths)), in: day)?.rpe.value
            let expected = EditAdv.rpe(halves: EditAdv.referenceRPEHalves(hundredths: hundredths))
            tally.check(value == expected, "RPE \(hundredths)/100 gave \(value ?? -1), expected \(expected)")
        }
        #expect(tally.passed, tally.summary)
        #expect(Self.edited(.rpe(dec("4.75")), in: day)?.rpe.value == 5)
        #expect(Self.edited(.rpe(dec("5.25")), in: day)?.rpe.value == dec("5.5"))
        #expect(Self.edited(.rpe(dec("9.99")), in: day)?.rpe.value == 10)
        #expect(Self.edited(.rpe(dec("7.2499999999999999999")), in: day)?.rpe.value == 7)
        #expect(Self.edited(.rpe(dec("7.7500000000000000001")), in: day)?.rpe.value == 8)
    }

    @Test("The drop set is one or none, whatever it was, and setting it twice changes nothing more.")
    func setDropSet_isOneOrNone() throws {
        let day = try Self.day()
        let original = try #require(day.slots.first)
        let once = DayEditing.setDropSet(true, slot: Self.slot, in: day)
        #expect(Self.isOnly(once.slots.first, original) { $0.dropSets = 1 })
        let twice = DayEditing.setDropSet(true, slot: Self.slot, in: once) == once
        #expect(twice)
        let off = DayEditing.setDropSet(false, slot: Self.slot, in: once) == day
        #expect(off)
    }
}

// MARK: - Steppers at the ends of each range

extension DayEditingFieldsAdversarialTests {
    /// The slot after a stepper button: `set(stepped(…))`.
    static func pressed(_ kind: SlotField.Kind, _ direction: StepDirection, _ slot: Slot) -> Slot? {
        let day = DayTemplate(id: EditAdv.dayID(4000), name: "Upper A", tag: "UA", slots: [slot])
        let field = DayEditing.stepped(kind, direction, of: slot, exercise: Fixtures.bench, units: .lb)
        return DayEditing.set(field, slot: slot.id, in: day).slots.first
    }

    @Test("stepped gives the value one step away and does not clamp, at both ends of every whole-number range.")
    func stepped_atTheEnds_doesNotClamp() throws {
        let low = try Fixtures.slot(Fixtures.bench, id: 1, sets: 1, reps: 1, repsHi: 2, rpe: 5, rest: 30)
        let high = try Fixtures.slot(Fixtures.bench, id: 1, sets: 12, reps: 30, repsHi: 40, rpe: 10, rest: 300)
        let down = SlotField.Kind.allCases.dropLast().map {
            DayEditing.stepped($0, .downward, of: low, exercise: Fixtures.bench, units: .lb)
        }
        #expect(down == [.sets(0), .reps(0), .repsHi(1), .rpe(4.5), .restSeconds(15)])
        let above = SlotField.Kind.allCases.dropLast().map {
            DayEditing.stepped($0, .upward, of: high, exercise: Fixtures.bench, units: .lb)
        }
        #expect(above == [.sets(13), .reps(31), .repsHi(41), .rpe(10.5), .restSeconds(315)])
    }

    @Test("The exercise and the unit matter to the start load alone: the other steppers give the same field without.")
    func stepped_otherThanTheLoad_ignoresTheExerciseAndTheUnit() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 8, repsHi: 12, rpe: 7.5, rest: 120)
        let kettlebell = Adversarial.catalogExercise(900, .kettlebell, loads: [:])
        for kind in SlotField.Kind.allCases.dropLast() {
            for direction in [StepDirection.upward, .downward] {
                let pounds = DayEditing.stepped(kind, direction, of: slot, exercise: Fixtures.bench, units: .lb)
                let kilograms = DayEditing.stepped(kind, direction, of: slot, exercise: kettlebell, units: .kg)
                #expect(pounds == kilograms, "\(kind) \(direction)")
            }
        }
    }

    @Test(
        "A stepper at its limit leaves the slot as it is (behaviour 11), and one step inside the range moves one step."
    )
    func pressed_atTheLimit_staysAndInsideMoves() throws {
        let low = try Fixtures.slot(Fixtures.bench, id: 1, sets: 1, reps: 1, repsHi: 2, rpe: 5, rest: 30)
        let high = try Fixtures.slot(Fixtures.bench, id: 1, sets: 12, reps: 30, repsHi: 40, rpe: 10, rest: 300)
        for kind in SlotField.Kind.allCases.dropLast() {
            let atTheFloor = Self.pressed(kind, .downward, low) == low
            #expect(atTheFloor, "\(kind) down from the floor")
            let atTheCeiling = Self.pressed(kind, .upward, high) == high
            #expect(atTheCeiling, "\(kind) up from the ceiling")
        }
        let middle = try Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 8, repsHi: 12, rpe: 7.5, rest: 120)
        #expect(Self.isOnly(Self.pressed(.sets, .upward, middle), middle) { $0.sets = 6 })
        #expect(Self.isOnly(Self.pressed(.sets, .downward, middle), middle) { $0.sets = 4 })
        #expect(Self.isOnly(Self.pressed(.reps, .upward, middle), middle) { $0.reps = 9 })
        #expect(Self.isOnly(Self.pressed(.repsHi, .downward, middle), middle) { $0.repsHi = 11 })
        #expect(Self.pressed(.rpe, .upward, middle)?.rpe.value == 8)
        #expect(Self.pressed(.rpe, .downward, middle)?.rpe.value == 7)
        #expect(Self.pressed(.rest, .downward, middle)?.rest.seconds == 105)
    }

    @Test(
        "\"+\" on reps from every pair is reps + 1, the top pushed when reached; \"−\" on the top never reaches reps."
    )
    func pressed_repsAndTopFromEveryPair_keepTheTopAbove() throws {
        var tally = Tally()
        for pair in Self.pairs {
            let slot = try Fixtures.slot(Fixtures.bench, id: 1, reps: pair.reps, repsHi: pair.top)
            let reps = min(pair.reps + 1, 30)
            let raised = Self.isOnly(Self.pressed(.reps, .upward, slot), slot) {
                $0.reps = reps
                $0.repsHi = max(pair.top, reps + 1)
            }
            tally.check(raised, "reps up from \(pair.reps) and \(pair.top)")
            let lowered = Self.isOnly(Self.pressed(.repsHi, .downward, slot), slot) {
                $0.repsHi = max(pair.top - 1, pair.reps + 1)
            }
            tally.check(lowered, "top down from \(pair.reps) and \(pair.top)")
            let top = Self.isOnly(Self.pressed(.repsHi, .upward, slot), slot) { $0.repsHi = min(pair.top + 1, 40) }
            let floor = Self.isOnly(Self.pressed(.reps, .downward, slot), slot) { $0.reps = max(pair.reps - 1, 1) }
            tally.check(top && floor, "top up or reps down from \(pair.reps) and \(pair.top)")
        }
        #expect(tally.passed, tally.summary)
    }
}
