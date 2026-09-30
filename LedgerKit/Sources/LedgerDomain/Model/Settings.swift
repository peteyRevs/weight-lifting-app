import Foundation

/// User preferences (spec §6.1 "User / Account" preferences, §3.3 Settings; decisions #7, #9, #10, #15).
public struct Settings: Hashable, Codable, Sendable {
    public var units: Units
    /// Rule 3: default rest for new slots, 90 s.
    public var defaultRest: RestDuration
    /// Rule 38 / decision #10: show plates per side (spec §3.3 default on).
    public var plateMathEnabled: Bool
    /// Decision #7: start rest on every logged set (default on).
    public var autoRest: Bool
    /// Buzz the watch at rest zero (spec §4.5, default on).
    public var watchBuzz: Bool
    /// Decision #15: the first day of the stats week.
    public var weekStart: Weekday
    public var plateInventory: [Units: PlateInventory]

    public init(
        units: Units,
        defaultRest: RestDuration,
        plateMathEnabled: Bool,
        autoRest: Bool,
        watchBuzz: Bool,
        weekStart: Weekday,
        plateInventory: [Units: PlateInventory]
    ) {
        self.units = units
        self.defaultRest = defaultRest
        self.plateMathEnabled = plateMathEnabled
        self.autoRest = autoRest
        self.watchBuzz = watchBuzz
        self.weekStart = weekStart
        self.plateInventory = plateInventory
    }

    /// The prototype defaults (spec §2 state seed): lb, 90 s rest, plate math, auto rest and
    /// watch buzz on, standard inventories for both units. `weekStart` is Monday here because the
    /// domain cannot read the locale; the app seeds it from `Weekday.first(of:)` on first launch
    /// (decision #15).
    public static let `default` = Settings(
        units: .lb,
        defaultRest: .defaultRest,
        plateMathEnabled: true,
        autoRest: true,
        watchBuzz: true,
        weekStart: .monday,
        plateInventory: [.lb: .standard(.lb), .kg: .standard(.kg)]
    )
}

// MARK: - Codable (tolerates missing keys)

extension Settings {
    private enum CodingKeys: String, CodingKey {
        case units, defaultRest, plateMathEnabled, autoRest, watchBuzz, weekStart, plateInventory
    }

    /// A missing key, or one holding `null`, takes its `Settings.default` value, so settings stored or sent
    /// before a field existed still decode (F05 orchestrator decision, 2026-09-30: F28 adds `iCloudEnabled`).
    /// A key that holds a value must hold a valid one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Settings.default
        try self.init(
            units: container.decodeIfPresent(Units.self, forKey: .units) ?? fallback.units,
            defaultRest: container.decodeIfPresent(RestDuration.self, forKey: .defaultRest) ?? fallback.defaultRest,
            plateMathEnabled: container.decodeIfPresent(Bool.self, forKey: .plateMathEnabled)
                ?? fallback.plateMathEnabled,
            autoRest: container.decodeIfPresent(Bool.self, forKey: .autoRest) ?? fallback.autoRest,
            watchBuzz: container.decodeIfPresent(Bool.self, forKey: .watchBuzz) ?? fallback.watchBuzz,
            weekStart: container.decodeIfPresent(Weekday.self, forKey: .weekStart) ?? fallback.weekStart,
            plateInventory: container.decodeIfPresent([Units: PlateInventory].self, forKey: .plateInventory)
                ?? fallback.plateInventory
        )
    }
}
