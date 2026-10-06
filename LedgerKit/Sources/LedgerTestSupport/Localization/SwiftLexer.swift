import Foundation

/// Reads a Swift source for `SwiftSource`: its code without comments, its string literals, and for each literal the
/// call argument it stands in. Text only: no types, no regex literals.
struct SwiftLexer {
    typealias Delimiter = (hashes: Int, isMultiline: Bool)

    /// What an open bracket is. A call's parentheses hold arguments; square brackets and braces hold none.
    enum Bracket {
        case call, brackets, braces
    }

    /// An open bracket in the code, and for a call the argument the code now stands in.
    struct Frame {
        let kind: Bracket
        var callee = ""
        var label = ""
        var index = 0
        /// The name that opens the current argument, while it can still turn out to be the argument's label; nil
        /// once anything else has been read.
        var opening: String? = ""
    }

    let characters: [Character]
    var index: Int
    var line: Int
    var literals: [SwiftStringLiteral] = []
    var code = [""]
    /// The code without spaces and line breaks, and the line of each of its characters.
    var compact: [Character] = []
    var compactLines: [Int] = []
    var frames: [Frame] = []
    /// For each literal this lexer read itself, where in `compact` the code after it starts.
    var trailStarts: [Int: Int] = [:]

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
                noteStructure(character)
                appendCode(character)
                index += 1
            }
        }
    }

    /// Fills in each own literal's `trail`, once all the code after it has been read.
    mutating func sealTrails() {
        for (slot, start) in trailStarts {
            let end = min(start + SwiftSource.leadLength, compact.count)
            literals[slot].trail = String(compact[min(start, end) ..< end])
        }
        trailStarts = [:]
    }

    func starts(with text: String, at offset: Int = 0) -> Bool {
        let start = index + offset
        return start + text.count <= characters.count && characters[start ..< start + text.count].elementsEqual(text)
    }

    mutating func appendCode(_ character: Character) {
        if character.isNewline {
            line += 1
            code.append("")
        } else {
            code[code.count - 1].append(character)
            if !character.isWhitespace {
                compact.append(character)
                compactLines.append(line)
            }
        }
    }

    /// Passes over a character that is not code (inside a comment or a literal), keeping the line count.
    mutating func skip() {
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

// MARK: - Calls and their arguments

extension SwiftLexer {
    /// The call argument the code now stands in: the nearest open parenthesis, through square brackets (an array
    /// in an argument is part of it) but not through braces (a closure's body is code of its own).
    var argument: SwiftCallArgument? {
        for frame in frames.reversed() {
            switch frame.kind {
            case .call: return SwiftCallArgument(callee: frame.callee, label: frame.label, index: frame.index)
            case .brackets: continue
            case .braces: return nil
            }
        }
        return nil
    }

    /// Keeps `frames` in step with one character of code, before it joins `compact`.
    mutating func noteStructure(_ character: Character) {
        switch character {
        case "(", "[", "{":
            noteArgumentContent()
            let kind: Bracket = character == "(" ? .call : character == "[" ? .brackets : .braces
            frames.append(Frame(kind: kind, callee: kind == .call ? calleeBeforeParenthesis() : ""))
        case ")", "]", "}":
            _ = frames.popLast()
        default:
            noteInArgument(character)
        }
    }

    /// Something that is not a name stands in the current argument: it has no label, if it has none yet.
    mutating func noteArgumentContent() {
        if let top = frames.indices.last {
            frames[top].opening = nil
        }
    }

    private mutating func noteInArgument(_ character: Character) {
        guard let top = frames.indices.last, frames[top].kind == .call, !character.isWhitespace else {
            return
        }
        if character == "," {
            frames[top].index += 1
            frames[top].label = ""
            frames[top].opening = ""
        } else if character == ":", let name = frames[top].opening, !name.isEmpty {
            frames[top].label = name
            frames[top].opening = nil
        } else if character.isLetter || character.isNumber || character == "_" {
            frames[top].opening?.append(character)
        } else {
            frames[top].opening = nil
        }
    }

    /// The name before an opening parenthesis, with what it is called on: `.accessibilityIdentifier`,
    /// `environment.logger.log.fault`.
    private func calleeBeforeParenthesis() -> String {
        var start = compact.count
        while start > 0, Self.isCalleeCharacter(compact[start - 1]) {
            start -= 1
        }
        return String(compact[start...])
    }

    private static func isCalleeCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "." || character == "?"
    }
}
