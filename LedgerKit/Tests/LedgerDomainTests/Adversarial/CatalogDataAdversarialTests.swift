import Foundation
@testable import LedgerDomain
import Testing

/// F03 criteria 1, 3–6 and the brief's JSON rules, attacked on the bundled `exercises.json`.
@Suite("Exercise catalog data (adversarial)", .tags(.domain))
struct CatalogDataAdversarialTests {}

// MARK: - Criterion 1 and ids

extension CatalogDataAdversarialTests {
    @Test("seed() returns ≥ 200 exercises, one per JSON entry, in file order (criterion 1: nothing skipped).")
    func seed_returnsEveryEntryInOrder() throws {
        let exercises = try CatalogUnderTest.exercises()
        let raw = try CatalogUnderTest.rawEntries()
        #expect(exercises.count >= 200)
        #expect(exercises.count == raw.count)
        #expect(exercises.map(\.id.rawValue.uuidString) == raw.map { ($0["id"] as? String ?? "").uppercased() })
        #expect(exercises.allSatisfy { !$0.isCustom })
        // No exact count: the Library's "Search %lld exercises" is a live count (F12 brief), so the
        // prototype's 214 is not a promise (F03 review N6; fix round 2 added entries).
    }

    @Test("Every id is written as an upper-case, canonical, random (v4) UUID, and ids are unique.")
    func ids_areCanonicalRandomUniqueUUIDs() throws {
        let raw = try CatalogUnderTest.rawEntries()
        let ids = raw.compactMap { $0["id"] as? String }
        #expect(ids.count == raw.count)
        let canonicalV4 = /[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}/
        for id in ids {
            #expect(id.wholeMatch(of: canonicalV4) != nil, "\(id) is not an upper-case canonical v4 UUID")
            #expect(UUID(uuidString: id)?.uuidString == id)
        }
        #expect(Set(ids.map { $0.uppercased() }).count == ids.count)
        let alternatives = raw.flatMap { $0["alternatives"] as? [String] ?? [] }
        #expect(alternatives.allSatisfy { $0.wholeMatch(of: canonicalV4) != nil })
    }

    @Test("Every entry has exactly the brief's keys (loadKind only when bodyweight) and nothing else.")
    func entries_haveExactlyTheSchemaKeys() throws {
        let required: Set = [
            "id", "name", "shortName", "equipment", "primaryMuscle", "secondaryMuscles", "pattern",
            "startLoad", "alternatives", "aliases"
        ]
        for entry in try CatalogUnderTest.rawEntries() {
            let keys = Set(entry.keys)
            #expect(keys == required || keys == required.union(["loadKind"]), "\(entry["name"] ?? "?"): \(keys)")
            if let kind = entry["loadKind"] {
                #expect(kind as? String == "bodyweight")
            }
            let load = entry["startLoad"] as? [String: Any]
            #expect(load.map { Set($0.keys) } == ["lb", "kg"])
        }
    }

    @Test("No entry in the file writes a key twice (the decoder would silently keep one value: finding 1).")
    func entries_noKeyWrittenTwice() throws {
        let entries = try CatalogScan.entryKeys(in: CatalogUnderTest.text())
        #expect(try entries.count == CatalogUnderTest.rawEntries().count)
        for keys in entries {
            #expect(keys.count >= 10 && Set(keys).count == keys.count, "\(keys)")
        }
    }

    /// Finding 1, retargeted in fix round 2: the catalog is static bundled data, so this scan of the
    /// one file the app loads is the guard, not the loader (`JSONDecoder` cannot report a repeat).
    @Test("The file scan catches a key written twice in an entry, which the decoder alone would load silently.")
    func duplicateKey_caughtByTheFileScan() throws {
        let text = try CatalogUnderTest.text()
        let line = "      \"shortName\": \"BENCH\",\n"
        #expect(text.components(separatedBy: line).count == 2, "the fixture edits exactly one entry")
        let doubled = text.replacingOccurrences(of: line, with: line + "      \"shortName\": \"BENCH PRESS\",\n")
        #expect(CatalogScan.repeatedKeys(in: doubled) == [["shortName"]])
        #expect(try CatalogScan.repeatedKeys(in: CatalogUnderTest.text()).isEmpty)
    }
}

// MARK: - Criterion 4: names, aliases, short names

extension CatalogDataAdversarialTests {
    @Test("Names and aliases never repeat across entries, ignoring case, spacing, punctuation and width.")
    func namesAndAliases_uniqueUnderStrictFolding() throws {
        var owner: [String: (ExerciseID, String)] = [:]
        for entry in try CatalogUnderTest.entriesDecoded() {
            for text in [entry.name] + entry.aliases {
                let key = CatalogText.key(text)
                #expect(!key.isEmpty)
                if let (id, first) = owner[key], id != entry.id {
                    Issue.record("\"\(text)\" (\(entry.name)) duplicates \"\(first)\"")
                }
                owner[key] = owner[key] ?? (entry.id, text)
            }
        }
    }

    @Test("Names, aliases and short names are plain ASCII text: no lookalike letters, no stray whitespace.")
    func text_isPlainASCII() throws {
        let nonASCII = try CatalogUnderTest.text().unicodeScalars.filter { !$0.isASCII }
        #expect(nonASCII.isEmpty, "\(nonASCII.map { $0.escaped(asASCII: true) })")
        for entry in try CatalogUnderTest.entriesDecoded() {
            for value in [entry.name, entry.shortName] + entry.aliases {
                #expect(CatalogText.isPlain(value), "\"\(value)\" (\(entry.name))")
            }
        }
    }

    @Test("Short names are unique, upper case and fit the 14-character label the JSON's contributing note sets.")
    func shortNames_uniqueUpperCaseShort() throws {
        let exercises = try CatalogUnderTest.exercises()
        let shorts = exercises.map(\.shortName)
        #expect(Set(shorts.map(CatalogText.key)).count == shorts.count)
        for exercise in exercises {
            #expect(exercise.shortName == exercise.shortName.uppercased(), "\(exercise.shortName)")
            #expect((1 ... 14).contains(exercise.shortName.count), "\(exercise.shortName)")
        }
    }
}

// MARK: - Criteria 5 and 6, enums

extension CatalogDataAdversarialTests {
    @Test(
        "Each muscle is some exercise's primary ≥ 10 times (core ≥ 8) (criterion 5).",
        arguments: MuscleGroup.allCases
    )
    func muscleCoverage(muscle: MuscleGroup) throws {
        let count = try CatalogUnderTest.exercises().count { $0.primaryMuscle == muscle }
        #expect(count >= (muscle == .core ? 8 : 10), "\(muscle): \(count)")
    }

    @Test("Equipment counts meet criterion 6.", arguments: [
        (Equipment.barbell, 30), (.dumbbell, 40), (.cable, 25), (.machine, 25), (.bodyweight, 25),
        (.kettlebell, 10), (.band, 8)
    ])
    func equipmentCoverage(equipment: Equipment, minimum: Int) throws {
        let count = try CatalogUnderTest.exercises().count { $0.equipment == equipment }
        #expect(count >= minimum, "\(equipment): \(count)")
    }

    @Test("Every pattern has ≥ 3 members (so ≥ 2 alternatives exist) and every enum case is spelled as F02 has it.")
    func enums_patternsPopulatedAndRawValuesValid() throws {
        let exercises = try CatalogUnderTest.exercises()
        for pattern in MovementPattern.allCases {
            #expect(exercises.count { $0.pattern == pattern } >= 3, "\(pattern)")
        }
        for entry in try CatalogUnderTest.rawEntries() {
            #expect(Equipment(rawValue: entry["equipment"] as? String ?? "") != nil)
            #expect(MuscleGroup(rawValue: entry["primaryMuscle"] as? String ?? "") != nil)
            #expect(MovementPattern(rawValue: entry["pattern"] as? String ?? "") != nil)
            let secondary = entry["secondaryMuscles"] as? [String] ?? ["?"]
            #expect(secondary.allSatisfy { MuscleGroup(rawValue: $0) != nil })
        }
    }

    @Test("Secondary muscles never repeat the primary or each other.")
    func secondaryMuscles_distinct() throws {
        for exercise in try CatalogUnderTest.exercises() {
            let all = [exercise.primaryMuscle] + exercise.secondaryMuscles
            #expect(Set(all).count == all.count, "\(exercise.name)")
        }
    }
}

// MARK: - Criterion 3: alternatives

extension CatalogDataAdversarialTests {
    @Test("Alternatives: ≥ 2, distinct, never self, all resolve, same pattern (criterion 3).")
    func alternatives_resolveSamePattern() throws {
        let exercises = try CatalogUnderTest.exercises()
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        for exercise in exercises {
            let alternatives = exercise.curatedAlternatives
            #expect(alternatives.count >= 2, "\(exercise.name)")
            #expect(Set(alternatives).count == alternatives.count, "\(exercise.name)")
            #expect(!alternatives.contains(exercise.id), "\(exercise.name)")
            for id in alternatives {
                let alternative = try #require(byID[id], "\(exercise.name) → \(id)")
                #expect(alternative.pattern == exercise.pattern, "\(exercise.name) → \(alternative.name)")
            }
        }
    }

    @Test("An isolation exercise's alternatives train the same primary muscle (ExerciseCatalog pattern rules).")
    func isolationAlternatives_samePrimaryMuscle() throws {
        let exercises = try CatalogUnderTest.exercises()
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        for exercise in exercises where exercise.pattern == .isolation {
            for id in exercise.curatedAlternatives {
                let alternative = try #require(byID[id])
                #expect(alternative.primaryMuscle == exercise.primaryMuscle, "\(exercise.name) → \(alternative.name)")
            }
        }
    }
}

extension CatalogUnderTest {
    /// The entries as the loader decodes them (aliases are not on `Exercise`).
    static func entriesDecoded() throws -> [CatalogEntry] {
        try ExerciseCatalog.entries(from: data())
    }
}
