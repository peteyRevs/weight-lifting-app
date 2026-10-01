import SwiftUI

/// The week at a glance (v2 Today): seven columns, each a weekday letter, the date and a dot. The
/// dot marks the day: filled grey once trained, an orange dot today, a ring for a planned session,
/// none for a rest day. The date is ink once trained and orange today.
///
/// VoiceOver reads one element per day: its `accessibilitySummary` ("Wednesday, August 19"), since
/// "W" and "19" alone are ambiguous, with the mark in words as its value ("Done", "Today",
/// "Planned", "Rest day"). At the largest text sizes the letters and dates shrink rather than wrap.
public struct WeekStrip: View {
    /// What a day's dot says.
    public nonisolated enum Mark: Sendable {
        /// Nothing scheduled: no dot.
        case rest
        /// A session is scheduled: a grey ring (the prototype's .18 dot is below WCAG's 3:1).
        case planned
        /// Today, not trained yet: the date and dot in orange.
        case today
        /// Trained: the date in ink and a filled grey dot.
        case done
    }

    /// One column. Strings are shown and spoken as given; features pass copy from their catalog.
    public nonisolated struct Day: Equatable, Sendable {
        public let weekday: String
        public let date: String
        public let mark: Mark
        public let accessibilitySummary: String

        public init(weekday: String, date: String, mark: Mark, accessibilitySummary: String) {
            self.weekday = weekday
            self.date = date
            self.mark = mark
            self.accessibilitySummary = accessibilitySummary
        }
    }

    private let days: [Day]

    public init(days: [Day]) {
        self.days = days
    }

    public var body: some View {
        HStack(alignment: .top, spacing: LedgerSpacing.s) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                WeekStripDay(day: day)
            }
        }
    }
}

/// One day's column.
private struct WeekStripDay: View {
    /// The prototype's 5 px dot beside its 12 px weekday letter, in ems, so it grows with the text.
    static let dotEms: CGFloat = 5.0 / 12

    let day: WeekStrip.Day
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let dotSide = LedgerFont.scaledSize(.caption, dynamicTypeSize: dynamicTypeSize) * Self.dotEms
        VStack(spacing: LedgerSpacing.s) {
            Text(day.weekday)
                .ledgerFont(.caption)
                .foregroundStyle(LedgerColor.inkMuted) // the prototype's .34 is below AA
                .lineLimit(1)
                .minimumScaleFactor(0.5) // seven columns share the width at every text size
            Text(day.date)
                .ledgerFont(.body)
                .foregroundStyle(dateColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            dot.frame(width: dotSide, height: dotSide)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: day.accessibilitySummary))
        .accessibilityValue(WeekStripSpeech.mark(day.mark))
    }

    private var dateColor: Color {
        switch day.mark {
        case .today: LedgerColor.accentText
        case .done: LedgerColor.ink
        case .planned, .rest: LedgerColor.inkMuted
        }
    }

    /// Each mark meets WCAG 1.4.11's 3:1 on paper and on the dark ground, and done and planned differ
    /// in shape as well as in the date's colour.
    @ViewBuilder private var dot: some View {
        switch day.mark {
        case .today: Circle().fill(LedgerColor.accentText)
        case .done: Circle().fill(LedgerColor.inkMuted)
        case .planned: Circle().strokeBorder(LedgerColor.inkMuted, lineWidth: LedgerHairline.width)
        case .rest: Color.clear
        }
    }
}

/// What VoiceOver says for a day's mark. English until LedgerDesign has a string catalog; the keys
/// are the English text ("Done" is `SetRow`'s key too).
private nonisolated enum WeekStripSpeech {
    static func mark(_ mark: WeekStrip.Mark) -> String {
        switch mark {
        case .rest:
            String(localized: "Rest day", bundle: .module, comment: "VoiceOver value of a day with no session")
        case .planned:
            String(localized: "Planned", bundle: .module, comment: "VoiceOver value of a day with a session planned")
        case .today:
            String(localized: "Today", bundle: .module, comment: "VoiceOver value of today in the week strip")
        case .done:
            String(localized: "Done", bundle: .module, comment: "VoiceOver value of a logged set and of its check")
        }
    }
}

/// The prototype's week (Monday 17 to Sunday 23 August, Wednesday today), for the preview, the
/// snapshot tests and the gallery.
struct WeekStripGallery: View {
    static let days: [WeekStrip.Day] = [
        ("M", "17", WeekStrip.Mark.done, "Monday"), ("T", "18", .done, "Tuesday"), ("W", "19", .today, "Wednesday"),
        ("T", "20", .rest, "Thursday"), ("F", "21", .planned, "Friday"), ("S", "22", .rest, "Saturday"),
        ("S", "23", .rest, "Sunday")
    ].map { weekday, date, mark, name in
        WeekStrip.Day(weekday: weekday, date: date, mark: mark, accessibilitySummary: "\(name), August \(date)")
    }

    var body: some View {
        WeekStrip(days: Self.days)
    }
}
