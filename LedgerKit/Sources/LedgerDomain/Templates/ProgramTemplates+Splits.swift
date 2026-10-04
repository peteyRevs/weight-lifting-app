import Foundation

// MARK: - What a split is made of

extension ProgramTemplates {
    /// How much a lift matters in its day: the main lift, a second compound lift, or an accessory. The goal
    /// gives each role its sets, reps, RPE, rest and progression (`schemes(for:)`).
    enum Role: Sendable {
        case primary, secondary, accessory
    }

    /// One exercise of a template day.
    struct Lift: Sendable {
        /// The catalog's full name, matched exactly: "Weighted Pull-Up", for one ("Pull-Up" is another
        /// exercise, which starts with no load).
        let exercise: String
        let role: Role
        /// Spec §6.1 `sup`: done as a superset with the lift before it.
        let isSupersetWithPrevious: Bool
        /// Spec §6.1 `drop`: 1 adds a drop set after the last working set.
        let dropSets: Int

        init(_ exercise: String, _ role: Role, isSupersetWithPrevious: Bool = false, dropSets: Int = 0) {
            self.exercise = exercise
            self.role = role
            self.isSupersetWithPrevious = isSupersetWithPrevious
            self.dropSets = dropSets
        }
    }

    /// One training day of a split.
    struct Day: Sendable {
        /// "Upper A — Push focus": the part before " — " is the day's short title (`DayTemplate.shortTitle`).
        let name: String
        let tag: String
        /// The day's line in onboarding's preview (spec §6.7).
        let exercises: String
        let lifts: [Lift]

        init(_ name: String, tag: String, preview exercises: String, _ lifts: [Lift]) {
            self.name = name
            self.tag = tag
            self.exercises = exercises
            self.lifts = lifts
        }
    }

    /// The program one number of days a week gets.
    struct Split: Sendable {
        let name: String
        /// The weekday each of `days` is trained on, in the same order.
        let weekdays: [Weekday]
        /// The training weekdays the deload week rests on. A deload changes loads, not days, so only spec
        /// §6.4's own schedule names one.
        var deloadRestDays: Set<Weekday> = []
        let days: [Day]
        /// Spec §6.4's rows by exercise, for the split the prototype drew: what `both` prescribes there in
        /// place of the role table.
        var seed: [String: Scheme] = [:]
    }

    static func split(for days: DaysPerWeek) -> Split {
        switch days {
        case .three: fullBody
        case .four: upperLower
        case .five: pushPullLegs
        case .six: bodyPart
        }
    }
}

// MARK: - The prototype's split (spec §6.4)

extension ProgramTemplates {
    /// 4 days, on Monday, Wednesday, Friday and Saturday; the deload week drops the Saturday. Under `both`
    /// every row is spec §6.4's (`specSeed`); the other goals keep the exercises, the supersets and the drop
    /// set, and take the role table.
    ///
    /// Lower B's preview line is spec §6.7's without its "hamstring, abs": the day has a leg curl and no abs
    /// slot, and the copy follows the day (F08 notes, decision 1).
    static let upperLower = Split(
        name: "Upper / Lower",
        weekdays: [.monday, .wednesday, .friday, .saturday],
        deloadRestDays: [.saturday],
        days: [
            Day("Upper A — Push focus", tag: "UA", preview: "Bench, incline, row, pulldown, laterals", [
                Lift("Barbell Bench Press", .primary),
                Lift("Incline DB Press", .secondary),
                Lift("Chest-Supported Row", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Cable Lateral Raise", .accessory, isSupersetWithPrevious: true)
            ]),
            Day("Lower A — Squat focus", tag: "LA", preview: "Squat, RDL, leg press, calves", [
                Lift("Back Squat", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Standing Calf Raise", .accessory, isSupersetWithPrevious: true)
            ]),
            Day("Upper B — Pull focus", tag: "UB", preview: "Weighted pull-up, OHP, row, curls", [
                Lift("Weighted Pull-Up", .primary),
                Lift("Overhead Press", .secondary),
                Lift("Barbell Row", .secondary),
                Lift("Barbell Curl", .accessory, dropSets: 1)
            ]),
            Day("Lower B — Hinge focus", tag: "LB", preview: "Deadlift, front squat, leg curl", [
                Lift("Deadlift", .primary),
                Lift("Front Squat", .secondary),
                Lift("Seated Leg Curl", .accessory)
            ])
        ],
        seed: specSeed
    )
}

// MARK: - Our splits (the prototype draws none for 3, 5 or 6 days)

extension ProgramTemplates {
    /// 3 days, on Monday, Wednesday and Friday: the whole body each session, around one main lift.
    static let fullBody = Split(
        name: "Full Body",
        weekdays: [.monday, .wednesday, .friday],
        days: [
            Day("Full Body A — Squat focus", tag: "FA", preview: "Squat, bench, pulldown, laterals, curl", [
                Lift("Back Squat", .primary),
                Lift("Barbell Bench Press", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Cable Lateral Raise", .accessory),
                Lift("Barbell Curl", .accessory)
            ]),
            Day("Full Body B — Bench focus", tag: "FB", preview: "Bench, RDL, row, leg press, pushdown", [
                Lift("Barbell Bench Press", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Chest-Supported Row", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Cable Triceps Pushdown", .accessory)
            ]),
            Day("Full Body C — Deadlift focus", tag: "FC", preview: "Deadlift, OHP, pull-up, leg curl, rear delt", [
                Lift("Deadlift", .primary),
                Lift("Overhead Press", .secondary),
                Lift("Weighted Pull-Up", .secondary),
                Lift("Seated Leg Curl", .accessory),
                Lift("Rear Delt Fly", .accessory)
            ])
        ]
    )

    /// 5 days, on Monday, Tuesday and Wednesday, then Friday and Saturday: push, pull and legs, then an upper
    /// and a lower day of second lifts and accessories.
    static let pushPullLegs = Split(
        name: "Push / Pull / Legs",
        weekdays: [.monday, .tuesday, .wednesday, .friday, .saturday],
        days: [
            Day("Push — Chest focus", tag: "PU", preview: "Bench, OHP, incline, laterals, pushdown", [
                Lift("Barbell Bench Press", .primary),
                Lift("Overhead Press", .secondary),
                Lift("Incline DB Press", .accessory),
                Lift("Cable Lateral Raise", .accessory),
                Lift("Cable Triceps Pushdown", .accessory)
            ]),
            Day("Pull — Back focus", tag: "PL", preview: "Pull-up, row, pulldown, rear delt, curl", [
                Lift("Weighted Pull-Up", .primary),
                Lift("Barbell Row", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Rear Delt Fly", .accessory),
                Lift("Incline DB Curl", .accessory)
            ]),
            Day("Legs — Squat focus", tag: "LG", preview: "Squat, RDL, leg press, leg curl, calves", [
                Lift("Back Squat", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Seated Leg Curl", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ]),
            Day("Upper — Accessories", tag: "UP", preview: "Dip, row, fly, extension, curl", [
                Lift("Weighted Dip", .secondary),
                Lift("Chest-Supported Row", .secondary),
                Lift("Low-to-High Cable Fly", .accessory),
                Lift("Overhead Cable Extension", .accessory),
                Lift("Barbell Curl", .accessory)
            ]),
            Day("Lower — Hinge focus", tag: "LW", preview: "Deadlift, front squat, leg curl, calves", [
                Lift("Deadlift", .primary),
                Lift("Front Squat", .secondary),
                Lift("Seated Leg Curl", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ])
        ]
    )

    /// 6 days, Monday to Saturday: one body part a day, the legs twice.
    static let bodyPart = Split(
        name: "Body-Part Split",
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
        days: [
            Day("Chest", tag: "CH", preview: "Bench, incline, dip, fly", [
                Lift("Barbell Bench Press", .primary),
                Lift("Incline DB Press", .secondary),
                Lift("Weighted Dip", .accessory),
                Lift("Low-to-High Cable Fly", .accessory)
            ]),
            Day("Back", tag: "BK", preview: "Row, pull-up, pulldown, chest-supported row", [
                Lift("Barbell Row", .primary),
                Lift("Weighted Pull-Up", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Chest-Supported Row", .accessory)
            ]),
            Day("Legs — Quad focus", tag: "LQ", preview: "Squat, front squat, leg press, calves", [
                Lift("Back Squat", .primary),
                Lift("Front Squat", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ]),
            Day("Shoulders", tag: "SH", preview: "OHP, laterals, rear delt, extension", [
                Lift("Overhead Press", .primary),
                Lift("Cable Lateral Raise", .accessory),
                Lift("Rear Delt Fly", .accessory),
                Lift("Overhead Cable Extension", .accessory)
            ]),
            Day("Arms", tag: "AR", preview: "Curl, pushdown, DB curl, extension", [
                Lift("Barbell Curl", .secondary),
                Lift("Cable Triceps Pushdown", .secondary),
                Lift("Incline DB Curl", .accessory),
                Lift("Overhead Cable Extension", .accessory)
            ]),
            Day("Legs — Hinge focus", tag: "LH", preview: "Deadlift, RDL, leg curl, calves", [
                Lift("Deadlift", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Seated Leg Curl", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ])
        ]
    )
}
