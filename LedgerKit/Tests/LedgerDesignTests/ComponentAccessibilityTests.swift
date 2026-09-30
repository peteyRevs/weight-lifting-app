#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F06 criterion 6, for `PrimaryButton` and every other tappable component in slice 2: the
        /// label VoiceOver reads, the button (or adjustable) trait, and a hit target of at least
        /// 44 × 44 pt on iOS. Each view is hosted in a window and read through UIKit's accessibility
        /// tree, as VoiceOver reads it; a button's accessibility frame is its tappable area.
        /// Run at the default text size and at `.accessibility3`, the largest in the snapshot matrix.
        @Suite("ComponentAccessibility", .tags(.design))
        struct ComponentAccessibilityTests {
            nonisolated static let sizes = [
                SnapshotAppearance(.light, .large),
                SnapshotAppearance(.dark, .accessibility3)
            ]

            @Test("PrimaryButton: its title is the label, it is a button, 44 pt target", arguments: sizes)
            func primaryButton_accessibility_labelledButtonWithTarget(_ appearance: SnapshotAppearance) throws {
                let elements = PrimaryButton("Start workout", icon: .arrow) {}.accessibilityElements(appearance)
                let button = try #require(elements.first)
                #expect(elements.count == 1, "the icon adds no element: \(elements)")
                #expect(button.label == "Start workout")
                expectButton(button)
                #expect(button.frame.height >= PrimaryButton.minimumHeight)
            }

            @Test("A disabled PrimaryButton says so")
            func primaryButton_disabled_isNotEnabled() throws {
                let button = try #require(PrimaryButton("Save workout") {}.disabled(true).accessibilityElements().first)
                expectButton(button)
                #expect(button.traits.contains(.notEnabled))
            }

            @Test(
                "PillButton: its title is the label, it is a button, 44 pt target in every style",
                arguments: [PillButton.Style.outline, .filled, .ghost]
            )
            func pillButton_accessibility_labelledButtonWithTarget(_ style: PillButton.Style) throws {
                for appearance in Self.sizes {
                    let elements = PillButton("Finish", style: style) {}.accessibilityElements(appearance)
                    let button = try #require(elements.first)
                    #expect(elements.count == 1)
                    #expect(button.label == "Finish")
                    expectButton(button)
                }
            }

            @Test("IconPillButton: its label names it, it is a button, 44 pt target", arguments: sizes)
            func iconPillButton_accessibility_labelledButtonWithTarget(_ appearance: SnapshotAppearance) throws {
                let elements = IconPillButton("Swap exercise", icon: .swap) {}.accessibilityElements(appearance)
                let button = try #require(elements.first)
                #expect(elements.count == 1)
                #expect(button.label == "Swap exercise")
                expectButton(button)
            }

            @Test("HairlineRow with an action is one labelled button with a 44 pt target", arguments: sizes)
            func hairlineRow_action_isOneLabelledButton(_ appearance: SnapshotAppearance) throws {
                let row = HairlineRow("Lower A", detail: "Mon · 58 min") {} accessory: {
                    LedgerIconView(.chevron, sizedAs: .body)
                }
                let elements = row.accessibilityElements(appearance)
                let button = try #require(elements.first)
                #expect(elements.count == 1)
                #expect(button.label.contains("Lower A") && button.label.contains("Mon · 58 min"))
                expectButton(button)
            }

            @Test("HairlineRow without an action is one element and not a button")
            func hairlineRow_noAction_isOneStaticElement() throws {
                let elements = HairlineRow("Barbell Bench Press", detail: "5 × 5 @ 185").accessibilityElements()
                let row = try #require(elements.first)
                #expect(elements.count == 1)
                #expect(row.label.contains("Barbell Bench Press") && row.label.contains("5 × 5 @ 185"))
                #expect(!row.traits.contains(.button))
            }

            @Test("Eyebrow is a heading")
            func eyebrow_accessibility_isHeader() throws {
                let eyebrow = try #require(Eyebrow("Up next", tint: .accent).accessibilityElements().first)
                #expect(eyebrow.label.localizedCaseInsensitiveCompare("Up next") == .orderedSame)
                #expect(eyebrow.traits.contains(.header))
            }

            @Test("RestRing reads its countdown and updates frequently")
            func restRing_accessibility_readsCountdown() throws {
                let elements = RestRing(progress: 0.5, label: "1:15").accessibilityElements()
                let ring = try #require(elements.first)
                #expect(elements.count == 1)
                #expect(ring.label == "1:15")
                #expect(ring.traits.contains(.updatesFrequently))
            }
        }
    }

    /// A button: the trait, and a target of at least 44 × 44 pt.
    func expectButton(
        _ element: AccessibilityElementSnapshot,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(element.traits.contains(.button), "\(element)", sourceLocation: sourceLocation)
        expectTarget(element, sourceLocation: sourceLocation)
    }

    /// A hit target of at least 44 × 44 pt. UIKit's conversion to window coordinates can report a
    /// 44 pt frame as 43.999999999999886, so the comparison allows a thousandth of a point.
    func expectTarget(
        _ element: AccessibilityElementSnapshot,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            element.frame.width >= 44 - 0.001 && element.frame.height >= 44 - 0.001,
            "hit target \(element.frame.size) is under 44 × 44 pt",
            sourceLocation: sourceLocation
        )
    }
#endif
