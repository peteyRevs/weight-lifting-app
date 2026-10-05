import Foundation

/// One string literal of a Swift source file, and where it stands.
public struct SwiftStringLiteral: Hashable, Sendable {
    public enum Part: Hashable, Sendable {
        /// Text between the quotes, its escapes resolved.
        case text(String)
        /// The expression inside `\(…)`, as written.
        case interpolation(String)
    }

    public let parts: [Part]
    /// The line of the opening quote, counted from 1.
    public let line: Int
    /// The code just before the opening quote, without comments or whitespace: it ends `accessibilityIdentifier(`
    /// for that modifier's argument and `localized:` for a lookup's key. At most `SwiftSource.leadLength` characters.
    public let lead: String
    /// A `"""` literal.
    public let isMultiline: Bool

    /// The literal's own text, without its interpolations.
    public var text: String {
        parts.map { part in
            if case let .text(text) = part {
                text
            } else {
                ""
            }
        }
        .joined()
    }
}

/// A Swift source file split into code and string literals, for the checks that read sources (`CopyAudit`). It
/// knows enough of Swift's lexical rules to tell code from comments and to walk a literal's interpolations: line
/// and nested block comments, escapes, `\(…)` with literals inside, multi-line and `#"raw"#` literals. It does not
/// know regex literals; a `/…"…/` would be read as the start of a string.
public struct SwiftSource: Sendable {
    static let leadLength = 48

    /// Every string literal, in the order of their opening quotes: a literal inside an interpolation follows the
    /// literal that holds it.
    public let literals: [SwiftStringLiteral]
    /// The code of each line: comments removed and every literal, its interpolations included, replaced by `""`.
    /// What an interpolation holds is in its literal's `parts`, and the literals inside it are in `literals`.
    public let code: [String]

    public init(_ source: String) {
        var lexer = Lexer(Array(source))
        lexer.readCode(insideInterpolation: false)
        literals = lexer.literals
        code = lexer.code
    }

    /// The code with every space and line break removed, for a check that reads across wrapped lines.
    public var compactCode: String {
        code.joined().filter { !$0.isWhitespace }
    }
}

private struct Lexer {
    fileprivate typealias Delimiter = (hashes: Int, isMultiline: Bool)

    private let characters: [Character]
    private var index = 0
    private var line = 1
    private var lead = ""
    private(set) var literals: [SwiftStringLiteral] = []
    private(set) var code = [""]

    init(_ characters: [Character], from index: Int = 0, line: Int = 1) {
        self.characters = characters
        self.index = index
        self.line = line
    }

    /// Reads code to the end of the source or, inside an interpolation, to its closing parenthesis (left unread).
    mutating func readCode(insideInterpolation: Bool) {
        var depth = 0
        while index < characters.count {
            let character = characters[index]
            if starts(with: "//") {
                skipLineComment()
            } else if starts(with: "/*") {
                skipBlockComment()
            } else if let delimiter = openingDelimiter() {
                readLiteral(delimiter)
            } else {
                if insideInterpolation, character == ")" {
                    if depth == 0 {
                        return
                    }
                    depth -= 1
                } else if insideInterpolation, character == "(" {
                    depth += 1
                }
                appendCode(character)
                index += 1
            }
        }
    }

    private func starts(with text: String, at offset: Int = 0) -> Bool {
        let start = index + offset
        return start + text.count <= characters.count && characters[start ..< start + text.count].elementsEqual(text)
    }

    private mutating func appendCode(_ character: Character) {
        if character.isNewline {
            line += 1
            code.append("")
        } else {
            code[code.count - 1].append(character)
            if !character.isWhitespace {
                lead.append(character)
            }
        }
    }

    /// Passes over a character that is not code (inside a comment or a literal), keeping the line count.
    private mutating func skip() {
        if characters[index].isNewline {
            line += 1
            code.append("")
        }
        index += 1
    }

    private mutating func skipLineComment() {
        while index < characters.count, !characters[index].isNewline {
            index += 1
        }
    }

    private mutating func skipBlockComment() {
        var depth = 0
        while index < characters.count {
            if starts(with: "/*") {
                depth += 1
                index += 2
            } else if starts(with: "*/") {
                depth -= 1
                index += 2
                if depth == 0 {
                    return
                }
            } else {
                skip()
            }
        }
    }

    /// At a string literal's opening quote (after its `#`s, if any): the delimiter.
    private func openingDelimiter() -> Delimiter? {
        var hashes = 0
        while starts(with: "#", at: hashes) {
            hashes += 1
        }
        guard starts(with: "\"", at: hashes) else {
            return nil
        }
        return (hashes, starts(with: "\"\"\"", at: hashes))
    }
}

/// Reading one literal: its text, its escapes and its interpolations.
private extension Lexer {
    mutating func readLiteral(_ delimiter: Delimiter) {
        let pounds = String(repeating: "#", count: delimiter.hashes)
        let quotes = delimiter.isMultiline ? "\"\"\"" : "\""
        let startLine = line
        let leadBefore = String(lead.suffix(SwiftSource.leadLength))
        let slot = literals.count
        literals.append(SwiftStringLiteral(parts: [], line: startLine, lead: leadBefore, isMultiline: false))
        var parts: [SwiftStringLiteral.Part] = []
        var text = ""
        index += delimiter.hashes + quotes.count
        while index < characters.count, !starts(with: quotes + pounds) {
            if !delimiter.isMultiline, characters[index].isNewline {
                break // an unterminated literal ends with its line, which stays unread
            }
            if starts(with: "\\" + pounds) {
                index += 1 + delimiter.hashes
                if starts(with: "(") {
                    parts.append(.text(text))
                    text = ""
                    parts.append(.interpolation(readInterpolation()))
                } else {
                    text.append(readEscape())
                }
            } else {
                text.append(characters[index])
                skip()
            }
        }
        if starts(with: quotes + pounds) {
            index += quotes.count + delimiter.hashes
        }
        parts.append(.text(text))
        literals[slot] = SwiftStringLiteral(
            parts: parts.filter { $0 != .text("") },
            line: startLine,
            lead: leadBefore,
            isMultiline: delimiter.isMultiline
        )
        for character in "\"\"" {
            appendCode(character)
        }
    }

    /// At an interpolation's opening parenthesis: reads the expression with a lexer of its own, so that its code
    /// stays out of this line's, keeps the literals inside it, and returns the expression as written.
    mutating func readInterpolation() -> String {
        var inner = Lexer(characters, from: index + 1, line: line)
        inner.readCode(insideInterpolation: true)
        let expression = String(characters[(index + 1) ..< inner.index])
        literals += inner.literals
        code += Array(repeating: "", count: inner.line - line)
        line = inner.line
        index = min(inner.index + 1, characters.count)
        return expression
    }

    /// After an escape's backslash: the text it stands for. A backslash before a line break, in a multi-line
    /// literal, joins the two lines.
    mutating func readEscape() -> String {
        guard index < characters.count else {
            return ""
        }
        let character = characters[index]
        if character.isNewline {
            skip()
            return ""
        }
        index += 1
        switch character {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "0": return "\0"
        case "u": return readUnicodeScalar()
        default: return String(character) // \" \' \\
        }
    }

    /// After `\u`: the scalar of `{1F600}`.
    mutating func readUnicodeScalar() -> String {
        guard starts(with: "{"), let close = characters[index...].firstIndex(of: "}") else {
            return ""
        }
        let digits = String(characters[(index + 1) ..< close])
        index = close + 1
        return UInt32(digits, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
    }
}
