#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// The two additions of F09 S4 (criterion 8): a `PrimaryButton` whose label is a `Text` the caller built
        /// (a timer), and an `IconPillButton` that holds one of Apple's symbols. Their trees are rows of
        /// `AccessibilityTreeTests`' table.
        @Suite("ButtonAdditions", .tags(.design))
        struct ButtonAdditionsTests {
            /// `view` on the ground at its own size, 1×.
            private static func drawn(_ view: some View) throws -> PixelBuffer {
                let image = RenderedImage.render(view.background(LedgerColor.ground))
                return try #require(image.flatMap(PixelBuffer.init))
            }

            /// A button whose label counts up from the gallery's start and stands still `seconds` after it.
            private static func timer(
                pausedAfter seconds: TimeInterval,
                _ action: @escaping () -> Void = {}
            ) -> some View {
                let start = PrimaryButtonTimerGallery.start
                let label = Text(
                    timerInterval: start ... .distantFuture,
                    pauseTime: start.addingTimeInterval(seconds),
                    countsDown: false
                )
                return PrimaryButton(label: label, accessibilityLabel: "Resume workout", action: action)
                    .frame(width: SnapshotConfig.phoneWidth)
            }

            @Test("A timer label is drawn from its moment: a second later it reads differently, the same moment alike")
            func timerLabel_followsItsPauseTime() throws {
                let at768 = try Self.drawn(Self.timer(pausedAfter: 768))
                let again = try Self.drawn(Self.timer(pausedAfter: 768))
                let later = try Self.drawn(Self.timer(pausedAfter: 769))
                let isStable = at768 == again
                let moved = at768 != later
                #expect(isStable, "a frozen timer draws the same every time")
                #expect(moved, "12:48 and 12:49 are different pictures")
            }

            @Test("A button with a timer label is one button that reads its spoken line, 54 pt tall, and acts")
            func timerButton_isOneLabelledButton() throws {
                for appearance in ComponentAccessibilityTests.sizes {
                    var taps = 0
                    let button = Self.timer(pausedAfter: 768) { taps += 1 }
                    let elements = button.accessibilityElements(appearance)
                    let element = try #require(elements.first)
                    #expect(elements.count == 1, "the timer and the icon add no element")
                    #expect(element.label == "Resume workout")
                    expectButton(element)
                    #expect(element.frame.height >= PrimaryButton.minimumHeight)
                    button.withAccessibilityElements { $0.first?.accessibilityActivate() }
                    #expect(taps == 1)
                }
            }

            @Test(
                "A spoken line that is empty or only white space is no line: the button reads its drawn label",
                arguments: ["", " ", "\n\t ", "\u{00A0}"]
            )
            func blankSpokenLine_readsTheDrawnLabel(_ blank: String) throws {
                let button = PrimaryButton(label: Text(verbatim: "Start workout"), accessibilityLabel: blank) {}
                let elements = button.accessibilityElements()
                let element = try #require(elements.first)
                #expect(elements.count == 1)
                #expect(element.label == "Start workout")
                expectButton(element)
                // As with no line at all, a timer's element keeps the trait SwiftUI gives it.
                let timer = PrimaryButton(label: PrimaryButtonTimerGallery.elapsed, accessibilityLabel: blank) {}
                let counting = try #require(timer.accessibilityElements().first)
                #expect(counting.label == "12:48")
                #expect(counting.traits.contains(.updatesFrequently))
            }

            @Test("A symbol button is one button that reads its label, with a 44 pt target, and acts")
            func symbolButton_isOneLabelledButton() throws {
                for appearance in ComponentAccessibilityTests.sizes {
                    var taps = 0
                    let button = IconPillButton("Settings", systemImage: "gearshape") { taps += 1 }
                    let elements = button.accessibilityElements(appearance)
                    let element = try #require(elements.first)
                    #expect(elements.count == 1, "the symbol adds no element")
                    #expect(element.label == "Settings")
                    expectButton(element)
                    button.withAccessibilityElements { $0.first?.accessibilityActivate() }
                    #expect(taps == 1)
                }
            }

            @Test("A symbol button is as big as one that holds a LedgerIcon, at every text size of the matrix")
            func symbolButton_isAsBigAsAnIconButton() throws {
                for size in [DynamicTypeSize.large, .xLarge, .accessibility3] {
                    let appearance = SnapshotAppearance(.light, size)
                    let symbol = IconPillButton("Settings", systemImage: "gearshape") {}.fixedSize()
                    let icon = IconPillButton("Swap exercise", icon: .swap) {}.fixedSize()
                    let symbolFrame = try #require(symbol.accessibilityElements(appearance).first).frame.size
                    let iconFrame = try #require(icon.accessibilityElements(appearance).first).frame.size
                    #expect(symbolFrame == iconFrame, "\(size)")
                }
            }
        }

        /// The two galleries in the phone matrix, light and dark × large, xLarge and accessibility3.
        /// `PrimaryButtonGallery`, `IconPillButtonGallery` and their references are as they were. Recorded on the
        /// PR plan's iPhone 17 (iOS 27.0).
        @Suite("ButtonAdditionsSnapshots", .tags(.design, .snapshot))
        struct ButtonAdditionsSnapshotTests {
            nonisolated static let phoneMatrix = SnapshotAppearance.phoneMatrix

            @Test("PrimaryButton with a timer label, frozen, matches its references", arguments: phoneMatrix)
            func primaryButtonTimer_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: PrimaryButtonTimerGallery().phonePage(), appearance)
            }

            @Test("IconPillButton with a symbol matches its references", arguments: phoneMatrix)
            func iconPillButtonSymbol_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: IconPillButtonSymbolGallery().phonePage(), appearance)
            }
        }
    }
#endif
