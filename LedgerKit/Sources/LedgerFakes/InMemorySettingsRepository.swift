#if DEBUG
    import Foundation
    import LedgerDomain

    /// `SettingsRepository` in memory, keeping `SettingsRepositoryContract` (LedgerTestSupport): the defaults
    /// until the first save, then the saved settings as the database stores them, through `SettingsCodec` (so an
    /// inventory's plates come back normalised, and a NaN weight throws `EncodingError`); `observe()` emits only a
    /// change.
    public final class InMemorySettingsRepository: SettingsRepository {
        /// The settings, and whether a row holds them: `seedIfAbsent(_:)` writes only when none does.
        private struct Stored {
            var settings: Settings
            var isRow: Bool
        }

        private let state: ObservedState<Stored>

        /// Holding `settings`, kept as given, as a stored row; with none, holding no row, where load gives
        /// `Settings.default`, as a database with no settings row does.
        public init(_ settings: Settings? = nil) {
            state = ObservedState(Stored(settings: settings ?? .default, isRow: settings != nil))
        }

        public func load() async throws -> Settings {
            state.read(\.settings)
        }

        public func save(_ settings: Settings) async throws {
            let stored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
            state.write { $0 = Stored(settings: stored, isRow: true) }
        }

        public func seedIfAbsent(_ settings: Settings) async throws {
            let stored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
            state.write { current in
                if !current.isRow {
                    current = Stored(settings: stored, isRow: true)
                }
            }
        }

        public func observe() -> AsyncStream<Settings> {
            state.observe(\.settings)
        }
    }
#endif
