import Foundation
@testable import LedgerDomain

// The brief's "Templates" list: every split's days, with the 4-day role line's shorthand written as the
// catalog's full names (the brief's amendment 4) and Lower B's preview line without "abs" (F08 notes,
// decision 1).

extension TemplateOracle {
    /// One day as the brief lists it: "name · tag: lifts with role → preview line".
    struct Day: Sendable {
        let name: String
        let tag: String
        /// Each lift's catalog name followed by its role's letter: "Back Squat P, Barbell Bench Press S".
        let lifts: String
        let preview: String

        init(_ name: String, _ tag: String, lifts: String, preview: String) {
            self.name = name
            self.tag = tag
            self.lifts = lifts
            self.preview = preview
        }

        /// The lifts' catalog names, in order.
        var exercises: [String] {
            lifts.split(separator: ", ").map { String($0.dropLast(2)) }
        }

        /// The lifts' role letters, in order.
        var roles: [Character] {
            lifts.split(separator: ", ").compactMap(\.last)
        }
    }

    struct Split: Sendable {
        let name: String
        let weekdays: [Weekday]
        let days: [Day]
    }

    static func split(for days: DaysPerWeek) -> Split {
        switch days {
        case .three: fullBody
        case .four: upperLower
        case .five: pushPullLegs
        case .six: bodyPart
        }
    }

    static let upperLower = Split(
        name: "Upper / Lower",
        weekdays: [.monday, .wednesday, .friday, .saturday],
        days: [
            Day(
                "Upper A — Push focus", "UA",
                lifts: "Barbell Bench Press P, Incline DB Press S, Chest-Supported Row S, Lat Pulldown A, "
                    + "Cable Lateral Raise A",
                preview: "Bench, incline, row, pulldown, laterals"
            ),
            Day(
                "Lower A — Squat focus", "LA",
                lifts: "Back Squat P, Romanian Deadlift S, Leg Press A, Standing Calf Raise A",
                preview: "Squat, RDL, leg press, calves"
            ),
            Day(
                "Upper B — Pull focus", "UB",
                lifts: "Weighted Pull-Up P, Overhead Press S, Barbell Row S, Barbell Curl A",
                preview: "Weighted pull-up, OHP, row, curls"
            ),
            Day(
                "Lower B — Hinge focus", "LB",
                lifts: "Deadlift P, Front Squat S, Seated Leg Curl A",
                preview: "Deadlift, front squat, leg curl"
            )
        ]
    )

    static let fullBody = Split(
        name: "Full Body",
        weekdays: [.monday, .wednesday, .friday],
        days: [
            Day(
                "Full Body A — Squat focus", "FA",
                lifts: "Back Squat P, Barbell Bench Press S, Lat Pulldown A, Cable Lateral Raise A, Barbell Curl A",
                preview: "Squat, bench, pulldown, laterals, curl"
            ),
            Day(
                "Full Body B — Bench focus", "FB",
                lifts: "Barbell Bench Press P, Romanian Deadlift S, Chest-Supported Row S, Leg Press A, "
                    + "Cable Triceps Pushdown A",
                preview: "Bench, RDL, row, leg press, pushdown"
            ),
            Day(
                "Full Body C — Deadlift focus", "FC",
                lifts: "Deadlift P, Overhead Press S, Weighted Pull-Up S, Seated Leg Curl A, Rear Delt Fly A",
                preview: "Deadlift, OHP, pull-up, leg curl, rear delt"
            )
        ]
    )

    static let pushPullLegs = Split(
        name: "Push / Pull / Legs",
        weekdays: [.monday, .tuesday, .wednesday, .friday, .saturday],
        days: [
            Day(
                "Push — Chest focus", "PU",
                lifts: "Barbell Bench Press P, Overhead Press S, Incline DB Press A, Cable Lateral Raise A, "
                    + "Cable Triceps Pushdown A",
                preview: "Bench, OHP, incline, laterals, pushdown"
            ),
            Day(
                "Pull — Back focus", "PL",
                lifts: "Weighted Pull-Up P, Barbell Row S, Lat Pulldown A, Rear Delt Fly A, Incline DB Curl A",
                preview: "Pull-up, row, pulldown, rear delt, curl"
            ),
            Day(
                "Legs — Squat focus", "LG",
                lifts: "Back Squat P, Romanian Deadlift S, Leg Press A, Seated Leg Curl A, Standing Calf Raise A",
                preview: "Squat, RDL, leg press, leg curl, calves"
            ),
            Day(
                "Upper — Accessories", "UP",
                lifts: "Weighted Dip S, Chest-Supported Row S, Low-to-High Cable Fly A, Overhead Cable Extension A, "
                    + "Barbell Curl A",
                preview: "Dip, row, fly, extension, curl"
            ),
            Day(
                "Lower — Hinge focus", "LW",
                lifts: "Deadlift P, Front Squat S, Seated Leg Curl A, Standing Calf Raise A",
                preview: "Deadlift, front squat, leg curl, calves"
            )
        ]
    )

    static let bodyPart = Split(
        name: "Body-Part Split",
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
        days: [
            Day(
                "Chest", "CH",
                lifts: "Barbell Bench Press P, Incline DB Press S, Weighted Dip A, Low-to-High Cable Fly A",
                preview: "Bench, incline, dip, fly"
            ),
            Day(
                "Back", "BK",
                lifts: "Barbell Row P, Weighted Pull-Up S, Lat Pulldown A, Chest-Supported Row A",
                preview: "Row, pull-up, pulldown, chest-supported row"
            ),
            Day(
                "Legs — Quad focus", "LQ",
                lifts: "Back Squat P, Front Squat S, Leg Press A, Standing Calf Raise A",
                preview: "Squat, front squat, leg press, calves"
            ),
            Day(
                "Shoulders", "SH",
                lifts: "Overhead Press P, Cable Lateral Raise A, Rear Delt Fly A, Overhead Cable Extension A",
                preview: "OHP, laterals, rear delt, extension"
            ),
            Day(
                "Arms", "AR",
                lifts: "Barbell Curl S, Cable Triceps Pushdown S, Incline DB Curl A, Overhead Cable Extension A",
                preview: "Curl, pushdown, DB curl, extension"
            ),
            Day(
                "Legs — Hinge focus", "LH",
                lifts: "Deadlift P, Romanian Deadlift S, Seated Leg Curl A, Standing Calf Raise A",
                preview: "Deadlift, RDL, leg curl, calves"
            )
        ]
    )
}
