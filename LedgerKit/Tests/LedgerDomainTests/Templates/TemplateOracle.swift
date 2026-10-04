import Foundation
@testable import LedgerDomain

/// The F08 brief's tables, written out a second time as the template suites' oracle: the role table, spec
/// §6.4's rows, and the "Templates" list with the catalog's full names (the brief's amendment 4). Nothing here
/// reads `ProgramTemplates`, so a changed template has to be changed here as well, on purpose.
enum TemplateOracle {
    /// The columns spec §6.4 and the role table share: sets × reps (up to `repsHi`) at an RPE, the rest in
    /// seconds, and the progression.
    struct Scheme: Equatable, Sendable, CustomStringConvertible {
        let sets: Int
        let reps: Int
        let repsHi: Int
        let rpe: Decimal
        let rest: Int
        let progression: Progression

        init(_ sets: Int, _ reps: Int, hi repsHi: Int, rpe: Decimal, rest: Int, _ progression: Progression) {
            self.sets = sets
            self.reps = reps
            self.repsHi = repsHi
            self.rpe = rpe
            self.rest = rest
            self.progression = progression
        }

        /// What `slot` prescribes.
        init(_ slot: Slot) {
            self.init(
                slot.sets,
                slot.reps,
                hi: slot.repsHi,
                rpe: slot.rpe.value,
                rest: slot.rest.seconds,
                slot.progression
            )
        }

        var description: String {
            "\(sets) × \(reps)–\(repsHi) @ RPE \(rpe), \(rest) s, \(progression.rawValue)"
        }
    }

    /// The role table, by goal and by the role's letter in the brief: P primary, S secondary, A accessory.
    static let roleTable: [TrainingGoal: [Character: Scheme]] = [
        .strength: [
            "P": Scheme(5, 5, hi: 7, rpe: 8, rest: 180, .linear),
            "S": Scheme(4, 6, hi: 8, rpe: 8, rest: 150, .linear),
            "A": Scheme(3, 8, hi: 10, rpe: 8, rest: 90, .linear)
        ],
        .hypertrophy: [
            "P": Scheme(4, 8, hi: 10, rpe: 8, rest: 120, .double),
            "S": Scheme(3, 10, hi: 12, rpe: 8, rest: 90, .double),
            "A": Scheme(3, 12, hi: 15, rpe: 9, rest: 60, .double)
        ],
        .both: [
            "P": Scheme(5, 5, hi: 7, rpe: 8, rest: 150, .linear),
            "S": Scheme(3, 8, hi: 10, rpe: 8, rest: 120, .linear),
            "A": Scheme(3, 12, hi: 14, rpe: 9, rest: 75, .double)
        ],
        .consistency: [
            "P": Scheme(3, 5, hi: 7, rpe: 7, rest: 120, .linear),
            "S": Scheme(3, 8, hi: 10, rpe: 7, rest: 90, .fixed),
            "A": Scheme(2, 12, hi: 14, rpe: 7, rest: 60, .fixed)
        ]
    ]

    /// One row of spec §6.4's table, without its load and step columns (the brief's amendment 2).
    struct SeedRow: Sendable, CustomStringConvertible {
        let tag: String
        /// The table's `#` column: 1 for the day's first slot.
        let number: Int
        let exercise: String
        let scheme: Scheme
        let isSuperset: Bool
        let dropSets: Int

        init(
            _ tag: String,
            _ number: Int,
            _ exercise: String,
            _ scheme: Scheme,
            isSuperset: Bool = false,
            dropSets: Int = 0
        ) {
            self.tag = tag
            self.number = number
            self.exercise = exercise
            self.scheme = scheme
            self.isSuperset = isSuperset
            self.dropSets = dropSets
        }

        var description: String {
            "\(tag) #\(number) \(exercise)"
        }
    }

    static let seedRows: [SeedRow] = [
        SeedRow("UA", 1, "Barbell Bench Press", Scheme(5, 5, hi: 7, rpe: 8, rest: 150, .linear)),
        SeedRow("UA", 2, "Incline DB Press", Scheme(3, 10, hi: 12, rpe: 8, rest: 90, .double)),
        SeedRow("UA", 3, "Chest-Supported Row", Scheme(4, 8, hi: 10, rpe: 8, rest: 90, .linear)),
        SeedRow("UA", 4, "Lat Pulldown", Scheme(3, 12, hi: 14, rpe: 9, rest: 75, .double)),
        SeedRow("UA", 5, "Cable Lateral Raise", Scheme(3, 15, hi: 17, rpe: 9, rest: 60, .double), isSuperset: true),
        SeedRow("LA", 1, "Back Squat", Scheme(5, 5, hi: 7, rpe: 8, rest: 180, .linear)),
        SeedRow("LA", 2, "Romanian Deadlift", Scheme(3, 8, hi: 10, rpe: 8, rest: 120, .linear)),
        SeedRow("LA", 3, "Leg Press", Scheme(3, 12, hi: 14, rpe: 9, rest: 90, .double)),
        SeedRow("LA", 4, "Standing Calf Raise", Scheme(4, 12, hi: 14, rpe: 9, rest: 60, .fixed), isSuperset: true),
        SeedRow("UB", 1, "Weighted Pull-Up", Scheme(4, 6, hi: 8, rpe: 8, rest: 150, .linear)),
        SeedRow("UB", 2, "Overhead Press", Scheme(4, 6, hi: 8, rpe: 8, rest: 120, .linear)),
        SeedRow("UB", 3, "Barbell Row", Scheme(3, 10, hi: 12, rpe: 8, rest: 90, .linear)),
        SeedRow("UB", 4, "Barbell Curl", Scheme(3, 12, hi: 14, rpe: 9, rest: 60, .double), dropSets: 1),
        SeedRow("LB", 1, "Deadlift", Scheme(4, 4, hi: 6, rpe: 8, rest: 210, .linear)),
        SeedRow("LB", 2, "Front Squat", Scheme(3, 8, hi: 10, rpe: 8, rest: 120, .linear)),
        SeedRow("LB", 3, "Seated Leg Curl", Scheme(3, 12, hi: 14, rpe: 9, rest: 75, .double))
    ]
}
