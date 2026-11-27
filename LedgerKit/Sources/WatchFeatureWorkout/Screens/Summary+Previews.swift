#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The summary in each state it draws, built through the presentation and its copy as the store builds it: Lower
    /// A of week 5, every set logged, finished at `Fixtures.now` after 55 minutes, for the previews and the snapshot
    /// tests (`WatchOverlaySnapshotTests`).
    nonisolated enum SummarySample: CaseIterable {
        /// In pounds, two records and Health's average; in kilograms, one record; and none, with no average.
        case records, recordsKg, noRecords

        var model: WatchSummaryModel? {
            (try? workout()).map { state in
                WatchPresentation.summary(
                    state, records: records(state), health: health(state), locale: Fixtures.locale
                )
            }
        }

        func workout() throws -> WorkoutState {
            let settings = self == .recordsKg ? Fixtures.settingsKg : Fixtures.settingsLb
            var state = try IdleSample.loggedLowerA(Fixtures.seedProgram(), ExerciseCatalog.seed(), settings)
            state.startedAt = Fixtures.now.addingTimeInterval(-55 * 60)
            state.endedAt = Fixtures.now
            return state
        }

        func records(_ state: WorkoutState) -> [PersonalRecord] {
            let count = switch self {
            case .records: 2
            case .recordsKg: 1
            case .noRecords: 0
            }
            return state.exercises.prefix(count).map { exercise in
                PersonalRecord(
                    exerciseID: exercise.exerciseID, kind: .weightAtReps(exercise.targetLoad, Reps(clamping: 5)),
                    previous: nil, achievedAt: state.startedAt, workoutID: state.id
                )
            }
        }

        func health(_ state: WorkoutState) -> HealthWorkoutRecord? {
            guard self != .noRecords else {
                return nil
            }
            return HealthWorkoutRecord(
                healthKitUUID: Fixtures.uuid(1800), start: state.startedAt, end: Fixtures.now,
                avgHeartRate: self == .records ? 138 : 141, maxHeartRate: nil, activeEnergyKcal: nil
            )
        }

        /// The screen in this state; its taps go nowhere.
        @MainActor @ViewBuilder var screen: some View {
            if let model {
                WatchSummaryScreen(model: model, send: { _ in })
            }
        }
    }

    /// The session list, the end overlay's workout and the takeover banner, over Lower A of week 5 with its squat
    /// done and the next exercise's first set logged, at `Fixtures.now`.
    nonisolated enum OverlaySample {
        static var workout: WorkoutState? {
            (try? LiveSample.ready.workout()).map { state in
                var state = state
                for set in state.exercises[0].sets.indices {
                    state.exercises[0].sets[set].doneAt = LiveSample.loggedAt
                }
                state.exercises[1].sets[0].doneAt = LiveSample.loggedAt
                return state
            }
        }

        static var listModel: WatchListModel? {
            workout.map { WatchPresentation.list($0, locale: Fixtures.locale) }
        }

        @MainActor @ViewBuilder static var list: some View {
            if let model = listModel {
                WatchListOverlay(model: model, send: { _ in })
            }
        }

        /// Set ready with "Apple Workout took over · logging continues" above it.
        @MainActor static var takeover: some View {
            LiveSample.ready.screen.watchBanner(WatchWorkoutCopy.healthTakenOver)
        }
    }

    /// The end overlay over the list's workout, with sets logged ("Save workout"), and over the same workout before
    /// its first set ("Discard").
    nonisolated enum EndSample: CaseIterable {
        case logged, empty

        var model: WatchEndModel? {
            let state = switch self {
            case .logged: OverlaySample.workout
            case .empty: try? LiveSample.ready.workout().clearingLoggedSets()
            }
            return state.map { WatchPresentation.end($0, locale: Fixtures.locale) }
        }

        /// The overlay in this state; its taps go nowhere.
        @MainActor @ViewBuilder var screen: some View {
            if let model {
                WatchEndOverlay(model: model, send: { _ in })
            }
        }
    }

    private extension WorkoutState {
        nonisolated func clearingLoggedSets() -> WorkoutState {
            var state = self
            for exercise in state.exercises.indices {
                for set in state.exercises[exercise].sets.indices {
                    state.exercises[exercise].sets[set].doneAt = nil
                }
            }
            return state
        }
    }

    #Preview("Summary — records") {
        WatchWorkoutPreview.summaryRecords.content
    }

    #Preview("Summary — kg") {
        WatchWorkoutPreview.summaryKg.content
    }

    #Preview("Summary — no records") {
        WatchWorkoutPreview.summaryNoRecords.content
    }

    #Preview("List") {
        WatchWorkoutPreview.list.content
    }

    #Preview("End — logged") {
        WatchWorkoutPreview.endLogged.content
    }

    #Preview("End — nothing logged") {
        WatchWorkoutPreview.endEmpty.content
    }

    #Preview("Ready — taken over") {
        WatchWorkoutPreview.takeover.content
    }
#endif
