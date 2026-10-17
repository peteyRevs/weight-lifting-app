#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, gate G2, round 1, criteria 6 and 7 by measurement, wider than `ProgramViewsLayoutTests` goes:
    /// every text size (twelve, not four), a 375 pt phone beside the iPhone 17, and the states no preview
    /// draws (ten days, sixteen deload weeks, a day of twelve exercises under a long name, 224 rows). In each,
    /// with Bold Text and right to left too, no stop is empty, outside the page, a target under 44 pt, or over
    /// another stop.
    @Suite("Adversarial F11 S9 · frames at every size and width", .serialized, .tags(.feature))
    struct ProgramViewsLayoutAdversarialTests {
        /// Every text size; on the hosted PR runner (`TestSweep`) the four representatives.
        nonisolated static let sizes = TestSweep.sizes(DynamicTypeSize.allCases)

        static func faults(of view: some View, at size: DynamicTypeSize) -> [String] {
            ViewsSetting.sweep(size).flatMap { setting in
                ProgramViewsProbe.faults(in: ProgramViewsProbe.placed(view, setting), width: setting.width)
                    .map { "\(setting.testDescription): \($0)" }
            }
        }

        @Test(
            "Every preview lays out soundly at every text size, on both widths",
            arguments: ProgramPreview.allCases,
            sizes
        )
        func previews_layOutSoundly(_ preview: ProgramPreview, _ size: DynamicTypeSize) {
            let faults = Self.faults(of: ProgramParts(preview: preview), at: size)
            #expect(faults.isEmpty, "\(faults.count) faults: \(faults.prefix(3).joined(separator: "; "))")
        }

        @Test("Each of this tester's builder states lays out soundly", arguments: BuilderState.allCases, sizes)
        func builder_states_layOutSoundly(_ state: BuilderState, _ size: DynamicTypeSize) throws {
            let faults = try Self.faults(of: ProgramPage(model: state.model()) { _ in }, at: size)
            #expect(faults.isEmpty, "\(faults.count) faults: \(faults.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "Each of this tester's library states lays out soundly, the 224 rows too",
            arguments: LibraryState.allCases, TestSweep.sizes([
                DynamicTypeSize.xSmall,
                .large,
                .xxxLarge,
                .accessibility3,
                .accessibility5
            ])
        )
        func library_states_layOutSoundly(_ state: LibraryState, _ size: DynamicTypeSize) throws {
            let faults = try Self.faults(of: ExercisePickerParts(model: state.model()), at: size)
            #expect(faults.isEmpty, "\(faults.count) faults: \(faults.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "The strip's seven targets are 44 pt on a 375 pt phone at every size at which they share a row",
            arguments: sizes
        )
        func strip_375_targets(_ size: DynamicTypeSize) throws {
            let model = try ProgramPreview.builder.builderModel()
            let setting = ViewsSetting(size: size, width: 375)
            let stops = ProgramViewsProbe.placed(ProgramPage(model: model) { _ in }, setting)
            let cells = ProgramViewsAlone.cells(of: model).map { stops[$0].frame }
            #expect(cells.count == 7)
            #expect(cells.allSatisfy { $0.width >= 43.5 && $0.height >= 43.5 }, "\(cells.map(\.size))")
        }

        @Test("The check sees a stop outside a narrower page, and two stops over each other")
        func check_seesFaults() {
            let title = "A pill whose one line of words is wider than a page of 375 points, by a good many points"
            let wide = PillButton(title) {}.fixedSize()
            let setting = ViewsSetting(width: 375)
            let outside = ProgramViewsProbe.faults(in: ProgramViewsProbe.placed(wide, ViewsSetting()), width: 375)
            #expect(outside.count == 1 && outside.first?.hasPrefix("outside the page") == true, "\(outside)")
            let stacked = ZStack {
                Text(verbatim: "one")
                Text(verbatim: "two")
            }
            let over = ProgramViewsProbe.faults(in: ProgramViewsProbe.placed(stacked, setting), width: 375)
            #expect(over.count == 1 && over.first?.hasPrefix("overlap") == true, "\(over)")
        }
    }
#endif
