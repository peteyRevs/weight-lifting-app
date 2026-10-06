@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain

/// The oracle against a model: each disagreement as one short line, so a suite compares a `Bool` and prints
/// only these lines (a whole `TodayModel` is never handed to `#expect`).
nonisolated extension TodayOracle {
    typealias Support = TodayAdversarial

    func problems(in model: TodayModel, for input: TodayInput) -> [String] {
        headerProblems(model.header)
            + stripProblems(model.weekStrip)
            + cardProblems(model.card, input)
            + statsProblems(model.stats, input)
    }

    func headerProblems(_ header: TodayModel.Header) -> [String] {
        var problems: [String] = []
        if header.date != Support.fullDate(today) {
            problems.append("header.date \"\(header.date)\", expected \"\(Support.fullDate(today))\"")
        }
        if header.title != title {
            problems.append("header.title \"\(header.title)\", expected \"\(title)\"")
        }
        if header.settings.title != "Settings" || header.settings.route != .settings {
            problems.append("header.settings is \"\(header.settings.title)\" → \(header.settings.route)")
        }
        return problems
    }

    func stripProblems(_ strip: [WeekStrip.Day]) -> [String] {
        guard strip.count == 7 else {
            return ["the strip has \(strip.count) days"]
        }
        var problems: [String] = []
        for (index, cell) in strip.enumerated() {
            let day = days[index]
            if cell.mark != marks[index] {
                problems.append("strip \(day) is \(cell.mark), expected \(marks[index])")
            }
            if cell.weekday != Support.letter(day) || cell.date != String(day.day) {
                problems.append("strip \(day) reads \"\(cell.weekday)\" \"\(cell.date)\"")
            }
            let spoken = Support.fullDate(day)
            let isTodayDone = day == today && marks[index] == .done
            if isTodayDone ? !cell.accessibilitySummary.contains(spoken) : cell.accessibilitySummary != spoken {
                problems.append("strip \(day) speaks \"\(cell.accessibilitySummary)\"")
            }
        }
        return problems
    }

    func statsProblems(_ stats: TodayModel.Stats, _ input: TodayInput) -> [String] {
        let units = input.settings.units
        var problems: [String] = []
        if stats.sessions.value != String(done) || stats.sessions.unit != "/\(planned)" {
            problems.append("sessions \"\(stats.sessions.value)\(stats.sessions.unit)\", expected \(done)/\(planned)")
        }
        if stats.sessions.caption != "sessions this week" || stats.sessions.delta != nil {
            problems.append("sessions caption \"\(stats.sessions.caption)\" delta \(stats.sessions.delta ?? "nil")")
        }
        if stats.volume.value != volume.thousands(in: units) || stats.volume.unit != "k" {
            problems.append(
                "volume \"\(stats.volume.value)\(stats.volume.unit)\", expected \(volume.thousands(in: units))k"
            )
        }
        if stats.volume.caption != (units == .lb ? "lb moved" : "kg moved") {
            problems.append("volume caption \"\(stats.volume.caption)\" in \(units)")
        }
        let change = input.previousWeekVolume.flatMap { volume.percentChange(from: $0) }
        if stats.volume.delta != change.map(Self.changeText) {
            problems
                .append(
                    "volume delta \(stats.volume.delta ?? "nil"), expected change \(change.map(String.init) ?? "nil")"
                )
        }
        return problems
    }

    /// "+8%", "−3%" with a real minus sign (U+2212), and "0%" (the brief gives no text for no change).
    static func changeText(_ percent: Int) -> String {
        if percent > 0 {
            return "+\(percent)%"
        }
        return percent < 0 ? "\u{2212}\(percent.magnitude)%" : "0%"
    }
}

// MARK: - The card

nonisolated extension TodayOracle {
    func cardProblems(_ actual: TodayModel.Card, _ input: TodayInput) -> [String] {
        let problems: [String]? = switch (card, actual) {
        case let (.resume, .upNext(shown)): resumeProblems(shown, input)
        case let (.start(week, day), .upNext(shown)): startProblems(shown, input, week: week, day: day)
        case let (.logged(ids, week), .logged(shown)): loggedProblems(shown, ids: ids, week: week)
        case let (.rest(week), .restDay(shown)): restProblems(shown, input, week: week)
        case let (.noProgram, .noProgram(shown)): Self.messageProblems(shown, route: .setUpProgram)
        case let (.blockComplete, .blockComplete(shown)): Self.messageProblems(shown, route: .openProgram)
        default: nil
        }
        return problems ?? ["card is \(Self.name(of: actual)), expected \(card)"]
    }

    static func name(of card: TodayModel.Card) -> String {
        switch card {
        case let .upNext(shown): "upNext(\(shown.action.action.route))"
        case let .logged(shown): "logged(\(shown.action.route))"
        case let .restDay(shown): "restDay(\(shown.editWeek.route))"
        case .noProgram: "noProgram"
        case .blockComplete: "blockComplete"
        }
    }

    func resumeProblems(_ shown: TodayModel.UpNext, _ input: TodayInput) -> [String] {
        guard case let .resume(action, startedAt) = shown.action else {
            return ["a live workout, yet the card offers \"\(shown.action.action.title)\""]
        }
        var problems: [String] = []
        if action.route != .resumeWorkout || startedAt != input.session?.startedAt {
            problems.append("resume carries \(action.route) from \(startedAt)")
        }
        if shown.title != input.session?.name || shown.eyebrow != "UP NEXT" {
            problems.append("resume card reads \"\(shown.eyebrow)\" \"\(shown.title)\"")
        }
        return problems
    }

    func startProblems(_ shown: TodayModel.UpNext, _ input: TodayInput, week: Int, day: DayTemplateID) -> [String] {
        guard case let .start(action) = shown.action, let program = input.program else {
            return ["no live workout, yet the card offers \"\(shown.action.action.title)\""]
        }
        var problems: [String] = []
        if action.route != .startWorkout(program: program.id, weekIndex: week, day: day) {
            problems.append("start carries \(action.route), expected week \(week)")
        }
        let name = program.days.first { $0.id == day }?.name
        if action.title != "Start workout" || shown.eyebrow != "UP NEXT" || shown.title != name {
            problems.append("start card reads \"\(shown.eyebrow)\" \"\(shown.title)\" \"\(action.title)\"")
        }
        return problems
    }

    func loggedProblems(_ shown: TodayModel.Logged, ids: Set<WorkoutID>, week: Int) -> [String] {
        var problems: [String] = []
        if !ids.contains(where: { shown.action.route == .openWorkout($0) }) {
            problems.append("logged carries \(shown.action.route), not the newest of today's")
        }
        if shown.eyebrow != "LOGGED · WEEK \(week + 1)" || shown.action.title != "View session" {
            problems.append("logged card reads \"\(shown.eyebrow)\" \"\(shown.action.title)\"")
        }
        return problems
    }

    func restProblems(_ shown: TodayModel.RestDay, _ input: TodayInput, week: Int) -> [String] {
        guard let program = input.program else {
            return ["a rest day without a program"]
        }
        var problems: [String] = []
        if shown.editWeek.route != .editWeek(program: program.id, weekIndex: week) {
            problems.append("edit carries \(shown.editWeek.route), expected week \(week)")
        }
        let titles = [shown.eyebrow, shown.title, shown.editWeek.title, shown.offSchedule.title]
        if titles != ["SCHEDULED REST", "No session today", "Edit this week", "Train off-schedule"] {
            problems.append("rest card reads \(titles)")
        }
        let offered = shown.offSchedule.days.map(\.route)
        let expected = program.days.map { TodayRoute.startWorkout(program: program.id, weekIndex: week, day: $0.id) }
        if program.weeks.contains(where: { $0.index == week }), offered != expected {
            problems.append("off-schedule offers \(offered.count) day(s), not the program's \(expected.count) in order")
        }
        return problems
    }

    static func messageProblems(_ shown: TodayModel.Message, route: TodayRoute) -> [String] {
        shown.action.route == route ? [] : ["the card carries \(shown.action.route), expected \(route)"]
    }
}
