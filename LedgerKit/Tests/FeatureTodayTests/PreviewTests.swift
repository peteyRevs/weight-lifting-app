#if DEBUG
    @testable import FeatureToday
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureToday is a case of `TodayPreview`, and every case renders (the convention
    /// F07's criterion 8 set for each module with previews). The cases are the states of S4's criterion 3.
    @Suite("Previews (FeatureToday)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureToday is a TodayPreview case, by name, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureToday")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(TodayPreview.allCases.map(\.rawValue)))
        }

        @Test("Every preview renders", arguments: TodayPreview.allCases)
        func preview_renders(_ preview: TodayPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }

        @Test("In the app the resume time counts: nothing stops it unless a preview or a test says when")
        func timerPause_isNilByDefault() {
            #expect(EnvironmentValues().todayTimerPause == nil)
        }

        @Test("Every preview shows the state it is named for: its fixture builds, and the card is the state's")
        func preview_showsItsState() throws {
            var kinds: [String] = []
            for preview in TodayPreview.allCases {
                switch preview.state {
                case .idle: kinds.append("idle")
                case .loading: kinds.append("loading")
                case .failed: kinds.append("failed")
                case let .loaded(model): kinds.append(model.card.kind)
                }
            }
            #expect(kinds == [
                "upNext", "upNext", "logged", "restDay", "restDay", "noProgram", "blockComplete", "loading",
                "failed", "upNext", "upNext"
            ])
            #expect(try TodayPreview.resume.model().card.upNext?.action.action.title == "Resume · 3:00")
            #expect(try TodayPreview.resumeOnRestDay.model().header.title == "Rest day")
            #expect(try TodayPreview.mondayVolume.model().stats.volume.delta == "−100%")
            #expect(try TodayPreview.blockComplete.model().stats.sessions.unit == "/0")
        }
    }
#endif
