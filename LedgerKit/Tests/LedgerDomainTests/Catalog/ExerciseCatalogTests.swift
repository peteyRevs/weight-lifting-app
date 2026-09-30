import CryptoKit
import Foundation
@testable import LedgerDomain
import Testing

/// The bundled catalog against F03's acceptance criteria. The malformed-input half of criterion 1 is
/// in `CatalogEntryTests`; criterion 8's fixture is checked in `CatalogSeedFixtureTests`.
///
/// These tests read the module's own resource bundle, as `seed()` does in the app.
@Suite("ExerciseCatalog", .tags(.domain))
struct ExerciseCatalogTests {
    /// Read and decoded once per run, not once per test case (review N8): Swift Testing builds an
    /// instance for every case, and the parameterized tests have dozens.
    private static let loaded = Result { try Loaded() }.mapError { LoadFailure(description: "\($0)") }

    let json: Data
    let entries: [CatalogEntry]
    let exercises: [Exercise]

    init() throws {
        let catalog = try Self.loaded.get()
        (json, entries, exercises) = (catalog.json, catalog.entries, catalog.exercises)
    }

    @Test("Criterion 1: seed() returns every entry, at least 200, as catalog exercises; the file is at most 200 KB")
    func seed_decodesAllEntries() {
        #expect(exercises.count >= 200)
        #expect(exercises.map(\.id) == entries.map(\.id))
        #expect(exercises.allSatisfy { !$0.isCustom })
        #expect(json.count <= 200_000, "exercises.json is \(json.count) bytes")
    }

    @Test(
        "Criterion 2: each spec §6.2 entry exists by name and equipment with the policy's conservative loads",
        arguments: prototypeEntries
    )
    func prototypeEntries_usePolicyLoads(_ expected: PrototypeEntry) throws {
        let exercise = try #require(exercises.first { $0.name == expected.name })
        #expect(exercise.id.rawValue.uuidString == expected.id, "ids never change")
        #expect(exercise.equipment == expected.equipment)
        #expect(exercise.defaultStartLoad[.lb] == .pounds(expected.pounds))
        #expect(exercise.defaultStartLoad[.kg] == .kilograms(expected.kilograms))
    }

    @Test("Criterion 3: every exercise has two or more alternatives; each exists, shares its pattern and is not itself")
    func alternatives_resolveToSamePattern() {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        for exercise in exercises {
            #expect(exercise.curatedAlternatives.count >= 2, "\(exercise.name)")
            #expect(Set(exercise.curatedAlternatives).count == exercise.curatedAlternatives.count, "\(exercise.name)")
            for id in exercise.curatedAlternatives {
                #expect(id != exercise.id, "\(exercise.name) lists itself")
                #expect(byID[id]?.pattern == exercise.pattern, "\(exercise.name) → \(byID[id]?.name ?? "missing")")
            }
        }
    }

    @Test("An isolation exercise's alternatives train the same primary muscle")
    func isolationAlternatives_trainTheSamePrimaryMuscle() {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        for exercise in exercises where exercise.pattern == .isolation {
            for alternative in exercise.curatedAlternatives.compactMap({ byID[$0] }) {
                #expect(alternative.primaryMuscle == exercise.primaryMuscle, "\(exercise.name) → \(alternative.name)")
            }
        }
    }

    @Test("Criterion 4: no two names or aliases are equal ignoring case")
    func namesAndAliases_haveNoDuplicates() {
        let names = entries.flatMap { [$0.name] + $0.aliases }.map { $0.lowercased() }
        let repeated = Dictionary(grouping: names, by: \.self).filter { $0.value.count > 1 }.keys.sorted()
        #expect(repeated.isEmpty, "\(repeated)")
        #expect(names.count > entries.count, "aliases are present")
    }

    @Test(
        "Criterion 5: each muscle group is the primary muscle of at least 10 exercises (core: 8)",
        arguments: MuscleGroup.allCases
    )
    func muscleCoverage_meetsMinimum(_ muscle: MuscleGroup) {
        let count = exercises.count { $0.primaryMuscle == muscle }
        #expect(count >= (muscle == .core ? 8 : 10), "\(muscle): \(count)")
    }

    @Test("Criterion 6: each equipment type has its minimum number of exercises", arguments: Equipment.allCases)
    func equipmentCoverage_meetsMinimum(_ equipment: Equipment) {
        let minimum = switch equipment {
        case .barbell: 30
        case .dumbbell: 40
        case .cable, .machine, .bodyweight: 25
        case .kettlebell: 10
        case .band: 8
        }
        let count = exercises.count { $0.equipment == equipment }
        #expect(count >= minimum, "\(equipment): \(count)")
    }

    @Test("Start loads are non-negative multiples of the equipment's default step in both units")
    func startLoads_areMultiplesOfStep() {
        for exercise in exercises {
            for units in Units.allCases {
                let load = exercise.startLoad(in: units)
                #expect(exercise.defaultStartLoad[units] != nil, "\(exercise.name) has no \(units) load")
                #expect(load >= .zero, "\(exercise.name)")
                #expect(load.rounded(toStep: exercise.equipment.defaultStep(in: units)) == load, "\(exercise.name)")
            }
        }
    }

    @Test("Every start load follows the conservative policy for its equipment and movement class (decision #21)")
    func startLoads_followThePolicy() throws {
        for exercise in exercises {
            let expected = try #require(StartLoadPolicy.startLoad(for: exercise), "no policy cell: \(exercise.name)")
            #expect(exercise.defaultStartLoad[.lb] == .pounds(expected.lb), "\(exercise.name)")
            #expect(exercise.defaultStartLoad[.kg] == .kilograms(expected.kg), "\(exercise.name)")
        }
        let names = Set(exercises.map(\.name))
        let named = StartLoadPolicy.floorPulls.union(StartLoadPolicy.landmine).union(StartLoadPolicy.small)
            .union(StartLoadPolicy.kettlebellUpper).union(StartLoadPolicy.straightBarIsolation)
            .union(StartLoadPolicy.specialtyBars.keys)
        #expect(named.subtracting(names).isEmpty, "the policy names missing exercises: \(named.subtracting(names))")
    }

    @Test("Short names fit the Program builder's day chips (spec §3.2): upper case, 1–14 characters, unique")
    func shortNames_fitTheDayChips() {
        for exercise in exercises {
            #expect(exercise.shortName == exercise.shortName.uppercased(), "\(exercise.shortName)")
            #expect((1 ... 14).contains(exercise.shortName.count), "\(exercise.shortName)")
        }
        #expect(Set(exercises.map(\.shortName)).count == exercises.count)
    }

    @Test("Ids are canonical upper-case UUIDv4 strings in the file, and unique")
    func ids_areStableUUIDs() throws {
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let rawEntries = try #require(object?["exercises"] as? [[String: Any]])
        let ids = rawEntries.compactMap { $0["id"] as? String }
        let uuidV4 = /[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}/ // as uuidgen prints it
        #expect(ids.count == entries.count)
        for id in ids {
            #expect(id.wholeMatch(of: uuidV4) != nil, "\(id)")
        }
        #expect(Set(ids).count == ids.count)
    }

    @Test("Criterion 7: catalog.version.sha pins this file's SHA-256 to ExerciseCatalog.version")
    func versionSha_matchesFile() throws {
        let history = try versionHistory()
        let digest = SHA256.hash(data: json).map { String(format: "%02x", $0) }.joined()
        let latest = try #require(history.last, "catalog.version.sha has no version lines")
        // Versions rise, gaps allowed, as scripts/check-catalog-version.sh allows them (review S1).
        let versions = history.map(\.version)
        #expect(versions[0] >= 1 && zip(versions, versions.dropFirst()).allSatisfy { $0 < $1 }, "\(versions)")
        #expect(Set(history.map(\.sha)).count == history.count, "each version has its own content")
        #expect(latest.version == ExerciseCatalog.version, "the last line is the current version")
        #expect(
            latest.sha == digest,
            """
            exercises.json changed. If this branch has not raised ExerciseCatalog.version yet, raise it \
            to \(ExerciseCatalog.version + 1) and append "\(ExerciseCatalog.version + 1) \(digest)" to \
            catalog.version.sha; if it has, make its last line "\(ExerciseCatalog.version) \(digest)"
            """
        )
    }

    /// The `<version> <sha256>` lines of `catalog.version.sha`; `#` and blank lines are skipped, and
    /// any other malformed line fails the test (never traps).
    private func versionHistory() throws -> [(version: Int, sha: String)] {
        let data = try ExerciseCatalog.resource("catalog.version", withExtension: "sha")
        let text = try #require(String(bytes: data, encoding: .utf8))
        let lines = text.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.allSatisfy(\.isWhitespace) }
        return try lines.map { line in
            let match = try #require(line.wholeMatch(of: /([0-9]{1,9}) ([0-9a-f]{64})/), "bad line: \(line)")
            return try (#require(Int(match.output.1)), String(match.output.2))
        }
    }
}

/// The bundled file, its entries and `seed()`'s result.
private struct Loaded {
    let json: Data
    let entries: [CatalogEntry]
    let exercises: [Exercise]

    init() throws {
        json = try ExerciseCatalog.resource("exercises", withExtension: "json")
        entries = try ExerciseCatalog.entries(from: json)
        exercises = try ExerciseCatalog.seed()
    }
}

/// Why the bundled catalog could not be read, kept as text so the cached result stays `Sendable`.
private struct LoadFailure: Error {
    let description: String
}

/// A spec §6.2 entry with the start load the policy gives it (criterion 2 as amended by Pete,
/// 2026-09-30), read off the table by hand; `id` pins the entry's identity: ids are stored in lifters'
/// databases and must never change.
struct PrototypeEntry: Sendable, CustomTestStringConvertible {
    let name: String
    let equipment: Equipment
    let pounds: Decimal
    let kilograms: Decimal
    let id: String

    init(_ name: String, _ equipment: Equipment, _ pounds: Decimal, _ kilograms: Decimal, _ id: String) {
        self.name = name
        self.equipment = equipment
        self.pounds = pounds
        self.kilograms = kilograms
        self.id = id
    }

    var testDescription: String {
        name
    }
}

private let prototypeEntries: [PrototypeEntry] = [
    // name, equipment, lb, kg, id
    PrototypeEntry("Barbell Bench Press", .barbell, 45, 20, "270DE1C9-481F-4904-BE85-070381E296C0"),
    PrototypeEntry("Incline DB Press", .dumbbell, 15, 7.5, "34ABACC5-2E75-4EE1-9F67-DC9E925E6D37"),
    PrototypeEntry("Low-to-High Cable Fly", .cable, 20, 10, "0212B3A2-68ED-4183-B183-0850BEDB68F7"),
    PrototypeEntry("Weighted Dip", .bodyweight, 10, 5, "2BF340CA-A558-40D2-81D9-5BF2DF1EB60F"),
    PrototypeEntry("Barbell Row", .barbell, 45, 20, "90383748-7413-4398-99FA-6EB6E5F2969A"),
    PrototypeEntry("Chest-Supported Row", .machine, 40, 20, "A9ED72CF-D506-430B-A12F-501D15B18E44"),
    PrototypeEntry("Lat Pulldown", .cable, 30, 15, "5F043F91-CD6E-4E9B-B12C-5B33ECB9B049"),
    PrototypeEntry("Weighted Pull-Up", .bodyweight, 10, 5, "0865DC39-D829-4DFD-8E6D-6EE9302EB777"),
    PrototypeEntry("Overhead Press", .barbell, 45, 20, "DA5CE9D0-60A1-41BC-B634-A3516D27B544"),
    PrototypeEntry("Cable Lateral Raise", .cable, 10, 5, "18EC9F77-0DD1-4037-B7B8-8214744142AC"),
    PrototypeEntry("Rear Delt Fly", .machine, 10, 5, "0A281016-6A02-459C-A7CC-23F7F41A6A0E"),
    PrototypeEntry("Back Squat", .barbell, 45, 20, "73EE7555-DC9F-4D98-A87F-08C8817876F1"),
    PrototypeEntry("Front Squat", .barbell, 45, 20, "223208C8-E7BB-4514-A335-6FCC43A62E18"),
    PrototypeEntry("Romanian Deadlift", .barbell, 45, 20, "C6C70E2B-BB44-4A53-98DD-D4861B70E8D7"),
    PrototypeEntry("Deadlift", .barbell, 95, 40, "F5CB98F6-7533-4BE9-85FA-8013FF01B1C6"),
    PrototypeEntry("Leg Press", .machine, 40, 20, "80834235-1B66-4070-8F6A-5A87794792FC"),
    PrototypeEntry("Seated Leg Curl", .machine, 20, 10, "60C1A421-610C-4FC2-8416-0DAC57FE29BC"),
    PrototypeEntry("Standing Calf Raise", .machine, 20, 10, "87EF983A-8D62-488E-9AAE-7BECDBF6F5EF"),
    PrototypeEntry("Barbell Curl", .barbell, 25, 10, "6C2540C1-DAF5-4ECB-B66E-C9EA231EB0CE"),
    PrototypeEntry("Incline DB Curl", .dumbbell, 10, 5, "2C3613AF-0D6B-4B2C-8AB5-21C5D3634B82"),
    PrototypeEntry("Cable Triceps Pushdown", .cable, 20, 10, "B91DC81A-203D-4FD8-90E7-5A29623FCB17"),
    PrototypeEntry("Overhead Cable Extension", .cable, 20, 10, "5006D164-29B4-4EC3-97AD-A6DD5E139846")
]
