import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The tags live in the test target, not LedgerTestSupport, as in `LedgerDomainTests` (F02 notes).
nonisolated extension Tag {
    /// Every WatchFeatureWorkout suite (layer tag, testing-strategy §6).
    @Tag static var watch: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
}

/// The lane a test plan runs in, from its `LEDGER_TEST_LANE` variable (testing-strategy §6).
nonisolated enum TestLane {
    static var isNightly: Bool {
        ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly"
    }
}

/// Workouts and inputs for the presentation's suites, all at `Fixtures.now` (Wednesday of week 5 of the seed
/// program, testing-strategy §3) unless a test moves the moment itself.
nonisolated enum WatchSample {
    /// The bundled catalog by id.
    static func catalog() throws -> [ExerciseID: Exercise] {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    /// The seed program's day `index` (0 Upper A, 1 Lower A, 2 Upper B, 3 Lower B) in week `weekIndex`, built at
    /// `now` in `settings`' unit, no set logged.
    static func session(
        day index: Int = 0,
        weekIndex: Int = 4,
        settings: Settings = Fixtures.settingsLb,
        now: Date = Fixtures.now
    ) throws -> WorkoutState {
        let program = try Fixtures.seedProgram()
        return try SessionBuilder.build(
            program: program, weekIndex: weekIndex, day: program.days[index], exercises: catalog(),
            history: [:], settings: settings, id: Fixtures.sessionID, device: Fixtures.deviceID, now: now
        )
    }

    /// `state` with the rows of `rows` logged at `Fixtures.now`.
    static func logging(_ rows: [(Int, Int)], in state: WorkoutState) -> WorkoutState {
        var state = state
        for (exercise, set) in rows {
            state.exercises[exercise].sets[set].doneAt = Fixtures.now
        }
        return state
    }

    static func live(
        heartRate: Int? = nil,
        health: HealthAuthorization = .authorized,
        connection: LiveConnectionState? = .connected(.mirroring),
        hasHeardPhone: Bool = true
    ) -> WatchLiveInput {
        WatchLiveInput(
            heartRate: heartRate.map { HeartRateSample(bpm: $0, date: Fixtures.now) },
            health: health,
            connection: connection,
            hasHeardPhone: hasHeardPhone,
            locale: Fixtures.locale
        )
    }
}
