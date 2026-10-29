import Foundation
import LedgerTestSupport
import Testing

/// The one suite that holds every module of the package to standards §7's localization rules. A feature adds a
/// catalog and a copy file and nothing here: a module is audited unless one of the two tables below names it.
///
/// - `CopyAudit` reads each audited module's sources: no copy outside its copy files, only the two lookup forms
///   inside them, a sound catalog.
/// - The bundle the build made resolves every key of every catalog.
/// - That each catalog's keys are the keys the compiler extracted is the gate's step
///   (`scripts/check-string-catalogs.sh`), not a test.
@Suite("Module copy")
nonisolated struct ModuleCopyTests {
    /// Modules that show a lifter nothing, by design, each with the reason. They are not audited: their string
    /// literals are data, SQL, keys and log lines.
    static let withoutCopyByDesign = [
        "LedgerDependencies": "dependency keys and stubs",
        "LedgerDomain": "models and rules; what it formats (weights, volumes, clock text) is shown as given",
        "LedgerFakes": "in-memory stores and fixtures for previews and tests, Debug builds only",
        "LedgerHealth": "the HealthKit adapter",
        "LedgerPersistence": "the schema, migrations and stores",
        "LedgerSnapshotTesting": "test-only snapshot helpers",
        "LedgerSync": "the transport between phone and watch",
        "LedgerTestSupport": "test-only contracts, builders and these checks"
    ]

    /// Modules that draw text and do not follow standards §7 yet. This table only shrinks: a module leaves it in
    /// the change that gives it a copy file and a catalog, and `notYetConverted_stillFailsTheAudit` fails for a
    /// module that could leave it and has not.
    ///
    /// The watch waits for F18. The gate's catalog step reads the iOS build, which compiles neither watch module,
    /// and this test bundle does not embed their resource bundles, so a catalog there would fail both. F18 gives
    /// `LedgerWatchAppKit` and `WatchFeatureWorkout` their catalogs (the second holds no copy yet, so it is
    /// audited today and not listed here).
    static let notYetConverted = [
        "LedgerDesign": "14 lookups in six files (VoiceOver words in WeekStrip and SetRow, the Debug menu, the "
            + "gallery's samples); the chore after F09 S1 converts it",
        "LedgerWatchAppKit": "the placeholder's title and the can't-open screen, as literals; converts with F18, "
            + "when the catalog step reads the watch build and a watch test target asks the watch bundles"
    ]

    /// What each audited module sets aside (`CopyAudit.Exemptions`; standards §7: the reviewer confirms each).
    /// A shared file in the sense of M1 convention 4: a feature lane adds only its own module's entry.
    static let exemptions: [String: CopyAudit.Exemptions] = [
        // The Debug menu's "Start sample workout" row and the seed program it starts.
        "FeatureWorkout": CopyAudit.Exemptions(debugOnly: ["WorkoutLauncher+Sample.swift"]),
        "LedgerAppKit": CopyAudit.Exemptions(
            // The UI-test launch argument (twice) and the temporary database's path: read by the launch, never drawn.
            literals: [
                "AppComposition.swift": ["-LEDGER_UITEST", "LedgerUITest-/ledger.sqlite"],
                // A UI test's own date (F09 S5): the two launch arguments, and what stops a launch whose
                // instant cannot be read. Read by the launch or by the test's author, never drawn.
                // "Z" is how an instant spells "no offset", which the argument's reader compares with.
                "UITestClock.swift": [
                    "-LEDGER_UITEST_NOW", "-LEDGER_UITEST", " needs an ISO 8601 instant such as 2026-09-17T12:00:00Z: ",
                    "Z"
                ],
                // A UI test's failing save (F10 S7a): the two launch arguments and what stops a launch whose
                // count cannot be read. Read by the launch or by the test's author, never drawn.
                "UITestSaveFailures.swift": [
                    "-LEDGER_UITEST_FAIL_FINISH",
                    "-LEDGER_UITEST",
                    " needs a count from 1 up: "
                ],
                // A UI test's program (F08, ruling R2): the two launch arguments, the one value, and what stops a
                // launch whose value cannot be read. Read by the launch or by the test's author, never drawn.
                "UITestProgram.swift": ["-LEDGER_UITEST_PROGRAM", "seed", "-LEDGER_UITEST", " takes one value, : "],
                // Settings' About line (F14 S1, N6): the four Info.plist keys it is read from, never drawn.
                "AppAbout.swift": [
                    "CFBundleDisplayName",
                    "CFBundleName",
                    "CFBundleShortVersionString",
                    "CFBundleVersion"
                ]
            ],
            // The Debug menu's Diagnostics sections.
            debugOnly: ["AppComposition+Diagnostics.swift"]
        )
    ]

    /// Every folder of `LedgerKit/Sources`. If the folder cannot be read this is empty, which
    /// `everyModule_isAuditedOrNamed` fails on; a parameterised test's arguments cannot throw.
    static let modules: [String] = (try? FileManager.default
        .contentsOfDirectory(at: PreviewScan.sourcesDirectory, includingPropertiesForKeys: nil)
        .filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()) ?? []

    static let audited = modules.filter { withoutCopyByDesign[$0] == nil && notYetConverted[$0] == nil }

    /// A catalog that is there and reads as one. One that does not read counts as none: its module is then
    /// audited as a module without a catalog, where its copy file is a finding, and the gate's step fails on it.
    static func hasCatalog(_ module: String) -> Bool {
        (try? StringCatalog(module: module)) != nil
    }

    /// F00 left each module one file, `<Module>.swift`, that holds the module's own name; no lifter sees it, and
    /// it goes when the module's first real file replaces it. Found, not listed, so that nothing here needs an
    /// edit on that day.
    static func placeholderName(of module: String) throws -> [String: [String]] {
        let file = "\(module).swift"
        let holdsTheName = try CopyAudit.sources(ofModule: module)[file]?.contains("static let name = \"\(module)\"")
        return holdsTheName == true ? [file: [module]] : [:]
    }

    static func audit(_ module: String) throws -> CopyAudit {
        var exempt = exemptions[module] ?? [:]
        try exempt.literals.merge(placeholderName(of: module)) { $0 + $1 }
        return try hasCatalog(module)
            ? CopyAudit(module: module, exempting: exempt)
            : CopyAudit(moduleWithoutCatalog: module, exempting: exempt)
    }

    @Test("Every module of the package is audited or named in one table, and the tables name only modules")
    func everyModule_isAuditedOrNamed() {
        let named = Set(Self.withoutCopyByDesign.keys).union(Self.notYetConverted.keys)
        #expect(Self.modules.count >= 20, "the package's sources were not found: \(Self.modules)")
        #expect(named.subtracting(Self.modules) == [], "a table names a module the package does not have")
        #expect(Set(Self.withoutCopyByDesign.keys).intersection(Self.notYetConverted.keys) == [])
        #expect(Set(Self.exemptions.keys).subtracting(Self.audited) == [], "an exemption for a module not audited")
        #expect(Self.audited.contains("LedgerAppKit") && Self.audited.contains("FeatureToday"))
    }

    @Test("An audited module holds no copy outside its copy files, and only lookups inside them", arguments: audited)
    func auditedModule_followsTheStandard(_ module: String) throws {
        #expect(try Self.audit(module).findings == [])
    }

    @Test(
        "A module not yet converted still fails the audit: when it passes, it leaves the table",
        arguments: notYetConverted.keys.sorted()
    )
    func notYetConverted_stillFailsTheAudit(_ module: String) throws {
        #expect(
            try !Self.audit(module).findings.isEmpty,
            "\(module) follows the standard now: take it out of the table"
        )
    }

    @Test("The bundle the build made resolves every key of a module's catalog", arguments: modules.filter(hasCatalog))
    func builtBundle_resolvesEveryKey(of module: String) throws {
        let catalog = try StringCatalog(module: module)
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: module), "no resource bundle for \(module)")
        #expect(!catalog.keys.isEmpty)
        #expect(catalog.unresolvedKeys(in: bundle) == [])
    }

    @Test("At least one module has a catalog, so the bundle check above checks something")
    func someModule_hasACatalog() {
        #expect(Self.modules.filter(Self.hasCatalog).contains("LedgerAppKit"))
    }

    @Test("A key the bundle's tables lack is reported: the bundle check can fail")
    func unresolvedKeys_reportsAKeyTheBundleLacks() throws {
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: "LedgerAppKit"))
        let catalog = try TestCatalog.plain("Today", "Not in the bundle", "today")
        #expect(catalog.unresolvedKeys(in: bundle) == ["Not in the bundle", "today"])
        #expect(try StringCatalog(module: "LedgerAppKit").unresolvedKeys(in: .main).count == 6, "nor in another bundle")
    }
}
