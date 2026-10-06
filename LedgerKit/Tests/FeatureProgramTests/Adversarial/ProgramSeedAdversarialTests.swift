@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 1: the seed program, text for text (criteria 1 to 5 of the brief; criteria 2 to 5
/// of the slice). Every expected text is written here from the brief; the minutes are `TimeEstimate`'s.
@Suite("Adversarial F11 S5 · the seed program on the builder", .tags(.feature))
nonisolated struct ProgramSeedAdversarialTests {
    @Test("Criterion 1: the header, the block and the eight chips read as the brief gives them")
    func seed_headerAndBlock_readAsTheBrief() throws {
        let model = try ProgramPresentation.make(AdvProgram.seed())
        #expect(model.header.eyebrow == "MY PROGRAM")
        #expect(model.header.name == "Upper / Lower")
        #expect(model.header.namePlaceholder == "Program name")
        #expect(model.block.title == "BLOCK · 8 WEEKS")
        #expect(model.block.chips.map(\.title) == ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"])
        let subtitles = model.block.chips.map(\.subtitle)
        #expect(subtitles == Array(repeating: "4 DAYS", count: 7) + ["DELOAD"])
        #expect(model.block.chips.map(\.isSelected) == [true] + Array(repeating: false, count: 7))
        #expect(model.block.chips.map(\.isDeload) == Array(repeating: false, count: 7) + [true])
        #expect(model.notice == nil)
    }

    @Test("Criterion 1: week 1's strip is M UA · T REST · W LA · T REST · F UB · S LB · S REST")
    func seed_weekOne_stripReadsAsTheBrief() throws {
        let week = try ProgramPresentation.make(AdvProgram.seed()).week
        #expect(week.title == "WEEK 1")
        #expect(week.hint == "Tap to assign")
        let strip = week.cells.map { "\($0.letter) \($0.label)" }.joined(separator: " · ")
        #expect(strip == "M UA · T REST · W LA · T REST · F UB · S LB · S REST")
        #expect(week.cells.map(\.isRest) == [false, true, false, true, false, false, true])
        #expect(week.copyPrevious.title == "First week")
        #expect(week.copyPrevious.action == nil)
        #expect(week.applyToLater?.title == "Apply to later weeks")
        #expect(week.deload.title == "Deload")
        #expect(week.deload.isOn == false)
    }

    @Test("Criterion 1: 4 days · 58 sets a week, and four cards with TimeEstimate's minutes 39, 38, 37, 31")
    func seed_trainingDays_readAsTheBrief() throws {
        let input = try AdvProgram.seed()
        let days = ProgramPresentation.make(input).days
        let minutes = input.program.days.map { TimeEstimate.minutes(day: $0, prescriptions: [:]) }
        #expect(minutes == [39, 38, 37, 31], "the plan's four values, from the Domain")
        #expect(days.title == "TRAINING DAYS")
        #expect(days.summary == "4 days · 58 sets a week")
        #expect(days.helper == "Shared by every week. The schedule above decides which day you train, and when.")
        #expect(days.addDay.title == "+ Add training day")
        #expect(days.cards.map(\.tag) == ["UA", "LA", "UB", "LB"])
        #expect(days.cards.map(\.name) == [
            "Upper A — Push focus", "Lower A — Squat focus", "Upper B — Pull focus", "Lower B — Hinge focus"
        ])
        #expect(days.cards.map(\.meta) == [
            "5 exercises · 18 sets · ~39 min", "4 exercises · 15 sets · ~38 min",
            "4 exercises · 15 sets · ~37 min", "3 exercises · 10 sets · ~31 min"
        ])
        #expect(days.cards.map(\.chips.count) == [5, 4, 4, 3], "four names and +1; four; four; three")
        #expect(days.cards.first?.chips.last == "+1")
        let short = input.program.days[1].slots.compactMap { input.exercises[$0.exerciseID]?.shortName }
        #expect(days.cards[1].chips == short, "the catalog's short names, in the day's order")
        #expect(days.cards.map(\.action) == input.program.days.map { .route(.day($0.id, weekIndex: 0)) })
    }

    @Test(
        "Criterion 1 holds on every week of the seed block against the tester's model of the screen",
        arguments: 0 ..< 8
    )
    func seed_everyWeek_matchesTheTestersScreen(week: Int) throws {
        let differences = try AdvScreen.differences(AdvProgram.seed(week: week))
        #expect(differences.isEmpty, "\(differences)")
    }

    @Test("Week 8 of the seed reads WEEK 8 · DELOAD with the toggle on, Copy week 7 and no Apply to later weeks")
    func seed_deloadWeek_readsAsTheBrief() throws {
        let model = try ProgramPresentation.make(AdvProgram.seed(week: 7))
        #expect(model.week.title == "WEEK 8 · DELOAD")
        #expect(model.week.deload.isOn)
        #expect(model.week.deload.action == .edit(.setDeload(false, week: 7)))
        #expect(model.week.copyPrevious.title == "Copy week 7")
        #expect(model.week.copyPrevious.action == .edit(.copyPreviousWeek(week: 7)))
        #expect(model.week.applyToLater == nil)
        #expect(model.week.cells.map(\.label) == ["UA", "REST", "LA", "REST", "UB", "REST", "REST"])
        #expect(model.block.chips.map(\.isSelected) == Array(repeating: false, count: 7) + [true])
    }
}

nonisolated extension ProgramSeedAdversarialTests {
    @Test("Criterion 2 as amended: Tuesday of week 1 goes UA, LA, UB, LB and back to REST, and the chip counts it")
    func seed_tuesdayTappedFiveTimes_cyclesAndCounts() throws {
        var input = try AdvProgram.seed()
        var labels: [String] = []
        var counts: [String] = []
        for tap in 1 ... 5 {
            let model = ProgramPresentation.make(input)
            let tuesday = try #require(model.week.cells.first { $0.weekday == .tuesday })
            let becomes = tap <= 4 ? input.program.days[tap - 1].id : nil
            #expect(tuesday.action == .edit(.setSchedule(week: 0, weekday: .tuesday, day: becomes), notice: nil))
            let step = try AdvStore.apply(#require(tuesday.action), to: input, fresh: tap)
            #expect(step.edits == 1)
            input = step.input
            let after = ProgramPresentation.make(input)
            labels.append(after.week.cells[1].label)
            counts.append(after.block.chips[0].subtitle)
        }
        #expect(labels == ["UA", "LA", "UB", "LB", "REST"])
        #expect(counts == ["5 DAYS", "5 DAYS", "5 DAYS", "5 DAYS", "4 DAYS"])
        let untouched = try input.program == Fixtures.seedProgram()
        #expect(untouched, "five taps bring the seed program back")
    }

    @Test("Criterion 3: Copy week 2, Apply to later weeks and Deload on week 3, each one edit")
    func seed_weekThreeActions_copyApplyAndToggle() throws {
        var input = try AdvProgram.seed(week: 2)
        input.program = ProgramEditing.cycleSchedule(input.program, week: 1, weekday: .sunday)
        let model = ProgramPresentation.make(input)
        #expect(model.week.title == "WEEK 3")
        #expect(model.week.copyPrevious.title == "Copy week 2")
        let copy = try #require(model.week.copyPrevious.action)
        input = AdvStore.apply(copy, to: input, fresh: 1).input
        #expect(input.program.weeks[2].schedule == input.program.weeks[1].schedule)
        #expect(ProgramPresentation.make(input).block.chips[2].subtitle == "5 DAYS")

        let apply = try #require(ProgramPresentation.make(input).week.applyToLater?.action)
        input = AdvStore.apply(apply, to: input, fresh: 2).input
        let later = ProgramPresentation.make(input).block.chips.map(\.subtitle)
        #expect(later == ["4 DAYS", "5 DAYS", "5 DAYS", "5 DAYS", "5 DAYS", "5 DAYS", "5 DAYS", "DELOAD"])
        #expect(input.program.weeks.map(\.isDeload) == Array(repeating: false, count: 7) + [true])
        #expect(input.program.weeks[7].schedule == input.program.weeks[2].schedule)

        input = AdvStore.apply(ProgramPresentation.make(input).week.deload.action, to: input, fresh: 3).input
        let toggled = ProgramPresentation.make(input)
        #expect(toggled.block.chips[2].subtitle == "DELOAD")
        #expect(toggled.week.title == "WEEK 3 · DELOAD")
        #expect(toggled.week.deload.isOn)
    }

    @Test("Criterion 4: + appends a copy of week 8's schedule, not a deload, and selects it; − then removes it")
    func seed_plusAndMinus_appendSelectAndRemove() throws {
        var input = try AdvProgram.seed(week: 2)
        let plus = ProgramPresentation.make(input).block.addWeek
        #expect(plus == .addWeek(selecting: 8))
        input = AdvStore.apply(plus, to: input, fresh: 1).input
        let grown = ProgramPresentation.make(input)
        #expect(grown.block.title == "BLOCK · 9 WEEKS")
        #expect(grown.block.chips.last?.subtitle == "3 DAYS")
        #expect(grown.block.chips.last?.isSelected == true)
        #expect(grown.week.title == "WEEK 9")
        #expect(grown.week.cells.map(\.label) == ["UA", "REST", "LA", "REST", "UB", "REST", "REST"])
        #expect(grown.block.removeWeek == .edit(.removeLastWeek(loggedWeeks: []), notice: nil))

        let step = AdvStore.apply(grown.block.removeWeek, to: input, fresh: 2)
        #expect(step.refused == nil)
        let shrunk = ProgramPresentation.make(step.input)
        #expect(shrunk.block.title == "BLOCK · 8 WEEKS")
        #expect(shrunk.week.title == "WEEK 8 · DELOAD", "a selection left behind by − reads as the last week")
    }

    @Test("Criterion 4: − on a last week with a finished workout is the notice with the week's number")
    func seed_minusOnALoggedLastWeek_isTheNotice() throws {
        var input = try AdvProgram.seed()
        input.loggedWeeks = [7]
        let minus = ProgramPresentation.make(input).block.removeWeek
        #expect(minus == .notice(.weekHasLoggedSessions(weekNumber: 8)))
        let step = AdvStore.apply(minus, to: input, fresh: 1)
        #expect(step.edits == 0)
        let after = ProgramPresentation.make(step.input)
        #expect(after.notice == "Week 8 has logged sessions and can't be removed.")
        #expect(after.block.title == "BLOCK · 8 WEEKS")
        input.loggedWeeks = [0, 3, 6]
        let free = ProgramPresentation.make(input).block.removeWeek
        #expect(free == .edit(.removeLastWeek(loggedWeeks: [0, 3, 6]), notice: nil), "earlier weeks do not hold it")
    }

    @Test("Criterion 5: + Add training day makes New day / D5, opens it, and its card reads No exercises yet")
    func seed_addTrainingDay_makesD5AndOpensIt() throws {
        var input = try AdvProgram.seed(week: 3)
        let add = try #require(ProgramPresentation.make(input).days.addDay.action)
        #expect(add == .addDay(name: "New day", weekIndex: 3))
        let step = AdvStore.apply(add, to: input, fresh: 1)
        input = step.input
        let card = try #require(ProgramPresentation.make(input).days.cards.last)
        #expect(step.route == .day(card.id, weekIndex: 3))
        #expect(card.name == "New day")
        #expect(card.tag == "D5")
        #expect(card.meta == "No exercises yet")
        #expect(card.chips.isEmpty)
        #expect(ProgramPresentation.make(input).days.summary == "5 days · 58 sets a week")
    }

    @Test("Behaviour 6: the tap that assigns the empty day carries the notice, and the next tap drops it")
    func seed_cycleOntoTheEmptyDay_carriesTheNotice() throws {
        var input = try AdvProgram.seed()
        input.program = ProgramEditing.addDay(input.program, id: DayTemplateID(Fixtures.uuid(77)), name: "New day")
        var notices: [String?] = []
        var labels: [String] = []
        for tap in 1 ... 6 {
            let action = ProgramPresentation.make(input).week.cells[1].action
            input = try AdvStore.apply(#require(action), to: input, fresh: tap).input
            let after = ProgramPresentation.make(input)
            notices.append(after.notice)
            labels.append(after.week.cells[1].label)
        }
        let text = "Add at least one exercise before scheduling this day."
        #expect(labels == ["UA", "LA", "UB", "LB", "D5", "REST"])
        #expect(notices == [nil, nil, nil, nil, text, nil])
    }
}
