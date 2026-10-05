#if DEBUG
    import Foundation
    import LedgerDomain

    /// How a concurrent script is judged (`concurrentScriptViolation(seed:on:)`): the five rules of
    /// `WorkoutSessionClientContract+ConcurrentScripts.swift`, each as a function of the history, which is a
    /// stream opened before the first call and read to the end, and of what the calls returned and threw.
    extension WorkoutSessionClientContract {
        /// What the rules make of `step` when the workout stands as `live`.
        static func ruling(on step: Step, standing live: WorkoutState?) -> (outcome: Outcome, published: Update?) {
            var model = Model(standing: live)
            return model.perform(step)
        }

        /// Rules 1 to 3: `history`, a stream from before the first call, against the calls made.
        static func concurrentHistoryIssue(_ history: [Update], calls: [Call]) -> String? {
            guard history.first == Update(state: nil) else {
                return "the history starts with \(brief(history.first)), expected no workout"
            }
            var unpublished = calls
            for (index, update) in history.enumerated().dropFirst() {
                let standing = history[index - 1].live
                let made = unpublished.firstIndex { call in
                    let ruled = ruling(on: call.step, standing: standing)
                    return ruled.published == update && ruled.outcome == call.outcome
                }
                guard let made else {
                    return "update \(index), \(brief(update)), does not follow from the one before it, "
                        + "\(brief(history[index - 1])), by a call not yet published that ended as the rules say"
                }
                unpublished.remove(at: made)
            }
            let stray = unpublished.first { call in
                !history.contains { ruling(on: call.step, standing: $0.live) == (call.outcome, nil) }
            }
            return stray.map { "\($0.step) \($0.outcome) and published nothing, which the rules allow nowhere" }
        }

        /// The stream that joins `history` after update `index`: the workout as it stood, without haptics,
        /// then every later update.
        static func suffix(of history: [Update], after index: Int) -> [Update] {
            [Update(state: history[index].live)] + history[(index + 1)...]
        }

        /// Rule 4, for one stream opened in flight and read to the end.
        static func lateStreamIssue(_ heard: [Update], in history: [Update]) -> String? {
            guard !history.indices.contains(where: { suffix(of: history, after: $0) == heard }) else {
                return nil
            }
            return "a stream opened in flight is no suffix of the history: it starts with \(brief(heard.first)) "
                + "and holds \(heard.count) updates of the history's \(history.count)"
        }

        /// Rule 5: the acting subscriber's stream is the history from its beginning; and from the update
        /// that told it of a workout on, `current()` and its own call are what the history says.
        static func reactionIssue(_ reaction: Reaction, in history: [Update]) -> String? {
            guard let call = reaction.call, let current = reaction.current,
                  reaction.heard == Array(history.prefix(reaction.heard.count))
            else {
                return "the acting subscriber heard \(reaction.heard.map(brief)), which is not how the history "
                    + "begins, or was never told of a workout"
            }
            let later = history[(reaction.heard.count - 1)...]
            guard later.contains(where: { ($0.live.map { .state($0) } ?? .done) == current }) else {
                return "current() on the update telling of a workout \(current), which the history never says "
                    + "from update \(later.startIndex) on"
            }
            let published = later.dropFirst().contains { $0.state != nil && $0.state == call.outcome.state }
            let unpublished = later.contains { ruling(on: call.step, standing: $0.live) == (call.outcome, nil) }
            return published || unpublished ? nil : "the acting subscriber's \(call.step) \(call.outcome), "
                + "which fits no point of the history from update \(later.startIndex) on"
        }
    }
#endif
