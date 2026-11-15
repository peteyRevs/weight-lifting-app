import Foundation
import LedgerTestSupport
import Testing

/// F15 criterion 8: `docs/accessibility-labels.md` lists every icon-only button in `LedgerKit/Sources` and the words
/// VoiceOver reads for it, and cannot drift from the sources silently. Read from the repository, as `ModuleCopyTests`
/// and `ProgramViewsSourceAdversarialTests` read it: every icon-only call has a row; every row's call is still in
/// its file; every row's copy still holds its English words; every row names a test file that exists.
@Suite("Accessibility labels document")
nonisolated struct AccessibilityLabelsDocTests {
    /// One row of the document's tables.
    struct Row: Equatable {
        let source: String
        let call: String
        let copy: String
        let english: String
        let pinnedBy: String
    }

    /// An icon-only button found in the sources: its file under `Sources` and its line, trimmed.
    struct Site: Hashable {
        let source: String
        let line: String
    }

    static let sources = PreviewScan.sourcesDirectory
    static let document = sources.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/accessibility-labels.md")

    /// The rows of every table whose header starts with "| Control |".
    static func rows() throws -> [Row] {
        let lines = try String(contentsOf: document, encoding: .utf8).components(separatedBy: "\n")
        return lines.filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Control |") }.map { line in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            return Row(source: cells[1], call: cells[2], copy: cells[3], english: cells[4], pinnedBy: cells[5])
        }
    }

    /// Every icon-only button of the sources (the document's rule): an `IconPillButton(` call, or a `Button` whose
    /// label is only a `LedgerIconView` or a `SetRowCheck`. Previews, galleries and the component's own file are not
    /// counted.
    static func sites() throws -> Set<Site> {
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path(percentEncoded: false))
            .filter { $0.hasSuffix(".swift") && !$0.contains("Previews") && !$0.contains("Gallery/") }
            .filter { $0 != "LedgerDesign/Components/IconPillButton.swift" }
        var found: Set<Site> = []
        for file in files {
            let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            for (index, line) in lines.enumerated() where !line.hasPrefix("//") {
                let afterLabel = index > 0 && lines[index - 1].hasSuffix("label: {")
                    && (line.hasPrefix("LedgerIconView(") || line.hasPrefix("SetRowCheck("))
                let sameLine = line.hasPrefix("Button(") && line.contains("{ SetRowCheck(")
                    || line.hasPrefix("Button(") && line.contains("{ LedgerIconView(")
                if line.hasPrefix("IconPillButton(") || afterLabel || sameLine {
                    found.insert(Site(source: file, line: line))
                }
            }
        }
        return found
    }

    @Test("The document lists rows, and the sources hold icon-only buttons: the scan reads both")
    func scan_readsBoth() throws {
        let (rows, sites) = try (Self.rows(), Self.sites())
        #expect(rows.count >= 9, "\(rows.count) rows")
        #expect(sites.count >= 7, "\(sites.count) sites")
    }

    @Test("Every icon-only button in the sources has a row, and every row's call is still in its file")
    func everyButton_hasARow_andEveryRowAButton() throws {
        let (rows, sites) = try (Self.rows(), Self.sites())
        let matches = { (site: Site, row: Row) in site.source == row.source && site.line.hasPrefix(row.call) }
        let unlisted = sites.filter { site in !rows.contains { matches(site, $0) } }
        let stale = rows.filter { row in !sites.contains { matches($0, row) } }
        let isExact = unlisted.isEmpty && stale.isEmpty
        #expect(isExact, "not in the document: \(unlisted.map(\.line)); not in the sources: \(stale.map(\.call))")
    }

    @Test("Every row's copy holds its English words, and its pinning test exists")
    func everyRow_copyMatches_andItsTestExists() throws {
        let tests = try FileManager.default.subpathsOfDirectory(atPath: Self.sources.deletingLastPathComponent()
            .appending(path: "Tests").path(percentEncoded: false))
        for row in try Self.rows() {
            #expect(tests.contains { $0.hasSuffix("/\(row.pinnedBy).swift") }, "no test \(row.pinnedBy)")
            guard row.copy != "—" else {
                continue
            }
            let parts = row.copy.split(separator: ".")
            let words = try Self.copy(named: String(parts[1]), of: String(parts[0]))
            #expect(words == row.english, "\(row.copy) says \(words ?? "nothing")")
        }
    }

    /// The English words of `name`, a static property or function of `type`, in the files of any module named for
    /// `type`: the `localized:` literal that follows its declaration. A design component's words are the feature's.
    static func copy(named name: String, of type: String) throws -> String? {
        let directory = sources
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path(percentEncoded: false))
        for file in files where file.hasSuffix(".swift") && (file as NSString).lastPathComponent.hasPrefix(type) {
            let lines = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
                .components(separatedBy: "\n")
            guard let start = lines.firstIndex(where: {
                $0.contains("static var \(name):") || $0.contains("static func \(name)(")
            }) else { continue }
            for line in lines[start ..< min(start + 6, lines.count)] {
                if let range = line.range(of: #"(?<=localized: ")[^"]*"#, options: .regularExpression) {
                    return String(line[range])
                }
            }
        }
        return nil
    }
}
