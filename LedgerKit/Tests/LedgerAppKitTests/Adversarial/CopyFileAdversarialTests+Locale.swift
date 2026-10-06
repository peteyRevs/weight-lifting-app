import Foundation
import LedgerTestSupport
import Testing

/// Standards §7, "Copy file": a lookup is written "with `locale:` when it formats a number (the caller passes the
/// injected `@Dependency(\.locale)`, so a test fixes the digits and their grouping)". A `%lld` key formats a number.
nonisolated extension CopyFileAdversarialTests {
    @Test(
        "A lookup that formats a number without `locale:` is a finding",
        arguments: ["%lld sets", "Week %lld of %lld"]
    )
    func lookupThatFormatsANumber_withoutALocale_isAFinding(key: String) throws {
        let literal = "\"" + key.replacingOccurrences(of: "%lld", with: "\\(count)") + "\""
        let catalog = [AdversarialCatalog.plain(key)]
        let withLocale = Self.counted("_ count: Int", literal)
        #expect(try AdversarialModule.findings(copy: withLocale, catalog: catalog).isEmpty, "control: with a locale")
        let without = Self.lookup("_ count: Int", literal)
        let findings = try AdversarialModule.findings(copy: without, catalog: catalog)
        #expect(findings.contains { $0.contains("FixtureCopy.swift") }, "no finding for: \(without)")
    }
}
