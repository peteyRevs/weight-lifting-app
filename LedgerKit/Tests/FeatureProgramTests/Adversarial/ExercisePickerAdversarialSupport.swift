@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport

/// F11 S8 adversarial round 1: the tester's own reading of the exercise library sheet, written from the
/// slice's criteria 6 to 13 and the brief's "Copy (exact)" and never from the feature's code. `AdvPicker.lines`
/// is the whole screen as lines of text, once from an input by the tester's rules and once from the model
/// `make` built; the suites compare the two.
nonisolated enum AdvPicker {
    static let muscleWords: [MuscleGroup: String] = [
        .chest: "Chest", .back: "Back", .shoulders: "Shoulders", .quads: "Quads", .hamstrings: "Hamstrings",
        .glutes: "Glutes", .calves: "Calves", .biceps: "Biceps", .triceps: "Triceps", .forearms: "Forearms",
        .core: "Core"
    ]
    static let equipmentWords: [Equipment: String] = [
        .barbell: "Barbell", .dumbbell: "Dumbbell", .cable: "Cable", .machine: "Machine",
        .bodyweight: "Bodyweight", .kettlebell: "Kettlebell", .band: "Band"
    ]
    /// Pete's decision 3, default B: the chips after "All", with the muscle groups each stands for.
    static let muscleChips: [(title: String, filter: ExerciseSearch.MuscleFilter)] = [
        ("Chest", .chest), ("Back", .back), ("Shoulders", .shoulders), ("Legs", .legs), ("Arms", .arms)
    ]
    static let muscleGroups: [ExerciseSearch.MuscleFilter: Set<MuscleGroup>] = [
        .chest: [.chest], .back: [.back], .shoulders: [.shoulders],
        .legs: [.quads, .hamstrings, .glutes, .calves], .arms: [.biceps, .triceps, .forearms]
    ]
    static let equipmentChips: [(title: String, equipment: Equipment)] = [
        ("Barbell", .barbell), ("Dumbbell", .dumbbell), ("Cable", .cable), ("Machine", .machine),
        ("Bodyweight", .bodyweight)
    ]

    /// Decision #23's key, spelled by the tester: case, marks and width folded away, then trimmed.
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The exercises the list shows, in name order, by the tester's own filter.
    static func shown(_ input: ExercisePickerInput) -> [Exercise] {
        let needle = key(input.query)
        let groups = input.muscle.flatMap { muscleGroups[$0] }
        let equipment = equipmentChips.first { $0.equipment == input.equipment }?.equipment
        return input.exercises
            .filter { exercise in
                (groups?.contains(exercise.primaryMuscle) ?? true)
                    && (equipment.map { $0 == exercise.equipment } ?? true)
                    && (needle.isEmpty || key(exercise.name).contains(needle)
                        || key(exercise.shortName).contains(needle))
            }
            .sorted {
                (key($0.name), $0.id.rawValue.uuidString) < (key($1.name), $1.id.rawValue.uuidString)
            }
    }

    /// The picks that count: stored, each once, at its first place.
    static func picks(_ input: ExercisePickerInput) -> [ExerciseID] {
        var found: [ExerciseID] = []
        for pick in input.picks where !found.contains(pick) && input.exercises.contains(where: { $0.id == pick }) {
            found.append(pick)
        }
        return found
    }

    static func number(_ value: Int, _ locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// The foot's text in English, with the count written as the locale writes numbers.
    static func footTitle(_ count: Int, _ locale: Locale) -> String {
        switch count {
        case 0: "Select exercises to add"
        case 1: "Add \(number(1, locale)) exercise"
        default: "Add \(number(count, locale)) exercises"
        }
    }
}

// MARK: - The screen as lines

nonisolated extension AdvPicker {
    /// The screen the criteria describe for `input`, a line for each thing drawn, spoken or tappable.
    static func lines(expectedFor input: ExercisePickerInput) -> [String] {
        let picked = picks(input)
        let listed = shown(input)
        var lines = ["title Exercise library", "cancel Cancel \(ExercisePickerAction.cancel)"]
        lines.append("search Search exercises [\(input.query)]")
        lines.append("row Muscle")
        lines.append(chip(0, "Muscle", "All", input.muscle == nil, .setMuscle(nil)))
        for (place, entry) in muscleChips.enumerated() {
            let isSelected = input.muscle == entry.filter
            lines.append(chip(place + 1, "Muscle", entry.title, isSelected, .setMuscle(entry.filter)))
        }
        let chosen = equipmentChips.first { $0.equipment == input.equipment }?.equipment
        lines.append("row Equipment")
        lines.append(chip(0, "Equipment", "All", chosen == nil, .setEquipment(nil)))
        for (place, entry) in equipmentChips.enumerated() {
            let isSelected = chosen == entry.equipment
            lines.append(chip(place + 1, "Equipment", entry.title, isSelected, .setEquipment(entry.equipment)))
        }
        if listed.isEmpty {
            lines.append("empty Nothing matches that filter. | Clear filters \(ExercisePickerAction.clearFilters)")
        }
        lines += listed.map { row($0, input: input, picked: picked) }
        let add: ExercisePickerAction? = picked.isEmpty ? nil : .add(picked)
        lines.append("foot \(footTitle(picked.count, input.locale)) \(String(describing: add))")
        return lines
    }

    static func chip(
        _ place: Int,
        _ row: String,
        _ title: String,
        _ isSelected: Bool,
        _ action: ExercisePickerAction
    ) -> String {
        "chip \(place) \(title) | \(row): \(title) | \(isSelected) | \(action)"
    }

    static func row(_ exercise: Exercise, input: ExercisePickerInput, picked: [ExerciseID]) -> String {
        let detail = "\(equipmentWords[exercise.equipment] ?? "?") · \(muscleWords[exercise.primaryMuscle] ?? "?")"
        let isInDay = input.dayExercises.contains(exercise.id)
        let line = isInDay ? "\(detail) · already in this day" : detail
        // Sanctioned edit (S14, Pete's question 4, A): the row has its line alone; no detail, mark or place
        // apart from it.
        let isPicked = picked.contains(exercise.id)
        let action = ExercisePickerAction.setPicked(!isPicked, exercise: exercise.id)
        return [
            "exercise \(exercise.id.rawValue.uuidString)", exercise.name, line, "\(isPicked)", "\(action)"
        ].joined(separator: " | ")
    }

    /// The same lines read off a model `make` built.
    static func lines(of model: ExercisePickerModel) -> [String] {
        var lines = ["title \(model.title)", "cancel \(model.cancel.title) \(model.cancel.action)"]
        lines.append("search \(model.search.placeholder) [\(model.search.query)]")
        for chips in [model.muscles, model.equipment] {
            lines.append("row \(chips.spokenLabel)")
            lines += chips.chips
                .map { "chip \($0.id) \($0.title) | \($0.spokenLabel) | \($0.isSelected) | \($0.action)" }
        }
        switch model.content {
        case let .nothingMatches(empty):
            lines.append("empty \(empty.message) | \(empty.clear.title) \(empty.clear.action)")
        case let .rows(rows):
            lines += rows.map { row in
                [
                    "exercise \(row.id.rawValue.uuidString)", row.name,
                    row.line, "\(row.isPicked)", "\(row.action)"
                ].joined(separator: " | ")
            }
        }
        lines.append("foot \(model.foot.title) \(String(describing: model.foot.action))")
        return lines
    }

    /// The first line at which the two screens part, or nil when they are one screen.
    static func difference(_ input: ExercisePickerInput) -> String? {
        let expected = lines(expectedFor: input)
        let found = lines(of: ExercisePickerPresentation.make(input))
        if let place = zip(expected, found).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
            return "line \(place.offset): expected «\(place.element.0)» found «\(place.element.1)»"
        }
        return expected.count == found.count ? nil : "expected \(expected.count) lines, found \(found.count)"
    }
}

// MARK: - Inputs and the store's part

nonisolated extension AdvPicker {
    static let names = [
        "Élévation latérale", "ＥＬＥＶＡＴＩＯＮ", "elevation", "Curl 💪", "تمرين الضغط", "דחיקת חזה", "Row · Row",
        "", "   ", "İstanbul Press", "Straße Pull", "a", "A", "ａ", "e\u{301}clair", "éclair", "Zercher Squat",
        "100% %@ %lld", "Row\nRow", "Ｒｏｗ　Ｒｏｗ"
    ]
    static let queries = [
        "", " ", "\n\t ", "\u{3000}", "ELEV", "é", "e\u{301}", "ｒｏｗ", "💪", "ضغط", "ss", "ß", "i", "İ", "zzz",
        " row ", "·", "%@", "a"
    ]
    /// Locales whose plural rules give English's forms for the counts drawn here (none to eight picks). A
    /// locale with no singular (ja_JP, zh_CN, ko_KR) is left out: there the foot reads "Add 1 exercises",
    /// finding F11-S8-1, which `ExercisePickerWordsAdversarialTests.foot_pluralForms_areEnglishInEveryLocale`
    /// shows by itself; with it here every seeded test would fail for that one cause.
    static let locales = ["en_US", "en_GB", "de_DE", "fr_FR", "ar_EG", "hi_IN", "ru_RU", "pl_PL", "he_IL"]
    static let stranger = ExerciseID(Fixtures.uuid(88001))

    static func exercise(_ number: Int, using generator: inout SeededGenerator) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(60000 + number)),
            name: names.randomElement(using: &generator) ?? "",
            shortName: ["", "ROW", "ÉLÉV", "x"].randomElement(using: &generator) ?? "",
            equipment: Equipment.allCases.randomElement(using: &generator) ?? .band,
            primaryMuscle: MuscleGroup.allCases.randomElement(using: &generator) ?? .core,
            pattern: .isolation,
            defaultStartLoad: [:],
            isCustom: Bool.random(using: &generator)
        )
    }

    /// A random input over exercises the tester makes: none to forty of them, names of every script, any
    /// chip or kind of equipment, picks with repeats and a stranger, day exercises with a stranger.
    static func input(using generator: inout SeededGenerator) -> ExercisePickerInput {
        let count = [0, 1, 2, Int.random(in: 0 ... 40, using: &generator)].randomElement(using: &generator) ?? 0
        let exercises = (0 ..< count).map { exercise($0, using: &generator) }.shuffled(using: &generator)
        let known = exercises.map(\.id) + [stranger]
        let muscles: [ExerciseSearch.MuscleFilter?] = [nil, nil] + ExerciseSearch.MuscleFilter.allCases
        let equipment: [Equipment?] = [nil, nil] + Equipment.allCases
        return ExercisePickerInput(
            exercises: exercises,
            dayExercises: Set(known.filter { _ in Int.random(in: 0 ..< 3, using: &generator) == 0 }),
            query: Bool.random(using: &generator) ? "" : queries.randomElement(using: &generator) ?? "",
            muscle: muscles.randomElement(using: &generator) ?? nil,
            equipment: equipment.randomElement(using: &generator) ?? nil,
            picks: (0 ..< Int.random(in: 0 ... 8, using: &generator)).compactMap { _ in
                known.randomElement(using: &generator)
            },
            locale: Locale(identifier: locales.randomElement(using: &generator) ?? "en_US")
        )
    }

    struct Applied {
        var input: ExercisePickerInput
        var isOpen = true
        var added: [ExerciseID]?
    }

    /// `input` after `action`, as `ExercisePickerAction`'s documentation gives the store's part.
    static func apply(_ action: ExercisePickerAction, to input: ExercisePickerInput) -> Applied {
        var applied = Applied(input: input)
        switch action {
        case let .setQuery(text):
            applied.input.query = text
        case let .setMuscle(muscle):
            applied.input.muscle = muscle
        case let .setEquipment(equipment):
            applied.input.equipment = equipment
        case let .setPicked(isPicked, exercise):
            let wasPicked = applied.input.picks.contains(exercise)
            if isPicked, !wasPicked {
                applied.input.picks.append(exercise)
            } else if !isPicked {
                applied.input.picks.removeAll { $0 == exercise }
            }
        case .clearFilters:
            applied.input.query = ""
            applied.input.muscle = nil
            applied.input.equipment = nil
        case let .add(exercises):
            applied.added = exercises
            fallthrough
        case .cancel:
            applied.input.query = ""
            applied.input.picks = []
            applied.isOpen = false
        }
        return applied
    }

    /// Every action a model hands out.
    static func actions(of model: ExercisePickerModel) -> [ExercisePickerAction] {
        var actions = [model.cancel.action] + model.muscles.chips.map(\.action) + model.equipment.chips.map(\.action)
        switch model.content {
        case let .rows(rows): actions += rows.map(\.action)
        case let .nothingMatches(empty): actions.append(empty.clear.action)
        }
        return actions + [model.foot.action].compactMap(\.self)
    }
}
