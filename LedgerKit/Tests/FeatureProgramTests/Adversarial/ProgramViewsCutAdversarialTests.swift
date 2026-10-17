#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, gate G2, round 1, criterion 7 ("nothing clips"): what a frame on the page cannot show, words cut
    /// short inside their own frame, by measurement and without a reference image. Each part whose words stand
    /// on one line (a heading, a note, a pill, a week's chip, a weekday's cell) is measured alone and in the
    /// page: a part the page gives less width than it takes alone, and that is no taller for it, has lost
    /// words. Swept over every text size, an iPhone 17's width and 375 pt, Bold Text and right to left.
    @Suite("Adversarial F11 S9 · words cut inside a frame", .serialized, .tags(.feature))
    struct ProgramViewsCutAdversarialTests {
        /// Every text size; on the hosted PR runner (`TestSweep`) the four representatives.
        nonisolated static let sizes = TestSweep.sizes(DynamicTypeSize.allCases)

        /// The strip's sizes: those, and on the runner too the four FINDING F11-S9-1 was seen at in the middle.
        nonisolated static let stripSizes = TestSweep.sizes(
            DynamicTypeSize.allCases,
            also: [.xLarge, .xxLarge, .accessibility1, .accessibility2]
        )

        /// The lines of `cut` for a builder's page in every setting of `size`: the strip's cells, or the rest.
        static func cutInBuilder(_ model: ProgramBuilderModel, at size: DynamicTypeSize, cells: Bool) -> [String] {
            let page = ProgramPage(model: model) { _ in }
            var alone = ProgramViewsAlone.builder(model)
            let strip = ProgramViewsAlone.cells(of: model)
            for place in alone.indices where strip.contains(place) != cells {
                alone[place] = nil
            }
            return ViewsSetting.sweep(size).flatMap { setting in
                ProgramViewsProbe.cut(page, alone: alone, setting).map { "\(setting.testDescription): \($0)" }
            }
        }

        /// **FINDING F11-S9-1** (bug; the review's B-1 by measurement, and wider than the review saw it). The
        /// strip takes the one row whenever the seven cells' own widths fit side by side, and then gives each
        /// a seventh of the row: a cell whose words are wider than a seventh is cut although the row "fits".
        /// With the seed program "REST" is drawn "RE…" at `.xLarge` and `.xxLarge` on an iPhone 17 (51.3 pt
        /// for a cell that takes 54.3 and 58.3), **and at the default size, `.large`, on a 375 pt phone**
        /// (47.3 pt for 48.3). Fails at those three sizes.
        @Test("In the seed program's week no weekday's cell is cut, at any text size or width", arguments: stripSizes)
        func strip_seedWeek_noCellIsCut(_ size: DynamicTypeSize) throws {
            let cut = try Self.cutInBuilder(ProgramPreview.builder.builderModel(), at: size, cells: true)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        /// **FINDING F11-S9-1**, a sibling: ten days, so the tag "D10" and no rest day. "D10" is drawn "D…" at
        /// `.xxxLarge` on a 375 pt phone, at `.accessibility1` on both widths and at `.accessibility2` on an
        /// iPhone 17. Fails at those three sizes.
        @Test("With ten days, a tag of three letters, no weekday's cell is cut", arguments: stripSizes)
        func strip_tenDays_noCellIsCut(_ size: DynamicTypeSize) throws {
            let cut = try Self.cutInBuilder(BuilderState.tenDays.model(), at: size, cells: true)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "In every state of the builder no heading, note, pill or week chip is cut, at any text size or width",
            arguments: ProgramPreview.builders, sizes
        )
        func builder_previews_noOtherPartIsCut(_ preview: ProgramPreview, _ size: DynamicTypeSize) throws {
            let cut = try Self.cutInBuilder(preview.builderModel(), at: size, cells: false)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "In this tester's states of the builder no heading, note, pill or week chip is cut",
            arguments: BuilderState.allCases, sizes
        )
        func builder_states_noOtherPartIsCut(_ state: BuilderState, _ size: DynamicTypeSize) throws {
            let cut = try Self.cutInBuilder(state.model(), at: size, cells: false)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        static func cutInLibrary(_ model: ExercisePickerModel, at size: DynamicTypeSize) -> [String] {
            let parts = ExercisePickerParts(model: model)
            let alone = ProgramViewsAlone.library(model)
            return ViewsSetting.sweep(size).flatMap { setting in
                ProgramViewsProbe.cut(parts, alone: alone, setting).map { "\(setting.testDescription): \($0)" }
            }
        }

        @Test(
            "In every state of the library no chip and no pill is cut, at any text size or width",
            arguments: ProgramPreview.libraries, sizes
        )
        func library_previews_noPillIsCut(_ preview: ProgramPreview, _ size: DynamicTypeSize) throws {
            let cut = try Self.cutInLibrary(preview.libraryModel(), at: size)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
        }

        @Test("The check sees a pill that is cut, and passes one that wraps onto more lines")
        func check_seesACut() {
            let title = "Apply to later weeks"
            // At an accessibility size two lines are higher than the 44 pt target, so a wrap shows.
            let setting = ViewsSetting(size: .accessibility1)
            let alone: [AnyView?] = [AnyView(PillButton(title) {})]
            let cutOne = PillButton(title) {}.lineLimit(1).frame(width: 120, alignment: .leading)
            #expect(ProgramViewsProbe.cut(cutOne, alone: alone, setting).count == 1)
            let wrapped = PillButton(title) {}.frame(width: 120, alignment: .leading)
            #expect(ProgramViewsProbe.cut(wrapped, alone: alone, setting).isEmpty)
            #expect(ProgramViewsProbe.cut(PillButton(title) {}, alone: alone, setting).isEmpty)
        }
    }

    // MARK: - By the pixels: the strip's words, and the headings

    extension ProgramViewsCutAdversarialTests {
        /// The strip as the page lays it out on a phone `width` wide: the page's width less its two margins.
        static func strip(_ cells: [ProgramBuilderModel.Cell], onAPhone width: CGFloat) -> some View {
            ScheduleStrip(cells: cells) { _ in }.frame(width: width - 2 * LedgerSpacing.screen)
        }

        /// Each cell by itself, at its own width: the strip's words with nothing to squeeze them.
        static func cellsAlone(_ cells: [ProgramBuilderModel.Cell]) -> some View {
            VStack(spacing: 0) {
                ForEach(cells, id: \.weekday) { ScheduleStrip(cells: [$0]) { _ in }.fixedSize() }
            }
        }

        /// The band a strip drawn whole stays in. Measured over the 72 cases of the two tests below (twelve
        /// sizes, two widths; the seed program plain and with Bold Text, ten days plain): every strip drawn
        /// whole gives 96 to 104 hundredths of its cells' words, every strip with a cut cell 81 to 94 (94 is
        /// one cell of seven reading "D…" for "D10"; three reading "RE…" for "REST" give 81 to 89).
        nonisolated static let wholeBand = 95 ... 105

        /// The share of the cells' word pixels that the strip draws on a phone `width` wide, in hundredths.
        static func wordsDrawn(_ cells: [ProgramBuilderModel.Cell], _ setting: ViewsSetting) throws -> Int {
            let whole = try ProgramViewsProbe.wordInk(of: cellsAlone(cells), setting)
            let drawn = try ProgramViewsProbe.wordInk(of: strip(cells, onAPhone: setting.width), setting)
            try #require(whole > 1000, "the cells alone drew no words")
            return drawn * 100 / whole
        }

        /// **FINDING F11-S9-1**, by the pixels, with no frame and no reference (the same cases as
        /// `strip_seedWeek_noCellIsCut`; looked at once as a picture too: three cells read "RE…"). The strip
        /// draws 81 to 89 hundredths of its cells' words at `.large` on 375 pt and at `.xLarge` and
        /// `.xxLarge` on 402 pt, plain and with Bold Text; 96 to 104 everywhere else. Fails in those six cases.
        @Test(
            "The seed week's strip draws all the words of its seven cells, at every text size and both widths",
            arguments: stripSizes, ViewsSetting.widths
        )
        func strip_seedWeek_drawsItsWordsWhole(_ size: DynamicTypeSize, _ width: CGFloat) throws {
            let cells = try ProgramPreview.builder.builderModel().week.cells
            for isBold in [false, true] {
                let setting = ViewsSetting(size: size, width: width, isBold: isBold)
                let share = try Self.wordsDrawn(cells, setting)
                #expect(Self.wholeBand.contains(share), "\(setting.testDescription): \(share) % of the words' pixels")
            }
        }

        /// **FINDING F11-S9-1**, a sibling, by the pixels: ten days, so "D10" on Sunday. 94 hundredths at
        /// `.xxxLarge` on 375 pt, 92 and 86 at `.accessibility1`, 86 at `.accessibility2` on 402 pt. Fails in
        /// those four cases.
        @Test(
            "With ten days the strip draws all the words of its seven cells, at every text size and both widths",
            arguments: stripSizes, ViewsSetting.widths
        )
        func strip_tenDays_drawsItsWordsWhole(_ size: DynamicTypeSize, _ width: CGFloat) throws {
            let cells = try BuilderState.tenDays.model().week.cells
            let setting = ViewsSetting(size: size, width: width)
            let share = try Self.wordsDrawn(cells, setting)
            #expect(Self.wholeBand.contains(share), "\(setting.testDescription): \(share) % of the words' pixels")
        }
    }

    // MARK: - The two text fields

    extension ProgramViewsCutAdversarialTests {
        /// The height in points of what `view` draws at `size`, on an iPhone 17's width.
        static func height(of view: some View, at size: DynamicTypeSize) throws -> CGFloat {
            try CGFloat(ProgramDrawing.pixels(of: view.environment(\.dynamicTypeSize, size), .light).height)
        }

        /// The height UIKit gives the one text field of `view` at `size`: its line of text.
        static func lineHeight(of view: some View, at size: DynamicTypeSize) throws -> CGFloat {
            let hosted = ProgramTextFieldTests.Hosted(view.environment(\.dynamicTypeSize, size))
            defer { hosted.close() }
            return try #require(hosted.fields.first).frame.height
        }

        static func searchField() -> ExerciseSearchField {
            let model = ExercisePickerModel.Search(placeholder: "Search exercises", query: "Squat")
            return ExerciseSearchField(model: model) { _ in }
        }

        /// **FINDING F11-S9-2** (minor; the review's S-3 by measurement). The search field's pill is the 44 pt
        /// target and nothing more: its line of text has no room above or below. At `.accessibility3` the pill
        /// is 44 pt and the line 40.7; at `.accessibility4` 47 and 46.7; at `.accessibility5` 54 and 54, where
        /// a "q"'s tail stands on the outline (looked at once as a picture). `PillButton` keeps
        /// `LedgerSpacing.s` above and below its words; this asks for `LedgerSpacing.xs`. Fails at those
        /// three sizes.
        @Test("The search field's text stands at least 4 pt inside its pill, above and below", arguments: sizes)
        func searchField_textStandsInsideItsPill(_ size: DynamicTypeSize) throws {
            let pill = try Self.height(of: Self.searchField(), at: size)
            let line = try Self.lineHeight(of: Self.searchField(), at: size)
            #expect(pill - line >= 2 * LedgerSpacing.xs, "pill \(pill) pt, line \(line) pt")
        }

        @Test("The search field's pill and the name field's row are 44 pt targets at every size", arguments: sizes)
        func fields_are44PointTargets(_ size: DynamicTypeSize) throws {
            #expect(try Self.height(of: Self.searchField(), at: size) >= 44)
            let header = ProgramBuilderModel.Header(
                eyebrow: "MY PROGRAM",
                name: "Upper",
                namePlaceholder: "Program name"
            )
            let whole = try Self.height(of: ProgramHeader(model: header) { _ in }, at: size)
            let eyebrow = try Self.height(of: Eyebrow(header.eyebrow), at: size)
            // A pixel of grace: the two heights are whole pixels of a drawing at 1×.
            #expect(whole - eyebrow - LedgerSpacing.xs >= 43, "\(whole) pt with an eyebrow of \(eyebrow) pt")
        }
    }
#endif
