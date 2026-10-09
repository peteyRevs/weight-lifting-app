@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport

/// One thing that happens in a seeded sequence (G2, F10 S4): the lifter asks, answers a dialog or taps the
/// cover, or another hand changes the workout.
nonisolated enum AdversarialStep: Sendable {
    case start(Int), resume
    case resumeIt, replace, cancel, dismissAlert
    case minimize, finish, keepLifting, discard, dismissDiscardAlert
    case finishedElsewhere, discardedElsewhere, loggedElsewhere

    /// A step that may end the live workout.
    var mayEnd: Bool {
        switch self {
        case .replace, .discard, .finishedElsewhere, .discardedElsewhere: true
        default: false
        }
    }

    /// A step that may make a new workout live.
    var mayStart: Bool {
        switch self {
        case .start, .replace: true
        default: false
        }
    }

    /// Twenty lots: four starts, two each of replace, minimize, finish and discard, one of each other.
    private static let lots: [AdversarialStep] = [
        .start(0), .start(1), .start(2), .start(0), .resume, .resumeIt, .replace, .replace, .cancel,
        .dismissAlert, .minimize, .minimize, .finish, .finish, .keepLifting, .discard, .discard,
        .dismissDiscardAlert, .finishedElsewhere, .loggedElsewhere, .discardedElsewhere, .loggedElsewhere
    ]

    static func random(using generator: inout SplitMix64) -> AdversarialStep {
        lots[Int.random(in: 0 ..< lots.count, using: &generator)]
    }

    @MainActor
    func perform(on rig: AdversarialRig, in world: AdversarialWorld, tick: Int) async throws {
        world.clock.setValue(Fixtures.now.addingTimeInterval(Double(tick + 1) * 60))
        switch self {
        case .start, .resume, .resumeIt, .replace, .cancel, .dismissAlert:
            try await ask(rig, in: world)
        case .minimize: await rig.tap(.minimize)
        case .finish: await rig.tap(.finish)
        case .keepLifting: await rig.tap(.keepLifting)
        case .discard:
            // The button exists only in the finish dialog.
            if rig.store?.dialog == .finish {
                await rig.tap(.discard)
            }
        case .dismissDiscardAlert: await rig.tap(.dismissFailure)
        case .finishedElsewhere, .discardedElsewhere, .loggedElsewhere:
            try await changeElsewhere(in: world)
        }
    }

    /// The launcher's requests and the answers to its dialogs.
    @MainActor
    private func ask(_ rig: AdversarialRig, in world: AdversarialWorld) async throws {
        switch self {
        case let .start(day): await rig.start(world.source(day: day))
        case .resume: await rig.resume()
        case .resumeIt:
            if case .conflict = rig.phase {
                await rig.answer(.resumeLive)
            }
        case .cancel:
            if case .conflict = rig.phase {
                await rig.answer(.cancelConflict)
            }
        case .dismissAlert: await rig.answer(.dismissFailure)
        case .replace: try await replace(rig, in: world)
        default: break
        }
    }

    /// "Discard and start new". Mostly there is no dialog to answer, so this takes down what is up and asks
    /// for another day first; none of that touches a call a fault was put on, but the start's own reads.
    @MainActor
    private func replace(_ rig: AdversarialRig, in world: AdversarialWorld) async throws {
        if rig.phase == .cover {
            await rig.tap(.keepLifting)
            await rig.tap(.dismissFailure)
            await rig.tap(.minimize)
        }
        await rig.answer(.dismissFailure)
        if rig.phase == .idle, let live = try await world.live() {
            await rig.start(world.source(day: live.source == world.source(day: 2) ? 1 : 2))
        }
        if case let .conflict(source) = rig.phase {
            await rig.answer(.replaceLive(source))
        }
    }

    /// Another hand: a refusal (nothing live) is not this step's to report.
    @MainActor
    private func changeElsewhere(in world: AdversarialWorld) async throws {
        let now = world.clock.value
        switch self {
        case .finishedElsewhere: _ = try? await world.truth.finish(endedAt: now)
        case .discardedElsewhere: try? await world.truth.discard(endedAt: now)
        default:
            if let live = try await world.live(), let set = live.exercises.first?.sets.first {
                let logged = WorkoutEvent.setLogged(
                    exerciseIndex: 0,
                    setID: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    doneAt: now
                )
                _ = try? await world.truth.apply(logged)
            }
        }
    }
}
