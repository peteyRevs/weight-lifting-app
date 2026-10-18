import Foundation

// MARK: - What a slot prescribes

extension ProgramTemplates {
    /// What a slot prescribes before any week's progression (spec §6.1 "Exercise slot"): `sets` sets of
    /// `reps.lowerBound` reps, which double progression climbs to `reps.upperBound`, at `rpe`, with `rest`
    /// seconds after each set. Every scheme below is inside spec §7.1's limits, which `Slot.init` checks.
    struct Scheme: Sendable {
        let sets: Int
        /// `Slot.reps ... Slot.repsHi`.
        let reps: ClosedRange<Int>
        let rpe: Decimal
        /// Whole seconds.
        let rest: Int
        let progression: Progression

        init(_ sets: Int, reps: ClosedRange<Int>, rpe: Decimal, rest: Int, _ progression: Progression) {
            self.sets = sets
            self.reps = reps
            self.rpe = rpe
            self.rest = rest
            self.progression = progression
        }
    }

    /// One goal's row of the role table: a scheme per role.
    struct RoleSchemes: Sendable {
        let primary: Scheme
        let secondary: Scheme
        let accessory: Scheme

        subscript(role: Role) -> Scheme {
            switch role {
            case .primary: primary
            case .secondary: secondary
            case .accessory: accessory
            }
        }
    }
}

extension ProgramTemplates.Split {
    /// What `lift` prescribes for `goal`: this split's own seed row under `both`, where it has one (spec §6.4,
    /// on the 4-day split), and the role table's scheme for the lift's role everywhere else.
    func scheme(for lift: ProgramTemplates.Lift, goal: TrainingGoal) -> ProgramTemplates.Scheme {
        if goal == .both, let row = seed[lift.exercise] {
            return row
        }
        return ProgramTemplates.schemes(for: goal)[lift.role]
    }
}

// MARK: - The role table (F08 brief)

extension ProgramTemplates {
    /// What `goal` prescribes for a day's main lift, its second compound lifts and its accessories. These are
    /// our defaults, not the prototype's, which has one program and ignores the goal (spec §6.7).
    static func schemes(for goal: TrainingGoal) -> RoleSchemes {
        switch goal {
        case .strength: strength
        case .hypertrophy: hypertrophy
        case .both: both
        case .consistency: consistency
        }
    }

    /// "Get stronger — Low reps, linear load increases": every lift is heavy and adds load each week.
    private static let strength = RoleSchemes(
        primary: Scheme(5, reps: 5 ... 7, rpe: 8, rest: 180, .linear),
        secondary: Scheme(4, reps: 6 ... 8, rpe: 8, rest: 150, .linear),
        accessory: Scheme(3, reps: 8 ... 10, rpe: 8, rest: 90, .linear)
    )

    /// "Build muscle — Moderate reps, volume tracking": reps climb through a range before the load does.
    private static let hypertrophy = RoleSchemes(
        primary: Scheme(4, reps: 8 ... 10, rpe: 8, rest: 120, .double),
        secondary: Scheme(3, reps: 10 ... 12, rpe: 8, rest: 90, .double),
        accessory: Scheme(3, reps: 12 ... 15, rpe: 9, rest: 60, .double)
    )

    /// "Both, honestly — Barbell strength + accessory volume": linear on the compound lifts, double
    /// progression on the accessories.
    private static let both = RoleSchemes(
        primary: Scheme(5, reps: 5 ... 7, rpe: 8, rest: 150, .linear),
        secondary: Scheme(3, reps: 8 ... 10, rpe: 8, rest: 120, .linear),
        accessory: Scheme(3, reps: 12 ... 14, rpe: 9, rest: 75, .double)
    )

    /// "Stay consistent — Habit first, numbers second": fewer, easier sets, and only the main lift's load moves.
    private static let consistency = RoleSchemes(
        primary: Scheme(3, reps: 5 ... 7, rpe: 7, rest: 120, .linear),
        secondary: Scheme(3, reps: 8 ... 10, rpe: 7, rest: 90, .fixed),
        accessory: Scheme(2, reps: 12 ... 14, rpe: 7, rest: 60, .fixed)
    )
}

// MARK: - Spec §6.4

extension ProgramTemplates {
    /// The prototype's own program, row by row (spec §6.4), by exercise: what `both` prescribes on the 4-day
    /// split. The table's load and step columns are not here: a start load is the catalog's (decision #21) and
    /// a slot's step is `nil`.
    static let specSeed: [String: Scheme] = [
        "Barbell Bench Press": specRow(5, 5, rest: 150),
        "Incline DB Press": specRow(3, 10, rest: 90, .double),
        "Chest-Supported Row": specRow(4, 8, rest: 90),
        "Lat Pulldown": specRow(3, 12, rpe: 9, rest: 75, .double),
        "Cable Lateral Raise": specRow(3, 15, rpe: 9, rest: 60, .double),
        "Back Squat": specRow(5, 5, rest: 180),
        "Romanian Deadlift": specRow(3, 8, rest: 120),
        "Leg Press": specRow(3, 12, rpe: 9, rest: 90, .double),
        "Standing Calf Raise": specRow(4, 12, rpe: 9, rest: 60, .fixed),
        "Weighted Pull-Up": specRow(4, 6, rest: 150),
        "Overhead Press": specRow(4, 6, rest: 120),
        "Barbell Row": specRow(3, 10, rest: 90),
        "Barbell Curl": specRow(3, 12, rpe: 9, rest: 60, .double),
        "Deadlift": specRow(4, 4, rest: 210),
        "Front Squat": specRow(3, 8, rest: 120),
        "Seated Leg Curl": specRow(3, 12, rpe: 9, rest: 75, .double)
    ]

    /// A row as the prototype's `mk(name, sets, reps, rpe, rest)` writes it: `repsHi = reps + 2`, and RPE 8
    /// and linear progression unless the row says otherwise.
    private static func specRow(
        _ sets: Int,
        _ reps: Int,
        rpe: Decimal = 8,
        rest: Int,
        _ progression: Progression = .linear
    ) -> Scheme {
        Scheme(sets, reps: reps ... reps + 2, rpe: rpe, rest: rest, progression)
    }
}
