@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 1: counts and their plurals, the selected week at and beyond the block's ends,
/// and the three notices (criteria 2, 3, 5 and 6). The expected lines are the brief's, written out here.
@Suite("Adversarial F11 S5 · counts, plurals, the selected week and the notices", .tags(.feature))
nonisolated struct ProgramCountsAdversarialTests {
    @Test("A week of 0, 1, 2 and 7 training days reads 0 DAYS, 1 DAY, 2 DAYS and 7 DAYS, spoken alike")
    func chip_countsOfDays_arePluralised() throws {
        let day = try AdvProgram.day(1, slots: [AdvProgram.slot(1, exercise: 0)])
        let program = try AdvProgram.program(weeks: 4, days: [day]) { week, weekday in
            weekday.rawValue <= [0, 1, 2, 7][week] ? 0 : nil
        }
        let chips = ProgramPresentation.make(AdvProgram.input(program)).block.chips
        #expect(chips.map(\.subtitle) == ["0 DAYS", "1 DAY", "2 DAYS", "7 DAYS"])
        #expect(chips.map(\.spokenValue) == ["0 days", "1 day", "2 days", "7 days"])
        #expect(chips.map(\.spokenLabel) == ["Week 1", "Week 2", "Week 3", "Week 4"])
    }

    @Test("One day of one exercise and one set reads in the singular everywhere")
    func oneOfEverything_readsInTheSingular() throws {
        let day = try AdvProgram.day(1, slots: [AdvProgram.slot(1, exercise: 0, sets: 1, rest: 30)])
        let program = try AdvProgram.program(weeks: 2, days: [day])
        let model = ProgramPresentation.make(AdvProgram.input(program, exercises: [:]))
        #expect(TimeEstimate.minutes(day: day, prescriptions: [:]) == 1, "42 s and 30 s of rest: one minute")
        #expect(model.days.summary == "1 day · 1 set a week")
        #expect(model.days.cards.first?.meta == "1 exercise · 1 set · ~1 min")
        #expect(model.block.title == "BLOCK · 2 WEEKS")
        #expect(model.block.spokenValue == "2 weeks")
    }

    @Test("A program with no days reads 0 days · 0 sets a week, has no card and seven REST cells")
    func noDays_readsZeroAndRests() throws {
        let program = try AdvProgram.program(weeks: 3, days: [], deloads: [1])
        let input = AdvProgram.input(program, week: 2)
        let model = ProgramPresentation.make(input)
        #expect(model.days.summary == "0 days · 0 sets a week")
        #expect(model.days.cards.isEmpty)
        #expect(model.days.addDay.action == .addDay(name: "New day", weekIndex: 2))
        #expect(model.week.cells.map(\.label) == Array(repeating: "REST", count: 7))
        #expect(model.block.chips.map(\.subtitle) == ["0 DAYS", "DELOAD", "0 DAYS"])
        #expect(model.week.cells.allSatisfy { $0.action == nil && $0.spokenHint == nil }, "criterion 13")
        #expect(model.week.hint == nil, "nothing to assign, so no Tap to assign")
        #expect(model.week.cells.map(\.spokenValue) == Array(repeating: "Rest", count: 7))
        #expect(model.week.cells.first?.spokenLabel == "Monday")
    }

    @Test("Drop sets count as sets, and a superset's minutes are TimeEstimate's")
    func dropSetsAndSupersets_areCountedAsTheDomainCounts() throws {
        let slots = try [
            AdvProgram.slot(1, exercise: 0, sets: 4, rest: 120, drop: 1),
            AdvProgram.slot(2, exercise: 1, sets: 3, rest: 60),
            AdvProgram.slot(3, exercise: 2, sets: 3, rest: 90, joined: true),
            AdvProgram.slot(4, exercise: 3, sets: 2, rest: 45, joined: true, drop: 1),
            AdvProgram.slot(5, exercise: 4, sets: 12, rest: 300),
            AdvProgram.slot(6, exercise: 5, sets: 1, rest: 30, drop: 1)
        ]
        let day = AdvProgram.day(1, name: "Mixed — everything", tag: "MX", slots: slots)
        let exercises = (0 ... 5).map { AdvProgram.exercise($0) }
        let stored = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let model = try ProgramPresentation.make(AdvProgram.input(
            AdvProgram.program(weeks: 2, days: [day]),
            exercises: stored
        ))
        let minutes = TimeEstimate.minutes(day: day, prescriptions: [:])
        let apart = TimeEstimate.minutes(
            day: DayEditing.setSuperset(false, slot: slots[2].id, in: day),
            prescriptions: [:]
        )
        #expect(DayEditing.groups(of: day).map(\.count) == [1, 3, 1, 1])
        #expect(minutes != apart, "the superset rests once a round, so the fixture tells the two apart")
        let card = try #require(model.days.cards.first)
        #expect(card.meta == "6 exercises · 28 sets · ~\(minutes) min")
        #expect(model.days.summary == "1 day · 28 sets a week")
        #expect(card.chips == ["Ex0", "Ex1", "Ex2", "Ex3", "+2"])
        #expect(card.spokenLabel == "Mixed — everything")
        #expect(card.spokenValue == card.meta)
    }

    @Test("Exactly four exercises are four names; five are four names and +1")
    func cardChips_atTheLimit_showFourThenTheRest() throws {
        let exercises = (0 ... 5).map { AdvProgram.exercise($0) }
        let stored = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let days = try [4, 5, 6].map { count in
            try AdvProgram.day(count, slots: (0 ..< count).map { try AdvProgram.slot(count * 10 + $0, exercise: $0) })
        }
        let program = try AdvProgram.program(weeks: 2, days: days)
        let cards = ProgramPresentation.make(AdvProgram.input(program, exercises: stored)).days.cards
        #expect(cards.map(\.chips) == [
            ["Ex0", "Ex1", "Ex2", "Ex3"], ["Ex0", "Ex1", "Ex2", "Ex3", "+1"], ["Ex0", "Ex1", "Ex2", "Ex3", "+2"]
        ])
    }

    @Test("A selection outside the block is read as the nearest week, and no action names another", arguments: [
        Int.min, -1000, -1, 0, 3, 4, 5, 1000, Int.max
    ])
    func selectedWeek_outOfRange_isTheNearestWeek(selected: Int) throws {
        let made = try AdvProgram.random(seed: 3)
        let program = try AdvProgram.program(weeks: 5, days: made.program.days, deloads: [0, 4]) { week, weekday in
            (week + weekday.rawValue) % 3 == 0 ? week % max(made.program.days.count, 1) : nil
        }
        let nearest = min(max(selected, 0), 4)
        let input = AdvProgram.input(program, exercises: made.exercises, week: selected)
        let model = ProgramPresentation.make(input)
        #expect(model.week.title == "WEEK \(nearest + 1)" + ([0, 4].contains(nearest) ? " · DELOAD" : ""))
        #expect(model.block.chips.map(\.isSelected) == (0 ..< 5).map { $0 == nearest })
        #expect(model.week.deload.action == .edit(.setDeload(![0, 4].contains(nearest), week: nearest)))
        #expect(model.week.copyPrevious.title == (nearest == 0 ? "First week" : "Copy week \(nearest)"))
        #expect((model.week.applyToLater == nil) == (nearest == 4))
        let same = model == ProgramPresentation.make(AdvProgram.input(
            program,
            exercises: made.exercises,
            week: nearest
        ))
        #expect(same, "the screen of week \(selected) is the screen of week \(nearest)")
        let differences = AdvScreen.differences(input)
        #expect(differences.isEmpty, "\(differences)")
    }

    @Test(
        "Blocks of 2, 16 and 52 weeks, every week a deload, read their length and one chip a week",
        arguments: [2, 16, 52]
    )
    func blockLengths_readTheirWeeks(weeks: Int) throws {
        let days = try (0 ..< 6).map { try AdvProgram.day($0, slots: [AdvProgram.slot($0, exercise: $0, sets: 12)]) }
        let program = try AdvProgram.program(weeks: weeks, days: days, deloads: Set(0 ..< weeks)) { week, weekday in
            weekday == .sunday ? nil : (week + weekday.rawValue) % 6
        }
        let input = AdvProgram.input(program, week: weeks - 1)
        let model = ProgramPresentation.make(input)
        #expect(model.block.title == "BLOCK · \(weeks) WEEKS")
        #expect(model.block.spokenValue == "\(weeks) weeks")
        #expect(model.block.chips.map(\.title) == (1 ... weeks).map { "W\($0)" })
        #expect(model.block.chips.allSatisfy { $0.subtitle == "DELOAD" && $0.spokenValue == "Deload" && $0.isDeload })
        #expect(model.week.title == "WEEK \(weeks) · DELOAD")
        #expect(model.days.summary == "6 days · 72 sets a week")
        let differences = AdvScreen.differences(input)
        #expect(differences.isEmpty, "\(differences)")
    }

    @Test("Each notice reads as the brief writes it, with its own week number, and changes nothing else", arguments: [
        (ProgramBuilderNotice.minimumTwoWeeks, "A block needs at least 2 weeks."),
        (.weekHasLoggedSessions(weekNumber: 8), "Week 8 has logged sessions and can't be removed."),
        (.weekHasLoggedSessions(weekNumber: 3), "Week 3 has logged sessions and can't be removed."),
        (.weekHasLoggedSessions(weekNumber: 1), "Week 1 has logged sessions and can't be removed."),
        (.weekHasLoggedSessions(weekNumber: 52), "Week 52 has logged sessions and can't be removed."),
        (.dayHasNoExercises, "Add at least one exercise before scheduling this day.")
    ])
    func notice_readsAsTheBrief(notice: ProgramBuilderNotice, text: String) throws {
        var input = try AdvProgram.seed(week: 4)
        let quiet = ProgramPresentation.make(input)
        input.notice = notice
        let loud = ProgramPresentation.make(input)
        #expect(quiet.notice == nil)
        #expect(loud.notice == text)
        let rest = loud.header == quiet.header && loud.block == quiet.block && loud.week == quiet.week
            && loud.days == quiet.days
        #expect(rest, "the notice changed another part of the screen")
    }

    @Test("The Domain's two refusals become the two notices the screen words")
    func noticeFromAnError_keepsTheWeekNumber() {
        #expect(ProgramBuilderNotice(.minimumTwoWeeks) == .minimumTwoWeeks)
        #expect(ProgramBuilderNotice(.weekHasLoggedSessions(weekNumber: 6)) == .weekHasLoggedSessions(weekNumber: 6))
    }
}
