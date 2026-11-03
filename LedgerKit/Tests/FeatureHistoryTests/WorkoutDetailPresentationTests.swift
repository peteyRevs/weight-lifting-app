@testable import FeatureHistory
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S2, criteria 3 and 7, N13's words and N14: a past workout's detail as the presentation makes it, word for word,
/// in pounds and in kilograms, with records and without, an exercise with nothing logged, a workout past an hour, the
/// day in the calendar's time zone, and each row's route.
@Suite("WorkoutDetailPresentation", .tags(.feature))
struct WorkoutDetailPresentationTests {
    static let recorded = DetailFixtures.twelve()
    static let bench = HistoryFixtures.bench
    static let squat = WorkoutRepositoryContract.exercises[1]

    /// The newest of the twelve: Friday, September 11, three sets of 5 at 190 lb, two records over the one before.
    static var newest: RecordedWorkout {
        get throws {
            try #require(recorded.last)
        }
    }

    /// Two sets of bench at 185 lb and a squat set left undone, 1 hour, 1 minute and 5 seconds long, started on
    /// Wednesday, September 16, 2026 at 02:00 UTC.
    static func pastAnHour() -> RecordedWorkout {
        var workout = Seeders.workout(
            number: 300,
            endedAt: Fixtures.date(2026, 9, 16, hour: 3, minute: 1),
            minutes: 61,
            [
                .straight(bench, sets: 2, reps: 5, pounds: 185),
                Seeders.ExerciseLog(squat, [.init(225, 5, done: false)])
            ]
        )
        workout.endedAt = workout.endedAt?.addingTimeInterval(5)
        return RecordedWorkout(workout: workout, records: [])
    }

    @Test("3. The header is the day the workout started over its name; the tiles read as F10's receipt writes them")
    func newest_inPounds_isTheReceipt() throws {
        let model = try WorkoutDetailPresentation.make(DetailFixtures.input(Self.newest))
        #expect(model.date == "Friday, September 11")
        #expect(model.title == "Upper B")
        let tiles = model.receipt.tiles.map { [$0.label, $0.value, $0.spoken] }
        #expect(tiles == [
            ["TIME", "58:00", "TIME, 58 minutes"],
            ["SETS", "3/3", "3 of 3 sets logged"],
            ["LB MOVED", "2,850", "2,850 lb moved"]
        ])
        #expect(model.receipt.tiles.map(\.isAccented) == [true, false, false], "TIME is the receipt's orange label")
        #expect(model.receipt.records == "2 new PRs this session")
        #expect(model.receipt.logged == "LOGGED")
        #expect(model.receipt.note == "Prescribed on the right")
    }

    @Test("3. A row is the Domain's, spoken with what each part is; it routes to its exercise's history")
    func rows_areTheDomains_andRouteToTheirExercise() throws {
        let stored = try Self.newest
        let model = WorkoutDetailPresentation.make(DetailFixtures.input(stored))
        let row = try #require(model.receipt.rows.first)
        let domain = ReceiptRow(exercise: stored.workout.exercises[0], units: .lb)
        #expect(row.name == Self.bench.name && row.target == domain.target)
        #expect(row.chips == ["3 × 190×5"])
        #expect(row.spoken == "\(Self.bench.name), Prescribed \(domain.target), Logged 3 × 190×5")
        #expect(model.rowRoutes == [.exercise(Self.bench.id)])
    }

    @Test("7. In kilograms every weight is the lifter's: the tile, its label and the chips")
    func kilograms_drawEveryWeightInKilograms() throws {
        let model = try WorkoutDetailPresentation.make(DetailFixtures.input(Self.newest, units: .kg))
        let moved = try #require(model.receipt.tiles.last)
        #expect([moved.label, moved.value, moved.spoken] == ["KG MOVED", "1,293", "1,293 kg moved"])
        #expect(model.receipt.rows.first?.chips == ["3 × 86.2×5"])
        #expect(model.receipt.rows.first?.target.hasSuffix(" kg") == true)
    }

    @Test("3. A workout with no record has no records line; one record is singular")
    func records_noneAndOne() throws {
        let first = try #require(Self.recorded.first)
        #expect(first.records.isEmpty)
        #expect(WorkoutDetailPresentation.make(DetailFixtures.input(first)).receipt.records == nil)
        let stored = try Self.newest
        let one = RecordedWorkout(workout: stored.workout, records: Array(stored.records.prefix(1)))
        #expect(WorkoutDetailPresentation.make(DetailFixtures.input(one)).receipt.records == "1 new PR this session")
    }

    @Test("An exercise with nothing logged reads a dash, spoken Nothing logged; past an hour reads 1:01:05")
    func skippedExercise_andPastAnHour() throws {
        let model = WorkoutDetailPresentation.make(DetailFixtures.input(Self.pastAnHour()))
        let time = try #require(model.receipt.tiles.first)
        #expect([time.value, time.spoken] == ["1:01:05", "TIME, 1 hour, 1 minute, 5 seconds"])
        #expect(model.receipt.tiles.dropFirst().first?.value == "2/3")
        let skipped = try #require(model.receipt.rows.last)
        #expect(skipped.chips == ["—"])
        #expect(skipped.spoken.hasSuffix(", Nothing logged"))
        #expect(model.rowRoutes == [.exercise(Self.bench.id), .exercise(Self.squat.id)])
    }

    @Test("N14. The day is the calendar's: 02:00 UTC is still Tuesday in Los Angeles")
    func date_isInTheCalendarsTimeZone() throws {
        var losAngeles = Fixtures.calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let input = DetailFixtures.input(Self.pastAnHour(), calendar: losAngeles)
        #expect(WorkoutDetailPresentation.make(input).date == "Tuesday, September 15")
        #expect(WorkoutDetailPresentation.make(DetailFixtures.input(Self.pastAnHour()))
            .date == "Wednesday, September 16")
    }

    @Test("Q8. Delete asks first, and a workout that can't be read still offers it")
    func deletion_andUnreadable() {
        let deletion = WorkoutDetailPresentation.deletion
        #expect([deletion.title, deletion.question, deletion.confirm, deletion.cancel] == [
            "Delete workout", "Delete this workout?", "Delete", "Cancel"
        ])
        #expect(deletion.message == "It's removed from your history, records and stats. This can't be undone.")
        let unreadable = WorkoutDetailPresentation.unreadable
        #expect(unreadable.title == "This workout can't be read.")
        #expect(unreadable.delete == deletion)
    }
}
