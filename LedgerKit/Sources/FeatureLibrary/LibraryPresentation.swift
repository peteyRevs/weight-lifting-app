import Foundation
import LedgerDomain

/// The Library's logic and its words, in two pure steps, so that a keystroke never formats a row:
/// - `rows(_:)`, made each time a source changes, writes every exercise's row once, in both its forms (with and
///   without its sessions);
/// - `make(_:filter:)`, made on each keystroke and each chip, filters those rows and lays out the screen.
///
/// It filters and sorts nothing itself: the list is `ExerciseSearch.filtered`'s, in its order, and the recent
/// section keeps `recentlyLogged`'s order. Every text comes from `LibraryCopy`; an exercise's name is data, and a
/// weight is the Domain's `formatted(in:)`.
nonisolated enum LibraryPresentation {
    static let separator = " · "
    /// Between the parts of a row's spoken value.
    static let spokenSeparator = ", "

    /// The muscle chips after "All", in order: the Domain's list of them, as the exercise library's.
    static let muscleChips = ExerciseSearch.MuscleFilter.allCases
    /// The equipment chips after "All", in order, as the exercise library's.
    static let equipmentChips = ExerciseSearch.equipmentFilters

    /// Every exercise's row, written once for the sources as they stand.
    struct Rows: Equatable, Sendable {
        /// The live exercises, for the filter.
        let exercises: [Exercise]
        /// Each live exercise's row as ALL EXERCISES draws it.
        let all: [ExerciseID: LibraryModel.Row]
        /// The recent exercises that are live, in `recentlyLogged`'s order, as RECENTLY LOGGED draws them.
        let recent: [LibraryModel.Row]
        let locale: Locale
    }

    static func rows(_ input: LibraryInput) -> Rows {
        let live = Dictionary(input.exercises.map { ($0.id, $0) }) { first, _ in first }
        return Rows(
            exercises: input.exercises,
            all: live.mapValues { row($0, sessions: nil, input: input) },
            recent: input.recent.compactMap { id in
                live[id].map { row($0, sessions: input.sessions[id] ?? 0, input: input) }
            },
            locale: input.locale
        )
    }

    static func make(_ rows: Rows, filter: LibraryFilter) -> LibraryModel {
        // A kind of equipment that has no chip would filter the list with no chip selected.
        let equipment = filter.equipment.flatMap { equipmentChips.contains($0) ? $0 : nil }
        let locale = rows.locale
        return LibraryModel(
            title: LibraryCopy.title,
            newExercise: newExercise,
            search: LibraryModel.Search(
                placeholder: LibraryCopy.searchExercises(rows.exercises.count, locale: locale),
                shortPlaceholder: LibraryCopy.search,
                query: filter.query
            ),
            muscles: chipRow(
                LibraryCopy.muscleRow,
                [ChipSpec(title: LibraryCopy.allChip, isSelected: filter.muscle == nil, action: .setMuscle(nil))]
                    + muscleChips.map {
                        ChipSpec(
                            title: LibraryCopy.muscleFilter($0),
                            isSelected: $0 == filter.muscle,
                            action: .setMuscle($0)
                        )
                    },
                locale: locale
            ),
            equipment: chipRow(
                LibraryCopy.equipmentRow,
                [ChipSpec(title: LibraryCopy.allChip, isSelected: equipment == nil, action: .setEquipment(nil))]
                    + equipmentChips.map {
                        ChipSpec(
                            title: LibraryCopy.equipment($0),
                            isSelected: $0 == equipment,
                            action: .setEquipment($0)
                        )
                    },
                locale: locale
            ),
            content: content(rows, filter: filter, equipment: equipment)
        )
    }

    static let newExercise = LibraryModel.Control(title: LibraryCopy.newExercise, action: .newExercise)

    private static func content(_ rows: Rows, filter: LibraryFilter, equipment: Equipment?) -> LibraryModel.Content {
        guard !rows.exercises.isEmpty else {
            return .noExercises(LibraryModel.Message(text: LibraryCopy.noExercisesYet, control: newExercise))
        }
        let shown = ExerciseSearch.filtered(
            rows.exercises,
            query: filter.query,
            muscle: filter.muscle,
            equipment: equipment
        )
        guard !shown.isEmpty else {
            let clear = LibraryModel.Control(title: LibraryCopy.clearFilters, action: .clearFilters)
            return .nothingMatches(LibraryModel.Message(text: LibraryCopy.nothingMatches, control: clear))
        }
        let passes = Set(shown.map(\.id))
        let recent = rows.recent.filter { passes.contains($0.id) }
        let all = LibraryModel.Section(id: .all, title: LibraryCopy.allExercises, rows: shown.compactMap {
            rows.all[$0.id]
        })
        guard !recent.isEmpty else {
            return .sections([all])
        }
        return .sections([LibraryModel.Section(id: .recent, title: LibraryCopy.recentlyLogged, rows: recent), all])
    }

    /// A chip before it has its place in a row: its title, whether it is the one chosen, and the filter it sets.
    private struct ChipSpec {
        let title: String
        let isSelected: Bool
        let action: LibraryAction
    }

    /// One row of chips, each with its place.
    private static func chipRow(_ name: String, _ chips: [ChipSpec], locale: Locale) -> LibraryModel.ChipRow {
        LibraryModel.ChipRow(chips: chips.enumerated().map { place, chip in
            LibraryModel.Chip(
                id: place,
                title: chip.title,
                spokenLabel: LibraryCopy.spokenChip(row: name, title: chip.title, locale: locale),
                isSelected: chip.isSelected,
                action: chip.action
            )
        })
    }

    /// An exercise's row; `sessions` is given in RECENTLY LOGGED only.
    private static func row(_ exercise: Exercise, sessions: Int?, input: LibraryInput) -> LibraryModel.Row {
        let parts = [
            LibraryCopy.equipment(exercise.equipment),
            LibraryCopy.muscle(exercise.primaryMuscle),
            sessions.map { LibraryCopy.sessions($0, locale: input.locale) },
            exercise.isCustom ? LibraryCopy.custom : nil
        ].compactMap(\.self)
        let best = input.bestSets[exercise.id]?.weight.formatted(in: input.units)
        let spokenBest = best.map { LibraryCopy.spokenRecord($0, units: input.units, locale: input.locale) }
        return LibraryModel.Row(
            id: exercise.id,
            name: exercise.name,
            meta: parts.joined(separator: separator),
            record: best ?? LibraryCopy.noRecord,
            spokenValue: (parts + [spokenBest].compactMap(\.self)).joined(separator: spokenSeparator),
            action: .route(.exercise(exercise.id))
        )
    }
}
