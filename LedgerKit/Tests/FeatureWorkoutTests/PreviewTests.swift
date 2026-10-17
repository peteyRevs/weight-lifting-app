#if DEBUG
    @testable import FeatureWorkout
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureWorkout is a case of `WorkoutPreview`, and every case renders (the
    /// convention F07's criterion 8 set for each module with previews).
    @Suite("Previews (FeatureWorkout)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureWorkout is a WorkoutPreview case, by name, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureWorkout")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(WorkoutPreview.allCases.map(\.rawValue)))
        }

        @Test("Every preview renders", arguments: WorkoutPreview.allCases)
        func preview_renders(_ preview: WorkoutPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("Every preview shows the state it is named for: its fixture builds, and the screen is the state's")
        func preview_showsItsState() throws {
            var kinds: [String] = []
            for preview in WorkoutPreview.allCases {
                switch preview.model {
                case .loading: kinds.append("loading")
                case .failed: kinds.append("failed")
                case let .workout(workout): kinds.append(workout.header.isEnabled ? "workout" : "busy")
                }
            }
            #expect(kinds == [
                "workout",
                "workout",
                "workout",
                "workout",
                "workout",
                "workout",
                "workout",
                "busy",
                "loading",
                "failed"
            ])
            // The time each case's header counts to, as the one formatter writes it.
            let elapsed = try [WorkoutPreview.started, .minutes, .hour].map { preview in
                try ClockText.elapsed(preview.workout().elapsed(at: preview.now))
            }
            #expect(elapsed == ["0:00", "24:22", "1:01:05"])
            // What the two states of the page are named for (F10 S5).
            let logging = try #require(WorkoutPreview.logging.model.page?.card)
            #expect(logging.rows.map(\.state) == [.done, .done, .active, .pending, .pending])
            #expect(logging.repeatLast == "Repeat")
            let dropSet = try #require(WorkoutPreview.dropSet.model.page)
            #expect(dropSet.card?.rows.map(\.label) == ["1", "2", "3", "D"])
            #expect(dropSet.card?.columns.weight == "kg")
            #expect(dropSet.remaining == nil)
            #expect(WorkoutPreview.started.model.page?.card?.last == "No history yet")
        }
    }
#endif
