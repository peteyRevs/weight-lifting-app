import Foundation

/// `WireFrame`'s bytes (F17): one magic byte `0x4C` ("L"), one version byte, then the frame as JSON.
///
/// - The JSON is `EventEnvelope`'s own `Codable` form with sorted keys and `JSONEncoder`'s default
///   `.deferredToDate` dates, which round-trip every date exactly. The brief's `.iso8601` would drop the
///   fractional seconds, and the sender and receiver would then order the same envelope by different stamps
///   (F17 "Inputs from F04", item 6).
/// - JSON has no ±∞ or NaN, so no frame carries a date that is not finite: encoding one throws
///   `unencodable`, and a number too large for a `Double` (`1e400`) makes a frame `unreadable`. A
///   receiver therefore never stores an envelope with a non-finite stamp (F17 "Inputs from F05").
/// - No `Data` is larger than `frameLimit`: `encode` cuts an `.envelopes` frame into as many frames as it
///   takes, keeping the envelopes' order.
/// - A frame of a version this build does not read is refused whole (`unsupportedVersion`), never decoded
///   in part: a peer's newer event payload could otherwise fold into a different workout here (F17 "Inputs
///   from F10 S8a"; F05's unreadable rows). `version` rises whenever `EnvelopeCodec.version` does, or the shape
///   of `WireFrame` changes.
public enum WireCodec {
    /// The first byte of every frame.
    public static let magic: UInt8 = 0x4C
    /// The version `encode` writes, and the only one `decode` reads so far.
    public static let version: UInt8 = 1
    /// The largest `Data` `encode` returns. WatchConnectivity's `sendMessageData` was measured to take up to
    /// 65 536 bytes (R1 §2.6); mirroring documents no limit (R1 §2.4), so both use this bound.
    public static let frameLimit = 60000

    /// `frame` as one or more payloads of at most `frameLimit` bytes each. Only an `.envelopes` frame is ever
    /// cut, into frames of consecutive envelopes, so decoding the payloads in order gives back its envelopes in
    /// order.
    ///
    /// Throws `tooLarge` when one envelope alone, or a handshake or replay request, takes more than
    /// `frameLimit`, and `unencodable` when a date in the frame is not finite.
    public static func encode(_ frame: WireFrame) throws -> [Data] {
        let data = try payload(frame)
        guard data.count > frameLimit else {
            return [data]
        }
        guard case let .envelopes(envelopes) = frame, envelopes.count > 1 else {
            throw WireCodecError.tooLarge
        }
        let half = envelopes.count / 2
        return try encode(.envelopes(Array(envelopes[..<half]))) + encode(.envelopes(Array(envelopes[half...])))
    }

    /// The frame `data` holds. Throws `notAFrame` when it does not start with `magic` and a version byte,
    /// `unsupportedVersion` for a version this build does not read, and `unreadable` when the JSON after them is
    /// not a frame.
    public static func decode(_ data: Data) throws -> WireFrame {
        guard data.count >= 2, data[data.startIndex] == magic else {
            throw WireCodecError.notAFrame
        }
        let written = data[data.startIndex + 1]
        guard written == version else {
            throw WireCodecError.unsupportedVersion(written)
        }
        do {
            return try JSONDecoder().decode(WireFrame.self, from: data.dropFirst(2))
        } catch {
            throw WireCodecError.unreadable
        }
    }

    /// The header and JSON of one frame, whatever its size.
    private static func payload(_ frame: WireFrame) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try Data([magic, version]) + encoder.encode(frame)
        } catch {
            throw WireCodecError.unencodable
        }
    }
}

/// Why `WireCodec` refused a frame.
public enum WireCodecError: Error, Equatable, Sendable {
    /// The bytes do not start with `WireCodec.magic` and a version byte: not a Ledger frame.
    case notAFrame
    /// A frame written in a version this build does not read: a peer with another version of Ledger.
    case unsupportedVersion(UInt8)
    /// The JSON after the header is not a `WireFrame` of this version: damaged, or carrying a number no
    /// `Double` holds.
    case unreadable
    /// A frame that cannot be cut to `WireCodec.frameLimit` bytes: one envelope, a handshake or a replay
    /// request is larger on its own.
    case tooLarge
    /// A date in the frame is not finite, which JSON cannot carry.
    case unencodable
}
