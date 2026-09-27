import Foundation
import Testing

/// Criterion 14 / engineering-standards §2: LedgerDomain imports Foundation and nothing else.
/// `scripts/check-package-graph.sh` pins the target's dependency edges (none); this test pins the
/// `import` statements. It reads the module's own source tree next to this file — the one
/// deliberate file-system read in the domain tests (read-only, inside the repository).
@Suite("LedgerDomain module boundary", .tags(.domain))
struct ModuleBoundaryTests {
    private static let sourcesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent() // LedgerDomainTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LedgerKit
        .appending(path: "Sources/LedgerDomain", directoryHint: .isDirectory)

    /// The module named by an `import` line (`@testable import X`, `import struct X.Y`, …), or nil.
    static func importedModule(in line: String) -> String? {
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = tokens.first, first.hasPrefix("@") {
            tokens.removeFirst()
        }
        guard tokens.first == "import", let path = tokens.last, tokens.count >= 2 else {
            return nil
        }
        return path.split(separator: ".").first.map(String.init)
    }

    @Test("The import parser finds modules in every import form")
    func importedModule_parsesImportForms() {
        #expect(Self.importedModule(in: "import Foundation") == "Foundation")
        #expect(Self.importedModule(in: "  @testable import LedgerDomain") == "LedgerDomain")
        #expect(Self.importedModule(in: "@_exported import SwiftUI") == "SwiftUI")
        #expect(Self.importedModule(in: "import struct Foundation.Date") == "Foundation")
        #expect(Self.importedModule(in: "// import UIKit is not an import") == nil)
        #expect(Self.importedModule(in: "import") == nil)
        #expect(Self.importedModule(in: "let important = 1") == nil)
    }

    @Test("LedgerDomain sources import Foundation only (criterion 14)")
    func sources_importFoundationOnly() throws {
        let enumerator = try #require(FileManager.default.enumerator(
            at: Self.sourcesDirectory,
            includingPropertiesForKeys: nil
        ))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count >= 30, "found \(files.count) Swift files under \(Self.sourcesDirectory.path)")
        var modules: [String: Set<String>] = [:]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let module = Self.importedModule(in: String(line)) {
                    modules[module, default: []].insert(file.lastPathComponent)
                }
            }
        }
        #expect(Set(modules.keys) == ["Foundation"], "imports: \(modules)")
    }
}
