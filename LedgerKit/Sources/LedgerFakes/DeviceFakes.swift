#if DEBUG
    import Foundation
    import LedgerDomain

    // Fakes of the device protocols, for previews and tests (`FakeHealthStore` and `FakeLiveWorkoutTransport` have
    // their own files). A protocol with no method yet (the companion transport and the Live Activity are shaped by
    // F19 and F21) has a fake that records nothing: the brief that adds a method grows its fake with scriptable
    // answers and recorded calls.

    /// `LiveConnectionClient` for previews and tests: each stream holds `state` and ends. S8 grows it with changes.
    public struct FakeLiveConnection: LiveConnectionClient {
        public let state: LiveConnectionState

        public init(_ state: LiveConnectionState = .solo) {
            self.state = state
        }

        public func states() -> AsyncStream<LiveConnectionState> {
            AsyncStream { continuation in
                continuation.yield(state)
                continuation.finish()
            }
        }
    }

    /// `CompanionTransport` for previews and tests; F19 adds recorded transfers.
    public struct FakeCompanionTransport: CompanionTransport {
        public init() {}
    }

    /// `HapticsClient` for previews and tests: it plays nothing and records what it was asked to play.
    public actor FakeHaptics: HapticsClient {
        /// Every haptic it was asked to play, in call order.
        public private(set) var played: [Haptic] = []

        public init() {}

        public func play(_ haptic: Haptic) {
            played.append(haptic)
        }
    }

    /// `NotificationsClient` for previews and tests: it schedules nothing and records what it was asked.
    /// F23 adds what its permission and its content need.
    public actor FakeNotifications: NotificationsClient {
        public enum Call: Hashable, Sendable {
            case scheduleRestOver(Date)
            case cancelRestOver
        }

        /// Every call, in order.
        public private(set) var calls: [Call] = []
        /// When the rest-over notification is due, as the calls leave it: the last one scheduled, or nil
        /// after a cancel.
        public private(set) var restOverAt: Date?

        public init() {}

        public func scheduleRestOver(at endsAt: Date) {
            calls.append(.scheduleRestOver(endsAt))
            restOverAt = endsAt
        }

        public func cancelRestOver() {
            calls.append(.cancelRestOver)
            restOverAt = nil
        }
    }

    /// `AnnouncementsClient` for previews and tests: it says nothing and records what it was asked to say.
    public actor FakeAnnouncements: AnnouncementsClient {
        /// Every text it was asked to announce, in call order.
        public private(set) var announced: [String] = []

        public init() {}

        public func announce(_ text: String) {
            announced.append(text)
        }
    }

    /// `LiveActivitiesClient` for previews and tests; F21 records starts, updates and ends.
    public struct FakeLiveActivities: LiveActivitiesClient {
        public init() {}
    }
#endif
