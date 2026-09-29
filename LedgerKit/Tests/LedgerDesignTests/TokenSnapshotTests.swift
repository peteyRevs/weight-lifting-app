@testable import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Specimen sheets of every token, recorded on the PR-plan simulators (iPhone 17 / Apple Watch
    /// Series 11 46 mm, OS 26.5). The phone sheets run the criterion 3 matrix.
    @Suite("TokenSnapshots", .tags(.design, .snapshot))
    struct TokenSnapshotTests {
        #if os(iOS)
            @Test("The phone type ramp matches its references", arguments: SnapshotAppearance.phoneMatrix)
            func phoneTypeRamp_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(
                    of: TypeRampSpecimen(roles: Specimen.phoneRoles, width: SnapshotConfig.phoneWidth),
                    appearance
                )
            }

            @Test("The phone palette matches its references", arguments: [ColorScheme.light, .dark])
            func phonePalette_scheme_matchesReference(_ scheme: ColorScheme) {
                assertPhoneSnapshot(
                    of: PaletteSpecimen(swatches: PaletteSpecimen.phone, width: SnapshotConfig.phoneWidth),
                    SnapshotAppearance(scheme, .large)
                )
            }

            @Test("The phone type ramp with Bold Text matches its reference (dark, large)")
            func phoneTypeRamp_boldText_matchesReference() {
                let appearance = SnapshotAppearance(.dark, .large)
                assertPhoneSnapshot(
                    of: TypeRampSpecimen(roles: Specimen.phoneRoles, width: SnapshotConfig.phoneWidth)
                        .environment(\.legibilityWeight, .bold),
                    appearance,
                    named: "bold-\(appearance)"
                )
            }

            @Test(
                "The phone palette with Increase Contrast matches its references",
                arguments: [ColorScheme.light, .dark]
            )
            func phonePalette_increasedContrast_matchesReference(_ scheme: ColorScheme) {
                let appearance = SnapshotAppearance(scheme, .large)
                assertPhoneSnapshot(
                    of: PaletteSpecimen(swatches: PaletteSpecimen.phone, width: SnapshotConfig.phoneWidth),
                    appearance,
                    named: "increasedContrast-\(appearance)",
                    modifyingTraits: { $0.accessibilityContrast = .high }
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

            @Test("The watch type ramp with Bold Text matches its reference at 46 mm")
            func watchTypeRamp_boldText46mm_matchesReference() throws {
                let sheet = TypeRampSpecimen(
                    roles: Specimen.watchRoles, width: WatchSize.mm46.size.width,
                    ground: LedgerColor.watchGround, ink: LedgerColor.watchInk, nameInk: LedgerColor.watchInkMuted
                ).environment(\.legibilityWeight, .bold)
                let image = try #require(RenderedImage.render(sheet, dynamicTypeSize: WatchSize.mm46.dynamicTypeSize))
                assertSnapshot(of: image, as: .png, named: "bold-\(WatchSize.mm46.rawValue)")
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
}
