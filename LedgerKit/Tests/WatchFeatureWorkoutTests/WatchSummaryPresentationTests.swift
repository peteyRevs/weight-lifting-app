import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The summary (spec §4.3, §5.1; F18 criterion 11, the pure half).
@Suite("Watch summary presentation", .tags(.watch))
struct WatchSummaryPresentationTests {
    static let locale = Fixtures.locale

    @Test("The summary: elapsed frozen at the end, sets done of all, and no records")
    func summary_tiles() throws {
        var workout = try WatchSample.loggedLowerA(.pounds(185), reps: 5, sets: 12)
        workout.endedAt = workout.startedAt.addingTimeInterval(45 * 60 + 30)
        let summary = WatchPresentation.summary(workout, records: [], health: nil, locale: Self.locale)
        #expect(summary.title == "WORKOUT DONE" && summary.done == "Done")
        #expect(summary.elapsed == "45:30" && summary.elapsedCaption == "ELAPSED")
        #expect(summary.sets == "12/15" && summary.setsCaption == "SETS")
        #expect(summary.volume == "11,100")
        #expect(summary.records == "0" && !summary.hasRecords && summary.recordsCaption == "NEW PR")
    }

    @Test("AVG BPM is the Health workout's average, and \"—\" without a record or without an average in it")
    func summary_averageHeartRate() throws {
        let workout = try WatchSample.loggedLowerA(.pounds(185), reps: 5)
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000F18B"))
        let record = { (average: Int?) in
            HealthWorkoutRecord(
                healthKitUUID: id, start: workout.startedAt, end: Fixtures.now.addingTimeInterval(3600),
                avgHeartRate: average, maxHeartRate: nil, activeEnergyKcal: nil
            )
        }
        let average = { (health: HealthWorkoutRecord?) in
            WatchPresentation.summary(workout, records: [], health: health, locale: Self.locale).averageHeartRate
        }
        #expect(average(nil) == "—" && average(record(nil)) == "—")
        #expect(average(record(138)) == "138")
        #expect(WatchPresentation.summary(workout, records: [], health: nil, locale: Self.locale)
            .averageHeartRateCaption == "AVG BPM")
    }

    @Test("NEW PR counts the workout's records and is marked while there is one")
    func summary_records() throws {
        let workout = try WatchSample.loggedLowerA(.pounds(185), reps: 5)
        let records = workout.exercises.prefix(2).map { exercise in
            PersonalRecord(
                exerciseID: exercise.exerciseID, kind: .weightAtReps(.pounds(185), Reps(clamping: 5)),
                previous: nil, achievedAt: workout.startedAt, workoutID: workout.id
            )
        }
        let summary = WatchPresentation.summary(workout, records: records, health: nil, locale: Self.locale)
        #expect(summary.records == "2" && summary.hasRecords)
    }

    @Test("VoiceOver reads each tile as one phrase, in pounds and in kilograms, with and without Health and records")
    func summary_spokenPhrases() throws {
        var workout = try WatchSample.loggedLowerA(.pounds(185), reps: 5, sets: 12)
        workout.endedAt = workout.startedAt.addingTimeInterval(45 * 60 + 30)
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000F18C"))
        let health = HealthWorkoutRecord(
            healthKitUUID: id, start: workout.startedAt, end: Fixtures.now,
            avgHeartRate: 138, maxHeartRate: nil, activeEnergyKcal: nil
        )
        let record = PersonalRecord(
            exerciseID: workout.exercises[0].exerciseID, kind: .weightAtReps(.pounds(185), Reps(clamping: 5)),
            previous: nil, achievedAt: workout.startedAt, workoutID: workout.id
        )
        let spoken = WatchPresentation.summary(workout, records: [record], health: health, locale: Self.locale).spoken
        #expect(spoken.elapsed == "45 minutes, 30 seconds elapsed" && spoken.sets == "12 of 15 sets logged")
        #expect(spoken.volume == "11,100 pounds moved")
        #expect(spoken.averageHeartRate == "Average heart rate, 138 beats per minute")
        #expect(spoken.records == "1 new personal record")
        let bare = WatchPresentation.summary(workout, records: [], health: nil, locale: Self.locale).spoken
        #expect(bare.averageHeartRate == "No average heart rate" && bare.records == "0 new personal records")
        workout.units = .kg
        let kg = WatchPresentation.summary(workout, records: [], health: nil, locale: Self.locale)
        #expect(kg.volumeCaption == "KG MOVED" && kg.spoken.volume.hasSuffix(" kilograms moved"))
    }
}
