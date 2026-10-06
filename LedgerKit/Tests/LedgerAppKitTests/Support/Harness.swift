import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDependencies
import LedgerPersistence

/// A composition on a fresh temporary directory (testing-strategy §3 rule 3), with stand-ins for the mirroring
/// handler and WatchConnectivity, and everything the launch does logged in order. It binds the keys with
/// `withDependencies`, never `prepareDependencies` (which would change them for every test in the process).
final class Harness {
    /// What happened, in order: the launch's events, and the stand-ins' calls.
    enum Entry: Equatable {
        case event(LaunchEvent)
        case handlerAssigned
        case companionActivated
    }

    nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    let directory: URL
    private(set) var log: [Entry] = []
    /// Told of each launch event as it is recorded, after `log` holds it: for a test that waits for a step to
    /// begin without polling `log`.
    var onEvent: (LaunchEvent) -> Void = { _ in }

    init(_ name: String = #function) {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LedgerAppKitTests-\(ProcessInfo.processInfo.processIdentifier)-\(safe)")
        try? FileManager.default.removeItem(at: directory) // absent unless an earlier run of this test crashed
    }

    /// Where the composition keeps its database, as the app does: a directory of its own.
    var databaseURL: URL {
        directory.appending(path: "Database/ledger.sqlite")
    }

    var databasePath: String {
        databaseURL.path(percentEncoded: false)
    }

    /// A composition over `databaseURL`, not yet booted. Its new device ids are `deviceUUID`; its process started at
    /// `processStart`.
    func composition(now: Date = Harness.now, processStart: Date? = nil) -> AppComposition {
        AppComposition(
            AppComposition.Environment(
                databaseURL: databaseURL,
                now: { now },
                newID: { Harness.deviceUUID },
                logger: .disabled,
                record: { [weak self] event in
                    self?.log.append(.event(event))
                    self?.onEvent(event)
                },
                assignMirroringHandler: { [weak self] in self?.log.append(.handlerAssigned) },
                activateCompanionSession: { [weak self] in self?.log.append(.companionActivated) },
                preparesDependencies: false,
                processStart: processStart
            )
        )
    }

    /// A composition booted as `App.init` boots it.
    func booted(now: Date = Harness.now) -> AppComposition {
        let composition = composition(now: now)
        composition.boot()
        return composition
    }

    nonisolated static let deviceUUID = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1") ?? UUID()

    /// Empties the log, so a test can look at what the next call does.
    func clearLog() {
        log = []
    }

    /// Opens the file the composition will open, for a test to arrange its rows, then closes it.
    func arrange(_ updates: @escaping @Sendable (Database) throws -> Void) throws {
        let queue = try LedgerDatabase.open(at: databaseURL)
        try queue.write(updates)
        try queue.close()
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory) // cleanup only: a leftover temporary file fails nothing
    }
}
