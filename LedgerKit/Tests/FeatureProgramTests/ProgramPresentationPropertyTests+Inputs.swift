@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The random inputs of the property suite.
nonisolated extension ProgramPresentationPropertyTests {
    static let locales = ["en_US", "de_DE", "fr_FR", "ja_JP", "ar_EG", "hi_IN"]

    /// A random input: a block of 2 to 16 weeks, one in sixteen of 52, and 0 to 12 days, each day with 0 to 7
    /// slots; any week a deload; schedules that may train a day twice in a week; any week start and one of six
    /// locales; a selected week from two before the block to two after it; some weeks logged; now and then an
    /// exercise that is not stored, and a notice showing.
    static func input(using generator: inout SeededGenerator) throws -> ProgramBuilderInput {
        let days = try (0 ..< Int.random(in: 0 ... 12, using: &generator)).map { try day($0, using: &generator) }
        let isLong = Int.random(in: 0 ..< 16, using: &generator) == 0
        let weekCount = isLong ? 52 : Int.random(in: 2 ... 16, using: &generator)
        var program = try ProgramFixtures.program(weekCount: weekCount, days: days)
        for place in program.weeks.indices {
            program.weeks[place].isDeload = Int.random(in: 0 ..< 5, using: &generator) == 0
            for weekday in Weekday.allCases where Bool.random(using: &generator) {
                program.weeks[place].schedule[weekday] = days.randomElement(using: &generator)?.id
            }
        }
        var input = try ProgramFixtures.input(program)
        input.selectedWeek = Int.random(in: -2 ... weekCount + 1, using: &generator)
        input.settings.weekStart = Weekday.allCases.randomElement(using: &generator) ?? .monday
        input.locale = Locale(identifier: locales.randomElement(using: &generator) ?? "en_US")
        input.loggedWeeks = Set((0 ..< weekCount).filter { _ in Int.random(in: 0 ..< 6, using: &generator) == 0 })
        if Bool.random(using: &generator) {
            input.exercises[Fixtures.CatalogID.backSquat] = nil
        }
        if Int.random(in: 0 ..< 4, using: &generator) == 0 {
            input.notice = [.minimumTwoWeeks, .dayHasNoExercises, .weekHasLoggedSessions(weekNumber: weekCount)]
                .randomElement(using: &generator)
        }
        return input
    }

    /// Day `number`, tagged "T" and its number, with up to seven slots of random sets, rests, drop sets and
    /// superset flags; the first slot's flag is random too, which the Domain reads as false.
    static func day(_ number: Int, using generator: inout SeededGenerator) throws -> DayTemplate {
        let exercises = [Fixtures.CatalogID.backSquat, Fixtures.CatalogID.benchPress, Fixtures.CatalogID.deadlift]
        let slots = try (0 ..< Int.random(in: 0 ... 7, using: &generator)).map { index in
            let reps = Int.random(in: 1 ... 20, using: &generator)
            return try Slot(
                id: SlotID(Fixtures.uuid(1000 + number * 10 + index)),
                exerciseID: exercises.randomElement(using: &generator) ?? Fixtures.CatalogID.benchPress,
                sets: Int.random(in: 1 ... 12, using: &generator),
                reps: reps,
                repsHi: reps + 2,
                rpe: 8,
                restSeconds: 15 * Int.random(in: 2 ... 20, using: &generator),
                progression: Progression.allCases.randomElement(using: &generator) ?? .linear,
                isSupersetWithPrevious: Bool.random(using: &generator),
                dropSets: Int.random(in: 0 ... 1, using: &generator)
            )
        }
        return DayTemplate(
            id: DayTemplateID(Fixtures.uuid(700 + number)),
            name: "Training \(number) — Focus",
            tag: "T\(number)",
            slots: slots
        )
    }
}
