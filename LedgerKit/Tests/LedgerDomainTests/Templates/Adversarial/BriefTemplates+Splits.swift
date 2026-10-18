import Foundation
@testable import LedgerDomain

// The brief's "Templates" list, transcribed with the catalog's full names (amendment 4: "Pull-Up" is Weighted
// Pull-Up), and spec §6.4's table for the 4-day split's own rows. Day names, tags and preview lines are the
// brief's; the 4-day lines are spec §6.7's, with Lower B as the brief's "Copy" paragraph corrects it.

extension BriefTemplates {
    private static func primary(_ exercise: String, seed: Scheme? = nil) -> Lift {
        Lift(exercise: exercise, role: .primary, seed: seed)
    }

    private static func secondary(_ exercise: String, seed: Scheme? = nil) -> Lift {
        Lift(exercise: exercise, role: .secondary, seed: seed)
    }

    private static func accessory(
        _ exercise: String,
        seed: Scheme? = nil,
        superset: Bool = false,
        drop: Int = 0
    ) -> Lift {
        Lift(exercise: exercise, role: .accessory, seed: seed, superset: superset, drop: drop)
    }

    /// A spec §6.4 row: sets, reps to repsHi, RPE, rest, progression.
    private static func row(
        _ sets: Int,
        _ reps: ClosedRange<Int>,
        _ rpe: Decimal,
        _ rest: Int,
        _ progression: Progression
    ) -> Scheme {
        Scheme(
            sets: sets, reps: reps.lowerBound, repsHi: reps.upperBound, rpe: rpe, rest: rest, progression: progression
        )
    }

    /// 4 days: spec §6.4, with the brief's roles for the other three goals.
    static let upperLower = Split(
        programName: "Upper / Lower",
        weekdays: [.monday, .wednesday, .friday, .saturday],
        deloadRest: [.saturday],
        days: [
            Day(name: "Upper A — Push focus", tag: "UA", line: "Bench, incline, row, pulldown, laterals", lifts: [
                primary("Barbell Bench Press", seed: row(5, 5 ... 7, 8, 150, .linear)),
                secondary("Incline DB Press", seed: row(3, 10 ... 12, 8, 90, .double)),
                secondary("Chest-Supported Row", seed: row(4, 8 ... 10, 8, 90, .linear)),
                accessory("Lat Pulldown", seed: row(3, 12 ... 14, 9, 75, .double)),
                accessory("Cable Lateral Raise", seed: row(3, 15 ... 17, 9, 60, .double), superset: true)
            ]),
            Day(name: "Lower A — Squat focus", tag: "LA", line: "Squat, RDL, leg press, calves", lifts: [
                primary("Back Squat", seed: row(5, 5 ... 7, 8, 180, .linear)),
                secondary("Romanian Deadlift", seed: row(3, 8 ... 10, 8, 120, .linear)),
                accessory("Leg Press", seed: row(3, 12 ... 14, 9, 90, .double)),
                accessory("Standing Calf Raise", seed: row(4, 12 ... 14, 9, 60, .fixed), superset: true)
            ]),
            Day(name: "Upper B — Pull focus", tag: "UB", line: "Weighted pull-up, OHP, row, curls", lifts: [
                primary("Weighted Pull-Up", seed: row(4, 6 ... 8, 8, 150, .linear)),
                secondary("Overhead Press", seed: row(4, 6 ... 8, 8, 120, .linear)),
                secondary("Barbell Row", seed: row(3, 10 ... 12, 8, 90, .linear)),
                accessory("Barbell Curl", seed: row(3, 12 ... 14, 9, 60, .double), drop: 1)
            ]),
            Day(name: "Lower B — Hinge focus", tag: "LB", line: "Deadlift, front squat, leg curl", lifts: [
                primary("Deadlift", seed: row(4, 4 ... 6, 8, 210, .linear)),
                secondary("Front Squat", seed: row(3, 8 ... 10, 8, 120, .linear)),
                accessory("Seated Leg Curl", seed: row(3, 12 ... 14, 9, 75, .double))
            ])
        ]
    )

    /// 3 days, Monday, Wednesday, Friday.
    static let fullBody = Split(
        programName: "Full Body",
        weekdays: [.monday, .wednesday, .friday],
        days: [
            Day(name: "Full Body A — Squat focus", tag: "FA", line: "Squat, bench, pulldown, laterals, curl", lifts: [
                primary("Back Squat"), secondary("Barbell Bench Press"), accessory("Lat Pulldown"),
                accessory("Cable Lateral Raise"), accessory("Barbell Curl")
            ]),
            Day(name: "Full Body B — Bench focus", tag: "FB", line: "Bench, RDL, row, leg press, pushdown", lifts: [
                primary("Barbell Bench Press"), secondary("Romanian Deadlift"), secondary("Chest-Supported Row"),
                accessory("Leg Press"), accessory("Cable Triceps Pushdown")
            ]),
            Day(
                name: "Full Body C — Deadlift focus",
                tag: "FC",
                line: "Deadlift, OHP, pull-up, leg curl, rear delt",
                lifts: [
                    primary("Deadlift"), secondary("Overhead Press"), secondary("Weighted Pull-Up"),
                    accessory("Seated Leg Curl"), accessory("Rear Delt Fly")
                ]
            )
        ]
    )

    /// 5 days, Monday, Tuesday, Wednesday, then Friday, Saturday.
    static let pushPullLegs = Split(
        programName: "Push / Pull / Legs",
        weekdays: [.monday, .tuesday, .wednesday, .friday, .saturday],
        days: [
            Day(name: "Push — Chest focus", tag: "PU", line: "Bench, OHP, incline, laterals, pushdown", lifts: [
                primary("Barbell Bench Press"), secondary("Overhead Press"), accessory("Incline DB Press"),
                accessory("Cable Lateral Raise"), accessory("Cable Triceps Pushdown")
            ]),
            Day(name: "Pull — Back focus", tag: "PL", line: "Pull-up, row, pulldown, rear delt, curl", lifts: [
                primary("Weighted Pull-Up"), secondary("Barbell Row"), accessory("Lat Pulldown"),
                accessory("Rear Delt Fly"), accessory("Incline DB Curl")
            ]),
            Day(name: "Legs — Squat focus", tag: "LG", line: "Squat, RDL, leg press, leg curl, calves", lifts: [
                primary("Back Squat"), secondary("Romanian Deadlift"), accessory("Leg Press"),
                accessory("Seated Leg Curl"), accessory("Standing Calf Raise")
            ]),
            Day(name: "Upper — Accessories", tag: "UP", line: "Dip, row, fly, extension, curl", lifts: [
                secondary("Weighted Dip"), secondary("Chest-Supported Row"), accessory("Low-to-High Cable Fly"),
                accessory("Overhead Cable Extension"), accessory("Barbell Curl")
            ]),
            Day(name: "Lower — Hinge focus", tag: "LW", line: "Deadlift, front squat, leg curl, calves", lifts: [
                primary("Deadlift"), secondary("Front Squat"), accessory("Seated Leg Curl"),
                accessory("Standing Calf Raise")
            ])
        ]
    )

    /// 6 days, Monday to Saturday.
    static let bodyPart = Split(
        programName: "Body-Part Split",
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
        days: [
            Day(name: "Chest", tag: "CH", line: "Bench, incline, dip, fly", lifts: [
                primary("Barbell Bench Press"), secondary("Incline DB Press"), accessory("Weighted Dip"),
                accessory("Low-to-High Cable Fly")
            ]),
            Day(name: "Back", tag: "BK", line: "Row, pull-up, pulldown, chest-supported row", lifts: [
                primary("Barbell Row"), secondary("Weighted Pull-Up"), accessory("Lat Pulldown"),
                accessory("Chest-Supported Row")
            ]),
            Day(name: "Legs — Quad focus", tag: "LQ", line: "Squat, front squat, leg press, calves", lifts: [
                primary("Back Squat"), secondary("Front Squat"), accessory("Leg Press"),
                accessory("Standing Calf Raise")
            ]),
            Day(name: "Shoulders", tag: "SH", line: "OHP, laterals, rear delt, extension", lifts: [
                primary("Overhead Press"), accessory("Cable Lateral Raise"), accessory("Rear Delt Fly"),
                accessory("Overhead Cable Extension")
            ]),
            Day(name: "Arms", tag: "AR", line: "Curl, pushdown, DB curl, extension", lifts: [
                secondary("Barbell Curl"), secondary("Cable Triceps Pushdown"), accessory("Incline DB Curl"),
                accessory("Overhead Cable Extension")
            ]),
            Day(name: "Legs — Hinge focus", tag: "LH", line: "Deadlift, RDL, leg curl, calves", lifts: [
                primary("Deadlift"), secondary("Romanian Deadlift"), accessory("Seated Leg Curl"),
                accessory("Standing Calf Raise")
            ])
        ]
    )
}
