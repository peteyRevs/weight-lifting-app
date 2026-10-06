@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5 adversarial round 2: the absolute edits (criterion 12), the strip of a program with no training day
/// (criterion 13) and the rename action (criterion 14). Programs come from `AdvProgram.random` for seeds 201
/// to 260; what a cell becomes is the tester's own cycle (`AdvScreen.next`), never `nextInCycle`.
@Suite("Adversarial F11 S5 · absolute edits, no training day, rename", .tags(.feature))
nonisolated struct ProgramAbsoluteAdversarialTests {
    static let seeds: [UInt64] = Array(201 ... 260)

    /// `program` rebuilt through `Program.init` is the same program: the Domain accepts it.
    static func isValid(_ program: Program) -> Bool {
        let rebuilt = try? Program(
            id: program.id, name: program.name, startDate: program.startDate, weeks: program.weeks,
            days: program.days, goal: program.goal, daysPerWeek: program.daysPerWeek, isActive: program.isActive
        )
        return rebuilt == program
    }

    /// A seeded program whose first slot has recorded misses, so an edit that wrote them would show.
    static func program(seed: UInt64) throws -> (program: Program, exercises: [ExerciseID: Exercise]) {
        var made = try AdvProgram.random(seed: seed)
        if let day = made.program.days.firstIndex(where: { !$0.slots.isEmpty }) {
            made.program.days[day].slots[0].misses = [0, 1]
        }
        return made
    }

    @Test(
        "A cell's action applied twice gives what one application gives: the tester's next of the cycle",
        arguments: seeds
    )
    func cellAction_appliedTwice_isOneApplication(seed: UInt64) throws {
        let made = try Self.program(seed: seed)
        var found: [String] = []
        for place in made.program.weeks.indices {
            let input = AdvProgram.input(made.program, exercises: made.exercises, weekStart: .saturday, week: place)
            for cell in ProgramPresentation.make(input).week.cells {
                guard let action = cell.action else {
                    continue
                }
                var wanted = made.program
                wanted.weeks[place].schedule[cell.weekday] = AdvScreen.next(
                    made.program,
                    place: place,
                    weekday: cell.weekday
                )?.id
                let once = AdvStore.apply(action, to: input, fresh: 1).input
                let twice = AdvStore.apply(action, to: once, fresh: 2).input
                if once.program != wanted || twice.program != wanted || !Self.isValid(once.program) {
                    found.append("week \(place) \(cell.weekday)")
                }
            }
        }
        #expect(found.isEmpty, "seed \(seed): \(found.prefix(4))")
    }

    @Test("The deload switch applied twice gives what one application gives: the other state", arguments: seeds)
    func deloadSwitch_appliedTwice_isOneApplication(seed: UInt64) throws {
        let made = try Self.program(seed: seed)
        var found: [String] = []
        for place in made.program.weeks.indices {
            let input = AdvProgram.input(made.program, exercises: made.exercises, week: place)
            let toggle = ProgramPresentation.make(input).week.deload
            var wanted = made.program
            wanted.weeks[place].isDeload = !made.program.weeks[place].isDeload
            let once = AdvStore.apply(toggle.action, to: input, fresh: 1).input
            let twice = AdvStore.apply(toggle.action, to: once, fresh: 2).input
            let after = ProgramPresentation.make(twice).week.deload
            let held = once.program == wanted && twice.program == wanted
            if !held || after.isOn == toggle.isOn || after.action == toggle.action {
                found.append("week \(place)")
            }
        }
        #expect(found.isEmpty, "seed \(seed): \(found.prefix(4))")
    }

    @Test("A cell's action applied to a program that changed meanwhile does what it names, or nothing")
    func cellAction_onAChangedProgram_isSafe() throws {
        let screen = try AdvProgram.seed(week: 7)
        let cells = ProgramPresentation.make(screen).week.cells
        let tuesday = try #require(cells.first { $0.weekday == .tuesday }?.action)
        let friday = try #require(cells.first { $0.weekday == .friday }?.action)
        let upperA = screen.program.days[0].id
        #expect(tuesday == .edit(.setSchedule(week: 7, weekday: .tuesday, day: upperA), notice: nil))
        #expect(friday == .edit(.setSchedule(week: 7, weekday: .friday, day: screen.program.days[3].id), notice: nil))

        var stored = screen
        stored.program = ProgramEditing.deleteDay(screen.program, day: upperA)
        let deleted = AdvStore.apply(tuesday, to: stored, fresh: 1).input.program
        let untouched = deleted == stored.program && Self.isValid(deleted)
        #expect(untouched, "the day it names is gone: nothing changes, and no entry dangles")

        stored.program = ProgramEditing.addDay(screen.program, id: DayTemplateID(Fixtures.uuid(91)), name: "New day")
        let added = AdvStore.apply(friday, to: stored, fresh: 2).input.program
        #expect(added.weeks[7].schedule[.friday] == screen.program.days[3].id, "Lower B, as the cell promised")
        #expect(Self.isValid(added))

        stored.program = try ProgramEditing.removeLastWeek(screen.program, loggedWeeks: [])
        let removed = AdvStore.apply(tuesday, to: stored, fresh: 3).input.program
        let shorter = removed == stored.program && removed.weeks.count == 7
        #expect(shorter, "the week it names is gone: nothing changes")

        let toggle = ProgramPresentation.make(screen).week.deload.action
        #expect(toggle == .edit(.setDeload(false, week: 7)))
        let gone = AdvStore.apply(toggle, to: stored, fresh: 4).input.program == stored.program
        #expect(gone, "a deload of a week that is gone changes nothing")
        stored.program = ProgramEditing.toggleDeload(screen.program, week: 7)
        let already = AdvStore.apply(toggle, to: stored, fresh: 5).input.program == stored.program
        #expect(already, "the week was switched off meanwhile: it stays off")
    }

    @Test("nextInCycle is rest, first day … last day, rest, from every state, for no day to six", arguments: 0 ... 6)
    func nextInCycle_everyState_isTheTestersCycle(dayCount: Int) throws {
        let days = (0 ..< dayCount).map { AdvProgram.day($0) }
        let program = try AdvProgram.program(weeks: 2, days: days)
        let ids = days.map(\.id)
        #expect(ProgramEditing.nextInCycle(after: nil, in: program) == ids.first)
        for (place, id) in ids.enumerated() {
            let wanted = place + 1 < ids.count ? ids[place + 1] : nil
            #expect(ProgramEditing.nextInCycle(after: id, in: program) == wanted, "after day \(place) of \(dayCount)")
        }
        let stranger = DayTemplateID(Fixtures.uuid(99999))
        #expect(ProgramEditing.nextInCycle(after: stranger, in: program) == ids.first, "a day not held counts as rest")
        var walked: [DayTemplateID?] = []
        var current: DayTemplateID?
        for _ in 0 ... dayCount {
            current = ProgramEditing.nextInCycle(after: current, in: program)
            walked.append(current)
        }
        #expect(walked == ids.map(Optional.some) + [nil])
    }
}

nonisolated extension ProgramAbsoluteAdversarialTests {
    @Test(
        "setSchedule and setDeload are total, change one thing, and leave a program the Domain accepts",
        arguments: seeds
    )
    func absoluteEdits_areTotalAndValid(seed: UInt64) throws {
        let program = try Self.program(seed: seed).program
        var rng = SplitMix64(seed: seed &* 104_729)
        var found: [String] = []
        let stranger = DayTemplateID(Fixtures.uuid(99999))
        for week in [Int.min, -1, program.weeks.count, 1000, Int.max] {
            let same = ProgramEditing
                .setSchedule(program, week: week, weekday: .monday, day: program.days.first?.id) == program
                && ProgramEditing.setSchedule(program, week: week, weekday: .monday, day: nil) == program
                && ProgramEditing.setDeload(program, true, week: week) == program
                && ProgramEditing.setDeload(program, false, week: week) == program
            found += same ? [] : ["week \(week) changed the program"]
        }
        for _ in 0 ..< 20 {
            let week = Int.random(in: program.weeks.indices, using: &rng)
            let weekday = Weekday.allCases.randomElement(using: &rng) ?? .monday
            let day = Bool.random(using: &rng) ? program.days.randomElement(using: &rng)?.id : nil
            var wanted = program
            wanted.weeks[week].schedule[weekday] = day
            let set = ProgramEditing.setSchedule(program, week: week, weekday: weekday, day: day)
            let again = ProgramEditing.setSchedule(set, week: week, weekday: weekday, day: day)
            let unknown = ProgramEditing.setSchedule(program, week: week, weekday: weekday, day: stranger)
            let flag = Bool.random(using: &rng)
            wanted.weeks[week].isDeload = flag
            let both = ProgramEditing.setDeload(ProgramEditing.setDeload(set, flag, week: week), flag, week: week)
            let good = again == set && unknown == program && both == wanted && Self.isValid(both) && both
                .days == program.days
            found += good ? [] : ["week \(week) \(weekday) day \(day == nil ? "rest" : "held") flag \(flag)"]
        }
        #expect(found.isEmpty, "seed \(seed): \(found.prefix(4))")
    }

    @Test("cycleSchedule and toggleDeload still give the tester's cycle and the other state", arguments: seeds)
    func relativeEdits_stillAgreeWithTheAbsoluteOnes(seed: UInt64) throws {
        let program = try Self.program(seed: seed).program
        var found: [String] = []
        for week in program.weeks.indices {
            for weekday in Weekday.allCases {
                var wanted = program
                wanted.weeks[week].schedule[weekday] = AdvScreen.next(program, place: week, weekday: weekday)?.id
                if ProgramEditing.cycleSchedule(program, week: week, weekday: weekday) != wanted {
                    found.append("cycle week \(week) \(weekday)")
                }
            }
            var flipped = program
            flipped.weeks[week].isDeload.toggle()
            found += ProgramEditing.toggleDeload(program, week: week) == flipped ? [] : ["toggle week \(week)"]
        }
        let outside = ProgramEditing.cycleSchedule(program, week: program.weeks.count, weekday: .monday) == program
            && ProgramEditing.toggleDeload(program, week: -1) == program
        #expect(outside, "seed \(seed): a week not held changed the program")
        #expect(found.isEmpty, "seed \(seed): \(found.prefix(4))")
    }

    @Test("With no training day the strip offers nothing in any state, and everything else still works", arguments: [
        2, 3, 9
    ])
    func noTrainingDay_everyState_theStripOffersNothing(weeks: Int) throws {
        var program = try AdvProgram.program(weeks: weeks, days: [AdvProgram.day(1)], deloads: [
            0,
            weeks - 1
        ]) { week, weekday in
            (week + weekday.rawValue).isMultiple(of: 2) ? 0 : nil
        }
        program.days = []
        var found: [String] = []
        let notices: [ProgramBuilderNotice?] = [
            nil,
            .minimumTwoWeeks,
            .weekHasLoggedSessions(weekNumber: weeks),
            .dayHasNoExercises
        ]
        for selected in -1 ... weeks {
            for (index, start) in Weekday.allCases.enumerated() {
                for emptied in try [program, AdvProgram.program(weeks: weeks, days: [])] {
                    let input = AdvProgram.input(
                        emptied, weekStart: start, week: selected, logged: index.isMultiple(of: 2) ? [weeks - 1] : [],
                        notice: notices[index % 4]
                    )
                    let week = ProgramPresentation.make(input).week
                    let offersNothing = week.hint == nil && week.cells.count == 7 && week.cells.allSatisfy {
                        $0.action == nil && $0.spokenHint == nil && $0.isRest && $0.label == "REST"
                            && $0.spokenValue == "Rest" && $0.spokenLabel == AdvScreen.weekdayNames[$0.weekday]
                    }
                    found += offersNothing ? [] : ["week \(selected), start \(start): the strip offers something"]
                    found += AdvScreen.differences(input).map { "week \(selected), start \(start): \($0)" }
                }
            }
        }
        #expect(found.isEmpty, "\(found.prefix(4))")
    }

    @Test("The first training day brings the strip back: seven actions, both hints, and the empty day's notice")
    func noTrainingDay_thenOneIsAdded_theStripReturns() throws {
        var input = try AdvProgram.input(AdvProgram.program(weeks: 2, days: []), week: 1)
        let add = try #require(ProgramPresentation.make(input).days.addDay.action)
        input = AdvStore.apply(add, to: input, fresh: 1).input
        let week = ProgramPresentation.make(input).week
        let day = try #require(input.program.days.first?.id)
        #expect(week.hint == "Tap to assign")
        #expect(week.cells.map(\.spokenHint) == Array(repeating: "Double-tap to assign", count: 7))
        #expect(week.cells.map(\.action) == week.cells.map {
            .edit(.setSchedule(week: 1, weekday: $0.weekday, day: day), notice: .dayHasNoExercises)
        })
    }

    @Test(
        "rename is one edit of the typed text: blank changes nothing, control characters go, a long name stays",
        arguments: [
            ("", "Upper / Lower"), ("   ", "Upper / Lower"), ("\n\t\u{0}", "Upper / Lower"), (
                "\u{7}\u{1B}",
                "Upper / Lower"
            ),
            ("  Push Pull  ", "Push Pull"), ("Pu\u{0}sh\tPu\nll\r", "PushPull"), ("a\u{85}b", "ab"),
            ("日本語 ブロック", "日本語 ブロック"), ("Block 👨‍👩‍👧‍👦", "Block 👨‍👩‍👧‍👦"), ("%@ %lld", "%@ %lld")
        ]
    )
    func rename_typedText_isCleanedOnce(typed: String, stored: String) throws {
        var input = try AdvProgram.seed()
        input.notice = .minimumTwoWeeks
        let action = ProgramBuilderAction.rename(typed)
        #expect(action == .edit(.renameProgram(typed), notice: nil), "the text as typed, and no notice")
        let step = AdvStore.apply(action, to: input, fresh: 1)
        #expect(step.edits == 1)
        #expect(ProgramPresentation.make(step.input).header.name == stored)
        var wanted = input.program
        wanted.name = stored
        let onlyTheName = step.input.program == wanted
        #expect(onlyTheName)
        let again = AdvStore.apply(action, to: step.input, fresh: 2).input.program == wanted
        #expect(again, "a rename sent twice is a rename")
    }

    @Test("A name of twenty thousand characters is stored whole and drawn whole")
    func rename_longText_isStoredWhole() throws {
        let input = try AdvProgram.seed()
        let long = String(repeating: "Ledger block ", count: 1600) + "x"
        let after = AdvStore.apply(.rename("  " + long + "\n"), to: input, fresh: 1).input
        let whole = ProgramPresentation.make(after).header.name == long && Self.isValid(after.program)
        #expect(whole, "\(after.program.name.count) of \(long.count) characters")
    }
}
