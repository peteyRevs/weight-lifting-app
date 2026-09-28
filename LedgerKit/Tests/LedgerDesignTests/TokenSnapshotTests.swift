@testable import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

/// Specimen sheets of every token, recorded on the PR-plan simulators (iPhone 17 / Apple Watch
/// Series 11 46 mm, OS 26.5). The phone sheets run the criterion 3 matrix.
@Suite("TokenSnapshots", .tags(.design, .snapshot))
struct TokenSnapshotTests {
    #if os(iOS)
        @Test("The phone type ramp matches its references", arguments: SnapshotAppearance.phoneMatrix)
        func phoneTypeRamp_appearance_matchesReference(_ appearance: SnapshotAppearance) {
            assertSnapshot(
                of: TypeRampSpecimen(roles: Specimen.phoneRoles, width: SnapshotConfig.phoneWidth),
                as: .image(
                    precision: SnapshotConfig.precision,
                    perceptualPrecision: SnapshotConfig.perceptualPrecision,
                    layout: .sizeThatFits,
                    traits: appearance.traits
                ),
                named: appearance.description
            )
        }

        @Test("The phone palette matches its references", arguments: [ColorScheme.light, .dark])
        func phonePalette_scheme_matchesReference(_ scheme: ColorScheme) {
            let appearance = SnapshotAppearance(scheme, .large)
            assertSnapshot(
                of: PaletteSpecimen(swatches: PaletteSpecimen.phone, width: SnapshotConfig.phoneWidth),
                as: .image(
                    precision: SnapshotConfig.precision,
                    perceptualPrecision: SnapshotConfig.perceptualPrecision,
                    layout: .sizeThatFits,
                    traits: appearance.traits
                ),
                named: appearance.description
            )
        }
    #endif

    #if os(watchOS)
        @Test("The watch type ramp matches its reference at 46 mm")
        func watchTypeRamp_46mm_matchesReference() throws {
            let sheet = TypeRampSpecimen(
                roles: Specimen.watchRoles, width: WatchSize.mm46.size.width,
                ground: LedgerColor.watchGround, ink: LedgerColor.watchInk, nameInk: LedgerColor.watchInkMuted
            )
            let image = try #require(RenderedImage.render(sheet, dynamicTypeSize: WatchSize.mm46.dynamicTypeSize))
            assertSnapshot(of: image, as: .png, named: WatchSize.mm46.rawValue)
        }

        @Test("The watch palette matches its reference")
        func watchPalette_46mm_matchesReference() throws {
            let sheet = PaletteSpecimen(
                swatches: PaletteSpecimen.watch, width: WatchSize.mm46.size.width,
                ground: LedgerColor.watchGround, ink: LedgerColor.watchInk
            )
            let image = try #require(RenderedImage.render(sheet, dynamicTypeSize: WatchSize.mm46.dynamicTypeSize))
            assertSnapshot(of: image, as: .png, named: WatchSize.mm46.rawValue)
        }
    #endif
}
