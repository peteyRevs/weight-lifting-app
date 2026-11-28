import Foundation

/// A payload a `CompanionTransport` carries as `CompanionCodec` bytes.
public protocol CompanionPayload: Codable, Sendable {
    /// The most bytes one may encode to, or nil (the default) for no limit.
    static var byteLimit: Int? { get }
}

public extension CompanionPayload {
    static var byteLimit: Int? {
        nil
    }
}

extension CompanionContext: CompanionPayload {
    public static var byteLimit: Int? {
        CompanionCodec.contextLimit
    }
}

extension CompanionFile: CompanionPayload {}

extension FinishedWorkoutRecord: CompanionPayload {}

/// How a finished workout's record travels (criterion 8).
public enum RecordDelivery: Hashable, Sendable {
    /// As user info (`CompanionTransport.enqueue`).
    case userInfo
    /// As a file (`CompanionTransport.transfer(.workoutLog(_:))`).
    case file
}

/// The companion payloads' bytes (F19), versioned as `WireCodec` versions a live frame: one magic byte `0x43`
/// ("C", so a live frame is never read as one), one version byte, then the payload as sorted-key JSON with
/// `.deferredToDate` dates, which round-trip every date exactly.
///
/// A payload of a version this build does not read is refused whole (`unsupportedVersion`), never decoded in
/// part: a newer watch's record could otherwise fold into a different workout here. `version` rises whenever
/// `WireCodec.version` does (a record carries envelopes) or a payload's shape changes.
public enum CompanionCodec {
    /// The first byte of every payload.
    public static let magic: UInt8 = 0x43
    /// The version `encode` writes, and the only one `decode` reads so far.
    public static let version: UInt8 = 1
    /// The most bytes a context may take: under the 262 144 bytes `updateApplicationContext` was measured to take
    /// (R1 §2.6), with room for the dictionary key that carries them.
    public static let contextLimit = 256_000
    /// The most bytes a record sent as user info may take: `transferUserInfo`'s measured 65 536 (R1 §2.6), with
    /// the same headroom as `WireCodec.frameLimit`.
    public static let userInfoLimit = 60000

    /// `payload`'s bytes. Throws `tooLarge` past its type's `byteLimit` and `unencodable` for a date that is not
    /// finite, which JSON cannot carry.
    public static func encode(_ payload: some CompanionPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data: Data
        do {
            data = try Data([magic, version]) + encoder.encode(payload)
        } catch {
            throw CompanionCodecError.unencodable
        }
        if let limit = type(of: payload).byteLimit, data.count > limit {
            throw CompanionCodecError.tooLarge
        }
        return data
    }

    /// The `type` payload `data` holds. Throws `notAPayload` when it does not start with `magic` and a version
    /// byte, `unsupportedVersion` for a version this build does not read, and `unreadable` when the JSON after them
    /// is not a `type`.
    public static func decode<Payload: CompanionPayload>(_ type: Payload.Type, from data: Data) throws -> Payload {
        guard data.count >= 2, data[data.startIndex] == magic else {
            throw CompanionCodecError.notAPayload
        }
        let written = data[data.startIndex + 1]
        guard written == version else {
            throw CompanionCodecError.unsupportedVersion(written)
        }
        do {
            return try JSONDecoder().decode(type, from: data.dropFirst(2))
        } catch {
            throw CompanionCodecError.unreadable
        }
    }

    /// How `record` travels: as a file when it encodes to more than `userInfoLimit` bytes (criterion 8).
    public static func delivery(for record: FinishedWorkoutRecord) throws -> RecordDelivery {
        try delivery(forEncodedSize: encode(record).count)
    }

    /// How a record of `size` encoded bytes travels.
    public static func delivery(forEncodedSize size: Int) -> RecordDelivery {
        size > userInfoLimit ? .file : .userInfo
    }
}

/// Why `CompanionCodec` refused a payload.
public enum CompanionCodecError: Error, Equatable, Sendable {
    /// The bytes do not start with `CompanionCodec.magic` and a version byte: not a companion payload.
    case notAPayload
    /// A payload written in a version this build does not read: a peer with another version of Ledger.
    case unsupportedVersion(UInt8)
    /// The JSON after the header is not a payload of the type asked for, in this version.
    case unreadable
    /// The payload passes its type's limit: a context over `CompanionCodec.contextLimit`, or a record queued as
    /// user info that must go as a file.
    case tooLarge
    /// A date in the payload is not finite.
    case unencodable
}
