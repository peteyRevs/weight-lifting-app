#if DEBUG
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    @testable import WatchFeatureWorkout

    /// F07 criterion 8 for WatchFeatureWorkout: every `#Preview` is a case of `WatchWorkoutPreview`, and every case
    /// renders.
    @MainActor
    @Suite("Previews (WatchFeatureWorkout)", .tags(.watch), .serialized)
    struct PreviewTests {
        @Test("Every #Preview in WatchFeatureWorkout is a WatchWorkoutPreview case, by name, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "WatchFeatureWorkout")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(WatchWorkoutPreview.allCases.map(\.rawValue)))
        }

        @Test("Every preview renders", arguments: WatchWorkoutPreview.allCases)
        func preview_renders(_ preview: WatchWorkoutPreview) {
            #expect(renderPreview(size: WatchSize.mm46.size) { preview.content })
        }
    }
#endif
