import Foundation

/// The check that a module's copy follows standards §7, read from its sources and its String Catalog. Each module
/// with copy has one test that expects `findings` to be empty:
///
/// - **The catalog and the copy files agree in both directions.** A copy file is `<Name>Copy.swift` or
///   `<Name>Copy+<Area>.swift`; its lookups are `String(localized: "…", bundle: .module)`. A key it looks up that the
///   catalog lacks is a finding, and so is a catalog key no copy file looks up.
/// - **The copy files hold lookups only, each one readable**: a string literal there is a lookup's key or its
///   `comment:`, and a lookup's key is a literal, so that no key escapes the comparison with the catalog.
/// - **No other file holds copy**: neither a localized lookup nor a string literal with a letter in it, unless the
///   literal is an accessibility identifier, an SF Symbol's name or a log line (`allowedLeads`, `isLogLine`), or
///   its file is exempt. `*+Previews.swift` files are Debug-only and not read.
/// - **The catalog is sound** (`StringCatalog.problems`).
///
/// The check reads text, not types. So that it can name each lookup's key, an interpolation in a lookup is a bare
/// parameter of the member it stands in, declared `Int` (`%lld`) or `String` (`%@`); anything else is a finding.
public struct CopyAudit: Sendable {
    /// Every violation, one line each (`AppTabs.swift:18: …`); empty when the module follows the rules.
    public let findings: [String]

    /// Audits `LedgerKit/Sources/<module>` against its `Resources/Localizable.xcstrings`. `exemptions` names files
    /// whose string literals no lifter sees, by their path in the module, each with the reason; an exemption that
    /// exempts nothing is a finding, so the list cannot go stale.
    public init(module: String, exempting exemptions: [String: String] = [:]) throws {
        let directory = PreviewScan.sourcesDirectory.appending(path: module, directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
        }
        let root = directory.standardizedFileURL.path(percentEncoded: false)
        var sources: [String: String] = [:]
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let path = file.standardizedFileURL.path(percentEncoded: false)
            let name = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : file.lastPathComponent
            sources[name] = try String(contentsOf: file, encoding: .utf8)
        }
        try self.init(sources: sources, catalog: StringCatalog(module: module), exempting: exemptions)
    }

    /// The same audit over sources given by their path in the module, for this helper's own tests.
    public init(sources: [String: String], catalog: StringCatalog, exempting exemptions: [String: String] = [:]) {
        var found = catalog.problems.map { "\(Self.catalogName): \($0)" }
        var lookedUp: Set<String> = []
        for (path, text) in sources.sorted(by: { $0.key < $1.key }) where !Self.isPreviewFile(path) {
            let source = SwiftSource(text)
            if Self.isCopyFile(path) {
                let copy = Self.copyFile(source)
                lookedUp.formUnion(copy.lookups.map(\.key))
                let missing = copy.lookups.filter { !catalog.keys.contains($0.key) }.map {
                    Problem(line: $0.line, message: "looks up \"\($0.key)\", which the catalog does not hold")
                }
                found += (missing + copy.problems).sorted { $0.line < $1.line }.map { $0.finding(in: path) }
            } else {
                let literals = Self.strayLiterals(in: source)
                if exemptions[path] == nil {
                    found += literals.map { $0.finding(in: path) }
                } else if literals.isEmpty {
                    found.append("\(path): is exempt, but holds no string literal to exempt")
                }
                found += Self.strayLookups(in: source).map { $0.finding(in: path) }
            }
        }
        found += exemptions.keys.sorted()
            .filter { sources[$0] == nil || Self.isCopyFile($0) || Self.isPreviewFile($0) }
            .map { "\($0): is exempt, but is not a file this check reads" }
        found += catalog.keys.subtracting(lookedUp).sorted().map {
            "\(Self.catalogName): \"\($0)\" is not looked up by a copy file"
        }
        findings = found
    }
}

// MARK: - The rules, each on one file's source

public extension CopyAudit {
    /// One violation in a file. `line` is 0 for one that belongs to the file as a whole.
    struct Problem: Hashable, Sendable {
        public let line: Int
        public let message: String

        func finding(in path: String) -> String {
            line == 0 ? "\(path): \(message)" : "\(path):\(line): \(message)"
        }
    }

    /// A lookup in a copy file: the catalog key it asks for.
    struct Lookup: Hashable, Sendable {
        public let key: String
        public let line: Int
    }

    /// What may stand just before a string literal outside a copy file, because no lifter sees the literal: an
    /// accessibility identifier (the modifier, or a parameter that carries one) or an SF Symbol's name.
    static let allowedLeads = ["accessibilityIdentifier(", "identifier:", "Identifier:", "systemImage:", "systemName:"]

    /// A log line stands in an `os.Logger` level call on a logger (`logger.error(`, `launchLogger.log.debug(`).
    static func isLogLine(lead: String) -> Bool {
        lead.contains(/(?:[Ll]ogger|\.log)(?:\.\w+)*\.(?:debug|info|notice|warning|error|fault|critical|trace)\($/)
    }

    /// The spellings of a localized lookup, which belongs in a copy file.
    static let lookupSpellings = [
        "localized:", "NSLocalizedString", "LocalizedStringKey", "LocalizedStringResource", "LocalizationValue",
        "localizedString(forKey"
    ]

    static func isCopyFile(_ path: String) -> Bool {
        fileName(path).contains(/^\w+Copy(?:\+\w+)?\.swift$/)
    }

    static func isPreviewFile(_ path: String) -> Bool {
        fileName(path).hasSuffix("+Previews.swift")
    }

    /// A copy file's lookups, and what in it is not a lookup this check can read.
    static func copyFile(_ source: SwiftSource) -> (lookups: [Lookup], problems: [Problem]) {
        var lookups: [Lookup] = []
        var problems: [Problem] = []
        let members = memberParameters(in: source)
        for literal in source.literals where !literal.lead.hasSuffix("comment:") {
            guard literal.lead.hasSuffix("localized:") else {
                if literal.text.contains(where: \.isLetter) {
                    let message = "a string literal that is not a lookup: \"\(literal.text)\""
                    problems.append(Problem(line: literal.line, message: message))
                }
                continue
            }
            let parameters = members.last { $0.line <= literal.line }?.parameters ?? [:]
            if let key = key(of: literal, parameters: parameters) {
                lookups.append(Lookup(key: key, line: literal.line))
            } else {
                problems.append(Problem(line: literal.line, message: unreadableLookup))
            }
        }
        problems += otherLookups(in: source)
        return (lookups, problems)
    }

    /// The localized lookups in a file that is not a copy file.
    static func strayLookups(in source: SwiftSource) -> [Problem] {
        lookups(in: source, spelled: lookupSpellings).map {
            Problem(line: $0.line, message: "a localized lookup outside the copy files: \($0.spelling)")
        }
    }

    /// The string literals a lifter could see in a file that is not a copy file.
    static func strayLiterals(in source: SwiftSource) -> [Problem] {
        source.literals
            .filter { literal in
                literal.text.contains(where: \.isLetter)
                    && !allowedLeads.contains { literal.lead.hasSuffix($0) }
                    && !isLogLine(lead: literal.lead)
            }
            .map { Problem(line: $0.line, message: "a string literal outside the copy files: \"\($0.text)\"") }
    }
}

private extension CopyAudit {
    static let catalogName = "Localizable.xcstrings"

    /// Each use of one of `spellings` in the code of `source`, an interpolation's included, with its line.
    static func lookups(in source: SwiftSource, spelled spellings: [String]) -> [(line: Int, spelling: String)] {
        let lines = source.code.enumerated().map { (line: $0 + 1, code: $1) }
        let interpolations = source.literals.flatMap { literal in
            literal.parts.compactMap { part -> (line: Int, code: String)? in
                if case let .interpolation(expression) = part {
                    (literal.line, expression)
                } else {
                    nil
                }
            }
        }
        return (lines + interpolations).flatMap { entry in
            spellings.filter { entry.code.contains($0) }.map { (entry.line, $0) }
        }
    }

    /// The lookups of a copy file that are not `String(localized: "…", bundle: .module)`: another API, a key that
    /// is not a literal (the check could not compare it with the catalog), another bundle or table.
    static func otherLookups(in source: SwiftSource) -> [Problem] {
        var problems = lookups(in: source, spelled: lookupSpellings.filter { $0 != "localized:" }).map {
            Problem(line: $0.line, message: "a lookup that is not `String(localized:)`: \($0.spelling)")
        }
        let code = source.compactCode
        let all = code.ranges(of: "localized:").count
        let literal = code.ranges(of: "localized:\"\"").count
        let inThisCatalog = code.ranges(of: "localized:\"\",bundle:.module").count
        if all > literal {
            problems.append(Problem(line: 0, message: "\(all - literal) lookup(s) whose key is not a string literal"))
        }
        if literal > inThisCatalog {
            let message = "\(literal - inThisCatalog) lookup(s) not written `localized: \"…\", bundle: .module`"
            problems.append(Problem(line: 0, message: message))
        }
        return problems
    }

    static let unreadableLookup = "a lookup this check cannot read: its key is a one-line literal, and each "
        + "interpolation a bare parameter of its member declared Int or String"
    /// The format specifier the compiler gives an interpolated value of each type (`String.LocalizationValue`).
    static let specifiers = ["Int": "%lld", "String": "%@"]

    static func fileName(_ path: String) -> Substring {
        path.split(separator: "/").last ?? ""
    }

    /// The catalog key of a lookup's literal, as the compiler derives it: a percent sign doubled, each
    /// interpolation the specifier of its parameter's type. Nil when the literal is not one this check can read.
    static func key(of literal: SwiftStringLiteral, parameters: [String: String]) -> String? {
        guard !literal.isMultiline else {
            return nil
        }
        var key = ""
        for part in literal.parts {
            switch part {
            case let .text(text):
                key += text.replacing("%", with: "%%")
            case let .interpolation(expression):
                let name = expression.trimmingCharacters(in: .whitespaces)
                guard let specifier = parameters[name].flatMap({ specifiers[$0] }) else {
                    return nil
                }
                key += specifier
            }
        }
        return key
    }

    /// Each member of a copy file (`static var`, `static let`, `func`), by the line it starts on, with its
    /// parameters' types by name: `func week(_ week: Int, of total: Int)` gives `week: Int, total: Int`.
    static func memberParameters(in source: SwiftSource) -> [(line: Int, parameters: [String: String])] {
        let code = source.code.joined(separator: "\n")
        return code.matches(of: /\bstatic\s+(?:var|let)\s+\w+|\bfunc\s+\w+\s*\(([^()]*)\)/).map { match in
            let line = code[..<match.range.lowerBound].count { $0.isNewline } + 1
            var parameters: [String: String] = [:]
            for parameter in (match.output.1 ?? "").split(separator: ",") {
                let halves = parameter.split(separator: ":", maxSplits: 1)
                if halves.count == 2, let name = halves[0].split(whereSeparator: \.isWhitespace).last {
                    let type = halves[1].split(separator: "=").first ?? ""
                    parameters[String(name)] = type.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return (line, parameters)
        }
    }
}
