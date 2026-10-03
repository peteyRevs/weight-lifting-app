import SwiftUI

/// Where a snapshot is drawn: the phone at `SnapshotConfig.phoneWidth`, or a watch case size.
public nonisolated enum SnapshotDevice: Hashable, Sendable {
    case phone
    case watch(WatchSize)

    /// The phone and every watch size.
    public static let all: [SnapshotDevice] = [.phone] + WatchSize.allCases.map(SnapshotDevice.watch)
}

/// One reference image of `assertLedgerSnapshot`: a phone appearance, or a watch appearance (the watch has
/// one, dark, scheme).
public nonisolated enum SnapshotCell: Sendable, CustomStringConvertible {
    case phone(SnapshotAppearance)
    case watch(WatchAppearance)

    /// The F06 matrix, narrowed to `devices`, `themes` (phone only) and `typeSizes` when given: the phone in
    /// light and dark at `.large`, `.xLarge` and `.accessibility3`; each watch at its default text size and
    /// at `.accessibility3`.
    public static func matrix(
        devices: [SnapshotDevice] = SnapshotDevice.all,
        themes: [ColorScheme] = [.light, .dark],
        typeSizes: [DynamicTypeSize]? = nil
    ) -> [SnapshotCell] {
        devices.flatMap { device -> [SnapshotCell] in
            switch device {
            case .phone:
                themes.flatMap { theme in
                    (typeSizes ?? [.large, .xLarge, .accessibility3]).map { .phone(SnapshotAppearance(theme, $0)) }
                }
            case let .watch(size):
                (typeSizes ?? [size.dynamicTypeSize, .accessibility3]).map { .watch(WatchAppearance(size, $0)) }
            }
        }
    }

    /// For example `dark-xLarge` or `mm46-accessibility3`; used in reference names.
    public var description: String {
        switch self {
        case let .phone(appearance): appearance.description
        case let .watch(appearance): appearance.description
        }
    }
}

/// Asserts `view` against its references across the F06 matrix (`SnapshotCell.matrix`), one reference per cell,
/// named `<name>-<cell>` (or `<cell>` without a name). The simulator a test runs on draws its own cells, phone
/// cells on iOS and watch cells on watchOS, through `assertPhoneSnapshot` and `assertWatchSnapshot`, so every
/// snapshot keeps their appearance steps and precisions; the Mac host draws none (F06 review N3).
public func assertLedgerSnapshot(
    of view: some View,
    named name: String? = nil,
    devices: [SnapshotDevice] = SnapshotDevice.all,
    themes: [ColorScheme] = [.light, .dark],
    typeSizes: [DynamicTypeSize]? = nil,
    fileID: StaticString = #file,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    for cell in SnapshotCell.matrix(devices: devices, themes: themes, typeSizes: typeSizes) {
        let reference = name.map { "\($0)-\(cell)" } ?? cell.description
        switch cell {
        case let .phone(appearance):
            #if os(iOS)
                assertPhoneSnapshot(
                    of: view, appearance, named: reference,
                    fileID: fileID, file: filePath, testName: testName, line: line, column: column
                )
            #else
                _ = appearance
            #endif
        case let .watch(appearance):
            #if os(watchOS)
                assertWatchSnapshot(
                    of: view, appearance, named: reference,
                    fileID: fileID, file: filePath, testName: testName, line: line, column: column
                )
            #else
                _ = appearance
            #endif
        }
    }
}
