import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F11 S3 adversarial round 1, criteria 2 to 4: an update that must store nothing. Every way `save` refuses a
/// program, a result under another id, a change that throws and a program that is not there: the error is the
/// one `save` (or `setActive`) gives, no row moves, no `updated_at` moves, and no watcher hears anything.
@Suite("Adversarial F11 S3 · an update that stores nothing", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramUpdateRefusalAdversarialTests {
    typealias Place = UpdateKit.Place
    typealias Fixture = LinkedFixture

    /// What went wrong when `refusal` was given to `update`, if anything.
    static func issues(_ refusal: UpdateRefusal, _ stores: LinkedStores) async throws -> [String] {
        var issues: [String] = []
        let before = try await UpdateSnapshot(stores)
        stores.clock.advance()
        let calls = UpdateTally()
        let outcome = await UpdateKit.attempt(stores.programs) { program in
            calls.add()
            return try refusal.result(program)
        }
        let after = try await UpdateSnapshot(stores)
        if let difference = after.difference(from: before) {
            issues.append("something was written: \(difference)")
        }
        if calls.count != 1 {
            issues.append("the change ran \(calls.count) times")
        }
        var expected = refusal.expected
        if expected == nil, let stored = try await UpdateKit.read(stores, 1), let result = try? refusal.result(stored) {
            expected = await UpdateKit.attemptSave(stores.programs, result)
        }
        if outcome == "stored" || outcome != expected {
            issues.append("update answered \(outcome.prefix(120)), save \((expected ?? "nil").prefix(120))")
        }
        return issues
    }

    @Test(
        "A result `save` refuses is refused with `save`'s error, and nothing is written",
        arguments: Place.allCases, Array(UpdateRefusal.all.indices)
    )
    func update_resultSaveRefuses_isRefusedAsSaveRefuses(place: Place, index: Int) async throws {
        let (stores, directory) = try await UpdateKit.make(place, "refusal\(index)")
        defer { try? directory?.remove() } // cleanup only
        let refusal = UpdateRefusal.all[index]
        let issues = try await Self.issues(refusal, stores)
        #expect(issues.isEmpty, "\(place), \(refusal.name): \(issues.joined(separator: "; "))")
    }

    @Test("The value refusals are refusals: `save` refuses each of them too", arguments: [Place.database, .memory])
    func save_refusesEveryValueRefusal(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let stored = try #require(try await UpdateKit.read(stores, 1))
        var accepted: [String] = []
        for refusal in UpdateRefusal.all where refusal.expected == nil {
            let outcome = try await UpdateKit.attemptSave(stores.programs, refusal.result(stored))
            if outcome == "stored" {
                accepted.append(refusal.name)
            }
        }
        #expect(accepted.isEmpty, "save stored: \(accepted)")
    }

    @Test("The database and the in-memory stores refuse each result with the same error")
    func update_refusedResult_sameErrorOnBothStores() async throws {
        let (database, _) = try await UpdateKit.make(.database)
        let (memory, _) = try await UpdateKit.make(.memory)
        var differing: [String] = []
        for refusal in UpdateRefusal.all {
            let first = await UpdateKit.attempt(database.programs, UpdateKit.one, refusal.result)
            let second = await UpdateKit.attempt(memory.programs, UpdateKit.one, refusal.result)
            if first != second {
                differing.append("\(refusal.name): \(first.prefix(70)) against \(second.prefix(70))")
            }
        }
        #expect(differing.isEmpty, "\(differing.joined(separator: "; "))")
    }

    @Test(
        "A program that is not stored, or is deleted, is a missing row; the change never runs",
        arguments: Place.allCases
    )
    func update_programNotStoredOrDeleted_throwsMissingRowWithoutCallingChange(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        try await stores.programs.delete(UpdateKit.two)
        var issues: [String] = []
        for id in [S2Kit.programID(404), UpdateKit.two] {
            let before = try await UpdateSnapshot(stores)
            stores.clock.advance()
            let calls = UpdateTally()
            let outcome = await UpdateKit.attempt(stores.programs, id) { program in
                calls.add()
                return UpdateRefusal.changed(program) { $0.name = "Never" }
            }
            let expected = "\(RepositoryError.missingRow("program \(ColumnCodec.text(id))"))"
            var activation = "stored"
            do {
                try await stores.programs.setActive(id)
            } catch {
                activation = "\(error)"
            }
            let difference = try await UpdateSnapshot(stores).difference(from: before)
            if outcome != expected || outcome != activation || !calls.isZero || difference != nil {
                issues.append("\(outcome), setActive \(activation), \(calls.count) calls, \(difference ?? "no change")")
            }
        }
        #expect(issues.isEmpty, "\(place): \(issues.joined(separator: "; "))")
    }

    @Test(
        "No watcher hears a refused update, a thrown change or a missing program",
        arguments: [Place.database, .memory]
    )
    func observeActive_refusedUpdates_hearsNothing(place: Place) async throws {
        let (stores, _) = try await UpdateKit.make(place)
        let heard = try await LinkedSaveObserverAdversarialTests.heardFirst(on: stores.programs.observeActive()) {
            for refusal in UpdateRefusal.all {
                _ = await UpdateKit.attempt(stores.programs, UpdateKit.one, refusal.result)
            }
            _ = await UpdateKit.attempt(stores.programs, S2Kit.programID(404)) { $0 }
            _ = try await stores.programs.update(UpdateKit.one) { program in
                UpdateRefusal.changed(program) { $0.name = "Marked" }
            }
        }
        #expect(heard??.name == "Marked", "\(place): heard a program named \(heard??.name ?? "nil") first")
    }

    @Test(
        "A deleted program saved again is there to update, and one deleted after an update is not",
        arguments: Place.allCases
    )
    func update_acrossDeleteAndSave_followsWhatIsStored(place: Place) async throws {
        let (stores, directory) = try await UpdateKit.make(place)
        defer { try? directory?.remove() } // cleanup only
        try await UpdateKit.zero(stores)
        try await stores.programs.delete(UpdateKit.one)
        let gone = await UpdateKit.attempt(stores.programs, UpdateKit.one, UpdateKit.increment)
        // Replaced: saved again with other days, and another name to count from.
        var replacement = try Fixture.program(1)
        replacement.name = "40"
        replacement.days[0].slots.removeLast()
        try await stores.programs.save(replacement)
        let back = try await stores.programs.update(UpdateKit.one, UpdateKit.increment)
        let stored = try await UpdateKit.read(stores, 1)
        #expect(gone == "\(RepositoryError.missingRow("program \(ColumnCodec.text(UpdateKit.one))"))")
        #expect(back.name == "41" && stored?.name == "41", "returned \(back.name), stored \(stored?.name ?? "nil")")
        let hasItsSlots = stored?.slotIDs == replacement.slotIDs && back.slotIDs == replacement.slotIDs
        #expect(hasItsSlots, "the replaced program lost or gained slots")
    }
}

/// One result a store must refuse, built from the program as stored.
struct UpdateRefusal: Sendable {
    typealias Fixture = LinkedFixture

    let name: String
    /// The error text expected; `nil` for "what `save` answers when given the same result".
    var expected: String?
    let result: @Sendable (Program) throws -> Program

    static func copy(_ program: Program, id: ProgramID) throws -> Program {
        try Program(
            id: id, name: program.name, startDate: program.startDate, weeks: program.weeks, days: program.days,
            goal: program.goal, daysPerWeek: program.daysPerWeek, isActive: program.isActive
        )
    }

    static func changed(_ program: Program, _ change: (inout Program) throws -> Void) rethrows -> Program {
        var edited = program
        try change(&edited)
        return edited
    }

    static let identityRefusals: [UpdateRefusal] = [
        UpdateRefusal(name: "a week id program 2 holds") { program in
            changed(program) { $0.weeks[0] = Week(id: S2Kit.weekID(200), index: 0, schedule: $0.weeks[0].schedule) }
        },
        UpdateRefusal(name: "a day id program 2 holds") { program in
            changed(program) { $0.days.append(DayTemplate(id: S2Kit.dayID(200), name: "Taken", tag: "T")) }
        },
        UpdateRefusal(name: "a slot id program 2 holds") { program in
            try changed(program) { try $0.days[0].slots.append(S2Kit.slot(2001)) }
        },
        UpdateRefusal(name: "a slot id used twice") { program in
            changed(program) { $0.days[1].slots.append($0.days[0].slots[0]) }
        },
        UpdateRefusal(name: "a slot whose exercise is not stored") { program in
            changed(program) { $0.days[1].slots[2].exerciseID = Fixture.unknownExercise }
        },
        UpdateRefusal(name: "another id, held by no program", expected: duplicate(S2Kit.programID(77))) { program in
            try copy(program, id: S2Kit.programID(77))
        },
        UpdateRefusal(
            name: "another id, program 2's, with program 1's rows",
            expected: duplicate(UpdateKit.two)
        ) { program in
            try copy(program, id: UpdateKit.two)
        },
        UpdateRefusal(name: "program 2 as the fixture builds it", expected: duplicate(UpdateKit.two)) { _ in
            try Fixture.program(2)
        }
    ]

    static let valueRefusals: [UpdateRefusal] = [
        UpdateRefusal(name: "a program name holding U+0000") { program in
            changed(program) { $0.name = "Block\u{0}one" }
        },
        UpdateRefusal(name: "a day tag holding U+0000") { program in
            changed(program) { $0.days[1].tag = "\u{0}" }
        },
        UpdateRefusal(name: "one week only, which Program.init refuses") { program in
            changed(program) { $0.weeks = [$0.weeks[0]] }
        },
        UpdateRefusal(name: "a schedule naming a day the program lacks") { program in
            changed(program) { $0.weeks[1].schedule[.sunday] = S2Kit.dayID(999) }
        },
        UpdateRefusal(name: "week indices with a gap") { program in
            changed(program) { $0.weeks[2].index = 7 }
        },
        UpdateRefusal(name: "a slot of 99 sets, which Slot.init refuses") { program in
            changed(program) { $0.days[0].slots[1].sets = 99 }
        },
        UpdateRefusal(name: "a start load that is no whole number of 10⁻⁷ g") { program in
            changed(program) { $0.days[0].slots[0].startLoad = Weight(grams: Decimal(1) / 1_000_000_000) }
        },
        UpdateRefusal(
            name: "a change that throws once it has its result",
            expected: "\(UpdateKit.Thrown(code: 7))"
        ) { program in
            _ = changed(program) { $0.name = "Computed" }
            throw UpdateKit.Thrown(code: 7)
        }
    ]

    static let all = identityRefusals + valueRefusals

    static func duplicate(_ id: ProgramID) -> String {
        "\(RepositoryError.duplicateIdentifier("program \(ColumnCodec.text(id))"))"
    }
}
