#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import SwiftUI
    import Testing

    // MARK: - Criterion 11: room, measured

    extension ProgramViewsStripAdversarialTests {
        @Test("A week chip keeps m above and below its two lines, at every size", arguments: DynamicTypeSize.allCases)
        func weekChip_keepsItsRoom(_ size: DynamicTypeSize) throws {
            let chip = try #require(ProgramPreview.builder.builderModel().block.chips.last)
            let lines = VStack(spacing: LedgerSpacing.xs) {
                Text(chip.title).ledgerFont(.numeralS)
                Text(chip.subtitle).ledgerFont(.eyebrow)
            }
            let words = try ProgramViewsCutAdversarialTests.height(of: lines.fixedSize(), at: size)
            let setting = ViewsSetting(size: size)
            let drawn = ProgramViewsProbe.placed(WeekChips(chips: [chip]) { _ in }, setting).first?.frame.height ?? 0
            // The words' height is whole pixels of a drawing at 1×: a point of grace.
            #expect(drawn - words >= 2 * LedgerSpacing.m - 1, "chip \(drawn) pt, its two lines \(words) pt")
        }

        @Test(
            "The long tag's strip draws all its words, by the pixels",
            arguments: DynamicTypeSize.allCases,
            ViewsSetting.widths
        )
        func longTag_drawsItsWordsWhole(_ size: DynamicTypeSize, _ width: CGFloat) throws {
            let cells = try Self.cells(of: "a long tag")
            let share = try ProgramViewsCutAdversarialTests.wordsDrawn(cells, ViewsSetting(size: size, width: width))
            #expect(ProgramViewsCutAdversarialTests.wholeBand.contains(share), "\(share) %")
        }
    }
#endif
