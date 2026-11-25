import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F17 S1: what `WireCodec` refuses to write or read (criterion 3 as resolved, and the non-finite dates of F17
/// "Inputs from F04 / F05").
@Suite("WireCodec refusals", .tags(.domain))
struct WireCodecRefusalTests {
    // MARK: Criterion 3, as resolved (implementation notes, S1)

    @Test("Criterion 3: a version-2 frame with an event this build does not know is refused whole")
    func decode_refusesANewerVersion() throws {
        let json = #"{"envelopes":{"_0":[{"device":"00000000-0000-0000-0000-00000000F002","#
            + #""event":{"setFlagged":{"exerciseIndex":0}},"seq":2,"wallClock":811228800,"#
            + #""workoutID":"00000000-0000-0000-0000-00000000F100"}]}}"#
        #expect(throws: WireCodecError.unsupportedVersion(2)) {
            try WireCodec.decode(WireCodecTests.frame(json, version: 2))
        }
        #expect(throws: WireCodecError.unreadable) {
            try WireCodec.decode(WireCodecTests.frame(json))
        }
        let known = try #require(try WireCodec.encode(.envelopes(WireCodecTests.setsLogged(1))).first)
        #expect(throws: WireCodecError.unsupportedVersion(2)) {
            try WireCodec.decode(Data([WireCodec.magic, 2]) + known.dropFirst(2))
        }
        #expect(throws: WireCodecError.unsupportedVersion(0)) {
            try WireCodec.decode(Data([WireCodec.magic, 0]) + known.dropFirst(2))
        }
    }

    // MARK: What no frame carries

    @Test("A date that is not finite cannot be encoded, in the stamp or in the payload")
    func encode_refusesNonFiniteDates() {
        let stamp = EventBuilders.envelope(.restSkipped, seq: 2, at: Date(timeIntervalSinceReferenceDate: .infinity))
        let done = Engine.envelope(
            .finished(endedAt: Date(timeIntervalSinceReferenceDate: .nan)), 30, seq: 3
        )
        for envelope in [stamp, done] {
            #expect(throws: WireCodecError.unencodable) {
                try WireCodec.encode(.envelopes(WireCodecTests.setsLogged(2) + [envelope]))
            }
        }
    }

    @Test("A number no Double holds makes the frame unreadable, so no non-finite stamp is ever stored")
    func decode_refusesAnOverflowingDate() throws {
        let payload = try #require(try WireCodec.encode(.envelopes(WireCodecTests.setsLogged(1))).first)
        let text = try #require(String(bytes: payload.dropFirst(2), encoding: .utf8))
        let stamp = try #require(text.firstRange(of: #/"wallClock":[0-9.e+-]+/#))
        let overflowing = text.replacingCharacters(in: stamp, with: #""wallClock":1e400"#)
        #expect(throws: WireCodecError.unreadable) {
            try WireCodec.decode(WireCodecTests.frame(overflowing))
        }
        let negative = text.replacingCharacters(in: stamp, with: #""wallClock":-1e400"#)
        #expect(throws: WireCodecError.unreadable) {
            try WireCodec.decode(WireCodecTests.frame(negative))
        }
    }

    @Test("Bytes that are not a Ledger frame are refused: empty, a header alone, another magic, not JSON")
    func decode_refusesWhatIsNotAFrame() {
        for bytes in [Data(), Data([WireCodec.magic]), Data([0x7B, 0x01]) + Data("{}".utf8), Data([0x4D, 0x01])] {
            #expect(throws: WireCodecError.notAFrame) {
                try WireCodec.decode(bytes)
            }
        }
        for json in ["", "{}", "[]", "not json", #"{"envelopes":{"_0":[{}]}}"#, #"{"handshake":{}}"#] {
            #expect(throws: WireCodecError.unreadable, "\(json)") {
                try WireCodec.decode(WireCodecTests.frame(json))
            }
        }
    }
}
