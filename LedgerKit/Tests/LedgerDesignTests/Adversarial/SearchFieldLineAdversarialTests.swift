#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F12 S1 adversarial round 1 (G2), finding F12-S1-1: `SearchField`, moved into LedgerDesign for the
        /// Library, sets its text with `ledgerFont(.body)`, the role's own line of 1.2, not with
        /// `ledgerFieldFont(.body)`'s 1.3. `ledgerFieldFont`'s doc comment and F11 S10's ruling 22 say why that
        /// matters: UIKit clips an edited field's text to its line, and 1.2 cuts the tails from
        /// `.accessibility3`. The running app shows it: "lying" typed into the Library's field at
        /// Accessibility XXXL loses the bottoms of its y and g (the round's pictures), and the system's audit
        /// reports "Text clipped" on the field. Measured as `FieldFontTests` measures a field: "Gyp" in the
        /// component itself, edited, against a text of the body role, light on black at 3×.
        @Suite("SearchField line (adversarial, F12 S1)", .tags(.design))
        struct SearchFieldLineAdversarialTests {
            nonisolated static let sizes = TestSweep.sizes([DynamicTypeSize.large, .accessibility3, .accessibility5])

            /// `view` on black, in the dark theme, where the field's ink is light and its hairline too faint to
            /// count as ink.
            static func onBlack(_ view: some View) -> some View {
                view
                    .padding(LedgerSpacing.xxl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
            }

            @Test("The Library's search field draws a query's tails whole while it is edited, at every size")
            func searchField_edited_drawsItsTailsWhole() throws {
                for size in Self.sizes {
                    let text = try FieldFontTests.ink(
                        Self.onBlack(Text("Gyp").ledgerFont(.body).foregroundStyle(Color.white)),
                        at: size,
                        isEdited: false
                    )
                    let field = try FieldFontTests.ink(
                        Self.onBlack(SearchField("", text: "Gyp") { _ in }),
                        at: size,
                        isEdited: true
                    )
                    // A pixel of the drawing at 3× is a third of a point.
                    #expect(
                        field.height > text.height - 0.34,
                        "\(size): the tails are cut: text \(text), field \(field)"
                    )
                }
            }
        }
    }
#endif
