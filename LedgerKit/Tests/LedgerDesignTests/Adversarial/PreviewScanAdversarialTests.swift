import LedgerTestSupport
import Testing

/// F07 S3 adversarial round 1: `PreviewScan` (criterion 8) against `#Preview` declarations Swift accepts but the scan
/// could miss. A preview the scan misses is never checked against the registry, so it could crash at render with no
/// test noticing.
@Suite("Adversarial F07 S3 · preview scan")
struct PreviewScanAdversarialTests {
    /// Swift accepts `@available` before `#Preview` on one line (checked with `swiftc -typecheck`), the usual way to
    /// preview a view that needs a newer OS than the package's deployment target.
    @Test("F7-S3-1: a #Preview after @available on the same line is found")
    func attributedPreview_isFound() {
        let source = """
        @available(iOS 18, watchOS 11, *) #Preview("Attributed") {
            Text("x")
        }
            @available(iOS 18, *) #Preview {}
        """
        #expect(PreviewScan.previews(in: source) == ["Attributed", nil])
    }

    @Test("F7-S3-1: a file saved with CRLF line endings has every one of its previews found")
    func crlfFile_everyPreviewFound() {
        let source = "import SwiftUI\r\n#Preview(\"A\") {\r\n    Text(\"a\")\r\n}\r\n#Preview(\"B\") {}\r\n"
        #expect(PreviewScan.previews(in: source) == ["A", "B"])
    }

    @Test("A preview on the line after its attribute, or with tabs before it, is found")
    func attributeOnPreviousLine_andTabs_areFound() {
        let source = "@available(iOS 18, *)\n#Preview(\"Next line\") {}\n\t\t#Preview(\"Tabbed\") {}\n"
        #expect(PreviewScan.previews(in: source) == ["Next line", "Tabbed"])
    }
}
