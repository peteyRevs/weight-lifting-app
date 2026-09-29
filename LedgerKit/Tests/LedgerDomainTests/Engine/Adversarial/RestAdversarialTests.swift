import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Rule 9, criterion 5 and decision #7, attacked: extend twice, extend at and after zero, skip with
/// nothing running, and a manual rest overtaken by an auto rest.
@Suite("WorkoutEngine · rest (adversarial)", .tags(.domain))
struct RestAdversarialTests {
    typealias Adv = EngineAdv

    /// A live seed session with a 90 s rest started at t = 0 (ends at t = 90).
    static func resting() -> WorkoutState? {
        Adv.state(after: [
            Adv.start(),
            Adv.env(.restStarted(endsAt: engineTime(90), total: .seconds(90)), seq: 2, at: 0)
        ])
    }

    static func extend(
        _ state: WorkoutState?,
        at seconds: Double,
        seq: UInt64,
        by amount: Int = 30
    ) -> (WorkoutState?, [Effect]) {
        WorkoutEngine.reduce(state, Adv.env(.restExtended(amount: .seconds(amount)), Adv.watch, seq: seq, at: seconds))
    }

    @Test("Criterion 5: no rest running, +30 s at t → RestTimer(endsAt: t + 30 s, total: 30 s).")
    func criterion5_extendWithNoRest() {
        let (state, _) = Self.extend(Adv.state(after: [Adv.start()]), at: 42, seq: 1)
        #expect(state?.rest == RestTimer(endsAt: engineTime(72), total: .seconds(30)))
    }

    @Test("Rule 9 / rule 23: extending twice adds to both endsAt and total each time.")
    func extendTwice_accumulates() {
        var state = Self.resting()
        state = Self.extend(state, at: 10, seq: 1).0
        state = Self.extend(state, at: 20, seq: 2).0
        #expect(state?.rest == RestTimer(endsAt: engineTime(150), total: .seconds(150)))
    }

    @Test("Decision #7: +30 s after the rest reached zero restarts a fresh 30 s rest from the envelope's time.")
    func extendAfterExpiry_restarts() {
        let (state, _) = Self.extend(Self.resting(), at: 100, seq: 1)
        #expect(state?.rest == RestTimer(endsAt: engineTime(130), total: .seconds(30)))
    }

    @Test("Decision #7 boundary: rest is over when endsAt <= now, so +30 s exactly at zero restarts.")
    func extendExactlyAtZero_restarts() {
        let (state, _) = Self.extend(Self.resting(), at: 90, seq: 1)
        #expect(state?.rest == RestTimer(endsAt: engineTime(120), total: .seconds(30)))
    }

    @Test("Decision #7 boundary: 1 ms before zero the rest is still running, so +30 s extends it.")
    func extendJustBeforeZero_extends() {
        let (state, _) = Self.extend(Self.resting(), at: 89.999, seq: 1)
        #expect(state?.rest == RestTimer(endsAt: engineTime(120), total: .seconds(120)))
    }

    @Test("Rule 9: +30 s after a skip starts a fresh rest.")
    func extendAfterSkip_restarts() {
        var state = Self.resting()
        state = WorkoutEngine.reduce(state, Adv.env(.restSkipped, seq: 3, at: 10)).0
        state = Self.extend(state, at: 20, seq: 1).0
        #expect(state?.rest == RestTimer(endsAt: engineTime(50), total: .seconds(30)))
    }

    @Test("Rule 9: skip with no rest running changes nothing, schedules nothing, buzzes nothing.")
    func skipWithNoRest_isHarmless() {
        let live = Adv.state(after: [Adv.start()])
        let (state, effects) = WorkoutEngine.reduce(live, Adv.env(.restSkipped, seq: 2, at: 5))
        #expect(state == live)
        #expect(!effects.contains(.updateLiveActivity))
        #expect(!Adv.buzzes(effects))
    }

    @Test("Rule 9: skip clears a running rest and cancels its notification.")
    func skip_clearsAndCancels() {
        let (state, effects) = WorkoutEngine.reduce(Self.resting(), Adv.env(.restSkipped, Adv.watch, seq: 1, at: 5))
        #expect(state?.rest == nil)
        #expect(effects.contains(.cancelRestNotification))
    }

    @Test("Rule 9: extending moves the rest-over notification to the new endsAt (else it fires at the old zero).")
    func extend_reschedulesNotification() {
        let (state, effects) = Self.extend(Self.resting(), at: 10, seq: 1)
        #expect(state?.rest?.endsAt == engineTime(120))
        #expect(effects.contains(.scheduleRestNotification(endsAt: engineTime(120))), "effects: \(effects)")
    }

    @Test("Rule 9: a restart via +30 s at zero schedules the new notification.")
    func extendRestart_schedulesNotification() {
        let (_, effects) = Self.extend(Self.resting(), at: 100, seq: 1)
        #expect(effects.contains(.scheduleRestNotification(endsAt: engineTime(130))), "effects: \(effects)")
    }

    @Test("Rule 9: restStarted stores the absolute endsAt and total and schedules the notification.")
    func restStarted_setsAndSchedules() {
        let (state, effects) = WorkoutEngine.reduce(
            Adv.state(after: [Adv.start()]),
            Adv.env(.restStarted(endsAt: engineTime(75), total: .seconds(60)), Adv.watch, seq: 1, at: 15)
        )
        #expect(state?.rest == RestTimer(endsAt: engineTime(75), total: .seconds(60)))
        #expect(effects.contains(.scheduleRestNotification(endsAt: engineTime(75))))
    }

    @Test("Rule 3a: a manual rest is replaced by the auto rest of a later last-of-round set.")
    func manualRest_overtakenByAutoRest() {
        let (state, _) = WorkoutEngine.reduce(Self.resting(), Adv.env(Adv.logged(0, 0, doneAt: 30), seq: 3, at: 30))
        #expect(state?.rest == RestTimer(endsAt: engineTime(180), total: .seconds(150)))
    }

    @Test("Rule 3a: a manual rest survives a later set that is not last of its round.")
    func manualRest_survivesNonLastMember() {
        let start = Adv.start(EventBuilders.session(EventBuilders.supersetExercises))
        let state = Adv.state(after: [
            start,
            Adv.env(.restStarted(endsAt: engineTime(300), total: .seconds(300)), seq: 2, at: 0),
            Adv.env(Adv.logged(0, 0, pounds: "55", reps: 10, doneAt: 30), seq: 3, at: 30)
        ])
        #expect(state?.rest == RestTimer(endsAt: engineTime(300), total: .seconds(300)))
    }

    @Test("Rule 3a: with auto-rest off, a later set leaves a manual rest untouched.")
    func manualRest_autoRestOff() {
        let state = Adv.state(after: [
            Adv.start(EventBuilders.seedSession(autoRest: false)),
            Adv.env(.restStarted(endsAt: engineTime(300), total: .seconds(300)), seq: 2, at: 0),
            Adv.env(Adv.logged(0, 0, doneAt: 30), seq: 3, at: 30)
        ])
        #expect(state?.rest == RestTimer(endsAt: engineTime(300), total: .seconds(300)))
    }

    @Test("Rule 12: two devices extending concurrently both count, whatever the arrival order.")
    func concurrentExtends_bothCount() {
        let base = [Adv.start(), Adv.env(.restStarted(endsAt: engineTime(90), total: .seconds(90)), seq: 2, at: 0)]
        let phone = Adv.env(.restExtended(amount: .seconds(30)), Adv.phone, seq: 3, at: 10)
        let watch = Adv.env(.restExtended(amount: .seconds(30)), Adv.watch, seq: 1, at: 10)
        let expected = RestTimer(endsAt: engineTime(150), total: .seconds(150))
        #expect(WorkoutEngine.replay(base + [phone, watch])?.rest == expected)
        #expect(Replica(base + [watch, phone]).state?.rest == expected)
        #expect(Replica(base + [phone, watch, watch, phone]).state?.rest == expected)
    }
}
