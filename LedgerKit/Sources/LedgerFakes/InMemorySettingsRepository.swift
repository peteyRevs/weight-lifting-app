#if DEBUG
    import Foundation
    import LedgerDomain

    /// `SettingsRepository` in memory, keeping `SettingsRepositoryContract` (LedgerTestSupport): the defaults
    /// until the first save, then the saved settings; `observe()` emits only a change.
    public final class InMemorySettingsRepository: SettingsRepository {
        private let state: ObservedState<Settings, Settings>

        /// Holding `settings`; `Settings.default` is what a database with no settings row loads.
        public init(_ settings: Settings = .default) {
            state = ObservedState(settings)
        }

        public func load() async throws -> Settings {
            state.read(\.self)
        }

        public func save(_ settings: Settings) async throws {
            state.write { $0 = settings }
        }

        public func observe() -> AsyncStream<Settings> {
            state.observe(\.self)
        }
    }
#endif
