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
        private let programs: InMemoryProgramRepository?

        /// Holding `settings`, kept as given, as a stored row; with none, holding no row, where load gives
        /// `Settings.default`, as a database with no settings row does. With `programs` (as `InMemoryStores` links
        /// them), `switchUnits` converts the active program there; without, it only saves.
        public init(_ settings: Settings? = nil, programs: InMemoryProgramRepository? = nil) {
            state = ObservedState(Stored(settings: settings ?? .default, isRow: settings != nil))
            self.programs = programs
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

        /// Both or neither, as the database's one transaction: the settings are checked first, then the program is
        /// converted (which may refuse it, and then nothing is written), and only then are the settings stored, which
        /// cannot fail. Two steps under two locks, so a reader may see the program converted a moment before the
        /// settings; no write can fail between them.
        public func switchUnits(_ settings: Settings) async throws {
            let stored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
            if state.read(\.settings.units) != stored.units {
                try programs?.convertActive(to: stored.units)
            }
            state.write { $0 = Stored(settings: stored, isRow: true) }
        }

        public func observe() -> AsyncStream<Settings> {
            state.observe(\.settings)
        }
    }
#endif
