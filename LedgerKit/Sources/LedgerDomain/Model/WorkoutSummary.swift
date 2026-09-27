import Foundation

/// The finished-workout receipt (spec §6.1 "Finished summary / receipt", rule 31).
public struct WorkoutSummary: Hashable, Codable, Sendable {
    public let workoutID: WorkoutID
    public let elapsed: Duration
    public let doneSets: Int
    public let totalSets: Int
    public let volume: Volume
    public let prs: [PersonalRecord]
    public let rows: [ReceiptRow]

    public init(
        workoutID: WorkoutID,
        elapsed: Duration,
        doneSets: Int,
        totalSets: Int,
        volume: Volume,
        prs: [PersonalRecord],
        rows: [ReceiptRow]
    ) {
        self.workoutID = workoutID
        self.elapsed = elapsed
        self.doneSets = doneSets
        self.totalSets = totalSets
        self.volume = volume
        self.prs = prs
        self.rows = rows
    }
}

/// One exercise on the receipt (rule 30).
public struct ReceiptRow: Hashable, Codable, Sendable {
    public let name: String
    /// The prescription before " · ": "5 × 5 @ 185 lb".
    public let target: String
    /// One chip per run of identical done sets: ["4 × 185×5", "185×4"], or ["—"] when none
    /// were done (spec §6.1 `actual[]`; the receipt renders each entry as its own chip).
    public let actual: [String]

    public init(name: String, target: String, actual: [String]) {
        self.name = name
        self.target = target
        self.actual = actual
    }

    /// Rule 30: target from the exercise's snapshot targets; actual run-length-groups the done
    /// sets in row order — "{n} × {w}×{r}" when n > 1, "{w}×{r}" for a single set, "—" if none.
    public init(exercise: WorkoutExercise, units: Units) {
        var runs: [(text: String, count: Int)] = []
        for set in exercise.sets where set.isDone {
            let text = "\(set.weight.formatted(in: units))×\(set.reps.value)"
            if let last = runs.last, last.text == text {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((text, 1))
            }
        }
        self.init(
            name: exercise.name,
            target: TargetText.scheme(
                sets: exercise.targetSets,
                reps: exercise.targetReps,
                load: exercise.targetLoad,
                units: units
            ),
            actual: runs.isEmpty ? ["—"] : runs.map { $0.count > 1 ? "\($0.count) × \($0.text)" : $0.text }
        )
    }
}
