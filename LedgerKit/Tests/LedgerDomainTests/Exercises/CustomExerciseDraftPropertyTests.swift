import Foundation
@testable import LedgerDomain
import Testing

/// F12 S3, N15 over random Unicode names: whatever the lifter types or pastes, a draft either builds an exercise
/// that keeps every rule, or names the first rule the name breaks, as a plain reading of the rules says (with the
/// stored name's cleaning ruled in S3 fix round 1: characters that draw nothing, kinds and runs of spaces).
@Suite("CustomExerciseDraft · random names", .tags(.domain))
struct CustomExerciseDraftPropertyTests {
    /// What a name is made of: letters of several scripts, combining marks, fullwidth forms, emoji and their
    /// joiners, blanks of several kinds, line breaks, and control characters (U+0000 among them).
    static let pieces: [String] = [
        "a", "Z", "é", "e\u{301}", "ß", "ı", "Ø", "Ж", "ж", "α", "ب", "א", "日", "한", "ｒ", "Ｒ", "5", "-", "'", "·",
        "\u{301}", "\u{308}", "🏋️", "👩🏽‍🦰", "🇫🇷", "\u{200D}", "\u{FE0F}",
        " ", "  ", "\u{A0}", "\u{2003}", "\u{2009}", "\u{3000}", "\n", "\r\n", "\u{2028}", "\u{2029}",
        "\u{200B}", "\u{2060}", "🏋️", "\u{200D}", "♂️", "\u{FEFF}", "\u{200E}", "\u{202E}", "\u{2066}", "\u{3164}",
        "\u{600}",
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

    /// The scalars the stored name keeps before its spaces are cleaned: none that draws nothing alone, and a joiner
    /// only between two emoji (review F12-S3-R1-1), selectors and skin tones before it skipped.
    static func keptScalars(of name: String, directions: Set<UInt32>) -> [Unicode.Scalar] {
        let all = Array(name.unicodeScalars)
        // A joiner stays only between two emoji (review F12-S3-R1-1); selectors and skin tones before it are skipped.
        let isEmoji = { (scalar: Unicode.Scalar) in scalar.properties.isEmoji && scalar.value > 0x7F }
        let joins = { (place: Int) -> Bool in
            let before = all[..<place].lastIndex {
                !($0.properties.isGraphemeExtend || $0.properties.isEmojiModifier)
            }
            guard let before, place + 1 < all.count else {
                return false
            }
            return isEmoji(all[before]) && isEmoji(all[place + 1])
        }
        return all.indices.filter { place in
            let scalar = all[place]
            if scalar == "\u{200D}" {
                return joins(place)
            }
            return !scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isGraphemeExtend
                || directions.contains(scalar.value)
        }
        .map { all[$0] }
    }

    /// The rule read plainly, apart from the code: what the draft must answer for `name`, and the name it stores.
    static func expected(for name: String) -> (error: CustomExerciseError?, stored: String) {
        let directions: Set<UInt32> = [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
        let visible = String(String.UnicodeScalarView(name.unicodeScalars.filter {
            !$0.properties.isDefaultIgnorableCodePoint
        }))
        let kept = keptScalars(of: name, directions: directions)
        // Spaces are collapsed by scalar: a space under a combining mark is still a space before it.
        let spaced = kept.map { $0.properties.generalCategory == .spaceSeparator ? " " : $0 }
        let collapsed = spaced.indices.filter { $0 == 0 || !(spaced[$0] == " " && spaced[$0 - 1] == " ") }
            .map { spaced[$0] }
        let stored = String(String.UnicodeScalarView(collapsed)).trimmingCharacters(in: .whitespacesAndNewlines)
        if visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (.blankName, stored)
        }
        if stored.count < 2 || stored.count > 40 || stored.unicodeScalars.count > 160 {
            return (.nameLength(stored.count), stored)
        }
        let refused = stored.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: true
            case .format: directions.contains(scalar.value) || !scalar.properties.isDefaultIgnorableCodePoint
            default: false
            }
        }
        if refused {
            return (.controlCharacter, stored)
        }
        if let other = live.first(where: { ExerciseSearch.key($0.name) == ExerciseSearch.key(stored) }) {
            return (.duplicateName(other.id), stored)
        }
        return (nil, stored)
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
                let expected = Self.expected(for: name)
                let isKept = expected.error == nil && built.name == expected.stored
                    && built.name == built.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    && CustomExerciseDraft.nameLength.contains(built.name.count)
                    && built.name.unicodeScalars.count <= 160
                    && !built.name.unicodeScalars.contains("\u{0}")
                    && built.shortName == built.name && built.isCustom
                #expect(isKept, "\(seed): \(name.unicodeScalars.map(\.value))")
                // The stored name, edited again unchanged, is the same exercise.
                let again = try CustomExerciseDraft(built).exercise(id: id, among: Self.live + [built])
                #expect(again == built, "\(seed): \(name.unicodeScalars.map(\.value))")
            } catch {
                #expect(error == Self.expected(for: name).error, "\(seed): \(name.unicodeScalars.map(\.value))")
            }
        }
    }
}
