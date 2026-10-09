@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 adversarial round 1, criteria 10, 12 and 13: the foot's plural forms in the locales a lifter may
/// have, the library's sources (no text outside the copy file, nothing ambient), and the catalog's keys.
@Suite("Adversarial F11 S8 · the exercise library's words", .tags(.feature))
nonisolated struct ExercisePickerWordsAdversarialTests {
    /// Locales that write numbers with Latin digits and whose plural rules are not English's: no singular
    /// (ja, zh, ko), one for 0 and 1 (fr), one/few/many (ru, pl), a dual (he, ar with Latin digits).
    static let latinDigitLocales = [
        "en_US", "en_GB", "de_DE", "fr_FR", "ja_JP", "zh_CN", "ko_KR", "ru_RU", "pl_PL", "he_IL", "ar_AE"
    ]

    /// FINDING F11-S8-1 (fails for ja_JP, zh_CN, ko_KR and ru_RU): the catalog is English only, and the
    /// plural form is chosen by the injected locale's rules, so the English text takes another language's
    /// form: "Add 1 exercises" where the language has no singular, "Add 21 exercise" in Russian.
    @Test(
        "The foot reads 'Add 1 exercise' for one pick and 'exercises' for more, in English, whatever the locale",
        arguments: latinDigitLocales
    )
    func foot_pluralForms_areEnglishInEveryLocale(identifier: String) {
        let locale = Locale(identifier: identifier)
        #expect(ProgramCopy.addExercises(1, locale: locale) == "Add 1 exercise")
        for count in [2, 3, 4, 5, 11, 21, 22, 101] {
            #expect(ProgramCopy.addExercises(count, locale: locale) == "Add \(count) exercises")
        }
    }

    @Test("The foot's count is written as the locale writes numbers, and one is still the singular")
    func foot_count_isWrittenInTheLocale() {
        #expect(ProgramCopy.addExercises(1, locale: Locale(identifier: "ar_EG")) == "Add ١ exercise")
        #expect(ProgramCopy.addExercises(3, locale: Locale(identifier: "ar_EG")) == "Add ٣ exercises")
        #expect(ProgramCopy.addExercises(1, locale: Locale(identifier: "hi_IN@numbers=deva")) == "Add १ exercise")
        #expect(ProgramCopy.addExercises(12345, locale: Locale(identifier: "fr_FR")) == "Add 12\u{202F}345 exercises")
    }

    @Test("A chip's spoken label keeps its two parts as they are, also when they look like format text")
    func spokenChip_keepsItsParts() {
        let locale = Locale(identifier: "en_US")
        #expect(ProgramCopy.spokenChip(row: "Muscle", title: "All", locale: locale) == "Muscle: All")
        #expect(ProgramCopy.spokenChip(row: "%@", title: "100% %lld", locale: locale) == "%@: 100% %lld")
    }

    @Test("A name of any script, or one that looks like format text, is the row's name and spoken label as stored")
    func names_areDataAsStored() {
        for name in AdvPicker.names {
            let exercise = Exercise(
                id: ExerciseID(Fixtures.uuid(61000)), name: name, shortName: "", equipment: .band,
                primaryMuscle: .core, pattern: .core, defaultStartLoad: [:], isCustom: true
            )
            let input = ExercisePickerInput(
                exercises: [exercise], dayExercises: [exercise.id], query: "", muscle: nil, equipment: nil,
                picks: [exercise.id], locale: Locale(identifier: "he_IL")
            )
            let row = ExercisePickerPresentation.make(input).rows.first
            #expect(row?.name == name && row?.spokenLabel == name)
            #expect(row?.line == "Band · Core · already in this day")
            #expect(row?.pickMark == "1")
        }
    }

    // MARK: - The sources

    static func folder(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(path)
    }

    static func sources() throws -> [(name: String, code: [String])] {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder("Sources/FeatureProgram/Picker"), includingPropertiesForKeys: nil
        )
        return try files.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }.map { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
            }
            return (file.lastPathComponent, code)
        }
    }

    @Test("The library's sources read no clock, calendar, locale, zone, random number or stored default")
    func sources_readNothingAmbient() throws {
        let banned = [
            "Date()", "Date.now", ".now", "Calendar.current", "Locale.current", "TimeZone.current",
            "autoupdatingCurrent", "UUID()", ".random", "ProcessInfo", "UserDefaults", "NSLocale", "Calendar(",
            "preferredLanguages", "DispatchTime", "ContinuousClock", "SystemRandom", ".formatted()", "Formatter("
        ]
        var found: [String] = []
        let files = try Self.sources()
        for file in files {
            for (place, line) in file.code.enumerated() {
                found += banned.filter { line.contains($0) }.map { "\(file.name):\(place + 1) \($0)" }
            }
        }
        #expect(files.map(\.name) == [
            "ExercisePickerAction.swift", "ExercisePickerInput.swift", "ExercisePickerModel.swift",
            "ExercisePickerPresentation.swift", "ProgramCopy+Picker.swift"
        ])
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("Outside the copy file the library's sources hold no text and look nothing up")
    func sources_holdNoCopyOutsideTheCopyFile() throws {
        var found: [String] = []
        for file in try Self.sources() where !file.name.hasPrefix("ProgramCopy") {
            for (place, line) in file.code.enumerated() {
                let pieces = line.split(separator: "\"", omittingEmptySubsequences: false)
                let literals = pieces.enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
                found += literals.filter { !$0.isEmpty }.map { "\(file.name):\(place + 1) \"\($0)\"" }
                let lookups = ["String(localized", "LocalizedStringKey", "NSLocalizedString", "bundle:"]
                found += lookups.filter { line.contains($0) }.map { "\(file.name):\(place + 1) \($0)" }
            }
        }
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    /// The key the compiler takes from a lookup's literal: a counted value is `%lld`, a text `%@`.
    static func key(ofLiteral literal: String) -> String {
        literal
            .replacingOccurrences(of: #"\(count)"#, with: "%lld")
            .replacingOccurrences(of: #"\\\([a-z]+\)"#, with: "%@", options: .regularExpression)
    }

    @Test("Every lookup of the library's copy file names the module's bundle and a key of the catalog")
    func copyFile_everyLookup_isAKeyOfTheCatalog() throws {
        let file = try #require(Self.sources().first { $0.name == "ProgramCopy+Picker.swift" })
        let catalog = try Data(contentsOf: Self.folder("Sources/FeatureProgram/Resources/Localizable.xcstrings"))
        let parsed = try #require(JSONSerialization.jsonObject(with: catalog) as? [String: Any])
        let keys = try Set(#require(parsed["strings"] as? [String: Any]).keys)
        var missing: [String] = []
        var lookups = 0
        for statement in file.code.joined(separator: "\n").components(separatedBy: "localized: \"").dropFirst() {
            lookups += 1
            let literal = String(statement.prefix { $0 != "\"" })
            let call = String(statement.prefix { $0 != "}" })
            if !keys.contains(Self.key(ofLiteral: literal)) {
                missing.append("no key «\(Self.key(ofLiteral: literal))»")
            }
            if !call.contains("bundle: .module") {
                missing.append("no bundle: \(literal)")
            }
            if literal.contains("\\(") != call.contains("locale: locale") {
                missing.append("value and locale disagree: \(literal)")
            }
        }
        #expect(lookups == 24, "the scan read \(lookups) lookups")
        #expect(missing.isEmpty, "\(missing.prefix(5))")
    }
}
