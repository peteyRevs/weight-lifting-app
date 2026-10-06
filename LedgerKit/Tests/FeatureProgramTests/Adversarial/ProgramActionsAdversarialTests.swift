@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 1: every action the model offers, applied (criterion 1: "an action the store can
/// apply without deciding anything"; the S1 ruling "For S13 and S14": each edit reaches the program once).
/// Programs come from seeds 1 to 60; a walk takes forty actions from the screen, applies each as its
/// documentation says, and holds the next screen against the tester's model.
@Suite("Adversarial F11 S5 · every action applied", .tags(.feature))
nonisolated struct ProgramActionsAdversarialTests {
    static let seeds: [UInt64] = Array(1 ... 60)

    /// Every action a screen offers, with the control that offers it.
    static func offered(_ model: ProgramBuilderModel) -> [(control: String, action: ProgramBuilderAction)] {
        var all: [(String, ProgramBuilderAction)] = [("−", model.block.removeWeek), ("+", model.block.addWeek)]
        all += model.block.chips.map { ($0.title, $0.action) }
        all += model.week.cells.map { ("cell \($0.weekday)", $0.action) }
        all += [model.week.copyPrevious, model.week.applyToLater, model.days.addDay].compactMap { control in
            control.flatMap { held in held.action.map { (held.title, $0) } }
        }
        all.append(("Deload", model.week.deload.action))
        all += model.days.cards.map { ("card \($0.tag)", $0.action) }
        return all
    }

    /// What is wrong with the places and ids `action` names in `input`'s program; empty when nothing is.
    static func strays(_ action: ProgramBuilderAction, _ input: ProgramBuilderInput) -> [String] {
        let weeks = input.program.weeks.indices
        let selected = AdvScreen.place(input)
        switch action {
        case let .selectWeek(place):
            return weeks.contains(place) ? [] : ["selects week \(place)"]
        case let .edit(.toggleDeload(week), _), let .edit(.cycleSchedule(week, _), _),
             let .edit(.copyPreviousWeek(week), _), let .edit(.applyToLaterWeeks(week), _):
            return week == selected ? [] : ["edits week \(week), selected \(selected)"]
        case let .addWeek(selecting):
            return selecting == weeks.count ? [] : ["+ selects \(selecting) of \(weeks.count)"]
        case let .addDay(name, weekIndex):
            return (name == "New day" ? [] : ["names the day \(name)"])
                + (weekIndex == selected ? [] : ["opens week \(weekIndex)"])
        case let .route(.day(id, weekIndex)):
            return (input.program.days.contains { $0.id == id } ? [] : ["routes to a day not held"])
                + (weekIndex == selected ? [] : ["routes with week \(weekIndex)"])
        case .route(.closeDay):
            return ["the builder closes a day"]
        case .edit(.renameProgram, _), .edit(.addWeek, _), .edit(.addDay, _):
            return ["a control offers \(action)"]
        case .edit(.removeLastWeek, _), .notice:
            return []
        }
    }

    @Test("No action of any seeded screen names a week, a weekday or a day the program does not hold", arguments: seeds)
    func offeredActions_nameOnlyWhatTheProgramHolds(seed: UInt64) throws {
        let made = try AdvProgram.random(seed: seed)
        var found: [String] = []
        for selected in -2 ... made.program.weeks.count + 1 {
            let input = AdvProgram.input(made.program, exercises: made.exercises, week: selected, logged: [1])
            let model = ProgramPresentation.make(input)
            for (control, action) in Self.offered(model) {
                found += Self.strays(action, input).map { "week \(selected), \(control): \($0)" }
            }
            let weekdays = model.week.cells.map(\.weekday)
            if Set(weekdays).count != 7 {
                found.append("week \(selected): the cells are \(weekdays)")
            }
        }
        #expect(found.isEmpty, "seed \(seed): \(found.prefix(4))")
    }

    @Test(
        "An edit the screen offers is the one ProgramEditing call the tester spells, and − never throws",
        arguments: seeds
    )
    func offeredEdits_areOneDomainCallEach(seed: UInt64) throws {
        let made = try AdvProgram.random(seed: seed)
        var found: [String] = []
        for selected in made.program.weeks.indices {
            for logged in [Set<Int>(), [made.program.weeks.count - 1], [0, 99, -1]] {
                let input = AdvProgram.input(made.program, exercises: made.exercises, week: selected, logged: logged)
                for (control, action) in Self.offered(ProgramPresentation.make(input)) {
                    guard case let .edit(edit, _) = action else {
                        continue
                    }
                    let mine = try? AdvStore.edited(input.program, edit)
                    let theirs = try? edit.applied(to: input.program)
                    if mine == nil || mine != theirs {
                        found.append("week \(selected), \(control): \(mine == nil ? "refused" : "another program")")
                    }
                }
            }
        }
        #expect(found.isEmpty, "seed \(seed): \(found.prefix(4))")
    }

    @Test("A walk of forty actions keeps the screen equal to the tester's model after every step", arguments: seeds)
    func walk_everyStep_matchesTheTestersScreen(seed: UInt64) throws {
        let made = try AdvProgram.random(seed: seed)
        var rng = SplitMix64(seed: seed &* 7919)
        var input = AdvProgram.input(
            made.program,
            exercises: made.exercises,
            weekStart: Weekday.allCases.randomElement(using: &rng) ?? .monday,
            week: Int.random(in: 0 ..< made.program.weeks.count, using: &rng),
            logged: Bool.random(using: &rng) ? [made.program.weeks.count - 1] : []
        )
        var found: [String] = []
        var taken: Set<String> = []
        for stepNumber in 1 ... 40 where found.isEmpty {
            let offered = Self.offered(ProgramPresentation.make(input))
            let (control, action) = try #require(offered.randomElement(using: &rng))
            let step = AdvStore.apply(action, to: input, fresh: stepNumber)
            taken.insert(String(describing: action).prefix { $0 != "(" }.description)
            if step.refused != nil {
                found.append("step \(stepNumber), \(control): the Domain refused the edit")
            }
            input = step.input
            found += AdvScreen.differences(input).map { "step \(stepNumber) after \(control): \($0)" }
        }
        #expect(found.isEmpty, "seed \(seed): \(found)")
        #expect(taken.count >= 3, "seed \(seed) took only \(taken)")
    }
}

nonisolated extension ProgramActionsAdversarialTests {
    @Test("Control: the tester's model tells one edit, one selection, one notice and one setting apart")
    func testersModel_isNotBlind() throws {
        let input = try AdvProgram.seed()
        var edited = input
        edited.program = ProgramEditing.toggleDeload(input.program, week: 5)
        var selected = input
        selected.selectedWeek = 1
        var noticed = input
        noticed.notice = .minimumTwoWeeks
        var started = input
        started.settings.weekStart = .tuesday
        var renamed = input
        renamed.program.days[3].tag = "XX"
        let blind = [edited, selected, noticed, started, renamed]
            .map { AdvScreen.differences(input, wanted: $0).isEmpty }
        #expect(blind == [false, false, false, false, false])
        #expect(AdvScreen.differences(input).isEmpty)
    }

    @Test("The sixty walks' programs reach every state the screen has")
    func seeds_reachEveryState() throws {
        let programs = try Self.seeds.map { try AdvProgram.random(seed: $0).program }
        let days = programs.flatMap(\.days)
        #expect(programs.contains { $0.days.isEmpty })
        #expect(programs.contains { $0.days.count == 6 })
        #expect(programs.contains { $0.weeks.count == 2 })
        #expect(programs.contains { $0.weeks.contains(where: \.isDeload) })
        #expect(days.contains { $0.slots.isEmpty })
        #expect(days.contains { $0.slots.count > 4 })
        #expect(days.contains { $0.slots.contains { $0.dropSets > 0 } })
        #expect(days.contains { $0.slots.contains(where: \.isSupersetWithPrevious) })
        #expect(days.contains { $0.slots.contains { $0.exerciseID == AdvProgram.exercise(13).id } })
    }

    @Test(
        "A cell's cycle goes rest, first day … last day, rest, for one to six days on every weekday",
        arguments: 1 ... 6
    )
    func cell_tappedThroughTheCycle_readsEachTagThenRest(dayCount: Int) throws {
        let days = try (0 ..< dayCount).map { try AdvProgram.day($0, slots: [AdvProgram.slot($0, exercise: 0)]) }
        let program = try AdvProgram.program(weeks: 3, days: days)
        var found: [String] = []
        for weekday in Weekday.allCases {
            var input = AdvProgram.input(program, weekStart: .thursday, week: 1)
            var read: [String] = []
            for tap in 0 ... dayCount {
                let cell = try #require(ProgramPresentation.make(input).week.cells.first { $0.weekday == weekday })
                input = AdvStore.apply(cell.action, to: input, fresh: tap).input
                let after = ProgramPresentation.make(input)
                read.append(after.week.cells.first { $0.weekday == weekday }?.label ?? "gone")
                let others = after.week.cells.filter { $0.weekday != weekday && !$0.isRest }.count
                if others != 0 || after.block.chips[0].subtitle != "0 DAYS" {
                    found.append("\(weekday), tap \(tap): another cell or week changed")
                }
            }
            if read != days.map(\.tag) + ["REST"] {
                found.append("\(weekday): \(read)")
            }
        }
        #expect(found.isEmpty, "\(found.prefix(4))")
    }

    @Test("− on two weeks is the notice whatever is logged, and the notice changes nothing but its line")
    func minusOnTwoWeeks_isTheNoticeAndNothingElse() throws {
        let day = try AdvProgram.day(1, slots: [AdvProgram.slot(1, exercise: 0)])
        let program = try AdvProgram.program(weeks: 2, days: [day]) { _, weekday in weekday == .monday ? 0 : nil }
        for logged in [Set<Int>(), [1], [0, 1]] {
            let input = AdvProgram.input(program, week: 1, logged: logged)
            let before = ProgramPresentation.make(input)
            #expect(before.block.removeWeek == .notice(.minimumTwoWeeks))
            let step = AdvStore.apply(before.block.removeWeek, to: input, fresh: 1)
            let after = ProgramPresentation.make(step.input)
            #expect(after.notice == "A block needs at least 2 weeks.")
            let unchanged = step.input.program == program && after.block == before.block
                && after.week == before.week && after.days == before.days && after.header == before.header
            #expect(unchanged, "logged \(logged)")
        }
    }
}
