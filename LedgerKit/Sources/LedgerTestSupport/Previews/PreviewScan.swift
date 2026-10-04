import Foundation

/// Reads the package's sources for `#Preview` declarations (F07 criterion 8), in the style of `ModuleBoundaryTests`:
/// each module that has previews lists them in a registry enum, one case per preview, and its test target's
/// `PreviewTests` render every case and compare the cases with what this scan finds.
public enum PreviewScan {
    /// The modules whose test targets check a preview registry. A module that gains its first `#Preview` adds a
    /// registry, those two suites, and its name here.
    public static let registeredModules: Set<String> = ["LedgerAppKit", "LedgerDesign", "LedgerWatchAppKit"]

    /// `LedgerKit/Sources`, found from this file's place in the repository.
    public static let sourcesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent() // Previews
        .deletingLastPathComponent() // LedgerTestSupport
        .deletingLastPathComponent() // Sources

    /// The name of each `#Preview` in `module`'s sources, in file order; nil for a preview with no name.
    public static func previews(inModule module: String) throws -> [String?] {
        try swiftFiles(in: sourcesDirectory.appending(path: module, directoryHint: .isDirectory))
            .flatMap { try previews(in: String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Every module under `Sources` with at least one `#Preview`.
    public static func modulesWithPreviews() throws -> Set<String> {
        let entries = try FileManager.default.contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
        let modules = entries.filter(\.hasDirectoryPath).map(\.lastPathComponent)
        return try Set(modules.filter { try !previews(inModule: $0).isEmpty })
    }

    /// The `#Preview` declarations in `source`: a line (`\n`, `\r\n` or `\r`) that starts with `#Preview`, after any
    /// attributes such as `@available(iOS 18, *)`, so a comment or a string that mentions one is not counted. The name
    /// is
    /// the first argument when it is a string literal.
    public static func previews(in source: String) -> [String?] {
        source.split(whereSeparator: \.isNewline).compactMap { line -> String?? in
            let code = droppingAttributes(line.drop(while: \.isWhitespace))
            guard code.hasPrefix("#Preview") else {
                return nil
            }
            let rest = code.dropFirst("#Preview".count)
            guard rest.first.map({ $0 == "(" || $0 == "{" || $0.isWhitespace }) ?? true else {
                return nil // another macro, such as `#PreviewFoo`
            }
            let arguments = rest.drop(while: \.isWhitespace)
            let first = arguments.hasPrefix("(") ? arguments.dropFirst().drop(while: \.isWhitespace) : ""
            guard first.hasPrefix("\""), let end = first.dropFirst().firstIndex(of: "\"") else {
                return .some(nil)
            }
            return .some(String(first.dropFirst()[..<end]))
        }
    }

    /// `code` without its leading attributes (`@name`, each with an optional balanced `(…)`) and the space after them.
    static func droppingAttributes(_ code: Substring) -> Substring {
        var rest = code
        while rest.first == "@" {
            rest = rest.dropFirst().drop { $0.isLetter || $0.isNumber || $0 == "_" }
            if rest.first == "(" {
                var depth = 0
                let close = rest.firstIndex { character in
                    depth += character == "(" ? 1 : character == ")" ? -1 : 0
                    return depth == 0
                }
                rest = close.map { rest[rest.index(after: $0)...] } ?? ""
            }
            rest = rest.drop(while: \.isWhitespace)
        }
        return rest
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
