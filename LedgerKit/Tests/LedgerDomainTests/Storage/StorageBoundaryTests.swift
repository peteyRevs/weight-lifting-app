import Foundation
import LedgerDomain
import Testing

/// `StorageBoundary` and the two codecs: what every store keeps, and how (ADR-007; F07 S1 fix round 1, the rule
/// the GRDB columns and LedgerFakes share). The repository contracts' storage clauses hold each store to it.
@Suite("Storage boundary", .tags(.domain))
struct StorageBoundaryTests {
    @Test(
        "A weight is a whole count of 10⁻⁷ g within Int64, exactly",
        arguments: [("185 lb", "83914.58845", 839_145_884_500), ("0", "0", 0), ("−1 g", "-1", -10_000_000)]
    )
    func units_areExact(_ what: String, _ grams: String, _ units: Int64) throws {
        let value = try #require(Decimal(string: grams), "\(what)")
        #expect(try StorageBoundary.units(ofGrams: value) == units)
        #expect(StorageBoundary.grams(units: units) == value)
    }

    @Test("⅛ lb, NaN and a mass beyond Int64 units throw inexactWeight with the grams given")
    func inexactWeights_areRefused() throws {
        let eighth = try Weight.pounds(#require(Decimal(string: "0.125")))
        let huge = Weight.kilograms(1_000_000_000)
        #expect(throws: RepositoryError.inexactWeight(eighth.grams)) { try eighth.checkStorable() }
        #expect(throws: RepositoryError.inexactWeight(huge.grams)) { try huge.checkStorable() }
        #expect(throws: RepositoryError.self) { try Weight(grams: .nan).checkStorable() }
        let volume = Volume(weight: eighth, reps: Reps(clamping: 5))
        #expect(throws: RepositoryError.inexactWeight(volume.gramReps)) { try volume.checkStorable() }
        #expect(throws: Never.self) { try Volume(weight: .pounds(185), reps: Reps(clamping: 5)).checkStorable() }
        #expect(throws: Never.self) { try Weight.pounds(185).checkStorable() }
    }

    @Test("A date is finite seconds since 2001; ±∞ and NaN throw nonFiniteDate", arguments: [
        Double.infinity, -.infinity, .nan
    ])
    func nonFiniteDates_areRefused(_ seconds: Double) throws {
        #expect(throws: RepositoryError.nonFiniteDate) {
            try StorageBoundary.seconds(Date(timeIntervalSinceReferenceDate: seconds))
        }
        #expect(try StorageBoundary.seconds(Date(timeIntervalSinceReferenceDate: 12.5)) == 12.5)
    }

    @Test("Settings round-trip through their encoding, plates normalised; NaN and later versions are refused")
    func settingsCodec_roundTrips() throws {
        var settings = Settings.default
        settings.plateInventory[.lb]?.plates = [.pounds(5), .pounds(45), .pounds(5), .zero]
        let stored = try SettingsCodec.decode(SettingsCodec.encode(settings), version: SettingsCodec.version)
        #expect(stored.plateInventory[.lb]?.plates == [.pounds(45), .pounds(5)])
        settings.plateInventory[.kg] = PlateInventory(bar: Weight(grams: .nan), plates: [])
        #expect(throws: EncodingError.self) { try SettingsCodec.encode(settings) }
        #expect(throws: RepositoryError.unknownPayloadVersion(2)) {
            try SettingsCodec.decode(Data("{}".utf8), version: 2)
        }
    }

    @Test("Envelopes round-trip through their encoding, non-finite stamps included; NaN weights are refused")
    func envelopeCodec_roundTrips() throws {
        let workout = WorkoutID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7)))
        let device = DeviceID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8)))
        let skipped = EventEnvelope(
            event: .restSkipped,
            workoutID: workout,
            device: device,
            seq: 1,
            wallClock: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        let payload = try EnvelopeCodec.encode(skipped)
        #expect(try EnvelopeCodec.decode(payload, version: EnvelopeCodec.version) == skipped)
        #expect(throws: RepositoryError.unknownPayloadVersion(9)) { try EnvelopeCodec.decode(payload, version: 9) }
        let logged = EventEnvelope(
            event: .setLogged(
                exerciseIndex: 0,
                setID: SetID(device.rawValue),
                weight: Weight(grams: .nan),
                reps: Reps(clamping: 5),
                doneAt: .distantPast
            ),
            workoutID: workout,
            device: device,
            seq: 2,
            wallClock: .distantPast
        )
        #expect(throws: EncodingError.self) { try EnvelopeCodec.encode(logged) }
    }
}
