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

        /// F18 S4, on a trimmed matrix (orchestrator ruling: 20 new references at most): the 46 mm default, the
        /// design's own size, and 42 mm at AX3, the narrowest screen at the largest text. 49 mm and 42 mm at its
        /// default size are left to the screens' snapshots (F18 S5).
        @Suite("WatchPillSnapshots", .tags(.design, .snapshot))
        struct WatchPillSnapshotTests {
            nonisolated static let trimmed = [
                WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize), WatchAppearance(.mm42, .accessibility3)
            ]

            @Test("WatchPill matches its references", arguments: trimmed)
            func watchPill_watchSize_matchesReference(_ appearance: WatchAppearance) {
                assertWatchSnapshot(of: WatchPillGallery().ledgerWatchPage(), appearance)
            }

            /// Always-On (`isLuminanceReduced`, R1 §5.5): the ring at full, half and empty and the orange pill, each
            /// in the dimmed accent; the track, the times and the white label as they are.
            @Test("The ring and the pill with the wrist down match their reference (46 mm)")
            func alwaysOn_ringAndPill_matchesReference() {
                let appearance = WatchAppearance(.mm46, WatchSize.mm46.dynamicTypeSize)
                let sheet = VStack(spacing: LedgerSpacing.l) {
                    WatchRestRingGallery()
                    WatchPill("Skip") {}
                }
                assertWatchSnapshot(
                    of: sheet.ledgerWatchPage().environment(\.isLuminanceReduced, true),
                    appearance,
                    named: "alwaysOn-\(appearance)"
                )
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
