import Foundation
import LedgerDomain

// The device protocols' live values until their briefs bind real ones: HealthKit (F16), the live and companion
// transports (F17, F19), haptics (F10), notifications (F23) and Live Activities (F21). A protocol with no
// method yet has nothing to log; the brief that adds a method adds it here too, logging and throwing (or
// doing nothing) as the store stubs do. The haptics and notifications clients cannot throw, so their stubs
// log at fault level and do nothing.

struct UnimplementedHealthStore: HealthStore {}

struct UnimplementedLiveWorkoutTransport: LiveWorkoutTransport {}

struct UnimplementedCompanionTransport: CompanionTransport {}

struct UnimplementedHaptics: HapticsClient {
    let stub = Unimplemented(key: "haptics")

    func play(_: Haptic) async {
        stub.log(#function)
    }
}

struct UnimplementedNotifications: NotificationsClient {
    let stub = Unimplemented(key: "notifications")

    func scheduleRestOver(at _: Date) async {
        stub.log(#function)
    }

    func cancelRestOver() async {
        stub.log(#function)
    }
}

struct UnimplementedLiveActivities: LiveActivitiesClient {}
