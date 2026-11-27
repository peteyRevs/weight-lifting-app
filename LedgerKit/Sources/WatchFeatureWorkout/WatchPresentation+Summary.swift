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
    /// What VoiceOver reads for each tile, one phrase each: "45 minutes, 30 seconds elapsed", "12 of 15 sets
    /// logged", "11,100 pounds moved", "Average heart rate, 138 beats per minute", "2 new personal records".
    let spoken: Spoken

    struct Spoken: Equatable, Sendable {
        let elapsed: String
        let sets: String
        let volume: String
        let averageHeartRate: String
        let records: String
    }
}

nonisolated extension WatchPresentation {
    /// The summary of the finished `state`: the phone's receipt tiles (`WorkoutEngine.summary`, as FeatureHistory
    /// and FeatureWorkout read it), with the time frozen at `endedAt`, the volume in the workout's unit with
    /// thousands separators, and the counts in the lifter's digits; VoiceOver reads each tile as one phrase. The
    /// average heart rate is the saved Health workout's (`HealthWorkoutRecord.avgHeartRate`), "—" without a record
    /// or without an average in it.
    static func summary(
        _ state: WorkoutState,
        records: [PersonalRecord],
        health: HealthWorkoutRecord?,
        locale: Locale
    ) -> WatchSummaryModel {
        let summary = WorkoutEngine.summary(state, prs: records)
        let digits = IntegerFormatStyle<Int>(locale: locale)
        let volume = summary.volume.formatted(in: state.units)
        let time = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes, .seconds], width: .wide)
        return WatchSummaryModel(
            title: WatchWorkoutCopy.workoutDone,
            elapsed: ClockText.elapsed(summary.elapsed),
            elapsedCaption: WatchWorkoutCopy.elapsedCaption,
            sets: WatchWorkoutCopy.setsRatio(
                digits.format(summary.doneSets), of: digits.format(summary.totalSets), locale: locale
            ),
            setsCaption: WatchWorkoutCopy.setsCaption,
            volume: volume,
            volumeCaption: WatchWorkoutCopy.movedCaption(state.units),
            averageHeartRate: health?.avgHeartRate.map(digits.format) ?? WatchWorkoutCopy.noHeartRate,
            averageHeartRateCaption: WatchWorkoutCopy.averageHeartRateCaption,
            records: digits.format(summary.prs.count),
            recordsCaption: WatchWorkoutCopy.newRecordsCaption,
            hasRecords: !summary.prs.isEmpty,
            done: WatchWorkoutCopy.done,
            spoken: WatchSummaryModel.Spoken(
                elapsed: WatchWorkoutCopy.elapsedSpoken(time.locale(locale).format(summary.elapsed), locale: locale),
                sets: WatchWorkoutCopy.setsLogged(
                    done: digits.format(summary.doneSets), of: summary.totalSets, locale: locale
                ),
                volume: WatchWorkoutCopy.movedSpoken(volume, units: state.units, locale: locale),
                averageHeartRate: health?.avgHeartRate
                    .map { WatchWorkoutCopy.averageHeartRateSpoken($0, locale: locale) }
                    ?? WatchWorkoutCopy.noAverageHeartRate,
                records: WatchWorkoutCopy.newRecordsSpoken(summary.prs.count, locale: locale)
            )
        )
    }
}
