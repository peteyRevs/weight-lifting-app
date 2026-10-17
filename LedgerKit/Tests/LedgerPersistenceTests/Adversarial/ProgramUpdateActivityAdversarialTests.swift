import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 adversarial round 1, criterion 6's last clause and what an update leaves outside the program: which
/// program is active changes only when the result says so, as `save` saves it, and history does not move when
/// an update deletes the day a finished workout came from.
@Suite("Adversarial F11 S3 · activity and history around an update", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramUpdateActivityAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Fixture = LinkedFixture

    @Test(
        "History is as it was after an update deletes the day a finished workout came from",
        arguments: Place.allCases
    )
    func update_deletingAWorkoutsDay_leavesHistory(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        let slot = try Fixture.slot(4)
        let workout = Fixture.workout(1, updates: [slot.id: Fixture.other(than: slot)])
        _ = await stores.save(workout, slots: [Fixture.missing(slot, [0])], droppingLog: false)
        let before = try await stores.workouts.workout(id: workout.id)
        // Both days go, the workout's own first: the block keeps its weeks and no day.
        let emptied = try await stores.programs.update(UpdateKit.one) { program in
            UpdateRefusal.changed(program) { changed in
                changed.days = []
                for week in changed.weeks.indices {
                    changed.weeks[week].schedule = [:]
                }
            }
        }
        let after = try await stores.workouts.workout(id: workout.id)
        let isUntouched = before == after && after?.source?.dayTemplateID == S2Kit.dayID(100)
        #expect(
            isUntouched && emptied.days.isEmpty,
            "\(place): the workout changed, or \(emptied.days.count) days stay"
        )
        #expect(try await stores.workouts.recent(limit: 5).count == 1)
    }

    @Test("An update of the program that is not active leaves the active one active", arguments: Place.allCases)
    func update_ofInactiveProgram_leavesActivityAlone(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        for edit in UpdateEdit.all {
            // Each edit as program 2 would take it: only the name is the same for both programs.
            _ = try await stores.programs.update(UpdateKit.two) { program in
                UpdateRefusal.changed(program) { $0.name = edit.name }
            }
        }
        let active = try await stores.programs.active()
        let other = try await UpdateKit.read(stores, 2)
        #expect(active?.id == UpdateKit.one && active?.isActive == true)
        #expect(other?.isActive == false && other?.name == UpdateEdit.all.last?.name)
    }

    @Test("A result's `isActive` is saved as `save` saves it: one active program at most", arguments: Place.allCases)
    func update_resultThatChangesActivity_isSavedAsSaveSavesIt(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        let activated = try await stores.programs.update(UpdateKit.two) { program in
            UpdateRefusal.changed(program) { $0.isActive = true }
        }
        let active = try await stores.programs.active()
        #expect(activated.isActive && active?.id == UpdateKit.two, "active is \(active?.name ?? "none")")
        let before = try await UpdateKit.read(stores, 1)
        #expect(before?.isActive == false, "program 1 stayed active beside program 2")
        let retired = try await stores.programs.update(UpdateKit.two) { program in
            UpdateRefusal.changed(program) { $0.isActive = false }
        }
        let left = try await stores.programs.active()
        #expect(!retired.isActive && left == nil, "\(left?.name ?? "no program") is active")
    }
}
