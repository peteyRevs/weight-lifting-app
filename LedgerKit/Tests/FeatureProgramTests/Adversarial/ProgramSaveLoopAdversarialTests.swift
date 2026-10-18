@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: the save loop (criteria 1 to 4). Storms of edits against a program store whose
/// writes a test holds and lets go: the program stored at the end is the one the same edits make applied one at
/// a time, no edit is lost or written twice, and the edits made while a write was held go in the next write,
/// together. Every case names its seed; the seeds are the shared count (`LEDGER_PROPERTY_SEED_COUNT`).
@MainActor
@Suite("Adversarial F11 S13 · the save loop under storms", .tags(.feature, .property), .timeLimit(.minutes(2)))
struct ProgramSaveLoopAdversarialTests {
    // MARK: The session alone, in held bursts

    /// One of `choices`, drawn by `random`.
    static func pick<Element>(_ choices: [Element], _ random: inout SeededGenerator) -> Element {
        choices[Int.random(in: choices.indices, using: &random)]
    }

    /// An edit of the block a lifter could make on `program`, with fresh ids from `fresh`: a mix of the
    /// absolute edits (by what they become), the relative one ("−") and those safe through their ids.
    static func edit(on program: Program, _ random: inout SeededGenerator, fresh: inout Int) -> ProgramBuilderEdit {
        let weeks = max(1, program.weeks.count)
        let week = Int.random(in: -1 ... weeks, using: &random)
        let days = program.days.map(\.id) as [DayTemplateID?] + [nil, DayTemplateID(Fixtures.uuid(99999))]
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0:
            return .renameProgram(pick(["Upper / Lower", "Block", "  ", "", "Upper Lower", "B"], &random))
        case 1, 2:
            fresh += 1
            return .addWeek(WeekID(Fixtures.uuid(80000 + fresh)))
        case 3, 4:
            return .removeLastWeek(loggedWeeks: Bool.random(using: &random) ? [] : [weeks - 1])
        case 5:
            return .setDeload(Bool.random(using: &random), week: week)
        case 6:
            return .setSchedule(week: week, weekday: pick(Weekday.allCases, &random), day: pick(days, &random))
        case 7:
            return .copyPreviousWeek(week: week)
        case 8:
            return .applyToLaterWeeks(week: week)
        default:
            fresh += 1
            return .addDay(DayTemplateID(Fixtures.uuid(85000 + fresh)), name: "Day \(fresh)")
        }
    }

    /// A burst's worth of edits, each checked on screen as it is made; returns how many were queued.
    static func burst(
        _ rig: S13SessionRig<ProgramBuilderEdit>,
        _ reference: inout Program,
        _ random: inout SeededGenerator,
        fresh: inout Int,
        seed: PropertySeed
    ) -> Int {
        var queued = 0
        for _ in 0 ..< Int.random(in: 1 ... 6, using: &random) {
            let edit = edit(on: reference, &random, fresh: &fresh)
            let before = reference
            reference = s13OneAtATime([edit], to: reference)
            let wasQueued = rig.session.enqueue(edit)
            #expect(wasQueued == (before != reference), "\(seed): \(edit) queued \(wasQueued)")
            #expect(rig.session.shown == reference, "\(seed): the screen after \(edit)")
            queued += wasQueued ? 1 : 0
        }
        return queued
    }

    @Test(
        "A storm of edits in held bursts: one write per burst, and the stored program is the edits one at a time",
        arguments: PropertySeed.all
    )
    func heldBursts_storeWhatOneAtATimeStores_oneWritePerBurst(seed: PropertySeed) async throws {
        var random = seed.generator
        let initial = try S13Fixtures.seed(weeks: Int.random(in: 2 ... 6, using: &random))
        let rig = try S13SessionRig<ProgramBuilderEdit>(program: initial)
        let follower = rig.follow()
        let loop = Task { await rig.session.run { _ in } }
        defer {
            loop.cancel()
            follower.cancel()
        }
        var reference = initial
        var writes = 0
        var parked = false
        var fresh = 0
        for _ in 0 ..< Int.random(in: 1 ... 8, using: &random) {
            await rig.probe.hold(.updateProgram)
            let queued = Self.burst(rig, &reference, &random, fresh: &fresh, seed: seed)
            if parked {
                await rig.probe.release()
            }
            parked = queued > 0
            if parked {
                writes += 1
                try await rig.probe.waitUntilHeld()
            } else {
                await s13Until { rig.session.isIdle }
            }
        }
        if parked {
            await rig.probe.release()
        }
        await s13Until { rig.session.isIdle }
        #expect(try await rig.memory.programs.active() == reference, "\(seed): stored")
        #expect(rig.session.shown == reference, "\(seed): shown")
        #expect(rig.session.waiting.isEmpty, "\(seed)")
        #expect(await rig.updates() == writes, "\(seed): one write per burst that queued an edit")
    }

    // MARK: The store, from the screen, with free scheduling

    /// What the screen offers that changes the program or the selection: no route, no new day (its route waits
    /// and holds the next one back, which the route suite attacks).
    static func offered(_ model: ProgramBuilderModel) -> [ProgramBuilderAction] {
        ProgramActionsAdversarialTests.offered(model).map(\.action).filter { action in
            switch action {
            case .route, .addDay: false
            default: true
            }
        }
    }

    /// `reference` after `action`, as the store applies it, with the ids it draws: one per "+".
    static func applied(_ action: ProgramBuilderAction, to reference: Program, addedWeeks: inout Int) -> Program {
        switch action {
        case let .edit(edit, _):
            return s13OneAtATime([edit], to: reference)
        case .addWeek:
            defer { addedWeeks += 1 }
            return s13OneAtATime([.addWeek(WeekID(S13IDs.id(addedWeeks)))], to: reference)
        default:
            return reference
        }
    }

    @Test(
        "Forty taps from the screen, writes held and let go at random, the scheduler free: nothing lost or doubled",
        arguments: PropertySeed.all
    )
    func screenStorm_storesWhatOneAtATimeStores(seed: PropertySeed) async throws {
        var random = seed.generator
        let rig = try S13Rig(yields: Int.random(in: 0 ... 2, using: &random))
        let tasks = await rig.start()
        defer {
            tasks.sources.cancel()
            tasks.saves.cancel()
        }
        var reference = try #require(rig.session.shown)
        var addedWeeks = 0
        for _ in 0 ..< 40 {
            if Int.random(in: 0 ..< 4, using: &random) == 0 {
                await rig.probe.hold(.updateProgram)
            }
            let model = try #require(rig.model, "\(seed): no model")
            let action = Self.pick(Self.offered(model), &random)
            reference = Self.applied(action, to: reference, addedWeeks: &addedWeeks)
            rig.store.send(action)
            #expect(rig.session.shown == reference, "\(seed): the screen after \(action)")
            if Int.random(in: 0 ..< 3, using: &random) == 0 {
                await rig.probe.release()
            }
            for _ in 0 ..< Int.random(in: 0 ... 3, using: &random) {
                await Task.yield()
            }
        }
        while !rig.session.isIdle {
            await rig.probe.release()
            await Task.yield()
        }
        #expect(try await rig.storedProgram() == reference, "\(seed): stored")
        #expect(rig.session.shown == reference, "\(seed): shown")
        #expect(rig.store.notice != .saveFailed, "\(seed)")
        #expect(rig.ids.drawn == addedWeeks, "\(seed): one id per \"+\"")
    }
}
