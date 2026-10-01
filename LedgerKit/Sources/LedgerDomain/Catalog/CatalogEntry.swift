import Foundation

/// One object in `Resources/exercises.json`, as written (F03 brief, "JSON schema").
///
/// Every key is required except `loadKind`, so a misspelt key fails decoding instead of being
/// ignored. A misspelt `loadKind` is still caught: its zero load then fails `exercise()`. A key the
/// schema does not have (a per-exercise `"step"`, say) is ignored, and a key written twice keeps one
/// value; the data tests scan the bundled file for both (F03 test findings, finding 1).
struct CatalogEntry: Decodable, Sendable {
    /// The start load per unit, as exact decimals (`JSONDecoder` reads a `Decimal` from the digits).
    struct StartLoad: Decodable, Sendable {
        let lb: Decimal
        let kg: Decimal
    }

    /// The only value: the lifter's body is the whole load, so the start load is zero. Bodyweight
    /// exercises with added load (Weighted Dip) omit it and give the added load instead.
    enum LoadKind: String, Decodable, Sendable {
        case bodyweight
    }

    let id: ExerciseID
    let name: String
    let shortName: String
    let equipment: Equipment
    let primaryMuscle: MuscleGroup
    let secondaryMuscles: [MuscleGroup]
    let pattern: MovementPattern
    let startLoad: StartLoad
    let loadKind: LoadKind?
    let alternatives: [ExerciseID]
    /// Other names lifters use. They only guard against duplicate entries (criterion 4): search
    /// matches name and short name only, and aliases are neither stored nor searched (decision #23).
    let aliases: [String]

    /// The catalog `Exercise`, after the checks that need only this entry. The checks across
    /// entries (unique ids and names, alternatives that resolve) are in `ExerciseCatalog`.
    func exercise() throws -> Exercise {
        for text in [name, shortName] + aliases {
            guard !text.isEmpty, text == text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw CatalogError.invalidText(id)
            }
        }
        guard !secondaryMuscles.contains(primaryMuscle), Set(secondaryMuscles).count == secondaryMuscles.count else {
            throw CatalogError.invalidMuscles(id)
        }
        let loads: [(Units, Weight)] = [(.lb, .pounds(startLoad.lb)), (.kg, .kilograms(startLoad.kg))]
        for (units, load) in loads {
            guard load >= .zero, load.rounded(toStep: equipment.defaultStep(in: units)) == load else {
                throw CatalogError.invalidStartLoad(id, units)
            }
        }
        let isBodyweight = loadKind == .bodyweight
        guard (startLoad.lb == 0) == (startLoad.kg == 0), isBodyweight == (startLoad.lb == 0),
              !isBodyweight || equipment == .bodyweight
        else {
            throw CatalogError.loadKindMismatch(id)
        }
        guard alternatives.count >= 2, !alternatives.contains(id), Set(alternatives).count == alternatives.count else {
            throw CatalogError.invalidAlternatives(id)
        }
        return Exercise(
            id: id,
            name: name,
            shortName: shortName,
            equipment: equipment,
            primaryMuscle: primaryMuscle,
            secondaryMuscles: secondaryMuscles,
            pattern: pattern,
            defaultStartLoad: Dictionary(uniqueKeysWithValues: loads),
            curatedAlternatives: alternatives
        )
    }
}
