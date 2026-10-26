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
    /// mark, a direction mark); every kind of space (Unicode `Zs`: a no-break space, a thin space) a plain space, and
    /// every run of spaces one. A joiner or a selector that belongs to its character (an emoji sequence, a script's
    /// shaping) is kept, and so is a direction override, which the rules refuse.
    var storedName: String {
        var scalars = String.UnicodeScalarView()
        var isAfterSpace = false
        for scalar in name.unicodeScalars where !Self.drawsNothingAlone(scalar) {
            let isSpace = scalar.properties.generalCategory == .spaceSeparator
            if isSpace, isAfterSpace {
                continue
            }
            scalars.append(isSpace ? " " : scalar)
            isAfterSpace = isSpace
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `name` draws nothing: once every character Unicode says draws nothing (default-ignorable) is taken out,
    /// only blanks and line breaks are left (S3-1).
    internal static func drawsNothing(_ name: String) -> Bool {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: name.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A character that draws nothing and belongs to no other: default-ignorable, but neither a joiner nor a selector
    /// that extends the character before it, nor a direction control, which `isRefused` keeps for its rule.
    internal static func drawsNothingAlone(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isDefaultIgnorableCodePoint && !scalar.properties.isGraphemeExtend
            && scalar != "\u{200D}" && !isDirectionControl(scalar)
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
