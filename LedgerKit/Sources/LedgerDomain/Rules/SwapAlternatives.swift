import Foundation

/// What a swap offers and what the chosen exercise brings (F10 S8; decision #13 as amended by the S8 rulings).
/// Pure and total: any catalog, any exercise, any history.
public enum SwapAlternatives {
    /// The most alternatives a swap offers.
    public static let limit = 8

    /// The alternatives to `exercise` in `catalog`, best first: its curated alternatives in their listed order
    /// (those the catalog holds), then the exercises with its movement pattern and primary muscle in name order
    /// (`ExerciseSearch.isInNameOrder`); each once, never `exercise` itself nor an id in `excluding` (the
    /// workout's other exercises, Q9), and at most `limit`. No tier offers "same muscle, any pattern" (Q3).
    public static func ranked(
        for exercise: Exercise,
        in catalog: [Exercise],
        excluding: Set<ExerciseID> = []
    ) -> [Exercise] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }) { first, _ in first }
        let curated = exercise.curatedAlternatives.compactMap { byID[$0] }
        let similar = ExerciseSearch.sorted(catalog.filter { candidate in
            candidate.pattern == exercise.pattern && candidate.primaryMuscle == exercise.primaryMuscle
        })
        var seen = excluding.union([exercise.id])
        var ranked: [Exercise] = []
        for candidate in curated + similar {
            guard ranked.count < limit else {
                break
            }
            if seen.insert(candidate.id).inserted {
                ranked.append(candidate)
            }
        }
        return ranked
    }

    /// What `exercise` brings when it replaces `current` in a workout in `units` (criterion 3): its equipment,
    /// its default step in `units` (decision #22), `last` as its "Last" line, and the load its undone sets take:
    /// `last`'s load when it was done before; else, with the same equipment as `current`, `current`'s target
    /// load; else its catalog start load (Q1). The load is rounded to the step and never below zero.
    ///
    /// Bench 185 lb → Incline Bench (barbell), never done: 185; → Dumbbell Bench, never done: its start, 15;
    /// → Dumbbell Bench, last done at 60: 60.
    public static func replacement(
        of current: WorkoutExercise,
        with exercise: Exercise,
        last: LastPerformance?,
        units: Units
    ) -> SwappedExercise {
        let step = exercise.equipment.defaultStep(in: units)
        let base = if let last {
            last.load
        } else if exercise.equipment == current.equipment {
            current.targetLoad
        } else {
            exercise.startLoad(in: units)
        }
        return SwappedExercise(
            equipment: exercise.equipment,
            step: step,
            load: max(base.rounded(toStep: step), .zero),
            lastPerformance: last
        )
    }
}
