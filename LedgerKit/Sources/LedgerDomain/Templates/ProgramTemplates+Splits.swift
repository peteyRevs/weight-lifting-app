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
        /// The weekday the day is trained on, every week it is trained.
        let weekday: Weekday
        let lifts: [Lift]
        /// The day's line in onboarding's preview (spec §6.7): its lifts, as a lifter would say them.
        let preview: String

        init(_ name: String, tag: String, on weekday: Weekday, lifts: [Lift], preview: String) {
            self.name = name
            self.tag = tag
            self.weekday = weekday
            self.lifts = lifts
            self.preview = preview
        }
    }

    /// The program one number of days a week gets.
    struct Split: Sendable {
        let name: String
        /// The training weekdays the deload week rests on. A deload changes loads, not days, so only spec
        /// §6.4's own schedule names one.
        let deloadRestDays: Set<Weekday>
        /// The training days, in the program's order, each on a weekday of its own.
        let days: [Day]
        /// Spec §6.4's rows by exercise, for the split the prototype drew: what `both` prescribes there in
        /// place of the role table.
        let seed: [String: Scheme]

        init(name: String, deloadRestDays: Set<Weekday> = [], days: [Day], seed: [String: Scheme] = [:]) {
            self.name = name
            self.deloadRestDays = deloadRestDays
            self.days = days
            self.seed = seed
        }
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
        deloadRestDays: [.saturday],
        days: [
            Day("Upper A — Push focus", tag: "UA", on: .monday, lifts: [
                Lift("Barbell Bench Press", .primary),
                Lift("Incline DB Press", .secondary),
                Lift("Chest-Supported Row", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Cable Lateral Raise", .accessory, isSupersetWithPrevious: true)
            ], preview: "Bench, incline, row, pulldown, laterals"),
            Day("Lower A — Squat focus", tag: "LA", on: .wednesday, lifts: [
                Lift("Back Squat", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Standing Calf Raise", .accessory, isSupersetWithPrevious: true)
            ], preview: "Squat, RDL, leg press, calves"),
            Day("Upper B — Pull focus", tag: "UB", on: .friday, lifts: [
                Lift("Weighted Pull-Up", .primary),
                Lift("Overhead Press", .secondary),
                Lift("Barbell Row", .secondary),
                Lift("Barbell Curl", .accessory, dropSets: 1)
            ], preview: "Weighted pull-up, OHP, row, curls"),
            Day("Lower B — Hinge focus", tag: "LB", on: .saturday, lifts: [
                Lift("Deadlift", .primary),
                Lift("Front Squat", .secondary),
                Lift("Seated Leg Curl", .accessory)
            ], preview: "Deadlift, front squat, leg curl")
        ],
        seed: specSeed
    )
}

// MARK: - Our splits (the prototype draws none for 3, 5 or 6 days)

extension ProgramTemplates {
    /// 3 days, on Monday, Wednesday and Friday: the whole body each session, around one main lift.
    static let fullBody = Split(
        name: "Full Body",
        days: [
            Day("Full Body A — Squat focus", tag: "FA", on: .monday, lifts: [
                Lift("Back Squat", .primary),
                Lift("Barbell Bench Press", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Cable Lateral Raise", .accessory),
                Lift("Barbell Curl", .accessory)
            ], preview: "Squat, bench, pulldown, laterals, curl"),
            Day("Full Body B — Bench focus", tag: "FB", on: .wednesday, lifts: [
                Lift("Barbell Bench Press", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Chest-Supported Row", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Cable Triceps Pushdown", .accessory)
            ], preview: "Bench, RDL, row, leg press, pushdown"),
            Day("Full Body C — Deadlift focus", tag: "FC", on: .friday, lifts: [
                Lift("Deadlift", .primary),
                Lift("Overhead Press", .secondary),
                Lift("Weighted Pull-Up", .secondary),
                Lift("Seated Leg Curl", .accessory),
                Lift("Rear Delt Fly", .accessory)
            ], preview: "Deadlift, OHP, pull-up, leg curl, rear delt")
        ]
    )

    /// 5 days, on Monday, Tuesday and Wednesday, then Friday and Saturday: push, pull and legs, then an upper
    /// and a lower day of second lifts and accessories.
    static let pushPullLegs = Split(
        name: "Push / Pull / Legs",
        days: [
            Day("Push — Chest focus", tag: "PU", on: .monday, lifts: [
                Lift("Barbell Bench Press", .primary),
                Lift("Overhead Press", .secondary),
                Lift("Incline DB Press", .accessory),
                Lift("Cable Lateral Raise", .accessory),
                Lift("Cable Triceps Pushdown", .accessory)
            ], preview: "Bench, OHP, incline, laterals, pushdown"),
            Day("Pull — Back focus", tag: "PL", on: .tuesday, lifts: [
                Lift("Weighted Pull-Up", .primary),
                Lift("Barbell Row", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Rear Delt Fly", .accessory),
                Lift("Incline DB Curl", .accessory)
            ], preview: "Pull-up, row, pulldown, rear delt, curl"),
            Day("Legs — Squat focus", tag: "LG", on: .wednesday, lifts: [
                Lift("Back Squat", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Seated Leg Curl", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ], preview: "Squat, RDL, leg press, leg curl, calves"),
            Day("Upper — Accessories", tag: "UP", on: .friday, lifts: [
                Lift("Weighted Dip", .secondary),
                Lift("Chest-Supported Row", .secondary),
                Lift("Low-to-High Cable Fly", .accessory),
                Lift("Overhead Cable Extension", .accessory),
                Lift("Barbell Curl", .accessory)
            ], preview: "Dip, row, fly, extension, curl"),
            Day("Lower — Hinge focus", tag: "LW", on: .saturday, lifts: [
                Lift("Deadlift", .primary),
                Lift("Front Squat", .secondary),
                Lift("Seated Leg Curl", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ], preview: "Deadlift, front squat, leg curl, calves")
        ]
    )

    /// 6 days, Monday to Saturday: one body part a day, the legs twice.
    static let bodyPart = Split(
        name: "Body-Part Split",
        days: [
            Day("Chest", tag: "CH", on: .monday, lifts: [
                Lift("Barbell Bench Press", .primary),
                Lift("Incline DB Press", .secondary),
                Lift("Weighted Dip", .accessory),
                Lift("Low-to-High Cable Fly", .accessory)
            ], preview: "Bench, incline, dip, fly"),
            Day("Back", tag: "BK", on: .tuesday, lifts: [
                Lift("Barbell Row", .primary),
                Lift("Weighted Pull-Up", .secondary),
                Lift("Lat Pulldown", .accessory),
                Lift("Chest-Supported Row", .accessory)
            ], preview: "Row, pull-up, pulldown, chest-supported row"),
            Day("Legs — Quad focus", tag: "LQ", on: .wednesday, lifts: [
                Lift("Back Squat", .primary),
                Lift("Front Squat", .secondary),
                Lift("Leg Press", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ], preview: "Squat, front squat, leg press, calves"),
            Day("Shoulders", tag: "SH", on: .thursday, lifts: [
                Lift("Overhead Press", .primary),
                Lift("Cable Lateral Raise", .accessory),
                Lift("Rear Delt Fly", .accessory),
                Lift("Overhead Cable Extension", .accessory)
            ], preview: "OHP, laterals, rear delt, extension"),
            Day("Arms", tag: "AR", on: .friday, lifts: [
                Lift("Barbell Curl", .secondary),
                Lift("Cable Triceps Pushdown", .secondary),
                Lift("Incline DB Curl", .accessory),
                Lift("Overhead Cable Extension", .accessory)
            ], preview: "Curl, pushdown, DB curl, extension"),
            Day("Legs — Hinge focus", tag: "LH", on: .saturday, lifts: [
                Lift("Deadlift", .primary),
                Lift("Romanian Deadlift", .secondary),
                Lift("Seated Leg Curl", .accessory),
                Lift("Standing Calf Raise", .accessory)
            ], preview: "Deadlift, RDL, leg curl, calves")
        ]
    )
}
