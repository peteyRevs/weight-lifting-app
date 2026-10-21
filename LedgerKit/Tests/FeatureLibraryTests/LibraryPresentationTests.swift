@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1, criteria 1, 2 and 8 (the Library's part), N2 and N7, on the pure presentation: what a fixed input
/// draws, with the bundled catalog and one exercise of the lifter's own.
@Suite("LibraryPresentation", .tags(.feature))
struct LibraryPresentationTests {
    static let bench = "Barbell Bench Press"
    static let squat = "Back Squat"

    /// The catalog and the custom exercise; bench logged in 34 sessions with a best of 195 × 5, then the squat,
    /// the row, a deadlift and the custom press, newest first.
    static func input(units: Units = .lb, recent names: [String]? = nil) throws -> LibraryInput {
        let named = try (names ?? [bench, squat, "Barbell Row", "Deadlift"]).map(LibraryFixtures.exercise)
        let custom = LibraryFixtures.custom
        let benchID = try LibraryFixtures.exercise(named: Self.bench).id
        return LibraryInput(
            exercises: LibraryFixtures.catalog + [custom],
            recent: named.map(\.id) + [custom.id],
            sessions: Dictionary(uniqueKeysWithValues: named.map { ($0.id, $0.id == benchID ? 34 : 3) } + [(
                custom.id,
                1
            )]),
            bestSets: [
                benchID: BestSet(weight: .pounds(195), reps: Reps(clamping: 5)),
                custom.id: BestSet(weight: .pounds(95), reps: Reps(clamping: 8))
            ],
            units: units,
            locale: Fixtures.locale
        )
    }

    static func model(_ input: LibraryInput, _ filter: LibraryFilter = LibraryFilter()) -> LibraryModel {
        LibraryPresentation.make(LibraryPresentation.rows(input), filter: filter)
    }

    // MARK: Criterion 1

    @Test("1. RECENTLY LOGGED lists the recent exercises in recentlyLogged's order, with their sessions and PR")
    func sections_recentInItsOrder_withSessionsAndPR() throws {
        let model = try Self.model(Self.input())
        #expect(model.sections.map(\.title) == ["RECENTLY LOGGED", "ALL EXERCISES"])
        #expect(model.names(.recent) == [
            Self.bench, Self.squat, "Barbell Row", "Deadlift", LibraryFixtures.custom.name
        ])
        let recentBench = try #require(model.row(Self.bench, in: .recent))
        #expect(recentBench.meta == "Barbell · Chest · 34 sessions")
        #expect(recentBench.record == "195")
        #expect(model.row(Self.squat, in: .recent)?.meta == "Barbell · Quads · 3 sessions")
        #expect(model.row(Self.squat, in: .recent)?.record == "—")
    }

    @Test("1. ALL EXERCISES lists every live exercise in ExerciseSearch's name order, each with its PR or a dash")
    func sections_allInNameOrder_withPROrDash() throws {
        let input = try Self.input()
        let model = Self.model(input)
        let all = try #require(model.section(.all))
        #expect(all.rows.count == LibraryFixtures.catalog.count + 1)
        #expect(all.rows.map(\.id) == ExerciseSearch.sorted(input.exercises).map(\.id), "name order")
        #expect(model.row(Self.bench)?.meta == "Barbell · Chest")
        #expect(model.row(Self.bench)?.record == "195")
        #expect(all.rows.count { $0.record == "—" } == all.rows.count - 2)
    }

    @Test("1. The lifter's own exercise reads Custom after its equipment and muscle, in both sections")
    func customExercise_readsCustom() throws {
        let model = try Self.model(Self.input())
        let name = LibraryFixtures.custom.name
        #expect(model.row(name)?.meta == "Barbell · Chest · Custom")
        #expect(model.row(name, in: .recent)?.meta == "Barbell · Chest · 1 session · Custom")
        #expect(model.row(name)?.record == "95")
    }

    @Test("1. With no history the recent section is not drawn")
    func noHistory_drawsNoRecentSection() throws {
        var input = try Self.input()
        input.recent = []
        input.sessions = [:]
        input.bestSets = [:]
        let model = Self.model(input)
        #expect(model.sections.map(\.id) == [.all])
        #expect(model.section(.all)?.rows.allSatisfy { $0.record == "—" } == true)
    }

    @Test("1. A recent exercise that is no longer stored is left out")
    func recent_notStored_isLeftOut() throws {
        var input = try Self.input()
        input.recent.insert(ExerciseID(Fixtures.uuid(77)), at: 0)
        #expect(Self.model(input).names(.recent).first == Self.bench)
    }

    // MARK: Criterion 2

    @Test("2. Query row, Back and Machine leave Chest-Supported Row alone, in both sections")
    func filter_rowBackMachine_leavesChestSupportedRow() throws {
        let row = "Chest-Supported Row"
        let input = try Self.input(recent: [Self.bench, row, "Barbell Row"])
        let model = Self.model(input, LibraryFilter(query: "row", muscle: .back, equipment: .machine))
        #expect(model.names(.recent) == [row])
        #expect(model.names(.all) == [row])
        #expect(model.selectedChips == ["Back", "Machine"])
        #expect(model.search.query == "row")
    }

    @Test(
        "2. The query is a substring of the name or the short name, ignoring case and diacritics",
        arguments: ["ROW", "rOw", "rôw"]
    )
    func filter_query_ignoresCaseAndDiacritics(_ query: String) throws {
        let model = try Self.model(Self.input(), LibraryFilter(query: query, muscle: .back, equipment: .machine))
        #expect(model.names(.all) == ["Chest-Supported Row"])
    }

    @Test("2. The short name matches too: the custom press is found by its own")
    func filter_shortName_matches() throws {
        let model = try Self.model(Self.input(), LibraryFilter(query: "sqz"))
        #expect(model.names(.all) == [LibraryFixtures.custom.name])
        #expect(model.names(.recent) == [LibraryFixtures.custom.name])
    }

    @Test("2. A filter that leaves nothing says so, with Clear filters, and keeps the chips")
    func filter_nothing_saysSoWithClearFilters() throws {
        let model = try Self.model(Self.input(), LibraryFilter(query: "zzz", muscle: .legs))
        guard case let .nothingMatches(message) = model.content else {
            Issue.record("expected nothing to match, got \(model.sections.map(\.title))")
            return
        }
        #expect(message.text == "Nothing matches that filter.")
        #expect(message.control == LibraryModel.Control(title: "Clear filters", action: .clearFilters))
        #expect(model.selectedChips == ["Legs", "All"])
    }

    @Test("2. A kind of equipment with no chip is read as All")
    func filter_equipmentWithoutAChip_isAll() throws {
        let model = try Self.model(Self.input(), LibraryFilter(equipment: .kettlebell))
        #expect(model.selectedChips == ["All", "All"])
        #expect(model.section(.all)?.rows.count == LibraryFixtures.catalog.count + 1)
    }

    @Test("2. The chips are the exercise library's, each read with its row's name and setting its filter")
    func chips_areThePickers() throws {
        let model = try Self.model(Self.input(), LibraryFilter(muscle: .arms))
        #expect(model.muscles.chips.map(\.title) == ["All", "Chest", "Back", "Shoulders", "Legs", "Arms"])
        #expect(model.equipment.chips.map(\.title) == ["All", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight"])
        #expect(model.muscles.chips.map(\.spokenLabel).last == "Muscle: Arms")
        #expect(model.equipment.chips.first?.spokenLabel == "Equipment: All")
        #expect(model.muscles.chips.map(\.action).first == .setMuscle(nil))
        #expect(model.equipment.chips.map(\.action).last == .setEquipment(.bodyweight))
        #expect(model.muscles.chips.map(\.id) == Array(0 ..< 6))
    }
}
