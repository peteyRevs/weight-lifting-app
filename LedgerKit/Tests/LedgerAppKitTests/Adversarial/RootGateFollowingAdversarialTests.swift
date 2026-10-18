import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import SwiftUI
import Testing

/// F08 S3 adversarial round 1 (G2), criteria 3 and 4: the gate keeps following the real store, through every
/// way a program can come and go, a read that fails, and the scene leaving and returning.
@Suite("Adversarial F08 S3 · the gate keeps following the real store", .timeLimit(.minutes(1)))
struct RootGateFollowingAdversarialTests {
    @Test("A program saved by another route, deleted, saved again, made inactive by another: the gate follows each")
    func programComesAndGoes_gateFollows() async throws {
        let app = GateApp()
        defer { app.remove() }
        let following = try GateFollowing(app)
        await following.startCall()
        #expect(following.gate.destination == .onboarding)
        let first = try await following.saveNew()
        #expect(following.gate.destination == .main)
        try await following.deleteActive()
        #expect(following.gate.destination == .onboarding)
        try await following.saveNew(isActive: false)
        let second = try await following.saveNew()
        #expect(following.gate.destination == .main)
        try await following.saveNew() // a third replaces the second as the active one
        #expect(following.gate.destination == .main)
        try await following.activate(second)
        #expect(following.gate.destination == .main)
        try await following.deleteActive()
        #expect(following.gate.destination == .onboarding, "the third is stored but inactive")
        try await following.stores.programs.save(first) // a deleted program saved again comes back
        await gateObserved { following.gate.destination == .main }
        #expect(following.recorder.seen == [.loading, .onboarding, .main, .onboarding, .main, .onboarding, .main])
        await following.endCall()
    }

    @Test("Deleted and saved again at once, and saved and deleted at once: the gate ends where the store does")
    func changesAtOnce_gateEndsWhereTheStoreDoes() async throws {
        let app = GateApp()
        defer { app.remove() }
        let following = try GateFollowing(app)
        await following.startCall()
        try await following.saveNew()
        for _ in 0 ..< 5 {
            try await following.deleteAndSaveAtOnce()
            #expect(following.gate.destination == .main)
        }
        try await following.deleteActive()
        for _ in 0 ..< 5 {
            try await following.saveAndDeleteAtOnce()
            #expect(following.gate.destination == .onboarding)
        }
        #expect(!following.recorder.seen.dropFirst().contains(.loading), "\(following.recorder.seen)")
        await following.endCall()
    }

    /// Seeds 0 ..< 24; a failing case prints its seed and the step.
    @Test(
        "Seeded random changes to the real store and phase changes: after each, the gate shows what the store holds",
        arguments: 0 ..< 24
    )
    func randomChanges_gateShowsWhatTheStoreHolds(seed: Int) async throws {
        var random = GateRandom(seed: UInt64(seed))
        let app = GateApp("randomChanges\(seed)")
        defer { app.remove() }
        let following = try GateFollowing(app)
        await following.startCall()
        for step in 0 ..< 14 {
            try await following.change(Int.random(in: 0 ..< 7, using: &random), step: step)
            #expect(following.gate.destination == following.expected, "seed \(seed) step \(step)")
        }
        #expect(!following.recorder.seen.dropFirst().contains(.loading), "seed \(seed): \(following.recorder.seen)")
        await following.endCall()
    }

    @Test(
        "An active program that cannot be read ends the stream: the tabs, never onboarding; the next call reads again"
    )
    func unreadableProgram_showsTheTabs_andTheNextCallReadsAgain() async throws {
        let app = GateApp()
        defer { app.remove() }
        try await app.arrange { queue in
            try await GatePrograms.store([GatePrograms.make()], in: queue)
            try await queue.write { try $0.execute(sql: "UPDATE slot SET sets = 0") } // no slot has 0 sets
        }
        let composition = app.booted()
        let stores = try #require(composition.stores)
        await #expect(throws: (any Error).self) { try await stores.programs.active() }
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        await gate.follow(composition, in: .active) // returns: the stream ended on a task nobody cancelled
        #expect(recorder.seen == [.loading, .main], "\(recorder.seen)")

        // While no call runs the gate follows nothing: the damaged program goes away and the tabs stay.
        try await stores.queue.write { try $0.execute(sql: "UPDATE program SET is_active = 0") }
        #expect(try await stores.programs.active() == nil)
        #expect(gate.destination == .main)
        // The next foreground reads again.
        let call = Task { await gate.follow(composition, in: .active) }
        await gateObserved { gate.destination == .onboarding }
        #expect(recorder.seen == [.loading, .main, .onboarding])
        call.cancel()
        await call.value
    }

    @Test("A program that becomes unreadable while onboarding is shown switches to the tabs and saves nothing more")
    func programBecomesUnreadable_midOnboarding() async throws {
        let app = GateApp()
        defer { app.remove() }
        let following = try GateFollowing(app)
        await following.startCall()
        #expect(following.gate.destination == .onboarding)
        try await following.saveNew(awaited: false)
        try await following.stores.queue.write { try $0.execute(sql: "UPDATE slot SET reps = 0") }
        await app.journal.until("relay 0 ended")
        await gateObserved { following.gate.destination == .main }
        #expect(!following.recorder.seen.dropFirst(2).contains(.onboarding), "\(following.recorder.seen)")
        await following.endCall()
    }

    @Test("The fake store is followed as the real one is: saved, deleted, activated")
    func fakeStore_isFollowed() async throws {
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(catalog: ExerciseCatalog.seed()))
        let gate = RootGate()
        let recorder = GateDestinationRecorder(gate)
        let call = Task { await gate.follow { stores.programs } }
        await gateObserved { gate.destination == .onboarding }
        let program = try GatePrograms.make()
        try await stores.programs.save(program)
        await gateObserved { gate.destination == .main }
        try await stores.programs.delete(program.id)
        await gateObserved { gate.destination == .onboarding }
        try await stores.programs.save(program)
        await gateObserved { gate.destination == .main }
        #expect(recorder.seen == [.loading, .onboarding, .main, .onboarding, .main])
        call.cancel()
        await call.value
        #expect(gate.destination == .main, "a cancelled call changes nothing")
    }
}
