#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The screen before a workout in each state it draws, built through the presentation and its copy as the store
    /// builds it: the seed program at `Fixtures.now`, the Wednesday of week 5 (Lower A), for the previews and the
    /// snapshot tests (`WatchIdleSnapshotTests`).
    nonisolated enum IdleSample: CaseIterable {
        /// Lower A to start.
        case plan
        /// Thursday: nothing scheduled, and Friday's session next.
        case restDay
        case noProgram
        /// Lower A finished this morning, in pounds and in kilograms: no "Start".
        case logged, loggedKg

        /// The app's name the previews show; the app reads its own (`CFBundleDisplayName`).
        static let appName = "Ledger"

        /// The model, or nil when a fixture does not build (a preview then shows the black ground alone).
        var model: WatchIdleModel? {
            (try? input()).map(WatchPresentation.idle)
        }

        func input() throws -> WatchIdleInput {
            let program = try Fixtures.seedProgram()
            let catalog = try ExerciseCatalog.seed()
            let settings = self == .loggedKg ? Fixtures.settingsKg : Fixtures.settingsLb
            return try WatchIdleInput(
                program: self == .noProgram ? nil : program,
                exercises: Dictionary(catalog.map { ($0.id, $0) }) { first, _ in first },
                workout: self == .logged || self == .loggedKg ? Self.loggedLowerA(program, catalog, settings) : nil,
                settings: settings,
                now: self == .restDay ? Fixtures.now.addingTimeInterval(86400) : Fixtures.now,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale,
                appName: Self.appName
            )
        }

        /// Lower A of week 5, begun an hour before `Fixtures.now`, every set logged as prescribed, and finished.
        static func loggedLowerA(
            _ program: Program,
            _ catalog: [Exercise],
            _ settings: Settings
        ) throws -> WorkoutState {
            var state = try SessionBuilder.build(
                program: program, weekIndex: 4, day: program.days[1],
                exercises: Dictionary(catalog.map { ($0.id, $0) }) { first, _ in first }, history: [:],
                settings: settings, id: Fixtures.sessionID, device: Fixtures.deviceID,
                now: Fixtures.now.addingTimeInterval(-3600)
            )
            for exercise in state.exercises.indices {
                for set in state.exercises[exercise].sets.indices {
                    state.exercises[exercise].sets[set].doneAt = Fixtures.now.addingTimeInterval(-600)
                }
            }
            state.phase = .finished
            state.endedAt = Fixtures.now.addingTimeInterval(-300)
            return state
        }

        /// The screen in this state; its taps go nowhere.
        @MainActor @ViewBuilder var screen: some View {
            if let model {
                WatchIdleScreen(model: model, send: { _ in })
            }
        }
    }

    #Preview("Idle — plan") {
        WatchWorkoutPreview.idlePlan.content
    }

    #Preview("Idle — rest day") {
        WatchWorkoutPreview.idleRestDay.content
    }

    #Preview("Idle — no program") {
        WatchWorkoutPreview.idleNoProgram.content
    }

    #Preview("Idle — logged") {
        WatchWorkoutPreview.idleLogged.content
    }
#endif
