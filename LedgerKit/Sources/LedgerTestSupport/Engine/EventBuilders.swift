import Foundation
import LedgerDomain

/// Live-workout fixtures shared by the engine tests (F04) and the sync tests (F17): sessions to
/// start from, and envelope logs with per-device sequence numbers.
public enum EventBuilders {
    /// The phone. Its ID sorts before the watch's, so on equal wall clocks the phone's envelope comes first.
    public static let phone = DeviceID(uuid(0xF001))
    public static let watch = DeviceID(uuid(0xF002))
    public static let workoutID = WorkoutID(uuid(0xF100))
    /// 2026-09-16T05:20:00Z, the fixed "now" of testing-strategy §3 rule 1.
    public static let start = Date(timeIntervalSince1970: 1_789_536_000)

    /// One exercise of a built session: `sets` working rows of `reps` × `pounds`, plus a drop row
    /// at the same weight when `dropSet` is on.
    public struct ExerciseSpec: Sendable {
        public var name: String
        public var equipment: Equipment
        public var sets: Int
        public var reps: Int
        public var pounds: Decimal
        public var restSeconds: Int
        public var isSupersetWithPrevious: Bool
        public var dropSet: Bool

        public init(
            _ name: String,
            _ equipment: Equipment,
            sets: Int,
            reps: Int,
            pounds: Decimal,
            restSeconds: Int,
            superset: Bool = false,
            dropSet: Bool = false
        ) {
            self.name = name
            self.equipment = equipment
            self.sets = sets
            self.reps = reps
            self.pounds = pounds
            self.restSeconds = restSeconds
            isSupersetWithPrevious = superset
            self.dropSet = dropSet
        }
    }

    /// Spec §6.3's five-exercise session, all straight sets: Bench 5 × 5 @ 185 lb (rest 150 s),
    /// Incline DB 3 × 10 @ 55 (90 s), Chest-Supported Row 4 × 8 @ 70 (90 s), Lat Pulldown 3 × 12 @ 100
    /// (75 s) and Cable Lateral Raise 3 × 15 @ 15 (60 s).
    public static let seedExercises: [ExerciseSpec] = [
        ExerciseSpec("Barbell Bench Press", .barbell, sets: 5, reps: 5, pounds: 185, restSeconds: 150),
        ExerciseSpec("Incline DB Press", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90),
        ExerciseSpec("Chest-Supported Row", .machine, sets: 4, reps: 8, pounds: 70, restSeconds: 90),
        ExerciseSpec("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75),
        ExerciseSpec("Cable Lateral Raise", .cable, sets: 3, reps: 15, pounds: 15, restSeconds: 60)
    ]

    /// Criterion 2's superset: A (3 sets, rest 90 s) then B (3 sets, rest 60 s, superset with A).
    public static let supersetExercises: [ExerciseSpec] = [
        ExerciseSpec("Incline DB Press", .dumbbell, sets: 3, reps: 10, pounds: 55, restSeconds: 90),
        ExerciseSpec("Chest-Supported Row", .machine, sets: 3, reps: 8, pounds: 70, restSeconds: 60, superset: true)
    ]

    /// The spec §6.3 session as a `started` snapshot.
    public static func seedSession(autoRest: Bool = true) -> WorkoutState {
        session(seedExercises, autoRest: autoRest)
    }

    /// A live snapshot as `SessionBuilder` would build it: cursor on (0, 0), IDs derived from `id`,
    /// exercise `i` for slot and exercise `uuid(0xE000 + i)`.
    public static func session(
        _ specs: [ExerciseSpec],
        id: WorkoutID = workoutID,
        autoRest: Bool = true,
        device: DeviceID = phone,
        startedAt: Date = start
    ) -> WorkoutState {
        WorkoutState(
            id: id,
            source: nil,
            name: "Upper A — Push focus",
            tag: "UA",
            isDeload: false,
            exercises: specs.enumerated().map { exercise($1, index: $0, workout: id) },
            cursor: specs.isEmpty ? nil : Cursor(exerciseIndex: 0, setIndex: 0),
            startedAt: startedAt,
            phase: .live,
            originDevice: device,
            autoRest: autoRest
        )
    }

    /// The set ID of row `setIndex` of exercise `exerciseIndex` in a session built for `workout`.
    public static func setID(_ exerciseIndex: Int, _ setIndex: Int, workout: WorkoutID = workoutID) -> SetID {
        .derived(from: .derived(from: workout, index: exerciseIndex), index: setIndex)
    }

    /// One envelope.
    public static func envelope(
        _ event: WorkoutEvent,
        device: DeviceID = phone,
        seq: UInt64,
        at wallClock: Date,
        workoutID: WorkoutID = workoutID
    ) -> EventEnvelope {
        EventEnvelope(event: event, workoutID: workoutID, device: device, seq: seq, wallClock: wallClock)
    }

    /// `events` as `device` records them: seq `firstSeq`, `firstSeq + 1`, … and wall clocks
    /// `startingAt`, `startingAt + spacing`, …
    public static func log(
        from events: [WorkoutEvent],
        device: DeviceID = phone,
        firstSeq: UInt64 = 1,
        startingAt: Date = start,
        spacing: TimeInterval = 10,
        workoutID: WorkoutID = workoutID
    ) -> [EventEnvelope] {
        events.enumerated().map { offset, event in
            envelope(
                event,
                device: device,
                seq: firstSeq + UInt64(offset),
                at: startingAt.addingTimeInterval(spacing * Double(offset)),
                workoutID: workoutID
            )
        }
    }

    /// A fixed UUID whose last bytes are `number`: 00000000-0000-0000-0000-0000000NNNNN.
    public static func uuid(_ number: Int) -> UUID {
        func byte(_ shift: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: number >> shift)
        }
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte(24), byte(16), byte(8), byte(0)))
    }

    private static func exercise(_ spec: ExerciseSpec, index: Int, workout: WorkoutID) -> WorkoutExercise {
        let id = WorkoutExerciseID.derived(from: workout, index: index)
        let exerciseID = ExerciseID(uuid(0xE000 + index))
        let reps = Reps(clamping: spec.reps)
        let kinds = Array(repeating: SetKind.working, count: spec.sets) + (spec.dropSet ? [.drop] : [])
        return WorkoutExercise(
            id: id,
            slotID: SlotID(uuid(0xE000 + index)),
            exerciseID: exerciseID,
            originalExerciseID: exerciseID,
            name: spec.name,
            equipment: spec.equipment,
            step: spec.equipment.defaultStep(in: .lb),
            rest: rest(spec.restSeconds),
            rpe: rpe(8),
            isSupersetWithPrevious: spec.isSupersetWithPrevious,
            targetSets: spec.sets,
            targetReps: spec.reps,
            targetLoad: .pounds(spec.pounds),
            sets: kinds.enumerated().map { row, kind in
                LoggedSet(id: .derived(from: id, index: row), weight: .pounds(spec.pounds), reps: reps, kind: kind)
            }
        )
    }

    private static func rest(_ seconds: Int) -> RestDuration {
        guard let rest = RestDuration(seconds: seconds) else {
            preconditionFailure("A fixture rest must be 30…300 s in 15 s steps, got \(seconds)")
        }
        return rest
    }

    private static func rpe(_ value: Decimal) -> RPE {
        guard let rpe = RPE(value) else {
            preconditionFailure("A fixture RPE must be 5…10 in 0.5 steps, got \(value)")
        }
        return rpe
    }
}
