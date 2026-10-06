import Foundation

/// How exercises are searched and ordered (Pete, 2026-09-30; product decision #23), as one rule for every
/// caller: `ExerciseRepository.search` and its name order (F05), the Library's pills filtering `observeAll()` in
/// memory (F12), and the in-memory fakes (F07).
///
/// Text is compared as its `key`: folded so that case, diacritics and width never matter ("Élévation",
/// "elevation" and fullwidth "ＥＬＥＶＡＴＩＯＮ" are one key), then trimmed. The folding is Foundation's, the
/// same in every locale, so results do not depend on the device's language; letters that are not a base letter
/// plus a mark, such as "ı" and "Ø", stay themselves.
public enum ExerciseSearch {
    /// `text` folded, then trimmed of blanks: the form every match and every name comparison uses. Trimming
    /// last also removes a blank that folding uncovers (a blank carrying a combining mark).
    public static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `exercise`'s name or short name contains `query`. A blank query matches every exercise.
    public static func matches(_ exercise: Exercise, query: String) -> Bool {
        matches(name: exercise.name, shortName: exercise.shortName, needle: key(query))
    }

    /// `matches(_:query:)` for text not yet decoded into an `Exercise`, with the query already a `key`, so a
    /// caller that filters many exercises folds the query once.
    public static func matches(name: String, shortName: String, needle: String) -> Bool {
        needle.isEmpty || key(name).contains(needle) || key(shortName).contains(needle)
    }

    /// Name order, the order of `all()`, `search` and `observeAll()`: by the name's `key`, then by id, so
    /// exercises with equal keys keep one order.
    public static func isInNameOrder(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        sortKey(lhs) < sortKey(rhs)
    }

    /// `exercises` in name order, each name folded once rather than once per comparison.
    public static func sorted(_ exercises: [Exercise]) -> [Exercise] {
        exercises
            .map { (key: sortKey($0), exercise: $0) }
            .sorted { $0.key < $1.key }
            .map(\.exercise)
    }

    /// The name's key, then the id.
    private static func sortKey(_ exercise: Exercise) -> (String, String) {
        (key(exercise.name), exercise.id.rawValue.uuidString)
    }
}

// MARK: - The exercise library's filter (F11 criterion 12, F12)

public extension ExerciseSearch {
    /// A muscle chip of the exercise library. The chips are coarser than `MuscleGroup`: "Legs" and "Arms"
    /// each stand for several groups, and no chip stands for the core (those exercises are found under "All"
    /// and by name).
    enum MuscleFilter: Hashable, Sendable, CaseIterable {
        case chest, back, shoulders, legs, arms

        /// The muscle groups the chip stands for.
        public var groups: Set<MuscleGroup> {
            switch self {
            case .chest: [.chest]
            case .back: [.back]
            case .shoulders: [.shoulders]
            case .legs: [.quads, .hamstrings, .glutes, .calves]
            case .arms: [.biceps, .triceps, .forearms]
            }
        }
    }

    /// The library's rows: the exercises whose primary muscle is one of the chip's groups, whose equipment
    /// is the one asked for, and whose name or short name contains `query` (decision #23), in name order.
    /// `nil` for a chip is "All", and a blank query matches every exercise. The query is folded once.
    static func filter(
        _ exercises: [Exercise],
        query: String,
        muscle: MuscleFilter?,
        equipment: Equipment?
    ) -> [Exercise] {
        let needle = key(query)
        let groups = muscle?.groups
        return sorted(exercises.filter { exercise in
            groups?.contains(exercise.primaryMuscle) != false
                && (equipment == nil || equipment == exercise.equipment)
                && matches(name: exercise.name, shortName: exercise.shortName, needle: needle)
        })
    }
}
