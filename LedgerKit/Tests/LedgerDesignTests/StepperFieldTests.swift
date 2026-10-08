#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F11 S8 criterion 1: `StepperField` is one adjustable element with its label and its value; each
        /// step has its closure; a step without one is switched off, drawn so and inert; the buttons are 44 pt
        /// targets; and the parts stack at accessibility sizes. Its trees are rows of `AccessibilityTreeTests`.
        @Suite("StepperField", .tags(.design))
        struct StepperFieldTests {
            /// A field with no text: only its two buttons draw, at the phone's width.
            private static func buttonsOnly(
                decrement: (() -> Void)? = {},
                increment: (() -> Void)? = {},
                _ size: DynamicTypeSize = .large
            ) throws -> PixelBuffer {
                let field = StepperField("", value: "", onDecrement: decrement, onIncrement: increment)
                let image = RenderedImage.render(
                    field.background(LedgerColor.ground),
                    width: SnapshotConfig.phoneWidth,
                    dynamicTypeSize: size
                )
                return try #require(image.flatMap(PixelBuffer.init))
            }

            private static func inkedColumns(_ buffer: PixelBuffer) throws -> ClosedRange<Int> {
                try #require(buffer.inkedColumns(differingFrom: buffer.pixel(column: 0, row: 0), tolerance: 6))
            }

            @Test("VoiceOver reads one adjustable element: the label, and the value or its spoken form")
            func field_accessibility_isOneAdjustableElement() throws {
                for appearance in ComponentAccessibilityTests.sizes {
                    let drawn = StepperField("Sets", value: "5", onDecrement: {}, onIncrement: {})
                        .accessibilityElements(appearance)
                    let field = try #require(drawn.first)
                    #expect(drawn.count == 1, "the buttons are no stops of their own: \(drawn)")
                    #expect(field.label == "Sets" && field.value == "5")
                    #expect(field.traits.contains(.adjustable) && !field.traits.contains(.notEnabled))
                    expectTarget(field)
                }
                let spoken = StepperField(
                    "Rest", value: "2:30", spokenValue: "2 minutes 30 seconds", onDecrement: {}, onIncrement: {}
                )
                #expect(spoken.accessibilityElements().map(\.value) == ["2 minutes 30 seconds"])
            }

            @Test("VoiceOver's swipe up calls the increment closure and its swipe down the decrement closure")
            func field_adjust_callsTheMatchingClosure() {
                var steps: [String] = []
                StepperField("Sets", value: "5") { steps.append("−") } onIncrement: { steps.append("+") }
                    .withAccessibilityElements { elements in
                        elements.first?.accessibilityIncrement()
                        elements.first?.accessibilityIncrement()
                        elements.first?.accessibilityDecrement()
                    }
                #expect(steps == ["+", "+", "−"])
            }

            @Test("A switched-off step does nothing; the other still steps, and the field is not dimmed")
            func field_oneStepOff_onlyTheOtherSteps() {
                var steps: [String] = []
                let traits = StepperField(
                    "Target RPE",
                    value: "10",
                    onDecrement: { steps.append("−") },
                    onIncrement: nil
                )
                .withAccessibilityElements { elements in
                    elements.first?.accessibilityIncrement()
                    elements.first?.accessibilityDecrement()
                    elements.first?.accessibilityIncrement()
                    return elements.map(\.accessibilityTraits)
                }
                #expect(steps == ["−"])
                #expect(traits.count == 1 && traits
                    .allSatisfy { $0.contains(.adjustable) && !$0.contains(.notEnabled) })
            }

            @Test("With both steps off the field is dimmed to VoiceOver; a disabled field is too, and does nothing")
            func field_bothStepsOffOrDisabled_isDimmedAndInert() {
                let off = StepperField("Sets", value: "5", onDecrement: nil, onIncrement: nil).accessibilityElements()
                #expect(off.count == 1 && off.allSatisfy { $0.traits.contains(.notEnabled) })
                #expect(off.map(\.label) == ["Sets"] && off.map(\.value) == ["5"])

                var steps = 0
                let traits = StepperField("Sets", value: "5") { steps += 1 } onIncrement: { steps += 1 }
                    .disabled(true)
                    .withAccessibilityElements { elements in
                        elements.first?.accessibilityIncrement()
                        elements.first?.accessibilityDecrement()
                        return elements.map(\.accessibilityTraits)
                    }
                #expect(steps == 0)
                #expect(traits.count == 1 && traits.allSatisfy { $0.contains(.notEnabled) })
            }

            @Test("Wired to a value with limits, VoiceOver announces each new value and stays at a limit")
            func field_adjustedAtItsLimits_announcesTheValue() {
                LimitedHarness().withLiveAccessibilityElements { read in
                    #expect(read().map { $0.accessibilityValue ?? "" } == ["2"])
                    read().first?.accessibilityIncrement()
                    #expect(read().first?.accessibilityValue == "3")
                    read().first?.accessibilityIncrement()
                    #expect(read().first?.accessibilityValue == "3", "the top: + is switched off")
                    read().first?.accessibilityDecrement()
                    read().first?.accessibilityDecrement()
                    read().first?.accessibilityDecrement()
                    #expect(read().first?.accessibilityValue == "1", "the bottom: − is switched off")
                }
            }

            @Test("Both buttons are 44 pt targets, 8 pt apart, at the trailing edge")
            func buttons_areFortyFourPointTargets() throws {
                let buffer = try Self.buttonsOnly()
                let columns = try Self.inkedColumns(buffer)
                #expect(buffer.height >= 44)
                #expect(columns.count == 44 + 8 + 44, "\(columns)")
                #expect(columns.upperBound == buffer.width - 1, "\(columns)")
            }

            @Test("A switched-off step is drawn differently from a live one, each side by itself, at the same size")
            func switchedOffStep_isDrawnAsSuch() throws {
                let live = try Self.buttonsOnly()
                let noDecrement = try Self.buttonsOnly(decrement: nil)
                let noIncrement = try Self.buttonsOnly(increment: nil)
                for (name, drawn) in [("−", noDecrement), ("+", noIncrement)] {
                    let isSameSize = drawn.width == live.width && drawn.height == live.height
                    #expect(isSameSize, "\(name)")
                    let differs = drawn != live
                    #expect(differs, "\(name) off looks like \(name) on")
                }
                let sidesDiffer = noDecrement != noIncrement
                #expect(sidesDiffer)
                // "−" is the left button: with it off, the right half is drawn as when both are live.
                let middle = live.width - 48
                let rightHalfIsLive = (0 ..< live.height).allSatisfy { row in
                    (middle ..< live.width).allSatisfy { column in
                        noDecrement.pixel(column: column, row: row) == live.pixel(column: column, row: row)
                    }
                }
                #expect(rightHalfIsLive)
            }

            @Test("At accessibility text sizes the buttons stand under the text, from the leading edge")
            func buttons_atAccessibilitySizes_standUnderTheText() throws {
                let beside = try Self.inkedColumns(Self.buttonsOnly(.xLarge))
                #expect(beside.lowerBound > Int(SnapshotConfig.phoneWidth) / 2, "\(beside)")
                for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
                    let under = try Self.inkedColumns(Self.buttonsOnly(size))
                    #expect(under.lowerBound == 0, "\(size): \(under)")
                    #expect(under.upperBound < Int(SnapshotConfig.phoneWidth) / 2, "\(size): \(under)")
                }
            }
        }
    }

    /// A field wired to a value from 1 to 3, as a feature wires one whose model leaves a step out at a limit.
    private struct LimitedHarness: View {
        @State private var sets = 2

        var body: some View {
            StepperField(
                "Sets",
                value: "\(sets)",
                onDecrement: sets > 1 ? { sets -= 1 } : nil,
                onIncrement: sets < 3 ? { sets += 1 } : nil
            )
        }
    }
#endif
