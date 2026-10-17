#if os(iOS)
    import Foundation
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S4, gate G2: the two additions to `LedgerDesign` (criterion 8), through their public interface as
    /// another feature would use them: a round button holding one of Apple's symbols, and the orange button
    /// with a `Text` for its label and a fixed line for VoiceOver.
    @Suite("Adversarial F09 S4 · the two design components", .tags(.feature))
    struct TodayViewsComponentsAdversarialTests {
        /// A stop with its tappable area and its traits as UIKit gives them.
        struct Activated {
            let stop: ViewStop
            let frame: CGRect
            let traits: UIAccessibilityTraits
        }

        /// The stops of `view`, each activated once.
        static func activated(_ view: some View, at size: DynamicTypeSize = .large) -> [Activated] {
            view.withAccessibilityElements(SnapshotAppearance(.dark, size)) { elements in
                elements.map { element in
                    _ = element.accessibilityActivate()
                    return Activated(
                        stop: ViewStop(reading: element),
                        frame: element.accessibilityFrame,
                        traits: element.accessibilityTraits
                    )
                }
            }
        }

        static func timerLabel() -> Text {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            return Text(
                timerInterval: start ... .distantFuture,
                pauseTime: start.addingTimeInterval(768),
                countsDown: false
            )
        }

        @Test(
            "A symbol button is one button read by its label, 44 points at least, at every text size",
            arguments: TodayViewsLayoutAdversarialTests.sizes
        )
        func symbolButton_isOneLabelledButton(_ size: DynamicTypeSize) {
            var taps = 0
            let found = Self.activated(IconPillButton("Settings", systemImage: "gearshape") { taps += 1 }, at: size)
            #expect(found.map(\.stop.description) == ["button \"Settings\""], "\(found.map(\.stop))")
            #expect(
                found.allSatisfy { $0.frame.width >= 43.5 && $0.frame.height >= 43.5 },
                "\(found.map(\.frame.size))"
            )
            #expect(found.allSatisfy { !$0.traits.contains(.image) }, "the symbol is read as an image")
            #expect(taps == 1)
        }

        @Test(
            "A symbol button and an icon button are the same size, so the two kinds stand side by side",
            arguments: [DynamicTypeSize.large, .xLarge, .accessibility3, .accessibility5]
        )
        func symbolButton_isAsBigAsAnIconButton(_ size: DynamicTypeSize) throws {
            let symbol = try #require(Self.activated(IconPillButton("A", systemImage: "gearshape") {}, at: size).first)
            let icon = try #require(Self.activated(IconPillButton("A", icon: .swap) {}, at: size).first)
            #expect(abs(symbol.frame.width - icon.frame.width) < 0.5, "\(symbol.frame.size) and \(icon.frame.size)")
            #expect(abs(symbol.frame.height - icon.frame.height) < 0.5, "\(symbol.frame.size) and \(icon.frame.size)")
        }

        @Test("Disabled, a symbol button does nothing and says it is dimmed; pressed, it reads the same")
        func symbolButton_states() {
            var taps = 0
            let button = IconPillButton("Settings", systemImage: "gearshape") { taps += 1 }
            let disabled = Self.activated(button.disabled(true))
            #expect(disabled.map(\.stop.description) == ["button \"Settings\" (dimmed)"], "\(disabled.map(\.stop))")
            #expect(taps == 0)
            let pressed = TodayViews.stops(of: button.environment(\.ledgerDrawsPressed, true))
            #expect(pressed.map(\.description) == ["button \"Settings\""], "\(pressed)")
        }

        @Test("A symbol name that is no symbol still leaves a labelled 44-point button")
        func symbolButton_unknownSymbol_isStillAButton() {
            let found = Self.activated(IconPillButton("Settings", systemImage: "no.such.symbol.anywhere") {})
            #expect(found.map(\.stop.description) == ["button \"Settings\""], "\(found.map(\.stop))")
            #expect(found.allSatisfy { $0.frame.width >= 43.5 && $0.frame.height >= 43.5 })
        }

        @Test(
            "A button with a timer for its label is read as the fixed line, and does not update by itself",
            arguments: TodayViewsLayoutAdversarialTests.sizes
        )
        func textButton_isReadAsItsFixedLine(_ size: DynamicTypeSize) {
            var taps = 0
            let button = PrimaryButton(label: Self.timerLabel(), accessibilityLabel: "Resume, 12 minutes") { taps += 1 }
            let found = Self.activated(button, at: size)
            #expect(found.map(\.stop.description) == ["button \"Resume, 12 minutes\""], "\(found.map(\.stop))")
            #expect(found.allSatisfy { !$0.traits.contains(.updatesFrequently) }, "the element updates frequently")
            #expect(found.allSatisfy { $0.frame.height >= 43.5 && $0.frame.maxX <= SnapshotConfig.phoneWidth + 0.5 })
            #expect(taps == 1)
        }

        @Test("With an icon, disabled or pressed, the text button keeps its one stop and its fixed line")
        func textButton_states() {
            var taps = 0
            let button = PrimaryButton(label: Self.timerLabel(), accessibilityLabel: "Resume", icon: .arrow) {
                taps += 1
            }
            #expect(TodayViews.stops(of: button).map(\.description) == ["button \"Resume\""])
            let pressed = TodayViews.stops(of: button.environment(\.ledgerDrawsPressed, true))
            #expect(pressed.map(\.description) == ["button \"Resume\""], "\(pressed)")
            let disabled = Self.activated(button.disabled(true))
            #expect(disabled.map(\.stop.description) == ["button \"Resume\" (dimmed)"], "\(disabled.map(\.stop))")
            #expect(taps == 0)
        }

        @Test("A plain Text label draws as the String button does: the two initialisers make one button")
        func textButton_drawsAsTheStringButton() throws {
            let width = SnapshotConfig.phoneWidth
            let fromText = RenderedImage.render(
                PrimaryButton(label: Text(verbatim: "Start workout"), accessibilityLabel: "Start workout") {},
                width: width
            )
            let fromString = RenderedImage.render(PrimaryButton("Start workout") {}, width: width)
            let first = try #require(fromText.flatMap(PixelBuffer.init))
            let second = try #require(fromString.flatMap(PixelBuffer.init))
            #expect(first.width == second.width && first.height == second.height)
            #expect(first == second, "the Text button and the String button draw differently")
        }

        @Test("The String button still reads its title, with or without an icon (unchanged by the slice)")
        func stringButton_isUnchanged() {
            #expect(TodayViews.stops(of: PrimaryButton("Start workout", icon: .arrow) {}).map(\.description)
                == ["button \"Start workout\""])
            #expect(TodayViews.stops(of: IconPillButton("Swap exercise", icon: .swap) {}).map(\.description)
                == ["button \"Swap exercise\""])
        }
    }
#endif
