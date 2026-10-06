@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 1: purity and totality (criterion 9). The sources are read in
/// `ProgramWordsAdversarialTests`.
@Suite("Adversarial F11 S5 · purity and totality", .tags(.feature))
nonisolated struct ProgramTotalityAdversarialTests {
    static let seeds: [UInt64] = Array(101 ... 140)

    @Test("The same input gives the same model, however the exercises were handed in", arguments: seeds)
    func sameInput_anyOrderOfExercises_sameModel(seed: UInt64) throws {
        let made = try AdvProgram.random(seed: seed)
        let input = AdvProgram.input(made.program, exercises: made.exercises, week: Int(seed % 5))
        let first = ProgramPresentation.make(input)
        var reordered = [ExerciseID: Exercise](minimumCapacity: 512)
        for exercise in made.exercises.values.sorted(by: { $0.shortName > $1.shortName }) {
            reordered[exercise.id] = exercise
        }
        var other = input
        other.exercises = reordered
        let again = ProgramPresentation.make(input) == first
        let shuffled = ProgramPresentation.make(other) == first
        #expect(again, "seed \(seed): two calls differ")
        #expect(shuffled, "seed \(seed): the exercises' order changed the model")
    }

    @Test("Exercises the program does not use, and settings the strip does not read, change nothing")
    func unusedInput_changesNothing() throws {
        let base = try AdvProgram.seed(week: 2)
        let first = ProgramPresentation.make(base)
        var other = base
        other.exercises[AdvProgram.exercise(1).id] = AdvProgram.exercise(1)
        other.settings.units = .kg
        other.settings.autoRest.toggle()
        other.program.startDate = try #require(CivilDate(year: 2031, month: 1, day: 1))
        other.program.isActive.toggle()
        let same = ProgramPresentation.make(other) == first
        #expect(same)
    }

    @Test("A slot whose exercise is not stored is counted, timed and named by one short mark")
    func slotOfAMissingExercise_isCountedAndNamed() throws {
        let slots = try (0 ..< 6).map { try AdvProgram.slot($0, exercise: $0, sets: 2) }
        let day = AdvProgram.day(1, slots: slots)
        let known = AdvProgram.exercise(1, short: "Known")
        let program = try AdvProgram.program(weeks: 2, days: [day])
        let card = try #require(
            ProgramPresentation.make(AdvProgram.input(program, exercises: [known.id: known])).days.cards.first
        )
        #expect(card.meta == "6 exercises · 12 sets · ~\(TimeEstimate.minutes(day: day, prescriptions: [:])) min")
        #expect(card.chips.count == 5)
        #expect(card.chips.dropFirst().first == "Known")
        #expect(card.chips.last == "+2")
        let marks = Set([card.chips[0], card.chips[2], card.chips[3]])
        #expect(marks.count == 1, "one mark for every missing exercise: \(marks)")
        #expect(marks.first.map { ["—", "–", "-"].contains($0) } == true, "the plan's dash: \(marks)")
    }

    @Test("Names and tags of any length and script are drawn as stored, and nothing traps", arguments: [
        "", " ", "A", String(repeating: "W", count: 20000), "مرحبا بالعالم", "日本語のプログラム", "👨‍👩‍👧‍👦🏋🏽‍♀️",
        "e\u{301}\u{301}\u{301}", "\u{202E}reversed", "%@ %lld %d %s %%", "a — b — c", " — ", "\u{200B}",
        "line\u{2028}two"
    ])
    func names_anyScript_areDrawnAsStored(text: String) throws {
        let exercise = AdvProgram.exercise(0, short: text)
        let day = try AdvProgram.day(1, name: text, tag: text, slots: [AdvProgram.slot(1, exercise: 0)])
        let program = try AdvProgram.program(name: text, weeks: 2, days: [day]) { _, weekday in
            weekday == .wednesday ? 0 : nil
        }
        let model = ProgramPresentation.make(AdvProgram.input(program, exercises: [exercise.id: exercise]))
        let card = try #require(model.days.cards.first)
        let wednesday = try #require(model.week.cells.first { $0.weekday == .wednesday })
        let drawn = model.header.name == text && card.name == text && card.tag == text
            && card.spokenLabel == text && card.chips == [text] && wednesday.label == text
            && wednesday.spokenValue == day.shortTitle && !wednesday.isRest
        #expect(drawn, "a text of \(text.count) characters was changed on its way to the screen")
        #expect(card.meta == "1 exercise · 3 sets · ~7 min")
    }

    @Test("Odd calendars, locales and logged weeks give a whole screen", arguments: [
        "", "xx_YY", "en_US_POSIX", "ar_EG", "fa_IR", "th_TH@calendar=buddhist", "he_IL", "hi_IN@numbers=deva",
        "zh-Hant"
    ])
    func oddLocales_giveAWholeScreen(identifier: String) throws {
        let locale = Locale(identifier: identifier)
        var input = try AdvProgram.seed(week: 7)
        input.locale = locale
        input.calendar = Calendar(identifier: .gregorian)
        input.loggedWeeks = [Int.min, -1, 7, 8, Int.max]
        input.notice = .weekHasLoggedSessions(weekNumber: 8)
        let model = ProgramPresentation.make(input)
        #expect(model.block.chips.count == 8)
        #expect(model.week.cells.count == 7)
        #expect(model.week.cells.allSatisfy { !$0.letter.isEmpty && !$0.spokenLabel.isEmpty })
        #expect(model.block.removeWeek == .notice(.weekHasLoggedSessions(weekNumber: 8)))
        #expect(model.notice?.isEmpty == false)
        #expect(model.days.cards.count == 4)
    }
}
