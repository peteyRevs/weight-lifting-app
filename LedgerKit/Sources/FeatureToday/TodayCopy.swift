import Foundation
import LedgerDomain

/// FeatureToday's copy (standards §7): every text Today shows or speaks is looked up here, in this module's
/// `Resources/Localizable.xcstrings`, whose keys are the English text. No other file of the module holds a
/// user-facing literal or a lookup; `TodayPresentation` is handed these `String`s and joins fragments with " · ".
/// A member whose key carries a value takes the locale its caller was given. The cards' texts are in
/// `TodayCopy+Cards.swift`.
nonisolated enum TodayCopy {
    // MARK: Header and week strip

    /// The title when there is no program or the block is complete, and the day of a workout that started today.
    static var today: String {
        String(localized: "Today", bundle: .module, comment: "Title of the Today screen; also the day of a workout")
    }

    static var restDay: String {
        String(localized: "Rest day", bundle: .module, comment: "Title of the Today screen on a day with no session")
    }

    static var settings: String {
        String(localized: "Settings", bundle: .module, comment: "Spoken label of the button that opens Settings")
    }

    /// What VoiceOver reads for today's day in the week strip once it is trained: its mark then says "Done", so
    /// the label says which day is today. `date` is "Wednesday, September 16".
    static func todaySummary(_ date: String, locale: Locale) -> String {
        String(
            localized: "Today, \(date)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of today in the week strip, before its date"
        )
    }

    // MARK: When Today cannot be shown

    /// The title in place of the screen when its data cannot be read (Pete's decision 5, the default wording).
    static var failedTitle: String {
        String(
            localized: "Can't show today right now",
            bundle: .module,
            comment: "Title shown in place of the Today screen when its data cannot be read"
        )
    }

    static var failedBody: String {
        String(
            localized: "Your workouts are still on this iPhone. Open the app again to try once more.",
            bundle: .module,
            comment: "Under the title shown when the Today screen's data cannot be read"
        )
    }

    // MARK: Tiles

    /// The sessions planned this week, drawn light after the number done: "2" then "/4".
    static func sessionsPlanned(_ planned: Int, locale: Locale) -> String {
        String(
            localized: "/\(planned)",
            bundle: .module,
            locale: locale,
            comment: "The sessions planned this week, after the number done: 2/4"
        )
    }

    static var sessionsThisWeek: String {
        String(localized: "sessions this week", bundle: .module, comment: "Caption under the sessions done and planned")
    }

    /// "2 of 4 sessions this week": what VoiceOver reads for the sessions tile.
    static func sessionsSummary(done: String, planned: Int, locale: Locale) -> String {
        String(
            localized: "\(done) of \(planned) sessions this week",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Spoken text of the sessions tile: the sessions done, then the sessions planned"
        )
    }

    static var thousands: String {
        String(localized: "k", bundle: .module, comment: "Thousands, after the week's volume: 24.2k")
    }

    /// The volume tile's caption.
    static func movedCaption(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "lb moved", bundle: .module, comment: "Caption of the week's volume, in pounds")
        case .kg: String(localized: "kg moved", bundle: .module, comment: "Caption of the week's volume, in kilograms")
        }
    }

    /// "24,180 lb moved": a workout's volume on the Logged card.
    static func moved(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb: String(localized: "\(volume) lb moved", bundle: .module, locale: locale)
        case .kg: String(localized: "\(volume) kg moved", bundle: .module, locale: locale)
        }
    }

    /// "24,180 lb moved this week": what VoiceOver reads for the volume tile when there is no previous week to
    /// compare with. The tile draws thousands ("24.2k"); this is the whole number.
    static func movedThisWeek(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(volume) lb moved this week",
                bundle: .module,
                locale: locale,
                comment: "Spoken text of the volume tile: the week's volume, in pounds"
            )
        case .kg:
            String(
                localized: "\(volume) kg moved this week",
                bundle: .module,
                locale: locale,
                comment: "Spoken text of the volume tile: the week's volume, in kilograms"
            )
        }
    }

    /// "24,180 lb moved this week, +8% from last week": the same line with the change the tile draws, and what
    /// the change is against.
    static func movedThisWeek(_ volume: String, change: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(volume) lb moved this week, \(change) from last week",
                bundle: .module,
                locale: locale,
                comment: "Spoken text of the volume tile: the week's volume in pounds, then its change, as in +8%"
            )
        case .kg:
            String(
                localized: "\(volume) kg moved this week, \(change) from last week",
                bundle: .module,
                locale: locale,
                comment: "Spoken text of the volume tile: the week's volume in kilograms, then its change, as in +8%"
            )
        }
    }

    /// "+8%": this week's volume is above the previous week's.
    static func increase(_ percent: Int, locale: Locale) -> String {
        String(localized: "+\(percent)%", bundle: .module, locale: locale, comment: "A rise in the week's volume")
    }

    /// "−3%", with a minus sign: this week's volume is below the previous week's. `percent` is the size of the fall.
    static func decrease(_ percent: Int, locale: Locale) -> String {
        String(localized: "−\(percent)%", bundle: .module, locale: locale, comment: "A fall in the week's volume")
    }

    /// "0%": this week's volume is within half a percent of the previous week's.
    static func unchanged(_ percent: Int, locale: Locale) -> String {
        String(localized: "\(percent)%", bundle: .module, locale: locale, comment: "No change in the week's volume")
    }

    // MARK: Recent

    static var recent: String {
        String(localized: "RECENT", bundle: .module, comment: "Eyebrow of the list of the last finished workouts")
    }

    /// "58 min": how long a finished workout took.
    static func duration(minutes: Int, locale: Locale) -> String {
        String(
            localized: "\(minutes) min",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "A workout's length in minutes"
        )
    }

    /// "24,180 lb": a finished workout's volume.
    static func volume(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb: String(localized: "\(volume) lb", bundle: .module, locale: locale)
        case .kg: String(localized: "\(volume) kg", bundle: .module, locale: locale)
        }
    }

    static var noSessionsYet: String {
        String(localized: "No sessions yet. Your first workout lands here.", bundle: .module)
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
