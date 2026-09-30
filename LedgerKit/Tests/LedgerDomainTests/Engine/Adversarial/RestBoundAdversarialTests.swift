import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: the fix round's clamps (`WorkoutEngine.longestRest`, the saturating "+30s" sum, the
/// saturating `elapsed`). Realistic values must pass through unchanged; hostile ones must stay bounded.
@Suite("WorkoutEngine · rest and elapsed bounds (adversarial, round 2)", .tags(.domain))
struct RestBoundAdversarialTests {
    typealias Adv = EngineAdv

    static let hour = WorkoutEngine.longestRest

    /// The rest after one `restStarted` stamped at 10 s.
    static func rest(endsAt seconds: Double, total: Duration) -> RestTimer? {
        Adv.state(after: [
            Adv.start(),
            Adv.env(.restStarted(endsAt: engineTime(seconds), total: total), seq: 2, at: 10)
        ])?.rest
    }

    /// `count` watch "+30s" taps, `spacing` seconds apart from `first` seconds, each on a rest the watch
    /// shows running (every caller taps before the rest's end).
    static func taps(_ count: Int, from first: Double, spacing: Double) -> [EventEnvelope] {
        (0 ..< count).map { index in
            let seconds = first + spacing * Double(index)
            return Adv.env(Adv.extend(shown: true, tappedAt: seconds), Adv.watch, seq: UInt64(index + 1), at: seconds)
        }
    }

    @Test(
        "Realistic rests of 1–10 min, grown by ten +30s taps, pass through the one-hour bound unchanged",
        arguments: [60, 90, 150, 300, 450, 600]
    )
    func realisticRests_areUntouched(seconds: Int) throws {
        let total = Duration.seconds(seconds)
        let started = Adv.env(.restStarted(endsAt: engineTime(10 + Double(seconds)), total: total), seq: 2, at: 10)
        let log = [Adv.start(), started] + Self.taps(10, from: 12, spacing: 3)
        let (state, effects) = Adv.fold(log)
        let rest = try #require(state?.rest)
        #expect(rest == RestTimer(endsAt: engineTime(10 + Double(seconds) + 300), total: total + .seconds(300)))
        #expect(effects.last?.contains(.scheduleRestNotification(endsAt: rest.endsAt)) == true)
        #expect(WorkoutEngine.replay(log) == state)
    }

    @Test("An automatic 300 s rest reaches exactly one hour after 110 taps; the 111th grows endsAt but not total")
    func autoRest_tapsUpToTheBound() throws {
        let session = EventBuilders.session([Adv.spec("Squat", sets: 3, rest: 300)])
        let log = Adv.env(Adv.logged(0, 0, doneAt: 100), seq: 2, at: 100)
        let taps = Self.taps(111, from: 101, spacing: 1)
        let atBound = try #require(Adv.state(after: [Adv.start(session), log] + taps.dropLast()))
        #expect(atBound.rest == RestTimer(endsAt: engineTime(3700), total: Self.hour))
        // The ring's scale is pinned at an hour; the countdown still grows (at 211 s it is 3,519 s ≤ an hour).
        let past = try #require(Adv.state(after: [Adv.start(session), log] + taps))
        #expect(past.rest == RestTimer(endsAt: engineTime(3730), total: Self.hour))
        #expect(past.rest.map { $0.fraction(at: engineTime(211)) <= 1 } == true)
    }

    @Test("Taps faster than the countdown runs: endsAt stops at one hour after the latest tap")
    func rapidTaps_endsAtHeldToAnHourAfterTheTap() throws {
        let session = EventBuilders.session([Adv.spec("Squat", sets: 3, rest: 300)])
        let log = Adv.env(Adv.logged(0, 0, doneAt: 100), seq: 2, at: 100)
        // 130 taps within 13 s: 300 + 3,900 s asked for.
        let taps = Self.taps(130, from: 100, spacing: 0.125)
        let rest = try #require(Adv.state(after: [Adv.start(session), log] + taps)?.rest)
        #expect(rest.total == Self.hour)
        #expect(rest.endsAt == engineTime(100 + 0.125 * 129).addingTimeInterval(3600))
    }

    /// Retargeted in fix round 2 (orchestrator decision A: reject, not clamp). A length outside
    /// `0 ... longestRest` makes the envelope malformed, so it is ignored: no rest, where round 1 clamped.
    @Test("The bound's edges: one hour and zero are kept; one attosecond beyond either makes the envelope ignored")
    func bound_edges() {
        #expect(Self.rest(endsAt: 3610, total: Self.hour) == RestTimer(endsAt: engineTime(3610), total: Self.hour))
        #expect(Self.rest(endsAt: 3610.5, total: Self.hour + Duration(attoseconds: 1)) == nil)
        #expect(Self.rest(endsAt: 10, total: .zero) == RestTimer(endsAt: engineTime(10), total: .zero))
        #expect(Self.rest(endsAt: 5, total: Duration(attoseconds: -1)) == nil)
        #expect(Self.rest(endsAt: 3610, total: Duration(attoseconds: .max)) == nil)
        #expect(Self.rest(endsAt: 3610, total: Duration(attoseconds: .min)) == nil)
        // A rest that is already over when its envelope is stamped is kept as it is (rule 9: views derive "over").
        #expect(Self.rest(endsAt: -50, total: .seconds(60)) == RestTimer(endsAt: engineTime(-50), total: .seconds(60)))
    }

    /// Retargeted in fix round 2 (orchestrator decisions A and B): a negative +N is malformed and
    /// ignored, where round 1 applied rule 9's arithmetic; the watch decides "shown" from its screen.
    @Test("Zero +N follows rule 9's arithmetic; a negative +N is malformed and leaves the rest as it was")
    func zeroAndNegativeExtensions() {
        let resting = [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)]
        func after(_ amount: Duration, at seconds: Double = 20) -> RestTimer? {
            let shown = Adv.state(after: resting)
            let tap = Adv.env(Adv.extend(amount, on: shown, at: seconds), Adv.watch, seq: 1, at: seconds)
            return Adv.state(after: resting + [tap])?.rest
        }
        let untouched = RestTimer(endsAt: engineTime(160), total: .seconds(150))
        #expect(after(.zero) == untouched)
        #expect(after(.seconds(-60)) == untouched)
        #expect(after(.seconds(-200)) == untouched)
        // No rest shown (rule 9, decision #7): a fresh rest of `amount` from the tap.
        #expect(after(.zero, at: 200) == RestTimer(endsAt: engineTime(200), total: .zero))
        #expect(after(.seconds(-30), at: 200) == untouched)
    }

    @Test("A three-hour workout's elapsed time and receipt are exact; the saturation only starts near 2^63 s")
    func elapsed_realisticAndSaturated() throws {
        let finish = Adv.env(.finished(endedAt: engineTime(10800.25)), seq: 2, at: 10800.25)
        let live = try #require(Adv.state(after: [Adv.start()]))
        #expect(live.elapsed(at: engineTime(5400)) == .seconds(5400))
        #expect(live.elapsed(at: engineTime(-1)) == .zero)
        let ended = try #require(Adv.state(after: [Adv.start(), finish]))
        #expect(ended.elapsed(at: engineTime(99999)) == .milliseconds(10_800_250))
        #expect(WorkoutEngine.summary(ended, prs: []).elapsed == .milliseconds(10_800_250))
        let cap = Duration.seconds(Double(Int64.max))
        let beyond = Date(timeIntervalSinceReferenceDate: 1e19)
        #expect(live.elapsed(at: beyond) == cap)
        #expect(live.elapsed(at: Date(timeIntervalSinceReferenceDate: .infinity)) == cap)
        #expect(live.elapsed(at: Date(timeIntervalSinceReferenceDate: 1e18)) < cap)
    }
}

// MARK: - Finding 9: absurd and non-finite dates escape the bound

extension RestBoundAdversarialTests {
    /// A date whose JSON form (`123456789`) is unique in an encoded event.
    static let marker = Date(timeIntervalSinceReferenceDate: 123_456_789)

    /// `value` encoded to JSON with every `marker` date replaced by the JSON number `literal`, then
    /// decoded: what a peer's corrupt envelope can carry through the default `JSONDecoder`.
    static func decoded<Value: Codable>(_ value: Value, markerAs literal: String) throws -> Value {
        let json = try #require(String(data: JSONEncoder().encode(value), encoding: .utf8))
        #expect(json.contains("123456789"))
        let hostile = json.replacingOccurrences(of: "123456789", with: literal)
        return try JSONDecoder().decode(Value.self, from: Data(hostile.utf8))
    }

    // Retargeted in fix round 2 (orchestrator decision A), and again in the final fix round (decision 2,
    // no time windows). Finding 9's fix direction named two options: hold every payload date to its
    // envelope, or saturate the ring. Pete chose the second: a finite date, however absurd, is accepted, and
    // the ring saturates (the exit twins below); only a non-finite date is malformed. Each test keeps its
    // input and its question ("can this date reach the rest ring or break ==?").

    /// The ring at 30 s on a rest ending near 1e21: pinned at its cap, full, and equal to itself.
    static func expectSaturated(_ rest: RestTimer?) {
        #expect(rest?.remaining(at: engineTime(30)) == .seconds(Double(Int64.max)))
        #expect(rest?.fraction(at: engineTime(30)) == 1)
        #expect(rest == rest)
    }

    @Test("Finding 9: a JSON setLogged with doneAt 1e21 is kept; its automatic rest reaches the ring, which saturates")
    func autoRest_absurdDoneAt_saturatesTheRing() throws {
        let event = try Self.decoded(
            WorkoutEvent.setLogged(
                exerciseIndex: 0, setID: Adv.sid(0, 0), weight: pounds("185"), reps: Reps(clamping: 5),
                doneAt: Self.marker
            ),
            markerAs: "1e21"
        )
        let hostile = Adv.env(event, Adv.watch, seq: 1, at: 20)
        #expect(hostile.isWellFormed)
        let state = try #require(Adv.state(after: [Adv.start(), hostile]))
        let far = Date(timeIntervalSinceReferenceDate: 1e21)
        #expect(state.rest == RestTimer(endsAt: far.addingTimeInterval(150), total: .seconds(150)))
        #expect(Adv.row(state, 0, 0)?.doneAt == far)
        Self.expectSaturated(state.rest)
        #expect(WorkoutEngine.replay([Adv.start(), hostile]) == state)
    }

    @Test("Finding 9: a JSON started snapshot whose rest ends at 1e21 starts the workout; the ring saturates")
    func snapshotRest_absurdEndsAt_saturatesTheRing() throws {
        var snapshot = EventBuilders.seedSession()
        snapshot.rest = RestTimer(endsAt: Self.marker, total: .seconds(60))
        let hostile = try Self.decoded(snapshot, markerAs: "1e21")
        #expect(Adv.start(hostile).isWellFormed)
        let state = try #require(Adv.state(after: [Adv.start(hostile)]))
        #expect(state.rest?.endsAt == Date(timeIntervalSinceReferenceDate: 1e21))
        Self.expectSaturated(state.rest)
        // The first usable started still picks the workout, as any well-formed one does.
        let peer = Adv.start(EventBuilders.seedSession(), Adv.watch, seq: 1, at: 1)
        #expect(WorkoutEngine.replay([Adv.start(hostile), peer]) == state)
    }

    @Test("Finding 9: a binary-plist restStarted whose endsAt is NaN is malformed: ignored, and replay stays Equatable")
    func nanEndsAt_isIgnored_andStateEqualsItself() throws {
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let wire = try encoder.encode(WorkoutEvent.restStarted(endsAt: nan, total: .seconds(90)))
        let event = try PropertyListDecoder().decode(WorkoutEvent.self, from: wire)
        let log = [Adv.start(), Adv.env(event, Adv.watch, seq: 1, at: 10)]
        let state = try #require(WorkoutEngine.replay(log))
        #expect(state.rest == nil, "NaN passed min() in round 1 and reached the state")
        #expect(state == WorkoutEngine.replay([Adv.start()]))
        let equal = WorkoutEngine.replay(log) == WorkoutEngine.replay(log)
        #expect(equal, "a NaN date makes the replayed state unequal to itself")
    }
}

#if os(macOS)
    extension RestBoundAdversarialTests {
        @Test("Finding 9 (exit): the rest ring's remaining time on a JSON doneAt of 1e21 does not trap")
        func autoRest_absurdDoneAt_remainingDoesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let template = WorkoutEvent.setLogged(
                    exerciseIndex: 0, setID: EngineAdv.sid(0, 0), weight: .pounds(185), reps: Reps(clamping: 5),
                    doneAt: Date(timeIntervalSinceReferenceDate: 123_456_789)
                )
                guard let data = try? JSONEncoder().encode(template),
                      let text = String(data: data, encoding: .utf8),
                      let event = try? JSONDecoder().decode(
                          WorkoutEvent.self,
                          from: Data(text.replacingOccurrences(of: "123456789", with: "1e21").utf8)
                      )
                else {
                    exit(2)
                }
                let state = EngineAdv.state(after: [EngineAdv.start(), EngineAdv.env(event, seq: 2, at: 20)])
                _ = state?.rest?.remaining(at: engineTime(30))
                // Round 2: also hand the decoded date to the ring directly, as any other decoder of a
                // RestTimer could (decision A, defence in depth).
                guard case let .setLogged(_, _, _, _, doneAt) = event else {
                    exit(4)
                }
                let ring = RestTimer(endsAt: doneAt.addingTimeInterval(150), total: .seconds(150))
                _ = (ring.remaining(at: engineTime(30)), ring.fraction(at: engineTime(30)))
            }
        }

        @Test("Finding 9 (exit): a JSON started snapshot resting until 1e21 does not trap the rest ring")
        func snapshotRest_absurdEndsAt_remainingDoesNotTrap() async {
            await #expect(processExitsWith: .success) {
                var snapshot = EventBuilders.seedSession()
                snapshot.rest = RestTimer(
                    endsAt: Date(timeIntervalSinceReferenceDate: 123_456_789),
                    total: .seconds(60)
                )
                guard let data = try? JSONEncoder().encode(snapshot),
                      let text = String(data: data, encoding: .utf8),
                      let hostile = try? JSONDecoder().decode(
                          WorkoutState.self,
                          from: Data(text.replacingOccurrences(of: "123456789", with: "1e21").utf8)
                      )
                else {
                    exit(2)
                }
                _ = EngineAdv.state(after: [EngineAdv.start(hostile)])?.rest?.fraction(at: engineTime(30))
                // Round 2: also run the ring on the decoded rest directly.
                _ = (hostile.rest?.remaining(at: engineTime(30)), hostile.rest?.fraction(at: engineTime(30)))
            }
        }
    }
#endif
