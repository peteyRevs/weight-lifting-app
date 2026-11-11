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
        /// them), `switchUnits` converts its live programs there; without, it only saves.
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

        /// Both or neither, as the database's one transaction, in one step: the settings are checked first; then,
        /// under the settings' lock, the units stored are compared, the programs converted (which may refuse, and
        /// then nothing is written) and the settings stored. Two switches never interleave (F14-S2 G3 N5); the
        /// programs' lock is the only one taken inside this one.
        public func switchUnits(_ settings: Settings) async throws {
            let stored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
            try state.write { current in
                if current.settings.units != stored.units {
                    try programs?.convertLive(to: stored.units)
                }
                current = Stored(settings: stored, isRow: true)
            }
        }

        public func observe() -> AsyncStream<Settings> {
            state.observe(\.settings)
        }
    }
#endif
