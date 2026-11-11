#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F14 S3 (G3 N2): `SheetChrome`'s cancel switched off, for a sheet whose work cannot be stopped once begun
        /// ("Delete all data" while it erases). The title still reads as it did; only the cancel is dimmed, and
        /// neither it nor the escape gesture cancels.
        @Suite("SheetChrome · cancel switched off", .tags(.design))
        struct SheetChromeCancelTests {
            @Test("With cancelEnabled false the cancel is dimmed and does nothing; the title is not dimmed")
            func cancelDisabled_isDimmedAndInert() throws {
                var cancels = 0
                let sheet = SheetChrome("Delete all data", cancel: "Cancel", cancelEnabled: false) {
                    cancels += 1
                } content: {
                    EmptyView()
                }
                let elements = sheet.accessibilityElements()
                let title = try #require(elements.first { $0.label == "Delete all data" })
                let cancel = try #require(elements.first { $0.label == "Cancel" })
                #expect(!title.traits.contains(.notEnabled))
                #expect(cancel.traits.contains(.notEnabled))
                sheet.withAccessibilityElements { live in
                    _ = live.first { $0.accessibilityLabel == "Cancel" }?.accessibilityActivate()
                }
                #expect(cancels == 0)
            }
        }
    }
#endif
