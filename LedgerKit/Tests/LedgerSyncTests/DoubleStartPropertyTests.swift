import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S5b: across a double start, no set the lifter logged is ever lost (Pete 2026-11-25). Each seed starts a
/// workout on each device, close together or not, partitioned or racing over a slow, duplicating, lossy link, then
/// logs sets on whichever workout each device shows, and ends with a reconnect on a clean link. Every set a device
/// logged must then be done on that device, in the workout it shows or in its history; and when the starts were
/// within the window, both devices show the same workout, converged.
@Suite("Live sync · no set lost across a double start", .tags(.sync, .property), .timeLimit(.minutes(1)))
struct DoubleStartPropertyTests {
    typealias Side = LiveSyncPair.Side

    /// A set as a device logged it.
    struct Logged {
        let workout: WorkoutID
        let setID: SetID
    }

    @Test(
        "Every logged set survives a double start, on the device that logged it",
        arguments: LiveSyncPropertyTests.seeds
    )
    func doubleStart_losesNoSet(seed: UInt64) async throws {
        var writer = EditWriter(seed: seed ^ 0xD0B1)
        let link = FakeLiveNetwork.Link(delay: .zero ... .seconds(2), loss: 0.2, duplication: 0.2)
        let pair = await LiveSyncPair.make(seed: seed, link: link)
        defer { pair.close() }
        let gap = writer.chance(0.8) ? writer.int(in: 0 ... 50) : writer.int(in: 61 ... 120)
        if writer.chance(0.7) {
            await pair.partition()
        }
        await Self.startBoth(pair, apart: gap, &writer)
        var logged: [DeviceID: [Logged]] = [:]
        for _ in 0 ..< writer.int(in: 4 ... 16) {
            let side = writer.coin() ? pair.phone : pair.watch
            pair.clock.set(pair.clock.now.addingTimeInterval(Double(writer.int(in: 1 ... 15))))
            if let set = try await Self.logRandomSet(on: side, &writer, at: pair.clock.now) {
                logged[side.device, default: []].append(set)
            }
            await side.rest()
            await pair.step(by: .milliseconds(writer.int(in: 0 ... 3000)))
            if writer.chance(0.1), pair.network.isPartitioned {
                await pair.heal()
            } else if writer.chance(0.1) {
                await pair.partition()
            }
        }
        pair.network.setLink(.init())
        await pair.partition()
        await pair.heal()
        await pair.settle()
        for side in pair.sides {
            for set in logged[side.device] ?? [] {
                #expect(try await Self.isDone(set, on: side), "seed \(seed): \(side.device) lost a set it logged")
            }
        }
        if gap <= Int(LocalWorkoutSessionActor.doubleStartWindow), let shown = try await pair.phone.host.current() {
            let isConverged = try await pair.converged(on: shown.id)
            #expect(isConverged, "seed \(seed): one workout on both")
        }
    }

    /// Each device starts its own workout, in an order the seed picks, `apart` seconds apart; a start the host
    /// refuses (the peer's arrived first, and this device adopted it) is skipped.
    static func startBoth(_ pair: LiveSyncPair, apart: Int, _ writer: inout EditWriter) async {
        let order = writer.coin() ? [pair.phone, pair.watch] : [pair.watch, pair.phone]
        for (index, side) in order.enumerated() {
            let seconds = Double(index * apart)
            pair.clock.set(Sample.at(seconds))
            let snapshot = side.device == pair.phone.device
                ? Sample.session
                : HostDoubleStartTests.watchSession(at: seconds)
            try? await side.host.start(snapshot)
            await side.rest()
            await pair.step(by: .milliseconds(writer.int(in: 0 ... 3000)))
        }
    }

    /// Logs a random row of the workout `side` shows, and returns it when it is done after.
    static func logRandomSet(on side: Side, _ writer: inout EditWriter, at date: Date) async throws -> Logged? {
        guard let state = try await side.host.current() else {
            return nil
        }
        let exercise = writer.int(in: 0 ... state.exercises.count - 1)
        let row = writer.int(in: 0 ... state.exercises[exercise].sets.count - 1)
        let after = try await side.host.apply(HostDoubleStartTests.logged(state, exercise, row, at: date))
        let id = state.exercises[exercise].sets[row].id
        let isDone = after.exercises[exercise].sets.first { $0.id == id }?.isDone == true
        return after.id == state.id && isDone ? Logged(workout: state.id, setID: id) : nil
    }

    /// Whether `set` is done on `side`: in the workout it shows, or in its history.
    static func isDone(_ set: Logged, on side: Side) async throws -> Bool {
        var copy = try await side.host.current()
        if copy?.id != set.workout {
            copy = try await side.stores.workouts.workout(id: set.workout)
        }
        return copy?.exercises.flatMap(\.sets).first { $0.id == set.setID }?.isDone == true
    }
}
