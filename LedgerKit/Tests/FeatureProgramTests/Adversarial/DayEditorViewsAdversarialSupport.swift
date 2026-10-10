#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// States of the Day editor that no preview draws, for the F11 S10 adversarial suites (gate G2, round 1).
    /// The first six are the models the presentation makes of days the Domain's own edits reach; the last two
    /// are such a model under words longer than the seed's.
    nonisolated enum DayViewsState: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// A day with no exercise, scheduled nowhere: the header and the two buttons.
        case emptyDay
        /// Lower A in week 4, the squat open after a missed week 3: "WEEK 4 · HELD".
        case heldWeek
        /// Upper A, its first exercise open and not stored: a row with no load and a panel of actions alone.
        case unstoredOpen
        /// Upper A in the deload week, the first exercise of its superset open.
        case deloadSupersetOpen
        /// Upper A, the last exercise of the day and of its superset open: no "Move down".
        case lastOpen
        /// Twelve exercises, the third to the fifth one superset, its last one open: both superset actions.
        case twelve
        /// The double progression's panel under loads of five digits and a half.
        case fiveDigits
        /// A long day name, one-word and long exercise names, a superset's note of several lines.
        case longWords

        static let longNote = "5 exercises back to back with no rest between them · rest 2:30 after the last, E"
        static let longName = "Single-Arm Half-Kneeling Landmine Press with a pause at the top and a slow negative"
        static let longDay = "Upper body, pressing and pulling, with every accessory the gym has room for"
        static let load = "12,345.5"

        var testDescription: String {
            rawValue
        }

        func input() throws -> DayEditorInput {
            let upperA = ProgramFixtures.DayIndex.upperA
            switch self {
            case .emptyDay:
                return try DayEditorFixtures.input(slots: [])
            case .heldWeek:
                let lowerA = ProgramFixtures.DayIndex.lowerA
                var input = try DayEditorFixtures.seedInput(dayIndex: lowerA, weekIndex: 3)
                input.program.days[lowerA].slots[0].misses = [2]
                input.openSlot = input.program.days[lowerA].slots[0].id
                return input
            case .unstoredOpen:
                var input = try DayEditorFixtures.seedInput()
                let slot = input.program.days[upperA].slots[0]
                input.exercises[slot.exerciseID] = nil
                input.openSlot = slot.id
                return input
            case .deloadSupersetOpen:
                var input = try DayEditorFixtures.seedInput(weekIndex: 7)
                input.openSlot = input.program.days[upperA].slots[3].id
                return input
            case .lastOpen:
                var input = try DayEditorFixtures.seedInput()
                input.openSlot = input.program.days[upperA].slots[4].id
                return input
            case .twelve:
                return try Self.twelve()
            case .fiveDigits, .longWords:
                var input = try DayEditorFixtures.seedInput()
                input.openSlot = input.program.days[upperA].slots[1].id
                return input
            }
        }

        private static func twelve() throws -> DayEditorInput {
            var day = try ProgramFixtures.day(1, slotCount: 12)
            for place in [3, 4] {
                day = DayEditing.setSuperset(true, slot: day.slots[place].id, in: day)
            }
            var input = try DayEditorFixtures.input(ProgramFixtures.program(weekCount: 3, days: [day]))
            input.openSlot = day.slots[4].id
            return input
        }

        func model() throws -> DayEditorModel.Content {
            let made = try DayEditorPresentation.make(input()).content()
            switch self {
            case .fiveDigits:
                return DayViewsText(change: { path, text in
                    let isALoad = path.hasSuffix(".load") || path.hasPrefix("panel.entry.")
                        || path == "panel.field.3.value"
                    if isALoad || path == "panel.week.line" {
                        return text.replacingOccurrences(of: "52.5", with: Self.load)
                            .replacingOccurrences(of: "47.5", with: Self.load)
                            .replacingOccurrences(of: "50", with: Self.load)
                            .replacingOccurrences(of: "55", with: Self.load)
                    }
                    return text
                }).content(made)
            case .longWords:
                return DayViewsText(change: { path, text in
                    switch path {
                    case "header.name": Self.longDay
                    case "row.0.name": "Hyperextension"
                    case "row.1.name", "row.3.name": Self.longName
                    case "row.4.name": "Concentration Curl"
                    case "group.3.note": Self.longNote
                    default: text
                    }
                }).content(made)
            default:
                return made
            }
        }
    }

    // MARK: - What a model must read and send, from the notes' tables and the model alone

    /// The VoiceOver tree a Day editor's model must give, the pinned header's over the page's, written from
    /// the plan's tree (notes, "One pinned VoiceOver tree per screen"), from "Inputs for the views (S10,
    /// S11)" and from the model, never from a view; each stop with what it must send. A stepper is swiped
    /// down, up and up again; every other stop is activated once.
    ///
    /// Three places where it follows the implementer's notes and not the plan's tree, all three listed there
    /// for the product owner: "Done" is read before the heading; the chosen progression is selected text and
    /// no button (criterion 6); the day's name is in no hosted tree (`DayEditorTextFieldTests`).
    nonisolated enum DayViewsOracle {
        struct Expected: Sendable {
            let stop: ViewStop
            var sends: [DayEditorAction] = []
        }

        static func tree(_ model: DayEditorModel.Content) -> [Expected] {
            let header = model.header
            var stops = [
                Expected(stop: .button(header.back.title), sends: [header.back.action]),
                Expected(stop: .button(header.done.title), sends: [header.done.action]),
                Expected(stop: .heading(header.position)),
                Expected(stop: .text(header.meta))
            ]
            for group in model.groups {
                if let superset = group.header {
                    stops.append(Expected(stop: .heading(superset.spokenLabel, value: superset.note)))
                }
                for row in group.rows {
                    let stop = ViewStop.row(row.spokenLabel, value: row.spokenValue, isOpen: row.isOpen)
                    stops.append(Expected(stop: stop, sends: [row.action]))
                    stops += row.panel.map(panel) ?? []
                }
            }
            return stops + [
                Expected(stop: .button(model.addExercise.title), sends: [model.addExercise.action]),
                // "Delete day" asks first: activating it sends nothing.
                Expected(stop: .button(model.deleteDay.title))
            ]
        }

        static func panel(_ panel: SlotEditorModel) -> [Expected] {
            var stops: [Expected] = []
            if let details = panel.details {
                stops.append(Expected(stop: .text(details.week.eyebrow, value: details.week.line)))
                stops += details.fields.map {
                    Expected(
                        stop: .adjustable($0.spokenLabel, value: $0.value),
                        sends: [$0.decrement, $0.increment, $0.increment]
                    )
                }
                stops.append(Expected(stop: .heading(details.progression.title)))
                stops += details.progression.chips.map { chip in
                    chip.action.map {
                        Expected(stop: .button(chip.title, selected: chip.isSelected), sends: [$0])
                    } ?? Expected(stop: .chosen(chip.title))
                }
                stops.append(Expected(stop: .text(details.progression.note)))
                let dropSet = details.dropSet
                stops.append(Expected(
                    stop: .toggle(dropSet.title, isOn: dropSet.isOn, hint: dropSet.note), sends: [dropSet.action]
                ))
            }
            let controls = panel.supersetActions + [panel.moveUp, panel.moveDown, panel.remove].compactMap(\.self)
            stops += controls.map { Expected(stop: .button($0.title), sends: [$0.action]) }
            if let details = panel.details {
                stops.append(Expected(stop: .text(details.strip.text)))
            }
            return stops
        }

        /// The first stop that did not send what the oracle says, as one line, or nil.
        static func firstWrongSend(_ sent: [[DayEditorAction]], _ expected: [Expected]) -> String? {
            guard sent.count == expected.count else {
                return "\(sent.count) stops were walked, \(expected.count) were expected"
            }
            for (place, pair) in zip(sent, expected).enumerated() where pair.0 != pair.1.sends {
                return "stop \(place + 1), \(pair.1.stop), sent \(pair.0.count) actions: \(pair.0)"
            }
            return nil
        }
    }

    /// Hosting and walking, shared by the F11 S10 adversarial suites.
    enum DayViewsProbe {
        /// What each stop of a model's header and page sends, top to bottom: a stepper swiped down, up and
        /// up, every other stop activated once.
        static func sentByEachStop(
            of model: DayEditorModel.Content,
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large)
        ) -> [[DayEditorAction]] {
            var sent: [DayEditorAction] = []
            return DayEditorParts(model: model) { sent.append($0) }.withAccessibilityElements(appearance) { elements in
                elements.map { element in
                    let before = sent.count
                    if element.accessibilityTraits.contains(.adjustable) {
                        element.accessibilityDecrement()
                        element.accessibilityIncrement()
                        element.accessibilityIncrement()
                    } else {
                        _ = element.accessibilityActivate()
                    }
                    return Array(sent[before...])
                }
            }
        }

        /// The first difference between what a model's parts read and the oracle's tree, or nil.
        static func difference(
            of model: DayEditorModel.Content,
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large),
            isRightToLeft: Bool = false
        ) -> String? {
            let found = DayEditorParts(model: model)
                .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
                .stops(appearance)
            return firstDifference(found: found, expected: DayViewsOracle.tree(model).map(\.stop))
        }

        /// The models every whole-page check runs over: the seven previews and this tester's eight.
        static func models() throws -> [(name: String, model: DayEditorModel.Content)] {
            try ProgramPreview.dayEditors.map { try ($0.rawValue, $0.dayEditorModel()) }
                + DayViewsState.allCases.map { try ($0.rawValue, $0.model()) }
        }
    }
#endif
