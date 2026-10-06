import Foundation

/// Reading one literal: its text, its escapes and its interpolations.
extension SwiftLexer {
    mutating func readLiteral(_ delimiter: Delimiter) {
        let startLine = line
        let lead = String(compact.suffix(SwiftSource.leadLength))
        let argument = argument
        noteArgumentContent()
        let slot = literals.count
        literals.append(
            SwiftStringLiteral(parts: [], line: startLine, lead: lead, isMultiline: false, argument: argument)
        )
        let parts = readParts(delimiter, heldBy: slot)
        literals[slot] = SwiftStringLiteral(
            parts: parts.filter { $0 != .text("") },
            line: startLine,
            lead: lead,
            isMultiline: delimiter.isMultiline,
            argument: argument
        )
        for character in "\"\"" {
            appendCode(character)
        }
        trailStarts[slot] = compact.count
    }

    /// From a literal's opening delimiter to past its closing one: its text and its interpolations, in order.
    private mutating func readParts(_ delimiter: Delimiter, heldBy slot: Int) -> [SwiftStringLiteral.Part] {
        let pounds = String(repeating: "#", count: delimiter.hashes)
        let quotes = delimiter.isMultiline ? "\"\"\"" : "\""
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
                    parts.append(.interpolation(readInterpolation(heldBy: slot)))
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
        return parts + [.text(text)]
    }

    /// At an interpolation's opening parenthesis: reads the expression with a lexer of its own, so that its code
    /// stays out of this line's, keeps the literals inside it as held by the literal at `slot`, and returns the
    /// expression as written.
    private mutating func readInterpolation(heldBy slot: Int) -> String {
        var inner = SwiftLexer(characters, from: index + 1, line: line)
        inner.readCode(insideInterpolation: true)
        inner.sealTrails()
        let expression = String(characters[(index + 1) ..< inner.index])
        let base = literals.count
        literals += inner.literals.map { literal in
            var held = literal
            held.holder = literal.holder.map { $0 + base } ?? slot
            return held
        }
        code += Array(repeating: "", count: inner.line - line)
        line = inner.line
        index = min(inner.index + 1, characters.count)
        return expression
    }

    /// After an escape's backslash: the text it stands for. A backslash before a line break, in a multi-line
    /// literal, joins the two lines.
    private mutating func readEscape() -> String {
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
    private mutating func readUnicodeScalar() -> String {
        guard starts(with: "{"), let close = characters[index...].firstIndex(of: "}") else {
            return ""
        }
        let digits = String(characters[(index + 1) ..< close])
        index = close + 1
        return UInt32(digits, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
    }
}
