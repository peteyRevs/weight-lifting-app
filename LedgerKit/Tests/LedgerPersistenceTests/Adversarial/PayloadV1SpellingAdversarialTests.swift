import Foundation
import LedgerDomain
import Testing

/// F05 S1 adversarial round 3 (close-out), on review SF1's golden fixtures. `Fixtures/payload-v001/` holds one
/// value of each enum a version-1 payload can carry (`barbell`, `live`, …), so renaming any other case (say
/// `Equipment.dumbbell`) passed every test and would have stranded the rows that hold it. This pins how version 1
/// spells every value. A failure means a LedgerDomain change altered version 1: ship it as payload version 2
/// (`PayloadV1`). A new case fails until it is listed here: decide then whether it needs version 2, since an
/// older app cannot read it.
@Suite("Adversarial S1 round 3 · version-1 enum spellings", .tags(.persistence))
struct PayloadV1SpellingAdversarialTests {
    @Test("Every equipment, set kind, phase, unit and weekday keeps its version-1 spelling")
    func everyEnumValue_keepsItsVersion1Spelling() throws {
        try Self.expect([
            .barbell: #""barbell""#, .dumbbell: #""dumbbell""#, .cable: #""cable""#, .machine: #""machine""#,
            .bodyweight: #""bodyweight""#, .kettlebell: #""kettlebell""#, .band: #""band""#
        ] as [Equipment: String])
        try Self.expect([
            .working: #""working""#, .drop: #""drop""#, .added: #""added""#, .warmup: #""warmup""#
        ] as [SetKind: String])
        try Self.expect([
            .live: #""live""#, .finished: #""finished""#, .discarded: #""discarded""#
        ] as [WorkoutPhase: String])
        try Self.expect([.lb: #""lb""#, .kg: #""kg""#] as [Units: String])
        try Self.expect([
            .monday: "1", .tuesday: "2", .wednesday: "3", .thursday: "4", .friday: "5", .saturday: "6", .sunday: "7"
        ] as [Weekday: String])
    }

    /// Every case of `Value` is listed, encodes as its JSON, and decodes from it.
    static func expect<Value: Codable & CaseIterable & Hashable>(
        _ spellings: [Value: String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(Set(Value.allCases) == Set(spellings.keys), "\(Value.self)", sourceLocation: sourceLocation)
        for (value, json) in spellings {
            let encoded = try String(bytes: JSONEncoder().encode([value]), encoding: .utf8)
            #expect(encoded == "[\(json)]", "\(Value.self).\(value)", sourceLocation: sourceLocation)
            let decoded = try JSONDecoder().decode([Value].self, from: Data("[\(json)]".utf8))
            #expect(decoded == [value], "\(Value.self).\(value)", sourceLocation: sourceLocation)
        }
    }
}
