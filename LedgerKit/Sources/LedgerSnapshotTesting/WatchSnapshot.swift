import SnapshotTesting
import SwiftUI
import Testing

/// One cell of the watch matrix (F06 criterion 4): a case size at a text size. The watch has one,
/// dark, appearance, so there is no colour scheme.
public nonisolated struct WatchAppearance: Sendable, CustomStringConvertible {
    public let size: WatchSize
    public let dynamicTypeSize: DynamicTypeSize

    public init(_ size: WatchSize, _ dynamicTypeSize: DynamicTypeSize) {
        self.size = size
        self.dynamicTypeSize = dynamicTypeSize
    }

    /// 42, 46 and 49 mm, each at its default text size and at `.accessibility3`, the largest watch text
    /// size (HIG, Typography: watchOS's larger accessibility type sizes end at AX3).
    public static let matrix: [WatchAppearance] = WatchSize.allCases.flatMap { size in
        [WatchAppearance(size, size.dynamicTypeSize), WatchAppearance(size, .accessibility3)]
    }

    /// For example `mm42-large`; used in reference names.
    public var description: String {
        "\(size.rawValue)-\(dynamicTypeSize)"
    }
}

/// Asserts `view` against its reference in one cell of the watch matrix: rendered with
/// `RenderedImage` (swift-snapshot-testing has no watchOS image strategy) at the case's width and
/// the view's own height, at the cell's text size, and compared with ``SnapshotConfig``'s precisions
/// through the `.png` strategy. `name` defaults to the cell (`mm42-large`).
public func assertWatchSnapshot(
    of view: some View,
    _ appearance: WatchAppearance,
    named name: String? = nil,
    fileID: StaticString = #file,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let sized = view.frame(width: appearance.size.size.width).fixedSize(horizontal: false, vertical: true)
    guard let image = RenderedImage.render(sized, dynamicTypeSize: appearance.dynamicTypeSize) else {
        Issue.record("\(appearance): the view did not render")
        return
    }
    assertSnapshot(
        of: image,
        as: .png,
        named: name ?? appearance.description,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}
