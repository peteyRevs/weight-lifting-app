import Synchronization

/// A stream a test feeds, with one consumer it can wait for (F17 S4b): `idle()` returns once the consumer has
/// taken everything fed so far and asked for more. A host's listener takes the next frame only when it is done
/// with the last, so `idle()` means every fed element has been dealt with: a barrier, with no sleep and no polling.
final class GatedStream<Element: Sendable>: Sendable {
    private enum Answer {
        case element(Element)
        case end
    }

    private struct State {
        var queue: [Element] = []
        var consumer: CheckedContinuation<Element?, Never>?
        var idleWaiters: [CheckedContinuation<Void, Never>] = []
        var isFinished = false

        var isIdle: Bool {
            isFinished || (consumer != nil && queue.isEmpty)
        }
    }

    private let state = Mutex(State())

    /// The stream to hand the consumer, once: its elements are what `feed(_:)` was given, in order.
    func makeStream() -> AsyncStream<Element> {
        AsyncStream(unfolding: { await self.take() }, onCancel: { self.finish() })
    }

    func feed(_ element: Element) {
        let consumer = state.withLock { state -> CheckedContinuation<Element?, Never>? in
            guard !state.isFinished else {
                return nil
            }
            guard let consumer = state.consumer else {
                state.queue.append(element)
                return nil
            }
            state.consumer = nil
            return consumer
        }
        consumer?.resume(returning: element)
    }

    /// Returns once the consumer waits for an element and none is left, or the stream has ended.
    func idle() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let isIdle = state.withLock { state in
                guard !state.isIdle else {
                    return true
                }
                state.idleWaiters.append(waiter)
                return false
            }
            if isIdle {
                waiter.resume()
            }
        }
    }

    /// Ends the stream: the consumer's wait returns nil, and so does every later one.
    func finish() {
        let (consumer, waiters) = state.withLock { state in
            state.isFinished = true
            defer { (state.consumer, state.idleWaiters) = (nil, []) }
            return (state.consumer, state.idleWaiters)
        }
        consumer?.resume(returning: nil)
        waiters.forEach { $0.resume() }
    }

    private func take() async -> Element? {
        await withCheckedContinuation { (consumer: CheckedContinuation<Element?, Never>) in
            let (answer, waiters) = state.withLock { state -> (Answer?, [CheckedContinuation<Void, Never>]) in
                if !state.queue.isEmpty {
                    return (.element(state.queue.removeFirst()), [])
                }
                if state.isFinished {
                    return (.end, [])
                }
                state.consumer = consumer
                defer { state.idleWaiters = [] }
                return (nil, state.idleWaiters)
            }
            waiters.forEach { $0.resume() }
            switch answer {
            case let .element(element):
                consumer.resume(returning: element)
            case .end:
                consumer.resume(returning: nil)
            case nil:
                break
            }
        }
    }
}
