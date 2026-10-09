#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// What the F11 S8 adversarial suites of the form controls share: the cells they draw in, and pixels.
    enum AdvForm {
        /// The six cells of testing-strategy §2.5, the largest size that still lays out in a row, and the
        /// largest of all.
        nonisolated static let cells = SnapshotAppearance.phoneMatrix
            + [SnapshotAppearance(.light, .xxxLarge), SnapshotAppearance(.dark, .accessibility5)]

        nonisolated static let width = Int(SnapshotConfig.phoneWidth)

        static func drawn(
            _ view: some View,
            _ appearance: SnapshotAppearance = SnapshotAppearance(.dark, .large),
            contrast: ColorSchemeContrast = .standard
        ) throws -> PixelBuffer {
            let image = RenderedImage.render(
                view.background(LedgerColor.ground).environment(\._colorSchemeContrast, contrast),
                width: SnapshotConfig.phoneWidth,
                colorScheme: appearance.colorScheme,
                dynamicTypeSize: appearance.dynamicTypeSize
            )
            return try #require(image.flatMap(PixelBuffer.init))
        }

        static func color(_ pixel: Pixel) -> SRGB {
            SRGB(
                red: Double(pixel.red) / 255, green: Double(pixel.green) / 255, blue: Double(pixel.blue) / 255,
                alpha: 1
            )
        }

        /// The runs of neighbouring columns, among `columns`, that hold a pixel unlike the ground.
        static func inkedRuns(_ buffer: PixelBuffer, columns: Range<Int>, tolerance: Int = 3) -> [ClosedRange<Int>] {
            let ground = buffer.pixel(column: 0, row: 0)
            var runs: [ClosedRange<Int>] = []
            for column in columns where (0 ..< buffer.height).contains(where: { row in
                buffer.pixel(column: column, row: row).differs(from: ground, by: tolerance)
            }) {
                if let last = runs.last, last.upperBound == column - 1 {
                    runs[runs.count - 1] = last.lowerBound ... column
                } else {
                    runs.append(column ... column)
                }
            }
            return runs
        }

        /// How many pixels are unlike the ground.
        static func ink(_ buffer: PixelBuffer) -> Int {
            let ground = buffer.pixel(column: 0, row: 0)
            return buffer.pixels.count { $0.differs(from: ground, by: 24) }
        }
    }

    extension RenderingSuites {
        /// F11 S8 adversarial round 1, criterion 1: `StepperField` in every cell, right to left, with Bold
        /// Text and Increase Contrast, with texts longer than the row, and what VoiceOver is told about a
        /// step that is switched off.
        @Suite("Adversarial F11 S8 · StepperField", .tags(.design))
        struct StepperFieldAdversarialTests {
            static let longLabel = "Start load for the first week of the block, before any progression is applied"
            static let longValue = "1,022,333.75 lb"

            private static func buttonsOnly(decrement: (() -> Void)? = {}, increment: (() -> Void)? = {}) -> some View {
                StepperField("", value: "", onDecrement: decrement, onIncrement: increment)
            }

            @Test(
                "In every cell, left to right and right to left, both buttons are drawn at least 44 pt wide and high",
                arguments: AdvForm.cells
            )
            func buttons_everyCell_areFortyFourPoints(_ cell: SnapshotAppearance) throws {
                for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                    let buffer = try AdvForm.drawn(Self.buttonsOnly().environment(\.layoutDirection, direction), cell)
                    let runs = AdvForm.inkedRuns(buffer, columns: 0 ..< buffer.width)
                    #expect(runs.count == 2, "\(cell) \(direction): \(runs)")
                    #expect(runs.allSatisfy { $0.count >= 44 }, "\(cell) \(direction): \(runs)")
                    #expect(buffer.height >= 44 && buffer.width == AdvForm.width, "\(cell) \(direction)")
                    if let first = runs.first, let last = runs.last, runs.count == 2 {
                        #expect(last.lowerBound - first.upperBound - 1 >= 8, "\(cell) \(direction): \(runs)")
                        #expect(first.lowerBound >= 0 && last.upperBound <= buffer.width - 1)
                    }
                }
            }

            @Test(
                "A label and a value longer than the row leave both buttons whole, clear of the text, in every cell",
                arguments: AdvForm.cells
            )
            func longTexts_everyCell_leaveTheButtonsWhole(_ cell: SnapshotAppearance) throws {
                let alone = try AdvForm.inkedRuns(AdvForm.drawn(Self.buttonsOnly(), cell), columns: 0 ..< AdvForm.width)
                let field = StepperField(Self.longLabel, value: Self.longValue, onDecrement: {}, onIncrement: {})
                let buffer = try AdvForm.drawn(field, cell)
                #expect(buffer.width == AdvForm.width)
                guard !cell.dynamicTypeSize.isAccessibilitySize, let first = alone.first else {
                    // Stacked: the buttons stand under the text, which may be as wide as the row.
                    #expect(buffer.height >= 44 * 2, "\(cell): \(buffer.height)")
                    return
                }
                // In a row: the buttons keep their columns, and the gap before them holds no ink.
                let beside = AdvForm.inkedRuns(buffer, columns: first.lowerBound ..< buffer.width)
                let isWhole = beside == alone
                #expect(isWhole, "\(cell): \(beside) against \(alone)")
                let gap = AdvForm.inkedRuns(buffer, columns: first.lowerBound - 12 ..< first.lowerBound)
                #expect(gap.isEmpty, "\(cell): text reaches the buttons at \(gap)")
            }

            @Test(
                "In every cell and direction VoiceOver finds one adjustable element, a 44 pt target inside the row",
                arguments: AdvForm.cells
            )
            func field_everyCell_isOneAdjustableTarget(_ cell: SnapshotAppearance) {
                for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                    let field = StepperField(
                        Self.longLabel, value: Self.longValue, spokenValue: "heavy", onDecrement: {}, onIncrement: nil
                    )
                    let found = field.environment(\.layoutDirection, direction).accessibilityElements(cell)
                    #expect(found.count == 1, "\(cell) \(direction): \(found)")
                    for element in found {
                        #expect(element.label == Self.longLabel && element.value == "heavy")
                        #expect(element.traits.contains(.adjustable) && !element.traits.contains(.notEnabled))
                        let isInside = element.frame.minX >= -0.001
                            && element.frame.maxX <= SnapshotConfig.phoneWidth + 0.001
                        #expect(isInside && element.frame.height >= 44 - 0.001, "\(cell): \(element.frame)")
                    }
                }
            }

            @Test(
                "Each swipe calls its closure once and never the other, in every cell and direction",
                arguments: AdvForm.cells
            )
            func adjust_everyCell_callsItsClosureOnce(_ cell: SnapshotAppearance) {
                for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                    var steps: [String] = []
                    StepperField("Sets", value: "5", spokenValue: "five") { steps.append("−") } onIncrement: {
                        steps.append("+")
                    }
                    .environment(\.layoutDirection, direction)
                    .withAccessibilityElements(cell) { elements in
                        elements.first?.accessibilityDecrement()
                        elements.first?.accessibilityIncrement()
                        elements.first?.accessibilityIncrement()
                        elements.first?.accessibilityDecrement()
                    }
                    #expect(steps == ["−", "+", "+", "−"], "\(cell) \(direction): \(steps)")
                }
            }
        }
    }

    extension RenderingSuites.StepperFieldAdversarialTests {
        /// FINDING F11-S8-2 (fails): criterion 1 asks that a switched-off step be "drawn and spoken as
        /// such". With one step off VoiceOver is handed exactly what it is handed with both on: the same
        /// label, value, traits and hint. Deviation 2 of the notes; a ruling is needed.
        @Test("A field with one step switched off is spoken differently from one with both steps on")
        func oneStepOff_isSpokenAsSuch() {
            func spoken(decrement: (() -> Void)?, increment: (() -> Void)?) -> [String] {
                StepperField("Sets", value: "5", onDecrement: decrement, onIncrement: increment)
                    .withAccessibilityElements { elements in
                        elements.map { element in
                            let actions = (element.accessibilityCustomActions ?? []).map(\.name)
                                .joined(separator: ",")
                            return [
                                element.accessibilityLabel ?? "", element.accessibilityValue ?? "",
                                "\(element.accessibilityTraits.rawValue)", element.accessibilityHint ?? "", actions
                            ].joined(separator: " | ")
                        }
                    }
            }
            let both = spoken(decrement: {}, increment: {})
            #expect(both.count == 1)
            #expect(spoken(decrement: nil, increment: {}) != both, "no − is spoken as both steps on: \(both)")
            #expect(spoken(decrement: {}, increment: nil) != both, "no + is spoken as both steps on: \(both)")
        }

        @Test("With Bold Text the label and the value lay down more ink, in a row and stacked")
        func boldText_isHeavier() throws {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let field = StepperField("Target RPE", value: "8.5", onDecrement: {}, onIncrement: {})
                let cell = SnapshotAppearance(.dark, size)
                let regular = try AdvForm.ink(AdvForm.drawn(field.environment(\.legibilityWeight, .regular), cell))
                let bold = try AdvForm.ink(AdvForm.drawn(field.environment(\.legibilityWeight, .bold), cell))
                #expect(Double(bold) > Double(regular) * 1.02, "\(size): ink \(regular) → \(bold)")
            }
        }

        @Test(
            "A switched-off step is drawn, and unlike a live one, in both themes, also under Increase Contrast",
            arguments: [ColorScheme.light, .dark]
        )
        func switchedOffStep_everyContrast_isDrawnAsSuch(_ scheme: ColorScheme) throws {
            let cell = SnapshotAppearance(scheme, .large)
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let live = try AdvForm.drawn(Self.buttonsOnly(), cell, contrast: contrast)
                let bothOff = try AdvForm.drawn(
                    Self.buttonsOnly(decrement: nil, increment: nil),
                    cell,
                    contrast: contrast
                )
                let differs = live != bothOff
                #expect(differs, "\(scheme) \(contrast)")
                // Faint, not gone: each switched-off button still shows its outline and its sign.
                let runs = AdvForm.inkedRuns(bothOff, columns: 0 ..< bothOff.width, tolerance: 2)
                #expect(runs.count == 2 && runs.allSatisfy { $0.count >= 44 }, "\(scheme) \(contrast): \(runs)")
                let disabled = try AdvForm.drawn(Self.buttonsOnly().disabled(true), cell, contrast: contrast)
                let looksOff = disabled == bothOff
                #expect(looksOff, "\(scheme) \(contrast): a disabled field's buttons are drawn as switched off")
            }
        }

        @Test("A field with no step, or disabled, takes no swipe, whatever its closures")
        func switchedOffField_takesNoSwipe() {
            var steps = 0
            let traits = StepperField("Sets", value: "5", onDecrement: nil, onIncrement: nil)
                .withAccessibilityElements { elements in
                    elements.first?.accessibilityIncrement()
                    elements.first?.accessibilityDecrement()
                    return elements.map(\.accessibilityTraits)
                }
            #expect(traits.count == 1 && traits.allSatisfy { $0.contains(.notEnabled) })
            StepperField("Sets", value: "5", onDecrement: nil) { steps += 1 }
                .disabled(true)
                .withAccessibilityElements { elements in
                    elements.first?.accessibilityIncrement()
                    elements.first?.accessibilityDecrement()
                }
            #expect(steps == 0)
        }
    }
#endif
