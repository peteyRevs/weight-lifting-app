import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1, product decision #23: a substring of the name or the short name, ignoring case
/// and diacritics, combined with the equipment and muscle filters; aliases are not searched.
@Suite("Adversarial S2 · exercise search", .tags(.persistence), .timeLimit(.minutes(1)))
struct ExerciseSearchAdversarialTests {
    static let library: [Exercise] = [
        S2Kit.exercise(1, "Barbell Bench Press", short: "Bench"),
        S2Kit.exercise(2, "Incline Dumbbell Bench", short: "Incline DB", equipment: .dumbbell),
        S2Kit.exercise(
            3,
            "Romanian Deadlift",
            short: "RDL",
            muscle: .hamstrings,
            secondary: [.glutes],
            pattern: .hinge
        ),
        S2Kit.exercise(
            4,
            "Overhead Press",
            short: "OHP",
            muscle: .shoulders,
            secondary: [.triceps],
            pattern: .verticalPush
        ),
        S2Kit.exercise(5, "Chest-Supported Row", short: "CS Row", equipment: .machine, muscle: .back),
        S2Kit.exercise(6, "Élévation Latérale", short: "Lat Raise", equipment: .dumbbell, muscle: .shoulders),
        S2Kit.exercise(7, "E\u{301}cole Squat", short: "Ecole", muscle: .quads, pattern: .squat),
        S2Kit.exercise(8, "50% Squat_Pause", short: "Half\\Pause", muscle: .quads, isCustom: true),
        S2Kit.exercise(9, "Jalapeño Curl", short: "Piñata", equipment: .cable, muscle: .biceps, pattern: .isolation),
        S2Kit.exercise(10, "Über Row [Band]", short: "O'Brien \"Row\"", equipment: .band, muscle: .back),
        S2Kit.exercise(
            11,
            "Farmer Carry 🧺",
            short: "Carry",
            equipment: .kettlebell,
            muscle: .forearms,
            pattern: .carry
        ),
        S2Kit.exercise(12, "Straße Lunge", short: "Lunge", equipment: .bodyweight, muscle: .quads, pattern: .lunge)
    ]

    static func repository() async throws -> GRDBExerciseRepository {
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        for exercise in library.reversed() {
            try await repository.save(exercise)
        }
        return repository
    }

    static func names(
        _ query: String,
        _ equipment: Equipment? = nil,
        _ muscle: MuscleGroup? = nil
    ) async throws -> Set<Int> {
        let found = try await repository().search(query, equipment: equipment, muscle: muscle)
        return Set(found.compactMap { exercise in library.firstIndex { $0.id == exercise.id }.map { $0 + 1 } })
    }

    struct Case: Sendable, CustomStringConvertible {
        let query: String
        let expected: Set<Int>
        var description: String {
            "\"\(query.unicodeScalars.map { $0.isASCII ? String($0) : $0.escaped(asASCII: true) }.joined())\""
        }
    }

    static let cases: [Case] = [
        Case(query: "bench", expected: [1, 2]), Case(query: "BENCH", expected: [1, 2]), Case(
            query: "nch pr",
            expected: [1]
        ),
        Case(query: "rdl", expected: [3]), Case(query: "OHP", expected: [4]), Case(query: "row", expected: [5, 10]),
        Case(query: "elevation", expected: [6]), Case(query: "ÉLÉVATION", expected: [6]), Case(
            query: "élévation",
            expected: [6]
        ),
        Case(query: "e\u{301}le\u{301}vation", expected: [6]), Case(query: "école", expected: [7]),
        Case(query: "ECOLE SQ", expected: [7]), Case(query: "jalapeno", expected: [9]), Case(
            query: "PINATA",
            expected: [9]
        ),
        Case(query: "uber", expected: [10]), Case(query: "ÜBER", expected: [10]), Case(query: "%", expected: [8]),
        Case(query: "50%", expected: [8]), Case(query: "_", expected: [8]), Case(query: "t_p", expected: [8]),
        Case(query: "%s", expected: []), Case(query: "\\", expected: [8]), Case(query: "f\\p", expected: [8]),
        Case(query: "[band]", expected: [10]), Case(query: "[", expected: [10]), Case(query: "*", expected: []),
        Case(query: "?", expected: []), Case(query: "o'b", expected: [10]), Case(query: "\"row\"", expected: [10]),
        Case(query: "'", expected: [10]), Case(query: "🧺", expected: [11]), Case(query: "carry 🧺", expected: [11]),
        Case(query: "press bench", expected: []), Case(query: "press oh", expected: []), Case(
            query: "deadlift rdl",
            expected: []
        ),
        Case(query: "barbell bench press and more", expected: []), Case(query: "  ohp  ", expected: [4]),
        Case(query: "bench  press", expected: []), Case(query: "chest", expected: [5]), Case(query: "-", expected: [5])
    ]

    @Test("Each query finds exactly the exercises whose name or short name contains it", arguments: cases)
    func query_findsExactly(_ testCase: Case) async throws {
        #expect(try await Self.names(testCase.query) == testCase.expected)
    }

    @Test("A blank query (empty, spaces, tabs, newlines) finds every exercise, with the filters still applied")
    func blankQuery_findsEverything() async throws {
        for blank in ["", " ", "   ", "\t", "\n", " \t\n "] {
            #expect(try await Self.names(blank) == Set(1 ... 12), "\(blank.debugDescription)")
            #expect(try await Self.names(blank, .dumbbell) == [2, 6], "\(blank.debugDescription)")
        }
    }

    @Test("Equipment and muscle filters combine with the text by AND")
    func filters_combine() async throws {
        #expect(try await Self.names("row", .machine) == [5])
        #expect(try await Self.names("row", nil, .back) == [5, 10])
        #expect(try await Self.names("row", .band, .back) == [10])
        #expect(try await Self.names("row", .band, .chest) == [])
        #expect(try await Self.names("squat", nil, .quads) == [7, 8])
        #expect(try await Self.names("", .kettlebell, .forearms) == [11])
    }

    @Test("(documents) The muscle filter matches the primary muscle only, not a secondary one")
    func muscleFilter_isPrimaryOnly() async throws {
        #expect(try await Self.names("", nil, .glutes) == [])
        #expect(try await Self.names("", nil, .triceps) == [])
    }

    @Test("(documents) \"ss\" and \"ß\" find each other (case folding is full folding)")
    func sharpS() async throws {
        #expect(try await Self.names("strasse") == [12])
        #expect(try await Self.names("STRASSE") == [12])
        #expect(try await Self.names("straße") == [12])
        #expect(try await Self.names("ße lu") == [12])
    }

    @Test("Results come back in `all()` order, and a soft-deleted exercise is never found")
    func order_andDeletedRows() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        for exercise in Self.library.shuffled() {
            try await repository.save(exercise)
        }
        let all = try await repository.all()
        let found = try await repository.search("", equipment: nil, muscle: nil)
        #expect(found == all)
        #expect(try await repository.search("o", equipment: nil, muscle: nil) == all.filter {
            ($0.name + "\u{0}" + $0.shortName).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .contains("o")
        })
        try await queue.write { database in
            try database.execute(sql: "UPDATE exercise SET deleted_at = 'then' WHERE short_name = 'OHP'")
        }
        #expect(try await repository.search("ohp", equipment: nil, muscle: nil).isEmpty)
        #expect(try await repository.all().count == 11)
    }
}
