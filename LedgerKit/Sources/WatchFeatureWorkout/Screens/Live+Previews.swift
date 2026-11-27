#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Set ready and the rest screen in each state they draw, built through the presentation and its copy as the
    /// store builds them, with time standing still at `Fixtures.now`, the Wednesday of week 5: for the previews and
    /// the snapshot tests (`WatchLiveSnapshotTests`). The workout began 24 minutes before, its first set logged 30 s
    /// before, at 142 BPM, with the iPhone connected.
    nonisolated enum LiveSample: CaseIterable {
        /// Lower A's squat, set 2 of 5, in pounds and in kilograms.
        case ready, readyKg
        /// Upper A's pulldown and lateral raise, a superset whose first round is logged: "A · SET 2 OF 3".
        case superset
        /// Health is not allowed: "— BPM", and the line that asks for it.
        case healthDenied
        /// 60 s left of a 90 s rest, in pounds and in kilograms; and "GO", at its end.
        case rest, restKg, restOver

        static let loggedAt = Fixtures.now.addingTimeInterval(-30)

        var state: WorkoutState? {
            try? workout()
        }

        var input: WatchLiveInput {
            WatchLiveInput(
                heartRate: HeartRateSample(bpm: 142, date: Fixtures.now),
                health: self == .healthDenied ? .denied : .authorized,
                connection: .connected(.mirroring),
                hasHeardPhone: true,
                locale: Fixtures.locale
            )
        }

        func workout() throws -> WorkoutState {
            let program = try Fixtures.seedProgram()
            let catalog = try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
            var session = try SessionBuilder.build(
                program: program, weekIndex: 4, day: program.days[self == .superset ? 0 : 1], exercises: catalog,
                history: [:], settings: [.readyKg, .restKg].contains(self) ? Fixtures.settingsKg : Fixtures.settingsLb,
                id: Fixtures.sessionID, device: Fixtures.deviceID, now: Fixtures.now.addingTimeInterval(-24 * 60)
            )
            for (exercise, set) in self == .superset ? [(3, 0), (4, 0)] : [(0, 0)] {
                session.exercises[exercise].sets[set].doneAt = Self.loggedAt
            }
            let resting = RestTimer(endsAt: Fixtures.now.addingTimeInterval(60), total: .seconds(90))
            switch self {
            case .rest, .restKg: session.rest = resting
            case .restOver: session.rest = RestTimer(endsAt: Fixtures.now, total: .seconds(30))
            default: break
            }
            return session
        }

        var readyModel: WatchReadyModel? {
            state.flatMap { WatchPresentation.ready($0, at: Fixtures.now, input) }
        }

        var restModel: WatchRestModel? {
            state.flatMap { state in
                let mode = WatchMode(state, at: Fixtures.now, summaryDismissed: false)
                return WatchPresentation.rest(state, mode: mode, at: Fixtures.now, input)
            }
        }

        /// The crown's dial on the shown set, as the store follows it.
        @MainActor var dial: CrownDial? {
            var crown = CrownWeightModel()
            crown.follow(state.flatMap(WatchWorkoutStore.crownReading))
            return WatchPresentation.crownDial(crown, locale: Fixtures.locale)
        }

        /// The screen in this state, its time fixed; its taps go nowhere.
        @MainActor var screen: some View {
            Group {
                if let model = restModel {
                    WatchRestScreen(model: model, send: { _ in })
                } else if let model = readyModel {
                    WatchReadyScreen(model: model, dial: dial, send: { _ in })
                }
            }
            .environment(\.watchTimeline, .fixed(at: Fixtures.now))
        }
    }

    #Preview("Ready — lb") {
        WatchWorkoutPreview.readyLb.content
    }

    #Preview("Ready — kg") {
        WatchWorkoutPreview.readyKg.content
    }

    #Preview("Ready — superset") {
        WatchWorkoutPreview.readySuperset.content
    }

    #Preview("Ready — Health denied") {
        WatchWorkoutPreview.readyHealthDenied.content
    }

    #Preview("Rest") {
        WatchWorkoutPreview.rest.content
    }

    #Preview("Rest — GO") {
        WatchWorkoutPreview.restGo.content
    }
#endif
