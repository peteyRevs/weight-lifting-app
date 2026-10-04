import os

/// The app's logger (engineering-standards §8, architecture §14): `os.Logger` under the subsystem
/// `com.petearevalo.Ledger`, one category per module, behind the `logger` dependency so a test can discard what
/// a store logs. Log through `log`, whose interpolation keeps each value's privacy; never log health data values.
public struct LedgerLogger: Sendable {
    public static let subsystem = "com.petearevalo.Ledger"

    /// The underlying logger.
    public let log: Logger
    /// False for `disabled`, which discards every message.
    public let isEnabled: Bool

    /// A logger for `category`.
    public init(category: String) {
        log = Logger(subsystem: Self.subsystem, category: category)
        isEnabled = true
    }

    private init(disabled _: Void) {
        log = Logger(.disabled)
        isEnabled = false
    }

    /// Discards every message: the `logger` dependency's test value.
    public static let disabled = LedgerLogger(disabled: ())

    /// The same logger under another category; a disabled logger stays disabled.
    public func category(_ name: String) -> LedgerLogger {
        isEnabled ? LedgerLogger(category: name) : self
    }
}
