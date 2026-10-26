#if os(iOS)
    @testable import LedgerDesign
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// The placeholder a hosted `SearchField` draws, its width and the width it is drawn in, in points.
    struct SearchFieldDrawn {
        let shown: String
        let needed: CGFloat
        let room: CGFloat
        /// The text field's own width, which is the width SwiftUI lays it out at.
        let field: CGFloat
    }

    extension RenderingSuites {
        /// F12 S1 review M1 (b): `SearchField`'s placeholder fits the field it stands in, measured on the hosted
        /// `UITextField`: the drawn placeholder's own width against the width UIKit draws it in
        /// (`placeholderRect(forBounds:)`), on phones 320 to 440 pt wide with the screen's margins (393, 430 and 440
        /// since review R2-2). Measured before the fix: "Search 224 exercises" needed 312 pt at `.accessibility3`
        /// and 420 at `.accessibility5`, against 291 on a 375-pt phone and 306 on a 390-pt one, so it was cut short
        /// ("…") on both, and from `.accessibility2` on a 320-pt one. A field given a short placeholder now draws
        /// that one instead.
        @Suite("SearchField fit", .serialized, .tags(.design))
        struct SearchFieldFitTests {
            nonisolated static let widths: [CGFloat] = [320, 375, 390, 393, 402, 430, 440]
            nonisolated static let sizes = TestSweep.sizes(DynamicTypeSize.allCases)

            /// The drawn placeholder, its width and the width it is drawn in, in points, for `field` hosted on a
            /// phone `width` points wide at `size`.
            static func measure(
                _ field: some View,
                width: CGFloat,
                size: DynamicTypeSize
            ) throws -> SearchFieldDrawn {
                let view = field
                    .padding(.horizontal, LedgerSpacing.screen)
                    .frame(width: width)
                    .environment(\.dynamicTypeSize, size)
                let host = UIHostingController(rootView: view)
                let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: width, height: 400))
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                // Twice: the field picks its placeholder from the widths the first layout measured.
                for _ in 0 ..< 2 {
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date())
                }
                host.view.layoutIfNeeded()
                let textField = try #require(FieldFontTests.field(in: host.view), "no text field")
                let placeholder = try #require(textField.attributedPlaceholder, "no placeholder")
                let room = textField.placeholderRect(forBounds: textField.bounds).width
                return SearchFieldDrawn(
                    shown: placeholder.string,
                    needed: ceil(placeholder.size().width),
                    room: room,
                    field: textField.bounds.width
                )
            }

            static let library = SearchField("Search 224 exercises", short: "Search", text: "") { _ in }

            @Test(
                "The Library's placeholder is drawn whole where it fits, and short where it does not",
                arguments: widths, sizes
            )
            func libraryPlaceholder_fitsOrIsShort(_ width: CGFloat, _ size: DynamicTypeSize) throws {
                let drawn = try Self.measure(Self.library, width: width, size: size)
                #expect(drawn.needed <= drawn.room, "\(width) pt, \(size): \(drawn)")
                #expect(["Search 224 exercises", "Search"].contains(drawn.shown))
                // Review R2-2: UIKit's placeholder rect is inset from the field by no more than the field's margin.
                #expect(drawn.field - drawn.room <= SearchField.placeholderMargin, "\(width) pt, \(size): \(drawn)")
            }

            @Test("On the iPhone 17 at the default size the placeholder is the whole one")
            func libraryPlaceholder_isWholeAtTheDefaultSize() throws {
                #expect(try Self.measure(Self.library, width: 402, size: .large).shown == "Search 224 exercises")
                #expect(try Self.measure(Self.library, width: 375, size: .xxxLarge).shown == "Search 224 exercises")
            }

            @Test("Control: without a short placeholder the whole one is drawn, and at the largest size does not fit")
            func control_wholePlaceholder_doesNotFitAtTheLargestSize() throws {
                let field = SearchField("Search 224 exercises", text: "") { _ in }
                let drawn = try Self.measure(field, width: 375, size: .accessibility5)
                #expect(drawn.shown == "Search 224 exercises")
                #expect(drawn.needed > drawn.room, "the control fits: \(drawn)")
            }

            /// Measured before the fix: "Search exercises" needed 337 pt at `.accessibility5`, against 318 on the
            /// iPhone 17, and 250 at `.accessibility3` against 236 on a 320-pt phone.
            @Test("The exercise library's placeholder fits too, short where it must be", arguments: widths, sizes)
            func pickerPlaceholder_fits(_ width: CGFloat, _ size: DynamicTypeSize) throws {
                let field = SearchField("Search exercises", short: "Search", text: "") { _ in }
                let drawn = try Self.measure(field, width: width, size: size)
                #expect(drawn.needed <= drawn.room, "\(width) pt, \(size): \(drawn)")
            }
        }
    }
#endif
