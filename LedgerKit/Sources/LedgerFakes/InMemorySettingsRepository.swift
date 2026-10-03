#if DEBUG
    import Foundation
    import LedgerDomain

    /// `SettingsRepository` in memory, keeping `SettingsRepositoryContract` (LedgerTestSupport): the defaults
    /// until the first save, then the saved settings as the database stores them, through `SettingsCodec` (so an
    /// inventory's plates come back normalised, and a NaN weight throws `EncodingError`); `observe()` emits only a
    /// change.
    public final class InMemorySettingsRepository: SettingsRepository {
        private let state: ObservedState<Settings, Settings>

        /// Holding `settings`, kept as given (stored state); `Settings.default` is what a database with no settings
        /// row loads.
        public init(_ settings: Settings = .default) {
            state = ObservedState(settings)
        }

        public func load() async throws -> Settings {
            state.read(\.self)
        }

        public func save(_ settings: Settings) async throws {
            let stored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
            state.write { $0 = stored }
        }

        public func observe() -> AsyncStream<Settings> {
            state.observe(\.self)
        }
    }
#endif
