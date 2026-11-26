import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S5b's fix to S4a: a link-up starts the handshake rate limit afresh.
extension HostTransportTests {
    @Test("A link-up starts the rate limit afresh: a workout asked about before it is asked about again")
    func linkUp_resetsTheRateLimit() async throws {
        var rig = await Rig()
        let other = Sample.other.id
        try await rig.subject.host.start(Sample.session)
        _ = await rig.next()
        try await rig.subject.host.receive(.handshake(workoutID: other, contiguousSeq: [Peer.device: 4]))
        #expect(await rig.next() == .handshake(workoutID: other, contiguousSeq: [:]))
        try await rig.subject.host.receive(.handshake(workoutID: other, contiguousSeq: [Peer.device: 4])) // limited
        rig.network.partition()
        rig.network.heal()
        #expect(await rig.next() == .handshake(workoutID: Self.workout, contiguousSeq: [Subject.device: 1]))
        try await rig.subject.host.receive(.handshake(workoutID: other, contiguousSeq: [Peer.device: 4]))
        #expect(await rig.next() == .handshake(workoutID: other, contiguousSeq: [:]))
    }
}
