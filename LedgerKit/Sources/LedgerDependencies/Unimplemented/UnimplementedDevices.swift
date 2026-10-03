import LedgerDomain

// The device protocols' live values until their briefs bind real ones: HealthKit (F16), the live and companion
// transports (F17, F19), haptics (F10), notifications (F23) and Live Activities (F21). The protocols have no
// methods yet, so there is nothing to log; the brief that adds a method adds it here too, logging and throwing
// (or doing nothing) as the store stubs do.

struct UnimplementedHealthStore: HealthStore {}

struct UnimplementedLiveWorkoutTransport: LiveWorkoutTransport {}

struct UnimplementedCompanionTransport: CompanionTransport {}

struct UnimplementedHaptics: HapticsClient {}

struct UnimplementedNotifications: NotificationsClient {}

struct UnimplementedLiveActivities: LiveActivitiesClient {}
