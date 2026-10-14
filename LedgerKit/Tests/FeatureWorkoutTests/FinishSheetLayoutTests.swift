#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F10 S7a, criteria 6, 38 and 39: the "End workout?" sheet in every setting. Nothing of it is cut,
    /// leaves the phone or lies over something else from the default size to the largest, on a 375 pt
    /// phone and an iPhone 17, with Bold Text and right to left (by measurement, `WorkoutLayoutProbe`);
    /// both buttons are full width; and orange is "Save workout" alone.
    @Suite("End workout? sheet layout", .serialized, .tags(.feature))
    struct FinishSheetLayoutTests {
        nonisolated static let sizes = WorkoutPageLayoutTests.sizes

        // MARK: Criteria 38 and 39: sizes, Bold Text, right to left

        static func parts(of model: WorkoutFinishModel) -> [LayoutPart] {
            [
                LayoutPart(model.title) { Text(model.title).ledgerFont(.subheading) },
                LayoutPart(model.keepLifting) { PillButton(model.keepLifting, style: .ghost) {} },
                LayoutPart(model.spokenSummary) {
                    Text(model.summary).ledgerFont(.bodyLight).accessibilityLabel(Text(verbatim: model.spokenSummary))
                },
                LayoutPart(model.save) { PrimaryButton(model.save) {} },
                LayoutPart(model.discard) { PillButton(model.discard, fillsWidth: true) {} }
            ]
        }

        @Test("No word of the sheet is cut, in any setting", arguments: sizes)
        func sheet_noWordIsCut(_ size: DynamicTypeSize) throws {
            for model in try FinishSheetTests.models() {
                let sheet = FinishSheetParts(model: model)
                for setting in LayoutSetting.sweep(size) {
                    let cut = WorkoutLayoutProbe.cut(in: sheet, parts: Self.parts(of: model), setting)
                    #expect(cut.isEmpty, "\(setting.testDescription): \(cut.prefix(2).joined(separator: "; "))")
                }
            }
        }

        @Test("Every stop is inside the phone, none lies over another, and every button is 44 pt", arguments: sizes)
        func sheet_nothingLeavesOrOverlaps(_ size: DynamicTypeSize) throws {
            for model in try FinishSheetTests.models() {
                let sheet = FinishSheetParts(model: model)
                for setting in LayoutSetting.sweep(size) {
                    let misplaced = WorkoutLayoutProbe.misplaced(in: sheet, setting)
                    #expect(
                        misplaced.isEmpty,
                        "\(setting.testDescription): \(misplaced.prefix(2).joined(separator: "; "))"
                    )
                    let buttons = setting.elements(of: sheet).filter { $0.traits.contains(.button) }
                    #expect(buttons.count == 3, "\(setting.testDescription)")
                    let small = buttons.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                    #expect(small.isEmpty, "\(setting.testDescription): \(small.map(\.label))")
                }
            }
        }

        @Test("Both buttons are as wide as the sheet's content, at every size", arguments: sizes)
        func buttons_areFullWidth(_ size: DynamicTypeSize) throws {
            let sheet = try FinishSheetParts(.withSets)
            for setting in LayoutSetting.sweep(size) {
                let stops = setting.elements(of: sheet)
                let save = try #require(stops.first { $0.label == "Save workout" }).frame
                let discard = try #require(stops.first { $0.label == "Discard" }).frame
                #expect(abs(save.width - (setting.width - 2 * LedgerSpacing.xl)) < 0.5, "\(setting.testDescription)")
                #expect(abs(discard.width - save.width) < 0.5, "\(setting.testDescription)")
                #expect(discard.minY >= save.maxY, "Discard stands under Save workout")
            }
        }

        @Test("Right to left the sheet is mirrored: Keep lifting at the other edge, the line in the same order")
        func rightToLeft_isMirrored() throws {
            let sheet = try FinishSheetParts(.withSets)
            func stops(_ isRightToLeft: Bool) throws -> [String: CGRect] {
                let found = LayoutSetting(isRightToLeft: isRightToLeft).elements(of: sheet)
                #expect(found.map(\.label).contains("6 of 18 sets logged, 5,578 lb moved"))
                return Dictionary(found.map { ($0.label, $0.frame) }) { first, _ in first }
            }
            let leading = try stops(false)
            let mirrored = try stops(true)
            let (title, keep) = ("End workout?", "Keep lifting")
            #expect(try #require(leading[keep]).midX > #require(leading[title]).midX)
            #expect(try #require(mirrored[keep]).midX < #require(mirrored[title]).midX)
            #expect(leading.keys.sorted() == mirrored.keys.sorted(), "every line keeps its characters' order")
        }

        @Test("The check sees a line that is cut")
        func check_seesACut() throws {
            let model = try FinishSheetTests.longWords()
            let cutOne = FinishSheetPage(model: model) { _ in }.lineLimit(1).frame(width: 200, alignment: .leading)
            let parts = [Self.parts(of: model)[2]]
            #expect(WorkoutLayoutProbe.cut(in: cutOne, parts: parts, LayoutSetting()).count == 1)
        }

        // MARK: Criterion 6: orange once

        @Test(
            "Orange on the sheet is the fill of Save workout and nothing else; with no set logged there is none",
            arguments: [ColorScheme.light, .dark]
        )
        func orange_isSaveWorkoutAlone(scheme: ColorScheme) throws {
            let width = SnapshotConfig.phoneWidth
            func orange(_ preview: FinishSheetPreview) throws -> (found: [CGPoint], save: CGRect) {
                let sheet = try FinishSheetParts(preview)
                let image = try #require(RenderedImage.render(
                    sheet, width: width, colorScheme: scheme, dynamicTypeSize: .large
                ))
                #expect(image.width == Int(width), "one pixel a point")
                let marked = VStack(spacing: 0) {
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                    sheet
                }
                let stops = marked.frame(width: width).accessibilityElements(SnapshotAppearance(scheme, .large))
                let top = try #require(stops.first { $0.label == "Top" }).frame
                let save = try #require(stops.first { $0.label == "Save workout" }).frame
                return (
                    WorkoutRestPanelAdversarialTests.orange(in: image),
                    save.offsetBy(dx: -top.minX, dy: -top.maxY)
                )
            }
            let withSets = try orange(.withSets)
            let inSave = withSets.found.count { withSets.save.contains($0) }
            #expect(inSave > 500, "\(scheme): Save workout is the sheet's orange button")
            #expect(withSets.found.count == inSave, "\(scheme): \(withSets.found.count - inSave) orange pixels stray")
            #expect(try orange(.zeroSets).found.isEmpty, "\(scheme): a Save workout that cannot save is not orange")
            #expect(try orange(.saving).found.isEmpty, "\(scheme): nor is one that is saving")
        }
    }
#endif
