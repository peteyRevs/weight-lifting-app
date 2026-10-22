@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Criterion 8 (the Library's part), N2, N7 and Pete's question 8 on the pure presentation.
extension LibraryPresentationTests {
    // MARK: Criterion 8, N2, N7, Q8

    @Test("8. In kilograms every PR is converted")
    func units_kilograms_convertThePRs() throws {
        let model = try Self.model(Self.input(units: .kg))
        #expect(model.row(Self.bench)?.record == "88.5")
        #expect(model.row(Self.bench, in: .recent)?.spokenValue == "Barbell, Chest, 34 sessions, PR 88.5 kilograms")
    }

    @Test("N2. The placeholder counts every live exercise, not the rows the filter leaves")
    func placeholder_countsEveryExercise() throws {
        let model = try Self.model(Self.input(), LibraryFilter(query: "row", muscle: .back, equipment: .machine))
        #expect(model.search.placeholder == "Search \(LibraryFixtures.catalog.count + 1) exercises")
    }

    @Test("N7. A row is one button: its name, then the meta's parts and its PR in pounds as its value")
    func row_spokenValue_readsTheMetaAndThePR() throws {
        let model = try Self.model(Self.input())
        let recentBench = try #require(model.row(Self.bench, in: .recent))
        #expect(recentBench.spokenValue == "Barbell, Chest, 34 sessions, PR 195 pounds")
        #expect(try recentBench.action == .route(.exercise(LibraryFixtures.exercise(named: Self.bench).id)))
        #expect(model.row(Self.squat)?.spokenValue == "Barbell, Quads", "no PR is read for a dash")
    }

    @Test("Q8. With no exercise stored the Library says so, with New exercise")
    func noExercises_saysSoWithNewExercise() {
        let input = LibraryInput(exercises: [], units: .lb, locale: Fixtures.locale)
        let model = Self.model(input, LibraryFilter(query: "row"))
        #expect(model.content == .noExercises(LibraryModel.Message(
            text: "No exercises yet.",
            control: LibraryModel.Control(title: "New exercise", action: .newExercise)
        )))
        #expect(model.search.placeholder == "Search 0 exercises")
    }

    @Test("The header reads Library, with New exercise")
    func header_readsLibrary_withNewExercise() throws {
        let model = try Self.model(Self.input())
        #expect(model.title == "Library")
        #expect(model.newExercise == LibraryModel.Control(title: "New exercise", action: .newExercise))
    }
}
