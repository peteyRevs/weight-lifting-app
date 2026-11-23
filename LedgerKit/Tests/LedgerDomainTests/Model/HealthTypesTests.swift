import Foundation
@testable import LedgerDomain
import Testing

/// The values `HealthStore` trades in (F16): Foundation-only, `Sendable`, and shaped as Health and the
/// `workout_health` row keep them.
@Suite("Health types", .tags(.domain))
struct HealthTypesTests {
    static func isSendable(_: some Sendable) -> Bool {
        true
    }

    @Test("Authorization statuses compare by case and cross isolation")
    func healthAuthorization_isEquatableAndSendable() {
        let all: [HealthAuthorization] = [.notDetermined, .authorized, .denied, .unavailable]
        #expect(Set(all).count == 4)
        #expect(HealthAuthorization.authorized != .denied)
        #expect(Self.isSendable(HealthAuthorization.unavailable))
    }

    @Test("The metadata's volume is exact grams, whatever unit it was logged in")
    func healthWorkoutMetadata_volumeIsGrams() {
        func metadata(_ volume: Weight) -> HealthWorkoutMetadata {
            HealthWorkoutMetadata(
                workoutID: WorkoutID(Fixtures.uuid(1)),
                programName: "Strength",
                dayName: "Day A",
                totalVolume: volume,
                doneSets: 12
            )
        }
        #expect(metadata(.kilograms(1250)).totalVolumeGrams == 1_250_000)
        #expect(metadata(.pounds(185)).totalVolumeGrams == dec("83914.58845"))
        #expect(metadata(.zero).totalVolumeGrams == 0)
    }

    @Test("A workout record round-trips through JSON, a missing heart rate included")
    func healthWorkoutRecord_roundTrips() throws {
        let record = HealthWorkoutRecord(
            healthKitUUID: Fixtures.uuid(7),
            start: Fixtures.now,
            end: Fixtures.now.addingTimeInterval(3600),
            avgHeartRate: nil,
            maxHeartRate: 151,
            activeEnergyKcal: 240
        )
        let decoded = try JSONDecoder().decode(HealthWorkoutRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(decoded.avgHeartRate == nil)
    }
}
