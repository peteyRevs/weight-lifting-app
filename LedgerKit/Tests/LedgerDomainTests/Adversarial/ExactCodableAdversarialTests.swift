import Foundation
@testable import LedgerDomain
import Testing

/// ADR-007 Codable shapes: `{"grams": "<exact decimal>"}`, `{"gramReps": "<exact decimal>"}` and
/// `"YYYY-MM-DD"`. Decoding accepts only those shapes, so malformed input must throw, never parse
/// a prefix or go through `Double`.
@Suite("Exact Codable shapes (adversarial, ADR-007)", .tags(.domain))
struct ExactCodableAdversarialTests {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func object(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    static let malformedNumbers = [
        "{\"grams\": 83914.58845}", "{\"grams\": \"abc\"}", "{\"grams\": \"\"}", "{\"grams\": \"12abc\"}",
        "{\"grams\": \"1.2.3\"}", "{\"grams\": \"NaN\"}", "{\"grams\": \"1,5\"}", "{\"grams\": null}", "{}",
        "\"83914.58845\"", "83914.58845", "{\"grams\": \"--1\"}", "{\"grams\": \"0x10\"}", "{\"grams\": \"1 2\"}"
    ]
}

extension ExactCodableAdversarialTests {
    @Test("A weight encodes as its exact decimal text under \"grams\" (ADR-007).")
    func weight_encodesExactDecimalString() throws {
        #expect(try Self.object(pounds("185"))["grams"] as? String == "83914.58845")
        #expect(try Self.object(Weight.zero)["grams"] as? String == "0")
        #expect(try Self.object(pounds("-0.001"))["grams"] as? String == "-0.45359237")
        #expect(try Self.object(pounds("185")).count == 1)
    }

    @Test(
        "Exact weights survive a Codable round-trip digit for digit.",
        arguments: [
            "83914.58845", "0.0000001", "-0.45359237", "12345678901234567890.1234567", "1e-20", "1e30",
            "0.33333333333333333333333333333333333333", "1133.9809250"
        ]
    )
    func weight_roundTrip_isExact(grams: String) throws {
        let weight = Weight(grams: dec(grams))
        let decoded = try Adversarial.roundTrip(weight)
        #expect(decoded == weight)
        #expect(decoded.grams == weight.grams)
        #expect(decoded.hashValue == weight.hashValue)
    }

    @Test("A weight built from pounds or a third of a pound round-trips exactly.")
    func weight_roundTrip_derivedValues() throws {
        let third = Weight.pounds(Decimal(1) / Decimal(3))
        #expect(try Adversarial.roundTrip(third) == third)
        #expect(try Adversarial.roundTrip(pounds("242.5").scaled(by: dec("0.85"))) == pounds("206.125"))
    }

    @Test(
        "Malformed weight JSON is rejected: numbers, garbage, partial numbers, NaN, wrong shapes.",
        arguments: malformedNumbers
    )
    func weight_malformed_throws(json: String) {
        #expect(throws: (any Error).self) { try Self.decode(Weight.self, json) }
    }

    @Test("Malformed volume JSON is rejected the same way.", arguments: malformedNumbers)
    func volume_malformed_throws(json: String) {
        let volume = json.replacingOccurrences(of: "\"grams\"", with: "\"gramReps\"")
        #expect(throws: (any Error).self) { try Self.decode(Volume.self, volume) }
    }

    @Test("A volume encodes as exact decimal text under \"gramReps\" and round-trips.")
    func volume_encodesExactDecimalString() throws {
        let volume = try Volume(weight: pounds("185"), reps: Fixtures.reps(5))
        #expect(try Self.object(volume)["gramReps"] as? String == "419572.94225")
        #expect(try Adversarial.roundTrip(volume) == volume)
        #expect(try Self.decode(Volume.self, "{\"gramReps\": \"419572.94225\"}") == volume)
    }

    @Test("A weight decodes from exact text inside a larger model (Slot start load).")
    func weight_decodesInsideSlot() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 2100, startLoad: pounds("185"), step: pounds("1.25"))
        let tampered = try Adversarial.tampered(slot) { $0["startLoad"] = ["grams": "83914.58845"] }
        #expect(try JSONDecoder().decode(Slot.self, from: tampered).startLoad == pounds("185"))
        let numeric = try Adversarial.tampered(slot) { $0["startLoad"] = ["grams": 83914.58845] }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Slot.self, from: numeric) }
    }

    @Test("A program's start date encodes as \"YYYY-MM-DD\" and rejects impossible or badly shaped dates.")
    func program_startDate_shape() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA()])
        #expect(try Self.object(program)["startDate"] as? String == "2026-08-17")
        let shapes: [Any] = ["2026-02-30", "2026-8-17", "2026-08-17T00:00:00Z", "17/08/2026", 20_260_817]
        for bad in shapes {
            let data = try Adversarial.tampered(program) { $0["startDate"] = bad }
            #expect(throws: (any Error).self, "\(bad)") { try JSONDecoder().decode(Program.self, from: data) }
        }
    }
}
