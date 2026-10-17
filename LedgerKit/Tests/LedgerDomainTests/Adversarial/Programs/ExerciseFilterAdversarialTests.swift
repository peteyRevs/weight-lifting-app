import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 11: the library's combined filter over the seed catalog, against a filter written here
/// from the plan's row ("keeps the exercises whose primary muscle is in the chip's groups, whose equipment
/// is the one asked for, and whose name or short name holds the query; in name order") and decision #23.
@Suite("ExerciseSearch.filter (adversarial)", .tags(.domain))
struct ExerciseFilterAdversarialTests {
    typealias Chip = ExerciseSearch.MuscleFilter

    let catalog: [Exercise]

    init() throws {
        catalog = try ExerciseCatalog.seed()
    }

    /// The plan's chips: legs are quads, hamstrings, glutes and calves; arms are biceps, triceps and forearms.
    static let chips: [Chip: Set<MuscleGroup>] = [
        .chest: [.chest], .back: [.back], .shoulders: [.shoulders],
        .legs: [.quads, .hamstrings, .glutes, .calves], .arms: [.biceps, .triceps, .forearms]
    ]

    static let queries = [
        "", "   ", "\t", "row", "ROW", " Row ", "r\u{F3}w", "\u{FF32}\u{FF2F}\u{FF37}", "ohp", "rdl", "bench",
        "chest-supported", "lat pull", "press", "db", "zzzz", "-", "e", "\u{301}", "row\u{0}"
    ]

    /// Decision #23's comparison: case, diacritics and width never matter; blanks at the ends are dropped.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An exercise with its two names folded once.
    struct Entry {
        let exercise: Exercise
        let name: String
        let shortName: String

        init(_ exercise: Exercise) {
            self.exercise = exercise
            name = ExerciseFilterAdversarialTests.folded(exercise.name)
            shortName = ExerciseFilterAdversarialTests.folded(exercise.shortName)
        }
    }

    /// The filter as the plan words it; the ids in name order (the folded name, then the id).
    static func reference(_ entries: [Entry], _ query: String, _ chip: Chip?, _ equipment: Equipment?) -> [ExerciseID] {
        let needle = folded(query)
        let kept = entries.filter { entry in
            let muscleFits = chip.map { chips[$0]?.contains(entry.exercise.primaryMuscle) ?? false } ?? true
            let equipmentFits = equipment.map { $0 == entry.exercise.equipment } ?? true
            let named = entry.name.contains(needle) || entry.shortName.contains(needle)
            return muscleFits && equipmentFits && (needle.isEmpty || named)
        }
        let ordered = kept.sorted {
            ($0.name, $0.exercise.id.rawValue.uuidString) < ($1.name, $1.exercise.id.rawValue.uuidString)
        }
        return ordered.map(\.exercise.id)
    }

    static func custom(_ number: Int, _ name: String, _ muscle: MuscleGroup, _ equipment: Equipment) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(number)),
            name: name,
            shortName: name.uppercased(),
            equipment: equipment,
            primaryMuscle: muscle,
            pattern: .horizontalPull,
            defaultStartLoad: [:],
            isCustom: true
        )
    }
}

extension ExerciseFilterAdversarialTests {
    @Test("Criterion 12: \"row\" with Back and Machine on the seed catalog is exactly Chest-Supported Row.")
    func filter_rowBackMachine_isChestSupportedRow() {
        let rows = ExerciseSearch.filtered(catalog, query: "row", muscle: .back, equipment: .machine)
        #expect(rows.map(\.name) == ["Chest-Supported Row"])
    }

    @Test("The five chips stand for the plan's muscle groups, and no chip stands for the core.")
    func muscleFilter_groups_areThePlans() {
        #expect(Chip.allCases.count == 5)
        for chip in Chip.allCases {
            #expect(chip.groups == Self.chips[chip], "\(chip)")
        }
        let covered = Chip.allCases.reduce(into: Set<MuscleGroup>()) { $0.formUnion($1.groups) }
        #expect(covered == Set(MuscleGroup.allCases).subtracting([.core]))
        #expect(Chip.allCases.map(\.groups.count).reduce(0, +) == 10, "a muscle group is under two chips")
    }

    @Test(
        "Every chip or none, every equipment or none, and twenty queries give the reference's exercises in its order."
    )
    func filter_everyCombination_matchesTheReference() {
        var tally = Tally()
        let entries = catalog.map(Entry.init)
        let chips: [Chip?] = [nil] + Chip.allCases
        let equipment: [Equipment?] = [nil] + Equipment.allCases
        for chip in chips {
            for kind in equipment {
                for query in Self.queries {
                    let rows = ExerciseSearch.filtered(catalog, query: query, muscle: chip, equipment: kind).map(\.id)
                    let expected = Self.reference(entries, query, chip, kind)
                    let asked = "\(String(describing: chip)) \(String(describing: kind))"
                    let note = "\(asked) query of \(query.unicodeScalars.count) scalars"
                    tally.check(rows == expected, "\(note): \(rows.count) rows, expected \(expected.count)")
                }
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 6 * 8 * 20)
    }

    @Test(
        "With no chip, no equipment and a blank query the whole catalog comes back, each exercise once, in name order."
    )
    func filter_nothingAsked_isTheWholeCatalogInNameOrder() {
        for query in ["", "  ", "\n"] {
            let rows = ExerciseSearch.filtered(catalog, query: query, muscle: nil, equipment: nil)
            #expect(rows.count == 224)
            #expect(Set(rows.map(\.id)).count == 224)
            let names = rows.map { Self.folded($0.name) }
            let inNameOrder = names == names.sorted()
            #expect(inNameOrder)
        }
    }

    @Test(
        "The catalog's order does not matter: a shuffled catalog gives the same rows in the same order.",
        arguments: PropertySeed.all.prefix(20)
    )
    func filter_shuffledCatalog_givesTheSameRows(seed: PropertySeed) {
        var generator = seed.generator
        let shuffled = catalog.shuffled(using: &generator)
        let chips: [Chip?] = [nil] + Chip.allCases
        let chip = chips.randomElement(using: &generator) ?? nil
        let query = Self.queries.randomElement(using: &generator) ?? ""
        let rows = ExerciseSearch.filtered(shuffled, query: query, muscle: chip, equipment: nil).map(\.id)
        let same = rows == Self.reference(catalog.map(Entry.init), query, chip, nil)
        #expect(same, "\(seed)")
    }

    @Test("Core exercises fit no chip: all 26 are listed under \"All\", by name too, and none under any chip.")
    func filter_coreExercises_areUnderAllOnly() {
        let core = Set(catalog.filter { $0.primaryMuscle == .core }.map(\.id))
        #expect(core.count == 26)
        let all = Set(ExerciseSearch.filtered(catalog, query: "", muscle: nil, equipment: nil).map(\.id))
        #expect(core.isSubset(of: all))
        for chip in Chip.allCases {
            let rows = Set(ExerciseSearch.filtered(catalog, query: "", muscle: chip, equipment: nil).map(\.id))
            #expect(rows.isDisjoint(with: core), "\(chip)")
        }
        let crunches = ExerciseSearch.filtered(catalog, query: "crunch", muscle: nil, equipment: nil)
        #expect(!crunches.isEmpty)
        let underArms = ExerciseSearch.filtered(catalog, query: "crunch", muscle: .arms, equipment: nil)
        #expect(underArms.map(\.name) == [])
    }

    @Test("Kettlebell and band exercises, which have no chip, are found by their equipment: 15 and 11.")
    func filter_equipmentWithoutAChip_isStillFiltered() {
        #expect(ExerciseSearch.filtered(catalog, query: "", muscle: nil, equipment: .kettlebell).count == 15)
        #expect(ExerciseSearch.filtered(catalog, query: "", muscle: nil, equipment: .band).count == 11)
    }

    @Test("A query that is only in short names finds them: \"ohp\" and \"RDL\" match no name of the catalog.")
    func filter_shortNameOnlyQuery_matches() {
        for query in ["ohp", "RDL"] {
            let rows = ExerciseSearch.filtered(catalog, query: query, muscle: nil, equipment: nil)
            #expect(!rows.isEmpty, "\(query)")
            #expect(rows.allSatisfy { Self.folded($0.shortName).contains(Self.folded(query)) }, "\(query)")
            #expect(rows.contains { !Self.folded($0.name).contains(Self.folded(query)) }, "\(query)")
        }
    }

    @Test("Custom exercises are filtered like the catalog's, and two with one name keep one order, by id.")
    func filter_customExercises_areIncludedAndOrdered() {
        let customs = [
            Self.custom(9102, "Meadows Row", .back, .machine),
            Self.custom(9101, "Meadows Row", .back, .machine),
            Self.custom(9103, "Meadows Row", .core, .machine),
            Self.custom(9104, "m\u{E9}adows row", .back, .barbell)
        ]
        let rows = ExerciseSearch.filtered(customs + catalog, query: "ROW", muscle: .back, equipment: .machine)
        #expect(rows.map(\.name) == ["Chest-Supported Row", "Meadows Row", "Meadows Row"])
        #expect(rows.suffix(2).map { EditAdv.number($0.id.rawValue) } == [9101, 9102])
        let accented = ExerciseSearch.filtered(customs, query: "MEADOWS", muscle: nil, equipment: .barbell)
        #expect(accented.map { EditAdv.number($0.id.rawValue) } == [9104])
        let ofNothing = ExerciseSearch.filtered([], query: "row", muscle: .back, equipment: .machine)
        #expect(ofNothing.map(\.name) == [])
    }
}
