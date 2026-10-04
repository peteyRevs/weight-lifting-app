import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import os
import Testing

/// `DatabaseLaunch`, the database half both apps' launches share: decision #29 (open), #28 (seed), the settings
/// fallback, the retries on return to the foreground, and cancelled or overlapping passes (F7-S2-1).
@MainActor
@Suite("DatabaseLaunch", .tags(.persistence), .timeLimit(.minutes(1)))
struct DatabaseLaunchTests {
    nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    nonisolated static let deviceUUID = UUID(uuidString: "00000000-0000-4000-8000-0000000000D3") ?? UUID()

    static var kilograms: Settings {
        var settings = Settings.default
        settings.units = .kg
        return settings
    }

    nonisolated static let refuseExercises =
        "CREATE TRIGGER refuse BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'full'); END"

    @Test("Opening binds through onOpen, then the first pass seeds and loads the saved settings, in that order")
    func open_thenFirstPass() async throws {
        let subject = Subject()
        defer { subject.remove() }
        let saved = Self.kilograms
        let queue = try LedgerDatabase.open(at: subject.url)
        try await GRDBSettingsRepository(queue).save(saved)
        try queue.close()
        subject.launch.open()
        #expect(subject.launch.state == .ready)
        #expect(subject.opened == [DeviceID(Self.deviceUUID)])
        #expect(subject.launch.stores?.deviceID == DeviceID(Self.deviceUUID))
        await subject.launch.resume(isForeground: false)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
        #expect(subject.launch.isCatalogSeeded)
        #expect(subject.launch.settings == saved)
        subject.clearEvents()
        await subject.launch.resume(isForeground: true)
        #expect(subject.events.isEmpty) // nothing left to do
    }

    @Test("A launch never opened (a process hosting tests) does nothing on resume")
    func neverOpened_resumeDoesNothing() async {
        let subject = Subject()
        defer { subject.remove() }
        await subject.launch.resume(isForeground: true)
        #expect(subject.launch.state == .idle)
        #expect(subject.events.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: subject.url.path(percentEncoded: false)))
    }

    @Test("#28: a failed seed is logged and recorded, the settings still load, and only the foreground retries it")
    func seedFailure_carriesOn_thenRetriesInTheForeground() async throws {
        let subject = Subject()
        defer { subject.remove() }
        try subject.arrange { try $0.execute(sql: Self.refuseExercises) }
        subject.launch.open()
        await subject.launch.resume(isForeground: false)
        #expect(subject.events.suffix(3) == [.began(.seedCatalog), .failed(.seedCatalog), .began(.loadSettings)])
        #expect(!subject.launch.isCatalogSeeded)
        #expect(subject.launch.state == .ready)
        try await #require(subject.launch.stores).queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        subject.clearEvents()
        await subject.launch.resume(isForeground: false)
        #expect(subject.events.isEmpty)
        await subject.launch.resume(isForeground: true)
        #expect(subject.events == [.began(.seedCatalog)])
        #expect(subject.launch.isCatalogSeeded)
    }

    @Test("#29: a file that is not a database is unavailable and untouched; the foreground retries; nothing binds")
    func openFailure_untouched_retriedInTheForeground() async throws {
        let subject = Subject()
        defer { subject.remove() }
        let directory = subject.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let damaged = Data(repeating: 0x41, count: 4096)
        try damaged.write(to: subject.url)
        subject.launch.open()
        #expect(subject.launch.state == .databaseUnavailable)
        #expect(subject.events == [.began(.openDatabase), .failed(.openDatabase)])
        await subject.launch.resume(isForeground: true) // the first pass: no retry yet
        await subject.launch.resume(isForeground: false)
        #expect(subject.events.count == 2)
        await subject.launch.resume(isForeground: true)
        #expect(subject.events.count == 4)
        #expect(try Data(contentsOf: subject.url) == damaged)
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == ["ledger.sqlite"])
        #expect(subject.opened.isEmpty)
        try FileManager.default.removeItem(at: subject.url) // the test, standing in for the cause going away
        subject.clearEvents()
        await subject.launch.resume(isForeground: true)
        #expect(subject.launch.state == .ready)
        #expect(subject.opened.count == 1)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
    }

    @Test("An unreadable settings row: the defaults in memory, recorded once, not retried, the row unchanged")
    func unreadableSettings_fallBack_notRetried() async throws {
        let subject = Subject()
        defer { subject.remove() }
        try subject.arrange { try $0.execute(sql: "INSERT INTO settings VALUES ('singleton', 999, '{}', 'then')") }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        await subject.launch.resume(isForeground: true)
        #expect(subject.launch.settings == .default)
        #expect(subject.events.filter { $0 == .began(.loadSettings) }.count == 1)
        #expect(subject.events.contains(.failed(.loadSettings)))
        let version = try await #require(subject.launch.stores).queue.read {
            try Int.fetchOne($0, sql: "SELECT payload_version FROM settings")
        }
        #expect(version == 999)
    }

    @Test("F7-S2-1: a cancelled pass records no failure, and the next call, in any phase, runs its steps again")
    func cancelledPass_isNotAttempted_andRunsAgain() async throws {
        let subject = Subject()
        defer { subject.remove() }
        let queue = try LedgerDatabase.open(at: subject.url)
        try await GRDBSettingsRepository(queue).save(Self.kilograms)
        try queue.close()
        subject.launch.open()
        let first = Task { await subject.launch.resume(isForeground: true) }
        first.cancel()
        await first.value
        #expect(!subject.events.contains(.failed(.seedCatalog)))
        #expect(!subject.events.contains(.failed(.loadSettings)))
        #expect(subject.launch.settings == .default)
        await subject.launch.resume(isForeground: false) // the launch has not finished its first pass
        #expect(subject.launch.isCatalogSeeded)
        #expect(subject.launch.settings == Self.kilograms)
    }

    @Test("F7-S2-1: overlapping calls start each step once")
    func overlappingCalls_startEachStepOnce() async {
        let subject = Subject()
        defer { subject.remove() }
        subject.launch.open()
        async let first: Void = subject.launch.resume(isForeground: false)
        async let second: Void = subject.launch.resume(isForeground: true)
        _ = await (first, second)
        #expect(subject.events.filter { $0 == .began(.seedCatalog) }.count == 1)
        #expect(subject.events.filter { $0 == .began(.loadSettings) }.count == 1)
        #expect(subject.launch.isCatalogSeeded)
    }

    @Test("The steps are in launch order")
    func steps_inOrder() {
        #expect(LaunchStep.allCases == [
            .assignMirroringHandler, .openDatabase, .seedCatalog, .loadSettings, .activateCompanionSession
        ])
    }
}

extension DatabaseLaunchTests {
    /// A launch over a file in its own temporary directory, recording its events and what `onOpen` was given.
    @MainActor
    final class Subject {
        let directory: TemporaryDirectory
        private(set) var events: [LaunchEvent] = []
        private(set) var opened: [DeviceID] = []
        private(set) lazy var launch = DatabaseLaunch(
            at: url,
            kind: .phone,
            now: { DatabaseLaunchTests.now },
            newID: { DatabaseLaunchTests.deviceUUID },
            logger: Logger(.disabled),
            record: { [weak self] in self?.events.append($0) },
            onOpen: { [weak self] in self?.opened.append($0.deviceID) }
        )

        init(_ name: String = #function) {
            directory = TemporaryDirectory("DatabaseLaunch\(name)")
        }

        var url: URL {
            directory.file("Database/ledger.sqlite")
        }

        func clearEvents() {
            events = []
        }

        /// Opens the file the launch will open, for the test to arrange its rows, then closes it.
        func arrange(_ updates: @escaping @Sendable (Database) throws -> Void) throws {
            let queue = try LedgerDatabase.open(at: url)
            try queue.write(updates)
            try queue.close()
        }

        func remove() {
            try? directory.remove() // cleanup only: a leftover temporary file fails nothing
        }
    }
}
