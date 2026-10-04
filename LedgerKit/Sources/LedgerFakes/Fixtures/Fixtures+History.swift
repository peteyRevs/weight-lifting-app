#if DEBUG
    import Foundation
    import LedgerDomain

    public extension Fixtures {
        /// Finished workouts of `seedProgram` over the `weeks` weeks that end with the one holding `now`, oldest
        /// first: each scheduled day at 07:00 UTC that started before `now`, built by `SessionBuilder` for its
        /// program week (weeks before the block's start repeat its first week), every set done as prescribed,
        /// two minutes apart, and the workout finished an hour after it started. None when `weeks` is below 1.
        static func history(weeks: Int) throws -> [WorkoutState] {
            let program = try seedProgram()
            let exercises = try catalogByID()
            let thisMonday = date(2026, 9, 14)
            let currentWeek = 4
            var workouts: [WorkoutState] = []
            for back in (0 ..< max(0, weeks)).reversed() {
                let index = max(0, currentWeek - back)
                guard let week = program.week(at: index) else {
                    throw Invalid(fixture: "history: week \(index)")
                }
                let monday = thisMonday.addingTimeInterval(-Double(back) * 7 * day)
                for (weekday, dayID) in week.schedule.sorted(by: { $0.key < $1.key }) {
                    let start = monday.addingTimeInterval(Double(weekday.rawValue - 1) * day + 7 * hour)
                    guard start < now, let template = program.days.first(where: { $0.id == dayID }) else {
                        continue
                    }
                    let built = try SessionBuilder.build(
                        program: program,
                        weekIndex: index,
                        day: template,
                        exercises: exercises,
                        history: [:],
                        settings: settingsLb,
                        id: WorkoutID(uuid(0x0700_0000 + back * 16 + weekday.rawValue)),
                        device: deviceID,
                        now: start
                    )
                    workouts.append(finished(built))
                }
            }
            return workouts
        }
    }

    extension Fixtures {
        private static let hour: TimeInterval = 3600
        private static let day: TimeInterval = 24 * hour

        /// `workout` with every set done as prescribed, two minutes apart, and finished an hour after its start.
        private static func finished(_ workout: WorkoutState) -> WorkoutState {
            var done = workout
            var tick = 0
            for exercise in done.exercises.indices {
                for set in done.exercises[exercise].sets.indices {
                    tick += 1
                    done.exercises[exercise].sets[set].doneAt = workout.startedAt.addingTimeInterval(Double(tick) * 120)
                }
            }
            done.cursor = nil
            done.rest = nil
            done.phase = .finished
            done.endedAt = workout.startedAt.addingTimeInterval(hour)
            return done
        }
    }
#endif
