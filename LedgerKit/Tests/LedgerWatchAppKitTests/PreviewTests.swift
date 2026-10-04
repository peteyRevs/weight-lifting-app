#if DEBUG
    import LedgerSnapshotTesting
    import LedgerTestSupport
    @testable import LedgerWatchAppKit
    import SwiftUI
    import Testing

    /// F07 criterion 8 for LedgerWatchAppKit: every `#Preview` is a case of `WatchPreview`, and every case renders.
    @Suite("Previews (LedgerWatchAppKit)", .serialized)
    struct PreviewTests {
        @Test("Every #Preview in LedgerWatchAppKit is a WatchPreview case, by name, and every case has its #Preview")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "LedgerWatchAppKit")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(WatchPreview.allCases.map(\.rawValue)))
        }

        @Test("Every preview renders", arguments: WatchPreview.allCases)
        func preview_renders(_ preview: WatchPreview) {
            #expect(renderPreview(preview.content, size: WatchSize.mm46.size))
        }
    }
#endif
