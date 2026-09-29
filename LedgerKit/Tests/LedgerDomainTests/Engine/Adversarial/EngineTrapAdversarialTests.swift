import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

#if os(macOS)
    /// Extreme values a decoded peer envelope can carry, run in a child process so a trap fails one
    /// test instead of the whole run (testing-strategy §2.1 exit tests). None of these may trap.
    @Suite("WorkoutEngine · trap-freedom (adversarial)", .tags(.domain))
    struct EngineTrapAdversarialTests {
        /// A set log, a +30 s and a rest start, all stamped `date`, from the watch.
        static func envelopes(at date: Date, row: Int, firstSeq: UInt64) -> [EventEnvelope] {
            let events: [WorkoutEvent] = [
                EngineAdv.logged(0, row, doneAt: 0),
                .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: date),
                .restStarted(endsAt: date, total: .seconds(30))
            ]
            return events.enumerated().map { offset, event in
                EventEnvelope(
                    event: event, workoutID: EngineAdv.workoutID, device: EngineAdv.watch,
                    seq: firstSeq + UInt64(offset), wallClock: date
                )
            }
        }
    }

    extension EngineTrapAdversarialTests {
        @Test("Rest durations at Int64.max seconds, extended over and over, do not trap.")
        func hugeDurations_doNotTrap() async {
            await #expect(processExitsWith: .success) {
                let huge = Duration.seconds(Int64.max)
                var state = EngineAdv.state(after: [
                    EngineAdv.start(),
                    EngineAdv.env(.restStarted(endsAt: engineTime(90), total: huge), seq: 2, at: 0)
                ])
                for seq in 3 ..< 40 {
                    state = WorkoutEngine.reduce(
                        state,
                        EngineAdv.env(EngineAdv.extend(huge, on: state, at: 1), seq: UInt64(seq), at: 1)
                    ).0
                }
                state = WorkoutEngine.reduce(
                    state,
                    EngineAdv.env(EngineAdv.extend(.seconds(Int64.min), on: state, at: 2), seq: 41, at: 2)
                ).0
                if state == nil {
                    exit(1)
                }
            }
        }

        @Test("A decodable restStarted whose total is the largest Duration, then an ordinary +30 s, does not trap.")
        func decodedMaxDurationThenPlus30_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let template = WorkoutEvent.restStarted(endsAt: engineTime(90), total: .zero)
                guard let json = try? String(data: JSONEncoder().encode(template), encoding: .utf8) else {
                    exit(2)
                }
                // Duration encodes as [high, low] attoseconds; any pair decodes, so a corrupt or hostile
                // peer envelope can carry the maximum.
                let hostile = json.replacingOccurrences(of: "[0,0]", with: "[9223372036854775807,18446744073709551615]")
                guard let event = try? JSONDecoder().decode(WorkoutEvent.self, from: Data(hostile.utf8)) else {
                    exit(3)
                }
                let log = [
                    EngineAdv.start(),
                    EngineAdv.env(event, EngineAdv.watch, seq: 1, at: 0),
                    EngineAdv.env(EngineAdv.extend(shown: true, tappedAt: 10), seq: 2, at: 10)
                ]
                _ = WorkoutEngine.replay(log)
            }
        }

        @Test("Extreme and non-finite dates (distant past/future, ±infinity) do not trap.")
        func extremeDates_doNotTrap() async {
            await #expect(processExitsWith: .success) {
                let dates = [
                    Date.distantPast,
                    .distantFuture,
                    Date(timeIntervalSinceReferenceDate: .infinity),
                    Date(timeIntervalSinceReferenceDate: -.infinity)
                ]
                var log = [EngineAdv.start()]
                for (offset, date) in dates.enumerated() {
                    let seq = UInt64(10 * offset + 2)
                    log += Self.envelopes(at: date, row: offset, firstSeq: seq)
                }
                log.append(EngineAdv.env(.finished(endedAt: .distantFuture), seq: 99, at: 1))
                _ = WorkoutEngine.replay(log)
                _ = EngineAdv.fold(log)
            }
        }

        @Test("A NaN weight or an astronomically large one does not trap, even through finish and its summary.")
        func oddWeights_doNotTrap() async {
            await #expect(processExitsWith: .success) {
                let weights = [
                    Weight(grams: .nan),
                    Weight(grams: .greatestFiniteMagnitude),
                    Weight(grams: -.greatestFiniteMagnitude)
                ]
                var log = [EngineAdv.start()]
                for (offset, weight) in weights.enumerated() {
                    log.append(EngineAdv.env(
                        .setLogged(
                            exerciseIndex: 0,
                            setID: EngineAdv.sid(0, offset),
                            weight: weight,
                            reps: Reps(clamping: Int.max),
                            doneAt: engineTime(1)
                        ),
                        seq: UInt64(offset + 2), at: Double(offset + 1)
                    ))
                }
                log.append(EngineAdv.env(
                    .allSetsRepeated(exerciseIndex: 1, weight: Weight(grams: .nan), reps: Reps.one),
                    seq: 20,
                    at: 20
                ))
                log.append(EngineAdv.env(.finished(endedAt: engineTime(30)), seq: 21, at: 30))
                _ = EngineAdv.fold(log)
            }
        }

        @Test("seq = UInt64.max and Int.max/Int.min indices do not trap.")
        func extremeSeqAndIndices_doNotTrap() async {
            await #expect(processExitsWith: .success) {
                var log = [EngineAdv.start()]
                for (offset, index) in [Int.max, Int.min, Int.max - 1, Int.min + 1].enumerated() {
                    let seq = UInt64.max - UInt64(offset * 3)
                    log += [
                        EngineAdv.env(
                            .exerciseSelected(exerciseIndex: index, setIndex: index),
                            EngineAdv.watch,
                            seq: seq,
                            at: 1
                        ),
                        EngineAdv.env(
                            .exerciseSelected(exerciseIndex: 0, setIndex: index),
                            EngineAdv.watch,
                            seq: seq - 1,
                            at: 1
                        ),
                        EngineAdv.env(
                            .allSetsRepeated(exerciseIndex: index, weight: .zero, reps: Reps.one),
                            EngineAdv.watch,
                            seq: seq - 2,
                            at: 1
                        )
                    ]
                }
                _ = WorkoutEngine.replay(log)
                _ = EngineAdv.fold(log)
            }
        }
    }
#endif
