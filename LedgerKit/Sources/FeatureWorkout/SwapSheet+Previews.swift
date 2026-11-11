#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The previews of the swap sheet (F10 S8b), one case each, drawn from the model the presentation makes
    /// for the bench press of `WorkoutPreview.started`: the alternatives the shipped catalog offers, none
    /// done before, so each brings the load S8 ruling Q1 gives it. `PreviewTests` render every case and fail
    /// on a `#Preview` of the sheet that is not a case here; the references and the VoiceOver trees draw the
    /// same states.
    enum SwapSheetPreview: String, CaseIterable {
        case rows = "Swap exercise"
        case updatingProgram = "Swap exercise, also updating the program"
        case loading = "Swap exercise, loading"
        case empty = "Swap exercise, no alternatives"
        case failed = "Swap exercise, could not load"

        /// The workout whose first exercise, the bench press, is being swapped.
        func workout() throws -> WorkoutState {
            try WorkoutPreview.started.workout()
        }

        /// What the store holds for the sheet in this state.
        func swap(of workout: WorkoutState) throws -> SwapState {
            let bench = workout.exercises[0]
            let alternatives: Loadable<[SwapChoice]> = switch self {
            case .rows, .updatingProgram: try .loaded(Self.choices(replacing: bench, in: workout))
            case .loading: .loading
            case .empty: .loaded([])
            case .failed: .failed(WorkoutPreview.Unreadable())
            }
            return SwapState(
                exerciseIndex: 0,
                exerciseID: bench.exerciseID,
                alternatives: alternatives,
                alsoUpdateProgram: self == .updatingProgram
            )
        }

        /// The bench press's alternatives on the shipped catalog, as the store reads them with no history.
        static func choices(replacing bench: WorkoutExercise, in workout: WorkoutState) throws -> [SwapChoice] {
            let catalog = try ExerciseCatalog.seed()
            guard let stored = catalog.first(where: { $0.id == bench.exerciseID }) else {
                throw WorkoutPreview.Unreadable()
            }
            let others = Set(workout.exercises.map(\.exerciseID))
            return SwapAlternatives.ranked(for: stored, in: catalog, excluding: others).map { exercise in
                SwapChoice(
                    replacing: bench.exerciseID,
                    exerciseID: exercise.id,
                    name: exercise.name,
                    replacement: SwapAlternatives.replacement(
                        of: bench, with: exercise, last: nil, units: workout.units
                    )
                )
            }
        }

        /// The sheet's model; nil when the fixture does not build, which fails `PreviewTests`.
        var model: SwapSheetModel? {
            guard let workout = try? workout(), let swap = try? swap(of: workout) else {
                return nil
            }
            return WorkoutPresentation.swapSheet(swap, in: workout, locale: Fixtures.locale)
        }

        @ViewBuilder var content: some View {
            if let model {
                SwapSheet(model: model) { _ in }
            }
        }
    }

    #Preview("Swap exercise") {
        SwapSheetPreview.rows.content
    }

    #Preview("Swap exercise, also updating the program") {
        SwapSheetPreview.updatingProgram.content
    }

    #Preview("Swap exercise, loading") {
        SwapSheetPreview.loading.content
    }

    #Preview("Swap exercise, no alternatives") {
        SwapSheetPreview.empty.content
    }

    #Preview("Swap exercise, could not load") {
        SwapSheetPreview.failed.content
    }
#endif
