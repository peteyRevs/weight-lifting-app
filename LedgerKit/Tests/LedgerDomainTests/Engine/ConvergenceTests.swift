import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · convergence (rule 12)", .tags(.domain))
struct ConvergenceTests {
    /// A device that rebuilds its state from its whole log on every arrival (ADR-004 rule 2).
    private struct Device {
        var log: [EventEnvelope]

        var state: WorkoutState? {
            WorkoutEngine.replay(log)
        }

        mutating func receive(_ envelope: EventEnvelope) {
            log.append(envelope)
        }
    }

    @Test("Criterion 9: phone and watch edit apart during a partition and agree after swapping envelopes")
    func criterion9_partition_thenHeal_converges() throws {
        let started = Engine.started()
        let phoneEvents = EventBuilders.log(
            from: [
                Engine.logged(0, 0, at: 10),
                Engine.extend(tapped: 30),
                Engine.logged(0, 1, pounds: 190, at: 50),
                .setTargetChanged(exerciseIndex: 1, setID: Engine.set(1, 0), weight: .pounds(60), reps: nil)
            ],
            device: Engine.phone,
            firstSeq: 2,
            startingAt: Engine.at(10),
            spacing: 20
        )
        let watchEvents = EventBuilders.log(
            from: [
                .setTargetChanged(exerciseIndex: 1, setID: Engine.set(1, 0), weight: .pounds(57.5), reps: nil),
                Engine.logged(1, 0, pounds: 57.5, reps: 10, at: 25),
                .restSkipped,
                .exerciseSelected(exerciseIndex: 2, setIndex: 0)
            ],
            device: Engine.watch,
            startingAt: Engine.at(15),
            spacing: 20
        )
        var phone = Device(log: [started] + phoneEvents)
        var watch = Device(log: [started] + watchEvents)
        #expect(phone.state != watch.state)
        watchEvents.reversed().forEach { phone.receive($0) }
        phoneEvents.forEach { watch.receive($0) }
        let healed = try #require(phone.state)
        #expect(watch.state == healed)
        #expect(healed.exercises[1].sets[0].weight == .pounds(60))
        #expect(healed.exercises[0].sets[1].weight == .pounds(190))
        #expect(healed.cursor == Cursor(exerciseIndex: 2, setIndex: 0))
    }

    @Test(
        "Two devices holding the same envelopes, received in any order and with repeats, compute the same state",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func randomPartition_converges(seed: PropertySeed) {
        var random = RandomWorkout(seed: seed)
        let log = random.log(steps: 40)
        let started = log[0]
        let rest = Array(log.dropFirst())
        var phone = Device(log: [started] + rest.filter { $0.device == Engine.phone })
        var watch = Device(log: [started] + rest.filter { $0.device == Engine.watch })
        random.shuffled(rest).forEach { phone.receive($0) }
        random.shuffled(rest + rest.prefix(5)).forEach { watch.receive($0) }
        #expect(phone.state == watch.state)
        #expect(phone.state == ModelOracle.replay(log))
    }

    @Test("Equal wall clocks break by device ID, then seq, so both devices pick the same last writer")
    func wallClockTie_breaksByDeviceThenSeq() throws {
        let change = { (pounds: Decimal) in
            WorkoutEvent.setTargetChanged(exerciseIndex: 0, setID: Engine.set(0, 0), weight: .pounds(pounds), reps: nil)
        }
        let fromPhone = Engine.envelope(change(190), 30, from: Engine.phone, seq: 2)
        let fromWatch = Engine.envelope(change(195), 30, from: Engine.watch, seq: 1)
        let laterPhone = Engine.envelope(change(200), 30, from: Engine.phone, seq: 3)
        #expect(Engine.phone.rawValue.uuidString < Engine.watch.rawValue.uuidString)
        let forward = try #require(WorkoutEngine.replay([Engine.started(), fromPhone, fromWatch]))
        let backward = try #require(WorkoutEngine.replay([fromWatch, fromPhone, Engine.started()]))
        #expect(forward == backward)
        #expect(forward.exercises[0].sets[0].weight == .pounds(195))
        let sameDevice = try #require(WorkoutEngine.replay([laterPhone, fromPhone, Engine.started()]))
        #expect(sameDevice.exercises[0].sets[0].weight == .pounds(200))
    }
}
