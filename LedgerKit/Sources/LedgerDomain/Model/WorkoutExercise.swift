import Foundation

/// One exercise in a live or finished workout (spec §6.1 "Session exercise").
///
/// Rule 16: rest, step, RPE, equipment, superset flag and targets are copied from the slot at
/// build time, so later template edits never alter a live session.
public struct WorkoutExercise: Identifiable, Hashable, Codable, Sendable {
    public let id: WorkoutExerciseID
    /// `nil` for exercises that did not come from a program slot.
    public var slotID: SlotID?
    /// The exercise performed (changes on swap, rule 27).
    public var exerciseID: ExerciseID
    /// The exercise the slot prescribed.
    public let originalExerciseID: ExerciseID
    public var name: String
    public var equipment: Equipment
    public var step: Weight
    public var rest: RestDuration
    public var rpe: RPE
    public var isSupersetWithPrevious: Bool
    public var targetSets: Int
    public var targetReps: Int
    public var targetLoad: Weight
    public var sets: [LoggedSet]
    public var lastPerformance: LastPerformance?

    public init(
        id: WorkoutExerciseID,
        slotID: SlotID?,
        exerciseID: ExerciseID,
        originalExerciseID: ExerciseID,
        name: String,
        equipment: Equipment,
        step: Weight,
        rest: RestDuration,
        rpe: RPE,
        isSupersetWithPrevious: Bool,
        targetSets: Int,
        targetReps: Int,
        targetLoad: Weight,
        sets: [LoggedSet],
        lastPerformance: LastPerformance? = nil
    ) {
        self.id = id
        self.slotID = slotID
        self.exerciseID = exerciseID
        self.originalExerciseID = originalExerciseID
        self.name = name
        self.equipment = equipment
        self.step = step
        self.rest = rest
        self.rpe = rpe
        self.isSupersetWithPrevious = isSupersetWithPrevious
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetLoad = targetLoad
        self.sets = sets
        self.lastPerformance = lastPerformance
    }
}
