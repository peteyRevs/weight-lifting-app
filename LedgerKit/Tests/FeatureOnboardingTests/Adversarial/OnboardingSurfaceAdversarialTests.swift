import Foundation
import LedgerTestSupport
import Testing

/// F08 S2 adversarial round 1, criterion 11, by a scan of the module's sources (comments and string literals left
/// out, as `SwiftSource` reads them): only `OnboardingRoot` is public, and nothing reads the clock, the device's
/// calendar or locale, or makes an id or a task of its own. What these rules mean in behaviour is in the other
/// suites: the injected date, zone, locale and ids decide everything that is saved and shown.
@Suite("Adversarial F08 S2 · the module's surface and its rules")
struct OnboardingSurfaceAdversarialTests {
    /// One line of code of the module, without comments and with every string literal emptied.
    nonisolated struct Line: CustomStringConvertible, Sendable {
        let file: String
        let number: Int
        let code: String

        var description: String {
            "\(file):\(number): \(code.trimmingCharacters(in: .whitespaces))"
        }
    }

    nonisolated static let module = PreviewScan.sourcesDirectory.appending(
        path: "FeatureOnboarding",
        directoryHint: .isDirectory
    )

    /// What the standards keep out of a store and its module (§3, §4, §11), as patterns over code.
    nonisolated static let forbidden: [(rule: String, pattern: String)] = [
        ("the clock is injected", #"\bDate\s*\(\s*\)|\bDate\s*\.\s*now\b|\bDate\s*\(\s*timeIntervalSinceNow"#),
        ("the calendar is injected", #"\bCalendar\s*\.\s*(current|autoupdatingCurrent)\b"#),
        (
            "the locale is injected",
            #"\bLocale\s*\.\s*(current|autoupdatingCurrent)\b|locale:\s*\.(current|autoupdating)"#
        ),
        ("the zone is the calendar's", #"\bTimeZone\s*\.\s*(current|autoupdatingCurrent)\b"#),
        ("ids are injected", #"\bUUID\s*\(\s*\)"#),
        ("no task of the module's own", #"\bTask\s*(\{|\(|<|\.\s*detached)"#),
        ("no queues, timers or locks", #"\bDispatchQueue\b|\bTimer\b|\bNSLock\b|\bDispatchSemaphore\b"#),
        ("no singletons or defaults", #"\bstatic\s+(let|var)\s+shared\b|\bUserDefaults\b"#),
        ("no print", #"\bprint\s*\("#),
        ("no UIKit in a feature", #"\bimport\s+UIKit\b|\bimport\s+WatchKit\b"#),
        ("no forced unwraps of errors or casts", #"\btry!|\bas!"#),
        ("no unchecked sendability", #"@unchecked"#)
    ]

    nonisolated static func lines() throws -> [Line] {
        let files = FileManager.default.enumerator(at: module, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.sorted { $0.path < $1.path }.flatMap { file in
            let source = try SwiftSource(String(contentsOf: file, encoding: .utf8))
            return source.code.enumerated().map { Line(
                file: file.lastPathComponent,
                number: $0.offset + 1,
                code: $0.element
            ) }
        }
    }

    /// `pattern` with `\b` as the edge of an identifier. Swift's default is Unicode's word boundary, which sees no
    /// edge at the full stops of `Calendar.current.component`.
    nonisolated static func regex(_ pattern: String) throws -> Regex<AnyRegexOutput> {
        try Regex(pattern).wordBoundaryKind(.simple)
    }

    @Test("The module's sources are found: nine Swift files, the store and the root among them")
    func sources_areRead() throws {
        let files = try Set(Self.lines().map(\.file))
        #expect(files.isSuperset(of: ["OnboardingRoot.swift", "OnboardingStore.swift", "OnboardingScreen.swift"]))
        #expect(files.count >= 9, "\(files.sorted())")
    }

    @Test("OnboardingRoot, its initializer and its body are the only public declarations")
    func publicDeclarations_areOnboardingRootOnly() throws {
        let access = try Self.regex(#"\b(public|open|package)\b|@_spi|@_exported|@usableFromInline"#)
        let found = try Self.lines().filter { $0.code.contains(access) }
        #expect(found.allSatisfy { $0.file == "OnboardingRoot.swift" }, "\(found)")
        let declarations = found.map { $0.code.trimmingCharacters(in: .whitespaces) }
        #expect(declarations.count == 3, "\(found)")
        #expect(declarations.first == "public struct OnboardingRoot: View {")
        #expect(declarations
            .contains { $0.hasPrefix("public init(prepareRetry: @escaping @MainActor () async -> Void") })
        #expect(declarations.contains("public var body: some View {"))
    }

    @Test("No line of the module breaks a store rule of the standards", arguments: forbidden.map(\.rule))
    func forbiddenSpellings_areAbsent(rule: String) throws {
        let pattern = try #require(Self.forbidden.first { $0.rule == rule }?.pattern)
        let regex = try Self.regex(pattern)
        let found = try Self.lines().filter { $0.code.contains(regex) }
        #expect(found.isEmpty, "\(rule): \(found)")
    }

    @Test("Control: the scan finds each forbidden spelling in a line that has it, and not in a comment or a string")
    func forbiddenSpellings_scanHasTeeth() throws {
        let planted = """
        let now = Date()
        let zone = TimeZone.current.identifier; let day = Calendar.current.component(.weekday, from: start)
        let text = String(localized: "x", bundle: .module, locale: .current)
        let id = UUID()
        Task { await work() }
        Task.detached { }
        print("x"); DispatchQueue.main.async { }
        let later = Date.now.addingTimeInterval(1)
        // Date() in a comment
        let quoted = "UUID() and Calendar.current in a string"
        let injected = date.now
        """
        let code = SwiftSource(planted).code
        func hits(_ rule: String) throws -> [Int] {
            let pattern = try #require(Self.forbidden.first { $0.rule == rule }?.pattern)
            let regex = try Self.regex(pattern)
            return code.indices.filter { code[$0].contains(regex) }
        }
        let found = try Self.forbidden.map(\.rule).map { try "\($0): \(hits($0))" }
        #expect(found.prefix(9) == [
            "the clock is injected: [0, 7]", "the calendar is injected: [1]", "the locale is injected: [2]",
            "the zone is the calendar's: [1]", "ids are injected: [3]", "no task of the module's own: [4, 5]",
            "no queues, timers or locks: [6]", "no singletons or defaults: []", "no print: [6]"
        ])
    }

    @Test("Every try? of the module says why its failure may be dropped (standards §8)")
    func optionalTry_isExplained() throws {
        let files = FileManager.default.enumerator(at: Self.module, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            let code = try SwiftSource(String(contentsOf: file, encoding: .utf8)).code
            for index in code.indices where code[index].contains("try?") {
                let nearby = raw[max(index - 2, 0) ... min(index, raw.count - 1)]
                #expect(nearby.contains { $0.contains("//") }, "\(file.lastPathComponent):\(index + 1) has no comment")
            }
        }
    }
}
