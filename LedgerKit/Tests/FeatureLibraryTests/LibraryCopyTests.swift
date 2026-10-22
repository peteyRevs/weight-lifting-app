@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// FeatureLibrary's counted texts through its copy file, with one and with several (standards §7), and the
/// lookups the presentation tests do not reach.
@Suite("LibraryCopy", .tags(.feature))
struct LibraryCopyTests {
    @Test("N2. The search placeholder counts its exercises: one, and several")
    func searchExercises_oneAndSeveral() {
        #expect(LibraryCopy.searchExercises(1, locale: Fixtures.locale) == "Search 1 exercise")
        #expect(LibraryCopy.searchExercises(224, locale: Fixtures.locale) == "Search 224 exercises")
        #expect(LibraryCopy.searchExercises(1224, locale: Fixtures.locale) == "Search 1,224 exercises")
    }

    @Test("A recent row counts its sessions: one, and several")
    func sessions_oneAndSeveral() {
        #expect(LibraryCopy.sessions(1, locale: Fixtures.locale) == "1 session")
        #expect(LibraryCopy.sessions(34, locale: Fixtures.locale) == "34 sessions")
    }

    @Test("A counted text takes the catalog's plural form, not the locale's language's")
    func countedText_takesTheCatalogsPluralForm() {
        #expect(LibraryCopy.sessions(0, locale: Locale(identifier: "fr_FR")) == "0 sessions")
    }

    @Test("The spoken PR names its unit")
    func spokenRecord_namesItsUnit() {
        #expect(LibraryCopy.spokenRecord("195", units: .lb, locale: Fixtures.locale) == "PR 195 pounds")
        #expect(LibraryCopy.spokenRecord("88.5", units: .kg, locale: Fixtures.locale) == "PR 88.5 kilograms")
    }

    @Test("Every kind of equipment and every muscle group has its own name", arguments: Equipment.allCases)
    func equipment_hasItsName(_ equipment: Equipment) {
        #expect(!LibraryCopy.equipment(equipment).isEmpty)
        #expect(LibraryCopy.equipment(equipment) != equipment.rawValue, "a lookup, not the raw value")
    }

    @Test("Every muscle group has its own name, capitalised as the exercise library's")
    func muscles_haveTheirNames() {
        let names = MuscleGroup.allCases.map(LibraryCopy.muscle)
        #expect(names == [
            "Chest", "Back", "Shoulders", "Quads", "Hamstrings", "Glutes", "Calves", "Biceps", "Triceps", "Forearms",
            "Core"
        ])
    }

    @Test("The failed state's two lines")
    func failed_readsItsTwoLines() {
        #expect(LibraryCopy.failedTitle == "Can't show the library right now")
        #expect(LibraryCopy.failedBody.hasPrefix("Your exercises and workouts are still on this iPhone."))
    }
}
