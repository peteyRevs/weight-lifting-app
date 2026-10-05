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
    /// The call argument the literal stands in, however deep in that argument's expression (a ternary's arm, an
    /// array); nil outside a call's parentheses and inside a closure's braces.
    public let argument: SwiftCallArgument?
    /// The code just after the closing quote, without comments or whitespace: `,bundle:.module)` after a lookup's
    /// key. At most `SwiftSource.leadLength` characters.
    public internal(set) var trail = ""
    /// The place in `SwiftSource.literals` of the literal whose interpolation holds this one; nil for a literal that
    /// stands in the file's own code.
    public internal(set) var holder: Int?

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

    /// The expressions of the literal's interpolations, as written.
    public var interpolations: [String] {
        parts.compactMap { part in
            if case let .interpolation(expression) = part {
                expression
            } else {
                nil
            }
        }
    }
}

/// An argument of a call, as far as text can tell: what is called, and the argument's label and place.
public struct SwiftCallArgument: Hashable, Sendable {
    /// The code before the argument list's parenthesis, back to the start of the name: `Image`,
    /// `.accessibilityIdentifier`, `environment.logger.log.fault`.
    public let callee: String
    /// The argument's label, a name that opens the argument and is followed by a colon; empty for an argument
    /// without one. A name later in the argument (a ternary's arm) is not a label.
    public let label: String
    /// The argument's place in the list, from 0.
    public let index: Int

    public init(callee: String, label: String, index: Int) {
        self.callee = callee
        self.label = label
        self.index = index
    }
}

/// A Swift source file split into code and string literals, for the checks that read sources (`CopyAudit`). It
/// knows enough of Swift's lexical rules to tell code from comments and to walk a literal's interpolations: line
/// and nested block comments, escapes, `\(…)` with literals inside, multi-line and `#"raw"#` literals. It does not
/// know regex literals: a `/…"…/` is read as the start of a string, and a `/…/*…/` as the start of a comment.
public struct SwiftSource: Sendable {
    static let leadLength = 48

    /// Every string literal, in the order of their opening quotes: a literal inside an interpolation follows the
    /// literal that holds it.
    public let literals: [SwiftStringLiteral]
    /// The code of each line: comments removed and every literal, its interpolations included, replaced by `""`.
    /// What an interpolation holds is in its literal's `parts`, and the literals inside it are in `literals`.
    public let code: [String]
    /// `code` without spaces and line breaks, and the line each of its characters stands on.
    private let compact: [Character]
    private let compactLines: [Int]

    public init(_ source: String) {
        var lexer = SwiftLexer(Array(source))
        lexer.readCode(insideInterpolation: false)
        lexer.sealTrails()
        literals = lexer.literals
        code = lexer.code
        compact = lexer.compact
        compactLines = lexer.compactLines
    }

    /// The code with every space and line break removed, for a check that reads across wrapped lines.
    public var compactCode: String {
        String(compact)
    }

    /// The line of each place where `spelling` (written without spaces) stands in the file's own code, however the
    /// code is wrapped over lines. An interpolation's code is not searched: it is in its literal's `parts`.
    public func lines(ofCode spelling: String) -> [Int] {
        let wanted = Array(spelling)
        guard !wanted.isEmpty, compact.count >= wanted.count else {
            return []
        }
        return (0 ... compact.count - wanted.count)
            .filter { compact[$0 ..< $0 + wanted.count].elementsEqual(wanted) }
            .map { compactLines[$0] }
    }
}
