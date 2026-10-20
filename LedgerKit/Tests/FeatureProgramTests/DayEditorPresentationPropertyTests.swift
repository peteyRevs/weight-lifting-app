@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Seeded checks of `DayEditorPresentation.make(_:)` on random days (`+Inputs`): the model is whole and agrees
/// with the day; every action names the day and a slot it holds; nothing is offered that does nothing, but a
/// stepper at its limit; every edit not marked relative is safe to apply twice; and any chain of taps leaves
/// a program the Domain accepts.
@Suite("DayEditorPresentation properties", .tags(.feature, .property))
nonisolated struct DayEditorPresentationPropertyTests {
    @Test("Any day gives a whole model that agrees with the day", arguments: PropertySeed.all)
    func make_randomDay_keepsTheInvariants(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 2 {
            let input = try Self.input(using: &generator)
            let model = DayEditorPresentation.make(input)
            let isSame = DayEditorPresentation.make(input) == model
            #expect(isSame, "the same input gave another model")
            guard let day = input.program.days.first(where: { $0.id == input.day }) else {
                #expect(model.isGone)
                continue
            }
            let content = try model.content()
            Self.checkRows(content, day, input)
            Self.checkTexts(content)
            try Self.checkPanel(content, day, input)
        }
    }

    @Test(
        "Every action names the day and a slot it holds, and only a move differs when applied twice",
        arguments: PropertySeed.all
    )
    func actions_randomDay_nameTheDayAndAreSafeTwice(seed: PropertySeed) throws {
        var generator = seed.generator
        let input = try Self.input(using: &generator, holdsTheDay: true)
        let day = try #require(input.program.days.first { $0.id == input.day })
        let content = try DayEditorPresentation.make(input).content()
        for action in Self.actions(of: content) {
            guard case let .edit(edit, _) = action else {
                continue
            }
            if case let .slot(slotEdit, named) = edit {
                #expect(named == day.id, "\(edit)")
                #expect(day.slots.contains { $0.id == slotEdit.slot }, "\(edit) names a slot the day lacks")
            }
            let once = edit.applied(to: input.program)
            if !edit.isRelative {
                let isSame = edit.applied(to: once) == once
                #expect(isSame, "\(edit) gave another program the second time")
            }
        }
    }

    @Test("Nothing is offered that leaves the day as it is, except a stepper at its limit", arguments: PropertySeed.all)
    func controls_randomDay_allDoSomething(seed: PropertySeed) throws {
        var generator = seed.generator
        let input = try Self.input(using: &generator, holdsTheDay: true)
        let content = try DayEditorPresentation.make(input).content()
        guard let panel = content.rows.first(where: \.isOpen)?.panel else {
            return
        }
        let offered = panel.supersetActions.map(\.action) + [panel.moveUp, panel.moveDown, panel.remove]
            .compactMap(\.self).map(\.action)
            + (panel.details.map { $0.progression.chips.compactMap(\.action) + [$0.dropSet.action] } ?? [])
        for action in offered {
            guard case let .edit(edit, _) = action else {
                Issue.record("\(action) is not an edit")
                continue
            }
            let hasChanged = edit.applied(to: input.program) != input.program
            #expect(hasChanged, "\(edit) is offered and does nothing")
        }
        // A stepper offers both directions whatever the value; at a limit the Domain holds the value.
        for field in panel.details?.fields ?? [] {
            for action in [field.decrement, field.increment] {
                guard case let .edit(edit, false) = action else {
                    Issue.record("\(action) is not an edit that leaves the panel open")
                    continue
                }
                var screen = DayScreen(input)
                try screen.tap(action)
                let after = try #require(screen.day).slots.first { $0.id == input.openSlot }
                try Self.checkRanges(#require(after), "\(edit)")
            }
        }
    }

    @Test(
        "Any chain of taps, applied as a store applies them, leaves a program the Domain accepts",
        arguments: PropertySeed.all
    )
    func taps_randomDay_leaveAValidProgram(seed: PropertySeed) throws {
        var generator = seed.generator
        var screen = try DayScreen(Self.input(using: &generator, holdsTheDay: true))
        for _ in 0 ..< 10 {
            guard case let .editing(content) = screen.model else {
                // The day was deleted: nothing more is offered.
                let isDeleted = screen.day == nil
                #expect(isDeleted)
                return
            }
            let action = try #require(Self.actions(of: content).randomElement(using: &generator))
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
            for slot in screen.day?.slots ?? [] {
                Self.checkRanges(slot, "\(action)")
            }
            // Every edit of the day's slots returns the day in the Domain's normal form.
            if case .edit(.slot, _) = action {
                #expect(screen.day?.slots.first?.isSupersetWithPrevious != true, "\(action)")
            }
        }
    }
}

// MARK: - The invariants

nonisolated extension DayEditorPresentationPropertyTests {
    /// Every action the model hands out.
    static func actions(of content: DayEditorModel.Content) -> [DayEditorAction] {
        var actions = [
            content.header.back.action, content.header.done.action, content.addExercise.action,
            content.deleteDay.confirmation.confirm.action
        ]
        for row in content.rows {
            actions.append(row.action)
            guard let panel = row.panel else {
                continue
            }
            actions += panel.supersetActions.map(\.action) + [panel.remove.action]
            actions += [panel.moveUp, panel.moveDown].compactMap(\.self).map(\.action)
            if let details = panel.details {
                actions += details.fields.flatMap { [$0.decrement, $0.increment] }
                actions += details.progression.chips.compactMap(\.action) + [details.dropSet.action]
            }
        }
        return actions
    }

    /// The rows are the day's slots, in order, in the Domain's groups; at most one is open, the input's.
    static func checkRows(_ content: DayEditorModel.Content, _ day: DayTemplate, _ input: DayEditorInput) {
        #expect(content.id == day.id)
        #expect(content.rows.map(\.id) == day.slots.map(\.id))
        #expect(content.groups.map { $0.rows.map(\.id) } == DayEditing.groups(of: day))
        for group in content.groups {
            #expect((group.header != nil) == (group.rows.count > 1))
            #expect(!group.rows.isEmpty)
            // Only the last member of a group rests.
            let rests = group.rows.map { !$0.sub.hasSuffix("no rest") }
            #expect(rests == group.rows.indices.map { $0 == group.rows.count - 1 }, "\(rests)")
        }
        let open = content.rows.filter(\.isOpen)
        #expect(open.map(\.id) == day.slots.map(\.id).filter { $0 == input.openSlot })
        #expect(content.rows.allSatisfy { ($0.panel != nil) == $0.isOpen })
        for (row, slot) in zip(content.rows, day.slots) {
            let isStored = input.exercises[slot.exerciseID] != nil
            #expect((row.load != nil) == isStored)
            #expect(row.action == .open(row.isOpen ? nil : slot.id))
        }
        if input.locale.identifier == "en_US" {
            let position = (input.program.days.firstIndex { $0.id == day.id } ?? -1) + 1
            #expect(content.header.position == "DAY \(position) OF \(input.program.days.count)")
        }
    }

    /// No text of the model is empty.
    static func checkTexts(_ content: DayEditorModel.Content) {
        let header = content.header
        var texts = [
            header.back.title, header.position, header.done.title, header.nameLabel, header.meta,
            content.addExercise.title, content.deleteDay.title, content.deleteDay.confirmation.title,
            content.deleteDay.confirmation.confirm.title, content.deleteDay.confirmation.cancel
        ]
        texts += content.groups.compactMap(\.header).flatMap { [$0.title, $0.note, $0.spokenLabel] }
        for row in content.rows {
            texts += [row.index, row.name, row.sub, row.scheme, row.spokenLabel, row.spokenValue]
            guard let panel = row.panel else {
                continue
            }
            texts += (panel.supersetActions + [panel.moveUp, panel.moveDown, panel.remove].compactMap(\.self))
                .map(\.title)
            if let details = panel.details {
                texts += [details.week.eyebrow, details.week.line, details.progression.title]
                texts += [details.progression.note, details.dropSet.title, details.dropSet.note, details.strip.text]
                texts += details.fields.flatMap { [$0.label, $0.value, $0.spokenLabel] }
                texts += details.progression.chips.map(\.title) + details.strip.entries.map(\.text)
            }
        }
        #expect(texts.allSatisfy { !$0.isEmpty }, "\(texts.filter(\.isEmpty).count) empty of \(texts.count)")
        #expect(content.deleteDay.confirmation.message?.isEmpty != true)
    }

    /// The open panel agrees with the Domain: a move is offered exactly when the Domain's move changes the
    /// order, the details exist exactly when the exercise is stored, the strip has one entry a week.
    static func checkPanel(_ content: DayEditorModel.Content, _ day: DayTemplate, _ input: DayEditorInput) throws {
        guard let row = content.rows.first(where: \.isOpen) else {
            return
        }
        let panel = try #require(row.panel)
        let slot = try #require(day.slots.first { $0.id == row.id })
        let order = day.slots.map(\.id)
        #expect((panel.moveUp != nil) == (DayEditing.move(day, slot: slot.id, .upward).slots.map(\.id) != order))
        #expect((panel.moveDown != nil) == (DayEditing.move(day, slot: slot.id, .downward).slots.map(\.id) != order))
        #expect(panel.remove.action == .edit(.slot(.remove(slot: slot.id), day: day.id), closesPanel: true))
        let weeks = input.program.weeks
        #expect((panel.details != nil) == (input.exercises[slot.exerciseID] != nil))
        guard let details = panel.details else {
            return
        }
        #expect(details.fields.count == (slot.progression == .double ? 6 : 5))
        #expect(details.selectedProgressions.count == 1)
        #expect(details.dropSet.isOn == (slot.dropSets > 0))
        #expect(details.strip.entries.count == weeks.count)
        #expect(details.strip.entries.map(\.isDeload) == weeks.map(\.isDeload))
        #expect(details.strip.entries.filter(\.isShown).count == 1)
        #expect(details.strip.text == details.strip.entries.map(\.text).joined(separator: " · "))
        // A held week is one whose week before was missed, unless it is a deload.
        let held = weeks.indices.map { slot.misses.contains($0 - 1) && !weeks[$0].isDeload }
        #expect(details.strip.entries.map(\.isHeld) == held)
        let shown = try #require(details.strip.entries.firstIndex { $0.isShown })
        #expect(details.week.isDeload == weeks[shown].isDeload)
        #expect(details.week.isHeld == held[shown])
    }

    /// The slot is one `Slot.init` accepts.
    static func checkRanges(_ slot: Slot, _ note: String) {
        #expect(Slot.setsRange.contains(slot.sets), "\(note)")
        #expect(Slot.repsRange.contains(slot.reps), "\(note)")
        #expect(Slot.repsHiRange.contains(slot.repsHi) && slot.repsHi > slot.reps, "\(note)")
        #expect((slot.startLoad ?? .zero) >= .zero, "\(note)")
        #expect((0 ... 1).contains(slot.dropSets), "\(note)")
        #expect((30 ... 300).contains(slot.rest.seconds) && (5 ... 10).contains(slot.rpe.value), "\(note)")
    }
}
