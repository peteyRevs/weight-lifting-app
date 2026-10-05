import Foundation
@testable import LedgerDomain
import Testing

/// The F08 brief as the G2 tester transcribed it (2026-10-04), for the adversarial suites: the role table, the
/// "Templates" list as amended ("Plan amendments", slice S1) and spec §6.4. Nothing here is read from
/// `ProgramTemplates`: a value that disagrees with the product is a finding, not a number to copy across.
enum BriefTemplates {
    /// A lift's weight in its day: the brief's `P`, `S` and `A`.
    enum Role: Int, Sendable {
        case primary, secondary, accessory
    }

    /// One prescription: `sets` × `reps` (double progression up to `repsHi`) at `rpe`, `rest` seconds, `progression`.
    struct Scheme: Equatable, Sendable, CustomStringConvertible {
        var sets: Int
        var reps: Int
        var repsHi: Int
        var rpe: Decimal
        var rest: Int
        var progression: Progression

        var description: String {
            "\(sets)×\(reps) (hi \(repsHi)) RPE \(rpe) \(rest) s \(progression.rawValue)"
        }
    }

    /// One exercise of a template day. `seed` is its spec §6.4 row, which only `both` on four days uses.
    struct Lift: Sendable {
        var exercise: String
        var role: Role
        var seed: Scheme?
        var superset = false
        var drop = 0
    }

    struct Day: Sendable {
        var name: String
        var tag: String
        var line: String
        var lifts: [Lift]
    }

    struct Split: Sendable {
        var programName: String
        /// The weekday of each day, in the days' order.
        var weekdays: [Weekday]
        /// Amendment 5: only the 4-day split rests an extra day (Saturday) in week 8.
        var deloadRest: Set<Weekday> = []
        var days: [Day]
    }

    /// What one slot of a generated program must hold, in every column the brief fixes but load and step.
    struct ExpectedSlot: Equatable, Sendable, CustomStringConvertible {
        var exercise: String
        var scheme: Scheme
        var superset: Bool
        var drop: Int

        var description: String {
            "\(exercise) \(scheme)\(superset ? " superset" : "")\(drop > 0 ? " drop \(drop)" : "")"
        }
    }

    /// One of the 32 inputs: 4 goals × 4 day counts × 2 units.
    struct Case: Sendable, CustomStringConvertible {
        var goal: TrainingGoal
        var days: DaysPerWeek
        var units: Units

        var description: String {
            "\(goal.rawValue) × \(days.rawValue) days in \(units.rawValue)"
        }

        static let all: [Case] = TrainingGoal.allCases.flatMap { goal in
            DaysPerWeek.allCases.flatMap { days in
                Units.allCases.map { Case(goal: goal, days: days, units: $0) }
            }
        }

        /// Sixteen: every goal on every split, in pounds.
        static let pounds = all.filter { $0.units == .lb }
    }
}

// MARK: - The role table

extension BriefTemplates {
    /// The brief's role table, one row per goal in the order primary, secondary, accessory. The goals carry
    /// `main`'s case names (amendment 1): stronger, muscle, both, consistent.
    static let roleTable: [TrainingGoal: [Scheme]] = [
        .strength: [
            Scheme(sets: 5, reps: 5, repsHi: 7, rpe: 8, rest: 180, progression: .linear),
            Scheme(sets: 4, reps: 6, repsHi: 8, rpe: 8, rest: 150, progression: .linear),
            Scheme(sets: 3, reps: 8, repsHi: 10, rpe: 8, rest: 90, progression: .linear)
        ],
        .hypertrophy: [
            Scheme(sets: 4, reps: 8, repsHi: 10, rpe: 8, rest: 120, progression: .double),
            Scheme(sets: 3, reps: 10, repsHi: 12, rpe: 8, rest: 90, progression: .double),
            Scheme(sets: 3, reps: 12, repsHi: 15, rpe: 9, rest: 60, progression: .double)
        ],
        .both: [
            Scheme(sets: 5, reps: 5, repsHi: 7, rpe: 8, rest: 150, progression: .linear),
            Scheme(sets: 3, reps: 8, repsHi: 10, rpe: 8, rest: 120, progression: .linear),
            Scheme(sets: 3, reps: 12, repsHi: 14, rpe: 9, rest: 75, progression: .double)
        ],
        .consistency: [
            Scheme(sets: 3, reps: 5, repsHi: 7, rpe: 7, rest: 120, progression: .linear),
            Scheme(sets: 3, reps: 8, repsHi: 10, rpe: 7, rest: 90, progression: .fixed),
            Scheme(sets: 2, reps: 12, repsHi: 14, rpe: 7, rest: 60, progression: .fixed)
        ]
    ]

    static func scheme(_ goal: TrainingGoal, _ role: Role) throws -> Scheme {
        let row = try #require(roleTable[goal], "the role table has no row for \(goal)")
        return row[role.rawValue]
    }

    /// The slots `goal` on `days` must have, day by day: spec §6.4's own rows for `both` on four days (the
    /// brief's "Exception (canonical seed)"), the role table everywhere else. Supersets and the drop set stay.
    static func expectedSlots(goal: TrainingGoal, days: DaysPerWeek) throws -> [[ExpectedSlot]] {
        let usesSeed = goal == .both && days == .four
        return try split(days).days.map { day in
            try day.lifts.map { lift in
                let fromTable = try scheme(goal, lift.role)
                let scheme = try usesSeed ? #require(lift.seed, "\(lift.exercise) has no §6.4 row") : fromTable
                return ExpectedSlot(exercise: lift.exercise, scheme: scheme, superset: lift.superset, drop: lift.drop)
            }
        }
    }

    static func split(_ days: DaysPerWeek) -> Split {
        switch days {
        case .three: fullBody
        case .four: upperLower
        case .five: pushPullLegs
        case .six: bodyPart
        }
    }

    /// Every week's schedule as (weekday, index of the day trained): weeks 1–7 train every day, and week 8
    /// rests on `deloadRest` as well.
    static func expectedSchedule(_ days: DaysPerWeek, weekIndex: Int) -> [Weekday: Int] {
        let split = split(days)
        let rests = weekIndex == 7 ? split.deloadRest : []
        let pairs = zip(split.weekdays, split.weekdays.indices).filter { !rests.contains($0.0) }
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })
    }
}

// MARK: - Generating

extension BriefTemplates {
    /// Monday 2026-09-14: criterion 11's start date.
    static let monday = Fixtures.civil(2026, 9, 14)
    static let programID = ProgramID(Fixtures.uuid(77000))

    private static let seeded = Result { try ExerciseCatalog.seed() }

    /// The bundled catalog, in file order.
    static func catalog() throws -> [Exercise] {
        try seeded.get()
    }

    static func request(_ input: Case, startDate: CivilDate = monday) -> ProgramTemplates.Request {
        ProgramTemplates.Request(goal: input.goal, days: input.days, units: input.units, startDate: startDate)
    }

    /// The program for `input`, with ids `uuid(firstID)`, `uuid(firstID + 1)` … in the order the generator asks.
    static func program(
        _ input: Case,
        catalog: [Exercise]? = nil,
        startDate: CivilDate = monday,
        firstID: Int = 1
    ) throws -> Program {
        var next = firstID
        return try ProgramTemplates.program(
            request(input, startDate: startDate),
            catalog: catalog ?? self.catalog(),
            id: programID
        ) {
            defer { next += 1 }
            return Fixtures.uuid(next)
        }
    }

    /// `slot` as the brief describes one, naming its exercise as `exercises` does.
    static func observed(_ slot: Slot, exercises: [ExerciseID: Exercise]) -> ExpectedSlot {
        ExpectedSlot(
            exercise: exercises[slot.exerciseID]?.name ?? "unknown exercise \(slot.exerciseID.rawValue)",
            scheme: Scheme(
                sets: slot.sets,
                reps: slot.reps,
                repsHi: slot.repsHi,
                rpe: slot.rpe.value,
                rest: slot.rest.seconds,
                progression: slot.progression
            ),
            superset: slot.isSupersetWithPrevious,
            drop: slot.dropSets
        )
    }

    static func byID(_ exercises: [Exercise]) -> [ExerciseID: Exercise] {
        Dictionary(exercises.map { ($0.id, $0) }) { first, _ in first }
    }
}
