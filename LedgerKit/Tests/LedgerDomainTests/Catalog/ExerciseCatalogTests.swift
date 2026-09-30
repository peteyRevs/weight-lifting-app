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
    let json: Data
    let entries: [CatalogEntry]
    let exercises: [Exercise]

    init() throws {
        json = try ExerciseCatalog.resource("exercises", withExtension: "json")
        entries = try ExerciseCatalog.entries(from: json)
        exercises = try ExerciseCatalog.seed()
    }

    @Test("Criterion 1: seed() returns every entry, at least 200, as catalog exercises; the file is at most 200 KB")
    func seed_decodesAllEntries() {
        #expect(exercises.count >= 200)
        #expect(exercises.map(\.id) == entries.map(\.id))
        #expect(exercises.allSatisfy { !$0.isCustom })
        #expect(json.count <= 200_000, "exercises.json is \(json.count) bytes")
    }

    @Test(
        "Criterion 2: each spec §6.2 entry exists by name with its W0 in lb, and kg is lb rounded to the kg step",
        arguments: prototypeEntries
    )
    func prototypeEntries_matchSpecW0(_ expected: PrototypeEntry) throws {
        let exercise = try #require(exercises.first { $0.name == expected.name })
        #expect(exercise.id.rawValue.uuidString == expected.id, "ids never change")
        #expect(exercise.defaultStartLoad[.lb] == .pounds(expected.pounds))
        #expect(exercise.defaultStartLoad[.kg] == .kilograms(expected.kilograms))
        let converted = Weight.pounds(expected.pounds).rounded(toStep: exercise.equipment.defaultStep(in: .kg))
        #expect(exercise.defaultStartLoad[.kg] == converted)
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

    @Test("Every kg start load is the lb one converted and rounded to the kg step; only bodyweight starts at zero")
    func kilogramStartLoads_areConvertedPounds() {
        for exercise in exercises {
            let pounds = exercise.startLoad(in: .lb)
            let kgStep = exercise.equipment.defaultStep(in: .kg)
            #expect(exercise.startLoad(in: .kg) == pounds.rounded(toStep: kgStep), "\(exercise.name)")
            #expect(pounds > .zero || exercise.equipment == .bodyweight, "\(exercise.name) starts at zero")
        }
    }

    @Test("Short names fit the watch: upper case, 1–14 characters, unique")
    func shortNames_fitTheWatch() {
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
        #expect(history.map(\.version) == Array(1 ... history.count), "versions are 1, 2, 3 … in order")
        #expect(Set(history.map(\.sha)).count == history.count, "each version has its own content")
        let latest = try #require(history.last)
        #expect(latest.version == ExerciseCatalog.version, "the last line is the current version")
        #expect(
            latest.sha == digest,
            """
            exercises.json changed: bump ExerciseCatalog.version to \(ExerciseCatalog.version + 1) and append \
            "\(ExerciseCatalog.version + 1) \(digest)" to catalog.version.sha
            """
        )
    }

    /// The `<version> <sha256>` lines of `catalog.version.sha`; `#` lines are comments.
    private func versionHistory() throws -> [(version: Int, sha: String)] {
        let data = try ExerciseCatalog.resource("catalog.version", withExtension: "sha")
        let text = try #require(String(bytes: data, encoding: .utf8))
        return try text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { line in
            let fields = line.split(separator: " ")
            let version = try #require(fields.count == 2 ? Int(fields[0]) : nil, "bad line: \(line)")
            return (version, String(fields[1]))
        }
    }
}

/// A spec §6.2 row. `kilograms` is worked by hand (lb × 0.45359237, nearest kg step), and `id` pins
/// the entry's identity: ids are stored in lifters' databases and must never change.
struct PrototypeEntry: Sendable, CustomTestStringConvertible {
    let name: String
    let pounds: Decimal
    let kilograms: Decimal
    let id: String

    init(_ name: String, pounds: Decimal, kilograms: Decimal, id: String) {
        self.name = name
        self.pounds = pounds
        self.kilograms = kilograms
        self.id = id
    }

    var testDescription: String {
        name
    }
}

private let prototypeEntries: [PrototypeEntry] = [
    PrototypeEntry("Barbell Bench Press", pounds: 180, kilograms: 82.5, id: "270DE1C9-481F-4904-BE85-070381E296C0"),
    PrototypeEntry("Incline DB Press", pounds: 50, kilograms: 22.5, id: "34ABACC5-2E75-4EE1-9F67-DC9E925E6D37"),
    PrototypeEntry("Low-to-High Cable Fly", pounds: 25, kilograms: 11.25, id: "0212B3A2-68ED-4183-B183-0850BEDB68F7"),
    PrototypeEntry("Weighted Dip", pounds: 45, kilograms: 20, id: "2BF340CA-A558-40D2-81D9-5BF2DF1EB60F"),
    PrototypeEntry("Barbell Row", pounds: 155, kilograms: 70, id: "90383748-7413-4398-99FA-6EB6E5F2969A"),
    PrototypeEntry("Chest-Supported Row", pounds: 65, kilograms: 30, id: "A9ED72CF-D506-430B-A12F-501D15B18E44"),
    PrototypeEntry("Lat Pulldown", pounds: 100, kilograms: 45, id: "5F043F91-CD6E-4E9B-B12C-5B33ECB9B049"),
    PrototypeEntry("Weighted Pull-Up", pounds: 35, kilograms: 16.25, id: "0865DC39-D829-4DFD-8E6D-6EE9302EB777"),
    PrototypeEntry("Overhead Press", pounds: 115, kilograms: 52.5, id: "DA5CE9D0-60A1-41BC-B634-A3516D27B544"),
    PrototypeEntry("Cable Lateral Raise", pounds: 12.5, kilograms: 6.25, id: "18EC9F77-0DD1-4037-B7B8-8214744142AC"),
    PrototypeEntry("Rear Delt Fly", pounds: 50, kilograms: 22.5, id: "0A281016-6A02-459C-A7CC-23F7F41A6A0E"),
    PrototypeEntry("Back Squat", pounds: 250, kilograms: 112.5, id: "73EE7555-DC9F-4D98-A87F-08C8817876F1"),
    PrototypeEntry("Front Squat", pounds: 185, kilograms: 85, id: "223208C8-E7BB-4514-A335-6FCC43A62E18"),
    PrototypeEntry("Romanian Deadlift", pounds: 205, kilograms: 92.5, id: "C6C70E2B-BB44-4A53-98DD-D4861B70E8D7"),
    PrototypeEntry("Deadlift", pounds: 315, kilograms: 142.5, id: "F5CB98F6-7533-4BE9-85FA-8013FF01B1C6"),
    PrototypeEntry("Leg Press", pounds: 320, kilograms: 145, id: "80834235-1B66-4070-8F6A-5A87794792FC"),
    PrototypeEntry("Seated Leg Curl", pounds: 90, kilograms: 41.25, id: "60C1A421-610C-4FC2-8416-0DAC57FE29BC"),
    PrototypeEntry("Standing Calf Raise", pounds: 160, kilograms: 72.5, id: "87EF983A-8D62-488E-9AAE-7BECDBF6F5EF"),
    PrototypeEntry("Barbell Curl", pounds: 75, kilograms: 35, id: "6C2540C1-DAF5-4ECB-B66E-C9EA231EB0CE"),
    PrototypeEntry("Incline DB Curl", pounds: 30, kilograms: 13.75, id: "2C3613AF-0D6B-4B2C-8AB5-21C5D3634B82"),
    PrototypeEntry("Cable Triceps Pushdown", pounds: 60, kilograms: 27.5, id: "B91DC81A-203D-4FD8-90E7-5A29623FCB17"),
    PrototypeEntry("Overhead Cable Extension", pounds: 45, kilograms: 20, id: "5006D164-29B4-4EC3-97AD-A6DD5E139846")
]
