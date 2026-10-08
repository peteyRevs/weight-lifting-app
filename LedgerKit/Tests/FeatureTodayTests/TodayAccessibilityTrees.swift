#if os(iOS)
    @testable import FeatureToday
    import UIKit

    /// One VoiceOver stop, as the tables write it: label, value and traits, compared exactly.
    nonisolated struct Stop: Equatable, Sendable, CustomStringConvertible {
        let label: String
        let value: String
        let traits: UInt64

        init(_ label: String, value: String = "", _ traits: UIAccessibilityTraits) {
            self.label = label
            self.value = value
            self.traits = traits.rawValue
        }

        static func button(_ label: String) -> Stop {
            Stop(label, .button)
        }

        static func text(_ label: String) -> Stop {
            Stop(label, .staticText)
        }

        /// The screen's title, a card's eyebrow or title, "RECENT", the sheet's title.
        static func heading(_ label: String) -> Stop {
            Stop(label, [.header, .staticText])
        }

        /// One day of the week strip: its spoken date, and the component's word for its mark as its value.
        static func day(_ label: String, _ mark: String) -> Stop {
            Stop(label, value: mark, .staticText)
        }

        var isButton: Bool {
            traits & UIAccessibilityTraits.button.rawValue != 0
        }

        var description: String {
            "\"\(label)\" value \"\(value)\" traits \(traits)"
        }
    }

    /// The first place two trees differ, as one short line, or nil when they are the same. A test expects this
    /// to be nil and so never hands a whole tree to `#expect`.
    nonisolated func firstDifference(found: [Stop], expected: [Stop]) -> String? {
        for (index, pair) in zip(found, expected).enumerated() where pair.0 != pair.1 {
            return "stop \(index + 1): found \(pair.0), expected \(pair.1)"
        }
        guard found.count != expected.count else {
            return nil
        }
        let extra = found.count > expected.count ? found[expected.count] : expected[found.count]
        return "found \(found.count) stops, expected \(expected.count); the first one more is \(extra)"
    }

    /// The intended VoiceOver tree of every state of Today, as the implementation notes write them ("The
    /// intended VoiceOver trees"). `TodayAccessibilityTests` reads each from the page and compares it exactly.
    /// Decorative parts (the rules, the strip's dots, the button's arrow, a row's chevron, the gear's symbol) are
    /// no stop and appear in no table.
    nonisolated enum TodayTrees {
        /// The week of Monday 2026-09-14, by the marks of its seven days.
        static func week(_ marks: [String], today: String? = nil) -> [Stop] {
            let days = [
                "Monday, September 14", "Tuesday, September 15", "Wednesday, September 16",
                "Thursday, September 17", "Friday, September 18", "Saturday, September 19", "Sunday, September 20"
            ]
            return zip(days, marks).map { day, mark in .day(day == today ? "Today, \(day)" : day, mark) }
        }

        static let mondayRow = Stop.button("Upper A — Push focus, Mon · 58 min · 12,243 lb")
        static let wednesdayRow = Stop.button("Lower A — Squat focus, Wed · 52 min · 30,370 lb")
        static let recent = Stop.heading("RECENT")

        static let lowerARows = [
            Stop.text("Back Squat, 5 × 5 @ 250"),
            .text("Romanian Deadlift, 3 × 8 @ 205"),
            .text("Leg Press, 3 × 12 @ 320"),
            .text("Standing Calf Raise, 4 × 12 @ 160")
        ]

        /// Wednesday of week 1 with Monday trained: the header, the strip, and what follows the card.
        static func wednesday(card: [Stop]) -> [Stop] {
            [.text("Wednesday, September 16"), .heading("Lower A"), .button("Settings")]
                + week(["Done", "Rest day", "Today", "Rest day", "Planned", "Planned", "Rest day"])
                + card
                + [
                    .text("1 of 4 sessions this week"),
                    .text("12,243 lb moved this week, +8% from last week"),
                    recent,
                    mondayRow
                ]
        }

        /// Thursday of week 1, a rest day, with Monday and Wednesday trained.
        static func thursday(card: [Stop]) -> [Stop] {
            [.text("Thursday, September 17"), .heading("Rest day"), .button("Settings")]
                + week(["Done", "Rest day", "Done", "Today", "Planned", "Planned", "Rest day"])
                + card
                + [
                    .text("2 of 4 sessions this week"),
                    .text("42,613 lb moved this week, +2% from last week"),
                    recent,
                    wednesdayRow,
                    mondayRow
                ]
        }

        static let upNext = wednesday(card: [
            .heading("UP NEXT"), .text("Week 1 of 8 · ~38 min"), .text("Lower A — Squat focus")
        ] + lowerARows + [.button("Start workout")])

        static let resume = wednesday(card: [
            .heading("UP NEXT"), .text("Week 1 of 8 · ~38 min"), .text("Lower A — Squat focus")
        ] + lowerARows + [.button("Resume · 3:00")])

        static let logged: [Stop] = [
            .text("Wednesday, September 16"), .heading("Lower A"), .button("Settings")
        ] + week(
            ["Done", "Rest day", "Done", "Rest day", "Planned", "Planned", "Rest day"],
            today: "Wednesday, September 16"
        ) + [
            .heading("LOGGED · WEEK 1"),
            .text("24:22"),
            .text("Lower A — Squat focus"),
            .text("15 of 15 sets · 30,370 lb moved"),
            .button("View session"),
            .text("Next: Friday · UB"),
            .text("2 of 4 sessions this week"),
            .text("42,613 lb moved this week, +8% from last week"),
            recent,
            .button("Lower A — Squat focus, Today · 24:22 · 30,370 lb"),
            mondayRow
        ]

        static let restDay = thursday(card: [
            .heading("SCHEDULED REST"),
            .text("No session today"),
            .text("Nothing scheduled for Thursday in week 1. Next up is Friday."),
            .button("Edit this week"),
            .button("Train off-schedule")
        ])

        static let noProgram: [Stop] = [
            .text("Wednesday, September 16"), .heading("Today"), .button("Settings")
        ] + week(["Rest day", "Rest day", "Today", "Rest day", "Rest day", "Rest day", "Rest day"]) + [
            .heading("No program yet"),
            .text("Set up a program to see your next session here."),
            .button("Set up program"),
            .text("0 of 0 sessions this week"),
            .text("0 lb moved this week"),
            recent,
            .text("No sessions yet. Your first workout lands here.")
        ]

        static let blockComplete: [Stop] = [
            .text("Wednesday, November 11"), .heading("Today"), .button("Settings"),
            .day("Monday, November 9", "Done"), .day("Tuesday, November 10", "Rest day"),
            .day("Wednesday, November 11", "Today"), .day("Thursday, November 12", "Rest day"),
            .day("Friday, November 13", "Rest day"), .day("Saturday, November 14", "Rest day"),
            .day("Sunday, November 15", "Rest day"),
            .heading("Block complete"),
            .text("8 weeks done. Start the next block from Program."),
            .button("Open Program"),
            .text("1 of 0 sessions this week"),
            .text("20,155 lb moved this week"),
            recent,
            .button("Lower A — Squat focus, Mon · 47 min · 20,155 lb")
        ]

        static let failed: [Stop] = [
            .heading("Can't show today right now"),
            .text("Your workouts are still on this iPhone. Open the app again to try once more.")
        ]

        /// The sheet of the rest-day state: its title and "Cancel", then its page.
        static let offSchedule: [Stop] = [
            .heading("Train off-schedule"),
            .button("Cancel"),
            .text("Pick a day from week 1."),
            .button("Upper A — Push focus, 5 exercises · ~39 min, Logged"),
            .button("Lower A — Squat focus, 4 exercises · ~38 min, Logged"),
            .button("Upper B — Pull focus, 4 exercises · ~37 min"),
            .button("Lower B — Hinge focus, 3 exercises · ~31 min")
        ]
    }

    nonisolated extension TodayTrees {
        // The two states that carry an open product question.

        static let resumeOnRestDay = thursday(card: [
            .heading("UP NEXT"),
            .text("Week 1 of 8 · ~31 min"),
            .text("Lower B — Hinge focus"),
            .text("Deadlift, 4 × 4 @ 315"),
            .text("Front Squat, 3 × 8 @ 185"),
            .text("Seated Leg Curl, 3 × 12 @ 90"),
            .button("Resume · 12:40")
        ])

        static let mondayVolume: [Stop] = [
            .text("Monday, September 21"), .heading("Upper A"), .button("Settings"),
            .day("Monday, September 21", "Today"), .day("Tuesday, September 22", "Rest day"),
            .day("Wednesday, September 23", "Planned"), .day("Thursday, September 24", "Rest day"),
            .day("Friday, September 25", "Planned"), .day("Saturday, September 26", "Planned"),
            .day("Sunday, September 27", "Rest day"),
            .heading("UP NEXT"),
            .text("Week 2 of 8 · ~39 min"),
            .text("Upper A — Push focus"),
            .text("Barbell Bench Press, 5 × 5 @ 185"),
            .text("Incline DB Press, 3 × 11 @ 50"),
            .text("Chest-Supported Row, 4 × 8 @ 67.5"),
            .text("Lat Pulldown, 3 × 13 @ 100"),
            .text("Cable Lateral Raise, 3 × 16 @ 12.5"),
            .button("Start workout"),
            .text("0 of 4 sessions this week"),
            .text("0 lb moved this week, −100% from last week"),
            recent,
            .button("Upper B — Pull focus, Fri · 61 min · 11,730 lb"),
            wednesdayRow,
            mondayRow
        ]

        /// The page's tree in each state of the preview registry; the sheet's case is the sheet's own tree.
        static let byState: [TodayPreview: [Stop]] = [
            .upNext: upNext, .resume: resume, .logged: logged, .restDay: restDay, .offSchedule: offSchedule,
            .noProgram: noProgram, .blockComplete: blockComplete, .loading: [], .failed: failed,
            .resumeOnRestDay: resumeOnRestDay, .mondayVolume: mondayVolume
        ]
    }
#endif
