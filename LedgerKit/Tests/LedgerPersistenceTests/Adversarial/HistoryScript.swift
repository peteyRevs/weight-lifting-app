import Foundation
import LedgerDomain

/// F05 S3 adversarial round 1: a seeded generator of history operations for the model test. Workouts come
/// from a small pool of ids, end dates, weights and reps, so ties, re-materialisations, shared weeks and
/// repeated exercises are common.
struct HistoryScript {
    enum Operation: Sendable {
        case materialize(WorkoutState, [PersonalRecord])
        case updateSets(WorkoutExerciseID, [LoggedSet])
        case delete(WorkoutID)
    }

    static let exercises = [S3Kit.bench, S3Kit.squat, S3Kit.row, S3Kit.press]
    static let zones = ["UTC", "America/New_York", "Pacific/Auckland", "Asia/Kathmandu"]
    /// The current times: a Wednesday before New Zealand's clocks change, the Saturday of ISO week 53 of 2026,
    /// and the Monday after the United States' clocks change.
    static let nows = [S3Kit.now, S3Kit.instant("UTC", 2027, 1, 2, 9), S3Kit.instant("UTC", 2026, 3, 9, 3)]

    var rng: SeededGenerator
    let now: Date
    let calendar: WeekCalendar
    /// The workout numbers a delete has named: a takeover prefers their ids.
    var deleted: [Int] = []

    init(seed: PropertySeed) {
        rng = seed.generator
        now = Self.nows[Int.random(in: 0 ..< Self.nows.count, using: &rng)]
        calendar = S3Kit.calendar(
            Self.zones[Int.random(in: 0 ..< Self.zones.count, using: &rng)],
            weekStart: Weekday.allCases[Int.random(in: 0 ..< 7, using: &rng)]
        )
    }

    mutating func pick<Value>(_ values: [Value]) -> Value {
        values[Int.random(in: 0 ..< values.count, using: &rng)]
    }

    mutating func chance(_ percent: Int) -> Bool {
        Int.random(in: 0 ..< 100, using: &rng) < percent
    }

    /// A start date: a week boundary of the calendar, or a few fixed times on a day within ten weeks of `now`.
    /// Round 1 used these as end dates; since product decision #26 a workout's date is its start, so the start
    /// now lands on these edges (S3 fix round 3).
    mutating func startDate() -> Date {
        let week = calendar.week(containing: now)
        if chance(20) {
            return pick([week.lowerBound, week.upperBound, week.lowerBound.addingTimeInterval(-0.5), now])
        }
        let day = Double(pick([-70, -56, -22, -15, -8, -7, -6, -1, 0, 1, 6, 7, 12, 47]))
        return now.addingTimeInterval(86400 * day + pick([0, 10800, 67200, 86399]))
    }

    mutating func sets() -> [S3Kit.SetSpec] {
        (0 ..< Int.random(in: 0 ... 4, using: &rng)).map { _ in
            S3Kit.SetSpec(
                weight: pick([.pounds(100), .pounds(105), .pounds(102.5), .kilograms(47.5), .zero]),
                reps: pick([1, 3, 5, 5, 12, 13, 20]),
                kind: pick([.working, .working, .working, .added, .drop, .warmup]),
                isDone: chance(80)
            )
        }
    }

    mutating func workout(_ number: Int) -> WorkoutState {
        let rows = (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in
            S3Kit.RowSpec(pick(Self.exercises), sets())
        }
        let start = startDate()
        let minutes = pick([30.0, 600, 20000])
        return S3Kit.workout(number, endedAt: start.addingTimeInterval(60 * minutes), minutes: minutes, rows)
    }

    /// At most one record of each kind, for one exercise, achieved at a time only this workout has.
    mutating func records(for workout: WorkoutState, number: Int) -> [PersonalRecord] {
        let exercise = pick(Self.exercises)
        let achieved = S3Kit.now.addingTimeInterval(Double(number))
        let kinds: [PRKind] = [.weightAtReps(.pounds(105), Reps(clamping: 5)), .estimatedOneRepMax(.pounds(120))]
        return kinds.filter { _ in chance(40) }.map { S3Kit.record(exercise, $0, in: workout, at: achieved) }
    }

    /// The next operation: mostly materialisations of the six workouts, valid or not.
    mutating func next() -> Operation {
        let number = Int.random(in: 1 ... 6, using: &rng)
        switch Int.random(in: 0 ..< 100, using: &rng) {
        case 0 ..< 50:
            var workout = workout(number)
            let prs = records(for: workout, number: number)
            spoil(&workout, number: number)
            return .materialize(workout, prs)
        case 50 ..< 80:
            let row = Int.random(in: 0 ... 3, using: &rng)
            let other = chance(15) ? Int.random(in: 1 ... 6, using: &rng) : number
            let specs = sets()
            let exercise = S3Kit.exercise(other, row, S3Kit.RowSpec(S3Kit.bench, specs), doneAt: now)
            return .updateSets(S3Kit.rowID(number, row), exercise.sets)
        default:
            deleted.append(number)
            return .delete(S3Kit.workoutID(number))
        }
    }

    /// Now and then makes `workout` one that must be refused: not finished, or holding one id of another
    /// workout's row or set, or one of its own twice.
    mutating func spoil(_ workout: inout WorkoutState, number: Int) {
        let other = deleted.last { $0 != number } ?? number % 6 + 1
        switch Int.random(in: 0 ..< 100, using: &rng) {
        case 0 ..< 5:
            workout.phase = pick([.live, .discarded])
        case 5 ..< 8:
            workout.endedAt = nil
        case 8 ..< 16 where !workout.exercises.isEmpty:
            let taken = S3Kit.exercise(
                other,
                Int.random(in: 0 ... 2, using: &rng),
                S3Kit.RowSpec(S3Kit.row, []),
                doneAt: now
            )
            workout.exercises[0] = taken
        case 16 ..< 24 where !workout.exercises.isEmpty:
            let taken = S3Kit.exercise(other, 0, S3Kit.RowSpec(S3Kit.row, [S3Kit.set(100, 5)]), doneAt: now)
            workout.exercises[0].sets.append(contentsOf: taken.sets)
        case 24 ..< 28 where workout.exercises.count > 1:
            workout.exercises[1].sets.append(contentsOf: workout.exercises[0].sets.prefix(1))
        default:
            break
        }
    }
}
