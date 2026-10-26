import Foundation

/// How a custom exercise's name is cleaned before its rules (F12 S3, N15 and the orchestrator's ruling on findings
/// S3-1 to S3-4): the name is stored as it draws, so two names that draw alike are one name to the duplicate rule,
/// and a name that draws nothing is blank. `ExerciseSearch.key` is left as it is: F11's search shares it.
public extension CustomExerciseDraft {
    /// The most Unicode scalars a name may hold (S3-4). Forty characters is the rule the lifter reads; a character can
    /// carry any number of combining marks, and a few hundred of them on two letters draw a smear over the rows around
    /// them. 160 is four scalars a character, room for every script's marks and for emoji sequences.
    static let nameScalars = 160

    /// The name as it is stored and compared: trimmed of blanks, line breaks and characters that draw nothing at either
    /// end; each character that draws nothing dropped from inside it (a zero-width space, a word joiner, a byte order
    /// mark, a direction mark, a joiner between anything but two emoji); every kind of space (Unicode `Zs`: a no-break
    /// space, a thin space) a plain space, and every run of spaces one. A joiner inside an emoji sequence and a
    /// selector that belongs to its character are kept, and so is a direction override, which the rules refuse.
    var storedName: String {
        let source = Array(name.unicodeScalars)
        var scalars = String.UnicodeScalarView()
        var isAfterSpace = false
        for (place, scalar) in source.enumerated() {
            let isKept = scalar == "\u{200D}" ? Self.joinsEmoji(source, at: place) : !Self.drawsNothingAlone(scalar)
            guard isKept else {
                continue
            }
            let isSpace = scalar.properties.generalCategory == .spaceSeparator
            if isSpace, isAfterSpace {
                continue
            }
            scalars.append(isSpace ? " " : scalar)
            isAfterSpace = isSpace
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the name draws nothing (S3-1): its stored form holds only blanks and characters that draw nothing (the
    /// direction controls and selectors `storedName` keeps). One reading of "draws nothing", `storedName`'s (review
    /// F12-S3-R1-6).
    internal var drawsNothing: Bool {
        storedName.unicodeScalars.allSatisfy { $0.properties.isDefaultIgnorableCodePoint || $0.properties.isWhitespace }
    }

    /// A character that draws nothing and belongs to no other: default-ignorable, but neither a selector that extends
    /// the character before it nor a direction control, which `isRefused` keeps for its rule. The zero-width joiner is
    /// `joinsEmoji`'s.
    internal static func drawsNothingAlone(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isDefaultIgnorableCodePoint && !scalar.properties.isGraphemeExtend
            && !isDirectionControl(scalar)
    }

    /// Whether the zero-width joiner at `place` joins two emoji, as in an emoji sequence (👩‍🦰, 🏋️‍♂️): the scalar
    /// before it, past the selectors and skin tones that extend it, and the scalar after it are emoji. Anywhere else
    /// it draws nothing and is dropped (review F12-S3-R1-1). ASCII digits, "#" and "*" are not emoji here.
    internal static func joinsEmoji(_ scalars: [Unicode.Scalar], at place: Int) -> Bool {
        var before = place - 1
        while before >= 0, scalars[before].properties.isGraphemeExtend || scalars[before].properties.isEmojiModifier {
            before -= 1
        }
        let after = place + 1
        return before >= 0 && after < scalars.count && isEmoji(scalars[before]) && isEmoji(scalars[after])
    }

    private static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && !scalar.isASCII
    }

    /// What a stored name never holds (S3-1, S3-3): a control character (`Cc`, U+0000 among them), a line or paragraph
    /// separator (`Zl`, `Zp`), a direction embedding, override or isolate (they reorder what is drawn: U+202E spells a
    /// name backwards), or any other format character (`Cf`) that draws something.
    internal static func isRefused(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            true
        case .format:
            isDirectionControl(scalar) || !scalar.properties.isDefaultIgnorableCodePoint
        default:
            false
        }
    }

    /// U+202A–U+202E (embeddings and overrides) and U+2066–U+2069 (isolates).
    private static func isDirectionControl(_ scalar: Unicode.Scalar) -> Bool {
        (0x202A ... 0x202E).contains(scalar.value) || (0x2066 ... 0x2069).contains(scalar.value)
    }
}
