@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The random inputs of the Day editor's property suite.
nonisolated extension DayEditorPresentationPropertyTests {
    static let locales = ["en_US", "de_DE", "fr_FR", "ja_JP", "ar_EG", "hi_IN"]

    /// The exercises a random slot is drawn from: a barbell, a dumbbell, a machine, a cable, a bodyweight and a
    /// kettlebell exercise of the catalog.
    static func exercisePool() throws -> [Exercise] {
        try ["Back Squat", "Incline DB Press", "Leg Press", "Lat Pulldown", "Weighted Pull-Up", "Kettlebell Row"]
            .map(DayEditorFixtures.exercise(named:))
    }

    /// A random input: a block of 2 to 12 weeks, any of them a deload; one to four days, the edited one with 0
    /// to 8 slots at any values the model accepts, limits included; pounds or kilograms; one of six locales; a
    /// shown week from two before the block to two after it; an open slot that is one of the day's, none, or
    /// a stranger; now and then an exercise that is not stored. Unless `holdsTheDay`, one input in ten names a
    /// day the program does not hold.
    static func input(using generator: inout SeededGenerator, holdsTheDay: Bool = false) throws -> DayEditorInput {
        let pool = try exercisePool()
        let dayCount = Int.random(in: 1 ... 4, using: &generator)
        let edited = Int.random(in: 0 ..< dayCount, using: &generator)
        let days = try (0 ..< dayCount).map { number in
            try day(number, slotCount: Int.random(in: 0 ... 8, using: &generator), pool, using: &generator)
        }
        let weekCount = Int.random(in: 2 ... 12, using: &generator)
        var program = try ProgramFixtures.program(weekCount: weekCount, days: days)
        for place in program.weeks.indices {
            program.weeks[place].isDeload = Int.random(in: 0 ..< 4, using: &generator) == 0
            for weekday in Weekday.allCases where Int.random(in: 0 ..< 3, using: &generator) == 0 {
                program.weeks[place].schedule[weekday] = days.randomElement(using: &generator)?.id
            }
        }
        var input = try DayEditorFixtures.input(program, dayIndex: edited)
        input.weekIndex = Int.random(in: -2 ... weekCount + 1, using: &generator)
        input.settings.units = Units.allCases.randomElement(using: &generator) ?? .lb
        input.locale = Locale(identifier: locales.randomElement(using: &generator) ?? "en_US")
        let candidates: [SlotID?] = days[edited].slots.map(\.id) + [SlotID(Fixtures.uuid(99999)), nil]
        input.openSlot = candidates.randomElement(using: &generator) ?? nil
        if Int.random(in: 0 ..< 4, using: &generator) == 0 {
            input.exercises[pool[0].id] = nil
        }
        if !holdsTheDay, Int.random(in: 0 ..< 10, using: &generator) == 0 {
            input.day = DayTemplateID(Fixtures.uuid(99998))
        }
        return input
    }

    /// Day `number` with `slotCount` random slots. A slot's numbers are drawn from its whole range, the ends
    /// often; its start load is absent, on a step or off it, in either unit; any week may be a miss; the first
    /// slot's superset flag is random too, which the Domain reads as false.
    static func day(
        _ number: Int,
        slotCount: Int,
        _ pool: [Exercise],
        using generator: inout SeededGenerator
    ) throws -> DayTemplate {
        let loads: [Weight?] = [nil, .zero, .pounds(180), .pounds(52.5), .kilograms(81), .kilograms(22.5)]
        let slots = try (0 ..< slotCount).map { index in
            let reps = [1, 30, Int.random(in: 1 ... 30, using: &generator)].randomElement(using: &generator) ?? 8
            let repsHi = [reps + 1, 40, Int.random(in: reps + 1 ... 40, using: &generator)]
                .randomElement(using: &generator) ?? reps + 2
            return try Slot(
                id: SlotID(Fixtures.uuid(2000 + number * 10 + index)),
                exerciseID: (pool.randomElement(using: &generator) ?? pool[0]).id,
                sets: [1, 12, Int.random(in: 1 ... 12, using: &generator)].randomElement(using: &generator) ?? 3,
                reps: reps,
                repsHi: repsHi,
                rpe: Decimal(Int.random(in: 10 ... 20, using: &generator)) / 2,
                restSeconds: 15 * Int.random(in: 2 ... 20, using: &generator),
                progression: Progression.allCases.randomElement(using: &generator) ?? .linear,
                startLoad: loads.randomElement(using: &generator) ?? nil,
                step: Int.random(in: 0 ..< 5, using: &generator) == 0 ? .pounds(10) : nil,
                isSupersetWithPrevious: Bool.random(using: &generator),
                dropSets: Int.random(in: 0 ... 1, using: &generator),
                misses: Set((0 ..< 12).filter { _ in Int.random(in: 0 ..< 6, using: &generator) == 0 })
            )
        }
        return DayTemplate(
            id: DayTemplateID(Fixtures.uuid(800 + number)),
            name: "Training \(number) — Focus",
            tag: "T\(number)",
            slots: slots
        )
    }
}
