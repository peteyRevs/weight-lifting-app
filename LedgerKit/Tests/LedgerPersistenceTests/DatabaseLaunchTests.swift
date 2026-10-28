import Dispatch
import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import os
import Testing

/// `DatabaseLaunch`, the database half both apps' launches share: decision #29 (open), #28 (seed), the settings
/// fallback and the retries on return to the foreground.
@MainActor
@Suite("DatabaseLaunch", .tags(.persistence), .timeLimit(.minutes(1)))
struct DatabaseLaunchTests {
    nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    nonisolated static let deviceUUID = UUID(uuidString: "00000000-0000-4000-8000-0000000000D3") ?? UUID()

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

    @Test("The steps are in launch order")
    func steps_inOrder() {
        #expect(LaunchStep.allCases == [
            .assignMirroringHandler, .openDatabase, .seedCatalog, .loadSettings, .resumeWorkout,
            .activateCompanionSession
        ])
    }
}

/// `DatabaseLaunch` under cancelled and overlapping calls (F7-S2-1, F7-S2-3): the launch owns each step's task, so
/// cancelling a call never cancels a step, and a call that finds a step running waits for it.
@MainActor
@Suite("DatabaseLaunch · cancelled and overlapping calls", .tags(.persistence), .timeLimit(.minutes(1)))
struct DatabaseLaunchConcurrencyTests {
    @Test("Cancelling a caller never cancels a running step: the seed waiting for the writer still seeds")
    func cancelledCaller_neverCancelsTheStep() async throws {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        subject.launch.open()
        let hold = try WriterHold(#require(subject.launch.stores).queue)
        var first: Task<Void, Never>?
        await withCheckedContinuation { seedBegan in // the first call starts the seed, which waits for the writer
            subject.whenSeedBegins = { seedBegan.resume() }
            first = Task { await subject.launch.resume(isForeground: true) }
        }
        let caller = try #require(first)
        caller.cancel()
        hold.free()
        await caller.value
        await subject.launch.resume(isForeground: false) // waits for the same seed, then loads the settings
        #expect(subject.launch.isCatalogSeeded)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
    }

    @Test("A call cancelled before it starts still runs every step once, to its outcome")
    func cancelledBeforeStarting_runsEveryStepOnce() async throws {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        let queue = try LedgerDatabase.open(at: subject.url)
        try await GRDBSettingsRepository(queue).save(DatabaseLaunchTests.kilograms)
        try queue.close()
        subject.launch.open()
        let first = Task { await subject.launch.resume(isForeground: true) }
        first.cancel()
        await first.value
        await subject.launch.resume(isForeground: false)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
        #expect(subject.launch.isCatalogSeeded)
        #expect(subject.launch.settings == DatabaseLaunchTests.kilograms)
    }

    @Test("A call that finds the seed running waits for its outcome before it begins the settings")
    func overlappingCall_waitsForTheRunningStep() async throws {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        try subject.arrange { try $0.execute(sql: DatabaseLaunchTests.refuseExercises) }
        subject.launch.open()
        let hold = try WriterHold(#require(subject.launch.stores).queue)
        var first: Task<Void, Never>?
        await withCheckedContinuation { seedBegan in
            subject.whenSeedBegins = { seedBegan.resume() }
            first = Task { await subject.launch.resume(isForeground: false) }
        }
        let second = Task { await subject.launch.resume(isForeground: true) }
        for _ in 0 ..< 10 {
            await Task.yield() // room for the second call to run while the seed waits for the writer
        }
        hold.free()
        await second.value
        await first?.value
        #expect(subject.events == [
            .began(.openDatabase), .began(.seedCatalog), .failed(.seedCatalog), .began(.loadSettings)
        ])
    }

    @Test("Overlapping calls start each step once and both wait for it")
    func overlappingCalls_startEachStepOnce() async {
        let subject = DatabaseLaunchTests.Subject()
        defer { subject.remove() }
        subject.launch.open()
        async let first: Void = subject.launch.resume(isForeground: false)
        async let second: Void = subject.launch.resume(isForeground: true)
        _ = await (first, second)
        #expect(subject.events.filter { $0 == .began(.seedCatalog) }.count == 1)
        #expect(subject.events.filter { $0 == .began(.loadSettings) }.count == 1)
        #expect(subject.launch.isCatalogSeeded)
    }
}

extension DatabaseLaunchTests {
    static var kilograms: Settings {
        var settings = Settings.default
        settings.units = .kg
        return settings
    }

    nonisolated static let refuseExercises =
        "CREATE TRIGGER refuse BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'full'); END"

    /// A launch over a file in its own temporary directory, recording its events and what `onOpen` was given.
    @MainActor
    final class Subject {
        let directory: TemporaryDirectory
        private(set) var events: [LaunchEvent] = []
        private(set) var opened: [DeviceID] = []
        /// Called once, when the seed step begins.
        var whenSeedBegins: (() -> Void)?
        private let regionalSettings: Settings?
        private(set) lazy var launch = DatabaseLaunch(
            at: url,
            kind: .phone,
            regionalSettings: regionalSettings,
            now: { DatabaseLaunchTests.now },
            newID: { DatabaseLaunchTests.deviceUUID },
            logger: Logger(.disabled),
            record: { [weak self] event in
                self?.events.append(event)
                if event == .began(.seedCatalog) {
                    self?.whenSeedBegins?()
                    self?.whenSeedBegins = nil
                }
            },
            onOpen: { [weak self] in self?.opened.append($0.deviceID) }
        )

        /// `regionalSettings` are the phone's (F14); `directory` is given for a second launch of one file.
        init(_ name: String = #function, regionalSettings: Settings? = nil, in directory: TemporaryDirectory? = nil) {
            self.directory = directory ?? TemporaryDirectory("DatabaseLaunch\(name)")
            self.regionalSettings = regionalSettings
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

/// Holds a database's writer until `free()`: what a step then waits for.
final class WriterHold: Sendable {
    private let held = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    init(_ queue: DatabaseQueue) {
        DispatchQueue.global().async { [held, release] in
            queue.inDatabase { _ in
                held.signal()
                release.wait()
            }
        }
        held.wait()
    }

    func free() {
        release.signal()
    }
}
