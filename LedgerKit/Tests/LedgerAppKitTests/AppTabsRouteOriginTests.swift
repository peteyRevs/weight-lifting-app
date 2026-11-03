#if os(iOS)
    import FeatureHistory
    @testable import LedgerAppKit
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F13-S1-6 one level up (review S2-R1-2, s2): `AppTabs` hands each pushed screen the tab of the stack that drew
    /// it, so the screen's routes are resolved there. A workout's detail pushed on Today, over empty stores, finds no
    /// workout and asks to close; the close must come from Today, not from History. The shell is hosted told the scene
    /// is active (a window with no scene reports the background, where a root follows nothing).
    @MainActor
    @Suite("AppTabs · where a pushed screen's routes come from", .serialized, .timeLimit(.minutes(1)))
    struct AppTabsRouteOriginTests {
        struct Sent: Equatable {
            let route: HistoryRoute
            let tab: AppTab
        }

        @MainActor @Observable
        final class Handed {
            var sent: [Sent] = []
        }

        @Test("A workout's detail pushed on Today sends its routes from Today")
        func detailOnToday_sendsFromToday() async {
            let workout = WorkoutID(Fixtures.uuid(471))
            let router = AppRouter()
            router.open(.workout(workout), in: .today)
            let handed = Handed()
            await withTestDependencies {
                $0.inMemoryStores()
                $0.workoutSession = FakeWorkoutSessionClient()
            } operation: {
                let shell = AppTabs(router: router, onHistoryRoute: { route, tab in
                    handed.sent.append(Sent(route: route, tab: tab))
                })
                .environment(\.scenePhase, .active)
                let host = UIHostingController(rootView: shell)
                let frame = CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874)
                let window = SceneLessWindow.make(frame: frame)
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                host.view.layoutIfNeeded()
                for await isSent in Observations({ !handed.sent.isEmpty }) where isSent {
                    break
                }
            }
            #expect(handed.sent.first == Sent(route: .closeWorkout(workout), tab: .today))
        }
    }
#endif
