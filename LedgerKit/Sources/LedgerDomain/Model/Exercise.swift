import Foundation

/// Equipment taxonomy (spec §6.1 plus kettlebell and band from decision #12).
public enum Equipment: String, Codable, Sendable, CaseIterable {
    case barbell, dumbbell, cable, machine, bodyweight, kettlebell, band

    /// Rule 1 / decision #9, amended by #22 (Pete, 2026-09-30): lb — barbell and kettlebell 5, everything
    /// else 2.5; kg — barbell 2.5, kettlebell 2 (the gap between bell sizes), everything else 1.25.
    public func defaultStep(in units: Units) -> Weight {
        switch (units, self) {
        case (.lb, .barbell), (.lb, .kettlebell): .pounds(5)
        case (.lb, _): .pounds(2.5)
        case (.kg, .barbell): .kilograms(2.5)
        case (.kg, .kettlebell): .kilograms(2)
        case (.kg, _): .kilograms(1.25)
        }
    }
}

/// Primary and secondary muscle groups (decision #12: finer than the prototype's five).
public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case chest, back, shoulders, quads, hamstrings, glutes, calves, biceps, triceps, forearms, core
}

/// Movement pattern, used to pick swap alternatives (decision #13).
public enum MovementPattern: String, Codable, Sendable, CaseIterable {
    case horizontalPush, horizontalPull, verticalPush, verticalPull, squat, hinge, lunge, carry, isolation, core
}

/// A catalog or custom exercise (spec §6.1 "Exercise (catalog)", decision #12).
public struct Exercise: Identifiable, Hashable, Codable, Sendable {
    public let id: ExerciseID
    public var name: String
    public var shortName: String
    public var equipment: Equipment
    public var primaryMuscle: MuscleGroup
    public var secondaryMuscles: [MuscleGroup]
    public var pattern: MovementPattern
    /// Spec §6.2 `W0`: the starting load per unit.
    public var defaultStartLoad: [Units: Weight]
    public var isCustom: Bool
    public var curatedAlternatives: [ExerciseID]

    public init(
        id: ExerciseID,
        name: String,
        shortName: String,
        equipment: Equipment,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [MuscleGroup] = [],
        pattern: MovementPattern,
        defaultStartLoad: [Units: Weight],
        isCustom: Bool = false,
        curatedAlternatives: [ExerciseID] = []
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles
        self.pattern = pattern
        self.defaultStartLoad = defaultStartLoad
        self.isCustom = isCustom
        self.curatedAlternatives = curatedAlternatives
    }

    /// Spec §7.2 `start = slot.load ?? W0[slot]`: the catalog start load in `units`. When only the
    /// other unit is known it is converted and rounded to this unit's default step; with no
    /// start load at all it is zero.
    public func startLoad(in units: Units) -> Weight {
        if let load = defaultStartLoad[units] {
            return load
        }
        guard let other = Units.allCases.lazy.compactMap({ defaultStartLoad[$0] }).first else {
            return .zero
        }
        return other.rounded(toStep: equipment.defaultStep(in: units))
    }
}
