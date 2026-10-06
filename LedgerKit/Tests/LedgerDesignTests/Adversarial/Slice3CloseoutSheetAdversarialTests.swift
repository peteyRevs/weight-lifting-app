#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F06 slice 3, adversarial close-out: the edges of fix round 1 (`a19d20a`) in `SheetChrome`. The
        /// title at every text size, with Bold Text, squeezed, tall and overflowing; the escape gesture
        /// from every stop.
        @Suite("Slice 3 close-out: SheetChrome (adversarial, slice 3 close-out round)", .tags(.design))
        struct Slice3CloseoutSheetAdversarialTests {
            nonisolated static let textSizes: [DynamicTypeSize] = [
                .xSmall, .large, .xxxLarge,
                .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
            ]

            nonisolated static let titles = [
                "Swap exercise",
                "Replace Single-Arm Dumbbell Romanian Deadlift",
                "Replace Single-Arm Dumbbell Romanian Deadlift with a Cable Pull-Through or a Kettlebell Swing"
            ]

            static func rows(_ count: Int) -> some View {
                ForEach(0 ..< count, id: \.self) { row in
                    Text(verbatim: "Alternative \(row + 1), same movement pattern and equipment you have")
                }
            }

            static func bold(_ view: some View, _ bold: Bool) -> some View {
                view.environment(\.legibilityWeight, bold ? .bold : .regular)
            }

            // MARK: S3-1: the title keeps every line it needs, however short the sheet

            /// The title's height in a chrome squeezed to 300 pt under twelve rows must equal its height in
            /// the same chrome at its ideal height, at every text size, regular and Bold Text. The reference
            /// is the chrome itself, so the header's layout (side by side, or stacked at AX sizes) is the
            /// same on both sides.
            @Test(
                "SheetChrome squeezed under its content keeps its title's every line, xSmall to AX5, bold too",
                arguments: textSizes
            )
            func sheetChrome_squeezed_titleKeepsEveryLine(_ size: DynamicTypeSize) throws {
                let appearance = SnapshotAppearance(.dark, size)
                for title in Self.titles {
                    for bold in [false, true] {
                        let cell = "\(size)\(bold ? " bold" : "")"
                        let chrome = SheetChrome(title, cancel: "Cancel") {} content: { Self.rows(12) }
                        let squeezed = Self.bold(chrome.frame(height: 300), bold).accessibilityElements(appearance)
                        let ideal = Self.bold(chrome, bold).accessibilityElements(appearance)
                        let inSqueezed = try #require(squeezed.first { $0.label == title }, "\(squeezed)")
                        let inIdeal = try #require(ideal.first { $0.label == title }, "\(ideal)")
                        #expect(
                            abs(inSqueezed.frame.height - inIdeal.frame.height) < 0.5,
                            "\(cell), \"\(title)\": \(inSqueezed.frame.size) squeezed, \(inIdeal.frame.size) ideal"
                        )
                    }
                }
            }

            // MARK: R3-S1: the chrome fills a sheet from the top

            /// A detent taller than the content, with no content at all or one line: the title's top is the
            /// sheet's top plus the chrome's vertical padding, at every text size.
            @Test(
                "SheetChrome in a tall sheet puts its title at the top, empty or one line, xSmall to AX5",
                arguments: textSizes
            )
            func sheetChrome_tallSheet_titleAtTheTop(_ size: DynamicTypeSize) throws {
                let appearance = SnapshotAppearance(.light, size)
                let sheets: [(String, AnyView)] = [
                    ("empty", AnyView(SheetChrome("Swap exercise", cancel: "Cancel") {} content: { EmptyView() })),
                    ("one line", AnyView(SheetChrome("Swap exercise", cancel: "Cancel") {} content: {
                        Text(verbatim: "Content")
                    }))
                ]
                for (name, sheet) in sheets {
                    let offset = try Self.titleOffset(sheet, title: "Swap exercise", height: 874, appearance)
                    #expect(
                        Self.isAtTheTop(offset, size),
                        "\(name), \(size): the title is \(offset) pt below the sheet's top"
                    )
                }
            }

            /// The title's top, measured from a marker placed directly above a sheet-sized frame (the
            /// helper centres the whole page in its window, as a sheet's host centres its root).
            static func titleOffset(
                _ sheet: some View,
                title: String,
                height: CGFloat,
                _ appearance: SnapshotAppearance,
                outsideScrollViews: Bool = false
            ) throws -> CGFloat {
                let page = VStack(spacing: 0) {
                    Text(verbatim: "Sheet top")
                    sheet.frame(height: height)
                }
                let elements = page.accessibilityElements(appearance, outsideScrollViews: outsideScrollViews)
                let top = try #require(elements.first { $0.label == "Sheet top" }, "\(elements)")
                let heading = try #require(elements.first { $0.label == title }, "\(elements)")
                return heading.frame.minY - top.frame.maxY
            }

            /// At the sheet's top: under the chrome's padding, or, beside the 44 pt pill at the smaller
            /// sizes, a little lower (first-baseline alignment), never more than the pill's height.
            static func isAtTheTop(_ offset: CGFloat, _ size: DynamicTypeSize) -> Bool {
                size.isAccessibilitySize
                    ? abs(offset - LedgerSpacing.l) < 0.5
                    : offset >= LedgerSpacing.l - 0.5 && offset <= LedgerSpacing.l + LedgerHitTarget.minimum
            }

            /// iPhone 17's `.medium` detent: about half of its 874 pt screen.
            nonisolated static let mediumDetent: CGFloat = 437

            /// F10's pattern for a list that can outgrow the detent: the rows in a `ScrollView`. The title
            /// then stays at the sheet's top and keeps every line, up to AX5, under twenty rows.
            @Test(
                "SheetChrome with scrolling content in a medium sheet keeps its whole title at the top",
                arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5]
            )
            func sheetChrome_scrollingContent_titleAtTheTopAndWhole(_ size: DynamicTypeSize) throws {
                let appearance = SnapshotAppearance(.dark, size)
                let title = Self.titles[1]
                let sheet = SheetChrome(title, cancel: "Cancel") {} content: {
                    ScrollView { VStack(alignment: .leading) { Self.rows(20) } }
                }
                let offset = try Self.titleOffset(
                    sheet, title: title, height: Self.mediumDetent, appearance, outsideScrollViews: true
                )
                #expect(Self.isAtTheTop(offset, size), "\(size): the title is \(offset) pt below the sheet's top")
                let inSheet = try #require(sheet.frame(height: Self.mediumDetent)
                    .accessibilityElements(appearance, outsideScrollViews: true).first { $0.label == title })
                let ideal = SheetChrome(title, cancel: "Cancel") {} content: { EmptyView() }
                let needed = try #require(ideal.accessibilityElements(appearance).first { $0.label == title })
                #expect(abs(inSheet.frame.height - needed.frame.height) < 0.5, "\(size): \(inSheet), \(needed)")
            }

            /// R3-S1's contract, "it fills the sheet and keeps its content at the top", when the content does
            /// not scroll and outgrows the detent (F10's eight rows at a large text size, say). The chrome
            /// then reports its own, taller height; the sheet's host centres it, and the sheet's top edge cuts
            /// off the title's first lines, the top rule and the corners.
            @Test(
                "SheetChrome whose content outgrows the sheet still keeps its title at the top",
                arguments: [DynamicTypeSize.large, .accessibility3]
            )
            func sheetChrome_contentOutgrowsTheSheet_titleStaysAtTheTop(_ size: DynamicTypeSize) throws {
                let sheet = SheetChrome("Swap exercise", cancel: "Cancel") {} content: { Self.rows(20) }
                let offset = try Self.titleOffset(
                    sheet,
                    title: "Swap exercise",
                    height: Self.mediumDetent,
                    SnapshotAppearance(.dark, size)
                )
                #expect(Self.isAtTheTop(offset, size), "\(size): the title is \(offset) pt below the sheet's top")
            }

            // MARK: S3-4: escape from every stop, at the text-size extremes; a feature can still override

            @Test(
                "VoiceOver's escape from every stop of a sheet with a row calls onCancel once, and not the row",
                arguments: [DynamicTypeSize.xSmall, .accessibility5]
            )
            func sheetChrome_escapeFromEveryStop_callsOnCancelOnly(_ size: DynamicTypeSize) {
                var cancels = 0
                var uses = 0
                let sheet = SheetChrome("Swap exercise", cancel: "Cancel") { cancels += 1 } content: {
                    Text(verbatim: "Same movement pattern, equipment you have.")
                    HairlineRow("Dumbbell Bench Press", detail: "Similar pattern") { uses += 1 } accessory: {
                        Text(verbatim: "Use")
                    }
                }
                let stops = sheet.withAccessibilityElements(SnapshotAppearance(.dark, size)) { elements in
                    elements.map(Slice3SheetAccessibilityAdversarialTests.performEscape)
                }
                #expect(stops.count == 4 && stops.allSatisfy(\.self), "\(size): \(stops)")
                #expect(cancels == stops.count, "\(size): \(cancels) cancels for \(stops.count) stops")
                #expect(uses == 0)
            }

            /// The chrome's escape sits on the whole chrome, so an escape a feature sets inside the content
            /// (a nested picker's own "back") is found first and wins.
            @Test("An escape set inside the content wins over the chrome's")
            func sheetChrome_innerEscape_wins() {
                var cancels = 0
                var inner = 0
                let sheet = SheetChrome("Swap exercise", cancel: "Cancel") { cancels += 1 } content: {
                    Text(verbatim: "Nested").accessibilityAction(.escape) { inner += 1 }
                }
                let handled = sheet.withAccessibilityElements { elements in
                    elements.first { $0.accessibilityLabel == "Nested" }
                        .map(Slice3SheetAccessibilityAdversarialTests.performEscape) ?? false
                }
                #expect(handled && inner == 1 && cancels == 0, "inner \(inner), cancels \(cancels)")
            }
        }
    }
#endif
