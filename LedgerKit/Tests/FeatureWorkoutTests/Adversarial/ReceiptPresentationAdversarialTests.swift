@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7b criteria 29, 30, 32 and 34 under attack: `WorkoutPresentation.receipt` is total and adds
/// nothing of its own. Ends before the start, starts that are not dates, a second's fraction, counts of one,
/// volumes past a million, other locales, and a property over random logs: a row is spoken as "Nothing
/// logged" exactly when the Domain draws its dash.
@Suite("Workout receipt presentation (adversarial)", .tags(.feature))
struct ReceiptPresentationAdversarialTests {
    typealias Finish = WorkoutPresentationFinishTests
    typealias Presentation = WorkoutPresentationReceiptTests

    static func receipt(
        _ workout: WorkoutState,
        records: Int = 0,
        locale: Locale = Fixtures.locale
    ) -> ReceiptScreenModel {
        WorkoutPresentation.receipt(
            workout,
            records: Presentation.records(records, of: workout),
            locale: locale,
            calendar: Fixtures.calendar
        )
    }

    @Test("An end before the start, an end under a second, and no end at all read 0:00, spoken as 0 seconds")
    func degenerateTimes_readZero() throws {
        let base = try Finish.workout([.pounds(100)], done: 1)
        var early = try Presentation.finished(base, after: 0)
        early.endedAt = base.startedAt.addingTimeInterval(-90)
        var fraction = try Presentation.finished(base, after: 0.4)
        fraction.endedAt = base.startedAt.addingTimeInterval(0.4)
        var none = try Presentation.finished(base, after: 0)
        none.endedAt = nil
        for workout in [early, fraction, none] {
            let time = try #require(Self.receipt(workout).page.tiles.first)
            #expect(time.value == "0:00")
            #expect(time.spoken == "TIME, 0 seconds")
        }
    }

    @Test("A start at either infinity gives a receipt: no date, a time that is written")
    func infiniteStart_givesAReceipt() throws {
        for start in [Double.infinity, -.infinity] {
            var workout = try Presentation.finished(Finish.workout([.pounds(100)], done: 1), after: 60)
            workout.startedAt = Date(timeIntervalSinceReferenceDate: start)
            let model = Self.receipt(workout)
            #expect(model.header.date == "")
            #expect(model.page.tiles.first?.value.isEmpty == false)
            #expect(model.page.tiles.first?.spoken.hasPrefix("TIME, ") == true)
        }
    }

    @Test("One set of one: the singular form; one record: the singular; two: the plural")
    func countsOfOne() throws {
        let one = try Presentation.finished(Finish.workout([.pounds(100)], done: 1), after: 60)
        let sets = try #require(Self.receipt(one).page.tiles.dropFirst().first)
        #expect([sets.value, sets.spoken] == ["1/1", "1 of 1 set logged"])
        #expect(Self.receipt(one, records: 1).page.records == "1 new PR this session")
        #expect(Self.receipt(one, records: 2).page.records == "2 new PRs this session")
        #expect(Self.receipt(one, records: 0).page.records == nil)
    }

    @Test("Volumes past a million are grouped, in pounds and in kilograms, and spoken with their units")
    func bigVolumes_areGrouped() throws {
        let pounds = try Presentation.finished(
            Finish.workout(Array(repeating: .pounds(1000), count: 247), done: 247),
            after: 60
        )
        let moved = try #require(Self.receipt(pounds).page.tiles.last)
        #expect([moved.label, moved.value, moved.spoken] == ["LB MOVED", "1,235,000", "1,235,000 lb moved"])

        let kilograms = try Presentation.finished(
            Finish.workout(Array(repeating: .kilograms(Decimal(4025) / 10), count: 600), done: 600, units: .kg),
            after: 60
        )
        let kg = try #require(Self.receipt(kilograms).page.tiles.last)
        #expect([kg.label, kg.value, kg.spoken] == ["KG MOVED", "1,207,500", "1,207,500 kg moved"])
        #expect(Self.receipt(kilograms).page.rows.first?.chips == ["600 × 402.5×5"])
    }

    @Test("Right-to-left and other locales give a receipt whose Domain lines keep their characters")
    func otherLocales_keepTheDomainsLines() throws {
        let workout = try Presentation.briefs()
        let english = Self.receipt(workout)
        for identifier in ["ar", "he_IL", "fa_IR", "ja_JP", "de_DE"] {
            let model = Self.receipt(workout, records: 1, locale: Locale(identifier: identifier))
            #expect(model.page.tiles.first?.value == "24:22", "\(identifier): the clock is the Domain's")
            #expect(model.page.tiles.last?.value == english.page.tiles.last?.value, "\(identifier): the volume")
            #expect(model.page.rows.map(\.chips) == english.page.rows.map(\.chips), "\(identifier): the chips")
            #expect(model.page.rows.map(\.target) == english.page.rows.map(\.target), "\(identifier): the targets")
            #expect(!model.header.date.isEmpty, "\(identifier)")
            #expect(model.page.tiles.allSatisfy { !$0.spoken.isEmpty }, "\(identifier)")
        }
    }

    @Test("The name is the workout's as stored, however long; the presentation is pure: twice is the same")
    func longName_pure() throws {
        var workout = try Presentation.briefs()
        workout.name = String(repeating: "Upper A — Push focus ", count: 20)
        let first = Self.receipt(workout, records: 2)
        #expect(first.header.title == workout.name)
        #expect(first == Self.receipt(workout, records: 2))
    }

    /// Property: over random logs of three exercises (sets done or not, working or warm-up), there is one row
    /// per exercise in order, a row says "Nothing logged" exactly when its chips are the dash, and otherwise
    /// it speaks exactly its chips.
    @Test("A row is spoken as Nothing logged exactly when the Domain draws the dash, over random logs")
    func rows_speakTheirChips_property() throws {
        for seed in RestSeeds.all {
            var generator = SplitMix64(seed: seed)
            var workout = try Fixtures.seedSession()
            workout.exercises = Array(workout.exercises.prefix(3))
            for index in workout.exercises.indices {
                let exercise = workout.exercises[index]
                workout.exercises[index].sets = (0 ..< Int.random(in: 0 ... 5, using: &generator)).map { place in
                    LoggedSet(
                        id: .derived(from: exercise.id, index: place),
                        weight: .pounds(Decimal(Int.random(in: 0 ... 3, using: &generator) * 5 + 100)),
                        reps: Reps(clamping: 5),
                        kind: Bool.random(using: &generator) ? .working : .warmup,
                        doneAt: Bool.random(using: &generator) ? workout.startedAt : nil
                    )
                }
            }
            let finished = try Presentation.finished(
                workout,
                after: Double(Int.random(in: 0 ... 9000, using: &generator))
            )
            let rows = Self.receipt(finished).page.rows
            #expect(rows.map(\.name) == finished.exercises.map(\.name))
            for row in rows {
                let isDash = row.chips == ["—"]
                #expect(row.spoken.hasSuffix(", Nothing logged") == isDash, "\(row.chips)")
                if !isDash {
                    #expect(row.spoken.hasSuffix(", Logged \(row.chips.joined(separator: ", "))"), "\(row.chips)")
                }
            }
        }
    }
}
