import Foundation
import LedgerDomain

/// F03 criterion 8: the inputs for F05's `seedIfNeeded(_:version:)` contract test (F05 criterion 11).
/// The contract test itself lives in F05.
///
/// The scenario these values support:
/// 1. Seed `base()`: one row per catalog exercise.
/// 2. Save `custom`, the lifter's own exercise, then seed `base()` again at the same version: no
///    new rows, and `custom` is untouched.
/// 3. Seed `upgrade()`, one version higher: `added` is inserted. `clash` is a new catalog entry
///    named like `custom` in another case, so "existing names are not duplicated" means it is not
///    inserted, and `custom` is still untouched.
public enum CatalogSeedFixture {
    /// A catalog as `seedIfNeeded` receives it.
    public struct Catalog: Equatable, Sendable {
        public let version: Int
        public let exercises: [Exercise]
    }

    /// The bundled catalog at `ExerciseCatalog.version`.
    public static func base() throws -> Catalog {
        try Catalog(version: ExerciseCatalog.version, exercises: ExerciseCatalog.seed())
    }

    /// `base()` plus `added` and `clash`, one version higher: an additive upgrade.
    public static func upgrade() throws -> Catalog {
        let base = try base()
        return Catalog(version: base.version + 1, exercises: base.exercises + [added, clash])
    }

    /// A custom exercise the lifter created before any upgrade. No catalog entry has its name.
    public static let custom = Exercise(
        id: ExerciseID(EventBuilders.uuid(0xCA01)),
        name: "Zercher Squat",
        shortName: "ZERCHER",
        equipment: .barbell,
        primaryMuscle: .quads,
        secondaryMuscles: [.glutes, .core],
        pattern: .squat,
        defaultStartLoad: [.lb: .pounds(95), .kg: .kilograms(42.5)],
        isCustom: true
    )

    /// A new catalog entry in `upgrade()`, with a name no row has.
    public static let added = Exercise(
        id: ExerciseID(EventBuilders.uuid(0xCA02)),
        name: "Cossack Squat",
        shortName: "COSSACK",
        equipment: .bodyweight,
        primaryMuscle: .quads,
        secondaryMuscles: [.glutes],
        pattern: .lunge,
        defaultStartLoad: [.lb: .zero, .kg: .zero]
    )

    /// A new catalog entry in `upgrade()` whose name equals `custom`'s ignoring case.
    public static let clash = Exercise(
        id: ExerciseID(EventBuilders.uuid(0xCA03)),
        name: "ZERCHER SQUAT",
        shortName: "ZERCHER",
        equipment: .barbell,
        primaryMuscle: .quads,
        secondaryMuscles: [.glutes],
        pattern: .squat,
        defaultStartLoad: [.lb: .pounds(95), .kg: .kilograms(42.5)]
    )
}
