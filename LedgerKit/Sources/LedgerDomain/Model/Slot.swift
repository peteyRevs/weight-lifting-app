import Foundation

/// How a slot's load and reps move week to week (spec §7.2, rules 9–11).
public enum Progression: String, Codable, Sendable, CaseIterable {
    case linear, double, fixed
}

/// One exercise in a day template (spec §6.1 "Exercise slot").
///
/// Ranges are validated at construction and on decoding (engineering-standards §5); the
/// `var` properties are for editors that rebuild through `init` when they change a ranged value.
public struct Slot: Identifiable, Hashable, Codable, Sendable {
    public let id: SlotID
    public var exerciseID: ExerciseID
    /// Rule 3: 1…12.
    public var sets: Int
    /// Rule 2: 1…30.
    public var reps: Int
    /// Rule 2: 2…40 and > `reps` (top of the double-progression range).
    public var repsHi: Int
    public var rpe: RPE
    public var rest: RestDuration
    public var progression: Progression
    /// `nil` → `exercise.startLoad(in: units)` (spec §7.2 `slot.load ?? W0`).
    public var startLoad: Weight?
    /// `nil` → `exercise.equipment.defaultStep(in: units)` (rule 1).
    public var step: Weight?
    public var isSupersetWithPrevious: Bool
    /// 0 or 1 (spec §6.1 `drop`).
    public var dropSets: Int
    /// Week indices in which this slot was missed (rule 13, decision #5).
    public var misses: Set<Int>

    /// Validates rules 1–3 and 6 and throws the first violated range, checked in this order:
    /// sets, reps, repsHi, repsHi > reps, rpe, rest, drop sets, start load, step.
    public init(
        id: SlotID,
        exerciseID: ExerciseID,
        sets: Int,
        reps: Int,
        repsHi: Int,
        rpe: Decimal,
        restSeconds: Int,
        progression: Progression,
        startLoad: Weight? = nil,
        step: Weight? = nil,
        isSupersetWithPrevious: Bool = false,
        dropSets: Int = 0,
        misses: Set<Int> = []
    ) throws(SlotValidationError) {
        try Self.validate(sets: sets, reps: reps, repsHi: repsHi)
        guard let validRPE = RPE(rpe) else {
            throw .rpeOutOfRange(rpe)
        }
        guard let validRest = RestDuration(seconds: restSeconds) else {
            throw .restOutOfRange(seconds: restSeconds)
        }
        try Self.validate(dropSets: dropSets, startLoad: startLoad, step: step)
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.repsHi = repsHi
        self.rpe = validRPE
        rest = validRest
        self.progression = progression
        self.startLoad = startLoad
        self.step = step
        self.isSupersetWithPrevious = isSupersetWithPrevious
        self.dropSets = dropSets
        self.misses = misses
    }

    private static func validate(sets: Int, reps: Int, repsHi: Int) throws(SlotValidationError) {
        guard (1 ... 12).contains(sets) else {
            throw .setsOutOfRange(sets)
        }
        guard (1 ... 30).contains(reps) else {
            throw .repsOutOfRange(reps)
        }
        guard (2 ... 40).contains(repsHi) else {
            throw .repsHiOutOfRange(repsHi)
        }
        guard repsHi > reps else {
            throw .repsHiNotAboveReps(reps: reps, repsHi: repsHi)
        }
    }

    private static func validate(dropSets: Int, startLoad: Weight?, step: Weight?) throws(SlotValidationError) {
        guard (0 ... 1).contains(dropSets) else {
            throw .dropSetsOutOfRange(dropSets)
        }
        if let startLoad, startLoad < .zero {
            throw .negativeStartLoad(startLoad)
        }
        if let step, step <= .zero {
            throw .nonPositiveStep(step)
        }
    }
}

// MARK: - Codable (re-validates)

extension Slot {
    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, sets, reps, repsHi, rpe, rest, progression, startLoad, step
        case isSupersetWithPrevious, dropSets, misses
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(SlotID.self, forKey: .id),
            exerciseID: container.decode(ExerciseID.self, forKey: .exerciseID),
            sets: container.decode(Int.self, forKey: .sets),
            reps: container.decode(Int.self, forKey: .reps),
            repsHi: container.decode(Int.self, forKey: .repsHi),
            rpe: container.decode(RPE.self, forKey: .rpe).value,
            restSeconds: container.decode(RestDuration.self, forKey: .rest).seconds,
            progression: container.decode(Progression.self, forKey: .progression),
            startLoad: container.decodeIfPresent(Weight.self, forKey: .startLoad),
            step: container.decodeIfPresent(Weight.self, forKey: .step),
            isSupersetWithPrevious: container.decode(Bool.self, forKey: .isSupersetWithPrevious),
            dropSets: container.decode(Int.self, forKey: .dropSets),
            misses: container.decode(Set<Int>.self, forKey: .misses)
        )
    }
}
