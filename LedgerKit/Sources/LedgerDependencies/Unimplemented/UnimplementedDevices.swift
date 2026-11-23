import Foundation
import LedgerDomain

// The device protocols' live values until their briefs bind real ones: HealthKit (F16), the live and companion
// transports (F17, F19), haptics (F10), notifications (F23) and Live Activities (F21). A protocol with no
// method yet has nothing to log; the brief that adds a method adds it here too, logging and throwing (or
// doing nothing) as the store stubs do. The haptics, notifications and announcements clients cannot throw,
// so their stubs log at fault level and do nothing.

/// Throws from every method that can; `authorization()` answers `.unavailable`, and every stream ends at once. It
/// is its own `remoteChannel`.
struct UnimplementedHealthStore: HealthStore, RemoteSessionChannel {
    let stub = Unimplemented(key: "healthStore")

    var events: AsyncStream<HealthSessionEvent> {
        stub.emptyStream()
    }

    var remoteChannel: any RemoteSessionChannel {
        self
    }

    var connection: AsyncStream<Bool> {
        stub.emptyStream()
    }

    var incoming: AsyncStream<[Data]> {
        stub.emptyStream()
    }

    func authorization() async -> HealthAuthorization {
        stub.log(#function)
        return .unavailable
    }

    func requestAuthorization() async throws -> HealthAuthorization {
        throw stub.failure()
    }

    func startSession(workoutID _: WorkoutID, at _: Date) async throws {
        throw stub.failure()
    }

    func heartRate() async -> AsyncStream<HeartRateSample> {
        stub.emptyStream()
    }

    func endSession(metadata _: HealthWorkoutMetadata, at _: Date) async throws -> HealthWorkoutRecord {
        throw stub.failure()
    }

    func discardSession() async throws {
        throw stub.failure()
    }

    func recoverActiveSession() async throws -> Bool {
        throw stub.failure()
    }

    func requestWatchStart() async throws {
        throw stub.failure()
    }

    func saveWorkout(
        metadata _: HealthWorkoutMetadata,
        start _: Date,
        end _: Date
    ) async throws -> HealthWorkoutRecord {
        throw stub.failure()
    }

    func workoutRecord(healthKitUUID _: UUID) async throws -> HealthWorkoutRecord? {
        throw stub.failure()
    }

    func send(_: Data) async throws {
        throw stub.failure()
    }
}

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

struct UnimplementedAnnouncements: AnnouncementsClient {
    let stub = Unimplemented(key: "announcements")

    func announce(_: String) async {
        stub.log(#function)
    }
}

struct UnimplementedLiveActivities: LiveActivitiesClient {}
