import Dependencies
import Foundation
@testable import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S6, criteria 7 and 8: the two device clients that gained methods. Their stubs cannot throw, so they
/// log and return; their fakes record; and `withTestDependencies` gives `haptics` a recording fake.
@Suite("Device clients: haptics and notifications")
struct DeviceClientTests {
    @Test("The haptics and notifications stubs cannot throw: each call returns, having done nothing (F10 S6)")
    func deviceClients_returnFromEveryCall() async {
        await HapticsKey.liveValue.play(.setLogged)
        await HapticsKey.liveValue.play(.restOver)
        await NotificationsKey.liveValue.scheduleRestOver(at: Fixtures.now)
        await NotificationsKey.liveValue.cancelRestOver()
        #expect(UnimplementedHaptics().stub.key == "haptics")
        #expect(UnimplementedNotifications().stub.key == "notifications")
    }

    @Test("The recording fakes keep what they were asked, in order (F10 S6)")
    func deviceFakes_record() async {
        let haptics = FakeHaptics()
        await haptics.play(.setLogged)
        await haptics.play(.restOver)
        #expect(await haptics.played == [.setLogged, .restOver])
        let notifications = FakeNotifications()
        #expect(await notifications.restOverAt == nil)
        await notifications.scheduleRestOver(at: Fixtures.now)
        await notifications.scheduleRestOver(at: Fixtures.now.addingTimeInterval(30))
        #expect(await notifications.restOverAt == Fixtures.now.addingTimeInterval(30), "one replaces the other")
        await notifications.cancelRestOver()
        #expect(await notifications.restOverAt == nil)
        #expect(await notifications.calls == [
            .scheduleRestOver(Fixtures.now), .scheduleRestOver(Fixtures.now.addingTimeInterval(30)), .cancelRestOver
        ])
    }

    /// F10 S6 (the orchestrator's ruling during G1): a store that plays haptics does so on every logged set,
    /// so `withTestDependencies` gives the key a recording fake, a new one for each call. Outside it the
    /// key still fails a test that reads it unconfigured.
    @Test("withTestDependencies gives haptics a recording fake of its own for each call; without it the key fails")
    func haptics_defaultsToAFreshFake() async {
        let first = withTestDependencies {
            @Dependency(\.haptics) var haptics
            return haptics
        }
        let second = withTestDependencies {
            @Dependency(\.haptics) var haptics
            return haptics
        }
        let fake = first as? FakeHaptics
        #expect(fake != nil)
        #expect(fake !== (second as? FakeHaptics), "no fake is shared between two tests")
        await first.play(.setLogged)
        #expect(await fake?.played == [.setLogged])
        #expect(await (second as? FakeHaptics)?.played == [])
        withKnownIssue {
            @Dependency(\.haptics) var haptics
            _ = haptics
        } matching: { issue in
            issue.description.contains("@Dependency(\\.haptics)")
        }
    }
}
