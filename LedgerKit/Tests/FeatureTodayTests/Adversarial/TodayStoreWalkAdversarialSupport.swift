@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// One seeded walk of `TodayStoreWalkAdversarialTests`: the scene, the run and the oracle. Its steps are in
/// `TodayStoreWalkAdversarialSupport+Steps.swift`.
@MainActor
final class TodayWalk {
    let seed: PropertySeed
    let scene: TodayScene
    let calendar: Calendar
    let base: Program
    var generator: SeededGenerator
    var task: Task<Void, Never>?
    var trace: [String] = []
    var number = 1000
    var stored: [WorkoutID] = []
    var live: WorkoutState?
    /// The workout the session finished since the store's task last started: the store still holds it.
    var endedInSession: WorkoutState?

    init(seed: PropertySeed, zone: String) throws {
        self.seed = seed
        var zoned = Calendar(identifier: .gregorian)
        zoned.timeZone = try #require(TimeZone(identifier: zone))
        calendar = zoned
        base = try TodayFixtures.program()
        generator = seed.generator
        scene = try TodayScene { $0.calendar = zoned }
    }

    /// Nil when every burst ended at the oracle's model; else what went wrong, with the steps that led there.
    func run(bursts: Int) async throws -> String? {
        task = await scene.running()
        let publications = StatePublications(scene.store)
        defer {
            publications.stop()
            task?.cancel()
        }
        for burst in 0 ..< bursts {
            for _ in 0 ..< Int.random(in: 1 ... 4, using: &generator) {
                try await step()
            }
            try await restartIfTheEndedWorkoutLeftTheWeek()
            let wanted = try await expected()
            let store = scene.store
            guard await settles(within: .seconds(10), { store.model == wanted }) else {
                return "\(seed) \(calendar.timeZone.identifier) burst \(burst): the store shows \(store.phase), "
                    + "differs in \(Self.difference(store.model, wanted)); at \(scene.clock.value); "
                    + "last reads \(scene.workouts.ranges.suffix(2)); steps: \(trace.suffix(12))"
            }
            let phases = publications.phases
            guard !phases.dropFirst().contains(where: { $0 != "loaded" }) else {
                return "\(seed) burst \(burst): the store showed \(phases); steps: \(trace.suffix(12))"
            }
        }
        return nil
    }

    /// The parts of the model that differ, by name.
    static func difference(_ shown: TodayModel?, _ wanted: TodayModel) -> String {
        guard let shown else {
            return "everything (no model)"
        }
        var parts: [String] = []
        if shown.header != wanted.header {
            parts.append("header (\(shown.header.date) / \(wanted.header.date))")
        }
        if shown.weekStrip != wanted.weekStrip {
            parts.append("strip (\(shown.weekStrip.marks) / \(wanted.weekStrip.marks))")
        }
        if shown.card != wanted.card {
            parts.append("card (\(shown.card.kind) / \(wanted.card.kind))")
        }
        if shown.stats != wanted.stats {
            let sessions = "\(shown.stats.sessions.value) / \(wanted.stats.sessions.value)"
            let volume = "\(shown.stats.volume.accessibilitySummary) / \(wanted.stats.volume.accessibilitySummary)"
            parts.append("stats (\(sessions); \(volume))")
        }
        if shown.recent != wanted.recent {
            parts.append("recent (\(shown.recent.rows.count) / \(wanted.recent.rows.count))")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: The oracle

    /// The two stretches of time from the calendar alone: the stats week of `now` joined with its program
    /// week while the block runs (week 1 before it begins), and the seven days before the stats week.
    static func ranges(
        program: Program?,
        weekStart: Weekday,
        now: Date,
        calendar: Calendar
    ) -> (week: Range<Date>, previous: Range<Date>) {
        func day(_ count: Int, from date: Date) -> Date {
            calendar.date(byAdding: .day, value: count, to: date) ?? .distantPast
        }
        let today = calendar.startOfDay(for: now)
        let back = (calendar.component(.weekday, from: now) - weekStart.calendarWeekday + 7) % 7
        let statsStart = day(-back, from: today)
        var lower = statsStart
        var upper = day(7, from: statsStart)
        if let program {
            let first = program.startDate
            let parts = DateComponents(year: first.year, month: first.month, day: first.day)
            let start = calendar.date(from: parts) ?? .distantPast
            let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
            let index = Int((Double(days) / 7).rounded(.down))
            if index < program.weeks.count {
                let week = max(0, index)
                lower = min(lower, day(7 * week, from: start))
                upper = max(upper, day(7 * week + 7, from: start))
            }
        }
        return (lower ..< upper, day(-7, from: statsStart) ..< statsStart)
    }

    /// What Today must show for the stores, the session and the clock as they stand.
    func expected() async throws -> TodayModel {
        let now = scene.clock.value
        let program = try await scene.stores.programs.active()
        let settings = try await scene.stores.settings.load()
        let exercises = try await scene.stores.exercises.all()
        let ranges = Self.ranges(program: program, weekStart: settings.weekStart, now: now, calendar: calendar)
        return try await TodayPresentation.make(TodayInput(
            program: program,
            exercises: Dictionary(exercises.map { ($0.id, $0) }) { first, _ in first },
            settings: settings,
            weekWorkouts: scene.stores.workouts.workouts(in: ranges.week),
            recentWorkouts: scene.stores.workouts.recent(limit: 5),
            previousWeekVolume: scene.stores.stats.weeklyVolume(in: ranges.previous),
            session: scene.fake.current(),
            now: now,
            calendar: calendar,
            locale: Fixtures.locale
        ))
    }
}
