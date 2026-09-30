import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 4 (G2 close-out after the re-plan): `effects(from:to:)`'s one set haptic, and "+30s never shortens
/// a running rest", written from ADR-004 ("The clock rule", "The host loop") and the public API.
@Suite("WorkoutEngine · set haptic and +30s (adversarial, round 4)", .tags(.domain))
struct Round4EffectsRestAdversarialTests {
    typealias Adv = EngineAdv

    /// The spec, spelled out: one haptic when the new state is live and holds a done set whose ID was not
    /// done before, whatever else changed; none otherwise.
    static func expectedBuzzes(from old: WorkoutState?, to new: WorkoutState?) -> Int {
        guard let new, new.phase == .live, new != old else {
            return 0
        }
        var doneBefore = Set<SetID>()
        for exercise in old?.exercises ?? [] {
            for set in exercise.sets where set.doneAt != nil {
                doneBefore.insert(set.id)
            }
        }
        for exercise in new.exercises {
            for set in exercise.sets where set.doneAt != nil && !doneBefore.contains(set.id) {
                return 1
            }
        }
        return 0
    }

    static func buzzes(_ effects: [Effect]) -> (sets: Int, other: Int) {
        let sets = effects.count(where: { $0 == .haptic(.setLogged) })
        return (sets, effects.count(where: {
            if case .haptic = $0 {
                true
            } else {
                false
            }
        }) - sets)
    }

    /// What the rebuilds of one seeded session showed: how many broke the rule, and which cases they covered.
    struct HapticTally {
        var wrong = 0
        var other = 0
        var multiSet = 0
        var endedWithNewSets = 0
        var lostDoneSets = 0
        var rebuilds = 0
        var buzzed = 0
    }

    /// A seeded two-device log (`EngineScenario`, terminals included) delivered to one device in random,
    /// shuffled batches of 1–12; each batch is one rebuild.
    static func rebuilds(_ seed: PropertySeed) -> HapticTally {
        var generator = seed.generator
        var scenario = EngineScenario(
            devices: [Adv.phone, Adv.watch], snapshot: EngineGen.session(using: &generator), using: &generator
        )
        scenario.start()
        for _ in 0 ..< 40 {
            scenario.act(generator.chance(50) ? Adv.phone : Adv.watch, using: &generator)
            if generator.chance(25) {
                scenario.heal(using: &generator)
            }
        }
        var (delivered, state, tally) = ([EventEnvelope](), WorkoutState?.none, HapticTally())
        var pending = scenario.all.shuffled(using: &generator)
        while !pending.isEmpty {
            let size = Int.random(in: 1 ... min(12, pending.count), using: &generator)
            delivered += pending.prefix(size)
            pending.removeFirst(size)
            let next = WorkoutEngine.replay(delivered)
            let (sets, other) = Self.buzzes(WorkoutEngine.effects(from: state, to: next))
            tally.wrong += sets == Self.expectedBuzzes(from: state, to: next) ? 0 : 1
            tally.other += other
            tally.rebuilds += 1
            tally.buzzed += sets
            let (before, after) = (state?.doneSets ?? 0, next?.doneSets ?? 0)
            tally.multiSet += next?.phase == .live && after >= before + 2 ? 1 : 0
            tally.endedWithNewSets += next?.phase != .live && after > before ? 1 : 0
            tally.lostDoneSets += after < before ? 1 : 0
            state = next
        }
        return tally
    }

    @Test(
        """
        Property: seeded two-device logs delivered in random batches; each rebuild plays exactly one set \
        haptic when it shows at least one newly done set while live, none otherwise (ended, un-logs, re-logs), \
        and never another haptic
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func setHaptic_exactlyOncePerRebuildWithANewlyDoneSet(seed: PropertySeed) {
        let tally = Self.rebuilds(seed)
        #expect(tally.wrong == 0 && tally.other == 0, "\(tally.wrong) wrong set haptics, \(tally.other) others")
    }

    @Test("The property has teeth: its rebuilds bring several sets at once, end with new sets, and lose done sets")
    func setHaptic_propertyCoversEveryCase() {
        var total = HapticTally()
        for seed in PropertySeed.all.prefix(100) {
            let tally = Self.rebuilds(seed)
            total.multiSet += tally.multiSet
            total.endedWithNewSets += tally.endedWithNewSets
            total.lostDoneSets += tally.lostDoneSets
        }
        #expect(total.multiSet > 0 && total.endedWithNewSets > 0 && total.lostDoneSets > 0, "\(total)")
    }
}

// MARK: - The set haptic, by case, and the launch

extension Round4EffectsRestAdversarialTests {
    @Test(
        """
        The haptic, by case: one for five remote sets, one when a set is logged and another un-logged, none \
        for an un-log alone, a re-log, a finish or discard that brings sets, or a rebuild that changes nothing
        """
    )
    func setHaptic_byCase() {
        let start = Adv.start()
        let log = (0 ..< 5).map { Adv.env(
            Adv.logged(0, $0, doneAt: Double(10 * ($0 + 1))),
            Adv.watch,
            seq: UInt64($0 + 1),
            at: Double(10 * ($0 + 1))
        ) }
        let live = WorkoutEngine.replay([start])
        let five = WorkoutEngine.replay([start] + log)
        #expect(Self.buzzes(WorkoutEngine.effects(from: live, to: five)).sets == 1)
        let unlog = Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), seq: 2, at: 60)
        let another = Adv.env(Adv.logged(1, 0, doneAt: 61), seq: 3, at: 61)
        #expect(Self.buzzes(WorkoutEngine.effects(from: five, to: WorkoutEngine.replay([start, unlog] + log)))
            .sets == 0)
        let swapped = WorkoutEngine.replay([start, unlog, another] + log)
        #expect(Self.buzzes(WorkoutEngine.effects(from: five, to: swapped)).sets == 1)
        let relog = Adv.env(Adv.logged(0, 0, pounds: "190", doneAt: 70), seq: 4, at: 70)
        #expect(
            Self.buzzes(WorkoutEngine.effects(
                from: swapped,
                to: WorkoutEngine.replay([start, unlog, another, relog] + log)
            )).sets == 1,
            "the re-log after the un-log is newly done"
        )
        for terminal in [WorkoutEvent.finished(endedAt: engineTime(90)), .discarded(endedAt: engineTime(90))] {
            let ended = WorkoutEngine.replay([start, Adv.env(terminal, seq: 2, at: 90)] + log)
            #expect(Self.buzzes(WorkoutEngine.effects(from: live, to: ended)) == (0, 0))
            #expect(Self.buzzes(WorkoutEngine.effects(from: nil, to: ended)) == (0, 0))
        }
        #expect(WorkoutEngine.effects(from: five, to: five).isEmpty)
    }

    @Test(
        """
        The launch step is not a rebuild (documents): effects(from: nil, to:) of a resumed live log would buzz \
        for sets logged before the kill, so the launch plays nothing; both host models' relaunches play nothing
        """
    )
    func launch_isNotARebuild() async throws {
        let log = [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)]
        let resumed = WorkoutEngine.replay(log)
        #expect(Self.buzzes(WorkoutEngine.effects(from: nil, to: resumed)).sets == 1)
        var literal = LiteralHost(Adv.phone, offset: 0)
        try await literal.receive(log)
        #expect(literal.haptics[.rebuild] == 1)
        try await literal.relaunch()
        #expect(literal.haptics[.rebuild] == 1 && literal.state == resumed, "the relaunch buzzed")
        var sim = SimHost(Adv.phone, offset: 0)
        try await sim.receive(log)
        await sim.relaunch()
        #expect(sim.remoteHaptics == 1 && sim.state == resumed)
    }
}

// MARK: - "+30s" never shortens a running rest

extension Round4EffectsRestAdversarialTests {
    /// The rest in the state when "+30s" lands, relative to the tap at 1,000 s.
    enum Prior: CustomStringConvertible {
        case absent
        case running(left: Double, total: Int)
        case expired(ago: Double)

        var description: String {
            switch self {
            case .absent: "absent"
            case let .running(left, total): "running, \(left) s of \(total) s left"
            case let .expired(ago): "expired \(ago) s ago"
            }
        }
    }

    static let priors: [Prior] = [
        .absent,
        .expired(ago: 0),
        .expired(ago: 0.001),
        .expired(ago: 45),
        .expired(ago: 3600)
    ]
        + [0.001, 1, 29, 29.999, 30, 30.001, 31, 145, 300, 3569, 3570, 3570.001, 3600, 3600.001, 3630].flatMap { left in
            [30, 150, 3600].map { Prior.running(left: left, total: $0) }
        }

    @Test(
        """
        Decision 4, both modes, against an absent, expired or running rest: after "+30s" a rest runs past the \
        tap (shown on an expired rest, it extends that rest as given), and a running rest never ends earlier; \
        the one exception is the shown mode's one-hour cap, which binds only with more than an hour left
        """
    )
    func plus30_neverShortensARunningRest() throws {
        var capped: [String] = []
        for prior in Self.priors {
            capped += try [true, false].filter { try Self.plus30(on: prior, shown: $0) }.map { "\(prior), shown \($0)" }
        }
        #expect(capped.count == 6, "the cap bound in \(capped)")
    }

    /// "+30s" tapped at 1,000 s on the seed session holding `prior`; `true` when the shown mode's one-hour cap
    /// ended a running rest earlier.
    static func plus30(on prior: Prior, shown: Bool) throws -> Bool {
        let tap = 1000.0
        var log = [Adv.start()]
        switch prior {
        case .absent:
            break
        case let .running(left, total):
            log.append(Adv.env(.restStarted(endsAt: engineTime(tap + left), total: .seconds(total)), seq: 2, at: 900))
        case let .expired(ago):
            log.append(Adv.env(.restStarted(endsAt: engineTime(tap - ago), total: .seconds(90)), seq: 2, at: 900))
        }
        let before = try #require(WorkoutEngine.replay(log))
        let plus = Adv.env(Adv.extend(shown: shown, tappedAt: tap), Adv.watch, seq: 1, at: tap)
        let (after, effects) = WorkoutEngine.reduce(before, plus)
        let rest = try #require(after?.rest, "\(prior), shown \(shown): no rest after +30s")
        #expect(after == WorkoutEngine.replay(log + [plus]))
        #expect(effects.starts(with: [.persist(plus), .transmit(plus)]))
        switch prior {
        case let .expired(ago) where shown:
            // The device showed a rest running, so the state's rest is not the one it showed (a peer replaced
            // it): extended as given (decision B), not the re-plan's change.
            #expect(rest.endsAt == engineTime(tap - ago).addingTimeInterval(30))
        case let .running(left, _):
            let old = engineTime(tap + left)
            #expect(rest.endsAt > engineTime(tap))
            if !shown {
                #expect(rest.endsAt == max(old, engineTime(tap + 30)), "\(prior), unshown")
            } else if rest.endsAt < old {
                #expect(left > 3600 && rest.endsAt == engineTime(tap + 3600), "\(prior)")
                return true
            }
        default:
            #expect(rest.endsAt == engineTime(tap + 30), "\(prior), shown \(shown)")
        }
        return false
    }
}
