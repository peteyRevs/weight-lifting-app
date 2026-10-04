#if DEBUG
    import LedgerDomain

    // Fakes of the device protocols, for previews and tests. The protocols have no methods yet (HealthKit,
    // the transports and the clients are shaped by F10, F16, F17, F19, F21 and F23), so the fakes record
    // nothing yet: the brief that adds a method grows its fake with scriptable answers and recorded calls.

    /// `HealthStore` for previews and tests; F16 adds scriptable authorisation, heart-rate samples and
    /// recorded calls.
    public struct FakeHealthStore: HealthStore {
        public init() {}
    }

    /// `LiveWorkoutTransport` for previews and tests; F17 builds it over `FakeLinkBus`.
    public struct FakeLiveWorkoutTransport: LiveWorkoutTransport {
        public init() {}
    }

    /// `CompanionTransport` for previews and tests; F19 adds recorded transfers.
    public struct FakeCompanionTransport: CompanionTransport {
        public init() {}
    }

    /// `HapticsClient` for previews and tests; F10 records the haptics played.
    public struct FakeHaptics: HapticsClient {
        public init() {}
    }

    /// `NotificationsClient` for previews and tests; F10 and F23 record what is scheduled and cancelled.
    public struct FakeNotifications: NotificationsClient {
        public init() {}
    }

    /// `LiveActivitiesClient` for previews and tests; F21 records starts, updates and ends.
    public struct FakeLiveActivities: LiveActivitiesClient {
        public init() {}
    }
#endif
