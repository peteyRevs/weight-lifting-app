@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Seeded checks of `ProgramPresentation.make(_:)` on random programs (`+Inputs`): the model is whole, its
/// counts are the ones a reference written here from the stored schedule gives, every action names a week or
/// a day the program holds, and applying any of them as a store does leaves a program the Domain accepts.
@Suite("ProgramPresentation properties", .tags(.feature, .property))
nonisolated struct ProgramPresentationPropertyTests {
    @Test(
        "Any program gives a whole model whose counts and actions agree with the program",
        arguments: PropertySeed.all
    )
    func make_randomProgram_keepsTheInvariants(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 2 {
            let input = try Self.input(using: &generator)
            let model = ProgramPresentation.make(input)
            let isSame = ProgramPresentation.make(input) == model
            #expect(isSame, "the same input gave another model")
            try Self.checkBlock(model, input)
            try Self.checkWeek(model, input)
            Self.checkDays(model, input)
            Self.checkTexts(model)
        }
    }

    @Test("Any action, applied as a store applies it, leaves a program the Domain accepts", arguments: PropertySeed.all)
    func actions_randomProgram_applyToAValidProgram(seed: PropertySeed) throws {
        var generator = seed.generator
        var screen = try BuilderScreen(Self.input(using: &generator))
        for _ in 0 ..< 8 {
            let actions = Self.actions(of: screen.model)
            let action = try #require(actions.randomElement(using: &generator))
            let before = screen.input.program
            // The model hands out an edit only when the Domain takes it: nothing here may throw.
            try screen.tap(action)
            let after = screen.input.program
            let rebuilt = try Program(
                id: after.id,
                name: after.name,
                startDate: after.startDate,
                weeks: after.weeks,
                days: after.days,
                goal: after.goal,
                daysPerWeek: after.daysPerWeek,
                isActive: after.isActive
            )
            let isValid = rebuilt == after
            #expect(isValid, "\(action) left a program the Domain rebuilds differently")
            if case .notice = action {
                let isUnchanged = after == before
                #expect(isUnchanged, "a notice changed the program")
                #expect(screen.model.notice?.isEmpty == false)
            }
        }
    }

    @Test("A cell tapped once for each day and once more is back where it began", arguments: PropertySeed.all)
    func cell_cycledThroughEveryDay_returns(seed: PropertySeed) throws {
        var generator = seed.generator
        var screen = try BuilderScreen(Self.input(using: &generator))
        let weekday = try #require(Weekday.allCases.randomElement(using: &generator))
        var model = screen.model
        let start = try #require(model.week.cell(weekday)).label
        let days = screen.input.program.days
        guard !days.isEmpty else {
            // Nothing to cycle through: the cell offers nothing (criterion 13).
            #expect(model.week.cell(weekday)?.action == nil)
            return
        }
        var seen: [String] = []
        for _ in 0 ... days.count {
            try screen.tap(#require(model.week.cell(weekday)).action)
            model = screen.model
            let cell = try #require(model.week.cell(weekday))
            seen.append(cell.label)
            // The notice shows exactly when the day just assigned has no exercise.
            let assigned = days.first { $0.tag == cell.label && !cell.isRest }
            #expect((model.notice != nil) == (assigned?.slots.isEmpty == true), "\(cell.label)")
        }
        #expect(seen.last == start)
        #expect(Set(seen) == Set(days.map(\.tag) + ["REST"]))
    }
}

// MARK: - The invariants

nonisolated extension ProgramPresentationPropertyTests {
    /// The week the model must read as selected: the input's, or the nearest the block has.
    static func nearest(_ input: ProgramBuilderInput) -> Int {
        let last = input.program.weeks.count - 1
        return input.selectedWeek < 0 ? 0 : (input.selectedWeek > last ? last : input.selectedWeek)
    }

    /// The reference: how many weekdays of `week` name a day the program holds.
    static func trainedDays(of week: Week, in program: Program) -> Int {
        let held = Set(program.days.map(\.id))
        return week.schedule.values.count { held.contains($0) }
    }

    static func checkBlock(_ model: ProgramBuilderModel, _ input: ProgramBuilderInput) throws {
        let weeks = input.program.weeks
        let selected = nearest(input)
        #expect(model.block.chips.count == weeks.count)
        #expect(model.block.selectedPlaces == [selected])
        #expect(model.block.addWeek == .addWeek(selecting: weeks.count))
        for (place, chip) in model.block.chips.enumerated() {
            let trained = trainedDays(of: weeks[place], in: input.program)
            let days = ProgramCopy.scheduledDays(trained, locale: input.locale)
            #expect(chip.subtitle == (weeks[place].isDeload ? "DELOAD" : days), "week \(place)")
            #expect(chip.isDeload == weeks[place].isDeload)
            #expect(chip.action == .selectWeek(place))
        }
        // The selected week's chip counts the cells that are not rest, deload or not.
        let cells = model.week.cells.count { !$0.isRest }
        #expect(cells == trainedDays(of: weeks[selected], in: input.program))
        let chip = model.block.chips[selected]
        #expect(chip.spokenValue == (chip.isDeload ? "Deload" : ProgramCopy.days(cells, locale: input.locale)))
        // "−" is the edit exactly when the Domain removes the week.
        let removes = (try? ProgramEditing.removeLastWeek(input.program, loggedWeeks: input.loggedWeeks)) != nil
        if case .edit(.removeLastWeek(input.loggedWeeks), notice: nil) = model.block.removeWeek {
            #expect(removes)
        } else {
            #expect(!removes)
            let notice = try #require(Self.notice(of: model.block.removeWeek))
            #expect(notice == (weeks.count == 2 ? .minimumTwoWeeks : .weekHasLoggedSessions(weekNumber: weeks.count)))
        }
    }

    static func notice(of action: ProgramBuilderAction) -> ProgramBuilderNotice? {
        if case let .notice(notice) = action {
            return notice
        }
        return nil
    }

    static func checkWeek(_ model: ProgramBuilderModel, _ input: ProgramBuilderInput) throws {
        let selected = nearest(input)
        let week = input.program.weeks[selected]
        let weekdays = model.week.cells.map(\.weekday)
        #expect(weekdays.count == 7)
        #expect(Set(weekdays).count == 7)
        #expect(weekdays.first == input.settings.weekStart)
        for cell in model.week.cells {
            let day = input.program.days.first { $0.id == week.schedule[cell.weekday] }
            #expect(cell.label == day?.tag ?? "REST")
            #expect(cell.isRest == (day == nil))
            #expect(cell.spokenValue == day?.shortTitle ?? "Rest")
            guard !input.program.days.isEmpty else {
                // With no training day a cell offers nothing (criterion 13).
                #expect(cell.action == nil && cell.spokenHint == nil)
                #expect(model.week.hint == nil)
                continue
            }
            #expect(cell.spokenHint == "Double-tap to assign")
            #expect(model.week.hint == "Tap to assign")
            guard case let .edit(.setSchedule(place, weekday, next), _) = cell.action else {
                Issue.record("\(cell.weekday) names no schedule: \(String(describing: cell.action))")
                continue
            }
            #expect(place == selected && weekday == cell.weekday)
            // The day named is rest or one the program holds, and never the one the cell shows.
            #expect(next == nil || input.program.days.contains { $0.id == next })
            #expect(next != day?.id)
        }
        #expect(model.week.deload.isOn == week.isDeload)
        #expect(model.week.deload.action == .edit(.setDeload(!week.isDeload, week: selected)))
        #expect(model.week.title.hasSuffix("DELOAD") == week.isDeload)
        #expect((model.week.copyPrevious.action == nil) == (selected == 0))
        if selected > 0 {
            #expect(model.week.copyPrevious.action == .edit(.copyPreviousWeek(week: selected)))
        }
        #expect((model.week.applyToLater == nil) == (selected == input.program.weeks.count - 1))
        if let apply = model.week.applyToLater {
            #expect(apply.action == .edit(.applyToLaterWeeks(week: selected)))
        }
    }

    static func checkDays(_ model: ProgramBuilderModel, _ input: ProgramBuilderInput) {
        let days = input.program.days
        let selected = nearest(input)
        #expect(model.days.cards.map(\.id) == days.map(\.id))
        #expect(model.days.addDay.action == .addDay(name: "New day", weekIndex: selected))
        var sets = 0
        for (card, day) in zip(model.days.cards, days) {
            #expect(card.action == .route(.day(day.id, weekIndex: selected)))
            #expect(card.tag == day.tag && card.name == day.name)
            let own = day.slots.reduce(0) { $0 + $1.sets + $1.dropSets }
            sets += own
            let named = day.slots.count < 4 ? day.slots.count : 4
            #expect(card.chips.count == named + (day.slots.count > 4 ? 1 : 0), "\(card.chips)")
            if day.slots.isEmpty {
                #expect(card.meta == "No exercises yet")
            } else {
                let minutes = TimeEstimate.minutes(day: day, prescriptions: [:])
                let estimate = ProgramCopy.estimate(minutes: minutes, locale: input.locale)
                #expect(card.meta.hasSuffix(" · " + ProgramCopy.sets(own, locale: input.locale) + " · " + estimate))
                #expect(card.meta.hasPrefix(ProgramCopy.exercises(day.slots.count, locale: input.locale) + " · "))
            }
        }
        #expect(model.days.summary.hasSuffix(" · " + ProgramCopy.setsAWeek(sets, locale: input.locale)))
        #expect(model.days.summary.hasPrefix(ProgramCopy.days(days.count, locale: input.locale) + " · "))
    }

    /// No text of the model is empty. The random programs name and tag every day.
    static func checkTexts(_ model: ProgramBuilderModel) {
        var texts = [
            model.header.eyebrow, model.header.name, model.header.namePlaceholder, model.block.title,
            model.block.spokenLabel, model.block.spokenValue, model.week.title,
            model.week.copyPrevious.title, model.week.deload.title, model.days.title, model.days.summary,
            model.days.helper, model.days.addDay.title
        ]
        texts += model.block.chips.flatMap { [$0.title, $0.subtitle, $0.spokenLabel, $0.spokenValue] }
        texts += model.week.cells.flatMap { [$0.letter, $0.label, $0.spokenLabel, $0.spokenValue] }
        texts += model.week.cells.compactMap(\.spokenHint) + [model.week.hint].compactMap(\.self)
        texts += model.days.cards.flatMap { [$0.tag, $0.name, $0.meta, $0.spokenLabel, $0.spokenValue] + $0.chips }
        texts += [model.week.applyToLater?.title, model.notice].compactMap(\.self)
        #expect(!texts.contains(""))
        #expect(!texts.contains { $0.hasPrefix(" ") || $0.hasSuffix(" ") || $0.contains(" ·  · ") })
    }

    /// Every action the model hands out.
    static func actions(of model: ProgramBuilderModel) -> [ProgramBuilderAction] {
        [model.block.removeWeek, model.block.addWeek, model.week.deload.action]
            + model.block.chips.map(\.action)
            + model.week.cells.compactMap(\.action)
            + [model.week.copyPrevious.action, model.week.applyToLater?.action, model.days.addDay.action]
            .compactMap(\.self)
            + model.days.cards.map(\.action)
    }
}
