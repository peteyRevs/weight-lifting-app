import Foundation

/// The source half of standards §7's localization check: where a module's copy may stand, read from its sources.
/// (The other half, that the catalog's keys are the keys the compiler extracted from the code, is the gate's
/// `scripts/check-string-catalogs.sh`; this audit derives no key.) One suite, `ModuleCopyTests`, runs it over
/// every module of the package and expects `findings` to be empty:
///
/// - **No copy outside the copy files.** A copy file is `<Name>Copy.swift` or `<Name>Copy+<Area>.swift`. In any
///   other file a localized lookup is a finding, and so is a string literal with a letter in it, or any literal
///   handed straight to `Text(…)`, unless the literal stands in an argument no lifter sees (`CopyAuditRules`) or
///   the module's exemptions name it.
/// - **A copy file holds lookups only**, in the two forms of standards §7, each reading this module's catalog.
/// - **Debug-only files are Debug-only.** A `*+Previews.swift` file and a file exempted as Debug-only are not
///   read, and must be wholly inside `#if DEBUG`.
/// - **The catalog is sound** (`StringCatalog.problems`), when the module has one.
///
/// The audit reads text, not types; standards §7 lists what that cannot see ("Known limits").
public struct CopyAudit: Sendable {
    /// What a module sets aside, each entry confirmed in review (standards §7).
    public struct Exemptions: Sendable, ExpressibleByDictionaryLiteral {
        /// Literals no lifter sees, by their file's path in the module and their text (a launch argument, a file
        /// name). Any other literal of the file is still a finding, and so is an entry the file does not hold.
        public var literals: [String: [String]]
        /// Files of Debug builds only, by their path in the module: wholly inside `#if DEBUG`, which is verified.
        public var debugOnly: Set<String>

        public init(literals: [String: [String]] = [:], debugOnly: Set<String> = []) {
            self.literals = literals
            self.debugOnly = debugOnly
        }

        public init(dictionaryLiteral elements: (String, [String])...) {
            self.init(literals: Dictionary(elements) { $0 + $1 })
        }
    }

    /// Every violation, one line each (`AppTabs.swift:18: …`); empty when the module follows the rules.
    public let findings: [String]

    /// Audits a module that has copy: `LedgerKit/Sources/<module>` and its `Resources/Localizable.xcstrings`.
    /// Throws when the module has no catalog or its folder cannot be read: it never passes on nothing.
    public init(module: String, exempting exemptions: Exemptions = [:]) throws {
        try self.init(
            sources: Self.sources(ofModule: module),
            catalog: StringCatalog(module: module),
            exempting: exemptions
        )
    }

    /// Audits a module that has no catalog: none of its files may hold copy, and a copy file is a finding.
    public init(moduleWithoutCatalog module: String, exempting exemptions: Exemptions = [:]) throws {
        try self.init(sources: Self.sources(ofModule: module), catalog: nil, exempting: exemptions)
    }

    /// The same audit over sources given by their path in the module, for this helper's own tests.
    public init(sources: [String: String], catalog: StringCatalog?, exempting exemptions: Exemptions = [:]) {
        var found = (catalog?.problems ?? []).map { "\(Self.catalogName): \($0)" }
        var read: Set<String> = []
        for (path, text) in sources.sorted(by: { $0.key < $1.key }) {
            let source = SwiftSource(text)
            let problems: [CopyAuditRules.Problem]
            if Self.isPreviewFile(path) || exemptions.debugOnly.contains(path) {
                problems = CopyAuditRules.debugOnlyProblems(source)
            } else if Self.isCopyFile(path) {
                problems = CopyAuditRules.copyFileProblems(source)
                    +
                    (catalog == nil ? [.init(line: 0, message: "is a copy file in a module that has no catalog")] :
                        [])
            } else {
                read.insert(path)
                problems = CopyAuditRules.strayProblems(source, exempting: exemptions.literals[path] ?? [])
            }
            found += problems.sorted { $0.line < $1.line }.map { $0.finding(in: path) }
        }
        let unread = Set(exemptions.literals.keys).subtracting(read)
            .union(exemptions.debugOnly.subtracting(sources.keys))
        found += unread.sorted().map { "\($0): is exempt, but is not a file this check reads" }
        findings = found
    }

    public static func isCopyFile(_ path: String) -> Bool {
        fileName(path).contains(/^\w+Copy(?:\+\w+)?\.swift$/)
    }

    public static func isPreviewFile(_ path: String) -> Bool {
        fileName(path).hasSuffix("+Previews.swift")
    }

    /// Every Swift file of `LedgerKit/Sources/<module>`, by its path in the module. Throws when the folder, or a
    /// folder inside it, cannot be read.
    public static func sources(ofModule module: String) throws -> [String: String] {
        let directory = PreviewScan.sourcesDirectory.appending(path: module, directoryHint: .isDirectory)
        let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path(percentEncoded: false))
        var sources: [String: String] = [:]
        for path in paths where path.hasSuffix(".swift") {
            sources[path] = try String(contentsOf: directory.appending(path: path), encoding: .utf8)
        }
        return sources
    }

    private static let catalogName = "Localizable.xcstrings"

    private static func fileName(_ path: String) -> Substring {
        path.split(separator: "/").last ?? ""
    }
}
