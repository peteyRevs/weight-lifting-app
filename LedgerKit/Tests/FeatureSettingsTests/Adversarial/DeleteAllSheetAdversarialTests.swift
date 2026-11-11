#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F14 S3 G2 (adversarial), hosted: the sheet at every Dynamic Type size, not only the sweep's four, xxxLarge (the
    /// largest size without the accessibility sizes) among them; its exact VoiceOver tree and a sane layout at each.
    @Suite("Adversarial F14 S3 · Delete all data sheet at every size", .serialized, .tags(.feature))
    struct DeleteAllSheetAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        @Test(
            "Criterion 6.2 (G2). At every size each state reads its exact tree and lays out sanely",
            arguments: DeleteAllPreview.allCases,
            sizes
        )
        func everySize_treeAndLayout(_ preview: DeleteAllPreview, _ size: DynamicTypeSize) throws {
            let model = try DeleteAllSheetTests.model(preview)
            let appearance = SnapshotAppearance(.light, size)
            let parts = DeleteAllParts(model: model)
            let difference = firstDifference(found: parts.stops(appearance), expected: DeleteAllSheetTests.tree(model))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
            let stops = try parts.placedStops(appearance)
            let faults = SettingsLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(preview.rawValue) at \(size): \(faults.prefix(4).joined(separator: "\n"))")
        }
    }
#endif
