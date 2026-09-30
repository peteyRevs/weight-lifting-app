import Foundation
import LedgerDomain

/// `ExerciseRepository`'s contract as named clauses (F05): search matching (Pete, 2026-09-30; product decision
/// #23), catalog seeding (criterion 11, and the orchestrator's rule of 2026-09-30 that a catalog entry is never
/// skipped over a name) and observation. Every clause gets a fresh, empty repository.
public enum ExerciseRepositoryContract {
    public typealias Clause = ContractClause<any ExerciseRepository>

    public static let clauses: [Clause] = [
        Clause("a saved exercise reads back by id and in all(); saving it again overwrites it", saveReadsBack),
        Clause("search matches a substring of the name or short name, ignoring case and diacritics", searchText),
        Clause("search combines the text with the equipment and primary-muscle filters", searchFilters),
        Clause("search reads % and _ as plain characters", searchWildcards),
        Clause("seeding one version twice changes nothing, and never touches a custom exercise", seedIdempotent),
        Clause("a higher version adds only the new ids; a lower one changes nothing", seedUpgrade),
        Clause("a catalog entry named like a custom exercise is seeded beside it", seedNameClash),
        Clause("observeAll emits the exercises now, then after each change", observeAll)
    ]

    // MARK: Fixtures

    /// A custom exercise ("Landmine Press"), barbell and chest.
    public static let landmine = custom(0x1A, "Landmine Press", "Landmine", .barbell, .chest)

    /// Search fixtures: bench and incline presses, an RDL, a diacritic name, two rows and a name with `%`.
    public static let searchable: [Exercise] = [
        custom(0x51, "Barbell Bench Press", "Bench", .barbell, .chest),
        custom(0x52, "Incline DB Press", "Incline DB", .dumbbell, .chest),
        custom(0x53, "Romanian Deadlift", "RDL", .barbell, .hamstrings),
        custom(0x54, "Élévation Latérale", "Lateral", .dumbbell, .shoulders),
        custom(0x55, "Chest-Supported Row", "CS Row", .machine, .back),
        custom(0x56, "Seated Cable Row", "Cable Row", .cable, .back),
        custom(0x57, "Box Squat (50%)", "Box Squat", .barbell, .quads)
    ]

    /// A custom exercise with id `number`.
    public static func custom(
        _ number: Int,
        _ name: String,
        _ shortName: String,
        _ equipment: Equipment,
        _ muscle: MuscleGroup
    ) -> Exercise {
        Exercise(
            id: ExerciseID(EventBuilders.uuid(0x0E00_0000 + number)),
            name: name,
            shortName: shortName,
            equipment: equipment,
            primaryMuscle: muscle,
            secondaryMuscles: [.triceps, .shoulders],
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(45)],
            isCustom: true
        )
    }

    // MARK: Clauses

    static func saveReadsBack(_ repository: any ExerciseRepository) async throws -> String? {
        try await repository.save(landmine)
        let first = try await (repository.exercise(id: landmine.id), repository.all())
        var renamed = landmine
        renamed.name = "Landmine Press (Kneeling)"
        renamed.defaultStartLoad = [.kg: .kilograms(20)]
        try await repository.save(renamed)
        let second = try await (repository.exercise(id: landmine.id), repository.all())
        let unknown = try await repository.exercise(id: Seeders.catalogID(9999))
        return ContractCheck.expect(first.0, landmine, "exercise(id:) after one save")
            ?? ContractCheck.expect(first.1, [landmine], "all() after one save")
            ?? ContractCheck.expect(second.0, renamed, "exercise(id:) after a second save")
            ?? ContractCheck.expect(second.1, [renamed], "all() after a second save")
            ?? ContractCheck.expect(unknown, nil, "exercise(id:) of an unknown id")
    }

    static func searchText(_ repository: any ExerciseRepository) async throws -> String? {
        for exercise in searchable {
            try await repository.save(exercise)
        }
        let cases: [(query: String, expected: [String])] = [
            ("press", ["Barbell Bench Press", "Incline DB Press"]), // a substring in the middle
            ("RDL", ["Romanian Deadlift"]), // the short name
            ("  ELEVATION ", ["Élévation Latérale"]), // case, diacritics and blanks
            ("élé", ["Élévation Latérale"]),
            ("bench press", ["Barbell Bench Press"]),
            ("zzz", []),
            ("", searchable.map(\.name).sorted { $0.folded < $1.folded })
        ]
        for (query, expected) in cases {
            let found = try await repository.search(query, equipment: nil, muscle: nil).map(\.name)
            if let issue = ContractCheck.expect(found, expected, "search(\"\(query)\")") {
                return issue
            }
        }
        return nil
    }

    static func searchFilters(_ repository: any ExerciseRepository) async throws -> String? {
        for exercise in searchable {
            try await repository.save(exercise)
        }
        struct Filtered {
            let query: String
            let equipment: Equipment?
            let muscle: MuscleGroup?
            let expected: [String]
        }
        let cases = [
            Filtered(query: "row", equipment: .machine, muscle: .back, expected: ["Chest-Supported Row"]),
            Filtered(
                query: "row",
                equipment: nil,
                muscle: .back,
                expected: ["Chest-Supported Row", "Seated Cable Row"]
            ),
            Filtered(query: "", equipment: .cable, muscle: nil, expected: ["Seated Cable Row"]),
            Filtered(query: "press", equipment: .barbell, muscle: nil, expected: ["Barbell Bench Press"]),
            Filtered(query: "press", equipment: nil, muscle: .back, expected: [])
        ]
        for filtered in cases {
            let found = try await repository.search(
                filtered.query,
                equipment: filtered.equipment,
                muscle: filtered.muscle
            ).map(\.name)
            let what = "search(\"\(filtered.query)\", \(String(describing: filtered.equipment)), "
                + "\(String(describing: filtered.muscle)))"
            if let issue = ContractCheck.expect(found, filtered.expected, what) {
                return issue
            }
        }
        return nil
    }

    static func searchWildcards(_ repository: any ExerciseRepository) async throws -> String? {
        for exercise in searchable {
            try await repository.save(exercise)
        }
        let percent = try await repository.search("%", equipment: nil, muscle: nil).map(\.name)
        let underscore = try await repository.search("_", equipment: nil, muscle: nil).map(\.name)
        let pattern = try await repository.search("B%h", equipment: nil, muscle: nil).map(\.name)
        return ContractCheck.expect(percent, ["Box Squat (50%)"], "search(\"%\")")
            ?? ContractCheck.expect(underscore, [], "search(\"_\")")
            ?? ContractCheck.expect(pattern, [], "search(\"B%h\")")
    }
}

extension String {
    /// Case and diacritics folded, as the contract's expected orders compare names.
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
