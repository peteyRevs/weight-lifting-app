/// What every `Unimplemented*` stub does when called: logs the call at fault level, naming the key and the
/// method, then throws `LedgerDependencyError.unimplemented(key:)`, or, where the protocol cannot throw,
/// returns nothing (an empty stream). A stub is the `liveValue` of a key the composition root has not bound
/// yet, so a call that reaches one is a wiring bug: loud in the log, harmless to the lifter's data.
struct Unimplemented: Sendable {
    static let logger = LedgerLogger(category: "dependencies")

    let key: String

    /// Logs the call and returns the error to throw.
    func failure(_ method: String = #function) -> LedgerDependencyError {
        log(method)
        return .unimplemented(key: key)
    }

    /// Logs the call and returns a stream that ends at once, for a protocol's non-throwing `observe…()`.
    func emptyStream<Element>(_ method: String = #function) -> AsyncStream<Element> {
        log(method)
        return AsyncStream { $0.finish() }
    }

    func log(_ method: String) {
        Self.logger.log.fault(
            "\(key, privacy: .public) has no live value yet: \(method, privacy: .public) was called on its stub"
        )
    }
}
