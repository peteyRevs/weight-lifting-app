import Foundation
@testable import LedgerDomain
import Testing

/// F12 S3, N15 over random Unicode names: whatever the lifter types or pastes, a draft either builds an exercise
/// that keeps every rule, or names the first rule the name breaks, as a plain reading of the rules says.
@Suite("CustomExerciseDraft · random names", .tags(.domain))
struct CustomExerciseDraftPropertyTests {
    /// What a name is made of: letters of several scripts, combining marks, fullwidth forms, emoji and their
    /// joiners, blanks of several kinds, line breaks, and control characters (U+0000 among them).
    static let pieces: [String] = [
        "a", "Z", "é", "e\u{301}", "ß", "ı", "Ø", "Ж", "ж", "α", "ب", "א", "日", "한", "ｒ", "Ｒ", "5", "-", "'", "·",
        "\u{301}", "\u{308}", "🏋️", "👩🏽‍🦰", "🇫🇷", "\u{200D}", "\u{FE0F}",
        " ", "  ", "\u{A0}", "\u{2003}", "\u{3000}", "\n", "\r\n", "\u{2028}",
        "\u{0}", "\t", "\u{7}", "\u{1B}", "\u{7F}", "\u{85}", "\u{9F}"
    ]

    static let live = [
        Exercise(
            id: ExerciseID(Fixtures.uuid(7201)), name: "Ab", shortName: "Ab", equipment: .cable,
            primaryMuscle: .core, pattern: .core, defaultStartLoad: [:]
        ),
        Exercise(
            id: ExerciseID(Fixtures.uuid(7202)), name: "Élan", shortName: "Élan", equipment: .barbell,
            primaryMuscle: .chest, pattern: .horizontalPush, defaultStartLoad: [:]
        )
    ]

    static func name(using generator: inout SeededGenerator) -> String {
        let count = Int.random(in: 0 ... 30, using: &generator)
        return (0 ..< count).map { _ in pieces.randomElement(using: &generator) ?? "" }.joined()
    }

    /// The rule read plainly, apart from the code: what the draft must answer for `name`.
    static func expected(for name: String) -> CustomExerciseError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .blankName
        }
        if trimmed.count < 2 || trimmed.count > 40 {
            return .nameLength(trimmed.count)
        }
        if trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            return .controlCharacter
        }
        if let other = live.first(where: { ExerciseSearch.key($0.name) == ExerciseSearch.key(trimmed) }) {
            return .duplicateName(other.id)
        }
        return nil
    }

    @Test(
        "A random name builds an exercise that keeps every rule, or is refused for the first it breaks",
        arguments: PropertySeed.all
    )
    func randomName_keepsTheRules(_ seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 20 {
            let name = Self.name(using: &generator)
            let draft = CustomExerciseDraft(name: name, primaryMuscle: .back, secondaryMuscles: [.biceps])
            let id = ExerciseID(Fixtures.uuid(7300))
            do {
                let built = try draft.exercise(id: id, among: Self.live)
                let isKept = Self.expected(for: name) == nil
                    && built.name == built.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    && CustomExerciseDraft.nameLength.contains(built.name.count)
                    && !built.name.unicodeScalars.contains("\u{0}")
                    && built.shortName == built.name && built.isCustom
                #expect(isKept, "\(seed): \(name.unicodeScalars.map(\.value))")
                // The stored name, edited again unchanged, is the same exercise.
                let again = try CustomExerciseDraft(built).exercise(id: id, among: Self.live + [built])
                #expect(again == built, "\(seed): \(name.unicodeScalars.map(\.value))")
            } catch {
                #expect(error == Self.expected(for: name), "\(seed): \(name.unicodeScalars.map(\.value))")
            }
        }
    }
}
