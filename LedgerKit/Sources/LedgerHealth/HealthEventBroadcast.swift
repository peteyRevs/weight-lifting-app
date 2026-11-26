import LedgerDomain

/// `HealthStore.events` for more than one reader (F17 S5a). The store's stream has one consumer; on the watch both
/// the session host (the phone's start request, `LocalWorkoutSessionActor.followPhoneStartRequests`) and the
/// workout screen (F18) read it. The composition makes one broadcast over the store's `events` and runs it for
/// the store's life; each reader subscribes.
///
/// - A subscriber gets every event the broadcast takes after it subscribed, in order. One that subscribes before
///   `run()` takes the first event gets them all: the store's stream holds them until then.
/// - A subscriber that stops reading is dropped at the next event, as the session host drops its ended streams.
/// - When the store's stream ends, every subscriber's ends, and so does one that subscribes later.
public actor HealthEventBroadcast {
    private let source: AsyncStream<HealthSessionEvent>
    private var subscribers: [AsyncStream<HealthSessionEvent>.Continuation] = []
    private var isRunning = false
    private var isFinished = false

    public init(_ source: AsyncStream<HealthSessionEvent>) {
        self.source = source
    }

    /// A new stream of what the store reports from now on.
    public func subscribe() -> AsyncStream<HealthSessionEvent> {
        let (stream, continuation) = AsyncStream<HealthSessionEvent>.makeStream(bufferingPolicy: .unbounded)
        if isFinished {
            continuation.finish()
        } else {
            subscribers.append(continuation)
        }
        return stream
    }

    /// Hands every event of the store's stream to the subscribers, until that stream ends or the caller's task is
    /// cancelled; then ends every subscriber's stream. Runs once: a second call returns at once.
    public func run() async {
        guard !isRunning else {
            return
        }
        isRunning = true
        for await event in source {
            deliver(event)
        }
        isFinished = true
        subscribers.forEach { $0.finish() }
        subscribers = []
    }

    private func deliver(_ event: HealthSessionEvent) {
        subscribers = subscribers.filter { subscriber in
            if case .terminated = subscriber.yield(event) {
                return false
            }
            return true
        }
    }
}
