#if DEBUG
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import SwiftUI

    // The watch components' galleries: every state each draws, built through the presentation and its copy as the
    // set screen builds them, for the previews and the snapshot tests (`WatchWorkoutComponentSnapshotTests`).

    nonisolated enum ComponentSample {
        static let locale = Locale(identifier: "en_US")

        /// The crown's dial at `weight` in `units`, on the exercise's `step`, not turning.
        static func dial(_ weight: Weight, step: Weight, units: Units) -> CrownDial? {
            var crown = CrownWeightModel()
            let target = CrownWeightModel.Target(exerciseIndex: 0, setID: SetID(UUID()))
            crown.follow(CrownWeightModel.Reading(target: target, weight: weight, step: step, units: units))
            return WatchPresentation.crownDial(crown, locale: locale)
        }

        /// The dots of five sets with `done` of them logged, and what VoiceOver reads for them.
        static func dots(_ done: Int, of count: Int = 5) -> (dots: [Bool], summary: String) {
            let dots = (0 ..< count).map { $0 < done }
            return (dots, WatchWorkoutCopy.setsLogged(done: "\(done)", of: count, locale: locale))
        }
    }

    /// Three digits in pounds, four in pounds, and kilograms on a 2.5 kg step.
    struct CrownWeightGallery: View {
        static let dials = [
            ComponentSample.dial(.pounds(185), step: .pounds(5), units: .lb),
            ComponentSample.dial(.pounds(1025), step: .pounds(5), units: .lb),
            ComponentSample.dial(.kilograms(102.5), step: .kilograms(2.5), units: .kg)
        ].compactMap(\.self)

        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                ForEach(Self.dials, id: \.weight) { dial in
                    CrownWeight(dial: dial, onRotate: { _ in }, onRest: {})
                }
            }
        }
    }

    /// None, two and all of five sets logged, then two with the wrist down.
    struct SetDotsGallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                ForEach([0, 2, 5], id: \.self) { done in
                    let sample = ComponentSample.dots(done)
                    SetDots(dots: sample.dots, accessibilitySummary: sample.summary)
                }
                let wristDown = ComponentSample.dots(2)
                SetDots(dots: wristDown.dots, accessibilitySummary: wristDown.summary)
                    .environment(\.isLuminanceReduced, true)
            }
        }
    }

    /// A reading, and "— BPM" with none yet and with Health denied.
    struct HeartRateLineGallery: View {
        static let lines = [
            WatchPresentation.heartRateLine(
                HeartRateSample(bpm: 142, date: .distantPast), .authorized, locale: ComponentSample.locale
            ),
            WatchPresentation.heartRateLine(nil, .authorized, locale: ComponentSample.locale)
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                ForEach(Self.lines, id: \.value) { HeartRateLine(model: $0) }
            }
        }
    }

    /// Every preview in WatchFeatureWorkout, one case each (F07 criterion 8): each `#Preview` below shows its case's
    /// content, and `PreviewTests` render every case and fail on a `#Preview` that is not a case here.
    enum WatchWorkoutPreview: String, CaseIterable {
        case crownWeight = "CrownWeight"
        case setDots = "SetDots"
        case heartRateLine = "HeartRateLine"
        case idlePlan = "Idle — plan"
        case idleRestDay = "Idle — rest day"
        case idleNoProgram = "Idle — no program"
        case idleLogged = "Idle — logged"
        case readyLb = "Ready — lb"
        case readyKg = "Ready — kg"
        case readySuperset = "Ready — superset"
        case readyHealthDenied = "Ready — Health denied"
        case rest = "Rest"
        case restGo = "Rest — GO"
        case takeover = "Ready — taken over"
        case list = "List"
        case endLogged = "End — logged"
        case endEmpty = "End — nothing logged"
        case summaryRecords = "Summary — records"
        case summaryKg = "Summary — kg"
        case summaryNoRecords = "Summary — no records"

        @ViewBuilder var content: some View {
            switch self {
            case .crownWeight: CrownWeightGallery().ledgerWatchPage()
            case .setDots: SetDotsGallery().ledgerWatchPage()
            case .heartRateLine: HeartRateLineGallery().ledgerWatchPage()
            case .idlePlan: IdleSample.plan.screen
            case .idleRestDay: IdleSample.restDay.screen
            case .idleNoProgram: IdleSample.noProgram.screen
            case .idleLogged: IdleSample.logged.screen
            case .readyLb: LiveSample.ready.screen
            case .readyKg: LiveSample.readyKg.screen
            case .readySuperset: LiveSample.superset.screen
            case .readyHealthDenied: LiveSample.healthDenied.screen
            case .rest: LiveSample.rest.screen
            case .restGo: LiveSample.restOver.screen
            case .takeover: OverlaySample.takeover
            case .list: OverlaySample.list
            case .endLogged: EndSample.logged.screen
            case .endEmpty: EndSample.empty.screen
            case .summaryRecords: SummarySample.records.screen
            case .summaryKg: SummarySample.recordsKg.screen
            case .summaryNoRecords: SummarySample.noRecords.screen
            }
        }
    }

    #Preview("CrownWeight") {
        WatchWorkoutPreview.crownWeight.content
    }

    #Preview("SetDots") {
        WatchWorkoutPreview.setDots.content
    }

    #Preview("HeartRateLine") {
        WatchWorkoutPreview.heartRateLine.content
    }
#endif
