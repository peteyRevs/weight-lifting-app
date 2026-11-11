import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("Adversarial F10 S8a · the swap event's payload", .tags(.domain))
struct SwapPayloadAdversarialTests {
    /// The committed version-1 fixture's text, byte for byte (`payload-v001/event-exerciseSwapped.json`).
    static let versionOne = """
    {
      "device" : "00000000-0000-0000-0000-000000000D01",
      "event" : {
        "exerciseSwapped" : {
          "alsoUpdateProgram" : true,
          "exerciseID" : "00000000-0000-0000-0000-000000000E02",
          "exerciseIndex" : 0,
          "name" : "Incline DB Press"
        }
      },
      "seq" : 6,
      "wallClock" : 811228840,
      "workoutID" : "00000000-0000-0000-0000-000000000100"
    }
    """

    @Test("A version-1 swap without the key decodes with no replacement, and so does an explicit null")
    func decode_versionOne_hasNoReplacement() throws {
        for text in [Self.versionOne, Self.versionOne.replacingOccurrences(
            of: "\"name\" : \"Incline DB Press\"",
            with: "\"name\" : \"Incline DB Press\", \"replacement\" : null"
        )] {
            let envelope = try EnvelopeCodec.decode(Data(text.utf8), version: 1)
            guard case let .exerciseSwapped(index, _, name, program, replacement) = envelope.event else {
                Issue.record("not a swap")
                continue
            }
            #expect(index == 0 && name == "Incline DB Press" && program)
            #expect(replacement == nil)
        }
    }

    @Test("A swap without a replacement encodes to exactly the version-1 keys: an old peer reads it unchanged")
    func encode_noReplacement_writesTheVersionOneKeys() throws {
        let decoded = try EnvelopeCodec.decode(Data(Self.versionOne.utf8), version: 1)
        let written = try EnvelopeCodec.encode(decoded)
        let object = try JSONSerialization.jsonObject(with: written) as? [String: Any]
        let event = object?["event"] as? [String: Any]
        let swap = event?["exerciseSwapped"] as? [String: Any]
        #expect(swap.map { Set($0.keys) } == ["alsoUpdateProgram", "exerciseID", "exerciseIndex", "name"])
        let same = try EnvelopeCodec.decode(written, version: 1) == decoded
        #expect(same)
    }

    @Test("A swap with a replacement round-trips through the codec, every field and a nil and a dated Last")
    func roundTrip_withReplacement_isExact() throws {
        let lasts: [LastPerformance?] = try [
            nil,
            LastPerformance(
                date: Date(timeIntervalSince1970: 1_789_000_000.123_456),
                sets: 3,
                reps: 8,
                load: Weight(grams: SwapAdv.dec("27215.5422"))
            )
        ]
        for last in lasts {
            for equipment in Equipment.allCases {
                let swap = try SwapAdv.replacement(
                    equipment,
                    step: .kilograms(2),
                    load: .pounds(SwapAdv.dec("52.5")),
                    last: last
                )
                let envelope = EventBuilders.envelope(
                    SwapAdv.swap(1, program: true, swap),
                    seq: 7,
                    at: EventBuilders.start
                )
                let back = try EnvelopeCodec.decode(EnvelopeCodec.encode(envelope), version: 1)
                let same = back == envelope
                #expect(same, "\(equipment) \(last == nil ? "no last" : "last")")
            }
        }
    }

    @Test("Hostile JSON: a NaN-dated Last, a zero, a negative step, a negative load: decoded, then ignored")
    func hostileJSON_isIgnoredByTheEngine() throws {
        let base = """
        {"device":"\(EventBuilders.phone.rawValue.uuidString)","seq":2,"wallClock":1,
        "workoutID":"\(EventBuilders.workoutID.rawValue.uuidString)","event":{"exerciseSwapped":{
        "alsoUpdateProgram":true,"exerciseID":"00000000-0000-0000-0000-00000000EEA1","exerciseIndex":0,
        "name":"X","replacement":{"equipment":"dumbbell","step":{"grams":"STEP"},"load":{"grams":"LOAD"}LAST}}}}
        """
        let cases: [[String]] = [
            [
                "1133.98",
                "27215.5",
                ",\"lastPerformance\":{\"date\":\"NaN\",\"sets\":1,\"reps\":1,\"load\":{\"grams\":\"1\"}}"
            ],
            [
                "1133.98",
                "27215.5",
                ",\"lastPerformance\":{\"date\":\"+Infinity\",\"sets\":1,\"reps\":1,\"load\":{\"grams\":\"1\"}}"
            ],
            ["0", "27215.5", ""],
            ["-1133.98", "27215.5", ""],
            ["1133.98", "-0.0000001", ""]
        ]
        let start = SwapAdv.session()
        let started = EventBuilders.envelope(.started(start), seq: 1, at: Date(timeIntervalSince1970: 0))
        for item in cases {
            let (step, load, last) = (item[0], item[1], item[2])
            let text = base.replacingOccurrences(of: "STEP", with: step)
                .replacingOccurrences(of: "LOAD", with: load)
                .replacingOccurrences(of: "LAST", with: last)
            let envelope = try EnvelopeCodec.decode(Data(text.utf8), version: 1)
            let (state, effects) = WorkoutEngine.reduce(start, envelope)
            let unchanged = state == start && WorkoutEngine.replay([started, envelope]) == start
            #expect(unchanged && effects.isEmpty, "step \(step) load \(load) \(last.prefix(40))")
        }
    }

    @Test("Equipment the app does not know, or a load given as a number: the decode throws, nothing traps")
    func unreadableReplacement_throws() {
        let texts = [
            #"{"equipment":"trapbar","step":{"grams":"1"},"load":{"grams":"1"}}"#,
            #"{"equipment":"barbell","step":{"grams":1},"load":{"grams":"1"}}"#,
            #"{"equipment":"barbell","step":{"grams":"NaN"},"load":{"grams":"1"}}"#,
            #"{"equipment":"barbell","step":{"grams":"1e3"},"load":{"grams":"1"}}"#,
            #"{"equipment":"barbell","load":{"grams":"1"}}"#
        ]
        for text in texts {
            #expect(throws: (any Error).self, "\(text)") {
                try JSONDecoder().decode(SwappedExercise.self, from: Data(text.utf8))
            }
        }
    }
}
