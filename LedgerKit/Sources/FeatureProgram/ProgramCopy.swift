import Foundation
import LedgerDomain

/// FeatureProgram's copy (standards §7): every text the Program screens show or speak is looked up here, in
/// this module's `Resources/Localizable.xcstrings`, whose keys are the English text. No other file of the
/// module holds a user-facing literal or a lookup; `ProgramPresentation` is handed these `String`s and joins
/// fragments with " · ". A member whose key carries a value takes the locale its caller was given. The texts
/// of the training days and of the notices are in `ProgramCopy+Days.swift`.
///
/// Not here: weekday letters and names, which are the injected calendar's; program names, day names, tags and
/// exercise names, which are data.
nonisolated enum ProgramCopy {
    // MARK: Header and block

    static var myProgram: String {
        String(localized: "MY PROGRAM", bundle: .module, comment: "Eyebrow above the program's name")
    }

    static var programName: String {
        String(
            localized: "Program name",
            bundle: .module,
            comment: "Placeholder and spoken label of the field that holds the program's name"
        )
    }

    /// "BLOCK · 8 WEEKS".
    static func block(weeks: Int, locale: Locale) -> String {
        String(
            localized: "BLOCK · \(weeks) WEEKS",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Eyebrow of the block's weeks, with the number of weeks in the block"
        )
    }

    static var blockLength: String {
        String(
            localized: "Block length",
            bundle: .module,
            comment: "Spoken label of the control that adds a week to the block or removes its last week"
        )
    }

    /// "8 weeks": what VoiceOver reads as the block's length.
    static func weeks(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) weeks",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Spoken value of the block's length"
        )
    }

    /// "W3": a week's chip.
    static func weekChip(_ number: Int, locale: Locale) -> String {
        String(
            localized: "W\(number)",
            bundle: .module,
            locale: locale,
            comment: "A week's chip: W for week, then the week's number, counted from 1"
        )
    }

    /// "4 DAYS": the training days a week schedules, under its chip.
    static func scheduledDays(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) DAYS",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Under a week's chip: the number of days that week trains"
        )
    }

    static var deloadMark: String {
        String(localized: "DELOAD", bundle: .module, comment: "Marks a deload week, under its chip and in its title")
    }

    /// "Week 3": what VoiceOver reads for a week's chip, and the start of the Day editor's summary line.
    static func week(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Week \(number)",
            bundle: .module,
            locale: locale,
            comment: "A week by its number, counted from 1: a chip's spoken label, and the Day editor's summary"
        )
    }

    /// "4 days": the program's training days in the summary, and a week's training days as VoiceOver reads them.
    static func days(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) days",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "A number of training days"
        )
    }

    // MARK: The selected week

    /// "WEEK 3".
    static func weekTitle(_ number: Int, locale: Locale) -> String {
        String(
            localized: "WEEK \(number)",
            bundle: .module,
            locale: locale,
            comment: "Eyebrow of the selected week's schedule: the week's number, counted from 1"
        )
    }

    static var tapToAssign: String {
        String(localized: "Tap to assign", bundle: .module, comment: "Hint beside the week's schedule")
    }

    static var rest: String {
        String(
            localized: "REST",
            bundle: .module,
            comment: "A weekday with no training day, in the week's schedule; also the label of the stepper for rest"
        )
    }

    static var restSpoken: String {
        String(
            localized: "Rest",
            bundle: .module,
            comment: "Spoken value of a weekday with no training day; also the spoken label of the stepper for rest"
        )
    }

    static var assignHint: String {
        String(
            localized: "Double-tap to assign",
            bundle: .module,
            comment: "Spoken hint of a weekday in the week's schedule: the tap assigns the next training day"
        )
    }

    static var firstWeek: String {
        String(
            localized: "First week",
            bundle: .module,
            comment: "Disabled button on the first week, where another week reads: Copy week 2"
        )
    }

    /// "Copy week 2": the button that gives the selected week the schedule of the week before it.
    static func copyWeek(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Copy week \(number)",
            bundle: .module,
            locale: locale,
            comment: "Button: the selected week takes the schedule of the week with this number"
        )
    }

    static var applyToLaterWeeks: String {
        String(localized: "Apply to later weeks", bundle: .module)
    }

    static var deload: String {
        String(
            localized: "Deload",
            bundle: .module,
            comment: "Button that makes the selected week a deload week; also a deload week's spoken value"
        )
    }
}

// MARK: - Counted texts

nonisolated extension Locale {
    /// The locale every counted text of the module is looked up with: the Domain's `forCountedText(in:)`,
    /// the one place that decides it, with this module's catalog. The plural form is the catalog's
    /// language's; the digits and their grouping stay the lifter's.
    var forCountedText: Locale {
        forCountedText(in: .module)
    }
}
