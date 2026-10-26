#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S3 (flag A3): `ReceiptLayout`'s optional row action. Each row, activated, hands back its place in the
    /// model's rows; without the action nothing on the receipt is a control. A row with the action is drawn as it
    /// was: F10's receipt references (`ReceiptTests`), drawn with the action since F12 S3, are unchanged.
    @Suite("ReceiptLayout row action", .serialized, .tags(.design))
    struct ReceiptLayoutRowActionTests {
        @Test("Each row is a button that hands back its own place; without the action there is none")
        func rows_handBackTheirPlaces() {
            var tapped: [Int] = []
            let count = ReceiptLayoutGallery { tapped.append($0) }.withAccessibilityElements { elements in
                let buttons = elements.filter { $0.accessibilityTraits.contains(.button) }
                for button in buttons {
                    _ = button.accessibilityActivate()
                }
                return buttons.count
            }
            #expect(count == ReceiptLayoutGallery.model.rows.count)
            #expect(tapped == Array(ReceiptLayoutGallery.model.rows.indices))
            let plain = ReceiptLayoutGallery().withAccessibilityElements { elements in
                elements.count { $0.accessibilityTraits.contains(.button) }
            }
            #expect(plain == 0)
        }
    }
#endif
