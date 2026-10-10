#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S10, gate G2, round 1, criteria 2 and 11 and the implementer's finding 2: what the pinned header
    /// leaves the page on an iPhone 17 and on a phone of the 375 × 667 class, measured on the hosted screen.
    /// The simulator's window keeps 62 pt above the screen whatever its size, so each phone is hosted as high
    /// as it leaves the screen under its own top inset. (`SceneLessWindow` is internal to
    /// `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("Adversarial F11 S10 · the room under the pinned header", .serialized, .tags(.feature))
    struct DayEditorViewsRoomAdversarialTests {
        /// A phone's screen in points, and what stands above the screen's content on it.
        nonisolated struct Phone: Sendable, CustomTestStringConvertible {
            let name: String
            let size: CGSize
            let topInset: CGFloat

            static let iPhone17 = Phone(name: "iPhone 17", size: CGSize(width: 402, height: 874), topInset: 62)
            /// An iPhone SE: a status bar of 20 pt.
            static let small = Phone(name: "375 × 667", size: CGSize(width: 375, height: 667), topInset: 20)

            var testDescription: String {
                name
            }
        }

        /// The Day editor's screen as it was hosted: how high its pinned header is, and its page's room.
        struct Hosted {
            var header: CGFloat = 0
            var page: CGFloat = 0
            var dismissMode = UIScrollView.KeyboardDismissMode.none
        }

        /// The screen of Upper A, every exercise closed, hosted with `height` points under the top inset.
        static func hosted(width: CGFloat, height: CGFloat, at size: DynamicTypeSize) throws -> Hosted {
            let screen = try DayEditorScreen(model: ProgramPreview.dayEditor.dayEditorModel()) { _ in }
            let host = UIHostingController(rootView: screen.environment(\.dynamicTypeSize, size))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: width, height: height + 200))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            // The window's own inset is the simulator's; the screen is given `height` under it.
            host.additionalSafeAreaInsets.bottom = 200 - host.view.safeAreaInsets.top
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            func found(in view: UIView) -> [UIScrollView] {
                ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(found(in:))
            }
            let scrolls = found(in: host.view)
            try #require(scrolls.count == 1, "\(scrolls.count) scroll views")
            let frame = scrolls[0].convert(scrolls[0].bounds, to: host.view)
            let top = host.view.safeAreaInsets.top
            return Hosted(
                header: frame.minY - top, page: top + height - frame.minY,
                dismissMode: scrolls[0].keyboardDismissMode
            )
        }

        /// The height of a closed row of Upper A on a phone `width` wide.
        static func rowHeight(at size: DynamicTypeSize, width: CGFloat) throws -> CGFloat {
            let bench = try #require(ProgramPreview.dayEditor.dayEditorModel().rows.first)
            let row = ExerciseRow(row: bench) { _ in }.padding(.horizontal, LedgerSpacing.screen)
            return try CGFloat(ProgramDrawing.pixels(of: row.environment(\.dynamicTypeSize, size), .light, width: width)
                .height)
        }

        /// **FINDING F11-S10-2** (should fix). `DayEditorScreen` stacks the header over the scroll view with
        /// nothing that keeps the header at its own height, so the stack offers it half of the screen first
        /// and a header that needs more is squeezed: its text is cut to fit. Upper A's header needs 325 pt
        /// at `.accessibility5` on a 375 pt phone; with the 647 pt an iPhone SE leaves under its status bar
        /// the header gets 323.5, and less under any bar the app adds. Fails at `.accessibility5`.
        @Test(
            "The pinned header keeps its own height on a 375 × 667 phone, however little room the screen has",
            arguments: [DynamicTypeSize.accessibility3, .accessibility4, .accessibility5]
        )
        func smallPhone_headerIsNotSqueezed(_ size: DynamicTypeSize) throws {
            let phone = Phone.small
            let own = try Self.hosted(width: phone.size.width, height: 3000, at: size).header
            for (what, height) in [
                ("the whole screen", phone.size.height - phone.topInset),
                ("under a 44 pt bar", 603)
            ] {
                let given = try Self.hosted(width: phone.size.width, height: height, at: size).header
                #expect(abs(given - own) < 1, "\(what): the header needs \(own) pt and is given \(given)")
            }
        }

        /// The implementer's finding 2, measured on the hosted screen and counted in closed rows of the seed
        /// program: a question for the product owner, not a defect, so the sizes that leave under two rows
        /// are a known issue. Measured: 375 × 667 shows 7.0 rows at `.large`, 2.1 at `.accessibility2`, 1.5
        /// at `.accessibility3`, 1.2 and 0.8 at the two largest; an iPhone 17 9.4, 3.0, 2.1, 1.8 and 1.5.
        @Test(
            "Under the pinned header the page shows at least two closed rows",
            arguments: [Phone.iPhone17, .small], DynamicTypeSize.allCases
        )
        func page_showsAtLeastTwoRows(_ phone: Phone, _ size: DynamicTypeSize) throws {
            let hosted = try Self.hosted(width: phone.size.width, height: phone.size.height - phone.topInset, at: size)
            let rows = try hosted.page / Self.rowHeight(at: size, width: phone.size.width)
            // Fix round 1 (ruling 14, the orchestrator's ruling on this line): with the bar alone pinned, the
            // cells that still show under two rows are the small phone's at the two largest sizes.
            let isShort = size >= .accessibility4 && phone.name == Phone.small.name
            withKnownIssue("The implementer's finding 2: the pinned header at the largest sizes") {
                #expect(rows >= 2, "\(rows) rows under a header of \(hosted.header) pt")
            } when: {
                isShort
            }
        }

        /// The screen says a drag on the page puts the name field's keyboard away. No tree and no reference
        /// sees that; UIKit's scroll view holds it.
        @Test("A drag on the page puts the keyboard away")
        func screen_dragDismissesTheKeyboard() throws {
            let mode = try Self.hosted(width: 402, height: 812, at: .large).dismissMode
            #expect(mode == .interactive || mode == .interactiveWithAccessory, "\(mode.rawValue)")
        }
    }
#endif
