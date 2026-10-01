import Foundation

/// How exercises are searched and ordered (Pete, 2026-09-30; product decision #23), as one rule for every
/// caller: `ExerciseRepository.search` and its name order (F05), the Library's pills filtering `observeAll()` in
/// memory (F12), and the in-memory fakes (F07).
///
/// Text is compared as its `key`: trimmed, and folded so that case and diacritics never matter ("Élévation" and
/// "elevation" are one key). The folding is the same in every locale, so results do not depend on the device's
/// language.
public enum ExerciseSearch {
    /// `text` trimmed of blanks and folded: the form every match and every name comparison uses.
    public static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
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
