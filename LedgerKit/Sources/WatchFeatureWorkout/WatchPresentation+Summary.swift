import Foundation
import LedgerDomain

/// What the summary draws once the workout is saved (spec §4.3 "Watch — summary").
nonisolated struct WatchSummaryModel: Equatable, Sendable {
    /// "WORKOUT DONE".
    let title: String
    /// "m:ss", frozen at the workout's end, over "ELAPSED".
    let elapsed: String
    let elapsedCaption: String
    /// "18/20", over "SETS".
    let sets: String
    let setsCaption: String
    /// "24,180", over "LB MOVED" / "KG MOVED".
    let volume: String
    let volumeCaption: String
    /// The workout's average heart rate from Health, "138", or "—" while Health has not answered; over "AVG BPM".
    let averageHeartRate: String
    let averageHeartRateCaption: String
    /// The records the workout set, "2", over "NEW PR"; orange while `hasRecords`.
    let records: String
    let recordsCaption: String
    let hasRecords: Bool
    /// "Done", which returns to the screen before a workout.
    let done: String
}

nonisolated extension WatchPresentation {
    /// The summary of the finished `state`: the phone's receipt tiles (`WorkoutEngine.summary`, as FeatureHistory
    /// and FeatureWorkout read it), with the time frozen at `endedAt`, the volume in the workout's unit with
    /// thousands separators, and the counts in the lifter's digits. The average heart rate is the saved Health
    /// workout's (`HealthWorkoutRecord.avgHeartRate`), "—" without a record or without an average in it.
    static func summary(
        _ state: WorkoutState,
        records: [PersonalRecord],
        health: HealthWorkoutRecord?,
        locale: Locale
    ) -> WatchSummaryModel {
        let summary = WorkoutEngine.summary(state, prs: records)
        let digits = IntegerFormatStyle<Int>(locale: locale)
        return WatchSummaryModel(
            title: WatchWorkoutCopy.workoutDone,
            elapsed: ClockText.elapsed(summary.elapsed),
            elapsedCaption: WatchWorkoutCopy.elapsedCaption,
            sets: WatchWorkoutCopy.setsRatio(
                digits.format(summary.doneSets), of: digits.format(summary.totalSets), locale: locale
            ),
            setsCaption: WatchWorkoutCopy.setsCaption,
            volume: summary.volume.formatted(in: state.units),
            volumeCaption: WatchWorkoutCopy.movedCaption(state.units),
            averageHeartRate: health?.avgHeartRate.map(digits.format) ?? WatchWorkoutCopy.noHeartRate,
            averageHeartRateCaption: WatchWorkoutCopy.averageHeartRateCaption,
            records: digits.format(summary.prs.count),
            recordsCaption: WatchWorkoutCopy.newRecordsCaption,
            hasRecords: !summary.prs.isEmpty,
            done: WatchWorkoutCopy.done
        )
    }
}
