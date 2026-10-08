#if os(iOS)
    @testable import FeatureToday
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// One VoiceOver stop of a hosted view, as the F09 S4 adversarial suites compare it (gate G2, round 1): what
    /// is read, its value, and what kind of stop it is. Printed on one line, so a failure shows a line.
    nonisolated struct ViewStop: Equatable, Sendable, CustomStringConvertible {
        enum Role: String, Sendable {
            case text, heading, button
            /// Both a button and a heading: no stop of Today is meant to be.
            case buttonHeading
        }

        let role: Role
        let label: String
        var value = ""
        var isEnabled = true

        static func text(_ label: String, value: String = "") -> Self {
            Self(role: .text, label: label, value: value)
        }

        static func heading(_ label: String) -> Self {
            Self(role: .heading, label: label)
        }

        static func button(_ label: String) -> Self {
            Self(role: .button, label: label)
        }

        var description: String {
            "\(role.rawValue) \"\(label)\"" + (value.isEmpty ? "" : " = \"\(value)\"") + (isEnabled ? "" : " (dimmed)")
        }
    }

    extension ViewStop {
        /// The stop UIKit hands VoiceOver for `element`.
        init(reading element: NSObject) {
            let traits = element.accessibilityTraits
            let role: Role =
                switch (traits.contains(.button), traits.contains(.header)) {
                case (true, true): .buttonHeading
                case (true, false): .button
                case (false, true): .heading
                case (false, false): .text
                }
            self.init(
                role: role,
                label: element.accessibilityLabel ?? "",
                value: element.accessibilityValue ?? "",
                isEnabled: !traits.contains(.notEnabled)
            )
        }
    }

    /// A state of the page with a name for the failure message.
    nonisolated struct ViewsCase: Sendable, CustomTestStringConvertible {
        let name: String
        let state: Loadable<TodayModel>
        /// The moment the model was made for: where the resume button's time stands still.
        var now = Fixtures.now

        var testDescription: String {
            name
        }

        var model: TodayModel? {
            if case let .loaded(model) = state {
                return model
            }
            return nil
        }
    }

    /// Hosting, reading and comparing, shared by the F09 S4 adversarial suites. Nothing here reads the views'
    /// sources: the expected trees are written from the specification and the model.
    enum TodayViews {
        struct Unreadable: Error {}

        /// A recorder of what a view sent.
        final class Sent {
            var actions: [TodayAction] = []
            var routes: [TodayRoute] = []
            var cancels = 0
        }

        /// The page as the screen scrolls it, its resume time standing still at the case's moment.
        static func page(_ item: ViewsCase, sent: Sent = Sent()) -> some View {
            TodayPage(state: item.state) { sent.actions.append($0) }
                .environment(\.todayTimerPause, item.now)
        }

        static func stops(
            of view: some View,
            at appearance: SnapshotAppearance = SnapshotAppearance(.light, .large)
        ) -> [ViewStop] {
            view.withAccessibilityElements(appearance) { $0.map(ViewStop.init(reading:)) }
        }

        /// The lines in which two trees differ, a few at most: never a whole tree in one expectation.
        nonisolated static func difference(found: [ViewStop], expected: [ViewStop]) -> [String] {
            var lines: [String] = []
            for index in 0 ..< max(found.count, expected.count) {
                let had = index < found.count ? found[index].description : "nothing"
                let wanted = index < expected.count ? expected[index].description : "nothing"
                if had != wanted {
                    lines.append("stop \(index + 1): found \(had), expected \(wanted)")
                }
            }
            return Array(lines.prefix(6))
        }

        /// Activates every stop of `view` once, in order, and returns each stop with what `sent` held more of
        /// after it.
        static func activations(of view: some View, sent: Sent) -> [(stop: ViewStop, sent: [TodayAction])] {
            view.withAccessibilityElements { elements in
                elements.map { element in
                    let before = sent.actions.count
                    _ = element.accessibilityActivate()
                    return (ViewStop(reading: element), Array(sent.actions[before...]))
                }
            }
        }
    }

    // MARK: - What the page must read, from the specification (S4 criterion 7) and the model alone

    nonisolated extension TodayViews {
        /// The tree of the page in `state`: the header (date, the title as the screen's heading, the gear), the
        /// strip's seven cells as the model words them, the card under its heading, each tile as one stop with
        /// the model's spoken line, and the recent list under its heading. Nothing while loading; the two texts
        /// when the load failed.
        static func expectedStops(for state: Loadable<TodayModel>) -> [ViewStop] {
            switch state {
            case .idle, .loading:
                []
            case .failed:
                [.heading(TodayCopy.failedTitle), .text(TodayCopy.failedBody)]
            case let .loaded(model):
                [.text(model.header.date), .heading(model.header.title), .button(model.header.settings.title)]
                    + model.weekStrip.map { .text($0.accessibilitySummary, value: markWord($0.mark)) }
                    + cardStops(model.card)
                    + [.text(model.stats.sessions.accessibilitySummary), .text(model.stats.volume.accessibilitySummary)]
                    + [.heading(model.recent.eyebrow)]
                    + model.recent.rows.map { .button("\($0.name), \($0.meta)") }
                    + (model.recent.emptyMessage.map { [.text($0)] } ?? [])
            }
        }

        /// `WeekStrip`'s spoken value of a mark (LedgerDesign's, pinned by its own tree tests).
        static func markWord(_ mark: WeekStrip.Mark) -> String {
            switch mark {
            case .done: "Done"
            case .today: "Today"
            case .planned: "Planned"
            case .rest: "Rest day"
            }
        }

        static func cardStops(_ card: TodayModel.Card) -> [ViewStop] {
            switch card {
            case let .upNext(card):
                [.heading(card.eyebrow)] + (card.meta.map { [.text($0)] } ?? []) + [.text(card.title)]
                    + card.rows.map { .text("\($0.name), \($0.scheme)") }
                    + [.button(card.action.action.title)]
            case let .logged(card):
                [
                    .heading(card.eyebrow), .text(card.elapsed), .text(card.title), .text(card.stats),
                    .button(card.action.title)
                ] + (card.next.map { [.text($0)] } ?? [])
            case let .restDay(card):
                [
                    .heading(card.eyebrow), .text(card.title), .text(card.body), .button(card.editWeek.title),
                    .button(card.offSchedule.title)
                ]
            case let .noProgram(card), let .blockComplete(card):
                [.heading(card.title), .text(card.body), .button(card.action.title)]
            }
        }

        /// What each button of the page must send, in reading order: the model's route for it, and the one
        /// action that is not a route, the rest-day card's request for the sheet.
        static func expectedActions(for model: TodayModel) -> [TodayAction] {
            let card: [TodayAction] =
                switch model.card {
                case let .upNext(card): [.route(card.action.action.route)]
                case let .logged(card): [.route(card.action.route)]
                case let .restDay(card): [.route(card.editWeek.route), .pickOffScheduleDay]
                case let .noProgram(card), let .blockComplete(card): [.route(card.action.route)]
                }
            return [.route(model.header.settings.route)] + card + model.recent.rows.map { .route($0.route) }
        }

        /// The sheet's page: which week, then one button per day, "Logged" read with a day already done.
        static func expectedSheetStops(_ model: TodayModel.OffSchedule) -> [ViewStop] {
            [.text(model.subtitle)] + model.days.map { day in
                .button(([day.name, day.detail] + (day.logged.map { [$0] } ?? [])).joined(separator: ", "))
            }
        }
    }
#endif
