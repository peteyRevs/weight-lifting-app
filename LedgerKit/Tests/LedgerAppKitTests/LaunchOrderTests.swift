import Foundation
@testable import LedgerAppKit
import Testing

/// The iPhone launch's order (F07 criterion 6, ADR-005). `boot()` is synchronous, so the compiler already rules
/// out an `await` before the mirroring handler is assigned; these tests pin the order the steps run in.
@Suite("Launch order", .timeLimit(.minutes(1)))
struct LaunchOrderTests {
    @Test("Criterion 6: boot assigns the mirroring handler first, then opens the database, and awaits nothing")
    func boot_assignsTheHandlerFirst() {
        let harness = Harness()
        defer { harness.remove() }
        _ = harness.booted()
        #expect(harness.log == [
            .event(.began(.assignMirroringHandler)),
            .handlerAssigned,
            .event(.began(.openDatabase))
        ])
    }

    @Test("The whole launch runs its steps in the brief's order, the asynchronous ones after boot")
    func launch_runsTheStepsInOrder() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(harness.log == [
            .event(.began(.assignMirroringHandler)),
            .handlerAssigned,
            .event(.began(.openDatabase)),
            .event(.began(.seedCatalog)),
            .event(.began(.loadSettings)),
            .event(.began(.activateCompanionSession)),
            .companionActivated
        ])
        #expect(LaunchStep.allCases == [
            .assignMirroringHandler, .openDatabase, .seedCatalog, .loadSettings, .activateCompanionSession
        ])
    }

    @Test("The handler is assigned even when the database then fails to open")
    func boot_handlerFirst_evenWhenOpeningFails() throws {
        let harness = Harness()
        defer { harness.remove() }
        try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)
        let composition = harness.booted()
        #expect(composition.state == .databaseUnavailable)
        #expect(harness.log.first == .event(.began(.assignMirroringHandler)))
        #expect(harness.log.dropFirst().first == .handlerAssigned)
    }

    @Test("Later calls of resume run nothing that already succeeded")
    func resume_again_runsNothingTwice() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        await composition.resume(in: .active)
        harness.clearLog()
        await composition.resume(in: .inactive)
        await composition.resume(in: .active)
        #expect(harness.log.isEmpty)
    }
}
