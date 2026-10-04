import Dependencies
import Foundation
import LedgerDomain
#if DEBUG
    import LedgerFakes
#endif

// The device keys (architecture §13): HealthKit, the two phone ⇄ watch transports, the device clients, this
// install's device id and the logger. `liveValue` is an `Unimplemented*` stub until a brief binds the real one;
// `testValue` is the library's default, which fails the test naming the key, except the logger's, which
// discards; `previewValue` is a fake.

public extension DependencyValues {
    var healthStore: any HealthStore {
        get { self[HealthStoreKey.self] }
        set { self[HealthStoreKey.self] = newValue }
    }

    var liveWorkoutTransport: any LiveWorkoutTransport {
        get { self[LiveWorkoutTransportKey.self] }
        set { self[LiveWorkoutTransportKey.self] = newValue }
    }

    var companionTransport: any CompanionTransport {
        get { self[CompanionTransportKey.self] }
        set { self[CompanionTransportKey.self] = newValue }
    }

    var haptics: any HapticsClient {
        get { self[HapticsKey.self] }
        set { self[HapticsKey.self] = newValue }
    }

    var notifications: any NotificationsClient {
        get { self[NotificationsKey.self] }
        set { self[NotificationsKey.self] = newValue }
    }

    var liveActivities: any LiveActivitiesClient {
        get { self[LiveActivitiesKey.self] }
        set { self[LiveActivitiesKey.self] = newValue }
    }

    /// This install's device: the one `device` row of this platform's kind (decision B4), which the composition
    /// root reads or inserts at launch (F07 S2) and binds here.
    var deviceID: DeviceID {
        get { self[DeviceIDKey.self] }
        set { self[DeviceIDKey.self] = newValue }
    }

    var logger: LedgerLogger {
        get { self[LoggerKey.self] }
        set { self[LoggerKey.self] = newValue }
    }
}

enum HealthStoreKey: DependencyKey {
    static let liveValue: any HealthStore = UnimplementedHealthStore()
    #if DEBUG
        static let previewValue: any HealthStore = FakeHealthStore()
    #endif
}

enum LiveWorkoutTransportKey: DependencyKey {
    static let liveValue: any LiveWorkoutTransport = UnimplementedLiveWorkoutTransport()
    #if DEBUG
        static let previewValue: any LiveWorkoutTransport = FakeLiveWorkoutTransport()
    #endif
}

enum CompanionTransportKey: DependencyKey {
    static let liveValue: any CompanionTransport = UnimplementedCompanionTransport()
    #if DEBUG
        static let previewValue: any CompanionTransport = FakeCompanionTransport()
    #endif
}

enum HapticsKey: DependencyKey {
    static let liveValue: any HapticsClient = UnimplementedHaptics()
    #if DEBUG
        static let previewValue: any HapticsClient = FakeHaptics()
    #endif
}

enum NotificationsKey: DependencyKey {
    static let liveValue: any NotificationsClient = UnimplementedNotifications()
    #if DEBUG
        static let previewValue: any NotificationsClient = FakeNotifications()
    #endif
}

enum LiveActivitiesKey: DependencyKey {
    static let liveValue: any LiveActivitiesClient = UnimplementedLiveActivities()
    #if DEBUG
        static let previewValue: any LiveActivitiesClient = FakeLiveActivities()
    #endif
}

enum DeviceIDKey: DependencyKey {
    /// No device row is read until the composition root binds one (F07 S2): reading this logs at fault level
    /// and gives the nil UUID, which no `device` row holds.
    static var liveValue: DeviceID {
        Unimplemented(key: "deviceID").log("liveValue")
        return DeviceID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    #if DEBUG
        static let previewValue = Fixtures.deviceID
    #endif
}

enum LoggerKey: DependencyKey {
    static let liveValue = LedgerLogger(category: "app")
    static let testValue = LedgerLogger.disabled
}
