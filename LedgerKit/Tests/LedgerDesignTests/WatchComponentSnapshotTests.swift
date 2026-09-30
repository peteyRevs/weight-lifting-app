@testable import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

// F06 criterion 4 for the watch components: each component's gallery (every state it has) at 42, 46
// and 49 mm, each at its default text size and at the largest watch text size (AX3), on the watch's
// black; `WatchComponentLayoutTests` checks the same cells for clipping and the 11 pt floor. Recorded on
// the PR-plan simulator (Apple Watch Series 12 46 mm, watchOS 27.0): one watch simulator renders all
// three sizes as fixed layouts (docs/testing-strategy.md §2.5).
#if os(watchOS)
    extension RenderingSuites {
        @Suite("WatchPrimaryButtonSnapshots", .tags(.design, .snapshot))
        struct WatchPrimaryButtonSnapshotTests {
            @Test("WatchPrimaryButton matches its references", arguments: WatchAppearance.matrix)
            func watchPrimaryButton_watchSize_matchesReference(_ appearance: WatchAppearance) {
                assertWatchSnapshot(of: WatchPrimaryButtonGallery().ledgerWatchPage(), appearance)
            }
        }

        @Suite("WatchRestRingSnapshots", .tags(.design, .snapshot))
        struct WatchRestRingSnapshotTests {
            @Test("WatchRestRing matches its references", arguments: WatchAppearance.matrix)
            func watchRestRing_watchSize_matchesReference(_ appearance: WatchAppearance) {
                assertWatchSnapshot(of: WatchRestRingGallery().ledgerWatchPage(), appearance)
            }
        }

        @Suite("WatchStatBlockSnapshots", .tags(.design, .snapshot))
        struct WatchStatBlockSnapshotTests {
            @Test("WatchStatBlock matches its references", arguments: WatchAppearance.matrix)
            func watchStatBlock_watchSize_matchesReference(_ appearance: WatchAppearance) {
                assertWatchSnapshot(of: WatchStatBlockGallery().ledgerWatchPage(), appearance)
            }
        }

        /// The watch components with Bold Text (they follow it: one weight step up) at 46 mm. There is
        /// no Increase Contrast image: the watch palette has one appearance and does not step up.
        @Suite("WatchComponentSheetSnapshots", .tags(.design, .snapshot))
        struct WatchComponentSheetSnapshotTests {
            @Test("The watch components with Bold Text match their reference (46 mm)")
            func watchComponents_boldText_matchesReference() {
                let appearance = WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize)
                assertWatchSnapshot(
                    of: WatchComponents().ledgerWatchPage().environment(\.legibilityWeight, .bold),
                    appearance,
                    named: "bold-\(appearance)"
                )
            }
        }
    }

    /// The watch galleries, one after another.
    struct WatchComponents: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
                WatchPrimaryButtonGallery()
                WatchRestRingGallery()
                WatchStatBlockGallery()
            }
        }
    }
#endif
