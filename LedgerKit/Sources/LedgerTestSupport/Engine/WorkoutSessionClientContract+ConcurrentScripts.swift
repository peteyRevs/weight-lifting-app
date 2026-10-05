#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes

    /// Seeded scripts whose calls are made at once (F10 S2 criterion 11): the general form of the clauses
    /// whose calls overlap. Those run pairs of call kinds chosen by hand; a script runs starts, applies,
    /// ends and subscriptions from several tasks, with a subscriber that acts on what it is told, and judges
    /// what came of them as one history, whatever order the scheduler chose (`concurrentHistoryIssue`):
    ///
    /// 1. every update follows from the one before it by exactly one call that succeeded: it is what the
    ///    rules (`Model`) publish for that call on that state, haptics included, and the call returned what
    ///    the rules say;
    /// 2. every call that succeeded is published once, and nothing else is published;
    /// 3. every other call was refused or ignored as the rules allow at some point of the history;
    /// 4. a stream opened in flight is a suffix of the history: it starts with a state that was published,
    ///    without haptics, and then misses no update and repeats none;
    /// 5. the subscriber that acts on the update telling it of a workout finds, from that update on, what
    ///    the history says.
    ///
    /// The seed fixes the calls; the scheduler fixes their order. Every call that changes a workout changes
    /// it in a way no other call does (a set, a weight, a date of its own), so an update names its call.
    ///
    /// Inside `#if DEBUG`, like the sequential scripts: they draw from `LedgerFakes`' `SplitMix64`.
    public extension WorkoutSessionClientContract {
        /// One thing a task of a concurrent script does.
        enum Action: Sendable, CustomStringConvertible {
            case call(Step)
            /// Opens a stream, which is read once every task has ended.
            case open

            public var description: String {
                switch self {
                case let .call(step): step.description
                case .open: "updates()"
                }
            }
        }

        /// What `concurrentScriptViolation(seed:on:)` runs.
        struct ConcurrentScript: Sendable, CustomStringConvertible {
            /// A start made before the tasks begin, in about half the seeds: the tasks then meet a workout.
            public let opening: Step?
            /// Each task makes its actions in order and gives way after each one; the tasks run at once.
            public let tasks: [[Action]]

            public var description: String {
                "\(opening.map(\.description) ?? "no opening") then \(tasks.map { $0.map(\.description) })"
            }
        }

        /// The concurrent script of `seed`, which the seed alone decides (testing-strategy §3 rule 5): six
        /// tasks of six actions. When nothing opens it, the first task starts with a start, so a workout is
        /// live at some point of every script.
        static func concurrentScript(seed: UInt64) -> ConcurrentScript {
            var writer = ConcurrentWriter(random: SplitMix64(seed: seed))
            let opening: Step? = seed.isMultiple(of: 2) ? .start(writer.snapshot()) : nil
            var tasks = (0 ..< 6).map { _ in (0 ..< 6).map { _ in writer.action() } }
            if opening == nil {
                tasks[0][0] = .call(.start(writer.snapshot()))
            }
            return ConcurrentScript(opening: opening, tasks: tasks)
        }

        /// Runs `concurrentScript(seed:)` on `client`, a fresh one, and judges it as one history. `nil` when
        /// the five rules hold, else the first thing that broke one.
        ///
        /// A client that never tells an open stream of a live workout, or never publishes the last change,
        /// keeps this waiting for the suite's time limit, as it does a clause.
        static func concurrentScriptViolation(seed: UInt64, on client: Client) async throws -> String? {
            let script = concurrentScript(seed: seed)
            var early = await Subscriber(client)
            let acting = await client.updates()
            var calls: [Call] = []
            if let opening = script.opening {
                await calls.append(Call(step: opening, outcome: outcome(of: opening, on: client)))
            }
            let (runs, reaction) = await withTaskGroup(of: Reaction.self) { group in
                group.addTask { await react(to: acting, on: client) }
                let runs = await run(script.tasks, on: client)
                return await (runs, group.next() ?? Reaction())
            }
            calls += runs.flatMap(\.calls) + [reaction.call].compactMap(\.self)
            let current = try await client.current()
            let mark = try await markEnd(of: client)
            let history = await early.updates(before: mark)
            var streams: [[Update]] = []
            for stream in runs.flatMap(\.streams) {
                var late = Subscriber(stream)
                await streams.append(late.updates(before: mark))
            }
            return ContractCheck.first(
                concurrentHistoryIssue(history, calls: calls),
                expectUpdates([Update(state: current)], [Update(state: history.last?.live)], "current() at the end"),
                streams.lazy.compactMap { lateStreamIssue($0, in: history) }.first,
                reactionIssue(reaction, in: history)
            ).map { "\($0); the script: \(script)" }
        }
    }

    extension WorkoutSessionClientContract {
        /// A call a script made and how it ended.
        struct Call: Sendable {
            let step: Step
            let outcome: Outcome
        }

        /// What one task of a script did: its calls in order, and the streams it opened.
        struct Run: Sendable {
            var calls: [Call] = []
            var streams: [AsyncStream<Update>] = []
        }

        /// The subscriber that acts on what it is told, on a stream opened before the first call: the
        /// updates it read up to the first that showed a workout, what `current()` answered then, and the
        /// set it logged in that workout.
        struct Reaction: Sendable {
            var heard: [Update] = []
            /// `current()` as an outcome: the workout, or `.done` for none.
            var current: Outcome?
            var call: Call?
        }

        /// Runs the tasks at once: each makes its actions in order and gives way after each one.
        static func run(_ tasks: [[Action]], on client: Client) async -> [Run] {
            await withTaskGroup(of: Run.self) { group in
                for actions in tasks {
                    group.addTask {
                        var run = Run()
                        for action in actions {
                            switch action {
                            case let .call(step):
                                await run.calls.append(Call(step: step, outcome: outcome(of: step, on: client)))
                            case .open:
                                await run.streams.append(client.updates())
                            }
                            await Task.yield()
                        }
                        return run
                    }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
        }

        /// Reads `stream` until an update shows a live workout, then does what a screen does: it reads
        /// `current()` and logs the workout's first set, while the script's tasks are still calling.
        static func react(to stream: AsyncStream<Update>, on client: Client) async -> Reaction {
            var reaction = Reaction()
            for await update in stream {
                reaction.heard.append(update)
                guard let first = update.live?.exercises.first?.sets.first else {
                    continue
                }
                do {
                    reaction.current = try await client.current().map { .state($0) } ?? .done
                } catch {
                    reaction.current = .threw("\(error)")
                }
                let log = Step.apply(.setLogged(
                    exerciseIndex: 0,
                    setID: first.id,
                    weight: .pounds(135),
                    reps: Reps(clamping: 5),
                    doneAt: at(30)
                ))
                reaction.call = await Call(step: log, outcome: outcome(of: log, on: client))
                break
            }
            return reaction
        }
    }

    /// Writes a concurrent script action by action. Nothing it writes depends on what is live when the call
    /// is made: that is the scheduler's choice.
    private struct ConcurrentWriter {
        typealias Contract = WorkoutSessionClientContract

        var random: SplitMix64
        /// Counts the values no two calls may share: workouts, added sets, weights and dates.
        var unique = 0

        /// The next workout's snapshot: the five solo exercises or the superset pair, auto rest on or off.
        mutating func snapshot() -> WorkoutState {
            unique += 1
            return EventBuilders.session(
                unique.isMultiple(of: 2) ? EventBuilders.supersetExercises : EventBuilders.seedExercises,
                id: WorkoutID(EventBuilders.uuid(0xF400 + unique)),
                autoRest: Bool.random(using: &random),
                startedAt: Contract.at(Double(unique))
            )
        }

        mutating func action() -> Contract.Action {
            unique += 1
            let moment = Contract.at(Double(600 + unique))
            let exercise = Int.random(in: 0 ... 1, using: &random)
            switch Int.random(in: 0 ..< 20, using: &random) {
            case 0 ..< 3:
                return .call(.start(snapshot()))
            case 3 ..< 10:
                let id = SetID(EventBuilders.uuid(0xC0000 + unique))
                let added = LoggedSet(id: id, weight: .pounds(45), reps: .one, kind: .added)
                return .call(.apply(.setAdded(exerciseIndex: exercise, set: added)))
            case 10, 11:
                let weight = Weight.pounds(Decimal(5 * (200 + unique)))
                return .call(.apply(.allSetsRepeated(exerciseIndex: exercise, weight: weight, reps: .one)))
            case 12:
                return .call(.apply(.restStarted(endsAt: moment, total: .seconds(90))))
            case 13, 14:
                return .call(.finish(endedAt: moment))
            case 15:
                return .call(.discard(endedAt: moment))
            case 16, 17:
                return .open
            default:
                return .call(refused())
            }
        }

        /// A call that must be refused or ignored whatever is live: a snapshot the engine would not start,
        /// an end at a date that is not finite, a second `started`.
        private mutating func refused() -> Contract.Step {
            switch Int.random(in: 0 ..< 4, using: &random) {
            case 0:
                var ended = snapshot()
                ended.phase = .finished
                ended.endedAt = Contract.at(1)
                return .start(ended)
            case 1:
                return .finish(endedAt: Contract.never)
            case 2:
                return .discard(endedAt: Contract.never)
            default:
                return .apply(.started(snapshot()))
            }
        }
    }
#endif
