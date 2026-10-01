import Foundation
@testable import LedgerDomain
import Testing

/// Criterion 1, the malformed half: a catalog document with any bad entry throws, naming the entry,
/// and nothing is skipped. Each case breaks one field of a valid three-entry document.
@Suite("CatalogEntry", .tags(.domain))
struct CatalogEntryTests {
    @Test("A valid entry maps field by field onto a catalog Exercise")
    func validEntry_mapsEveryField() throws {
        let exercises = try ExerciseCatalog.exercises(from: document())
        #expect(exercises.count == 3)
        let first = try #require(exercises.first)
        #expect(first == Exercise(
            id: RawEntry.idA,
            name: "Press A",
            shortName: "PRESS A",
            equipment: .barbell,
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps],
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(45), .kg: .kilograms(20)],
            isCustom: false,
            curatedAlternatives: [RawEntry.idB, RawEntry.idC]
        ))
    }

    @Test("A bodyweight entry starts at zero with loadKind, and a weighted one gives its added load")
    func bodyweightEntries_decode() throws {
        let exercises = try ExerciseCatalog.exercises(from: document { entries in
            entries[0].equipment = "bodyweight"
            entries[0].startLoad = ["lb": 0, "kg": 0]
            entries[0].loadKind = "bodyweight"
            entries[1].equipment = "bodyweight"
            entries[1].startLoad = ["lb": 45, "kg": 20]
        })
        #expect(exercises[0].defaultStartLoad == [.lb: .zero, .kg: .zero])
        #expect(exercises[1].defaultStartLoad == [.lb: .pounds(45), .kg: .kilograms(20)])
    }

    @Test("A broken entry throws the matching CatalogError", arguments: brokenEntries)
    func brokenEntry_throws(_ broken: BrokenEntry) {
        #expect(throws: broken.error) {
            try ExerciseCatalog.exercises(from: document(broken.edit))
        }
    }

    @Test("An undecodable document throws unreadable", arguments: undecodableDocuments)
    func undecodableDocument_throwsUnreadable(_ broken: UndecodableDocument) {
        let error = #expect(throws: CatalogError.self) {
            try ExerciseCatalog.exercises(from: broken.json())
        }
        if case .unreadable = error {} else {
            Issue.record("expected unreadable, got \(String(describing: error))")
        }
    }

    @Test("A resource missing from the bundle throws missingResource")
    func missingResource_throws() {
        #expect(throws: CatalogError.missingResource("absent.json")) {
            try ExerciseCatalog.resource("absent", withExtension: "json")
        }
    }
}

// MARK: - Documents

/// One entry spelled as the file spells it, so a case can break any field.
struct RawEntry: Encodable, Sendable {
    static let idA = ExerciseID(Fixtures.uuid(0xA))
    static let idB = ExerciseID(Fixtures.uuid(0xB))
    static let idC = ExerciseID(Fixtures.uuid(0xC))
    static let unknownID = ExerciseID(Fixtures.uuid(0xD))

    var id: String
    var name: String
    var shortName: String
    var equipment = "barbell"
    var primaryMuscle = "chest"
    var secondaryMuscles = ["triceps"]
    var pattern = "horizontalPush"
    var startLoad: [String: Decimal]? = ["lb": 45, "kg": 20]
    var loadKind: String?
    var alternatives: [String]
    var aliases: [String] = []

    init(_ id: ExerciseID, _ letter: String, alternatives: [ExerciseID]) {
        self.id = id.rawValue.uuidString
        name = "Press \(letter)"
        shortName = "PRESS \(letter)"
        self.alternatives = alternatives.map(\.rawValue.uuidString)
    }
}

/// Three valid pressing entries, each listing the other two, after `edit`.
private func document(_ edit: (inout [RawEntry]) -> Void = { _ in }) throws -> Data {
    struct Document: Encodable {
        let exercises: [RawEntry]
    }
    var entries = [
        RawEntry(RawEntry.idA, "A", alternatives: [RawEntry.idB, RawEntry.idC]),
        RawEntry(RawEntry.idB, "B", alternatives: [RawEntry.idA, RawEntry.idC]),
        RawEntry(RawEntry.idC, "C", alternatives: [RawEntry.idA, RawEntry.idB])
    ]
    edit(&entries)
    return try JSONEncoder().encode(Document(exercises: entries))
}

// MARK: - Cases

/// A change to the three entries of `document(_:)`.
typealias EntryEdit = @Sendable (inout [RawEntry]) -> Void

struct BrokenEntry: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let error: CatalogError
    let edit: EntryEdit
}

private let idA = RawEntry.idA
private let idB = RawEntry.idB.rawValue.uuidString
private let idC = RawEntry.idC.rawValue.uuidString

private let brokenEntries: [BrokenEntry] = [
    BrokenEntry(testDescription: "repeated id", error: .duplicateID(idA)) { $0[1].id = idA.rawValue.uuidString },
    BrokenEntry(testDescription: "name repeated in lower case", error: .duplicateName("press a")) {
        $0[1].name = "press a"
    },
    BrokenEntry(testDescription: "alias repeats a name", error: .duplicateName("PRESS A")) {
        $0[1].aliases = ["PRESS A"]
    },
    BrokenEntry(testDescription: "alias repeats its own name", error: .duplicateName("press a")) {
        $0[0].aliases = ["press a"]
    },
    BrokenEntry(testDescription: "blank short name", error: .invalidText(idA)) { $0[0].shortName = "" },
    BrokenEntry(testDescription: "untrimmed name", error: .invalidText(idA)) { $0[0].name = " Press A" },
    BrokenEntry(testDescription: "blank alias", error: .invalidText(idA)) { $0[0].aliases = [" "] },
    BrokenEntry(testDescription: "primary as secondary", error: .invalidMuscles(idA)) {
        $0[0].secondaryMuscles = ["chest"]
    },
    BrokenEntry(testDescription: "repeated secondary", error: .invalidMuscles(idA)) {
        $0[0].secondaryMuscles = ["triceps", "triceps"]
    },
    BrokenEntry(testDescription: "lb off the 5 lb barbell step", error: .invalidStartLoad(idA, .lb)) {
        $0[0].startLoad = ["lb": 47.5, "kg": 20]
    },
    BrokenEntry(testDescription: "kg off the 2.5 kg barbell step", error: .invalidStartLoad(idA, .kg)) {
        $0[0].startLoad = ["lb": 45, "kg": 21.25]
    },
    BrokenEntry(testDescription: "negative load", error: .invalidStartLoad(idA, .lb)) {
        $0[0].startLoad = ["lb": -5, "kg": -2.5]
    },
    BrokenEntry(testDescription: "zero load without loadKind", error: .loadKindMismatch(idA)) {
        $0[0].startLoad = ["lb": 0, "kg": 0]
    },
    BrokenEntry(testDescription: "zero load in one unit only", error: .loadKindMismatch(idA)) {
        $0[0].startLoad = ["lb": 0, "kg": 20]
    },
    BrokenEntry(testDescription: "bodyweight loadKind with a load", error: .loadKindMismatch(idA)) {
        $0[0].equipment = "bodyweight"
        $0[0].loadKind = "bodyweight"
    },
    BrokenEntry(testDescription: "bodyweight loadKind on a barbell", error: .loadKindMismatch(idA)) {
        $0[0].startLoad = ["lb": 0, "kg": 0]
        $0[0].loadKind = "bodyweight"
    },
    BrokenEntry(testDescription: "one alternative", error: .invalidAlternatives(idA)) { $0[0].alternatives = [idB] },
    BrokenEntry(testDescription: "itself as an alternative", error: .invalidAlternatives(idA)) {
        $0[0].alternatives = [idA.rawValue.uuidString, idB]
    },
    BrokenEntry(testDescription: "repeated alternative", error: .invalidAlternatives(idA)) {
        $0[0].alternatives = [idB, idB]
    },
    BrokenEntry(
        testDescription: "unknown alternative",
        error: .unknownAlternative(idA, alternative: RawEntry.unknownID)
    ) { $0[0].alternatives = [idB, RawEntry.unknownID.rawValue.uuidString] },
    BrokenEntry(
        testDescription: "alternative with another pattern",
        error: .alternativePatternMismatch(idA, alternative: RawEntry.idC)
    ) { $0[2].pattern = "verticalPush" }
]

struct UndecodableDocument: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let json: @Sendable () throws -> Data
}

/// A valid document with one field broken by `edit` so that it no longer decodes.
private func undecodable(_ description: String, _ edit: @escaping EntryEdit) -> UndecodableDocument {
    UndecodableDocument(testDescription: description) { try document(edit) }
}

private let undecodableDocuments: [UndecodableDocument] = [
    UndecodableDocument(testDescription: "not JSON") { Data("{".utf8) },
    UndecodableDocument(testDescription: "no exercises key") { Data(#"{"contributing": []}"#.utf8) },
    undecodable("unknown equipment") { $0[0].equipment = "sled" },
    undecodable("unknown muscle") { $0[0].primaryMuscle = "neck" },
    undecodable("unknown pattern") { $0[0].pattern = "twist" },
    undecodable("id that is not a UUID") { $0[0].id = "bench-press" },
    undecodable("missing start load") { $0[0].startLoad = nil },
    undecodable("start load without kg") { $0[0].startLoad = ["lb": 45] },
    undecodable("unknown loadKind") { $0[0].loadKind = "external" }
]
