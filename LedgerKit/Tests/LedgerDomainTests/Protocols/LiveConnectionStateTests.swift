@testable import LedgerDomain
import Testing

/// F17 criterion 12, the rule both devices' connection lines read (F18 S1 moved it here from FeatureWorkout).
@Suite("LiveConnectionState", .tags(.domain))
struct LiveConnectionStateTests {
    @Test("The peer is away while reconnecting, and in solo once it was heard; never otherwise")
    func isPeerAway_reconnecting_orSoloAfterThePeer() {
        #expect(LiveConnectionState.isPeerAway(.reconnecting, hasHeardThePeer: false))
        #expect(LiveConnectionState.isPeerAway(.reconnecting, hasHeardThePeer: true))
        #expect(LiveConnectionState.isPeerAway(.solo, hasHeardThePeer: true))
        #expect(!LiveConnectionState.isPeerAway(.solo, hasHeardThePeer: false), "one device never reads the line")
        let quiet: [LiveConnectionState?] = [
            nil, .connected(.mirroring), .connected(.watchConnectivity), .degraded(.mirroring)
        ]
        for connection in quiet {
            for heard in [false, true] {
                let isAway = LiveConnectionState.isPeerAway(connection, hasHeardThePeer: heard)
                #expect(!isAway, "\(String(describing: connection)), heard \(heard)")
            }
        }
    }
}
