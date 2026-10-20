#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// G2, F10 S7b criteria 38 and 39: the "LOGGED" eyebrow, which the implementer's cut check leaves out in
    /// every setting (notes, S7b "Deviations" 5) because right to left at the accessibility sizes the reader
    /// gives it 5 pt less than it measures alone. The exemption is only justified if that is a reading of
    /// the mirrored frame, not a cut: so left to right it must pass the cut check in every setting, and right
    /// to left it must stay one line (a Text with no line limit and room below it wraps before it truncates)
    /// within a few points of its whole width, so that a real squeeze is still seen. And the other part the
    /// check leaves out, the tiles' values (`tileValues_neverTruncate`).
    @Suite("Receipt LOGGED cut (adversarial)", .serialized, .tags(.feature))
    struct ReceiptLoggedCutAdversarialTests {
        /// The most the mirrored reading may fall short of the eyebrow's own width: the 5 pt measured, and a
        /// little room. A squeeze of the word would be far more.
        static let mirroredSlack: CGFloat = 8

        @Test(
            "LOGGED is whole: cut-checked left to right; right to left, one line at about its own width",
            arguments: ReceiptLayoutTests.sizes
        )
        func logged_isWhole(_ size: DynamicTypeSize) throws {
            for model in try ReceiptLayoutTests.models() {
                let receipt = ReceiptParts(model: model)
                let word = model.page.logged
                let part = LayoutPart(word) { Eyebrow(word) }
                // The cut check runs left to right only, so the PR runner's sweep (the iPhone 17 plain, the
                // 375 pt phone bold and mirrored) also keeps the 375 pt phone bold left to right: the narrow
                // phone is cut-checked on every runner, and each direction has a setting.
                let narrow = { (setting: LayoutSetting) in
                    setting.width == LayoutSetting.narrowWidth && setting.isBold && !setting.isRightToLeft
                }
                for setting in LayoutSetting.sweep(size, also: narrow) {
                    if !setting.isRightToLeft {
                        let cut = WorkoutLayoutProbe.cut(in: receipt, parts: [part], setting)
                        #expect(cut.isEmpty, "\(setting.testDescription): \(cut.joined(separator: "; "))")
                        continue
                    }
                    let onPage = try #require(setting.elements(of: receipt).first { $0.label == word }).frame.size
                    let alone = try #require(setting.elements(of: Eyebrow(word).fixedSize(), fixedWidth: false).first)
                        .frame.size
                    #expect(onPage.height <= alone.height + 0.5, "\(setting.testDescription): one line")
                    #expect(
                        onPage.width >= alone.width - Self.mirroredSlack,
                        "\(setting.testDescription): \(onPage.width) of \(alone.width) pt"
                    )
                }
            }
        }

        /// Criterion 38: "Numerals shrink before they wrap and never truncate". The implementer's cut check
        /// leaves the tiles' values out because they shrink by design; that holds only while half the
        /// value's own width fits in its tile (the tile shrinks it at most to half, then truncates). Side by
        /// side, three tiles share a 375 pt phone: the longest receipt's "1,234/1,250" and its volume.
        @Test(
            "A tile's value fits its tile at half its size or more, so it never truncates",
            arguments: ReceiptLayoutTests.sizes
        )
        func tileValues_neverTruncate(_ size: DynamicTypeSize) throws {
            for model in try ReceiptLayoutTests.models() {
                let receipt = ReceiptParts(model: model)
                // The PR runner's sweep keeps the 375 pt phone, where the three tiles have least room.
                for setting in LayoutSetting.sweep(size) {
                    let stops = setting.elements(of: receipt)
                    for tile in model.page.tiles {
                        let frame = try #require(stops.first { $0.label == tile.spoken }).frame
                        let room = frame.width - 2 * LedgerSpacing.m
                        let value = Text(tile.value).ledgerFont(.numeralM).fixedSize()
                        let whole = try #require(setting.elements(of: value, fixedWidth: false).first).frame.width
                        #expect(
                            whole * 0.5 <= room + 0.5,
                            "\(setting.testDescription): \"\(tile.value)\" needs \(whole * 0.5) pt at half, has \(room)"
                        )
                    }
                }
            }
        }
    }
#endif
