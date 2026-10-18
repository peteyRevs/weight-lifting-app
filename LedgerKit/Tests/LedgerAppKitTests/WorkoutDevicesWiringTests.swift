import Dependencies
import Foundation
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S6, criteria 7 and 8: what the iPhone's composition gives the live workout of the device: its
/// haptics and its announcements (F10 S7a), bound with the session; and no notifications client, until F23.
@Suite("AppComposition · the live workout's devices", .timeLimit(.minutes(1)))
struct WorkoutDevicesWiringTests {
    /// F10 S6, criterion 7 and the ruling on the test default: the composition binds the iPhone's haptics
    /// itself. `withDependencies` starts from the live values here, as the app does, so a composition that
    /// left the key unbound would hand back the stub and fail this test.
    @Test("With the database open the composition binds the live haptics; before that it binds nothing")
    func boot_bindsTheLiveHaptics() async {
        let harness = Harness()
        defer { harness.remove() }
        func bound(by composition: AppComposition) -> any HapticsClient {
            withDependencies {
                $0.context = .live
                composition.bind(&$0)
            } operation: {
                @Dependency(\.haptics) var haptics
                return haptics
            }
        }
        #expect(!(bound(by: harness.composition()) is LiveHaptics))
        let haptics = bound(by: harness.booted())
        #expect(haptics is LiveHaptics)
        // Each of the engine's haptics is played without a trap, on a simulator that has no Taptic Engine.
        for haptic in Haptic.allCases {
            await haptics.play(haptic)
        }
    }

    /// F10 S7a, criterion 20: the composition binds the iPhone's announcements with the session, as it does
    /// the haptics. `withDependencies` starts from the live values, so a composition that left the key
    /// unbound would hand back the stub and fail this test.
    @Test("With the database open the composition binds the live announcements; before that it binds nothing")
    func boot_bindsTheLiveAnnouncements() async {
        let harness = Harness()
        defer { harness.remove() }
        func bound(by composition: AppComposition) -> any AnnouncementsClient {
            withDependencies {
                $0.context = .live
                composition.bind(&$0)
            } operation: {
                @Dependency(\.announcements) var announcements
                return announcements
            }
        }
        #expect(!(bound(by: harness.composition()) is LiveAnnouncements))
        let announcements = bound(by: harness.booted())
        #expect(announcements is LiveAnnouncements)
        // Posting one traps nothing where no assistive technology runs.
        await announcements.announce("Rest over")
    }

    /// F10 S6, criterion 8: the app's host is given no notifications client until F23. A rest that starts,
    /// is extended, ends and is skipped through the bound session runs the workout and calls nothing.
    @Test("A rest starts, is extended and is skipped through the app's host without a notifications client")
    func rest_runsWithoutANotificationsClient() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let host = try #require(harness.booted().session)
        let session = EventBuilders.seedSession()
        try await host.start(session)
        let row = session.exercises[0].sets[0]
        let rested = try await host.apply(.setLogged(
            exerciseIndex: 0, setID: row.id, weight: row.weight, reps: row.reps, doneAt: Harness.now
        ))
        #expect(rested.shownRest == RestTimer(endsAt: Harness.now.addingTimeInterval(150), total: .seconds(150)))
        let extended = try await host.apply(
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: Harness.now)
        )
        #expect(extended.shownRest?.total == .seconds(180))
        #expect(try await host.apply(.restSkipped).shownRest == nil)
        try await host.discard(endedAt: Harness.now.addingTimeInterval(60))
        #expect(try await host.current() == nil)
    }
}
