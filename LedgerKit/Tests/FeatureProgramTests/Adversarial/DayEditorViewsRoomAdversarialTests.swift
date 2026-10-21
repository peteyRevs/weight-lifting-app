#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
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

        /// The Day editor's screen as it was hosted: how high its pinned part is, and its page's room.
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

        /// Round 1's finding F11-S10-2, closed by ruling 14: the whole header was pinned and a short screen
        /// squeezed it (325 pt needed, 302 given). Now the bar alone is pinned, at its own height. Each
        /// phone's screen is hosted three times: with all its height, with 3,000 pt, and with 150 pt, where
        /// a part that can give way does. On the hosted PR runner (`TestSweep`) the representative sizes: the bar
        /// is 60 pt to `.accessibility2` and grows from `.accessibility3` to 70.3 pt at `.accessibility5`, the
        /// size nearest its 72 pt bound, on both phones (2026-10-21).
        @Test(
            "The pinned bar keeps its own height on both phones, however little room the screen has",
            arguments: [Phone.iPhone17, .small], TestSweep.sizes(DynamicTypeSize.allCases)
        )
        func bar_isNeverSqueezed(_ phone: Phone, _ size: DynamicTypeSize) throws {
            let width = phone.size.width
            let own = try Self.hosted(width: width, height: 3000, at: size).header
            let onThePhone = try Self.hosted(width: width, height: phone.size.height - phone.topInset, at: size).header
            let cramped = try Self.hosted(width: width, height: 150, at: size).header
            #expect(abs(onThePhone - own) < 0.5 && abs(cramped - own) < 0.5, "\(own), \(onThePhone), \(cramped) pt")
            // Its two buttons and `s` above and below; a line of the largest text is higher than 44 pt.
            #expect(own >= 44 + 2 * LedgerSpacing.s - 0.5 && own <= 72, "the bar is \(own) pt high")
        }

        @Test("The bar's two buttons are 44 pt targets at the ends of the bar, at every size", arguments: [
            DynamicTypeSize.xSmall, .large, .accessibility5
        ])
        func bar_targets(_ size: DynamicTypeSize) throws {
            let header = try ProgramPreview.dayEditor.dayEditorModel().header
            for width in ViewsSetting.widths {
                let stops = ProgramViewsProbe.placed(
                    DayEditorBar(model: header) { _ in },
                    ViewsSetting(size: size, width: width)
                )
                let faults = ProgramViewsProbe.faults(in: stops, width: width)
                #expect(stops.map(\.stop) == [.button(header.back.title), .button(header.done.title)])
                #expect(faults.isEmpty, "\(Int(width)) pt: \(faults)")
                let gap = (stops.last?.frame.minX ?? 0) - (stops.first?.frame.maxX ?? 0)
                #expect(gap >= LedgerSpacing.m, "\(Int(width)) pt: \(gap) pt between the two")
            }
        }

        /// The implementer's finding 2 after ruling 14, measured on the hosted screen and counted in closed
        /// rows of the seed program: with the bar alone pinned every cell shows two rows but the small
        /// phone's at the two largest sizes (1.99 and 1.36 rows of 293 and 424 pt), which stay a known issue
        /// for the product owner. The page's first rows are its title block, which this count leaves out: it
        /// is the room under the bar, not what is left under the title. On the hosted PR runner (`TestSweep`) the
        /// representative sizes, and `.accessibility3` and `.accessibility4`: the small phone's 2.26 rows at
        /// `.accessibility3` are the least that pass, and its 1.99 at `.accessibility4` the first of the known
        /// issue (2026-10-21).
        @Test(
            "Under the pinned bar the page has room for at least two closed rows",
            arguments: [Phone.iPhone17, .small],
            TestSweep.sizes(DynamicTypeSize.allCases, also: [.accessibility3, .accessibility4])
        )
        func page_showsAtLeastTwoRows(_ phone: Phone, _ size: DynamicTypeSize) throws {
            let hosted = try Self.hosted(width: phone.size.width, height: phone.size.height - phone.topInset, at: size)
            let rows = try hosted.page / Self.rowHeight(at: size, width: phone.size.width)
            let isShort = size >= .accessibility4 && phone.name == Phone.small.name
            withKnownIssue("The implementer's finding 2: a 375 × 667 phone at the two largest sizes") {
                #expect(rows >= 2, "\(rows) rows under a bar of \(hosted.header) pt")
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
