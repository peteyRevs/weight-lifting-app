@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7b, criteria 28 to 30, 32 and 34: the receipt as the presentation makes it, word for word, in pounds
/// and in kilograms; and that it is total.
@Suite("WorkoutPresentation receipt", .tags(.feature))
struct WorkoutPresentationReceiptTests {
    typealias Finish = WorkoutPresentationFinishTests

    /// `workout` finished `seconds` after its start, as the engine ends it.
    static func finished(_ workout: WorkoutState, after seconds: TimeInterval) throws -> WorkoutState {
        let end = workout.startedAt.addingTimeInterval(seconds)
        let envelope = EventEnvelope(
            event: .finished(endedAt: end),
            workoutID: workout.id,
            device: workout.originDevice,
            seq: 1000,
            wallClock: end
        )
        return try #require(WorkoutEngine.reduce(workout, envelope).0)
    }

    static func receipt(
        _ finished: WorkoutState,
        records: [PersonalRecord] = [],
        locale: Locale = Fixtures.locale,
        calendar: Calendar = Fixtures.calendar
    ) -> ReceiptScreenModel {
        WorkoutPresentation.receipt(finished, records: records, locale: locale, calendar: calendar)
    }

    /// `count` records of the workout's first exercise.
    static func records(_ count: Int, of workout: WorkoutState) -> [PersonalRecord] {
        (0 ..< count).map { index in
            PersonalRecord(
                exerciseID: workout.exercises[0].exerciseID,
                kind: .weightAtReps(.pounds(Decimal(200 + index)), Reps(clamping: 5)),
                previous: nil,
                achievedAt: workout.startedAt,
                workoutID: workout.id
            )
        }
    }

    /// The brief's receipt: 23 of 25 sets, 24,180 lb, 24 minutes and 22 seconds.
    static func briefs() throws -> WorkoutState {
        let weights = Array(repeating: Weight.pounds(210), count: 22) + Array(repeating: .pounds(216), count: 3)
        return try finished(Finish.workout(weights, done: 23), after: 24 * 60 + 22)
    }

    @Test("The receipt reads as the brief writes it: the date, the name, Done and the three tiles")
    func receipt_isTheBriefs() throws {
        let workout = try Self.briefs()
        let model = Self.receipt(workout, records: Self.records(1, of: workout))
        let isHeader = model.header == ReceiptHeaderModel(
            date: "Wednesday, September 16", title: workout.name, done: "Done"
        )
        #expect(isHeader)
        let tiles = model.page.tiles.map { [$0.label, $0.value, $0.spoken] }
        #expect(tiles == [
            ["TIME", "24:22", "TIME, 24 minutes, 22 seconds"],
            ["SETS", "23/25", "23 of 25 sets logged"],
            ["LB MOVED", "24,180", "24,180 lb moved"]
        ])
        #expect(model.page.tiles.map(\.isAccented) == [true, false, false], "TIME is the orange label")
        #expect(model.page.records == "1 new PR this session")
        #expect(model.page.logged == "LOGGED")
        #expect(model.page.note == "Prescribed on the right")
    }

    @Test("The rows are the Domain's: name, target and one chip for each run; spoken with what each is")
    func rows_areTheDomains() throws {
        let workout = try Self.briefs()
        let rows = Self.receipt(workout).page.rows
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.name == workout.exercises[0].name)
        #expect(row.target == "5 × 5 @ 200 lb")
        #expect(row.chips == ["22 × 210×5", "216×5"])
        #expect(row.spoken == "\(row.name), Prescribed 5 × 5 @ 200 lb, Logged 22 × 210×5, 216×5")

        // Nothing logged: the Domain's dash, read as words.
        let none = try Self.finished(Finish.workout([.pounds(185), .pounds(185)], done: 0), after: 60)
        let empty = try #require(Self.receipt(none).page.rows.first)
        #expect(empty.chips == ["—"])
        #expect(empty.spoken == "\(empty.name), Prescribed 5 × 5 @ 200 lb, Nothing logged")
    }

    @Test("In kilograms: KG MOVED, the Domain's volume and chips")
    func receipt_inKilograms() throws {
        let model = try #require(ReceiptPreview.kilograms.model)
        let moved = try #require(model.page.tiles.last)
        #expect([moved.label, moved.value, moved.spoken] == ["KG MOVED", "160", "160 kg moved"])
        #expect(model.page.rows.last?.chips == ["10×16"])
        #expect(model.page.rows.last?.target == "3 × 16 @ 10 kg")
        #expect(model.page.records == nil)
    }

    @Test("Past an hour the time reads h:mm:ss, and is spoken in hours, minutes and seconds")
    func receipt_pastAnHour() throws {
        let model = try #require(ReceiptPreview.noRecords.model)
        let time = try #require(model.page.tiles.first)
        #expect(time.value == "1:01:05")
        #expect(time.spoken == "TIME, 1 hour, 1 minute, 5 seconds")
        #expect(model.page.tiles[1].value == "15/18")
    }

    @Test("The records line counts the records, in the plural form its number takes; none draws no line")
    func recordsLine_countsTheRecords() throws {
        let workout = try Self.briefs()
        #expect(Self.receipt(workout).page.records == nil)
        #expect(Self.receipt(workout, records: Self.records(3, of: workout)).page.records == "3 new PRs this session")
    }

    @Test("The spoken time is rounded down to the second, as the tile's is")
    func spokenTime_isRoundedDown() {
        let locale = Fixtures.locale
        #expect(WorkoutPresentation.spokenElapsed(.milliseconds(59900), locale: locale) == "59 seconds")
        #expect(WorkoutPresentation.spokenElapsed(.seconds(3600), locale: locale) == "1 hour")
        #expect(ClockText.elapsed(.milliseconds(59900)) == "0:59")
    }

    @Test("The date is the day the workout started, in the handed calendar's zone and the handed locale")
    func date_isTheStartsDay() throws {
        var workout = try Self.briefs()
        workout.startedAt = Fixtures.now.addingTimeInterval(16 * 3600) // 21:20 on the 16th, UTC
        var tokyo = Fixtures.calendar
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(Self.receipt(workout).header.date == "Wednesday, September 16")
        #expect(Self.receipt(workout, calendar: tokyo).header.date == "Thursday, September 17")
        let french = Self.receipt(workout, locale: Locale(identifier: "fr_FR")).header.date
        #expect(french == "mercredi 16 septembre")
    }

    @Test("Total: no exercise, no volume and a start that is not a date all give a receipt")
    func receipt_isTotal() throws {
        var empty = try Self.briefs()
        empty.exercises = []
        let model = Self.receipt(empty)
        #expect(model.page.tiles.map(\.value) == ["24:22", "0/0", "0"])
        #expect(model.page.tiles.map(\.spoken).last == "0 lb moved")
        #expect(model.page.rows.isEmpty)

        var lost = try Self.briefs()
        lost.startedAt = Date(timeIntervalSinceReferenceDate: .nan)
        let unreadable = Self.receipt(lost)
        #expect(unreadable.header.date == "")
        #expect(unreadable.page.tiles.first?.value == "0:00")
        #expect(unreadable.page.tiles.first?.spoken == "TIME, 0 seconds")

        var forever = try Self.briefs()
        forever.startedAt = Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude)
        let long = Self.receipt(forever)
        #expect(long.page.tiles.first?.value.isEmpty == false, "a saturated time is written, not trapped on")
    }
}
