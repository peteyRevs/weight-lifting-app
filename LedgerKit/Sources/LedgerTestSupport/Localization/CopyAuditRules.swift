import Foundation

/// The rules of `CopyAudit`, each on one file's source (standards §7, "Localization").
public enum CopyAuditRules {
    /// One violation in a file. `line` is 0 for one that belongs to the file as a whole.
    public struct Problem: Hashable, Sendable {
        public let line: Int
        public let message: String

        func finding(in path: String) -> String {
            line == 0 ? "\(path): \(message)" : "\(path):\(line): \(message)"
        }
    }

    /// Argument labels whose literals no lifter sees: an accessibility identifier (also `…Identifier:`), an SF
    /// Symbol's name, a logger's category. A label is the name that opens an argument, so it covers every literal
    /// in that argument's expression (both arms of a ternary), and a name that merely reads like one covers none.
    public static let unseenLabels: Set<String> = ["identifier", "systemImage", "systemName", "category"]

    /// The spellings of a localized lookup, written without spaces. `localized:` is the copy files' own.
    public static let lookupSpellings = [
        "localized:", "NSLocalizedString", "LocalizedStringKey", "LocalizedStringResource", "LocalizationValue",
        "localizedString(forKey", "localizedAttributedString(forKey"
    ]

    /// Whether no lifter sees a literal that stands in `argument`: an allowed label, the argument of
    /// `.accessibilityIdentifier(…)`, or the message of a level call on a logger (`logger.error(`,
    /// `launchLogger.log.debug(`).
    public static func isUnseen(_ argument: SwiftCallArgument) -> Bool {
        if unseenLabels.contains(argument.label) || argument.label.hasSuffix("Identifier") {
            return true
        }
        guard argument.label.isEmpty, argument.index == 0 else {
            return false
        }
        let levels = /(?:[Ll]ogger|\.log)(?:\.\w+)*\.(?:debug|info|notice|warning|error|fault|critical|trace)$/
        return argument.callee.hasSuffix("accessibilityIdentifier") || argument.callee.contains(levels)
    }

    /// What a file that is not a copy file holds and must not: lookups, literals a lifter could see, and entries
    /// of `exempt` (texts of literals no lifter sees) that the file does not hold.
    public static func strayProblems(_ source: SwiftSource, exempting exempt: [String] = []) -> [Problem] {
        var problems = lookups(in: source, spelled: lookupSpellings).map {
            Problem(line: $0.line, message: "a localized lookup outside the copy files: \($0.spelling)")
        }
        var unseen: [Bool] = []
        var held: Set<String> = []
        for literal in source.literals {
            let isCovered = literal.argument.map(isUnseen) ?? false || literal.holder.map { unseen[$0] } ?? false
            unseen.append(isCovered)
            let isHandedToText = isTextArgument(literal)
            guard !isCovered, isHandedToText || literal.text.contains(where: \.isLetter) else {
                continue
            }
            if !isHandedToText, let entry = exempt.first(where: { isSameText($0, literal.text) }) {
                held.insert(entry)
            } else {
                let what = isHandedToText ? "a literal handed to Text" : "a string literal"
                problems.append(Problem(
                    line: literal.line,
                    message: "\(what) outside the copy files: \"\(literal.text)\""
                ))
            }
        }
        return problems + exempt.filter { !held.contains($0) }.map {
            Problem(line: 0, message: "is exempt for \"\($0)\", which it does not hold")
        }
    }

    /// What a copy file holds besides the two lookup forms of standards §7.
    public static func copyFileProblems(_ source: SwiftSource) -> [Problem] {
        var problems = Set(otherLookups(in: source))
        for literal in source.literals {
            let argument = literal.argument
            if argument?.label == "comment", argument?.callee == "String" || argument?.callee == "Text" {
                continue
            }
            let message: String? = if isStringLookupKey(literal) {
                stringLookupProblem(literal)
            } else if isTextArgument(literal) {
                textLookupProblem(literal)
            } else {
                literal.text
                    .contains(where: \.isLetter) ? "a string literal that is not a lookup: \"\(literal.text)\"" : nil
            }
            if let message {
                problems.insert(Problem(line: literal.line, message: message))
            }
        }
        return problems.sorted { ($0.line, $0.message) < ($1.line, $1.message) }
    }

    /// A file the audit leaves unread must be wholly inside `#if DEBUG`, its imports aside (they may stand before
    /// it): one finding when it is not.
    public static func debugOnlyProblems(_ source: SwiftSource) -> [Problem] {
        let lines = source.code.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .drop { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }
        var depth = 0
        var isWhole = lines.first == "#if DEBUG" && lines.last == "#endif"
        for (offset, line) in lines.enumerated() where isWhole {
            if line.hasPrefix("#if") {
                depth += 1
            } else if line.hasPrefix("#endif") {
                depth -= 1
                isWhole = depth > 0 || offset == lines.count - 1
            } else if line.hasPrefix("#else"), depth == 1 {
                isWhole = false
            }
        }
        return isWhole ? [] : [Problem(line: 0, message: "is not wholly inside `#if DEBUG`, so it cannot go unread")]
    }

    /// Two texts with the same Unicode scalars: what a strings table compares, where Swift's `==` would also call
    /// a composed and a decomposed spelling equal.
    public static func isSameText(_ first: String, _ second: String) -> Bool {
        first.unicodeScalars.elementsEqual(second.unicodeScalars)
    }
}

private extension CopyAuditRules {
    static let nested = "a lookup inside another literal's interpolation: write the join as two statements"

    /// A literal handed straight to `Text(…)`, which SwiftUI looks up as a key whatever it holds.
    static func isTextArgument(_ literal: SwiftStringLiteral) -> Bool {
        guard let argument = literal.argument, argument.label.isEmpty, argument.index == 0 else {
            return false
        }
        return (argument.callee == "Text" || argument.callee.hasSuffix(".Text")) && literal.lead.hasSuffix("Text(")
    }

    /// The key of a `String(localized: "…"`: the literal stands right after that label, in a call of `String`.
    static func isStringLookupKey(_ literal: SwiftStringLiteral) -> Bool {
        literal.argument?.callee == "String" && literal.argument?.label == "localized"
            && literal.lead.hasSuffix("localized:")
    }

    /// What is wrong with a `String(localized: "…"` whose key is `literal`, if anything.
    static func stringLookupProblem(_ literal: SwiftStringLiteral) -> String? {
        if literal.holder != nil {
            nested
        } else if literal.isMultiline {
            "a lookup whose key is not a one-line literal"
        } else if !literal.trail.hasPrefix(",bundle:.module") {
            "a lookup not written `String(localized: \"…\", bundle: .module)`"
        } else if !literal.interpolations.isEmpty, !literal.trail.hasPrefix(",bundle:.module,locale:") {
            "a lookup whose key carries a value and that passes no `locale:`"
        } else {
            nil
        }
    }

    /// What is wrong with a `Text("…"` in a copy file: the one form allowed embeds a live timer.
    static func textLookupProblem(_ literal: SwiftStringLiteral) -> String? {
        let isTimer = literal.interpolations.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("timerInterval:")
        }
        if literal.holder != nil {
            return nested
        }
        if isTimer, !literal.isMultiline, literal.trail.hasPrefix(",bundle:.module") {
            return nil
        }
        return "a Text's own lookup that is not `Text(\"… \\(timerInterval: …)\", bundle: .module)`"
    }

    /// The lookups of a copy file that are in neither form: another API, a key that is not a literal, a lookup
    /// inside an interpolation.
    static func otherLookups(in source: SwiftSource) -> [Problem] {
        var problems = lookups(in: source, spelled: lookupSpellings.filter { $0 != "localized:" }).map {
            Problem(line: $0.line, message: "a lookup that is not `String(localized:)`: \($0.spelling)")
        }
        var keyed = source.literals.filter { $0.holder == nil && isStringLookupKey($0) }.map(\.line)
        for line in source.lines(ofCode: "localized:") {
            if let index = keyed.firstIndex(of: line) {
                keyed.remove(at: index)
            } else {
                problems.append(Problem(
                    line: line,
                    message: "a lookup that is not `String(localized: \"…\"`, its key a literal"
                ))
            }
        }
        for literal in source.literals where literal.interpolations.contains(where: { holdsALookup($0) }) {
            problems.append(Problem(line: literal.line, message: nested))
        }
        return problems
    }

    static func holdsALookup(_ expression: String) -> Bool {
        let code = expression.filter { !$0.isWhitespace }
        return lookupSpellings.contains { code.contains($0) }
    }

    /// Each use of one of `spellings` in the code of `source`, an interpolation's included, with its line.
    static func lookups(in source: SwiftSource, spelled spellings: [String]) -> [(line: Int, spelling: String)] {
        spellings.flatMap { spelling in
            let inCode = source.lines(ofCode: spelling)
            let inInterpolations = source.literals.flatMap { literal in
                literal.interpolations
                    .filter { $0.filter { !$0.isWhitespace }.contains(spelling) }
                    .map { _ in literal.line }
            }
            return (inCode + inInterpolations).map { (line: $0, spelling: spelling) }
        }
    }
}
