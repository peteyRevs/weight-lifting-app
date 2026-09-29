import Foundation

/// Lifecycle of a workout (ADR-004; `finished` and `discarded` are terminal).
public enum WorkoutPhase: String, Codable, Sendable, CaseIterable {
    case live, finished, discarded
}

/// Which program week and day a workout was built from (rule 17 resumes on the same source).
public struct WorkoutSource: Hashable, Codable, Sendable {
    public let programID: ProgramID
    public let weekIndex: Int
    public let dayTemplateID: DayTemplateID

    public init(programID: ProgramID, weekIndex: Int, dayTemplateID: DayTemplateID) {
        self.programID = programID
        self.weekIndex = weekIndex
        self.dayTemplateID = dayTemplateID
    }
}

/// The selected row: an index into `exercises` and into that exercise's `sets`.
public struct Cursor: Hashable, Codable, Sendable {
    public var exerciseIndex: Int
    public var setIndex: Int

    public init(exerciseIndex: Int, setIndex: Int) {
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
    }
}

/// The live (or finished) workout: the state the `WorkoutEngine` (F04) folds events into.
public struct WorkoutState: Identifiable, Hashable, Codable, Sendable {
    public let id: WorkoutID
    /// `nil` for an ad-hoc workout.
    public var source: WorkoutSource?
    public var name: String
    public var tag: String
    public var isDeload: Bool
    public var exercises: [WorkoutExercise]
    public var cursor: Cursor?
    public var rest: RestTimer?
    public var startedAt: Date
    public var endedAt: Date?
    public var phase: WorkoutPhase
    public var originDevice: DeviceID
    /// Settings "Auto rest timer" snapshotted at build time (decision #7; read by F04 rule 3).
    public var autoRest: Bool
    /// Settings units snapshotted at build time: the units of the receipt rows (rule 30, F04 `summary`).
    public var units: Units
    /// Decision #13: the exercise each slot should hold in the program after this workout, recorded by
    /// swaps with "Also update program" (latest swap per slot wins). F05 applies them on materialisation.
    public var programUpdates: [SlotID: ExerciseID]

    public init(
        id: WorkoutID,
        source: WorkoutSource?,
        name: String,
        tag: String,
        isDeload: Bool,
        exercises: [WorkoutExercise],
        cursor: Cursor?,
        rest: RestTimer? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        phase: WorkoutPhase,
        originDevice: DeviceID,
        autoRest: Bool = true,
        units: Units = .lb,
        programUpdates: [SlotID: ExerciseID] = [:]
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.tag = tag
        self.isDeload = isDeload
        self.exercises = exercises
        self.cursor = cursor
        self.rest = rest
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phase = phase
        self.originDevice = originDevice
        self.autoRest = autoRest
        self.units = units
        self.programUpdates = programUpdates
    }

    /// Sets ticked done, across every exercise and kind.
    public var doneSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count(where: \.isDone) }
    }

    /// Every set row, across every exercise and kind (rule 26 grows it on "+ Add set").
    public var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// Rule 34: Σ over done sets of weight × reps.
    public var volume: Volume {
        exercises
            .flatMap(\.sets)
            .filter(\.isDone)
            .reduce(Volume.zero) { $0 + Volume(weight: $1.weight, reps: $1.reps) }
    }

    /// Rule 24: time since `startedAt`, frozen at `endedAt` once the workout ends; never negative.
    /// It saturates at `Int64.max` seconds (NaN gives zero), because both dates can come from a peer's
    /// envelope and `Duration.seconds` traps on a non-finite or out-of-range interval (F04 fix round 1).
    public func elapsed(at now: Date) -> Duration {
        .seconds(min(max(0, (endedAt ?? now).timeIntervalSince(startedAt)), Double(Int64.max)))
    }
}
