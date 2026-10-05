import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import SwiftUI
import Testing

/// A gate following a booted composition's real store of programs, through `GateRelayedPrograms`, so that each
/// change the test makes to the store can be waited for until the gate has dealt with it.
final class GateFollowing {
    let app: GateApp
    let composition: AppComposition
    let gate = RootGate()
    let recorder: GateDestinationRecorder
    let stores: LedgerStores
    private var call: Task<Void, Never>?
    /// The program the store holds as active, as the test left it.
    private(set) var active: Program?
    /// Stored programs that are not active.
    private var spare: [Program] = []

    init(_ app: GateApp) throws {
        self.app = app
        composition = app.booted()
        stores = try #require(composition.stores)
        recorder = GateDestinationRecorder(gate)
    }

    var expected: RootGate.Destination {
        active == nil ? .onboarding : .main
    }

    /// The scene's phase changed: the call that is running is cancelled and the next one starts, as
    /// `.task(id: scenePhase)` does. Returns once the gate has dealt with the store's current value.
    func startCall(in phase: ScenePhase = .active) async {
        await endCall()
        let mark = app.journal.entries.count
        call = Task { [gate, composition, notes = app.journal] in
            await gate.follow {
                await composition.resume(in: phase)
                return composition.stores.map { GateRelayedPrograms($0.programs, notes) }
            }
        }
        await app.journal.untilDealtWith(GatePrograms.name(active), since: mark)
    }

    func endCall() async {
        call?.cancel()
        await call?.value
        call = nil
    }

    /// Saves a new program by another route than onboarding; an active one becomes the store's active program.
    @discardableResult
    func saveNew(isActive: Bool = true, awaited: Bool = true) async throws -> Program {
        let program = try GatePrograms.make(isActive: isActive)
        let mark = app.journal.entries.count
        try await stores.programs.save(program)
        if isActive {
            active = program
            if awaited, call != nil {
                await app.journal.untilDealtWith(GatePrograms.name(program), since: mark)
            }
        }
        return program
    }

    func deleteActive(awaited: Bool = true) async throws {
        guard let program = active else {
            return
        }
        let mark = app.journal.entries.count
        try await stores.programs.delete(program.id)
        active = nil
        if awaited, call != nil {
            await app.journal.untilDealtWith("none", since: mark)
        }
    }

    func activate(_ program: Program) async throws {
        let mark = app.journal.entries.count
        try await stores.programs.setActive(program.id)
        active = program
        if call != nil {
            await app.journal.untilDealtWith(GatePrograms.name(program), since: mark)
        }
    }

    /// Makes two changes with nothing awaited between them, then a change the gate must report, so the test
    /// knows the gate has seen everything before it.
    func deleteAndSaveAtOnce() async throws {
        try await deleteActive(awaited: false)
        try await saveNew()
    }

    func saveAndDeleteAtOnce() async throws {
        try await saveNew(awaited: false)
        try await deleteActive(awaited: false)
        try await saveNew()
        try await deleteActive()
    }

    /// One change of the seeded plays, by number: a program saved (active or not), the active one deleted, a
    /// stored one made active, two changes at once, a phase change, or a change while no call is running.
    func change(_ choice: Int, step: Int) async throws {
        switch choice {
        case 0: try await saveNew()
        case 1: try await spare.append(saveNew(isActive: false))
        case 2: try await deleteActive()
        case 3: try await activateSpare()
        case 4: try await changeTwiceAtOnce()
        case 5: await startCall(in: [ScenePhase.active, .inactive, .background][step % 3])
        default: try await changeWhileAway()
        }
    }

    private func activateSpare() async throws {
        if let program = spare.popLast() {
            try await activate(program)
        }
    }

    private func changeTwiceAtOnce() async throws {
        if active == nil {
            try await saveAndDeleteAtOnce()
        } else {
            try await deleteAndSaveAtOnce()
        }
    }

    /// The scene is away while the store changes: the next call must read what is there now.
    private func changeWhileAway() async throws {
        await endCall()
        if active == nil {
            try await saveNew()
        } else {
            try await deleteActive()
        }
        await startCall()
    }
}
