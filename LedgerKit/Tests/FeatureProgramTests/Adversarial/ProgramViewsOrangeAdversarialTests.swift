#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F11 S9, gate G2, round 1, criterion 8 (Pete's decision 1, A) from the other side. `ProgramOrangeAudit
    /// Tests` shows that the parts that may be orange are, and that some named parts are not. Here the one
    /// thing that may be orange is taken out of the model and the whole page must then hold no orange pixel:
    /// orange anywhere else, in any state, fails. And with it left in, the page is orange exactly when the
    /// model says so.
    @Suite("Adversarial F11 S9 · the orange audit, whole pages", .serialized, .tags(.feature))
    struct ProgramViewsOrangeAdversarialTests {
        nonisolated static let themes: [ColorScheme] = [.dark, .light]

        /// `model` with no week marked a deload week on its chip, and no title over the strip: what the builder
        /// may draw in orange is the word under a deload week's chip and a selected deload week's title.
        nonisolated static func withoutItsOrange(_ model: ProgramBuilderModel) -> ProgramBuilderModel {
            let chips = model.block.chips.map { chip in
                ProgramBuilderModel.WeekChip(
                    title: chip.title, subtitle: chip.subtitle, isDeload: false, isSelected: chip.isSelected,
                    spokenLabel: chip.spokenLabel, spokenValue: chip.spokenValue, action: chip.action
                )
            }
            let block = ProgramBuilderModel.Block(
                title: model.block.title, spokenLabel: model.block.spokenLabel, spokenValue: model.block.spokenValue,
                removeWeek: model.block.removeWeek, addWeek: model.block.addWeek, chips: chips
            )
            let week = ProgramBuilderModel.SelectedWeek(
                title: "", hint: model.week.hint, cells: model.week.cells, copyPrevious: model.week.copyPrevious,
                applyToLater: model.week.applyToLater, deload: model.week.deload
            )
            return ProgramBuilderModel(
                header: model.header, block: block, week: week, days: model.days, notice: model.notice
            )
        }

        /// `model` with a foot that offers nothing: what the library may draw in orange is its foot's button.
        nonisolated static func withoutItsOrange(_ model: ExercisePickerModel) -> ExercisePickerModel {
            ExercisePickerModel(
                title: model.title, cancel: model.cancel, search: model.search, muscles: model.muscles,
                equipment: model.equipment, content: model.content,
                foot: ExercisePickerModel.Foot(title: model.foot.title, action: nil)
            )
        }

        static func builderModels() throws -> [(name: String, model: ProgramBuilderModel)] {
            try ProgramPreview.builders.map { try ($0.rawValue, $0.builderModel()) }
                + BuilderState.allCases.map { try ($0.rawValue, $0.model()) }
        }

        /// The library's states but the two of 224 rows, whose page is too long to draw whole.
        static func libraryModels() throws -> [(name: String, model: ExercisePickerModel)] {
            try ProgramPreview.libraries.map { try ($0.rawValue, $0.libraryModel()) }
                + [LibraryState.emptyCatalog, .longNames, .longQuery].map { try ($0.rawValue, $0.model()) }
        }

        @Test(
            "Without the deload word and the deload title, no state of the builder draws an orange pixel",
            arguments: themes
        )
        func builder_withoutItsOrange_drawsNone(_ theme: ColorScheme) throws {
            for (name, model) in try Self.builderModels() {
                let page = ProgramPage(model: Self.withoutItsOrange(model)) { _ in }
                #expect(try ProgramDrawing.orangePixels(in: page, theme) == 0, "\(name)")
            }
        }

        @Test(
            "A builder's page is orange exactly when a deload week is not selected, or the selected week is one",
            arguments: themes
        )
        func builder_isOrangeWhenTheModelSaysSo(_ theme: ColorScheme) throws {
            for (name, model) in try Self.builderModels() {
                let mayBeOrange = model.block.chips.contains { $0.isDeload && !$0.isSelected } || model.week.deload.isOn
                let count = try ProgramDrawing.orangePixels(in: ProgramPage(model: model) { _ in }, theme)
                #expect((count > 0) == mayBeOrange, "\(name): \(count) orange pixels")
            }
        }

        @Test("At the largest text size too, the builder without its orange draws none", arguments: themes)
        func builder_largestText_withoutItsOrange_drawsNone(_ theme: ColorScheme) throws {
            for preview in [ProgramPreview.deloadWeek, .emptyDay] {
                let page = try ProgramPage(model: Self.withoutItsOrange(preview.builderModel())) { _ in }
                    .environment(\.dynamicTypeSize, .accessibility3)
                #expect(try ProgramDrawing.orangePixels(in: page, theme) == 0, "\(preview.rawValue)")
            }
        }

        @Test(
            "Without an offering foot, no state of the library draws an orange pixel; with one, the foot is",
            arguments: themes
        )
        func library_withoutItsFoot_drawsNoOrange(_ theme: ColorScheme) throws {
            for (name, model) in try Self.libraryModels() {
                let parts = ExercisePickerParts(model: Self.withoutItsOrange(model))
                #expect(try ProgramDrawing.orangePixels(in: parts, theme) == 0, "\(name)")
                let count = try ProgramDrawing.orangePixels(in: ExercisePickerParts(model: model), theme)
                #expect((count > 1000) == (model.foot.action != nil), "\(name): \(count) orange pixels")
            }
        }

        @Test("The check sees an orange word on a page", arguments: themes)
        func check_seesOrange(_ theme: ColorScheme) throws {
            let model = try Self.withoutItsOrange(ProgramPreview.builder.builderModel())
            let page = VStack {
                ProgramPage(model: model) { _ in }
                Eyebrow("DELOAD", tint: .accent)
            }
            #expect(try ProgramDrawing.orangePixels(in: page, theme) > 0)
        }
    }

    // MARK: - The previews

    /// F11 S9, gate G2, round 1, criterion 5: `PreviewTests.preview_renders` passes when a preview draws an
    /// image of the right size, which an empty view does too. Here every registered preview draws its screen:
    /// more than a ground.
    @Suite("Adversarial F11 S9 · the previews draw", .serialized, .tags(.feature))
    struct ProgramViewsPreviewAdversarialTests {
        @Test("Every registered preview draws a screen and not a blank ground", arguments: ProgramPreview.allCases)
        func preview_drawsItsScreen(_ preview: ProgramPreview) throws {
            let drawn = try ProgramDrawing.pixels(of: preview.content.frame(height: 874), .dark)
            let ground = try #require(drawn.pixels.first)
            let inked = drawn.pixels.count { $0.differs(from: ground, by: 24) }
            #expect(drawn.height == 874)
            #expect(inked > 2000, "\(inked) pixels differ from the ground")
        }

        @Test("The registry holds the eight states the criteria name, and no other")
        func registry_holdsTheNamedStates() {
            #expect(ProgramPreview.allCases.map(\.rawValue) == [
                "Program builder", "Deload week selected", "A day with no exercise", "Two weeks, minus refused",
                "Sixteen weeks and a long name", "Exercise library", "Three exercises picked", "Nothing matches"
            ])
        }
    }
#endif
