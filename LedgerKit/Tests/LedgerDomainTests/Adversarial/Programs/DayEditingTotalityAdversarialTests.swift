import Foundation
@testable import LedgerDomain
import Testing

#if os(macOS)
    /// Slice criterion 1, "never traps", for the Day editor: each attack runs in a child process, so a trap
    /// fails one test instead of ending the run. A slot's numbers are `var` and can hold any `Int`, a
    /// `Weight` any `Decimal`, and a day any list of slots, so these drive values no screen sends as well.
    @Suite("DayEditing never traps (adversarial)", .tags(.domain))
    struct DayEditingTotalityAdversarialTests {
        static let extremes = [Int.min, Int.min + 1, -1, 0, 1, Int.max - 1, Int.max]
        static let decimals: [Decimal] = [
            .nan, .greatestFiniteMagnitude, -Decimal.greatestFiniteMagnitude, .leastNonzeroMagnitude,
            -Decimal.leastNonzeroMagnitude, 0, -1
        ]

        /// Every field set to every extreme value.
        static let fields: [SlotField] = extremes.flatMap { value -> [SlotField] in
            [.sets(value), .reps(value), .repsHi(value), .restSeconds(value)]
        } + decimals.flatMap { value -> [SlotField] in
            [.rpe(value), .startLoad(Weight(grams: value))]
        }

        /// Every `DayEditing` function on every slot of `day` and on a slot it does not hold, a stepper
        /// button for every field in both directions among them. Returns every result.
        static func everyEdit(of day: DayTemplate, exercise: Exercise = Fixtures.bench) -> [DayTemplate] {
            var results = [DayEditing.addSlots(day, day.slots), DayEditing.addSlots(day, [])]
            for slot in day.slots.map(\.id) + [EditAdv.slotID(999)] {
                results.append(DayEditing.removeSlot(day, slot: slot))
                results += fields.map { DayEditing.set($0, slot: slot, in: day) }
                results += Progression.allCases.map { DayEditing.setProgression($0, slot: slot, in: day) }
                results += [true, false].map { DayEditing.setDropSet($0, slot: slot, in: day) }
                results += [true, false].map { DayEditing.setSuperset($0, slot: slot, in: day) }
                results += [MoveDirection.upward, .downward].map { DayEditing.move(day, slot: slot, $0) }
            }
            for slot in day.slots {
                results += pressed(every: slot, in: day, exercise: exercise)
            }
            return results + [DayTemplate(id: day.id, name: "\(DayEditing.groups(of: day).count)", tag: day.tag)]
        }

        /// `set(stepped(…))` for every field, both directions, both units.
        static func pressed(every slot: Slot, in day: DayTemplate, exercise: Exercise) -> [DayTemplate] {
            SlotField.Kind.allCases.flatMap { kind in
                Units.allCases.flatMap { units in
                    [StepDirection.upward, .downward].map { direction in
                        let field = DayEditing.stepped(kind, direction, of: slot, exercise: exercise, units: units)
                        return DayEditing.set(field, slot: slot.id, in: day)
                    }
                }
            }
        }

        /// A day of `flags.count` slots with each of these numbers written straight into its fields.
        static func mutated(_ value: Int, flags: [Bool]) throws -> DayTemplate {
            var day = try EditAdv.day(flags: flags)
            for place in day.slots.indices {
                day.slots[place].sets = value
                day.slots[place].reps = value
                day.slots[place].repsHi = value
                day.slots[place].dropSets = value
            }
            return day
        }
    }

    extension DayEditingTotalityAdversarialTests {
        @Test("Every field set to Int.min, Int.max, NaN and the largest decimals gives a slot Slot.init accepts.")
        func set_extremeValues_giveAnAcceptedSlot() async {
            await #expect(processExitsWith: .success) {
                let day = try EditAdv.day(flags: [false, true, false])
                let slot = EditAdv.slotID(5001)
                let rejected = Self.fields
                    .contains { EditAdv.rejection(of: DayEditing.set($0, slot: slot, in: day).slots) != nil }
                exit(rejected ? 1 : 0)
            }
        }

        @Test(
            "Int.min and Int.max are held at the limits: sets 1 and 12, reps 1 and 30, top 2 and 40, rest 30 and 300."
        )
        func set_extremeWholeNumbers_areHeldAtTheLimits() async {
            await #expect(processExitsWith: .success) {
                let slot = try Fixtures.slot(Fixtures.bench, id: 1, reps: 1, repsHi: 2)
                let day = DayTemplate(id: EditAdv.dayID(4000), name: "Upper A", tag: "UA", slots: [slot])
                func after(_ field: SlotField) -> Slot {
                    DayEditing.set(field, slot: slot.id, in: day).slots[0]
                }
                let low = [
                    after(.sets(.min)).sets,
                    after(.reps(.min)).reps,
                    after(.repsHi(.min)).repsHi,
                    after(.restSeconds(.min)).rest.seconds
                ]
                let high = [
                    after(.sets(.max)).sets,
                    after(.reps(.max)).reps,
                    after(.reps(.max)).repsHi,
                    after(.repsHi(.max)).repsHi,
                    after(.restSeconds(.max)).rest.seconds
                ]
                exit(low == [1, 1, 2, 30] && high == [12, 30, 31, 40, 300] ? 0 : 1)
            }
        }

        @Test(
            "The clamping initializers of RPE and RestDuration hold NaN, the largest decimals and both ends of Int."
        )
        func clampingInitializers_extremes_areInRange() async {
            await #expect(processExitsWith: .success) {
                let rates = Self.decimals.map { RPE(clamping: $0).value }
                let expected: [Decimal] = [5, 10, 5, 5, 5, 5, 5]
                let rests = Self.extremes.map { RestDuration(clampingSeconds: $0).seconds }
                exit(rates == expected && rests == [30, 30, 30, 30, 30, 300, 300] ? 0 : 1)
            }
        }

        @Test(
            "Two rounds of every edit, extreme values among them, on days of no slot, one slot and five never trap."
        )
        func everyEdit_onValidDays_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let days = try [[], [false], [true], [false, true, true, false, true]]
                    .map { try EditAdv.day(flags: $0) }
                let second = days.flatMap { Self.everyEdit(of: $0) }.flatMap { Self.everyEdit(of: $0) }
                exit(second.isEmpty ? 1 : 0)
            }
        }

        @Test(
            "Slots holding Int.min, Int.max, 0 and −1 in sets, reps, top and drop sets survive every edit and stepper."
        )
        func everyEdit_onSlotsWithExtremeNumbers_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let days = try Self.extremes.map { try Self.mutated($0, flags: [false, true]) }
                exit(days.flatMap { Self.everyEdit(of: $0) }.isEmpty ? 1 : 0)
            }
        }

        @Test("A day holding one slot id two and three times survives every edit.")
        func everyEdit_onADayWithOneSlotIDTwice_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let day = try EditAdv.day(flags: [false, true, false])
                let twin = DayTemplate(
                    id: day.id,
                    name: day.name,
                    tag: day.tag,
                    slots: day.slots + day.slots + [day.slots[1]]
                )
                let second = Self.everyEdit(of: twin).flatMap { Self.everyEdit(of: $0) }
                exit(second.isEmpty ? 1 : 0)
            }
        }

        @Test(
            "Loads and steps of NaN, zero, below zero and the largest decimals, in slot or exercise, survive a press."
        )
        func pressed_oddLoadsAndSteps_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                var count = 0
                let weights = Self.decimals.map { Weight?.some(Weight(grams: $0)) } + [nil]
                for exerciseLoad in weights {
                    let loads = exerciseLoad.map { [Units.lb: $0] } ?? [:]
                    let exercise = Adversarial.catalogExercise(900, .kettlebell, loads: loads)
                    for load in weights {
                        for step in weights {
                            var day = try EditAdv.day(flags: [false])
                            day.slots[0].startLoad = load
                            day.slots[0].step = step
                            count += Self.pressed(every: day.slots[0], in: day, exercise: exercise).count
                        }
                    }
                }
                exit(count == 8 * 8 * 8 * 24 ? 0 : 1)
            }
        }

        @Test("A start-load stepper never asks for a load below zero, however far below zero the slot's load is.")
        func stepped_fromALoadBelowZero_isNeverBelowZero() async {
            await #expect(processExitsWith: .success) {
                var slot = try EditAdv.distinctSlot(0, id: 5000, joined: false)
                var belowZero = 0
                for hundredths in stride(from: -2000, through: 2000, by: 25) {
                    slot.startLoad = EditAdv.weight(fine: EditAdv.fine(hundredths: hundredths, .lb))
                    for direction in [StepDirection.upward, .downward] {
                        let field = DayEditing.stepped(
                            .startLoad,
                            direction,
                            of: slot,
                            exercise: Fixtures.bench,
                            units: .kg
                        )
                        if case let .startLoad(weight) = field, weight >= .zero {
                            continue
                        }
                        belowZero += 1
                    }
                }
                exit(belowZero == 0 ? 0 : 1)
            }
        }
    }
#endif
