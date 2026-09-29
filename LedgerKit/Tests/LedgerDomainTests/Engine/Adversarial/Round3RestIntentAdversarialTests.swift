import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3 (G2 after fix round 2): `restExtended(amount:extendsShownRest:tappedAt:)` (decision B) under
/// races between phone and watch. Each case replays every arrival order, and states what the lifter sees.
@Suite("WorkoutEngine · +30s intent under races (adversarial, round 3)", .tags(.domain))
struct Round3RestIntentAdversarialTests {
    typealias Adv = EngineAdv

    /// The phone logs bench set 1 at 10 s: an automatic 150 s rest, ending at 160 s.
    static let resting = [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)]

    /// The rest after replaying `base` plus `racing` in every order, which must all agree.
    static func rest(_ racing: [EventEnvelope], base: [EventEnvelope] = resting) -> RestTimer? {
        let orders = racing.count == 2 ? [racing, racing.reversed()] : [racing]
        let states = orders.map { WorkoutEngine.replay(base + $0) }
        #expect(Set(states.map { $0?.rest }).count == 1, "arrival order changed the rest")
        var replica = Replica(base)
        for envelope in racing.reversed() {
            replica.receive(envelope)
        }
        #expect(replica.state == states[0], "a device reducing or rebuilding disagrees with replay")
        return states[0]?.rest
    }

    @Test("Held: both devices tap +30s on the rest they see; both count, whatever arrives first")
    func bothExtend_bothCount() {
        let phone = Adv.env(Adv.extend(shown: true, tappedAt: 100), seq: 3, at: 100)
        let watch = Adv.env(Adv.extend(shown: true, tappedAt: 101), Adv.watch, seq: 1, at: 101)
        #expect(Self.rest([phone, watch]) == RestTimer(endsAt: engineTime(220), total: .seconds(210)))
    }

    @Test(
        """
        Held: the phone skips while the watch taps +30s. Skip first: the watch's tap, meant for a running rest, \
        starts a fresh 30 s rest at the tap. +30s first: the skip ends it. Every device agrees
        """
    )
    func skipAndExtend_race() {
        let skip = Adv.env(.restSkipped, seq: 3, at: 100)
        let extend = Adv.env(Adv.extend(shown: true, tappedAt: 101), Adv.watch, seq: 1, at: 101)
        #expect(Self.rest([skip, extend]) == RestTimer(endsAt: engineTime(131), total: .seconds(30)))
        let early = Adv.env(Adv.extend(shown: true, tappedAt: 99), Adv.watch, seq: 1, at: 99)
        #expect(Self.rest([skip, early]) == nil)
    }

    @Test(
        """
        Held: the watch taps +30s on the rest after set 1 while the phone, unseen, logs set 2 and replaces it; \
        the +30s lands on set 2's rest, the rest now running
        """
    )
    func extendAfterReplace_growsTheCurrentRest() {
        let second = Adv.env(Adv.logged(0, 1, doneAt: 120), seq: 3, at: 120)
        let extend = Adv.env(Adv.extend(shown: true, tappedAt: 125), Adv.watch, seq: 1, at: 125)
        #expect(Self.rest([second, extend]) == RestTimer(endsAt: engineTime(300), total: .seconds(180)))
    }

    @Test("Held (decision #7): +30s on a rest the device shows over starts a fresh 30 s rest at the tap")
    func extendAfterZero_startsFresh() {
        let extend = Adv.env(Adv.extend(shown: false, tappedAt: 170), Adv.watch, seq: 1, at: 170)
        #expect(Self.rest([extend]) == RestTimer(endsAt: engineTime(200), total: .seconds(30)))
    }

    @Test(
        """
        Finding 20 (documents): the watch has not yet heard the phone's set log, so it shows no rest and \
        its +30s starts a 30 s rest; stamped after the log, it replaces the phone's running 150 s rest, \
        and the rest the phone shows drops from 145 s to 30 s
        """
    )
    func unseenRest_plus30Shortens() {
        let tap = Adv.env(Adv.extend(shown: false, tappedAt: 15), Adv.watch, seq: 1, at: 15)
        let rest = Self.rest([tap])
        #expect(rest == RestTimer(endsAt: engineTime(45), total: .seconds(30)))
        #expect(rest?.remaining(at: engineTime(15)) == .seconds(30), "the phone showed 145 s left")
    }
}
