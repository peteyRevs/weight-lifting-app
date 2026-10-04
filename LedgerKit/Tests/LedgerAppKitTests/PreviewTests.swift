#if DEBUG
    @testable import LedgerAppKit
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F07 criterion 8 for LedgerAppKit: every `#Preview` is a case of `AppPreview`, and every case renders.
    @Suite("Previews (LedgerAppKit)", .serialized)
    struct PreviewTests {
        @Test("Every #Preview in LedgerAppKit is an AppPreview case, by name, and every case has its #Preview")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "LedgerAppKit")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(AppPreview.allCases.map(\.rawValue)))
        }

        @Test("Every preview renders", arguments: AppPreview.allCases)
        func preview_renders(_ preview: AppPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }
    }
#endif
