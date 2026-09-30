import Foundation
@testable import LedgerDomain

/// The conservative start-load policy (decision #21, Pete 2026-09-30) as an oracle for
/// `ExerciseCatalogTests`: the lb and kg start load a catalog exercise must have, from its
/// equipment, its pattern and, for four classes, its name. `ExerciseCatalog`'s doc comment holds the
/// same table for readers.
enum StartLoadPolicy {
    struct Load: Equatable {
        let lb: Decimal
        let kg: Decimal

        init(_ lb: Decimal, _ kg: Decimal) {
            self.lb = lb
            self.kg = kg
        }
    }

    enum LoadClass {
        case compound, isolation, small, floorPull, landmine, kettlebellUpper, weighted
    }

    /// Deadlift-family pulls from the floor or pins: the bar needs plates to reach pulling height.
    static let floorPulls: Set = ["Deadlift", "Sumo Deadlift", "Trap Bar Deadlift", "Rack Pull"]
    /// Landmine lifts count the plates only.
    static let landmine: Set = ["T-Bar Row", "Meadows Row", "Landmine Press", "Landmine Rotation"]
    /// Delt raises and flies, rotator-cuff rotations, kickbacks, cable hip abduction, dumbbell wrist curls.
    static let small: Set = [
        "Dumbbell Lateral Raise", "Dumbbell Front Raise", "Dumbbell Rear Delt Fly", "Dumbbell Kickback",
        "Dumbbell Wrist Curl", "Dumbbell Reverse Wrist Curl", "Cable Lateral Raise", "Cable Front Raise",
        "Cable Rear Delt Fly", "Cable External Rotation", "Cable Triceps Kickback", "Cable Glute Kickback",
        "Cable Hip Abduction", "Machine Lateral Raise", "Rear Delt Fly", "Band Pull-Apart", "Band External Rotation"
    ]
    /// Kettlebell upper-body, overhead and get-up work takes the lighter bell.
    static let kettlebellUpper: Set = [
        "Kettlebell Overhead Press", "Kettlebell Row", "Kettlebell Floor Press", "Kettlebell Clean",
        "Kettlebell Snatch", "Turkish Get-Up", "Kettlebell Windmill"
    ]

    static func loadClass(of exercise: Exercise) -> LoadClass {
        if floorPulls.contains(exercise.name) {
            return .floorPull
        }
        if landmine.contains(exercise.name) {
            return .landmine
        }
        if small.contains(exercise.name) {
            return .small
        }
        if kettlebellUpper.contains(exercise.name) {
            return .kettlebellUpper
        }
        if exercise.equipment == .bodyweight, exercise.name.hasPrefix("Weighted ") {
            return .weighted
        }
        return [.isolation, .core].contains(exercise.pattern) ? .isolation : .compound
    }

    /// The policy, row by row as in `ExerciseCatalog`'s doc comment.
    static let table: [Equipment: [LoadClass: Load]] = [
        .barbell: [.compound: Load(45, 20), .isolation: Load(25, 10), .floorPull: Load(95, 40), .landmine: Load(10, 5)],
        .dumbbell: [.compound: Load(15, 7.5), .isolation: Load(10, 5), .small: Load(5, 2.5)],
        .cable: [.compound: Load(30, 15), .isolation: Load(20, 10), .small: Load(10, 5)],
        .machine: [.compound: Load(40, 20), .isolation: Load(20, 10), .small: Load(10, 5)],
        .kettlebell: [.compound: Load(25, 12), .kettlebellUpper: Load(15, 8)],
        .band: [.compound: Load(20, 10), .isolation: Load(10, 5), .small: Load(5, 2.5)],
        .bodyweight: [.compound: Load(0, 0), .isolation: Load(0, 0), .weighted: Load(10, 5)]
    ]

    /// The policy's start load, or nil when the table has no cell for the exercise's class.
    static func startLoad(for exercise: Exercise) -> Load? {
        table[exercise.equipment]?[loadClass(of: exercise)]
    }
}
