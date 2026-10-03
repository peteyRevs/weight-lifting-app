import Foundation

/// `Settings` as a store keeps them: JSON with sorted keys, decoded by the payload version it was written in
/// (orchestrator decision, 2026-09-30); `settings.payload` in LedgerPersistence and the stored form in LedgerFakes
/// (ADR-008), so a fake loads what the database loads (plates normalised by `PlateInventory`'s decoder, a NaN
/// weight refused with `EncodingError`). Version 1 is the only one so far.
public enum SettingsCodec {
    /// The payload version `encode` writes.
    public static let version = 1

    public static func encode(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(settings)
    }

    public static func decode(_ payload: Data, version: Int) throws -> Settings {
        switch version {
        case 1:
            try JSONDecoder().decode(Settings.self, from: payload)
        default:
            throw RepositoryError.unknownPayloadVersion(version)
        }
    }
}
