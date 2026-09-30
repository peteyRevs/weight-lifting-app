#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// Slice 3's controls beside the tree table (`AccessibilityTreeSlice3Tables`): each is a labelled
        /// button with a 44 pt target (iOS's minimum; on watchOS the HIG's default control size, HIG
        /// Accessibility › Mobility), and activating it through VoiceOver calls its own action. Read on
        /// iOS, at the default text size and at `.accessibility3`.
        @Suite("Slice3ComponentAccessibility", .tags(.design))
        struct Slice3ComponentAccessibilityTests {
            nonisolated static let sizes = ComponentAccessibilityTests.sizes

            @Test("SheetChrome: its cancel is a 44 pt button that calls onCancel", arguments: sizes)
            func sheetChrome_cancel_isATargetThatCancels(_ appearance: SnapshotAppearance) throws {
                var cancels = 0
                let sheet = SheetChrome("Swap exercise", cancel: "Cancel") { cancels += 1 } content: { EmptyView() }
                try Self.activate("Cancel", in: sheet, appearance)
                #expect(cancels == 1)
            }

            @Test("EmptyState: its action is a 44 pt button that calls it", arguments: sizes)
            func emptyState_action_isATargetThatActs(_ appearance: SnapshotAppearance) throws {
                var clears = 0
                let state = EmptyState("Nothing matches", body: "Try another muscle.", actionTitle: "Clear filters") {
                    clears += 1
                }
                try Self.activate("Clear filters", in: state, appearance)
                #expect(clears == 1)
            }

            @Test(
                "WatchPrimaryButton: a full-width button at least 44 pt tall that calls its action",
                arguments: sizes
            )
            func watchPrimaryButton_target_isFullWidthAndActs(_ appearance: SnapshotAppearance) throws {
                var taps = 0
                let button = WatchPrimaryButton("Done set") { taps += 1 }.frame(width: WatchSize.mm46.size.width)
                let element = try Self.activate("Done set", in: button, appearance)
                #expect(taps == 1)
                #expect(abs(element.frame.width - WatchSize.mm46.size.width) < 0.001, "\(element)")
            }

            @Test("A disabled WatchPrimaryButton says so and does nothing")
            func watchPrimaryButton_disabled_isNotEnabled() throws {
                var taps = 0
                let button = WatchPrimaryButton("Skip") { taps += 1 }.disabled(true)
                let element = try #require(button.accessibilityElements().first)
                #expect(element.traits.contains(.notEnabled))
                button.withAccessibilityElements { elements in _ = elements.first?.accessibilityActivate() }
                #expect(taps == 0)
            }

            /// Finds the one element labelled `label`, checks it is a button with a 44 pt target, and
            /// activates it as VoiceOver would. Returns the element as read before activation.
            @discardableResult
            static func activate(
                _ label: String,
                in view: some View,
                _ appearance: SnapshotAppearance,
                sourceLocation: SourceLocation = #_sourceLocation
            ) throws -> AccessibilityElementSnapshot {
                let elements = view.accessibilityElements(appearance)
                let element = try #require(
                    elements.first { $0.label == label },
                    "no \"\(label)\" in \(elements)",
                    sourceLocation: sourceLocation
                )
                expectButton(element, sourceLocation: sourceLocation)
                view.withAccessibilityElements(appearance) { live in
                    _ = live.first { $0.accessibilityLabel == label }?.accessibilityActivate()
                }
                return element
            }
        }
    }
#endif
