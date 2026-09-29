#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import UIKit

    /// Asserts `view` against its reference in one cell of the phone matrix. Every phone snapshot goes
    /// through here, so none can leave a step out (F06 review S1): the appearance is applied with
    /// `snapshotAppearance(_:)` (SwiftUI's environment, the view's own height) and as traits, with
    /// ``SnapshotConfig``'s precisions. `name` defaults to the appearance (`dark-xLarge`);
    /// `modifyingTraits` adds traits on top of the appearance's, for example Increase Contrast.
    public func assertPhoneSnapshot(
        of view: some View,
        _ appearance: SnapshotAppearance,
        named name: String? = nil,
        modifyingTraits: (inout any UIMutableTraits) -> Void = { _ in },
        fileID: StaticString = #file,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertSnapshot(
            of: view.snapshotAppearance(appearance),
            as: .image(
                precision: SnapshotConfig.precision,
                perceptualPrecision: SnapshotConfig.perceptualPrecision,
                layout: .sizeThatFits,
                traits: appearance.traits.modifyingTraits(modifyingTraits)
            ),
            named: name ?? appearance.description,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
#endif
