import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3: a seeded session of 2–3 `LiteralHost`s. Clocks are skewed by up to ±30 s and step back by up
/// to 30 s; links are cut and healed; a device is killed and relaunched; each delivery is a random subset of
/// what is pending (a lost message that a later resend brings), sometimes shuffled, sometimes with a copy
/// of something already delivered. Every device sends only its own envelopes (ADR-004 rule 4).
struct Round3Scenario {
    private(set) var hosts: [LiteralHost]
    private(set) var real: Double = 0
    private var cut: Set<[Int]> = []
    /// `delivered[sender][peer]`: the keys of `sender`'s envelopes that `peer` has been handed.
    private var delivered: [[Set<EnvelopeKey>]]

    init(using generator: inout SeededGenerator) {
        let devices = [EngineAdv.phone, EngineAdv.watch, EngineAdv.tablet]
        let count = Int.random(in: 2 ... 3, using: &generator)
        hosts = devices.prefix(count).map { device in
            LiteralHost(device, offset: Double(Int.random(in: -30000 ... 30000, using: &generator)) / 1000)
        }
        delivered = Array(repeating: Array(repeating: [], count: count), count: count)
    }

    /// Every envelope any device sent.
    var everything: [EventEnvelope] {
        hosts.flatMap(\.outbox)
    }

    static func run(seed: PropertySeed, steps: Int = 40) async throws -> Round3Scenario {
        var generator = seed.generator
        var scenario = Round3Scenario(using: &generator)
        try await scenario.hosts[0].create(.started(EngineGen.session(using: &generator)), real: 0)
        try await scenario.deliver(using: &generator)
        for step in 0 ..< steps {
            try await scenario.perturb(using: &generator)
            try await scenario.act(late: step >= steps - 3, using: &generator)
            try await scenario.deliver(using: &generator)
        }
        scenario.cut = []
        try await scenario.deliver(all: true, using: &generator)
        return scenario
    }

    private mutating func perturb(using generator: inout SeededGenerator) async throws {
        real += Double(Int.random(in: 1 ... 40, using: &generator))
        let index = Int.random(in: hosts.indices, using: &generator)
        if generator.chance(15) {
            let other = (index + Int.random(in: 1 ..< hosts.count, using: &generator)) % hosts.count
            let link = [index, other]
            if cut.remove(link) == nil {
                cut.insert(link)
            }
        }
        if generator.chance(5) {
            hosts[index].offset -= Double(Int.random(in: 1 ... 30, using: &generator))
        }
        if generator.chance(4) {
            try await hosts[index].relaunch()
        }
    }

    /// A lifter action on a random device that shows a live workout. Terminals only in the last steps.
    private mutating func act(late: Bool, using generator: inout SeededGenerator) async throws {
        let index = Int.random(in: hosts.indices, using: &generator)
        guard let view = hosts[index].state, view.phase == .live else {
            return
        }
        let now = hosts[index].now(real)
        var event = EngineGen.intent(for: view, at: now, sharedAddIDs: [], using: &generator)
        switch event {
        case .finished, .discarded:
            event = late ? event : .restSkipped
        default:
            break
        }
        try await hosts[index].create(event, real: real)
    }

    private mutating func deliver(all: Bool = false, using generator: inout SeededGenerator) async throws {
        for sender in hosts.indices {
            for peer in hosts.indices where sender != peer && !cut.contains([sender, peer]) {
                let sent = hosts[sender].outbox
                let pending = sent.filter { !delivered[sender][peer].contains($0.key) }
                guard !pending.isEmpty, all || generator.chance(60) else {
                    continue
                }
                var batch = all ? pending : pending.filter { _ in generator.chance(70) }
                let old = sent.filter { delivered[sender][peer].contains($0.key) }
                if generator.chance(30), let copy = old.randomElement(using: &generator) {
                    batch.append(copy)
                }
                if generator.chance(30) {
                    batch.shuffle(using: &generator)
                }
                guard !batch.isEmpty else {
                    continue
                }
                try await hosts[peer].receive(batch)
                delivered[sender][peer].formUnion(batch.map(\.key))
            }
        }
    }
}
