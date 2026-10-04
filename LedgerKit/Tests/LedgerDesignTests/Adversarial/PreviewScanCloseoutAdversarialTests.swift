import LedgerTestSupport
import Testing

/// F07 S3 fix round 1 verification: `PreviewScan`'s attribute skipper and newline split. Each source below compiles
/// (checked with `swiftc -typecheck` on the Mac).
@Suite("Adversarial F07 S3 close-out · preview scan")
struct PreviewScanCloseoutAdversarialTests {
    @Test("Two attributes, nested parentheses, CR alone as a newline, and a non-preview after an attribute")
    func attributes_andNewlines_held() {
        let source = """
        @available(iOS 18, *) @available(watchOS 11, *) #Preview("Two") {}\r#Preview("AfterCR") {}
        @MainActor func notAPreview() {}
        @available(iOS 18, *) // #Preview("In a comment")
        @available(iOS 18, *) let text = "#Preview(\\"In a string\\")"
        """
        #expect(PreviewScan.previews(in: source) == ["Two", "AfterCR"])
    }

    // F7-S3-3, accepted (orchestrator ruling, F07 S3 close-out): a line scanner cannot chase every form Swift accepts
    // without becoming a parser, and testing-strategy §2.6 says to declare a preview at the start of a line, after any
    // balanced single-line attributes. These three forms compile but are outside that rule; the tests pin that the
    // scan does not find them, so a change in either direction is noticed.

    @Test("F7-S3-3 (documents): an attribute whose string argument holds a parenthesis hides the preview from the scan")
    func parenthesisInAttributeString_found() {
        let source = #"@available(*, deprecated, message: "use Y (new") #Preview("Paren") {}"#
        #expect(PreviewScan.previews(in: source) == [])
    }

    @Test("F7-S3-3 (documents): a block comment before #Preview on its line hides it from the scan")
    func blockCommentBeforePreview_found() {
        #expect(PreviewScan.previews(in: #"/* the old one */ #Preview("Commented") {}"#) == [])
    }

    @Test("F7-S3-3 (documents): an attribute split over two lines hides the #Preview after it from the scan")
    func attributeOverTwoLines_found() {
        let source = "@available(iOS 18,\n    *) #Preview(\"Split\") {}"
        #expect(PreviewScan.previews(in: source) == [])
    }
}
