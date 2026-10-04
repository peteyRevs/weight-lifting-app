import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// LedgerFakes' fixtures construct, pass the domain's validation, keep the bundled catalog's ids, and say what
/// the spec's seed program says (§6.4), so previews and tests built on them start from valid data.
@Suite("Fixtures")
struct FixturesTests {
    static let catalogIDs: [(ExerciseID, String)] = [
        (Fixtures.CatalogID.benchPress, "Barbell Bench Press"),
        (Fixtures.CatalogID.inclineDBPress, "Incline DB Press"),
        (Fixtures.CatalogID.chestSupportedRow, "Chest-Supported Row"),
        (Fixtures.CatalogID.latPulldown, "Lat Pulldown"),
        (Fixtures.CatalogID.cableLateralRaise, "Cable Lateral Raise"),
        (Fixtures.CatalogID.backSquat, "Back Squat"),
        (Fixtures.CatalogID.romanianDeadlift, "Romanian Deadlift"),
        (Fixtures.CatalogID.legPress, "Leg Press"),
        (Fixtures.CatalogID.standingCalfRaise, "Standing Calf Raise"),
        (Fixtures.CatalogID.weightedPullUp, "Weighted Pull-Up"),
        (Fixtures.CatalogID.overheadPress, "Overhead Press"),
        (Fixtures.CatalogID.barbellRow, "Barbell Row"),
        (Fixtures.CatalogID.barbellCurl, "Barbell Curl"),
        (Fixtures.CatalogID.deadlift, "Deadlift"),
        (Fixtures.CatalogID.frontSquat, "Front Squat"),
        (Fixtures.CatalogID.seatedLegCurl, "Seated Leg Curl")
    ]

    static func catalog() throws -> [ExerciseID: Exercise] {
        try Dictionary(uniqueKeysWithValues: ExerciseCatalog.seed().map { ($0.id, $0) })
    }

    @Test("Each catalog id is the bundled catalog's exercise of that name, and benchPress is its entry")
    func catalogIDs_matchTheBundledCatalog() throws {
        let catalog = try Self.catalog()
        for (id, name) in Self.catalogIDs {
            #expect(catalog[id]?.name == name, "\(name)")
        }
        #expect(catalog[Fixtures.CatalogID.benchPress] == Fixtures.benchPress)
    }

    @Test("The seed program is spec §6.4's: 8 weeks of 4 days and 16 slots, week 8 a deload of three days")
    func seedProgram_isTheSpecs() throws {
        let program = try Fixtures.seedProgram()
        #expect(program.isActive)
        #expect(program.weeks.count == 8)
        #expect(program.days.map(\.tag) == ["UA", "LA", "UB", "LB"])
        #expect(program.days.map(\.slots.count) == [5, 4, 4, 3])
        #expect(program.weeks.map(\.schedule.count) == [4, 4, 4, 4, 4, 4, 4, 3])
        #expect(program.weeks.map(\.isDeload) == Array(repeating: false, count: 7) + [true])
        let slots = program.days.flatMap(\.slots)
        #expect(slots.map(\.exerciseID) == Self.catalogIDs.map(\.0))
        #expect(slots.allSatisfy { $0.repsHi == $0.reps + 2 && $0.misses.isEmpty })
        #expect(slots.filter(\.isSupersetWithPrevious).map(\.exerciseID) == [
            Fixtures.CatalogID.cableLateralRaise, Fixtures.CatalogID.standingCalfRaise
        ])
        #expect(slots.filter { $0.dropSets == 1 }.map(\.exerciseID) == [Fixtures.CatalogID.barbellCurl])
        #expect(slots.first?.startLoad == .pounds(180))
    }

    @Test("Saved to a store, the seed program reads back equal: it passes a save's re-validation")
    func seedProgram_savesAndReadsBack() async throws {
        let programs = InMemoryProgramRepository()
        try await programs.save(Fixtures.seedProgram())
        #expect(try await programs.active() == Fixtures.seedProgram())
    }

    @Test("The seed session is Upper A of week 5, live at now, with no set done")
    func seedSession_isUpperA_live() throws {
        let session = try Fixtures.seedSession()
        #expect(session.phase == .live)
        #expect(session.startedAt == Fixtures.now)
        #expect(session.tag == "UA")
        #expect(session.source?.weekIndex == 4)
        #expect(session.exercises.map(\.exerciseID) == Array(Self.catalogIDs.prefix(5).map(\.0)))
        #expect(session.doneSets == 0 && session.totalSets == 18)
    }

    @Test("history(weeks:) is the seed schedule's finished workouts before now, every set done", arguments: [0, 1, 8])
    func history_isFinishedWorkoutsBeforeNow(weeks: Int) async throws {
        let history = try Fixtures.history(weeks: weeks)
        #expect(history.count == [0: 0, 1: 1, 8: 29][weeks])
        #expect(history.allSatisfy { $0.phase == .finished && $0.startedAt < Fixtures.now })
        #expect(history.allSatisfy { workout in
            workout.doneSets == workout.totalSets && (workout.endedAt ?? .distantPast) > workout.startedAt
        })
        #expect(history.map(\.startedAt) == history.map(\.startedAt).sorted())
        #expect(Set(history.map(\.id)).count == history.count)
        let workouts = InMemoryWorkoutRepository(workouts: history)
        #expect(try await workouts.recent(limit: 100).count == history.count)
    }

    @Test("The settings fixtures are the defaults, in pounds and in kilograms")
    func settings_areTheDefaultsInEachUnit() {
        #expect(Fixtures.settingsLb == .default)
        #expect(Fixtures.settingsKg.units == .kg)
        var back = Fixtures.settingsKg
        back.units = .lb
        #expect(back == .default)
    }

    @Test("The preview seed builds, with every catalog exercise")
    func previewSeed_builds() throws {
        let seed = try InMemoryStores.Seed.preview()
        #expect(seed.catalog.count >= 200)
        #expect(try seed.programs == [Fixtures.seedProgram()])
        #expect(seed.workouts.count == 29)
    }
}
