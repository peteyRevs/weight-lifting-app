import Foundation
@testable import LedgerDomain
import Testing

/// F08 S1, G2 round 1: criterion 9 and its limits. The same inputs and id sequence give an equal block; ids,
/// the catalog's order and the start date change only what they name.
@Suite("Adversarial F08 S1 · determinism of the generator", .tags(.domain, .property))
struct TemplatesDeterminismAdversarialTests {
    typealias Brief = BriefTemplates

    static let seeds = PropertySeed.all

    /// A block with its ids taken out: days by position, slots by exercise.
    static func shape(_ program: Program) -> [String] {
        let position = Dictionary(zip(program.days.map(\.id), program.days.indices)) { first, _ in first }
        let header = [
            program.name, program.startDate.description, program.goal?.rawValue ?? "nil",
            program.daysPerWeek.map(String.init) ?? "nil", String(program.isActive)
        ].joined(separator: "|")
        let weeks: [String] = program.weeks.map { week in
            let entries: [String] = week.schedule.sorted { $0.key < $1.key }.map { entry in
                let day = position[entry.value].map(String.init) ?? "?"
                return "\(entry.key.rawValue):\(day)"
            }
            return "week \(week.index) deload \(week.isDeload) " + entries.joined(separator: ",")
        }
        var days: [String] = []
        for day in program.days {
            days.append("day \(day.name)|\(day.tag)")
            days += day.slots.map(line)
        }
        return [header] + weeks + days
    }

    /// Every field of `slot` but its id.
    static func line(_ slot: Slot) -> String {
        let load: String = slot.startLoad.map { "\($0.grams)" } ?? "nil"
        let step: String = slot.step.map { "\($0.grams)" } ?? "nil"
        let scheme = "\(slot.sets) \(slot.reps) \(slot.repsHi) \(slot.rpe.value) \(slot.rest.seconds)"
        let flags = "\(slot.isSupersetWithPrevious) \(slot.dropSets) \(slot.misses.sorted())"
        return "\(slot.exerciseID.rawValue.uuidString) \(scheme) \(slot.progression.rawValue) \(load) \(step) \(flags)"
    }

    static func randomCase(using random: inout SeededGenerator) -> Brief.Case {
        Brief.Case.all[Int.random(in: 0 ..< Brief.Case.all.count, using: &random)]
    }

    @Test("Criterion 9: the same request, catalog, id and id sequence give equal blocks", arguments: Brief.Case.all)
    func sameInputs_giveEqualPrograms(_ input: Brief.Case) throws {
        let first = try Brief.program(input)
        let second = try Brief.program(input)
        #expect(first == second, "\(input)")
        #expect(first.hashValue == second.hashValue, "\(input)")
    }

    @Test(
        "Ids are drawn as documented: the eight weeks, then each day followed by its slots, and no more",
        arguments: Brief.Case.pounds
    )
    func ids_areDrawnInTheDocumentedOrder(_ input: Brief.Case) throws {
        var drawn = 0
        let program = try ProgramTemplates
            .program(Brief.request(input), catalog: Brief.catalog(), id: Brief.programID) {
                drawn += 1
                return Fixtures.uuid(drawn)
            }
        #expect(program.weeks.map(\.id.rawValue) == (1 ... 8).map(Fixtures.uuid), "\(input)")
        var next = 9
        for day in program.days {
            #expect(day.id.rawValue == Fixtures.uuid(next), "\(input): \(day.name)")
            #expect(day.slots.map(\.id.rawValue) == day.slots.indices.map { Fixtures.uuid(next + 1 + $0) }, "\(input)")
            next += 1 + day.slots.count
        }
        #expect(drawn == next - 1, "\(input): \(drawn) ids drawn for \(next - 1) used")
        #expect(input.days != .four || drawn == 28, "the 4-day split draws 28 ids")
    }

    @Test("Any id sequence changes ids only: the block is otherwise the same", arguments: seeds)
    func randomIDs_changeOnlyIDs(seed: PropertySeed) throws {
        var random = seed.generator
        let input = Self.randomCase(using: &random)
        let baseline = try Brief.program(input)
        let program = try ProgramTemplates.program(
            Brief.request(input),
            catalog: Brief.catalog(),
            id: ProgramID(UUID(uuid: Self.bytes(using: &random)))
        ) {
            UUID(uuid: Self.bytes(using: &random))
        }
        #expect(Self.shape(program) == Self.shape(baseline), "\(seed), \(input)")
        let slots = program.days.flatMap(\.slots)
        let ids = program.weeks.map(\.id.rawValue) + program.days.map(\.id.rawValue) + slots.map(\.id.rawValue)
        #expect(Set(ids).count == ids.count, "\(seed), \(input)")
    }

    static func bytes(using random: inout SeededGenerator) -> uuid_t {
        let high = random.next().bigEndian
        let low = random.next().bigEndian
        return withUnsafeBytes(of: (high, low)) { $0.load(as: uuid_t.self) }
    }

    @Test("The catalog's order does not matter: a shuffled catalog gives the same block", arguments: seeds)
    func shuffledCatalog_givesTheSameProgram(seed: PropertySeed) throws {
        var random = seed.generator
        let input = Self.randomCase(using: &random)
        let shuffled = try Brief.catalog().shuffled(using: &random)
        #expect(try Brief.program(input, catalog: shuffled) == Brief.program(input), "\(seed), \(input)")
    }
}

// MARK: - Start dates, odd id sources and the request

extension TemplatesDeterminismAdversarialTests {
    @Test("Any start date is recorded as given and changes nothing else", arguments: seeds)
    func randomStartDate_changesOnlyTheStart(seed: PropertySeed) throws {
        var random = seed.generator
        let input = Self.randomCase(using: &random)
        let year = Int.random(in: 1 ... 9999, using: &random)
        let month = Int.random(in: 1 ... 12, using: &random)
        let start = try #require(CivilDate(year: year, month: month, day: Int.random(in: 1 ... 28, using: &random)))
        var program = try Brief.program(input, startDate: start)
        #expect(program.startDate == start, "\(seed), \(input)")
        program.startDate = Brief.monday
        #expect(try program == Brief.program(input), "\(seed), \(input)")
    }

    @Test(
        "The edges of the calendar are start dates like any other",
        arguments: [(1, 1, 1), (9999, 12, 31), (2028, 2, 29), (2026, 12, 31), (2027, 1, 1), (1970, 1, 1)]
    )
    func edgeStartDates_areKept(year: Int, month: Int, day: Int) throws {
        let start = try #require(CivilDate(year: year, month: month, day: day))
        let input = Brief.Case(goal: .both, days: .four, units: .kg)
        let program = try Brief.program(input, startDate: start)
        #expect(program.startDate == start)
        #expect(try Adversarial.roundTrip(program) == program)
    }

    @Test(
        "An id source that repeats itself does not trap: the block has its shape, with every id the same",
        arguments: DaysPerWeek.allCases
    )
    func constantIDSource_doesNotTrap(_ days: DaysPerWeek) throws {
        let input = Brief.Case(goal: .consistency, days: days, units: .kg)
        let constant = Fixtures.uuid(5)
        let program = try ProgramTemplates
            .program(Brief.request(input), catalog: Brief.catalog(), id: Brief.programID) {
                constant
            }
        let baseline = try Brief.program(input)
        #expect(program.days.map(\.name) == baseline.days.map(\.name))
        #expect(program.days.map { $0.slots.map(Self.line) } == baseline.days.map { $0.slots.map(Self.line) })
        #expect(program.weeks.map(\.schedule.count) == baseline.weeks.map(\.schedule.count))
        #expect(Set(program.weeks.map(\.id.rawValue) + program.days.map(\.id.rawValue)) == [constant])
    }

    @Test("Sixty-four blocks written at once are the blocks written one at a time")
    func concurrentCalls_giveTheSameBlocks() async throws {
        let catalog = try Brief.catalog()
        let expected = try Brief.Case.all.map { try Brief.program($0) }
        let written = try await withThrowingTaskGroup(of: (Int, Program).self) { group in
            for index in 0 ..< 64 {
                group.addTask {
                    try (index, Brief.program(Brief.Case.all[index % 32], catalog: catalog))
                }
            }
            var programs: [Int: Program] = [:]
            for try await (index, program) in group {
                programs[index] = program
            }
            return programs
        }
        #expect(written.count == 64)
        #expect(written.allSatisfy { $0.value == expected[$0.key % 32] })
    }

    @Test("A request is its four fields: equal requests are equal, and each field tells two apart")
    func request_isAValue() {
        let request = Brief.request(Brief.Case(goal: .both, days: .four, units: .lb))
        var other = request
        #expect(other == request && other.hashValue == request.hashValue)
        other.goal = .strength
        #expect(other != request)
        other = request
        other.days = .five
        #expect(other != request)
        other = request
        other.units = .kg
        #expect(other != request)
        other = request
        other.startDate = Fixtures.civil(2026, 9, 21)
        #expect(other != request)
    }

    @Test("DaysPerWeek is 3, 4, 5, 6, in order, and codes as its number")
    func daysPerWeek_rawValues() throws {
        #expect(DaysPerWeek.allCases.map(\.rawValue) == [3, 4, 5, 6])
        #expect(try Fixtures.json(DaysPerWeek.allCases) == "[3,4,5,6]")
        #expect(DaysPerWeek(rawValue: 2) == nil && DaysPerWeek(rawValue: 7) == nil)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([DaysPerWeek].self, from: Data("[7]".utf8)) }
    }
}
