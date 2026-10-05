#if DEBUG
    import Foundation
    import LedgerDomain

    /// How a concurrent script is judged (`concurrentScriptViolation(seed:on:)`): the rules of
    /// `WorkoutSessionClientContract+ConcurrentScripts.swift` as functions of the history, which is a stream
    /// opened before the first call and read to the end, and of what each task did, in the order it did it.
    ///
    /// A point of the history is the index of an update: "at point 3" is after the fourth update and before
    /// the fifth. A call that published was made at the point before its update. Anything else a task did (a
    /// call that was refused or ignored, a stream it opened, a `current()` it read) was done at some point,
    /// and because a task does one thing after another, at no earlier point than what it did before.
    extension WorkoutSessionClientContract {
        /// One thing a task did that the history must explain.
        enum Deed: Sendable, CustomStringConvertible {
            case call(Call)
            /// `current()` and what it answered: the workout, or `.done` for none.
            case current(Outcome)
            /// A stream opened in flight, as it read to the end.
            case stream([Update])

            var description: String {
                switch self {
                case let .call(call): "\(call.step) \(call.outcome)"
                case let .current(answer): "current() \(answer)"
                case let .stream(heard): "a stream opened in flight, starting with \(brief(heard.first)),"
                }
            }

            /// Whether this was done at `point` of `history` without publishing anything.
            func fits(_ history: [Update], at point: Int) -> Bool {
                let standing = history[point].live
                switch self {
                case let .call(call):
                    return ruling(on: call.step, standing: standing) == (call.outcome, nil)
                case let .current(answer):
                    return (standing.map { .state($0) } ?? .done) == answer
                case let .stream(heard):
                    return [Update(state: standing)] + history[(point + 1)...] == heard
                }
            }
        }

        /// What the rules make of `step` when the workout stands as `live`.
        static func ruling(on step: Step, standing live: WorkoutState?) -> (outcome: Outcome, published: Update?) {
            var model = Model(standing: live)
            return model.perform(step)
        }

        /// Rules 1 to 5. `opening` was made before anything else, on a client with no workout; each of `tasks`
        /// is what one task did, in order; `acting` is the subscriber that acted on what it was told.
        static func concurrentHistoryIssue(
            _ history: [Update],
            opening: Call?,
            tasks: [[Deed]],
            acting: Reaction
        ) -> String? {
            guard history.first == Update(state: nil) else {
                return "the history starts with \(brief(history.first)), expected no workout"
            }
            // The opening call is judged against the first state alone: nothing else had been called.
            var explained = 0
            if let opening {
                let ruled = ruling(on: opening.step, standing: nil)
                let published = ruled.published.map { history.dropFirst().first == $0 } ?? true
                guard ruled.outcome == opening.outcome, published else {
                    return "the opening \(opening.step) \(opening.outcome), then \(brief(history.dropFirst().first)); "
                        + "expected \(ruled.outcome), then \(brief(ruled.published))"
                }
                explained = ruled.published == nil ? 0 : 1
            }
            guard let told = acting.heard.indices.last, let current = acting.current else {
                return "the acting subscriber was never told of a workout"
            }
            // The acting subscriber read `current()` and then made its calls, all after the update that told it.
            let acted: [Deed] = [.current(current)] + acting.calls.map { .call($0) }
            let sequences = tasks + [acted]
            let starts = tasks.map { _ in explained } + [max(told, explained)]
            var updates = Array(repeating: [Int: Int](), count: sequences.count)
            for index in history.indices.dropFirst(explained + 1) {
                guard let (sequence, deed) = publisher(of: index, in: history, among: sequences, updates) else {
                    return "update \(index), \(brief(history[index])), does not follow from the one before it, "
                        + "\(brief(history[index - 1])), by a call not yet published that ended as the rules say"
                }
                updates[sequence][deed] = index
            }
            return sequences.indices.lazy.compactMap { number in
                orderIssue(sequences[number], from: starts[number], published: updates[number], in: history)
            }.first
        }

        /// Rules 1 and 2: the call, by its task and its place in it, that made update `index`: one not yet
        /// matched to an update, for which the rules publish exactly that update on the state before it, and
        /// which returned what the rules say.
        static func publisher(
            of index: Int,
            in history: [Update],
            among sequences: [[Deed]],
            _ updates: [[Int: Int]]
        ) -> (sequence: Int, deed: Int)? {
            let standing = history[index - 1].live
            for (sequence, deeds) in sequences.enumerated() {
                for (number, deed) in deeds.enumerated() where updates[sequence][number] == nil {
                    guard case let .call(call) = deed else {
                        continue
                    }
                    let ruled = ruling(on: call.step, standing: standing)
                    if ruled.published == history[index], ruled.outcome == call.outcome {
                        return (sequence, number)
                    }
                }
            }
            return nil
        }

        /// Rules 3 to 5 for what one task did, in order, from point `start` on: a call that published stands
        /// at its update, after the point of what the task did before; anything else fits a point no earlier
        /// than that. The earliest such point is taken, which leaves the most room for what follows.
        static func orderIssue(
            _ deeds: [Deed],
            from start: Int,
            published: [Int: Int],
            in history: [Update]
        ) -> String? {
            var point = start
            for (number, deed) in deeds.enumerated() {
                if let update = published[number] {
                    guard update > point else {
                        return "\(deed) was published as update \(update), which is not after point \(point), "
                            + "where the same task's earlier call stands"
                    }
                    point = update
                } else if let fitting = history.indices.dropFirst(point).first(where: { deed.fits(history, at: $0) }) {
                    point = fitting
                } else {
                    return "\(deed) and published nothing, which the rules allow at no point of the history "
                        + "from \(point) on, where the same task's earlier call stands"
                }
            }
            return nil
        }
    }
#endif
