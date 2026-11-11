import Foundation
import LedgerDomain

public extension DataResetContract {
    /// What the stores hold, as the reads show it: compared before and after an erase that must change nothing, and
    /// after one that must leave the empty state.
    struct Contents: Equatable, Sendable {
        public let exercises: [Exercise]
        public let active: Program?
        public let recent: [WorkoutState]
        public let entries: [HistoryEntry]
        public let deleted: WorkoutState?
        public let logs: [WorkoutID]
        public let settings: Settings

        public static func read(_ stores: DataResetStores) async throws -> Contents {
            try await Contents(
                exercises: stores.exercises.all(),
                active: stores.programs.active(),
                recent: stores.workouts.recent(limit: 100),
                entries: stores.workouts.historyEntries(),
                deleted: stores.workouts.workout(id: workout(3).id),
                logs: stores.events.uncompactedWorkoutIDs(),
                settings: stores.settings.load()
            )
        }

        /// A new install's, after its first launch: the bundled catalog in name order, no program, workout or log, and
        /// `settings`.
        public static func fresh(_ settings: Settings) throws -> Contents {
            try Contents(
                exercises: ExerciseSearch.sorted(ExerciseCatalog.seed()),
                active: nil,
                recent: [],
                entries: [],
                deleted: nil,
                logs: [],
                settings: settings
            )
        }

        /// The first field that differs from `expected`, by name, or nil: a whole history is never printed.
        public func difference(from expected: Contents) -> String? {
            let fields: [(String, Bool)] = [
                (
                    "exercises (\(exercises.count), expected \(expected.exercises.count))",
                    exercises == expected.exercises
                ),
                ("the active program", active == expected.active),
                ("recent (\(recent.count), expected \(expected.recent.count))", recent == expected.recent),
                ("history entries", entries == expected.entries),
                ("the deleted workout", deleted == expected.deleted),
                ("the live logs (\(logs.count))", logs == expected.logs),
                ("the settings", settings == expected.settings)
            ]
            return fields.first { !$0.1 }.map { "differs in \($0.0)" }
        }
    }
}
