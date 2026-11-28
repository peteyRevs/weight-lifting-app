#if DEBUG
    import Foundation
    import LedgerDomain

    // Fakes of the device protocols, for previews and tests (`FakeHealthStore`, `FakeLiveWorkoutTransport` and
    // `FakeCompanionTransport` have their own files). A protocol with no method yet (the Live Activity is shaped by
    // F21) has a fake that records nothing: the brief that adds a method grows its fake with scriptable answers and
    // recorded calls.

    /// `LiveConnectionClient` for previews and tests. Made with a state alone, each stream holds that state and ends.
    /// Made `scripted` (F17 S8), each reader's stream holds the state now, then each `change(to:)`, until `end()`; a
    /// reader that comes after `end()` gets the state and an ended stream.
    public actor FakeLiveConnection: LiveConnectionClient {
        /// The state a new reader is handed first: the one made with, then the last `change(to:)`.
        public private(set) var state: LiveConnectionState
        private var readers: [AsyncStream<LiveConnectionState>.Continuation] = []
        private var hasEnded: Bool

        public init(_ state: LiveConnectionState = .solo, scripted: Bool = false) {
            self.state = state
            hasEnded = !scripted
        }

        public func states() -> AsyncStream<LiveConnectionState> {
            let (stream, reader) = AsyncStream.makeStream(of: LiveConnectionState.self)
            reader.yield(state)
            if hasEnded {
                reader.finish()
            } else {
                readers.append(reader)
            }
            return stream
        }

        /// The connection becomes `next`: every open reader hears it, and later readers start from it.
        public func change(to next: LiveConnectionState) {
            state = next
            for reader in readers {
                reader.yield(next)
            }
        }

        /// The connection's owner stops: every stream ends.
        public func end() {
            hasEnded = true
            for reader in readers {
                reader.finish()
            }
            readers = []
        }
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
