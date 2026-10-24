@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S2 adversarial round 1 (G2): the history's presentation and store where their own tests are silent. A step
/// up across a change of units; the sessions caption under one session; the store over a newest workout deleted
/// while the screen is up, a read that fails once, a read overtaken by a finished workout, the first day of the
/// week changed, the exercise taken away and given back, a workout finished or deleted that is not the newest, and
/// the log's dates across New Year in a time zone and in an injected locale.
@MainActor
@Suite("Adversarial F12 S2 · ExerciseHistory", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct ExerciseHistoryAdversarialTests {
    static func session(_ number: Int, _ date: Date, _ weight: Weight) -> ExerciseSession {
        ExerciseSession(
            workoutID: WorkoutID(Fixtures.uuid(7500 + number)),
            startedAt: date,
            sets: [LoggedSet(
                id: SetID(Fixtures.uuid(75000 + number)),
                weight: weight,
                reps: Reps(clamping: 5),
                kind: .working,
                doneAt: date
            )]
        )
    }

    // MARK: Presentation

    /// F12-S2-1. A heavier session is `.heavier(Δ)` by the exact weights, and its tag is `Δ.formatted(in:)`, which
    /// rounds to one decimal. A step under 0.05 of the shown unit, which a change of units makes (100 kg, then
    /// 220.5 lb: 0.04 lb), reads "+0 lb": a gain of nothing.
    @Test("A step up smaller than the shown precision never reads +0", arguments: [Units.lb, .kg])
    func tag_tinyStepAcrossUnits_neverReadsPlusZero(_ units: Units) throws {
        let earlier = units == .lb ? Weight.kilograms(100) : .pounds(225)
        let later = try units == .lb ? Weight.pounds(220.5) : .kilograms(#require(Decimal(string: "102.1")))
        #expect(later > earlier, "the later session is heavier, by a hair")
        let sessions = [
            Self.session(2, Fixtures.now, later),
            Self.session(1, Fixtures.now.addingTimeInterval(-7 * 86400), earlier)
        ]
        let tag = try ExerciseHistoryPresentation.make(HistoryFixtures.input(sessions, units: units)).log.entries[0].tag
        #expect(!["+0 lb", "+0 kg"].contains(tag), "\(units): \(tag)")
    }

    /// F12-S2-2. The brief's DoD: "Every string above in the String Catalog with plurals (sessions, exercises)".
    /// The stat's caption is a fixed "sessions", so one session reads "1 sessions" (VoiceOver "1, sessions").
    @Test("Under one session the caption is singular")
    func sessionsCaption_oneSession_isSingular() throws {
        let one = [Self.session(1, Fixtures.now, .pounds(200))]
        let stats = try ExerciseHistoryPresentation.make(HistoryFixtures.input(one)).stats
        #expect(stats[2].value == "1")
        #expect(stats[2].caption == "session")
    }

    @Test("Bars stand between a quarter and the full height, and an empty week has none, at any spread")
    func bars_anySpread_levelsStayInRange() throws {
        // A wide spread, a narrow one (one pound) and zero beside a value.
        let spreads: [[Weight]] = [[.pounds(95), .pounds(405)], [.pounds(200), .pounds(201)], [.zero, .pounds(135)]]
        for spread in spreads {
            let sessions = spread.enumerated().map { back, weight in
                Self.session(back, Fixtures.now.addingTimeInterval(-Double(back) * 7 * 86400), weight)
            }
            let bars = try ExerciseHistoryPresentation.make(HistoryFixtures.input(sessions)).chart.bars
            for bar in bars {
                #expect(bar.number == nil ? bar.level == 0 : (25 ... 100).contains(bar.level), "\(spread): \(bar)")
            }
            #expect(bars.compactMap { $0.number == nil ? nil : $0.level }.max() == 100)
        }
    }

    // MARK: Store

    @Test("The newest workout deleted while the history is up leaves the log, the count and the chart")
    func newestWorkoutDeleted_whileShown_leavesTheHistory() async throws {
        let workouts = try HistoryScene.benchWorkouts()
        let scene = try HistoryScene(workouts: workouts)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.log.entries.count == 3)
        let newest = try #require(workouts.last)
        try await scene.memory.workouts.delete(id: newest.id)
        await eventually { (try? scene.model.log.entries.count) == 2 }
        let model = try scene.model
        #expect(model.stats.map(\.value) == ["214", "190", "2"])
        #expect(model.numbers.last == .some(nil), "the current week is empty again")
        #expect(!model.log.entries.contains { $0.id == newest.id })
    }

    @Test("A read that fails once shows the failed state, and the next change brings the history back")
    func readFailsOnce_unitsChange_recovers() async throws {
        let gate = SessionsGate(failures: 1)
        let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts()) {
            $0.statsQueries = GatedSessions(base: $0.statsQueries, gate: gate)
        }
        let run = await scene.running()
        defer { run.cancel() }
        #expect(scene.store.state == .failed)
        try await scene.memory.settings.save(Fixtures.settingsKg)
        await eventually { (try? scene.model.stats.first?.value) == "100" }
        #expect(try scene.model.log.entries.count == 3)
    }

    @Test("A read overtaken by a finished workout ends on the history that holds it")
    func readOvertaken_byAFinishedWorkout_showsIt() async throws {
        let gate = SessionsGate(holdsFirst: true)
        let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts()) {
            $0.statsQueries = GatedSessions(base: $0.statsQueries, gate: gate)
        }
        let run = Task { await scene.store.run() }
        defer { run.cancel() }
        // The gate is not observable, so `eventually` cannot watch it: yield until the first read is held.
        while !gate.isHolding {
            await Task.yield()
        }
        let bench = try HistoryFixtures.bench
        try await scene.memory.workouts.materialize(
            Seeders.workout(number: 640, endedAt: Fixtures.now.addingTimeInterval(3600), [
                .straight(bench, sets: 1, reps: 5, pounds: 200)
            ]),
            slotUpdates: []
        )
        gate.release()
        await eventually { (try? scene.model.log.entries.count) == 4 }
        #expect(try scene.model.stats[1].value == "200")
    }

    @Test("A change of the first day of the week moves the weeks while the history is up")
    func weekStartChanged_whileShown_movesTheWeeks() async throws {
        let bench = try HistoryFixtures.bench
        // Sunday 2026-09-13: in the current week from Sunday, in the week before from Monday.
        let sunday = Seeders.workout(number: 650, endedAt: Fixtures.date(2026, 9, 13, hour: 10), [
            .straight(bench, sets: 1, reps: 5, pounds: 200)
        ])
        let scene = try HistoryScene(workouts: [sunday])
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.numbers.last == .some(nil))
        var settings = Fixtures.settingsLb
        settings.weekStart = .sunday
        try await scene.memory.settings.save(settings)
        await eventually { (try? scene.model.numbers.last) == .some(225) }
    }

    @Test("The exercise taken away while shown shows the failed state; given back, its history returns")
    func exerciseRemoved_whileShown_failsThenReturns() async throws {
        let exercises = ScriptedExercises()
        let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts()) { $0.exerciseRepository = exercises }
        let catalog = LibraryFixtures.catalog
        exercises.send(catalog)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.title == "Barbell Bench Press")
        let bench = try HistoryFixtures.bench
        exercises.send(catalog.filter { $0.id != bench.id })
        await eventually { scene.store.state == .failed }
        exercises.send(catalog)
        await eventually { (try? scene.model.title) == "Barbell Bench Press" }
    }
}

extension ExerciseHistoryAdversarialTests {
    // MARK: N13: a change that is not the newest workout

    /// F12-S2-3. The store reads again only when `observeRecent(limit: 1)` changes, and that observation emits
    /// "for no other write". A finished workout that started before the newest (a watch workout saved after a phone
    /// one, both today) is not the newest, so the open history never shows it, nor its PR.
    @Test("A finished workout older than the newest shows on an open history")
    func olderWorkoutFinished_whileShown_shows() async throws {
        let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts())
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.log.entries.count == 3)
        let bench = try HistoryFixtures.bench
        // Ends two hours before the newest (195 × 5 at `Fixtures.now`), heavier than every session.
        let older = Seeders.workout(number: 660, endedAt: Fixtures.now.addingTimeInterval(-2 * 3600), [
            .straight(bench, sets: 1, reps: 5, pounds: 225)
        ])
        try await scene.memory.workouts.materialize(older, slotUpdates: [])
        _ = await eventually(within: 2) { (try? scene.model.log.entries.count) == 4 }
        #expect(try scene.model.log.entries.count == 4, "the older workout is in the log")
        #expect(try scene.model.stats[1].value == "225", "its best set is the best set")
    }

    /// F12-S2-3, the other half: a workout deleted that is not the newest stays in the open history's log, count
    /// and bests; its row still routes to a deleted workout.
    @Test("A deleted workout older than the newest leaves an open history")
    func olderWorkoutDeleted_whileShown_leaves() async throws {
        let workouts = try HistoryScene.benchWorkouts()
        let scene = try HistoryScene(workouts: workouts)
        let run = await scene.running()
        defer { run.cancel() }
        let oldest = try #require(workouts.first)
        try await scene.memory.workouts.delete(id: oldest.id)
        _ = await eventually(within: 2) { (try? scene.model.log.entries.count) == 2 }
        let model = try scene.model
        #expect(model.log.entries.count == 2, "the deleted workout has left the log")
        #expect(model.stats[2].value == "2", "and the session count")
    }

    // MARK: N14: dates in the injected calendar and locale

    static func input(
        _ sessions: [ExerciseSession],
        now: Date,
        zone: TimeZone,
        locale: Locale = Fixtures.locale
    ) throws -> ExerciseHistoryInput {
        var calendar = Fixtures.calendar
        calendar.timeZone = zone
        return try ExerciseHistoryInput(
            exercise: HistoryFixtures.bench,
            sessions: sessions,
            records: [],
            units: .lb,
            weekStart: .monday,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    @Test("Across New Year in New York: the year is the local one, of the date and of now")
    func date_newYearInNewYork_isLocal() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        // Now: 2027-01-01 10:00 in New York. Dec 31 22:00 there is already 2027 in UTC; Jan 1 00:30 is 2027 both.
        let now = Fixtures.date(2027, 1, 1, hour: 10, in: newYork)
        let sessions = [
            Self.session(2, Fixtures.date(2027, 1, 1, minute: 30, in: newYork), .pounds(200)),
            Self.session(1, Fixtures.date(2026, 12, 31, hour: 22, in: newYork), .pounds(195))
        ]
        let model = try ExerciseHistoryPresentation.make(Self.input(sessions, now: now, zone: newYork))
        #expect(model.log.entries.map(\.date) == ["Jan 1", "Dec 31, 2026"])
    }

    @Test("Across New Year in Tokyo: a session of Jan 1 local is this year's though it is Dec 31 in UTC")
    func date_newYearInTokyo_isLocal() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = Fixtures.date(2027, 1, 1, hour: 20, in: tokyo)
        let sessions = [Self.session(1, Fixtures.date(2027, 1, 1, hour: 7, in: tokyo), .pounds(200))]
        let model = try ExerciseHistoryPresentation.make(Self.input(sessions, now: now, zone: tokyo))
        #expect(model.log.entries.map(\.date) == ["Jan 1"])
    }

    @Test("The injected locale writes the date, never the device's", arguments: ["fr_FR", "de_DE", "en_GB"])
    func date_injectedLocale_writesIt(_ identifier: String) throws {
        let locale = Locale(identifier: identifier)
        let date = Fixtures.date(2026, 8, 12, hour: 7)
        let model = try ExerciseHistoryPresentation.make(
            Self.input([Self.session(1, date, .pounds(200))], now: Fixtures.now, zone: Fixtures.utc, locale: locale)
        )
        var calendar = Fixtures.calendar
        calendar.locale = locale
        let expected = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: Fixtures.utc)
            .month(.abbreviated).day().format(date)
        #expect(model.log.entries.map(\.date) == [expected])
        #expect(model.log.entries.first?.date != "Aug 12", "\(identifier)")
    }

    // MARK: Criterion 6 and the reps edge

    @Test("12 reps have an estimate; 13 do not, and a 13-rep best set reads with its reps")
    func estimate_thirteenReps_isDash_twelveIsNot() throws {
        let thirteen = [ExerciseSession(
            workoutID: WorkoutID(Fixtures.uuid(7601)),
            startedAt: Fixtures.now,
            sets: [LoggedSet(
                id: SetID(Fixtures.uuid(76001)), weight: .pounds(100), reps: Reps(clamping: 13), kind: .working,
                doneAt: Fixtures.now
            )]
        )]
        let model = try ExerciseHistoryPresentation.make(HistoryFixtures.input(thirteen))
        #expect(model.stats.map(\.value) == ["—", "100", "1"])
        #expect(model.stats[1].unit == "×13")
        #expect(model.chart.empty != nil, "no week has an estimate: the chart says so")
        #expect(model.chart.bars.allSatisfy { $0.number == nil && $0.level == 0 && !$0.isAccented })
    }

    @Test("A warm-up or drop set never makes the estimate, the best set or a week; it still reads in the log")
    func warmupAndDrop_onlyInTheLog() throws {
        let sets = [(SetKind.warmup, Decimal(300)), (.drop, 250), (.working, 200)].enumerated().map { place, set in
            LoggedSet(
                id: SetID(Fixtures.uuid(76100 + place)), weight: .pounds(set.1), reps: Reps(clamping: 5), kind: set.0,
                doneAt: Fixtures.now
            )
        }
        let session = ExerciseSession(workoutID: WorkoutID(Fixtures.uuid(7610)), startedAt: Fixtures.now, sets: sets)
        let model = try ExerciseHistoryPresentation.make(HistoryFixtures.input([session]))
        #expect(model.stats[1].value == "200")
        #expect(model.stats[0].value == "225", "Brzycki of 200 × 5")
        #expect(model.numbers.last == .some(225))
        #expect(model.log.entries.first?.sets.hasPrefix("300×5") == true)
    }
}
