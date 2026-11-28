import Foundation

/// What the phone tells the watch about the plan and the settings (F19; `updateApplicationContext`): small, sent
/// on every change, and only the latest one counts. It must encode to at most `CompanionCodec.contextLimit` bytes.
///
/// The watch's idle screen reads its own copy, never a live call (F18 §4.3). The full program travels separately,
/// as `CompanionFile.program`.
public struct CompanionContext: Hashable, Codable, Sendable {
    /// Rises with every context the phone sends, across launches. The watch applies a context only when its
    /// revision is above the one it holds (`supersedes(_:)`, criterion 2).
    public var revision: UInt64
    /// The active program, or nil when the lifter has none.
    public var programID: ProgramID?
    public var programName: String?
    /// The program's current week, 0-based, as `WeekCalendar` places today, and how many weeks it has.
    public var weekIndex: Int
    public var weekCount: Int
    public var isDeload: Bool
    /// The next scheduled day, today's if one is scheduled; nil without a program or a scheduled day.
    public var nextDay: NextDay?
    public var settings: WatchSettings
    /// The finished workouts whose records the phone has stored, so the watch can compact their logs (F05). The
    /// phone keeps this to the recent ones: a context listing thousands would pass the size limit.
    public var acknowledgedWorkoutIDs: [WorkoutID]

    public init(
        revision: UInt64,
        programID: ProgramID?,
        programName: String?,
        weekIndex: Int,
        weekCount: Int,
        isDeload: Bool,
        nextDay: NextDay?,
        settings: WatchSettings,
        acknowledgedWorkoutIDs: [WorkoutID]
    ) {
        self.revision = revision
        self.programID = programID
        self.programName = programName
        self.weekIndex = weekIndex
        self.weekCount = weekCount
        self.isDeload = isDeload
        self.nextDay = nextDay
        self.settings = settings
        self.acknowledgedWorkoutIDs = acknowledgedWorkoutIDs
    }

    /// Whether this context replaces `held`, the one the watch holds: only a higher revision does, so a context
    /// delivered late, or twice, changes nothing (criterion 2). Any context replaces none.
    public func supersedes(_ held: CompanionContext?) -> Bool {
        guard let held else {
            return true
        }
        return revision > held.revision
    }
}

/// The day the watch offers to start (spec §4.3, §5.1): enough for the idle screen without the program file.
public struct NextDay: Hashable, Codable, Sendable {
    public var dayTemplateID: DayTemplateID
    public var name: String
    public var tag: String
    public var weekday: Weekday
    public var exerciseCount: Int
    public var setCount: Int
    public var firstExerciseName: String?
    /// Whether the day is scheduled today, and whether a workout of it was already logged today.
    public var isToday: Bool
    public var isLoggedToday: Bool

    public init(
        dayTemplateID: DayTemplateID,
        name: String,
        tag: String,
        weekday: Weekday,
        exerciseCount: Int,
        setCount: Int,
        firstExerciseName: String?,
        isToday: Bool,
        isLoggedToday: Bool
    ) {
        self.dayTemplateID = dayTemplateID
        self.name = name
        self.tag = tag
        self.weekday = weekday
        self.exerciseCount = exerciseCount
        self.setCount = setCount
        self.firstExerciseName = firstExerciseName
        self.isToday = isToday
        self.isLoggedToday = isLoggedToday
    }
}

/// The settings the watch uses (criterion 10): the rest are the phone's alone.
public struct WatchSettings: Hashable, Codable, Sendable {
    public var units: Units
    public var defaultRest: RestDuration
    public var autoRest: Bool
    public var watchBuzz: Bool
    public var weekStart: Weekday

    public init(units: Units, defaultRest: RestDuration, autoRest: Bool, watchBuzz: Bool, weekStart: Weekday) {
        self.units = units
        self.defaultRest = defaultRest
        self.autoRest = autoRest
        self.watchBuzz = watchBuzz
        self.weekStart = weekStart
    }

    /// The subset of the phone's `settings`.
    public init(_ settings: Settings) {
        self.init(
            units: settings.units,
            defaultRest: settings.defaultRest,
            autoRest: settings.autoRest,
            watchBuzz: settings.watchBuzz,
            weekStart: settings.weekStart
        )
    }
}
