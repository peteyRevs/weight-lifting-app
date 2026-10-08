import Foundation
import LedgerDomain

/// The Program builder's logic and its words: one pure function from a `ProgramBuilderInput` to the
/// `ProgramBuilderModel` the views draw.
///
/// It reads its input and nothing else. It holds no rule of the block: which day a tap assigns and whether
/// the last week can go are asked of `ProgramEditing`, a day's minutes of `TimeEstimate`, and every action it
/// hands out is an edit `ProgramEditing` applies. A weekday and a deload are edited by what they become. Every text
/// comes from `ProgramCopy`, except the weekday
/// letters and names, which are the injected calendar's in the injected locale.
///
/// The block and the selected week are in `+Weeks`, the training days in `+Days`.
nonisolated enum ProgramPresentation {
    /// What joins the fragments of a line: "4 days · 58 sets a week" (M1 convention).
    static let separator = " · "

    static func make(_ input: ProgramBuilderInput) -> ProgramBuilderModel {
        let context = Context(input)
        return ProgramBuilderModel(
            header: ProgramBuilderModel.Header(
                eyebrow: ProgramCopy.myProgram,
                name: input.program.name,
                namePlaceholder: ProgramCopy.programName
            ),
            block: block(context),
            week: selectedWeek(context),
            days: trainingDays(context),
            notice: input.notice.map { text(of: $0, locale: input.locale) }
        )
    }

    /// A notice as the line the builder shows.
    static func text(of notice: ProgramBuilderNotice, locale: Locale) -> String {
        switch notice {
        case .minimumTwoWeeks: ProgramCopy.minimumTwoWeeks
        case let .weekHasLoggedSessions(weekNumber): ProgramCopy.weekHasLoggedSessions(weekNumber, locale: locale)
        case .dayHasNoExercises: ProgramCopy.dayHasNoExercises
        }
    }

    /// The day the week at `place` of `program` trains on `weekday`. Nil is rest: no entry, an entry that
    /// names a day the program does not hold, or a place the block does not have. The chips' counts and the
    /// strip's cells both read the schedule through here, so they cannot disagree.
    static func scheduledDay(in program: Program, week place: Int, on weekday: Weekday) -> DayTemplate? {
        guard program.weeks.indices.contains(place), let id = program.weeks[place].schedule[weekday] else {
            return nil
        }
        return program.days.first { $0.id == id }
    }
}

// MARK: - The input, resolved once

nonisolated extension ProgramPresentation {
    /// The input, with what several parts of the model need from it: the selected week's place and the
    /// weekdays' letters and names. Built once per `make`.
    struct Context {
        let input: ProgramBuilderInput
        /// The selected week's place in the block: the input's when the block has it, the first week for a
        /// place before the block, the last for one after it.
        let selected: Int
        /// The seven weekdays from the settings' week start, the order of the strip's cells.
        let weekdays: [Weekday]
        /// The calendar's weekday letters and names in the injected locale, as Foundation orders them: Sunday
        /// first.
        private let letters: [String]
        private let names: [String]

        init(_ input: ProgramBuilderInput) {
            self.input = input
            selected = ProgramPresentation.nearestPlace(to: input.selectedWeek, in: input.program.weeks.indices)
            let weekStart = input.settings.weekStart
            weekdays = Weekday.allCases.filter { $0 >= weekStart } + Weekday.allCases.filter { $0 < weekStart }
            var calendar = input.calendar
            calendar.locale = input.locale
            letters = calendar.veryShortStandaloneWeekdaySymbols
            names = calendar.standaloneWeekdaySymbols
        }

        var program: Program {
            input.program
        }

        var locale: Locale {
            input.locale
        }

        /// "T".
        func letter(of weekday: Weekday) -> String {
            ProgramPresentation.symbol(of: weekday, in: letters)
        }

        /// "Tuesday".
        func name(of weekday: Weekday) -> String {
            ProgramPresentation.symbol(of: weekday, in: names)
        }
    }

    /// The week a selection means: `place` when the block has it, the first week for a place before the
    /// block, the last for one after it, and 0 in a block with no week.
    static func nearestPlace(to place: Int, in places: Range<Int>) -> Int {
        if places.contains(place) {
            return place
        }
        return place < 0 ? 0 : places.last ?? 0
    }

    /// The symbol of `weekday` among a calendar's weekday symbols, which Foundation orders from Sunday; empty
    /// for a calendar that has none at its place.
    static func symbol(of weekday: Weekday, in symbols: [String]) -> String {
        let place = weekday.calendarWeekday - 1
        return symbols.indices.contains(place) ? symbols[place] : ""
    }
}
