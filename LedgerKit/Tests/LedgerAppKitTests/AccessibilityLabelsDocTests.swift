import Foundation
import LedgerTestSupport
import Testing

/// F15 criterion 8: `docs/accessibility-labels.md` lists every icon-only button in `LedgerKit/Sources` and the words
/// VoiceOver reads for it, bound to the shipped label, and cannot drift from the sources silently. Read from the
/// repository, as `ModuleCopyTests` and `ProgramViewsSourceAdversarialTests` read it:
/// - every icon-only call has a row, and every row's call is still in its file;
/// - every row's copy holds its English words;
/// - every row's "Wired by" file names its copy;
/// - every row's "Pinned by" file holds its words or its copy (its component, for a row with no copy).
@Suite("Accessibility labels document")
nonisolated struct AccessibilityLabelsDocTests {
    /// One row of the document's tables.
    struct Row: Equatable {
        let source: String
        let call: String
        let wiredBy: String
        let copy: String
        let english: String
        let pinnedBy: String
    }

    /// A table row with fewer cells than a row has.
    struct MalformedRow: Error, CustomStringConvertible {
        let line: String
        var description: String {
            "a row of docs/accessibility-labels.md has not seven cells: \(line)"
        }
    }

    /// An icon-only button found in the sources: its file under `Sources` and its line, trimmed.
    struct Site: Hashable {
        let source: String
        let line: String
    }

    static let sources = PreviewScan.sourcesDirectory
    static let tests = sources.deletingLastPathComponent().appending(path: "Tests")
    static let document = sources.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/accessibility-labels.md")

    /// The rows of every table whose header starts with "| Control |".
    static func rows(in text: String) throws -> [Row] {
        try text.components(separatedBy: "\n").filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Control |") }.map {
            let cells = $0.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            guard cells.count == 7 else {
                throw MalformedRow(line: $0)
            }
            return Row(
                source: cells[1], call: cells[2], wiredBy: cells[3], copy: cells[4], english: cells[5],
                pinnedBy: cells[6]
            )
        }
    }

    static func rows() throws -> [Row] {
        try rows(in: String(contentsOf: document, encoding: .utf8))
    }

    /// The icon-only buttons of one file's `text` (the document's rule): an `IconPillButton(` call; a `Button` or a
    /// `Menu` whose label starts with an icon, inside its braces on the same line or on the line after its opening
    /// brace or `label: {`; anything given `.labelStyle(.iconOnly)`. Comments are not read.
    static func sites(in text: String, file: String) -> Set<Site> {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let icons = ["LedgerIconView(", "SetRowCheck(", "Image("]
        let opensALabel = { (line: String) in
            line.hasSuffix("label: {")
                || ["Button(", "Button {", "Menu(", "Menu {"].contains { line.hasPrefix($0) } && line.hasSuffix("{")
        }
        var found: Set<Site> = []
        for (index, line) in lines.enumerated() where !line.hasPrefix("//") {
            let afterLabel = index > 0 && opensALabel(lines[index - 1]) && icons.contains { line.hasPrefix($0) }
            let sameLine = ["Button(", "Button {", "Menu(", "Menu {"].contains { line.hasPrefix($0) }
                && icons.contains { line.contains("{ \($0)") }
            let iconOnly = line.contains(".labelStyle(.iconOnly)")
            if line.hasPrefix("IconPillButton(") || afterLabel || sameLine || iconOnly {
                found.insert(Site(source: file, line: line))
            }
        }
        return found
    }

    /// Every icon-only button of the sources. Previews, galleries and the component's own file are not counted.
    static func sites() throws -> Set<Site> {
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path(percentEncoded: false))
            .filter { $0.hasSuffix(".swift") && !$0.contains("Previews") && !$0.contains("Gallery/") }
            .filter { $0 != "LedgerDesign/Components/IconPillButton.swift" }
        var found: Set<Site> = []
        for file in files {
            let text = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            found.formUnion(sites(in: text, file: file))
        }
        return found
    }

    /// The text of the first file under `directory` named `name`.
    static func file(named name: String, under directory: URL) throws -> String? {
        let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path(percentEncoded: false))
        return try paths.first { ($0 as NSString).lastPathComponent == name }
            .map { try String(contentsOf: directory.appending(path: $0), encoding: .utf8) }
    }

    @Test("The document lists rows, and the sources hold icon-only buttons: the scan reads both")
    func scan_readsBoth() throws {
        let (rows, sites) = try (Self.rows(), Self.sites())
        #expect(rows.count >= 13, "\(rows.count) rows")
        #expect(sites.count >= 8, "\(sites.count) sites")
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

    @Test("Every row's copy holds its English words, its wiring names the copy, and its pin holds the words")
    func everyRow_isBoundToItsCopyWiringAndPin() throws {
        for row in try Self.rows() {
            let pin = try #require(try Self.file(named: "\(row.pinnedBy).swift", under: Self.tests), "\(row.pinnedBy)")
            guard row.copy != "—" else {
                let component = ((row.source as NSString).lastPathComponent as NSString).deletingPathExtension
                #expect(pin.contains(component), "\(row.pinnedBy) does not name \(component)")
                continue
            }
            let parts = row.copy.split(separator: ".").map(String.init)
            let words = try Self.copy(named: parts[1], of: parts[0])
            #expect(words == row.english, "\(row.copy) says \(words ?? "nothing")")
            let wiring = try Self.file(named: row.wiredBy, under: Self.sources)
            #expect(wiring.map { Self.names($0, row.copy) } == true, "\(row.wiredBy) does not name \(row.copy)")
            let spoken = pin.range(of: Self.spoken(row.english), options: .regularExpression) != nil
            let pinned = Self.names(pin, row.copy) || spoken
            #expect(pinned, "\(row.pinnedBy) holds neither \(row.english) nor \(row.copy)")
        }
    }

    /// Whether `text` names `reference` (`WorkoutCopy.logSet`) as a whole name: not as the start of a longer one
    /// (`WorkoutCopy.logSetHeavy`).
    static func names(_ text: String, _ reference: String) -> Bool {
        let pattern = NSRegularExpression.escapedPattern(for: reference) + "(?![A-Za-z0-9_])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// `english` as a pattern of a quoted string: each `\(…)` stands for any text.
    static func spoken(_ english: String) -> String {
        let parts = english.components(separatedBy: #"\("#).enumerated().map { index, part in
            let literal = index == 0 ? part : String(part.drop { $0 != ")" }.dropFirst())
            return NSRegularExpression.escapedPattern(for: literal)
        }
        return "\"" + parts.joined(separator: "[^\"]+") + "\""
    }

    /// The English words of `name`, a static property or function of `type`, in the files of any module named for
    /// `type`: the `localized:` literal that follows its declaration. A design component's words are the feature's.
    static func copy(named name: String, of type: String) throws -> String? {
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path(percentEncoded: false))
        for file in files where file.hasSuffix(".swift") && (file as NSString).lastPathComponent.hasPrefix(type) {
            let lines = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
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

extension AccessibilityLabelsDocTests {
    /// G3 S3: each form of an icon-only button is found, and a button that draws its words is not.
    @Test("The scan finds every form of icon-only button, and no button with words", arguments: [
        ("IconPillButton(\"Add\", icon: .plus) {}", 1),
        ("Button(action: add) {\n    Image(systemName: \"plus\")\n}", 1),
        ("Button {\n    Image(\"gear\")\n}", 1),
        ("Button {\n    add()\n} label: {\n    LedgerIconView(.plus, sizedAs: .body)\n}", 1),
        ("Menu {\n    Picker(\"Day\", selection: $day) {}\n} label: {\n    Image(systemName: \"ellipsis\")\n}", 1),
        ("Button(action: check) { SetRowCheck(state: state) }", 1),
        ("Label(\"Add\", systemImage: \"plus\")\n    .labelStyle(.iconOnly)", 1),
        ("Button(\"Finish\") { finish() }", 0),
        ("Button(action: add) {\n    Text(\"Add\")\n}", 0),
        ("// Button(action: add) { Image(systemName: \"plus\") }", 0)
    ])
    func scan_findsEachForm(_ fixture: String, _ count: Int) {
        #expect(Self.sites(in: fixture, file: "Fixture.swift").count == count, "\(fixture)")
    }

    /// G3 N11: a copy is named by its whole name only.
    @Test("A copy's name is found whole, never as the start of a longer name", arguments: [
        ("check: WorkoutCopy.logSet(number, locale: locale)", true),
        ("WorkoutCopy.logSet\n", true),
        ("check: WorkoutCopy.logSetHeavy(number, locale: locale)", false),
        ("WorkoutCopy.logSet_2", false)
    ])
    func names_matchTheWholeName(_ text: String, _ isNamed: Bool) {
        #expect(Self.names(text, "WorkoutCopy.logSet") == isNamed, "\(text)")
    }

    /// G3 N6: a malformed row fails with its line, never by a crash.
    @Test("A row with too few cells fails, naming the row")
    func malformedRow_failsWithItsLine() {
        let error = #expect(throws: MalformedRow.self) {
            try Self.rows(in: "| Control | Source |\n|---|---|\n| Gear | `A.swift` |")
        }
        #expect(error?.line == "| Gear | `A.swift` |")
    }
}
