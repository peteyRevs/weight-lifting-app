import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence

/// F05 S3 adversarial round 1: builders, databases and SQL probes for the history and stats attacks, written
/// from the brief and the public interfaces (never from `Seeders` or the contracts' fixtures), so the fixtures
/// cannot share a blind spot with the implementer's.
enum S3Kit {
    // MARK: - Identifiers

    /// A deterministic UUID: `family` names the kind of row, `number` the row.
    static func uuid(_ family: UInt16, _ number: Int) -> UUID {
        let text = String(format: "AD53%04X-0000-4000-8000-%012llX", family, UInt64(number))
        guard let uuid = UUID(uuidString: text) else {
            preconditionFailure("bad fixture uuid \(text)")
        }
        return uuid
    }

    static func workoutID(_ number: Int) -> WorkoutID {
        WorkoutID(uuid(0xA, number))
    }

    /// Row `index` of workout `workout`.
    static func rowID(_ workout: Int, _ index: Int) -> WorkoutExerciseID {
        WorkoutExerciseID(uuid(0xB, workout * 100 + index))
    }

    /// Set `position` of row `index` of workout `workout`.
    static func setID(_ workout: Int, _ index: Int, _ position: Int) -> SetID {
        SetID(uuid(0xC, workout * 10000 + index * 100 + position))
    }

    static func exerciseID(_ number: Int) -> ExerciseID {
        ExerciseID(uuid(0xE, number))
    }

    static let bench = exerciseID(1)
    static let squat = exerciseID(2)
    static let row = exerciseID(3)
    static let press = exerciseID(4)
    static let device = DeviceID(uuid(0xD, 1))

    /// 2026-09-16T05:20:00Z, a Wednesday.
    static let now = Date(timeIntervalSinceReferenceDate: 811_228_800)

    static func day(_ days: Double) -> Date {
        now.addingTimeInterval(86400 * days)
    }

    // MARK: - Workouts

    /// One set row to build.
    struct SetSpec: Sendable {
        var weight: Weight
        var reps: Int
        var kind: SetKind = .working
        var isDone = true
    }

    static func set(_ pounds: Decimal, _ reps: Int, _ kind: SetKind = .working, done: Bool = true) -> SetSpec {
        SetSpec(weight: .pounds(pounds), reps: reps, kind: kind, isDone: done)
    }

    /// One exercise row to build: what was performed, and its sets.
    struct RowSpec: Sendable {
        var exercise: ExerciseID
        var sets: [SetSpec]

        init(_ exercise: ExerciseID, _ sets: [SetSpec]) {
            self.exercise = exercise
            self.sets = sets
        }
    }

    static let rest: RestDuration = .defaultRest

    static func rpe(_ value: Decimal = 8) -> RPE {
        guard let rpe = RPE(value) else {
            preconditionFailure("a fixture RPE must be valid, got \(value)")
        }
        return rpe
    }

    /// A finished workout as a history read returns it. It ends at `endedAt`, `minutes` after it started;
    /// a done set is ticked one second before the end.
    static func workout(_ number: Int, endedAt: Date = now, minutes: Double = 45, _ rows: [RowSpec]) -> WorkoutState {
        WorkoutState(
            id: workoutID(number),
            source: nil,
            name: "Session \(number)",
            tag: "S\(number)",
            isDeload: false,
            exercises: rows.enumerated().map { index, spec in
                exercise(number, index, spec, doneAt: endedAt.addingTimeInterval(-1))
            },
            cursor: nil,
            startedAt: endedAt.addingTimeInterval(-60 * minutes),
            endedAt: endedAt,
            phase: .finished,
            originDevice: device,
            units: .lb
        )
    }

    static func exercise(_ workout: Int, _ index: Int, _ spec: RowSpec, doneAt: Date) -> WorkoutExercise {
        WorkoutExercise(
            id: rowID(workout, index),
            slotID: nil,
            exerciseID: spec.exercise,
            originalExerciseID: spec.exercise,
            name: "Lift \(index)",
            equipment: .barbell,
            step: .pounds(5),
            rest: rest,
            rpe: rpe(),
            isSupersetWithPrevious: false,
            targetSets: spec.sets.count,
            targetReps: spec.sets.first?.reps ?? 1,
            targetLoad: spec.sets.first?.weight ?? .zero,
            sets: spec.sets.enumerated().map { position, set in
                LoggedSet(
                    id: setID(workout, index, position),
                    weight: set.weight,
                    reps: Reps(clamping: set.reps),
                    kind: set.kind,
                    doneAt: set.isDone ? doneAt : nil
                )
            }
        )
    }

    /// Two exercises with every kind of set, one of them undone, one above 12 reps.
    static func mixed(_ number: Int, endedAt: Date = now) -> WorkoutState {
        workout(number, endedAt: endedAt, [
            RowSpec(bench, [set(185, 5), set(185, 5), set(190, 3, .added), set(155, 8, .drop), set(95, 10, .warmup)]),
            RowSpec(squat, [set(225, 13), set(225, 12), set(230, 5, done: false)])
        ])
    }

    static func record(
        _ exercise: ExerciseID,
        _ kind: PRKind,
        in workout: WorkoutState,
        at achievedAt: Date? = nil
    ) -> PersonalRecord {
        PersonalRecord(
            exerciseID: exercise,
            kind: kind,
            previous: nil,
            achievedAt: achievedAt ?? workout.endedAt ?? now,
            workoutID: workout.id
        )
    }

    // MARK: - Calendars

    static func calendar(_ zone: String = "UTC", weekStart: Weekday = .monday) -> WeekCalendar {
        var gregorian = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: zone), let start = CivilDate(year: 2026, month: 8, day: 17) else {
            preconditionFailure("unknown fixture time zone \(zone)")
        }
        gregorian.timeZone = timeZone
        return WeekCalendar(startDate: start, weekStart: weekStart, calendar: gregorian)
    }

    static func gregorian(_ zone: String) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: zone) else {
            preconditionFailure("unknown fixture time zone \(zone)")
        }
        gregorian.timeZone = timeZone
        return gregorian
    }

    /// The instant of a wall-clock time in `zone`.
    static func instant(
        _ zone: String,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0
    ) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = gregorian(zone).date(from: parts) else {
            preconditionFailure("no such instant \(parts)")
        }
        return date
    }
}
