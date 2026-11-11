#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S3, criterion 6.2, hosted: the sheet's VoiceOver tree, pinned exactly (its title, Cancel, the line, the
    /// failure's line and "Delete everything", dimmed until the word matches), its one text field read from UIKit (the
    /// hosted reader does not list a field: brief risk R5, F12 S3's technique), what each control sends, and its layout
    /// at every text size, read from its parts (`DeleteAllParts`).
    @Suite("Delete all data sheet", .serialized, .tags(.feature))
    struct DeleteAllSheetTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .accessibility3, .accessibility5])

        static func model(_ preview: DeleteAllPreview) throws -> DeleteAllSheetModel {
            try #require(preview.model())
        }

        static func tree(_ model: DeleteAllSheetModel) -> [ViewStop] {
            [.heading(model.title), .button(model.cancel), .text(model.message)]
                + (model.problem.map { [ViewStop.text($0)] } ?? [])
                + [model.confirm == nil ? .dimmedButton(model.confirmTitle) : .button(model.confirmTitle)]
        }

        @Test(
            "Criterion 6.2. Each state has its exact VoiceOver tree, Delete everything dimmed until it acts",
            arguments: DeleteAllPreview.allCases,
            sizes
        )
        func tree_isExactlyTheTable(_ preview: DeleteAllPreview, _ size: DynamicTypeSize) throws {
            let model = try Self.model(preview)
            let found = DeleteAllParts(model: model).stops(SnapshotAppearance(.light, size))
            let difference = firstDifference(found: found, expected: Self.tree(model))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("The sheet has one text field, the word's: its placeholder is DELETE, and it holds the text as typed")
        func field_isTheOneField() throws {
            #expect(try Self.fields(of: Self.model(.empty)) == [["DELETE", ""]])
            #expect(try Self.fields(of: Self.model(.typed)) == [["DELETE", "delete "]])
            #expect(try Self.fields(of: Self.model(.failed)) == [["DELETE", "DELETE"]])
        }

        @Test("Cancel sends cancelDeleteAll; Delete everything sends confirmDeleteAll once the word matches")
        func controls_sendTheirActions() throws {
            for preview in DeleteAllPreview.allCases {
                var sent: [SettingsAction] = []
                let model = try Self.model(preview)
                DeleteAllParts(model: model, send: { sent.append($0) }).withAccessibilityElements { elements in
                    for element in elements where element.accessibilityTraits.contains(.button) {
                        _ = element.accessibilityActivate()
                    }
                }
                let expected: [SettingsAction] = [.cancelDeleteAll] + (model.confirm.map { [$0] } ?? [])
                #expect(sent == expected, "\(preview.rawValue)")
            }
        }

        @Test(
            "In every state and size no stop is empty, outside the sheet, under 44 points or over another",
            arguments: DeleteAllPreview.allCases,
            sizes
        )
        func parts_layOutSanely(_ preview: DeleteAllPreview, _ size: DynamicTypeSize) throws {
            let stops = try DeleteAllParts(model: Self.model(preview)).placedStops(SnapshotAppearance(.dark, size))
            #expect(stops.count >= 4, "the parts were not read")
            let faults = SettingsLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        /// The placeholder and the text of each text field of `model`'s parts, found in the hosted view.
        static func fields(of model: DeleteAllSheetModel) -> [[String]] {
            let host = UIHostingController(rootView: DeleteAllParts(model: model))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            func fields(in view: UIView) -> [UITextField] {
                ((view as? UITextField).map { [$0] } ?? []) + view.subviews.flatMap(fields(in:))
            }
            return fields(in: host.view).map { [$0.placeholder ?? "", $0.text ?? ""] }
        }
    }

    /// F14 S3: the sheet against its references, at the iPhone 17 width and its own height: nothing typed and the
    /// failure at the default size, and the word typed at the default and an accessibility size, light and dark.
    @Suite("Delete all data sheet snapshots", .serialized, .tags(.feature, .snapshot))
    struct DeleteAllSheetSnapshotTests {
        private func parts(_ preview: DeleteAllPreview) throws -> some View {
            try DeleteAllParts(model: #require(preview.model())).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("Nothing typed: Delete everything is dimmed")
        func empty_matchesReferences() throws {
            try assertLedgerSnapshot(of: parts(.empty), devices: [.phone], typeSizes: [.large])
        }

        @Test("The word typed: Delete everything acts, at the default and an accessibility size")
        func typed_matchesReferences() throws {
            try assertLedgerSnapshot(of: parts(.typed), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("An erase that failed: the sheet says nothing was deleted")
        func failed_matchesReferences() throws {
            try assertLedgerSnapshot(of: parts(.failed), devices: [.phone], typeSizes: [.large])
        }
    }
#endif
